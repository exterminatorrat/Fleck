#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"

expect_error() {
  local expected="$1"
  shift
  local actual
  if actual="$("$@" 2>&1)"; then
    printf 'expected command to fail: %s\n' "$*" >&2
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected error: %s\nactual error: %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

assert_rejects_fixture_symlink() {
  local operation="$1"
  local fixture_path="$2"
  local sentinel_target="$3"
  local label="$4"
  local holding_path="$symlink_sentinel_root/original-$label"
  local rejected_link="$symlink_sentinel_root/rejected-$label"

  /bin/mv "$fixture_path" "$holding_path"
  /bin/ln -s "$sentinel_target" "$fixture_path"
  if [[ "$operation" == "launch" ]]; then
    expect_error \
      "$symlink_error" \
      /usr/bin/env \
        PATH="$fake_bin:/usr/bin:/bin" \
        FLECK_CAPTURE_LAB_PGREP_SENTINEL="$pgrep_sentinel" \
        Scripts/fleck-capture-lab.sh launch "$manifest"
    test ! -e "$pgrep_sentinel"
  else
    expect_error \
      "$symlink_error" \
      Scripts/fleck-capture-lab.sh "$operation" "$manifest"
  fi
  /bin/mv "$fixture_path" "$rejected_link"
  /bin/mv "$holding_path" "$fixture_path"
}

cd "$repo_root"
canonical_session_parent="$repo_root/.build/fleck-capture-lab"
readonly canonical_session_parent

packager_test_root="$(/usr/bin/mktemp -d /tmp/fleck-packager-test.XXXXXX)"
readonly packager_test_root
packager_test_scripts="$packager_test_root/Scripts"
readonly packager_test_scripts
packager_test_bin="$packager_test_root/bin"
readonly packager_test_bin
/bin/mkdir -p "$packager_test_scripts" "$packager_test_bin"
/bin/cp Scripts/fleck-capture-lab.sh "$packager_test_scripts/fleck-capture-lab.sh"

enhanced_packager_sentinel="$packager_test_root/enhanced-packager-called"
readonly enhanced_packager_sentinel
lightweight_packager_sentinel="$packager_test_root/lightweight-packager-called"
readonly lightweight_packager_sentinel
printf '%s\n' \
  '#!/bin/sh' \
  '/usr/bin/touch "$FLECK_CAPTURE_LAB_ENHANCED_PACKAGER_SENTINEL"' \
  > "$packager_test_scripts/build-parakeet-test-app.sh"
printf '%s\n' \
  '#!/bin/sh' \
  '/usr/bin/touch "$FLECK_CAPTURE_LAB_LIGHTWEIGHT_PACKAGER_SENTINEL"' \
  > "$packager_test_scripts/build-fleck-app.sh"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "${1:-}" = "build" ] && [ "${2:-}" = "--show-bin-path" ]; then' \
  '  printf "%s\n" "$FLECK_CAPTURE_LAB_FAKE_BIN_PATH"' \
  'fi' \
  > "$packager_test_bin/swift"
printf '%s\n' \
  '#!/bin/sh' \
  'test "$1" = "prepare"' \
  'test "$2" = "--session-root"' \
  > "$packager_test_bin/fleck-capture-lab"
/bin/chmod 755 \
  "$packager_test_scripts/fleck-capture-lab.sh" \
  "$packager_test_scripts/build-parakeet-test-app.sh" \
  "$packager_test_scripts/build-fleck-app.sh" \
  "$packager_test_bin/swift" \
  "$packager_test_bin/fleck-capture-lab"

PATH="$packager_test_bin:/usr/bin:/bin" \
  FLECK_CAPTURE_LAB_SKIP_BUILD=0 \
  FLECK_CAPTURE_LAB_ENHANCED_PACKAGER_SENTINEL="$enhanced_packager_sentinel" \
  FLECK_CAPTURE_LAB_LIGHTWEIGHT_PACKAGER_SENTINEL="$lightweight_packager_sentinel" \
  FLECK_CAPTURE_LAB_FAKE_BIN_PATH="$packager_test_bin" \
  "$packager_test_scripts/fleck-capture-lab.sh" prepare >/dev/null
