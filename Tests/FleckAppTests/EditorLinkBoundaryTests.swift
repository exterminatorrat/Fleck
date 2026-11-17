import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func linkBoundaryEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 200)
  let view = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
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

@MainActor
private func linkLabelPoint(_ view: ListAwareTextView, at characterIndex: Int) -> NSPoint? {
  guard let layoutManager = view.layoutManager, let container = view.textContainer else {
    return nil
  }
  layoutManager.ensureLayout(for: container)
  let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
  let rect = layoutManager.boundingRect(
    forGlyphRange: NSRange(location: glyphIndex, length: 1),
    in: container
  )
  guard rect.width > 0 else { return nil }
  return NSPoint(
    x: rect.midX + view.textContainerOrigin.x,
    y: rect.midY + view.textContainerOrigin.y
  )
}

@MainActor
private func clickEditor(
  _ view: ListAwareTextView,
  in window: NSWindow,
  at point: NSPoint,
  clickCount: Int = 1,
  modifiers: NSEvent.ModifierFlags = []
) throws {
  let windowPoint = view.convert(point, to: nil)
  let down = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: windowPoint,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: clickCount,
      pressure: 1
    )
  )
  let up = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: windowPoint,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 2,
      clickCount: clickCount,
      pressure: 0
    )
  )
  NSApplication.shared.postEvent(up, atStart: true)
  view.mouseDown(with: down)
  _ = NSApplication.shared.nextEvent(
    matching: .leftMouseUp,
    until: Date(),
    inMode: .default,
    dequeue: true
  )
}

@Test @MainActor func clickInsideLinkLabelSelectsTheWholeLink() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { window.contentView = nil }
  let link = try #require(NoteLinkParser.links(in: text).first)

  let point = try #require(linkLabelPoint(view, at: link.labelRange.location + 1))
  try clickEditor(view, in: window, at: point)

  #expect(view.selectedRange() == link.range)
}

@Test @MainActor func caretMovementIntoLinkLandsOnTheWholeToken() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = linkBoundaryEditor(text)
  defer { window.contentView = nil }
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
  defer { window.contentView = nil }
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
  defer { window.contentView = nil }

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
  defer { window.contentView = nil }
  let link = try #require(NoteLinkParser.links(in: text).first)

  let point = try #require(linkLabelPoint(view, at: link.labelRange.location + 1))
  try clickEditor(view, in: window, at: point)
  view.deleteBackward(nil)

  #expect(view.string == "Body  tail")
  #expect(!view.string.contains("["))
  #expect(!view.string.contains("]"))
}
