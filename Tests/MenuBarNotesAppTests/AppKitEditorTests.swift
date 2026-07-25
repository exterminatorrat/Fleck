import AppKit
import Testing

@testable import MenuBarNotesApp

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
  #expect(
    (textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int ?? 0) == 0
  )
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
  let alphabeticEnd = (textView.string as NSString).range(of: "i. Item 9").upperBound
  textView.setSelectedRange(NSRange(location: alphabeticEnd, length: 0))

  textView.insertNewline(nil)

  #expect(textView.string.hasSuffix("i. Item 9\nj. "))

  textView.string = "    Roman"
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  textView.toggleList(.number(.roman))
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  textView.insertNewline(nil)

  #expect(textView.string == "    i. Roman\n    ii. ")
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
