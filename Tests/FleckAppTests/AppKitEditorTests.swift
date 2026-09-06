import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@MainActor private final class EditorChangeDelegate: NSObject, NSTextViewDelegate {
  var changeCount = 0

  func textDidChange(_ notification: Notification) {
    changeCount += 1
  }
}

@Test @MainActor func pasteOptionTitlesMatchWordOrder() {
  #expect(
    PasteOption.allCases.map(\.title) == [
      "Keep Source Formatting",
      "Paste Text Only",
      "Merge Formatting"
    ]
  )
}

@Test @MainActor func pasteTextOnlyUsesDestinationAttributes() throws {
  let font = NSFont.systemFont(ofSize: 18)
  let color = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
  let destinationLink = URL(string: "https://example.com/destination")!
  let pasted = ListAwareTextView.pasteTextOnly(
    "Plain",
    destinationAttributes: [
      .font: font,
      .foregroundColor: color,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .link: destinationLink
    ]
  )

  #expect(pasted.string == "Plain")
  #expect((pasted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == font)
  #expect(
    (pasted.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
      == color
  )
  #expect(
    pasted.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(pasted.attribute(.link, at: 0, effectiveRange: nil) as? URL == destinationLink)
}

@Test @MainActor func mergePasteKeepsSemanticAttributesAndDestinationTypography() throws {
  let sourceFont = NSFontManager.shared.convert(
    NSFontManager.shared.convert(
      NSFont.systemFont(ofSize: 13),
      toHaveTrait: .boldFontMask
    ),
    toHaveTrait: .italicFontMask
  )
  let sourceUnderlineColor = NSColor.systemRed
  let sourceStrikethroughColor = NSColor.systemBlue
  let destinationUnderlineColor = NSColor.systemGreen
  let destinationStrikethroughColor = NSColor.systemPurple
  let source = NSMutableAttributedString(
    string: "Link",
    attributes: [
      .font: sourceFont,
      .foregroundColor: NSColor.systemRed,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: sourceUnderlineColor,
      .strikethroughStyle: NSUnderlineStyle.single.rawValue,
      .strikethroughColor: sourceStrikethroughColor,
      .link: URL(string: "https://example.com")!
    ]
  )
  let destinationFont = NSFont.systemFont(ofSize: 19)
  let destinationColor = NSColor.systemBlue
  let destinationBackground = NSColor.systemYellow
  let paragraphStyle = NSMutableParagraphStyle()
  paragraphStyle.alignment = .right
  let merged = ListAwareTextView.mergePaste(
    source,
    destinationAttributes: [
      .font: destinationFont,
      .foregroundColor: destinationColor,
      .backgroundColor: destinationBackground,
      .underlineColor: destinationUnderlineColor,
      .strikethroughColor: destinationStrikethroughColor,
      .paragraphStyle: paragraphStyle
    ]
  )

  let mergedFont = try #require(merged.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(mergedFont.pointSize == destinationFont.pointSize)
  #expect(NSFontManager.shared.traits(of: mergedFont).contains(.boldFontMask))
  #expect(NSFontManager.shared.traits(of: mergedFont).contains(.italicFontMask))
  #expect((merged.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == destinationColor)
  #expect((merged.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor) == destinationBackground)
  #expect(
    (merged.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment
      == .right
  )
  #expect(
    merged.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (merged.attribute(.underlineColor, at: 0, effectiveRange: nil) as? NSColor)
      == destinationUnderlineColor
  )
  #expect(
    merged.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (merged.attribute(.strikethroughColor, at: 0, effectiveRange: nil) as? NSColor)
      == destinationStrikethroughColor
  )
  #expect(merged.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com")!)
}

@Test @MainActor func plainPasteShowsOptionsAndEscapeDismissesThem() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  contentView.addSubview(textView)
  let otherResponder = NSButton(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
  contentView.addSubview(otherResponder)
  window.contentView = contentView
  textView.allowsUndo = true
  #expect(window.makeFirstResponder(textView))
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  textView.insertPastedTextForTesting(
    NSAttributedString(string: "Pasted"),
    plainText: "Pasted",
    hasRichFormatting: false
  )

  #expect(textView.string == "Pasted")
  #expect(textView.hasPasteOptions)
  #expect(textView.pasteOptionMenuTitles == PasteOption.allCases.map(\.title))
  #expect(textView.pasteOptionEnabledStates == [true, false, false])
  textView.cancelOperation(nil)
  #expect(!textView.hasPasteOptions)

  textView.insertPastedTextForTesting(
    NSAttributedString(string: "Again"),
    plainText: "Again",
    hasRichFormatting: false
  )
  #expect(textView.hasPasteOptions)
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  #expect(!textView.hasPasteOptions)

  textView.insertPastedTextForTesting(
    NSAttributedString(string: "Once more"),
    plainText: "Once more",
    hasRichFormatting: false
  )
  #expect(textView.hasPasteOptions)
  #expect(window.makeFirstResponder(otherResponder))
  #expect(!textView.hasPasteOptions)

  textView.insertPastedTextForTesting(
    NSAttributedString(string: "Teardown"),
    plainText: "Teardown",
    hasRichFormatting: false
  )
  #expect(textView.hasPasteOptions)
  textView.viewWillMove(toWindow: nil)
  #expect(!textView.hasPasteOptions)
}

@Test @MainActor func identicalPasteStillShowsPasteOptions() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "Same"
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  let source = textView.textStorage?.attributedSubstring(
    from: NSRange(location: 0, length: textView.string.utf16.count)
  ) ?? NSAttributedString(string: "Same")

  textView.insertPastedTextForTesting(
    source,
    plainText: source.string,
    hasRichFormatting: true
  )

  #expect(textView.string == "Same")
  #expect(textView.hasPasteOptions)
}

@Test @MainActor func pasteOptionsDismissWhenNativeSelectionMoves() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  #expect(window.makeFirstResponder(textView))

  textView.insertPastedTextForTesting(NSAttributedString(string: "Pasted"))
  #expect(textView.hasPasteOptions)
  let pastedEnd = textView.selectedRange()

  textView.moveLeft(nil)

  #expect(textView.selectedRange() != pastedEnd)
  #expect(!textView.hasPasteOptions)
}

@MainActor private func pasteOptionsDismissOnWindowAndApplicationFocusNotificationsImpl() async {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.viewDidMoveToWindow()
  #expect(window.makeFirstResponder(textView))

  textView.insertPastedTextForTesting(NSAttributedString(string: "Window"))
  #expect(textView.hasPasteOptions)
  NotificationCenter.default.post(
    name: NSWindow.didResignKeyNotification,
    object: window
  )
  await Task.yield()
  #expect(!textView.hasPasteOptions)

  textView.insertPastedTextForTesting(NSAttributedString(string: "Application"))
  #expect(textView.hasPasteOptions)
  NotificationCenter.default.post(
    name: NSApplication.didResignActiveNotification,
    object: NSApplication.shared
  )
  await Task.yield()
  #expect(!textView.hasPasteOptions)
}

@Test @MainActor func pasteOptionsDismissOnSameWindowOutsideClick() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 160))
  let background = NSView(frame: NSRect(x: 220, y: 0, width: 100, height: 160))
  let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  contentView.addSubview(textView)
  contentView.addSubview(background)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = contentView
  window.makeKeyAndOrderFront(nil)
  defer { window.orderOut(nil) }
  textView.viewDidMoveToWindow()
  #expect(window.makeFirstResponder(textView))

  textView.insertPastedTextForTesting(NSAttributedString(string: "Pasted"))
  #expect(textView.hasPasteOptions)

  let location = background.convert(NSPoint(x: 20, y: 20), to: nil)
  let mouseDown = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    )
  )
  let mouseUp = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 0
    )
  )
  NSApplication.shared.sendEvent(mouseDown)
  NSApplication.shared.sendEvent(mouseUp)

  #expect(window.firstResponder === textView)
  #expect(!textView.hasPasteOptions)
}

@Test @MainActor func pasteOptionsDismissOnNonactivatingWindowClick() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 160))
  let editorWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  editorWindow.contentView = textView
  editorWindow.makeKeyAndOrderFront(nil)
  defer { editorWindow.orderOut(nil) }
  textView.viewDidMoveToWindow()
  #expect(editorWindow.makeFirstResponder(textView))
  textView.insertPastedTextForTesting(NSAttributedString(string: "Pasted"))
  #expect(textView.hasPasteOptions)

  let panel = NSPanel(
    contentRect: NSRect(x: 260, y: 0, width: 120, height: 80),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
  )
  panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
  panel.orderFrontRegardless()
  defer { panel.orderOut(nil) }

  let location = NSPoint(x: textView.bounds.maxX + 20, y: textView.bounds.midY)
  let panelWindowNumber = panel.windowNumber == editorWindow.windowNumber
    ? editorWindow.windowNumber + 1
    : panel.windowNumber
  let mouseDown = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: panelWindowNumber,
      context: nil,
      eventNumber: 2,
      clickCount: 1,
      pressure: 1
    )
  )
  NSApplication.shared.sendEvent(mouseDown)

  #expect(!textView.hasPasteOptions)
}

@Test @MainActor func attachmentPasteKeepsNativeOptionEnabledOnly() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  let attachment = NSTextAttachment()
  textView.insertPastedTextForTesting(
    NSAttributedString(attachment: attachment),
    plainText: "\u{FFFC}",
    hasRichFormatting: true
  )

  #expect(textView.hasPasteOptions)
  #expect(textView.pasteOptionEnabledStates == [true, false, false])
}

@MainActor private func selectingPasteTextOnlyReplacesOnlyLatestPasteAndUndoRestoresItImpl() async throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  #expect(window.makeFirstResponder(textView))
  textView.string = "Before"
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  let sourceFont = NSFontManager.shared.convert(
    NSFont.systemFont(ofSize: 13),
    toHaveTrait: .italicFontMask
  )
  let source = NSAttributedString(
    string: " Pasted",
    attributes: [.font: sourceFont, .foregroundColor: NSColor.systemRed]
  )
  let changeDelegate = EditorChangeDelegate()
  textView.delegate = changeDelegate
  textView.insertPastedTextForTesting(
    source,
    plainText: source.string,
    hasRichFormatting: true
  )
  #expect(textView.string == "Before Pasted")
  #expect(textView.hasPasteOptions)
  #expect(textView.pasteOptionEnabledStates == [true, true, true])
  #expect(
    NSFontManager.shared.traits(
      of: try #require(textView.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
    ).contains(.italicFontMask)
  )
  let changesBeforeOption = changeDelegate.changeCount

  await Task.yield()
  textView.applyPasteOption(.pasteTextOnly)
  #expect(textView.string == "Before Pasted")
  #expect(
    NSFontManager.shared.traits(
      of: try #require(textView.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
    ).contains(.italicFontMask) == false
  )
  #expect(changeDelegate.changeCount > changesBeforeOption)
  #expect(!textView.hasPasteOptions)

  await Task.yield()
  try #require(textView.undoManager).undo()
  #expect(textView.string == "Before Pasted")
  #expect(
    NSFontManager.shared.traits(
      of: try #require(textView.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
    ).contains(.italicFontMask)
  )
}

@Suite(.serialized)
struct PasteOptionsGlobalFocusTests {
  @Test @MainActor func pasteOptionsDismissOnWindowAndApplicationFocusNotifications() async {
    await pasteOptionsDismissOnWindowAndApplicationFocusNotificationsImpl()
  }

  @Test @MainActor func selectingPasteTextOnlyReplacesOnlyLatestPasteAndUndoRestoresIt() async throws {
    try await selectingPasteTextOnlyReplacesOnlyLatestPasteAndUndoRestoresItImpl()
  }
}

@Test @MainActor func listFormattingPreservesInlineAttributes() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "One two"
  textView.textStorage?.addAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 4, length: 3)
  )
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

  textView.toggleList(.bullet(.disc))

  #expect(textView.string == "• One two")
  #expect(
    textView.textStorage?.attribute(
      .underlineStyle,
      at: 6,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func deletingEmptyChecklistPrefixRemovesMarkerAndSeparatorAtomically() async throws {
  let textView = ListAwareTextView(frame: .zero)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = "○ x"
  textView.setSelectedRange(NSRange(location: 3, length: 0))

  textView.deleteBackward(nil)

  #expect(textView.string == "○ ")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  await Task.yield()

  textView.deleteBackward(nil)

  #expect(textView.string == "")
  #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

  try #require(textView.undoManager).undo()

  #expect(textView.string == "○ ")

  textView.string = "    ● \n"
  textView.setSelectedRange(NSRange(location: 6, length: 0))

  textView.deleteBackward(nil)

  #expect(textView.string == "    \n")
  #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
}

@Test @MainActor func appKitLinkPresentationDoesNotWriteLinkAttributes() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
  textView.string = "Before \(token) after"
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  let link = try #require(NoteLinkParser.links(in: textView.string).first)

  #expect(textView.textStorage?.attribute(.link, at: link.range.location, effectiveRange: nil) == nil)
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: link.range.location,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
  #expect(textView.string == "Before \(token) after")
}

@Test @MainActor func nativeEditorDismantleRemovesOnlyItsTextSystemUndoActions() throws {
  let commands = EditorCommands()
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  let scrollView = NSScrollView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = scrollView
  scrollView.documentView = NativeEditorDocumentView(
    titleField: NSTextField(),
    textView: textView
  )
  textView.allowsUndo = true

  let undoManager = try #require(textView.undoManager)
  let storage = try #require(textView.textStorage)
  undoManager.removeAllActions()
  var dismantledTextViewActionInvoked = false
  var dismantledStorageActionInvoked = false
  var unrelatedActionInvoked = false
  let unrelatedTarget = NSObject()
  undoManager.registerUndo(withTarget: textView) { _ in
    dismantledTextViewActionInvoked = true
  }
  undoManager.registerUndo(withTarget: storage) { _ in
    dismantledStorageActionInvoked = true
  }
  undoManager.registerUndo(withTarget: unrelatedTarget) { _ in
    unrelatedActionInvoked = true
  }

  let delegate = EditorDelegateProbe()
  textView.delegate = delegate
  textView.onRequestNoteLink = { _ in }
  textView.onOpenNoteLink = { _ in }
  textView.onUnavailableNoteLink = {}
  commands.textView = textView
  let editor = NativeRichTextEditor(
    text: "",
    richTextRTF: nil,
    onChange: { _, _ in },
    fontFamily: "Helvetica",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#FFD600",
    reduceMotion: false,
    automaticLists: true,
    commands: commands
  )

  NativeRichTextEditor.dismantleNSView(
    scrollView,
    coordinator: editor.makeCoordinator()
  )

  #expect(commands.textView == nil)
  #expect(textView.delegate == nil)
  #expect(textView.onRequestNoteLink == nil)
  #expect(textView.onOpenNoteLink == nil)
  #expect(textView.onUnavailableNoteLink == nil)
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(unrelatedActionInvoked)
  #expect(!undoManager.canUndo)
  #expect(!dismantledTextViewActionInvoked)
  #expect(!dismantledStorageActionInvoked)
}

@MainActor
private final class EditorDelegateProbe: NSObject, NSTextViewDelegate {}

@Test @MainActor func checklistCompletionUndoRestoresMarkerAndStrikethrough() throws {
  let textView = ListAwareTextView(frame: .zero)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = "○ Task"
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  _ = try #require(textView.accessibilityCustomActions()?.first)

  #expect(textView.toggleSelectedChecklist())
  #expect(textView.string == "● Task")
  #expect(textView.checklistCompletionOverlayCount == 1)
  let overlay = try #require(
    textView.subviews.compactMap { $0 as? ChecklistCompletionOverlay }.first
  )
  #expect(abs(CGFloat(overlay.layer?.opacity ?? 0) - 1) < 0.001)
  #expect(
    textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )

  let undoManager = try #require(textView.undoManager)
  #expect(undoManager.canUndo)
  undoManager.undo()

  #expect(textView.string == "○ Task")
  #expect(textView.checklistCompletionOverlayCount == 0)
  #expect(
    (textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int ?? 0) == 0
  )
}

@Test @MainActor func reduceMotionSkipsChecklistCompletionOverlay() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "○ Task"
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.reduceMotion = true

  #expect(textView.toggleSelectedChecklist())
  #expect(textView.string == "● Task")
  #expect(textView.checklistCompletionOverlayCount == 0)
}

@Test @MainActor func emptyChecklistCompletionOverlayUsesEmptyItemOpacity() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "○ "
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.reduceMotion = false

  #expect(textView.toggleSelectedChecklist())
  let overlay = try #require(
    textView.subviews.compactMap { $0 as? ChecklistCompletionOverlay }.first
  )
  #expect(
    abs(
      CGFloat(overlay.layer?.opacity ?? 0)
        - ChecklistMarkerDrawing.emptyListMarkerOpacity
    ) < 0.001
  )
}

@Test @MainActor func rapidChecklistToggleDoesNotLeaveStaleOverlay() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "○ Task"
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.reduceMotion = false

  #expect(textView.toggleSelectedChecklist())
  #expect(textView.checklistCompletionOverlayCount <= 1)
  #expect(textView.toggleSelectedChecklist())
  #expect(textView.checklistCompletionOverlayCount == 0)
}

@Test @MainActor func returnInsideCompletedChecklistClearsNewItemFormatting() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "● Task"
  textView.textStorage?.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 2, length: 4)
  )
  textView.setSelectedRange(NSRange(location: 4, length: 0))

  textView.insertNewline(nil)

  #expect(textView.string == "● Ta\n○ sk")
  #expect(
    textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 7,
      effectiveRange: nil
    ) as? Int ?? 0) == 0
  )
}

@Test @MainActor func listEditingRenumbersAdjacentNumberedSiblings() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "1. A\n2. B\n3. C"
  textView.setSelectedRange(NSRange(location: 4, length: 0))

  textView.insertNewline(nil)

  #expect(textView.string == "1. A\n2. \n3. B\n4. C")

  textView.string = "1. A\n2. B\n3. C"
  textView.setSelectedRange(NSRange(location: 5, length: 4))
  textView.insertTab(nil)

  #expect(textView.string == "1. A\n    a. B\n2. C")
}

@Test @MainActor func depthZeroBacktabIsAUiNoOp() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "5. Unchanged"
  textView.setSelectedRange(NSRange(location: 3, length: 0))

  textView.insertBacktab(nil)

  #expect(textView.string == "5. Unchanged")
}

@Test @MainActor func renumberingDoesNotRewriteUnrelatedLists() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "1. A\n2. B\nPlain\n8. Separate\n9. List"
  textView.setSelectedRange(NSRange(location: 4, length: 0))

  textView.insertNewline(nil)

  #expect(textView.string == "1. A\n2. \n3. B\nPlain\n8. Separate\n9. List")
}

@Test @MainActor func manualNumberStyleHintDisambiguatesAlphabeticAndRoman() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = (1...9).map { "Item \($0)" }.joined(separator: "\n")
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  textView.toggleList(.number(.alphabetic))
  let restoredAlphabetic = rtfRoundTrip(textView)
  let alphabeticEnd =
    (restoredAlphabetic.string as NSString).range(of: "i. Item 9").upperBound
  restoredAlphabetic.setSelectedRange(NSRange(location: alphabeticEnd, length: 0))

  restoredAlphabetic.insertNewline(nil)

  #expect(restoredAlphabetic.string.hasSuffix("i. Item 9\nj. "))

  textView.string = "    Roman"
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  textView.toggleList(.number(.roman))
  let restoredRoman = rtfRoundTrip(textView)
  restoredRoman.setSelectedRange(
    NSRange(location: restoredRoman.string.utf16.count, length: 0)
  )
  restoredRoman.insertNewline(nil)

  #expect(restoredRoman.string == "    i. Roman\n    ii. ")
}

@Test @MainActor func returnAndRenumberUndoAsOneAction() throws {
  let textView = ListAwareTextView(frame: .zero)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = "1. A\n2. B"
  textView.setSelectedRange(NSRange(location: 4, length: 0))

  textView.insertNewline(nil)
  try #require(textView.undoManager).undo()

  #expect(textView.string == "1. A\n2. B")
}

