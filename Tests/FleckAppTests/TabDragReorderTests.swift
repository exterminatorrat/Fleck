import Foundation
import SwiftUI
import Testing

@testable import FleckApp
import FleckCore

@Test func tabStripAllocatesItsActualOverflowViewportAtSupportedWidths() throws {
  #expect(TabOverflowPresentation.tabViewportWidth(totalStripWidth: 380) == 352)
  #expect(TabOverflowPresentation.tabViewportWidth(totalStripWidth: 520) == 492)

  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let scrollViewport = try #require(
    tabStrip.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").last?
      .components(separatedBy: "if hasHiddenTrailingTabs").first
  )
  let tabContent = try #require(
    scrollViewport.components(separatedBy: "HStack(spacing: 6) {").last?
      .components(separatedBy: ".padding(.horizontal, 12)").first
  )

  #expect(tabStrip.contains("GeometryReader { proxy in"))
  #expect(tabStrip.contains("TabOverflowPresentation.tabViewportWidth(totalStripWidth: proxy.size.width)"))
  #expect(tabStrip.contains(".frame(width: tabViewportWidth, alignment: .leading)"))
  #expect(tabStrip.contains(".frame(height: 37)"))
  #expect(tabStrip.contains("visibleTrailingEdge: tabViewportWidth"))
  #expect(scrollViewport.contains(".coordinateSpace(name: \"tab-scroll-viewport\")"))
  #expect(tabContent.contains("Color.clear"))
  #expect(tabContent.contains(".frame(width: 0, height: 0)"))
  #expect(tabContent.contains("value: proxy.frame(in: .named(\"tab-scroll-viewport\")).minX - 6"))
  #expect(!tabContent.contains("value: proxy.frame(in: .named(\"tab-scroll-viewport\")).maxX"))
  #expect(!tabStrip.contains("TabViewportTrailingEdgePreferenceKey"))
  #expect(tabStrip.contains(".coordinateSpace(name: \"tab-strip\")"))
  #expect(!tabStrip.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
}

@Test func liveTabDragProductionPathUsesLocalHorizontalGestureAndCurrentFrames() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("DragGesture("))
  #expect(tabStrip.contains("coordinateSpace: .named(\"tab-strip\")"))
  #expect(tabStrip.contains("value.translation.width"))
  #expect(tabStrip.contains("TabDragReorder.performLiveMove"))
  #expect(tabStrip.contains("TabFramePreferenceKey"))
  #expect(tabStrip.contains("proxy.frame(in: .named(\"tab-strip\"))"))
  #expect(tabStrip.contains("appState.moveNote"))
  #expect(tabStrip.contains("toVisibleIndex: localDestination"))
  #expect(tabStrip.contains(".onDrag"))
  #expect(!tabStrip.contains(".onDrop"))
  #expect(!tabStrip.contains("TabDropDelegate"))
}

@Test func tabContextMenuExposesCurrentFolderMoveDestinations() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("Move to Folder"))
  #expect(tabStrip.contains("Unfiled"))
  #expect(tabStrip.contains("appState.workspace.folders"))
  #expect(tabStrip.contains("fromFolderID"))
  #expect(tabStrip.contains("toFolderID"))
  #expect(tabStrip.contains(".disabled"))
  #expect(tabStrip.contains("checkmark"))
}

@Test @MainActor
func partitionLocalLiveMoveUsesAppStateInUnfiledAndNamedFolderScopes() async throws {
  let folder = try Folder(id: UUID(), name: "Work")
  try await assertPartitionLocalLiveMove(folderID: nil, folders: [])
  try await assertPartitionLocalLiveMove(folderID: folder.id, folders: [folder])
}

