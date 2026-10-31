import FleckCore
import Foundation

struct AgentEventDeliveryEligibilityObservation: Equatable, Sendable {
  let profileID: UUID
  let subscriptionID: String
  let eventID: String
  let reservationID: UUID
  let ledgerGenerationID: String
  let ownerControlGenerationID: UUID
  let proofGenerationID: UUID
  let expectedTemporaryExclusionGeneration: UUID?
}

struct AgentEventDeliveryAuthorizationService: Sendable {
  private let authority: AgentCapabilityAuthority
  private let profileStore: AgentProfileStore
  private let subscriptionStore: AgentEventSubscriptionStore
  private let verificationStore: AgentEventCallbackVerificationStore
  private let outboxStore: AgentEventOutboxStore
  private let ledgerStore: AgentEventDeliveryLedgerStore
  private let now: @Sendable () -> Date

  var temporaryExclusionGeneration: UUID? {
    authority.temporaryExclusionGeneration
  }

  init(
    authority: AgentCapabilityAuthority,
    profileStore: AgentProfileStore,
    subscriptionStore: AgentEventSubscriptionStore,
    verificationStore: AgentEventCallbackVerificationStore,
    outboxStore: AgentEventOutboxStore,
    ledgerStore: AgentEventDeliveryLedgerStore,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.authority = authority
    self.profileStore = profileStore
    self.subscriptionStore = subscriptionStore
    self.verificationStore = verificationStore
    self.outboxStore = outboxStore
    self.ledgerStore = ledgerStore
    self.now = now
  }

  func observeEligibility(
    for attempt: AgentEventDeliveryAttempt,
    workspaceProvider: AgentEventWorkspaceProvider
  ) async -> AgentEventDeliveryEligibilityObservation? {
    let expectedTemporaryExclusionGeneration = authority.temporaryExclusionGeneration
    return await observeEligibility(
      for: attempt,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      workspaceProvider: workspaceProvider
    )
  }

  func observeEligibility(
    for attempt: AgentEventDeliveryAttempt,
    expectedTemporaryExclusionGeneration: UUID?,
    workspaceProvider: AgentEventWorkspaceProvider
  ) async -> AgentEventDeliveryEligibilityObservation? {
    let reservation = attempt.reservation
    let binding = reservation.binding
    let startedAt = now()
    guard
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      Self.isValidDate(startedAt),
      Self.isValidDate(reservation.expiresAt),
      Self.isValidDate(reservation.leaseDeadline),
      reservation.attemptCount > 0,
      startedAt < reservation.expiresAt,
      startedAt < reservation.leaseDeadline
    else {
      return nil
    }
    guard
      let expectedLedgerGeneration = try? ledgerStore.currentBindingGeneration(
        profileID: binding.profileID,
        subscriptionID: binding.subscriptionID
      ),
      expectedLedgerGeneration.binding == binding,
      expectedLedgerGeneration.generationID == reservation.bindingGenerationID,
      let proof = try? verificationStore.currentProof(for: binding),
      proof.binding == binding,
      Self.isValidDate(proof.verifiedAt),
      Self.isValidDate(proof.expiresAt),
      proof.verifiedAt <= startedAt,
      startedAt < proof.expiresAt
    else {
      return nil
    }

    guard
      let initialSubscription = try? await subscriptionStore.currentSubscription(
        id: binding.subscriptionID
      ),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      Self.binding(for: initialSubscription) == binding,
      initialSubscription.status == .pending,
      Self.isValidDate(initialSubscription.expiresAt),
      startedAt < initialSubscription.expiresAt,
      proof.expiresAt <= initialSubscription.expiresAt,
      let ownerControl = initialSubscription.deliveryControl,
      ownerControl.binding == binding,
      ownerControl.enabled,
      let event = Self.event(
        in: attempt.body,
        reservation: reservation,
        subscription: initialSubscription,
        now: startedAt
      ),
      Self.matchesOutbox(
        try? outboxStore.load(),
        attempt: attempt,
        subscription: initialSubscription,
        binding: binding
      )
    else {
      return nil
    }

    guard
      let firstProfiles = try? await profileStore.activeProfiles(),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      firstProfiles.contains(where: { $0.id == binding.profileID && !$0.isRevoked })
    else {
      return nil
    }
    let initialWorkspace: Workspace
    do {
      initialWorkspace = try await workspaceProvider()
    } catch {
      return nil
    }
    guard authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
      return nil
    }
    guard
      let initialGrantRevision = try? await authority.authorizeEventObservation(
        profileID: binding.profileID,
        scope: initialSubscription.scope,
        workspace: initialWorkspace
      ),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      initialGrantRevision == binding.grantRevision,
      let initialAuthorization = try? await authority.snapshot(
        profileID: binding.profileID,
        workspace: initialWorkspace
      ),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      initialAuthorization.profileID == binding.profileID,
      initialAuthorization.grantRevision == binding.grantRevision,
      Self.isReadable(event.noteID, scope: initialSubscription.scope, workspace: initialWorkspace),
      initialAuthorization.readableNoteIDs.contains(event.noteID)
    else {
      return nil
    }

