#!/usr/bin/env bash
set -euo pipefail

readonly target="${1:-.build/release/Motes}"
readonly limit_mb="${APP_SIZE_LIMIT_MB:-15}"
readonly limit_bytes=$((limit_mb * 1024 * 1024))

if [[ ! -f "$target" ]]; then
  printf 'error: release executable not found: %s\n' "$target" >&2
  exit 2
fi

size_bytes="$(wc -c < "$target" | tr -d '[:space:]')"
printf 'Release executable: %s bytes (budget: %s MB)\n' "$size_bytes" "$limit_mb"

if (( size_bytes > limit_bytes )); then
  printf 'error: release executable exceeds the %s MB budget\n' "$limit_mb" >&2
  exit 1
fi
