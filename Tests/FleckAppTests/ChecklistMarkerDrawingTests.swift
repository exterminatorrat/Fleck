#if os(macOS)
  import AppKit
  import Testing

  @testable import FleckApp

  @Test @MainActor func checklistCompletionOverlayUsesQuickNativeTiming() {
    #expect(ChecklistCompletionOverlay.duration == AppMotion.quickDuration)
  }

  @Test @MainActor func markerRectKeepsStableSixteenPointControlSize() {
    let markerRect = ChecklistMarkerDrawing.markerRect(
      around: NSRect(x: 12, y: 8, width: 8, height: 8)
    )

    #expect(markerRect.size == NSSize(width: 16, height: 16))
    #expect(markerRect.maxX == 20)
    #expect(markerRect.midY == 12)
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
#endif
