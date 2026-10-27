import FleckCore
import Foundation

enum AgentEventOutboxError: Error, Equatable, Sendable {
  case capacityExceeded
  case registrationRequired
  case sourceChanged
  case storageFailure
}

enum AgentEventOutboxProgressStatus: String, Codable, Equatable, Sendable {
  case pending
  case pausedHistory
  case pausedUnavailable
  case pausedCapacity
  case discarded
}

enum AgentEventOutboxEntryStatus: String, Codable, Equatable, Sendable {
  case awaitingVerification
  case notDelivered
}

enum AgentEventOutboxNonDeliveryDisposition: String, Codable, Equatable, Sendable {
  case ownerPaused
  case profileRevoked
  case subscriptionRemoved
  case expired
  case permissionChanged
  case scopeMembershipChanged
  case noteNoLongerAuthorized
}

enum AgentEventOutboxPreparedResponseFenceDisposition: String, Codable, Equatable, Sendable {
  case awaitingResponse
  case failedResponse
}

struct AgentEventOutboxPreparedResponseFence: Codable, Equatable, Sendable {
  let binding: AgentEventCallbackVerificationBinding
  var ownerControlGenerationID: UUID
  let originIntentID: UUID
  var disposition: AgentEventOutboxPreparedResponseFenceDisposition

  init(
    binding: AgentEventCallbackVerificationBinding,
    ownerControlGenerationID: UUID,
    originIntentID: UUID,
    disposition: AgentEventOutboxPreparedResponseFenceDisposition = .awaitingResponse
  ) {
    self.binding = binding
    self.ownerControlGenerationID = ownerControlGenerationID
    self.originIntentID = originIntentID
    self.disposition = disposition
  }

  func blocksDelivery(for control: AgentEventDeliveryControl) -> Bool {
    guard binding == control.binding else { return false }
    if disposition == .awaitingResponse { return true }
    return ownerControlGenerationID == control.generationID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try requireAgentEventOutboxKeys(
      container.allKeys,
      ["binding", "ownerControlGenerationID", "originIntentID", "disposition"],
      decoder: decoder
    )
    binding = try container.decode(
      AgentEventCallbackVerificationBinding.self,
      forKey: AgentEventOutboxCodingKey("binding")
    )
    ownerControlGenerationID = try container.decode(
      UUID.self,
      forKey: AgentEventOutboxCodingKey("ownerControlGenerationID")
    )
    originIntentID = try container.decode(
      UUID.self,
      forKey: AgentEventOutboxCodingKey("originIntentID")
    )
    disposition = try container.decode(
      AgentEventOutboxPreparedResponseFenceDisposition.self,
      forKey: AgentEventOutboxCodingKey("disposition")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try container.encode(binding, forKey: AgentEventOutboxCodingKey("binding"))
    try container.encode(
      ownerControlGenerationID,
      forKey: AgentEventOutboxCodingKey("ownerControlGenerationID")
    )
    try container.encode(originIntentID, forKey: AgentEventOutboxCodingKey("originIntentID"))
    try container.encode(disposition, forKey: AgentEventOutboxCodingKey("disposition"))
  }
}

struct AgentEventOutboxPosition: Codable, Equatable, Sendable {
  let epoch: UUID
  let sequence: UInt64

  init(epoch: UUID, sequence: UInt64) {
    self.epoch = epoch
    self.sequence = sequence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try requireAgentEventOutboxKeys(container.allKeys, ["epoch", "sequence"], decoder: decoder)
    epoch = try container.decode(UUID.self, forKey: AgentEventOutboxCodingKey("epoch"))
    sequence = try container.decode(UInt64.self, forKey: AgentEventOutboxCodingKey("sequence"))
    guard sequence < UInt64.max else {
      throw AgentEventOutboxError.storageFailure
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try container.encode(epoch, forKey: AgentEventOutboxCodingKey("epoch"))
    try container.encode(sequence, forKey: AgentEventOutboxCodingKey("sequence"))
  }
}

struct AgentEventOutboxProgress: Codable, Equatable, Sendable {
  let profileID: UUID
  let subscriptionID: String
  var subscriptionRevision: UInt64
  let grantRevision: UInt64
  let anchor: AgentEventOutboxPosition?
  var capturedThrough: AgentEventOutboxPosition?
  var status: AgentEventOutboxProgressStatus
  var nonDeliveryDisposition: AgentEventOutboxNonDeliveryDisposition?
  var preparedResponseFence: AgentEventOutboxPreparedResponseFence?
  var requiresPreparedResponseFence: Bool

