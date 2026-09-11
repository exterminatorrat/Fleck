import AppKit
import Combine
import Foundation
import ObjectiveC.runtime
import Testing
import SwiftUI
@testable import FleckApp
import FleckCore

@Test @MainActor
func reorderNoteSourceOwnsNativePointerEvents() throws {
  for selector in [
    #selector(NSResponder.mouseDown(with:)),
    #selector(NSResponder.mouseDragged(with:)),
    #selector(NSResponder.mouseUp(with:)),
  ] {
    let sourceMethod = try #require(class_getInstanceMethod(ReorderSourceHostingView.self, selector))
    let inheritedMethod = try #require(class_getInstanceMethod(NSHostingView<AnyView>.self, selector))
    #expect(method_getImplementation(sourceMethod) != method_getImplementation(inheritedMethod))
  }
}

@Test @MainActor
func reorderNoteSourceKeepsClickBelowFourPointDragThresholdAndStartsFromMouseDown() throws {
  let noteID = UUID()
  let source = NoteDropSource(noteID: noteID, sourceFolderID: nil)
  let view = ReorderSourceHostingView(
    rootView: AnyView(
      Button {} label: {
        Text("Readable tab").padding(.horizontal, 10).padding(.vertical, 6)
      }
      .buttonStyle(.plain)
    )
  )
  view.noteID = noteID
  view.frame = NSRect(origin: .zero, size: view.fittingSize)
  let window = NSWindow(
    contentRect: view.frame,
    styleMask: [.borderless], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = view
  window.makeKeyAndOrderFront(nil)
  defer { window.contentView = nil; window.orderOut(nil); window.close() }
  #expect(view.hitTest(NSPoint(x: 2, y: view.bounds.midY)) === view)
  #expect(view.hitTest(NSPoint(x: view.bounds.midX, y: view.bounds.midY)) === view)

  var activations = 0
  var nativeBegins = 0
  var nativeEnds = 0
  var nativeStartEvent: NSEvent?
  view.onPrimaryClick = { activations += 1 }
  view.onNativeBegin = {
    nativeBegins += 1
    return (
      FolderDragPayload.noteProvider(source: source),
      FolderDragPayload.notePasteboardItem(source: source),
      { _ in nativeEnds += 1 }
    )
  }
  view.interceptNativeDrag = { _, _, event in
    nativeStartEvent = event
    return true
  }

  func event(_ type: NSEvent.EventType, x: CGFloat, number: Int) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
      with: type,
      location: NSPoint(x: x, y: 15),
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime + Double(number) * 0.01,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: number,
      clickCount: 1,
      pressure: type == .leftMouseUp ? 0 : 1
    ))
  }

  window.sendEvent(try event(.leftMouseDown, x: 10, number: 1))
  window.sendEvent(try event(.leftMouseDragged, x: 13, number: 2))
  #expect(nativeBegins == 0)
  window.sendEvent(try event(.leftMouseUp, x: 13, number: 3))
  #expect(activations == 1)

  window.sendEvent(try event(.leftMouseDown, x: 10, number: 4))
  window.sendEvent(try event(.leftMouseDragged, x: 14, number: 5))
  #expect(nativeBegins == 1)
  #expect(nativeStartEvent?.type == .leftMouseDown)
  #expect(nativeStartEvent?.locationInWindow == NSPoint(x: 10, y: 15))
  window.sendEvent(try event(.leftMouseUp, x: 14, number: 6))
  #expect(activations == 1)
  #expect(nativeEnds == 1)
}

@MainActor
private final class DraggingInfoProbe: NSObject, NSDraggingInfo {
  let draggingDestinationWindow: NSWindow?
  let draggingSourceOperationMask: NSDragOperation = .move
  var draggingLocation: NSPoint
  let draggedImageLocation: NSPoint = .zero
  let draggedImage: NSImage? = nil
  let draggingPasteboard: NSPasteboard
  let draggingSource: Any?
  let draggingSequenceNumber: Int
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = true
  var numberOfValidItemsForDrop = 1
  let springLoadingHighlight: NSSpringLoadingHighlight = .none

