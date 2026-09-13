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

home_dir=$(CDPATH= cd -- "$home_dir" 2>/dev/null && pwd -P) || {
  printf '%s\n' 'error: HOME must resolve to an existing directory to protect Fleck Application Support' >&2
  exit 2
}

for required_command in awk date osascript perl ps sort uname; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$required_command" >&2
    exit 2
  fi
done

case "$requested_output_dir" in
  -*)
    printf '%s\n' 'error: output directory must not begin with -' >&2
    exit 2
    ;;
esac

# AX_MEASUREMENT_DIRECTORY_RECORD_BEGIN
measurement_output_directory_record() {
  /usr/bin/perl -MCwd=abs_path -e '
use strict;
use warnings;
use File::Spec;

my $requested = shift @ARGV;
my $protected = shift @ARGV;
if (!defined($requested) || $requested =~ /[\t\r\n]/) {
  print STDERR "error: output directory path contains tab, carriage return, or line feed\n";
  exit 2;
}
my $requested_lstat_path = $requested;
$requested_lstat_path =~ s{/+\z}{};
$requested_lstat_path = "/" if $requested_lstat_path eq "";
my @requested_stat = lstat($requested_lstat_path);
unless (@requested_stat && -d _ && !-l _) {
  print STDERR "error: output directory must be one existing non-symlink directory\n";
  exit 2;
}
my $canonical = abs_path($requested);
if (!defined($canonical) || $canonical =~ /[\t\r\n]/) {
  print STDERR "error: output directory path contains tab, carriage return, or line feed\n";
  exit 2;
}
my @canonical_stat = lstat($canonical);
unless (
  @canonical_stat &&
  -d _ &&
  !-l _ &&
  $canonical_stat[0] == $requested_stat[0] &&
  $canonical_stat[1] == $requested_stat[1]
) {
  print STDERR "error: output directory must resolve to one existing non-symlink directory\n";
  exit 2;
}
sub has_protected_ancestor {
  my ($path, $device, $inode) = @_;
  my $candidate = File::Spec->rootdir;
  for my $part (File::Spec->splitdir($path)) {
    next unless length($part);
    $candidate = File::Spec->catdir($candidate, $part);
    my @current = stat($candidate);
    return 1 if @current && $current[0] == $device && $current[1] == $inode;
  }
  return 0;
}
if (defined($protected) && length($protected)) {
  my @protected_stat = stat($protected);
  if (@protected_stat && -d _ && has_protected_ancestor($canonical, $protected_stat[0], $protected_stat[1])) {
    print STDERR "error: output directory cannot be Fleck Application Support or a child of it\n";
    exit 2;
  }
}
print $canonical, "\t", $canonical_stat[0], "\t", $canonical_stat[1], "\n" or exit 2;
' "$1" "${2-}"
}
bind_measurement_output_directory() {
  exec 9<"$1"
}
# AX_MEASUREMENT_DIRECTORY_RECORD_END

protected_output_dir="$home_dir/Library/Application Support/Fleck"
output_directory_record=$(measurement_output_directory_record \
  "$requested_output_dir" "$protected_output_dir") || exit 2
output_dir=$(printf '%s\n' "$output_directory_record" | awk -F '\t' 'NF == 3 { print $1 }')
if [ -z "$output_dir" ]; then
  printf '%s\n' 'error: could not resolve output directory identity' >&2
  exit 2
fi

bind_measurement_output_directory "$output_dir" || {
  printf '%s\n' 'error: could not bind the approved output directory' >&2
  exit 2
}

raw_basename=ax-press-to-accessible-window-raw.tsv
summary_basename=ax-press-to-accessible-window-summary.txt
metadata_basename=ax-press-to-accessible-window-metadata.txt

# AX_MEASUREMENT_OUTPUT_HELPERS_BEGIN
cleanup_output_temp() {
  cleanup_directory_record=$1
  cleanup_temp_record=$2
  if [ -n "$cleanup_temp_record" ]; then
    measurement_output_helper cleanup "$cleanup_directory_record" "$cleanup_temp_record" || :
  fi
}

