#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly package_root="$(cd "$script_dir/../.." && pwd)"
readonly preflight_product="nemotron-asr-preflight"

backend=""
runtime_path=""
model_path=""
helper_path=""
output=""
self_test=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend|--runtime-path|--model-path|--helper-path|--output)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        echo "missing value for $1" >&2
        exit 2
      }
      case "$1" in
        --backend) [[ -z "$backend" ]] || { echo "duplicate argument: $1" >&2; exit 2; }; backend="$2" ;;
        --runtime-path) [[ -z "$runtime_path" ]] || { echo "duplicate argument: $1" >&2; exit 2; }; runtime_path="$2" ;;
        --model-path) [[ -z "$model_path" ]] || { echo "duplicate argument: $1" >&2; exit 2; }; model_path="$2" ;;
        --helper-path) [[ -z "$helper_path" ]] || { echo "duplicate argument: $1" >&2; exit 2; }; helper_path="$2" ;;
        --output) [[ -z "$output" ]] || { echo "duplicate argument: $1" >&2; exit 2; }; output="$2" ;;
      esac
      shift 2
      ;;
    --self-test)
      self_test=true
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

require_absolute_local_path() {
  local field="$1"
  local path="$2"
  if [[ "$path" != /* || "$path" == *"://"* ]]; then
    echo "all $field paths must be absolute local paths" >&2
    return 2
  fi
}

build_checked_in_preflight() {
  local scratch_root="$1"
  local build_log="$scratch_root/build.log"
  local bin_path
  local executable

  mkdir -p "$scratch_root"
  if ! swift build \
    --package-path "$package_root" \
    --scratch-path "$scratch_root/swiftpm" \
    --disable-automatic-resolution \
    --configuration release \
    --product "$preflight_product" \
    >"$build_log" 2>&1; then
    cat "$build_log" >&2
    return 2
  fi

  if ! bin_path="$(swift build \
    --package-path "$package_root" \
    --scratch-path "$scratch_root/swiftpm" \
    --disable-automatic-resolution \
    --configuration release \
    --show-bin-path 2>>"$build_log")"; then
    cat "$build_log" >&2
    return 2
  fi

  executable="$bin_path/$preflight_product"
  [[ -x "$executable" ]] || {
    echo "checked-in preflight build is not executable" >&2
    return 2
  }
  printf '%s\n' "$executable"
}

publish_output_exclusively() {
  local source="$1"
  local destination="$2"

  if ! /bin/link "$source" "$destination"; then
    rm -f "$source"
    echo "preflight output publication failed: destination already exists or is unavailable" >&2
    return 2
  fi
  if ! rm -f "$source"; then
    echo "preflight output publication cleanup failed" >&2
    return 2
  fi
}

assert_no_output_or_temp() {
  local destination="$1"
  local parent
  local name

  parent="$(dirname "$destination")"
  name="$(basename "$destination")"
  if [[ -e "$destination" ]] || compgen -G "$parent/.${name}.preflight.*" > /dev/null; then
    echo "self-test=preflight-failure-left-output:fail" >&2
    return 1
  fi
}

run_self_test() {
  local self_test_root
  local preflight
  local fake_preflight
  local launch_marker
  local invalid_output
  local invalid_exit
  local invalid_path
  local substitution_output
  local substitution_exit
  local substitution_path
  local checked_in_output
  local checked_in_exit
  local checked_in_path
  local retry_output
  local retry_exit
  local retry_path
  local race_temp
  local race_output
  local race_result
  local race_exit
  local directory_race_temp
  local directory_race_output
  local directory_race_result
  local directory_race_exit
  local symlink_race_temp
  local symlink_race_output
  local symlink_race_target
  local symlink_race_result
  local symlink_race_exit

  self_test_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nemotron-preflight-self-test.XXXXXX")"
  trap 'rm -rf "$self_test_root"' RETURN

  preflight="$(build_checked_in_preflight "$self_test_root/build")"

  race_temp="$self_test_root/race-output-temp"
  race_output="$self_test_root/race-output"
  printf 'candidate-output\n' > "$race_temp"
  printf 'race-created-output\n' > "$race_output"
  set +e
  race_result="$(publish_output_exclusively "$race_temp" "$race_output" 2>&1)"
  race_exit=$?
  set -e
  if [[ "$race_exit" -eq 0 || "$race_result" != *"preflight output publication failed"* || -e "$race_temp" || "$(<"$race_output")" != "race-created-output" ]]; then
    echo "self-test=exclusive-publication-race-preserves-destination:fail" >&2
    return 1
  fi
  echo "self-test=exclusive-publication-race-preserves-destination:pass"

  directory_race_temp="$self_test_root/directory-race-output-temp"
  directory_race_output="$self_test_root/directory-race-output"
  printf 'directory-race-output\n' > "$directory_race_temp"
  mkdir "$directory_race_output"
  set +e
  directory_race_result="$(publish_output_exclusively "$directory_race_temp" "$directory_race_output" 2>&1)"
  directory_race_exit=$?
  set -e
  if [[ "$directory_race_exit" -eq 0 ||
        "$directory_race_result" != *"preflight output publication failed"* ||
        -e "$directory_race_temp" ||
        ! -d "$directory_race_output" ]] ||
     [[ -n "$(find "$directory_race_output" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "self-test=exclusive-publication-directory-destination-rejected:fail" >&2
    return 1
  fi
  echo "self-test=exclusive-publication-directory-destination-rejected:pass"

  symlink_race_temp="$self_test_root/symlink-race-output-temp"
  symlink_race_output="$self_test_root/symlink-race-output"
  symlink_race_target="$self_test_root/symlink-race-target"
  printf 'symlink-race-output\n' > "$symlink_race_temp"
  mkdir "$symlink_race_target"
  ln -s "$symlink_race_target" "$symlink_race_output"
  set +e
  symlink_race_result="$(publish_output_exclusively "$symlink_race_temp" "$symlink_race_output" 2>&1)"
  symlink_race_exit=$?
  set -e
  if [[ "$symlink_race_exit" -eq 0 ||
        "$symlink_race_result" != *"preflight output publication failed"* ||
        -e "$symlink_race_temp" ||
        ! -L "$symlink_race_output" ]] ||
     [[ -n "$(find "$symlink_race_target" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "self-test=exclusive-publication-symlink-directory-destination-rejected:fail" >&2
    return 1
  fi
  echo "self-test=exclusive-publication-symlink-directory-destination-rejected:pass"

  invalid_path="$self_test_root/invalid-backend.json"
  set +e
  invalid_output="$(
    "$script_dir/run-preflight.sh" \
      --backend gpu \
      --runtime-path "$self_test_root/runtime" \
      --model-path "$self_test_root/model" \
      --helper-path "$self_test_root/helper" \
      --output "$invalid_path" 2>&1
  )"
  invalid_exit=$?
  set -e
  if [[ "$invalid_exit" -ne 2 || "$invalid_output" != *"invalid-backend:gpu"* ]]; then
    echo "self-test=backend-validation:fail" >&2
    printf '%s\n' "$invalid_output" >&2
    return 1
  fi
  assert_no_output_or_temp "$invalid_path"
  echo "self-test=backend-validation:pass"

  launch_marker="$self_test_root/fake-preflight-launched"
  fake_preflight="$self_test_root/fake-preflight"
  printf '#!/usr/bin/env bash\n: > %q\n' "$launch_marker" > "$fake_preflight"
  chmod +x "$fake_preflight"
  substitution_path="$self_test_root/substitution.json"
  set +e
  substitution_output="$(
    "$script_dir/run-preflight.sh" \
      --preflight "$fake_preflight" \
      --backend cpu \
      --runtime-path "$self_test_root/runtime" \
      --model-path "$self_test_root/model" \
      --helper-path "$self_test_root/helper" \
      --output "$substitution_path" 2>&1
  )"
  substitution_exit=$?
  set -e
  if [[ "$substitution_exit" -ne 2 || "$substitution_output" != *"unknown argument: --preflight"* ]]; then
    echo "self-test=preflight-substitution-rejected:fail" >&2
    printf '%s\n' "$substitution_output" >&2
    return 1
  fi
  if [[ -e "$launch_marker" ]]; then
    echo "self-test=preflight-substitution-launch:fail" >&2
    return 1
  fi
  assert_no_output_or_temp "$substitution_path"
  echo "self-test=preflight-substitution-rejected:pass"

  checked_in_path="$self_test_root/checked-in.json"
  set +e
  checked_in_output="$(
    "$script_dir/run-preflight.sh" \
      --backend cpu \
      --runtime-path "$self_test_root/runtime" \
      --model-path "$self_test_root/model" \
      --helper-path "$self_test_root/helper" \
      --output "$checked_in_path" 2>&1
  )"
  checked_in_exit=$?
  set -e
  if [[ "$checked_in_exit" -ne 2 || "$checked_in_output" != *"artifact-identity-unadmitted/runtime-identity-unavailable"* ]]; then
    echo "self-test=checked-in-preflight-fails-closed:fail" >&2
    printf '%s\n' "$checked_in_output" >&2
    return 1
  fi
  assert_no_output_or_temp "$checked_in_path"
  echo "self-test=checked-in-preflight-fails-closed:pass"

  retry_path="$self_test_root/checked-in.json"
  set +e
  retry_output="$(
    "$script_dir/run-preflight.sh" \
      --backend metal \
      --runtime-path "$self_test_root/runtime" \
      --model-path "$self_test_root/model" \
      --helper-path "$self_test_root/helper" \
      --output "$retry_path" 2>&1
  )"
  retry_exit=$?
  set -e
  if [[ "$retry_exit" -ne 2 || "$retry_output" != *"artifact-identity-unadmitted/runtime-identity-unavailable"* ]]; then
    echo "self-test=preflight-failure-retry-unblocked:fail" >&2
    printf '%s\n' "$retry_output" >&2
    return 1
  fi
  assert_no_output_or_temp "$retry_path"
  echo "self-test=preflight-failure-retry-unblocked:pass"

  # Keep the built path exercised directly so the harness cannot pass by replacing it.
  set +e
  checked_in_output="$(
    "$preflight" \
      --backend metal \
      --runtime-path "$self_test_root/runtime" \
      --model-path "$self_test_root/model" \
      --helper-path "$self_test_root/helper" 2>&1
  )"
  checked_in_exit=$?
  set -e
  if [[ "$checked_in_exit" -ne 2 || "$checked_in_output" != *"artifact-identity-unadmitted/runtime-identity-unavailable"* ]]; then
    echo "self-test=checked-in-binary-identity-gate:fail" >&2
    printf '%s\n' "$checked_in_output" >&2
    return 1
  fi
  echo "self-test=checked-in-binary-identity-gate:pass"
}

if [[ "$self_test" == true ]]; then
  if [[ -n "$backend$runtime_path$model_path$helper_path$output" ]]; then
    echo "--self-test cannot be combined with preflight arguments" >&2
    exit 2
  fi
  run_self_test
  exit 0
fi

[[ -n "$backend" ]] || { echo "--backend is required" >&2; exit 2; }
[[ -n "$runtime_path" ]] || { echo "--runtime-path is required" >&2; exit 2; }
[[ -n "$model_path" ]] || { echo "--model-path is required" >&2; exit 2; }
[[ -n "$helper_path" ]] || { echo "--helper-path is required" >&2; exit 2; }
[[ -n "$output" ]] || { echo "--output is required" >&2; exit 2; }

require_absolute_local_path "runtime" "$runtime_path"
require_absolute_local_path "model" "$model_path"
require_absolute_local_path "helper" "$helper_path"
require_absolute_local_path "output" "$output"
[[ "$output" != "/" && "$output" != */ ]] || { echo "--output must name a file" >&2; exit 2; }
[[ ! -e "$output" && ! -L "$output" ]] || { echo "output already exists: $output" >&2; exit 2; }

readonly output_parent="$(dirname "$output")"
[[ -d "$output_parent" ]] || { echo "output parent is not a directory" >&2; exit 2; }
readonly output_name="$(basename "$output")"
readonly preflight_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nemotron-preflight.XXXXXX")"
readonly preflight_stderr="$(mktemp "$preflight_root/stderr.XXXXXX")"
output_temp=""
cleanup() {
  rm -rf "$preflight_root"
  [[ -z "$output_temp" ]] || rm -f "$output_temp"
}
trap cleanup EXIT

readonly checked_in_preflight="$(build_checked_in_preflight "$preflight_root/build")"
output_temp="$(mktemp "$output_parent/.${output_name}.preflight.XXXXXX")"

set +e
"$checked_in_preflight" \
  --backend "$backend" \
  --runtime-path "$runtime_path" \
  --model-path "$model_path" \
  --helper-path "$helper_path" \
  >"$output_temp" 2>"$preflight_stderr"
preflight_exit=$?
set -e
cat "$preflight_stderr" >&2
if [[ "$preflight_exit" -ne 0 ]]; then
  echo "preflight-exit=$preflight_exit" >&2
  exit "$preflight_exit"
fi

publish_output_exclusively "$output_temp" "$output"
echo "preflight-admitted=true"
