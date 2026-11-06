#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly audit_source="$repo_root/Scripts/audit-agent-boundary.sh"
readonly test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fleck-agent-boundary.XXXXXX")"
readonly fixture_root="$test_root/fixture"
readonly fixture_audit="$fixture_root/Scripts/audit-agent-boundary.sh"
readonly helper_root="$fixture_root/Sources/FleckAgentBridge"
readonly transport_source="$helper_root/FleckMCPBoundedStdioTransport.swift"
readonly helper_source="$helper_root/AgentIPCClient.swift"

cleanup() {
  /usr/bin/find "$test_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_rejection() {
  local label="$1"
  local expected_boundary="$2"
  local expected_violation="$3"
  local log="$test_root/$label.log"

  if bash "$fixture_audit" >"$log" 2>&1; then
    fail "audit accepted $label"
  fi
  if ! /usr/bin/grep -Fq -- "$expected_boundary" "$log" ||
    ! /usr/bin/grep -Fq -- "$expected_violation" "$log"; then
    /bin/cat "$log" >&2
    fail "audit rejected $label for an unrelated reason"
  fi
}

/bin/mkdir -p "$fixture_root/Scripts" "$fixture_root/Sources/FleckApp"
/bin/cp -p "$audit_source" "$fixture_audit"
/bin/cp -Rp "$repo_root/Sources/FleckAgentBridge" "$fixture_root/Sources/"
/bin/cp -p \
  "$repo_root/Sources/FleckApp/AgentClientSetup.swift" \
  "$repo_root/Sources/FleckApp/AgentBridgeInstaller.swift" \
  "$fixture_root/Sources/FleckApp/"

if ! bash "$fixture_audit" >"$test_root/protocol-default.log" 2>&1; then
  /bin/cat "$test_root/protocol-default.log" >&2
  fail 'audit rejected the legitimate protocol output descriptor default'
fi

/usr/bin/awk '
  index($0, "actor FleckMCPBoundedStdioTransport: Transport {") {
    print
    print "    private func stdoutLogProbe() { print(\"transport diagnostic\") }"
    next
  }
  { print }
' "$transport_source" >"$test_root/transport-log.swift"
/bin/cp -p "$test_root/transport-log.swift" "$transport_source"
expect_rejection \
  'transport-stdout-log' \
  'MCP transport stdout references differ from its default output descriptor' \
  'private func stdoutLogProbe() { print("transport diagnostic") }'

/bin/cp -p "$repo_root/Sources/FleckAgentBridge/FleckMCPBoundedStdioTransport.swift" "$transport_source"
/usr/bin/awk '
  index($0, "actor FleckMCPBoundedStdioTransport: Transport {") {
    print
    print "    private let extraOutputDescriptor = STDOUT_FILENO"
    next
  }
  { print }
' "$transport_source" >"$test_root/transport-extra-stdout.swift"
/bin/cp -p "$test_root/transport-extra-stdout.swift" "$transport_source"
expect_rejection \
  'transport-extra-stdout' \
  'MCP transport stdout references differ from its default output descriptor' \
  'private let extraOutputDescriptor = STDOUT_FILENO'

/bin/cp -p "$repo_root/Sources/FleckAgentBridge/FleckMCPBoundedStdioTransport.swift" "$transport_source"
/bin/cp -p "$repo_root/Sources/FleckAgentBridge/AgentIPCClient.swift" "$helper_source"
printf '\nprivate func auditProbeOutput() { print("unexpected helper output") }\n' >> "$helper_source"
expect_rejection \
  'ordinary-helper-stdout' \
  'FleckAgentBridge Swift source outside the audited CLI entrypoint writes to stdout' \
  'private func auditProbeOutput() { print("unexpected helper output") }'
printf '%s\n' 'Agent boundary audit regression tests passed.'
