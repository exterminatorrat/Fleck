import Foundation

public enum AgentEventName: String, CaseIterable, Codable, Equatable, Sendable {
  case noteCreated = "note.created"
  case noteUpdated = "note.updated"
  case taskStateChanged = "task.state_changed"
}

public enum AgentEventScope: Codable, Equatable, Sendable {
  case note(noteID: UUID)
  case folder(folderID: UUID)

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    switch keys {
    case ["note_id"]:
      self = .note(
        noteID: try Self.decodeUUID(
          from: container,
          key: "note_id",
          decoder: decoder
        )
      )
    case ["folder_id"]:
      self = .folder(
        folderID: try Self.decodeUUID(
          from: container,
          key: "folder_id",
          decoder: decoder
        )
      )
    default:
      throw agentEventDecodingError(decoder, "Scope must contain one UUID filter.")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventCodingKey.self)
    switch self {
    case .note(let noteID):
      try container.encode(noteID.uuidString.lowercased(), forKey: AgentEventCodingKey("note_id"))
    case .folder(let folderID):
      try container.encode(
        folderID.uuidString.lowercased(), forKey: AgentEventCodingKey("folder_id"))
    }
  }

  private static func decodeUUID(
    from container: KeyedDecodingContainer<AgentEventCodingKey>,
    key: String,
    decoder: Decoder
  ) throws -> UUID {
    let value = try container.decode(String.self, forKey: AgentEventCodingKey(key))
    guard
      let uuid = UUID(uuidString: value),
      uuid.uuidString.lowercased() == value.lowercased()
    else {
      throw agentEventDecodingError(decoder, "Scope UUID is invalid.")
    }
    return uuid
  }
}

public enum AgentEventChangedField: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case title
  case body
  case formatting
  case appearance
  case organization
}

public enum AgentEventOrigin: String, Codable, Equatable, Sendable {
  case local
}

public enum AgentTaskCompletionTransition: String, CaseIterable, Codable, Equatable, Sendable {
  case incompleteToComplete = "incomplete_to_complete"
  case completeToIncomplete = "complete_to_incomplete"
}

public enum AgentEventData: Codable, Equatable, Sendable {
  case noteCreated(noteID: UUID, revision: UInt64, origin: AgentEventOrigin)
  case noteUpdated(
    noteID: UUID,
    revision: UInt64,
    changedFields: [AgentEventChangedField],
    origin: AgentEventOrigin
  )
  case taskStateChanged(
    noteID: UUID,
    revision: UInt64,
    transition: AgentTaskCompletionTransition,
    origin: AgentEventOrigin
  )

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    let noteID = try Self.decodeUUID(from: container, decoder: decoder)
    let revision = try container.decode(UInt64.self, forKey: AgentEventCodingKey("revision"))
    let origin = try container.decode(AgentEventOrigin.self, forKey: AgentEventCodingKey("origin"))