@Test @MainActor func completedChecklistReturnUndoRestoresSuffixFormatting() throws {
  let textView = ListAwareTextView(frame: .zero)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = "● Task"
  textView.textStorage?.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 2, length: 4)
  )
  textView.setSelectedRange(NSRange(location: 4, length: 0))

  textView.insertNewline(nil)
  try #require(textView.undoManager).undo()

  #expect(textView.string == "● Task")
  #expect(
    textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 4,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func checklistHitRectContainsItsRenderedMarker() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.font = .systemFont(ofSize: 11)
  textView.string = "○ Task"
  textView.layoutManager?.ensureLayout(for: try #require(textView.textContainer))

  let markerRange = NSRange(location: 0, length: 1)
  let markerRect = try #require(textView.checklistMarkerRect(for: markerRange))
  let hitRect = try #require(textView.checklistHitRect(for: markerRange))
  let layoutManager = try #require(textView.layoutManager)
  let textContainer = try #require(textView.textContainer)
  let slotGlyphRange = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 0, length: 2),
    actualCharacterRange: nil
  )
  let slotRect = layoutManager.boundingRect(
    forGlyphRange: slotGlyphRange,
    in: textContainer
  ).offsetBy(
    dx: textView.textContainerOrigin.x,
    dy: textView.textContainerOrigin.y
  )
  let contentGlyphRange = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 2, length: 1),
    actualCharacterRange: nil
  )
  let contentRect = layoutManager.boundingRect(
    forGlyphRange: contentGlyphRange,
    in: textContainer
  ).offsetBy(
    dx: textView.textContainerOrigin.x,
    dy: textView.textContainerOrigin.y
  )
  let expectedX = min(
    slotRect.midX - 8,
    slotRect.maxX - ChecklistMarkerDrawing.markerDiameter
      - ChecklistMarkerDrawing.minimumContentGap
  )

  #expect(markerRect.size == CGSize(width: 16, height: 16))
  #expect(abs(markerRect.minX - expectedX) < 0.01)
  if slotRect.width >= ChecklistMarkerDrawing.markerDiameter
    + 2 * ChecklistMarkerDrawing.minimumContentGap
  {
    #expect(abs(markerRect.midX - slotRect.midX) < 0.01)
  } else {
    #expect(
      abs(
        markerRect.maxX
          - (slotRect.maxX - ChecklistMarkerDrawing.minimumContentGap)
      ) < 0.01
    )
  }
  #expect(hitRect.contains(markerRect))
  #expect(hitRect.width > markerRect.width)
  #expect(hitRect.height > markerRect.height)
  #expect(hitRect.width >= 28)
  #expect(hitRect.height >= 28)
  #expect(abs(hitRect.maxX - markerRect.maxX) < 0.01)
  #expect(markerRect.maxX <= contentRect.minX)
  #expect(hitRect.maxX <= contentRect.minX)
}

@Test @MainActor func checklistMarkerLeavesMinimumGapBeforeFirstContentGlyph() throws {
  for fontSize in [CGFloat(11), CGFloat(14)] {
    for text in ["○ d", "○ 1"] {
      let textView = ListAwareTextView(
        frame: NSRect(x: 0, y: 0, width: 320, height: 160)
      )
      textView.textContainerInset = NSSize(width: 16, height: 10)
      textView.textContainer?.lineFragmentPadding = 0
      textView.font = .systemFont(ofSize: fontSize)
      textView.string = text

      let textContainer = try #require(textView.textContainer)
      let layoutManager = try #require(textView.layoutManager)
      layoutManager.ensureLayout(for: textContainer)

      let markerRect = try #require(
        textView.checklistMarkerRect(for: NSRange(location: 0, length: 1))
      )
      let contentGlyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: 2, length: 1),
        actualCharacterRange: nil
      )
      let contentRect = layoutManager.boundingRect(
        forGlyphRange: contentGlyphRange,
        in: textContainer
      ).offsetBy(
        dx: textView.textContainerOrigin.x,
        dy: textView.textContainerOrigin.y
      )
      let gap = contentRect.minX - markerRect.maxX

      #expect(
        gap >= 4 - 0.001,
        "font \(fontSize), text \(text), gap \(gap)"
      )
    }
  }
}

@Test @MainActor func checklistMarkerRemainsStableWhileTypingAndDeleting() throws {
  for family in ["Avenir Next", ".AppleSystemUIFont"] {
    for size in [CGFloat(11), CGFloat(17), CGFloat(24)] {
      for completed in [false, true] {
        let indent = size == 24 ? "    " : ""
        let prefix = indent + (completed ? "● " : "○ ")
        let textView = checklistTypingEditor(family: family, size: size, text: prefix)
        let window = NSWindow(contentRect: textView.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = textView
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
        let markerRange = NSRange(location: indent.utf16.count, length: 1)
        let empty = try #require(textView.checklistMarkerRect(for: markerRange))
        let emptyBaseline = try checklistLineBaseline(in: textView, at: markerRange.location + 1)
        for value in ["F", "a", "g", "1", " ", "   a", "中", "🙂"] {
          textView.insertText(value, replacementRange: textView.selectedRange())
          let populated = try #require(textView.checklistMarkerRect(for: markerRange))
          let populatedBaseline = try checklistLineBaseline(in: textView, at: markerRange.location + 1)
          print("CHECKLIST \(family) \(size) completed=\(completed) \(String(reflecting: value)): empty=\(empty.midY), populated=\(populated.midY), line baselines=\(emptyBaseline)->\(populatedBaseline)")
          // Fallback fonts may move the actual line baseline; the marker must follow it exactly.
          #expect(abs((populated.midY - populatedBaseline) - (empty.midY - emptyBaseline)) < 0.01)
          #expect(populated.size == empty.size)
          if family == "Avenir Next", size == 17 {
            try captureChecklist(textView, name: "checklist-\(completed)-\(value.unicodeScalars.map { String($0.value) }.joined(separator: "-"))")
          }
          while textView.string.utf16.count > prefix.utf16.count {
            textView.deleteBackward(nil)
          }
          #expect(textView.string == prefix)
          let restored = try #require(textView.checklistMarkerRect(for: markerRange))
          #expect(abs(restored.midY - empty.midY) < 0.01)
        }
        if family == "Avenir Next", size == 17 {
          try captureChecklist(textView, name: "checklist-\(completed)-empty")
        }
      }
    }
  }
}

@Test @MainActor func checklistMarkerAlignmentSurvivesCompletionToggle() throws {
  let textView = checklistTypingEditor(family: "Avenir Next", size: 17, text: "○ ")
  let window = NSWindow(contentRect: textView.bounds, styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = textView
  defer { window.orderOut(nil) }
  #expect(window.makeFirstResponder(textView))
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  let marker = NSRange(location: 0, length: 1)
  let empty = try #require(textView.checklistMarkerRect(for: marker))
  textView.insertText("g                    F", replacementRange: textView.selectedRange())
  let populated = try #require(textView.checklistMarkerRect(for: marker))
  #expect(abs(populated.midY - empty.midY) < 0.01)
  #expect(textView.toggleSelectedChecklist())
  let completed = try #require(textView.checklistMarkerRect(for: marker))
  #expect(abs(completed.midY - populated.midY) < 0.01)

  @MainActor func strikeRows() throws -> [Int] {
    textView.refreshChecklistPresentation()
    let bitmap = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
    textView.cacheDisplay(in: textView.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / textView.bounds.width
    // The middle of the long space run contains only the native strike-through.
    return (0..<min(bitmap.pixelsHigh, Int(50 * scale))).filter { y in
      (Int(70 * scale)..<Int(75 * scale)).contains { x in
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return color.alphaComponent > 0.2 && color.redComponent < 0.9
      }
    }
  }
  let originalStrikeRows = try strikeRows()
  #expect(!originalStrikeRows.isEmpty)
  textView.setSelectedRange(NSRange(location: 2, length: 1))
  textView.insertText("F", replacementRange: textView.selectedRange())
  let replaced = try #require(textView.checklistMarkerRect(for: marker))
  #expect(abs(replaced.midY - completed.midY) < 0.01)
  #expect(try strikeRows() == originalStrikeRows)
  try captureChecklist(textView, name: "checklist-strike-through")
  #expect(textView.toggleSelectedChecklist())
  let reopened = try #require(textView.checklistMarkerRect(for: marker))
  #expect(abs(reopened.midY - completed.midY) < 0.01)
}

@MainActor
private func checklistLineBaseline(in textView: ListAwareTextView, at index: Int) throws -> CGFloat {
  let manager = try #require(textView.layoutManager)
  let glyph = manager.glyphIndexForCharacter(at: index)
  return textView.textContainerOrigin.y
    + manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    + manager.location(forGlyphAt: glyph).y
}

@MainActor
private func checklistTypingEditor(family: String, size: CGFloat, text: String) -> ListAwareTextView {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.appearance = NSAppearance(named: .aqua)
  textView.drawsBackground = true
  textView.backgroundColor = .white
  textView.textColor = .black
  textView.reduceMotion = true
  textView.textContainerInset = NSSize(width: 16, height: 10)
  textView.textContainer?.lineFragmentPadding = 0
  var attributes = EditorTypography.defaultAttributes(family: family, size: size)
  attributes[.foregroundColor] = NSColor.black
  textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
  textView.typingAttributes = attributes
  return textView
}

@MainActor
private func captureChecklist(_ textView: ListAwareTextView, name: String) throws {
  guard let directory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] else { return }
  textView.refreshChecklistPresentation()
  let bitmap = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
  textView.cacheDisplay(in: textView.bounds, to: bitmap)
  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
}

@Test @MainActor func checklistMarkerUsesFontCapHeightAcrossFontSizes() throws {
  for fontSize in [CGFloat(11), CGFloat(14), CGFloat(24)] {
    let textView = ListAwareTextView(
      frame: NSRect(x: 0, y: 0, width: 320, height: 160)
    )
    textView.textContainerInset = NSSize(width: 16, height: 10)
    textView.textContainer?.lineFragmentPadding = 0
    textView.font = .systemFont(ofSize: fontSize)
    textView.string = "○ Formative 1"

    let textContainer = try #require(textView.textContainer)
    let layoutManager = try #require(textView.layoutManager)
    layoutManager.ensureLayout(for: textContainer)

    let markerRect = try #require(
      textView.checklistMarkerRect(for: NSRange(location: 0, length: 1))
    )
    let contentGlyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: 2, length: 1),
      actualCharacterRange: nil
    )
    let contentGlyph = contentGlyphRange.location
    let contentFont = try #require(
      textView.textStorage?.attribute(
        .font,
        at: 2,
        effectiveRange: nil
      ) as? NSFont
    )
    let lineFragmentRect = layoutManager.lineFragmentRect(
      forGlyphAt: contentGlyph,
      effectiveRange: nil
    )
    let baselineY = textView.textContainerOrigin.y
      + lineFragmentRect.minY
      + layoutManager.location(forGlyphAt: contentGlyph).y
    let capHeightMidY = baselineY - contentFont.capHeight / 2

    #expect(
      abs(markerRect.midY - capHeightMidY) < 0.01,
      "font \(fontSize), marker midY \(markerRect.midY), cap-height midY \(capHeightMidY)"
    )
  }
}

@Test @MainActor func checklistMarkerKeepsFontAlignmentWithLeadingWhitespace() throws {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  textView.textContainerInset = NSSize(width: 16, height: 10)
  textView.textContainer?.lineFragmentPadding = 0
  textView.font = .systemFont(ofSize: 14)
  textView.string = "○   Formative 1"

  let textContainer = try #require(textView.textContainer)
  let layoutManager = try #require(textView.layoutManager)
  layoutManager.ensureLayout(for: textContainer)

  let markerRect = try #require(
    textView.checklistMarkerRect(for: NSRange(location: 0, length: 1))
  )
  let contentGlyphRange = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 4, length: 1),
    actualCharacterRange: nil
  )
  let contentGlyph = contentGlyphRange.location
  let contentFont = try #require(
    textView.textStorage?.attribute(
      .font,
      at: 4,
      effectiveRange: nil
    ) as? NSFont
  )
  let lineFragmentRect = layoutManager.lineFragmentRect(
    forGlyphAt: contentGlyph,
    effectiveRange: nil
  )
  let baselineY = textView.textContainerOrigin.y
    + lineFragmentRect.minY
    + layoutManager.location(forGlyphAt: contentGlyph).y
  let capHeightMidY = baselineY - contentFont.capHeight / 2

  #expect(
    abs(markerRect.midY - capHeightMidY) < 0.01,
    "marker midY \(markerRect.midY), cap-height midY \(capHeightMidY)"
  )
}

@Test @MainActor func allWhitespaceChecklistContentKeepsEmptyAlignment() throws {
  let textView = checklistTypingEditor(family: ".AppleSystemUIFont", size: 14, text: "○ ")
  let empty = try #require(textView.checklistMarkerRect(for: NSRange(location: 0, length: 1)))
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertText("  ", replacementRange: textView.selectedRange())
  let spaced = try #require(textView.checklistMarkerRect(for: NSRange(location: 0, length: 1)))
  #expect(spaced == empty)
}

@Test @MainActor func checklistMarkerStaysOnFirstLineWithWrappedMixedSizeContent() throws {
  let textView = checklistTypingEditor(family: "Avenir Next", size: 17, text: "    ○ F")
  textView.setFrameSize(NSSize(width: 160, height: 240))
  let window = NSWindow(contentRect: textView.bounds, styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = textView
  defer { window.orderOut(nil) }
  let markerRange = NSRange(location: 4, length: 1)
  let original = try #require(textView.checklistMarkerRect(for: markerRange))
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  textView.insertText(String(repeating: " wrapped content", count: 12), replacementRange: textView.selectedRange())
  let wrapped = try #require(textView.checklistMarkerRect(for: markerRange))
  #expect(abs(wrapped.midY - original.midY) < 0.01)
  let container = try #require(textView.textContainer)
  #expect((textView.layoutManager?.usedRect(for: container).height ?? 0) > 54)
  textView.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 24), range: NSRange(location: 6, length: 1))
  let mixed = try #require(textView.checklistMarkerRect(for: markerRange))
  textView.setSelectedRange(NSRange(location: 6, length: 1))
  textView.insertText("a", replacementRange: textView.selectedRange())
  let replaced = try #require(textView.checklistMarkerRect(for: markerRange))
  #expect(abs(replaced.midY - mixed.midY) < 0.01)
}

@Test @MainActor func depthZeroChecklistMarkerCacheDisplayKeepsWholeCircleInsideLeftClip() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
  textView.appearance = NSAppearance(named: .aqua)
  textView.drawsBackground = true
  textView.backgroundColor = .white
  textView.textContainerInset = NSSize(width: 16, height: 10)
  textView.textContainer?.lineFragmentPadding = 0
  textView.font = .systemFont(ofSize: 11)
  textView.checklistAccentColor = NSColor(
    calibratedRed: 0.12,
    green: 0.42,
    blue: 0.92,
    alpha: 1
  )
  textView.string = "○ Task"
  textView.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemRed,
    range: NSRange(location: 2, length: 4)
  )
  textView.refreshChecklistPresentation()

  let markerRect = try #require(
    textView.checklistMarkerRect(for: NSRange(location: 0, length: 1))
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  window.makeKeyAndOrderFront(nil)
  defer { window.orderOut(nil) }
  textView.updateTrackingAreas()
  let hoverLocation = textView.convert(
    NSPoint(x: markerRect.midX, y: markerRect.midY),
    to: nil
  )
  let hoverEvent = try #require(
    NSEvent.mouseEvent(
      with: .mouseMoved,
      location: hoverLocation,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 0,
      pressure: 0
    )
  )
  textView.mouseMoved(with: hoverEvent)

  let imageRep = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
  textView.cacheDisplay(in: textView.bounds, to: imageRep)

  let scaleX = CGFloat(imageRep.pixelsWide) / textView.bounds.width
  let scaleY = CGFloat(imageRep.pixelsHigh) / textView.bounds.height
  let xEnd = min(imageRep.pixelsWide, max(0, Int(ceil(markerRect.maxX * scaleX))))
  let yStart = max(0, Int(floor(markerRect.minY * scaleY)))
  let yEnd = min(imageRep.pixelsHigh, max(0, Int(ceil(markerRect.maxY * scaleY))))
  let inkColumns = (0..<xEnd).filter { x in
    (yStart..<yEnd).contains { y in
      guard let color = imageRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
        return false
      }
      let channelRange = max(color.redComponent, color.greenComponent, color.blueComponent)
        - min(color.redComponent, color.greenComponent, color.blueComponent)
      return channelRange < 0.08
        && color.redComponent < 0.95
    }
  }
  let renderedWidth = (inkColumns.last ?? -1) - (inkColumns.first ?? 0) + 1
  #expect(markerRect.width == ChecklistMarkerDrawing.markerDiameter)
  #expect(
    renderedWidth
      >= Int(ChecklistMarkerDrawing.markerDiameter * scaleX) - 1
  )
}

@Test @MainActor func nestedChecklistUsesStableMarkerSizeAndKeepsHitTargetBeforeContent() throws {
  for fontSize in [CGFloat(11), CGFloat(14)] {
    let textView = ListAwareTextView(
      frame: NSRect(x: 0, y: 0, width: 320, height: 160)
    )
    textView.font = .systemFont(ofSize: fontSize)
    textView.string = "    ○ Nested"
    let container = try #require(textView.textContainer)
    let layoutManager = try #require(textView.layoutManager)
    layoutManager.ensureLayout(for: container)

    let markerRange = NSRange(location: 4, length: 1)
    let markerRect = try #require(textView.checklistMarkerRect(for: markerRange))
    let hitRect = try #require(textView.checklistHitRect(for: markerRange))
    let slotGlyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: 4, length: 2),
      actualCharacterRange: nil
    )
    let slotRect = layoutManager.boundingRect(
      forGlyphRange: slotGlyphRange,
      in: container
    ).offsetBy(
      dx: textView.textContainerOrigin.x,
      dy: textView.textContainerOrigin.y
    )
    let contentGlyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: 6, length: 1),
      actualCharacterRange: nil
    )
    let contentRect = layoutManager.boundingRect(
      forGlyphRange: contentGlyphRange,
      in: container
    ).offsetBy(
      dx: textView.textContainerOrigin.x,
      dy: textView.textContainerOrigin.y
    )
    let expectedX = min(
      slotRect.midX - 8,
      slotRect.maxX - ChecklistMarkerDrawing.markerDiameter
        - ChecklistMarkerDrawing.minimumContentGap
    )

    #expect(markerRect.size == CGSize(width: 16, height: 16))
    #expect(abs(markerRect.minX - expectedX) < 0.01)
    if slotRect.width >= ChecklistMarkerDrawing.markerDiameter
      + 2 * ChecklistMarkerDrawing.minimumContentGap
    {
      #expect(abs(markerRect.midX - slotRect.midX) < 0.01)
    } else {
      #expect(
        abs(
          markerRect.maxX
            - (slotRect.maxX - ChecklistMarkerDrawing.minimumContentGap)
        ) < 0.01
      )
    }
    #expect(hitRect.contains(markerRect))
    #expect(hitRect.width >= 28)
    #expect(hitRect.height >= 28)
    #expect(abs(hitRect.maxX - markerRect.maxX) < 0.01)
    #expect(markerRect.maxX <= contentRect.minX)
    #expect(hitRect.maxX <= contentRect.minX)
  }
}

@Test @MainActor func emptyBulletMarkerUsesRelativeTemporaryOpacity() throws {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  let authoredColor = NSColor(
    calibratedRed: 0.12,
    green: 0.42,
    blue: 0.92,
    alpha: 0.6
  )
  textView.string = "• "
  let storage = try #require(textView.textStorage)
  let layoutManager = try #require(textView.layoutManager)
  storage.addAttribute(
    .foregroundColor,
    value: authoredColor,
    range: NSRange(location: 0, length: 1)
  )

  textView.refreshChecklistPresentation()

  let temporaryColor = try #require(
    layoutManager.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: 0,
      effectiveRange: nil
    ) as? NSColor
  )
  #expect(abs(temporaryColor.alphaComponent - authoredColor.alphaComponent * 0.45) < 0.001)
  #expect(temporaryColor.alphaComponent < authoredColor.alphaComponent)
  #expect(
    (storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
      == authoredColor
  )

  textView.refreshChecklistPresentation()
  let repeatedColor = try #require(
    layoutManager.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: 0,
      effectiveRange: nil
    ) as? NSColor
  )
  #expect(abs(repeatedColor.alphaComponent - authoredColor.alphaComponent * 0.45) < 0.001)

  textView.clearNoteLinkPresentation()
  #expect(
    (storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
      == authoredColor
  )
  textView.refreshChecklistPresentation()
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertText("x", replacementRange: textView.selectedRange())
  textView.refreshChecklistPresentation()
  #expect(textView.string == "• x")
  #expect(
    layoutManager.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: 0,
      effectiveRange: nil
    ) == nil
  )
}

