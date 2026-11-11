import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func imageTransformCommitPreservesSelectionAndRoundTripsUndo() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let editor = fixture.editor
  let original = try #require(editor.textStorage).attributedSubstring(from: fixture.range)
  let originalAttachment = try #require(
    original.attribute(.attachment, at: 0, effectiveRange: nil) as? InlineNoteImageAttachment
  )
  let source = InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string
  let transform = InlineImageTransform(size: CGSize(width: 180, height: 90), rotationDegrees: 30)

  #expect(editor.applyInlineImageTransform(transform: transform, range: fixture.range))
  #expect(editor.selectedRange() == fixture.range)
  let attachment = try fixture.attachment()
  #expect(attachment.displayTransform == transform)
  #expect(attachment !== originalAttachment)
  let changedSource = InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string
  #expect(changedSource != source)
  #expect(changedSource.hasPrefix("Before\n"))
  #expect(changedSource.hasSuffix("\nAfter"))

  editor.undoManager?.undo()
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == source)
  editor.undoManager?.redo()
  #expect(try fixture.attachment().displayTransform == transform)
}

@Test @MainActor func imageTransformRejectsReadOnlyAndStaleRanges() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let transform = InlineImageTransform(size: CGSize(width: 180, height: 90))
  fixture.editor.isEditable = false
  #expect(!fixture.editor.applyInlineImageTransform(transform: transform, range: fixture.range))
  fixture.editor.isEditable = true
  #expect(!fixture.editor.applyInlineImageTransform(
    transform: transform,
    range: NSRange(location: 0, length: 1)
  ))
  #expect(!fixture.editor.applyInlineImageTransform(
    transform: InlineImageTransform(size: .zero),
    range: fixture.range
  ))
  #expect(try fixture.attachment().displayTransform == nil)
}

@Test @MainActor func imageResizePreviewCancelsWithoutChangingCanonicalSource() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  #expect(layout.handleCenters.count == 8)
  let handle = try #require(layout.handleCenters[.bottomRight])
  let source = InlineNoteImageProjection.expanded(try #require(fixture.editor.textStorage)).string

  #expect(controller.begin(with: try fixture.event(.leftMouseDown, point: handle)))
  controller.drag(with: try fixture.event(
    .leftMouseDragged,
    point: NSPoint(x: handle.x + 80, y: handle.y + 40)
  ))
  #expect(controller.isDragging)
  #expect(try #require(controller.currentLayout).transform.size.width > layout.transform.size.width)
  #expect(InlineNoteImageProjection.expanded(try #require(fixture.editor.textStorage)).string == source)
  #expect(controller.cancel())
  #expect(!controller.isDragging)
  #expect(InlineNoteImageProjection.expanded(try #require(fixture.editor.textStorage)).string == source)
}

@Test @MainActor func imageResizeAndRotationCommitThroughPointerHandlers() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let original = try #require(controller.currentLayout)
  let undoManager = try #require(fixture.editor.undoManager)
  try #require(undoManager.groupingLevel == 0)
  let groupsByEvent = undoManager.groupsByEvent
  undoManager.groupsByEvent = false
  defer { undoManager.groupsByEvent = groupsByEvent }
  let right = try #require(original.handleCenters[.right])
  let destination = NSPoint(x: right.x - 40, y: right.y)

  #expect(controller.begin(with: try fixture.event(.leftMouseDown, point: right)))
  controller.drag(with: try fixture.event(.leftMouseDragged, point: destination))
  controller.end(with: try fixture.event(.leftMouseUp, point: destination))
  let resized = try #require(fixture.attachment().displayTransform)
  #expect(abs(resized.size.width - (original.transform.size.width - 40)) < 0.01)
  #expect(abs(resized.size.height - original.transform.size.height) < 0.01)
  #expect(undoManager.groupingLevel == 0)

  let layout = try #require(controller.currentLayout)
  let rotation = layout.rotationHandleCenter
  let radius = hypot(rotation.x - layout.center.x, rotation.y - layout.center.y)
  let rotatedPointer = NSPoint(x: layout.center.x + radius, y: layout.center.y)
  #expect(controller.begin(with: try fixture.event(.leftMouseDown, point: rotation)))
  controller.drag(with: try fixture.event(.leftMouseDragged, point: rotatedPointer, flags: .shift))
  controller.end(with: try fixture.event(.leftMouseUp, point: rotatedPointer, flags: .shift))
  #expect(undoManager.groupingLevel == 0)
  #expect(try fixture.attachment().displayTransform?.rotationDegrees == 90)
  fixture.editor.undoManager?.undo()
  let afterUndo = try fixture.attachment().displayTransform
  #expect(afterUndo == resized)
  undoManager.undo()
  #expect(try fixture.attachment().displayTransform == nil)
  undoManager.redo()
  #expect(try fixture.attachment().displayTransform == resized)
  undoManager.redo()
  #expect(try fixture.attachment().displayTransform?.rotationDegrees == 90)
}

