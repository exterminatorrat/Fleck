import Foundation

public struct AgentWriteContext: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let expectedRevision: UInt64
  public let operationID: UUID

  public init(noteID: UUID, expectedRevision: UInt64, operationID: UUID) {
    self.noteID = noteID
    self.expectedRevision = expectedRevision
    self.operationID = operationID
  }
}

public enum AgentWorkspaceCommand: Codable, Equatable, Sendable {
  public struct ReadNoteRequest: Codable, Equatable, Sendable {
    public let noteID: UUID
    public let startLine: Int?
    public let maxLines: Int?

    public init(noteID: UUID, startLine: Int? = nil, maxLines: Int? = nil) {
      self.noteID = noteID
      self.startLine = startLine
      self.maxLines = maxLines
    }
  }

  public struct AppendTextRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let text: String

    public init(context: AgentWriteContext, text: String) {
      self.context = context
      self.text = text
    }
  }

  public struct InsertTextRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let beforeLine: Int
    public let text: String

    public init(context: AgentWriteContext, beforeLine: Int, text: String) {
      self.context = context
      self.beforeLine = beforeLine
      self.text = text
    }
  }

  public struct ReplaceLinesRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let startLine: Int
    public let endLine: Int
    public let expectedTextSHA256: String
    public let text: String

    public init(
      context: AgentWriteContext,
      startLine: Int,
      endLine: Int,
      expectedTextSHA256: String,
      text: String
    ) {
      self.context = context
      self.startLine = startLine
      self.endLine = endLine
      self.expectedTextSHA256 = expectedTextSHA256
      self.text = text
    }
  }

  public struct ListTasksRequest: Codable, Equatable, Sendable {
    public let noteID: UUID

    public init(noteID: UUID) {
      self.noteID = noteID
    }
  }

  public struct AddTaskRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let afterTaskHandle: String?
    public let text: String

    public init(
      context: AgentWriteContext,
      afterTaskHandle: String? = nil,
      text: String
    ) {
      self.context = context
      self.afterTaskHandle = afterTaskHandle
      self.text = text
    }
  }

  public struct RenameTaskRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let taskHandle: String
    public let text: String

    public init(context: AgentWriteContext, taskHandle: String, text: String) {
      self.context = context
      self.taskHandle = taskHandle
      self.text = text
    }
  }

  public struct SetTaskStateRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let taskHandle: String
    public let completed: Bool

    public init(
      context: AgentWriteContext,
      taskHandle: String,
      completed: Bool
    ) {
      self.context = context
      self.taskHandle = taskHandle
      self.completed = completed
    }
  }

  public struct RemoveTaskRequest: Codable, Equatable, Sendable {
    public let context: AgentWriteContext
    public let taskHandle: String

    public init(context: AgentWriteContext, taskHandle: String) {
      self.context = context
      self.taskHandle = taskHandle
    }
  }

  public struct UndoChangeRequest: Codable, Equatable, Sendable {
    public let changeID: UUID
    public let expectedRevision: UInt64
    public let operationID: UUID

    public init(
      changeID: UUID,
      expectedRevision: UInt64,
      operationID: UUID
    ) {
      self.changeID = changeID
      self.expectedRevision = expectedRevision
      self.operationID = operationID
    }
  }

  case listSharedNotes
  case readNote(request: ReadNoteRequest)
  case appendText(request: AppendTextRequest)
  case insertText(request: InsertTextRequest)
  case replaceLines(request: ReplaceLinesRequest)
  case listTasks(request: ListTasksRequest)
  case addTask(request: AddTaskRequest)
  case renameTask(request: RenameTaskRequest)
  case setTaskState(request: SetTaskStateRequest)
  case removeTask(request: RemoveTaskRequest)
  case listActivity
  case undoChange(request: UndoChangeRequest)
  case getCapabilities

  public func isSupported(wireVersion: Int) -> Bool {
    switch self {
    case .listSharedNotes,
      .readNote,
      .appendText,
      .insertText,
      .replaceLines,
      .listTasks,
      .addTask,
      .renameTask,
      .setTaskState,
      .removeTask,
      .listActivity,
      .undoChange:
      return wireVersion == 1 || wireVersion == 2
    case .getCapabilities:
      return wireVersion == 2
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentWorkspaceCodingKey.self)
    guard container.allKeys.count == 1, let key = container.allKeys.first else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Command must contain exactly one case."
        )
      )
    }
    guard [
      "listSharedNotes", "readNote", "appendText", "insertText",
      "replaceLines", "listTasks", "addTask", "renameTask", "setTaskState",
      "removeTask", "listActivity", "undoChange", "getCapabilities",
    ].contains(key.stringValue) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Unknown command case."
        )
      )
    }
    try validateCommandPayload(from: container, caseKey: key)
    self = try LegacyAgentWorkspaceCommand(from: decoder).command
  }

  public func encode(to encoder: any Encoder) throws {
    try LegacyAgentWorkspaceCommand(self).encode(to: encoder)
  }
}

