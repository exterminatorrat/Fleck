#!/usr/bin/env bash
set -euo pipefail
unset FLECK_TEST_APPKIT_HOST_APP_PATH

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ordinary_runner="$script_dir/run-nonempty-swift-tests.sh"
readonly enhanced_runner="$script_dir/run-nonempty-enhanced-tests.sh"
readonly appkit_runner="$script_dir/run-swift-tests-with-appkit-host.sh"
readonly appkit_host_source="$script_dir/../Tests/Support/AppKitTestMain.swift"
readonly validate_script="$script_dir/validate-macos.sh"
temp_path="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nonempty-runner-test.XXXXXX")"
readonly temp_root="$(cd -- "$temp_path" && pwd -P)"
readonly fixture_root="$temp_root/repo"
readonly fixture_scripts="$fixture_root/Scripts"
readonly fixture_bin="$temp_root/bin"
readonly fixture_state="$temp_root/state"
readonly foreign_root="$temp_root/foreign"
readonly app_resource_source="$script_dir/../Sources/FleckApp/Resources"
readonly candidate_resource_names=(
  EnhancedModelManifest.json
  GemmaCleanupModelManifest.json
  GemmaCleanupNotice.md
  ThirdPartyNotices.md
)
decoy_pid=''

cleanup() {
  if [[ -n "$decoy_pid" ]]; then
    /bin/kill -TERM "$decoy_pid" 2>/dev/null || true
    wait "$decoy_pid" 2>/dev/null || true
  fi
  /bin/rm -rf -- "$temp_root"
}
trap cleanup EXIT

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

for runner in "$ordinary_runner" "$enhanced_runner" "$appkit_runner"; do
  [[ -x "$runner" ]] || fail "required runner is missing or not executable: $runner"
done
[[ -f "$appkit_host_source" ]] ||
  fail "required AppKit host source is missing: $appkit_host_source"
/usr/bin/grep -Fq '"$script_dir/run-nonempty-swift-tests.sh" '\''^.+$'\''' \
  "$validate_script" || fail 'validate-macos does not use the non-empty runner'

/bin/mkdir -p "$fixture_scripts" "$fixture_bin" "$fixture_state" "$foreign_root" \
  "$fixture_root/Tests/Support" \
  "$fixture_state/platform/Developer/Library/Frameworks/Testing.framework" \
  "$fixture_state/sdk" "$fixture_state/app-resource-source"
/bin/cp "$ordinary_runner" "$enhanced_runner" "$appkit_runner" "$fixture_scripts/"
/bin/cp "$appkit_host_source" "$fixture_root/Tests/Support/"
for resource_name in "${candidate_resource_names[@]}"; do
  [[ -f "$app_resource_source/$resource_name" && ! -L "$app_resource_source/$resource_name" ]] ||
    fail "required App resource is missing or unsafe: $resource_name"
  /bin/cp "$app_resource_source/$resource_name" \
    "$fixture_state/app-resource-source/$resource_name"
done
printf '// fixture package\n' > "$fixture_root/Package.swift"
printf 'ordinary root lock\n' > "$fixture_root/Package.resolved"

cat > "$fixture_scripts/resolve-enhanced-candidate.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly scratch="${1:?missing scratch}"
shift
printf '%s\n' "$repo_root" > "$FAKE_STATE/resolver-root"

if [[ -e "$scratch" ]]; then
  printf 'error: candidate scratch path must not already exist: %s\n' "$scratch" >&2
  exit 41
fi

/bin/mkdir "$scratch"
printf '%s\n' "$scratch" > "$FAKE_STATE/enhanced-scratch"
/bin/cp "$repo_root/Package.resolved" "$FAKE_STATE/resolver-root-backup"
/bin/rm -f -- "$repo_root/Package.resolved"
if [[ ! -f "$FAKE_ACTUAL_ROOT/Package.resolved" ]]; then
  /bin/cp "$FAKE_STATE/resolver-root-backup" "$repo_root/Package.resolved"
  printf '%s\n' 'error: actual root lock became transiently absent' >&2
  exit 42
fi
printf 'enhanced candidate lock\n' > "$repo_root/Package.resolved"

if [[ "${FAKE_RESOLVER_FAIL:-0}" = 1 ]]; then
  /bin/cp "$FAKE_STATE/resolver-root-backup" "$repo_root/Package.resolved"
  exit "${FAKE_RESOLVER_EXIT:-31}"
fi

set +e
FLECK_ENHANCED_CANDIDATE=1 "$@"
status=$?
set -e
/bin/cp "$FAKE_STATE/resolver-root-backup" "$repo_root/Package.resolved"
exit "$status"
SH
/bin/chmod +x "$fixture_scripts/resolve-enhanced-candidate.sh"

cat > "$fixture_bin/swift" <<'SH'
#!/bin/sh
set -eu

printf '%s|%s\n' "$(pwd -P)" "$*" >> "$FAKE_STATE/swift-invocations"
if [ -n "${FAKE_REACHED_SWIFT_MARKER:-}" ]; then
  /usr/bin/touch "$FAKE_REACHED_SWIFT_MARKER"
fi
if [ -n "${FAKE_SWIFT_PID_FILE:-}" ]; then
  printf '%s\n' "$$" > "$FAKE_SWIFT_PID_FILE"
fi

if [ "${1:-}" = build ] && [ "${2:-}" = --build-tests ]; then
  /bin/mkdir -p "$FAKE_STATE/bin"
  if [ "${FAKE_SKIP_BUNDLE:-0}" != 1 ]; then
    bundle="$FAKE_STATE/bin/FakePackageTests.xctest/Contents/MacOS"
    /bin/mkdir -p "$bundle"
    printf '%s\n' 'fake test bundle' > "$bundle/FakePackageTests"
    /bin/chmod +x "$bundle/FakePackageTests"
    if [ "${FAKE_MULTIPLE_BUNDLES:-0}" = 1 ]; then
      second="$FAKE_STATE/bin/OtherPackageTests.xctest/Contents/MacOS"
      /bin/mkdir -p "$second"
      printf '%s\n' 'fake second test bundle' > "$second/OtherPackageTests"
      /bin/chmod +x "$second/OtherPackageTests"
    fi
  fi
  if [ "${FLECK_ENHANCED_CANDIDATE:-}" = 1 ] &&
    [ "${FAKE_CANDIDATE_RESOURCE_BUNDLE_MISSING:-0}" != 1 ]; then
    candidate_bundle="$FAKE_STATE/bin/Fleck_FleckApp.bundle"
    if [ "${FAKE_CANDIDATE_RESOURCE_BUNDLE_SYMLINK:-0}" = 1 ]; then
      candidate_bundle_target="$FAKE_STATE/candidate-resource-bundle-target"
      /bin/rm -rf "$candidate_bundle_target"
      /bin/mkdir -p "$candidate_bundle_target"
      candidate_bundle_output="$candidate_bundle_target"
    else
      /bin/mkdir -p "$candidate_bundle"
      candidate_bundle_output="$candidate_bundle"
    fi
    for resource_name in EnhancedModelManifest.json \
      GemmaCleanupModelManifest.json GemmaCleanupNotice.md ThirdPartyNotices.md; do
      if [ "${FAKE_CANDIDATE_RESOURCE_MISSING:-}" = "$resource_name" ]; then
        continue
      fi
      if [ "${FAKE_CANDIDATE_RESOURCE_SYMLINK:-}" = "$resource_name" ]; then
        /bin/ln -s "$FAKE_STATE/app-resource-source/$resource_name" \
          "$candidate_bundle_output/$resource_name"
      else
        /bin/cp "$FAKE_STATE/app-resource-source/$resource_name" \
          "$candidate_bundle_output/$resource_name"
      fi
    done
    if [ "${FAKE_CANDIDATE_RESOURCE_EXTRA:-0}" = 1 ]; then
      printf '%s\n' 'unrequested model data' > "$candidate_bundle_output/weights.safetensors"
    fi
    if [ "${FAKE_CANDIDATE_RESOURCE_BUNDLE_SYMLINK:-0}" = 1 ]; then
      /bin/ln -s "$candidate_bundle_output" "$candidate_bundle"
    fi
    printf '%s\n' 'unpackaged model weights' > "$FAKE_STATE/bin/model.safetensors"
    printf '%s\n' 'unpackaged helper executable' > "$FAKE_STATE/bin/gemma-cleanup-helper"
  fi
  exit "${FAKE_BUILD_EXIT:-0}"
fi

if [ "${1:-}" = build ] && [ "${2:-}" = --show-bin-path ]; then
  printf '%s\n' "$FAKE_STATE/bin"
  exit "${FAKE_BIN_PATH_EXIT:-0}"
fi

if [ "${1:-}" = test ] && [ "${2:-}" = list ]; then
  if [ -n "${FAKE_BLOCK_LIST_MARKER:-}" ]; then
    /usr/bin/touch "$FAKE_BLOCK_LIST_MARKER"
    while [ ! -e "$FAKE_RELEASE_LIST_MARKER" ]; do
      /bin/sleep 0.05
    done
  fi
  printf '%s\n' "${FAKE_LIST_OUTPUT:-}"
  exit "${FAKE_LIST_EXIT:-0}"
fi

if [ "${1:-}" = test ]; then
  if [ "${FAKE_EXPECT_NO_PARALLEL:-0}" = 1 ]; then
    saw_no_parallel=0
    for argument in "$@"; do
      if [ "$argument" = --no-parallel ]; then
        saw_no_parallel=1
      fi
    done
    if [ "$saw_no_parallel" -ne 1 ]; then
      printf '%s\n' 'error: filtered run omitted --no-parallel' >&2
      exit 93
    fi
  fi
  if [ -n "${FAKE_EXPECT_FILTER:-}" ]; then
    actual_filter=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = --filter ]; then
        actual_filter="${2:-}"
        break
      fi
      shift
    done
    if [ "$actual_filter" != "$FAKE_EXPECT_FILTER" ]; then
      printf 'error: expected derived filter %s, got %s\n' \
        "$FAKE_EXPECT_FILTER" "$actual_filter" >&2
      exit 92
    fi
  fi
  if [ -n "${FAKE_RUNTIME_IDENTIFIERS:-}" ]; then
    : > "$FAKE_STATE/selected-runtime-identifiers"
    printf '%s\n' "$FAKE_RUNTIME_IDENTIFIERS" |
      while IFS= read -r runtime_identifier; do
        if printf '%s\n' "$runtime_identifier" |
          /usr/bin/grep -E -- "$actual_filter" >/dev/null; then
          printf '%s\n' "$runtime_identifier" >> \
            "$FAKE_STATE/selected-runtime-identifiers"
        fi
      done
  fi
  if [ -n "${FAKE_MUTATE_LOCK:-}" ]; then
    printf 'mutated lock\n' > "$FAKE_MUTATE_LOCK"
  fi
  if [ -n "${FAKE_READONLY_LOCK_PARENT:-}" ]; then
    /bin/chmod 400 "$FAKE_MUTATE_LOCK"
    /bin/chmod 500 "$FAKE_READONLY_LOCK_PARENT"
  fi
  if [ "${FAKE_SIGNAL_RUNNER:-0}" = 1 ]; then
    kill -TERM "$PPID"
  fi
  if [ "${FAKE_RUN_OUTPUT+x}" = x ]; then
    if [ -n "$FAKE_RUN_OUTPUT" ]; then
      printf '%s\n' "$FAKE_RUN_OUTPUT"
    fi
  else
    printf '%s\n' '✔ Test run with 1 test in 0 suites passed after 0.001 seconds.'
  fi
  exit "${FAKE_RUN_EXIT:-0}"
fi

printf 'error: unexpected fake swift invocation: %s\n' "$*" >&2
exit 90
SH
/bin/chmod +x "$fixture_bin/swift"

cat > "$fixture_state/fake-appkit-host" <<'SH'
#!/bin/bash
set -eu

bundle_binary="$1"
shift
list_tests=0
saw_no_parallel=0
actual_filter=''
host_configuration=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list-tests)
      list_tests=1
      shift
      ;;
    --filter)
      actual_filter="${2:-}"
      shift 2
      ;;
    --no-parallel)
      saw_no_parallel=1
      shift
      ;;
    --host-config)
      host_configuration="${2:-}"
      shift 2
      ;;
    *)
      printf 'error: unsupported test argument: %s\n' "$1" >&2
      exit 94
      ;;
  esac
done
[[ -n "$host_configuration" ]] || {
  printf '%s\n' 'error: fake host configuration is missing' >&2
  exit 95
}
configuration_values=()
while IFS= read -r -d '' value; do
  configuration_values+=("$value")
done < "$host_configuration"
[[ "${#configuration_values[@]}" -eq 5 ]] || {
  printf '%s\n' 'error: fake host configuration has the wrong field count' >&2
  exit 96
}
nonce="${configuration_values[0]}"
receipt_path="${configuration_values[1]}"
pid_path="${configuration_values[2]}"
phase_path="${configuration_values[3]}"
host_log_path="${configuration_values[4]}"
exec >> "$host_log_path" 2>&1
printf '%s\t%s\n' "$nonce" "$$" > "$pid_path"
printf '%s\n' 'didFinishLaunching' > "$phase_path"
printf '%s|%s|%s|%s\n' "$bundle_binary" "$list_tests" "$actual_filter" \
  "$saw_no_parallel" >> "$FAKE_STATE/host-invocations"
if [ -n "${FAKE_REACHED_SWIFT_MARKER:-}" ]; then
  /usr/bin/touch "$FAKE_REACHED_SWIFT_MARKER"
fi
if [ -n "${FAKE_SWIFT_PID_FILE:-}" ]; then
  printf '%s\n' "$$" > "$FAKE_SWIFT_PID_FILE"
fi
if [ -f "$FAKE_STATE/host-path-forwarding-contract" ] &&
  [[ ${FLECK_TEST_APPKIT_HOST_APP_PATH+x} ]]; then
  printf '%s\n' 'error: fake host received the internal host-app path variable' >&2
  exit 97
