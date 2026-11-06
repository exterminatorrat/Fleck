import CryptoKit
import FleckMCPFixtureSupport
import Foundation
import Testing

@testable import FleckCore

private enum AgentEventJournalTestFailure: Error {
  case invalidJSON
  case missingJournal
  case missingRecords
  case beforeManifestCommit
}

private func jsonObject(at url: URL) throws -> [String: Any] {
  guard
    let object = try JSONSerialization.jsonObject(
      with: Data(contentsOf: url)
    ) as? [String: Any]
  else {
    throw AgentEventJournalTestFailure.invalidJSON
  }
  return object
}

private func journalObject(at directory: URL) throws -> [String: Any] {
  let manifest = try jsonObject(at: directory.appendingPathComponent("workspace.json"))
  guard let journal = manifest["agentEventJournal"] as? [String: Any] else {
    throw AgentEventJournalTestFailure.missingJournal
  }
  return journal
}

private func journalRecords(_ journal: [String: Any]) throws -> [[String: Any]] {
  guard let records = journal["records"] as? [[String: Any]] else {
    throw AgentEventJournalTestFailure.missingRecords
  }
  return records
}

private func canonicalJSON(_ object: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func installJournalSequences(
  _ sequences: [UInt64],
  at directory: URL
) throws {
  var manifest = try jsonObject(at: directory.appendingPathComponent("workspace.json"))
  var journal = try journalObject(at: directory)
  let template = try #require(try journalRecords(journal).first)
  let eventIDs = [
    UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
    UUID(uuidString: "00000000-0000-0000-0000-000000000092")!,
    UUID(uuidString: "00000000-0000-0000-0000-000000000093")!,
  ]
  let records = try sequences.enumerated().map { index, sequence in
    guard eventIDs.indices.contains(index) else {
      throw AgentEventJournalTestFailure.missingRecords
    }
    var record = template
    record["eventID"] = eventIDs[index].uuidString
    record["sequence"] = sequence
    return record
  }
  guard let floor = sequences.first, let lastSequence = sequences.last else {
    throw AgentEventJournalTestFailure.missingRecords
  }
  journal["historyIncomplete"] = true
  journal["historyFloor"] = floor
  journal["lastSequence"] = lastSequence
  journal["records"] = records
  manifest["agentEventJournal"] = journal
  manifest["agentEventJournalSHA256"] = sha256(try canonicalJSON(journal))
  try canonicalJSON(manifest).write(
    to: directory.appendingPathComponent("workspace.json"),
    options: .atomic
  )
}

private func rootFileContents(excludingRecoveryAt root: URL) throws -> [String: Data] {
  guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [:] }
  var contents: [String: Data] = [:]
  while let path = enumerator.nextObject() as? String {
    if path == "Recovery" {
      enumerator.skipDescendants()
      continue
    }
    guard !path.hasPrefix("Recovery/") else { continue }
    let url = root.appendingPathComponent(path)
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      continue
    }
    contents[path] = try Data(contentsOf: url)
  }
  return contents
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data)
    .map { String(format: "%02x", $0) }
    .joined()
}

private func updateRecord(
  at directory: URL,
  index: Int = -1
) throws -> [String: Any] {
  let records = try journalRecords(journalObject(at: directory))
  let record = try #require(records.indices.contains(index) ? records[index] : records.last)
  return record
}

