#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly package_path="$repo_root/Tools/LocalDictationCandidateAdapters"
readonly manifest_path="$repo_root/Tests/Fixtures/local-dictation-admission-v1.json"
readonly schema_path="$repo_root/Tests/Fixtures/local-dictation-admission-v1.schema.json"
readonly adapter_path="$package_path/Tests/Fixtures/local-dictation-fixture-adapter.sh"

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-local-dictation-candidate.XXXXXX")"
cleanup() {
  rm -rf -- "$temporary_dir"
}
trap cleanup EXIT HUP INT TERM

cd "$repo_root"

swift test --package-path "$package_path" --no-parallel

swift_bin="$(command -v swift)"
[[ -x "$swift_bin" ]] || { printf '%s\n' 'swift executable not found' >&2; exit 2; }
cli_bin="$($swift_bin build --package-path "$package_path" --product local-dictation-candidate --show-bin-path)/local-dictation-candidate"
[[ -x "$cli_bin" ]] || { printf '%s\n' 'candidate CLI was not built' >&2; exit 2; }

"$cli_bin" validate-admission --manifest "$manifest_path" --schema "$schema_path"

invalid_manifest="$temporary_dir/duplicate-case.json"
jq '.cases[1].id = .cases[0].id' "$manifest_path" > "$invalid_manifest"
if "$cli_bin" validate-admission --manifest "$invalid_manifest" --schema "$schema_path" \
  > "$temporary_dir/invalid.stdout" 2> "$temporary_dir/invalid.stderr"; then
  printf '%s\n' 'duplicate admission case unexpectedly passed' >&2
  exit 1
fi
if ! grep -F 'duplicate-case-id' "$temporary_dir/invalid.stderr" >/dev/null; then
  printf '%s\n' 'duplicate admission case returned an unexpected diagnostic' >&2
  cat "$temporary_dir/invalid.stderr" >&2
  exit 1
fi

model_root="$temporary_dir/model-root"
mkdir -p -- "$model_root"
report_path="$temporary_dir/admission-report.json"
"$script_dir/run-local-dictation-candidate.sh" \
  --manifest "$manifest_path" \
  --adapter "$adapter_path" \
  --model-root "$model_root" \
  --output "$report_path"

jq -e '
  .schemaVersion == 1
  and .audioAdmissionStatus == "synthetic-only"
  and .releaseEvidenceStatus == "refused-no-admitted-real-audio"
  and .networkIsolationMethod == "not-enforced-by-harness"
  and (.cases | length) == 10
  and ([.cases[].status] | index("cancelled")) != null
  and .childExitStatus == 0
' "$report_path" >/dev/null
if grep -F '"transcript"' "$report_path" >/dev/null; then
  printf '%s\n' 'admission report leaked transcript content' >&2
  exit 1
fi

if "$cli_bin" run --manifest "$manifest_path" --adapter "$adapter_path" \
  --model-root "$model_root" --output "$report_path" \
  > "$temporary_dir/existing.stdout" 2> "$temporary_dir/existing.stderr"; then
  printf '%s\n' 'existing report path unexpectedly passed' >&2
  exit 1
fi
if ! grep -F 'output-exists' "$temporary_dir/existing.stderr" >/dev/null; then
  printf '%s\n' 'existing report path returned an unexpected diagnostic' >&2
  cat "$temporary_dir/existing.stderr" >&2
  exit 1
fi

if ps -axo command | grep -F 'local-dictation-fixture-adapter.sh' | grep -v 'grep -F' >/dev/null; then
  printf '%s\n' 'fixture adapter process survived the admission gate' >&2
  exit 1
fi

printf '%s\n' 'local dictation candidate adapter checks passed'
