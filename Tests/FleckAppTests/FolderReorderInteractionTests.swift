import AppKit
import Combine
import Foundation
import Testing
import SwiftUI
@testable import FleckApp
import FleckCore

@MainActor
private final class DraggingInfoProbe: NSObject, NSDraggingInfo {
  let draggingDestinationWindow: NSWindow?
  let draggingSourceOperationMask: NSDragOperation = .move
  var draggingLocation: NSPoint
  let draggedImageLocation: NSPoint = .zero
  let draggedImage: NSImage? = nil
  let draggingPasteboard: NSPasteboard
  let draggingSource: Any? = NSObject()
  let draggingSequenceNumber = 1
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = true
  var numberOfValidItemsForDrop = 1
  let springLoadingHighlight: NSSpringLoadingHighlight = .none

  init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard) {
    draggingDestinationWindow = window
    draggingLocation = location
    draggingPasteboard = pasteboard
  }

  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func enumerateDraggingItems(
    options enumOpts: NSDraggingItemEnumerationOptions,
    for view: NSView?,
    classes classArray: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}
  func resetSpringLoading() {}
}

@Test @MainActor
func reorderInteractionFoldersRequireExactLocalSourceSessionAndDistinctPayload() async throws {
  let ids = [UUID(), UUID(), UUID()]
  var interaction = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
  let expected = FolderDragPayload.FolderValue(folderID: ids[0], sessionID: interaction.sessionID)
  let values = [expected, .init(folderID: ids[0], sessionID: UUID()),
    .init(folderID: ids[1], sessionID: interaction.sessionID)]
  for value in values {
    let session = ReorderDropSession(folder: expected)
    var commits = 0
    let provider = reconstructedReorderProvider(data: try JSONEncoder().encode(value),
      typeIdentifier: FolderDragPayload.folderType.identifier)
    let load = try #require(session.acceptDrop(from: [provider]) { commits += 1 })
    session.end(operation: .move)
    await load.value
    #expect(commits == (value == expected ? 1 : 0))
  }
  let session = ReorderDropSession(folder: expected)
  #expect(session.acceptDrop(from: [FolderDragPayload.noteProvider(source:
    NoteDropSource(noteID: ids[0], sourceFolderID: nil))], commit: {}) == nil)
  #expect(session.acceptDrop(from: [NSItemProvider()], commit: {}) == nil)
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

@Test func reorderInteractionLocalPayloadTypesDeclareNativeDataConformance() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let data = try Data(contentsOf: root.appendingPathComponent("Sources/FleckApp/Info.plist"))
  let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  let declarations = plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
  // AppKit registers SwiftUI drop destinations for public.data/public.item.
  // Own-process payloads still need declared conformance to reach validateDrop.
  for identifier in [FolderDragPayload.noteType.identifier, FolderDragPayload.folderType.identifier] {
    let declaration = declarations.first { $0["UTTypeIdentifier"] as? String == identifier }
    #expect((declaration?["UTTypeConformsTo"] as? [String])?.contains("public.data") == true)
  }
}

@Test @MainActor func reorderInteractionGenericProviderCarriesAuthenticatedNotePayload() async throws {
  let source = NoteDropSource(noteID: UUID(), sourceFolderID: UUID())
  let encoded = try JSONEncoder().encode(source)
  let reconstructed = NSItemProvider()
  reconstructed.registerDataRepresentation(forTypeIdentifier: FolderDragPayload.noteType.identifier,
    visibility: .ownProcess) { completion in
      completion(encoded, nil)
      return nil
    }
  let data: Data? = await withCheckedContinuation { continuation in
    reconstructed.loadDataRepresentation(forTypeIdentifier: FolderDragPayload.noteType.identifier) {
      data, _ in continuation.resume(returning: data)
    }
  }
  #expect(FolderDragPayload.noteValue(from: try #require(data)) == source)
  for nativeEndFirst in [false, true] {
    let session = ReorderDropSession(source: source)
    var commits = 0
    let load = try #require(session.acceptDrop(from: [reconstructed]) { commits += 1 })
    if nativeEndFirst { session.end(operation: .move) }
    await load.value
    if !nativeEndFirst {
      #expect(commits == 0)
      session.end(operation: .move)
    }
    #expect(commits == 1)
    session.end(operation: .move)
    #expect(session.acceptDrop(from: [reconstructed], commit: { commits += 1 }) == nil)
    #expect(commits == 1)
  }
}


private func reconstructedReorderProvider(data: Data, typeIdentifier: String) -> NSItemProvider {
  let provider = NSItemProvider()
  provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) {
    completion in
    completion(data, nil)
    return nil
  }
  return provider
}