fi
if [ -f "$FAKE_STATE/environment-forwarding-contract" ]; then
  if [[ ${FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR+x} ]]; then
    printf '%s\n' 'error: fake host received an unset whitelist variable' >&2
    exit 97
  fi
  if [[ ! ${FLECK_SETTINGS_WINDOW_CAPTURE_DIR+x} ]]; then
    printf '%s\n' 'error: fake host lost an explicitly empty whitelist variable' >&2
    exit 97
  fi
  if [[ -n "$FLECK_SETTINGS_WINDOW_CAPTURE_DIR" ]]; then
    printf '%s\n' 'error: fake host changed an explicitly empty whitelist variable' >&2
    exit 97
  fi
  if [[ ! ${FLECK_SETTINGS_MODELS_CAPTURE_DIR+x} ]]; then
    printf '%s\n' 'error: fake host lost a non-empty whitelist variable' >&2
    exit 97
  fi
  if [[ "$FLECK_SETTINGS_MODELS_CAPTURE_DIR" != \
    'mock capture path with spaces = $literal * [glob]; "quoted"' ]]; then
    printf '%s\n' 'error: fake host changed a non-empty whitelist variable' >&2
    exit 97
  fi
  if [[ ${FLECK_TEST_UNWHITELISTED_CAPTURE_PROBE+x} ]]; then
    printf '%s\n' 'error: fake host received an unwhitelisted variable' >&2
    exit 97
  fi
  if [[ ${FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC+x} ]]; then
    [[ "$FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC" = 1 ]] || {
      printf '%s\n' 'error: fake host changed the folder navigator diagnostic value' >&2
      exit 97
    }
    printf 'FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC=%s\n' \
      "$FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC" \
      >> "$FAKE_STATE/folder-diagnostic-observations"
  fi
  printf '%s\n' 'pass' >> "$FAKE_STATE/host-environment-observations"
fi

write_receipt() {
  local status="$1"
  local phase
  phase="$(/bin/cat "$phase_path")"
  if [ "${FAKE_NO_RECEIPT:-0}" = 1 ] ||
    [ "${FAKE_NO_RECEIPT_PHASE:-}" = "$phase" ]; then
    return 0
  fi
  printf '%s\t%s\t%s\n' "${FAKE_RECEIPT_NONCE:-$nonce}" \
    "${FAKE_RECEIPT_PID:-$$}" "$status" \
    > "$receipt_path"
}

hang_host() {
  trap '' TERM
  while :; do
    /bin/sleep 1
  done
}

if [ "${FAKE_HOST_LOAD_EXIT:-0}" != 0 ]; then
  printf '%s\n' 'error: failed to load test bundle: fixture failure' >&2
  write_receipt "$FAKE_HOST_LOAD_EXIT"
  exit "$FAKE_HOST_LOAD_EXIT"
fi
if [ "$list_tests" -eq 1 ]; then
  printf '%s\n' 'listingTests' > "$phase_path"
  if [ "${FAKE_HOST_HANG_PHASE:-}" = listingTests ]; then
    hang_host
  fi
  if [ -n "${FAKE_BLOCK_LIST_MARKER:-}" ]; then
    /usr/bin/touch "$FAKE_BLOCK_LIST_MARKER"
    while [ ! -e "$FAKE_RELEASE_LIST_MARKER" ]; do
      /bin/sleep 0.05
    done
  fi
  printf '%s\n' "${FAKE_LIST_OUTPUT:-}"
  status="${FAKE_LIST_EXIT:-0}"
  write_receipt "$status"
  exit "$status"
fi

printf '%s\n' 'runningTests' > "$phase_path"
if [ "${FAKE_EXPECT_NO_PARALLEL:-0}" = 1 ] && [ "$saw_no_parallel" -ne 1 ]; then
  printf '%s\n' 'error: native host run omitted --no-parallel' >&2
  exit 93
fi
if [ -n "${FAKE_EXPECT_FILTER:-}" ] && [ "$actual_filter" != "$FAKE_EXPECT_FILTER" ]; then
  printf 'error: expected derived filter %s, got %s\n' \
    "$FAKE_EXPECT_FILTER" "$actual_filter" >&2
  exit 92
fi
if [ -n "${FAKE_RUNTIME_IDENTIFIERS:-}" ]; then
  : > "$FAKE_STATE/selected-runtime-identifiers"
  printf '%s\n' "$FAKE_RUNTIME_IDENTIFIERS" |
    while IFS= read -r runtime_identifier; do
      if printf '%s\n' "$runtime_identifier" |
        /usr/bin/grep -E -- "$actual_filter" >/dev/null; then
        printf '%s\n' "$runtime_identifier" >> \
          "$FAKE_STATE/selected-runtime-identifiers"
      fi
    done
fi
if [ -n "${FAKE_MUTATE_LOCK:-}" ]; then
  printf 'mutated lock\n' > "$FAKE_MUTATE_LOCK"
fi
if [ -n "${FAKE_READONLY_LOCK_PARENT:-}" ]; then
  /bin/chmod 400 "$FAKE_MUTATE_LOCK"
  /bin/chmod 500 "$FAKE_READONLY_LOCK_PARENT"
fi
if [ "${FAKE_HOST_HANG_PHASE:-}" = runningTests ]; then
  printf '%s\n' 'fixture host output tail for runningTests'
fi
if [ "${FAKE_SIGNAL_RUNNER:-0}" = 1 ] ||
  [ "${FAKE_SIGNAL_RUNNER_PHASE:-}" = runningTests ]; then
  kill -TERM "$PPID"
fi
if [ "${FAKE_HOST_HANG:-0}" = 1 ] ||
  [ "${FAKE_HOST_HANG_PHASE:-}" = runningTests ]; then
  hang_host
fi
if [ "${FAKE_RUN_OUTPUT+x}" = x ]; then
  if [ -n "$FAKE_RUN_OUTPUT" ]; then
    printf '%s\n' "$FAKE_RUN_OUTPUT"
  fi
else
  printf '%s\n' '✔ Test run with 1 test in 0 suites passed after 0.001 seconds.'
fi
status="${FAKE_RUN_EXIT:-0}"
write_receipt "$status"
exit "$status"
SH
/bin/chmod +x "$fixture_state/fake-appkit-host"

cat > "$fixture_bin/codesign" <<'SH'
#!/bin/bash
set -eu

printf '%s\n' "$*" >> "$FAKE_STATE/codesign-invocations"
app_path=''
for argument in "$@"; do app_path="$argument"; done
case "${1:-}" in
  --force)
    [[ "${2:-}" = --deep && "${3:-}" = --sign && "${4:-}" = - ]] || exit 97
    if [ "${FAKE_CODESIGN_SIGN_EXIT:-0}" != 0 ]; then
      exit "$FAKE_CODESIGN_SIGN_EXIT"
    fi
    [[ -x "$app_path/Contents/MacOS/AppKitTestHost" ]] || exit 98
    if [ "${FLECK_ENHANCED_CANDIDATE:-}" = 1 ]; then
      candidate_bundle="$app_path/Contents/Resources/Fleck_FleckApp.bundle"
      [[ -d "$candidate_bundle" && ! -L "$candidate_bundle" ]] || exit 101
      [[ "$(/usr/bin/find "$app_path/Contents/Resources" -mindepth 1 -maxdepth 1 -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 && \
        "$(/usr/bin/find "$candidate_bundle" -mindepth 1 -maxdepth 1 -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 4 ]] || exit 101
      for resource_name in EnhancedModelManifest.json \
        GemmaCleanupModelManifest.json GemmaCleanupNotice.md ThirdPartyNotices.md; do
        [[ -f "$candidate_bundle/$resource_name" && ! -L "$candidate_bundle/$resource_name" ]] || exit 101
        /usr/bin/cmp -s "$FAKE_STATE/bin/Fleck_FleckApp.bundle/$resource_name" \
          "$candidate_bundle/$resource_name" || exit 101
      done
      [[ ! -e "$app_path/Contents/Resources/model.safetensors" && \
        ! -e "$app_path/Contents/Resources/gemma-cleanup-helper" ]] || exit 101
    else
      [[ ! -e "$app_path/Contents/Resources" && ! -L "$app_path/Contents/Resources" ]] || exit 101
    fi
    printf '%s\n' "$app_path" >> "$FAKE_STATE/signed-app-paths"
    printf '%s\n' 'ad-hoc fixture signature' > \
      "$app_path/Contents/.fixture-adhoc-signature"
    ;;
  --verify)
    [[ "${2:-}" = --deep && "${3:-}" = --strict && \
      "${4:-}" = --verbose=2 ]] || exit 99
    [[ -f "$app_path/Contents/.fixture-adhoc-signature" ]] || exit 100
    if [ "${FAKE_CODESIGN_VERIFY_EXIT:-0}" != 0 ]; then
      exit "$FAKE_CODESIGN_VERIFY_EXIT"
    fi
    printf '%s\n' "$app_path" >> "$FAKE_STATE/verified-app-paths"
    ;;
  *)
    exit 96
    ;;
esac
SH
/bin/chmod +x "$fixture_bin/codesign"

cat > "$fixture_bin/open" <<'SH'
#!/bin/bash
set -eu

printf '%s\n' 'fake open invocation' >> "$FAKE_STATE/open-invocations"
if [ -n "${FAKE_OPEN_PID_FILE:-}" ]; then
  printf '%s\n' "$$" > "$FAKE_OPEN_PID_FILE"
fi
app_path=''
list_background=0
saw_new=0
saw_wait=0
app_arguments=()
forwarded_environment_names=()
forwarded_environment_assignments=()

environment_name_is_forwarded() {
  local expected_name="$1"
  local forwarded_name
  for forwarded_name in "${forwarded_environment_names[@]}"; do
    [[ "$forwarded_name" = "$expected_name" ]] && return 0
  done
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n)
      saw_new=1
      shift
      ;;
    -W)
      saw_wait=1
      shift
      ;;
    -g)
      list_background=1
      shift
      ;;
    -a)
      app_path="${2:-}"
      shift 2
      ;;
    --env)
      environment_argument="${2:-}"
      if [[ "$environment_argument" = *=* ]]; then
        environment_name="${environment_argument%%=*}"
        environment_assignment="$environment_argument"
      else
        environment_name="$environment_argument"
        environment_assignment="$environment_name="
      fi
      forwarded_environment_names+=("$environment_name")
      forwarded_environment_assignments+=("$environment_assignment")
      printf 'environment:%s\n' "$environment_name" >> "$FAKE_STATE/open-environments"
      if [ -f "$FAKE_STATE/environment-forwarding-contract" ]; then
        case "$environment_name" in
          FLECK_SETTINGS_WINDOW_CAPTURE_DIR|FLECK_SETTINGS_MODELS_CAPTURE_DIR|FLECK_NATIVE_CAPTURE_QA|FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC)
            printf 'environment:%s\n' "$environment_assignment" \
              >> "$FAKE_STATE/open-environment-probes"
            ;;
        esac
      fi
      shift 2
      ;;
    --args)
      shift
      app_arguments=("$@")
      break
      ;;
    *)
      printf 'error: unsupported fake open option: %s\n' "$1" >&2
      exit 91
      ;;
  esac
done
printf '%s\n' "${forwarded_environment_names[*]}" \
  >> "$FAKE_STATE/open-environment-name-blocks"
[[ "$saw_new" -eq 1 && "$saw_wait" -eq 1 && -n "$app_path" ]] || {
  printf '%s\n' 'error: fake open did not receive -n, -W, and -a' >&2
  exit 92
}
host_binary="$app_path/Contents/MacOS/AppKitTestHost"
[[ -x "$host_binary" && -f "$app_path/Contents/Info.plist" ]] || {
  printf '%s\n' 'error: fake open received an invalid AppKit test bundle' >&2
  exit 93
}
bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
  "$app_path/Contents/Info.plist")"
[[ "$bundle_id" = 'com.harryjin.fleck.tests.appkit-host' ]] || {
  printf 'error: unexpected AppKit test bundle identifier: %s\n' "$bundle_id" >&2
  exit 94
}
[[ -f "$app_path/Contents/.fixture-adhoc-signature" ]] && \
  /usr/bin/grep -Fxq -- "$app_path" "$FAKE_STATE/verified-app-paths" || {
  printf '%s\n' 'error: fake LaunchServices received an unsigned or unverified AppKit test host' >&2
  exit 97
}
if [ "${FLECK_ENHANCED_CANDIDATE:-}" = 1 ]; then
  candidate_bundle="$app_path/Contents/Resources/Fleck_FleckApp.bundle"
  [[ -d "$candidate_bundle" && ! -L "$candidate_bundle" ]] || {
    printf '%s\n' 'error: fake LaunchServices received a candidate host without resources' >&2
    exit 98
  }
  for resource_name in EnhancedModelManifest.json \
    GemmaCleanupModelManifest.json GemmaCleanupNotice.md ThirdPartyNotices.md; do
    [[ -f "$candidate_bundle/$resource_name" && ! -L "$candidate_bundle/$resource_name" ]] && \
      /usr/bin/cmp -s "$FAKE_STATE/bin/Fleck_FleckApp.bundle/$resource_name" \
        "$candidate_bundle/$resource_name" || {
      printf 'error: fake LaunchServices received mismatched candidate resource: %s\n' \
        "$resource_name" >&2
      exit 98
    }
  done
fi
printf '%s\n' "$app_path" >> "$FAKE_STATE/host-app-paths"
if [ -n "${FAKE_PRESERVE_HOST_APP_PATH:-}" ] &&
  [ ! -e "$FAKE_PRESERVE_HOST_APP_PATH" ]; then
  /bin/cp -R "$app_path" "$FAKE_PRESERVE_HOST_APP_PATH"
fi
if [ -f "$FAKE_STATE/environment-forwarding-contract" ]; then
  for probe_name in FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR \
    FLECK_SETTINGS_WINDOW_CAPTURE_DIR FLECK_SETTINGS_MODELS_CAPTURE_DIR \
    FLECK_TEST_UNWHITELISTED_CAPTURE_PROBE FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC; do
    if ! environment_name_is_forwarded "$probe_name"; then
      unset "$probe_name"
    fi
  done
fi
if ! environment_name_is_forwarded FLECK_TEST_APPKIT_HOST_APP_PATH; then
  unset FLECK_TEST_APPKIT_HOST_APP_PATH
fi
if [ "${FAKE_OPEN_EXIT:-0}" != 0 ]; then
  exit "$FAKE_OPEN_EXIT"