@Test @MainActor func emptyListCommandsPlaceCaretAfterMarkerAndReturnExits() throws {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true

  textView.toggleList(.bullet(.disc))
  #expect(textView.string == "• ")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  try #require(textView.undoManager).undo()
  #expect(textView.string.isEmpty)
  try #require(textView.undoManager).redo()
  #expect(textView.string == "• ")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))

  textView.string = "\n"
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  textView.toggleAutomaticList(.numbers)
  #expect(textView.string == "1. \n")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

  textView.string = "○ "
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  #expect(textView.accessibilityCustomActions()?.isEmpty == false)
  #expect(textView.toggleSelectedChecklist())
  #expect(textView.string == "● ")

  textView.string = "○ "
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  let markerRect = try #require(
    textView.checklistMarkerRect(for: NSRange(location: 0, length: 1))
  )
  let clickPoint = NSPoint(x: markerRect.midX, y: markerRect.midY)
  let windowPoint = textView.convert(clickPoint, to: nil)
  let event = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: windowPoint,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    )
  )
  textView.mouseDown(with: event)
  #expect(textView.string == "● ")

  for marker in ["• ", "1. ", "○ "] {
    textView.string = marker
    textView.setSelectedRange(NSRange(location: marker.utf16.count, length: 0))
    textView.insertNewline(nil)
    #expect(textView.string.isEmpty)
  }
}

@Test @MainActor func newlineTerminatedEmptyListRemovalLeavesCaretAtParagraphStart() {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )

  func toggleTwice(
    marker: String,
    toggle: (ListAwareTextView) -> Void
  ) {
    textView.string = "\n"
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    toggle(textView)
    #expect(textView.string == marker + "\n")
    #expect(textView.selectedRange() == NSRange(location: marker.utf16.count, length: 0))

    toggle(textView)
    #expect(textView.string == "\n")
    #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
  }

  toggleTwice(marker: "• ") { $0.toggleList(.bullet(.disc)) }
  toggleTwice(marker: "○ ") { $0.toggleList(.checklist) }
  toggleTwice(marker: "1. ") { $0.toggleAutomaticList(.numbers) }
}

@Test @MainActor func multilineEmptyListRemovalKeepsReplacementSelection() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "• \n• "
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

  textView.toggleList(.bullet(.disc))

  #expect(textView.string == "\n")
  #expect(textView.selectedRange() == NSRange(location: 0, length: 1))
}

@Test @MainActor func completedChecklistTextUsesReversibleDisplayOnlyRecession() {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  let authoredColor = NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.92, alpha: 1)
  textView.string = "● Task"
  textView.textStorage?.addAttribute(
    .foregroundColor,
    value: authoredColor,
    range: NSRange(location: 2, length: 4)
  )
  textView.textStorage?.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 2, length: 4)
  )
  textView.refreshChecklistPresentation()

  NSImage(size: textView.bounds.size).lockFocus()
  textView.draw(textView.bounds)
  NSImage(size: textView.bounds.size).unlockFocus()

  let foreground = textView.layoutManager?.temporaryAttribute(
    .foregroundColor,
    atCharacterIndex: 2,
    effectiveRange: nil
  ) as? NSColor
  let strikethrough = textView.layoutManager?.temporaryAttribute(
    .strikethroughColor,
    atCharacterIndex: 2,
    effectiveRange: nil
  ) as? NSColor

  #expect(foreground != nil)
  #expect((foreground?.alphaComponent ?? 1) < authoredColor.alphaComponent)
  #expect(strikethrough?.isEqual(foreground) == true)
  let storedColor = textView.textStorage?.attribute(
    .foregroundColor,
    at: 2,
    effectiveRange: nil
  ) as? NSColor
  #expect(storedColor?.isEqual(authoredColor) == true)
}

@Test @MainActor func completedChecklistRecessionComposesWithNoteLinkPresentation() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let text = "● Outside \(token) tail"
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  textView.string = text
  let storage = try #require(textView.textStorage)
  let layoutManager = try #require(textView.layoutManager)
  let link = try #require(NoteLinkParser.links(in: text).first)
  let contentRange = NSRange(location: 2, length: text.utf16.count - 2)
  let authoredColor = NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.92, alpha: 1)
  storage.addAttribute(
    .foregroundColor,
    value: authoredColor,
    range: NSRange(location: 2, length: 7)
  )
  storage.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: contentRange
  )

  let accent = try #require(NSColor(hex: "#FFD600"))
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  textView.refreshChecklistPresentation()
  textView.refreshChecklistPresentation()

  func assertLayers() {
    #expect(
      sRGB(
        layoutManager.temporaryAttribute(
          .foregroundColor,
          atCharacterIndex: link.range.location,
          effectiveRange: nil
        ) as? NSColor
      ) == sRGB(accent)
    )
    #expect(
      layoutManager.temporaryAttribute(
        .underlineStyle,
        atCharacterIndex: link.range.location,
        effectiveRange: nil
      ) as? Int == NSUnderlineStyle.single.rawValue
    )

    let expectedRecession = authoredColor.withAlphaComponent(0.72)
    let foreground = layoutManager.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: 2,
      effectiveRange: nil
    ) as? NSColor
    let strikethrough = layoutManager.temporaryAttribute(
      .strikethroughColor,
      atCharacterIndex: 2,
      effectiveRange: nil
    ) as? NSColor
    #expect(sRGB(foreground) == sRGB(expectedRecession))
    #expect(sRGB(strikethrough) == sRGB(expectedRecession))
    #expect(
      storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        == authoredColor
    )
    #expect(
      storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? Int
        == NSUnderlineStyle.single.rawValue
    )
  }

  assertLayers()
  textView.clearNoteLinkPresentation()
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  assertLayers()
}

@Test @MainActor func clickingChecklistControlUsesSharedHitRect() throws {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.string = "○ Task"
  let container = try #require(textView.textContainer)
  textView.layoutManager?.ensureLayout(for: container)
  let hitRect = try #require(
    textView.checklistHitRect(for: NSRange(location: 0, length: 1))
  )
  let markerRect = try #require(
    textView.checklistMarkerRect(for: NSRange(location: 0, length: 1))
  )
  let paddedPoint = NSPoint(x: markerRect.minX - 1, y: markerRect.midY)
  #expect(hitRect.contains(paddedPoint))
  #expect(!markerRect.contains(paddedPoint))
  let windowPoint = textView.convert(
    paddedPoint,
    to: nil
  )
  let event = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: windowPoint,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    )
  )

  textView.mouseDown(with: event)

  #expect(textView.string == "● Task")
  #expect(
    textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func checklistTrackingAreaReplacesWithoutDuplicates() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.updateTrackingAreas()
  textView.updateTrackingAreas()

  let checklistAreas = textView.trackingAreas.filter {
    ($0.userInfo?["fleckChecklistMarker"] as? Bool) == true
      && $0.owner === textView
      && $0.options.contains(.inVisibleRect)
      && $0.options.contains(.mouseMoved)
      && $0.options.contains(.mouseEnteredAndExited)
  }
  #expect(checklistAreas.count == 1)
}

@Test @MainActor func completedChecklistRoundTripsWithoutRenderingArtifacts() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "● Task"
  textView.textStorage?.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 2, length: 4)
  )

  let restored = rtfRoundTrip(textView)

  #expect(restored.string == "● Task")
  #expect(
    restored.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
}

@MainActor
private func rtfRoundTrip(_ textView: NSTextView) -> ListAwareTextView {
  let storage = textView.textStorage!
  let data = try! storage.data(
    from: NSRange(location: 0, length: storage.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let attributed = try! NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let restored = ListAwareTextView(frame: .zero)
  restored.textStorage?.setAttributedString(attributed)
  return restored
}

@Test @MainActor func editorCommandsReportsCaretAndUniformFontState() throws {
  let textView = NSTextView()
  let font = try #require(NSFont(name: "Avenir Next", size: 17))
  textView.string = "Text"
  textView.typingAttributes[.font] = font
  textView.textStorage?.addAttribute(.font, value: font, range: NSRange(location: 0, length: 4))
  let commands = EditorCommands()
  commands.textView = textView

  textView.setSelectedRange(NSRange(location: 0, length: 0))
  commands.refreshFormattingState()
  #expect(commands.currentFontFamily == font.familyName)
  #expect(commands.currentFontSize == font.pointSize)
  #expect(!commands.isFontFamilyMixed)
  #expect(!commands.isFontSizeMixed)

  textView.setSelectedRange(NSRange(location: 0, length: 4))
  commands.refreshFormattingState()
  #expect(commands.currentFontFamily == font.familyName)
  #expect(commands.currentFontSize == font.pointSize)
}

@Test @MainActor func editorCommandsReportsMixedFamilyAndSizeWithoutInventingAValue() throws {
  let textView = NSTextView()
  let first = try #require(NSFont(name: "Avenir Next", size: 17))
  let second = try #require(NSFont(name: "Courier", size: 21))
  textView.string = "AB"
  textView.textStorage?.addAttribute(.font, value: first, range: NSRange(location: 0, length: 1))
  textView.textStorage?.addAttribute(.font, value: second, range: NSRange(location: 1, length: 1))
  let commands = EditorCommands()
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: 0, length: 2))
  commands.refreshFormattingState()

  #expect(commands.currentFontFamily == nil)
  #expect(commands.currentFontSize == nil)
  #expect(commands.isFontFamilyMixed)
  #expect(commands.isFontSizeMixed)
}

@Test @MainActor func editorCommandsAppliesValidSizeAtCaretAndSelection() {
  let textView = NSTextView()
  textView.string = "AB"
  let commands = EditorCommands()
  commands.textView = textView

  textView.setSelectedRange(NSRange(location: 0, length: 0))
  #expect(commands.applyFontSize(18))
  #expect((textView.typingAttributes[.font] as? NSFont)?.pointSize == 18)

  textView.setSelectedRange(NSRange(location: 0, length: 2))
  #expect(commands.applyFontSize(22))
  #expect((textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 22)
}

@Test @MainActor func editorCommandsRejectsInvalidSizesWithoutChangingAttributes() {
  let textView = NSTextView()
  textView.string = "A"
  let commands = EditorCommands()
  commands.textView = textView
  let original = textView.typingAttributes[.font] as? NSFont

  #expect(!commands.applyFontSize(0))
  #expect(!commands.applyFontSize(513))
  #expect(!commands.applyFontSize(.nan))
  #expect(!commands.applyFontSize(.infinity))
  #expect((textView.typingAttributes[.font] as? NSFont) == original)
  #expect(textView.string == "A")
}

@Test @MainActor func editorCommandsCaretFontFormattingDoesNotNotifyUntilTyping() throws {
  let textView = NSTextView()
  let recorder = EditorChangeRecorder()
  let font = try #require(NSFont(name: "Courier", size: 17))
  let family = try #require(font.familyName)
  textView.delegate = recorder
  textView.string = "A"
  let commands = EditorCommands()
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: 1, length: 0))

  commands.applyFontFamily(family)
  #expect(commands.applyFontSize(24))
  #expect(textView.string == "A")
  #expect(recorder.count == 0)

  textView.insertText("B", replacementRange: textView.selectedRange())
  #expect(textView.string == "AB")
  #expect(recorder.count == 1)
  #expect((textView.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.familyName == family)
  #expect((textView.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.pointSize == 24)
}

@Test @MainActor func editorFormattingCommandsUndoAndRedoSelectedAttributes() throws {
  let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
  let textView = NSTextView()
  let recorder = EditorChangeRecorder()
  window.contentView = textView
  textView.allowsUndo = true
  textView.delegate = recorder
  textView.string = "AB"
  let original = try #require(textView.textStorage?.attributedSubstring(from: NSRange(location: 0, length: 2)))
  let commands = EditorCommands()
  commands.textView = textView
  let family = try #require(NSFont(name: "Courier", size: 17)?.familyName)

  for (operation, requestedAttributeIsRestored) in [
    (
      { commands.applyFontFamily(family) },
      { (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == family }
    ),
    (
      { _ = commands.applyFontSize(24) },
      { (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 24 }
    ),
    (
      { commands.applyForegroundColor(.systemRed) },
      { textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemRed }
    ),
    (
      { commands.applyBackgroundColor(.systemYellow) },
      { textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemYellow }
    ),
  ] {
    textView.textStorage?.setAttributedString(original)
    try #require(textView.undoManager).removeAllActions()
    textView.setSelectedRange(NSRange(location: 0, length: 2))
    recorder.count = 0
    operation()
    #expect(recorder.count == 1)
    try #require(textView.undoManager).undo()
    #expect(textView.string == "AB")
    #expect(textView.textStorage?.attributedSubstring(from: NSRange(location: 0, length: 2)) == original)
    try #require(textView.undoManager).redo()
    #expect(textView.string == "AB")
    #expect(requestedAttributeIsRestored())
  }
}

@Test @MainActor func editorCommandsReportsMixedForegroundAndBackgroundColors() {
  let textView = NSTextView()
  textView.string = "AB"
  textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: 1))
  textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: NSRange(location: 1, length: 1))
  textView.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: NSRange(location: 0, length: 1))
  textView.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemGreen, range: NSRange(location: 1, length: 1))
  textView.setSelectedRange(NSRange(location: 0, length: 2))
  let commands = EditorCommands()
  commands.textView = textView

  commands.refreshFormattingState()

  #expect(commands.isForegroundColorMixed)
  #expect(commands.currentForegroundColor == nil)
  #expect(commands.isBackgroundColorMixed)
  #expect(commands.currentBackgroundColor == nil)
}

@Test @MainActor func editorCommandsTreatsVisuallyIdenticalColorsAcrossConvertibleColorSpacesAsUniform() throws {
  let textView = NSTextView()
  let foreground = NSColor(srgbRed: 0.22, green: 0.44, blue: 0.66, alpha: 1)
  let background = NSColor(srgbRed: 0.76, green: 0.58, blue: 0.34, alpha: 1)
  let foregroundInDisplayP3 = try #require(foreground.usingColorSpace(.displayP3))
  let backgroundInDisplayP3 = try #require(background.usingColorSpace(.displayP3))
  textView.string = "AB"
  textView.textStorage?.addAttributes(
    [.foregroundColor: foreground, .backgroundColor: background],
    range: NSRange(location: 0, length: 1)
  )
  textView.textStorage?.addAttributes(
    [.foregroundColor: foregroundInDisplayP3, .backgroundColor: backgroundInDisplayP3],
    range: NSRange(location: 1, length: 1)
  )
  textView.setSelectedRange(NSRange(location: 0, length: 2))
  let commands = EditorCommands()
  commands.textView = textView

  commands.refreshFormattingState()

  #expect(!commands.isForegroundColorMixed)
  #expect(sRGB(commands.currentForegroundColor) == sRGB(foreground))
  #expect(!commands.isBackgroundColorMixed)
  #expect(sRGB(commands.currentBackgroundColor) == sRGB(background))
}

@Test @MainActor func editorCommandsReportsGenuinelyDifferentColorsAcrossColorSpacesAsMixed() throws {
  let textView = NSTextView()
  let firstForeground = NSColor(srgbRed: 0.9, green: 0.08, blue: 0.1, alpha: 1)
  let secondForeground = try #require(
    NSColor(srgbRed: 0.08, green: 0.1, blue: 0.9, alpha: 1).usingColorSpace(.displayP3)
  )
  let firstBackground = NSColor(srgbRed: 0.95, green: 0.82, blue: 0.06, alpha: 1)
  let secondBackground = try #require(
    NSColor(srgbRed: 0.08, green: 0.82, blue: 0.14, alpha: 1).usingColorSpace(.displayP3)
  )
  textView.string = "AB"
  textView.textStorage?.addAttributes(
    [.foregroundColor: firstForeground, .backgroundColor: firstBackground],
    range: NSRange(location: 0, length: 1)
  )
  textView.textStorage?.addAttributes(
    [.foregroundColor: secondForeground, .backgroundColor: secondBackground],
    range: NSRange(location: 1, length: 1)
  )
  textView.setSelectedRange(NSRange(location: 0, length: 2))
  let commands = EditorCommands()
  commands.textView = textView

  commands.refreshFormattingState()

  #expect(commands.isForegroundColorMixed)
  #expect(commands.currentForegroundColor == nil)
  #expect(commands.isBackgroundColorMixed)
  #expect(commands.currentBackgroundColor == nil)
}

@Test @MainActor func editorAppearancePreservesExplicitSystemAndPaletteColorsWithoutUndoMutation() throws {
  let textView = NSTextView()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.string = "RGB"
  textView.textStorage?.addAttribute(
    .foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: 1)
  )
  textView.textStorage?.addAttribute(
    .foregroundColor, value: NSColor.systemRed, range: NSRange(location: 1, length: 1)
  )
  textView.textStorage?.removeAttribute(.foregroundColor, range: NSRange(location: 2, length: 1))
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.typingAttributes[.foregroundColor] = NSColor.textColor
  let explicitSystemColor = try #require(
    textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
  )
  let undoManager = try #require(window.undoManager)
  undoManager.removeAllActions()

  NativeRichTextEditor.applyAppearance(
    to: textView,
    textColorHex: "#30D158",
    backgroundColorHex: nil
  )
  #expect((textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.isEqual(NSColor.textColor) == true)
  #expect(textView.textStorage?.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .systemRed)
  #expect(textView.textStorage?.attribute(.foregroundColor, at: 2, effectiveRange: nil) == nil)
  #expect((textView.typingAttributes[.foregroundColor] as? NSColor)?.isEqual(NSColor.textColor) == true)
  #expect(temporaryForegroundColor(in: textView, at: 2) == sRGB(NSColor(hex: "#30D158")))
  #expect(!undoManager.canUndo)

  textView.textStorage?.addAttribute(
    .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 2, length: 1)
  )
  #expect(textView.textStorage?.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
  undoManager.removeAllActions()
  NativeRichTextEditor.applyAppearance(
    to: textView,
    textColorHex: "#30D158",
    backgroundColorHex: nil
  )
  #expect((textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.isEqual(NSColor.textColor) == true)
  #expect((textView.typingAttributes[.foregroundColor] as? NSColor)?.isEqual(NSColor.textColor) == true)
  #expect(!undoManager.canUndo)

  let rtfData = try textView.textStorage?.data(
    from: NSRange(location: 0, length: 3),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let restored = try NSAttributedString(
    data: try #require(rtfData),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let reloadedTextView = NSTextView()
  reloadedTextView.textStorage?.setAttributedString(restored)
  let reloadedSystemColor = reloadedTextView.textStorage?.attribute(
    .foregroundColor, at: 0, effectiveRange: nil
  ) as? NSColor
  #expect(reloadedSystemColor != nil)
  #expect(sRGB(reloadedSystemColor) == sRGB(explicitSystemColor))
  #expect(reloadedTextView.textStorage?.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .systemRed)
  #expect(reloadedTextView.textStorage?.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
}

@Test @MainActor func editorAccentAppearanceUpdatesCaretAndSelectionWithoutMutatingRichText() throws {
  let textView = NSTextView()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = "Accent"
  textView.textStorage?.addAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 0, length: textView.string.utf16.count)
  )
  textView.setSelectedRange(NSRange(location: 1, length: 4))
  textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 17)
  let selectionForeground = NSColor(srgbRed: 0.12, green: 0.34, blue: 0.56, alpha: 1)
  let selectionUnderline = NSUnderlineStyle.single.rawValue
  let selectionBackground = NSColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1)
  textView.selectedTextAttributes = [
    .foregroundColor: selectionForeground,
    .underlineStyle: selectionUnderline,
    .backgroundColor: selectionBackground,
  ]
  let originalText = NSAttributedString(attributedString: try #require(textView.textStorage))
  let originalRTF = try #require(
    try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.string.utf16.count),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
  )
  let originalSelection = textView.selectedRange()
  let originalTypingAttributes = NSDictionary(dictionary: textView.typingAttributes)
  let undoManager = try #require(textView.undoManager)
  undoManager.registerUndo(withTarget: textView) { _ in }
  let originalCanUndo = undoManager.canUndo

  NativeRichTextEditor.applyAccentAppearance(to: textView, accentColorHex: "#FFD600")
  let yellow = try #require(NSColor(hex: "#FFD600"))
  let yellowSelection = try #require(
    textView.selectedTextAttributes[.backgroundColor] as? NSColor
  )
  let yellowComponents = try #require(sRGB(yellow))
  let selectedYellowComponents = try #require(sRGB(yellowSelection))
  #expect(sRGB(textView.insertionPointColor) == yellowComponents)
  #expect(textView.selectedTextAttributes.count == 3)
  #expect(sRGB(textView.selectedTextAttributes[.foregroundColor] as? NSColor) == sRGB(selectionForeground))
  #expect(textView.selectedTextAttributes[.underlineStyle] as? Int == selectionUnderline)
  #expect(selectedYellowComponents == sRGB(yellow.withAlphaComponent(0.35)))

  NativeRichTextEditor.applyAccentAppearance(to: textView, accentColorHex: "#30D158")
  let green = try #require(NSColor(hex: "#30D158"))
  let greenSelection = try #require(
    textView.selectedTextAttributes[.backgroundColor] as? NSColor
  )
  let greenComponents = try #require(sRGB(green))
  let selectedGreenComponents = try #require(sRGB(greenSelection))
  #expect(sRGB(textView.insertionPointColor) == greenComponents)
  #expect(textView.selectedTextAttributes.count == 3)
  #expect(sRGB(textView.selectedTextAttributes[.foregroundColor] as? NSColor) == sRGB(selectionForeground))
  #expect(textView.selectedTextAttributes[.underlineStyle] as? Int == selectionUnderline)
  #expect(selectedGreenComponents == sRGB(green.withAlphaComponent(0.35)))

  #expect(NSAttributedString(attributedString: try #require(textView.textStorage)) == originalText)
  #expect(
    try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.string.utf16.count),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    ) == originalRTF
  )
  #expect(textView.selectedRange() == originalSelection)
  #expect(NSDictionary(dictionary: textView.typingAttributes).isEqual(to: originalTypingAttributes))
  #expect(undoManager.canUndo == originalCanUndo)
}