  init(
    profileID: UUID,
    subscriptionID: String,
    subscriptionRevision: UInt64,
    grantRevision: UInt64,
    anchor: AgentEventOutboxPosition?,
    capturedThrough: AgentEventOutboxPosition?,
    status: AgentEventOutboxProgressStatus,
    nonDeliveryDisposition: AgentEventOutboxNonDeliveryDisposition?,
    preparedResponseFence: AgentEventOutboxPreparedResponseFence? = nil,
    requiresPreparedResponseFence: Bool = false
  ) {
    self.profileID = profileID
    self.subscriptionID = subscriptionID
    self.subscriptionRevision = subscriptionRevision
    self.grantRevision = grantRevision
    self.anchor = anchor
    self.capturedThrough = capturedThrough
    self.status = status
    self.nonDeliveryDisposition = nonDeliveryDisposition
    self.preparedResponseFence = preparedResponseFence
    self.requiresPreparedResponseFence = requiresPreparedResponseFence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    let baseKeys: Set<String> = [
      "profileID", "subscriptionID", "subscriptionRevision", "grantRevision", "anchor",
      "capturedThrough", "status", "nonDeliveryDisposition",
    ]
    let actualKeys = Set(container.allKeys.map(\.stringValue))
    let optionalKeys: Set<String> = ["preparedResponseFence", "requiresPreparedResponseFence"]
    guard
      baseKeys.isSubset(of: actualKeys),
      actualKeys.subtracting(baseKeys).isSubset(of: optionalKeys)
    else {
      throw AgentEventOutboxError.storageFailure
    }
    profileID = try container.decode(UUID.self, forKey: AgentEventOutboxCodingKey("profileID"))
    subscriptionID = try container.decode(
      String.self,
      forKey: AgentEventOutboxCodingKey("subscriptionID")
    )
    subscriptionRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventOutboxCodingKey("subscriptionRevision")
    )
    grantRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventOutboxCodingKey("grantRevision")
    )
    anchor = try container.decode(
      AgentEventOutboxPosition?.self,
      forKey: AgentEventOutboxCodingKey("anchor")
    )
    capturedThrough = try container.decode(
      AgentEventOutboxPosition?.self,
      forKey: AgentEventOutboxCodingKey("capturedThrough")
    )
    status = try container.decode(
      AgentEventOutboxProgressStatus.self,
      forKey: AgentEventOutboxCodingKey("status")
    )
    nonDeliveryDisposition = try container.decode(
      AgentEventOutboxNonDeliveryDisposition?.self,
      forKey: AgentEventOutboxCodingKey("nonDeliveryDisposition")
    )
    preparedResponseFence = try container.decodeIfPresent(
      AgentEventOutboxPreparedResponseFence.self,
      forKey: AgentEventOutboxCodingKey("preparedResponseFence")
    )
    requiresPreparedResponseFence = try container.decodeIfPresent(
      Bool.self,
      forKey: AgentEventOutboxCodingKey("requiresPreparedResponseFence")
    ) ?? (preparedResponseFence != nil)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try container.encode(profileID, forKey: AgentEventOutboxCodingKey("profileID"))
    try container.encode(subscriptionID, forKey: AgentEventOutboxCodingKey("subscriptionID"))
    try container.encode(
      subscriptionRevision,
      forKey: AgentEventOutboxCodingKey("subscriptionRevision")
    )
    try container.encode(grantRevision, forKey: AgentEventOutboxCodingKey("grantRevision"))
    try container.encode(anchor, forKey: AgentEventOutboxCodingKey("anchor"))
    try container.encode(capturedThrough, forKey: AgentEventOutboxCodingKey("capturedThrough"))
    try container.encode(status, forKey: AgentEventOutboxCodingKey("status"))
    try container.encode(
      nonDeliveryDisposition,
      forKey: AgentEventOutboxCodingKey("nonDeliveryDisposition")
    )
    try container.encodeIfPresent(
      preparedResponseFence,
      forKey: AgentEventOutboxCodingKey("preparedResponseFence")
    )
    try container.encode(
      requiresPreparedResponseFence,
      forKey: AgentEventOutboxCodingKey("requiresPreparedResponseFence")
    )
  }
}

struct AgentEventOutboxEntry: Codable, Equatable, Sendable {
  let profileID: UUID
  let subscriptionID: String
  let eventID: String
  let sourcePosition: AgentEventOutboxPosition
  var body: Data?
  var status: AgentEventOutboxEntryStatus
  var nonDeliveryDisposition: AgentEventOutboxNonDeliveryDisposition?

