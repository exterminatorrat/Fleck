#if os(macOS)
import SwiftUI

struct FleckPillCanvasLayers: Equatable {
  var rim = true
  var shoulders = true
  var signal = true
  var halo = true
}

#if DEBUG
enum FleckPillCanvasBackdrop: CaseIterable, Hashable {
  case clear
  case dark
  case bright

  var color: Color? {
    switch self {
    case .clear:
      nil
    case .dark:
      FleckPillPainter.color(0x07080B)
    case .bright:
      FleckPillPainter.color(0xF6F6F6)
    }
  }
}
#endif

struct FleckPillCanvas: View {
  var frame: FleckPillArtworkFrame
  var layers = FleckPillCanvasLayers()
  var colors = FleckRailColors()
  var renderGeneration: UInt64 = 0
  var renderSessionID: UUID?
  var receipt: FleckPillRenderReceipt?

  #if DEBUG
  var backdrop: FleckPillCanvasBackdrop = .clear
  #endif

  init(
    frame: FleckPillArtworkFrame,
    layers: FleckPillCanvasLayers = FleckPillCanvasLayers(),
    renderGeneration: UInt64 = 0,
    renderSessionID: UUID? = nil,
    receipt: FleckPillRenderReceipt? = nil,
    colors: FleckRailColors = FleckRailColors()
  ) {
    self.frame = frame
    self.layers = layers
    self.renderGeneration = renderGeneration
    self.renderSessionID = renderSessionID
    self.receipt = receipt
    self.colors = colors
  }

  #if DEBUG
  init(
    frame: FleckPillMotionFrame,
    layers: FleckPillCanvasLayers = FleckPillCanvasLayers(),
    backdrop: FleckPillCanvasBackdrop = .clear
  ) {
    self.frame = frame.artworkFrame
    self.layers = layers
    self.renderGeneration = 0
    self.renderSessionID = nil
    self.receipt = nil
    self.backdrop = backdrop
  }

  init(
    frame: FleckPillArtworkFrame,
    layers: FleckPillCanvasLayers = FleckPillCanvasLayers(),
    backdrop: FleckPillCanvasBackdrop
  ) {
    self.frame = frame
    self.layers = layers
    self.renderGeneration = 0
    self.renderSessionID = nil
    self.receipt = nil
    self.backdrop = backdrop
  }

  private var backdropColor: Color? { backdrop.color }
  #else
  private var backdropColor: Color? { nil }
  #endif

  var body: some View {
    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
      if let color = backdropColor {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
      }
      FleckPillPainter.draw(frame, layers: layers, colors: colors, in: context)
      receipt?.record(frame, generation: renderGeneration, sessionID: renderSessionID)
    }
    .frame(width: FleckPillGeometry.canvasSize.width, height: FleckPillGeometry.canvasSize.height)
    .accessibilityHidden(true)
  }
}

struct FleckErrorCanvas: View {
  let presentation: FleckErrorPresentation
  let frame: FleckPillArtworkFrame
  let sourceFrame: FleckPillArtworkFrame?
  let increaseContrast: Bool
  let reduceTransparency: Bool
  let colors: FleckRailColors

  private var layout: FleckErrorLayout { FleckErrorLayout.forKind(presentation.kind) }

  var body: some View {
    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
      let geometry = FleckErrorGeometry.shell(
        dismissal: presentation.dismissal,
        target: presentation.target,
        layout: layout
      )
      let errorOpacity = 1 - presentation.dismissal * presentation.dismissal
      if errorOpacity != 0 {
        context.drawLayer { error in
          error.opacity = errorOpacity
          FleckPillPainter.drawError(
            geometry,
            layout: layout,
            increaseContrast: increaseContrast,
            colors: colors,
            in: error
          )
        }
      }
      let normalFrame = sourceFrame ?? frame
      let normalEndpointOpacity = presentation.dismissal * presentation.dismissal
      if normalEndpointOpacity != 0 {
        var endpoint = context
        endpoint.opacity = normalEndpointOpacity
        endpoint.concatenate(CGAffineTransform(
          translationX: (layout.canvasWidth - DictationCapsuleController.livePillHostSize.width) / 2,
          y: layout.canvasHeight - DictationCapsuleController.livePillHostSize.height
        ))
        FleckPillPainter.draw(
          normalFrame,
          layers: FleckPillCanvasLayers(
            rim: true,
            shoulders: !reduceTransparency,
            signal: true,
            halo: !reduceTransparency && !increaseContrast
          ),
          colors: colors,
          in: endpoint
        )
      }
    }
    .frame(width: layout.canvasWidth, height: layout.canvasHeight)
    .accessibilityHidden(true)
  }
}

