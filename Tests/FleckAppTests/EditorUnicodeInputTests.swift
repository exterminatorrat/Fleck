import AppKit
import Testing

@testable import FleckApp

@MainActor
private func unicodeEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
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

@Test @MainActor func forwardDeleteInsideAnEmojiRemovesTheWholeCluster() {
  let (view, window) = unicodeEditor("a🙂b")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 2, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "ab")
  #expect(!view.string.utf16.contains(where: { (0xD800...0xDFFF).contains($0) }))
}

@Test @MainActor func backwardDeleteAfterAnEmojiLeavesNoLoneSurrogate() {
  let (view, window) = unicodeEditor("a🙂b")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 3, length: 0))
  view.deleteBackward(nil)

  #expect(view.string == "ab")
}

@Test @MainActor func forwardDeleteKeepsACombiningAccentWithItsBase() {
  let (view, window) = unicodeEditor("e\u{301}xy")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 2, length: 0))
  view.deleteForward(nil)

  #expect(view.string == "e\u{301}y")
  #expect((view.string as NSString).rangeOfComposedCharacterSequence(at: 0).length == 2)
}

@Test @MainActor func insertNewlineDefersWhileMarkedTextIsActive() {
  let (view, window) = unicodeEditor("• one")
  defer { window.contentView = nil }

  view.setSelectedRange(NSRange(location: 2, length: 0))
  view.setMarkedText(
    "拼",
    selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0)
  )
  #expect(view.hasMarkedText())

  view.insertNewline(nil)

  #expect(!view.string.hasSuffix("• "), "string \(view.string.debugDescription)")
  #expect(view.string.contains("\n"))
}

@Test @MainActor func deleteBackwardDefersWhileMarkedTextIsActive() throws {
  let (view, window) = unicodeEditor("plain\n• item")
  defer { window.contentView = nil }
  let bulletContentStart = try #require(
    (view.string as NSString).range(of: "item").location != NSNotFound
      ? (view.string as NSString).range(of: "item").location
      : nil
  )

  view.setSelectedRange(NSRange(location: bulletContentStart, length: 0))
  view.setMarkedText(
    "拼",
    selectedRange: NSRange(location: 0, length: 0),
    replacementRange: NSRange(location: bulletContentStart, length: 0)
  )
  try #require(view.hasMarkedText())
  try #require(
    view.selectedRange().location == bulletContentStart,
    "caret \(view.selectedRange()) content start \(bulletContentStart)"
  )

  view.deleteBackward(nil)

  #expect(view.string.contains("\n•"), "string \(view.string.debugDescription)")
  #expect(view.string.contains("item"), "string \(view.string.debugDescription)")
}
