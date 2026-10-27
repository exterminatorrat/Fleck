import CryptoKit
import Foundation

public enum AgentEventProvenance: String, Codable, Equatable, Sendable {
  case local
  case integration
  case uncertain
}

public struct AgentEventJournalRecord: Codable, Equatable, Sendable {
  public let eventID: UUID
  public let sequence: UInt64
  public let noteID: UUID
  public let revision: UInt64
  public let occurredAt: Date
  public let eventName: AgentEventName
  public let changedFields: [AgentEventChangedField]?
  public let completionTransition: AgentTaskCompletionTransition?
  public let priorFolderID: UUID?
  public let currentFolderID: UUID?
  public let provenance: AgentEventProvenance

  init(
    eventID: UUID,
    sequence: UInt64,
    noteID: UUID,
    revision: UInt64,
    occurredAt: Date,
    eventName: AgentEventName,
    changedFields: [AgentEventChangedField]?,
    completionTransition: AgentTaskCompletionTransition?,
    priorFolderID: UUID?,
    currentFolderID: UUID?,
    provenance: AgentEventProvenance
  ) {
    self.eventID = eventID
    self.sequence = sequence
    self.noteID = noteID
    self.revision = revision
    self.occurredAt = occurredAt
    self.eventName = eventName
    self.changedFields = changedFields
    self.completionTransition = completionTransition
    self.priorFolderID = priorFolderID
    self.currentFolderID = currentFolderID
    self.provenance = provenance
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventJournalCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    let required: Set<String> = [
      "eventID", "sequence", "noteID", "revision", "occurredAt", "eventName",
      "provenance",
    ]
    let optional: Set<String> = [
      "changedFields", "completionTransition", "priorFolderID", "currentFolderID",
    ]
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
      throw agentEventJournalDecodingError(decoder)
    }

    eventID = try container.decode(UUID.self, forKey: .eventID)
    sequence = try container.decode(UInt64.self, forKey: .sequence)
    noteID = try container.decode(UUID.self, forKey: .noteID)
    revision = try container.decode(UInt64.self, forKey: .revision)
    occurredAt = try container.decode(Date.self, forKey: .occurredAt)
    eventName = try container.decode(AgentEventName.self, forKey: .eventName)
    provenance = try container.decode(AgentEventProvenance.self, forKey: .provenance)
    changedFields = try container.decodeOptional(
      [AgentEventChangedField].self, forKey: .changedFields)
    completionTransition = try container.decodeOptional(
      AgentTaskCompletionTransition.self,
      forKey: .completionTransition
    )
    priorFolderID = try container.decodeOptional(UUID.self, forKey: .priorFolderID)
    currentFolderID = try container.decodeOptional(UUID.self, forKey: .currentFolderID)
    try validate()
  }

  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(eventID, forKey: .eventID)
    try container.encode(sequence, forKey: .sequence)
    try container.encode(noteID, forKey: .noteID)
    try container.encode(revision, forKey: .revision)
    try container.encode(occurredAt, forKey: .occurredAt)
    try container.encode(eventName, forKey: .eventName)
    try container.encodeIfPresent(changedFields, forKey: .changedFields)
    try container.encodeIfPresent(completionTransition, forKey: .completionTransition)
    try container.encodeIfPresent(priorFolderID, forKey: .priorFolderID)
    try container.encodeIfPresent(currentFolderID, forKey: .currentFolderID)
    try container.encode(provenance, forKey: .provenance)
  }

  fileprivate func validate() throws {
    guard sequence > 0, occurredAt.timeIntervalSince1970.isFinite else {
      throw AgentEventJournalError.invalidData
    }
    if let changedFields {
      guard
        !changedFields.isEmpty,
        Set(changedFields).count == changedFields.count,
        changedFields == changedFields.sorted(by: { $0.rawValue < $1.rawValue })
      else {
        throw AgentEventJournalError.invalidData
      }
    }
    switch eventName {
    case .noteCreated:
      guard changedFields == nil, completionTransition == nil else {
        throw AgentEventJournalError.invalidData
      }
    case .noteUpdated:
      guard changedFields != nil, completionTransition == nil else {
        throw AgentEventJournalError.invalidData
      }
    case .taskStateChanged:
      guard changedFields == nil, completionTransition != nil else {
        throw AgentEventJournalError.invalidData
      }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case eventID
    case sequence
    case noteID
    case revision
    case occurredAt
    case eventName
    case changedFields
    case completionTransition
    case priorFolderID
    case currentFolderID
    case provenance
  }
}