@Test func snapshotJournalIsAtomicAndStoresOnlyMetadata() throws {
  let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventJournal)
  let root = ownedRoot.url
  defer {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Owned MCP fixture cleanup failed: \(error)")
    }
  }

  let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
  let originalFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
  let currentFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
  let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
  let original = Note(
    id: noteID,
    title: "PRIVATE_TITLE_CANARY",
    body: "PRIVATE_BODY_CANARY",
    richTextRTF: Data("PRIVATE_RTF_CANARY".utf8),
    createdAt: fixedDate,
    modifiedAt: fixedDate,
    folderID: originalFolderID
  )
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { fixedDate })

  #expect(
    try writer.save(
      workspace: Workspace(notes: [original], selectedNoteID: original.id),
      preferences: .init(),
      generation: 0
    ) == .committed
  )

  var changed = original
  changed.title = "PRIVATE_TITLE_UPDATED_CANARY"
  changed.body = "PRIVATE_BODY_UPDATED_CANARY"
  changed.richTextRTF = Data("PRIVATE_RTF_UPDATED_CANARY".utf8)
  changed.folderID = currentFolderID
  changed.modifiedAt = fixedDate.addingTimeInterval(1)
  changed.revision = 1
  #expect(
    try writer.save(
      workspace: Workspace(notes: [changed], selectedNoteID: changed.id),
      preferences: .init(),
      generation: 0
    ) == .committed
  )

  let manifest = try jsonObject(at: root.appendingPathComponent("workspace.json"))
  let journal = try #require(manifest["agentEventJournal"] as? [String: Any])
  let records = try journalRecords(journal)
  let record = try #require(records.last)
  #expect(records.count == 2)
  #expect(journal["schemaVersion"] as? Int == 1)
  #expect(journal["historyIncomplete"] as? Bool == false)
  #expect(journal["historyFloor"] as? Int == 1)
  #expect((journal["epoch"] as? String).flatMap(UUID.init(uuidString:)) != nil)
  #expect(records.compactMap { $0["sequence"] as? Int } == [1, 2])
  #expect(record["eventName"] as? String == AgentEventName.noteUpdated.rawValue)
  #expect(
    record["changedFields"] as? [String]
      == ["body", "formatting", "organization", "title"]
  )
  #expect(record["provenance"] as? String == "local")
  #expect(
    (record["priorFolderID"] as? String).flatMap(UUID.init(uuidString:))
      == originalFolderID
  )
  #expect(
    (record["currentFolderID"] as? String).flatMap(UUID.init(uuidString:))
      == currentFolderID
  )
  #expect(record["body"] == nil)
  #expect(record["title"] == nil)
  #expect(record["contentHash"] == nil)
  #expect(record["profileID"] == nil)
  #expect(record["displayName"] == nil)
  #expect(record["taskHandle"] == nil)
  #expect(record["origin"] == nil)

  let serializedJournal = String(
    decoding: try canonicalJSON(journal),
    as: UTF8.self
  )
  #expect(!serializedJournal.contains("PRIVATE_TITLE_CANARY"))
  #expect(!serializedJournal.contains("PRIVATE_TITLE_UPDATED_CANARY"))
  #expect(!serializedJournal.contains("PRIVATE_BODY_CANARY"))
  #expect(!serializedJournal.contains("PRIVATE_BODY_UPDATED_CANARY"))
  #expect(!serializedJournal.contains("PRIVATE_RTF_CANARY"))
  #expect(!serializedJournal.contains("PRIVATE_RTF_UPDATED_CANARY"))
  #expect(
    manifest["agentEventJournalSHA256"] as? String == sha256(try canonicalJSON(journal))
  )
}

@Test func selectionPreferencesTimestampAndAccessOnlySavesDoNotAppendEvents() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let note = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
    title: "Stable",
    body: "Stable body",
    createdAt: date,
    modifiedAt: date
  )
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try writer.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 0
  )
  let originalJournal = try journalObject(at: root)
  let originalRecords = try journalRecords(originalJournal)
  let originalEventID = originalRecords.first?["eventID"] as? String

  var metadataOnly = note
  metadataOnly.modifiedAt = date.addingTimeInterval(1)
  metadataOnly.agentAccess = true
  metadataOnly.revision = 1
  _ = try writer.save(
    workspace: Workspace(notes: [metadataOnly], selectedNoteID: nil),
    preferences: .init(fontFamily: "Menlo"),
    generation: 0
  )

  let finalJournal = try journalObject(at: root)
  let finalRecords = try journalRecords(finalJournal)
  #expect(finalRecords.count == 1)
  #expect(finalRecords.first?["eventID"] as? String == originalEventID)
  #expect(finalJournal["epoch"] as? String == originalJournal["epoch"] as? String)
}