struct FleckErrorButtonCanvas: View {
  let feedback: FleckErrorButtonFeedback
  let layout: FleckErrorLayout
  let increaseContrast: Bool
  let reduceMotion: Bool

  var body: some View {
    ZStack {
      FleckErrorButtonStopsCanvas(
        stops: feedback.stops,
        layout: layout,
        increaseContrast: increaseContrast
      )
        .animation(animation(duration: FleckErrorGeometry.buttonFillRimDuration), value: feedback.stops)
      if !increaseContrast {
        FleckErrorButtonReflectionCanvas(opacity: feedback.reflection, layout: layout)
          .animation(
            animation(duration: FleckErrorGeometry.buttonColorReflectionDuration),
            value: feedback.reflection
          )
      }
    }
    .frame(width: layout.buttonFaceWidth, height: layout.buttonFaceHeight)
    .accessibilityHidden(true)
  }

  private func animation(duration: Double) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: duration)
  }
}

private typealias FleckErrorButtonStopPair = AnimatablePair<Double, Double>
private typealias FleckErrorButtonStopQuad = AnimatablePair<FleckErrorButtonStopPair, FleckErrorButtonStopPair>
private typealias FleckErrorButtonStopVector = AnimatablePair<FleckErrorButtonStopQuad, FleckErrorButtonStopPair>

private struct FleckErrorButtonStopsCanvas: View, Animatable {
  var stops: FleckErrorButtonStops
  var layout: FleckErrorLayout
  let increaseContrast: Bool

  nonisolated var animatableData: FleckErrorButtonStopVector {
    get {
      AnimatablePair(
        AnimatablePair(
          AnimatablePair(stops.fill[0], stops.fill[1]),
          AnimatablePair(stops.fill[2], stops.rim[0])
        ),
        AnimatablePair(stops.rim[1], stops.rim[2])
      )
    }
    set {
      stops = FleckErrorButtonStops(
        fill: [newValue.first.first.first, newValue.first.first.second, newValue.first.second.first],
        rim: [newValue.first.second.second, newValue.second.first, newValue.second.second]
      )
    }
  }

  var body: some View {
    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
      FleckPillPainter.drawErrorButtonStops(
        stops,
        layout: layout,
        increaseContrast: increaseContrast,
        in: context
      )
    }
    .frame(width: layout.buttonFaceWidth, height: layout.buttonFaceHeight)
    .accessibilityHidden(true)
  }
}

private struct FleckErrorButtonReflectionCanvas: View, Animatable {
  var opacity: Double
  var layout: FleckErrorLayout

  nonisolated var animatableData: Double {
    get { opacity }
    set { opacity = newValue }
  }

  var body: some View {
    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
      FleckPillPainter.drawErrorButtonReflection(opacity, layout: layout, in: context)
    }
    .frame(width: layout.buttonFaceWidth, height: layout.buttonFaceHeight)
    .accessibilityHidden(true)
  }
}

private enum FleckPillPainter {
  fileprivate static func color(_ rgb: UInt32, alpha: Double = 1) -> Color {
    Color(
      .sRGB,
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255,
      opacity: alpha
    )
  }

  static func draw(
    _ frame: FleckPillArtworkFrame,
    layers: FleckPillCanvasLayers,
    colors: FleckRailColors = FleckRailColors(),
    in context: GraphicsContext
  ) {
    let shell = FleckPillGeometry.shell(expansion: frame.expansion)
    let shellMatrix = viewMatrix(shell: shell.shellTransform)
    let shellFill = path(shell.fill).applying(shellMatrix)
    let shellBounds = shellFill.boundingRect
    let stops = layers.shoulders
      ? [
        Gradient.Stop(color: colors.shellColor, location: 0),
        Gradient.Stop(color: colors.shellColor, location: 0.86),
        Gradient.Stop(color: colors.shellEdgeColor, location: 1),
      ]
      : [Gradient.Stop(color: colors.shellColor, location: 0)]
    context.drawLayer { body in
      body.opacity = colors.effectiveShellOpacity
      body.fill(
        shellFill,
        with: .linearGradient(
          Gradient(stops: stops),
          startPoint: CGPoint(x: shellBounds.midX, y: shellBounds.minY),
          endPoint: CGPoint(x: shellBounds.midX, y: shellBounds.maxY)
        )
      )
      if layers.rim {
        drawRim(
          in: body,
          shell: shell,
          matrix: shellMatrix,
          expansion: shell.expansion,
          colors: colors
        )
      }
    }
    if layers.signal, frame.signalOpacity > 0, shell.expansion > 0 {
      drawSignal(
        frame,
        geometry: FleckPillMotion.signalGeometry(frame),
        in: context,
        clip: path(shell.fill).applying(viewMatrix()),
        matrix: viewMatrix(light: shell.lightTransform),
        haloVisible: layers.halo,
        colors: colors
      )
    }
  }

