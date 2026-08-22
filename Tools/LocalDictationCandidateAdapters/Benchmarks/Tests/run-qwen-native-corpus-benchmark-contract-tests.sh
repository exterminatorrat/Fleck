#!/usr/bin/env bash

set -euo pipefail

contract_fail() {
  printf 'contract=assertion-failed:%s\n' "$*" >&2
  exit 1
}

contract_assert() {
  if ! "$@"; then
    contract_fail "$@"
  fi
}

contract_absent() {
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    contract_fail "unexpected-match:$*"
  elif [ "$status" -ne 1 ]; then
    contract_fail "assertion-command-failed:$* status=$status"
  fi
}

negative_assertion_status=0
(contract_assert test 1 -eq 2) >/dev/null 2>&1 || negative_assertion_status=$?
contract_assert test "$negative_assertion_status" -ne 0
echo "contract=explicit-assertion-failure-self-test:pass"

readonly test_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly candidate_dir="$test_dir/../Candidates"
readonly source="$candidate_dir/QwenNativeCorpusBenchmark.swift"
readonly runner="$candidate_dir/run-qwen-native-corpus-benchmark.sh"
readonly metadata="$candidate_dir/qwen3-asr-0.6b-int8.json"

if [[ ! -f "$source" || ! -f "$runner" || ! -f "$metadata" ]]; then
  echo "red=benchmark-candidate-files-missing" >&2
  exit 1
fi

readonly repo_root="$(cd "$test_dir/../../../.." && pwd -P)"
readonly model_evaluation_source="$repo_root/Sources/FleckModelEvaluation/ModelEvaluation.swift"
readonly evidence_source="$repo_root/Sources/FleckModelEvaluation/CandidateBenchmarkEvidence.swift"
readonly artifact_inventory_source="$repo_root/Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateRunner/ArtifactInventory.swift"
readonly temp_root="$(mktemp -d /Users/harryjin/.codex/fleck-qwen-native-contract.XXXXXX)"
trap 'rm -rf "$temp_root"' EXIT
readonly build_dir="$temp_root/build"
mkdir -p "$build_dir"

swiftc -O -parse-as-library \
  "$source" \
  "$model_evaluation_source" \
  "$evidence_source" \
  "$artifact_inventory_source" \
  -o "$build_dir/qwen-native-corpus-benchmark"

readonly self_test_log="$temp_root/self-test.log"
"$runner" --self-test >"$self_test_log"
for contract in \
  "contract=duplicate-output-keys:pass" \
  "contract=unknown-output-keys:pass" \
  "contract=partial-output-rejected:pass" \
  "contract=helper-output-flood-rejected:pass" \
  "contract=request-order-rejected:pass" \
  "contract=output-race-file-rejected:pass" \
  "contract=output-race-directory-rejected:pass" \
  "contract=output-race-symlink-rejected:pass"; do
  contract_assert /usr/bin/grep -Fqx "$contract" "$self_test_log"
done
echo "contract=parser-and-publication-self-tests:pass"

for token in \
  "installed-artifact-inventory.json" \
  "native-decode-blocked" \
  "process-level-forced-termination-not-cooperative" \
  "renameatx_np" \
  "RENAME_EXCL" \
  "partial-helper-output" \
  "duplicate-helper-output-key" \
  "helper-output-flood" \
  "helper-output-request-order" \
  "supportsCancellation" \
  "CandidateBenchmarkEvidence" \
  "nonCanonicalDiagnostics" \
  "runOfflineNetworkProbe" \
  "unexpectedConnectionCount" \
  "ArtifactInventory.collect" \
  "cooperativeFinishDeadline" \
  "helper-shutdown-timeout-forced-termination"; do
  contract_assert /usr/bin/grep -Fq -- "$token" "$source"
done
contract_absent /usr/bin/grep -Fq -- 'private struct CandidateBenchmarkEvidence' "$source"
contract_absent /usr/bin/grep -Fq -- '--offline-attestation' "$source" "$runner"
for token in \
  "sandbox-exec" \
  "deny network" \
  "PATH=/usr/bin:/bin" \
  "LC_ALL=C" \
  "http_proxy" \
  "env -i" \
  "CandidateBenchmarkEvidence.swift" \
  "ArtifactInventory.swift"; do
  contract_assert /usr/bin/grep -Fq -- "$token" "$runner"
