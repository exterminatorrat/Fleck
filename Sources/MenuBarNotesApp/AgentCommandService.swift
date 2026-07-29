#if os(macOS)
  import CryptoKit
  import Foundation
  import MenuBarNotesCore

  struct AgentChangeFeedback: Equatable, Sendable {
    let changeID: UUID
    let noteID: UUID
    let noteTitle: String
    let actor: AgentActivityActor
    let resultingRevision: UInt64
    let createdAt: Date
  }

  @MainActor
  protocol AgentWorkspaceStateAccess: AnyObject {
    var workspace: Workspace { get }
    var persistenceGeneration: UInt64 { get }
    var preferences: AppPreferences { get }
    var isAgentWorkspaceAvailable: Bool { get }
    var agentCommitProofs: [AgentWorkspaceCommitProof] { get }
    func flushPendingPersistenceForAgent() async throws
    func commitAgentWorkspace(
      _ workspace: Workspace,
      expectedGeneration: UInt64,
      commitProof: AgentWorkspaceCommitProof
    ) throws
    func publishAgentFeedback(_ feedback: AgentChangeFeedback)
  }

  protocol AgentProfileAuthorizing: Sendable {
    func authorize(
      profileID: UUID,
      credential: Data
    ) async throws -> AgentIntegrationProfile
  }

  extension AgentProfileStore: AgentProfileAuthorizing {}

  protocol AgentActivityPersisting: Sendable {
    func prepare(_ transaction: PreparedAgentTransaction) throws
    func commit(changeID: UUID, receipt: AgentWriteReceipt) throws
    func abort(changeID: UUID) throws
    func priorReceipt(
      actor: AgentActivityActor,
      operationID: UUID
    ) -> AgentWriteReceipt?
    func list(
      profileID: UUID?,
      visibleNoteIDs: Set<UUID>
    ) -> [AgentActivityRecord]
    func record(id: UUID) -> AgentActivityRecord?
    func reconcile(
      workspace: Workspace,
      commitProofs: [AgentWorkspaceCommitProof]
    ) throws
  }

  extension AgentActivityStore: AgentActivityPersisting {}

  @MainActor
  final class AgentCommandService {
    private struct BodyLine {
      let text: String
      let delimiter: String
    }

    private struct PendingWrite {
      let candidate: Workspace
      let transaction: PreparedAgentTransaction
      let proof: AgentWorkspaceCommitProof
      let receipt: AgentWriteReceipt
    }

    private let state: any AgentWorkspaceStateAccess
    private let profileStore: any AgentProfileAuthorizing
    private let activityStore: any AgentActivityPersisting
    private let taskHandleCodec: AgentTaskHandleCodec
    private let now: @Sendable () -> Date
    private var commandTail = Task<Void, Never> {}

    init(
      state: any AgentWorkspaceStateAccess,
      profileStore: any AgentProfileAuthorizing,
      activityStore: any AgentActivityPersisting,
      taskHandleCodec: AgentTaskHandleCodec = AgentTaskHandleCodec(),
      now: @escaping @Sendable () -> Date = Date.init
    ) {
      self.state = state
      self.profileStore = profileStore
      self.activityStore = activityStore
      self.taskHandleCodec = taskHandleCodec
      self.now = now
    }

    func execute(
      profileID: UUID,
      credential: Data,
      command: AgentWorkspaceCommand
    ) async throws -> AgentWorkspaceResponse {
      do {
        return try await enqueue { [self] in
          let profile: AgentIntegrationProfile
          do {
            profile = try await profileStore.authorize(
              profileID: profileID,
              credential: credential
            )
          } catch let error as AgentWorkspaceError {
            throw error
          } catch {
            throw AgentWorkspaceError(code: .permissionRevoked)
          }
          try requireAvailable()
          let actor = AgentActivityActor.integration(
            profileID: profile.id,
            displayName: profile.displayName
          )
          try reconcile()
          if let operationID = command.operationID,
            let receipt = activityStore.priorReceipt(
              actor: actor,
              operationID: operationID
            )
          {
            return command.isUndo ? .undo(receipt: receipt) : .write(receipt: receipt)
          }
          return try await perform(
            command,
            actor: actor,
            profileID: profile.id
          )
        }
      } catch let error as AgentWorkspaceError {
        throw error
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }
    }

    func executeLocalUndo(
      changeID: UUID,
      expectedRevision: UInt64,
      operationID: UUID
    ) async throws -> AgentWorkspaceResponse {
      do {
        return try await enqueue { [self] in
          try requireAvailable()
          try reconcile()
          let actor = AgentActivityActor.localUser
          if let receipt = activityStore.priorReceipt(
            actor: actor,
            operationID: operationID
          ) {
            return .undo(receipt: receipt)
          }
          try await state.flushPendingPersistenceForAgent()
          let generation = state.persistenceGeneration
          guard
            let record = activityStore.record(id: changeID),
            state.workspace.selectedNoteID == record.noteID,
            let note = state.workspace.notes.first(where: {
              $0.id == record.noteID
            })
          else {
            throw AgentWorkspaceError(code: .unsafeUndo)
          }
          guard note.revision == expectedRevision else {
            throw AgentWorkspaceError(code: .revisionConflict)
          }
          let draft = try undoDraft(for: record, in: note)
          let sourceOperation = record.sourceOperation ?? record.operation
          let pending = try pendingWrite(
            draft: draft,
            operation: .undoChange,
            operationID: operationID,
            actor: actor,
            originatingActor: record.originatingActor ?? record.actor,
            sourceOperation: sourceOperation,
            checklistFormatting: checklistFormatting(forUndoing: sourceOperation),
            note: note,
            workspace: state.workspace,
            preferences: state.preferences
          )
          return try commit(
            pending,
            capturedGeneration: generation,
            expectedRevision: expectedRevision,
            responseIsUndo: true
          )
        }
      } catch let error as AgentWorkspaceError {
        throw error
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }
    }

    private func enqueue(
      _ operation: @escaping @MainActor () async throws -> AgentWorkspaceResponse
    ) async throws -> AgentWorkspaceResponse {
      let predecessor = commandTail
      let task = Task { @MainActor in
        await predecessor.value
        return try await operation()
      }
      commandTail = Task { @MainActor in
        _ = try? await task.value
      }
      return try await task.value
    }

    private func perform(
      _ command: AgentWorkspaceCommand,
      actor: AgentActivityActor,
      profileID: UUID
    ) async throws -> AgentWorkspaceResponse {
      switch command {
      case .listSharedNotes:
        return .sharedNotes(
          notes: state.workspace.notes
            .filter(\.agentAccess)
            .map {
              AgentNoteSummary(
                noteID: $0.id,
                title: $0.displayTitle,
                revision: $0.revision,
                modifiedAt: $0.modifiedAt
              )
            }
        )
      case .readNote(let request):
        let note = try sharedNote(request.noteID)
        return .note(page: try notePage(note, request: request))
      case .listTasks(let request):
        let note = try sharedNote(request.noteID)
        return .tasks(tasks: try taskSummaries(note))
      case .listActivity:
        let visible = Set(
          state.workspace.notes.filter(\.agentAccess).map(\.id)
        )
        let records = activityStore.list(
          profileID: profileID,
          visibleNoteIDs: visible
        )
        return .activity(
          entries: records.map { record in
            let note = state.workspace.notes.first {
              $0.id == record.noteID
            }
            return AgentActivitySummary(
              changeID: record.changeID,
              noteID: record.noteID,
              noteTitle: record.noteTitle,
              actor: record.actor,
              originatingActor: record.originatingActor,
              createdAt: record.createdAt,
              operation: record.operation,
              patch: record.patch,
              previousRevision: record.previousRevision,
              resultingRevision: record.resultingRevision,
              canUndo: note.map {
                (try? undoDraft(for: record, in: $0)) != nil
              } ?? false
            )
          }
        )
      case .undoChange(let request):
        return try await performAuthorizedUndo(
          request,
          actor: actor,
          profileID: profileID
        )
      default:
        return try await performWrite(command, actor: actor)
      }
    }

    private func performWrite(
      _ command: AgentWorkspaceCommand,
      actor: AgentActivityActor
    ) async throws -> AgentWorkspaceResponse {
      try await state.flushPendingPersistenceForAgent()
      let generation = state.persistenceGeneration
      let workspace = state.workspace
      let context = try command.writeContext
      let note = try sharedNote(context.noteID, in: workspace)
      guard note.revision == context.expectedRevision else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }

      let operation: AgentActivityOperation
      let draft: AgentMutationDraft
      switch command {
      case .appendText(let request):
        operation = .appendText
        draft = try AgentNoteMutationEngine.append(
          text: request.text,
          to: note.body
        )
      case .insertText(let request):
        operation = .insertText
        draft = try AgentNoteMutationEngine.insert(
          text: request.text,
          beforeLine: request.beforeLine,
          in: note.body
        )
      case .replaceLines(let request):
        operation = .replaceLines
        draft = try AgentNoteMutationEngine.replaceLines(
          in: note.body,
          startLine: request.startLine,
          endLine: request.endLine,
          expectedTextSHA256: request.expectedTextSHA256,
          replacement: request.text
        )
      case .addTask(let request):
        operation = .addTask
        let after = try request.afterTaskHandle.map {
          try task(from: $0, note: note)
        }
        draft = try AgentNoteMutationEngine.addTask(
          text: request.text,
          after: after,
          in: note.body
        )
      case .renameTask(let request):
        operation = .renameTask
        draft = try AgentNoteMutationEngine.renameTask(
          try task(from: request.taskHandle, note: note),
          text: request.text,
          in: note.body
        )
      case .setTaskState(let request):
        operation = .setTaskState
        draft = try AgentNoteMutationEngine.setTaskState(
          try task(from: request.taskHandle, note: note),
          completed: request.completed,
          in: note.body
        )
      case .removeTask(let request):
        operation = .removeTask
        draft = try AgentNoteMutationEngine.removeTask(
          try task(from: request.taskHandle, note: note),
          in: note.body
        )
      default:
        throw AgentWorkspaceError(code: .invalidOperation)
      }

      let pending = try pendingWrite(
        draft: draft,
        operation: operation,
        operationID: context.operationID,
        actor: actor,
        note: note,
        workspace: workspace,
        preferences: state.preferences
      )
      return try commit(
        pending,
        capturedGeneration: generation,
        expectedRevision: context.expectedRevision,
        responseIsUndo: false
      )
    }

    private func performAuthorizedUndo(
      _ request: AgentWorkspaceCommand.UndoChangeRequest,
      actor: AgentActivityActor,
      profileID: UUID
    ) async throws -> AgentWorkspaceResponse {
      try await state.flushPendingPersistenceForAgent()
      let generation = state.persistenceGeneration
      guard
        let record = activityStore.record(id: request.changeID),
        case .integration(let recordProfileID, _) = record.actor,
        recordProfileID == profileID
      else {
        throw AgentWorkspaceError(code: .unsafeUndo)
      }
      let note = try sharedNote(record.noteID)
      guard note.revision == request.expectedRevision else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      let draft = try undoDraft(for: record, in: note)
      let sourceOperation = record.sourceOperation ?? record.operation
      let pending = try pendingWrite(
        draft: draft,
        operation: .undoChange,
        operationID: request.operationID,
        actor: actor,
        originatingActor: record.originatingActor ?? record.actor,
        sourceOperation: sourceOperation,
        checklistFormatting: checklistFormatting(forUndoing: sourceOperation),
        note: note,
        workspace: state.workspace,
        preferences: state.preferences
      )
      return try commit(
        pending,
        capturedGeneration: generation,
        expectedRevision: request.expectedRevision,
        responseIsUndo: true
      )
    }

    private func pendingWrite(
      draft: AgentMutationDraft,
      operation: AgentActivityOperation,
      operationID: UUID,
      actor: AgentActivityActor,
      originatingActor: AgentActivityActor? = nil,
      sourceOperation: AgentActivityOperation? = nil,
      checklistFormatting: AgentChecklistFormattingIntent? = nil,
      note: Note,
      workspace: Workspace,
      preferences: AppPreferences
    ) throws -> PendingWrite {
      let changed = try AgentRichTextMutator.applying(
        draft,
        operation: operation,
        checklistFormatting: checklistFormatting,
        to: note,
        preferences: preferences,
        now: now()
      )
      var candidate = workspace
      guard let index = candidate.notes.firstIndex(where: { $0.id == note.id })
      else {
        throw noteNotFound()
      }
      candidate.notes[index] = changed
      let changeID = UUID()
      let taskHandle = try draft.updatedTask.map {
        try taskHandleCodec.encode(
          AgentTaskReference(
            noteID: note.id,
            revision: changed.revision,
            line: $0.line,
            checklistLine: line($0.line, in: changed.body)
          )
        )
      }
      let transaction = PreparedAgentTransaction(
        changeID: changeID,
        noteID: note.id,
        noteTitle: note.displayTitle,
        actor: actor,
        originatingActor: originatingActor,
        operationID: operationID,
        createdAt: now(),
        operation: operation,
        patch: draft.patch,
        previousRevision: note.revision,
        resultingRevision: changed.revision,
        resultingBodySHA256: bodySHA256(changed.body),
        taskHandle: taskHandle,
        sourceOperation: sourceOperation
      )
      let receipt = AgentWriteReceipt(
        changeID: changeID,
        noteID: note.id,
        previousRevision: note.revision,
        resultingRevision: changed.revision,
        taskHandle: taskHandle
      )
      let proof = AgentWorkspaceCommitProof(
        changeID: changeID,
        noteID: note.id,
        resultingRevision: changed.revision,
        bodySHA256: transaction.resultingBodySHA256,
        actor: actor,
        operationID: operationID,
        expiresAt: transaction.expiresAt
      )
      return PendingWrite(
        candidate: candidate,
        transaction: transaction,
        proof: proof,
        receipt: receipt
      )
    }

    private func checklistFormatting(
      forUndoing operation: AgentActivityOperation
    ) -> AgentChecklistFormattingIntent {
      switch operation {
      case .renameTask, .setTaskState, .removeTask:
        return .normalizePatchedLine
      default:
        return .none
      }
    }

    private func undoDraft(
      for record: AgentActivityRecord,
      in note: Note
    ) throws -> AgentMutationDraft {
      guard note.revision >= record.resultingRevision else {
        throw AgentWorkspaceError(code: .unsafeUndo)
      }
      return try AgentUndoEngine.draft(
        inverting: record.patch,
        in: note.body
      )
    }

    private func commit(
      _ pending: PendingWrite,
      capturedGeneration: UInt64,
      expectedRevision: UInt64,
      responseIsUndo: Bool
    ) throws -> AgentWorkspaceResponse {
      do {
        try activityStore.prepare(pending.transaction)
      } catch let error as AgentWorkspaceError {
        throw error
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }

      var workspaceCommitted = false
      do {
        guard
          state.persistenceGeneration == capturedGeneration,
          state.workspace.notes.first(where: {
            $0.id == pending.transaction.noteID
          })?.revision == expectedRevision
        else {
          throw AgentWorkspaceError(code: .revisionConflict)
        }
        try state.commitAgentWorkspace(
          pending.candidate,
          expectedGeneration: capturedGeneration,
          commitProof: pending.proof
        )
        workspaceCommitted = true
        try activityStore.commit(
          changeID: pending.transaction.changeID,
          receipt: pending.receipt
        )
      } catch let error as AgentWorkspaceError {
        if workspaceCommitted {
          throw AgentWorkspaceError(code: .internalSaveFailure)
        }
        try? activityStore.abort(changeID: pending.transaction.changeID)
        throw error
      } catch {
        if !workspaceCommitted {
          try? activityStore.abort(changeID: pending.transaction.changeID)
        }
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }

      state.publishAgentFeedback(
        AgentChangeFeedback(
          changeID: pending.transaction.changeID,
          noteID: pending.transaction.noteID,
          noteTitle: pending.transaction.noteTitle,
          actor: pending.transaction.actor,
          resultingRevision: pending.transaction.resultingRevision,
          createdAt: pending.transaction.createdAt
        )
      )
      return responseIsUndo
        ? .undo(receipt: pending.receipt)
        : .write(receipt: pending.receipt)
    }

    private func reconcile() throws {
      do {
        try activityStore.reconcile(
          workspace: state.workspace,
          commitProofs: state.agentCommitProofs
        )
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }
    }

    private func sharedNote(
      _ id: UUID,
      in workspace: Workspace? = nil
    ) throws -> Note {
      let workspace = workspace ?? state.workspace
      guard
        let note = workspace.notes.first(where: { $0.id == id }),
        note.agentAccess
      else {
        throw noteNotFound()
      }
      return note
    }

    private func notePage(
      _ note: Note,
      request: AgentWorkspaceCommand.ReadNoteRequest
    ) throws -> AgentNotePage {
      let lines = bodyLines(note.body)
      let start = request.startLine ?? 1
      let maximum = request.maxLines ?? lines.count
      guard start > 0, maximum > 0, start <= lines.count else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      let end = min(lines.count, start + maximum - 1)
      var pageBody = ""
      for index in (start - 1)..<end {
        pageBody += lines[index].text
        if index < end - 1 {
          pageBody += lines[index].delimiter
        }
      }
      return AgentNotePage(
        noteID: note.id,
        title: note.displayTitle,
        revision: note.revision,
        body: pageBody,
        startLine: start,
        endLine: end,
        totalLineCount: lines.count,
        nextLine: end < lines.count ? end + 1 : nil,
        modifiedAt: note.modifiedAt
      )
    }

    private func taskSummaries(_ note: Note) throws -> [AgentTaskSummary] {
      try AgentNoteMutationEngine.tasks(in: note.body).map { task in
        AgentTaskSummary(
          taskHandle: try taskHandleCodec.encode(
            AgentTaskReference(
              noteID: note.id,
              revision: note.revision,
              line: task.line,
              checklistLine: line(task.line, in: note.body)
            )
          ),
          text: task.text,
          completed: task.completed,
          line: task.line,
          indentation: task.indentation
        )
      }
    }

    private func task(from handle: String, note: Note) throws -> AgentParsedTask {
      let reference = try taskHandleCodec.decode(
        handle,
        noteID: note.id,
        revision: note.revision
      )
      let checklistLine = line(reference.line, in: note.body)
      _ = try taskHandleCodec.decode(
        handle,
        noteID: note.id,
        revision: note.revision,
        checklistLine: checklistLine
      )
      guard
        let task = AgentNoteMutationEngine.tasks(in: note.body)
          .first(where: { $0.line == reference.line })
      else {
        throw AgentWorkspaceError(code: .taskHandleExpired)
      }
      return task
    }

    private func line(_ number: Int, in body: String) -> String {
      let lines = bodyLines(body)
      guard number > 0, number <= lines.count else { return "" }
      return lines[number - 1].text
    }

    private func bodyLines(_ body: String) -> [BodyLine] {
      let source = body as NSString
      guard source.length > 0 else {
        return [BodyLine(text: "", delimiter: "")]
      }
      var lines: [BodyLine] = []
      var start = 0
      while true {
        var cursor = start
        while cursor < source.length,
          source.character(at: cursor) != 10,
          source.character(at: cursor) != 13
        {
          cursor += 1
        }
        if cursor == source.length {
          lines.append(
            BodyLine(
              text: source.substring(
                with: NSRange(
                  location: start,
                  length: source.length - start
                )
              ),
              delimiter: ""
            )
          )
          break
        }
        let delimiterStart = cursor
        if source.character(at: cursor) == 13,
          cursor + 1 < source.length,
          source.character(at: cursor + 1) == 10
        {
          cursor += 1
        }
        lines.append(
          BodyLine(
            text: source.substring(
              with: NSRange(
                location: start,
                length: delimiterStart - start
              )
            ),
            delimiter: source.substring(
              with: NSRange(
                location: delimiterStart,
                length: cursor - delimiterStart + 1
              )
            )
          )
        )
        start = cursor + 1
        if start == source.length {
          lines.append(BodyLine(text: "", delimiter: ""))
          break
        }
      }
      return lines
    }

    private func requireAvailable() throws {
      guard state.isAgentWorkspaceAvailable else {
        throw AgentWorkspaceError(
          code: .motesUnavailable,
          recoveryAction: "Reopen Fleck after resolving its workspace storage."
        )
      }
    }

    private func noteNotFound() -> AgentWorkspaceError {
      AgentWorkspaceError(code: .noteNotFound)
    }

    private func bodySHA256(_ body: String) -> String {
      SHA256.hash(data: Data(body.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    }
  }

  extension AgentWorkspaceCommand {
    fileprivate var operationID: UUID? {
      switch self {
      case .appendText(let request): request.context.operationID
      case .insertText(let request): request.context.operationID
      case .replaceLines(let request): request.context.operationID
      case .addTask(let request): request.context.operationID
      case .renameTask(let request): request.context.operationID
      case .setTaskState(let request): request.context.operationID
      case .removeTask(let request): request.context.operationID
      case .undoChange(let request): request.operationID
      default: nil
      }
    }

    fileprivate var writeContext: AgentWriteContext {
      get throws {
        switch self {
        case .appendText(let request): request.context
        case .insertText(let request): request.context
        case .replaceLines(let request): request.context
        case .addTask(let request): request.context
        case .renameTask(let request): request.context
        case .setTaskState(let request): request.context
        case .removeTask(let request): request.context
        default: throw AgentWorkspaceError(code: .invalidOperation)
        }
      }
    }

    fileprivate var isUndo: Bool {
      if case .undoChange = self { return true }
      return false
    }
  }
#endif
