#!/usr/bin/env bash
set -euo pipefail

readonly revision="19600a485baa4998812e4654b70d2bab8f2c9949"

Scripts/verify-enhanced-candidate-pin.swift \
  Tests/Fixtures/enhanced-candidate-pin-valid.json

if Scripts/verify-enhanced-candidate-pin.swift \
  Tests/Fixtures/enhanced-candidate-pin-wrong-revision.json >/dev/null 2>&1
then
  printf 'error: wrong candidate revision was accepted\n' >&2
  exit 1
fi

rg -F "revision: \"$revision\"" \
  Packages/FleckEnhancedCandidateDependencies/Package.swift >/dev/null
if rg -F 'exact: "0.15.5"' \
  Packages/FleckEnhancedCandidateDependencies/Package.swift >/dev/null
then
  printf 'error: mutable FluidAudio version requirement remains in candidate manifest\n' >&2
  exit 1
fi
