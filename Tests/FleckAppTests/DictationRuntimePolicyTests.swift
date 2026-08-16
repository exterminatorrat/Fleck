import Foundation
import Testing

@testable import FleckApp

@Test func policyReachesColdAfterCriticalMemory() {
  let policy = DictationRuntimePolicy.policy(
    memoryBytes: 16 * 1_024 * 1_024 * 1_024
  )

  #expect(policy.targetState(
    after: .memoryCritical,
    activeLease: false
  ) == .cold)
}

@Test func policyUsesShortAndExtendedRetentionByMemoryClass() {
  let short = DictationRuntimePolicy.policy(
    memoryBytes: 16 * 1_024 * 1_024 * 1_024
  )
  let extended = DictationRuntimePolicy.policy(
    memoryBytes: 24 * 1_024 * 1_024 * 1_024
  )

  #expect(short.warmDuration == .seconds(120))
  #expect(short.standbyDuration == .seconds(600))
  #expect(extended.warmDuration == .seconds(300))
  #expect(extended.standbyDuration == .seconds(1_800))
}

@Test func activeLeaseDefersEveryRuntimeSignal() {
  let policy = DictationRuntimePolicy.policy(
    memoryBytes: 16 * 1_024 * 1_024 * 1_024
  )
  let signals: [DictationRuntimeSignal] = [
    .memoryWarning,
    .memoryCritical,
    .thermalSerious,
    .thermalCritical,
    .lowPowerMode(true),
    .lowPowerMode(false),
    .willSleep,
    .didWake,
    .modelMutationWillBegin,
  ]

  for signal in signals {
    #expect(policy.targetState(after: signal, activeLease: true) == .active)
  }
}

@Test func idlePressureAndReleaseSignalsChooseStandbyOrCold() {
  let policy = DictationRuntimePolicy.policy(
    memoryBytes: 16 * 1_024 * 1_024 * 1_024
  )

  for signal in [
    DictationRuntimeSignal.memoryWarning,
    .thermalSerious,
    .lowPowerMode(true),
  ] {
    #expect(policy.targetState(after: signal, activeLease: false) == .standby)
  }

  for signal in [
    DictationRuntimeSignal.memoryCritical,
    .thermalCritical,
    .lowPowerMode(false),
    .willSleep,
    .didWake,
    .modelMutationWillBegin,
  ] {
    #expect(policy.targetState(after: signal, activeLease: false) == .cold)
  }
}