  init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard,
    source: Any? = NSObject(), sequence: Int = 1) {
    draggingDestinationWindow = window
    draggingLocation = location
    draggingPasteboard = pasteboard
    draggingSource = source
    draggingSequenceNumber = sequence
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

@MainActor
private final class ForeignWindowDelegateSentinel: NSObject, NSWindowDelegate {
  private(set) var entered = 0
  private(set) var exited = 0
  private(set) var performed = 0

  func windowShouldClose(_ sender: NSWindow) -> Bool { false }

  @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    entered += 1
    return .copy
  }

  @objc func draggingExited(_ sender: NSDraggingInfo?) { exited += 1 }

  @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    performed += 1
    return true
  }
}

@Test @MainActor
func menuWindowDropProxyForwardsForeignSelectorsAndRestoresOnlyItsDelegate() throws {
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let original = ForeignWindowDelegateSentinel()
  window.delegate = original
  let coordinator = MenuWindowNoteDropCoordinator()
  coordinator.attach(to: window)
  let proxy = try #require(window.delegate as? MenuWindowDropProxy)
  let pasteboard = NSPasteboard(name: .init("foreign-" + UUID().uuidString))
  pasteboard.declareTypes([.string], owner: nil)
  pasteboard.setString("foreign", forType: .string)
  let info = DraggingInfoProbe(window: window, location: .zero, pasteboard: pasteboard)

  #expect(window.delegate?.windowShouldClose?(window) == false)
  #expect(proxy.draggingEntered(info) == .copy)
  #expect(proxy.draggingUpdated(info) == .copy)
  #expect(proxy.prepareForDragOperation(info))
  #expect(proxy.performDragOperation(info))
  proxy.draggingExited(info)
  proxy.draggingExited(nil)
  #expect(original.entered == 1)
  #expect(original.exited == 2)
  #expect(original.performed == 1)

  coordinator.detach()
  #expect(window.delegate === original)
  coordinator.attach(to: window)
  let replacement = ForeignWindowDelegateSentinel()
  window.delegate = replacement
  coordinator.detach()
  #expect(window.delegate === replacement)
}

@Test @MainActor
func menuWindowDropGeometryIgnoresZeroHostButClipsToEveryNativeClipView() throws {
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let root = NSView(frame: window.contentView!.bounds)
  window.contentView = root
  let clip = NSClipView(frame: NSRect(x: 50, y: 20, width: 100, height: 50))
  root.addSubview(clip)
  let zeroHost = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
  clip.addSubview(zeroHost)
  let target = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
  zeroHost.addSubview(target)

  let rect = try #require(MenuWindowDropGeometry.targetRect(for: target, in: window))
  #expect(rect == NSRect(x: 50, y: 20, width: 100, height: 30))
  clip.bounds.origin.x = 200
  #expect(MenuWindowDropGeometry.targetRect(for: target, in: window) == nil)
}

