#!/usr/bin/env bash
set -euo pipefail

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

printf '%s\n' '--- Host ---'
sw_vers
xcodebuild -version
swift --version

printf '%s\n' '--- Tests ---'
swift test

printf '%s\n' '--- Release build ---'
swift package clean
swift build -c release
Scripts/check-release-size.sh .build/release/Motes

printf '%s\n' '--- Candidate release rejection ---'
Scripts/check-candidate-release-rejected.sh

printf '\nValidation build passed. Launch manually with:\n  %s\n' \
  "$(pwd)/.build/release/Motes"