    do {
      try await authority.assertEventObservationCurrent(
        profileID: binding.profileID,
        grantRevision: binding.grantRevision,
        scope: initialSubscription.scope,
        workspace: initialWorkspace
      )
      guard authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
        return nil
      }
    } catch {
      return nil
    }
    let currentWorkspace: Workspace
    do {
      currentWorkspace = try await workspaceProvider()
    } catch {
      return nil
    }
    guard
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      currentWorkspace == initialWorkspace,
      Self.isReadable(event.noteID, scope: initialSubscription.scope, workspace: currentWorkspace),
      let latestProfiles = try? await profileStore.activeProfiles(),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      latestProfiles.contains(where: { $0.id == binding.profileID && !$0.isRevoked })
    else {
      return nil
    }
    do {
      try await authority.assertEventObservationCurrent(
        profileID: binding.profileID,
        grantRevision: binding.grantRevision,
        scope: initialSubscription.scope,
        workspace: currentWorkspace
      )
      guard authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
        return nil
      }
    } catch {
      return nil
    }
    guard
      let currentSubscription = try? await subscriptionStore.currentSubscription(
        id: binding.subscriptionID
      ),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      currentSubscription == initialSubscription
    else {
      return nil
    }

    let finishedAt = now()
    guard
      Self.isValidDate(finishedAt),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration,
      finishedAt >= startedAt,
      finishedAt < reservation.expiresAt,
      finishedAt < reservation.leaseDeadline,
      finishedAt < currentSubscription.expiresAt,
      finishedAt < proof.expiresAt,
      event.timestamp <= finishedAt,
      (try? verificationStore.currentProof(for: binding)) == proof,
      let finalLedgerGeneration = try? ledgerStore.currentBindingGeneration(
        profileID: binding.profileID,
        subscriptionID: binding.subscriptionID
      ),
      finalLedgerGeneration == expectedLedgerGeneration,
      Self.matchesOutbox(
        try? outboxStore.load(),
        attempt: attempt,
        subscription: currentSubscription,
        binding: binding
      )
    else {
      return nil
    }
    do {
      try ledgerStore.observe(reservation, expectedGeneration: expectedLedgerGeneration)
    } catch {
      return nil
    }
    guard authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
      return nil
    }
    guard
      subscriptionStore.isCurrentOwnerDeliveryControl(
        binding: binding,
        generationID: ownerControl.generationID
      ),
      authority.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration
    else {
      return nil
    }
    return AgentEventDeliveryEligibilityObservation(
      profileID: binding.profileID,
      subscriptionID: binding.subscriptionID,
      eventID: reservation.eventID,
      reservationID: reservation.id,
      ledgerGenerationID: reservation.bindingGenerationID,
      ownerControlGenerationID: ownerControl.generationID,
      proofGenerationID: proof.originIntentID,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration
    )
  }

  func isCurrent(
    _ observation: AgentEventDeliveryEligibilityObservation,
    for attempt: AgentEventDeliveryAttempt,
    workspaceProvider: AgentEventWorkspaceProvider
  ) async -> Bool {
    guard
      observation.expectedTemporaryExclusionGeneration == authority.temporaryExclusionGeneration,
      observation.profileID == attempt.reservation.binding.profileID,
      observation.subscriptionID == attempt.reservation.binding.subscriptionID,
      observation.eventID == attempt.reservation.eventID,
      observation.reservationID == attempt.reservation.id,
      observation.ledgerGenerationID == attempt.reservation.bindingGenerationID,
      let current = await observeEligibility(
        for: attempt,
        expectedTemporaryExclusionGeneration: observation.expectedTemporaryExclusionGeneration,
        workspaceProvider: workspaceProvider
      )
    else {
      return false
    }
    return
      authority.temporaryExclusionGeneration == observation.expectedTemporaryExclusionGeneration
      && current == observation
  }

  private struct Event {
    let noteID: UUID
    let timestamp: Date
  }

  private static func event(
    in body: Data,
    reservation: AgentEventDeliveryLedgerReservation,
    subscription: AgentEventPendingSubscription,
    now: Date
  ) -> Event? {
    guard
      let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: body),
      envelope.eventID == reservation.eventID,
      envelope.name == subscription.event,
      envelope.cursor == nil,
      let timestamp = date(from: envelope.timestamp),
      isValidDate(timestamp),
      timestamp <= now
    else {
      return nil
    }
    let eventExpiry = timestamp.addingTimeInterval(AgentEventDeliveryLedgerStore.maximumRetention)
    guard
      isValidDate(eventExpiry),
      eventExpiry > timestamp,
      min(eventExpiry, subscription.expiresAt) == reservation.expiresAt
    else {
      return nil
    }
    let noteID: UUID
    switch envelope.data {
    case .noteCreated(let id, _, _):
      noteID = id
    case .noteUpdated(let id, _, _, _):
      noteID = id
    case .taskStateChanged(let id, _, _, _):
      noteID = id
    }
    return Event(noteID: noteID, timestamp: timestamp)
  }

  private static func matchesOutbox(
    _ state: AgentEventOutboxState?,
    attempt: AgentEventDeliveryAttempt,
    subscription: AgentEventPendingSubscription,
    binding: AgentEventCallbackVerificationBinding
  ) -> Bool {
    let reservation = attempt.reservation
    guard
      let state,
      Self.binding(for: subscription) == binding,
      let progress = state.progress.first(where: {
        $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
      }),
      progress.status == .pending,
      progress.subscriptionRevision == binding.subscriptionRevision,
      progress.grantRevision == binding.grantRevision,
      let ownerDeliveryControl = subscription.deliveryControl,
      ownerDeliveryControl.binding == binding,
      progress.preparedResponseFence?.blocksDelivery(for: ownerDeliveryControl) != true,
      let anchor = progress.anchor,
      let capturedThrough = progress.capturedThrough,
      anchor.epoch == reservation.sourcePosition.epoch,
      capturedThrough.epoch == reservation.sourcePosition.epoch,
      reservation.sourcePosition.sequence > anchor.sequence,
      reservation.sourcePosition.sequence <= capturedThrough.sequence,
      let entry = state.entries.first(where: {
        $0.profileID == binding.profileID
          && $0.subscriptionID == binding.subscriptionID
          && $0.eventID == reservation.eventID
          && $0.sourcePosition == reservation.sourcePosition
          && $0.status == .awaitingVerification
      }),
      entry.body == attempt.body
    else {
      return false
    }
    return true
  }

  private static func isReadable(
    _ noteID: UUID,
    scope: AgentEventScope,
    workspace: Workspace
  ) -> Bool {
    guard let note = workspace.notes.first(where: { $0.id == noteID }) else { return false }
    switch scope {
    case .note(let scopedNoteID):
      return scopedNoteID == noteID
    case .folder(let folderID):
      return note.folderID == folderID && workspace.folders.contains(where: { $0.id == folderID })
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

  private static func date(from timestamp: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp)
  }

  private static func isValidDate(_ date: Date) -> Bool {
    date.timeIntervalSince1970.isFinite
  }
}
