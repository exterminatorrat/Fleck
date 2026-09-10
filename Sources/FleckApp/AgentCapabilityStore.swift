import CryptoKit
import FleckCore
import Foundation

struct AgentCapabilityState: Equatable, Sendable {
  var profiles: [UUID: AgentProfileCapabilities]
  var unassignedLegacyNoteIDs: Set<UUID>

  init(
    profiles: [UUID: AgentProfileCapabilities],
    unassignedLegacyNoteIDs: Set<UUID>
  ) {
    self.profiles = profiles
    self.unassignedLegacyNoteIDs = unassignedLegacyNoteIDs
  }
}

actor AgentCapabilityStore {
  private static let schemaVersion = 2
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

  init(
    capabilitiesURL: URL? = nil,
    previousCapabilitiesURL: URL? = nil
  ) {
    let currentURL = capabilitiesURL ?? Self.defaultCapabilitiesURL()
    self.capabilitiesURL = currentURL
    self.previousCapabilitiesURL = previousCapabilitiesURL
      ?? currentURL.deletingLastPathComponent()
        .appendingPathComponent(Self.previousFileName)
  }

  func loadOrMigrate(
    activeProfileIDs: [UUID],
    workspace: Workspace
  ) throws -> AgentCapabilityState {
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

  func currentState() throws -> AgentCapabilityState {
    try loadPersistedState()
  }

  func registerEmptyProfile(_ profileID: UUID) throws -> AgentCapabilityState {
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
    _ replacements: [
      (profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)
    ]
  ) throws -> AgentCapabilityState {
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

  func replaceProfiles(
    _ replacements: [
      (profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)
    ],
    expectedGrantRevisions: [UUID: UInt64]
  ) throws -> AgentCapabilityState {
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

  func assignUnassignedLegacyNotes(
    _ noteIDs: Set<UUID>,
    to profileID: UUID,
    expectedGrantRevision: UInt64
  ) throws -> AgentCapabilityState {
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
      guard case let .note(noteID) = grant.scope else { return true }
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
      grants: retainedGrants + newGrants
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

  private var hasPersistedState: Bool {
    let fileManager = FileManager.default
    return fileManager.fileExists(atPath: capabilitiesURL.path)
      || fileManager.fileExists(atPath: previousCapabilitiesURL.path)
  }

  private func loadPersistedState() throws -> AgentCapabilityState {
    do {
      return try readState(from: capabilitiesURL)
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
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
    let data = try Data(contentsOf: url)
    let persisted = try JSONDecoder().decode(
      PersistedCapabilityDocument.self,
      from: data
    )
    guard persisted.schemaVersion == Self.schemaVersion else {
      throw CapabilityStoreDecodingError.invalid
    }
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
        let currentData = try Data(contentsOf: capabilitiesURL)
        try currentData.write(to: previousCapabilitiesURL, options: .atomic)
      }
      try data.write(to: capabilitiesURL, options: .atomic)
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
  }

  private func encode(_ state: AgentCapabilityState) throws -> Data {
    let persisted = try PersistedCapabilityDocument(
      schemaVersion: Self.schemaVersion,
      state: state
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(persisted)
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
  allowed: Set<String>
) throws {
  guard
    keys.count == allowed.count,
    Set(keys.map(\.stringValue)) == allowed
  else {
    throw CapabilityStoreDecodingError.invalid
  }
}

private struct PersistedCapabilityDocument: Codable {
  let schemaVersion: Int
  let profiles: [PersistedProfile]
  let unassignedLegacyNoteIDs: [UUID]

  init(schemaVersion: Int, state: AgentCapabilityState) throws {
    try validateCapabilityState(state)
    self.schemaVersion = schemaVersion
    self.profiles = state.profiles.values
      .sorted { $0.profileID.uuidString < $1.profileID.uuidString }
      .map(PersistedProfile.init)
    self.unassignedLegacyNoteIDs = state.unassignedLegacyNoteIDs.sorted {
      $0.uuidString < $1.uuidString
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CapabilityCodingKey.self)
    try requireExactKeys(
      container.allKeys,
      allowed: [
        "schemaVersion",
        "profiles",
        "unassignedLegacyNoteIDs",
      ]
    )
    schemaVersion = try container.decode(
      Int.self,
      forKey: CapabilityCodingKey("schemaVersion")
    )
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
    let state = AgentCapabilityState(
      profiles: Dictionary(
        uniqueKeysWithValues: publicProfiles.map { ($0.profileID, $0) }
      ),
      unassignedLegacyNoteIDs: Set(unassignedLegacyNoteIDs)
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
  }
}

private struct PersistedProfile: Codable {
  let profileID: UUID
  let grantRevision: UInt64
  let allowedCapabilities: [AgentCapability]
  let grants: [PersistedGrant]

  init(profile: AgentProfileCapabilities) {
    profileID = profile.profileID
    grantRevision = profile.grantRevision
    allowedCapabilities = profile.allowedCapabilities.sorted {
      $0.rawValue < $1.rawValue
    }
    grants = profile.grants.map(PersistedGrant.init)
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
      ]
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
      grants: grants.map { $0.makePublic() }
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
    case let .note(noteID):
      self = .note(noteID: noteID)
    case let .folderIncludingFutureNotes(folderID):
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
    case let .note(noteID):
      return .note(noteID: noteID)
    case let .folderIncludingFutureNotes(folderID):
      return .folderIncludingFutureNotes(folderID: folderID)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CapabilityCodingKey.self)
    switch self {
    case let .note(noteID):
      try container.encode("note", forKey: CapabilityCodingKey("kind"))
      try container.encode(
        noteID,
        forKey: CapabilityCodingKey("noteID")
      )
    case let .folderIncludingFutureNotes(folderID):
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
