import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FleckApp
import FleckCore

private final class NativePreviewDraggingSessionProbe: NSDraggingSession {}

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
  #expect(payload.contains("loadDataRepresentation(forTypeIdentifier:"))
  #expect(!payload.contains("LocalNoteItemProvider"))
  #expect(tabStrip.contains("dragSessionID: interaction.sessionID"))
  #expect(tabStrip.contains("noteDropSource = source"))
  #expect(tabStrip.contains("noteProvider(source: source)"))
  #expect(tabStrip.contains("reorderDragSession?.cancel()"))
  #expect(tabDropDelegate.contains("session.acceptReorder"))
  #expect(navigator.contains("delegate: noteDropDelegate("))
  #expect(navigator.contains("expectedSource: NoteDropSource"))
  #expect(navigator.contains("dragSession.acceptNoteTransfer"))
  #expect(navigator.contains("draggedSource == expectedSource"))
  #expect(navigator.contains("if oldValue != newValue"))
  #expect(!navigator.contains("isTargeted: noteDropTargetBinding"))
}

@Test @MainActor func noteDragSessionRoundTripsAndRejectsOtherOrMissingSessions() async throws {
  let sessionID = UUID()
  let source = NoteDropSource(
    noteID: UUID(),
    sourceFolderID: UUID(),
    dragSessionID: sessionID
  )
  let encoded = try JSONEncoder().encode(source)

  #expect(FolderDragPayload.noteValue(from: encoded) == source)

  let otherSession = NoteDropSource(
    noteID: source.noteID,
    sourceFolderID: source.sourceFolderID,
    dragSessionID: UUID()
  )
  for providerSource in [otherSession, source] {
    let session = ReorderDropSession(source: source)
    var commits = 0
    let load = try #require(session.acceptDrop(from: [FolderDragPayload.noteProvider(source: providerSource)]) {
      commits += 1
    })
    session.end(operation: .move)
    await load.value
    #expect(commits == (providerSource == source ? 1 : 0))
  }

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
  #expect(tabStrip.contains("if noteDropSource == source { noteDropSource = nil }"))
  #expect(dropDelegate.contains("interaction = nil"))
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
  #expect(scrollViewport.contains(".id(TabScrollTarget.leading)"))
  #expect(scrollViewport.contains(".id(TabScrollTarget.trailing)"))
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
  #expect(tabStrip.contains("scrollProxy.scrollTo(TabScrollTarget.leading, anchor: .leading)"))
  #expect(tabStrip.contains("scrollProxy.scrollTo(TabScrollTarget.trailing, anchor: .trailing)"))
  #expect(!tabStrip.contains("scrollProxy.scrollTo(firstNoteID, anchor: .leading)"))
  #expect(!tabStrip.contains("scrollProxy.scrollTo(lastNoteID, anchor: .trailing)"))
  #expect(tabStrip.contains("accessibilityLabel(\"Reveal earlier tabs\")"))
  #expect(tabStrip.contains("accessibilityLabel(\"Reveal later tabs\")"))
  #expect(tabStrip.contains(".help(\"Show earlier tabs\")"))
  #expect(tabStrip.contains(".help(\"Show later tabs\")"))
  #expect(tabStrip.contains(".frame(width: 56, height: 37"))
  #expect(tabStrip.components(separatedBy: ".frame(width: 28, height: 37)").count - 1 == 2)
  #expect(tabStrip.components(separatedBy: ".contentShape(Rectangle())").count - 1 == 2)
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
  let documentView = try #require(tabScrollView.documentView)
  let leadingOffset = clipView.bounds.origin.x
  let maximumOffset = documentView.frame.maxX - clipView.bounds.width
  let tabFrame = tabScrollView.convert(tabScrollView.bounds, to: host)
  // The top two points of each rail half are outside the current 28-point button frame.
  let offGlyphY = tabFrame.minY + 2
  clickHostedTabControl(
    at: NSPoint(x: tabFrame.maxX + 42, y: offGlyphY),
    in: window,
    root: host
  )
  await settleTabStripHost(host)
  let trailingOffset = clipView.bounds.origin.x
  #expect(abs(trailingOffset - maximumOffset) <= 1)

  clickHostedTabControl(
    at: NSPoint(x: tabFrame.maxX + 14, y: offGlyphY),
    in: window,
    root: host
  )
  await settleTabStripHost(host)

  #expect(clipView.bounds.origin.x < trailingOffset - 1)
  #expect(abs(clipView.bounds.origin.x - leadingOffset) <= 1)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
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
  #expect(source.contains("absoluteDestination: destination,"))
  #expect(source.contains("visibleNotes: appState.visibleNotes(in: note.folderID)"))
  #expect(moveFunction.contains("TabDragReorder.partitionLocalDestination"))
  #expect(moveFunction.contains("absoluteDestination: index + offset"))
  #expect(!moveFunction.contains("toVisibleIndex: index + offset"))
}

