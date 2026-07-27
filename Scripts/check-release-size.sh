#!/usr/bin/env bash
set -euo pipefail

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

physical_directory() {
  (cd -P -- "$1" 2>/dev/null && pwd)
}

nearest_app_root() {
  local current="$1"
  local parent
  local name

  while :; do
    name="$(lowercase "$(basename "$current")")"
    if [[ "$name" == *.app ]]; then
      physical_directory "$current"
      return
    fi
    parent="$(dirname "$current")"
    if [[ "$parent" == "$current" || "$current" == "." ]]; then
      return 1
    fi
    current="$parent"
  done
}

is_model_context_path() {
  local path="$1"
  local boundary="$2"
  local relative_path
  local boundary_name

  if [[ "$path" == "$boundary" ]]; then
    relative_path="${path##*/}"
  elif [[ "$path" == "$boundary/"* ]]; then
    relative_path="${path#"$boundary/"}"
  else
    relative_path="${path##*/}"
  fi

  path="$(lowercase "$path")"
  relative_path="$(lowercase "$relative_path")"
  boundary_name="$(lowercase "${boundary##*/}")"
  case "$boundary_name" in
    model|models|*.mlmodelc|*.mlpackage)
      return 0
      ;;
  esac
  case "$relative_path" in
    *.mlmodelc|*.mlmodelc/*|*.mlpackage|*.mlpackage/*|\
      model|model/*|models|models/*|*/model|*/model/*|*/models|*/models/*)
      return 0
      ;;
  esac
  return 1
}

is_forbidden_model_path() {
  local path="$1"
  local boundary="$2"
  local model_context="${3:-false}"
  local filename
  local original_path="$path"

  path="$(lowercase "$path")"
  filename="${path##*/}"
  case "$filename" in
    *.mlmodel|*.mlpackage|*.mlmodelc|coremldata.bin|weight.bin|weights.bin)
      return 0
      ;;
  esac

  case "$filename" in
    *.bin)
      if [[ "$model_context" == true ]] \
        || is_model_context_path "$original_path" "$boundary"; then
        return 0
      fi
      ;;
  esac
  return 1
}

