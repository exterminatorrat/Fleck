import FleckCore
import Foundation

struct AgentEventDeliveryLedgerService: Sendable {
  private struct CurrentSources {
    let outbox: AgentEventOutboxState
    let subscription: AgentEventPendingSubscription
    let progress: AgentEventOutboxProgress

    var binding: AgentEventCallbackVerificationBinding {
      AgentEventCallbackVerificationBinding(
        profileID: subscription.profileID,
        subscriptionID: subscription.subscriptionID,
        subscriptionRevision: subscription.revision,
        grantRevision: subscription.grantRevision,
        signingKeyReference: subscription.signingKeyReference
      )
    }
  }

  private let outboxStore: AgentEventOutboxStore
  private let subscriptionRead: @Sendable (String) async throws -> AgentEventPendingSubscription?
  private let ledgerStore: AgentEventDeliveryLedgerStore

  init(
    outboxStore: AgentEventOutboxStore,
    subscriptionStore: AgentEventSubscriptionStore,
    ledgerStore: AgentEventDeliveryLedgerStore,
    subscriptionRead: (@Sendable (String) async throws -> AgentEventPendingSubscription?)? = nil
  ) {
    self.outboxStore = outboxStore
    self.subscriptionRead =
      subscriptionRead ?? { id in
        try await subscriptionStore.currentSubscription(id: id)
      }
    self.ledgerStore = ledgerStore
  }

  func reserveNext(
    profileID: UUID,
    subscriptionID: String
  ) async throws -> AgentEventDeliveryLedgerReservation? {
    let expectedGeneration = try ledgerStore.currentBindingGeneration(
      profileID: profileID,
      subscriptionID: subscriptionID
    )
    guard
      let current = try await currentSources(
        profileID: profileID,
        subscriptionID: subscriptionID
      )
    else {
      return nil
    }
    let entries = current.outbox.entries
      .filter {
        $0.profileID == profileID && $0.subscriptionID == subscriptionID
          && $0.status == .awaitingVerification
      }
      .sorted { $0.sourcePosition.sequence < $1.sourcePosition.sequence }
    let candidates = try entries.map { entry in
      try makeCandidate(entry, current: current).0
    }
    switch try ledgerStore.reconcileAndReserve(
      candidates: candidates,
      validatedBinding: current.binding,
      expectedGeneration: expectedGeneration
    ) {
    case .reserved(let reservation):
      return reservation
    case .blocked, .skipped:
      return nil
    }
  }

  func observe(
    _ reservation: AgentEventDeliveryLedgerReservation
  ) async throws -> AgentEventDeliveryAttempt {
    let (current, expectedGeneration) = try await requireCurrent(reservation)
    guard
      let (candidate, body) = try candidate(for: reservation, in: current),
      candidate.expiresAt == reservation.expiresAt
    else {
      throw AgentEventDeliveryLedgerError.staleReservation
    }
    try ledgerStore.observe(reservation, expectedGeneration: expectedGeneration)
    return AgentEventDeliveryAttempt(reservation: reservation, body: body)
  }

  func settle(
    _ reservation: AgentEventDeliveryLedgerReservation,
    outcome: AgentEventDeliveryLedgerOutcome
  ) async throws -> AgentEventDeliveryLedgerRecord {
    let (_, expectedGeneration) = try await requireCurrent(
      reservation,
      allowCapacityPausedProgress: true
    )
    return try ledgerStore.settle(
      reservation,
      outcome: outcome,
      expectedGeneration: expectedGeneration
    )
  }

  func cancel(
    _ reservation: AgentEventDeliveryLedgerReservation
  ) async throws -> AgentEventDeliveryLedgerRecord {
    let (_, expectedGeneration) = try await requireCurrent(reservation)
    return try ledgerStore.cancel(reservation, expectedGeneration: expectedGeneration)
  }

