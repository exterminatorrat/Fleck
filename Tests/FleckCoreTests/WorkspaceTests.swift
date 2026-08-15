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

@Test func movingNotesClampsToTheirPinnedPartition() {
  let pinnedFirst = Note(title: "Pinned first", body: "A", richTextRTF: Data([1]), isPinned: true)
  let pinnedSecond = Note(title: "Pinned second", body: "B", richTextRTF: Data([2]), isPinned: true)
  let unpinnedFirst = Note(title: "Unpinned first", body: "C", richTextRTF: Data([3]))
  let unpinnedSecond = Note(title: "Unpinned second", body: "D", richTextRTF: Data([4]))
  var workspace = Workspace(
    notes: [pinnedFirst, pinnedSecond, unpinnedFirst, unpinnedSecond],
    selectedNoteID: unpinnedFirst.id
  )

  workspace.moveNote(id: pinnedFirst.id, to: 3)
  #expect(workspace.notes == [pinnedSecond, pinnedFirst, unpinnedFirst, unpinnedSecond])

  workspace.moveNote(id: unpinnedSecond.id, to: 0)
  #expect(workspace.notes == [pinnedSecond, pinnedFirst, unpinnedSecond, unpinnedFirst])

  workspace.moveNote(id: pinnedFirst.id, to: 0)
  workspace.moveNote(id: unpinnedFirst.id, to: 2)
  #expect(workspace.notes == [pinnedFirst, pinnedSecond, unpinnedFirst, unpinnedSecond])
  #expect(workspace.selectedNoteID == unpinnedFirst.id)
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
  #expect(note.titleFontFamily == nil)
}

@Test func oldWorkspaceJSONDefaultsFoldersAndNoteFolderID() throws {
  let data = Data(
    """
    {
      "notes": [
        {
          "id":"00000000-0000-0000-0000-000000000011",
          "title":"Legacy",
          "body":"Body",
          "createdAt":0,
          "modifiedAt":0,
          "isPinned":false
        }
      ],
      "selectedNoteID":"00000000-0000-0000-0000-000000000011"
    }
    """.utf8
  )
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970

  let workspace = try decoder.decode(Workspace.self, from: data)

  #expect(workspace.folders.isEmpty)
  #expect(workspace.notes.first?.folderID == nil)
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

@Test func titleFontFamilyChangesOnlyTargetNoteAndNoOpsDoNot() {
  let firstID = UUID()
  let secondID = UUID()
  let originalDate = Date(timeIntervalSince1970: 500)
  let changedAt = Date(timeIntervalSince1970: 600)
  var workspace = Workspace(
    notes: [
      Note(id: firstID, modifiedAt: originalDate),
      Note(id: secondID, modifiedAt: originalDate, titleFontFamily: "Avenir"),
    ],
    selectedNoteID: firstID
  )

  workspace.setTitleFontFamily(id: firstID, family: "Menlo", now: changedAt)

  #expect(workspace.notes[0].titleFontFamily == "Menlo")
  #expect(workspace.notes[0].revision == 1)
  #expect(workspace.notes[0].modifiedAt == changedAt)
  #expect(workspace.notes[1].titleFontFamily == "Avenir")
  #expect(workspace.notes[1].revision == 0)
  #expect(workspace.notes[1].modifiedAt == originalDate)

  workspace.setTitleFontFamily(
    id: firstID,
    family: "Menlo",
    now: changedAt.addingTimeInterval(1)
  )

  #expect(workspace.notes[0].revision == 1)
  #expect(workspace.notes[0].modifiedAt == changedAt)
}

@Test func WorkspaceFolderNameNormalizationAndReservedVariants() throws {
  let invalidNames = [
    "",
    "one/two",
    String(repeating: "a", count: 81),
    "Inbox",
    " inbox ",
    "INBOX",
    "Trash",
    " trash ",
  ]
  for name in invalidNames {
    #expect(throws: FolderError.self) {
      try Folder(name: name)
    }
  }

  for controlName in [
    "one\t two",
    "one\ntwo",
    "one\rtwo",
    "one\u{0000}two",
    "one\u{0001}two",
    "one\u{2028}two",
  ] {
    #expect(throws: FolderError.controlCharacter) {
      try Folder(name: controlName)
    }
  }

  let normalized = try Folder(name: "  Team\u{00A0}\u{2003}  Notes  ")
  #expect(normalized.name == "Team Notes")
  #expect(try Folder(name: "Cafe\u{301}").name == "Café")

  var workspace = Workspace()
  let folder = try workspace.createFolder(name: "  Team\u{00A0}\u{2003}Notes ")
  #expect(workspace.folders == [folder])
  #expect(throws: FolderError.self) {
    try workspace.createFolder(name: "team notes")
  }
}

