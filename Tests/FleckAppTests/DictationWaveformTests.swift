import AppKit
import Testing

@testable import FleckApp

@Test func waveformRefreshCadenceUsesNormalAndReducedMotionBudgets() {
  #expect(DictationWaveformRefreshSchedule.interval(reduceMotion: false) == 1.0 / 30.0)
  #expect(DictationWaveformRefreshSchedule.interval(reduceMotion: true) == 1.0 / 15.0)
}

@Test @MainActor func waveformUsesThirteenStableAsymmetricBarsAndExactGeometry() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 100))
  model.receive(level: 2, now: Date(timeIntervalSince1970: 100.04))
  let loud = model.barHeights(
    at: Date(timeIntervalSince1970: 100.05),
    reduceMotion: false
  )

  #expect(DictationWaveformModel.barCount == 13)
  #expect(DictationWaveformModel.barWidth == 1.5)
  #expect(DictationWaveformModel.barGap == 1.5)
  #expect(
    CGFloat(DictationWaveformModel.barCount) * DictationWaveformModel.barWidth
      + CGFloat(DictationWaveformModel.barCount - 1) * DictationWaveformModel.barGap == 37.5
  )
  #expect(DictationWaveformModel.minimumHeight == 3)
  #expect(DictationWaveformModel.maximumHeight == 20)
  #expect(DictationWaveformModel.barWeights.count == 13)
  #expect(Set(DictationWaveformModel.barWeights).count > 1)
  #expect(loud.count == 13)
  #expect(loud.allSatisfy {
    (DictationWaveformModel.minimumHeight...DictationWaveformModel.maximumHeight).contains($0)
  })
  #expect(loud[0] != loud[1])
}

@Test @MainActor func waveformReachesNormalMaximumAfterSustainedLoudInput() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 15)
  model.beginListening(at: start)

  for index in 0...12 {
    model.receive(
      level: 1,
      now: start.addingTimeInterval(0.04 + (Double(index) * 0.04))
    )
  }

  let heights = model.barHeights(
    at: start.addingTimeInterval(0.57),
    reduceMotion: false
  )
  #expect(heights.max()! > 19.9)
}

@Test @MainActor func waveformIsStaticAtMinimumDuringSilence() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 10))
  let first = model.barHeights(at: Date(timeIntervalSince1970: 10.1), reduceMotion: false)
  let second = model.barHeights(at: Date(timeIntervalSince1970: 10.3), reduceMotion: false)
  let reduced = model.barHeights(at: Date(timeIntervalSince1970: 10.3), reduceMotion: true)

  #expect(first == second)
  #expect(second == reduced)
  #expect(Set(first).count == 1)
  #expect(first.allSatisfy { $0 == DictationWaveformModel.minimumHeight })
}

@Test @MainActor func waveformRespondsImmediatelyAcrossRepresentativeMicrophoneRMS() {
  let start = Date(timeIntervalSince1970: 30)
  func peak(for level: Float) -> CGFloat {
    let model = DictationWaveformModel()
    model.beginListening(at: start)
    model.receive(level: level, now: start.addingTimeInterval(0.04))
    return model.barHeights(at: start.addingTimeInterval(0.05), reduceMotion: false).max()!
  }

  let silence = peak(for: 0.002)
  let soft = peak(for: 0.006)
  let conversational = peak(for: 0.02)
  let loud = peak(for: 0.20)
  #expect(silence == DictationWaveformModel.minimumHeight)
  #expect(soft >= silence + 0.75)
  #expect(conversational > soft)
  #expect(loud > conversational)
}

@Test @MainActor func waveformUsesFastAttackAndSlowerReleaseWithoutSyntheticMotion() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 35)
  model.beginListening(at: start)
  model.receive(level: 0.24, now: start.addingTimeInterval(0.04))
  let attack = model.energy
  model.receive(level: 0.015, now: start.addingTimeInterval(0.08))
  let release = attack - model.energy

  #expect(attack > 0)
  #expect(release > 0)
  #expect(attack > release)
}

