import Testing

@testable import FleckApp

@Test func reduceMotionRemovesMovementAndPressScaling() {
  let motion = AppMotion(reduceMotion: true)

  #expect(motion.pressScale == 1)
  #expect(motion.offset == 0)
}

@Test func standardMotionUsesRestrainedNativeValues() {
  let motion = AppMotion(reduceMotion: false)

  #expect(AppMotion.quickDuration == 0.10)
  #expect(AppMotion.standardDuration == 0.16)
  #expect(motion.pressScale == 0.97)
  #expect(motion.offset == 4)
}
