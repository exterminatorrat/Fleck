#if os(macOS)
import AppKit
import Foundation

enum FleckPillPose: String, CaseIterable, Sendable {
  case standby
  case activating
  case listening
  case processing
}

struct FleckPillPoint: Equatable, Sendable {
  var x: Double
  var y: Double
}

enum FleckPillPathCommand: Equatable, Sendable {
  case move(FleckPillPoint)
  case line(FleckPillPoint)
  case cubic(FleckPillPoint, FleckPillPoint, FleckPillPoint)
  case close
}

struct FleckPillVectorPath: Equatable, Sendable {
  var commands: [FleckPillPathCommand]

  var data: String {
    commands.map { command in
      switch command {
      case .move(let point):
        "M \(Self.number(point.x)) \(Self.number(point.y))"
      case .line(let point):
        "L \(Self.number(point.x)) \(Self.number(point.y))"
      case .cubic(let first, let second, let end):
        "C \(Self.number(first.x)) \(Self.number(first.y)) "
          + "\(Self.number(second.x)) \(Self.number(second.y)) "
          + "\(Self.number(end.x)) \(Self.number(end.y))"
      case .close:
        "Z"
      }
    }
    .joined(separator: " ")
  }

  func appending(_ other: Self) -> Self {
    Self(commands: commands + other.commands)
  }

  static func number(_ value: Double) -> String {
    let rounded = (value * 10_000).rounded(.toNearestOrAwayFromZero) / 10_000
    var result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    while result.last == "0" { result.removeLast() }
    if result.last == "." { result.removeLast() }
    return result == "-0" ? "0" : result
  }
}

struct FleckPillTransform: Equatable, Sendable {
  var translateX: Double
  var translateY: Double
  var scaleX: Double
  var scaleY: Double

  func applying(to point: FleckPillPoint) -> FleckPillPoint {
    FleckPillPoint(
      x: translateX + scaleX * point.x,
      y: translateY + scaleY * point.y
    )
  }

  var data: String {
    "translate(\(FleckPillVectorPath.number(translateX)) \(FleckPillVectorPath.number(translateY))) "
      + "scale(\(FleckPillVectorPath.number(scaleX)) \(FleckPillVectorPath.number(scaleY)))"
  }
}

struct FleckPillShellGeometry: Equatable, Sendable {
  var expansion: Double
  var contour: FleckPillVectorPath
  var fill: FleckPillVectorPath
  var shellTransform: FleckPillTransform
  var lightTransform: FleckPillTransform
  var bodyTop: Double
  var width: Double
  var height: Double
  var scaleY: Double
  var translateY: Double
}

enum FleckPillGeometryError: Error, Equatable {
  case curveNeedsTwoPoints
  case unknownPose(String)
}

enum FleckPillGeometry {
  static let artworkScale = 0.75
  static let canvasSize = (width: 180.0, height: 39.0)
  static let baseline = 40.0

  private static let standbyCoordinates: [Double] = [
    83, 40, 94.5, 40, 96.5, 36.5, 101.5, 32.5,
    105.1, 29.2, 107.7, 28, 112, 28, 112, 28,
    116.3, 28, 118.9, 29.2, 122.5, 32.5,
    127.5, 36.5, 129.5, 40, 141, 40,
  ]

  private static let activeCoordinates: [Double] = [
    0, 40, 24, 40, 33, 37.2, 42, 21.5,
    50, 7, 55.5, 0, 77, 0, 147, 0,
    168.5, 0, 174, 7, 182, 21.5,
    191, 37.2, 200, 40, 224, 40,
  ]

  static func finite(_ value: Double, fallback: Double = 0) -> Double {
    value.isFinite ? value : fallback
  }

  static func clamp(_ value: Double, lower: Double = 0, upper: Double = 1) -> Double {
    min(upper, max(lower, finite(value)))
  }

  static func mix(_ first: Double, _ second: Double, _ progress: Double) -> Double {
    if progress == 0 { return first }
    if progress == 1 { return second }
    return first + (second - first) * progress
  }

  static func rounded4(_ value: Double) -> Double {
    (value * 10_000).rounded(.toNearestOrAwayFromZero) / 10_000
  }