@Test func onlyTheNewlyMatchedCommitProofControlsEventProvenance() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let note = Note(title: "Provenance", body: "local start", createdAt: date, modifiedAt: date)
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try writer.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 0
  )

  let integration = AgentActivityActor.integration(
    profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
    displayName: "Synthetic integration"
  )
  var integrationEdit = note
  integrationEdit.body = "integration edit"
  integrationEdit.revision = 1
  integrationEdit.modifiedAt = date.addingTimeInterval(1)
  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(),
    noteID: note.id,
    resultingRevision: integrationEdit.revision,
    bodySHA256: sha256(Data(integrationEdit.body.utf8)),
    actor: .localUser,
    originatingActor: integration,
    operationID: UUID(),
    expiresAt: date.addingTimeInterval(60)
  )
  _ = try writer.save(
    workspace: Workspace(notes: [integrationEdit], selectedNoteID: note.id),
    preferences: .init(),
    generation: 0,
    commitProof: proof
  )

  var localEdit = integrationEdit
  localEdit.body = "later local edit"
  localEdit.revision = 2
  localEdit.modifiedAt = date.addingTimeInterval(2)
  _ = try writer.save(
    workspace: Workspace(notes: [localEdit], selectedNoteID: note.id),
    preferences: .init(),
    generation: 0
  )

  let records = try journalRecords(journalObject(at: root))
  #expect(records.compactMap { $0["provenance"] as? String } == ["local", "integration", "local"])
}

@Test func checklistCompletionRequiresOneUnambiguousSerializerTransition() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let note = Note(
    title: "Tasks",
    body: "Heading\n○ PRIVATE_TASK_CANARY\n",
    createdAt: date,
    modifiedAt: date
  )
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try writer.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 0
  )

  let task = try #require(AgentNoteMutationEngine.tasks(in: note.body).first)
  let draft = try AgentNoteMutationEngine.setTaskState(
    task,
    completed: true,
    in: note.body
  )
  var completed = note
  completed.body = draft.body
  completed.richTextRTF = Data("updated rich-text representation".utf8)
  completed.modifiedAt = date.addingTimeInterval(1)
  completed.revision = 1
  _ = try writer.save(
    workspace: Workspace(notes: [completed], selectedNoteID: note.id),
    preferences: .init(),
    generation: 0
  )

  let completion = try updateRecord(at: root)
  #expect(completion["eventName"] as? String == AgentEventName.taskStateChanged.rawValue)
  #expect(
    completion["completionTransition"] as? String
      == AgentTaskCompletionTransition.incompleteToComplete.rawValue
  )
  #expect(completion["changedFields"] == nil)
  #expect(
    !String(decoding: try canonicalJSON(try journalObject(at: root)), as: UTF8.self)
      .contains("PRIVATE_TASK_CANARY")
  )

  let duplicateRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: duplicateRoot) }
  let repeatedBody = "○ duplicate task\n○ duplicate task"
  let repeated = Note(
    title: "Repeated tasks", body: repeatedBody, createdAt: date, modifiedAt: date)
  let repeatedWriter = LocalStoreSnapshotWriter(rootURL: duplicateRoot, now: { date })
  _ = try repeatedWriter.save(
    workspace: Workspace(notes: [repeated], selectedNoteID: repeated.id),
    preferences: .init(),
    generation: 0
  )
  let repeatedTask = try #require(AgentNoteMutationEngine.tasks(in: repeatedBody).first)
  let repeatedDraft = try AgentNoteMutationEngine.setTaskState(
    repeatedTask,
    completed: true,
    in: repeatedBody
  )
  var repeatedCompletion = repeated
  repeatedCompletion.body = repeatedDraft.body
  repeatedCompletion.revision = 1
  _ = try repeatedWriter.save(
    workspace: Workspace(notes: [repeatedCompletion], selectedNoteID: repeated.id),
    preferences: .init(),
    generation: 0
  )

  let ambiguous = try updateRecord(at: duplicateRoot)
  #expect(ambiguous["eventName"] as? String == AgentEventName.noteUpdated.rawValue)
  #expect(ambiguous["changedFields"] as? [String] == ["body"])
  #expect(ambiguous["completionTransition"] == nil)
}

