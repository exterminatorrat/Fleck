#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly validator="$repo_root/Scripts/validate-macos.sh"
readonly test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-validate-contract.XXXXXX")"

cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  return 1
}

require_fixed() {
  local file="$1"
  local expected="$2"
  local label="$3"
  /usr/bin/grep -Fq -- "$expected" "$file" \
    || fail "validator is missing $label"
}

reject_regex() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if /usr/bin/grep -Eq -- "$pattern" "$file"; then
    fail "validator contains $label"
  fi
}

validate_contract() {
  local file="$1"

  require_fixed \
    "$file" \
    '"$script_dir/run-nonempty-swift-tests.sh" '\''^.+$'\''' \
    'the complete non-empty Swift test gate' \
    || return 1
  require_fixed \
    "$file" \
    '"$script_dir/build-fleck-app.sh"' \
    'the packaged release build gate' \
    || return 1
  require_fixed \
    "$file" \
    '/usr/bin/codesign --verify --deep --strict "$app_bundle"' \
    'strict static bundle signature verification' \
    || return 1
  require_fixed \
    "$file" \
    '"$script_dir/check-release-size.sh" "$app_bundle"' \
    'the static release size and model-asset gate' \
    || return 1
  require_fixed \
    "$file" \
    '"$script_dir/test-enhanced-candidate-lock-preservation.sh"' \
    'candidate lock preservation' \
    || return 1
  require_fixed \
    "$file" \
    '"$script_dir/check-candidate-release-rejected.sh"' \
    'candidate release rejection' \
    || return 1
  require_fixed \
    "$file" \
    '/usr/bin/strings "$app_binary"' \
    'static executable identity inspection' \
    || return 1

  if [[ "$(/usr/bin/grep -Fc -- '$app_binary' "$file")" != '1' ]]; then
    fail 'validator must use app_binary only for static strings inspection'
    return 1
  fi
  reject_regex \
    "$file" \
    '^[[:space:]]*(/usr/bin/)?open[[:space:]]' \
    'a native open invocation' \
    || return 1
  reject_regex \
    "$file" \
    '^[[:space:]]*(/bin/)?(kill|wait)([[:space:]]|$)' \
    'process termination or waiting' \
    || return 1
  reject_regex \
    "$file" \
    '&[[:space:]]*$' \
    'a background process launch' \
    || return 1
}

validate_contract "$validator"

runtime_fixture="$test_root/runtime-launch.sh"
/bin/cp "$validator" "$runtime_fixture"
printf '%s\n' '"$app_binary" >/dev/null 2>&1 &' >> "$runtime_fixture"
if validate_contract "$runtime_fixture" 2>/dev/null; then
  fail 'contract accepted an app-binary launch'
fi

open_fixture="$test_root/native-open.sh"
/bin/cp "$validator" "$open_fixture"
printf '%s\n' '/usr/bin/open -n "$app_bundle"' >> "$open_fixture"
if validate_contract "$open_fixture" 2>/dev/null; then
  fail 'contract accepted a native open invocation'
fi

kill_fixture="$test_root/process-kill.sh"
/bin/cp "$validator" "$kill_fixture"
printf '%s\n' '/bin/kill -TERM 123' >> "$kill_fixture"
if validate_contract "$kill_fixture" 2>/dev/null; then
  fail 'contract accepted process termination'
fi

missing_static_fixture="$test_root/missing-static-gate.sh"
/usr/bin/grep -Fv \
  '/usr/bin/codesign --verify --deep --strict "$app_bundle"' \
  "$validator" > "$missing_static_fixture"
if validate_contract "$missing_static_fixture" 2>/dev/null; then
  fail 'contract accepted removal of strict static signature verification'
fi

printf '%s\n' 'validate-macos no-launch contract passed.'