@Test @MainActor
func menuWindowDropRoutesBetweenTabFolderAndOutsideWithOnePerform() throws {
  let ids = [UUID(), UUID()]
  let source = NoteDropSource(noteID: ids[0], sourceFolderID: nil)
  let session = ReorderDropSession(source: source)
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let root = NSView(frame: window.contentView!.bounds)
  window.contentView = root
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 150, height: 40))
  let tabs = FluidTabDestinationView(rootView: AnyView(Color.clear.frame(width: 220, height: 37)))
  tabs.frame = NSRect(x: 0, y: 0, width: 220, height: 37)
  scroll.documentView = tabs
  root.addSubview(scroll)
  for (index, id) in ids.enumerated() {
    let tab = ReorderSourceHostingView(rootView: AnyView(Color.clear.frame(width: 100, height: 30)))
    tab.noteID = id
    tab.frame = NSRect(x: index * 106, y: 0, width: 100, height: 30)
    tabs.addSubview(tab)
  }
  let controller = FluidTabDragController()
  controller.view = tabs
  let interaction = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
  controller.prepare(interaction: interaction, session: session, currentIDs: { ids },
    currentPins: { [] }, move: { _, _ in }, finish: {})
  let begin = window.convertPoint(toScreen: tabs.convert(NSPoint(x: 20, y: 15), to: nil))
  controller.began(at: begin)

  let folder = NSView(frame: NSRect(x: 200, y: 0, width: 100, height: 30))
  root.addSubview(folder)
  var highlights: [Bool] = []
  var performs = 0
  let destinationID = UUID()
  let sourceNotes = [Note(id: source.noteID)]
  let coordinator = MenuWindowNoteDropCoordinator()
  coordinator.activate(source: source, session: session, tabController: controller)
  _ = coordinator.registerFolderTarget(view: folder, canAccept: { _ in true }, perform: { _ in
    session.acceptNoteTransfer(data: try! JSONEncoder().encode(source), source: source,
      targetFolderID: destinationID, currentSourceNotes: { sourceNotes },
      validTargetFolderIDs: { [destinationID] }, move: { _, _ in
        performs += 1
        return true
      })
  }, setHovered: { highlights.append($0) })
  coordinator.attach(to: window)
  let proxy = try #require(window.delegate as? MenuWindowDropProxy)
  let pasteboard = NSPasteboard(name: .init("menu-route-" + UUID().uuidString))
  pasteboard.declareTypes([.init(FolderDragPayload.noteType.identifier)], owner: nil)
  pasteboard.setData(try JSONEncoder().encode(source),
    forType: .init(FolderDragPayload.noteType.identifier))
  let nativeSource = ReorderNativeSource(id: UUID(), source: nil, began: nil,
    end: { session.end(operation: $0) })
  let info = DraggingInfoProbe(window: window, location: NSPoint(x: 100, y: 15),
    pasteboard: pasteboard, source: nativeSource, sequence: 7)

  #expect(proxy.draggingEntered(info) == .move)
  #expect(controller.inside)
  info.draggingLocation = NSPoint(x: 220, y: 15)
  #expect(proxy.draggingUpdated(info) == .move)
  #expect(!controller.inside)
  #expect(highlights == [true])
  info.draggingLocation = NSPoint(x: 340, y: 80)
  #expect(proxy.draggingUpdated(info).isEmpty)
  #expect(highlights == [true, false])
  info.draggingLocation = NSPoint(x: 220, y: 15)
  #expect(proxy.draggingUpdated(info) == .move)
  #expect(highlights == [true, false, true])
  proxy.draggingExited(nil)
  #expect(highlights == [true, false, true, false])
  #expect(proxy.draggingEntered(info) == .move)
  #expect(highlights == [true, false, true, false, true])
  #expect(proxy.prepareForDragOperation(info))
  #expect(proxy.performDragOperation(info))
  #expect(!proxy.performDragOperation(info))
  #expect(performs == 0)
  proxy.concludeDragOperation(nil)
  proxy.draggingEnded(info)
  #expect(performs == 0)
  #expect(highlights == [true, false, true, false, true, false])
  nativeSource.end(.move)
  #expect(performs == 1)
}

