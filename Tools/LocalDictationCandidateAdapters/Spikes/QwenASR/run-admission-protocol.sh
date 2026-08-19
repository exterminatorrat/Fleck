#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly case_plan="$script_dir/Cases/ten-case-plan.jsonl"
runtime_root=""
model_root=""
adapter=""
output=""
english_audio=""
mandarin_audio=""
mixed_en_zh_audio=""
mixed_zh_en_audio=""
silence_audio=""
backend=""
route=""
capability="batch-final-only"
self_test=false
repetitions=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-root) runtime_root="${2:-}"; shift 2 ;;
    --model-root) model_root="${2:-}"; shift 2 ;;
    --adapter) adapter="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --english-audio) english_audio="${2:-}"; shift 2 ;;
    --mandarin-audio) mandarin_audio="${2:-}"; shift 2 ;;
    --mixed-en-zh-audio) mixed_en_zh_audio="${2:-}"; shift 2 ;;
    --mixed-zh-en-audio) mixed_zh_en_audio="${2:-}"; shift 2 ;;
    --silence-audio) silence_audio="${2:-}"; shift 2 ;;
    --backend) backend="${2:-}"; shift 2 ;;
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

run_self_test() {
  readonly self_test_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-admission-self-test.XXXXXX")"
  trap 'rm -rf "$self_test_root"' RETURN
  readonly launch_marker="$self_test_root/adapter-launched"
  readonly fake_adapter="$self_test_root/fake-adapter"
  printf '#!/usr/bin/env bash\n: > %q\n' "$launch_marker" > "$fake_adapter"
  chmod +x "$fake_adapter"

  if ! validate_case_plan; then
    echo "self-test=final-only-no-partials:fail" >&2
    return 1
  fi
  echo "self-test=final-only-no-partials:pass"

  for self_test_route in sherpa; do
    set +e
    refusal_output="$(
      "$script_dir/run-admission-protocol.sh" \
        --route "$self_test_route" \
        --capability active-cancellation \
        --runtime-root "$self_test_root/runtime" \
        --model-root "$self_test_root/model" \
        --adapter "$fake_adapter" \
        --output "$self_test_root/output-$self_test_route" \
        --english-audio "$self_test_root/english.wav" \
        --mandarin-audio "$self_test_root/mandarin.wav" \
        --mixed-en-zh-audio "$self_test_root/mixed-en-zh.wav" \
        --mixed-zh-en-audio "$self_test_root/mixed-zh-en.wav" \
        --silence-audio "$self_test_root/silence.wav" \
        --backend mlx 2>&1
    )"
    refusal_exit=$?
    set -e
    if [[ "$refusal_exit" -ne 42 || "$refusal_output" != *"unsupported-active-cancellation-refused"* ]]; then
      echo "self-test=unsupported-active-cancellation-refused:fail:$self_test_route" >&2
      return 1
    fi
    if [[ -e "$launch_marker" ]]; then
      echo "self-test=adapter-not-launched:fail:$self_test_route" >&2
      return 1
    fi
  done
  echo "self-test=unsupported-active-cancellation-refused:pass"
  echo "self-test=adapter-launch:skipped"
}

if [[ "$self_test" == true ]]; then
  run_self_test
  exit 0
fi

[[ -n "$route" ]] || { echo "--route is required" >&2; exit 2; }
validate_case_plan || { echo "case plan is not final-only and route-specific" >&2; exit 2; }
require_route_capability "$route" "$capability"

for path in "$runtime_root" "$model_root" "$adapter" "$output" "$english_audio" \
  "$mandarin_audio" "$mixed_en_zh_audio" "$mixed_zh_en_audio" "$silence_audio"; do
  [[ "$path" == /* ]] || { echo "all paths must be absolute" >&2; exit 2; }
done
[[ "$repetitions" =~ ^[1-9][0-9]*$ ]] || { echo "repetitions must be positive" >&2; exit 2; }
[[ -x "$adapter" ]] || { echo "adapter is not executable" >&2; exit 2; }
for path in "$english_audio" "$mandarin_audio" "$mixed_en_zh_audio" "$mixed_zh_en_audio" "$silence_audio"; do
  [[ -f "$path" ]] || { echo "audio fixture is missing: $path" >&2; exit 2; }
done

readonly work_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-qwen-admission-run.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT
readonly input="$work_root/requests.jsonl"
readonly time_output="$work_root/time.txt"

emit_load() {
  jq -cn --arg id "$1" '{schemaVersion:1,requestID:$id,operation:"load",contextPhrases:[],protectedForms:[]}' >> "$input"
}

emit_unload() {
  jq -cn --arg id "$1" '{schemaVersion:1,requestID:$id,operation:"unload",contextPhrases:[],protectedForms:[]}' >> "$input"
}

emit_transcribe() {
  jq -cn \
    --arg id "$1" \
    --arg audio "$2" \
    --arg locale "$3" \
    --argjson context "$4" \
    '{schemaVersion:1,requestID:$id,operation:"transcribe",audioPath:$audio,sampleRate:16000,localeIdentifier:$locale,contextPhrases:$context,protectedForms:[]}' \
    >> "$input"
}

emit_shutdown() {
  jq -cn --arg id "$1" '{schemaVersion:1,requestID:$id,operation:"shutdown",contextPhrases:[],protectedForms:[]}' >> "$input"
}

: > "$input"
if [[ "$repetitions" -eq 1 ]]; then
  emit_load load-initial
  emit_transcribe case-english-technical "$english_audio" en-US '["Fleck","SwiftUI"]'
  emit_transcribe case-english-command "$english_audio" en-US '["Package.swift","/Users/harryjin"]'
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

adapter_args=(--runtime-root "$runtime_root" --model-root "$model_root")
if [[ -n "$backend" ]]; then
  adapter_args+=(--backend "$backend")
fi

set +e
/usr/bin/time -l env DYLD_FRAMEWORK_PATH="$runtime_root" "$adapter" "${adapter_args[@]}" \
  < "$input" > "$output" 2> "$time_output"
exit_code=$?
set -e

jq -s -e 'all(.[]; .schemaVersion == 1)' "$output" >/dev/null
if [[ "$repetitions" -eq 1 ]]; then
  jq -s -e '
    any(.[]; .event == "ready" and .requestID == "load-initial") and
    any(.[]; .event == "final" and .requestID == "case-english-technical") and
    any(.[]; .event == "final" and .requestID == "case-mandarin-prose") and
    any(.[]; .event == "final" and .requestID == "case-english-mandarin") and
    any(.[]; .event == "unloaded" and .requestID == "shutdown-final") and
    (all(.[]; .event != "partial"))
  ' "$output" >/dev/null
else
  jq -s -e --argjson expected "$repetitions" '
    ([.[] | select(.event == "ready")] | length) == ($expected) and
    ([.[] | select(.event == "final")] | length) == ($expected) and
    ([.[] | select(.event == "unloaded")] | length) == ($expected + 1) and
    (all(.[]; .event != "partial"))
  ' "$output" >/dev/null
fi

if [[ "$exit_code" -ne 0 ]]; then
  echo "adapter-exit=$exit_code" >&2
  exit "$exit_code"
fi

max_rss="$(awk '/maximum resident set size/ { print $1; exit }' "$time_output")"
echo "protocol-evidence=$output"
echo "route=$route"
echo "capability=$capability"
echo "repetitions=$repetitions"
echo "max-resident-bytes=${max_rss:-unreported}"
echo "shutdown-acknowledged=true"
