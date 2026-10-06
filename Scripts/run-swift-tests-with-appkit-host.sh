#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  printf 'usage: %s <package-root> <scratch-path-or-empty> <anchored-test-identifier-regex>\n' \
    "${0##*/}" >&2
  exit 2
fi

if [[ ${FLECK_NATIVE_CAPTURE_QA+x} ]]; then
  case "$FLECK_NATIVE_CAPTURE_QA" in
    0|1) ;;
    *)
      printf '%s\n' 'error: FLECK_NATIVE_CAPTURE_QA must be unset, 0, or 1' >&2
      exit 2
      ;;
  esac
fi

readonly package_root="$1"
readonly scratch_path="$2"
readonly identifier_regex="$3"
readonly host_source="$package_root/Tests/Support/AppKitTestMain.swift"

[[ "$(/usr/bin/uname -s)" = Darwin ]] || {
  printf '%s\n' 'error: the AppKit Swift test host requires macOS' >&2
  exit 1
}
[[ -f "$host_source" && ! -L "$host_source" ]] || {
  printf 'error: AppKit Swift test host source is missing or unsafe: %s\n' \
    "$host_source" >&2
  exit 1
}

xcrun_path="$(command -v xcrun || true)"
[[ -n "$xcrun_path" && -x "$xcrun_path" ]] || {
  printf '%s\n' 'error: xcrun is required to build the AppKit Swift test host' >&2
  exit 1
}

set +e
sdk_path="$("$xcrun_path" --sdk macosx --show-sdk-path)"
sdk_status=$?
platform_path="$("$xcrun_path" --sdk macosx --show-sdk-platform-path)"
platform_status=$?
swiftc_path="$("$xcrun_path" --sdk macosx --find swiftc)"
swiftc_status=$?
set -e
if (( sdk_status != 0 || platform_status != 0 || swiftc_status != 0 )) ||
  [[ ! -d "$sdk_path" || ! -d "$platform_path" || ! -x "$swiftc_path" ]]; then
  printf '%s\n' 'error: failed to resolve the selected macOS SDK and Swift compiler' >&2
  exit 1
