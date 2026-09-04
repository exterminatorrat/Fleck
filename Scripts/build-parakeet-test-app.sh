#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly resolver="$script_dir/resolve-enhanced-candidate.sh"
readonly resolved="$repo_root/Package.resolved"
readonly gemma_cleanup_package="$repo_root/Tools/GemmaCleanupBenchmark/NativeRuntime"
readonly gemma_cleanup_package_manifest="$gemma_cleanup_package/Package.swift"
readonly gemma_cleanup_resolved="$gemma_cleanup_package/Package.resolved"
readonly info_plist="$repo_root/Sources/FleckApp/Info.plist"
readonly canonical_mark="$repo_root/website/public/fleck-mark.png"
readonly manifest="$repo_root/Sources/FleckApp/Resources/EnhancedModelManifest.json"
readonly notices="$repo_root/Sources/FleckApp/Resources/ThirdPartyNotices.md"
readonly gemma_cleanup_manifest="$repo_root/Sources/FleckApp/Resources/GemmaCleanupModelManifest.json"
readonly gemma_cleanup_notice="$repo_root/Sources/FleckApp/Resources/GemmaCleanupNotice.md"
readonly build_root="$repo_root/.build"
readonly output_root="$build_root/parakeet-test"
readonly app_destination="$output_root/Fleck.app"
readonly sibling_resource_output="$output_root/Fleck_FleckApp.bundle"
readonly expected_bundle_identifier="com.harryjin.fleck"
readonly lock_path="$build_root/.parakeet-test.lock"
readonly lock_owner_marker_name=".parakeet-owner"
readonly cleanup_marker_name=".parakeet-cleanup-owner"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'error: building the Parakeet test app requires macOS' >&2
  exit 2
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  printf '%s\n' 'error: building the Parakeet test app requires an arm64 host' >&2
  exit 2
fi
if ! xcode-select -p >/dev/null 2>&1 \
  || ! xcodebuild -version >/dev/null 2>&1; then
  printf '%s\n' \
    'error: building the Parakeet test app requires an active Xcode installation' \
    >&2
  exit 2
fi

readonly swift_path="$(xcrun --find swift)"
readonly xcodebuild_path="$(xcrun --find xcodebuild)"
readonly codesign_path="$(xcrun --find codesign)"
readonly lipo_path="$(xcrun --find lipo)"
readonly otool_path="$(xcrun --find otool)"
readonly install_name_tool_path="$(xcrun --find install_name_tool)"
readonly active_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
readonly deployment_target="14.0"
for required_tool in \
  "$resolver" "$swift_path" "$xcodebuild_path" "$codesign_path" "$lipo_path" "$otool_path" \
  "$install_name_tool_path"; do
  if [[ ! -x "$required_tool" ]]; then
    printf 'error: required Xcode tool is unavailable: %s\n' "$required_tool" >&2
    exit 2
  fi
done

for required_input in \
  "$resolved" "$info_plist" "$canonical_mark" "$manifest" "$notices" \
  "$gemma_cleanup_manifest" "$gemma_cleanup_notice"; do
  if [[ -L "$required_input" ]]; then
    printf 'error: required input must not be a symlink: %s\n' "$required_input" >&2
    exit 2
  fi
  if [[ ! -f "$required_input" ]]; then
    printf 'error: required input not found: %s\n' "$required_input" >&2
    exit 2
  fi
done
if [[ -L "$gemma_cleanup_package" || ! -d "$gemma_cleanup_package" ]]; then
  printf 'error: Gemma cleanup helper package is not a directory: %s\n' \
    "$gemma_cleanup_package" >&2
  exit 2
fi
for required_input in "$gemma_cleanup_package_manifest" "$gemma_cleanup_resolved"; do
  if [[ -L "$required_input" ]]; then
    printf 'error: required input must not be a symlink: %s\n' "$required_input" >&2
    exit 2
  fi
  if [[ ! -f "$required_input" ]]; then
    printf 'error: required input not found: %s\n' "$required_input" >&2
    exit 2
  fi
done

if [[ -L "$build_root" || ( -e "$build_root" && ! -d "$build_root" ) ]]; then
  printf 'error: repository build root is not a directory: %s\n' "$build_root" >&2
  exit 2
fi
/bin/mkdir -p "$build_root"
if [[ -L "$build_root" || ! -d "$build_root" ]]; then
  printf 'error: repository build root was substituted during setup: %s\n' "$build_root" >&2
  exit 1
fi
readonly canonical_build_root="$(cd -- "$build_root" && pwd -P)"
if [[ "$canonical_build_root" != "$build_root" ]]; then
  printf 'error: repository build root is not canonical: %s\n' "$build_root" >&2
  exit 1
fi
readonly requested_tmp_root="${TMPDIR:-/tmp}"
if [[ ! -d "$requested_tmp_root" ]]; then
  printf 'error: TMPDIR is not a directory: %s\n' "$requested_tmp_root" >&2
  exit 2
