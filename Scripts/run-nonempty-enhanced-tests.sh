#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly resolver="$script_dir/resolve-enhanced-candidate.sh"

if (( $# != 1 )); then
  printf 'usage: %s <anchored-test-identifier-regex>\n' "${0##*/}" >&2
  exit 2
fi
readonly identifier_regex="$1"
if (( ${#identifier_regex} <= 2 )) ||
  [[ "$identifier_regex" != ^* || "$identifier_regex" != *'$' ]]; then
  printf 'error: test identifier regex must be non-empty and anchored with ^ and $\n' >&2
  exit 2
fi
set +e
printf '' | /usr/bin/grep -E -- "$identifier_regex" >/dev/null 2>&1
regex_status=$?
set -e
if (( regex_status == 2 )); then
  printf 'error: invalid extended regular expression: %s\n' "$identifier_regex" >&2
  exit 2
fi
[[ -x "$resolver" ]] || {
  printf 'error: enhanced candidate resolver is not executable: %s\n' "$resolver" >&2
  exit 2
}

temp_parent="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nonempty-enhanced-tests.XXXXXX")"
readonly temp_parent
readonly scratch="$temp_parent/build"
readonly root_lock="$repo_root/Package.resolved"
readonly root_backup="$temp_parent/ordinary.Package.resolved"
readonly coordination_lock="$repo_root/.build/.fleck-nonempty-swift-tests.lockf"
readonly shadow_root="$temp_parent/repository"
readonly shadow_scripts="$shadow_root/Scripts"
lock_acquired=0
snapshot_ready=0
if [[ -e "$scratch" || -L "$scratch" ]]; then
  printf 'error: candidate scratch path must not already exist: %s\n' "$scratch" >&2
  /bin/rm -rf -- "$temp_parent"
  exit 2
fi

root_matches_snapshot() {
  [[ -f "$root_lock" && ! -L "$root_lock" ]] &&
    /usr/bin/cmp -s "$root_backup" "$root_lock"
}

restore_root_lock() {
  local replacement
  root_matches_snapshot && return 0
  replacement="$(mktemp "${root_lock}.restore.XXXXXX")" || {
    printf '%s\n' 'error: failed to restore root Package.resolved' >&2
    return 1
  }
  if ! /bin/cp -p "$root_backup" "$replacement" ||
    ! /bin/mv -f "$replacement" "$root_lock"; then
    /bin/rm -f -- "$replacement"
    printf '%s\n' 'error: failed to restore root Package.resolved' >&2
    return 1
  fi
  if ! root_matches_snapshot; then
    printf '%s\n' 'error: failed to verify restored root Package.resolved' >&2
    return 1
  fi
}

cleanup() {
  local status=$?
  local cleanup_failed=0
  trap - EXIT HUP INT TERM
  set +e
  if (( lock_acquired )); then
    if (( snapshot_ready )); then
      restore_root_lock || cleanup_failed=1
    fi
    exec 9>&- || {
      printf '%s\n' 'error: failed to release Swift test coordination lock' >&2
      cleanup_failed=1
    }
  fi
  /bin/rm -rf -- "$temp_parent" || cleanup_failed=1
  if (( cleanup_failed )); then
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/bin/mkdir -p "$repo_root/.build"
if ! exec 9>>"$coordination_lock"; then
  printf '%s\n' 'error: failed to open Swift test coordination lock' >&2
  exit 4
fi
set +e
/usr/bin/lockf -s -t 60 9
lock_status=$?
set -e
if (( lock_status != 0 )); then
  printf '%s\n' 'error: timed out waiting for Swift test coordination lock' >&2
  exit 4
fi
lock_acquired=1

if [[ ! -f "$root_lock" || -L "$root_lock" ]]; then
  printf 'error: ordinary Package.resolved is missing or unsafe: %s\n' \
    "$root_lock" >&2
  exit 2
fi
/bin/cp -p "$root_lock" "$root_backup"
snapshot_ready=1

/bin/mkdir -p "$shadow_scripts"
for entry in "$repo_root"/*; do
  entry_name="${entry##*/}"
  case "$entry_name" in
    Package.resolved|Scripts) continue ;;
  esac
  /bin/ln -s "$entry" "$shadow_root/$entry_name"
done
for entry in "$script_dir"/*; do
  /bin/ln -s "$entry" "$shadow_scripts/${entry##*/}"
done
/bin/cp -p "$root_backup" "$shadow_root/Package.resolved"
readonly shadow_resolver="$shadow_scripts/resolve-enhanced-candidate.sh"

readonly callback='set -uo pipefail
repo_root="$1"
scratch="$2"
identifier_regex="$3"
list_output="$4"
canonical_output="$5"
matches="$6"
test_output="$7"
cd "$repo_root"
swift test list --disable-automatic-resolution --scratch-path "$scratch" > "$list_output"
status=$?
(( status == 0 )) || exit "$status"
LC_ALL=C /usr/bin/grep -E \
  '\''^[[:alnum:]_][[:alnum:]_-]*\.[[:alnum:]_][[:alnum:]_.-]*(/[[:alnum:]_][[:alnum:]_.-]*)*\((([[:alpha:]_][[:alnum:]_]*):)*\)$'\'' \
  "$list_output" > "$canonical_output" || true
/usr/bin/grep -E -- "$identifier_regex" "$canonical_output" > "$matches"
status=$?
if (( status == 2 )); then
  printf '\''error: invalid extended regular expression: %s\n'\'' "$identifier_regex" >&2
  exit 2
fi
if [[ ! -s "$matches" ]]; then
  printf '\''error: test identifier regex matched zero tests: %s\n'\'' "$identifier_regex" >&2
  exit 3
fi
matched_count="$(/usr/bin/wc -l < "$matches" | /usr/bin/tr -d '\'' '\'')"
printf '\''matched test count: %s\n'\'' "$matched_count"
while IFS= read -r identifier; do
  printf '\''matched test: %s\n'\'' "$identifier"
done < "$matches"
run_filter="$(/usr/bin/awk '\''
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
'\'' "$matches")"
swift test --disable-automatic-resolution --scratch-path "$scratch" \
  --no-parallel --filter "$run_filter" 2>&1 | /usr/bin/tee "$test_output"
test_pipeline_status=("${PIPESTATUS[@]}")
test_status="${test_pipeline_status[0]}"
output_status="${test_pipeline_status[1]}"
(( test_status == 0 )) || exit "$test_status"
if (( output_status != 0 )); then
  printf '\''%s\n'\'' '\''error: failed to capture Swift test output'\'' >&2
  exit 1
fi
final_output_line="$(/usr/bin/awk '\''NF { line = $0 } END { print line }'\'' "$test_output")"
if ! printf '\''%s\n'\'' "$final_output_line" | LC_ALL=C /usr/bin/grep -Eq \
  '\''^✔ Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed after [0-9]+(\.[0-9]+)? seconds\.$'\''; then
  printf '\''%s\n'\'' \
    '\''error: Swift test exited successfully without a final non-empty passing test summary'\'' >&2
  exit 1
fi'

set +e
"$shadow_resolver" "$scratch" /bin/bash -c "$callback" runner-callback \
  "$shadow_root" "$scratch" "$identifier_regex" \
  "$temp_parent/test-list" "$temp_parent/canonical-test-list" \
  "$temp_parent/matches" "$temp_parent/test-output"
resolver_status=$?
set -e

if ! root_matches_snapshot; then
  printf 'error: root Package.resolved changed during enhanced test execution\n' >&2
  if (( resolver_status == 0 )); then
    resolver_status=1
  fi
fi
exit "$resolver_status"