fi
if [ "${FAKE_OPEN_RETURN_EARLY:-0}" = 1 ] ||
  { [ "${FAKE_OPEN_RETURN_EARLY_RUN:-0}" = 1 ] && [ "$list_background" -eq 0 ]; }; then
  /usr/bin/env "${forwarded_environment_assignments[@]}" \
    "$host_binary" "${app_arguments[@]}" &
  child_pid=$!
  if [ -n "${FAKE_OPEN_CHILD_PID_FILE:-}" ]; then
    printf '%s\n' "$child_pid" > "$FAKE_OPEN_CHILD_PID_FILE"
  fi
  config=''
  for (( index = 0; index < ${#app_arguments[@]}; index++ )); do
    if [ "${app_arguments[index]}" = --host-config ]; then
      config="${app_arguments[index + 1]:-}"
      break
    fi
  done
  values=()
  while IFS= read -r -d '' value; do values+=("$value"); done < "$config"
  for _ in {1..50}; do
    [ -s "${values[2]}" ] && break
    /bin/sleep 0.02
  done
  if [ -n "${FAKE_OPEN_WAIT_PHASE:-}" ]; then
    for _ in {1..50}; do
      [ "$(/bin/cat "${values[3]}" 2>/dev/null || true)" = \
        "$FAKE_OPEN_WAIT_PHASE" ] && break
      /bin/sleep 0.02
    done
  fi
  exit 0
fi
if [ "$list_background" -ne 1 ] &&
  printf '%s\n' "${app_arguments[@]}" | /usr/bin/grep -Fxq -- '--list-tests'; then
  printf '%s\n' 'error: list mode was not launched in the background' >&2
  exit 95
fi
exec /usr/bin/env "${forwarded_environment_assignments[@]}" \
  "$host_binary" "${app_arguments[@]}"
SH
/bin/chmod +x "$fixture_bin/open"

cat > "$fixture_bin/sample" <<'SH'
#!/bin/sh
set -eu

pid="$1"
printf '%s\n' "$pid" >> "$FAKE_STATE/sample-pids"
output=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -file ]; then
    output="${2:-}"
    break
  fi
  shift
done
[ -n "$output" ] || exit 95
printf 'fixture stack for pid %s\n' "$pid" > "$output"
SH
/bin/chmod +x "$fixture_bin/sample"

cat > "$fixture_bin/swiftc" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >> "$FAKE_STATE/swiftc-invocations"
output=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    output="${2:-}"
    break
  fi
  shift
done
[ -n "$output" ] || exit 95
if [ "${FAKE_HOST_BUILD_EXIT:-0}" != 0 ]; then
  exit "$FAKE_HOST_BUILD_EXIT"
fi
/bin/cp "$FAKE_STATE/fake-appkit-host" "$output"
/bin/chmod +x "$output"
SH
/bin/chmod +x "$fixture_bin/swiftc"

cat > "$fixture_bin/xcrun" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >> "$FAKE_STATE/xcrun-invocations"
case "$*" in
  '--sdk macosx --show-sdk-path')
    printf '%s\n' "$FAKE_STATE/sdk"
    ;;
  '--sdk macosx --show-sdk-platform-path')
    printf '%s\n' "$FAKE_STATE/platform"
    ;;
  '--sdk macosx --find swiftc')
    printf '%s\n' "$FAKE_STATE/../bin/swiftc"
    ;;
  *)
    exit 96
    ;;
esac
SH
/bin/chmod +x "$fixture_bin/xcrun"

run_capture() {
  local output_path="$1"
  shift
  set +e
  "$@" > "$output_path" 2>&1
  RUN_STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"
  [[ "$RUN_STATUS" -eq "$expected" ]] ||
    fail "expected status $expected, got $RUN_STATUS; output: $(cat "$fixture_state/output")"
}

assert_root_lock() {
  /usr/bin/grep -Fxq 'ordinary root lock' "$fixture_root/Package.resolved" ||
    fail 'root Package.resolved was not restored'
}

assert_pid_stopped() {
  local pid="$1" label="$2" process_state
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || fail "$label did not record a valid PID"
  for _ in {1..100}; do
    if ! /bin/kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    process_state="$(/bin/ps -p "$pid" -o stat= 2>/dev/null | /usr/bin/tr -d '[:space:]' || true)"
    [[ -n "$process_state" && "$process_state" != *Z* ]] || return 0
    /bin/sleep 0.05
  done
  fail "$label PID $pid remained running"
}

assert_host_state_removed() {
  local host_app_path state_dir
  host_app_path="$(/usr/bin/tail -n 1 "$fixture_state/host-app-paths")"
  [[ -n "$host_app_path" ]] || fail 'fake LaunchServices did not record a host app path'
  state_dir="$(/usr/bin/dirname "$host_app_path")"
  [[ ! -e "$state_dir" ]] || fail 'AppKit test host state/watchdog directory remained after exit'
}

assert_configured_host_rejected() {
  local app_path="$1" expected_error="$2" expected_status="${3:-1}"
  local temporary_host_app
  reset_invocations
  FLECK_TEST_APPKIT_HOST_APP_PATH="$app_path" \
    FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
    run_capture "$fixture_state/output" \
      run_ordinary '^FleckCoreTests\.known\(\)$'
  assert_status "$expected_status"
  /usr/bin/grep -Fq -- "$expected_error" "$fixture_state/output" ||
    fail "configured AppKit host was not rejected with: $expected_error"
  [[ ! -s "$fixture_state/open-invocations" && \
    ! -s "$fixture_state/host-app-paths" ]] ||
    fail 'LaunchServices was called before configured-host validation completed'
  [[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -ge 2 ]] ||
    fail 'configured-host validation skipped signing or verifying the expected temporary helper'
  temporary_host_app="$(/usr/bin/sed -n '1p' "$fixture_state/signed-app-paths")"
  [[ -n "$temporary_host_app" && ! -e "$temporary_host_app" ]] ||
    fail 'configured-host rejection retained its owned temporary helper app'
  assert_root_lock
}

assert_candidate_resource_source_rejected() {
  local expected_error="$1"
  shift
  reset_invocations
  FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
    run_capture "$fixture_state/output" run_enhanced_with_controls \
      '^FleckCoreTests\.known\(\)$' "$@"
  assert_status 1
  /usr/bin/grep -Fq -- "$expected_error" "$fixture_state/output" ||
    fail "candidate SwiftPM resource bundle was not rejected with: $expected_error"
  [[ ! -s "$fixture_state/codesign-invocations" && \
    ! -s "$fixture_state/open-invocations" && \
    ! -s "$fixture_state/host-app-paths" ]] ||
    fail 'candidate SwiftPM resource rejection signed or launched an AppKit host'
  assert_root_lock
}

assert_configured_candidate_host_rejected() {
  local app_path="$1" expected_error="$2" temporary_host_app
  reset_invocations
  FLECK_TEST_APPKIT_HOST_APP_PATH="$app_path" \
    FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
    run_capture "$fixture_state/output" run_enhanced \
      '^FleckCoreTests\.known\(\)$'
  assert_status 1
  /usr/bin/grep -Fq -- "$expected_error" "$fixture_state/output" ||
    fail "configured candidate AppKit host was not rejected with: $expected_error"
  [[ ! -s "$fixture_state/open-invocations" && \
    ! -s "$fixture_state/host-app-paths" ]] ||
    fail 'LaunchServices received a configured candidate host before resource validation completed'
  [[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -ge 2 ]] ||
    fail 'configured candidate-host validation skipped signing or verifying the expected temporary helper'
  temporary_host_app="$(/usr/bin/sed -n '1p' "$fixture_state/signed-app-paths")"
  [[ -n "$temporary_host_app" && ! -e "$temporary_host_app" ]] ||
    fail 'configured candidate-host rejection retained its owned temporary helper app'
  assert_root_lock
}

assert_completion_error() {
  /usr/bin/grep -Fq \
    'error: Swift test exited successfully without a final non-empty passing test summary' \
    "$fixture_state/output" || fail 'missing Swift test completion error'
}

reset_invocations() {
  : > "$fixture_state/swift-invocations"
  : > "$fixture_state/swiftc-invocations"
  : > "$fixture_state/xcrun-invocations"
  : > "$fixture_state/codesign-invocations"
  : > "$fixture_state/signed-app-paths"
  : > "$fixture_state/verified-app-paths"
  : > "$fixture_state/host-invocations"
  : > "$fixture_state/open-invocations"
  : > "$fixture_state/open-environments"
  : > "$fixture_state/open-environment-probes"
  : > "$fixture_state/open-environment-name-blocks"
  : > "$fixture_state/folder-diagnostic-observations"
  : > "$fixture_state/host-app-paths"
  : > "$fixture_state/sample-pids"
  : > "$fixture_state/output"
  printf 'ordinary root lock\n' > "$fixture_root/Package.resolved"
  /bin/rm -rf -- "$fixture_state/bin"
  /bin/rm -f -- "$fixture_state/enhanced-scratch" \
    "$fixture_state/resolver-root-backup" \
    "$fixture_state/resolver-root" \
    "$fixture_state/selected-runtime-identifiers" \
    "$fixture_state/environment-forwarding-contract" \
    "$fixture_state/host-path-forwarding-contract" \
    "$fixture_state/host-environment-observations"
}

run_ordinary() {
  (
    cd "$foreign_root"
    PATH="$fixture_bin:$PATH" \
      FLECK_TEST_APPKIT_OPEN_PATH="$fixture_bin/open" \
      FLECK_TEST_APPKIT_SAMPLE_PATH="$fixture_bin/sample" \
      FLECK_TEST_APPKIT_CODESIGN_PATH="$fixture_bin/codesign" \
      FAKE_STATE="$fixture_state" \
      "$fixture_scripts/run-nonempty-swift-tests.sh" "$@"
  )
}

run_enhanced() {
  (
    cd "$foreign_root"
    PATH="$fixture_bin:$PATH" \
      FLECK_TEST_APPKIT_OPEN_PATH="$fixture_bin/open" \
      FLECK_TEST_APPKIT_SAMPLE_PATH="$fixture_bin/sample" \
      FLECK_TEST_APPKIT_CODESIGN_PATH="$fixture_bin/codesign" \
      FAKE_STATE="$fixture_state" \
      FAKE_ACTUAL_ROOT="$fixture_root" \
      "$fixture_scripts/run-nonempty-enhanced-tests.sh" "$@"
  )
}

run_enhanced_with_controls() {
  local identifier_regex="$1"
  shift
  (
    cd "$foreign_root"
    /usr/bin/env \
      PATH="$fixture_bin:$PATH" \
      FLECK_TEST_APPKIT_OPEN_PATH="$fixture_bin/open" \
      FLECK_TEST_APPKIT_SAMPLE_PATH="$fixture_bin/sample" \
      FLECK_TEST_APPKIT_CODESIGN_PATH="$fixture_bin/codesign" \
      FAKE_STATE="$fixture_state" \
      FAKE_ACTUAL_ROOT="$fixture_root" \
      "$@" \
      "$fixture_scripts/run-nonempty-enhanced-tests.sh" "$identifier_regex"
  )
}

run_appkit_environment_probe() {
  (
    cd "$foreign_root"
    unset FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR FLECK_ENHANCED_CANDIDATE
    FLECK_SETTINGS_WINDOW_CAPTURE_DIR=''
    export FLECK_SETTINGS_WINDOW_CAPTURE_DIR
    FLECK_SETTINGS_MODELS_CAPTURE_DIR='mock capture path with spaces = $literal * [glob]; "quoted"'
    export FLECK_SETTINGS_MODELS_CAPTURE_DIR
    FLECK_TEST_UNWHITELISTED_CAPTURE_PROBE='mock unlisted value'
    export FLECK_TEST_UNWHITELISTED_CAPTURE_PROBE
    PATH="$fixture_bin:$PATH" \
      FLECK_TEST_APPKIT_OPEN_PATH="$fixture_bin/open" \
      FLECK_TEST_APPKIT_SAMPLE_PATH="$fixture_bin/sample" \
      FLECK_TEST_APPKIT_CODESIGN_PATH="$fixture_bin/codesign" \
      FAKE_STATE="$fixture_state" \
      FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
      FAKE_RUN_OUTPUT='✔ Test run with 1 test in 0 suites passed after 0.001 seconds.' \
      "$fixture_scripts/run-swift-tests-with-appkit-host.sh" \
        "$fixture_root" '' '^FleckCoreTests\.known\(\)$'
  )
}

assert_folder_navigator_diagnostic_forwarding_contracts() {
  reset_invocations
  : > "$fixture_state/environment-forwarding-contract"
  unset FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC FLECK_NATIVE_CAPTURE_QA
  run_capture "$fixture_state/output" run_appkit_environment_probe
  assert_status 0
  if /usr/bin/grep -E -q \
    '^environment:FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC(=|$)' \
    "$fixture_state/open-environments"; then
    fail 'AppKit host forwarded the unset folder navigator diagnostic variable'
  fi
  [[ ! -s "$fixture_state/folder-diagnostic-observations" ]] ||
    fail 'fake host received the unset folder navigator diagnostic variable'
  assert_root_lock

  reset_invocations
  : > "$fixture_state/environment-forwarding-contract"
  FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC=1 \
    run_capture "$fixture_state/output" run_appkit_environment_probe
  assert_status 0
  forwarded_count="$(/usr/bin/grep -Fxc \
    'environment:FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC=1' \
    "$fixture_state/open-environment-probes" || true)"
  [[ "$forwarded_count" -eq 2 ]] ||
    fail 'AppKit host did not forward the literal diagnostic flag to both phases'
  [[ "$(wc -l < "$fixture_state/folder-diagnostic-observations" | tr -d ' ')" -eq 2 ]] ||
    fail 'fake AppKit hosts did not both receive the diagnostic flag'
  /usr/bin/grep -Fxq 'FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC=1' \
    "$fixture_state/folder-diagnostic-observations" ||
    fail 'fake AppKit host received a changed diagnostic flag'
  assert_root_lock
}

if [[ "${FLECK_TEST_FOLDER_DIAGNOSTIC_CONTRACT_ONLY:-0}" = 1 ]]; then
  assert_folder_navigator_diagnostic_forwarding_contracts
  printf '%s\n' 'Folder navigator diagnostic environment contracts passed.'
  exit 0
fi

assert_completion_contracts() {
  local runner="$1"
  local label="$2"
  local identifier='CompletionTests.known()'
  local identifier_regex='^CompletionTests\.known\(\)$'

  reset_invocations
  FAKE_LIST_OUTPUT="$identifier" \
    FAKE_RUN_OUTPUT=$'✔ Test known() passed after 0.001 seconds.\n◇ Test stale() started.' \
    run_capture "$fixture_state/output" "$runner" "$identifier_regex"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "$label incomplete zero exit unexpectedly passed"
  assert_completion_error
  assert_root_lock

  reset_invocations
  FAKE_LIST_OUTPUT="$identifier" \
    FAKE_RUN_OUTPUT='' \
    run_capture "$fixture_state/output" "$runner" "$identifier_regex"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "$label silent zero exit unexpectedly passed"
  assert_completion_error
  assert_root_lock

  reset_invocations
  FAKE_LIST_OUTPUT="$identifier" \
    FAKE_RUN_OUTPUT='✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.' \
    run_capture "$fixture_state/output" "$runner" "$identifier_regex"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "$label zero-test summary unexpectedly passed"
  assert_completion_error
  assert_root_lock

  reset_invocations
  FAKE_LIST_OUTPUT="$identifier" \
    FAKE_RUN_OUTPUT='✘ Test run with 1 test in 0 suites failed after 0.001 seconds with 1 issue.' \
    run_capture "$fixture_state/output" "$runner" "$identifier_regex"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "$label failure summary unexpectedly passed"
  assert_completion_error
  assert_root_lock

  reset_invocations
  FAKE_LIST_OUTPUT="$identifier" \
    FAKE_RUN_OUTPUT='✔ Test run with 2 tests in 1 suite passed after 0.001 seconds.' \
    run_capture "$fixture_state/output" "$runner" "$identifier_regex"
  assert_status 0
  /usr/bin/grep -Fxq \
    '✔ Test run with 2 tests in 1 suite passed after 0.001 seconds.' \
    "$fixture_state/output" || fail "$label did not stream successful test output"
  assert_root_lock

  reset_invocations
  FAKE_LIST_OUTPUT="$identifier" \
    FAKE_RUN_OUTPUT='◇ Test known() started.' \
    FAKE_RUN_EXIT=37 \
    run_capture "$fixture_state/output" "$runner" "$identifier_regex"
  assert_status 37
  assert_root_lock
}