  static func drawError(
    _ geometry: FleckErrorShellGeometry,
    layout: FleckErrorLayout,
    increaseContrast: Bool,
    colors: FleckRailColors,
    in context: GraphicsContext
  ) {
    let transform = CGAffineTransform(
      a: layout.scale,
      b: 0,
      c: 0,
      d: layout.scale * 0.925,
      tx: layout.artworkPadding,
      ty: layout.scale * 15
    )
    let fill = path(geometry.artworkFill)
    let contour = path(geometry.artworkContour)
    context.drawLayer { body in
      body.opacity = colors.effectiveShellOpacity
      body.fill(fill.applying(transform), with: .color(colors.shellColor))
      body.stroke(
        contour.applying(transform),
        with: .color(colors.shellBorderColor),
        lineWidth: increaseContrast ? 1 : 0.5
      )
      if increaseContrast {
        body.stroke(
          contour.applying(transform),
          with: .color(colors.primaryTextColor),
          lineWidth: 1
        )
      }
    }
  }

  static func drawErrorRepairProgress(
    _ sample: FleckErrorRepairSample,
    increaseContrast: Bool,
    reduceTransparency: Bool,
    colors: FleckRailColors,
    layout: FleckErrorLayout,
    in context: GraphicsContext
  ) {
    let frame = FleckPillArtworkFrame(
      expansion: 1,
      energy: 0,
      phase: 0,
      activationMix: 0,
      processingMix: 1,
      signalOpacity: 1,
      glint: sample.glint,
      glintOpacity: sample.opacity
    )
    let shell = FleckErrorGeometry.shell(layout: layout)
    let shellTransform = CGAffineTransform(
      a: layout.scale,
      b: 0,
      c: 0,
      d: layout.scale * 0.925,
      tx: layout.artworkPadding,
      ty: layout.scale * 15
    )
    drawSignal(
      frame,
      geometry: FleckPillMotion.signalGeometry(frame),
      in: context,
      clip: path(shell.artworkFill).applying(shellTransform),
      matrix: FleckErrorGeometry.repairProgressTransform(layout: layout),
      haloVisible: !reduceTransparency && !increaseContrast,
      colors: colors
    )
  }

  static func drawErrorButtonStops(
    _ stops: FleckErrorButtonStops,
    layout: FleckErrorLayout,
    increaseContrast: Bool,
    in context: GraphicsContext
  ) {
    let width = layout.buttonFaceWidth
    let height = layout.buttonFaceHeight
    let rect = CGRect(x: 0.3, y: 0.3, width: width - 0.6, height: height - 0.6)
    let corner = CGSize(width: rect.height / 2, height: rect.height / 2)
    let face = Path(roundedRect: rect, cornerSize: corner)
    if increaseContrast {
      context.fill(face, with: .color(Color(nsColor: .controlBackgroundColor)))
      context.stroke(face, with: .color(Color(nsColor: .controlTextColor)), lineWidth: 1)
      return
    }
    let fillColors = stops.fill
    context.fill(
      face,
      with: linear(
        [
          (0.0, color(0xFFFFFF, alpha: fillColors[0])),
          (0.48, color(0xFFFFFF, alpha: fillColors[1])),
          (1.0, color(0xD0D0D1, alpha: fillColors[2])),
        ],
        start: point(0, 0),
        end: point(0, height)
      )
    )
    let rimColors = stops.rim
    context.stroke(
      face,
      with: linear(
        [
          (0.0, color(0xE3E3E4, alpha: rimColors[0])),
          (0.48, color(0x8E8E90, alpha: rimColors[1])),
          (1.0, color(0xD1D1D3, alpha: rimColors[2])),
        ],
        start: point(width * 0.15, 0),
        end: point(width * 0.72, height)
      ),
      lineWidth: 0.5
    )
  }

