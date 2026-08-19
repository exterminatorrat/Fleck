#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly repo_root="$(cd "$script_dir/../../../../.." && pwd)"
readonly protocol_sources=(
  "$repo_root/Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/CandidateAdapterModels.swift"
  "$repo_root/Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/JSONLinesCodec.swift"
)
readonly spike_sources=(
  "$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Sources/QwenASRSpikeContract/AdmissionGates.swift"
  "$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Sources/QwenASRSpikeSupport/WaveReader.swift"
  "$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Sources/QwenASRSpikeSupport/JSONLinesStdio.swift"
  "$script_dir/main.swift"
)

runtime_root=""
output_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-root)
      runtime_root="${2:-}"
      shift 2
      ;;
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

if [[ "$runtime_root" != /* || "$output_root" != /* ]]; then
  echo "--runtime-root and --output-root must be absolute paths" >&2
  exit 2
fi

readonly framework_root="$runtime_root/SherpaOnnxC.framework"
if [[ ! -d "$framework_root" || ! -f "$framework_root/Headers/sherpa-onnx/c-api/c-api.h" ]]; then
  echo "missing SherpaOnnxC.framework under runtime root" >&2
  exit 2
fi

mkdir -p "$output_root"
swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  -parse-as-library \
  -emit-library \
  -static \
  -module-name LocalDictationCandidateProtocol \
  -emit-module \
  -emit-module-path "$output_root/LocalDictationCandidateProtocol.swiftmodule" \
  -o "$output_root/libLocalDictationCandidateProtocol.a" \
  "${protocol_sources[@]}"

swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  -parse-as-library \
  -I "$output_root" \
  -L "$output_root" \
  -lLocalDictationCandidateProtocol \
  -F "$runtime_root" \
  -I "$framework_root/Headers" \
  -import-objc-header "$script_dir/SherpaOnnx-Bridging-Header.h" \
  -lc++ \
  -framework SherpaOnnxC \
  "${spike_sources[@]}" \
  -o "$output_root/qwen-sherpa-spike"
