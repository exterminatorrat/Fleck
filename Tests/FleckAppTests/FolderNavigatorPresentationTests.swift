import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Suite("FolderNavigatorPresentationTests")
@MainActor
struct FolderNavigatorPresentationTests {
  struct OverflowCase: Sendable {
    let width: CGFloat
    let names: [String]
    let overflows: Bool
  }

  @Test func overflowUsesActualContentAndTreatsExactFitAsFitting() {
    let fitting = FolderNavigatorOverflowPresentation(contentWidth: 240, referenceWidth: 240)
    #expect(!fitting.overflows)
    #expect(fitting.railWidth == 0)

    let overflowing = FolderNavigatorOverflowPresentation(
      contentWidth: 240.01,
      referenceWidth: 240
    )
    #expect(overflowing.overflows)
    #expect(overflowing.railWidth == 56)
  }

  @Test func occlusionConservativelyCoversPartialAndFullyHiddenRows() {
    let occlusion = FolderNavigatorOcclusionPresentation(composerLeadingX: 200)
    #expect(!occlusion.covers(CGRect(x: 100, y: 0, width: 100, height: 24)))
    #expect(occlusion.covers(CGRect(x: 190, y: 0, width: 20, height: 24)))
    #expect(occlusion.covers(CGRect(x: 220, y: 0, width: 40, height: 24)))
    #expect(occlusion.covers(nil))
  }