  static func smooth(_ value: Double) -> Double {
    let x = clamp(value)
    return x * x * x * (x * (x * 6 - 15) + 10)
  }

  static func shell(expansion: Double) -> FleckPillShellGeometry {
    let q = clamp(expansion)
    let coordinates = zip(standbyCoordinates, activeCoordinates).map { first, second in
      (q == 0 ? first : (q == 1 ? second : mix(first, second, q)))
    }
    var index = 0
    func point() -> FleckPillPoint {
      defer { index += 2 }
      return FleckPillPoint(x: coordinates[index], y: coordinates[index + 1])
    }
    let contour = FleckPillVectorPath(commands: [
      .move(point()),
      .cubic(point(), point(), point()),
      .cubic(point(), point(), point()),
      .line(point()),
      .cubic(point(), point(), point()),
      .cubic(point(), point(), point()),
    ])
    let left = mix(83, 0, q)
    let right = mix(141, 224, q)
    let fill = contour.appending(FleckPillVectorPath(commands: [
      .line(FleckPillPoint(x: right, y: 41)),
      .line(FleckPillPoint(x: left, y: 41)),
      .close,
    ]))
    let scaleY = 1 - 0.075 * q
    let translateY = 3 * q
    let activeLightScaleX = mix(58 / 224, 1, q)
    let activeLightScaleY = mix(0.3, 1, q)
    return FleckPillShellGeometry(
      expansion: q,
      contour: contour,
      fill: fill,
      shellTransform: FleckPillTransform(
        translateX: 0,
        translateY: rounded4(translateY),
        scaleX: 1,
        scaleY: rounded4(scaleY)
      ),
      lightTransform: FleckPillTransform(
        translateX: rounded4(112 * (1 - activeLightScaleX)),
        translateY: rounded4(40 * (1 - activeLightScaleY)),
        scaleX: rounded4(activeLightScaleX),
        scaleY: rounded4(activeLightScaleY)
      ),
      bodyTop: mix(28, 0, q),
      width: mix(43.5, 168, q),
      height: 0.75 * (40 - (translateY + scaleY * mix(28, 0, q))),
      scaleY: scaleY,
      translateY: translateY
    )
  }

  static func waveSamples(
    energy: Double = 1,
    phase: Double = 0,
    pose: FleckPillPose = .listening
  ) -> [FleckPillPoint] {
    let e = clamp(finite(energy))
    let p = finite(phase)
    return (0...160).map { index in
      let u = Double(index) / 160
      let v = 2 * u - 1
      var y = 26.4
      if index != 0 && index != 160 && e > 0 {
        let envelope = exp(-2.55 * v * v) * pow(max(0, 1 - v * v), 1.65)
        let angle = Double.pi * 2 * (2.15 * v + 1.75 * v * v * v) + p
        let carrierValue = cos(angle)
        let baseCarrier = 0.75 * carrierValue + 0.25 * carrierValue * carrierValue
        let carrier = baseCarrier > 0.5
          ? baseCarrier + 2 * pow(baseCarrier - 0.5, 2) * (1 - baseCarrier)
          : baseCarrier
        let value = pose == .activating
          ? exp(-19 * v * v) * cos(2.9 * Double.pi * v)
          : envelope * carrier
        y -= 16.4 * e * value
      }
      return FleckPillPoint(x: 56 + 112 * u, y: y)
    }
  }

  static func curve(
    _ points: [FleckPillPoint],
    move: Bool = true
  ) throws -> FleckPillVectorPath {
    guard points.count >= 2 else { throw FleckPillGeometryError.curveNeedsTwoPoints }
    return curveUnchecked(points, move: move)
  }

  static func ribbon(
    _ points: [FleckPillPoint],
    width: Double = 1.05
  ) throws -> FleckPillVectorPath {
    guard points.count >= 2 else { throw FleckPillGeometryError.curveNeedsTwoPoints }
    return ribbonUnchecked(points, width: width)
  }

  #if DEBUG
  static func pose(named name: String) throws -> FleckPillMotionFrame {
    guard let pose = FleckPillPose(rawValue: name) else {
      throw FleckPillGeometryError.unknownPose(name)
    }
    return FleckPillMotion.sample(FleckPillMotion.anchors[pose]!)
  }
  #endif

