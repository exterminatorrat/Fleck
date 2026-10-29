import FleckCore
import Foundation
import FleckMCPFixtureSupport
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentEventSubscriptionTests {
  @Test func pendingLookupRejectsInvalidOrRolledBackClockWithoutChangingStorage() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = UUID()
    let noteID = UUID()
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/clock-watermark",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      requestedTTLSeconds: 60,
      workspace: workspace,
      now: now
    )
    let trustedNow = receipt.expiresAt.addingTimeInterval(1)
    #expect(try await fixture.pendingStore.observeTrustedClock(now: trustedNow) == false)
    let persisted = try Data(contentsOf: fixture.subscriptionURL)
    for invalidNow in [
      now,
      Date(timeIntervalSince1970: -1),
      Date(timeIntervalSince1970: .infinity),
      Date(timeIntervalSince1970: .nan),
    ] {
      await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
        _ = try await fixture.pendingStore.pendingSubscriptions(now: invalidNow)
      }
      #expect(try Data(contentsOf: fixture.subscriptionURL) == persisted)
    }
    #expect(try await fixture.pendingStore.pendingSubscriptions(now: trustedNow).isEmpty)
    #expect(try await fixture.pendingStore.allSubscriptions().count == 1)
  }

  @Test func legacyAndNewProfilesDefaultObservationOffAndOmitFalseOnDisk() async throws {
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000101")
    let legacyProfile = Data(
      #"{"profileID":"00000000-0000-4000-8000-000000000101","grantRevision":0,"allowedCapabilities":[],"grants":[]}"#
        .utf8
    )
    let decoded = try JSONDecoder().decode(AgentProfileCapabilities.self, from: legacyProfile)
    #expect(!decoded.allowsEventObservation)

    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let migrated = try await fixture.capabilities.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    #expect(migrated.profiles[profileID]?.allowsEventObservation == false)
    let firstDocument = try fixture.readCapabilityDocument()
    let firstProfile = try fixture.profileDocument(firstDocument)
    #expect(firstProfile["allowsEventObservation"] == nil)

    let newProfileID = eventTestUUID("00000000-0000-4000-8000-000000000102")
    let created = try await fixture.capabilities.registerEmptyProfile(newProfileID)
    #expect(created.profiles[newProfileID]?.allowsEventObservation == false)
    let newProfileDocument = try fixture.profileDocument(
      try fixture.readCapabilityDocument(), id: newProfileID)
    #expect(newProfileDocument["allowsEventObservation"] == nil)

    var profile = try fixture.profileDocument(try fixture.readCapabilityDocument(), id: profileID)
    profile.removeValue(forKey: "allowsEventObservation")
    try fixture.writeProfile(profile, id: profileID)
    let reloaded = AgentCapabilityStore(
      capabilitiesURL: fixture.capabilitiesURL,
      previousCapabilitiesURL: fixture.previousCapabilitiesURL
    )
    #expect(try await reloaded.currentState().profiles[profileID]?.allowsEventObservation == false)
  }

  @Test func profileCopiesPreserveObservationOptIn() throws {
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000111")
    let baseline = AgentProfileCapabilities(
      profileID: eventTestUUID("00000000-0000-4000-8000-000000000112"),
      grantRevision: 3,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)
      ],
      allowsEventObservation: true
    )

    let capabilityCopy = AgentCapabilityPresentation.capabilityReplacement(
      baseline: baseline,
      allowedCapabilities: [],
      expectedGrantRevision: baseline.grantRevision,
      directAccess: [:],
      folderAccess: [:]
    )
    let noteCopy = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: noteID,
      level: .write,
      baseline: baseline
    )

    #expect(capabilityCopy.allowsEventObservation)
    #expect(noteCopy.allowsEventObservation)
  }

  @Test func legacyNoteAssignmentPreservesObservationOptIn() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000113")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000114")
    let workspace = Workspace(notes: [Note(id: noteID, agentAccess: true)])
    let migrated = try await fixture.capabilities.loadOrMigrate(
      activeProfileIDs: [],
      workspace: workspace
    )
    #expect(migrated.unassignedLegacyNoteIDs == [noteID])
    let empty = try await fixture.capabilities.registerEmptyProfile(profileID)
    let current = try #require(empty.profiles[profileID])
    let optedIn = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [],
      allowsEventObservation: true
    )
    _ = try await fixture.capabilities.replaceProfile(
      optedIn,
      expectedGrantRevision: current.grantRevision
    )

    let assigned = try await fixture.capabilities.assignUnassignedLegacyNotes(
      [noteID],
      to: profileID,
      expectedGrantRevision: optedIn.grantRevision
    )
    #expect(assigned.profiles[profileID]?.allowsEventObservation == true)
    #expect(assigned.unassignedLegacyNoteIDs.isEmpty)
  }

  @Test func malformedPersistedObservationFlagFailsClosed() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000115")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000116")
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: Workspace(notes: [Note(id: noteID)]),
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: false
    )
    var profile = try fixture.profileDocument(try fixture.readCapabilityDocument())
    profile["allowsEventObservation"] = NSNull()
    try fixture.writeProfile(profile, id: profileID)
    try FileManager.default.removeItem(at: fixture.previousCapabilitiesURL)

    let reloaded = AgentCapabilityStore(
      capabilitiesURL: fixture.capabilitiesURL,
      previousCapabilitiesURL: fixture.previousCapabilitiesURL
    )
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await reloaded.currentState()
    }
  }

  @Test func authorityRequiresSeparateObservationReadAndExplicitScopeGrants() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000121")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000122")
    let folderID = eventTestUUID("00000000-0000-4000-8000-000000000123")
    let note = Note(id: noteID, folderID: folderID)
    let folder = try Folder(id: folderID, name: "Projects")
    let workspace = Workspace(notes: [note], folders: [folder])
    let authority = AgentCapabilityAuthority(store: fixture.capabilities)

    let profile = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: false
    )
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .note(noteID: noteID),
        workspace: workspace
      )
    }

    let optedInWithoutRead = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: profile.grantRevision + 1,
      allowedCapabilities: [],
      grants: profile.grants,
      allowsEventObservation: true
    )
    _ = try await fixture.capabilities.replaceProfile(
      optedInWithoutRead,
      expectedGrantRevision: profile.grantRevision
    )
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .note(noteID: noteID),
        workspace: workspace
      )
    }

    let optedIn = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: optedInWithoutRead.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      allowsEventObservation: true
    )
    _ = try await fixture.capabilities.replaceProfile(
      optedIn,
      expectedGrantRevision: optedInWithoutRead.grantRevision
    )
    #expect(
      try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .note(noteID: noteID),
        workspace: workspace
      ) == optedIn.grantRevision
    )

    authority.exclude(noteID: noteID)
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .note(noteID: noteID),
        workspace: workspace
      )
    }
    authority.include(noteID: noteID)

    let futureFolderOnly = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: optedIn.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folderID),
          authority: .read
        )
      ],
      allowsEventObservation: true
    )
    _ = try await fixture.capabilities.replaceProfile(
      futureFolderOnly,
      expectedGrantRevision: optedIn.grantRevision
    )
    #expect(
      try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .folder(folderID: folderID),
        workspace: workspace
      ) == futureFolderOnly.grantRevision
    )
    authority.exclude(noteID: noteID)
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .folder(folderID: folderID),
        workspace: workspace
      )
    }
    authority.include(noteID: noteID)
  }

  @Test func subscriptionRechecksTheCurrentWorkspaceAfterPersistence() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000197")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000198")
    let folderID = eventTestUUID("00000000-0000-4000-8000-000000000199")
    let folder = try Folder(id: folderID, name: "Granted")
    let workspace = Workspace(
      notes: [Note(id: noteID, folderID: folderID)],
      folders: [folder]
    )
    var movedWorkspace = workspace
    try movedWorkspace.moveNote(id: noteID, toFolderID: nil)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folderID),
          authority: .read
        )
      ],
      observation: true
    )
    let callbackURL = "https://example.com/current-workspace"
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: callbackURL
    )
    let sequence = EventWorkspaceSequence(
      [workspace, workspace, movedWorkspace],
      store: fixture.pendingStore,
      subscriptionID: subscriptionID
    )
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: fixture.pendingStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )

    await #expect(throws: AgentWorkspaceError.self) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingSecret: eventSecret(byte: 0x21, count: 24),
        workspaceProvider: { await sequence.next() },
        now: Date(timeIntervalSince1970: 1_790_755_200)
      )
    }

    #expect(await sequence.snapshotCount() == 3)
    #expect(await sequence.mutationAtPostPersistenceSnapshot()?.revision == 1)
    #expect(try await fixture.pendingStore.pendingSubscriptions(now: Date()).isEmpty)
    #expect(try await fixture.pendingStore.pendingSigningKeyDeletions().isEmpty)
    #expect(fixture.secrets.values().isEmpty)
  }

  @Test func staleRefreshRollsBackThePersistedMutationAndPreservesThePriorKey() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000202")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000203")
    let folderID = eventTestUUID("00000000-0000-4000-8000-000000000204")
    let folder = try Folder(id: folderID, name: "Granted")
    let workspace = Workspace(
      notes: [Note(id: noteID, folderID: folderID)],
      folders: [folder]
    )
    var movedWorkspace = workspace
    try movedWorkspace.moveNote(id: noteID, toFolderID: nil)
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folderID),
          authority: .read
        )
      ],
      observation: true
    )
    let callbackURL = "https://example.com/stale-refresh"
    let original = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: callbackURL,
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )
    let subscriptionID = original.subscriptionID
    let originalRow = try #require(
      await fixture.pendingStore.currentSubscription(id: subscriptionID))
    let originalKey = try #require(fixture.secrets.value(account: originalRow.signingKeyReference))
    let sequence = EventWorkspaceSequence(
      [workspace, workspace, movedWorkspace],
      store: fixture.pendingStore,
      subscriptionID: subscriptionID
    )

    await #expect(throws: AgentWorkspaceError.self) {
      _ = try await fixture.service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingSecret: eventSecret(byte: 0x42, count: 24),
        workspaceProvider: { await sequence.next() },
        now: now.addingTimeInterval(30)
      )
    }

    #expect(await sequence.snapshotCount() == 3)
    let persistedMutation = await sequence.mutationAtPostPersistenceSnapshot()
    #expect(persistedMutation?.revision == original.revision + 1)
    #expect(persistedMutation?.signingKeyReference != originalRow.signingKeyReference)
    let rolledBackRow = try #require(
      await fixture.pendingStore.currentSubscription(id: subscriptionID))
    #expect(
      rolledBackRow.replacingDeliveryControl(nil) == originalRow.replacingDeliveryControl(nil))
    #expect(rolledBackRow.deliveryControl?.enabled == false)
    #expect(
      rolledBackRow.deliveryControl?.generationID != originalRow.deliveryControl?.generationID)
    #expect(fixture.secrets.value(account: originalRow.signingKeyReference) == originalKey)
    #expect(fixture.secrets.accounts() == [originalRow.signingKeyReference])
    #expect(try await fixture.pendingStore.pendingSigningKeyDeletions().isEmpty)
  }

  @Test func pendingCreateIsDeterministicDurableAndRefreshRotatesTheKey() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000131")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000132")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let profile = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let service = fixture.service
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    let firstSecret = eventSecret(byte: 0x21, count: 24)
    let first = try await service.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "HTTPS://Example.COM:443/hook?tenant=a%2Fb",
      signingSecret: firstSecret,
      workspace: workspace,
      now: now
    )

    #expect(first.status == .pending)
    #expect(first.expiresAt == now.addingTimeInterval(86_400))
    #expect(first.grantRevision == profile.grantRevision)
    let firstRows = try await fixture.pendingStore.pendingSubscriptions(
      profileID: profileID,
      now: now
    )
    #expect(firstRows.count == 1)
    let oldKeyReference = try #require(firstRows.first?.signingKeyReference)
    #expect(firstRows.first?.callbackURL == "https://example.com/hook?tenant=a%2Fb")

    let secondSecret = eventSecret(byte: 0x42, count: 64)
    let refreshed = try await service.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/hook?tenant=a%2Fb",
      signingSecret: secondSecret,
      requestedTTLSeconds: 3_600,
      workspace: workspace,
      now: now.addingTimeInterval(30)
    )
    #expect(refreshed.subscriptionID == first.subscriptionID)
    #expect(refreshed.revision == first.revision + 1)
    #expect(refreshed.expiresAt == now.addingTimeInterval(3_630))
    let overlapBeforeRollback = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)?.previousSigningKey
    )
    #expect(overlapBeforeRollback.reference == oldKeyReference)
    #expect(overlapBeforeRollback.startedAt == now.addingTimeInterval(30))
    #expect(overlapBeforeRollback.expiresAt == now.addingTimeInterval(90))
    #expect(fixture.secrets.value(account: oldKeyReference) != nil)
    #expect(fixture.secrets.values().count == 2)
    await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/hook?tenant=a%2Fb",
        signingSecret: eventSecret(byte: 0x63, count: 24),
        requestedTTLSeconds: 3_600,
        workspace: workspace,
        now: now.addingTimeInterval(20)
      )
    }

    let refreshedRows = try await AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)
      .pendingSubscriptions(profileID: profileID, now: now.addingTimeInterval(30))
    #expect(refreshedRows.count == 1)
    let newKeyReference = try #require(refreshedRows.first?.signingKeyReference)
    #expect(newKeyReference != oldKeyReference)
    #expect(refreshedRows.first?.previousSigningKey == nil)
    #expect(fixture.secrets.value(account: oldKeyReference) == nil)
    #expect(
      fixture.secrets.value(account: newKeyReference)
        == Data(base64Encoded: eventSecretPayload(byte: 0x42, count: 64)))
    #expect(fixture.secrets.values().count == 1)

    let bytes = try Data(contentsOf: fixture.subscriptionURL)
    let json = String(decoding: bytes, as: UTF8.self)
    #expect(bytes.count <= 1_048_576)
    let directoryAttributes = try FileManager.default.attributesOfItem(
      atPath: fixture.subscriptionURL.deletingLastPathComponent().path
    )
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect(!json.contains(firstSecret))
    #expect(!json.contains(secondSecret))
    #expect(!json.contains(eventSecretPayload(byte: 0x42, count: 64)))
    #expect(json.contains(newKeyReference))
    #expect(json.contains("pending"))

    let afterRestart = try await AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)
      .pendingSubscriptions(profileID: profileID, now: now.addingTimeInterval(30))
    #expect(afterRestart == refreshedRows)
  }

  @Test func sameSecretRefreshReusesCurrentKeyAndCreatesFreshOffControl() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000321")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000322")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let secret = eventSecret(byte: 0x41, count: 32)
    let first = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/same-secret",
      signingSecret: secret,
      workspace: workspace,
      now: now
    )
    let initial = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    let enabled = try #require(
      try await fixture.pendingStore.setOwnerDeliveryEligibility(
        binding: AgentEventCallbackVerificationBinding(
          profileID: initial.profileID,
          subscriptionID: initial.subscriptionID,
          subscriptionRevision: initial.revision,
          grantRevision: initial.grantRevision,
          signingKeyReference: initial.signingKeyReference
        ),
        expectedGenerationID: initial.deliveryControl?.generationID,
        eligible: true
      )
    )

    let refreshed = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/same-secret",
      signingSecret: secret,
      requestedTTLSeconds: 3_600,
      workspace: workspace,
      now: now.addingTimeInterval(10)
    )
    let row = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    let control = try #require(row.deliveryControl)

    #expect(refreshed.revision == first.revision + 1)
    #expect(row.signingKeyReference == initial.signingKeyReference)
    #expect(row.previousSigningKey == nil)
    #expect(row.updatedAt == now.addingTimeInterval(10))
    #expect(row.expiresAt == now.addingTimeInterval(3_610))
    #expect(!control.enabled)
    #expect(!control.allowsAutomaticRenewal)
    #expect(control.generationID != enabled.generationID)
    #expect(fixture.secrets.values().count == 1)
    #expect(try await fixture.pendingStore.pendingSigningKeyDeletions() == [])
  }

  @Test func rotationOverlapIsFixedAndFurtherSecretChangesWaitUntilDeadline() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000323")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000324")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let start = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let firstSecret = eventSecret(byte: 0x21, count: 32)
    let secondSecret = eventSecret(byte: 0x42, count: 32)
    let first = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/rotation-window",
      signingSecret: firstSecret,
      workspace: workspace,
      now: start
    )
    let original = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    let rotated = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/rotation-window",
      signingSecret: secondSecret,
      workspace: workspace,
      now: start.addingTimeInterval(30)
    )
    let firstOverlap = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)?.previousSigningKey
    )
    let rotatedRow = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )

    #expect(rotated.revision == first.revision + 1)
    #expect(rotatedRow.signingKeyReference != original.signingKeyReference)
    #expect(firstOverlap.reference == original.signingKeyReference)
    #expect(firstOverlap.startedAt == start.addingTimeInterval(30))
    #expect(firstOverlap.expiresAt == start.addingTimeInterval(90))
    #expect(fixture.secrets.value(account: original.signingKeyReference) != nil)

    await #expect(throws: AgentWorkspaceError.signingKeyRotationInProgress(retryAfterMs: 45_000)) {
      _ = try await fixture.service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/rotation-window",
        signingSecret: eventSecret(byte: 0x63, count: 32),
        requestedTTLSeconds: 3_600,
        workspace: workspace,
        now: start.addingTimeInterval(45)
      )
    }
    #expect(try await fixture.pendingStore.currentSubscription(id: first.subscriptionID) == rotatedRow)
    #expect(try await fixture.pendingStore.stagedSigningKeyReferences() == [])
    #expect(fixture.secrets.values().count == 2)

    let sameKeyRefresh = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/rotation-window",
      signingSecret: secondSecret,
      workspace: workspace,
      now: start.addingTimeInterval(60)
    )
    let refreshedRow = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    #expect(sameKeyRefresh.revision == rotated.revision + 1)
    #expect(refreshedRow.signingKeyReference == rotatedRow.signingKeyReference)
    #expect(refreshedRow.previousSigningKey == firstOverlap)

    let thirdSecret = eventSecret(byte: 0x64, count: 32)
    let nextRotation = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/rotation-window",
      signingSecret: thirdSecret,
      workspace: workspace,
      now: start.addingTimeInterval(90)
    )
    let nextRow = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    let nextOverlap = try #require(nextRow.previousSigningKey)
    #expect(nextRotation.revision == sameKeyRefresh.revision + 1)
    #expect(nextRow.signingKeyReference != rotatedRow.signingKeyReference)
    #expect(nextOverlap.reference == rotatedRow.signingKeyReference)
    #expect(nextOverlap.startedAt == start.addingTimeInterval(90))
    #expect(nextOverlap.expiresAt == start.addingTimeInterval(150))
    #expect(fixture.secrets.value(account: original.signingKeyReference) == nil)
    #expect(fixture.secrets.values().count == 2)
  }

  @Test func refreshExpiryAndRotationOverlapStartAtLockedAcceptanceTime() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000327")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000328")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let start = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let first = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/acceptance-clock",
      signingSecret: eventSecret(byte: 0x21, count: 32),
      workspace: workspace,
      now: start
    )

    let preparedAt = start.addingTimeInterval(30)
    let preflightAt = start.addingTimeInterval(31)
    let acceptedAt = start.addingTimeInterval(45)
    let clock = EventSubscriptionAcceptanceClock([preparedAt, preflightAt, acceptedAt])
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: fixture.pendingStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets),
      clock: { clock.now() }
    )
    let refreshed = try await service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/acceptance-clock",
      signingSecret: eventSecret(byte: 0x42, count: 32),
      requestedTTLSeconds: 3_600,
      workspaceProvider: { workspace }
    )
    let row = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    let overlap = try #require(row.previousSigningKey)

    #expect(clock.sampleCount() == 3)
    #expect(refreshed.expiresAt == acceptedAt.addingTimeInterval(3_600))
    #expect(row.updatedAt == acceptedAt)
    #expect(row.expiresAt == acceptedAt.addingTimeInterval(3_600))
    #expect(overlap.startedAt == acceptedAt)
    #expect(overlap.expiresAt == acceptedAt.addingTimeInterval(60))
  }

  @Test func trustedClockRollbackRetiresOverlapBeforeRejectingRefresh() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000325")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000326")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let start = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let first = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/clock-rollback",
      signingSecret: eventSecret(byte: 0x21, count: 32),
      workspace: workspace,
      now: start
    )
    let initial = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    let rotated = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/clock-rollback",
      signingSecret: eventSecret(byte: 0x42, count: 32),
      workspace: workspace,
      now: start.addingTimeInterval(30)
    )
    let beforeRollback = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    #expect(rotated.revision == beforeRollback.revision)

    await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try await fixture.service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/clock-rollback",
        signingSecret: eventSecret(byte: 0x63, count: 32),
        workspace: workspace,
        now: start.addingTimeInterval(20)
      )
    }

    let afterRollback = try #require(
      try await fixture.pendingStore.currentSubscription(id: first.subscriptionID)
    )
    #expect(afterRollback.signingKeyReference == beforeRollback.signingKeyReference)
    #expect(afterRollback.previousSigningKey == nil)
    #expect(afterRollback.revision == beforeRollback.revision)
    #expect(afterRollback.expiresAt == beforeRollback.expiresAt)
    #expect(afterRollback.deliveryControl == beforeRollback.deliveryControl)
    #expect(fixture.secrets.value(account: initial.signingKeyReference) == nil)
    #expect(fixture.secrets.value(account: beforeRollback.signingKeyReference) != nil)
  }

  @Test func callbackCanonicalizationPreservesURLSemanticsAndBoundsTTL() throws {
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000181")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000182")
    let normalized = try AgentEventSubscriptionIdentity.canonicalCallbackURL(
      "HTTPS://Example.COM:443/hook?tenant=a%2Fb"
    )
    #expect(normalized == "https://example.com/hook?tenant=a%2Fb")
    let identity = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: normalized
    )
    #expect(
      identity
        == AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: try AgentEventSubscriptionIdentity.canonicalCallbackURL(
            "https://example.com/hook?tenant=a%2Fb"
          )
        )
    )
    #expect(
      try AgentEventSubscriptionIdentity.canonicalCallbackURL("https://example.com/a%2Fb")
        != AgentEventSubscriptionIdentity.canonicalCallbackURL("https://example.com/a/b")
    )
    #expect(
      identity
        != AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: "https://example.com/hook?tenant=a%2Fb&other=1"
        )
    )
    #expect(
      identity
        != AgentEventSubscriptionIdentity.subscriptionID(
          profileID: eventTestUUID("00000000-0000-4000-8000-000000000185"),
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: normalized
        )
    )
    #expect(
      identity
        != AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteUpdated,
          scope: .note(noteID: noteID),
          callbackURL: normalized
        )
    )
    #expect(
      identity
        != AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteCreated,
          scope: .folder(folderID: noteID),
          callbackURL: normalized
        )
    )
    #expect(try AgentEventSubscriptionIdentity.grantedTTL(nil) == 86_400)
    #expect(try AgentEventSubscriptionIdentity.grantedTTL(60) == 60)
    #expect(try AgentEventSubscriptionIdentity.grantedTTL(.infinity) == 604_800)
    #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try AgentEventSubscriptionIdentity.grantedTTL(59)
    }
    #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try AgentEventSubscriptionIdentity.grantedTTL(604_801)
    }
    for callbackURL in [
      "http://example.com/hook",
      "https://user@example.com/hook",
      "https://example.com/hook#fragment",
      "https://example.com/" + String(repeating: "x", count: 2_048),
    ] {
      #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
        _ = try AgentEventSubscriptionIdentity.canonicalCallbackURL(callbackURL)
      }
    }
  }

  @Test func concurrentRefreshesKeepOnePendingIdentityAndSigningKey() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000183")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000184")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )

    var unexpectedErrors: [String] = []
    let service = fixture.service
    let sharedSecret = eventSecret(byte: 0x42, count: 24)
    await withTaskGroup(of: String?.self) { group in
      for _ in UInt8(1)...UInt8(8) {
        group.addTask {
          do {
            _ = try await service.createPending(
              profileID: profileID,
              event: .noteUpdated,
              scope: .note(noteID: noteID),
              callbackURL: "https://example.com/shared-hook",
              signingSecret: sharedSecret,
              workspace: workspace,
              now: now
            )
            return nil
          } catch let error as AgentWorkspaceError where error.code == .capabilityDenied {
            return nil
          } catch {
            return String(describing: error)
          }
        }
      }
      for await error in group {
        if let error { unexpectedErrors.append(error) }
      }
    }

    #expect(unexpectedErrors.isEmpty)
    let rows = try await fixture.pendingStore.pendingSubscriptions(profileID: profileID, now: now)
    #expect(rows.count == 1)
    let keyReference = try #require(rows.first?.signingKeyReference)
    #expect(rows.first?.previousSigningKey == nil)
    #expect(fixture.secrets.value(account: keyReference) != nil)
    #expect(fixture.secrets.values().count == 1)
    #expect(try await fixture.pendingStore.stagedSigningKeyReferences().isEmpty)
    #expect(try await fixture.pendingStore.pendingSigningKeyCleanupReferences().isEmpty)
  }

  @Test func concurrentRemovalAndRefreshLeaveNoDanglingKeyOrRow() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000185")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000186")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let original = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/removal-race",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )

    var unexpectedErrors: [String] = []
    let service = fixture.service
    await withTaskGroup(of: String?.self) { group in
      group.addTask {
        do {
          _ = try await service.createPending(
            profileID: profileID,
            event: .noteUpdated,
            scope: .note(noteID: noteID),
            callbackURL: "https://example.com/removal-race",
            signingSecret: eventSecret(byte: 0x42, count: 24),
            workspace: workspace,
            now: now.addingTimeInterval(30)
          )
          return nil
        } catch let error as AgentWorkspaceError where error.code == .capabilityDenied {
          return nil
        } catch {
          return String(describing: error)
        }
      }
      group.addTask {
        do {
          try await service.remove(
            profileID: profileID,
            subscriptionID: original.subscriptionID
          )
          return nil
        } catch {
          return String(describing: error)
        }
      }
      for await error in group {
        if let error { unexpectedErrors.append(error) }
      }
    }

    #expect(unexpectedErrors.isEmpty)
    let rows = try await fixture.pendingStore.pendingSubscriptions(
      profileID: profileID, now: now.addingTimeInterval(30))
    if let row = rows.first {
      #expect(rows.count == 1)
      #expect(fixture.secrets.values().count == 1)
      #expect(fixture.secrets.value(account: row.signingKeyReference) != nil)
    } else {
      #expect(fixture.secrets.values().isEmpty)
    }
  }

  @Test func invalidCallbackTTLAndSecretFailBeforePersistingKey() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000141")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000142")
    let workspace = Workspace(notes: [Note(id: noteID)])
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let service = fixture.service
    let validSecret = eventSecret(byte: 0x21, count: 24)

    await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "http://example.com/callback",
        signingSecret: validSecret,
        workspace: workspace
      )
    }
    for invalidURL in [
      "https://example.com/%ZZ",
      "https://example.com/private note",
      "https://example.com/private\ncallback",
    ] {
      await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
        _ = try await service.createPending(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: invalidURL,
          signingSecret: validSecret,
          workspace: workspace
        )
      }
    }
    for invalidLength in [23, 65] {
      await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
        _ = try await service.createPending(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: "https://example.com/callback",
          signingSecret: eventSecret(byte: 0x42, count: invalidLength),
          workspace: workspace
        )
      }
    }
    await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/callback",
        signingSecret: "whsec_not-base64",
        workspace: workspace
      )
    }
    await #expect(throws: AgentEventSubscriptionError.invalidConfiguration) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/callback",
        signingSecret: validSecret,
        requestedTTLSeconds: 30,
        workspace: workspace
      )
    }
    #expect(fixture.secrets.values().isEmpty)
    #expect(try await fixture.pendingStore.pendingSubscriptions(now: Date()).isEmpty)
  }

  @Test func expiredEntriesAreNotReturnedAndGrantRevocationBlocksRefresh() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000151")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000152")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let profile = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    let first = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/callback",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )
    let expired = try await fixture.pendingStore.pendingSubscriptions(
      profileID: profileID,
      now: first.expiresAt.addingTimeInterval(1)
    )
    #expect(expired.isEmpty)

    let revoked = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: profile.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: profile.grants,
      allowsEventObservation: false
    )
    _ = try await fixture.capabilities.replaceProfile(
      revoked,
      expectedGrantRevision: profile.grantRevision
    )
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await fixture.service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/callback",
        signingSecret: eventSecret(byte: 0x42, count: 24),
        workspace: workspace,
        now: now.addingTimeInterval(86_401)
      )
    }
    #expect(
      try await fixture.pendingStore.pendingSubscriptions(now: now).first?.subscriptionID
        == first.subscriptionID)
    #expect(fixture.secrets.values().count == 1)
  }

  @Test func grantRevocationDuringSecretStagingDeniesRefreshAndDeletesTheStagedKey() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000153")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000154")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let profile = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    let original = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/revocable",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )
    let originalRow = try #require(
      try await fixture.pendingStore.currentSubscription(id: original.subscriptionID)
    )

    let stagedSecrets = EventBlockingSecretStore(backingStore: fixture.secrets)
    let stagingService = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: fixture.pendingStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: stagedSecrets)
    )
    let refresh = Task {
      try await stagingService.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/revocable",
        signingSecret: eventSecret(byte: 0x42, count: 24),
        workspace: workspace,
        now: now.addingTimeInterval(30)
      )
    }
    let keyWasStaged = await Task.detached {
      stagedSecrets.waitForWrite()
    }.value
    #expect(keyWasStaged)
    _ = try await fixture.capabilities.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: profile.grantRevision + 1,
        allowedCapabilities: [.readNotes],
        grants: profile.grants,
        allowsEventObservation: false
      ),
      expectedGrantRevision: profile.grantRevision
    )
    stagedSecrets.continueWrite()

    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await refresh.value
    }
    let rows = try await fixture.pendingStore.pendingSubscriptions(
      profileID: profileID, now: now.addingTimeInterval(30))
    #expect(rows.count == 1)
    #expect(rows.first?.subscriptionID == original.subscriptionID)
    #expect(rows.first?.revision == original.revision)
    #expect(stagedSecrets.accounts() == [originalRow.signingKeyReference])
    #expect(fixture.secrets.values().count == 1)
  }

  @Test func removalIsOwnerBoundIdempotentAndDoesNotRevealOtherProfileRecords() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let ownerID = eventTestUUID("00000000-0000-4000-8000-000000000161")
    let otherID = eventTestUUID("00000000-0000-4000-8000-000000000162")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000163")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let grants = [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)]
    _ = try await fixture.createProfile(
      profileID: ownerID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: grants,
      observation: true
    )
    _ = try await fixture.createProfile(
      profileID: otherID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: grants,
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: ownerID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/callback",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace
    )

    try await fixture.service.remove(
      profileID: otherID,
      subscriptionID: receipt.subscriptionID
    )
    #expect(
      try await fixture.pendingStore.pendingSubscriptions(profileID: ownerID, now: Date())
        .first?.subscriptionID == receipt.subscriptionID
    )
    #expect(fixture.secrets.values().count == 1)
    try await fixture.service.remove(profileID: ownerID, subscriptionID: receipt.subscriptionID)
    try await fixture.service.remove(profileID: ownerID, subscriptionID: receipt.subscriptionID)
    #expect(
      try await fixture.pendingStore.pendingSubscriptions(profileID: ownerID, now: Date()).isEmpty)
    #expect(fixture.secrets.values().isEmpty)
  }

  @Test func failedSigningKeyDeletionIsDurableAndRetriedBeforeCreate() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000200")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000201")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let original = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/deferred-key-cleanup",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )
    let originalRows = try await fixture.pendingStore.pendingSubscriptions(
      profileID: profileID,
      now: now
    )
    let originalKey = try #require(originalRows.first?.signingKeyReference)
    fixture.secrets.failNextDelete()

    try await fixture.service.remove(
      profileID: profileID,
      subscriptionID: original.subscriptionID
    )

    #expect(
      try await fixture.pendingStore.pendingSubscriptions(profileID: profileID, now: now).isEmpty)
    #expect(try await fixture.pendingStore.pendingSigningKeyDeletions() == [originalKey])
    #expect(fixture.secrets.value(account: originalKey) != nil)
    _ = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/deferred-key-cleanup",
      signingSecret: eventSecret(byte: 0x42, count: 24),
      workspace: workspace,
      now: now.addingTimeInterval(30)
    )

    #expect(try await fixture.pendingStore.pendingSigningKeyDeletions().isEmpty)
    #expect(fixture.secrets.values().count == 1)
  }

  @Test func corruptStoreFailsClosedBeforeSigningKeyCreation() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000171")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000172")
    let workspace = Workspace(notes: [Note(id: noteID)])
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    try FileManager.default.createDirectory(
      at: fixture.subscriptionURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    for corrupted in [
      Data("not-json".utf8),
      Data(#"{"schemaVersion":1,"subscriptions":[],"unexpected":true}"#.utf8),
      Data(#"{"schemaVersion":2,"subscriptions":[]}"#.utf8),
    ] {
      try corrupted.write(to: fixture.subscriptionURL, options: .atomic)
      await #expect(throws: AgentEventSubscriptionError.storageFailure) {
        _ = try await fixture.service.createPending(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: "https://example.com/callback",
          signingSecret: eventSecret(byte: 0x21, count: 24),
          workspace: workspace
        )
      }
      #expect(fixture.secrets.values().isEmpty)
      #expect(try Data(contentsOf: fixture.subscriptionURL) == corrupted)
    }

    let oversized = Data(repeating: 0x61, count: 1_048_577)
    try oversized.write(to: fixture.subscriptionURL, options: .atomic)
    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await fixture.pendingStore.pendingSubscriptions(now: Date())
    }
    #expect(fixture.secrets.values().isEmpty)
    #expect(try Data(contentsOf: fixture.subscriptionURL) == oversized)
  }

  @Test func legacyStoreSchemasUpgradeWithoutLosingRetirementReferences() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentEventStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pendingKey = UUID().uuidString.lowercased()
    let stagedKey = UUID().uuidString.lowercased()
    let cases: [(Data, [String])] = [
      (Data(#"{"schemaVersion":1,"subscriptions":[]}"#.utf8), []),
      (
        try JSONSerialization.data(
          withJSONObject: [
            "schemaVersion": 2,
            "subscriptions": [],
            "pendingSigningKeyDeletions": [pendingKey],
          ],
          options: [.sortedKeys]
        ),
        [pendingKey]
      ),
      (
        try JSONSerialization.data(
          withJSONObject: [
            "schemaVersion": 3,
            "subscriptions": [],
            "pendingSigningKeyDeletions": [pendingKey],
            "stagedSigningKeyReferences": [],
          ],
          options: [.sortedKeys]
        ),
        [pendingKey]
      ),
      (
        try JSONSerialization.data(
          withJSONObject: [
            "schemaVersion": 4,
            "subscriptions": [],
            "pendingSigningKeyDeletions": [pendingKey],
            "stagedSigningKeyReferences": [],
          ],
          options: [.sortedKeys]
        ),
        [pendingKey]
      ),
    ]

    for (index, item) in cases.enumerated() {
      let fileURL = directory.appendingPathComponent("store-\(index).json")
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try item.0.write(to: fileURL, options: .atomic)
      let store = AgentEventSubscriptionStore(fileURL: fileURL)
      #expect(try await store.pendingSigningKeyDeletions() == item.1)
      try await store.reserveSigningKeyReference(stagedKey)

      let upgraded = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
      )
      #expect(upgraded["schemaVersion"] as? Int == 5)
      #expect(upgraded["pendingSigningKeyDeletions"] as? [String] == item.1)
      #expect(upgraded["stagedSigningKeyReferences"] as? [String] == [stagedKey])
    }
  }

  @Test func persistedSubscriptionRowsRejectUnknownKeys() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000202")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000203")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    _ = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/unknown-row-key",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )
    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.subscriptionURL))
        as? [String: Any]
    )
    var subscriptions = try #require(document["subscriptions"] as? [[String: Any]])
    subscriptions[0]["unexpected"] = "ignored metadata"
    document["subscriptions"] = subscriptions
    let corrupted = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    try corrupted.write(to: fixture.subscriptionURL, options: .atomic)

    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await fixture.pendingStore.pendingSubscriptions(now: now)
    }
    #expect(try Data(contentsOf: fixture.subscriptionURL) == corrupted)
    #expect(fixture.secrets.values().count == 1)
  }

  @Test func schemaFiveRejectsNullAndUnknownPreviousSigningKeyFields() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000327")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000328")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/strict-overlap-schema",
      signingSecret: eventSecret(byte: 0x41, count: 32),
      workspace: workspace,
      now: now
    )
    let original = try Data(contentsOf: fixture.subscriptionURL)
    let invalidFields: [[String: Any]] = [
      ["previousSigningKey": NSNull()],
      [
        "previousSigningKey": [
          "reference": UUID().uuidString.lowercased(),
          "startedAt": now.timeIntervalSinceReferenceDate,
          "expiresAt": now.addingTimeInterval(60).timeIntervalSinceReferenceDate,
          "unexpected": true,
        ]
      ],
      [
        "previousSigningKey": [
          "reference": UUID().uuidString.lowercased(),
          "startedAt": now.addingTimeInterval(61).timeIntervalSinceReferenceDate,
          "expiresAt": now.addingTimeInterval(90).timeIntervalSinceReferenceDate,
        ]
      ],
    ]

    for fields in invalidFields {
      var document = try #require(
        JSONSerialization.jsonObject(with: original) as? [String: Any]
      )
      var subscriptions = try #require(document["subscriptions"] as? [[String: Any]])
      subscriptions[0].merge(fields) { _, new in new }
      document["subscriptions"] = subscriptions
      let corrupted = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
      try corrupted.write(to: fixture.subscriptionURL, options: .atomic)

      await #expect(throws: AgentEventSubscriptionError.storageFailure) {
        _ = try await fixture.pendingStore.currentSubscription(id: receipt.subscriptionID)
      }
      #expect(try Data(contentsOf: fixture.subscriptionURL) == corrupted)
    }
    #expect(fixture.secrets.values().count == 1)
  }

  @Test func unwritableStagingIntentPreventsAnySigningKeyWrite() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000173")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000174")
    let workspace = Workspace(notes: [Note(id: noteID)])
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let secrets = EventSecretStore()
    secrets.failNextDelete()
    let unavailableStore = AgentEventSubscriptionStore(
      fileURL: URL(fileURLWithPath: "/dev/null/event-subscriptions.json")
    )
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: unavailableStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: secrets)
    )

    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/callback",
        signingSecret: eventSecret(byte: 0x21, count: 24),
        workspace: workspace
      )
    }
    #expect(secrets.writeCount() == 0)
    #expect(secrets.values().isEmpty)
  }

  @Test func partiallyWrittenSigningKeyRemainsTrackedAndIsCleanedAfterStoreReopen() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000205")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000206")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    fixture.secrets.failNextWriteAfterPersisting()
    fixture.secrets.failNextDelete()

    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await fixture.service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/partial-key-write",
        signingSecret: eventSecret(byte: 0x21, count: 24),
        workspace: workspace,
        now: now
      )
    }

    let partialReferences = fixture.secrets.accounts()
    #expect(partialReferences.count == 1)
    let stagedDocument =
      try? JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.subscriptionURL)
      ) as? [String: Any]
    #expect(stagedDocument?["stagedSigningKeyReferences"] as? [String] == partialReferences)
    #expect(try await fixture.pendingStore.pendingSubscriptions(now: now).isEmpty)

    let reopenedStore = AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)
    let reopenedService = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: reopenedStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )
    _ = try await reopenedService.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/partial-key-recovered",
      signingSecret: eventSecret(byte: 0x42, count: 24),
      workspace: workspace,
      now: now.addingTimeInterval(30)
    )

    #expect(fixture.secrets.value(account: partialReferences[0]) == nil)
    #expect(fixture.secrets.accounts().count == 1)
    #expect(try await reopenedStore.pendingSigningKeyDeletions().isEmpty)
  }

  @Test func promotionWriteFailureKeepsStagingIntentForRestartRecovery() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000207")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000208")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let writer = EventSubscriptionFileWriter(
      failBeforeWritePredicates: [
        { data, url in EventSubscriptionFileWriter.isPromotionWrite(data, at: url) }
      ]
    )
    let store = AgentEventSubscriptionStore(
      fileURL: fixture.subscriptionURL,
      fileWriter: { data, url in try writer.write(data, to: url) }
    )
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: store,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )
    fixture.secrets.failNextDelete()
    fixture.secrets.failNextDelete()

    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/promotion-failure",
        signingSecret: eventSecret(byte: 0x21, count: 24),
        workspace: workspace,
        now: now
      )
    }

    let stagedReferences = try await store.stagedSigningKeyReferences()
    let stagedReference = try #require(stagedReferences.first)
    #expect(stagedReferences == fixture.secrets.accounts())
    #expect(try await store.pendingSubscriptions(now: now).isEmpty)
    let stagedDocumentBytes = try Data(contentsOf: fixture.subscriptionURL)
    #expect(stagedDocumentBytes.count <= 1_048_576)
    print("event-subscription promotion-attempt document bytes: \(writer.serializedByteCounts())")

    let reopenedStore = AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)
    let reopenedService = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: reopenedStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )
    _ = try await reopenedService.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/promotion-recovered",
      signingSecret: eventSecret(byte: 0x42, count: 24),
      workspace: workspace,
      now: now.addingTimeInterval(30)
    )

    #expect(fixture.secrets.value(account: stagedReference) == nil)
    #expect(fixture.secrets.accounts().count == 1)
    #expect(try await reopenedStore.pendingSigningKeyCleanupReferences().isEmpty)
  }

  @Test func failedStagingAcknowledgementRemainsRecoverableAfterReopen() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000214")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000215")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let writer = EventSubscriptionFileWriter(
      failBeforeWritePredicates: [
        { data, url in EventSubscriptionFileWriter.isPromotionWrite(data, at: url) },
        { data, url in EventSubscriptionFileWriter.isStagingAcknowledgementWrite(data, at: url) },
        { data, url in EventSubscriptionFileWriter.isStagingAcknowledgementWrite(data, at: url) },
      ]
    )
    let store = AgentEventSubscriptionStore(
      fileURL: fixture.subscriptionURL,
      fileWriter: { data, url in try writer.write(data, to: url) }
    )
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: store,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )

    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await service.createPending(
        profileID: profileID,
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/acknowledgement-failure",
        signingSecret: eventSecret(byte: 0x21, count: 24),
        workspace: workspace,
        now: now
      )
    }

    let stagedReference = try #require(try await store.stagedSigningKeyReferences().first)
    #expect(fixture.secrets.value(account: stagedReference) == nil)
    #expect(try await store.pendingSigningKeyCleanupReferences() == [stagedReference])

    let reopenedStore = AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)
    let reopenedService = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: reopenedStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )
    _ = try await reopenedService.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/acknowledgement-recovered",
      signingSecret: eventSecret(byte: 0x42, count: 24),
      workspace: workspace,
      now: now.addingTimeInterval(30)
    )

    #expect(try await reopenedStore.pendingSigningKeyCleanupReferences().isEmpty)
    #expect(fixture.secrets.accounts().count == 1)
  }

  @Test func promotionWriteThatReportsFailureAfterCommitKeepsTheReferencedKey() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000209")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000210")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let writer = EventSubscriptionFileWriter(
      failAfterWritePredicates: [
        { data, url in EventSubscriptionFileWriter.isPromotionWrite(data, at: url) }
      ]
    )
    let store = AgentEventSubscriptionStore(
      fileURL: fixture.subscriptionURL,
      fileWriter: { data, url in try writer.write(data, to: url) }
    )
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: store,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: fixture.secrets)
    )

    let receipt = try await service.createPending(
      profileID: profileID,
      event: .noteCreated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/promotion-reported-failure",
      signingSecret: eventSecret(byte: 0x21, count: 24),
      workspace: workspace,
      now: now
    )
    let row = try #require(await store.currentSubscription(id: receipt.subscriptionID))

    #expect(row.signingKeyReference == fixture.secrets.accounts().first)
    #expect(fixture.secrets.value(account: row.signingKeyReference) != nil)
    #expect(try await store.stagedSigningKeyReferences().isEmpty)
    #expect(try await store.pendingSigningKeyCleanupReferences().isEmpty)
  }

  @Test func staleRefreshRollbackPreservesPriorRowAndKeyBeforeQueuedRefresh() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000211")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000212")
    let folderID = eventTestUUID("00000000-0000-4000-8000-000000000213")
    let folder = try Folder(id: folderID, name: "Granted")
    let workspace = Workspace(
      notes: [Note(id: noteID, folderID: folderID)],
      folders: [folder]
    )
    var movedWorkspace = workspace
    try movedWorkspace.moveNote(id: noteID, toFolderID: nil)
    let now = Date(timeIntervalSince1970: 1_790_755_200)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folderID),
          authority: .read
        )
      ],
      observation: true
    )
    let callbackURL = "https://example.com/queued-rollback"
    let keyStore = EventBlockingSecretStore()
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: fixture.pendingStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: keyStore)
    )
    let initialCreate = Task {
      try await service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingSecret: eventSecret(byte: 0x21, count: 24),
        workspace: workspace,
        now: now
      )
    }
    #expect(await keyStore.waitForWriteAsync())
    keyStore.continueWrite()
    let original = try await initialCreate.value
    let originalRow = try #require(
      await fixture.pendingStore.currentSubscription(id: original.subscriptionID))
    let originalKey = try #require(keyStore.value(account: originalRow.signingKeyReference))
    let staleSequence = EventWorkspaceSequence(
      [workspace, workspace, movedWorkspace],
      store: fixture.pendingStore,
      subscriptionID: original.subscriptionID
    )
    let staleRefresh = Task {
      try await service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingSecret: eventSecret(byte: 0x42, count: 24),
        workspaceProvider: { await staleSequence.next() },
        now: now.addingTimeInterval(30)
      )
    }
    #expect(await keyStore.waitForWriteAsync())
    let queuedBarrier = EventWorkspaceBarrier(workspace: workspace)
    let queuedRefresh = Task {
      try await service.createPending(
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingSecret: eventSecret(byte: 0x63, count: 24),
        workspaceProvider: { await queuedBarrier.next() },
        now: now.addingTimeInterval(60)
      )
    }
    await AgentEventSubscriptionService.waitForQueuedLifecycleOperation()
    keyStore.continueWrite()
    await #expect(throws: AgentWorkspaceError.self) {
      _ = try await staleRefresh.value
    }

    await queuedBarrier.waitUntilEntered()
    let rolledBackRow = try #require(
      await fixture.pendingStore.currentSubscription(id: original.subscriptionID))
    #expect(
      rolledBackRow.replacingDeliveryControl(nil) == originalRow.replacingDeliveryControl(nil))
    #expect(rolledBackRow.deliveryControl?.enabled == false)
    #expect(
      rolledBackRow.deliveryControl?.generationID != originalRow.deliveryControl?.generationID)
    #expect(keyStore.value(account: originalRow.signingKeyReference) == originalKey)
    await queuedBarrier.release()
    #expect(await keyStore.waitForWriteAsync())
    #expect(
      try await fixture.pendingStore.currentSubscription(id: original.subscriptionID)
        == rolledBackRow)
    #expect(keyStore.value(account: originalRow.signingKeyReference) == originalKey)
    keyStore.continueWrite()
    _ = try await queuedRefresh.value

    let finalRow = try #require(
      await fixture.pendingStore.currentSubscription(id: original.subscriptionID))
    #expect(finalRow.revision == originalRow.revision + 1)
    #expect(finalRow.signingKeyReference != originalRow.signingKeyReference)
    let finalOverlap = try #require(finalRow.previousSigningKey)
    #expect(finalOverlap.reference == originalRow.signingKeyReference)
    #expect(finalOverlap.startedAt == now.addingTimeInterval(60))
    #expect(finalOverlap.expiresAt == now.addingTimeInterval(120))
    #expect(keyStore.value(account: originalRow.signingKeyReference) == originalKey)
    #expect(keyStore.value(account: finalRow.signingKeyReference) != nil)
    #expect(keyStore.values().count == 2)
    try await service.maintainSigningKeyLifecycle(now: finalOverlap.expiresAt)
    #expect(
      try await fixture.pendingStore.currentSubscription(id: original.subscriptionID)?
        .previousSigningKey == nil)
    #expect(keyStore.value(account: originalRow.signingKeyReference) == nil)
    #expect(keyStore.value(account: finalRow.signingKeyReference) != nil)
    #expect(keyStore.values().count == 1)
  }

  @Test func pendingCapacityIsBoundedPerProfileAndAcrossTheStore() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileIDs = [
      eventTestUUID("00000000-0000-4000-8000-000000000191"),
      eventTestUUID("00000000-0000-4000-8000-000000000192"),
      eventTestUUID("00000000-0000-4000-8000-000000000193"),
      eventTestUUID("00000000-0000-4000-8000-000000000194"),
      eventTestUUID("00000000-0000-4000-8000-000000000195"),
    ]
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000196")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_790_755_200)

    for profileID in profileIDs.prefix(4) {
      _ = try await fixture.createProfile(
        profileID: profileID,
        workspace: workspace,
        allowed: [.readNotes],
        grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
        observation: true
      )
    }

    for (profileIndex, profileID) in profileIDs.prefix(4).enumerated() {
      for subscriptionIndex in 0..<32 {
        _ = try await fixture.service.createPending(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: noteID),
          callbackURL: "https://example.com/\(profileIndex)/\(subscriptionIndex)",
          signingSecret: eventSecret(byte: 0x21, count: 24),
          workspace: workspace,
          now: now
        )
      }
    }

    await #expect(throws: AgentEventSubscriptionError.capacityExceeded) {
      _ = try await fixture.service.createPending(
        profileID: profileIDs[0],
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/per-profile-overflow",
        signingSecret: eventSecret(byte: 0x42, count: 24),
        workspace: workspace,
        now: now
      )
    }
    _ = try await fixture.createProfile(
      profileID: profileIDs[4],
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    await #expect(throws: AgentEventSubscriptionError.capacityExceeded) {
      _ = try await fixture.service.createPending(
        profileID: profileIDs[4],
        event: .noteCreated,
        scope: .note(noteID: noteID),
        callbackURL: "https://example.com/total-overflow",
        signingSecret: eventSecret(byte: 0x42, count: 24),
        workspace: workspace,
        now: now
      )
    }

    #expect(try await fixture.pendingStore.pendingSubscriptions(now: now).count == 128)
    #expect(fixture.secrets.values().count == 128)
    #expect(try Data(contentsOf: fixture.subscriptionURL).count <= 1_048_576)
  }

  @Test func newSubscriptionsPersistDefaultOffControlBoundToFullBinding() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000301")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000302")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/default-off",
      signingSecret: eventSecret(byte: 0x41, count: 24),
      workspace: workspace,
      now: now
    )

    let row = try #require(
      try await fixture.pendingStore.currentSubscription(id: receipt.subscriptionID))
    let control = try #require(row.deliveryControl)
    let expectedBinding = AgentEventCallbackVerificationBinding(
      profileID: row.profileID,
      subscriptionID: row.subscriptionID,
      subscriptionRevision: row.revision,
      grantRevision: row.grantRevision,
      signingKeyReference: row.signingKeyReference
    )
    #expect(control.enabled == false)
    #expect(control.binding == expectedBinding)

    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.subscriptionURL))
        as? [String: Any]
    )
    let subscriptions = try #require(document["subscriptions"] as? [[String: Any]])
    let storedControl = try #require(subscriptions.first?["deliveryControl"] as? [String: Any])
    #expect(storedControl["enabled"] as? Bool == false)
    #expect(
      storedControl["generationID"] as? String == control.generationID.uuidString.lowercased()
    )
    #expect(document["schemaVersion"] as? Int == 5)

    let reopened = AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)
    #expect(
      try await reopened.currentSubscription(
        id: receipt.subscriptionID
      )?.deliveryControl == control
    )
  }

  @Test func legacySchemasDecodeOwnerControlOffAndOwnerWritesUseNilOnlyOnce()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentEventOwnerControlLegacy-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000303")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000304")
    let callbackURL = "https://example.com/legacy-owner-control"
    let scope = AgentEventScope.note(noteID: noteID)
    let subscription = AgentEventPendingSubscription(
      subscriptionID: AgentEventSubscriptionIdentity.subscriptionID(
        profileID: profileID,
        event: .noteUpdated,
        scope: scope,
        callbackURL: callbackURL
      ),
      profileID: profileID,
      event: .noteUpdated,
      scope: scope,
      callbackURL: callbackURL,
      signingKeyReference: UUID().uuidString.lowercased(),
      grantRevision: 7,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.addingTimeInterval(3_600),
      revision: 5
    )
    let binding = AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: subscription.subscriptionID,
      subscriptionRevision: subscription.revision,
      grantRevision: subscription.grantRevision,
      signingKeyReference: subscription.signingKeyReference
    )

    for schemaVersion in 1...4 {
      let fileURL = directory.appendingPathComponent("schema-\(schemaVersion).json")
      try writeLegacyEventSubscription(subscription, schemaVersion: schemaVersion, to: fileURL)
      let store = AgentEventSubscriptionStore(fileURL: fileURL)
      let decoded = try #require(
        try await store.currentSubscription(id: subscription.subscriptionID))
      #expect(decoded.deliveryControl == nil)

      let firstOptIn = try #require(
        try await store.setOwnerDeliveryEligibility(
          binding: binding,
          expectedGenerationID: nil,
          eligible: true
        )
      )
      #expect(firstOptIn.enabled)
      #expect(firstOptIn.binding == binding)
      #expect(firstOptIn.generationID != UUID(uuidString: "00000000-0000-4000-8000-000000000000"))

      let upgraded = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
      #expect(upgraded["schemaVersion"] as? Int == 5)
      #expect(
        try await store.setOwnerDeliveryEligibility(
          binding: binding,
          expectedGenerationID: nil,
          eligible: false
        ) == nil
      )
    }
  }

  @Test func ownerControlCompareAndSwapRetainsFreshOffOnOffGenerations() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000305")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000306")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/owner-cas",
      signingSecret: eventSecret(byte: 0x42, count: 24),
      workspace: workspace,
      now: now
    )
    let initial = try #require(
      try await fixture.pendingStore.currentSubscription(
        id: receipt.subscriptionID
      )?.deliveryControl
    )
    let binding = initial.binding
    let storeA = fixture.pendingStore
    let storeB = AgentEventSubscriptionStore(fileURL: fixture.subscriptionURL)

    async let firstWrite = storeA.setOwnerDeliveryEligibility(
      binding: binding,
      expectedGenerationID: initial.generationID,
      eligible: true
    )
    async let secondWrite = storeB.setOwnerDeliveryEligibility(
      binding: binding,
      expectedGenerationID: initial.generationID,
      eligible: true
    )
    let (first, second) = try await (firstWrite, secondWrite)
    #expect((first == nil) != (second == nil))
    let on = try #require(first ?? second)
    #expect(on.enabled)

    let off = try #require(
      try await storeB.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: on.generationID,
        eligible: false
      )
    )
    #expect(!off.enabled)
    #expect(off.generationID != on.generationID)
    #expect(
      try await storeA.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: on.generationID,
        eligible: true
      ) == nil
    )
    #expect(
      try await storeA.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: nil,
        eligible: true
      ) == nil
    )

    let onAgain = try #require(
      try await storeA.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: off.generationID,
        eligible: true
      )
    )
    #expect(onAgain.enabled)
    #expect(onAgain.generationID != off.generationID)
  }

  @Test func ownerControlWritesRecognizeOnlyTheBytesActuallyCommitted() async throws {
    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000307")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000308")
    let workspace = Workspace(notes: [Note(id: noteID)])
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: workspace,
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: "https://example.com/owner-write-recognition",
      signingSecret: eventSecret(byte: 0x43, count: 24),
      workspace: workspace,
      now: now
    )
    let initial = try #require(
      try await fixture.pendingStore.currentSubscription(
        id: receipt.subscriptionID
      )?.deliveryControl
    )

    let beforeWrite = AgentEventSubscriptionStore(
      fileURL: fixture.subscriptionURL,
      fileWriter: { _, _ in throw AgentEventTestError.fileWriteFailure }
    )
    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await beforeWrite.setOwnerDeliveryEligibility(
        binding: initial.binding,
        expectedGenerationID: initial.generationID,
        eligible: true
      )
    }
    let afterFailedWrite = try #require(
      try await fixture.pendingStore.currentSubscription(id: receipt.subscriptionID)
    )
    #expect(afterFailedWrite.deliveryControl == initial)

    let afterWrite = AgentEventSubscriptionStore(
      fileURL: fixture.subscriptionURL,
      fileWriter: { data, url in
        try data.write(to: url, options: .atomic)
        throw AgentEventTestError.fileWriteFailure
      }
    )
    let committed = try #require(
      try await afterWrite.setOwnerDeliveryEligibility(
        binding: initial.binding,
        expectedGenerationID: initial.generationID,
        eligible: true
      )
    )
    #expect(committed.enabled)
    let afterCommittedWrite = try #require(
      try await fixture.pendingStore.currentSubscription(id: receipt.subscriptionID)
    )
    #expect(afterCommittedWrite.deliveryControl == committed)

    let silentWriter = AgentEventSubscriptionStore(
      fileURL: fixture.subscriptionURL,
      fileWriter: { _, _ in }
    )
    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await silentWriter.setOwnerDeliveryEligibility(
        binding: committed.binding,
        expectedGenerationID: committed.generationID,
        eligible: false
      )
    }
    let afterSilentWrite = try #require(
      try await fixture.pendingStore.currentSubscription(id: receipt.subscriptionID)
    )
    #expect(afterSilentWrite.deliveryControl == committed)
  }

  @Test func refreshRollbackInvalidatesALegacyNilOwnerGeneration() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentEventLegacyOwnerRollback-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000313")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000314")
    let callbackURL = "https://example.com/legacy-owner-rollback"
    let scope = AgentEventScope.note(noteID: noteID)
    let legacyRow = AgentEventPendingSubscription(
      subscriptionID: AgentEventSubscriptionIdentity.subscriptionID(
        profileID: profileID,
        event: .noteUpdated,
        scope: scope,
        callbackURL: callbackURL
      ),
      profileID: profileID,
      event: .noteUpdated,
      scope: scope,
      callbackURL: callbackURL,
      signingKeyReference: UUID().uuidString.lowercased(),
      grantRevision: 9,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.addingTimeInterval(3_600),
      revision: 4
    )
    let binding = AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: legacyRow.subscriptionID,
      subscriptionRevision: legacyRow.revision,
      grantRevision: legacyRow.grantRevision,
      signingKeyReference: legacyRow.signingKeyReference
    )
    let fileURL = directory.appendingPathComponent("event-subscriptions.json")
    try writeLegacyEventSubscription(legacyRow, schemaVersion: 3, to: fileURL)
    let store = AgentEventSubscriptionStore(fileURL: fileURL)
    #expect(
      try await store.currentSubscription(id: legacyRow.subscriptionID)?.deliveryControl == nil
    )

    let refreshedReference = UUID().uuidString.lowercased()
    try await store.reserveSigningKeyReference(refreshedReference)
    let mutation = try await store.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: legacyRow.subscriptionID,
        profileID: profileID,
        event: legacyRow.event,
        scope: scope,
        callbackURL: callbackURL,
        signingKeyReference: refreshedReference,
        grantRevision: legacyRow.grantRevision,
        createdAt: now,
        updatedAt: now.addingTimeInterval(1),
        expiresAt: now.addingTimeInterval(3_601),
        revision: legacyRow.revision
      ),
      now: now.addingTimeInterval(1)
    )
    let refreshedControl = try #require(mutation.stored.deliveryControl)
    #expect(mutation.previous?.deliveryControl == nil)
    #expect(try await store.rollback(mutation))

    let restored = try #require(
      try await store.currentSubscription(id: legacyRow.subscriptionID)
    )
    let restoredControl = try #require(restored.deliveryControl)
    #expect(restored.replacingDeliveryControl(nil) == legacyRow)
    #expect(!restoredControl.enabled)
    #expect(restoredControl.binding == binding)
    #expect(restoredControl.generationID != refreshedControl.generationID)
    #expect(
      try await store.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: nil,
        eligible: true
      ) == nil
    )
  }

  @Test func structuralRefreshRollbackAndRecreationInvalidateOwnerControlGenerations()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentEventOwnerControlRollback-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000309")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000310")
    let callbackURL = "https://example.com/owner-rollback"
    let scope = AgentEventScope.note(noteID: noteID)
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteUpdated,
      scope: scope,
      callbackURL: callbackURL
    )
    let oldReference = UUID().uuidString.lowercased()
    let legacyRow = AgentEventPendingSubscription(
      subscriptionID: subscriptionID,
      profileID: profileID,
      event: .noteUpdated,
      scope: scope,
      callbackURL: callbackURL,
      signingKeyReference: oldReference,
      grantRevision: 9,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.addingTimeInterval(3_600),
      revision: 4
    )
    let fileURL = directory.appendingPathComponent("event-subscriptions.json")
    try writeLegacyEventSubscription(legacyRow, schemaVersion: 3, to: fileURL)
    let store = AgentEventSubscriptionStore(fileURL: fileURL)
    let binding = AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: subscriptionID,
      subscriptionRevision: legacyRow.revision,
      grantRevision: legacyRow.grantRevision,
      signingKeyReference: oldReference
    )
    let ownerOn = try #require(
      try await store.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: nil,
        eligible: true
      )
    )

    let refreshedReference = UUID().uuidString.lowercased()
    try await store.reserveSigningKeyReference(refreshedReference)
    let refreshedMutation = try await store.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: .noteUpdated,
        scope: scope,
        callbackURL: callbackURL,
        signingKeyReference: refreshedReference,
        grantRevision: legacyRow.grantRevision,
        createdAt: now,
        updatedAt: now.addingTimeInterval(1),
        expiresAt: now.addingTimeInterval(3_601),
        revision: legacyRow.revision
      ),
      now: now.addingTimeInterval(1)
    )
    let refreshed = try #require(
      try await store.currentSubscription(id: subscriptionID)?.deliveryControl)
    #expect(!refreshed.enabled)
    #expect(refreshed.generationID != ownerOn.generationID)
    #expect(refreshed.binding.subscriptionRevision == legacyRow.revision + 1)

    #expect(try await store.rollback(refreshedMutation))
    let restored = try #require(try await store.currentSubscription(id: subscriptionID))
    let restoredControl = try #require(restored.deliveryControl)
    #expect(restored.revision == legacyRow.revision)
    #expect(restored.signingKeyReference == oldReference)
    #expect(!restoredControl.enabled)
    #expect(restoredControl.generationID != ownerOn.generationID)
    #expect(
      try await store.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: nil,
        eligible: true
      ) == nil
    )
    #expect(
      try await store.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: ownerOn.generationID,
        eligible: true
      ) == nil
    )

    let currentOn = try #require(
      try await store.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: restoredControl.generationID,
        eligible: true
      )
    )
    _ = try #require(try await store.remove(subscriptionID: subscriptionID, profileID: profileID))
    #expect(try await store.currentSubscription(id: subscriptionID) == nil)

    let recreatedReference = UUID().uuidString.lowercased()
    try await store.reserveSigningKeyReference(recreatedReference)
    _ = try await store.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: .noteUpdated,
        scope: scope,
        callbackURL: callbackURL,
        signingKeyReference: recreatedReference,
        grantRevision: legacyRow.grantRevision,
        createdAt: now.addingTimeInterval(2),
        updatedAt: now.addingTimeInterval(2),
        expiresAt: now.addingTimeInterval(3_602),
        revision: 1
      ),
      now: now.addingTimeInterval(2)
    )
    let recreated = try #require(
      try await store.currentSubscription(id: subscriptionID)?.deliveryControl)
    #expect(!recreated.enabled)
    #expect(recreated.generationID != currentOn.generationID)
    #expect(
      try await store.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: currentOn.generationID,
        eligible: true
      ) == nil
    )

    let recreatedOn = try #require(
      try await store.setOwnerDeliveryEligibility(
        binding: recreated.binding,
        expectedGenerationID: recreated.generationID,
        eligible: true
      )
    )
    #expect(try await store.pruneExpired(now: now.addingTimeInterval(3_602)).count == 1)
    #expect(try await store.currentSubscription(id: subscriptionID) == nil)
    #expect(
      try await store.setOwnerDeliveryEligibility(
        binding: recreatedOn.binding,
        expectedGenerationID: recreatedOn.generationID,
        eligible: true
      ) == nil
    )
  }

  @Test func unchangedPruneDoesNotRewriteTheTrustedWatermark() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentEventPruneNoop-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("subscriptions.json")
    let writer = EventSubscriptionFileWriter()
    let store = AgentEventSubscriptionStore(
      fileURL: fileURL,
      fileWriter: { data, url in try writer.write(data, to: url) }
    )
    let now = Date(timeIntervalSince1970: 1_790_755_200)

    #expect(try await store.observeTrustedClock(now: now) == false)
    let persistedWatermark = try Data(contentsOf: fileURL)
    let watermarkDocument = try #require(
      JSONSerialization.jsonObject(with: persistedWatermark) as? [String: Any]
    )
    #expect(watermarkDocument["lastObservedAt"] as? Double == now.timeIntervalSinceReferenceDate)
    #expect(try await store.pruneExpired(now: now).isEmpty)

    #expect(writer.serializedByteCounts().count == 1)
    #expect(try Data(contentsOf: fileURL) == persistedWatermark)
  }

  @Test func legacySchemaRejectsUnexpectedOwnerControlAndMalformedControlsFailClosed()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentEventOwnerControlMalformed-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_798_070_400)
    let profileID = eventTestUUID("00000000-0000-4000-8000-000000000311")
    let noteID = eventTestUUID("00000000-0000-4000-8000-000000000312")
    let callbackURL = "https://example.com/owner-malformed"
    let scope = AgentEventScope.note(noteID: noteID)
    let row = AgentEventPendingSubscription(
      subscriptionID: AgentEventSubscriptionIdentity.subscriptionID(
        profileID: profileID,
        event: .noteUpdated,
        scope: scope,
        callbackURL: callbackURL
      ),
      profileID: profileID,
      event: .noteUpdated,
      scope: scope,
      callbackURL: callbackURL,
      signingKeyReference: UUID().uuidString.lowercased(),
      grantRevision: 1,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.addingTimeInterval(3_600),
      revision: 1
    )
    let fileURL = directory.appendingPathComponent("event-subscriptions.json")
    try writeLegacyEventSubscription(row, schemaVersion: 3, to: fileURL)
    var legacyDocument = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
    var legacyRows = try #require(legacyDocument["subscriptions"] as? [[String: Any]])
    legacyRows[0]["deliveryControl"] = ["unexpected": true]
    legacyDocument["subscriptions"] = legacyRows
    let legacyBytes = try JSONSerialization.data(
      withJSONObject: legacyDocument,
      options: [.sortedKeys]
    )
    try legacyBytes.write(to: fileURL, options: .atomic)
    let legacyStore = AgentEventSubscriptionStore(fileURL: fileURL)
    await #expect(throws: AgentEventSubscriptionError.storageFailure) {
      _ = try await legacyStore.pendingSubscriptions(now: now)
    }
    #expect(try Data(contentsOf: fileURL) == legacyBytes)

    let fixture = try EventSubscriptionFixture()
    defer { fixture.remove() }
    _ = try await fixture.createProfile(
      profileID: profileID,
      workspace: Workspace(notes: [Note(id: noteID)]),
      allowed: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      observation: true
    )
    let receipt = try await fixture.service.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: scope,
      callbackURL: "https://example.com/owner-malformed-current",
      signingSecret: eventSecret(byte: 0x44, count: 24),
      workspace: Workspace(notes: [Note(id: noteID)]),
      now: now
    )
    let original = try Data(contentsOf: fixture.subscriptionURL)
    var document = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
    var rows = try #require(document["subscriptions"] as? [[String: Any]])
    let control = try #require(rows.first?["deliveryControl"] as? [String: Any])
    var oversizedBinding = try #require(control["binding"] as? [String: Any])
    oversizedBinding["subscriptionID"] = String(repeating: "x", count: 1_050_000)
    let oversizedControl: [String: Any] = [
      "generationID": control["generationID"]!,
      "binding": oversizedBinding,
      "enabled": false,
    ]
    let malformedControls: [Any] = [
      ["generationID": "not-a-uuid", "binding": control["binding"]!, "enabled": false],
      ["generationID": control["generationID"]!, "binding": control["binding"]!, "enabled": "yes"],
      [
        "generationID": control["generationID"]!, "binding": control["binding"]!, "enabled": false,
        "unexpected": true,
      ],
      NSNull(),
      oversizedControl,
    ]
    for malformed in malformedControls {
      rows[0]["deliveryControl"] = malformed
      document["subscriptions"] = rows
      let bytes = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
      try bytes.write(to: fixture.subscriptionURL, options: .atomic)
      await #expect(throws: AgentEventSubscriptionError.storageFailure) {
        _ = try await fixture.pendingStore.pendingSubscriptions(
          now: now
        )
      }
      #expect(try Data(contentsOf: fixture.subscriptionURL) == bytes)
      document = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
      rows = try #require(document["subscriptions"] as? [[String: Any]])
    }
    try original.write(to: fixture.subscriptionURL, options: .atomic)
    let restored = try #require(
      try await fixture.pendingStore.currentSubscription(id: receipt.subscriptionID))
    #expect(restored.deliveryControl?.enabled == false)
  }
}

