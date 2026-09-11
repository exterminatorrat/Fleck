#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly app_destination="$build_root/Fleck.app"
readonly info_plist="$repo_root/Sources/FleckApp/Info.plist"
readonly canonical_mark="$repo_root/website/public/fleck-mark.png"
readonly identity_tool="$script_dir/fleck-build-identity.py"
readonly identity_mode="${FLECK_BUILD_IDENTITY_MODE:-local}"

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
/bin/mkdir -p "$build_root"
readonly identity_capture="$build_root/.fleck-app-build-identity.$$.json"
staging_root=""
cleanup() {
  local exit_code=$?
  trap - EXIT
  if [[ -n "$staging_root" ]]; then
    case "$staging_root" in
      "$build_root/.fleck-app."*)
        /bin/rm -rf -- "$staging_root" || exit_code=1
        ;;
    esac
  fi
  if [[ -f "$identity_capture" && ! -L "$identity_capture" ]]; then
    "$identity_tool" release --capture "$identity_capture" || exit_code=1
    /bin/rm -f -- "$identity_capture" || exit_code=1
  fi
  exit "$exit_code"
}
trap cleanup EXIT
"$identity_tool" begin \
  --repo "$repo_root" \
  --flavor development \
  --configuration Release \
  --mode "$identity_mode" \
  --capture "$identity_capture"

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

staging_root="$(mktemp -d "$build_root/.fleck-app.XXXXXX")"

readonly staged_app="$staging_root/Fleck.app"
/bin/mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/SharedSupport" "$staged_app/Contents/Resources"
/bin/cp "$app_executable" "$staged_app/Contents/MacOS/Fleck"
/bin/cp "$helper_executable" "$staged_app/Contents/SharedSupport/fleck-agent"
/bin/cp "$info_plist" "$staged_app/Contents/Info.plist"
/bin/cp "$canonical_mark" "$staged_app/Contents/Resources/fleck-mark.png"
/usr/bin/plutil -insert FleckDevelopmentAccess -bool true "$staged_app/Contents/Info.plist"
"$identity_tool" stamp \
  --capture "$identity_capture" \
  --plist "$staged_app/Contents/Info.plist"
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
"$identity_tool" finish \
  --capture "$identity_capture" \
  --plist "$staged_app/Contents/Info.plist"

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
