import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func waveformClampsSmoothsAndKeepsElevenBars() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 100))
  model.receive(level: 2, now: Date(timeIntervalSince1970: 100.04))
  let loud = model.barLevels(
    at: Date(timeIntervalSince1970: 100.05),
    reduceMotion: false
  )

  #expect(loud.count == 11)
  #expect(loud.allSatisfy { (0...1).contains($0) })
  #expect(loud[5] > loud[0])
}

@Test @MainActor func waveformIsStaticAtMinimumDuringSilence() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 10))
  let first = model.barLevels(at: Date(timeIntervalSince1970: 10.1), reduceMotion: false)
  let second = model.barLevels(at: Date(timeIntervalSince1970: 10.3), reduceMotion: false)
  let reduced = model.barLevels(at: Date(timeIntervalSince1970: 10.3), reduceMotion: true)

  #expect(first == second)
  #expect(second == reduced)
  #expect(Set(first).count == 1)
  #expect(first.allSatisfy { $0 == 0.05 })
}

@Test @MainActor func waveformAmplitudeIncreasesWithRealInputLevel() {
  let start = Date(timeIntervalSince1970: 30)
  func peak(for level: Float) -> CGFloat {
    let model = DictationWaveformModel()
    model.beginListening(at: start)
    model.receive(level: level, now: start.addingTimeInterval(0.04))
    return model.barLevels(at: start.addingTimeInterval(0.05), reduceMotion: false).max()!
  }

  let quiet = peak(for: 0.01)
  let soft = peak(for: 0.05)
  let loud = peak(for: 0.20)
  #expect(quiet == 0.05)
  #expect(soft > quiet)
  #expect(loud > soft)
}

@Test @MainActor func waveformDecaysToRestWhenLevelsStopArriving() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 40)
  model.beginListening(at: start)
  model.receive(level: 0.20, now: start.addingTimeInterval(0.04))

  let active = model.barLevels(at: start.addingTimeInterval(0.05), reduceMotion: false)
  let stale = model.barLevels(at: start.addingTimeInterval(0.60), reduceMotion: false)
  #expect(active.max()! > 0.05)
  #expect(stale.allSatisfy { $0 == 0.05 })
}

@Test @MainActor func waveformThrottlesAndResets() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 20)
  model.beginListening(at: start)
  model.receive(level: 0.7, now: start.addingTimeInterval(0.04))
  let accepted = model.energy
  model.receive(level: 0.1, now: start.addingTimeInterval(0.05))

  #expect(model.energy == accepted)

  model.reset()
  #expect(model.energy == 0)
  #expect(model.listeningStartedAt == nil)
}

@Test @MainActor func waveformElapsedTimeUsesTabularMinuteSecondCopy() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 100))

  #expect(model.elapsedText(at: Date(timeIntervalSince1970: 108.9)) == "0:08")
  #expect(model.elapsedText(at: Date(timeIntervalSince1970: 165)) == "1:05")
}
