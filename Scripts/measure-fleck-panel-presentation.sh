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
    'error: output directory must be one existing non-symlink directory' >&2
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

raw_samples="$output_dir/ax-press-to-accessible-visible-raw.tsv"
summary="$output_dir/ax-press-to-accessible-visible-summary.txt"
metadata="$output_dir/ax-press-to-accessible-visible-metadata.txt"
for output_file in "$raw_samples" "$summary" "$metadata"; do
  if [ -L "$output_file" ]; then
    printf 'error: refusing symlinked output: %s\n' "$output_file" >&2
    exit 2
  fi
done

for required_command in awk date osascript ps sort uname; do
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

readonly total_samples=31
readonly warm_sample_count=30

measurement_output=$(
  /usr/bin/osascript -l JavaScript - "$profile_pid" "$total_samples" <<'JXA'
// AX_MEASUREMENT_JXA_BEGIN
function attribute(object, name) {
  try {
    return object[name]();
  } catch (_) {
    return null;
  }
}

function stringAttribute(object, name) {
  var value = attribute(object, name);
  return value === null || value === undefined ? "" : String(value);
}

function numberAttribute(object, name) {
  var value = attribute(object, name);
  return value === null || value === undefined ? NaN : Number(value);
}

function isVisible(object) {
  var value = attribute(object, "visible");
  return value === true || value === 1 || value === "true" || value === "1";
}

function findExactFleckProcess(systemEvents, targetPid) {
  var matches = [];
  var processes = systemEvents.applicationProcesses();
  for (var index = 0; index < processes.length; index += 1) {
    var process = processes[index];
    if (
      numberAttribute(process, "unixId") === targetPid &&
      stringAttribute(process, "name") === "Fleck"
    ) {
      matches.push(process);
    }
  }
  if (matches.length !== 1) {
    throw new Error("expected exactly one Fleck process for PID");
  }
  return matches[0];
}

function findUniqueMenuExtra(process) {
  var matches = [];
  var menuBars = process.menuBars();
  for (var barIndex = 0; barIndex < menuBars.length; barIndex += 1) {
    var menuBarItems = menuBars[barIndex].menuBarItems();
    for (var itemIndex = 0; itemIndex < menuBarItems.length; itemIndex += 1) {
      var item = menuBarItems[itemIndex];
      var title = stringAttribute(item, "title");
      var name = stringAttribute(item, "name");
      if (
        (title === "Fleck" || name === "Fleck") &&
        stringAttribute(item, "role") === "AXMenuBarItem" &&
        stringAttribute(item, "subrole") === "AXMenuExtra"
      ) {
        matches.push(item);
      }
    }
  }
  if (matches.length !== 1) {
    throw new Error("expected exactly one Fleck AXMenuExtra");
  }
  return matches[0];
}

function pressMenuExtra(menuExtra) {
  var action = menuExtra.actions.byName("AXPress");
  if (!action) {
    throw new Error("Fleck AXMenuExtra has no AXPress action");
  }
  action.perform();
}

function isTransientPanelWindow(window) {
  if (stringAttribute(window, "role") !== "AXWindow") {
    return false;
  }
  var subrole = stringAttribute(window, "subrole");
  if (subrole !== "AXSystemDialog" && subrole !== "AXDialog") {
    return false;
  }
  var size = attribute(window, "size");
  if (!size || size.length < 2) {
    return false;
  }
  var width = Number(size[0]);
  var height = Number(size[1]);
  return (
    isFinite(width) &&
    isFinite(height) &&
    width >= 200 &&
    height >= 100 &&
    width <= 2000 &&
    height <= 1400
  );
}

function visiblePanelWindows(process) {
  var windows = process.windows();
  var matches = [];
  for (var index = 0; index < windows.length; index += 1) {
    var window = windows[index];
    if (isTransientPanelWindow(window) && isVisible(window)) {
      matches.push(window);
    }
  }
  return matches;
}

function waitForPanelState(process, expectedVisible, clock, sleep, timeoutMs) {
  var deadline = clock() + timeoutMs;
  while (clock() <= deadline) {
    var panels = visiblePanelWindows(process);
    if (panels.length > 1) {
      throw new Error("ambiguous accessible-visible panel window");
    }
    if ((panels.length === 1) === expectedVisible) {
      return panels.length === 1 ? panels[0] : null;
    }
    sleep(50);
  }
  throw new Error(
    expectedVisible
      ? "accessible-visible panel timeout"
      : "panel did not normalize closed before timeout"
  );
}

function normalizeClosed(process, menuExtra, clock, sleep, timeoutMs) {
  var panels = visiblePanelWindows(process);
  if (panels.length > 1) {
    throw new Error("ambiguous accessible-visible panel window");
  }
  if (panels.length === 1) {
    pressMenuExtra(menuExtra);
    waitForPanelState(process, false, clock, sleep, timeoutMs);
  }
}

function measureSample(process, menuExtra, sampleLabel, clock, sleep, timeoutMs) {
  normalizeClosed(process, menuExtra, clock, sleep, timeoutMs);
  var startedAt = clock();
  pressMenuExtra(menuExtra);
  waitForPanelState(process, true, clock, sleep, timeoutMs);
  var elapsedMilliseconds = clock() - startedAt;
  if (elapsedMilliseconds < 0) {
    throw new Error("Date.now moved backwards during sample");
  }
  pressMenuExtra(menuExtra);
  waitForPanelState(process, false, clock, sleep, timeoutMs);
  return {
    sampleLabel: sampleLabel,
    elapsedMilliseconds: elapsedMilliseconds
  };
}

function collectSamples(process, menuExtra, count, clock, sleep, timeoutMs) {
  if (!isFinite(count) || count < 1 || count !== Math.floor(count)) {
    throw new Error("invalid sample count");
  }
  var samples = [];
  for (var index = 0; index < count; index += 1) {
    samples.push(
      measureSample(
        process,
        menuExtra,
        index === 0 ? "cold" : "warm",
        clock,
        sleep,
        timeoutMs
      )
    );
  }
  return samples;
}
// AX_MEASUREMENT_JXA_END

function run(argv) {
  var targetPid = Number(argv[0]);
  var count = Number(argv[1]);
  if (!isFinite(targetPid) || targetPid < 1 || targetPid !== Math.floor(targetPid)) {
    throw new Error("invalid Fleck PID");
  }
  var systemEvents = Application("System Events");
  var process = findExactFleckProcess(systemEvents, targetPid);
  var menuExtra = findUniqueMenuExtra(process);
  var samples = collectSamples(
    process,
    menuExtra,
    count,
    Date.now,
    function(milliseconds) { delay(milliseconds / 1000); },
    5000
  );
  var lines = ["sample_label\tsample_number\telapsed_ms"];
  for (var index = 0; index < samples.length; index += 1) {
    lines.push(
      samples[index].sampleLabel +
        "\t" +
        (index + 1) +
        "\t" +
        samples[index].elapsedMilliseconds
    );
  }
  console.log(lines.join("\n"));
}
JXA
) || {
  printf '%s\n' \
    'error: AX-press-to-accessible-visible JXA failed; verify one exact AXMenuExtra, a closed panel, and one accessible transient window' >&2
  exit 2
}