fi
readonly sdk_path platform_path swiftc_path
if ! sdk_version="$(/usr/bin/plutil -extract Version raw -o - "$sdk_path/SDKSettings.plist")" ||
  [[ ! "$sdk_version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  printf 'error: failed to resolve the selected macOS SDK version from %s/SDKSettings.plist\n' \
    "$sdk_path" >&2
  exit 1
fi
if ! target_info="$("$swiftc_path" -print-target-info -sdk "$sdk_path")"; then
  printf '%s\n' 'error: failed to resolve the selected Swift compiler target information' >&2
  exit 1
fi
if ! target_triple="$(printf '%s\n' "$target_info" | \
  /usr/bin/plutil -extract target.triple raw -o - -)"; then
  printf '%s\n' 'error: failed to resolve the selected Swift compiler target triple' >&2
  exit 1
fi
macos_target_pattern='^[^-]+-apple-macosx[0-9]+([.][0-9]+)+$'
if [[ ! "$target_triple" =~ $macos_target_pattern ]]; then
  printf 'error: selected Swift compiler reported an unsupported macOS target triple: %s\n' \
    "$target_triple" >&2
  exit 1
fi
deployment_target="${target_triple##*-apple-macosx}"
readonly sdk_version deployment_target
readonly framework_path="$platform_path/Developer/Library/Frameworks"
[[ -d "$framework_path/Testing.framework" ]] || {
  printf 'error: selected macOS platform has no Testing framework: %s\n' \
    "$framework_path/Testing.framework" >&2
  exit 1
}

readonly open_path="${FLECK_TEST_APPKIT_OPEN_PATH:-/usr/bin/open}"
readonly sample_path="${FLECK_TEST_APPKIT_SAMPLE_PATH:-/usr/bin/sample}"
readonly codesign_path="${FLECK_TEST_APPKIT_CODESIGN_PATH:-/usr/bin/codesign}"
readonly host_watchdog_seconds="${FLECK_TEST_APPKIT_WATCHDOG_SECONDS:-2700}"
if [[ ! -x "$open_path" || ! -x "$sample_path" || ! -x "$codesign_path" ]]; then
  printf '%s\n' 'error: LaunchServices, process sampling, and code-signing tools are required' >&2
  exit 1
fi
if [[ ! "$host_watchdog_seconds" =~ ^[1-9][0-9]{0,3}$ ]] ||
  (( host_watchdog_seconds > 2700 )); then
  printf '%s\n' 'error: AppKit test host watchdog interval must be between 1 and 2700 seconds' >&2
  exit 1
fi

state_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-appkit-test-host.XXXXXX")"
readonly state_dir
readonly expected_host_app="$state_dir/AppKitTestHost.app"
readonly expected_host_contents="$expected_host_app/Contents"
readonly expected_host_binary="$expected_host_contents/MacOS/AppKitTestHost"
readonly expected_host_resource_root="$expected_host_contents/Resources"
readonly expected_host_resource_bundle="$expected_host_resource_root/Fleck_FleckApp.bundle"
readonly candidate_resource_names=(
  EnhancedModelManifest.json
  GemmaCleanupModelManifest.json
  GemmaCleanupNotice.md
  ThirdPartyNotices.md
)
candidate_graph_selected=0
if [[ "${FLECK_ENHANCED_CANDIDATE:-}" = 1 ]]; then
  candidate_graph_selected=1
fi
host_app="$expected_host_app"
host_binary="$expected_host_binary"
readonly host_environment_names=(
  HOME TMPDIR PATH LANG LC_ALL LC_CTYPE
  AGENT_ACTIVITY_CAPTURE_DIR FLECK_AGENT_ACTIVITY_CAPTURE_DIR
  FLECK_AGENT_ACTIVITY_CAPTURE_PREFIX FLECK_CONTROL_FOCUS_CAPTURE_DIR
  FLECK_DICTATION_BANNER_CAPTURE_DIR FLECK_DICTIONARY_SETTINGS_CAPTURE_DIR
  FLECK_EDITOR_EVIDENCE_DIR FLECK_ENHANCED_CANDIDATE
  FLECK_FILE_REFERENCE_EVIDENCE_DIR FLECK_FOLDER_CAPTURE_DIR
  FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC
  FLECK_FONT_PICKER_ALIGNMENT_EVIDENCE_DIRECTORY
  FLECK_FONT_PICKER_EVIDENCE_DIRECTORY FLECK_GLASS_SYNTHETIC_CAPTURE_DIR
  FLECK_NATIVE_CAPTURE_QA
  FLECK_LAYOUT_EVIDENCE_DIR FLECK_MODEL_LIBRARY_VISUAL_CAPTURE_DIRECTORY
  FLECK_PACKET_C_CAPTURE_DIR FLECK_PINNED_CHROME_CAPTURE_PATH
  FLECK_RAIL_CAPTURE_DIR FLECK_SEARCH_TEST_CAPTURE_DIR
  FLECK_SETTINGS_MODELS_CAPTURE_DIR FLECK_SETTINGS_REDUCE_TRANSPARENCY_CAPTURE_DIR
  FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR FLECK_SETTINGS_WINDOW_CAPTURE_DIR
  FLECK_THEME_PICKER_CAPTURE_DIR FLECK_TOOLBAR_WINDOW_CAPTURE
  FLECK_WAVEFORM_CAPTURE_DIR UNFILED_CAPTURE_DIR
)
active_open_pid=''
active_watchdog_pid=''
active_completion_path=''
active_claim_path=''
active_host_log_path=''
active_host_pid_path=''
active_host_phase_path=''
active_host_nonce=''

directory_entry_count() {
  local directory="$1" entry count=0
  for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    count=$((count + 1))
  done
  printf '%s\n' "$count"
}

verify_configured_host_resources() {
  local configured_contents="$1"
  local configured_resource_root="$configured_contents/Resources"
  local configured_resource_bundle="$configured_resource_root/Fleck_FleckApp.bundle"
  local resource_name

  if (( ! candidate_graph_selected )); then
    if [[ -e "$configured_resource_root" || -L "$configured_resource_root" ]]; then
      printf '%s\n' 'error: configured AppKit test host has unexpected resources for the ordinary test graph' >&2
      return 1
    fi
    return 0
  fi

  if [[ ! -d "$configured_resource_root" || -L "$configured_resource_root" ||
    ! -d "$configured_resource_bundle" || -L "$configured_resource_bundle" ]]; then
    printf '%s\n' 'error: configured AppKit test host candidate resources are missing or unsafe' >&2
    return 1
  fi
  if [[ "$(directory_entry_count "$configured_resource_root")" != 1 ||
    "$(directory_entry_count "$configured_resource_bundle")" != "${#candidate_resource_names[@]}" ]]; then
    printf '%s\n' 'error: configured AppKit test host candidate resources do not match the current build' >&2
    return 1
  fi
  for resource_name in "${candidate_resource_names[@]}"; do
    if [[ ! -f "$configured_resource_bundle/$resource_name" ||
      -L "$configured_resource_bundle/$resource_name" ]] ||
      ! /usr/bin/cmp -s "$expected_host_resource_bundle/$resource_name" \
        "$configured_resource_bundle/$resource_name"; then
      printf 'error: configured AppKit test host candidate resource does not match the current build: %s\n' \
        "$resource_name" >&2
      return 1
    fi
  done
}

read_owned_host_pid() {
  [[ -f "$active_host_pid_path" && ! -L "$active_host_pid_path" ]] || return 1
  local nonce pid extra
  IFS=$'\t' read -r nonce pid extra < "$active_host_pid_path" || return 1
  [[ "$nonce" = "$active_host_nonce" && "$pid" =~ ^[1-9][0-9]*$ && -z "$extra" ]] ||
    return 1
  printf '%s\n' "$pid"
}

owned_host_is_running() {
  local pid="$1"
  /bin/kill -0 "$pid" 2>/dev/null || return 1
  local process_state process_command
  process_state="$(/bin/ps -p "$pid" -o stat= 2>/dev/null | /usr/bin/tr -d '[:space:]' || true)"
  [[ -n "$process_state" && "$process_state" != *Z* ]] || return 1
  process_command="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$process_command" == *"$host_binary"* ]]
}

