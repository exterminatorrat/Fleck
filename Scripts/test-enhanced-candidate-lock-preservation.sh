#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly temp_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-candidate-lock-test.XXXXXX")"
readonly foreign_root="$temp_root/foreign"
readonly scratch="$temp_root/candidate-build"
readonly ordinary_copy="$temp_root/Package.resolved"
readonly candidate_seen="$temp_root/candidate-seen"
readonly fake_bin="$temp_root/bin"
cleanup() {
  /bin/rm -rf -- "$temp_root"
}
trap cleanup EXIT

/bin/mkdir -p "$foreign_root" "$fake_bin"
/bin/cp -p "$repo_root/Package.resolved" "$ordinary_copy"
printf 'caller canary\n' > "$foreign_root/Package.resolved"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'case "${1:-}" in' \
  '  package)' \
  '    test "$#" -eq 5' \
  '    test "$2" = "--skip-update"' \
  '    test "$3" = "--scratch-path"' \
  '    test "$4" = "$FAKE_CANDIDATE_SCRATCH"' \
  '    test "$5" = "resolve"' \
  '    test "${FLECK_ENHANCED_CANDIDATE:-}" = "1"' \
  '    /bin/mkdir "$FAKE_CANDIDATE_SCRATCH"' \
  '    /bin/cp "$FAKE_CANDIDATE_FIXTURE" "$FAKE_REPO_ROOT/Package.resolved"' \
  '    ;;' \
  '  */verify-enhanced-candidate-pin.swift)' \
  '    /usr/bin/grep -Fq "19600a485baa4998812e4654b70d2bab8f2c9949" "$2"' \
  '    ;;' \
  '  *)' \
  '    printf "error: unexpected fake swift invocation: %s\n" "$*" >&2' \
  '    exit 1' \
  '    ;;' \
  'esac' > "$fake_bin/swift"
/bin/chmod +x "$fake_bin/swift"

set +e
(
  cd "$foreign_root"
  PATH="$fake_bin:$PATH" \
  FAKE_REPO_ROOT="$repo_root" \
  FAKE_CANDIDATE_FIXTURE="$repo_root/Tests/Fixtures/enhanced-candidate-pin-valid.json" \
  FAKE_CANDIDATE_SCRATCH="$scratch" \
  "$script_dir/resolve-enhanced-candidate.sh" "$scratch" \
    /bin/sh -c '
      test "${FLECK_ENHANCED_CANDIDATE:-}" = "1"
      grep -Fq "\"identity\": \"fluidaudio\"" "$1/Package.resolved"
      printf "candidate lock active\n" > "$2"
      exit 23
    ' candidate-lock-check "$repo_root" "$candidate_seen"
)
readonly resolver_exit=$?
set -e

if (( resolver_exit != 23 )); then
  printf 'error: candidate callback exit was not preserved (%s)\n' \
    "$resolver_exit" >&2
  exit 1
fi
grep -Fxq 'caller canary' "$foreign_root/Package.resolved"
grep -Fxq 'candidate lock active' "$candidate_seen"
/usr/bin/cmp -s "$ordinary_copy" "$repo_root/Package.resolved"

printf 'Candidate lock stayed repository-rooted and restored the ordinary lock.\n'
