#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
source_file="$script_dir/WhisperSmallCorpusBenchmark.swift"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-whisper-small-benchmark.XXXXXX")"
module_cache="$build_dir/module-cache"
binary="$build_dir/whisper-small-corpus-benchmark"

cleanup() {
  rm -rf -- "$build_dir"
}
trap cleanup EXIT

mkdir -p -- "$module_cache"
CLANG_MODULE_CACHE_PATH="$module_cache" swiftc -O -parse-as-library "$source_file" -o "$binary"
exec "$binary" "$@"