@Test @MainActor
func reorderInteractionPendingDropRejectsCancelledAndReplacedSessions() async throws {
  let source = NoteDropSource(noteID: UUID(), sourceFolderID: nil)
  let provider = reconstructedReorderProvider(data: try JSONEncoder().encode(source),
    typeIdentifier: FolderDragPayload.noteType.identifier)
  for end in [NSDragOperation(), .copy] {
    for authenticateFirst in [false, true] {
      let session = ReorderDropSession(source: source)
      var commits = 0
      let load = try #require(session.acceptDrop(from: [provider]) { commits += 1 })
      if authenticateFirst { await load.value }
      session.end(operation: end)
      await load.value
      session.end(operation: .move)
      #expect(commits == 0)
    }
  }
  // The latest session survives presentation cleanup so a later drag can cancel it.
  var latest = ReorderDropSession(source: source)
  var commits = 0
  let old = latest
  let load = try #require(old.acceptDrop(from: [provider]) { commits += 1 })
  old.end(operation: .move)
  latest.cancel()
  latest = ReorderDropSession(source: NoteDropSource(noteID: source.noteID, sourceFolderID: nil))
  await load.value
  #expect(commits == 0)
  #expect(latest.canAcceptDrop)
  let pending = ReorderDropSession(source: source)
  let decoded = try #require(pending.acceptDrop(from: [provider]) { commits += 1 })
  await decoded.value
  pending.cancel()
  pending.end(operation: .move)
  #expect(commits == 0)
}

@Test @MainActor
func reorderInteractionGenericPayloadRejectsMismatchAndReplay() async throws {
  let source = NoteDropSource(noteID: UUID(), sourceFolderID: UUID())
  let mismatches = [
    NoteDropSource(noteID: source.noteID, sourceFolderID: source.sourceFolderID),
    NoteDropSource(noteID: UUID(), sourceFolderID: source.sourceFolderID, dragSessionID: source.dragSessionID),
    NoteDropSource(noteID: source.noteID, sourceFolderID: nil, dragSessionID: source.dragSessionID)
  ]
  for data in try mismatches.map({ try JSONEncoder().encode($0) }) + [Data("{}".utf8)] {
    let session = ReorderDropSession(source: source)
    var commits = 0
    let load = try #require(session.acceptDrop(from: [reconstructedReorderProvider(data: data,
      typeIdentifier: FolderDragPayload.noteType.identifier)]) { commits += 1 })
    session.end(operation: .move)
    await load.value
    #expect(commits == 0)
  }
}

@Test @MainActor
func reorderInteractionDeferredReorderRevalidatesOrderMembershipAndPins() async throws {
  let ids = [UUID(), UUID(), UUID()]
  for change in 0..<5 {
    var currentIDs = ids
    var currentPins: Set<UUID> = []
    var interaction = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
    interaction.propose(over: ids[2], after: true, currentIDs: ids)
    let source = NoteDropSource(noteID: ids[0], sourceFolderID: nil, dragSessionID: interaction.sessionID)
    let session = ReorderDropSession(source: source)
    var commits = 0
    let provider = reconstructedReorderProvider(data: try JSONEncoder().encode(source),
      typeIdentifier: FolderDragPayload.noteType.identifier)
    let load = try #require(session.acceptReorder(from: [provider], interaction: interaction,
      currentIDs: { currentIDs }, currentPinnedIDs: { currentPins }) { sourceID, destination in
        #expect(sourceID == ids[0])
        #expect(destination == 2)
        commits += 1
      })
    await load.value
    #expect(commits == 0)
    switch change {
    case 1: currentIDs.swapAt(1, 2)
    case 2: currentIDs.removeLast()
    case 3: currentIDs.removeFirst()
    case 4: currentPins.insert(ids[0]) // Order can stay identical when the first tab becomes pinned.
    default: break
    }
    session.end(operation: .move)
    session.end(operation: .move)
    #expect(commits == (change == 0 ? 1 : 0))
  }
}

