#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  printf 'usage: %s\n' "${0##*/}" >&2
  exit 2
fi

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly nonempty_runner="$script_dir/run-nonempty-swift-tests.sh"
readonly strict_capture_selector='^FleckAppTests\.hostedGlassAndSolidMenuPanelsCaptureSyntheticChromeAndOpaqueEditor\(\)$'

[[ -x "$nonempty_runner" ]] || {
  printf 'error: non-empty Swift test runner is missing or not executable: %s\n' \
    "$nonempty_runner" >&2
  exit 1
}
[[ -f "$repo_root/VERSION" && ! -L "$repo_root/VERSION" ]] || {
  printf 'error: product VERSION file is missing or unsafe: %s\n' \
    "$repo_root/VERSION" >&2
  exit 1
}

resolve_clean_source() {
  local commit tree status confirmed_commit

  if ! commit="$(git -C "$repo_root" rev-parse --verify 'HEAD^{commit}')"; then
    printf '%s\n' 'error: could not resolve the native-QA source commit' >&2
    return 1
  fi
  if [[ ! "$commit" =~ ^([[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]]; then
    printf '%s\n' 'error: native-QA source commit is not a full object ID' >&2
    return 1
  fi
  if ! tree="$(git -C "$repo_root" rev-parse --verify "$commit^{tree}")"; then
    printf '%s\n' 'error: could not resolve the native-QA source tree' >&2
    return 1
  fi
  if [[ ! "$tree" =~ ^([[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]]; then
    printf '%s\n' 'error: native-QA source tree is not a full object ID' >&2
    return 1
  fi
  if ! status="$(git -C "$repo_root" status --porcelain --untracked-files=all \
    --ignore-submodules=none)"; then
    printf '%s\n' 'error: could not verify a clean native-QA working tree' >&2
    return 1
  fi
  if [[ -n "$status" ]]; then
    printf '%s\n' 'error: native QA requires a clean committed working tree' >&2
    return 1
  fi
  if ! confirmed_commit="$(git -C "$repo_root" rev-parse --verify 'HEAD^{commit}')"; then
    printf '%s\n' 'error: could not confirm the native-QA source commit' >&2
    return 1
  fi
  if [[ "$confirmed_commit" != "$commit" ]]; then
    printf '%s\n' 'error: native-QA source commit changed during provenance verification' >&2
    return 1
  fi

  printf '%s\n%s\n' "$commit" "$tree"
}

if ! initial_source="$(resolve_clean_source)"; then
  exit 1
fi
readonly source_commit="${initial_source%%$'\n'*}"
readonly source_tree="${initial_source#*$'\n'}"
if ! source_version="$(cat "$repo_root/VERSION")" || [[ -z "$source_version" ]]; then
  printf '%s\n' 'error: could not read the native-QA product version' >&2
  exit 1
fi
readonly source_version

output_parent="${TMPDIR:-/tmp}"
[[ -d "$output_parent" ]] || {
  printf 'error: native capture QA output parent is not a directory: %s\n' \
    "$output_parent" >&2
  exit 1
}
output_parent="$(cd -P -- "$output_parent" && pwd -P)"
case "$output_parent/" in
  "$repo_root/"*|*/Fleck-builds/accepted/*)
    printf '%s\n' 'error: native capture QA output parent must be outside the repository and accepted store' >&2
    exit 1
    ;;
esac

output_dir="$(mktemp -d "$output_parent/fleck-native-capture-qa.XXXXXXXX")"
readonly output_dir
readonly console_receipt="$output_dir/console.log"

export FLECK_NATIVE_CAPTURE_QA=1
export FLECK_GLASS_SYNTHETIC_CAPTURE_DIR="$output_dir"
unset FLECK_ENHANCED_CANDIDATE

{
  printf '%s\n' 'Native capture QA provenance'
  printf '%s\n' 'Working source status: clean'
  printf 'Fleck version: %s\n' "$source_version"
  printf 'Source commit: %s\n' "$source_commit"
  printf 'Source tree: %s\n' "$source_tree"
  printf 'Native capture opt-in: FLECK_NATIVE_CAPTURE_QA=1\n'
  printf 'Strict test selector: %s\n' "$strict_capture_selector"
  printf 'Output directory: %s\n' "$output_dir"
  printf 'Console receipt: %s\n' "$console_receipt"
  printf 'PNG artifacts on success: %s/glass.png and %s/solid.png\n' \
    "$output_dir" "$output_dir"
} | tee "$console_receipt"

set +e
"$nonempty_runner" "$strict_capture_selector" 2>&1 | tee -a "$console_receipt"
pipeline_status=("${PIPESTATUS[@]}")
set -e

capture_status="${pipeline_status[0]}"
receipt_status="${pipeline_status[1]}"
source_status=0
if ! final_source="$(resolve_clean_source)"; then
  source_status=1
elif [[ "$final_source" != "$source_commit"$'\n'"$source_tree" ]]; then
  printf '%s\n' 'error: native-QA source commit or tree changed during the run' >&2
  source_status=1
fi
if (( source_status == 0 )); then
  printf '%s\n' 'Native capture QA source verification after run: clean and unchanged' \
    | tee -a "$console_receipt"
else
  printf '%s\n' 'Native capture QA source verification after run: FAILED' \
    | tee -a "$console_receipt"
fi
printf 'Native capture QA runner exit status: %s\n' "$capture_status" | tee -a "$console_receipt"
if (( source_status != 0 )); then
  if (( capture_status != 0 )); then
    exit "$capture_status"
  fi
  exit 1
fi
if (( capture_status == 0 && receipt_status != 0 )); then
  exit "$receipt_status"
fi
exit "$capture_status"
