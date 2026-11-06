import FleckCore
import Foundation
import FleckMCPFixtureSupport
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

  @Test func TemporaryExclusionGenerationTracksSetMutationAndSharedCopies()
    async throws
  {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000741")
    let noteID = testUUID("00000000-0000-0000-0000-000000000742")
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace(notes: [Note(id: noteID, agentAccess: true)])
    )
    let authority = AgentCapabilityAuthority(store: fixture.store)
    let copy = authority
    let initial = try #require(authority.temporaryExclusionGeneration)

    authority.include(noteID: noteID)
    #expect(authority.temporaryExclusionGeneration == initial)
    authority.exclude(noteID: noteID)
    let excluded = try #require(authority.temporaryExclusionGeneration)
    #expect(excluded != initial)
    #expect(copy.temporaryExclusionGeneration == excluded)
    authority.exclude(noteID: noteID)
    #expect(authority.temporaryExclusionGeneration == excluded)
    authority.include(noteID: noteID)
    let included = try #require(authority.temporaryExclusionGeneration)
    #expect(included != excluded)
    #expect(included != initial)
    #expect(copy.temporaryExclusionGeneration == included)
    authority.include(noteID: noteID)
    #expect(authority.temporaryExclusionGeneration == included)
  }

  @Test func ContextAwareAssertionRejectsStaleTemporaryExclusionGeneration()
    async throws
  {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000751")
    let noteID = testUUID("00000000-0000-0000-0000-000000000752")
    let state = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace(notes: [Note(id: noteID, agentAccess: true)])
    )
    let profile = try #require(state.profiles[profileID])
    let authority = AgentCapabilityAuthority(store: fixture.store)
    let expectedGeneration = try #require(authority.temporaryExclusionGeneration)
    authority.exclude(noteID: noteID)

    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      try await authority.assertCurrent(
        profileID: profileID,
        grantRevision: profile.grantRevision,
        expectedTemporaryExclusionGeneration: expectedGeneration
      )
    }
  }

  @Test func defaultContextAssertionRejectsMismatchedGenerationBeforeLegacyAssertion()
    async throws
  {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000761")
    let noteID = testUUID("00000000-0000-0000-0000-000000000762")
    let state = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace(notes: [Note(id: noteID, agentAccess: true)])
    )
    let profile = try #require(state.profiles[profileID])
    let authority = AgentCapabilityAuthority(store: fixture.store)
    let generation = try #require(authority.temporaryExclusionGeneration)
    let probe = LegacyCapabilityAssertionProbe(pauses: false)
    let authorizer = GenerationAwareLegacyCapabilityAuthorizer(
      base: authority,
      probe: probe
    )
    let mismatchedGeneration = UUID()
    #expect(mismatchedGeneration != generation)

    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      try await authorizer.assertCurrent(
        profileID: profileID,
        grantRevision: profile.grantRevision,
        expectedTemporaryExclusionGeneration: mismatchedGeneration
      )
    }
    let legacyAssertionCount = await probe.legacyAssertionCount()
    #expect(legacyAssertionCount == 0)
  }

  @Test func defaultContextAssertionRejectsGenerationChangedDuringLegacyAssertion()
    async throws
  {
    let fixture = try CapabilityAuthorityFixture()
    defer { fixture.remove() }
    let profileID = testUUID("00000000-0000-0000-0000-000000000771")
    let noteID = testUUID("00000000-0000-0000-0000-000000000772")
    let state = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace(notes: [Note(id: noteID, agentAccess: true)])
    )
    let profile = try #require(state.profiles[profileID])
    let authority = AgentCapabilityAuthority(store: fixture.store)
    let generation = try #require(authority.temporaryExclusionGeneration)
    let probe = LegacyCapabilityAssertionProbe(pauses: true)
    let authorizer = GenerationAwareLegacyCapabilityAuthorizer(
      base: authority,
      probe: probe
    )
    let assertion = Task {
      try await authorizer.assertCurrent(
        profileID: profileID,
        grantRevision: profile.grantRevision,
        expectedTemporaryExclusionGeneration: generation
      )
    }
    await probe.waitUntilLegacyAssertionStarts()
    authority.exclude(noteID: noteID)
    await probe.resume()

    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      try await assertion.value
    }
    #expect(authority.temporaryExclusionGeneration != generation)
    let legacyAssertionCount = await probe.legacyAssertionCount()
    #expect(legacyAssertionCount == 1)
  }
}

private final class CapabilityAuthorityFixture {
  let ownedRoot: OwnedMCPFixtureRoot
  let root: URL
  let store: AgentCapabilityStore

  init() throws {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .capabilityAuthority)
    self.ownedRoot = ownedRoot
    root = ownedRoot.url
    store = AgentCapabilityStore(
      capabilitiesURL:
        root
        .appendingPathComponent("AgentIntegrations", isDirectory: true)
        .appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL:
        root
        .appendingPathComponent("AgentIntegrations", isDirectory: true)
        .appendingPathComponent("capabilities.previous.json")
    )
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Owned MCP fixture cleanup failed: \(error)")
    }
  }
}

private actor LegacyCapabilityAssertionProbe {
  private let pauses: Bool
  private var assertionCount = 0
  private var isPaused = false
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var resumeContinuation: CheckedContinuation<Void, Never>?

  init(pauses: Bool) {
    self.pauses = pauses
  }

  func legacyAssertion() async {
    assertionCount += 1
    guard pauses else { return }
    isPaused = true
    startContinuation?.resume()
    startContinuation = nil
    await withCheckedContinuation { resumeContinuation = $0 }
  }

  func waitUntilLegacyAssertionStarts() async {
    guard !isPaused else { return }
    await withCheckedContinuation { startContinuation = $0 }
  }

  func resume() {
    resumeContinuation?.resume()
    resumeContinuation = nil
  }

  func legacyAssertionCount() -> Int {
    assertionCount
  }
}

private struct GenerationAwareLegacyCapabilityAuthorizer: AgentCapabilityAuthorizing {
  let base: AgentCapabilityAuthority
  let probe: LegacyCapabilityAssertionProbe

  var temporaryExclusionGeneration: UUID? {
    base.temporaryExclusionGeneration
  }

  func snapshot(
    profileID: UUID,
    workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot {
    try await base.snapshot(profileID: profileID, workspace: workspace)
  }

  func assertCurrent(
    profileID: UUID,
    grantRevision: UInt64
  ) async throws {
    try await base.assertCurrent(
      profileID: profileID,
      grantRevision: grantRevision
    )
    await probe.legacyAssertion()
  }
}

private func testUUID(_ value: String) -> UUID {
  UUID(uuidString: value)!
}