@Test @MainActor
func reorderInteractionDeferredFolderTransferRevalidatesAndPreservesSelection() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = try Folder(name: "Destination")
  let dragged = Note(title: "Drag")
  let selected = Note(title: "Keep selected")
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  for change in 0..<4 {
    state.workspace = Workspace(notes: [dragged, selected], selectedNoteID: selected.id, folders: [folder])
    let source = NoteDropSource(noteID: dragged.id, sourceFolderID: nil)
    let session = ReorderDropSession(source: source)
    let provider = reconstructedReorderProvider(data: try JSONEncoder().encode(source),
      typeIdentifier: FolderDragPayload.noteType.identifier)
    var commits = 0
    let load = try #require(session.acceptNoteTransfer(from: [provider], source: source,
      targetFolderID: folder.id, currentSourceNotes: { state.visibleNotes(in: nil) },
      validTargetFolderIDs: { Set(state.workspace.folders.map(\.id)) }) { source, target in
        commits += 1
        return state.moveNote(source.noteID, fromFolderID: source.sourceFolderID,
          toFolderID: target, activeFolderID: nil)
      })
    await load.value
    #expect(commits == 0)
    switch change {
    case 1: state.workspace.notes[0].folderID = folder.id
    case 2: state.workspace.folders = []
    case 3: state.workspace.notes[0].isPinned = true
    default: break
    }
    session.end(operation: .move)
    #expect(commits == (change == 0 ? 1 : 0))
    #expect(state.workspace.selectedNoteID == selected.id)
    if change == 0 { #expect(state.workspace.notes.first(where: { $0.id == dragged.id })?.folderID == folder.id) }
  }
}

@Test @MainActor func reorderInteractionNativeSourceOnlyAllowsLocalMoves() {
  #expect(ReorderNativeSource.operationMask(for: .withinApplication) == .move)
  #expect(ReorderNativeSource.operationMask(for: .outsideApplication).isEmpty)
}

@Test func reorderInteractionFluidUnequalWidthsDisplaceFullSourceGapAndReverse() throws {
  let ids = [UUID(), UUID(), UUID()]
  let frames = [ids[0]: CGRect(x: 0, y: 0, width: 60, height: 30),
    ids[1]: CGRect(x: 66, y: 0, width: 120, height: 30),
    ids[2]: CGRect(x: 192, y: 0, width: 80, height: 30)]
  var drag = try #require(FluidTabReorder(interaction: ReorderInteraction(sourceID: ids[0], originalIDs: ids),
    frames: frames, pointerX: 15))
  drag.update(pointerX: 230)
  #expect(drag.destination == 2)
  #expect(drag.offset(for: ids[1]) == -66)
  #expect(drag.offset(for: ids[2]) == -66)
  #expect(drag.slotFrame == CGRect(x: 212, y: 0, width: 60, height: 30))
  for _ in 0..<20 { drag.update(pointerX: 230); #expect(drag.destination == 2) }
  drag.update(pointerX: 15)
  #expect(drag.destination == 0)
  #expect(ids.allSatisfy { drag.offset(for: $0) == 0 })
  var reverse = try #require(FluidTabReorder(interaction: ReorderInteraction(sourceID: ids[2], originalIDs: ids),
    frames: frames, pointerX: 210))
  reverse.update(pointerX: 18)
  #expect(reverse.destination == 0)
  #expect(reverse.offset(for: ids[0]) == 86)
  #expect(reverse.offset(for: ids[1]) == 86)
}

@Test func reorderInteractionFluidPinsGeometryInvalidationAndNoHoverMutation() throws {
  let ids = [UUID(), UUID(), UUID()]
  let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map {
    ($0.element, CGRect(x: $0.offset * 66, y: 0, width: 60, height: 30))
  })
  let original = ReorderInteraction(sourceID: ids[1], originalIDs: ids, pinnedIDs: [ids[0]])
  var drag = try #require(FluidTabReorder(interaction: original, frames: frames, pointerX: 80))
  drag.update(pointerX: -100)
  #expect(drag.destination == 1)
  #expect(drag.interaction.originalIDs == ids)
  #expect(drag.isValid(ids: ids, pins: [ids[0]], frames: frames))
  #expect(!drag.isValid(ids: ids.reversed(), pins: [ids[0]], frames: frames))
  #expect(!drag.isValid(ids: ids, pins: [], frames: frames))
  var resized = frames
  resized[ids[1]]?.size.width = 100
  #expect(!drag.isValid(ids: ids, pins: [ids[0]], frames: resized))
}

@Test func reorderInteractionFluidOverflowRecomputesFromLiveScrollAndStopsOutside() throws {
  #expect(FluidTabReorder.scrollDelta(pointerX: 99, viewport: 0...100) > 0)
  #expect(FluidTabReorder.scrollDelta(pointerX: 1, viewport: 0...100) < 0)
  #expect(FluidTabReorder.scrollDelta(pointerX: 50, viewport: 0...100) == 0)
  #expect(FluidTabReorder.scrollDelta(pointerX: 101, viewport: 0...100) == 0)
  let ids = [UUID(), UUID(), UUID()]
  let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map {
    ($0.element, CGRect(x: $0.offset * 106, y: 0, width: 100, height: 30))
  })
  var drag = try #require(FluidTabReorder(interaction: ReorderInteraction(sourceID: ids[0], originalIDs: ids),
    frames: frames, pointerX: 20))
  drag.update(pointerX: 90)
  let before = drag.destination
  drag.update(pointerX: 90 + 150)
  #expect(drag.destination > before)
}