if [[ ! -e "$enhanced_packager_sentinel" ]]; then
  printf 'expected default prepare to invoke build-parakeet-test-app.sh\n' >&2
  exit 1
fi
if [[ -e "$lightweight_packager_sentinel" ]]; then
  printf 'default prepare invoked build-fleck-app.sh\n' >&2
  exit 1
fi

prebuild_test_root="$(/usr/bin/mktemp -d /tmp/fleck-prebuild-test.XXXXXX)"
prebuild_test_root="$(cd -- "$prebuild_test_root" && pwd -P)"
readonly prebuild_test_root
/bin/mkdir -p "$prebuild_test_root/Scripts"
/bin/cp Scripts/fleck-capture-lab.sh "$prebuild_test_root/Scripts/fleck-capture-lab.sh"
/bin/cp \
  "$packager_test_scripts/build-parakeet-test-app.sh" \
  "$prebuild_test_root/Scripts/build-parakeet-test-app.sh"
/bin/chmod 755 \
  "$prebuild_test_root/Scripts/fleck-capture-lab.sh" \
  "$prebuild_test_root/Scripts/build-parakeet-test-app.sh"
prebuild_external_root="$packager_test_root/prebuild-external-root"
readonly prebuild_external_root
/bin/mkdir -p "$prebuild_external_root"
/bin/ln -s "$prebuild_external_root" "$prebuild_test_root/.build"
prebuild_packager_sentinel="$packager_test_root/prebuild-packager-called"
readonly prebuild_packager_sentinel
expect_error \
  "error: capture session parent must be a canonical non-symlink directory" \
  /usr/bin/env \
    PATH="$packager_test_bin:/usr/bin:/bin" \
    FLECK_CAPTURE_LAB_SKIP_BUILD=0 \
    FLECK_CAPTURE_LAB_ENHANCED_PACKAGER_SENTINEL="$prebuild_packager_sentinel" \
    FLECK_CAPTURE_LAB_FAKE_BIN_PATH="$packager_test_bin" \
    "$prebuild_test_root/Scripts/fleck-capture-lab.sh" prepare
if [[ -e "$prebuild_packager_sentinel" ]]; then
  printf 'enhanced packager ran before redirected build root was rejected\n' >&2
  exit 1
fi

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
fleck_root="$session_root/Library/Application Support/Fleck"
readonly fleck_root
actual_session_parent="${session_root%/*}"
if [[ "$actual_session_parent" != "$canonical_session_parent" ]]; then
  printf 'expected skip-build prepare session parent: %s\nactual session parent: %s\n' \
    "$canonical_session_parent" \
    "$actual_session_parent" >&2
  exit 1
fi
[[ "${session_root##*/}" =~ ^fleck-demo\.[[:alnum:]]{6}$ ]]
test ! -L "$repo_root/.build"
test ! -L "$canonical_session_parent"
test ! -L "$session_root"
test "$(cd -- "$canonical_session_parent" && pwd -P)" = "$canonical_session_parent"
test "$(cd -- "$session_root" && pwd -P)" = "$session_root"
test "$(printf '%s\n' "$session_output" | sed -n 's/^Session: //p')" = "$session_root"
test "$(printf '%s\n' "$session_output" | sed -n 's/^Fleck app: //p')" = "$fleck_app"
test "$(printf '%s\n' "$session_output" | sed -n 's/^Fake repository: //p')" = "$fake_repo"
test -d "$session_root/Library/Application Support/Fleck"
test -f "$session_root/NorthstarDemo/Package.swift"
test -z "$(/usr/bin/git -C "$fake_repo" status --porcelain)"

