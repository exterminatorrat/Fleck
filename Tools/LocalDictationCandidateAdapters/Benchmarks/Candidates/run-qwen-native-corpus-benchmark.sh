#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly source="$script_dir/QwenNativeCorpusBenchmark.swift"
readonly metadata="$script_dir/qwen3-asr-0.6b-int8.json"
readonly default_repo_root="$(cd "$script_dir/../../../.." && pwd -P)"
readonly model_evaluation_source="$default_repo_root/Sources/FleckModelEvaluation/ModelEvaluation.swift"
readonly evidence_source="$default_repo_root/Sources/FleckModelEvaluation/CandidateBenchmarkEvidence.swift"
readonly local_writing_evidence_source="$default_repo_root/Sources/FleckModelEvaluation/LocalWritingEvidence.swift"
readonly artifact_inventory_source="$default_repo_root/Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateRunner/ArtifactInventory.swift"
readonly fleck_core_sources=("$default_repo_root"/Sources/FleckCore/*.swift)

prepared_root=""
helper=""
public_manifest=""
public_root=""
composite_manifest=""
composite_root=""
output_root=""
repo_root="$default_repo_root"
self_test=0

usage() {
  cat >&2 <<'EOF'
usage: run-qwen-native-corpus-benchmark.sh \
  --prepared-root ABSOLUTE_DIR \
  --helper ABSOLUTE_EXECUTABLE \
  --public-human-manifest ABSOLUTE_JSON \
  --public-human-root ABSOLUTE_DIR \
  --composite-manifest ABSOLUTE_JSON \
  --composite-root ABSOLUTE_DIR \
  --output-root NEW_EXTERNAL_DIR \
  [--repo-root ABSOLUTE_DIR]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepared-root) prepared_root="${2:-}"; shift 2 ;;
    --helper) helper="${2:-}"; shift 2 ;;
    --public-human-manifest) public_manifest="${2:-}"; shift 2 ;;
    --public-human-root) public_root="${2:-}"; shift 2 ;;
    --composite-manifest) composite_manifest="${2:-}"; shift 2 ;;
    --composite-root) composite_root="${2:-}"; shift 2 ;;
    --output-root) output_root="${2:-}"; shift 2 ;;
    --repo-root) repo_root="${2:-}"; shift 2 ;;
    --self-test) self_test=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! -x /usr/bin/sandbox-exec ]]; then
  echo "qwen-native-corpus-benchmark:fail:sandbox-exec-unavailable" >&2
  exit 2
fi

readonly build_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-native-benchmark.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

mkdir -p "$build_dir/module-cache"
swiftc -parse-as-library -emit-library -emit-module \
  -module-name FleckCore \
  -module-cache-path "$build_dir/module-cache" \
  "${fleck_core_sources[@]}" \
  -o "$build_dir/libFleckCore.dylib" \
  -emit-module-path "$build_dir/FleckCore.swiftmodule"
swiftc -O -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  -I "$build_dir" \
  -L "$build_dir" \
  -Xlinker -rpath \
  -Xlinker "$build_dir" \
  -lFleckCore \
  "$source" \
  "$model_evaluation_source" \
  "$evidence_source" \
  "$local_writing_evidence_source" \
  "$artifact_inventory_source" \
  -o "$build_dir/qwen-native-corpus-benchmark"

readonly sandbox_profile='(version 1) (allow default) (deny network*)'
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

if [[ "$self_test" == 1 ]]; then
  exec env -i PATH=/usr/bin:/bin LC_ALL=C \
    /usr/bin/sandbox-exec -p "$sandbox_profile" \
    "$build_dir/qwen-native-corpus-benchmark" --self-test
fi

if [[ -z "$prepared_root" || -z "$helper" || -z "$public_manifest" || -z "$public_root" ||
  -z "$composite_manifest" || -z "$composite_root" || -z "$output_root" ]]; then
  usage
  exit 2
fi

exec env -i PATH=/usr/bin:/bin LC_ALL=C \
  /usr/bin/sandbox-exec -p "$sandbox_profile" \
  "$build_dir/qwen-native-corpus-benchmark" \
  --prepared-root "$prepared_root" \
  --helper "$helper" \
  --public-human-manifest "$public_manifest" \
  --public-human-root "$public_root" \
  --composite-manifest "$composite_manifest" \
  --composite-root "$composite_root" \
  --output-root "$output_root" \
  --metadata "$metadata" \
  --repo-root "$repo_root"
