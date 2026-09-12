#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly input_builder="$script_dir/build-parakeet-test-app.sh"
readonly identity_tool="$script_dir/fleck-build-identity.py"
readonly identity_mode="${FLECK_BUILD_IDENTITY_MODE:-local}"
readonly lock_path="$build_root/.corrected-packaging.lock"
readonly receipt_name='BUILD-PROVENANCE.txt'
readonly input_manifest_name='INPUT-APP-MANIFEST.sha256.tsv'
readonly expected_bundle_identifier='com.harryjin.fleck'
readonly expected_executable='Fleck'
readonly expected_requirement='designated => identifier "com.harryjin.fleck"'
readonly identity_capture="$build_root/.corrected-build-identity.$$.json"

result_file=''
if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || "$1" != '--result-file' || -z "$2" ]]; then
    printf 'usage: %s [--result-file ABSOLUTE_PATH]\n' "${0##*/}" >&2
    exit 2
  fi
  result_file="$2"
fi

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != 'Darwin' ]]; then
  die 'corrected packaging requires macOS'
fi
if [[ "$(uname -m)" != 'arm64' ]]; then
  die 'corrected packaging requires an arm64 host'
fi
for tool in git plutil codesign lipo ditto unzip shasum find mktemp awk cmp grep sed sort stat swift; do
  tool_path="$(command -v "$tool" || true)"
  [[ -n "$tool_path" && -x "$tool_path" ]] || die "required tool is unavailable: $tool"
done

if [[ -L "$build_root" || ( -e "$build_root" && ! -d "$build_root" ) ]]; then
  die "build root is not a canonical directory: $build_root"
fi
if [[ ! -d "$build_root" ]]; then
  /bin/mkdir "$build_root" || die "could not create build root: $build_root"
fi
[[ ! -L "$build_root" && -d "$build_root" ]] \
  || die "build root is not a canonical directory: $build_root"
[[ "$(cd -- "$build_root" && pwd -P)" == "$build_root" ]] \
  || die "build root is not canonical: $build_root"
if [[ -n "$result_file" ]]; then
  "$identity_tool" validate-result-path --repo "$repo_root" --result-file "$result_file"
fi
[[ ! -L "$input_builder" && -f "$input_builder" && -x "$input_builder" ]] \
  || die "input builder is missing or unsafe: $input_builder"
[[ ! -L "$identity_tool" && -f "$identity_tool" && -x "$identity_tool" ]] \
  || die "build identity tool is missing or unsafe: $identity_tool"
[[ "$(/usr/bin/git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" == "$repo_root" ]] \
  || die 'script is not running from its owning Git worktree'
/usr/bin/git -C "$repo_root" ls-files --error-unmatch -- 'Scripts/build-parakeet-test-app.sh' \
  >/dev/null 2>&1 || die 'input builder is not tracked by this worktree'
/usr/bin/git -C "$repo_root" ls-files --error-unmatch -- 'Scripts/fleck-build-identity.py' \
  >/dev/null 2>&1 || die 'build identity tool is not tracked by this worktree'
readonly source_commit="$(/usr/bin/git -C "$repo_root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)"
readonly source_tree="$(/usr/bin/git -C "$repo_root" rev-parse --verify 'HEAD^{tree}' 2>/dev/null)"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die 'could not resolve a full source commit'
[[ "$source_tree" =~ ^[0-9a-f]{40}$ ]] || die 'could not resolve a full source tree'

verify_clean_source() {
  /usr/bin/git -C "$repo_root" diff --quiet --ignore-submodules -- \
    || die 'tracked source changes are present; commit them before packaging'
  /usr/bin/git -C "$repo_root" diff --cached --quiet --ignore-submodules -- \
    || die 'staged source changes are present; commit them before packaging'
  [[ -z "$(/usr/bin/git -C "$repo_root" status --porcelain=v1 \
    --untracked-files=all --ignore-submodules=none)" ]] \
    || die 'untracked files or dirty submodules are present; clean them before packaging'
  [[ "$(/usr/bin/git -C "$repo_root" rev-parse 'HEAD^{commit}')" == "$source_commit" ]] \
    || die 'source commit changed during the build/package operation'
  [[ "$(/usr/bin/git -C "$repo_root" rev-parse 'HEAD^{tree}')" == "$source_tree" ]] \
    || die 'source tree changed during the build/package operation'
}
verify_clean_source

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1/Contents/Info.plist" 2>/dev/null
}

