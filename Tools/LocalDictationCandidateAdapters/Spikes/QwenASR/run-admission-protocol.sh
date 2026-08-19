#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly case_plan="$script_dir/Cases/ten-case-plan.jsonl"
runtime_root=""
model_root=""
output=""
english_audio=""
mandarin_audio=""
mixed_en_zh_audio=""
mixed_zh_en_audio=""
silence_audio=""
route=""
capability="batch-final-only"
self_test=false
repetitions=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-root) runtime_root="${2:-}"; shift 2 ;;
    --model-root) model_root="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --english-audio) english_audio="${2:-}"; shift 2 ;;
    --mandarin-audio) mandarin_audio="${2:-}"; shift 2 ;;
    --mixed-en-zh-audio) mixed_en_zh_audio="${2:-}"; shift 2 ;;
    --mixed-zh-en-audio) mixed_zh_en_audio="${2:-}"; shift 2 ;;
    --silence-audio) silence_audio="${2:-}"; shift 2 ;;
    --route) route="${2:-}"; shift 2 ;;
    --capability) capability="${2:-}"; shift 2 ;;
    --repetitions) repetitions="${2:-}"; shift 2 ;;
    --self-test) self_test=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

validate_case_plan() {
  jq -s -e '
    length == 10 and
    all(.[];
      (.routeCapabilities.sherpa.resultSemantics == "batch-final-only") and
      (.routeCapabilities.sherpa.claimsRollingWindowPartials == false) and
      (.evaluationOnlyContextPhrases | type == "array") and
      (.appliedContextPhrases == []) and
      ((has("contextPhrases") | not)) and
      ((has("claimsPartials") | not))
    ) and
    ([.[] | select(.id == "cancellation-active-decode")] | length == 1) and
    ([.[] | select((has("cancellationPoint")) or (has("cancellationClaim")))] | length == 1) and
    ([.[] | select(
      .id == "cancellation-active-decode" and
      .cancellationPoint == "during-active-decode" and
      .cancellationClaim == "unsupported-by-batch-routes"
    )] | length == 1)
  ' "$case_plan" >/dev/null
}

require_route_capability() {
  local requested_route="$1"
  local requested_capability="$2"
  case "$requested_route:$requested_capability" in
    sherpa:batch-final-only)
      ;;
    sherpa:active-cancellation)
      echo "unsupported-active-cancellation-refused:route=$requested_route" >&2
      return 42
      ;;
    sherpa:*)
      echo "unsupported-capability:route=$requested_route capability=$requested_capability" >&2
      return 2
      ;;
    *)
      echo "unsupported-route:$requested_route" >&2
      return 2
      ;;
  esac
}

emit_load() {
  jq -cn --arg id "$1" '{schemaVersion:1,requestID:$id,operation:"load",contextPhrases:[],protectedForms:[]}' >> "$input"
}

emit_unload() {
  jq -cn --arg id "$1" '{schemaVersion:1,requestID:$id,operation:"unload",contextPhrases:[],protectedForms:[]}' >> "$input"
}

emit_transcribe() {
  local request_id="$1"
  local audio_path="$2"
  local locale="$3"
  local evaluation_phrases="$4"
  jq -cn \
    --arg id "$request_id" \
    --argjson phrases "$evaluation_phrases" \
    '{requestID:$id,evaluationOnlyContextPhrases:$phrases,appliedContextPhrases:[]}' \
    >> "$evaluation_metadata"
  jq -cn \
    --arg id "$request_id" \
    --arg audio "$audio_path" \
    --arg locale "$locale" \
    '{schemaVersion:1,requestID:$id,operation:"transcribe",audioPath:$audio,sampleRate:16000,localeIdentifier:$locale,contextPhrases:[],protectedForms:[]}' \
    >> "$input"
}

emit_shutdown() {
  jq -cn --arg id "$1" '{schemaVersion:1,requestID:$id,operation:"shutdown",contextPhrases:[],protectedForms:[]}' >> "$input"
}

