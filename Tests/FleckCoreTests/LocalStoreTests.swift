import Foundation
import Testing

@testable import FleckCore

@Test func storeRoundTripsWorkspaceAndPreferences() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckTests-\(UUID().uuidString)")
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
    "FleckTests-\(UUID())")
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
    .appendingPathComponent("FleckTests-\(UUID().uuidString)")
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
    "FleckTests-\(UUID())")
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
    "FleckTests-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data("broken".utf8).write(to: root.appendingPathComponent("preferences.json"))

  #expect(try await LocalStore(rootURL: root).loadPreferences() == AppPreferences())
}

@Test func missingAndInvalidNoteFilesDoNotPreventWorkspaceLoading() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckTests-\(UUID())")
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
    "FleckTests-\(UUID())")
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
  let observedURLs = [
    noteFileURL(root: root, noteID: newer.id),
    root.appendingPathComponent("preferences.json"),
    root.appendingPathComponent("workspace.json"),
  ]
  for url in observedURLs {
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)],
      ofItemAtPath: url.path
    )
  }
  let before = try Dictionary(
    uniqueKeysWithValues: observedURLs.map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )
  #expect(
    try writer.save(
      workspace: Workspace(notes: [older], selectedNoteID: older.id),
      preferences: .init(),
      generation: 1
    ) == .superseded
  )
  #expect(
    try Dictionary(
      uniqueKeysWithValues: observedURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
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

@Test func contentEditRewritesOnlyChangedBodyAndRichTextFiles() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let first = Note(
    title: "First",
    body: "first body",
    richTextRTF: Data("{\\rtf1 first}".utf8)
  )
  let second = Note(
    title: "Second",
    body: "second body",
    richTextRTF: Data("{\\rtf1 second}".utf8)
  )
  let initialWorkspace = Workspace(
    notes: [first, second],
    selectedNoteID: first.id
  )
  try await store.save(
    workspace: initialWorkspace,
    preferences: .init(),
    generation: 1
  )

  let secondBodyURL = noteFileURL(root: root, noteID: second.id)
  let secondRTFURL = rtfFileURL(root: root, noteID: second.id)
  let sentinelDate = Date(timeIntervalSince1970: 1)
  for url in [secondBodyURL, secondRTFURL] {
    try FileManager.default.setAttributes(
      [.modificationDate: sentinelDate],
      ofItemAtPath: url.path
    )
  }
  let secondBodyBefore = try fileObservation(at: secondBodyURL)
  let secondRTFBefore = try fileObservation(at: secondRTFURL)

  var changedWorkspace = initialWorkspace
  changedWorkspace.updateContent(
    id: first.id,
    body: "first body updated",
    rtf: Data("{\\rtf1 first updated}".utf8),
    now: Date(timeIntervalSince1970: 2)
  )
  try await store.save(
    workspace: changedWorkspace,
    preferences: .init(),
    generation: 2
  )

  #expect(try fileObservation(at: secondBodyURL) == secondBodyBefore)
  #expect(try fileObservation(at: secondRTFURL) == secondRTFBefore)
  #expect(
    try Data(contentsOf: noteFileURL(root: root, noteID: first.id))
      == Data("first body updated".utf8)
  )
  #expect(
    try Data(contentsOf: rtfFileURL(root: root, noteID: first.id))
      == Data("{\\rtf1 first updated}".utf8)
  )
}