@Test @MainActor func paletteRecognitionSurvivesRTFRoundTrip() throws {
  let foreground = try #require(NSColor(hex: "#FF4245"))
  let background = try #require(NSColor(hex: "#FFD600"))
  let custom = NSColor(srgbRed: 0.12, green: 0.34, blue: 0.56, alpha: 1)
  let attributed = NSMutableAttributedString(string: "RYC")
  attributed.addAttribute(.foregroundColor, value: foreground, range: NSRange(location: 0, length: 1))
  attributed.addAttribute(.backgroundColor, value: background, range: NSRange(location: 1, length: 1))
  attributed.addAttribute(.foregroundColor, value: custom, range: NSRange(location: 2, length: 1))
  let rtf = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let restored = try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let restoredForeground = restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
  let restoredBackground = restored.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? NSColor
  let restoredCustom = restored.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor

  #expect(FleckPaletteOption.matchesPaletteColor(restoredForeground, hex: "#FF4245"))
  #expect(FleckPaletteOption.paletteName(for: restoredForeground) == "Red")
  #expect(FleckPaletteOption.matchesPaletteColor(restoredBackground, hex: "#FFD600"))
  #expect(FleckPaletteOption.paletteName(for: restoredBackground) == "Yellow")
  #expect(!FleckPaletteOption.matchesPaletteColor(restoredCustom, hex: "#FF4245"))
  #expect(FleckPaletteOption.paletteName(for: restoredCustom) == nil)
}

@Test @MainActor func editorCommandsPersistsSelectedColorsInRTF() throws {
  let textView = NSTextView()
  textView.string = "A"
  textView.setSelectedRange(NSRange(location: 0, length: 1))
  let commands = EditorCommands()
  commands.textView = textView

  commands.applyForegroundColor(.systemRed)
  commands.applyBackgroundColor(.systemYellow)
  let rtfData = try textView.textStorage?.data(
    from: NSRange(location: 0, length: 1), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let data = try #require(rtfData)
  let restored = try NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )

  #expect(restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemRed)
  #expect(restored.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemYellow)
}

@Test @MainActor func fontFamilyAndSizePreserveTraitsUnderlineForegroundParagraphAndListAttributes() throws {
  let targetFamily = try #require(NSFont(name: "Courier", size: 17)?.familyName)

  let familyFixture = try richTextFormattingFixture()
  familyFixture.commands.applyFontFamily(targetFamily)
  #expect(familyFixture.recorder.count == 1)
  #expect(familyFixture.textView.string == familyFixture.string)
  let familyFont = try #require(familyFixture.font(at: 0))
  #expect(familyFont.familyName == targetFamily)
  #expect(familyFont.pointSize == familyFixture.font.pointSize)
  #expect(fontTraits(familyFont) == fontTraits(familyFixture.font))
  assertNonFontRichTextAttributes(in: familyFixture)

  let sizeFixture = try richTextFormattingFixture()
  #expect(sizeFixture.commands.applyFontSize(24))
  #expect(sizeFixture.recorder.count == 1)
  #expect(sizeFixture.textView.string == sizeFixture.string)
  let sizeFont = try #require(sizeFixture.font(at: 0))
  #expect(sizeFont.familyName == sizeFixture.font.familyName)
  #expect(sizeFont.pointSize == 24)
  #expect(fontTraits(sizeFont) == fontTraits(sizeFixture.font))
  assertNonFontRichTextAttributes(in: sizeFixture)
}

@Test @MainActor func editorFormattingCommandsNotifyAndRoundTripRTF() throws {
  let fixture = try richTextFormattingFixture()
  let targetFamily = try #require(NSFont(name: "Courier", size: 17)?.familyName)

  fixture.commands.applyFontFamily(targetFamily)
  #expect(fixture.commands.applyFontSize(24))
  fixture.commands.applyForegroundColor(.systemRed)
  fixture.commands.applyBackgroundColor(.systemYellow)
  #expect(fixture.recorder.count == 4)
  #expect(fixture.textView.string == fixture.string)

  let rtfData = try fixture.textView.textStorage?.data(
    from: NSRange(location: 0, length: fixture.string.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let data = try #require(rtfData)
  let restored = try NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let attributes = restored.attributes(at: 0, effectiveRange: nil)
  let font = try #require(attributes[.font] as? NSFont)

  #expect(restored.string == fixture.string)
  #expect(font.familyName == targetFamily)
  #expect(font.pointSize == 24)
  #expect(fontTraits(font) == fontTraits(fixture.font))
  #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
  #expect(sRGB(attributes[.foregroundColor] as? NSColor) == sRGB(.systemRed))
  #expect(sRGB(attributes[.backgroundColor] as? NSColor) == sRGB(.systemYellow))
  #expect(textListMarker(in: attributes) == .disc)
}

@Test @MainActor func editorCommandsAddsAndRemovesForegroundColorForSelectionAndCaret() {
  let textView = NSTextView()
  let recorder = EditorChangeRecorder()
  textView.delegate = recorder
  textView.string = "A"
  let commands = EditorCommands()
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: 0, length: 1))
  commands.applyForegroundColor(.systemRed)
  #expect(recorder.count == 1)
  #expect(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemRed)
  commands.applyForegroundColor(nil)
  #expect(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
  recorder.count = 0
  textView.setSelectedRange(NSRange(location: 1, length: 0))
  commands.applyForegroundColor(.systemBlue)
  #expect(recorder.count == 0)
  textView.insertText("B", replacementRange: textView.selectedRange())
  #expect(recorder.count == 1)
  #expect(textView.textStorage?.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .systemBlue)
}

@Test @MainActor func editorCommandsAddsAndRemovesHighlightForSelectionAndCaret() {
  let textView = NSTextView()
  let recorder = EditorChangeRecorder()
  textView.delegate = recorder
  textView.string = "A"
  let commands = EditorCommands()
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: 0, length: 1))
  commands.applyBackgroundColor(.systemYellow)
  #expect(recorder.count == 1)
  #expect(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemYellow)
  commands.applyBackgroundColor(nil)
  #expect(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
  recorder.count = 0
  textView.setSelectedRange(NSRange(location: 1, length: 0))
  commands.applyBackgroundColor(.systemGreen)
  #expect(recorder.count == 0)
  textView.insertText("B", replacementRange: textView.selectedRange())
  #expect(recorder.count == 1)
  #expect(textView.textStorage?.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? NSColor == .systemGreen)
}

private final class EditorChangeRecorder: NSObject, NSTextViewDelegate {
  var count = 0

  func textDidChange(_ notification: Notification) {
    count += 1
  }
}

@Test func formattingBarUsesCurrentCommandStateAndOnlyNumericSizeInput() throws {
  let source = try notesPanelSource()

  #expect(source.contains("currentFontFamily"))
  #expect(source.contains("isFontFamilyMixed"))
  #expect(source.contains("currentFontSize"))
  #expect(source.contains("isFontSizeMixed"))
  #expect(source.contains("applyFontSize"))
  #expect(source.contains("commands.isFontSizeMixed ? \"Mixed\""))
  #expect(!source.contains("Stepper"))
  #expect(!source.contains("Font Size Presets"))
}

@Test func highlighterMarkerShapeUsesUprightBodyAndDistinctLowerChiselInk() throws {
  let rect = CGRect(x: 0, y: 0, width: 20, height: 18)
  let bodyPath = HighlighterMarkerShape().path(in: rect)
  let inkPath = HighlighterMarkerNibShape().path(in: rect)
  var inkPoints: [CGPoint] = []
  inkPath.forEach { element in
    switch element {
    case .move(to: let point), .line(to: let point):
      inkPoints.append(point)
    case .quadCurve, .curve, .closeSubpath:
      break
    @unknown default:
      break
    }
  }
  let flatChiselEdge = zip(inkPoints, inkPoints.dropFirst()).first { first, second in
    abs(first.y - second.y) < 0.01 && abs(first.x - second.x) >= rect.width * 0.25
  }

  #expect(bodyPath.boundingRect.width >= rect.width * 0.55)
  #expect(bodyPath.boundingRect.minY < inkPath.boundingRect.minY)
  #expect(inkPath.boundingRect.maxY > bodyPath.boundingRect.maxY)
  #expect(inkPath.boundingRect.width <= bodyPath.boundingRect.width * 0.7)
  #expect(inkPath.contains(CGPoint(x: rect.width * 0.5, y: rect.height * 0.75)))
  #expect(flatChiselEdge != nil)
  #expect(!(try notesPanelSource()).contains(".rotationEffect(.degrees(-32))"))
}

@Test @MainActor func highlighterMarkerIconUsesUniformHighlightAndYellowFallback() throws {
  let selectedColor = try #require(NSColor(hex: "#4D8DFF"))
  let selectedIcon = HighlighterMarkerIcon(
    backgroundColor: selectedColor,
    isMixed: false
  )
  let noColorIcon = HighlighterMarkerIcon(
    backgroundColor: nil,
    isMixed: false
  )
  let mixedColorIcon = HighlighterMarkerIcon(
    backgroundColor: selectedColor,
    isMixed: true
  )

  #expect(FleckColorHex.hex(from: selectedIcon.inkColor) == "#4D8DFF")
  #expect(FleckColorHex.hex(from: noColorIcon.inkColor) == "#FFD600")
  #expect(FleckColorHex.hex(from: mixedColorIcon.inkColor) == "#FFD600")

  let source = try notesPanelSource()

  #expect(source.contains("backgroundColor: commands.currentBackgroundColor"))
  #expect(source.contains("isMixed: commands.isBackgroundColorMixed"))
  #expect(!source.contains("HighlighterMarkerIcon()"))
}

@Test func titleFontActionRoutesOnlyToFocusedMutation() {
  var titleFamily: String?
  var bodyFamily: String?

  routeFontFamilyAction(
    family: "Menlo",
    isTitleFocused: true,
    titleMutation: { titleFamily = $0 },
    bodyMutation: { bodyFamily = $0 }
  )

  #expect(titleFamily == "Menlo")
  #expect(bodyFamily == nil)

  titleFamily = nil
  bodyFamily = nil

  routeFontFamilyAction(
    family: "Avenir",
    isTitleFocused: false,
    titleMutation: { titleFamily = $0 },
    bodyMutation: { bodyFamily = $0 }
  )

  #expect(titleFamily == nil)
  #expect(bodyFamily == "Avenir")
}

@Test func formattingBarUsesFleckPaletteForForegroundAndHighlight() throws {
  let source = try notesPanelSource()

  #expect(source.contains("Automatic"))
  #expect(source.contains("No Highlight"))
  #expect(source.contains("FleckColorPicker"))
  #expect(source.contains("currentForegroundColor"))
  #expect(source.contains("currentBackgroundColor"))
  #expect(!source.contains("TabColorOption"))
}

@Test func fontSizeSubmissionRestoresInvalidInputAndSkipsAnUnchangedUniformSize() {
  #expect(FontSizeSubmission.requestedSize(for: "1", currentSize: 18, isMixed: false) == 1)
  #expect(FontSizeSubmission.requestedSize(for: "512", currentSize: 18, isMixed: false) == 512)
  #expect(FontSizeSubmission.requestedSize(for: "0", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "513", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "not a number", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "nan", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "inf", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "18", currentSize: 18, isMixed: false) == nil)
  #expect(FontSizeSubmission.requestedSize(for: "18", currentSize: 18, isMixed: true) == 18)
  #expect(FontSizeSubmission.requestedSize(for: "24", currentSize: 18, isMixed: false) == 24)
}

@MainActor
private struct RichTextFormattingFixture {
  let textView: NSTextView
  let recorder: EditorChangeRecorder
  let commands: EditorCommands
  let font: NSFont
  let foregroundColor: NSColor
  let backgroundColor: NSColor
  let string: String

  func font(at index: Int) -> NSFont? {
    textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
  }
}

@MainActor
private func richTextFormattingFixture() throws -> RichTextFormattingFixture {
  let textView = NSTextView()
  let recorder = EditorChangeRecorder()
  let font = try #require(NSFont(name: "Helvetica-BoldOblique", size: 17))
  let foregroundColor = NSColor.systemBlue
  let backgroundColor = NSColor.systemGreen
  let list = NSTextList(markerFormat: .disc, options: 0)
  let paragraph = NSMutableParagraphStyle()
  paragraph.textLists = [list]
  paragraph.firstLineHeadIndent = 18
  let string = "AB"
  let range = NSRange(location: 0, length: string.utf16.count)

  textView.delegate = recorder
  textView.string = string
  textView.textStorage?.addAttributes(
    [
      .font: font,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .foregroundColor: foregroundColor,
      .backgroundColor: backgroundColor,
      .paragraphStyle: paragraph,
    ],
    range: range
  )
  textView.setSelectedRange(range)
  let commands = EditorCommands()
  commands.textView = textView
  return .init(
    textView: textView,
    recorder: recorder,
    commands: commands,
    font: font,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    string: string
  )
}

@MainActor
private func assertNonFontRichTextAttributes(in fixture: RichTextFormattingFixture) {
  let attributes = fixture.textView.textStorage?.attributes(at: 0, effectiveRange: nil)
  #expect(attributes?[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
  #expect((attributes?[.foregroundColor] as? NSColor)?.isEqual(fixture.foregroundColor) == true)
  #expect((attributes?[.backgroundColor] as? NSColor)?.isEqual(fixture.backgroundColor) == true)
  #expect(textListMarker(in: attributes ?? [:]) == .disc)
}

private func fontTraits(_ font: NSFont) -> NSFontTraitMask {
  NSFontManager.shared.traits(of: font).intersection([.boldFontMask, .italicFontMask])
}

private func textListMarker(in attributes: [NSAttributedString.Key: Any]) -> NSTextList.MarkerFormat? {
  (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.first?.markerFormat
}

private func sRGB(_ color: NSColor?) -> [Int]? {
  guard let color = color?.usingColorSpace(.sRGB) else { return nil }
  return [
    Int((color.redComponent * 255).rounded()),
    Int((color.greenComponent * 255).rounded()),
    Int((color.blueComponent * 255).rounded()),
    Int((color.alphaComponent * 255).rounded()),
  ]
}

@MainActor
private func temporaryForegroundColor(in textView: NSTextView, at index: Int) -> [Int]? {
  sRGB(
    textView.layoutManager?.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: index,
      effectiveRange: nil
    ) as? NSColor
  )
}

@Test func formattingBarAnnouncesPaletteNamesAndPickerResetContexts() throws {
  let source = try notesPanelSource()

  #expect(source.contains("FleckColorPicker"))
  #expect(source.contains("resetTitle: \"Automatic\""))
  #expect(source.contains("resetTitle: \"No Highlight\""))
  #expect(source.contains("\"Automatic\""))
  #expect(source.contains("\"No Highlight\""))
  #expect(source.contains("colorAccessibilityValue"))
  #expect(source.contains("\"Custom\""))
  #expect(source.contains("accessibilityHint(\"Enter a size from 1 through 512 points.\")"))
}

@Test @MainActor func formattingBarAdaptsOneReachableCommandSurfaceAtSupportedWidths() async throws {
  #expect(FormattingToolbarLayout.presentation(availableWidth: 780) == .full)
  #expect(FormattingToolbarLayout.presentation(availableWidth: 360) == .compact)
  #expect(FormattingToolbarLayout.presentation(availableWidth: 719) == .compact)
  #expect(FormattingToolbarLayout.presentation(availableWidth: 720) == .full)
  #expect(FormattingToolbarLayout.presentation(availableWidth: 721) == .full)
  #expect(
    NotesPanelSizing.storedSize(
      preferred: CGSize(width: 800, height: 430),
      available: CGSize(width: 700, height: 400)
    ) == CGSize(width: 700, height: 400)
  )
  #expect(
    NotesPanelSizing.storedSize(
      preferred: CGSize(width: 620, height: 390),
      available: CGSize(width: 1_200, height: 900)
    ) == CGSize(width: 620, height: 390)
  )

  NSApplication.shared.accessibilitySetValue(
    true,
    forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  )
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Toolbar fixture", body: "Body")
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  defer { window.orderOut(nil) }
  window.setContentSize(NSSize(width: 800, height: 430))
  await settleHostedView(host)

  let fullLabels = [
    "Start Dictation", "Undo", "Redo", "Bold", "Italic", "Underline", "Strikethrough", "Font",
    "Font size", "Font Color", "Highlight", "Bullets", "Numbers", "Checklist", "Delete",
  ]
  let compactLabels = [
    "Start Dictation", "Undo", "Bold", "Font", "Font size", "Font Color",
    "Highlight", "More formatting", "Delete",
  ]

  func expectControlFramesWithinWindow(_ labels: [String], panelWidth: CGFloat) throws {
    let contentView = try #require(window.contentView)
    let contentFrame = window.convertToScreen(contentView.convert(contentView.bounds, to: nil))
      .insetBy(dx: -1, dy: -1)
    let hostFrame = window.convertToScreen(host.convert(host.bounds, to: nil))
      .insetBy(dx: -1, dy: -1)
    print("Toolbar geometry width=\(panelWidth) content=\(contentFrame) host=\(hostFrame)")
    for label in labels {
      let control = try #require(fontPickerAccessibilityElement(host, label: label))
      let frame = try #require(
        control.value(forKey: "accessibilityFrame") as? NSValue
      ).rectValue
      print("Toolbar control width=\(panelWidth) label=\(label) frame=\(frame)")
      #expect(frame.width > 0)
      #expect(frame.height > 0)
      #expect(contentFrame.contains(frame))
      #expect(hostFrame.contains(frame))
    }
  }

  try expectControlFramesWithinWindow(fullLabels, panelWidth: 800)
  #expect(fontPickerAccessibilityElement(host, label: "More formatting") == nil)

  for panelWidth in [739.0, 740.0, 741.0] {
    state.updatePreferences { $0.panelWidth = panelWidth }
    window.setContentSize(NSSize(width: panelWidth, height: 430))
    await settleHostedView(host)
    let more = fontPickerAccessibilityElement(host, label: "More formatting")
    if panelWidth < 740 {
      #expect(more != nil)
      try expectControlFramesWithinWindow(compactLabels, panelWidth: panelWidth)
    } else {
      #expect(more == nil)
      try expectControlFramesWithinWindow(fullLabels, panelWidth: panelWidth)
    }
  }

  state.updatePreferences { $0.panelWidth = 380 }
  window.setContentSize(NSSize(width: 380, height: 430))
  await settleHostedView(host)

  try expectControlFramesWithinWindow(compactLabels, panelWidth: 380)

  let editor = try #require(hostedPanelEditor(in: host))
  editor.setSelectedRange(NSRange(location: 0, length: 4))
  #expect(window.makeFirstResponder(editor))
  try sendHostedKeyEquivalent("u", keyCode: 32, modifiers: .command, to: window)
  #expect(
    (editor.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int)
      == NSUnderlineStyle.single.rawValue
  )
  commands.toggleBold()
  commands.undo()
  #expect(editor.undoManager?.canRedo == true)
  window.makeKeyAndOrderFront(nil)
  #expect(window.makeFirstResponder(editor))
  try sendHostedKeyEquivalent("z", keyCode: 6, modifiers: [.command, .shift], to: window)
  let font = try #require(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(fontTraits(font).contains(.boldFontMask))
}