private func writeLegacyEventSubscription(
  _ subscription: AgentEventPendingSubscription,
  schemaVersion: Int,
  to fileURL: URL
) throws {
  let row = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(subscription)) as? [String: Any])
  var document: [String: Any] = ["schemaVersion": schemaVersion, "subscriptions": [row]]
  if schemaVersion >= 2 { document["pendingSigningKeyDeletions"] = [] }
  if schemaVersion >= 3 { document["stagedSigningKeyReferences"] = [] }
  let bytes = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
  try FileManager.default.createDirectory(
    at: fileURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try bytes.write(to: fileURL, options: .atomic)
}

private final class EventSubscriptionAcceptanceClock: @unchecked Sendable {
  private let lock = NSLock()
  private var dates: [Date]
  private var lastDate: Date
  private var sampleCountValue = 0

  init(_ dates: [Date]) {
    precondition(!dates.isEmpty)
    self.dates = dates
    lastDate = dates[0]
  }

  func now() -> Date {
    lock.withLock {
      sampleCountValue += 1
      if !dates.isEmpty { lastDate = dates.removeFirst() }
      return lastDate
    }
  }

  func sampleCount() -> Int {
    lock.withLock { sampleCountValue }
  }
}

private struct EventSubscriptionFixture {
  let ownedRoot: OwnedMCPFixtureRoot
  let rootURL: URL
  let capabilitiesURL: URL
  let previousCapabilitiesURL: URL
  let subscriptionURL: URL
  let capabilities: AgentCapabilityStore
  let pendingStore: AgentEventSubscriptionStore
  let secrets = EventSecretStore()
  let authority: AgentCapabilityAuthority
  let service: AgentEventSubscriptionService

