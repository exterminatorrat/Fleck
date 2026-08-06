#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' 'error: Fleck panel measurement requires macOS' >&2
  exit 2
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
  printf '%s\n' \
    'Set FLECK_PERFORMANCE_PID to an already-running packaged Fleck PID.' \
    'The output directory must already exist and must not be a symlink.' >&2
  exit 2
fi

requested_output_dir=$1
home_dir=${HOME:-}

if [ -z "$home_dir" ]; then
  printf '%s\n' 'error: HOME must be set to protect Fleck Application Support' >&2
  exit 2
fi

case "$requested_output_dir" in
  -*)
    printf '%s\n' 'error: output directory must not begin with -' >&2
    exit 2
    ;;
esac

case "$requested_output_dir" in
  "$home_dir/Library/Application Support/Fleck"|\
  "$home_dir/Library/Application Support/Fleck"/*)
    printf '%s\n' \
      'error: output directory cannot be Fleck Application Support or a child of it' >&2
    exit 2
    ;;
esac

if [ ! -d "$requested_output_dir" ] || [ -L "$requested_output_dir" ]; then
  printf '%s\n' \
    'error: output directory must already exist and must not be a symlink' >&2
  exit 2
fi

output_dir=$(CDPATH= cd -- "$requested_output_dir" && pwd -P) || exit 2
case "$output_dir" in
  "$home_dir/Library/Application Support/Fleck"|\
  "$home_dir/Library/Application Support/Fleck"/*)
    printf '%s\n' \
      'error: resolved output directory cannot be Fleck Application Support or a child of it' >&2
    exit 2
    ;;
esac

raw_samples="$output_dir/panel-presentation-raw.tsv"
samples="$output_dir/panel-presentation-samples.tsv"
summary="$output_dir/panel-presentation-summary.txt"
metadata="$output_dir/panel-presentation-metadata.txt"
for output_file in "$raw_samples" "$samples" "$summary" "$metadata"; do
  if [ -L "$output_file" ]; then
    printf 'error: refusing symlinked output: %s\n' "$output_file" >&2
    exit 2
  fi
done

for required_command in awk date log osascript ps sleep sort sw_vers uname wc; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$required_command" >&2
    exit 2
  fi
done

profile_pid=${FLECK_PERFORMANCE_PID:-}
if [ -z "$profile_pid" ]; then
  printf '%s\n' \
    'error: FLECK_PERFORMANCE_PID is required for an already-running exact packaged Fleck app' >&2
  exit 2
fi
case "$profile_pid" in
  *[!0-9]*)
    printf '%s\n' 'error: FLECK_PERFORMANCE_PID must be a decimal process ID' >&2
    exit 2
    ;;
esac
if [ "$profile_pid" -eq 0 ]; then
  printf '%s\n' 'error: FLECK_PERFORMANCE_PID must identify Fleck' >&2
  exit 2
fi

is_exact_fleck_command() {
  case "$1" in
    */Fleck.app/Contents/MacOS/Fleck) return 0 ;;
    *) return 1 ;;
  esac
}

process_name=$(ps -p "$profile_pid" -o comm= | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')
if ! is_exact_fleck_command "$process_name"; then
  printf 'error: PID %s is not the exact Fleck command (found: %s)\n' \
    "$profile_pid" "${process_name:-missing}" >&2
  exit 2
fi

if ! /usr/bin/osascript -e \
  'tell application "System Events" to get name of first application process' \
  >/dev/null 2>&1; then
  printf '%s\n' \
    'error: System Events Accessibility is not authorized for the calling terminal or agent; enable it in System Settings > Privacy & Security > Accessibility, then rerun.' >&2
  exit 2
fi

metadata_predicate="processID == $profile_pid AND subsystem == \"com.harryjin.fleck\" AND category == \"performance\""
readonly total_samples=31
readonly warm_sample_count=30

: > "$raw_samples"
: > "$samples"
: > "$summary"
: > "$metadata"

printf 'sample_label\tsample_number\telapsed_ms\troot_state\n' > "$raw_samples"
printf 'sample_label\tsample_number\telapsed_ms\troot_state\n' > "$samples"

show_performance_logs() {
  "$1" show \
    --last 5m \
    --style compact \
    --info \
    --predicate "$metadata_predicate" 2>/dev/null
}

log_records() {
  show_performance_logs /usr/bin/log |
    awk '
      /panel_presentation elapsed_ms=/ {
        record = $0
        sub(/^.*panel_presentation elapsed_ms=/, "", record)
        split(record, fields, /[[:space:]]+/)
        elapsed = fields[1]
        root = fields[2]
        sub(/^root_state=/, "", root)
        if (elapsed ~ /^[0-9]+([.][0-9]+)?$/ && root ~ /^(loading|notes|blocked|resume)$/) {
          print elapsed "\t" root
        }
      }
    '
}

baseline_count=$(log_records | awk 'END { print NR + 0 }')

capture_records() {
  {
    printf 'sample_label\tsample_number\telapsed_ms\troot_state\n'
    log_records |
      awk -v baseline="$baseline_count" -v maximum="$total_samples" '
        NR > baseline && NR <= baseline + maximum {
          print "unlabeled\t" NR - baseline "\t" $1 "\t" $2
        }
      '
  } > "$raw_samples"
  sample_count=$(awk 'END { print NR - 1 }' "$raw_samples")
}

wait_for_sample() {
  expected_sample=$1
  deadline=$(( $(date '+%s') + 8 ))
  while :; do
    capture_records
    if [ "$sample_count" -ge "$expected_sample" ]; then
      return 0
    fi
    if [ "$(date '+%s')" -ge "$deadline" ]; then
      printf 'error: sample %s has no Fleck panel completion record\n' "$expected_sample" >&2
      return 1
    fi
    sleep 0.2
  done
}

click_status_item() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  set processNames to {"SystemUIServer", "ControlCenter", "Fleck"}
  repeat with processName in processNames
    try
      tell application process (processName as text)
        repeat with itemRef in (menu bar items of menu bar 1)
          set itemTitle to ""
          set itemDescription to ""
          try
            set itemTitle to title of itemRef as text
          end try
          try
            set itemDescription to description of itemRef as text
          end try
          if itemTitle is "Fleck" or itemDescription is "Fleck" then
            click itemRef
            return "clicked"
          end if
        end repeat
      end tell
    end try
  end repeat
end tell
error "Fleck status item with accessible Fleck label or description was not found"
APPLESCRIPT
}