  static func drawErrorButtonReflection(
    _ opacity: Double,
    layout: FleckErrorLayout,
    in context: GraphicsContext
  ) {
    let width = layout.buttonFaceWidth
    let height = layout.buttonFaceHeight
    let rect = CGRect(x: 0.8, y: 0.8, width: width - 1.6, height: height - 1.6)
    let corner = CGSize(width: rect.height / 2, height: rect.height / 2)
    let reflection = Path(roundedRect: rect, cornerSize: corner)
    let scaleX = width / FleckErrorLayout.buttonFaceArtworkWidth
    let scaleY = height / FleckErrorLayout.buttonFaceArtworkHeight
    context.drawLayer { glass in
      glass.opacity = opacity
      fillRadial(
        in: glass,
        shape: reflection,
        transform: radialMatrix(
          center: point(20 * scaleX, 0.7 * scaleY),
          radiusX: 38 * scaleX,
          radiusY: 14 * scaleY,
          angle: 0,
          outer: .identity
        ),
        stops: [
          (0.0, color(0xFFFFFF)),
          (0.5, color(0xFFFFFF, alpha: 0.38)),
          (1.0, color(0xFFFFFF, alpha: 0)),
        ]
      )
    }
  }

  private static func drawRim(
    in context: GraphicsContext,
    shell: FleckPillShellGeometry,
    matrix: CGAffineTransform,
    expansion: Double,
    colors: FleckRailColors
  ) {
    context.stroke(
      path(shell.contour).applying(matrix),
      with: .color(colors.shellBorderColor),
      lineWidth: colors.increasedContrast ? 1 : (expansion > 0.5 ? 0.55 : 0.5)
    )
  }

  private static func drawSignal(
    _ frame: FleckPillArtworkFrame,
    geometry: FleckPillSignalGeometry,
    in context: GraphicsContext,
    clip: Path,
    matrix: CGAffineTransform,
    haloVisible: Bool,
    colors: FleckRailColors
  ) {
    let signalColor = colors.liveColor
    let coreLight = [
      (0.0, signalColor.opacity(0)),
      (0.08, signalColor.opacity(0.4)),
      (0.27, signalColor.opacity(0.93)),
      (0.5, signalColor),
      (0.73, signalColor.opacity(0.93)),
      (0.92, signalColor.opacity(0.4)),
      (1.0, signalColor.opacity(0)),
    ]
    let lineLight = [
      (0.0, signalColor.opacity(0.4)),
      (0.12, signalColor.opacity(0.64)),
      (0.88, signalColor.opacity(0.64)),
      (1.0, signalColor.opacity(0.4)),
    ]
    let glintLight = [
      (0.0, signalColor),
      (0.17, signalColor.opacity(0.95)),
      (0.45, signalColor.opacity(0.36)),
      (1.0, signalColor.opacity(0)),
    ]
    context.drawLayer { signal in
      signal.opacity = frame.signalOpacity
      signal.clip(to: clip)
      if geometry.waveOpacity > 0 {
        signal.drawLayer { wave in
          wave.opacity = geometry.waveOpacity
          let core = path(geometry.core)
          if haloVisible {
            let scatter = path(geometry.scatter).applying(CGAffineTransform(translationX: 0, y: 0.8))
            drawBlurred(in: wave, transform: matrix, radius: 3.8, opacity: 0.34) { glow in
              glow.fill(
                scatter,
                with: linear(coreLight, start: point(56, 25), end: point(168, 25))
              )
            }
            drawBlurred(in: wave, transform: matrix, radius: 2.8, opacity: 0.68) { glow in
              glow.fill(
                core,
                with: linear(coreLight, start: point(56, 25), end: point(168, 25))
              )
            }
            drawBlurred(in: wave, transform: matrix, radius: 0.7, opacity: 0.75) { glow in
              glow.fill(
                core,
                with: linear(coreLight, start: point(56, 25), end: point(168, 25))
              )
            }
          }
          wave.fill(
            core.applying(matrix),
            with: linear(
              coreLight,
              start: point(56, 25, transform: matrix),
              end: point(168, 25, transform: matrix)
            )
          )
        }
      }
      if geometry.lineOpacity > 0 {
        signal.drawLayer { line in
          line.opacity = geometry.lineOpacity
          let stroke = path(geometry.line)
          if haloVisible {
            drawBlurred(in: line, transform: matrix, radius: 2.8, opacity: 0.19) { glow in
              glow.fill(
                stroked(stroke, width: 0.9, lineCap: .butt),
                with: .color(signalColor)
              )
            }
          }
          fillLinearStroke(
            line,
            path: stroke,
            width: 0.72,
            transform: matrix,
            lineCap: .round,
            stops: lineLight,
            start: point(76, 0, transform: matrix),
            end: point(148, 0, transform: matrix)
          )
          line.drawLayer { glint in
            glint.opacity = frame.glintOpacity
            let x = 76 + 72 * frame.glint
            let gradientMatrix = radialMatrix(center: point(x, 26.4), radiusX: 7, radiusY: 2.4, angle: 0, outer: matrix)
            if haloVisible {
              drawBlurred(in: glint, transform: matrix, radius: 2, opacity: 0.8) { bloom in
                fillRadial(
                  in: bloom,
                  shape: ellipse(x, 26.4, 14, 3),
                  transform: radialMatrix(center: point(x, 26.4), radiusX: 7, radiusY: 2.4, angle: 0, outer: .identity),
                  stops: glintLight
                )
              }
            }
            glint.drawLayer { core in
              core.opacity = 0.84
              fillRadial(
                in: core,
                shape: ellipse(x, 26.4, 13, 2.1).applying(matrix),
                transform: gradientMatrix,
                stops: glintLight
              )
            }
            fillRadialStroke(
              glint,
              path: stroke,
              width: 0.9,
              transform: matrix,
              gradientTransform: gradientMatrix,
              stops: glintLight
            )
          }
        }
      }
    }
  }

