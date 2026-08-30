import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FleckApp
import FleckCore

@Test func noteDropPresentationRejectsSameFolderAndInvalidDragStates() throws {
  let work = try Folder(id: UUID(), name: "Work")
  let other = try Folder(id: UUID(), name: "Other")
  let filed = Note(id: UUID(), title: "Filed", folderID: work.id)
  let unfiled = Note(id: UUID(), title: "Unfiled")
  let notes = [filed, unfiled]
  let folderIDs = Set([work.id, other.id])

  #expect(
    !NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: filed.id, sourceFolderID: work.id),
      targetFolderID: work.id,
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: filed.id, sourceFolderID: work.id),
      targetFolderID: other.id,
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    !NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: unfiled.id, sourceFolderID: nil),
      targetFolderID: nil,
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: unfiled.id, sourceFolderID: nil),
      targetFolderID: work.id,
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    !NoteDropPresentation.isValidTarget(
      draggedSource: nil,
      targetFolderID: work.id,
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    !NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: UUID(), sourceFolderID: work.id),
      targetFolderID: work.id,
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    !NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: filed.id, sourceFolderID: work.id),
      targetFolderID: UUID(),
      notes: notes,
      validTargetFolderIDs: folderIDs
    )
  )
}

@Test func noteDropPresentationFailsClosedWhenLiveNoteMovesAfterDragStarts() throws {
  let sourceFolder = try Folder(id: UUID(), name: "Source")
  let currentFolder = try Folder(id: UUID(), name: "Current")
  let thirdFolder = try Folder(id: UUID(), name: "Third")
  let noteID = UUID()
  let capturedSource = NoteDropSource(noteID: noteID, sourceFolderID: sourceFolder.id)
  let liveNote = Note(id: noteID, title: "Moved", folderID: currentFolder.id)
  let folderIDs = Set([sourceFolder.id, currentFolder.id, thirdFolder.id])

  for targetFolderID in [sourceFolder.id, currentFolder.id, thirdFolder.id] {
    #expect(
      !NoteDropPresentation.isValidTarget(
        draggedSource: capturedSource,
        targetFolderID: targetFolderID,
        notes: [liveNote],
        validTargetFolderIDs: folderIDs
      )
    )
  }
}

@Test func noteDropPresentationAllowsValidUnfiledAndFolderTransfers() throws {
  let folder = try Folder(id: UUID(), name: "Folder")
  let otherFolder = try Folder(id: UUID(), name: "Other")
  let filed = Note(id: UUID(), title: "Filed", folderID: folder.id)
  let unfiled = Note(id: UUID(), title: "Unfiled")
  let folderIDs = Set([folder.id, otherFolder.id])

  #expect(
    NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: filed.id, sourceFolderID: folder.id),
      targetFolderID: otherFolder.id,
      notes: [filed, unfiled],
      validTargetFolderIDs: folderIDs
    )
  )
  #expect(
    NoteDropPresentation.isValidTarget(
      draggedSource: NoteDropSource(noteID: unfiled.id, sourceFolderID: nil),
      targetFolderID: folder.id,
      notes: [filed, unfiled],
      validTargetFolderIDs: folderIDs
    )
  )
}

@Test func noteDragPayloadIsBoundToOneOriginatingPanelSession() throws {
  let source = try tabNotesPanelSource()
  let payload = try #require(
    source.components(separatedBy: "enum FolderDragPayload").last?
      .components(separatedBy: "enum NoteDropPresentation").first
  )
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let tabDropDelegate = try #require(
    source.components(separatedBy: "private struct TabDropDelegate").last?
      .components(separatedBy: "private struct ToolbarIconLabel").first
  )

  #expect(payload.contains("let dragSessionID: UUID"))
  #expect(payload.contains("static func noteProvider(source: NoteDropSource)"))
  #expect(payload.contains("static func noteSource(from providers: [NSItemProvider])"))
  #expect(tabStrip.contains("dragSessionID: UUID()"))
  #expect(tabStrip.contains("noteDropSource = source"))
  #expect(tabStrip.contains("noteProvider(source: source)"))
  #expect(tabDropDelegate.contains("providerSource: providerSource"))
  #expect(tabDropDelegate.contains("draggedSource == providerSource"))
  #expect(navigator.contains("delegate: noteDropDelegate("))
  #expect(navigator.contains("expectedSource: NoteDropSource"))
  #expect(navigator.contains("payload == expectedSource"))
  #expect(navigator.contains("draggedSource == expectedSource"))
  #expect(navigator.contains("if oldValue != newValue"))
  #expect(!navigator.contains("isTargeted: noteDropTargetBinding"))
}

