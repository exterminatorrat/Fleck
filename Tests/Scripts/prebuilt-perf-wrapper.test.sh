#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-prebuilt-wrapper.XXXXXX")"
readonly canonical_test_root="$(cd -- "$test_root" && pwd -P)"
readonly fixture_root="$canonical_test_root/repo"
readonly fixture_scripts="$fixture_root/Scripts"
readonly tools="$canonical_test_root/tools"
readonly state="$canonical_test_root/state"
readonly receipt="$canonical_test_root/perf-prebuilt.json"
readonly sdk_path="$canonical_test_root/sdk"
readonly platform_path="$canonical_test_root/platform"
readonly products="$fixture_root/.build/out/Products/Debug"
readonly test_executable="$products/FleckPerformanceTests.xctest/Contents/MacOS/FleckPerformanceTests"
readonly runner="$fixture_scripts/run-swift-tests-with-appkit-host.sh"

cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

/bin/mkdir -p "$fixture_scripts" "$fixture_root/Tests/Support" "$tools" "$state" \
  "$sdk_path" "$platform_path/Developer/Library/Frameworks/Testing.framework" \
  "$products/FleckPerformanceTests.xctest/Contents/MacOS"
/bin/cp "$repo_root/Scripts/run-swift-tests-with-appkit-host.sh" "$fixture_scripts/"
/bin/cp "$repo_root/Scripts/validate-perf-prebuilt.py" "$fixture_scripts/"
/bin/cp "$repo_root/Tests/Support/AppKitTestMain.swift" "$fixture_root/Tests/Support/"
/bin/cat > "$fixture_root/.gitignore" <<'EOF'
.build/
EOF
/bin/cat > "$sdk_path/SDKSettings.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>Version</key>
  <string>27.4</string>
</dict>
</plist>
PLIST
/bin/cat > "$test_executable" <<'EOF'
prebuilt performance bundle fixture
EOF
/bin/chmod +x "$test_executable"

git -C "$fixture_root" init -q
git -C "$fixture_root" config user.email fixture@example.invalid
git -C "$fixture_root" config user.name 'Prebuilt wrapper fixture'
git -C "$fixture_root" add .
git -C "$fixture_root" commit -qm 'Prebuilt wrapper fixture source'

python3 -B - "$fixture_root" "$receipt" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def git(*args):
    return subprocess.run(
        ["git", "-C", str(root), *args], check=True, capture_output=True, text=True
    ).stdout.strip()
receipt = {
    "schemaVersion": 1,
    "packageRoot": str(root),
    "sourceCommit": git("rev-parse", "HEAD"),
    "sourceTree": git("rev-parse", "HEAD^{tree}"),
    "configuration": "debug",
    "buildSystem": "swiftbuild",
    "testabilityEnabled": True,
    "swiftVersion": "Swift version 6.4.0 (swift-6.4-RELEASE)",
    "sdkVersion": "27.4",
    "harnessSHA256": digest(root / "Tests/Support/AppKitTestMain.swift"),
    "bootstrapWrapperSHA256": digest(root / "Scripts/run-swift-tests-with-appkit-host.sh"),
    "testBundleExecutableSHA256": digest(
        root / ".build/out/Products/Debug/FleckPerformanceTests.xctest/Contents/MacOS/FleckPerformanceTests"
    ),
}
Path(sys.argv[2]).write_text(json.dumps(receipt), encoding="utf-8")
PY

/bin/cat > "$tools/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_XCRUN_LOG"
if [[ "$#" == 3 && "$1" == --sdk && "$2" == macosx ]]; then
  case "$3" in
    --show-sdk-path) printf '%s\n' "$FAKE_SDK_PATH" ;;
    --show-sdk-platform-path) printf '%s\n' "$FAKE_PLATFORM_PATH" ;;
    *) exit 98 ;;
  esac
elif [[ "$#" == 4 && "$1" == --sdk && "$2" == macosx &&
  "$3" == --find && "$4" == swiftc ]]; then
  printf '%s\n' "$FAKE_SWIFTC_PATH"
else
  exit 98
fi
SH

/bin/cat > "$tools/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_SWIFT_LOG"
if [[ "$*" == --version ]]; then
  printf '%s\n' 'Swift version 6.4.0 (swift-6.4-RELEASE)' 'Target: arm64-apple-macosx24.5'
  exit 0
fi
exit 97
SH

/bin/cat > "$tools/swiftc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_SWIFTC_LOG"
if [[ "${1:-}" == -print-target-info ]]; then
  printf '%s\n' '{"target":{"triple":"arm64-apple-macosx24.5"}}'
  exit 0