  private static func linear(
    _ stops: [(Double, Color)],
    start: CGPoint,
    end: CGPoint
  ) -> GraphicsContext.Shading {
    .linearGradient(Gradient(stops: stops.map { .init(color: $0.1, location: $0.0) }), startPoint: start, endPoint: end)
  }

  private static func fillLinearStroke(
    _ context: GraphicsContext,
    path: Path,
    width: Double,
    transform: CGAffineTransform,
    lineCap: CGLineCap = .butt,
    stops: [(Double, Color)],
    start: CGPoint,
    end: CGPoint
  ) {
    context.fill(
      stroked(path, width: width, lineCap: lineCap).applying(transform),
      with: linear(stops, start: start, end: end)
    )
  }

  private static func fillRadialStroke(
    _ context: GraphicsContext,
    path: Path,
    width: Double,
    transform: CGAffineTransform,
    gradientTransform: CGAffineTransform,
    stops: [(Double, Color)]
  ) {
    fillRadial(
      in: context,
      shape: stroked(path, width: width, lineCap: .round).applying(transform),
      transform: gradientTransform,
      stops: stops
    )
  }

  private static func fillRadial(
    in context: GraphicsContext,
    shape: Path,
    transform: CGAffineTransform,
    stops: [(Double, Color)]
  ) {
    guard abs(transform.a * transform.d - transform.b * transform.c) > 0.000001 else { return }
    var gradient = context
    gradient.concatenate(transform)
    gradient.fill(
      shape.applying(transform.inverted()),
      with: .radialGradient(
        Gradient(stops: stops.map { .init(color: $0.1, location: $0.0) }),
        center: .zero,
        startRadius: 0,
        endRadius: 1
      )
    )
  }

  private static func drawBlurred(
    in context: GraphicsContext,
    transform: CGAffineTransform,
    radius: Double,
    opacity: Double,
    draw: (GraphicsContext) -> Void
  ) {
    var transformed = context
    transformed.concatenate(transform)
    transformed.drawLayer { layer in
      layer.opacity = opacity
      layer.addFilter(.blur(radius: radius))
      draw(layer)
    }
  }

  private static func stroked(
    _ path: Path,
    width: Double,
    lineCap: CGLineCap = .butt
  ) -> Path {
    path.strokedPath(StrokeStyle(
      lineWidth: width,
      lineCap: lineCap == .round ? .round : .butt,
      lineJoin: .miter
    ))
  }

  private static func path(_ vector: FleckPillVectorPath) -> Path {
    var result = Path()
    for command in vector.commands {
      switch command {
      case .move(let point):
        result.move(to: cgPoint(point))
      case .line(let point):
        result.addLine(to: cgPoint(point))
      case .cubic(let first, let second, let end):
        result.addCurve(to: cgPoint(end), control1: cgPoint(first), control2: cgPoint(second))
      case .close:
        result.closeSubpath()
      }
    }
    return result
  }

