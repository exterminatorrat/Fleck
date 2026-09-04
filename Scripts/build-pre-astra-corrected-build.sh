#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly input_builder="$script_dir/build-parakeet-test-app.sh"
readonly input_app="$build_root/parakeet-test/Fleck.app"
readonly output_root="$build_root/pre-astra-corrected"
readonly legacy_zip="$build_root/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
readonly lock_path="$build_root/.pre-astra-corrected.lock"
readonly handoff_name='Fleck Pre-Astra Corrected Build'
readonly app_name="$handoff_name.app"
readonly launcher_name="Launch $handoff_name.command"
readonly receipt_name='BUILD-PROVENANCE.txt'
readonly input_manifest_name='INPUT-APP-MANIFEST.sha256.tsv'
readonly zip_name='Fleck-Pre-Astra-Corrected-Build-arm64.zip'
readonly expected_bundle_identifier='com.harryjin.fleck'
readonly expected_executable='Fleck'
readonly expected_requirement='designated => identifier "com.harryjin.fleck"'
readonly build_label='Pre-Astra Corrected Build'

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != 'Darwin' ]]; then
  die 'pre-Astra packaging requires macOS'
fi
if [[ "$(uname -m)" != 'arm64' ]]; then
  die 'pre-Astra packaging requires an arm64 host'
fi
for tool in git plutil codesign lipo ditto unzip shasum find mktemp awk cmp grep sed sort stat; do
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
[[ ! -L "$input_builder" && -f "$input_builder" && -x "$input_builder" ]] \
  || die "input builder is missing or unsafe: $input_builder"
[[ "$(/usr/bin/git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" == "$repo_root" ]] \
  || die 'script is not running from its owning Git worktree'
/usr/bin/git -C "$repo_root" ls-files --error-unmatch -- 'Scripts/build-parakeet-test-app.sh' \
  >/dev/null 2>&1 || die 'input builder is not tracked by this worktree'
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
previous_input=''
input_transaction_started=0
input_committed=0
publication_backup=''
legacy_zip_backup=''
publication_swap_started=0
publication_committed=0
staged_publication=''
cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM

  if (( publication_committed == 0 )); then
    if (( publication_swap_started != 0 )) && [[ -n "$staged_publication" \
      && ! -e "$staged_publication" && ( -e "$output_root" || -L "$output_root" ) ]]; then
      if [[ ! -L "$output_root" && -d "$output_root" \
        && "$(cd -- "$output_root" && pwd -P)" == "$output_root" ]]; then
        /usr/bin/find "$output_root" -depth -delete || exit_code=1
      else
        printf 'error: refusing to remove an unsafe failed publication: %s\n' "$output_root" >&2
        exit_code=1
      fi
    fi
    if [[ -n "$publication_backup" && ! -L "$publication_backup" \
      && -d "$publication_backup" ]]; then
      if [[ ! -e "$output_root" && ! -L "$output_root" ]]; then
        /bin/mv "$publication_backup" "$output_root" || exit_code=1
      else
        printf 'error: could not restore prior publication because its path is occupied: %s\n' \
          "$output_root" >&2
        exit_code=1
      fi
    fi
    if [[ -n "$legacy_zip_backup" && ! -L "$legacy_zip_backup" \
      && -f "$legacy_zip_backup" ]]; then
      if [[ ! -e "$legacy_zip" && ! -L "$legacy_zip" ]]; then
        /bin/mv "$legacy_zip_backup" "$legacy_zip" || exit_code=1
      else
        printf 'error: could not restore prior legacy ZIP because its path is occupied: %s\n' \
          "$legacy_zip" >&2
        exit_code=1
      fi
    fi
  fi
  if (( input_committed == 0 )) && { (( input_transaction_started != 0 )) \
    || [[ -n "$previous_input" && -d "$previous_input" ]]; }; then
    if [[ -L "$input_app" || -f "$input_app" ]]; then
      /usr/bin/find "$input_app" -maxdepth 0 \( -type f -o -type l \) -delete || exit_code=1
    elif [[ -d "$input_app" ]]; then
      /usr/bin/find "$input_app" -depth -delete || exit_code=1
    elif [[ -e "$input_app" ]]; then
      printf 'error: refusing to remove an unsupported failed input path: %s\n' "$input_app" >&2
      exit_code=1
    fi
    if [[ -n "$previous_input" && ! -L "$previous_input" && -d "$previous_input" ]]; then
      /bin/mkdir -p "$(dirname -- "$input_app")"
      /bin/mv "$previous_input" "$input_app" || exit_code=1
    fi
  fi
  if [[ -n "$operation_root" && ! -L "$operation_root" && -d "$operation_root" \
    && "$operation_root" == "$build_root"/.pre-astra-corrected-operation.* ]]; then
    /usr/bin/find "$operation_root" -depth -delete || exit_code=1
  fi
  if [[ -n "$lock_owner_temp" && ! -L "$lock_owner_temp" && -f "$lock_owner_temp" \
    && "$lock_owner_temp" == "$build_root"/.pre-astra-corrected-lock-owner.* ]]; then
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
  exit "$exit_code"
}
trap cleanup EXIT HUP INT TERM