@Test @MainActor func reorderInteractionRejectsInvalidStaleAndCrossFolderTargets() async throws {
  let folder = try Folder(name: "Work")
  let first = Note(title: "A", folderID: folder.id)
  let second = Note(title: "B", folderID: folder.id)
  let ids = [first.id, second.id]
  var interaction = ReorderInteraction(sourceID: first.id, originalIDs: ids)
  interaction.propose(over: second.id, after: true, currentIDs: ids)
  let source = NoteDropSource(noteID: first.id, sourceFolderID: folder.id, dragSessionID: interaction.sessionID)
  let session = ReorderDropSession(source: source)
  var commits = 0
  #expect(session.acceptReorder(from: [FolderDragPayload.noteProvider(source: source)],
    interaction: interaction, currentIDs: { [first.id] }, currentPinnedIDs: { [] },
    move: { _, _ in commits += 1 }) == nil)
  var invalidSource = ReorderInteraction(sourceID: UUID(), originalIDs: ids)
  invalidSource.propose(over: second.id, after: true, currentIDs: ids)
  #expect(invalidSource.destination == nil)
  let otherScope = NoteDropSource(noteID: source.noteID, sourceFolderID: nil, dragSessionID: source.dragSessionID)
  let load = try #require(session.acceptReorder(from: [FolderDragPayload.noteProvider(source: otherScope)],
    interaction: interaction, currentIDs: { ids }, currentPinnedIDs: { [] },
    move: { _, _ in commits += 1 }))
  session.end(operation: .move)
  await load.value
  #expect(commits == 0)
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
    source.components(separatedBy: "private struct FolderNavigator").last?
      .components(separatedBy: "private struct DeleteConfirmationOverlay").first
  )

  #expect(source.contains("com.harryjin.fleck.local-note"))
  #expect(source.contains("com.harryjin.fleck.local-folder"))
  #expect(navigator.contains("dragSession.acceptNoteTransfer"))
  #expect(navigator.contains("onDrop"))
  #expect(navigator.contains(".modifier(ReorderDragSource("))
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
    source.components(separatedBy: "private struct FolderNavigator").last?
      .components(separatedBy: "private struct DeleteConfirmationOverlay").first
  )

  #expect(navigator.contains("private enum NoteDropTarget"))
  #expect(navigator.contains("@State private var noteDropTarget"))
  #expect(navigator.contains("private struct NoteDropDelegate: DropDelegate"))
  #expect(navigator.contains("delegate: noteDropDelegate("))
  #expect(navigator.contains("dragSession.id == expectedSource.dragSessionID"))
  #expect(navigator.contains("Color.accentColor.opacity"))
  #expect(navigator.contains("noteDropTarget = nil"))
  #expect(navigator.contains("sourceFolderID"))
  #expect(navigator.contains("targetFolderID"))
  #expect(navigator.contains("validTargetFolderIDs: { Set(appState.workspace.folders.map"))
  #expect(navigator.contains("of: [FolderDragPayload.noteType]"))
  #expect(navigator.contains("type: FolderDragPayload.folderType"))
  #expect(!navigator.contains("of: [FolderDragPayload.noteType, FolderDragPayload.folderType]"))
}

