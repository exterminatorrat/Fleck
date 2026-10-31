#if os(macOS)
  import FleckCore
  import Foundation

  enum AgentEventOwnerState: Equatable, Sendable {
    case awaitingApproval
    case awaitingVerification
    case enabled
    case paused
    case pausedCapacity
    case pausedHistory
    case retrying
    case stopped
    case expired
    case unavailable
  }

  struct AgentEventOwnerSummary: Identifiable, Equatable, Sendable {
    let id: String
    let profileID: UUID
    let event: AgentEventName
    let scope: AgentEventScope
    let callbackHost: String
    let state: AgentEventOwnerState
    let expiresAt: Date
    let lastReceiptAt: Date?
    let allowsAutomaticRenewal: Bool
    let consentGenerationID: UUID?
  }

  final class AgentEventResponseLease: @unchecked Sendable {
    private let lock = NSLock()
    private var disposition: (@Sendable (Bool) async -> Void)?

    init(disposition: @escaping @Sendable (Bool) async -> Void) {
      self.disposition = disposition
    }

    func complete(delivered: Bool) async {
      let disposition = lock.withLock {
        let disposition = self.disposition
        self.disposition = nil
        return disposition
      }
      if let disposition {
        await disposition(delivered)
      }
    }
  }

  struct AgentEventMonitoringVerificationObservation: Sendable {
    let receipt: AgentEventVerifiedSubscriptionReceipt
    let responseLease: AgentEventResponseLease
    private let remainsCurrent: @Sendable () -> Bool

    init(
      receipt: AgentEventVerifiedSubscriptionReceipt,
      responseLease: AgentEventResponseLease,
      remainsCurrent: @escaping @Sendable () -> Bool
    ) {
      self.receipt = receipt
      self.responseLease = responseLease
      self.remainsCurrent = remainsCurrent
    }

    func isCurrent() -> Bool {
      remainsCurrent()
    }
  }

  private enum AgentEventMonitoringRuntimeError: Error, Sendable {
    case ownerApprovalTimedOut
    case subscriptionChanged
  }

  struct AgentEventMonitoringRuntimeTestObservation: Sendable {
    let beforeInitialOwnerWait: @Sendable () async -> Void
    let ownerWaiterRegistered: @Sendable () -> Void
  }

  struct ScopeNoteMembership: Equatable, Sendable {
    let id: UUID
    let folderID: UUID?
    let agentAccess: Bool
  }

  enum ScopeMembership: Equatable, Sendable {
    case note(id: UUID, note: ScopeNoteMembership?)
    case folder(id: UUID, isPresent: Bool, notes: [ScopeNoteMembership])

    func matches(scope: AgentEventScope, in workspace: Workspace) -> Bool {
      self == Self.capture(scope, in: workspace)
    }

    static func capture(_ scope: AgentEventScope, in workspace: Workspace) -> ScopeMembership {
      switch scope {
      case .note(let noteID):
        return .note(
          id: noteID,
          note: workspace.notes.first(where: { $0.id == noteID }).map {
            ScopeNoteMembership(id: $0.id, folderID: $0.folderID, agentAccess: $0.agentAccess)
          }
        )
      case .folder(let folderID):
        return .folder(
          id: folderID,
          isPresent: workspace.folders.contains(where: { $0.id == folderID }),
          notes: workspace.notes
            .filter { $0.folderID == folderID }
            .map {
              ScopeNoteMembership(id: $0.id, folderID: $0.folderID, agentAccess: $0.agentAccess)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        )
      }
    }
  }

  private final class AgentEventMonitoringCommitSignal: @unchecked Sendable {
    let stream: AsyncStream<Void>
    private let lock = NSLock()
    private let continuation: AsyncStream<Void>.Continuation
    private var workspaceCommitPending = false

    init() {
      var capturedContinuation: AsyncStream<Void>.Continuation!
      stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
        capturedContinuation = $0
      }
      continuation = capturedContinuation
    }

    func signal(workspaceCommit: Bool = false) {
      lock.withLock {
        workspaceCommitPending = workspaceCommitPending || workspaceCommit
        _ = continuation.yield(())
      }
    }

    func consumeWorkspaceCommit() -> Bool {
      lock.withLock {
        defer { workspaceCommitPending = false }
        return workspaceCommitPending
      }
    }

    func finish() {
      lock.withLock { continuation.finish() }
    }
  }

  private final class AgentEventVerificationCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
      lock.withLock { cancelled = true }
    }

    var isCancelled: Bool {
      lock.withLock { cancelled }
    }
  }

  actor AgentEventMonitoringRuntime {
    private struct OwnerApprovalOrigin {
      let intentID: UUID
      var binding: AgentEventCallbackVerificationBinding?
      var initialApprovalSatisfied = false
    }

    private struct OwnerWaiter {
      let continuation: CheckedContinuation<Void, Error>
      let timeoutTask: Task<Void, Never>
      let originIntentID: UUID
    }

    private let subscriptionService: AgentEventSubscriptionService
    private let subscriptionStore: AgentEventSubscriptionStore
    private let monitoringService: AgentEventMonitoringService
    private let callbackVerificationStore: AgentEventCallbackVerificationStore
    private let outboxService: AgentEventOutboxService
    private let outboxStore: AgentEventOutboxStore
    private let deliveryLedgerStore: AgentEventDeliveryLedgerStore
    private let profileStore: AgentProfileStore
    private let authority: AgentCapabilityAuthority
    private let scopeAuthorization:
      @Sendable (UUID, AgentEventScope, Workspace) async throws -> UInt64
    private let afterSubscriptionCreation: @Sendable () async -> Void
    private let approvalObservationHook:
      AgentEventMonitoringRuntimeTestObservation?
    private let now: @Sendable () -> Date
    private let approvalWaitLimit: Duration
    private let commitSignal = AgentEventMonitoringCommitSignal()
    private let monotonicClock = ContinuousClock()
    private var workspaceProvider: AgentEventWorkspaceProvider?
    private var workerTask: Task<Void, Never>?
    private var scheduledWakeTask: Task<Void, Never>?
    private var activeDelivery:
      (
        subscriptionID: String,
        task: Task<AgentEventDeliverySenderResult?, Never>
      )?
    private var verificationCancellationActions: [String: [UUID: @Sendable () -> Void]] = [:]
    private var commandWaitCounts: [AgentEventCallbackVerificationBinding: Int] = [:]
    private var ownerApprovalOrigins: [String: [UUID: OwnerApprovalOrigin]] = [:]
    private var ownerWaiters: [String: [UUID: OwnerWaiter]] = [:]
    private var observedBindings: [String: AgentEventCallbackVerificationBinding] = [:]
    private var pendingCaptureSubscriptions: Set<String> = []
    private var lastDeliveryAttempt: [String: ContinuousClock.Instant] = [:]
    private var captureRetryAt: [String: ContinuousClock.Instant] = [:]
    private var roundRobinOffset = 0

    init(
      subscriptionService: AgentEventSubscriptionService,
      subscriptionStore: AgentEventSubscriptionStore,
      monitoringService: AgentEventMonitoringService,
      callbackVerificationStore: AgentEventCallbackVerificationStore,
      outboxService: AgentEventOutboxService,
      outboxStore: AgentEventOutboxStore,
      deliveryLedgerStore: AgentEventDeliveryLedgerStore,
      profileStore: AgentProfileStore,
      authority: AgentCapabilityAuthority,
      now: @escaping @Sendable () -> Date = Date.init,
      approvalWaitLimit: Duration = .seconds(60),
      scopeAuthorization:
        (@Sendable (UUID, AgentEventScope, Workspace) async throws -> UInt64)? = nil,
      afterSubscriptionCreation: (@Sendable () async -> Void)? = nil,
      approvalObservationHook:
        AgentEventMonitoringRuntimeTestObservation? = nil
    ) {
      self.subscriptionService = subscriptionService
      self.subscriptionStore = subscriptionStore
      self.monitoringService = monitoringService
      self.callbackVerificationStore = callbackVerificationStore
      self.outboxService = outboxService
      self.outboxStore = outboxStore
      self.deliveryLedgerStore = deliveryLedgerStore
      self.profileStore = profileStore
      self.authority = authority
      self.scopeAuthorization =
        scopeAuthorization ?? { profileID, scope, workspace in
          try await authority.authorizeEventObservation(
            profileID: profileID,
            scope: scope,
            workspace: workspace
          )
        }
      self.afterSubscriptionCreation = afterSubscriptionCreation ?? {}
      self.approvalObservationHook = approvalObservationHook
      self.now = now
      self.approvalWaitLimit = approvalWaitLimit
    }

    static func production(
      applicationSupportURL: URL,
      localStore: LocalStore,
      profileStore: AgentProfileStore,
      authority: AgentCapabilityAuthority,
      now: @escaping @Sendable () -> Date = Date.init
    ) -> AgentEventMonitoringRuntime {
      let directory =
        applicationSupportURL.appendingPathComponent(
          "AgentEventMonitoring",
          isDirectory: true
        )
      let subscriptionStore = AgentEventSubscriptionStore(
        fileURL: directory.appendingPathComponent("subscriptions.json")
      )
      let verificationStore = AgentEventCallbackVerificationStore(
        fileURL: directory.appendingPathComponent("verification.json"),
        now: now
      )
      let outboxStore = AgentEventOutboxStore(
        fileURL: directory.appendingPathComponent("outbox.json")
      )
      let deliveryLedgerStore = AgentEventDeliveryLedgerStore(
        fileURL: directory.appendingPathComponent("delivery-ledger.json"),
        now: now
      )
      let signingKeyStore = AgentEventSigningKeyStore()
      let subscriptionService = AgentEventSubscriptionService(
        authority: authority,
        store: subscriptionStore,
        signingKeyStore: signingKeyStore,
        clock: now
      )
      let outboxService = AgentEventOutboxService(
        store: outboxStore,
        localStore: localStore,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        authority: authority,
        coalescesNoteUpdateBursts: true
      )
      let callbackVerificationService = AgentEventCallbackVerificationService(
        authority: authority,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        signingKeyStore: signingKeyStore,
        verificationStore: verificationStore,
        now: now
      )
      let deliveryLedgerService = AgentEventDeliveryLedgerService(
        outboxStore: outboxStore,
        subscriptionStore: subscriptionStore,
        ledgerStore: deliveryLedgerStore
      )
      let authorizationService = AgentEventDeliveryAuthorizationService(
        authority: authority,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        verificationStore: verificationStore,
        outboxStore: outboxStore,
        ledgerStore: deliveryLedgerStore,
        now: now
      )
      let deliverySender = AgentEventDeliverySender(
        ledgerService: deliveryLedgerService,
        authorizationService: authorizationService,
        subscriptionStore: subscriptionStore,
        signingKeyStore: signingKeyStore,
        now: now,
        exchange: { callbackURL, headers, body in
          try await AgentEventHTTPTransport().post(
            callbackURL: callbackURL,
            headers: headers,
            body: body
          )
        }
      )
      let monitoringService = AgentEventMonitoringService(
        authority: authority,
        outboxService: outboxService,
        callbackVerificationService: callbackVerificationService,
        deliveryLedgerService: deliveryLedgerService,
        deliverySender: deliverySender
      )
      return AgentEventMonitoringRuntime(
        subscriptionService: subscriptionService,
        subscriptionStore: subscriptionStore,
        monitoringService: monitoringService,
        callbackVerificationStore: verificationStore,
        outboxService: outboxService,
        outboxStore: outboxStore,
        deliveryLedgerStore: deliveryLedgerStore,
        profileStore: profileStore,
        authority: authority,
        now: now
      )
    }

    func start(workspaceProvider: @escaping AgentEventWorkspaceProvider) {
      guard workerTask == nil else { return }
      self.workspaceProvider = workspaceProvider
      let stream = commitSignal.stream
      workerTask = Task { [weak self] in
        for await _ in stream {
          guard let self else { return }
          await self.drain()
        }
      }
      commitSignal.signal()
    }

    func stop() async {
      let worker = workerTask
      let delivery = activeDelivery?.task
      workerTask?.cancel()
      scheduledWakeTask?.cancel()
      scheduledWakeTask = nil
      delivery?.cancel()
      for cancellations in verificationCancellationActions.values {
        for cancel in cancellations.values { cancel() }
      }
      commitSignal.finish()
      for subscriptionID in Array(ownerWaiters.keys) {
        resolveOwnerWaiters(for: subscriptionID, error: CancellationError())
      }
      if let delivery {
        _ = await delivery.value
      }
      await worker?.value
      activeDelivery = nil
      workerTask = nil
    }

    func listEvents(profileID: UUID, workspace: Workspace) async throws
      -> [AgentEventDescriptor]
    {
      try await subscriptionService.listEvents(profileID: profileID, workspace: workspace)
    }

    func assertCurrentEventScope(
      profileID: UUID,
      scope: AgentEventScope,
      expectedGrantRevision: UInt64,
      expectedTemporaryExclusionGeneration: UUID?,
      workspaceProvider: AgentEventWorkspaceProvider
    ) async throws -> ScopeMembership {
      try await requireCurrentScope(
        profileID: profileID,
        scope: scope,
        expectedGrantRevision: expectedGrantRevision,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        workspaceProvider: workspaceProvider
      )
    }

    nonisolated func workspaceDidCommit() {
      commitSignal.signal(workspaceCommit: true)
    }

    func prepareAndVerifySubscription(
      profileID: UUID,
      event: AgentEventName,
      scope: AgentEventScope,
      callbackURL: String,
      signingSecret: String,
      requestedTTLSeconds: TimeInterval?,
      expectedGrantRevision: UInt64,
      expectedTemporaryExclusionGeneration: UUID?,
      workspaceProvider: @escaping AgentEventWorkspaceProvider
    ) async throws -> AgentEventMonitoringVerificationObservation {
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      let canonicalURL = try AgentEventSubscriptionIdentity.canonicalCallbackURL(callbackURL)
      for previous in try await subscriptionStore.allSubscriptions()
      where
        previous.expiresAt <= now()
      {
        try await pause(
          previous,
          disposition: .expired
        )
      }

      let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
        profileID: profileID,
        event: event,
        scope: scope,
        callbackURL: canonicalURL
      )
      let requestOriginID = UUID()
      ownerApprovalOrigins[subscriptionID, default: [:]][requestOriginID] = OwnerApprovalOrigin(
        intentID: requestOriginID,
        binding: nil
      )
      var responseLeaseTransferred = false
      var commandWaitBinding: AgentEventCallbackVerificationBinding?
      defer {
        if !responseLeaseTransferred {
          invalidateOwnerApprovalOrigin(requestOriginID, subscriptionID: subscriptionID)
          if let commandWaitBinding {
            endCommandWait(commandWaitBinding)
          }
          commitSignal.signal()
        }
      }
      let receipt = try await subscriptionService.createPending(
        profileID: profileID,
        event: event,
        scope: scope,
        callbackURL: canonicalURL,
        signingSecret: signingSecret,
        requestedTTLSeconds: requestedTTLSeconds,
        workspaceProvider: workspaceProvider
      )
      guard receipt.subscriptionID == subscriptionID else {
        throw AgentEventMonitoringRuntimeError.subscriptionChanged
      }
      cancelVerification(for: receipt.subscriptionID)
      let initial = try await requireSubscription(
        receipt.subscriptionID,
        profileID: profileID,
        revision: receipt.revision,
        grantRevision: receipt.grantRevision
      )
      let binding = Self.binding(for: initial)
      var origins = ownerApprovalOrigins[receipt.subscriptionID] ?? [:]
      if var ownerApprovalOrigin = origins[requestOriginID] {
        ownerApprovalOrigin.binding = binding
        origins[requestOriginID] = ownerApprovalOrigin
        for supersededIntentID in origins.compactMap({
          $0.value.binding != nil && $0.value.binding != binding ? $0.key : nil
        }) {
          origins.removeValue(forKey: supersededIntentID)
        }
        ownerApprovalOrigins[receipt.subscriptionID] = origins
      }
      commandWaitBinding = binding
      beginCommandWait(binding)
      guard let createdControl = initial.deliveryControl,
        createdControl.binding == binding,
        subscriptionStore.isCurrentOwnerDeliveryControl(binding: binding, control: createdControl)
      else {
        throw AgentEventMonitoringRuntimeError.subscriptionChanged
      }
      var observedOwnerControl = createdControl
      do {
        try Task.checkCancellation()
        await afterSubscriptionCreation()
        try Task.checkCancellation()
        guard receipt.grantRevision == expectedGrantRevision else {
          throw AgentWorkspaceError(code: .capabilityDenied)
        }
        _ = try await requireCurrentScope(
          initial,
          expectedGrantRevision: expectedGrantRevision,
          expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
          workspaceProvider: workspaceProvider
        )
        try Task.checkCancellation()
        let latestForPrearm = try await requireSubscription(
          receipt.subscriptionID,
          profileID: profileID,
          revision: receipt.revision,
          grantRevision: receipt.grantRevision
        )
        guard let prearmControl = latestForPrearm.deliveryControl,
          Self.binding(for: latestForPrearm) == binding,
          prearmControl.binding == binding,
          subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: binding,
            control: prearmControl
          )
        else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }
        observedOwnerControl = prearmControl
        try await outboxService.registerPending(
          profileID: profileID,
          subscriptionID: receipt.subscriptionID,
          now: now(),
          ownerDeliveryControl: prearmControl,
          preparedResponseOriginID: requestOriginID
        )
        try Task.checkCancellation()
        guard ownerApprovalOriginIsBound(
          requestOriginID,
          subscriptionID: receipt.subscriptionID,
          binding: binding
        ) else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }
        if prearmControl.enabled && prearmControl.allowsAutomaticRenewal {
          _ = try await requireCurrentScope(
            latestForPrearm,
            expectedGrantRevision: expectedGrantRevision,
            expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
            workspaceProvider: workspaceProvider
          )
          try Task.checkCancellation()
          let prearmReadback = try await requireSubscription(
            receipt.subscriptionID,
            profileID: profileID,
            revision: receipt.revision,
            grantRevision: expectedGrantRevision
          )
          try Task.checkCancellation()
          try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
          guard Self.binding(for: prearmReadback) == binding,
            let currentOrigin = ownerApprovalOrigins[receipt.subscriptionID]?[requestOriginID],
            currentOrigin.intentID == requestOriginID,
            currentOrigin.binding == binding
          else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          if prearmReadback.deliveryControl == prearmControl,
            subscriptionStore.isCurrentOwnerDeliveryControl(
              binding: binding,
              control: prearmControl
            )
          {
            try outboxService.requirePreparedResponseFence(
              binding: binding,
              ownerDeliveryControl: prearmControl,
              originIntentID: requestOriginID
            )
            if !currentOrigin.initialApprovalSatisfied {
              guard ownerApprovalOriginIsCurrent(
                requestOriginID,
                subscriptionID: receipt.subscriptionID,
                binding: binding
              ) else {
                throw AgentEventMonitoringRuntimeError.subscriptionChanged
              }
              var satisfiedOrigin = currentOrigin
              satisfiedOrigin.initialApprovalSatisfied = true
              ownerApprovalOrigins[receipt.subscriptionID]?[requestOriginID] = satisfiedOrigin
            }
          }
        }
        await approvalObservationHook?.beforeInitialOwnerWait()
        let approved = try await awaitOwnerApproval(
          subscriptionID: receipt.subscriptionID,
          binding: binding,
          originIntentID: requestOriginID
        )
        try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
        guard let approvedControl = approved.deliveryControl,
          Self.binding(for: approved) == binding,
          approvedControl.binding == binding,
          approvedControl.enabled
        else {
          throw AgentEventCallbackVerificationError.notAuthorized
        }
        try outboxService.requirePreparedResponseFence(
          binding: binding,
          ownerDeliveryControl: approvedControl,
          originIntentID: requestOriginID
        )
        observedOwnerControl = approvedControl
        try Task.checkCancellation()

        guard ownerApprovalOriginIsBound(
          requestOriginID,
          subscriptionID: receipt.subscriptionID,
          binding: binding
        ), ownerApprovalOrigins[receipt.subscriptionID]?[requestOriginID]?
          .initialApprovalSatisfied == true
        else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }

        let proof = try await anchorAndVerifyPendingSubscription(
          profileID: profileID,
          subscriptionID: receipt.subscriptionID,
          workspaceProvider: workspaceProvider,
          ownerDeliveryControl: approvedControl,
          requestOriginID: requestOriginID,
          preparedResponseOriginID: requestOriginID,
          now: now()
        )
        try Task.checkCancellation()
        guard proof.binding == binding, proof.expiresAt > now(),
          proof.expiresAt <= approved.expiresAt
        else {
          throw AgentEventCallbackVerificationError.verificationFailed
        }
        _ = try await requireCurrentScope(
          approved,
          expectedGrantRevision: expectedGrantRevision,
          expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
          workspaceProvider: workspaceProvider
        )
        try Task.checkCancellation()
        let current = try await requireSubscription(
          receipt.subscriptionID,
          profileID: profileID,
          revision: receipt.revision,
          grantRevision: expectedGrantRevision
        )
        try Task.checkCancellation()
        guard current.deliveryControl == approvedControl else {
          throw AgentEventCallbackVerificationError.notAuthorized
        }
        guard
          Self.binding(for: current) == proof.binding,
          let savedProof = try callbackVerificationStore.currentProof(for: proof.binding),
          savedProof == proof,
          savedProof.expiresAt > now(),
          savedProof.expiresAt <= current.expiresAt
        else {
          throw AgentEventCallbackVerificationError.notAuthorized
        }
        try outboxService.requirePreparedResponseFence(
          binding: binding,
          ownerDeliveryControl: approvedControl,
          originIntentID: requestOriginID
        )
        guard ownerApprovalOriginIsBound(
          requestOriginID,
          subscriptionID: receipt.subscriptionID,
          binding: binding
        ), ownerApprovalOrigins[receipt.subscriptionID]?[requestOriginID]?
          .initialApprovalSatisfied == true
        else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }
        let verifiedReceipt = AgentEventVerifiedSubscriptionReceipt(
          subscriptionID: current.subscriptionID,
          refreshBefore: current.expiresAt,
          revision: current.revision,
          grantRevision: current.grantRevision
        )
        let subscriptionStore = self.subscriptionStore
        let callbackVerificationStore = self.callbackVerificationStore
        let outboxService = self.outboxService
        let controlGenerationID = approvedControl.generationID
        let subscriptionExpiresAt = current.expiresAt
        let now = self.now
        let responseLease = AgentEventResponseLease { [self] delivered in
          await completePreparedResponse(
            delivered: delivered,
            binding: binding,
            observedOwnerControl: approvedControl,
            requestOriginID: requestOriginID
          )
        }
        responseLeaseTransferred = true
        return AgentEventMonitoringVerificationObservation(
          receipt: verifiedReceipt,
          responseLease: responseLease,
          remainsCurrent: {
            subscriptionStore.isCurrentOwnerDeliveryControl(
              binding: binding,
              generationID: controlGenerationID
            )
              && (try? callbackVerificationStore.currentProof(for: binding)) == proof
              && outboxService.hasPreparedResponseFence(
                binding: binding,
                ownerDeliveryControl: approvedControl,
                originIntentID: requestOriginID
              )
              && proof.expiresAt > now()
              && proof.expiresAt <= subscriptionExpiresAt
          }
        )
      } catch {
        invalidateOwnerApprovalOrigin(requestOriginID, subscriptionID: receipt.subscriptionID)
        let callbackError = error as? AgentEventCallbackVerificationError
        let runtimeError = error as? AgentEventMonitoringRuntimeError
        let approvalTimedOut: Bool
        if let runtimeError, case .ownerApprovalTimedOut = runtimeError {
          approvalTimedOut = true
        } else {
          approvalTimedOut = false
        }
        if error is CancellationError || callbackError == .cancelled
          || callbackError == .timedOut || approvalTimedOut
        {
          try? outboxService.failPreparedResponseFence(
            binding: binding,
            ownerDeliveryControl: observedOwnerControl,
            originIntentID: requestOriginID
          )
          try await disposeCancelledPreparation(
            binding: binding,
            observedOwnerControl: observedOwnerControl,
            requestOriginID: requestOriginID
          )
        } else {
          try? outboxService.failPreparedResponseFence(
            binding: binding,
            ownerDeliveryControl: observedOwnerControl,
            originIntentID: requestOriginID
          )
          try callbackVerificationStore.removeProof(for: binding, generatedBy: requestOriginID)
        }
        throw error
      }
    }

    func setOwnerDeliveryConsent(
      subscriptionID: String,
      enabled: Bool,
      allowsAutomaticRenewal: Bool,
      workspaceProvider: AgentEventWorkspaceProvider?,
      expectedConsentGenerationID: UUID? = nil
    ) async throws {
      guard let current = try await subscriptionStore.currentSubscription(id: subscriptionID) else {
        throw AgentWorkspaceError(code: .invalidOperation)
      }
      if let expectedConsentGenerationID,
        current.deliveryControl?.generationID != expectedConsentGenerationID
      {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      try Task.checkCancellation()
      let binding = Self.binding(for: current)
      let readinessMode = ownerApprovalReadinessMode(
        subscriptionID: subscriptionID,
        binding: binding
      )
      let preparedResponseOriginID: UUID?
      if case .prepared(let originIntentID)? = readinessMode {
        preparedResponseOriginID = originIntentID
      } else {
        preparedResponseOriginID = nil
      }
      let prospectiveGenerationID = enabled ? UUID() : nil
      if enabled {
        beginCommandWait(binding)
      }
      defer {
        if enabled {
          endCommandWait(binding)
        }
        commitSignal.signal()
      }
      do {
        if enabled {
          try Task.checkCancellation()
          guard let readinessMode else {
            throw AgentEventOutboxError.registrationRequired
          }
          guard current.expiresAt > now(), let workspaceProvider else {
            throw AgentWorkspaceError(code: .invalidOperation)
          }
          let activeProfiles = try await profileStore.activeProfiles()
          try Task.checkCancellation()
          guard activeProfiles.contains(where: { $0.id == current.profileID && !$0.isRevoked }) else {
            throw AgentWorkspaceError(code: .permissionRevoked)
          }
          let workspace = try await workspaceProvider()
          try Task.checkCancellation()
          let grantRevision = try await authority.authorizeEventObservation(
            profileID: current.profileID,
            scope: current.scope,
            workspace: workspace
          )
          try Task.checkCancellation()
          guard grantRevision == current.grantRevision else {
            throw AgentWorkspaceError(code: .capabilityDenied)
          }
          try await authority.assertEventObservationCurrent(
            profileID: current.profileID,
            grantRevision: current.grantRevision,
            scope: current.scope,
            workspace: workspace
          )
          try Task.checkCancellation()
          let latest = try await requireSubscription(
            subscriptionID,
            profileID: current.profileID,
            revision: current.revision,
            grantRevision: current.grantRevision
          )
          try Task.checkCancellation()
          guard Self.binding(for: latest) == binding else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          guard ownerApprovalOriginIsCurrent(
            preparedResponseOriginID,
            subscriptionID: subscriptionID,
            binding: binding
          ) else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          guard let expectedOwnerDeliveryControl = current.deliveryControl else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          let readiness = try outboxService.requireOwnerApprovalReadiness(
            binding: binding,
            ownerDeliveryControl: expectedOwnerDeliveryControl,
            mode: readinessMode
          )
          switch readiness {
          case .awaitingApproval, .ownerPaused:
            break
          case .pausedCapacity, .pausedHistory:
            throw AgentEventOutboxError.sourceChanged
          }
          if let preparedResponseOriginID {
            guard let prospectiveGenerationID else {
              throw AgentEventMonitoringRuntimeError.subscriptionChanged
            }
            try outboxService.armProspectivePreparedResponseFence(
              binding: binding,
              expectedOwnerDeliveryControl: expectedOwnerDeliveryControl,
              prospectiveGenerationID: prospectiveGenerationID,
              originIntentID: preparedResponseOriginID
            )
          }
          try Task.checkCancellation()
          guard ownerApprovalOriginIsCurrent(
            preparedResponseOriginID,
            subscriptionID: subscriptionID,
            binding: binding
          ) else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
        }

        guard
          let control = try await subscriptionStore.setOwnerDeliveryEligibility(
            binding: binding,
            expectedGenerationID: current.deliveryControl?.generationID,
            eligible: enabled,
            allowsAutomaticRenewal: enabled && allowsAutomaticRenewal,
            prospectiveGenerationID: prospectiveGenerationID
          ),
          control.binding == binding,
          control.enabled == enabled,
          prospectiveGenerationID.map({ control.generationID == $0 }) ?? true,
          subscriptionStore.isCurrentOwnerDeliveryControl(binding: binding, control: control)
        else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }
        if enabled {
          try Task.checkCancellation()
          guard ownerApprovalOriginIsCurrent(
            preparedResponseOriginID,
            subscriptionID: subscriptionID,
            binding: binding
          ) else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
        }
        cancelVerification(for: subscriptionID)
        if enabled {
          try await outboxService.registerPending(
            profileID: current.profileID,
            subscriptionID: subscriptionID,
            now: now(),
            ownerDeliveryControl: control,
            preparedResponseOriginID: preparedResponseOriginID
          )
          try Task.checkCancellation()
          guard ownerApprovalOriginIsCurrent(
            preparedResponseOriginID,
            subscriptionID: subscriptionID,
            binding: binding
          ) else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          guard
            let latest = try await subscriptionStore.currentSubscription(id: subscriptionID),
            Self.binding(for: latest) == binding,
            latest.deliveryControl == control,
            subscriptionStore.isCurrentOwnerDeliveryControl(binding: binding, control: control)
          else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          try Task.checkCancellation()
          guard ownerApprovalOriginIsCurrent(
            preparedResponseOriginID,
            subscriptionID: subscriptionID,
            binding: binding
          ) else {
            throw AgentEventMonitoringRuntimeError.subscriptionChanged
          }
          if let preparedResponseOriginID {
            try outboxService.requirePreparedResponseFence(
              binding: binding,
              ownerDeliveryControl: control,
              originIntentID: preparedResponseOriginID
            )
          }
          if let preparedResponseOriginID {
            guard
              var ownerApprovalOrigin = ownerApprovalOrigins[subscriptionID]?[preparedResponseOriginID],
              ownerApprovalOrigin.binding == binding
            else {
              throw AgentEventMonitoringRuntimeError.subscriptionChanged
            }
            ownerApprovalOrigin.initialApprovalSatisfied = true
            ownerApprovalOrigins[subscriptionID]?[preparedResponseOriginID] = ownerApprovalOrigin
          }
          resolveOwnerWaiters(for: subscriptionID)
        } else {
          cancelDelivery(for: subscriptionID)
          try outboxService.discardPendingBodies(
            profileID: current.profileID,
            subscriptionID: subscriptionID,
            disposition: .ownerPaused
          )
          resolveOwnerWaiters(for: subscriptionID)
        }
      } catch {
        if let preparedResponseOriginID, let prospectiveGenerationID {
          try? outboxService.failProspectivePreparedResponseFence(
            binding: binding,
            prospectiveGenerationID: prospectiveGenerationID,
            originIntentID: preparedResponseOriginID
          )
        }
        throw error
      }
    }

    func removeSubscription(subscriptionID: String) async throws {
      pendingCaptureSubscriptions.remove(subscriptionID)
      captureRetryAt.removeValue(forKey: subscriptionID)
      cancelVerification(for: subscriptionID)
      guard let current = try await subscriptionStore.currentSubscription(id: subscriptionID) else {
        let outbox = try outboxStore.load()
        for progress in outbox.progress where progress.subscriptionID == subscriptionID {
          try outboxService.discardPendingBodies(
            profileID: progress.profileID,
            subscriptionID: subscriptionID,
            disposition: .subscriptionRemoved
          )
        }
        resolveOwnerWaiters(for: subscriptionID)
        commitSignal.signal()
        return
      }
      let binding = Self.binding(for: current)
      guard
        let control = try await subscriptionStore.setOwnerDeliveryEligibility(
          binding: binding,
          expectedGenerationID: current.deliveryControl?.generationID,
          eligible: false
        ),
        subscriptionStore.isCurrentOwnerDeliveryControl(binding: binding, control: control)
      else {
        throw AgentEventMonitoringRuntimeError.subscriptionChanged
      }
      cancelDelivery(for: subscriptionID)
      try await subscriptionService.retirePreviousSigningKey(
        subscriptionID: subscriptionID,
        now: now()
      )
      try outboxService.discardPendingBodies(
        profileID: current.profileID,
        subscriptionID: subscriptionID,
        disposition: .subscriptionRemoved
      )
      try await subscriptionService.remove(
        profileID: current.profileID,
        subscriptionID: subscriptionID
      )
    }

    func pauseSubscriptions(
      profileIDs: Set<UUID>,
      noteIDs: Set<UUID> = [],
      folderIDs: Set<UUID> = [],
      disposition: AgentEventOutboxNonDeliveryDisposition
    ) async throws {
      let subscriptions = try await subscriptionStore.allSubscriptions()
      for subscription in subscriptions {
        let affectedByProfile = profileIDs.contains(subscription.profileID)
        let affectedByScope: Bool
        switch subscription.scope {
        case .note(let noteID):
          affectedByScope = noteIDs.contains(noteID)
        case .folder(let folderID):
          affectedByScope = folderIDs.contains(folderID)
        }
        guard affectedByProfile || affectedByScope else { continue }
        try await pause(subscription, disposition: disposition)
      }
      commitSignal.signal()
    }

    func ownerSummaries(workspace currentWorkspace: Workspace?) async throws
      -> [AgentEventOwnerSummary]
    {
      let subscriptions = try await subscriptionStore.allSubscriptions()
      let activeProfiles = try? await profileStore.activeProfiles()
      let activeProfileIDs = activeProfiles.map {
        Set($0.filter { !$0.isRevoked }.map(\.id))
      }
      let currentTime = now()
      var summaries: [AgentEventOwnerSummary] = []
      for subscription in subscriptions {
        let state = await ownerState(
          for: subscription,
          activeProfileIDs: activeProfileIDs,
          workspace: currentWorkspace,
          now: currentTime
        )
        let lastReceiptAt = try? deliveryLedgerStore.lastReceiptAt(
          profileID: subscription.profileID,
          subscriptionID: subscription.subscriptionID
        )
        summaries.append(
          AgentEventOwnerSummary(
            id: subscription.subscriptionID,
            profileID: subscription.profileID,
            event: subscription.event,
            scope: subscription.scope,
            callbackHost: Self.callbackHost(subscription.callbackURL),
            state: state,
            expiresAt: subscription.expiresAt,
            lastReceiptAt: lastReceiptAt,
            allowsAutomaticRenewal: subscription.deliveryControl?.allowsAutomaticRenewal == true,
            consentGenerationID: subscription.deliveryControl?.generationID
          )
        )
      }
      return summaries
    }

    private func drain() async {
      scheduledWakeTask?.cancel()
      scheduledWakeTask = nil
      guard let workspaceProvider else { return }
      guard !Task.isCancelled else { return }
      let currentTime = now()
      do {
        try await subscriptionService.maintainSigningKeyLifecycle(now: currentTime)
      } catch {
        scheduleWake(at: currentTime.addingTimeInterval(2))
        return
      }
      let subscriptions: [AgentEventPendingSubscription]
      do {
        subscriptions = try await subscriptionStore.allSubscriptions()
      } catch {
        scheduleWake(at: currentTime.addingTimeInterval(2))
        return
      }
      if commitSignal.consumeWorkspaceCommit() {
        pendingCaptureSubscriptions.formUnion(
          subscriptions.lazy.filter {
            $0.expiresAt > currentTime
              && $0.status == .pending
              && $0.deliveryControl?.enabled == true
          }.map(\.subscriptionID)
        )
      }
      for subscription in subscriptions where subscription.expiresAt <= currentTime {
        try? await pause(subscription, disposition: .expired)
      }
      do {
        try await subscriptionService.pruneExpiredSubscriptions(now: currentTime)
      } catch {
        scheduleWake(at: currentTime.addingTimeInterval(2))
        return
      }
      let activeSubscriptions = subscriptions.filter {
        $0.expiresAt > currentTime && $0.status == .pending
      }
      guard !activeSubscriptions.isEmpty else {
        if let nextWake = nextWakeDate(subscriptions, now: now()) {
          scheduleWake(at: nextWake)
        }
        return
      }
      let profiles: [AgentIntegrationProfile]
      do {
        profiles = try await profileStore.activeProfiles()
      } catch {
        scheduleWake(at: currentTime.addingTimeInterval(2))
        return
      }
      let activeProfileIDs = Set(profiles.filter { !$0.isRevoked }.map(\.id))
      roundRobinOffset %= activeSubscriptions.count
      for offset in activeSubscriptions.indices {
        let index = (roundRobinOffset + offset) % activeSubscriptions.count
        let subscription = activeSubscriptions[index]
        let subscriptionID = subscription.subscriptionID
        let binding = Self.binding(for: subscription)
        guard let ownerDeliveryControl = subscription.deliveryControl,
          ownerDeliveryControl.binding == binding
        else {
          continue
        }
        do {
          let records = try deliveryLedgerStore.records(for: binding)
          try await outboxService.releaseCompletedRecords(records)
        } catch {
          continue
        }
        guard activeProfileIDs.contains(subscription.profileID) else {
          try? await pause(subscription, disposition: .profileRevoked)
          continue
        }
        guard ownerDeliveryControl.enabled else {
          pendingCaptureSubscriptions.remove(subscriptionID)
          captureRetryAt.removeValue(forKey: subscriptionID)
          continue
        }
        guard outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: ownerDeliveryControl
        ) else {
          continue
        }
        if commandWaitCounts[binding, default: 0] > 0 { continue }
        if observedBindings[subscriptionID] != binding {
          observedBindings[subscriptionID] = binding
          pendingCaptureSubscriptions.insert(subscriptionID)
        }
        if let retryAt = captureRetryAt[subscriptionID] {
          guard retryAt <= monotonicClock.now else { continue }
        }
        if pendingCaptureSubscriptions.contains(subscriptionID) {
          do {
            try await outboxService.capturePending(
              profileID: subscription.profileID,
              subscriptionID: subscriptionID,
              now: currentTime
            )
            pendingCaptureSubscriptions.remove(subscriptionID)
            captureRetryAt.removeValue(forKey: subscriptionID)
          } catch {
            captureRetryAt[subscriptionID] = monotonicClock.now.advanced(by: .seconds(2))
            continue
          }
        }
        if !isCallbackProofCurrent(for: subscription, now: currentTime) {
          do {
            let verificationOriginID = UUID()
            _ = try await anchorAndVerifyPendingSubscription(
              profileID: subscription.profileID,
              subscriptionID: subscriptionID,
              workspaceProvider: workspaceProvider,
              ownerDeliveryControl: ownerDeliveryControl,
              requestOriginID: verificationOriginID,
              now: currentTime
            )
          } catch {
            continue
          }
          guard let latest = try? await subscriptionStore.currentSubscription(id: subscriptionID),
            Self.binding(for: latest) == binding,
            latest.deliveryControl == ownerDeliveryControl,
            subscriptionStore.isCurrentOwnerDeliveryControl(
              binding: binding,
              control: ownerDeliveryControl
            ),
            isCallbackProofCurrent(for: latest, now: now())
          else {
            continue
          }
        }
        if let lastAttempt = lastDeliveryAttempt[subscriptionID],
          monotonicClock.now - lastAttempt < .seconds(2)
        {
          continue
        }
        let task = Task {
          try? await monitoringService.captureReserveAndSendAtMostOne(
            profileID: subscription.profileID,
            subscriptionID: subscriptionID,
            workspaceProvider: workspaceProvider,
            now: now()
          )
        }
        activeDelivery = (subscriptionID, task)
        lastDeliveryAttempt[subscriptionID] = monotonicClock.now
        let result = await task.value
        activeDelivery = nil
        guard !Task.isCancelled else { return }
        switch result {
        case .some(.settled(.receipt)), .some(.settled(.terminal)),
          .some(.settled(.expired)), .some(.settled(.exhausted)),
          .some(.settled(.superseded)):
          commitSignal.signal()
        default:
          break
        }
      }
      roundRobinOffset = (roundRobinOffset + 1) % activeSubscriptions.count
      if let nextWake = nextWakeDate(subscriptions, now: now()) {
        scheduleWake(at: nextWake)
      }
    }

    private func nextWakeDate(
      _ subscriptions: [AgentEventPendingSubscription],
      now currentTime: Date
    ) -> Date? {
      var deadlines: [Date] = []
      for subscription in subscriptions {
        if let previousSigningKey = subscription.previousSigningKey,
          previousSigningKey.expiresAt > currentTime
        {
          deadlines.append(previousSigningKey.expiresAt)
        }
      }
      guard let outbox = try? outboxStore.load() else { return deadlines.min() }
      for subscription in subscriptions {
        guard let ownerDeliveryControl = subscription.deliveryControl,
          ownerDeliveryControl.enabled
        else {
          continue
        }
        guard subscription.expiresAt > currentTime else {
          deadlines.append(currentTime)
          continue
        }
        deadlines.append(subscription.expiresAt)
        if let retryAt = captureRetryAt[subscription.subscriptionID] {
          deadlines.append(
            currentTime.addingTimeInterval(
              max(0, Self.seconds(monotonicClock.now.duration(to: retryAt)))
            )
          )
        } else if pendingCaptureSubscriptions.contains(subscription.subscriptionID) {
          deadlines.append(currentTime.addingTimeInterval(2))
        }
        let binding = Self.binding(for: subscription)
        guard
          let progress = outbox.progress.first(where: {
            $0.profileID == subscription.profileID
              && $0.subscriptionID == subscription.subscriptionID
              && $0.subscriptionRevision == subscription.revision
              && $0.grantRevision == subscription.grantRevision
          }),
          progress.status == .pending,
          progress.preparedResponseFence?.blocksDelivery(for: ownerDeliveryControl) != true,
          let entry = outbox.entries.filter({
            $0.profileID == subscription.profileID
              && $0.subscriptionID == subscription.subscriptionID
              && $0.status == .awaitingVerification
              && $0.body != nil
          }).min(by: { $0.sourcePosition.sequence < $1.sourcePosition.sequence })
        else {
          continue
        }
        guard isCallbackProofCurrent(for: subscription, now: currentTime) else {
          deadlines.append(min(subscription.expiresAt, currentTime.addingTimeInterval(30)))
          continue
        }
        var deadline = currentTime
        var awaitsDeliveryAttempt = true
        if let records = try? deliveryLedgerStore.records(for: binding),
          let record = records.first(where: {
            $0.eventID == entry.eventID && $0.sourcePosition == entry.sourcePosition
          })
        {
          switch record.status {
          case .retryWaiting:
            deadline = record.nextEligibleAt ?? currentTime
          case .reserved:
            deadline = record.leaseDeadline ?? currentTime
          case .paused:
            continue
          case .receipt, .terminal, .expired, .exhausted, .superseded:
            deadline = currentTime
            awaitsDeliveryAttempt = false
          }
        }
        if awaitsDeliveryAttempt,
          let lastAttempt = lastDeliveryAttempt[subscription.subscriptionID]
        {
          let allowedAt = lastAttempt.advanced(by: .seconds(2))
          if monotonicClock.now < allowedAt {
            deadline = max(
              deadline,
              currentTime.addingTimeInterval(
                Self.seconds(monotonicClock.now.duration(to: allowedAt))
              )
            )
          }
        } else if awaitsDeliveryAttempt, observedBindings[subscription.subscriptionID] != binding {
          deadline = max(deadline, currentTime.addingTimeInterval(2))
        }
        deadlines.append(deadline)
      }
      return deadlines.min()
    }

    private func ownerState(
      for subscription: AgentEventPendingSubscription,
      activeProfileIDs: Set<UUID>?,
      workspace: Workspace?,
      now currentTime: Date
    ) async -> AgentEventOwnerState {
      guard subscription.expiresAt > currentTime else { return .expired }
      guard let activeProfileIDs else { return .unavailable }
      guard activeProfileIDs.contains(subscription.profileID) else { return .stopped }
      let binding = Self.binding(for: subscription)
      guard let deliveryControl = subscription.deliveryControl,
        deliveryControl.binding == binding
      else { return .unavailable }
      guard let readinessMode = ownerApprovalReadinessMode(
        subscriptionID: subscription.subscriptionID,
        binding: binding
      ) else {
        return .unavailable
      }
      do {
        let readiness = try outboxService.requireOwnerApprovalReadiness(
          binding: binding,
          ownerDeliveryControl: deliveryControl,
          mode: readinessMode
        )
        switch readiness {
        case .awaitingApproval:
          break
        case .ownerPaused:
          return .paused
        case .pausedCapacity:
          return .pausedCapacity
        case .pausedHistory:
          return .pausedHistory
        }
      } catch {
        return .unavailable
      }
      if case .prepared = readinessMode, deliveryControl.enabled {
        return .unavailable
      }
      guard deliveryControl.enabled else { return .awaitingApproval }
      guard let workspace else { return .unavailable }
      do {
        let grantRevision = try await authority.authorizeEventObservation(
          profileID: subscription.profileID,
          scope: subscription.scope,
          workspace: workspace
        )
        guard grantRevision == subscription.grantRevision else { return .unavailable }
      } catch {
        return .unavailable
      }
      guard let outbox = try? outboxStore.load(),
        let progress = outbox.progress.first(where: {
          $0.profileID == subscription.profileID
            && $0.subscriptionID == subscription.subscriptionID
            && $0.subscriptionRevision == subscription.revision
            && $0.grantRevision == subscription.grantRevision
        })
      else {
        return .unavailable
      }
      switch progress.status {
      case .pending:
        break
      case .pausedCapacity:
        return .pausedCapacity
      case .pausedHistory:
        return .pausedHistory
      case .pausedUnavailable, .discarded:
        return .unavailable
      }
      guard isCallbackProofCurrent(for: subscription, now: currentTime) else {
        return .awaitingVerification
      }
      guard let records = try? deliveryLedgerStore.records(for: binding) else {
        return .unavailable
      }
      if records.contains(where: { $0.status == .retryWaiting || $0.status == .reserved }) {
        return .retrying
      }
      return .enabled
    }

    private func awaitOwnerApproval(
      subscriptionID: String,
      binding: AgentEventCallbackVerificationBinding,
      originIntentID: UUID
    ) async throws -> AgentEventPendingSubscription {
      let deadline = monotonicClock.now.advanced(by: approvalWaitLimit)
      while true {
        try Task.checkCancellation()
        guard let current = try await subscriptionStore.currentSubscription(id: subscriptionID),
          Self.binding(for: current) == binding,
          current.expiresAt > now()
        else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }
        guard ownerApprovalOriginIsBound(
          originIntentID,
          subscriptionID: subscriptionID,
          binding: binding
        ) else {
          throw AgentEventMonitoringRuntimeError.subscriptionChanged
        }
        if let currentControl = current.deliveryControl,
          currentControl.binding == binding,
          currentControl.enabled,
          subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: binding,
            control: currentControl
          ),
          ownerApprovalOrigins[subscriptionID]?[originIntentID]?.initialApprovalSatisfied == true
        {
          return current
        }
        guard monotonicClock.now < deadline else {
          throw AgentEventMonitoringRuntimeError.ownerApprovalTimedOut
        }
        try await waitForOwnerChange(
          subscriptionID,
          originIntentID: originIntentID,
          duration: min(monotonicClock.now.duration(to: deadline), approvalWaitLimit)
        )
      }
    }

    private func waitForOwnerChange(
      _ subscriptionID: String,
      originIntentID: UUID,
      duration: Duration
    ) async throws {
      let waiterID = UUID()
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.resolveOwnerWaiter(
              subscriptionID,
              waiterID: waiterID,
              error: AgentEventMonitoringRuntimeError.ownerApprovalTimedOut
            )
          }
          ownerWaiters[subscriptionID, default: [:]][waiterID] = OwnerWaiter(
            continuation: continuation,
            timeoutTask: timeoutTask,
            originIntentID: originIntentID
          )
          approvalObservationHook?.ownerWaiterRegistered()
        }
      } onCancel: {
        Task {
          await self.resolveOwnerWaiter(
            subscriptionID,
            waiterID: waiterID,
            error: CancellationError()
          )
        }
      }
    }

    private func resolveOwnerWaiters(for subscriptionID: String, error: Error? = nil) {
      let waiters: [OwnerWaiter]
      if let current = ownerWaiters.removeValue(forKey: subscriptionID) {
        waiters = Array(current.values)
      } else {
        waiters = []
      }
      for waiter in waiters {
        waiter.timeoutTask.cancel()
        if let error {
          invalidateOwnerApprovalOrigin(waiter.originIntentID, subscriptionID: subscriptionID)
          waiter.continuation.resume(throwing: error)
        } else {
          waiter.continuation.resume()
        }
      }
    }

    private func resolveOwnerWaiter(
      _ subscriptionID: String,
      waiterID: UUID,
      error: Error
    ) {
      guard let waiter = ownerWaiters[subscriptionID]?.removeValue(forKey: waiterID) else {
        return
      }
      if ownerWaiters[subscriptionID]?.isEmpty == true {
        ownerWaiters.removeValue(forKey: subscriptionID)
      }
      waiter.timeoutTask.cancel()
      invalidateOwnerApprovalOrigin(waiter.originIntentID, subscriptionID: subscriptionID)
      waiter.continuation.resume(throwing: error)
    }

    private func beginCommandWait(_ binding: AgentEventCallbackVerificationBinding) {
      commandWaitCounts[binding, default: 0] += 1
    }

    private func endCommandWait(_ binding: AgentEventCallbackVerificationBinding) {
      guard let count = commandWaitCounts[binding] else { return }
      if count == 1 {
        commandWaitCounts.removeValue(forKey: binding)
      } else {
        commandWaitCounts[binding] = count - 1
      }
    }

    private func ownerApprovalOriginIsCurrent(
      _ originIntentID: UUID?,
      subscriptionID: String,
      binding: AgentEventCallbackVerificationBinding
    ) -> Bool {
      let origins = ownerApprovalOrigins[subscriptionID] ?? [:]
      if let originIntentID {
        guard let currentOrigin = origins[originIntentID] else { return false }
        return currentOrigin.intentID == originIntentID
          && currentOrigin.binding == binding
          && !currentOrigin.initialApprovalSatisfied
      }
      let currentOrigins = origins.values.filter { $0.binding == binding }
      if currentOrigins.contains(where: { !$0.initialApprovalSatisfied }) { return false }
      if !currentOrigins.isEmpty { return true }
      return !origins.values.contains(where: { $0.binding == nil })
    }

    private func ownerApprovalOriginIsBound(
      _ intentID: UUID,
      subscriptionID: String,
      binding: AgentEventCallbackVerificationBinding
    ) -> Bool {
      let origins = ownerApprovalOrigins[subscriptionID] ?? [:]
      guard let origin = origins[intentID] else {
        return false
      }
      return origin.intentID == intentID && origin.binding == binding
    }

    private func ownerApprovalReadinessMode(
      subscriptionID: String,
      binding: AgentEventCallbackVerificationBinding
    ) -> AgentEventOwnerApprovalReadinessMode? {
      let origins = ownerApprovalOrigins[subscriptionID] ?? [:]
      let preparedOrigins = origins.values.filter {
        $0.binding == binding && !$0.initialApprovalSatisfied
      }
      if preparedOrigins.count == 1, let currentOrigin = preparedOrigins.first {
        return .prepared(originIntentID: currentOrigin.intentID)
      }
      guard preparedOrigins.isEmpty else { return nil }
      if origins.values.contains(where: {
        $0.binding == binding && $0.initialApprovalSatisfied
      }) {
        return .independent
      }
      guard !origins.values.contains(where: { $0.binding == nil }) else { return nil }
      return .legacy
    }

    private func invalidateOwnerApprovalOrigin(
      _ intentID: UUID,
      subscriptionID: String
    ) {
      removeOwnerApprovalOrigin(intentID, subscriptionID: subscriptionID)
    }

    private func removeOwnerApprovalOrigin(_ intentID: UUID, subscriptionID: String) {
      guard var origins = ownerApprovalOrigins[subscriptionID] else { return }
      origins.removeValue(forKey: intentID)
      ownerApprovalOrigins[subscriptionID] = origins.isEmpty ? nil : origins
    }

    private func completePreparedResponse(
      delivered: Bool,
      binding: AgentEventCallbackVerificationBinding,
      observedOwnerControl: AgentEventDeliveryControl,
      requestOriginID: UUID
    ) async {
      defer {
        endCommandWait(binding)
        commitSignal.signal()
      }
      if delivered {
        removeOwnerApprovalOrigin(requestOriginID, subscriptionID: binding.subscriptionID)
        try? outboxService.clearPreparedResponseFence(
          binding: binding,
          ownerDeliveryControl: observedOwnerControl,
          originIntentID: requestOriginID
        )
        return
      }
      try? outboxService.failPreparedResponseFence(
        binding: binding,
        ownerDeliveryControl: observedOwnerControl,
        originIntentID: requestOriginID
      )
      try? await disposeCancelledPreparation(
        binding: binding,
        observedOwnerControl: observedOwnerControl,
        requestOriginID: requestOriginID
      )
    }

    private func requireCurrentScope(
      _ subscription: AgentEventPendingSubscription,
      expectedGrantRevision: UInt64,
      expectedTemporaryExclusionGeneration: UUID?,
      workspaceProvider: AgentEventWorkspaceProvider
    ) async throws -> ScopeMembership {
      guard subscription.grantRevision == expectedGrantRevision else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
      return try await requireCurrentScope(
        profileID: subscription.profileID,
        scope: subscription.scope,
        expectedGrantRevision: expectedGrantRevision,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        workspaceProvider: workspaceProvider
      )
    }

    private func requireCurrentScope(
      profileID: UUID,
      scope: AgentEventScope,
      expectedGrantRevision: UInt64,
      expectedTemporaryExclusionGeneration: UUID?,
      workspaceProvider: AgentEventWorkspaceProvider
    ) async throws -> ScopeMembership {
      for _ in 0..<2 {
        try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
        let workspace = try await workspaceProvider()
        try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
        let membership = ScopeMembership.capture(scope, in: workspace)
        let currentRevision = try await scopeAuthorization(profileID, scope, workspace)
        guard currentRevision == expectedGrantRevision else {
          throw AgentWorkspaceError(code: .capabilityDenied)
        }
        try await authority.assertEventObservationCurrent(
          profileID: profileID,
          grantRevision: expectedGrantRevision,
          scope: scope,
          workspace: workspace
        )
        try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
        let latestWorkspace = try await workspaceProvider()
        try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
        guard membership == ScopeMembership.capture(scope, in: latestWorkspace) else { continue }
        return membership
      }
      throw AgentWorkspaceError(code: .capabilityDenied)
    }

    private func requireSubscription(
      _ subscriptionID: String,
      profileID: UUID,
      revision: UInt64,
      grantRevision: UInt64
    ) async throws -> AgentEventPendingSubscription {
      guard let subscription = try await subscriptionStore.currentSubscription(id: subscriptionID),
        subscription.profileID == profileID,
        subscription.revision == revision,
        subscription.grantRevision == grantRevision,
        subscription.status == .pending,
        subscription.expiresAt > now()
      else {
        throw AgentEventMonitoringRuntimeError.subscriptionChanged
      }
      return subscription
    }

    private func pause(
      _ subscription: AgentEventPendingSubscription,
      disposition: AgentEventOutboxNonDeliveryDisposition
    ) async throws {
      let binding = Self.binding(for: subscription)
      guard
        let control = try await subscriptionStore.setOwnerDeliveryEligibility(
          binding: binding,
          expectedGenerationID: subscription.deliveryControl?.generationID,
          eligible: false
        ),
        subscriptionStore.isCurrentOwnerDeliveryControl(binding: binding, control: control)
      else {
        throw AgentEventMonitoringRuntimeError.subscriptionChanged
      }
      pendingCaptureSubscriptions.remove(subscription.subscriptionID)
      captureRetryAt.removeValue(forKey: subscription.subscriptionID)
      cancelVerification(for: subscription.subscriptionID)
      cancelDelivery(for: subscription.subscriptionID)
      if disposition != .ownerPaused {
        try await subscriptionService.retirePreviousSigningKey(
          subscriptionID: subscription.subscriptionID,
          now: now()
        )
      }
      try outboxService.discardPendingBodies(
        profileID: subscription.profileID,
        subscriptionID: subscription.subscriptionID,
        disposition: disposition
      )
      resolveOwnerWaiters(for: subscription.subscriptionID)
    }

    private func cancelDelivery(for subscriptionID: String) {
      guard activeDelivery?.subscriptionID == subscriptionID else { return }
      activeDelivery?.task.cancel()
    }

    private func cancelVerification(for subscriptionID: String) {
      guard let cancellations = verificationCancellationActions[subscriptionID]?.values else {
        return
      }
      for cancel in cancellations { cancel() }
    }

    private func anchorAndVerifyPendingSubscription(
      profileID: UUID,
      subscriptionID: String,
      workspaceProvider: @escaping AgentEventWorkspaceProvider,
      ownerDeliveryControl: AgentEventDeliveryControl?,
      requestOriginID: UUID,
      preparedResponseOriginID: UUID? = nil,
      now: Date
    ) async throws -> AgentEventCallbackVerificationProof {
      let verificationID = UUID()
      let cancellationFlag = AgentEventVerificationCancellationFlag()
      let task = Task {
        try await monitoringService.anchorAndVerifyPendingSubscription(
          profileID: profileID,
          subscriptionID: subscriptionID,
          workspaceProvider: workspaceProvider,
          ownerDeliveryControl: ownerDeliveryControl,
          requestOriginID: requestOriginID,
          preparedResponseOriginID: preparedResponseOriginID,
          now: now
        )
      }
      let cancel: @Sendable () -> Void = {
        cancellationFlag.cancel()
        task.cancel()
      }
      verificationCancellationActions[subscriptionID, default: [:]][verificationID] = cancel
      defer {
        verificationCancellationActions[subscriptionID]?.removeValue(forKey: verificationID)
        if verificationCancellationActions[subscriptionID]?.isEmpty == true {
          verificationCancellationActions.removeValue(forKey: subscriptionID)
        }
      }
      let proof = try await withTaskCancellationHandler(
        operation: { try await task.value },
        onCancel: cancel
      )
      guard !Task.isCancelled, !cancellationFlag.isCancelled else {
        if proof.originIntentID == requestOriginID {
          try callbackVerificationStore.removeProof(
            for: proof.binding,
            generatedBy: requestOriginID
          )
        }
        throw CancellationError()
      }
      return proof
    }

    private func disposeCancelledPreparation(
      binding: AgentEventCallbackVerificationBinding,
      observedOwnerControl: AgentEventDeliveryControl,
      requestOriginID: UUID
    ) async throws {
      var proofCleanupError: Error?
      do {
        try callbackVerificationStore.removeProof(for: binding, generatedBy: requestOriginID)
      } catch {
        proofCleanupError = error
      }
      guard observedOwnerControl.binding == binding else {
        if let proofCleanupError { throw proofCleanupError }
        return
      }
      let offControl: AgentEventDeliveryControl
      if observedOwnerControl.enabled {
        guard
          let result = try await subscriptionStore.setOwnerDeliveryEligibility(
            binding: binding,
            expectedGenerationID: observedOwnerControl.generationID,
            eligible: false
          ),
          result.binding == binding,
          !result.enabled,
          subscriptionStore.isCurrentOwnerDeliveryControl(binding: binding, control: result)
        else {
          if let proofCleanupError { throw proofCleanupError }
          return
        }
        offControl = result
        resolveOwnerWaiters(for: binding.subscriptionID)
      } else {
        guard
          !observedOwnerControl.enabled,
          subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: binding,
            control: observedOwnerControl
          )
        else {
          if let proofCleanupError { throw proofCleanupError }
          return
        }
        offControl = observedOwnerControl
      }
      guard subscriptionStore.isCurrentOwnerDeliveryControl(
        binding: binding,
        control: offControl
      ) else {
        if let proofCleanupError { throw proofCleanupError }
        return
      }
      cancelVerification(for: binding.subscriptionID)
      cancelDelivery(for: binding.subscriptionID)
      do {
        try outboxService.discardPendingBodies(
          profileID: binding.profileID,
          subscriptionID: binding.subscriptionID,
          disposition: .ownerPaused,
          expectedCancellationBinding: binding,
          expectedCancellationControl: offControl
        )
      } catch AgentEventOutboxError.sourceChanged {
        if let proofCleanupError { throw proofCleanupError }
        return
      }
      if let proofCleanupError { throw proofCleanupError }
    }

    private func scheduleWake(at deadline: Date) {
      let delay = max(1, deadline.timeIntervalSince(now()))
      let milliseconds = max(1_000, Int64(min(delay * 1_000, 604_800_000)))
      scheduledWakeTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(milliseconds))
        guard !Task.isCancelled else { return }
        await self?.signalScheduledWake()
      }
    }

    private func signalScheduledWake() {
      scheduledWakeTask = nil
      commitSignal.signal()
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
      let components = duration.components
      return TimeInterval(components.seconds)
        + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func isCallbackProofCurrent(
      for subscription: AgentEventPendingSubscription,
      now currentTime: Date
    ) -> Bool {
      let binding = Self.binding(for: subscription)
      guard subscription.deliveryControl?.binding == binding,
        subscription.deliveryControl?.enabled == true,
        let proof = try? callbackVerificationStore.currentProof(for: binding)
      else {
        return false
      }
      return proof.binding == binding
        && proof.expiresAt > currentTime
        && proof.expiresAt <= subscription.expiresAt
    }

    private func requireTemporaryExclusionGeneration(_ expected: UUID?) throws {
      guard authority.temporaryExclusionGeneration == expected else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
    }

    private static func binding(
      for subscription: AgentEventPendingSubscription
    ) -> AgentEventCallbackVerificationBinding {
      AgentEventCallbackVerificationBinding(
        profileID: subscription.profileID,
        subscriptionID: subscription.subscriptionID,
        subscriptionRevision: subscription.revision,
        grantRevision: subscription.grantRevision,
        signingKeyReference: subscription.signingKeyReference
      )
    }

    private static func callbackHost(_ callbackURL: String) -> String {
      guard let host = URLComponents(string: callbackURL)?.host, !host.isEmpty else {
        return "Unavailable"
      }
      return host
    }
  }
#endif
