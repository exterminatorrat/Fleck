#!/usr/bin/env bash
set -euo pipefail

readonly source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly source_packager="$source_root/Scripts/build-pre-astra-corrected-build.sh"
readonly test_only="${FLECK_PRE_ASTRA_TEST_ONLY:-}"

if [[ ! -x "$source_packager" ]]; then
  printf 'FAIL: executable packager is missing: %s\n' "$source_packager" >&2
  exit 1
fi
if [[ "$(uname -s)" != 'Darwin' || "$(uname -m)" != 'arm64' ]]; then
  printf '%s\n' 'FAIL: this packaging test requires macOS on arm64' >&2
  exit 1
fi

readonly test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-pre-astra-test.XXXXXX")"
cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

readonly fixture_root="$test_root/Fleck Fixture"
/bin/mkdir -p "$fixture_root/Scripts"
if [[ -n "$test_only" && "$test_only" != 'first-run' ]]; then
  /bin/mkdir "$fixture_root/.build"
fi
/bin/cp -p "$source_packager" "$fixture_root/Scripts/build-pre-astra-corrected-build.sh"
/bin/cat > "$fixture_root/.gitignore" <<'EOF'
.build/
EOF
/bin/cat > "$fixture_root/.pre-astra-packager-test-fixture" <<'EOF'
pre-astra-packager-fixture-v1
EOF
/bin/cat > "$fixture_root/Scripts/build-parakeet-test-app.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly build_root="$repo_root/.build"
readonly app="$build_root/parakeet-test/Fleck.app"
if [[ -f "$build_root/fixture-noop-build" ]]; then
  exit 0
fi
version='fresh-checkout-build'
if [[ -f "$build_root/fixture-build-version" ]]; then
  version="$(/bin/cat "$build_root/fixture-build-version")"
fi
if [[ -d "$app" && ! -L "$app" ]]; then
  /usr/bin/find "$app" -depth -delete
fi
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
EOF
/bin/chmod 755 "$fixture_root/Scripts/build-parakeet-test-app.sh"

(
  cd -- "$fixture_root"
  /usr/bin/git init -q
  /usr/bin/git config user.email fixture@example.invalid
  /usr/bin/git config user.name 'Fleck packaging fixture'
  /usr/bin/git add .
  /usr/bin/git commit -qm 'Create Fleck packaging fixture'
)

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
  test "$(/bin/cat "$fixture_root/.build/parakeet-test/Fleck.app/Contents/Resources/fixture-build-version.txt")" = \
    'fresh-checkout-build'
  if [[ "$test_only" == 'first-run' ]]; then
    exit 0
  fi
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

readonly input_app="$fixture_root/.build/parakeet-test/Fleck.app"
if [[ -z "$test_only" || "$test_only" == 'lock-owner' ]]; then
  if FLECK_PRE_ASTRA_TEST_FAIL_LOCK_OWNER_WRITE=1 \
    "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/lock-owner.out" 2>"$test_root/lock-owner.err"; then
    printf '%s\n' 'FAIL: lock-owner failpoint did not stop the operation' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'injected lock-owner creation failure' "$test_root/lock-owner.err"
  test ! -e "$fixture_root/.build/.pre-astra-corrected.lock"
  if [[ "$test_only" == 'lock-owner' ]]; then
    exit 0
  fi
fi
if [[ "$test_only" == 'requirement' ]]; then
  printf '%s\n' 'wrong-requirement-build' > "$fixture_root/.build/fixture-build-version"
  /usr/bin/touch "$fixture_root/.build/fixture-wrong-requirement"
  "$fixture_root/Scripts/build-parakeet-test-app.sh" >/dev/null
  if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/requirement.out" 2>"$test_root/requirement.err"; then
    printf '%s\n' 'FAIL: packager accepted a mismatched designated requirement' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'unexpected designated requirement' "$test_root/requirement.err"
  exit 0