  @Test func narrowMaskFullyHidesUnderlyingRowsWithoutOverrunningTheBand() {
    let mask = FolderNavigatorMaskPresentation(bandWidth: 280)
    #expect(mask.composerWidth == 280)
    #expect(mask.leadingWidth == 0)
    #expect(mask.fadeWidth == 0)
    #expect(mask.opaqueWidth == 0)
    #expect(mask.opaqueWidth + mask.fadeWidth + mask.composerWidth == mask.bandWidth)

    let wideMask = FolderNavigatorMaskPresentation(bandWidth: 520)
    #expect(wideMask.composerWidth == 340)
    #expect(wideMask.fadeWidth == 12)
    #expect(wideMask.opaqueWidth == 168)
    #expect(
      wideMask.opaqueWidth + wideMask.fadeWidth + wideMask.composerWidth
        == wideMask.bandWidth
    )
  }

  @Test func coveredRowsGateNativeDropsReorderKeyboardAndAccessibility() throws {
    let source = try folderNavigatorSource()
    #expect(source.contains("accepts: { !isCovered(.folder(folder.id)) }"))
    #expect(source.contains("if hovered && !isCovered(target)"))
    #expect(
      source.components(separatedBy: "guard !isCovered(target) else { return false }").count
        - 1 == 3
    )
    #expect(source.contains(".disabled(isCovered(.unfiled))"))
    #expect(source.contains(".disabled(isCovered(.folder(folder.id)))"))
    #expect(source.contains(".accessibilityHidden(isCovered(.unfiled))"))
    #expect(source.contains(".accessibilityHidden(isCovered(.folder(folder.id)))"))
    #expect(source.contains(".disabled(isCreatingFolder)"))
    #expect(
      source.components(separatedBy: "guard !isFolderTextInputActive else").count - 1 == 5
    )
    #expect(source.contains("if isCreatingFolder { return isNewFolderTextEditing }"))
    #expect(source.contains("guard !isCovered(.unfiled) else { return }"))
    #expect(source.contains("case .unfiled: !isCovered(.unfiled)"))
    #expect(source.contains("case .folder(let id): !isCovered(.folder(id))"))
    #expect(source.contains("func controlTextDidBeginEditing"))
    #expect(source.contains("func controlTextDidEndEditing"))
    #expect(source.contains("return reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)"))
    #expect(source.contains("if reduceMotion { return .opacity.animation(motion.state) }"))
    #expect(source.contains("case .keyboard:\n        return nil"))
    #expect(source.contains(".transition(composerTransition)"))
  }

  @Test(arguments: [
    OverflowCase(width: 380, names: ["A"], overflows: false),
    OverflowCase(width: 520, names: ["A", "B"], overflows: false),
    OverflowCase(
      width: 520,
      names: ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"],
      overflows: true
    ),
    OverflowCase(
      width: 640,
      names: [String(repeating: "Long folder name ", count: 3)],
      overflows: true
    ),
  ])
  func hostedIntrinsicFolderWidthsControlOverflow(testCase: OverflowCase) async throws {
    let fixture = try await FolderNavigatorFixture(width: testCase.width, names: testCase.names)
    defer { fixture.close() }

    #expect(
      fixture.isVisible(label: "Reveal earlier folders") == testCase.overflows
    )
    #expect(
      fixture.isVisible(label: "Reveal later folders") == testCase.overflows
    )
    if testCase.width == 520, testCase.names == ["A", "B"] {
      try fixture.captureIfRequested(name: "fitting-two-short-ab-520-resting")
      try fixture.click(fixture.element(label: "New folder"))
      await fixture.settle()
      try fixture.captureIfRequested(name: "fitting-two-short-ab-520-composing")
    }
  }

  @Test func resizingOverflowingContentBackToFitRemovesTheArrowRail() async throws {
    let fixture = try await FolderNavigatorFixture(
      width: 380,
      names: ["Moderately long folder"]
    )
    defer { fixture.close() }

    let scroll = try fixture.folderScrollView()
    let document = try #require(scroll.documentView)
    let restingViewportWidth = scroll.contentView.bounds.width
    try fixture.click(fixture.element(label: "Reveal later folders"))
    await fixture.settle()
    #expect(scroll.contentView.bounds.minX > 0)

    await fixture.resize(to: 640)
    #expect(!fixture.isVisible(label: "Reveal earlier folders"))
    #expect(try fixture.folderScrollView() === scroll)
    #expect(scroll.documentView === document)
    #expect(scroll.contentView.bounds.width > restingViewportWidth)
    #expect(abs(scroll.contentView.bounds.minX) < 0.5)
    await fixture.resize(to: 380)
    #expect(fixture.isVisible(label: "Reveal earlier folders"))
    #expect(try fixture.folderScrollView() === scroll)
  }

  @Test func compactRenameCreateAndDeleteRemeasureIntrinsicContent() async throws {
    let fixture = try await FolderNavigatorFixture(width: 420, names: ["A", "B"])
    defer { fixture.close() }

    #expect(fixture.isVisible(label: "Reveal earlier folders"))
    try fixture.click(fixture.element(label: "Collapse Unfiled"))
    await fixture.settle()
    #expect(!fixture.isVisible(label: "Reveal earlier folders"))

    let first = try #require(fixture.state.workspace.folders.first)
    try fixture.state.renameFolder(
      id: first.id,
      name: "A folder name that becomes much wider"
    )
    await fixture.settle()
    #expect(fixture.isVisible(label: "Reveal earlier folders"))
    try fixture.state.renameFolder(id: first.id, name: "A")
    await fixture.settle()
    #expect(!fixture.isVisible(label: "Reveal earlier folders"))

    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    try fixture.type("A newly created folder with a wider name")
    try fixture.sendKey(characters: "\r", keyCode: 36)
    await fixture.settle()
    #expect(fixture.isVisible(label: "Reveal earlier folders"))
    let created = try #require(fixture.state.workspace.folders.last)
    try fixture.state.deleteFolder(id: created.id, activeFolderID: nil)
    await fixture.settle()
    #expect(!fixture.isVisible(label: "Reveal earlier folders"))
  }

  @Test func composingPreservesOverflowRailAndScrolledFolderGeometry() async throws {
    let fixture = try await FolderNavigatorFixture(
      width: 520,
      names: ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
    )
    defer { fixture.close() }
    let firstFolderID = try #require(fixture.state.workspace.folders.first?.id)
    let scroll = try fixture.folderScrollView()
    let document = try #require(scroll.documentView)

    try fixture.click(fixture.element(label: "Reveal later folders"))
    await fixture.settle()
    try fixture.captureIfRequested(name: "overflow-many-folders-520-resting")
    let scrolledFrame = try fixture.frame(identifier: "folder-\(firstFolderID.uuidString)")
    let trashFrame = try fixture.frame(identifier: "folder-trash")
    let scrolledOffset = scroll.contentView.bounds.origin
    let viewport = scroll.contentView.bounds.size
    #expect(scrolledOffset.x > 0)

    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    try fixture.captureIfRequested(name: "overflow-many-folders-520-composing")
    #expect(fixture.elementIfPresent(label: "Reveal earlier folders") != nil)
    #expect(
      try fixture.frame(identifier: "folder-\(firstFolderID.uuidString)") == scrolledFrame
    )
    #expect(try fixture.frame(identifier: "folder-trash") == trashFrame)
    #expect(try fixture.folderScrollView() === scroll)
    #expect(scroll.documentView === document)
    #expect(scroll.contentView.bounds.origin == scrolledOffset)
    #expect(scroll.contentView.bounds.size == viewport)
    try fixture.performAccessibilityPress(label: "Reveal earlier folders")
    await fixture.settle()
    #expect(scroll.contentView.bounds.origin == scrolledOffset)
  }

  @Test func compactUnfiledAllocationStaysStableAcrossComposeCloseAndReopen() async throws {
    let fixture = try await FolderNavigatorFixture(
      width: 520,
      names: ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
    )
    defer { fixture.close() }
    try fixture.click(fixture.element(label: "Collapse Unfiled"))
    try await fixture.settleAnimation()
    let scroll = try fixture.folderScrollView()
    let before = scroll.contentView.bounds

    try fixture.click(fixture.element(label: "New folder"))
    try await fixture.settleAnimation()
    #expect(scroll.contentView.bounds == before)
    try fixture.click(fixture.element(label: "Cancel new folder"))
    try await fixture.settleAnimation()
    #expect(scroll.contentView.bounds == before)
    try fixture.click(fixture.element(label: "New folder"))
    try await fixture.settleAnimation()
    #expect(scroll.contentView.bounds == before)
  }

  @Test func compactUnfiledAllocationPreservesNonzeroScrolledOffsetDuringCompose() async throws {
    let fixture = try await FolderNavigatorFixture(
      width: 520,
      names: ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
    )
    defer { fixture.close() }
    try fixture.click(fixture.element(label: "Reveal later folders"))
    try await fixture.settleAnimation()
    try fixture.click(fixture.element(label: "Collapse Unfiled"))
    try await fixture.settleAnimation()
    let scroll = try fixture.folderScrollView()
    let before = scroll.contentView.bounds
    #expect(before.minX > 0)

    try fixture.click(fixture.element(label: "New folder"))
    try await fixture.settleAnimation()
    #expect(scroll.contentView.bounds == before)
  }

  @Test func deletingScrolledOverflowRestoresTheMountedScrollToLeading() async throws {
    let fixture = try await FolderNavigatorFixture(
      width: 520,
      names: ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
    )
    defer { fixture.close() }
    let scroll = try fixture.folderScrollView()
    let document = try #require(scroll.documentView)
    let overflowingViewportWidth = scroll.contentView.bounds.width

    try fixture.click(fixture.element(label: "Reveal later folders"))
    await fixture.settle()
    #expect(scroll.contentView.bounds.minX > 0)
    for folder in fixture.state.workspace.folders.dropFirst() {
      try fixture.state.deleteFolder(id: folder.id, activeFolderID: nil)
    }
    await fixture.settle()

    #expect(!fixture.isVisible(label: "Reveal earlier folders"))
    #expect(try fixture.folderScrollView() === scroll)
    #expect(scroll.documentView === document)
    #expect(scroll.contentView.bounds.width > overflowingViewportWidth)
    #expect(abs(scroll.contentView.bounds.minX) < 0.5)
  }

  @Test func creatingFolderKeepsNavigatorControlsOnTheSameRow() async throws {
    let fixture = try await FolderNavigatorFixture(width: 520)
    defer { fixture.close() }
    let unfiledBefore = try fixture.frame(identifier: "folder-unfiled")
    let trashBefore = try fixture.frame(identifier: "folder-trash")
    let newFolder = try fixture.element(label: "New folder")
    let newFolderFrame = try fixture.frame(identifier: "folder-new")
    try fixture.click(newFolder)
    await fixture.settle()

    _ = try #require(
      fixture.textFields.first { $0.placeholderString == "New folder" }
    )
    let unfiledAfter = try fixture.frame(identifier: "folder-unfiled")
    let trashAfter = try fixture.frame(identifier: "folder-trash")

    #expect(abs(unfiledAfter.minY - unfiledBefore.minY) < 1)
    #expect(abs(trashAfter.minY - trashBefore.minY) < 1)
    #expect(try fixture.frame(identifier: "folder-new").minX < newFolderFrame.minX)

    try fixture.click(fixture.element(label: "Cancel new folder"))
    try await fixture.settleAnimation()
    #expect(abs(try fixture.frame(identifier: "folder-new").minX - newFolderFrame.minX) < 1)
  }

  @Test func composerFocusValidationCancellationAndCreationStayNative() async throws {
    let fixture = try await FolderNavigatorFixture(width: 380)
    defer { fixture.close() }
    let selectedNoteID = fixture.state.workspace.selectedNoteID
    let coveredUnfiledFrame = try fixture.frame(identifier: "folder-unfiled")

    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    let field = try fixture.newFolderField()
    #expect(field.currentEditor() === fixture.window.firstResponder)
    #expect(fixture.isVisible(identifier: "folder-trash"))
    try fixture.click(screenPoint: NSPoint(x: coveredUnfiledFrame.midX, y: coveredUnfiledFrame.midY))
    await fixture.settle()
    try fixture.captureIfRequested(name: "narrow-composing-380")
    #expect(fixture.state.workspace.selectedNoteID == selectedNoteID)
    try fixture.performAccessibilityPress(identifier: "folder-unfiled")
    await fixture.settle()
    #expect(fixture.state.workspace.selectedNoteID == selectedNoteID)
    #expect(fixture.newFolderFieldIfPresent() != nil)

    try fixture.type("   ")
    try fixture.sendKey(characters: "\r", keyCode: 36)
    await fixture.settle()
    #expect(fixture.state.workspace.folders.count == 2)
    #expect(try fixture.newFolderField().stringValue == "   ")

    try fixture.replaceDraft(with: "Work")
    try fixture.sendKey(characters: "\r", keyCode: 36)
    await fixture.settle()
    #expect(fixture.state.workspace.folders.count == 2)
    #expect(try fixture.newFolderField().stringValue == "Work")

    try fixture.click(fixture.element(identifier: "folder-new"))
    await fixture.settle()
    #expect(try fixture.newFolderField().stringValue == "Work")

    try fixture.sendKey(characters: "\u{1b}", keyCode: 53)
    await fixture.settle()
    #expect(fixture.newFolderFieldIfPresent() == nil)

    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    #expect(try fixture.newFolderField().stringValue.isEmpty)
    try fixture.type("Created")
    try fixture.sendKey(characters: "\r", keyCode: 36)
    await fixture.settle()
    #expect(fixture.newFolderFieldIfPresent() == nil)
    #expect(fixture.state.workspace.folders.map(\.name).contains("Created"))
    #expect(fixture.state.workspace.selectedNoteID == selectedNoteID)
  }

  @Test func uncoveredRowsRemainUsableWhileComposing() async throws {
    let fixture = try await FolderNavigatorFixture(width: 640)
    defer { fixture.close() }
    let unfiledNote = try #require(fixture.state.workspace.notes.first { $0.folderID == nil })

    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    try fixture.performAccessibilityPress(identifier: "folder-unfiled")
    await fixture.settle()

    #expect(fixture.state.workspace.selectedNoteID == unfiledNote.id)
    #expect(fixture.newFolderFieldIfPresent() != nil)
  }

  @Test func escapeCancelsComposerAfterFocusMovesToUncoveredRow() async throws {
    let fixture = try await FolderNavigatorFixture(width: 640)
    defer { fixture.close() }
    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    try fixture.click(fixture.element(identifier: "folder-unfiled"))
    await fixture.settle()
    #expect(try fixture.newFolderField().currentEditor() == nil)

    try fixture.sendKey(characters: "\u{1b}", keyCode: 53)
    await fixture.settle()
    #expect(fixture.newFolderFieldIfPresent() == nil)
  }

  @Test func initialSpaceBelongsToTheNativeFolderField() async throws {
    let fixture = try await FolderNavigatorFixture(width: 640)
    defer { fixture.close() }
    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    let field = try fixture.newFolderField()
    #expect(field.currentEditor() === fixture.window.firstResponder)

    try fixture.sendKey(characters: " ", keyCode: 49)
    await fixture.settle()
    #expect(field.stringValue == " ")
  }

  @Test func returnSubmitsUnchangedDraftAfterNativeFieldRefocus() async throws {
    let fixture = try await FolderNavigatorFixture(width: 640)
    defer { fixture.close() }
    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    try fixture.type("Projects")
    try fixture.click(fixture.element(identifier: "folder-unfiled"))
    await fixture.settle()
    #expect(try fixture.newFolderField().currentEditor() == nil)

    let field = try fixture.newFolderField()
    #expect(fixture.window.makeFirstResponder(field))
    await fixture.settle()
    #expect(try fixture.newFolderField().currentEditor() === fixture.window.firstResponder)
    try fixture.sendKey(characters: "\r", keyCode: 36)
    await fixture.settle()
    #expect(fixture.newFolderFieldIfPresent() == nil)
    #expect(fixture.state.workspace.folders.map(\.name).contains("Projects"))
  }

  @Test func markedTextSurvivesUpdatesAndDoesNotSubmitAsACommand() async throws {
    let fixture = try await FolderNavigatorFixture(width: 520)
    defer { fixture.close() }
    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    let field = try fixture.newFolderField()
    let editor = try #require(field.currentEditor() as? NSTextView)

    editor.setMarkedText(
      "かな",
      selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    #expect(editor.hasMarkedText())
    let markedRange = editor.markedRange()
    fixture.state.updatePreferences { $0.showFormattingBar.toggle() }
    await fixture.settle()
    #expect(field.currentEditor() === editor)
    #expect(editor.hasMarkedText())
    #expect(editor.markedRange() == markedRange)

    try fixture.sendKey(characters: "\r", keyCode: 36)
    await fixture.settle()
    #expect(fixture.newFolderFieldIfPresent() != nil)
    #expect(!fixture.state.workspace.folders.map(\.name).contains("かな"))
  }

  @Test func nativeRegisteredTargetsRecheckOcclusionBeforeAcceptAndPerform() throws {
    let source = NoteDropSource(noteID: UUID(), sourceFolderID: nil)
    let session = ReorderDropSession(source: source)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView(frame: window.contentView!.bounds)
    window.contentView = root
    let target = NSView(frame: NSRect(x: 20, y: 10, width: 80, height: 30))
    root.addSubview(target)
    var rowFrame: CGRect?
    var composerLeadingX: CGFloat = 120
    var performs = 0
    func allowsInteraction() -> Bool {
      !FolderNavigatorOcclusionPresentation(composerLeadingX: composerLeadingX)
        .covers(rowFrame)
    }
    let coordinator = MenuWindowNoteDropCoordinator()
    coordinator.activate(source: source, session: session, tabController: nil)
    _ = coordinator.registerFolderTarget(
      view: target,
      canAccept: { _ in allowsInteraction() },
      perform: { _ in
        guard allowsInteraction() else { return false }
        performs += 1
        return true
      },
      setHovered: { _ in }
    )
    coordinator.attach(to: window)
    let proxy = try #require(window.delegate as? MenuWindowDropProxy)
    let pasteboard = NSPasteboard(name: .init("folder-occlusion-" + UUID().uuidString))
    let type = NSPasteboard.PasteboardType(FolderDragPayload.noteType.identifier)
    pasteboard.declareTypes([type], owner: nil)
    pasteboard.setData(try JSONEncoder().encode(source), forType: type)
    let nativeSource = ReorderNativeSource(id: UUID(), source: nil, began: nil, end: { _ in })
    let info = FolderNavigatorDraggingInfo(
      window: window,
      location: NSPoint(x: 40, y: 20),
      pasteboard: pasteboard,
      source: nativeSource
    )

    #expect(proxy.draggingEntered(info).isEmpty)
    #expect(!proxy.performDragOperation(info))
    rowFrame = target.frame
    #expect(proxy.draggingUpdated(info) == .move)
    #expect(proxy.prepareForDragOperation(info))
    composerLeadingX = 50
    #expect(!proxy.performDragOperation(info))
    #expect(performs == 0)
    composerLeadingX = 120
    #expect(proxy.draggingUpdated(info) == .move)
    #expect(proxy.performDragOperation(info))
    #expect(performs == 1)
  }
}

