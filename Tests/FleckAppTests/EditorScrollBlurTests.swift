import AppKit
import CoreImage
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func editorScrollBlurIsOffByDefaultAndTogglesAtRuntime() throws {
  let (scrollView, textView) = makeEditorScrollView(long: true, showScrollEdgeBlur: false)
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))
  let originalText = textView.string
  let selection = NSRange(location: 8, length: 5)
  textView.setSelectedRange(selection)

  scrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  #expect(effectViews.allSatisfy { $0.isHidden })

  scrollView.showScrollEdgeBlur = true
  #expect(effectViews.allSatisfy { !$0.isHidden })
  #expect(effectViews.allSatisfy { $0.alphaValue > 0 })
  #expect(effectViews.allSatisfy { $0.alphaValue < 1 })
  #expect(scrollView.contentView.bounds.origin.y == 12)
  #expect(textView.string == originalText)
  #expect(textView.selectedRange() == selection)

  scrollView.showScrollEdgeBlur = false
  #expect(effectViews.allSatisfy { $0.isHidden })
}

@Test @MainActor func editorScrollBlurAppearsOnlyAfterScrollingWithoutChangingEditorState() throws {
  let (scrollView, textView) = makeEditorScrollView(long: true)
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))
  let originalText = textView.string
  let selection = NSRange(location: 8, length: 5)
  textView.setSelectedRange(selection)

  #expect(effectViews.allSatisfy { $0.isHidden })
  scrollView.contentView.scroll(to: NSPoint(x: 0, y: 10))
  scrollView.reflectScrolledClipView(scrollView.contentView)

  #expect(effectViews.allSatisfy { !$0.isHidden })
  #expect(effectViews.allSatisfy { $0.alphaValue > 0 && $0.alphaValue < 1 })
  #expect(scrollView.contentView.bounds.origin.y == 10)
  #expect(textView.string == originalText)
  #expect(textView.selectedRange() == selection)

  scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: -4))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  #expect(effectViews.allSatisfy { $0.isHidden })
}

@Test @MainActor func editorScrollBlurStaysClearAtTopForShortContentAndReducedTransparency() throws {
  let (longScrollView, _) = makeEditorScrollView(long: true)
  let longEffectViews = try #require(scrollEdgeEffectViews(in: longScrollView))

  #expect(longEffectViews.allSatisfy { $0.isHidden })
  longScrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
  longScrollView.reflectScrolledClipView(longScrollView.contentView)
  #expect(longEffectViews.allSatisfy { !$0.isHidden })

  longScrollView.reduceTransparency = true
  #expect(longEffectViews.allSatisfy { $0.isHidden })
  longScrollView.reduceTransparency = false
  #expect(longEffectViews.allSatisfy { !$0.isHidden })

  let (shortScrollView, _) = makeEditorScrollView(long: false)
  let shortEffectViews = try #require(scrollEdgeEffectViews(in: shortScrollView))
  shortScrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
  shortScrollView.reflectScrolledClipView(shortScrollView.contentView)
  #expect(shortEffectViews.allSatisfy { $0.isHidden })
}

@Test @MainActor func editorScrollBlurUsesNativeTopEdgeGeometryAndPassesInteractionsThrough() throws {
  let (scrollView, _) = makeEditorScrollView(long: true)
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))
  let bands = defaultScrollEdgeBlurBands()
  #expect(effectViews.count == bands.count)

  #expect(scrollView.isFlipped)
  for (view, band) in zip(effectViews, bands) {
    #expect(!view.isFlipped)
    #expect(view.frame.height == min(band.depth, scrollView.contentView.frame.height))
    #expect(view.frame.minY == scrollView.contentView.frame.minY)
    #expect(view.hitTest(NSPoint(x: 4, y: 4)) == nil)
    #expect(!view.isAccessibilityElement())
  }

  scrollView.setFrameSize(NSSize(width: 460, height: 180))
  scrollView.needsLayout = true
  scrollView.layoutSubtreeIfNeeded()

  for (view, band) in zip(effectViews, bands) {
    #expect(view.frame.width == scrollView.contentView.frame.width)
    #expect(view.frame.height == min(band.depth, scrollView.contentView.frame.height))
    #expect(view.frame.minY == scrollView.contentView.frame.minY)
    #expect(view.layer?.mask?.frame == view.bounds)
  }
}

