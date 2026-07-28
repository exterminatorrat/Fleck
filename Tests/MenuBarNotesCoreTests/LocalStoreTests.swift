import Foundation
import Testing

@testable import MenuBarNotesCore

@Test func storeRoundTripsWorkspaceAndPreferences() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("MenuBarNotesTests-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }

  let store = LocalStore(rootURL: root)
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let note = Note(
    title: "Shopping",
    body: "- Tea\n- Coffee",
    createdAt: date,
    modifiedAt: date,
    agentAccess: true,
    revision: 7
  )
  let workspace = Workspace(notes: [note], selectedNoteID: note.id)
  let preferences = AppPreferences(fontFamily: "Avenir", accentHex: "#336699")

  try await store.save(workspace: workspace, preferences: preferences)

  #expect(try await store.loadWorkspace() == workspace)
  #expect(try await store.loadPreferences() == preferences)
  #expect(
    FileManager.default.fileExists(
      atPath: root.appendingPathComponent("\(note.id.uuidString.lowercased()).md").path
    ))
}

@Test func storeRoundTripsOptionalRichTextSidecar() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let rtf = Data("{\\rtf1 formatted}".utf8)
  let note = Note(title: "Formatted", body: "formatted", richTextRTF: rtf)

  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id), preferences: .init())
  #expect(try await store.loadWorkspace().notes.first?.richTextRTF == rtf)
  #expect(
    FileManager.default.fileExists(
      atPath:
        root
        .appendingPathComponent("\(note.id.uuidString.lowercased()).rtf").path))
}

@Test func storeRemovesFilesForDeletedNotes() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("MenuBarNotesTests-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }

  let store = LocalStore(rootURL: root)
  let first = Note(title: "First")
  let second = Note(title: "Second", richTextRTF: Data("{\\rtf1 second}".utf8))
  try await store.save(
    workspace: Workspace(notes: [first, second], selectedNoteID: first.id),
    preferences: AppPreferences()
  )
  try await store.save(
    workspace: Workspace(notes: [first], selectedNoteID: first.id),
    preferences: AppPreferences()
  )

  #expect(
    !FileManager.default.fileExists(
      atPath: root.appendingPathComponent("\(second.id.uuidString.lowercased()).md").path
    ))
  #expect(
    !FileManager.default.fileExists(
      atPath: root.appendingPathComponent("\(second.id.uuidString.lowercased()).rtf").path
    ))
}

@Test func malformedManifestRecoversPreviousGeneration() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let original = Note(title: "Recover me", body: "safe body")
  try await store.save(
    workspace: Workspace(notes: [original], selectedNoteID: original.id), preferences: .init())

  var changed = original
  changed.body = "new body"
  try await store.save(
    workspace: Workspace(notes: [changed], selectedNoteID: changed.id), preferences: .init())
  try Data("not json".utf8).write(to: root.appendingPathComponent("workspace.json"))

  let recovered = try await store.loadWorkspace()
  #expect(recovered.notes.first?.body == "safe body")
}

@Test func malformedPreferencesFallBackWithoutFailing() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data("broken".utf8).write(to: root.appendingPathComponent("preferences.json"))

  #expect(try await LocalStore(rootURL: root).loadPreferences() == AppPreferences())
}

@Test func missingAndInvalidNoteFilesDoNotPreventWorkspaceLoading() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let note = Note(title: "Damaged")
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id), preferences: .init())
  try Data([0xff]).write(to: root.appendingPathComponent("\(note.id.uuidString.lowercased()).md"))

  let loaded = try await store.loadWorkspace()
  #expect(loaded.notes.count == 1)
  #expect(loaded.notes[0].id != note.id)
}

@Test func manifestRecordsFormatVersion() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  try await store.save(workspace: Workspace(notes: [Note()]), preferences: .init())
  let object = try JSONSerialization.jsonObject(
    with: Data(contentsOf: root.appendingPathComponent("workspace.json")))
  let manifest = try #require(object as? [String: Any])
  #expect(manifest["formatVersion"] as? Int == 1)
}

