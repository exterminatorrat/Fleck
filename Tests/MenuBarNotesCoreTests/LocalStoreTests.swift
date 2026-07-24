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