write_swift_code_only() {
  local source="$1"
  local destination="$2"

  perl - "$source" >"$destination" <<'PERL'
use strict;
use warnings;

my $path = shift @ARGV;
open my $input, '<', $path or die "cannot open $path: $!\n";
local $/;
my $source = <$input>;
close $input or die "cannot close $path: $!\n";

my $output = '';
my $index = 0;
my $state = 'code';
my $block_depth = 0;
my $string_hashes = '';
my $string_closer = '';
my $interpolation_depth = 0;
my @interpolation_frames;
while ($index < length $source) {
  my $character = substr($source, $index, 1);
  my $pair = substr($source, $index, 2);
  my $remaining = substr($source, $index);

  if ($state eq 'code') {
    if ($remaining =~ /\A(#+)?("""|")/) {
      $string_hashes = defined $1 ? $1 : '';
      my $quotes = $2;
      my $opening = $string_hashes . $quotes;
      $string_closer = $quotes . $string_hashes;
      $output .= ' ' x length($opening);
      $index += length($opening);
      $state = length($quotes) == 3 ? 'multiline_string' : 'string';
    } elsif ($pair eq '//') {
      $output .= '  ';
      $index += 2;
      $state = 'line_comment';
    } elsif ($pair eq '/*') {
      $output .= '  ';
      $index += 2;
      $block_depth = 1;
      $state = 'block_comment';
    } elsif (@interpolation_frames && $character eq '(') {
      $output .= $character;
      $index += 1;
      $interpolation_depth += 1;
    } elsif (@interpolation_frames && $character eq ')') {
      $output .= $character;
      $index += 1;
      $interpolation_depth -= 1;
      if ($interpolation_depth == 0) {
        my $frame = pop @interpolation_frames;
        ($state, $string_hashes, $string_closer, $interpolation_depth) = @$frame;
      }
    } else {
      $output .= $character;
      $index += 1;
    }
  } elsif ($state eq 'line_comment') {
    $output .= $character eq "\n" ? "\n" : ' ';
    $index += 1;
    $state = 'code' if $character eq "\n";
  } elsif ($state eq 'block_comment') {
    if ($pair eq '/*') {
      $output .= '  ';
      $index += 2;
      $block_depth += 1;
    } elsif ($pair eq '*/') {
      $output .= '  ';
      $index += 2;
      $block_depth -= 1;
      $state = 'code' if $block_depth == 0;
    } else {
      $output .= $character eq "\n" ? "\n" : ' ';
      $index += 1;
    }
  } elsif ($state eq 'string' || $state eq 'multiline_string') {
    my $raw_escape = '\\' . $string_hashes;
    my $interpolation_opener = $raw_escape . '(';
    if (substr($source, $index, length($interpolation_opener))
      eq $interpolation_opener) {
      push @interpolation_frames,
        [$state, $string_hashes, $string_closer, $interpolation_depth];
      $output .= ' ' x length($interpolation_opener);
      $index += length($interpolation_opener);
      $interpolation_depth = 1;
      $state = 'code';
    } elsif ($string_hashes ne ''
      && substr($source, $index, length($raw_escape)) eq $raw_escape
      && $index + length($raw_escape) < length $source) {
      my $escaped = substr($source, $index, length($raw_escape) + 1);
      $escaped =~ s/[^\n]/ /g;
      $output .= $escaped;
      $index += length($raw_escape) + 1;
    } elsif (substr($source, $index, length($string_closer)) eq $string_closer) {
      $output .= ' ' x length($string_closer);
      $index += length($string_closer);
      $state = 'code';
    } elsif ($string_hashes eq '' && $character eq '\\'
      && $index + 1 < length $source) {
      my $escaped = substr($source, $index, 2);
      $escaped =~ s/[^\n]/ /g;
      $output .= $escaped;
      $index += 2;
    } else {
      $output .= $character eq "\n" ? "\n" : ' ';
      $index += 1;
    }
  }
}

die "unterminated Swift comment, string, or interpolation in $path\n"
  if $state eq 'block_comment' || $state eq 'string'
    || $state eq 'multiline_string' || @interpolation_frames;
print $output;
PERL
}

assert_rg_present() {
  local pattern="$1"
  local description="$2"
  local output
  local rg_exit
  shift 2

  set +e
  output="$(rg -U -n --glob '*.swift' -- "$pattern" "$@" 2>&1)"
  rg_exit=$?
  set -e
  case "$rg_exit" in
    0)
      return
      ;;
    1)
      printf 'error: required production source missing: %s\n' "$description" >&2
      exit 1
      ;;
    *)
      printf 'error: ripgrep failed while checking %s (exit %s)\n' \
        "$description" "$rg_exit" >&2
      if [[ -n "$output" ]]; then printf '%s\n' "$output" >&2; fi
      exit 2
      ;;
  esac
}

assert_rg_absent() {
  local pattern="$1"
  local description="$2"
  local output
  local rg_exit
  shift 2

  set +e
  output="$(rg -U -n --glob '*.swift' -- "$pattern" "$@" 2>&1)"
  rg_exit=$?
  set -e
  case "$rg_exit" in
    0)
      if [[ -n "$output" ]]; then printf '%s\n' "$output" >&2; fi
      printf 'error: forbidden production source found: %s\n' "$description" >&2
      exit 1
      ;;
    1)
      return
      ;;
    *)
      printf 'error: ripgrep failed while checking %s (exit %s)\n' \
        "$description" "$rg_exit" >&2
      if [[ -n "$output" ]]; then printf '%s\n' "$output" >&2; fi
      exit 2
      ;;
  esac
}

readonly target="${1:-.build/release/Motes}"
readonly limit_mb="${APP_SIZE_LIMIT_MB:-15}"
readonly limit_bytes=$((limit_mb * 1024 * 1024))
readonly repository_root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly sources_root="$repository_root/Sources"
readonly enhanced_capture="$sources_root/MenuBarNotesApp/EnhancedSpeechCapture.swift"

if ! command -v realpath >/dev/null 2>&1; then
  printf 'error: realpath is required for safe release artifact traversal\n' >&2
  exit 2
fi

