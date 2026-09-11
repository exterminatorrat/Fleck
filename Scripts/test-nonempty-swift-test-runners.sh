#!/usr/bin/env bash
set -euo pipefail

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

cleanup() {
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
  "$fixture_state/sdk"
/bin/cp "$ordinary_runner" "$enhanced_runner" "$appkit_runner" "$fixture_scripts/"
/bin/cp "$appkit_host_source" "$fixture_root/Tests/Support/"
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
#!/bin/sh
set -eu

printf '%s\n' "$*" >> "$FAKE_STATE/host-invocations"
if [ -n "${FAKE_REACHED_SWIFT_MARKER:-}" ]; then
  /usr/bin/touch "$FAKE_REACHED_SWIFT_MARKER"
fi
if [ -n "${FAKE_SWIFT_PID_FILE:-}" ]; then
  printf '%s\n' "$$" > "$FAKE_SWIFT_PID_FILE"
fi
if [ "${FAKE_HOST_LOAD_EXIT:-0}" != 0 ]; then
  printf '%s\n' 'error: failed to load test bundle: fixture failure' >&2
  exit "$FAKE_HOST_LOAD_EXIT"
fi
if [ "${2:-}" = --list-tests ]; then
  if [ -n "${FAKE_BLOCK_LIST_MARKER:-}" ]; then
    /usr/bin/touch "$FAKE_BLOCK_LIST_MARKER"
    while [ ! -e "$FAKE_RELEASE_LIST_MARKER" ]; do
      /bin/sleep 0.05
    done
  fi
  printf '%s\n' "${FAKE_LIST_OUTPUT:-}"
  exit "${FAKE_LIST_EXIT:-0}"
fi

saw_no_parallel=0
actual_filter=''
shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --filter)
      actual_filter="${2:-}"
      shift 2
      ;;
    --no-parallel)
      saw_no_parallel=1
      shift
      ;;
    *)
      printf 'error: unsupported fake host argument: %s\n' "$1" >&2
      exit 94
      ;;
  esac
done
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
SH
/bin/chmod +x "$fixture_state/fake-appkit-host"

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

assert_completion_error() {
  /usr/bin/grep -Fq \
    'error: Swift test exited successfully without a final non-empty passing test summary' \
    "$fixture_state/output" || fail 'missing Swift test completion error'
}

reset_invocations() {
  : > "$fixture_state/swift-invocations"
  : > "$fixture_state/swiftc-invocations"
  : > "$fixture_state/xcrun-invocations"
  : > "$fixture_state/host-invocations"
  : > "$fixture_state/output"
  printf 'ordinary root lock\n' > "$fixture_root/Package.resolved"
  /bin/rm -rf -- "$fixture_state/bin"
  /bin/rm -f -- "$fixture_state/enhanced-scratch" \
    "$fixture_state/resolver-root-backup" \
    "$fixture_state/resolver-root" \
    "$fixture_state/selected-runtime-identifiers"
}

run_ordinary() {
  (
    cd "$foreign_root"
    PATH="$fixture_bin:$PATH" \
      FAKE_STATE="$fixture_state" \
      "$fixture_scripts/run-nonempty-swift-tests.sh" "$@"
  )
}

run_enhanced() {
  (
    cd "$foreign_root"
    PATH="$fixture_bin:$PATH" \
      FAKE_STATE="$fixture_state" \
      FAKE_ACTUAL_ROOT="$fixture_root" \
      "$fixture_scripts/run-nonempty-enhanced-tests.sh" "$@"
  )
}

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
"$(/usr/bin/xcrun --sdk macosx --find swiftc)" -parse-as-library \
  -sdk "$real_sdk" -F "$real_frameworks" \
  -framework AppKit -framework Testing \
  -Xlinker -rpath -Xlinker "$real_frameworks" \
  "$appkit_host_source" -o "$real_host"
run_capture "$fixture_state/output" "$real_host" /missing/test-bundle --bogus
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native host accepted an unsupported argument'
/usr/bin/grep -Fq 'error: unsupported test argument: --bogus' \
  "$fixture_state/output" || fail 'native host did not report its unsupported argument'
run_capture "$fixture_state/output" "$real_host" /missing/test-bundle
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native host accepted a missing test bundle'
/usr/bin/grep -Fq 'error: test bundle binary is missing' "$fixture_state/output" ||
  fail 'native host did not report its missing test bundle'
printf '%s\n' 'not a Mach-O test bundle' > "$fixture_state/invalid-test-bundle"
run_capture "$fixture_state/output" "$real_host" "$fixture_state/invalid-test-bundle"
[[ "$RUN_STATUS" -ne 0 ]] || fail 'native host loaded an invalid test bundle'
/usr/bin/grep -Fq 'error: failed to load test bundle:' "$fixture_state/output" ||
  fail 'native host did not report its test bundle loading failure'

assert_completion_contracts run_ordinary ordinary
assert_completion_contracts run_enhanced enhanced

reset_invocations
FAKE_LIST_OUTPUT=$'TargetA.first()\nTargetB.second()' \
  FAKE_EXPECT_FILTER='^.+$' \
  FAKE_EXPECT_NO_PARALLEL=1 \
  run_capture "$fixture_state/output" run_ordinary '^.+$'
assert_status 0
/usr/bin/grep -Fxq 'matched test count: 2' "$fixture_state/output" ||
  fail 'ordinary whole-suite selection did not retain its exact non-empty count'
assert_root_lock

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
/usr/bin/grep -Fq -- '--list-tests' "$fixture_state/host-invocations" ||
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

printf '%s\n' 'Non-empty Swift test runner contracts passed.'