@Test func noteDragSessionRoundTripsAndRejectsOtherOrMissingSessions() throws {
  let sessionID = UUID()
  let source = NoteDropSource(
    noteID: UUID(),
    sourceFolderID: UUID(),
    dragSessionID: sessionID
  )
  let encoded = try JSONEncoder().encode(source)

  #expect(FolderDragPayload.noteValue(from: encoded) == source)
  #expect(FolderDragPayload.noteSource(from: [FolderDragPayload.noteProvider(source: source)]) == source)
  #expect(FolderDragPayload.noteSource(from: [NSItemProvider()]) == nil)

  let otherSession = NoteDropSource(
    noteID: source.noteID,
    sourceFolderID: source.sourceFolderID,
    dragSessionID: UUID()
  )
  let destination = Note(id: UUID(), title: "Destination", folderID: source.sourceFolderID)
  let currentNotes = [
    Note(id: source.noteID, title: "Source", folderID: source.sourceFolderID),
    destination,
  ]
  #expect(otherSession != source)
  #expect(
    !TabDragReorder.isValidLocalDrag(
      draggedSource: source,
      providerSource: otherSession,
      destinationID: destination.id,
      activeFolderID: source.sourceFolderID,
      currentNotes: currentNotes
    )
  )
  #expect(
    TabDragReorder.isValidLocalDrag(
      draggedSource: source,
      providerSource: source,
      destinationID: destination.id,
      activeFolderID: source.sourceFolderID,
      currentNotes: currentNotes
    )
  )
  #expect(
    !TabDragReorder.isValidLocalDrag(
      draggedSource: source,
      providerSource: source,
      destinationID: source.noteID,
      activeFolderID: source.sourceFolderID,
      currentNotes: currentNotes
    )
  )

  let legacyPayload = Data(
    "{\"noteID\":\"\(source.noteID.uuidString)\",\"sourceFolderID\":null}".utf8
  )
  #expect(FolderDragPayload.noteValue(from: legacyPayload) == nil)
  #expect(FolderDragPayload.noteValue(from: Data("not-json".utf8)) == nil)
  #expect(sessionID == source.dragSessionID)
}

@Test func noteDropHighlightUsesCapturedSourceContextAndClearsAtEnd() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let dropDelegate = try #require(
    source.components(separatedBy: "private struct TabDropDelegate").last?
      .components(separatedBy: "private struct ToolbarIconLabel").first
  )

  #expect(tabStrip.contains("let source = NoteDropSource"))
  #expect(tabStrip.contains("noteDropSource = source"))
  #expect(tabStrip.contains("sourceFolderID: note.folderID"))
  #expect(dropDelegate.contains("draggedSource = nil"))
  #expect(dropDelegate.contains("if draggedSource == providerSource"))
  #expect(navigator.contains("NoteDropPresentation.isValidTarget"))
  #expect(navigator.contains("draggedSource"))
  #expect(navigator.contains(".onChange(of: draggedSource)"))
  #expect(navigator.contains("draggedSource = nil"))
  #expect(navigator.contains("noteDropTarget = nil"))
}

@Test func tabStripAllocatesItsActualOverflowViewportAtSupportedWidths() throws {
  #expect(TabOverflowPresentation.tabViewportWidth(totalStripWidth: 380) == 324)
  #expect(TabOverflowPresentation.tabViewportWidth(totalStripWidth: 520) == 464)

  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let scrollViewport = try #require(
    tabStrip.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").last
  )

  #expect(tabStrip.contains("GeometryReader { proxy in"))
  #expect(tabStrip.contains("TabOverflowPresentation.tabViewportWidth(totalStripWidth: proxy.size.width)"))
  #expect(tabStrip.contains(".frame(width: tabViewportWidth, alignment: .leading)"))
  #expect(tabStrip.contains(".frame(height: 37)"))
  #expect(scrollViewport.contains("HStack(spacing: 6) {"))
  #expect(!tabStrip.contains("TabContentLeadingEdgePreferenceKey"))
  #expect(!tabStrip.contains("TabContentTrailingEdgePreferenceKey"))
  #expect(!tabStrip.contains(".coordinateSpace(name: \"tab-scroll-viewport\")"))
  #expect(!tabStrip.contains(".coordinateSpace(name: \"tab-strip\")"))
  #expect(!tabStrip.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
}

