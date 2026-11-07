import AppKit
import Testing

@testable import FleckApp

@MainActor
private func tabCaretEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
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

private func threeSpaceTabInterval(for font: NSFont) -> CGFloat {
  3 * (" " as NSString).size(withAttributes: [.font: font]).width
}

@Test(arguments: ["", "\n", "Before\n\nAfter", "Before\n", "    "])
@MainActor func emptyPlainParagraphTabIsOneNativeCharacterWithSelectionUndo(_ original: String) throws {
  let (view, window) = tabCaretEditor(original)
  defer { window.contentView = nil }
  let location = original == "Before\n\nAfter" ? "Before\n".utf16.count : original.utf16.count
  let selection = NSRange(location: location, length: 0)
  view.setSelectedRange(selection)
  view.undoManager?.removeAllActions()

  view.doCommand(by: #selector(NSResponder.insertTab(_:)))

  let expected = (original as NSString).replacingCharacters(in: selection, with: "\t")
  #expect(view.string == expected)
  #expect((view.string as NSString).character(at: selection.location) == 0x09)
  #expect(view.selectedRange() == NSRange(location: selection.location + 1, length: 0))
  #expect(window.firstResponder === view)
  let undo = try #require(view.undoManager)
  undo.undo()
  #expect(view.string == original)
  #expect(view.selectedRange() == selection)
  undo.redo()
  #expect(view.string == expected)
  #expect(view.selectedRange() == NSRange(location: selection.location + 1, length: 0))
}

@Test(arguments: [
  ("• ", "    ◦ "), ("    ◦ ", "        ▪ "),
  ("○ ", "    ○ "), ("● ", "    ● "), ("1. ", "    a. "),
])
@MainActor func emptyListTabNestsAndRestoresSelectionThroughUndo(
  _ item: (String, String)
) throws {
  let (view, window) = tabCaretEditor(item.0)
  defer { window.contentView = nil }
  let selection = NSRange(location: item.0.utf16.count, length: 0)
  view.setSelectedRange(selection)
  view.undoManager?.removeAllActions()

  view.doCommand(by: #selector(NSResponder.insertTab(_:)))

  #expect(view.string == item.1)
  #expect(view.selectedRange() == NSRange(location: item.1.utf16.count, length: 0))
  let undo = try #require(view.undoManager)
  undo.undo()
  #expect(view.string == item.0)
  #expect(view.selectedRange() == selection)
  undo.redo()
  #expect(view.string == item.1)
  #expect(view.selectedRange() == NSRange(location: item.1.utf16.count, length: 0))
  view.insertText("i", replacementRange: view.selectedRange())
  #expect(view.string == item.1 + "i")
}

@Test @MainActor func populatedBulletTabInsertsNativeTabsAtCaretPositions() {
  let cases: [(text: String, location: Int, expected: String)] = [
    ("• bullet", 2, "• \tbullet"),
    ("• bullet", 5, "• bul\tlet"),
    ("• bullet", 8, "• bullet\t"),
    ("•   item", 4, "•   \titem"),
    ("    ◦ nested", 6, "    ◦ \tnested"),
  ]

  for item in cases {
    let (view, window) = tabCaretEditor(item.text)
    view.setSelectedRange(NSRange(location: item.location, length: 0))
    view.insertTab(nil)
    #expect(view.string == item.expected)
    #expect(view.selectedRange() == NSRange(location: item.location + 1, length: 0))
    window.contentView = nil
  }
}

@Test @MainActor func bulletTabDeletionAndUndoRestoreTheCaretOneTabAtATime() throws {
  let (view, window) = tabCaretEditor("• item")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 2, length: 0))
  let undo = try #require(view.undoManager)
  undo.groupsByEvent = false
  undo.removeAllActions()

  view.insertTab(nil)
  view.insertTab(nil)
  #expect(view.string == "• \t\titem")
  #expect(view.selectedRange() == NSRange(location: 4, length: 0))
  view.moveLeft(nil)
  #expect(view.selectedRange() == NSRange(location: 3, length: 0))
  view.moveRight(nil)
  #expect(view.selectedRange() == NSRange(location: 4, length: 0))

  view.deleteBackward(nil)
  #expect(view.string == "• \titem")
  #expect(view.selectedRange() == NSRange(location: 3, length: 0))
  view.deleteBackward(nil)
  #expect(view.string == "• item")
  #expect(view.selectedRange() == NSRange(location: 2, length: 0))

  undo.undo()
  #expect(view.string == "• \titem")
  #expect(view.selectedRange() == NSRange(location: 3, length: 0))
  undo.undo()
  #expect(view.string == "• \t\titem")
  #expect(view.selectedRange() == NSRange(location: 4, length: 0))
}

