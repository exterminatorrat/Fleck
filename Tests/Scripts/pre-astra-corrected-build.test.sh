#!/usr/bin/env bash
set -euo pipefail

readonly source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly source_packager="$source_root/Scripts/build-pre-astra-corrected-build.sh"
readonly source_development_packager="$source_root/Scripts/build-fleck-app.sh"
readonly test_only="${FLECK_PRE_ASTRA_TEST_ONLY:-}"
readonly launcher_case="${FLECK_PRE_ASTRA_LAUNCHER_CASE:-all}"

case "$test_only" in
  ''|first-run|launcher|lock-owner|requirement|manifest|after-final-source|after-swap|legacy-zip|publication)
    ;;
  *)
    printf 'FAIL: unknown FLECK_PRE_ASTRA_TEST_ONLY selector: %s\n' "$test_only" >&2
    exit 2
    ;;
esac
if [[ "$test_only" == 'launcher' ]]; then
  case "$launcher_case" in
    all|open|inventory|late|bounded) ;;
    *)
      printf 'FAIL: unknown FLECK_PRE_ASTRA_LAUNCHER_CASE selector: %s\n' "$launcher_case" >&2
      exit 2
      ;;
  esac
fi

if [[ ! -x "$source_packager" ]]; then
  printf 'FAIL: executable packager is missing: %s\n' "$source_packager" >&2
  exit 1
fi
if [[ "$(uname -s)" != 'Darwin' || "$(uname -m)" != 'arm64' ]]; then
  printf '%s\n' 'FAIL: this packaging test requires macOS on arm64' >&2
  exit 1
fi

test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-pre-astra-test.XXXXXX")"
test_root="$(cd -- "$test_root" && pwd -P)"
readonly test_root
cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

readonly fixture_root="$test_root/Fleck Fixture"
/bin/mkdir -p \
  "$fixture_root/Scripts" \
  "$fixture_root/Sources/FleckApp" \
  "$fixture_root/website/public"
if [[ -n "$test_only" && "$test_only" != 'first-run' ]]; then
  /bin/mkdir "$fixture_root/.build"
fi
/bin/cp -p "$source_packager" "$fixture_root/Scripts/build-pre-astra-corrected-build.sh"
/bin/cp -p "$source_development_packager" "$fixture_root/Scripts/build-fleck-app.sh"
/bin/cp -p "$source_root/Scripts/fleck-build-identity.py" \
  "$fixture_root/Scripts/fleck-build-identity.py"
/bin/cat > "$fixture_root/.gitignore" <<'EOF'
.build/
.identity-test/
EOF
/bin/cat > "$fixture_root/.pre-astra-packager-test-fixture" <<'EOF'
pre-astra-packager-fixture-v1
EOF
/bin/cat > "$fixture_root/.fleck-build-identity-test-fixture" <<'EOF'
fleck-build-identity-test-fixture-v1
EOF
/bin/cat > "$fixture_root/.fleck-development-packager-test-fixture" <<'EOF'
fleck-development-packager-test-fixture-v1
EOF
/bin/cat > "$fixture_root/VERSION" <<'EOF'
1.0.0-beta.1
EOF
/bin/cat > "$fixture_root/CHANGELOG.md" <<'EOF'
# Changelog

## [1.0.0-beta.1] - 2026-09-11
EOF
/bin/cat > "$fixture_root/Sources/FleckApp/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Fleck</string>
  <key>CFBundleIdentifier</key><string>com.harryjin.fleck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
printf '%s\n' 'fixture mark' > "$fixture_root/website/public/fleck-mark.png"
/bin/cat > "$fixture_root/Scripts/build-parakeet-test-app.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly identity_tool="$script_dir/fleck-build-identity.py"
readonly identity_capture="$build_root/.fixture-parakeet-identity.$$.json"
result_file=''
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == '--result-file' ]] || exit 2
  result_file="$2"
fi
if [[ -f "$build_root/fixture-noop-build" ]]; then
  exit 0
fi
identity_nested_arguments=()
if [[ -n "${FLECK_BUILD_IDENTITY_NESTED_TOKEN:-}" ]]; then
  identity_nested_arguments+=(--nested-token "$FLECK_BUILD_IDENTITY_NESTED_TOKEN")
fi
cleanup_identity() {
  exit_code=$?
  trap - EXIT
  if [[ -f "$identity_capture" ]]; then
    "$identity_tool" release --capture "$identity_capture" || exit_code=1
    /bin/rm -f "$identity_capture" || exit_code=1
  fi
  exit "$exit_code"
}
trap cleanup_identity EXIT
"$identity_tool" begin \
  --repo "$repo_root" \
  --flavor parakeet \
  --configuration Debug \
  --capture "$identity_capture" \
  --test-accepted-root "$FLECK_BUILD_IDENTITY_TEST_ACCEPTED_ROOT" \
  --test-database "$FLECK_BUILD_IDENTITY_TEST_DATABASE" \
  "${identity_nested_arguments[@]+"${identity_nested_arguments[@]}"}"
readonly artifact_name="$("$identity_tool" name --capture "$identity_capture")"
readonly app="$build_root/parakeet-test/$artifact_name.app"
version='fresh-checkout-build'
if [[ -f "$build_root/fixture-build-version" ]]; then
  version="$(/bin/cat "$build_root/fixture-build-version")"
fi
[[ ! -e "$app" && ! -L "$app" ]] || exit 1
/bin/mkdir -p \
  "$app/Contents/MacOS" \
  "$app/Contents/SharedSupport" \
  "$app/Contents/Resources"
/bin/cat > "$build_root/fixture-main.c" <<'SOURCE'
int main(void) { return 0; }
SOURCE
/bin/cat > "$build_root/fixture-helper-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
</dict></plist>
PLIST
/bin/cat > "$build_root/fixture-helper-launch-constraint.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>validation-category</key><integer>1</integer>
</dict></plist>
PLIST
/usr/bin/xcrun clang -arch arm64 "$build_root/fixture-main.c" -o "$app/Contents/MacOS/Fleck"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/Fleck"
for helper_name in fleck-agent gemma-cleanup-helper; do
  helper_identifier="com.harryjin.fleck.$helper_name"
  helper_path="$app/Contents/SharedSupport/$helper_name"
  /usr/bin/xcrun clang -arch arm64 "$build_root/fixture-main.c" -o "$helper_path"
  /usr/bin/codesign --force --sign - \
    --identifier "$helper_identifier" \
    --entitlements "$build_root/fixture-helper-entitlements.plist" \
    --launch-constraint-self "$build_root/fixture-helper-launch-constraint.plist" \
    -r "=designated => identifier \"$helper_identifier\"" \
    "$helper_path"
