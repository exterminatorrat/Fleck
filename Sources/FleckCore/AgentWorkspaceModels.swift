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
}

public struct AgentWorkspaceError: Codable, Equatable, Error, Sendable {
  public let code: AgentWorkspaceErrorCode
  public let recoveryAction: String?

  public init(code: AgentWorkspaceErrorCode, recoveryAction: String? = nil) {
    self.code = code
    self.recoveryAction = recoveryAction
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