parent_link_test_root="$(/usr/bin/mktemp -d /tmp/fleck-parent-link-test.XXXXXX)"
readonly parent_link_test_root
/bin/mkdir -p "$parent_link_test_root/Scripts" "$parent_link_test_root/.build"
/bin/cp Scripts/fleck-capture-lab.sh "$parent_link_test_root/Scripts/fleck-capture-lab.sh"
/bin/chmod 755 "$parent_link_test_root/Scripts/fleck-capture-lab.sh"
external_session_parent="$packager_test_root/external-session-parent"
readonly external_session_parent
/bin/mkdir -p "$external_session_parent"
/bin/ln -s "$external_session_parent" "$parent_link_test_root/.build/fleck-capture-lab"
expect_error \
  "error: capture session parent must be a canonical non-symlink directory" \
  /usr/bin/env \
    PATH="$packager_test_bin:/usr/bin:/bin" \
    FLECK_CAPTURE_LAB_SKIP_BUILD=1 \
    FLECK_CAPTURE_LAB_FAKE_BIN_PATH="$packager_test_bin" \
    "$parent_link_test_root/Scripts/fleck-capture-lab.sh" prepare

Scripts/fleck-capture-lab.sh verify "$manifest"
test -z "$(/usr/bin/git -C "$fake_repo" status --porcelain)"
test -d "$session_root/SwiftPMBuild/NorthstarDemo"

readonly symlink_error="error: capture session paths must not be symlinks"
symlink_sentinel_root="$(/usr/bin/mktemp -d /tmp/fleck-symlink-sentinel.XXXXXX)"
readonly symlink_sentinel_root
sentinel_file="$symlink_sentinel_root/external-file"
readonly sentinel_file
sentinel_directory="$symlink_sentinel_root/external-directory"
readonly sentinel_directory
printf 'external sentinel\n' > "$sentinel_file"
/bin/mkdir -p "$sentinel_directory"
printf 'external directory sentinel\n' > "$sentinel_directory/sentinel"

assert_rejects_fixture_symlink verify \
  "$fleck_root/11111111-1111-4111-8111-111111111111.md" \
  "$sentinel_file" \
  "fleck-note"
assert_rejects_fixture_symlink verify \
  "$fake_repo/Package.swift" \
  "$sentinel_file" \
  "northstar-package"
assert_rejects_fixture_symlink verify \
  "$fake_repo/Sources" \
  "$sentinel_directory" \
  "northstar-sources"
assert_rejects_fixture_symlink verify \
  "$fake_repo/Tests" \
  "$sentinel_directory" \
  "northstar-tests"
assert_rejects_fixture_symlink verify \
  "$fake_repo/README.md" \
  "$sentinel_file" \
  "northstar-readme"
assert_rejects_fixture_symlink verify \
  "$fake_repo/.git" \
  "$sentinel_directory" \
  "northstar-git"
test "$(<"$sentinel_file")" = "external sentinel"
test "$(<"$sentinel_directory/sentinel")" = "external directory sentinel"
test -z "$(/usr/bin/git -C "$fake_repo" status --porcelain)"

fake_bin="$session_root/TestBin"
readonly fake_bin
/bin/mkdir -p "$fake_bin"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ -n "${FLECK_CAPTURE_LAB_PGREP_SENTINEL:-}" ]; then' \
  '  /usr/bin/touch "$FLECK_CAPTURE_LAB_PGREP_SENTINEL"' \
  'fi' \
  'exit 0' > "$fake_bin/pgrep"
/bin/chmod 755 "$fake_bin/pgrep"
pgrep_sentinel="$symlink_sentinel_root/pgrep-called"
readonly pgrep_sentinel
if ! /usr/bin/grep -Fq \
  'if /usr/bin/pgrep -x Fleck >/dev/null 2>&1; then' \
  Scripts/fleck-capture-lab.sh; then
  printf 'expected launch guard to use /usr/bin/pgrep\n' >&2
  exit 1
fi

