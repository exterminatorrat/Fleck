import CryptoKit
import FleckCore
import Foundation

struct AgentCapabilityState: Equatable, Sendable {
  var profiles: [UUID: AgentProfileCapabilities]
  var unassignedLegacyNoteIDs: Set<UUID>
  var privacyPolicy: AgentCapabilityPrivacyPolicy?

  init(
    profiles: [UUID: AgentProfileCapabilities],
    unassignedLegacyNoteIDs: Set<UUID>,
    privacyPolicy: AgentCapabilityPrivacyPolicy? = nil
  ) {
    self.profiles = profiles
    self.unassignedLegacyNoteIDs = unassignedLegacyNoteIDs
    self.privacyPolicy = privacyPolicy
  }
}

struct AgentCapabilityPrivacyPolicy: Equatable, Sendable {
  let generation: UUID
  let deniedNoteIDs: Set<UUID>
  let deniedFolderIDs: Set<UUID>
}

private final class AgentCapabilityStoreGate: @unchecked Sendable {
  static let shared = AgentCapabilityStoreGate()

  private let lock = NSLock()

  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    try lock.withLock(body)
  }
}

actor AgentCapabilityStore {
  fileprivate static let legacySchemaVersion = 2
  fileprivate static let policySchemaVersion = 3
  private static let maximumDocumentBytes = 64 * 1_024 * 1_024
  fileprivate static let maximumDeniedIDs = 65_536
  private static let currentFileName = "capabilities.json"
  private static let previousFileName = "capabilities.previous.json"
  private static let legacyCapabilities: Set<AgentCapability> = [
    .listNotes,
    .readNotes,
    .writeNotes,
    .undoChanges,
  ]

  private let capabilitiesURL: URL
  private let previousCapabilitiesURL: URL
  private let writeData: @Sendable (Data, URL) throws -> Void

  init(
    capabilitiesURL: URL? = nil,
    previousCapabilitiesURL: URL? = nil,
    writeData: (@Sendable (Data, URL) throws -> Void)? = nil
  ) {
    let currentURL = capabilitiesURL ?? Self.defaultCapabilitiesURL()
    self.capabilitiesURL = currentURL
    self.previousCapabilitiesURL =
      previousCapabilitiesURL
      ?? currentURL.deletingLastPathComponent()
      .appendingPathComponent(Self.previousFileName)
    self.writeData =
      writeData ?? { data, url in
        try data.write(to: url, options: .atomic)
      }
  }

  func loadOrMigrate(
    activeProfileIDs: [UUID],
    workspace: Workspace
  ) throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      guard !hasPersistedState else {
        return try loadPersistedState()
      }

      let state = migrate(
        activeProfileIDs: activeProfileIDs,
        workspace: workspace
      )
      try save(state)
      return state
    }
  }

  func currentState() throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      try loadPersistedState()
    }
  }

  func registerEmptyProfile(_ profileID: UUID) throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      var state = try loadPersistedState()
      guard state.profiles[profileID] == nil else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }

      state.profiles[profileID] = AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: 0,
        allowedCapabilities: [],
        grants: []
      )
      try save(state)
      return state
    }
  }

  func replaceProfile(
    _ profile: AgentProfileCapabilities,
    expectedGrantRevision: UInt64
  ) throws -> AgentCapabilityState {
    try replaceProfiles([
      (
        profile: profile,
        expectedGrantRevision: expectedGrantRevision
      )
    ])
  }

  func replaceProfiles(
    _ replacements: [(profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)]
  ) throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      var state = try loadPersistedState()
      guard !replacements.isEmpty else { return state }
      guard Set(replacements.map { $0.profile.profileID }).count == replacements.count else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }

      for replacement in replacements {
        guard let current = state.profiles[replacement.profile.profileID] else {
          throw AgentWorkspaceError(code: .invalidPayload)
        }
        guard current.grantRevision == replacement.expectedGrantRevision else {
          throw AgentWorkspaceError(code: .revisionConflict)
        }
        guard
          current.grantRevision < UInt64.max,
          replacement.profile.grantRevision == current.grantRevision + 1
        else {
          throw AgentWorkspaceError(code: .invalidPayload)
        }
      }

      for replacement in replacements {
        state.profiles[replacement.profile.profileID] = replacement.profile
      }
      do {
        try validateCapabilityState(state)
      } catch {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      try save(state)
      return state
    }
  }

  func replaceProfiles(
    _ replacements: [(profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)],
    expectedGrantRevisions: [UUID: UInt64]
  ) throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      var state = try loadPersistedState()
      guard Set(replacements.map { $0.profile.profileID }).count == replacements.count else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }

      for (profileID, expectedGrantRevision) in expectedGrantRevisions {
        guard let current = state.profiles[profileID] else {
          throw AgentWorkspaceError(code: .revisionConflict)
        }
        guard current.grantRevision == expectedGrantRevision else {
          throw AgentWorkspaceError(code: .revisionConflict)
        }
      }

      for replacement in replacements {
        guard let current = state.profiles[replacement.profile.profileID] else {
          throw AgentWorkspaceError(code: .invalidPayload)
        }
        guard
          expectedGrantRevisions[replacement.profile.profileID]
            == replacement.expectedGrantRevision,
          current.grantRevision == replacement.expectedGrantRevision
        else {
          throw AgentWorkspaceError(code: .revisionConflict)
        }
        guard
          current.grantRevision < UInt64.max,
          replacement.profile.grantRevision == current.grantRevision + 1
        else {
          throw AgentWorkspaceError(code: .invalidPayload)
        }
      }

      guard !replacements.isEmpty else { return state }
      for replacement in replacements {
        state.profiles[replacement.profile.profileID] = replacement.profile
      }
      do {
        try validateCapabilityState(state)
      } catch {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      try save(state)
      return state
    }
  }

  func assignUnassignedLegacyNotes(
    _ noteIDs: Set<UUID>,
    to profileID: UUID,
    expectedGrantRevision: UInt64
  ) throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      var state = try loadPersistedState()
      guard !noteIDs.isEmpty else { return state }
      guard let current = state.profiles[profileID] else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      guard current.grantRevision == expectedGrantRevision else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      guard noteIDs.isSubset(of: state.unassignedLegacyNoteIDs) else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      guard current.grantRevision < UInt64.max else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }

      let retainedGrants = current.grants.filter { grant in
        guard case .note(let noteID) = grant.scope else { return true }
        return !noteIDs.contains(noteID)
      }
      let newGrants = noteIDs.sorted { $0.uuidString < $1.uuidString }.map { noteID in
        AgentResourceGrant(
          scope: .note(noteID: noteID),
          authority: .write
        )
      }
      state.profiles[profileID] = AgentProfileCapabilities(
        profileID: current.profileID,
        grantRevision: current.grantRevision + 1,
        allowedCapabilities: current.allowedCapabilities,
        grants: retainedGrants + newGrants,
        allowsEventObservation: current.allowsEventObservation
      )
      state.unassignedLegacyNoteIDs.subtract(noteIDs)
      do {
        try validateCapabilityState(state)
      } catch {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      try save(state)
      return state
    }
  }

  func replacePrivacyPolicy(
    deniedNoteIDs: Set<UUID>,
    deniedFolderIDs: Set<UUID>,
    expectedGeneration: UUID?
  ) throws -> AgentCapabilityState {
    try AgentCapabilityStoreGate.shared.withLock {
      guard deniedNoteIDs.count + deniedFolderIDs.count <= Self.maximumDeniedIDs else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      var state = try loadPersistedState()
      guard state.privacyPolicy?.generation == expectedGeneration else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      if state.privacyPolicy?.deniedNoteIDs == deniedNoteIDs,
        state.privacyPolicy?.deniedFolderIDs == deniedFolderIDs
      {
        return state
      }
      if state.privacyPolicy == nil,
        deniedNoteIDs.isEmpty,
        deniedFolderIDs.isEmpty
      {
        return state
      }

      guard state.profiles.values.allSatisfy({ $0.grantRevision < UInt64.max }) else {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      let previousState = state
      var generation = UUID()
      while generation == state.privacyPolicy?.generation {
        generation = UUID()
      }
      state.privacyPolicy = AgentCapabilityPrivacyPolicy(
        generation: generation,
        deniedNoteIDs: deniedNoteIDs,
        deniedFolderIDs: deniedFolderIDs
      )
      state.profiles = state.profiles.mapValues { profile in
        AgentProfileCapabilities(
          profileID: profile.profileID,
          grantRevision: profile.grantRevision + 1,
          allowedCapabilities: profile.allowedCapabilities,
          grants: profile.grants,
          allowsEventObservation: profile.allowsEventObservation
        )
      }
      do {
        try validateCapabilityState(state)
      } catch {
        throw AgentWorkspaceError(code: .invalidPayload)
      }
      try savePrivacyPolicyChange(from: previousState, to: state)
      return state
    }
  }

  private var hasPersistedState: Bool {
    let fileManager = FileManager.default
    return fileManager.fileExists(atPath: capabilitiesURL.path)
      || fileManager.fileExists(atPath: previousCapabilitiesURL.path)
  }

  private func loadPersistedState() throws -> AgentCapabilityState {
    let state: AgentCapabilityState
    do {
      state = try readState(from: capabilitiesURL)
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
    guard
      state.privacyPolicy != nil
        || !hasPrivacyOrUnknownMarker(at: previousCapabilitiesURL)
    else {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
    return state
  }

  private func migrate(
    activeProfileIDs: [UUID],
    workspace: Workspace
  ) -> AgentCapabilityState {
    let profileIDs = Set(activeProfileIDs).sorted { $0.uuidString < $1.uuidString }
    let sharedNoteIDs = Set(
      workspace.notes
        .filter(\.agentAccess)
        .map(\.id)
    ).sorted { $0.uuidString < $1.uuidString }

    let profiles = Dictionary(
      uniqueKeysWithValues: profileIDs.map { profileID in
        let grants = sharedNoteIDs.map { noteID in
          AgentResourceGrant(
            id: Self.legacyGrantID(profileID: profileID, noteID: noteID),
            scope: .note(noteID: noteID),
            authority: .write
          )
        }
        return (
          profileID,
          AgentProfileCapabilities(
            profileID: profileID,
            grantRevision: 1,
            allowedCapabilities: Self.legacyCapabilities,
            grants: grants
          )
        )
      }
    )

    return AgentCapabilityState(
      profiles: profiles,
      unassignedLegacyNoteIDs: profileIDs.isEmpty
        ? Set(sharedNoteIDs)
        : []
    )
  }

  private func readState(from url: URL) throws -> AgentCapabilityState {
    let data = try readDocumentData(from: url)
    let persisted = try JSONDecoder().decode(
      PersistedCapabilityDocument.self,
      from: data
    )
    do {
      return try persisted.makeState()
    } catch {
      throw CapabilityStoreDecodingError.invalid
    }
  }

  private func save(_ state: AgentCapabilityState) throws {
    do {
      try validateCapabilityState(state)
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }

    do {
      let data = try encode(state)
      try FileManager.default.createDirectory(
        at: capabilitiesURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.createDirectory(
        at: previousCapabilitiesURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: capabilitiesURL.path) {
        let currentData = try readDocumentData(from: capabilitiesURL)
        try writePersistedData(currentData, to: previousCapabilitiesURL)
      }
      try writePersistedData(data, to: capabilitiesURL)
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
  }

  private func savePrivacyPolicyChange(
    from previousState: AgentCapabilityState,
    to state: AgentCapabilityState
  ) throws {
    do {
      try validateCapabilityState(state)
      guard let policy = state.privacyPolicy else {
        throw CapabilityStoreValidationError.invalid
      }
      let oldPolicy = previousState.privacyPolicy
      let backupNoteIDs = policy.deniedNoteIDs.union(oldPolicy?.deniedNoteIDs ?? [])
      let backupFolderIDs = policy.deniedFolderIDs.union(oldPolicy?.deniedFolderIDs ?? [])
      var backupState = state
      backupState.privacyPolicy =
        backupNoteIDs.count + backupFolderIDs.count <= Self.maximumDeniedIDs
        ? AgentCapabilityPrivacyPolicy(
          generation: policy.generation,
          deniedNoteIDs: backupNoteIDs,
          deniedFolderIDs: backupFolderIDs
        )
        : policy
      try FileManager.default.createDirectory(
        at: capabilitiesURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.createDirectory(
        at: previousCapabilitiesURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let backupData = try encode(backupState)
      let currentData = try encode(state)
      try writePersistedData(backupData, to: previousCapabilitiesURL)
      try writePersistedData(currentData, to: capabilitiesURL)
    } catch let error as AgentWorkspaceError {
      throw error
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
  }

  private func encode(_ state: AgentCapabilityState) throws -> Data {
    let persisted = try PersistedCapabilityDocument(state: state)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(persisted)
    guard data.count <= Self.maximumDocumentBytes else {
      throw CapabilityStoreValidationError.invalid
    }
    return data
  }

  private func readDocumentData(from url: URL) throws -> Data {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard
      let fileSize = attributes[.size] as? NSNumber,
      fileSize.uint64Value <= UInt64(Self.maximumDocumentBytes)
    else {
      throw CapabilityStoreDecodingError.invalid
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while data.count <= Self.maximumDocumentBytes {
      let remaining = Self.maximumDocumentBytes + 1 - data.count
      let chunk = try handle.read(upToCount: min(remaining, 64 * 1_024)) ?? Data()
      guard !chunk.isEmpty else { break }
      data.append(chunk)
    }
    guard data.count <= Self.maximumDocumentBytes else {
      throw CapabilityStoreDecodingError.invalid
    }
    return data
  }

  private func writePersistedData(_ data: Data, to url: URL) throws {
    guard data.count <= Self.maximumDocumentBytes else {
      throw CapabilityStoreValidationError.invalid
    }
    do {
      try writeData(data, url)
    } catch {
      guard (try? readDocumentData(from: url)) == data else { throw error }
    }
  }

  private func hasPrivacyOrUnknownMarker(at url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    guard let data = try? readDocumentData(from: url) else {
      if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let fileSize = attributes[.size] as? NSNumber
      {
        return fileSize.uint64Value > UInt64(Self.maximumDocumentBytes)
      }
      return false
    }
    guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    let schemaVersion = document["schemaVersion"] as? Int
    return document.keys.contains("privacyPolicy")
      || schemaVersion != Self.legacySchemaVersion
  }

  private static func legacyGrantID(profileID: UUID, noteID: UUID) -> UUID {
    let seed = Data(
      "fleck.legacy-note-grant.\(profileID.uuidString).\(noteID.uuidString)".utf8
    )
    let digest = SHA256.hash(data: seed)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    let characters = Array(hex)
    let uuid = [
      String(characters[0..<8]),
      String(characters[8..<12]),
      String(characters[12..<16]),
      String(characters[16..<20]),
      String(characters[20..<32]),
    ].joined(separator: "-")
    return UUID(uuidString: uuid)!
  }

  private static func defaultCapabilitiesURL() -> URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appendingPathComponent(
      FleckProductPaths.canonicalDirectoryName,
      isDirectory: true
    )
    .appendingPathComponent("AgentIntegrations", isDirectory: true)
    .appendingPathComponent(Self.currentFileName)
  }
}

private struct CapabilityCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int? = nil

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
  }
}

private func requireExactKeys(
  _ keys: [CapabilityCodingKey],
  allowed: Set<String>,
  optional: Set<String> = []
) throws {
  let actual = Set(keys.map(\.stringValue))
  guard
    keys.count == actual.count,
    allowed.isSubset(of: actual),
    actual.isSubset(of: allowed.union(optional))
  else {
    throw CapabilityStoreDecodingError.invalid
  }
}

private struct PersistedCapabilityDocument: Codable {
  let schemaVersion: Int
  let profiles: [PersistedProfile]
  let unassignedLegacyNoteIDs: [UUID]
  let privacyPolicy: PersistedPrivacyPolicy?

  init(state: AgentCapabilityState) throws {
    try validateCapabilityState(state)
    schemaVersion =
      state.privacyPolicy == nil
      ? AgentCapabilityStore.legacySchemaVersion
      : AgentCapabilityStore.policySchemaVersion
    self.profiles = state.profiles.values
      .sorted { $0.profileID.uuidString < $1.profileID.uuidString }
      .map(PersistedProfile.init)
    self.unassignedLegacyNoteIDs = state.unassignedLegacyNoteIDs.sorted {
      $0.uuidString < $1.uuidString
    }
    privacyPolicy = state.privacyPolicy.map(PersistedPrivacyPolicy.init)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CapabilityCodingKey.self)
    schemaVersion = try container.decode(
      Int.self,
      forKey: CapabilityCodingKey("schemaVersion")
    )
    let baseKeys: Set<String> = [
      "schemaVersion",
      "profiles",
      "unassignedLegacyNoteIDs",
    ]
    switch schemaVersion {
    case AgentCapabilityStore.legacySchemaVersion:
      try requireExactKeys(container.allKeys, allowed: baseKeys)
      privacyPolicy = nil
    case AgentCapabilityStore.policySchemaVersion:
      try requireExactKeys(container.allKeys, allowed: baseKeys.union(["privacyPolicy"]))
      privacyPolicy = try container.decode(
        PersistedPrivacyPolicy.self,
        forKey: CapabilityCodingKey("privacyPolicy")
      )
    default:
      throw CapabilityStoreDecodingError.invalid
    }
    profiles = try container.decode(
      [PersistedProfile].self,
      forKey: CapabilityCodingKey("profiles")
    )
    unassignedLegacyNoteIDs = try container.decode(
      [UUID].self,
      forKey: CapabilityCodingKey("unassignedLegacyNoteIDs")
    )
  }

  func makeState() throws -> AgentCapabilityState {
    let profileIDs = profiles.map(\.profileID)
    guard Set(profileIDs).count == profileIDs.count else {
      throw CapabilityStoreDecodingError.invalid
    }

    guard
      Set(unassignedLegacyNoteIDs).count == unassignedLegacyNoteIDs.count
    else {
      throw CapabilityStoreDecodingError.invalid
    }

    let publicProfiles = try profiles.map { try $0.makePublic() }
    let publicPolicy = try privacyPolicy?.makePublic()
    guard
      (schemaVersion == AgentCapabilityStore.legacySchemaVersion && publicPolicy == nil)
        || (schemaVersion == AgentCapabilityStore.policySchemaVersion && publicPolicy != nil)
    else {
      throw CapabilityStoreDecodingError.invalid
    }
    let state = AgentCapabilityState(
      profiles: Dictionary(
        uniqueKeysWithValues: publicProfiles.map { ($0.profileID, $0) }
      ),
      unassignedLegacyNoteIDs: Set(unassignedLegacyNoteIDs),
      privacyPolicy: publicPolicy
    )
    try validateCapabilityState(state)
    return state
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CapabilityCodingKey.self)
    try container.encode(
      schemaVersion,
      forKey: CapabilityCodingKey("schemaVersion")
    )
    try container.encode(
      profiles,
      forKey: CapabilityCodingKey("profiles")
    )
    try container.encode(
      unassignedLegacyNoteIDs,
      forKey: CapabilityCodingKey("unassignedLegacyNoteIDs")
    )
    if let privacyPolicy {
      try container.encode(
        privacyPolicy,
        forKey: CapabilityCodingKey("privacyPolicy")
      )
    }
  }
}

private struct PersistedPrivacyPolicy: Codable {
  let generation: UUID
  let deniedNoteIDs: [UUID]
  let deniedFolderIDs: [UUID]

  init(_ policy: AgentCapabilityPrivacyPolicy) {
    generation = policy.generation
    deniedNoteIDs = policy.deniedNoteIDs.sorted { $0.uuidString < $1.uuidString }
    deniedFolderIDs = policy.deniedFolderIDs.sorted { $0.uuidString < $1.uuidString }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CapabilityCodingKey.self)
    try requireExactKeys(
      container.allKeys,
      allowed: ["generation", "deniedNoteIDs", "deniedFolderIDs"]
    )
    generation = try container.decode(
      UUID.self,
      forKey: CapabilityCodingKey("generation")
    )
    deniedNoteIDs = try container.decode(
      [UUID].self,
      forKey: CapabilityCodingKey("deniedNoteIDs")
    )
    deniedFolderIDs = try container.decode(
      [UUID].self,
      forKey: CapabilityCodingKey("deniedFolderIDs")
    )
  }

  func makePublic() throws -> AgentCapabilityPrivacyPolicy {
    guard
      Set(deniedNoteIDs).count == deniedNoteIDs.count,
      Set(deniedFolderIDs).count == deniedFolderIDs.count,
      deniedNoteIDs.count + deniedFolderIDs.count
        <= AgentCapabilityStore.maximumDeniedIDs
    else {
      throw CapabilityStoreDecodingError.invalid
    }
    return AgentCapabilityPrivacyPolicy(
      generation: generation,
      deniedNoteIDs: Set(deniedNoteIDs),
      deniedFolderIDs: Set(deniedFolderIDs)
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CapabilityCodingKey.self)
    try container.encode(generation, forKey: CapabilityCodingKey("generation"))
    try container.encode(
      deniedNoteIDs,
      forKey: CapabilityCodingKey("deniedNoteIDs")
    )
    try container.encode(
      deniedFolderIDs,
      forKey: CapabilityCodingKey("deniedFolderIDs")
    )
  }
}

private struct PersistedProfile: Codable {
  let profileID: UUID
  let grantRevision: UInt64
  let allowedCapabilities: [AgentCapability]
  let grants: [PersistedGrant]
  let allowsEventObservation: Bool

  init(profile: AgentProfileCapabilities) {
    profileID = profile.profileID
    grantRevision = profile.grantRevision
    allowedCapabilities = profile.allowedCapabilities.sorted {
      $0.rawValue < $1.rawValue
    }
    grants = profile.grants.map(PersistedGrant.init)
    allowsEventObservation = profile.allowsEventObservation
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CapabilityCodingKey.self)
    try requireExactKeys(
      container.allKeys,
      allowed: [
        "profileID",
        "grantRevision",
        "allowedCapabilities",
        "grants",
      ],
      optional: ["allowsEventObservation"]
    )
    profileID = try container.decode(
      UUID.self,
      forKey: CapabilityCodingKey("profileID")
    )
    grantRevision = try container.decode(
      UInt64.self,
      forKey: CapabilityCodingKey("grantRevision")
    )
    allowedCapabilities = try container.decode(
      [AgentCapability].self,
      forKey: CapabilityCodingKey("allowedCapabilities")
    )
    grants = try container.decode(
      [PersistedGrant].self,
      forKey: CapabilityCodingKey("grants")
    )
    let observationKey = CapabilityCodingKey("allowsEventObservation")
    allowsEventObservation =
      container.contains(observationKey)
      ? try container.decode(Bool.self, forKey: observationKey)
      : false
  }

  func makePublic() throws -> AgentProfileCapabilities {
    guard
      Set(allowedCapabilities).count == allowedCapabilities.count
    else {
      throw CapabilityStoreDecodingError.invalid
    }

    let grantIDs = grants.map(\.id)
    guard Set(grantIDs).count == grantIDs.count else {
      throw CapabilityStoreDecodingError.invalid
    }

    return AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: grantRevision,
      allowedCapabilities: Set(allowedCapabilities),
      grants: grants.map { $0.makePublic() },
      allowsEventObservation: allowsEventObservation
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CapabilityCodingKey.self)
    try container.encode(
      profileID,
      forKey: CapabilityCodingKey("profileID")
    )
    try container.encode(
      grantRevision,
      forKey: CapabilityCodingKey("grantRevision")
    )
    try container.encode(
      allowedCapabilities,
      forKey: CapabilityCodingKey("allowedCapabilities")
    )
    try container.encode(
      grants,
      forKey: CapabilityCodingKey("grants")
    )
    if allowsEventObservation {
      try container.encode(
        true,
        forKey: CapabilityCodingKey("allowsEventObservation")
      )
    }
  }
}