@Test @MainActor func reorderInteractionFluidControllerHoverCancelAndOverflowDoNotSave() async throws {
  let notes = ["One", "Two", "Three"].map { Note(title: $0) }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: notes, selectedNoteID: notes[1].id)
  let original = state.workspace
  let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 180, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 40))
  let view = FluidTabDestinationView(rootView: AnyView(Color.clear.frame(width: 400, height: 37)))
  view.frame = NSRect(x: 0, y: 0, width: 400, height: 37)
  scroll.documentView = view
  window.contentView = scroll
  let controller = FluidTabDragController()
  controller.view = view
  var sourceViews: [ReorderSourceHostingView] = []
  for (index, note) in notes.enumerated() {
    let source = ReorderSourceHostingView(rootView: AnyView(Color.clear.frame(width: 100, height: 30)))
    source.noteID = note.id
    source.frame = NSRect(x: index * 106, y: 0, width: 100, height: 30)
    view.addSubview(source)
    sourceViews.append(source)
  }
  let interaction = ReorderInteraction(sourceID: notes[0].id, originalIDs: notes.map(\.id))
  let session = ReorderDropSession(source: .init(noteID: notes[0].id, sourceFolderID: nil,
    dragSessionID: interaction.sessionID))
  var moves = 0
  func screen(_ x: CGFloat) -> NSPoint {
    window.convertPoint(toScreen: view.convert(NSPoint(x: x, y: 15), to: nil))
  }
  controller.prepare(interaction: interaction, session: session,
    currentIDs: { state.visibleNotes(in: nil).map(\.id) }, currentPins: { [] },
    move: { _, _ in moves += 1 }, finish: {})
  controller.began(at: screen(20))
  #expect(sourceViews[0].layer?.opacity == 0)
  controller.moved(to: screen(175))
  let before = scroll.contentView.bounds.minX
  for _ in 0..<20 { controller.tick() }
  #expect(scroll.contentView.bounds.minX > before)
  #expect(controller.preview?.destination == 2)
  #expect(moves == 0)
  #expect(state.workspace == original)
  controller.exited()
  #expect(sourceViews[0].layer?.opacity == 1)
  let stopped = scroll.contentView.bounds.origin
  controller.tick()
  #expect(scroll.contentView.bounds.origin == stopped)
  controller.moved(to: window.convertPoint(toScreen: NSPoint(x: 90, y: 15)))
  #expect(sourceViews[0].layer?.opacity == 0)
  controller.cancel()
  #expect(sourceViews[0].layer?.opacity == 1)
  #expect(controller.preview == nil)
  #expect(!session.canAcceptDrop)
  controller.tick()
  #expect(scroll.contentView.bounds.origin == stopped)
  #expect(moves == 0)
  #expect(state.workspace == original)
}

@Test @MainActor
func reorderInteractionFluidControllerDoesNotRepublishAnUnchangedSlot() throws {
  let ids = [UUID(), UUID(), UUID()]
  var liveIDs = ids
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  let scroll = NSScrollView(frame: window.contentView!.bounds)
  let destination = FluidTabDestinationView(
    rootView: AnyView(Color.clear.frame(width: 400, height: 37))
  )
  destination.frame = NSRect(x: 0, y: 0, width: 400, height: 37)
  scroll.documentView = destination
  window.contentView = scroll
  window.makeKeyAndOrderFront(nil)
  defer { window.contentView = nil; window.orderOut(nil); window.close() }
  for (index, id) in ids.enumerated() {
    let source = ReorderSourceHostingView(
      rootView: AnyView(Color.clear.frame(width: 100, height: 30))
    )
    source.noteID = id
    source.frame = NSRect(x: index * 106, y: 0, width: 100, height: 30)
    destination.addSubview(source)
  }
  let interaction = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
  let session = ReorderDropSession(source: .init(
    noteID: ids[0], sourceFolderID: nil, dragSessionID: interaction.sessionID
  ))
  let controller = FluidTabDragController()
  controller.view = destination
  controller.prepare(
    interaction: interaction,
    session: session,
    currentIDs: { liveIDs },
    currentPins: { [] },
    move: { _, _ in Issue.record("Pointer movement must not commit a reorder") },
    finish: {}
  )
  let point = window.convertPoint(toScreen: destination.convert(NSPoint(x: 20, y: 15), to: nil))
  controller.began(at: point)
  controller.moved(to: point) // Establish the first native proposal.
  var publicationCount = 0
  let observation = controller.objectWillChange.sink { publicationCount += 1 }
  for _ in 0..<40 { controller.moved(to: point) }

  #expect(publicationCount == 0)
  #expect(controller.preview?.destination == 0)
  #expect(controller.inside)
  withExtendedLifetime(observation) {}

  liveIDs.removeLast()
  controller.moved(to: point)
  #expect(controller.preview == nil)
  #expect(!session.canAcceptDrop)
}

