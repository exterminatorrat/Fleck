#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  printf 'usage: %s <package-root> <scratch-path-or-empty> <anchored-test-identifier-regex>\n' \
    "${0##*/}" >&2
  exit 2
fi

readonly package_root="$1"
readonly scratch_path="$2"
readonly identifier_regex="$3"
readonly host_source="$package_root/Tests/Support/AppKitTestMain.swift"

[[ "$(/usr/bin/uname -s)" = Darwin ]] || {
  printf '%s\n' 'error: the AppKit Swift test host requires macOS' >&2
  exit 1
}
[[ -f "$host_source" && ! -L "$host_source" ]] || {
  printf 'error: AppKit Swift test host source is missing or unsafe: %s\n' \
    "$host_source" >&2
  exit 1
}

xcrun_path="$(command -v xcrun || true)"
[[ -n "$xcrun_path" && -x "$xcrun_path" ]] || {
  printf '%s\n' 'error: xcrun is required to build the AppKit Swift test host' >&2
  exit 1
}

set +e
sdk_path="$("$xcrun_path" --sdk macosx --show-sdk-path)"
sdk_status=$?
platform_path="$("$xcrun_path" --sdk macosx --show-sdk-platform-path)"
platform_status=$?
swiftc_path="$("$xcrun_path" --sdk macosx --find swiftc)"
swiftc_status=$?
set -e
if (( sdk_status != 0 || platform_status != 0 || swiftc_status != 0 )) ||
  [[ ! -d "$sdk_path" || ! -d "$platform_path" || ! -x "$swiftc_path" ]]; then
  printf '%s\n' 'error: failed to resolve the selected macOS SDK and Swift compiler' >&2
  exit 1
fi
readonly sdk_path platform_path swiftc_path
readonly framework_path="$platform_path/Developer/Library/Frameworks"
[[ -d "$framework_path/Testing.framework" ]] || {
  printf 'error: selected macOS platform has no Testing framework: %s\n' \
    "$framework_path/Testing.framework" >&2
  exit 1
}

state_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-appkit-test-host.XXXXXX")"
readonly state_dir
cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  /bin/rm -rf -- "$state_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

build_arguments=(build --build-tests --disable-automatic-resolution)
bin_arguments=(build --show-bin-path --disable-automatic-resolution)
if [[ -n "$scratch_path" ]]; then
  build_arguments+=(--scratch-path "$scratch_path")
  bin_arguments+=(--scratch-path "$scratch_path")
fi

set +e
(
  cd "$package_root"
  swift "${build_arguments[@]}"
)
build_status=$?
set -e
(( build_status == 0 )) || exit "$build_status"

