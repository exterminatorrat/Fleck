import FleckCore
import Foundation
import Security
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentProfileStoreTests {
  @Test func unsignedDevelopmentKeychainQueryUsesLoginKeychain() {
    let query = AgentKeychainSecretStore.baseQuery(
      service: "service",
      account: "account"
    )

    #expect(
      query[kSecClass] as? String == kSecClassGenericPassword as String
    )
    #expect(query[kSecAttrService] as? String == "service")
    #expect(query[kSecAttrAccount] as? String == "account")
    #expect(query[kSecUseDataProtectionKeychain] == nil)
    #expect(
      query[kSecAttrAccessible] == nil,
      "Accessibility belongs on additions, not lookup/update queries."
    )
  }

  @Test func createTrimsNameReturnsCredentialOnceAndPersistsMetadataOnly() async throws {
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0xA5, count: 32)
    )
    defer { fixture.remove() }

    let provisioning = try await fixture.store.create(name: "  Codex \n")

    #expect(provisioning.profile.displayName == "Codex")
    #expect(provisioning.credential == Data(repeating: 0xA5, count: 32))
    #expect(
      fixture.secrets.value(
        service: AgentCredentialSecurity.profileVerifierService,
        account: provisioning.profile.id.uuidString
      ) == AgentCredentialSecurity.sha256(provisioning.credential)
    )

    let profiles = try await fixture.store.activeProfiles()
    #expect(profiles == [provisioning.profile])
    let persisted = try Data(contentsOf: fixture.profilesURL)
    let json = String(decoding: persisted, as: UTF8.self)
    #expect(!json.contains(provisioning.credential.base64EncodedString()))
    #expect(
      !json.contains(
        AgentCredentialSecurity.sha256(provisioning.credential).base64EncodedString()
      ))
    #expect(!json.localizedCaseInsensitiveContains("credential"))
    #expect(!json.localizedCaseInsensitiveContains("verifier"))
  }

  @Test func nameMustContainBetweenOneAndEightyTrimmedCharacters() async throws {
    let fixture = try ProfileFixture()
    defer { fixture.remove() }

    for invalid in ["", " \n\t ", String(repeating: "a", count: 81)] {
      await #expect(throws: AgentWorkspaceError.self) {
        try await fixture.store.create(name: invalid)
      }
    }

    let profile = try await fixture.store.create(
      name: String(repeating: "😀", count: 80)
    )
    #expect(profile.profile.displayName.count == 80)
  }

  @Test func createRejectsRandomGeneratorsThatDoNotReturnExactlyThirtyTwoBytes() async throws {
    for byteCount in [0, 31, 33] {
      let fixture = try ProfileFixture(
        randomBytes: Data(repeating: 0x01, count: byteCount)
      )
      defer { fixture.remove() }

      await #expect(throws: AgentWorkspaceError.self) {
        try await fixture.store.create(name: "Codex")
      }
      #expect(!FileManager.default.fileExists(atPath: fixture.profilesURL.path))
      #expect(fixture.secrets.entries.isEmpty)
    }
  }

  @Test func validCredentialAuthorizesAndUpdatesLastConnection() async throws {
    let dates = DateSequence([
      Date(timeIntervalSince1970: 100),
      Date(timeIntervalSince1970: 200),
    ])
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0x7B, count: 32),
      now: { dates.next() }
    )
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Claude Code")

    let authorized = try await fixture.store.authorize(
      profileID: provisioning.profile.id,
      credential: provisioning.credential
    )

    #expect(authorized.createdAt == Date(timeIntervalSince1970: 100))
    #expect(authorized.lastConnectedAt == Date(timeIntervalSince1970: 200))
    #expect(authorized.revokedAt == nil)
    #expect(try await fixture.store.activeProfiles() == [authorized])
  }

  @Test func wrongUnknownAndRevokedProfilesArePermissionRevoked() async throws {
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0x44, count: 32)
    )
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Kimi")

    let wrongError = await permissionRevokedError {
      _ = try await fixture.store.authorize(
        profileID: provisioning.profile.id,
        credential: Data(repeating: 0x45, count: 32)
      )
    }
    let unknownError = await permissionRevokedError {
      _ = try await fixture.store.authorize(
        profileID: UUID(),
        credential: provisioning.credential
      )
    }

    try await fixture.store.revoke(profileID: provisioning.profile.id)
    let revokedError = await permissionRevokedError {
      _ = try await fixture.store.authorize(
        profileID: provisioning.profile.id,
        credential: provisioning.credential
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try encoder.encode(wrongError) == encoder.encode(unknownError))
    #expect(try encoder.encode(wrongError) == encoder.encode(revokedError))
    #expect(
      fixture.secrets.value(
        service: AgentCredentialSecurity.profileVerifierService,
        account: provisioning.profile.id.uuidString
      ) == nil
    )
    #expect(try await fixture.store.activeProfiles().isEmpty)
  }

  @Test func revocationIsRecheckedBeforeEveryCommandAuthorization() async throws {
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0x19, count: 32)
    )
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Codex")

    _ = try await fixture.store.authorize(
      profileID: provisioning.profile.id,
      credential: provisioning.credential
    )
    try await fixture.store.revoke(profileID: provisioning.profile.id)

    _ = await permissionRevokedError {
      _ = try await fixture.store.authorize(
        profileID: provisioning.profile.id,
        credential: provisioning.credential
      )
    }
  }

  @Test func revocationRemainsEffectiveWhenKeychainCleanupNeedsRetry() async throws {
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0x29, count: 32)
    )
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Codex")
    fixture.secrets.failNextDelete()

    await #expect(throws: AgentWorkspaceError.self) {
      try await fixture.store.revoke(profileID: provisioning.profile.id)
    }
    #expect(try await fixture.store.activeProfiles().isEmpty)
    _ = await permissionRevokedError {
      _ = try await fixture.store.authorize(
        profileID: provisioning.profile.id,
        credential: provisioning.credential
      )
    }

    try await fixture.store.revoke(profileID: provisioning.profile.id)
    #expect(
      fixture.secrets.value(
        service: AgentCredentialSecurity.profileVerifierService,
        account: provisioning.profile.id.uuidString
      ) == nil
    )
  }

  @Test func profilesReloadWithoutExposingOrRegeneratingCredentials() async throws {
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0x93, count: 32)
    )
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Generic CLI")
    let reloaded = AgentProfileStore(
      profilesURL: fixture.profilesURL,
      secretStore: fixture.secrets,
      randomBytes: RejectingRandomBytes(),
      now: { Date(timeIntervalSince1970: 400) }
    )

    #expect(try await reloaded.activeProfiles() == [provisioning.profile])
    #expect(
      try await reloaded.authorize(
        profileID: provisioning.profile.id,
        credential: provisioning.credential
      ).id == provisioning.profile.id
    )
  }

  @Test func legacyProfileVerifierMigratesBeforeAuthorization() async throws {
    let fixture = try ProfileFixture(
      randomBytes: Data(repeating: 0x73, count: 32)
    )
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Legacy Codex")
    let account = provisioning.profile.id.uuidString
    let verifier = try #require(
      fixture.secrets.value(
        service: AgentCredentialSecurity.profileVerifierService,
        account: account
      )
    )
    try fixture.secrets.delete(
      service: AgentCredentialSecurity.profileVerifierService,
      account: account
    )
    try fixture.secrets.write(
      verifier,
      service: AgentCredentialSecurity.legacyProfileVerifierService,
      account: account
    )

    #expect(
      try await fixture.store.authorize(
        profileID: provisioning.profile.id,
        credential: provisioning.credential
      ).id == provisioning.profile.id
    )
    #expect(
      fixture.secrets.value(
        service: AgentCredentialSecurity.profileVerifierService,
        account: account
      ) == verifier
    )
    #expect(
      fixture.secrets.value(
        service: AgentCredentialSecurity.legacyProfileVerifierService,
        account: account
      ) == verifier
    )
  }

  @Test func constantTimeComparisonHandlesEqualWrongAndDifferentLengthData() {
    let value = Data(repeating: 0xEF, count: 32)

    #expect(AgentCredentialSecurity.constantTimeEqual(value, value))
    #expect(
      !AgentCredentialSecurity.constantTimeEqual(
        value,
        Data(repeating: 0xEE, count: 32)
      )
    )
    #expect(
      !AgentCredentialSecurity.constantTimeEqual(
        value,
        Data(value.dropLast())
      )
    )
  }

  @Test @MainActor
  func successfulProvisioningRegistersAnEmptyCapabilityProfile() async throws {
    let fixture = try ProfileFixture()
    defer { fixture.remove() }
    let capabilityStore = profileCapabilityStore(root: fixture.rootURL)
    let provisions = CallCounter()
    let state = AppState(
      store: LocalStore(rootURL: fixture.rootURL),
      agentProfileStore: fixture.store,
      agentCapabilityStore: capabilityStore,
      provisionAgentProfile: { _, _ in provisions.increment() }
    )

    await state.waitUntilInitialLoad()
    await state.addAgentProfile(named: "Codex")

    let profile = try #require(await fixture.store.activeProfiles().first)
    let capabilities = try #require(
      await capabilityStore.currentState().profiles[profile.id]
    )
    #expect(provisions.value == 1)
    #expect(
      capabilities
        == AgentProfileCapabilities(
          profileID: profile.id,
          grantRevision: 0,
          allowedCapabilities: [],
          grants: []
        )
    )
    #expect(state.capabilityProfile(profile.id) == capabilities)
  }

  @Test @MainActor
  func failedProvisioningRevokesProfileAndDisconnectsHelperCredential()
    async throws
  {
    let fixture = try ProfileFixture()
    defer { fixture.remove() }
    let capabilityStore = profileCapabilityStore(root: fixture.rootURL)
    let disconnects = CallCounter()
    let state = AppState(
      store: LocalStore(rootURL: fixture.rootURL),
      agentProfileStore: fixture.store,
      agentCapabilityStore: capabilityStore,
      provisionAgentProfile: { _, _ in
        throw AgentWorkspaceError(code: .internalSaveFailure)
      },
      disconnectAgentProfile: { _ in disconnects.increment() }
    )

    await state.waitUntilInitialLoad()
    await state.addAgentProfile(named: "Failed")

    #expect(try await fixture.store.activeProfiles().isEmpty)
    #expect(fixture.secrets.entries.isEmpty)
    #expect(disconnects.value == 1)
    #expect(try await capabilityStore.currentState().profiles.isEmpty)
  }

  @Test @MainActor
  func failedCapabilityRegistrationRevokesProfileAndDisconnectsHelperCredential()
    async throws
  {
    let fixture = try ProfileFixture()
    defer { fixture.remove() }
    let capabilityStore = profileCapabilityStore(root: fixture.rootURL)
    try FileManager.default.createDirectory(
      at: fixture.rootURL.appendingPathComponent("AgentIntegrations"),
      withIntermediateDirectories: true
    )
    try Data("not-json".utf8).write(
      to: fixture.rootURL.appendingPathComponent(
        "AgentIntegrations/capabilities.json"
      )
    )
    let disconnects = CallCounter()
    let state = AppState(
      store: LocalStore(rootURL: fixture.rootURL),
      agentProfileStore: fixture.store,
      agentCapabilityStore: capabilityStore,
      provisionAgentProfile: { _, _ in },
      disconnectAgentProfile: { _ in disconnects.increment() }
    )

    await state.waitUntilInitialLoad()
    #expect(!state.isAgentWorkspaceAvailable)
    await state.addAgentProfile(named: "Unregistered")

    #expect(try await fixture.store.activeProfiles().isEmpty)
    #expect(fixture.secrets.entries.isEmpty)
    #expect(disconnects.value == 1)
  }

  @Test @MainActor
  func capabilityReplacementPublishesOnlyCurrentRevision() async throws {
    let fixture = try ProfileFixture()
    defer { fixture.remove() }
    let capabilityStore = profileCapabilityStore(root: fixture.rootURL)
    _ = try await fixture.store.create(name: "Codex")
    let state = AppState(
      store: LocalStore(rootURL: fixture.rootURL),
      agentProfileStore: fixture.store,
      agentCapabilityStore: capabilityStore,
      disconnectAgentProfile: { _ in }
    )
    await state.waitUntilInitialLoad()
    let profileID = try #require(state.agentProfiles.first?.id)
    let current = try #require(state.capabilityProfile(profileID))
    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: []
    )

    await state.updateAgentCapabilities(
      replacement,
      expectedGrantRevision: current.grantRevision
    )
    #expect(state.capabilityProfile(profileID) == replacement)

    let stale = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: replacement.grantRevision + 1,
      allowedCapabilities: [.writeNotes],
      grants: []
    )
    await state.updateAgentCapabilities(
      stale,
      expectedGrantRevision: current.grantRevision
    )
    #expect(state.capabilityProfile(profileID) == replacement)
  }

  @Test @MainActor
  func revocationRemovesEffectiveSharingWhilePersistedGrantRemains() async throws {
    let fixture = try ProfileFixture()
    defer { fixture.remove() }
    let provisioning = try await fixture.store.create(name: "Codex")
    let note = Note(title: "Shared", agentAccess: false)
    let localStore = LocalStore(rootURL: fixture.rootURL)
    try await localStore.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init()
    )
    let capabilityStore = profileCapabilityStore(root: fixture.rootURL)
    let legacyWorkspace = Workspace(
      notes: [Note(id: note.id, title: note.title, agentAccess: true)],
      selectedNoteID: note.id
    )
    _ = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [provisioning.profile.id],
      workspace: legacyWorkspace
    )
    let state = AppState(
      store: localStore,
      agentProfileStore: fixture.store,
      agentCapabilityStore: capabilityStore,
      disconnectAgentProfile: { _ in }
    )

    await state.waitUntilInitialLoad()
    #expect(
      state.profilesWithReadAccess(to: note.id).map(\.id)
        == [provisioning.profile.id]
    )
    #expect(state.isSharedWithAnyActiveProfile(note.id))

    await state.revokeAgentProfile(provisioning.profile)

    #expect(state.profilesWithReadAccess(to: note.id).isEmpty)
    #expect(!state.isSharedWithAnyActiveProfile(note.id))
    #expect(
      try await capabilityStore.currentState().profiles[provisioning.profile.id]
        != nil
    )
  }
}