@Test @MainActor func bulletTabUsesDepthSpecificDefaultAndPreservesCustomPolicy() throws {
  let font = NSFont.systemFont(ofSize: 17)
  let defaultParagraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (topLevel, topWindow) = tabCaretEditor("• item")
  defer { topWindow.contentView = nil }
  topLevel.textStorage?.addAttribute(
    .paragraphStyle,
    value: defaultParagraph,
    range: NSRange(location: 0, length: topLevel.string.utf16.count)
  )
  topLevel.setSelectedRange(NSRange(location: 2, length: 0))
  topLevel.insertTab(nil)
  let topStyle = try #require(
    topLevel.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(topStyle.defaultTabInterval == 36)
  #expect(topStyle.tabStops.isEmpty)
  #expect(topStyle.firstLineHeadIndent == defaultParagraph.firstLineHeadIndent)
  #expect(topStyle.headIndent == defaultParagraph.headIndent)
  #expect(topStyle.tailIndent == defaultParagraph.tailIndent)

  let (nested, nestedWindow) = tabCaretEditor("    ◦ nested")
  defer { nestedWindow.contentView = nil }
  nested.textStorage?.addAttribute(
    .paragraphStyle,
    value: defaultParagraph,
    range: NSRange(location: 0, length: nested.string.utf16.count)
  )
  nested.setSelectedRange(NSRange(location: 6, length: 0))
  nested.insertTab(nil)
  let nestedStyle = try #require(
    nested.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(nestedStyle.defaultTabInterval - threeSpaceTabInterval(for: font)) < 0.01)
  #expect(nestedStyle.tabStops.isEmpty)

  let persistedThreeSpaces = NSMutableParagraphStyle()
  persistedThreeSpaces.defaultTabInterval = threeSpaceTabInterval(for: font)
  let (persisted, persistedWindow) = tabCaretEditor("• item")
  defer { persistedWindow.contentView = nil }
  persisted.textStorage?.addAttribute(
    .paragraphStyle,
    value: persistedThreeSpaces,
    range: NSRange(location: 0, length: persisted.string.utf16.count)
  )
  persisted.setSelectedRange(NSRange(location: 2, length: 0))
  persisted.insertTab(nil)
  let persistedStyle = try #require(
    persisted.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(persistedStyle.defaultTabInterval - threeSpaceTabInterval(for: font)) < 0.01)
  #expect(persistedStyle.isEqual(persistedThreeSpaces))

  let custom = NSMutableParagraphStyle()
  custom.defaultTabInterval = 24
  custom.tabStops = [NSTextTab(textAlignment: .right, location: 72, options: [:])]
  custom.firstLineHeadIndent = 4
  custom.headIndent = 12
  custom.tailIndent = -8
  custom.lineSpacing = 3
  let (customView, customWindow) = tabCaretEditor("• item")
  defer { customWindow.contentView = nil }
  customView.textStorage?.addAttribute(
    .paragraphStyle,
    value: custom,
    range: NSRange(location: 0, length: customView.string.utf16.count)
  )
  customView.setSelectedRange(NSRange(location: 2, length: 0))
  customView.insertTab(nil)
  let customResult = try #require(
    customView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(customResult.isEqual(custom))

  let (existingTab, existingWindow) = tabCaretEditor("• \titem")
  defer { existingWindow.contentView = nil }
  existingTab.textStorage?.addAttribute(
    .paragraphStyle,
    value: defaultParagraph,
    range: NSRange(location: 0, length: existingTab.string.utf16.count)
  )
  existingTab.setSelectedRange(NSRange(location: 3, length: 0))
  existingTab.insertTab(nil)
  #expect(existingTab.string == "• \t\titem")
  let existingStyle = try #require(
    existingTab.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(existingStyle.isEqual(defaultParagraph))
}

