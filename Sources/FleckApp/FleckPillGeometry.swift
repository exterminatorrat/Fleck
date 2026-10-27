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
#endif
