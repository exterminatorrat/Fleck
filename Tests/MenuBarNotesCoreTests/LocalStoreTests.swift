import Foundation
import Testing

@testable import MenuBarNotesCore

@Test func storeRoundTripsWorkspaceAndPreferences() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("MenuBarNotesTests-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }

  let store = LocalStore(rootURL: root)
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let note = Note(title: "Shopping", body: "- Tea\n- Coffee", createdAt: date, modifiedAt: date)
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
    isPinned: true
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
  #expect(metadata["deletedAt"] != nil)
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
  #expect(!FileManager.default.fileExists(atPath: trashEntryURL(root: root, noteID: deleted.id).path))
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
  #expect(!FileManager.default.fileExists(atPath: trashEntryURL(root: root, noteID: deleted.id).path))
}

private func temporaryStoreURL() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "MenuBarNotesTests-\(UUID().uuidString)"
  )
}

private func trashEntryURL(root: URL, noteID: UUID) -> URL {
  root
    .appendingPathComponent("Trash", isDirectory: true)
    .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
}
