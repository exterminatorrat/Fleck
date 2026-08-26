import Testing

@testable import FleckApp

@Test func reduceMotionRemovesMovementAndPressScaling() {
  let motion = AppMotion(reduceMotion: true)

  #expect(motion.pressScale == 1)
  #expect(motion.offset == 0)
  #expect(!motion.allowsSpatialMotion(for: .pointer))
  #expect(motion.presentationAnimation(for: .pointer) != nil)
}

@Test func standardMotionUsesRestrainedNativeValues() {
  let motion = AppMotion(reduceMotion: false)

  #expect(AppMotion.pressDuration == 0.10)
  #expect(AppMotion.stateDuration == 0.12)
  #expect(AppMotion.selectionDuration == 0.16)
  #expect(AppMotion.revealDuration == 0.18)
  #expect(AppMotion.surfaceDuration == 0.22)
  #expect(AppMotion.rareDuration == 0.26)
  #expect(AppMotion.quickDuration == 0.10)
  #expect(AppMotion.standardDuration == 0.16)
  #expect(motion.pressScale == 0.97)
  #expect(motion.offset == 4)
}

@Test func keyboardPresentationIsInstantAndNeverSpatial() {
  let motion = AppMotion(reduceMotion: false)

  #expect(motion.presentationAnimation(for: .keyboard) == nil)
  #expect(!motion.allowsSpatialMotion(for: .keyboard))
}

@Test func pointerPresentationMayPreserveSpatialContinuity() {
  let motion = AppMotion(reduceMotion: false)

  #expect(motion.presentationAnimation(for: .pointer) != nil)
  #expect(motion.allowsSpatialMotion(for: .pointer))
}

@Test func programmaticPresentationUsesStateFeedbackWithoutSpatialMotion() {
  let motion = AppMotion(reduceMotion: false)

  #expect(motion.presentationAnimation(for: .programmatic) != nil)
  #expect(!motion.allowsSpatialMotion(for: .programmatic))
}