@MainActor
private func assertPartitionLocalLiveMove(
  folderID: UUID?,
  folders: [Folder]
) async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("tab-reorder-state-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let pinned = Note(title: "Pinned", isPinned: true, folderID: folderID)
  let first = Note(title: "A", folderID: folderID)
  let second = Note(title: "B", folderID: folderID)
  let third = Note(title: "C", folderID: folderID)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [pinned, first, second, third],
    selectedNoteID: first.id,
    folders: folders
  )

  var lastDestinationID: UUID?
  func drag(_ locationX: CGFloat) -> TabDragReorder.LiveMoveResult {
    let result = TabDragReorder.performLiveMove(
      draggedID: first.id,
      locationX: locationX,
      currentNoteIDs: {
        state.visibleNotes(in: folderID).map(\.id)
      },
      currentFrames: {
        tabFrames(for: state.visibleNotes(in: folderID).map(\.id))
      },
      lastDestinationID: lastDestinationID,
      move: { id, absoluteDestination in
        let visibleNotes = state.visibleNotes(in: folderID)
        guard let localDestination = TabDragReorder.partitionLocalDestination(
          draggedID: id,
          absoluteDestination: absoluteDestination,
          visibleNotes: visibleNotes
        ) else { return }
        _ = state.moveNote(
          id,
          inFolderID: folderID,
          toVisibleIndex: localDestination
        )
      }
    )
    lastDestinationID = result.destinationID
    return result
  }

  #expect(drag(270).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "A", "C"])
  #expect(drag(380).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "C", "A"])
  #expect(!drag(500).didMove)
  #expect(drag(250).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "A", "C"])
  #expect(drag(140).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "A", "B", "C"])
  #expect(!drag(140).didMove)
  #expect(state.workspace.selectedNoteID == first.id)
}

@Test @MainActor
func contextMovesUsePartitionLocalMapperInUnfiledAndNamedFolderScopes() async throws {
  let folder = try Folder(id: UUID(), name: "Work")
  try await assertContextMoves(folderID: nil, folders: [])
  try await assertContextMoves(folderID: folder.id, folders: [folder])
}

@MainActor
private func assertContextMoves(folderID: UUID?, folders: [Folder]) async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("tab-reorder-context-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let pinned = Note(title: "Pinned", isPinned: true, folderID: folderID)
  let first = Note(title: "A", folderID: folderID)
  let second = Note(title: "B", folderID: folderID)
  let third = Note(title: "C", folderID: folderID)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [pinned, first, second, third],
    selectedNoteID: first.id,
    folders: folders
  )

  func contextMove(_ noteID: UUID, offset: Int) -> Bool {
    let visibleNotes = state.visibleNotes(in: folderID)
    guard let index = visibleNotes.firstIndex(where: { $0.id == noteID }),
      let localDestination = TabDragReorder.partitionLocalDestination(
        draggedID: noteID,
        absoluteDestination: index + offset,
        visibleNotes: visibleNotes
      )
    else { return false }
    return state.moveNote(
      noteID,
      inFolderID: folderID,
      toVisibleIndex: localDestination
    )
  }

  #expect(contextMove(first.id, offset: 1))
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "A", "C"])
  #expect(contextMove(first.id, offset: 1))
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "C", "A"])
  #expect(contextMove(first.id, offset: -1))
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "A", "C"])
  #expect(contextMove(first.id, offset: -1))
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "A", "B", "C"])
  #expect(!contextMove(pinned.id, offset: 1))
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "A", "B", "C"])
}

@Test func tabReorderUsesOnePartitionLocalMapperForDragAndContextMoves() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let moveFunction = try #require(
    source.components(separatedBy: "private func move(_ note: Note, offset: Int)").last?
      .components(separatedBy: "private func startExport").first
  )

  #expect(tabStrip.contains("TabDragReorder.partitionLocalDestination"))
  #expect(tabStrip.contains("absoluteDestination: destination"))
  #expect(moveFunction.contains("TabDragReorder.partitionLocalDestination"))
  #expect(moveFunction.contains("absoluteDestination: index + offset"))
  #expect(!tabStrip.contains("toVisibleIndex: destination"))
  #expect(!moveFunction.contains("toVisibleIndex: index + offset"))
}

