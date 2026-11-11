#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly packager="$repo_root/Scripts/build-fleck-app.sh"
readonly identity_tool="$repo_root/Scripts/fleck-build-identity.py"
readonly test_root="$(cd -P -- "$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-app-symbols.XXXXXX")" && pwd)"

cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

strip_line="$(/usr/bin/grep -nF 'xcrun strip -S "$staged_app/Contents/MacOS/Fleck"' "$packager" | /usr/bin/cut -d: -f1 || true)"
sign_line="$(/usr/bin/grep -nF '/usr/bin/codesign --force --sign -' "$packager" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
[[ -n "$strip_line" ]] || fail 'packager does not strip debug symbols from the staged executable'
[[ -n "$sign_line" && "$strip_line" -lt "$sign_line" ]] \
  || fail 'packager does not strip the staged executable before signing'

fixture_root="$test_root/repository"
fake_bin="$test_root/bin"
strip_log="$test_root/strip.log"
launch_sentinel="$test_root/launched"
swift_log="$test_root/swift.log"
source_hash_log="$test_root/source-hashes.log"
/bin/mkdir -p \
  "$fixture_root/Scripts" \
  "$fixture_root/Sources/FleckApp" \
  "$fixture_root/Assets" \
  "$fake_bin"
/bin/cp "$packager" "$fixture_root/Scripts/build-fleck-app.sh"
/bin/cp "$identity_tool" "$fixture_root/Scripts/fleck-build-identity.py"
printf '1.0.3-beta.1\n' > "$fixture_root/VERSION"
cat > "$fixture_root/CHANGELOG.md" <<'CHANGELOG'
# Changelog

## [1.0.3-beta.1] - 2026-09-13
CHANGELOG
cat > "$fixture_root/BuildBaseline.json" <<'BASELINE'
{
  "schemaVersion": 1,
  "canonicalManifestSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "selectedRecordID": "fixture-accepted",
  "acceptedSourceCommit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "acceptedSourceTree": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "requiredRegistryStatus": "active"
}
BASELINE
cat > "$fixture_root/Sources/FleckApp/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Fleck</string>
  <key>CFBundleIconFile</key><string>FleckAppIcon.icns</string>
  <key>CFBundleIdentifier</key><string>test.fleck.packager</string>
</dict></plist>
PLIST
printf 'fixture mark\n' > "$fixture_root/Assets/fleck-mark.png"
printf 'fixture light icon\n' > "$fixture_root/Assets/FleckAppIcon.icns"
printf 'fixture dark icon\n' > "$fixture_root/Assets/FleckAppIconDark.icns"

cat > "$fake_bin/uname" <<'SCRIPT'
#!/bin/sh
printf 'Darwin\n'
SCRIPT
cat > "$fake_bin/xcode-select" <<'SCRIPT'
#!/bin/sh
printf '/fixture/Xcode.app/Contents/Developer\n'
SCRIPT
cat > "$fake_bin/xcodebuild" <<'SCRIPT'
#!/bin/sh
printf 'Xcode fixture\n'
SCRIPT
cat > "$fake_bin/git" <<SCRIPT
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == '-C' ]]; then shift 2; fi
case "\${1:-} \${2:-}" in
  'rev-parse --show-toplevel') printf '%s\n' '$fixture_root' ;;
  'rev-parse HEAD^{commit}') printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
  'rev-parse HEAD^{tree}') printf '%s\n' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' ;;
  'ls-files -v') ;;
  'status --porcelain=v1') ;;
  'merge-base --is-ancestor') ;;
  *) exit 2 ;;
esac
SCRIPT
cat > "$fake_bin/swift" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

product=''
linker_values=()
while (( $# > 0 )); do
  case "$1" in
    --product)
      product="${2:-}"
      shift 2
      ;;
    -Xlinker)
      linker_values+=("${2:-}")
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

minos=''
sdk=''
for index in "${!linker_values[@]}"; do
  if [[ "${linker_values[$index]}" == '-platform_version' ]]; then
    minos="${linker_values[$((index + 2))]:-}"
    sdk="${linker_values[$((index + 3))]:-}"
  fi
