import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func clickDepthEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 200)
  let view = ListAwareTextView(frame: frame)
  let window = NSWindow(
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
  return (view, window)
}

@MainActor
private func characterPoint(_ view: ListAwareTextView, at characterIndex: Int) -> NSPoint? {
  guard let window = view.window else { return nil }
  let caret = view.firstRect(
    forCharacterRange: NSRange(location: characterIndex, length: 1),
    actualRange: nil
  )
  guard caret.width > 0 || caret.height > 0 else { return nil }
  return view.convert(
    window.convertPoint(fromScreen: NSPoint(x: caret.midX, y: caret.midY)),
    from: nil
  )
}

/// A previous test can leave a synthesized mouse event in the queue, and the
/// tracking AppKit runs inside `mouseDown` consumes whatever it finds first.
@MainActor
private func drainPendingMouseEvents() {
  while
    NSApplication.shared.nextEvent(
      matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved],
      until: .distantPast,
      inMode: .default,
      dequeue: true
    ) != nil
  {}
}

@MainActor
private func click(
  _ view: ListAwareTextView,
  in window: NSWindow,
  at point: NSPoint,
  clickCount: Int = 1,
  modifiers: NSEvent.ModifierFlags = []
) throws {
  drainPendingMouseEvents()
  defer { drainPendingMouseEvents() }
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

@Test @MainActor func doubleClickSelectsTheWordUnderThePointer() throws {
  let (view, window) = clickDepthEditor("alpha beta gamma")
  defer { closeEditorTestWindow(window) }

  let point = try #require(characterPoint(view, at: 1))
  try click(view, in: window, at: point, clickCount: 2)

  let selection = view.selectedRange()
  #expect(
    (view.string as NSString).substring(with: selection) == "alpha",
    "selected \(selection) of \(view.string.debugDescription)"
  )
}

@Test @MainActor func tripleClickSelectsTheParagraphUnderThePointer() throws {
  let (view, window) = clickDepthEditor("first line\nsecond line")
  defer { closeEditorTestWindow(window) }

  let point = try #require(characterPoint(view, at: 2))
  try click(view, in: window, at: point, clickCount: 3)

  let selected = (view.string as NSString).substring(with: view.selectedRange())
  #expect(selected.hasPrefix("first line"), "selected \(selected.debugDescription)")
  #expect(!selected.contains("second"), "selected \(selected.debugDescription)")
}

@Test @MainActor func doubleClickOnAChecklistMarkerStillTogglesIt() throws {
  let (view, window) = clickDepthEditor("○ one\n○ two")
  defer { closeEditorTestWindow(window) }

  let hitRect = try #require(view.checklistHitRect(for: NSRange(location: 0, length: 1)))
  try click(
    view,
    in: window,
    at: NSPoint(x: hitRect.midX, y: hitRect.midY),
    clickCount: 2
  )

  #expect(view.string.hasPrefix("● one"))
  #expect(view.string.hasSuffix("○ two"))
}

@Test @MainActor func shiftClickExtendsTheSelectionNatively() throws {
  let (view, window) = clickDepthEditor("alpha beta gamma")
  defer { closeEditorTestWindow(window) }

  view.setSelectedRange(NSRange(location: 0, length: 5))
  let anchorBefore = view.selectedRange()
  let point = try #require(characterPoint(view, at: 8))
  try click(view, in: window, at: point, modifiers: .shift)

  #expect(view.selectedRange().length > anchorBefore.length)
  #expect(NSMaxRange(view.selectedRange()) > NSMaxRange(anchorBefore))
}