@Test @MainActor
func menuWindowDropRejectsForeignSourceAndForgedOrMalformedActivePayload() throws {
  let source = NoteDropSource(noteID: UUID(), sourceFolderID: nil)
  let session = ReorderDropSession(source: source)
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let target = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 40))
  window.contentView = target
  var highlights = 0
  let coordinator = MenuWindowNoteDropCoordinator()
  coordinator.activate(source: source, session: session, tabController: nil)
  _ = coordinator.registerFolderTarget(view: target, canAccept: { _ in true },
    perform: { _ in true }, setHovered: { if $0 { highlights += 1 } })
  coordinator.attach(to: window)
  let proxy = try #require(window.delegate as? MenuWindowDropProxy)
  let pasteboard = NSPasteboard(name: .init("menu-reject-" + UUID().uuidString))
  pasteboard.declareTypes([.init(FolderDragPayload.noteType.identifier)], owner: nil)
  let type = NSPasteboard.PasteboardType(FolderDragPayload.noteType.identifier)

  pasteboard.setData(try JSONEncoder().encode(source), forType: type)
  let foreign = DraggingInfoProbe(window: window, location: NSPoint(x: 20, y: 20),
    pasteboard: pasteboard, source: NSObject())
  #expect(proxy.draggingEntered(foreign).isEmpty)
  let nativeSource = ReorderNativeSource(id: UUID(), source: nil, began: nil, end: { _ in })
  pasteboard.setData(Data("malformed".utf8), forType: type)
  let malformed = DraggingInfoProbe(window: window, location: NSPoint(x: 20, y: 20),
    pasteboard: pasteboard, source: nativeSource, sequence: 2)
  #expect(proxy.draggingEntered(malformed).isEmpty)
  let mismatch = NoteDropSource(noteID: UUID(), sourceFolderID: nil,
    dragSessionID: source.dragSessionID)
  pasteboard.setData(try JSONEncoder().encode(mismatch), forType: type)
  #expect(proxy.draggingEntered(malformed).isEmpty)
  #expect(highlights == 0)
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

@Test @MainActor func reorderInteractionNativeDataCommitsSynchronouslyOnlyAtValidEnd() throws {
  let ids = [UUID(), UUID(), UUID()]
  for change in 0..<4 {
    var currentIDs = ids
    var currentPins: Set<UUID> = []
    var interaction = ReorderInteraction(sourceID: ids[0], originalIDs: ids)
    interaction.propose(over: ids[2], after: true, currentIDs: ids)
    let source = NoteDropSource(
      noteID: ids[0], sourceFolderID: nil, dragSessionID: interaction.sessionID
    )
    let data = try JSONEncoder().encode(source)
    let session = ReorderDropSession(source: source)
    var commits = 0
    let accepted = session.acceptReorder(data: data, interaction: interaction,
      currentIDs: { currentIDs }, currentPinnedIDs: { currentPins }) { sourceID, destination in
        #expect(sourceID == ids[0])
        #expect(destination == 2)
        commits += 1
      }
    #expect(accepted)
    let replayed = session.acceptReorder(data: data, interaction: interaction,
      currentIDs: { currentIDs }, currentPinnedIDs: { currentPins }, move: { _, _ in
        Issue.record("A native payload must not be accepted twice")
      })
    #expect(!replayed)
    #expect(commits == 0)
    switch change {
    case 1: currentIDs.swapAt(1, 2)
    case 2: currentPins.insert(ids[0])
    case 3: session.cancel()
    default: break
    }
    session.end(operation: .move)
    #expect(commits == (change == 0 ? 1 : 0))
  }

  let source = NoteDropSource(noteID: ids[0], sourceFolderID: nil)
  let mismatch = NoteDropSource(
    noteID: ids[1], sourceFolderID: nil, dragSessionID: source.dragSessionID
  )
  let session = ReorderDropSession(source: source)
  var commits = 0
  #expect(!session.acceptDrop(data: try JSONEncoder().encode(mismatch)) { commits += 1 })
  session.end(operation: .move)
  #expect(commits == 0)
}