private enum LegacyAgentWorkspaceCommand: Codable {
  case listSharedNotes
  case readNote(request: AgentWorkspaceCommand.ReadNoteRequest)
  case appendText(request: AgentWorkspaceCommand.AppendTextRequest)
  case insertText(request: AgentWorkspaceCommand.InsertTextRequest)
  case replaceLines(request: AgentWorkspaceCommand.ReplaceLinesRequest)
  case listTasks(request: AgentWorkspaceCommand.ListTasksRequest)
  case addTask(request: AgentWorkspaceCommand.AddTaskRequest)
  case renameTask(request: AgentWorkspaceCommand.RenameTaskRequest)
  case setTaskState(request: AgentWorkspaceCommand.SetTaskStateRequest)
  case removeTask(request: AgentWorkspaceCommand.RemoveTaskRequest)
  case listActivity
  case undoChange(request: AgentWorkspaceCommand.UndoChangeRequest)
  case getCapabilities

  init(_ command: AgentWorkspaceCommand) {
    switch command {
    case .listSharedNotes: self = .listSharedNotes
    case .readNote(let request): self = .readNote(request: request)
    case .appendText(let request): self = .appendText(request: request)
    case .insertText(let request): self = .insertText(request: request)
    case .replaceLines(let request): self = .replaceLines(request: request)
    case .listTasks(let request): self = .listTasks(request: request)
    case .addTask(let request): self = .addTask(request: request)
    case .renameTask(let request): self = .renameTask(request: request)
    case .setTaskState(let request): self = .setTaskState(request: request)
    case .removeTask(let request): self = .removeTask(request: request)
    case .listActivity: self = .listActivity
    case .undoChange(let request): self = .undoChange(request: request)
    case .getCapabilities: self = .getCapabilities
    }
  }

  var command: AgentWorkspaceCommand {
    switch self {
    case .listSharedNotes: return .listSharedNotes
    case .readNote(let request): return .readNote(request: request)
    case .appendText(let request): return .appendText(request: request)
    case .insertText(let request): return .insertText(request: request)
    case .replaceLines(let request): return .replaceLines(request: request)
    case .listTasks(let request): return .listTasks(request: request)
    case .addTask(let request): return .addTask(request: request)
    case .renameTask(let request): return .renameTask(request: request)
    case .setTaskState(let request): return .setTaskState(request: request)
    case .removeTask(let request): return .removeTask(request: request)
    case .listActivity: return .listActivity
    case .undoChange(let request): return .undoChange(request: request)
    case .getCapabilities: return .getCapabilities
    }
  }
}

public struct AgentNoteSummary: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let title: String
  public let revision: UInt64
  public let modifiedAt: Date

  public init(noteID: UUID, title: String, revision: UInt64, modifiedAt: Date) {
    self.noteID = noteID
    self.title = title
    self.revision = revision
    self.modifiedAt = modifiedAt
  }
}