fi
readonly canonical_tmp_root="$(cd -- "$requested_tmp_root" && pwd -P)"
if [[ "$canonical_tmp_root" == "/" \
  || "$canonical_tmp_root" == "$repo_root" \
  || "$repo_root" == "$canonical_tmp_root"/* ]]; then
  printf 'error: TMPDIR is too broad or overlaps the repository: %s\n' \
    "$canonical_tmp_root" >&2
  exit 2
fi

validate_direct_child_directory() {
  local candidate="$1"
  local allowed_parent="$2"
  local label="$3"
  local canonical_candidate
  local relative
  if [[ -z "$candidate" || -L "$candidate" || ! -d "$candidate" ]]; then
    printf 'error: %s is not a non-symlink directory: %s\n' "$label" "$candidate" >&2
    return 1
  fi
  case "$candidate" in
    "$allowed_parent"/*) ;;
    *)
      printf 'error: %s is outside its allowed parent: %s\n' "$label" "$candidate" >&2
      return 1
      ;;
  esac
  relative="${candidate#"$allowed_parent"/}"
  if [[ -z "$relative" || "$relative" == */* ]]; then
    printf 'error: %s is not a direct child of its allowed parent: %s\n' \
      "$label" "$candidate" >&2
    return 1
  fi
  canonical_candidate="$(cd -- "$candidate" && pwd -P)"
  if [[ "$canonical_candidate" != "$candidate" ]]; then
    printf 'error: %s is not canonical: %s\n' "$label" "$candidate" >&2
    return 1
  fi
}

write_cleanup_marker() {
  local marker="$1"
  if [[ -e "$marker" || -L "$marker" ]]; then
    printf 'error: cleanup marker already exists: %s\n' "$marker" >&2
    return 1
  fi
  if ! (set -C; printf '%s\n' "$invocation_token" > "$marker"); then
    printf 'error: could not create cleanup marker: %s\n' "$marker" >&2
    return 1
  fi
}

validate_cleanup_target() {
  local candidate="$1"
  local allowed_parent="$2"
  local marker="$3"
  local label="$4"
  local marker_value
  if ! validate_direct_child_directory "$candidate" "$allowed_parent" "$label"; then
    return 1
  fi
  if [[ -z "$marker" || -L "$marker" || ! -f "$marker" ]]; then
    printf 'error: cleanup marker is missing or unsafe for %s: %s\n' \
      "$label" "$candidate" >&2
    return 1
  fi
  marker_value="$(/bin/cat "$marker")"
  if [[ "$marker_value" != "$invocation_token" ]]; then
    printf 'error: cleanup marker ownership mismatch for %s: %s\n' \
      "$label" "$candidate" >&2
    return 1
  fi
}

cleanup_owned_directory() {
  local candidate="$1"
  local allowed_parent="$2"
  local marker="$3"
  local label="$4"
  if [[ -z "$candidate" ]]; then
    return 0
  fi
  if ! validate_cleanup_target "$candidate" "$allowed_parent" "$marker" "$label"; then
    printf 'error: refusing cleanup of unowned or substituted %s: %s\n' \
      "$label" "$candidate" >&2
    return 1
  fi
  /usr/bin/find "$candidate" -depth -delete
}

scratch_parent=""
gemma_scratch_parent=""
staging_root=""
scratch_marker=""
gemma_scratch_marker=""
staging_marker=""
lock_owner_marker=""
lock_acquired=0
gemma_lock_backup=""
gemma_lock_backup_ready=0
readonly invocation_token="$(/usr/bin/uuidgen)"

validate_lock_owner() {
  local marker_value
  if [[ -L "$lock_path" || ! -d "$lock_path" ]]; then
    printf 'error: repository packager lock was substituted: %s\n' "$lock_path" >&2
    return 1
  fi
  if ! validate_direct_child_directory "$lock_path" "$canonical_build_root" "packager lock"; then
    return 1
  fi
  if [[ -z "$lock_owner_marker" || -L "$lock_owner_marker" \
    || ! -f "$lock_owner_marker" ]]; then
    printf 'error: repository packager lock owner marker is unsafe: %s\n' \
      "$lock_path" >&2
    return 1
  fi
  marker_value="$(/bin/cat "$lock_owner_marker")"
  if [[ "$marker_value" != "$invocation_token" ]]; then
    printf 'error: repository packager lock ownership mismatch: %s\n' \
      "$lock_path" >&2
    return 1
  fi
  if [[ "$(/usr/bin/find "$lock_path" -mindepth 1 -maxdepth 1 -print \
    | LC_ALL=C /usr/bin/sort)" != "$lock_owner_marker" ]]; then
    printf 'error: repository packager lock contains unexpected entries: %s\n' \
      "$lock_path" >&2
    return 1
  fi
}

release_lock() {
  if (( lock_acquired == 0 )); then
    return 0
  fi
  if ! validate_lock_owner; then
    printf '%s\n' 'error: refusing to remove a lock that is not demonstrably owned by this invocation' >&2
    return 1
  fi
  /bin/rm -f -- "$lock_owner_marker"
  if [[ -e "$lock_owner_marker" || -L "$lock_owner_marker" ]] \
    || ! /bin/rmdir "$lock_path"; then
    printf 'error: could not safely remove owned repository packager lock: %s\n' \
      "$lock_path" >&2
    return 1
  fi
  lock_acquired=0
}

