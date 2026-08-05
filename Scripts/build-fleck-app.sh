#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly app_destination="$repo_root/.build/Fleck.app"
readonly info_plist="$repo_root/Sources/FleckApp/Info.plist"
readonly canonical_mark="$repo_root/website/public/fleck-mark.png"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: building Fleck.app requires macOS\n' >&2
  exit 2
fi

if ! xcode-select -p >/dev/null 2>&1 \
  || ! xcodebuild -version >/dev/null 2>&1; then
  printf 'error: building Fleck.app requires an active Xcode installation\n' >&2
  exit 2
fi

cd "$repo_root"
swift build -c release --product Fleck --disable-automatic-resolution
swift build -c release --product fleck-agent --disable-automatic-resolution

readonly release_directory="$repo_root/.build/release"
readonly app_executable="$release_directory/Fleck"
readonly helper_executable="$release_directory/fleck-agent"
for required_file in "$app_executable" "$helper_executable" "$info_plist" "$canonical_mark"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'error: required release input not found: %s\n' "$required_file" >&2
    exit 2
  fi
done

staging_root="$(mktemp -d "$repo_root/.build/.fleck-app.XXXXXX")"
readonly staging_root
cleanup() {
  case "$staging_root" in
    "$repo_root/.build/.fleck-app."*)
      /bin/rm -rf -- "$staging_root"
      ;;
  esac
}
trap cleanup EXIT

readonly staged_app="$staging_root/Fleck.app"
/bin/mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/SharedSupport" "$staged_app/Contents/Resources"
/bin/cp "$app_executable" "$staged_app/Contents/MacOS/Fleck"
/bin/cp "$helper_executable" "$staged_app/Contents/SharedSupport/fleck-agent"
/bin/cp "$info_plist" "$staged_app/Contents/Info.plist"
/bin/cp "$canonical_mark" "$staged_app/Contents/Resources/fleck-mark.png"
/bin/chmod 755 \
  "$staged_app/Contents/MacOS/Fleck" \
  "$staged_app/Contents/SharedSupport/fleck-agent"

readonly bundle_identifier="$(
  /usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    "$staged_app/Contents/Info.plist"
)"
readonly designated_requirement="=designated => identifier \"$bundle_identifier\""
/usr/bin/codesign --force --sign - \
  --identifier "$bundle_identifier.agent" \
  "$staged_app/Contents/SharedSupport/fleck-agent"
/usr/bin/codesign --force --sign - \
  --identifier "$bundle_identifier" \
  --requirements "$designated_requirement" \
  "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

readonly swift_path="$(xcrun --find swift)"
"$swift_path" -e '
  import Foundation

  let arguments = CommandLine.arguments
  let staged = URL(fileURLWithPath: arguments[1])
  let destination = URL(fileURLWithPath: arguments[2])
  let fileManager = FileManager.default
  if fileManager.fileExists(atPath: destination.path) {
    _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
  } else {
    try fileManager.moveItem(at: staged, to: destination)
  }
' "$staged_app" "$app_destination"

printf 'Built development-signed app bundle: %s\n' "$app_destination"
