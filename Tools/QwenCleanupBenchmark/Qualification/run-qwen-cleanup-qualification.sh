#!/usr/bin/env bash

# This check must remain POSIX-syntax and precede Bash-only options/arrays so
# an explicit `sh runner ...` fails before any validation, harness, or model work.
if [ "${BASH##*/}" != "bash" ] || [ "${POSIXLY_CORRECT:-}" = "y" ]; then
  echo "qwen-cleanup-qualification-error: unsupported shell; invoke this script with Bash, not sh" >&2
  exit 2
fi

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(git -C "$script_dir/../../.." rev-parse --show-toplevel)"
readonly qualification_dir="$script_dir"
readonly accepted_runner="$repo_root/Tools/QwenCleanupBenchmark/run-qwen-cleanup-benchmark.sh"
readonly scorer_source="$qualification_dir/score_qwen_cleanup_qualification.swift"
readonly corpus_source="$qualification_dir/corpus-v1.json"
python_executable="${FLECK_QWEN_PYTHON_EXECUTABLE:-}"
runtime_site_packages="${FLECK_QWEN_RUNTIME_SITE_PACKAGES:-}"
model_root="${FLECK_QWEN_MODEL_ROOT:-}"
output_root="${FLECK_QWEN_QUALIFICATION_OUTPUT_ROOT:-}"
corpus_path="$corpus_source"
qwen_source="${FLECK_QWEN_QUALIFICATION_QWEN_SOURCE:-}"
whisper_source="${FLECK_QWEN_QUALIFICATION_WHISPER_SOURCE:-}"
mode=""
rescore_input_root=""
fake_responses=""
test_manifest=""
process_timeout_ms=300000
test_sleep_ms=0
test_pause_before_publish_ms=0
test_pause_before_rescore_publish_ms=0
test_pause_around_rescore_report_read_ms=0
test_pause_around_rescore_cold_score_ms=0
cancel_process_timeout_ms=100
cancel_sleep_ms=0