run_crashing_ordinary() {
  cd "$foreign_root"
  exec env \
    PATH="$fixture_bin:$PATH" \
    FLECK_TEST_APPKIT_OPEN_PATH="$fixture_bin/open" \
    FLECK_TEST_APPKIT_SAMPLE_PATH="$fixture_bin/sample" \
    FLECK_TEST_APPKIT_CODESIGN_PATH="$fixture_bin/codesign" \
    FAKE_STATE="$fixture_state" \
    FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
    FAKE_BLOCK_LIST_MARKER="$crash_blocked" \
    FAKE_RELEASE_LIST_MARKER="$crash_release" \
    FAKE_SWIFT_PID_FILE="$crash_swift_pid_file" \
    "$fixture_scripts/run-nonempty-swift-tests.sh" \
      '^FleckCoreTests\.known\(\)$'
}

reset_invocations
run_capture "$fixture_state/output" run_ordinary ''
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary runner accepted an empty regex'
run_capture "$fixture_state/output" run_ordinary 'FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary runner accepted an unanchored regex'
[[ ! -s "$fixture_state/swift-invocations" ]] ||
  fail 'invalid regex reached swift'

readonly real_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
readonly real_platform="$(/usr/bin/xcrun --sdk macosx --show-sdk-platform-path)"
readonly real_frameworks="$real_platform/Developer/Library/Frameworks"
readonly real_host="$fixture_state/AppKitTestHost"
readonly real_host_config="$fixture_state/real-host-configuration"
readonly real_host_receipt="$fixture_state/real-host-receipt"
readonly real_host_process="$fixture_state/real-host-process"
readonly real_host_phase="$fixture_state/real-host-phase"
readonly real_host_log="$fixture_state/real-host-log"
"$(/usr/bin/xcrun --sdk macosx --find swiftc)" -parse-as-library \
  -sdk "$real_sdk" -F "$real_frameworks" \
  -framework AppKit -framework Testing \
  -Xlinker -rpath -Xlinker "$real_frameworks" \
  "$appkit_host_source" -o "$real_host"

prepare_real_host_configuration() {
  local nonce
  nonce="$(/usr/bin/uuidgen | /usr/bin/tr -d '\r\n')"
  printf '%s\0' "$nonce" "$real_host_receipt" "$real_host_process" \
    "$real_host_phase" "$real_host_log" > "$real_host_config"
  /bin/rm -f -- "$real_host_receipt" "$real_host_process" \
    "$real_host_phase" "$real_host_log"
}

readonly bundle_validation_line="$(/usr/bin/grep -nF \
  'try loadTestBundle(at: parsedArguments.bundlePath)' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
readonly list_branch_line="$(/usr/bin/grep -nF \
  'if parsedArguments.testingArguments.listTests == true' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
readonly appkit_initialization_line="$(/usr/bin/grep -nF \
  'let application = NSApplication.shared' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
readonly launch_guard_line="$(/usr/bin/grep -nF \
  'guard !didStartTestRun' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
readonly activation_request_line="$(/usr/bin/grep -nF \
  'application.activate(ignoringOtherApps: true)' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
readonly activation_task_line="$(/usr/bin/grep -nF \
  'Task { @MainActor in' "$appkit_host_source" | \
  /usr/bin/tail -n 1 | /usr/bin/cut -d: -f1)"
readonly running_phase_line="$(/usr/bin/grep -nF \
  'configuration.writePhase("runningTests")' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
readonly run_entry_line="$(/usr/bin/grep -nF \
  'Testing.__swiftPMEntryPoint(passing: testingArguments)' "$appkit_host_source" | \
  /usr/bin/head -n 1 | /usr/bin/cut -d: -f1)"
[[ -n "$bundle_validation_line" && -n "$list_branch_line" && \
  -n "$appkit_initialization_line" && \
  "$bundle_validation_line" -lt "$list_branch_line" && \
  "$list_branch_line" -lt "$appkit_initialization_line" ]] ||
  fail 'AppKit initialization precedes CPU-only bundle/list validation'
[[ -n "$launch_guard_line" && -n "$activation_request_line" && \
  -n "$activation_task_line" && \
  "$launch_guard_line" -lt "$activation_request_line" && \
  "$activation_request_line" -lt "$activation_task_line" ]] ||
  fail 'AppKit test run is not guarded against a duplicate launch callback'
[[ -n "$running_phase_line" && -n "$run_entry_line" && \
  "$((run_entry_line - running_phase_line))" -eq 1 ]] ||
  fail 'AppKit host does not record runningTests before entering Swift Testing'

run_capture "$fixture_state/output" "$real_host" /missing/test-bundle --bogus
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native host accepted an unsupported argument'
/usr/bin/grep -Fq 'error: unsupported test argument: --bogus' \
  "$fixture_state/output" || fail 'native host did not report its unsupported argument'

prepare_real_host_configuration
run_capture "$fixture_state/output" "$real_host" /missing/test-bundle \
  --host-config "$real_host_config"
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native host accepted a missing test bundle'
/usr/bin/grep -Fq 'error: test bundle binary is missing' "$real_host_log" ||
  fail 'native host did not report its missing test bundle'
/usr/bin/grep -Fxq 'completed' "$real_host_phase" ||
  fail 'native host did not complete its missing-bundle receipt'
/usr/bin/grep -Fq $'\t1\n' "$real_host_receipt" ||
  fail 'native host did not record its missing-bundle status'

printf '%s\n' 'not a Mach-O test bundle' > "$fixture_state/invalid-test-bundle"
prepare_real_host_configuration
run_capture "$fixture_state/output" "$real_host" \
  "$fixture_state/invalid-test-bundle" --list-tests \
  --filter '^FleckCoreTests\\.known\\(\\)$' --host-config "$real_host_config"
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native host loaded an invalid test bundle'
/usr/bin/grep -Fq 'error: failed to load test bundle:' "$real_host_log" ||
  fail 'native host did not report its test bundle loading failure'
/usr/bin/grep -Fxq 'completed' "$real_host_phase" ||
  fail 'native host did not complete its invalid-bundle receipt'

assert_completion_contracts run_ordinary ordinary
assert_completion_contracts run_enhanced enhanced

reset_invocations
FAKE_PRESERVE_HOST_APP_PATH="$fixture_state/preserved-host.app" \
FLECK_ENHANCED_CANDIDATE='' \
FAKE_LIST_OUTPUT=$'TargetA.first()\nTargetB.second()' \
  FAKE_EXPECT_FILTER='^.+$' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" run_ordinary '^.+$'
assert_status 0
/usr/bin/grep -Fxq 'matched test count: 2' "$fixture_state/output" ||
  fail 'ordinary whole-suite selection did not retain its exact non-empty count'
[[ "$(wc -l < "$fixture_state/host-app-paths" | tr -d ' ')" -eq 2 ]] ||
  fail 'ordinary runner did not launch separate list and run host apps'
while IFS= read -r host_app_path; do
  [[ ! -e "$host_app_path" ]] || fail 'ordinary runner retained its temporary AppKit host app'
done < "$fixture_state/host-app-paths"
/usr/bin/grep -Fxq 'environment:FLECK_ENHANCED_CANDIDATE' \
  "$fixture_state/open-environments" ||
  fail 'LaunchServices host did not receive the enhanced-candidate environment name'