  static func curveUnchecked(
    _ points: [FleckPillPoint],
    move: Bool = true
  ) -> FleckPillVectorPath {
    var commands: [FleckPillPathCommand] = move ? [.move(points[0])] : []
    for index in 0..<(points.count - 1) {
      let before = points[max(0, index - 1)]
      let start = points[index]
      let end = points[index + 1]
      let after = points[min(points.count - 1, index + 2)]
      commands.append(.cubic(
        FleckPillPoint(
          x: start.x + (end.x - before.x) / 6,
          y: start.y + (end.y - before.y) / 6
        ),
        FleckPillPoint(
          x: end.x - (after.x - start.x) / 6,
          y: end.y - (after.y - start.y) / 6
        ),
        end
      ))
    }
    return FleckPillVectorPath(commands: commands)
  }

  static func ribbonUnchecked(
    _ points: [FleckPillPoint],
    width: Double
  ) -> FleckPillVectorPath {
    var top: [FleckPillPoint] = []
    var bottom: [FleckPillPoint] = []
    for index in points.indices {
      let point = points[index]
      let before = points[max(0, index - 1)]
      let after = points[min(points.count - 1, index + 1)]
      let dx = after.x - before.x
      let dy = after.y - before.y
      let length = hypot(dx, dy)
      let divisor = length == 0 ? 1 : length
      let u = Double(index) / Double(points.count - 1)
      let taper = pow(sin(Double.pi * u), 1.7)
      let half = (0.045 + width * taper) * 0.5
      top.append(FleckPillPoint(
        x: point.x + dy / divisor * half,
        y: point.y - dx / divisor * half
      ))
      bottom.append(FleckPillPoint(
        x: point.x - dy / divisor * half,
        y: point.y + dx / divisor * half
      ))
    }
    let reversedBottom = Array(bottom.reversed())
    var commands = curveUnchecked(top).commands
    commands.append(.line(reversedBottom[0]))
    commands += curveUnchecked(reversedBottom, move: false).commands
    commands.append(.close)
    return FleckPillVectorPath(commands: commands)
  }
}

enum FleckErrorShellTarget: String, CaseIterable, Sendable {
  case standby
  case activating

  var expansion: Double { self == .standby ? 0 : 1 }
  var width: Double { self == .standby ? 43.5 : 168 }
  var height: Double { self == .standby ? 9 : 27.75 }
}

struct FleckErrorLayout: Equatable, Sendable {
  let canvasWidth: Double
  let canvasHeight: Double
  let visibleWidth: Double
  let visibleHeight: Double
  let baseline: Double
  let scale: Double
  let artworkWidth: Double
  let centerExtension: Double
  let artworkPadding: Double
  let messageCenterX: Double
  let contentCenterY: Double
  let buttonX: Double
  let buttonY: Double
  let buttonWidth: Double
  let buttonHeight: Double
  let buttonFaceX: Double
  let buttonFaceY: Double
  let buttonFaceWidth: Double
  let buttonFaceHeight: Double

  var messageTextCenterY: Double {
    contentCenterY
  }

  var actionLabelCenterY: Double {
    buttonFaceHeight / 2
  }

  static let approved = Self()

  private init() {
    let scale = 44.0 / 37
    let baseline = 52 * scale
    let artworkWidth = 384 / scale
    let buttonWidth = 72.0
    let buttonHeight = 28.0
    canvasWidth = 384 + 16 * scale
    canvasHeight = baseline
    visibleWidth = 384
    visibleHeight = 44
    self.baseline = baseline
    self.scale = scale
    self.artworkWidth = artworkWidth
    centerExtension = artworkWidth - 224
    artworkPadding = 8 * scale
    messageCenterX = artworkPadding + 142
    contentCenterY = baseline - 19
    buttonX = artworkPadding + 258 - buttonWidth / 2
    buttonY = contentCenterY - buttonHeight / 2
    self.buttonWidth = buttonWidth
    self.buttonHeight = buttonHeight
    buttonFaceX = 4
    buttonFaceY = 3
    buttonFaceWidth = 64
    buttonFaceHeight = 22
  }
}

struct FleckErrorShellGeometry: Equatable, Sendable {
  let contour: FleckPillVectorPath
  let fill: FleckPillVectorPath
  let artworkContour: FleckPillVectorPath
  let artworkFill: FleckPillVectorPath
  let width: Double
  let height: Double
  let baseline: Double
  let dismissal: Double
  let target: FleckErrorShellTarget
}