@Test @MainActor func editorScrollBlurUsesTintFreeBackgroundFilter() throws {
  let (scrollView, _) = makeEditorScrollView(long: true)
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))
  let bands = defaultScrollEdgeBlurBands()
  #expect(effectViews.count == bands.count)

  for (view, band) in zip(effectViews, bands) {
    #expect(!(view is NSVisualEffectView))
    #expect(!view.isOpaque)
    #expect(view.layer?.backgroundColor == nil)
    #expect(view.layer?.contents == nil)
    #expect(view.layer?.masksToBounds == true)
    #expect(view.subviews.isEmpty)
    #expect(view.blurRadius == band.blurRadius)

    let backgroundFilters = view.backgroundFilters
    #expect(backgroundFilters.count == 1)
    let filter = try #require(backgroundFilters.first)
    #expect(filter.name == "CIGaussianBlur")
    let radius = try #require(
      (filter.value(forKey: kCIInputRadiusKey) as? NSNumber)?.doubleValue
    )
    #expect(radius == Double(band.blurRadius))

    let maskLayer = try #require(view.layer?.mask)
    #expect(maskLayer.contents != nil)
    #expect(maskLayer.contentsGravity == .resize)
  }
}

@Test @MainActor func editorScrollBlurMasksFadeMonotonicallyFromTheTop() throws {
  let (scrollView, _) = makeEditorScrollView(long: true)
  let bands = defaultScrollEdgeBlurBands()
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))

  let fullDepth = try #require(bands.map(\.depth).max())
  let strongestRadius = try #require(bands.map(\.blurRadius).max())
  #expect(bands.count == 3)
  #expect((12.0...18.0).contains(Double(fullDepth)))
  #expect(Double(strongestRadius) <= 1.1)
  for (deeper, shallower) in zip(bands, bands.dropFirst()) {
    #expect(deeper.blurRadius > shallower.blurRadius)
    #expect(deeper.depth > shallower.depth)
  }

  // NSBitmapImageRep row 0 is the top row, and rendering the layer into an
  // unflipped context maps the layer's top to row 0. The scroll edge effect
  // must therefore be strongest at row 0 and fully clear at the last row.
  let calibration = try makeMaskBitmap(pixelsHigh: 20)
  let calibrationContext = try #require(NSGraphicsContext(bitmapImageRep: calibration))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = calibrationContext
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: 1, height: 20).fill(using: .copy)
  NSColor.white.setFill()
  NSRect(x: 0, y: 0, width: 1, height: 1).fill(using: .copy)
  NSGraphicsContext.restoreGraphicsState()
  #expect(!calibrationContext.isFlipped)
  let calibrationTopAlpha = try #require(
    calibration.colorAt(x: 0, y: 0)
  ).alphaComponent
  let calibrationBottomAlpha = try #require(
    calibration.colorAt(x: 0, y: 19)
  ).alphaComponent
  #expect(calibrationTopAlpha == 0)
  #expect(calibrationBottomAlpha == 1)

  for (view, band) in zip(effectViews, bands) {
    let pixels = max(1, Int(band.depth.rounded(.up)))
    let maskLayer = try #require(view.layer?.mask)
    let rendered = try makeMaskBitmap(pixelsHigh: pixels)
    let context = try #require(NSGraphicsContext(bitmapImageRep: rendered))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: 1, y: CGFloat(pixels) / band.depth)
    maskLayer.render(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    let topAlpha = try #require(rendered.colorAt(x: 0, y: 0)).alphaComponent
    let middleAlpha = try #require(
      rendered.colorAt(x: 0, y: pixels / 2)
    ).alphaComponent
    let bottomAlpha = try #require(
      rendered.colorAt(x: 0, y: pixels - 1)
    ).alphaComponent
    #expect(topAlpha > 0.9)
    #expect(middleAlpha > 0.2)
    #expect(middleAlpha < 0.8)
    #expect(bottomAlpha < 0.05)
  }
}

