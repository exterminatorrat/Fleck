#if os(macOS)
import SwiftUI

struct FleckPillCanvasLayers: Equatable {
  var rim = true
  var shoulders = true
  var signal = true
  var halo = true
}

struct FleckPillCanvas: View {
  var frame: FleckPillArtworkFrame
  var layers = FleckPillCanvasLayers()
  var colors = FleckRailColors()
  var renderGeneration: UInt64 = 0
  var renderSessionID: UUID?
  var receipt: FleckPillRenderReceipt?


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

  var body: some View {
    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
      FleckPillPainter.draw(frame, layers: layers, colors: colors, in: context)
      receipt?.record(frame, generation: renderGeneration, sessionID: renderSessionID)
    }
    .frame(width: FleckPillGeometry.canvasSize.width, height: FleckPillGeometry.canvasSize.height)
    .accessibilityHidden(true)
  }
}

private enum FleckPillPainter {
  private static let activeBody = [
    (0.0, color(0x17191D)),
    (0.32, color(0x090A0D)),
    (0.75, color(0x111216)),
    (1.0, color(0x000000)),
  ]
  private static let activeRim = [
    (0.0, color(0xFFFFFF, alpha: 0)),
    (0.14, color(0xBCC0C8, alpha: 0.19)),
    (0.23, color(0xFFFFFF, alpha: 0.9)),
    (0.34, color(0xDDDFE5, alpha: 0.44)),
    (0.52, color(0xDDDFE5, alpha: 0.31)),
    (0.66, color(0xDDDFE5, alpha: 0.35)),
    (0.78, color(0xFFFFFF, alpha: 0.77)),
    (0.88, color(0xBCC0C8, alpha: 0.17)),
    (1.0, color(0xFFFFFF, alpha: 0)),
  ]
  private static let idleRim = [
    (0.0, color(0xFFFFFF, alpha: 0)),
    (0.34, color(0xCCCFD7, alpha: 0.35)),
    (0.5, color(0xFFFFFF, alpha: 0.7)),
    (0.64, color(0xCCCFD7, alpha: 0.26)),
    (1.0, color(0xFFFFFF, alpha: 0)),
  ]
  private static let insideRim = [
    (0.0, color(0xAFB3BD, alpha: 0.24)),
    (0.22, color(0xA0A5B0, alpha: 0.14)),
    (0.8, color(0x949BA8, alpha: 0.07)),
    (1.0, color(0x8A919E, alpha: 0)),
  ]
  private static let shoulderLeft = [
    (0.0, color(0xFFFFFF, alpha: 0.82)),
    (0.23, color(0xE0E2E9, alpha: 0.47)),
    (0.6, color(0x9B9FA9, alpha: 0.19)),
    (1.0, color(0x797D87, alpha: 0)),
  ]
  private static let shoulderRight = [
    (0.0, color(0xFFFFFF, alpha: 0.66)),
    (0.24, color(0xE0E2E9, alpha: 0.39)),
    (0.65, color(0x9B9FA9, alpha: 0.15)),
    (1.0, color(0x797D87, alpha: 0)),
  ]
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
    let activeMatrix = viewMatrix(shell: shell.shellTransform, light: shell.lightTransform)
    let shellFill = path(shell.fill).applying(shellMatrix)
    context.drawLayer { body in
      body.opacity = colors.effectiveShellOpacity
      body.fill(
        shellFill,
        with: linear(
          activeBody,
          start: point(0, shell.bodyTop, transform: shellMatrix),
          end: point(0, 40, transform: shellMatrix)
        )
      )
      body.clip(to: shellFill)
      body.drawLayer { active in
        active.opacity = shell.expansion
        drawActiveLight(
          in: active,
          matrix: activeMatrix,
          visible: layers.shoulders
        )
      }
      body.drawLayer { idle in
        idle.opacity = 1 - shell.expansion
        let idlePath = path("M 95 39 C 103 26 119 26 129 39")
        drawBlurred(in: idle, transform: shellMatrix, radius: 1.6, opacity: 0.14) { glow in
          glow.fill(stroked(idlePath, width: 2), with: .color(color(0x9399A5)))
        }
      }
      body.fill(
        shellFill,
        with: linear(
          [(0.0, color(0x000000, alpha: 0)), (1.0, color(0x000000))],
          start: point(0, 36, transform: shellMatrix),
          end: point(0, 40, transform: shellMatrix)
        )
      )
    }
    if layers.rim {
      drawRim(
        in: context,
        shell: shell,
        matrix: shellMatrix,
        expansion: shell.expansion,
        colors: colors
      )
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

  private static func drawActiveLight(
    in context: GraphicsContext,
    matrix: CGAffineTransform,
    visible: Bool
  ) {
    let pool = ellipse(112, 24, 73, 20).applying(matrix)
    fillRadial(
      in: context,
      shape: pool,
      transform: radialMatrix(center: point(112, 20), radiusX: 73, radiusY: 20, angle: 0, outer: matrix),
      stops: [
        (0.0, color(0xAAAEBA, alpha: 0.125)),
        (1.0, color(0xAAAEBA, alpha: 0)),
      ]
    )
    guard visible else { return }
    let shoulderL = path("M 29 39 C 41 36 43.3 24 51 14 C 57.8 5.2 65 4.4 82 3.8")
    let shoulderR = path("M 195 39 C 183 36 180.7 24 173 14 C 166.2 5.2 159 4.4 142 3.8")
    let shoulderPairs = [(shoulderL, shoulderLeft, 53.0, -41.0, 0.82), (shoulderR, shoulderRight, 171.0, 41.0, 0.66)]
    var shoulderPairPath = shoulderL
    shoulderPairPath.addPath(shoulderR)
    drawBlurred(in: context, transform: matrix, radius: 3.2, opacity: 1) { glow in
      fillLinearStroke(
        glow,
        path: shoulderPairPath,
        width: 4.6,
        transform: .identity,
        stops: insideRim,
        start: point(0, 0),
        end: point(0, 40)
      )
    }
    drawBlurred(in: context, transform: matrix, radius: 0.7, opacity: 1) { glow in
      fillLinearStroke(
        glow,
        path: shoulderPairPath,
        width: 1.5,
        transform: .identity,
        stops: insideRim,
        start: point(0, 0),
        end: point(0, 40)
      )
    }
    let blackEdge = path("M 45 23 C 52 9 63 3.2 79 3.4 L 145 3.4 C 161 3.2 172 9 179 23")
    drawBlurred(in: context, transform: matrix, radius: 0.7, opacity: 0.7) { edge in
      edge.fill(stroked(blackEdge, width: 1.4), with: .color(color(0x050506)))
    }
    for (line, stops, centerX, angle, _) in shoulderPairs {
      let centerY = 12.0
      let ellipseShape = ellipse(centerX + (centerX < 100 ? 2 : -2), 13, 27, 26).applying(matrix)
      context.drawLayer { glow in
        glow.opacity = 0.26
        fillRadial(
          in: glow,
          shape: ellipseShape,
          transform: radialMatrix(center: point(centerX, centerY), radiusX: 20, radiusY: 10, angle: angle, outer: matrix),
          stops: stops
        )
      }
      drawBlurred(in: context, transform: matrix, radius: 1.6, opacity: 1) { soft in
        fillRadial(
          in: soft,
          shape: stroked(line, width: 8),
          transform: radialMatrix(center: point(centerX, centerY), radiusX: 20, radiusY: 10, angle: angle, outer: .identity),
          stops: stops
        )
      }
      drawBlurred(in: context, transform: matrix, radius: 0.7, opacity: 1) { near in
        fillRadial(
          in: near,
          shape: stroked(line, width: 3.6),
          transform: radialMatrix(center: point(centerX, centerY), radiusX: 20, radiusY: 10, angle: angle, outer: .identity),
          stops: stops
        )
      }
      let fine = centerX < 100
        ? path("M 46 22 C 51 13 55.5 8.6 63.5 5.9")
        : path("M 178 22 C 173 13 168.5 8.6 160.5 5.9")
      drawBlurred(in: context, transform: matrix, radius: 0.7, opacity: 1) { highlight in
        fillRadial(
          in: highlight,
          shape: stroked(fine, width: centerX < 100 ? 1.2 : 1.15),
          transform: radialMatrix(center: point(centerX, centerY), radiusX: 20, radiusY: 10, angle: angle, outer: .identity),
          stops: stops
        )
      }
    }
  }

  private static func drawRim(
    in context: GraphicsContext,
    shell: FleckPillShellGeometry,
    matrix: CGAffineTransform,
    expansion: Double,
    colors: FleckRailColors
  ) {
    let contour = path(shell.contour)
    for (opacity, stops, width, startX, endX) in [
      (expansion, activeRim, 0.48, 0.0, 224.0),
      (1 - expansion, idleRim, 0.43, 83.0, 141.0),
    ] {
      context.drawLayer { rim in
        rim.opacity = opacity
        drawBlurred(in: rim, transform: matrix, radius: 0.7, opacity: 0.24) { glow in
          fillLinearStroke(
            glow,
            path: contour,
            width: 1.25,
            transform: .identity,
            stops: stops,
            start: point(startX, 0),
            end: point(endX, 0)
          )
        }
        fillLinearStroke(
          rim,
          path: contour,
          width: width,
          transform: matrix,
          stops: stops,
          start: point(startX, 0, transform: matrix),
          end: point(endX, 0, transform: matrix)
        )
      }
    }
    context.stroke(
      contour.applying(matrix),
      with: .color(colors.borderColor),
      lineWidth: expansion > 0.5 ? 0.48 : 0.43
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

#endif