@Test @MainActor func imageEditingRendersSelectionAndRotationEvidence() throws {
  guard let path = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let appearances: [(String, NSAppearance.Name)] = [
    ("light", .aqua), ("dark", .darkAqua),
    ("contrast", .accessibilityHighContrastAqua),
  ]
  for (name, appearanceName) in appearances {
    for width: CGFloat in [360, 600] {
      let fixture = try ImageEditingFixture()
      defer { fixture.close() }
      let appearance = try #require(NSAppearance(named: appearanceName))
      fixture.window.appearance = appearance
      fixture.editor.appearance = appearance
      fixture.window.setContentSize(NSSize(width: width, height: 400))
      fixture.editor.frame.size = NSSize(width: width, height: 400)
      fixture.editor.drawsBackground = true
      fixture.editor.backgroundColor = .textBackgroundColor
      fixture.editor.textColor = .textColor
      let transform = InlineImageTransform(size: CGSize(width: 220, height: 110), rotationDegrees: 30)
      #expect(fixture.editor.applyInlineImageTransform(transform: transform, range: fixture.range))
      let controller = InlineImageEditingController(textView: fixture.editor)
      let layout = try #require(controller.currentLayout)
      #expect(layout.handleCenters.count == 8)
      #expect(layout.bounds.width <= width - 32)
      let bitmap = try #require(fixture.editor.bitmapImageRepForCachingDisplay(in: fixture.editor.bounds))
      appearance.performAsCurrentDrawingAppearance {
        fixture.editor.cacheDisplay(in: fixture.editor.bounds, to: bitmap)
      }
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: directory.appendingPathComponent("image-editing-\(name)-\(Int(width)).png")
      )
    }
  }
}

@Test @MainActor func firstLineImageKeepsRotationHandleInsideTheEditor() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let attachment = try fixture.attachment()
  fixture.editor.textContainerInset = NSSize(width: 16, height: 8)
  fixture.editor.textStorage?.setAttributedString(NSAttributedString(attachment: attachment))
  fixture.editor.setSelectedRange(NSRange(location: 0, length: 1))
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  #expect(fixture.editor.bounds.insetBy(dx: 6, dy: 6).contains(layout.rotationHandleCenter))
  #expect(controller.begin(with: try fixture.event(.leftMouseDown, point: layout.rotationHandleCenter)))
  #expect(controller.isDragging)
  #expect(controller.cancel())
}

@Test @MainActor func imageTransformAccessibilityActionsUseTheSameUndoableCommit() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let names = fixture.editor.accessibilityCustomActions()?.map(\.name) ?? []
  #expect(names.contains("Enlarge image"))
  #expect(names.contains("Rotate image clockwise"))
  #expect(fixture.editor.rotateSelectedImageClockwise())
  #expect(try fixture.attachment().displayTransform?.rotationDegrees == 15)
  fixture.editor.undoManager?.undo()
  #expect(try fixture.attachment().displayTransform == nil)
  #expect(fixture.editor.enlargeSelectedImage())
  #expect(try #require(fixture.attachment().displayTransform).size.width > 240)
}

@Test @MainActor func rotatingViewportFittedImagePreservesItsCanonicalDimensions() throws {
  let fixture = try ImageEditingFixture(width: 300)
  defer { fixture.close() }
  let saved = InlineImageTransform(size: CGSize(width: 600, height: 300))
  #expect(fixture.editor.applyInlineImageTransform(transform: saved, range: fixture.range))
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  #expect(layout.transform.size.width < saved.size.width)
  let handle = layout.rotationHandleCenter
  let vector = NSPoint(x: handle.x - layout.center.x, y: handle.y - layout.center.y)
  let target = NSPoint(x: layout.center.x - vector.y, y: layout.center.y + vector.x)
  #expect(controller.begin(with: try fixture.event(.leftMouseDown, point: handle)))
  controller.end(with: try fixture.event(.leftMouseUp, point: target, flags: .shift))
  #expect(try fixture.attachment().displayTransform?.size == saved.size)
  #expect(try fixture.attachment().displayTransform?.rotationDegrees == 90)
  #expect(fixture.editor.rotateSelectedImageClockwise())
  #expect(fixture.editor.rotateSelectedImageClockwise())
  #expect(try fixture.attachment().displayTransform?.size == saved.size)
  #expect(try fixture.attachment().displayTransform?.rotationDegrees == 120)
}

