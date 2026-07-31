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

@Test @MainActor func waveformUsesAQuietMovingBaselineDuringSilence() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 10))
  let first = model.barLevels(
    at: Date(timeIntervalSince1970: 10.1),
    reduceMotion: false
  )
  let second = model.barLevels(
    at: Date(timeIntervalSince1970: 10.2),
    reduceMotion: false
  )

  #expect(first != second)
  #expect(first.max()! < 0.25)
  #expect(second.max()! < 0.25)
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
