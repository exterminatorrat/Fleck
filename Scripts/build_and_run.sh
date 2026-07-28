#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Motes"
BUNDLE_ID="com.harryjin.motes"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_INFO_PLIST="$ROOT_DIR/Sources/MenuBarNotesApp/Info.plist"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$SOURCE_INFO_PLIST" "$INFO_PLIST"
chmod +x "$APP_BINARY"
codesign --force --sign - "$APP_BUNDLE" >/dev/null

verify_bundle() {
  plutil -lint "$INFO_PLIST" >/dev/null
  [[ "$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")" == "$BUNDLE_ID" ]]
  [[ -n "$(plutil -extract NSMicrophoneUsageDescription raw -o - "$INFO_PLIST")" ]]
  [[ -n "$(plutil -extract NSSpeechRecognitionUsageDescription raw -o - "$INFO_PLIST")" ]]
  codesign --verify --strict "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    verify_bundle
    open_app
    ;;
  --debug|debug)
    verify_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    verify_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    verify_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    printf 'usage: %s [run|--debug|--logs|--telemetry|--verify]\n' "$0" >&2
    exit 2
    ;;
esac