additional_artifact_root=""
if [[ -f "$target" ]]; then
  set +e
  resolved_executable="$(realpath "$target" 2>/dev/null)"
  realpath_exit=$?
  set -e
  if (( realpath_exit != 0 )) || [[ ! -f "$resolved_executable" ]]; then
    printf 'error: cannot resolve release executable: %s\n' "$target" >&2
    exit 2
  fi
  readonly executable="$resolved_executable"
  executable_directory="$(dirname "$resolved_executable")"
  logical_app_root=""
  resolved_app_root=""
  if app_root="$(nearest_app_root "$(dirname "$target")")"; then
    logical_app_root="$app_root"
  fi
  if app_root="$(nearest_app_root "$executable_directory")"; then
    resolved_app_root="$app_root"
  fi
  if [[ -n "$resolved_app_root" ]]; then
    readonly artifact_root="$resolved_app_root"
    if [[ -n "$logical_app_root" && "$logical_app_root" != "$resolved_app_root" ]]; then
      additional_artifact_root="$logical_app_root"
    fi
  elif [[ -n "$logical_app_root" ]]; then
    readonly artifact_root="$logical_app_root"
  else
    readonly artifact_root="$executable_directory"
  fi
elif [[ -d "$target" ]]; then
  resolved_target="$(physical_directory "$target")" || {
    printf 'error: cannot resolve release artifact directory: %s\n' "$target" >&2
    exit 2
  }
  if [[ -f "$resolved_target/Contents/MacOS/Motes" ]]; then
    readonly executable="$resolved_target/Contents/MacOS/Motes"
    readonly artifact_root="$resolved_target"
  elif [[ -f "$resolved_target/Motes" ]]; then
    readonly executable="$resolved_target/Motes"
    readonly artifact_root="$resolved_target"
  else
    printf 'error: release executable not found in artifact: %s\n' "$target" >&2
    exit 2
  fi
else
  printf 'error: release executable or artifact not found: %s\n' "$target" >&2
  exit 2
fi

size_bytes="$(wc -c < "$executable" | tr -d '[:space:]')"
printf 'Release executable: %s bytes (budget: %s MB)\n' "$size_bytes" "$limit_mb"

if (( size_bytes > limit_bytes )); then
  printf 'error: release executable exceeds the %s MB budget\n' "$limit_mb" >&2
  exit 1
fi

scan_output="$(mktemp "${TMPDIR:-/tmp}/motes-release-scan.XXXXXX")" || {
  printf 'error: could not create release artifact scan output\n' >&2
  exit 2
}
scan_errors="$(mktemp "${TMPDIR:-/tmp}/motes-release-scan-errors.XXXXXX")" || {
  printf 'error: could not create release artifact scan error output\n' >&2
  /bin/rm -f "$scan_output"
  exit 2
}
all_swift_code="${scan_output}-all.swift"
enhanced_swift_code="${scan_output}-enhanced.swift"
swift_piece="${scan_output}-piece.swift"
cleanup_scan_files() {
  /bin/rm -f "$scan_output" "$scan_errors" \
    "$all_swift_code" "$enhanced_swift_code" "$swift_piece"
}
trap cleanup_scan_files EXIT

forbidden_model_assets=()
scan_roots=("$artifact_root")
scan_logical_roots=("$artifact_root")
scan_boundaries=("$artifact_root")
scan_model_contexts=(false)
if [[ -n "$additional_artifact_root" ]]; then
  scan_roots+=("$additional_artifact_root")
  scan_logical_roots+=("$additional_artifact_root")
  scan_boundaries+=("$additional_artifact_root")
  scan_model_contexts+=(false)
