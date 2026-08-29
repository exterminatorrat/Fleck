#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"

die() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

usage() {
  printf \
    'usage: %s prepare | launch <manifest> | verify <manifest> | codex-command <manifest>\n' \
    "${0##*/}" >&2
  exit 2
}

require_session_root() {
  [[ "$1" =~ ^/tmp/fleck-demo\.[[:alnum:]]{6}$ ]] \
    || die "capture sessions must use /tmp/fleck-demo.XXXXXX"
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
  [[ "$manifest" == /* && -f "$manifest" ]] || die "capture manifest was not found"

  session_root="$(/usr/bin/plutil -extract sessionRoot raw -o - "$manifest")"
  fake_repo="$(/usr/bin/plutil -extract fakeRepository raw -o - "$manifest")"
  fleck_app="$(/usr/bin/plutil -extract fleckApp raw -o - "$manifest")"
  require_session_root "$session_root"
  [[ "$manifest" == "$session_root/fleck-capture-manifest.json" ]] \
    || die "capture manifest is outside its session"
  [[ "$fake_repo" == "$session_root/NorthstarDemo" ]] \
    || die "fake repository is outside its session"
  [[ "$fleck_app" == "$repo_root/.build/Fleck.app" ]] \
    || die "capture manifest names the wrong Fleck app"
}

find_codex_profile() {
  profiles="$session_root/Library/Application Support/Fleck/AgentIntegrations/profiles.json"
  [[ -f "$profiles" ]] || die "Codex Demo profile was not found"

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
    )" || die "Codex Demo profile data is invalid"
    if [[ "$display_name" == "Codex Demo" ]] \
      && ! /usr/bin/plutil -extract "$profile_index.revokedAt" raw -o /dev/null \
        "$profiles" 2>/dev/null; then
      candidate_id="$(
        /usr/bin/plutil -extract "$profile_index.id" raw -o - \
          "$profiles" 2>/dev/null
      )" || die "Codex Demo profile data is invalid"
      [[ "$candidate_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] \
        || die "Codex Demo profile data is invalid"
      profile_id="$candidate_id"
      profile_matches=$((profile_matches + 1))
    fi
    profile_index=$((profile_index + 1))
  done

  [[ "$profile_matches" -gt 0 ]] || die "Codex Demo profile was not found"
  [[ "$profile_matches" -eq 1 ]] || die "multiple active Codex Demo profiles were found"
}

case "${1:-}" in
  prepare)
    [[ $# -eq 1 ]] || usage
    if [[ "${FLECK_CAPTURE_LAB_SKIP_BUILD:-0}" != "1" ]]; then
      "$repo_root/Scripts/build-fleck-app.sh"
    fi
    session_root="$(/usr/bin/mktemp -d /tmp/fleck-demo.XXXXXX)"
    require_session_root "$session_root"
    resolve_capture_tool
    "$capture_tool" prepare --session-root "$session_root"
    ;;
  verify)
    [[ $# -eq 2 ]] || usage
    read_manifest "$2"
    resolve_capture_tool
    "$capture_tool" verify --manifest "$manifest"
    swift test --package-path "$fake_repo"
    ;;
  launch)
    [[ $# -eq 2 ]] || usage
    if pgrep -x Fleck >/dev/null 2>&1; then
      die "Fleck is already running; leave it open and use this session later"
    fi
    read_manifest "$2"
    [[ -d "$repo_root/.build/Fleck.app" ]] || die "packaged Fleck app was not found"
    /usr/bin/open -n \
      --env "CFFIXED_USER_HOME=$session_root" \
      "$repo_root/.build/Fleck.app"
    ;;
  codex-command)
    [[ $# -eq 2 ]] || usage
    read_manifest "$2"
    find_codex_profile
    installed_helper="$session_root/Library/Application Support/Fleck/AgentBridge/bin/fleck"
    [[ -x "$installed_helper" ]] || die "isolated Agent Connector was not found"
    printf \
      'Codex command: codex -C '\''%s'\'' -c '\''mcp_servers.fleck.command="%s"'\'' -c '\''mcp_servers.fleck.args=["mcp","--profile","%s"]'\'' -c '\''mcp_servers.fleck.env.CFFIXED_USER_HOME="%s"'\''\n' \
      "$fake_repo" \
      "$installed_helper" \
      "$profile_id" \
      "$session_root"
    ;;
  *)
    usage
    ;;
esac
