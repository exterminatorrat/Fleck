#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
git_common_dir="$(
  /usr/bin/git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir
)"
git_common_dir="$(cd -- "$git_common_dir" && pwd -P)"
readonly git_common_dir
common_checkout="$(cd -- "$git_common_dir/.." && pwd -P)"
readonly common_checkout
readonly common_build_root="$common_checkout/.build"
readonly session_parent="$common_build_root"
readonly product_build_root="$repo_root/.build"
readonly canonical_fleck_app="$product_build_root/parakeet-test/Fleck.app"

die() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

usage() {
  printf \
    'usage: %s prepare | launch <manifest> | verify <manifest> | postflight <manifest> | codex-command <manifest>\n' \
    "${0##*/}" >&2
  exit 2
}

is_session_root_path() {
  local root="$1"
  local leaf="${root##*/}"
  [[ "${root%/*}" == "$session_parent" \
    && "$leaf" =~ ^f\.[[:alnum:]]{6}$ ]]
}

require_common_build_root() {
  [[ -d "$common_build_root" && ! -L "$common_build_root" ]] \
    || die "capture common build root must be a canonical non-symlink directory"
  local canonical_root
  canonical_root="$(cd -- "$common_build_root" && pwd -P)"
  [[ "$canonical_root" == "$common_build_root" ]] \
    || die "capture common build root must be a canonical non-symlink directory"
  [[ "$(/usr/bin/stat -f '%u' "$common_build_root")" == "$(/usr/bin/id -u)" \
    && "$(/usr/bin/stat -f '%Lp' "$common_build_root")" == "700" ]] \
    && /usr/bin/git -C "$common_checkout" check-ignore --quiet -- .build \
    || die "capture common build root must be current-UID owned, mode 700, and ignored by Git"
}

prepare_session_parent() {
  [[ ! -L "$common_build_root" \
    && ( ! -e "$common_build_root" || -d "$common_build_root" ) ]] \
    || die "capture common build root must be a canonical non-symlink directory"
  /bin/mkdir -p -m 700 "$common_build_root"
  [[ "$(cd -- "$common_build_root" && pwd -P)" == "$common_build_root" ]] \
    || die "capture common build root must be a canonical non-symlink directory"
  [[ "$(/usr/bin/stat -f '%u' "$common_build_root")" == "$(/usr/bin/id -u)" ]] \
    && /usr/bin/git -C "$common_checkout" check-ignore --quiet -- .build \
    || die "capture common build root must be current-UID owned, mode 700, and ignored by Git"
  /bin/chmod 700 "$common_build_root"
  require_common_build_root
  require_socket_path "$session_parent/f.XXXXXX"
}

require_session_root() {
  is_session_root_path "$1" \
    || die "capture sessions must use $session_parent/f.XXXXXX"
  require_common_build_root
  reject_symlinks "$1"
  [[ -d "$1" && "$(cd -- "$1" && pwd -P)" == "$1" \
    && "$(/usr/bin/stat -f '%u' "$1")" == "$(/usr/bin/id -u)" \
    && "$(/usr/bin/stat -f '%Lp' "$1")" == "700" ]] \
    && /usr/bin/git -C "$common_checkout" check-ignore --quiet -- \
      ".build/${1##*/}" \
    || die "capture session root must be canonical, current-UID owned, mode 700, and ignored by Git"
  require_socket_path "$1"
}

require_socket_path() {
  local socket_path="$1/Library/Application Support/Fleck/AgentBridge/fleck.sock"
  local socket_path_bytes
  socket_path_bytes="$(
    /usr/bin/printf '%s' "$socket_path" | LC_ALL=C /usr/bin/wc -c | /usr/bin/tr -d ' '
  )"
  [[ "$((socket_path_bytes + 1))" -le 104 ]] \
    || die "capture session socket path exceeds the 104-byte AF_UNIX limit"
}