@Test func tabStripUsesAStableBidirectionalControlRail() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("chevron.left"))
  #expect(tabStrip.contains("chevron.right"))
  #expect(tabStrip.contains("scrollProxy.scrollTo(firstNoteID, anchor: .leading)"))
  #expect(tabStrip.contains("scrollProxy.scrollTo(lastNoteID, anchor: .trailing)"))
  #expect(tabStrip.contains("accessibilityLabel(\"Reveal earlier tabs\")"))
  #expect(tabStrip.contains("accessibilityLabel(\"Reveal later tabs\")"))
  #expect(tabStrip.contains(".help(\"Show earlier tabs\")"))
  #expect(tabStrip.contains(".help(\"Show later tabs\")"))
  #expect(tabStrip.contains(".frame(width: 56, height: 37"))
  #expect(!tabStrip.contains("accessibilityHidden(!hasHidden"))
  #expect(!tabStrip.contains(".opacity(hasHidden"))
}

@Test func tabStripCentersItsContentAndAvoidsStaleGeometryGates() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains(".frame(height: 37, alignment: .center)"))
  #expect(!tabStrip.contains(".padding(.bottom, 9)"))
  #expect(!source.contains("@State private var tabContentLeadingEdge"))
  #expect(!source.contains("@State private var tabContentTrailingEdge"))
  #expect(!tabStrip.contains("hasHiddenLeadingTabs"))
  #expect(!tabStrip.contains("hasHiddenTrailingTabs"))
  #expect(!tabStrip.contains("onPreferenceChange(TabContentLeadingEdgePreferenceKey"))
  #expect(!tabStrip.contains("onPreferenceChange(TabContentTrailingEdgePreferenceKey"))
  #expect(tabStrip.components(separatedBy: ".disabled(visibleNotes.isEmpty)").count - 1 == 2)
}

@Test func tabStripRemovesTheWindowBackgroundFade() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(!tabStrip.contains("LinearGradient"))
  #expect(!tabStrip.contains("windowBackgroundColor"))
}

@Test @MainActor
func hostedNotesPanelTabOverflowLeftControlReturnsFromTrailingOffset() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("tab-strip-left-control-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let notes = (0..<12).map { index in
    Note(title: "Note " + String(index) + " " + String(repeating: "Long title ", count: 8))
  }
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: notes, selectedNoteID: notes[0].id)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(
    rootView: NotesPanel(dictationRuntime: runtime, sizing: .container)
      .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleTabStripHost(host)

  let tabScrollView = try #require(hostedTabScrollView(in: host))
  let clipView = tabScrollView.contentView
  let leadingOffset = clipView.bounds.origin.x
  let tabFrame = tabScrollView.convert(tabScrollView.bounds, to: host)
  clickHostedTabControl(
    at: NSPoint(x: tabFrame.maxX + 42, y: tabFrame.midY),
    in: window,
    root: host
  )
  await settleTabStripHost(host)
  let trailingOffset = clipView.bounds.origin.x
  #expect(trailingOffset > leadingOffset + 10)

  clickHostedTabControl(
    at: NSPoint(x: tabFrame.maxX + 14, y: tabFrame.midY),
    in: window,
    root: host
  )
  await settleTabStripHost(host)

  #expect(clipView.bounds.origin.x < trailingOffset - 1)
  #expect(clipView.bounds.origin.x <= leadingOffset + 13)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test func tabDragProductionPathUsesOneNativeSourceForReorderAndFolderTransfer() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let tab = try #require(
    tabStrip.components(separatedBy: "ForEach(visibleNotes) { note in").last?
      .components(separatedBy: ".contextMenu {").first
  )
  let label = try #require(
    tab.components(separatedBy: "} label: {").last?
      .components(separatedBy: "            }\n            .buttonStyle(.plain)").first
  )
  let outerModifiers = try #require(
    tab.components(separatedBy: "            }\n            .buttonStyle(.plain)").last
  )
  let dropDelegate = try #require(
    source.components(separatedBy: "private struct TabDropDelegate").last?
      .components(separatedBy: "private struct ToolbarIconLabel").first
  )
  let reorder = try #require(
    source.components(separatedBy: "enum TabDragReorder").last?
      .components(separatedBy: "enum TabOverflowPresentation").first
  )

  #expect(!label.contains(".onDrag"))
  #expect(outerModifiers.contains(".onDrag"))
  #expect(outerModifiers.contains("let source = NoteDropSource"))
  #expect(outerModifiers.contains("noteDropSource = source"))
  #expect(outerModifiers.contains("FolderDragPayload.noteProvider"))
  #expect(outerModifiers.contains(".onDrop("))
  #expect(outerModifiers.contains("of: [FolderDragPayload.noteType]"))
  #expect(outerModifiers.contains("delegate: TabDropDelegate("))
  #expect(outerModifiers.contains("activeFolderID: activeFolderID"))
  #expect(outerModifiers.contains("currentNotes: { visibleNotes }"))
  #expect(!outerModifiers.contains(".simultaneousGesture("))
  #expect(!outerModifiers.contains("DragGesture("))
  #expect(dropDelegate.contains("TabDragReorder.performLiveMove"))
  #expect(dropDelegate.contains("DropProposal(operation: .move)"))
  #expect(reorder.contains("draggedSource.sourceFolderID == activeFolderID"))
  #expect(reorder.contains("currentNotes: () -> [Note]"))
  #expect(reorder.contains("partitionLocalDestination"))
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
  let source = NoteDropSource(noteID: first.id, sourceFolderID: folderID)
  func drag(over destinationID: UUID) -> TabDragReorder.LiveMoveResult {
    let result = TabDragReorder.performLiveMove(
      draggedSource: source,
      providerSource: source,
      over: destinationID,
      activeFolderID: folderID,
      currentNotes: { state.visibleNotes(in: folderID) },
      lastDestinationID: lastDestinationID,
      move: { id, localDestination in
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

  #expect(drag(over: second.id).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "A", "C"])
  #expect(drag(over: third.id).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "C", "A"])
  #expect(!drag(over: third.id).didMove)
  #expect(drag(over: third.id).didMove == false)
  lastDestinationID = nil
  #expect(drag(over: third.id).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "B", "A", "C"])
  #expect(drag(over: second.id).didMove)
  #expect(state.visibleNotes(in: folderID).map(\.title) == ["Pinned", "A", "B", "C"])
  #expect(!drag(over: second.id).didMove)
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
  let reorder = try #require(
    source.components(separatedBy: "enum TabDragReorder").last?
      .components(separatedBy: "enum TabOverflowPresentation").first
  )
  let moveFunction = try #require(
    source.components(separatedBy: "private func move(_ note: Note, offset: Int)").last?
      .components(separatedBy: "private func startExport").first
  )

  #expect(reorder.contains("partitionLocalDestination"))
  #expect(reorder.contains("absoluteDestination: absoluteDestination"))
  #expect(moveFunction.contains("TabDragReorder.partitionLocalDestination"))
  #expect(moveFunction.contains("absoluteDestination: index + offset"))
  #expect(!moveFunction.contains("toVisibleIndex: index + offset"))
}

