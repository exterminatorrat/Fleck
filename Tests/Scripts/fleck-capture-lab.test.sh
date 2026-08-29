#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"

cd "$repo_root"
session_output="$(
  FLECK_CAPTURE_LAB_SKIP_BUILD=1 \
    Scripts/fleck-capture-lab.sh prepare
)"
readonly session_output
manifest="$(printf '%s\n' "$session_output" | sed -n 's/^Manifest: //p')"
readonly manifest

test -f "$manifest"
session_root="$(/usr/bin/plutil -extract sessionRoot raw -o - "$manifest")"
readonly session_root
fake_repo="$(/usr/bin/plutil -extract fakeRepository raw -o - "$manifest")"
readonly fake_repo
fleck_app="$(/usr/bin/plutil -extract fleckApp raw -o - "$manifest")"
readonly fleck_app
[[ "$session_root" =~ ^/tmp/fleck-demo\.[[:alnum:]]{6}$ ]]
test "$(printf '%s\n' "$session_output" | sed -n 's/^Session: //p')" = "$session_root"
test "$(printf '%s\n' "$session_output" | sed -n 's/^Fleck app: //p')" = "$fleck_app"
test "$(printf '%s\n' "$session_output" | sed -n 's/^Fake repository: //p')" = "$fake_repo"
test -d "$session_root/Library/Application Support/Fleck"
test -f "$session_root/NorthstarDemo/Package.swift"
Scripts/fleck-capture-lab.sh verify "$manifest"

fake_bin="$session_root/TestBin"
readonly fake_bin
/bin/mkdir -p "$fake_bin"
printf '#!/bin/sh\nexit 0\n' > "$fake_bin/pgrep"
/bin/chmod 755 "$fake_bin/pgrep"
if launch_error="$(
  PATH="$fake_bin:/usr/bin:/bin" \
    Scripts/fleck-capture-lab.sh launch "$manifest" 2>&1
)"; then
  printf 'expected launch to refuse a running Fleck process\n' >&2
  exit 1
fi
readonly launch_error
test "$launch_error" = "error: Fleck is already running; leave it open and use this session later"

if profile_error="$(Scripts/fleck-capture-lab.sh codex-command "$manifest" 2>&1)"; then
  printf 'expected codex-command to require a Codex Demo profile\n' >&2
  exit 1
fi
readonly profile_error
test "$profile_error" = "error: Codex Demo profile was not found"

readonly profile_id="01234567-89AB-CDEF-0123-456789ABCDEF"
profiles_dir="$session_root/Library/Application Support/Fleck/AgentIntegrations"
readonly profiles_dir
profiles="$profiles_dir/profiles.json"
readonly profiles
/bin/mkdir -p "$profiles_dir"
printf '%s\n' \
  '[' \
  '  {' \
  '    "createdAt": 0,' \
  '    "displayName": "Codex Demo",' \
  "    \"id\": \"$profile_id\"" \
  '  }' \
  ']' > "$profiles"

installed_helper="$session_root/Library/Application Support/Fleck/AgentBridge/bin/fleck"
readonly installed_helper
/bin/mkdir -p "$(dirname -- "$installed_helper")"
/usr/bin/touch "$installed_helper"
/bin/chmod 755 "$installed_helper"

codex_output="$(Scripts/fleck-capture-lab.sh codex-command "$manifest")"
readonly codex_output
expected_codex_output="Codex command: codex -C '$fake_repo' -c 'mcp_servers.fleck.command=\"$installed_helper\"' -c 'mcp_servers.fleck.args=[\"mcp\",\"--profile\",\"$profile_id\"]' -c 'mcp_servers.fleck.env.CFFIXED_USER_HOME=\"$session_root\"'"
readonly expected_codex_output
test "$codex_output" = "$expected_codex_output"
[[ "$codex_output" != *"codex mcp add"* ]]
