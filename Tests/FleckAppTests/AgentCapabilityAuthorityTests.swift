import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentCapabilityAuthorityTests {
  @Test func DelegatesScopeComputationToAgentCapabilityPolicy() async throws {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000701")
    let grantedNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000702"),
      agentAccess: true
    )
    let workspace = Workspace(notes: [grantedNote])
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    let current = try #require(initial.profiles[profileID])
    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: [.listNotes, .readNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: grantedNote.id),
          authority: .read
        )
      ]
    )
    _ = try await fixture.store.replaceProfile(
      replacement,
      expectedGrantRevision: current.grantRevision
    )

    let authority = AgentCapabilityAuthority(store: fixture.store)
    let snapshot = try await authority.snapshot(
      profileID: profileID,
      workspace: workspace
    )

    #expect(
      snapshot
        == AgentCapabilityPolicy.authorizationSnapshot(
          for: replacement,
          workspace: workspace
        )
    )
  }

  @Test func UnknownProfileIsContentFreeCapabilityDenied() async throws {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let knownProfileID = testUUID("00000000-0000-0000-0000-000000000711")
    let workspace = Workspace()
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [knownProfileID],
      workspace: workspace
    )
    let authority = AgentCapabilityAuthority(store: fixture.store)

    do {
      _ = try await authority.snapshot(
        profileID: testUUID("00000000-0000-0000-0000-000000000712"),
        workspace: workspace
      )
      Issue.record("Expected capability denial")
    } catch let error as AgentWorkspaceError {
      #expect(error == AgentWorkspaceError(code: .capabilityDenied))
      #expect(
        try JSONEncoder().encode(error)
          == JSONEncoder().encode(AgentWorkspaceError(code: .capabilityDenied))
      )
    }
  }

  @Test func CurrentGrantRevisionIsAccepted() async throws {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000721")
    let workspace = Workspace()
    let state = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    let profile = try #require(state.profiles[profileID])
    let authority = AgentCapabilityAuthority(store: fixture.store)

    try await authority.assertCurrent(
      profileID: profileID,
      grantRevision: profile.grantRevision
    )
  }

  @Test func ReplacedGrantRejectsItsStaleRevisionAsContentFreeCapabilityDenied()
    async throws
  {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000731")
    let workspace = Workspace()
    let state = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    let current = try #require(state.profiles[profileID])
    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: [],
      grants: []
    )
    _ = try await fixture.store.replaceProfile(
      replacement,
      expectedGrantRevision: current.grantRevision
    )
    let authority = AgentCapabilityAuthority(store: fixture.store)

    do {
      try await authority.assertCurrent(
        profileID: profileID,
        grantRevision: current.grantRevision
      )
      Issue.record("Expected stale grant denial")
    } catch let error as AgentWorkspaceError {
      #expect(error == AgentWorkspaceError(code: .capabilityDenied))
      #expect(error.recoveryAction == nil)
    }
  }
}

private final class CapabilityAuthorityFixture {
  let root: URL
  let store: AgentCapabilityStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentCapabilityAuthorityTests-\(UUID().uuidString)",
        isDirectory: true
      )
    store = AgentCapabilityStore(
      capabilitiesURL: root
        .appendingPathComponent("AgentIntegrations", isDirectory: true)
        .appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: root
        .appendingPathComponent("AgentIntegrations", isDirectory: true)
        .appendingPathComponent("capabilities.previous.json")
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

private func testUUID(_ value: String) -> UUID {
  UUID(uuidString: value)!
}
