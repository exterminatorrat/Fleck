#if os(macOS)
import AppKit
import Foundation

@MainActor
final class InlineImageEditingController {
  private struct Selection {
    let attachment: InlineNoteImageAttachment
    let range: NSRange
  }

  private enum DragKind {
    case resize(InlineImageHandle)
    case rotate(grabAngleDegrees: Double)
  }

  private struct DragState {
    let attachment: InlineNoteImageAttachment
    let range: NSRange
    let selection: NSRange
    let originalTransform: InlineImageTransform
    let canonicalTransform: InlineImageTransform
    let availableWidth: CGFloat
    let originalLayout: InlineImageEditingLayout
    let grabPoint: NSPoint
    let kind: DragKind
    var previewTransform: InlineImageTransform?
    var previewLayout: InlineImageEditingLayout?
    var previewImage: NSImage?
  }

  private weak var textView: ListAwareTextView?
  private var dragState: DragState?
  private var activeHoverCursor: NSCursor?

  init(textView: ListAwareTextView) {
    self.textView = textView
  }

  var isDragging: Bool {
    dragState != nil
  }

  var currentLayout: InlineImageEditingLayout? {
    if let previewLayout = dragState?.previewLayout {
      return visibleRotationHandle(in: previewLayout)
    }
    guard let selection = selectedAttachment() else { return nil }
    return layout(for: selection)
  }

  func begin(with event: NSEvent) -> Bool {
    guard dragState == nil,
      let textView,
      textView.isEditable,
      let point = viewPoint(for: event)
    else { return false }

    if let selection = selectedAttachment(),
      let editingLayout = layout(for: selection)
    {
      switch editingLayout.hitTarget(at: point) {
      case .resize(let handle):
        startResize(
          handle: handle,
          at: point,
          selection: selection,
          layout: editingLayout
        )
        return true
      case .rotate:
        return startRotation(at: point, selection: selection, layout: editingLayout)
      case .body:
        return captureBodyClick(selection, event: event)
      case .none:
        break
      }
    }

    guard event.clickCount == 1,
      event.modifierFlags.intersection([.shift, .command]).isEmpty,
      let selection = attachment(at: point)
    else { return false }
    textView.setSelectedRange(selection.range)
    textView.needsDisplay = true
    invalidateCursorRects()
    return true
  }

  func drag(with event: NSEvent) {
    guard var state = dragState,
      let textView,
      let point = viewPoint(for: event)
    else { return }
    guard isCurrent(state) else {
      cancel()
      return
    }
    guard
      let preview = makePreview(
        for: state,
        at: point,
        snapRotation: event.modifierFlags.contains(.shift)
      )
    else { return }
    applyPreview(preview.transform, layout: preview.layout, to: &state)
    dragState = state
    textView.needsDisplay = true
  }

  func end(with event: NSEvent) {
    guard let state = dragState else { return }
    dragState = nil
    defer {
      textView?.needsDisplay = true
      invalidateCursorRects()
    }
    guard isCurrent(state),
      let point = viewPoint(for: event),
      let preview = makePreview(
        for: state,
        at: point,
        snapRotation: event.modifierFlags.contains(.shift)
      ),
      preview.transform != state.canonicalTransform
    else { return }
    _ = textView?.applyInlineImageTransform(
      transform: preview.transform,
      range: state.range
    )
  }

  @discardableResult
  func cancel() -> Bool {
    guard dragState != nil else { return false }
    dragState = nil
    textView?.needsDisplay = true
    invalidateCursorRects()
    return true
  }

  func draw() {
    guard let layout = currentLayout else { return }
    if let previewImage = dragState?.previewImage {
      fillPreviewBackground()
      previewImage.draw(
        in: layout.bounds,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
      )
    }
    drawOutline(layout)
    guard let textView, textView.isEditable else { return }
    drawHandles(layout)
    drawRotationHandle(layout)
  }