@Test func liveTabDragMovesFirstAcrossSecondAndThirdUsingCurrentTargets() {
  let first = Note(title: "A")
  let second = Note(title: "B")
  let third = Note(title: "C")
  var notes = [first, second, third]
  var lastDestinationID: UUID?
  var moves: [(UUID, Int)] = []
  let source = NoteDropSource(noteID: first.id, sourceFolderID: nil)

  func move(_ id: UUID, to destination: Int) {
    moves.append((id, destination))
    let source = notes.firstIndex(where: { $0.id == id })!
    notes.insert(notes.remove(at: source), at: destination)
  }

  func drag(over destinationID: UUID) -> TabDragReorder.LiveMoveResult {
    let result = TabDragReorder.performLiveMove(
      draggedSource: source,
      providerSource: source,
      over: destinationID,
      activeFolderID: nil,
      currentNotes: { notes },
      lastDestinationID: lastDestinationID,
      move: move
    )
    lastDestinationID = result.destinationID
    return result
  }

  #expect(drag(over: second.id).didMove)
  #expect(notes == [second, first, third])
  #expect(drag(over: second.id).didMove == false)
  #expect(drag(over: third.id).didMove)
  #expect(notes == [second, third, first])
  #expect(drag(over: second.id).didMove)
  #expect(notes == [first, second, third])
  #expect(moves.map(\.0) == [first.id, first.id, first.id])
  #expect(moves.map(\.1) == [1, 2, 0])
}

