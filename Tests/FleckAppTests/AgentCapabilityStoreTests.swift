import FleckCore
import Foundation
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentCapabilityStoreTests {
  @Test func MigratesLegacySharesToEveryActiveProfile() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }

    let sharedID = testUUID("00000000-0000-0000-0000-000000000101")
    let privateID = testUUID("00000000-0000-0000-0000-000000000102")
    let firstProfileID = testUUID("00000000-0000-0000-0000-000000000111")
    let secondProfileID = testUUID("00000000-0000-0000-0000-000000000112")
    let shared = Note(
      id: sharedID,
      title: "Shared",
      body: "Legacy body",
      agentAccess: true
    )
    let privateNote = Note(
      id: privateID,
      title: "Private",
      body: "Private body"
    )
    let workspace = Workspace(notes: [shared, privateNote])

    let migrated = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [secondProfileID, firstProfileID],
      workspace: workspace
    )

    #expect(Set(migrated.profiles.keys) == [firstProfileID, secondProfileID])
    #expect(migrated.unassignedLegacyNoteIDs.isEmpty)
    #expect(shared.agentAccess)
    #expect(!privateNote.agentAccess)

    for profileID in [firstProfileID, secondProfileID] {
      let profile = try #require(migrated.profiles[profileID])
      #expect(profile.grantRevision == 1)
      #expect(profile.allowedCapabilities == Set(AgentCapability.allCases))
      #expect(profile.grants.count == 1)
      #expect(
        profile.grants[0].scope == AgentGrantScope.note(noteID: sharedID)
      )
      #expect(profile.grants[0].authority == .write)
    }
  }

  @Test func NoProfileLegacySharesNeverFlowToANewProfile() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    let shared = Note(
      id: testUUID("00000000-0000-0000-0000-000000000121"),
      agentAccess: true
    )

    let migrated = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [],
      workspace: Workspace(notes: [shared])
    )
    #expect(migrated.unassignedLegacyNoteIDs == [shared.id])

    let profileID = testUUID("00000000-0000-0000-0000-000000000122")
    let created = try await fixture.store.registerEmptyProfile(profileID)
    #expect(created.profiles[profileID]?.grants.isEmpty == true)
    #expect(created.profiles[profileID]?.allowedCapabilities.isEmpty == true)
    #expect(created.unassignedLegacyNoteIDs == [shared.id])
  }

  @Test func MigrationIsOneTimeAndDoesNotWidenOnRerun() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000131")
    let firstShared = Note(
      id: testUUID("00000000-0000-0000-0000-000000000132"),
      agentAccess: true
    )
    let firstState = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace(notes: [firstShared])
    )
    let firstBytes = try Data(contentsOf: fixture.capabilitiesURL)

    let secondShared = Note(
      id: testUUID("00000000-0000-0000-0000-000000000133"),
      agentAccess: true
    )
    let rerun = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID, testUUID("00000000-0000-0000-0000-000000000134")],
      workspace: Workspace(notes: [firstShared, secondShared])
    )

    #expect(rerun == firstState)
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == firstBytes)
  }

  @Test func DuplicateRegistrationFailsWithoutWriting() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000141")
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    let before = try Data(contentsOf: fixture.capabilitiesURL)

    await #expect(throws: AgentWorkspaceError(code: .invalidPayload)) {
      _ = try await fixture.store.registerEmptyProfile(profileID)
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == before)
  }

  @Test func ReplaceRequiresCurrentProfileAndAdvancesExactlyOneRevision() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000151")
    let state = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    let current = try #require(state.profiles[profileID])
    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: [.listNotes],
      grants: []
    )

    let updated = try await fixture.store.replaceProfile(
      replacement,
      expectedGrantRevision: current.grantRevision
    )
    #expect(updated.profiles[profileID] == replacement)

    let beforeStaleWrite = try Data(contentsOf: fixture.capabilitiesURL)
    let staleReplacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: Set(AgentCapability.allCases),
      grants: []
    )
    await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
      _ = try await fixture.store.replaceProfile(
        staleReplacement,
        expectedGrantRevision: current.grantRevision
      )
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == beforeStaleWrite)

    let mismatched = AgentProfileCapabilities(
      profileID: testUUID("00000000-0000-0000-0000-000000000152"),
      grantRevision: replacement.grantRevision + 1,
      allowedCapabilities: [],
      grants: []
    )
    await #expect(throws: AgentWorkspaceError(code: .invalidPayload)) {
      _ = try await fixture.store.replaceProfile(
        mismatched,
        expectedGrantRevision: replacement.grantRevision
      )
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == beforeStaleWrite)
  }

  @Test func EquivalentMigrationsProduceIdenticalPrettySortedBytes() async throws {
    let profileIDs = [
      testUUID("00000000-0000-0000-0000-000000000161"),
      testUUID("00000000-0000-0000-0000-000000000162"),
    ]
    let notes = [
      Note(
        id: testUUID("00000000-0000-0000-0000-000000000163"),
        agentAccess: true
      ),
      Note(
        id: testUUID("00000000-0000-0000-0000-000000000164"),
        agentAccess: false
      ),
    ]
    let firstFixture = try CapabilityStoreFixture()
    let secondFixture = try CapabilityStoreFixture()
    defer {
      firstFixture.remove()
      secondFixture.remove()
    }

    _ = try await firstFixture.store.loadOrMigrate(
      activeProfileIDs: profileIDs.reversed(),
      workspace: Workspace(notes: notes.reversed())
    )
    _ = try await secondFixture.store.loadOrMigrate(
      activeProfileIDs: profileIDs,
      workspace: Workspace(notes: notes)
    )

    let firstBytes = try Data(contentsOf: firstFixture.capabilitiesURL)
    let secondBytes = try Data(contentsOf: secondFixture.capabilitiesURL)
    #expect(firstBytes == secondBytes)
    #expect(String(decoding: firstBytes, as: UTF8.self).contains("\n  \""))
  }

  @Test func CurrentRecoveryRestoresPreviousCompleteState() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000171")
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    let current = try #require(initial.profiles[profileID])
    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: []
    )
    let latest = try await fixture.store.replaceProfile(
      replacement,
      expectedGrantRevision: current.grantRevision
    )
    let previousBytes = try Data(contentsOf: fixture.previousCapabilitiesURL)
    try Data("corrupt-current".utf8).write(to: fixture.capabilitiesURL)

    let reloaded = AgentCapabilityStore(
      capabilitiesURL: fixture.capabilitiesURL,
      previousCapabilitiesURL: fixture.previousCapabilitiesURL
    )
    let recovered = try await reloaded.currentState()
    #expect(recovered == initial)
    #expect(recovered != latest)
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == previousBytes)
  }

  @Test func UnknownSchemaAndMalformedGenerationsFailClosed() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    try fixture.makeDirectory()
    try Data(#"{"schemaVersion":99}"#.utf8).write(to: fixture.capabilitiesURL)

    let unknownSchemaStore = AgentCapabilityStore(
      capabilitiesURL: fixture.capabilitiesURL,
      previousCapabilitiesURL: fixture.previousCapabilitiesURL
    )
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await unknownSchemaStore.currentState()
    }

    try Data("not-json".utf8).write(to: fixture.previousCapabilitiesURL)
    let malformedBothStore = AgentCapabilityStore(
      capabilitiesURL: fixture.capabilitiesURL,
      previousCapabilitiesURL: fixture.previousCapabilitiesURL
    )
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await malformedBothStore.currentState()
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == Data(#"{"schemaVersion":99}"#.utf8))
    #expect(try Data(contentsOf: fixture.previousCapabilitiesURL) == Data("not-json".utf8))
  }

  @Test func CapabilityDocumentContainsNoCredentialVerifierOrNoteBodyText() async throws {
    let fixture = try CapabilityStoreFixture()
    defer { fixture.remove() }
    let body = "private-body-never-persists-in-capability-state"
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [testUUID("00000000-0000-0000-0000-000000000181")],
      workspace: Workspace(notes: [
        Note(
          id: testUUID("00000000-0000-0000-0000-000000000182"),
          body: body,
          agentAccess: true
        )
      ])
    )

    let json = String(
      decoding: try Data(contentsOf: fixture.capabilitiesURL),
      as: UTF8.self
    )
    #expect(!json.contains(body))
    #expect(!json.localizedCaseInsensitiveContains("credential"))
    #expect(!json.localizedCaseInsensitiveContains("verifier"))
    #expect(!json.contains("agentAccess"))
  }
}

private struct CapabilityStoreFixture {
  let rootURL: URL
  let capabilitiesURL: URL
  let previousCapabilitiesURL: URL
  let store: AgentCapabilityStore

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    capabilitiesURL = rootURL
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("capabilities.json")
    previousCapabilitiesURL = rootURL
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("capabilities.previous.json")
    store = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
  }

  func makeDirectory() throws {
    try FileManager.default.createDirectory(
      at: capabilitiesURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private func testUUID(_ value: String) -> UUID {
  UUID(uuidString: value)!
}
