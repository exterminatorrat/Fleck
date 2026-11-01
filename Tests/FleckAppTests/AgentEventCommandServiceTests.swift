import FleckCore
import FleckMCPFixtureSupport
import Foundation
import Testing

@testable import FleckApp

@Suite("Agent event command service")
struct AgentEventCommandServiceTests {
  @Test @MainActor func callbackVerificationFailuresMapToSanitizedEndpointCategories() throws {
    let nonEndpointFailures: [(AgentEventCallbackVerificationError, AgentWorkspaceErrorCode)] = [
      (.notAuthorized, .capabilityDenied),
      (.verificationInProgress, .internalSaveFailure),
      (.capacityExceeded, .writeTooLarge),
      (.keyUnavailable, .internalSaveFailure),
      (.randomUnavailable, .internalSaveFailure),
      (.busy, .internalSaveFailure),
      (.storageFailure, .internalSaveFailure),
    ]
    for (failure, expectedCode) in nonEndpointFailures {
      let mapped = try AgentCommandService.mapCallbackVerificationFailure(failure)
      #expect(mapped.code == expectedCode)
      #expect(mapped.eventFailure == nil)
    }

    let endpointFailures: [(AgentEventCallbackVerificationError, AgentWorkspaceEventFailure.Reason)] =
      [
        (.verificationFailed, .challengeFailed),
        (.timedOut, .timedOut),
        (.transportFailure, .connectionFailed),
      ]
    for (failure, expectedReason) in endpointFailures {
      let mapped = try AgentCommandService.mapCallbackVerificationFailure(failure)
      #expect(mapped.code == .internalSaveFailure)
      #expect(mapped.eventFailure?.reason == expectedReason)
      #expect(mapped.isSupported(wireVersion: 2))
      #expect(!mapped.isSupported(wireVersion: 1))
    }

    #expect(throws: (any Error).self) {
      try AgentCommandService.mapCallbackVerificationFailure(.cancelled)
    }
  }

  @Test @MainActor func missingEventServiceReturnsUnavailableWithoutEventWrites() async throws {
    let fixture = try await AgentEventIPCFixture()
    defer { fixture.remove() }
    let commandJSON =
      #"{"prepareEventSubscription":{"request":{"event":"note.updated","scope":{"note_id":"\#(fixture.noteID.uuidString.lowercased())"},"callbackURL":"https://example.test/hook","signingSecret":"whsec_\#(Data(repeating: 0x42, count: 24).base64EncodedString())","ttl":{"default":{}}}}}"#
    let command = try? JSONDecoder().decode(
      AgentWorkspaceCommand.self,
      from: Data(commandJSON.utf8)
    )
    #expect(command != nil)
    guard let command else { return }

    do {
      _ = try await fixture.commandService.execute(
        profileID: fixture.profileID,
        credential: fixture.credential,
        command: command
      )
      Issue.record("Expected the default event service to be unavailable.")
    } catch let error as AgentWorkspaceError {
      #expect(error.code == .invalidOperation)
    }

    #expect(!FileManager.default.fileExists(atPath: fixture.subscriptionFileURL.path))
    #expect(fixture.secretStore.writeCount() == 0)
  }

  @Test @MainActor func eventCatalogReflectsAuthorizedScopeKindsWithoutResourceDetails()
    async throws
  {
    let directFixture = try await AgentEventIPCFixture(enableEventService: true)
    defer { directFixture.remove() }
    let listCommand = try eventListCommand()
    let directResponse = try await directFixture.commandService.execute(
      profileID: directFixture.profileID,
      credential: directFixture.credential,
      command: listCommand
    )
    guard case .events(let directEvents) = directResponse else {
      Issue.record("Expected an event catalog response.")
      return
    }
    #expect(!directEvents.isEmpty)
    for event in directEvents {
      #expect(event.inputSchema.oneOf?.count == 1)
      #expect(Set(event.inputSchema.properties?.keys.map { $0 } ?? []) == ["note_id"])
    }
    let directJSON = String(decoding: try JSONEncoder().encode(directResponse), as: UTF8.self)
    #expect(!directJSON.contains(directFixture.noteID.uuidString))
    #expect(!directJSON.contains(directFixture.folderID.uuidString))
    #expect(!directJSON.contains("Private title"))
    #expect(!directJSON.contains("Private body"))

    let folderFixture = try await AgentEventIPCFixture(
      enableEventService: true,
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(
            folderID: UUID(
              uuidString: "00000000-0000-4000-8000-000000000703"
            )!),
          authority: .read
        )
      ]
    )
    defer { folderFixture.remove() }
    let folderResponse = try await folderFixture.commandService.execute(
      profileID: folderFixture.profileID,
      credential: folderFixture.credential,
      command: eventListCommand()
    )
    guard case .events(let folderEvents) = folderResponse else {
      Issue.record("Expected an event catalog response for a folder grant.")
      return
    }
    for event in folderEvents {
      #expect(event.inputSchema.oneOf?.count == 2)
      #expect(Set(event.inputSchema.properties?.keys.map { $0 } ?? []) == ["note_id", "folder_id"])
    }

    directFixture.capabilityAuthority.exclude(noteID: directFixture.noteID)
    let excludedResponse = try await directFixture.commandService.execute(
      profileID: directFixture.profileID,
      credential: directFixture.credential,
      command: listCommand
    )
    #expect(excludedResponse == .events(events: []))
  }

  @Test @MainActor func pendingCommandsRefreshReopenAndRemoveOnlyTheirProfileRow() async throws {
    let fixture = try await AgentEventIPCFixture(enableEventService: true)
    defer { fixture.remove() }
    let command = try eventPrepareCommand(noteID: fixture.noteID)
    let firstResponse = try await fixture.commandService.execute(
      profileID: fixture.profileID,
      credential: fixture.credential,
      command: command
    )
    guard case .pendingEventSubscription(let firstReceipt) = firstResponse else {
      Issue.record("Expected an internal pending receipt.")
      return
    }
    #expect(firstReceipt.status == "pending")
    #expect(fixture.secretStore.secretCount() == 1)

    let secondResponse = try await fixture.commandService.execute(
      profileID: fixture.profileID,
      credential: fixture.credential,
      command: command
    )
    guard case .pendingEventSubscription(let refreshedReceipt) = secondResponse else {
      Issue.record("Expected a refreshed internal pending receipt.")
      return
    }
    #expect(refreshedReceipt.subscriptionID == firstReceipt.subscriptionID)
    #expect(refreshedReceipt.revision == firstReceipt.revision + 1)
    let reopenedStore = AgentEventSubscriptionStore(fileURL: fixture.subscriptionFileURL)
    #expect(
      try await reopenedStore.pendingSubscriptions(profileID: fixture.profileID, now: Date()).count
        == 1
    )

    let otherProfile = try await fixture.registerProfile(
      grants: [
        AgentResourceGrant(scope: .note(noteID: fixture.noteID), authority: .read)
      ]
    )
    let removeCommand = try eventRemoveCommand(noteID: fixture.noteID)
    let otherRemoval = try await fixture.commandService.execute(
      profileID: otherProfile.id,
      credential: otherProfile.credential,
      command: removeCommand
    )
    #expect(otherRemoval == .eventUnsubscribed)
    #expect(
      try await reopenedStore.pendingSubscriptions(profileID: fixture.profileID, now: Date()).count
        == 1
    )

    try await fixture.replaceCapabilities(
      profileID: fixture.profileID,
      grants: [AgentResourceGrant(scope: .note(noteID: fixture.noteID), authority: .read)],
      allowsEventObservation: false
    )
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await fixture.commandService.execute(
        profileID: fixture.profileID,
        credential: fixture.credential,
        command: command
      )
    }
    #expect(fixture.secretStore.secretCount() == 1)
    #expect(
      try await reopenedStore.pendingSubscriptions(profileID: fixture.profileID, now: Date()).count
        == 1
    )

    let ownerRemoval = try await fixture.commandService.execute(
      profileID: fixture.profileID,
      credential: fixture.credential,
      command: removeCommand
    )
    #expect(ownerRemoval == .eventUnsubscribed)
    #expect(
      try await reopenedStore.pendingSubscriptions(profileID: fixture.profileID, now: Date())
        .isEmpty
    )
    #expect(fixture.secretStore.secretCount() == 0)
  }

  @Test @MainActor func profileCredentialIsRecheckedAtEveryPendingMutationCheckpoint()
    async throws
  {
    for refresh in [false, true] {
      for authorizationCall in [3, 4] {
        let fixture = try await AgentEventIPCFixture(enableEventService: true)
        defer { fixture.remove() }
        let command = try eventPrepareCommand(
          noteID: fixture.noteID,
          secretByte: refresh ? 0x43 : 0x42
        )
        let original: AgentEventPendingSubscription?
        if refresh {
          let seedCommand = try eventPrepareCommand(noteID: fixture.noteID)
          _ = try await fixture.commandService.execute(
            profileID: fixture.profileID,
            credential: fixture.credential,
            command: seedCommand
          )
          let subscriptions = try await fixture.eventStore.pendingSubscriptions(
            profileID: fixture.profileID
          )
          guard let subscription = subscriptions.first else {
            Issue.record("Expected the seed subscription to be stored.")
            continue
          }
          original = subscription
        } else {
          original = nil
        }

        let observations = EventAuthorizationSnapshotRecorder()
        let eventStore = fixture.eventStore
        let profileID = fixture.profileID
        let secretStore = fixture.secretStore
        fixture.profileAuthorizer.checkpoint(
          onAuthorizationCall: authorizationCall,
          revoke: true
        ) { call in
          let subscriptions =
            (try? await eventStore.pendingSubscriptions(profileID: profileID)) ?? []
          let staged = (try? await eventStore.stagedSigningKeyReferences()) ?? []
          let pendingDeletion = (try? await eventStore.pendingSigningKeyDeletions()) ?? []
          await observations.record(
            EventAuthorizationSnapshot(
              call: call,
              subscriptions: subscriptions,
              stagedSigningKeyReferences: staged,
              pendingSigningKeyDeletions: pendingDeletion,
              secretCount: secretStore.secretCount()
            )
          )
        }

        do {
          _ = try await fixture.commandService.execute(
            profileID: fixture.profileID,
            credential: fixture.credential,
            command: command
          )
          Issue.record("Expected credential revocation at authorization checkpoint.")
        } catch let error as AgentWorkspaceError {
          #expect(error.code == .capabilityDenied)
        }

        let snapshots = await observations.all()
        #expect(snapshots.count == 1)
        guard let snapshot = snapshots.first else { continue }
        if authorizationCall == 3 {
          #expect(snapshot.subscriptions == (original.map { [$0] } ?? []))
          #expect(snapshot.stagedSigningKeyReferences.count == 1)
          #expect(snapshot.pendingSigningKeyDeletions.isEmpty)
          if let original {
            let stagedReference = try #require(snapshot.stagedSigningKeyReferences.first)
            #expect(stagedReference != original.signingKeyReference)
            #expect(
              try await fixture.eventStore.isSigningKeyReferenced(original.signingKeyReference)
            )
            #expect(snapshot.secretCount == 2)
          }
        } else {
          #expect(snapshot.subscriptions.count == 1)
          #expect(snapshot.stagedSigningKeyReferences.isEmpty)
          if let original {
            let promoted = try #require(snapshot.subscriptions.first)
            let overlap = try #require(promoted.previousSigningKey)
            #expect(promoted.revision == original.revision + 1)
            #expect(promoted.signingKeyReference != original.signingKeyReference)
            #expect(overlap.reference == original.signingKeyReference)
            #expect(overlap.startedAt == promoted.updatedAt)
            #expect(overlap.expiresAt > promoted.updatedAt)
            #expect(
              overlap.expiresAt
                <= promoted.updatedAt.addingTimeInterval(
                  AgentEventPreviousSigningKey.maximumLifetime
                )
            )
            #expect(overlap.expiresAt <= promoted.expiresAt)
            #expect(snapshot.pendingSigningKeyDeletions.isEmpty)
            #expect(
              try await fixture.eventStore.isSigningKeyReferenced(original.signingKeyReference)
            )
            #expect(snapshot.secretCount == 2)
          } else {
            #expect(snapshot.pendingSigningKeyDeletions.isEmpty)
          }
        }

        let restored = try await fixture.eventStore.pendingSubscriptions(
          profileID: fixture.profileID
        )
        if authorizationCall == 3 {
          #expect(restored == (original.map { [$0] } ?? []))
        } else if let original {
          #expect(restored.count == 1)
          let restoredSubscription = try #require(restored.first)
          #expect(
            restoredSubscription.replacingDeliveryControl(nil)
              == original.replacingDeliveryControl(nil)
          )
          let restoredControl = try #require(restoredSubscription.deliveryControl)
          let expectedBinding = AgentEventCallbackVerificationBinding(
            profileID: original.profileID,
            subscriptionID: original.subscriptionID,
            subscriptionRevision: original.revision,
            grantRevision: original.grantRevision,
            signingKeyReference: original.signingKeyReference
          )
          #expect(!restoredControl.enabled)
          #expect(restoredControl.binding == expectedBinding)
          let originalControl = try #require(original.deliveryControl)
          #expect(restoredControl.generationID != originalControl.generationID)
          let mutatedControl = try #require(snapshot.subscriptions.first?.deliveryControl)
          #expect(restoredControl.generationID != mutatedControl.generationID)
        } else {
          #expect(restored.isEmpty)
        }
        #expect(try await fixture.eventStore.stagedSigningKeyReferences().isEmpty)
        #expect(try await fixture.eventStore.pendingSigningKeyCleanupReferences().isEmpty)
        #expect(
          fixture.secretStore.secretCount() == (original == nil ? 0 : 1)
        )
        if let original {
          #expect(try await fixture.eventStore.isSigningKeyReferenced(original.signingKeyReference))
        }
      }
    }
  }

  @Test @MainActor func unavailableWorkspaceAtPostSaveCheckpointRollsBackInitialAndRefresh()
    async throws
  {
    for refresh in [false, true] {
      let fixture = try await AgentEventIPCFixture(enableEventService: true)
      defer { fixture.remove() }
      let command = try eventPrepareCommand(noteID: fixture.noteID)
      let original: AgentEventPendingSubscription?
      if refresh {
        _ = try await fixture.commandService.execute(
          profileID: fixture.profileID,
          credential: fixture.credential,
          command: command
        )
        let subscriptions = try await fixture.eventStore.pendingSubscriptions(
          profileID: fixture.profileID
        )
        guard let subscription = subscriptions.first else {
          Issue.record("Expected the seed subscription to be stored.")
          continue
        }
        original = subscription
      } else {
        original = nil
      }

      let gate = EventIPCCheckpointGate()
      fixture.state.pauseFlush(onCall: 3, gate: gate)
      let request = Task {
        try await fixture.commandService.execute(
          profileID: fixture.profileID,
          credential: fixture.credential,
          command: command
        )
      }
      await gate.waitUntilPaused()
      let mutated = try await fixture.eventStore.pendingSubscriptions(
        profileID: fixture.profileID
      )
      #expect(mutated.count == 1)
      fixture.state.isAgentWorkspaceAvailable = false
      await gate.resume()

      do {
        _ = try await request.value
        Issue.record("Expected the unavailable workspace to reject the pending mutation.")
      } catch let error as AgentWorkspaceError {
        #expect(error.code == .capabilityDenied)
      }
      let restored = try await fixture.eventStore.pendingSubscriptions(
        profileID: fixture.profileID
      )
      if let original {
        #expect(restored.count == 1)
        let restoredSubscription = try #require(restored.first)
        #expect(
          restoredSubscription.replacingDeliveryControl(nil)
            == original.replacingDeliveryControl(nil)
        )
        let restoredControl = try #require(restoredSubscription.deliveryControl)
        let expectedBinding = AgentEventCallbackVerificationBinding(
          profileID: original.profileID,
          subscriptionID: original.subscriptionID,
          subscriptionRevision: original.revision,
          grantRevision: original.grantRevision,
          signingKeyReference: original.signingKeyReference
        )
        #expect(!restoredControl.enabled)
        #expect(restoredControl.binding == expectedBinding)
        let originalControl = try #require(original.deliveryControl)
        #expect(restoredControl.generationID != originalControl.generationID)
        let mutatedControl = try #require(mutated.first?.deliveryControl)
        #expect(restoredControl.generationID != mutatedControl.generationID)
      } else {
        #expect(restored.isEmpty)
      }
      #expect(try await fixture.eventStore.stagedSigningKeyReferences().isEmpty)
      #expect(try await fixture.eventStore.pendingSigningKeyCleanupReferences().isEmpty)
      #expect(fixture.secretStore.secretCount() == (original == nil ? 0 : 1))
    }
  }

  @Test @MainActor func movedNoteScopeWhileWorkspaceReadIsSuspendedRollsBackRefresh()
    async throws
  {
    let fixture = try await AgentEventIPCFixture(
      enableEventService: true,
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(
            folderID: UUID(
              uuidString: "00000000-0000-4000-8000-000000000703"
            )!),
          authority: .read
        )
      ]
    )
    defer { fixture.remove() }
    let command = try eventPrepareCommand(noteID: fixture.noteID)
    _ = try await fixture.commandService.execute(
      profileID: fixture.profileID,
      credential: fixture.credential,
      command: command
    )
    let subscriptions = try await fixture.eventStore.pendingSubscriptions(
      profileID: fixture.profileID
    )
    guard let original = subscriptions.first else {
      Issue.record("Expected the seed subscription to be stored.")
      return
    }

    let gate = EventIPCCheckpointGate()
    fixture.state.pauseFlush(onCall: 3, gate: gate)
    let request = Task {
      try await fixture.commandService.execute(
        profileID: fixture.profileID,
        credential: fixture.credential,
        command: command
      )
    }
    await gate.waitUntilPaused()
    var movedWorkspace = fixture.state.workspace
    try movedWorkspace.moveNote(id: fixture.noteID, toFolderID: nil)
    fixture.state.replaceWorkspace(movedWorkspace)
    await gate.resume()

    do {
      _ = try await request.value
      Issue.record("Expected the moved note to invalidate its event scope.")
    } catch let error as AgentWorkspaceError {
      #expect(error.code == .capabilityDenied)
    }
    let restored = try await fixture.eventStore.pendingSubscriptions(
      profileID: fixture.profileID
    )
    #expect(restored.count == 1)
    let restoredSubscription = try #require(restored.first)
    #expect(
      restoredSubscription.replacingDeliveryControl(nil)
        == original.replacingDeliveryControl(nil)
    )
    let restoredControl = try #require(restoredSubscription.deliveryControl)
    let expectedBinding = AgentEventCallbackVerificationBinding(
      profileID: original.profileID,
      subscriptionID: original.subscriptionID,
      subscriptionRevision: original.revision,
      grantRevision: original.grantRevision,
      signingKeyReference: original.signingKeyReference
    )
    #expect(!restoredControl.enabled)
    #expect(restoredControl.binding == expectedBinding)
    let originalControl = try #require(original.deliveryControl)
    #expect(restoredControl.generationID != originalControl.generationID)
    #expect(try await fixture.eventStore.isSigningKeyReferenced(original.signingKeyReference))
    #expect(try await fixture.eventStore.pendingSigningKeyCleanupReferences().isEmpty)
    #expect(fixture.secretStore.secretCount() == 1)
  }
}