  init() throws {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventSubscription)
    self.ownedRoot = ownedRoot
    rootURL = ownedRoot.url
    let directory = rootURL.appendingPathComponent("AgentIntegrations", isDirectory: true)
    capabilitiesURL = directory.appendingPathComponent("capabilities.json")
    previousCapabilitiesURL = directory.appendingPathComponent("capabilities.previous.json")
    subscriptionURL = directory.appendingPathComponent("AgentEvents", isDirectory: true)
      .appendingPathComponent("event-subscriptions.json")
    capabilities = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
    pendingStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    authority = AgentCapabilityAuthority(store: capabilities)
    service = AgentEventSubscriptionService(
      authority: authority,
      store: pendingStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: secrets)
    )
  }

  func createProfile(
    profileID: UUID,
    workspace: Workspace,
    allowed: Set<AgentCapability>,
    grants: [AgentResourceGrant],
    observation: Bool
  ) async throws -> AgentProfileCapabilities {
    var state = try await capabilities.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    if state.profiles[profileID] == nil {
      state = try await capabilities.registerEmptyProfile(profileID)
    }
    let current = try #require(state.profiles[profileID])
    let profile = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: allowed,
      grants: grants,
      allowsEventObservation: observation
    )
    _ = try await capabilities.replaceProfile(
      profile,
      expectedGrantRevision: current.grantRevision
    )
    return profile
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Owned MCP fixture cleanup failed: \(error)")
    }
  }

  func readCapabilityDocument() throws -> [String: Any] {
    try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: capabilitiesURL)) as? [String: Any])
  }

  func profileDocument(_ document: [String: Any], id: UUID? = nil) throws -> [String: Any] {
    let profiles = try #require(document["profiles"] as? [[String: Any]])
    return try #require(
      profiles.first { profile in
        guard let profileID = profile["profileID"] as? String else { return false }
        return id.map { profileID.lowercased() == $0.uuidString.lowercased() } ?? true
      })
  }

  func writeProfile(_ profile: [String: Any], id: UUID) throws {
    var document = try readCapabilityDocument()
    var profiles = try #require(document["profiles"] as? [[String: Any]])
    guard
      let index = profiles.firstIndex(where: {
        ($0["profileID"] as? String)?.lowercased() == id.uuidString.lowercased()
      })
    else {
      throw AgentEventTestError.missingProfile
    }
    profiles[index] = profile
    document["profiles"] = profiles
    let bytes = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    try bytes.write(to: capabilitiesURL, options: .atomic)
  }
}

