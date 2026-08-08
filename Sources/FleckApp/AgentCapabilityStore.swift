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
    var state = try loadPersistedState()
    guard let current = state.profiles[profile.profileID] else {
      throw AgentWorkspaceError(code: .invalidPayload)
    }
    guard current.grantRevision == expectedGrantRevision else {
      throw AgentWorkspaceError(code: .revisionConflict)
    }
    guard
      current.grantRevision < UInt64.max,
      profile.grantRevision == current.grantRevision + 1
    else {
      throw AgentWorkspaceError(code: .invalidPayload)
    }

    state.profiles[profile.profileID] = profile
    try save(state)
    return state
  }

  private var hasPersistedState: Bool {
    let fileManager = FileManager.default
    return fileManager.fileExists(atPath: capabilitiesURL.path)
      || fileManager.fileExists(atPath: previousCapabilitiesURL.path)
  }

  private func loadPersistedState() throws -> AgentCapabilityState {
    if FileManager.default.fileExists(atPath: capabilitiesURL.path),
      let state = try? readState(from: capabilitiesURL)
    {
      return state
    }

    if FileManager.default.fileExists(atPath: previousCapabilitiesURL.path),
      let state = try? readState(from: previousCapabilitiesURL)
    {
      do {
        try writeCurrent(state)
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }
      return state
    }

    throw AgentWorkspaceError(code: .internalSaveFailure)
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
            allowedCapabilities: Set(AgentCapability.allCases),
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
      PersistedCapabilityState.self,
      from: data
    )
    guard persisted.schemaVersion == Self.schemaVersion else {
      throw CapabilityStoreDecodingError.invalid
    }

    let profileIDs = persisted.profiles.map(\.profileID)
    guard Set(profileIDs).count == profileIDs.count else {
      throw CapabilityStoreDecodingError.invalid
    }
    for profile in persisted.profiles {
      let grantIDs = profile.grants.map(\.id)
      guard Set(grantIDs).count == grantIDs.count else {
        throw CapabilityStoreDecodingError.invalid
      }
    }

    let unassignedIDs = persisted.unassignedLegacyNoteIDs
    guard Set(unassignedIDs).count == unassignedIDs.count else {
      throw CapabilityStoreDecodingError.invalid
    }

    return AgentCapabilityState(
      profiles: Dictionary(
        uniqueKeysWithValues: persisted.profiles.map { ($0.profileID, $0) }
      ),
      unassignedLegacyNoteIDs: Set(unassignedIDs)
    )
  }

  private func save(_ state: AgentCapabilityState) throws {
    do {
      let data = try encode(state)
      try FileManager.default.createDirectory(
        at: capabilitiesURL.deletingLastPathComponent(),
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

  private func writeCurrent(_ state: AgentCapabilityState) throws {
    let data = try encode(state)
    try FileManager.default.createDirectory(
      at: capabilitiesURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: capabilitiesURL, options: .atomic)
  }

  private func encode(_ state: AgentCapabilityState) throws -> Data {
    let persisted = PersistedCapabilityState(
      schemaVersion: Self.schemaVersion,
      profiles: state.profiles.values.sorted {
        $0.profileID.uuidString < $1.profileID.uuidString
      },
      unassignedLegacyNoteIDs: state.unassignedLegacyNoteIDs.sorted {
        $0.uuidString < $1.uuidString
      }
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

private struct PersistedCapabilityState: Codable {
  let schemaVersion: Int
  let profiles: [AgentProfileCapabilities]
  let unassignedLegacyNoteIDs: [UUID]

  init(
    schemaVersion: Int,
    profiles: [AgentProfileCapabilities],
    unassignedLegacyNoteIDs: [UUID]
  ) {
    self.schemaVersion = schemaVersion
    self.profiles = profiles
    self.unassignedLegacyNoteIDs = unassignedLegacyNoteIDs
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case profiles
    case unassignedLegacyNoteIDs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    let expectedKeys = Set(CodingKeys.allCases.map(\.stringValue))
    guard keys == expectedKeys else {
      throw CapabilityStoreDecodingError.invalid
    }
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    profiles = try container.decode(
      [AgentProfileCapabilities].self,
      forKey: .profiles
    )
    unassignedLegacyNoteIDs = try container.decode(
      [UUID].self,
      forKey: .unassignedLegacyNoteIDs
    )
  }
}

private enum CapabilityStoreDecodingError: Error {
  case invalid
}