@Test func legacyManifestStartsAnExplicitlyIncompleteHistory() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let original = Note(title: "Legacy", body: "old", createdAt: date, modifiedAt: date)
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try writer.save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id),
    preferences: .init(),
    generation: 0
  )
  var manifest = try jsonObject(at: root.appendingPathComponent("workspace.json"))
  manifest.removeValue(forKey: "agentEventJournal")
  manifest.removeValue(forKey: "agentEventJournalSHA256")
  try canonicalJSON(manifest).write(
    to: root.appendingPathComponent("workspace.json"),
    options: .atomic
  )

  var changed = original
  changed.body = "new"
  changed.revision = 1
  let migrationWriter = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  #expect(try migrationWriter.loadSnapshot().source == .root)
  _ = try migrationWriter.save(
    workspace: Workspace(notes: [changed], selectedNoteID: changed.id),
    preferences: .init(),
    generation: 1
  )

  let journal = try journalObject(at: root)
  #expect(journal["historyIncomplete"] as? Bool == true)
  #expect(journal["historyFloor"] as? Int == 1)
  #expect(try journalRecords(journal).count == 1)
  #expect(try updateRecord(at: root)["eventName"] as? String == AgentEventName.noteUpdated.rawValue)
}

@Test func malformedJournalFallsBackAndRecoveryRotatesTheEpoch() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let original = Note(title: "Recover", body: "original", createdAt: date, modifiedAt: date)
  let firstWriter = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try firstWriter.save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id),
    preferences: .init(),
    generation: 0
  )
  let originalJournal = try journalObject(at: root)
  let originalEpoch = originalJournal["epoch"] as? String

  var changed = original
  changed.body = "unreliable root"
  changed.revision = 1
  _ = try firstWriter.save(
    workspace: Workspace(notes: [changed], selectedNoteID: changed.id),
    preferences: .init(),
    generation: 1
  )
  var malformedManifest = try jsonObject(at: root.appendingPathComponent("workspace.json"))
  malformedManifest["agentEventJournalSHA256"] = "incorrect-hash"
  try canonicalJSON(malformedManifest).write(
    to: root.appendingPathComponent("workspace.json"),
    options: .atomic
  )

  let recoveringWriter = LocalStoreSnapshotWriter(
    rootURL: root,
    now: { date.addingTimeInterval(2) }
  )
  let recovered = try recoveringWriter.loadSnapshot()
  #expect(recovered.source == .recovery)
  #expect(recovered.workspace.notes.first?.body == original.body)

  var recoveredEdit = recovered.workspace.notes[0]
  recoveredEdit.body = "committed after recovery"
  recoveredEdit.revision = 1
  _ = try recoveringWriter.save(
    workspace: Workspace(notes: [recoveredEdit], selectedNoteID: recoveredEdit.id),
    preferences: .init(),
    generation: 2
  )
  var journal = try journalObject(at: root)
  #expect(journal["epoch"] as? String != originalEpoch)
  #expect(journal["historyIncomplete"] as? Bool == true)
  #expect(try journalRecords(journal).count == 2)

  var manifest = try jsonObject(at: root.appendingPathComponent("workspace.json"))
  journal["schemaVersion"] = 99
  manifest["agentEventJournal"] = journal
  manifest["agentEventJournalSHA256"] = sha256(try canonicalJSON(journal))
  try canonicalJSON(manifest).write(
    to: root.appendingPathComponent("workspace.json"),
    options: .atomic
  )

  let schemaFallback = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  #expect(schemaFallback.source == .recovery)
  #expect(schemaFallback.workspace.notes.first?.body == original.body)

  journal["schemaVersion"] = 1
  journal["historyFloor"] = 0
  manifest["agentEventJournal"] = journal
  manifest["agentEventJournalSHA256"] = sha256(try canonicalJSON(journal))
  try canonicalJSON(manifest).write(
    to: root.appendingPathComponent("workspace.json"),
    options: .atomic
  )

  let shapeFallback = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  #expect(shapeFallback.source == .recovery)
  #expect(shapeFallback.workspace.notes.first?.body == original.body)
}