    switch keys {
    case ["note_id", "revision", "origin"]:
      self = .noteCreated(noteID: noteID, revision: revision, origin: origin)
    case ["note_id", "revision", "origin", "changed_fields"]:
      let changedFields = try container.decode(
        [AgentEventChangedField].self,
        forKey: AgentEventCodingKey("changed_fields")
      )
      guard
        !changedFields.isEmpty,
        Set(changedFields).count == changedFields.count
      else {
        throw agentEventDecodingError(decoder, "Changed-field categories are invalid.")
      }
      self = .noteUpdated(
        noteID: noteID,
        revision: revision,
        changedFields: changedFields.sorted { $0.rawValue < $1.rawValue },
        origin: origin
      )
    case ["note_id", "revision", "origin", "completion_transition"]:
      self = .taskStateChanged(
        noteID: noteID,
        revision: revision,
        transition: try container.decode(
          AgentTaskCompletionTransition.self,
          forKey: AgentEventCodingKey("completion_transition")
        ),
        origin: origin
      )
    default:
      throw agentEventDecodingError(decoder, "Event data fields are invalid.")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventCodingKey.self)
    switch self {
    case .noteCreated(let noteID, let revision, let origin):
      try Self.encode(noteID, revision: revision, origin: origin, to: &container)
    case .noteUpdated(let noteID, let revision, let changedFields, let origin):
      guard
        !changedFields.isEmpty,
        Set(changedFields).count == changedFields.count
      else {
        throw agentEventEncodingError(encoder, "Changed-field categories are invalid.")
      }
      try Self.encode(noteID, revision: revision, origin: origin, to: &container)
      try container.encode(
        changedFields.sorted { $0.rawValue < $1.rawValue },
        forKey: AgentEventCodingKey("changed_fields")
      )
    case .taskStateChanged(let noteID, let revision, let transition, let origin):
      try Self.encode(noteID, revision: revision, origin: origin, to: &container)
      try container.encode(
        transition,
        forKey: AgentEventCodingKey("completion_transition")
      )
    }
  }

  var name: AgentEventName {
    switch self {
    case .noteCreated: .noteCreated
    case .noteUpdated: .noteUpdated
    case .taskStateChanged: .taskStateChanged
    }
  }

  var isValid: Bool {
    guard case .noteUpdated(_, _, let changedFields, _) = self else { return true }
    return !changedFields.isEmpty && Set(changedFields).count == changedFields.count
  }

  private static func decodeUUID(
    from container: KeyedDecodingContainer<AgentEventCodingKey>,
    decoder: Decoder
  ) throws -> UUID {
    let value = try container.decode(String.self, forKey: AgentEventCodingKey("note_id"))
    guard
      let uuid = UUID(uuidString: value),
      uuid.uuidString.lowercased() == value.lowercased()
    else {
      throw agentEventDecodingError(decoder, "Event note UUID is invalid.")
    }
    return uuid
  }

  private static func encode(
    _ noteID: UUID,
    revision: UInt64,
    origin: AgentEventOrigin,
    to container: inout KeyedEncodingContainer<AgentEventCodingKey>
  ) throws {
    try container.encode(noteID.uuidString.lowercased(), forKey: AgentEventCodingKey("note_id"))
    try container.encode(revision, forKey: AgentEventCodingKey("revision"))
    try container.encode(origin, forKey: AgentEventCodingKey("origin"))
  }
}

public struct AgentEventEnvelope: Codable, Equatable, Sendable {
  public let eventID: String
  public let name: AgentEventName
  public let timestamp: String
  public let data: AgentEventData
  public let cursor: String?