done
[[ -n "$minos" ]] || minos='14.0'
[[ -n "$sdk" ]] || sdk="$minos"

printf '%s %s %s\n' "$product" "$minos" "$sdk" >> "$FLECK_TEST_SWIFT_LOG"

case "$product" in
  Fleck | fleck-agent) ;;
  *) exit 2 ;;
esac

/bin/mkdir -p .build/release
fixture_source="$FLECK_TEST_ROOT/fixture-$product.c"
cat > "$fixture_source" <<'C'
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

int main(void) {
  const char *sentinel = getenv("FLECK_TEST_LAUNCH_SENTINEL");
  if (sentinel != NULL) {
    int descriptor = open(sentinel, O_CREAT | O_WRONLY, 0644);
    if (descriptor >= 0) {
      close(descriptor);
    }
  }
  return 0;
}
C
link_flags=(
  -Xlinker -platform_version -Xlinker macos
  -Xlinker "$minos" -Xlinker "$sdk"
)
if [[ "$product" == 'Fleck' && "${FLECK_TEST_LINK_SPARKLE:-0}" == 1 ]]; then
  framework='.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
  /bin/mkdir -p "$framework/Versions/B/Resources"
  /bin/ln -s B "$framework/Versions/Current"
  /bin/ln -s Versions/Current/Sparkle "$framework/Sparkle"
  /bin/ln -s Versions/Current/Resources "$framework/Resources"
  cat > "$framework/Versions/B/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Sparkle</string>
  <key>CFBundleIdentifier</key><string>test.fleck.sparkle</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
  /usr/bin/xcrun clang -dynamiclib -x c - -o "$framework/Versions/B/Sparkle" \
    -install_name '@rpath/Sparkle.framework/Versions/B/Sparkle' <<'C'
int sparkle_fixture_value(void) { return 42; }
C
  /usr/bin/xcrun clang -x c - -o .build/release/Fleck \
    "${link_flags[@]}" \
    -F "$(/usr/bin/dirname "$framework")" -framework Sparkle \
    -Wl,-rpath,@loader_path <<'C'
extern int sparkle_fixture_value(void);
int main(void) { return sparkle_fixture_value() == 42 ? 0 : 1; }
C
else
  /usr/bin/xcrun clang -g "$fixture_source" -o ".build/release/$product" \
    "${link_flags[@]}"
fi

if [[ -n "${FLECK_TEST_VTOOL_STAMP:-}" \
  && "${FLECK_TEST_VTOOL_STAMP_PRODUCT:-$product}" == "$product" ]]; then
  read -r -a vtool_arguments <<< "$FLECK_TEST_VTOOL_STAMP"
  /usr/bin/xcrun vtool "${vtool_arguments[@]}" \
    -output ".build/release/$product.stamped" ".build/release/$product"
  /bin/mv -f ".build/release/$product.stamped" ".build/release/$product"
fi
if [[ "${FLECK_TEST_NON_MACHO:-0}" == 1 \
  && "${FLECK_TEST_NON_MACHO_PRODUCT:-$product}" == "$product" ]]; then
  printf 'not a Mach-O executable\n' > ".build/release/$product"
fi
/bin/chmod 755 ".build/release/$product"
printf '%s %s\n' "$product" \
  "$(/usr/bin/shasum -a 256 ".build/release/$product" | /usr/bin/awk '{print $1}')" \
  >> "$FLECK_TEST_SOURCE_HASH_LOG"