private func folderNavigatorSource() throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  return try #require(
    source.components(separatedBy: "private struct FolderNavigator: View").last?
      .components(separatedBy: "struct TrashPanelOverlay: View").first
  )
}

@MainActor
private final class FolderNavigatorDraggingInfo: NSObject, NSDraggingInfo {
  let draggingDestinationWindow: NSWindow?
  let draggingSourceOperationMask: NSDragOperation = .move
  var draggingLocation: NSPoint
  let draggedImageLocation: NSPoint = .zero
  let draggedImage: NSImage? = nil
  let draggingPasteboard: NSPasteboard
  let draggingSource: Any?
  let draggingSequenceNumber = 1
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = true
  var numberOfValidItemsForDrop = 1
  let springLoadingHighlight: NSSpringLoadingHighlight = .none

  init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard, source: Any?) {
    draggingDestinationWindow = window
    draggingLocation = location
    draggingPasteboard = pasteboard
    draggingSource = source
  }

  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
    nil
  }
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
private final class FolderNavigatorFixture {
  let root: URL
  let state: AppState
  let runtime: DictationRuntime
  let window: NSWindow
  let host: NSHostingView<AnyView>

  init(width: CGFloat, names: [String] = ["Work", "Personal"]) async throws {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("folder-navigator-" + UUID().uuidString, isDirectory: true)
    state = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    let folders = try names.map { try Folder(name: $0) }
    let filedNotes = folders.map { Note(title: "Note in \($0.name)", folderID: $0.id) }
    let unfiledNote = Note(title: "Unfiled fixture note")
    let selectedNoteID = filedNotes.first?.id ?? unfiledNote.id
    state.workspace = Workspace(
      notes: filedNotes + [unfiledNote],
      selectedNoteID: selectedNoteID,
      folders: folders
    )
    runtime = DictationRuntime(appState: state, applicationSupportURL: root)
    host = NSHostingView(
      rootView: AnyView(
        NotesPanel(dictationRuntime: runtime, sizing: .container)
          .environmentObject(state)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      )
    )
    window = NSWindow(
      contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 430),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    await settle()
  }