public struct AgentNotePage: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let title: String
  public let revision: UInt64
  public let body: String
  public let startLine: Int
  public let endLine: Int
  public let totalLineCount: Int
  public let nextLine: Int?
  public let modifiedAt: Date

  public init(
    noteID: UUID,
    title: String,
    revision: UInt64,
    body: String,
    startLine: Int,
    endLine: Int,
    totalLineCount: Int,
    nextLine: Int?,
    modifiedAt: Date
  ) {
    self.noteID = noteID
    self.title = title
    self.revision = revision
    self.body = body
    self.startLine = startLine
    self.endLine = endLine
    self.totalLineCount = totalLineCount
    self.nextLine = nextLine
    self.modifiedAt = modifiedAt
  }
}

public struct AgentTaskSummary: Codable, Equatable, Sendable {
  public let taskHandle: String
  public let text: String
  public let completed: Bool
  public let line: Int
  public let indentation: String

  public init(
    taskHandle: String,
    text: String,
    completed: Bool,
    line: Int,
    indentation: String
  ) {
    self.taskHandle = taskHandle
    self.text = text
    self.completed = completed
    self.line = line
    self.indentation = indentation
  }
}

public struct AgentWriteReceipt: Codable, Equatable, Sendable {
  public let changeID: UUID
  public let noteID: UUID
  public let previousRevision: UInt64
  public let resultingRevision: UInt64
  public let taskHandle: String?

  public init(
    changeID: UUID,
    noteID: UUID,
    previousRevision: UInt64,
    resultingRevision: UInt64,
    taskHandle: String? = nil
  ) {
    self.changeID = changeID
    self.noteID = noteID
    self.previousRevision = previousRevision
    self.resultingRevision = resultingRevision
    self.taskHandle = taskHandle
  }
}

public enum AgentActivityActor: Codable, Equatable, Sendable {
  case integration(profileID: UUID, displayName: String)
  case localUser
}

public enum AgentActivityOperation: String, Codable, Equatable, Sendable {
  case appendText
  case insertText
  case replaceLines
  case addTask
  case renameTask
  case setTaskState
  case removeTask
  case undoChange
}

public struct AgentActivitySummary: Codable, Equatable, Sendable {
  public let changeID: UUID
  public let noteID: UUID
  public let noteTitle: String
  public let actor: AgentActivityActor
  public let originatingActor: AgentActivityActor?
  public let createdAt: Date
  public let operation: AgentActivityOperation
  public let patch: AgentTextPatch
  public let previousRevision: UInt64
  public let resultingRevision: UInt64
  public let canUndo: Bool

  public init(
    changeID: UUID,
    noteID: UUID,
    noteTitle: String,
    actor: AgentActivityActor,
    originatingActor: AgentActivityActor? = nil,
    createdAt: Date,
    operation: AgentActivityOperation,
    patch: AgentTextPatch,
    previousRevision: UInt64,
    resultingRevision: UInt64,
    canUndo: Bool
  ) {
    self.changeID = changeID
    self.noteID = noteID
    self.noteTitle = noteTitle
    self.actor = actor
    self.originatingActor = originatingActor
    self.createdAt = createdAt
    self.operation = operation
    self.patch = patch
    self.previousRevision = previousRevision
    self.resultingRevision = resultingRevision
    self.canUndo = canUndo
  }
}

public enum AgentWorkspaceResponse: Codable, Equatable, Sendable {
  case sharedNotes(notes: [AgentNoteSummary])
  case note(page: AgentNotePage)
  case tasks(tasks: [AgentTaskSummary])
  case write(receipt: AgentWriteReceipt)
  case activity(entries: [AgentActivitySummary])
  case undo(receipt: AgentWriteReceipt)
  case capabilities(summary: AgentCapabilitySummary)