done
contract_absent /usr/bin/grep -Eiq '(^|[^a-z])retry([^a-z]|$)' "$source" "$runner"
echo "contract=static-safety-and-no-retry:pass"

readonly prepared_root="$temp_root/prepared"
readonly public_root="$temp_root/public-human"
readonly composite_root="$temp_root/composite"
readonly fake_metadata="$temp_root/fake-metadata.json"
readonly public_manifest="$temp_root/public-manifest.json"
readonly composite_manifest="$temp_root/composite-manifest.json"
readonly helper="$temp_root/fake-helper.sh"
readonly hang_helper="$temp_root/hang-after-shutdown-helper.sh"
readonly helper_log="$temp_root/helper-launches.log"
mkdir -p "$prepared_root/runtime" "$prepared_root/model" "$public_root/audio" "$composite_root/audio"

python3 - "$metadata" "$prepared_root" "$public_root" "$composite_root" \
  "$fake_metadata" "$public_manifest" "$composite_manifest" "$helper" "$helper_log" <<'PY'
import hashlib
import json
import os
import pathlib
import shlex
import sys
import wave

metadata_path, prepared_root, public_root, composite_root, fake_metadata_path, public_manifest_path, composite_manifest_path, helper_path, log_path = sys.argv[1:]
prepared_root = pathlib.Path(prepared_root)
public_root = pathlib.Path(public_root)
composite_root = pathlib.Path(composite_root)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def write_wav(path, sample_count):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(16000)
        stream.writeframes(bytes((0, 0)) * sample_count)
    data = path.read_bytes()
    return digest(data), len(data)

def source():
    return {
        "dataset": "google/fleurs",
        "repository": "https://huggingface.co/datasets/google/fleurs",
        "revision": "a3c817cbf7c08863e0c472861c7c39e27ce7f38e",
        "license": "CC-BY-4.0",
        "licenseURL": "https://creativecommons.org/licenses/by/4.0/",
        "licenseMetadataURL": "https://huggingface.co/datasets/google/fleurs",
        "files": {
            "englishValidation": {
                "path": "data/english_validation.tar",
                "url": "https://example.invalid/english_validation.tar",
                "sha256": "7c3eebdff31e1c510b78e51319e5b9779429b87c9895f2e5f3005bfe68854c65",
                "byteCount": 1
            },
            "mandarinValidation": {
                "path": "data/mandarin_validation.tar",
                "url": "https://example.invalid/mandarin_validation.tar",
                "sha256": "18698f80879a221f68318a4ccb8752b74c2f5bf521af0e0011b07e4670ea62ad",
                "byteCount": 1
            }
        }
    }

def public_case(language, index):
    prefix = "en" if language == "english" else "zh"
    case_id = f"{prefix}-{index:02d}"
    relative = f"audio/{case_id}.wav"
    reference = "hello" if language == "english" else "你好"
    audio_hash, audio_bytes = write_wav(public_root / relative, 1600)
    return {
        "id": case_id,
        "sourceFile": relative,
        "language": language,
        "sourceClass": "publicHuman",
        "audioSHA256": audio_hash,
        "audioDurationMilliseconds": 100,
        "audioBytes": audio_bytes,
        "reference": reference,
        "protectedExpectations": [],
        "naturalCodeSwitch": False
    }

public_cases = [public_case("english", index) for index in range(12)]
public_cases += [public_case("mandarin", index) for index in range(12)]
public_by_id = {item["id"]: item for item in public_cases}

composite_cases = []
for index in range(12):
    case_id = f"mix-{index:02d}"
    relative = f"audio/{case_id}.wav"
    audio_hash, audio_bytes = write_wav(composite_root / relative, 3200)
    composite_cases.append({
        "id": case_id,
        "sourceFile": relative,
        "language": "mixed",
        "sourceClass": "publicHumanComposite",
        "audioSHA256": audio_hash,
        "audioDurationMilliseconds": 200,
        "audioBytes": audio_bytes,
        "reference": "hello 你好",
        "protectedExpectations": [],
        "naturalCodeSwitch": False,
        "codeSwitchSpans": [
            {
                "language": "en_us",
                "sourceCaseID": f"en-{index:02d}",
                "startSample": 0,
                "endSample": 1600,
                "reference": public_by_id[f"en-{index:02d}"]["reference"]
            },
            {
                "language": "cmn_hans_cn",
                "sourceCaseID": f"zh-{index:02d}",
                "startSample": 1600,
                "endSample": 3200,
                "reference": public_by_id[f"zh-{index:02d}"]["reference"]
            }
        ]
    })

