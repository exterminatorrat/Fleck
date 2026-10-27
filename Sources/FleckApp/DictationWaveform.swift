#if os(macOS)
  import Combine
  import Foundation

  @MainActor
  final class DictationWaveformModel: ObservableObject {
    static let barCount = 13
    static let barWidth: CGFloat = 2
    static let barGap: CGFloat = 1
    static let minimumHeight: CGFloat = 3
    static let maximumHeight: CGFloat = 20
    static let reducedMaximumHeight: CGFloat = 12
    static let barWeights: [CGFloat] = [
      0.32, 0.54, 0.43, 0.76, 0.62, 0.88, 1.0,
      0.88, 0.62, 0.76, 0.43, 0.54, 0.32
    ]
    static let noiseFloorDecibels: CGFloat = -50
    static let fullScaleDecibels: CGFloat = -12
    static let attackSmoothing: CGFloat = 0.65
    static let releaseSmoothing: CGFloat = 0.18
    static let staleGracePeriod: TimeInterval = 0.12
    static let staleDecayDuration: TimeInterval = 0.30
    static let reducedAmplitudeScale: CGFloat = 0.72

    @Published private(set) var energy: CGFloat = 0
    private(set) var listeningStartedAt: Date?
    private(set) var lastAcceptedLevelAt: Date?
    private var listeningStartedTime: TimeInterval?
    private var lastSampledLevelTime: TimeInterval?
    private var lastAcceptedLevelTime: TimeInterval?
    private var usesMonotonicTime = false

    static func refreshInterval(reduceMotion: Bool) -> TimeInterval {
      reduceMotion ? 1 / 15 : 1 / 30
    }

    func beginListening(at date: Date = Date()) {
      beginListening(at: date.timeIntervalSinceReferenceDate, usesMonotonicTime: false)
      listeningStartedAt = date
    }

    func beginListening(monotonicNow: TimeInterval) {
      beginListening(at: monotonicNow, usesMonotonicTime: true)
    }

    private func beginListening(at time: TimeInterval, usesMonotonicTime: Bool) {
      self.usesMonotonicTime = usesMonotonicTime
      listeningStartedTime = time
      lastSampledLevelTime = nil
      lastAcceptedLevelTime = nil
      listeningStartedAt = nil
      lastAcceptedLevelAt = nil
      energy = 0
    }

    func receive(
      level: Float,
      now: Date = Date(),
      reduceMotion: Bool = false
    ) {
      if receive(
        level: level,
        at: now.timeIntervalSinceReferenceDate,
        usesMonotonicTime: false,
        reduceMotion: reduceMotion
      ) { lastAcceptedLevelAt = now }
    }

    func receive(
      level: Float,
      monotonicNow: TimeInterval,
      reduceMotion: Bool = false
    ) {
      receive(
        level: level,
        at: monotonicNow,
        usesMonotonicTime: true,
        reduceMotion: reduceMotion
      )
    }

    @discardableResult
    private func receive(
      level: Float,
      at time: TimeInterval,
      usesMonotonicTime: Bool,
      reduceMotion: Bool
    ) -> Bool {
      guard self.usesMonotonicTime == usesMonotonicTime else { return false }
      if let lastSampledLevelTime,
        time - lastSampledLevelTime < Self.refreshInterval(reduceMotion: reduceMotion)
      {
        return false
      }
      lastSampledLevelTime = time
      let previousEnergy = lastAcceptedLevelTime == nil
        ? energy
        : displayedEnergy(at: time, usesMonotonicTime: usesMonotonicTime)
      let rawLevel = CGFloat(level)
      let finiteLevel = rawLevel.isFinite ? max(rawLevel, 0) : 0
      let decibels = finiteLevel > 0 ? 20 * log10(finiteLevel) : Self.noiseFloorDecibels
      let normalized = min(
        max(
          (decibels - Self.noiseFloorDecibels)
            / (Self.fullScaleDecibels - Self.noiseFloorDecibels),
          0
        ),
        1
      )
      if normalized > 0 { lastAcceptedLevelTime = time }
      let smoothing = normalized > previousEnergy ? Self.attackSmoothing : Self.releaseSmoothing
      let nextEnergy = min(max(previousEnergy + (normalized - previousEnergy) * smoothing, 0), 1)
      if nextEnergy != energy { energy = nextEnergy }
      return normalized > 0
    }

    func reset() {
      listeningStartedAt = nil
      lastAcceptedLevelAt = nil
      listeningStartedTime = nil
      lastSampledLevelTime = nil
      lastAcceptedLevelTime = nil
      usesMonotonicTime = false
      energy = 0
    }

    private func staleScale(at time: TimeInterval, usesMonotonicTime: Bool) -> CGFloat {
      guard
        self.usesMonotonicTime == usesMonotonicTime,
        let lastAcceptedLevelTime
      else { return 0 }
      let elapsed = time - lastAcceptedLevelTime
      let staleInterval = max(elapsed - Self.staleGracePeriod, 0)
      return max(
        1 - CGFloat(staleInterval / Self.staleDecayDuration),
        0
      )
    }

    private func displayedEnergy(at time: TimeInterval, usesMonotonicTime: Bool) -> CGFloat {
      min(max(energy * staleScale(at: time, usesMonotonicTime: usesMonotonicTime), 0), 1)
    }

    func displayedEnergy(monotonicNow: TimeInterval) -> CGFloat {
      displayedEnergy(at: monotonicNow, usesMonotonicTime: true)
    }

    func barLevels(at date: Date, reduceMotion: Bool) -> [CGFloat] {
      barLevels(
        at: date.timeIntervalSinceReferenceDate,
        usesMonotonicTime: false,
        reduceMotion: reduceMotion
      )
    }

    func barLevels(monotonicNow: TimeInterval, reduceMotion: Bool) -> [CGFloat] {
      barLevels(at: monotonicNow, usesMonotonicTime: true, reduceMotion: reduceMotion)
    }

    private func barLevels(
      at time: TimeInterval,
      usesMonotonicTime: Bool,
      reduceMotion: Bool
    ) -> [CGFloat] {
      let displayedEnergy = displayedEnergy(at: time, usesMonotonicTime: usesMonotonicTime)
      let amplitude = reduceMotion
        ? displayedEnergy * Self.reducedAmplitudeScale
        : displayedEnergy
      return Self.barWeights.map { weight in
        min(max(amplitude * weight, 0), 1)
      }
    }

    func barHeights(at date: Date, reduceMotion: Bool) -> [CGFloat] {
      barHeights(
        at: date.timeIntervalSinceReferenceDate,
        usesMonotonicTime: false,
        reduceMotion: reduceMotion
      )
    }

    func barHeights(monotonicNow: TimeInterval, reduceMotion: Bool) -> [CGFloat] {
      barHeights(at: monotonicNow, usesMonotonicTime: true, reduceMotion: reduceMotion)
    }

    private func barHeights(
      at time: TimeInterval,
      usesMonotonicTime: Bool,
      reduceMotion: Bool
    ) -> [CGFloat] {
      let maximum = reduceMotion ? Self.reducedMaximumHeight : Self.maximumHeight
      let range = maximum - Self.minimumHeight
      return barLevels(at: time, usesMonotonicTime: usesMonotonicTime, reduceMotion: reduceMotion).map {
        Self.minimumHeight + ($0 * range)
      }
    }

    func elapsedText(at date: Date) -> String {
      elapsedText(at: date.timeIntervalSinceReferenceDate, usesMonotonicTime: false)
    }

    func elapsedText(monotonicNow: TimeInterval) -> String {
      elapsedText(at: monotonicNow, usesMonotonicTime: true)
    }

    private func elapsedText(at time: TimeInterval, usesMonotonicTime: Bool) -> String {
      guard
        self.usesMonotonicTime == usesMonotonicTime,
        let listeningStartedTime
      else { return "0:00" }
      let seconds = max(Int(time - listeningStartedTime), 0)
      return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
  }
#endif
