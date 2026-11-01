#if os(macOS)
import Foundation

#if DEBUG
struct FleckPillMotionFrame: Equatable, Sendable {
  var time: Double
  var state: FleckPillPose
  var label: String
  var segment: String
  var expansion: Double
  var energy: Double
  var phase: Double
  var activationMix: Double
  var processingMix: Double
  var signalOpacity: Double
  var glint: Double
  var glintOpacity: Double

  var artworkFrame: FleckPillArtworkFrame {
    FleckPillArtworkFrame(
      expansion: expansion,
      energy: energy,
      phase: phase,
      activationMix: activationMix,
      processingMix: processingMix,
      signalOpacity: signalOpacity,
      glint: glint,
      glintOpacity: glintOpacity
    )
  }
}
#endif

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
  static let wavePhaseRate = 2.7
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

#if DEBUG
  static func signalGeometry(_ frame: FleckPillMotionFrame) -> FleckPillSignalGeometry {
    signalGeometry(frame.artworkFrame)
  }
#endif

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

#if DEBUG
  static let duration = 10.0
  static let anchors: [FleckPillPose: Double] = [
    .standby: 0.2,
    .activating: 1,
    .listening: 2.5,
    .processing: 7.1,
  ]
  static let boundaries: [Double] = [
    0.6, 0.78, 0.92, 1, 1.22, 1.5, 4.3, 4.65, 5.2,
    5.5, 6.2, 6.48, 8.6, 8.72, 8.92,
  ]
  static let chapters: [(label: String, time: Double)] = [
    ("Rest", 0),
    ("Open", 0.6),
    ("Voice", 1.5),
    ("Quiet", 4.65),
    ("Voice", 5.5),
    ("Process", 6.2),
    ("Return", 8.6),
  ]

  private static let energyKeys: [(time: Double, value: Double)] = [
    (0, 0.22), (1.22, 0.22), (1.5, 0.52), (1.78, 0.85),
    (2.12, 0.64), (2.5, 1), (2.86, 0.65), (3.2, 0.9),
    (3.65, 0.55), (4.02, 0.82), (4.3, 0.56), (4.65, 0),
    (5.2, 0), (5.5, 0.58), (5.8, 0.85), (6.2, 0.62),
  ]

  static func sample(_ seconds: Double) -> FleckPillMotionFrame {
    let time = FleckPillGeometry.clamp(seconds, lower: 0, upper: duration)
    var expansion = ramp(time, from: 0.6, to: 0.92) * (1 - ramp(time, from: 8.6, to: 8.92))
    if time >= 0.92 && time <= 8.6 { expansion = 1 }
    let signalOpacity = ramp(time, from: 0.78, to: 0.92) * (1 - ramp(time, from: 8.6, to: 8.72))
    let activationMix = 1 - ramp(time, from: 1.22, to: 1.5)
    let processingMix = ramp(time, from: 6.2, to: 6.48)
    let phaseTime = max(0, min(time, 4.65) - 1.22) + max(0, min(time, 6.2) - 5.2)
    let phase = wavePhaseRate * (phaseTime - 1.28)
    var state: FleckPillPose = .standby
    var label = "Standby"
    var segment = "standby"
    if time >= 0.6 && time < 1.5 {
      state = .activating
      label = time < 0.92 ? "Opening" : "Activation"
      segment = time < 0.92 ? "opening" : "activating"
    } else if time >= 1.5 && time < 6.2 {
      state = .listening
      label = time >= 4.65 && time <= 5.2 ? "Quiet · still listening" : "Listening"
      segment = time >= 4.65 && time <= 5.2 ? "quiet" : "listening"
    } else if time >= 6.2 && time < 8.6 {
      state = .processing
      label = time < 6.48 ? "Wave → line" : "Processing"
      segment = time < 6.48 ? "flattening" : "processing"
    } else if time >= 8.6 && time < 8.92 {
      label = "Returning to standby"
      segment = "closing"
    }
    let shimmer = shimmer(at: time)
    return FleckPillMotionFrame(
      time: time,
      state: state,
      label: label,
      segment: segment,
      expansion: expansion,
      energy: energy(at: time),
      phase: phase,
      activationMix: activationMix,
      processingMix: processingMix,
      signalOpacity: signalOpacity,
      glint: shimmer.position,
      glintOpacity: shimmer.opacity
    )
  }

  private static func energy(at time: Double) -> Double {
    if time <= energyKeys[0].time { return energyKeys[0].value }
    for index in 1..<energyKeys.count {
      let first = energyKeys[index - 1]
      let second = energyKeys[index]
      if time <= second.time {
        return FleckPillGeometry.mix(
          first.value,
          second.value,
          ramp(time, from: first.time, to: second.time)
        )
      }
    }
    return energyKeys[energyKeys.count - 1].value
  }

  private static func shimmer(at time: Double) -> (position: Double, opacity: Double) {
    let elapsed = min(time, 8.6) - anchors[.processing]! + 0.61 * 0.86
    let local = (elapsed.truncatingRemainder(dividingBy: 1.1) + 1.1)
      .truncatingRemainder(dividingBy: 1.1)
    let position = FleckPillGeometry.clamp(local / 0.86)
    let opacity = ramp(local, from: 0, to: 0.09) * (1 - ramp(local, from: 0.77, to: 0.86))
    return (position, opacity)
  }