@Test func oldManifestDefaultsAgentFields() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data(
    """
    {
      "formatVersion": 1,
      "noteOrder": ["\(id.uuidString)"],
      "selectedNoteID": "\(id.uuidString)",
      "metadata": [
        "\(id.uuidString)",
        {
          "title": "Legacy",
          "createdAt": "1970-01-01T00:00:00Z",
          "modifiedAt": "1970-01-01T00:00:00Z",
          "isPinned": false
        }
      ]
    }
    """.utf8
  ).write(to: root.appendingPathComponent("workspace.json"))
  try "Legacy body".write(
    to: root.appendingPathComponent("\(id.uuidString.lowercased()).md"),
    atomically: true,
    encoding: .utf8
  )

  let note = try #require(await LocalStore(rootURL: root).loadWorkspace().notes.first)

  #expect(note.id == id)
  #expect(note.agentAccess == false)
  #expect(note.revision == 0)
}

@Test func storeArchivesDeletedNoteBodyMetadataAndRichText() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let deleted = Note(
    title: "Formatted",
    body: "kept body",
    richTextRTF: Data("{\\rtf1 kept formatting}".utf8),
    createdAt: deletedAt.addingTimeInterval(-120),
    modifiedAt: deletedAt.addingTimeInterval(-60),
    isPinned: true,
    agentAccess: true,
    revision: 9
  )
  let remaining = Note(
    title: "Remaining",
    createdAt: deletedAt.addingTimeInterval(-30),
    modifiedAt: deletedAt.addingTimeInterval(-30)
  )
  let store = LocalStore(rootURL: root, now: { deletedAt })

  try await store.save(
    workspace: Workspace(notes: [remaining], selectedNoteID: remaining.id),
    preferences: .init(),
    trashedNotes: [deleted]
  )

  let trash = try await store.loadTrash()
  #expect(trash == [TrashedNote(note: deleted, deletedAt: deletedAt)])

  let entryURL = trashEntryURL(root: root, noteID: deleted.id)
  #expect(
    try String(contentsOf: entryURL.appendingPathComponent("body.md"), encoding: .utf8)
      == deleted.body
  )
  #expect(
    try Data(contentsOf: entryURL.appendingPathComponent("rich-text.rtf"))
      == deleted.richTextRTF
  )
  let metadataObject = try JSONSerialization.jsonObject(
    with: Data(contentsOf: entryURL.appendingPathComponent("metadata.json"))
  )
  let metadata = try #require(metadataObject as? [String: Any])
  #expect(metadata["id"] as? String == deleted.id.uuidString)
  #expect(metadata["title"] as? String == deleted.title)
  #expect(metadata["isPinned"] as? Bool == true)
  #expect(metadata["agentAccess"] as? Bool == true)
  #expect(metadata["revision"] as? Int == 9)
  #expect(metadata["deletedAt"] != nil)
}

@Test func oldTrashMetadataDefaultsAgentFields() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let entryURL = trashEntryURL(root: root, noteID: id)
  try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
  try Data(
    """
    {
      "id": "\(id.uuidString)",
      "title": "Legacy trash",
      "createdAt": "1970-01-01T00:00:00Z",
      "modifiedAt": "1970-01-01T00:00:00Z",
      "isPinned": false,
      "deletedAt": "1970-01-02T00:00:00Z"
    }
    """.utf8
  ).write(to: entryURL.appendingPathComponent("metadata.json"))
  try "Legacy trash body".write(
    to: entryURL.appendingPathComponent("body.md"),
    atomically: true,
    encoding: .utf8
  )

  let note = try #require(
    await LocalStore(
      rootURL: root,
      now: { Date(timeIntervalSince1970: 86_401) }
    ).loadTrash().first?.note
  )

  #expect(note.id == id)
  #expect(note.agentAccess == false)
  #expect(note.revision == 0)
}