@Test func formattingBarCanAlwaysBeCollapsedAndRestoredFromTheHeader() throws {
  let source = try notesPanelSource()

  #expect(source.contains("Hide Editor toolbar"))
  #expect(source.contains("Show Editor toolbar"))
  #expect(source.contains("showFormattingBar.toggle()"))
  #expect(source.contains("if appState.preferences.showFormattingBar"))
  #expect(source.contains("\"chevron.up\""))
  #expect(source.contains(".rotationEffect("))
  #expect(
    source.contains(
      ".degrees(appState.preferences.showFormattingBar ? 0 : 180)"
    )
  )
  #expect(source.contains("if reduceMotion"))
  #expect(source.contains("withAnimation(motion.quick)"))
  #expect(source.contains(".move(edge: .top).combined(with: .opacity)"))

  let editorCommands = try #require(source.range(of: "@StateObject private var editorCommands = EditorCommands()"))
  let formattingBar = try #require(source.range(of: "if appState.preferences.showFormattingBar"))
  #expect(editorCommands.lowerBound < formattingBar.lowerBound)
  #expect(!source.contains(".id(appState.preferences.showFormattingBar)"))
}

@Test func AppKitEditorFolderScopeDoesNotDuplicateEditor() throws {
  let source = try notesPanelSource()
  #expect(source.contains("FolderNavigator"))
  #expect(source.contains("visibleNotes"))
  #expect(source.contains("isEditorVisible"))
  #expect(source.contains(".opacity(isEditorVisible ? 1 : 0)"))
  #expect(source.components(separatedBy: "NativeRichTextEditor(").count - 1 == 1)
  #expect(!source.contains(".id(activeFolderID)"))
  #expect(!source.contains("folder-specific NSTextView"))
}

@Test func NotesPanelFolderScopeGatesActionsAndBoundsTheNavigator() throws {
  let source = try notesPanelSource()

  #expect(source.contains("visibleSelectedNote"))
  #expect(source.contains("activateNoteAndScope"))
  #expect(source.contains("onChange(of: appState.workspace.selectedNoteID)"))
  #expect(source.contains("guard isShowingTrash"))
  #expect(source.contains("ScrollView(.horizontal"))
  #expect(source.contains(".accessibilityIdentifier(\"folder-unfiled\")"))
  #expect(source.contains(".accessibilityIdentifier(\"folder-trash\")"))
  #expect(source.contains("folderNavigatorMaxHeight"))
  #expect(source.contains(".frame(maxHeight: folderNavigatorMaxHeight)"))
  #expect(source.contains("guard visibleSelectedNote?.id == note.id else { return }"))

  let navigator = try #require(source.components(separatedBy: "private struct FolderNavigator").last)
  let bodyStart = try #require(navigator.range(of: "var body: some View"))
  let rootDefinition = try #require(navigator.range(of: "private var rootRow"))
  let body = String(navigator[bodyStart.upperBound..<rootDefinition.lowerBound])
  let rootUse = try #require(body.range(of: "rootRow"))
  let folderScroll = try #require(body.range(of: "ScrollView(.horizontal"))
  let trashIdentifier = try #require(body.range(of: ".accessibilityIdentifier(\"folder-trash\")"))
  #expect(rootUse.lowerBound < folderScroll.lowerBound)
  #expect(folderScroll.lowerBound < trashIdentifier.lowerBound)
}

@Test func NotesPanelFolderContextActionsUseConcreteVisibleNotes() throws {
  let source = try notesPanelSource()

  #expect(source.contains("private func isNoteVisible(_ noteID: UUID)"))
  #expect(source.contains("guard isNoteVisible(note.id) else { return }"))
  #expect(source.contains("guard isNoteVisible(noteID), activateNoteAndScope(noteID) else"))
  #expect(source.contains("if activateNoteAndScope(noteID)"))
  #expect(source.contains("appState.setSelectedTabColor(hex)"))
  #expect(source.contains("guard let note = visibleSelectedNote else { return }"))
}

@Test func folderCreationPolishUsesSmoothMotionAndFleckPills() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let bodyStart = try #require(navigator.range(of: "var body: some View"))
  let rootDefinition = try #require(navigator.range(of: "private var rootRow"))
  let body = String(navigator[bodyStart.upperBound..<rootDefinition.lowerBound])
  let editor = navigator
    .components(separatedBy: "@ViewBuilder\n    private func folderEditor")
    .dropFirst()
    .first ?? ""
  let styleTail = navigator
    .components(separatedBy: "private struct FolderActionButtonStyle: ButtonStyle")
    .dropFirst()
    .first ?? ""
  let style = styleTail
    .components(separatedBy: "@ViewBuilder\n    private func folderEditor")
    .first ?? styleTail
  let normalizedNavigator = navigator
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")
  let normalizedEditor = editor
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")

  #expect(navigator.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
  #expect(
    normalizedNavigator.contains(
      "private var folderMorphAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0) }"
    )
  )
  #expect(body.contains(".animation(folderMorphAnimation, value: isCreatingFolder)"))
  #expect(!body.contains(".animation(motion.spatial, value: isCreatingFolder)"))

  #expect(editor.contains("let accent = Color(hex: appState.preferences.accentHex) ?? .accentColor"))
  #expect(
    normalizedEditor.contains(
      ".buttonStyle(FolderActionButtonStyle(role: .save, accent: accent, motion: motion))"
    )
  )
  #expect(
    normalizedEditor.contains(
      ".buttonStyle(FolderActionButtonStyle(role: .cancel, accent: accent, motion: motion))"
    )
  )
  #expect(editor.contains("Button(\"Save\")"))
  #expect(editor.contains("Button(\"Cancel\", role: .cancel)"))
  #expect(editor.contains("Save folder name"))
  #expect(editor.contains("Cancel folder name"))

  #expect(style.contains("enum Role: Equatable"))
  #expect(style.contains("let role: Role"))
  #expect(style.contains("let accent: Color"))
  #expect(style.contains("let motion: AppMotion"))
  #expect(style.contains("@Environment(\\.isEnabled) private var isEnabled"))
  #expect(style.contains(".font(.caption.weight(isSave ? .semibold : .medium))"))
  #expect(style.contains(".padding(.horizontal, 8)"))
  #expect(style.contains(".frame(height: 22)"))
  #expect(
    style.contains("RoundedRectangle(cornerRadius: 6, style: .continuous)")
  )
  #expect(style.contains("accent.opacity(configuration.isPressed ? 0.24 : 0.16)"))
  #expect(
    style.contains(
      "Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06)"
    )
  )
  #expect(
    style.contains(
      ".scaleEffect(isEnabled && configuration.isPressed ? motion.pressScale : 1)"
    )
  )
  #expect(style.contains(".opacity(isEnabled ? 1 : 0.48)"))
  #expect(style.contains(".animation(motion.quick, value: configuration.isPressed)"))
  #expect(editor.contains("folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"))
  #expect(!style.contains("Image(systemName:"))
  #expect(!style.lowercased().contains("material"))
  #expect(!style.lowercased().contains("gradient"))
  #expect(!style.lowercased().contains("shadow"))
  #expect(!style.lowercased().contains("outline"))
  #expect(!style.lowercased().contains("stroke"))
}

@Test func folderNoteDropTargetsDoNotNavigateOrSpringOpen() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )

  #expect(navigator.contains("NoteDropTarget"))
  #expect(navigator.contains("private struct NoteDropDelegate: DropDelegate"))
  #expect(navigator.contains("delegate: noteDropDelegate("))
  #expect(navigator.contains("providerSource == expectedSource"))
  #expect(navigator.contains("draggedSource == expectedSource"))
  #expect(navigator.contains("Color.accentColor.opacity"))
  #expect(navigator.contains(".contentShape"))
  #expect(navigator.contains("accessibilityAction"))
  #expect(navigator.contains("noteDropTarget = nil"))
  #expect(!navigator.contains("spring"))
  #expect(!navigator.contains("onSelect(targetFolderID)"))
}

@Test func compactUnfiledKeepsSelectionDropAndAccessibilityContracts() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )

  #expect(navigator.contains("isUnfiledCompact"))
  #expect(navigator.contains("updatePreferences"))
  #expect(navigator.contains("isUnfiledHovered"))
  #expect(navigator.contains("focusedRow == .unfiled"))
  #expect(navigator.contains(".accessibilityLabel(\"Unfiled\")"))
  #expect(navigator.contains(".accessibilityAction"))
  #expect(navigator.contains("FolderDragPayload.noteType"))
  #expect(navigator.contains("count:"))
}

@Test func compactUnfiledDisclosureShowsExpandedAtRestAndOnInteraction() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let normalizedNavigator = navigator
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")

  #expect(
    normalizedNavigator.contains(
      "private var showsUnfiledDisclosure: Bool { !isUnfiledCompact || isUnfiledHovered || focusedRow == .unfiled || isUnfiledDisclosureFocused }"
    )
  )
}

@Test func compactUnfiledRemovesOnlyItsAccidentalEditorLayoutModifiers() throws {
  let source = try notesPanelSource()
  let editor = try #require(
    source.components(separatedBy: "private var editor: some View").last
  )

  #expect(!editor.contains(".frame(minHeight: 48)"))
  #expect(source.contains(".frame(minHeight: 80)"))
  #expect(source.components(separatedBy: ".layoutPriority(1)").count - 1 == 1)
}

@Test func compactUnfiledDoesNotChangeNamedFolderOrTrashRowLabels() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )

  #expect(navigator.contains("name: \"Trash\""))
  #expect(navigator.contains("name: \"Unfiled\""))
  #expect(navigator.contains("ForEach(appState.workspace.folders"))
  #expect(!navigator.contains("All Notes"))
  #expect(!navigator.contains("Inbox"))
}

@Test func compactUnfiledUsesIntrinsicRootRowWidth() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let rootRow = try #require(
    navigator.components(separatedBy: "private var rootRow").last?
      .components(separatedBy: "@ViewBuilder\n    private func folderRow").first
  )
  let rowLabel = try #require(
    navigator.components(separatedBy: "private func rowLabel").last?
      .components(separatedBy: "private func noteDropDelegate").first
  )

  #expect(rootRow.contains(".fixedSize(horizontal: true, vertical: false)"))
  #expect(!rootRow.contains(".fixedSize(horizontal: isUnfiledCompact, vertical: false)"))
  #expect(!rowLabel.contains(".fixedSize(horizontal:"))
}

@Test func compactTrashAloneUsesIntrinsicWidthAndLeavesFolderStripFlexible() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let bodyStart = try #require(navigator.range(of: "var body: some View"))
  let rootDefinition = try #require(navigator.range(of: "private var rootRow"))
  let body = String(navigator[bodyStart.upperBound..<rootDefinition.lowerBound])
  let folderScroll = try #require(
    body.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").last?
      .components(separatedBy: "beginNewFolder()").first
  )
  let trashBlock = try #require(
    body.components(separatedBy: "Divider()").last?
      .components(separatedBy: ".accessibilityValue(").first
  )
  let rootRow = try #require(
    navigator.components(separatedBy: "private var rootRow").last?
      .components(separatedBy: "@ViewBuilder\n    private func folderRow").first
  )
  let folderRow = try #require(
    navigator.components(separatedBy: "private func folderRow").last?
      .components(separatedBy: "private struct FolderActionButtonStyle").first
  )
  let rowLabel = try #require(
    navigator.components(separatedBy: "private func rowLabel").last?
      .components(separatedBy: "private func noteDropDelegate").first
  )

  #expect(folderScroll.contains(".frame(maxWidth: .infinity)"))
  #expect(trashBlock.contains("onOpenTrash()"))
  #expect(trashBlock.contains("name: \"Trash\""))
  #expect(trashBlock.contains(".fixedSize(horizontal: true, vertical: false)"))
  #expect(
    body.components(separatedBy: ".fixedSize(horizontal: true, vertical: false)").count
      - 1 == 1
  )
  #expect(rootRow.contains(".fixedSize(horizontal: true, vertical: false)"))
  #expect(!rootRow.contains(".fixedSize(horizontal: isUnfiledCompact, vertical: false)"))
  #expect(!folderRow.contains(".fixedSize(horizontal: true, vertical: false)"))
  #expect(!rowLabel.contains(".fixedSize(horizontal: true, vertical: false)"))
}

@Test @MainActor func hostedNotesPanelToolbarVisibilityPreservesTheRealEditorAndCommands() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let text = "Keep this rich text"
  let selectedRange = NSRange(location: 5, length: 4)
  let boldFont = try #require(NSFont(name: "Helvetica-Bold", size: 18))
  let rtfDocumentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
    .documentType: NSAttributedString.DocumentType.rtf
  ]
  let attributed = NSMutableAttributedString(string: text)
  attributed.addAttributes(
    [.font: boldFont, .foregroundColor: NSColor.systemRed],
    range: NSRange(location: 0, length: text.utf16.count)
  )
  let rtf = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: rtfDocumentAttributes
  )
  state.updateSelected(body: text, richTextRTF: rtf)

  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(
    rootView: NotesPanel(dictationRuntime: runtime, editorCommands: commands)
      .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  window.contentView = host
  await settleHostedView(host)
  let textView = try #require(hostedDescendant(in: host, as: ListAwareTextView.self))
  textView.setSelectedRange(selectedRange)
  textView.typingAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.refreshFormattingState()
  commands.applyBackgroundColor(.systemYellow)
  let expectedRTF = try textView.textStorage?.data(
    from: NSRange(location: 0, length: text.utf16.count),
    documentAttributes: rtfDocumentAttributes
  )
  let expectedTypingAttributes = textView.typingAttributes

  #expect(commands.textView === textView)
  #expect(commands.isBold)
  #expect(textView.undoManager?.canUndo == true)

  state.updatePreferences { $0.showFormattingBar = false }
  await settleHostedView(host)
  state.updatePreferences { $0.showFormattingBar = true }
  await settleHostedView(host)

  #expect(commands.textView === textView)
  #expect(textView.string == text)
  #expect(textView.selectedRange() == selectedRange)
  #expect(
    NSDictionary(dictionary: textView.typingAttributes)
      .isEqual(to: expectedTypingAttributes)
  )
  let actualRTF = try textView.textStorage?.data(
    from: NSRange(location: 0, length: text.utf16.count),
    documentAttributes: rtfDocumentAttributes
  )
  #expect(actualRTF == expectedRTF)
  #expect(commands.isBold)
  #expect(textView.undoManager?.canUndo == true)
}

@Test @MainActor func hostedNotesPanelTitleScrollsWithBody() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(
    title: "Scrollable title",
    body: (0..<80).map { "Body line \($0) keeps the document taller than the viewport." }
      .joined(separator: "\n"),
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let titleField = try #require(hostedPanelTitleField(with: note.title, in: host))
  let bodyTextView = try #require(hostedPanelEditor(in: host))
  let bodyScrollView = try #require(hostedPanelBodyScrollView(in: host))
  let documentView = try #require(bodyScrollView.documentView)
  let titleScrollView = hostedVerticalScrollView(containing: titleField)

  #expect(titleField.isDescendant(of: documentView))

  let initialBounds = bodyScrollView.contentView.bounds
  let initialVisibleDocumentRect = documentView.convert(
    initialBounds,
    from: bodyScrollView.contentView
  )
  let initialTitleFrame = documentView.convert(titleField.bounds, from: titleField)
  #expect(titleScrollView === bodyScrollView)
  #expect(documentView.frame.height > initialBounds.height)
  #expect(initialVisibleDocumentRect.contains(initialTitleFrame))

  let maximumOriginY = max(
    documentView.frame.minY,
    documentView.frame.maxY - initialBounds.height
  )
  bodyScrollView.contentView.scroll(
    to: NSPoint(x: initialBounds.origin.x, y: maximumOriginY)
  )
  bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)
  forceHostedViewUpdate(host)

  let scrolledBounds = bodyScrollView.contentView.bounds
  let scrolledVisibleDocumentRect = documentView.convert(
    scrolledBounds,
    from: bodyScrollView.contentView
  )
  #expect(scrolledBounds.origin.y > initialBounds.origin.y)
  #expect(!scrolledVisibleDocumentRect.intersects(initialTitleFrame))

  window.setContentSize(NSSize(width: 640, height: 360))
  host.setFrameSize(window.contentView?.bounds.size ?? NSSize(width: 640, height: 360))
  await settleHostedView(host)

  let relaidBounds = bodyScrollView.contentView.bounds
  let relaidVisibleDocumentRect = documentView.convert(
    relaidBounds,
    from: bodyScrollView.contentView
  )
  let relaidTitleFrame = documentView.convert(titleField.bounds, from: titleField)
  #expect(abs(relaidBounds.origin.y - scrolledBounds.origin.y) < 0.01)
  #expect(relaidBounds.origin.y > 0)
  #expect(!relaidVisibleDocumentRect.intersects(relaidTitleFrame))
  #expect(bodyTextView.enclosingScrollView === bodyScrollView)
}

@Test @MainActor func hostedNotesPanelUsesSlimOverlayScrollIndicator() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(
    title: "Slim indicator",
    body: (0..<80).map { "Body line \($0) keeps the document scrollable." }
      .joined(separator: "\n"),
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  )
  let commands = EditorCommands()
  let (_, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let scrollView = try #require(hostedPanelBodyScrollView(in: host))
  let verticalScroller = try #require(scrollView.verticalScroller)

  #expect(scrollView.hasVerticalScroller)
  #expect(scrollView.autohidesScrollers)
  #expect(scrollView.scrollerStyle == .overlay)
  #expect(verticalScroller.controlSize == .mini)
  #expect(scrollView.contentView.frame.width >= scrollView.bounds.width - 1)
}

@Test @MainActor func hostedNotesPanelTitleUsesSemiboldCustomFont() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(
    title: "Semibold title",
    body: "Body",
    richTextRTF: try hostedPanelRTF(text: "Body"),
    folderID: nil,
    titleFontFamily: "Avenir Next"
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  )
  state.updatePreferences { $0.fontFamily = "Menlo" }
  let commands = EditorCommands()
  let (_, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let titleField = try #require(hostedPanelTitleField(with: note.title, in: host))
  let font = try #require(titleField.font)

  #expect(font.familyName == "Avenir Next")
  #expect(font.fontName == "AvenirNext-DemiBold")
  #expect(font.pointSize == 20)
  #expect(
    EditorTypography.titleNSFont(family: ".AppleSystemUIFont").isEqual(
      NSFont.systemFont(ofSize: 20, weight: .semibold)
    )
  )
}