#endif
}

struct FleckErrorRepairSample: Equatable, Sendable {
  let glint: Double
  let opacity: Double
}

enum FleckErrorRepairMotion {
  static let cycleDuration = 1.1
  static let travelDuration = 0.86

  static func sample(
    at elapsed: TimeInterval,
    reduceMotion: Bool
  ) -> FleckErrorRepairSample {
    guard !reduceMotion else {
      return FleckErrorRepairSample(glint: 0.61, opacity: 1)
    }
    let local = max(0, FleckPillGeometry.finite(elapsed))
      .truncatingRemainder(dividingBy: cycleDuration)
    return FleckErrorRepairSample(
      glint: FleckPillGeometry.clamp(local / travelDuration),
      opacity: FleckPillGeometry.smooth(local / 0.09)
        * (1 - FleckPillGeometry.smooth((local - 0.77) / 0.09))
    )
  }
}

#if DEBUG
struct FleckPillPlaybackClock: Equatable, Sendable {
  struct Snapshot: Equatable, Sendable {
    var time: Double
    var rate: Double
    var loops: Bool
    var playing: Bool
  }

  private(set) var time = 0.0
  private(set) var rate = 1.0
  private(set) var loops = false
  private(set) var playing = false
  private var lastTimestamp: Double?

  func snapshot() -> Snapshot {
    Snapshot(time: time, rate: rate, loops: loops, playing: playing)
  }

  mutating func tick(at timestamp: Double) -> Snapshot {
    let now = FleckPillGeometry.finite(timestamp, fallback: lastTimestamp ?? 0)
    if playing, let previous = lastTimestamp {
      time += max(0, now - previous) / 1000 * rate
      if time >= FleckPillMotion.duration {
        if loops {
          time = time.truncatingRemainder(dividingBy: FleckPillMotion.duration)
        } else {
          time = FleckPillMotion.duration
          playing = false
        }
      }
    }
    lastTimestamp = playing ? max(lastTimestamp ?? now, now) : nil
    return snapshot()
  }

  mutating func play(at timestamp: Double) -> Snapshot {
    if time >= FleckPillMotion.duration { time = 0 }
    playing = true
    lastTimestamp = FleckPillGeometry.finite(timestamp)
    return snapshot()
  }

  mutating func pause(at timestamp: Double? = nil) -> Snapshot {
    if let timestamp { _ = tick(at: timestamp) }
    playing = false
    lastTimestamp = nil
    return snapshot()
  }

  mutating func seek(to newTime: Double, at timestamp: Double? = nil) -> Snapshot {
    time = FleckPillGeometry.clamp(newTime, lower: 0, upper: FleckPillMotion.duration)
    lastTimestamp = playing && timestamp != nil
      ? FleckPillGeometry.finite(timestamp!, fallback: 0)
      : nil
    return snapshot()
  }

  mutating func select(_ pose: FleckPillPose) -> Snapshot {
    _ = pause()
    return seek(to: FleckPillMotion.anchors[pose]!)
  }

  mutating func setRate(_ newRate: Double, at timestamp: Double? = nil) -> Snapshot {
    if let timestamp { _ = tick(at: timestamp) }
    rate = min(2, max(0.1, FleckPillGeometry.finite(newRate)))
    return snapshot()
  }

  mutating func setLoops(_ value: Bool) -> Snapshot {
    loops = value
    return snapshot()
  }

  mutating func step(frames: Int) -> Snapshot {
    _ = pause()
    time = FleckPillGeometry.clamp(
      time + Double(frames) / 60,
      lower: 0,
      upper: FleckPillMotion.duration
    )
    return snapshot()
  }
}
#endif
#endif