  func addCursorRects() {
    guard let textView, textView.isEditable, let layout = currentLayout else { return }
    let visibleRect = textView.visibleRect
    let radius = InlineImageEditingLayout.handleCursorRectRadius
    let rotationDegrees = layout.transform.rotationDegrees
    for handle in InlineImageHandle.allCases {
      guard let center = layout.handleCenters[handle] else { continue }
      let rect = hitRect(around: center, radius: radius)
      guard rect.intersects(visibleRect) else { continue }
      textView.addCursorRect(rect, cursor: cursor(for: handle, rotationDegrees: rotationDegrees))
    }
    let rotationRect = hitRect(around: layout.rotationHandleCenter, radius: radius)
    guard rotationRect.intersects(visibleRect) else { return }
    textView.addCursorRect(rotationRect, cursor: .crosshair)
  }

  func hoverCursor(at point: NSPoint) -> NSCursor? {
    guard dragState == nil,
      textView?.isEditable == true,
      let layout = currentLayout
    else { return nil }
    switch layout.hitTarget(at: point) {
    case .resize(let handle):
      return cursor(for: handle, rotationDegrees: layout.transform.rotationDegrees)
    case .rotate:
      return .crosshair
    case .body, .none:
      return nil
    }
  }

  @discardableResult
  func updateHoverCursor(at point: NSPoint) -> Bool {
    let claimed = hoverCursor(at: point)
    let previous = activeHoverCursor
    activeHoverCursor = claimed
    guard let claimed else {
      restoreTextCursor(from: previous)
      return false
    }
    guard NSCursor.current !== claimed else { return true }
    claimed.set()
    return true
  }

  func clearHoverCursor() {
    activeHoverCursor = nil
  }

  private func restoreTextCursor(from previous: NSCursor?) {
    guard let previous, NSCursor.current === previous else { return }
    NSCursor.iBeam.set()
  }

  private func startResize(
    handle: InlineImageHandle,
    at point: NSPoint,
    selection: Selection,
    layout: InlineImageEditingLayout
  ) {
    dragState = DragState(
      attachment: selection.attachment,
      range: selection.range,
      selection: selection.range,
      originalTransform: layout.transform,
      canonicalTransform: selection.attachment.displayTransform ?? layout.transform,
      availableWidth: availableWidth(at: selection.range),
      originalLayout: layout,
      grabPoint: point,
      kind: .resize(handle)
    )
    invalidateCursorRects()
  }

  private func startRotation(
    at point: NSPoint,
    selection: Selection,
    layout: InlineImageEditingLayout
  ) -> Bool {
    guard let grabAngle = pointerAngle(from: layout.center, to: point) else {
      return false
    }
    dragState = DragState(
      attachment: selection.attachment,
      range: selection.range,
      selection: selection.range,
      originalTransform: layout.transform,
      canonicalTransform: selection.attachment.displayTransform ?? layout.transform,
      availableWidth: availableWidth(at: selection.range),
      originalLayout: layout,
      grabPoint: point,
      kind: .rotate(grabAngleDegrees: grabAngle)
    )
    invalidateCursorRects()
    return true
  }

  private func captureBodyClick(_ selection: Selection, event: NSEvent) -> Bool {
    guard event.clickCount == 1,
      event.modifierFlags.intersection([.shift, .command]).isEmpty,
      let textView
    else { return false }
    if textView.selectedRange() != selection.range {
      textView.setSelectedRange(selection.range)
    }
    textView.needsDisplay = true
    invalidateCursorRects()
    return true
  }

  private func makePreview(
    for state: DragState,
    at point: NSPoint,
    snapRotation: Bool
  ) -> (transform: InlineImageTransform, layout: InlineImageEditingLayout)? {
    guard hypot(point.x - state.grabPoint.x, point.y - state.grabPoint.y) >= 2 else {
      return (state.canonicalTransform, state.originalLayout)
    }
    switch state.kind {
    case .resize(let handle):
      let delta = NSSize(
        width: point.x - state.grabPoint.x,
        height: point.y - state.grabPoint.y
      )
      guard
        let preview = state.originalTransform.resizePreview(
          dragging: handle,
          pointerDelta: delta,
          center: state.originalLayout.center
        )
      else { return nil }
      return (preview.transform, preview.layout)
    case .rotate(let grabAngleDegrees):
      guard
        let angle = pointerAngle(from: state.originalLayout.center, to: point),
        let delta = normalizedAngleDelta(angle - grabAngleDegrees)
      else { return nil }
      var degrees = state.canonicalTransform.rotationDegrees + delta
      if snapRotation {
        let snap = InlineImageTransform.rotationSnapDegrees
        degrees = (degrees / snap).rounded() * snap
      }
      let transform = InlineImageTransform(
        size: state.canonicalTransform.size,
        rotationDegrees: degrees
      )
      return (
        transform,
        transform.fitting(availableWidth: state.availableWidth)
          .layout(centeredAt: state.originalLayout.center)
      )
    }
  }

