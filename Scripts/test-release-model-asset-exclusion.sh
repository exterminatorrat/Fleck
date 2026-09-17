#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly gate="$script_dir/check-release-size.sh"
readonly temp_root="$(cd -P -- "$(mktemp -d "${TMPDIR:-/tmp}/fleck-release-model-assets.XXXXXX")" && pwd)"
readonly app="$temp_root/Fleck.app"
readonly resources="$app/Contents/Resources"
readonly output="$temp_root/gate-output"
readonly old_limit_bytes=$((18 * 1024 * 1024))
cleanup() {
  find "$temp_root" -depth -delete
}
trap cleanup EXIT

/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/SharedSupport"
printf 'print("Fleck release fixture")\n' > "$temp_root/Fleck.swift"
xcrun swiftc "$temp_root/Fleck.swift" -o "$temp_root/Fleck"
/bin/cp "$temp_root/Fleck" "$app/Contents/MacOS/Fleck"
/bin/cp "$temp_root/Fleck" "$app/Contents/SharedSupport/fleck-agent"

reset_resources() {
  find "$resources" -depth -delete 2>/dev/null || true
  /bin/mkdir -p "$resources/Neutral"
}

run_gate() {
  local label="$1"
  local expected_exit="$2"
  local actual_exit

  set +e
  "$gate" "$app" >"$output" 2>&1
  actual_exit=$?
  set -e
  if (( actual_exit != expected_exit )); then
    printf 'error: %s expected exit %s, got %s\n' \
      "$label" "$expected_exit" "$actual_exit" >&2
    cat "$output" >&2
    exit 1
  fi
}

assert_rejected_at_neutral_path() {
  local filename="$1"
  local path="$resources/Neutral/$filename"

  reset_resources
  printf 'temporary fixture\n' > "$path"
  run_gate "$filename" 1
  grep -Fq 'error: release artifact contains model assets:' "$output"
  grep -Fq "$path" "$output"
  printf 'Rejected neutral %s with an explicit path diagnostic.\n' "$filename"
}

assert_rejected_at_neutral_path 'payload.SaFeTeNsOrS'
assert_rejected_at_neutral_path 'payload.GgUf'
assert_rejected_at_neutral_path 'payload.OnNx'

reset_resources
printf 'temporary fixture\n' > "$resources/Neutral/payload.bin"
run_gate 'unrelated neutral .bin' 0
grep -Fq 'Release artifact contains no bundled model assets.' "$output"
printf 'Accepted unrelated neutral .bin.\n'

reset_resources
/bin/mkdir -p "$temp_root/external/Neutral"
printf 'temporary fixture\n' > "$temp_root/external/Neutral/payload.sAfEtEnSoRs"
ln -s "$temp_root/external/Neutral" "$resources/Neutral/linked-directory"
linked_path="$resources/Neutral/linked-directory/payload.sAfEtEnSoRs"
run_gate 'symlinked directory' 1
grep -Fq 'error: release artifact contains model assets:' "$output"
grep -Fq "$linked_path" "$output"
printf 'Rejected mixed-case .safetensors through a symlinked directory.\n'

reset_resources
/bin/dd if=/dev/zero of="$app/Contents/MacOS/Fleck" \
  bs=1 count=1 seek="$old_limit_bytes" conv=notrunc 2>/dev/null
oversized_bytes="$(wc -c < "$app/Contents/MacOS/Fleck" | tr -d '[:space:]')"
helper_bytes="$(wc -c < "$app/Contents/SharedSupport/fleck-agent" | tr -d '[:space:]')"
if (( oversized_bytes <= old_limit_bytes )); then
  printf 'error: oversized compiled fixture was not padded past 18 MiB\n' >&2
  exit 1
fi
APP_SIZE_LIMIT_MB=1 run_gate 'oversized valid compiled artifact' 0
grep -Fq "Fleck executable: $oversized_bytes bytes" "$output"
grep -Fq "fleck-agent helper: $helper_bytes bytes" "$output"
grep -Fq 'Release artifact contains no bundled model assets.' "$output"
printf 'Accepted oversized valid compiled artifact and reported its actual size.\n'

oversized_model_path="$resources/Neutral/oversized-model.safetensors"
printf 'temporary fixture\n' > "$oversized_model_path"
run_gate 'oversized artifact with model asset' 1
grep -Fq 'error: release artifact contains model assets:' "$output"
grep -Fq "$oversized_model_path" "$output"
printf 'Rejected model asset in the same oversized artifact with an explicit path diagnostic.\n'

/bin/cp "$temp_root/Fleck" "$app/Contents/MacOS/Fleck"
cmp -s "$temp_root/Fleck" "$app/Contents/MacOS/Fleck"

printf 'Release model-asset exclusion fixtures passed.\n'