[[ "$(wc -l < "$fixture_state/open-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'ordinary runner did not use LaunchServices for both host invocations'
[[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'ordinary runner did not sign and verify its temporary host app once'
/usr/bin/grep -Fq -- '--force --deep --sign - ' \
  "$fixture_state/codesign-invocations" ||
  fail 'temporary host app was not signed ad hoc and recursively'
/usr/bin/grep -Fq -- '--verify --deep --strict --verbose=2 ' \
  "$fixture_state/codesign-invocations" ||
  fail 'temporary host app was not deep/strict verified before launch'
assert_root_lock

existing_host_app="$fixture_state/preserved-host.app"
[[ -d "$existing_host_app" && ! -L "$existing_host_app" ]] ||
  fail 'fake LaunchServices did not preserve a reusable host app'
[[ ! -e "$existing_host_app/Contents/Resources" && \
  ! -L "$existing_host_app/Contents/Resources" ]] ||
  fail 'ordinary test host unexpectedly contains candidate app resources'
preserved_host_files=(
  "$existing_host_app/Contents/Info.plist"
  "$existing_host_app/Contents/MacOS/AppKitTestHost"
  "$existing_host_app/Contents/.fixture-adhoc-signature"
)
/usr/bin/shasum -a 256 "${preserved_host_files[@]}" \
  > "$fixture_state/preserved-host-before.sha256"
reset_invocations
: > "$fixture_state/host-path-forwarding-contract"
FLECK_TEST_APPKIT_HOST_APP_PATH="$existing_host_app" \
FAKE_LIST_OUTPUT=$'TargetA.first()\nTargetB.second()' \
  run_capture "$fixture_state/output" run_ordinary '^.+$'
assert_status 0
[[ "$(wc -l < "$fixture_state/host-app-paths" | tr -d ' ')" -eq 2 ]] ||
  fail 'configured existing host was not reused for list and run phases'
while IFS= read -r host_app_path; do
  [[ "$host_app_path" = "$existing_host_app" ]] ||
    fail 'LaunchServices did not receive the configured existing host app'
done < "$fixture_state/host-app-paths"
[[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -eq 3 ]] ||
  fail 'configured existing host was not strictly verified after the temporary host'
/usr/bin/grep -Fq -- \
  "--verify --deep --strict --verbose=2 $existing_host_app" \
  "$fixture_state/codesign-invocations" ||
  fail 'configured existing host did not receive deep/strict signature verification'
if /usr/bin/grep -Fxq 'environment:FLECK_TEST_APPKIT_HOST_APP_PATH' \
  "$fixture_state/open-environments"; then
  fail 'AppKit host path configuration was forwarded through LaunchServices'
fi
temporary_host_app="$(/usr/bin/sed -n '1p' "$fixture_state/signed-app-paths")"
[[ -n "$temporary_host_app" && ! -e "$temporary_host_app" ]] ||
  fail 'configured-host run retained its owned temporary helper app'
/usr/bin/shasum -a 256 "${preserved_host_files[@]}" \
  > "$fixture_state/preserved-host-after.sha256"
/usr/bin/cmp -s "$fixture_state/preserved-host-before.sha256" \
  "$fixture_state/preserved-host-after.sha256" ||
  fail 'configured existing host app changed during verification or cleanup'
assert_root_lock

/bin/ln -s "$existing_host_app" "$fixture_state/symlink-host.app"
assert_configured_host_rejected "$fixture_state/symlink-host.app" \
  'configured AppKit test host path is unsafe or incomplete'

/bin/cp -R "$existing_host_app" "$fixture_state/mismatched-binary-host.app"
printf '%s\n' 'mismatched executable' \
  > "$fixture_state/mismatched-binary-host.app/Contents/MacOS/AppKitTestHost"
/bin/chmod +x "$fixture_state/mismatched-binary-host.app/Contents/MacOS/AppKitTestHost"
assert_configured_host_rejected "$fixture_state/mismatched-binary-host.app" \
  'configured AppKit test host executable does not match the current build'

/bin/cp -R "$existing_host_app" "$fixture_state/mismatched-info-host.app"
printf '%s\n' 'mismatched Info.plist' \
  > "$fixture_state/mismatched-info-host.app/Contents/Info.plist"
assert_configured_host_rejected "$fixture_state/mismatched-info-host.app" \
  'configured AppKit test host Info.plist does not match the current build'

/bin/cp -R "$existing_host_app" "$fixture_state/symlink-binary-host.app"
/bin/rm "$fixture_state/symlink-binary-host.app/Contents/MacOS/AppKitTestHost"
/bin/ln -s "$existing_host_app/Contents/MacOS/AppKitTestHost" \
  "$fixture_state/symlink-binary-host.app/Contents/MacOS/AppKitTestHost"
assert_configured_host_rejected "$fixture_state/symlink-binary-host.app" \
  'configured AppKit test host path is unsafe or incomplete'

/bin/cp -R "$existing_host_app" "$fixture_state/symlink-info-host.app"
/bin/rm "$fixture_state/symlink-info-host.app/Contents/Info.plist"
/bin/ln -s "$existing_host_app/Contents/Info.plist" \
  "$fixture_state/symlink-info-host.app/Contents/Info.plist"
assert_configured_host_rejected "$fixture_state/symlink-info-host.app" \
  'configured AppKit test host path is unsafe or incomplete'

/bin/cp -R "$existing_host_app" "$fixture_state/unsigned-host.app"
/bin/rm "$fixture_state/unsigned-host.app/Contents/.fixture-adhoc-signature"
assert_configured_host_rejected "$fixture_state/unsigned-host.app" \
  'configured AppKit test host failed strict signature verification' 100
[[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -eq 3 ]] ||
  fail 'configured existing host was not independently deep/strict verified'
/usr/bin/shasum -a 256 "${preserved_host_files[@]}" \
  > "$fixture_state/preserved-host-after-rejections.sha256"
/usr/bin/cmp -s "$fixture_state/preserved-host-before.sha256" \
  "$fixture_state/preserved-host-after-rejections.sha256" ||
  fail 'configured-host rejection modified the preserved matching host'

reset_invocations
: > "$fixture_state/environment-forwarding-contract"
unset FLECK_NATIVE_CAPTURE_QA FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC
run_capture "$fixture_state/output" run_appkit_environment_probe
assert_status 0
[[ "$(wc -l < "$fixture_state/open-environment-name-blocks" | tr -d ' ')" -eq 2 ]] ||
  fail 'AppKit list and run hosts did not both record their forwarded environment names'
[[ "$(sed -n '1p' "$fixture_state/open-environment-name-blocks")" = \
  "$(sed -n '2p' "$fixture_state/open-environment-name-blocks")" ]] ||
  fail 'AppKit list and run hosts received different environment-name lists'
for environment_name in FLECK_SETTINGS_WINDOW_CAPTURE_DIR \
  FLECK_SETTINGS_MODELS_CAPTURE_DIR; do
  forwarded_count="$(/usr/bin/grep -Fxc "environment:$environment_name" \
    "$fixture_state/open-environments" || true)"
  [[ "$forwarded_count" -eq 2 ]] ||
    fail 'AppKit host did not forward a set whitelist variable to both phases'
done
for environment_assignment in \
  'FLECK_SETTINGS_WINDOW_CAPTURE_DIR=' \
  'FLECK_SETTINGS_MODELS_CAPTURE_DIR=mock capture path with spaces = $literal * [glob]; "quoted"'; do
  forwarded_count="$(/usr/bin/grep -Fxc "environment:$environment_assignment" \
    "$fixture_state/open-environment-probes" || true)"
  [[ "$forwarded_count" -eq 2 ]] ||
    fail 'AppKit host did not forward the exact whitelist assignment to both phases'
done
for environment_name in FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR \
  FLECK_TEST_UNWHITELISTED_CAPTURE_PROBE FLECK_NATIVE_CAPTURE_QA \
  FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC; do
  if /usr/bin/grep -E -q "^environment:$environment_name(=|$)" \
    "$fixture_state/open-environments"; then
    fail 'AppKit host forwarded an unset or unwhitelisted environment name'
  fi
done
if /usr/bin/grep -Fq 'environment:FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR=' \
  "$fixture_state/open-environment-probes"; then
  fail 'AppKit host forwarded an unset whitelist assignment'
fi
if /usr/bin/grep -E -q '(^| )[^ ]+=' \
  "$fixture_state/open-environment-name-blocks"; then
  fail 'AppKit host serialized an environment value in the forwarded-name list'
fi
if /usr/bin/grep -Fq 'mock capture path with spaces' \
  "$fixture_state/open-invocations" ||
  /usr/bin/grep -Fq 'mock unlisted value' "$fixture_state/open-invocations"; then
  fail 'fake LaunchServices invocation log exposed an environment value'
fi
[[ "$(wc -l < "$fixture_state/host-environment-observations" | tr -d ' ')" -eq 2 ]] ||
  fail 'AppKit list/run hosts did not both receive the expected environment values'
/usr/bin/grep -Fxq 'pass' "$fixture_state/host-environment-observations" ||
  fail 'AppKit host forwarded-environment contract failed'

for native_capture_value in 0 1; do
  reset_invocations
  : > "$fixture_state/environment-forwarding-contract"
  FLECK_NATIVE_CAPTURE_QA="$native_capture_value" \
    run_capture "$fixture_state/output" run_appkit_environment_probe
  assert_status 0
  forwarded_count="$(/usr/bin/grep -Fxc \
    "environment:FLECK_NATIVE_CAPTURE_QA=$native_capture_value" \
    "$fixture_state/open-environment-probes" || true)"
  [[ "$forwarded_count" -eq 2 ]] ||
    fail "AppKit host did not forward FLECK_NATIVE_CAPTURE_QA=$native_capture_value to both phases"
done

unset FLECK_NATIVE_CAPTURE_QA
for invalid_native_capture_value in '' 2 true; do
  reset_invocations
  FLECK_NATIVE_CAPTURE_QA="$invalid_native_capture_value" \
    run_capture "$fixture_state/output" run_appkit_environment_probe
  [[ "$RUN_STATUS" -ne 0 ]] ||
    fail "AppKit host accepted invalid FLECK_NATIVE_CAPTURE_QA value '$invalid_native_capture_value'"
  /usr/bin/grep -Fq 'FLECK_NATIVE_CAPTURE_QA' "$fixture_state/output" ||
    fail 'invalid native capture opt-in was not reported explicitly'
  [[ ! -s "$fixture_state/xcrun-invocations" && \
    ! -s "$fixture_state/swiftc-invocations" && \
    ! -s "$fixture_state/open-invocations" ]] ||
    fail 'invalid native capture opt-in reached a build or host launch'
done
unset FLECK_NATIVE_CAPTURE_QA
unset FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC
assert_root_lock
assert_folder_navigator_diagnostic_forwarding_contracts

reset_invocations
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_HOST_LOAD_EXIT=41 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 41
/usr/bin/grep -Fq 'error: failed to load test bundle: fixture failure' \
  "$fixture_state/output" || fail 'ordinary runner hid the native loading failure'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_NO_RECEIPT_PHASE=runningTests \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary runner accepted a missing host receipt'
/usr/bin/grep -Fq 'error: AppKit test host completion receipt is missing' \
  "$fixture_state/output" || fail 'missing host receipt was not rejected explicitly'
assert_root_lock

reset_invocations
FAKE_RECEIPT_NONCE=wrong-invocation \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary runner accepted a mismatched host receipt'
/usr/bin/grep -Fq 'error: AppKit test host completion receipt does not match this invocation' \
  "$fixture_state/output" || fail 'mismatched host receipt was not rejected explicitly'
assert_root_lock

reset_invocations
FAKE_RECEIPT_PID=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary runner accepted a receipt from another PID'
/usr/bin/grep -Fq 'error: AppKit test host completion receipt does not match this invocation' \
  "$fixture_state/output" || fail 'foreign-PID host receipt was not rejected explicitly'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_RUN_EXIT=256 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary runner accepted an invalid Swift Testing status'
/usr/bin/grep -Fq 'error: AppKit test host returned an invalid Swift Testing status' \
  "$fixture_state/output" || fail 'invalid host status was not rejected explicitly'
assert_root_lock

reset_invocations
FAKE_OPEN_EXIT=47 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 47
/usr/bin/grep -Fq 'error: /usr/bin/open -W returned status 47' \
  "$fixture_state/output" || fail 'LaunchServices failure status was not propagated'
assert_root_lock

reset_invocations
/bin/sleep 30 >/dev/null 2>&1 &
decoy_pid=$!
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_OPEN_RETURN_EARLY=1 \
  FAKE_OPEN_CHILD_PID_FILE="$fixture_state/early-open-child-pid" \
  FAKE_HOST_HANG_PHASE=listingTests \
  FAKE_OPEN_WAIT_PHASE=listingTests \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
/bin/kill -0 "$decoy_pid" 2>/dev/null || {
  fail 'early-return cleanup terminated an unrelated decoy process'
}
/bin/kill -TERM "$decoy_pid" 2>/dev/null || true
wait "$decoy_pid" 2>/dev/null || true
decoy_pid=''
/usr/bin/grep -Fq 'error: /usr/bin/open -W returned while owned AppKit test host PID' \
  "$fixture_state/output" || fail 'early LaunchServices return was not detected'
/usr/bin/grep -Fq 'last phase: listingTests' "$fixture_state/output" ||
  fail 'early-return diagnostics omitted the last host phase'
[[ "$(cat "$fixture_state/early-open-child-pid")" = \
  "$(cat "$fixture_state/sample-pids")" ]] ||
  fail 'early-return cleanup did not sample the invocation-owned host PID'
assert_root_lock

reset_invocations
/bin/sleep 30 >/dev/null 2>&1 &
decoy_pid=$!
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_OPEN_RETURN_EARLY_RUN=1 \
  FAKE_OPEN_WAIT_PHASE=runningTests \
  FAKE_OPEN_CHILD_PID_FILE="$fixture_state/run-early-host-pid" \
  FAKE_OPEN_PID_FILE="$fixture_state/run-early-open-pid" \
  FAKE_HOST_HANG_PHASE=runningTests \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 1
/usr/bin/grep -Fq 'error: /usr/bin/open -W returned while owned AppKit test host PID' \
  "$fixture_state/output" || fail 'run-phase early LaunchServices return was not detected'
/usr/bin/grep -Fq 'last phase: runningTests' "$fixture_state/output" ||
  fail 'run-phase early-return diagnostics omitted the runningTests phase'
[[ "$(cat "$fixture_state/run-early-host-pid")" = \
  "$(cat "$fixture_state/sample-pids")" ]] ||
  fail 'run-phase early-return cleanup did not sample the owned host PID'
assert_pid_stopped "$(cat "$fixture_state/run-early-host-pid")" \
  'run-phase early-return host'
assert_pid_stopped "$(cat "$fixture_state/run-early-open-pid")" \
  'run-phase early-return open child'
assert_host_state_removed
/bin/kill -0 "$decoy_pid" 2>/dev/null || {
  fail 'run-phase early-return cleanup terminated an unrelated decoy process'
}
/bin/kill -TERM "$decoy_pid" 2>/dev/null || true
wait "$decoy_pid" 2>/dev/null || true
decoy_pid=''
assert_root_lock

reset_invocations
/bin/sleep 30 >/dev/null 2>&1 &
decoy_pid=$!
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_SIGNAL_RUNNER_PHASE=runningTests \
  FAKE_HOST_HANG_PHASE=runningTests \
  FAKE_OPEN_PID_FILE="$fixture_state/term-open-pid" \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 143
[[ "$(cat "$fixture_state/term-open-pid")" = \
  "$(cat "$fixture_state/sample-pids")" ]] ||
  fail 'run-phase TERM cleanup did not sample the owned open/host PID'
sampled_pid="$(cat "$fixture_state/term-open-pid")"
/usr/bin/grep -Fq \
  'error: interrupted while running the AppKit test host (status 143)' \
  "$fixture_state/output" || fail 'TERM interruption diagnostics were not caller-visible'
/usr/bin/grep -Fq \
  'error: AppKit test host was interrupted; last phase: runningTests; owned PID:' \
  "$fixture_state/output" || fail 'TERM cleanup omitted the runningTests host diagnostic'
/usr/bin/grep -Fq "fixture stack for pid $sampled_pid" "$fixture_state/output" ||
  fail 'TERM cleanup sample stack was not caller-visible'
/usr/bin/grep -Fq -- '--- last AppKit test host output ---' "$fixture_state/output" ||
  fail 'TERM cleanup host log header was not caller-visible'
/usr/bin/grep -Fq 'fixture host output tail for runningTests' "$fixture_state/output" ||
  fail 'TERM cleanup host log tail was not caller-visible'
assert_pid_stopped "$(cat "$fixture_state/term-open-pid")" \
  'run-phase TERM open/host'
assert_host_state_removed
/bin/kill -0 "$decoy_pid" 2>/dev/null || {
  fail 'run-phase TERM cleanup terminated an unrelated decoy process'
}
/bin/kill -TERM "$decoy_pid" 2>/dev/null || true
wait "$decoy_pid" 2>/dev/null || true
decoy_pid=''
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_HOST_HANG=1 \
  run_capture "$fixture_state/output" env \
    PATH="$fixture_bin:$PATH" \
    FLECK_TEST_APPKIT_OPEN_PATH="$fixture_bin/open" \
    FLECK_TEST_APPKIT_SAMPLE_PATH="$fixture_bin/sample" \
    FLECK_TEST_APPKIT_CODESIGN_PATH="$fixture_bin/codesign" \
    FLECK_TEST_APPKIT_WATCHDOG_SECONDS=1 \
    FAKE_STATE="$fixture_state" \
    FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
    "$fixture_scripts/run-nonempty-swift-tests.sh" \
      '^FleckCoreTests\.known\(\)$'
assert_status 124
/usr/bin/grep -Fq 'error: AppKit test host watchdog terminated the owned host' \
  "$fixture_state/output" || fail 'AppKit host watchdog did not report its timeout'
/usr/bin/grep -Fq 'last phase: runningTests' "$fixture_state/output" ||
  fail 'watchdog diagnostics omitted the runningTests phase'
[[ -s "$fixture_state/sample-pids" ]] ||
  fail 'AppKit host watchdog did not sample the timed-out host'
assert_root_lock

reset_invocations
FAKE_BUILD_EXIT=42 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 42
[[ ! -s "$fixture_state/host-invocations" ]] ||
  fail 'failed SwiftPM test build reached the native host'
assert_root_lock

reset_invocations
FAKE_HOST_BUILD_EXIT=43 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 43
[[ ! -s "$fixture_state/host-invocations" ]] ||
  fail 'failed native host build reached test execution'
assert_root_lock

reset_invocations
FAKE_CODESIGN_SIGN_EXIT=44 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 44
/usr/bin/grep -Fq 'error: failed to ad-hoc sign the temporary AppKit test host' \
  "$fixture_state/output" || fail 'ad-hoc signing failure was not reported'
[[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -eq 1 ]] ||
  fail 'signature verification ran after ad-hoc signing failed'
[[ ! -s "$fixture_state/host-invocations" ]] ||
  fail 'ad-hoc signing failure reached LaunchServices'
assert_root_lock

reset_invocations
FAKE_CODESIGN_VERIFY_EXIT=45 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 45
/usr/bin/grep -Fq 'error: temporary AppKit test host failed strict signature verification' \
  "$fixture_state/output" || fail 'strict signature failure was not reported'
[[ "$(wc -l < "$fixture_state/codesign-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'ad-hoc signature was not verified before LaunchServices'
[[ ! -s "$fixture_state/host-invocations" ]] ||
  fail 'signature verification failure reached LaunchServices'
assert_root_lock

reset_invocations
FAKE_SKIP_BUNDLE=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'missing test bundle unexpectedly passed'
/usr/bin/grep -Fq 'error: expected exactly one freshly built Swift test bundle, found 0' \
  "$fixture_state/output" || fail 'missing test bundle was not rejected explicitly'
assert_root_lock

reset_invocations
FAKE_MULTIPLE_BUNDLES=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ambiguous test bundles unexpectedly passed'
/usr/bin/grep -Fq 'error: expected exactly one freshly built Swift test bundle, found 2' \
  "$fixture_state/output" || fail 'ambiguous test bundles were not rejected explicitly'
assert_root_lock

reset_invocations
/bin/mv "$fixture_state/platform/Developer/Library/Frameworks/Testing.framework" \
  "$fixture_state/Testing.framework.hidden"
run_capture "$fixture_state/output" run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'missing selected Testing framework unexpectedly passed'
/usr/bin/grep -Fq 'error: selected macOS platform has no Testing framework:' \
  "$fixture_state/output" || fail 'missing selected Testing framework was not rejected explicitly'
/bin/mv "$fixture_state/Testing.framework.hidden" \
  "$fixture_state/platform/Developer/Library/Frameworks/Testing.framework"
assert_root_lock

readonly old_coordination_artifact="$fixture_root/.build/.fleck-nonempty-swift-tests.lock"
readonly coordination_artifact="$fixture_root/.build/.fleck-nonempty-swift-tests.lockf"
/bin/mkdir -p "$old_coordination_artifact"
printf '%s\n' 'stale artifact' > "$coordination_artifact"
readonly stale_reached_swift="$fixture_state/stale-reached-swift"
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_REACHED_SWIFT_MARKER="$stale_reached_swift" \
  run_ordinary '^FleckCoreTests\.known\(\)$' \
  > "$fixture_state/stale-output" 2>&1 &
stale_runner_pid=$!
for _ in {1..20}; do
  [[ -e "$stale_reached_swift" ]] && break
  /bin/sleep 0.05
done
if [[ ! -e "$stale_reached_swift" ]]; then
  /bin/kill -TERM "$stale_runner_pid" 2>/dev/null || true
  wait "$stale_runner_pid" || true
  fail 'a stale coordination artifact blocked the runner'
fi
wait "$stale_runner_pid"
[[ -d "$old_coordination_artifact" && -f "$coordination_artifact" ]] ||
  fail 'runner deleted a stale coordination artifact'

reset_invocations
ordinary_unchanged_inode="$(/usr/bin/stat -f %i "$fixture_root/Package.resolved")"
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.missing\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'ordinary no-match unexpectedly passed'
[[ "$(wc -l < "$fixture_state/swift-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'ordinary no-match used an unexpected SwiftPM build sequence'
/usr/bin/grep -Fq "$fixture_root|build --build-tests --disable-automatic-resolution" \
  "$fixture_state/swift-invocations" || fail 'ordinary tests were not built from the repository root'
[[ "$(wc -l < "$fixture_state/host-invocations" | tr -d ' ')" -eq 1 ]] ||
  fail 'ordinary no-match invoked the native filtered test run'
/usr/bin/grep -Fq '|1||0' "$fixture_state/host-invocations" ||
  fail 'ordinary no-match did not list through the native host'
[[ "$(/usr/bin/stat -f %i "$fixture_root/Package.resolved")" = \
  "$ordinary_unchanged_inode" ]] || fail 'ordinary runner replaced an unchanged root lock'
assert_root_lock

readonly nested_root="$fixture_root/Tools/Nested"
/bin/mkdir -p "$nested_root"
printf '// nested fixture package\n' > "$nested_root/Package.swift"
printf 'ordinary nested lock\n' > "$nested_root/Package.resolved"
/bin/mkdir -p "$temp_root/outside-package"
printf '// outside fixture package\n' > "$temp_root/outside-package/Package.swift"
/bin/ln -s "$temp_root/outside-package" "$fixture_root/Tools/EscapingLink"

reset_invocations
FAKE_LIST_OUTPUT='NestedTests.known()' \
  run_capture "$fixture_state/output" \
  run_ordinary --package-path Tools/Nested '^NestedTests\.missing\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'nested no-match unexpectedly passed'
/usr/bin/grep -Fq "$nested_root|test list --disable-automatic-resolution" \
  "$fixture_state/swift-invocations" || fail 'nested list used the wrong package cwd'
/usr/bin/grep -Fxq 'ordinary nested lock' "$nested_root/Package.resolved" ||
  fail 'nested Package.resolved changed after no-match'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='NestedTests.known()' \
  FAKE_EXPECT_FILTER='^(NestedTests\.known\(\)/)' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" \
  run_ordinary --package-path Tools/Nested '^NestedTests\.known\(\)$'
assert_status 0
[[ ! -s "$fixture_state/host-invocations" ]] ||
  fail 'research package unexpectedly used the AppKit host'
/usr/bin/grep -Fq "$nested_root|test --disable-automatic-resolution --no-parallel" \
  "$fixture_state/swift-invocations" ||
  fail 'research package did not retain ordinary serial SwiftPM execution'
/usr/bin/grep -Fxq 'ordinary nested lock' "$nested_root/Package.resolved" ||
  fail 'nested Package.resolved changed after successful research run'
assert_root_lock

for unsafe_path in /tmp ../outside Tools/../Nested Tools/Missing Tools/EscapingLink; do
  reset_invocations
  run_capture "$fixture_state/output" run_ordinary \
    --package-path "$unsafe_path" '^NestedTests\.known\(\)$'
  [[ "$RUN_STATUS" -ne 0 ]] || fail "unsafe package path passed: $unsafe_path"
  [[ ! -s "$fixture_state/swift-invocations" ]] ||
    fail "unsafe package path reached swift: $unsafe_path"
done

reset_invocations
FAKE_LIST_OUTPUT=$'build log\nFleckCoreTests.known()\nnot an identifier' \
  FAKE_RUN_EXIT=23 \
  FAKE_EXPECT_FILTER='^(FleckCoreTests\.known\(\)/)' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 23
/usr/bin/grep -Fxq 'matched test: FleckCoreTests.known()' "$fixture_state/output" ||
  fail 'ordinary runner did not report the matched canonical identifier'
[[ "$(wc -l < "$fixture_state/swift-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'ordinary match used an unexpected SwiftPM build sequence'
[[ "$(wc -l < "$fixture_state/host-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'ordinary match did not run native list and filtered test exactly once'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT=$'TargetA.foo()\nTargetA.foobar()\nTargetB.foo()' \
  FAKE_RUNTIME_IDENTIFIERS=$'TargetA.foo()/case\nTargetA.foobar()/case\nTargetB.foo()/case' \
  FAKE_EXPECT_FILTER='^(TargetA\.foo\(\)/)' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^TargetA\.foo\(\)$'
assert_status 0
/usr/bin/grep -Fxq 'matched test count: 1' "$fixture_state/output" ||
  fail 'ordinary runner did not print the exact positive match count'
[[ "$(cat "$fixture_state/selected-runtime-identifiers")" = \
  'TargetA.foo()/case' ]] || fail 'derived filter selected a target or name collision'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT=$'Target.ParamSuite/positional(_:)\nTarget.ParamSuite/pinned(isPinned:)\nTarget.ParamSuite/host(hostCase:)\nTarget.ParamSuite/notCanonical(bad;:)' \
  FAKE_RUNTIME_IDENTIFIERS=$'Target.ParamSuite/positional(_:)/case-1\nTarget.ParamSuite/pinned(isPinned:)/case-1\nTarget.ParamSuite/host(hostCase:)/case-1' \
  FAKE_EXPECT_FILTER='^(Target\.ParamSuite/positional\(_:\)/|Target\.ParamSuite/pinned\(isPinned:\)/|Target\.ParamSuite/host\(hostCase:\)/)' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^Target\.ParamSuite/.*\(.*:\)$'
assert_status 0
/usr/bin/grep -Fxq 'matched test count: 3' "$fixture_state/output" ||
  fail 'parameterized canonical identifiers were not all counted'
[[ "$(wc -l < "$fixture_state/selected-runtime-identifiers" | tr -d ' ')" -eq 3 ]] ||
  fail 'parameterized canonical identifiers were not all executed'
assert_root_lock

reset_invocations
printf 'ordinary nested lock\n' > "$nested_root/Package.resolved"
FAKE_LIST_OUTPUT='NestedTests.known()' \
  FAKE_MUTATE_LOCK="$nested_root/Package.resolved" \
  run_capture "$fixture_state/output" \
  run_ordinary --package-path Tools/Nested '^NestedTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'nested lock mutation unexpectedly passed'
/usr/bin/grep -Fxq 'ordinary nested lock' "$nested_root/Package.resolved" ||
  fail 'nested Package.resolved was not restored after mutation'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_MUTATE_LOCK="$fixture_root/Package.resolved" \
  FAKE_SIGNAL_RUNNER=1 \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
assert_status 143
assert_root_lock

reset_invocations
enhanced_unchanged_inode="$(/usr/bin/stat -f %i "$fixture_root/Package.resolved")"
FAKE_LIST_OUTPUT='FleckAppTests.EnhancedKnown()' \
  run_capture "$fixture_state/output" \
  run_enhanced '^FleckAppTests\.EnhancedMissing\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'enhanced no-match unexpectedly passed'
[[ "$(wc -l < "$fixture_state/swift-invocations" | tr -d ' ')" -eq 2 ]] ||
  fail 'enhanced no-match used an unexpected SwiftPM build sequence'
[[ "$(wc -l < "$fixture_state/host-invocations" | tr -d ' ')" -eq 1 ]] ||
  fail 'enhanced no-match invoked the native filtered test run'
resolver_root="$(cat "$fixture_state/resolver-root")"
[[ "$resolver_root" != "$fixture_root" ]] ||
  fail 'enhanced resolver ran against the actual repository root'
/usr/bin/grep -Fq "$resolver_root|build --build-tests --disable-automatic-resolution --scratch-path" \
  "$fixture_state/swift-invocations" || {
    /bin/cat "$fixture_state/swift-invocations" >&2
    fail 'enhanced tests were not built from the resolver shadow root'
  }
[[ "$(/usr/bin/stat -f %i "$fixture_root/Package.resolved")" = \
  "$enhanced_unchanged_inode" ]] || fail 'enhanced runner replaced an unchanged root lock'
enhanced_scratch="$(cat "$fixture_state/enhanced-scratch")"
[[ ! -e "$(dirname -- "$enhanced_scratch")" ]] ||
  fail 'enhanced no-match left its temporary parent behind'
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='FleckAppTests.EnhancedKnown()' \
  FAKE_RUN_EXIT=29 \
  FAKE_EXPECT_FILTER='^(FleckAppTests\.EnhancedKnown\(\)/)' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" \
  run_enhanced '^FleckAppTests\.EnhancedKnown\(\)$'
assert_status 29
/usr/bin/grep -Fxq 'matched test: FleckAppTests.EnhancedKnown()' \
  "$fixture_state/output" ||
  fail 'enhanced runner did not report the matched canonical identifier'
assert_root_lock

reset_invocations
printf 'ordinary root lock\n' > "$fixture_root/Package.resolved"
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_MUTATE_LOCK="$fixture_root/Package.resolved" \
  FAKE_READONLY_LOCK_PARENT="$fixture_root" \
  run_capture "$fixture_state/output" \
  run_ordinary '^FleckCoreTests\.known\(\)$'
[[ "$RUN_STATUS" -ne 0 ]] || fail 'restoration failure unexpectedly passed'
/usr/bin/grep -Fq 'error: failed to restore root Package.resolved' \
  "$fixture_state/output" || fail 'restoration failure was not reported explicitly'
/bin/chmod 700 "$fixture_root"
if [[ -e "$fixture_root/Package.resolved" ]]; then
  /bin/chmod 600 "$fixture_root/Package.resolved"
fi
printf 'ordinary root lock\n' > "$fixture_root/Package.resolved"
assert_root_lock

reset_invocations
readonly first_blocked="$fixture_state/first-blocked"
readonly release_first="$fixture_state/release-first"
readonly second_reached_swift="$fixture_state/second-reached-swift"
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_BLOCK_LIST_MARKER="$first_blocked" \
  FAKE_RELEASE_LIST_MARKER="$release_first" \
  run_ordinary '^FleckCoreTests\.known\(\)$' \
  > "$fixture_state/concurrent-first-output" 2>&1 &
first_pid=$!
for _ in {1..100}; do
  [[ -e "$first_blocked" ]] && break
  /bin/sleep 0.05
done
[[ -e "$first_blocked" ]] || fail 'first concurrent runner did not reach swift'
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_REACHED_SWIFT_MARKER="$second_reached_swift" \
  run_enhanced '^FleckCoreTests\.known\(\)$' \
  > "$fixture_state/concurrent-second-output" 2>&1 &
second_pid=$!
/bin/sleep 0.2
if [[ -e "$second_reached_swift" ]]; then
  /usr/bin/touch "$release_first"
  wait "$first_pid" || true
  wait "$second_pid" || true
  fail 'concurrent runner entered swift before the repository lock was released'
fi
/usr/bin/touch "$release_first"
set +e
wait "$first_pid"
first_status=$?
wait "$second_pid"
second_status=$?
set -e
[[ "$first_status" -eq 0 && "$second_status" -eq 0 ]] ||
  fail "concurrent runners failed: $first_status, $second_status"
[[ -e "$second_reached_swift" ]] || fail 'second concurrent runner never resumed'
assert_root_lock

reset_invocations
readonly crash_blocked="$fixture_state/crash-blocked"
readonly crash_release="$fixture_state/crash-release"
readonly crash_swift_pid_file="$fixture_state/crash-swift-pid"
run_crashing_ordinary > "$fixture_state/crash-owner-output" 2>&1 &
crash_owner_pid=$!
for _ in {1..100}; do
  [[ -e "$crash_blocked" && -s "$crash_swift_pid_file" ]] && break
  /bin/sleep 0.05
done
[[ -e "$crash_blocked" && -s "$crash_swift_pid_file" ]] || {
  /bin/kill -KILL "$crash_owner_pid" 2>/dev/null || true
  wait "$crash_owner_pid" 2>/dev/null || true
  fail 'crash fixture did not acquire the coordination lock'
}
crash_swift_pid="$(cat "$crash_swift_pid_file")"
set +e
{
  /bin/kill -KILL "$crash_owner_pid"
  /bin/kill -KILL "$crash_swift_pid" 2>/dev/null || true
  wait "$crash_owner_pid"
} 2>/dev/null
crash_owner_status=$?
set -e
[[ "$crash_owner_status" -eq 137 ]] ||
  fail "force-killed owner returned unexpected status: $crash_owner_status"

readonly crash_recovery_reached="$fixture_state/crash-recovery-reached"
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  FAKE_REACHED_SWIFT_MARKER="$crash_recovery_reached" \
  run_ordinary '^FleckCoreTests\.known\(\)$' \
  > "$fixture_state/crash-recovery-output" 2>&1 &
crash_recovery_pid=$!
for _ in {1..40}; do
  [[ -e "$crash_recovery_reached" ]] && break
  /bin/sleep 0.05
done
if [[ ! -e "$crash_recovery_reached" ]]; then
  /bin/kill -TERM "$crash_recovery_pid" 2>/dev/null || true
  wait "$crash_recovery_pid" 2>/dev/null || true
  fail 'force-killed owner left coordination permanently blocked'
fi
wait "$crash_recovery_pid"
assert_root_lock

reset_invocations
FAKE_LIST_OUTPUT='FleckAppTests.EnhancedKnown()' \
  FAKE_MUTATE_LOCK="$fixture_root/Package.resolved" \
  FAKE_SIGNAL_RUNNER=1 \
  run_capture "$fixture_state/output" \
  run_enhanced '^FleckAppTests\.EnhancedKnown\(\)$'
assert_status 143
enhanced_scratch="$(cat "$fixture_state/enhanced-scratch")"
[[ ! -e "$(dirname -- "$enhanced_scratch")" ]] ||
  fail 'enhanced interruption left its temporary parent behind'
assert_root_lock

reset_invocations
FAKE_RESOLVER_FAIL=1 \
  FAKE_RESOLVER_EXIT=31 \
  run_capture "$fixture_state/output" \
  run_enhanced '^FleckAppTests\.EnhancedKnown\(\)$'
assert_status 31
assert_root_lock

reset_invocations
/bin/mkdir "$fixture_state/existing-scratch"
run_capture "$fixture_state/output" env \
  FAKE_STATE="$fixture_state" \
  "$script_dir/resolve-enhanced-candidate.sh" \
    "$fixture_state/existing-scratch" /usr/bin/true
[[ "$RUN_STATUS" -ne 0 ]] || fail 'real resolver accepted an existing scratch path'
/bin/rm -rf -- "$fixture_state/existing-scratch"
assert_root_lock

assert_candidate_resource_source_rejected \
  'candidate SwiftPM App resource bundle is missing or unsafe' \
  FAKE_CANDIDATE_RESOURCE_BUNDLE_MISSING=1
assert_candidate_resource_source_rejected \
  'candidate SwiftPM App resource bundle is missing or unsafe' \
  FAKE_CANDIDATE_RESOURCE_BUNDLE_SYMLINK=1
assert_candidate_resource_source_rejected \
  'candidate SwiftPM App resource bundle does not contain exactly the expected metadata documents' \
  FAKE_CANDIDATE_RESOURCE_MISSING=ThirdPartyNotices.md
assert_candidate_resource_source_rejected \
  'candidate SwiftPM App resource bundle does not contain exactly the expected metadata documents' \
  FAKE_CANDIDATE_RESOURCE_EXTRA=1
assert_candidate_resource_source_rejected \
  'candidate SwiftPM App resource document is missing or unsafe: ThirdPartyNotices.md' \
  FAKE_CANDIDATE_RESOURCE_SYMLINK=ThirdPartyNotices.md

reset_invocations
FAKE_PRESERVE_HOST_APP_PATH="$fixture_state/candidate-preserved-host.app" \
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  run_capture "$fixture_state/output" run_enhanced \
    '^FleckCoreTests\.known\(\)$'
assert_status 0
candidate_preserved_host="$fixture_state/candidate-preserved-host.app"
candidate_preserved_resource_bundle="$candidate_preserved_host/Contents/Resources/Fleck_FleckApp.bundle"
[[ -d "$candidate_preserved_resource_bundle" && ! -L "$candidate_preserved_resource_bundle" ]] ||
  fail 'candidate test host did not preserve the SwiftPM app resources'
[[ "$(/usr/bin/find "$candidate_preserved_host/Contents/Resources" -mindepth 1 -maxdepth 1 -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 && \
  "$(/usr/bin/find "$candidate_preserved_resource_bundle" -mindepth 1 -maxdepth 1 -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 4 ]] ||
  fail 'candidate test host did not preserve exactly the four flat metadata documents'
for resource_name in "${candidate_resource_names[@]}"; do
  /usr/bin/cmp -s "$fixture_state/bin/Fleck_FleckApp.bundle/$resource_name" \
    "$candidate_preserved_resource_bundle/$resource_name" ||
    fail "candidate test host resource bytes differ from the SwiftPM output: $resource_name"
done
[[ ! -e "$candidate_preserved_resource_bundle/weights.safetensors" && \
  ! -e "$candidate_preserved_host/Contents/Resources/model.safetensors" && \
  ! -e "$candidate_preserved_host/Contents/Resources/gemma-cleanup-helper" ]] ||
  fail 'candidate test host included model weights or a helper executable'
candidate_preserved_host_files=(
  "$candidate_preserved_host/Contents/Info.plist"
  "$candidate_preserved_host/Contents/MacOS/AppKitTestHost"
  "$candidate_preserved_host/Contents/.fixture-adhoc-signature"
  "$candidate_preserved_resource_bundle/EnhancedModelManifest.json"
  "$candidate_preserved_resource_bundle/GemmaCleanupModelManifest.json"
  "$candidate_preserved_resource_bundle/GemmaCleanupNotice.md"
  "$candidate_preserved_resource_bundle/ThirdPartyNotices.md"
)
/usr/bin/shasum -a 256 "${candidate_preserved_host_files[@]}" \
  > "$fixture_state/candidate-preserved-before.sha256"
assert_root_lock

reset_invocations
FLECK_TEST_APPKIT_HOST_APP_PATH="$candidate_preserved_host" \
FAKE_LIST_OUTPUT='FleckCoreTests.known()' \
  run_capture "$fixture_state/output" run_enhanced \
    '^FleckCoreTests\.known\(\)$'
assert_status 0
[[ "$(wc -l < "$fixture_state/host-app-paths" | /usr/bin/tr -d ' ')" -eq 2 ]] ||
  fail 'configured candidate host was not reused for list and run phases'
while IFS= read -r host_app_path; do
  [[ "$host_app_path" = "$candidate_preserved_host" ]] ||
    fail 'LaunchServices did not receive the exactly matching configured candidate host'
done < "$fixture_state/host-app-paths"
/usr/bin/shasum -a 256 "${candidate_preserved_host_files[@]}" \
  > "$fixture_state/candidate-preserved-after.sha256"
/usr/bin/cmp -s "$fixture_state/candidate-preserved-before.sha256" \
  "$fixture_state/candidate-preserved-after.sha256" ||
  fail 'configured candidate host changed during resource verification or reuse'
assert_root_lock

/bin/cp -R "$candidate_preserved_host" \
  "$fixture_state/mismatched-candidate-resource-host.app"
printf '%s\n' 'mismatched candidate resource' > \
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/Resources/Fleck_FleckApp.bundle/ThirdPartyNotices.md"
mismatched_candidate_resource_files=(
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/Info.plist"
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/MacOS/AppKitTestHost"
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/.fixture-adhoc-signature"
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/Resources/Fleck_FleckApp.bundle/EnhancedModelManifest.json"
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/Resources/Fleck_FleckApp.bundle/GemmaCleanupModelManifest.json"
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/Resources/Fleck_FleckApp.bundle/GemmaCleanupNotice.md"
  "$fixture_state/mismatched-candidate-resource-host.app/Contents/Resources/Fleck_FleckApp.bundle/ThirdPartyNotices.md"
)
/usr/bin/shasum -a 256 "${mismatched_candidate_resource_files[@]}" \
  > "$fixture_state/mismatched-candidate-resource-before.sha256"
assert_configured_candidate_host_rejected \
  "$fixture_state/mismatched-candidate-resource-host.app" \
  'configured AppKit test host candidate resource does not match the current build: ThirdPartyNotices.md'
/usr/bin/shasum -a 256 "${mismatched_candidate_resource_files[@]}" \
  > "$fixture_state/mismatched-candidate-resource-after.sha256"
/usr/bin/cmp -s "$fixture_state/mismatched-candidate-resource-before.sha256" \
  "$fixture_state/mismatched-candidate-resource-after.sha256" ||
  fail 'configured candidate-host resource rejection modified the configured host'

native_qa_runner="$script_dir/run-native-capture-qa.sh"
[[ -x "$native_qa_runner" ]] || fail 'native capture QA entrypoint is missing or not executable'
native_qa_fixture="$temp_root/native-qa-repo"
native_qa_scripts="$native_qa_fixture/Scripts"
native_qa_bin="$native_qa_fixture/bin"
native_qa_tmp="$temp_root/native-qa-output"
native_qa_log="$native_qa_fixture/invocations"
native_qa_commit_change_marker="$native_qa_fixture/commit-changed"
native_qa_worktree_change_marker="$native_qa_fixture/worktree-changed"
/bin/mkdir -p "$native_qa_scripts" "$native_qa_bin" "$native_qa_tmp"
/bin/cp "$native_qa_runner" "$native_qa_scripts/"
/bin/cp "$script_dir/../VERSION" "$native_qa_fixture/VERSION"
: > "$native_qa_log"

cat > "$native_qa_bin/git" <<'SH'
#!/bin/sh
set -eu
[ "${1:-}" = -C ] || exit 90
shift 2
case "${1:-}" in
  rev-parse)
    shift
    case "$*" in
      '--verify HEAD^{commit}')
        [ "${FAKE_NATIVE_QA_GIT_FAILURE:-}" != commit ] || exit 93
        if [ "${FAKE_NATIVE_QA_GIT_BAD_HASH:-0}" = 1 ]; then
          printf '%s\n' 'short-id'
        elif [ -n "${FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER:-}" ] &&
          [ -f "$FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER" ]; then
          printf '%s\n' '3333333333333333333333333333333333333333'
        else
          printf '%s\n' '1111111111111111111111111111111111111111'
        fi
        ;;
      '--verify 1111111111111111111111111111111111111111^{tree}')
        [ "${FAKE_NATIVE_QA_GIT_FAILURE:-}" != tree ] || exit 94
        printf '%s\n' '2222222222222222222222222222222222222222'
        ;;
      '--verify 3333333333333333333333333333333333333333^{tree}')
        [ "${FAKE_NATIVE_QA_GIT_FAILURE:-}" != tree ] || exit 94
        printf '%s\n' '4444444444444444444444444444444444444444'
        ;;
      *) exit 92 ;;
    esac
    ;;
  status)
    shift
    [ "$*" = '--porcelain --untracked-files=all --ignore-submodules=none' ] || exit 92
    [ "${FAKE_NATIVE_QA_GIT_FAILURE:-}" != status ] || exit 95
    if [ "${FAKE_NATIVE_QA_INITIAL_DIRTY:-0}" = 1 ] ||
      { [ -n "${FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER:-}" ] &&
        [ -f "$FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER" ]; }; then
      printf '%s\n' ' M Sources/fixture.swift'
    fi
    ;;
  *) exit 91 ;;
esac
SH
/bin/chmod +x "$native_qa_bin/git"

cat > "$native_qa_scripts/run-nonempty-swift-tests.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'flag=%s\n' "${FLECK_NATIVE_CAPTURE_QA-unset}" >> "$FAKE_NATIVE_QA_LOG"
printf 'capture_dir=%s\n' "${FLECK_GLASS_SYNTHETIC_CAPTURE_DIR-unset}" >> "$FAKE_NATIVE_QA_LOG"
printf 'selector=%s\n' "${1:-}" >> "$FAKE_NATIVE_QA_LOG"
printf 'host=%s\n' "${FLECK_TEST_APPKIT_HOST_APP_PATH-unset}" >> "$FAKE_NATIVE_QA_LOG"
printf 'candidate=%s\n' "${FLECK_ENHANCED_CANDIDATE-unset}" >> "$FAKE_NATIVE_QA_LOG"
[[ "${FLECK_NATIVE_CAPTURE_QA:-}" = 1 ]] || exit 88
[[ ! ${FLECK_ENHANCED_CANDIDATE+x} ]] || exit 91
case "${FLECK_GLASS_SYNTHETIC_CAPTURE_DIR:-}" in
  "$TMPDIR"/fleck-native-capture-qa.*) ;;
  *) exit 89 ;;
esac
[[ "$#" -eq 1 && "$1" = '^FleckAppTests\.hostedGlassAndSolidMenuPanelsCaptureSyntheticChromeAndOpaqueEditor\(\)$' ]] || exit 90
case "${FAKE_NATIVE_QA_CHANGE_AFTER_RUN:-}" in
  commit) : > "$FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER" ;;
  worktree) : > "$FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER" ;;
esac
exit "${FAKE_NATIVE_QA_STATUS:-0}"
SH
/bin/chmod +x "$native_qa_scripts/run-nonempty-swift-tests.sh"

for source_lookup_failure in commit tree status; do
  FAKE_NATIVE_QA_GIT_FAILURE="$source_lookup_failure" \
  FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
  FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
  TMPDIR="$native_qa_tmp" \
  PATH="$native_qa_bin:/usr/bin:/bin" \
  FAKE_NATIVE_QA_LOG="$native_qa_log" \
    run_capture "$native_qa_fixture/lookup-$source_lookup_failure-output" \
      "$native_qa_scripts/run-native-capture-qa.sh"
  [[ "$RUN_STATUS" -ne 0 ]] ||
    fail "native capture QA accepted failed $source_lookup_failure provenance lookup"
  [[ ! -s "$native_qa_log" ]] ||
    fail "native capture QA launched its runner after failed $source_lookup_failure provenance lookup"
  if /usr/bin/grep -q '^Output directory:' \
    "$native_qa_fixture/lookup-$source_lookup_failure-output"; then
    fail "native capture QA created output evidence after failed $source_lookup_failure provenance lookup"
  fi
done

FAKE_NATIVE_QA_GIT_BAD_HASH=1 \
FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
TMPDIR="$native_qa_tmp" \
PATH="$native_qa_bin:/usr/bin:/bin" \
FAKE_NATIVE_QA_LOG="$native_qa_log" \
  run_capture "$native_qa_fixture/short-hash-output" \
    "$native_qa_scripts/run-native-capture-qa.sh"
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native capture QA accepted a short source commit ID'
[[ ! -s "$native_qa_log" ]] || fail 'native capture QA launched its runner after a short source ID'

FAKE_NATIVE_QA_INITIAL_DIRTY=1 \
FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
TMPDIR="$native_qa_tmp" \
PATH="$native_qa_bin:/usr/bin:/bin" \
FAKE_NATIVE_QA_LOG="$native_qa_log" \
  run_capture "$native_qa_fixture/dirty-source-output" \
    "$native_qa_scripts/run-native-capture-qa.sh"
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native capture QA accepted a dirty committed source checkout'
[[ ! -s "$native_qa_log" ]] || fail 'native capture QA launched its runner from a dirty source checkout'
if /usr/bin/grep -q '^Output directory:' "$native_qa_fixture/dirty-source-output"; then
  fail 'native capture QA created output evidence for a dirty source checkout'
fi
if compgen -G "$native_qa_tmp/fleck-native-capture-qa.*" > /dev/null; then
  fail 'native capture QA created an output directory before source preflight passed'
fi

FLECK_NATIVE_CAPTURE_QA=0 \
FLECK_GLASS_SYNTHETIC_CAPTURE_DIR="$native_qa_fixture/ignored-output" \
FLECK_TEST_APPKIT_HOST_APP_PATH="$native_qa_fixture/Existing Host.app" \
TMPDIR="$native_qa_tmp" \
PATH="$native_qa_bin:/usr/bin:/bin" \
FAKE_NATIVE_QA_LOG="$native_qa_log" \
FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
FLECK_ENHANCED_CANDIDATE=1 \
  run_capture "$native_qa_fixture/first-output" "$native_qa_scripts/run-native-capture-qa.sh"
[[ "$RUN_STATUS" -eq 0 ]] ||
  fail "expected native capture QA status 0, got $RUN_STATUS; output: $(cat "$native_qa_fixture/first-output")"
native_qa_directory_1="$(/usr/bin/sed -n 's/^Output directory: //p' \
  "$native_qa_fixture/first-output")"
[[ -n "$native_qa_directory_1" && -d "$native_qa_directory_1" && \
  ! -L "$native_qa_directory_1" && -f "$native_qa_directory_1/console.log" && \
  ! -L "$native_qa_directory_1/console.log" ]] ||
  fail 'native capture QA did not preserve a unique safe output directory and console receipt'
case "$native_qa_directory_1" in
  "$native_qa_tmp"/fleck-native-capture-qa.*) ;;
  *) fail 'native capture QA output directory was not created under the caller temp parent' ;;