cleanup() {
  local exit_code=$?
  local cleanup_status=0
  trap - EXIT HUP INT TERM
  if (( gemma_lock_backup_ready != 0 )); then
    if [[ -L "$gemma_cleanup_resolved" ]]; then
      /bin/rm -f -- "$gemma_cleanup_resolved"
    fi
    if ! /bin/cp -p "$gemma_lock_backup" "$gemma_cleanup_resolved" \
      || ! /usr/bin/cmp -s "$gemma_cleanup_resolved" "$gemma_lock_backup"; then
      printf '%s\n' 'error: could not restore NativeRuntime Package.resolved' >&2
      cleanup_status=1
    fi
  fi
  if [[ -n "$staging_root" && -e "$staging_root" ]]; then
    if ! cleanup_owned_directory "$staging_root" "$canonical_build_root" \
      "$staging_marker" 'staging directory'; then
      cleanup_status=1
    fi
  fi
  if [[ -n "$gemma_scratch_parent" && -e "$gemma_scratch_parent" ]]; then
    if ! cleanup_owned_directory "$gemma_scratch_parent" "$canonical_build_root" \
      "$gemma_scratch_marker" 'Gemma cleanup helper scratch directory'; then
      cleanup_status=1
    fi
  fi
  if [[ -n "$scratch_parent" && -e "$scratch_parent" ]]; then
    if ! cleanup_owned_directory "$scratch_parent" "$canonical_tmp_root" \
      "$scratch_marker" 'scratch directory'; then
      cleanup_status=1
    fi
  fi
  if ! release_lock; then
    cleanup_status=1
  fi
  if (( cleanup_status != 0 && exit_code == 0 )); then
    exit_code=1
  fi
  exit "$exit_code"
}

if [[ -L "$lock_path" || ( -e "$lock_path" && ! -d "$lock_path" ) ]]; then
  printf 'error: repository packager lock path is a symlink or non-directory: %s\n' \
    "$lock_path" >&2
  exit 1
fi
if ! /bin/mkdir "$lock_path" 2>/dev/null; then
  if [[ -L "$lock_path" || ! -d "$lock_path" ]]; then
    printf 'error: repository packager lock was substituted: %s\n' "$lock_path" >&2
  else
    printf 'error: another Parakeet test app packager is already running (lock: %s)\n' \
      "$lock_path" >&2
  fi
  exit 1
fi
lock_acquired=1
lock_owner_marker="$lock_path/$lock_owner_marker_name"
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if ! write_cleanup_marker "$lock_owner_marker"; then
  exit 1
fi
if ! validate_lock_owner; then
  exit 1
fi

if [[ -L "$output_root" || ( -e "$output_root" && ! -d "$output_root" ) ]]; then
  printf 'error: test app output root is not a directory: %s\n' "$output_root" >&2
  exit 2
fi
/bin/mkdir -p "$output_root"
if ! validate_direct_child_directory "$output_root" "$canonical_build_root" 'test app output root'; then
  exit 1
fi
if [[ -e "$app_destination" || -L "$app_destination" ]]; then
  printf 'error: refusing to overwrite existing test app: %s\n' "$app_destination" >&2
  exit 1
fi
if [[ -e "$sibling_resource_output" || -L "$sibling_resource_output" ]]; then
  printf 'error: refusing to use an existing sibling resource bundle: %s\n' \
    "$sibling_resource_output" >&2
  exit 1
fi

scratch_parent="$(mktemp -d "$canonical_tmp_root/fleck-parakeet-test-build.XXXXXX")"
scratch_marker="$scratch_parent/$cleanup_marker_name"
if ! validate_direct_child_directory "$scratch_parent" "$canonical_tmp_root" 'scratch directory' \
  || ! write_cleanup_marker "$scratch_marker"; then
  exit 1
fi
readonly candidate_scratch="$scratch_parent/build"
readonly lock_backup="$scratch_parent/Package.resolved"
readonly bin_marker="$scratch_parent/bin-path"
/bin/cp -p "$resolved" "$lock_backup"

"$resolver" "$candidate_scratch" /bin/sh -c '
  set -eu
  "$3" build -c debug --product Fleck \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$4" -Xlinker "$5" \
    --disable-automatic-resolution --skip-update --scratch-path "$1"
  "$3" build -c debug --product fleck-agent \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$4" -Xlinker "$5" \
    --disable-automatic-resolution --skip-update --scratch-path "$1"
  "$3" build -c debug --show-bin-path \
    --disable-automatic-resolution --skip-update --scratch-path "$1" >"$2"
' /bin/sh "$candidate_scratch" "$bin_marker" "$swift_path" \
  "$deployment_target" "$active_sdk_version"

if ! /usr/bin/cmp -s "$resolved" "$lock_backup"; then
  printf '%s\n' 'error: candidate build changed root Package.resolved' >&2
  exit 1
fi

readonly candidate_bin="$(/usr/bin/tail -n 1 "$bin_marker")"
readonly app_executable="$candidate_bin/Fleck"
readonly helper_executable="$candidate_bin/fleck-agent"
readonly resource_bundle="$candidate_bin/Fleck_FleckApp.bundle"
for build_input in "$app_executable" "$helper_executable" "$resource_bundle"; do
  if [[ -L "$build_input" ]]; then
    printf 'error: candidate build input must not be a symlink: %s\n' "$build_input" >&2
    exit 1
  fi
  if [[ ! -e "$build_input" ]]; then
    printf 'error: candidate build input not found: %s\n' "$build_input" >&2
    exit 1
  fi
