#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly helper_root="$repo_root/Sources/MotesAgentBridge"
readonly launch_adapter="$helper_root/AgentIPCClient.swift"
readonly mcp_server="$helper_root/MotesMCPServer.swift"
readonly tool_registry="$helper_root/MotesMCPToolRegistry.swift"
readonly client_setup="$repo_root/Sources/MenuBarNotesApp/AgentClientSetup.swift"
readonly installer="$repo_root/Sources/MenuBarNotesApp/AgentBridgeInstaller.swift"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: audit-agent-boundary requires rg\n' >&2
  exit 2
fi

fail_matches() {
  local boundary="$1"
  local pattern="$2"
  shift 2
  local matches
  if matches="$(rg -n --glob '*.swift' "$pattern" "$@" 2>/dev/null)"; then
    printf 'error: %s\n%s\n' "$boundary" "$matches" >&2
    exit 1
  fi
}

# AppKit is permitted only in AgentIPCClient's non-activating launch adapter.
helper_without_launch=()
while IFS= read -r file; do
  if [[ "$file" != "$launch_adapter" ]]; then
    helper_without_launch+=("$file")
  fi
done < <(find "$helper_root" -maxdepth 1 -name '*.swift' -type f | sort)
fail_matches \
  'MotesAgentBridge imports AppKit outside the launch adapter' \
  '^[[:space:]]*(import|@_implementationOnly[[:space:]]+import)[[:space:]]+AppKit([[:space:]]|$)' \
  "${helper_without_launch[@]}"
if [[ "$(rg -c '^[[:space:]]*import[[:space:]]+AppKit$' "$launch_adapter")" != "1" ]]; then
  printf 'error: launch adapter must contain exactly one AppKit import\n' >&2
  exit 1
fi
launch_stripped="$(mktemp "${TMPDIR:-/tmp}/motes-launch-audit.XXXXXX")"
cleanup() {
  /bin/rm -f -- "$launch_stripped" "${expected_tools:-}" "${actual_tools:-}"
}
trap cleanup EXIT
awk '
  /private static func launchMotes\(\) throws/ { inside = 1 }
  {
    if (!inside) print
    if (inside) {
      line = $0
      opens = gsub(/\{/, "{", line)
      closes = gsub(/\}/, "}", line)
      depth += opens - closes
      if (opens > 0 && depth == 0) inside = 0
    }
  }
' "$launch_adapter" >"$launch_stripped"
fail_matches \
  'AppKit symbols occur outside AgentIPCClient.launchMotes' \
  '\bNS(Application|RunningApplication|Workspace|WorkspaceOpenConfiguration)\b' \
  "$launch_stripped"

# The helper may connect to the private AF_UNIX socket, but must not open an
# HTTP service, TCP socket, network listener, or URL-loading session.
fail_matches \
  'helper contains an HTTP/TCP/network-listener API' \
  '(^[[:space:]]*import[[:space:]]+Network([[:space:]]|$)|\b(NWListener|URLSession|URLRequest|HTTPURLResponse|AF_INET6?|PF_INET6?|IPPROTO_TCP)\b|https?://|localhost|127\.0\.0\.1|0\.0\.0\.0|[[:space:]](bind|listen|accept)[[:space:]]*\()' \
  "$helper_root"

# The helper receives typed values over IPC; it must never discover or edit
# Motes note, workspace, Trash, or Dictation History storage paths directly.
fail_matches \
  'helper references a forbidden Motes storage path' \
  '"[^"]*(\.md|\.rtf|workspace\.json|Dictation[[:space:]]*History)[^"]*"|"Trash"' \
  "$helper_root"

# The MCP surface is the approved twelve tools, in the reviewed order.
expected_tools="$(mktemp "${TMPDIR:-/tmp}/motes-tools-expected.XXXXXX")"
actual_tools="$(mktemp "${TMPDIR:-/tmp}/motes-tools-actual.XXXXXX")"
printf '%s\n' \
  list_shared_notes \
  read_note \
  append_text \
  insert_text \
  replace_lines \
  list_tasks \
  add_task \
  rename_task \
  set_task_state \
  remove_task \
  list_agent_activity \
  undo_agent_change >"$expected_tools"
awk '
  /^[[:space:]]+tool\($/ {
    if (getline > 0 && match($0, /"[^"]+"/)) {
      print substr($0, RSTART + 1, RLENGTH - 2)
    }
  }
' "$tool_registry" >"$actual_tools"
if ! diff -u "$expected_tools" "$actual_tools"; then
  printf 'error: MCP tool registry differs from the approved twelve\n' >&2
  exit 1
fi

# MCP advertises and handles tools only. Roots are client capabilities; no
# resources, prompts, logging, completions, sampling, or elicitation handler is
# registered by this server.
if [[ "$(rg -c 'capabilities: \.init\(tools: \.init\(listChanged: false\)\)' "$mcp_server")" != "1" ]]; then
  printf 'error: MCP server must advertise exactly the reviewed tools capability\n' >&2
  exit 1
fi
handlers="$(
  rg -o 'withMethodHandler\([A-Za-z]+\.self' "$mcp_server" \
    | sed -E 's/.*\(([A-Za-z]+)\.self/\1/' \
    | sort
)"
if [[ "$handlers" != $'CallTool\nListTools' ]]; then
  printf 'error: MCP server registers a non-tool handler\n%s\n' "$handlers" >&2
  exit 1
fi
fail_matches \
  'MCP server references a forbidden non-tool protocol surface' \
  '\b(List|Get|Subscribe)(Resources|ResourceTemplates|Prompts|Roots|Completions)\b|\b(CreateMessage|Elicit)\b' \
  "$mcp_server"

# stdout is the MCP protocol channel. MCP runtime files and the `.mcp` command
# branch must not write production diagnostics or prose to it.
fail_matches \
  'MCP runtime writes non-protocol output to stdout' \
  'FileHandle\.standardOutput|\.standardOutput|(^|[^A-Za-z])print[[:space:]]*\(' \
  "$mcp_server" "$tool_registry" \
  "$helper_root/AgentIPCClient.swift" "$helper_root/BridgeCredentialStore.swift"
mcp_branch="$(
  awk '
    /case \.mcp\(let profileID\):/ { inside = 1 }
    inside && /case \.workspace\(/ { exit }
    inside { print }
  ' "$helper_root/MotesAgentBridge.swift"
)"
if rg -n '\.standardOutput|(^|[^A-Za-z])print[[:space:]]*\(' \
  <<<"$mcp_branch" >/dev/null; then
  printf 'error: MCP command branch writes production output to stdout\n' >&2
  exit 1
fi

# Generated client setup snippets identify only the helper and profile. The
# one-time credential must remain on stdin/Keychain and never enter snippets.
fail_matches \
  'generated client setup contains a credential-bearing field' \
  '\b(token|credential|secret|canonicalBase64)\b' \
  "$client_setup"
setup_snippet="$(
  awk '
    /func setupSnippet\(profileID: UUID\)/ { inside = 1 }
    inside { print }
    inside && /^[[:space:]]{4}\}/ { exit }
  ' "$installer"
)"
if rg -ni '\b(token|credential|secret|base64)\b' \
  <<<"$setup_snippet" >/dev/null; then
  printf 'error: helper setup snippet contains credential material\n' >&2
  exit 1
fi

printf 'Agent boundary audit passed: local IPC, 12 MCP tools, no storage-path fallback.\n'
