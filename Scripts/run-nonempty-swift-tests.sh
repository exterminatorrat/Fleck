#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly appkit_runner="$script_dir/run-swift-tests-with-appkit-host.sh"

usage() {
  printf 'usage: %s [--package-path <repository-relative-package>] <anchored-test-identifier-regex>\n' \
    "${0##*/}" >&2
  exit 2
}

package_root="$repo_root"
if [[ "${1:-}" = --package-path ]]; then
  (( $# >= 3 )) || usage
  package_path="$2"
  shift 2
  case "$package_path" in
    ''|/*|.|..|./*|*/./*|*/.|../*|*/../*|*/..)
      printf 'error: package path must be a normalized repository-relative path\n' >&2
      exit 2
      ;;
  esac
  [[ -d "$repo_root/$package_path" ]] || {
    printf 'error: package path is not a directory: %s\n' "$package_path" >&2
    exit 2
  }
  package_root="$(cd -- "$repo_root/$package_path" && pwd -P)"
  case "$package_root/" in
    "$repo_root"/*) ;;
    *)
      printf 'error: package path escapes the repository: %s\n' "$package_path" >&2
      exit 2
      ;;
  esac
  [[ -f "$package_root/Package.swift" ]] || {
    printf 'error: package path has no Package.swift: %s\n' "$package_path" >&2
    exit 2
  }
fi

(( $# == 1 )) || usage
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

state_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nonempty-swift-tests.XXXXXX")"
readonly state_dir
readonly root_lock="$repo_root/Package.resolved"
readonly package_lock="$package_root/Package.resolved"
readonly root_backup="$state_dir/root.Package.resolved"
readonly package_backup="$state_dir/package.Package.resolved"
readonly coordination_lock="$repo_root/.build/.fleck-nonempty-swift-tests.lockf"
root_lock_existed=0
package_lock_existed=0
separate_package_lock=0
lock_acquired=0
snapshots_ready=0

lock_matches_snapshot() {
  local path="$1"
  local backup="$2"
  local existed="$3"
  if (( existed )); then
    [[ -f "$path" && ! -L "$path" ]] && /usr/bin/cmp -s "$backup" "$path"
  else
    [[ ! -e "$path" && ! -L "$path" ]]
  fi
}

restore_lock() {
  local label="$1"
  local path="$2"
  local backup="$3"
  local existed="$4"
  local replacement
  local quarantine

  lock_matches_snapshot "$path" "$backup" "$existed" && return 0
  if (( existed )); then
    replacement="$(mktemp "${path}.restore.XXXXXX")" || {
      printf 'error: failed to restore %s Package.resolved\n' "$label" >&2
      return 1
    }
    if ! /bin/cp -p "$backup" "$replacement" ||
      ! /bin/mv -f "$replacement" "$path"; then
      /bin/rm -f -- "$replacement"
      printf 'error: failed to restore %s Package.resolved\n' "$label" >&2
      return 1
    fi
  else
    if [[ -d "$path" && ! -L "$path" ]]; then
      printf 'error: failed to restore absent %s Package.resolved\n' "$label" >&2
      return 1
    fi
    quarantine="$(mktemp "${path}.remove.XXXXXX")" || {
      printf 'error: failed to restore absent %s Package.resolved\n' "$label" >&2
      return 1
    }
    /bin/rm -f -- "$quarantine"
    if ! /bin/mv "$path" "$quarantine" || ! /bin/rm -f -- "$quarantine"; then
      printf 'error: failed to restore absent %s Package.resolved\n' "$label" >&2
      return 1
    fi
  fi
  if ! lock_matches_snapshot "$path" "$backup" "$existed"; then
    printf 'error: failed to verify restored %s Package.resolved\n' "$label" >&2
    return 1
  fi
}

cleanup() {
  local status=$?
  local cleanup_failed=0
  trap - EXIT HUP INT TERM
  set +e
  if (( lock_acquired )); then
    if (( snapshots_ready )); then
      restore_lock root "$root_lock" "$root_backup" "$root_lock_existed" ||
        cleanup_failed=1
      if (( separate_package_lock )); then
        restore_lock selected-package "$package_lock" "$package_backup" \
          "$package_lock_existed" || cleanup_failed=1
      fi
    fi
    exec 9>&- || {
      printf '%s\n' 'error: failed to release Swift test coordination lock' >&2
      cleanup_failed=1
    }
  fi
  /bin/rm -rf -- "$state_dir" || cleanup_failed=1
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

if [[ -f "$root_lock" && ! -L "$root_lock" ]]; then
  root_lock_existed=1
  /bin/cp -p "$root_lock" "$root_backup"
elif [[ -e "$root_lock" || -L "$root_lock" ]]; then
  printf 'error: root Package.resolved is not a regular file\n' >&2
  exit 2
fi

if [[ "$package_lock" != "$root_lock" ]]; then
  separate_package_lock=1
  if [[ -f "$package_lock" && ! -L "$package_lock" ]]; then
    package_lock_existed=1
    /bin/cp -p "$package_lock" "$package_backup"
  elif [[ -e "$package_lock" || -L "$package_lock" ]]; then
    printf 'error: selected package Package.resolved is not a regular file\n' >&2
    exit 2
  fi
fi
snapshots_ready=1

finish() {
  local status="$1"
  local changed=0
  if ! lock_matches_snapshot "$root_lock" "$root_backup" "$root_lock_existed"; then
    printf 'error: root Package.resolved changed during test execution\n' >&2
    changed=1
  fi
  if (( separate_package_lock )) &&
    ! lock_matches_snapshot "$package_lock" "$package_backup" "$package_lock_existed"; then
    printf 'error: selected package Package.resolved changed during test execution\n' >&2
    changed=1
  fi
  if (( changed && status == 0 )); then
    status=1
  fi
  exit "$status"
}

readonly list_output="$state_dir/test-list"
readonly canonical_output="$state_dir/canonical-test-list"
readonly matches="$state_dir/matches"
readonly test_output="$state_dir/test-output"

if [[ "$package_root" = "$repo_root" ]]; then
  [[ -x "$appkit_runner" ]] || {
    printf 'error: AppKit Swift test runner is not executable: %s\n' \
      "$appkit_runner" >&2
    finish 2
  }
  set +e
  "$appkit_runner" "$package_root" '' "$identifier_regex"
  appkit_status=$?
  set -e
  finish "$appkit_status"
fi

set +e
(
  cd "$package_root"
  swift test list --disable-automatic-resolution
) > "$list_output"
list_status=$?
set -e
(( list_status == 0 )) || finish "$list_status"

LC_ALL=C /usr/bin/grep -E \
  '^[[:alnum:]_][[:alnum:]_-]*\.[[:alnum:]_][[:alnum:]_.-]*(/[[:alnum:]_][[:alnum:]_.-]*)*\((([[:alpha:]_][[:alnum:]_]*):)*\)$' \
  "$list_output" > "$canonical_output" || true
set +e
/usr/bin/grep -E -- "$identifier_regex" "$canonical_output" > "$matches"
match_status=$?
set -e
if (( match_status == 2 )); then
  printf 'error: invalid extended regular expression: %s\n' "$identifier_regex" >&2
  finish 2
fi
if [[ ! -s "$matches" ]]; then
  printf 'error: test identifier regex matched zero tests: %s\n' \
    "$identifier_regex" >&2
  finish 3
fi

matched_count="$(/usr/bin/wc -l < "$matches" | /usr/bin/tr -d ' ')"
printf 'matched test count: %s\n' "$matched_count"
while IFS= read -r identifier; do
  printf 'matched test: %s\n' "$identifier"
done < "$matches"

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
set +e
(
  cd "$package_root"
  swift test --disable-automatic-resolution --no-parallel --filter "$run_filter"
) 2>&1 | /usr/bin/tee "$test_output"
test_pipeline_status=("${PIPESTATUS[@]}")
set -e
test_status="${test_pipeline_status[0]}"
output_status="${test_pipeline_status[1]}"
(( test_status == 0 )) || finish "$test_status"
if (( output_status != 0 )); then
  printf '%s\n' 'error: failed to capture Swift test output' >&2
  finish 1
fi

final_output_line="$(/usr/bin/awk 'NF { line = $0 } END { print line }' "$test_output")"
if ! printf '%s\n' "$final_output_line" | LC_ALL=C /usr/bin/grep -Eq \
  '^✔ Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed after [0-9]+(\.[0-9]+)? seconds\.$'; then
  printf '%s\n' \
    'error: Swift test exited successfully without a final non-empty passing test summary' >&2
  finish 1
fi

finish 0
