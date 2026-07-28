#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly app_destination="$repo_root/.build/Motes.app"
readonly info_plist="$repo_root/Sources/MenuBarNotesApp/Info.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: building Motes.app requires macOS\n' >&2
  exit 2
fi

if ! xcode-select -p >/dev/null 2>&1 \
  || ! xcodebuild -version >/dev/null 2>&1; then
  printf 'error: building Motes.app requires an active Xcode installation\n' >&2
  exit 2
fi

cd "$repo_root"
swift build -c release --product Motes --disable-automatic-resolution
swift build -c release --product motes-agent --disable-automatic-resolution

readonly release_directory="$repo_root/.build/release"
readonly app_executable="$release_directory/Motes"
readonly helper_executable="$release_directory/motes-agent"
for required_file in "$app_executable" "$helper_executable" "$info_plist"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'error: required release input not found: %s\n' "$required_file" >&2
    exit 2
  fi
done

staging_root="$(mktemp -d "$repo_root/.build/.motes-app.XXXXXX")"
readonly staging_root
cleanup() {
  case "$staging_root" in
    "$repo_root/.build/.motes-app."*)
      /bin/rm -rf -- "$staging_root"
      ;;
  esac
}
trap cleanup EXIT

readonly staged_app="$staging_root/Motes.app"
/bin/mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/SharedSupport"
/bin/cp "$app_executable" "$staged_app/Contents/MacOS/Motes"
/bin/cp "$helper_executable" "$staged_app/Contents/SharedSupport/motes-agent"
/bin/cp "$info_plist" "$staged_app/Contents/Info.plist"
/bin/chmod 755 \
  "$staged_app/Contents/MacOS/Motes" \
  "$staged_app/Contents/SharedSupport/motes-agent"

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

printf 'Built unsigned app bundle: %s\n' "$app_destination"
