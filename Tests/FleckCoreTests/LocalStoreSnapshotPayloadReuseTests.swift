import Foundation
import Testing

@testable import FleckCore

@Test func modernSnapshotPreservesVerifiedMarkdownDecodingAndRawRTFBytes() throws {
  let root = snapshotPayloadReuseRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let body = "\u{FEFF}Cafe\u{301} and café"
  let rtf = Data("{\\rtf1 raw \\u233?}".utf8)
  let note = Note(title: "Unicode", body: body, richTextRTF: rtf)
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  _ = try writer.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 1
  )

  let markdownURL = snapshotPayloadURL(root: root, noteID: note.id, fileExtension: "md")
  #expect(try Data(contentsOf: markdownURL) == Data(body.utf8))
  let existingDecodedBody = try String(contentsOf: markdownURL, encoding: .utf8)
  let snapshot = try writer.loadSnapshot()
  let loadedNote = try #require(snapshot.workspace.notes.first)

  #expect(snapshot.source == .root)
  #expect(Array(loadedNote.body.utf8) == Array(existingDecodedBody.utf8))
  #expect(loadedNote.richTextRTF == rtf)
}

@Test func modernMarkdownOrRTFCorruptionSelectsThePreviousCompleteSnapshot() throws {
  for fileExtension in ["md", "rtf"] {
    let root = snapshotPayloadReuseRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let firstRTF = Data("{\\rtf1 first}".utf8)
    let first = Note(title: "First", body: "first body", richTextRTF: firstRTF)
    let writer = LocalStoreSnapshotWriter(rootURL: root)
    _ = try writer.save(
      workspace: Workspace(notes: [first], selectedNoteID: first.id),
      preferences: .init(),
      generation: 1
    )
    var second = first
    second.body = "second body"
    second.richTextRTF = Data("{\\rtf1 second}".utf8)
    _ = try writer.save(
      workspace: Workspace(notes: [second], selectedNoteID: second.id),
      preferences: .init(),
      generation: 2
    )
    try Data("corrupt".utf8).write(
      to: snapshotPayloadURL(root: root, noteID: first.id, fileExtension: fileExtension),
      options: .atomic
    )

    let snapshot = try writer.loadSnapshot()
    let recoveredNote = try #require(snapshot.workspace.notes.first)

    #expect(snapshot.source == .recovery)
    #expect(snapshot.generation == 1)
    #expect(recoveredNote.body == first.body)
    #expect(recoveredNote.richTextRTF == firstRTF)
  }
}

@Test func legacySnapshotKeepsBestEffortBehaviorForMissingAndCorruptFiles() throws {
  let root = snapshotPayloadReuseRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let missingBody = Note(title: "Missing", body: "missing body")
  let invalidBody = Note(title: "Invalid", body: "invalid body")
  let readable = Note(
    title: "Readable",
    body: "readable body",
    richTextRTF: Data("{\\rtf1 optional}".utf8)
  )
  let writer = LocalStoreSnapshotWriter(rootURL: root)
  _ = try writer.save(
    workspace: Workspace(
      notes: [missingBody, invalidBody, readable],
      selectedNoteID: readable.id
    ),
    preferences: AppPreferences(fontFamily: "Menlo"),
    generation: 1
  )

  let manifestURL = root.appendingPathComponent("workspace.json")
  var manifest = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
  )
  manifest["formatVersion"] = 1
  for key in [
    "snapshotIntegrityVersion",
    "markdownSHA256",
    "rtfSHA256",
    "preferencesSHA256",
  ] {
    manifest.removeValue(forKey: key)
  }
  try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    .write(to: manifestURL, options: .atomic)

  try FileManager.default.removeItem(
    at: snapshotPayloadURL(root: root, noteID: missingBody.id, fileExtension: "md")
  )
  try Data([0xFF]).write(
    to: snapshotPayloadURL(root: root, noteID: invalidBody.id, fileExtension: "md"),
    options: .atomic
  )
  try FileManager.default.removeItem(
    at: snapshotPayloadURL(root: root, noteID: readable.id, fileExtension: "rtf")
  )
  try Data("corrupt preferences".utf8).write(
    to: root.appendingPathComponent("preferences.json"),
    options: .atomic
  )

  let snapshot = try writer.loadSnapshot()

  #expect(snapshot.source == .root)
  #expect(snapshot.workspace.notes.map(\.id) == [readable.id])
  #expect(snapshot.workspace.notes.first?.body == readable.body)
  #expect(snapshot.workspace.notes.first?.richTextRTF == nil)
  #expect(snapshot.preferences == AppPreferences())
}

private func snapshotPayloadReuseRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "LocalStoreSnapshotPayloadReuseTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func snapshotPayloadURL(
  root: URL,
  noteID: UUID,
  fileExtension: String
) -> URL {
  root.appendingPathComponent("\(noteID.uuidString.lowercased()).\(fileExtension)")
}
