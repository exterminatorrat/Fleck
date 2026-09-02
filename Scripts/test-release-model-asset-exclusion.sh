#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly gate="$script_dir/check-release-size.sh"
readonly temp_root="$(cd -P -- "$(mktemp -d "${TMPDIR:-/tmp}/fleck-release-model-assets.XXXXXX")" && pwd)"
readonly app="$temp_root/Fleck.app"
readonly resources="$app/Contents/Resources"
readonly output="$temp_root/gate-output"
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

printf 'Release model-asset exclusion fixtures passed.\n'