generate_requests() {
  : > "$input"
  : > "$evaluation_metadata"
  if [[ "$repetitions" -eq 1 ]]; then
    emit_load load-initial
    emit_transcribe case-english-technical "$english_audio" en-US '["Fleck","SwiftUI"]'
    emit_transcribe case-english-command "$english_audio" en-US '["Package.swift","/fixtures/Fleck"]'
    emit_transcribe case-mandarin-prose "$mandarin_audio" zh-CN '["16 kHz","GB"]'
    emit_transcribe case-mandarin-technical "$mandarin_audio" zh-CN '["SwiftUI","Metal"]'
    emit_transcribe case-english-mandarin "$mixed_en_zh_audio" en-US '["Fleck","本地"]'
    emit_transcribe case-mandarin-english "$mixed_zh_en_audio" zh-CN '["Swift","语音"]'
    emit_transcribe case-dictionary "$english_audio" en-US '["Fleck","canonical"]'
    emit_transcribe case-silence "$silence_audio" en-US '[]'
    emit_transcribe case-repeated "$english_audio" en-US '["Fleck","SwiftUI"]'
    emit_unload unload-repeated
    emit_load reload-repeated
    emit_transcribe reload-transcribe-repeated "$english_audio" en-US '["Fleck","SwiftUI"]'
    emit_unload final-unload-repeated
  else
    for ((index = 1; index <= repetitions; index += 1)); do
      emit_load "load-$index"
      emit_transcribe "transcribe-$index" "$english_audio" en-US '[]'
      emit_unload "unload-$index"
    done
  fi
  emit_shutdown shutdown-final
}

run_self_test() {
  readonly self_test_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-admission-self-test.XXXXXX")"
  trap 'rm -rf "$self_test_root"' RETURN
  readonly fake_preflight="$self_test_root/fake-preflight"
  readonly launch_marker="$self_test_root/preflight-launched"
  readonly input="$self_test_root/requests.jsonl"
  readonly evaluation_metadata="$self_test_root/evaluation-metadata.jsonl"
  printf '#!/usr/bin/env bash\n: > %q\n' "$launch_marker" > "$fake_preflight"
  chmod +x "$fake_preflight"

  if ! validate_case_plan; then
    echo "self-test=final-only-no-partials:fail" >&2
    return 1
  fi
  echo "self-test=final-only-no-partials:pass"

  english_audio="$self_test_root/english.wav"
  mandarin_audio="$self_test_root/mandarin.wav"
  mixed_en_zh_audio="$self_test_root/mixed-en-zh.wav"
  mixed_zh_en_audio="$self_test_root/mixed-zh-en.wav"
  silence_audio="$self_test_root/silence.wav"
  repetitions=1
  generate_requests
  if ! jq -s -e 'all(.[]; .operation != "transcribe" or .contextPhrases == [])' "$input" >/dev/null; then
    echo "self-test=context-not-applied:fail" >&2
    return 1
  fi
  echo "self-test=context-not-applied:pass"
  if ! jq -s -e 'length > 0 and all(.[]; .appliedContextPhrases == [])' "$evaluation_metadata" >/dev/null; then
    echo "self-test=evaluation-context-metadata-only:fail" >&2
    return 1
  fi
  echo "self-test=evaluation-context-metadata-only:pass"

  set +e
  substitution_output="$(
    "$script_dir/run-admission-protocol.sh" \
      --route sherpa \
      --capability batch-final-only \
      --preflight "$fake_preflight" \
      --runtime-root "$self_test_root/runtime" \
      --model-root "$self_test_root/model" \
      --output "$self_test_root/substitution-output" 2>&1
  )"
  substitution_exit=$?
  set -e
  if [[ "$substitution_exit" -ne 2 || "$substitution_output" != *"unknown argument: --preflight"* ]]; then
    echo "self-test=preflight-substitution-rejected:fail" >&2
    return 1
  fi
  if [[ -e "$launch_marker" ]]; then
    echo "self-test=preflight-substitution-launch:fail" >&2
    return 1
  fi
  echo "self-test=preflight-substitution-rejected:pass"

  set +e
  checked_in_output="$(
    "$script_dir/run-admission-protocol.sh" \
      --route sherpa \
      --capability batch-final-only \
      --runtime-root "$self_test_root/runtime" \
      --model-root "$self_test_root/model" \
      --output "$self_test_root/checked-in-output" 2>&1
  )"
  checked_in_exit=$?
  set -e
  if [[ "$checked_in_exit" -ne 2 || "$checked_in_output" != *"artifact-identity-unadmitted"* ]]; then
    echo "self-test=checked-in-preflight-fails-closed:fail" >&2
    printf '%s\n' "$checked_in_output" >&2
    return 1
  fi
  if [[ -e "$launch_marker" ]]; then
    echo "self-test=checked-in-preflight-launch:fail" >&2
    return 1
  fi
  echo "self-test=checked-in-preflight-fails-closed:pass"

  set +e
  refusal_output="$(
    "$script_dir/run-admission-protocol.sh" \
      --route sherpa \
      --capability active-cancellation \
      --runtime-root "$self_test_root/runtime" \
      --model-root "$self_test_root/model" \
      --output "$self_test_root/refusal-output" 2>&1
  )"
  refusal_exit=$?
  set -e
  if [[ "$refusal_exit" -ne 42 || "$refusal_output" != *"unsupported-active-cancellation-refused"* ]]; then
    echo "self-test=unsupported-active-cancellation-refused:fail" >&2
    return 1
  fi
  if [[ -e "$launch_marker" ]]; then
    echo "self-test=unsupported-active-cancellation-launch:fail" >&2
    return 1
  fi
  echo "self-test=unsupported-active-cancellation-refused:pass"
}

