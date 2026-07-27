#!/usr/bin/env bash
set -euo pipefail

readonly scratch="$(mktemp -d "${TMPDIR:-/tmp}/motes-candidate-release.XXXXXX")"
readonly output="$(mktemp "${TMPDIR:-/tmp}/motes-candidate-release-output.XXXXXX")"
cleanup() {
  /bin/rm -rf -- "$scratch"
  /bin/rm -f -- "$output"
}
trap cleanup EXIT

set +e
MOTES_ENHANCED_CANDIDATE=1 swift build -c release \
  --scratch-path "$scratch" >"$output" 2>&1
readonly build_exit=$?
set -e

if (( build_exit == 0 )); then
  printf 'error: candidate release unexpectedly compiled\n' >&2
  exit 1
fi
if ! grep -Fq \
  'Enhanced Local is a debug-only candidate and cannot be built for release.' \
  "$output"; then
  printf 'error: candidate release did not fail at the production #error gate\n' >&2
  cat "$output" >&2
  exit 1
fi
if find "$scratch" -type f -name Motes -print -quit | grep -q .; then
  printf 'error: candidate release produced a linked Motes executable\n' >&2
  exit 1
fi

printf 'Candidate release was rejected before linking.\n'
