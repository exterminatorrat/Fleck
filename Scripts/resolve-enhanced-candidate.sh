#!/usr/bin/env bash
set -euo pipefail

readonly scratch="${1:-.build-candidate}"
readonly resolved="Package.resolved"

if [[ -e "$resolved" ]]; then
  printf 'error: remove Package.resolved before fresh candidate resolution\n' >&2
  exit 1
fi
if [[ -e "$scratch" ]]; then
  printf 'error: candidate scratch path must not already exist: %s\n' "$scratch" >&2
  exit 1
fi
trap 'rm -f "$resolved"' EXIT
MOTES_ENHANCED_CANDIDATE=1 \
  swift package --scratch-path "$scratch" resolve
Scripts/verify-enhanced-candidate-pin.swift "$resolved"
