import FleckCore
import Foundation
import FleckMCPFixtureSupport
import Testing

@testable import FleckApp
@testable import FleckCore

@Suite(.serialized)
struct AgentEventDeliveryAuthorizationTests {
  @Test func ownerControlOffDeniesFreshProofAndLiveReservation() async throws {
    let fixture = try await DeliveryAuthorizationFixture.make()
    defer { fixture.remove() }

    let row = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID))
    #expect(row.deliveryControl?.enabled == false)
    #expect(try fixture.verificationStore.currentProof(for: fixture.binding) != nil)
    #expect(fixture.attempt.reservation.binding == fixture.binding)

    let observation = await fixture.authorizationService().observeEligibility(
      for: fixture.attempt,
      workspaceProvider: { fixture.workspace }
    )
    #expect(observation == nil)
    #expect(fixture.secretProbe.operationCounts == (0, 0, 0))
  }

  @Test func proofOnlyPendingOnlyAndReservationOnlyNeverQualify() async throws {
    let proofOnly = try await DeliveryAuthorizationFixture.make(
      includeProof: true,
      liveReservation: false
    )
    defer { proofOnly.remove() }
    _ = try await proofOnly.subscriptionStore.remove(
      subscriptionID: proofOnly.subscriptionID,
      profileID: proofOnly.profileID
    )
    #expect(try proofOnly.verificationStore.currentProof(for: proofOnly.binding) != nil)
    #expect(
      await proofOnly.authorizationService().observeEligibility(
        for: proofOnly.attempt,
        workspaceProvider: { proofOnly.workspace }
      ) == nil
    )

    let pendingOnly = try await DeliveryAuthorizationFixture.make(
      includeProof: false,
      liveReservation: false
    )
    defer { pendingOnly.remove() }
    #expect(
      try await pendingOnly.subscriptionStore.currentSubscription(id: pendingOnly.subscriptionID)
        != nil
    )
    #expect(
      await pendingOnly.authorizationService().observeEligibility(
        for: pendingOnly.attempt,
        workspaceProvider: { pendingOnly.workspace }
      ) == nil
    )

    let reservationOnly = try await DeliveryAuthorizationFixture.make(
      includeProof: false,
      liveReservation: true
    )
    defer { reservationOnly.remove() }
    #expect(try reservationOnly.verificationStore.currentProof(for: reservationOnly.binding) == nil)
    #expect(
      await reservationOnly.authorizationService().observeEligibility(
        for: reservationOnly.attempt,
        workspaceProvider: { reservationOnly.workspace }
      ) == nil
    )
  }

  @Test func currentOwnerProofPermissionAndReservationProduceOnlyRecheckableObservation()
    async throws
  {
    let fixture = try await DeliveryAuthorizationFixture.make()
    defer { fixture.remove() }
    let off = try #require(
      try await fixture.subscriptionStore.currentSubscription(
        id: fixture.subscriptionID
      )?.deliveryControl
    )
    let on = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: fixture.binding,
        expectedGenerationID: off.generationID,
        eligible: true
      )
    )
    let service = fixture.authorizationService()
    let observation = try #require(
      await service.observeEligibility(
        for: fixture.attempt,
        workspaceProvider: { fixture.workspace }
      )
    )
    #expect(observation.eventID == fixture.eventID)
    #expect(observation.reservationID == fixture.attempt.reservation.id)
    #expect(observation.ownerControlGenerationID == on.generationID)
    let proof = try #require(try fixture.verificationStore.currentProof(for: fixture.binding))
    #expect(observation.proofGenerationID == proof.originIntentID)
    #expect(
      await service.isCurrent(
        observation,
        for: fixture.attempt,
        workspaceProvider: { fixture.workspace }
      )
    )

    let offAgain = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: fixture.binding,
        expectedGenerationID: on.generationID,
        eligible: false
      )
    )
    #expect(!offAgain.enabled)
    #expect(offAgain.generationID != on.generationID)
    #expect(
      !(await service.isCurrent(
        observation,
        for: fixture.attempt,
        workspaceProvider: { fixture.workspace }
      ))
    )
    #expect(
      await service.observeEligibility(
        for: fixture.attempt,
        workspaceProvider: { fixture.workspace }
      ) == nil
    )
    #expect(fixture.secretProbe.operationCounts == (0, 0, 0))
  }

  @Test func finalOwnerControlValidationRejectsAnOffWriteAfterTheActorSnapshot() async throws {
    let fixture = try await DeliveryAuthorizationFixture.make()
    defer { fixture.remove() }
    try await fixture.enableOwnerControl()
    let original = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)?
        .deliveryControl
    )
    let invocations = DeliveryAuthorizationNowInvocationCounter()
    let clock = fixture.clock
    let subscriptionURL = fixture.subscriptionURL
    let service = fixture.authorizationService(now: {
      if invocations.next() == 2 {
        _ = disableOwnerControlSynchronously(at: subscriptionURL)
      }
      return clock.now()
    })

    #expect(
      await service.observeEligibility(
        for: fixture.attempt,
        workspaceProvider: { fixture.workspace }
      ) == nil
    )
    let current = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)?
        .deliveryControl
    )
    #expect(!current.enabled)
    #expect(current.generationID != original.generationID)
  }

  @Test func unreadableMovedExcludedAndUnavailableWorkspaceContextsDeny() async throws {
    let noteFixture = try await DeliveryAuthorizationFixture.make()
    defer { noteFixture.remove() }
    try await noteFixture.enableOwnerControl()
    let service = noteFixture.authorizationService()
    #expect(
      await service.observeEligibility(
        for: noteFixture.attempt,
        workspaceProvider: { Workspace() }
      ) == nil
    )
    noteFixture.authority.exclude(noteID: noteFixture.noteID)
    #expect(
      await service.observeEligibility(
        for: noteFixture.attempt,
        workspaceProvider: { noteFixture.workspace }
      ) == nil
    )
    noteFixture.authority.include(noteID: noteFixture.noteID)
    #expect(
      await service.observeEligibility(
        for: noteFixture.attempt,
        workspaceProvider: { throw AgentWorkspaceError(code: .capabilityDenied) }
      ) == nil
    )

    let folderFixture = try await DeliveryAuthorizationFixture.make(scope: .folder)
    defer { folderFixture.remove() }
    try await folderFixture.enableOwnerControl()
    var movedWorkspace = folderFixture.workspace
    try movedWorkspace.moveNote(id: folderFixture.noteID, toFolderID: nil)
    let movedWorkspaceSnapshot = movedWorkspace
    #expect(
      await folderFixture.authorizationService().observeEligibility(
        for: folderFixture.attempt,
        workspaceProvider: { movedWorkspaceSnapshot }
      ) == nil
    )

    let inaccessibleFolder = try await DeliveryAuthorizationFixture.make(
      scope: .folder,
      grantFolder: false
    )
    defer { inaccessibleFolder.remove() }
    try await inaccessibleFolder.enableOwnerControl()
    #expect(
      await inaccessibleFolder.authorizationService().observeEligibility(
        for: inaccessibleFolder.attempt,
        workspaceProvider: { inaccessibleFolder.workspace }
      ) == nil
    )
  }

  @Test func changesDuringWorkspaceSuspensionInvalidateControlProofGrantProfileAndLease()
    async throws
  {
    for change in DeliveryAuthorizationSuspendedChange.allCases {
      #expect(try await deniedDuringWorkspaceSuspension(change))
    }
  }

  @Test func temporaryExclusionChangesDuringWorkspaceSuspensionDenyEligibility() async throws {
    for reinclude in [false, true] {
      let fixture = try await DeliveryAuthorizationFixture.make()
      defer { fixture.remove() }
      try await fixture.enableOwnerControl()
      let gate = DeliveryAuthorizationWorkspaceGate(workspace: fixture.workspace)
      let service = fixture.authorizationService()
      let attempt = fixture.attempt
      let observation = Task {
        await service.observeEligibility(
          for: attempt,
          workspaceProvider: { await gate.next() }
        )
      }

      await gate.waitUntilEntered()
      fixture.authority.exclude(noteID: fixture.noteID)
      if reinclude {
        fixture.authority.include(noteID: fixture.noteID)
      }
      await gate.release()

      #expect(await observation.value == nil)
      #expect(try fixture.verificationStore.currentProof(for: fixture.binding) != nil)
      #expect(fixture.secretProbe.operationCounts == (0, 0, 0))
    }
  }

  @Test func finiteProofEventSubscriptionAndLeaseDeadlinesAreRequired() async throws {
    let base = DeliveryAuthorizationFixture.baseDate

    let expiredProof = try await DeliveryAuthorizationFixture.make(
      proofVerifiedAt: base.addingTimeInterval(-590)
    )
    defer { expiredProof.remove() }
    try await expiredProof.enableOwnerControl()
    let proofService = expiredProof.authorizationService()
    #expect(
      await proofService.observeEligibility(
        for: expiredProof.attempt,
        workspaceProvider: { expiredProof.workspace }
      ) != nil
    )
    expiredProof.clock.set(base.addingTimeInterval(11))
    #expect(
      await proofService.observeEligibility(
        for: expiredProof.attempt,
        workspaceProvider: { expiredProof.workspace }
      ) == nil
    )

    let expiredEvent = try await DeliveryAuthorizationFixture.make(
      eventTimestamp: base.addingTimeInterval(-AgentEventDeliveryLedgerStore.maximumRetention + 5)
    )
    defer { expiredEvent.remove() }
    try await expiredEvent.enableOwnerControl()
    let eventService = expiredEvent.authorizationService()
    #expect(
      await eventService.observeEligibility(
        for: expiredEvent.attempt,
        workspaceProvider: { expiredEvent.workspace }
      ) != nil
    )
    expiredEvent.clock.set(base.addingTimeInterval(6))
    #expect(
      await eventService.observeEligibility(
        for: expiredEvent.attempt,
        workspaceProvider: { expiredEvent.workspace }
      ) == nil
    )

    let expiredSubscription = try await DeliveryAuthorizationFixture.make(
      subscriptionUpdatedAt: base.addingTimeInterval(-55),
      subscriptionExpiresAt: base.addingTimeInterval(5),
      proofVerifiedAt: base.addingTimeInterval(-55)
    )
    defer { expiredSubscription.remove() }
    try await expiredSubscription.enableOwnerControl()
    let subscriptionService = expiredSubscription.authorizationService()
    #expect(
      await subscriptionService.observeEligibility(
        for: expiredSubscription.attempt,
        workspaceProvider: { expiredSubscription.workspace }
      ) != nil
    )
    expiredSubscription.clock.set(base.addingTimeInterval(6))
    #expect(
      await subscriptionService.observeEligibility(
        for: expiredSubscription.attempt,
        workspaceProvider: { expiredSubscription.workspace }
      ) == nil
    )

    let expiredLease = try await DeliveryAuthorizationFixture.make()
    defer { expiredLease.remove() }
    try await expiredLease.enableOwnerControl()
    let leaseService = expiredLease.authorizationService()
    #expect(
      await leaseService.observeEligibility(
        for: expiredLease.attempt,
        workspaceProvider: { expiredLease.workspace }
      ) != nil
    )
    expiredLease.clock.set(base.addingTimeInterval(31))
    #expect(
      await leaseService.observeEligibility(
        for: expiredLease.attempt,
        workspaceProvider: { expiredLease.workspace }
      ) == nil
    )
  }

  @Test func nonFiniteCurrentTimeAndLeaseDeadlineDeny() async throws {
    let currentTimeFixture = try await DeliveryAuthorizationFixture.make()
    defer { currentTimeFixture.remove() }
    try await currentTimeFixture.enableOwnerControl()
    let currentTimeService = currentTimeFixture.authorizationService(now: {
      Date(timeIntervalSince1970: .infinity)
    })
    #expect(
      await currentTimeService.observeEligibility(
        for: currentTimeFixture.attempt,
        workspaceProvider: { currentTimeFixture.workspace }
      ) == nil
    )

    let leaseFixture = try await DeliveryAuthorizationFixture.make()
    defer { leaseFixture.remove() }
    try await leaseFixture.enableOwnerControl()
    let reservation = leaseFixture.attempt.reservation
    let invalidLeaseAttempt = AgentEventDeliveryAttempt(
      reservation: AgentEventDeliveryLedgerReservation(
        id: reservation.id,
        binding: reservation.binding,
        bindingGenerationID: reservation.bindingGenerationID,
        eventID: reservation.eventID,
        sourcePosition: reservation.sourcePosition,
        expiresAt: reservation.expiresAt,
        attemptCount: reservation.attemptCount,
        leaseDeadline: Date(timeIntervalSince1970: .infinity)
      ),
      body: leaseFixture.attempt.body
    )
    #expect(
      await leaseFixture.authorizationService().observeEligibility(
        for: invalidLeaseAttempt,
        workspaceProvider: { leaseFixture.workspace }
      ) == nil
    )
  }
}

