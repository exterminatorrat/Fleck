import Foundation
import Testing

@testable import FleckCore

@Test func workspaceMutationResultsPreserveNoOpAndNoteRevisionSemantics() {
  let id = UUID()
  let originalDate = Date(timeIntervalSince1970: 10)
  let note = Note(
    id: id,
    title: "Before",
    body: "Original body",
    richTextRTF: Data([1, 2]),
    modifiedAt: originalDate,
    revision: 7
  )
  var workspace = Workspace(notes: [note], selectedNoteID: id)
  let changedAt = Date(timeIntervalSince1970: 20)

  let unchanged = workspace.updateNote(
    id: id,
    title: note.title,
    body: note.body,
    isPinned: note.isPinned,
    now: changedAt
  )
  #expect(unchanged == .unchanged)
  #expect(workspace.notes[0] == note)
  #expect(workspace.notes[0].revision == 7)
  #expect(workspace.notes[0].modifiedAt == originalDate)

  let missing = workspace.updateNote(id: UUID(), title: "Missing", now: changedAt)
  #expect(missing == .unchanged)

  let changed = workspace.updateNote(
    id: id,
    title: "After",
    body: "Changed body",
    isPinned: true,
    now: changedAt
  )
  #expect(changed == .changed)
  #expect(workspace.notes[0].title == "After")
  #expect(workspace.notes[0].body == "Changed body")
  #expect(workspace.notes[0].richTextRTF == note.richTextRTF)
  #expect(workspace.notes[0].isPinned)
  #expect(workspace.notes[0].revision == 8)
  #expect(workspace.notes[0].modifiedAt == changedAt)

  let pinnedAt = changedAt.addingTimeInterval(1)
  let pinOnlyChange = workspace.updateNote(
    id: id,
    isPinned: false,
    now: pinnedAt
  )
  #expect(pinOnlyChange == .changed)
  #expect(!workspace.notes[0].isPinned)
  #expect(workspace.notes[0].revision == 8)
  #expect(workspace.notes[0].modifiedAt == pinnedAt)
}

@Test func workspaceContentMutationReportsBodyAndRTFChanges() {
  let id = UUID()
  let originalDate = Date(timeIntervalSince1970: 30)
  let note = Note(
    id: id,
    body: "Before",
    richTextRTF: Data([3, 4]),
    modifiedAt: originalDate,
    revision: 11
  )
  var workspace = Workspace(notes: [note], selectedNoteID: id)
  let changedAt = Date(timeIntervalSince1970: 40)

  let unchanged = workspace.updateContent(
    id: id,
    body: note.body,
    rtf: note.richTextRTF,
    now: changedAt
  )
  #expect(unchanged == .unchanged)
  #expect(workspace.notes[0] == note)

  let bodyChanged = workspace.updateContent(
    id: id,
    body: "After",
    rtf: note.richTextRTF,
    now: changedAt
  )
  #expect(bodyChanged == .changed)
  #expect(workspace.notes[0].body == "After")
  #expect(workspace.notes[0].richTextRTF == note.richTextRTF)
  #expect(workspace.notes[0].revision == 12)
  #expect(workspace.notes[0].modifiedAt == changedAt)

  let rtfChangedAt = changedAt.addingTimeInterval(1)
  let rtfChanged = workspace.updateContent(
    id: id,
    body: "After",
    rtf: Data([5, 6]),
    now: rtfChangedAt
  )
  #expect(rtfChanged == .changed)
  #expect(workspace.notes[0].body == "After")
  #expect(workspace.notes[0].richTextRTF == Data([5, 6]))
  #expect(workspace.notes[0].revision == 13)
  #expect(workspace.notes[0].modifiedAt == rtfChangedAt)

  let repeatedNoOp = workspace.updateContent(
    id: id,
    body: "After",
    rtf: Data([5, 6]),
    now: rtfChangedAt.addingTimeInterval(1)
  )
  #expect(repeatedNoOp == .unchanged)
  #expect(workspace.notes[0].revision == 13)
  #expect(workspace.notes[0].modifiedAt == rtfChangedAt)
}

@Test func noteEqualityChecksContentAfterMatchingRevisionMetadata() {
  let id = UUID()
  let createdAt = Date(timeIntervalSince1970: 50)
  let modifiedAt = Date(timeIntervalSince1970: 60)
  let folderID = UUID()
  let note = Note(
    id: id,
    title: "Title",
    body: "Body",
    richTextRTF: Data([7, 8]),
    tabColorHex: "#123456",
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    isPinned: true,
    agentAccess: true,
    revision: 17,
    folderID: folderID,
    titleFontFamily: "Avenir"
  )
  var changedTitle = note
  changedTitle.title = "Different title"
  var changedBody = note
  changedBody.body = "Different body"
  var changedRTF = note
  changedRTF.richTextRTF = Data([9, 10])

  #expect(note == note)
  #expect(changedTitle.revision == note.revision)
  #expect(changedTitle.modifiedAt == note.modifiedAt)
  #expect(changedBody.revision == note.revision)
  #expect(changedBody.modifiedAt == note.modifiedAt)
  #expect(changedRTF.revision == note.revision)
  #expect(changedRTF.modifiedAt == note.modifiedAt)
  #expect(note != changedTitle)
  #expect(note != changedBody)
  #expect(note != changedRTF)
}
