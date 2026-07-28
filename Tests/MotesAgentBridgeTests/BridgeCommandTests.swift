import Foundation
import MenuBarNotesCore
import Testing

@testable import MotesAgentBridge

private let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
private let changeID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

@Test func everyWorkspaceCLICommandMapsToTheCoreCommand() throws {
  let cases: [([String], String, AgentWorkspaceCommand)] = [
    (
      ["notes", "list", "--profile", profileID.uuidString],
      "",
      .listSharedNotes
    ),
    (
      [
        "note", "read", noteID.uuidString,
        "--start-line", "2", "--max-lines", "5",
        "--profile", profileID.uuidString,
      ],
      "",
      .readNote(
        request: .init(noteID: noteID, startLine: 2, maxLines: 5)
      )
    ),
    (
      writeArguments(["note", "append", noteID.uuidString, "--stdin"]),
      "Appended text",
      .appendText(
        request: .init(context: context(), text: "Appended text")
      )
    ),
    (
      writeArguments([
        "note", "insert", noteID.uuidString, "3", "--stdin",
      ]),
      "Inserted text",
      .insertText(
        request: .init(
          context: context(),
          beforeLine: 3,
          text: "Inserted text"
        )
      )
    ),
    (
      writeArguments([
        "note", "replace-lines", noteID.uuidString, "2", "4",
        "--expected-text-sha256", String(repeating: "a", count: 64),
        "--stdin",
      ]),
      "Replacement",
      .replaceLines(
        request: .init(
          context: context(),
          startLine: 2,
          endLine: 4,
          expectedTextSHA256: String(repeating: "a", count: 64),
          text: "Replacement"
        )
      )
    ),
    (
      ["tasks", "list", noteID.uuidString, "--profile", profileID.uuidString],
      "",
      .listTasks(request: .init(noteID: noteID))
    ),
    (
      writeArguments([
        "task", "add", noteID.uuidString, "Add screenshots",
        "--after-task-handle", "prior-handle",
      ]),
      "",
      .addTask(
        request: .init(
          context: context(),
          afterTaskHandle: "prior-handle",
          text: "Add screenshots"
        )
      )
    ),
    (
      writeArguments([
        "task", "rename", noteID.uuidString, "task-handle",
        "Capture final screenshots",
      ]),
      "",
      .renameTask(
        request: .init(
          context: context(),
          taskHandle: "task-handle",
          text: "Capture final screenshots"
        )
      )
    ),
    (
      writeArguments([
        "task", "complete", noteID.uuidString, "task-handle",
      ]),
      "",
      .setTaskState(
        request: .init(
          context: context(),
          taskHandle: "task-handle",
          completed: true
        )
      )
    ),
    (
      writeArguments([
        "task", "reopen", noteID.uuidString, "task-handle",
      ]),
      "",
      .setTaskState(
        request: .init(
          context: context(),
          taskHandle: "task-handle",
          completed: false
        )
      )
    ),
    (
      writeArguments([
        "task", "remove", noteID.uuidString, "task-handle",
      ]),
      "",
      .removeTask(
        request: .init(context: context(), taskHandle: "task-handle")
      )
    ),
    (
      ["activity", "list", "--profile", profileID.uuidString],
      "",
      .listActivity
    ),
    (
      writeArguments(["activity", "undo", changeID.uuidString]),
      "",
      .undoChange(
        request: .init(
          changeID: changeID,
          expectedRevision: 7,
          operationID: operationID
        )
      )
    ),
  ]

  for (arguments, stdin, expected) in cases {
    let parsed = try BridgeCommand.parse(arguments: arguments) { stdin }
    #expect(parsed.profileID == profileID)
    #expect(parsed.workspaceCommand == expected)
  }
}

@Test func parserRequiresProfileAndWriteConcurrencyFields() {
  expectUsageError(["notes", "list"])
  expectUsageError([
    "note", "append", noteID.uuidString, "--profile", profileID.uuidString,
    "--operation-id", operationID.uuidString, "--stdin",
  ])
  expectUsageError([
    "note", "append", noteID.uuidString, "--profile", profileID.uuidString,
    "--revision", "7", "--stdin",
  ])
  expectUsageError([
    "activity", "undo", changeID.uuidString,
    "--profile", profileID.uuidString,
    "--revision", "7",
  ])
}

@Test func parserRejectsZeroBasedAndReversedLines() {
  expectUsageError([
    "note", "read", noteID.uuidString, "--start-line", "0",
    "--profile", profileID.uuidString,
  ])
  expectUsageError(
    writeArguments([
      "note", "insert", noteID.uuidString, "0", "--stdin",
    ]))
  expectUsageError(
    writeArguments([
      "note", "replace-lines", noteID.uuidString, "4", "2",
      "--expected-text-sha256", String(repeating: "a", count: 64),
      "--stdin",
    ]))
}

@Test func parserRejectsUnknownFlagsAndCredentialsInArgumentsWithUsageExit() {
  expectUsageError([
    "notes", "list", "--profile", profileID.uuidString, "--unknown",
  ])
  expectUsageError([
    "configure", "--profile", profileID.uuidString,
    "--token", Data(repeating: 7, count: 32).base64EncodedString(),
  ])
}

@Test func parserSupportsJSONConfigureDisconnectAndReservedMCP() throws {
  let configure = try BridgeCommand.parse(
    arguments: [
      "configure", "--profile", profileID.uuidString, "--token-stdin",
    ]
  ) { "secret-from-stdin" }
  #expect(configure == .configure(profileID: profileID))

  let disconnect = try BridgeCommand.parse(
    arguments: ["disconnect", "--profile", profileID.uuidString]
  ) { "" }
  #expect(disconnect == .disconnect(profileID: profileID))

  let mcp = try BridgeCommand.parse(
    arguments: ["mcp", "--profile", profileID.uuidString]
  ) { "" }
  #expect(mcp == .mcp(profileID: profileID))

  let json = try BridgeCommand.parse(
    arguments: [
      "notes", "list", "--profile", profileID.uuidString, "--json",
    ]
  ) { "" }
  #expect(json.usesJSON)
}

@Test func workspaceErrorsHaveStableSecretFreeJSON() throws {
  let secret = Data(repeating: 9, count: 32).base64EncodedString()
  let output = try BridgeOutput.workspaceError(
    AgentWorkspaceError(
      code: .revisionConflict,
      recoveryAction: "Reread the note."
    ),
    json: true
  )

  #expect(
    output
      == #"{"code":"revision_conflict","recoveryAction":"Reread the note."}"#
  )
  #expect(!output.contains(secret))
}

@Test func timedOutWriteMessageRetainsOnlyTheOperationID() {
  let message = BridgeOutput.writeTimedOut(operationID: operationID)
  #expect(message.contains(operationID.uuidString))
  #expect(message.contains("retry"))
  #expect(!message.contains("credential"))
}

private func context() -> AgentWriteContext {
  AgentWriteContext(
    noteID: noteID,
    expectedRevision: 7,
    operationID: operationID
  )
}

private func writeArguments(_ prefix: [String]) -> [String] {
  prefix + [
    "--profile", profileID.uuidString,
    "--revision", "7",
    "--operation-id", operationID.uuidString,
  ]
}

private func expectUsageError(
  _ arguments: [String],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    _ = try BridgeCommand.parse(arguments: arguments) { "text" }
    Issue.record("Expected usage error", sourceLocation: sourceLocation)
  } catch let error as BridgeParseError {
    #expect(error.exitCode == 64, sourceLocation: sourceLocation)
  } catch {
    Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
  }
}