@Test func liveTabDragMovesFirstAcrossSecondAndThirdUsingCurrentFrames() {
  let first = UUID()
  let second = UUID()
  let third = UUID()
  var ids = [first, second, third]
  var lastDestinationID: UUID?
  var moves: [(UUID, Int)] = []

  func move(_ id: UUID, to destination: Int) {
    moves.append((id, destination))
    let source = ids.firstIndex(of: id)!
    ids.insert(ids.remove(at: source), at: destination)
  }

  func drag(_ locationX: CGFloat) -> TabDragReorder.LiveMoveResult {
    let result = TabDragReorder.performLiveMove(
      draggedID: first,
      locationX: locationX,
      currentNoteIDs: { ids },
      currentFrames: { tabFrames(for: ids) },
      lastDestinationID: lastDestinationID,
      move: move
    )
    lastDestinationID = result.destinationID
    return result
  }

  #expect(drag(160).didMove)
  #expect(ids == [second, first, third])
  #expect(drag(160).didMove == false)
  #expect(drag(270).didMove)
  #expect(ids == [second, third, first])
  #expect(drag(30).didMove)
  #expect(ids == [first, second, third])
  #expect(moves.map(\.0) == [first, first, first])
  #expect(moves.map(\.1) == [1, 2, 0])
}

@Test func liveTabDragIgnoresInvalidAndSameTabTargets() {
  let first = UUID()
  let second = UUID()
  let missing = UUID()
  let ids = [first, second]
  let frames = tabFrames(for: ids)

  #expect(
    TabDragReorder.destination(
      draggedID: nil,
      locationX: 150,
      currentNoteIDs: ids,
      currentFrames: frames
    ) == nil
  )
  #expect(
    TabDragReorder.destination(
      draggedID: first,
      locationX: 40,
      currentNoteIDs: ids,
      currentFrames: frames
    ) == nil
  )
  #expect(
    TabDragReorder.destination(
      draggedID: missing,
      locationX: 150,
      currentNoteIDs: ids,
      currentFrames: frames
    ) == nil
  )
  #expect(
    TabDragReorder.destination(
      draggedID: first,
      locationX: 150,
      currentNoteIDs: ids,
      currentFrames: [first: frames[first]!]
    ) == nil
  )
}

@Test func liveTabDragUsesCurrentOrderAndFramesWhenMovingBackLeft() {
  let first = UUID()
  let second = UUID()
  let third = UUID()
  var ids = [first, second, third]
  var lastDestinationID: UUID?

  func move(_ id: UUID, to destination: Int) {
    let source = ids.firstIndex(of: id)!
    ids.insert(ids.remove(at: source), at: destination)
  }

  var result = TabDragReorder.performLiveMove(
    draggedID: third,
    locationX: 140,
    currentNoteIDs: { ids },
    currentFrames: { tabFrames(for: ids) },
    lastDestinationID: lastDestinationID,
    move: move
  )
  lastDestinationID = result.destinationID
  #expect(result.didMove)
  #expect(ids == [first, third, second])

  result = TabDragReorder.performLiveMove(
    draggedID: third,
    locationX: 30,
    currentNoteIDs: { ids },
    currentFrames: { tabFrames(for: ids) },
    lastDestinationID: lastDestinationID,
    move: move
  )
  #expect(result.didMove)
  #expect(ids == [third, first, second])
}

@Test func liveTabDragClampsPinnedAndUnpinnedNotesAtTheirPartitionEdges() {
  let pinned = Note(title: "Pinned", body: "A", richTextRTF: Data([1]), isPinned: true)
  let firstUnpinned = Note(title: "First", body: "B", richTextRTF: Data([2]))
  let secondUnpinned = Note(title: "Second", body: "C", richTextRTF: Data([3]))
  var workspace = Workspace(
    notes: [pinned, firstUnpinned, secondUnpinned], selectedNoteID: secondUnpinned.id
  )

  func move(_ id: UUID, to destination: Int) {
    workspace.moveNote(id: id, to: destination)
  }

  var lastDestinationID: UUID?
  var result = TabDragReorder.performLiveMove(
    draggedID: pinned.id,
    locationX: 160,
    currentNoteIDs: { workspace.notes.map(\.id) },
    currentFrames: { tabFrames(for: workspace.notes.map(\.id)) },
    lastDestinationID: lastDestinationID,
    move: move
  )
  lastDestinationID = result.destinationID
  #expect(result.didMove)
  #expect(workspace.notes == [pinned, firstUnpinned, secondUnpinned])

  result = TabDragReorder.performLiveMove(
    draggedID: pinned.id,
    locationX: 160,
    currentNoteIDs: { workspace.notes.map(\.id) },
    currentFrames: { tabFrames(for: workspace.notes.map(\.id)) },
    lastDestinationID: lastDestinationID,
    move: move
  )
  #expect(!result.didMove)

  lastDestinationID = nil
  result = TabDragReorder.performLiveMove(
    draggedID: secondUnpinned.id,
    locationX: 30,
    currentNoteIDs: { workspace.notes.map(\.id) },
    currentFrames: { tabFrames(for: workspace.notes.map(\.id)) },
    lastDestinationID: lastDestinationID,
    move: move
  )
  #expect(result.didMove)
  #expect(workspace.notes == [pinned, secondUnpinned, firstUnpinned])
  #expect(workspace.selectedNoteID == secondUnpinned.id)
}

