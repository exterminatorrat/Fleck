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