done
if [[ ! -x "$app_executable" || ! -x "$helper_executable" ]]; then
  printf '%s\n' 'error: candidate executables are not executable' >&2
  exit 1
fi
if [[ ! -d "$resource_bundle" ]]; then
  printf 'error: candidate resource bundle is not a directory: %s\n' \
    "$resource_bundle" >&2
  exit 1
fi

linked_sdk_version="$($otool_path -l "$app_executable" | /usr/bin/awk '
  $1 == "cmd" {
    in_build_version = ($2 == "LC_BUILD_VERSION")
    next
  }
  in_build_version && $1 == "sdk" {
    linked_sdk = $2
    in_build_version = 0
  }
  END {
    if (linked_sdk != "") {
      print linked_sdk
    }
  }
')"
if [[ "$linked_sdk_version" != "$active_sdk_version" ]]; then
  printf 'error: candidate Fleck SDK stamp does not match active SDK: %s (expected %s)\n' \
    "${linked_sdk_version:-missing}" "$active_sdk_version" >&2
  exit 1
fi
if [[ -n "$(/usr/bin/find "$resource_bundle" -type l -print -quit)" ]]; then
  printf 'error: candidate resource bundle contains a symlink: %s\n' \
    "$resource_bundle" >&2
  exit 1
fi

gemma_lock_backup="$scratch_parent/NativeRuntime.Package.resolved"
/bin/cp -p "$gemma_cleanup_resolved" "$gemma_lock_backup"
gemma_lock_backup_ready=1
gemma_scratch_parent="$(mktemp -d "$canonical_build_root/.parakeet-gemma-cleanup.XXXXXX")"
gemma_scratch_marker="$gemma_scratch_parent/$cleanup_marker_name"
if ! validate_direct_child_directory "$gemma_scratch_parent" "$canonical_build_root" \
  'Gemma cleanup helper scratch directory' \
  || ! write_cleanup_marker "$gemma_scratch_marker"; then
  exit 1
fi
readonly gemma_derived_data="$gemma_scratch_parent/DerivedData"
readonly gemma_products_root="$gemma_derived_data/Products"

# NativeRuntime is lock-verified; noninteractive packaging cannot accept Xcode's plug-in prompt.
(
  cd -- "$gemma_cleanup_package"
  "$xcodebuild_path" \
    -scheme GemmaCleanupNativeRuntime \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$gemma_derived_data" \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    -skipPackagePluginValidation \
    "CONFIGURATION_BUILD_DIR=$gemma_products_root" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    build
)

if ! /usr/bin/cmp -s "$gemma_cleanup_resolved" "$gemma_lock_backup"; then
  printf '%s\n' 'error: Gemma cleanup helper build changed NativeRuntime Package.resolved' >&2
  exit 1
fi

if [[ -L "$gemma_products_root" || ! -d "$gemma_products_root" ]]; then
  printf 'error: Gemma cleanup helper product root not found: %s\n' \
    "$gemma_products_root" >&2
  exit 1
fi
readonly gemma_helper_executable="$gemma_products_root/gemma-cleanup-helper"
if [[ -L "$gemma_helper_executable" || ! -f "$gemma_helper_executable" \
  || ! -x "$gemma_helper_executable" ]]; then
  printf 'error: Gemma cleanup helper build input is unsafe: %s\n' \
    "$gemma_helper_executable" >&2
  exit 1
fi

readonly gemma_resource_bundle="$gemma_products_root/mlx-swift_Cmlx.bundle"
if [[ -L "$gemma_resource_bundle" || ! -d "$gemma_resource_bundle" ]]; then
  printf '%s\n' 'error: Gemma cleanup helper build did not produce exactly one MLX resource bundle' >&2
  exit 1
fi
first_gemma_resource_symlink="$(
  /usr/bin/find "$gemma_resource_bundle" -type l -print -quit
)"
if [[ -n "$first_gemma_resource_symlink" ]]; then
  printf 'error: Gemma cleanup helper MLX resource bundle contains a symlink: %s\n' \
    "$first_gemma_resource_symlink" >&2
  exit 1
fi
readonly gemma_resource_metadata="$gemma_resource_bundle/Contents/Info.plist"
if [[ -L "$gemma_resource_metadata" || ! -f "$gemma_resource_metadata" ]]; then
  printf 'error: Gemma cleanup helper MLX resource metadata is missing or unsafe: %s\n' \
    "$gemma_resource_metadata" >&2
  exit 1
fi
readonly gemma_metallib="$gemma_resource_bundle/Contents/Resources/default.metallib"
if [[ -L "$gemma_metallib" || ! -f "$gemma_metallib" ]]; then
  printf 'error: Gemma cleanup helper MLX resource is missing or unsafe: %s\n' \
    "$gemma_metallib" >&2
  exit 1