  public func isSupported(wireVersion: Int) -> Bool {
    switch self {
    case .sharedNotes,
      .note,
      .tasks,
      .write,
      .activity,
      .undo:
      return wireVersion == 1 || wireVersion == 2
    case .capabilities:
      return wireVersion == 2
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentWorkspaceCodingKey.self)
    guard container.allKeys.count == 1, let key = container.allKeys.first else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Response must contain exactly one case."
        )
      )
    }
    switch key.stringValue {
    case "sharedNotes", "note", "tasks", "write", "activity", "undo":
      try validateResponsePayload(from: container, caseKey: key)
      self = try LegacyAgentWorkspaceResponse(from: decoder).response
    case "capabilities":
      let payload = try container.nestedContainer(
        keyedBy: AgentWorkspaceCodingKey.self,
        forKey: key
      )
      try payload.requireExactKeys(["summary"])
      let summaryContainer = try payload.nestedContainer(
        keyedBy: AgentWorkspaceCodingKey.self,
        forKey: AgentWorkspaceCodingKey("summary")
      )
      try summaryContainer.requireExactKeys(
        ["grantRevision", "availableCapabilities"]
      )
      let rawCapabilities = try summaryContainer.decode(
        [AgentCapability].self,
        forKey: AgentWorkspaceCodingKey("availableCapabilities")
      )
      guard Set(rawCapabilities).count == rawCapabilities.count else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: summaryContainer.codingPath,
            debugDescription: "Capability values must not be duplicated."
          )
        )
      }
      self = .capabilities(
        summary: AgentCapabilitySummary(
          grantRevision: try summaryContainer.decode(
            UInt64.self,
            forKey: AgentWorkspaceCodingKey("grantRevision")
          ),
          availableCapabilities: Set(rawCapabilities)
        )
      )
    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Unknown response case."
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    try LegacyAgentWorkspaceResponse(self).encode(to: encoder)
  }
}

private enum LegacyAgentWorkspaceResponse: Codable {
  case sharedNotes(notes: [AgentNoteSummary])
  case note(page: AgentNotePage)
  case tasks(tasks: [AgentTaskSummary])
  case write(receipt: AgentWriteReceipt)
  case activity(entries: [AgentActivitySummary])
  case undo(receipt: AgentWriteReceipt)
  case capabilities(summary: AgentCapabilitySummary)

  init(_ response: AgentWorkspaceResponse) {
    switch response {
    case .sharedNotes(let notes): self = .sharedNotes(notes: notes)
    case .note(let page): self = .note(page: page)
    case .tasks(let tasks): self = .tasks(tasks: tasks)
    case .write(let receipt): self = .write(receipt: receipt)
    case .activity(let entries): self = .activity(entries: entries)
    case .undo(let receipt): self = .undo(receipt: receipt)
    case .capabilities(let summary): self = .capabilities(summary: summary)
    }
  }

  var response: AgentWorkspaceResponse {
    switch self {
    case .sharedNotes(let notes): return .sharedNotes(notes: notes)
    case .note(let page): return .note(page: page)
    case .tasks(let tasks): return .tasks(tasks: tasks)
    case .write(let receipt): return .write(receipt: receipt)
    case .activity(let entries): return .activity(entries: entries)
    case .undo(let receipt): return .undo(receipt: receipt)
    case .capabilities(let summary): return .capabilities(summary: summary)
    }
  }
}

private struct AgentWorkspaceCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

private extension KeyedDecodingContainer where Key == AgentWorkspaceCodingKey {
  func requireNestedKeys(forKey key: Key, expected: Set<String>) throws {
    let payload = try nestedContainer(keyedBy: Key.self, forKey: key)
    try payload.requireExactKeys(expected)
  }

  func requireExactKeys(_ expected: Set<String>) throws {
    guard Set(allKeys.map(\.stringValue)) == expected else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "Unexpected or missing response fields."
        )
      )
    }
  }

  func requireKeys(
    required: Set<String>,
    optional: Set<String> = []
  ) throws {
    let actual = Set(allKeys.map(\.stringValue))
    let allowed = required.union(optional)
    guard required.isSubset(of: actual), actual.isSubset(of: allowed) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "Unexpected or missing response fields."
        )
      )
    }
  }
}

private func strictObject(
  from decoder: any Decoder,
  required: Set<String>,
  optional: Set<String> = []
) throws -> KeyedDecodingContainer<AgentWorkspaceCodingKey> {
  let container = try decoder.container(
    keyedBy: AgentWorkspaceCodingKey.self
  )
  try container.requireKeys(required: required, optional: optional)
  return container
}

