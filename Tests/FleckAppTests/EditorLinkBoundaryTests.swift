import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func linkBoundaryEditor(_ text: String) -> (ListAwareTextView, EditorMouseTestWindow) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 200)
  let view = ListAwareTextView(frame: frame)
  let window = EditorMouseTestWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = view
  view.allowsUndo = true
  view.textStorage?.setAttributedString(
    NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 17),
      .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
    ])
  )
  window.makeKeyAndOrderFront(nil)
  window.makeFirstResponder(view)
  view.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [])
  return (view, window)
}

@Test @MainActor func clickInsideLinkLabelSelectsTheWholeLink() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { closeEditorTestWindow(window) }
  let link = try #require(NoteLinkParser.links(in: text).first)

  let point = try #require(editorCharacterPoint(view, at: link.labelRange.location + 1))
  try window.click(view, at: point)

  #expect(view.selectedRange() == link.range)
}

@Test @MainActor func caretMovementIntoLinkLandsOnTheWholeToken() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { closeEditorTestWindow(window) }
  let link = try #require(NoteLinkParser.links(in: text).first)
  let ns = view.string as NSString

  #expect(
    view.selectionRange(
      forProposedRange: NSRange(location: link.labelRange.location, length: 0),
      granularity: .selectByCharacter
    ) == link.range
  )

  view.setSelectedRange(NSRange(location: link.range.location, length: 0))
  view.moveRight(nil)
  #expect(view.selectedRange() == link.range)

  view.setSelectedRange(NSRange(location: NSMaxRange(link.range), length: 0))
  view.moveLeft(nil)
  #expect(view.selectedRange() == link.range)
  #expect(view.snappedSelection(for: NSRange(location: 0, length: 2), in: ns) == NSRange(location: 0, length: 2))
}

@Test @MainActor func snappedSelectionWidensOnlyPartiallyCoveredLinks() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { closeEditorTestWindow(window) }
  let link = try #require(NoteLinkParser.links(in: text).first)
  let ns = view.string as NSString

  #expect(view.snappedSelection(for: link.range, in: ns) == link.range)
  #expect(
    view.snappedSelection(for: NSRange(location: link.labelRange.location, length: 0), in: ns)
      == link.range
  )
  #expect(
    view.snappedSelection(for: NSRange(location: NSMaxRange(link.range), length: 0), in: ns)
      == NSRange(location: NSMaxRange(link.range), length: 0)
  )
  #expect(
    view.snappedSelection(for: NSRange(location: link.range.location - 2, length: 3), in: ns)
      == NSUnionRange(NSRange(location: link.range.location - 2, length: 3), link.range)
  )
  let covering = NSRange(location: link.range.location - 2, length: link.range.length + 5)
  #expect(view.snappedSelection(for: covering, in: ns) == covering)
}

@Test @MainActor func snappedSelectionDefersWhileMarkedTextIsActive() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { closeEditorTestWindow(window) }

  view.setSelectedRange(NSRange(location: 0, length: 0))
  view.setMarkedText(
    "拼",
    selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0)
  )
  #expect(view.hasMarkedText())

  let link = try #require(NoteLinkParser.links(in: view.string).first)
  let caret = NSRange(location: link.labelRange.location, length: 0)
  #expect(view.snappedSelection(for: caret, in: view.string as NSString) == caret)
}

@Test @MainActor func deletingAWholeSelectedLinkLeavesNoStrayBrackets() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { closeEditorTestWindow(window) }
  let link = try #require(NoteLinkParser.links(in: text).first)

  let point = try #require(editorCharacterPoint(view, at: link.labelRange.location + 1))
  try window.click(view, at: point)
  view.deleteBackward(nil)

  #expect(view.string == "Body  tail")
  #expect(!view.string.contains("["))
  #expect(!view.string.contains("]"))
}
