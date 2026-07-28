import CryptoKit
import Foundation

public struct PreparedAgentTransaction: Codable, Equatable, Sendable {
  public let changeID: UUID
  public let noteID: UUID
  public let noteTitle: String
  public let actor: AgentActivityActor
  public let originatingActor: AgentActivityActor?
  public let operationID: UUID
  public let createdAt: Date
  public let operation: AgentActivityOperation
  public let patch: AgentTextPatch
  public let previousRevision: UInt64
  public let resultingRevision: UInt64
  public let resultingBodySHA256: String
  public let taskHandle: String?

  public init(
    changeID: UUID,
    noteID: UUID,
    noteTitle: String,
    actor: AgentActivityActor,
    originatingActor: AgentActivityActor? = nil,
    operationID: UUID,
    createdAt: Date,
    operation: AgentActivityOperation,
    patch: AgentTextPatch,
    previousRevision: UInt64,
    resultingRevision: UInt64,
    resultingBodySHA256: String,
    taskHandle: String? = nil
  ) {
    self.changeID = changeID
    self.noteID = noteID
    self.noteTitle = noteTitle
    self.actor = actor
    self.originatingActor = originatingActor
    self.operationID = operationID
    self.createdAt = createdAt
    self.operation = operation
    self.patch = patch
    self.previousRevision = previousRevision
    self.resultingRevision = resultingRevision
    self.resultingBodySHA256 = resultingBodySHA256
    self.taskHandle = taskHandle
  }

  public var expiresAt: Date {
    createdAt.addingTimeInterval(AgentActivityStore.retentionInterval)
  }
}

public struct AgentActivityRecord: Codable, Equatable, Sendable {
  public let changeID: UUID
  public let noteID: UUID
  public let noteTitle: String
  public let actor: AgentActivityActor
  public let originatingActor: AgentActivityActor?
  public let operationID: UUID
  public let createdAt: Date
  public let operation: AgentActivityOperation
  public let patch: AgentTextPatch
  public let previousRevision: UInt64
  public let resultingRevision: UInt64
  public let taskHandle: String?
  public let receipt: AgentWriteReceipt
  public let expiresAt: Date

  public init(
    transaction: PreparedAgentTransaction,
    receipt: AgentWriteReceipt
  ) {
    changeID = transaction.changeID
    noteID = transaction.noteID
    noteTitle = transaction.noteTitle
    actor = transaction.actor
    originatingActor = transaction.originatingActor
    operationID = transaction.operationID
    createdAt = transaction.createdAt
    operation = transaction.operation
    patch = transaction.patch
    previousRevision = transaction.previousRevision
    resultingRevision = transaction.resultingRevision
    taskHandle = transaction.taskHandle
    self.receipt = receipt
    expiresAt = transaction.expiresAt
  }
}

public final class AgentActivityStore: @unchecked Sendable {
  public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

  private struct Tombstone: Codable, Equatable, Sendable {
    let changeID: UUID
    let noteID: UUID
    let previousRevision: UInt64
    let resultingRevision: UInt64
    let taskHandle: String?
    let actor: AgentActivityActor
    let operationID: UUID
    let receipt: AgentWriteReceipt
    let expiresAt: Date
  }

  private enum EntryKind: String, CaseIterable {
    case prepared = "Prepared"
    case records = "Records"
    case tombstones = "Tombstones"
  }

  private let activityURL: URL
  private let now: @Sendable () -> Date
  private let lock = NSLock()
  private let fileManager = FileManager.default
  private let removeItem: (URL) throws -> Void

  public convenience init(
    rootURL: URL,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.init(
      rootURL: rootURL,
      now: now,
      removeItem: { try FileManager.default.removeItem(at: $0) }
    )
  }

  init(
    rootURL: URL,
    now: @escaping @Sendable () -> Date,
    removeItem: @escaping (URL) throws -> Void
  ) {
    activityURL = rootURL.appendingPathComponent("AgentActivity", isDirectory: true)
    self.now = now
    self.removeItem = removeItem
  }

  public func prepare(_ transaction: PreparedAgentTransaction) throws {
    try lock.withLock {
      try ensureDirectories()
      try purgeExpired(at: now())
      try write(transaction, id: transaction.changeID, kind: .prepared)
    }
  }

  public func commit(changeID: UUID, receipt: AgentWriteReceipt) throws {
    try lock.withLock {
      try ensureDirectories()
      try purgeExpired(at: now())
      guard let transaction = preparedTransaction(id: changeID),
        receipt.changeID == transaction.changeID,
        receipt.noteID == transaction.noteID,
        receipt.previousRevision == transaction.previousRevision,
        receipt.resultingRevision == transaction.resultingRevision,
        receipt.taskHandle == transaction.taskHandle
      else {
        throw AgentWorkspaceError(code: .invalidOperation)
      }
      try commit(transaction: transaction, receipt: receipt)
    }
  }

  public func abort(changeID: UUID) throws {
    try lock.withLock {
      try remove(id: changeID, kind: .prepared)
    }
  }