@Test @MainActor func bulletCaretCannotEnterPrefixAndLeftArrowMovesToPreviousParagraph() {
  let (view, window) = tabCaretEditor("Before\n• item")
  defer { window.contentView = nil }
  let bulletStart = "Before\n".utf16.count
  let contentStart = "Before\n• ".utf16.count
  for location in bulletStart..<contentStart {
    view.setSelectedRange(NSRange(location: location, length: 0))
    #expect(view.selectedRange() == NSRange(location: contentStart, length: 0))
    #expect(view.selectionRange(
      forProposedRange: NSRange(location: location, length: 0),
      granularity: .selectByCharacter
    ) == NSRange(location: contentStart, length: 0))
  }
  view.setSelectedRanges(
    [NSValue(range: NSRange(location: bulletStart, length: 0))],
    affinity: .downstream,
    stillSelecting: false
  )
  #expect(view.selectedRange() == NSRange(location: contentStart, length: 0))
  view.setSelectedRange(NSRange(location: bulletStart, length: 2))
  #expect(view.selectedRange() == NSRange(location: bulletStart, length: 2))

  view.setSelectedRange(NSRange(location: contentStart, length: 0))
  view.moveLeft(nil)
  #expect(view.selectedRange() == NSRange(location: "Before".utf16.count, length: 0))
}

@Test @MainActor func backspaceRemovesAnEmptyBulletPrefixInOneUndoableAction() throws {
  let original = "Before\n• \nAfter"
  let (view, window) = tabCaretEditor(original)
  defer { window.contentView = nil }
  let itemStart = "Before\n".utf16.count
  view.setSelectedRange(NSRange(location: itemStart + 2, length: 0))
  view.undoManager?.removeAllActions()

  view.deleteBackward(nil)

  #expect(view.string == "Before\n\nAfter")
  #expect(view.selectedRange() == NSRange(location: itemStart, length: 0))
  let undo = try #require(view.undoManager)
  #expect(undo.canUndo)
  undo.undo()
  #expect(view.string == original)
  undo.redo()
  #expect(view.string == "Before\n\nAfter")
}

@Test @MainActor func bulletTabDefersToNativeCommandDuringMarkedTextAndRequiresEditableView() {
  let (view, window) = tabCaretEditor("• item")
  defer { window.contentView = nil }
  let reference = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
  reference.string = "item"
  view.setSelectedRange(NSRange(location: 4, length: 0))
  reference.setSelectedRange(NSRange(location: 2, length: 0))
  for editor: NSTextView in [view, reference] {
    editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    editor.insertTab(nil)
  }
  #expect(view.string == "• " + reference.string)
  #expect(view.hasMarkedText() == reference.hasMarkedText())
  #expect(view.selectedRange().location == reference.selectedRange().location + 2)
  #expect(view.selectedRange().length == reference.selectedRange().length)

  let (readOnly, readOnlyWindow) = tabCaretEditor("• item")
  defer { readOnlyWindow.contentView = nil }
  readOnly.isEditable = false
  readOnly.setSelectedRange(NSRange(location: 2, length: 0))
  readOnly.insertTab(nil)
  #expect(readOnly.string == "• item")
  #expect(readOnly.selectedRange() == NSRange(location: 2, length: 0))
}