done
/bin/cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>Fleck</string>
  <key>CFBundleExecutable</key><string>Fleck</string>
  <key>CFBundleIdentifier</key><string>com.harryjin.fleck</string>
  <key>CFBundleName</key><string>Fleck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
"$identity_tool" stamp --capture "$identity_capture" --plist "$app/Contents/Info.plist"
printf '%s\n' "$version" > "$app/Contents/Resources/fixture-build-version.txt"
if [[ -f "$build_root/fixture-with-weight" ]]; then
  /usr/bin/touch "$app/Contents/Resources/forbidden.onnx"
fi
if [[ -f "$build_root/fixture-wrong-requirement" ]]; then
  /usr/bin/codesign --force --sign - -r '=designated => true' "$app"
else
  /usr/bin/codesign --force --sign - \
    -r '=designated => identifier "com.harryjin.fleck"' "$app"
fi
"$identity_tool" finish --capture "$identity_capture" --plist "$app/Contents/Info.plist"
if [[ -n "$result_file" && ! -f "$build_root/fixture-no-result" ]]; then
  "$identity_tool" write-result \
    --capture "$identity_capture" --app "$app" --result-file "$result_file"
  if [[ -f "$build_root/fixture-result-wrong-build-id" ]]; then
    /usr/bin/plutil -replace buildID -string 00000000-0000-4000-8000-000000000000 \
      "$result_file"
  fi
fi
EOF
/bin/chmod 755 \
  "$fixture_root/Scripts/build-fleck-app.sh" \
  "$fixture_root/Scripts/build-parakeet-test-app.sh" \
  "$fixture_root/Scripts/fleck-build-identity.py"

(
  cd -- "$fixture_root"
  /usr/bin/git init -q
  /usr/bin/git config user.email fixture@example.invalid
  /usr/bin/git config user.name 'Fleck packaging fixture'
  /usr/bin/git add .
  /usr/bin/git commit -qm 'Create accepted Fleck packaging fixture base'
)

readonly fixture_accepted_commit="$(/usr/bin/git -C "$fixture_root" rev-parse HEAD)"
readonly fixture_accepted_tree="$(/usr/bin/git -C "$fixture_root" rev-parse 'HEAD^{tree}')"
readonly fixture_accepted_root="$fixture_root/.identity-test/accepted"
readonly fixture_identity_database="$fixture_root/.identity-test/build-metadata/identities.sqlite3"
/bin/mkdir -p "$fixture_accepted_root"
/bin/cat > "$fixture_accepted_root/check-accepted-build.py" <<'EOF'
#!/usr/bin/env python3
import sys
sys.exit(0)
EOF
/bin/chmod 755 "$fixture_accepted_root/check-accepted-build.py"
readonly fixture_validator_hash="$(
  /usr/bin/shasum -a 256 "$fixture_accepted_root/check-accepted-build.py" \
    | /usr/bin/awk '{print $1}'
)"
readonly fixture_validator_size="$(
  /usr/bin/stat -f '%z' "$fixture_accepted_root/check-accepted-build.py"
)"
/usr/bin/python3 - "$fixture_accepted_root/manifest.json" \
  "$fixture_accepted_commit" "$fixture_accepted_tree" \
  "$fixture_validator_hash" "$fixture_validator_size" <<'PY'
import json
import sys
path, commit, tree, validator_hash, validator_size = sys.argv[1:]
manifest = {
    "schemaVersion": 1,
    "registryStatus": "active",
    "latestAcceptedRecordID": "fixture-accepted",
    "records": [{
        "id": "fixture-accepted",
        "status": "latestAccepted",
        "source": {"commit": commit, "tree": tree},
    }],
    "supportFiles": [{
        "relativePath": "check-accepted-build.py",
        "sha256": validator_hash,
        "size": int(validator_size),
    }],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
readonly fixture_manifest_hash="$(
  /usr/bin/shasum -a 256 "$fixture_accepted_root/manifest.json" | /usr/bin/awk '{print $1}'
)"
printf '%s  manifest.json\n' "$fixture_manifest_hash" \
  > "$fixture_accepted_root/manifest.sha256"
/usr/bin/python3 - "$fixture_root/BuildBaseline.json" "$fixture_manifest_hash" \
  "$fixture_accepted_commit" "$fixture_accepted_tree" <<'PY'
