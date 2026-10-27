import FleckCore
import Foundation

struct AgentEventMonitoringService: Sendable {
  private let authority: AgentCapabilityAuthority
  private let outboxService: AgentEventOutboxService
  private let callbackVerificationService: AgentEventCallbackVerificationService
  private let deliveryLedgerService: AgentEventDeliveryLedgerService
  private let deliverySender: AgentEventDeliverySender

  init(
    authority: AgentCapabilityAuthority,
    outboxService: AgentEventOutboxService,
    callbackVerificationService: AgentEventCallbackVerificationService,
    deliveryLedgerService: AgentEventDeliveryLedgerService,
    deliverySender: AgentEventDeliverySender
  ) {
    self.authority = authority
    self.outboxService = outboxService
    self.callbackVerificationService = callbackVerificationService
    self.deliveryLedgerService = deliveryLedgerService
    self.deliverySender = deliverySender
  }

  func anchorAndVerifyPendingSubscription(
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: @escaping AgentEventWorkspaceProvider,
    ownerDeliveryControl: AgentEventDeliveryControl? = nil,
    requestOriginID: UUID? = nil,
    preparedResponseOriginID: UUID? = nil,
    now: Date = Date()
  ) async throws -> AgentEventCallbackVerificationProof {
    let exclusionGeneration = authority.temporaryExclusionGeneration
    let fencedProvider = self.fencedWorkspaceProvider(
      from: workspaceProvider,
      expectedExclusionGeneration: exclusionGeneration
    )
    try requireCurrent(exclusionGeneration)
    try await outboxService.registerPending(
      profileID: profileID,
      subscriptionID: subscriptionID,
      now: now,
      ownerDeliveryControl: ownerDeliveryControl,
      preparedResponseOriginID: preparedResponseOriginID
    )
    try requireCurrent(exclusionGeneration)
    let proof = try await callbackVerificationService.verifyPending(
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: fencedProvider,
      ownerDeliveryControl: ownerDeliveryControl,
      requestOriginID: requestOriginID
    )
    try requireCurrent(exclusionGeneration)
    return proof
  }

  func captureReserveAndSendAtMostOne(
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: @escaping AgentEventWorkspaceProvider,
    now: Date = Date()
  ) async throws -> AgentEventDeliverySenderResult? {
    let exclusionGeneration = authority.temporaryExclusionGeneration
    let fencedProvider = self.fencedWorkspaceProvider(
      from: workspaceProvider,
      expectedExclusionGeneration: exclusionGeneration
    )
    try requireCurrent(exclusionGeneration)
    try await outboxService.capturePending(
      profileID: profileID,
      subscriptionID: subscriptionID,
      now: now
    )
    try requireCurrent(exclusionGeneration)
    guard
      let reservation = try await deliveryLedgerService.reserveNext(
        profileID: profileID,
        subscriptionID: subscriptionID
      )
    else {
      return nil
    }
    do {
      try requireCurrent(exclusionGeneration)
    } catch {
      _ = try? await deliveryLedgerService.cancel(reservation)
      throw error
    }
    return await deliverySender.send(
      reservation,
      workspaceProvider: fencedProvider
    )
  }

  private func fencedWorkspaceProvider(
    from provider: @escaping AgentEventWorkspaceProvider,
    expectedExclusionGeneration: UUID?
  ) -> AgentEventWorkspaceProvider {
    let authority = self.authority
    return {
      guard authority.temporaryExclusionGeneration == expectedExclusionGeneration else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
      let workspace = try await provider()
      guard authority.temporaryExclusionGeneration == expectedExclusionGeneration else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
      return workspace
    }
  }

  private func requireCurrent(_ expectedExclusionGeneration: UUID?) throws {
    guard authority.temporaryExclusionGeneration == expectedExclusionGeneration else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
  }
}