fi
actual_gemma_resource_contents="$(
  /usr/bin/find "$gemma_resource_bundle" ! -path "$gemma_resource_bundle" -print \
    | /usr/bin/sed "s#^$gemma_resource_bundle/##" \
    | LC_ALL=C /usr/bin/sort
)"
expected_gemma_resource_contents=$'Contents\nContents/Info.plist\nContents/Resources\nContents/Resources/default.metallib'
if [[ "$actual_gemma_resource_contents" != "$expected_gemma_resource_contents" ]]; then
  printf '%s\n' 'error: Gemma cleanup helper MLX resource bundle contains unexpected entries' >&2
  printf 'actual:\n%s\n' "$actual_gemma_resource_contents" >&2
  exit 1
fi

staging_root="$(mktemp -d "$canonical_build_root/.parakeet-test.XXXXXX")"
staging_marker="$staging_root/$cleanup_marker_name"
if ! validate_direct_child_directory "$staging_root" "$canonical_build_root" 'staging directory' \
  || ! write_cleanup_marker "$staging_marker"; then
  exit 1
fi
readonly staged_app="$staging_root/Fleck.app"
readonly staged_bundle="$staged_app/Contents/Resources/Fleck_FleckApp.bundle"
readonly staged_gemma_resource_bundle="$staged_app/Contents/SharedSupport/mlx-swift_Cmlx.bundle"
/bin/mkdir -p \
  "$staged_app/Contents/MacOS" \
  "$staged_app/Contents/SharedSupport" \
  "$staged_app/Contents/Resources"
/bin/cp "$app_executable" "$staged_app/Contents/MacOS/Fleck"
/bin/cp "$helper_executable" "$staged_app/Contents/SharedSupport/fleck-agent"
/bin/cp "$gemma_helper_executable" \
  "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
/bin/cp -R "$gemma_resource_bundle" "$staged_gemma_resource_bundle"
/bin/cp "$info_plist" "$staged_app/Contents/Info.plist"
/bin/cp "$canonical_mark" "$staged_app/Contents/Resources/fleck-mark.png"
/bin/cp -R "$resource_bundle" "$staged_bundle"
/bin/chmod 755 \
  "$staged_app/Contents/MacOS/Fleck" \
  "$staged_app/Contents/SharedSupport/fleck-agent" \
  "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"

first_symlink="$(/usr/bin/find "$staging_root" -type l -print -quit)"
if [[ -n "$first_symlink" ]]; then
  printf 'error: staged test app contains a symlink: %s\n' "$first_symlink" >&2
  exit 1
fi

for forbidden_suffix in \
  '*.mlmodel' '*.mlpackage' '*.mlmodelc' '*.safetensors' '*.gguf' '*.onnx' \
  '*model.bin' '*weight.bin' '*weights.bin' 'coremldata.bin'; do
  forbidden_path="$(/usr/bin/find "$staging_root" -iname "$forbidden_suffix" -print -quit)"
  if [[ -n "$forbidden_path" ]]; then
    printf 'error: staged test app contains a forbidden model asset: %s\n' \
      "$forbidden_path" >&2
    exit 1
  fi
done

expected_app_contents=$'Contents\nContents/Info.plist\nContents/MacOS\nContents/MacOS/Fleck\nContents/Resources\nContents/Resources/Fleck_FleckApp.bundle\nContents/Resources/Fleck_FleckApp.bundle/EnhancedModelManifest.json\nContents/Resources/Fleck_FleckApp.bundle/GemmaCleanupModelManifest.json\nContents/Resources/Fleck_FleckApp.bundle/GemmaCleanupNotice.md\nContents/Resources/Fleck_FleckApp.bundle/ThirdPartyNotices.md\nContents/Resources/fleck-mark.png\nContents/SharedSupport\nContents/SharedSupport/fleck-agent\nContents/SharedSupport/gemma-cleanup-helper\nContents/SharedSupport/mlx-swift_Cmlx.bundle\nContents/SharedSupport/mlx-swift_Cmlx.bundle/Contents\nContents/SharedSupport/mlx-swift_Cmlx.bundle/Contents/Info.plist\nContents/SharedSupport/mlx-swift_Cmlx.bundle/Contents/Resources\nContents/SharedSupport/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib'
actual_app_contents="$(
  /usr/bin/find "$staged_app" ! -path "$staged_app" -print \
    | /usr/bin/sed "s#^$staged_app/##" \
    | LC_ALL=C /usr/bin/sort
)"
if [[ "$actual_app_contents" != "$expected_app_contents" ]]; then
  printf '%s\n' 'error: staged app contains files outside the permitted inputs' >&2
  printf 'actual:\n%s\n' "$actual_app_contents" >&2
  exit 1
fi

if [[ -e "$staged_app/Fleck_FleckApp.bundle" || -L "$staged_app/Fleck_FleckApp.bundle" ]]; then
  printf '%s\n' 'error: staged resource bundle must not be at the app root' >&2
  exit 1
fi
if [[ -n "$(/usr/bin/find "$staged_bundle" ! -path "$staged_bundle" ! -type f -print -quit)" ]]; then
  printf '%s\n' 'error: staged resource bundle contains a directory or symlink' >&2
  exit 1