if [[ "$self_test" == true ]]; then
  run_self_test
  exit 0
fi

[[ -n "$route" ]] || { echo "--route is required" >&2; exit 2; }
validate_case_plan || { echo "case plan is not final-only and route-specific" >&2; exit 2; }
require_route_capability "$route" "$capability"

for path in "$runtime_root" "$model_root" "$output"; do
  [[ "$path" == /* ]] || { echo "all runtime/model/output paths must be absolute" >&2; exit 2; }
done
[[ "$repetitions" =~ ^[1-9][0-9]*$ ]] || { echo "repetitions must be positive" >&2; exit 2; }
[[ ! -e "$output" ]] || { echo "output already exists: $output" >&2; exit 2; }

readonly output_parent="$(dirname "$output")"
[[ -d "$output_parent" ]] || { echo "output parent is not a directory" >&2; exit 2; }
readonly preflight_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-preflight.XXXXXX")"
readonly preflight_stderr="$(mktemp "${TMPDIR:-/tmp}/fleck-qwen-preflight.XXXXXX")"
trap 'rm -rf "$preflight_root"; rm -f "$preflight_stderr"' EXIT

"$script_dir/Sherpa/build.sh" --output-root "$preflight_root"
readonly checked_in_preflight="$preflight_root/qwen-sherpa-preflight"
[[ -x "$checked_in_preflight" ]] || { echo "checked-in preflight build is not executable" >&2; exit 2; }

set +e
"$checked_in_preflight" \
  --runtime-root "$runtime_root" \
  --model-root "$model_root" \
  --helper-path "/future/qwen-sherpa-helper" \
  > "$output" 2> "$preflight_stderr"
preflight_exit=$?
set -e
cat "$preflight_stderr" >&2
if [[ "$preflight_exit" -ne 0 ]]; then
  echo "preflight-exit=$preflight_exit" >&2
  exit "$preflight_exit"
fi
echo "preflight-admitted=true"
