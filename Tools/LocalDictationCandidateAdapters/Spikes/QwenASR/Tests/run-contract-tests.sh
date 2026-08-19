#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly test_source="$script_dir/AdmissionGateTests.swift"
readonly implementation="$script_dir/../Sources/QwenASRSpikeContract/AdmissionGates.swift"
readonly wave_reader="$script_dir/../Sources/QwenASRSpikeSupport/WaveReader.swift"
readonly build_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-admission-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

sources=("$test_source")
if [[ -f "$implementation" ]]; then
  sources+=("$implementation")
fi
if [[ -f "$wave_reader" ]]; then
  sources+=("$wave_reader")
fi

swiftc -O -parse-as-library "${sources[@]}" -o "$build_dir/admission-gate-tests"
"$build_dir/admission-gate-tests"
