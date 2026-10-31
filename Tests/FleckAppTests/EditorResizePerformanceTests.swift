import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func editorRepeatedResizeSettlesWithoutTextFrameChurn() throws {
  let body = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
  body.isVerticallyResizable = true
  body.isHorizontallyResizable = false
  body.textContainerInset = NSSize(width: 16, height: 8)
  body.textContainer?.widthTracksTextView = true
  body.textContainer?.heightTracksTextView = false
  body.string = String(repeating: "Synthetic resize paragraph with enough words to wrap at narrow widths.\n", count: 120)
  let document = NativeEditorDocumentView(
    titleField: NSTextField(string: "Synthetic resize fixture"),
    textView: body
  )
  let scroll = NativeEditorScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
  scroll.hasVerticalScroller = true
  scroll.documentView = document
  let original = body.string
  let selection = NSRange(location: 40, length: 12)
  body.setSelectedRange(selection)
  let counter = EditorResizeFrameCounter()
  body.postsFrameChangedNotifications = true
  let observer = NotificationCenter.default.addObserver(
    forName: NSView.frameDidChangeNotification,
    object: body,
    queue: nil
  ) { _ in
    MainActor.assumeIsolated {
      counter.count += 1
      if counter.frames.count < 8 { counter.frames.append(body.frame) }
    }
  }
  defer { NotificationCenter.default.removeObserver(observer) }

  let clock = ContinuousClock()
  let resizeStart = clock.now
  for width in [CGFloat(380), 900, 380, 900, 380, 900, 380, 520] {
    scroll.setFrameSize(NSSize(width: width, height: 400))
    scroll.relayoutDocument()
  }
  let resizeDuration = resizeStart.duration(to: clock.now)
  let resizeChanges = counter.count
  counter.count = 0
  counter.frames = []
  print("RESIZE_LAYOUT_INPUT frame=\(body.frame) document=\(document.frame) container=\(body.textContainer?.containerSize ?? .zero) min=\(body.minSize) max=\(body.maxSize) autoresizing=\(body.autoresizingMask.rawValue) viewport=\(scroll.contentView.bounds)")
  let settledStart = clock.now
  for _ in 0..<30 { scroll.relayoutDocument() }
  let settledDuration = settledStart.duration(to: clock.now)
  print("RESIZE_LAYOUT_METRICS resize=\(resizeDuration) resizeFrameChanges=\(resizeChanges) settled=\(settledDuration) settledFrameChanges=\(counter.count)")
  print("RESIZE_LAYOUT_FRAME_SAMPLE \(counter.frames)")

  #expect(counter.count == 0)
  #expect(body.string == original)
  #expect(body.selectedRange() == selection)
  let container = try #require(body.textContainer)
  let manager = try #require(body.layoutManager)
  #expect(body.frame.height >= manager.usedRect(for: container).height)
  body.string = "Short replacement"
  scroll.relayoutDocument()
  #expect(document.frame.height >= scroll.contentView.bounds.height)
  #expect(document.frame.height < 800)
}

@MainActor private final class EditorResizeFrameCounter {
  var count = 0
  var frames: [NSRect] = []
}