@Test @MainActor func editorScrollBlurMaskMathIsMonotonicWithoutCutoffs() {
  let bands = defaultScrollEdgeBlurBands()

  for band in bands {
    #expect(NativeEditorScrollView.scrollEdgeMaskAlpha(depth: 0, band: band) == 1)
    #expect(NativeEditorScrollView.scrollEdgeMaskAlpha(depth: band.depth, band: band) == 0)
    #expect(NativeEditorScrollView.scrollEdgeMaskAlpha(depth: -1, band: band) == 1)

    var previous: CGFloat = 1
    var largestStep: CGFloat = 0
    for step in 0...(Int(band.depth * 10) + 1) {
      let alpha = NativeEditorScrollView.scrollEdgeMaskAlpha(
        depth: CGFloat(step) / 10,
        band: band
      )
      #expect(alpha <= previous + 0.0001)
      largestStep = max(largestStep, previous - alpha)
      previous = alpha
    }
    #expect(largestStep < 0.05)
  }

  #expect(scrollEdgeCompositeAlpha(depth: 0, bands: bands) == 1)
  let fullDepth = bands.map(\.depth).max() ?? 0
  #expect(scrollEdgeCompositeAlpha(depth: fullDepth, bands: bands) == 0)
  #expect(scrollEdgeCompositeAlpha(depth: fullDepth + 10, bands: bands) == 0)

  var previous: CGFloat = 1
  var largestStep: CGFloat = 0
  for step in 0...(Int(fullDepth * 10) + 1) {
    let alpha = scrollEdgeCompositeAlpha(
      depth: CGFloat(step) / 10,
      bands: bands
    )
    #expect(alpha <= previous + 0.0001)
    largestStep = max(largestStep, previous - alpha)
    previous = alpha
  }
  #expect(largestStep < 0.05)
}

@Test @MainActor func editorScrollBlurAmountScalesBandsWithinBounds() throws {
  #expect(NativeEditorScrollView.scrollEdgeBands(forAmount: 0).isEmpty)
  #expect(NativeEditorScrollView.scrollEdgeBands(forAmount: -1).isEmpty)

  let fullBands = NativeEditorScrollView.scrollEdgeBands(forAmount: 1)
  #expect(fullBands == NativeEditorScrollView.scrollEdgeBands(forAmount: 4))
  #expect(fullBands.count == 3)
  let fullDepth = try #require(fullBands.map(\.depth).max())
  let fullRadius = try #require(fullBands.map(\.blurRadius).max())
  #expect(Double(fullDepth) <= Double(NativeEditorScrollView.scrollEdgeBlurMaximumDepth))
  #expect(Double(fullRadius) <= Double(NativeEditorScrollView.scrollEdgeBlurMaximumRadius))

  let defaultBands = defaultScrollEdgeBlurBands()
  let defaultDepth = try #require(defaultBands.map(\.depth).max())
  let defaultRadius = try #require(defaultBands.map(\.blurRadius).max())
  #expect((12.0...18.0).contains(Double(defaultDepth)))
  #expect(abs(Double(defaultRadius) - 1) < 0.1)

  let halfBands = NativeEditorScrollView.scrollEdgeBands(forAmount: 0.5)
  #expect((halfBands.first?.depth ?? 0) > (defaultBands.first?.depth ?? 0))
  #expect((halfBands.first?.blurRadius ?? 0) > (defaultBands.first?.blurRadius ?? 0))

  for amount in [0.05, 0.35, 0.7, 1.0] {
    let bands = NativeEditorScrollView.scrollEdgeBands(forAmount: amount)
    #expect(bands.count == 3)
    #expect(
      zip(bands, bands.dropFirst()).allSatisfy {
        $0.depth > $1.depth && $0.blurRadius > $1.blurRadius
      }
    )
  }
}

@Test @MainActor func editorScrollBlurAmountChangesOnlyTheEffect() throws {
  let (scrollView, textView) = makeEditorScrollView(
    long: true,
    showScrollEdgeBlur: true,
    scrollEdgeBlurAmount: 0.2
  )
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))
  scrollView.contentView.scroll(to: NSPoint(x: 0, y: 30))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  let originalText = textView.string
  let selection = NSRange(location: 4, length: 6)
  textView.setSelectedRange(selection)
  let originalBounds = scrollView.contentView.bounds
  let documentView = try #require(scrollView.documentView)
  let originalDocumentFrame = documentView.frame
  let initialRadii = effectViews.map(\.blurRadius)

  scrollView.scrollEdgeBlurAmount = 0.9
  let raisedBands = NativeEditorScrollView.scrollEdgeBands(forAmount: 0.9)
  #expect(zip(effectViews, raisedBands).allSatisfy { $0.blurRadius == $1.blurRadius })
  #expect((effectViews.first?.blurRadius ?? 0) > (initialRadii.first ?? 0))
  #expect(effectViews.allSatisfy { !$0.isHidden })
  #expect(effectViews.allSatisfy { $0.layer?.mask?.contents != nil })
  #expect(textView.string == originalText)
  #expect(textView.selectedRange() == selection)
  #expect(scrollView.contentView.bounds == originalBounds)
  #expect(documentView.frame == originalDocumentFrame)

  scrollView.scrollEdgeBlurAmount = 0
  #expect(effectViews.allSatisfy { $0.isHidden })
  #expect(effectViews.allSatisfy { $0.backgroundFilters.isEmpty })
  #expect(textView.string == originalText)
  #expect(textView.selectedRange() == selection)
  #expect(scrollView.contentView.bounds == originalBounds)
  #expect(documentView.frame == originalDocumentFrame)
}