  private func applyPreview(
    _ transform: InlineImageTransform,
    layout: InlineImageEditingLayout,
    to state: inout DragState
  ) {
    if state.previewTransform != transform {
      state.previewImage = InlineNoteImageAttachment.renderedImage(
        original: state.attachment.originalImage,
        transform: layout.transform
      )
    }
    state.previewTransform = transform
    state.previewLayout = layout
  }

  private func isCurrent(_ state: DragState) -> Bool {
    guard let textView, let storage = textView.textStorage,
      textView.selectedRange() == state.selection,
      state.range.length == 1,
      state.range.location >= 0,
      NSMaxRange(state.range) <= storage.length,
      let attachment = storage.attribute(
        .attachment,
        at: state.range.location,
        effectiveRange: nil
      ) as? InlineNoteImageAttachment
    else { return false }
    return attachment === state.attachment
  }

  private func selectedAttachment() -> Selection? {
    guard let textView, let storage = textView.textStorage else { return nil }
    let ranges = textView.selectedRanges
    guard ranges.count == 1, let value = ranges.first else { return nil }
    let selection = value.rangeValue
    guard selection.location != NSNotFound,
      selection.length == 1,
      selection.location >= 0,
      NSMaxRange(selection) <= storage.length,
      let attachment = storage.attribute(
        .attachment,
        at: selection.location,
        effectiveRange: nil
      ) as? InlineNoteImageAttachment
    else { return nil }
    return Selection(attachment: attachment, range: selection)
  }

  private func attachment(at point: NSPoint) -> Selection? {
    guard let textView,
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer,
      let storage = textView.textStorage,
      layoutManager.numberOfGlyphs > 0
    else { return nil }
    let textPoint = NSPoint(
      x: point.x - textView.textContainerOrigin.x,
      y: point.y - textView.textContainerOrigin.y
    )
    guard textPoint.x >= 0, textPoint.y >= 0 else { return nil }
    let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
    guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
    let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
    guard characterIndex < storage.length,
      let attachment = storage.attribute(
        .attachment,
        at: characterIndex,
        effectiveRange: nil
      ) as? InlineNoteImageAttachment
    else { return nil }
    let selection = Selection(
      attachment: attachment,
      range: NSRange(location: characterIndex, length: 1)
    )
    guard let editingLayout = layout(for: selection) else { return nil }
    return editingLayout.hitTarget(at: point) == .body ? selection : nil
  }