reject_symlinks() {
  local path
  for path in "$@"; do
    [[ ! -L "$path" ]] || die "capture session paths must not be symlinks"
  done
}

reject_tree_symlinks() {
  local root
  local symlinks
  for root in "$@"; do
    symlinks="$(/usr/bin/find -P "$root" -type l -print)"
    [[ -z "$symlinks" ]] || die "capture session paths must not be symlinks"
  done
}

require_canonical_fleck_app() {
  local app_parent="$product_build_root/parakeet-test"
  local resolved_build_root
  local resolved_app_parent
  local resolved_fleck_app
  local app_symlinks
  [[ -d "$product_build_root" && ! -L "$product_build_root" \
    && -d "$app_parent" && ! -L "$app_parent" \
    && -d "$canonical_fleck_app" && ! -L "$canonical_fleck_app" ]] \
    || die "packaged Fleck app must be a canonical non-symlink tree"
  resolved_build_root="$(cd -- "$product_build_root" && pwd -P)"
  resolved_app_parent="$(cd -- "$app_parent" && pwd -P)"
  resolved_fleck_app="$(cd -- "$canonical_fleck_app" && pwd -P)"
  [[ "$resolved_build_root" == "$product_build_root" \
    && "$resolved_app_parent" == "$app_parent" \
    && "$resolved_fleck_app" == "$canonical_fleck_app" ]] \
    || die "packaged Fleck app must be a canonical non-symlink tree"
  app_symlinks="$(/usr/bin/find -P "$canonical_fleck_app" -type l -print)" \
    || die "packaged Fleck app must be a canonical non-symlink tree"
  [[ -z "$app_symlinks" ]] \
    || die "packaged Fleck app must be a canonical non-symlink tree"
}

resolve_capture_tool() {
  cd "$repo_root"
  swift build --product fleck-capture-lab --disable-automatic-resolution
  local bin_path
  bin_path="$(swift build --show-bin-path)"
  capture_tool="$bin_path/fleck-capture-lab"
  [[ -x "$capture_tool" ]] || die "capture tool was not built"
}

read_manifest() {
  manifest="$1"
  session_root="${manifest%/fleck-capture-manifest.json}"
  [[ "$session_root" != "$manifest" ]] && is_session_root_path "$session_root" \
    || die "capture manifest path must use $session_parent/f.XXXXXX/fleck-capture-manifest.json"
  require_common_build_root
  reject_symlinks "$session_root" "$manifest"
  [[ -d "$session_root" && -f "$manifest" ]] || die "capture manifest was not found"

  manifest_session_root="$(/usr/bin/plutil -extract sessionRoot raw -o - "$manifest")"
  fleck_root="$(/usr/bin/plutil -extract fleckRoot raw -o - "$manifest")"
  fake_repo="$(/usr/bin/plutil -extract fakeRepository raw -o - "$manifest")"
  fleck_app="$(/usr/bin/plutil -extract fleckApp raw -o - "$manifest")"
  require_session_root "$session_root"
  [[ "$manifest_session_root" == "$session_root" ]] \
    || die "capture manifest is outside its session"
  [[ "$fleck_root" == "$session_root/Library/Application Support/Fleck" ]] \
    || die "Fleck data is outside its session"
  [[ "$fake_repo" == "$session_root/NorthstarDemo" ]] \
    || die "fake repository is outside its session"
  [[ "$fleck_app" == "$canonical_fleck_app" ]] \
    || die "capture manifest names the wrong Fleck app"
  reject_symlinks \
    "$session_root/Library" \
    "$session_root/Library/Application Support" \
    "$fleck_root" \
    "$fake_repo"
}

