#if os(macOS)
  import AppKit
  import QuartzCore

  enum ChecklistMarkerDrawing {
    static func checkmarkPath(in rect: CGRect, flipped: Bool) -> CGPath {
      let elbowY = rect.minY + rect.height * (flipped ? 0.66 : 0.34)
      let rightY = rect.minY + rect.height * (flipped ? 0.32 : 0.68)
      let path = CGMutablePath()
      path.move(
        to: CGPoint(
          x: rect.minX + rect.width * 0.27,
          y: rect.minY + rect.height * (flipped ? 0.49 : 0.51)
        )
      )
      path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: elbowY))
      path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rightY))
      return path
    }

    static func drawCompleted(in rect: NSRect, accentColor: NSColor, flipped: Bool) {
      guard let context = NSGraphicsContext.current?.cgContext else { return }
      context.saveGState()
      context.setFillColor(accentColor.cgColor)
      context.fillEllipse(in: rect)
      context.addPath(checkmarkPath(in: rect, flipped: flipped))
      context.setStrokeColor(NSColor.white.cgColor)
      context.setLineWidth(max(1.35, rect.width * 0.11))
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.strokePath()
      context.restoreGState()
    }
  }
#endif
