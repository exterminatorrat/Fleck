#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(cd "$script_dir/../../../../.." && pwd -P)"
readonly recognizer_source="$script_dir/QwenSherpaRecognizer.swift"
readonly main_source="$script_dir/main.swift"
readonly bridging_header="$script_dir/SherpaOnnx-Bridging-Header.h"

prepared_root=""
output_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepared-root)
      prepared_root="${2:-}"
      shift 2
      ;;
    --output-root)
      output_root="${2:-}"
      shift 2
      ;;
    *)
      echo "unsupported-argument:$1" >&2
      exit 2
      ;;
  esac
done

is_safe_absolute_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != *"://"* && "$path" != *"/./"* && "$path" != *"/../"* && "$path" != */. && "$path" != */.. ]]
}

has_symlink_component() {
  local path="$1"
  local current="/"
  local remaining="${path#/}"
  local component
  while [[ -n "$remaining" ]]; do
    if [[ "$remaining" == */* ]]; then
      component="${remaining%%/*}"
      remaining="${remaining#*/}"
    else
      component="$remaining"
      remaining=""
    fi
    [[ -n "$component" ]] || continue
    current="${current%/}/$component"
    [[ -L "$current" ]] && return 0
  done
  return 1
}

canonicalize_existing_ancestor() {
  local path="$1"
  local unresolved=""
  local probe="$path"
  local component
  while [[ ! -e "$probe" && ! -L "$probe" ]]; do
    [[ "$probe" != "/" ]] || return 1
    component="${probe##*/}"
    unresolved="/$component$unresolved"
    probe="${probe%/*}"
    [[ -n "$probe" ]] || probe="/"
  done
  local canonical
  canonical="$(realpath "$probe")" || return 1
  if [[ "$canonical" == "/" ]]; then
    printf '/%s\n' "${unresolved#/}"
  else
    printf '%s%s\n' "${canonical%/}" "$unresolved"
  fi
}

if ! is_safe_absolute_path "$prepared_root"; then
  echo "prepared-root-must-be-absolute" >&2
  exit 2
fi
if ! is_safe_absolute_path "$output_root"; then
  echo "output-root-must-be-absolute" >&2
  exit 2
fi
readonly canonical_repo_root="$(realpath "$repo_root")"
if has_symlink_component "$prepared_root" || has_symlink_component "$output_root"; then
  echo "path-symlink-alias-rejected" >&2
  exit 2
fi
readonly canonical_prepared_root="$(canonicalize_existing_ancestor "$prepared_root")" || {
  echo "prepared-root-cannot-be-canonicalized" >&2
  exit 2
}
readonly canonical_output_root="$(canonicalize_existing_ancestor "$output_root")" || {
  echo "output-root-cannot-be-canonicalized" >&2
  exit 2
}
[[ "$canonical_prepared_root" == "$prepared_root" ]] || {
  echo "prepared-root-must-be-canonical" >&2
  exit 2
}
if [[ "$canonical_output_root" == "$canonical_repo_root" || "$canonical_output_root" == "$canonical_repo_root"/* ]]; then
  echo "output-root-must-be-external" >&2
  exit 2
fi
readonly output_parent="$(dirname "$output_root")"
[[ -d "$output_parent" && ! -L "$output_parent" ]] || {
  echo "output-parent-must-be-existing-directory" >&2
  exit 2
}
[[ "$(uname -m)" == "arm64" ]] || {
  echo "arm64-required" >&2
  exit 2
}
[[ -f "$prepared_root/installed-artifact-inventory.json" ]] || {
  echo "prepared-inventory-missing" >&2
  exit 2
}

readonly framework_parent="$prepared_root/runtime/sherpa-onnx.xcframework/macos-arm64_x86_64"
readonly framework="$framework_parent/SherpaOnnxC.framework"
readonly header="$framework/Versions/A/Headers/sherpa-onnx/c-api/c-api.h"
readonly binary="$framework/Versions/A/SherpaOnnxC"
[[ -f "$header" ]] || {
  echo "sherpa-header-missing" >&2
  exit 2
}
[[ -f "$binary" ]] || {
  echo "sherpa-framework-binary-missing" >&2
  exit 2
}
[[ "$(file -b "$binary")" == *"arm64"* ]] || {
  echo "sherpa-framework-arm64-slice-missing" >&2
  exit 2
}

if [[ -e "$output_root" || -L "$output_root" ]]; then
  [[ -d "$output_root" && ! -L "$output_root" ]] || {
    echo "output-root-must-be-directory" >&2
    exit 2
  }
else
  mkdir "$output_root"
fi
readonly temporary_output_root="$(mktemp -d "$output_root/.qwen-native-evaluation.XXXXXX")"
trap 'rm -rf "$temporary_output_root"' EXIT
swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  -parse-as-library \
  -module-name QwenASRNativeEvaluation \
  -import-objc-header "$bridging_header" \
  -F "$framework_parent" \
  -Xcc -F -Xcc "$framework_parent" \
  "$recognizer_source" \
  "$main_source" \
  -o "$temporary_output_root/qwen-sherpa-native-evaluation"
mv -f "$temporary_output_root/qwen-sherpa-native-evaluation" "$output_root/qwen-sherpa-native-evaluation"