lock_owner_temp="$(/usr/bin/mktemp "$build_root/.pre-astra-corrected-lock-owner.XXXXXX")"
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_LOCK_OWNER_WRITE:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_LOCK_OWNER_WRITE" 'lock-owner'
  die 'injected lock-owner creation failure'
fi
printf '%s\n' "$source_commit:$$" > "$lock_owner_temp" \
  || die 'could not create pre-Astra lock owner'
if ! /bin/mkdir "$lock_path" 2>/dev/null; then
  die "another pre-Astra build/package operation holds the lock: $lock_path"
fi
lock_directory_created=1
/bin/mv "$lock_owner_temp" "$lock_path/owner" || die 'could not install pre-Astra lock owner'
lock_owner_temp=''
operation_root="$(/usr/bin/mktemp -d "$build_root/.pre-astra-corrected-operation.XXXXXX")"

if [[ -e "$input_app" || -L "$input_app" ]]; then
  [[ ! -L "$input_app" && -d "$input_app" ]] || die "existing input app is unsafe: $input_app"
  [[ "$(cd -- "$input_app" && pwd -P)" == "$input_app" ]] || die "existing input app is not canonical: $input_app"
  previous_input="$operation_root/previous-input.app"
  /bin/mv "$input_app" "$previous_input"
fi

input_transaction_started=1
if ! "$input_builder"; then
  die 'fresh input build failed'
fi
verify_clean_source
[[ ! -L "$input_app" && -d "$input_app" ]] || die 'fresh build did not produce the input app'
[[ "$(cd -- "$input_app" && pwd -P)" == "$input_app" ]] || die 'fresh input app is not canonical'
verify_app "$input_app" ''

readonly input_manifest="$operation_root/input-app.manifest"
readonly input_manifest_after="$operation_root/input-app-after.manifest"
write_tree_manifest "$input_app" "$input_manifest"
readonly input_manifest_hash="$(/usr/bin/shasum -a 256 "$input_manifest" | /usr/bin/awk '{print $1}')"

staged_publication="$operation_root/publication"
readonly staged_handoff="$staged_publication/$handoff_name"
readonly staged_app="$staged_handoff/$app_name"
readonly staged_launcher="$staged_handoff/$launcher_name"
readonly staged_receipt="$staged_handoff/$receipt_name"
readonly staged_input_manifest="$staged_handoff/$input_manifest_name"
readonly staged_zip="$staged_publication/$zip_name"
/bin/mkdir -p "$staged_handoff"
/bin/cp -p "$input_manifest" "$staged_input_manifest"
/bin/chmod 644 "$staged_input_manifest"
/usr/bin/ditto --norsrc "$input_app" "$staged_app"

readonly staged_plist="$staged_app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleDisplayName -string "$handoff_name" "$staged_plist"
/usr/bin/plutil -replace CFBundleName -string "$handoff_name" "$staged_plist"
for key in FleckBuildLabel FleckSourceCommit FleckSourceTree FleckInputManifestSHA256; do
  /usr/bin/plutil -remove "$key" "$staged_plist" >/dev/null 2>&1 || true
done
/usr/bin/plutil -insert FleckBuildLabel -string "$build_label" "$staged_plist"
/usr/bin/plutil -insert FleckSourceCommit -string "$source_commit" "$staged_plist"
/usr/bin/plutil -insert FleckSourceTree -string "$source_tree" "$staged_plist"
/usr/bin/plutil -insert FleckInputManifestSHA256 -string "$input_manifest_hash" "$staged_plist"

