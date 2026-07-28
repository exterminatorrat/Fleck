#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: memory profiling requires macOS\n' >&2
  exit 2
fi

readonly process_name="${1:-Motes}"
readonly limit_mb="${RAM_LIMIT_MB:-75}"
readonly pid="$(pgrep -x "$process_name" | head -n 1 || true)"

if [[ -z "$pid" ]]; then
  printf 'error: %s is not running\n' "$process_name" >&2
  exit 2
fi

resident_kb="$(ps -o rss= -p "$pid" | tr -d '[:space:]')"
resident_mb="$(( (resident_kb + 1023) / 1024 ))"
printf '%s (pid %s) resident memory: %s MB (budget: %s MB)\n' \
  "$process_name" "$pid" "$resident_mb" "$limit_mb"

if (( resident_mb > limit_mb )); then
  printf 'error: resident memory exceeds the %s MB budget\n' "$limit_mb" >&2
  exit 1
fi