if ! printf '%s\n' "$measurement_output" | awk -F '\t' -v expected="$total_samples" '
  BEGIN { valid = 1 }
  NR == 1 {
    if ($0 != "sample_label\tsample_number\telapsed_ms") valid = 0
    next
  }
  {
    if (
      NF != 3 ||
      ($1 != "cold" && $1 != "warm") ||
      $2 !~ /^[0-9]+$/ ||
      $3 !~ /^[0-9]+$/ ||
      $2 != NR - 1
    ) valid = 0
    if ($1 == "cold") cold += 1
    if ($1 == "warm") warm += 1
  }
  END {
    if (NR != expected + 1 || cold != 1 || warm != expected - 1) valid = 0
    exit(valid ? 0 : 1)
  }
'; then
  printf '%s\n' 'error: JXA returned an invalid or incomplete 31-sample record set' >&2
  exit 2
fi

printf '%s\n' "$measurement_output" > "$raw_samples"

stats=$(awk -F '\t' 'NR > 1 { print $3 }' "$raw_samples" | sort -n | awk -v expected="$total_samples" '
  {
    values[NR] = $1
    minimum = NR == 1 || $1 < minimum ? $1 : minimum
    maximum = NR == 1 || $1 > maximum ? $1 : maximum
  }
  END {
    if (NR != expected) exit 1
    p50 = values[int((expected + 1) / 2)]
    p95 = values[int((95 * expected + 99) / 100)]
    printf "%s\t%s\t%s\t%s\t%s\n", NR, p50, p95, minimum, maximum
  }
') || {
  printf '%s\n' 'error: could not calculate statistics for the complete sample set' >&2
  exit 2
}

set -- $stats
if [ "$#" -ne 5 ] || [ "$1" -ne "$total_samples" ]; then
  printf '%s\n' 'error: expected 31 completed samples for summary statistics' >&2
  exit 2
fi

{
  printf '%s\n' 'Fleck AX-press-to-accessible-visible measurement summary'
  printf 'sample_count=%s\n' "$1"
  printf 'cold_sample_count=1\n'
  printf 'warm_sample_count=%s\n' "$warm_sample_count"
  printf 'p50_ms=%s\n' "$2"
  printf 'p95_ms=%s\n' "$3"
  printf 'min_ms=%s\n' "$4"
  printf 'max_ms=%s\n' "$5"
  printf '%s\n' 'measurement_boundary=AX-press-to-accessible-visible'
  printf '%s\n' 'automation_boundary=not pixel-complete and not human click latency'
} > "$summary"

{
  printf 'captured_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s\n' 'measurement_name=AX-press-to-accessible-visible'
  printf 'sample_count=%s\n' "$1"
  printf 'cold_sample_count=1\n'
  printf 'warm_sample_count=%s\n' "$warm_sample_count"
  printf '%s\n' \
    'status_item_contract=exact Fleck title or name; role AXMenuBarItem; subrole AXMenuExtra; searched across all Fleck menu bars'
  printf '%s\n' \
    'panel_window_contract=Fleck process window; role AXWindow; subrole AXSystemDialog or AXDialog; visible=true; sane size'
  printf '%s\n' \
    'normalization=before every sample, toggle exact AXPress only when a matching panel is visible and verify no matching panel'
  printf '%s\n' \
    'timing=one JXA process using Date.now from AXPress invocation to first matching accessible-visible panel'
  printf '%s\n' \
    'boundary=AX-press-to-accessible-visible; not pixel-complete and not human click latency'
  printf '%s\n' \
    'data_boundary=no editor descendants or user data; no Fleck Application Support access'
  printf '%s\n' \
    'process_boundary=already-running exact packaged Fleck only; no launch, termination, rebuild, signal, or process mutation'
} > "$metadata"

printf 'Wrote 1 cold and %s warm AX-press-to-accessible-visible samples to %s\n' \
  "$warm_sample_count" "$output_dir"
