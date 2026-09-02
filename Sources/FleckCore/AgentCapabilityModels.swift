import Foundation

public enum AgentCapability: String, Codable, CaseIterable, Hashable, Sendable {
  case listNotes = "notes.list"
  case readNotes = "notes.read"
  case writeNotes = "notes.write"
  case undoChanges = "changes.undo"
}

public enum AgentAuthority: String, Codable, CaseIterable, Sendable {
  case read
  case propose
  case write

  public func allows(_ required: AgentAuthority) -> Bool {
    switch self {
    case .read:
      return required == .read
    case .propose:
      return required == .read || required == .propose
    case .write:
      return true
    }
  }
}

public enum AgentGrantScope: Codable, Equatable, Sendable {
  case note(noteID: UUID)
  case folderIncludingFutureNotes(folderID: UUID)

  private enum CodingKeys: String, CodingKey {
    case kind
    case noteID
    case folderID
  }

  private enum Kind: String, Codable {
    case note
    case folderIncludingFutureNotes
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .note:
      self = .note(noteID: try container.decode(UUID.self, forKey: .noteID))
    case .folderIncludingFutureNotes:
      self = .folderIncludingFutureNotes(
        folderID: try container.decode(UUID.self, forKey: .folderID)
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .note(noteID):
      try container.encode(Kind.note, forKey: .kind)
      try container.encode(noteID, forKey: .noteID)
    case let .folderIncludingFutureNotes(folderID):
      try container.encode(Kind.folderIncludingFutureNotes, forKey: .kind)
      try container.encode(folderID, forKey: .folderID)
    }
  }
}

public struct AgentResourceGrant: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let scope: AgentGrantScope
  public let authority: AgentAuthority

  public init(
    id: UUID = UUID(),
    scope: AgentGrantScope,
    authority: AgentAuthority
  ) {
    self.id = id
    self.scope = scope
    self.authority = authority
  }
}

public struct AgentProfileCapabilities: Codable, Equatable, Sendable {
  public let profileID: UUID
  public let grantRevision: UInt64
  public let allowedCapabilities: Set<AgentCapability>
  public let grants: [AgentResourceGrant]

  public init(
    profileID: UUID,
    grantRevision: UInt64,
    allowedCapabilities: Set<AgentCapability>,
    grants: [AgentResourceGrant]
  ) {
    self.profileID = profileID
    self.grantRevision = grantRevision
    self.allowedCapabilities = allowedCapabilities
    self.grants = Self.sortedGrants(grants)
  }

  private enum CodingKeys: String, CodingKey {
    case profileID
    case grantRevision
    case allowedCapabilities
    case grants
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    profileID = try container.decode(UUID.self, forKey: .profileID)
    grantRevision = try container.decode(UInt64.self, forKey: .grantRevision)
    allowedCapabilities = Set(
      try container.decode([AgentCapability].self, forKey: .allowedCapabilities)
    )
    grants = Self.sortedGrants(
      try container.decode([AgentResourceGrant].self, forKey: .grants)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(profileID, forKey: .profileID)
    try container.encode(grantRevision, forKey: .grantRevision)
    try container.encode(
      allowedCapabilities.sorted { $0.rawValue < $1.rawValue },
      forKey: .allowedCapabilities
    )
    try container.encode(Self.sortedGrants(grants), forKey: .grants)
  }

  private static func sortedGrants(
    _ grants: [AgentResourceGrant]
  ) -> [AgentResourceGrant] {
    grants.sorted { lhs, rhs in
      let lhsScope = scopeSortKey(lhs.scope)
      let rhsScope = scopeSortKey(rhs.scope)
      if lhsScope.kind != rhsScope.kind {
        return lhsScope.kind < rhsScope.kind
      }
      if lhsScope.targetID != rhsScope.targetID {
        return lhsScope.targetID < rhsScope.targetID
      }
      let lhsAuthority = authoritySortKey(lhs.authority)
      let rhsAuthority = authoritySortKey(rhs.authority)
      if lhsAuthority != rhsAuthority {
        return lhsAuthority < rhsAuthority
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private static func scopeSortKey(
    _ scope: AgentGrantScope
  ) -> (kind: Int, targetID: String) {
    switch scope {
    case let .note(noteID):
      return (0, noteID.uuidString)
    case let .folderIncludingFutureNotes(folderID):
      return (1, folderID.uuidString)
    }
  }

  private static func authoritySortKey(_ authority: AgentAuthority) -> Int {
    switch authority {
    case .read:
      return 0
    case .propose:
      return 1
    case .write:
      return 2
    }
  }
}

public struct AgentCapabilitySummary: Codable, Equatable, Sendable {
  public let grantRevision: UInt64
  public let availableCapabilities: Set<AgentCapability>

  public init(
    grantRevision: UInt64,
    availableCapabilities: Set<AgentCapability>
  ) {
    self.grantRevision = grantRevision
    self.availableCapabilities = availableCapabilities
  }

  private enum CodingKeys: String, CodingKey {
    case grantRevision
    case availableCapabilities
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    grantRevision = try container.decode(UInt64.self, forKey: .grantRevision)
    availableCapabilities = Set(
      try container.decode([AgentCapability].self, forKey: .availableCapabilities)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(grantRevision, forKey: .grantRevision)
    try container.encode(
      availableCapabilities.sorted { $0.rawValue < $1.rawValue },
      forKey: .availableCapabilities
    )
  }
}

public struct AgentAuthorizationSnapshot: Equatable, Sendable {
  public let profileID: UUID
  public let grantRevision: UInt64
  public let availableCapabilities: Set<AgentCapability>
  public let readableNoteIDs: Set<UUID>
  public let proposableNoteIDs: Set<UUID>
  public let writableNoteIDs: Set<UUID>

  public init(
    profileID: UUID,
    grantRevision: UInt64,
    availableCapabilities: Set<AgentCapability>,
    readableNoteIDs: Set<UUID>,
    proposableNoteIDs: Set<UUID>,
    writableNoteIDs: Set<UUID>
  ) {
    self.profileID = profileID
    self.grantRevision = grantRevision
    self.availableCapabilities = availableCapabilities
    self.readableNoteIDs = readableNoteIDs
    self.proposableNoteIDs = proposableNoteIDs
    self.writableNoteIDs = writableNoteIDs
  }
}
