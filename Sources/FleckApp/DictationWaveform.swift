#if os(macOS)
  import Combine
  import Foundation

  @MainActor
  final class DictationWaveformModel: ObservableObject {
    static let barCount = 7
    static let barWidth: CGFloat = 2.5
    static let barGap: CGFloat = 2
    static let minimumHeight: CGFloat = 4
    static let maximumHeight: CGFloat = 17
    static let reducedMaximumHeight: CGFloat = 12
    static let barWeights: [CGFloat] = [0.78, 0.93, 1.0, 0.84, 0.96, 0.72, 0.88]
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

    static func refreshInterval(reduceMotion: Bool) -> TimeInterval {
      reduceMotion ? 1 / 15 : 1 / 30
    }

    func beginListening(at date: Date = Date()) {
      listeningStartedAt = date
      lastAcceptedLevelAt = nil
      energy = 0
    }

    func receive(
      level: Float,
      now: Date = Date(),
      reduceMotion: Bool = false
    ) {
      if let lastAcceptedLevelAt,
        now.timeIntervalSince(lastAcceptedLevelAt) < Self.refreshInterval(reduceMotion: reduceMotion)
      {
        return
      }
      if lastAcceptedLevelAt != nil {
        energy = displayedEnergy(at: now)
      }
      lastAcceptedLevelAt = now
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
      let smoothing = normalized > energy ? Self.attackSmoothing : Self.releaseSmoothing
      energy = min(max(energy + (normalized - energy) * smoothing, 0), 1)
    }

    func reset() {
      listeningStartedAt = nil
      lastAcceptedLevelAt = nil
      energy = 0
    }

    private func displayedEnergy(at date: Date) -> CGFloat {
      guard let lastAcceptedLevelAt else { return 0 }
      let elapsed = date.timeIntervalSince(lastAcceptedLevelAt)
      let staleInterval = max(elapsed - Self.staleGracePeriod, 0)
      let staleScale = max(
        1 - CGFloat(staleInterval / Self.staleDecayDuration),
        0
      )
      return min(max(energy * staleScale, 0), 1)
    }

    func barLevels(at date: Date, reduceMotion: Bool) -> [CGFloat] {
      let displayedEnergy = displayedEnergy(at: date)
      let amplitude = reduceMotion
        ? displayedEnergy * Self.reducedAmplitudeScale
        : displayedEnergy
      return Self.barWeights.map { weight in
        min(max(amplitude * weight, 0), 1)
      }
    }

    func barHeights(at date: Date, reduceMotion: Bool) -> [CGFloat] {
      let maximum = reduceMotion ? Self.reducedMaximumHeight : Self.maximumHeight
      let range = maximum - Self.minimumHeight
      return barLevels(at: date, reduceMotion: reduceMotion).map {
        Self.minimumHeight + ($0 * range)
      }
    }

    func elapsedText(at date: Date) -> String {
      let seconds = max(Int(date.timeIntervalSince(listeningStartedAt ?? date)), 0)
      return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
  }
#endif