  init(
    profileID: UUID,
    subscriptionID: String,
    eventID: String,
    sourcePosition: AgentEventOutboxPosition,
    body: Data?,
    status: AgentEventOutboxEntryStatus,
    nonDeliveryDisposition: AgentEventOutboxNonDeliveryDisposition?
  ) {
    self.profileID = profileID
    self.subscriptionID = subscriptionID
    self.eventID = eventID
    self.sourcePosition = sourcePosition
    self.body = body
    self.status = status
    self.nonDeliveryDisposition = nonDeliveryDisposition
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try requireAgentEventOutboxKeys(
      container.allKeys,
      [
        "profileID", "subscriptionID", "eventID", "sourcePosition", "body", "status",
        "nonDeliveryDisposition",
      ],
      decoder: decoder
    )
    profileID = try container.decode(UUID.self, forKey: AgentEventOutboxCodingKey("profileID"))
    subscriptionID = try container.decode(
      String.self,
      forKey: AgentEventOutboxCodingKey("subscriptionID")
    )
    eventID = try container.decode(String.self, forKey: AgentEventOutboxCodingKey("eventID"))
    sourcePosition = try container.decode(
      AgentEventOutboxPosition.self,
      forKey: AgentEventOutboxCodingKey("sourcePosition")
    )
    body = try container.decode(Data?.self, forKey: AgentEventOutboxCodingKey("body"))
    status = try container.decode(
      AgentEventOutboxEntryStatus.self,
      forKey: AgentEventOutboxCodingKey("status")
    )
    nonDeliveryDisposition = try container.decode(
      AgentEventOutboxNonDeliveryDisposition?.self,
      forKey: AgentEventOutboxCodingKey("nonDeliveryDisposition")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventOutboxCodingKey.self)
    try container.encode(profileID, forKey: AgentEventOutboxCodingKey("profileID"))
    try container.encode(subscriptionID, forKey: AgentEventOutboxCodingKey("subscriptionID"))
    try container.encode(eventID, forKey: AgentEventOutboxCodingKey("eventID"))
    try container.encode(sourcePosition, forKey: AgentEventOutboxCodingKey("sourcePosition"))
    try container.encode(body, forKey: AgentEventOutboxCodingKey("body"))
    try container.encode(status, forKey: AgentEventOutboxCodingKey("status"))
    try container.encode(
      nonDeliveryDisposition,
      forKey: AgentEventOutboxCodingKey("nonDeliveryDisposition")
    )
  }
}

struct AgentEventOutboxState: Equatable, Sendable {
  var progress: [AgentEventOutboxProgress]
  var entries: [AgentEventOutboxEntry]

  init(
    progress: [AgentEventOutboxProgress] = [],
    entries: [AgentEventOutboxEntry] = []
  ) {
    self.progress = progress
    self.entries = entries
  }
}

final class AgentEventOutboxStore: @unchecked Sendable {
  private struct Document: Codable {
    let schemaVersion: Int
    let progress: [AgentEventOutboxProgress]
    let entries: [AgentEventOutboxEntry]

