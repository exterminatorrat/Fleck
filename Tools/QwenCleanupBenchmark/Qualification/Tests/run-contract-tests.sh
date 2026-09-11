#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(git -C "$script_dir/../../.." rev-parse --show-toplevel)"
readonly runner="$repo_root/Tools/QwenCleanupBenchmark/Qualification/run-qwen-cleanup-qualification.sh"
readonly corpus="$repo_root/Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json"
readonly python="${FLECK_QWEN_PYTHON_EXECUTABLE:-}"
readonly qwen_source="${FLECK_QWEN_QUALIFICATION_QWEN_SOURCE:-}"
readonly whisper_source="${FLECK_QWEN_QUALIFICATION_WHISPER_SOURCE:-}"
readonly rescore_source_root="${FLECK_QWEN_QUALIFICATION_RESCORE_FIXTURE_ROOT:-}"
readonly test_root="$(realpath "$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-qualification-contract.XXXXXX")")"
readonly fake_model="$test_root/fake-model"
readonly fake_site="$test_root/fake-site"
readonly fake_responses="$test_root/fake-responses.json"
readonly fake_manifest="$test_root/fake-manifest.json"
readonly poison_site="$test_root/poison-site"
readonly marker="$test_root/poison-marker"
readonly log_dir="$test_root/logs"
readonly rescore_fixture_root="$test_root/rescore-input"
readonly rescore_input_race_fixture_root="$test_root/rescore-input-race"
readonly rescore_swap_restore_fixture_root="$test_root/rescore-input-swap-restore"
readonly rescore_cold_evidence_swap_restore_fixture_root="$test_root/rescore-cold-evidence-swap-restore"
readonly rescore_tmp_root="$test_root/rescore-tmp"
readonly rescore_source_cold_baseline="$test_root/source-cold-manifest.json"
trap 'rm -rf "$test_root"' EXIT

for required_name in \
  FLECK_QWEN_PYTHON_EXECUTABLE \
  FLECK_QWEN_QUALIFICATION_QWEN_SOURCE \
  FLECK_QWEN_QUALIFICATION_WHISPER_SOURCE \
  FLECK_QWEN_QUALIFICATION_RESCORE_FIXTURE_ROOT; do
  [[ -n "${!required_name:-}" ]] || {
    echo "qualification-contract-failure: required environment missing: $required_name" >&2
    exit 2
  }
done

fail() {
  echo "qualification-contract-failure: $*" >&2
  exit 1
}

mkdir -m 700 "$fake_model" "$fake_site" "$poison_site" "$log_dir" "$rescore_tmp_root"
cp "$rescore_source_root/cold-manifest.json" "$rescore_source_cold_baseline"
[[ -x "$runner" ]] || fail "qualification runner must remain executable"
bash -n "$runner"
printf '%s\n' 'from pathlib import Path; Path("'"$marker"'").write_text("poison")' >"$poison_site/sitecustomize.py"

for name in \
  .gitattributes \
  README.md \
  chat_template.jinja \
  config.json \
  model.safetensors \
  model.safetensors.index.json \
  preprocessor_config.json \
  processor_config.json \
  tokenizer.json \
  tokenizer_config.json \
  video_preprocessor_config.json \
  vocab.json \
  LICENSE.Qwen-upstream-Apache-2.0
do
  case "$name" in
    config.json|model.safetensors.index.json|preprocessor_config.json|processor_config.json|tokenizer.json|tokenizer_config.json|video_preprocessor_config.json|vocab.json)
      printf '{}\n' >"$fake_model/$name"
      ;;
    *)
      printf 'contract fixture %s\n' "$name" >"$fake_model/$name"
      ;;
  esac
done

"$python" -I -S - "$fake_model" "$fake_manifest" "$fake_responses" "$corpus" <<'PY'
import base64
import hashlib
import json
import os
import sys
from pathlib import Path