import json
import sys
path, digest, commit, tree = sys.argv[1:]
baseline = {
    "schemaVersion": 1,
    "canonicalManifestSHA256": digest,
    "selectedRecordID": "fixture-accepted",
    "acceptedSourceCommit": commit,
    "acceptedSourceTree": tree,
    "requiredRegistryStatus": "active",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(baseline, handle, indent=2)
    handle.write("\n")
PY
(
  cd -- "$fixture_root"
  /usr/bin/git add BuildBaseline.json
  /usr/bin/git commit -qm 'Pin accepted Fleck packaging fixture baseline'
)
export FLECK_BUILD_IDENTITY_TEST_ACCEPTED_ROOT="$fixture_accepted_root"
export FLECK_BUILD_IDENTITY_TEST_DATABASE="$fixture_identity_database"
export FLECK_BUILD_IDENTITY_TEST_FIXTURE=1
export FLECK_BUILD_IDENTITY_MODE=local

if [[ -z "$test_only" || "$test_only" == 'first-run' ]]; then
  /bin/mkdir "$test_root/unsafe-build-target"
  /bin/ln -s "$test_root/unsafe-build-target" "$fixture_root/.build"
  if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/build-symlink.out" 2>"$test_root/build-symlink.err"; then
    printf '%s\n' 'FAIL: packager accepted a symlinked build root' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'build root is not a canonical directory' "$test_root/build-symlink.err"
  /usr/bin/find "$fixture_root/.build" -maxdepth 0 -type l -delete

  /usr/bin/touch "$fixture_root/.build"
  if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/build-file.out" 2>"$test_root/build-file.err"; then
    printf '%s\n' 'FAIL: packager accepted a non-directory build root' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'build root is not a canonical directory' "$test_root/build-file.err"
  /usr/bin/find "$fixture_root/.build" -maxdepth 0 -type f -delete

  test ! -e "$fixture_root/.build"
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" >/dev/null
  first_run_input="$(/usr/bin/find "$fixture_root/.build/parakeet-test" -maxdepth 1 -type d -name 'Fleck *.app' -print -quit)"
  test "$(/bin/cat "$first_run_input/Contents/Resources/fixture-build-version.txt")" = \
    'fresh-checkout-build'
  if [[ "$test_only" == 'first-run' ]]; then
    exit 0
  fi
fi

if [[ -z "$test_only" ]]; then
development_tools="$test_root/development-tools"
/bin/mkdir "$development_tools"
/bin/cat > "$development_tools/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == '-p' ]]
printf '%s\n' '/Applications/Xcode.app/Contents/Developer'
EOF
/bin/cat > "$development_tools/xcodebuild" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == '-version' ]]
printf '%s\n' 'Xcode fixture'
EOF
/bin/cat > "$development_tools/xcrun" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == '--find' && "$2" == 'swift' ]]
printf '%s\n' '/usr/bin/swift'
EOF
/bin/cat > "$development_tools/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == 'build' ]]
product=''
while (( $# > 0 )); do
  if [[ "$1" == '--product' ]]; then
    product="$2"
    break
  fi
  shift
done
[[ "$product" == 'Fleck' || "$product" == 'fleck-agent' ]]
/bin/mkdir -p "$PWD/.build/release"
/bin/cp /bin/echo "$PWD/.build/release/$product"
EOF
/bin/chmod 755 "$development_tools"/*
readonly development_result="$fixture_root/.build/development-replaced-result.json"
if /usr/bin/env \
  PATH="$development_tools:/usr/bin:/bin" \
  TMPDIR="$test_root" \
  CI=true \
  GITHUB_ACTIONS=true \
  FLECK_BUILD_IDENTITY_MODE=ci-unverified \
  FLECK_DEVELOPMENT_TEST_REPLACE_AFTER_PUBLICATION=1 \
  "$fixture_root/Scripts/build-fleck-app.sh" --result-file "$development_result" \
  >"$test_root/development-replaced.out" 2>"$test_root/development-replaced.err"; then
  printf '%s\n' 'FAIL: development publication replacement failpoint did not stop the build' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected failure after development publication replacement' \
  "$test_root/development-replaced.err"
test ! -e "$development_result"
development_replacement=''
for candidate in "$fixture_root/.build"/Fleck\ *\ Build\ *.app; do
  if [[ -f "$candidate/sentinel" \
    && "$(/bin/cat "$candidate/sentinel")" == 'replacement sentinel' ]]; then
    development_replacement="$candidate"
  fi
done
test -n "$development_replacement"
test -d "$fixture_root/.build/.development-owned-publication."*
fi

tree_manifest() {
  local root="$1"
  (
    cd -- "$root"
    /usr/bin/find . -print | LC_ALL=C /usr/bin/sort | while IFS= read -r relative; do
      if [[ -d "$relative" ]]; then
        printf 'd\t%s\t%s\n' "$(/usr/bin/stat -f '%Lp' "$relative")" "$relative"
      elif [[ -f "$relative" ]]; then
        printf 'f\t%s\t%s\t%s\n' \
          "$(/usr/bin/stat -f '%Lp' "$relative")" \
          "$(/usr/bin/shasum -a 256 "$relative" | /usr/bin/awk '{print $1}')" \
          "$relative"
      else
        printf 'unsafe\t%s\n' "$relative"
      fi
    done
  )
}

signature_requirement() {
  /usr/bin/codesign -d -r- "$1" 2>&1 \
    | /usr/bin/sed -n 's/^designated => /designated => /p'
}

signature_entitlements() {
  /usr/bin/codesign -d --entitlements - "$1" 2>/dev/null
}

if [[ "$test_only" == 'launcher' ]]; then
  readonly launcher_result="$fixture_root/.build/launcher-result.json"
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    --result-file "$launcher_result" >/dev/null
  readonly packaged_launcher_app="$(/usr/bin/plutil -extract appPath raw -o - "$launcher_result")"
  readonly launcher_handoff="${packaged_launcher_app%/*}"
  launcher_label="${packaged_launcher_app##*/}"
  launcher_label="${launcher_label%.app}"
  readonly launcher_label
  readonly generated_launcher="$launcher_handoff/Launch $launcher_label.command"
  readonly runtime_handoff="$test_root/runtime/$launcher_label"
  readonly runtime_app="$runtime_handoff/$launcher_label.app"
  readonly runtime_launcher="$runtime_handoff/Launch $launcher_label.command"
  /bin/mkdir -p "$runtime_handoff"
  /usr/bin/ditto --norsrc "$packaged_launcher_app" "$runtime_app"
  readonly canonical_runtime_app="$(cd -- "$runtime_app" && pwd -P)"
  readonly process_state="$test_root/process-state.tsv"
  readonly inventory_count="$test_root/inventory-count"
  readonly kill_log="$test_root/kill.log"
  readonly open_log="$test_root/open.log"
  readonly sleep_log="$test_root/sleep.log"
  readonly ps_stub="$test_root/ps-stub.sh"
  readonly kill_stub="$test_root/kill-stub.sh"
  readonly open_stub="$test_root/open-stub.sh"
  readonly sleep_stub="$test_root/sleep-stub.sh"
  /bin/cat > "$ps_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == '-x -o pid=,comm=' ]]; then
  count=0
  if [[ -f "$FLECK_PRE_ASTRA_TEST_INVENTORY_COUNT" ]]; then
    count="$(/bin/cat "$FLECK_PRE_ASTRA_TEST_INVENTORY_COUNT")"
  fi
  (( count += 1 ))
  printf '%s\n' "$count" > "$FLECK_PRE_ASTRA_TEST_INVENTORY_COUNT"
  if [[ -n "${FLECK_PRE_ASTRA_TEST_FAIL_INVENTORY:-}" ]]; then
    exit 71
  fi
  if [[ "${FLECK_PRE_ASTRA_TEST_LATE_MODE:-}" == 'one' && "$count" == '2' ]]; then
    printf '%s\n' \
      $'107\t/Applications/Fleck Late.app/Contents/MacOS/Fleck\t/Applications/Fleck Late.app/Contents/MacOS/Fleck\talive' \
      >> "$FLECK_PRE_ASTRA_TEST_PROCESS_STATE"
  elif [[ "${FLECK_PRE_ASTRA_TEST_LATE_MODE:-}" == 'continuous' \
    && ( "$count" == '2' || "$count" == '3' ) ]]; then
    printf '%s\t/Applications/Fleck Late %s.app/Contents/MacOS/Fleck\tlate\talive\n' \
      "$((200 + count))" "$count" >> "$FLECK_PRE_ASTRA_TEST_PROCESS_STATE"
  fi
  /usr/bin/awk -F '\t' '$4 == "alive" { printf "%5s %s\n", $1, $2 }' \
    "$FLECK_PRE_ASTRA_TEST_PROCESS_STATE"
  exit 0
fi
if [[ "$1" == '-p' && "$3" == '-o' && "$4" == 'comm=' ]]; then
  /usr/bin/awk -F '\t' -v pid="$2" '$1 == pid && $4 == "alive" { print $2 }' \
    "$FLECK_PRE_ASTRA_TEST_PROCESS_STATE"
  exit 0
fi
exit 2
EOF
  /bin/cat > "$kill_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == '-TERM' && "$2" =~ ^[0-9]+$ ]]
printf '%s\n' "$2" >> "$FLECK_PRE_ASTRA_TEST_KILL_LOG"
if [[ "$2" == "${FLECK_PRE_ASTRA_TEST_STUBBORN_PID:-}" ]]; then
  exit 0
fi
readonly replacement="$FLECK_PRE_ASTRA_TEST_PROCESS_STATE.new"
/usr/bin/awk -F '\t' -v OFS='\t' -v pid="$2" '$1 == pid { $4 = "dead" } { print }' \
  "$FLECK_PRE_ASTRA_TEST_PROCESS_STATE" > "$replacement"
/bin/mv "$replacement" "$FLECK_PRE_ASTRA_TEST_PROCESS_STATE"
EOF
  /bin/cat > "$open_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$FLECK_PRE_ASTRA_TEST_OPEN_LOG"
EOF
  /bin/cat > "$sleep_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FLECK_PRE_ASTRA_TEST_SLEEP_LOG"
EOF
  /bin/chmod 755 "$ps_stub" "$kill_stub" "$open_stub" "$sleep_stub"
  /usr/bin/sed \
    -e 's#/bin/ps#"$FLECK_PRE_ASTRA_TEST_PS"#g' \
    -e 's#/bin/kill#"$FLECK_PRE_ASTRA_TEST_KILL"#g' \
    -e 's#/bin/sleep#"$FLECK_PRE_ASTRA_TEST_SLEEP"#g' \
    -e 's#/usr/bin/open#"$FLECK_PRE_ASTRA_TEST_OPEN"#g' \
    "$generated_launcher" > "$runtime_launcher"
  /bin/chmod 755 "$runtime_launcher"

  run_test_launcher() {
    /usr/bin/env \
      TMPDIR="$test_root" \
      FLECK_PRE_ASTRA_TEST_PS="$ps_stub" \
      FLECK_PRE_ASTRA_TEST_KILL="$kill_stub" \
      FLECK_PRE_ASTRA_TEST_SLEEP="$sleep_stub" \
      FLECK_PRE_ASTRA_TEST_OPEN="$open_stub" \
      FLECK_PRE_ASTRA_TEST_PROCESS_STATE="$process_state" \
      FLECK_PRE_ASTRA_TEST_INVENTORY_COUNT="$inventory_count" \
      FLECK_PRE_ASTRA_TEST_KILL_LOG="$kill_log" \
      FLECK_PRE_ASTRA_TEST_SLEEP_LOG="$sleep_log" \
      FLECK_PRE_ASTRA_TEST_OPEN_LOG="$open_log" \
      "$@" "$runtime_launcher"
  }

  if [[ "$launcher_case" == 'all' || "$launcher_case" == 'open' ]]; then
    /bin/cat > "$process_state" <<EOF
101	/Applications/Fleck.app/Contents/MacOS/Fleck	/Applications/Fleck.app/Contents/MacOS/Fleck	alive
102	$canonical_runtime_app/Contents/MacOS/Fleck	$canonical_runtime_app/Contents/MacOS/Fleck	alive
103	/Applications/Fleck.app/Contents/SharedSupport/fleck-agent	/Applications/Fleck.app/Contents/SharedSupport/fleck-agent	alive
104	/Applications/Fleck.app/Contents/SharedSupport/gemma-cleanup-helper	/Applications/Fleck.app/Contents/SharedSupport/gemma-cleanup-helper	alive
105	/bin/sh	/bin/sh -c while-running Fleck.app/Contents/MacOS/Fleck	alive
106	/Applications/Notes.app/Contents/MacOS/Fleck	/Applications/Notes.app/Contents/MacOS/Fleck	alive
108	/tmp/Fleck Archive/Notes.app/Contents/MacOS/Fleck	/tmp/Fleck Archive/Notes.app/Contents/MacOS/Fleck	alive
EOF
    run_test_launcher

    test "$(/usr/bin/awk -F '\t' '$1 == 101 { print $4 }' "$process_state")" = 'dead'
    if [[ "$(/usr/bin/awk -F '\t' '$1 == 108 { print $4 }' "$process_state")" != 'alive' ]]; then
      printf '%s\n' 'FAIL: launcher terminated an unrelated app nested below a Fleck-named directory' >&2
      exit 1
    fi
    test "$(/usr/bin/awk -F '\t' '$1 != 101 { print $4 }' "$process_state" | /usr/bin/sort -u)" = 'alive'
    test "$(/bin/cat "$kill_log")" = '101'
    if [[ "$(/bin/cat "$open_log")" != "$canonical_runtime_app" ]]; then
      printf '%s\n' 'FAIL: launcher did not use normal path-based open for the adjacent app' >&2
      exit 1
    fi
    if [[ "$launcher_case" == 'open' ]]; then
      printf '%s\n' 'PASS: launcher uses normal path-based open for the adjacent app'
      exit 0
    fi
  fi

  if [[ "$launcher_case" == 'all' || "$launcher_case" == 'inventory' ]]; then
    printf '102\t%s/Contents/MacOS/Fleck\tintended\talive\n' \
      "$canonical_runtime_app" > "$process_state"
    /usr/bin/find "$inventory_count" "$kill_log" "$open_log" "$sleep_log" \
      -maxdepth 0 -type f -delete 2>/dev/null || true
    if run_test_launcher FLECK_PRE_ASTRA_TEST_FAIL_INVENTORY=1 \
      >"$test_root/inventory.out" 2>"$test_root/inventory.err"; then
      printf '%s\n' 'FAIL: launcher opened the app after process inventory failed' >&2
      exit 1
    fi
    /usr/bin/grep -Fq 'could not inspect running Fleck app processes' "$test_root/inventory.err"
    test ! -e "$open_log"
    test -z "$(/usr/bin/find "$test_root" -maxdepth 1 -name 'fleck-corrected-launch.*' -print -quit)"
    if [[ "$launcher_case" == 'inventory' ]]; then
      printf '%s\n' 'PASS: launcher fails closed when process inventory fails'
      exit 0
    fi
  fi

  if [[ "$launcher_case" == 'all' || "$launcher_case" == 'late' ]]; then
    printf '102\t%s/Contents/MacOS/Fleck\tintended\talive\n' \
      "$canonical_runtime_app" > "$process_state"
    /usr/bin/find "$inventory_count" "$kill_log" "$open_log" "$sleep_log" \
      -maxdepth 0 -type f -delete 2>/dev/null || true
    run_test_launcher FLECK_PRE_ASTRA_TEST_LATE_MODE=one
    if [[ "$(/usr/bin/awk -F '\t' '$1 == 107 { print $4 }' "$process_state")" != 'dead' ]]; then
      printf '%s\n' 'FAIL: launcher did not retire a late-arriving Fleck GUI process' >&2
      exit 1
    fi
    test "$(/bin/cat "$kill_log")" = '107'
    test "$(/bin/cat "$inventory_count")" = '3'
    test "$(/bin/cat "$open_log")" = "$canonical_runtime_app"
    if [[ "$launcher_case" == 'late' ]]; then
      printf '%s\n' 'PASS: launcher retires a conflict that appears during launch preparation'
      exit 0
    fi
  fi

  if [[ "$launcher_case" == 'all' || "$launcher_case" == 'bounded' ]]; then
    printf '102\t%s/Contents/MacOS/Fleck\tintended\talive\n' \
      "$canonical_runtime_app" > "$process_state"
    /usr/bin/find "$inventory_count" "$kill_log" "$open_log" "$sleep_log" \
      -maxdepth 0 -type f -delete 2>/dev/null || true
    if run_test_launcher FLECK_PRE_ASTRA_TEST_LATE_MODE=continuous \
      >"$test_root/bounded.out" 2>"$test_root/bounded.err"; then
      printf '%s\n' 'FAIL: launcher opened while conflicts kept appearing' >&2
      exit 1
    fi
    /usr/bin/grep -Fq 'a conflicting Fleck app appeared during final launch verification' \
      "$test_root/bounded.err"
    test "$(/bin/cat "$inventory_count")" = '3'
    test ! -e "$open_log"
    if [[ "$launcher_case" == 'bounded' ]]; then
      printf '%s\n' 'PASS: launcher bounds retries and fails closed when conflicts keep appearing'
      exit 0
    fi
  fi

  /bin/cat > "$process_state" <<EOF
102	$canonical_runtime_app/Contents/MacOS/Fleck	$canonical_runtime_app/Contents/MacOS/Fleck	alive
201	/Applications/Fleck Old.app/Contents/MacOS/Fleck	/Applications/Fleck Old.app/Contents/MacOS/Fleck	alive
EOF
  /usr/bin/find "$inventory_count" "$kill_log" "$open_log" "$sleep_log" \
    -maxdepth 0 -type f -delete 2>/dev/null || true
  if run_test_launcher FLECK_PRE_ASTRA_TEST_STUBBORN_PID=201 \
    >"$test_root/stubborn.out" 2>"$test_root/stubborn.err"; then
    printf '%s\n' 'FAIL: launcher opened the app while a conflicting Fleck GUI process remained' >&2
    exit 1
  fi
  /usr/bin/grep -Fq \
    'conflicting Fleck app did not exit after TERM: /Applications/Fleck Old.app/Contents/MacOS/Fleck (pid 201); quit it manually and rerun this launcher' \
    "$test_root/stubborn.err"
  test "$(/usr/bin/wc -l < "$sleep_log" | /usr/bin/tr -d ' ')" = '20'
  test ! -e "$open_log"
  printf '%s\n' 'PASS: launcher retires only foreign Fleck GUI processes before opening the adjacent app'
  exit 0
fi

result_app() {
  /usr/bin/plutil -extract appPath raw -o - "$1"
}

input_app_for_id() {
  local expected="$1"
  local candidate
  for candidate in "$fixture_root/.build/parakeet-test"/Fleck\ *.app; do
    [[ -d "$candidate" ]] || continue
    if [[ "$(/usr/bin/plutil -extract FleckBuildID raw -o - "$candidate/Contents/Info.plist")" == "$expected" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

input_app_for_version() {
  local expected="$1"
  local candidate
  for candidate in "$fixture_root/.build/parakeet-test"/Fleck\ *.app; do
    [[ -d "$candidate" ]] || continue
    if [[ "$(/bin/cat "$candidate/Contents/Resources/fixture-build-version.txt" 2>/dev/null || true)" == "$expected" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ "$test_only" == 'requirement' ]]; then
  /usr/bin/touch "$fixture_root/.build/fixture-wrong-requirement"
  printf '%s\n' 'wrong-requirement-build' > "$fixture_root/.build/fixture-build-version"
  readonly requirement_result="$fixture_root/.build/requirement-result.json"
  if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    --result-file "$requirement_result" \
    >"$test_root/requirement.out" 2>"$test_root/requirement.err"; then
    printf '%s\n' 'FAIL: packager accepted a mismatched designated requirement' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'unexpected designated requirement' "$test_root/requirement.err"
  test ! -e "$requirement_result"
  test -z "$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -type d -name 'Fleck * Build *' -print -quit)"
  exit 0
fi

if [[ "$test_only" == 'manifest' ]]; then
  printf '%s\n' 'manifest-build' > "$fixture_root/.build/fixture-build-version"
  readonly manifest_result="$fixture_root/.build/manifest-result.json"
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    --result-file "$manifest_result" >/dev/null
  readonly manifest_app="$(result_app "$manifest_result")"
  readonly manifest_handoff="${manifest_app%/*}"
  readonly published_input_manifest="$manifest_handoff/INPUT-APP-MANIFEST.sha256.tsv"
  readonly input_build_id="$(/usr/bin/plutil -extract FleckInputBuildID raw -o - \
    "$manifest_app/Contents/Info.plist")"
  readonly input_app="$(input_app_for_id "$input_build_id")"
  readonly expected_input_manifest="$test_root/expected-input.manifest"
  tree_manifest "$input_app" > "$expected_input_manifest"
  /usr/bin/cmp -s "$expected_input_manifest" "$published_input_manifest"
  readonly published_input_manifest_hash="$(/usr/bin/shasum -a 256 \
    "$published_input_manifest" | /usr/bin/awk '{print $1}')"
  test "$(/usr/bin/plutil -extract FleckInputManifestSHA256 raw -o - \
    "$manifest_app/Contents/Info.plist")" = "$published_input_manifest_hash"
  /usr/bin/grep -Fq "Input app manifest SHA-256: $published_input_manifest_hash" \
    "$manifest_handoff/BUILD-PROVENANCE.txt"
  exit 0
fi

if [[ "$test_only" == 'after-final-source' || "$test_only" == 'after-swap' \
  || "$test_only" == 'legacy-zip' || "$test_only" == 'publication' ]]; then
  printf '%s\n' 'transaction-baseline' > "$fixture_root/.build/fixture-build-version"
  readonly baseline_result="$fixture_root/.build/transaction-baseline-result.json"
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    --result-file "$baseline_result" >/dev/null
  readonly baseline_app="$(result_app "$baseline_result")"
  readonly baseline_handoff="${baseline_app%/*}"
  readonly baseline_build_id="$(/usr/bin/plutil -extract FleckInputBuildID raw -o - \
    "$baseline_app/Contents/Info.plist")"
  readonly baseline_input_app="$(input_app_for_id "$baseline_build_id")"
  readonly baseline_publication_before="$(tree_manifest "$baseline_handoff")"
  readonly baseline_input_before="$(tree_manifest "$baseline_input_app")"
  readonly corrected_count_before="$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 \
    -type d -name 'Fleck * Build *' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  readonly parakeet_count_before="$(/usr/bin/find "$fixture_root/.build/parakeet-test" \
    -maxdepth 1 -type d -name 'Fleck *.app' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

  readonly transaction_legacy_zip="$fixture_root/.build/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
  readonly expected_legacy_zip="$test_root/expected-legacy.zip"
  if [[ "$test_only" == 'legacy-zip' ]]; then
    printf '%s\n' 'legacy-zip-sentinel' > "$transaction_legacy_zip"
    /bin/cp -p "$transaction_legacy_zip" "$expected_legacy_zip"
  fi

  printf '%s\n' 'transaction-replacement' > "$fixture_root/.build/fixture-build-version"
  case "$test_only" in
    after-final-source)
      failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK'
      expected_failure='injected failure after final source check'
      ;;
    after-swap)
      failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP'
      expected_failure='injected failure after publication swap'
      ;;
    legacy-zip)
      failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP'
      expected_failure='injected failure after legacy ZIP backup'
      ;;
    publication)
      failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP'
      expected_failure='injected publication failure after publication backup'
      ;;
  esac
  readonly transaction_result="$fixture_root/.build/transaction-failure-result.json"
  if /usr/bin/env "$failpoint_name=1" \
    "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    --result-file "$transaction_result" \
    >"$test_root/transaction.out" 2>"$test_root/transaction.err"; then
    printf 'FAIL: %s did not stop the operation\n' "$failpoint_name" >&2
    exit 1
  fi
  /usr/bin/grep -Fq "$expected_failure" "$test_root/transaction.err"
  test ! -e "$transaction_result"
  test "$baseline_publication_before" = "$(tree_manifest "$baseline_handoff")"
  test "$baseline_input_before" = "$(tree_manifest "$baseline_input_app")"
  test "$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -type d \
    -name 'Fleck * Build *' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" \
    -eq "$corrected_count_before"
  test "$(/usr/bin/find "$fixture_root/.build/parakeet-test" -maxdepth 1 -type d \
    -name 'Fleck *.app' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" \
    -eq "$((parakeet_count_before + 1))"
  readonly replacement_input="$(input_app_for_version 'transaction-replacement')"
  test -d "$replacement_input"
  test "$(/bin/cat "$replacement_input/Contents/Resources/fixture-build-version.txt")" = \
    'transaction-replacement'
  if [[ "$test_only" == 'legacy-zip' ]]; then
    /usr/bin/cmp -s "$expected_legacy_zip" "$transaction_legacy_zip"
  fi
  exit 0
fi

if [[ -z "$test_only" || "$test_only" == 'lock-owner' ]]; then
  if FLECK_PRE_ASTRA_TEST_FAIL_LOCK_OWNER_WRITE=1 \
    "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/lock-owner.out" 2>"$test_root/lock-owner.err"; then
    printf '%s\n' 'FAIL: lock-owner failpoint did not stop the operation' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'injected lock-owner creation failure' "$test_root/lock-owner.err"
  test ! -e "$fixture_root/.build/.corrected-packaging.lock"
  if [[ "$test_only" == 'lock-owner' ]]; then
    exit 0
  fi
fi

readonly legacy_publication="$fixture_root/.build/pre-astra-corrected"
readonly legacy_zip="$fixture_root/.build/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
/bin/mkdir -p "$legacy_publication"
printf '%s\n' 'legacy-publication-sentinel' > "$legacy_publication/sentinel"
printf '%s\n' 'legacy-zip-sentinel' > "$legacy_zip"
readonly legacy_publication_before="$(tree_manifest "$legacy_publication")"
readonly legacy_zip_before="$(/usr/bin/shasum -a 256 "$legacy_zip" | /usr/bin/awk '{print $1}')"

printf '%s\n' 'stale-build' > "$fixture_root/.build/fixture-build-version"
"$fixture_root/Scripts/build-parakeet-test-app.sh" >/dev/null
stale_input="$(input_app_for_version 'stale-build')"
readonly stale_input
readonly stale_input_before="$(tree_manifest "$stale_input")"
/usr/bin/touch "$fixture_root/.build/fixture-noop-build"
readonly missing_child_result="$fixture_root/.build/missing-child-result.json"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$missing_child_result" \
  >"$test_root/stale.out" 2>"$test_root/stale.err"; then
  printf '%s\n' 'FAIL: corrected packager accepted child success without a result' >&2
  exit 1
fi
/usr/bin/grep -Fq 'succeeded without an immutable result' "$test_root/stale.err"
test ! -e "$missing_child_result"
test "$stale_input_before" = "$(tree_manifest "$stale_input")"
/usr/bin/find "$fixture_root/.build/fixture-noop-build" -maxdepth 0 -type f -delete

printf '%s\n' 'mismatched-result-build' > "$fixture_root/.build/fixture-build-version"
/usr/bin/touch "$fixture_root/.build/fixture-result-wrong-build-id"
readonly mismatched_result="$fixture_root/.build/mismatched-result.json"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$mismatched_result" \
  >"$test_root/mismatch.out" 2>"$test_root/mismatch.err"; then
  printf '%s\n' 'FAIL: corrected packager accepted a child result/plist UUID mismatch' >&2
  exit 1
fi
/usr/bin/grep -Fq 'result build ID does not match' "$test_root/mismatch.err"
test ! -e "$mismatched_result"
/usr/bin/find "$fixture_root/.build/fixture-result-wrong-build-id" -maxdepth 0 -type f -delete

printf '%s\n' 'fresh-build-1' > "$fixture_root/.build/fixture-build-version"
readonly first_result="$fixture_root/.build/corrected-result-1.json"
"$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$first_result" >/dev/null
readonly first_app="$(result_app "$first_result")"
readonly first_handoff="${first_app%/*}"
first_label="${first_app##*/}"
first_label="${first_label%.app}"
readonly first_label
readonly first_launcher="$first_handoff/Launch $first_label.command"
readonly first_receipt="$first_handoff/BUILD-PROVENANCE.txt"
readonly first_input_manifest="$first_handoff/INPUT-APP-MANIFEST.sha256.tsv"
readonly first_zip="$first_handoff/$first_label-arm64.zip"
for required in "$first_app" "$first_launcher" "$first_receipt" "$first_input_manifest" "$first_zip"; do
  test -e "$required"
done
test -x "$first_launcher"
test "${first_handoff%/*}" = "$fixture_root/.build"
test "$first_label" = "$(/usr/bin/plutil -extract CFBundleName raw -o - "$first_app/Contents/Info.plist")"
test "$first_label" = "$(/usr/bin/plutil -extract CFBundleDisplayName raw -o - "$first_app/Contents/Info.plist")"
test "$first_label" = "$(/usr/bin/plutil -extract FleckBuildLabel raw -o - "$first_app/Contents/Info.plist")"
test "$(/bin/cat "$first_app/Contents/Resources/fixture-build-version.txt")" = 'fresh-build-1'
readonly first_build_id="$(/usr/bin/plutil -extract FleckBuildID raw -o - "$first_app/Contents/Info.plist")"
readonly first_result_id="$(/usr/bin/plutil -extract buildID raw -o - "$first_result")"
readonly first_input_build_id="$(/usr/bin/plutil -extract FleckInputBuildID raw -o - "$first_app/Contents/Info.plist")"
test "$first_build_id" = "$first_result_id"
test "$first_build_id" != "$first_input_build_id"
readonly first_input_app="$(input_app_for_id "$first_input_build_id")"
readonly expected_input_manifest="$test_root/expected-input.manifest"
tree_manifest "$first_input_app" > "$expected_input_manifest"
/usr/bin/cmp -s "$expected_input_manifest" "$first_input_manifest"
readonly input_manifest_hash="$(/usr/bin/shasum -a 256 "$first_input_manifest" | /usr/bin/awk '{print $1}')"
test "$(/usr/bin/plutil -extract FleckInputManifestSHA256 raw -o - "$first_app/Contents/Info.plist")" = "$input_manifest_hash"
/usr/bin/grep -Fq "Build label: $first_label" "$first_receipt"
/usr/bin/grep -Fq "Input build ID: $first_input_build_id" "$first_receipt"
if /usr/bin/grep -Fq 'Pre-Astra' "$first_receipt" "$first_launcher"; then
  printf '%s\n' 'FAIL: new corrected output contains a retired Pre-Astra label' >&2
  exit 1
fi
/usr/bin/grep -Fq 'exec /usr/bin/open "$app_path"' "$first_launcher"
/usr/bin/codesign --verify --deep --strict "$first_app"
test "$(signature_requirement "$first_app")" = 'designated => identifier "com.harryjin.fleck"'
for helper_name in fleck-agent gemma-cleanup-helper; do
  input_helper="$first_input_app/Contents/SharedSupport/$helper_name"
  corrected_helper="$first_app/Contents/SharedSupport/$helper_name"
  test "$(/usr/bin/shasum -a 256 "$corrected_helper" | /usr/bin/awk '{print $1}')" = \
    "$(/usr/bin/shasum -a 256 "$input_helper" | /usr/bin/awk '{print $1}')"
  /usr/bin/codesign -d --verbose=5 "$input_helper" 2>&1 \
    | /usr/bin/grep -F 'Has Self Launch Constraints' >/dev/null
  /usr/bin/codesign -d --verbose=5 "$corrected_helper" 2>&1 \
    | /usr/bin/grep -F 'Has Self Launch Constraints' >/dev/null
  test "$(signature_requirement "$corrected_helper")" = "$(signature_requirement "$input_helper")"
  test "$(signature_entitlements "$corrected_helper")" = "$(signature_entitlements "$input_helper")"
done

if /usr/bin/unzip -Z1 "$first_zip" | /usr/bin/grep -Eq '(^|/)__MACOSX(/|$)'; then
  printf '%s\n' 'FAIL: ZIP contains an unexpected __MACOSX entry' >&2
  exit 1
fi
test "$(/usr/bin/unzip -Z1 "$first_zip" | /usr/bin/sed -n 's#/.*##p' | LC_ALL=C /usr/bin/sort -u)" = "$first_label"
readonly extract_root="$test_root/extracted"
/bin/mkdir "$extract_root"
/usr/bin/ditto -x -k "$first_zip" "$extract_root"
readonly extracted_handoff="$extract_root/$first_label"
test "$(tree_manifest "$first_app")" = "$(tree_manifest "$extracted_handoff/$first_label.app")"
for relative in "Launch $first_label.command" BUILD-PROVENANCE.txt INPUT-APP-MANIFEST.sha256.tsv; do
  /usr/bin/cmp -s "$first_handoff/$relative" "$extracted_handoff/$relative"
done

readonly first_publication_before="$(tree_manifest "$first_handoff")"
readonly first_input_before="$(tree_manifest "$first_input_app")"
printf '%s\n' 'let untrackedBuildInput = true' > "$fixture_root/UntrackedBuildInput.swift"
readonly untracked_result="$fixture_root/.build/untracked-result.json"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$untracked_result" \
  >"$test_root/untracked.out" 2>"$test_root/untracked.err"; then
  printf '%s\n' 'FAIL: packager accepted an untracked build-relevant source file' >&2
  exit 1
fi
/usr/bin/grep -Fq 'untracked files or dirty submodules are present' "$test_root/untracked.err"
test ! -e "$untracked_result"
test "$first_input_before" = "$(tree_manifest "$first_input_app")"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"
/usr/bin/find "$fixture_root/UntrackedBuildInput.swift" -maxdepth 0 -type f -delete

/usr/bin/touch "$fixture_root/.build/fixture-wrong-requirement"
printf '%s\n' 'wrong-requirement-build' > "$fixture_root/.build/fixture-build-version"
readonly requirement_result="$fixture_root/.build/requirement-result.json"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$requirement_result" \
  >"$test_root/requirement.out" 2>"$test_root/requirement.err"; then
  printf '%s\n' 'FAIL: packager accepted a mismatched designated requirement' >&2
  exit 1
fi
/usr/bin/grep -Fq 'unexpected designated requirement' "$test_root/requirement.err"
test ! -e "$requirement_result"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"
/usr/bin/find "$fixture_root/.build/fixture-wrong-requirement" -maxdepth 0 -type f -delete

printf '%s\n' 'fresh-build-2' > "$fixture_root/.build/fixture-build-version"
readonly second_result="$fixture_root/.build/corrected-result-2.json"
"$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$second_result" >/dev/null
readonly second_app="$(result_app "$second_result")"
readonly second_handoff="${second_app%/*}"
test "$second_app" != "$first_app"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"
test "$first_input_before" = "$(tree_manifest "$first_input_app")"
test "$(/bin/cat "$second_app/Contents/Resources/fixture-build-version.txt")" = 'fresh-build-2'
test "$(/usr/bin/plutil -extract FleckBuildID raw -o - "$second_app/Contents/Info.plist")" != "$first_build_id"

readonly second_publication_before="$(tree_manifest "$second_handoff")"
readonly parakeet_count_before="$(/usr/bin/find "$fixture_root/.build/parakeet-test" -maxdepth 1 -type d -name 'Fleck *.app' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
printf '%s\n' 'outer-failure-input-survives' > "$fixture_root/.build/fixture-build-version"
readonly failed_outer_result="$fixture_root/.build/failed-outer-result.json"
if FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$failed_outer_result" \
  >"$test_root/outer-failure.out" 2>"$test_root/outer-failure.err"; then
  printf '%s\n' 'FAIL: publication-swap failpoint did not stop the operation' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected failure after publication swap' "$test_root/outer-failure.err"
test ! -e "$failed_outer_result"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"
test "$second_publication_before" = "$(tree_manifest "$second_handoff")"
readonly parakeet_count_after="$(/usr/bin/find "$fixture_root/.build/parakeet-test" -maxdepth 1 -type d -name 'Fleck *.app' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
test "$parakeet_count_after" -eq "$((parakeet_count_before + 1))"

readonly corrected_count_before_late_collision="$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -type d -name 'Fleck * Build *' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
printf '%s\n' 'late-collision-input' > "$fixture_root/.build/fixture-build-version"
readonly late_collision_result="$fixture_root/.build/late-collision-result.json"
if FLECK_PRE_ASTRA_TEST_LATE_PUBLICATION_COLLISION=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$late_collision_result" \
  >"$test_root/late-collision.out" 2>"$test_root/late-collision.err"; then
  printf '%s\n' 'FAIL: late publication collision did not stop the operation' >&2
  exit 1
fi
/usr/bin/grep -Fq 'could not atomically install the verified publication' "$test_root/late-collision.err"
test ! -e "$late_collision_result"
late_collision_handoff=''
for candidate in "$fixture_root/.build"/Fleck\ *\ Build\ *; do
  if [[ -f "$candidate/sentinel" \
    && "$(/bin/cat "$candidate/sentinel")" == 'late collision sentinel' ]]; then
    late_collision_handoff="$candidate"
  fi
done
test -n "$late_collision_handoff"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"
test "$second_publication_before" = "$(tree_manifest "$second_handoff")"
test "$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -type d -name 'Fleck * Build *' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" \
  -eq "$((corrected_count_before_late_collision + 1))"

readonly corrected_count_before_post_result="$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -type d -name 'Fleck * Build *' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
printf '%s\n' 'post-result-failure-input' > "$fixture_root/.build/fixture-build-version"
readonly post_result_failure="$fixture_root/.build/post-result-failure.json"
if FLECK_PRE_ASTRA_TEST_FAIL_AFTER_RESULT=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$post_result_failure" \
  >"$test_root/post-result.out" 2>"$test_root/post-result.err"; then
  printf '%s\n' 'FAIL: post-result failpoint did not stop the operation' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected failure after result publication' "$test_root/post-result.err"
test ! -e "$post_result_failure"
test "$(/usr/bin/find "$fixture_root/.build" -maxdepth 1 -type d -name 'Fleck * Build *' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" \
  -eq "$corrected_count_before_post_result"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"
test "$second_publication_before" = "$(tree_manifest "$second_handoff")"

/usr/bin/touch "$fixture_root/.build/fixture-with-weight"
readonly weight_result="$fixture_root/.build/weight-result.json"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$weight_result" \
  >"$test_root/weight.out" 2>"$test_root/weight.err"; then
  printf '%s\n' 'FAIL: packager accepted a forbidden model-weight suffix' >&2
  exit 1
fi
/usr/bin/grep -Fq 'forbidden model asset' "$test_root/weight.err"
test ! -e "$weight_result"

# Resetting the allocator must collide rather than replace the first version/build publication.
/bin/rm -f "$fixture_identity_database" "$fixture_identity_database-shm" "$fixture_identity_database-wal"
readonly collision_result="$fixture_root/.build/collision-result.json"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" --result-file "$collision_result" \
  >"$test_root/collision.out" 2>"$test_root/collision.err"; then
  printf '%s\n' 'FAIL: allocator-reset collision replaced an existing publication' >&2
  exit 1
fi
/usr/bin/grep -Fq 'refusing to overwrite existing corrected publication' "$test_root/collision.err"
test ! -e "$collision_result"
test "$first_publication_before" = "$(tree_manifest "$first_handoff")"

test "$legacy_publication_before" = "$(tree_manifest "$legacy_publication")"
test "$(/usr/bin/shasum -a 256 "$legacy_zip" | /usr/bin/awk '{print $1}')" = "$legacy_zip_before"
test "$(/usr/bin/shasum -a 256 "$fixture_accepted_root/manifest.json" | /usr/bin/awk '{print $1}')" = "$fixture_manifest_hash"
test "$(/usr/bin/awk '{print $1}' "$fixture_accepted_root/manifest.sha256")" = "$fixture_manifest_hash"
printf '%s\n' 'PASS: immutable versioned corrected packaging, pinned nested results, provenance, and rollback safety'
