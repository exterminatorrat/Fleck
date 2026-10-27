#if os(macOS) && DEBUG
  import Testing

  @testable import FleckApp

  @Test func FleckPillFourPosesKeepOneActiveShell() throws {
    let frames = try FleckPillPose.allCases.map { try FleckPillGeometry.pose(named: $0.rawValue) }
    #expect(frames.map(\.state) == FleckPillPose.allCases)
    let activeShells = frames.dropFirst().map { FleckPillGeometry.shell(expansion: $0.expansion) }
    #expect(activeShells.count == 3)
    #expect(activeShells.dropFirst().allSatisfy { $0 == activeShells[0] })
    #expect(activeShells[0].contour.data == FleckPillGeometry.shell(expansion: 1).contour.data)
    #expect(activeShells[0].width == 168)
    #expect(activeShells[0].height == 27.75)
  }

  @Test func FleckPillTimelineBoundariesAreFrozenAndDeterministic() {
    #expect(FleckPillMotion.boundaries.count == 15)
    for time in FleckPillMotion.boundaries {
      let first = FleckPillMotion.sample(time)
      let second = FleckPillMotion.sample(time)
      #expect(first == second)
    }
    #expect(FleckPillMotion.sample(0.6).segment == "opening")
    #expect(FleckPillMotion.sample(0.92).segment == "activating")
    #expect(FleckPillMotion.sample(1.5).state == .listening)
    #expect(FleckPillMotion.sample(4.65).segment == "quiet")
    #expect(FleckPillMotion.sample(5.2).segment == "quiet")
    #expect(FleckPillMotion.sample(6.2).segment == "flattening")
    #expect(FleckPillMotion.sample(6.48).segment == "processing")
    #expect(FleckPillMotion.sample(8.6).segment == "closing")
    #expect(FleckPillMotion.sample(8.92).segment == "standby")
    #expect(FleckPillMotion.sample(.nan) == FleckPillMotion.sample(0))
    #expect(FleckPillMotion.sample(-.infinity) == FleckPillMotion.sample(0))
  }

  @Test func FleckPillGeometryRejectsInvalidCurvesAndSanitizesSignalInputs() throws {
    #expect(throws: FleckPillGeometryError.curveNeedsTwoPoints) {
      try FleckPillGeometry.curve([])
    }
    #expect(throws: FleckPillGeometryError.curveNeedsTwoPoints) {
      try FleckPillGeometry.ribbon([FleckPillPoint(x: 1, y: 2)])
    }
    #expect(throws: FleckPillGeometryError.unknownPose("silence")) {
      try FleckPillGeometry.pose(named: "silence")
    }
    #expect(FleckPillGeometry.shell(expansion: .nan) == FleckPillGeometry.shell(expansion: 0))
    #expect(FleckPillGeometry.waveSamples(energy: .nan, phase: .infinity)
      == FleckPillGeometry.waveSamples(energy: 0, phase: 0))

    let invalidFrame = FleckPillMotionFrame(
      time: .nan,
      state: .processing,
      label: "invalid",
      segment: "invalid",
      expansion: .nan,
      energy: .nan,
      phase: .infinity,
      activationMix: .nan,
      processingMix: .infinity,
      signalOpacity: .nan,
      glint: .nan,
      glintOpacity: .nan
    )
    let signal = FleckPillMotion.signalGeometry(invalidFrame)
    #expect(signal.points.count == 161)
    #expect(signal.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    #expect(signal.waveOpacity.isFinite)
    #expect(signal.lineOpacity.isFinite)
  }

  @Test func FleckPillPlaybackClockUsesInjectedTimeAndSupportsTransportControls() {
    var clock = FleckPillPlaybackClock()
    #expect(clock.play(at: 100).playing)
    #expect(clock.tick(at: 600).time == 0.5)
    #expect(clock.setRate(2, at: 600).rate == 2)
    #expect(clock.tick(at: 850).time == 1)
    #expect(clock.pause(at: 1_100).time == 1.5)
    #expect(!clock.snapshot().playing)
    #expect(clock.seek(to: 2.5).time == 2.5)
    #expect(clock.step(frames: 30).time == 3)
    #expect(clock.step(frames: -240).time == 0)
    #expect(clock.setRate(.nan).rate == 0.1)
    #expect(clock.seek(to: .infinity).time == 0)
    #expect(clock.setRate(1).rate == 1)

    _ = clock.seek(to: 9.5)
    #expect(clock.play(at: 2_000).playing)
    #expect(clock.tick(at: 2_500).time == 10)
    #expect(!clock.snapshot().playing)
    #expect(clock.play(at: 3_000).time == 0)

    _ = clock.setLoops(true)
    #expect(clock.play(at: 4_000).playing)
    #expect(clock.tick(at: 15_500).time == 1.5)
    #expect(clock.snapshot().playing)
  }
#endif