def manifest(cases):
    return {
        "schemaVersion": 1,
        "manifestID": "fake-fleurs-public-human-v1",
        "immutable": True,
        "source": source(),
        "cases": cases
    }

pathlib.Path(public_manifest_path).write_text(json.dumps(manifest(public_cases), sort_keys=True, separators=(",", ":")) + "\n")
pathlib.Path(composite_manifest_path).write_text(json.dumps(manifest(composite_cases), sort_keys=True, separators=(",", ":")) + "\n")

(prepared_root / "runtime" / "fake-runtime.bin").write_bytes(b"r")
(prepared_root / "model" / "fake-model.bin").write_bytes(b"m")
os.symlink("../model/fake-model.bin", prepared_root / "runtime" / "model-link")
runtime_bytes = (prepared_root / "runtime" / "fake-runtime.bin").read_bytes()
model_bytes = (prepared_root / "model" / "fake-model.bin").read_bytes()
symlink_target = "../model/fake-model.bin"
inventory = {
    "archives": [
        {"fileName": "fake-runtime.zip", "sha256": "a" * 64, "sizeBytes": 1},
        {"fileName": "fake-model.tar", "sha256": "b" * 64, "sizeBytes": 2}
    ],
    "candidate": "qwen3-asr-0.6b-int8",
    "installedFiles": [
        {"path": "runtime/fake-runtime.bin", "sha256": digest(runtime_bytes), "sizeBytes": len(runtime_bytes)},
        {"path": "model/fake-model.bin", "sha256": digest(model_bytes), "sizeBytes": len(model_bytes)}
    ],
    "installedSymlinks": [
        {"path": "runtime/model-link", "target": symlink_target}
    ],
    "releaseAdmitted": False,
    "schemaVersion": 1,
    "status": "fake-unadmitted",
    "totalInstalledBytes": len(runtime_bytes) + len(model_bytes)
}
inventory_bytes = json.dumps(inventory, sort_keys=True, separators=(",", ":")).encode() + b"\n"
(prepared_root / "installed-artifact-inventory.json").write_bytes(inventory_bytes)

metadata = json.loads(pathlib.Path(metadata_path).read_text())
metadata["model"]["convertedRevision"] = "fake-model-revision"
metadata["model"]["archive"].update({
    "id": "fake-model-archive",
    "fileName": "fake-model.tar",
    "revision": "fake-model-archive-revision",
    "sha256": "b" * 64,
    "sizeBytes": 2
})
metadata["runtime"]["revision"] = "fake-runtime-revision"
metadata["runtime"]["sourceCommit"] = "fake-runtime-commit"
metadata["runtime"]["archive"].update({
    "id": "fake-runtime-archive",
    "fileName": "fake-runtime.zip",
    "revision": "fake-runtime-archive-revision",
    "sha256": "a" * 64,
    "sizeBytes": 1
})
metadata["inventory"].update({
    "sha256": digest(inventory_bytes),
    "sizeBytes": len(inventory_bytes),
    "status": "fake-unadmitted"
})

