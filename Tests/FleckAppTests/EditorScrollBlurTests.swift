import AppKit
import CoreImage
import Testing

@testable import FleckApp

@Test @MainActor func editorScrollBlurAppearsOnlyAfterScrollingWithoutChangingEditorState() throws {
  let (scrollView, textView) = makeEditorScrollView(long: true)
  let effectView = try #require(scrollEdgeEffectView(in: scrollView))
  let originalText = textView.string
  let selection = NSRange(location: 8, length: 5)
  textView.setSelectedRange(selection)

  #expect(effectView.isHidden)
  scrollView.contentView.scroll(to: NSPoint(x: 0, y: 10))
  scrollView.reflectScrolledClipView(scrollView.contentView)

  #expect(!effectView.isHidden)
  #expect(effectView.alphaValue > 0)
  #expect(effectView.alphaValue < 1)
  #expect(scrollView.contentView.bounds.origin.y == 10)
  #expect(textView.string == originalText)
  #expect(textView.selectedRange() == selection)

  scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: -4))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  #expect(effectView.isHidden)
}

@Test @MainActor func editorScrollBlurStaysClearAtTopForShortContentAndReducedTransparency() throws {
  let (longScrollView, _) = makeEditorScrollView(long: true)
  let longEffectView = try #require(scrollEdgeEffectView(in: longScrollView))

  #expect(longEffectView.isHidden)
  longScrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
  longScrollView.reflectScrolledClipView(longScrollView.contentView)
  #expect(!longEffectView.isHidden)

  longScrollView.reduceTransparency = true
  #expect(longEffectView.isHidden)
  longScrollView.reduceTransparency = false
  #expect(!longEffectView.isHidden)

  let (shortScrollView, _) = makeEditorScrollView(long: false)
  let shortEffectView = try #require(scrollEdgeEffectView(in: shortScrollView))
  shortScrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
  shortScrollView.reflectScrolledClipView(shortScrollView.contentView)
  #expect(shortEffectView.isHidden)
}

@Test @MainActor func editorScrollBlurUsesNativeTopEdgeGeometryAndPassesInteractionsThrough() throws {
  let (scrollView, _) = makeEditorScrollView(long: true)
  let effectView = try #require(scrollEdgeEffectView(in: scrollView))

  #expect(scrollView.isFlipped)
  #expect(!effectView.isFlipped)
  #expect(effectView.frame.height == 20)
  #expect(effectView.frame.minY == scrollView.contentView.frame.minY)
  #expect(effectView.hitTest(NSPoint(x: 4, y: 4)) == nil)
  #expect(!effectView.isAccessibilityElement())

  scrollView.setFrameSize(NSSize(width: 460, height: 180))
  scrollView.needsLayout = true
  scrollView.layoutSubtreeIfNeeded()

  #expect(effectView.frame.width == scrollView.contentView.frame.width)
  #expect(effectView.frame.height == 20)
  #expect(effectView.frame.minY == scrollView.contentView.frame.minY)
  #expect(effectView.layer?.mask?.frame == effectView.bounds)
}

@Test @MainActor func editorScrollBlurUsesTintFreeBackgroundFilter() throws {
  let (scrollView, _) = makeEditorScrollView(long: true)
  let blurView = try #require(scrollEdgeEffectView(in: scrollView))

  #expect(!(blurView is NSVisualEffectView))
  let configuredBlurView = try #require(blurView as? EditorScrollEdgeBlurView)
  #expect(!blurView.isOpaque)
  #expect(blurView.layer?.backgroundColor == nil)
  #expect(blurView.layer?.contents == nil)
  #expect(blurView.layer?.masksToBounds == true)
  #expect(blurView.subviews.isEmpty)
  let backgroundFilters = blurView.backgroundFilters
  #expect(backgroundFilters.count == 1)
  let filter = try #require(backgroundFilters.first)
  #expect(filter.name == "CIGaussianBlur")
  #expect(configuredBlurView.blurRadius == 2)

  let maskLayer = try #require(blurView.layer?.mask)
  #expect(maskLayer.contents != nil)
  let calibration = try makeMaskBitmap()
  let calibrationContext = try #require(NSGraphicsContext(bitmapImageRep: calibration))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = calibrationContext
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: 1, height: 20).fill(using: .copy)
  NSColor.white.setFill()
  NSRect(x: 0, y: 0, width: 1, height: 1).fill(using: .copy)
  NSGraphicsContext.restoreGraphicsState()
  #expect(!calibrationContext.isFlipped)
  let calibrationTopAlpha = try #require(calibration.colorAt(x: 0, y: 0)).alphaComponent
  let calibrationBottomAlpha = try #require(calibration.colorAt(x: 0, y: 19)).alphaComponent
  #expect(calibrationTopAlpha == 0)
  #expect(calibrationBottomAlpha == 1)

  let renderedMask = try makeMaskBitmap()
  let maskContext = try #require(NSGraphicsContext(bitmapImageRep: renderedMask))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = maskContext
  maskLayer.render(in: maskContext.cgContext)
  NSGraphicsContext.restoreGraphicsState()
  let displayedTopAlpha = try #require(renderedMask.colorAt(x: 0, y: 0)).alphaComponent
  let displayedBottomAlpha = try #require(renderedMask.colorAt(x: 0, y: 19)).alphaComponent
  #expect(displayedTopAlpha > displayedBottomAlpha + 0.5)
}

@Test @MainActor func editorScrollBlurClearsWhenLongContentIsReplaced() throws {
  let (scrollView, textView) = makeEditorScrollView(long: true)
  let effectView = try #require(scrollEdgeEffectView(in: scrollView))
  scrollView.contentView.scroll(to: NSPoint(x: 0, y: 20))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  #expect(!effectView.isHidden)

  textView.string = "Short note"
  textView.setSelectedRange(NSRange(location: 5, length: 0))
  scrollView.relayoutDocument()

  #expect(effectView.isHidden)
  #expect(textView.string == "Short note")
  #expect(textView.selectedRange() == NSRange(location: 5, length: 0))
}

@MainActor
private func makeEditorScrollView(long: Bool) -> (NativeEditorScrollView, ListAwareTextView) {
  let scrollView = NativeEditorScrollView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 120)
  )
  scrollView.hasVerticalScroller = true
  scrollView.autohidesScrollers = true

  let textView = ListAwareTextView(frame: .zero)
  textView.isVerticallyResizable = true
  textView.isHorizontallyResizable = false
  textView.textContainerInset = NSSize(width: 16, height: 8)
  textView.textContainer?.lineFragmentPadding = 0
  textView.textContainer?.widthTracksTextView = true
  textView.textContainer?.heightTracksTextView = false
  textView.textContainer?.containerSize = NSSize(
    width: 0,
    height: CGFloat.greatestFiniteMagnitude
  )
  textView.string = long
    ? (0..<30).map { "Line \($0)" }.joined(separator: "\n")
    : "Short note"

  scrollView.documentView = NativeEditorDocumentView(
    titleField: NSTextField(labelWithString: "Title"),
    textView: textView
  )
  scrollView.relayoutDocument()
  return (scrollView, textView)
}

@MainActor
private func scrollEdgeEffectView(in scrollView: NativeEditorScrollView) -> NSView? {
  scrollView.subviews.first { view in
    view is NSVisualEffectView
      || view.backgroundFilters.contains { $0.name == "CIGaussianBlur" }
  }
}

private func makeMaskBitmap() throws -> NSBitmapImageRep {
  try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 1,
      pixelsHigh: 20,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bitmapFormat: [],
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
}