app_link_test_root="$(/usr/bin/mktemp -d /tmp/fleck-app-link-test.XXXXXX)"
app_link_test_root="$(cd -- "$app_link_test_root" && pwd -P)"
readonly app_link_test_root
/bin/mkdir -p "$app_link_test_root/Scripts"
/bin/cp Scripts/fleck-capture-lab.sh "$app_link_test_root/Scripts/fleck-capture-lab.sh"
/bin/chmod 755 "$app_link_test_root/Scripts/fleck-capture-lab.sh"
app_link_session_root="$app_link_test_root/.build/fleck-capture-lab/fleck-demo.ABC123"
readonly app_link_session_root
app_link_fleck_root="$app_link_session_root/Library/Application Support/Fleck"
readonly app_link_fleck_root
app_link_fake_repo="$app_link_session_root/NorthstarDemo"
readonly app_link_fake_repo
app_link_fleck_app="$app_link_test_root/.build/parakeet-test/Fleck.app"
readonly app_link_fleck_app
app_link_manifest="$app_link_session_root/fleck-capture-manifest.json"
readonly app_link_manifest
/bin/mkdir -p "$app_link_fleck_root" "$app_link_fake_repo"
printf '%s\n' \
  '{' \
  '  "captureCommands" : {' \
  '    "agentPrompt" : "Pick up where I left off.",' \
  '    "approval" : "Do it.",' \
  '    "dictation" : "Northstar Demo: move the location permission request until after onboarding."' \
  '  },' \
  "  \"fakeRepository\" : \"$app_link_fake_repo\"," \
  "  \"fleckApp\" : \"$app_link_fleck_app\"," \
  "  \"fleckRoot\" : \"$app_link_fleck_root\"," \
  '  "projectNames" : [' \
  '    "Northstar Demo",' \
  '    "Relay Demo",' \
  '    "Canvas Demo"' \
  '  ],' \
  "  \"sessionRoot\" : \"$app_link_session_root\"" \
  '}' > "$app_link_manifest"

app_link_external_root="$symlink_sentinel_root/app-link-external"
readonly app_link_external_root
/bin/mkdir -p "$app_link_external_root/Fleck.app/Contents"
/bin/ln -s "$app_link_external_root" "$app_link_test_root/.build/parakeet-test"
readonly app_tree_error="error: packaged Fleck app must be a canonical non-symlink tree"
expect_error \
  "$app_tree_error" \
  /usr/bin/env PATH="$fake_bin:/usr/bin:/bin" \
    FLECK_CAPTURE_LAB_PGREP_SENTINEL="$pgrep_sentinel" \
    "$app_link_test_root/Scripts/fleck-capture-lab.sh" launch "$app_link_manifest"
test ! -e "$pgrep_sentinel"

/bin/mv "$app_link_test_root/.build/parakeet-test" "$app_link_external_root/parent-link"
/bin/mkdir -p "$app_link_test_root/.build/parakeet-test"
/bin/ln -s "$app_link_external_root/Fleck.app" "$app_link_fleck_app"
expect_error \
  "$app_tree_error" \
  /usr/bin/env PATH="$fake_bin:/usr/bin:/bin" \
    FLECK_CAPTURE_LAB_PGREP_SENTINEL="$pgrep_sentinel" \
    "$app_link_test_root/Scripts/fleck-capture-lab.sh" launch "$app_link_manifest"
test ! -e "$pgrep_sentinel"

/bin/mv "$app_link_fleck_app" "$app_link_external_root/app-link"
/bin/mkdir -p "$app_link_fleck_app/Contents"
/bin/ln -s "$sentinel_file" "$app_link_fleck_app/Contents/redirected-resource"
expect_error \
  "$app_tree_error" \
  /usr/bin/env PATH="$fake_bin:/usr/bin:/bin" \
    FLECK_CAPTURE_LAB_PGREP_SENTINEL="$pgrep_sentinel" \
    "$app_link_test_root/Scripts/fleck-capture-lab.sh" launch "$app_link_manifest"
test ! -e "$pgrep_sentinel"

assert_rejects_fixture_symlink launch \
  "$fleck_root/workspace.json" \
  "$sentinel_file" \
  "launch-nested-fleck"