private enum DeliveryAuthorizationSuspendedChange: CaseIterable {
  case ownerABA
  case proofReplacement
  case grantRevocation
  case profileRevocation
  case reservationCancellation
  case leaseExpiry
}

private func deniedDuringWorkspaceSuspension(
  _ change: DeliveryAuthorizationSuspendedChange
) async throws -> Bool {
  let fixture = try await DeliveryAuthorizationFixture.make()
  defer { fixture.remove() }
  try await fixture.enableOwnerControl()
  let gate = DeliveryAuthorizationWorkspaceGate(workspace: fixture.workspace)
  let task = Task {
    await fixture.authorizationService().observeEligibility(
      for: fixture.attempt,
      workspaceProvider: { await gate.next() }
    )
  }
  await gate.waitUntilEntered()

  switch change {
  case .ownerABA:
    let current = try #require(
      try await fixture.subscriptionStore.currentSubscription(
        id: fixture.subscriptionID
      )?.deliveryControl
    )
    let off = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: fixture.binding,
        expectedGenerationID: current.generationID,
        eligible: false
      )
    )
    let onAgain = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: fixture.binding,
        expectedGenerationID: off.generationID,
        eligible: true
      )
    )
    #expect(onAgain.generationID != current.generationID)
  case .proofReplacement:
    _ = try await fixture.replaceProof()
  case .grantRevocation:
    try await fixture.disableObservationPermission()
  case .profileRevocation:
    try fixture.revokeProfile()
  case .reservationCancellation:
    let generation = try #require(
      try fixture.ledgerStore.currentBindingGeneration(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    _ = try fixture.ledgerStore.cancel(fixture.attempt.reservation, expectedGeneration: generation)
  case .leaseExpiry:
    fixture.clock.set(DeliveryAuthorizationFixture.baseDate.addingTimeInterval(31))
  }

  await gate.release()
  return await task.value == nil
}

