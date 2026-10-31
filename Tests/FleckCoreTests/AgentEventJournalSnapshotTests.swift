import Foundation
import Testing

@testable import FleckCore

@Suite(.serialized)
struct AgentEventJournalSnapshotTests {
  @Test func verifiedRootSnapshotExposesItsValidatedJournal() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentEventJournalSnapshotTests-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let note = Note(title: "PRIVATE_TITLE_CANARY", body: "PRIVATE_BODY_CANARY")
    let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
    _ = try writer.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init(),
      generation: 0
    )

    let snapshot = try writer.loadSnapshot()
    let journal = try #require(snapshot.agentEventJournal)
    #expect(snapshot.source == .root)
    #expect(journal.lastSequence == 1)
    #expect(journal.records.map(\.noteID) == [note.id])
    #expect(journal.records.map(\.eventName) == [.noteCreated])
    let encoded = String(decoding: try journal.canonicalData(), as: UTF8.self)
    #expect(!encoded.contains(note.title))
    #expect(!encoded.contains(note.body))
  }

  @Test func legacyRootSnapshotWithoutJournalRemainsReadable() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentEventJournalSnapshotTests-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let writer = LocalStoreSnapshotWriter(rootURL: root)
    _ = try writer.save(
      workspace: Workspace(notes: [Note(title: "Legacy")]),
      preferences: .init(),
      generation: 0
    )
    let manifestURL = root.appendingPathComponent("workspace.json")
    var manifest = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    manifest.removeValue(forKey: "agentEventJournal")
    manifest.removeValue(forKey: "agentEventJournalSHA256")
    try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
      .write(to: manifestURL, options: .atomic)

    let snapshot = try writer.loadSnapshot()
    #expect(snapshot.source == .root)
    #expect(snapshot.agentEventJournal == nil)
  }

  @Test func recoverySnapshotCarriesOnlyItsVerifiedJournal() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentEventJournalSnapshotTests-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let note = Note(title: "Original", body: "Original body")
    let writer = LocalStoreSnapshotWriter(rootURL: root, now: { date })
    _ = try writer.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init(),
      generation: 0
    )
    var changed = note
    changed.body = "Changed body"
    changed.revision = 1
    _ = try writer.save(
      workspace: Workspace(notes: [changed], selectedNoteID: note.id),
      preferences: .init(),
      generation: 1
    )
    try Data("corrupt root body".utf8).write(
      to: root.appendingPathComponent("\(note.id.uuidString.lowercased()).md"),
      options: .atomic
    )

    let snapshot = try writer.loadSnapshot()
    #expect(snapshot.source == .recovery)
    #expect(snapshot.workspace.notes.first?.body == note.body)
    #expect(snapshot.agentEventJournal?.lastSequence == 1)
  }
}