capture_and_terminate_owned_host() {
  local reason="$1"
  [[ -n "$active_host_pid_path" ]] || return 0
  /bin/mkdir "$active_claim_path/claimed" 2>/dev/null || return 0

  local pid phase
  if ! pid="$(read_owned_host_pid)"; then
    printf 'error: could not verify the owned AppKit host PID during %s\n' \
      "$reason" >&2
    return 1
  fi
  if ! owned_host_is_running "$pid"; then
    return 0
  fi

  phase='unknown'
  if [[ -f "$active_host_phase_path" && ! -L "$active_host_phase_path" ]]; then
    phase="$(/bin/cat "$active_host_phase_path" 2>/dev/null || printf '%s' unknown)"
  fi
  printf 'error: AppKit test host %s; last phase: %s; owned PID: %s\n' \
    "$reason" "$phase" "$pid" >&2
  if "$sample_path" "$pid" 1 1 -mayDie -file "$active_claim_path/stack" \
    >/dev/null 2>&1; then
    /bin/cat "$active_claim_path/stack" >&2 2>/dev/null || true
  else
    printf '%s\n' 'error: failed to capture the AppKit test host stack' >&2
  fi
  if [[ -f "$active_host_log_path" && ! -L "$active_host_log_path" ]]; then
    printf '%s\n' '--- last AppKit test host output ---' >&2
    /usr/bin/tail -n 25 "$active_host_log_path" >&2 || true
  fi

  /bin/kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    owned_host_is_running "$pid" || return 0
    /bin/sleep 0.1
  done
  if owned_host_is_running "$pid"; then
    /bin/kill -KILL "$pid" 2>/dev/null || true
  fi
}

terminate_open_child() {
  local pid="$1"
  /bin/kill -0 "$pid" 2>/dev/null || return 0
  /bin/kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    /bin/kill -0 "$pid" 2>/dev/null || return 0
    /bin/sleep 0.1
  done
  /bin/kill -KILL "$pid" 2>/dev/null || true
}

watch_host() {
  local open_pid="$1"
  local started_seconds="$SECONDS"
  trap '' HUP INT TERM
  while (( SECONDS - started_seconds < host_watchdog_seconds )); do
    [[ -e "$active_completion_path" ]] && return 0
    /bin/kill -0 "$open_pid" 2>/dev/null || return 0
    /bin/sleep 1
  done
  [[ -e "$active_completion_path" ]] && return 0
  : > "$active_claim_path/timeout"
  capture_and_terminate_owned_host "exceeded the ${host_watchdog_seconds}s watchdog" || true
  terminate_open_child "$open_pid"
}