fi
exit 97
SH
/bin/chmod +x "$tools/xcrun" "$tools/swift" "$tools/swiftc"

base_environment=(
  "PATH=$tools:$PATH"
  "TMPDIR=$canonical_test_root"
  "FAKE_SDK_PATH=$sdk_path"
  "FAKE_PLATFORM_PATH=$platform_path"
  "FAKE_SWIFTC_PATH=$tools/swiftc"
  "FLECK_TEST_APPKIT_OPEN_PATH=/usr/bin/true"
  "FLECK_TEST_APPKIT_SAMPLE_PATH=/usr/bin/true"
  "FLECK_TEST_APPKIT_CODESIGN_PATH=/usr/bin/true"
)

if env -i "${base_environment[@]}" \
  FLECK_PERF_PREBUILT_RECEIPT="$receipt" FLECK_PERF_RUN=1 \
  FLECK_TEST_SWIFT_BUILD_SYSTEM=swiftbuild \
  FLECK_TEST_SWIFT_CONFIGURATION=debug \
  FLECK_TEST_SWIFT_TARGET=FleckPerformanceTests \
  FAKE_SWIFT_LOG="$state/valid.swift" \
  FAKE_SWIFTC_LOG="$state/valid.swiftc" \
  FAKE_XCRUN_LOG="$state/valid.xcrun" \
  "$runner" "$fixture_root" '' '^FleckPerformanceTests\.contractOne\(\)$' \
  > "$state/valid.output" 2>&1; then
  fail 'valid prebuilt invocation unexpectedly passed the mocked host compiler'
else
  status=$?
  [[ "$status" == 97 ]] || {
    /bin/cat "$state/valid.output" >&2
    fail "valid receipt did not reach the existing host compiler path (status $status)"
  }
fi

[[ "$(/usr/bin/wc -l < "$state/valid.swift" | /usr/bin/tr -d ' ')" == 1 ]] ||
  fail 'prebuilt mode invoked a Swift build or binary-path query'
/usr/bin/grep -Fxq -- --version "$state/valid.swift" ||
  fail 'prebuilt mode did not check the current Swift toolchain'
/usr/bin/grep -Fq -- '-print-target-info' "$state/valid.swiftc" ||
  fail 'prebuilt mode bypassed the selected SDK target check'
[[ "$(/usr/bin/wc -l < "$state/valid.swiftc" | /usr/bin/tr -d ' ')" == 2 ]] ||
  fail 'prebuilt mode did not continue through the normal AppKit host compiler path'
/usr/bin/grep -Fq -- "$test_executable" "$state/valid.output" &&
  fail 'wrapper leaked a bundle path while handling the mocked compiler failure'

if env -i "${base_environment[@]}" FLECK_PERF_PREBUILT_RECEIPT='' \
  FLECK_PERF_RUN=1 FLECK_TEST_SWIFT_BUILD_SYSTEM=swiftbuild \
  FLECK_TEST_SWIFT_CONFIGURATION=debug FLECK_TEST_SWIFT_TARGET=FleckPerformanceTests \
  FAKE_SWIFT_LOG="$state/empty.swift" FAKE_XCRUN_LOG="$state/empty.xcrun" \
  "$runner" "$fixture_root" '' '^FleckPerformanceTests\.contractOne\(\)$' \
  > "$state/empty.output" 2>&1; then
  fail 'empty prebuilt receipt input was accepted'
fi
[[ ! -e "$state/empty.swift" && ! -e "$state/empty.xcrun" ]] ||
  fail 'empty prebuilt receipt was not rejected before toolchain queries'

for field in \
  'if launch_host list --list-tests' \
  '/usr/bin/grep -E -- "$identifier_regex" "$canonical_output" > "$matches"' \
  'if launch_host run --filter "$run_filter" --no-parallel' \
  'if "$codesign_path" --verify --deep --strict --verbose=2 "$expected_host_app"' \
  'if ! verify_configured_host_resources "$configured_host_contents"'; do
  /usr/bin/grep -Fq -- "$field" "$runner" || fail "prebuilt path lost normal host gate: $field"
done
if /usr/bin/sed -n '/readonly host_environment_names=(/,/^)/p' "$runner" |
  /usr/bin/grep -Fq -- FLECK_PERF_PREBUILT_RECEIPT; then
  fail 'prebuilt receipt path was forwarded into the test host environment'
fi

printf '%s\n' 'prebuilt performance wrapper contract passed'