measurement_output_helper() {
  /usr/bin/perl -MFile::Temp -e '
# AX_MEASUREMENT_PERL_BEGIN
use strict;
use warnings;
use Cwd qw(getcwd);

sub directory_record_parts {
  my ($record) = @_;
  return unless defined($record);
  my @parts = split(/\t/, $record, -1);
  return unless @parts == 3;
  return unless length($parts[0]) && $parts[0] !~ /[\t\r\n]/;
  return unless $parts[1] =~ /^\d+$/ && $parts[2] =~ /^\d+$/;
  return @parts;
}

sub enter_directory {
  my ($record) = @_;
  my ($path, $device, $inode) = directory_record_parts($record);
  return unless defined($path);
  open(my $directory, "<&=9") or return;
  my @bound = stat($directory);
  return unless @bound && -d _;
  return unless $bound[0] == $device && $bound[1] == $inode;
  return unless syscall(13, 9) == 0;
  my @current = stat(".");
  return unless @current && -d _;
  return unless $current[0] == $device && $current[1] == $inode;
  close($directory);
  return ($path, $device, $inode);
}

sub safe_basename {
  my ($basename) = @_;
  return defined($basename)
    && $basename =~ /^[A-Za-z0-9._-]+$/
    && $basename ne "."
    && $basename ne "..";
}

sub cleanup_created_path {
  my ($basename, $created) = @_;
  return unless @$created >= 2;
  return unless safe_basename($basename);
  my @current = lstat($basename);
  return unless @current && -f _ && !-l _;
  return unless $current[0] == $created->[0] && $current[1] == $created->[1];
  unlink($basename);
}

sub file_record_parts {
  my ($record) = @_;
  return unless defined($record);
  my @parts = split(/\t/, $record, -1);
  return unless @parts == 3;
  return unless safe_basename($parts[0]);
  return unless $parts[1] =~ /^\d+$/ && $parts[2] =~ /^\d+$/;
  return @parts;
}

sub matches_created_file {
  my ($basename, $device, $inode) = @_;
  return 0 unless safe_basename($basename);
  my @current = lstat($basename);
  return 0 unless @current && -f _ && !-l _;
  return $current[0] == $device && $current[1] == $inode;
}

my $operation = shift @ARGV;
if ($operation eq "create") {
  my $directory_record = shift @ARGV;
  exit 2 unless enter_directory($directory_record);
  my ($handle, $path);
  eval {
    ($handle, $path) = File::Temp::tempfile(
      ".fleck-panel-measurement.XXXXXX",
      DIR => ".",
      UNLINK => 0
    );
    1;
  } or exit 2;
  $path =~ s{^\./}{};
  exit 2 unless safe_basename($path);
  my @created = stat($handle);
  unless (@created && binmode(STDIN) && binmode($handle)) {
    close($handle);
    cleanup_created_path($path, \@created);
    exit 2;
  }
  my $hook = defined($ENV{"FLECK_MEASUREMENT_TEMP_HOOK"})
    ? $ENV{"FLECK_MEASUREMENT_TEMP_HOOK"} : "";
  if ($hook ne "") {
    my $status = system($hook, getcwd() . "/" . $path);
    unless ($status == 0) {
      close($handle);
      cleanup_created_path($path, \@created);
      exit 2;
    }
  }
  my $buffer;
  while (1) {
    my $read = read(STDIN, $buffer, 65536);
    unless (defined($read)) {
      close($handle);
      cleanup_created_path($path, \@created);
      exit 2;
    }
    last if $read == 0;
    unless (print {$handle} $buffer) {
      close($handle);
      cleanup_created_path($path, \@created);
      exit 2;
    }
  }
  unless (close($handle)) {
    cleanup_created_path($path, \@created);
    exit 2;
  }
  my @published = lstat($path);
  my $same_inode =
    @published &&
    $published[0] == $created[0] &&
    $published[1] == $created[1];
  unless (@published && -f _ && !-l _ && $same_inode) {
    cleanup_created_path($path, \@created);
    exit 2;
  }
  print $path, "\t", $created[0], "\t", $created[1], "\n" or exit 2;
  exit 0;
}
if ($operation eq "cleanup") {
  my $directory_record = shift @ARGV;
  exit 2 unless enter_directory($directory_record);
  my ($source, $device, $inode) = file_record_parts(shift @ARGV);
  exit 2 unless defined($source) && matches_created_file($source, $device, $inode);
  exit(unlink($source) ? 0 : 2);
}
if ($operation eq "publish") {
  my $directory_record = shift @ARGV;
  exit 2 unless enter_directory($directory_record);
  my ($source, $device, $inode) = file_record_parts(shift @ARGV);
  my $destination = shift @ARGV;
  exit 2 unless defined($source) && safe_basename($destination);
  exit 2 unless matches_created_file($source, $device, $inode);
  exit 2 if -d($destination) && !-l($destination);
  my $hook = defined($ENV{"FLECK_MEASUREMENT_PUBLISH_HOOK"})
    ? $ENV{"FLECK_MEASUREMENT_PUBLISH_HOOK"} : "";
  if ($hook ne "") {
    my $status = system($hook, getcwd() . "/" . $destination);
    exit 2 unless $status == 0;
  }
  exit 2 unless matches_created_file($source, $device, $inode);
  exit 2 unless link($source, $destination);
  unless (matches_created_file($destination, $device, $inode)) {
    exit 2;
  }
  unless (matches_created_file($source, $device, $inode)) {
    unlink($destination) if matches_created_file($destination, $device, $inode);
    exit 2;
  }
  unless (unlink($source)) {
    unlink($destination) if matches_created_file($destination, $device, $inode);
    exit 2;
  }
  exit 2 unless matches_created_file($destination, $device, $inode);
  print $destination, "\t", $device, "\t", $inode, "\n" or exit 2;
  exit 0;
}
if ($operation eq "rollback") {
  my $directory_record = shift @ARGV;
  exit 2 unless enter_directory($directory_record);
  my ($destination, $device, $inode) = file_record_parts(shift @ARGV);
  exit 2 unless defined($destination) && matches_created_file($destination, $device, $inode);
  exit(unlink($destination) ? 0 : 2);
}
if ($operation eq "absent") {
  my $directory_record = shift @ARGV;
  exit 2 unless enter_directory($directory_record);
  my $destination = shift @ARGV;
  exit 2 unless safe_basename($destination);
  my @existing = lstat($destination);
  exit 2 if @existing;
  exit 0;
}
exit 2;
# AX_MEASUREMENT_PERL_END
' "$@"
}