extension AgentEventSubscriptionService {
  fileprivate func createPending(
    profileID: UUID,
    event: AgentEventName,
    scope: AgentEventScope,
    callbackURL: String,
    signingSecret: String,
    requestedTTLSeconds: TimeInterval? = nil,
    workspace: Workspace,
    now: Date = Date()
  ) async throws -> AgentEventSubscriptionReceipt {
    try await createPending(
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: callbackURL,
      signingSecret: signingSecret,
      requestedTTLSeconds: requestedTTLSeconds,
      workspaceProvider: { workspace },
      now: now
    )
  }
}

private actor EventWorkspaceSequence {
  private var pendingWorkspaces: [Workspace]
  private let fallbackWorkspace: Workspace
  private let store: AgentEventSubscriptionStore
  private let subscriptionID: String
  private var snapshots = 0
  private var persistedMutation: AgentEventPendingSubscription?

  init(
    _ workspaces: [Workspace],
    store: AgentEventSubscriptionStore,
    subscriptionID: String
  ) {
    precondition(!workspaces.isEmpty)
    fallbackWorkspace = workspaces.last!
    pendingWorkspaces = workspaces
    self.store = store
    self.subscriptionID = subscriptionID
  }

  func next() async -> Workspace {
    snapshots += 1
    if snapshots == 3 {
      persistedMutation = try? await store.currentSubscription(id: subscriptionID)
    }
    return pendingWorkspaces.isEmpty ? fallbackWorkspace : pendingWorkspaces.removeFirst()
  }

  func snapshotCount() -> Int {
    snapshots
  }

  func mutationAtPostPersistenceSnapshot() -> AgentEventPendingSubscription? {
    persistedMutation
  }
}

