import CryptoKit
import Foundation
import Testing

@testable import MenuBarNotesCore

@Test func agentActivityStorePreparesOneAtomicJSONEntry() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(
    rootURL: root,
    now: { Date(timeIntervalSince1970: 300) }
  )
  let transaction = preparedTransaction()

  try store.prepare(transaction)

  let files = try directoryFiles(root, "AgentActivity/Prepared")
  #expect(
    files.map(\.lastPathComponent) == ["\(transaction.changeID.uuidString.lowercased()).json"])
  let decoded = try JSONDecoder.agentActivity.decode(
    PreparedAgentTransaction.self,
    from: Data(contentsOf: try #require(files.first))
  )
  #expect(decoded == transaction)
}

@Test func agentActivityStoreCommitCreatesRecordAndActorScopedTombstone() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let transaction = preparedTransaction()
  let receipt = receipt(for: transaction)

  try store.prepare(transaction)
  try store.commit(changeID: transaction.changeID, receipt: receipt)

  #expect(store.record(id: transaction.changeID)?.receipt == receipt)
  #expect(
    store.priorReceipt(actor: transaction.actor, operationID: transaction.operationID)
      == receipt
  )
  #expect(try directoryFiles(root, "AgentActivity/Prepared").isEmpty)
  #expect(try directoryFiles(root, "AgentActivity/Records").count == 1)
  #expect(try directoryFiles(root, "AgentActivity/Tombstones").count == 1)
}

@Test func agentActivityStoreScopesOperationIDsByActorIdentity() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let operationID = UUID()
  let profileID = UUID()
  let integration = preparedTransaction(
    actor: .integration(profileID: profileID, displayName: "Codex"),
    operationID: operationID
  )
  let local = preparedTransaction(actor: .localUser, operationID: operationID)

  try store.prepare(integration)
  try store.commit(changeID: integration.changeID, receipt: receipt(for: integration))
  try store.prepare(local)
  try store.commit(changeID: local.changeID, receipt: receipt(for: local))

  #expect(
    store.priorReceipt(
      actor: .integration(profileID: profileID, displayName: "Renamed Codex"),
      operationID: operationID
    ) == receipt(for: integration)
  )
  #expect(
    store.priorReceipt(actor: .localUser, operationID: operationID)
      == receipt(for: local)
  )
}

@Test func agentActivityStoreReconcilesExactRevisionAndBodyHash() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let note = Note(body: "Committed", revision: 4)
  let transaction = preparedTransaction(
    noteID: note.id,
    resultingRevision: note.revision,
    resultingBodySHA256: sha256(note.body)
  )
  try store.prepare(transaction)

  try store.reconcile(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    commitProofs: []
  )

  #expect(store.record(id: transaction.changeID)?.receipt == receipt(for: transaction))
}

@Test func agentActivityStoreReconcilesLaterRevisionOnlyWithCompleteProof() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let noteID = UUID()
  let transaction = preparedTransaction(
    noteID: noteID,
    resultingRevision: 4,
    resultingBodySHA256: sha256("Agent result")
  )
  let laterNote = Note(id: noteID, body: "Later human edit", revision: 5)
  try store.prepare(transaction)

  try store.reconcile(
    workspace: Workspace(notes: [laterNote], selectedNoteID: noteID),
    commitProofs: [commitProof(for: transaction)]
  )

  #expect(store.record(id: transaction.changeID) != nil)
}

@Test func agentActivityStorePreservesFractionalExpiryForProofReconciliation() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let noteID = UUID()
  let transaction = preparedTransaction(
    noteID: noteID,
    createdAt: Date(timeIntervalSince1970: 1_900_000_000.125),
    resultingRevision: 4,
    resultingBodySHA256: sha256("Agent result")
  )
  let laterNote = Note(id: noteID, body: "Later edit", revision: 5)
  try store.prepare(transaction)

  try store.reconcile(
    workspace: Workspace(notes: [laterNote], selectedNoteID: noteID),
    commitProofs: [commitProof(for: transaction)]
  )

  #expect(store.record(id: transaction.changeID) != nil)
}

