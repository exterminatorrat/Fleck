#if os(macOS)
  import Combine
  import Foundation

  @MainActor
  final class DictationWaveformModel: ObservableObject {
    static let barCount = 13
    static let barWidth: CGFloat = 1.5
    static let barGap: CGFloat = 1.5
    static let minimumHeight: CGFloat = 3
    static let maximumHeight: CGFloat = 20
    static let reducedMaximumHeight: CGFloat = 12
    static let barWeights: [CGFloat] = [
      0.72, 0.84, 0.93, 0.78, 0.98, 0.89, 1.0,
      0.91, 0.99, 0.82, 0.94, 0.76, 0.87
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
    private var recentEnergies: [CGFloat] = []

    static func refreshInterval(reduceMotion: Bool) -> TimeInterval {
      reduceMotion ? 1 / 15 : 1 / 30
    }

    func beginListening(at date: Date = Date()) {
      listeningStartedAt = date
      lastAcceptedLevelAt = nil
      energy = 0
      recentEnergies.removeAll(keepingCapacity: true)
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
        let decayScale = staleScale(at: now)
        energy *= decayScale
        if decayScale > 0 {
          recentEnergies = recentEnergies.map { $0 * decayScale }
        } else {
          recentEnergies.removeAll(keepingCapacity: true)
        }
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
      recentEnergies.append(energy)
      if recentEnergies.count > Self.barCount {
        recentEnergies.removeFirst(recentEnergies.count - Self.barCount)
      }
    }

    func reset() {
      listeningStartedAt = nil
      lastAcceptedLevelAt = nil
      energy = 0
      recentEnergies.removeAll(keepingCapacity: true)
    }

    private func staleScale(at date: Date) -> CGFloat {
      guard let lastAcceptedLevelAt else { return 0 }
      let elapsed = date.timeIntervalSince(lastAcceptedLevelAt)
      let staleInterval = max(elapsed - Self.staleGracePeriod, 0)
      return max(
        1 - CGFloat(staleInterval / Self.staleDecayDuration),
        0
      )
    }

    func barLevels(at date: Date, reduceMotion: Bool) -> [CGFloat] {
      let amplitudeScale = staleScale(at: date)
        * (reduceMotion ? Self.reducedAmplitudeScale : 1)
      return Self.barWeights.enumerated().map { index, weight in
        guard !recentEnergies.isEmpty else { return 0 }
        let historyIndex = min(
          index * recentEnergies.count / Self.barCount,
          recentEnergies.count - 1
        )
        return min(max(recentEnergies[historyIndex] * amplitudeScale * weight, 0), 1)
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
