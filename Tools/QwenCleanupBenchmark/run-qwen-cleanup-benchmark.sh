#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(git -C "$script_dir/../.." rev-parse --show-toplevel)"
readonly helper_path="$script_dir/qwen_cleanup_helper.py"
readonly validator_source="$script_dir/validate_cleanup_candidate.swift"
readonly default_fixture_path="$script_dir/Fixtures/cases-v1.json"
readonly sandbox_exec="/usr/bin/sandbox-exec"
readonly sandbox_profile='(version 1) (allow default) (deny network*)'
readonly required_artifacts=(
  ".gitattributes"
  "README.md"
  "chat_template.jinja"
  "config.json"
  "model.safetensors"
  "model.safetensors.index.json"
  "preprocessor_config.json"
  "processor_config.json"
  "tokenizer.json"
  "tokenizer_config.json"
  "video_preprocessor_config.json"
  "vocab.json"
  "LICENSE.Qwen-upstream-Apache-2.0"
)
readonly required_artifact_bytes=(
  1570
  2307
  7755
  3112
  625229487
  71473
  390
  1300
  19989343
  1139
  385
  6722759
  11544
)
readonly required_artifact_sha256=(
  "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"
  "7024f593c30b51462de050b5cdf938a5b0f0d554901e6ac3af3ed7af92fb5e5f"
  "273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80"
  "ba7770da23eae5ebd6827571f086e331956b33f4442a9e876fb4aa10969a6772"
  "f5a0d9dd3efa73510542a8023d610ff26be2b4b020d181cfc4bedaa1fcc5dd9e"
  "6e48f2fa5d6f033a6d77bf833abfa9698ca24d1715ecea4c67447bcfaee44650"
  "27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516"
  "14932921ca485d458a04dafd8069fbb0a4505622a48208d19ed247115801385b"
  "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"
  "e98f1901ac6f0adff67b1d540bfa0c36ac1a0cf59eb72ed78146ef89aafa1182"
  "7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13"
  "ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003"
  "bbedc3fda3305820b977265f01b8619d87570a6739de3a5582c3464840f1e57a"
)

python_executable="${FLECK_QWEN_PYTHON_EXECUTABLE:-}"
runtime_site_packages="${FLECK_QWEN_RUNTIME_SITE_PACKAGES:-}"
model_root="${FLECK_QWEN_MODEL_ROOT:-}"
output_root="${FLECK_QWEN_OUTPUT_ROOT:-}"
fixture_path="$default_fixture_path"
mode=""
fake_responses=""
case_id=""
process_timeout_ms=300000
test_sleep_ms=0
test_artifact_manifest=""
test_pause_before_publish_ms=0

