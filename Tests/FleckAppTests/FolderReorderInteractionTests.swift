import AppKit
import Foundation
import Testing
@testable import FleckApp
import FleckCore

@Test func reorderInteractionFoldersRequireExactLocalSourceSessionAndDistinctPayload() {
  let ids = [UUID(), UUID(), UUID()]
  var interaction = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
  let local = FolderDragPayload.folderProvider(folderID: ids[0], sessionID: interaction.sessionID)
  #expect(FolderDragPayload.matchesFolder([local], interaction: interaction))
  #expect(!FolderDragPayload.matchesFolder([local], interaction: nil))
  #expect(!FolderDragPayload.matchesFolder([local], interaction:
    ReorderInteraction(sourceID: ids[0], originalIDs: ids)))
  #expect(!FolderDragPayload.matchesFolder([FolderDragPayload.noteProvider(source:
    NoteDropSource(noteID: ids[0], sourceFolderID: nil))], interaction: interaction))
  #expect(!FolderDragPayload.matchesFolder([NSItemProvider()], interaction: interaction))
  interaction.propose(over: ids[2], after: true, currentIDs: ids)
  #expect(interaction.consume(currentIDs: [ids[0], ids[1]]) == nil)
}

@Test @MainActor
func reorderInteractionDropPreservesInactiveNoteSelectionAndStoredOrderUntilCommit() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = try Folder(name: "Work")
  for folderID in [nil, folder.id] {
    let pinned = Note(title: "Pinned", isPinned: true, folderID: folderID)
    let notes = [pinned] + ["A", "B", "C"].map { Note(title: $0, folderID: folderID) }
    let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: notes, selectedNoteID: notes[2].id, folders: [folder])
    let original = state.workspace
    var interaction = ReorderInteraction(sourceID: notes[1].id, originalIDs: notes.map(\.id))
    for after in [false, true, false, true] {
      interaction.propose(over: notes[3].id, after: after, currentIDs: state.visibleNotes(in: folderID).map(\.id))
      #expect(state.workspace == original)
    }
    let consumed = interaction.consume(currentIDs: notes.map(\.id))
    let destination = try #require(consumed)
    let local = try #require(TabDragReorder.partitionLocalDestination(draggedID: notes[1].id,
      absoluteDestination: destination, visibleNotes: notes))
    #expect(state.moveNote(notes[1].id, inFolderID: folderID, toVisibleIndex: local))
    #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "C", "A"])
    #expect(state.workspace.selectedNoteID == notes[2].id)
    #expect(interaction.consume(currentIDs: state.visibleNotes(in: folderID).map(\.id)) == nil)
  }
}

@Test func reorderInteractionFolderMidpointsPredictBothDirectionsAndCancel() throws {
  let folders = try ["A", "B", "C"].map { try Folder(name: $0) }
  var workspace = Workspace(folders: folders)
  var drag = ReorderInteraction(sourceID: folders[0].id, originalIDs: folders.map(\.id))
  drag.propose(over: folders[2].id, after: false, currentIDs: folders.map(\.id))
  #expect(drag.destination == 1)
  drag.clearTarget()
  #expect(drag.consume(currentIDs: folders.map(\.id)) == nil)
  #expect(workspace.folders.map(\.name) == ["A", "B", "C"])
  drag.propose(over: folders[2].id, after: true, currentIDs: folders.map(\.id))
  let right = drag.consume(currentIDs: folders.map(\.id))
  try workspace.reorderFolder(id: drag.sourceID, to: #require(right))
  #expect(workspace.folders.map(\.name) == ["B", "C", "A"])
  drag = ReorderInteraction(sourceID: folders[0].id, originalIDs: workspace.folders.map(\.id))
  drag.propose(over: folders[1].id, after: false, currentIDs: workspace.folders.map(\.id))
  let left = drag.consume(currentIDs: workspace.folders.map(\.id))
  try workspace.reorderFolder(id: drag.sourceID, to: #require(left))
  #expect(workspace.folders.map(\.name) == ["A", "B", "C"])
}

@Test @MainActor
func reorderInteractionFolderTransferCommitsBeforeReleaseCleanupAndRejectsStaleSources() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = try Folder(name: "Destination")
  let note = Note(title: "Transfer")
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [folder])
  let source = NoteDropSource(noteID: note.id, sourceFolderID: nil)
  var activeSource: NoteDropSource? = source
  var commits = 0
  func drop(_ providerSource: NoteDropSource?) -> Bool {
    NoteDropPresentation.performLocalDrop(draggedSource: activeSource, providerSource: providerSource,
      targetFolderID: folder.id, notes: state.workspace.notes, validTargetFolderIDs: [folder.id]) {
        source, target in
        commits += 1
        return state.moveNote(source.noteID, fromFolderID: source.sourceFolderID,
          toFolderID: target, activeFolderID: nil)
      }
  }
  #expect(!drop(nil))
  #expect(!drop(NoteDropSource(noteID: note.id, sourceFolderID: nil)))
  #expect(commits == 0)
  #expect(drop(source))
  #expect(state.workspace.notes.first?.folderID == folder.id)
  activeSource = nil // Native release cleanup immediately after performDrop returns.
  #expect(commits == 1)
  #expect(!drop(source))
  activeSource = source // A captured source from before the transfer is stale.
  #expect(!drop(source))
  #expect(commits == 1)
}
