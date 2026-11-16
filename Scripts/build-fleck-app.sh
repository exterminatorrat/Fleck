#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly info_plist="$repo_root/Sources/FleckApp/Info.plist"
readonly canonical_mark="$repo_root/Assets/fleck-mark.png"
readonly canonical_app_icon="$repo_root/Assets/FleckAppIcon.icns"
readonly canonical_dark_app_icon="$repo_root/Assets/FleckAppIconDark.icns"
readonly identity_tool="$script_dir/fleck-build-identity.py"
readonly inputs_tool="$script_dir/fleck-build-inputs.py"
readonly identity_mode="${FLECK_BUILD_IDENTITY_MODE:-local}"

usage() {
  printf 'usage: %s [--result-file ABSOLUTE_PATH] [--prebuilt-inputs ABSOLUTE_RECEIPT --input-receipt-sha256 SHA256]\n' \
    "${0##*/}" >&2
  exit 2
}

result_file=''
prebuilt_inputs=''
prebuilt_inputs_sha256=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --result-file)
      [[ -z "$result_file" && $# -ge 2 && -n "$2" ]] || usage
      result_file="$2"
      shift 2
      ;;
    --prebuilt-inputs)
      [[ -z "$prebuilt_inputs" && $# -ge 2 && -n "$2" ]] || usage
      prebuilt_inputs="$2"
      shift 2
      ;;
    --input-receipt-sha256)
      [[ -z "$prebuilt_inputs_sha256" && $# -ge 2 && -n "$2" ]] || usage
      prebuilt_inputs_sha256="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done
if [[ -n "$prebuilt_inputs" && -z "$prebuilt_inputs_sha256" ]] \
  || [[ -z "$prebuilt_inputs" && -n "$prebuilt_inputs_sha256" ]]; then
  usage
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

readonly deployment_target='14.0'
active_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
case "$active_sdk_version" in
  '' | *[!0-9.]*)
    printf 'error: could not determine the active macOS SDK version\n' >&2
    exit 2
    ;;
esac
readonly active_sdk_version
expected_linker_sdk="$active_sdk_version"

cd "$repo_root"
/bin/mkdir -p "$build_root"
if [[ -n "$result_file" ]]; then
  "$identity_tool" validate-result-path --repo "$repo_root" --result-file "$result_file"
fi
readonly identity_capture="$build_root/.fleck-app-build-identity.$$.json"
staging_root=""
prebuilt_stage=""
prebuilt_app_executable=''
prebuilt_helper_executable=''
prebuilt_sparkle_framework=''
input_receipt_id=''
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
  if [[ -n "$prebuilt_stage" ]]; then
    case "$prebuilt_stage" in
      "$build_root/.fleck-inputs."*)
        /bin/rm -rf -- "$prebuilt_stage" || exit_code=1
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

verify_linker_identity() {
  local executable="$1"
  local inspection identity
  if ! inspection="$(xcrun otool -l "$executable" 2>/dev/null)"; then
    printf 'error: packaged executable SDK/minOS identity could not be read: %s\n' \
      "$executable" >&2
    exit 1
  fi
  identity="$(printf '%s\n' "$inspection" | /usr/bin/awk '
    $1 == "cmd" {
      in_build_version = ($2 == "LC_BUILD_VERSION")
      next
    }
    in_build_version && $1 == "minos" { minos = $2 }
    in_build_version && $1 == "sdk" { sdk = $2; in_build_version = 0 }
    END {
      if (minos != "" && sdk != "") {
        print minos " " sdk
      }
    }
  ')"
  if [[ "$identity" != "$deployment_target $expected_linker_sdk" ]]; then
    printf 'error: packaged executable SDK/minOS identity does not match: %s (found %s, expected %s %s)\n' \
      "$executable" "${identity:-missing}" "$deployment_target" "$expected_linker_sdk" >&2
    exit 1
  fi
}
if [[ -n "$prebuilt_inputs" ]]; then
  prebuilt_stage="$build_root/.fleck-inputs.$$"
  "$inputs_tool" verify \
    --receipt "$prebuilt_inputs" \
    --receipt-sha256 "$prebuilt_inputs_sha256" \
    --repo "$repo_root" \
    --staging "$prebuilt_stage"
  prebuilt_app_executable="$prebuilt_stage/Fleck"
  prebuilt_helper_executable="$prebuilt_stage/fleck-agent"
  if [[ -d "$prebuilt_stage/Sparkle.framework" ]]; then
    prebuilt_sparkle_framework="$prebuilt_stage/Sparkle.framework"
  fi
  input_receipt_id="$(/usr/bin/plutil -extract receiptID raw -o - "$prebuilt_inputs")"
  expected_linker_sdk="$(
    /usr/bin/plutil -extract toolchain.sdkVersion raw -o - "$prebuilt_inputs"
  )"
  case "$expected_linker_sdk" in
    '' | *[!0-9.]*)
      printf 'error: compile input receipt records no usable SDK version\n' >&2
      exit 1
      ;;
  esac
