#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

swift test --package-path Tools/LocalDictationEvaluation --no-parallel

corpus_path="Tests/Fixtures/local-dictation-evaluation-v1.json"
run_path="Tests/Fixtures/local-dictation-run-sample-v1.json"
gate_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-gate.XXXXXX")
report_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-report.XXXXXX")
invalid_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-invalid.XXXXXX")
stderr_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-stderr.XXXXXX")
cleanup() {
  rm -f "$gate_path" "$report_path" "$invalid_path" "$stderr_path"
}
trap cleanup EXIT HUP INT TERM

cat > "$gate_path" <<'JSON'
{
  "schemaVersion": 1,
  "maxEnglishWordErrorRate": 0.25,
  "maxMandarinCharacterErrorRate": 0.25,
  "maxMixedEnglishWordErrorRate": 0.30,
  "maxMixedMandarinCharacterErrorRate": 0.30,
  "minimumProtectedTermAccuracy": 0.90,
  "maximumNumberFailures": 0,
  "maximumNegationFailures": 0,
  "maximumCleanupPreservationFailures": 0,
  "maxColdLatencyMilliseconds": 2000,
  "maxWarmLatencyMilliseconds": 500,
  "maxPeakMemoryBytes": 2000000000,
  "maxIdleMemoryBytes": 500000000,
  "maxPostUnloadMemoryBytes": 500000000,
  "maxEnergyImpact": 2.0,
  "maxModelDownloadBytes": 2000000000,
  "maxModelInstalledBytes": 2000000000,
  "minimumStandardMaterialImprovement": 0.10,
  "allowedThermalStates": ["nominal", "fair"]
}
JSON

Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus "$corpus_path"
Scripts/evaluate-local-dictation.sh validate-run \
  --corpus "$corpus_path" \
  --run "$run_path"
Scripts/evaluate-local-dictation.sh report \
  --corpus "$corpus_path" \
  --run "$run_path" \
  --gate "$gate_path" \
  --output "$report_path"
grep -F -x 'SAMPLE DATA — NOT MODEL EVIDENCE' "$report_path" >/dev/null
grep -F 'failure-cancellation-behavior' "$report_path" >/dev/null
if grep -F 'fixInputMonitor' "$report_path" >/dev/null; then
  printf '%s\n' 'sample report leaked transcript content' >&2
  exit 1
fi

if Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus --run > /dev/null 2> "$stderr_path"
then
  printf '%s\n' 'flag-looking value unexpectedly passed' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 2 ]; then
    printf 'flag-looking value returned %s\n' "$status" >&2
    exit 1
  fi
fi
grep -F -x 'argument error: missing value for --corpus' "$stderr_path" >/dev/null
if grep -F 'file error' "$stderr_path" >/dev/null; then
  printf '%s\n' 'flag-looking value was treated as a file path' >&2
  exit 1
fi

printf '%s\n' '{"schemaVersion":0}' > "$invalid_path"
if Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus "$invalid_path" > /dev/null 2> "$stderr_path"
then
  printf '%s\n' 'invalid corpus unexpectedly passed' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 2 ]; then
    printf 'invalid corpus returned %s\n' "$status" >&2
    exit 1
  fi
fi
if grep -E 'fixInputMonitor|请在星期五|PRIVATE_TRANSCRIPT' "$stderr_path" >/dev/null; then
  printf '%s\n' 'invalid diagnostics leaked transcript content' >&2
  exit 1
fi

printf '%s\n' 'local dictation evaluation integration checks passed'