close_panel() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  tell application process "Fleck"
    key code 53
  end tell
end tell
APPLESCRIPT
}

printf '%s\n' \
  'captured_at_utc='"$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  'fleck_pid='"$profile_pid" \
  'fleck_command='"$process_name" \
  'subsystem=com.harryjin.fleck' \
  'category=performance' \
  'log_predicate='"$metadata_predicate" \
  'cold_sample_count=1' \
  'warm_sample_count=30' \
  'status_item_lookup=System Events accessible Fleck label or description' \
  'close_action=System Events Escape key code 53' \
  'automation_click_wall_clock=not included as product latency' \
  'data_boundary=no Fleck Application Support or note data read or written' \
  'output_directory='"$output_dir" > "$metadata"

if ! close_panel >/dev/null 2>&1; then
  printf '%s\n' \
    'error: could not send the non-destructive Escape action; verify System Events Accessibility' >&2
  exit 2
fi

record_sample() {
  sample_label=$1
  sample_number=$2
  elapsed=$(awk -F '\t' -v sample="$sample_number" 'NR == sample + 1 { print $3; exit }' "$raw_samples")
  root_state=$(awk -F '\t' -v sample="$sample_number" 'NR == sample + 1 { print $4; exit }' "$raw_samples")
  if [ -z "$elapsed" ] || [ -z "$root_state" ]; then
    printf 'error: sample %s has no parsed app-side completion record\n' "$sample_number" >&2
    exit 2
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$sample_label" "$sample_number" "$elapsed" "$root_state" >> "$samples"
  {
    printf 'sample_label\tsample_number\telapsed_ms\troot_state\n'
    awk -F '\t' 'NR > 1 { print }' "$samples"
  } > "$raw_samples"
}

if ! click_status_item >/dev/null 2>&1; then
  printf '%s\n' \
    'error: could not identify the Fleck status item by accessible label or description' >&2
  exit 2
fi
wait_for_sample 1
record_sample cold 1
if ! close_panel >/dev/null 2>&1; then
  printf '%s\n' 'error: could not close the cold panel with Escape' >&2
  exit 2
fi

warm_sample=1
while [ "$warm_sample" -le "$warm_sample_count" ]; do
  sample_number=$((warm_sample + 1))
  if ! click_status_item >/dev/null 2>&1; then
    printf 'error: could not identify Fleck status item for warm sample %s\n' "$warm_sample" >&2
    exit 2
  fi
  wait_for_sample "$sample_number"
  record_sample warm "$sample_number"
  if ! close_panel >/dev/null 2>&1; then
    printf 'error: could not close warm panel %s with Escape\n' "$warm_sample" >&2
    exit 2
  fi
  warm_sample=$((warm_sample + 1))
done

stats=$(awk -F '\t' 'NR > 1 { print $3 }' "$samples" | sort -n | awk '
  { values[NR] = $1; minimum = NR == 1 || $1 < minimum ? $1 : minimum; maximum = NR == 1 || $1 > maximum ? $1 : maximum }
  END {
    count = NR
    p50 = values[int((count + 1) / 2)]
    p95 = values[int((95 * count + 99) / 100)]
    print count "\t" p50 "\t" p95 "\t" minimum "\t" maximum
  }
')
set -- $stats
if [ "$1" -ne "$total_samples" ]; then
  printf 'error: expected %s app-side completion records, found %s\n' "$total_samples" "$1" >&2
  exit 2
fi

{
  printf '%s\n' 'Fleck panel presentation measurement summary'
  printf 'sample_count=%s\n' "$1"
  printf 'cold_sample_count=1\n'
  printf 'warm_sample_count=30\n'
  printf 'p50_ms=%s\n' "$2"
  printf 'p95_ms=%s\n' "$3"
  printf 'min_ms=%s\n' "$4"
  printf 'max_ms=%s\n' "$5"
  printf '%s\n' 'measurement_boundary=app-side panel_presentation completion Logger records only'
  printf '%s\n' 'automation_boundary=System Events click wall-clock time is not product latency'
} > "$summary"

printf 'Wrote Fleck panel presentation samples and summary to %s\n' "$output_dir"
