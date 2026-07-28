import Foundation
import MenuBarNotesCore

enum BridgeCommand: Equatable {
  case help
  case configure(profileID: UUID)
  case disconnect(profileID: UUID)
  case mcp(profileID: UUID)
  case workspace(
    profileID: UUID,
    command: AgentWorkspaceCommand,
    json: Bool
  )

  var profileID: UUID? {
    switch self {
    case .help:
      nil
    case .configure(let profileID),
      .disconnect(let profileID),
      .mcp(let profileID),
      .workspace(let profileID, _, _):
      profileID
    }
  }

  var workspaceCommand: AgentWorkspaceCommand? {
    guard case .workspace(_, let command, _) = self else { return nil }
    return command
  }

  var usesJSON: Bool {
    guard case .workspace(_, _, let json) = self else { return false }
    return json
  }

  var operationID: UUID? {
    guard let workspaceCommand else { return nil }
    switch workspaceCommand {
    case .appendText(let request):
      return request.context.operationID
    case .insertText(let request):
      return request.context.operationID
    case .replaceLines(let request):
      return request.context.operationID
    case .addTask(let request):
      return request.context.operationID
    case .renameTask(let request):
      return request.context.operationID
    case .setTaskState(let request):
      return request.context.operationID
    case .removeTask(let request):
      return request.context.operationID
    case .undoChange(let request):
      return request.operationID
    case .listSharedNotes, .readNote, .listTasks, .listActivity:
      return nil
    }
  }