@Test @MainActor
func reorderInteractionNativeFolderDataStagesOnceAndRevalidatesAtEnd() throws {
  let destination = try Folder(name: "Destination")
  let note = Note(title: "Move me")
  let source = NoteDropSource(noteID: note.id, sourceFolderID: nil)
  let data = try JSONEncoder().encode(source)
  var notes = [note]
  var folders = [destination]
  var moves = 0
  var movedSource: NoteDropSource?
  var movedTarget: UUID?
  let session = ReorderDropSession(source: source)

  let accepted = session.acceptNoteTransfer(data: data, source: source,
    targetFolderID: destination.id, currentSourceNotes: { notes },
    validTargetFolderIDs: { Set(folders.map(\.id)) }) { accepted, target in
      movedSource = accepted
      movedTarget = target
      moves += 1
      return true
    }
  #expect(accepted)
  #expect(!session.acceptNoteTransfer(data: data, source: source,
    targetFolderID: destination.id, currentSourceNotes: { notes },
    validTargetFolderIDs: { Set(folders.map(\.id)) }, move: { _, _ in false }))
  #expect(moves == 0)
  session.end(operation: .move)
  #expect(moves == 1)
  #expect(movedSource == source)
  #expect(movedTarget == destination.id)

  for change in 0..<4 {
    notes = [note]
    folders = [destination]
    let candidate = ReorderDropSession(source: source)
    var rejectedMoves = 0
    #expect(candidate.acceptNoteTransfer(data: data, source: source,
      targetFolderID: destination.id, currentSourceNotes: { notes },
      validTargetFolderIDs: { Set(folders.map(\.id)) }) { _, _ in
        rejectedMoves += 1
        return true
      })
    switch change {
    case 0: notes.removeAll()
    case 1: notes[0].isPinned.toggle()
    case 2: folders.removeAll()
    case 3: candidate.cancel()
    default: break
    }
    candidate.end(operation: .move)
    #expect(rejectedMoves == 0)
  }
}

@MainActor
private final class DraggingSessionLocationProbe: NSDraggingSession {
  override var draggingLocation: NSPoint { NSPoint(x: -1, y: 1441) }
}

@MainActor
private final class ScrollCallClipView: NSClipView {
  private(set) var scrollCalls = 0
  var preservesProposedBounds = false

  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    preservesProposedBounds ? proposedBounds : super.constrainBoundsRect(proposedBounds)
  }

  override func scroll(to newOrigin: NSPoint) {
    scrollCalls += 1
    super.scroll(to: newOrigin)
  }

  func resetScrollCalls() { scrollCalls = 0 }
}

@MainActor
private final class ScrollReflectionProbe: NSScrollView {
  private(set) var reflectionCalls = 0

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    reflectionCalls += 1
    super.reflectScrolledClipView(clipView)
  }

  func resetReflectionCalls() { reflectionCalls = 0 }
}

@Test @MainActor func reorderInteractionNativeBeginUsesCallbackScreenPoint() {
  let expected = NSPoint(x: 1642, y: 487)
  var received: NSPoint?
  let source = ReorderNativeSource(
    id: UUID(), source: nil, began: { received = $0 }, end: { _ in }
  )

  source.draggingSession(DraggingSessionLocationProbe(), willBeginAt: expected)

  #expect(received == expected)
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
  var aligned = frames
  aligned[ids[2]]?.size.width -= 1
  aligned[ids[2]]?.size.height += 1
  #expect(drag.isValid(ids: ids, pins: [ids[0]], frames: aligned, backingScaleFactor: 1))
  var retinaAligned = frames
  retinaAligned[ids[2]]?.size.width -= 0.5
  retinaAligned[ids[2]]?.size.height += 0.5
  #expect(drag.isValid(ids: ids, pins: [ids[0]], frames: retinaAligned, backingScaleFactor: 2))
  var overOnePixel = frames
  overOnePixel[ids[2]]?.size.width -= 1.001
  #expect(!drag.isValid(ids: ids, pins: [ids[0]], frames: overOnePixel, backingScaleFactor: 1))
  overOnePixel = frames
  overOnePixel[ids[2]]?.size.width -= 0.501
  #expect(!drag.isValid(ids: ids, pins: [ids[0]], frames: overOnePixel, backingScaleFactor: 2))
  var missing = frames
  missing[ids[2]] = nil
  #expect(!drag.isValid(ids: ids, pins: [ids[0]], frames: missing))
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
  sourceViews[2].frame.size.width -= 1 / window.backingScaleFactor
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
func reorderInteractionFluidControllerSkipsSaturatedEdgeScrollWork() {
  let ids = [UUID(), UUID()]
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false
  )
  window.isReleasedWhenClosed = false
  let scroll = ScrollReflectionProbe(frame: window.contentView!.bounds)
  let clip = ScrollCallClipView(frame: scroll.bounds)
  scroll.contentView = clip
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
  let interaction = ReorderInteraction(sourceID: ids[1], originalIDs: ids)
  let session = ReorderDropSession(source: .init(
    noteID: ids[1], sourceFolderID: nil, dragSessionID: interaction.sessionID
  ))
  let controller = FluidTabDragController()
  controller.view = destination
  controller.prepare(
    interaction: interaction,
    session: session,
    currentIDs: { ids },
    currentPins: { [] },
    move: { _, _ in Issue.record("A saturated edge tick must not commit") },
    finish: {}
  )
  func screen(_ x: CGFloat) -> NSPoint {
    window.convertPoint(toScreen: destination.convert(NSPoint(x: x, y: 15), to: nil))
  }
  controller.began(at: screen(120))
  controller.moved(to: screen(1))
  // AppKit can leave this rounding residue after constraining a scroll to the leading edge.
  let observedLeadingResidue: CGFloat = -4.973799150320701e-14
  clip.preservesProposedBounds = true
  clip.setBoundsOrigin(NSPoint(x: observedLeadingResidue, y: clip.bounds.minY))
  #expect(clip.bounds.minX == observedLeadingResidue)
  clip.resetScrollCalls()
  scroll.resetReflectionCalls()
  var publications = 0
  let observation = controller.objectWillChange.sink { publications += 1 }

  for _ in 0..<20 { controller.tick() }

  #expect(clip.scrollCalls == 0)
  #expect(scroll.reflectionCalls == 0)
  #expect(publications == 0)
  #expect(scroll.contentView.bounds.minX == observedLeadingResidue)
  #expect(controller.preview?.destination == 0)
  withExtendedLifetime(observation) {}
  controller.cancel()
}

