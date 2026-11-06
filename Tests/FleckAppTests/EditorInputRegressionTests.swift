import AppKit
import Testing

@testable import FleckApp

@MainActor
private func inputRegressionEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: 360, height: 200)
  let view = ListAwareTextView(frame: frame)
  let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = view
  view.allowsUndo = true
  view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: 17),
    .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
  ]))
  window.makeFirstResponder(view)
  return (view, window)
}

@Test(arguments: [false, true])
@MainActor func checkedItemAppendsStrikeWhilePreservingInsertionStyles(_ attributed: Bool) throws {
  let (view, window) = inputRegressionEditor("○ old\n○ next")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  #expect(view.toggleSelectedChecklist())
  let font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font, .foregroundColor: NSColor.systemRed,
    .underlineStyle: NSUnderlineStyle.single.rawValue, .strikethroughStyle: 0,
  ]
  view.typingAttributes = attributes
  view.undoManager?.removeAllActions()
  let insertion: Any = attributed ? NSAttributedString(string: "iW", attributes: attributes) : "iW"
  view.insertText(insertion, replacementRange: view.selectedRange())
  #expect(view.string == "● oldiW\n○ next")
  let storage = try #require(view.textStorage)
  for location in 5..<7 {
    #expect(storage.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int == 1)
    #expect(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == font)
    #expect(storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor == .systemRed)
    #expect(storage.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int == 1)
  }
  #expect((storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
  let restored = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(storage))
  #expect(restored.string == storage.string)
  #expect(restored.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
  let undo = try #require(view.undoManager)
  view.breakUndoCoalescing()
  undo.undo()
  #expect(view.string == "● old\n○ next")
  #expect(view.selectedRange() == NSRange(location: 5, length: 0))
  undo.redo()
  #expect(view.string == "● oldiW\n○ next")
  #expect(view.selectedRange() == NSRange(location: 7, length: 0))
  #expect(view.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
}

@Test @MainActor func checkedItemPasteKeepsStrikeOnlyInCheckedParagraph() throws {
  let (view, window) = inputRegressionEditor("○ old")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  #expect(view.toggleSelectedChecklist())
  view.undoManager?.removeAllActions()
  let pasted = NSAttributedString(string: "iW\nplain", attributes: [
    .font: NSFont.systemFont(ofSize: 23), .underlineStyle: 1, .strikethroughStyle: 0,
  ])
  view.insertPastedTextForTesting(pasted)
  #expect(view.string == "● oldiW\nplain")
  #expect(view.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
  #expect((view.textStorage?.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int ?? 0) == 0)
  #expect((view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)?.pointSize == 23)
  #expect(view.textStorage?.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int == 1)
  let undo = try #require(view.undoManager)
  undo.undo()
  #expect(view.string == "● old")
  #expect(view.selectedRange() == NSRange(location: 5, length: 0))
  undo.redo()
  #expect(view.string == "● oldiW\nplain")
  #expect(view.selectedRange() == NSRange(location: 13, length: 0))
  #expect(view.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
  let restored = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(try #require(view.textStorage)))
  #expect(restored.string == view.string)
  #expect(restored.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
  #expect((restored.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int ?? 0) == 0)
}

@Test(arguments: [0, 1, 2])
@MainActor func checkedItemPasteOptionsPreserveCompletionWithoutLeakingToPlainText(_ rawOption: Int) throws {
  let (view, window) = inputRegressionEditor("○ old")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  #expect(view.toggleSelectedChecklist())
  view.insertPastedTextForTesting(NSAttributedString(string: "iW\nplain", attributes: [
    .font: NSFont.systemFont(ofSize: 23), .underlineStyle: 1, .strikethroughStyle: 0,
  ]))
  let option = try #require(PasteOption(rawValue: rawOption))
  view.applyPasteOption(option)
  #expect(view.string == "● oldiW\nplain")
  #expect(view.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
  #expect((view.textStorage?.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int ?? 0) == 0)
}

@Test @MainActor func uncheckingAndNewChecklistParagraphDoNotLeakCompletionTyping() throws {
  let (view, window) = inputRegressionEditor("○ old")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  #expect(view.toggleSelectedChecklist())
  view.insertText("W", replacementRange: view.selectedRange())
  #expect(view.textStorage?.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int == 1)
  #expect(view.toggleSelectedChecklist())
  view.insertText("i", replacementRange: view.selectedRange())
  #expect(view.string == "○ oldWi")
  #expect((view.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int ?? 0) == 0)
  #expect(view.toggleSelectedChecklist())
  view.insertNewline(nil)
  view.insertText("fresh", replacementRange: view.selectedRange())
  #expect(view.string == "● oldWi\n○ fresh")
  #expect((view.textStorage?.attribute(.strikethroughStyle, at: 10, effectiveRange: nil) as? Int ?? 0) == 0)
}

@Test @MainActor func checkedItemMarkedTextCommitPreservesNativeComposition() throws {
  let (view, window) = inputRegressionEditor("● old")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  view.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(view.hasMarkedText())
  view.insertText("拼音", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(!view.hasMarkedText())
  #expect(view.string == "● old拼音")
  #expect(view.selectedRange() == NSRange(location: 7, length: 0))
  #expect(view.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == 1)
}