SCRIPT
cat > "$fake_bin/move-staged" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
while (( $# > 2 )); do shift; done
staged="$1"
destination="$2"
/bin/rm -rf -- "$destination"
/bin/mv -- "$staged" "$destination"
SCRIPT
cat > "$fake_bin/xcrun" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
if [[ "$1" == '--sdk' && "$2" == 'macosx' && "$3" == '--show-sdk-version' ]]; then
  printf '27.0\n'
  exit 0
fi
if [[ "$1" == '--find' && "$2" == 'swift' ]]; then
  printf '%s\n' "$FLECK_TEST_FAKE_BIN/move-staged"
  exit 0
fi
if [[ "$1" == 'strip' && "$2" == '-S' && $# == 3 ]]; then
  printf '%s\n' "$3" >> "$FLECK_TEST_STRIP_LOG"
  [[ "${FLECK_TEST_STRIP_FAIL:-0}" != 1 ]] || exit 42
  [[ "${FLECK_TEST_STRIP_NOOP:-0}" != 1 ]] || exit 0
  exec /usr/bin/strip -S "$3"
fi
if [[ "$1" == 'otool' ]]; then
  shift
  if [[ "$1" == '-l' && "${FLECK_TEST_OTOOL_FAIL:-0}" == 1 ]]; then
    /usr/bin/otool "$@" || true
    exit 1
  fi
  exec /usr/bin/otool "$@"
fi
if [[ "$1" == 'install_name_tool' ]]; then
  shift
  exec /usr/bin/install_name_tool "$@"
fi
exit 2
SCRIPT
/bin/chmod 755 \
  "$fake_bin"/* \
  "$fixture_root/Scripts/build-fleck-app.sh" \
  "$fixture_root/Scripts/fleck-build-identity.py"

run_packager() {
  local result_file="$1"
  shift
  /usr/bin/env \
    PATH="$fake_bin:/usr/bin:/bin" \
    CI=true \
    GITHUB_ACTIONS=true \
    FLECK_BUILD_IDENTITY_MODE=ci-unverified \
    FLECK_TEST_FAKE_BIN="$fake_bin" \
    FLECK_TEST_LAUNCH_SENTINEL="$launch_sentinel" \
    FLECK_TEST_STRIP_LOG="$strip_log" \
    FLECK_TEST_SWIFT_LOG="$swift_log" \
    FLECK_TEST_SOURCE_HASH_LOG="$source_hash_log" \
    FLECK_TEST_ROOT="$test_root" \
    "$@" \
    "$fixture_root/Scripts/build-fleck-app.sh" \
    --result-file "$result_file"
}

results="$fixture_root/.build/results"
/bin/mkdir -p "$results"
first_result="$results/first.json"
: > "$swift_log"
: > "$source_hash_log"
run_packager "$first_result" >/dev/null
original="$fixture_root/.build/release/Fleck"
packaged_app="$("$fixture_root/Scripts/fleck-build-identity.py" read-result \
  --repo "$fixture_root" \
  --result-file "$first_result" \
  --flavor development)"
packaged="$packaged_app/Contents/MacOS/Fleck"
test -f "$original"
test -f "$packaged"
packaged_resources="$(/usr/bin/dirname "$packaged")/../Resources"
for icon_name in FleckAppIcon.icns FleckAppIconDark.icns; do
  /usr/bin/cmp -s "$fixture_root/Assets/$icon_name" "$packaged_resources/$icon_name" \
    || fail "packager did not stage $icon_name"
done
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw -o - \
  "$(/usr/bin/dirname "$packaged")/../Info.plist")" == 'FleckAppIcon.icns' ]] \
  || fail 'packaged Info.plist does not name the primary native app icon'
built_hash="$(/usr/bin/awk '$1 == "Fleck" { hash = $2 } END { print hash }' "$source_hash_log")"
[[ -n "$built_hash" ]] || fail 'swift fixture did not record the built executable identity'
built_debug_entries="$(/usr/bin/nm -pa "$original" 2>/dev/null \
  | /usr/bin/awk '$5 == "OSO" {n += 1} END {print n + 0}')"
[[ "$built_debug_entries" -gt 0 ]] \
  || fail 'swift fixture did not emit a debug map for the built executable'
packaged_debug_entries="$(/usr/bin/nm -pa "$packaged" 2>/dev/null \
  | /usr/bin/awk '$5 == "OSO" {n += 1} END {print n + 0}')"
[[ "$packaged_debug_entries" == 0 ]] \
  || fail 'packager published an executable that still carries its debug map'
[[ "$(/usr/bin/shasum -a 256 "$original" | /usr/bin/awk '{print $1}')" == "$built_hash" ]] \
  || fail 'packager changed the original release executable'
[[ "$(/usr/bin/wc -l < "$strip_log" | /usr/bin/tr -d '[:space:]')" == 1 ]] \
  || fail 'packager did not strip exactly one executable'
[[ "$(/bin/cat "$strip_log")" == *'/.build/.fleck-app.'*'/Fleck.app/Contents/MacOS/Fleck' ]] \
  || fail 'packager stripped a non-staged executable'
/usr/bin/codesign --verify --deep --strict "$packaged_app"
test ! -e "$launch_sentinel" || fail 'packager launched the executable'

packaged_helper="$(/usr/bin/dirname "$packaged")/../SharedSupport/fleck-agent"
for product in Fleck fleck-agent; do
  /usr/bin/grep -Fxq "$product 14.0 27.0" "$swift_log" \
    || fail "packager did not link $product with the active SDK and deployment target"
done
for executable in "$packaged" "$packaged_helper"; do
  stamp="$(/usr/bin/vtool -show-build "$executable" | /usr/bin/awk '
    $1 == "minos" { minos = $2 }
    $1 == "sdk" { sdk = $2 }
    END { print minos " " sdk }')"
  [[ "$stamp" == '14.0 27.0' ]] \
    || fail "packager published $(/usr/bin/basename "$executable") with SDK/minOS ${stamp:-missing}"
done

published_hash="$(/usr/bin/shasum -a 256 "$packaged" | /usr/bin/awk '{print $1}')"
published_receipt_hash="$(/usr/bin/shasum -a 256 "$first_result" | /usr/bin/awk '{print $1}')"

expect_rejection() {
  local label="$1"
  local result_path="$2"
  local log_path="$3"
  local expected_message="$4"
  [[ ! -e "$result_path" ]] || fail "packager wrote a result receipt for $label"
  /usr/bin/grep -Fq "$expected_message" "$log_path" \
    || fail "packager did not reject $label before signing"
  if /usr/bin/grep -Fq 'replacing existing signature' "$log_path"; then
    fail "packager signed the app before rejecting $label"
  fi
  [[ "$(/usr/bin/shasum -a 256 "$packaged" | /usr/bin/awk '{print $1}')" == "$published_hash" ]] \
    || fail "$label replaced the published app"
  [[ "$(/usr/bin/shasum -a 256 "$first_result" | /usr/bin/awk '{print $1}')" == "$published_receipt_hash" ]] \
    || fail "$label replaced the published receipt"
  [[ "$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -name 'Fleck *.app' | /usr/bin/wc -l \
    | /usr/bin/tr -d '[:space:]')" == 1 ]] \
    || fail "$label published an app"
}

while IFS='|' read -r case_name stamp_arguments; do
  rejected_result="$results/rejected-$case_name.json"
  if run_packager "$rejected_result" \
    FLECK_TEST_VTOOL_STAMP="$stamp_arguments" >"$test_root/rejected-$case_name.log" 2>&1; then
    fail "packager published an app with a $case_name linker stamp"
  fi
  expect_rejection "a $case_name linker stamp" "$rejected_result" \
    "$test_root/rejected-$case_name.log" \
    'error: packaged executable SDK/minOS identity does not match'
done <<'CASES'
wrong-sdk|-replace -set-build-version macos 14.0 14.0
wrong-minos|-replace -set-build-version macos 13.0 27.0
missing-stamp|-remove-build-version macos
CASES

helper_only_result="$results/rejected-helper-sdk.json"
if run_packager "$helper_only_result" \
  FLECK_TEST_VTOOL_STAMP='-replace -set-build-version macos 14.0 14.0' \
  FLECK_TEST_VTOOL_STAMP_PRODUCT='fleck-agent' >"$test_root/rejected-helper-sdk.log" 2>&1; then
  fail 'packager published an app whose helper carried a stale SDK stamp'
fi
/usr/bin/grep -Fq 'release/fleck-agent' "$test_root/rejected-helper-sdk.log" \
  || fail 'packager did not reject the helper executable by path'
expect_rejection 'a stale helper SDK stamp' "$helper_only_result" \
  "$test_root/rejected-helper-sdk.log" \
  'error: packaged executable SDK/minOS identity does not match'

if run_packager "$results/rejected-unreadable.json" \
  FLECK_TEST_NON_MACHO=1 >"$test_root/rejected-unreadable.log" 2>&1; then
  fail 'packager published an executable without a readable linker stamp'
fi
/usr/bin/grep -Fq 'found missing' "$test_root/rejected-unreadable.log" \
  || fail 'packager did not reject an unreadable linker stamp as a missing identity'
expect_rejection 'an unreadable linker stamp' "$results/rejected-unreadable.json" \
  "$test_root/rejected-unreadable.log" \
  'error: packaged executable SDK/minOS identity does not match'

if run_packager "$results/rejected-otool-failure.json" \
  FLECK_TEST_OTOOL_FAIL=1 >"$test_root/rejected-otool-failure.log" 2>&1; then
  fail 'packager accepted a failed linker-identity read that still printed a valid identity'
fi
expect_rejection 'a failed linker-identity read' "$results/rejected-otool-failure.json" \
  "$test_root/rejected-otool-failure.log" \
  'error: packaged executable SDK/minOS identity could not be read'

test ! -e "$launch_sentinel" || fail 'a rejected linker stamp launched the executable'

packaged_hash="$(/usr/bin/shasum -a 256 "$packaged" | /usr/bin/awk '{print $1}')"
if run_packager "$results/failed.json" FLECK_TEST_STRIP_FAIL=1 >/dev/null 2>&1; then
  fail 'packager continued after strip failed'
fi
[[ "$(/usr/bin/shasum -a 256 "$packaged" | /usr/bin/awk '{print $1}')" == "$packaged_hash" ]] \
  || fail 'failed strip replaced the existing packaged app'
test ! -e "$launch_sentinel" || fail 'failed strip path launched the executable'

noop_result="$results/noop-strip.json"
run_packager "$noop_result" FLECK_TEST_STRIP_NOOP=1 >/dev/null
noop_app="$("$fixture_root/Scripts/fleck-build-identity.py" read-result \
  --repo "$fixture_root" --result-file "$noop_result" --flavor development)"
noop_debug_entries="$(/usr/bin/nm -pa "$noop_app/Contents/MacOS/Fleck" 2>/dev/null \
  | /usr/bin/awk '$5 == "OSO" {n += 1} END {print n + 0}')"
[[ "$noop_debug_entries" -gt 0 ]] \
  || fail 'no-op strip mutation escaped the published debug-map verification'
/bin/rm -rf "$noop_app" "$noop_result"

test ! -e "$packaged_app/Contents/Frameworks" \
  || fail 'packager embedded an unlinked framework'
sparkle_result="$results/sparkle.json"
run_packager "$sparkle_result" FLECK_TEST_LINK_SPARKLE=1 >/dev/null
sparkle_app="$("$fixture_root/Scripts/fleck-build-identity.py" read-result \
  --repo "$fixture_root" --result-file "$sparkle_result" --flavor development)"
test -f "$sparkle_app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" \
  || fail 'packager omitted a linked framework'
/usr/bin/otool -L "$sparkle_app/Contents/MacOS/Fleck" \
  | /usr/bin/grep -Fq '@executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle ' \
  || fail 'packaged executable does not resolve its embedded framework'
/usr/bin/otool -L "$fixture_root/.build/release/Fleck" \
  | /usr/bin/grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle ' \
  || fail 'packager changed the source executable dependency'
/usr/bin/codesign --verify --deep --strict "$sparkle_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$sparkle_app" "$test_root/sparkle.zip"
/usr/bin/ditto -x -k "$test_root/sparkle.zip" "$test_root/extracted"
extracted_app="$test_root/extracted/$(/usr/bin/basename "$sparkle_app")"
/usr/bin/codesign --verify --deep --strict "$extracted_app"
"$extracted_app/Contents/MacOS/Fleck" \
  || fail 'archive-extracted fixture cannot load the embedded framework'

printf 'build-fleck-app debug-symbol packaging tests passed.\n'
