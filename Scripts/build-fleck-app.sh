#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly info_plist="$repo_root/Sources/FleckApp/Info.plist"
readonly canonical_mark="$repo_root/website/public/fleck-mark.png"
readonly identity_tool="$script_dir/fleck-build-identity.py"
readonly identity_mode="${FLECK_BUILD_IDENTITY_MODE:-local}"

result_file=''
if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || "$1" != '--result-file' || -z "$2" ]]; then
    printf 'usage: %s [--result-file ABSOLUTE_PATH]\n' "${0##*/}" >&2
    exit 2
  fi
  result_file="$2"
fi

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
if [[ -n "$result_file" ]]; then
  "$identity_tool" validate-result-path --repo "$repo_root" --result-file "$result_file"
fi
readonly identity_capture="$build_root/.fleck-app-build-identity.$$.json"
staging_root=""
app_destination=""
publication_created=0
published_device=""
published_inode=""
result_identity=""
build_succeeded=0
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
  if (( publication_created != 0 && build_succeeded == 0 )) \
    && [[ -n "$app_destination" && ! -L "$app_destination" && -d "$app_destination" \
      && "$app_destination" == "$build_root"/Fleck\ *.app \
      && "$(/usr/bin/stat -f '%d' "$app_destination" 2>/dev/null || true)" == "$published_device" \
      && "$(/usr/bin/stat -f '%i' "$app_destination" 2>/dev/null || true)" == "$published_inode" ]]; then
    /usr/bin/find "$app_destination" -depth -delete || exit_code=1
  fi
  if [[ -f "$identity_capture" && ! -L "$identity_capture" ]]; then
    "$identity_tool" release --capture "$identity_capture" || exit_code=1
    /bin/rm -f -- "$identity_capture" || exit_code=1
  fi
  if (( exit_code != 0 )) && [[ -n "$result_identity" ]]; then
    "$identity_tool" remove-owned-result \
      --repo "$repo_root" \
      --result-file "$result_file" \
      --identity "$result_identity" || exit_code=1
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
readonly artifact_label="$("$identity_tool" name --capture "$identity_capture")"
app_destination="$build_root/$artifact_label.app"
readonly app_destination
if [[ -e "$app_destination" || -L "$app_destination" ]]; then
  printf 'error: refusing to overwrite existing development app: %s\n' "$app_destination" >&2
  exit 1
fi

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
xcrun strip -S "$staged_app/Contents/MacOS/Fleck"

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
published_device="$(/usr/bin/stat -f '%d' "$staged_app")"
published_inode="$(/usr/bin/stat -f '%i' "$staged_app")"
"$swift_path" -e '
  import Foundation

  let arguments = CommandLine.arguments
  let staged = URL(fileURLWithPath: arguments[1])
  let destination = URL(fileURLWithPath: arguments[2])
  let fileManager = FileManager.default
  guard !fileManager.fileExists(atPath: destination.path) else {
    throw NSError(domain: "FleckDevelopmentPackaging", code: 1)
  }
  try fileManager.moveItem(at: staged, to: destination)
' "$staged_app" "$app_destination"
publication_created=1
if [[ -n "${FLECK_DEVELOPMENT_TEST_REPLACE_AFTER_PUBLICATION:-}" ]]; then
  canonical_tmp="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
  if [[ "$FLECK_DEVELOPMENT_TEST_REPLACE_AFTER_PUBLICATION" != '1' \
    || "$repo_root" != "$canonical_tmp"/* \
    || "$(/bin/cat "$repo_root/.fleck-development-packager-test-fixture" 2>/dev/null || true)" \
      != 'fleck-development-packager-test-fixture-v1' ]]; then
    printf '%s\n' 'error: development publication replacement failpoint is unavailable' >&2
    exit 1
  fi
  /bin/mv "$app_destination" "$build_root/.development-owned-publication.$$"
  /bin/mkdir "$app_destination"
  printf '%s\n' 'replacement sentinel' > "$app_destination/sentinel"
  printf '%s\n' 'error: injected failure after development publication replacement' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_destination"
"$identity_tool" verify \
  --capture "$identity_capture" \
  --plist "$app_destination/Contents/Info.plist"
if [[ -n "$result_file" ]]; then
  result_identity="$("$identity_tool" write-result \
    --capture "$identity_capture" \
    --app "$app_destination" \
    --result-file "$result_file")"
fi
build_succeeded=1

printf 'Built development-signed app bundle: %s\n' "$app_destination"