fi
if [[ "$test_only" == 'manifest' ]]; then
  printf '%s\n' 'manifest-build' > "$fixture_root/.build/fixture-build-version"
  "$fixture_root/Scripts/build-parakeet-test-app.sh" >/dev/null
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" >/dev/null
  readonly manifest_app="$fixture_root/.build/pre-astra-corrected/Fleck Pre-Astra Corrected Build/Fleck Pre-Astra Corrected Build.app"
  readonly manifest_handoff="$fixture_root/.build/pre-astra-corrected/Fleck Pre-Astra Corrected Build"
  readonly published_input_manifest="$manifest_handoff/INPUT-APP-MANIFEST.sha256.tsv"
  readonly expected_input_manifest="$test_root/expected-input.manifest"
  tree_manifest "$input_app" > "$expected_input_manifest"
  test -f "$manifest_handoff/BUILD-PROVENANCE.txt"
  test -f "$published_input_manifest"
  /usr/bin/cmp -s "$expected_input_manifest" "$published_input_manifest"
  readonly published_input_manifest_hash="$(/usr/bin/shasum -a 256 "$published_input_manifest" | /usr/bin/awk '{print $1}')"
  test "$(/usr/bin/plutil -extract FleckInputManifestSHA256 raw -o - "$manifest_app/Contents/Info.plist")" = \
    "$published_input_manifest_hash"
  /usr/bin/grep -Fq "Input app manifest SHA-256: $published_input_manifest_hash" \
    "$manifest_handoff/BUILD-PROVENANCE.txt"
  exit 0
fi
if [[ "$test_only" == 'after-final-source' || "$test_only" == 'after-swap' \
  || "$test_only" == 'legacy-zip' ]]; then
  printf '%s\n' 'transaction-baseline' > "$fixture_root/.build/fixture-build-version"
  "$fixture_root/Scripts/build-parakeet-test-app.sh" >/dev/null
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" >/dev/null
  readonly transaction_output="$fixture_root/.build/pre-astra-corrected"
  readonly transaction_input_before="$(tree_manifest "$input_app")"
  readonly transaction_publication_before="$(tree_manifest "$transaction_output")"
  readonly transaction_legacy_zip="$fixture_root/.build/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
  readonly expected_legacy_zip="$test_root/expected-legacy.zip"
  if [[ "$test_only" == 'legacy-zip' ]]; then
    printf '%s\n' 'legacy-zip-sentinel' > "$transaction_legacy_zip"
    /bin/cp -p "$transaction_legacy_zip" "$expected_legacy_zip"
  fi
  printf '%s\n' 'transaction-replacement' > "$fixture_root/.build/fixture-build-version"
  if [[ "$test_only" == 'after-final-source' ]]; then
    failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK'
    expected_failure='injected failure after final source check'
  elif [[ "$test_only" == 'after-swap' ]]; then
    failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP'
    expected_failure='injected failure after publication swap'
  else
    failpoint_name='FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP'
    expected_failure='injected failure after legacy ZIP backup'
  fi
  if /usr/bin/env "$failpoint_name=1" \
    "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/transaction.out" 2>"$test_root/transaction.err"; then
    printf 'FAIL: %s did not stop the operation\n' "$failpoint_name" >&2
    exit 1
  fi
  /usr/bin/grep -Fq "$expected_failure" "$test_root/transaction.err"
  test "$transaction_input_before" = "$(tree_manifest "$input_app")"
  test "$transaction_publication_before" = "$(tree_manifest "$transaction_output")"
  if [[ "$test_only" == 'legacy-zip' ]]; then
    /usr/bin/cmp -s "$expected_legacy_zip" "$transaction_legacy_zip"
  fi
  exit 0
fi
if [[ "$test_only" == 'publication' ]]; then
  printf '%s\n' 'publication-build-1' > "$fixture_root/.build/fixture-build-version"
  "$fixture_root/Scripts/build-parakeet-test-app.sh" >/dev/null
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" >/dev/null
  readonly publication_app="$fixture_root/.build/pre-astra-corrected/Fleck Pre-Astra Corrected Build/Fleck Pre-Astra Corrected Build.app"
  printf '%s\n' 'publication-build-2' > "$fixture_root/.build/fixture-build-version"
  if FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP=1 \
    "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
    >"$test_root/publication.out" 2>"$test_root/publication.err"; then
    printf '%s\n' 'FAIL: publication failpoint did not stop publication' >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'injected publication failure' "$test_root/publication.err"
  test "$(/bin/cat "$publication_app/Contents/Resources/fixture-build-version.txt")" = \
    'publication-build-1'
  exit 0