  static func parse(
    arguments: [String],
    readStdin: () throws -> String
  ) throws -> BridgeCommand {
    guard !arguments.isEmpty else { return .help }
    if arguments == ["--help"] || arguments == ["-h"] {
      return .help
    }

    var arguments = ArgumentBag(arguments)
    let json = try arguments.takeFlag("--json")
    let profileID = try arguments.requiredUUID("--profile")
    let command = arguments.takeFirst()

    switch command {
    case "configure":
      guard try arguments.takeFlag("--token-stdin") else {
        throw BridgeParseError("configure requires --token-stdin")
      }
      try arguments.requireEmpty()
      return .configure(profileID: profileID)
    case "disconnect":
      try arguments.requireEmpty()
      return .disconnect(profileID: profileID)
    case "mcp":
      try arguments.requireEmpty()
      return .mcp(profileID: profileID)
    case "notes":
      guard arguments.takeFirst() == "list" else {
        throw BridgeParseError("Expected 'notes list'.")
      }
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .listSharedNotes,
        json: json
      )
    case "note":
      return try parseNote(
        arguments: &arguments,
        profileID: profileID,
        json: json,
        readStdin: readStdin
      )
    case "tasks":
      guard
        arguments.takeFirst() == "list",
        let noteID = UUID(uuidString: arguments.takeFirst() ?? "")
      else {
        throw BridgeParseError("Expected 'tasks list <note-id>'.")
      }
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .listTasks(request: .init(noteID: noteID)),
        json: json
      )
    case "task":
      return try parseTask(
        arguments: &arguments,
        profileID: profileID,
        json: json
      )
    case "activity":
      return try parseActivity(
        arguments: &arguments,
        profileID: profileID,
        json: json
      )
    default:
      throw BridgeParseError("Unknown command.")
    }
  }

  private static func parseNote(
    arguments: inout ArgumentBag,
    profileID: UUID,
    json: Bool,
    readStdin: () throws -> String
  ) throws -> BridgeCommand {
    let action = arguments.takeFirst()
    guard let noteID = UUID(uuidString: arguments.takeFirst() ?? "") else {
      throw BridgeParseError("A valid note ID is required.")
    }

    switch action {
    case "read":
      let startLine = try arguments.optionalPositiveInt("--start-line")
      let maxLines = try arguments.optionalPositiveInt("--max-lines")
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .readNote(
          request: .init(
            noteID: noteID,
            startLine: startLine,
            maxLines: maxLines
          )
        ),
        json: json
      )
    case "append":
      let context = try arguments.writeContext(noteID: noteID)
      try arguments.requireStdin()
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .appendText(
          request: .init(context: context, text: try readStdin())
        ),
        json: json
      )
    case "insert":
      guard let beforeLine = positiveInt(arguments.takeFirst()) else {
        throw BridgeParseError("before-line must be one-based.")
      }
      let context = try arguments.writeContext(noteID: noteID)
      try arguments.requireStdin()
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .insertText(
          request: .init(
            context: context,
            beforeLine: beforeLine,
            text: try readStdin()
          )
        ),
        json: json
      )
    case "replace-lines":
      guard
        let startLine = positiveInt(arguments.takeFirst()),
        let endLine = positiveInt(arguments.takeFirst()),
        endLine >= startLine
      else {
        throw BridgeParseError("Line range must be one-based and inclusive.")
      }
      let expectedHash = try arguments.requiredValue(
        "--expected-text-sha256"
      )
      guard
        expectedHash.count == 64,
        expectedHash.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
      else {
        throw BridgeParseError(
          "--expected-text-sha256 must be 64 lowercase hexadecimal characters."
        )
      }
      let context = try arguments.writeContext(noteID: noteID)
      try arguments.requireStdin()
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .replaceLines(
          request: .init(
            context: context,
            startLine: startLine,
            endLine: endLine,
            expectedTextSHA256: expectedHash,
            text: try readStdin()
          )
        ),
        json: json
      )
    default:
      throw BridgeParseError("Unknown note command.")
    }
  }

  private static func parseTask(
    arguments: inout ArgumentBag,
    profileID: UUID,
    json: Bool
  ) throws -> BridgeCommand {
    let action = arguments.takeFirst()
    guard let noteID = UUID(uuidString: arguments.takeFirst() ?? "") else {
      throw BridgeParseError("A valid note ID is required.")
    }
    let context = try arguments.writeContext(noteID: noteID)
    let command: AgentWorkspaceCommand

    switch action {
    case "add":
      guard let text = arguments.takeFirst() else {
        throw BridgeParseError("Task text is required.")
      }
      let afterTaskHandle = try arguments.optionalValue(
        "--after-task-handle"
      )
      command = .addTask(
        request: .init(
          context: context,
          afterTaskHandle: afterTaskHandle,
          text: text
        )
      )
    case "rename":
      guard
        let taskHandle = arguments.takeFirst(),
        let text = arguments.takeFirst()
      else {
        throw BridgeParseError("Task handle and text are required.")
      }
      command = .renameTask(
        request: .init(
          context: context,
          taskHandle: taskHandle,
          text: text
        )
      )
    case "complete", "reopen":
      guard let taskHandle = arguments.takeFirst() else {
        throw BridgeParseError("Task handle is required.")
      }
      command = .setTaskState(
        request: .init(
          context: context,
          taskHandle: taskHandle,
          completed: action == "complete"
        )
      )
    case "remove":
      guard let taskHandle = arguments.takeFirst() else {
        throw BridgeParseError("Task handle is required.")
      }
      command = .removeTask(
        request: .init(context: context, taskHandle: taskHandle)
      )
    default:
      throw BridgeParseError("Unknown task command.")
    }

    try arguments.requireEmpty()
    return .workspace(profileID: profileID, command: command, json: json)
  }

  private static func parseActivity(
    arguments: inout ArgumentBag,
    profileID: UUID,
    json: Bool
  ) throws -> BridgeCommand {
    switch arguments.takeFirst() {
    case "list":
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .listActivity,
        json: json
      )
    case "undo":
      guard let changeID = UUID(uuidString: arguments.takeFirst() ?? "") else {
        throw BridgeParseError("A valid change ID is required.")
      }
      let expectedRevision = try arguments.requiredRevision()
      let operationID = try arguments.requiredUUID("--operation-id")
      try arguments.requireEmpty()
      return .workspace(
        profileID: profileID,
        command: .undoChange(
          request: .init(
            changeID: changeID,
            expectedRevision: expectedRevision,
            operationID: operationID
          )
        ),
        json: json
      )
    default:
      throw BridgeParseError("Unknown activity command.")
    }
  }

  private static func positiveInt(_ value: String?) -> Int? {
    guard let value, let parsed = Int(value), parsed >= 1 else { return nil }
    return parsed
  }
}

struct BridgeParseError: Error, Equatable, CustomStringConvertible {
  let message: String
  let exitCode: Int32 = 64

  init(_ message: String) {
    self.message = message
  }

  var description: String { message }
}

enum BridgeOutput {
  static let help = """
    Usage: motes-agent <command> --profile <uuid> [--json]

      notes list
      note read <note-id> [--start-line <line>] [--max-lines <count>]
      note append <note-id> --revision <revision> --operation-id <uuid> --stdin
      note insert <note-id> <before-line> --revision <revision> --operation-id <uuid> --stdin
      note replace-lines <note-id> <start> <end> --expected-text-sha256 <hash> --revision <revision> --operation-id <uuid> --stdin
      tasks list <note-id>
      task add <note-id> <text> [--after-task-handle <handle>] --revision <revision> --operation-id <uuid>
      task rename <note-id> <handle> <text> --revision <revision> --operation-id <uuid>
      task complete|reopen|remove <note-id> <handle> --revision <revision> --operation-id <uuid>
      activity list
      activity undo <change-id> --revision <revision> --operation-id <uuid>
      disconnect --profile <uuid>
    """

