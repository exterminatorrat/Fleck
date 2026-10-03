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

  @Test func focusedUnselectedFolderRowsUseAdaptiveNeutralOutlines() throws {
    let source = try folderNavigatorSource()
    #expect(source.contains(".fleckNeutralControlOutline("))
    #expect(source.contains("isFocused: isFocused && !isSelected"))
    #expect(source.contains("cornerRadius: 6"))
    #expect(!source.contains(".strokeBorder(theme.color(.focusRing), lineWidth: 1)"))
    #expect(source.contains("? theme.color(.hoverFill)"))
    #expect(source.contains("isSelected ? theme.color(.selectionFill) : .clear"))
    #expect(source.contains(".accessibilityHint(isEmpty ? \"Empty folder\" : \"\")"))
  }

  @Test func folderRenameFieldUsesNeutralKeyboardFocusStyling() throws {
    let source = try folderNavigatorSource()
    let editor = try #require(
      source.components(separatedBy: "private func folderEditor(").last?
        .components(separatedBy: "private struct FolderRowFocusPublisher").first
    )

    #expect(editor.contains(".textFieldStyle(.plain)"))
    #expect(editor.contains(".focusEffectDisabled()"))
    #expect(editor.contains(".focused($focusedRow, equals: focus)"))
    #expect(editor.contains(".fleckNeutralControlOutline("))
    #expect(editor.contains("isFocused: focusedRow == focus"))
    #expect(editor.contains("idleOpacity: 0.22"))
    #expect(!editor.contains(".textFieldStyle(.roundedBorder)"))
    #expect(editor.contains(".onSubmit { commitFolderEditing() }"))
    #expect(editor.contains(".onExitCommand { cancelFolderEditing() }"))
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
    let diagnostics = FolderNavigatorNativeDiagnostics(
      testName: "compactRenameCreateAndDeleteRemeasureIntrinsicContent",
      window: fixture.window,
      fieldProvider: { fixture.newFolderFieldIfPresent() },
      contextProvider: { fixture.folderNavigatorDiagnosticContext() }
    )
    defer { diagnostics.finish() }

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
    let composerFocused = try await fixture.waitForNewFolderComposer(isPresent: true)
    try #require(composerFocused)
    await fixture.settle()
    diagnostics.attachCurrentField()
    try fixture.type("A newly created folder with a wider name")
    diagnostics.beginKeyDispatch(label: "Return", characters: "\r", keyCode: 36)
    try fixture.sendKey(characters: "\r", keyCode: 36)
    diagnostics.endKeyDispatch()
    let createdComposerDismissed = try await fixture.waitForNewFolderComposer(isPresent: false)
    if !createdComposerDismissed {
      fixture.printCreationFailureSnapshot(
        testName: "compactRenameCreateAndDeleteRemeasureIntrinsicContent",
        expectedName: "A newly created folder with a wider name"
      )
    }
    try #require(createdComposerDismissed)
    await fixture.settle()
    #expect(fixture.isVisible(label: "Reveal earlier folders"))
    let created = try #require(fixture.state.workspace.folders.last)
    try #require(created.name == "A newly created folder with a wider name")
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
    let diagnostics = FolderNavigatorNativeDiagnostics(
      testName: "composerFocusValidationCancellationAndCreationStayNative",
      window: fixture.window,
      fieldProvider: { fixture.newFolderFieldIfPresent() },
      contextProvider: { fixture.folderNavigatorDiagnosticContext() }
    )
    defer { diagnostics.finish() }
    let selectedNoteID = fixture.state.workspace.selectedNoteID
    let coveredUnfiledFrame = try fixture.frame(identifier: "folder-unfiled")

    try fixture.click(fixture.element(label: "New folder"))
    let initialComposerFocused = try await fixture.waitForNewFolderComposer(isPresent: true)
    try #require(initialComposerFocused)
    let field = try fixture.newFolderField()
    diagnostics.attachCurrentField()
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
    diagnostics.beginKeyDispatch(label: "Return", characters: "\r", keyCode: 36)
    try fixture.sendKey(characters: "\r", keyCode: 36)
    diagnostics.endKeyDispatch()
    await fixture.settle()
    #expect(fixture.state.workspace.folders.count == 2)
    #expect(try fixture.newFolderField().stringValue == "   ")

    try fixture.replaceDraft(with: "Work")
    diagnostics.beginKeyDispatch(label: "Return", characters: "\r", keyCode: 36)
    try fixture.sendKey(characters: "\r", keyCode: 36)
    diagnostics.endKeyDispatch()
    await fixture.settle()
    #expect(fixture.state.workspace.folders.count == 2)
    #expect(try fixture.newFolderField().stringValue == "Work")

    try fixture.click(fixture.element(identifier: "folder-new"))
    await fixture.settle()
    #expect(try fixture.newFolderField().stringValue == "Work")

    diagnostics.beginKeyDispatch(label: "Escape", characters: "\u{1b}", keyCode: 53)
    try fixture.sendKey(characters: "\u{1b}", keyCode: 53)
    diagnostics.endKeyDispatch()
    let escapedComposerDismissed = try await fixture.waitForNewFolderComposer(isPresent: false)
    try #require(escapedComposerDismissed)
    #expect(fixture.newFolderFieldIfPresent() == nil)

    try fixture.click(fixture.element(label: "New folder"))
    let reopenedComposerFocused = try await fixture.waitForNewFolderComposer(isPresent: true)
    try #require(reopenedComposerFocused)
    #expect(try fixture.newFolderField().stringValue.isEmpty)
    diagnostics.attachCurrentField()
    try fixture.type("Created")
    diagnostics.beginKeyDispatch(label: "Return", characters: "\r", keyCode: 36)
    try fixture.sendKey(characters: "\r", keyCode: 36)
    diagnostics.endKeyDispatch()
    let createdComposerDismissed = try await fixture.waitForNewFolderComposer(isPresent: false)
    if !createdComposerDismissed {
      fixture.printCreationFailureSnapshot(
        testName: "composerFocusValidationCancellationAndCreationStayNative",
        expectedName: "Created"
      )
    }
    try #require(createdComposerDismissed)
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
    let diagnostics = FolderNavigatorNativeDiagnostics(
      testName: "escapeCancelsComposerAfterFocusMovesToUncoveredRow",
      window: fixture.window,
      fieldProvider: { fixture.newFolderFieldIfPresent() },
      contextProvider: { fixture.folderNavigatorDiagnosticContext() }
    )
    defer { diagnostics.finish() }
    try fixture.click(fixture.element(label: "New folder"))
    await fixture.settle()
    diagnostics.attachCurrentField()
    try fixture.click(fixture.element(identifier: "folder-unfiled"))
    await fixture.settle()
    #expect(try fixture.newFolderField().currentEditor() == nil)

    diagnostics.beginKeyDispatch(label: "Escape", characters: "\u{1b}", keyCode: 53)
    try fixture.sendKey(characters: "\u{1b}", keyCode: 53)
    diagnostics.endKeyDispatch()
    await fixture.settle()
    let escapedComposerDismissed = try await fixture.waitForNewFolderComposer(isPresent: false)
    try #require(escapedComposerDismissed)
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
    let composerDismissed = try await fixture.waitForNewFolderComposer(isPresent: false)
    try #require(composerDismissed)
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