fi

printf '%s\n' 'stale-build' > "$fixture_root/.build/fixture-build-version"
"$fixture_root/Scripts/build-parakeet-test-app.sh" >/dev/null
readonly stale_hash="$(/usr/bin/shasum -a 256 "$input_app/Contents/Resources/fixture-build-version.txt" | /usr/bin/awk '{print $1}')"
/usr/bin/touch "$fixture_root/.build/fixture-noop-build"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/stale.out" 2>"$test_root/stale.err"; then
  printf '%s\n' 'FAIL: packager stamped a stale app after a no-op source build' >&2
  exit 1
fi
/usr/bin/grep -Fq 'fresh build did not produce the input app' "$test_root/stale.err"
test "$stale_hash" = \
  "$(/usr/bin/shasum -a 256 "$input_app/Contents/Resources/fixture-build-version.txt" | /usr/bin/awk '{print $1}')"
/usr/bin/find "$fixture_root/.build/fixture-noop-build" -maxdepth 0 -type f -delete

printf '%s\n' 'fresh-build-1' > "$fixture_root/.build/fixture-build-version"
"$fixture_root/Scripts/build-pre-astra-corrected-build.sh"

readonly source_commit="$(/usr/bin/git -C "$fixture_root" rev-parse HEAD)"
readonly source_tree="$(/usr/bin/git -C "$fixture_root" rev-parse 'HEAD^{tree}')"
readonly output_root="$fixture_root/.build/pre-astra-corrected"
readonly handoff_root="$output_root/Fleck Pre-Astra Corrected Build"
readonly staged_app="$handoff_root/Fleck Pre-Astra Corrected Build.app"
readonly launcher="$handoff_root/Launch Fleck Pre-Astra Corrected Build.command"
readonly receipt="$handoff_root/BUILD-PROVENANCE.txt"
readonly published_input_manifest="$handoff_root/INPUT-APP-MANIFEST.sha256.tsv"
readonly zip_path="$output_root/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
test -d "$staged_app"
test -x "$launcher"
test -f "$receipt"
test -f "$published_input_manifest"
test -f "$zip_path"
test ! -e "$fixture_root/.build/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
test "$(/bin/cat "$staged_app/Contents/Resources/fixture-build-version.txt")" = 'fresh-build-1'

test "$(/usr/bin/plutil -extract CFBundleDisplayName raw -o - "$staged_app/Contents/Info.plist")" = \
  'Fleck Pre-Astra Corrected Build'
test "$(/usr/bin/plutil -extract CFBundleName raw -o - "$staged_app/Contents/Info.plist")" = \
  'Fleck Pre-Astra Corrected Build'
test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$staged_app/Contents/Info.plist")" = \
  'com.harryjin.fleck'
test "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$staged_app/Contents/Info.plist")" = 'Fleck'
test "$(/usr/bin/plutil -extract FleckBuildLabel raw -o - "$staged_app/Contents/Info.plist")" = \
  'Pre-Astra Corrected Build'
test "$(/usr/bin/plutil -extract FleckSourceCommit raw -o - "$staged_app/Contents/Info.plist")" = \
  "$source_commit"
test "$(/usr/bin/plutil -extract FleckSourceTree raw -o - "$staged_app/Contents/Info.plist")" = \
  "$source_tree"
readonly input_manifest_hash="$(tree_manifest "$input_app" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
readonly expected_input_manifest="$test_root/expected-input.manifest"
tree_manifest "$input_app" > "$expected_input_manifest"
/usr/bin/cmp -s "$expected_input_manifest" "$published_input_manifest"
test "$(/usr/bin/plutil -extract FleckInputManifestSHA256 raw -o - "$staged_app/Contents/Info.plist")" = \
  "$input_manifest_hash"
test "$(/usr/bin/shasum -a 256 "$published_input_manifest" | /usr/bin/awk '{print $1}')" = \
  "$input_manifest_hash"