{
  printf 'Build label: %s\n' "$build_label"
  printf 'Source commit: %s\n' "$source_commit"
  printf 'Source tree: %s\n' "$source_tree"
  printf 'Input app manifest SHA-256: %s\n' "$input_manifest_hash"
} > "$staged_receipt"
/bin/chmod 644 "$staged_receipt"
/bin/cat > "$staged_launcher" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
readonly script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
readonly app_path="$script_dir/Fleck Pre-Astra Corrected Build.app"
if [[ -L "$app_path" || ! -d "$app_path" ]]; then
  printf 'error: adjacent Fleck app is missing or unsafe: %s\n' "$app_path" >&2
  exit 1
fi
exec /usr/bin/open -n "$app_path"
EOF
/bin/chmod 755 "$staged_launcher"

/usr/bin/codesign --force --sign - \
  --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
  "$staged_app"
verify_app "$staged_app" "$source_commit"
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
/usr/bin/cmp -s "$input_manifest" "$extracted_handoff/$input_manifest_name" \
  || die 'extracted input manifest differs from the manifest used for provenance'
write_tree_manifest "$extracted_handoff" "$extracted_handoff_manifest"
/usr/bin/cmp -s "$staged_handoff_manifest" "$extracted_handoff_manifest" \
  || die 'complete extracted handoff differs from the staged handoff'

write_tree_manifest "$input_app" "$input_manifest_after"
/usr/bin/cmp -s "$input_manifest" "$input_manifest_after" \
  || die 'complete input app changed during packaging'
readonly staged_publication_manifest="$operation_root/staged-publication.manifest"
readonly published_publication_manifest="$operation_root/published-publication.manifest"
write_tree_manifest "$staged_publication" "$staged_publication_manifest"
verify_clean_source
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK" \
    'final-source'
  die 'injected failure after final source check'
fi

if [[ -L "$output_root" || ( -e "$output_root" && ! -d "$output_root" ) ]]; then
  die "publication root is unsafe: $output_root"
fi
if [[ -d "$output_root" && "$(cd -- "$output_root" && pwd -P)" != "$output_root" ]]; then
  die "publication root is not canonical: $output_root"
fi
if [[ -L "$legacy_zip" || ( -e "$legacy_zip" && ! -f "$legacy_zip" ) ]]; then
  die "legacy ZIP path is unsafe: $legacy_zip"
fi
if [[ -f "$legacy_zip" ]]; then
  legacy_zip_backup="$operation_root/previous-legacy.zip"
  /bin/mv "$legacy_zip" "$legacy_zip_backup"
fi
if [[ -d "$output_root" ]]; then
  publication_backup="$operation_root/previous-publication"
  /bin/mv "$output_root" "$publication_backup"
fi
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP" \
    'publication'
  die 'injected publication failure after publication backup'
fi
publication_swap_started=1
if ! /bin/mv "$staged_publication" "$output_root"; then
  die 'could not atomically install the verified publication'
fi
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP" \
    'publication-swap'
  die 'injected failure after publication swap'
fi

readonly published_app="$output_root/$handoff_name/$app_name"
readonly published_launcher="$output_root/$handoff_name/$launcher_name"
readonly published_zip="$output_root/$zip_name"
verify_app "$published_app" "$source_commit"
write_tree_manifest "$output_root" "$published_publication_manifest"
/usr/bin/cmp -s "$staged_publication_manifest" "$published_publication_manifest" \
  || die 'complete published handoff differs from the verified staged publication'
if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP:-}" ]]; then
  require_fixture_failpoint "$FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP" \
    'legacy-zip'
  die 'injected failure after legacy ZIP backup'
fi

printf 'Packaged app: %s\n' "$published_app"
printf 'Packaged launcher: %s\n' "$published_launcher"
printf 'Packaged ZIP: %s\n' "$published_zip"
printf 'Source commit: %s\n' "$source_commit"
printf 'Source tree: %s\n' "$source_tree"
printf 'Input app manifest SHA-256: %s\n' "$input_manifest_hash"
printf 'App executable SHA-256: %s\n' \
  "$(/usr/bin/shasum -a 256 "$published_app/Contents/MacOS/Fleck" | /usr/bin/awk '{print $1}')"
printf 'ZIP SHA-256: %s\n' "$(/usr/bin/shasum -a 256 "$published_zip" | /usr/bin/awk '{print $1}')"
input_committed=1 publication_committed=1