private struct EventAuthorizationSnapshot: Sendable {
  let call: Int
  let subscriptions: [AgentEventPendingSubscription]
  let stagedSigningKeyReferences: [String]
  let pendingSigningKeyDeletions: [String]
  let secretCount: Int
}

private actor EventAuthorizationSnapshotRecorder {
  private var snapshots: [EventAuthorizationSnapshot] = []

  func record(_ snapshot: EventAuthorizationSnapshot) {
    snapshots.append(snapshot)
  }

  func all() -> [EventAuthorizationSnapshot] {
    snapshots
  }
}

@MainActor
private func eventListCommand() throws -> AgentWorkspaceCommand {
  try JSONDecoder().decode(AgentWorkspaceCommand.self, from: Data(#"{"listEvents":{}}"#.utf8))
}

@MainActor
private func eventPrepareCommand(
  noteID: UUID,
  secretByte: UInt8 = 0x42
) throws -> AgentWorkspaceCommand {
  let secret = "whsec_" + Data(repeating: secretByte, count: 24).base64EncodedString()
  let json =
    #"{"prepareEventSubscription":{"request":{"event":"note.updated","scope":{"note_id":"\#(noteID.uuidString.lowercased())"},"callbackURL":"https://example.test/hook","signingSecret":"\#(secret)","ttl":{"default":{}}}}}"#
  return try JSONDecoder().decode(AgentWorkspaceCommand.self, from: Data(json.utf8))
}

@MainActor
private func eventRemoveCommand(noteID: UUID) throws -> AgentWorkspaceCommand {
  let json =
    #"{"removeEventSubscription":{"request":{"event":"note.updated","scope":{"note_id":"\#(noteID.uuidString.lowercased())"},"callbackURL":"https://example.test/hook"}}}"#
  return try JSONDecoder().decode(AgentWorkspaceCommand.self, from: Data(json.utf8))
}

@MainActor
final class AgentEventIPCFixture {
  let rootURL: URL
  let ownedRoot: OwnedMCPFixtureRoot
  let profileID = UUID(uuidString: "00000000-0000-4000-8000-000000000701")!
  let credential = Data(repeating: 0x31, count: 32)
  let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000702")!
  let folderID = UUID(uuidString: "00000000-0000-4000-8000-000000000703")!
  let subscriptionFileURL: URL
  let state: EventIPCWorkspaceState
  let capabilityStore: AgentCapabilityStore
  let capabilityAuthority: AgentCapabilityAuthority
  let profileAuthorizer: EventIPCProfileAuthorizer
  let eventStore: AgentEventSubscriptionStore
  let secretStore: EventIPCSecretStore
  let eventService: AgentEventSubscriptionService
  let commandService: AgentCommandService

  init(
    enableEventService: Bool = false,
    grants: [AgentResourceGrant]? = nil
  ) async throws {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventCommandService)
    self.ownedRoot = ownedRoot
    var ownershipTransferred = false
    defer {
      if !ownershipTransferred {
        do {
          try ownedRoot.cleanup()
        } catch {
          Issue.record("IPC fixture construction cleanup failed: \(error)")
        }
      }
    }
    rootURL = ownedRoot.url
    let folder = try Folder(id: folderID, name: "Private folder")
    let workspace = Workspace(
      notes: [Note(id: noteID, title: "Private title", body: "Private body", folderID: folderID)],
      folders: [folder]
    )
    state = EventIPCWorkspaceState(workspace: workspace)

    capabilityStore = AgentCapabilityStore(
      capabilitiesURL: rootURL.appendingPathComponent("capabilities.json")
    )
    _ = try await capabilityStore.loadOrMigrate(activeProfileIDs: [], workspace: workspace)
    _ = try await capabilityStore.registerEmptyProfile(profileID)
    _ = try await capabilityStore.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: 1,
        allowedCapabilities: [.listNotes, .readNotes],
        grants: grants ?? [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
        allowsEventObservation: true
      ),
      expectedGrantRevision: 0
    )
    capabilityAuthority = AgentCapabilityAuthority(store: capabilityStore)

    profileAuthorizer = EventIPCProfileAuthorizer()
    profileAuthorizer.add(profileID: profileID, credential: credential)
    subscriptionFileURL = rootURL.appendingPathComponent("event-subscriptions.json")
    eventStore = AgentEventSubscriptionStore(fileURL: subscriptionFileURL)
    secretStore = EventIPCSecretStore()
    eventService = AgentEventSubscriptionService(
      authority: capabilityAuthority,
      store: eventStore,
      signingKeyStore: AgentEventSigningKeyStore(secretStore: secretStore)
    )
    commandService = AgentCommandService(
      state: state,
      profileStore: profileAuthorizer,
      activityStore: AgentActivityStore(rootURL: rootURL.appendingPathComponent("activity")),
      capabilityAuthority: capabilityAuthority,
      eventService: enableEventService ? eventService : nil
    )
    ownershipTransferred = true
  }

  func registerProfile(grants: [AgentResourceGrant]) async throws -> (id: UUID, credential: Data) {
    let id = UUID()
    let credential = Data(repeating: UInt8(id.uuidString.utf8.first ?? 0x32), count: 32)
    _ = try await capabilityStore.registerEmptyProfile(id)
    _ = try await capabilityStore.replaceProfile(
      AgentProfileCapabilities(
        profileID: id,
        grantRevision: 1,
        allowedCapabilities: [.listNotes, .readNotes],
        grants: grants,
        allowsEventObservation: true
      ),
      expectedGrantRevision: 0
    )
    profileAuthorizer.add(profileID: id, credential: credential)
    return (id, credential)
  }

  func replaceCapabilities(
    profileID: UUID,
    grants: [AgentResourceGrant],
    allowsEventObservation: Bool
  ) async throws {
    let state = try await capabilityStore.currentState()
    guard let current = state.profiles[profileID] else {
      throw AgentWorkspaceError(code: .permissionRevoked)
    }
    _ = try await capabilityStore.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: current.grantRevision + 1,
        allowedCapabilities: current.allowedCapabilities,
        grants: grants,
        allowsEventObservation: allowsEventObservation
      ),
      expectedGrantRevision: current.grantRevision
    )
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("IPC fixture cleanup failed: \(error)")
    }
  }
}