private struct PersistedGrant: Codable {
  let id: UUID
  let scope: PersistedScope
  let authority: AgentAuthority

  init(grant: AgentResourceGrant) {
    id = grant.id
    scope = PersistedScope(scope: grant.scope)
    authority = grant.authority
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CapabilityCodingKey.self)
    try requireExactKeys(
      container.allKeys,
      allowed: ["id", "scope", "authority"]
    )
    id = try container.decode(
      UUID.self,
      forKey: CapabilityCodingKey("id")
    )
    scope = try container.decode(
      PersistedScope.self,
      forKey: CapabilityCodingKey("scope")
    )
    authority = try container.decode(
      AgentAuthority.self,
      forKey: CapabilityCodingKey("authority")
    )
  }

  func makePublic() -> AgentResourceGrant {
    AgentResourceGrant(
      id: id,
      scope: scope.makePublic(),
      authority: authority
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CapabilityCodingKey.self)
    try container.encode(id, forKey: CapabilityCodingKey("id"))
    try container.encode(scope, forKey: CapabilityCodingKey("scope"))
    try container.encode(
      authority,
      forKey: CapabilityCodingKey("authority")
    )
  }
}

private enum PersistedScope: Codable {
  case note(noteID: UUID)
  case folderIncludingFutureNotes(folderID: UUID)