@Test @MainActor func hostedNotesPanelTitleBodyGeometryRemainsStableAcrossFocus() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(
    title: "Geometry title",
    body: "First body line\nSecond body line",
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  defer { window.orderOut(nil) }
  await settleHostedView(host)

  let titleField = try #require(hostedPanelTitleField(with: note.title, in: host))
  let bodyTextView = try #require(hostedPanelEditor(in: host))
  let documentView = try #require(bodyTextView.enclosingScrollView?.documentView)
  let layoutManager = try #require(bodyTextView.layoutManager)
  let textContainer = try #require(bodyTextView.textContainer)

  func measure() throws -> HostedTitleBodyGeometry {
    layoutManager.ensureLayout(for: textContainer)
    var firstLineGlyphRange = NSRange(location: 0, length: 0)
    _ = layoutManager.lineFragmentRect(
      forGlyphAt: layoutManager.glyphIndexForCharacter(at: 0),
      effectiveRange: &firstLineGlyphRange
    )
    let firstBodyLineRectInTextView = layoutManager.boundingRect(
      forGlyphRange: firstLineGlyphRange,
      in: textContainer
    ).offsetBy(
      dx: bodyTextView.textContainerOrigin.x,
      dy: bodyTextView.textContainerOrigin.y
    )
    let firstBodyLineRect = documentView.convert(
      firstBodyLineRectInTextView,
      from: bodyTextView
    )
    let titleFrame = documentView.convert(titleField.bounds, from: titleField)
    let titleCell = try #require(titleField.cell)
    let cellTitleRect = titleCell.titleRect(forBounds: titleField.bounds)
    let titleRenderRect: CGRect
    if let fieldEditor = titleField.currentEditor() as? NSTextView,
      let fieldEditorLayoutManager = fieldEditor.layoutManager,
      let fieldEditorTextContainer = fieldEditor.textContainer,
      fieldEditor.textStorage?.length ?? 0 > 0
    {
      fieldEditorLayoutManager.ensureLayout(for: fieldEditorTextContainer)
      var titleLineGlyphRange = NSRange(location: 0, length: 0)
      _ = fieldEditorLayoutManager.lineFragmentRect(
        forGlyphAt: fieldEditorLayoutManager.glyphIndexForCharacter(at: 0),
        effectiveRange: &titleLineGlyphRange
      )
      let titleGlyphRectInFieldEditor = fieldEditorLayoutManager.boundingRect(
        forGlyphRange: titleLineGlyphRange,
        in: fieldEditorTextContainer
      ).offsetBy(
        dx: fieldEditor.textContainerOrigin.x,
        dy: fieldEditor.textContainerOrigin.y
      )
      titleRenderRect = documentView.convert(
        titleGlyphRectInFieldEditor,
        from: fieldEditor
      )
    } else {
      titleRenderRect = documentView.convert(cellTitleRect, from: titleField)
    }
    let geometry = HostedTitleBodyGeometry(
      titleFrame: titleFrame,
      titleRenderRect: titleRenderRect,
      firstBodyLineRect: firstBodyLineRect
    )
    return geometry
  }

  let initial = try measure()
  #expect(window.makeFirstResponder(titleField))
  await settleHostedView(host)
  let titleFocused = try measure()
  #expect(window.makeFirstResponder(bodyTextView))
  await settleHostedView(host)
  let bodyFocused = try measure()
  #expect(window.makeFirstResponder(titleField))
  await settleHostedView(host)
  let titleFocusedAgain = try measure()

  for geometry in [initial, titleFocused, bodyFocused, titleFocusedAgain] {
    #expect(
      geometry.renderedGap <= 8,
      "rendered title/body gap \(geometry.renderedGap) pt exceeds 8 pt"
    )
  }
  for geometry in [titleFocused, bodyFocused, titleFocusedAgain] {
    #expect(
      abs(geometry.renderedTitleMinY - initial.renderedTitleMinY) < 0.01,
      "rendered title minY shifted from \(initial.renderedTitleMinY) to \(geometry.renderedTitleMinY)"
    )
    #expect(
      abs(geometry.titleFrame.minY - initial.titleFrame.minY) < 0.01,
      "title frame minY shifted from \(initial.titleFrame.minY) to \(geometry.titleFrame.minY)"
    )
    #expect(
      abs(geometry.titleFrame.height - initial.titleFrame.height) < 0.01,
      "title frame height shifted from \(initial.titleFrame.height) to \(geometry.titleFrame.height)"
    )
    #expect(
      abs(geometry.renderedGap - initial.renderedGap) < 0.01,
      "rendered gap shifted from \(initial.renderedGap) to \(geometry.renderedGap)"
    )
  }
}

@Test @MainActor func hostedTitleKeepsSingleLineEditingCommands() async throws {
  try await withHostedTitleEditors { _, window, _, title, _ in
    #expect(window.makeFirstResponder(title))
    let editor = try #require(title.currentEditor() as? NSTextView)
    let original = editor.string
    for command in [
      #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
      #selector(NSResponder.insertLineBreak(_:)),
      #selector(NSResponder.insertParagraphSeparator(_:)),
    ] {
      editor.setSelectedRange(NSRange(location: 2, length: 0))
      editor.doCommand(by: command)
      #expect(editor.string == original)
    }

    editor.undoManager?.removeAllActions()
    editor.selectAll(nil)
    editor.insertText(
      NSAttributedString(
        string: "Direct\r\ninput\u{2028}stays\u{2029}plain",
        attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
      ),
      replacementRange: editor.selectedRange()
    )
    #expect(editor.string == "Direct input stays plain")
    #expect(editor.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    #expect(editor.undoManager?.canUndo == true)
    editor.undoManager?.undo()
    #expect(editor.string == original)

    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let pasted = NSAttributedString(
      string: "Pasted\r\ntext\u{0085}on\u{2028}one\u{2029}line",
      attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
    )
    pasteboard.setData(
      pasted.rtf(from: NSRange(location: 0, length: pasted.length)),
      forType: .rtf
    )
    editor.undoManager?.removeAllActions()
    editor.selectAll(nil)
    #expect(editor.readSelection(from: pasteboard, type: .rtf))
    #expect(editor.string == "Pasted text on one line")
    #expect(editor.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    #expect(editor.undoManager?.canUndo == true)
    editor.undoManager?.undo()
    #expect(editor.string == original)
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(editor.string == original)
  }
}

@Test @MainActor func hostedTitlePreservesNativeReturnTabAndEscapeCommands() async throws {
  try await withHostedTitleEditors { state, window, host, title, body in
    title.nextKeyView = body

    // Direct command routing matches an ordinary AppKit field editor: Return and
    // cancelOperation keep it active, while Tab advances through the key loop.
    #expect(window.makeFirstResponder(title))
    let returnEditor = try #require(title.currentEditor() as? NSTextView)
    returnEditor.selectAll(nil)
    returnEditor.insertText("Committed title", replacementRange: returnEditor.selectedRange())
    returnEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    await settleHostedView(host)
    #expect(window.firstResponder === returnEditor)
    #expect(title.stringValue == "Committed title")
    #expect(state.workspace.notes.first?.title == "Committed title")

    #expect(window.makeFirstResponder(title))
    let tabEditor = try #require(title.currentEditor() as? NSTextView)
    tabEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    #expect(window.firstResponder === body)
    #expect(title.stringValue == "Committed title")

    #expect(window.makeFirstResponder(title))
    let cancelEditor = try #require(title.currentEditor() as? NSTextView)
    cancelEditor.selectAll(nil)
    cancelEditor.insertText("Discarded title", replacementRange: cancelEditor.selectedRange())
    cancelEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    await settleHostedView(host)
    #expect(window.firstResponder === cancelEditor)
    #expect(title.stringValue == "Discarded title")
    #expect(state.workspace.notes.first?.title == "Discarded title")
  }
}

@Test @MainActor func hostedTitlePreservesMarkedTextComposition() async throws {
  try await withHostedTitleEditors { state, window, host, title, _ in
    #expect(window.makeFirstResponder(title))
    let editor = try #require(title.currentEditor() as? NSTextView)
    editor.selectAll(nil)
    editor.setMarkedText(
      "かな", selectedRange: NSRange(location: 2, length: 0),
      replacementRange: editor.selectedRange()
    )
    #expect(editor.hasMarkedText())
    #expect(editor.string == "かな")
    editor.unmarkText()
    #expect(!editor.hasMarkedText())
    editor.insertText("。", replacementRange: editor.selectedRange())
    await settleHostedView(host)
    #expect(editor.string == "かな。")
    #expect(title.stringValue == "かな。")
    #expect(state.workspace.notes.first?.title == "かな。")
  }
}

@Test @MainActor func hostedEmptyTitlePlaceholderStaysAlignedThroughEditing() async throws {
  for family in ["Avenir Next", ".AppleSystemUIFont"] {
    try await withHostedTitleEditors(titleText: "", fontFamily: family) { state, window, host, title, body in
      #expect(window.makeFirstResponder(body))
      await settleHostedView(host)
      let originalFrame = host.convert(title.bounds, from: title)
      let originalBody = state.workspace.notes.first?.body
      @MainActor func sample(_ phase: String) throws -> ClosedRange<Int> {
        // Capture the native draw path before asking TextKit to calculate any layout.
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        let top = host.isFlipped ? originalFrame.minY : host.bounds.height - originalFrame.maxY
        let rows = max(0, Int((top - 10) * scale))..<min(bitmap.pixelsHigh, Int((top + originalFrame.height) * scale))
        // The first N is common to the placeholder and typed text; exclude the caret at x=2.
        let columns = Int((originalFrame.minX + 5) * scale)..<Int((originalFrame.minX + 13) * scale)
        let ink = rows.filter { y in columns.contains { x in
          (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
        } }
        let first = try #require(ink.first)
        let last = try #require(ink.last)
        #expect(ink.count < rows.count)
        #expect(host.convert(title.bounds, from: title) == originalFrame)
        let label = "placeholder-\(family)-\(window.appearance!.name.rawValue)-\(phase)"
        print("\(label): ink=\(first)...\(last), frame=\(originalFrame)")
        if let directory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] {
          try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
          )
          let png = try #require(bitmap.representation(using: .png, properties: [:]))
          try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(label).png"))
        }
        return first...last
      }
      let inactive = try sample("inactive-empty")
      #expect(window.makeFirstResponder(title))
      let editor = try #require(title.currentEditor() as? NSTextView)
      #expect(window.firstResponder === editor)
      let editorFrame = host.convert(editor.bounds, from: editor)
      print("PLACEHOLDER EDITOR FRAME \(family): title=\(originalFrame), editor=\(editorFrame)")
      #expect(editorFrame.intersection(originalFrame).height >= originalFrame.height - 1)
      for turn in 0..<3 {
        if turn > 0 {
          await Task.yield()
          host.layoutSubtreeIfNeeded()
        }
        let focused = try sample("focused-empty-\(turn)")
        #expect(abs(focused.lowerBound - inactive.lowerBound) <= 1)
        #expect(abs(focused.upperBound - inactive.upperBound) <= 1)
      }
      #expect(editor.string.isEmpty)
      editor.insertText("N", replacementRange: editor.selectedRange())
      let typed = try sample("first-character")
      #expect(abs(typed.lowerBound - inactive.lowerBound) <= 1)
      #expect(abs(typed.upperBound - inactive.upperBound) <= 1)
      editor.deleteBackward(nil)
      for turn in 0..<3 {
        if turn > 0 {
          await Task.yield()
          host.layoutSubtreeIfNeeded()
        }
        let emptied = try sample("deleted-empty-\(turn)")
        #expect(abs(emptied.lowerBound - inactive.lowerBound) <= 1)
        #expect(abs(emptied.upperBound - inactive.upperBound) <= 1)
      }
      await settleHostedView(host)
      #expect(editor.string.isEmpty)
      #expect(state.workspace.notes.first?.title == "")
      #expect(state.workspace.notes.first?.body == originalBody)
      #expect(window.makeFirstResponder(body))
      let unfocused = try sample("unfocused-empty")
      #expect(abs(unfocused.lowerBound - inactive.lowerBound) <= 1)
      #expect(abs(unfocused.upperBound - inactive.upperBound) <= 1)
      // Inspect input-method caret geometry only after all unforced visual samples.
      #expect(window.makeFirstResponder(title))
      let cursorEditor = try #require(title.currentEditor() as? NSTextView)
      let emptyCaret = cursorEditor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
      let emptyLine = cursorEditor.layoutManager?.extraLineFragmentRect
      cursorEditor.insertText("N", replacementRange: cursorEditor.selectedRange())
      let typedCaret = cursorEditor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
      print("PLACEHOLDER CARET \(family): empty=\(emptyCaret), typed=\(typedCaret), emptyLine=\(String(describing: emptyLine))")
      #expect(abs(emptyCaret.minY - typedCaret.minY) <= 1)
      #expect(abs(emptyCaret.height - typedCaret.height) <= 1)
      cursorEditor.deleteBackward(nil)
    }
  }
}

@Test @MainActor func hostedTitleBaselineRemainsStableDuringFocusTransition() async throws {
  let longTitle = String(repeating: "Caret title ", count: 12)
  for (isPinned, font, titleText, scrollY) in [
    (false, "Avenir Next", "Caret title", 0.0),
    (false, ".AppleSystemUIFont", longTitle, 8.0),
    (true, "Avenir Next", longTitle, 8.0),
    (true, ".AppleSystemUIFont", "Caret title", 0.0),
  ] {
    try await withHostedTitleEditors(
      isPinned: isPinned, titleText: titleText, fontFamily: font,
      bodyText: String(repeating: "Caret body\n", count: 50)
    ) { _, window, host, title, body in
      let scrollView = try #require(body.enclosingScrollView)
      do {
        #expect(window.makeFirstResponder(body))
        await settleHostedView(host)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let titleFrame = host.convert(title.bounds, from: title)
        let bodyFrame = host.convert(body.bounds, from: body)
        let clipOrigin = scrollView.contentView.bounds.origin
        let label = "\(isPinned ? "pinned" : "regular")-\(font)-keyboard-\(window.appearance!.name.rawValue)"

        @MainActor func sample(_ phase: String) throws -> (title: ClosedRange<Int>, body: ClosedRange<Int>) {
          // Do not force field-editor layout: that changes the very transition under test.
          @MainActor func ink(in rect: NSRect, from source: NSView) throws -> ClosedRange<Int> {
            let bitmap = try #require(source.bitmapImageRepForCachingDisplay(in: source.bounds))
            source.cacheDisplay(in: source.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsHigh) / source.bounds.height
            let sourceRect = source.convert(rect, from: host)
            let top = source.isFlipped
              ? sourceRect.minY - source.bounds.minY
              : source.bounds.maxY - sourceRect.maxY
            let left = sourceRect.minX - source.bounds.minX
            let right = sourceRect.maxX - source.bounds.minX
            let xs = max(0, Int(left * scale))..<min(bitmap.pixelsWide, Int(right * scale))
            let ys = max(0, Int(top * scale))..<min(bitmap.pixelsHigh, Int((top + sourceRect.height) * scale))
            let rows = ys.filter { y in xs.contains { x in
              (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2
            } }
            let first = try #require(rows.first)
            let last = try #require(rows.last)
            // A solid captured background must not silently count as glyph ink.
            #expect(rows.count < ys.count)
            let sourceFrame = host.convert(source.bounds, from: source)
            let sourceTop = host.isFlipped
              ? sourceFrame.minY - host.bounds.minY
              : host.bounds.maxY - sourceFrame.maxY
            let hostOffset = Int(sourceTop * scale)
            return (hostOffset + first)...(hostOffset + last)
          }
          // Leading glyphs exclude the caret at x=2; long-title horizontal scrolling is reset below.
          let titleSource: NSView = title.currentEditor() ?? title
          let titleInk = try ink(
            in: NSRect(
              x: titleFrame.minX + 5,
              y: titleFrame.minY - 10,
              width: 55,
              height: titleFrame.height + 10
            ),
            from: titleSource
          )
          let bodyInk = try ink(
            in: NSRect(x: bodyFrame.minX + 16, y: bodyFrame.minY + 8, width: 60, height: 27),
            from: body
          )
          #expect(host.convert(title.bounds, from: title) == titleFrame)
          #expect(host.convert(body.bounds, from: body) == bodyFrame)
          #expect(scrollView.contentView.bounds.origin == clipOrigin)
          print("TITLE INK \(label) \(phase): title=\(titleInk), body=\(bodyInk), frame=\(titleFrame), clip=\(clipOrigin)")
          if let directory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(label)-\(phase).png"))
          }
          return (titleInk, bodyInk)
        }

        let before = try sample("before")
        #expect(window.makeFirstResponder(title))
        let editor = try #require(title.currentEditor() as? NSTextView)
        #expect(window.firstResponder === editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        for turn in 0..<4 {
          if turn > 0 {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
          }
          let after = try sample("turn-\(turn)")
          #expect(abs(after.title.lowerBound - before.title.lowerBound) <= 1, "Title ascenders move or clip on focus")
          #expect(abs(after.title.upperBound - before.title.upperBound) <= 1, "Title baseline moves on focus")
          #expect(after.body == before.body)
        }
        let textContainer = try #require(editor.textContainer)
        let layoutManager = try #require(editor.layoutManager)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
          lineCount += 1
        }
        #expect(lineCount == 1)
      }
    }
  }
}

@Test @MainActor func hostedTitleCaretMatchesBodyAccent() async throws {
  try await withHostedTitleEditors { _, window, host, titleField, bodyEditor in
    let accent = try #require(NSColor(hex: "#FFD600"))
    for _ in 0..<2 {
      #expect(window.makeFirstResponder(bodyEditor))
      #expect(sRGB(bodyEditor.insertionPointColor) == sRGB(accent))
      #expect(window.makeFirstResponder(titleField))
      let fieldEditor = try #require(titleField.currentEditor() as? NSTextView)
      #expect(window.firstResponder === fieldEditor)
      // Check immediately: merely focusing an empty selection must style the caret.
      fieldEditor.setSelectedRange(NSRange(location: 2, length: 0))
      #expect(sRGB(fieldEditor.insertionPointColor) == sRGB(bodyEditor.insertionPointColor))
      await settleHostedView(host)
      #expect(sRGB(fieldEditor.insertionPointColor) == sRGB(accent))
    }
  }
}

@Test @MainActor func hostedTitleCaretUpdatesAccentWhileEditing() async throws {
  try await withHostedTitleEditors { state, window, host, titleField, bodyEditor in
    #expect(window.makeFirstResponder(titleField))
    let fieldEditor = try #require(titleField.currentEditor() as? NSTextView)
    let selection = NSRange(location: 1, length: 3)
    fieldEditor.setSelectedRange(selection)
    let typing = NSDictionary(dictionary: fieldEditor.typingAttributes)
    let selectedAppearance = NSDictionary(dictionary: fieldEditor.selectedTextAttributes)
    let originalTitle = fieldEditor.string
    state.updatePreferences { $0.accentHex = "#30D158" }
    await settleHostedView(host)
    #expect(window.firstResponder === fieldEditor)
    #expect(sRGB(fieldEditor.insertionPointColor) == sRGB(NSColor(hex: "#30D158")))
    #expect(sRGB(fieldEditor.insertionPointColor) == sRGB(bodyEditor.insertionPointColor))
    #expect(fieldEditor.selectedRange() == selection)
    #expect(NSDictionary(dictionary: fieldEditor.typingAttributes).isEqual(to: typing))
    #expect(NSDictionary(dictionary: fieldEditor.selectedTextAttributes).isEqual(to: selectedAppearance))
    #expect(fieldEditor.string == originalTitle)
    fieldEditor.insertText("EDIT", replacementRange: selection)
    await settleHostedView(host)
    #expect(state.workspace.notes.first?.title == (originalTitle as NSString).replacingCharacters(in: selection, with: "EDIT"))
    #expect(state.workspace.notes.first?.body == "Caret body")
  }
}