/usr/bin/grep -Fq "Source commit: $source_commit" "$receipt"
/usr/bin/grep -Fq "Source tree: $source_tree" "$receipt"
/usr/bin/grep -Fq "Input app manifest SHA-256: $input_manifest_hash" "$receipt"

/usr/bin/grep -Fq '/usr/bin/open -n "$app_path"' "$launcher"
/usr/bin/codesign --verify --deep --strict "$staged_app"
test "$(/usr/bin/codesign -d -r- "$staged_app" 2>&1 | /usr/bin/sed -n 's/^designated => /designated => /p')" = \
  'designated => identifier "com.harryjin.fleck"'
for helper_name in fleck-agent gemma-cleanup-helper; do
  input_helper="$input_app/Contents/SharedSupport/$helper_name"
  staged_helper="$staged_app/Contents/SharedSupport/$helper_name"
  test "$(/usr/bin/shasum -a 256 "$staged_helper" | /usr/bin/awk '{print $1}')" = \
    "$(/usr/bin/shasum -a 256 "$input_helper" | /usr/bin/awk '{print $1}')"
  /usr/bin/codesign -d --verbose=5 "$input_helper" 2>&1 \
    | /usr/bin/grep -F 'Has Self Launch Constraints' >/dev/null
  /usr/bin/codesign -d --verbose=5 "$staged_helper" 2>&1 \
    | /usr/bin/grep -F 'Has Self Launch Constraints' >/dev/null
  test "$(signature_requirement "$staged_helper")" = "$(signature_requirement "$input_helper")"
  test "$(signature_entitlements "$staged_helper")" = "$(signature_entitlements "$input_helper")"
done
for executable in \
  "$staged_app/Contents/MacOS/Fleck" \
  "$staged_app/Contents/SharedSupport/fleck-agent" \
  "$staged_app/Contents/SharedSupport/gemma-cleanup-helper"; do
  test "$(/usr/bin/lipo -archs "$executable")" = 'arm64'
done

if /usr/bin/unzip -Z1 "$zip_path" | /usr/bin/grep -Eq '(^|/)__MACOSX(/|$)'; then
  printf '%s\n' 'FAIL: ZIP contains an unexpected __MACOSX entry' >&2
  exit 1
fi
readonly extract_root="$test_root/extracted"
/bin/mkdir "$extract_root"
/usr/bin/ditto -x -k "$zip_path" "$extract_root"
readonly extracted_handoff="$extract_root/Fleck Pre-Astra Corrected Build"
test "$(tree_manifest "$handoff_root")" = "$(tree_manifest "$extracted_handoff")"
/usr/bin/cmp -s "$published_input_manifest" \
  "$extracted_handoff/INPUT-APP-MANIFEST.sha256.tsv"

readonly first_input_manifest="$(tree_manifest "$input_app")"
readonly first_publication_manifest="$(tree_manifest "$output_root")"
printf '%s\n' 'let untrackedBuildInput = true' > "$fixture_root/UntrackedBuildInput.swift"
printf '%s\n' 'untracked-source-build' > "$fixture_root/.build/fixture-build-version"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/untracked.out" 2>"$test_root/untracked.err"; then
  printf '%s\n' 'FAIL: packager accepted an untracked build-relevant source file' >&2
  exit 1
fi
/usr/bin/grep -Fq 'untracked files or dirty submodules are present' "$test_root/untracked.err"
test "$first_input_manifest" = "$(tree_manifest "$input_app")"
test "$first_publication_manifest" = "$(tree_manifest "$output_root")"
/usr/bin/find "$fixture_root/UntrackedBuildInput.swift" -maxdepth 0 -type f -delete

/usr/bin/touch "$fixture_root/.build/fixture-wrong-requirement"
printf '%s\n' 'wrong-requirement-build' > "$fixture_root/.build/fixture-build-version"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/requirement.out" 2>"$test_root/requirement.err"; then
  printf '%s\n' 'FAIL: packager accepted a mismatched designated requirement' >&2
  exit 1
fi
/usr/bin/grep -Fq 'unexpected designated requirement' "$test_root/requirement.err"
test "$first_publication_manifest" = "$(tree_manifest "$output_root")"
/usr/bin/find "$fixture_root/.build/fixture-wrong-requirement" -maxdepth 0 -type f -delete

