import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func emptyBulletEnterTabKeepsCaretBeforeTypingAtMiddleOfDocument() {
  let text = "• Parent\nSibling"
  let marker = "• Parent\n    ◦ "
  let textView = makeListIndentationEditor(
    text,
    selection: NSRange(location: "• Parent".utf16.count, length: 0)
  )

  textView.insertNewline(nil)
  textView.insertTab(nil)

  #expect(textView.string == "• Parent\n    ◦ \nSibling")
  #expect(textView.selectedRange() == NSRange(location: marker.utf16.count, length: 0))

  textView.insertText("typed", replacementRange: textView.selectedRange())

  #expect(textView.string == marker + "typed\nSibling")
}

@Test @MainActor func emptyBulletEnterTabKeepsCaretBeforeTypingAtDocumentEnd() {
  let text = "• Parent"
  let marker = "• Parent\n    ◦ "
  let textView = makeListIndentationEditor(
    text,
    selection: NSRange(location: text.utf16.count, length: 0)
  )

  textView.insertNewline(nil)
  textView.insertTab(nil)

  #expect(textView.string == marker)
  #expect(textView.selectedRange() == NSRange(location: marker.utf16.count, length: 0))

  textView.insertText("typed", replacementRange: textView.selectedRange())

  #expect(textView.string == marker + "typed")
}

@Test @MainActor func emptyNestedBacktabKeepsCaretAfterOutdent() {
  let text = "    ◦ "
  let textView = makeListIndentationEditor(
    text,
    selection: NSRange(location: text.utf16.count, length: 0)
  )

  textView.insertBacktab(nil)

  #expect(textView.string == "• ")
  #expect(textView.selectedRange() == NSRange(location: "• ".utf16.count, length: 0))

  textView.insertText("typed", replacementRange: textView.selectedRange())

  #expect(textView.string == "• typed")
}

@Test @MainActor func selectedListLinesRemainSelectedWhenIndented() {
  let text = "• First\n• Second"
  let indented = "    ◦ First\n    ◦ Second"
  let textView = makeListIndentationEditor(
    text,
    selection: NSRange(location: 0, length: text.utf16.count)
  )

  textView.insertTab(nil)

  #expect(textView.string == indented)
  #expect(textView.selectedRange() == NSRange(location: 0, length: indented.utf16.count))
}

@Test @MainActor func nonListTabRetainsExistingSelectionBehavior() {
  let textView = makeListIndentationEditor(
    "Plain",
    selection: NSRange(location: 2, length: 0)
  )

  textView.insertTab(nil)

  #expect(textView.string == "    Plain")
  #expect(textView.selectedRange() == NSRange(location: 0, length: "    Plain".utf16.count))
}

@Test @MainActor func emptyNumberedIndentKeepsCaretAfterRenumbering() {
  let text = "10. P 🧪\n11. Q\n    a. R\n        i. S\n    b. \nTail"
  let expected = "1. P 🧪\n2. Q\n    a. R\n        i. S\n        ii. \nTail"
  let textView = makeListIndentationEditor(
    text,
    selection: NSRange(
      location: NSMaxRange((text as NSString).range(of: "    b. ")),
      length: 0
    )
  )

  textView.insertTab(nil)

  #expect(textView.string == expected)
  #expect(
    textView.selectedRange()
      == NSRange(
        location: NSMaxRange((expected as NSString).range(of: "        ii. ")),
        length: 0
      )
  )

  textView.insertText("typed", replacementRange: textView.selectedRange())

  #expect(textView.string == "1. P 🧪\n2. Q\n    a. R\n        i. S\n        ii. typed\nTail")
}

@Test @MainActor func emptyNumberedOutdentKeepsCaretAfterRenumbering() {
  let text = "10. A\n11. B\n12. C\n13. D\n14. E\n15. F\n16. G\n17. H\n18. I\n    a. Nested\n    b. \nTail"
  let expected = "1. A\n2. B\n3. C\n4. D\n5. E\n6. F\n7. G\n8. H\n9. I\n    a. Nested\n10. \nTail"
  let textView = makeListIndentationEditor(
    text,
    selection: NSRange(
      location: NSMaxRange((text as NSString).range(of: "    b. ")),
      length: 0
    )
  )

  textView.insertBacktab(nil)

  #expect(textView.string == expected)
  #expect(
    textView.selectedRange()
      == NSRange(
        location: NSMaxRange((expected as NSString).range(of: "10. ")),
        length: 0
      )
  )

  textView.insertText("typed", replacementRange: textView.selectedRange())

  #expect(
    textView.string
      == "1. A\n2. B\n3. C\n4. D\n5. E\n6. F\n7. G\n8. H\n9. I\n    a. Nested\n10. typed\nTail"
  )
}

@MainActor
private func makeListIndentationEditor(_ text: String, selection: NSRange) -> ListAwareTextView {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = text
  textView.setSelectedRange(selection)
  return textView
}