forbidden_model_asset() {
  /usr/bin/find "$1" \( -type f -o -type d \) \( \
    -iname '*.mlmodel' -o -iname '*.mlpackage' -o -iname '*.mlmodelc' \
    -o -iname '*.safetensors' -o -iname '*.gguf' -o -iname '*.onnx' \
    -o -iname '*model.bin' -o -iname '*weight.bin' -o -iname '*weights.bin' \
    -o -iname 'coremldata.bin' \) -print -quit
}

exact_requirement() {
  /usr/bin/codesign -d -r- "$1" 2>&1 \
    | /usr/bin/sed -n 's/^designated => /designated => /p'
}

verify_app() {
  local app="$1"
  local expected_commit="$2"
  local actual_requirement
  local forbidden
  local executable

  [[ ! -L "$app" && -d "$app" ]] || die "app is missing or unsafe: $app"
  [[ -z "$(/usr/bin/find "$app" -type l -print -quit)" ]] || die "app contains a symlink: $app"
  [[ "$(plist_value "$app" CFBundleIdentifier)" == "$expected_bundle_identifier" ]] \
    || die "app has unexpected CFBundleIdentifier: $app"
  [[ "$(plist_value "$app" CFBundleExecutable)" == "$expected_executable" ]] \
    || die "app has unexpected CFBundleExecutable: $app"
  if [[ -n "$expected_commit" ]]; then
    [[ "$(plist_value "$app" CFBundleDisplayName)" == "$handoff_name" ]] \
      || die "staged app has unexpected CFBundleDisplayName: $app"
    [[ "$(plist_value "$app" CFBundleName)" == "$handoff_name" ]] \
      || die "staged app has unexpected CFBundleName: $app"
    [[ "$(plist_value "$app" FleckBuildLabel)" == "$build_label" ]] \
      || die "staged app has unexpected FleckBuildLabel: $app"
    [[ "$(plist_value "$app" FleckSourceCommit)" == "$expected_commit" ]] \
      || die "staged app has unexpected FleckSourceCommit: $app"
    [[ "$(plist_value "$app" FleckSourceTree)" == "$source_tree" ]] \
      || die "staged app has unexpected FleckSourceTree: $app"
  fi
  for executable in \
    "$app/Contents/MacOS/Fleck" \
    "$app/Contents/SharedSupport/fleck-agent" \
    "$app/Contents/SharedSupport/gemma-cleanup-helper"; do
    [[ ! -L "$executable" && -f "$executable" && -x "$executable" ]] \
      || die "required executable is missing or unsafe: $executable"
    [[ "$(/usr/bin/lipo -archs "$executable" 2>/dev/null)" == 'arm64' ]] \
      || die "required executable is not arm64-only: $executable"
  done
  forbidden="$(forbidden_model_asset "$app")"
  [[ -z "$forbidden" ]] || die "forbidden model asset found: $forbidden"
  /usr/bin/codesign --verify --deep --strict "$app" \
    || die "app failed strict/deep code-signature verification: $app"
  actual_requirement="$(exact_requirement "$app")"
  [[ "$actual_requirement" == "$expected_requirement" ]] \
    || die "app has unexpected designated requirement ($actual_requirement): $app"
}

write_tree_manifest() {
  local root="$1"
  local destination="$2"
  (
    cd -- "$root"
    /usr/bin/find . -print | LC_ALL=C /usr/bin/sort | while IFS= read -r relative; do
      if [[ -d "$relative" ]]; then
        printf 'd\t%s\t%s\n' "$(/usr/bin/stat -f '%Lp' "$relative")" "$relative"
      elif [[ -f "$relative" ]]; then
        printf 'f\t%s\t%s\t%s\n' \
          "$(/usr/bin/stat -f '%Lp' "$relative")" \
          "$(/usr/bin/shasum -a 256 "$relative" | /usr/bin/awk '{print $1}')" \
          "$relative"
      else
        printf 'error: unsupported manifest entry: %s\n' "$relative" >&2
        exit 1
      fi
    done
  ) > "$destination"
}