  public init(
    eventID: String,
    name: AgentEventName,
    timestamp: String,
    data: AgentEventData,
    cursor: String?
  ) throws {
    guard
      Self.isValidEventID(eventID),
      Self.isValidTimestamp(timestamp),
      data.name == name,
      data.isValid,
      cursor.map(Self.isValidCursor) ?? true
    else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: [], debugDescription: "Event envelope is invalid.")
      )
    }
    self.eventID = eventID
    self.name = name
    self.timestamp = timestamp
    self.data = data
    self.cursor = cursor
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventCodingKey.self)
    try requireAgentEventKeys(
      container.allKeys,
      expected: ["eventId", "name", "timestamp", "data", "cursor"],
      decoder: decoder
    )
    try self.init(
      eventID: container.decode(String.self, forKey: AgentEventCodingKey("eventId")),
      name: container.decode(AgentEventName.self, forKey: AgentEventCodingKey("name")),
      timestamp: container.decode(String.self, forKey: AgentEventCodingKey("timestamp")),
      data: container.decode(AgentEventData.self, forKey: AgentEventCodingKey("data")),
      cursor: container.decode(String?.self, forKey: AgentEventCodingKey("cursor"))
    )
  }

  public func encode(to encoder: Encoder) throws {
    guard
      Self.isValidEventID(eventID),
      Self.isValidTimestamp(timestamp),
      data.name == name,
      data.isValid,
      cursor.map(Self.isValidCursor) ?? true
    else {
      throw agentEventEncodingError(encoder, "Event envelope is invalid.")
    }
    var container = encoder.container(keyedBy: AgentEventCodingKey.self)
    try container.encode(eventID, forKey: AgentEventCodingKey("eventId"))
    try container.encode(name, forKey: AgentEventCodingKey("name"))
    try container.encode(timestamp, forKey: AgentEventCodingKey("timestamp"))
    try container.encode(data, forKey: AgentEventCodingKey("data"))
    try container.encode(cursor, forKey: AgentEventCodingKey("cursor"))
  }

  private static func isValidEventID(_ value: String) -> Bool {
    (1...128).contains(value.utf8.count)
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 95
      }
  }

  private static func isValidCursor(_ value: String) -> Bool {
    value.utf8.count <= 256
      && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
  }

  private static func isValidTimestamp(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard Self.hasValidTimestampShape(bytes) else { return false }
    let year = Self.integer(in: bytes, startingAt: 0, count: 4)
    let month = Self.integer(in: bytes, startingAt: 5, count: 2)
    let day = Self.integer(in: bytes, startingAt: 8, count: 2)
    let hour = Self.integer(in: bytes, startingAt: 11, count: 2)
    let minute = Self.integer(in: bytes, startingAt: 14, count: 2)
    let second = Self.integer(in: bytes, startingAt: 17, count: 2)
    guard
      year > 0,
      (1...12).contains(month),
      day <= Self.daysInMonth(month, year: year),
      day > 0,
      (0...23).contains(hour),
      (0...59).contains(minute),
      (0...59).contains(second)
    else {
      return false
    }

    var zoneStart = 19
    if bytes[zoneStart] == 0x2e {
      zoneStart = 20
      while zoneStart < bytes.count, isASCIIDigit(bytes[zoneStart]) {
        zoneStart += 1
      }
    }
    if bytes[zoneStart] != 0x5a {
      let offsetHour = Self.integer(in: bytes, startingAt: zoneStart + 1, count: 2)
      let offsetMinute = Self.integer(in: bytes, startingAt: zoneStart + 4, count: 2)
      guard
        (0...14).contains(offsetHour),
        (0...59).contains(offsetMinute),
        offsetHour < 14 || offsetMinute == 0
      else {
        return false
      }
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if formatter.date(from: value) != nil { return true }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) != nil
  }

  private static func hasValidTimestampShape(_ bytes: [UInt8]) -> Bool {
    guard (20...35).contains(bytes.count) else { return false }
    guard
      bytes[4] == 0x2d,
      bytes[7] == 0x2d,
      bytes[10] == 0x54,
      bytes[13] == 0x3a,
      bytes[16] == 0x3a,
      [0...3, 5...6, 8...9, 11...12, 14...15, 17...18]
        .allSatisfy({ $0.allSatisfy { isASCIIDigit(bytes[$0]) } })
    else {
      return false
    }

    let zoneStart: Int
    if bytes[19] == 0x2e {
      var index = 20
      while index < bytes.count, isASCIIDigit(bytes[index]), index - 20 < 9 {
        index += 1
      }
      guard index > 20 else { return false }
      zoneStart = index
    } else {
      zoneStart = 19
    }

    guard zoneStart < bytes.count else { return false }
    if bytes[zoneStart] == 0x5a {
      return zoneStart + 1 == bytes.count
    }
    guard
      bytes[zoneStart] == 0x2b || bytes[zoneStart] == 0x2d,
      zoneStart + 6 == bytes.count,
      isASCIIDigit(bytes[zoneStart + 1]),
      isASCIIDigit(bytes[zoneStart + 2]),
      bytes[zoneStart + 3] == 0x3a,
      isASCIIDigit(bytes[zoneStart + 4]),
      isASCIIDigit(bytes[zoneStart + 5])
    else {
      return false
    }
    return true
  }

  private static func isASCIIDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
  }

  private static func integer(in bytes: [UInt8], startingAt start: Int, count: Int) -> Int {
    (start..<(start + count)).reduce(into: 0) { value, index in
      value = value * 10 + Int(bytes[index] - 0x30)
    }
  }

  private static func daysInMonth(_ month: Int, year: Int) -> Int {
    switch month {
    case 2:
      return year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        ? 29
        : 28
    case 4, 6, 9, 11:
      return 30
    default:
      return 31
    }
  }
}

struct AgentEventCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int? = nil

  init(_ value: String) {
    stringValue = value
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
  }
}

func requireAgentEventKeys(
  _ keys: [AgentEventCodingKey],
  expected: Set<String>,
  decoder: Decoder
) throws {
  guard Set(keys.map(\.stringValue)) == expected else {
    throw agentEventDecodingError(decoder, "Event fields are invalid.")
  }
}

func agentEventDecodingError(_ decoder: Decoder, _ message: String) -> DecodingError {
  .dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: message))
}

func agentEventEncodingError(_ encoder: Encoder, _ message: String) -> EncodingError {
  .invalidValue(
    message,
    EncodingError.Context(codingPath: encoder.codingPath, debugDescription: message)
  )
}