public struct AgentEventJournal: Codable, Equatable, Sendable {
  static let maximumRecordCount = 4_096
  static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
  static let maximumCanonicalBytes = 1_048_576
  private static let maximumSequence = UInt64.max - 1

  public private(set) var schemaVersion = 1
  public private(set) var epoch: UUID
  public private(set) var lastSequence: UInt64 = 0
  public private(set) var historyFloor: UInt64 = 1
  public private(set) var historyIncomplete: Bool
  public private(set) var records: [AgentEventJournalRecord] = []

  init(epoch: UUID, historyIncomplete: Bool = false) {
    self.epoch = epoch
    self.historyIncomplete = historyIncomplete
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventJournalCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    guard
      keys == [
        "schemaVersion", "epoch", "lastSequence", "historyFloor", "historyIncomplete",
        "records",
      ]
    else {
      throw agentEventJournalDecodingError(decoder)
    }

    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    epoch = try container.decode(UUID.self, forKey: .epoch)
    lastSequence = try container.decode(UInt64.self, forKey: .lastSequence)
    historyFloor = try container.decode(UInt64.self, forKey: .historyFloor)
    historyIncomplete = try container.decode(Bool.self, forKey: .historyIncomplete)
    records = try container.decode([AgentEventJournalRecord].self, forKey: .records)
    try validate()
  }

  public func encode(to encoder: Encoder) throws {
    try validateShape()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(epoch, forKey: .epoch)
    try container.encode(lastSequence, forKey: .lastSequence)
    try container.encode(historyFloor, forKey: .historyFloor)
    try container.encode(historyIncomplete, forKey: .historyIncomplete)
    try container.encode(records, forKey: .records)
  }

  mutating func markIncompleteAndRotate(to newEpoch: UUID) {
    epoch = newEpoch
    historyIncomplete = true
  }

