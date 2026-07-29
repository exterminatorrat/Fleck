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

  final class ChecklistCompletionOverlay: NSView {
    static let duration = AppMotion.quickDuration
    private let accentColor: NSColor
    private let checkLayer = CAShapeLayer()

    init(frame: NSRect, accentColor: NSColor) {
      self.accentColor = accentColor
      super.init(frame: frame)
      wantsLayer = true
      layer?.backgroundColor = accentColor.cgColor
      layer?.cornerRadius = frame.width / 2
      layer?.masksToBounds = true
      setAccessibilityElement(false)

      checkLayer.frame = bounds
      checkLayer.path = ChecklistMarkerDrawing.checkmarkPath(in: bounds, flipped: false)
      checkLayer.fillColor = NSColor.clear.cgColor
      checkLayer.strokeColor = NSColor.white.cgColor
      checkLayer.lineWidth = max(1.35, bounds.width * 0.11)
      checkLayer.lineCap = .round
      checkLayer.lineJoin = .round
      checkLayer.strokeEnd = 1
      layer?.addSublayer(checkLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start(completion: @escaping () -> Void) {
      let animation = CABasicAnimation(keyPath: "strokeEnd")
      animation.fromValue = 0
      animation.toValue = 1
      animation.duration = Self.duration
      animation.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.23, 1.0, 0.32, 1.0
      )

      CATransaction.begin()
      CATransaction.setCompletionBlock(completion)
      checkLayer.add(animation, forKey: "checkmark")
      CATransaction.commit()
    }
  }
#endif