@Test func tabStripKeepsManualOrderAndPinnedPartitionWithoutRecencySorting() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("visibleNotes.map(\\.id)"))
  #expect(tabStrip.contains("inFolderID: note.folderID"))
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
private func clickHostedPointer(atScreen point: NSPoint, in window: NSWindow) {
  let location = window.convertPoint(fromScreen: point)
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
private func hostedPointerElement(_ value: Any?, identifier: String) -> NSObject? {
  guard let element = value as? NSObject else { return nil }
  let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let value = element.responds(to: identifierSelector)
    ? element.perform(identifierSelector)?.takeUnretainedValue() as? String : nil
  if value == identifier { return element }
  let children = element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in children ?? [] {
    if let found = hostedPointerElement(child, identifier: identifier) { return found }
  }
  return nil
}

@MainActor
private func settleTabStripHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func advanceTabStripHostEventBoundary(_ view: NSView) async {
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    RunLoop.main.perform {
      MainActor.assumeIsolated {
        view.layoutSubtreeIfNeeded()
        continuation.resume()
      }
    }
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

@Test func reorderInteractionPreviewCancelsWithoutMutatingAndDropConsumesOnce() {
  let ids = [UUID(), UUID(), UUID()]
  var drag = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
  drag.propose(over: ids[2], after: true, currentIDs: ids)
  drag.propose(over: ids[2], after: true, currentIDs: ids)
  #expect(drag.destination == 2)
  let cancelled = drag
  drag.clearTarget()
  #expect(drag.consume(currentIDs: ids) == nil)
  drag = cancelled
  #expect(drag.consume(currentIDs: ids) == 2)
  #expect(drag.consume(currentIDs: ids) == nil)
}

@Test @MainActor func reorderInteractionRejectsChangedOrderMissingItemsAndPinBoundary() {
  let pinned = Note(title: "Pinned", isPinned: true)
  let first = Note(title: "First")
  let last = Note(title: "Last")
  let notes = [pinned, first, last]
  var drag = ReorderInteraction(sourceID: first.id, originalIDs: notes.map(\.id), pinnedIDs: [pinned.id])
  let source = NoteDropSource(noteID: first.id, sourceFolderID: nil, dragSessionID: drag.sessionID)
  let session = ReorderDropSession(source: source)
  drag.propose(over: pinned.id, after: false, currentIDs: notes.map(\.id))
  #expect(session.acceptReorder(from: [FolderDragPayload.noteProvider(source: source)],
    interaction: drag, currentIDs: { notes.map(\.id) }, currentPinnedIDs: { [pinned.id] },
    move: { _, _ in Issue.record("A note must not cross the pinned partition") }) == nil)
  drag.propose(over: last.id, after: true, currentIDs: notes.map(\.id))
  #expect(drag.consume(currentIDs: [pinned.id, last.id]) == nil)
  drag.propose(over: last.id, after: true, currentIDs: [pinned.id, last.id, first.id])
  #expect(drag.destination == nil)
}


@Test @MainActor
func reorderInteractionNativeLifetimeDoesNotEndBetweenPointerEvents() throws {
  // The real native drag trace reports zero global pressed buttons after onDrag.
  // A live source must survive the edge-scroll timer until its native end signal.
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 50),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  let view = ReorderDragLifecycle.DragView(frame: window.contentView!.bounds)
  var cancellations = 0
  view.cancel = { cancellations += 1 }
  window.contentView!.addSubview(view)
  defer { view.setActive(false); window.close() }
  #expect(NSEvent.pressedMouseButtons == 0)
  view.setActive(true)
  RunLoop.main.run(until: Date().addingTimeInterval(0.12))
  #expect(cancellations == 0)
}