@Test func trashRetainsEntriesUntilThirtyDaysThenPurgesThem() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let deleted = Note(title: "Expires", body: "after thirty days")
  let remaining = Note(title: "Remaining")
  try await LocalStore(rootURL: root, now: { deletedAt }).save(
    workspace: Workspace(notes: [remaining], selectedNoteID: remaining.id),
    preferences: .init(),
    trashedNotes: [deleted]
  )

  let beforeExpiry = deletedAt.addingTimeInterval((30 * 24 * 60 * 60) - 1)
  #expect(try await LocalStore(rootURL: root, now: { beforeExpiry }).loadTrash().count == 1)

  let atExpiry = deletedAt.addingTimeInterval(30 * 24 * 60 * 60)
  #expect(try await LocalStore(rootURL: root, now: { atExpiry }).loadTrash().isEmpty)
  #expect(
    !FileManager.default.fileExists(atPath: trashEntryURL(root: root, noteID: deleted.id).path))
}

@Test func retryingTrashArchiveKeepsTheOriginalDeletionDate() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let firstDeletedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let retryDate = firstDeletedAt.addingTimeInterval(7 * 24 * 60 * 60)
  let deleted = Note(title: "Retry", body: "do not reset my clock")
  let remaining = Note(title: "Remaining")
  let workspace = Workspace(notes: [remaining], selectedNoteID: remaining.id)

  try await LocalStore(rootURL: root, now: { firstDeletedAt }).save(
    workspace: workspace,
    preferences: .init(),
    trashedNotes: [deleted]
  )
  let retryingStore = LocalStore(rootURL: root, now: { retryDate })
  try await retryingStore.save(
    workspace: workspace,
    preferences: .init(),
    trashedNotes: [deleted]
  )

  #expect(try await retryingStore.loadTrash().first?.deletedAt == firstDeletedAt)
}

@Test func malformedTrashEntryDoesNotBlockOrDeleteValidEntries() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let deleted = Note(title: "Valid")
  let remaining = Note(title: "Remaining")
  let store = LocalStore(rootURL: root, now: { deletedAt })
  try await store.save(
    workspace: Workspace(notes: [remaining], selectedNoteID: remaining.id),
    preferences: .init(),
    trashedNotes: [deleted]
  )

  let malformedURL = root.appendingPathComponent("Trash/Malformed", isDirectory: true)
  try FileManager.default.createDirectory(at: malformedURL, withIntermediateDirectories: true)
  try Data("not json".utf8).write(to: malformedURL.appendingPathComponent("metadata.json"))

  #expect(try await store.loadTrash().map(\.id) == [deleted.id])
  #expect(FileManager.default.fileExists(atPath: malformedURL.path))
}

@Test func restoringTrashPreservesIdentityContentAndFormatting() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let deleted = Note(
    title: "Restore me",
    body: "readable content",
    richTextRTF: Data("{\\rtf1 restored formatting}".utf8),
    createdAt: deletedAt.addingTimeInterval(-120),
    modifiedAt: deletedAt.addingTimeInterval(-60),
    isPinned: true
  )
  let remaining = Note(
    title: "Remaining",
    createdAt: deletedAt.addingTimeInterval(-30),
    modifiedAt: deletedAt.addingTimeInterval(-30)
  )
  let activeWorkspace = Workspace(notes: [remaining], selectedNoteID: remaining.id)
  let preferences = AppPreferences(accentHex: "#112233")
  let store = LocalStore(rootURL: root, now: { deletedAt })
  try await store.save(
    workspace: activeWorkspace,
    preferences: preferences,
    trashedNotes: [deleted]
  )
  let trashedNote = try #require(await store.loadTrash().first)

  let restoredWorkspace = try await store.restore(
    trashedNote,
    into: activeWorkspace,
    preferences: preferences
  )

  #expect(restoredWorkspace.selectedNoteID == deleted.id)
  #expect(restoredWorkspace.notes.last == deleted)
  #expect(try await store.loadWorkspace() == restoredWorkspace)
  #expect(try await store.loadPreferences() == preferences)
  #expect(
    !FileManager.default.fileExists(atPath: trashEntryURL(root: root, noteID: deleted.id).path))
}

