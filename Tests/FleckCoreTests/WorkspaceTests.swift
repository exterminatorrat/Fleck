import Foundation
import Testing

@testable import FleckCore

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

@Test func repeatedLiveTabMovesPreserveEveryNoteExactlyOnce() {
  var workspace = Workspace()
  let first = workspace.addNote()
  let second = workspace.addNote()
  let third = workspace.addNote()

  workspace.moveNote(id: first, to: 1)
  #expect(workspace.notes.map(\.id) == [second, first, third])

  workspace.moveNote(id: first, to: 2)
  #expect(workspace.notes.map(\.id) == [second, third, first])
  #expect(Set(workspace.notes.map(\.id)) == Set([first, second, third]))
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

@Test func oldNoteJSONDefaultsAgentFields() throws {
  let data = Data(
    """
    {
      "id":"00000000-0000-0000-0000-000000000001",
      "title":"Legacy",
      "body":"Body",
      "createdAt":0,
      "modifiedAt":0,
      "isPinned":false
    }
    """.utf8
  )
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970

  let note = try decoder.decode(Note.self, from: data)

  #expect(note.agentAccess == false)
  #expect(note.revision == 0)
}

@Test func contentAndSharingChangesIncrementRevisionOnce() {
  let id = UUID()
  let changedAt = Date(timeIntervalSince1970: 300)
  var workspace = Workspace(notes: [Note(id: id)], selectedNoteID: id)

  workspace.updateContent(id: id, body: "A", rtf: Data([1]), now: changedAt)
  #expect(workspace.notes[0].revision == 1)
  #expect(workspace.notes[0].modifiedAt == changedAt)

  workspace.updateContent(
    id: id,
    body: "A",
    rtf: Data([1]),
    now: changedAt.addingTimeInterval(1)
  )
  #expect(workspace.notes[0].revision == 1)
  #expect(workspace.notes[0].modifiedAt == changedAt)

  workspace.setAgentAccess(
    id: id,
    enabled: true,
    now: changedAt.addingTimeInterval(2)
  )
  #expect(workspace.notes[0].agentAccess)
  #expect(workspace.notes[0].revision == 2)

  workspace.setAgentAccess(
    id: id,
    enabled: true,
    now: changedAt.addingTimeInterval(3)
  )
  #expect(workspace.notes[0].revision == 2)
}

@Test func titleChangesIncrementRevisionOnceAndNoOpsDoNot() {
  let id = UUID()
  let changedAt = Date(timeIntervalSince1970: 400)
  var workspace = Workspace(
    notes: [Note(id: id, title: "Before")],
    selectedNoteID: id
  )

  workspace.updateNote(id: id, title: "After", now: changedAt)
  #expect(workspace.notes[0].revision == 1)
  #expect(workspace.notes[0].modifiedAt == changedAt)

  workspace.updateNote(
    id: id,
    title: "After",
    now: changedAt.addingTimeInterval(1)
  )
  #expect(workspace.notes[0].revision == 1)
  #expect(workspace.notes[0].modifiedAt == changedAt)
}