quoted_log = shlex.quote(log_path)
helper_script = f"""#!/bin/sh
set -eu
printf '%s\n' launch >> {quoted_log}
probe=0
for argument do
  if [ "$argument" = "--probe-blocked-decode" ]; then
    probe=1
  fi
done
while IFS= read -r line; do
  request_id=$(printf '%s' "$line" | /usr/bin/grep -o '"requestID":"[^"]*"' | /usr/bin/sed 's/.*"requestID":"//;s/"$//')
  operation=$(printf '%s' "$line" | /usr/bin/grep -o '"operation":"[^"]*"' | /usr/bin/sed 's/.*"operation":"//;s/"$//')
  printf 'request=%s\n' "$operation" >> {quoted_log}
  case "$operation" in
    load)
      printf '%s\n' '{{"schemaVersion":1,"event":"ready","requestID":"'"$request_id"'","runtimeVersion":"fake-runtime-revision","modelRevision":"fake-model-revision"}}'
      printf '%s\n' 'capabilities resultSemantics=batch-final-only supportsCancellation=false supportsCooperativeDecodeCancellation=false supportsHotwords=false releaseAdmitted=false' >&2
      ;;
    transcribe)
      if [ "$probe" = 1 ]; then
        printf '%s\n' native-decode-blocked >&2
        while :; do /bin/sleep 1; done
      fi
      if printf '%s' "$line" | /usr/bin/grep -Fq '"localeIdentifier":"zh-CN"'; then
        transcript='你好'
      elif printf '%s' "$line" | /usr/bin/grep -Fq '"localeIdentifier":"auto"'; then
        transcript='hello 你好'
      else
        transcript='hello'
      fi
      printf '%s\n' '{{"schemaVersion":1,"event":"final","requestID":"'"$request_id"'","transcript":"'"$transcript"'"}}'
      printf 'measurement requestID=%s elapsedMs=0.25\n' "$request_id" >&2
      ;;
    unload|shutdown)
      printf '%s\n' '{{"schemaVersion":1,"event":"unloaded","requestID":"'"$request_id"'"}}'
      if [ "$operation" = shutdown ]; then
        exit 0
      fi
      ;;
    *)
      printf '%s\n' '{{"schemaVersion":1,"event":"failure","requestID":"'"$request_id"'","code":"unsupported-operation","message":"unsupported-operation"}}'
      ;;
  esac
done
"""
pathlib.Path(helper_path).write_text(helper_script)
os.chmod(helper_path, 0o755)
helper_bytes = pathlib.Path(helper_path).read_bytes()
metadata["helperBuild"] = {
    "id": "fake-helper-build",
    "executableFileName": pathlib.Path(helper_path).name,
    "sha256": digest(helper_bytes),
    "sizeBytes": len(helper_bytes),
    "modelID": metadata["model"]["id"],
    "modelRevision": metadata["model"]["convertedRevision"],
    "runtimeID": metadata["runtime"]["id"],
    "runtimeRevision": metadata["runtime"]["revision"],
    "status": "fake-accepted-development-build"
}
pathlib.Path(fake_metadata_path).write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
pathlib.Path(log_path).write_text("")
PY

run_benchmark() {
  local destination="$1"
  local metadata_path="$2"
  local helper_path="$helper"
  local public_manifest_path="$public_manifest"
  local composite_manifest_path="$composite_manifest"
  if [[ "$#" -ge 3 ]]; then public_manifest_path="$3"; fi
  if [[ "$#" -ge 4 ]]; then composite_manifest_path="$4"; fi
  if [[ "$#" -ge 5 ]]; then helper_path="$5"; fi
  /usr/bin/env -i PATH=/usr/bin:/bin \
    LC_ALL=C "$build_dir/qwen-native-corpus-benchmark" \
    --prepared-root "$prepared_root" \
    --helper "$helper_path" \
    --public-human-manifest "$public_manifest_path" \
    --public-human-root "$public_root" \
    --composite-manifest "$composite_manifest_path" \
    --composite-root "$composite_root" \
    --repo-root "$repo_root" \
    --contract-test \
    --output-root "$destination" \
    --metadata "$metadata_path"
}

readonly real_output="$temp_root/real-output"
run_benchmark "$real_output" "$fake_metadata"

python3 - "$real_output" "$helper_log" <<'PY'
import json
import pathlib
import sys

output, log_path = map(pathlib.Path, sys.argv[1:])
evidence = json.loads((output / "candidate-benchmark-evidence-v2.json").read_text())
evaluation = json.loads((output / "model-evaluation-run-input-v1.json").read_text())
transcripts = (output / "transcripts.jsonl").read_text().splitlines()

assert evidence["schemaVersion"] == 2
assert evidence["evidenceClasses"] == ["publicHuman", "publicHumanComposite"]
assert len(evidence["cases"]) == 36
assert len(set(case["id"] for case in evidence["cases"])) == 36
assert [case["sourceClass"] for case in evidence["cases"][:12]] == ["publicHuman"] * 12
assert [case["sourceClass"] for case in evidence["cases"][12:24]] == ["publicHuman"] * 12
assert [case["sourceClass"] for case in evidence["cases"][24:]] == ["publicHumanComposite"] * 12
assert all(case["claimsNaturalCodeSwitch"] is False for case in evidence["cases"])
assert all(case["hypothesis"] for case in evidence["cases"])
assert all(case["timing"]["isCold"] is False for case in evidence["cases"])
assert all(case["timing"]["fileDecodeMilliseconds"] == case["timing"]["stopToFinalMilliseconds"] for case in evidence["cases"])
assert len(evidence["warmRun"]["caseOrder"]) == 36
assert evidence["warmRun"]["caseOrder"] == [case["id"] for case in evidence["cases"]]
def nearest_rank(values, percentile):
    return sorted(values)[max(0, int(__import__("math").ceil(percentile * len(values))) - 1)]