private final class EventSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: Data] = [:]
  private var deleteFailuresRemaining = 0
  private var writeCountValue = 0
  private var shouldFailNextWriteAfterPersisting = false

  func value(account: String) -> Data? {
    lock.withLock { storage[account] }
  }

  func values() -> [Data] {
    lock.withLock { Array(storage.values) }
  }

  func accounts() -> [String] {
    lock.withLock { storage.keys.sorted() }
  }

  func writeCount() -> Int {
    lock.withLock { writeCountValue }
  }

  func failNextDelete() {
    lock.withLock { deleteFailuresRemaining += 1 }
  }

  func failNextWriteAfterPersisting() {
    lock.withLock { shouldFailNextWriteAfterPersisting = true }
  }

  func read(service: String, account: String) throws -> Data? {
    lock.withLock { storage[account] }
  }

  func write(_ data: Data, service: String, account: String) throws {
    let shouldFail = lock.withLock {
      writeCountValue += 1
      storage[account] = data
      guard shouldFailNextWriteAfterPersisting else { return false }
      shouldFailNextWriteAfterPersisting = false
      return true
    }
    if shouldFail { throw AgentEventTestError.writeFailure }
  }

  func delete(service: String, account: String) throws {
    let shouldFail = lock.withLock {
      guard deleteFailuresRemaining > 0 else { return false }
      deleteFailuresRemaining -= 1
      return true
    }
    guard !shouldFail else { throw AgentEventTestError.deleteFailure }
    lock.withLock { _ = storage.removeValue(forKey: account) }
  }
}