@Test func TabDragReorderFolderScopePreservesGlobalOrder() throws {
  let folder = try Folder(name: "Visible")
  let other = try Folder(name: "Other")
  let pinnedA = Note(title: "A", isPinned: true, folderID: folder.id)
  let pinnedHidden = Note(title: "H1", isPinned: true, folderID: other.id)
  let pinnedB = Note(title: "B", isPinned: true, folderID: folder.id)
  let pinnedHiddenTwo = Note(title: "H2", isPinned: true, folderID: other.id)
  let pinnedC = Note(title: "C", isPinned: true, folderID: folder.id)
  var workspace = Workspace(
    notes: [pinnedA, pinnedHidden, pinnedB, pinnedHiddenTwo, pinnedC],
    selectedNoteID: pinnedA.id,
    folders: [folder, other]
  )

  try workspace.reorderNote(id: pinnedA.id, inFolderID: folder.id, toVisibleIndex: 1)
  #expect(workspace.notes.map(\.id) == [pinnedHidden.id, pinnedB.id, pinnedHiddenTwo.id, pinnedA.id, pinnedC.id])
  #expect(workspace.notes(inFolderID: folder.id).map(\.id) == [pinnedB.id, pinnedA.id, pinnedC.id])

  var movedToFront = Workspace(
    notes: [pinnedA, pinnedHidden, pinnedB, pinnedHiddenTwo, pinnedC],
    selectedNoteID: pinnedA.id,
    folders: [folder, other]
  )
  try movedToFront.reorderNote(id: pinnedC.id, inFolderID: folder.id, toVisibleIndex: 0)
  #expect(movedToFront.notes.map(\.id) == [pinnedC.id, pinnedA.id, pinnedHidden.id, pinnedB.id, pinnedHiddenTwo.id])
}

@Test func TabDragReorderFolderOrderUsesPostRemovalInsertionIndex() throws {
  let folders = try ["A", "B", "C", "D"].map { try Folder(name: $0) }
  var workspace = Workspace(folders: folders)

  try workspace.reorderFolder(id: folders[2].id, to: 0)
  #expect(workspace.folders.map(\.name) == ["C", "A", "B", "D"])
  try workspace.reorderFolder(id: workspace.folders[2].id, to: 2)
  #expect(workspace.folders.map(\.name) == ["C", "A", "B", "D"])
  try workspace.reorderFolder(id: workspace.folders[2].id, to: 3)
  #expect(workspace.folders.map(\.name) == ["C", "A", "D", "B"])
  try workspace.reorderFolder(id: UUID(), to: 0)
  #expect(workspace.folders.map(\.name) == ["C", "A", "D", "B"])
}