@Test func tabColorRoundTripsThroughTrashAndRestore() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let colored = Note(title: "Colored", tabColorHex: "#BF5AF2")
  let remaining = Note(title: "Remaining")
  let activeWorkspace = Workspace(notes: [remaining], selectedNoteID: remaining.id)
  let store = LocalStore(rootURL: root, now: { deletedAt })

  try await store.save(
    workspace: activeWorkspace,
    preferences: .init(),
    trashedNotes: [colored]
  )
  let trashedNote = try #require(await store.loadTrash().first)
  #expect(trashedNote.note.tabColorHex == "#BF5AF2")

  let restoredWorkspace = try await store.restore(
    trashedNote,
    into: activeWorkspace,
    preferences: .init()
  )
  #expect(restoredWorkspace.notes.last?.tabColorHex == "#BF5AF2")
  #expect(try await store.loadWorkspace().notes.last?.tabColorHex == "#BF5AF2")
}

@Test func snapshotWriterRejectsOlderGenerationWithoutTouchingDisk() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  let newer = Note(title: "Newer")
  let older = Note(title: "Older")

  #expect(
    try writer.save(
      workspace: Workspace(notes: [newer], selectedNoteID: newer.id),
      preferences: .init(),
      generation: 2
    ) == .committed
  )
  #expect(
    try writer.save(
      workspace: Workspace(notes: [older], selectedNoteID: older.id),
      preferences: .init(),
      generation: 1
    ) == .superseded
  )
  #expect(try writer.loadSnapshot().workspace.notes.map(\.title) == ["Newer"])
}

@Test func supersededDeleteSnapshotCannotRearchiveARestoredNote() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let deleted = Note(
    title: "Restored",
    createdAt: date,
    modifiedAt: date
  )
  let remaining = Note(
    title: "Remaining",
    createdAt: date,
    modifiedAt: date
  )
  let activeWorkspace = Workspace(notes: [remaining], selectedNoteID: remaining.id)
  let store = LocalStore(rootURL: root)

  #expect(
    try await store.save(
      workspace: activeWorkspace,
      preferences: .init(),
      trashedNotes: [deleted],
      generation: 2
    ) == .committed
  )
  let trashed = try #require(await store.loadTrash().first)
  let restoredWorkspace = try await store.restore(
    trashed,
    into: activeWorkspace,
    preferences: .init(),
    generation: 3
  )
  #expect(try await store.loadTrash().isEmpty)

  #expect(
    try await store.save(
      workspace: activeWorkspace,
      preferences: .init(),
      trashedNotes: [deleted],
      generation: 2
    ) == .superseded
  )
  #expect(try await store.loadTrash().isEmpty)
  #expect(try await store.loadSnapshot().workspace == restoredWorkspace)
}

@Test func failedSnapshotGenerationRemainsRetryable() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let failure = SnapshotFailureController(failingGeneration: 3)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      try failure.failOnce(generation)
    })
  )
  let note = Note(title: "Retry")
  let workspace = Workspace(notes: [note], selectedNoteID: note.id)

  #expect(throws: SnapshotTestError.failed) {
    try writer.save(workspace: workspace, preferences: .init(), generation: 3)
  }
  #expect(
    try writer.save(workspace: workspace, preferences: .init(), generation: 3)
      == .committed
  )
}

@Test func failedNewerGenerationSupersedesOlderButRemainsRetryable() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let failure = SnapshotFailureController(failingGeneration: 3)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      try failure.failOnce(generation)
    })
  )
  let newer = Note(title: "Newer")
  let older = Note(title: "Older")

  #expect(throws: SnapshotTestError.failed) {
    try writer.save(
      workspace: Workspace(notes: [newer], selectedNoteID: newer.id),
      preferences: .init(),
      generation: 3
    )
  }
  #expect(
    try writer.save(
      workspace: Workspace(notes: [older], selectedNoteID: older.id),
      preferences: .init(),
      generation: 2
    ) == .superseded
  )
  #expect(
    try writer.save(
      workspace: Workspace(notes: [newer], selectedNoteID: newer.id),
      preferences: .init(),
      generation: 3
    ) == .committed
  )
}

