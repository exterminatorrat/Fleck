#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' 'error: Fleck performance profiling requires macOS' >&2
  exit 2
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
  printf '%s\n' \
    'Set FLECK_PERFORMANCE_PID to a running Fleck PID for five safe process samples.' \
    'OUTPUT_DIRECTORY must already exist; the script never launches or terminates Fleck.' >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P) || exit 2
readonly requested_output_dir=$1
readonly home_dir=${HOME:-}

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

for output_name in metadata.txt executable-size.txt process-samples.tsv disk-io.txt; do
  if [ -L "$output_dir/$output_name" ]; then
    printf 'error: refusing symlinked output file: %s\n' "$output_dir/$output_name" >&2
    exit 2
  fi
done

for required_command in git swift xcodebuild sw_vers sysctl ps wc date iostat sleep tr sed; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$required_command" >&2
    exit 2
  fi
done

readonly profile_pid=${FLECK_PERFORMANCE_PID:-}
if [ -n "$profile_pid" ]; then
  case "$profile_pid" in
    *[!0-9]*)
      printf '%s\n' 'error: FLECK_PERFORMANCE_PID must be a decimal process ID' >&2
      exit 2
      ;;
  esac
  if [ "$profile_pid" -eq 0 ]; then
    printf '%s\n' 'error: FLECK_PERFORMANCE_PID must be a running Fleck process' >&2
    exit 2
  fi
  process_name=$(ps -p "$profile_pid" -o comm= | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ "$process_name" != "Fleck" ]; then
    printf 'error: PID %s is not the Fleck executable\n' "$profile_pid" >&2
    exit 2
  fi
fi

commit=$(git -C "$repo_root" rev-parse HEAD) || exit 2
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || exit 2
machine_model=$(sysctl -n hw.model) || exit 2
macos_version=$(sw_vers -productVersion) || exit 2
macos_build=$(sw_vers -buildVersion) || exit 2
readonly release_executable="$repo_root/.build/release/Fleck"

cd "$repo_root"
swift build -c release --product Fleck --disable-automatic-resolution
if [ ! -x "$release_executable" ]; then
  printf 'error: release executable not found: %s\n' "$release_executable" >&2
  exit 2
fi

executable_bytes=$(wc -c < "$release_executable" | tr -d '[:space:]') || exit 2
{
  printf '%s\n' 'Fleck performance profile metadata'
  printf 'captured_at_utc=%s\n' "$timestamp"
  printf 'machine=%s\n' "$machine_model"
  printf 'architecture=%s\n' "$(uname -m)"
  printf 'macos_version=%s\n' "$macos_version"
  printf 'macos_build=%s\n' "$macos_build"
  printf 'commit=%s\n' "$commit"
  printf 'build_configuration=release\n'
  printf 'repository=%s\n' "$repo_root"
  printf 'output_directory=%s\n' "$output_dir"
  printf 'profile_pid=%s\n' "${profile_pid:-not-provided}"
  printf '%s\n' 'launch_boundary=manual QA Fleck.app launch required; this script does not launch Fleck'
  printf '%s\n' 'data_boundary=the script does not read, copy, move, or delete Fleck Application Support'
  printf '%s\n' 'command=swift build -c release --product Fleck --disable-automatic-resolution'
  printf '%s\n' 'xcode_version:'
  xcodebuild -version
  printf '%s\n' 'swift_version:'
  swift --version
} > "$output_dir/metadata.txt"

{
  printf 'executable=%s\n' "$release_executable"
  printf 'bytes=%s\n' "$executable_bytes"
  printf '%s\n' 'target_bytes=18874368'
  printf '%s\n' 'note=SwiftPM executable size only; measure the final signed .app separately.'
} > "$output_dir/executable-size.txt"

if [ -n "$profile_pid" ]; then
  {
    printf 'sample\tpid\tcpu_percent\tresident_kb\n'
    sample=1
    while [ "$sample" -le 5 ]; do
      process_name=$(ps -p "$profile_pid" -o comm= | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      if [ "$process_name" != "Fleck" ]; then
        printf 'error: Fleck PID %s exited during sampling\n' "$profile_pid" >&2
        exit 2
      fi
      cpu=$(ps -p "$profile_pid" -o %cpu= | tr -d '[:space:]')
      resident_kb=$(ps -p "$profile_pid" -o rss= | tr -d '[:space:]')
      if [ -z "$cpu" ] || [ -z "$resident_kb" ]; then
        printf 'error: could not read metrics for Fleck PID %s\n' "$profile_pid" >&2
        exit 2
      fi
      printf '%s\t%s\t%s\t%s\n' "$sample" "$profile_pid" "$cpu" "$resident_kb"
      if [ "$sample" -lt 5 ]; then sleep 1; fi
      sample=$((sample + 1))
    done
  } > "$output_dir/process-samples.tsv"
else
  {
    printf '%s\n' 'process samples not captured'
    printf '%s\n' 'launch the QA Fleck.app manually, then rerun with FLECK_PERFORMANCE_PID=PID'
  } > "$output_dir/process-samples.tsv"
fi

{
  printf '%s\n' 'logical disk writes: not measured per process by this safe shell workflow'
  printf '%s\n' 'use Instruments File Activity or fs_usage on the caller-specified QA PID'
  printf '%s\n' 'the following is an aggregate device sample and must not be reported as Fleck-only writes'
  iostat -d -w 1 -c 5
} > "$output_dir/disk-io.txt"

printf 'Wrote Fleck performance profile metadata to %s\n' "$output_dir"
printf '%s\n' 'No Fleck process was launched or terminated; fill timing and p50/p95 results from the QA app manually.'