@Test @MainActor func editorScrollBlurClearsWhenLongContentIsReplaced() throws {
  let (scrollView, textView) = makeEditorScrollView(long: true)
  let effectViews = try #require(scrollEdgeEffectViews(in: scrollView))
  scrollView.contentView.scroll(to: NSPoint(x: 0, y: 20))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  #expect(effectViews.allSatisfy { !$0.isHidden })

  textView.string = "Short note"
  textView.setSelectedRange(NSRange(location: 5, length: 0))
  scrollView.relayoutDocument()

  #expect(effectViews.allSatisfy { $0.isHidden })
  #expect(textView.string == "Short note")
  #expect(textView.selectedRange() == NSRange(location: 5, length: 0))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLECK_NATIVE_CAPTURE_QA"] == "1"))
@MainActor func scrollEdgeBlurNativeVisualFixtureWhenRequested() async throws {
  let (scrollView, textView) = makeEditorScrollView(long: true, showScrollEdgeBlur: false)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = scrollView
  scrollView.autoresizingMask = [.width, .height]
  textView.font = .systemFont(ofSize: 18)
  textView.textColor = .textColor
  textView.backgroundColor = .textBackgroundColor
  textView.string = (1...40).map {
    "Line \($0): a quiet edge should fade into readable notes."
  }.joined(separator: "\n")
  defer {
    window.orderOut(nil)
    window.contentView = nil
  }
  window.center()
  window.makeKeyAndOrderFront(nil)
  for name in [NSAppearance.Name.aqua, .darkAqua] {
    window.appearance = NSAppearance(named: name)
    for enabled in [false, true] {
      scrollView.showScrollEdgeBlur = enabled
      let amounts =
        enabled
        ? [AppPreferences.defaultScrollEdgeBlurAmount, 0.8]
        : [AppPreferences.defaultScrollEdgeBlurAmount]
      for amount in amounts {
        scrollView.scrollEdgeBlurAmount = amount
        scrollView.relayoutDocument()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 95))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        window.title =
          "FLEC-165 Blur \(name.rawValue) \(enabled ? "on" : "off") \(Int(amount * 100))%"
        try await Task.sleep(for: .seconds(10))
      }
    }
  }
}

@MainActor
private func makeEditorScrollView(
  long: Bool,
  showScrollEdgeBlur: Bool = true,
  scrollEdgeBlurAmount: Double = AppPreferences.defaultScrollEdgeBlurAmount
) -> (NativeEditorScrollView, ListAwareTextView) {
  let scrollView = NativeEditorScrollView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 120)
  )
  scrollView.hasVerticalScroller = true
  scrollView.autohidesScrollers = true
  scrollView.showScrollEdgeBlur = showScrollEdgeBlur
  scrollView.scrollEdgeBlurAmount = scrollEdgeBlurAmount

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
private func scrollEdgeCompositeAlpha(
  depth: CGFloat,
  bands: [NativeEditorScrollView.ScrollEdgeBlurBand]
) -> CGFloat {
  bands.reduce(CGFloat(0)) { visibility, band in
    let bandVisibility = NativeEditorScrollView.scrollEdgeMaskAlpha(
      depth: depth,
      band: band
    )
    return 1 - (1 - visibility) * (1 - bandVisibility)
  }
}

@MainActor
private func defaultScrollEdgeBlurBands()
  -> [NativeEditorScrollView.ScrollEdgeBlurBand]
{
  NativeEditorScrollView.scrollEdgeBands(
    forAmount: AppPreferences.defaultScrollEdgeBlurAmount
  )
}

@MainActor
private func scrollEdgeEffectViews(in scrollView: NativeEditorScrollView)
  -> [EditorScrollEdgeBlurView]?
{
  let effectViews = scrollView.subviews.compactMap { $0 as? EditorScrollEdgeBlurView }
    .sorted { $0.blurRadius > $1.blurRadius }
  return effectViews.isEmpty ? nil : effectViews
}

private func makeMaskBitmap(pixelsHigh: Int) throws -> NSBitmapImageRep {
  try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 1,
      pixelsHigh: pixelsHigh,
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