@Test func supersededRestoreKeepsTheOnlyTrashCopy() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let deleted = Note(
    title: "Only copy",
    body: "Recover me",
    createdAt: date,
    modifiedAt: date
  )
  let remaining = Note(
    title: "Remaining",
    createdAt: date,
    modifiedAt: date
  )
  let active = Workspace(notes: [remaining], selectedNoteID: remaining.id)

  _ = try await store.save(
    workspace: active,
    preferences: .init(),
    trashedNotes: [deleted],
    generation: 2
  )
  _ = try await store.save(
    workspace: active,
    preferences: .init(),
    generation: 4
  )
  let trashed = try #require(await store.loadTrash().first)

  await #expect(throws: LocalStore.StoreError.self) {
    try await store.restore(
      trashed,
      into: active,
      preferences: .init(),
      generation: 3
    )
  }

  #expect(try await store.loadTrash().map(\.id) == [deleted.id])
  #expect(try await store.loadSnapshot().workspace == active)
}

@Test func trashArchiveCompletesBeforeManifestCommit() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { _ in
      throw SnapshotTestError.failed
    })
  )
  let deleted = Note(title: "Recoverable", body: "Keep me")
  let remaining = Note(title: "Remaining")

  #expect(throws: SnapshotTestError.failed) {
    try writer.save(
      workspace: Workspace(notes: [remaining], selectedNoteID: remaining.id),
      preferences: .init(),
      generation: 1,
      trashedNotes: [deleted]
    )
  }
  let entryURL = trashEntryURL(root: root, noteID: deleted.id)
  #expect(
    try String(
      contentsOf: entryURL.appendingPathComponent("body.md"),
      encoding: .utf8
    ) == deleted.body
  )
}

@Test func snapshotIntegrityCouplesWorkspaceAndPreferencesToRecovery() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let first = Note(title: "First", body: "First body")
  try await store.save(
    workspace: Workspace(notes: [first], selectedNoteID: first.id),
    preferences: AppPreferences(fontFamily: "Menlo"),
    generation: 1
  )
  let second = Note(title: "Second", body: "Second body")
  try await store.save(
    workspace: Workspace(notes: [second], selectedNoteID: second.id),
    preferences: AppPreferences(fontFamily: "Avenir"),
    generation: 2
  )
  try Data("corrupt".utf8).write(
    to: root.appendingPathComponent("preferences.json")
  )

  let snapshot = try await store.loadSnapshot()

  #expect(snapshot.source == .recovery)
  #expect(snapshot.workspace.notes.map(\.title) == ["First"])
  #expect(snapshot.preferences.fontFamily == "Menlo")
}

@Test func snapshotManifestCommitsExactHashesAndAgentProof() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let note = Note(title: "Shared", body: "Body", agentAccess: true, revision: 2)
  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(),
    noteID: note.id,
    resultingRevision: note.revision,
    bodySHA256:
      "6ccaa6415b5ee449e3c0e6150de1203414a8bb8dfcf7a595702f18c5412a3f6e",
    actor: .localUser,
    operationID: UUID(),
    expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
  )

  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: AppPreferences(fontFamily: "Menlo"),
    generation: 4,
    commitProof: proof
  )
  let snapshot = try await store.loadSnapshot()

  #expect(snapshot.source == .root)
  #expect(snapshot.commitProofs == [proof])
  let manifest = try #require(
    try JSONSerialization.jsonObject(
      with: Data(contentsOf: root.appendingPathComponent("workspace.json"))
    ) as? [String: Any]
  )
  #expect(manifest["snapshotIntegrityVersion"] as? Int == 1)
  #expect(manifest["preferencesSHA256"] as? String != nil)
  let markdownHashes = try #require(manifest["markdownSHA256"] as? [String: String])
  #expect(markdownHashes[note.id.uuidString.lowercased()] != nil)
}