@Test func overflowingJournalShapeThrowsAndUsesRecoveryBeforeHashValidation() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let original = Note(title: "Overflow", body: "recovery", createdAt: date, modifiedAt: date)
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try writer.save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id),
    preferences: .init(),
    generation: 0
  )
  var changed = original
  changed.body = "untrusted root"
  changed.revision = 1
  _ = try writer.save(
    workspace: Workspace(notes: [changed], selectedNoteID: changed.id),
    preferences: .init(),
    generation: 1
  )

  let first = UInt64.max - 1
  try installJournalSequences([first, UInt64.max, first], at: root)
  var manifest = try jsonObject(at: root.appendingPathComponent("workspace.json"))
  manifest["agentEventJournalSHA256"] = "incorrect-hash"
  try canonicalJSON(manifest).write(
    to: root.appendingPathComponent("workspace.json"),
    options: .atomic
  )
  let journal = try journalObject(at: root)
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  var decodeFailed = false
  do {
    _ = try decoder.decode(AgentEventJournal.self, from: canonicalJSON(journal))
  } catch {
    decodeFailed = true
  }
  #expect(decodeFailed)

  let recovered = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  #expect(recovered.source == .recovery)
  #expect(recovered.workspace.notes.first?.body == original.body)

  var invalidLastSequenceJournal = journal
  invalidLastSequenceJournal["historyFloor"] = UInt64.max
  invalidLastSequenceJournal["lastSequence"] = UInt64.max
  invalidLastSequenceJournal["records"] = []
  var outOfDomainDecodeFailed = false
  do {
    _ = try decoder.decode(
      AgentEventJournal.self,
      from: canonicalJSON(invalidLastSequenceJournal)
    )
  } catch {
    outOfDomainDecodeFailed = true
  }
  #expect(outOfDomainDecodeFailed)
}