private struct FolderNavigatorDiagnosticContext {
  let folderNames: [String]
  let createButtonFound: Bool
  let createButtonEnabled: Bool?
  let saveError: String?
}

@MainActor
private final class FolderNavigatorComposerIdentity {
  weak var field: NSTextField?
  weak var editor: NSText?
  let fieldIdentity: String
  var editorIdentity: String?

  init(field: NSTextField, editor: NSText?, fieldIdentity: String, editorIdentity: String?) {
    self.field = field
    self.editor = editor
    self.fieldIdentity = fieldIdentity
    self.editorIdentity = editorIdentity
  }

  func matches(field: NSTextField?, editors: [NSText]) -> Bool {
    if let field, self.field === field { return true }
    guard let editor else { return false }
    return editors.contains { $0 === editor }
  }
}

private struct FolderNavigatorDiagnosticRecord: Encodable {
  let testName: String
  let phase: String
  let requestedKeyEvent: String?
  let commandSelector: String?
  let commandHandled: Bool?
  let delegateCommandSelectors: [String]
  let delegateCommandHandled: [Bool]
  let nativeNotification: String?
  let nativeNotificationSourceIdentity: String?
  let nativeNotificationComposerIdentities: [String]
  let nativeNotificationEditorIdentities: [String]
  let nativeNotifications: [String]
  let proxyInstalled: Bool
  let originalDelegateType: String?
  let originalSelectorAvailability: [String: Bool]
  let windowIdentity: String
  let windowIsKey: Bool
  let applicationIsActive: Bool
  let applicationKeyWindowMatches: Bool
  let firstResponderIdentity: String?
  let fieldIdentity: String?
  let fieldString: String?
  let editorIdentity: String?
  let editorString: String?
  let editorHasMarkedText: Bool?
  let markedRange: String?
  let markedText: String?
  let createButtonFound: Bool
  let createButtonEnabled: Bool?
  let folderNames: [String]
  let folderCount: Int
  let saveError: String?
  let detail: String?
}

