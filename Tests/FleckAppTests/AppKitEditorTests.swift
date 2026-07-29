import AppKit
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
