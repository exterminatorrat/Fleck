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
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent("\(note.id.uuidString.lowercased()).md").path
    ))
}

@Test func storeRemovesFilesForDeletedNotes() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MenuBarNotesTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LocalStore(rootURL: root)
    let first = Note(title: "First")
    let second = Note(title: "Second")
    try await store.save(
        workspace: Workspace(notes: [first, second], selectedNoteID: first.id),
        preferences: AppPreferences()
    )
    try await store.save(
        workspace: Workspace(notes: [first], selectedNoteID: first.id),
        preferences: AppPreferences()
    )

    #expect(!FileManager.default.fileExists(
        atPath: root.appendingPathComponent("\(second.id.uuidString.lowercased()).md").path
    ))
}