@MainActor
final class EventIPCWorkspaceState: AgentWorkspaceStateAccess {
  private var workspaceValue: Workspace
  private var flushCount = 0
  private var flushCheckpoint: (call: Int, gate: EventIPCCheckpointGate)?
  var persistenceGeneration: UInt64 = 1
  var preferences = AppPreferences()
  var isAgentWorkspaceAvailable = true
  var agentCommitProofs: [AgentWorkspaceCommitProof] = []

  init(workspace: Workspace) {
    workspaceValue = workspace
  }

  var workspace: Workspace { workspaceValue }

  func flushPendingPersistenceForAgent() async throws {
    flushCount += 1
    if flushCount == flushCheckpoint?.call {
      await flushCheckpoint?.gate.pause()
    }
  }

  fileprivate func pauseFlush(onCall call: Int, gate: EventIPCCheckpointGate) {
    flushCount = 0
    flushCheckpoint = (call, gate)
  }

  func replaceWorkspace(_ workspace: Workspace) {
    workspaceValue = workspace
    persistenceGeneration += 1
  }

  func commitAgentWorkspace(
    _ workspace: Workspace,
    expectedGeneration: UInt64,
    commitProof: AgentWorkspaceCommitProof
  ) throws {
    workspaceValue = workspace
    persistenceGeneration += 1
    agentCommitProofs.append(commitProof)
  }