  var textFields: [NSTextField] {
    descendants(in: host, as: NSTextField.self)
  }

  func close() {
    window.contentView = nil
    window.orderOut(nil)
    window.close()
    Task { await runtime.shutdown() }
    try? FileManager.default.removeItem(at: root)
  }

  func settle() async {
    for _ in 0..<40 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
  }

  func settleAnimation() async throws {
    try await Task.sleep(for: .milliseconds(260))
    await settle()
  }

  func resize(to width: CGFloat) async {
    window.setContentSize(NSSize(width: width, height: 430))
    host.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 430))
    await settle()
  }

  func element(label: String) throws -> NSObject {
    try #require(findElement(host, matching: "accessibilityLabel", value: label))
  }

  func element(identifier: String) throws -> NSObject {
    try #require(findElement(host, matching: "accessibilityIdentifier", value: identifier))
  }

  func elementIfPresent(label: String) -> NSObject? {
    findElement(host, matching: "accessibilityLabel", value: label)
  }

  func elementIfPresent(identifier: String) -> NSObject? {
    findElement(host, matching: "accessibilityIdentifier", value: identifier)
  }

  func isVisible(label: String) -> Bool {
    elementIfPresent(label: label) != nil
  }

  func isVisible(identifier: String) -> Bool {
    elementIfPresent(identifier: identifier) != nil
  }

  func performAccessibilityPress(identifier: String) throws {
    try performAccessibilityPress(element(identifier: identifier))
  }

  func performAccessibilityPress(label: String) throws {
    try performAccessibilityPress(element(label: label))
  }

  private func performAccessibilityPress(_ element: NSObject) throws {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    #expect(element.responds(to: selector))
    _ = element.perform(selector)
  }

  func frame(identifier: String) throws -> NSRect {
    let element = try #require(
      findElement(host, matching: "accessibilityIdentifier", value: identifier)
    )
    return try #require(element.value(forKey: "accessibilityFrame") as? NSValue).rectValue
  }

  func folderScrollView() throws -> NSScrollView {
    let folderFrame = try frame(identifier: "folder-\(state.workspace.folders[0].id.uuidString)")
    return try #require(
      descendants(in: host, as: NSScrollView.self)
        .filter { scroll in
          let windowFrame = scroll.convert(scroll.bounds, to: nil)
          let screenFrame = window.convertToScreen(windowFrame)
          return screenFrame.minY <= folderFrame.midY && screenFrame.maxY >= folderFrame.midY
            && screenFrame.height <= 34
        }
        .min { $0.bounds.height < $1.bounds.height }
    )
  }

  func click(_ element: NSObject) throws {
    let frame = try #require(element.value(forKey: "accessibilityFrame") as? NSValue).rectValue
    try click(screenPoint: NSPoint(x: frame.midX, y: frame.midY))
  }

  func click(screenPoint: NSPoint) throws {
    let location = window.convertPoint(fromScreen: screenPoint)
    for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try #require(NSEvent.mouseEvent(
        with: eventType,
        location: location,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: eventType == .leftMouseDown ? 1 : 0
      ))
      window.sendEvent(event)
    }
  }

  func newFolderFieldIfPresent() -> NSTextField? {
    textFields.first { $0.placeholderString == "New folder" }
  }

  func newFolderField() throws -> NSTextField {
    try #require(newFolderFieldIfPresent())
  }

  func type(_ string: String) throws {
    let editor = try #require(newFolderField().currentEditor() as? NSTextView)
    editor.insertText(string, replacementRange: editor.selectedRange())
  }

  func replaceDraft(with string: String) throws {
    let editor = try #require(newFolderField().currentEditor() as? NSTextView)
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    editor.insertText(string, replacementRange: editor.selectedRange())
  }

  func sendKey(characters: String, keyCode: UInt16) throws {
    let event = try #require(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    ))
    window.sendEvent(event)
  }

  func captureIfRequested(name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["FLECK_FOLDER_CAPTURE_DIR"] else {
      return
    }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    host.displayIfNeeded()
    let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: image)
    let data = try #require(image.representation(using: .png, properties: [:]))
    try data.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
  }

  private func descendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
    var result = view as? T == nil ? [] : [view as! T]
    for subview in view.subviews {
      result.append(contentsOf: descendants(in: subview, as: type))
    }
    return result
  }

  private func findElement(_ value: Any?, matching selectorName: String, value expected: String)
    -> NSObject?
  {
    guard let element = value as? NSObject else { return nil }
    let selector = NSSelectorFromString(selectorName)
    if element.responds(to: selector),
      element.perform(selector)?.takeUnretainedValue() as? String == expected
    {
      return element
    }
    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    let rawChildren = element.responds(to: childrenSelector)
      ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
    let children = NSAccessibility.unignoredChildren(from: rawChildren ?? [])
    for child in children {
      if let match = findElement(child, matching: selectorName, value: expected) {
        return match
      }
    }
    return nil
  }
}