@Test @MainActor
func reorderDestinationDisablesNativeDropAnimation() throws {
  let ids = [UUID(), UUID()]
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  let scroll = NSScrollView(frame: window.contentView!.bounds)
  let destination = FluidTabDestinationView(
    rootView: AnyView(Color.clear.frame(width: 220, height: 37))
  )
  destination.frame = NSRect(x: 0, y: 0, width: 220, height: 37)
  scroll.documentView = destination
  window.contentView = scroll
  window.makeKeyAndOrderFront(nil)
  defer { window.contentView = nil; window.orderOut(nil); window.close() }
  for (index, id) in ids.enumerated() {
    let source = ReorderSourceHostingView(
      rootView: AnyView(Color.clear.frame(width: 100, height: 30))
    )
    source.noteID = id
    source.frame = NSRect(x: index * 106, y: 0, width: 100, height: 30)
    destination.addSubview(source)
  }
  let interaction = ReorderInteraction(
    sourceID: ids[0], originalIDs: ids
  )
  let source = NoteDropSource(
    noteID: ids[0], sourceFolderID: nil, dragSessionID: interaction.sessionID
  )
  let session = ReorderDropSession(source: source)
  let controller = FluidTabDragController()
  controller.view = destination
  destination.controller = controller
  controller.prepare(
    interaction: interaction,
    session: session,
    currentIDs: { ids },
    currentPins: { [] },
    move: { _, _ in },
    finish: {}
  )
  func screen(_ x: CGFloat) -> NSPoint {
    window.convertPoint(toScreen: destination.convert(NSPoint(x: x, y: 15), to: nil))
  }
  controller.began(at: screen(20))
  let pasteboard = NSPasteboard(name: .init("drop-animation-" + UUID().uuidString))
  pasteboard.declareTypes([.init(FolderDragPayload.noteType.identifier)], owner: nil)
  pasteboard.setData(
    try JSONEncoder().encode(source),
    forType: .init(FolderDragPayload.noteType.identifier)
  )
  let probe = DraggingInfoProbe(
    window: window,
    location: destination.convert(NSPoint(x: 120, y: 15), to: nil),
    pasteboard: pasteboard
  )

  #expect(destination.prepareForDragOperation(probe))
  #expect(probe.animatesToDestination == false)
  controller.cancel()
}

@Test @MainActor func reorderInteractionNativeLayerReversalUsesPresentationAndMotionCanBeDisabled() async throws {
  let source = ReorderSourceHostingView(rootView: AnyView(Color.clear.frame(width: 120, height: 30)))
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = source
  window.makeKeyAndOrderFront(nil)
  defer { window.contentView = nil; window.orderOut(nil); window.close() }
  source.setReorderDisplacement(0, animated: false)
  try await Task.sleep(nanoseconds: 30_000_000)
  source.setReorderDisplacement(-80, animated: true)
  try await Task.sleep(nanoseconds: 50_000_000)
  let layer = try #require(source.layer)
  let beforeReversal = try #require(layer.presentation()).transform.m41
  #expect(beforeReversal < -1 && beforeReversal > -79)
  source.setReorderDisplacement(0, animated: true)
  let animation = try #require((layer.animationKeys() ?? []).compactMap {
    layer.animation(forKey: $0) as? CABasicAnimation
  }.first { $0.keyPath == "transform.translation.x" })
  let resumedFrom = try #require(animation.fromValue as? NSNumber).doubleValue
  #expect(abs(resumedFrom - beforeReversal) < 2)
  #expect(layer.transform.m41 == 0)
  // Reduce Motion and accepted-order rebasing both use the immediate path.
  source.setReorderDisplacement(-80, animated: false)
  #expect(layer.animationKeys()?.isEmpty != false)
  #expect(layer.transform.m41 == -80)
  source.setReorderDisplacement(0, animated: false)
  #expect(layer.animationKeys()?.isEmpty != false)
  #expect(layer.transform.m41 == 0)
}