  func publishAgentFeedback(_ feedback: AgentChangeFeedback) {}
  func publishAgentRequestEvent(_ event: AgentRequestEvent) {}
}

final class EventIPCProfileAuthorizer: AgentProfileAuthorizing, @unchecked Sendable {
  private let lock = NSLock()
  private var credentials: [UUID: Data] = [:]
  private var authorizationCallCount = 0
  private var checkpointCall: Int?
  private var checkpointRevokes = false
  private var checkpointHandler: (@Sendable (Int) async -> Void)?

  func add(profileID: UUID, credential: Data) {
    lock.withLock { credentials[profileID] = credential }
  }

  func checkpoint(
    onAuthorizationCall call: Int,
    revoke: Bool,
    handler: @escaping @Sendable (Int) async -> Void
  ) {
    lock.withLock {
      authorizationCallCount = 0
      checkpointCall = call
      checkpointRevokes = revoke
      checkpointHandler = handler
    }
  }

  func authorize(profileID: UUID, credential: Data) async throws -> AgentIntegrationProfile {
    let (call, authorized, shouldRevoke, handler) = lock.withLock {
      authorizationCallCount += 1
      let call = authorizationCallCount
      return (
        call,
        credentials[profileID] == credential,
        checkpointCall == call && checkpointRevokes,
        checkpointCall == call ? checkpointHandler : nil
      )
    }
    await handler?(call)
    if shouldRevoke {
      lock.withLock { credentials[profileID] = nil }
      throw AgentWorkspaceError(code: .permissionRevoked)
    }
    guard authorized else { throw AgentWorkspaceError(code: .permissionRevoked) }
    return AgentIntegrationProfile(
      id: profileID,
      displayName: "Isolated test profile",
      createdAt: Date(timeIntervalSince1970: 0),
      lastConnectedAt: nil,
      revokedAt: nil
    )
  }
}

private actor EventIPCCheckpointGate {
  private var didPause = false
  private var pauseContinuation: CheckedContinuation<Void, Never>?
  private var arrivalContinuation: CheckedContinuation<Void, Never>?

  func pause() async {
    didPause = true
    arrivalContinuation?.resume()
    arrivalContinuation = nil
    await withCheckedContinuation { continuation in
      pauseContinuation = continuation
    }
  }

  func waitUntilPaused() async {
    guard !didPause else { return }
    await withCheckedContinuation { continuation in
      arrivalContinuation = continuation
    }
  }

  func resume() {
    pauseContinuation?.resume()
    pauseContinuation = nil
  }
}

final class EventIPCSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: Data] = [:]
  private var writes = 0

  func read(service: String, account: String) throws -> Data? {
    lock.withLock { storage[account] }
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock {
      writes += 1
      storage[account] = data
    }
  }

  func delete(service: String, account: String) throws {
    lock.withLock { storage[account] = nil }
  }

  func writeCount() -> Int {
    lock.withLock { writes }
  }

  func secretCount() -> Int {
    lock.withLock { storage.count }
  }
}
