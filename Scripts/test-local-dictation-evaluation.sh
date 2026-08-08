#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

swift test --package-path Tools/LocalDictationEvaluation --no-parallel

corpus_path="$repo_root/Tests/Fixtures/local-dictation-evaluation-v1.json"
corpus_schema_path="$repo_root/Tests/Fixtures/local-dictation-evaluation-v1.schema.json"
run_path="$repo_root/Tests/Fixtures/local-dictation-run-sample-v1.json"
run_schema_path="$repo_root/Tests/Fixtures/local-dictation-run-v1.schema.json"
v2_run_path="$repo_root/Tests/Fixtures/local-dictation-run-sample-v2.json"
v2_run_schema_path="$repo_root/Tests/Fixtures/local-dictation-run-v2.schema.json"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/fleck-local-dictation.XXXXXX")
gate_path="$temporary_dir/gate.json"
v2_gate_path="$temporary_dir/gate-v2.json"
report_path="$temporary_dir/report.md"
v2_report_path="$temporary_dir/report-v2.md"
invalid_path="$temporary_dir/invalid.json"
unknown_run_path="$temporary_dir/unknown-run.json"
stderr_path="$temporary_dir/stderr.txt"
cleanup() {
  rm -rf "$temporary_dir"
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

jq --slurpfile sample "$v2_run_path" '
  .schemaVersion = 2
  | .sliceGates = ($sample[0].standardBaseline.sliceMetrics | map({
      sliceID,
      metric,
      maximumCandidateValue: 1.0,
      maximumRegressionFromStandard: 1.0
    }))
  | .maxFirstMeaningfulPartialMilliseconds = 500
  | .maxProvisionalUpdateIntervalMilliseconds = 500
  | .maxProvisionalInstabilityRate = 0.50
  | .maxFinalASRMilliseconds = 500
  | .maxCleanupMilliseconds = 500
  | .maxStopToInsertionMilliseconds = 2000
  | .maxCancellationMilliseconds = 500
  | .maxReadyIdleDeltaBytes = 500000000
  | .maxPostUnloadDeltaBytes = 2000000000
  | .maxUnloadMilliseconds = 500
  | .minimumRepeatedRunCount = 50
' "$gate_path" > "$v2_gate_path"

Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus "$corpus_path" \
  --corpus-schema "$corpus_schema_path"
Scripts/evaluate-local-dictation.sh validate-run \
  --corpus "$corpus_path" \
  --corpus-schema "$corpus_schema_path" \
  --run "$run_path" \
  --run-schema "$run_schema_path"
Scripts/evaluate-local-dictation.sh report \
  --corpus "$corpus_path" \
  --corpus-schema "$corpus_schema_path" \
  --run "$run_path" \
  --run-schema "$run_schema_path" \
  --gate "$gate_path" \
  --output "$report_path"
grep -F -x 'SAMPLE DATA — NOT MODEL EVIDENCE' "$report_path" >/dev/null
grep -F 'failure-cancellation-behavior' "$report_path" >/dev/null
if grep -F 'fixInputMonitor' "$report_path" >/dev/null; then
  printf '%s\n' 'sample report leaked transcript content' >&2
  exit 1
fi

Scripts/evaluate-local-dictation.sh validate-run \
  --corpus "$corpus_path" \
  --corpus-schema "$corpus_schema_path" \
  --run "$v2_run_path" \
  --run-schema "$v2_run_schema_path"
Scripts/evaluate-local-dictation.sh report \
  --corpus "$corpus_path" \
  --corpus-schema "$corpus_schema_path" \
  --run "$v2_run_path" \
  --run-schema "$v2_run_schema_path" \
  --gate "$v2_gate_path" \
  --output "$v2_report_path"
grep -F 'first-meaningful-partial' "$v2_report_path" >/dev/null
grep -F 'slice:category:' "$v2_report_path" >/dev/null

sed '1,/"latency": {/s/"latency": {/&"mysteryMilliseconds": 1,/' \
  "$run_path" > "$unknown_run_path"
if Scripts/evaluate-local-dictation.sh validate-run \
  --corpus "$corpus_path" \
  --corpus-schema "$corpus_schema_path" \
  --run "$unknown_run_path" \
  --run-schema "$run_schema_path" \
  > /dev/null 2> "$stderr_path"
then
  printf '%s\n' 'unknown run key unexpectedly passed' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 2 ]; then
    printf 'unknown run key returned %s\n' "$status" >&2
    exit 1
  fi
fi
grep -F -x \
  "input error: $unknown_run_path unknown-key:/results/0/latency/mysteryMilliseconds" \
  "$stderr_path" >/dev/null

if Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus --corpus-schema "$corpus_schema_path" > /dev/null 2> "$stderr_path"
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
  --corpus "$invalid_path" \
  --corpus-schema "$corpus_schema_path" > /dev/null 2> "$stderr_path"
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