    init(state: AgentEventOutboxState) {
      schemaVersion = 1
      progress = state.progress
      entries = state.entries
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: AgentEventOutboxCodingKey.self)
      try requireAgentEventOutboxKeys(
        container.allKeys,
        ["schemaVersion", "progress", "entries"],
        decoder: decoder
      )
      schemaVersion = try container.decode(
        Int.self,
        forKey: AgentEventOutboxCodingKey("schemaVersion")
      )
      progress = try container.decode(
        [AgentEventOutboxProgress].self,
        forKey: AgentEventOutboxCodingKey("progress")
      )
      entries = try container.decode(
        [AgentEventOutboxEntry].self,
        forKey: AgentEventOutboxCodingKey("entries")
      )
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: AgentEventOutboxCodingKey.self)
      try container.encode(schemaVersion, forKey: AgentEventOutboxCodingKey("schemaVersion"))
      try container.encode(progress, forKey: AgentEventOutboxCodingKey("progress"))
      try container.encode(entries, forKey: AgentEventOutboxCodingKey("entries"))
    }
  }

  private static let maximumFileSize = 8 * 1_048_576
  private static let maximumProgress = 128
  private static let maximumEntriesPerSubscription = 256
  private static let maximumEntriesPerProfile = 512
  private static let maximumEntriesTotal = 4_096
  private static let maximumBodySize = 1_024
  private static let stateLock = NSLock()

  let fileURL: URL
  private let fileWriter: @Sendable (Data, URL) throws -> Void

  init(
    fileURL: URL? = nil,
    fileWriter: @escaping @Sendable (Data, URL) throws -> Void = {
      try $0.write(to: $1, options: .atomic)
    }
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    self.fileWriter = fileWriter
  }

  func load() throws -> AgentEventOutboxState {
    try Self.stateLock.withLock { try loadState() }
  }

  func update(_ mutation: (inout AgentEventOutboxState) throws -> Void) throws {
    try Self.stateLock.withLock {
      var state = try loadState()
      let previous = state
      try mutation(&state)
      Self.sort(&state)
      guard state != previous else { return }
      let data = try Self.encodedData(for: state)
      try Self.validate(state, maximumStateSize: Self.maximumFileSize)
      guard data.count <= Self.maximumFileSize else {
        throw AgentEventOutboxError.capacityExceeded
      }
      try save(data)
    }
  }

  static func validateForWrite(_ state: AgentEventOutboxState) throws {
    try validate(state, maximumStateSize: maximumFileSize)
    guard try encodedData(for: state).count <= maximumFileSize else {
      throw AgentEventOutboxError.capacityExceeded
    }
  }

  private func loadState() throws -> AgentEventOutboxState {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return AgentEventOutboxState()
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      guard
        let fileSize = attributes[.size] as? NSNumber,
        fileSize.intValue <= Self.maximumFileSize
      else {
        throw AgentEventOutboxError.storageFailure
      }
      let data = try Data(contentsOf: fileURL)
      guard data.count <= Self.maximumFileSize else {
        throw AgentEventOutboxError.storageFailure
      }
      let document = try JSONDecoder().decode(Document.self, from: data)
      let state = AgentEventOutboxState(progress: document.progress, entries: document.entries)
      guard
        document.schemaVersion == 1,
        state.progress == Self.sortedProgress(state.progress),
        state.entries == Self.sortedEntries(state.entries)
      else {
        throw AgentEventOutboxError.storageFailure
      }
      try Self.validate(
        state, maximumStateSize: Self.maximumFileSize, invalidIsStorageFailure: true)
      return state
    } catch let error as AgentEventOutboxError {
      throw error
    } catch {
      throw AgentEventOutboxError.storageFailure
    }
  }

  private func save(_ data: Data) throws {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: fileURL.deletingLastPathComponent().path
      )
      do {
        try fileWriter(data, fileURL)
      } catch {
        let persistedData: Data?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
          let fileSize = attributes[.size] as? NSNumber,
          fileSize.intValue <= Self.maximumFileSize
        {
          persistedData = try? Data(contentsOf: fileURL)
        } else {
          persistedData = nil
        }
        guard persistedData == data else {
          throw AgentEventOutboxError.storageFailure
        }
      }
    } catch let error as AgentEventOutboxError {
      throw error
    } catch {
      throw AgentEventOutboxError.storageFailure
    }
  }

  private static func encodedData(for state: AgentEventOutboxState) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(Document(state: state))
  }

  private static func validate(
    _ state: AgentEventOutboxState,
    maximumStateSize: Int,
    invalidIsStorageFailure: Bool = false
  ) throws {
    func capacityExceeded() -> AgentEventOutboxError {
      invalidIsStorageFailure ? .storageFailure : .capacityExceeded
    }

    guard state.progress.count <= maximumProgress, state.entries.count <= maximumEntriesTotal else {
      throw capacityExceeded()
    }
    guard
      Set(state.progress.map { key($0.profileID, $0.subscriptionID) }).count
        == state.progress.count,
      Set(state.entries.map { entryKey($0.profileID, $0.subscriptionID, $0.eventID) }).count
        == state.entries.count,
      state.progress.allSatisfy({ progress in
        validSubscriptionID(progress.subscriptionID)
          && progress.subscriptionRevision > 0
          && validProgress(progress)
      })
    else {
      throw AgentEventOutboxError.storageFailure
    }

    let progressByKey = Dictionary(
      uniqueKeysWithValues: state.progress.map { (key($0.profileID, $0.subscriptionID), $0) }
    )
    let awaitingEntries = state.entries.filter { $0.status == .awaitingVerification }
    guard
      Dictionary(grouping: awaitingEntries, by: { key($0.profileID, $0.subscriptionID) })
        .values.allSatisfy({ $0.count <= maximumEntriesPerSubscription }),
      Dictionary(grouping: awaitingEntries, by: \.profileID)
        .values.allSatisfy({ $0.count <= maximumEntriesPerProfile })
    else {
      throw capacityExceeded()
    }

    for entry in state.entries {
      guard
        validSubscriptionID(entry.subscriptionID),
        validEventID(entry.eventID),
        let progress = progressByKey[key(entry.profileID, entry.subscriptionID)],
        let anchor = progress.anchor,
        let capturedThrough = progress.capturedThrough,
        entry.sourcePosition.epoch == anchor.epoch,
        capturedThrough.epoch == anchor.epoch,
        entry.sourcePosition.sequence > anchor.sequence,
        entry.sourcePosition.sequence <= capturedThrough.sequence
      else {
        throw AgentEventOutboxError.storageFailure
      }
      switch entry.status {
      case .awaitingVerification:
        guard
          entry.body.map({ $0.count < maximumBodySize }) == true,
          entry.nonDeliveryDisposition == nil,
          let body = entry.body,
          let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: body),
          envelope.eventID == entry.eventID,
          envelope.cursor == nil,
          try canonicalBody(envelope) == body
        else {
          throw AgentEventOutboxError.storageFailure
        }
        guard progress.status != .discarded else {
          throw AgentEventOutboxError.storageFailure
        }
      case .notDelivered:
        guard entry.body == nil, entry.nonDeliveryDisposition != nil else {
          throw AgentEventOutboxError.storageFailure
        }
      }
    }

    let data: Data
    do {
      data = try encodedData(for: state)
    } catch {
      throw AgentEventOutboxError.storageFailure
    }
    guard data.count <= maximumStateSize else {
      throw capacityExceeded()
    }

    func validProgress(_ progress: AgentEventOutboxProgress) -> Bool {
      guard
        progress.requiresPreparedResponseFence == (progress.preparedResponseFence != nil)
      else {
        return false
      }
      if let fence = progress.preparedResponseFence {
        guard
          fence.binding.profileID == progress.profileID,
          fence.binding.subscriptionID == progress.subscriptionID,
          fence.binding.subscriptionRevision == progress.subscriptionRevision,
          fence.binding.grantRevision == progress.grantRevision
        else {
          return false
        }
      }
      if progress.status == .discarded {
        guard progress.nonDeliveryDisposition != nil else { return false }
      }
      guard let anchor = progress.anchor, let capturedThrough = progress.capturedThrough else {
        return progress.anchor == nil
          && progress.capturedThrough == nil
          && progress.status != .pending
      }
      return anchor.epoch == capturedThrough.epoch
        && capturedThrough.sequence >= anchor.sequence
        && (progress.status != .discarded || progress.nonDeliveryDisposition != nil)
    }

    func validSubscriptionID(_ value: String) -> Bool {
      value.hasPrefix("evt_")
        && value.utf8.count == 68
        && value.utf8.dropFirst(4).allSatisfy {
          (48...57).contains($0) || (97...102).contains($0)
        }
    }

    func validEventID(_ value: String) -> Bool {
      guard let uuid = UUID(uuidString: value) else { return false }
      return uuid.uuidString.lowercased() == value
    }
  }

  private static func canonicalBody(_ envelope: AgentEventEnvelope) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(envelope)
  }

  private static func key(_ profileID: UUID, _ subscriptionID: String) -> String {
    "\(profileID.uuidString.lowercased())\u{0}\(subscriptionID)"
  }

  private static func entryKey(_ profileID: UUID, _ subscriptionID: String, _ eventID: String)
    -> String
  {
    "\(key(profileID, subscriptionID))\u{0}\(eventID)"
  }

  private static func sort(_ state: inout AgentEventOutboxState) {
    state.progress = sortedProgress(state.progress)
    state.entries = sortedEntries(state.entries)
  }

  private static func sortedProgress(_ values: [AgentEventOutboxProgress])
    -> [AgentEventOutboxProgress]
  {
    values.sorted {
      if $0.profileID != $1.profileID {
        return $0.profileID.uuidString.lowercased() < $1.profileID.uuidString.lowercased()
      }
      return $0.subscriptionID < $1.subscriptionID
    }
  }

  private static func sortedEntries(_ values: [AgentEventOutboxEntry]) -> [AgentEventOutboxEntry] {
    values.sorted {
      if $0.profileID != $1.profileID {
        return $0.profileID.uuidString.lowercased() < $1.profileID.uuidString.lowercased()
      }
      if $0.subscriptionID != $1.subscriptionID {
        return $0.subscriptionID < $1.subscriptionID
      }
      return $0.eventID < $1.eventID
    }
  }

  private static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(FleckProductPaths.canonicalDirectoryName, isDirectory: true)
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("AgentEvents", isDirectory: true)
      .appendingPathComponent("event-outbox.json")
  }
}

private struct AgentEventOutboxCodingKey: CodingKey {
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

private func requireAgentEventOutboxKeys(
  _ keys: [AgentEventOutboxCodingKey],
  _ expected: Set<String>,
  decoder: Decoder
) throws {
  guard Set(keys.map(\.stringValue)) == expected else {
    throw AgentEventOutboxError.storageFailure
  }
}