enum FleckErrorButtonPhase: String, CaseIterable, Sendable {
  case `default`
  case hover
  case focus
  case pressed
  case pending
  case copied
  case copyFailed
}

enum FleckErrorButtonInteraction: String, CaseIterable, Sendable {
  case idle
  case hover
  case focus
  case pressed
}

struct FleckErrorButtonStops: Equatable, Sendable {
  let fill: [Double]
  let rim: [Double]

  func interpolated(to other: Self, progress: Double) -> Self {
    let progress = min(max(progress, 0), 1)
    return Self(
      fill: zip(fill, other.fill).map { FleckPillGeometry.mix($0, $1, progress) },
      rim: zip(rim, other.rim).map { FleckPillGeometry.mix($0, $1, progress) }
    )
  }
}

struct FleckErrorButtonColor: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double

  init(hex: String) {
    let value = UInt32(String(hex.dropFirst()), radix: 16) ?? 0
    red = Double((value >> 16) & 0xFF) / 255
    green = Double((value >> 8) & 0xFF) / 255
    blue = Double(value & 0xFF) / 255
  }

  init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  var hex: String {
    String(
      format: "#%02x%02x%02x",
      Int((red * 255).rounded()),
      Int((green * 255).rounded()),
      Int((blue * 255).rounded())
    )
  }

  func interpolated(to other: Self, progress: Double) -> Self {
    let progress = min(max(progress, 0), 1)
    return Self(
      red: FleckPillGeometry.mix(red, other.red, progress),
      green: FleckPillGeometry.mix(green, other.green, progress),
      blue: FleckPillGeometry.mix(blue, other.blue, progress)
    )
  }
}

struct FleckErrorButtonFeedback: Equatable, Sendable {
  let fill: [Double]
  let rim: [Double]
  let reflection: Double
  let scale: Double
  let color: FleckErrorButtonColor

  var colorHex: String { color.hex }
  var stops: FleckErrorButtonStops { FleckErrorButtonStops(fill: fill, rim: rim) }

  init(fill: [Double], rim: [Double], reflection: Double, scale: Double, colorHex: String) {
    self.init(
      fill: fill,
      rim: rim,
      reflection: reflection,
      scale: scale,
      color: FleckErrorButtonColor(hex: colorHex)
    )
  }

  private init(fill: [Double], rim: [Double], reflection: Double, scale: Double, color: FleckErrorButtonColor) {
    self.fill = fill
    self.rim = rim
    self.reflection = reflection
    self.scale = scale
    self.color = color
  }

  func interpolated(to other: Self, progress: Double) -> Self {
    let progress = min(max(progress, 0), 1)
    return Self(
      fill: zip(fill, other.fill).map { FleckPillGeometry.mix($0, $1, progress) },
      rim: zip(rim, other.rim).map { FleckPillGeometry.mix($0, $1, progress) },
      reflection: FleckPillGeometry.mix(reflection, other.reflection, progress),
      scale: FleckPillGeometry.mix(scale, other.scale, progress),
      color: color.interpolated(to: other.color, progress: progress)
    )
  }
}

enum FleckErrorGeometry {
  static let messageSize = 10.5
  static let actionSize = 9.5
  static let messageColorHex = "#c7c8ca"
  static let defaultActionColorHex = "#ced0d1"
  static let svgMessageBaselineShift = 3.0
  static let svgActionBaselineShift = 2.2
  static let pressDuration = 0.07
  static let buttonFillRimDuration = 0.09
  static let buttonColorReflectionDuration = 0.11
  static let retryMorphDuration = 0.32
  static let labelFadeDuration = 0.12
  static let copiedHoldDuration = 0.7
  static let dismissalDuration = 0.24
  static let contentExitDuration = 0.11
  static let microphoneFallbackMessageWidth = 128.421875
  static let repairProgressScale = 0.75
  static let repairProgressSourceCenterX = 112.0
  static let repairProgressSourceCenterY = 26.4