latency = evidence["aggregate"]["latency"]
assert set(latency) == {"warmP50Milliseconds", "warmP95Milliseconds"}
canonical_wall = [case["timing"]["fileDecodeMilliseconds"] for case in evidence["cases"]]
assert latency["warmP50Milliseconds"] == nearest_rank(canonical_wall, 0.50)
assert latency["warmP95Milliseconds"] == nearest_rank(canonical_wall, 0.95)
noncanonical = evidence["nonCanonicalDiagnostics"]
assert noncanonical["canonical"] is False
assert len(noncanonical["coldRuns"]) == 5
assert [run["language"] for run in noncanonical["coldRuns"]] == ["english", "english", "mandarin", "mandarin", "mixed"]
assert all(run["launchToFinalMilliseconds"] > run["requestToFinalMilliseconds"] > 0 for run in noncanonical["coldRuns"])
assert all(run["helperNativeDecodeMilliseconds"] == 0.25 for run in noncanonical["coldRuns"])
assert all(run["launchToFinalMilliseconds"] > run["helperNativeDecodeMilliseconds"] for run in noncanonical["coldRuns"])
assert noncanonical["freshProcessLaunchToFinalTiming"]["p50Milliseconds"] == nearest_rank(
    [run["launchToFinalMilliseconds"] for run in noncanonical["coldRuns"]], 0.50
)
assert noncanonical["freshProcessLaunchToFinalTiming"]["p95Milliseconds"] == nearest_rank(
    [run["launchToFinalMilliseconds"] for run in noncanonical["coldRuns"]], 0.95
)
assert noncanonical["wallRequestToFinalTiming"]["p50Milliseconds"] == nearest_rank(
    [run["requestToFinalMilliseconds"] for run in noncanonical["coldRuns"]], 0.50
)
assert noncanonical["helperNativeDecodeTiming"]["p50Milliseconds"] == 0.25
assert noncanonical["helperNativeDecodeTiming"]["p95Milliseconds"] == 0.25
assert "coldRuns" not in evidence
assert evidence["privacy"]["enforced"] is False
assert evidence["privacy"]["claimsVerifiedOffline"] is False
assert evidence["privacy"]["unexpectedConnectionCount"] == 0
assert "unexpectedNetworkConnectionCount" not in evidence["privacy"]
assert "attestationToken" not in evidence["privacy"]
assert evidence["aggregate"]["lifecycleSummary"]["reloadSucceeded"] is False
assert evidence["aggregate"]["lifecycleSummary"]["allSucceeded"] is False
assert "reloadOutcome" not in evidence["aggregate"]["lifecycleSummary"]
assert "allMeasuredSucceeded" not in evidence["aggregate"]["lifecycleSummary"]
assert evidence["inputs"]["preparedRoot"] == str(output.parent / "prepared")
assert evidence["lifecycle"]["reload"]["outcome"] == "cancelled"
assert evidence["nonCanonicalDiagnostics"]["reloadOutcome"] == "notMeasured"
assert evidence["nonCanonicalDiagnostics"]["reloadReason"] == "not-run-by-corpus-benchmark"
assert evidence["cancellation"]["outcome"] == "forced"
unsupported_cancellation = evidence["cancellation"]["unsupportedProtocolCancellation"]
assert unsupported_cancellation["status"] == "not-sent-advertised-unsupported"
assert unsupported_cancellation["advertisedUnsupported"] is True
assert unsupported_cancellation["requestWritten"] is False
assert unsupported_cancellation["processTerminationRequestedAfterPositiveStart"] is True
assert "requestWritten" + "AfterPositiveStart" not in unsupported_cancellation
assert "request" + "Operation" not in unsupported_cancellation
assert evidence["cancellation"]["noLateFinal"] is True
assert evidence["gate"]["automatedCandidatePass"] is False
assert evidence["gate"]["releaseAdmitted"] is False
assert evidence["truthFlags"] == {
    "automatedCandidatePass": False,
    "productionIntegrated": False,
    "packagedAppVerified": False,
    "releaseAdmitted": False
}
assert evidence["productionIntegrated"] is False
assert evidence["packagedAppVerified"] is False
assert evidence["releaseAdmitted"] is False
assert evaluation["schemaVersion"] == 1
assert evaluation["unexpectedNetworkConnectionCount"] == 0
assert len(evaluation["cases"]) == 36
assert {case["language"] for case in evaluation["cases"]} == {"english", "mandarin", "mixed"}
assert len(transcripts) == 36
assert all("partials" in json.loads(line) and not json.loads(line)["partials"] for line in transcripts)
launches = [line for line in log_path.read_text().splitlines() if line == "launch"]
assert len(launches) == 7, len(launches)
assert "request=cancel" not in log_path.read_text().splitlines()
PY
validation_log="$temp_root/evidence-validation.log"
"$build_dir/qwen-native-corpus-benchmark" --validate-evidence "$real_output/candidate-benchmark-evidence-v2.json" >"$validation_log"
contract_assert /usr/bin/grep -Fqx "candidate-benchmark-evidence-v2:valid" "$validation_log"
echo "contract=warm-36-cold-5-cancel-and-evaluation-output:pass"