@Test func preferencesOnlyPrecommitFailureFallsBackToPreviousCompleteGeneration() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let first = Note(title: "First")
  try await store.save(
    workspace: Workspace(notes: [first], selectedNoteID: first.id),
    preferences: AppPreferences(fontFamily: "Menlo"),
    generation: 1
  )
  let failure = SnapshotFailureController(failingGeneration: 2)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      try failure.failOnce(generation)
    })
  )
  let second = Note(title: "Second")

  #expect(throws: SnapshotTestError.failed) {
    try writer.save(
      workspace: Workspace(notes: [second], selectedNoteID: second.id),
      preferences: AppPreferences(fontFamily: "Avenir"),
      generation: 2
    )
  }
  let snapshot = try writer.loadSnapshot()

  #expect(snapshot.source == .recovery)
  #expect(snapshot.workspace.notes.map(\.title) == ["First"])
  #expect(snapshot.preferences.fontFamily == "Menlo")
}

@Test func snapshotWriterSerializesNewerThenOlderAsCommittedThenSuperseded() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      guard generation == 2 else { return }
      entered.signal()
      release.wait()
    })
  )
  let newer = Note(title: "Newer")
  let older = Note(title: "Older")
  let newerTask = Task.detached {
    try writer.save(
      workspace: Workspace(notes: [newer], selectedNoteID: newer.id),
      preferences: .init(),
      generation: 2
    )
  }
  await wait(for: entered)
  let olderTask = Task.detached {
    try writer.save(
      workspace: Workspace(notes: [older], selectedNoteID: older.id),
      preferences: .init(),
      generation: 1
    )
  }
  release.signal()

  #expect(try await newerTask.value == .committed)
  #expect(try await olderTask.value == .superseded)
  #expect(try writer.loadSnapshot().workspace.notes.map(\.title) == ["Newer"])
}

@Test func snapshotWriterSerializesOlderThenNewerAndLeavesNewerOnDisk() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      guard generation == 1 else { return }
      entered.signal()
      release.wait()
    })
  )
  let older = Note(title: "Older")
  let newer = Note(title: "Newer")
  let olderTask = Task.detached {
    try writer.save(
      workspace: Workspace(notes: [older], selectedNoteID: older.id),
      preferences: .init(),
      generation: 1
    )
  }
  await wait(for: entered)
  let newerTask = Task.detached {
    try writer.save(
      workspace: Workspace(notes: [newer], selectedNoteID: newer.id),
      preferences: .init(),
      generation: 2
    )
  }
  release.signal()

  #expect(try await olderTask.value == .committed)
  #expect(try await newerTask.value == .committed)
  #expect(try writer.loadSnapshot().workspace.notes.map(\.title) == ["Newer"])
}

@Test func postManifestMaintenanceFailureDoesNotTurnCommitIntoFailure() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(afterManifestCommit: { _ in
      throw SnapshotTestError.failed
    })
  )
  let note = Note(title: "Committed")

  #expect(
    try writer.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init(),
      generation: 1
    ) == .committed
  )
  #expect(
    try writer.loadSnapshot().workspace.notes.map(\.title)
      == ["Committed"]
  )
}

@Test func missingPreferencesRejectRootAndLoadsWorkspaceAndPreferencesFromRecovery()
  async throws
{
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let first = Note(title: "First")
  try await store.save(
    workspace: Workspace(notes: [first], selectedNoteID: first.id),
    preferences: AppPreferences(fontFamily: "Menlo"),
    generation: 1
  )
  let second = Note(title: "Second")
  try await store.save(
    workspace: Workspace(notes: [second], selectedNoteID: second.id),
    preferences: AppPreferences(fontFamily: "Avenir"),
    generation: 2
  )
  try FileManager.default.removeItem(
    at: root.appendingPathComponent("preferences.json")
  )

  let snapshot = try await store.loadSnapshot()

  #expect(snapshot.source == .recovery)
  #expect(snapshot.workspace.notes.map(\.title) == ["First"])
  #expect(snapshot.preferences.fontFamily == "Menlo")
}

