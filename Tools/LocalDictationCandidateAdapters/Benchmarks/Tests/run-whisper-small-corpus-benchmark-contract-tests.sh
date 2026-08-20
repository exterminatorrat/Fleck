#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
candidate_dir="$(CDPATH= cd -- "$script_dir/../Candidates" && pwd -P)"
benchmark="$candidate_dir/WhisperSmallCorpusBenchmark.swift"
control="$candidate_dir/whisper-small-control.json"
runner="$candidate_dir/run-whisper-small-corpus-benchmark.sh"
readme="$candidate_dir/README-Whisper-Small.md"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-whisper-small-contract.XXXXXX")"
module_cache="$build_dir/module-cache"
binary="$build_dir/whisper-small-corpus-benchmark"

cleanup() {
  rm -rf -- "$build_dir"
}
trap cleanup EXIT

test -f "$benchmark"
test -f "$control"
test -x "$runner"
test -f "$readme"

command -v jq >/dev/null
command -v swiftc >/dev/null
bash -n "$runner"
jq empty "$control"
jq -e '
  .schemaVersion == 1
  and .candidate.model.id == "ggerganov/whisper.cpp:ggml-small.bin"
  and .candidate.model.revision == "80da2d8bfee42b0e836fc3a9890373e5defc00a6"
  and .candidate.model.path == "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Quarantine/whisper-small-control/ggml-small.bin"
  and .candidate.model.byteCount == 487601967
  and .candidate.model.sha256 == "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
  and .candidate.model.fileType == 1
  and .candidate.model.quantization == "mostly-F16/float16 (ggml ftype=1)"
  and .candidate.model.license == "MIT"
  and .candidate.runtime.id == "whisper.cpp"
  and .candidate.runtime.version == "v1.9.2"
  and .candidate.runtime.sourceCommit == "306c88f4d1286aec1bf96e544632897886af5501"
  and .candidate.runtime.sourcePath == "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Sources/whisper.cpp-306c88f4d1286aec1bf96e544632897886af5501"
  and .candidate.runtime.cliPath == "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Builds/whisper-small-control/metal-static/bin/whisper-cli"
  and .candidate.runtime.cliByteCount == 3271592
  and .candidate.runtime.cliSHA256 == "cbde25b4d8db46feeab59355809725ff11ec4039b3251a1997ddd3a187901e03"
  and .candidate.runtime.buildCachePath == "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Builds/whisper-small-control/metal-static/CMakeCache.txt"
  and .candidate.runtime.architecture == "arm64"
  and .candidate.runtime.license == "MIT"
  and .candidate.runtime.buildFlags.BUILD_SHARED_LIBS == "OFF"
  and .candidate.runtime.buildFlags.CMAKE_BUILD_TYPE == "Release"
  and .candidate.runtime.buildFlags.CMAKE_OSX_ARCHITECTURES == ""
  and .candidate.runtime.buildFlags.CMAKE_OSX_DEPLOYMENT_TARGET == "14.0"
  and .candidate.runtime.buildFlags.GGML_BLAS == "OFF"
  and .candidate.runtime.buildFlags.GGML_METAL == "ON"
  and .candidate.runtime.buildFlags.GGML_METAL_EMBED_LIBRARY == "ON"
  and .candidate.runtime.buildFlags.GGML_OPENMP == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_COREML == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_CURL == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_BUILD_SERVER == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_OPENVINO == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_SDL2 == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_BUILD_TESTS == "OFF"
  and .candidate.runtime.buildFlags.WHISPER_BUILD_EXAMPLES == "ON"
  and (.candidate.runtime.buildFlags | length) == 15
  and .corpus.manifestPath == "Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/manifest-v1.json"
  and .corpus.validationRoot == "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Prepared/corpus/fleurs-a3c817c-validation-subset-v1"
  and .corpus.compositeRoot == "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Prepared/corpus/fleurs-a3c817c-public-human-composite-mixed-v1"
  and .corpus.manifestID == "fleurs-a3c817c-local-dictation-corpus-v1"
  and .corpus.sourceRevision == "a3c817cbf7c08863e0c472861c7c39e27ce7f38e"
  and .corpus.license == "CC-BY-4.0"
  and .corpus.expectedCounts == {"english":12,"mandarin":12,"mixed":12}
  and .execution.expectedWarmCaseCount == 36
  and (.execution.coldCaseIDs | length) == 5
  and ([.execution.coldCaseIDs[] | select(startswith("en_us-"))] | length) == 2
  and ([.execution.coldCaseIDs[] | select(startswith("cmn_hans_cn-"))] | length) == 2
  and ([.execution.coldCaseIDs[] | select(startswith("mixed-"))] | length) == 1
  and .execution.cancellationCaseID == "mixed-01"
' "$control" >/dev/null

if rg -n -i '\bq8\b|\bint8\b|URLSession|curl[[:space:]]|wget[[:space:]]|git clone|swift package resolve|FleckApp|releaseAdmitted[^[:alnum:]]*true|automatedCandidatePass[^[:alnum:]]*true' \
  "$benchmark" "$runner" "$control"; then
  echo "forbidden benchmark content found" >&2
  exit 1
fi

mkdir -p -- "$module_cache"
CLANG_MODULE_CACHE_PATH="$module_cache" swiftc -O -parse-as-library "$benchmark" -o "$binary"
self_test_output="$($binary --self-test)"
grep -F "SELF-TEST PASS: 9 fake-only Whisper benchmark contract checks" <<<"$self_test_output"

echo "Whisper small corpus contract tests: PASS (fake-only; external CLI not launched)"