readonly unattested_output="$temp_root/unattested-output"
unattested_result=0
"$build_dir/qwen-native-corpus-benchmark" \
  --prepared-root "$prepared_root" \
  --helper "$helper" \
  --public-human-manifest "$public_manifest" \
  --public-human-root "$public_root" \
  --composite-manifest "$composite_manifest" \
  --composite-root "$composite_root" \
  --repo-root "$repo_root" \
  --output-root "$unattested_output" \
  --metadata "$fake_metadata" >"$temp_root/unattested.log" 2>&1 || unattested_result=$?
contract_assert test "$unattested_result" -ne 0
if /usr/bin/grep -Fq "outputRoot=" "$temp_root/unattested.log"; then
  echo "contract=unattested-run-published-output" >&2
  exit 1
fi
contract_assert test ! -e "$unattested_output"
contract_assert test ! -L "$unattested_output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
echo "contract=unattested-run-cannot-claim-offline:pass"

readonly forged_token_output="$temp_root/forged-token-output"
forged_token_result=0
"$build_dir/qwen-native-corpus-benchmark" \
  --prepared-root "$prepared_root" \
  --helper "$helper" \
  --public-human-manifest "$public_manifest" \
  --public-human-root "$public_root" \
  --composite-manifest "$composite_manifest" \
  --composite-root "$composite_root" \
  --repo-root "$repo_root" \
  --offline-attestation "sandbox-network-denied-v1:EPERM" \
  --output-root "$forged_token_output" \
  --metadata "$fake_metadata" >"$temp_root/forged-token.log" 2>&1 || forged_token_result=$?
contract_assert test "$forged_token_result" -ne 0
contract_assert test ! -e "$forged_token_output"
contract_assert test ! -L "$forged_token_output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
echo "contract=caller-token-cannot-claim-offline:pass"

readonly bad_metadata="$temp_root/bad-inventory-metadata.json"
python3 - "$fake_metadata" "$bad_metadata" <<'PY'
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
metadata = json.loads(source.read_text())
metadata["inventory"]["sha256"] = "0" * 64
destination.write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
PY

expect_failure() {
  local destination="$1"
  local metadata_path="$2"
  local result=0
  if [[ "$#" -ge 4 ]]; then
    run_benchmark "$destination" "$metadata_path" "$3" "$4" >"$temp_root/failure.log" 2>&1 || result=$?
  elif [[ "$#" -ge 3 ]]; then
    run_benchmark "$destination" "$metadata_path" "$3" >"$temp_root/failure.log" 2>&1 || result=$?
  else
    run_benchmark "$destination" "$metadata_path" >"$temp_root/failure.log" 2>&1 || result=$?
  fi
  if [[ "$result" == 0 ]]; then
    echo "contract=expected-failure-missing:$destination" >&2
    exit 1
  fi
}

expect_failure "$temp_root/identity-failure-output" "$bad_metadata"
contract_assert test ! -e "$temp_root/identity-failure-output"
contract_assert test ! -L "$temp_root/identity-failure-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
echo "contract=identity-before-helper-launch:pass"

printf '%s' tampered >"$prepared_root/runtime/fake-runtime.bin"
expect_failure "$temp_root/tampered-prepared-file-output" "$fake_metadata"
contract_assert test ! -e "$temp_root/tampered-prepared-file-output"
contract_assert test ! -L "$temp_root/tampered-prepared-file-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
printf '%s' r >"$prepared_root/runtime/fake-runtime.bin"
echo "contract=prepared-file-tamper-before-helper-launch:pass"