  private func layout(for selection: Selection) -> InlineImageEditingLayout? {
    guard let textView,
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer,
      let storage = textView.textStorage,
      selection.range.length == 1,
      selection.range.location >= 0,
      NSMaxRange(selection.range) <= storage.length
    else { return nil }
    layoutManager.ensureLayout(for: textContainer)
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: selection.range.location)
    guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
    let lineRect = layoutManager.lineFragmentRect(
      forGlyphAt: glyphIndex,
      effectiveRange: nil
    )
    let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
    let attachmentBounds = selection.attachment.attachmentBounds(
      for: textContainer,
      proposedLineFragment: lineRect,
      glyphPosition: glyphLocation,
      characterIndex: selection.range.location
    )
    guard attachmentBounds.width > 0, attachmentBounds.height > 0 else { return nil }
    let transform: InlineImageTransform
    if selection.attachment.displayTransform == nil {
      transform = InlineImageTransform(size: attachmentBounds.size)
    } else {
      transform = selection.attachment.effectiveTransform(fitting: lineRect)
    }
    guard transform.isValid else { return nil }
    let origin = textView.textContainerOrigin
    let baselineY = origin.y + lineRect.minY + glyphLocation.y
    let center = NSPoint(
      x: origin.x + lineRect.minX + glyphLocation.x + attachmentBounds.midX,
      y: baselineY - attachmentBounds.midY
    )
    return visibleRotationHandle(in: transform.layout(centeredAt: center))
  }

  private func availableWidth(at range: NSRange) -> CGFloat {
    guard let manager = textView?.layoutManager else { return 1 }
    let glyph = manager.glyphIndexForCharacter(at: range.location)
    return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).width
  }

  private func visibleRotationHandle(in layout: InlineImageEditingLayout) -> InlineImageEditingLayout {
    guard let textView else { return layout }
    let center = layout.center
    let margin = InlineImageEditingLayout.rotationHandleRadius + 6
    let safeBounds = textView.bounds.insetBy(dx: margin, dy: margin)
    guard !safeBounds.contains(layout.rotationHandleCenter) else { return layout }
    let opposite = NSPoint(
      x: center.x * 2 - layout.rotationHandleCenter.x,
      y: center.y * 2 - layout.rotationHandleCenter.y
    )
    let rotationCenter = safeBounds.contains(opposite) ? opposite : NSPoint(
      x: min(max(layout.rotationHandleCenter.x, safeBounds.minX), safeBounds.maxX),
      y: min(max(layout.rotationHandleCenter.y, safeBounds.minY), safeBounds.maxY)
    )
    return InlineImageEditingLayout(
      transform: layout.transform, center: center, rotationHandleCenter: rotationCenter
    )
  }

  private func pointerAngle(from center: NSPoint, to point: NSPoint) -> Double? {
    let dx = Double(point.x - center.x)
    let dy = Double(point.y - center.y)
    guard dx != 0 || dy != 0 else { return nil }
    return atan2(dy, dx) * 180 / .pi
  }

  private func normalizedAngleDelta(_ degrees: Double) -> Double? {
    guard degrees.isFinite else { return nil }
    var delta = degrees.truncatingRemainder(dividingBy: 360)
    if delta > 180 { delta -= 360 }
    if delta < -180 { delta += 360 }
    return delta
  }

  private func viewPoint(for event: NSEvent) -> NSPoint? {
    guard let textView else { return nil }
    return textView.convert(event.locationInWindow, from: nil)
  }

  private func hitRect(around center: NSPoint, radius: CGFloat) -> NSRect {
    NSRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    )
  }

  func cursor(for handle: InlineImageHandle, rotationDegrees: Double) -> NSCursor {
    Self.frameResizeCursor(handle.resizeDirection(rotationDegrees: rotationDegrees))
  }

  private static var frameResizeCursors: [InlineImageResizeDirection: NSCursor] = [:]

  private static func frameResizeCursor(_ direction: InlineImageResizeDirection) -> NSCursor {
    if let cached = frameResizeCursors[direction] { return cached }
    let cursor: NSCursor
    if #available(macOS 15.0, *) {
      cursor = NSCursor.frameResize(position: direction.frameResizePosition, directions: .all)
    } else {
      cursor = legacyFrameResizeCursor(direction)
    }
    frameResizeCursors[direction] = cursor
    return cursor
  }

  private static func legacyFrameResizeCursor(_ direction: InlineImageResizeDirection) -> NSCursor {
    let side: CGFloat = 22
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      let radians = CGFloat(direction.screenAngleDegrees) * .pi / 180
      let cosine = cos(radians)
      let sine = sin(radians)
      let place: (CGFloat, CGFloat) -> NSPoint = { horizontal, vertical in
        NSPoint(
          x: rect.midX + horizontal * cosine - vertical * sine,
          y: rect.midY + horizontal * sine + vertical * cosine
        )
      }
      for sign: CGFloat in [-1, 1] {
        let arrowhead = NSBezierPath()
        arrowhead.move(to: place(sign * 9.5, 0))
        arrowhead.line(to: place(sign * 4, 3.4))
        arrowhead.line(to: place(sign * 4, -3.4))
        arrowhead.close()
        NSColor.black.setFill()
        arrowhead.fill()
        arrowhead.lineWidth = 1
        NSColor.white.setStroke()
        arrowhead.stroke()
      }
      return true
    }
    return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
  }

  private func invalidateCursorRects() {
    guard let textView, let window = textView.window else { return }
    window.invalidateCursorRects(for: textView)
  }

  private func fillPreviewBackground() {
    guard let textView, let state = dragState else { return }
    var color = EditorCanvasInk.canvasColor(for: textView)
    if let storage = textView.textStorage,
      state.range.location >= 0,
      NSMaxRange(state.range) <= storage.length,
      let attributeColor = storage.attribute(
        .backgroundColor,
        at: state.range.location,
        effectiveRange: nil
      ) as? NSColor
    {
      color = attributeColor
    }
    color.setFill()
    NSBezierPath(rect: state.originalLayout.bounds).fill()
  }

  private func drawOutline(_ layout: InlineImageEditingLayout) {
    guard let first = layout.corners.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for corner in layout.corners.dropFirst() {
      path.line(to: corner)
    }
    path.close()
    path.lineWidth = 1
    let dashPattern: [CGFloat] = [4, 3]
    path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
    accentColor.setStroke()
    path.stroke()
  }

  private func drawHandles(_ layout: InlineImageEditingLayout) {
    let size = InlineImageEditingLayout.handleSize
    for handle in InlineImageHandle.allCases {
      guard let center = layout.handleCenters[handle] else { continue }
      let path = NSBezierPath(
        rect: NSRect(
          x: center.x - size / 2,
          y: center.y - size / 2,
          width: size,
          height: size
        )
      )
      NSColor.white.setFill()
      path.fill()
      path.lineWidth = 1
      NSColor.black.setStroke()
      path.stroke()
    }
  }

  private func drawRotationHandle(_ layout: InlineImageEditingLayout) {
    let sides: [InlineImageHandle] = [.top, .right, .bottom, .left]
    let connector = sides.compactMap { layout.handleCenters[$0] }.min { first, second in
      hypot(first.x - layout.rotationHandleCenter.x, first.y - layout.rotationHandleCenter.y)
        < hypot(second.x - layout.rotationHandleCenter.x, second.y - layout.rotationHandleCenter.y)
    }
    if let top = connector {
      let line = NSBezierPath()
      line.move(to: top)
      line.line(to: layout.rotationHandleCenter)
      line.lineWidth = 1
      accentColor.setStroke()
      line.stroke()
    }

    let center = layout.rotationHandleCenter
    let radius = InlineImageEditingLayout.rotationHandleRadius
    let disk = NSBezierPath(
      ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
    )
    NSColor.white.setFill()
    disk.fill()
    disk.lineWidth = 1
    NSColor.black.setStroke()
    disk.stroke()

    guard let glyph = Self.rotationGlyph else { return }
    let glyphSide = InlineImageEditingLayout.rotationGlyphSide
    glyph.draw(
      in: NSRect(
        x: center.x - glyphSide / 2,
        y: center.y - glyphSide / 2,
        width: glyphSide,
        height: glyphSide
      ),
      from: .zero,
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: nil
    )
  }

  private static let rotationGlyph: NSImage? = {
    guard
      let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil),
      let configured = symbol.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
          .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
      )
    else { return nil }
    configured.isTemplate = false
    return configured
  }()

  private var accentColor: NSColor {
    guard let textView else { return .controlAccentColor }
    return FleckColorContrast.accessibleForeground(
      textView.checklistAccentColor,
      against: EditorCanvasInk.canvasColor(for: textView),
      minimumContrast: 3
    )
  }
}

@available(macOS 15.0, *)
private extension InlineImageResizeDirection {
  var frameResizePosition: NSCursor.FrameResizePosition {
    switch self {
    case .right: .right
    case .topRight: .topRight
    case .top: .top
    case .topLeft: .topLeft
    case .left: .left
    case .bottomLeft: .bottomLeft
    case .bottom: .bottom
    case .bottomRight: .bottomRight
    }
  }
}
#endif
