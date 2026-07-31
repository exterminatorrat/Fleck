# Agent Delete Lines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose an explicit revision-safe `delete_lines` MCP tool for content in shared Fleck notes.

**Architecture:** Add one MCP adapter alias that maps a validated line range to the existing `AgentWorkspaceCommand.replaceLines` command with an empty replacement. Reuse every existing authorization, revision, hash, idempotency, persistence, activity, rich-text, and Undo path.

**Tech Stack:** Swift 6, Swift Testing, SwiftPM, Model Context Protocol Swift SDK

## Global Constraints

- Delete only one-based inclusive line ranges in notes explicitly shared with the calling integration.
- Require `note_id`, `expected_revision`, `operation_id`, `start_line`, `end_line`, and `expected_text_sha256`.
- Do not add a second mutation engine or change the wire protocol.
- Do not allow note, Trash, settings, history, or file deletion.
- Preserve the macOS 14 deployment target and add no dependency.

---

### Task 1: Explicit MCP Line Deletion

**Files:**
- Modify: `Tests/FleckAgentBridgeTests/FleckMCPToolRegistryTests.swift`
- Modify: `Sources/FleckAgentBridge/FleckMCPToolRegistry.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AgentWorkspaceCommand.replaceLines(request:)`
- Produces: MCP tool `delete_lines(note_id, expected_revision, operation_id, start_line, end_line, expected_text_sha256)`

- [ ] **Step 1: Write the failing registry test**

Add a focused test that requires the new schema and maps it to an empty
replacement:

```swift
@Test func deleteLinesUsesExistingSafeReplacementCommand() throws {
  let tool = try #require(
    FleckMCPToolRegistry.tools.first { $0.name == "delete_lines" }
  )
  let schema = try #require(tool.inputSchema.objectValue)
  #expect(
    Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
      == [
        "note_id", "expected_revision", "operation_id", "start_line",
        "end_line", "expected_text_sha256",
      ]
  )

  let operationID = UUID()
  let command = try FleckMCPToolRegistry.command(
    name: "delete_lines",
    arguments: [
      "note_id": .string(noteID.uuidString),
      "expected_revision": .int(7),
      "operation_id": .string(operationID.uuidString),
      "start_line": .int(2),
      "end_line": .int(4),
      "expected_text_sha256": .string(
        "df5bec8f75db4b6d25c5f32b904fb8d0faca846071d8d4a8df7341d591ae5a9b"
      ),
    ]
  )

  #expect(
    command == .replaceLines(
      request: .init(
        context: .init(
          noteID: noteID,
          expectedRevision: 7,
          operationID: operationID
        ),
        startLine: 2,
        endLine: 4,
        expectedTextSHA256:
          "df5bec8f75db4b6d25c5f32b904fb8d0faca846071d8d4a8df7341d591ae5a9b",
        text: ""
      )
    )
  )
}
```

Also add `delete_lines` to the existing exact tool-name, schema, and write
safety expectations.

- [ ] **Step 2: Run the focused test and observe RED**

Run:

```bash
swift test --filter FleckMCPToolRegistryTests
```

Expected: FAIL because `delete_lines` is absent.

- [ ] **Step 3: Add the minimal MCP schema and mapping**

In `FleckMCPToolRegistry.tools`, add:

```swift
tool(
  "delete_lines",
  writeDescription("Delete an inclusive one-based line range."),
  properties: writeProperties([
    "start_line": positiveInteger("First one-based line to delete."),
    "end_line": positiveInteger("Last one-based line to delete, inclusive."),
    "expected_text_sha256": string(
      "SHA-256 of the observed line range as 64 lowercase hexadecimal characters."
    ),
  ]),
  required: writeRequired
    + ["start_line", "end_line", "expected_text_sha256"]
)
```

In `command(for:)`, validate the range and hash exactly like `replace_lines`,
then return:

```swift
.replaceLines(
  request: .init(
    context: context,
    startLine: startLine,
    endLine: endLine,
    expectedTextSHA256: hash,
    text: ""
  )
)
```

Do not change `AgentWorkspaceCommand`, the mutation engine, persistence, or
activity storage.

- [ ] **Step 4: Document the explicit tool**

Add `delete_lines` beside `replace_lines` in the README MCP tool list. Explain
that it deletes verified line ranges and remains revision-protected and
undoable.

- [ ] **Step 5: Run focused and full verification**

Run:

```bash
swift test --filter FleckMCPToolRegistryTests
swift test
swift build -c release
git diff --check
```

Expected: all tests and the release build pass with no whitespace errors.

- [ ] **Step 6: Commit when Git metadata is writable**

```bash
git add \
  Sources/FleckAgentBridge/FleckMCPToolRegistry.swift \
  Tests/FleckAgentBridgeTests/FleckMCPToolRegistryTests.swift \
  README.md \
  docs/superpowers/specs/2026-07-30-agent-delete-lines-design.md \
  docs/superpowers/plans/2026-07-30-agent-delete-lines.md
git commit -m "feat: let agents delete verified note lines"
```

After installing the rebuilt helper, start a new Codex task so it discovers the
updated MCP tool schema.