@Test func agentActivityStoreMatchesManifestCanonicalProofExpiry() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let noteID = UUID()
  let transaction = preparedTransaction(
    noteID: noteID,
    createdAt: Date(timeIntervalSince1970: 1_900_000_000.875),
    resultingRevision: 4,
    resultingBodySHA256: sha256("Agent result")
  )
  let laterNote = Note(id: noteID, body: "Later edit", revision: 5)
  let manifestEncoder = JSONEncoder()
  manifestEncoder.dateEncodingStrategy = .iso8601
  let manifestDecoder = JSONDecoder()
  manifestDecoder.dateDecodingStrategy = .iso8601
  let persistedProof = try manifestDecoder.decode(
    AgentWorkspaceCommitProof.self,
    from: manifestEncoder.encode(commitProof(for: transaction))
  )
  try store.prepare(transaction)

  try store.reconcile(
    workspace: Workspace(notes: [laterNote], selectedNoteID: noteID),
    commitProofs: [persistedProof]
  )

  #expect(store.record(id: transaction.changeID) != nil)
}

@Test func agentActivityStoreRejectsIncompleteProofAndLaterRevisionAlone() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let noteID = UUID()
  let transaction = preparedTransaction(
    noteID: noteID,
    resultingRevision: 4,
    resultingBodySHA256: sha256("Agent result")
  )
  let laterNote = Note(id: noteID, body: "Later human edit", revision: 5)
  var wrongProof = commitProof(for: transaction)
  wrongProof = AgentWorkspaceCommitProof(
    changeID: wrongProof.changeID,
    noteID: wrongProof.noteID,
    resultingRevision: wrongProof.resultingRevision,
    bodySHA256: "wrong",
    actor: wrongProof.actor,
    operationID: wrongProof.operationID,
    expiresAt: wrongProof.expiresAt
  )
  try store.prepare(transaction)

  try store.reconcile(
    workspace: Workspace(notes: [laterNote], selectedNoteID: noteID),
    commitProofs: [wrongProof]
  )

  #expect(store.record(id: transaction.changeID) == nil)
  #expect(
    store.priorReceipt(actor: transaction.actor, operationID: transaction.operationID)
      == nil
  )
  #expect(try directoryFiles(root, "AgentActivity/Prepared").isEmpty)
}

@Test func agentActivityStoreRemovesUnappliedPreparation() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let transaction = preparedTransaction()
  try store.prepare(transaction)

  try store.reconcile(workspace: Workspace(), commitProofs: [])

  #expect(try directoryFiles(root, "AgentActivity/Prepared").isEmpty)
  #expect(store.record(id: transaction.changeID) == nil)
}

@Test func agentActivityStoreIgnoresMalformedAndMismatchedEntries() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let valid = preparedTransaction()
  try store.prepare(valid)
  try store.commit(changeID: valid.changeID, receipt: receipt(for: valid))

  let records = root.appendingPathComponent("AgentActivity/Records", isDirectory: true)
  try Data("not json".utf8).write(to: records.appendingPathComponent("\(UUID()).json"))
  let mismatched = preparedTransaction()
  let mismatchedRecord = AgentActivityRecord(
    transaction: mismatched, receipt: receipt(for: mismatched))
  try JSONEncoder.agentActivity.encode(mismatchedRecord).write(
    to: records.appendingPathComponent("\(UUID().uuidString.lowercased()).json")
  )
  try JSONEncoder.agentActivity.encode(mismatchedRecord).write(
    to: records.appendingPathComponent("\(mismatched.changeID.uuidString.uppercased()).json")
  )

  #expect(
    store.list(profileID: nil, visibleNoteIDs: [valid.noteID]).map(\.changeID) == [valid.changeID])
}

@Test func agentActivityStoreRejectsSemanticallyIncoherentRecords() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let transaction = preparedTransaction(taskHandle: "task-handle")
  try store.prepare(transaction)
  try store.commit(
    changeID: transaction.changeID,
    receipt: receipt(for: transaction)
  )
  let recordURL = try #require(
    directoryFiles(root, "AgentActivity/Records").first
  )
  let original = try jsonObject(at: recordURL)
  #expect(original["taskHandle"] as? String == transaction.taskHandle)
  let mismatches: [(String, Any)] = [
    ("changeID", UUID().uuidString),
    ("noteID", UUID().uuidString),
    ("previousRevision", Int(transaction.previousRevision + 1)),
    ("resultingRevision", Int(transaction.resultingRevision + 1)),
    ("taskHandle", "different-task"),
  ]

  for (key, value) in mismatches {
    var object = original
    var receipt = try #require(object["receipt"] as? [String: Any])
    receipt[key] = value
    object["receipt"] = receipt
    try writeJSONObject(object, to: recordURL)

    #expect(store.record(id: transaction.changeID) == nil)
    #expect(
      store.list(profileID: nil, visibleNoteIDs: [transaction.noteID]).isEmpty
    )
  }
}