finish_active_run() {
  [[ -n "$active_completion_path" ]] || return 0
  local pid
  if [[ -n "$active_host_pid_path" ]] &&
    pid="$(read_owned_host_pid 2>/dev/null)" && owned_host_is_running "$pid"; then
    capture_and_terminate_owned_host 'was interrupted' || true
  fi
  if [[ ! -e "$active_completion_path" ]]; then
    : > "$active_completion_path"
  fi
  if [[ -n "$active_open_pid" ]]; then
    terminate_open_child "$active_open_pid"
    wait "$active_open_pid" 2>/dev/null || true
  fi
  if [[ -n "$active_watchdog_pid" ]]; then
    wait "$active_watchdog_pid" 2>/dev/null || true
  fi
  active_open_pid=''
  active_watchdog_pid=''
  active_completion_path=''
  active_claim_path=''
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  set +e
  finish_active_run
  /bin/rm -rf -- "$state_dir"
  exec 8>&-
  exit "$status"
}

handle_signal() {
  local status="$1"
  {
    printf 'error: interrupted while running the AppKit test host (status %s)\n' \
      "$status" >&2
    finish_active_run
  } 1>&8 2>&8
  exit "$status"
}

exec 8>&2
trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

launch_host() {
  local mode="$1"
  shift
  local stage_nonce stage_root configuration_path receipt_path pid_path phase_path
  local host_log_path open_log_path completion_path claim_path
  local open_status watchdog_status receipt_nonce receipt_pid receipt_status receipt_extra
  local host_pid

  stage_nonce="$(/usr/bin/uuidgen | /usr/bin/tr -d '\r\n')"
  [[ "$stage_nonce" =~ ^[[:xdigit:]-]{36}$ ]] || {
    printf '%s\n' 'error: failed to generate AppKit host invocation nonce' >&2
    return 1
  }
  stage_root="$state_dir/$mode"
  /bin/mkdir -m 700 "$stage_root"
  configuration_path="$stage_root/host-configuration"
  receipt_path="$stage_root/completion-receipt"
  pid_path="$stage_root/host-process"
  phase_path="$stage_root/host-phase"
  host_log_path="$stage_root/host.log"
  open_log_path="$stage_root/open.log"
  completion_path="$stage_root/complete"
  claim_path="$stage_root/watchdog"
  /bin/mkdir -m 700 "$claim_path"
  : > "$host_log_path"
  : > "$open_log_path"
  {
    printf '%s\0' "$stage_nonce" "$receipt_path" "$pid_path" "$phase_path" \
      "$host_log_path"
  } > "$configuration_path"

  active_completion_path="$completion_path"
  active_claim_path="$claim_path"
  active_host_log_path="$host_log_path"
  active_host_pid_path="$pid_path"
  active_host_phase_path="$phase_path"
  active_host_nonce="$stage_nonce"

  local open_arguments=(-n -W)
  if [[ "$mode" = list ]]; then
    open_arguments+=(-g)
  fi
  open_arguments+=(-a "$host_app")
  local environment_name
  for environment_name in "${host_environment_names[@]}"; do
    if [[ ${!environment_name+x} ]]; then
      open_arguments+=(--env "$environment_name=${!environment_name}")
    fi
  done
  open_arguments+=(--args "$bundle_binary" "$@" --host-config "$configuration_path")

  "$open_path" "${open_arguments[@]}" 8>&- > "$open_log_path" 2>&1 &
  active_open_pid=$!
  watch_host "$active_open_pid" 8>&- &
  active_watchdog_pid=$!

  set +e
  wait "$active_open_pid"
  open_status=$?
  set -e
  active_open_pid=''
  : > "$completion_path"
  set +e
  wait "$active_watchdog_pid"
  watchdog_status=$?
  set -e
  active_watchdog_pid=''

  if [[ -s "$open_log_path" ]]; then
    /bin/cat "$open_log_path" >&2 || return 1
  fi
  if [[ -f "$host_log_path" && ! -L "$host_log_path" ]]; then
    if [[ "$mode" = list ]] && (( open_status != 0 )); then
      /bin/cat "$host_log_path" >&2 || return 1
    else
      /bin/cat "$host_log_path" || return 1
    fi
  fi
  if [[ -e "$claim_path/timeout" ]]; then
    printf '%s\n' 'error: AppKit test host watchdog terminated the owned host' >&2
    return 124
  fi
  if (( watchdog_status != 0 )); then
    printf '%s\n' 'error: AppKit test host watchdog failed' >&2
    return 1
  fi
  if (( open_status != 0 )); then
    printf 'error: /usr/bin/open -W returned status %s\n' "$open_status" >&2
    return "$open_status"
  fi

  if ! host_pid="$(read_owned_host_pid)"; then
    printf '%s\n' 'error: AppKit test host did not write a valid owned-process marker' >&2
    return 1
  fi
  if owned_host_is_running "$host_pid"; then
    printf 'error: /usr/bin/open -W returned while owned AppKit test host PID %s was still running\n' \
      "$host_pid" >&2
    return 1
  fi
  if [[ ! -f "$receipt_path" || -L "$receipt_path" ]]; then
    printf '%s\n' 'error: AppKit test host completion receipt is missing' >&2
    return 1
  fi
  IFS=$'\t' read -r receipt_nonce receipt_pid receipt_status receipt_extra \
    < "$receipt_path" || {
    printf '%s\n' 'error: AppKit test host completion receipt is unreadable' >&2
    return 1
  }
  if [[ "$receipt_nonce" != "$stage_nonce" || "$receipt_pid" != "$host_pid" ||
    ! $receipt_status =~ ^[0-9]{1,3}$ || -n "$receipt_extra" ]]; then
    printf '%s\n' 'error: AppKit test host completion receipt does not match this invocation' >&2
    return 1
  fi
  if (( receipt_status > 255 )); then
    printf '%s\n' 'error: AppKit test host returned an invalid Swift Testing status' >&2
    return 1
  fi
  if (( receipt_status != 0 )); then
    printf 'error: Swift Testing returned status %s\n' "$receipt_status" >&2
    return "$receipt_status"
  fi

  active_host_log_path=''
  active_host_pid_path=''
  active_host_phase_path=''
  active_host_nonce=''
}