private func permissionRevokedError(
  _ operation: () async throws -> Void
) async -> AgentWorkspaceError {
  do {
    try await operation()
    Issue.record("Expected permission_revoked")
    return AgentWorkspaceError(code: .internalSaveFailure)
  } catch let error as AgentWorkspaceError {
    #expect(error.code == .permissionRevoked)
    #expect(error.recoveryAction == "Reconnect this integration in Fleck Settings.")
    return error
  } catch {
    Issue.record("Unexpected error: \(error)")
    return AgentWorkspaceError(code: .internalSaveFailure)
  }
}

private struct ProfileFixture {
  let rootURL: URL
  let profilesURL: URL
  let secrets = FakeAgentSecretStore()
  let store: AgentProfileStore

  init(
    randomBytes: Data = Data(repeating: 0x5A, count: 32),
    now: @escaping @Sendable () -> Date = {
      Date(timeIntervalSince1970: 100)
    }
  ) throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    profilesURL = rootURL.appendingPathComponent("profiles.json")
    store = AgentProfileStore(
      profilesURL: profilesURL,
      secretStore: secrets,
      randomBytes: FixedRandomBytes(value: randomBytes),
      now: now
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private final class FakeAgentSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: Data] = [:]
  private var pendingDeleteFailures = 0

