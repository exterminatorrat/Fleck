import Foundation
import FleckCore

struct AgentIntegrationProfile: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let displayName: String
  let createdAt: Date
  let lastConnectedAt: Date?
  let revokedAt: Date?

  var isRevoked: Bool {
    revokedAt != nil
  }
}

struct AgentProfileProvisioning: Equatable, Sendable {
  let profile: AgentIntegrationProfile
  let credential: Data
}

actor AgentProfileStore {
  private let profilesURL: URL
  private let secretStore: any AgentSecretStoring
  private let randomBytes: any AgentRandomBytesProviding
  private let now: @Sendable () -> Date

  init(
    profilesURL: URL? = nil,
    secretStore: any AgentSecretStoring = AgentKeychainSecretStore(),
    randomBytes: any AgentRandomBytesProviding = AgentSystemRandomBytesProvider(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.profilesURL = profilesURL ?? Self.defaultProfilesURL()
    self.secretStore = secretStore
    self.randomBytes = randomBytes
    self.now = now
  }

  func create(name: String) async throws -> AgentProfileProvisioning {
    let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...80).contains(displayName.count) else {
      throw AgentWorkspaceError(
        code: .invalidPayload,
        recoveryAction: "Use a name between 1 and 80 characters."
      )
    }

    let credential: Data
    do {
      credential = try randomBytes.randomBytes(
        count: AgentCredentialSecurity.secretByteCount
      )
    } catch let error as AgentWorkspaceError {
      throw error
    } catch {
      throw AgentCredentialSecurity.internalFailure
    }
    guard credential.count == AgentCredentialSecurity.secretByteCount else {
      throw AgentCredentialSecurity.internalFailure
    }

    var profiles = try loadProfiles()
    let profile = AgentIntegrationProfile(
      id: UUID(),
      displayName: displayName,
      createdAt: now(),
      lastConnectedAt: nil,
      revokedAt: nil
    )
    let account = profile.id.uuidString
    do {
      try verifierStore.write(
        AgentCredentialSecurity.sha256(credential),
        account: account
      )
      profiles.append(profile)
      try saveProfiles(profiles)
    } catch {
      try? secretStore.delete(
        service: AgentCredentialSecurity.profileVerifierService,
        account: account
      )
      if let agentError = error as? AgentWorkspaceError {
        throw agentError
      }
      throw AgentCredentialSecurity.internalFailure
    }
    return AgentProfileProvisioning(profile: profile, credential: credential)
  }

  func authorize(
    profileID: UUID,
    credential: Data
  ) async throws -> AgentIntegrationProfile {
    var profiles: [AgentIntegrationProfile]
    do {
      profiles = try loadProfiles()
    } catch {
      throw AgentCredentialSecurity.internalFailure
    }
    guard
      let index = profiles.firstIndex(where: { $0.id == profileID }),
      profiles[index].revokedAt == nil
    else {
      throw AgentCredentialSecurity.permissionRevokedError
    }
    let storedVerifier: Data
    do {
      guard
        let value = try verifierStore.readOrMigrate(
          account: profileID.uuidString
        )
      else {
        throw AgentCredentialSecurity.permissionRevokedError
      }
      storedVerifier = value
    } catch let error as AgentWorkspaceError {
      throw error
    } catch {
      throw AgentCredentialSecurity.internalFailure
    }
    guard
      AgentCredentialSecurity.constantTimeEqual(
        storedVerifier,
        AgentCredentialSecurity.sha256(credential)
      )
    else {
      throw AgentCredentialSecurity.permissionRevokedError
    }

    let profile = profiles[index]
    let connected = AgentIntegrationProfile(
      id: profile.id,
      displayName: profile.displayName,
      createdAt: profile.createdAt,
      lastConnectedAt: now(),
      revokedAt: nil
    )
    profiles[index] = connected
    do {
      try saveProfiles(profiles)
    } catch {
      throw AgentCredentialSecurity.internalFailure
    }
    return connected
  }

  func revoke(profileID: UUID) async throws {
    var profiles = try loadProfiles()
    guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
      throw AgentCredentialSecurity.permissionRevokedError
    }
    let profile = profiles[index]
    if profile.revokedAt == nil {
      profiles[index] = AgentIntegrationProfile(
        id: profile.id,
        displayName: profile.displayName,
        createdAt: profile.createdAt,
        lastConnectedAt: profile.lastConnectedAt,
        revokedAt: now()
      )
      try saveProfiles(profiles)
    }
    try secretStore.delete(
      service: AgentCredentialSecurity.profileVerifierService,
      account: profileID.uuidString
    )
  }

  func activeProfiles() async throws -> [AgentIntegrationProfile] {
    try loadProfiles()
      .filter { !$0.isRevoked }
      .sorted {
        if $0.createdAt != $1.createdAt {
          return $0.createdAt < $1.createdAt
        }
        return $0.id.uuidString < $1.id.uuidString
      }
  }

  private var verifierStore: MigratingKeychainDataStore {
    MigratingKeychainDataStore(
      store: secretStore,
      canonicalService: AgentCredentialSecurity.profileVerifierService,
      legacyServices: [
        AgentCredentialSecurity.legacyProfileVerifierService
      ]
    )
  }

  private func loadProfiles() throws -> [AgentIntegrationProfile] {
    guard FileManager.default.fileExists(atPath: profilesURL.path) else {
      return []
    }
    do {
      return try JSONDecoder().decode(
        [AgentIntegrationProfile].self,
        from: Data(contentsOf: profilesURL)
      )
    } catch {
      throw AgentCredentialSecurity.internalFailure
    }
  }

  private func saveProfiles(_ profiles: [AgentIntegrationProfile]) throws {
    do {
      try FileManager.default.createDirectory(
        at: profilesURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(profiles).write(to: profilesURL, options: .atomic)
    } catch {
      throw AgentCredentialSecurity.internalFailure
    }
  }

  private static func defaultProfilesURL() -> URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appendingPathComponent(
      FleckProductPaths.canonicalDirectoryName,
      isDirectory: true
    )
    .appendingPathComponent("AgentIntegrations", isDirectory: true)
    .appendingPathComponent("profiles.json")
  }
}
