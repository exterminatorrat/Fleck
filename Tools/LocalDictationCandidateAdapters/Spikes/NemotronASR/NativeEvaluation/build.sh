#!/usr/bin/env bash

set -euo pipefail

# source-anchor and build-input snapshots are checked before publication.

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repo_root="$(cd "$script_dir/../../../../.." && pwd -P)"
readonly model_protocol_source="$repo_root/Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol"
readonly wave_reader_source="$repo_root/Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Sources/QwenASRSpikeSupport/WaveReader.swift"
readonly recognizer_source="$script_dir/NemotronRecognizer.swift"
readonly main_source="$script_dir/main.swift"
readonly bridging_header="$script_dir/NemoSpeechASR-Bridging-Header.h"

source_path=""
output_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-path)
      [[ $# -ge 2 && -z "$source_path" ]] || { echo "invalid-source-path-arguments" >&2; exit 2; }
      source_path="$2"
      shift 2
      ;;
    --output-root)
      [[ $# -ge 2 && -z "$output_root" ]] || { echo "invalid-output-root-arguments" >&2; exit 2; }
      output_root="$2"
      shift 2
      ;;
    *)
      echo "unsupported-argument:$1" >&2
      exit 2
      ;;
  esac
done

is_safe_absolute_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != *"://"* && "$path" != *"/./"* && "$path" != *"/../"* && "$path" != */. && "$path" != */.. && "$path" != *$'\n'* && "$path" != *$'\r'* ]]
}