@Test func WorkspaceFolderNameKeyFoldsUnicodeWithoutRemovingDiacritics() throws {
  var workspace = Workspace()
  let cafe = try workspace.createFolder(name: "Café")
  let plain = try workspace.createFolder(name: "CAFE")

  #expect(workspace.folders == [cafe, plain])
  #expect(cafe.id != plain.id)

  #expect(throws: FolderError.duplicateName) {
    try workspace.createFolder(name: "Cafe\u{301}")
  }
  #expect(throws: FolderError.duplicateName) {
    try workspace.renameFolder(id: plain.id, name: "Cafe\u{301}")
  }
  #expect(workspace.folders == [cafe, plain])

  try workspace.renameFolder(id: plain.id, name: "CAFE Notes")
  #expect(workspace.folders[1].id == plain.id)
  #expect(workspace.folders[1].name == "CAFE Notes")

  var sharpSWorkspace = Workspace()
  _ = try sharpSWorkspace.createFolder(name: "Straße")
  #expect(throws: FolderError.duplicateName) {
    try sharpSWorkspace.createFolder(name: "STRASSE")
  }

  #expect(throws: FolderError.reservedName) {
    try Folder(name: "INBOX")
  }
  #expect(throws: FolderError.reservedName) {
    try Folder(name: " trASH ")
  }
}

@Test func WorkspaceFolderRenameRetainsIdentityAndValidatesTargets() throws {
  let first = try Folder(name: "First")
  let second = try Folder(name: "Second")
  var workspace = Workspace(folders: [first, second])

  try workspace.renameFolder(id: first.id, name: "Renamed")
  #expect(workspace.folders[0].id == first.id)
  #expect(workspace.folders[0].name == "Renamed")
  #expect(throws: FolderError.duplicateName) {
    try workspace.renameFolder(id: first.id, name: " second ")
  }
  #expect(throws: FolderError.reservedName) {
    try workspace.renameFolder(id: first.id, name: "INBOX")
  }
  #expect(throws: FolderError.invalidTarget) {
    try workspace.renameFolder(id: UUID(), name: "Nope")
  }
}

@Test func WorkspaceFolderMovePreservesNoteDataAndOrganizationTimestamps() throws {
  let firstFolder = try Folder(name: "First")
  let secondFolder = try Folder(name: "Second")
  let createdAt = Date(timeIntervalSince1970: 10)
  let modifiedAt = Date(timeIntervalSince1970: 20)
  let note = Note(
    title: "Formatted",
    body: "Body",
    richTextRTF: Data("{\\rtf1 Body}".utf8),
    tabColorHex: "#123456",
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    isPinned: true,
    agentAccess: true,
    revision: 9,
    folderID: firstFolder.id
  )
  var workspace = Workspace(
    notes: [note],
    selectedNoteID: note.id,
    folders: [firstFolder, secondFolder]
  )

  try workspace.moveNote(id: note.id, toFolderID: secondFolder.id)
  var expected = note
  expected.folderID = secondFolder.id
  #expect(workspace.notes == [expected])
  #expect(workspace.notes[0].createdAt == createdAt)
  #expect(workspace.notes[0].modifiedAt == modifiedAt)
  #expect(workspace.notes[0].revision == 9)

  let beforeInvalidMove = workspace.notes
  #expect(throws: FolderError.invalidTarget) {
    try workspace.moveNote(id: note.id, toFolderID: UUID())
  }
  #expect(workspace.notes == beforeInvalidMove)
}