fail() {
  echo "qwen-cleanup-qualification-error: $*" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
Usage:
  run-qwen-cleanup-qualification.sh --real [options]
  run-qwen-cleanup-qualification.sh --contract-test --fake-responses PATH --test-artifact-manifest PATH [options]
  run-qwen-cleanup-qualification.sh --rescore --rescore-input-root PATH --output-root PATH

The real mode uses only the exact already-downloaded Qwen runtime/model and writes
to a new external output directory. The contract mode is fake-only. Rescore mode
uses only immutable previously published evidence and launches no harness/model.
External paths are required through CLI options or the corresponding FLECK_QWEN_*
environment variables; nothing is downloaded or reconfigured.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --real)
      [[ -z "$mode" ]] || usage
      mode="real"
      shift
      ;;
    --contract-test)
      [[ -z "$mode" ]] || usage
      mode="contract"
      shift
      ;;
    --rescore)
      [[ -z "$mode" ]] || usage
      mode="rescore"
      shift
      ;;
    --corpus)
      [[ $# -ge 2 ]] || usage
      corpus_path="$2"
      shift 2
      ;;
    --qwen-source)
      [[ $# -ge 2 ]] || usage
      qwen_source="$2"
      shift 2
      ;;
    --whisper-source)
      [[ $# -ge 2 ]] || usage
      whisper_source="$2"
      shift 2
      ;;
    --python-executable)
      [[ $# -ge 2 ]] || usage
      python_executable="$2"
      shift 2
      ;;
    --runtime-site-packages)
      [[ $# -ge 2 ]] || usage
      runtime_site_packages="$2"
      shift 2
      ;;
    --model-root)
      [[ $# -ge 2 ]] || usage
      model_root="$2"
      shift 2
      ;;
    --output-root)
      [[ $# -ge 2 ]] || usage
      output_root="$2"
      shift 2
      ;;
    --rescore-input-root)
      [[ $# -ge 2 ]] || usage
      rescore_input_root="$2"
      shift 2
      ;;
    --fake-responses)
      [[ $# -ge 2 ]] || usage
      fake_responses="$2"
      shift 2
      ;;
    --test-artifact-manifest)
      [[ $# -ge 2 ]] || usage
      test_manifest="$2"
      shift 2
      ;;
    --process-timeout-ms)
      [[ $# -ge 2 ]] || usage
      process_timeout_ms="$2"
      shift 2
      ;;
    --test-sleep-ms)
      [[ $# -ge 2 ]] || usage
      test_sleep_ms="$2"
      shift 2
      ;;
    --test-pause-before-publish-ms)
      [[ $# -ge 2 ]] || usage
      test_pause_before_publish_ms="$2"
      shift 2
      ;;
    --test-pause-before-rescore-publish-ms)
      [[ $# -ge 2 ]] || usage
      test_pause_before_rescore_publish_ms="$2"
      shift 2
      ;;
    --test-pause-around-rescore-report-read-ms)
      [[ $# -ge 2 ]] || usage
      test_pause_around_rescore_report_read_ms="$2"
      shift 2
      ;;
    --test-pause-around-rescore-cold-score-ms)
      [[ $# -ge 2 ]] || usage
      test_pause_around_rescore_cold_score_ms="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$mode" == "real" || "$mode" == "contract" || "$mode" == "rescore" ]] || usage
[[ -n "$python_executable" ]] || fail "--python-executable or FLECK_QWEN_PYTHON_EXECUTABLE is required"
[[ -n "$output_root" ]] || fail "--output-root or FLECK_QWEN_QUALIFICATION_OUTPUT_ROOT is required"
[[ "$process_timeout_ms" =~ ^[1-9][0-9]*$ ]] || fail "--process-timeout-ms must be positive"
[[ "$test_sleep_ms" =~ ^[0-9]+$ ]] || fail "--test-sleep-ms must be non-negative"
[[ "$test_pause_before_publish_ms" =~ ^[0-9]+$ ]] || fail "--test-pause-before-publish-ms must be non-negative"
[[ "$test_pause_before_rescore_publish_ms" =~ ^[0-9]+$ ]] || fail "--test-pause-before-rescore-publish-ms must be non-negative"
[[ "$test_pause_around_rescore_report_read_ms" =~ ^[0-9]+$ ]] || fail "--test-pause-around-rescore-report-read-ms must be non-negative"
[[ "$test_pause_around_rescore_cold_score_ms" =~ ^[0-9]+$ ]] || fail "--test-pause-around-rescore-cold-score-ms must be non-negative"
[[ -x "$accepted_runner" ]] || fail "accepted harness is missing or not executable: $accepted_runner"
[[ -f "$scorer_source" ]] || fail "scorer source is missing: $scorer_source"
[[ -f "$corpus_path" ]] || fail "corpus is missing: $corpus_path"
if [[ "$mode" == "real" && "$test_pause_before_publish_ms" != "0" ]]; then
  fail "--test-pause-before-publish-ms is contract-test-only"
fi
if [[ "$mode" == "real" && "$test_sleep_ms" != "0" ]]; then
  fail "--test-sleep-ms is contract-test-only"
fi
if [[ "$mode" == "rescore" ]]; then
  [[ -n "$rescore_input_root" ]] || fail "--rescore requires --rescore-input-root"
  [[ "$test_pause_before_publish_ms" == "0" ]] || fail "--test-pause-before-publish-ms is rescore-incompatible"
  [[ "$test_sleep_ms" == "0" ]] || fail "--test-sleep-ms is rescore-incompatible"
fi
if [[ "$test_pause_before_rescore_publish_ms" != "0" ]]; then
  [[ "$mode" == "rescore" ]] || fail "--test-pause-before-rescore-publish-ms is rescore-only"
  [[ "${FLECK_QWEN_CONTRACT_TESTS:-}" == "1" ]] || fail "--test-pause-before-rescore-publish-ms is contract-test-only"
fi
if [[ "$test_pause_around_rescore_report_read_ms" != "0" ]]; then
  [[ "$mode" == "rescore" ]] || fail "--test-pause-around-rescore-report-read-ms is rescore-only"
  [[ "${FLECK_QWEN_CONTRACT_TESTS:-}" == "1" ]] || fail "--test-pause-around-rescore-report-read-ms is contract-test-only"
fi
if [[ "$test_pause_around_rescore_cold_score_ms" != "0" ]]; then
  [[ "$mode" == "rescore" ]] || fail "--test-pause-around-rescore-cold-score-ms is rescore-only"
  [[ "${FLECK_QWEN_CONTRACT_TESTS:-}" == "1" ]] || fail "--test-pause-around-rescore-cold-score-ms is contract-test-only"
fi
if [[ "$mode" == "contract" ]]; then
  [[ -n "$fake_responses" ]] || fail "--contract-test requires --fake-responses"
  [[ -n "$test_manifest" ]] || fail "--contract-test requires --test-artifact-manifest"
  [[ "${FLECK_QWEN_CONTRACT_TESTS:-}" == "1" ]] || fail "contract mode is restricted to the fake contract suite"
fi
if [[ "$mode" != "rescore" ]]; then
  [[ -n "$qwen_source" ]] || fail "--qwen-source or FLECK_QWEN_QUALIFICATION_QWEN_SOURCE is required"
  [[ -n "$whisper_source" ]] || fail "--whisper-source or FLECK_QWEN_QUALIFICATION_WHISPER_SOURCE is required"
  [[ -n "$runtime_site_packages" ]] || fail "--runtime-site-packages or FLECK_QWEN_RUNTIME_SITE_PACKAGES is required"
  [[ -n "$model_root" ]] || fail "--model-root or FLECK_QWEN_MODEL_ROOT is required"
fi

require_absolute_safe() {
  local path="$1"
  local label="$2"
  [[ "$path" == /* ]] || fail "$label must be an absolute path"
  [[ "$path" != *[[:cntrl:]]* ]] || fail "$label contains a control character"
  [[ "$path" != */../* && "$path" != */.. ]] || fail "$label contains path traversal"
}

require_canonical() {
  local path="$1"
  local label="$2"
  require_absolute_safe "$path" "$label"
  [[ -e "$path" ]] || fail "$label does not exist: $path"
  [[ "$(realpath "$path")" == "$path" ]] || fail "$label must be canonical and not a symlink: $path"
  local probe="$path"
  while [[ "$probe" != "/" ]]; do
    [[ ! -L "$probe" ]] || fail "$label has a symlinked ancestor: $probe"
    probe="${probe%/*}"
    [[ -n "$probe" ]] || probe="/"
  done
}

require_file() {
  local path="$1"
  local label="$2"
  require_canonical "$path" "$label"
  [[ -f "$path" && ! -L "$path" ]] || fail "$label must be a regular file: $path"
}

require_directory() {
  local path="$1"
  local label="$2"
  require_canonical "$path" "$label"
  [[ -d "$path" && ! -L "$path" ]] || fail "$label must be a directory: $path"
}

ensure_output_root() {
  require_absolute_safe "$output_root" "output root"
  if [[ ! -e "$output_root" ]]; then
    local parent
    parent="$(dirname "$output_root")"
    require_directory "$parent" "output root parent"
    mkdir -m 700 "$output_root"
  fi
  require_directory "$output_root" "output root"
  if find "$output_root" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    fail "output root must be a new empty directory: $output_root"
  fi
  local canonical_repo
  canonical_repo="$(realpath "$repo_root")"
  case "$(realpath "$output_root")/" in
    "$canonical_repo/"*) fail "output root must be outside the repository" ;;
  esac
  case "$output_root/" in
    *.app/*|*.app/) fail "output root must be outside an app bundle" ;;
  esac
}

require_file "$corpus_path" "qualification corpus"
require_file "$scorer_source" "qualification scorer"
require_file "$python_executable" "Python executable"
if [[ "$mode" != "rescore" ]]; then
  require_file "$qwen_source" "Qwen source evidence"
  require_file "$whisper_source" "Whisper source evidence"
  require_directory "$runtime_site_packages" "runtime site-packages"
  require_directory "$model_root" "model root"
fi
if [[ "$mode" == "contract" ]]; then
  require_file "$fake_responses" "fake responses"
  require_file "$test_manifest" "test artifact manifest"
fi
if [[ "$mode" == "rescore" ]]; then
  require_directory "$rescore_input_root" "rescore input root"
fi
ensure_output_root

run_stdlib_python() {
  env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" PYTHONDONTWRITEBYTECODE=1 "$python_executable" -I -S "$@"
}

private_root=""
swift_build_dir=""
cleanup() {
  if [[ -n "$swift_build_dir" && -d "$swift_build_dir" ]]; then
    rm -rf "$swift_build_dir"
  fi
  if [[ -n "$private_root" && -d "$private_root" ]]; then
    rm -rf "$private_root"
  fi
}
trap cleanup EXIT

private_root="$(realpath "$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-qualification.XXXXXX")")"
chmod 700 "$private_root"
case "$private_root/" in
  "$(realpath "$repo_root")/"*|"$output_root/"*) fail "private staging escaped outside repo/output root" ;;
esac
mkdir -m 700 "$private_root/staging"
staging_dir="$private_root/staging"
accepted_fixture="$private_root/accepted-fixture.json"
corpus_metadata="$private_root/corpus-metadata.json"
cold_selection="$private_root/cold-selection.json"
accepted_runs="$private_root/accepted-runs.jsonl"
: > "$accepted_runs"
chmod 600 "$accepted_runs"

validate_corpus() {
  run_stdlib_python - \
    "$corpus_path" \
    "$qwen_source" \
    "$whisper_source" \
    "$repo_root" \
    "$accepted_fixture" \
    "$corpus_metadata" \
    "$cold_selection" <<'PY'
import hashlib
import json
import os
import re
import stat
import sys
from collections import Counter
from pathlib import Path

corpus_path, qwen_path, whisper_path, repo_root, fixture_path, metadata_path, cold_path = sys.argv[1:]
EXPECTED_QWEN_LOCATOR = "historical-external-evidence:qwen3-asr-0.6b-int8-20260821-real-5/transcripts.jsonl"
EXPECTED_WHISPER_LOCATOR = "historical-external-evidence:whisper-small-control/transcripts.jsonl"
CASE_KEYS = {
    "id",
    "language",
    "sourceClass",
    "rawBaseline",
    "protectedForms",
    "protectedExpectations",
    "sourceEvidence",
    "deterministicCleanupExpectedToChange",
    "tags",
}
SOURCE_KEYS = {
    "audioSHA256",
    "engine",
    "field",
    "kind",
    "path",
    "recordID",
    "sha256",
}
EXPECTATION_KEYS = {"comparison", "kind", "text"}
EXPECTED_COUNTS = {
    "byLanguage": {"english": 33, "mandarin": 25, "mixed": 25},
    "asrByEngine": {"qwen": 36, "whisper": 36},
    "asrByLanguage": {"english": 24, "mandarin": 24, "mixed": 24},
    "protectedStress": 11,
    "total": 83,
}
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$")

def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

def parse_json(data, label):
    try:
        return json.loads(
            data.decode("utf-8"),
            object_pairs_hook=reject_duplicates,
            parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite number {value}")),
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"corpus validation failed: invalid {label}: {error}")

def canonical_file(raw, label):
    if not isinstance(raw, str) or not raw.startswith("/") or ".." in Path(raw).parts:
        raise SystemExit(f"corpus validation failed: {label} is not an absolute traversal-free path")
    if any(ord(character) < 0x20 or ord(character) == 0x7f for character in raw):
        raise SystemExit(f"corpus validation failed: {label} contains a control character")
    path = Path(raw)
    if os.path.realpath(path) != raw:
        raise SystemExit(f"corpus validation failed: {label} is not canonical: {raw}")
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            if stat.S_ISLNK(os.lstat(current).st_mode):
                raise SystemExit(f"corpus validation failed: {label} has a symlinked ancestor: {current}")
        except FileNotFoundError:
            raise SystemExit(f"corpus validation failed: {label} does not exist: {raw}")
    try:
        mode = os.lstat(path).st_mode
    except FileNotFoundError:
        raise SystemExit(f"corpus validation failed: {label} does not exist: {raw}")
    if not stat.S_ISREG(mode) or stat.S_ISLNK(mode):
        raise SystemExit(f"corpus validation failed: {label} is not a regular file: {raw}")
    return path

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()

def validate_text(value, label, allow_empty=False):
    if not isinstance(value, str) or (not allow_empty and not value):
        raise SystemExit(f"corpus validation failed: {label} must be a non-empty string")
    if any(ord(character) < 0x20 and character not in "\n\r\t" for character in value):
        raise SystemExit(f"corpus validation failed: {label} contains a control character")
    if len(value.encode("utf-8")) > 8192:
        raise SystemExit(f"corpus validation failed: {label} exceeds 8192 UTF-8 bytes")
    return value

def lexical_count(value):
    tokens = re.findall(
        r"[A-Za-z]+(?:['’][A-Za-z]+)?|[\u3400-\u9fff]+|\d+(?:[.,:/-]\d+)*|[^\s\w]",
        value,
        flags=re.UNICODE,
    )
    return len(tokens)

def read_qwen(path):
    records = {}
    for line_number, line in enumerate(path.read_bytes().splitlines(), 1):
        if not line.strip():
            continue
        value = parse_json(line, f"Qwen JSONL line {line_number}")
        if not isinstance(value, dict) or not isinstance(value.get("id"), str):
            raise SystemExit(f"corpus validation failed: malformed Qwen record {line_number}")
        key = value["id"]
        if key in records:
            raise SystemExit(f"corpus validation failed: duplicate Qwen record {key}")
        records[key] = value
    return records

def read_whisper(path):
    decoder = json.JSONDecoder(object_pairs_hook=reject_duplicates)
    text = path.read_bytes().decode("utf-8")
    records = {}
    index = 0
    while index < len(text):
        while index < len(text) and text[index].isspace():
            index += 1
        if index >= len(text):
            break
        try:
            value, index = decoder.raw_decode(text, index)
        except (json.JSONDecodeError, ValueError) as error:
            raise SystemExit(f"corpus validation failed: invalid Whisper concatenated JSON: {error}")
        if not isinstance(value, dict) or value.get("recordType") != "transcript":
            continue
        key = value.get("caseID")
        if not isinstance(key, str):
            raise SystemExit("corpus validation failed: malformed Whisper transcript identity")
        if key in records:
            raise SystemExit(f"corpus validation failed: duplicate Whisper record {key}")
        records[key] = value
    return records

def write_json(path, value):
    path = Path(path)
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8") + b"\n"
    with path.open("wb") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())

corpus_file = canonical_file(corpus_path, "corpus")
qwen_file = canonical_file(qwen_path, "Qwen source evidence")
whisper_file = canonical_file(whisper_path, "Whisper source evidence")
repo = canonical_file(str(Path(repo_root) / "Sources/FleckApp/FoundationModelDictation.swift"), "checked-in cleanup source")
corpus = parse_json(corpus_file.read_bytes(), "qualification corpus")
if not isinstance(corpus, dict):
    raise SystemExit("corpus validation failed: top-level object required")
if set(corpus) != {"cases", "corpusID", "expectedCounts", "revision", "schemaVersion"}:
    raise SystemExit("corpus validation failed: unknown or missing top-level keys")
if corpus.get("schemaVersion") != 1 or corpus.get("corpusID") != "fleck-qwen-cleanup-qualification-corpus-v1":
    raise SystemExit("corpus validation failed: schema or corpus identity mismatch")
if corpus.get("expectedCounts") != EXPECTED_COUNTS:
    raise SystemExit("corpus validation failed: expectedCounts mismatch")
if not isinstance(corpus.get("revision"), str) or "af49c07" not in corpus["revision"]:
    raise SystemExit("corpus validation failed: revision is not pinned to af49c07")
raw_cases = corpus.get("cases")
if not isinstance(raw_cases, list) or len(raw_cases) != EXPECTED_COUNTS["total"]:
    raise SystemExit("corpus validation failed: case count mismatch")
qwen_records = read_qwen(qwen_file)
whisper_records = read_whisper(whisper_file)
qwen_sha = sha256(qwen_file)
whisper_sha = sha256(whisper_file)
repo_sha = sha256(repo)
seen = set()
fixture = []
external_sources = []
language_counts = Counter()
asr_engine_counts = Counter()
asr_language_counts = Counter()
stress_count = 0
for case in raw_cases:
    if not isinstance(case, dict) or set(case) != CASE_KEYS:
        raise SystemExit("corpus validation failed: case key set mismatch")
    case_id = validate_text(case.get("id"), "case id")
    if not ID_RE.fullmatch(case_id) or case_id in seen:
        raise SystemExit(f"corpus validation failed: duplicate or path-unsafe case id {case_id}")
    seen.add(case_id)
    language = case.get("language")
    if language not in {"english", "mandarin", "mixed"}:
        raise SystemExit(f"corpus validation failed: unsupported language {case_id}")
    source_class = case.get("sourceClass")
    if not isinstance(source_class, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]{0,39}", source_class):
        raise SystemExit(f"corpus validation failed: invalid source class {case_id}")
    baseline = validate_text(case.get("rawBaseline"), f"rawBaseline {case_id}")
    if lexical_count(baseline) == 0 or lexical_count(baseline) > 80:
        raise SystemExit(f"corpus validation failed: rawBaseline exceeds 80 lexical tokens {case_id}")
    forms = case.get("protectedForms")
    if not isinstance(forms, list) or any(not isinstance(form, str) or not form for form in forms):
        raise SystemExit(f"corpus validation failed: protectedForms {case_id}")
    for form in forms:
        validate_text(form, f"protected form {case_id}")
    expectations = case.get("protectedExpectations")
    if not isinstance(expectations, list):
        raise SystemExit(f"corpus validation failed: protectedExpectations {case_id}")
    for expectation in expectations:
        if not isinstance(expectation, dict) or set(expectation) != EXPECTATION_KEYS:
            raise SystemExit(f"corpus validation failed: protected expectation key set {case_id}")
        if expectation["comparison"] != "exactSubstring":
            raise SystemExit(f"corpus validation failed: unsupported protected comparison {case_id}")
        validate_text(expectation["kind"], f"protected expectation kind {case_id}")
        validate_text(expectation["text"], f"protected expectation text {case_id}")
    evidence = case.get("sourceEvidence")
    if not isinstance(evidence, dict) or set(evidence) != SOURCE_KEYS:
        raise SystemExit(f"corpus validation failed: source evidence key set {case_id}")
    engine = evidence.get("engine")
    source_kind = evidence.get("kind")
    if source_kind == "externalBenchmark":
        if engine not in {"qwen", "whisper"} or evidence["audioSHA256"] is None:
            raise SystemExit(f"corpus validation failed: unpinned external source evidence {case_id}")
        source_path = qwen_file if engine == "qwen" else whisper_file
        expected_locator = EXPECTED_QWEN_LOCATOR if engine == "qwen" else EXPECTED_WHISPER_LOCATOR
        expected_sha = qwen_sha if engine == "qwen" else whisper_sha
        expected_field = "hypothesis" if engine == "qwen" else "rawHypothesis"
        records = qwen_records if engine == "qwen" else whisper_records
        record_id = evidence.get("recordID")
        if evidence.get("path") != expected_locator or evidence.get("sha256") != expected_sha:
            raise SystemExit(f"corpus validation failed: source evidence hash mismatch or locator mismatch {case_id}")
        if evidence.get("field") != expected_field or record_id not in records:
            raise SystemExit(f"corpus validation failed: source evidence record identity mismatch {case_id}")
        record = records[record_id]
        if record.get(expected_field) != baseline:
            raise SystemExit(f"corpus validation failed: raw baseline does not match pinned source record {case_id}")
        if record.get("language") != language or record.get("sourceClass") != source_class:
            raise SystemExit(f"corpus validation failed: source language/class mismatch {case_id}")
        if evidence.get("audioSHA256") != record.get("audioSHA256"):
            raise SystemExit(f"corpus validation failed: audio identity mismatch {case_id}")
        asr_engine_counts[engine] += 1
        asr_language_counts[language] += 1
        external_sources.append({
            "engine": engine,
            "path": str(source_path),
            "sha256": expected_sha,
            "bytes": source_path.stat().st_size,
            "recordCount": len(records),
        })
    elif source_kind == "checkedInSource":
        if engine != "none" or evidence.get("audioSHA256") is not None:
            raise SystemExit(f"corpus validation failed: checked-in source evidence is malformed {case_id}")
        if evidence.get("path") != "repo:Sources/FleckApp/FoundationModelDictation.swift":
            raise SystemExit(f"corpus validation failed: checked-in source path mismatch {case_id}")
        if evidence.get("sha256") != repo_sha:
            raise SystemExit(f"corpus validation failed: source evidence hash mismatch {case_id}")
        if source_class != "protectedStress":
            raise SystemExit(f"corpus validation failed: non-stress checked-in case {case_id}")
        stress_count += 1
    else:
        raise SystemExit(f"corpus validation failed: unpinned source evidence kind {case_id}")
    tags = case.get("tags")
    if not isinstance(tags, list) or any(not isinstance(tag, str) or not re.fullmatch(r"[a-z0-9-]{1,40}", tag) for tag in tags):
        raise SystemExit(f"corpus validation failed: path-unsafe tags {case_id}")
    if not isinstance(case.get("deterministicCleanupExpectedToChange"), bool):
        raise SystemExit(f"corpus validation failed: deterministic expectation {case_id}")
    language_counts[language] += 1
    fixture.append({
        "id": case_id,
        "rawBaseline": baseline,
        "protectedForms": forms,
        "tags": tags,
    })
external_sources = sorted({
    (entry["engine"], entry["path"], entry["sha256"], entry["bytes"], entry["recordCount"])
    for entry in external_sources
})
external_sources = [
    {"engine": engine, "path": path, "sha256": digest, "bytes": size, "recordCount": count}
    for engine, path, digest, size, count in external_sources
]
if dict(language_counts) != EXPECTED_COUNTS["byLanguage"]:
    raise SystemExit("corpus validation failed: language counts mismatch")
if dict(asr_engine_counts) != EXPECTED_COUNTS["asrByEngine"]:
    raise SystemExit("corpus validation failed: ASR engine counts mismatch")
if dict(asr_language_counts) != EXPECTED_COUNTS["asrByLanguage"] or stress_count != EXPECTED_COUNTS["protectedStress"]:
    raise SystemExit("corpus validation failed: ASR/stress counts mismatch")
if len(qwen_records) != 36 or len(whisper_records) != 36:
    raise SystemExit("corpus validation failed: final evidence record counts mismatch")
cold = []
for engine in ("qwen", "whisper"):
    for language in ("english", "mandarin", "mixed"):
        cold.append(next(item["id"] for item in fixture if item["id"].startswith(engine + "-asr-") and raw_cases[fixture.index(item)]["language"] == language))
write_json(fixture_path, fixture)
write_json(cold_path, cold)
write_json(metadata_path, {
    "schemaVersion": 1,
    "corpusID": corpus["corpusID"],
    "corpusRevision": corpus["revision"],
    "corpusFile": {
        "path": str(corpus_file),
        "bytes": corpus_file.stat().st_size,
        "sha256": sha256(corpus_file),
    },
    "sourceEvidence": external_sources + [{
        "engine": "none",
        "path": "repo:Sources/FleckApp/FoundationModelDictation.swift",
        "sha256": repo_sha,
        "bytes": repo.stat().st_size,
        "recordCount": None,
    }],
    "acceptedFinalSourcesOnly": True,
    "noMicrophoneAudioCopied": True,
    "caseCount": len(fixture),
    "coldCaseIDs": cold,
})
PY
}

if [[ "$mode" != "rescore" ]]; then
  validate_corpus
fi


write_anchor() {
  run_stdlib_python - "$output_root" "$private_root/output-anchor.json" <<'PY'
import json
import os
import sys
root, output_path = sys.argv[1:]
if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
    raise SystemExit("anchored output flags unavailable")
if os.path.realpath(root) != root:
    raise SystemExit("output root is not canonical")
parent = os.path.dirname(root)
if os.path.realpath(parent) != parent:
    raise SystemExit("output root parent is not canonical")
parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
fd = os.open(os.path.basename(root), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
try:
    identity = os.fstat(fd)
    parent_identity = os.fstat(parent_fd)
finally:
    os.close(fd)
    os.close(parent_fd)
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump({
        "dev": identity.st_dev,
        "ino": identity.st_ino,
        "parentPath": parent,
        "parentDev": parent_identity.st_dev,
        "parentIno": parent_identity.st_ino,
    }, handle, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

list_output_files() {
  find "$output_root" -mindepth 1 -maxdepth 1 -type f -print | sed "s#^$output_root/##" | LC_ALL=C sort
}

run_accepted() {
  local label="$1"
  local selected_case="$2"
  local timeout_ms="$3"
  local sleep_ms="$4"
  local stdout_path="$private_root/$label.stdout"
  local stderr_path="$private_root/$label.stderr"
  local start_ns
  local end_ns
  local code=0
  local evidence_path=""
  local summary_path=""
  local harness_mode="--smoke"
  local -a command

  if [[ "$mode" == "contract" ]]; then
    harness_mode="--contract-test"
  fi
  command=(
    "$accepted_runner"
    "$harness_mode"
    --python-executable "$python_executable"
    --runtime-site-packages "$runtime_site_packages"
    --model-root "$model_root"
    --fixture "$accepted_fixture"
    --output-root "$output_root"
    --process-timeout-ms "$timeout_ms"
  )
  if [[ -n "$selected_case" ]]; then
    command+=(--case-id "$selected_case")
  fi
  if [[ "$mode" == "contract" ]]; then
    command+=(--fake-responses "$fake_responses" --test-artifact-manifest "$test_manifest" --test-sleep-ms "$sleep_ms")
  fi
  start_ns="$(run_stdlib_python -c 'import time; print(time.monotonic_ns())')"
  set +e
  if [[ "$mode" == "contract" ]]; then
    FLECK_QWEN_CONTRACT_TESTS=1 "${command[@]}" >"$stdout_path" 2>"$stderr_path"
    code=$?
  else
    "${command[@]}" >"$stdout_path" 2>"$stderr_path"
    code=$?
  fi
  set -e
  end_ns="$(run_stdlib_python -c 'import time; print(time.monotonic_ns())')"
  RUN_ELAPSED_MS=$(( (end_ns - start_ns) / 1000000 ))
  if (( code != 0 )); then
    cat "$stderr_path" >&2 || true
    return "$code"
  fi
  evidence_path="$(sed -n 's/^qwen cleanup benchmark evidence: //p' "$stdout_path" | tail -n 1)"
  summary_path="$(sed -n 's/^qwen cleanup benchmark summary: //p' "$stdout_path" | tail -n 1)"
  [[ -n "$evidence_path" && -f "$evidence_path" && ! -L "$evidence_path" ]] || { cat "$stdout_path" >&2 || true; fail "$label accepted run did not publish evidence"; }
  [[ -n "$summary_path" && -f "$summary_path" && ! -L "$summary_path" ]] || { cat "$stdout_path" >&2 || true; fail "$label accepted run did not publish summary"; }
  [[ "$(realpath "$evidence_path")" == "$evidence_path" ]] || fail "$label evidence path is not canonical"
  [[ "$(realpath "$summary_path")" == "$summary_path" ]] || fail "$label summary path is not canonical"
  case "$evidence_path" in "$output_root/"*) ;; *) fail "$label evidence escaped output root" ;; esac
  case "$summary_path" in "$output_root/"*) ;; *) fail "$label summary escaped output root" ;; esac
  RUN_EVIDENCE="$evidence_path"
  RUN_SUMMARY="$summary_path"
  run_stdlib_python - "$accepted_runs" "$label" "$selected_case" "$RUN_ELAPSED_MS" "$RUN_EVIDENCE" "$RUN_SUMMARY" <<'PY'
import json
import os
import sys
path, label, case_id, elapsed, evidence, summary = sys.argv[1:]
with open(path, "a", encoding="utf-8") as handle:
    json.dump({
        "label": label,
        "caseID": case_id or None,
        "status": "success",
        "processToResultMilliseconds": float(elapsed),
        "evidencePath": evidence,
        "summaryPath": summary,
    }, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

run_cancellation_probe() {
  local selected_case="$1"
  local before_path="$private_root/cancellation-before.txt"
  local after_path="$private_root/cancellation-after.txt"
  local later_path="$private_root/cancellation-later.txt"
  local stdout_path="$private_root/cancellation.stdout"
  local stderr_path="$private_root/cancellation.stderr"
  local start_ns
  local end_ns
  local code=0
  local harness_mode="--smoke"
  local -a command
  list_output_files >"$before_path"
  if [[ "$mode" == "contract" ]]; then
    harness_mode="--contract-test"
  fi
  command=(
    "$accepted_runner"
    "$harness_mode"
    --python-executable "$python_executable"
    --runtime-site-packages "$runtime_site_packages"
    --model-root "$model_root"
    --fixture "$accepted_fixture"
    --output-root "$output_root"
    --case-id "$selected_case"
    --process-timeout-ms "$cancel_process_timeout_ms"
  )
  if [[ "$mode" == "contract" ]]; then
    command+=(--fake-responses "$fake_responses" --test-artifact-manifest "$test_manifest" --test-sleep-ms 2200)
  fi
  start_ns="$(run_stdlib_python -c 'import time; print(time.monotonic_ns())')"
  set +e
  if [[ "$mode" == "contract" ]]; then
    FLECK_QWEN_CONTRACT_TESTS=1 "${command[@]}" >"$stdout_path" 2>"$stderr_path"
    code=$?
  else
    "${command[@]}" >"$stdout_path" 2>"$stderr_path"
    code=$?
  fi
  set -e
  end_ns="$(run_stdlib_python -c 'import time; print(time.monotonic_ns())')"
  RUN_CANCEL_ELAPSED_MS=$(( (end_ns - start_ns) / 1000000 ))
  list_output_files >"$after_path"
  sleep 0.25
  list_output_files >"$later_path"
  if (( code == 0 )); then
    cat "$stdout_path" >&2 || true
    fail "cancellation probe unexpectedly completed and published output"
  fi
  if ! cmp -s "$before_path" "$after_path" || ! cmp -s "$after_path" "$later_path"; then
    cat "$stdout_path" >&2 || true
    cat "$stderr_path" >&2 || true
    fail "cancellation probe published evidence or late output"
  fi
  if [[ "$mode" == "contract" ]]; then
    grep -E "generation-deadline|1,500 ms|nonCooperativeTermination" "$stderr_path" >/dev/null || { cat "$stderr_path" >&2 || true; fail "contract cancellation did not prove over-deadline termination"; }
    RUN_CANCEL_PATH="generation-deadline"
  else
    RUN_CANCEL_PATH="whole-process-timeout"
  fi
  run_stdlib_python - "$private_root/cancellation.json" "$selected_case" "$RUN_CANCEL_PATH" "$RUN_CANCEL_ELAPSED_MS" "$before_path" "$after_path" "$later_path" <<'PY'
import json
import os
import sys
destination, case_id, path, elapsed, before, after, later = sys.argv[1:]
before_text = open(before, encoding="utf-8").read()
after_text = open(after, encoding="utf-8").read()
later_text = open(later, encoding="utf-8").read()
with open(destination, "w", encoding="utf-8") as handle:
    json.dump({
        "caseID": case_id,
        "status": "forced-termination",
        "path": path,
        "processElapsedMilliseconds": float(elapsed),
        "noLatePublication": before_text == after_text == later_text,
        "outputDirectoryUnchanged": before_text == after_text,
        "afterGracePeriodUnchanged": after_text == later_text,
        "nonCooperativeTermination": True,
    }, handle, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

build_scorer() {
  swift_build_dir="$(realpath "$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-qualification-swift.XXXXXX")")"
  mkdir -m 700 "$swift_build_dir/module-cache"
  swiftc -parse-as-library -emit-library -emit-module -module-name FleckCore \
    -module-cache-path "$swift_build_dir/module-cache" \
    "$repo_root/Sources/FleckCore/PersonalDictionary.swift" \
    "$repo_root/Sources/FleckCore/PersonalDictionaryResolver.swift" \
    "$repo_root/Sources/FleckCore/DictationModels.swift" \
    -o "$swift_build_dir/libFleckCore.dylib" \
    -emit-module-path "$swift_build_dir/FleckCore.swiftmodule"
  swiftc -parse-as-library -module-name FleckCleanupQualification \
    -module-cache-path "$swift_build_dir/module-cache" \
    -I "$swift_build_dir" \
    -L "$swift_build_dir" \
    -Xlinker -rpath -Xlinker "$swift_build_dir" \
    -lFleckCore \
    "$repo_root/Sources/FleckApp/CleanupLexeme.swift" \
    "$repo_root/Sources/FleckApp/CleanupProtectedSpan.swift" \
    "$repo_root/Sources/FleckApp/FaithfulCleanupValidator.swift" \
    "$repo_root/Sources/FleckApp/FoundationModelDictation.swift" \
    "$scorer_source" \
    -o "$swift_build_dir/score_qwen_cleanup_qualification"
}

verify_rescore_inputs() {
  local phase="$1"
  local metadata_path="$2"
  run_stdlib_python - "$metadata_path" "$phase" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
phase = sys.argv[2]
for item in metadata["files"] + [metadata["currentCorpus"]]:
    path = Path(item["path"])
    try:
        first = os.lstat(path)
    except FileNotFoundError:
        raise SystemExit(f"immutable rescore input changed during {phase}: {item['role']}")
    if (
        os.path.realpath(path) != str(path)
        or stat.S_ISLNK(first.st_mode)
        or not stat.S_ISREG(first.st_mode)
        or first.st_dev != item["dev"]
        or first.st_ino != item["ino"]
    ):
        raise SystemExit(f"immutable rescore input changed during {phase}: {item['role']}")
    data = path.read_bytes()
    if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
        raise SystemExit(f"immutable rescore input changed during {phase}: {item['role']}")
    snapshot = Path(item["snapshotPath"])
    try:
        snapshot_stat = os.lstat(snapshot)
    except FileNotFoundError:
        raise SystemExit(f"immutable rescore snapshot changed during {phase}: {item['role']}")
    if os.path.realpath(snapshot) != str(snapshot) or stat.S_ISLNK(snapshot_stat.st_mode) or not stat.S_ISREG(snapshot_stat.st_mode):
        raise SystemExit(f"immutable rescore snapshot changed during {phase}: {item['role']}")
    snapshot_data = snapshot.read_bytes()
    if len(snapshot_data) != item["bytes"] or hashlib.sha256(snapshot_data).hexdigest() != item["sha256"]:
        raise SystemExit(f"immutable rescore snapshot changed during {phase}: {item['role']}")
view = metadata["scorerColdManifest"]
view_path = Path(view["path"])
try:
    view_fd = os.open(view_path, os.O_RDONLY | os.O_NOFOLLOW)
except FileNotFoundError:
    raise SystemExit(f"scorer cold manifest changed during {phase}")
try:
    view_before = os.fstat(view_fd)
    if (
        os.path.realpath(view_path) != str(view_path)
        or stat.S_ISLNK(view_before.st_mode)
        or not stat.S_ISREG(view_before.st_mode)
        or view_before.st_dev != view["dev"]
        or view_before.st_ino != view["ino"]
    ):
        raise SystemExit(f"scorer cold manifest changed during {phase}")
    view_chunks = []
    while True:
        chunk = os.read(view_fd, 1024 * 1024)
        if not chunk:
            break
        view_chunks.append(chunk)
    view_after = os.fstat(view_fd)
finally:
    os.close(view_fd)
view_data = b"".join(view_chunks)
if (
    (view_after.st_dev, view_after.st_ino) != (view_before.st_dev, view_before.st_ino)
    or view_after.st_size != len(view_data)
    or len(view_data) != view["bytes"]
    or hashlib.sha256(view_data).hexdigest() != view["sha256"]
):
    raise SystemExit(f"scorer cold manifest changed during {phase}")
PY
}

run_rescore() {
  local rescore_inputs="$private_root/rescore-inputs.json"
  local rescore_report="$private_root/rescore-report.json"
  local rescore_corpus="$rescore_input_root/qualification-corpus-v1.json"
  local rescore_cold_manifest="$rescore_input_root/cold-manifest.json"
  local rescore_cancellation="$rescore_input_root/cancellation.json"
  local rescore_prior_provenance=""
  local rescore_warm

  run_stdlib_python - "$rescore_input_root" "$corpus_path" "$rescore_inputs" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

root_raw, current_corpus_raw, destination_raw = sys.argv[1:]
root = Path(root_raw)
current_corpus_path = Path(current_corpus_raw)
destination = Path(destination_raw)
if os.path.realpath(root) != str(root):
    raise SystemExit("rescore input root is not canonical")
root = root.resolve()
if not hasattr(os, "O_NOFOLLOW"):
    raise SystemExit("immutable rescore snapshot flags unavailable")
snapshot_root = destination.parent / "rescore-snapshots"
snapshot_root.mkdir(mode=0o700)
snapshot_index = 0

def snapshot(path, role):
    global snapshot_index
    path = Path(path)
    path_identity = os.lstat(path)
    if os.path.realpath(path) != str(path) or stat.S_ISLNK(path_identity.st_mode) or not stat.S_ISREG(path_identity.st_mode):
        raise SystemExit(f"rescore input is not a canonical regular file: {role}")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd)
        if (before.st_dev, before.st_ino) != (path_identity.st_dev, path_identity.st_ino):
            raise SystemExit(f"rescore input path changed before snapshot: {role}")
        chunks = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(fd)
    finally:
        os.close(fd)
    data = b"".join(chunks)
    if (
        (after.st_dev, after.st_ino) != (before.st_dev, before.st_ino)
        or after.st_size != len(data)
    ):
        raise SystemExit(f"rescore input changed while snapshotting: {role}")
    snapshot_index += 1
    safe_role = "".join(character if character.isalnum() else "_" for character in role)
    snapshot_path = snapshot_root / f"{snapshot_index:03d}-{safe_role}.bin"
    snapshot_fd = os.open(snapshot_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        offset = 0
        while offset < len(data):
            offset += os.write(snapshot_fd, data[offset:])
        os.fsync(snapshot_fd)
    finally:
        os.close(snapshot_fd)
    return {
        "role": role,
        "path": str(path),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "dev": before.st_dev,
        "ino": before.st_ino,
        "snapshotPath": str(snapshot_path),
    }, data

def inside(raw):
    path = Path(raw)
    if os.path.realpath(path) != str(path):
        raise SystemExit(f"rescore evidence path is not canonical: {path}")
    try:
        path.relative_to(root)
    except ValueError:
        raise SystemExit(f"rescore evidence escaped input root: {path}")
    return path

manifest_path = root / "accepted-run-manifest.json"
cold_manifest_path = root / "cold-manifest.json"
cancellation_path = root / "cancellation.json"
input_corpus_path = root / "qualification-corpus-v1.json"
prior_provenance_path = root / "qualification-provenance.json"
manifest_item, manifest_data = snapshot(manifest_path, "acceptedRunManifest")
cold_manifest_item, cold_manifest_data = snapshot(cold_manifest_path, "coldManifest")
cancellation_item, cancellation_data = snapshot(cancellation_path, "cancellation")
input_corpus_item, input_corpus_data = snapshot(input_corpus_path, "inputCorpus")
current_corpus_item, current_corpus_data = snapshot(current_corpus_path, "currentCorpus")
manifest = json.loads(manifest_data.decode("utf-8"))
cold_manifest = json.loads(cold_manifest_data.decode("utf-8"))
cancellation = json.loads(cancellation_data.decode("utf-8"))
input_corpus = json.loads(input_corpus_data.decode("utf-8"))
current_corpus = json.loads(current_corpus_data.decode("utf-8"))
if not isinstance(manifest, list) or not isinstance(cold_manifest, list):
    raise SystemExit("accepted-run-manifest and cold-manifest must be arrays")
if input_corpus != current_corpus:
    raise SystemExit("immutable rescore corpus differs from current corpus")
if cancellation.get("noLatePublication") is not True:
    raise SystemExit("immutable rescore cancellation evidence is not no-late-output evidence")

warm_entries = [entry for entry in manifest if entry.get("label") == "warm"]
cold_entries = [entry for entry in manifest if str(entry.get("label", "")).startswith("cold-")]
if len(warm_entries) != 1 or len(cold_entries) != len(cold_manifest) or len(cold_manifest) < 5:
    raise SystemExit("accepted-run-manifest does not contain the complete warm/cold qualification")
warm_entry = warm_entries[0]
if warm_entry.get("status") != "success":
    raise SystemExit("warm accepted-run-manifest entry is not successful")
warm_path = inside(warm_entry["evidencePath"])
warm_item, warm_data = snapshot(warm_path, "warmEvidence")

cold_by_id = {entry["caseID"]: entry for entry in cold_manifest}
manifest_cold_by_id = {entry["caseID"]: entry for entry in cold_entries}
if set(cold_by_id) != set(manifest_cold_by_id):
    raise SystemExit("cold manifest identities do not match accepted-run-manifest")

selected_files = [manifest_item, warm_item]
for entry in cold_manifest:
    case_id = entry["caseID"]
    evidence_path = inside(entry["evidencePath"])
    manifest_entry = manifest_cold_by_id[case_id]
    if manifest_entry.get("status") != "success" or manifest_entry.get("evidencePath") != str(evidence_path):
        raise SystemExit(f"accepted-run-manifest does not select cold evidence for {case_id}")
    actual, evidence_data = snapshot(evidence_path, f"coldEvidence:{case_id}")
    if actual["sha256"] != entry.get("evidenceSHA256"):
        raise SystemExit(f"cold evidence hash mismatch for {case_id}")
    selected_files.append(actual)
    summary_item, summary_data = snapshot(inside(manifest_entry["summaryPath"]), f"coldSummary:{case_id}")
    selected_files.append(summary_item)
warm_summary_item, warm_summary_data = snapshot(inside(warm_entry["summaryPath"]), "warmSummary")
selected_files.extend([warm_summary_item, cold_manifest_item, cancellation_item, input_corpus_item])

evidence_snapshots = {
    item["role"]: item
    for item in selected_files
    if item["role"].startswith("coldEvidence:")
}
summary_snapshots = {
    item["role"]: item
    for item in selected_files
    if item["role"].startswith("coldSummary:")
}
scorer_cold_manifest = []
for entry in cold_manifest:
    case_id = entry["caseID"]
    manifest_entry = manifest_cold_by_id[case_id]
    evidence_snapshot = evidence_snapshots.get(f"coldEvidence:{case_id}")
    summary_snapshot = summary_snapshots.get(f"coldSummary:{case_id}")
    if evidence_snapshot is None or summary_snapshot is None:
        raise SystemExit(f"missing verified cold snapshot for scorer view: {case_id}")
    view_entry = dict(entry)
    view_entry["evidencePath"] = evidence_snapshot["snapshotPath"]
    if manifest_entry.get("summaryPath") is not None:
        view_entry["summaryPath"] = summary_snapshot["snapshotPath"]
    scorer_cold_manifest.append(view_entry)

scorer_view_path = snapshot_root / "scorer-cold-manifest.json"
scorer_view_data = (json.dumps(scorer_cold_manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
scorer_view_fd = os.open(
    scorer_view_path,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
    0o600,
)
try:
    offset = 0
    while offset < len(scorer_view_data):
        offset += os.write(scorer_view_fd, scorer_view_data[offset:])
    os.fsync(scorer_view_fd)
    scorer_view_stat = os.fstat(scorer_view_fd)
finally:
    os.close(scorer_view_fd)
if scorer_view_stat.st_size != len(scorer_view_data):
    raise SystemExit("scorer cold manifest snapshot was truncated")
scorer_view_item = {
    "role": "scorerColdManifest",
    "path": str(scorer_view_path),
    "bytes": len(scorer_view_data),
    "sha256": hashlib.sha256(scorer_view_data).hexdigest(),
    "dev": scorer_view_stat.st_dev,
    "ino": scorer_view_stat.st_ino,
}

prior_item = None
if prior_provenance_path.is_file() and not prior_provenance_path.is_symlink():
    prior_item, prior_data = snapshot(prior_provenance_path, "priorQualificationProvenance")
    selected_files.append(prior_item)

warm_records = [line for line in warm_data.decode("utf-8").splitlines() if line.strip()]
if len(warm_records) != len(input_corpus.get("cases", [])):
    raise SystemExit("warm evidence is not complete for the immutable corpus")
current_identity = current_corpus_item
input_identity = next(item for item in selected_files if item["role"] == "inputCorpus")
if current_identity["sha256"] != input_identity["sha256"]:
    raise SystemExit("current corpus hash differs from immutable input corpus")

with destination.open("w", encoding="utf-8") as handle:
    json.dump({
        "inputRoot": str(root),
        "acceptedRunManifest": manifest_item,
        "warmEvidence": warm_item,
        "coldManifest": cold_manifest_item,
        "cancellation": cancellation_item,
        "inputCorpus": input_corpus_item,
        "priorQualificationProvenance": prior_item,
        "scorerColdManifest": scorer_view_item,
        "files": selected_files,
        "currentCorpus": current_identity,
    }, handle, ensure_ascii=False, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY

  rescore_corpus="$(run_stdlib_python -c 'import json,sys; print(json.load(open(sys.argv[1]))["inputCorpus"]["snapshotPath"])' "$rescore_inputs")"
  rescore_warm="$(run_stdlib_python -c 'import json,sys; print(json.load(open(sys.argv[1]))["warmEvidence"]["snapshotPath"])' "$rescore_inputs")"
  rescore_cold_manifest="$(run_stdlib_python -c 'import json,sys; print(json.load(open(sys.argv[1]))["scorerColdManifest"]["path"])' "$rescore_inputs")"
  rescore_cancellation="$(run_stdlib_python -c 'import json,sys; print(json.load(open(sys.argv[1]))["cancellation"]["snapshotPath"])' "$rescore_inputs")"
  rescore_prior_provenance="$(run_stdlib_python -c 'import json,sys; value=json.load(open(sys.argv[1])).get("priorQualificationProvenance"); print(value["snapshotPath"] if value else "")' "$rescore_inputs")"
  if (( test_pause_around_rescore_cold_score_ms > 0 )); then
    echo "qwen cleanup qualification rescore: before verified cold snapshot score" >&2
    pause_seconds="$(awk -v milliseconds="$test_pause_around_rescore_cold_score_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
    sleep "$pause_seconds"
  fi
  DYLD_LIBRARY_PATH="$swift_build_dir" \
    "$swift_build_dir/score_qwen_cleanup_qualification" \
    --corpus "$rescore_corpus" \
    --warm "$rescore_warm" \
    --cold-manifest "$rescore_cold_manifest" \
    --cancellation "$rescore_cancellation" \
    >"$rescore_report"

  if (( test_pause_around_rescore_cold_score_ms > 0 )); then
    echo "qwen cleanup qualification rescore: after verified cold snapshot score" >&2
    pause_seconds="$(awk -v milliseconds="$test_pause_around_rescore_cold_score_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
    sleep "$pause_seconds"
  fi
  verify_rescore_inputs "scoring" "$rescore_inputs"

  if (( test_pause_around_rescore_report_read_ms > 0 )); then
    echo "qwen cleanup qualification rescore: before immutable snapshot report read" >&2
    pause_seconds="$(awk -v milliseconds="$test_pause_around_rescore_report_read_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
    sleep "$pause_seconds"
  fi

  run_stdlib_python - \
    "$rescore_report" \
    "$rescore_inputs" \
    "$rescore_prior_provenance" \
    "$base_commit" \
    "$repo_root" \
    "$corpus_path" \
    "$scorer_source" \
    "$qualification_dir/run-qwen-cleanup-qualification.sh" \
    "$qualification_dir/Tests/run-contract-tests.sh" \
    "$qualification_dir/README.md" \
    "$output_root" \
    "$staging_dir/qualification-report.json" \
    "$staging_dir/qualification-provenance.json" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

(
    scorer_path,
    inputs_path,
    prior_provenance_path,
    base_commit,
    repo_root,
    current_corpus_path,
    current_scorer_path,
    runner_path,
    tests_path,
    readme_path,
    output_root,
    report_path,
    provenance_path,
) = sys.argv[1:]

def identity(raw, role):
    path = Path(raw)
    first = os.lstat(path)
    if os.path.realpath(path) != str(path) or stat.S_ISLNK(first.st_mode) or not stat.S_ISREG(first.st_mode):
        raise SystemExit(f"rescore provenance path is not canonical regular file: {role}")
    data = path.read_bytes()
    return {"role": role, "path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

report = json.loads(Path(scorer_path).read_text(encoding="utf-8"))
inputs = json.loads(Path(inputs_path).read_text(encoding="utf-8"))
cold_value = json.loads(Path(inputs["coldManifest"]["snapshotPath"]).read_text(encoding="utf-8"))
prior_provenance = {}
if prior_provenance_path:
    prior_provenance_path = Path(prior_provenance_path)
    if prior_provenance_path.is_file() and not prior_provenance_path.is_symlink():
        prior_provenance = json.loads(prior_provenance_path.read_text(encoding="utf-8"))
attempts = [
    {
        "id": "taxonomy-fix-first-real",
        "root": "historical-external-evidence:QwenCleanupQualification-20260821T075500Z-taxonomy-fix",
        "status": "failed-before-publication",
        "failureReason": "qwen-asr-mixed-12 exceeded 1,500 ms; forcing nonCooperativeTermination=true; warm all-case accepted harness run failed",
        "failureClass": "deadline-instability",
        "aggregatePublished": False,
    },
    {
        "id": "taxonomy-fix-second-real",
        "root": "historical-external-evidence:QwenCleanupQualification-20260820T235632Z-taxonomy-fix-rerun",
        "status": "failed-before-qualification-publication",
        "failureReason": "83 warm cases reached, then /bin/sh invocation hit Bash process-substitution line 828; runner rejected unsupported shell only after the warm accepted evidence",
        "failureClass": "unsupported-shell-post-warm",
        "aggregatePublished": False,
    },
]
current_files = [
    identity(current_corpus_path, "currentCorpus"),
    identity(current_scorer_path, "currentScorer"),
    identity(runner_path, "currentRunner"),
    identity(tests_path, "currentContractTests"),
    identity(readme_path, "currentREADME"),
]
deterministic_files = [
    identity(str(Path(repo_root) / "Sources/FleckApp/FoundationModelDictation.swift"), "FoundationModelDictation"),
    identity(str(Path(repo_root) / "Sources/FleckApp/FaithfulCleanupValidator.swift"), "FaithfulCleanupValidator"),
    identity(str(Path(repo_root) / "Sources/FleckApp/CleanupLexeme.swift"), "CleanupLexeme"),
    identity(str(Path(repo_root) / "Sources/FleckApp/CleanupProtectedSpan.swift"), "CleanupProtectedSpan"),
    identity(str(Path(repo_root) / "Sources/FleckCore/PersonalDictionaryResolver.swift"), "PersonalDictionaryResolver"),
]
input_files_receipt = [
    {key: value for key, value in item.items() if key != "snapshotPath"}
    for item in inputs["files"]
]
provenance = {
    "schemaVersion": 1,
    "receiptType": "qwen-cleanup-qualification-rescore",
    "baseCommit": base_commit,
    "inputRoot": inputs["inputRoot"],
    "inputFiles": input_files_receipt,
    "currentQualificationFiles": current_files,
    "deterministicControlSources": deterministic_files,
    "acceptedHarnessProvenance": report.get("provenance", {}),
    "externalSourceEvidence": prior_provenance.get("externalSourceEvidence", report.get("externalSourceEvidence", [])),
    "acceptedFinalSourcesOnly": True,
    "attemptOutcomes": attempts,
    "immutableInputsVerified": True,
    "verifiedSnapshotsConsumed": True,
    "verifiedSnapshotHashes": {
        item["role"]: item["sha256"]
        for item in inputs["files"] + [inputs["currentCorpus"]]
    },
}
candidate = dict(report.get("candidate", {}))
candidate["automatedCandidatePass"] = False
candidate["failureReasons"] = [
    "strict_candidate_rejections",
    "deadline_instability_first_attempt",
    "unsupported_shell_post_warm_second_attempt",
]
report["candidate"] = candidate
report["claimScope"] = "developer-only-external-qwen-cleanup-qualification-rescore"
report["qualificationAttempts"] = attempts
evidence_items = {
    item["role"]: item
    for item in inputs["files"]
    if item["role"] == "warmEvidence" or item["role"].startswith("coldEvidence:")
}
expected_evidence_roles = ["warmEvidence"] + [f"coldEvidence:{entry['caseID']}" for entry in cold_value]
scored_evidence = report.get("evidenceFiles")
if not isinstance(scored_evidence, list) or len(scored_evidence) != len(expected_evidence_roles):
    raise SystemExit("scorer evidence identity count does not match verified evidence snapshots")
public_evidence_files = []
evidence_bindings = []
for scored, role in zip(scored_evidence, expected_evidence_roles):
    item = evidence_items.get(role)
    if item is None or scored.get("path") != item["snapshotPath"]:
        raise SystemExit(f"scorer did not consume the verified private snapshot: {role}")
    if scored.get("bytes") != item["bytes"] or scored.get("sha256") != item["sha256"]:
        raise SystemExit(f"scorer evidence identity did not match the verified private snapshot: {role}")
    public_identity = dict(scored)
    public_identity["path"] = item["path"]
    public_evidence_files.append(public_identity)
    evidence_bindings.append({
        "role": role,
        "path": item["path"],
        "bytes": scored["bytes"],
        "sha256": scored["sha256"],
        "computedFrom": "private-verified-snapshot-bytes",
    })
report["evidenceFiles"] = public_evidence_files
report["rescore"] = {
    "inputRoot": inputs["inputRoot"],
    "acceptedRunManifestSelectedInputs": True,
    "immutableInputsVerified": True,
    "modelLaunched": False,
    "attemptOutcomesRecorded": True,
    "verifiedSnapshotsConsumed": True,
    "evidenceMetricsSource": "private-verified-snapshot-bytes",
    "coldEvidenceRSSSource": "private-verified-cold-evidence-snapshots",
    "evidenceBindings": evidence_bindings,
}
report["qualificationProvenance"] = provenance
report["acceptedFinalSourcesOnly"] = True
report["truthFlags"] = {
    "productionIntegrated": False,
    "packagedAppVerified": False,
    "releaseAdmitted": False,
}
report["productionIntegrated"] = False
report["packagedAppVerified"] = False
report["releaseAdmitted"] = False
report["externalSourceEvidence"] = provenance["externalSourceEvidence"]
report["qualification"]["acceptedFinalSourcesOnly"] = True
report["acceptedHarnessRuns"] = json.loads(Path(inputs["acceptedRunManifest"]["snapshotPath"]).read_text(encoding="utf-8"))
report["coldManifest"] = {
    "path": inputs["coldManifest"]["path"],
    "caseCount": len(cold_value),
    "cases": cold_value,
}
report["cancellation"] = json.loads(Path(inputs["cancellation"]["snapshotPath"]).read_text(encoding="utf-8"))

Path(report_path).write_text(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
provenance["rescoreReport"] = identity(report_path, "rescoreReport")
Path(provenance_path).write_text(json.dumps(provenance, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY

  if (( test_pause_around_rescore_report_read_ms > 0 )); then
    echo "qwen cleanup qualification rescore: after immutable snapshot report read" >&2
    pause_seconds="$(awk -v milliseconds="$test_pause_around_rescore_report_read_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
    sleep "$pause_seconds"
  fi

  chmod 600 "$staging_dir/qualification-report.json" "$staging_dir/qualification-provenance.json"
  verify_rescore_inputs "final publication check" "$rescore_inputs"
  if (( test_pause_before_rescore_publish_ms > 0 )); then
    echo "qwen cleanup qualification rescore: staging complete; holding output anchor before publication" >&2
    pause_seconds="$(awk -v milliseconds="$test_pause_before_rescore_publish_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
    sleep "$pause_seconds"
  fi
  verify_rescore_inputs "publication check after pause" "$rescore_inputs"
  run_stdlib_python - "$output_root" "$private_root/output-anchor.json" "$staging_dir" <<'PY'
import json
import os
import stat
import sys
root, anchor_path, staging = sys.argv[1:]
with open(anchor_path, encoding="utf-8") as handle:
    anchor = json.load(handle)
if os.path.realpath(root) != root:
    raise SystemExit("rescore output directory identity changed: canonical path mismatch")
if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
    raise SystemExit("anchored output flags unavailable")
parent = os.path.dirname(root)
if anchor.get("parentPath") != parent or os.path.realpath(parent) != parent:
    raise SystemExit("rescore output parent identity changed: canonical path mismatch")
parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
parent_identity = os.fstat(parent_fd)
if parent_identity.st_dev != anchor["parentDev"] or parent_identity.st_ino != anchor["parentIno"]:
    os.close(parent_fd)
    raise SystemExit("rescore output parent identity changed: device/inode mismatch")
fd = os.open(os.path.basename(root), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
published = []
try:
    identity = os.fstat(fd)
    if identity.st_dev != anchor["dev"] or identity.st_ino != anchor["ino"]:
        raise SystemExit("rescore output directory identity changed: device/inode mismatch")
    for name in ("qualification-report.json", "qualification-provenance.json"):
        source = os.path.join(staging, name)
        source_stat = os.lstat(source)
        if os.path.realpath(source) != source or stat.S_ISLNK(source_stat.st_mode) or not stat.S_ISREG(source_stat.st_mode):
            raise SystemExit(f"rescore staged source is not a regular file: {source}")
        if os.path.exists(os.path.join(root, name)):
            raise SystemExit(f"refusing to overwrite existing rescore output: {name}")
    try:
        for name in ("qualification-report.json", "qualification-provenance.json"):
            os.link(os.path.join(staging, name), name, dst_dir_fd=fd, follow_symlinks=False)
            published.append(name)
    except BaseException:
        for name in reversed(published):
            try:
                os.unlink(name, dir_fd=fd)
            except OSError:
                pass
        raise
finally:
    os.close(fd)
    os.close(parent_fd)
PY
  echo "qwen cleanup qualification rescore report: $output_root/qualification-report.json"
  echo "qwen cleanup qualification rescore provenance: $output_root/qualification-provenance.json"
}

base_commit="$(git -C "$repo_root" rev-parse --verify HEAD)"
expected_base="$(git -C "$repo_root" rev-parse --verify af49c07^{commit})"
[[ "$base_commit" == "$expected_base" ]] || fail "HEAD is not the expected af49c07 base: $base_commit"
if [[ "$mode" == "rescore" ]]; then
  write_anchor
  build_scorer
  run_rescore
  exit 0
fi
write_anchor
build_scorer

if [[ "$mode" == "real" ]]; then
  cancel_process_timeout_ms=1
else
  cancel_process_timeout_ms=8000
fi

if run_accepted "warm" "" "$process_timeout_ms" "$test_sleep_ms"; then
  warm_evidence="$RUN_EVIDENCE"
  warm_summary="$RUN_SUMMARY"
else
  fail "warm all-case accepted harness run failed"
fi

cold_case_ids=()
while IFS= read -r cold_case_id; do
  [[ -n "$cold_case_id" ]] && cold_case_ids+=("$cold_case_id")
done < <(run_stdlib_python -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$cold_selection")
[[ "${#cold_case_ids[@]}" -ge 5 ]] || fail "cold selection contains fewer than five cases"
cold_case_ids_file="$private_root/cold-case-ids.txt"
printf '%s\n' "${cold_case_ids[@]}" >"$cold_case_ids_file"
for cold_case_id in "${cold_case_ids[@]}"; do
  if ! run_accepted "cold-$cold_case_id" "$cold_case_id" "$process_timeout_ms" 0; then
    fail "cold accepted harness run failed for $cold_case_id"
  fi
done

run_cancellation_probe "${cold_case_ids[0]}"

cold_manifest="$private_root/cold-manifest.json"
run_stdlib_python - "$accepted_runs" "$cold_manifest" "$output_root" <<'PY'
import hashlib
import json
import os
import sys
runs_path, destination, output_root = sys.argv[1:]
records = []
with open(runs_path, encoding="utf-8") as handle:
    for line in handle:
        if not line.strip():
            continue
        value = json.loads(line)
        if value.get("label", "").startswith("cold-"):
            path = value["evidencePath"]
            if os.path.realpath(path) != path or os.path.islink(path) or not os.path.isfile(path):
                raise SystemExit(f"cold evidence is not a canonical regular file: {path}")
            with open(path, "rb") as evidence_handle:
                digest = hashlib.sha256(evidence_handle.read()).hexdigest()
            records.append({
                "caseID": value["caseID"],
                "status": value["status"],
                "processToResultMilliseconds": value["processToResultMilliseconds"],
                "evidencePath": path,
                "evidenceSHA256": digest,
            })
if len(records) < 5 or len({record["caseID"] for record in records}) != len(records):
    raise SystemExit("cold manifest does not contain five unique cold cases")
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(records, handle, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY

scorer_report="$private_root/scorer-report.json"
DYLD_LIBRARY_PATH="$swift_build_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  "$swift_build_dir/score_qwen_cleanup_qualification" \
  --corpus "$corpus_path" \
  --warm "$warm_evidence" \
  --cold-manifest "$cold_manifest" \
  --cancellation "$private_root/cancellation.json" \
  >"$scorer_report"

run_stdlib_python - "$scorer_report" "$corpus_metadata" "$cold_manifest" "$private_root/cancellation.json" "$accepted_runs" "$base_commit" "$repo_root" "$corpus_path" "$scorer_source" "$qualification_dir/run-qwen-cleanup-qualification.sh" "$qualification_dir/Tests/run-contract-tests.sh" "$qualification_dir/README.md" "$output_root" "$staging_dir/qualification-report.json" "$staging_dir/qualification-provenance.json" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

(
    scorer_path,
    metadata_path,
    cold_manifest_path,
    cancellation_path,
    accepted_runs_path,
    base_commit,
    repo_root,
    corpus_path,
    scorer_source,
    runner_source,
    tests_source,
    readme_source,
    output_root,
    report_path,
    provenance_path,
) = sys.argv[1:]

def identity(raw, label):
    path = Path(raw)
    first = os.lstat(path)
    if os.path.realpath(path) != str(path) or stat.S_ISLNK(first.st_mode) or not stat.S_ISREG(first.st_mode):
        raise SystemExit(f"qualification provenance path is not canonical regular file: {label}")
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

with open(scorer_path, encoding="utf-8") as handle:
    report = json.load(handle)
with open(metadata_path, encoding="utf-8") as handle:
    metadata = json.load(handle)
with open(cold_manifest_path, encoding="utf-8") as handle:
    cold_manifest = json.load(handle)
with open(cancellation_path, encoding="utf-8") as handle:
    cancellation = json.load(handle)
with open(accepted_runs_path, encoding="utf-8") as handle:
    accepted_runs = [json.loads(line) for line in handle if line.strip()]
qualification_files = [
    identity(corpus_path, "corpus"),
    identity(scorer_source, "scorer"),
    identity(runner_source, "runner"),
    identity(tests_source, "contract tests"),
    identity(readme_source, "README"),
]
deterministic_files = [
    identity(str(Path(repo_root) / "Sources/FleckApp/FoundationModelDictation.swift"), "FoundationModelDictation"),
    identity(str(Path(repo_root) / "Sources/FleckApp/FaithfulCleanupValidator.swift"), "FaithfulCleanupValidator"),
    identity(str(Path(repo_root) / "Sources/FleckApp/CleanupLexeme.swift"), "CleanupLexeme"),
    identity(str(Path(repo_root) / "Sources/FleckApp/CleanupProtectedSpan.swift"), "CleanupProtectedSpan"),
    identity(str(Path(repo_root) / "Sources/FleckCore/PersonalDictionaryResolver.swift"), "PersonalDictionaryResolver"),
]
provenance = {
    "schemaVersion": 1,
    "baseCommit": base_commit,
    "acceptedHarnessProvenance": report.get("provenance", {}),
    "qualificationFiles": qualification_files,
    "deterministicControlSources": deterministic_files,
    "externalSourceEvidence": metadata["sourceEvidence"],
    "acceptedFinalSourcesOnly": metadata["acceptedFinalSourcesOnly"],
}
report["releaseAdmitted"] = False
report["productionIntegrated"] = False
report["packagedAppVerified"] = False
report["truthFlags"] = {
    "productionIntegrated": False,
    "packagedAppVerified": False,
    "releaseAdmitted": False,
}
report["qualificationProvenance"] = provenance
report["externalSourceEvidence"] = metadata["sourceEvidence"]
report["acceptedFinalSourcesOnly"] = True
report["acceptedHarnessRuns"] = accepted_runs
report["coldManifest"] = {
    "path": str(Path(output_root) / "cold-manifest.json"),
    "caseCount": len(cold_manifest),
    "cases": cold_manifest,
}
report["cancellation"] = cancellation
report["qualification"]["sourceEvidence"] = metadata["sourceEvidence"]
report["qualification"]["acceptedFinalSourcesOnly"] = True
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, ensure_ascii=False, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
with open(provenance_path, "w", encoding="utf-8") as handle:
    json.dump(provenance, handle, ensure_ascii=False, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY

cp "$corpus_path" "$staging_dir/qualification-corpus-v1.json"
cp "$cold_manifest" "$staging_dir/cold-manifest.json"
cp "$private_root/cancellation.json" "$staging_dir/cancellation.json"
run_stdlib_python - "$accepted_runs" "$staging_dir/accepted-run-manifest.json" <<'PY'
import json
import os
import sys
source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    records = [json.loads(line) for line in handle if line.strip()]
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(records, handle, sort_keys=True, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
chmod 600 "$staging_dir"/*


publish_exclusive() {
  run_stdlib_python - "$output_root" "$private_root/output-anchor.json" "$staging_dir" <<'PY'
import json
import os
import stat
import sys
root, anchor_path, staging = sys.argv[1:]
with open(anchor_path, encoding="utf-8") as handle:
    anchor = json.load(handle)
if os.path.realpath(root) != root:
    raise SystemExit("output directory identity changed: canonical path mismatch")
if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
    raise SystemExit("anchored output flags unavailable")
parent = os.path.dirname(root)
if anchor.get("parentPath") != parent or os.path.realpath(parent) != parent:
    raise SystemExit("output parent identity changed: canonical path mismatch")
parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
parent_identity = os.fstat(parent_fd)
if parent_identity.st_dev != anchor["parentDev"] or parent_identity.st_ino != anchor["parentIno"]:
    os.close(parent_fd)
    raise SystemExit("output parent identity changed: device/inode mismatch")
names = [
    "qualification-report.json",
    "qualification-provenance.json",
    "qualification-corpus-v1.json",
    "cold-manifest.json",
    "cancellation.json",
    "accepted-run-manifest.json",
]
fd = os.open(os.path.basename(root), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
published = []
try:
    identity = os.fstat(fd)
    if identity.st_dev != anchor["dev"] or identity.st_ino != anchor["ino"]:
        raise SystemExit("output directory identity changed: device/inode mismatch")
    for name in names:
        source = os.path.join(staging, name)
        if os.path.realpath(source) != source:
            raise SystemExit(f"staged source is not canonical: {source}")
        source_stat = os.lstat(source)
        if stat.S_ISLNK(source_stat.st_mode) or not stat.S_ISREG(source_stat.st_mode):
            raise SystemExit(f"staged source is not a regular file: {source}")
        if os.path.exists(os.path.join(root, name)):
            raise SystemExit(f"refusing to overwrite existing output: {name}")
    try:
        for name in names:
            os.link(os.path.join(staging, name), name, dst_dir_fd=fd, follow_symlinks=False)
            published.append(name)
    except BaseException:
        for name in reversed(published):
            try:
                os.unlink(name, dir_fd=fd)
            except OSError:
                pass
        raise
finally:
    os.close(fd)
    os.close(parent_fd)
PY
}

if (( test_pause_before_publish_ms > 0 )); then
  echo "qwen cleanup qualification: staging complete; holding output anchor before publication" >&2
  pause_seconds="$(awk -v milliseconds="$test_pause_before_publish_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
  sleep "$pause_seconds"
fi
publish_exclusive || fail "anchored exclusive publication failed; no redirected aggregate evidence was published"

echo "qwen cleanup qualification report: $output_root/qualification-report.json"
echo "qwen cleanup qualification provenance: $output_root/qualification-provenance.json"