publish_output_file() {
  publish_directory_record=$1
  publish_temp_record=$2
  publish_destination=$3
  published_record=
  published_record=$(measurement_output_helper publish \
    "$publish_directory_record" "$publish_temp_record" "$publish_destination")
}

rollback_output_file() {
  rollback_directory_record=$1
  rollback_published_record=$2
  if [ -n "$rollback_published_record" ]; then
    if ! measurement_output_helper rollback \
      "$rollback_directory_record" "$rollback_published_record"; then
      rollback_failed=1
    fi
  fi
}
# AX_MEASUREMENT_OUTPUT_HELPERS_END

for output_basename in "$raw_basename" "$summary_basename" "$metadata_basename"; do
  if ! measurement_output_helper absent "$output_directory_record" "$output_basename"; then
    printf 'error: output destination must be absent in the approved directory: %s\n' \
      "$output_basename" >&2
    exit 2
  fi
done

profile_pid=${FLECK_PERFORMANCE_PID:-}
if [ -z "$profile_pid" ]; then
  printf '%s\n' \
    'error: FLECK_PERFORMANCE_PID is required for an already-running Fleck process' >&2
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

is_packaged_fleck_path_shape() {
  executable_path=$1
  case "$executable_path" in
    */Fleck.app/Contents/MacOS/Fleck) return 0 ;;
    */Contents/MacOS/Fleck) ;;
    *) return 1 ;;
  esac
  bundle_path=${executable_path%/Contents/MacOS/Fleck}
  bundle_name=${bundle_path##*/}
  printf '%s\n' "$bundle_name" | /usr/bin/grep -Eq \
    '^Fleck [0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)? Build [1-9][0-9]*\.app$'
}

