#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"
readonly helper_root="$repo_root/Sources/FleckAgentBridge"
readonly launch_adapter="$helper_root/AgentIPCClient.swift"
readonly mcp_server="$helper_root/FleckMCPServer.swift"
readonly tool_registry="$helper_root/FleckMCPToolRegistry.swift"
readonly cli_entrypoint="$helper_root/FleckAgentBridge.swift"
readonly client_setup="$repo_root/Sources/FleckApp/AgentClientSetup.swift"
readonly installer="$repo_root/Sources/FleckApp/AgentBridgeInstaller.swift"
readonly stdout_pattern='FileHandle\.standardOutput|\.standardOutput|\bSTDOUT_FILENO\b|\bstdout\b|(^|[^A-Za-z])print[[:space:]]*\(|(Darwin\.)?write[[:space:]]*\([[:space:]]*1[[:space:]]*,'

for command in rg perl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'error: audit-agent-boundary requires %s\n' "$command" >&2
    exit 2
  fi
done

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
done < <(find "$helper_root" -name '*.swift' -type f | sort)
fail_matches \
  'FleckAgentBridge imports AppKit outside the launch adapter' \
  '^[[:space:]]*(import|@_implementationOnly[[:space:]]+import)[[:space:]]+AppKit([[:space:]]|$)' \
  "${helper_without_launch[@]}"
if [[ "$(rg -c '^[[:space:]]*import[[:space:]]+AppKit$' "$launch_adapter")" != "1" ]]; then
  printf 'error: launch adapter must contain exactly one AppKit import\n' >&2
  exit 1
fi
launch_stripped="$(mktemp "${TMPDIR:-/tmp}/fleck-launch-audit.XXXXXX")"
tool_parser_probe="$(mktemp "${TMPDIR:-/tmp}/fleck-tool-parser-probe.XXXXXX")"
stdout_probe="$(mktemp "${TMPDIR:-/tmp}/fleck-stdout-probe.XXXXXX")"
cleanup() {
  /bin/rm -f -- \
    "$launch_stripped" "$tool_parser_probe" "$stdout_probe" \
    "${expected_tools:-}" "${actual_tools:-}"
}
trap cleanup EXIT
awk '
  /private static func launchFleck\(\) throws/ { inside = 1 }
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
  'AppKit symbols occur outside AgentIPCClient.launchFleck' \
  '\bNS(Application|RunningApplication|Workspace|WorkspaceOpenConfiguration)\b' \
  "$launch_stripped"

# The helper may connect to the private AF_UNIX socket, but must not open an
# HTTP service, TCP socket, network listener, or URL-loading session.
fail_matches \
  'helper contains an HTTP/TCP/network-listener API' \
  '(^[[:space:]]*import[[:space:]]+Network([[:space:]]|$)|\b(NWListener|URLSession|URLRequest|HTTPURLResponse|AF_INET6?|PF_INET6?|IPPROTO_TCP)\b|https?://|localhost|127\.0\.0\.1|0\.0\.0\.0|[[:space:]](bind|listen|accept)[[:space:]]*\()' \
  "$helper_root"

# The helper receives typed values over IPC; it must never discover or edit
# Fleck note, workspace, Trash, or Dictation History storage paths directly.
fail_matches \
  'helper references a forbidden Fleck storage path' \
  '"[^"]*(\.md|\.rtf|workspace\.json|Dictation[[:space:]]*History)[^"]*"|"Trash"' \
  "$helper_root"

# The MCP surface is the exact approved thirteen tools, independent of whether
# registrations use one line or several.
extract_tool_names() {
  perl -0777 -ne '
    while (/\btool\s*\(\s*"([^"]+)"/g) {
      print "$1\n";
    }
  ' "$@"
}
printf '%s\n' \
  'tool("dangerous_one_line", description: "probe")' \
  'tool(' \
  '  "dangerous_multi_line",' \
  '  description: "probe"' \
  ')' >"$tool_parser_probe"
tool_parser_result="$(extract_tool_names "$tool_parser_probe" | LC_ALL=C sort)"
if [[ "$tool_parser_result" != $'dangerous_multi_line\ndangerous_one_line' ]]; then
  printf 'error: MCP tool parser self-test did not detect both registration formats\n' >&2
  exit 2
fi

expected_tools="$(mktemp "${TMPDIR:-/tmp}/fleck-tools-expected.XXXXXX")"
actual_tools="$(mktemp "${TMPDIR:-/tmp}/fleck-tools-actual.XXXXXX")"
printf '%s\n' \
  add_task \
  append_text \
  delete_lines \
  insert_text \
  list_agent_activity \
  list_shared_notes \
  list_tasks \
  read_note \
  remove_task \
  rename_task \
  replace_lines \
  set_task_state \
  undo_agent_change >"$expected_tools"
extract_tool_names "$tool_registry" | LC_ALL=C sort >"$actual_tools"
if ! diff -u "$expected_tools" "$actual_tools"; then
  printf 'error: MCP tool registry differs from the approved thirteen\n' >&2
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

# stdout is the MCP protocol channel. Only the reviewed non-MCP CLI branches in
# the entrypoint may write to it; every other helper Swift source is forbidden.
printf '%s\n' 'print("dangerous helper output")' >"$stdout_probe"
if ! rg -n "$stdout_pattern" "$stdout_probe" >/dev/null; then
  printf 'error: helper stdout self-test did not detect a print call\n' >&2
  exit 2
fi
helper_without_cli=()
while IFS= read -r file; do
  if [[ "$file" != "$cli_entrypoint" ]]; then
    helper_without_cli+=("$file")
  fi
done < <(find "$helper_root" -name '*.swift' -type f | sort)
fail_matches \
  'FleckAgentBridge Swift source outside the audited CLI entrypoint writes to stdout' \
  "$stdout_pattern" \
  "${helper_without_cli[@]}"
cli_stdout_branches="$(
  perl -ne '
    if (/case \.(help|configure|disconnect|mcp|workspace)(?:\(|:)/) {
      $branch = $1;
    }
    if (
      /FileHandle\.standardOutput|\.standardOutput|\bSTDOUT_FILENO\b|\bstdout\b/
      || /(?:^|[^A-Za-z])print\s*\(/
      || /(?:Darwin\.)?write\s*\(\s*1\s*,/
    ) {
      print(($branch // "outside"), "\n");
    }
  ' "$cli_entrypoint"
)"
if [[ "$cli_stdout_branches" != $'help\nconfigure\ndisconnect\nworkspace' ]]; then
  printf \
    'error: CLI stdout writes differ from the four audited branches\n%s\n' \
    "$cli_stdout_branches" >&2
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

printf 'Agent boundary audit passed: local IPC, 13 MCP tools, no storage-path fallback.\n'