esac
[[ "$(/usr/bin/stat -f %Lp "$native_qa_directory_1")" = 700 ]] ||
  fail 'native capture QA output directory permissions are not private'
/usr/bin/grep -Fqx "flag=1" "$native_qa_log" ||
  fail 'native capture QA did not override a caller 0 opt-in with literal 1'
/usr/bin/grep -Fqx "capture_dir=$native_qa_directory_1" "$native_qa_log" ||
  fail 'native capture QA did not route capture output to its fresh directory'
/usr/bin/grep -Fqx \
  'selector=^FleckAppTests\.hostedGlassAndSolidMenuPanelsCaptureSyntheticChromeAndOpaqueEditor\(\)$' \
  "$native_qa_log" || fail 'native capture QA did not use the exact strict test selector'
/usr/bin/grep -Fqx "host=$native_qa_fixture/Existing Host.app" "$native_qa_log" ||
  fail 'native capture QA did not preserve the caller-configured host path'
/usr/bin/grep -Fqx 'candidate=unset' "$native_qa_log" ||
  fail 'native capture QA did not select the ordinary test graph'
/usr/bin/grep -Fq 'Source commit: 1111111111111111111111111111111111111111' \
  "$native_qa_directory_1/console.log" || fail 'native capture QA omitted its source commit receipt'