build_arguments=(build --build-tests --disable-automatic-resolution)
bin_arguments=(build --show-bin-path --disable-automatic-resolution)
if [[ -n "$scratch_path" ]]; then
  build_arguments+=(--scratch-path "$scratch_path")
  bin_arguments+=(--scratch-path "$scratch_path")
fi

set +e
(
  cd "$package_root"
  swift "${build_arguments[@]}"
)
build_status=$?
set -e
(( build_status == 0 )) || exit "$build_status"

set +e
bin_path="$({
  cd "$package_root"
  swift "${bin_arguments[@]}"
})"
bin_status=$?
set -e
(( bin_status == 0 )) || exit "$bin_status"
if [[ "$bin_path" != /* || ! -d "$bin_path" || -L "$bin_path" || "$bin_path" == *$'\n'* ]]; then
  printf 'error: SwiftPM returned an invalid test binary path: %s\n' "$bin_path" >&2
  exit 1
fi
readonly bin_path

readonly candidate_resource_bundle="$bin_path/Fleck_FleckApp.bundle"
if (( candidate_graph_selected )); then
  if [[ ! -d "$candidate_resource_bundle" || -L "$candidate_resource_bundle" ]]; then
    printf '%s\n' 'error: candidate SwiftPM App resource bundle is missing or unsafe' >&2
    exit 1
  fi
  if [[ "$(directory_entry_count "$candidate_resource_bundle")" != \
    "${#candidate_resource_names[@]}" ]]; then
    printf '%s\n' 'error: candidate SwiftPM App resource bundle does not contain exactly the expected metadata documents' >&2
    exit 1
  fi
  for resource_name in "${candidate_resource_names[@]}"; do
    if [[ ! -f "$candidate_resource_bundle/$resource_name" ||
      -L "$candidate_resource_bundle/$resource_name" ]]; then
      printf 'error: candidate SwiftPM App resource document is missing or unsafe: %s\n' \
        "$resource_name" >&2
      exit 1
    fi
  done
fi

readonly bundle_candidates="$state_dir/test-bundles"
/usr/bin/find "$bin_path" -maxdepth 1 -type d -name '*.xctest' -print \
  > "$bundle_candidates"
bundle_count="$(/usr/bin/wc -l < "$bundle_candidates" | /usr/bin/tr -d ' ')"
if [[ "$bundle_count" != 1 ]]; then
  printf 'error: expected exactly one freshly built Swift test bundle, found %s in %s\n' \
    "$bundle_count" "$bin_path" >&2
  exit 1
fi
bundle_path="$(/bin/cat "$bundle_candidates")"
bundle_name="$(/usr/bin/basename "$bundle_path" .xctest)"
readonly bundle_binary="$bundle_path/Contents/MacOS/$bundle_name"
if [[ ! -f "$bundle_binary" || -L "$bundle_binary" || ! -x "$bundle_binary" ]]; then
  printf 'error: freshly built Swift test bundle has no safe executable: %s\n' \
    "$bundle_binary" >&2
  exit 1
fi

/bin/mkdir -p "$expected_host_contents/MacOS"
cat > "$expected_host_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Fleck Swift Test Host</string>
  <key>CFBundleExecutable</key>
  <string>AppKitTestHost</string>
  <key>CFBundleIdentifier</key>
  <string>com.harryjin.fleck.tests.appkit-host</string>
  <key>CFBundleName</key>
  <string>Fleck Swift Test Host</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
if (( candidate_graph_selected )); then
  /bin/mkdir -p "$expected_host_resource_bundle"
  for resource_name in "${candidate_resource_names[@]}"; do
    /bin/cp "$candidate_resource_bundle/$resource_name" \
      "$expected_host_resource_bundle/$resource_name"
    if ! /usr/bin/cmp -s "$candidate_resource_bundle/$resource_name" \
      "$expected_host_resource_bundle/$resource_name"; then
      printf 'error: copied candidate SwiftPM App resource does not match its build output: %s\n' \
        "$resource_name" >&2
      exit 1
    fi
  done
fi
set +e
"$swiftc_path" -parse-as-library -sdk "$sdk_path" -F "$framework_path" \
  -framework AppKit -framework Testing \
  -Xlinker -platform_version -Xlinker macos -Xlinker "$deployment_target" \
  -Xlinker "$sdk_version" \
  -Xlinker -rpath -Xlinker "$framework_path" \
  "$host_source" -o "$expected_host_binary"
host_build_status=$?
set -e
(( host_build_status == 0 )) || exit "$host_build_status"
[[ -x "$expected_host_binary" && ! -L "$expected_host_binary" ]] || {
  printf '%s\n' 'error: Swift compiler did not produce the AppKit Swift test host' >&2
  exit 1
}
if "$codesign_path" --force --deep --sign - "$expected_host_app"; then
  :
else
  sign_status=$?
  printf '%s\n' 'error: failed to ad-hoc sign the temporary AppKit test host' >&2
  exit "$sign_status"
fi
if "$codesign_path" --verify --deep --strict --verbose=2 "$expected_host_app"; then
  :
else
  verify_status=$?
  printf '%s\n' 'error: temporary AppKit test host failed strict signature verification' >&2
  exit "$verify_status"
fi

if [[ ${FLECK_TEST_APPKIT_HOST_APP_PATH+x} ]]; then
  configured_host_app="$FLECK_TEST_APPKIT_HOST_APP_PATH"
  if [[ -z "$configured_host_app" || "$configured_host_app" != /* ||
    "$configured_host_app" != *.app || "$configured_host_app" = *$'\n'* ||
    -L "$configured_host_app" || ! -d "$configured_host_app" ]]; then
    printf 'error: configured AppKit test host path is unsafe or incomplete: %s\n' \
      "$configured_host_app" >&2
    exit 1
  fi
  if ! configured_host_realpath="$(cd "$configured_host_app" 2>/dev/null && pwd -P)" ||
    [[ "$configured_host_realpath" != "$configured_host_app" ]]; then
    printf 'error: configured AppKit test host path is not canonical: %s\n' \
      "$configured_host_app" >&2
    exit 1
  fi
  configured_host_contents="$configured_host_app/Contents"
  configured_host_macos="$configured_host_contents/MacOS"
  configured_host_info="$configured_host_contents/Info.plist"
  configured_host_binary="$configured_host_macos/AppKitTestHost"
  if [[ ! -d "$configured_host_contents" || -L "$configured_host_contents" ||
    ! -d "$configured_host_macos" || -L "$configured_host_macos" ||
    ! -f "$configured_host_info" || -L "$configured_host_info" ||
    ! -f "$configured_host_binary" || ! -x "$configured_host_binary" ||
    -L "$configured_host_binary" ]]; then
    printf 'error: configured AppKit test host path is unsafe or incomplete: %s\n' \
      "$configured_host_app" >&2
    exit 1
  fi
  if ! /usr/bin/cmp -s "$expected_host_binary" "$configured_host_binary"; then
    printf '%s\n' 'error: configured AppKit test host executable does not match the current build' >&2
    exit 1
  fi
  if ! /usr/bin/cmp -s "$expected_host_contents/Info.plist" "$configured_host_info"; then
    printf '%s\n' 'error: configured AppKit test host Info.plist does not match the current build' >&2
    exit 1
  fi
  if ! verify_configured_host_resources "$configured_host_contents"; then
    exit 1
  fi
  if "$codesign_path" --verify --deep --strict --verbose=2 "$configured_host_app"; then
    :
  else
    verify_status=$?
    printf '%s\n' 'error: configured AppKit test host failed strict signature verification' >&2
    exit "$verify_status"
  fi
  host_app="$configured_host_app"
  host_binary="$configured_host_binary"
fi

readonly list_output="$state_dir/test-list"
readonly canonical_output="$state_dir/canonical-test-list"
readonly matches="$state_dir/matches"
readonly test_output="$state_dir/test-output"
set +e
launch_host list --list-tests > "$list_output"
list_status=$?
set -e
(( list_status == 0 )) || exit "$list_status"

LC_ALL=C /usr/bin/grep -E \
  '^[[:alnum:]_][[:alnum:]_-]*\.[[:alnum:]_][[:alnum:]_.-]*(/[[:alnum:]_][[:alnum:]_.-]*)*\((([[:alpha:]_][[:alnum:]_]*):)*\)$' \
  "$list_output" > "$canonical_output" || true
set +e
/usr/bin/grep -E -- "$identifier_regex" "$canonical_output" > "$matches"
match_status=$?
set -e
if (( match_status == 2 )); then
  printf 'error: invalid extended regular expression: %s\n' "$identifier_regex" >&2
  exit 2
fi
if [[ ! -s "$matches" ]]; then
  printf 'error: test identifier regex matched zero tests: %s\n' \
    "$identifier_regex" >&2
  exit 3
fi

matched_count="$(/usr/bin/wc -l < "$matches" | /usr/bin/tr -d ' ')"
printf 'matched test count: %s\n' "$matched_count"
while IFS= read -r identifier; do
  printf 'matched test: %s\n' "$identifier"
done < "$matches"

if [[ "$identifier_regex" = '^.+$' ]]; then
  run_filter="$identifier_regex"
else
  run_filter="$(/usr/bin/awk '
  function escape_ere(value, result, index_, character) {
    result = ""
    for (index_ = 1; index_ <= length(value); index_++) {
      character = substr(value, index_, 1)
      if (index("\\.^$|()[]*+?{}", character) > 0) {
        result = result "\\" character
      } else {
        result = result character
      }
    }
    return result
  }
  BEGIN { printf "^(" }
  {
    identifier = $0
    if (count++) { printf "|" }
    printf "%s/", escape_ere(identifier)
  }
  END { print ")" }
' "$matches")"
fi

if launch_host run --filter "$run_filter" --no-parallel > "$test_output" 2>&1; then
  test_status=0
else
  test_status=$?
fi
if /bin/cat "$test_output"; then
  output_status=0
else
  output_status=$?
fi
(( test_status == 0 )) || exit "$test_status"
if (( output_status != 0 )); then
  printf '%s\n' 'error: failed to capture Swift test output' >&2
  exit 1
fi

final_output_line="$(/usr/bin/awk 'NF { line = $0 } END { print line }' "$test_output")"
if ! printf '%s\n' "$final_output_line" | LC_ALL=C /usr/bin/grep -Eq \
  '^✔ Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed after [0-9]+(\.[0-9]+)? seconds\.$'; then
  printf '%s\n' \
    'error: Swift test exited successfully without a final non-empty passing test summary' >&2
  exit 1
fi