fi
seen_scan_roots=()
seen_scan_contexts=()
scan_index=0
while (( scan_index < ${#scan_roots[@]} )); do
  scan_root="${scan_roots[$scan_index]}"
  scan_logical_root="${scan_logical_roots[$scan_index]}"
  scan_boundary="${scan_boundaries[$scan_index]}"
  scan_model_context="${scan_model_contexts[$scan_index]}"
  scan_index=$((scan_index + 1))

  already_scanned=false
  if (( ${#seen_scan_roots[@]} > 0 )); then
    seen_index=0
    while (( seen_index < ${#seen_scan_roots[@]} )); do
      if [[ "${seen_scan_roots[$seen_index]}" == "$scan_root" \
        && "${seen_scan_contexts[$seen_index]}" == "$scan_model_context" ]]; then
        already_scanned=true
        break
      fi
      seen_index=$((seen_index + 1))
    done
  fi
  if [[ "$already_scanned" == true ]]; then continue; fi
  seen_scan_roots+=("$scan_root")
  seen_scan_contexts+=("$scan_model_context")

  : > "$scan_output"
  : > "$scan_errors"
  set +e
  find "$scan_root" \
    \( -type l -o -iname '*.mlmodel' -o -iname '*.mlpackage' \
      -o -iname '*.mlmodelc' -o -iname '*.bin' \) \
    -print0 >"$scan_output" 2>"$scan_errors"
  find_exit=$?
  set -e
  if (( find_exit != 0 )); then
    printf 'error: release artifact traversal failed at %s (exit %s)\n' \
      "$scan_root" "$find_exit" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi

  while IFS= read -r -d '' path; do
    logical_path="$scan_logical_root${path#"$scan_root"}"
    if is_forbidden_model_path \
      "$logical_path" "$scan_boundary" "$scan_model_context"; then
      forbidden_model_assets+=("$logical_path")
    fi

    if [[ -L "$path" ]]; then
      : > "$scan_errors"
      set +e
      resolved_path="$(realpath "$path" 2>"$scan_errors")"
      realpath_exit=$?
      set -e
      if (( realpath_exit != 0 )) || [[ ! -e "$resolved_path" ]]; then
        printf 'error: release artifact symlink cannot be resolved: %s\n' \
          "$path" >&2
        if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
        exit 2
      fi
      if is_forbidden_model_path "$resolved_path" "$(dirname "$resolved_path")"; then
        forbidden_model_assets+=("$logical_path -> $resolved_path")
      fi
      if [[ -d "$resolved_path" ]]; then
        linked_model_context="$scan_model_context"
        if is_model_context_path "$logical_path" "$scan_boundary" \
          || is_model_context_path "$resolved_path" "$resolved_path"; then
          linked_model_context=true
        fi
        scan_roots+=("$resolved_path")
        scan_logical_roots+=("$logical_path")
        scan_boundaries+=("$scan_boundary")
        scan_model_contexts+=("$linked_model_context")
      fi
    fi
  done < "$scan_output"
done

if (( ${#forbidden_model_assets[@]} > 0 )); then
  printf 'error: release artifact contains model assets:\n' >&2
  for path in "${forbidden_model_assets[@]}"; do
    printf '  %s\n' "$path" >&2
  done
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for release source assertions\n' >&2
  exit 2
fi

if ! command -v perl >/dev/null 2>&1; then
  printf 'error: perl is required for Swift source assertions\n' >&2
  exit 2
fi

: > "$all_swift_code"
enhanced_found=false
source_scan_roots=("$sources_root")
source_logical_roots=("$sources_root")
source_ancestor_separator=$'\034'
source_ancestor_chains=(
  "${source_ancestor_separator}${sources_root}${source_ancestor_separator}"
)
seen_source_roots=()
seen_source_files=()
source_scan_index=0
while (( source_scan_index < ${#source_scan_roots[@]} )); do
  source_scan_root="${source_scan_roots[$source_scan_index]}"
  source_logical_root="${source_logical_roots[$source_scan_index]}"
  source_ancestor_chain="${source_ancestor_chains[$source_scan_index]}"
  source_scan_index=$((source_scan_index + 1))

  source_root_seen=false
  if (( ${#seen_source_roots[@]} > 0 )); then
    for seen_source_root in "${seen_source_roots[@]}"; do
      if [[ "$seen_source_root" == "$source_scan_root" ]]; then
        source_root_seen=true
        break
      fi
    done
  fi
  if [[ "$source_root_seen" == true ]]; then continue; fi
  seen_source_roots+=("$source_scan_root")

  : > "$scan_output"
  : > "$scan_errors"
  set +e
  find "$source_scan_root" \
    \( -type l -o \( -type f -name '*.swift' \) \) \
    -print0 >"$scan_output" 2>"$scan_errors"
  find_exit=$?
  set -e
  if (( find_exit != 0 )); then
    printf 'error: Swift source traversal failed at %s (exit %s)\n' \
      "$source_logical_root" "$find_exit" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi

  while IFS= read -r -d '' source_path; do
    logical_source_path="$source_logical_root${source_path#"$source_scan_root"}"
    physical_source_path="$source_path"

    if [[ -L "$source_path" ]]; then
      : > "$scan_errors"
      set +e
      physical_source_path="$(realpath "$source_path" 2>"$scan_errors")"
      realpath_exit=$?
      set -e
      if (( realpath_exit != 0 )) || [[ ! -e "$physical_source_path" ]]; then
        printf 'error: Swift source symlink cannot be resolved: %s\n' \
          "$logical_source_path" >&2
        if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
        exit 2
      fi

      if [[ -d "$physical_source_path" ]]; then
        source_parent="$(dirname "$source_path")"
        if [[ "$source_parent" == "$physical_source_path" \
          || "$source_parent" == "$physical_source_path/"* \
          || "$source_ancestor_chain" == \
            *"${source_ancestor_separator}${physical_source_path}${source_ancestor_separator}"* ]]; then
          printf 'error: Swift source symlink cycle detected: %s\n' \
            "$logical_source_path" >&2
          exit 2
        fi
        source_scan_roots+=("$physical_source_path")
        source_logical_roots+=("$logical_source_path")
        source_ancestor_chains+=(
          "${source_ancestor_chain}${physical_source_path}${source_ancestor_separator}"
        )
        continue
      fi
    fi

    case "$logical_source_path" in
      *.swift)
        ;;
      *)
        continue
        ;;
    esac
    if [[ ! -f "$physical_source_path" ]]; then
      printf 'error: Swift source path is not a file: %s\n' \
        "$logical_source_path" >&2
      exit 2
    fi

    source_file_seen=false
    if (( ${#seen_source_files[@]} > 0 )); then
      for seen_source_file in "${seen_source_files[@]}"; do
        if [[ "$seen_source_file" == "$physical_source_path" ]]; then
          source_file_seen=true
          break
        fi
      done
    fi
    if [[ "$source_file_seen" == true && "$logical_source_path" != "$enhanced_capture" ]]; then
      continue
    fi

    : > "$scan_errors"
    set +e
    write_swift_code_only "$physical_source_path" "$swift_piece" 2>"$scan_errors"
    swift_scan_exit=$?
    set -e
    if (( swift_scan_exit != 0 )); then
      printf 'error: could not prepare Swift source for assertions: %s\n' \
        "$logical_source_path" >&2
      if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
      exit 2
    fi

    if [[ "$source_file_seen" != true ]]; then
      seen_source_files+=("$physical_source_path")
      cat "$swift_piece" >> "$all_swift_code"
      printf '\n' >> "$all_swift_code"
    fi
    if [[ "$logical_source_path" == "$enhanced_capture" ]]; then
      cp "$swift_piece" "$enhanced_swift_code"
      enhanced_found=true
    fi
  done < "$scan_output"
done

if [[ "$enhanced_found" != true ]]; then
  printf 'error: EnhancedSpeechCapture Swift source was not found\n' >&2
  exit 2
fi

assert_rg_present \
  '(?m)^[\t ]*ModelHub[\t \r\n]*\.[\t \r\n]*offlineMode[\t \r\n]*=[\t \r\n]*true[\t ]*(?://[^\r\n]*)?$' \
  'an executable ModelHub.offlineMode = true assignment in EnhancedSpeechCapture' \
  "$enhanced_swift_code"
assert_rg_absent \
  '\bModelHub\s*\.\s*offlineMode\s*=\s*false\b' \
  'ModelHub.offlineMode = false' \
  "$all_swift_code"
assert_rg_absent \
  '\bAsrModels\s*\.\s*downloadAndLoad\b' \
  'AsrModels.downloadAndLoad' \
  "$all_swift_code"
assert_rg_absent \
  '\bModelHub\s*\.\s*(download|fetchFile)\b' \
  'ModelHub.download or ModelHub.fetchFile in EnhancedSpeechCapture' \
  "$enhanced_swift_code"
assert_rg_absent \
  '\bNSEvent\s*\.\s*addGlobalMonitorForEvents\b' \
  'NSEvent.addGlobalMonitorForEvents' \
  "$all_swift_code"

printf 'Release artifact contains no bundled model assets.\n'
printf 'Release source assertions passed.\n'
