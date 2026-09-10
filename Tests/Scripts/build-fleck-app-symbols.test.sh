#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly packager="$repo_root/Scripts/build-fleck-app.sh"
readonly test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-app-symbols.XXXXXX")"

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
/bin/mkdir -p \
  "$fixture_root/Scripts" \
  "$fixture_root/Sources/FleckApp" \
  "$fixture_root/website/public" \
  "$fake_bin"
/bin/cp "$packager" "$fixture_root/Scripts/build-fleck-app.sh"
cat > "$fixture_root/Sources/FleckApp/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Fleck</string>
  <key>CFBundleIdentifier</key><string>test.fleck.packager</string>
</dict></plist>
PLIST
printf 'fixture mark\n' > "$fixture_root/website/public/fleck-mark.png"

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
cat > "$fake_bin/swift" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
product=''
while (( $# > 0 )); do
  if [[ "$1" == '--product' ]]; then
    product="$2"
    break
  fi
  shift
done
/bin/mkdir -p .build/release
case "$product" in
  Fleck)
    printf '#!/bin/sh\nDEBUG_SYMBOLS\n/bin/touch %q\n' "$FLECK_TEST_LAUNCH_SENTINEL" > .build/release/Fleck
    /bin/chmod 755 .build/release/Fleck
    ;;
  fleck-agent)
    printf '#!/bin/sh\nexit 0\n' > .build/release/fleck-agent
    /bin/chmod 755 .build/release/fleck-agent
    ;;
  *) exit 2 ;;
esac
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
if [[ "$1" == '--find' && "$2" == 'swift' ]]; then
  printf '%s\n' "$FLECK_TEST_FAKE_BIN/move-staged"
  exit 0
fi
if [[ "$1" == 'strip' && "$2" == '-S' && $# == 3 ]]; then
  printf '%s\n' "$3" >> "$FLECK_TEST_STRIP_LOG"
  [[ "${FLECK_TEST_STRIP_FAIL:-0}" != 1 ]] || exit 42
  /usr/bin/sed -i '' '/^DEBUG_SYMBOLS$/d' "$3"
  exit 0
fi
exit 2
SCRIPT
/bin/chmod 755 "$fake_bin"/* "$fixture_root/Scripts/build-fleck-app.sh"

run_packager() {
  /usr/bin/env \
    PATH="$fake_bin:/usr/bin:/bin" \
    FLECK_TEST_FAKE_BIN="$fake_bin" \
    FLECK_TEST_LAUNCH_SENTINEL="$launch_sentinel" \
    FLECK_TEST_STRIP_LOG="$strip_log" \
    "$@" \
    "$fixture_root/Scripts/build-fleck-app.sh"
}

run_packager >/dev/null
original="$fixture_root/.build/release/Fleck"
packaged="$fixture_root/.build/Fleck.app/Contents/MacOS/Fleck"
test -f "$original"
test -f "$packaged"
/usr/bin/grep -Fq 'DEBUG_SYMBOLS' "$original" \
  || fail 'packager changed the original release executable'
if /usr/bin/grep -Fq 'DEBUG_SYMBOLS' "$packaged"; then
  fail 'packager left debug symbols in the staged executable'
fi
[[ "$(/usr/bin/wc -l < "$strip_log" | /usr/bin/tr -d '[:space:]')" == 1 ]] \
  || fail 'packager did not strip exactly one executable'
[[ "$(/bin/cat "$strip_log")" == *'/.build/.fleck-app.'*'/Fleck.app/Contents/MacOS/Fleck' ]] \
  || fail 'packager stripped a non-staged executable'
/usr/bin/codesign --verify --deep --strict "$fixture_root/.build/Fleck.app"
test ! -e "$launch_sentinel" || fail 'packager launched the executable'

packaged_hash="$(/usr/bin/shasum -a 256 "$packaged" | /usr/bin/awk '{print $1}')"
if run_packager FLECK_TEST_STRIP_FAIL=1 >/dev/null 2>&1; then
  fail 'packager continued after strip failed'
fi
[[ "$(/usr/bin/shasum -a 256 "$packaged" | /usr/bin/awk '{print $1}')" == "$packaged_hash" ]] \
  || fail 'failed strip replaced the existing packaged app'
test ! -e "$launch_sentinel" || fail 'failed strip path launched the executable'

printf 'build-fleck-app debug-symbol packaging tests passed.\n'