  private func currentSources(
    profileID: UUID,
    subscriptionID: String,
    allowCapacityPausedProgress: Bool = false
  ) async throws -> CurrentSources? {
    let initialOutbox = try outboxStore.load()
    let initialSubscription = try await subscriptionRead(subscriptionID)
    let currentOutbox = try outboxStore.load()
    let currentSubscription = try await subscriptionRead(subscriptionID)
    let finalOutbox = try outboxStore.load()
    guard
      initialOutbox == currentOutbox,
      currentOutbox == finalOutbox,
      initialSubscription == currentSubscription
    else {
      throw AgentEventDeliveryLedgerError.sourceChanged
    }
    guard let subscription = currentSubscription,
      subscription.subscriptionID == subscriptionID,
      subscription.profileID == profileID,
      subscription.status == .pending,
      AgentEventDeliveryLedgerStore.isValidDate(subscription.expiresAt),
      let progress = currentOutbox.progress.first(where: {
        $0.profileID == profileID && $0.subscriptionID == subscriptionID
      }),
      progress.status == .pending
        || (allowCapacityPausedProgress && progress.status == .pausedCapacity),
      progress.subscriptionRevision == subscription.revision,
      progress.grantRevision == subscription.grantRevision,
      let anchor = progress.anchor,
      let capturedThrough = progress.capturedThrough,
      anchor.epoch == capturedThrough.epoch
    else {
      return nil
    }
    return CurrentSources(outbox: finalOutbox, subscription: subscription, progress: progress)
  }

  private func requireCurrent(
    _ reservation: AgentEventDeliveryLedgerReservation,
    allowCapacityPausedProgress: Bool = false
  ) async throws -> (CurrentSources, AgentEventDeliveryLedgerBindingGeneration) {
    let expectedGeneration = try ledgerStore.currentBindingGeneration(
      profileID: reservation.binding.profileID,
      subscriptionID: reservation.binding.subscriptionID
    )
    guard
      let expectedGeneration,
      expectedGeneration.binding == reservation.binding,
      expectedGeneration.generationID == reservation.bindingGenerationID,
      let current = try await currentSources(
        profileID: reservation.binding.profileID,
        subscriptionID: reservation.binding.subscriptionID,
        allowCapacityPausedProgress: allowCapacityPausedProgress
      ), current.binding == reservation.binding,
      let (candidate, _) = try candidate(for: reservation, in: current),
      candidate.expiresAt == reservation.expiresAt
    else {
      throw AgentEventDeliveryLedgerError.staleReservation
    }
    return (current, expectedGeneration)
  }

  private func candidate(
    for reservation: AgentEventDeliveryLedgerReservation,
    in current: CurrentSources
  ) throws -> (AgentEventDeliveryLedgerCandidate, Data)? {
    guard
      let entry = current.outbox.entries.first(where: {
        $0.profileID == reservation.binding.profileID
          && $0.subscriptionID == reservation.binding.subscriptionID
          && $0.eventID == reservation.eventID
          && $0.sourcePosition == reservation.sourcePosition
          && $0.status == .awaitingVerification
      })
    else {
      return nil
    }
    let result = try makeCandidate(entry, current: current)
    guard result.0.binding == reservation.binding else { return nil }
    return result
  }

  private func makeCandidate(
    _ entry: AgentEventOutboxEntry,
    current: CurrentSources
  ) throws -> (AgentEventDeliveryLedgerCandidate, Data) {
    guard
      entry.profileID == current.subscription.profileID,
      entry.subscriptionID == current.subscription.subscriptionID,
      entry.status == .awaitingVerification,
      entry.sourcePosition.epoch == current.progress.anchor?.epoch,
      entry.sourcePosition.sequence > (current.progress.anchor?.sequence ?? UInt64.max),
      entry.sourcePosition.sequence <= (current.progress.capturedThrough?.sequence ?? 0),
      let body = entry.body,
      let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: body),
      envelope.eventID == entry.eventID,
      envelope.name == current.subscription.event,
      envelope.cursor == nil,
      let eventTimestamp = Self.date(from: envelope.timestamp)
    else {
      throw AgentEventDeliveryLedgerError.sourceChanged
    }
    let candidate = AgentEventDeliveryLedgerCandidate(
      binding: current.binding,
      eventID: entry.eventID,
      sourcePosition: entry.sourcePosition,
      eventTimestamp: eventTimestamp,
      subscriptionExpiresAt: current.subscription.expiresAt
    )
    guard candidate.expiresAt != nil else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    return (candidate, body)
  }

  private static func date(from timestamp: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp)
  }
}