@Test @MainActor func waveformDecaysToRestWhenLevelsStopArriving() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 40)
  model.beginListening(at: start)
  model.receive(level: 0.20, now: start.addingTimeInterval(0.04))

  let active = model.barHeights(at: start.addingTimeInterval(0.05), reduceMotion: false)
  let stale = model.barHeights(at: start.addingTimeInterval(0.49), reduceMotion: false)
  let reducedStale = model.barHeights(at: start.addingTimeInterval(0.49), reduceMotion: true)
  #expect(active.max()! > DictationWaveformModel.minimumHeight)
  #expect(stale.allSatisfy { $0 == DictationWaveformModel.minimumHeight })
  #expect(reducedStale == stale)
}

@Test @MainActor func waveformResumesFromDisplayedRestInsteadOfStaleLoudEnergy() {
  let start = Date(timeIntervalSince1970: 50)
  let resumed = DictationWaveformModel()
  let fresh = DictationWaveformModel()
  resumed.beginListening(at: start)
  resumed.receive(level: 0.20, now: start.addingTimeInterval(0.04))

  let resumedAtRest = resumed.barHeights(at: start.addingTimeInterval(0.60), reduceMotion: false)
  #expect(resumedAtRest.allSatisfy { $0 == DictationWaveformModel.minimumHeight })

  fresh.beginListening(at: start.addingTimeInterval(0.56))
  resumed.receive(level: 0.05, now: start.addingTimeInterval(0.60))
  fresh.receive(level: 0.05, now: start.addingTimeInterval(0.60))

  let resumedLevels = resumed.barHeights(at: start.addingTimeInterval(0.61), reduceMotion: false)
  let freshLevels = fresh.barHeights(at: start.addingTimeInterval(0.61), reduceMotion: false)
  #expect(resumedLevels == freshLevels)
}

@Test @MainActor func waveformThrottlesAndResets() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 20)
  model.beginListening(at: start)
  model.receive(level: 0.7, now: start.addingTimeInterval(0.04))
  let accepted = model.energy
  model.receive(level: 0.1, now: start.addingTimeInterval(0.05))

  #expect(model.energy == accepted)

  model.receive(level: 0.1, now: start.addingTimeInterval(0.08), reduceMotion: true)
  let reducedAccepted = model.energy
  model.receive(level: 0.9, now: start.addingTimeInterval(0.10), reduceMotion: true)
  #expect(model.energy == reducedAccepted)

  model.reset()
  #expect(model.energy == 0)
  #expect(model.listeningStartedAt == nil)
  #expect(model.lastAcceptedLevelAt == nil)
}

@Test @MainActor func waveformReducedMotionUsesFifteenHertzAndSmoothedLowerAmplitude() {
  let start = Date(timeIntervalSince1970: 60)
  let normal = DictationWaveformModel()
  let reduced = DictationWaveformModel()
  normal.beginListening(at: start)
  reduced.beginListening(at: start)
  normal.receive(level: 0.24, now: start.addingTimeInterval(0.04))
  reduced.receive(level: 0.24, now: start.addingTimeInterval(0.04), reduceMotion: true)

  let normalHeights = normal.barHeights(at: start.addingTimeInterval(0.05), reduceMotion: false)
  let reducedHeights = reduced.barHeights(at: start.addingTimeInterval(0.05), reduceMotion: true)
  #expect(reducedHeights.max()! < normalHeights.max()!)
  #expect(DictationWaveformModel.refreshInterval(reduceMotion: false) == 1.0 / 30.0)
  #expect(DictationWaveformModel.refreshInterval(reduceMotion: true) == 1.0 / 15.0)
}

@Test @MainActor func waveformElapsedTimeUsesTabularMinuteSecondCopy() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 100))

  #expect(model.elapsedText(at: Date(timeIntervalSince1970: 108.9)) == "0:08")
  #expect(model.elapsedText(at: Date(timeIntervalSince1970: 165)) == "1:05")
}
