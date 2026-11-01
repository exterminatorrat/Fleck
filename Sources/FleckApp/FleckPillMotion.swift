#if os(macOS)
import Foundation


struct FleckPillArtworkFrame: Equatable, Sendable {
  var expansion: Double
  var energy: Double
  var phase: Double
  var activationMix: Double
  var processingMix: Double
  var signalOpacity: Double
  var glint: Double
  var glintOpacity: Double
}

struct FleckPillSignalGeometry: Equatable, Sendable {
  var points: [FleckPillPoint]
  var core: FleckPillVectorPath
  var scatter: FleckPillVectorPath
  var line: FleckPillVectorPath
  var waveOpacity: Double
  var lineOpacity: Double
}

enum FleckPillMotion {
  static let liveWavePhaseRate = 6.075

  static func signalGeometry(_ frame: FleckPillArtworkFrame) -> FleckPillSignalGeometry {
    let energy = FleckPillGeometry.clamp(frame.energy)
    let activation = FleckPillGeometry.clamp(frame.activationMix)
    let processing = FleckPillGeometry.clamp(frame.processingMix)
    let listening = FleckPillGeometry.waveSamples(energy: energy, phase: frame.phase)
    let opening = activation > 0
      ? FleckPillGeometry.waveSamples(energy: 0.22, pose: .activating)
      : nil
    var points: [FleckPillPoint]
    if activation == 0 {
      points = listening
    } else if activation == 1 {
      points = opening!
    } else {
      points = listening.enumerated().map { index, point in
        FleckPillPoint(
          x: point.x,
          y: FleckPillGeometry.mix(point.y, opening![index].y, activation)
        )
      }
    }
    if processing > 0 {
      points = points.enumerated().map { index, point in
        let progress = Double(index) / Double(points.count - 1)
        return FleckPillPoint(
          x: FleckPillGeometry.mix(point.x, 76 + 72 * progress, processing),
          y: FleckPillGeometry.mix(point.y, 26.4, processing)
        )
      }
    }
    let width = FleckPillGeometry.mix(0.52 + 1.38 * energy, 0.6, activation)
    let spread = FleckPillGeometry.mix(1 + 2.1 * energy, 0.9, activation)
    let line = processing == 1
      ? FleckPillVectorPath(commands: [
        .move(FleckPillPoint(x: 76, y: 26.4)),
        .cubic(
          FleckPillPoint(x: 100, y: 26.4),
          FleckPillPoint(x: 124, y: 26.4),
          FleckPillPoint(x: 148, y: 26.4)
        ),
      ])
      : FleckPillGeometry.curveUnchecked(points)
    return FleckPillSignalGeometry(
      points: points,
      core: FleckPillGeometry.ribbonUnchecked(points, width: width),
      scatter: FleckPillGeometry.ribbonUnchecked(points, width: spread),
      line: line,
      waveOpacity: (1 - processing) * FleckPillGeometry.mix(1, 0.78, activation),
      lineOpacity: processing
    )
  }


  static func processingGlint(at elapsed: TimeInterval) -> (position: Double, opacity: Double) {
    let local = max(elapsed - 0.28, 0).truncatingRemainder(dividingBy: 1.1)
    return (
      FleckPillGeometry.clamp(local / 0.86),
      ramp(local, from: 0, to: 0.09) * (1 - ramp(local, from: 0.77, to: 0.86))
    )
  }

  private static func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
    FleckPillGeometry.smooth((value - start) / (end - start))
  }

}
#endif
