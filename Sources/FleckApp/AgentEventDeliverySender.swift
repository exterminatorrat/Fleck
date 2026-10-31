import Foundation

typealias AgentEventDeliveryExchange =
  @Sendable (
    String,
    [AgentEventHTTPHeader],
    Data
  ) async throws -> AgentEventHTTPResponse

enum AgentEventDeliverySenderResult: Equatable, Sendable {
  case busy
  case denied
  case settled(AgentEventDeliveryLedgerRecordStatus)
  case settlementFailed
}

actor AgentEventDeliverySender {
  private let ledgerService: AgentEventDeliveryLedgerService
  private let authorizationService: AgentEventDeliveryAuthorizationService
  private let subscriptionStore: AgentEventSubscriptionStore
  private let signingKeyStore: AgentEventSigningKeyStore
  private let now: @Sendable () -> Date
  private let exchange: AgentEventDeliveryExchange
  private var isSending = false

  init(
    ledgerService: AgentEventDeliveryLedgerService,
    authorizationService: AgentEventDeliveryAuthorizationService,
    subscriptionStore: AgentEventSubscriptionStore,
    signingKeyStore: AgentEventSigningKeyStore,
    now: @escaping @Sendable () -> Date,
    exchange: @escaping AgentEventDeliveryExchange
  ) {
    self.ledgerService = ledgerService
    self.authorizationService = authorizationService
    self.subscriptionStore = subscriptionStore
    self.signingKeyStore = signingKeyStore
    self.now = now
    self.exchange = exchange
  }

  func send(
    _ reservation: AgentEventDeliveryLedgerReservation,
    workspaceProvider: AgentEventWorkspaceProvider
  ) async -> AgentEventDeliverySenderResult {
    guard !isSending else { return .busy }
    isSending = true
    defer { isSending = false }
    let expectedTemporaryExclusionGeneration =
      authorizationService.temporaryExclusionGeneration

    if Task.isCancelled { return await settleCancelled(reservation) }

    let attempt: AgentEventDeliveryAttempt
    do {
      attempt = try await ledgerService.observe(reservation)
    } catch {
      if Task.isCancelled { return await settleCancelled(reservation) }
      return .denied
    }
    if Task.isCancelled { return await settleCancelled(reservation) }
    guard
      authorizationService.temporaryExclusionGeneration
        == expectedTemporaryExclusionGeneration
    else {
      return .denied
    }

    let eligibilityObservation = await authorizationService.observeEligibility(
      for: attempt,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      workspaceProvider: workspaceProvider
    )
    if Task.isCancelled { return await settleCancelled(reservation) }
    guard
      let observation = eligibilityObservation,
      authorizationService.temporaryExclusionGeneration
        == expectedTemporaryExclusionGeneration
    else {
      return .denied
    }

    let currentSubscription: AgentEventPendingSubscription?
    do {
      currentSubscription = try await subscriptionStore.currentSubscription(
        id: reservation.binding.subscriptionID
      )
    } catch {
      if Task.isCancelled { return await settleCancelled(reservation) }
      return .denied
    }
    if Task.isCancelled { return await settleCancelled(reservation) }
    guard
      authorizationService.temporaryExclusionGeneration
        == expectedTemporaryExclusionGeneration
    else {
      return .denied
    }
    guard let subscription = currentSubscription,
      Self.binding(for: subscription) == reservation.binding
    else {
      return .denied
    }

    let signingTime = now()
    if Task.isCancelled { return await settleCancelled(reservation) }
    guard Self.isValidSigningTime(signingTime, reservation: reservation, subscription: subscription)
    else {
      return .denied
    }
    let secret: Data
    do {
      secret = try signingKeyStore.validatedSecretData(
        reference: subscription.signingKeyReference
      )
    } catch {
      if Task.isCancelled { return await settleCancelled(reservation) }
      return .denied
    }
    if Task.isCancelled { return await settleCancelled(reservation) }

    let previousSecret: Data?
    if let overlap = subscription.previousSigningKey, overlap.startedAt <= signingTime,
      signingTime < overlap.expiresAt
    {
      do {
        previousSecret = try signingKeyStore.validatedSecretData(reference: overlap.reference)
      } catch {
        if Task.isCancelled { return await settleCancelled(reservation) }
        return .denied
      }
    } else {
      previousSecret = nil
    }

    if Task.isCancelled { return await settleCancelled(reservation) }

    let authorizationIsCurrent = await authorizationService.isCurrent(
      observation,
      for: attempt,
      workspaceProvider: workspaceProvider
    )
    if Task.isCancelled { return await settleCancelled(reservation) }
    guard
      authorizationIsCurrent,
      authorizationService.temporaryExclusionGeneration
        == expectedTemporaryExclusionGeneration
    else {
      return .denied
    }

    let finalSubscription: AgentEventPendingSubscription?
    do {
      finalSubscription = try await subscriptionStore.currentSubscription(
        id: reservation.binding.subscriptionID
      )
    } catch {
      if Task.isCancelled { return await settleCancelled(reservation) }
      return .denied
    }
    if Task.isCancelled { return await settleCancelled(reservation) }
    guard let finalSubscription,
      Self.binding(for: finalSubscription) == reservation.binding,
      finalSubscription.previousSigningKey == subscription.previousSigningKey
        || (subscription.previousSigningKey != nil && finalSubscription.previousSigningKey == nil),
      finalSubscription.replacingPreviousSigningKey(subscription.previousSigningKey) == subscription,
      authorizationService.temporaryExclusionGeneration == expectedTemporaryExclusionGeneration
    else {
      return .denied
    }
    let exchangeSigningTime = now()
    guard exchangeSigningTime >= signingTime,
      Self.isValidSigningTime(
        exchangeSigningTime,
        reservation: reservation,
        subscription: finalSubscription
      )
    else {
      return .denied
    }
    let exchangePreviousSecret: Data?
    if let overlap = finalSubscription.previousSigningKey,
      overlap == subscription.previousSigningKey,
      overlap.startedAt <= exchangeSigningTime,
      exchangeSigningTime < overlap.expiresAt
    {
      guard let previousSecret else { return .denied }
      exchangePreviousSecret = previousSecret
    } else {
      exchangePreviousSecret = nil
    }
    let signature: AgentEventWebhookSignature
    do {
      signature = try AgentEventWebhookSigner.sign(
        id: reservation.eventID,
        timestamp: signingTime,
        body: attempt.body,
        secret: secret,
        previousSecret: exchangePreviousSecret
      )
    } catch {
      if Task.isCancelled { return await settleCancelled(reservation) }
      return .denied
    }
    let headers = [
      AgentEventHTTPHeader(name: "content-type", value: "application/json"),
      AgentEventHTTPHeader(name: "webhook-id", value: signature.webhookID),
      AgentEventHTTPHeader(name: "webhook-timestamp", value: signature.webhookTimestamp),
      AgentEventHTTPHeader(name: "webhook-signature", value: signature.webhookSignature),
      AgentEventHTTPHeader(name: "x-mcp-subscription-id", value: finalSubscription.subscriptionID),
    ]

    let outcome: AgentEventDeliveryLedgerOutcome
    if Task.isCancelled {
      outcome = .cancelled
    } else {
      do {
        let response = try await exchange(finalSubscription.callbackURL, headers, attempt.body)
        if Task.isCancelled {
          outcome = .cancelled
        } else {
          outcome = .httpStatus(
            response.statusCode,
            retryAfter: Self.boundedRetryAfter(response.retryAfterSeconds)
          )
        }
      } catch {
        outcome =
          (Task.isCancelled || Self.isCancellation(error))
          ? .cancelled
          : .transportFailure
      }
    }

    do {
      let record = try await ledgerService.settle(reservation, outcome: outcome)
      return .settled(record.status)
    } catch {
      return .settlementFailed
    }
  }

  private func settleCancelled(
    _ reservation: AgentEventDeliveryLedgerReservation
  ) async -> AgentEventDeliverySenderResult {
    do {
      let record = try await ledgerService.settle(reservation, outcome: .cancelled)
      return .settled(record.status)
    } catch {
      return .settlementFailed
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

  private static func isValidSigningTime(
    _ timestamp: Date,
    reservation: AgentEventDeliveryLedgerReservation,
    subscription: AgentEventPendingSubscription
  ) -> Bool {
    let timestampSeconds = timestamp.timeIntervalSince1970
    return timestampSeconds.isFinite
      && timestampSeconds >= 0
      && reservation.expiresAt.timeIntervalSince1970.isFinite
      && reservation.leaseDeadline.timeIntervalSince1970.isFinite
      && subscription.expiresAt.timeIntervalSince1970.isFinite
      && timestamp < reservation.expiresAt
      && timestamp < reservation.leaseDeadline
      && timestamp < subscription.expiresAt
  }

  private static func boundedRetryAfter(_ value: TimeInterval?) -> TimeInterval? {
    guard let value,
      value.isFinite,
      (0...Double(AgentEventHTTPTransport.maximumRetryAfterSeconds)).contains(value)
    else {
      return nil
    }
    return value
  }

  private static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? AgentEventHTTPTransportError) == .cancelled
  }
}