@Test @MainActor func hostedNotesPanelTabOverflowNativeDestinationMeasuresRealUnequalSourcesAndBlankTail() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let notes = [Note(title: "One"), Note(title: "A substantially wider second title")]
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: notes, selectedNoteID: notes[0].id)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(rootView: NotesPanel(dictationRuntime: runtime, sizing: .container).environmentObject(state))
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleTabStripHost(host)
  func find(_ view: NSView) -> FluidTabDestinationView? {
    if let destination = view as? FluidTabDestinationView { return destination }
    return view.subviews.lazy.compactMap { find($0) }.first
  }
  let destination = try #require(find(host))
  let controller = try #require(destination.controller)
  let scroll = try #require(destination.enclosingScrollView)
  #expect(destination.bounds.width >= scroll.contentView.bounds.width - 1)
  let interaction = ReorderInteraction(sourceID: notes[0].id, originalIDs: notes.map(\.id))
  let session = ReorderDropSession(source: .init(noteID: notes[0].id, sourceFolderID: nil,
    dragSessionID: interaction.sessionID))
  controller.prepare(interaction: interaction, session: session, currentIDs: { notes.map(\.id) },
    currentPins: { [] }, move: { _, _ in Issue.record("Measuring a native row must not move notes") }, finish: {})
  controller.began(at: window.convertPoint(toScreen: destination.convert(NSPoint(x: 25, y: 15), to: nil)))
  let preview = try #require(controller.preview)
  let first = try #require(preview.frames[notes[0].id])
  let second = try #require(preview.frames[notes[1].id])
  #expect(first.width > 20)
  #expect(second.width > first.width + 50)
  #expect(abs(second.minX - first.maxX - 6) < 1)
  #expect(first.minX >= 0)
  #expect(destination.bounds.maxX - second.maxX > 30)
  func sourceView(_ view: NSView) -> ReorderSourceHostingView? {
    if let source = view as? ReorderSourceHostingView, source.noteID == notes[1].id { return source }
    return view.subviews.lazy.compactMap { sourceView($0) }.first
  }
  let sibling = try #require(sourceView(destination))
  var positions: [CGFloat] = []
  if let presentation = sibling.layer?.presentation(), let root = destination.layer?.presentation() {
    positions.append(presentation.convert(presentation.bounds, to: root).minX)
  }
  controller.moved(to: window.convertPoint(toScreen:
    destination.convert(NSPoint(x: second.maxX, y: 15), to: nil)))
  let deadline = ProcessInfo.processInfo.systemUptime + 1
  let intermediateRange = (first.minX + 1)..<(second.minX - 1)
  var observedAnimation = false
  var hasIntermediatePosition = false
  repeat {
    await advanceTabStripHostEventBoundary(host)
    observedAnimation = observedAnimation
      || sibling.layer?.animation(forKey: "fleck.tab-reorder") != nil
    if let presentation = sibling.layer?.presentation(), let root = destination.layer?.presentation() {
      positions.append(presentation.convert(presentation.bounds, to: root).minX)
    }
    hasIntermediatePosition = positions.contains { intermediateRange.contains($0) }
  } while ProcessInfo.processInfo.systemUptime < deadline
    && (!hasIntermediatePosition || sibling.layer?.animation(forKey: "fleck.tab-reorder") != nil)
  #expect(observedAnimation)
  #expect(hasIntermediatePosition)
  let finalPosition = try #require(positions.last)
  #expect(abs(finalPosition - first.minX) < 1)
  #expect(controller.preview?.frames[notes[1].id] == second)
  controller.cancel()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func hostedNotesPanelPointerHitMapsIncludeNoteAndFolderPaddedInteriors() async throws {
  NSApplication.shared.accessibilitySetValue(
    true,
    forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  )
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("pointer-hit-maps-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let firstFolder = try Folder(name: "First folder")
  let secondFolder = try Folder(name: "Second folder")
  let firstNote = Note(title: "First note", folderID: firstFolder.id)
  let selectedNote = Note(title: "Selected note", folderID: firstFolder.id)
  let secondFolderNote = Note(title: "Second folder note", folderID: secondFolder.id)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [firstNote, selectedNote, secondFolderNote],
    selectedNoteID: selectedNote.id,
    folders: [firstFolder, secondFolder]
  )
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(
    rootView: NotesPanel(dictationRuntime: runtime, sizing: .container)
      .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 430),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleTabStripHost(host)

  func findDestination(_ view: NSView) -> FluidTabDestinationView? {
    if let destination = view as? FluidTabDestinationView { return destination }
    return view.subviews.lazy.compactMap { findDestination($0) }.first
  }
  let destination = try #require(findDestination(host))
  let noteSourceFrames = destination.sourceFrames()
  #expect(noteSourceFrames[firstNote.id]?.width ?? 0 > 20)
  #expect(noteSourceFrames[selectedNote.id]?.width ?? 0 > 20)

  func click(identifier: String, x: (NSRect) -> CGFloat) async throws {
    let element = try #require(hostedPointerElement(host, identifier: identifier))
    let frame = try #require(element.value(forKey: "accessibilityFrame") as? NSValue).rectValue
    clickHostedPointer(
      atScreen: NSPoint(x: x(frame), y: frame.midY), in: window
    )
    await settleTabStripHost(host)
  }
  func clickNote(_ noteID: UUID, x: (NSRect) -> CGFloat) async throws {
    let frame = try #require(noteSourceFrames[noteID])
    let screenFrame = window.convertToScreen(destination.convert(frame, to: nil))
    clickHostedPointer(
      atScreen: NSPoint(x: x(screenFrame), y: screenFrame.midY), in: window
    )
    await settleTabStripHost(host)
  }

  try await clickNote(firstNote.id, x: { $0.midX })
  #expect(state.workspace.selectedNoteID == firstNote.id)
  try await clickNote(selectedNote.id, x: { $0.minX + 2 })
  #expect(state.workspace.selectedNoteID == selectedNote.id)
  try await clickNote(selectedNote.id, x: { $0.midX })
  #expect(state.workspace.selectedNoteID == selectedNote.id)
  try await clickNote(firstNote.id, x: { $0.maxX - 2 })
  #expect(state.workspace.selectedNoteID == firstNote.id)

  let secondFolderID = "folder-\(secondFolder.id.uuidString)"
  let firstFolderID = "folder-\(firstFolder.id.uuidString)"
  try await click(identifier: secondFolderID, x: { $0.midX })
  #expect(state.workspace.selectedNoteID == secondFolderNote.id)
  try await click(identifier: firstFolderID, x: { $0.minX + 2 })
  #expect(state.workspace.selectedNoteID == firstNote.id)
  try await click(identifier: secondFolderID, x: { $0.maxX - 2 })
  #expect(state.workspace.selectedNoteID == secondFolderNote.id)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func nativeTabDragImageFillsBothHalvesAtRetinaScale() throws {
  let captured = try #require(NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 200,
    pixelsHigh: 74,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ))
  captured.size = NSSize(width: 100, height: 37)
  let image = try #require(ReorderSourceHostingView.compositedDraggingImage(
    captured: captured,
    size: captured.size,
    appearance: NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()
  ))
  let representation = try #require(image.representations.first as? NSBitmapImageRep)

  #expect(representation.pixelsWide == 200)
  #expect(representation.pixelsHigh == 74)
  #expect(image.size == NSSize(width: 100, height: 37))
  for point in [(25, 18), (175, 18), (25, 55), (175, 55)] {
    #expect((representation.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 0) > 0.99)
  }
}

