import Foundation
import Testing
@testable import MenuBarNotesCore

@Test func workspaceAlwaysKeepsAnEditableNote() {
    let date = Date(timeIntervalSince1970: 100)
    var workspace = Workspace()

    workspace.ensureNoteExists(now: date)
    #expect(workspace.notes.count == 1)
    #expect(workspace.selectedNoteID == workspace.notes[0].id)

    workspace.deleteNote(id: workspace.notes[0].id, now: date)
    #expect(workspace.notes.count == 1)
    #expect(workspace.selectedNoteID == workspace.notes[0].id)
}

@Test func deletingSelectedNoteSelectsItsNeighbor() {
    var workspace = Workspace()
    let first = workspace.addNote()
    let second = workspace.addNote()
    _ = workspace.addNote()
    workspace.selectedNoteID = second

    workspace.deleteNote(id: second)

    #expect(workspace.selectedNoteID != second)
    #expect(workspace.notes.map(\.id).contains(first))
    #expect(workspace.notes.count == 2)
}

@Test func displayTitleFallsBackToFirstBodyLine() {
    let note = Note(title: "  ", body: "First useful line\nSecond line")
    #expect(note.displayTitle == "First useful line")
}