model, manifest, responses, corpus = map(Path, sys.argv[1:])
names = sorted(path.name for path in model.iterdir())
manifest_value = {}
for path in sorted(model.iterdir()):
    data = path.read_bytes()
    manifest_value[path.name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
with manifest.open("w", encoding="utf-8") as handle:
    json.dump(manifest_value, handle, sort_keys=True, indent=2)
    handle.write("\n")
cases = json.loads(corpus.read_text(encoding="utf-8"))["cases"]
response_map = {}
for case in cases:
    text = case["rawBaseline"]
    if case["id"] == "qwen-asr-en_us-02":
        text = text + " please"
    elif case["id"] == "stress-url-path":
        response_map[case["id"]] = "not JSON"
        continue
    elif case["id"] == "stress-name-destination":
        text = "send the report to Office"
    response_map[case["id"]] = json.dumps({"text": text}, ensure_ascii=False, separators=(",", ":"))
with responses.open("w", encoding="utf-8") as handle:
    json.dump(response_map, handle, ensure_ascii=False, sort_keys=True, indent=2)
    handle.write("\n")
PY

make_rescore_fixture() {
  local source_root="$1"
  local destination_root="$2"
  "$python" -I -S - "$source_root" "$destination_root" "$corpus" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

source_root, destination_root, current_corpus = map(Path, sys.argv[1:])
destination_root.mkdir(mode=0o700)

def copy_file(raw):
    source = Path(raw)
    if os.path.realpath(source) != str(source) or source.is_symlink() or not source.is_file():
        raise SystemExit(f"fixture source is not a canonical regular file: {source}")
    destination = destination_root / source.name
    if destination.exists():
        if destination.read_bytes() != source.read_bytes():
            raise SystemExit(f"fixture basename collision: {source.name}")
    else:
        shutil.copyfile(source, destination)
    return str(destination)

manifest = json.loads((source_root / "accepted-run-manifest.json").read_text(encoding="utf-8"))
rewritten_manifest = []
for entry in manifest:
    rewritten = dict(entry)
    rewritten["evidencePath"] = copy_file(entry["evidencePath"])
    rewritten["summaryPath"] = copy_file(entry["summaryPath"])
    rewritten_manifest.append(rewritten)

cold_manifest = json.loads((source_root / "cold-manifest.json").read_text(encoding="utf-8"))
rewritten_cold_manifest = []
for entry in cold_manifest:
    rewritten = dict(entry)
    rewritten["evidencePath"] = copy_file(entry["evidencePath"])
    rewritten_cold_manifest.append(rewritten)

for name in (
    "cancellation.json",
    "qualification-provenance.json",
):
    shutil.copyfile(source_root / name, destination_root / name)
shutil.copyfile(current_corpus, destination_root / "qualification-corpus-v1.json")

(destination_root / "accepted-run-manifest.json").write_text(
    json.dumps(rewritten_manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
    encoding="utf-8",
)
(destination_root / "cold-manifest.json").write_text(
    json.dumps(rewritten_cold_manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

shell_guard_output="$test_root/shell-guard-output"
mkdir -m 700 "$shell_guard_output"
set +e
FLECK_QWEN_CONTRACT_TESTS=1 /bin/sh "$runner" \
  --contract-test \
  --corpus "$corpus" \
  --qwen-source "$qwen_source" \
  --whisper-source "$whisper_source" \
  --python-executable "$python" \
  --runtime-site-packages "$fake_site" \
  --model-root "$fake_model" \
  --fake-responses "$fake_responses" \
  --test-artifact-manifest "$fake_manifest" \
  --output-root "$shell_guard_output" \
  >"$log_dir/shell-guard.stdout" 2>"$log_dir/shell-guard.stderr"
shell_guard_code=$?
set -e
[[ "$shell_guard_code" -eq 2 ]] || fail "unsupported sh invocation did not fail with status 2"
grep -F "unsupported shell; invoke this script with Bash, not sh" "$log_dir/shell-guard.stderr" >/dev/null || fail "unsupported sh invocation was not rejected early"
[[ -z "$(find "$shell_guard_output" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "unsupported sh invocation published output"
[[ ! -e "$marker" ]] || fail "unsupported sh invocation launched the accepted harness/runtime"

run_contract() {
  local name="$1"
  local output="$2"
  shift 2
  mkdir -m 700 "$output"
  set +e
  PYTHONPATH="$poison_site" PYTHONSTARTUP="$poison_site/startup.py" \
    FLECK_QWEN_CONTRACT_TESTS=1 \
    "$runner" \
    --contract-test \
    --corpus "$corpus" \
    --qwen-source "$qwen_source" \
    --whisper-source "$whisper_source" \
    --python-executable "$python" \
    --runtime-site-packages "$fake_site" \
    --model-root "$fake_model" \
    --fake-responses "$fake_responses" \
    --test-artifact-manifest "$fake_manifest" \
    --output-root "$output" \
    --process-timeout-ms 300000 \
    "$@" >"$log_dir/$name.log" 2>&1
  RUN_CODE=$?
  set -e
}

good_output="$test_root/good-output"
run_contract good "$good_output"
[[ "$RUN_CODE" -eq 0 ]] || { cat "$log_dir/good.log" >&2; fail "good fake qualification failed"; }
"$python" -I -S - "$good_output" "$marker" "$qwen_source" "$whisper_source" <<'PY'
import json
import sys
from pathlib import Path
output, marker, qwen_source, whisper_source = map(Path, sys.argv[1:])
report = json.loads((output / "qualification-report.json").read_text())
assert report["productionIntegrated"] is False
assert report["packagedAppVerified"] is False
assert report["releaseAdmitted"] is False
assert report["truthFlags"] == {
    "productionIntegrated": False,
    "packagedAppVerified": False,
    "releaseAdmitted": False,
}
assert report["qualification"]["corpusCaseCount"] == 83
assert report["qualification"]["acceptedFinalSourcesOnly"] is True
assert report["candidate"]["protectedViolationCount"] >= 1
assert report["candidate"]["automatedCandidatePass"] is False
declared_reasons = {
    "lexicalInsertion",
    "lexicalDeletion",
    "lexicalSubstitution",
    "reorderedContent",
    "ambiguousCorrection",
    "numberMeaningChanged",
}
declared_count = sum(report["candidate"]["rejectionReasons"].get(reason, 0) for reason in declared_reasons)
assert declared_count > 0
assert report["candidate"]["unexpectedLexicalChangeCount"] == declared_count
assert report["candidate"]["rejectionReasons"]["envelope_rejected"] == 1
assert report["candidate"]["rejectionReasons"]["protectedContentChanged"] >= 1
assert report["candidate"]["rejectionReasons"]["protectedViolation"] >= 1
by_id = {result["caseID"]: result for result in report["caseResults"]}
assert by_id["stress-url-path"]["qwen"]["validatorReason"] == "envelope_rejected"
assert by_id["stress-name-destination"]["qwen"]["validatorReason"] == "protectedContentChanged"
assert any(result["qwen"]["validatorReason"] in declared_reasons for result in by_id.values())
assert report["deterministicControl"]["acceptedCaseCount"] > 0
assert report["deterministicControl"]["expectedChangeMismatchCount"] == 0
assert report["timing"]["warmCaseCount"] == 83
assert report["timing"]["coldRunCount"] == 6
assert report["timing"]["warmGenerationMilliseconds"]["count"] == 83
assert report["timing"]["coldProcessToResultMilliseconds"]["count"] == 6
assert report["cancellation"]["noLatePublication"] is True
assert report["cancellation"]["nonCooperativeTermination"] is True
assert report["cancellation"]["path"] == "generation-deadline"
assert not marker.exists()
for path in output.glob("*.jsonl"):
    for line in path.read_text().splitlines():
        if line.strip():
            value = json.loads(line)
            generation = value["generation"]
            assert generation["requestCount"] == 1
            assert generation["retryCount"] == 0
assert report["qualificationProvenance"]["acceptedFinalSourcesOnly"] is True
assert any(item["path"] == str(qwen_source) for item in report["externalSourceEvidence"])
assert any(item["path"] == str(whisper_source) for item in report["externalSourceEvidence"])
PY

make_bad_corpus() {
  local mode="$1"
  local destination="$2"
  "$python" -I -S - "$corpus" "$destination" "$mode" <<'PY'
import json
import sys
from pathlib import Path
source, destination, mode = sys.argv[1:]
text = Path(source).read_text(encoding="utf-8")
if mode == "duplicate":
    text = text.replace('"schemaVersion": 1,', '"schemaVersion": 1,\n  "schemaVersion": 1,', 1)
    Path(destination).write_text(text, encoding="utf-8")
    raise SystemExit(0)
value = json.loads(text)
if mode == "hash":
    next(case for case in value["cases"] if case["sourceEvidence"]["engine"] == "qwen")["sourceEvidence"]["sha256"] = "0" * 64
elif mode == "unknown":
    value["cases"][0]["notAllowed"] = True
else:
    raise SystemExit(mode)
Path(destination).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

bad_hash="$test_root/bad-hash.json"
make_bad_corpus hash "$bad_hash"
run_contract bad-hash "$test_root/bad-hash-output" --corpus "$bad_hash"
[[ "$RUN_CODE" -ne 0 ]] || fail "source hash mismatch unexpectedly passed"
grep -F "source evidence hash mismatch" "$log_dir/bad-hash.log" >/dev/null || fail "hash mismatch was not reported"

bad_unknown="$test_root/bad-unknown.json"
make_bad_corpus unknown "$bad_unknown"
run_contract bad-unknown "$test_root/bad-unknown-output" --corpus "$bad_unknown"
[[ "$RUN_CODE" -ne 0 ]] || fail "unknown corpus key unexpectedly passed"
grep -F "case key set mismatch" "$log_dir/bad-unknown.log" >/dev/null || fail "unknown corpus key was not reported"

bad_duplicate="$test_root/bad-duplicate.json"
make_bad_corpus duplicate "$bad_duplicate"
run_contract bad-duplicate "$test_root/bad-duplicate-output" --corpus "$bad_duplicate"
[[ "$RUN_CODE" -ne 0 ]] || fail "duplicate corpus key unexpectedly passed"
grep -F "duplicate JSON key" "$log_dir/bad-duplicate.log" >/dev/null || fail "duplicate corpus key was not reported"

older_qwen_source="$test_root/older-qwen-source.jsonl"
cp "$qwen_source" "$older_qwen_source"
printf '\n' >>"$older_qwen_source"
run_contract old-source "$test_root/old-source-output" --qwen-source "$older_qwen_source"
[[ "$RUN_CODE" -ne 0 ]] || fail "older Qwen evidence unexpectedly passed"
grep -F "source evidence hash mismatch" "$log_dir/old-source.log" >/dev/null || fail "older Qwen evidence was not rejected"

race_output="$test_root/race-output"
race_log="$log_dir/race.log"
mkdir -m 700 "$race_output"
set +e
PYTHONPATH="$poison_site" FLECK_QWEN_CONTRACT_TESTS=1 \
  "$runner" --contract-test --corpus "$corpus" \
  --qwen-source "$qwen_source" --whisper-source "$whisper_source" \
  --python-executable "$python" --runtime-site-packages "$fake_site" \
  --model-root "$fake_model" --fake-responses "$fake_responses" \
  --test-artifact-manifest "$fake_manifest" --output-root "$race_output" \
  --process-timeout-ms 300000 --test-pause-before-publish-ms 1000 \
  >"$race_log" 2>&1 &
race_pid=$!
set -e
race_count=0
for iteration in $(seq 1 1800); do
  race_count="$(find "$race_output" -mindepth 1 -maxdepth 1 -type f -print | wc -l | tr -d ' ')"
  if [[ "$race_count" -ge 14 ]] && grep -F "staging complete; holding output anchor" "$race_log" >/dev/null 2>&1; then break; fi
  sleep 0.05
done
[[ "$race_count" -ge 14 ]] || { cat "$race_log" >&2; fail "race probe did not reach accepted publication boundary"; }
mv "$race_output" "$test_root/race-old"
mkdir -m 700 "$race_output"
set +e
wait "$race_pid"
race_code=$?
set -e
[[ "$race_code" -ne 0 ]] || fail "output-root replacement race unexpectedly passed"
grep -F "output directory identity changed" "$race_log" >/dev/null || { cat "$race_log" >&2; fail "output-root replacement was not rejected"; }
[[ ! -e "$race_output/qualification-report.json" ]] || fail "race published aggregate evidence into replacement root"

run_rescore_race() {
  local name="$1"
  local output="$2"
  local input="$3"
  local mutation="$4"
  local log="$log_dir/$name.log"
  local tmp="$rescore_tmp_root/$name"
  local expected_error
  local pid
  local ready=0
  local code
  local original
  local parent
  local backup

  mkdir -m 700 "$output" "$tmp"
  set +e
  TMPDIR="$tmp" PYTHONPATH="$poison_site" FLECK_QWEN_CONTRACT_TESTS=1 \
    bash "$runner" --rescore \
    --rescore-input-root "$input" \
    --output-root "$output" \
    --test-pause-before-rescore-publish-ms 1200 \
    >"$log" 2>&1 &
  pid=$!
  set -e
  for iteration in $(seq 1 1800); do
    if grep -F "rescore: staging complete; holding output anchor" "$log" >/dev/null 2>&1; then
      ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done
  if [[ "$ready" -ne 1 ]]; then
    set +e
    kill "$pid" 2>/dev/null
    wait "$pid"
    set -e
    cat "$log" >&2 || true
    fail "$name did not reach deterministic rescore publication boundary"
  fi

  case "$mutation" in
    destination)
      original="${output}.original"
      mv "$output" "$original"
      mkdir -m 700 "$output"
      expected_error="rescore output directory identity changed"
      ;;
    parent)
      parent="$(dirname "$output")"
      original="${parent}.original"
      mv "$parent" "$original"
      mkdir -m 700 "$parent"
      mkdir -m 700 "$output"
      expected_error="rescore output parent identity changed"
      ;;
    input)
      backup="$input/cold-manifest.original.json"
      mv "$input/cold-manifest.json" "$backup"
      "$python" -I -S - "$input/cold-manifest.json" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text("[]\n", encoding="utf-8")
PY
      expected_error="immutable rescore input changed during publication check after pause"
      ;;
    *)
      fail "unknown rescore race mutation: $mutation"
      ;;
  esac

  set +e
  wait "$pid"
  code=$?
  set -e
  [[ "$code" -ne 0 ]] || fail "$name unexpectedly published rescore evidence"
  grep -F "$expected_error" "$log" >/dev/null || { cat "$log" >&2; fail "$name did not fail closed at the expected boundary"; }
  [[ ! -e "$output/qualification-report.json" && ! -e "$output/qualification-provenance.json" ]] || fail "$name published into the replacement destination"
  case "$mutation" in
    destination)
      [[ ! -e "$original/qualification-report.json" && ! -e "$original/qualification-provenance.json" ]] || fail "$name lost the original destination"
      ;;
    parent)
      [[ ! -e "$original/output/qualification-report.json" && ! -e "$original/output/qualification-provenance.json" ]] || fail "$name lost the original parent/destination"
      ;;
    input)
      "$python" -I -S - "$rescore_source_root/cold-manifest.json" "$rescore_source_cold_baseline" "$backup" "$input/cold-manifest.json" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path
source, baseline, original, competitor = map(Path, sys.argv[1:])
assert source.read_bytes() == baseline.read_bytes()
assert len(json.loads(original.read_text(encoding="utf-8"))) == 6
assert json.loads(competitor.read_text(encoding="utf-8")) == []
assert (os.stat(original).st_dev, os.stat(original).st_ino) != (os.stat(competitor).st_dev, os.stat(competitor).st_ino)
assert hashlib.sha256(original.read_bytes()).hexdigest() != hashlib.sha256(competitor.read_bytes()).hexdigest()
PY
      ;;
  esac
  [[ ! -e "$marker" ]] || fail "$name launched the Python runtime/model path"
  if grep -Eq "run-qwen-cleanup-benchmark|qwen-cleanup-benchmark" "$log"; then
    cat "$log" >&2
    fail "$name launched or referenced the accepted model harness"
  fi
  [[ -z "$(find "$tmp" -mindepth 1 -print -quit)" ]] || fail "$name leaked private staging or build files"
}

run_rescore_swap_restore() {
  local name="rescore-swap-restore"
  local output="$test_root/rescore-swap-restore-output"
  local input="$rescore_swap_restore_fixture_root"
  local log="$log_dir/$name.log"
  local tmp="$rescore_tmp_root/$name"
  local target="$input/cold-manifest.json"
  local original="$input/cold-manifest.original.json"
  local competitor="$input/cold-manifest.competitor.json"
  local baseline="$test_root/$name-baseline.json"
  local pid
  local code
  local before_ready=0
  local after_ready=0

  mkdir -m 700 "$output" "$tmp"
  "$python" -I -S - "$target" "$baseline" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
identity = os.stat(source)
destination.write_text(json.dumps({
    "dev": identity.st_dev,
    "ino": identity.st_ino,
    "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
}) + "\n", encoding="utf-8")
PY
  set +e
  TMPDIR="$tmp" PYTHONPATH="$poison_site" FLECK_QWEN_CONTRACT_TESTS=1 \
    bash "$runner" --rescore \
    --rescore-input-root "$input" \
    --output-root "$output" \
    --test-pause-around-rescore-report-read-ms 1200 \
    >"$log" 2>&1 &
  pid=$!
  set -e
  for iteration in $(seq 1 1800); do
    if grep -F "before immutable snapshot report read" "$log" >/dev/null 2>&1; then
      before_ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.05
  done
  [[ "$before_ready" -eq 1 ]] || { cat "$log" >&2 || true; fail "$name did not reach the snapshot-read boundary"; }
  mv "$target" "$original"
  "$python" -I -S - "$target" <<'PY'
import sys
from pathlib import Path
Path(sys.argv[1]).write_text("[]\n", encoding="utf-8")
PY
  for iteration in $(seq 1 1800); do
    if grep -F "after immutable snapshot report read" "$log" >/dev/null 2>&1; then
      after_ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.05
  done
  [[ "$after_ready" -eq 1 ]] || { cat "$log" >&2 || true; fail "$name did not prove snapshot consumption"; }
  mv "$target" "$competitor"
  mv "$original" "$target"
  set +e
  wait "$pid"
  code=$?
  set -e
  [[ "$code" -eq 0 ]] || { cat "$log" >&2 || true; fail "$name did not publish after swap/restore"; }
  "$python" -I -S - "$output" "$target" "$competitor" "$baseline" "$input" "$rescore_source_root" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path
output, target, competitor, baseline, fixture_root, source_root = map(Path, sys.argv[1:])
report = json.loads((output / "qualification-report.json").read_text(encoding="utf-8"))
assert report["acceptedHarnessRuns"] and len(report["acceptedHarnessRuns"]) == 7
assert report["coldManifest"]["caseCount"] == 6
assert report["cancellation"]["noLatePublication"] is True
provenance = json.loads((output / "qualification-provenance.json").read_text(encoding="utf-8"))
input_files = provenance["inputFiles"]
snapshot_hashes = provenance["verifiedSnapshotHashes"]
assert len(input_files) == 19
assert len(snapshot_hashes) == 20
warm_summary = next(item for item in input_files if item["role"] == "warmSummary")
fixture_manifest = json.loads((fixture_root / "accepted-run-manifest.json").read_text(encoding="utf-8"))
source_manifest = json.loads((source_root / "accepted-run-manifest.json").read_text(encoding="utf-8"))
fixture_warm_path = Path(next(item for item in fixture_manifest if item["label"] == "warm")["summaryPath"])
source_warm_path = Path(next(item for item in source_manifest if item["label"] == "warm")["summaryPath"])
assert source_warm_path.name == "qwen-cleanup-benchmark-20260820T213512Z-32571.summary.json"
assert warm_summary["path"] == str(fixture_warm_path)
expected_warm_bytes = fixture_warm_path.read_bytes()
source_warm_bytes = source_warm_path.read_bytes()
expected_warm_hash = hashlib.sha256(expected_warm_bytes).hexdigest()
assert expected_warm_bytes == source_warm_bytes
assert warm_summary["bytes"] == len(expected_warm_bytes)
assert warm_summary["sha256"] == expected_warm_hash
assert snapshot_hashes["warmSummary"] == expected_warm_hash
assert "snapshotPath" not in warm_summary
assert "currentCorpus" in snapshot_hashes
expected = json.loads(baseline.read_text(encoding="utf-8"))
actual = os.stat(target)
assert (actual.st_dev, actual.st_ino) == (expected["dev"], expected["ino"])
assert hashlib.sha256(target.read_bytes()).hexdigest() == expected["sha256"]
competitor_stat = os.stat(competitor)
assert (competitor_stat.st_dev, competitor_stat.st_ino) != (actual.st_dev, actual.st_ino)
assert json.loads(competitor.read_text(encoding="utf-8")) == []
PY
  [[ ! -e "$marker" ]] || fail "$name launched the Python runtime/model path"
  if grep -Eq "run-qwen-cleanup-benchmark|qwen-cleanup-benchmark" "$log"; then
    cat "$log" >&2
    fail "$name launched or referenced the accepted model harness"
  fi
  [[ -z "$(find "$tmp" -mindepth 1 -print -quit)" ]] || fail "$name leaked private staging or build files"
}

run_rescore_cold_evidence_swap_restore() {
  local name="rescore-cold-evidence-swap-restore"
  local output="$test_root/rescore-cold-evidence-swap-restore-output"
  local input="$rescore_cold_evidence_swap_restore_fixture_root"
  local log="$log_dir/$name.log"
  local tmp="$rescore_tmp_root/$name"
  local target
  local original
  local competitor
  local baseline="$test_root/$name-baseline.json"
  local pid
  local code
  local before_ready=0
  local after_ready=0

  target="$($python -I -S - "$input/cold-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(next(item["evidencePath"] for item in manifest if item["caseID"] == "qwen-asr-en_us-01"))
PY
)"
  original="$target.original"
  competitor="$target.competitor"
  mkdir -m 700 "$output" "$tmp"
  "$python" -I -S - "$target" "$baseline" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
identity = os.stat(source)
destination.write_text(json.dumps({
    "bytes": source.stat().st_size,
    "dev": identity.st_dev,
    "ino": identity.st_ino,
    "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
}) + "\n", encoding="utf-8")
PY
  set +e
  TMPDIR="$tmp" PYTHONPATH="$poison_site" FLECK_QWEN_CONTRACT_TESTS=1 \
    bash "$runner" --rescore \
    --rescore-input-root "$input" \
    --output-root "$output" \
    --test-pause-around-rescore-cold-score-ms 1200 \
    >"$log" 2>&1 &
  pid=$!
  set -e
  for iteration in $(seq 1 1800); do
    if grep -F "before verified cold snapshot score" "$log" >/dev/null 2>&1; then
      before_ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.05
  done
  [[ "$before_ready" -eq 1 ]] || { cat "$log" >&2 || true; fail "$name did not reach the scoring boundary"; }
  mv "$target" "$original"
  "$python" -I -S - "$target" <<'PY'
import sys
from pathlib import Path
Path(sys.argv[1]).write_text("[]\n", encoding="utf-8")
PY
  for iteration in $(seq 1 1800); do
    if grep -F "after verified cold snapshot score" "$log" >/dev/null 2>&1; then
      after_ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.05
  done
  [[ "$after_ready" -eq 1 ]] || { cat "$log" >&2 || true; fail "$name did not complete scoring with the competitor installed"; }
  mv "$target" "$competitor"
  mv "$original" "$target"
  set +e
  wait "$pid"
  code=$?
  set -e
  [[ "$code" -eq 0 ]] || { cat "$log" >&2 || true; fail "$name did not publish after cold-evidence swap/restore"; }

  "$python" -I -S - "$output" "$target" "$competitor" "$baseline" "$input" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path
output, target, competitor, baseline, input_root = map(Path, sys.argv[1:])
report = json.loads((output / "qualification-report.json").read_text(encoding="utf-8"))
provenance = json.loads((output / "qualification-provenance.json").read_text(encoding="utf-8"))
cold_manifest = json.loads((input_root / "cold-manifest.json").read_text(encoding="utf-8"))
accepted_manifest = json.loads((input_root / "accepted-run-manifest.json").read_text(encoding="utf-8"))
warm_path = Path(next(item["evidencePath"] for item in accepted_manifest if item["label"] == "warm"))
expected_evidence = [("warmEvidence", warm_path)] + [
    (f"coldEvidence:{item['caseID']}", Path(item["evidencePath"]))
    for item in cold_manifest
]
report_evidence = {item["path"]: item for item in report["evidenceFiles"]}
bindings = {item["role"]: item for item in report["rescore"]["evidenceBindings"]}
expected_rss = []
for role, path in expected_evidence:
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    report_item = report_evidence.get(str(path))
    assert report_item is not None
    assert report_item["bytes"] == len(data)
    assert report_item["sha256"] == digest
    binding = bindings[role]
    assert binding["path"] == str(path)
    assert binding["bytes"] == len(data)
    assert binding["sha256"] == digest
    assert binding["computedFrom"] == "private-verified-snapshot-bytes"
    for line in data.splitlines():
        if line.strip():
            expected_rss.append(json.loads(line)["generation"]["maxRssBytes"])
assert report["rescore"]["evidenceMetricsSource"] == "private-verified-snapshot-bytes"
assert report["rescore"]["coldEvidenceRSSSource"] == "private-verified-cold-evidence-snapshots"
assert report["timing"]["maxRssBytes"] == max(expected_rss)
assert all("rescore-snapshots" not in item["path"] for item in report["evidenceFiles"])
serialized_report = json.dumps(report, ensure_ascii=False, sort_keys=True)
serialized_provenance = json.dumps(provenance, ensure_ascii=False, sort_keys=True)
assert "rescore-snapshots" not in serialized_report
assert "rescore-snapshots" not in serialized_provenance
target_baseline = json.loads(baseline.read_text(encoding="utf-8"))
target_stat = os.stat(target)
assert (target_stat.st_dev, target_stat.st_ino) == (target_baseline["dev"], target_baseline["ino"])
assert target.stat().st_size == target_baseline["bytes"]
assert hashlib.sha256(target.read_bytes()).hexdigest() == target_baseline["sha256"]
competitor_stat = os.stat(competitor)
assert (competitor_stat.st_dev, competitor_stat.st_ino) != (target_stat.st_dev, target_stat.st_ino)
assert competitor.read_bytes() == b"[]\n"
target_receipt = next(item for item in provenance["inputFiles"] if item["role"] == "coldEvidence:qwen-asr-en_us-01")
assert target_receipt["path"] == str(target)
assert target_receipt["sha256"] == target_baseline["sha256"]
assert "snapshotPath" not in target_receipt
PY
  [[ ! -e "$marker" ]] || fail "$name launched the Python runtime/model path"
  if grep -Eq "run-qwen-cleanup-benchmark|qwen-cleanup-benchmark" "$log"; then
    cat "$log" >&2
    fail "$name launched or referenced the accepted model harness"
  fi
  [[ -z "$(find "$tmp" -mindepth 1 -print -quit)" ]] || fail "$name leaked private staging or build files"
}

make_rescore_fixture "$rescore_source_root" "$rescore_fixture_root"
make_rescore_fixture "$rescore_source_root" "$rescore_input_race_fixture_root"
make_rescore_fixture "$rescore_source_root" "$rescore_swap_restore_fixture_root"
make_rescore_fixture "$rescore_source_root" "$rescore_cold_evidence_swap_restore_fixture_root"
run_rescore_race rescore-destination-race "$test_root/rescore-destination-output" "$rescore_fixture_root" destination
mkdir -m 700 "$test_root/rescore-parent"
run_rescore_race rescore-parent-race "$test_root/rescore-parent/output" "$rescore_fixture_root" parent
run_rescore_race rescore-input-race "$test_root/rescore-input-output" "$rescore_input_race_fixture_root" input
run_rescore_swap_restore
run_rescore_cold_evidence_swap_restore

echo "qualification contract tests: PASS"