fail() {
  echo "qwen-cleanup-benchmark-error: $*" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
Usage:
  run-qwen-cleanup-benchmark.sh --smoke [paths/options]
  run-qwen-cleanup-benchmark.sh --contract-test --fake-responses ABSOLUTE_JSON [paths/options]

Runtime, model, and output paths are required through the listed CLI options or
FLECK_QWEN_PYTHON_EXECUTABLE, FLECK_QWEN_RUNTIME_SITE_PACKAGES,
FLECK_QWEN_MODEL_ROOT, and FLECK_QWEN_OUTPUT_ROOT. Nothing is downloaded.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke)
      [[ -z "$mode" ]] || usage
      mode="smoke"
      shift
      ;;
    --contract-test)
      [[ -z "$mode" ]] || usage
      mode="contract"
      shift
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
    --fixture)
      [[ $# -ge 2 ]] || usage
      fixture_path="$2"
      shift 2
      ;;
    --fake-responses)
      [[ $# -ge 2 ]] || usage
      fake_responses="$2"
      shift 2
      ;;
    --case-id)
      [[ $# -ge 2 ]] || usage
      case_id="$2"
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
    --test-artifact-manifest)
      [[ $# -ge 2 ]] || usage
      test_artifact_manifest="$2"
      shift 2
      ;;
    --test-pause-before-publish-ms)
      [[ $# -ge 2 ]] || usage
      test_pause_before_publish_ms="$2"
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

[[ "$mode" == "smoke" || "$mode" == "contract" ]] || usage
[[ -n "$python_executable" ]] || fail "--python-executable or FLECK_QWEN_PYTHON_EXECUTABLE is required"
[[ -n "$runtime_site_packages" ]] || fail "--runtime-site-packages or FLECK_QWEN_RUNTIME_SITE_PACKAGES is required"
[[ -n "$model_root" ]] || fail "--model-root or FLECK_QWEN_MODEL_ROOT is required"
[[ -n "$output_root" ]] || fail "--output-root or FLECK_QWEN_OUTPUT_ROOT is required"
[[ "$process_timeout_ms" =~ ^[1-9][0-9]*$ ]] || fail "--process-timeout-ms must be a positive integer"
[[ "$test_sleep_ms" =~ ^[0-9]+$ ]] || fail "--test-sleep-ms must be a non-negative integer"
[[ "$test_pause_before_publish_ms" =~ ^[0-9]+$ ]] || fail "--test-pause-before-publish-ms must be a non-negative integer"
[[ -f "$helper_path" && -x "$helper_path" ]] || fail "helper is missing or not executable: $helper_path"
[[ -f "$validator_source" ]] || fail "validator source is missing: $validator_source"
[[ -f "$fixture_path" ]] || fail "fixture is missing: $fixture_path"

require_absolute_path() {
  local value="$1"
  local label="$2"
  [[ "$value" == /* ]] || fail "$label must be an absolute path"
  case "$value" in
    *$'\001'*|*$'\002'*|*$'\003'*|*$'\004'*|*$'\005'*|*$'\006'*|*$'\007'*|*$'\010'*|*$'\011'*|*$'\012'*|*$'\013'*|*$'\014'*|*$'\015'*|*$'\016'*|*$'\017'*|*$'\020'*|*$'\021'*|*$'\022'*|*$'\023'*|*$'\024'*|*$'\025'*|*$'\026'*|*$'\027'*|*$'\030'*|*$'\031'*|*$'\032'*|*$'\033'*|*$'\034'*|*$'\035'*|*$'\036'*|*$'\037'*|*$'\177'*)
      fail "$label contains a control character"
      ;;
  esac
  [[ "$value" != */../* && "$value" != */.. ]] || fail "$label must not contain '..'"
}

require_canonical_path() {
  local path="$1"
  local label="$2"
  require_absolute_path "$path" "$label"
  [[ -e "$path" ]] || fail "$label does not exist: $path"
  local canonical
  canonical="$(/bin/realpath "$path")" || fail "$label cannot be canonicalized: $path"
  [[ "$canonical" == "$path" ]] || fail "$label must be the canonical path without symlink aliases and must not be a symlink: $path"
  local probe="$path"
  while [[ "$probe" != "/" ]]; do
    [[ ! -L "$probe" ]] || fail "$label has a symlinked ancestor: $probe"
    probe="${probe%/*}"
    [[ -n "$probe" ]] || probe="/"
  done
}

require_regular_file() {
  local path="$1"
  local label="$2"
  [[ -f "$path" ]] || fail "$label must be a regular file: $path"
  [[ ! -L "$path" ]] || fail "$label must not be a symlink: $path"
}

require_directory() {
  local path="$1"
  local label="$2"
  [[ -d "$path" ]] || fail "$label must be a directory: $path"
  [[ ! -L "$path" ]] || fail "$label must not be a symlink: $path"
}

require_canonical_path "$python_executable" "Python executable"
require_canonical_path "$runtime_site_packages" "runtime site-packages"
require_canonical_path "$model_root" "model root"
require_canonical_path "$output_root" "output root"
require_canonical_path "$fixture_path" "fixture"
[[ -z "$fake_responses" ]] || require_canonical_path "$fake_responses" "fake responses"
[[ -z "$test_artifact_manifest" ]] || require_canonical_path "$test_artifact_manifest" "test artifact manifest"
require_regular_file "$python_executable" "Python executable"
[[ -x "$python_executable" ]] || fail "Python executable is not executable: $python_executable"
require_directory "$model_root" "model root"
require_regular_file "$fixture_path" "fixture"
require_directory "$output_root" "output root"
if [[ "$mode" == "smoke" ]]; then
  require_directory "$runtime_site_packages" "runtime site-packages"
else
  [[ "$fake_responses" != "" ]] || fail "--contract-test requires --fake-responses"
  [[ "${FLECK_QWEN_CONTRACT_TESTS:-}" == "1" ]] || fail "contract mode is restricted to run-contract-tests.sh"
  require_regular_file "$fake_responses" "fake responses"
  [[ "$test_artifact_manifest" != "" ]] || fail "--contract-test requires --test-artifact-manifest"
fi
[[ "$mode" == "contract" || "$test_artifact_manifest" == "" ]] || fail "--test-artifact-manifest is contract-test-only"
[[ "$mode" == "contract" || "$test_pause_before_publish_ms" == "0" ]] || fail "--test-pause-before-publish-ms is contract-test-only"

canonical_output_root="$output_root"
canonical_repo_root="$(/bin/realpath "$repo_root")"
case "$canonical_output_root/" in
  "$canonical_repo_root/"*) fail "output root must not be inside the repository: $output_root" ;;
esac
IFS='/' read -r -a output_components <<< "$canonical_output_root"
for component in "${output_components[@]}"; do
  [[ "$component" == *.app ]] && fail "output root must not be inside an app bundle: $output_root"
done

verify_artifact_shell() {
  local root="$1"
  local exact_identity="$2"
  for index in "${!required_artifacts[@]}"; do
    local name="${required_artifacts[$index]}"
    local path="$root/$name"
    require_regular_file "$path" "artifact $name"
    if [[ "$exact_identity" == "1" ]]; then
      local bytes
      local sha256
      bytes="$(/usr/bin/stat -f '%z' "$path")"
      sha256="$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')"
      [[ "$bytes" == "${required_artifact_bytes[$index]}" && "$sha256" == "${required_artifact_sha256[$index]}" ]] || \
        fail "artifact $name identity mismatch before Python/model load: bytes=$bytes sha256=$sha256"
    fi
  done
}

verify_network_deny() {
  [[ -x "$sandbox_exec" ]] || fail "macOS network-deny sandbox unavailable: $sandbox_exec"
  local probe_code=0
  local probe_output
  probe_output="$(env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" PYTHONDONTWRITEBYTECODE=1 \
    "$sandbox_exec" -p "$sandbox_profile" /usr/bin/python3 -I -S -c $'import socket,sys\ns=socket.socket()\ntry:\n s.connect(("198.51.100.1",80))\n print("network-allowed")\n sys.exit(1)\nexcept OSError as e:\n print(f"network-error:{e.errno}")\n sys.exit(0 if e.errno == 1 else 2)' 2>&1)" || probe_code=$?
  [[ "$probe_code" -eq 0 && "$probe_output" == *"network-error:1"* ]] || fail "network-deny enforcement unavailable: $probe_output"
}

build_validator() {
  swift_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-validator.XXXXXX")"
  swift_build_dir="$(/bin/realpath "$swift_build_dir")"
  mkdir -p "$swift_build_dir/module-cache"
  swiftc \
    -parse-as-library \
    -emit-library \
    -emit-module \
    -module-name FleckCore \
    -module-cache-path "$swift_build_dir/module-cache" \
    "$repo_root/Sources/FleckCore/PersonalDictionary.swift" \
    "$repo_root/Sources/FleckCore/CompiledPersonalDictionary.swift" \
    "$repo_root/Sources/FleckCore/PersonalDictionaryResolver.swift" \
    -o "$swift_build_dir/libFleckCore.dylib" \
    -emit-module-path "$swift_build_dir/FleckCore.swiftmodule"
  swiftc \
    -parse-as-library \
    -module-name FleckCleanupValidatorCLI \
    -module-cache-path "$swift_build_dir/module-cache" \
    -I "$swift_build_dir" \
    -L "$swift_build_dir" \
    -Xlinker -rpath \
    -Xlinker "$swift_build_dir" \
    -lFleckCore \
    "$repo_root/Sources/FleckApp/CleanupLexeme.swift" \
    "$repo_root/Sources/FleckApp/CleanupProtectedSpan.swift" \
    "$repo_root/Sources/FleckApp/FaithfulCleanupValidator.swift" \
    "$repo_root/Sources/FleckApp/LocalCleanupResponseEnvelope.swift" \
    "$validator_source" \
    -o "$swift_build_dir/validate_cleanup_candidate"
}

run_isolated_helper() {
  local stdout_path="$1"
  local stderr_path="$2"
  local progress_path="$3"
  shift 3
  local helper_pid
  local started_ns
  local now_ns
  local elapsed_ms
  local wait_code=0
  local latest_started_line
  local latest_finished_line
  local started_case
  local started_line_number
  local finished_line_number
  local finished_case
  local active_case=""
  local active_started_ns=""
  FLECK_QWEN_HELPER_FORCED_TERMINATION=0
  FLECK_QWEN_HELPER_TIMEOUT_REASON=""
  (
    exec \
    env -i \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      PYTHONDONTWRITEBYTECODE=1 \
      HF_HUB_OFFLINE=1 \
      TRANSFORMERS_OFFLINE=1 \
      FLECK_QWEN_NETWORK_DENY=1 \
      FLECK_QWEN_CONTRACT_TESTS="${FLECK_QWEN_CONTRACT_TESTS:-}" \
      "$sandbox_exec" -p "$sandbox_profile" \
        "$python_executable" -I -S "$helper_path" "$@"
  ) >"$stdout_path" 2>"$stderr_path" &
  helper_pid=$!
  started_ns="$(monotonic_ns)"
  while kill -0 "$helper_pid" 2>/dev/null; do
    now_ns="$(monotonic_ns)"
    elapsed_ms=$(( (now_ns - started_ns) / 1000000 ))
    latest_started_line="$(/usr/bin/grep -n '"event":"generation-started"' "$progress_path" 2>/dev/null | /usr/bin/tail -n 1 || true)"
    latest_finished_line="$(/usr/bin/grep -n '"event":"generation-finished"' "$progress_path" 2>/dev/null | /usr/bin/tail -n 1 || true)"
    started_line_number="${latest_started_line%%:*}"
    finished_line_number="${latest_finished_line%%:*}"
    latest_started_line="${latest_started_line#*:}"
    latest_finished_line="${latest_finished_line#*:}"
    started_case="$(/usr/bin/sed -n 's/.*"caseID":"\([^"]*\)".*/\1/p' <<< "$latest_started_line")"
    finished_case="$(/usr/bin/sed -n 's/.*"caseID":"\([^"]*\)".*/\1/p' <<< "$latest_finished_line")"
    if [[ -n "$started_case" && "$started_case" == "$finished_case" && \
          "$started_line_number" =~ ^[0-9]+$ && "$finished_line_number" =~ ^[0-9]+$ && \
          "$finished_line_number" -ge "$started_line_number" ]]; then
      active_case=""
      active_started_ns=""
    elif [[ -n "$started_case" ]]; then
      if [[ "$active_case" != "$started_case" ]]; then
        active_case="$started_case"
        # The progress marker is only a positive observation. Enforcement
        # starts at this supervisor-owned monotonic instant; helper wall-clock
        # timestamps are persisted as evidence but never used as a deadline.
        active_started_ns="$(monotonic_ns)"
        echo "qwen-cleanup-benchmark: generation-started caseID=$active_case" >&2
      fi
      local generation_elapsed_ms=$(( (now_ns - active_started_ns) / 1000000 ))
      if (( generation_elapsed_ms >= 1500 )); then
        echo "qwen-cleanup-benchmark: generation-started caseID=$active_case exceeded 1,500 ms; forcing nonCooperativeTermination=true" >&2
        kill -TERM "$helper_pid" 2>/dev/null || true
        local grace_index
        for grace_index in {1..20}; do
          kill -0 "$helper_pid" 2>/dev/null || break
          sleep 0.01
        done
        if kill -0 "$helper_pid" 2>/dev/null; then
          kill -KILL "$helper_pid" 2>/dev/null || true
        fi
        wait "$helper_pid" 2>/dev/null || true
        FLECK_QWEN_HELPER_FORCED_TERMINATION=1
        FLECK_QWEN_HELPER_TIMEOUT_REASON="generation-deadline"
        return 124
      fi
    fi
    if (( elapsed_ms >= process_timeout_ms )); then
      echo "qwen-cleanup-benchmark: isolated helper exceeded whole-process timeout; forcing nonCooperativeTermination=true" >&2
      kill -TERM "$helper_pid" 2>/dev/null || true
      local grace_index
      for grace_index in {1..20}; do
        kill -0 "$helper_pid" 2>/dev/null || break
        sleep 0.01
      done
      if kill -0 "$helper_pid" 2>/dev/null; then
        kill -KILL "$helper_pid" 2>/dev/null || true
      fi
      wait "$helper_pid" 2>/dev/null || true
      FLECK_QWEN_HELPER_FORCED_TERMINATION=1
      FLECK_QWEN_HELPER_TIMEOUT_REASON="whole-process-timeout"
      return 124
    fi
    sleep 0.005
  done
  if wait "$helper_pid"; then
    wait_code=0
  else
    wait_code=$?
  fi
  return "$wait_code"
}

monotonic_ns() {
  run_stdlib_python -c 'import time; print(time.monotonic_ns())'
}

run_stdlib_python() {
  env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" PYTHONDONTWRITEBYTECODE=1 "$python_executable" -I -S "$@"
}

write_provenance() {
  local destination="$1"
  local compiled_validator="$2"
  run_stdlib_python - "$repo_root" "$compiled_validator" "$base_commit" "$destination" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

repo_root, compiled_validator, base_commit, destination = sys.argv[1:]
harness_paths = [
    "Tools/QwenCleanupBenchmark/Fixtures/cases-v1.json",
    "Tools/QwenCleanupBenchmark/README.md",
    "Tools/QwenCleanupBenchmark/Tests/run-contract-tests.sh",
    "Tools/QwenCleanupBenchmark/qwen_cleanup_helper.py",
    "Tools/QwenCleanupBenchmark/run-qwen-cleanup-benchmark.sh",
    "Tools/QwenCleanupBenchmark/validate_cleanup_candidate.swift",
]
if not isinstance(base_commit, str) or len(base_commit) != 40 or any(character not in "0123456789abcdef" for character in base_commit):
    raise SystemExit("base commit is not an exact lowercase commit identity")

def identity(path):
    path = Path(path)
    path_stat = os.lstat(path)
    if os.path.realpath(path) != str(path) or stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISREG(path_stat.st_mode):
        raise SystemExit(f"provenance path is not a canonical regular file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return {"bytes": path.stat().st_size, "sha256": digest.hexdigest()}

harness_files = {relative: identity(Path(repo_root) / relative) for relative in harness_paths}
value = {
    "schemaVersion": 1,
    "baseCommit": base_commit,
    "harnessFiles": harness_files,
    "compiledValidator": identity(compiled_validator),
}
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

write_summary() {
  local summary_path="$1"
  local evidence_name="$2"
  run_stdlib_python - "$summary_path" "$evidence_name" "$preflight_path" "$validated_path" "$provenance_path" <<'PY'
import json
import os
import sys

summary_path, evidence_name, preflight_path, validated_path, provenance_path = sys.argv[1:]
with open(preflight_path, encoding="utf-8") as handle:
    preflight = json.load(handle)
with open(provenance_path, encoding="utf-8") as handle:
    provenance = json.load(handle)
records = []
with open(validated_path, encoding="utf-8") as handle:
    for line in handle:
        if line.strip():
            records.append(json.loads(line))
if any(record.get("provenance") != provenance for record in records):
    raise SystemExit("validated records do not all bind the exact harness provenance")
summary = {
    "schemaVersion": 1,
    "claimScope": "developer-only-external-qwen-cleanup-benchmark",
    "releaseAdmitted": False,
    "productionIntegrated": False,
    "packagedAppVerified": False,
    "evidenceFile": evidence_name,
    "caseCount": len(records),
    "acceptedCaseCount": sum(bool(record.get("caseAccepted")) for record in records),
    "rejectedCaseCount": sum(not bool(record.get("caseAccepted")) for record in records),
    "oneRequestPerCase": all(record.get("generation", {}).get("requestCount") == 1 for record in records),
    "noRetries": all(record.get("generation", {}).get("retryCount") == 0 for record in records),
    "provenance": provenance,
    "preflight": preflight,
    "modelRuntimeLoaded": bool(records) and all(
        record.get("artifact", {}).get("verificationMode") == "exact-full-artifact"
        and record.get("artifact", {}).get("postLoadVerified") is True
        for record in records
    ),
    "fullArtifactInventoryBound": all(
        len(record.get("artifact", {}).get("requiredInventory", [])) == 13
        for record in records
    ),
    "progressMarkersPersisted": all(
        set(record.get("generation", {}).get("progress", {}))
        == {"modelReady", "generationStarted", "generationFinished"}
        for record in records
    ),
    "notes": [
        "Benchmark evidence is not model admission or Fleck product integration.",
        "No microphone audio or unrelated transcripts are persisted.",
    ],
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

if [[ "$mode" == "smoke" ]]; then
  verify_artifact_shell "$model_root" "1"
else
  verify_artifact_shell "$model_root" "0"
fi
verify_network_deny
export FLECK_QWEN_NETWORK_DENY=1

swift_build_dir=""
private_root=""
cleanup() {
  if [[ -n "$swift_build_dir" && -d "$swift_build_dir" ]]; then
    rm -rf "$swift_build_dir"
  fi
  if [[ -n "$private_root" && -d "$private_root" ]]; then
    rm -rf "$private_root"
  fi
}
trap cleanup EXIT

private_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-benchmark.XXXXXX")"
private_root="$(/bin/realpath "$private_root")"
chmod 700 "$private_root"
case "$private_root/" in
  "$canonical_repo_root/"*|"$canonical_output_root/"*) fail "private benchmark directory is not outside repository/output roots" ;;
esac
snapshot_dir="$private_root/model-snapshot"
mkdir "$snapshot_dir"
chmod 700 "$snapshot_dir"
progress_file="$private_root/progress.jsonl"
: > "$progress_file"
chmod 600 "$progress_file"
output_anchor="$private_root/output-anchor.json"
staging_dir="$private_root/staging"
mkdir "$staging_dir"
chmod 700 "$staging_dir"

copy_snapshot() {
  local name
  for name in "${required_artifacts[@]}"; do
    if ! /bin/cp -c "$model_root/$name" "$snapshot_dir/$name" 2>/dev/null; then
      /bin/cp "$model_root/$name" "$snapshot_dir/$name"
    fi
  done
  chmod 600 "$snapshot_dir"/*
  if [[ "$mode" == "smoke" ]]; then
    verify_artifact_shell "$snapshot_dir" "1"
  else
    verify_artifact_shell "$snapshot_dir" "0"
  fi
}

capture_output_anchor() {
  run_stdlib_python - "$canonical_output_root" "$output_anchor" <<'PY'
import json
import os
import sys

root, anchor_path = sys.argv[1:]
if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
    raise SystemExit("anchored output flags unavailable")
flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
if os.path.realpath(root) != root:
    raise SystemExit("output directory identity is not canonical")
fd = os.open(root, flags)
try:
    identity = os.fstat(fd)
finally:
    os.close(fd)
with open(anchor_path, "w", encoding="utf-8") as handle:
    json.dump({"dev": identity.st_dev, "ino": identity.st_ino}, handle, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

copy_snapshot
capture_output_anchor
build_validator
base_commit="$(/usr/bin/git -C "$repo_root" rev-parse --verify HEAD)" || fail "cannot resolve exact base commit"
preflight_path="$staging_dir/preflight.json"
helper_path_output="$staging_dir/helper.jsonl"
validated_path="$staging_dir/validated.jsonl"
validator_stderr="$staging_dir/validator.stderr"
provenance_path="$staging_dir/provenance.json"
write_provenance "$provenance_path" "$swift_build_dir/validate_cleanup_candidate"

helper_args=(
  --python-executable "$python_executable"
  --runtime-site-packages "$runtime_site_packages"
  --model-root "$snapshot_dir"
  --source-model-root "$model_root"
  --cases-file "$fixture_path"
  --progress-file "$progress_file"
  --provenance-file "$provenance_path"
)
if [[ -n "$case_id" ]]; then
  helper_args+=(--case-id "$case_id")
fi
if [[ "$mode" == "contract" ]]; then
  helper_args+=(
    --test-mode
    --test-artifact-manifest "$test_artifact_manifest"
    --fake-responses "$fake_responses"
    --test-sleep-ms "$test_sleep_ms"
  )
fi

preflight_args=("${helper_args[@]}" --preflight-only)
preflight_code=0
if run_isolated_helper "$preflight_path" "$staging_dir/preflight.stderr" "$progress_file" "${preflight_args[@]}"; then
  preflight_code=0
else
  preflight_code=$?
fi
if (( preflight_code != 0 )); then
  cat "$staging_dir/preflight.stderr" >&2 || true
  if [[ "$FLECK_QWEN_HELPER_FORCED_TERMINATION" -eq 1 ]]; then
    fail "preflight helper exceeded whole-process timeout and was forcibly terminated (nonCooperativeTermination=true)"
  fi
  fail "preflight failed before model invocation"
fi

generation_code=0
if run_isolated_helper "$helper_path_output" "$staging_dir/helper.stderr" "$progress_file" "${helper_args[@]}"; then
  generation_code=0
else
  generation_code=$?
fi
if (( generation_code != 0 )); then
  cat "$staging_dir/helper.stderr" >&2 || true
  if [[ "$FLECK_QWEN_HELPER_FORCED_TERMINATION" -eq 1 ]]; then
    if [[ "$FLECK_QWEN_HELPER_TIMEOUT_REASON" == "generation-deadline" ]]; then
      fail "isolated helper forcibly terminated at the 1,500 ms generation deadline (nonCooperativeTermination=true); no evidence was published"
    fi
    fail "isolated helper forcibly terminated at the whole-process timeout (nonCooperativeTermination=true); no evidence was published"
  fi
  fail "helper failed; no staged evidence was published"
fi

[[ -s "$helper_path_output" ]] || fail "helper produced no per-case JSONL output"
DYLD_LIBRARY_PATH="$swift_build_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  "$swift_build_dir/validate_cleanup_candidate" \
  < "$helper_path_output" \
  > "$validated_path" \
  2> "$validator_stderr" || {
    cat "$validator_stderr" >&2 || true
    fail "Swift envelope/validator CLI failed; no staged evidence was published"
  }

run_stdlib_python - "$validated_path" "$fixture_path" "$case_id" <<'PY'
import json
import sys

validated_path, fixture_path, selected_case_id = sys.argv[1:]
with open(fixture_path, encoding="utf-8") as handle:
    fixture = json.load(handle)
expected_ids = [
    case["id"]
    for case in fixture
    if not selected_case_id or case["id"] == selected_case_id
]
with open(validated_path, encoding="utf-8") as handle:
    records = [json.loads(line) for line in handle if line.strip()]
if len(records) != len(expected_ids):
    raise SystemExit(f"case count mismatch: expected {len(expected_ids)} got {len(records)}")
if [record.get("caseID") for record in records] != expected_ids:
    raise SystemExit("case ordering or identity mismatch")
for record in records:
    generation = record.get("generation", {})
    if generation.get("requestCount") != 1 or generation.get("retryCount") != 0:
        raise SystemExit(f"request/retry contract failed for {record.get('caseID')}")
    if record.get("rawBaseline") != next(case["rawBaseline"] for case in fixture if case["id"] == record["caseID"]):
        raise SystemExit(f"baseline persistence failed for {record.get('caseID')}")
PY

provenance_recheck_path="$staging_dir/provenance-recheck.json"
write_provenance "$provenance_recheck_path" "$swift_build_dir/validate_cleanup_candidate"
cmp -s "$provenance_path" "$provenance_recheck_path" || fail "harness provenance changed during run; no evidence was published"

evidence_stem="qwen-cleanup-benchmark-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
evidence_name="$evidence_stem.jsonl"
summary_name="$evidence_stem.summary.json"
summary_path="$staging_dir/summary.json"
write_summary "$summary_path" "$evidence_name"

publish_exclusive() {
  run_stdlib_python - \
    "$canonical_output_root" \
    "$output_anchor" \
    "$validated_path" \
    "$evidence_name" \
    "$summary_path" \
    "$summary_name" <<'PY'
import json
import os
import sys

root, anchor_path, evidence_source, evidence_name, summary_source, summary_name = sys.argv[1:]
with open(anchor_path, encoding="utf-8") as handle:
    anchor = json.load(handle)
if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
    raise SystemExit("anchored output flags unavailable")
if os.path.realpath(root) != root:
    raise SystemExit("output directory identity changed: canonical path mismatch")
flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
fd = os.open(root, flags)
published_evidence = False
try:
    identity = os.fstat(fd)
    if identity.st_dev != anchor["dev"] or identity.st_ino != anchor["ino"]:
        raise SystemExit("output directory identity changed: device/inode mismatch")
    for source in (evidence_source, summary_source):
        source_stat = os.lstat(source)
        if not os.path.isfile(source) or os.path.islink(source):
            raise SystemExit(f"staged publication source is not a regular file: {source}")
    os.link(evidence_source, evidence_name, dst_dir_fd=fd, follow_symlinks=False)
    published_evidence = True
    try:
        os.link(summary_source, summary_name, dst_dir_fd=fd, follow_symlinks=False)
    except BaseException:
        if published_evidence:
            os.unlink(evidence_name, dir_fd=fd)
        raise
finally:
    os.close(fd)
PY
}

if (( test_pause_before_publish_ms > 0 )); then
  pause_seconds="$(/usr/bin/awk -v milliseconds="$test_pause_before_publish_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
  sleep "$pause_seconds"
fi
publish_exclusive || fail "anchored exclusive publication failed; no redirected evidence was published"

echo "qwen cleanup benchmark evidence: $canonical_output_root/$evidence_name"
echo "qwen cleanup benchmark summary: $canonical_output_root/$summary_name"