/usr/bin/grep -Fq 'Source tree: 2222222222222222222222222222222222222222' \
  "$native_qa_directory_1/console.log" || fail 'native capture QA omitted its source tree receipt'
/usr/bin/grep -Fq 'Working source status: clean' "$native_qa_directory_1/console.log" ||
  fail 'native capture QA omitted its initial clean source status receipt'
/usr/bin/grep -Fq 'Native capture QA source verification after run: clean and unchanged' \
  "$native_qa_directory_1/console.log" ||
  fail 'native capture QA did not verify the committed source remained clean after execution'
/usr/bin/grep -Fq "Fleck version: $(tr -d '\n' < "$script_dir/../VERSION")" \
  "$native_qa_directory_1/console.log" || fail 'native capture QA omitted its version receipt'

unset FLECK_NATIVE_CAPTURE_QA
TMPDIR="$native_qa_tmp" \
PATH="$native_qa_bin:/usr/bin:/bin" \
FAKE_NATIVE_QA_LOG="$native_qa_log" \
FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
  run_capture "$native_qa_fixture/second-output" "$native_qa_scripts/run-native-capture-qa.sh"
[[ "$RUN_STATUS" -eq 0 ]] ||
  fail "expected native capture QA status 0, got $RUN_STATUS; output: $(cat "$native_qa_fixture/second-output")"