private struct DeliveryAuthorizationFixture {
  static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

  let ownedRoot: OwnedMCPFixtureRoot
  let rootURL: URL
  let profileURL: URL
  let profileID: UUID
  let noteID: UUID
  let folderID: UUID
  let subscriptionID: String
  let subscriptionURL: URL
  let eventID: String
  let workspace: Workspace
  let binding: AgentEventCallbackVerificationBinding
  let attempt: AgentEventDeliveryAttempt
  let clock: DeliveryAuthorizationClock
  let capabilities: AgentCapabilityStore
  let authority: AgentCapabilityAuthority
  let profileStore: AgentProfileStore
  let profile: AgentIntegrationProfile
  let secretProbe: DeliveryAuthorizationSecretProbe
  let subscriptionStore: AgentEventSubscriptionStore
  let verificationStore: AgentEventCallbackVerificationStore
  let outboxStore: AgentEventOutboxStore
  let ledgerStore: AgentEventDeliveryLedgerStore
  let ledgerService: AgentEventDeliveryLedgerService

  static func make(
    includeProof: Bool = true,
    liveReservation: Bool = true,
    scope: DeliveryAuthorizationScope = .note,
    grantFolder: Bool = true,
    subscriptionUpdatedAt: Date? = nil,
    subscriptionExpiresAt: Date? = nil,
    eventTimestamp: Date? = nil,
    proofVerifiedAt: Date? = nil
  ) async throws -> DeliveryAuthorizationFixture {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .deliveryAuthorization)
    let rootURL = ownedRoot.url
    var rootOwnershipTransferred = false
    defer {
      if !rootOwnershipTransferred {
        do {
          try ownedRoot.cleanup()
        } catch {
          Issue.record("Owned MCP fixture cleanup failed: \(error)")
        }
      }
    }
    let baseDate = Self.baseDate
    let profileID = UUID()
    let noteID = UUID()
    let folderID = UUID()
    let folder = try Folder(id: folderID, name: "Authorized")
    let eventScope: AgentEventScope
    let workspace: Workspace
    switch scope {
    case .note:
      eventScope = .note(noteID: noteID)
      workspace = Workspace(notes: [Note(id: noteID)])
    case .folder:
      eventScope = .folder(folderID: folderID)
      workspace = Workspace(notes: [Note(id: noteID, folderID: folderID)], folders: [folder])
    }
    let callbackURL = "https://delivery-auth.invalid/events"
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteUpdated,
      scope: eventScope,
      callbackURL: callbackURL
    )
    let keyReference = UUID().uuidString.lowercased()
    let updatedAt = subscriptionUpdatedAt ?? proofVerifiedAt ?? baseDate
    let expiresAt = subscriptionExpiresAt ?? updatedAt.addingTimeInterval(86_400)
    let profileURL = rootURL.appendingPathComponent("profiles.json")
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Synthetic profile",
      createdAt: updatedAt,
      lastConnectedAt: nil,
      revokedAt: nil
    )
    try JSONEncoder().encode([profile]).write(to: profileURL, options: .atomic)
    let secretProbe = DeliveryAuthorizationSecretProbe()
    let profileStore = AgentProfileStore(profilesURL: profileURL, secretStore: secretProbe)

    let capabilityDirectory = rootURL.appendingPathComponent("capabilities", isDirectory: true)
    let capabilities = AgentCapabilityStore(
      capabilitiesURL: capabilityDirectory.appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: capabilityDirectory.appendingPathComponent(
        "capabilities.previous.json"
      )
    )
    var capabilityState = try await capabilities.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    if capabilityState.profiles[profileID] == nil {
      capabilityState = try await capabilities.registerEmptyProfile(profileID)
    }
    let oldProfile = try #require(capabilityState.profiles[profileID])
    let grants: [AgentResourceGrant]
    switch scope {
    case .note:
      grants = [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)]
    case .folder:
      if grantFolder {
        grants = [
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folderID),
            authority: .read
          )
        ]
      } else {
        grants = [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)]
      }
    }
    let capabilityProfile = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: oldProfile.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: grants,
      allowsEventObservation: true
    )
    _ = try await capabilities.replaceProfile(
      capabilityProfile,
      expectedGrantRevision: oldProfile.grantRevision
    )
    let authority = AgentCapabilityAuthority(store: capabilities)

    let subscriptionURL = rootURL.appendingPathComponent("event-subscriptions.json")
    let subscriptionStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    try await subscriptionStore.reserveSigningKeyReference(keyReference)
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: .noteUpdated,
        scope: eventScope,
        callbackURL: callbackURL,
        signingKeyReference: keyReference,
        grantRevision: capabilityProfile.grantRevision,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        expiresAt: expiresAt,
        revision: 1
      ),
      now: updatedAt
    )
    let binding = AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: subscriptionID,
      subscriptionRevision: 1,
      grantRevision: capabilityProfile.grantRevision,
      signingKeyReference: keyReference
    )

    let clock = DeliveryAuthorizationClock(date: proofVerifiedAt ?? baseDate)
    let verificationStore = AgentEventCallbackVerificationStore(
      fileURL: rootURL.appendingPathComponent("event-callback-verification.json"),
      now: { clock.now() }
    )
    if includeProof {
      let proofDate = proofVerifiedAt ?? baseDate
      let intent = AgentEventCallbackVerificationIntent(
        id: UUID(),
        binding: binding,
        nonceDigest: Data(repeating: 0x2a, count: 32),
        createdAt: proofDate,
        expiresAt: min(proofDate.addingTimeInterval(60), expiresAt)
      )
      try verificationStore.begin(intent)
      _ = try verificationStore.complete(intent, subscriptionExpiresAt: expiresAt)
    }
    clock.set(baseDate)

    let eventID = UUID().uuidString.lowercased()
    let position = AgentEventOutboxPosition(epoch: UUID(), sequence: 1)
    let timestamp = eventTimestamp ?? baseDate
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let envelope = try AgentEventEnvelope(
      eventID: eventID,
      name: .noteUpdated,
      timestamp: formatter.string(from: timestamp),
      data: .noteUpdated(
        noteID: noteID,
        revision: 1,
        changedFields: [.body],
        origin: .local
      ),
      cursor: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let body = try encoder.encode(envelope)
    let outboxURL = rootURL.appendingPathComponent("event-outbox.json")
    let outboxStore = AgentEventOutboxStore(fileURL: outboxURL)
    try outboxStore.update { state in
      state.progress = [
        AgentEventOutboxProgress(
          profileID: profileID,
          subscriptionID: subscriptionID,
          subscriptionRevision: 1,
          grantRevision: capabilityProfile.grantRevision,
          anchor: AgentEventOutboxPosition(epoch: position.epoch, sequence: 0),
          capturedThrough: position,
          status: .pending,
          nonDeliveryDisposition: nil
        )
      ]
      state.entries = [
        AgentEventOutboxEntry(
          profileID: profileID,
          subscriptionID: subscriptionID,
          eventID: eventID,
          sourcePosition: position,
          body: body,
          status: .awaitingVerification,
          nonDeliveryDisposition: nil
        )
      ]
    }
    let ledgerURL = rootURL.appendingPathComponent("event-delivery-ledger.json")
    let ledgerStore = AgentEventDeliveryLedgerStore(
      fileURL: ledgerURL,
      now: { clock.now() },
      jitterBasisPoints: { 0 }
    )
    let ledgerService = AgentEventDeliveryLedgerService(
      outboxStore: outboxStore,
      subscriptionStore: subscriptionStore,
      ledgerStore: ledgerStore
    )
    let attempt: AgentEventDeliveryAttempt
    if liveReservation,
      let reservation = try await ledgerService.reserveNext(
        profileID: profileID,
        subscriptionID: subscriptionID
      )
    {
      attempt = try await ledgerService.observe(reservation)
    } else {
      attempt = AgentEventDeliveryAttempt(
        reservation: AgentEventDeliveryLedgerReservation(
          id: UUID(),
          binding: binding,
          bindingGenerationID: UUID().uuidString.lowercased(),
          eventID: eventID,
          sourcePosition: position,
          expiresAt: min(
            timestamp.addingTimeInterval(AgentEventDeliveryLedgerStore.maximumRetention),
            expiresAt
          ),
          attemptCount: 1,
          leaseDeadline: baseDate.addingTimeInterval(30)
        ),
        body: body
      )
    }
    let fixture = DeliveryAuthorizationFixture(
      ownedRoot: ownedRoot,
      rootURL: rootURL,
      profileURL: profileURL,
      profileID: profileID,
      noteID: noteID,
      folderID: folderID,
      subscriptionID: subscriptionID,
      subscriptionURL: subscriptionURL,
      eventID: eventID,
      workspace: workspace,
      binding: binding,
      attempt: attempt,
      clock: clock,
      capabilities: capabilities,
      authority: authority,
      profileStore: profileStore,
      profile: profile,
      secretProbe: secretProbe,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      ledgerService: ledgerService
    )
    rootOwnershipTransferred = true
    return fixture
  }

  func authorizationService(
    now: (@Sendable () -> Date)? = nil
  ) -> AgentEventDeliveryAuthorizationService {
    AgentEventDeliveryAuthorizationService(
      authority: authority,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      now: now ?? { clock.now() }
    )
  }

  func enableOwnerControl() async throws {
    let current = try #require(
      try await subscriptionStore.currentSubscription(id: subscriptionID)?.deliveryControl)
    _ = try await subscriptionStore.setOwnerDeliveryEligibility(
      binding: binding,
      expectedGenerationID: current.generationID,
      eligible: true
    )
  }

  func disableObservationPermission() async throws {
    let state = try await capabilities.currentState()
    let current = try #require(state.profiles[profileID])
    let replacement = AgentProfileCapabilities(
      profileID: current.profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: current.allowedCapabilities,
      grants: current.grants,
      allowsEventObservation: false
    )
    _ = try await capabilities.replaceProfile(
      replacement,
      expectedGrantRevision: current.grantRevision
    )
  }

  func revokeProfile() throws {
    let revoked = AgentIntegrationProfile(
      id: profile.id,
      displayName: profile.displayName,
      createdAt: profile.createdAt,
      lastConnectedAt: profile.lastConnectedAt,
      revokedAt: clock.now()
    )
    try JSONEncoder().encode([revoked]).write(to: profileURL, options: .atomic)
  }

  func replaceProof() async throws -> AgentEventCallbackVerificationProof {
    let now = clock.now()
    let expiresAt = try #require(
      try await subscriptionStore.currentSubscription(id: subscriptionID)?.expiresAt)
    let intent = AgentEventCallbackVerificationIntent(
      id: UUID(),
      binding: binding,
      nonceDigest: Data(repeating: 0x6b, count: 32),
      createdAt: now,
      expiresAt: min(now.addingTimeInterval(60), expiresAt)
    )
    try verificationStore.begin(intent)
    return try verificationStore.complete(intent, subscriptionExpiresAt: expiresAt)
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Owned MCP fixture cleanup failed: \(error)")
    }
  }
}

private final class DeliveryAuthorizationNowInvocationCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func next() -> Int {
    lock.withLock {
      count += 1
      return count
    }
  }
}

private func disableOwnerControlSynchronously(at subscriptionURL: URL) -> Bool {
  guard
    var document = try? JSONSerialization.jsonObject(with: Data(contentsOf: subscriptionURL))
      as? [String: Any],
    var subscriptions = document["subscriptions"] as? [[String: Any]],
    var subscription = subscriptions.first,
    var control = subscription["deliveryControl"] as? [String: Any]
  else {
    return false
  }
  control["generationID"] = UUID().uuidString.lowercased()
  control["enabled"] = false
  subscription["deliveryControl"] = control
  subscriptions[0] = subscription
  document["subscriptions"] = subscriptions
  guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
  else {
    return false
  }
  do {
    try data.write(to: subscriptionURL, options: .atomic)
    return true
  } catch {
    return false
  }
}

private enum DeliveryAuthorizationScope {
  case note
  case folder
}

private final class DeliveryAuthorizationClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(date: Date) {
    self.date = date
  }

  func now() -> Date {
    lock.withLock { date }
  }

  func set(_ date: Date) {
    lock.withLock { self.date = date }
  }
}

private final class DeliveryAuthorizationSecretProbe: AgentSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  private var writes = 0
  private var deletes = 0

  var operationCounts: (Int, Int, Int) {
    lock.withLock { (reads, writes, deletes) }
  }

  func read(service: String, account: String) throws -> Data? {
    lock.withLock { reads += 1 }
    return nil
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock { writes += 1 }
  }

  func delete(service: String, account: String) throws {
    lock.withLock { deletes += 1 }
  }
}

private actor DeliveryAuthorizationWorkspaceGate {
  private let workspace: Workspace
  private var shouldPause = true
  private var hasEntered = false
  private var releaseRequested = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(workspace: Workspace) {
    self.workspace = workspace
  }

  func next() async -> Workspace {
    guard shouldPause else { return workspace }
    shouldPause = false
    hasEntered = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      if releaseRequested {
        continuation.resume()
      } else {
        releaseContinuation = continuation
      }
    }
    return workspace
  }

  func waitUntilEntered() async {
    guard !hasEntered else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      enteredWaiters.append(continuation)
    }
  }

  func release() {
    releaseRequested = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}
