#!/usr/bin/env bash
set -euo pipefail

readonly target="${1:-.build/release/Motes}"
readonly limit_mb="${APP_SIZE_LIMIT_MB:-15}"
readonly limit_bytes=$((limit_mb * 1024 * 1024))
readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly sources_root="$repository_root/Sources"
readonly enhanced_capture="$sources_root/MenuBarNotesApp/EnhancedSpeechCapture.swift"

if [[ -f "$target" ]]; then
  readonly executable="$target"
  readonly artifact_root="$(dirname "$target")"
elif [[ -d "$target" && -f "$target/Contents/MacOS/Motes" ]]; then
  readonly executable="$target/Contents/MacOS/Motes"
  readonly artifact_root="$target"
elif [[ -d "$target" && -f "$target/Motes" ]]; then
  readonly executable="$target/Motes"
  readonly artifact_root="$target"
else
  printf 'error: release executable or artifact not found: %s\n' "$target" >&2
  exit 2
fi

size_bytes="$(wc -c < "$executable" | tr -d '[:space:]')"
printf 'Release executable: %s bytes (budget: %s MB)\n' "$size_bytes" "$limit_mb"

if (( size_bytes > limit_bytes )); then
  printf 'error: release executable exceeds the %s MB budget\n' "$limit_mb" >&2
  exit 1
fi

forbidden_model_assets=()
while IFS= read -r -d '' path; do
  forbidden_model_assets+=("$path")
done < <(
  find "$artifact_root" \
    \( -name '*.mlmodel' -o -name '*.mlpackage' -o -name '*.mlmodelc' \) \
    -print0
)

while IFS= read -r -d '' path; do
  filename="$(basename "$path")"
  case "$filename" in
    coremldata.bin|weight.bin|weights.bin)
      forbidden_model_assets+=("$path")
      continue
      ;;
  esac

  case "$path" in
    *.mlmodelc/*|*.mlpackage/*|*/Model/*|*/Models/*|*/model/*|*/models/*)
      forbidden_model_assets+=("$path")
      ;;
  esac
done < <(find "$artifact_root" -type f -name '*.bin' -print0)

if (( ${#forbidden_model_assets[@]} > 0 )); then
  printf 'error: release artifact contains model assets:\n' >&2
  for path in "${forbidden_model_assets[@]}"; do
    printf '  %s\n' "$path" >&2
  done
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for release source assertions\n' >&2
  exit 2
fi

if ! rg -q 'ModelHub\.offlineMode\s*=\s*true' "$enhanced_capture"; then
  printf 'error: EnhancedSpeechCapture must force ModelHub.offlineMode = true\n' >&2
  exit 1
fi

assert_absent() {
  local pattern="$1"
  local description="$2"
  shift 2

  if rg -n "$pattern" "$@"; then
    printf 'error: forbidden production source found: %s\n' "$description" >&2
    exit 1
  fi
}

assert_absent \
  'ModelHub\.offlineMode\s*=\s*false' \
  'ModelHub.offlineMode = false' \
  "$sources_root"
assert_absent \
  'AsrModels\s*\.\s*downloadAndLoad' \
  'AsrModels.downloadAndLoad' \
  "$sources_root"
assert_absent \
  'ModelHub\s*\.\s*(download|fetchFile)' \
  'ModelHub.download or ModelHub.fetchFile in EnhancedSpeechCapture' \
  "$enhanced_capture"
assert_absent \
  'NSEvent\s*\.\s*addGlobalMonitorForEvents' \
  'NSEvent.addGlobalMonitorForEvents' \
  "$sources_root"

printf 'Release artifact contains no bundled model assets.\n'
printf 'Release source assertions passed.\n'