  var entries: [String: Data] {
    lock.withLock { storage }
  }

  func value(service: String, account: String) -> Data? {
    lock.withLock { storage[key(service: service, account: account)] }
  }

  func read(service: String, account: String) throws -> Data? {
    value(service: service, account: account)
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock {
      storage[key(service: service, account: account)] = data
    }
  }

  func delete(service: String, account: String) throws {
    try lock.withLock {
      if pendingDeleteFailures > 0 {
        pendingDeleteFailures -= 1
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }
      storage.removeValue(forKey: key(service: service, account: account))
    }
  }

  func failNextDelete() {
    lock.withLock {
      pendingDeleteFailures += 1
    }
  }

  private func key(service: String, account: String) -> String {
    "\(service)\u{0}\(account)"
  }
}

private struct FixedRandomBytes: AgentRandomBytesProviding {
  let value: Data

  func randomBytes(count: Int) throws -> Data {
    value
  }
}

private struct RejectingRandomBytes: AgentRandomBytesProviding {
  func randomBytes(count: Int) throws -> Data {
    throw AgentWorkspaceError(code: .internalSaveFailure)
  }
}

private final class DateSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Date]

  init(_ values: [Date]) {
    self.values = values
  }

  func next() -> Date {
    lock.withLock {
      if values.count == 1 {
        return values[0]
      }
      return values.removeFirst()
    }
  }
}

private func profileCapabilityStore(root: URL) -> AgentCapabilityStore {
  let directory = root.appendingPathComponent("AgentIntegrations", isDirectory: true)
  return AgentCapabilityStore(
    capabilitiesURL: directory.appendingPathComponent("capabilities.json"),
    previousCapabilitiesURL: directory.appendingPathComponent(
      "capabilities.previous.json"
    )
  )
}

private final class CallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }

  func increment() {
    lock.withLock { count += 1 }
  }
}
