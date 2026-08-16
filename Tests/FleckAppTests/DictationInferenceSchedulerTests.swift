import Testing

@testable import FleckApp

@Test func liveASRPreemptsCleanupButCleanupCannotPreemptLiveASR() {
  let scheduler = DictationInferenceScheduler()

  #expect(scheduler.canStart(.liveASR, while: .cleanup))
  #expect(!scheduler.canStart(.cleanup, while: .liveASR))
}

@Test func inferencePriorityOrdersByRawValue() {
  #expect(DictationInferencePriority.optionalPolish < .cleanup)
  #expect(DictationInferencePriority.finalASR < .liveASR)
}

@Test func schedulerAllowsIdleOrEqualPriorityAndRejectsPreemptionByLowerPriority() {
  let scheduler = DictationInferenceScheduler()

  #expect(scheduler.canStart(.cleanup, while: nil))
  #expect(scheduler.canStart(.cleanup, while: .cleanup))
  #expect(scheduler.canStart(.liveASR, while: .finalASR))
  #expect(!scheduler.canStart(.optionalPolish, while: .cleanup))
}
