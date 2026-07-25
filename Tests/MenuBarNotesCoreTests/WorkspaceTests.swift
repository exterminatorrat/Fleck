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

@Test func importedNoteBecomesSelectedWithoutChangingItsIdentity() {
  var workspace = Workspace()
  workspace.ensureNoteExists()
  let imported = Note(title: "Imported", body: "Contents")

  workspace.addNote(imported)

  #expect(workspace.selectedNoteID == imported.id)
  #expect(workspace.notes.last == imported)
}

@Test func adjacentSelectionWrapsInBothDirections() {
  var workspace = Workspace()
  let first = workspace.addNote()
  let second = workspace.addNote()
  workspace.selectedNoteID = second
  workspace.selectAdjacent(forward: true)
  #expect(workspace.selectedNoteID == first)
  workspace.selectAdjacent(forward: false)
  #expect(workspace.selectedNoteID == second)
}

@Test func notesCanBeReorderedAndPinnedNotesStayAtFront() {
  var workspace = Workspace()
  let first = workspace.addNote()
  let second = workspace.addNote()
  let third = workspace.addNote()
  workspace.moveNote(id: third, to: 0)
  #expect(workspace.notes.map(\.id) == [third, first, second])
  workspace.togglePinned(id: second)
  #expect(workspace.notes.first?.id == second)
  #expect(workspace.notes.first?.isPinned == true)
  workspace.togglePinned(id: second)
  #expect(workspace.notes.first(where: { $0.id == second })?.isPinned == false)
}

@Test func workspaceSetsAndClearsTabColor() {
  let changedAt = Date(timeIntervalSince1970: 200)
  var workspace = Workspace()
  let noteID = workspace.addNote()

  workspace.setTabColor(id: noteID, hex: "#FF5A5F", now: changedAt)
  #expect(workspace.notes.first?.tabColorHex == "#FF5A5F")
  #expect(workspace.notes.first?.modifiedAt == changedAt)

  workspace.setTabColor(id: noteID, hex: nil, now: changedAt.addingTimeInterval(1))
  #expect(workspace.notes.first?.tabColorHex == nil)
}