fi

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

readonly release_directory="$repo_root/.build/release"
if [[ -z "$prebuilt_inputs" ]]; then
  swift build -c release --product Fleck --disable-automatic-resolution \
    -Xlinker -platform_version -Xlinker macos \
    -Xlinker "$deployment_target" -Xlinker "$active_sdk_version"
  swift build -c release --product fleck-agent --disable-automatic-resolution \
    -Xlinker -platform_version -Xlinker macos \
    -Xlinker "$deployment_target" -Xlinker "$active_sdk_version"
  readonly app_executable="$release_directory/Fleck"
  readonly helper_executable="$release_directory/fleck-agent"
else
  readonly app_executable="$prebuilt_app_executable"
  readonly helper_executable="$prebuilt_helper_executable"
fi
for required_file in \
  "$app_executable" \
  "$helper_executable" \
  "$info_plist" \
  "$canonical_mark" \
  "$canonical_app_icon" \
  "$canonical_dark_app_icon"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'error: required release input not found: %s\n' "$required_file" >&2
    exit 2
  fi
done

verify_linker_identity "$app_executable"
verify_linker_identity "$helper_executable"

staging_root="$(mktemp -d "$build_root/.fleck-app.XXXXXX")"

readonly staged_app="$staging_root/Fleck.app"
/bin/mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/SharedSupport" "$staged_app/Contents/Resources"
/bin/cp "$app_executable" "$staged_app/Contents/MacOS/Fleck"
/bin/cp "$helper_executable" "$staged_app/Contents/SharedSupport/fleck-agent"
/bin/cp "$info_plist" "$staged_app/Contents/Info.plist"
/bin/cp "$canonical_mark" "$staged_app/Contents/Resources/fleck-mark.png"
/bin/cp "$canonical_app_icon" "$staged_app/Contents/Resources/FleckAppIcon.icns"
/bin/cp "$canonical_dark_app_icon" "$staged_app/Contents/Resources/FleckAppIconDark.icns"
/usr/bin/plutil -insert FleckDevelopmentAccess -bool true "$staged_app/Contents/Info.plist"
if [[ -n "$prebuilt_inputs" ]]; then
  /bin/cp "$prebuilt_inputs" "$staged_app/Contents/Resources/FleckBuildInputs.json"
  /usr/bin/plutil -insert FleckInputReceiptID -string "$input_receipt_id" \
    "$staged_app/Contents/Info.plist"
  /usr/bin/plutil -insert FleckInputReceiptSHA256 -string "$prebuilt_inputs_sha256" \
    "$staged_app/Contents/Info.plist"
  if [[ "$(/usr/bin/shasum -a 256 "$staged_app/Contents/Resources/FleckBuildInputs.json" \
    | /usr/bin/awk '{print $1}')" != "$prebuilt_inputs_sha256" ]]; then
    printf '%s\n' 'error: staged compile input receipt does not match the trusted transfer digest' >&2
    exit 1
  fi