  private static func path(_ data: String) -> Path {
    var tokens = data.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    var result = Path()
    while !tokens.isEmpty {
      let command = tokens.removeFirst()
      switch command {
      case "M":
        result.move(to: CGPoint(x: number(tokens.removeFirst()), y: number(tokens.removeFirst())))
      case "L":
        result.addLine(to: CGPoint(x: number(tokens.removeFirst()), y: number(tokens.removeFirst())))
      case "C":
        let first = CGPoint(x: number(tokens.removeFirst()), y: number(tokens.removeFirst()))
        let second = CGPoint(x: number(tokens.removeFirst()), y: number(tokens.removeFirst()))
        let end = CGPoint(x: number(tokens.removeFirst()), y: number(tokens.removeFirst()))
        result.addCurve(to: end, control1: first, control2: second)
      case "Z":
        result.closeSubpath()
      default:
        return result
      }
    }
    return result
  }

  private static func ellipse(_ x: Double, _ y: Double, _ radiusX: Double, _ radiusY: Double) -> Path {
    Path(ellipseIn: CGRect(
      x: x - radiusX,
      y: y - radiusY,
      width: radiusX * 2,
      height: radiusY * 2
    ))
  }

  private static func radialMatrix(
    center: CGPoint,
    radiusX: Double,
    radiusY: Double,
    angle: Double,
    outer: CGAffineTransform
  ) -> CGAffineTransform {
    let radians = angle * Double.pi / 180
    let cosine = cos(radians)
    let sine = sin(radians)
    return CGAffineTransform(
      a: outer.a * radiusX * cosine,
      b: outer.d * radiusX * sine,
      c: outer.a * -radiusY * sine,
      d: outer.d * radiusY * cosine,
      tx: outer.a * center.x + outer.tx,
      ty: outer.d * center.y + outer.ty
    )
  }

  private static func viewMatrix(
    shell: FleckPillTransform = FleckPillTransform(translateX: 0, translateY: 0, scaleX: 1, scaleY: 1),
    light: FleckPillTransform? = nil
  ) -> CGAffineTransform {
    let inner = light ?? FleckPillTransform(translateX: 0, translateY: 0, scaleX: 1, scaleY: 1)
    let scale = FleckPillGeometry.artworkScale
    return CGAffineTransform(
      a: scale * shell.scaleX * inner.scaleX,
      b: 0,
      c: 0,
      d: scale * shell.scaleY * inner.scaleY,
      tx: scale * (8 + shell.translateX + shell.scaleX * inner.translateX),
      ty: scale * (12 + shell.translateY + shell.scaleY * inner.translateY)
    )
  }

  private static func transformOffset(
    matrix: CGAffineTransform,
    x: Double,
    y: Double
  ) -> FleckPillTransform {
    FleckPillTransform(
      translateX: matrix.tx / FleckPillGeometry.artworkScale - 8 + x,
      translateY: matrix.ty / FleckPillGeometry.artworkScale - 12
        + matrix.d / FleckPillGeometry.artworkScale * y,
      scaleX: matrix.a / FleckPillGeometry.artworkScale,
      scaleY: matrix.d / FleckPillGeometry.artworkScale
    )
  }

  private static func point(_ x: Double, _ y: Double, transform: CGAffineTransform = .identity) -> CGPoint {
    CGPoint(
      x: transform.a * x + transform.c * y + transform.tx,
      y: transform.b * x + transform.d * y + transform.ty
    )
  }

  private static func cgPoint(_ point: FleckPillPoint) -> CGPoint {
    CGPoint(
      x: number(FleckPillVectorPath.number(point.x)),
      y: number(FleckPillVectorPath.number(point.y))
    )
  }

  private static func number(_ value: String) -> CGFloat {
    CGFloat(Double(value) ?? 0)
  }
}

func drawFleckErrorRepairProgress(
  _ sample: FleckErrorRepairSample,
  increaseContrast: Bool,
  reduceTransparency: Bool,
  colors: FleckRailColors,
  layout: FleckErrorLayout,
  in context: GraphicsContext
) {
  FleckPillPainter.drawErrorRepairProgress(
    sample,
    increaseContrast: increaseContrast,
    reduceTransparency: reduceTransparency,
    colors: colors,
    layout: layout,
    in: context
  )
}
#endif