  public func priorReceipt(
    actor: AgentActivityActor,
    operationID: UUID
  ) -> AgentWriteReceipt? {
    lock.withLock {
      try? ensureDirectories()
      let currentDate = now()
      try? purgeExpired(at: currentDate)
      return validTombstones()
        .first {
          $0.expiresAt > currentDate
            && sameActorScope($0.actor, actor)
            && $0.operationID == operationID
        }?
        .receipt
    }
  }

  public func list(
    profileID: UUID?,
    visibleNoteIDs: Set<UUID>
  ) -> [AgentActivityRecord] {
    lock.withLock {
      try? ensureDirectories()
      let currentDate = now()
      try? purgeExpired(at: currentDate)
      return validRecords()
        .filter { record in
          guard
            record.expiresAt > currentDate,
            visibleNoteIDs.contains(record.noteID)
          else { return false }
          guard let profileID else { return true }
          guard case .integration(let recordProfileID, _) = record.actor else {
            return false
          }
          return recordProfileID == profileID
        }
        .sorted {
          if $0.createdAt != $1.createdAt {
            return $0.createdAt > $1.createdAt
          }
          return $0.changeID.uuidString < $1.changeID.uuidString
        }
    }
  }

  public func record(id: UUID) -> AgentActivityRecord? {
    lock.withLock {
      try? ensureDirectories()
      let currentDate = now()
      try? purgeExpired(at: currentDate)
      let record = validEntry(
        AgentActivityRecord.self,
        id: id,
        kind: .records,
        embeddedID: \.changeID
      )
      guard
        let record,
        recordIsCoherent(record),
        record.expiresAt > currentDate
      else { return nil }
      return record
    }
  }

  public func clearVisibleActivity() throws {
    try lock.withLock {
      try ensureDirectories()
      try purgeExpired(at: now())
      for url in try entryURLs(kind: .records) {
        try removeItem(url)
      }
    }
  }

  public func reconcile(
    workspace: Workspace,
    commitProofs: [AgentWorkspaceCommitProof]
  ) throws {
    try lock.withLock {
      try ensureDirectories()
      try purgeExpired(at: now())
      for transaction in validEntries(
        PreparedAgentTransaction.self,
        kind: .prepared,
        id: \.changeID
      ) {
        guard let note = workspace.notes.first(where: { $0.id == transaction.noteID })
        else {
          try remove(id: transaction.changeID, kind: .prepared)
          continue
        }

        let exactCommit =
          note.revision == transaction.resultingRevision
          && bodySHA256(note.body) == transaction.resultingBodySHA256
        let provenCommit =
          note.revision >= transaction.resultingRevision
          && commitProofs.contains { proofMatches($0, transaction: transaction) }

        guard exactCommit || provenCommit else {
          try remove(id: transaction.changeID, kind: .prepared)
          continue
        }

        let receipt = AgentWriteReceipt(
          changeID: transaction.changeID,
          noteID: transaction.noteID,
          previousRevision: transaction.previousRevision,
          resultingRevision: transaction.resultingRevision,
          taskHandle: transaction.taskHandle
        )
        try commit(transaction: transaction, receipt: receipt)
      }
    }
  }

  private func commit(
    transaction: PreparedAgentTransaction,
    receipt: AgentWriteReceipt
  ) throws {
    let record = AgentActivityRecord(transaction: transaction, receipt: receipt)
    let tombstone = Tombstone(
      changeID: transaction.changeID,
      noteID: transaction.noteID,
      previousRevision: transaction.previousRevision,
      resultingRevision: transaction.resultingRevision,
      taskHandle: transaction.taskHandle,
      actor: transaction.actor,
      operationID: transaction.operationID,
      receipt: receipt,
      expiresAt: transaction.expiresAt
    )
    try write(record, id: transaction.changeID, kind: .records)
    try write(tombstone, id: transaction.changeID, kind: .tombstones)
    try remove(id: transaction.changeID, kind: .prepared)
  }

  private func proofMatches(
    _ proof: AgentWorkspaceCommitProof,
    transaction: PreparedAgentTransaction
  ) -> Bool {
    proof.changeID == transaction.changeID
      && proof.noteID == transaction.noteID
      && proof.resultingRevision == transaction.resultingRevision
      && proof.bodySHA256 == transaction.resultingBodySHA256
      && proof.actor == transaction.actor
      && proof.operationID == transaction.operationID
      && manifestDateIdentity(proof.expiresAt)
        == manifestDateIdentity(transaction.expiresAt)
  }

