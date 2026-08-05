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
  let windowPoint = textView.convert(
    NSPoint(x: hitRect.midX, y: hitRect.midY),
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
  let foreground = NSColor(Color(hex: "#FF4245"))
  let background = NSColor(Color(hex: "#FFD600"))
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

  #expect(TabColorOption.matchesPaletteColor(restoredForeground, hex: "#FF4245"))
  #expect(TabColorOption.paletteName(for: restoredForeground) == "Red")
  #expect(TabColorOption.matchesPaletteColor(restoredBackground, hex: "#FFD600"))
  #expect(TabColorOption.paletteName(for: restoredBackground) == "Yellow")
  #expect(!TabColorOption.matchesPaletteColor(restoredCustom, hex: "#FF4245"))
  #expect(TabColorOption.paletteName(for: restoredCustom) == nil)
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
  #expect(source.contains("TabColorOption.all.filter { $0.hex != nil }"))
  #expect(source.contains("currentForegroundColor"))
  #expect(source.contains("currentBackgroundColor"))
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

@Test func formattingBarAnnouncesPaletteNamesAndMarksSpecialColorRows() throws {
  let source = try notesPanelSource()

  #expect(source.contains("specialColorMenuLabel("))
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
  #expect(formattingBar.contains("accessibilityLabel(\"Formatting controls\")"))
  #expect(formattingBar.contains("ToolbarIconLabel(systemImage: \"trash\")"))
  #expect(!formattingBar.contains("ViewThatFits"))
}

@Test func formattingBarCanAlwaysBeCollapsedAndRestoredFromTheHeader() throws {
  let source = try notesPanelSource()

  #expect(source.contains("Hide formatting controls"))
  #expect(source.contains("Show formatting controls"))
  #expect(source.contains("showFormattingBar.toggle()"))
  #expect(source.contains("if appState.preferences.showFormattingBar"))
  #expect(source.contains("\"chevron.up\""))
  #expect(source.contains("\"chevron.down\""))

  let editorCommands = try #require(source.range(of: "@StateObject private var editorCommands = EditorCommands()"))
  let formattingBar = try #require(source.range(of: "if appState.preferences.showFormattingBar"))
  #expect(editorCommands.lowerBound < formattingBar.lowerBound)
  #expect(!source.contains(".id(appState.preferences.showFormattingBar)"))
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

@Test @MainActor func tabColorSwatchesAreNonTemplateImages() {
  for option in TabColorOption.all where option.hex != nil {
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

  for option in TabColorOption.all where option.hex != nil {
    #expect(option.hex == expectedHexByName[option.name])
  }
}
