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

is_forbidden_model_path() {
  local path="$1"
  local boundary="$2"
  local filename
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
  filename="${path##*/}"
  case "$filename" in
    *.mlmodel|*.mlpackage|*.mlmodelc|coremldata.bin|weight.bin|weights.bin)
      return 0
      ;;
  esac

  case "$filename" in
    *.bin)
      case "$boundary_name" in
        model|models|*.mlmodelc|*.mlpackage)
          return 0
          ;;
      esac
      case "$relative_path" in
        *.mlmodelc/*|*.mlpackage/*|model/*|models/*|*/model/*|*/models/*)
          return 0
          ;;
      esac
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
  } elsif ($state eq 'string') {
    my $raw_escape = '\\' . $string_hashes;
    if ($string_hashes ne ''
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
  } elsif ($state eq 'multiline_string') {
    my $raw_escape = '\\' . $string_hashes;
    if ($string_hashes ne ''
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

die "unterminated Swift comment or string in $path\n"
  if $state eq 'block_comment' || $state eq 'string' || $state eq 'multiline_string';
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
if [[ -n "$additional_artifact_root" ]]; then
  scan_roots+=("$additional_artifact_root")
fi
seen_scan_roots=()
scan_index=0
while (( scan_index < ${#scan_roots[@]} )); do
  scan_root="${scan_roots[$scan_index]}"
  scan_index=$((scan_index + 1))

  already_scanned=false
  if (( ${#seen_scan_roots[@]} > 0 )); then
    for seen_root in "${seen_scan_roots[@]}"; do
      if [[ "$seen_root" == "$scan_root" ]]; then
        already_scanned=true
        break
      fi
    done
  fi
  if [[ "$already_scanned" == true ]]; then continue; fi
  seen_scan_roots+=("$scan_root")

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
    if is_forbidden_model_path "$path" "$scan_root"; then
      forbidden_model_assets+=("$path")
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
        forbidden_model_assets+=("$path -> $resolved_path")
      fi
      if [[ -d "$resolved_path" ]]; then
        scan_roots+=("$resolved_path")
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

: > "$scan_output"
: > "$scan_errors"
set +e
find "$sources_root" -type f -name '*.swift' -print0 \
  >"$scan_output" 2>"$scan_errors"
find_exit=$?
set -e
if (( find_exit != 0 )); then
  printf 'error: Swift source traversal failed (exit %s)\n' "$find_exit" >&2
  if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
  exit 2
fi

: > "$all_swift_code"
enhanced_found=false
while IFS= read -r -d '' source_path; do
  : > "$scan_errors"
  set +e
  write_swift_code_only "$source_path" "$swift_piece" 2>"$scan_errors"
  swift_scan_exit=$?
  set -e
  if (( swift_scan_exit != 0 )); then
    printf 'error: could not prepare Swift source for assertions: %s\n' \
      "$source_path" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi
  cat "$swift_piece" >> "$all_swift_code"
  printf '\n' >> "$all_swift_code"
  if [[ "$source_path" == "$enhanced_capture" ]]; then
    cp "$swift_piece" "$enhanced_swift_code"
    enhanced_found=true
  fi
done < "$scan_output"

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