native_qa_directory_2="$(/usr/bin/sed -n 's/^Output directory: //p' \
  "$native_qa_fixture/second-output")"
[[ -n "$native_qa_directory_2" && "$native_qa_directory_2" != "$native_qa_directory_1" && \
  -d "$native_qa_directory_2" && ! -L "$native_qa_directory_2" && \
  -f "$native_qa_directory_2/console.log" ]] ||
  fail 'native capture QA reused or overwrote a prior output directory'
/usr/bin/grep -Fqx "flag=1" "$native_qa_log" ||
  fail 'native capture QA false-passed without an inherited opt-in value'
/usr/bin/grep -Fqx "capture_dir=$native_qa_directory_2" "$native_qa_log" ||
  fail 'native capture QA did not create a fresh directory on its second invocation'

FAKE_NATIVE_QA_STATUS=37 \
TMPDIR="$native_qa_tmp" \
PATH="$native_qa_bin:/usr/bin:/bin" \
FAKE_NATIVE_QA_LOG="$native_qa_log" \
FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
  run_capture "$native_qa_fixture/failure-output" "$native_qa_scripts/run-native-capture-qa.sh"
[[ "$RUN_STATUS" -eq 37 ]] ||
  fail "expected native capture QA status 37, got $RUN_STATUS; output: $(cat "$native_qa_fixture/failure-output")"
native_qa_failure_directory="$(/usr/bin/sed -n 's/^Output directory: //p' \
  "$native_qa_fixture/failure-output")"
/usr/bin/grep -Fq 'Native capture QA runner exit status: 37' \
  "$native_qa_failure_directory/console.log" ||
  fail 'native capture QA did not retain its nonzero status receipt'
/usr/bin/grep -Fq 'Native capture QA source verification after run: clean and unchanged' \
  "$native_qa_failure_directory/console.log" ||
  fail 'native capture QA did not verify source after a failed test run'

for source_change in commit worktree; do
  FAKE_NATIVE_QA_CHANGE_AFTER_RUN="$source_change" \
  FAKE_NATIVE_QA_COMMIT_CHANGE_MARKER="$native_qa_commit_change_marker" \
  FAKE_NATIVE_QA_WORKTREE_CHANGE_MARKER="$native_qa_worktree_change_marker" \
  TMPDIR="$native_qa_tmp" \
  PATH="$native_qa_bin:/usr/bin:/bin" \
  FAKE_NATIVE_QA_LOG="$native_qa_log" \
    run_capture "$native_qa_fixture/source-change-$source_change-output" \
      "$native_qa_scripts/run-native-capture-qa.sh"
  [[ "$RUN_STATUS" -ne 0 ]] ||
    fail "native capture QA accepted a $source_change source change during execution"
  native_qa_source_change_directory="$(/usr/bin/sed -n 's/^Output directory: //p' \
    "$native_qa_fixture/source-change-$source_change-output")"
  [[ -n "$native_qa_source_change_directory" && \
    -f "$native_qa_source_change_directory/console.log" ]] ||
    fail "native capture QA did not preserve the $source_change source-change receipt"
  /usr/bin/grep -Fq 'Native capture QA source verification after run: FAILED' \
    "$native_qa_source_change_directory/console.log" ||
    fail "native capture QA falsely claimed unchanged source after $source_change change"
  /usr/bin/grep -Fq 'Native capture QA runner exit status: 0' \
    "$native_qa_source_change_directory/console.log" ||
    fail "native capture QA omitted the successful test status after $source_change change"
  /bin/rm -f "$native_qa_commit_change_marker" "$native_qa_worktree_change_marker"
done

python3 - "$script_dir/.." <<'PY'
import hashlib
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
workflow_path = root / ".github/workflows/ci.yml"
current_workflow = workflow_path.read_text()

def job_block(contents, job_id):
    match = re.search(rf"^  {re.escape(job_id)}:\n", contents, re.M)
    if match is None:
        raise SystemExit(f"missing supplemental CI job: {job_id}")
    following = re.search(r"^  [A-Za-z0-9_-]+:\n", contents[match.end():], re.M)
    end = match.end() + following.start() if following else len(contents)
    return match.start(), end, contents[match.start():end]

dispatch = re.search(
    r"^  workflow_dispatch:\n(?P<body>.*?)(?=^permissions:\n)",
    current_workflow,
    re.M | re.S,
)
if dispatch is None or dispatch.group("body").count("folder_navigator_probe:") != 1:
    raise SystemExit("workflow_dispatch must declare one folder_navigator_probe input")
input_match = re.search(
    r"^      folder_navigator_probe:\n(?:^ {8}.*\n)+",
    current_workflow,
    re.M,
)
if input_match is None:
    raise SystemExit("folder_navigator_probe input block is missing")
input_block = input_match.group(0)
for required in ("required: false", "type: boolean", "default: false"):
    if required not in input_block:
        raise SystemExit(f"folder_navigator_probe input omitted: {required}")

supplemental_jobs = (
    (
        "folder-navigator-diagnostic",
        "Supplemental folder navigator diagnostic (ordinary)",
        "Scripts/run-nonempty-swift-tests.sh '^.*FolderNavigatorPresentationTests.*$'",
        False,
    ),
    (
        "folder-navigator-diagnostic-enhanced",
        "Supplemental folder navigator diagnostic (Enhanced)",
        "Scripts/run-nonempty-enhanced-tests.sh '^.*FolderNavigatorPresentationTests.*$'",
        True,
    ),
)
for job_id, job_name, selector, enhanced in supplemental_jobs:
    _, _, block = job_block(current_workflow, job_id)
    for required in (
        f"name: {job_name}",
        "if: ${{ github.event_name == 'workflow_dispatch' && inputs.folder_navigator_probe }}",
        'FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC: "1"',
        'test "$source_commit" = "$GITHUB_SHA"',
        selector,
    ):
        if required not in block:
            raise SystemExit(f"supplemental CI job {job_id} omitted: {required}")
    if enhanced != ("Scripts/test-enhanced-candidate-pin.sh" in block):
        raise SystemExit(f"supplemental CI job {job_id} has unexpected candidate pin validation")

def step_block(contents, name):
    match = re.search(rf"^      - name: {re.escape(name)}\n", contents, re.M)
    if match is None:
        raise SystemExit(f"missing CI step: {name}")
    following = re.search(r"^      - name: ", contents[match.end():], re.M)
    end = match.end() + following.start() if following else len(contents)
    return match.start(), end, contents[match.start():end]

ordinary_name = "Test ordinary graph"
candidate_name = "Test Enhanced Local candidate graph"
ordinary = step_block(current_workflow, ordinary_name)[2]
candidate = step_block(current_workflow, candidate_name)[2]
for name, block, selector in (
    (ordinary_name, ordinary, "Scripts/run-nonempty-swift-tests.sh '^.+$'"),
    (candidate_name, candidate, "Scripts/run-nonempty-enhanced-tests.sh '^.+$'"),
):
    if 'FLECK_NATIVE_CAPTURE_QA: "0"' not in block or selector not in block:
        raise SystemExit(f"CI {name} did not explicitly disable only native capture QA")

boundary_names = (
    "Declare native capture boundary (ordinary graph)",
    "Declare native capture boundary (candidate graph)",
)
normalized_workflow = current_workflow
normalized_workflow = normalized_workflow.replace(input_block, "", 1)
for job_id, _, _, _ in supplemental_jobs:
    start, end, _ = job_block(normalized_workflow, job_id)
    if start >= 2 and normalized_workflow[start - 2:start] == "\n\n":
        start -= 1
    normalized_workflow = normalized_workflow[:start] + normalized_workflow[end:]
for name in boundary_names:
    start, end, block = step_block(normalized_workflow, name)
    for required in (
        "Strict native screenshot/pixel capture: NOT RUN",
        "separate native-QA artifact and status-receipt evidence",
        "does not claim full native screenshot coverage",
        "All other full-graph selectors and assertions remain enabled",
        '>> "$GITHUB_STEP_SUMMARY"',
    ):
        if required not in block:
            raise SystemExit(f"CI disclosure step {name} omitted: {required}")
    normalized_workflow = normalized_workflow[:start] + normalized_workflow[end:]

for name in (ordinary_name, candidate_name):
    start, end, block = step_block(normalized_workflow, name)
    environment = '        env:\n          FLECK_NATIVE_CAPTURE_QA: "0"\n'
    if block.count(environment) != 1:
        raise SystemExit(f"CI {name} has unexpected native-capture environment changes")
    normalized_workflow = (
        normalized_workflow[:start]
        + block.replace(environment, "", 1)
        + normalized_workflow[end:]
    )
if hashlib.sha256(normalized_workflow.encode()).hexdigest() != (
    "da0fb3074c3cb3dcf77223d43f4cf536f4cf36bbd9699d5027a89f9385a5aa0e"
):
    raise SystemExit("CI changed outside the declared native-capture boundary fixture")

test_name = "hostedGlassAndSolidMenuPanelsCaptureSyntheticChromeAndOpaqueEditor"
test_path = root / "Tests/FleckAppTests/AppKitEditorTests.swift"
current_tests = test_path.read_text()

def test_function(contents, name):
    match = re.search(
        rf"^(?:private )?func {re.escape(name)}\(\) async throws \{{\n(.*?)^\}}",
        contents,
        re.M | re.S,
    )
    if match is None:
        raise SystemExit(f"missing native capture test function: {name}")
    return match.group(1)

if test_function(current_tests, test_name) != (
    "  try #require(CGPreflightScreenCaptureAccess())\n"
    "  try await captureHostedGlassAndSolidMenuPanels()\n"
):
    raise SystemExit("strict native capture test body changed")
if current_tests.count('ProcessInfo.processInfo.environment["FLECK_NATIVE_CAPTURE_QA"]') != 1:
    raise SystemExit("strict native capture test has unexpected opt-in traits")
strict_declaration = current_tests[current_tests.rfind("@Test", 0, current_tests.index(f"func {test_name}")):current_tests.index(f"func {test_name}")]
expected_declaration = (
    "@Test(\n"
    "  .enabled(\n"
    '    if: ProcessInfo.processInfo.environment["FLECK_NATIVE_CAPTURE_QA"] == "1"\n'
    "  )\n"
    ")\n"
    "@MainActor\n"
)
if strict_declaration != expected_declaration:
    raise SystemExit("strict native capture test is not gated only by the explicit 1 opt-in")

capture_helper_body = test_function(current_tests, "captureHostedGlassAndSolidMenuPanels")
if hashlib.sha256(capture_helper_body.encode()).hexdigest() != (
    "d60b00e7db651347ddaabff61d058fe0ef75b8033e65bdbc43a115fd5a00fbbc"
):
    raise SystemExit("strict native capture helper body changed from its approved fixture")

probe_name = "hostedOwnWindowCaptureCapabilityProbe"
probe_function_start = current_tests.index(f"func {probe_name}")
probe_annotation_start = current_tests.rfind("@Test", 0, probe_function_start)
probe_declaration = current_tests[probe_annotation_start:probe_function_start]
expected_probe_declaration = (
    "@Test(\n"
    "  .enabled(\n"
    '    if: ProcessInfo.processInfo.environment["FLECK_GLASS_SYNTHETIC_CAPTURE_DIR"] != nil\n'
    "  )\n"
    ")\n"
    "@MainActor\n"
)
expected_probe_body = (
    "  let preflightObservation = CGPreflightScreenCaptureAccess()\n"
    '  print("CGPreflightScreenCaptureAccess() observation only: \\(preflightObservation)")\n'
    "  try await captureHostedGlassAndSolidMenuPanels()\n"
)
if (
    probe_declaration != expected_probe_declaration
    or test_function(current_tests, probe_name) != expected_probe_body
):
    raise SystemExit("supplemental own-window capture probe changed")
PY

printf '%s\n' 'Non-empty Swift test runner contracts passed.'