printf '%s\n' 'fresh-build-2' > "$fixture_root/.build/fixture-build-version"
"$fixture_root/Scripts/build-pre-astra-corrected-build.sh" >/dev/null
test "$(/bin/cat "$staged_app/Contents/Resources/fixture-build-version.txt")" = 'fresh-build-2'
readonly second_publication_manifest="$(tree_manifest "$output_root")"
readonly second_input_manifest="$(tree_manifest "$input_app")"
test "$first_publication_manifest" != "$second_publication_manifest"

printf '%s\n' 'fresh-build-3' > "$fixture_root/.build/fixture-build-version"
readonly legacy_zip="$fixture_root/.build/Fleck-Pre-Astra-Corrected-Build-arm64.zip"
readonly expected_legacy_zip="$test_root/expected-legacy.zip"
printf '%s\n' 'legacy-zip-sentinel' > "$legacy_zip"
/bin/cp -p "$legacy_zip" "$expected_legacy_zip"
if FLECK_PRE_ASTRA_TEST_FAIL_AFTER_LEGACY_ZIP_BACKUP=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/legacy-zip.out" 2>"$test_root/legacy-zip.err"; then
  printf '%s\n' 'FAIL: legacy-ZIP failpoint did not stop the operation' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected failure after legacy ZIP backup' "$test_root/legacy-zip.err"
test "$second_input_manifest" = "$(tree_manifest "$input_app")"
test "$second_publication_manifest" = "$(tree_manifest "$output_root")"
/usr/bin/cmp -s "$expected_legacy_zip" "$legacy_zip"
/usr/bin/find "$legacy_zip" -maxdepth 0 -type f -delete

printf '%s\n' 'fresh-build-4' > "$fixture_root/.build/fixture-build-version"
if FLECK_PRE_ASTRA_TEST_FAIL_AFTER_FINAL_SOURCE_CHECK=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/final-source.out" 2>"$test_root/final-source.err"; then
  printf '%s\n' 'FAIL: final-source failpoint did not stop the operation' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected failure after final source check' "$test_root/final-source.err"
test "$second_input_manifest" = "$(tree_manifest "$input_app")"
test "$second_publication_manifest" = "$(tree_manifest "$output_root")"

printf '%s\n' 'fresh-build-5' > "$fixture_root/.build/fixture-build-version"
if FLECK_PRE_ASTRA_TEST_FAIL_AFTER_PUBLICATION_SWAP=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/publication-swap.out" 2>"$test_root/publication-swap.err"; then
  printf '%s\n' 'FAIL: publication-swap failpoint did not stop the operation' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected failure after publication swap' "$test_root/publication-swap.err"
test "$second_input_manifest" = "$(tree_manifest "$input_app")"
test "$second_publication_manifest" = "$(tree_manifest "$output_root")"

printf '%s\n' 'fresh-build-6' > "$fixture_root/.build/fixture-build-version"
if FLECK_PRE_ASTRA_TEST_FAIL_PUBLICATION_AFTER_BACKUP=1 \
  "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/publication.out" 2>"$test_root/publication.err"; then
  printf '%s\n' 'FAIL: publication failpoint did not stop publication' >&2
  exit 1
fi
/usr/bin/grep -Fq 'injected publication failure' "$test_root/publication.err"
test "$second_publication_manifest" = "$(tree_manifest "$output_root")"
test "$second_input_manifest" = "$(tree_manifest "$input_app")"
test "$(/bin/cat "$staged_app/Contents/Resources/fixture-build-version.txt")" = 'fresh-build-2'

/usr/bin/touch "$fixture_root/.build/fixture-with-weight"
if "$fixture_root/Scripts/build-pre-astra-corrected-build.sh" \
  >"$test_root/weight.out" 2>"$test_root/weight.err"; then
  printf '%s\n' 'FAIL: packager accepted a forbidden model-weight suffix' >&2
  exit 1
fi
/usr/bin/grep -Fq 'forbidden model asset' "$test_root/weight.err"

printf '%s\n' 'PASS: fresh-build provenance, exact identity, complete equivalence, and rollback-safe publication'