require_fixture_failpoint() {
  local value="$1"
  local name="$2"
  local canonical_tmp
  canonical_tmp="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
  [[ "$value" == '1' && "$repo_root" == "$canonical_tmp"/* \
    && "$(/bin/cat "$repo_root/.pre-astra-packager-test-fixture" 2>/dev/null || true)" == \
      'pre-astra-packager-fixture-v1' ]] \
    || die "$name test failpoint is unavailable outside its explicit temporary fixture"
}

lock_directory_created=0
lock_owner_temp=''
operation_root=''
publication_committed=0
publication_created=0
published_device=''
published_inode=''
result_identity=''
staged_publication=''
output_root=''
cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM

  if (( publication_created != 0 && publication_committed == 0 )) \
    && [[ -n "$output_root" && ! -L "$output_root" && -d "$output_root" \
      && "$output_root" == "$build_root"/Fleck\ *\ Build\ * \
      && "$(/usr/bin/stat -f '%d' "$output_root" 2>/dev/null || true)" == "$published_device" \
      && "$(/usr/bin/stat -f '%i' "$output_root" 2>/dev/null || true)" == "$published_inode" ]]; then
    /usr/bin/find "$output_root" -depth -delete || exit_code=1
  fi
  if [[ -n "$operation_root" && ! -L "$operation_root" && -d "$operation_root" \
    && "$operation_root" == "$build_root"/.corrected-packaging-operation.* ]]; then
    /usr/bin/find "$operation_root" -depth -delete || exit_code=1
  fi
  if [[ -n "$lock_owner_temp" && ! -L "$lock_owner_temp" && -f "$lock_owner_temp" \
    && "$lock_owner_temp" == "$build_root"/.corrected-packaging-lock-owner.* ]]; then
    /usr/bin/find "$lock_owner_temp" -maxdepth 0 -type f -delete || exit_code=1
  fi
  if (( lock_directory_created != 0 )); then
    if [[ -f "$lock_path/owner" && ! -L "$lock_path/owner" \
      && "$(/bin/cat "$lock_path/owner")" == "$source_commit:$$" ]]; then
      /usr/bin/find "$lock_path/owner" -maxdepth 0 -type f -delete || exit_code=1
    elif [[ -e "$lock_path/owner" || -L "$lock_path/owner" ]]; then
      printf 'error: refusing to release a lock not owned by this process: %s\n' "$lock_path" >&2
      exit_code=1
    fi
    if [[ ! -L "$lock_path" && -d "$lock_path" ]]; then
      /bin/rmdir "$lock_path" || exit_code=1
    else
      printf 'error: refusing to release an unsafe lock path: %s\n' "$lock_path" >&2
      exit_code=1
    fi
  fi
  if [[ -f "$identity_capture" && ! -L "$identity_capture" ]]; then
    "$identity_tool" release --capture "$identity_capture" || exit_code=1
    /usr/bin/find "$identity_capture" -maxdepth 0 -type f -delete || exit_code=1
  fi
  if (( exit_code != 0 )) && [[ -n "$result_identity" ]]; then
    "$identity_tool" remove-owned-result \
      --repo "$repo_root" \
      --result-file "$result_file" \
      --identity "$result_identity" || exit_code=1
  fi
  exit "$exit_code"
}
trap cleanup EXIT HUP INT TERM

lock_owner_temp="$(/usr/bin/mktemp "$build_root/.corrected-packaging-lock-owner.XXXXXX")"
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_LOCK_OWNER_WRITE:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_LOCK_OWNER_WRITE" 'lock-owner'
  die 'injected lock-owner creation failure'
fi
printf '%s\n' "$source_commit:$$" > "$lock_owner_temp" \
  || die 'could not create corrected-packaging lock owner'
if ! /bin/mkdir "$lock_path" 2>/dev/null; then
  die "another corrected build/package operation holds the lock: $lock_path"
fi
lock_directory_created=1
/bin/mv "$lock_owner_temp" "$lock_path/owner" || die 'could not install corrected-packaging lock owner'
lock_owner_temp=''
operation_root="$(/usr/bin/mktemp -d "$build_root/.corrected-packaging-operation.XXXXXX")"

identity_test_arguments=()
if [[ -n "${FLECK_BUILD_IDENTITY_TEST_ACCEPTED_ROOT:-}" \
  || -n "${FLECK_BUILD_IDENTITY_TEST_DATABASE:-}" ]]; then
  if [[ -z "${FLECK_BUILD_IDENTITY_TEST_ACCEPTED_ROOT:-}" \
    || -z "${FLECK_BUILD_IDENTITY_TEST_DATABASE:-}" ]]; then
    die 'build identity test root and database must be supplied together'
  fi
  if [[ "$(/bin/cat "$repo_root/.fleck-build-identity-test-fixture" 2>/dev/null || true)" \
    != 'fleck-build-identity-test-fixture-v1' ]]; then
    die 'build identity test injection is unavailable outside an explicit fixture'
  fi
  identity_test_arguments+=(
    --test-accepted-root "$FLECK_BUILD_IDENTITY_TEST_ACCEPTED_ROOT"
    --test-database "$FLECK_BUILD_IDENTITY_TEST_DATABASE"
  )
fi
"$identity_tool" begin \
  --repo "$repo_root" \
  --flavor corrected \
  --configuration Debug \
  --mode "$identity_mode" \
  --capture "$identity_capture" \
  "${identity_test_arguments[@]+"${identity_test_arguments[@]}"}"
readonly nested_identity_token="$(
  "$identity_tool" field --capture "$identity_capture" guardToken
)"
readonly handoff_name="$("$identity_tool" name --capture "$identity_capture")"
readonly app_name="$handoff_name.app"
readonly launcher_name="Launch $handoff_name.command"
readonly zip_name="$handoff_name-arm64.zip"
readonly build_label="$handoff_name"
output_root="$build_root/$handoff_name"
readonly output_root
if [[ -e "$output_root" || -L "$output_root" ]]; then
  die "refusing to overwrite existing corrected publication: $output_root"
fi

readonly input_result="$operation_root/parakeet-result.json"
if ! /usr/bin/env FLECK_BUILD_IDENTITY_NESTED_TOKEN="$nested_identity_token" \
  "$input_builder" --result-file "$input_result"; then
  die 'fresh input build failed'
fi
verify_clean_source
[[ ! -L "$input_result" && -f "$input_result" ]] \
  || die 'fresh input build succeeded without an immutable result'
if ! /usr/bin/python3 - "$input_result" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        value = json.load(handle)
except (OSError, UnicodeError, json.JSONDecodeError):
    sys.exit(1)
if set(value) != {"appPath", "buildID"} \
        or not all(isinstance(value[key], str) and value[key] for key in value):
    sys.exit(1)
PY
then
  die 'fresh input build result is malformed or has unexpected fields'
fi
readonly input_app="$(/usr/bin/plutil -extract appPath raw -o - "$input_result")"
readonly result_input_build_id="$(/usr/bin/plutil -extract buildID raw -o - "$input_result")"
[[ ! -L "$input_app" && -d "$input_app" ]] || die 'fresh build did not produce the input app'
[[ "$(cd -- "$input_app" && pwd -P)" == "$input_app" ]] || die 'fresh input app is not canonical'
input_app_label="${input_app##*/}"
input_app_label="${input_app_label%.app}"
[[ "${input_app%/*}" == "$build_root/parakeet-test" \
  && "${input_app##*/}" =~ ^Fleck\ ([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?)\ Build\ ([1-9][0-9]*)\.app$ ]] \
  || die 'fresh input result names an app outside the Parakeet publication root'
readonly input_product_version="${BASH_REMATCH[1]}"
readonly input_build_number="${BASH_REMATCH[4]}"
verify_app "$input_app" ''
[[ "$(plist_value "$input_app" CFBundleName)" == "$input_app_label" \
  && "$(plist_value "$input_app" CFBundleDisplayName)" == "$input_app_label" \
  && "$(plist_value "$input_app" FleckBuildLabel)" == "$input_app_label" \
  && "$(plist_value "$input_app" FleckVersion)" == "$input_product_version" \
  && "$(plist_value "$input_app" FleckBuildNumber)" == "$input_build_number" \
  && "$(plist_value "$input_app" FleckBuildFlavor)" == 'parakeet' ]] \
  || die 'fresh input app name and Parakeet identity metadata do not agree'
"$identity_tool" verify --source-only \
  --capture "$identity_capture" \
  --plist "$input_app/Contents/Info.plist"
readonly input_build_id="$(plist_value "$input_app" FleckBuildID)"
[[ "$result_input_build_id" == "$input_build_id" ]] \
  || die 'fresh input result build ID does not match the input app plist'

readonly input_manifest="$operation_root/input-app.manifest"
readonly input_manifest_after="$operation_root/input-app-after.manifest"
write_tree_manifest "$input_app" "$input_manifest"
readonly input_manifest_hash="$(/usr/bin/shasum -a 256 "$input_manifest" | /usr/bin/awk '{print $1}')"
"$identity_tool" augment \
  --capture "$identity_capture" \
  --input-build-id "$input_build_id" \
  --input-manifest-sha256 "$input_manifest_hash"

staged_publication="$operation_root/$handoff_name"
readonly staged_handoff="$staged_publication"
readonly staged_app="$staged_handoff/$app_name"
readonly staged_launcher="$staged_handoff/$launcher_name"
readonly staged_receipt="$staged_handoff/$receipt_name"
readonly staged_input_manifest="$staged_handoff/$input_manifest_name"
readonly staged_zip="$operation_root/$zip_name"
/bin/mkdir -p "$staged_handoff"
/bin/cp -p "$input_manifest" "$staged_input_manifest"
/bin/chmod 644 "$staged_input_manifest"
/usr/bin/ditto --norsrc "$input_app" "$staged_app"

readonly staged_plist="$staged_app/Contents/Info.plist"
for key in FleckBuildLabel FleckInputBuildID FleckInputManifestSHA256; do
  /usr/bin/plutil -remove "$key" "$staged_plist" >/dev/null 2>&1 || true
done
"$identity_tool" stamp \
  --capture "$identity_capture" \
  --plist "$staged_plist"

{
  printf 'Build label: %s\n' "$build_label"
  "$identity_tool" info \
    --capture "$identity_capture" \
    --bundle-identifier "$expected_bundle_identifier"
} > "$staged_receipt"
/bin/chmod 644 "$staged_receipt"
/bin/cat > "$staged_launcher" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
readonly script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
readonly app_path="$script_dir/__FLECK_VERSIONED_APP__.app"
if [[ -L "$app_path" || ! -d "$app_path" ]]; then
  printf 'error: adjacent Fleck app is missing or unsafe: %s\n' "$app_path" >&2
  exit 1
fi
readonly intended_executable="$app_path/Contents/MacOS/Fleck"
is_conflicting_fleck_gui() {
  local executable="$1"
  local bundle_path
  [[ "$executable" == */Contents/MacOS/Fleck ]] || return 1
  bundle_path="${executable%/Contents/MacOS/Fleck}"
  case "${bundle_path##*/}" in
    Fleck*.app) ;;
    *) return 1 ;;
  esac
  [[ "$executable" != "$intended_executable" ]]
}
inventory_file=''
remove_inventory() {
  [[ -n "$inventory_file" ]] || return 0
  if [[ -L "$inventory_file" || ! -f "$inventory_file" ]]; then
    printf 'error: refusing to remove unsafe Fleck process inventory: %s\n' \
      "$inventory_file" >&2
    inventory_file=''
    return 1
  fi
  if ! /usr/bin/find "$inventory_file" -maxdepth 0 -type f -delete; then
    printf 'error: could not remove Fleck process inventory: %s\n' "$inventory_file" >&2
    inventory_file=''
    return 1
  fi
  inventory_file=''
}
cleanup_launcher() {
  exit_code=$?
  trap - EXIT HUP INT TERM
  remove_inventory || exit_code=1
  exit "$exit_code"
}
trap cleanup_launcher EXIT HUP INT TERM
if ! inventory_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/fleck-corrected-launch.XXXXXX")"; then
  printf '%s\n' 'error: could not create secure Fleck process inventory' >&2
  exit 1
fi
capture_inventory() {
  if ! /bin/ps -x -o pid=,comm= > "$inventory_file"; then
    printf '%s\n' 'error: could not inspect running Fleck app processes; no app was opened' >&2
    return 1
  fi
}
retire_inventory() {
  while IFS= read -r process; do
    [[ "$process" =~ ^[[:space:]]*([0-9]+)[[:space:]](.*)$ ]] || continue
    pid="${BASH_REMATCH[1]}"
    executable="${BASH_REMATCH[2]}"
    if ! is_conflicting_fleck_gui "$executable"; then
      continue
    fi
    [[ "$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)" == "$executable" ]] || continue
    if ! /bin/kill -TERM "$pid" 2>/dev/null; then
      [[ "$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)" == "$executable" ]] \
        || continue
      printf 'error: could not ask conflicting Fleck app to exit: %s (pid %s)\n' \
        "$executable" "$pid" >&2
      return 1
    fi
    attempts=0
    while [[ "$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)" == "$executable" ]]; do
      if (( attempts == 20 )); then
        printf 'error: conflicting Fleck app did not exit after TERM: %s (pid %s); quit it manually and rerun this launcher\n' \
          "$executable" "$pid" >&2
        return 1
      fi
      /bin/sleep 0.1
      (( attempts += 1 ))
    done
  done < "$inventory_file"
}
for pass in 1 2; do
  capture_inventory
  retire_inventory
done
capture_inventory
while IFS= read -r process; do
  [[ "$process" =~ ^[[:space:]]*([0-9]+)[[:space:]](.*)$ ]] || continue
  pid="${BASH_REMATCH[1]}"
  executable="${BASH_REMATCH[2]}"
  if ! is_conflicting_fleck_gui "$executable"; then
    continue
  fi
  [[ "$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)" == "$executable" ]] || continue
  printf 'error: a conflicting Fleck app appeared during final launch verification: %s (pid %s); quit it manually and rerun this launcher\n' \
    "$executable" "$pid" >&2
  exit 1
done < "$inventory_file"
remove_inventory
trap - EXIT HUP INT TERM
exec /usr/bin/open "$app_path"
EOF
/usr/bin/sed -i '' "s/__FLECK_VERSIONED_APP__/$handoff_name/g" "$staged_launcher"
/bin/chmod 755 "$staged_launcher"

/usr/bin/codesign --force --sign - \
  --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
  "$staged_app"
verify_app "$staged_app" "$source_commit"
"$identity_tool" verify \
  --capture "$identity_capture" \
  --plist "$staged_app/Contents/Info.plist"
[[ "$(plist_value "$staged_app" FleckInputManifestSHA256)" == "$input_manifest_hash" ]] \
  || die 'staged app has unexpected FleckInputManifestSHA256'
/usr/bin/cmp -s "$input_manifest" "$staged_input_manifest" \
  || die 'published input manifest differs from the manifest used for provenance'
[[ "$(/usr/bin/shasum -a 256 "$staged_input_manifest" | /usr/bin/awk '{print $1}')" == \
  "$input_manifest_hash" ]] || die 'published input manifest has an unexpected digest'

readonly staged_handoff_manifest="$operation_root/staged-handoff.manifest"
readonly extracted_handoff_manifest="$operation_root/extracted-handoff.manifest"
write_tree_manifest "$staged_handoff" "$staged_handoff_manifest"
/usr/bin/ditto -c -k --norsrc --keepParent "$staged_handoff" "$staged_zip"
if /usr/bin/unzip -Z1 "$staged_zip" | /usr/bin/grep -Eq '(^|/)__MACOSX(/|$)'; then
  die 'ZIP contains an unexpected __MACOSX entry'
fi
[[ "$(/usr/bin/unzip -Z1 "$staged_zip" | /usr/bin/sed -n 's#/.*##p' | LC_ALL=C /usr/bin/sort -u)" == \
  "$handoff_name" ]] || die 'ZIP does not contain exactly the named top-level handoff folder'

readonly verification_root="$operation_root/verification"
/bin/mkdir "$verification_root"
/usr/bin/ditto -x -k "$staged_zip" "$verification_root"
readonly extracted_handoff="$verification_root/$handoff_name"
readonly extracted_app="$extracted_handoff/$app_name"
verify_app "$extracted_app" "$source_commit"
"$identity_tool" verify \
  --capture "$identity_capture" \
  --plist "$extracted_app/Contents/Info.plist"
/usr/bin/cmp -s "$input_manifest" "$extracted_handoff/$input_manifest_name" \
  || die 'extracted input manifest differs from the manifest used for provenance'
write_tree_manifest "$extracted_handoff" "$extracted_handoff_manifest"
/usr/bin/cmp -s "$staged_handoff_manifest" "$extracted_handoff_manifest" \
  || die 'complete extracted handoff differs from the staged handoff'

write_tree_manifest "$input_app" "$input_manifest_after"
/usr/bin/cmp -s "$input_manifest" "$input_manifest_after" \
  || die 'complete input app changed during packaging'
/bin/mv "$staged_zip" "$staged_handoff/$zip_name" \
  || die 'could not place the verified ZIP in the staged handoff'
readonly staged_publication_manifest="$operation_root/staged-publication.manifest"
readonly published_publication_manifest="$operation_root/published-publication.manifest"
write_tree_manifest "$staged_publication" "$staged_publication_manifest"
verify_clean_source
"$identity_tool" finish \
  --capture "$identity_capture" \
  --plist "$staged_app/Contents/Info.plist"
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK" \
    'final-source'
  die 'injected failure after final source check'
fi

if [[ -e "$output_root" || -L "$output_root" ]]; then
  die "corrected publication destination must remain unused: $output_root"
fi
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP" \
    'publication'
  die 'injected publication failure after publication backup'
fi
if [[ -n "${FLECK_PRE_ASTRA_TEST_LATE_PUBLICATION_COLLISION:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_LATE_PUBLICATION_COLLISION" \
    'late-publication-collision'
  /bin/mkdir "$output_root" || die 'could not create late publication collision fixture'
  printf '%s\n' 'late collision sentinel' > "$output_root/sentinel"
fi
published_device="$(/usr/bin/stat -f '%d' "$staged_publication")"
published_inode="$(/usr/bin/stat -f '%i' "$staged_publication")"
if ! /usr/bin/swift -e '
  import Darwin

  guard renamex_np(CommandLine.arguments[1], CommandLine.arguments[2], UInt32(RENAME_EXCL)) == 0 else {
    exit(1)
  }
' "$staged_publication" "$output_root"; then
  die 'could not atomically install the verified publication'
fi
publication_created=1
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP" \
    'publication-swap'
  die 'injected failure after publication swap'
fi

readonly published_app="$output_root/$app_name"
readonly published_launcher="$output_root/$launcher_name"
readonly published_zip="$output_root/$zip_name"
verify_app "$published_app" "$source_commit"
"$identity_tool" verify \
  --capture "$identity_capture" \
  --plist "$published_app/Contents/Info.plist"
write_tree_manifest "$output_root" "$published_publication_manifest"
/usr/bin/cmp -s "$staged_publication_manifest" "$published_publication_manifest" \
  || die 'complete published handoff differs from the verified staged publication'
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP" \
    'legacy-zip'
  die 'injected failure after legacy ZIP backup'
fi

if [[ -n "$result_file" ]]; then
  result_identity="$("$identity_tool" write-result \
    --capture "$identity_capture" \
    --app "$published_app" \
    --result-file "$result_file")"
fi
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_RESULT:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_RESULT" 'post-result'
  die 'injected failure after result publication'
fi

printf 'Packaged app: %s\n' "$published_app"
printf 'Packaged launcher: %s\n' "$published_launcher"
printf 'Packaged ZIP: %s\n' "$published_zip"
printf 'Source commit: %s\n' "$source_commit"
printf 'Source tree: %s\n' "$source_tree"
printf 'Input app manifest SHA-256: %s\n' "$input_manifest_hash"
printf 'Input build ID: %s\n' "$input_build_id"
printf 'Build ID: %s\n' "$(plist_value "$published_app" FleckBuildID)"
printf 'App executable SHA-256: %s\n' \
  "$(/usr/bin/shasum -a 256 "$published_app/Contents/MacOS/Fleck" | /usr/bin/awk '{print $1}')"
printf 'ZIP SHA-256: %s\n' "$(/usr/bin/shasum -a 256 "$published_zip" | /usr/bin/awk '{print $1}')"
publication_committed=1