private final class EventBlockingSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let storage: EventSecretStore
  private let stagedWrite = DispatchSemaphore(value: 0)
  private let releaseWrite = DispatchSemaphore(value: 0)

  init(backingStore: EventSecretStore = EventSecretStore()) {
    storage = backingStore
  }

  func waitForWrite() -> Bool {
    stagedWrite.wait(timeout: .now() + 5) == .success
  }

  func waitForWriteAsync() async -> Bool {
    await Task.detached { self.waitForWrite() }.value
  }

  func continueWrite() {
    releaseWrite.signal()
  }

  func values() -> [Data] {
    storage.values()
  }

  func value(account: String) -> Data? {
    storage.value(account: account)
  }

  func accounts() -> [String] {
    storage.accounts()
  }

  func read(service: String, account: String) throws -> Data? {
    try storage.read(service: service, account: account)
  }

  func write(_ data: Data, service: String, account: String) throws {
    stagedWrite.signal()
    guard releaseWrite.wait(timeout: .now() + 5) == .success else {
      throw AgentEventTestError.writeTimeout
    }
    try storage.write(data, service: service, account: account)
  }

  func delete(service: String, account: String) throws {
    try storage.delete(service: service, account: account)
  }
}

private final class EventSubscriptionFileWriter: @unchecked Sendable {
  typealias FailurePredicate = @Sendable (Data, URL) -> Bool