set +e
bin_path="$({
  cd "$package_root"
  swift "${bin_arguments[@]}"
})"
bin_status=$?
set -e
(( bin_status == 0 )) || exit "$bin_status"
if [[ "$bin_path" != /* || ! -d "$bin_path" || -L "$bin_path" || "$bin_path" == *$'\n'* ]]; then
  printf 'error: SwiftPM returned an invalid test binary path: %s\n' "$bin_path" >&2
  exit 1
fi
readonly bin_path

readonly bundle_candidates="$state_dir/test-bundles"
/usr/bin/find "$bin_path" -maxdepth 1 -type d -name '*.xctest' -print \
  > "$bundle_candidates"
bundle_count="$(/usr/bin/wc -l < "$bundle_candidates" | /usr/bin/tr -d ' ')"
if [[ "$bundle_count" != 1 ]]; then
  printf 'error: expected exactly one freshly built Swift test bundle, found %s in %s\n' \
    "$bundle_count" "$bin_path" >&2
  exit 1
fi
bundle_path="$(/bin/cat "$bundle_candidates")"
bundle_name="$(/usr/bin/basename "$bundle_path" .xctest)"
readonly bundle_binary="$bundle_path/Contents/MacOS/$bundle_name"
if [[ ! -f "$bundle_binary" || -L "$bundle_binary" || ! -x "$bundle_binary" ]]; then
  printf 'error: freshly built Swift test bundle has no safe executable: %s\n' \
    "$bundle_binary" >&2
  exit 1
fi

readonly host_binary="$state_dir/AppKitTestHost"
set +e
"$swiftc_path" -parse-as-library -sdk "$sdk_path" -F "$framework_path" \
  -framework AppKit -framework Testing \
  -Xlinker -rpath -Xlinker "$framework_path" \
  "$host_source" -o "$host_binary"
host_build_status=$?
set -e
(( host_build_status == 0 )) || exit "$host_build_status"
[[ -x "$host_binary" && ! -L "$host_binary" ]] || {
  printf '%s\n' 'error: Swift compiler did not produce the AppKit Swift test host' >&2
  exit 1
}

readonly list_output="$state_dir/test-list"
readonly canonical_output="$state_dir/canonical-test-list"
readonly matches="$state_dir/matches"
readonly test_output="$state_dir/test-output"
set +e
"$host_binary" "$bundle_binary" --list-tests > "$list_output"
list_status=$?
set -e
(( list_status == 0 )) || exit "$list_status"

LC_ALL=C /usr/bin/grep -E \
  '^[[:alnum:]_][[:alnum:]_-]*\.[[:alnum:]_][[:alnum:]_.-]*(/[[:alnum:]_][[:alnum:]_.-]*)*\((([[:alpha:]_][[:alnum:]_]*):)*\)$' \
  "$list_output" > "$canonical_output" || true
set +e
/usr/bin/grep -E -- "$identifier_regex" "$canonical_output" > "$matches"
match_status=$?
set -e
if (( match_status == 2 )); then
  printf 'error: invalid extended regular expression: %s\n' "$identifier_regex" >&2
  exit 2
fi
if [[ ! -s "$matches" ]]; then
  printf 'error: test identifier regex matched zero tests: %s\n' \
    "$identifier_regex" >&2
  exit 3
fi

matched_count="$(/usr/bin/wc -l < "$matches" | /usr/bin/tr -d ' ')"
printf 'matched test count: %s\n' "$matched_count"
while IFS= read -r identifier; do
  printf 'matched test: %s\n' "$identifier"
done < "$matches"

if [[ "$identifier_regex" = '^.+$' ]]; then
  run_filter="$identifier_regex"
else
  run_filter="$(/usr/bin/awk '
  function escape_ere(value, result, index_, character) {
    result = ""
    for (index_ = 1; index_ <= length(value); index_++) {
      character = substr(value, index_, 1)
      if (index("\\.^$|()[]*+?{}", character) > 0) {
        result = result "\\" character
      } else {
        result = result character
      }
    }
    return result
  }
  BEGIN { printf "^(" }
  {
    identifier = $0
    if (count++) { printf "|" }
    printf "%s/", escape_ere(identifier)
  }
  END { print ")" }
' "$matches")"
fi

set +e
"$host_binary" "$bundle_binary" --filter "$run_filter" --no-parallel 2>&1 |
  /usr/bin/tee "$test_output"
test_pipeline_status=("${PIPESTATUS[@]}")
set -e
test_status="${test_pipeline_status[0]}"
output_status="${test_pipeline_status[1]}"
(( test_status == 0 )) || exit "$test_status"
if (( output_status != 0 )); then
  printf '%s\n' 'error: failed to capture Swift test output' >&2
  exit 1
fi

final_output_line="$(/usr/bin/awk 'NF { line = $0 } END { print line }' "$test_output")"
if ! printf '%s\n' "$final_output_line" | LC_ALL=C /usr/bin/grep -Eq \
  '^✔ Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed after [0-9]+(\.[0-9]+)? seconds\.$'; then
  printf '%s\n' \
    'error: Swift test exited successfully without a final non-empty passing test summary' >&2
  exit 1
fi
