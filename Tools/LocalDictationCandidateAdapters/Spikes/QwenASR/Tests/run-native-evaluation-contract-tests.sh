#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(cd "$script_dir/../../../../.." && pwd -P)"
readonly test_source="$script_dir/NativeEvaluationContractTests.swift"
readonly build_script="$script_dir/../NativeEvaluation/build.sh"
readonly build_root_raw="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-native-evaluation.XXXXXX")"
readonly build_root="$(realpath "$build_root_raw")"
readonly test_binary="$build_root/native-evaluation-contract-tests"
readonly native_output="$build_root/native"
readonly prepared_root="${FLECK_QWEN_PREPARED_ROOT:-}"
trap 'rm -rf "$build_root"' EXIT

[[ -n "$prepared_root" ]] || {
  echo "native-evaluation-contract-tests:required-environment-missing:FLECK_QWEN_PREPARED_ROOT" >&2
  exit 2
}
swiftc -O -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" --repo-root "$repo_root" --static-only

[[ "$(uname -m)" == "arm64" ]] || {
  echo "native-evaluation-contract-tests:arm64-required" >&2
  exit 2
}
[[ -d "$prepared_root" ]] || {
  echo "native-evaluation-contract-tests:prepared-root-unavailable" >&2
  exit 2
}

sh "$build_script" --prepared-root "$prepared_root" --output-root "$native_output"
[[ -x "$native_output/qwen-sherpa-native-evaluation" ]] || {
  echo "native-evaluation-contract-tests:helper-not-built" >&2
  exit 2
}

"$test_binary" \
  --repo-root "$repo_root" \
  --prepared-root "$prepared_root" \
  --helper "$native_output/qwen-sherpa-native-evaluation"

git -C "$repo_root" diff --check