fi
expected_bundle_contents=$'EnhancedModelManifest.json\nGemmaCleanupModelManifest.json\nGemmaCleanupNotice.md\nThirdPartyNotices.md'
actual_bundle_contents="$(
  /usr/bin/find "$staged_bundle" -type f -print \
    | /usr/bin/sed "s#^$staged_bundle/##" \
    | LC_ALL=C /usr/bin/sort
)"
if [[ "$actual_bundle_contents" != "$expected_bundle_contents" ]]; then
  printf '%s\n' 'error: resource bundle does not contain exactly the permitted resources' >&2
  printf 'actual:\n%s\n' "$actual_bundle_contents" >&2
  exit 1
fi

for exact_pair in \
  "$info_plist|$staged_app/Contents/Info.plist" \
  "$canonical_mark|$staged_app/Contents/Resources/fleck-mark.png" \
  "$manifest|$staged_bundle/EnhancedModelManifest.json" \
  "$notices|$staged_bundle/ThirdPartyNotices.md" \
  "$gemma_cleanup_manifest|$staged_bundle/GemmaCleanupModelManifest.json" \
  "$gemma_cleanup_notice|$staged_bundle/GemmaCleanupNotice.md" \
  "$gemma_resource_metadata|$staged_gemma_resource_bundle/Contents/Info.plist" \
  "$gemma_metallib|$staged_gemma_resource_bundle/Contents/Resources/default.metallib"; do
  source_path="${exact_pair%%|*}"
  staged_path="${exact_pair#*|}"
  if ! /usr/bin/cmp -s "$source_path" "$staged_path"; then
    printf 'error: staged resource differs from source: %s\n' "$staged_path" >&2
    exit 1
  fi
done

verify_arm64() {
  local executable="$1"
  local architectures
  architectures="$($lipo_path -archs "$executable")"
  if [[ "$architectures" != "arm64" ]]; then
    printf 'error: executable is not arm64-only: %s (%s)\n' \
      "$executable" "$architectures" >&2
    exit 1
  fi
}

extract_rpaths() {
  local executable="$1"
  "$otool_path" -l "$executable" | /usr/bin/awk '
    $1 == "cmd" {
      in_rpath = ($2 == "LC_RPATH")
      next
    }
    in_rpath && $1 == "path" {
      print $2
      in_rpath = 0
    }
  '
}

