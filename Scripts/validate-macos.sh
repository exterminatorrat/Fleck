#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"

if [[ -n "${MOTES_ENHANCED_CANDIDATE+x}" ]]; then
  printf '%s\n' \
    'error: unset MOTES_ENHANCED_CANDIDATE before validating an ordinary release' \
    >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: this validation script must run on macOS\n' >&2
  exit 2
fi

major_version="$(sw_vers -productVersion | cut -d. -f1)"
if (( major_version < 14 )); then
  printf 'error: Motes requires macOS 14 or later (found %s)\n' \
    "$(sw_vers -productVersion)" >&2
  exit 2
fi

if ! xcode-select -p >/dev/null 2>&1; then
  printf 'error: select Xcode command-line tools with xcode-select first\n' >&2
  exit 2
fi

cd "$repo_root"

printf '%s\n' '--- Host ---'
sw_vers
xcodebuild -version
swift --version

printf '%s\n' '--- Tests ---'
swift test --disable-automatic-resolution

printf '%s\n' '--- Release build ---'
swift package clean
swift build -c release --disable-automatic-resolution
"$script_dir/check-release-size.sh" .build/release/Motes

printf '%s\n' '--- Candidate lock preservation ---'
"$script_dir/test-enhanced-candidate-lock-preservation.sh"

printf '%s\n' '--- Candidate release rejection ---'
"$script_dir/check-candidate-release-rejected.sh"

printf '\nValidation build passed. Launch manually with:\n  %s\n' \
  "$(pwd)/.build/release/Motes"
