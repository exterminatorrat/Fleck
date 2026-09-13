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

run_preservation_fixture() {
  local validator_source="$1"
  local fixture_root="$2"
  local tools="$fixture_root/tools"
  local gate_log="$fixture_root/gates"
  local validator_log="$fixture_root/validator.log"
  local sentinel_paths=(
    '.build/Fleck 1.0.2-beta.1 Build 41.app/sentinel'
    '.build/Fleck 1.0.2-beta.1 Build 42/sentinel'
    '.build/Fleck 1.0.2-beta.1 Build 42/Fleck 1.0.2-beta.1 Build 42-arm64.zip'
    '.build/parakeet-test/Fleck 1.0.2-beta.1 Build 40.app/sentinel'
    '.build/results/prior-result.json'
    '.build/build-metadata/identities.sqlite3'
    '.build/.fleck-packaging-operation.lock/owner.json'
  )

  /bin/mkdir -p \
    "$fixture_root/Scripts" \
    "$fixture_root/website/public" \
    "$tools" \
    "$gate_log"
  /bin/cp "$validator_source" "$fixture_root/Scripts/validate-macos.sh"
  printf '%s\n' 'fixture mark' > "$fixture_root/website/public/fleck-mark.png"

  local relative
  for relative in "${sentinel_paths[@]}"; do
    /bin/mkdir -p "$(/usr/bin/dirname "$fixture_root/$relative")"
    printf '%s\n' "preserve $relative" > "$fixture_root/$relative"
  done

  /bin/cat > "$tools/sw_vers" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-productVersion' ]]; then
  printf '%s\n' '14.0'
else
  printf '%s\n' 'ProductName: macOS' 'ProductVersion: 14.0'
fi
EOF
  /bin/cat > "$tools/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == '-p' ]]
printf '%s\n' '/Applications/Xcode.app/Contents/Developer'
EOF
  /bin/cat > "$tools/xcodebuild" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == '-version' ]]
printf '%s\n' 'Xcode fixture'
EOF
  /bin/cat > "$tools/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == '--version' ]]; then
  printf '%s\n' 'Swift fixture'
  exit 0
fi
if [[ "${1:-}" == 'package' && "${2:-}" == 'clean' ]]; then
  /usr/bin/find "$PWD/.build" -depth -delete
  /bin/mkdir "$PWD/.build"
  exit 0
fi
exit 2
EOF

  /bin/cat > "$fixture_root/Scripts/run-nonempty-swift-tests.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == '^.+$' ]]
/usr/bin/touch "$FLECK_VALIDATOR_GATE_ROOT/tests"
EOF
  /bin/cat > "$fixture_root/Scripts/build-fleck-app.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 && "$1" == '--result-file' ]]
readonly result_file="$2"
readonly repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly app="$repo_root/.build/Fleck 1.0.3-beta.1 Build 999.app"
readonly plist="$app/Contents/Info.plist"
/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/SharedSupport" "$app/Contents/Resources"
/bin/cat > "$repo_root/.build/fixture.c" <<'SOURCE'
#include <stdio.h>
int main(void) { puts("com.harryjin.fleck"); return 0; }
SOURCE
/usr/bin/clang -arch arm64 "$repo_root/.build/fixture.c" -o "$app/Contents/MacOS/Fleck"
/usr/bin/clang -arch arm64 "$repo_root/.build/fixture.c" -o "$app/Contents/SharedSupport/fleck-agent"
/bin/cp "$repo_root/website/public/fleck-mark.png" "$app/Contents/Resources/fleck-mark.png"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.harryjin.fleck "$plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
/usr/bin/plutil -insert LSUIElement -bool true "$plist"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$plist"
/usr/bin/plutil -insert NSMicrophoneUsageDescription -string fixture "$plist"
/usr/bin/plutil -insert NSSpeechRecognitionUsageDescription -string fixture "$plist"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/Fleck" >/dev/null
/usr/bin/codesign --force --sign - "$app/Contents/SharedSupport/fleck-agent" >/dev/null
/usr/bin/codesign --force --sign - \
  --identifier com.harryjin.fleck \
  -r '=designated => identifier "com.harryjin.fleck"' \
  "$app" >/dev/null
/usr/bin/python3 - "$result_file" "$app" <<'PY'
import json
import sys
with open(sys.argv[1], "x", encoding="utf-8") as handle:
    json.dump({"appPath": sys.argv[2], "buildID": "99999999-9999-4999-8999-999999999999"}, handle)
PY
/usr/bin/touch "$FLECK_VALIDATOR_GATE_ROOT/package"
EOF
  /bin/cat > "$fixture_root/Scripts/fleck-build-identity.py" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == 'read-result' ]]
while (( $# > 0 )); do
  if [[ "$1" == '--result-file' ]]; then
    /usr/bin/plutil -extract appPath raw -o - "$2"
    exit 0
  fi
  shift
done
exit 2
EOF
  /bin/cat > "$fixture_root/Scripts/check-release-size.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test -d "$1"
/usr/bin/touch "$FLECK_VALIDATOR_GATE_ROOT/size"
EOF
  /bin/cat > "$fixture_root/Scripts/test-enhanced-candidate-lock-preservation.sh" <<'EOF'
#!/usr/bin/env bash
/usr/bin/touch "$FLECK_VALIDATOR_GATE_ROOT/lock"
EOF
  /bin/cat > "$fixture_root/Scripts/check-candidate-release-rejected.sh" <<'EOF'
#!/usr/bin/env bash
/usr/bin/touch "$FLECK_VALIDATOR_GATE_ROOT/rejection"
EOF
  /bin/chmod 755 "$tools"/* "$fixture_root/Scripts"/*

  if ! /usr/bin/env \
    PATH="$tools:/usr/bin:/bin" \
    FLECK_VALIDATOR_GATE_ROOT="$gate_log" \
    /bin/bash "$fixture_root/Scripts/validate-macos.sh" \
    >"$validator_log" 2>&1; then
    /bin/cat "$validator_log" >&2
    return 2
  fi
  for relative in tests package size lock rejection; do
    test -f "$gate_log/$relative" || return 2
  done
  for relative in "${sentinel_paths[@]}"; do
    test -f "$fixture_root/$relative" || return 1
  done
}

readonly preserved_fixture="$test_root/preserved/repository"
run_preservation_fixture "$validator" "$preserved_fixture"

readonly root_clean_mutant="$test_root/root-clean-mutant.sh"
/usr/bin/awk '
  { print }
  /--- Release build ---/ { print "swift package clean" }
' "$validator" > "$root_clean_mutant"
readonly mutant_fixture="$test_root/mutant/repository"
set +e
run_preservation_fixture "$root_clean_mutant" "$mutant_fixture"
mutant_status=$?
set -e
if [[ "$mutant_status" != '1' ]]; then
  fail "root-clean mutant did not fail artifact preservation (status $mutant_status)"
fi
printf '%s\n' 'root-clean mutant failed artifact preservation with status 1.'

printf '%s\n' 'validate-macos no-launch and artifact-preservation contracts passed.'