@Test func TabDragReorderFolderNavigatorUsesLocalPayloadsAndKeyboardContracts() throws {
  let source = try tabNotesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )

  #expect(source.contains("com.harryjin.fleck.local-note"))
  #expect(source.contains("com.harryjin.fleck.local-folder"))
  #expect(navigator.contains("loadDataRepresentation"))
  #expect(navigator.contains("onDrop"))
  #expect(navigator.contains("onDrag"))
  #expect(navigator.contains("onMoveCommand"))
  #expect(navigator.contains("onDeleteCommand"))
  #expect(navigator.contains("onExitCommand"))
  #expect(navigator.contains("NSF2FunctionKey"))
  #expect(navigator.contains("name: \"Unfiled\""))
  #expect(navigator.contains("name: \"Trash\""))
  #expect(navigator.range(of: "rootRow")!.lowerBound < navigator.range(of: "Divider()")!.lowerBound)
  #expect(navigator.range(of: "Divider()")!.lowerBound < navigator.range(of: "name: \"Trash\"")!.lowerBound)
  #expect(!navigator.contains("All Notes"))
  #expect(!navigator.contains("Inbox"))
}

@Test func folderNoteDropsUseTypeSpecificTransientAccentTargets() throws {
  let source = try tabNotesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )

  #expect(navigator.contains("private enum NoteDropTarget"))
  #expect(navigator.contains("@State private var noteDropTarget"))
  #expect(navigator.contains("noteDropTargetBinding"))
  #expect(navigator.contains("isTargeted: noteDropTargetBinding"))
  #expect(navigator.contains("Color.accentColor.opacity"))
  #expect(navigator.contains("noteDropTarget = nil"))
  #expect(navigator.contains("sourceFolderID"))
  #expect(navigator.contains("targetFolderID"))
  #expect(navigator.contains("workspace.folders.contains"))
  #expect(navigator.contains("of: [FolderDragPayload.noteType]"))
  #expect(navigator.contains("of: [FolderDragPayload.folderType]"))
  #expect(!navigator.contains("of: [FolderDragPayload.noteType, FolderDragPayload.folderType]"))
}

@Test func tabStripKeepsManualOrderAndPinnedPartitionWithoutRecencySorting() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("visibleNotes.map(\\.id)"))
  #expect(tabStrip.contains("inFolderID: activeFolderID"))
  #expect(tabStrip.contains("toVisibleIndex: localDestination"))
  #expect(!tabStrip.contains("modifiedAt"))
  #expect(!tabStrip.contains("sorted("))
}

@Test func FolderNavigatorFocusMovesOnlyVertically() {
  #expect(
    FolderNavigatorFocus.nextIndex(
      currentIndex: 1,
      direction: .up,
      count: 4
    ) == 0
  )
  #expect(
    FolderNavigatorFocus.nextIndex(
      currentIndex: 1,
      direction: .down,
      count: 4
    ) == 2
  )
  #expect(
    FolderNavigatorFocus.nextIndex(
      currentIndex: 1,
      direction: .left,
      count: 4
    ) == 1
  )
  #expect(
    FolderNavigatorFocus.nextIndex(
      currentIndex: 1,
      direction: .right,
      count: 4
    ) == 1
  )
  #expect(
    FolderNavigatorFocus.nextIndex(
      currentIndex: 0,
      direction: .up,
      count: 4
    ) == 0
  )
  #expect(
    FolderNavigatorFocus.nextIndex(
      currentIndex: 3,
      direction: .down,
      count: 4
    ) == 3
  )
}

private func tabFrames(for noteIDs: [UUID]) -> [UUID: CGRect] {
  Dictionary(uniqueKeysWithValues: noteIDs.enumerated().map { index, id in
    (id, CGRect(x: CGFloat(index) * 106, y: 0, width: 100, height: 36))
  })
}

private func tabNotesPanelSource() throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
}

@Test func tabOverflowShowsOnlyWhenTrailingContentExceedsVisibleEdge() {
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 100,
      visibleTrailingEdge: 100
    )
  )
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 99,
      visibleTrailingEdge: 100
    )
  )
  #expect(
    TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 101,
      visibleTrailingEdge: 100
    )
  )
}

@Test func tabOverflowDoesNotInferHiddenTrailingContentFromLeadingOffset() {
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 180,
      visibleTrailingEdge: 180
    )
  )
}

@Test func tabOverflowHidesWhenTheRealLastTabTrailingEdgeIsRevealed() {
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 492,
      visibleTrailingEdge: 492
    )
  )
}
