import Foundation
import Testing

@testable import FleckCore

@Test func filingLedgerRejectsDuplicateIDsUnsupportedVersionsAndOverlappingRanges() throws {
  let commit = filingCommit()
  #expect(DictationFilingLedger(commits: [commit]).isValid)
  #expect(!DictationFilingLedger(commits: [commit, commit]).isValid)
  let overlapping = DictationFilingCommit(
    captureID: UUID(), inputDigest: commit.inputDigest,
    insertions: [commit.insertions[0], commit.insertions[0]]
  )
  #expect(!DictationFilingLedger(commits: [overlapping]).isValid)
  let invalid = DictationFilingCommit(
    captureID: UUID(), inputDigest: "not-a-digest", insertions: commit.insertions
  )
  #expect(!DictationFilingLedger(commits: [invalid]).isValid)
  let data = Data("{\"version\":2,\"commits\":[]}".utf8)
  #expect(!(try JSONDecoder().decode(DictationFilingLedger.self, from: data)).isValid)
}

@Test func filingLedgerRetainsUndoneIDsAndNeverStoresCaptureText() throws {
  let commit = filingCommit()
  let original = DictationFilingLedger(commits: [commit])
  var undone = commit
  undone.state = .undone
  let tombstone = DictationFilingLedger(commits: [undone])
  #expect(tombstone.preserves(original))
  #expect(!original.preserves(tombstone))
  #expect(!DictationFilingLedger().preserves(original))
  let encoded = String(decoding: try original.canonicalData(), as: UTF8.self)
  #expect(!encoded.contains("synthetic capture text"))
  #expect(!encoded.contains("richText"))
  #expect(!encoded.contains("title"))
}

@Test func filingSnapshotPartialWriteRecoversAllNotesAndLedgerTogetherThenRetries() throws {
  let root = filingStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let first = Note(title: "Alpha", body: "old alpha", createdAt: date, modifiedAt: date)
  let second = Note(title: "Beta", body: "old beta", createdAt: date, modifiedAt: date)
  let baseline = Workspace(notes: [first, second], selectedNoteID: first.id)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      if generation == 2 { throw FilingStoreFailure.injected }
    })
  )
  #expect(try writer.save(workspace: baseline, preferences: .init(), generation: 1) == .committed)
  var filed = baseline
  filed.updateContent(
    id: first.id, body: "old alpha\n\nalpha addition", rtf: nil,
    now: date.addingTimeInterval(1)
  )
  filed.updateContent(
    id: second.id, body: "old beta\n\nbeta addition", rtf: nil,
    now: date.addingTimeInterval(1)
  )
  filed.dictationFilingLedger.commits = [filingCommit(noteIDs: [first.id, second.id])]
  #expect(throws: FilingStoreFailure.injected) {
    try writer.save(workspace: filed, preferences: .init(), generation: 2)
  }
  let recovered = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  #expect(recovered.source == .recovery)
  #expect(recovered.workspace == baseline)
  #expect(try writer.save(workspace: filed, preferences: .init(), generation: 3) == .committed)
  let committed = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  #expect(committed.workspace == filed)
  #expect(committed.workspace.dictationFilingLedger.commits.count == 1)
}

@Test func filingSnapshotPostManifestFailureKeepsCommittedNotesAndCaptureIdentity() throws {
  let root = filingStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let note = Note(title: "Alpha", body: "filed content", createdAt: date, modifiedAt: date)
  let workspace = Workspace(
    notes: [note], selectedNoteID: note.id,
    dictationFilingLedger: .init(commits: [filingCommit(noteIDs: [note.id])])
  )
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(afterManifestCommit: { _ in throw FilingStoreFailure.injected })
  )
  #expect(try writer.save(workspace: workspace, preferences: .init(), generation: 1) == .committed)
  #expect(try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot().workspace == workspace)
}