@Test @MainActor func clickingTinyImageHandleWithoutDraggingMakesNoChange() throws {
  let fixture = try ImageEditingFixture(imageWidth: 16, imageHeight: 16)
  defer { fixture.close() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  let handle = try #require(layout.handleCenters[.bottomRight])
  let original = try fixture.attachment()
  let couldUndo = fixture.editor.undoManager?.canUndo
  #expect(controller.begin(with: try fixture.event(.leftMouseDown, point: handle)))
  controller.end(with: try fixture.event(.leftMouseUp, point: handle))
  #expect(try fixture.attachment() === original)
  #expect(try fixture.attachment().displayTransform == nil)
  #expect(fixture.editor.undoManager?.canUndo == couldUndo)
}

@Test @MainActor func transformedImageCopyPreservesRotatedPixelsAndPrivateReference() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let transform = InlineImageTransform(size: CGSize(width: 200, height: 100), rotationDegrees: 90)
  #expect(fixture.editor.applyInlineImageTransform(transform: transform, range: fixture.range))
  let image = try fixture.attachment()
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  #expect(fixture.editor.copyInlineImage(image, to: pasteboard))
  let data = try #require(pasteboard.data(forType: .png))
  let bitmap = try #require(NSBitmapImageRep(data: data))
  #expect(bitmap.pixelsWide == 200)
  #expect(bitmap.pixelsHigh == 400)
  #expect(pasteboard.data(forType: .rtf) == nil)
  #expect(pasteboard.string(forType: .string) == nil)
  let references = (pasteboard.types ?? []).compactMap { pasteboard.string(forType: $0) }
  #expect(references.contains(image.sourceReference))
}

@Test func imageResizeCursorsFollowTheRotatedHandleGeometry() {
  let upright: [(InlineImageHandle, InlineImageResizeDirection)] = [
    (.topLeft, .topLeft),
    (.top, .top),
    (.topRight, .topRight),
    (.right, .right),
    (.bottomRight, .bottomRight),
    (.bottom, .bottom),
    (.bottomLeft, .bottomLeft),
    (.left, .left),
  ]
  for (handle, direction) in upright {
    #expect(handle.resizeDirection(rotationDegrees: 0) == direction)
  }
  #expect(InlineImageHandle.right.resizeDirection(rotationDegrees: 90) == .bottom)
  #expect(InlineImageHandle.top.resizeDirection(rotationDegrees: 90) == .right)
  #expect(InlineImageHandle.topRight.resizeDirection(rotationDegrees: 90) == .bottomRight)
  #expect(InlineImageHandle.right.resizeDirection(rotationDegrees: 45) == .bottomRight)
  #expect(InlineImageHandle.topRight.resizeDirection(rotationDegrees: 45) == .right)
  #expect(InlineImageHandle.left.resizeDirection(rotationDegrees: 180) == .right)
}

@Test func imageResizeCursorsWrapNormalizedRotations() {
  for handle in InlineImageHandle.allCases {
    let upright = handle.resizeDirection(rotationDegrees: 0)
    #expect(handle.resizeDirection(rotationDegrees: 360) == upright)
    #expect(
      handle.resizeDirection(rotationDegrees: 405)
        == handle.resizeDirection(rotationDegrees: 45)
    )
    #expect(
      handle.resizeDirection(rotationDegrees: -90)
        == handle.resizeDirection(rotationDegrees: 270)
    )
  }
}

@Test func imageEditingCursorRectsStayInsideTheHitTargets() throws {
  let layout = InlineImageTransform(size: CGSize(width: 100, height: 50))
    .layout(centeredAt: CGPoint(x: 200, y: 100))
  let radius = InlineImageEditingLayout.handleCursorRectRadius
  #expect(radius * CGFloat(2).squareRoot() < InlineImageEditingLayout.handleHitRadius)
  for handle in InlineImageHandle.allCases {
    let center = try #require(layout.handleCenters[handle])
    for horizontal: CGFloat in [-radius, radius] {
      for vertical: CGFloat in [-radius, radius] {
        #expect(
          layout.hitTarget(at: CGPoint(x: center.x + horizontal, y: center.y + vertical))
            == .resize(handle)
        )
      }
    }
  }
  let rotation = layout.rotationHandleCenter
  for horizontal: CGFloat in [-radius, radius] {
    for vertical: CGFloat in [-radius, radius] {
      #expect(layout.hitTarget(at: CGPoint(x: rotation.x + horizontal, y: rotation.y + vertical)) == .rotate)
    }
  }
}