@Test @MainActor func hostedTitleAccentDoesNotLeakToOtherFields() async throws {
  try await withHostedTitleEditors { state, window, host, titleField, _ in
    let otherField = NSTextField(string: "Unrelated input")
    otherField.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    host.addSubview(otherField)
    #expect(window.makeFirstResponder(otherField))
    let ordinaryEditor = try #require(otherField.currentEditor() as? NSTextView)
    let originalCaret = ordinaryEditor.insertionPointColor
    let originalSelection = NSDictionary(dictionary: ordinaryEditor.selectedTextAttributes)
    #expect(window.makeFirstResponder(titleField))
    let titleEditor = try #require(titleField.currentEditor() as? NSTextView)
    #expect(titleEditor !== ordinaryEditor)
    #expect(sRGB(titleEditor.insertionPointColor) == sRGB(NSColor(hex: "#FFD600")))
    #expect(window.makeFirstResponder(otherField))
    #expect(otherField.currentEditor() === ordinaryEditor)
    #expect(sRGB(ordinaryEditor.insertionPointColor) == sRGB(originalCaret))
    #expect(NSDictionary(dictionary: ordinaryEditor.selectedTextAttributes).isEqual(to: originalSelection))
    state.updatePreferences { $0.accentHex = "#30D158" }
    await settleHostedView(host)
    #expect(sRGB(ordinaryEditor.insertionPointColor) == sRGB(originalCaret))
    #expect(window.makeFirstResponder(titleField))
    #expect(sRGB(titleEditor.insertionPointColor) == sRGB(NSColor(hex: "#30D158")))
    #expect(window.makeFirstResponder(otherField))
    #expect(otherField.currentEditor() === ordinaryEditor)
    #expect(sRGB(ordinaryEditor.insertionPointColor) == sRGB(originalCaret))
  }
}

@MainActor
private func withHostedTitleEditors(
  isPinned: Bool = false,
  titleText: String = "Caret title",
  fontFamily: String = "Avenir Next",
  bodyText: String = "Caret body",
  _ check: @MainActor (AppState, NSWindow, NSHostingView<AnyView>, NSTextField, ListAwareTextView) async throws -> Void
) async throws {
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: titleText, body: bodyText, folderID: nil)
    let state = await hostedPanelState(
      root: root,
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    state.updatePreferences {
      $0.accentHex = "#FFD600"
      $0.fontFamily = fontFamily
    }
    let (window, host) = hostedPanel(root: root, state: state, commands: EditorCommands(), isPinned: isPinned)
    defer { window.orderOut(nil) }
    window.appearance = NSAppearance(named: appearance)
    await settleHostedView(host)
    let titleField = try #require(hostedPanelTitleField(with: note.title, in: host))
    let bodyEditor = try #require(hostedPanelEditor(in: host))
    try await check(state, window, host, titleField, bodyEditor)
    window.makeFirstResponder(nil)
  }
}

@Test @MainActor func hostedNotesPanelTitleEditingUsesRealFieldEditor() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let title = "Original title"
  let text = "Body stays exactly the same"
  let note = Note(
    title: title,
    body: text,
    richTextRTF: try hostedPanelRTF(text: text),
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let bodyEditor = try #require(hostedPanelEditor(in: host))
  let titleField = try #require(hostedPanelTitleField(with: title, in: host))
  let selectedNoteID = try #require(state.workspace.selectedNoteID)
  let originalNote = try #require(
    state.workspace.notes.first(where: { $0.id == selectedNoteID })
  )
  let originalBody = originalNote.body
  let originalRichTextRTF = originalNote.richTextRTF
  let newTitle = "Edited through AppKit"

  #expect(commands.textView === bodyEditor)
  #expect(window.makeFirstResponder(titleField))
  let fieldEditor = try #require(window.fieldEditor(false, for: titleField) as? NSTextView)
  #expect(window.firstResponder === fieldEditor)
  #expect(fieldEditor !== titleField)

  fieldEditor.selectAll(nil)
  fieldEditor.insertText(newTitle, replacementRange: fieldEditor.selectedRange())
  await settleHostedView(host)

  let editedNote = try #require(
    state.workspace.notes.first(where: { $0.id == selectedNoteID })
  )
  #expect(editedNote.title == newTitle)
  #expect(editedNote.body == originalBody)
  #expect(editedNote.richTextRTF == originalRichTextRTF)
  #expect(state.workspace.selectedNoteID == selectedNoteID)
  #expect(commands.textView === bodyEditor)
}

@Test @MainActor func hostedCompactUnfiledKeepsNamedFolderPillInsideNavigator() async throws {
  let unfiledRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let namedRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer {
    try? FileManager.default.removeItem(at: unfiledRoot)
    try? FileManager.default.removeItem(at: namedRoot)
  }
  let folder = try Folder(id: UUID(), name: "SoftwareDev")
  let unfiledNote = Note(title: "Selected Unfiled", body: "Body")
  let namedNote = Note(
    title: "Selected folder render",
    body: "Body",
    folderID: folder.id
  )
  let unfiledWorkspace = Workspace(
    notes: [unfiledNote, namedNote],
    selectedNoteID: unfiledNote.id,
    folders: [folder]
  )
  var namedWorkspace = unfiledWorkspace
  namedWorkspace.selectedNoteID = namedNote.id
  let accentHex = "#00FF00"
  let unfiledPill = try await hostedFolderSelectionGeometry(
    root: unfiledRoot,
    workspace: unfiledWorkspace,
    accentHex: accentHex
  )
  let namedPill = try await hostedFolderSelectionGeometry(
    root: namedRoot,
    workspace: namedWorkspace,
    accentHex: accentHex
  )

  let navigatorBand = CGRect(x: 0, y: 42, width: 640, height: 40)
  let windowBounds = CGRect(x: 0, y: 0, width: 640, height: 430)
  for pill in [unfiledPill, namedPill] {
    #expect(navigatorBand.contains(pill.bounds))
    #expect(windowBounds.contains(pill.bounds))
    #expect(pill.bounds.width >= 24)
    #expect(pill.bounds.height >= 24)
    #expect(pill.bounds.height <= 33)
    #expect(pill.pixelCount >= 32)
    #expect(pill.bounds.minX >= 4)
    #expect(pill.bounds.maxX <= 636)
  }

  #expect(abs(namedPill.bounds.minY - unfiledPill.bounds.minY) <= 2)
  #expect(abs(namedPill.bounds.height - unfiledPill.bounds.height) <= 5)
  #expect(namedPill.bounds.width > unfiledPill.bounds.width)

  let focusDestination = FolderNavigatorFocus.nextIndex(
    currentIndex: 0,
    direction: .down,
    count: 2
  )
  #expect(focusDestination == 1)
  #expect(unfiledWorkspace.selectedNoteID == unfiledNote.id)

  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  #expect(navigator.contains(".focused($focusedRow, equals: .unfiled)"))
  #expect(navigator.contains(".focused($focusedRow, equals: .folder(folder.id))"))
  #expect(navigator.contains(".onMoveCommand { direction in"))
  #expect(navigator.contains("moveFocus(direction)"))
  #expect(navigator.contains("isSelected: activeFolderID == nil"))
  #expect(navigator.contains("isSelected: activeFolderID == folder.id"))
  let rowLabel = try #require(navigator.range(of: "private func rowLabel("))
  let rowLabelBody = navigator[rowLabel.lowerBound...]
  let rootRow = try #require(
    navigator.components(separatedBy: "private var rootRow").last?
      .components(separatedBy: "@ViewBuilder\n    private func folderRow").first
  )
  let folderRow = try #require(
    navigator.components(separatedBy: "private func folderRow").last?
      .components(separatedBy: "private struct FolderActionButtonStyle").first
  )
  #expect(rowLabelBody.contains("RoundedRectangle(cornerRadius: 6)"))
  #expect(rowLabelBody.contains("isSelected ? Color.accentColor.opacity(0.18)"))
  #expect(rootRow.contains("isFocused: focusedRow == .unfiled"))
  #expect(folderRow.contains("isFocused: focusedRow == .folder(folder.id)"))
  #expect(rootRow.contains(".focusEffectDisabled()"))
  #expect(folderRow.contains(".focusEffectDisabled()"))
  let rootFocused = try #require(
    rootRow.range(of: ".focused($focusedRow, equals: .unfiled)")
  )
  let rootFocusable = try #require(rootRow.range(of: ".focusable()"))
  let folderFocused = try #require(
    folderRow.range(of: ".focused($focusedRow, equals: .folder(folder.id))")
  )
  let folderFocusable = try #require(folderRow.range(of: ".focusable()"))
  #expect(rootFocusable.lowerBound < rootFocused.lowerBound)
  #expect(folderFocusable.lowerBound < folderFocused.lowerBound)
  #expect(rowLabelBody.contains("isFocused: Bool"))
  #expect(rowLabelBody.contains("isFocused && !isSelected"))
  #expect(rowLabelBody.contains(".overlay"))
  #expect(
    rowLabelBody.contains(
      ".strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)"
    )
  )
}

@Test @MainActor func hostedUnfiledDisclosureKeepsFolderToolbarFramesStable() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = try Folder(id: UUID(), name: "School")
  let unfiledNote = Note(title: "Unfiled note", body: "Body")
  let folderNote = Note(
    title: "School note",
    body: "Body",
    folderID: folder.id
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(
      notes: [unfiledNote, folderNote],
      selectedNoteID: unfiledNote.id,
      folders: [folder]
    )
  )
  state.updatePreferences {
    $0.accentHex = "#00FF00"
    $0.isUnfiledCompact = true
    $0.showFormattingBar = false
  }
  let commands = EditorCommands()
  let (window, host) = hostedPanel(
    root: root,
    state: state,
    commands: commands,
    accentHex: "#00FF00"
  )
  window.appearance = NSAppearance(named: .darkAqua)
  defer { window.orderOut(nil) }
  await settleHostedView(host)
  let editor = try #require(hostedPanelEditor(in: host))
  #expect(window.makeFirstResponder(editor))
  await settleHostedView(host)

  let before = hostedNavigatorKeyViewFrames(in: host)
  let beforeFolderFrame = try #require(hostedSchoolFolderFrame(in: host))
  let beforeHostSize = host.bounds.size
  let beforeEditorFrame = host.convert(editor.bounds, from: editor)
  let unfiledControl = try #require(hostedNavigatorKeyViews(in: host).first)
  let unfiledFrame = unfiledControl.convert(unfiledControl.bounds, to: host)
  #expect(
    !before.contains { frame in
      abs(frame.width - 28) < 0.5 && abs(frame.height - 28) < 0.5
    }
  )
  #expect(window.makeFirstResponder(unfiledControl))
  await settleHostedView(host)
  let focused = hostedNavigatorKeyViewFrames(in: host)
  let focusedFolderFrame = try #require(hostedSchoolFolderFrame(in: host))

  #expect(state.preferences.isUnfiledCompact)
  #expect(focused.count == before.count)
  #expect(focusedFolderFrame.minX == beforeFolderFrame.minX + 28)
  #expect(focusedFolderFrame.minY == beforeFolderFrame.minY)
  #expect(host.bounds.size == beforeHostSize)
  #expect(host.convert(editor.bounds, from: editor) == beforeEditorFrame)

  try sendHostedClick(
    at: NSPoint(x: unfiledFrame.maxX + 14, y: unfiledFrame.midY),
    in: host,
    to: window
  )
  forceHostedViewUpdate(host)
  let expandingFolderFrame = try #require(hostedSchoolFolderFrame(in: host))
  try await Task.sleep(for: .milliseconds(300))
  await settleHostedView(host)
  let expandedFolderFrame = try #require(hostedSchoolFolderFrame(in: host))

  #expect(!state.preferences.isUnfiledCompact)
  #expect(expandingFolderFrame == expandedFolderFrame)
  #expect(host.bounds.size == beforeHostSize)
  #expect(host.convert(editor.bounds, from: editor) == beforeEditorFrame)
}

@Test @MainActor func hostedFolderKeyboardFocusAddsOutlineToUnselectedRow() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = try Folder(id: UUID(), name: "School")
  let note = Note(title: "Selected Unfiled", body: "Body")
  let folderNote = Note(
    title: "Selected School",
    body: "Body",
    folderID: folder.id
  )
  let workspace = Workspace(
    notes: [note, folderNote],
    selectedNoteID: note.id,
    folders: [folder]
  )
  let state = await hostedPanelState(root: root, workspace: workspace)
  state.updatePreferences {
    $0.accentHex = "#00FF00"
    $0.isUnfiledCompact = false
    $0.showFormattingBar = false
  }
  let commands = EditorCommands()
  let (window, host) = hostedPanel(
    root: root,
    state: state,
    commands: commands,
    accentHex: "#00FF00"
  )
  window.appearance = NSAppearance(named: .darkAqua)
  defer { window.orderOut(nil) }
  await settleHostedView(host)

  try sendHostedClick(at: NSPoint(x: 40, y: 60), in: host, to: window)
  await settleHostedView(host)

  let before = try hostedNavigatorAccentGeometry(
    in: host,
    accentHex: "#00FF00"
  )
  try sendHostedKeyDown("\t", keyCode: 48, to: window)
  await settleHostedView(host)
  let after = try hostedNavigatorAccentGeometry(
    in: host,
    accentHex: "#00FF00"
  )

  #expect(after.pixelCount > before.pixelCount)

  try sendHostedKeyDown("\r", keyCode: 36, to: window)
  await settleHostedView(host)
  #expect(state.workspace.selectedNoteID == folderNote.id)
}

private struct HostedAccentPillGeometry {
  let bounds: CGRect
  let pixelCount: Int
}

@MainActor
private func hostedFolderSelectionGeometry(
  root: URL,
  workspace: Workspace,
  accentHex: String
) async throws -> HostedAccentPillGeometry {
  let state = await hostedPanelState(root: root, workspace: workspace)
  state.updatePreferences {
    $0.accentHex = accentHex
    $0.isUnfiledCompact = true
    $0.showFormattingBar = false
  }
  let commands = EditorCommands()
  let (window, host) = hostedPanel(
    root: root,
    state: state,
    commands: commands,
    accentHex: accentHex
  )
  window.appearance = NSAppearance(named: .darkAqua)
  defer { window.orderOut(nil) }
  await settleHostedView(host)

  let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: imageRep)
  return try #require(
    hostedAccentFillBounds(
      in: imageRep,
      hostSize: host.bounds.size,
      accentHex: accentHex
    )
  )
}

@MainActor
private func hostedNavigatorAccentGeometry(
  in host: NSHostingView<AnyView>,
  accentHex: String
) throws -> HostedAccentPillGeometry {
  let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: imageRep)
  return try #require(
    hostedAccentFillBounds(
      in: imageRep,
      hostSize: host.bounds.size,
      accentHex: accentHex
    )
  )
}

@Test @MainActor func hostedNotesPanelEvacuatesTitleFocusWithoutRestoringBody() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let work = try Folder(id: UUID(), name: "Work")
  let text = "Title focus stays inert"
  let note = Note(
    title: "Title focus",
    body: text,
    richTextRTF: try hostedPanelRTF(text: text),
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [work])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let editor = try #require(hostedPanelEditor(in: host))
  let titleField = try #require(hostedPanelTitleField(with: note.title, in: host))
  let expectedRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: text.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let expectedSelection = editor.selectedRange()

  #expect(window.makeFirstResponder(titleField))
  let titleResponder = try #require(window.firstResponder)
  #expect(titleResponder !== editor)

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: work.id)
  await settleHostedView(host)

  #expect(window.firstResponder !== titleResponder)
  #expect(window.firstResponder !== editor)
  #expect(editor.string == text)
  #expect(editor.selectedRange() == expectedSelection)
  #expect(state.workspace.notes.first?.body == text)
  #expect(state.workspace.notes.first?.richTextRTF == expectedRTF)

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: nil)
  await settleHostedView(host)

  #expect(hostedPanelEditor(in: host) === editor)
  #expect(commands.textView === editor)
  #expect(window.firstResponder !== editor)
  #expect(window.firstResponder !== titleResponder)
  #expect(editor.string == text)
  #expect(state.workspace.notes.first?.richTextRTF == expectedRTF)
}

@Test @MainActor func hostedNotesPanelHiddenFormattingAndUndoRemainInertAcrossRefresh() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let work = try Folder(id: UUID(), name: "Work")
  let text = "Formatting remains unchanged"
  let note = Note(
    title: "Formatting",
    body: text,
    richTextRTF: try hostedPanelRTF(text: text),
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [work])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let editor = try #require(hostedPanelEditor(in: host))
  editor.setSelectedRange(NSRange(location: 2, length: 9))
  editor.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.applyBackgroundColor(.systemYellow)
  let expectedAttributed = NSAttributedString(attributedString: try #require(editor.textStorage))
  let expectedText = editor.string
  let expectedSelection = editor.selectedRange()
  let expectedTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let expectedRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: expectedText.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let expectedCanUndo = try #require(editor.undoManager).canUndo
  let expectedCanRedo = editor.undoManager?.canRedo ?? false
  #expect(expectedCanUndo)
  #expect(window.makeFirstResponder(editor))

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: work.id)
  await settleHostedView(host)
  let hiddenWorkspace = state.workspace

  try sendHostedKeyEquivalent("b", keyCode: 11, modifiers: [.command], to: window)
  try sendHostedKeyEquivalent("z", keyCode: 6, modifiers: [.command], to: window)
  commands.toggleBold()
  commands.undo()

  #expect(commands.textView == nil)
  #expect(state.workspace == hiddenWorkspace)
  #expect(editor.string == expectedText)
  #expect(editor.selectedRange() == expectedSelection)
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: expectedAttributed))
  #expect(
    NSDictionary(dictionary: editor.typingAttributes)
      .isEqual(to: expectedTypingAttributes)
  )
  let hiddenRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: expectedText.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  #expect(hiddenRTF == expectedRTF)
  #expect(editor.undoManager?.canUndo == expectedCanUndo)
  #expect(editor.undoManager?.canRedo == expectedCanRedo)

  state.saveError = "unrelated refresh"
  await settleHostedView(host)
  try sendHostedKeyEquivalent("b", keyCode: 11, modifiers: [.command], to: window)
  commands.toggleBold()
  commands.undo()

  #expect(commands.textView == nil)
  #expect(state.workspace == hiddenWorkspace)
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: expectedAttributed))
  #expect(editor.selectedRange() == expectedSelection)
  #expect(editor.undoManager?.canUndo == expectedCanUndo)
  #expect(editor.undoManager?.canRedo == expectedCanRedo)

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: nil)
  await settleHostedView(host)
  #expect(hostedPanelEditor(in: host) === editor)
  #expect(commands.textView === editor)
  #expect(window.firstResponder === editor)
  commands.toggleItalic()
  #expect(
    fontTraits(try #require(editor.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont))
      .contains(.italicFontMask)
  )
  commands.undo()
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: expectedAttributed))
}

@Test @MainActor func hostedNotesPanelCancelsFocusedDictationAtHiddenScopeBoundary() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let work = try Folder(id: UUID(), name: "Work")
  let text = "Focused dictation remains scoped"
  let note = Note(title: "Dictation", body: text, folderID: nil)
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [work])
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)
  let editor = try #require(hostedPanelEditor(in: host))
  editor.setSelectedRange(NSRange(location: 8, length: 0))
  let originalAttributed = NSAttributedString(attributedString: try #require(editor.textStorage))
  let originalSelection = editor.selectedRange()
  let originalTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let originalRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: text.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  #expect(window.makeFirstResponder(editor))

  #expect(commands.beginFocusedDictation())
  #expect(commands.isFocusedDictationActive)
  setHostedPanelNoteFolder(state, noteID: note.id, folderID: work.id)
  await settleHostedView(host)

  #expect(!commands.isFocusedDictationActive)
  #expect(commands.textView == nil)
  commands.updateFocusedDictation(provisionalText: "late provisional")
  #expect(commands.commitFocusedDictation(text: "late commit") == nil)
  #expect(editor.string == text)
  #expect(editor.selectedRange() == originalSelection)
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: originalAttributed))
  #expect(
    NSDictionary(dictionary: editor.typingAttributes)
      .isEqual(to: originalTypingAttributes)
  )
  let hiddenRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: text.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  #expect(hiddenRTF == originalRTF)

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: nil)
  await settleHostedView(host)
  #expect(commands.textView === editor)
  #expect(commands.canBeginFocusedDictation)
  #expect(commands.beginFocusedDictation())
  commands.updateFocusedDictation(provisionalText: "temporary provisional")
  #expect(editor.string != text)

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: work.id)
  await settleHostedView(host)

  #expect(!commands.isFocusedDictationActive)
  #expect(commands.textView == nil)
  commands.updateFocusedDictation(provisionalText: "late replacement")
  #expect(commands.commitFocusedDictation(text: "late commit") == nil)
  #expect(editor.string == text)
  #expect(editor.selectedRange() == originalSelection)
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: originalAttributed))

  setHostedPanelNoteFolder(state, noteID: note.id, folderID: nil)
  await settleHostedView(host)
  #expect(commands.textView === editor)
  #expect(commands.canBeginFocusedDictation)
  #expect(commands.beginFocusedDictation())
  commands.cancelFocusedDictation()
}