  init(scope: AgentGrantScope) {
    switch scope {
    case .note(let noteID):
      self = .note(noteID: noteID)
    case .folderIncludingFutureNotes(let folderID):
      self = .folderIncludingFutureNotes(folderID: folderID)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CapabilityCodingKey.self)
    let kind = try container.decode(
      String.self,
      forKey: CapabilityCodingKey("kind")
    )

    switch kind {
    case "note":
      try requireExactKeys(container.allKeys, allowed: ["kind", "noteID"])
      self = .note(
        noteID: try container.decode(
          UUID.self,
          forKey: CapabilityCodingKey("noteID")
        )
      )
    case "folderIncludingFutureNotes":
      try requireExactKeys(
        container.allKeys,
        allowed: ["kind", "folderID"]
      )
      self = .folderIncludingFutureNotes(
        folderID: try container.decode(
          UUID.self,
          forKey: CapabilityCodingKey("folderID")
        )
      )
    default:
      throw CapabilityStoreDecodingError.invalid
    }
  }

  func makePublic() -> AgentGrantScope {
    switch self {
    case .note(let noteID):
      return .note(noteID: noteID)
    case .folderIncludingFutureNotes(let folderID):
      return .folderIncludingFutureNotes(folderID: folderID)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CapabilityCodingKey.self)
    switch self {
    case .note(let noteID):
      try container.encode("note", forKey: CapabilityCodingKey("kind"))
      try container.encode(
        noteID,
        forKey: CapabilityCodingKey("noteID")
      )
    case .folderIncludingFutureNotes(let folderID):
      try container.encode(
        "folderIncludingFutureNotes",
        forKey: CapabilityCodingKey("kind")
      )
      try container.encode(
        folderID,
        forKey: CapabilityCodingKey("folderID")
      )
    }
  }
}

private func validateCapabilityState(_ state: AgentCapabilityState) throws {
  if let policy = state.privacyPolicy {
    guard
      policy.deniedNoteIDs.count + policy.deniedFolderIDs.count
        <= AgentCapabilityStore.maximumDeniedIDs
    else {
      throw CapabilityStoreValidationError.invalid
    }
  }
  let profiles = Array(state.profiles.values)
  let profileIDs = profiles.map(\.profileID)
  guard Set(profileIDs).count == profileIDs.count else {
    throw CapabilityStoreValidationError.invalid
  }

  for (profileID, profile) in state.profiles {
    guard profileID == profile.profileID else {
      throw CapabilityStoreValidationError.invalid
    }
    let grantIDs = profile.grants.map(\.id)
    guard Set(grantIDs).count == grantIDs.count else {
      throw CapabilityStoreValidationError.invalid
    }
  }
}

private enum CapabilityStoreDecodingError: Error {
  case invalid
}

private enum CapabilityStoreValidationError: Error {
  case invalid
}