printf '%s' undeclared >"$prepared_root/runtime/undeclared.bin"
expect_failure "$temp_root/undeclared-prepared-file-output" "$fake_metadata"
contract_assert test ! -e "$temp_root/undeclared-prepared-file-output"
contract_assert test ! -L "$temp_root/undeclared-prepared-file-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
rm "$prepared_root/runtime/undeclared.bin"
echo "contract=prepared-undeclared-file-before-helper-launch:pass"

rm "$prepared_root/runtime/model-link"
ln -s ../../outside "$prepared_root/runtime/model-link"
expect_failure "$temp_root/symlink-target-output" "$fake_metadata"
contract_assert test ! -e "$temp_root/symlink-target-output"
contract_assert test ! -L "$temp_root/symlink-target-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
rm "$prepared_root/runtime/model-link"
ln -s ../model/fake-model.bin "$prepared_root/runtime/model-link"
ln -s ../model/fake-model.bin "$prepared_root/runtime/undeclared-link"
expect_failure "$temp_root/undeclared-symlink-output" "$fake_metadata"
contract_assert test ! -e "$temp_root/undeclared-symlink-output"
contract_assert test ! -L "$temp_root/undeclared-symlink-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
rm "$prepared_root/runtime/undeclared-link"
echo "contract=prepared-symlink-target-and-declaration-before-helper-launch:pass"

readonly bad_aggregate_metadata="$temp_root/bad-aggregate-metadata.json"
readonly original_inventory="$temp_root/original-inventory.json"
cp "$prepared_root/installed-artifact-inventory.json" "$original_inventory"
python3 - "$fake_metadata" "$prepared_root/installed-artifact-inventory.json" "$bad_aggregate_metadata" <<'PY'
import json
import pathlib
import sys