@Test func agentActivityStoreRejectsSemanticallyIncoherentTombstones() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let transaction = preparedTransaction(taskHandle: "task-handle")
  try store.prepare(transaction)
  try store.commit(
    changeID: transaction.changeID,
    receipt: receipt(for: transaction)
  )
  let tombstoneURL = try #require(
    directoryFiles(root, "AgentActivity/Tombstones").first
  )
  let original = try jsonObject(at: tombstoneURL)
  #expect(original["noteID"] as? String == transaction.noteID.uuidString)
  #expect(
    original["previousRevision"] as? Int
      == Int(transaction.previousRevision)
  )
  #expect(
    original["resultingRevision"] as? Int
      == Int(transaction.resultingRevision)
  )
  #expect(original["taskHandle"] as? String == transaction.taskHandle)
  let mismatches: [(String, Any)] = [
    ("changeID", UUID().uuidString),
    ("noteID", UUID().uuidString),
    ("previousRevision", Int(transaction.previousRevision + 1)),
    ("resultingRevision", Int(transaction.resultingRevision + 1)),
    ("taskHandle", "different-task"),
  ]

  for (key, value) in mismatches {
    var object = original
    var receipt = try #require(object["receipt"] as? [String: Any])
    receipt[key] = value
    object["receipt"] = receipt
    try writeJSONObject(object, to: tombstoneURL)

    #expect(
      store.priorReceipt(
        actor: transaction.actor,
        operationID: transaction.operationID
      ) == nil
    )
  }
}

@Test func agentActivityStoreExpiresRecordsAndTombstonesAtThirtyDaysExactly() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
  let clock = AgentActivityTestClock(createdAt)
  let store = AgentActivityStore(rootURL: root, now: { clock.now })
  let transaction = preparedTransaction(createdAt: createdAt)
  try store.prepare(transaction)
  try store.commit(changeID: transaction.changeID, receipt: receipt(for: transaction))

  clock.now = createdAt.addingTimeInterval(30 * 24 * 60 * 60 - 1)
  #expect(store.record(id: transaction.changeID) != nil)
  #expect(
    store.priorReceipt(actor: transaction.actor, operationID: transaction.operationID)
      != nil
  )

  clock.now = createdAt.addingTimeInterval(30 * 24 * 60 * 60)
  #expect(store.record(id: transaction.changeID) == nil)
  #expect(
    store.priorReceipt(actor: transaction.actor, operationID: transaction.operationID)
      == nil
  )
}

@Test func agentActivityStoreNeverReturnsExpiredDataWhenDeletionFails() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
  let transaction = preparedTransaction(createdAt: createdAt)
  let setupStore = AgentActivityStore(rootURL: root, now: { createdAt })
  try setupStore.prepare(transaction)
  try setupStore.commit(
    changeID: transaction.changeID,
    receipt: receipt(for: transaction)
  )
  let expiry = createdAt.addingTimeInterval(
    AgentActivityStore.retentionInterval
  )
  let store = AgentActivityStore(
    rootURL: root,
    now: { expiry },
    removeItem: { _ in throw AgentActivityDeletionFailure() }
  )

  #expect(
    store.list(profileID: nil, visibleNoteIDs: [transaction.noteID]).isEmpty
  )
  #expect(store.record(id: transaction.changeID) == nil)
  #expect(
    store.priorReceipt(
      actor: transaction.actor,
      operationID: transaction.operationID
    ) == nil
  )
}

@Test func agentActivityStoreClearRemovesPatchesButKeepsContentFreeTombstones() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let transaction = preparedTransaction()
  let transactionReceipt = receipt(for: transaction)
  try store.prepare(transaction)
  try store.commit(changeID: transaction.changeID, receipt: transactionReceipt)

  try store.clearVisibleActivity()

  #expect(store.record(id: transaction.changeID) == nil)
  #expect(
    store.priorReceipt(actor: transaction.actor, operationID: transaction.operationID)
      == transactionReceipt
  )
  let tombstoneData = try Data(
    contentsOf: try #require(
      directoryFiles(root, "AgentActivity/Tombstones").first
    )
  )
  let tombstoneJSON = String(decoding: tombstoneData, as: UTF8.self)
  #expect(!tombstoneJSON.contains("beforeText"))
  #expect(!tombstoneJSON.contains("afterText"))
  #expect(!tombstoneJSON.contains(transaction.patch.beforeText))
  #expect(!tombstoneJSON.contains(transaction.patch.afterText))
}

