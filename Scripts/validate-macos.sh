#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"

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
swift package clean
"$script_dir/build-fleck-app.sh"

readonly app_bundle="$repo_root/.build/Fleck.app"
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

printf '%s\n' '--- Bounded app-binary smoke test ---'
smoke_output="$(mktemp "${TMPDIR:-/tmp}/fleck-smoke.XXXXXX")"
smoke_pid=""
cleanup_smoke() {
  if [[ -n "$smoke_pid" ]] && /bin/kill -0 "$smoke_pid" 2>/dev/null; then
    /bin/kill -TERM "$smoke_pid" 2>/dev/null || true
    wait "$smoke_pid" 2>/dev/null || true
  fi
  /bin/rm -f -- "$smoke_output"
}
trap cleanup_smoke EXIT

"$app_binary" >"$smoke_output" 2>&1 &
smoke_pid=$!
/bin/sleep 2
if ! /bin/kill -0 "$smoke_pid" 2>/dev/null; then
  smoke_status=0
  wait "$smoke_pid" || smoke_status=$?
  printf 'error: Fleck exited during smoke test with status %s\n' \
    "$smoke_status" >&2
  cat "$smoke_output" >&2
  exit 1
fi
/bin/kill -TERM "$smoke_pid" 2>/dev/null || true
wait "$smoke_pid" 2>/dev/null || true
smoke_pid=""

printf '%s\n' '--- Candidate lock preservation ---'
"$script_dir/test-enhanced-candidate-lock-preservation.sh"

printf '%s\n' '--- Candidate release rejection ---'
"$script_dir/check-candidate-release-rejected.sh"

printf '\nValidation build passed. Launch Fleck as an app bundle with:\n  %s\n' \
  "/usr/bin/open -n \"$app_bundle\""