@Test func sequenceExhaustionFailsClosedAfterTheLastLegalEvent() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let original = Note(title: "Boundary", body: "base", createdAt: date, modifiedAt: date)
  _ = try LocalStoreSnapshotWriter(rootURL: root, now: { date }).save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id),
    preferences: .init(),
    generation: 0
  )
  try installJournalSequences([UInt64.max - 2], at: root)

  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  let snapshot = try writer.loadSnapshot()
  var boundaryWorkspace = snapshot.workspace
  let epoch = try journalObject(at: root)["epoch"] as? String
  let boundaryNote = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
    title: "Last legal sequence",
    body: "one event",
    createdAt: date,
    modifiedAt: date
  )
  boundaryWorkspace.notes.append(boundaryNote)
  #expect(
    try writer.save(
      workspace: boundaryWorkspace,
      preferences: .init(),
      generation: 1
    ) == .committed
  )
  let lastLegalJournal = try journalObject(at: root)
  let lastLegalRecords = try journalRecords(lastLegalJournal)
  let lastLegalIDs = lastLegalRecords.compactMap { $0["eventID"] as? String }
  #expect(lastLegalJournal["lastSequence"] as? UInt64 == UInt64.max - 1)
  #expect(
    lastLegalRecords.compactMap { $0["sequence"] as? UInt64 } == [UInt64.max - 2, UInt64.max - 1])

  let reopenedWriter = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  var reopened = try reopenedWriter.loadSnapshot()
  #expect(reopened.source == .root)
  #expect(reopened.workspace.notes.contains { $0.id == boundaryNote.id })
  #expect(
    try reopenedWriter.save(
      workspace: reopened.workspace,
      preferences: .init(fontFamily: "Menlo"),
      generation: 1
    ) == .committed
  )
  let afterPreferenceSave = try journalObject(at: root)
  #expect(afterPreferenceSave["epoch"] as? String == epoch)
  #expect(
    try journalRecords(afterPreferenceSave).compactMap { $0["eventID"] as? String } == lastLegalIDs)

  reopened = try reopenedWriter.loadSnapshot()
  let journalBeforeNoOp = try canonicalJSON(journalObject(at: root))
  #expect(
    try reopenedWriter.save(
      workspace: reopened.workspace,
      preferences: .init(fontFamily: "Menlo"),
      generation: 1
    ) == .committed
  )
  #expect(try canonicalJSON(journalObject(at: root)) == journalBeforeNoOp)

  let manifestURL = root.appendingPathComponent("workspace.json")
  let manifestBeforeFailure = try Data(contentsOf: manifestURL)
  let filesBeforeFailure = try rootFileContents(excludingRecoveryAt: root)
  let journalBeforeFailure = try journalObject(at: root)
  let hashBeforeFailure = try jsonObject(at: manifestURL)["agentEventJournalSHA256"] as? String
  let eventIDsBeforeFailure = try journalRecords(journalBeforeFailure).compactMap {
    $0["eventID"] as? String
  }
  var rejectedWorkspace = reopened.workspace
  let rejectedNote = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
    title: "Beyond the sequence boundary",
    body: "rejected",
    createdAt: date,
    modifiedAt: date
  )
  rejectedWorkspace.notes.append(rejectedNote)
  var appendFailed = false
  do {
    _ = try reopenedWriter.save(
      workspace: rejectedWorkspace,
      preferences: .init(fontFamily: "Menlo"),
      generation: 2
    )
  } catch {
    appendFailed = true
  }
  #expect(appendFailed)
  #expect(try Data(contentsOf: manifestURL) == manifestBeforeFailure)
  #expect(try rootFileContents(excludingRecoveryAt: root) == filesBeforeFailure)
  let journalAfterFailure = try journalObject(at: root)
  #expect(journalAfterFailure["epoch"] as? String == journalBeforeFailure["epoch"] as? String)
  #expect(
    journalAfterFailure["lastSequence"] as? UInt64
      == journalBeforeFailure["lastSequence"] as? UInt64
  )
  #expect(
    journalAfterFailure["historyFloor"] as? UInt64
      == journalBeforeFailure["historyFloor"] as? UInt64
  )
  #expect(
    try journalRecords(journalAfterFailure).compactMap { $0["eventID"] as? String }
      == eventIDsBeforeFailure
  )
  #expect(
    try jsonObject(at: manifestURL)["agentEventJournalSHA256"] as? String
      == hashBeforeFailure
  )

  let expirationDate = date.addingTimeInterval(8 * 24 * 60 * 60)
  let expirationWriter = LocalStoreSnapshotWriter(rootURL: root, now: { expirationDate })
  let beforeExpiration = try expirationWriter.loadSnapshot()
  #expect(
    try expirationWriter.save(
      workspace: beforeExpiration.workspace,
      preferences: .init(fontFamily: "Menlo"),
      generation: 2
    ) == .committed
  )
  let trimmedJournal = try journalObject(at: root)
  #expect(trimmedJournal["epoch"] as? String == epoch)
  #expect(trimmedJournal["lastSequence"] as? UInt64 == UInt64.max - 1)
  #expect(trimmedJournal["historyFloor"] as? UInt64 == UInt64.max)
  #expect(try journalRecords(trimmedJournal).isEmpty)
  #expect(try expirationWriter.loadSnapshot().source == .root)
}

