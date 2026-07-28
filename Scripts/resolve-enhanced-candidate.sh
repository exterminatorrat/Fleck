#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly scratch_arg="${1:-.build-candidate}"
if [[ "$scratch_arg" = /* ]]; then
  readonly scratch="$scratch_arg"
else
  readonly scratch="$repo_root/$scratch_arg"
fi
if (( $# > 0 )); then
  shift
fi
readonly resolved="$repo_root/Package.resolved"

if [[ ! -f "$resolved" ]]; then
  printf 'error: ordinary Package.resolved is missing: %s\n' "$resolved" >&2
  exit 1
fi
if [[ -e "$scratch" ]]; then
  printf 'error: candidate scratch path must not already exist: %s\n' "$scratch" >&2
  exit 1
fi
readonly ordinary_backup="$(
  mktemp "${TMPDIR:-/tmp}/motes-ordinary-package-resolved.XXXXXX"
)"
/bin/cp -p "$resolved" "$ordinary_backup"
cleanup() {
  /bin/rm -f -- "$resolved"
  /bin/cp -p "$ordinary_backup" "$resolved"
  /bin/rm -f -- "$ordinary_backup"
}
trap cleanup EXIT

/bin/rm -f -- "$resolved"
cd "$repo_root"
MOTES_ENHANCED_CANDIDATE=1 \
  swift package --scratch-path "$scratch" resolve
"$script_dir/verify-enhanced-candidate-pin.swift" "$resolved"

if (( $# > 0 )); then
  MOTES_ENHANCED_CANDIDATE=1 "$@"
fi
