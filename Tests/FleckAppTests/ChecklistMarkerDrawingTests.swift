#if os(macOS)
  import AppKit
  import Testing

  @testable import FleckApp

  @Test @MainActor func checklistCompletionOverlayUsesQuickNativeTiming() {
    #expect(ChecklistCompletionOverlay.duration == AppMotion.quickDuration)
  }

  @Test @MainActor func markerRectCentersWideSlotsAndClampsNarrowSlots() {
    let wideSlot = NSRect(x: 12, y: 8, width: 24, height: 8)
    let centered = ChecklistMarkerDrawing.markerRect(around: wideSlot)

    #expect(centered.size == NSSize(width: 16, height: 16))
    #expect(centered.minX == 16)
    #expect(centered.midX == wideSlot.midX)
    #expect(centered.maxX == wideSlot.maxX - ChecklistMarkerDrawing.minimumContentGap)
    #expect(centered.midY == wideSlot.midY)

    let narrowSlot = NSRect(x: 12, y: 8, width: 8, height: 8)
    let clamped = ChecklistMarkerDrawing.markerRect(around: narrowSlot)
    let hitRect = ChecklistMarkerDrawing.hitRect(around: clamped)

    #expect(clamped.size == NSSize(width: 16, height: 16))
    #expect(clamped.maxX == narrowSlot.maxX - ChecklistMarkerDrawing.minimumContentGap)
    #expect(clamped.midY == narrowSlot.midY)
    #expect(hitRect.contains(clamped))
    #expect(hitRect.width >= 28)
    #expect(hitRect.height >= 28)
    #expect(hitRect.maxX == clamped.maxX)
  }

  @Test @MainActor func completedChecklistMarkerContainsAccentFillAndWhiteCheck() throws {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    ChecklistMarkerDrawing.drawCompleted(
      in: NSRect(x: 3, y: 3, width: 18, height: 18),
      accentColor: NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.92, alpha: 1),
      flipped: false
    )
    image.unlockFocus()

    let representation = try #require(
      image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    )
    var accentPixels = 0
    var whitePixels = 0
    for y in 0..<representation.pixelsHigh {
      for x in 0..<representation.pixelsWide {
        guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
          continue
        }
        if color.blueComponent > 0.70, color.redComponent < 0.40 {
          accentPixels += 1
        }
        if color.redComponent > 0.90,
          color.greenComponent > 0.90,
          color.blueComponent > 0.90,
          color.alphaComponent > 0.50
        {
          whitePixels += 1
        }
      }
    }

    #expect(accentPixels > 80)
    #expect(whitePixels > 3)
  }

  @Test @MainActor func emptyChecklistOpacityMultipliesTheWholeControl() throws {
    #expect(ChecklistMarkerDrawing.emptyListMarkerOpacity == 0.45)

    func render(opacity: CGFloat) throws -> NSBitmapImageRep {
      let representation = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: 24,
          pixelsHigh: 24,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bitmapFormat: [.alphaFirst],
          bytesPerRow: 0,
          bitsPerPixel: 0
        )
      )
      let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
      context.cgContext.clear(CGRect(x: 0, y: 0, width: 24, height: 24))
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      ChecklistMarkerDrawing.drawCompleted(
        in: NSRect(x: 3, y: 3, width: 18, height: 18),
        accentColor: NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.92, alpha: 1),
        flipped: false,
        opacity: opacity
      )
      context.flushGraphics()
      NSGraphicsContext.restoreGraphicsState()
      return representation
    }

    let full = try render(opacity: 1)
    let dimmed = try render(opacity: ChecklistMarkerDrawing.emptyListMarkerOpacity)
    let fullFill = try #require(full.colorAt(x: 12, y: 5)?.usingColorSpace(.sRGB))
    let dimmedFill = try #require(dimmed.colorAt(x: 12, y: 5)?.usingColorSpace(.sRGB))

    #expect(fullFill.alphaComponent > 0.95)
    #expect(dimmedFill.alphaComponent > 0)
    #expect(
      abs(
        dimmedFill.alphaComponent
          - fullFill.alphaComponent * ChecklistMarkerDrawing.emptyListMarkerOpacity
      ) < 0.02
    )
  }
#endif