@Test func imageEditingRotationControlFitsItsHitTarget() {
  #expect(InlineImageEditingLayout.rotationHandleRadius * 2 == 18)
  #expect(InlineImageEditingLayout.rotationGlyphSide == 12)
  #expect(InlineImageEditingLayout.rotationGlyphSide < InlineImageEditingLayout.rotationHandleRadius * 2)
  #expect(InlineImageEditingLayout.rotationHandleRadius < InlineImageEditingLayout.handleHitRadius)
  #expect(
    InlineImageEditingLayout.rotationHandleRadius * 2
      < InlineImageEditingLayout.rotationHandleOffset
  )
}

@Test @MainActor func imageEditingHoverCursorCoversTheWholeCircularHitTarget() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  let top = try #require(layout.handleCenters[.top])
  let inset = InlineImageEditingLayout.handleCursorRectRadius
  let radius = InlineImageEditingLayout.handleHitRadius
  let expected = controller.cursor(for: .top, rotationDegrees: 0)
  let outward = NSPoint(x: top.x, y: top.y - radius + 0.5)
  let diagonal = NSPoint(x: top.x + 6.5, y: top.y - 8.5)
  #expect(abs(outward.y - top.y) > inset)
  #expect(abs(diagonal.y - top.y) > inset)
  #expect(hypot(diagonal.x - top.x, diagonal.y - top.y) < radius)
  #expect(controller.hoverCursor(at: outward) === expected)
  #expect(controller.hoverCursor(at: diagonal) === expected)
}

@Test @MainActor func imageEditingHoverCursorReappliesAfterTheTextCursorReturns() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let priorCursor = NSCursor.current
  defer { priorCursor.set() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  let top = try #require(layout.handleCenters[.top])
  let resize = controller.cursor(for: .top, rotationDegrees: 0)

  #expect(controller.updateHoverCursor(at: top))
  #expect(NSCursor.current === resize)
  NSCursor.iBeam.set()
  #expect(controller.updateHoverCursor(at: top))
  #expect(NSCursor.current === resize)

  #expect(!controller.updateHoverCursor(at: layout.center))
  #expect(NSCursor.current === NSCursor.iBeam)

  NSCursor.arrow.set()
  controller.clearHoverCursor()
  #expect(NSCursor.current === NSCursor.arrow)
  #expect(controller.hoverCursor(at: top) === resize)
}

@Test @MainActor func imageEditingHoverCursorPreservesACursorItDidNotSet() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let priorCursor = NSCursor.current
  defer { priorCursor.set() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  let top = try #require(layout.handleCenters[.top])
  let resize = controller.cursor(for: .top, rotationDegrees: 0)

  NSCursor.pointingHand.set()
  #expect(!controller.updateHoverCursor(at: layout.center))
  #expect(NSCursor.current === NSCursor.pointingHand)

  #expect(controller.updateHoverCursor(at: top))
  #expect(NSCursor.current === resize)
  NSCursor.pointingHand.set()
  #expect(!controller.updateHoverCursor(at: layout.center))
  #expect(NSCursor.current === NSCursor.pointingHand)
}

@Test @MainActor func imageHandleHoverAndClickOutrankAnOverlappingChecklistMarker() throws {
  let fixture = try ImageEditingFixture(width: 600, imageWidth: 16, imageHeight: 16, checklistPrefix: "○ ")
  defer { fixture.close() }
  let priorCursor = NSCursor.current
  defer { priorCursor.set() }
  let editor = fixture.editor
  let controller = InlineImageEditingController(textView: editor)
  let layout = try #require(controller.currentLayout)
  let markerRect = try #require(editor.checklistHitRect(for: NSRange(location: 0, length: 1)))
  let radius = InlineImageEditingLayout.handleHitRadius
  let overlap = try #require(
    InlineImageHandle.allCases.compactMap { handle -> (InlineImageHandle, NSPoint)? in
      guard let center = layout.handleCenters[handle] else { return nil }
      let hitRect = NSRect(
        x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
      )
      let intersection = hitRect.intersection(markerRect)
      guard !intersection.isEmpty else { return nil }
      let point = NSPoint(x: intersection.midX, y: intersection.midY)
      guard layout.hitTarget(at: point) == .resize(handle) else { return nil }
      return (handle, point)
    }.first
  )
  let (handle, point) = overlap

  NSCursor.arrow.set()
  editor.mouseMoved(with: try fixture.event(.mouseMoved, point: point))
  #expect(
    NSCursor.current
      === controller.cursor(for: handle, rotationDegrees: layout.transform.rotationDegrees)
  )

  let before = InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string
  editor.mouseDown(with: try fixture.event(.leftMouseDown, point: point))
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == before)
  #expect(editor.selectedRange() == fixture.range)
}

