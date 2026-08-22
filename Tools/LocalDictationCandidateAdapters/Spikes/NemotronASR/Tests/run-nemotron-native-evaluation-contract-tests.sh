#!/usr/bin/env bash

set -euo pipefail

# Contract coverage: concurrent-substitution blocked-decode-in-flight.

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(cd "$script_dir/../../../../.." && pwd -P)"
readonly test_source="$script_dir/NemotronNativeEvaluationContractTests.swift"
readonly bridge_header="$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/NemotronASR/NativeEvaluation/NemoSpeechASR-Bridging-Header.h"
readonly source_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Sources/NeMo-Speech.cpp-5be7bfb104802131e61fe679b3f1401b27270216"
readonly model_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Quarantine/nemotron-3.5-asr-streaming-0.6b-q8/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf"
readonly runtime_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Builds/nemotron-3.5-asr-streaming-0.6b-q8/metal-asr/bin"
readonly english_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/Inputs/fleurs-a3c817c-36-flat/en_us-01.wav"
readonly mandarin_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/Inputs/fleurs-a3c817c-36-flat/cmn_hans_cn-01.wav"
readonly mixed_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/Inputs/fleurs-a3c817c-36-flat/mixed-05.wav"
readonly silence_path="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Prepared/corpus/deterministic-nonspeech-v1/silence-5s.wav"
readonly test_root_raw="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nemotron-native-contract.XXXXXX")"
readonly test_root="$(realpath "$test_root_raw")"
readonly test_binary="$test_root/nemotron-native-evaluation-contract-tests"
trap 'rm -rf "$test_root"' EXIT

[[ "$(uname -m)" == "arm64" ]] || {
  echo "nemotron-native-evaluation-contract-tests:arm64-required" >&2
  exit 2
}
for required_path in "$source_path" "$model_path" "$runtime_path" "$english_path" "$mandarin_path" "$mixed_path" "$silence_path"; do
  [[ -e "$required_path" ]] || {
    echo "nemotron-native-evaluation-contract-tests:external-input-missing:$required_path" >&2
    exit 2
  }
done

swiftc -O -parse-as-library \
  -import-objc-header "$bridge_header" \
  -Xcc -I -Xcc "$source_path/include" \
  "$test_source" \
  -o "$test_binary"
"$test_binary" --repo-root "$repo_root" --static-only

bash "$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/NemotronASR/NativeEvaluation/build.sh" \
  --source-path "$source_path" \
  --output-root "$test_root"
[[ -x "$test_root/nemotron-native-evaluation" ]] || {
  echo "nemotron-native-evaluation-contract-tests:helper-not-built" >&2
  exit 2
}

"$test_binary" \
  --repo-root "$repo_root" \
  --source-path "$source_path" \
  --model-path "$model_path" \
  --runtime-path "$runtime_path" \
  --english-path "$english_path" \
  --mandarin-path "$mandarin_path" \
  --mixed-path "$mixed_path" \
  --silence-path "$silence_path" \
  --helper "$test_root/nemotron-native-evaluation"

git -C "$repo_root" diff --check