private func validateCommandPayload(
  from container: KeyedDecodingContainer<AgentWorkspaceCodingKey>,
  caseKey: AgentWorkspaceCodingKey
) throws {
  switch caseKey.stringValue {
  case "listSharedNotes", "listActivity", "getCapabilities":
    try container.requireNestedKeys(forKey: caseKey, expected: [])
  case "readNote":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateReadNoteRequest
    )
  case "appendText":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateAppendTextRequest
    )
  case "insertText":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateInsertTextRequest
    )
  case "replaceLines":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateReplaceLinesRequest
    )
  case "listTasks":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateListTasksRequest
    )
  case "addTask":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateAddTaskRequest
    )
  case "renameTask":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateRenameTaskRequest
    )
  case "setTaskState":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateSetTaskStateRequest
    )
  case "removeTask":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateRemoveTaskRequest
    )
  case "undoChange":
    try validateCommandRequest(
      from: container,
      caseKey: caseKey,
      validator: validateUndoChangeRequest
    )
  default:
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: container.codingPath,
        debugDescription: "Unknown command case."
      )
    )
  }
}

private func validateCommandRequest(
  from container: KeyedDecodingContainer<AgentWorkspaceCodingKey>,
  caseKey: AgentWorkspaceCodingKey,
  validator: (any Decoder) throws -> Void
) throws {
  let payload = try container.nestedContainer(
    keyedBy: AgentWorkspaceCodingKey.self,
    forKey: caseKey
  )
  try payload.requireExactKeys(["request"])
  try validator(
    payload.superDecoder(forKey: AgentWorkspaceCodingKey("request"))
  )
}

private func validateReadNoteRequest(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["noteID"],
    optional: ["startLine", "maxLines"]
  )
}

private func validateWriteContext(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["noteID", "expectedRevision", "operationID"]
  )
}

private func validateAppendTextRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: ["context", "text"]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateInsertTextRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: ["context", "beforeLine", "text"]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateReplaceLinesRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: [
      "context", "startLine", "endLine", "expectedTextSHA256", "text",
    ]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateListTasksRequest(from decoder: any Decoder) throws {
  _ = try strictObject(from: decoder, required: ["noteID"])
}

private func validateAddTaskRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: ["context", "text"],
    optional: ["afterTaskHandle"]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateRenameTaskRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: ["context", "taskHandle", "text"]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateSetTaskStateRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: ["context", "taskHandle", "completed"]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateRemoveTaskRequest(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: ["context", "taskHandle"]
  )
  try validateWriteContext(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("context"))
  )
}

private func validateUndoChangeRequest(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["changeID", "expectedRevision", "operationID"]
  )
}

private func validateResponsePayload(
  from container: KeyedDecodingContainer<AgentWorkspaceCodingKey>,
  caseKey: AgentWorkspaceCodingKey
) throws {
  let payload = try container.nestedContainer(
    keyedBy: AgentWorkspaceCodingKey.self,
    forKey: caseKey
  )
  switch caseKey.stringValue {
  case "sharedNotes":
    try payload.requireExactKeys(["notes"])
    try validateArray(
      in: payload,
      forKey: "notes",
      validator: validateNoteSummary
    )
  case "note":
    try payload.requireExactKeys(["page"])
    try validateNotePage(
      from: payload.superDecoder(forKey: AgentWorkspaceCodingKey("page"))
    )
  case "tasks":
    try payload.requireExactKeys(["tasks"])
    try validateArray(
      in: payload,
      forKey: "tasks",
      validator: validateTaskSummary
    )
  case "write", "undo":
    try payload.requireExactKeys(["receipt"])
    try validateWriteReceipt(
      from: payload.superDecoder(forKey: AgentWorkspaceCodingKey("receipt"))
    )
  case "activity":
    try payload.requireExactKeys(["entries"])
    try validateArray(
      in: payload,
      forKey: "entries",
      validator: validateActivitySummary
    )
  default:
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: container.codingPath,
        debugDescription: "Unknown response case."
      )
    )
  }
}