assert_rejects_fixture_symlink launch \
  "$fake_repo/README.md" \
  "$sentinel_file" \
  "launch-nested-northstar"

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

assert_rejects_fixture_symlink codex-command \
  "$fleck_root/workspace.json" \
  "$sentinel_file" \
  "codex-nested-fleck"
assert_rejects_fixture_symlink codex-command \
  "$fake_repo/README.md" \
  "$sentinel_file" \
  "codex-nested-northstar"

external_integrations="$symlink_sentinel_root/ExternalAgentIntegrations"
readonly external_integrations
/bin/mkdir -p "$external_integrations"
printf 'external profile sentinel\n' > "$external_integrations/profiles.json"
external_bridge="$symlink_sentinel_root/ExternalAgentBridge"
readonly external_bridge
/bin/mkdir -p "$external_bridge/bin"
printf '#!/bin/sh\nexit 0\n' > "$external_bridge/bin/fleck"
/bin/chmod 755 "$external_bridge/bin/fleck"

test ! -L "$session_root/Library"
test ! -L "$session_root/Library/Application Support"
test ! -L "$fleck_root"
assert_rejects_fixture_symlink codex-command \
  "$profiles_dir" \
  "$external_integrations" \
  "codex-agent-integrations"
assert_rejects_fixture_symlink codex-command \
  "$profiles" \
  "$external_integrations/profiles.json" \
  "codex-profiles"
assert_rejects_fixture_symlink codex-command \
  "$fleck_root/AgentBridge" \
  "$external_bridge" \
  "codex-agent-bridge"
assert_rejects_fixture_symlink codex-command \
  "$(dirname -- "$installed_helper")" \
  "$external_bridge/bin" \
  "codex-agent-bridge-bin"
assert_rejects_fixture_symlink codex-command \
  "$installed_helper" \
  "$external_bridge/bin/fleck" \
  "codex-helper"

readonly exact_path_error="error: capture manifest path must use $canonical_session_parent/fleck-demo.XXXXXX/fleck-capture-manifest.json"
expect_error \
  "$exact_path_error" \
  Scripts/fleck-capture-lab.sh verify "$session_root/./fleck-capture-manifest.json"

legacy_session_root="$(/usr/bin/mktemp -d /tmp/fleck-demo.XXXXXX)"
readonly legacy_session_root
expect_error \
  "$exact_path_error" \
  Scripts/fleck-capture-lab.sh verify "$legacy_session_root/fleck-capture-manifest.json"

manifest_link_root="$(/usr/bin/mktemp -d "$canonical_session_parent/fleck-demo.XXXXXX")"
readonly manifest_link_root
/bin/ln -s "$manifest" "$manifest_link_root/fleck-capture-manifest.json"
expect_error \
  "$symlink_error" \
  Scripts/fleck-capture-lab.sh verify "$manifest_link_root/fleck-capture-manifest.json"

session_link="$(/usr/bin/mktemp -d "$canonical_session_parent/fleck-demo.XXXXXX")"
readonly session_link
session_link_holding="$(/usr/bin/mktemp -d /tmp/fleck-redirection.XXXXXX)"
readonly session_link_holding
/bin/mv "$session_link" "$session_link_holding/unused-session"
/bin/ln -s "$session_root" "$session_link"
expect_error \
  "$symlink_error" \
  Scripts/fleck-capture-lab.sh verify "$session_link/fleck-capture-manifest.json"

fleck_redirect="$(/usr/bin/mktemp -d /tmp/fleck-redirection.XXXXXX)"
readonly fleck_redirect
/bin/mv "$fleck_root" "$fleck_redirect/Fleck"
/bin/ln -s "$fleck_redirect/Fleck" "$fleck_root"
expect_error \
  "$symlink_error" \
  /usr/bin/env PATH="$fake_bin:/usr/bin:/bin" \
    Scripts/fleck-capture-lab.sh launch "$manifest"
expect_error \
  "$symlink_error" \
  Scripts/fleck-capture-lab.sh codex-command "$manifest"
