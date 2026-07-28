#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly temp_root="$(mktemp -d "${TMPDIR:-/tmp}/motes-candidate-release.XXXXXX")"
readonly scratch="$temp_root/build"
readonly output="$temp_root/output"
cleanup() {
  /bin/rm -rf -- "$temp_root"
}
trap cleanup EXIT

set +e
"$script_dir/resolve-enhanced-candidate.sh" "$scratch" \
  swift build -c release --disable-automatic-resolution \
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
