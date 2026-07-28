import Foundation
import MCP
import MenuBarNotesCore
import Testing

@testable import MotesAgentBridge

private let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let changeID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

@Suite("MotesMCP tool registry")
struct MotesMCPToolRegistryTests {
  @Test func exposesOnlyTheApprovedToolsInOrder() {
    #expect(
      MotesMCPToolRegistry.tools.map(\.name) == [
        "list_shared_notes",
        "read_note",
        "append_text",
        "insert_text",
        "replace_lines",
        "list_tasks",
        "add_task",
        "rename_task",
        "set_task_state",
        "remove_task",
        "list_agent_activity",
        "undo_agent_change",
      ]
    )
  }

  @Test func schemasDeclareExactRequiredFieldsAndRejectUnknownFields() {
    let expectations: [(String, Set<String>, Set<String>)] = [
      ("list_shared_notes", [], []),
      ("read_note", ["note_id"], ["note_id", "start_line", "max_lines"]),
      (
        "append_text",
        ["note_id", "expected_revision", "operation_id", "text"],
        ["note_id", "expected_revision", "operation_id", "text"]
      ),
      (
        "insert_text",
        ["note_id", "expected_revision", "operation_id", "before_line", "text"],
        ["note_id", "expected_revision", "operation_id", "before_line", "text"]
      ),
      (
        "replace_lines",
        [
          "note_id", "expected_revision", "operation_id", "start_line", "end_line",
          "expected_text_sha256", "text",
        ],
        [
          "note_id", "expected_revision", "operation_id", "start_line", "end_line",
          "expected_text_sha256", "text",
        ]
      ),
      ("list_tasks", ["note_id"], ["note_id"]),
      (
        "add_task",
        ["note_id", "expected_revision", "operation_id", "text"],
        [
          "note_id", "expected_revision", "operation_id", "after_task_handle", "text",
        ]
      ),
      (
        "rename_task",
        ["note_id", "expected_revision", "operation_id", "task_handle", "text"],
        ["note_id", "expected_revision", "operation_id", "task_handle", "text"]
      ),
      (
        "set_task_state",
        [
          "note_id", "expected_revision", "operation_id", "task_handle", "completed",
        ],
        [
          "note_id", "expected_revision", "operation_id", "task_handle", "completed",
        ]
      ),
      (
        "remove_task",
        ["note_id", "expected_revision", "operation_id", "task_handle"],
        ["note_id", "expected_revision", "operation_id", "task_handle"]
      ),
      ("list_agent_activity", [], []),
      (
        "undo_agent_change",
        ["change_id", "expected_revision", "operation_id"],
        ["change_id", "expected_revision", "operation_id"]
      ),
    ]

    for (name, required, properties) in expectations {
      let schema = MotesMCPToolRegistry.tools.first { $0.name == name }!
        .inputSchema.objectValue!
      #expect(schema["type"]?.stringValue == "object")
      #expect(schema["additionalProperties"]?.boolValue == false)
      #expect(
        Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
          == required
      )
      #expect(Set(schema["properties"]!.objectValue!.keys) == properties)
    }
  }

  @Test func schemasDescribeWriteAndLineSafety() {
    let tools = Dictionary(
      uniqueKeysWithValues: MotesMCPToolRegistry.tools.map { ($0.name, $0) }
    )
    for name in [
      "append_text", "insert_text", "replace_lines", "add_task", "rename_task",
    ] {
      #expect(tools[name]?.description?.contains("65,536 UTF-8 bytes") == true)
    }
    for name in ["insert_text", "replace_lines"] {
      #expect(tools[name]?.description?.contains("one-based") == true)
    }
    for name in [
      "append_text", "insert_text", "replace_lines", "add_task", "rename_task",
      "set_task_state", "remove_task", "undo_agent_change",
    ] {
      #expect(tools[name]?.description?.contains("expected revision") == true)
      #expect(tools[name]?.description?.contains("operation ID") == true)
    }
  }

  @Test func mapsEveryToolToTheCanonicalWorkspaceCommand() throws {
    let write: [String: Value] = [
      "note_id": .string(noteID.uuidString),
      "expected_revision": .int(7),
      "operation_id": .string(operationID.uuidString),
    ]
    let cases: [(String, [String: Value], AgentWorkspaceCommand)] = [
      ("list_shared_notes", [:], .listSharedNotes),
      (
        "read_note",
        ["note_id": .string(noteID.uuidString), "start_line": 2, "max_lines": 5],
        .readNote(request: .init(noteID: noteID, startLine: 2, maxLines: 5))
      ),
      (
        "append_text",
        write.merging(["text": .string("hello")]) { _, new in new },
        .appendText(request: .init(context: context, text: "hello"))
      ),
      (
        "insert_text",
        write.merging(["before_line": .int(2), "text": .string("hello")]) {
          _, new in new
        },
        .insertText(
          request: .init(context: context, beforeLine: 2, text: "hello")
        )
      ),
      (
        "replace_lines",
        write.merging([
          "start_line": 2,
          "end_line": 3,
          "expected_text_sha256": .string(String(repeating: "a", count: 64)),
          "text": .string("hello"),
        ]) { _, new in new },
        .replaceLines(
          request: .init(
            context: context,
            startLine: 2,
            endLine: 3,
            expectedTextSHA256: String(repeating: "a", count: 64),
            text: "hello"
          )
        )
      ),
      (
        "list_tasks",
        ["note_id": .string(noteID.uuidString)],
        .listTasks(request: .init(noteID: noteID))
      ),
      (
        "add_task",
        write.merging([
          "after_task_handle": .string("handle"), "text": .string("hello"),
        ]) {
          _, new in new
        },
        .addTask(
          request: .init(
            context: context,
            afterTaskHandle: "handle",
            text: "hello"
          )
        )
      ),
      (
        "rename_task",
        write.merging([
          "task_handle": .string("handle"), "text": .string("hello"),
        ]) { _, new in new },
        .renameTask(
          request: .init(context: context, taskHandle: "handle", text: "hello")
        )
      ),
      (
        "set_task_state",
        write.merging([
          "task_handle": .string("handle"), "completed": .bool(true),
        ]) { _, new in new },
        .setTaskState(
          request: .init(context: context, taskHandle: "handle", completed: true)
        )
      ),
      (
        "remove_task",
        write.merging(["task_handle": .string("handle")]) { _, new in new },
        .removeTask(request: .init(context: context, taskHandle: "handle"))
      ),
      ("list_agent_activity", [:], .listActivity),
      (
        "undo_agent_change",
        [
          "change_id": .string(changeID.uuidString),
          "expected_revision": .int(7),
          "operation_id": .string(operationID.uuidString),
        ],
        .undoChange(
          request: .init(
            changeID: changeID,
            expectedRevision: 7,
            operationID: operationID
          )
        )
      ),
    ]

    for (name, arguments, command) in cases {
      #expect(
        try MotesMCPToolRegistry.command(name: name, arguments: arguments)
          == command
      )
    }
  }

  @Test func rejectsUnknownMissingMalformedAndOversizedInputs() {
    #expect(throws: AgentWorkspaceError.self) {
      try MotesMCPToolRegistry.command(
        name: "list_shared_notes",
        arguments: ["unknown": .bool(true)]
      )
    }
    #expect(throws: AgentWorkspaceError.self) {
      try MotesMCPToolRegistry.command(name: "read_note", arguments: [:])
    }
    #expect(throws: AgentWorkspaceError.self) {
      try MotesMCPToolRegistry.command(
        name: "insert_text",
        arguments: [
          "note_id": .string(noteID.uuidString),
          "expected_revision": .int(7),
          "operation_id": .string(operationID.uuidString),
          "before_line": .int(0),
          "text": .string("hello"),
        ]
      )
    }
    #expect(throws: AgentWorkspaceError.self) {
      try MotesMCPToolRegistry.command(
        name: "append_text",
        arguments: [
          "note_id": .string(noteID.uuidString),
          "expected_revision": .int(7),
          "operation_id": .string(operationID.uuidString),
          "text": .string(String(repeating: "é", count: 32_769)),
        ]
      )
    }
  }

  @Test func returnsReadableAndStructuredSuccessContent() throws {
    let response = AgentWorkspaceResponse.sharedNotes(notes: [])
    let result = try MotesMCPToolRegistry.result(for: response)

    #expect(result.isError == false)
    #expect(result.content.count == 2)
    #expect(result.structuredContent != nil)
  }

  @Test func workspaceErrorsRetainStableCodeAndSetIsError() throws {
    let result = try MotesMCPToolRegistry.result(
      for: AgentWorkspaceError(
        code: .revisionConflict,
        recoveryAction: "Read the note again."
      )
    )

    #expect(result.isError == true)
    #expect(result.content.count == 2)
    #expect(result.structuredContent?.description.contains("revision_conflict") == true)
  }

  private var context: AgentWriteContext {
    AgentWriteContext(
      noteID: noteID,
      expectedRevision: 7,
      operationID: operationID
    )
  }
}