process_name=$(ps -p "$profile_pid" -o comm= | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')
if ! is_packaged_fleck_path_shape "$process_name"; then
  printf 'error: PID %s is not a packaged Fleck executable path shape (found: %s)\n' \
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

raw_temp=
summary_temp=
metadata_temp=
published_raw=
published_summary=
published_metadata=
measurement_succeeded=0
rollback_failed=0

rollback_published_outputs() {
  rollback_output_file "$output_directory_record" "$published_metadata"
  rollback_output_file "$output_directory_record" "$published_summary"
  rollback_output_file "$output_directory_record" "$published_raw"
}

cleanup_temporary_files() {
  exit_status=$?
  trap - EXIT
  if [ "$measurement_succeeded" -eq 0 ]; then
    rollback_published_outputs
    if [ "$rollback_failed" -ne 0 ]; then
      exit_status=2
    fi
  fi
  cleanup_output_temp "$output_directory_record" "$raw_temp"
  cleanup_output_temp "$output_directory_record" "$summary_temp"
  cleanup_output_temp "$output_directory_record" "$metadata_temp"
  exit "$exit_status"
}

trap cleanup_temporary_files EXIT

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

function accessiblePanelWindows(process) {
  var windows = process.windows();
  var matches = [];
  for (var index = 0; index < windows.length; index += 1) {
    var window = windows[index];
    if (isTransientPanelWindow(window)) {
      matches.push(window);
    }
  }
  return matches;
}

function waitForPanelState(process, expectedPresent, clock, sleep, timeoutMs) {
  var deadline = clock() + timeoutMs;
  while (clock() <= deadline) {
    var panels = accessiblePanelWindows(process);
    if (panels.length > 1) {
      throw new Error("ambiguous accessible panel window");
    }
    if ((panels.length === 1) === expectedPresent) {
      return panels.length === 1 ? panels[0] : null;
    }
    sleep(50);
  }
  throw new Error(
    expectedPresent
      ? "accessible panel window timeout"
      : "panel did not normalize closed before timeout"
  );
}

function closePanelBestEffort(process, menuExtra, clock, sleep, timeoutMs) {
  try {
    var panels = accessiblePanelWindows(process);
    if (panels.length > 1) {
      return false;
    }
    if (panels.length === 1) {
      pressMenuExtra(menuExtra);
      waitForPanelState(process, false, clock, sleep, timeoutMs);
    }
    return true;
  } catch (_) {
    return false;
  }
}

function normalizeClosed(process, menuExtra, clock, sleep, timeoutMs) {
  var panels = accessiblePanelWindows(process);
  if (panels.length > 1) {
    throw new Error("ambiguous accessible panel window");
  }
  if (panels.length === 1) {
    pressMenuExtra(menuExtra);
    waitForPanelState(process, false, clock, sleep, timeoutMs);
  }
}

function measureSample(process, menuExtra, sampleLabel, clock, sleep, timeoutMs) {
  try {
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
  } catch (error) {
    closePanelBestEffort(process, menuExtra, clock, sleep, timeoutMs);
    throw error;
  }
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

// AX_MEASUREMENT_JXA_RUN_BEGIN
function runMeasurement(argv, systemEvents) {
  var targetPid = Number(argv[0]);
  var count = Number(argv[1]);
  if (!isFinite(targetPid) || targetPid < 1 || targetPid !== Math.floor(targetPid)) {
    throw new Error("invalid Fleck PID");
  }
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
  return lines.join("\n");
}

function run(argv) {
  return runMeasurement(argv, Application("System Events"));
}
// AX_MEASUREMENT_JXA_RUN_END
JXA
) || {
  printf '%s\n' \
    'error: AX-press-to-accessible-window JXA failed; verify one exact AXMenuExtra, a closed panel, and one accessible transient window' >&2
  exit 2
}

if ! printf '%s\n' "$measurement_output" | awk -F '\t' -v expected="$total_samples" '
  BEGIN { valid = 1 }
  NR == 1 {
    if ($0 != "sample_label\tsample_number\telapsed_ms") valid = 0
    next
  }
  {
    expected_label = NR == 2 ? "cold" : "warm"
    if (NF != 3 || $1 != expected_label || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+([.][0-9]+)?$/ || $2 != NR - 1) valid = 0
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

raw_temp=$(
  printf '%s\n' "$measurement_output" |
    measurement_output_helper create "$output_directory_record"
) || {
  printf '%s\n' 'error: could not create a raw-sample temporary file' >&2
  exit 2
}

# AX_MEASUREMENT_STATS_BEGIN
calculate_measurement_statistics() {
  printf '%s\n' "$1" | awk -F '\t' 'NR > 1 { print $3 }' | sort -n | awk -v expected="$total_samples" '
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
'
}
# AX_MEASUREMENT_STATS_END

stats=$(calculate_measurement_statistics "$measurement_output") || {
  printf '%s\n' 'error: could not calculate statistics for the complete sample set' >&2
  exit 2
}

set -- $stats
if [ "$#" -ne 5 ] || [ "$1" -ne "$total_samples" ]; then
  printf '%s\n' 'error: expected 31 completed samples for summary statistics' >&2
  exit 2
fi

summary_temp=$(
  {
    printf '%s\n' 'Fleck AX-press-to-accessible-window measurement summary'
    printf 'sample_count=%s\n' "$1"
    printf 'cold_sample_count=1\n'
    printf 'warm_sample_count=%s\n' "$warm_sample_count"
    printf 'p50_ms=%s\n' "$2"
    printf 'p95_ms=%s\n' "$3"
    printf 'min_ms=%s\n' "$4"
    printf 'max_ms=%s\n' "$5"
    printf '%s\n' 'measurement_boundary=AX-press-to-accessible-window'
    printf '%s\n' 'automation_boundary=not pixel-complete and not human click latency'
  } | measurement_output_helper create "$output_directory_record"
) || {
  printf '%s\n' 'error: could not create a summary temporary file' >&2
  exit 2
}

metadata_temp=$(
  {
    printf 'captured_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\n' 'measurement_name=AX-press-to-accessible-window'
    printf 'sample_count=%s\n' "$1"
    printf 'cold_sample_count=1\n'
    printf 'warm_sample_count=%s\n' "$warm_sample_count"
    printf '%s\n' \
      'status_item_contract=exact Fleck title or name; role AXMenuBarItem; subrole AXMenuExtra; searched across all Fleck menu bars'
    printf '%s\n' \
      'panel_window_contract=one Fleck process window; role AXWindow; subrole AXSystemDialog or AXDialog; sane size; exposed by window-list membership'
    printf '%s\n' \
      'normalization=before every sample, toggle exact AXPress only when a matching panel window is exposed and verify no matching panel window'
    printf '%s\n' \
      'timing=one JXA process using Date.now from AXPress invocation to first matching accessible-exposed panel window'
    printf '%s\n' \
      'boundary=AX-press-to-accessible-window; window-list exposure is the observed criterion; not pixel-complete and not human click latency'
    printf '%s\n' \
      'data_boundary=no editor descendants or user data; no Fleck Application Support access'
    printf '%s\n' \
      'process_boundary=already-running Fleck only; AXPress toggles panel presentation state; no launch, termination, rebuild, signal, or process-lifecycle control'
    printf '%s\n' \
      'mutation_boundary=no note/editor/Application Support mutation; presentation-state AXPress is intentional'
  } | measurement_output_helper create "$output_directory_record"
) || {
  printf '%s\n' 'error: could not create metadata temporary file' >&2
  exit 2
}

if ! publish_output_file "$output_directory_record" "$raw_temp" "$raw_basename"; then
  exit 2
fi
published_raw=$published_record
raw_temp=
if ! publish_output_file "$output_directory_record" "$summary_temp" "$summary_basename"; then
  exit 2
fi
published_summary=$published_record
summary_temp=
if ! publish_output_file "$output_directory_record" "$metadata_temp" "$metadata_basename"; then
  exit 2
fi
published_metadata=$published_record
metadata_temp=
measurement_succeeded=1

printf 'Wrote 1 cold and %s warm AX-press-to-accessible-window samples to %s\n' \
  "$warm_sample_count" "$output_dir"