fi
"$identity_tool" stamp \
  --capture "$identity_capture" \
  --plist "$staged_app/Contents/Info.plist"
/bin/chmod 755 \
  "$staged_app/Contents/MacOS/Fleck" \
  "$staged_app/Contents/SharedSupport/fleck-agent"
verify_linker_identity "$staged_app/Contents/MacOS/Fleck"
verify_linker_identity "$staged_app/Contents/SharedSupport/fleck-agent"
linked_libraries="$(xcrun otool -L "$app_executable")"
staged_sparkle=''
if /usr/bin/grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle ' <<<"$linked_libraries"; then
  if [[ -n "$prebuilt_inputs" ]]; then
    sparkle_framework="$prebuilt_sparkle_framework"
    [[ -n "$sparkle_framework" ]] || {
      printf '%s\n' 'error: prebuilt inputs do not include the linked Sparkle framework' >&2
      exit 1
    }
  else
    sparkle_framework="$build_root/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    [[ -f "$sparkle_framework/Versions/B/Sparkle" ]] || {
      printf '%s\n' 'error: linked Sparkle framework is missing from the resolved build artifacts' >&2
      exit 1
    }
  fi
  /bin/mkdir -p "$staged_app/Contents/Frameworks"
  staged_sparkle="$staged_app/Contents/Frameworks/Sparkle.framework"
  /usr/bin/ditto "$sparkle_framework" "$staged_sparkle"
  xcrun install_name_tool -change \
    '@rpath/Sparkle.framework/Versions/B/Sparkle' \
    '@executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle' \
    "$staged_app/Contents/MacOS/Fleck"
fi
xcrun strip -S "$staged_app/Contents/MacOS/Fleck"

readonly bundle_identifier="$(
  /usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    "$staged_app/Contents/Info.plist"
)"
readonly designated_requirement="=designated => identifier \"$bundle_identifier\""
if [[ -n "$staged_sparkle" ]]; then
  for nested_code in \
    "$staged_sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$staged_sparkle/Versions/B/XPCServices/Installer.xpc" \
    "$staged_sparkle/Versions/B/Autoupdate" \
    "$staged_sparkle/Versions/B/Updater.app"; do
    [[ -e "$nested_code" ]] || continue
    /usr/bin/codesign --force --sign - --preserve-metadata=entitlements "$nested_code"
  done
  /usr/bin/codesign --force --sign - "$staged_sparkle"
fi
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

published_device="$(/usr/bin/stat -f '%d' "$staged_app")"
published_inode="$(/usr/bin/stat -f '%i' "$staged_app")"
if [[ -n "$prebuilt_inputs" ]]; then
  /bin/mv -n "$staged_app" "$app_destination"
  if [[ -e "$staged_app" || -L "$staged_app" || ! -d "$app_destination" \
    || -L "$app_destination" ]]; then
    printf 'error: could not publish the staged app atomically without overwriting %s\n' \
      "$app_destination" >&2
    exit 1
  fi
else
  readonly swift_path="$(xcrun --find swift)"
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
fi
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
if [[ -n "$prebuilt_inputs" ]]; then
  if [[ "$(/usr/bin/shasum -a 256 "$app_destination/Contents/Resources/FleckBuildInputs.json" \
    | /usr/bin/awk '{print $1}')" != "$prebuilt_inputs_sha256" ]]; then
    printf '%s\n' 'error: published compile input receipt does not match the trusted transfer digest' >&2
    exit 1
  fi
  if [[ "$(/usr/bin/plutil -extract FleckInputReceiptSHA256 raw -o - \
    "$app_destination/Contents/Info.plist")" != "$prebuilt_inputs_sha256" ]]; then
    printf '%s\n' 'error: published bundle plist does not bind the trusted transfer digest' >&2
    exit 1
  fi
fi
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
