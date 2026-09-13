#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly identity_tool="$script_dir/fleck-build-identity.py"

if [[ -n "${FLECK_ENHANCED_CANDIDATE+x}" ]]; then
  printf '%s\n' \
    'error: unset FLECK_ENHANCED_CANDIDATE before validating an ordinary release' \
    >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: this validation script must run on macOS\n' >&2
  exit 2
fi

major_version="$(sw_vers -productVersion | cut -d. -f1)"
if (( major_version < 14 )); then
  printf 'error: Fleck requires macOS 14 or later (found %s)\n' \
    "$(sw_vers -productVersion)" >&2
  exit 2
fi

if ! xcode-select -p >/dev/null 2>&1; then
  printf 'error: select Xcode command-line tools with xcode-select first\n' >&2
  exit 2
fi

cd "$repo_root"

printf '%s\n' '--- Host ---'
sw_vers
xcodebuild -version
swift --version

printf '%s\n' '--- Tests ---'
"$script_dir/run-nonempty-swift-tests.sh" '^.+$'

printf '%s\n' '--- Release build ---'
validation_result_root="$(/usr/bin/mktemp -d "$repo_root/.build/.validation-result.XXXXXX")"
readonly validation_result_device="$(/usr/bin/stat -f '%d' "$validation_result_root")"
readonly validation_result_inode="$(/usr/bin/stat -f '%i' "$validation_result_root")"
validation_result_pending=1
cleanup_validation_result() {
  local exit_code=$?
  trap - EXIT
  if (( validation_result_pending != 0 )); then
    if [[ ! -L "$validation_result_root" && -d "$validation_result_root" \
      && "$(/usr/bin/stat -f '%d' "$validation_result_root" 2>/dev/null || true)" == "$validation_result_device" \
      && "$(/usr/bin/stat -f '%i' "$validation_result_root" 2>/dev/null || true)" == "$validation_result_inode" ]]; then
      /usr/bin/find "$validation_result_root" -depth -delete || exit_code=1
    else
      printf '%s\n' 'error: refusing to remove a substituted validation result directory' >&2
      exit_code=1
    fi
  fi
  exit "$exit_code"
}
trap cleanup_validation_result EXIT
readonly build_result="$validation_result_root/build-result.json"
"$script_dir/build-fleck-app.sh" --result-file "$build_result"

if ! app_bundle="$("$identity_tool" read-result \
  --repo "$repo_root" \
  --result-file "$build_result" \
  --flavor development)"; then
  printf '%s\n' 'error: development packager returned an invalid result' >&2
  exit 1
fi
if [[ ! -L "$validation_result_root" && -d "$validation_result_root" \
  && "$(/usr/bin/stat -f '%d' "$validation_result_root")" == "$validation_result_device" \
  && "$(/usr/bin/stat -f '%i' "$validation_result_root")" == "$validation_result_inode" ]]; then
  /usr/bin/find "$validation_result_root" -depth -delete
  validation_result_pending=0
  trap - EXIT
else
  printf '%s\n' 'error: refusing to remove a substituted validation result directory' >&2
  exit 1
fi
readonly app_bundle
readonly app_binary="$app_bundle/Contents/MacOS/Fleck"
readonly bundled_helper="$app_bundle/Contents/SharedSupport/fleck-agent"
readonly bundled_mark="$app_bundle/Contents/Resources/fleck-mark.png"
readonly canonical_mark="$repo_root/website/public/fleck-mark.png"
readonly expected_bundle_identifier="com.harryjin.fleck"

bundle_identifier="$(
  /usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    "$app_bundle/Contents/Info.plist"
)"
if [[ "$bundle_identifier" != "$expected_bundle_identifier" ]]; then
  printf 'error: unexpected app bundle identifier: %s\n' \
    "$bundle_identifier" >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract LSUIElement raw -o - \
  "$app_bundle/Contents/Info.plist")" != "true" ]]; then
  printf '%s\n' 'error: packaged Fleck must have LSUIElement=true' >&2
  exit 1
fi
if [[ ! -s "$bundled_mark" ]]; then
  printf 'error: bundled Fleck mark not found: %s\n' "$bundled_mark" >&2
  exit 1
fi
if ! /usr/bin/cmp -s "$canonical_mark" "$bundled_mark"; then
  printf '%s\n' 'error: bundled Fleck mark differs from website/public/fleck-mark.png' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_bundle"
signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_bundle" 2>&1)"
signature_identifier="$(
  /usr/bin/sed -n 's/^Identifier=//p' <<<"$signature_details"
)"
if [[ "$signature_identifier" != "$bundle_identifier" ]]; then
  printf 'error: signature identifier does not match bundle identifier: %s\n' \
    "$signature_identifier" >&2
  exit 1
fi
signature_requirement="$(/usr/bin/codesign -d -r- "$app_bundle" 2>&1)"
if /usr/bin/grep -F 'cdhash' <<<"$signature_requirement" >/dev/null; then
  printf 'error: signature uses a build-specific code hash\n' >&2
  exit 1
fi
if ! /usr/bin/grep -F "identifier \"$bundle_identifier\"" \
  <<<"$signature_requirement" >/dev/null; then
  printf 'error: signature requirement is missing the bundle identifier\n' >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract CFBundlePackageType raw -o - \
  "$app_bundle/Contents/Info.plist")" != "APPL" ]]; then
  printf 'error: packaged Fleck is missing CFBundlePackageType=APPL\n' >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract NSPrincipalClass raw -o - \
  "$app_bundle/Contents/Info.plist")" != "NSApplication" ]]; then
  printf 'error: packaged Fleck is missing NSPrincipalClass=NSApplication\n' >&2
  exit 1
fi
for privacy_key in \
  NSMicrophoneUsageDescription \
  NSSpeechRecognitionUsageDescription; do
  if [[ -z "$(/usr/bin/plutil -extract "$privacy_key" raw -o - \
    "$app_bundle/Contents/Info.plist")" ]]; then
    printf 'error: packaged Fleck is missing %s\n' "$privacy_key" >&2
    exit 1
  fi
done
if ! /usr/bin/strings "$app_binary" \
  | /usr/bin/grep -Fx "$expected_bundle_identifier" >/dev/null; then
  printf 'error: app binary is missing embedded bundle identifier: %s\n' \
    "$expected_bundle_identifier" >&2
  exit 1
fi
if [[ ! -x "$bundled_helper" ]]; then
  printf 'error: executable bundled helper not found: %s\n' \
    "$bundled_helper" >&2
  exit 1
fi
"$script_dir/check-release-size.sh" "$app_bundle"

printf '%s\n' '--- Candidate lock preservation ---'
"$script_dir/test-enhanced-candidate-lock-preservation.sh"

printf '%s\n' '--- Candidate release rejection ---'
"$script_dir/check-candidate-release-rejected.sh"

printf '\nValidation build passed. Launch Fleck as an app bundle with:\n  %s\n' \
  "/usr/bin/open -n \"$app_bundle\""
