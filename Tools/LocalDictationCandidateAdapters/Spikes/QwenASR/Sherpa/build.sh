#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly repo_root="$(cd "$script_dir/../../../../.." && pwd)"
readonly admission_source="$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Sources/QwenASRSpikeContract/AdmissionGates.swift"
readonly preflight_source="$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Sources/QwenASRSpikeContract/Preflight.swift"
readonly main_source="$script_dir/../Preflight/main.swift"

output_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-root)
      output_root="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$output_root" != /* ]]; then
  echo "--output-root must be an absolute path" >&2
  exit 2
fi

mkdir -p "$output_root"

# This binary is a Foundation-only admission boundary. It does not import,
# compile, link, resolve, or invoke the Sherpa native runtime.
swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  -parse-as-library \
  -module-name QwenASRPreflight \
  "$admission_source" \
  "$preflight_source" \
  "$main_source" \
  -o "$output_root/qwen-sherpa-preflight"