@Test func WorkspaceFolderDeletionMovesMembersToUnfiled() throws {
  let folder = try Folder(name: "Work")
  let other = try Folder(name: "Other")
  let first = Note(
    title: "First",
    body: "Body",
    richTextRTF: Data("{\\rtf1 Body}".utf8),
    createdAt: Date(timeIntervalSince1970: 10),
    modifiedAt: Date(timeIntervalSince1970: 20),
    isPinned: true,
    agentAccess: true,
    revision: 4,
    folderID: folder.id
  )
  let second = Note(title: "Second", folderID: folder.id)
  let untouched = Note(title: "Untouched", folderID: other.id)
  var workspace = Workspace(
    notes: [first, second, untouched],
    selectedNoteID: first.id,
    folders: [folder, other]
  )
  let before = workspace.notes

  try workspace.deleteFolder(id: folder.id)

  #expect(workspace.folders == [other])
  #expect(workspace.notes.map(\.id) == before.map(\.id))
  #expect(workspace.notes[0].folderID == nil)
  #expect(workspace.notes[1].folderID == nil)
  #expect(workspace.notes[2] == untouched)
  #expect(workspace.notes[0].richTextRTF == first.richTextRTF)
  #expect(workspace.notes[0].revision == first.revision)
  #expect(workspace.notes[0].modifiedAt == first.modifiedAt)
  #expect(workspace.selectedNoteID == first.id)
}

@Test func WorkspaceFolderReorderUsesPostRemovalInsertionIndex() throws {
  let folders = try ["A", "B", "C", "D"].map { try Folder(name: $0) }
  var workspace = Workspace(folders: folders)

  try workspace.reorderFolder(id: folders[2].id, to: 0)
  #expect(workspace.folders.map(\.name) == ["C", "A", "B", "D"])

  try workspace.reorderFolder(id: folders[0].id, to: 2)
  #expect(workspace.folders.map(\.name) == ["C", "B", "A", "D"])

  try workspace.reorderFolder(id: folders[0].id, to: 3)
  #expect(workspace.folders.map(\.name) == ["C", "B", "D", "A"])
  let beforeNoOp = workspace.folders
  try workspace.reorderFolder(id: folders[0].id, to: 99)
  #expect(workspace.folders == beforeNoOp)
  try workspace.reorderFolder(id: UUID(), to: 0)
  #expect(workspace.folders == beforeNoOp)
}

@Test func WorkspaceFolderReorderPreservesInterleavedHiddenNotes() throws {
  let selected = try Folder(name: "Selected")
  let other = try Folder(name: "Other")
  let a = Note(title: "A", isPinned: true, folderID: selected.id)
  let h1 = Note(title: "H1", isPinned: true, folderID: other.id)
  let b = Note(title: "B", isPinned: true, folderID: selected.id)
  let h2 = Note(title: "H2", isPinned: true, folderID: other.id)
  let c = Note(title: "C", isPinned: true, folderID: selected.id)
  var workspace = Workspace(
    notes: [a, h1, b, h2, c],
    selectedNoteID: a.id,
    folders: [selected, other]
  )

  try workspace.reorderNote(
    id: a.id,
    inFolderID: selected.id,
    toVisibleIndex: 1
  )
  #expect(workspace.notes.map(\.title) == ["H1", "B", "H2", "A", "C"])

  try workspace.reorderNote(
    id: a.id,
    inFolderID: selected.id,
    toVisibleIndex: 2
  )
  #expect(workspace.notes.map(\.title) == ["H1", "B", "H2", "C", "A"])

  workspace = Workspace(
    notes: [a, h1, b, h2, c],
    selectedNoteID: a.id,
    folders: [selected, other]
  )
  try workspace.reorderNote(
    id: c.id,
    inFolderID: selected.id,
    toVisibleIndex: 0
  )
  #expect(workspace.notes.map(\.title) == ["C", "A", "H1", "B", "H2"])
}