  private let lock = NSLock()
  private let failBeforeWritePredicates: [FailurePredicate]
  private let failAfterWritePredicates: [FailurePredicate]
  private var byteCounts: [Int] = []
  private var failedBeforeWritePredicates: Set<Int> = []
  private var failedAfterWritePredicates: Set<Int> = []

  init(
    failBeforeWritePredicates: [FailurePredicate] = [],
    failAfterWritePredicates: [FailurePredicate] = []
  ) {
    self.failBeforeWritePredicates = failBeforeWritePredicates
    self.failAfterWritePredicates = failAfterWritePredicates
  }

  func write(_ data: Data, to url: URL) throws {
    let shouldFailBeforeWrite = lock.withLock {
      byteCounts.append(data.count)
      for index in failBeforeWritePredicates.indices
      where !failedBeforeWritePredicates.contains(index)
        && failBeforeWritePredicates[index](data, url)
      {
        failedBeforeWritePredicates.insert(index)
        return true
      }
      return false
    }
    if shouldFailBeforeWrite { throw AgentEventTestError.fileWriteFailure }
    try data.write(to: url, options: .atomic)
    let shouldFailAfterWrite = lock.withLock {
      for index in failAfterWritePredicates.indices
      where !failedAfterWritePredicates.contains(index)
        && failAfterWritePredicates[index](data, url)
      {
        failedAfterWritePredicates.insert(index)
        return true
      }
      return false
    }
    if shouldFailAfterWrite { throw AgentEventTestError.fileWriteFailure }
  }