@Test func richTextOnlyEditRewritesOnlyTheChangedRichTextFile() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let first = Note(
    title: "First",
    body: "same body",
    richTextRTF: Data("{\\rtf1 first}".utf8)
  )
  let second = Note(
    title: "Second",
    body: "second body",
    richTextRTF: Data("{\\rtf1 second}".utf8)
  )
  let workspace = Workspace(
    notes: [first, second],
    selectedNoteID: first.id
  )
  try await store.save(workspace: workspace, preferences: .init(), generation: 1)

  let firstBodyURL = noteFileURL(root: root, noteID: first.id)
  let firstRTFURL = rtfFileURL(root: root, noteID: first.id)
  let secondBodyURL = noteFileURL(root: root, noteID: second.id)
  let secondRTFURL = rtfFileURL(root: root, noteID: second.id)
  let contentURLs = [firstBodyURL, firstRTFURL, secondBodyURL, secondRTFURL]
  for url in contentURLs {
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)],
      ofItemAtPath: url.path
    )
  }
  let before = try Dictionary(
    uniqueKeysWithValues: contentURLs.map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )

  var changedWorkspace = workspace
  changedWorkspace.updateContent(
    id: first.id,
    body: first.body,
    rtf: Data("{\\rtf1 first changed}".utf8),
    now: Date(timeIntervalSince1970: 2)
  )
  try await store.save(
    workspace: changedWorkspace,
    preferences: .init(),
    generation: 2
  )
  let after = try Dictionary(
    uniqueKeysWithValues: contentURLs.map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )
  #expect(after[firstBodyURL.lastPathComponent] == before[firstBodyURL.lastPathComponent])
  #expect(after[secondBodyURL.lastPathComponent] == before[secondBodyURL.lastPathComponent])
  #expect(after[secondRTFURL.lastPathComponent] == before[secondRTFURL.lastPathComponent])
  #expect(after[firstRTFURL.lastPathComponent] != before[firstRTFURL.lastPathComponent])
  #expect(try Data(contentsOf: firstBodyURL) == Data(first.body.utf8))
  #expect(try Data(contentsOf: firstRTFURL) == Data("{\\rtf1 first changed}".utf8))
}

@Test func metadataOnlySavesLeaveAllContentFilesUntouched() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let first = Note(
    title: "First",
    body: "first body",
    richTextRTF: Data("{\\rtf1 first}".utf8),
    createdAt: date,
    modifiedAt: date
  )
  let second = Note(
    title: "Second",
    body: "second body",
    richTextRTF: Data("{\\rtf1 second}".utf8),
    createdAt: date,
    modifiedAt: date
  )
  var workspace = Workspace(
    notes: [first, second],
    selectedNoteID: first.id
  )
  try await store.save(
    workspace: workspace,
    preferences: .init(),
    generation: 1
  )

  let contentURLs = workspace.notes.flatMap { note in
    [noteFileURL(root: root, noteID: note.id), rtfFileURL(root: root, noteID: note.id)]
  }
  let sentinelDate = Date(timeIntervalSince1970: 1)
  for url in contentURLs {
    try FileManager.default.setAttributes(
      [.modificationDate: sentinelDate],
      ofItemAtPath: url.path
    )
  }
  let before = try Dictionary(
    uniqueKeysWithValues: contentURLs.map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )

  workspace.updateNote(
    id: first.id,
    title: "Renamed",
    now: date.addingTimeInterval(1)
  )
  try await store.save(workspace: workspace, preferences: .init(), generation: 2)
  #expect(
    try Dictionary(
      uniqueKeysWithValues: contentURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
  )

  workspace.moveNote(id: first.id, to: 1)
  try await store.save(workspace: workspace, preferences: .init(), generation: 3)
  #expect(
    try Dictionary(
      uniqueKeysWithValues: contentURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
  )

  workspace.togglePinned(id: first.id, now: date.addingTimeInterval(2))
  try await store.save(workspace: workspace, preferences: .init(), generation: 4)
  #expect(
    try Dictionary(
      uniqueKeysWithValues: contentURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
  )

  workspace.selectAdjacent(forward: true)
  try await store.save(workspace: workspace, preferences: .init(), generation: 5)
  #expect(
    try Dictionary(
      uniqueKeysWithValues: contentURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
  )

  workspace.setAgentAccess(
    id: first.id,
    enabled: true,
    now: date.addingTimeInterval(3)
  )
  try await store.save(workspace: workspace, preferences: .init(), generation: 6)
  #expect(
    try Dictionary(
      uniqueKeysWithValues: contentURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
  )
  let loaded = try await store.loadSnapshot()
  #expect(loaded.workspace.notes.map(\.id) == workspace.notes.map(\.id))
  #expect(loaded.workspace.selectedNoteID == workspace.selectedNoteID)
  #expect(loaded.workspace.notes.first?.title == "Renamed")
  #expect(loaded.workspace.notes.first?.isPinned == workspace.notes.first?.isPinned)
  #expect(loaded.workspace.notes.first?.agentAccess == true)
  #expect(loaded.workspace.notes.first?.revision == 2)
}