@Test func multiEventSaveThatCrossesSequenceLimitCommitsNoPrefix() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let original = Note(title: "Multi-event", body: "base", createdAt: date, modifiedAt: date)
  _ = try LocalStoreSnapshotWriter(rootURL: root, now: { date }).save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id),
    preferences: .init(),
    generation: 0
  )
  try installJournalSequences([UInt64.max - 2], at: root)

  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  let snapshot = try writer.loadSnapshot()
  var multiEventWorkspace = snapshot.workspace
  let manifestURL = root.appendingPathComponent("workspace.json")
  let manifestBeforeFailure = try Data(contentsOf: manifestURL)
  let filesBeforeFailure = try rootFileContents(excludingRecoveryAt: root)
  let journalBeforeFailure = try journalObject(at: root)
  let hashBeforeFailure = try jsonObject(at: manifestURL)["agentEventJournalSHA256"] as? String
  let eventIDsBeforeFailure = try journalRecords(journalBeforeFailure).compactMap {
    $0["eventID"] as? String
  }
  multiEventWorkspace.notes.append(
    Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
      title: "First of two",
      body: "fits",
      createdAt: date,
      modifiedAt: date
    )
  )
  multiEventWorkspace.notes.append(
    Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
      title: "Second of two",
      body: "does not fit",
      createdAt: date,
      modifiedAt: date
    )
  )

  var appendFailed = false
  do {
    _ = try writer.save(
      workspace: multiEventWorkspace,
      preferences: .init(),
      generation: 1
    )
  } catch {
    appendFailed = true
  }
  #expect(appendFailed)
  #expect(try Data(contentsOf: manifestURL) == manifestBeforeFailure)
  #expect(try rootFileContents(excludingRecoveryAt: root) == filesBeforeFailure)
  let journalAfterFailure = try journalObject(at: root)
  #expect(journalAfterFailure["epoch"] as? String == journalBeforeFailure["epoch"] as? String)
  #expect(
    try jsonObject(at: manifestURL)["agentEventJournalSHA256"] as? String
      == hashBeforeFailure
  )
  #expect(
    try journalRecords(journalAfterFailure).compactMap { $0["eventID"] as? String }
      == eventIDsBeforeFailure
  )
}

@Test func journalHistoryIsBoundedByCountAndCanonicalBytes() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let firstFolder = try Folder(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
    name: "First"
  )
  let secondFolder = try Folder(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
    name: "Second"
  )
  let notes = (0..<3_000).map { _ in
    Note(
      title: "Bounded",
      body: "",
      createdAt: date,
      modifiedAt: date,
      folderID: firstFolder.id
    )
  }
  let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try writer.save(
    workspace: Workspace(
      notes: notes,
      selectedNoteID: notes.first?.id,
      folders: [firstFolder, secondFolder]
    ),
    preferences: .init(),
    generation: 0
  )
  let afterCreation = try journalObject(at: root)
  #expect(try journalRecords(afterCreation).count == 3_000)
  #expect(try canonicalJSON(afterCreation).count <= 1_048_576)

  var movedNotes = notes
  for index in movedNotes.indices {
    movedNotes[index].folderID = secondFolder.id
  }
  _ = try writer.save(
    workspace: Workspace(
      notes: movedNotes,
      selectedNoteID: movedNotes.first?.id,
      folders: [firstFolder, secondFolder]
    ),
    preferences: .init(),
    generation: 0
  )

  let bounded = try journalObject(at: root)
  let records = try journalRecords(bounded)
  #expect(records.count <= 4_096)
  #expect(records.count < 4_096)
  #expect(try canonicalJSON(bounded).count <= 1_048_576)
  #expect(bounded["historyIncomplete"] as? Bool == true)
  let sequences = records.compactMap { $0["sequence"] as? Int }
  #expect(sequences == sequences.sorted())
  #expect(sequences.first.map { $0 > 1 } == true)
  #expect(bounded["historyFloor"] as? Int == sequences.first)
}