@Test @MainActor
func nativeTabDragPreviewFollowsPointerAndClosesOnEveryFinishPath() throws {
  let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 300, height: 120),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
  let sourceView = NSView(frame: NSRect(x: 30, y: 40, width: 100, height: 37))
  root.addSubview(sourceView)
  window.contentView = root
  window.makeKeyAndOrderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
    window.close()
  }
  let image = NSImage(size: sourceView.bounds.size)
  let initialFrame = window.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
  let grabPoint = NSPoint(x: 23, y: 11)
  let grabPointOnScreen = window.convertPoint(toScreen: sourceView.convert(grabPoint, to: nil))
  let beginPoint = NSPoint(x: grabPointOnScreen.x + 8, y: grabPointOnScreen.y + 4)
  let movedPoint = NSPoint(x: grabPointOnScreen.x + 80, y: grabPointOnScreen.y - 25)
  let preview = try #require(ReorderNativePreview(
    image: image, sourceView: sourceView, grabPoint: grabPoint
  ))
  var operations: [NSDragOperation] = []
  let nativeSource = ReorderNativeSource(
    id: UUID(), source: nil, began: nil, preview: preview,
    end: { operations.append($0) }
  )
  let session = NativePreviewDraggingSessionProbe()

  #expect(preview.panel.ignoresMouseEvents)
  #expect(preview.panel.styleMask.contains(.nonactivatingPanel))
  #expect(!preview.panel.isOpaque)
  #expect(preview.panel.level.rawValue == window.level.rawValue + 1)
  #expect(!preview.panel.isVisible)
  nativeSource.draggingSession(session, willBeginAt: beginPoint)
  let visibleWindowNumber = preview.panel.windowNumber
  #expect(preview.panel.isVisible)
  #expect(!preview.panel.isKeyWindow)
  #expect(preview.panel.frame.origin == NSPoint(
    x: initialFrame.minX + 8, y: initialFrame.minY + 4
  ))
  nativeSource.draggingSession(session, willBeginAt: beginPoint)
  #expect(preview.panel.windowNumber == visibleWindowNumber)
  nativeSource.draggingSession(session, movedTo: movedPoint)
  #expect(preview.panel.frame.origin == NSPoint(
    x: initialFrame.minX + 80, y: initialFrame.minY - 25
  ))
  nativeSource.draggingSession(session, endedAt: movedPoint, operation: .move)
  #expect(!preview.panel.isVisible)
  #expect(operations == [.move])

  let abortedPreview = try #require(ReorderNativePreview(
    image: image, sourceView: sourceView, grabPoint: grabPoint
  ))
  let abortedSource = ReorderNativeSource(
    id: UUID(), source: nil, began: nil, preview: abortedPreview,
    end: { operations.append($0) }
  )
  abortedSource.draggingSession(session, willBeginAt: beginPoint)
  #expect(abortedPreview.panel.isVisible)
  abortedSource.end([])
  #expect(!abortedPreview.panel.isVisible)
  #expect(operations == [.move, []])

  let invalidatedPreview = try #require(ReorderNativePreview(
    image: image, sourceView: sourceView, grabPoint: grabPoint
  ))
  let invalidatedSource = ReorderNativeSource(
    id: UUID(), source: nil, began: nil, preview: invalidatedPreview,
    end: { operations.append($0) }
  )
  invalidatedSource.draggingSession(session, willBeginAt: beginPoint)
  #expect(invalidatedPreview.panel.isVisible)
  invalidatedSource.closePreview()
  #expect(!invalidatedPreview.panel.isVisible)
  #expect(operations == [.move, []])
}