  private func manifestDateIdentity(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  private func purgeExpired(at currentDate: Date) throws {
    for record in validRecords() where record.expiresAt <= currentDate {
      try remove(id: record.changeID, kind: .records)
    }
    for tombstone in validTombstones()
    where tombstone.expiresAt <= currentDate {
      try remove(id: tombstone.changeID, kind: .tombstones)
    }
    for transaction in validEntries(
      PreparedAgentTransaction.self,
      kind: .prepared,
      id: \.changeID
    ) where transaction.expiresAt <= currentDate {
      try remove(id: transaction.changeID, kind: .prepared)
    }
  }

  private func ensureDirectories() throws {
    for kind in EntryKind.allCases {
      try fileManager.createDirectory(
        at: directoryURL(kind),
        withIntermediateDirectories: true
      )
    }
  }

  private func directoryURL(_ kind: EntryKind) -> URL {
    activityURL.appendingPathComponent(kind.rawValue, isDirectory: true)
  }

  private func entryURL(id: UUID, kind: EntryKind) -> URL {
    directoryURL(kind).appendingPathComponent(
      "\(id.uuidString.lowercased()).json"
    )
  }

  private func entryURLs(kind: EntryKind) throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: directoryURL(kind),
      includingPropertiesForKeys: [.isRegularFileKey]
    )
  }

  private func write<Value: Encodable>(
    _ value: Value,
    id: UUID,
    kind: EntryKind
  ) throws {
    try encoder().encode(value).write(to: entryURL(id: id, kind: kind), options: .atomic)
  }

  private func remove(id: UUID, kind: EntryKind) throws {
    let url = entryURL(id: id, kind: kind)
    guard fileManager.fileExists(atPath: url.path) else { return }
    try removeItem(url)
  }

  private func preparedTransaction(id: UUID) -> PreparedAgentTransaction? {
    validEntry(
      PreparedAgentTransaction.self,
      id: id,
      kind: .prepared,
      embeddedID: \.changeID
    )
  }

  private func validRecords() -> [AgentActivityRecord] {
    validEntries(
      AgentActivityRecord.self,
      kind: .records,
      id: \.changeID
    ).filter(recordIsCoherent)
  }

  private func validTombstones() -> [Tombstone] {
    validEntries(
      Tombstone.self,
      kind: .tombstones,
      id: \.changeID
    ).filter(tombstoneIsCoherent)
  }

  private func recordIsCoherent(_ record: AgentActivityRecord) -> Bool {
    record.receipt.changeID == record.changeID
      && record.receipt.noteID == record.noteID
      && record.receipt.previousRevision == record.previousRevision
      && record.receipt.resultingRevision == record.resultingRevision
      && record.receipt.taskHandle == record.taskHandle
  }

  private func tombstoneIsCoherent(_ tombstone: Tombstone) -> Bool {
    tombstone.receipt.changeID == tombstone.changeID
      && tombstone.receipt.noteID == tombstone.noteID
      && tombstone.receipt.previousRevision == tombstone.previousRevision
      && tombstone.receipt.resultingRevision == tombstone.resultingRevision
      && tombstone.receipt.taskHandle == tombstone.taskHandle
  }

  private func validEntries<Value: Decodable>(
    _ type: Value.Type,
    kind: EntryKind,
    id: KeyPath<Value, UUID>
  ) -> [Value] {
    (try? entryURLs(kind: kind))?.compactMap { url in
      validEntry(type, url: url, embeddedID: id)
    } ?? []
  }

  private func validEntry<Value: Decodable>(
    _ type: Value.Type,
    id: UUID,
    kind: EntryKind,
    embeddedID: KeyPath<Value, UUID>
  ) -> Value? {
    validEntry(
      type,
      url: entryURL(id: id, kind: kind),
      embeddedID: embeddedID
    )
  }

  private func validEntry<Value: Decodable>(
    _ type: Value.Type,
    url: URL,
    embeddedID: KeyPath<Value, UUID>
  ) -> Value? {
    guard
      url.pathExtension == "json",
      let filenameID = UUID(
        uuidString: url.deletingPathExtension().lastPathComponent
      ),
      url.lastPathComponent
        == "\(filenameID.uuidString.lowercased()).json",
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
      values.isRegularFile == true,
      let value = try? decoder().decode(type, from: Data(contentsOf: url)),
      value[keyPath: embeddedID] == filenameID
    else {
      return nil
    }
    return value
  }

  private func sameActorScope(
    _ lhs: AgentActivityActor,
    _ rhs: AgentActivityActor
  ) -> Bool {
    switch (lhs, rhs) {
    case (.localUser, .localUser):
      return true
    case (
      .integration(let lhsProfileID, _),
      .integration(let rhsProfileID, _)
    ):
      return lhsProfileID == rhsProfileID
    default:
      return false
    }
  }

  private func bodySHA256(_ body: String) -> String {
    SHA256.hash(data: Data(body.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var wholeSeconds = floor(date.timeIntervalSince1970)
      var nanoseconds = Int(
        ((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded()
      )
      if nanoseconds == 1_000_000_000 {
        wholeSeconds += 1
        nanoseconds = 0
      }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      let whole = formatter.string(
        from: Date(timeIntervalSince1970: wholeSeconds)
      )
      let value =
        String(whole.dropLast())
        + String(
          format: ".%09dZ",
          locale: Locale(identifier: "en_US_POSIX"),
          nanoseconds
        )
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