  static func microphoneMessageWidth() -> Double {
    let font = NSFont.systemFont(ofSize: CGFloat(messageSize), weight: .regular)
    let measuredWidth = Double((FleckErrorKind.microphone.message as NSString)
      .size(withAttributes: [.font: font]).width)
    guard measuredWidth.isFinite, measuredWidth > 0 else {
      return microphoneFallbackMessageWidth
    }
    return measuredWidth
  }

  static func microphoneContentOffset(
    messageWidth: Double,
    layout: FleckErrorLayout = .approved
  ) -> Double {
    let labelLeft = layout.messageCenterX - messageWidth / 2
    let buttonFaceRight = layout.buttonX + layout.buttonFaceX + layout.buttonFaceWidth
    return layout.canvasWidth / 2 - (labelLeft + buttonFaceRight) / 2
  }

  static func repairProgressTransform(
    layout: FleckErrorLayout = .approved
  ) -> CGAffineTransform {
    let scale = CGFloat(repairProgressScale)
    return CGAffineTransform(
      a: scale,
      b: 0,
      c: 0,
      d: scale,
      tx: CGFloat(
        layout.buttonX + layout.buttonWidth / 2
          - repairProgressSourceCenterX * repairProgressScale
      ),
      ty: CGFloat(
        layout.messageTextCenterY
          - repairProgressSourceCenterY * repairProgressScale
      )
    )
  }

  static func reflectionOpacity(dismissal: Double) -> Double {
    1 - FleckPillGeometry.clamp(dismissal)
  }

  static func reflectionTransform(
    for shell: FleckErrorShellGeometry,
    layout: FleckErrorLayout = .approved
  ) -> CGAffineTransform {
    let scaleX = shell.width / layout.visibleWidth
    let scaleY = shell.height / layout.visibleHeight
    return CGAffineTransform(
      a: layout.scale * scaleX,
      b: 0,
      c: 0,
      d: layout.scale * 0.925 * scaleY,
      tx: layout.artworkPadding + layout.scale * layout.artworkWidth / 2 * (1 - scaleX),
      ty: layout.scale * 15 + layout.scale * 0.925 * 40 * (1 - scaleY)
    )
  }

  static func shell(
    dismissal: Double = 0,
    target: FleckErrorShellTarget = .standby,
    layout: FleckErrorLayout = .approved
  ) -> FleckErrorShellGeometry {
    let q = FleckPillGeometry.clamp(dismissal)
    let start = logicalErrorContour(layout: layout)
    let end = normalContour(target: target, layout: layout)
    let contour = zip(start.commands, end.commands).map { first, second in
      interpolate(first, second, progress: q)
    }
    let path = FleckPillVectorPath(commands: contour)
    let width = FleckPillGeometry.mix(layout.visibleWidth, target.width, q)
    let height = FleckPillGeometry.mix(layout.visibleHeight, target.height, q)
    let left = (layout.artworkWidth - width / layout.scale) / 2
    let right = left + width / layout.scale
    let artworkContour = unmapErrorContour(path, layout: layout)
    let artworkFill = artworkContour.appending(FleckPillVectorPath(commands: [
      .line(FleckPillPoint(x: right, y: 41)),
      .line(FleckPillPoint(x: left, y: 41)),
      .close,
    ]))
    let fill = path.appending(FleckPillVectorPath(commands: [
      .line(errorPoint(FleckPillPoint(x: right, y: 41), layout: layout)),
      .line(errorPoint(FleckPillPoint(x: left, y: 41), layout: layout)),
      .close,
    ]))
    return FleckErrorShellGeometry(
      contour: path,
      fill: fill,
      artworkContour: artworkContour,
      artworkFill: artworkFill,
      width: width,
      height: height,
      baseline: layout.baseline,
      dismissal: q,
      target: target
    )
  }