@Test func invalidRootRetryPreservesLastValidRecoveryUntilNewManifestCommits()
  throws
{
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  let first = Note(title: "First", body: "safe")
  let second = Note(title: "Second", body: "new")
  _ = try writer.save(
    workspace: Workspace(notes: [first], selectedNoteID: first.id),
    preferences: .init(),
    generation: 1
  )
  _ = try writer.save(
    workspace: Workspace(notes: [second], selectedNoteID: second.id),
    preferences: .init(),
    generation: 2
  )
  try Data("corrupt".utf8).write(
    to: root.appendingPathComponent(
      "\(second.id.uuidString.lowercased()).md"
    )
  )
  let third = Note(title: "Third", body: "final")

  _ = try writer.save(
    workspace: Workspace(notes: [third], selectedNoteID: third.id),
    preferences: .init(),
    generation: 3
  )

  #expect(
    try String(
      contentsOf:
        root
        .appendingPathComponent("Recovery", isDirectory: true)
        .appendingPathComponent(
          "\(first.id.uuidString.lowercased()).md"
        ),
      encoding: .utf8
    ) == "safe"
  )
  #expect(try writer.loadSnapshot().workspace.notes.map(\.title) == ["Third"])
}

@Test func oldHashlessManifestLoadsAndAcquiresIntegrityOnNextSave() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: true
  )
  try Data(
    """
    {
      "formatVersion": 1,
      "noteOrder": ["\(id.uuidString)"],
      "selectedNoteID": "\(id.uuidString)",
      "metadata": [
        "\(id.uuidString)",
        {
          "title": "Legacy",
          "createdAt": "1970-01-01T00:00:00Z",
          "modifiedAt": "1970-01-01T00:00:00Z",
          "isPinned": false
        }
      ]
    }
    """.utf8
  ).write(to: root.appendingPathComponent("workspace.json"))
  try "legacy".write(
    to: root.appendingPathComponent("\(id.uuidString.lowercased()).md"),
    atomically: true,
    encoding: .utf8
  )
  let store = LocalStore(rootURL: root)
  let snapshot = try await store.loadSnapshot()

  _ = try await store.save(
    workspace: snapshot.workspace,
    preferences: snapshot.preferences,
    generation: 1
  )

  let manifest = try #require(
    try JSONSerialization.jsonObject(
      with: Data(contentsOf: root.appendingPathComponent("workspace.json"))
    ) as? [String: Any]
  )
  #expect(manifest["snapshotIntegrityVersion"] as? Int == 1)
  #expect(manifest["markdownSHA256"] as? [String: String] != nil)
  #expect(manifest["preferencesSHA256"] as? String != nil)
}

@Test func integritySnapshotNeverLoadsAnUnhashedRTFOrphan() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Plain", body: "Body")
  let store = LocalStore(rootURL: root)
  _ = try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 1
  )
  try Data("uncommitted sidecar".utf8).write(
    to: root.appendingPathComponent(
      "\(note.id.uuidString.lowercased()).rtf"
    )
  )

  let snapshot = try await store.loadSnapshot()

  #expect(snapshot.source == .root)
  #expect(snapshot.workspace.notes.first?.body == "Body")
  #expect(snapshot.workspace.notes.first?.richTextRTF == nil)
}

private func temporaryStoreURL() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID().uuidString)"
  )
}

private enum SnapshotTestError: Error {
  case failed
}

private func wait(for semaphore: DispatchSemaphore) async {
  await withCheckedContinuation { continuation in
    DispatchQueue.global().async {
      semaphore.wait()
      continuation.resume()
    }
  }
}

private final class SnapshotFailureController: @unchecked Sendable {
  private let lock = NSLock()
  private let generation: UInt64
  private var hasFailed = false

  init(failingGeneration: UInt64) {
    generation = failingGeneration
  }

  func failOnce(_ generation: UInt64) throws {
    try lock.withLock {
      guard generation == self.generation, !hasFailed else { return }
      hasFailed = true
      throw SnapshotTestError.failed
    }
  }
}

private func trashEntryURL(root: URL, noteID: UUID) -> URL {
  root
    .appendingPathComponent("Trash", isDirectory: true)
    .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
}