@MainActor
private final class FolderNavigatorNativeDiagnostics: NSObject, NSTextFieldDelegate {
  private static let nativeNotificationNames = [
    NSControl.textDidBeginEditingNotification,
    NSControl.textDidChangeNotification,
    NSControl.textDidEndEditingNotification,
    NSText.didBeginEditingNotification,
    NSText.didChangeNotification,
    NSText.didEndEditingNotification,
  ]

  private static let requiredDelegateSelectors: [(String, Selector)] = [
    (
      "controlTextDidBeginEditing:",
      #selector(NSControlTextEditingDelegate.controlTextDidBeginEditing(_:))
    ),
    (
      "controlTextDidChange:",
      #selector(NSControlTextEditingDelegate.controlTextDidChange(_:))
    ),
    (
      "controlTextDidEndEditing:",
      #selector(NSControlTextEditingDelegate.controlTextDidEndEditing(_:))
    ),
    (
      "control:textView:doCommandBySelector:",
      #selector(NSControlTextEditingDelegate.control(_:textView:doCommandBy:))
    ),
  ]

  private let testName: String
  private let enabled: Bool
  private weak var window: NSWindow?
  private var fieldProvider: (@MainActor () -> NSTextField?)?
  private var contextProvider: (@MainActor () -> FolderNavigatorDiagnosticContext)?
  private weak var attachedField: NSTextField?
  nonisolated(unsafe) private weak var originalDelegate: NSTextFieldDelegate?
  private var originalDelegateType: String?
  private var originalSelectorAvailability: [String: Bool] = [:]
  private var trackedComposer: FolderNavigatorComposerIdentity?
  private var endingComposer: FolderNavigatorComposerIdentity?
  private var nativeNotifications: [String] = []
  private var delegateCommandSelectors: [String] = []
  private var delegateCommandHandled: [Bool] = []
  private var requestedKeyEvent: String?
  private var finished = false

