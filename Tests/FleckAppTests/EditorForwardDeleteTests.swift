import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func forwardDeleteEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
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
  return (view, window)
}

@Test @MainActor func forwardDeleteMidWordRemovesFollowingCharacter() {
  let (view, window) = forwardDeleteEditor("alpha beta")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 2, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "alha beta")
  #expect(view.selectedRange() == NSRange(location: 2, length: 0))
}

@Test @MainActor func forwardDeleteAtLineEndMergesNextListItem() {
  let (view, window) = forwardDeleteEditor("• one\n• two")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 5, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "• onetwo")
  #expect(view.selectedRange() == NSRange(location: 5, length: 0))
}

@Test @MainActor func forwardDeleteAtNumberedLineEndKeepsOneMarker() {
  let (view, window) = forwardDeleteEditor("1. one\n2. two")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 6, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "1. onetwo")
}

@Test @MainActor func forwardDeleteAtChecklistLineEndKeepsOneMarker() {
  let (view, window) = forwardDeleteEditor("○ one\n○ two")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 5, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "○ onetwo")
}

@Test @MainActor func forwardDeleteBeforeLinkRemovesWholeLink() throws {
  let target = UUID()
  let text = "Body \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) tail"
  let (view, window) = forwardDeleteEditor(text)
  defer { window.contentView = nil }
  let link = try #require(NoteLinkParser.links(in: text).first)

  view.setSelectedRange(NSRange(location: link.range.location, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "Body  tail")
  #expect(view.selectedRange() == NSRange(location: link.range.location, length: 0))
  #expect(!view.string.contains("["))
  #expect(!view.string.contains("]"))
}

@Test @MainActor func forwardDeleteDefersWhileMarkedTextIsActive() throws {
  let (view, window) = forwardDeleteEditor("• one\n• two\n• three")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 11, length: 0))
  view.setMarkedText(
    "拼",
    selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0)
  )
  #expect(view.hasMarkedText())
  #expect(view.selectedRange() == NSRange(location: 12, length: 0))

  view.deleteForward(nil)

  #expect(view.string.contains("• three"))
}