@Test func richTextRemovalWaitsForManifestCommit() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(
    title: "Formatted",
    body: "body",
    richTextRTF: Data("{\\rtf1 body}".utf8)
  )
  let workspace = Workspace(notes: [note], selectedNoteID: note.id)
  let initialWriter = LocalStoreSnapshotWriter(rootURL: root)
  _ = try initialWriter.save(
    workspace: workspace,
    preferences: .init(),
    generation: 1
  )

  let rtfURL = rtfFileURL(root: root, noteID: note.id)
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSince1970: 1)],
    ofItemAtPath: rtfURL.path
  )
  let beforeFailure = try fileObservation(at: rtfURL)
  var plainWorkspace = workspace
  plainWorkspace.updateContent(
    id: note.id,
    body: note.body,
    rtf: nil,
    now: Date(timeIntervalSince1970: 2)
  )
  let failure = SnapshotFailureController(failingGeneration: 2)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      try failure.failOnce(generation)
    })
  )

  #expect(throws: SnapshotTestError.failed) {
    try writer.save(
      workspace: plainWorkspace,
      preferences: .init(),
      generation: 2
    )
  }
  #expect(try fileObservation(at: rtfURL) == beforeFailure)
  #expect(try writer.loadSnapshot().source == .root)
  #expect(try writer.loadSnapshot().workspace.notes.first?.richTextRTF != nil)

  #expect(
    try writer.save(
      workspace: plainWorkspace,
      preferences: .init(),
      generation: 2
    ) == .committed
  )
  #expect(!FileManager.default.fileExists(atPath: rtfURL.path))
  #expect(try writer.loadSnapshot().workspace.notes.first?.richTextRTF == nil)
}

@Test func preferenceOnlySavesWriteOnlyChangedPreferences() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let note = Note(
    title: "Content",
    body: "body",
    richTextRTF: Data("{\\rtf1 body}".utf8)
  )
  let workspace = Workspace(notes: [note], selectedNoteID: note.id)
  let initialPreferences = AppPreferences(fontFamily: "Menlo")
  try await store.save(
    workspace: workspace,
    preferences: initialPreferences,
    generation: 1
  )

  let preferencesURL = root.appendingPathComponent("preferences.json")
  let bodyURL = noteFileURL(root: root, noteID: note.id)
  let rtfURL = rtfFileURL(root: root, noteID: note.id)
  let sentinelDate = Date(timeIntervalSince1970: 1)
  for url in [preferencesURL, bodyURL, rtfURL] {
    try FileManager.default.setAttributes(
      [.modificationDate: sentinelDate],
      ofItemAtPath: url.path
    )
  }
  let before = try Dictionary(
    uniqueKeysWithValues: [preferencesURL, bodyURL, rtfURL].map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )

  var bodyChanged = workspace
  bodyChanged.updateContent(
    id: note.id,
    body: "changed body",
    rtf: note.richTextRTF,
    now: Date(timeIntervalSince1970: 2)
  )
  try await store.save(
    workspace: bodyChanged,
    preferences: initialPreferences,
    generation: 2
  )
  let afterBodySave = try Dictionary(
    uniqueKeysWithValues: [preferencesURL, bodyURL, rtfURL].map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )
  #expect(
    afterBodySave[preferencesURL.lastPathComponent]
      == before[preferencesURL.lastPathComponent]
  )
  #expect(afterBodySave[rtfURL.lastPathComponent] == before[rtfURL.lastPathComponent])

  let beforeSamePreferences = afterBodySave
  try await store.save(
    workspace: bodyChanged,
    preferences: initialPreferences,
    generation: 3
  )
  #expect(
    try Dictionary(
      uniqueKeysWithValues: [preferencesURL, bodyURL, rtfURL].map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == beforeSamePreferences
  )

  let changedPreferences = AppPreferences(fontFamily: "Avenir")
  try await store.save(
    workspace: bodyChanged,
    preferences: changedPreferences,
    generation: 4
  )
  let afterPreferencesChange = try Dictionary(
    uniqueKeysWithValues: [preferencesURL, bodyURL, rtfURL].map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )
  #expect(
    afterPreferencesChange[preferencesURL.lastPathComponent]
      != beforeSamePreferences[preferencesURL.lastPathComponent]
  )
  #expect(
    afterPreferencesChange[bodyURL.lastPathComponent]
      == beforeSamePreferences[bodyURL.lastPathComponent]
  )
  #expect(
    afterPreferencesChange[rtfURL.lastPathComponent]
      == beforeSamePreferences[rtfURL.lastPathComponent]
  )
  #expect(try await store.loadPreferences() == changedPreferences)
}