source, inventory_path, destination = map(pathlib.Path, sys.argv[1:])
metadata = json.loads(source.read_text())
inventory = json.loads(inventory_path.read_text())
inventory["totalInstalledBytes"] = 999
inventory_bytes = (json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()
inventory_path.write_bytes(inventory_bytes)
metadata["inventory"]["sha256"] = __import__("hashlib").sha256(inventory_bytes).hexdigest()
metadata["inventory"]["sizeBytes"] = len(inventory_bytes)
destination.write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
PY
expect_failure "$temp_root/prepared-aggregate-mismatch-output" "$bad_aggregate_metadata"
contract_assert test ! -e "$temp_root/prepared-aggregate-mismatch-output"
contract_assert test ! -L "$temp_root/prepared-aggregate-mismatch-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq 7
cp "$original_inventory" "$prepared_root/installed-artifact-inventory.json"
echo "contract=prepared-aggregate-mismatch-before-helper-launch:pass"

readonly hang_metadata="$temp_root/hang-helper-metadata.json"
python3 - "$helper" "$hang_helper" "$fake_metadata" "$hang_metadata" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

source_path, hang_path, metadata_path, hang_metadata_path = map(pathlib.Path, sys.argv[1:])
source = source_path.read_text()
needle = '''      if [ "$operation" = shutdown ]; then
        exit 0
      fi'''
replacement = '''      if [ "$operation" = shutdown ]; then
        while :; do /bin/sleep 1; done
      fi'''
assert needle in source
hang_path.write_text(source.replace(needle, replacement))
os.chmod(hang_path, 0o755)
hang_bytes = hang_path.read_bytes()
metadata = json.loads(metadata_path.read_text())
metadata["helperBuild"].update({
    "executableFileName": hang_path.name,
    "sha256": hashlib.sha256(hang_bytes).hexdigest(),
    "sizeBytes": len(hang_bytes),
})
hang_metadata_path.write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
PY

hang_output="$temp_root/hang-after-shutdown-output"
hang_test_result=0
/usr/bin/python3 - "$build_dir/qwen-native-corpus-benchmark" \
  --prepared-root "$prepared_root" \
  --helper "$hang_helper" \
  --public-human-manifest "$public_manifest" \
  --public-human-root "$public_root" \
  --composite-manifest "$composite_manifest" \
  --composite-root "$composite_root" \
  --repo-root "$repo_root" \
  --contract-test \
  --output-root "$hang_output" \
  --metadata "$hang_metadata" >"$temp_root/hang-after-shutdown.log" 2>&1 <<'PY' || hang_test_result=$?
import os
import signal
import subprocess
import sys

command = sys.argv[1:]
process = subprocess.Popen(command, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"}, start_new_session=True)
try:
    status = process.wait(timeout=8)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    raise SystemExit("cooperative shutdown test timed out")
if status == 0:
    raise SystemExit("cooperative shutdown hang unexpectedly succeeded")
PY
contract_assert test "$hang_test_result" -eq 0
contract_assert test ! -e "$hang_output"
contract_assert test ! -L "$hang_output"
readonly helper_launch_baseline_after_hang="$(grep -c '^launch$' "$helper_log" || true)"
contract_assert test "$helper_launch_baseline_after_hang" -eq 8
echo "contract=shutdown-ack-hang-is-bounded-and-fails:pass"

readonly bad_helper_metadata="$temp_root/bad-helper-receipt-metadata.json"
python3 - "$fake_metadata" "$bad_helper_metadata" <<'PY'
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
metadata = json.loads(source.read_text())
metadata["helperBuild"]["sha256"] = "0" * 64
destination.write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
PY
expect_failure "$temp_root/helper-receipt-failure-output" "$bad_helper_metadata"
contract_assert test ! -e "$temp_root/helper-receipt-failure-output"
contract_assert test ! -L "$temp_root/helper-receipt-failure-output"
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq "$helper_launch_baseline_after_hang"
echo "contract=helper-build-receipt-before-launch:pass"

readonly bad_hash_manifest="$temp_root/bad-audio-hash-manifest.json"
readonly bad_count_manifest="$temp_root/bad-count-manifest.json"
readonly bad_composite_manifest="$temp_root/bad-composite-truth-manifest.json"
python3 - "$public_manifest" "$composite_manifest" "$bad_hash_manifest" "$bad_count_manifest" "$bad_composite_manifest" <<'PY'
import copy
import json
import pathlib
import sys

public_path, composite_path, bad_hash_path, bad_count_path, bad_composite_path = map(pathlib.Path, sys.argv[1:])
public = json.loads(public_path.read_text())
composite = json.loads(composite_path.read_text())

bad_hash = copy.deepcopy(public)
bad_hash["cases"][0]["audioSHA256"] = "0" * 64
pathlib.Path(bad_hash_path).write_text(json.dumps(bad_hash, sort_keys=True, indent=2) + "\n")

bad_count = copy.deepcopy(public)
bad_count["cases"] = bad_count["cases"][:-1]
pathlib.Path(bad_count_path).write_text(json.dumps(bad_count, sort_keys=True, indent=2) + "\n")

bad_composite = copy.deepcopy(composite)
bad_composite["cases"][0]["language"] = "english"
bad_composite["cases"][0]["naturalCodeSwitch"] = True
pathlib.Path(bad_composite_path).write_text(json.dumps(bad_composite, sort_keys=True, indent=2) + "\n")
PY
expect_failure "$temp_root/bad-hash-output" "$fake_metadata" "$bad_hash_manifest" "$composite_manifest"
expect_failure "$temp_root/bad-count-output" "$fake_metadata" "$bad_count_manifest" "$composite_manifest"
expect_failure "$temp_root/bad-composite-output" "$fake_metadata" "$public_manifest" "$bad_composite_manifest"
for destination in \
  "$temp_root/bad-hash-output" \
  "$temp_root/bad-count-output" \
  "$temp_root/bad-composite-output"; do
  contract_assert test ! -e "$destination"
  contract_assert test ! -L "$destination"
done
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq "$helper_launch_baseline_after_hang"
echo "contract=manifest-hash-count-language-composite-validation:pass"

printf '%s\n' existing >"$temp_root/existing-file-output"
mkdir "$temp_root/existing-directory-output"
mkdir "$temp_root/symlink-target"
ln -s "$temp_root/symlink-target" "$temp_root/existing-symlink-output"
for destination in \
  "$temp_root/existing-file-output" \
  "$temp_root/existing-directory-output" \
  "$temp_root/existing-symlink-output"; do
  expect_failure "$destination" "$fake_metadata"
done
contract_assert test "$(grep -c '^launch$' "$helper_log" || true)" -eq "$helper_launch_baseline_after_hang"
echo "contract=output-file-directory-symlink-races:pass"

echo "contract=all-qwen-native-corpus-contracts:pass"
