#if os(macOS)
  import CryptoKit
  import Foundation
  import FleckCore

  struct AgentChangeFeedback: Equatable, Sendable {
    let changeID: UUID
    let noteID: UUID
    let noteTitle: String
    let actor: AgentActivityActor
    let resultingRevision: UInt64
    let createdAt: Date
  }

  @MainActor
  protocol AgentWorkspaceStateAccess: AnyObject, Sendable {
    var workspace: Workspace { get }
    var persistenceGeneration: UInt64 { get }
    var preferences: AppPreferences { get }
    var isAgentWorkspaceAvailable: Bool { get }
    var agentCommitProofs: [AgentWorkspaceCommitProof] { get }
    func refreshAgentEventMonitoring() async
    func flushPendingPersistenceForAgent() async throws
    func commitAgentWorkspace(
      _ workspace: Workspace,
      expectedGeneration: UInt64,
      commitProof: AgentWorkspaceCommitProof
    ) throws
    func publishAgentFeedback(_ feedback: AgentChangeFeedback)
    func publishAgentRequestEvent(_ event: AgentRequestEvent)
  }

  extension AgentWorkspaceStateAccess {
    func refreshAgentEventMonitoring() async {}
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

  private final class AgentCommandQueueRelease: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
      await withCheckedContinuation { continuation in
        let resumeImmediately = lock.withLock {
          guard !released else { return true }
          self.continuation = continuation
          return false
        }
        if resumeImmediately { continuation.resume() }
      }
    }

    func release() {
      let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
        guard !released else { return nil }
        released = true
        defer { self.continuation = nil }
        return self.continuation
      }
      continuation?.resume()
    }
  }

  @MainActor
  final class AgentCommandService {
    private struct BodyLine {
      let text: String
      let delimiter: String
    }

    private struct RequestContext {
      let workspace: Workspace
      let temporaryExclusionGeneration: UUID?
    }

    private struct PendingWrite {
      let candidate: Workspace
      let transaction: PreparedAgentTransaction
      let proof: AgentWorkspaceCommitProof
      let receipt: AgentWriteReceipt
    }

    @MainActor
    private final class ResponseLeaseHolder {
      private var lease: AgentEventResponseLease?

      func install(_ lease: AgentEventResponseLease) {
        precondition(self.lease == nil)
        self.lease = lease
      }

      func complete(delivered: Bool) async {
        guard let lease else { return }
        self.lease = nil
        await lease.complete(delivered: delivered)
      }

      func takeDisposition() -> (@Sendable (Bool) async -> Void)? {
        guard let lease else { return nil }
        self.lease = nil
        return { await lease.complete(delivered: $0) }
      }
    }

    private let state: any AgentWorkspaceStateAccess
    private let profileStore: any AgentProfileAuthorizing
    private let capabilityAuthority: any AgentCapabilityAuthorizing
    private let activityStore: any AgentActivityPersisting
    private let eventService: AgentEventSubscriptionService?
    private let eventRuntime: AgentEventMonitoringRuntime?
    private let taskHandleCodec: AgentTaskHandleCodec
    private let now: @Sendable () -> Date
    private var commandTail = Task<Void, Never> {}

    init(
      state: any AgentWorkspaceStateAccess,
      profileStore: any AgentProfileAuthorizing,
      activityStore: any AgentActivityPersisting,
      capabilityAuthority: any AgentCapabilityAuthorizing = AgentCapabilityAuthority(),
      eventService: AgentEventSubscriptionService? = nil,
      eventRuntime: AgentEventMonitoringRuntime? = nil,
      taskHandleCodec: AgentTaskHandleCodec = AgentTaskHandleCodec(),
      now: @escaping @Sendable () -> Date = Date.init
    ) {
      self.state = state
      self.profileStore = profileStore
      self.capabilityAuthority = capabilityAuthority
      self.activityStore = activityStore
      self.eventService = eventService
      self.eventRuntime = eventRuntime
      self.taskHandleCodec = taskHandleCodec
      self.now = now
    }

    func execute(
      profileID: UUID,
      credential: Data,
      command: AgentWorkspaceCommand
    ) async throws -> AgentWorkspaceResponse {
      try await executeWithResponseDisposition(
        profileID: profileID,
        credential: credential,
        command: command,
        deferResponseDisposition: false
      ).response
    }

    func executeForIPC(
      profileID: UUID,
      credential: Data,
      command: AgentWorkspaceCommand
    ) async throws -> AgentIPCServer.ExecutionResult {
      try await executeWithResponseDisposition(
        profileID: profileID,
        credential: credential,
        command: command,
        deferResponseDisposition: true
      )
    }

    private func executeWithResponseDisposition(
      profileID: UUID,
      credential: Data,
      command: AgentWorkspaceCommand,
      deferResponseDisposition: Bool
    ) async throws -> AgentIPCServer.ExecutionResult {
      do {
        let cancellationAware: Bool
        if case .prepareEventSubscription = command {
          cancellationAware = true
        } else {
          cancellationAware = false
        }
        return try await enqueue(
          cancellationAware: cancellationAware
        ) { [self] releaseCommandQueue in
          let responseLeaseHolder = ResponseLeaseHolder()
          var request: (id: UUID, profileID: UUID)?

          @MainActor func beginRequest(profileID: UUID) {
            guard request == nil else { return }
            let requestID = UUID()
            request = (requestID, profileID)
            state.publishAgentRequestEvent(
              .began(requestID: requestID, profileID: profileID)
            )
          }

          @MainActor func finishRequest(_ outcome: AgentRequestOutcome) {
            guard let request else { return }
            state.publishAgentRequestEvent(
              .finished(
                requestID: request.id,
                profileID: request.profileID,
                outcome: outcome
              )
            )
          }

          do {
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
            let requestContext = captureRequestContext()
            let snapshot = try await capabilityAuthority.snapshot(
              profileID: profile.id,
              workspace: requestContext.workspace
            )
            try requireRequestContext(requestContext)
            try requireCapability(for: command, snapshot: snapshot)
            try await assertCurrent(
              profileID: profile.id,
              snapshot: snapshot,
              requestContext: requestContext
            )
            if let operationID = command.operationID,
              let receipt = activityStore.priorReceipt(
                actor: actor,
                operationID: operationID
              )
            {
              _ = try authorizedNote(
                receipt.noteID,
                noteIDs: snapshot.writableNoteIDs,
                in: requestContext.workspace
              )
              try await assertCurrent(
                profileID: profile.id,
                snapshot: snapshot,
                requestContext: requestContext
              )
              beginRequest(profileID: profile.id)
              let response: AgentWorkspaceResponse =
                command.isUndo ? .undo(receipt: receipt) : .write(receipt: receipt)
              try requireRequestContext(requestContext)
              finishRequest(.succeeded)
              return AgentIPCServer.ExecutionResult(response: response)
            }
            let response = try await perform(
              command,
              actor: actor,
              profileID: profile.id,
              credential: credential,
              snapshot: snapshot,
              requestContext: requestContext,
              beginRequest: { beginRequest(profileID: profile.id) },
              releaseCommandQueue: releaseCommandQueue,
              responseLeaseHolder: responseLeaseHolder
            )
            if command.operationID == nil {
              if case .prepareEventSubscription = command {
                try requireRequestAvailabilityAndExclusion(requestContext)
              } else {
                try requireRequestContext(requestContext)
              }
            } else {
              try requireRequestAvailabilityAndExclusion(requestContext)
            }
            try Task.checkCancellation()
            finishRequest(.succeeded)
            if deferResponseDisposition {
              return AgentIPCServer.ExecutionResult(
                response: response,
                responseDisposition: responseLeaseHolder.takeDisposition()
              )
            }
            await responseLeaseHolder.complete(delivered: true)
            return AgentIPCServer.ExecutionResult(response: response)
          } catch let cancellation as CancellationError {
            await responseLeaseHolder.complete(delivered: false)
            finishRequest(.cancelled)
            throw cancellation
          } catch let error as AgentEventCallbackVerificationError where error == .cancelled {
            await responseLeaseHolder.complete(delivered: false)
            finishRequest(.cancelled)
            throw error
          } catch {
            await responseLeaseHolder.complete(delivered: false)
            finishRequest(.failed)
            throw error
          }
        }
      } catch let error as AgentWorkspaceError {
        throw error
      } catch let error as AgentEventSubscriptionError {
        switch error {
        case .invalidConfiguration:
          throw AgentWorkspaceError(code: .invalidPayload)
        case .capacityExceeded:
          throw AgentWorkspaceError(code: .writeTooLarge)
        case .storageFailure:
          throw AgentWorkspaceError(code: .internalSaveFailure)
        }
      } catch let error as AgentEventCallbackVerificationError where error == .cancelled {
        throw CancellationError()
      } catch let error as AgentEventCallbackVerificationError {
        throw try Self.mapCallbackVerificationFailure(error)
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }
    }

    static func mapCallbackVerificationFailure(
      _ failure: AgentEventCallbackVerificationError
    ) throws -> AgentWorkspaceError {
      switch failure {
      case .notAuthorized:
        return AgentWorkspaceError(code: .capabilityDenied)
      case .verificationInProgress, .keyUnavailable, .randomUnavailable, .busy, .storageFailure:
        return AgentWorkspaceError(code: .internalSaveFailure)
      case .capacityExceeded:
        return AgentWorkspaceError(code: .writeTooLarge)
      case .verificationFailed:
        return AgentWorkspaceError.callbackEndpointFailure(reason: .challengeFailed)
      case .timedOut:
        return AgentWorkspaceError.callbackEndpointFailure(reason: .timedOut)
      case .transportFailure:
        return AgentWorkspaceError.callbackEndpointFailure(reason: .connectionFailed)
      case .cancelled:
        throw CancellationError()
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
          return try await commit(
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

    private func enqueue<Result: Sendable>(
      _ operation: @escaping @MainActor () async throws -> Result
    ) async throws -> Result {
      try await enqueue(cancellationAware: false) { _ in try await operation() }
    }

    private func enqueue<Result: Sendable>(
      cancellationAware: Bool,
      _ operation: @escaping @MainActor (@Sendable () -> Void) async throws -> Result
    ) async throws -> Result {
      let predecessor = commandTail
      let release = AgentCommandQueueRelease()
      let task = Task { @MainActor in
        await predecessor.value
        defer { release.release() }
        if cancellationAware { try Task.checkCancellation() }
        let releaseCommandQueue: @Sendable () -> Void = { release.release() }
        return try await operation(releaseCommandQueue)
      }
      commandTail = Task { @MainActor in
        await release.wait()
      }
      if cancellationAware {
        return try await withTaskCancellationHandler {
          try await task.value
        } onCancel: {
          task.cancel()
        }
      }
      return try await task.value
    }

    private func perform(
      _ command: AgentWorkspaceCommand,
      actor: AgentActivityActor,
      profileID: UUID,
      credential: Data,
      snapshot: AgentAuthorizationSnapshot,
      requestContext: RequestContext,
      beginRequest: () -> Void,
      releaseCommandQueue: @Sendable () -> Void,
      responseLeaseHolder: ResponseLeaseHolder
    ) async throws -> AgentWorkspaceResponse {
      switch command {
      case .listSharedNotes:
        beginRequest()
        return try await checkedRead(
          .sharedNotes(
            notes: requestContext.workspace.notes
              .filter { snapshot.readableNoteIDs.contains($0.id) }
              .map {
                AgentNoteSummary(
                  noteID: $0.id,
                  title: $0.displayTitle,
                  revision: $0.revision,
                  modifiedAt: $0.modifiedAt
                )
              }
          ),
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
      case .readNote(let request):
        let note = try authorizedNote(
          request.noteID,
          noteIDs: snapshot.readableNoteIDs,
          in: requestContext.workspace
        )
        beginRequest()
        return try await checkedRead(
          .note(page: try notePage(note, request: request)),
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
      case .listTasks(let request):
        let note = try authorizedNote(
          request.noteID,
          noteIDs: snapshot.readableNoteIDs,
          in: requestContext.workspace
        )
        beginRequest()
        return try await checkedRead(
          .tasks(tasks: try taskSummaries(note)),
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
      case .listActivity:
        beginRequest()
        let records = activityStore.list(
          profileID: profileID,
          visibleNoteIDs: snapshot.readableNoteIDs
        )
        return try await checkedRead(
          .activity(
            entries: records.map { record in
              let note = requestContext.workspace.notes.first {
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
                canUndo: snapshot.availableCapabilities.contains(.undoChanges)
                  && snapshot.writableNoteIDs.contains(record.noteID)
                  && (note.map {
                    (try? undoDraft(for: record, in: $0)) != nil
                  } ?? false)
              )
            }
          ),
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
      case .undoChange(let request):
        return try await performAuthorizedUndo(
          request,
          actor: actor,
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext,
          beginRequest: beginRequest
        )
      case .getCapabilities:
        beginRequest()
        return try await checkedRead(
          .capabilities(
            summary: AgentCapabilitySummary(
              grantRevision: snapshot.grantRevision,
              availableCapabilities: snapshot.availableCapabilities
            )
          ),
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
      case .listEvents:
        beginRequest()
        let events: [AgentEventDescriptor]
        if let eventRuntime {
          events = try await eventRuntime.listEvents(
            profileID: profileID,
            workspace: requestContext.workspace
          )
        } else if let eventService {
          events = try await eventService.listEvents(
            profileID: profileID,
            workspace: requestContext.workspace
          )
        } else {
          throw AgentWorkspaceError(code: .invalidOperation)
        }
        let response = try await checkedRead(
          .events(events: events),
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
        try await reauthorize(profileID: profileID, credential: credential)
        try requireRequestContext(requestContext)
        return try await checkedRead(
          response,
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
      case .prepareEventSubscription(let request):
        guard eventRuntime != nil || eventService != nil else {
          throw AgentWorkspaceError(code: .invalidOperation)
        }
        beginRequest()
        let state = self.state
        let workspaceProvider: AgentEventWorkspaceProvider = {
          try await state.flushPendingPersistenceForAgent()
          try await MainActor.run {
            if self.eventRuntime == nil {
              try self.requireRequestContext(requestContext)
            } else {
              try self.requireRequestAvailabilityAndExclusion(requestContext)
            }
          }
          try await self.reauthorize(profileID: profileID, credential: credential)
          return try await MainActor.run {
            if self.eventRuntime == nil {
              try self.requireRequestContext(requestContext)
              return requestContext.workspace
            }
            try self.requireRequestAvailabilityAndExclusion(requestContext)
            return state.workspace
          }
        }
        if let eventRuntime {
          releaseCommandQueue()
          let verification = try await eventRuntime.prepareAndVerifySubscription(
            profileID: profileID,
            event: request.event,
            scope: request.scope,
            callbackURL: request.callbackURL,
            signingSecret: request.signingSecret,
            requestedTTLSeconds: request.ttl.requestedSeconds,
            expectedGrantRevision: snapshot.grantRevision,
            expectedTemporaryExclusionGeneration: requestContext.temporaryExclusionGeneration,
            workspaceProvider: workspaceProvider
          )
          responseLeaseHolder.install(verification.responseLease)
          await state.refreshAgentEventMonitoring()
          try await reauthorize(profileID: profileID, credential: credential)
          let scopeMembership = try await eventRuntime.assertCurrentEventScope(
            profileID: profileID,
            scope: request.scope,
            expectedGrantRevision: snapshot.grantRevision,
            expectedTemporaryExclusionGeneration: requestContext.temporaryExclusionGeneration,
            workspaceProvider: workspaceProvider
          )
          try await capabilityAuthority.assertCurrent(
            profileID: profileID,
            grantRevision: snapshot.grantRevision,
            expectedTemporaryExclusionGeneration: requestContext.temporaryExclusionGeneration
          )
          guard scopeMembership.matches(scope: request.scope, in: state.workspace) else {
            throw AgentWorkspaceError(code: .capabilityDenied)
          }
          guard verification.isCurrent() else {
            throw AgentWorkspaceError(code: .capabilityDenied)
          }
          try requireRequestAvailabilityAndExclusion(requestContext)
          return .verifiedEventSubscription(receipt: verification.receipt)
        }
        guard let eventService else {
          throw AgentWorkspaceError(code: .invalidOperation)
        }
        let receipt = try await eventService.createPending(
          profileID: profileID,
          event: request.event,
          scope: request.scope,
          callbackURL: request.callbackURL,
          signingSecret: request.signingSecret,
          requestedTTLSeconds: request.ttl.requestedSeconds,
          workspaceProvider: workspaceProvider,
          now: now()
        )
        try requireRequestContext(requestContext)
        try await assertCurrent(
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
        return .pendingEventSubscription(
          receipt: AgentEventPendingReceipt(
            subscriptionID: receipt.subscriptionID,
            expiresAt: receipt.expiresAt,
            revision: receipt.revision,
            grantRevision: receipt.grantRevision
          )
        )
      case .removeEventSubscription(let request):
        guard eventRuntime != nil || eventService != nil else {
          throw AgentWorkspaceError(code: .invalidOperation)
        }
        beginRequest()
        let callbackURL = try AgentEventSubscriptionIdentity.canonicalCallbackURL(
          request.callbackURL
        )
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: request.event,
          scope: request.scope,
          callbackURL: callbackURL
        )
        if let eventRuntime {
          try await eventRuntime.removeSubscription(subscriptionID: subscriptionID)
        } else if let eventService {
          try await eventService.remove(
            profileID: profileID,
            subscriptionID: subscriptionID
          )
        }
        await state.refreshAgentEventMonitoring()
        try requireRequestContext(requestContext)
        try await reauthorize(profileID: profileID, credential: credential)
        try requireRequestContext(requestContext)
        try await assertCurrent(
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext
        )
        return .eventUnsubscribed
      default:
        return try await performWrite(
          command,
          actor: actor,
          profileID: profileID,
          snapshot: snapshot,
          requestContext: requestContext,
          beginRequest: beginRequest
        )
      }
    }

    private func performWrite(
      _ command: AgentWorkspaceCommand,
      actor: AgentActivityActor,
      profileID: UUID,
      snapshot: AgentAuthorizationSnapshot,
      requestContext: RequestContext,
      beginRequest: () -> Void
    ) async throws -> AgentWorkspaceResponse {
      try await state.flushPendingPersistenceForAgent()
      try requireRequestContext(requestContext)
      let generation = state.persistenceGeneration
      let workspace = requestContext.workspace
      let context = try command.writeContext
      let note = try authorizedNote(
        context.noteID,
        noteIDs: snapshot.writableNoteIDs,
        in: workspace
      )
      guard note.revision == context.expectedRevision else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      beginRequest()

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
      return try await commit(
        pending,
        capturedGeneration: generation,
        expectedRevision: context.expectedRevision,
        responseIsUndo: false,
        profileID: profileID,
        grantRevision: snapshot.grantRevision,
        requestContext: requestContext
      )
    }

    private func performAuthorizedUndo(
      _ request: AgentWorkspaceCommand.UndoChangeRequest,
      actor: AgentActivityActor,
      profileID: UUID,
      snapshot: AgentAuthorizationSnapshot,
      requestContext: RequestContext,
      beginRequest: () -> Void
    ) async throws -> AgentWorkspaceResponse {
      try await state.flushPendingPersistenceForAgent()
      try requireRequestContext(requestContext)
      let generation = state.persistenceGeneration
      guard
        let record = activityStore.record(id: request.changeID),
        case .integration(let recordProfileID, _) = record.actor,
        recordProfileID == profileID
      else {
        throw AgentWorkspaceError(code: .unsafeUndo)
      }
      let note = try authorizedNote(
        record.noteID,
        noteIDs: snapshot.writableNoteIDs,
        in: requestContext.workspace
      )
      guard note.revision == request.expectedRevision else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      beginRequest()
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
        workspace: requestContext.workspace,
        preferences: state.preferences
      )
      return try await commit(
        pending,
        capturedGeneration: generation,
        expectedRevision: request.expectedRevision,
        responseIsUndo: true,
        profileID: profileID,
        grantRevision: snapshot.grantRevision,
        requestContext: requestContext
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
        originatingActor: transaction.originatingActor,
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
      responseIsUndo: Bool,
      profileID: UUID? = nil,
      grantRevision: UInt64? = nil,
      requestContext: RequestContext? = nil
    ) async throws -> AgentWorkspaceResponse {
      if let profileID, let grantRevision {
        if let requestContext {
          try await assertCurrent(
            profileID: profileID,
            grantRevision: grantRevision,
            requestContext: requestContext
          )
        } else {
          try await capabilityAuthority.assertCurrent(
            profileID: profileID,
            grantRevision: grantRevision
          )
        }
      }
      do {
        try activityStore.prepare(pending.transaction)
      } catch let error as AgentWorkspaceError {
        throw error
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }

      var workspaceCommitted = false
      do {
        if let profileID, let grantRevision {
          if let requestContext {
            try await assertCurrent(
              profileID: profileID,
              grantRevision: grantRevision,
              requestContext: requestContext
            )
          } else {
            try await capabilityAuthority.assertCurrent(
              profileID: profileID,
              grantRevision: grantRevision
            )
          }
        }
        if let requestContext {
          try requireRequestContext(requestContext)
        }
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

    private func requireCapability(
      for command: AgentWorkspaceCommand,
      snapshot: AgentAuthorizationSnapshot
    ) throws {
      switch command.capabilityRequirement {
      case .authenticated:
        return
      case .capability(let capability, _):
        guard snapshot.availableCapabilities.contains(capability) else {
          throw AgentWorkspaceError(code: .capabilityDenied)
        }
      }
    }

    private func reauthorize(profileID: UUID, credential: Data) async throws {
      do {
        let profile = try await profileStore.authorize(
          profileID: profileID,
          credential: credential
        )
        guard profile.id == profileID else {
          throw AgentWorkspaceError(code: .permissionRevoked)
        }
      } catch let error as AgentWorkspaceError {
        throw error
      } catch {
        throw AgentWorkspaceError(code: .permissionRevoked)
      }
    }

    private func checkedRead(
      _ response: AgentWorkspaceResponse,
      profileID: UUID,
      snapshot: AgentAuthorizationSnapshot,
      requestContext: RequestContext
    ) async throws -> AgentWorkspaceResponse {
      try await assertCurrent(
        profileID: profileID,
        snapshot: snapshot,
        requestContext: requestContext
      )
      return response
    }

    private func captureRequestContext() -> RequestContext {
      RequestContext(
        workspace: state.workspace,
        temporaryExclusionGeneration: capabilityAuthority
          .temporaryExclusionGeneration
      )
    }

    private func requireRequestContext(_ requestContext: RequestContext) throws {
      try requireRequestAvailabilityAndExclusion(requestContext)
      guard state.workspace == requestContext.workspace else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
    }

    private func requireRequestAvailabilityAndExclusion(
      _ requestContext: RequestContext
    ) throws {
      try requireAvailable()
      guard
        capabilityAuthority.temporaryExclusionGeneration
          == requestContext.temporaryExclusionGeneration
      else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
    }

    private func assertCurrent(
      profileID: UUID,
      snapshot: AgentAuthorizationSnapshot,
      requestContext: RequestContext
    ) async throws {
      try await assertCurrent(
        profileID: profileID,
        grantRevision: snapshot.grantRevision,
        requestContext: requestContext
      )
    }

    private func assertCurrent(
      profileID: UUID,
      grantRevision: UInt64,
      requestContext: RequestContext
    ) async throws {
      try await capabilityAuthority.assertCurrent(
        profileID: profileID,
        grantRevision: grantRevision,
        expectedTemporaryExclusionGeneration: requestContext
          .temporaryExclusionGeneration
      )
      try requireRequestContext(requestContext)
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

    private func authorizedNote(
      _ id: UUID,
      noteIDs: Set<UUID>,
      in workspace: Workspace? = nil
    ) throws -> Note {
      let workspace = workspace ?? state.workspace
      guard
        noteIDs.contains(id),
        let note = workspace.notes.first(where: { $0.id == id })
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
          code: .fleckUnavailable,
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