@Test func agentCommitProofOnlySaveLeavesContentFilesUntouched() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(
    title: "Shared",
    body: "body",
    richTextRTF: Data("{\\rtf1 body}".utf8),
    agentAccess: true,
    revision: 2
  )
  let workspace = Workspace(notes: [note], selectedNoteID: note.id)
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  _ = try writer.save(
    workspace: workspace,
    preferences: .init(),
    generation: 1
  )

  let contentURLs = [
    noteFileURL(root: root, noteID: note.id),
    rtfFileURL(root: root, noteID: note.id),
  ]
  for url in contentURLs {
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)],
      ofItemAtPath: url.path
    )
  }
  let before = try Dictionary(
    uniqueKeysWithValues: contentURLs.map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )
  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(),
    noteID: note.id,
    resultingRevision: note.revision,
    bodySHA256: "body-hash",
    actor: .localUser,
    operationID: UUID(),
    expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
  )

  #expect(
    try writer.save(
      workspace: workspace,
      preferences: .init(),
      generation: 2,
      commitProof: proof
    ) == .committed
  )
  #expect(
    try Dictionary(
      uniqueKeysWithValues: contentURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == before
  )
  #expect(try writer.loadSnapshot().commitProofs == [proof])
}

@Test func deletedContentCleanupWaitsForManifestCommitAndRestoreReusesExistingFiles()
  async throws
{
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let remaining = Note(
    title: "Remaining",
    body: "keep me",
    richTextRTF: Data("{\\rtf1 keep me}".utf8)
  )
  let deleted = Note(
    title: "Deleted",
    body: "restore me",
    richTextRTF: Data("{\\rtf1 restore me}".utf8)
  )
  let initialWorkspace = Workspace(
    notes: [remaining, deleted],
    selectedNoteID: remaining.id
  )
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: initialWorkspace,
    preferences: .init(),
    generation: 1
  )

  let remainingURLs = [
    noteFileURL(root: root, noteID: remaining.id),
    rtfFileURL(root: root, noteID: remaining.id),
  ]
  for url in remainingURLs {
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)],
      ofItemAtPath: url.path
    )
  }
  let remainingBefore = try Dictionary(
    uniqueKeysWithValues: remainingURLs.map { url in
      (url.lastPathComponent, try fileObservation(at: url))
    }
  )
  let reducedWorkspace = Workspace(
    notes: [remaining],
    selectedNoteID: remaining.id
  )
  let failure = SnapshotFailureController(failingGeneration: 2)
  let writer = LocalStoreSnapshotWriter(
    rootURL: root,
    hooks: .init(beforeManifestCommit: { generation in
      try failure.failOnce(generation)
    })
  )

  #expect(throws: SnapshotTestError.failed) {
    try writer.save(
      workspace: reducedWorkspace,
      preferences: .init(),
      generation: 2,
      trashedNotes: [deleted]
    )
  }
  #expect(
    FileManager.default.fileExists(
      atPath: noteFileURL(root: root, noteID: deleted.id).path
    )
  )
  #expect(
    FileManager.default.fileExists(
      atPath: rtfFileURL(root: root, noteID: deleted.id).path
    )
  )
  #expect(
    try Dictionary(
      uniqueKeysWithValues: remainingURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == remainingBefore
  )
  let failedSnapshot = try writer.loadSnapshot()
  #expect(failedSnapshot.source == .root)
  #expect(failedSnapshot.workspace.notes.map(\.id) == initialWorkspace.notes.map(\.id))

  #expect(
    try writer.save(
      workspace: reducedWorkspace,
      preferences: .init(),
      generation: 2,
      trashedNotes: [deleted]
    ) == .committed
  )
  #expect(
    !FileManager.default.fileExists(
      atPath: noteFileURL(root: root, noteID: deleted.id).path
    )
  )
  #expect(
    !FileManager.default.fileExists(
      atPath: rtfFileURL(root: root, noteID: deleted.id).path
    )
  )
  #expect(
    try Dictionary(
      uniqueKeysWithValues: remainingURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == remainingBefore
  )

  let restoredStore = LocalStore(rootURL: root)
  let trashedNote = try #require(await restoredStore.loadTrash().first)
  let restoredWorkspace = try await restoredStore.restore(
    trashedNote,
    into: reducedWorkspace,
    preferences: .init(),
    generation: 3
  )
  #expect(restoredWorkspace.notes.map(\.id) == [remaining.id, deleted.id])
  #expect(
    try Dictionary(
      uniqueKeysWithValues: remainingURLs.map { url in
        (url.lastPathComponent, try fileObservation(at: url))
      }
    ) == remainingBefore
  )
  #expect(
    FileManager.default.fileExists(
      atPath: noteFileURL(root: root, noteID: deleted.id).path
    )
  )
  #expect(try await restoredStore.loadTrash().isEmpty)
}

