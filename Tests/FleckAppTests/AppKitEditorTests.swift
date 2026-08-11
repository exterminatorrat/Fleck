import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

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
  scrollView.documentView = textView
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
  textView.font = .systemFont(ofSize: 16)
  textView.string = "○ Task"
  textView.layoutManager?.ensureLayout(for: try #require(textView.textContainer))

  let markerRange = NSRange(location: 0, length: 1)
  let markerRect = try #require(textView.checklistMarkerRect(for: markerRange))
  let hitRect = try #require(textView.checklistHitRect(for: markerRange))

  #expect(hitRect.contains(NSPoint(x: markerRect.midX, y: markerRect.midY)))
  #expect(hitRect.width > markerRect.width)
  #expect(hitRect.height > markerRect.height)
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

@Test func formattingBarKeepsOneReachableCommandSurfaceAtSupportedWidths() throws {
  let source = try notesPanelSource()
  let formattingBar = try #require(source.components(separatedBy: "private struct FormattingBar").last)

  #expect(formattingBar.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").count == 2)
  #expect(formattingBar.contains("accessibilityLabel(\"Editor toolbar\")"))
  #expect(formattingBar.contains("ToolbarIconLabel(systemImage: \"trash\")"))
  #expect(!formattingBar.contains("ViewThatFits"))
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
      "private var showsUnfiledDisclosure: Bool { !isUnfiledCompact || isUnfiledHovered || focusedRow == .unfiled }"
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

@Test func compactUnfiledDisclosureUsesForgivingRectangularHitTarget() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  let rootRow = try #require(
    navigator.components(separatedBy: "private var rootRow").last?
      .components(separatedBy: "@ViewBuilder\n    private func folderRow").first
  )
  let disclosure = try #require(
    rootRow.components(separatedBy: "if showsUnfiledDisclosure").last?
      .components(separatedBy: ".onHover").first
  )

  #expect(disclosure.contains(".frame(width: 28, height: 28)"))
  #expect(disclosure.contains(".contentShape(Rectangle())"))
  #expect(disclosure.contains(".buttonStyle(.plain)"))
  #expect(disclosure.contains("Expand Unfiled"))
  #expect(disclosure.contains("Collapse Unfiled"))
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
  #expect(rowLabelBody.contains("isFocused: Bool"))
  #expect(rowLabelBody.contains("isFocused && !isSelected"))
  #expect(rowLabelBody.contains(".overlay"))
  #expect(
    rowLabelBody.contains(
      ".strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)"
    )
  )
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
  accentHex: String? = nil
) -> (NSWindow, NSHostingView<AnyView>) {
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let panel = NotesPanel(dictationRuntime: runtime, editorCommands: commands)
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
