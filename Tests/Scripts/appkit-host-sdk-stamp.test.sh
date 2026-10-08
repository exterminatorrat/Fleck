#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
runner="$repo_root/Scripts/run-swift-tests-with-appkit-host.sh"
test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-appkit-sdk-stamp.XXXXXX")"

cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

line_for() {
  /usr/bin/awk -v needle="$1" '
    index($0, needle) { count++; line = NR }
    END {
      if (count != 1) {
        exit 1
      }
      print line
    }
  ' "$runner"
}

sign_line="$(line_for 'if "$codesign_path" --force --deep --sign - "$expected_host_app"; then')" \
  || fail 'runner must explicitly ad-hoc sign the built host once'
expected_verify_line="$(line_for 'if "$codesign_path" --verify --deep --strict --verbose=2 "$expected_host_app"; then')" \
  || fail 'runner must strictly verify the signed expected host'
binary_compare_line="$(line_for 'if ! /usr/bin/cmp -s "$expected_host_binary" "$configured_host_binary"; then')" \
  || fail 'runner must compare the signed executable byte-for-byte'
plist_compare_line="$(line_for 'if ! /usr/bin/cmp -s "$expected_host_contents/Info.plist" "$configured_host_info"; then')" \
  || fail 'runner must compare the Info.plist byte-for-byte'
resource_compare_line="$(line_for 'if ! verify_configured_host_resources "$configured_host_contents"; then')" \
  || fail 'runner must retain the configured host resource comparison'
configured_verify_line="$(line_for 'if "$codesign_path" --verify --deep --strict --verbose=2 "$configured_host_app"; then')" \
  || fail 'runner must strictly verify the configured host signature'
if ! (( sign_line < expected_verify_line && expected_verify_line < binary_compare_line &&
  binary_compare_line < plist_compare_line && plist_compare_line < resource_compare_line &&
  resource_compare_line < configured_verify_line )); then
  fail 'signed host reuse checks must retain their original ordering'
fi

/usr/bin/grep -Fq -- '/usr/bin/plutil -extract Version raw -o - "$sdk_path/SDKSettings.plist"' \
  "$runner" || fail 'runner must read SDK version from the selected SDK path'
/usr/bin/grep -Fq -- '"$swiftc_path" -print-target-info -sdk "$sdk_path"' \
  "$runner" || fail 'runner must obtain the compiler target from the selected SDK'

tools="$test_root/tools"
/bin/mkdir -p "$tools"

/bin/cat > "$tools/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" == 3 && "$1" == '--sdk' && "$2" == 'macosx' ]]; then
  case "$3" in
    --show-sdk-path) printf '%s\n' "$FAKE_SDK_PATH" ;;
    --show-sdk-platform-path) printf '%s\n' "$FAKE_PLATFORM_PATH" ;;
    *) exit 98 ;;
  esac
elif [[ "$#" == 4 && "$1" == '--sdk' && "$2" == 'macosx' &&
  "$3" == '--find' && "$4" == 'swiftc' ]]; then
  printf '%s\n' "$FAKE_SWIFTC_PATH"
else
  exit 98
fi
SH

/bin/cat > "$tools/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_SWIFTPM_LOG_PATH"
if [[ "$*" == 'build --build-tests --disable-automatic-resolution' ]]; then
  exit 0
fi
if [[ "$*" == 'build --show-bin-path --disable-automatic-resolution' ]]; then
  /bin/mkdir -p "$FAKE_BIN_PATH/FleckTests.xctest/Contents/MacOS"
  printf '%s\n' 'fake test bundle' > "$FAKE_BIN_PATH/FleckTests.xctest/Contents/MacOS/FleckTests"
  /bin/chmod +x "$FAKE_BIN_PATH/FleckTests.xctest/Contents/MacOS/FleckTests"
  printf '%s\n' "$FAKE_BIN_PATH"
  exit 0
fi
exit 98
SH

/bin/cat > "$tools/swiftc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == '-print-target-info' ]]; then
  printf '%s\n' "$@" > "$FAKE_TARGET_INFO_ARGS_PATH"
  printf '{"target":{"triple":"%s"}}\n' "$FAKE_TARGET_TRIPLE"
  exit 0
fi
printf '%s\n' "$@" > "$FAKE_LINK_ARGS_PATH"
exit 97
SH

/bin/cat > "$tools/not-run" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$0 $*" >> "$FAKE_RUNTIME_TOOLS_LOG_PATH"
exit 98
SH

/bin/chmod +x "$tools/xcrun" "$tools/swift" "$tools/swiftc" "$tools/not-run"

write_sdk_settings() {
  local sdk_path="$1"
  local sdk_version="$2"
  /bin/mkdir -p "$sdk_path"
  /bin/cat > "$sdk_path/SDKSettings.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>Version</key>
  <string>$sdk_version</string>
</dict>
</plist>
PLIST
}