@Test @MainActor func hostedNotesPanelStaleHiddenBoundaryCannotDetachNewVisibleEditor() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let work = try Folder(id: UUID(), name: "Work")
  let firstText = "First note remains unchanged"
  let secondText = "Second note remains usable"
  let first = Note(
    title: "First",
    body: firstText,
    richTextRTF: try hostedPanelRTF(text: firstText),
    folderID: nil
  )
  let second = Note(
    title: "Second",
    body: secondText,
    richTextRTF: try hostedPanelRTF(text: secondText),
    folderID: nil
  )
  let state = await hostedPanelState(
    root: root,
    workspace: Workspace(
      notes: [first, second],
      selectedNoteID: first.id,
      folders: [work]
    )
  )
  let commands = EditorCommands()
  let (window, host) = hostedPanel(root: root, state: state, commands: commands)
  await settleHostedView(host)

  let firstEditor = try #require(hostedPanelEditor(in: host))
  let firstWorkspace = state.workspace
  #expect(commands.textView === firstEditor)
  #expect(window.makeFirstResponder(firstEditor))

  var secondEditor: ListAwareTextView?
  var secondFocusWasSet = false
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async {
      setHostedPanelNoteFolder(state, noteID: first.id, folderID: work.id)
      forceHostedViewUpdate(host)
    }
    DispatchQueue.main.async {
      setHostedPanelSelectedNote(state, noteID: second.id)
      forceHostedViewUpdate(host)
      if let candidate = hostedPanelEditor(in: host), candidate.string == secondText {
        secondEditor = candidate
        secondFocusWasSet = window.makeFirstResponder(candidate)
      }
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }

  let visibleEditor = try #require(secondEditor)
  let secondWorkspace = state.workspace
  let secondAttributed = NSAttributedString(attributedString: try #require(visibleEditor.textStorage))
  let secondRTF = try visibleEditor.textStorage?.data(
    from: NSRange(location: 0, length: secondText.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )

  #expect(visibleEditor !== firstEditor)
  #expect(secondFocusWasSet)
  #expect(window.firstResponder === visibleEditor)
  #expect(commands.textView === visibleEditor)
  #expect(visibleEditor.string == secondText)
  #expect(state.workspace.notes.first(where: { $0.id == first.id })?.body == firstText)
  #expect(state.workspace.notes.first(where: { $0.id == second.id })?.body == secondText)
  #expect(state.workspace.notes.first(where: { $0.id == first.id })?.richTextRTF == firstWorkspace.notes.first?.richTextRTF)
  #expect(state.workspace == secondWorkspace)

  visibleEditor.setSelectedRange(NSRange(location: 1, length: 6))
  commands.toggleItalic()
  #expect(
    fontTraits(try #require(visibleEditor.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont))
      .contains(.italicFontMask)
  )
  commands.undo()
  #expect(NSAttributedString(attributedString: try #require(visibleEditor.textStorage)).isEqual(to: secondAttributed))
  #expect(try visibleEditor.textStorage?.data(
    from: NSRange(location: 0, length: secondText.utf16.count),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  ) == secondRTF)
  #expect(commands.canBeginFocusedDictation)
  #expect(commands.beginFocusedDictation())
  commands.cancelFocusedDictation()
}

@MainActor
private func hostedDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = hostedDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func hostedNavigatorKeyViewFrames(in view: NSView) -> [CGRect] {
  hostedNavigatorKeyViews(in: view).map { $0.convert($0.bounds, to: view) }
}

@MainActor
private func hostedSchoolFolderFrame(in view: NSView) -> CGRect? {
  hostedNavigatorKeyViewFrames(in: view).first { abs($0.width - 108) < 0.5 }
}

@MainActor
private func hostedNavigatorKeyViews(in view: NSView) -> [NSView] {
  var views: [NSView] = []
  func collect(_ candidate: NSView) {
    if String(describing: type(of: candidate)) == "KeyViewProxy" {
      let frame = candidate.convert(candidate.bounds, to: view)
      if frame.minY >= 42, frame.maxY <= 82 {
        views.append(candidate)
      }
    }
    for subview in candidate.subviews { collect(subview) }
  }
  collect(view)
  return views.sorted { lhs, rhs in
    let lhsFrame = lhs.convert(lhs.bounds, to: view)
    let rhsFrame = rhs.convert(rhs.bounds, to: view)
    if lhsFrame.minX == rhsFrame.minX { return lhsFrame.width < rhsFrame.width }
    return lhsFrame.minX < rhsFrame.minX
  }
}

@MainActor
private func settleHostedView(_ view: NSView) async {
  for _ in 0..<5 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func forceHostedViewUpdate(_ view: NSView) {
  view.layoutSubtreeIfNeeded()
  view.displayIfNeeded()
}

private struct HostedTitleBodyGeometry {
  let titleFrame: CGRect
  let titleRenderRect: CGRect
  let firstBodyLineRect: CGRect

  var renderedGap: CGFloat {
    firstBodyLineRect.minY - titleFrame.maxY
  }

  var renderedTitleMinY: CGFloat {
    titleRenderRect.minY
  }
}

private func notesPanelSource() throws -> String {
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
private func hostedPanelState(root: URL, workspace: Workspace) async -> AppState {
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = workspace
  return state
}

@MainActor
private func hostedPanel(
  root: URL,
  state: AppState,
  commands: EditorCommands,
  accentHex: String? = nil,
  isPinned: Bool = false
) -> (NSWindow, NSHostingView<AnyView>) {
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let panel = NotesPanel(dictationRuntime: runtime, isPinned: isPinned, editorCommands: commands)
  let rootView: AnyView
  if let accentHex, let accent = Color(hex: accentHex) {
    rootView = AnyView(panel.environmentObject(state).accentColor(accent))
  } else {
    rootView = AnyView(panel.environmentObject(state))
  }
  let host = NSHostingView(rootView: rootView)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  return (window, host)
}

@MainActor
private func hostedPanelEditor(in view: NSView) -> ListAwareTextView? {
  if let editor = view as? ListAwareTextView { return editor }
  for subview in view.subviews {
    if let editor = hostedPanelEditor(in: subview) { return editor }
  }
  return nil
}

@MainActor
private func hostedPanelBodyScrollView(in view: NSView) -> NSScrollView? {
  if let scrollView = view as? NSScrollView,
    let documentView = scrollView.documentView,
    hostedDescendant(in: documentView, as: ListAwareTextView.self) != nil {
    return scrollView
  }
  for subview in view.subviews {
    if let scrollView = hostedPanelBodyScrollView(in: subview) { return scrollView }
  }
  return nil
}

@MainActor
private func hostedVerticalScrollView(containing view: NSView) -> NSScrollView? {
  var current: NSView? = view
  while let candidate = current {
    if let scrollView = candidate as? NSScrollView, scrollView.hasVerticalScroller {
      return scrollView
    }
    current = candidate.superview
  }
  return nil
}

@MainActor
private func hostedPanelTitleField(with value: String, in view: NSView) -> NSTextField? {
  if let field = view as? NSTextField,
    field.stringValue == value,
    field.placeholderString == "Note title"
  {
    return field
  }
  for subview in view.subviews {
    if let field = hostedPanelTitleField(with: value, in: subview) { return field }
  }
  return nil
}

@MainActor
private func hostedPanelRTF(text: String) throws -> Data {
  let attributed = NSMutableAttributedString(string: text)
  let range = NSRange(location: 0, length: text.utf16.count)
  attributed.addAttributes(
    [.font: try #require(NSFont(name: "Helvetica-Bold", size: 18)), .foregroundColor: NSColor.systemRed],
    range: range
  )
  return try attributed.data(
    from: range,
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
}

@MainActor
private func hostedAccentFillBounds(
  in imageRep: NSBitmapImageRep,
  hostSize: CGSize,
  accentHex: String
) -> HostedAccentPillGeometry? {
  guard hostSize.width > 0, hostSize.height > 0,
    let accent = NSColor(hex: accentHex)?.usingColorSpace(.sRGB)
  else { return nil }

  var accentRed: CGFloat = 0
  var accentGreen: CGFloat = 0
  var accentBlue: CGFloat = 0
  var accentAlpha: CGFloat = 0
  accent.getRed(
    &accentRed,
    green: &accentGreen,
    blue: &accentBlue,
    alpha: &accentAlpha
  )
  guard accentRed < 0.01, accentGreen > 0.99, accentBlue < 0.01 else { return nil }

  let scaleX = CGFloat(imageRep.pixelsWide) / hostSize.width
  let scaleY = CGFloat(imageRep.pixelsHigh) / hostSize.height
  let bandTop: CGFloat = 42
  let bandBottom: CGFloat = 82
  let bandStart = max(0, Int(floor(bandTop * scaleY)))
  let bandEnd = min(imageRep.pixelsHigh, Int(ceil(bandBottom * scaleY)))
  guard bandStart < bandEnd else { return nil }
  var matchCount = 0
  var minX = Int.max
  var minY = Int.max
  var maxX = Int.min
  var maxY = Int.min

  for y in bandStart..<bandEnd {
    for x in 0..<imageRep.pixelsWide {
      guard let color = imageRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
      else { continue }
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0
      color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      guard alpha > 0.5 else { continue }
      guard green > 0.05, green > red + 0.05, green > blue + 0.05 else { continue }
      matchCount += 1
      minX = min(minX, x)
      minY = min(minY, y)
      maxX = max(maxX, x)
      maxY = max(maxY, y)
    }
  }

  let minimumPixels = max(32, Int(20 * scaleX * scaleY))
  guard matchCount >= minimumPixels else { return nil }
  return HostedAccentPillGeometry(
    bounds: CGRect(
      x: CGFloat(minX) / scaleX,
      y: CGFloat(minY) / scaleY,
      width: CGFloat(maxX - minX + 1) / scaleX,
      height: CGFloat(maxY - minY + 1) / scaleY
    ),
    pixelCount: matchCount
  )
}

@MainActor
private func setHostedPanelNoteFolder(_ state: AppState, noteID: UUID, folderID: UUID?) {
  var workspace = state.workspace
  guard let index = workspace.notes.firstIndex(where: { $0.id == noteID }) else { return }
  workspace.notes[index].folderID = folderID
  state.workspace = workspace
}

@MainActor
private func setHostedPanelSelectedNote(_ state: AppState, noteID: UUID) {
  var workspace = state.workspace
  workspace.selectedNoteID = noteID
  state.workspace = workspace
}

@MainActor
private func sendHostedKeyEquivalent(
  _ characters: String,
  keyCode: UInt16,
  modifiers: NSEvent.ModifierFlags,
  to window: NSWindow
) throws {
  let event = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )
  )
  _ = window.performKeyEquivalent(with: event)
}

@MainActor
private func sendHostedClick(
  at point: NSPoint,
  in host: NSView,
  to window: NSWindow
) throws {
  let location = host.convert(point, to: nil)
  for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    let event = try #require(
      NSEvent.mouseEvent(
        with: eventType,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: eventType == .leftMouseDown ? 1 : 0
      )
    )
    window.sendEvent(event)
  }
}

@MainActor
private func sendHostedKeyDown(
  _ characters: String,
  keyCode: UInt16,
  to window: NSWindow
) throws {
  let event = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )
  )
  window.sendEvent(event)
}

@Test @MainActor func tabColorSwatchesAreNonTemplateImages() {
  for option in FleckPaletteOption.all {
    #expect(option.swatchImage?.isTemplate == false)
  }
}

@Test @MainActor func tabColorPaletteMatchesMacOSDarkAppearance() {
  let expectedHexByName = [
    "Red": "#FF4245",
    "Orange": "#FF9230",
    "Yellow": "#FFD600",
    "Green": "#30D158",
    "Blue": "#0091FF",
    "Purple": "#DB34F2",
    "Pink": "#FF375F",
    "Gray": "#98989D",
  ]

  for option in FleckPaletteOption.all {
    #expect(option.hex == expectedHexByName[option.name])
  }
}

@Test @MainActor func fontPickerHostedSelectionSearchCancelAndUndo() throws {
  let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
  let textView = NSTextView()
  window.contentView = textView
  textView.allowsUndo = true
  textView.textStorage?.setAttributedString(NSAttributedString(string: "ABCD", attributes: [.font: NSFont.systemFont(ofSize: 17)]))
  textView.setSelectedRange(NSRange(location: 1, length: 2))
  window.makeFirstResponder(textView)
  let original = NSAttributedString(attributedString: try #require(textView.textStorage))
  let commands = EditorCommands()
  commands.textView = textView
  let note = Note(body: "ABCD")
  let target = try #require(FontPickerTarget(note: note, isTitle: false, commands: commands))
  var cancelled = false
  let picker = FontFamilyPickerController(currentFamily: nil, isMixed: true, targetLabel: target.label, onCommit: { _ in Issue.record("Cancelled picker committed") }, onCancel: { cancelled = true })
  picker.loadViewIfNeeded()
  let host = NSWindow(contentRect: .init(x: 0, y: 0, width: 280, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
  host.contentViewController = picker
  host.makeFirstResponder(picker.searchField)
  picker.searchField.stringValue = "no such font"
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  picker.cancelOperation(nil)
  #expect(cancelled)
  #expect(textView.textStorage == original)
  #expect(textView.selectedRange() == NSRange(location: 1, length: 2))
  #expect(target.apply("Courier", note: note, isEditorVisible: true, commands: commands, titleMutation: { _ in Issue.record("Body routed to title") }))
  #expect((textView.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.familyName == "Courier")
  #expect(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NSFont.systemFont(ofSize: 17))
  try #require(textView.undoManager).undo()
  #expect(textView.textStorage == original)
  try #require(textView.undoManager).redo()
  #expect((textView.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.familyName == "Courier")
}

@Test @MainActor func fontPickerRejectsLiveBodyEditOrRangeChange() throws {
  let textView = NSTextView()
  textView.string = "ABCD"
  let commands = EditorCommands()
  commands.textView = textView
  let note = Note(body: "ABCD")
  for change in [{ textView.insertText("X", replacementRange: NSRange(location: 0, length: 1)) }, { textView.setSelectedRange(NSRange(location: 3, length: 0)) }] {
    textView.setSelectedRange(NSRange(location: 0, length: 2))
    let target = try #require(FontPickerTarget(note: note, isTitle: false, commands: commands))
    change()
    #expect(!target.apply("Courier", note: note, isEditorVisible: true, commands: commands, titleMutation: { _ in }))
  }
}

// SwiftUI accessibility nodes expose the informal AppKit API, not NSAccessibilityProtocol.
@MainActor private func fontPickerAccessibilityElement(_ value: Any, label: String) -> NSObject? {
  guard let element = value as? NSObject else { return nil }
  let labelSelector = NSSelectorFromString("accessibilityLabel")
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let name = element.responds(to: labelSelector)
    ? element.perform(labelSelector)?.takeUnretainedValue() as? String : nil
  if name == label { return element }
  let children = element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in children ?? [] {
    if let found = fontPickerAccessibilityElement(child, label: label) { return found }
  }
  return nil
}

@Test @MainActor func fontPickerHostedToolbarRetainsTitleAndBodyTargets() async throws {
  NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
  for isTitle in [true, false] {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: "Font picker fixture", body: "Body selection", richTextRTF: try hostedPanelRTF(text: "Body selection"), titleFontFamily: "Avenir Next")
    let state = await hostedPanelState(root: root, workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: []))
    let commands = EditorCommands()
    let (window, host) = hostedPanel(root: root, state: state, commands: commands, isPinned: isTitle)
    defer { window.orderOut(nil) }
    if !isTitle { window.setContentSize(NSSize(width: 390, height: 430)) }
    await settleHostedView(host)
    let body = try #require(hostedPanelEditor(in: host))
    if isTitle {
      let titleField = try #require(hostedPanelTitleField(with: note.title, in: host))
      #expect(window.makeFirstResponder(titleField))
    } else {
      #expect(window.makeFirstResponder(body))
      body.setSelectedRange(NSRange(location: 0, length: 4))
    }
    await settleHostedView(host)
    let before = try #require(state.selectedNote)
    let button = try #require(fontPickerAccessibilityElement(host, label: "Font"))
    if isTitle {
      let value = button.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String
      #expect(value == "Avenir Next")
    }
    _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleHostedView(host)
    let searchFields: [NSSearchField] = NSApplication.shared.windows.filter(\.isVisible).compactMap { window -> NSSearchField? in
      guard let content = window.contentView else { return nil }
      return hostedDescendant(in: content, as: NSSearchField.self)
    }
    let search = try #require(searchFields.first(where: { $0.placeholderString == "Search fonts" }))
    let picker = try #require(search.delegate as? FontFamilyPickerController)
    search.stringValue = "Menlo"
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    #expect(state.selectedNote == before)
    let searchEditor = try #require(search.currentEditor() as? NSTextView)
    #expect(picker.control(search, textView: searchEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    await settleHostedView(host)
    let capture = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: capture)
    let captureData = try #require(capture.representation(using: .png, properties: [:]))
    let captureName = isTitle ? "phase2-font-pinned-host.png" : "phase2-font-narrow-host.png"
    try captureData.write(to: fontPickerEvidenceDirectory().appendingPathComponent(captureName))
    if isTitle {
      #expect(state.selectedNote?.titleFontFamily == "Menlo")
      #expect(state.selectedNote?.richTextRTF == before.richTextRTF)
    } else {
      #expect(state.selectedNote?.titleFontFamily == before.titleFontFamily)
      #expect((body.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == "Menlo")
      #expect(body.selectedRange() == NSRange(location: 0, length: 4))
    }
    let updated = try #require(state.selectedNote)
    _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleHostedView(host)
    let reopenedPickers: [FontFamilyPickerController] = NSApplication.shared.windows.filter(\.isVisible).compactMap { window in
      guard let content = window.contentView,
        let search = hostedDescendant(in: content, as: NSSearchField.self)
      else { return nil }
      return search.delegate as? FontFamilyPickerController
    }
    let reopenedPicker = try #require(reopenedPickers.first)
    let other = Note(title: "Other note", body: "Unchanged")
    state.workspace.notes.append(other)
    state.workspace.selectedNoteID = other.id
    await settleHostedView(host)
    reopenedPicker.commitSelection()
    #expect(reopenedPicker.view.window?.isVisible != true)
    #expect(state.selectedNote == other)
    #expect(state.workspace.notes.first(where: { $0.id == updated.id }) == updated)
  }
}

@Test @MainActor func fontPickerTitleUndoTargetsOriginalNoteAfterSelectionSwitch() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let original = Note(title: "Original")
  let other = Note(title: "Other", titleFontFamily: "Avenir Next")
  let state = await hostedPanelState(root: root, workspace: Workspace(notes: [original, other], selectedNoteID: original.id, folders: []))
  let undo = UndoManager()
  undo.groupsByEvent = false
  undo.beginUndoGrouping()
  state.setTitleFontFamily("Menlo", noteID: original.id, undoManager: undo)
  undo.endUndoGrouping()
  #expect(state.selectedNote?.titleFontFamily == "Menlo")
  state.workspace.selectedNoteID = other.id
  #expect(undo.canUndo)
  undo.undo()
  #expect(state.workspace.notes.first(where: { $0.id == original.id })?.titleFontFamily == nil)
  #expect(state.selectedNote?.titleFontFamily == "Avenir Next")
  undo.redo()
  #expect(state.workspace.notes.first(where: { $0.id == original.id })?.titleFontFamily == "Menlo")
  #expect(state.selectedNote?.titleFontFamily == "Avenir Next")
}

@Test @MainActor func fontPickerTableKeyboardReturnAndEscape() throws {
  var committed: [String] = []
  var cancelled = false
  let picker = FontFamilyPickerController(currentFamily: "Menlo", isMixed: false, targetLabel: "New text", onCommit: { committed.append($0) }, onCancel: { cancelled = true })
  let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 280, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
  window.contentViewController = picker
  let table = try #require(hostedDescendant(in: picker.view, as: NSTableView.self))
  window.makeFirstResponder(table)
  let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
  table.keyDown(with: enter)
  #expect(committed == ["Menlo"])
  let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
  table.keyDown(with: escape)
  #expect(cancelled)
}
