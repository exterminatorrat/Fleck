#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly package_path="$repo_root/Tools/LocalDictationCandidateAdapters"
readonly schema_fixture_path="$repo_root/Tests/Fixtures/local-dictation-admission-v1.schema.json"

manifest_path=""
adapter_path=""
model_root_path=""
output_path=""

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

while (($# > 0)); do
  flag="$1"
  case "$flag" in
    --manifest|--adapter|--model-root|--output)
      (($# >= 2)) || fail "missing value for $flag"
      value="$2"
      [[ "$value" != --* ]] || fail "missing value for $flag"
      case "$flag" in
        --manifest) [[ -z "$manifest_path" ]] || fail "duplicate flag $flag"; manifest_path="$value" ;;
        --adapter) [[ -z "$adapter_path" ]] || fail "duplicate flag $flag"; adapter_path="$value" ;;
        --model-root) [[ -z "$model_root_path" ]] || fail "duplicate flag $flag"; model_root_path="$value" ;;
        --output) [[ -z "$output_path" ]] || fail "duplicate flag $flag"; output_path="$value" ;;
      esac
      shift 2
      ;;
    *)
      fail "unknown argument $flag"
      ;;
  esac
done

[[ -n "$manifest_path" ]] || fail "--manifest is required"
[[ -n "$adapter_path" ]] || fail "--adapter is required"
[[ -n "$model_root_path" ]] || fail "--model-root is required"
[[ -n "$output_path" ]] || fail "--output is required"

resolve_existing_file() {
  local input="$1"
  [[ -f "$input" ]] || fail "not a regular file: $input"
  local resolved="$input"
  local count=0
  while :; do
    count=$((count + 1))
    ((count <= 32)) || fail "symlink resolution exceeded limit: $input"
    local parent
    local basename
    local parent_abs
    parent="$(dirname -- "$resolved")"
    basename="$(basename -- "$resolved")"
    parent_abs="$(cd -P -- "$parent" && pwd -P)" || fail "cannot resolve parent: $input"
    resolved="$parent_abs/$basename"
    if [[ ! -L "$resolved" ]]; then
      [[ -f "$resolved" ]] || fail "resolved path is not a regular file: $input"
      printf '%s\n' "$resolved"
      return
    fi
    local target
    target="$(readlink -- "$resolved")" || fail "cannot resolve symlink: $input"
    if [[ "$target" == /* ]]; then
      resolved="$target"
    else
      resolved="$(dirname -- "$resolved")/$target"
    fi
    [[ -e "$resolved" || -L "$resolved" ]] || fail "broken symlink: $input"
  done
}

resolve_existing_directory() {
  local input="$1"
  [[ -d "$input" ]] || fail "not a directory: $input"
  cd -P -- "$input" || fail "cannot resolve directory: $input"
  pwd -P
}

resolve_new_output() {
  local input="$1"
  [[ -n "$input" ]] || fail "output path is empty"
  [[ ! -e "$input" && ! -L "$input" ]] || fail "output already exists: $input"
  local parent
  parent="$(dirname -- "$input")"
  [[ -d "$parent" ]] || fail "output parent is not a directory: $parent"
  local parent_abs
  parent_abs="$(cd -P -- "$parent" && pwd -P)" || fail "cannot resolve output parent: $parent"
  printf '%s/%s\n' "$parent_abs" "$(basename -- "$input")"
}

manifest_path="$(resolve_existing_file "$manifest_path")"
adapter_path="$(resolve_existing_file "$adapter_path")"
[[ -x "$adapter_path" ]] || fail "adapter is not executable: $adapter_path"
model_root_path="$(resolve_existing_directory "$model_root_path")"
output_path="$(resolve_new_output "$output_path")"
schema_path="$(resolve_existing_file "$schema_fixture_path")"

swift_bin="$(command -v swift)"
[[ -x "$swift_bin" ]] || fail "swift executable not found"
swift_bin="$(resolve_existing_file "$swift_bin")"

cli_bin="$($swift_bin build --package-path "$package_path" --product local-dictation-candidate --show-bin-path)/local-dictation-candidate"
[[ -x "$cli_bin" ]] || fail "candidate CLI was not built"

"$cli_bin" validate-admission --manifest "$manifest_path" --schema "$schema_path"
exec "$cli_bin" run \
  --manifest "$manifest_path" \
  --adapter "$adapter_path" \
  --model-root "$model_root_path" \
  --output "$output_path"