find_codex_profile() {
  profiles="$session_root/Library/Application Support/Fleck/AgentIntegrations/profiles.json"
  [[ -f "$profiles" ]] || die "Codex profile was not found"

  local profile_index=0
  local profile_matches=0
  local display_name
  local candidate_id
  profile_id=""
  while /usr/bin/plutil -extract "$profile_index" raw -o /dev/null \
    "$profiles" 2>/dev/null; do
    display_name="$(
      /usr/bin/plutil -extract "$profile_index.displayName" raw -o - \
        "$profiles" 2>/dev/null
    )" || die "Codex profile data is invalid"
    if [[ "$display_name" == "Codex" ]] \
      && ! /usr/bin/plutil -extract "$profile_index.revokedAt" raw -o /dev/null \
        "$profiles" 2>/dev/null; then
      candidate_id="$(
        /usr/bin/plutil -extract "$profile_index.id" raw -o - \
          "$profiles" 2>/dev/null
      )" || die "Codex profile data is invalid"
      [[ "$candidate_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] \
        || die "Codex profile data is invalid"
      profile_id="$candidate_id"
      profile_matches=$((profile_matches + 1))
    fi
    profile_index=$((profile_index + 1))
  done

  [[ "$profile_matches" -gt 0 ]] || die "Codex profile was not found"
  [[ "$profile_matches" -eq 1 ]] || die "multiple active Codex profiles were found"
}

test_fake_repository() {
  scratch_path="$session_root/SwiftPMBuild/NorthstarDemo"
  reject_symlinks "$session_root/SwiftPMBuild" "$scratch_path"
  swift test --package-path "$fake_repo" --scratch-path "$scratch_path"
}

case "${1:-}" in
  prepare)
    [[ $# -eq 1 ]] || usage
    prepare_session_parent
    if [[ "${FLECK_CAPTURE_LAB_SKIP_BUILD:-0}" != "1" ]]; then
      "$repo_root/Scripts/build-parakeet-test-app.sh"
    fi
    session_root="$(/usr/bin/mktemp -d "$session_parent/f.XXXXXX")"
    /bin/chmod 700 "$session_root"
    require_session_root "$session_root"
    resolve_capture_tool
    "$capture_tool" prepare --session-root "$session_root"
    ;;
  verify)
    [[ $# -eq 2 ]] || usage
    read_manifest "$2"
    reject_tree_symlinks "$fleck_root" "$fake_repo"
    resolve_capture_tool
    "$capture_tool" verify --manifest "$manifest"
    test_fake_repository
    ;;
  postflight)
    [[ $# -eq 2 ]] || usage
    read_manifest "$2"
    reject_tree_symlinks "$fleck_root" "$fake_repo"
    resolve_capture_tool
    "$capture_tool" postflight --manifest "$manifest"
    test_fake_repository
    ;;
  launch)
    [[ $# -eq 2 ]] || usage
    read_manifest "$2"
    reject_tree_symlinks "$fleck_root" "$fake_repo"
    require_canonical_fleck_app
    if /usr/bin/pgrep -x Fleck >/dev/null 2>&1; then
      die "Fleck is already running; leave it open and use this session later"
    fi
    /usr/bin/open -n \
      --env "CFFIXED_USER_HOME=$session_root" \
      "$fleck_app"
    ;;
  codex-command)
    [[ $# -eq 2 ]] || usage
    read_manifest "$2"
    reject_tree_symlinks "$fleck_root" "$fake_repo"
    profiles="$fleck_root/AgentIntegrations/profiles.json"
    installed_helper="$fleck_root/AgentBridge/bin/fleck"
    find_codex_profile
    [[ -x "$installed_helper" ]] || die "isolated Agent Connector was not found"
    printf \
      'Codex command: codex exec --ephemeral --ignore-user-config -C '\''%s'\'' -s workspace-write -a never -c '\''mcp_servers.fleck.command="%s"'\'' -c '\''mcp_servers.fleck.args=["mcp","--profile","%s"]'\'' -c '\''mcp_servers.fleck.env.CFFIXED_USER_HOME="%s"'\'' '\''Pick up where I left off.'\''\n' \
      "$fake_repo" \
      "$installed_helper" \
      "$profile_id" \
      "$session_root"
    ;;
  *)
    usage
    ;;
esac