@Test @MainActor
func hostedUnselectedTabBuildsVisibleDragItemBeforeNativeWillBegin() async throws {
  func visiblePixels(in image: NSImage) -> Int {
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data)
    else { return 0 }
    return (0..<bitmap.pixelsHigh).reduce(0) { count, y in
      count + (0..<bitmap.pixelsWide).filter {
        bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0 > 0.01
      }.count
    }
  }
  func opaqueInteriorFraction(in image: NSImage) -> Double {
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
      bitmap.pixelsWide > 8, bitmap.pixelsHigh > 8
    else { return 0 }
    let scale = max(1, CGFloat(bitmap.pixelsHigh) / image.size.height)
    let horizontalInset = max(2, Int((4 * scale).rounded(.up)))
    let bandHalfHeight = max(1, Int((3 * scale).rounded(.up)))
    let xs = horizontalInset..<(bitmap.pixelsWide - horizontalInset)
    let ys = (bitmap.pixelsHigh / 2 - bandHalfHeight)..<(bitmap.pixelsHigh / 2 + bandHalfHeight)
    let pixelCount = xs.count * ys.count
    let opaqueCount = ys.reduce(0) { count, y in
      count + xs.filter { x in
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.99
      }.count
    }
    return Double(opaqueCount) / Double(pixelCount)
  }
  func readableForegroundFraction(in image: NSImage, darkAppearance: Bool) -> Double {
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
      bitmap.pixelsWide > 8, bitmap.pixelsHigh > 8
    else { return 0 }
    let scale = max(1, CGFloat(bitmap.pixelsHigh) / image.size.height)
    let leadingInset = max(2, Int((20 * scale).rounded(.up)))
    let trailingInset = max(2, Int((4 * scale).rounded(.up)))
    let verticalInset = max(2, Int((4 * scale).rounded(.up)))
    let xs = leadingInset..<(bitmap.pixelsWide - trailingInset)
    let ys = verticalInset..<(bitmap.pixelsHigh - verticalInset)
    let pixelCount = xs.count * ys.count
    let foregroundCount = ys.reduce(0) { count, y in
      count + xs.filter { x in
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
          color.alphaComponent > 0.99
        else { return false }
        let luminance = 0.2126 * color.redComponent
          + 0.7152 * color.greenComponent
          + 0.0722 * color.blueComponent
        return darkAppearance ? luminance > 0.55 : luminance < 0.45
      }.count
    }
    return Double(foregroundCount) / Double(pixelCount)
  }
  func renderedImage(of view: NSView) throws -> NSImage {
    let bounds = view.bounds
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: bounds))
    view.cacheDisplay(in: bounds, to: bitmap)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(bitmap)
    return image
  }
  func findDestination(_ view: NSView) -> FluidTabDestinationView? {
    if let destination = view as? FluidTabDestinationView { return destination }
    return view.subviews.lazy.compactMap { findDestination($0) }.first
  }
  func findSource(_ noteID: UUID, in view: NSView) -> ReorderSourceHostingView? {
    if let source = view as? ReorderSourceHostingView, source.noteID == noteID { return source }
    return view.subviews.lazy.compactMap { findSource(noteID, in: $0) }.first
  }

  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("visible-tab-preview-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let dragged = Note(title: "Preview")
  let selected = Note(title: "Preview")
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [dragged, selected], selectedNoteID: selected.id)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(
    rootView: NotesPanel(dictationRuntime: runtime, sizing: .container).environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 430),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleTabStripHost(host)
  defer {
    window.contentView = nil
    window.orderOut(nil)
    window.close()
  }

  var endOperations: [NSDragOperation] = []
  var completedCaptures = 0
  var previewDataByAppearance: [String: [Bool: Data]] = [:]
  let captureCases: [(appearance: NSAppearance.Name, ambient: NSAppearance.Name,
    dark: Bool, noteID: UUID, selected: Bool)] = [
      (.vibrantDark, .aqua, true, dragged.id, false),
      (.vibrantDark, .aqua, true, selected.id, true),
      (.vibrantLight, .darkAqua, false, dragged.id, false),
      (.vibrantLight, .darkAqua, false, selected.id, true),
    ]
  for captureCase in captureCases {
    window.appearance = NSAppearance(named: captureCase.appearance)
    await settleTabStripHost(host)
    let destination = try #require(findDestination(host))
    let source = try #require(findSource(captureCase.noteID, in: destination))
    let renderedSource = try renderedImage(of: source)
    #expect(visiblePixels(in: renderedSource) > 0)
    let originalBegin = try #require(source.onNativeBegin)
    source.onNativeBegin = {
      let (provider, pasteboardWriter, end) = originalBegin()
      return (provider, pasteboardWriter, { operation in
        endOperations.append(operation)
        end(operation)
      })
    }
    var draggingItems: [NSDraggingItem] = []
    var capturedSource: ReorderNativeSource?
    var capturedEvent: NSEvent?
    source.interceptNativeDrag = { items, nativeSource, event in
      draggingItems = items
      capturedSource = nativeSource
      capturedEvent = event
      return true
    }
    let sourceFrame = destination.convert(source.bounds, from: source)
    let start = destination.convert(
      NSPoint(x: sourceFrame.midX, y: sourceFrame.midY), to: nil
    )
    let ambientAppearance = try #require(NSAppearance(named: captureCase.ambient))
    ambientAppearance.performAsCurrentDrawingAppearance {
      for (sequence, event) in [
        NSEvent.EventType.leftMouseDown,
        NSEvent.EventType.leftMouseDragged,
      ].enumerated() {
        let point = event == .leftMouseDragged ? NSPoint(x: start.x + 8, y: start.y) : start
        let mouseEvent = NSEvent.mouseEvent(
          with: event,
          location: point,
          modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime + Double(sequence) * 0.01,
          windowNumber: window.windowNumber,
          context: nil,
          eventNumber: sequence,
          clickCount: 1,
          pressure: 1
        )
        if let mouseEvent { window.sendEvent(mouseEvent) }
      }
    }
    await settleTabStripHost(host)

    let item = try #require(draggingItems.first)
    let preview = try #require(capturedSource?.preview)
    let previewImage = preview.image
    #expect(previewImage.size == source.bounds.size)
    #expect(previewImage.representations.first?.pixelsWide == renderedSource.representations.first?.pixelsWide)
    #expect(previewImage.representations.first?.pixelsHigh == renderedSource.representations.first?.pixelsHigh)
    #expect(item.draggingFrame == source.bounds)
    #expect(item.imageComponents?.contains(where: { $0.contents != nil }) != true)
    #expect(!preview.panel.isVisible)
    #expect(capturedEvent?.locationInWindow == start)
    #expect(visiblePixels(in: previewImage) > 0)
    #expect(opaqueInteriorFraction(in: previewImage) > 0.98)
    #expect(readableForegroundFraction(in: previewImage, darkAppearance: captureCase.dark) > 0.01,
      "appearance=\(captureCase.appearance.rawValue) selected=\(captureCase.selected)")
    #expect(capturedSource?.began != nil)
    #expect(capturedSource?.moved != nil)
    completedCaptures += 1
    #expect(endOperations.count == completedCaptures)
    #expect(destination.controller?.inside == false)
    #expect(destination.controller?.preview == nil)
    #expect(source.layer?.opacity == 1)
    #expect(state.workspace.selectedNoteID == selected.id)
    let data = try #require(previewImage.tiffRepresentation)
    previewDataByAppearance[captureCase.appearance.rawValue, default: [:]][captureCase.selected] = data
  }
  for images in previewDataByAppearance.values {
    #expect(images[false] != images[true])
  }
  #expect(endOperations.count == captureCases.count)

  findDestination(host)?.controller?.cancel()
  await runtime.shutdown()
}