  mutating func captureChanges(
    from previous: Workspace?,
    to current: Workspace,
    previousFolderIDs: [UUID: UUID],
    commitProof: AgentWorkspaceCommitProof?,
    occurredAt: Date,
    makeUUID: @Sendable () -> UUID
  ) throws {
    let previousNotes = Dictionary(
      uniqueKeysWithValues: (previous?.notes ?? []).map { originalNote in
        var note = originalNote
        if let folderID = previousFolderIDs[note.id] {
          note.folderID = folderID
        }
        return (note.id, note)
      }
    )
    var eventIDs = Set(records.map(\.eventID))

    for note in current.notes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      let previousNote = previousNotes[note.id]
      let eventName: AgentEventName
      let changedFields: [AgentEventChangedField]?
      let completionTransition: AgentTaskCompletionTransition?
      if let previousNote {
        let fields = Self.changedFields(from: previousNote, to: note)
        guard !fields.isEmpty else { continue }
        if fields.contains(.body),
          fields.allSatisfy({ $0 == .body || $0 == .formatting }),
          previousNote.titleFontFamily == note.titleFontFamily,
          let transition = Self.completionTransition(
            from: previousNote.body,
            to: note.body
          )
        {
          eventName = .taskStateChanged
          changedFields = nil
          completionTransition = transition
        } else {
          eventName = .noteUpdated
          changedFields = fields
          completionTransition = nil
        }
      } else {
        eventName = .noteCreated
        changedFields = nil
        completionTransition = nil
      }

      guard lastSequence < Self.maximumSequence else {
        throw AgentEventJournalError.invalidData
      }
      let (nextSequence, sequenceOverflow) = lastSequence.addingReportingOverflow(1)
      guard !sequenceOverflow, nextSequence <= Self.maximumSequence else {
        throw AgentEventJournalError.invalidData
      }
      lastSequence = nextSequence
      let eventID = makeUUID()
      guard eventIDs.insert(eventID).inserted else {
        throw AgentEventJournalError.invalidData
      }
      let record = AgentEventJournalRecord(
        eventID: eventID,
        sequence: lastSequence,
        noteID: note.id,
        revision: note.revision,
        occurredAt: occurredAt,
        eventName: eventName,
        changedFields: changedFields,
        completionTransition: completionTransition,
        priorFolderID: previousNote?.folderID,
        currentFolderID: note.folderID,
        provenance: Self.provenance(for: note, commitProof: commitProof)
      )
      try record.validate()
      records.append(record)
    }
  }

  mutating func trim(now: Date) throws {
    let cutoff = now.addingTimeInterval(-Self.maximumAge)
    if let expiredThrough =
      records
      .filter({ $0.occurredAt < cutoff })
      .map(\.sequence)
      .max()
    {
      try discardOldest(through: expiredThrough)
    }
    if records.count > Self.maximumRecordCount {
      try discardOldest(count: records.count - Self.maximumRecordCount)
    }

    guard try canonicalDataUnchecked().count > Self.maximumCanonicalBytes else { return }
    guard !records.isEmpty else { throw AgentEventJournalError.invalidData }
    var low = 1
    var high = records.count
    while low < high {
      let middle = (low + high) / 2
      var candidate = self
      try candidate.discardOldest(count: middle)
      if try candidate.canonicalDataUnchecked().count <= Self.maximumCanonicalBytes {
        high = middle
      } else {
        low = middle + 1
      }
    }
    try discardOldest(count: low)
  }

  func canonicalData() throws -> Data {
    try validateShape()
    let data = try canonicalDataUnchecked()
    guard data.count <= Self.maximumCanonicalBytes else {
      throw AgentEventJournalError.invalidData
    }
    return data
  }

  private mutating func discardOldest(through sequence: UInt64) throws {
    try discardOldest(count: records.prefix { $0.sequence <= sequence }.count)
  }

  private mutating func discardOldest(count: Int) throws {
    guard count > 0 else { return }
    records.removeFirst(min(count, records.count))
    historyIncomplete = true
    if let firstSequence = records.first?.sequence {
      historyFloor = firstSequence
    } else {
      let (nextFloor, floorOverflow) = lastSequence.addingReportingOverflow(1)
      guard !floorOverflow else { throw AgentEventJournalError.invalidData }
      historyFloor = nextFloor
    }
  }

  private func canonicalDataUnchecked() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(
      JournalDocument(
        schemaVersion: schemaVersion,
        epoch: epoch,
        lastSequence: lastSequence,
        historyFloor: historyFloor,
        historyIncomplete: historyIncomplete,
        records: records
      )
    )
  }

  private func validate() throws {
    try validateShape()
    guard try canonicalDataUnchecked().count <= Self.maximumCanonicalBytes else {
      throw AgentEventJournalError.invalidData
    }
  }

  private func validateShape() throws {
    guard
      schemaVersion == 1,
      historyFloor > 0,
      lastSequence <= Self.maximumSequence,
      records.count <= Self.maximumRecordCount
    else {
      throw AgentEventJournalError.invalidData
    }

    if records.isEmpty {
      let (nextFloor, floorOverflow) = lastSequence.addingReportingOverflow(1)
      guard !floorOverflow, historyFloor == nextFloor else {
        throw AgentEventJournalError.invalidData
      }
    } else {
      guard
        records.first?.sequence == historyFloor,
        records.last?.sequence == lastSequence
      else {
        throw AgentEventJournalError.invalidData
      }
      for (index, record) in records.enumerated() {
        try record.validate()
        let (expectedSequence, sequenceOverflow) = historyFloor.addingReportingOverflow(
          UInt64(index)
        )
        guard !sequenceOverflow, record.sequence == expectedSequence else {
          throw AgentEventJournalError.invalidData
        }
      }
    }

    guard historyIncomplete || historyFloor == 1 else {
      throw AgentEventJournalError.invalidData
    }
    if !historyIncomplete {
      guard UInt64(records.count) == lastSequence else {
        throw AgentEventJournalError.invalidData
      }
    }
    guard Set(records.map(\.eventID)).count == records.count else {
      throw AgentEventJournalError.invalidData
    }
  }

  private static func changedFields(
    from old: Note,
    to new: Note
  ) -> [AgentEventChangedField] {
    var fields: [AgentEventChangedField] = []
    if old.title != new.title { fields.append(.title) }
    if old.body != new.body { fields.append(.body) }
    if old.richTextRTF != new.richTextRTF || old.titleFontFamily != new.titleFontFamily {
      fields.append(.formatting)
    }
    if old.tabColorHex != new.tabColorHex || old.isPinned != new.isPinned {
      fields.append(.appearance)
    }
    if old.folderID != new.folderID { fields.append(.organization) }
    return fields.sorted { $0.rawValue < $1.rawValue }
  }

  private static func completionTransition(
    from oldBody: String,
    to newBody: String
  ) -> AgentTaskCompletionTransition? {
    let old = oldBody as NSString
    let new = newBody as NSString
    guard old.length == new.length else { return nil }
    var changedOffset: Int?
    for index in 0..<old.length where old.character(at: index) != new.character(at: index) {
      guard changedOffset == nil else { return nil }
      changedOffset = index
    }
    guard let changedOffset else { return nil }
    let oldMarker = old.character(at: changedOffset)
    let newMarker = new.character(at: changedOffset)
    guard
      (oldMarker == 0x25CB && newMarker == 0x25CF)
        || (oldMarker == 0x25CF && newMarker == 0x25CB)
    else {
      return nil
    }

    let oldTasks = AgentNoteMutationEngine.tasks(in: oldBody)
    let newTasks = AgentNoteMutationEngine.tasks(in: newBody)
    guard !oldTasks.isEmpty, oldTasks.count == newTasks.count else { return nil }
    var changedTask: AgentParsedTask?
    var transition: AgentTaskCompletionTransition?
    for (oldTask, newTask) in zip(oldTasks, newTasks) {
      guard
        oldTask.line == newTask.line,
        oldTask.indentation == newTask.indentation,
        oldTask.text == newTask.text
      else {
        return nil
      }
      guard oldTask.completed != newTask.completed else { continue }
      guard changedTask == nil else { return nil }
      changedTask = oldTask
      transition =
        oldTask.completed
        ? .completeToIncomplete
        : .incompleteToComplete
    }
    guard
      let changedTask,
      let transition,
      oldTasks.filter({
        $0.indentation == changedTask.indentation && $0.text == changedTask.text
      }).count == 1
    else {
      return nil
    }
    return transition
  }

  private static func provenance(
    for note: Note,
    commitProof: AgentWorkspaceCommitProof?
  ) -> AgentEventProvenance {
    guard let commitProof else { return .local }
    guard
      commitProof.noteID == note.id,
      commitProof.resultingRevision == note.revision,
      commitProof.bodySHA256 == bodySHA256(note.body)
    else {
      return .uncertain
    }
    if isIntegration(commitProof.actor) || isIntegration(commitProof.originatingActor) {
      return .integration
    }
    return .local
  }

  private static func isIntegration(_ actor: AgentActivityActor?) -> Bool {
    guard let actor else { return false }
    if case .integration = actor { return true }
    return false
  }

  private static func bodySHA256(_ body: String) -> String {
    SHA256.hash(data: Data(body.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case epoch
    case lastSequence
    case historyFloor
    case historyIncomplete
    case records
  }
}

private struct JournalDocument: Encodable {
  let schemaVersion: Int
  let epoch: UUID
  let lastSequence: UInt64
  let historyFloor: UInt64
  let historyIncomplete: Bool
  let records: [AgentEventJournalRecord]
}

private struct AgentEventJournalCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int? = nil

  static let eventID = Self("eventID")
  static let sequence = Self("sequence")
  static let noteID = Self("noteID")
  static let revision = Self("revision")
  static let occurredAt = Self("occurredAt")
  static let eventName = Self("eventName")
  static let provenance = Self("provenance")
  static let changedFields = Self("changedFields")
  static let completionTransition = Self("completionTransition")
  static let priorFolderID = Self("priorFolderID")
  static let currentFolderID = Self("currentFolderID")
  static let schemaVersion = Self("schemaVersion")
  static let epoch = Self("epoch")
  static let lastSequence = Self("lastSequence")
  static let historyFloor = Self("historyFloor")
  static let historyIncomplete = Self("historyIncomplete")
  static let records = Self("records")

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

extension KeyedDecodingContainer where Key == AgentEventJournalCodingKey {
  fileprivate func decodeOptional<Value: Decodable>(
    _ type: Value.Type,
    forKey key: AgentEventJournalCodingKey
  ) throws -> Value? {
    guard contains(key) else { return nil }
    guard try !decodeNil(forKey: key) else {
      throw AgentEventJournalError.invalidData
    }
    return try decode(type, forKey: key)
  }
}

private func agentEventJournalDecodingError(_ decoder: Decoder) -> DecodingError {
  .dataCorrupted(
    DecodingError.Context(
      codingPath: decoder.codingPath,
      debugDescription: "Agent event journal fields are invalid."
    )
  )
}

private enum AgentEventJournalError: Error {
  case invalidData
}