is_allowed_rpath() {
  case "$1" in
    /usr/lib/swift)
      return 0
      ;;
    @executable_path/*|@loader_path/*)
      if [[ "$1" == *".."* ]]; then
        return 1
      fi
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

strip_disallowed_rpaths() {
  local executable="$1"
  local rpath
  while IFS= read -r rpath; do
    [[ -z "$rpath" ]] && continue
    if ! is_allowed_rpath "$rpath"; then
      printf 'Removing non-portable LC_RPATH from %s: %s\n' \
        "$executable" "$rpath" >&2
      "$install_name_tool_path" -delete_rpath "$rpath" "$executable"
    fi
  done < <(extract_rpaths "$executable")
}

verify_rpaths() {
  local executable="$1"
  local rpath
  local rpath_count=0
  while IFS= read -r rpath; do
    [[ -z "$rpath" ]] && continue
    rpath_count=$((rpath_count + 1))
    if ! is_allowed_rpath "$rpath"; then
      printf 'error: unpermitted LC_RPATH in %s: %s\n' "$executable" "$rpath" >&2
      return 1
    fi
    case "$rpath" in
      /*)
        if [[ "$rpath" != "/usr/lib/swift" ]]; then
          printf 'error: absolute non-system LC_RPATH in %s: %s\n' \
            "$executable" "$rpath" >&2
          return 1
        fi
        ;;
      @executable_path/*|@loader_path/*)
        if [[ "$rpath" == *".."* ]]; then
          printf 'error: escaping in-app LC_RPATH in %s: %s\n' "$executable" "$rpath" >&2
          return 1
        fi
        ;;
    esac
  done < <(extract_rpaths "$executable")
  if (( rpath_count == 0 )); then
    printf '%s\n' "LC_RPATH (none)" >&2
  fi
}

verify_dynamic_dependencies() {
  local executable="$1"
  local dependency_output
  local dependency
  if ! dependency_output="$($otool_path -L "$executable" 2>&1)"; then
    printf 'error: unable to inspect dynamic dependencies: %s\n' "$executable" >&2
    exit 1
  fi
  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    case "$dependency" in
      /System/Library/*|/usr/lib/*|@rpath/libswift*.dylib)
        ;;
      *)
        printf 'error: unpermitted dynamic dependency in %s: %s\n' \
          "$executable" "$dependency" >&2
        exit 1
        ;;
    esac
  done < <(
    /usr/bin/sed -n \
      's/^[[:space:]]*\([^[:space:]]*\) (.*$/\1/p' \
      <<<"$dependency_output"
  )
}

verify_rpath_dependencies() {
  local executable="$1"
  local executable_directory
  local dependency_output
  local dependency
  local dependency_name
  local rpath
  local candidate
  local satisfied
  executable_directory="$(cd -- "$(dirname -- "$executable")" && pwd -P)"
  dependency_output="$($otool_path -L "$executable")"
  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    case "$dependency" in
      @rpath/*)
        dependency_name="${dependency#@rpath/}"
        if [[ "$dependency_name" != libswift*.dylib || "$dependency_name" == */* \
          || "$dependency_name" == *".."* ]]; then
          printf 'error: unsupported @rpath dependency in %s: %s\n' \
            "$executable" "$dependency" >&2
          return 1
        fi
        satisfied=0
        while IFS= read -r rpath; do
          [[ -z "$rpath" ]] && continue
          case "$rpath" in
            /usr/lib/swift)
              candidate="$rpath/$dependency_name"
              ;;
            @executable_path/*|@loader_path/*)
              candidate="$executable_directory/${rpath#*/}/$dependency_name"
              case "$candidate" in
                "$staged_app"/*) ;;
                *)
                  printf 'error: @rpath candidate escapes the app: %s\n' "$candidate" >&2
                  return 1
                  ;;
              esac
              ;;
            *)
              printf 'error: @rpath dependency uses a disallowed rpath: %s\n' "$rpath" >&2
              return 1
              ;;
          esac
          if [[ -f "$candidate" ]]; then
            satisfied=1
            break
          fi
        done < <(extract_rpaths "$executable")
        if (( satisfied == 0 )); then
          printf 'error: @rpath dependency is unsatisfied in %s: %s\n' \
            "$executable" "$dependency" >&2
          return 1
        fi
        ;;
      /System/Library/*|/usr/lib/*)
        ;;
      *)
        printf 'error: dependency is not portable in %s: %s\n' \
          "$executable" "$dependency" >&2
        return 1
        ;;
    esac
  done < <(
    /usr/bin/sed -n \
      's/^[[:space:]]*\([^[:space:]]*\) (.*$/\1/p' \
      <<<"$dependency_output"
  )
}

print_rpath_evidence() {
  local executable="$1"
  printf 'LC_RPATH evidence for %s:\n' "$executable"
  extract_rpaths "$executable" | /usr/bin/sed 's/^/  /'
  printf 'Dynamic dependency evidence for %s:\n' "$executable"
  "$otool_path" -L "$executable" | /usr/bin/sed -n '1,8p'
}

verify_arm64 "$staged_app/Contents/MacOS/Fleck"
verify_arm64 "$staged_app/Contents/SharedSupport/fleck-agent"
verify_arm64 "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
strip_disallowed_rpaths "$staged_app/Contents/MacOS/Fleck"
strip_disallowed_rpaths "$staged_app/Contents/SharedSupport/fleck-agent"
strip_disallowed_rpaths "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
verify_rpaths "$staged_app/Contents/MacOS/Fleck"
verify_rpaths "$staged_app/Contents/SharedSupport/fleck-agent"
verify_rpaths "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
verify_dynamic_dependencies "$staged_app/Contents/MacOS/Fleck"
verify_dynamic_dependencies "$staged_app/Contents/SharedSupport/fleck-agent"
verify_dynamic_dependencies "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
verify_rpath_dependencies "$staged_app/Contents/MacOS/Fleck"
verify_rpath_dependencies "$staged_app/Contents/SharedSupport/fleck-agent"
verify_rpath_dependencies "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
print_rpath_evidence "$staged_app/Contents/MacOS/Fleck"
print_rpath_evidence "$staged_app/Contents/SharedSupport/fleck-agent"
print_rpath_evidence "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"

readonly bundle_identifier="$(
  /usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    "$staged_app/Contents/Info.plist"
)"
if [[ "$bundle_identifier" != "$expected_bundle_identifier" ]]; then
  printf 'error: unexpected Fleck bundle identifier: %s\n' "$bundle_identifier" >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - \
  "$staged_app/Contents/Info.plist")" != "Fleck" ]]; then
  printf '%s\n' 'error: staged app has unexpected CFBundleExecutable' >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract CFBundlePackageType raw -o - \
  "$staged_app/Contents/Info.plist")" != "APPL" ]]; then
  printf '%s\n' 'error: staged app is missing CFBundlePackageType=APPL' >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract LSUIElement raw -o - \
  "$staged_app/Contents/Info.plist")" != "true" ]]; then
  printf '%s\n' 'error: staged app is missing LSUIElement=true' >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract NSPrincipalClass raw -o - \
  "$staged_app/Contents/Info.plist")" != "NSApplication" ]]; then
  printf '%s\n' 'error: staged app is missing NSPrincipalClass=NSApplication' >&2
  exit 1
fi

readonly designated_requirement="=designated => identifier \"$bundle_identifier\""
"$codesign_path" --force --sign - \
  --identifier "$bundle_identifier.gemma-cleanup-helper" \
  "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
"$codesign_path" --force --sign - \
  --identifier "$bundle_identifier.agent" \
  "$staged_app/Contents/SharedSupport/fleck-agent"
"$codesign_path" --force --sign - \
  --identifier "$bundle_identifier" \
  --requirements "$designated_requirement" \
  "$staged_app"
"$codesign_path" --verify --strict \
  "$staged_app/Contents/SharedSupport/fleck-agent"
"$codesign_path" --verify --strict \
  "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"
"$codesign_path" --verify --deep --strict "$staged_app"

app_signature_details="$(
  "$codesign_path" -dv --verbose=4 "$staged_app" 2>&1
)"
helper_signature_details="$(
  "$codesign_path" -dv --verbose=4 \
    "$staged_app/Contents/SharedSupport/fleck-agent" 2>&1
)"
gemma_signature_details="$(
  "$codesign_path" -dv --verbose=4 \
    "$staged_app/Contents/SharedSupport/gemma-cleanup-helper" 2>&1
)"
if ! /usr/bin/grep -Fq 'Signature=adhoc' <<<"$app_signature_details" \
  || ! /usr/bin/grep -Fq 'Signature=adhoc' <<<"$helper_signature_details"; then
  printf '%s\n' 'error: test app and helper must use ad-hoc signatures' >&2
  exit 1
fi
if ! /usr/bin/grep -Fq 'Signature=adhoc' <<<"$gemma_signature_details"; then
  printf '%s\n' 'error: Gemma cleanup helper must use an ad-hoc signature' >&2
  exit 1
fi
if [[ "$(/usr/bin/sed -n 's/^Identifier=//p' <<<"$app_signature_details")" \
  != "$bundle_identifier" ]]; then
  printf '%s\n' 'error: app signature identifier does not match the stable bundle identifier' >&2
  exit 1
fi
if [[ "$(/usr/bin/sed -n 's/^Identifier=//p' <<<"$helper_signature_details")" \
  != "$bundle_identifier.agent" ]]; then
  printf '%s\n' 'error: helper signature identifier does not match the stable app identifier' >&2
  exit 1
fi
if [[ "$(/usr/bin/sed -n 's/^Identifier=//p' <<<"$gemma_signature_details")" \
  != "$bundle_identifier.gemma-cleanup-helper" ]]; then
  printf '%s\n' 'error: Gemma cleanup helper signature identifier is not subordinate to the app identifier' >&2
  exit 1
fi
app_signature_requirement="$(
  "$codesign_path" -d -r- "$staged_app" 2>&1
)"
if /usr/bin/grep -Fq 'cdhash' <<<"$app_signature_requirement" \
  || ! /usr/bin/grep -Fq "identifier \"$bundle_identifier\"" \
    <<<"$app_signature_requirement"; then
  printf '%s\n' 'error: app signature does not use the stable designated requirement' >&2
  exit 1
fi

if [[ -e "$app_destination" || -L "$app_destination" \
  || -e "$sibling_resource_output" || -L "$sibling_resource_output" ]]; then
  printf '%s\n' 'error: test app publication destinations must be unused' >&2
  exit 1
fi

publish_atomic() {
  local staged="$1"
  local destination="$2"
  "$swift_path" -e '
    import Foundation

    let staged = URL(fileURLWithPath: CommandLine.arguments[1])
    let destination = URL(fileURLWithPath: CommandLine.arguments[2])
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: destination.path) else {
      throw NSError(domain: "FleckParakeetPackaging", code: 1)
    }
    try fileManager.moveItem(at: staged, to: destination)
  ' "$staged" "$destination"
}

publish_atomic "$staged_app" "$app_destination"
"$codesign_path" --verify --deep --strict "$app_destination"
if [[ -e "$sibling_resource_output" || -L "$sibling_resource_output" ]]; then
  printf 'error: sibling resource bundle was published: %s\n' \
    "$sibling_resource_output" >&2
  exit 1
fi
if [[ -e "$app_destination/Fleck_FleckApp.bundle" \
  || -L "$app_destination/Fleck_FleckApp.bundle" ]]; then
  printf '%s\n' 'error: resource bundle was published at the app root' >&2
  exit 1
fi
for published_resource in \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/EnhancedModelManifest.json" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/ThirdPartyNotices.md" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/GemmaCleanupModelManifest.json" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/GemmaCleanupNotice.md"; do
  if [[ ! -f "$published_resource" ]]; then
    printf 'error: embedded resource missing after publication: %s\n' \
      "$published_resource" >&2
    exit 1
  fi
done
if ! /usr/bin/cmp -s \
  "$manifest" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/EnhancedModelManifest.json"; then
  printf '%s\n' 'error: published manifest differs from source' >&2
  exit 1
fi
if ! /usr/bin/cmp -s \
  "$notices" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/ThirdPartyNotices.md"; then
  printf '%s\n' 'error: published notices differ from source' >&2
  exit 1
fi
if ! /usr/bin/cmp -s \
  "$gemma_cleanup_manifest" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/GemmaCleanupModelManifest.json"; then
  printf '%s\n' 'error: published Gemma cleanup manifest differs from source' >&2
  exit 1
fi
if ! /usr/bin/cmp -s \
  "$gemma_cleanup_notice" \
  "$app_destination/Contents/Resources/Fleck_FleckApp.bundle/GemmaCleanupNotice.md"; then
  printf '%s\n' 'error: published Gemma cleanup notice differs from source' >&2
  exit 1
fi

printf 'Built arm64 ad-hoc Parakeet test app: %s\n' "$app_destination"
printf 'Manual open command (not run):\n  /usr/bin/open -n "%s"\n' "$app_destination"
printf '%s\n' \
  'Model install: this artifact is a pinned experimental Parakeet candidate; install nothing automatically and do not treat it as admitted or release-ready.'