@Test(arguments: ["version", "hash", "null", "missingHash", "missingBoth"])
func filingSnapshotRejectsCorruptMetadataAsOneGeneration(_ corruption: String) throws {
  let root = filingStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let note = Note(title: "Alpha", body: "before", createdAt: date, modifiedAt: date)
  let baseline = Workspace(notes: [note], selectedNoteID: note.id)
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  try writer.save(workspace: baseline, preferences: .init(), generation: 1)
  var filed = baseline
  filed.updateContent(id: note.id, body: "after", rtf: nil, now: date.addingTimeInterval(1))
  filed.dictationFilingLedger.commits = [filingCommit(noteIDs: [note.id])]
  try writer.save(workspace: filed, preferences: .init(), generation: 2)
  let manifestURL = root.appendingPathComponent("workspace.json")
  var object = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
  )
  switch corruption {
  case "version":
    var ledger = try #require(object["dictationFilingLedger"] as? [String: Any])
    ledger["version"] = 99
    object["dictationFilingLedger"] = ledger
  case "hash": object["dictationFilingLedgerSHA256"] = String(repeating: "0", count: 64)
  case "null": object["dictationFilingLedger"] = NSNull()
  case "missingBoth":
    object.removeValue(forKey: "dictationFilingLedger")
    object.removeValue(forKey: "dictationFilingLedgerSHA256")
  default: object.removeValue(forKey: "dictationFilingLedgerSHA256")
  }
  try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)
  let recovered = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  #expect(recovered.source == .recovery)
  #expect(recovered.workspace == baseline)
}

@Test func filingSnapshotAcceptsLegacyMetadataAbsenceWithoutDestructiveMigration() throws {
  let root = filingStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let note = Note(title: "Legacy", body: "preserved", createdAt: date, modifiedAt: date)
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  let baseline = Workspace(notes: [note], selectedNoteID: note.id)
  try writer.save(workspace: baseline, preferences: .init(), generation: 1)
  let manifestURL = root.appendingPathComponent("workspace.json")
  var object = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
  )
  object.removeValue(forKey: "dictationFilingLedger")
  object.removeValue(forKey: "dictationFilingLedgerSHA256")
  try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)
  let priorBytes = try Data(contentsOf: manifestURL)
  #expect(try writer.loadSnapshot().workspace == baseline)
  #expect(try Data(contentsOf: manifestURL) == priorBytes)
}

@Test func filingSnapshotCannotPruneOrReviveCommittedCaptureIDs() throws {
  let root = filingStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Alpha", body: "content")
  let commit = filingCommit(noteIDs: [note.id])
  var workspace = Workspace(
    notes: [note], dictationFilingLedger: .init(commits: [commit])
  )
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  try writer.save(workspace: workspace, preferences: .init(), generation: 1)
  workspace.dictationFilingLedger.commits = []
  #expect(throws: LocalStore.StoreError.invalidSnapshot) {
    try writer.save(workspace: workspace, preferences: .init(), generation: 2)
  }
  var undone = commit
  undone.state = .undone
  workspace.dictationFilingLedger.commits = [undone]
  try writer.save(workspace: workspace, preferences: .init(), generation: 3)
  workspace.dictationFilingLedger.commits = [commit]
  #expect(throws: LocalStore.StoreError.invalidSnapshot) {
    try writer.save(workspace: workspace, preferences: .init(), generation: 4)
  }
  let reopened = try writer.loadSnapshot()
  #expect(reopened.workspace.dictationFilingLedger.commits == [undone])
}

private func filingCommit(noteIDs: [UUID] = [UUID()]) -> DictationFilingCommit {
  DictationFilingCommit(
    captureID: UUID(), inputDigest: DictationFilingLedger.digest("synthetic capture text"),
    insertions: noteIDs.map {
      DictationFilingInsertion(
        noteID: $0, noteRevision: 1, location: 0, length: 4,
        digest: DictationFilingLedger.digest("text")
      )
    }
  )
}

private func filingStoreRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private enum FilingStoreFailure: Error {
  case injected
}