private func validateArray(
  in container: KeyedDecodingContainer<AgentWorkspaceCodingKey>,
  forKey key: String,
  validator: (any Decoder) throws -> Void
) throws {
  var elements = try container.nestedUnkeyedContainer(
    forKey: AgentWorkspaceCodingKey(key)
  )
  while !elements.isAtEnd {
    try validator(elements.superDecoder())
  }
}

private func validateNoteSummary(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["noteID", "title", "revision", "modifiedAt"]
  )
}

private func validateNotePage(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: [
      "noteID", "title", "revision", "body", "startLine", "endLine",
      "totalLineCount", "modifiedAt",
    ],
    optional: ["nextLine"]
  )
}

private func validateTaskSummary(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["taskHandle", "text", "completed", "line", "indentation"]
  )
}

private func validateWriteReceipt(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["changeID", "noteID", "previousRevision", "resultingRevision"],
    optional: ["taskHandle"]
  )
}

private func validateActivitySummary(from decoder: any Decoder) throws {
  let container = try strictObject(
    from: decoder,
    required: [
      "changeID", "noteID", "noteTitle", "actor", "createdAt", "operation",
      "patch", "previousRevision", "resultingRevision", "canUndo",
    ],
    optional: ["originatingActor"]
  )
  try validateActivityActor(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("actor"))
  )
  try validateOptionalNestedObject(
    in: container,
    forKey: "originatingActor",
    validator: validateActivityActor
  )
  try validateTextPatch(
    from: container.superDecoder(forKey: AgentWorkspaceCodingKey("patch"))
  )
}

private func validateOptionalNestedObject(
  in container: KeyedDecodingContainer<AgentWorkspaceCodingKey>,
  forKey key: String,
  validator: (any Decoder) throws -> Void
) throws {
  let key = AgentWorkspaceCodingKey(key)
  guard container.contains(key), try !container.decodeNil(forKey: key) else {
    return
  }
  try validator(container.superDecoder(forKey: key))
}

private func validateActivityActor(from decoder: any Decoder) throws {
  let container = try decoder.container(
    keyedBy: AgentWorkspaceCodingKey.self
  )
  guard container.allKeys.count == 1, let key = container.allKeys.first else {
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: container.codingPath,
        debugDescription: "Activity actor must contain exactly one case."
      )
    )
  }
  switch key.stringValue {
  case "integration":
    let payload = try container.nestedContainer(
      keyedBy: AgentWorkspaceCodingKey.self,
      forKey: key
    )
    try payload.requireExactKeys(["profileID", "displayName"])
  case "localUser":
    let payload = try container.nestedContainer(
      keyedBy: AgentWorkspaceCodingKey.self,
      forKey: key
    )
    try payload.requireExactKeys([])
  default:
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: container.codingPath,
        debugDescription: "Unknown activity actor case."
      )
    )
  }
}

private func validateTextPatch(from decoder: any Decoder) throws {
  _ = try strictObject(
    from: decoder,
    required: ["beforeText", "afterText", "range", "prefixContext", "suffixContext"]
  )
}

public enum AgentWorkspaceErrorCode: String, Codable, CaseIterable, Sendable {
  case noteNotFound = "note_not_found"
  case permissionRevoked = "permission_revoked"
  case revisionConflict = "revision_conflict"
  case taskHandleExpired = "task_handle_expired"
  case unsafeUndo = "unsafe_undo"
  case fleckUnavailable = "fleck_unavailable"
  case writeTooLarge = "write_too_large"
  case responseTooLarge = "response_too_large"
  case invalidOperation = "invalid_operation"
  case invalidPayload = "invalid_payload"
  case internalSaveFailure = "internal_save_failure"
  case capabilityDenied = "capability_denied"
  case protocolVersionUnsupported = "protocol_version_unsupported"
}

