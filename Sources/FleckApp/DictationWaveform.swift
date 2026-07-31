#if os(macOS)
  import Combine
  import Foundation

  @MainActor
  final class DictationWaveformModel: ObservableObject {
    @Published private(set) var energy: CGFloat = 0
    private(set) var listeningStartedAt: Date?
    private var lastAcceptedLevelAt: Date?

    func beginListening(at date: Date = Date()) {
      listeningStartedAt = date
      lastAcceptedLevelAt = nil
      energy = 0
    }

    func receive(level: Float, now: Date = Date()) {
      if let lastAcceptedLevelAt,
        now.timeIntervalSince(lastAcceptedLevelAt) < (1 / 30)
      {
        return
      }
      lastAcceptedLevelAt = now
      let normalized = min(max((CGFloat(level) - 0.015) / 0.24, 0), 1)
      let smoothing: CGFloat = normalized > energy ? 0.65 : 0.18
      energy += (normalized - energy) * smoothing
    }

    func reset() {
      listeningStartedAt = nil
      lastAcceptedLevelAt = nil
      energy = 0
    }

    func barLevels(at date: Date, reduceMotion: Bool) -> [CGFloat] {
      let elapsed = date.timeIntervalSince(listeningStartedAt ?? date)
      return (0..<11).map { index in
        let distance = abs(CGFloat(index) - 5) / 5
        let centerWeight = 1 - (distance * 0.58)
        let motion =
          reduceMotion
          ? 0.5
          : (sin((elapsed * 8.5) + (Double(index) * 0.9)) + 1) / 2
        let baseline = 0.07 + (CGFloat(motion) * (reduceMotion ? 0.02 : 0.08))
        let voice = energy * centerWeight * (0.72 + CGFloat(motion) * 0.28)
        return min(max(baseline + voice, 0.05), 1)
      }
    }

    func elapsedText(at date: Date) -> String {
      let seconds = max(Int(date.timeIntervalSince(listeningStartedAt ?? date)), 0)
      return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
  }
#endif