@Test func liveTabDragRejectsInvalidStaleAndCrossFolderTargets() throws {
  let folder = try Folder(name: "Work")
  let first = Note(title: "A", folderID: folder.id)
  let second = Note(title: "B", folderID: folder.id)
  let missing = UUID()
  let notes = [first, second]
  var moves: [(UUID, Int)] = []

  func result(
    source: NoteDropSource?,
    destinationID: UUID,
    activeFolderID: UUID? = folder.id
  ) -> TabDragReorder.LiveMoveResult {
    TabDragReorder.performLiveMove(
      draggedSource: source,
      providerSource: source,
      over: destinationID,
      activeFolderID: activeFolderID,
      currentNotes: { notes },
      lastDestinationID: nil,
      move: { moves.append(($0, $1)) }
    )
  }

  #expect(!result(source: nil, destinationID: second.id).didMove)
  #expect(
    !result(
      source: NoteDropSource(noteID: first.id, sourceFolderID: folder.id),
      destinationID: first.id
    ).didMove
  )
  #expect(
    !result(
      source: NoteDropSource(noteID: missing, sourceFolderID: folder.id),
      destinationID: second.id
    ).didMove
  )
  #expect(
    !result(
      source: NoteDropSource(noteID: first.id, sourceFolderID: nil),
      destinationID: second.id
    ).didMove
  )
  #expect(
    !result(
      source: NoteDropSource(noteID: first.id, sourceFolderID: folder.id),
      destinationID: second.id,
      activeFolderID: nil
    ).didMove
  )
  #expect(
    !result(
      source: NoteDropSource(noteID: first.id, sourceFolderID: folder.id),
      destinationID: missing
    ).didMove
  )
  #expect(moves.isEmpty)
}

@Test func liveTabDragUsesCurrentOrderWhenMovingBackLeft() {
  let first = Note(title: "A")
  let second = Note(title: "B")
  let third = Note(title: "C")
  var notes = [first, second, third]
  var lastDestinationID: UUID?
  let source = NoteDropSource(noteID: third.id, sourceFolderID: nil)

  func move(_ id: UUID, to destination: Int) {
    let source = notes.firstIndex(where: { $0.id == id })!
    notes.insert(notes.remove(at: source), at: destination)
  }

  var result = TabDragReorder.performLiveMove(
    draggedSource: source,
    providerSource: source,
    over: second.id,
    activeFolderID: nil,
    currentNotes: { notes },
    lastDestinationID: lastDestinationID,
    move: move
  )
  lastDestinationID = result.destinationID
  #expect(result.didMove)
  #expect(notes == [first, third, second])

  result = TabDragReorder.performLiveMove(
    draggedSource: source,
    providerSource: source,
    over: first.id,
    activeFolderID: nil,
    currentNotes: { notes },
    lastDestinationID: lastDestinationID,
    move: move
  )
  #expect(result.didMove)
  #expect(notes == [third, first, second])
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
  let pinnedSource = NoteDropSource(noteID: pinned.id, sourceFolderID: nil)
  var result = TabDragReorder.performLiveMove(
    draggedSource: pinnedSource,
    providerSource: pinnedSource,
    over: firstUnpinned.id,
    activeFolderID: nil,
    currentNotes: { workspace.notes },
    lastDestinationID: lastDestinationID,
    move: move
  )
  lastDestinationID = result.destinationID
  #expect(result.didMove)
  #expect(workspace.notes == [pinned, firstUnpinned, secondUnpinned])

  result = TabDragReorder.performLiveMove(
    draggedSource: pinnedSource,
    providerSource: pinnedSource,
    over: firstUnpinned.id,
    activeFolderID: nil,
    currentNotes: { workspace.notes },
    lastDestinationID: lastDestinationID,
    move: move
  )
  #expect(!result.didMove)

  lastDestinationID = nil
  let unpinnedSource = NoteDropSource(noteID: secondUnpinned.id, sourceFolderID: nil)
  result = TabDragReorder.performLiveMove(
    draggedSource: unpinnedSource,
    providerSource: unpinnedSource,
    over: pinned.id,
    activeFolderID: nil,
    currentNotes: { workspace.notes },
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
  #expect(navigator.contains("private struct NoteDropDelegate: DropDelegate"))
  #expect(navigator.contains("delegate: noteDropDelegate("))
  #expect(navigator.contains("providerSource == expectedSource"))
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

@MainActor
private func hostedTabScrollView(in view: NSView) -> NSScrollView? {
  if let scrollView = view as? NSScrollView,
    let documentView = scrollView.documentView,
    scrollView.frame.height <= 50,
    documentView.frame.width > scrollView.contentView.bounds.width + 1
  {
    return scrollView
  }
  for subview in view.subviews {
    if let scrollView = hostedTabScrollView(in: subview) {
      return scrollView
    }
  }
  return nil
}

@MainActor
private func clickHostedTabControl(at point: NSPoint, in window: NSWindow, root: NSView) {
  let location = root.convert(point, to: nil)
  for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    guard let event = NSEvent.mouseEvent(
      with: eventType,
      location: location,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: eventType == .leftMouseDown ? 1 : 0
    ) else { continue }
    window.sendEvent(event)
  }
}

@MainActor
private func settleTabStripHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@Test func tabOverflowEndpointControlsStayEnabledForVisibleNotes() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.components(separatedBy: ".disabled(visibleNotes.isEmpty)").count - 1 == 2)
}