@Test func agentActivityStoreFiltersIntegrationActivityByProfileAndVisibleNotes() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(rootURL: root)
  let profileID = UUID()
  let visibleNoteID = UUID()
  let ownVisible = preparedTransaction(
    noteID: visibleNoteID,
    actor: .integration(profileID: profileID, displayName: "Codex")
  )
  let ownHidden = preparedTransaction(
    actor: .integration(profileID: profileID, displayName: "Codex")
  )
  let otherVisible = preparedTransaction(
    noteID: visibleNoteID,
    actor: .integration(profileID: UUID(), displayName: "Claude")
  )
  let localVisible = preparedTransaction(noteID: visibleNoteID, actor: .localUser)
  for transaction in [ownVisible, ownHidden, otherVisible, localVisible] {
    try store.prepare(transaction)
    try store.commit(changeID: transaction.changeID, receipt: receipt(for: transaction))
  }

  let integrationRecords = store.list(
    profileID: profileID,
    visibleNoteIDs: [visibleNoteID]
  )
  #expect(integrationRecords.map(\.changeID) == [ownVisible.changeID])
  #expect(
    Set(store.list(profileID: nil, visibleNoteIDs: [visibleNoteID]).map(\.changeID))
      == [ownVisible.changeID, otherVisible.changeID, localVisible.changeID]
  )
}

@Test func agentActivityStoreListsNewestFirst() throws {
  let root = temporaryAgentActivityURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = AgentActivityStore(
    rootURL: root,
    now: { Date(timeIntervalSince1970: 300) }
  )
  let older = preparedTransaction(createdAt: Date(timeIntervalSince1970: 100))
  let newer = preparedTransaction(
    noteID: older.noteID,
    createdAt: Date(timeIntervalSince1970: 200)
  )
  for transaction in [older, newer] {
    try store.prepare(transaction)
    try store.commit(changeID: transaction.changeID, receipt: receipt(for: transaction))
  }

  #expect(
    store.list(profileID: nil, visibleNoteIDs: [older.noteID]).map(\.changeID)
      == [newer.changeID, older.changeID]
  )
}

private func temporaryAgentActivityURL() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesAgentActivityTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func preparedTransaction(
  changeID: UUID = UUID(),
  noteID: UUID = UUID(),
  actor: AgentActivityActor = .integration(profileID: UUID(), displayName: "Codex"),
  operationID: UUID = UUID(),
  createdAt: Date = Date(timeIntervalSince1970: 1_900_000_000),
  resultingRevision: UInt64 = 4,
  resultingBodySHA256: String = sha256("Result"),
  taskHandle: String? = nil
) -> PreparedAgentTransaction {
  PreparedAgentTransaction(
    changeID: changeID,
    noteID: noteID,
    noteTitle: "Tasks",
    actor: actor,
    operationID: operationID,
    createdAt: createdAt,
    operation: .replaceLines,
    patch: AgentTextPatch(
      beforeText: "Before secret",
      afterText: "After secret",
      range: NSRange(location: 0, length: 6),
      prefixContext: "",
      suffixContext: ""
    ),
    previousRevision: resultingRevision - 1,
    resultingRevision: resultingRevision,
    resultingBodySHA256: resultingBodySHA256,
    taskHandle: taskHandle
  )
}

private func receipt(for transaction: PreparedAgentTransaction) -> AgentWriteReceipt {
  AgentWriteReceipt(
    changeID: transaction.changeID,
    noteID: transaction.noteID,
    previousRevision: transaction.previousRevision,
    resultingRevision: transaction.resultingRevision,
    taskHandle: transaction.taskHandle
  )
}

private func commitProof(
  for transaction: PreparedAgentTransaction
) -> AgentWorkspaceCommitProof {
  AgentWorkspaceCommitProof(
    changeID: transaction.changeID,
    noteID: transaction.noteID,
    resultingRevision: transaction.resultingRevision,
    bodySHA256: transaction.resultingBodySHA256,
    actor: transaction.actor,
    operationID: transaction.operationID,
    expiresAt: transaction.createdAt.addingTimeInterval(30 * 24 * 60 * 60)
  )
}

private func sha256(_ text: String) -> String {
  SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func directoryFiles(_ root: URL, _ path: String) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(
    at: root.appendingPathComponent(path, isDirectory: true),
    includingPropertiesForKeys: nil
  ).sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func jsonObject(at url: URL) throws -> [String: Any] {
  try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: url))
      as? [String: Any]
  )
}

private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    .write(to: url, options: .atomic)
}

private final class AgentActivityTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(_ value: Date) {
    self.value = value
  }

  var now: Date {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}

private struct AgentActivityDeletionFailure: Error {}

extension JSONEncoder {
  fileprivate static var agentActivity: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var agentActivity: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