@Test func WorkspaceFolderRestoreUsesPinnedPartition() throws {
  let folder = try Folder(name: "Work")
  let pinned = Note(title: "P1", isPinned: true, folderID: folder.id)
  let unpinned = Note(title: "U1", folderID: folder.id)
  let restoredPinned = Note(title: "P2", isPinned: true, folderID: folder.id)
  let restoredUnpinned = Note(title: "U2", folderID: folder.id)
  var workspace = Workspace(
    notes: [pinned, unpinned],
    selectedNoteID: unpinned.id,
    folders: [folder]
  )

  workspace.addRestoredNote(restoredPinned)
  #expect(workspace.notes.map(\.title) == ["P1", "P2", "U1"])
  workspace.addRestoredNote(restoredUnpinned)
  #expect(workspace.notes.map(\.title) == ["P1", "P2", "U1", "U2"])
}

@Test func WorkspaceFolderReorderPreservesPinnedUnpinnedAndHiddenOrder() throws {
  let selected = try Folder(name: "Selected")
  let other = try Folder(name: "Other")
  let pinnedA = Note(title: "PA", isPinned: true, folderID: selected.id)
  let pinnedHidden1 = Note(title: "PH1", isPinned: true, folderID: other.id)
  let pinnedB = Note(title: "PB", isPinned: true, folderID: selected.id)
  let pinnedHidden2 = Note(title: "PH2", isPinned: true, folderID: other.id)
  let pinnedC = Note(title: "PC", isPinned: true, folderID: selected.id)
  let unpinnedA = Note(title: "UA", folderID: selected.id)
  let unpinnedHidden1 = Note(title: "UH1", folderID: other.id)
  let unpinnedB = Note(title: "UB", folderID: selected.id)
  let unpinnedHidden2 = Note(title: "UH2", folderID: other.id)
  let unpinnedC = Note(title: "UC", folderID: selected.id)
  var workspace = Workspace(
    notes: [
      pinnedA, pinnedHidden1, pinnedB, pinnedHidden2, pinnedC,
      unpinnedA, unpinnedHidden1, unpinnedB, unpinnedHidden2, unpinnedC,
    ],
    selectedNoteID: pinnedA.id,
    folders: [selected, other]
  )

  try workspace.reorderNote(
    id: pinnedA.id,
    inFolderID: selected.id,
    toVisibleIndex: 2
  )
  try workspace.reorderNote(
    id: unpinnedA.id,
    inFolderID: selected.id,
    toVisibleIndex: 2
  )

  #expect(workspace.notes.map(\.title) == [
    "PH1", "PB", "PH2", "PC", "PA",
    "UH1", "UB", "UH2", "UC", "UA",
  ])
  #expect(workspace.notes.prefix(5).allSatisfy { $0.isPinned })
  #expect(workspace.notes.dropFirst(5).allSatisfy { !$0.isPinned })
  #expect(workspace.notes.filter { $0.folderID == other.id }.map(\.title) == [
    "PH1", "PH2", "UH1", "UH2",
  ])

  let beforeOutOfRange = workspace.notes
  try workspace.reorderNote(
    id: pinnedA.id,
    inFolderID: selected.id,
    toVisibleIndex: 99
  )
  #expect(workspace.notes == beforeOutOfRange)
  #expect(throws: FolderError.invalidTarget) {
    try workspace.reorderNote(
      id: pinnedA.id,
      inFolderID: UUID(),
      toVisibleIndex: 0
    )
  }
  #expect(workspace.notes == beforeOutOfRange)
}