@Test func invalidRootSaveRewritesContentInsteadOfReusingUnvalidatedFiles() throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let first = Note(title: "First", body: "first")
  let second = Note(title: "Second", body: "second")
  let initialWorkspace = Workspace(
    notes: [first, second],
    selectedNoteID: first.id
  )
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  _ = try writer.save(
    workspace: initialWorkspace,
    preferences: .init(),
    generation: 1
  )
  _ = try writer.save(
    workspace: initialWorkspace,
    preferences: .init(),
    generation: 2
  )

  let secondURL = noteFileURL(root: root, noteID: second.id)
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSince1970: 1)],
    ofItemAtPath: secondURL.path
  )
  let before = try fileObservation(at: secondURL)
  try Data("corrupt root".utf8).write(
    to: noteFileURL(root: root, noteID: first.id)
  )

  var requestedWorkspace = initialWorkspace
  requestedWorkspace.updateContent(
    id: first.id,
    body: "new first",
    rtf: nil,
    now: Date(timeIntervalSince1970: 3)
  )
  _ = try writer.save(
    workspace: requestedWorkspace,
    preferences: .init(),
    generation: 3
  )

  #expect(try fileObservation(at: secondURL) != before)
  #expect(try writer.loadSnapshot().source == .root)
  #expect(try writer.loadSnapshot().workspace.notes.map(\.body) == ["new first", "second"])
  #expect(
    try String(
      contentsOf: root.appendingPathComponent(
        "Recovery/\(second.id.uuidString.lowercased()).md"
      ),
      encoding: .utf8
    ) == "second"
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

private struct FileObservation: Equatable {
  let bytes: Data
  let modificationDate: Date
  let fileNumber: UInt64?
}

private func fileObservation(at url: URL) throws -> FileObservation {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return FileObservation(
    bytes: try Data(contentsOf: url),
    modificationDate: try #require(attributes[.modificationDate] as? Date),
    fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
  )
}

private func noteFileURL(root: URL, noteID: UUID) -> URL {
  root.appendingPathComponent("\(noteID.uuidString.lowercased()).md")
}

private func rtfFileURL(root: URL, noteID: UUID) -> URL {
  root.appendingPathComponent("\(noteID.uuidString.lowercased()).rtf")
}

private func temporaryStoreURL() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckTests-\(UUID().uuidString)"
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
