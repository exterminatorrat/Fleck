import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func clickDepthEditor(
  _ text: String,
  usePlainTextView: Bool = false
) -> (NSTextView, EditorMouseTestWindow) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 200)
  let view: NSTextView
  if usePlainTextView {
    // Match Fleck's TextKit 1 setup while leaving selection entirely to AppKit.
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(
      size: NSSize(width: frame.width, height: 10_000_000)
    )
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    storage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    view = NSTextView(frame: frame, textContainer: textContainer)
    view.isHorizontallyResizable = false
    view.isVerticallyResizable = true
    view.minSize = frame.size
    view.maxSize = NSSize(width: frame.width, height: 10_000_000)
  } else {
    view = ListAwareTextView(frame: frame)
  }
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
  return (view, window)
}

// The plain NSTextView case verifies the event fixture independently of Fleck's
// selection overrides; both implementations must retain native click depth.
@Test(arguments: [true, false])
@MainActor func doubleClickSelectsTheWordUnderThePointer(usePlainTextView: Bool) async throws {
  let (view, window) = clickDepthEditor("alpha beta gamma", usePlainTextView: usePlainTextView)
  defer { closeEditorTestWindow(window) }
  try await window.prepareForClick()

  let point = try #require(editorCharacterPoint(view, at: 1))
  try window.click(view, at: point, clickCount: 2)

  let selection = view.selectedRange()
  #expect(
    (view.string as NSString).substring(with: selection) == "alpha",
    "selected \(selection) of \(view.string.debugDescription)"
  )
}

@Test(arguments: [true, false])
@MainActor func tripleClickSelectsTheParagraphUnderThePointer(usePlainTextView: Bool) async throws {
  let (view, window) = clickDepthEditor("first line\nsecond line", usePlainTextView: usePlainTextView)
  defer { closeEditorTestWindow(window) }
  try await window.prepareForClick()

  let point = try #require(editorCharacterPoint(view, at: 2))
  try window.click(view, at: point, clickCount: 3)

  let selected = (view.string as NSString).substring(with: view.selectedRange())
  #expect(selected.hasPrefix("first line"), "selected \(selected.debugDescription)")
  #expect(!selected.contains("second"), "selected \(selected.debugDescription)")
}

@Test @MainActor func doubleClickOnAChecklistMarkerStillTogglesIt() async throws {
  let (editor, window) = clickDepthEditor("○ one\n○ two")
  defer { closeEditorTestWindow(window) }
  try await window.prepareForClick()
  let view = try #require(editor as? ListAwareTextView)

  let hitRect = try #require(view.checklistHitRect(for: NSRange(location: 0, length: 1)))
  try window.click(
    view,
    at: NSPoint(x: hitRect.midX, y: hitRect.midY),
    clickCount: 2
  )

  #expect(view.string.hasPrefix("● one"))
  #expect(view.string.hasSuffix("○ two"))
}

@Test(arguments: [true, false])
@MainActor func shiftClickExtendsTheSelectionNatively(usePlainTextView: Bool) async throws {
  let (view, window) = clickDepthEditor("alpha beta gamma", usePlainTextView: usePlainTextView)
  defer { closeEditorTestWindow(window) }
  try await window.prepareForClick()

  view.setSelectedRange(NSRange(location: 0, length: 5))
  let anchorBefore = view.selectedRange()
  let point = try #require(editorCharacterPoint(view, at: 8))
  let insertionIndex = view.characterIndexForInsertion(at: point)
  try #require(insertionIndex > NSMaxRange(anchorBefore))
  try #require(insertionIndex < (view.string as NSString).length)
  try window.click(view, at: point, modifiers: .shift)

  #expect(
    view.selectedRange()
      == NSRange(location: anchorBefore.location, length: insertionIndex - anchorBefore.location)
  )
}