has_symlink_component() {
  local path="$1"
  local current="/"
  local remaining="${path#/}"
  local component
  while [[ -n "$remaining" ]]; do
    if [[ "$remaining" == */* ]]; then
      component="${remaining%%/*}"
      remaining="${remaining#*/}"
    else
      component="$remaining"
      remaining=""
    fi
    [[ -n "$component" ]] || continue
    current="${current%/}/$component"
    [[ -L "$current" ]] && return 0
  done
  return 1
}

canonicalize_existing_ancestor() {
  local path="$1"
  local unresolved=""
  local probe="$path"
  local component
  while [[ ! -e "$probe" && ! -L "$probe" ]]; do
    [[ "$probe" != "/" ]] || return 1
    component="${probe##*/}"
    unresolved="/$component$unresolved"
    probe="${probe%/*}"
    [[ -n "$probe" ]] || probe="/"
  done
  local canonical
  canonical="$(realpath "$probe")" || return 1
  if [[ "$canonical" == "/" ]]; then
    printf '/%s\n' "${unresolved#/}"
  else
    printf '%s%s\n' "${canonical%/}" "$unresolved"
  fi
}

[[ -n "$source_path" && -n "$output_root" ]] || {
  echo "source-path-and-output-root-required" >&2
  exit 2
}
is_safe_absolute_path "$source_path" || { echo "source-path-must-be-absolute" >&2; exit 2; }
is_safe_absolute_path "$output_root" || { echo "output-root-must-be-absolute" >&2; exit 2; }
has_symlink_component "$source_path" && { echo "source-path-symlink-alias-rejected" >&2; exit 2; }
has_symlink_component "$output_root" && { echo "output-root-symlink-alias-rejected" >&2; exit 2; }

readonly canonical_repo_root="$(realpath "$repo_root")"
readonly canonical_source_path="$(canonicalize_existing_ancestor "$source_path")" || {
  echo "source-path-cannot-be-canonicalized" >&2
  exit 2
}
[[ "$canonical_source_path" == "$source_path" ]] || {
  echo "source-path-must-be-canonical" >&2
  exit 2
}
[[ -d "$source_path" && ! -L "$source_path" ]] || {
  echo "source-path-must-be-directory" >&2
  exit 2
}
readonly canonical_output_root="$(canonicalize_existing_ancestor "$output_root")" || {
  echo "output-root-cannot-be-canonicalized" >&2
  exit 2
}
[[ "$canonical_output_root" == "$output_root" ]] || {
  echo "output-root-must-be-canonical" >&2
  exit 2
}
if [[ "$canonical_output_root" == "$canonical_repo_root" || "$canonical_output_root" == "$canonical_repo_root"/* ]]; then
  echo "output-root-must-be-external" >&2
  exit 2
fi
readonly output_parent="$(dirname "$output_root")"
[[ -d "$output_parent" && ! -L "$output_parent" ]] || {
  echo "output-parent-must-be-existing-directory" >&2
  exit 2
}
[[ -d "$output_root" && ! -L "$output_root" ]] || {
  echo "output-root-must-be-existing-directory" >&2
  exit 2
}
[[ "$(uname -m)" == "arm64" ]] || { echo "arm64-required" >&2; exit 2; }

readonly temporary_build_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-nemotron-native-build.XXXXXX")"
trap 'rm -rf "$temporary_build_root"; exec 6<&- 7<&- 8<&- 9<&- 2>/dev/null || true' EXIT

exec 6< "$source_path"
exec 7< "$output_parent"
exec 8< "$output_root"
exec 9< "$canonical_repo_root"

readonly publication_tool="$temporary_build_root/nemotron-anchor-tool"
/usr/bin/clang \
  -target arm64-apple-macosx14.0 \
  -O2 -Wall -Werror -x c - -o "$publication_tool" <<'EOF'
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int parse_fd(const char *value) {
    char *end = NULL;
    long fd = strtol(value, &end, 10);
    if (value == end || *end != '\0' || fd < 0 || fd > INT_MAX) return -1;
    return (int)fd;
}

static int same_directory(int fd, const char *path) {
    struct stat held;
    struct stat current;
    int relative_fd = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (relative_fd < 0) return 0;
    close(relative_fd);
    if (fstat(fd, &held) != 0 || lstat(path, &current) != 0) return 0;
    if ((held.st_mode & S_IFMT) != S_IFDIR || (current.st_mode & S_IFMT) != S_IFDIR) return 0;
    return held.st_dev == current.st_dev && held.st_ino == current.st_ino;
}

static int check_anchors(int parent_fd, const char *parent_path,
                         int output_fd, const char *output_path,
                         int repo_fd, const char *repo_path,
                         int source_fd, const char *source_path) {
    return same_directory(parent_fd, parent_path) &&
        same_directory(output_fd, output_path) &&
        same_directory(repo_fd, repo_path) &&
        same_directory(source_fd, source_path);
}

static int copy_snapshot(const char *source_path, const char *destination_path) {
    struct stat path_stat;
    struct stat fd_stat;
    if (lstat(source_path, &path_stat) != 0 || (path_stat.st_mode & S_IFMT) != S_IFREG) return 2;
    int source_fd = open(source_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (source_fd < 0 || fstat(source_fd, &fd_stat) != 0 ||
        (fd_stat.st_mode & S_IFMT) != S_IFREG ||
        fd_stat.st_dev != path_stat.st_dev || fd_stat.st_ino != path_stat.st_ino) {
        if (source_fd >= 0) close(source_fd);
        return 2;
    }
    int destination_fd = open(destination_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (destination_fd < 0) { close(source_fd); return 2; }
    char buffer[1048576];
    int failed = 0;
    ssize_t count;
    while ((count = read(source_fd, buffer, sizeof(buffer))) > 0) {
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(destination_fd, buffer + offset, (size_t)(count - offset));
            if (written <= 0) { failed = 1; break; }
            offset += written;
        }
        if (failed) break;
    }
    if (count < 0 || fsync(destination_fd) != 0 || fchmod(destination_fd, 0400) != 0) failed = 1;
    close(source_fd);
    close(destination_fd);
    if (failed) { unlink(destination_path); return 2; }
    return 0;
}

static int publish_exclusive(int parent_fd, const char *parent_path,
                             int output_fd, const char *output_path,
                             int repo_fd, const char *repo_path,
                             int source_fd, const char *source_path,
                             const char *temporary_binary) {
    if (!check_anchors(parent_fd, parent_path, output_fd, output_path,
                       repo_fd, repo_path, source_fd, source_path)) return 2;
    struct stat source_path_stat;
    struct stat source_fd_stat;
    if (lstat(temporary_binary, &source_path_stat) != 0 ||
        (source_path_stat.st_mode & S_IFMT) != S_IFREG) return 2;
    int source_binary_fd = open(temporary_binary, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (source_binary_fd < 0 || fstat(source_binary_fd, &source_fd_stat) != 0 ||
        source_fd_stat.st_dev != source_path_stat.st_dev ||
        source_fd_stat.st_ino != source_path_stat.st_ino) {
        if (source_binary_fd >= 0) close(source_binary_fd);
        return 2;
    }
    close(source_binary_fd);
    if (linkat(AT_FDCWD, temporary_binary, output_fd,
               "nemotron-native-evaluation", 0) != 0) return 2;
    if (!check_anchors(parent_fd, parent_path, output_fd, output_path,
                       repo_fd, repo_path, source_fd, source_path)) {
        unlinkat(output_fd, "nemotron-native-evaluation", 0);
        return 2;
    }
    if (unlink(temporary_binary) != 0 || fsync(output_fd) != 0) {
        unlinkat(output_fd, "nemotron-native-evaluation", 0);
        return 2;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 4 && strcmp(argv[1], "snapshot") == 0) {
        return copy_snapshot(argv[2], argv[3]);
    }
    if (argc == 10 && strcmp(argv[1], "check") == 0) {
        int parent_fd = parse_fd(argv[2]);
        int output_fd = parse_fd(argv[4]);
        int repo_fd = parse_fd(argv[6]);
        int source_fd = parse_fd(argv[8]);
        if (parent_fd < 0 || output_fd < 0 || repo_fd < 0 || source_fd < 0) return 2;
        return check_anchors(parent_fd, argv[3], output_fd, argv[5],
                             repo_fd, argv[7], source_fd, argv[9]) ? 0 : 2;
    }
    if (argc == 11 && strcmp(argv[1], "publish") == 0) {
        int parent_fd = parse_fd(argv[2]);
        int output_fd = parse_fd(argv[4]);
        int repo_fd = parse_fd(argv[6]);
        int source_fd = parse_fd(argv[8]);
        if (parent_fd < 0 || output_fd < 0 || repo_fd < 0 || source_fd < 0) return 2;
        return publish_exclusive(parent_fd, argv[3], output_fd, argv[5],
                                 repo_fd, argv[7], source_fd, argv[9], argv[10]);
    }
    return 2;
}
EOF

check_anchors() {
  "$publication_tool" check 7 "$output_parent" 8 "$output_root" 9 "$canonical_repo_root" 6 "$source_path"
}

pause_for_test() {
  local stage="$1"
  [[ "${FLECK_NEMOTRON_BUILD_TEST_PAUSE:-}" == "$stage" ]] || return 0
  local marker="${FLECK_NEMOTRON_BUILD_TEST_MARKER:-}"
  local release="${FLECK_NEMOTRON_BUILD_TEST_RELEASE:-}"
  [[ -n "$marker" && -n "$release" ]] || { echo "build-test-pause-files-required" >&2; exit 2; }
  : > "$marker"
  while [[ ! -e "$release" ]]; do sleep 0.01; done
}

verify_source_identity() {
  local expected_source_commit="5be7bfb104802131e61fe679b3f1401b27270216"
  [[ "$(git --no-optional-locks -C "$source_path" rev-parse --verify HEAD)" == "$expected_source_commit" ]] || {
    echo "source-commit-mismatch" >&2
    exit 2
  }
  [[ -z "$(git --no-optional-locks -C "$source_path" status --porcelain=v1 --untracked-files=all)" ]] || {
    echo "source-worktree-dirty" >&2
    exit 2
  }

  local expected_submodule_count=9
  local observed_submodule_count=0
  local observed_submodule_paths=$'\n'
  local line payload hash rest path expected_hash
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "${line:0:1}" == " " ]] || { echo "submodule-state-mismatch" >&2; exit 2; }
    payload="${line:1}"
    hash="${payload%% *}"
    rest="${payload#* }"
    path="${rest%% *}"
    [[ -n "$hash" && -n "$path" ]] || { echo "submodule-status-malformed" >&2; exit 2; }
    case "$path" in
      ggml) expected_hash="c03b4e2bcece5134827881af90242086daf75be5" ;;
      llama.cpp) expected_hash="560445bf34c87356ad0f8d80fb03ec5488850b65" ;;
      proto/riva-common) expected_hash="71df98266725320a6b6b3a9f32a6da832dc93691" ;;
      third_party/cpp-httplib) expected_hash="62d899feac3cf9215a55f2b43da250fdd98d2156" ;;
      third_party/cppjieba) expected_hash="b3602bef7d1f67521a61788a74fb5801a0e62cd3" ;;
      third_party/cppjieba/deps/limonp) expected_hash="9d74077dfcdf8073536c97a00bb79d7a3c3fdaba" ;;
      third_party/flashlight-text) expected_hash="49e163ab1e7b8108922512c294ab8513b89f404c" ;;
      third_party/kenlm) expected_hash="4cb443e60b7bf2c0ddf3c745378f76cb59e254e5" ;;
      third_party/open_jtalk) expected_hash="1e52154e6677d02dcb4b7f15453e65b5ca1cb6aa" ;;
      *) echo "submodule-inventory-mismatch" >&2; exit 2 ;;
    esac
    [[ "$observed_submodule_paths" != *$'\n'"$path"$'\n'* ]] || {
      echo "submodule-duplicate" >&2
      exit 2
    }
    [[ "$hash" == "$expected_hash" ]] || { echo "submodule-commit-mismatch" >&2; exit 2; }
    observed_submodule_paths="${observed_submodule_paths}${path}"$'\n'
    observed_submodule_count=$((observed_submodule_count + 1))
  done < <(git --no-optional-locks -C "$source_path" submodule status --recursive)
  [[ "$observed_submodule_count" -eq "$expected_submodule_count" ]] || {
    echo "submodule-inventory-mismatch" >&2
    exit 2
  }
}

check_anchors
verify_source_identity
pause_for_test "after-source-identity"
check_anchors

[[ -f "$source_path/include/nemo_speech/asr.h" && ! -L "$source_path/include/nemo_speech/asr.h" ]] || {
  echo "nemo-speech-asr-header-missing" >&2
  exit 2
}
[[ -f "$bridging_header" && ! -L "$bridging_header" &&
  -f "$recognizer_source" && ! -L "$recognizer_source" &&
  -f "$main_source" && ! -L "$main_source" ]] || {
  echo "native-source-missing" >&2
  exit 2
}

readonly input_root="$temporary_build_root/input"
mkdir -p "$input_root/include/nemo_speech" "$input_root/protocol" "$input_root/wave"
"$publication_tool" snapshot "$source_path/include/nemo_speech/asr.h" "$input_root/include/nemo_speech/asr.h"
"$publication_tool" snapshot "$bridging_header" "$input_root/NemoSpeechASR-Bridging-Header.h"
"$publication_tool" snapshot "$recognizer_source" "$input_root/NemotronRecognizer.swift"
"$publication_tool" snapshot "$main_source" "$input_root/main.swift"
"$publication_tool" snapshot "$model_protocol_source/CandidateAdapterModels.swift" "$input_root/protocol/CandidateAdapterModels.swift"
"$publication_tool" snapshot "$model_protocol_source/JSONLinesCodec.swift" "$input_root/protocol/JSONLinesCodec.swift"
"$publication_tool" snapshot "$wave_reader_source" "$input_root/wave/WaveReader.swift"

pause_for_test "after-build-input-snapshot"
check_anchors
verify_source_identity

readonly temporary_output_root="$temporary_build_root/output"
mkdir -p "$temporary_output_root"
swiftc \
  -target arm64-apple-macosx14.0 \
  -O \
  -parse-as-library \
  -module-name NemotronASRNativeEvaluation \
  -import-objc-header "$input_root/NemoSpeechASR-Bridging-Header.h" \
  -Xcc -I -Xcc "$input_root/include" \
  "$input_root/protocol/CandidateAdapterModels.swift" \
  "$input_root/protocol/JSONLinesCodec.swift" \
  "$input_root/wave/WaveReader.swift" \
  "$input_root/NemotronRecognizer.swift" \
  "$input_root/main.swift" \
  -o "$temporary_output_root/nemotron-native-evaluation"

pause_for_test "before-publish"
check_anchors
"$publication_tool" publish 7 "$output_parent" 8 "$output_root" 9 "$canonical_repo_root" 6 "$source_path" \
  "$temporary_output_root/nemotron-native-evaluation"