@Test @MainActor func imageEditingHoverCursorFollowsTheNearestHandle() throws {
  let fixture = try ImageEditingFixture(imageWidth: 16, imageHeight: 16)
  defer { fixture.close() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  let bottomRight = try #require(layout.handleCenters[.bottomRight])
  let bottomLeft = try #require(layout.handleCenters[.bottomLeft])
  let nearestBottomRight = NSPoint(
    x: bottomRight.x + (bottomLeft.x - bottomRight.x) * 0.2,
    y: bottomRight.y
  )
  #expect(controller.hoverCursor(at: nearestBottomRight) === controller.cursor(
    for: .bottomRight,
    rotationDegrees: 0
  ))
  #expect(controller.hoverCursor(at: layout.rotationHandleCenter) === NSCursor.crosshair)
}

@Test @MainActor func imageEditingHoverCursorFollowsRotationAndBodyFallback() throws {
  let fixture = try ImageEditingFixture()
  defer { fixture.close() }
  let controller = InlineImageEditingController(textView: fixture.editor)
  let layout = try #require(controller.currentLayout)
  #expect(controller.hoverCursor(at: layout.center) == nil)
  #expect(controller.hoverCursor(at: layout.rotationHandleCenter) === NSCursor.crosshair)
  #expect(
    controller.cursor(for: .right, rotationDegrees: 90)
      === controller.cursor(for: .bottom, rotationDegrees: 0)
  )
  #expect(
    controller.cursor(for: .topRight, rotationDegrees: 0)
      !== controller.cursor(for: .topLeft, rotationDegrees: 0)
  )
}

@MainActor
private final class ImageEditingFixture {
  let root: URL
  let editor: ListAwareTextView
  let window: NSWindow
  let range: NSRange

  init(
    width: CGFloat = 600,
    imageWidth: Int = 240,
    imageHeight: Int = 120,
    checklistPrefix: String? = nil
  ) throws {
    range = checklistPrefix.map { NSRange(location: $0.utf16.count, length: 1) }
      ?? NSRange(location: 7, length: 1)
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FleckImageEditing-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("synthetic.png")
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: imageWidth, pixelsHigh: imageHeight,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    for y in 0..<imageHeight {
      for x in 0..<imageWidth {
        let color = x < imageWidth / 2
          ? NSColor(calibratedRed: 0.1, green: 0.35, blue: 0.9, alpha: 1)
          : NSColor(calibratedRed: 1, green: 0.5, blue: 0.1, alpha: 1)
        bitmap.setColor(color, atX: x, y: y)
      }
    }
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: source)
    let store = InlineNoteImageStore(rootURL: root.appendingPathComponent("managed", isDirectory: true))
    let reference = try store.importImage(at: source).reference
    editor = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
    editor.isRichText = true
    editor.isEditable = true
    editor.allowsUndo = true
    editor.inlineImageStore = store
    editor.textContainerInset = NSSize(width: 16, height: 36)
    editor.textStorage?.setAttributedString(store.projectedContent(from: NSAttributedString(
      string: checklistPrefix.map { "\($0)\(reference)" } ?? "Before\n\(reference)\nAfter",
      attributes: [.font: NSFont.systemFont(ofSize: 17)]
    )))
    window = NSWindow(
      contentRect: editor.frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = editor
    editor.layoutManager?.backgroundLayoutEnabled = false
    if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
    editor.setSelectedRange(range)
    editor.undoManager?.removeAllActions()
  }

  func attachment() throws -> InlineNoteImageAttachment {
    try #require(editor.textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil)
      as? InlineNoteImageAttachment)
  }

  func event(
    _ type: NSEvent.EventType,
    point: NSPoint,
    flags: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
      with: type, location: editor.convert(point, to: nil), modifierFlags: flags,
      timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1
    ))
  }

  func close() {
    editor.layoutManager?.delegate = nil
    window.close()
    try? FileManager.default.removeItem(at: root)
  }
}
