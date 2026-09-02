#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "$script_dir/../../../.." && pwd -P)"
readonly revision="a3c817cbf7c08863e0c472861c7c39e27ce7f38e"
readonly english_url="https://huggingface.co/datasets/google/fleurs/resolve/$revision/en_us/validation-00000-of-00001.parquet"
readonly mandarin_url="https://huggingface.co/datasets/google/fleurs/resolve/$revision/cmn_hans_cn/validation-00000-of-00001.parquet"
readonly english_name="en_us-validation-00000-of-00001.parquet"
readonly mandarin_name="cmn_hans_cn-validation-00000-of-00001.parquet"
readonly english_sha256="7c3eebdff31e1c510b78e51319e5b9779429b87c9895f2e5f3005bfe68854c65"
readonly mandarin_sha256="18698f80879a221f68318a4ccb8752b74c2f5bf521af0e0011b07e4670ea62ad"
readonly english_bytes="236549523"
readonly mandarin_bytes="287985961"

die() {
  echo "acquire-corpus: $*" >&2
  exit 2
}

usage() {
  echo "usage: acquire-corpus.sh [--dry-run] ABSOLUTE_DESTINATION" >&2
  exit 2
}

absolute_local_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != *"://"* && "$path" != "/" ]] || return 1
  [[ "$path" != *"/../"* && "$path" != */.. && "$path" != *"/./"* && "$path" != */. ]] || return 1
}

file_byte_count() {
  local path="$1"
  local count
  if count="$(stat -f %z "$path" 2>/dev/null)"; then
    printf '%s\n' "$count"
  else
    stat -c %s "$path"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_existing_final() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"
  local actual_bytes
  local actual_sha256

  [[ -f "$path" && ! -L "$path" ]] || die "existing final must be a non-symlink regular file: $path"
  actual_bytes="$(file_byte_count "$path")"
  [[ "$actual_bytes" == "$expected_bytes" ]] || die "existing final has the wrong byte count: $path"
  actual_sha256="$(sha256_file "$path")"
  [[ "$actual_sha256" == "$expected_sha256" ]] || die "existing final has the wrong SHA-256: $path"
}

destination_real_path() {
  local destination="$1"
  local parent
  parent="$(dirname "$destination")"
  [[ -d "$parent" ]] || die "destination parent is not a directory: $parent"
  (cd -P "$parent" && printf '%s/%s\n' "$PWD" "$(basename "$destination")")
}

validate_destination() {
  local destination="$1"
  local destination_real="$2"
  local destination_exists="$3"
  local final_name
  local entry

  case "$destination_real" in
    "$repository_root"|"$repository_root"/*)
      die "destination must not be inside the repository"
      ;;
  esac

  if [[ "$destination_exists" == true ]]; then
    [[ ! -L "$destination" ]] || die "destination must not be a symlink"
    [[ -d "$destination" ]] || die "destination must be a directory"
    for entry in "$destination"/* "$destination"/.[!.]* "$destination"/..?*; do
      [[ -e "$entry" || -L "$entry" ]] || continue
      final_name="$(basename "$entry")"
      case "$final_name" in
        "$english_name")
          verify_existing_final "$entry" "$english_bytes" "$english_sha256"
          ;;
        "$mandarin_name")
          verify_existing_final "$entry" "$mandarin_bytes" "$mandarin_sha256"
          ;;
        "$english_name.partial"|"$mandarin_name.partial")
          [[ -f "$entry" && ! -L "$entry" ]] || die "partial download must be a non-symlink regular file: $entry"
          ;;
        *)
          die "destination contains an unexpected or overwrite target: $entry"
          ;;
      esac
    done
  fi
}

download_and_publish() {
  local url="$1"
  local name="$2"
  local expected_sha256="$3"
  local expected_bytes="$4"
  local final="$destination/$name"
  local partial="$final.partial"
  local actual_bytes
  local actual_sha256

  if [[ -e "$final" || -L "$final" ]]; then
    verify_existing_final "$final" "$expected_bytes" "$expected_sha256"
    echo "already acquired $name ($expected_bytes bytes, $expected_sha256)"
    return
  fi
  if [[ -e "$partial" || -L "$partial" ]]; then
    [[ -f "$partial" && ! -L "$partial" ]] || die "partial download must be a non-symlink regular file: $partial"
  fi

  if [[ -e "$partial" ]]; then
    actual_bytes="$(file_byte_count "$partial")"
    [[ "$actual_bytes" -le "$expected_bytes" ]] || die "partial download is larger than its contract: $partial"
    if [[ "$actual_bytes" -eq "$expected_bytes" ]]; then
      actual_sha256="$(sha256_file "$partial")"
      [[ "$actual_sha256" == "$expected_sha256" ]] || die "complete partial download has the wrong SHA-256: $partial"
    else
      curl --fail --location --retry 3 --continue-at - --output "$partial" "$url"
    fi
  else
    curl --fail --location --retry 3 --continue-at - --output "$partial" "$url"
  fi

  actual_bytes="$(file_byte_count "$partial")"
  [[ "$actual_bytes" == "$expected_bytes" ]] || die "byte-count mismatch for $partial: expected $expected_bytes, got $actual_bytes"
  actual_sha256="$(sha256_file "$partial")"
  [[ "$actual_sha256" == "$expected_sha256" ]] || die "SHA-256 mismatch for $partial: expected $expected_sha256, got $actual_sha256"

  [[ ! -e "$final" && ! -L "$final" ]] || die "destination appeared during publication: $final"
  /bin/link "$partial" "$final" || die "exclusive publication failed: $final"
  rm "$partial"
  echo "acquired $name ($expected_bytes bytes, $expected_sha256)"
}

dry_run=false
destination=""
if [[ "$#" -eq 0 ]]; then
  usage
fi
case "$#:$1" in
  1:/*)
    destination="$1"
    ;;
  2:--dry-run)
    dry_run=true
    destination="$2"
    ;;
  *)
    usage
    ;;
esac

absolute_local_path "$destination" || die "destination must be an absolute local path"
destination_real="$(destination_real_path "$destination")"
destination_exists=false
if [[ -e "$destination" || -L "$destination" ]]; then
  destination_exists=true
fi
validate_destination "$destination" "$destination_real" "$destination_exists"

if [[ "$destination_exists" == false ]]; then
  [[ "$dry_run" == true ]] || mkdir "$destination"
  if [[ "$dry_run" == false ]]; then
    [[ ! -L "$destination" && -d "$destination" ]] || die "destination changed during creation"
  fi
fi

if [[ "$dry_run" == true ]]; then
  echo "dry-run: would acquire $english_url -> $destination/$english_name"
  echo "dry-run: would verify $english_bytes bytes and $english_sha256"
  echo "dry-run: would acquire $mandarin_url -> $destination/$mandarin_name"
  echo "dry-run: would verify $mandarin_bytes bytes and $mandarin_sha256"
  exit 0
fi

download_and_publish "$english_url" "$english_name" "$english_sha256" "$english_bytes"
download_and_publish "$mandarin_url" "$mandarin_name" "$mandarin_sha256" "$mandarin_bytes"