public struct AgentWorkspaceError: Codable, Equatable, Error, Sendable {
  public let code: AgentWorkspaceErrorCode
  public let recoveryAction: String?

  public init(code: AgentWorkspaceErrorCode, recoveryAction: String? = nil) {
    self.code = code
    self.recoveryAction = recoveryAction
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentWorkspaceCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    guard keys == ["code"] || keys == ["code", "recoveryAction"] else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Unexpected or missing error fields."
        )
      )
    }
    code = try container.decode(
      AgentWorkspaceErrorCode.self,
      forKey: AgentWorkspaceCodingKey("code")
    )
    recoveryAction = try container.decodeIfPresent(
      String.self,
      forKey: AgentWorkspaceCodingKey("recoveryAction")
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AgentWorkspaceCodingKey.self)
    try container.encode(code, forKey: AgentWorkspaceCodingKey("code"))
    try container.encodeIfPresent(
      recoveryAction,
      forKey: AgentWorkspaceCodingKey("recoveryAction")
    )
  }
}

extension AgentWorkspaceError: LocalizedError {
  public var errorDescription: String? {
    switch code {
    case .noteNotFound:
      "The shared note could not be found."
    case .permissionRevoked:
      "This agent connection is no longer authorized."
    case .revisionConflict:
      "The note changed before the agent update could be saved."
    case .taskHandleExpired:
      "This task reference is out of date."
    case .unsafeUndo:
      "Fleck cannot safely undo this agent change."
    case .fleckUnavailable:
      "Fleck's agent workspace is not available."
    case .writeTooLarge:
      "The agent update is too large."
    case .responseTooLarge:
      "The agent response is too large."
    case .invalidOperation:
      "The agent request is not supported."
    case .invalidPayload:
      "The agent request is invalid."
    case .internalSaveFailure:
      "Fleck could not update its local agent data."
    case .capabilityDenied:
      "This agent capability is not authorized."
    case .protocolVersionUnsupported:
      "This agent protocol version is not supported."
    }
  }

  public var recoverySuggestion: String? {
    recoveryAction
  }
}

public struct AgentWorkspaceCommitProof: Codable, Equatable, Sendable {
  public let changeID: UUID
  public let noteID: UUID
  public let resultingRevision: UInt64
  public let bodySHA256: String
  public let actor: AgentActivityActor
  public let operationID: UUID
  public let expiresAt: Date

  public init(
    changeID: UUID,
    noteID: UUID,
    resultingRevision: UInt64,
    bodySHA256: String,
    actor: AgentActivityActor,
    operationID: UUID,
    expiresAt: Date
  ) {
    self.changeID = changeID
    self.noteID = noteID
    self.resultingRevision = resultingRevision
    self.bodySHA256 = bodySHA256
    self.actor = actor
    self.operationID = operationID
    self.expiresAt = expiresAt
  }
}

public struct AgentTextPatch: Codable, Equatable, Sendable {
  public let beforeText: String
  public let afterText: String
  public let range: NSRange
  public let prefixContext: String
  public let suffixContext: String

  public init(
    beforeText: String,
    afterText: String,
    range: NSRange,
    prefixContext: String,
    suffixContext: String
  ) {
    self.beforeText = beforeText
    self.afterText = afterText
    self.range = range
    self.prefixContext = prefixContext
    self.suffixContext = suffixContext
  }
}

public struct AgentParsedTask: Equatable, Sendable {
  public let line: Int
  public let indentation: String
  public let completed: Bool
  public let text: String

  public init(
    line: Int,
    indentation: String,
    completed: Bool,
    text: String
  ) {
    self.line = line
    self.indentation = indentation
    self.completed = completed
    self.text = text
  }
}

public struct AgentMutationDraft: Equatable, Sendable {
  public let body: String
  public let patch: AgentTextPatch
  public let updatedTask: AgentParsedTask?

  public init(
    body: String,
    patch: AgentTextPatch,
    updatedTask: AgentParsedTask? = nil
  ) {
    self.body = body
    self.patch = patch
    self.updatedTask = updatedTask
  }
}