@Test func expiredHistoryMovesTheDurableFloor() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let start = Date(timeIntervalSince1970: 1_800_000_000)
  var notes = [Note(title: "One", createdAt: start, modifiedAt: start)]
  _ = try LocalStoreSnapshotWriter(rootURL: root, now: { start }).save(
    workspace: Workspace(notes: notes, selectedNoteID: notes[0].id),
    preferences: .init(),
    generation: 0
  )

  let sevenDays = start.addingTimeInterval(7 * 24 * 60 * 60)
  notes.append(Note(title: "Two", createdAt: sevenDays, modifiedAt: sevenDays))
  _ = try LocalStoreSnapshotWriter(rootURL: root, now: { sevenDays }).save(
    workspace: Workspace(notes: notes, selectedNoteID: notes[0].id),
    preferences: .init(),
    generation: 0
  )
  #expect(try journalRecords(journalObject(at: root)).count == 2)

  let beyondSevenDays = sevenDays.addingTimeInterval(1)
  notes.append(Note(title: "Three", createdAt: beyondSevenDays, modifiedAt: beyondSevenDays))
  _ = try LocalStoreSnapshotWriter(rootURL: root, now: { beyondSevenDays }).save(
    workspace: Workspace(notes: notes, selectedNoteID: notes[0].id),
    preferences: .init(),
    generation: 0
  )
  let journal = try journalObject(at: root)
  let records = try journalRecords(journal)
  #expect(records.compactMap { $0["sequence"] as? Int } == [2, 3])
  #expect(journal["historyIncomplete"] as? Bool == true)
  #expect(journal["historyFloor"] as? Int == 2)
}

@Test func manifestHooksPreserveJournalAcrossBeforeAndAfterCommitFailures() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventJournalTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let original = Note(title: "Atomic", body: "old", createdAt: date, modifiedAt: date)
  let baseWriter = LocalStoreSnapshotWriter(rootURL: root, now: { date })
  _ = try baseWriter.save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id),
    preferences: .init(),
    generation: 0
  )
  let beforeEpoch = try journalObject(at: root)["epoch"] as? String

  var changed = original
  changed.body = "new"
  changed.revision = 1
  let failingWriter = LocalStoreSnapshotWriter(
    rootURL: root,
    now: { date.addingTimeInterval(1) },
    hooks: .init(beforeManifestCommit: { _ in
      throw AgentEventJournalTestFailure.beforeManifestCommit
    })
  )
  #expect(throws: AgentEventJournalTestFailure.beforeManifestCommit) {
    try failingWriter.save(
      workspace: Workspace(notes: [changed], selectedNoteID: changed.id),
      preferences: .init(),
      generation: 1
    )
  }
  let preCommitRecovery = try journalObject(at: root.appendingPathComponent("Recovery"))
  #expect(try journalRecords(preCommitRecovery).count == 1)

  let retryWriter = LocalStoreSnapshotWriter(
    rootURL: root,
    now: { date.addingTimeInterval(2) }
  )
  _ = try retryWriter.save(
    workspace: Workspace(notes: [changed], selectedNoteID: changed.id),
    preferences: .init(),
    generation: 1
  )
  let retried = try journalObject(at: root)
  #expect(retried["epoch"] as? String != beforeEpoch)
  #expect(retried["historyIncomplete"] as? Bool == true)
  #expect(try journalRecords(retried).count == 2)

  var changedAgain = changed
  changedAgain.body = "committed despite hook error"
  changedAgain.revision = 2
  let afterCommitWriter = LocalStoreSnapshotWriter(
    rootURL: root,
    now: { date.addingTimeInterval(3) },
    hooks: .init(afterManifestCommit: { _ in
      throw AgentEventJournalTestFailure.beforeManifestCommit
    })
  )
  #expect(
    try afterCommitWriter.save(
      workspace: Workspace(notes: [changedAgain], selectedNoteID: changedAgain.id),
      preferences: .init(),
      generation: 2
    ) == .committed
  )
  let committedJournal = try journalObject(at: root)
  let committedIDs = try journalRecords(committedJournal).compactMap { $0["eventID"] as? String }
  #expect(committedIDs.count == 3)
  _ = try LocalStoreSnapshotWriter(rootURL: root).loadSnapshot()
  _ = try afterCommitWriter.save(
    workspace: Workspace(notes: [changedAgain], selectedNoteID: changedAgain.id),
    preferences: .init(),
    generation: 2
  )
  #expect(
    try journalRecords(journalObject(at: root)).compactMap { $0["eventID"] as? String }
      == committedIDs
  )
}