@Test @MainActor
func reorderDestinationCommitsAndResetsSynchronouslyAtNativeEnd() throws {
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
  var sourceViews: [ReorderSourceHostingView] = []
  for (index, id) in ids.enumerated() {
    let source = ReorderSourceHostingView(
      rootView: AnyView(Color.clear.frame(width: 100, height: 30))
    )
    source.noteID = id
    source.frame = NSRect(x: index * 106, y: 0, width: 100, height: 30)
    destination.addSubview(source)
    sourceViews.append(source)
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
  var moves = 0
  var finishes = 0
  controller.prepare(
    interaction: interaction,
    session: session,
    currentIDs: { ids },
    currentPins: { [] },
    move: { sourceID, destination in
      #expect(sourceID == ids[0])
      #expect(destination == 1)
      moves += 1
    },
    finish: { finishes += 1 }
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
    location: destination.convert(NSPoint(x: 180, y: 15), to: nil),
    pasteboard: pasteboard
  )

  #expect(destination.prepareForDragOperation(probe))
  #expect(probe.animatesToDestination == false)
  #expect(destination.performDragOperation(probe))
  #expect(moves == 0)
  #expect(controller.preview != nil)
  #expect(sourceViews[0].layer?.opacity == 0)

  session.end(operation: .move)
  controller.ended(sessionID: session.id, operation: .move)

  #expect(moves == 1)
  #expect(finishes == 1)
  #expect(controller.preview == nil)
  #expect(!controller.inside)
  #expect(sourceViews[0].layer?.opacity == 1)
}

@Test @MainActor func reorderInteractionNativeLayerReversalUsesPresentationAndMotionCanBeDisabled() throws {
  let source = ReorderSourceHostingView(rootView: AnyView(Color.clear.frame(width: 120, height: 30)))
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = source
  window.makeKeyAndOrderFront(nil)
  defer { window.contentView = nil; window.orderOut(nil); window.close() }
  window.displayIfNeeded()
  CATransaction.flush()
  source.setReorderDisplacement(0, animated: false)
  let layer = try #require(source.layer)
  layer.speed = 0
  layer.timeOffset = 0
  source.setReorderDisplacement(-80, animated: true)
  CATransaction.flush()
  layer.timeOffset = AppMotion.standardDuration / 3
  CATransaction.flush()
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