  static func buttonFeedback(for phase: FleckErrorButtonPhase) -> FleckErrorButtonFeedback {
    switch phase {
    case .default, .copyFailed:
      FleckErrorButtonFeedback(
        fill: [0.027, 0.011, 0.006], rim: [0.30, 0.065, 0.16],
        reflection: 0.028, scale: 1, colorHex: defaultActionColorHex
      )
    case .hover, .focus:
      FleckErrorButtonFeedback(
        fill: [0.047, 0.019, 0.009], rim: [0.37, 0.085, 0.20],
        reflection: 0.062, scale: 1, colorHex: "#ededee"
      )
    case .pressed:
      FleckErrorButtonFeedback(
        fill: [0.077, 0.025, 0.015], rim: [0.40, 0.12, 0.24],
        reflection: 0.046, scale: 0.98, colorHex: "#e4e5e7"
      )
    case .pending:
      FleckErrorButtonFeedback(
        fill: [0.027, 0.011, 0.006], rim: [0.30, 0.065, 0.16],
        reflection: 0.028, scale: 1, colorHex: "#b6b7b9"
      )
    case .copied:
      FleckErrorButtonFeedback(
        fill: [0.038, 0.015, 0.008], rim: [0.34, 0.075, 0.19],
        reflection: 0.041, scale: 1, colorHex: "#d8dadb"
      )
    }
  }

  static func interpolatedButtonFeedback(
    from: FleckErrorButtonPhase,
    to: FleckErrorButtonPhase,
    progress: Double
  ) -> FleckErrorButtonFeedback {
    buttonFeedback(for: from).interpolated(to: buttonFeedback(for: to), progress: progress)
  }

  private static func logicalErrorContour(layout: FleckErrorLayout) -> FleckPillVectorPath {
    let contour = FleckPillGeometry.shell(expansion: 1).contour
    let widened = map(contour) { point in
      FleckPillPoint(
        x: point.x > 112 ? point.x + layout.centerExtension : point.x,
        y: point.y
      )
    }
    return map(widened) { errorPoint($0, layout: layout) }
  }

  private static func normalContour(
    target: FleckErrorShellTarget,
    layout: FleckErrorLayout
  ) -> FleckPillVectorPath {
    let shell = FleckPillGeometry.shell(expansion: target.expansion)
    return map(shell.contour) { point in
      let adjusted = shell.shellTransform.applying(to: point)
      return FleckPillPoint(
        x: layout.canvasWidth / 2 + (point.x - 112) * FleckPillGeometry.artworkScale,
        y: layout.baseline + (adjusted.y - FleckPillGeometry.baseline) * FleckPillGeometry.artworkScale
      )
    }
  }

  private static func errorPoint(_ point: FleckPillPoint, layout: FleckErrorLayout) -> FleckPillPoint {
    FleckPillPoint(
      x: layout.artworkPadding + point.x * layout.scale,
      y: (point.y * 0.925 + 15) * layout.scale
    )
  }

  private static func unmapErrorContour(
    _ path: FleckPillVectorPath,
    layout: FleckErrorLayout
  ) -> FleckPillVectorPath {
    map(path) { point in
      FleckPillPoint(
        x: (point.x - layout.artworkPadding) / layout.scale,
        y: ((point.y / layout.scale) - 15) / 0.925
      )
    }
  }

  private static func interpolate(
    _ first: FleckPillPathCommand,
    _ second: FleckPillPathCommand,
    progress: Double
  ) -> FleckPillPathCommand {
    switch (first, second) {
    case (.move(let first), .move(let second)):
      .move(mix(first, second, progress))
    case (.line(let first), .line(let second)):
      .line(mix(first, second, progress))
    case (.cubic(let firstA, let firstB, let firstEnd), .cubic(let secondA, let secondB, let secondEnd)):
      .cubic(
        mix(firstA, secondA, progress),
        mix(firstB, secondB, progress),
        mix(firstEnd, secondEnd, progress)
      )
    case (.close, .close):
      .close
    default:
      first
    }
  }

  private static func map(
    _ path: FleckPillVectorPath,
    _ transform: (FleckPillPoint) -> FleckPillPoint
  ) -> FleckPillVectorPath {
    FleckPillVectorPath(commands: path.commands.map { command in
      switch command {
      case .move(let point): .move(transform(point))
      case .line(let point): .line(transform(point))
      case .cubic(let first, let second, let end):
        .cubic(transform(first), transform(second), transform(end))
      case .close: .close
      }
    })
  }
  private static func mix(_ first: FleckPillPoint, _ second: FleckPillPoint, _ progress: Double) -> FleckPillPoint {
    FleckPillPoint(
      x: FleckPillGeometry.mix(first.x, second.x, progress),
      y: FleckPillGeometry.mix(first.y, second.y, progress)
    )
  }
}
#endif