  static func response(
    _ response: AgentWorkspaceResponse,
    json: Bool
  ) throws -> String {
    if json {
      return try encode(response)
    }
    switch response {
    case .sharedNotes(let notes):
      return notes.map {
        "\($0.noteID.uuidString)\t\($0.revision)\t\($0.title)"
      }.joined(separator: "\n")
    case .note(let page):
      return """
        \(page.title) (\(page.noteID.uuidString), revision \(page.revision))
        Lines \(page.startLine)-\(page.endLine) of \(page.totalLineCount)
        \(page.body)
        """
    case .tasks(let tasks):
      return tasks.map {
        "\($0.completed ? "done" : "open")\t\($0.line)\t\($0.taskHandle)\t\($0.text)"
      }.joined(separator: "\n")
    case .write(let receipt), .undo(let receipt):
      var output =
        "Applied change \(receipt.changeID.uuidString); revision "
        + "\(receipt.previousRevision) → \(receipt.resultingRevision)."
      if let taskHandle = receipt.taskHandle {
        output += "\nTask handle: \(taskHandle)"
      }
      return output
    case .activity(let entries):
      return entries.map {
        "\($0.changeID.uuidString)\t\($0.operation.rawValue)\t\($0.noteTitle)"
      }.joined(separator: "\n")
    }
  }

  static func workspaceError(
    _ error: AgentWorkspaceError,
    json: Bool
  ) throws -> String {
    if json {
      return try encode(error)
    }
    return [error.code.rawValue, error.recoveryAction]
      .compactMap { $0 }
      .joined(separator: ": ")
  }

  static func writeTimedOut(operationID: UUID) -> String {
    "The write timed out; retry with the same operation ID "
      + "\(operationID.uuidString) to avoid a duplicate change."
  }

  private static func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

private struct ArgumentBag {
  private var values: [String]

  init(_ values: [String]) {
    self.values = values
  }

  mutating func takeFirst() -> String? {
    values.isEmpty ? nil : values.removeFirst()
  }

  mutating func takeFlag(_ name: String) throws -> Bool {
    let matches = values.indices.filter { values[$0] == name }
    guard matches.count <= 1 else {
      throw BridgeParseError("Duplicate \(name).")
    }
    guard let index = matches.first else { return false }
    values.remove(at: index)
    return true
  }

  mutating func optionalValue(_ name: String) throws -> String? {
    let matches = values.indices.filter { values[$0] == name }
    guard matches.count <= 1 else {
      throw BridgeParseError("Duplicate \(name).")
    }
    guard let index = matches.first else { return nil }
    guard index + 1 < values.count else {
      throw BridgeParseError("\(name) requires a value.")
    }
    let value = values[index + 1]
    values.removeSubrange(index...index + 1)
    return value
  }

  mutating func requiredValue(_ name: String) throws -> String {
    guard let value = try optionalValue(name) else {
      throw BridgeParseError("\(name) is required.")
    }
    return value
  }

  mutating func requiredUUID(_ name: String) throws -> UUID {
    guard let value = UUID(uuidString: try requiredValue(name)) else {
      throw BridgeParseError("\(name) must be a UUID.")
    }
    return value
  }

  mutating func requiredRevision() throws -> UInt64 {
    guard
      let revision = UInt64(try requiredValue("--revision"))
    else {
      throw BridgeParseError("--revision must be a nonnegative integer.")
    }
    return revision
  }

  mutating func optionalPositiveInt(_ name: String) throws -> Int? {
    guard let value = try optionalValue(name) else { return nil }
    guard let parsed = Int(value), parsed >= 1 else {
      throw BridgeParseError("\(name) must be one-based.")
    }
    return parsed
  }

  mutating func writeContext(noteID: UUID) throws -> AgentWriteContext {
    AgentWriteContext(
      noteID: noteID,
      expectedRevision: try requiredRevision(),
      operationID: try requiredUUID("--operation-id")
    )
  }

  mutating func requireStdin() throws {
    guard try takeFlag("--stdin") else {
      throw BridgeParseError("--stdin is required.")
    }
  }

  func requireEmpty() throws {
    guard values.isEmpty else {
      throw BridgeParseError("Unknown argument: \(values[0])")
    }
  }
}