run_case() {
  local name="$1"
  local sdk_version="$2"
  local target_triple="$3"
  local expected_status="$4"
  local root="$test_root/$name"
  local sdk_path="$root/selected-sdk"
  local platform_path="$root/selected-platform"
  local bin_path="$root/bin"
  local temporary_path="$root/tmp"
  local state_path="$root/state"
  local status

  /bin/mkdir -p "$platform_path/Developer/Library/Frameworks/Testing.framework" \
    "$temporary_path" "$state_path"
  write_sdk_settings "$sdk_path" "$sdk_version"

  if (
    unset FLECK_NATIVE_CAPTURE_QA FLECK_TEST_APPKIT_HOST_APP_PATH FLECK_ENHANCED_CANDIDATE
    unset FLECK_TEST_APPKIT_WATCHDOG_SECONDS MACOSX_DEPLOYMENT_TARGET
    export PATH="$tools:$PATH"
    export TMPDIR="$temporary_path"
    export FAKE_SDK_PATH="$sdk_path"
    export FAKE_PLATFORM_PATH="$platform_path"
    export FAKE_SWIFTC_PATH="$tools/swiftc"
    export FAKE_BIN_PATH="$bin_path"
    export FAKE_SWIFTPM_LOG_PATH="$state_path/swiftpm-arguments"
    export FAKE_TARGET_INFO_ARGS_PATH="$state_path/target-info-arguments"
    export FAKE_LINK_ARGS_PATH="$state_path/link-arguments"
    export FAKE_RUNTIME_TOOLS_LOG_PATH="$state_path/runtime-tools"
    export FAKE_TARGET_TRIPLE="$target_triple"
    export FLECK_TEST_APPKIT_OPEN_PATH="$tools/not-run"
    export FLECK_TEST_APPKIT_SAMPLE_PATH="$tools/not-run"
    export FLECK_TEST_APPKIT_CODESIGN_PATH="$tools/not-run"
    "$runner" "$repo_root" '' '^Fleck.*$' > "$state_path/runner-output" 2>&1
  ); then
    status=0
  else
    status=$?
  fi

  [[ "$status" == "$expected_status" ]] || {
    /bin/cat "$state_path/runner-output" >&2
    fail "$name runner status was $status, expected $expected_status"
  }
  [[ ! -e "$state_path/runtime-tools" ]] || fail "$name invoked open, sample, or codesign"
  printf '%s\n' "$state_path"
}

invalid_sdk_state="$(run_case invalid-sdk not-a-version arm64-apple-macosx26.0 1)"
[[ ! -e "$invalid_sdk_state/swiftpm-arguments" &&
  ! -e "$invalid_sdk_state/target-info-arguments" &&
  ! -e "$invalid_sdk_state/link-arguments" ]] ||
  fail 'invalid SDK metadata must stop before SwiftPM and host compilation'

invalid_target_state="$(run_case invalid-target 27.4 arm64-apple-ios26.0 1)"
[[ -e "$invalid_target_state/target-info-arguments" &&
  ! -e "$invalid_target_state/swiftpm-arguments" &&
  ! -e "$invalid_target_state/link-arguments" ]] ||
  fail 'unsupported target triples must stop before SwiftPM and host compilation'

valid_state="$(run_case valid 27.4 arm64-apple-macosx24.5 97)"
[[ -s "$valid_state/target-info-arguments" && -s "$valid_state/link-arguments" ]] ||
  fail 'valid inputs must reach the compiler contract stub'
[[ "$(/usr/bin/grep -Fc -- 'build --build-tests --disable-automatic-resolution' \
  "$valid_state/swiftpm-arguments")" == 1 &&
  "$(/usr/bin/grep -Fc -- 'build --show-bin-path --disable-automatic-resolution' \
  "$valid_state/swiftpm-arguments")" == 1 ]] ||
  fail 'runner must use only the two fake SwiftPM preparation commands'

link_arguments=()
while IFS= read -r argument || [[ -n "$argument" ]]; do
  link_arguments+=("$argument")
done < "$valid_state/link-arguments"
expected_link_arguments=(-Xlinker -platform_version -Xlinker macos -Xlinker 24.5 -Xlinker 27.4)
found_link_arguments=0
for ((start = 0; start <= ${#link_arguments[@]} - ${#expected_link_arguments[@]}; start++)); do
  matches=1
  for ((offset = 0; offset < ${#expected_link_arguments[@]}; offset++)); do
    if [[ "${link_arguments[$((start + offset))]}" != "${expected_link_arguments[$offset]}" ]]; then
      matches=0
      break
    fi
  done
  if (( matches )); then
    found_link_arguments=1
    break
  fi
done
(( found_link_arguments == 1 )) || fail 'selected SDK and compiler deployment target were not forwarded to ld'
valid_sdk_path="$test_root/valid/selected-sdk"
/usr/bin/grep -Fqx -- "$valid_sdk_path" "$valid_state/link-arguments" ||
  fail 'compiler contract did not use the selected SDK path'
/usr/bin/grep -Fqx -- "$valid_sdk_path" "$valid_state/target-info-arguments" ||
  fail 'target query did not use the selected SDK path'

printf '%s\n' 'PASS: selected SDK and compiler target metadata are forwarded as linker platform-version inputs.'
printf '%s\n' 'PASS: invalid SDK or non-macOS metadata stops before SwiftPM and host compilation.'
printf '%s\n' 'PASS: signing, expected-host verification, and exact reuse checks retain their original order.'