  func serializedByteCounts() -> [Int] {
    lock.withLock { byteCounts }
  }

  static func isPromotionWrite(_ data: Data, at url: URL) -> Bool {
    guard let currentData = try? Data(contentsOf: url),
      let currentDocument = document(currentData),
      let currentStagedReferences = currentDocument["stagedSigningKeyReferences"] as? [String],
      let nextDocument = document(data),
      let nextSubscriptions = nextDocument["subscriptions"] as? [[String: Any]],
      let nextStagedReferences = nextDocument["stagedSigningKeyReferences"] as? [String]
    else {
      return false
    }
    guard let promotedReference = nextSubscriptions.compactMap({
      $0["signingKeyReference"] as? String
    }).first(where: { currentStagedReferences.contains($0) }) else {
      return false
    }
    return !nextStagedReferences.contains(promotedReference)
  }

  static func isStagingAcknowledgementWrite(_ data: Data, at url: URL) -> Bool {
    guard let currentData = try? Data(contentsOf: url),
      let currentDocument = document(currentData),
      let currentSubscriptions = currentDocument["subscriptions"] as? [[String: Any]],
      currentSubscriptions.isEmpty,
      let currentStagedReferences = currentDocument["stagedSigningKeyReferences"] as? [String],
      let currentPendingReferences = currentDocument["pendingSigningKeyDeletions"] as? [String],
      let nextDocument = document(data),
      let nextSubscriptions = nextDocument["subscriptions"] as? [[String: Any]],
      nextSubscriptions.isEmpty,
      let nextStagedReferences = nextDocument["stagedSigningKeyReferences"] as? [String],
      let nextPendingReferences = nextDocument["pendingSigningKeyDeletions"] as? [String]
    else {
      return false
    }
    return currentStagedReferences.count > nextStagedReferences.count
      && Set(nextStagedReferences).isSubset(of: Set(currentStagedReferences))
      && currentPendingReferences == nextPendingReferences
  }

  private static func document(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

private actor EventWorkspaceBarrier {
  private let workspace: Workspace
  private var waitsForFirstCall = true
  private var hasEntered = false
  private var releaseRequested = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(workspace: Workspace) {
    self.workspace = workspace
  }

  func next() async -> Workspace {
    guard waitsForFirstCall else { return workspace }
    waitsForFirstCall = false
    hasEntered = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
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

private enum AgentEventTestError: Error {
  case missingProfile
  case writeTimeout
  case writeFailure
  case fileWriteFailure
  case deleteFailure
}

private func eventTestUUID(_ value: String) -> UUID {
  UUID(uuidString: value)!
}

private func eventSecretPayload(byte: UInt8, count: Int) -> String {
  Data(repeating: byte, count: count).base64EncodedString()
}

private func eventSecret(byte: UInt8, count: Int) -> String {
  "whsec_" + eventSecretPayload(byte: byte, count: count)
}