  init(
    testName: String,
    window: NSWindow,
    fieldProvider: @escaping @MainActor () -> NSTextField?,
    contextProvider: @escaping @MainActor () -> FolderNavigatorDiagnosticContext
  ) {
    self.testName = testName
    enabled = ProcessInfo.processInfo.environment["FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC"] == "1"
    self.window = window
    self.fieldProvider = fieldProvider
    self.contextProvider = contextProvider
    super.init()

    guard enabled else { return }
    for name in Self.nativeNotificationNames {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(receiveNativeTextNotification(_:)),
        name: name,
        object: nil
      )
    }
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    guard let originalDelegate, originalDelegate.responds(to: selector) else {
      return super.forwardingTarget(for: selector)
    }
    return originalDelegate
  }

  func attachCurrentField() {
    guard enabled, let fieldProvider, let field = fieldProvider() else { return }
    rememberComposerIdentity(for: field)
    if attachedField === field {
      guard field.delegate === self else {
        appendRecord(phase: "proxy-unavailable", detail: "field delegate changed after proxy install")
        restoreAttachedDelegate()
        return
      }
      return
    }

    restoreAttachedDelegate()
    guard let delegate = field.delegate else {
      appendRecord(phase: "proxy-unavailable", detail: "native field delegate is nil")
      return
    }

    originalDelegateType = String(reflecting: type(of: delegate))
    originalSelectorAvailability = Dictionary(
      uniqueKeysWithValues: Self.requiredDelegateSelectors.map { name, selector in
        (name, delegate.responds(to: selector))
      }
    )
    let unavailableSelectors = originalSelectorAvailability.filter { !$0.value }.keys.sorted()
    guard unavailableSelectors.isEmpty else {
      appendRecord(
        phase: "proxy-unavailable",
        detail: "native delegate lacks selectors: \(unavailableSelectors.joined(separator: ", "))"
      )
      return
    }

    originalDelegate = delegate
    attachedField = field
    field.delegate = self
    guard field.delegate === self else {
      appendRecord(phase: "proxy-unavailable", detail: "native field rejected forwarding delegate")
      restoreAttachedDelegate()
      return
    }
    appendRecord(phase: "proxy-installed")
  }

  func beginKeyDispatch(label: String, characters: String, keyCode: UInt16) {
    guard enabled, !finished else { return }
    delegateCommandSelectors.removeAll()
    delegateCommandHandled.removeAll()
    requestedKeyEvent = "\(label); characters=\(characters); keyCode=\(keyCode)"
    attachCurrentField()
    appendRecord(phase: "before-dispatch")
  }

  func endKeyDispatch() {
    guard enabled, !finished else { return }
    appendRecord(phase: "after-dispatch")
    requestedKeyEvent = nil
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    forwardDelegateNotification("controlTextDidBeginEditing", notification: notification) {
      delegate, notification in
      delegate.controlTextDidBeginEditing?(notification)
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    forwardDelegateNotification("controlTextDidChange", notification: notification) {
      delegate, notification in
      delegate.controlTextDidChange?(notification)
    }
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    forwardDelegateNotification("controlTextDidEndEditing", notification: notification) {
      delegate, notification in
      delegate.controlTextDidEndEditing?(notification)
    }
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    let commandSelector = NSStringFromSelector(selector)
    delegateCommandSelectors.append(commandSelector)
    appendRecord(phase: "before-command-forward", commandSelector: commandSelector)
    let handled = originalDelegate?.control?(control, textView: textView, doCommandBy: selector)
      ?? false
    delegateCommandHandled.append(handled)
    appendRecord(
      phase: "after-command-forward",
      commandSelector: commandSelector,
      commandHandled: handled
    )
    return handled
  }

  func finish() {
    guard !finished else { return }
    finished = true
    appendRecord(phase: "test-finish")
    NotificationCenter.default.removeObserver(self)
    restoreAttachedDelegate()
    trackedComposer = nil
    endingComposer = nil
    fieldProvider = nil
    contextProvider = nil
  }

  @objc private func receiveNativeTextNotification(_ notification: Notification) {
    guard enabled else { return }
    let composers = composerIdentities(for: notification)
    guard !composers.isEmpty else { return }
    let name = notification.name.rawValue
    nativeNotifications.append(name)
    let editorSources = [
      notification.object as? NSText,
      notification.userInfo?["NSFieldEditor"] as? NSText,
    ].compactMap { $0 }
    appendRecord(
      phase: "native-notification",
      nativeNotification: name,
      nativeNotificationSourceIdentity: (notification.object as? NSObject).map {
        Self.identity(of: $0)
      },
      nativeNotificationComposerIdentities: Array(Set(composers.map(\.fieldIdentity))).sorted(),
      nativeNotificationEditorIdentities: Array(
        Set(
          composers.compactMap(\.editorIdentity)
            + editorSources.map { Self.identity(of: $0) }
        )
      ).sorted()
    )
  }

  private func composerIdentities(for notification: Notification)
    -> [FolderNavigatorComposerIdentity]
  {
    let sourceField = notification.object as? NSTextField
    let sourceEditors = [
      notification.object as? NSText,
      notification.userInfo?["NSFieldEditor"] as? NSText,
    ].compactMap { $0 }
    let trackedComposers = [endingComposer, trackedComposer].compactMap { $0 }
    let matchingField = trackedComposers.filter {
      $0.matches(field: sourceField, editors: [])
    }
    if !matchingField.isEmpty { return matchingField }

    let matchingEditor = trackedComposers.filter {
      $0.matches(field: nil, editors: sourceEditors)
    }
    guard let field = fieldProvider?() else { return matchingEditor }
    if sourceField === field {
      rememberComposerIdentity(for: field)
      return trackedComposer.map { [$0] } ?? []
    }
    guard let editor = field.currentEditor(), sourceEditors.contains(where: { $0 === editor }) else {
      return matchingEditor
    }

    rememberComposerIdentity(for: field)
    return [endingComposer, trackedComposer].compactMap { $0 }.filter {
      $0.matches(field: nil, editors: sourceEditors)
    }
  }

  private func rememberComposerIdentity(for field: NSTextField) {
    let editor = field.currentEditor()
    let identity = FolderNavigatorComposerIdentity(
      field: field,
      editor: editor,
      fieldIdentity: Self.identity(of: field),
      editorIdentity: editor.map { Self.identity(of: $0) }
    )
    if let trackedComposer, trackedComposer.field === field {
      guard let editor, editor !== trackedComposer.editor else { return }
      if trackedComposer.editor != nil {
        endingComposer = trackedComposer
      }
      self.trackedComposer = identity
      return
    }
    if let trackedComposer { endingComposer = trackedComposer }
    trackedComposer = identity
  }

  private static func identity(of object: AnyObject) -> String {
    "\(String(reflecting: type(of: object)))#\(ObjectIdentifier(object))"
  }

  private func forwardDelegateNotification(
    _ name: String,
    notification: Notification,
    forward: (NSTextFieldDelegate, Notification) -> Void
  ) {
    appendRecord(phase: "before-\(name)-forward")
    if let originalDelegate {
      forward(originalDelegate, notification)
    }
    appendRecord(phase: "after-\(name)-forward")
  }

  private func appendRecord(
    phase: String,
    commandSelector: String? = nil,
    commandHandled: Bool? = nil,
    nativeNotification: String? = nil,
    nativeNotificationSourceIdentity: String? = nil,
    nativeNotificationComposerIdentities: [String] = [],
    nativeNotificationEditorIdentities: [String] = [],
    detail: String? = nil
  ) {
    guard enabled, let window, let contextProvider else { return }
    let field = nativeNotification == nil ? fieldProvider?() : nil
    let editor = field?.currentEditor() as? NSTextView
    let markedRange = editor.flatMap { $0.hasMarkedText() ? $0.markedRange() : nil }
    let markedText: String?
    if let editor, let markedRange,
      markedRange.location != NSNotFound,
      NSMaxRange(markedRange) <= editor.string.utf16.count
    {
      markedText = (editor.string as NSString).substring(with: markedRange)
    } else {
      markedText = nil
    }
    let context = contextProvider()
    let firstResponder = window.firstResponder.map {
      "\(String(reflecting: type(of: $0)))#\(ObjectIdentifier($0))"
    }
    let record = FolderNavigatorDiagnosticRecord(
      testName: testName,
      phase: phase,
      requestedKeyEvent: requestedKeyEvent,
      commandSelector: commandSelector,
      commandHandled: commandHandled,
      delegateCommandSelectors: delegateCommandSelectors,
      delegateCommandHandled: delegateCommandHandled,
      nativeNotification: nativeNotification,
      nativeNotificationSourceIdentity: nativeNotificationSourceIdentity,
      nativeNotificationComposerIdentities: nativeNotificationComposerIdentities,
      nativeNotificationEditorIdentities: nativeNotificationEditorIdentities,
      nativeNotifications: nativeNotifications,
      proxyInstalled: attachedField?.delegate === self,
      originalDelegateType: originalDelegateType,
      originalSelectorAvailability: originalSelectorAvailability,
      windowIdentity: "\(String(reflecting: type(of: window)))#\(ObjectIdentifier(window))",
      windowIsKey: window.isKeyWindow,
      applicationIsActive: NSApp.isActive,
      applicationKeyWindowMatches: NSApp.keyWindow === window,
      firstResponderIdentity: firstResponder,
      fieldIdentity: field.map { "\(String(reflecting: type(of: $0)))#\(ObjectIdentifier($0))" },
      fieldString: field?.stringValue,
      editorIdentity: editor.map { "\(String(reflecting: type(of: $0)))#\(ObjectIdentifier($0))" },
      editorString: editor?.string,
      editorHasMarkedText: editor?.hasMarkedText(),
      markedRange: markedRange.map { "\($0.location):\($0.length)" },
      markedText: markedText,
      createButtonFound: context.createButtonFound,
      createButtonEnabled: context.createButtonEnabled,
      folderNames: context.folderNames,
      folderCount: context.folderNames.count,
      saveError: context.saveError,
      detail: detail
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(record),
      let line = String(data: data, encoding: .utf8)
    else { return }
    print("FLECK_FOLDER_NAVIGATOR_DIAGNOSTIC \(line)")
  }

  private func restoreAttachedDelegate() {
    if let attachedField, attachedField.delegate === self {
      attachedField.delegate = originalDelegate
    }
    attachedField = nil
    originalDelegate = nil
    originalDelegateType = nil
    originalSelectorAvailability = [:]
  }
}

@MainActor
private final class FolderNavigatorFixture {
  private static var nextMouseEventNumber = 1

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
    let timestamp = ProcessInfo.processInfo.systemUptime
    let mouseDownEventNumber = Self.nextMouseEventNumber
    Self.nextMouseEventNumber += 1
    let mouseUpEventNumber = Self.nextMouseEventNumber
    Self.nextMouseEventNumber += 1
    let mouseDown = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: location,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: mouseDownEventNumber,
        clickCount: 1,
        pressure: 1
      ))
    let mouseUp = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: location,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: mouseUpEventNumber,
        clickCount: 1,
        pressure: 0
      ))
    window.postEvent(mouseUp, atStart: true)
    window.sendEvent(mouseDown)
  }

  func newFolderFieldIfPresent() -> NSTextField? {
    textFields.first { $0.placeholderString == "New folder" }
  }

  func folderNavigatorDiagnosticContext() -> FolderNavigatorDiagnosticContext {
    let createButton = elementIfPresent(label: "Create folder")
    let createButtonEnabled: Bool?
    if let accessible = createButton as? NSAccessibilityProtocol {
      createButtonEnabled = accessible.isAccessibilityEnabled()
    } else if let control = createButton as? NSControl {
      createButtonEnabled = control.isEnabled
    } else {
      createButtonEnabled = nil
    }
    return FolderNavigatorDiagnosticContext(
      folderNames: state.workspace.folders.map(\.name),
      createButtonFound: createButton != nil,
      createButtonEnabled: createButtonEnabled,
      saveError: state.saveError
    )
  }

  func printCreationFailureSnapshot(testName: String, expectedName: String) {
    let folderNames = state.workspace.folders.map(\.name)
    let saveError = state.saveError
    let identity: (AnyObject) -> String = {
      "\(String(reflecting: type(of: $0)))#\(ObjectIdentifier($0))"
    }
    let rawFields: [[String: Any]] = textFields
      .filter { $0.placeholderString == "New folder" }
      .map { field in
        let fieldWindow = field.window
        let parent = field.superview
        let editor = field.currentEditor()
        let editorView = editor as? NSTextView
        let editorString = editor?.string
        let markedRange = editorView.flatMap { $0.hasMarkedText() ? $0.markedRange() : nil }
        var hiddenAncestor = parent
        while let ancestor = hiddenAncestor, !ancestor.isHidden {
          hiddenAncestor = ancestor.superview
        }
        let markedText: String?
        if let editorString, let markedRange,
          markedRange.location != NSNotFound,
          NSMaxRange(markedRange) <= editorString.utf16.count
        {
          markedText = (editorString as NSString).substring(with: markedRange)
        } else {
          markedText = nil
        }
        return [
          "fieldIdentity": identity(field),
          "windowPresent": fieldWindow != nil,
          "windowIdentity": fieldWindow.map { identity($0) as Any } ?? NSNull(),
          "parentPresent": parent != nil,
          "parentIdentity": parent.map { identity($0) as Any } ?? NSNull(),
          "isHidden": field.isHidden,
          "hiddenAncestorIdentity": hiddenAncestor.map { identity($0) as Any } ?? NSNull(),
          "nativeString": field.stringValue,
          "editorIdentity": editor.map { identity($0) as Any } ?? NSNull(),
          "editorString": editorString.map { $0 as Any } ?? NSNull(),
          "editorHasMarkedText": editorView.map { $0.hasMarkedText() as Any } ?? NSNull(),
          "markedRange": markedRange.map { "\($0.location):\($0.length)" as Any } ?? NSNull(),
          "markedText": markedText.map { $0 as Any } ?? NSNull(),
        ]
      }
    let firstResponder = window.firstResponder
    let applicationKeyWindow = NSApp.keyWindow
    let fixtureWindowIdentity = identity(window)
    let fixtureWindowIsKey = window.isKeyWindow
    let applicationKeyWindowIdentity = applicationKeyWindow.map { identity($0) }
    let applicationIsActive = NSApp.isActive
    let firstResponderIdentity = firstResponder.map { identity($0) }
    let createFolderPresent = elementIfPresent(label: "Create folder") != nil
    let cancelNewFolderPresent = elementIfPresent(label: "Cancel new folder") != nil
    let folderNewNamePresent = elementIfPresent(identifier: "folder-new-name") != nil
    let snapshot: [String: Any] = [
      "testName": testName,
      "expectedName": expectedName,
      "workspaceFolderNames": folderNames,
      "workspaceFolderCount": folderNames.count,
      "saveError": saveError.map { $0 as Any } ?? NSNull(),
      "rawNewFolderFields": rawFields,
      "fixtureWindowIdentity": fixtureWindowIdentity,
      "fixtureWindowIsKey": fixtureWindowIsKey,
      "applicationKeyWindowIdentity": applicationKeyWindowIdentity.map { $0 as Any }
        ?? NSNull(),
      "applicationKeyWindowMatchesFixture": applicationKeyWindow === window,
      "applicationIsActive": applicationIsActive,
      "firstResponderIdentity": firstResponderIdentity.map { $0 as Any } ?? NSNull(),
      "publicAX": [
        "createFolderPresent": createFolderPresent,
        "cancelNewFolderPresent": cancelNewFolderPresent,
        "folderNewNamePresent": folderNewNamePresent,
      ],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
      let line = String(data: data, encoding: .utf8)
    else { return }
    print("FLECK_FOLDER_CREATION_FAILURE_DIAGNOSTIC \(line)")
  }

  func waitForNewFolderComposer(isPresent: Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))

    func stateMatches() -> Bool {
      guard let field = newFolderFieldIfPresent() else {
        return !isPresent
          && elementIfPresent(label: "Create folder") == nil
          && elementIfPresent(label: "Cancel new folder") == nil
      }
      guard isPresent else { return false }
      guard
        field.window === window,
        let editor = field.currentEditor(),
        editor === window.firstResponder,
        window.isKeyWindow,
        NSApp.keyWindow === window,
        NSApp.isActive
      else { return false }
      return true
    }

    while clock.now < deadline {
      try Task.checkCancellation()
      host.layoutSubtreeIfNeeded()
      if stateMatches(), clock.now < deadline { return true }
      let remaining = clock.now.duration(to: deadline)
      guard remaining > .zero else { break }
      try await Task.sleep(for: min(.milliseconds(25), remaining))
    }

    try Task.checkCancellation()
    return false
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
