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

@Test func parakeetRetentionUsesProcessorCapAndMemoryTiers() {
  let cases: [(UInt64, Int, Duration)] = [
    (8 * gib, 8, .seconds(15)),
    (64 * gib, 4, .seconds(5)),
    (16 * gib, 8, .seconds(30)),
    (24 * gib, 10, .seconds(120)),
    (32 * gib, 12, .seconds(300)),
  ]

  for (installedMemoryBytes, activeProcessorCount, expected) in cases {
    let profile = DictationResourceProfile(
      installedMemoryBytes: installedMemoryBytes,
      activeProcessorCount: activeProcessorCount
    )
    let snapshot = healthyResourceSnapshot(
      reclaimableMemoryBytes: installedMemoryBytes / 4 * 3
    )

    #expect(
      DictationRuntimePolicy.policy(memoryBytes: installedMemoryBytes)
        .parakeetRetention(profile: profile, snapshot: snapshot) == expected
    )
  }
}

@Test func parakeetRetentionCollapsesForPressureAndLowCapacity() {
  let profile = DictationResourceProfile(
    installedMemoryBytes: 24 * gib,
    activeProcessorCount: 10
  )

  for snapshot in [
    healthyResourceSnapshot(memoryPressure: .warning),
    healthyResourceSnapshot(memoryPressure: .critical),
    healthyResourceSnapshot(thermalPressure: .serious),
    healthyResourceSnapshot(thermalPressure: .critical),
    healthyResourceSnapshot(lowPowerMode: true),
    healthyResourceSnapshot(reclaimableMemoryBytes: 2 * gib),
    healthyResourceSnapshot(reclaimableMemoryBytes: 5 * gib),
    healthyResourceSnapshot(reclaimableMemoryBytes: 8 * gib),
  ] {
    let retention = DictationRuntimePolicy.policy(memoryBytes: profile.installedMemoryBytes)
      .parakeetRetention(profile: profile, snapshot: snapshot)

    if snapshot.reclaimableMemoryBytes == 8 * gib {
      #expect(retention == .seconds(5))
    } else {
      #expect(retention == .zero)
    }
  }

  let constrainedProfile = DictationResourceProfile(
    installedMemoryBytes: 8 * gib,
    activeProcessorCount: 8
  )
  #expect(
    DictationRuntimePolicy.policy(memoryBytes: constrainedProfile.installedMemoryBytes)
      .parakeetRetention(
        profile: constrainedProfile,
        snapshot: healthyResourceSnapshot(reclaimableMemoryBytes: 4 * gib)
      ) == .seconds(5)
  )

  #expect(
    DictationRuntimePolicy.policy(memoryBytes: profile.installedMemoryBytes)
      .parakeetRetention(
        profile: profile,
        snapshot: healthyResourceSnapshot(reclaimableMemoryBytes: nil)
      ) == .zero
  )
}

private let gib: UInt64 = 1_024 * 1_024 * 1_024

private func healthyResourceSnapshot(
  reclaimableMemoryBytes: UInt64? = 16 * gib,
  memoryPressure: DictationMemoryPressure = .normal,
  thermalPressure: DictationThermalPressure = .nominal,
  lowPowerMode: Bool = false
) -> DictationResourceSnapshot {
  DictationResourceSnapshot(
    reclaimableMemoryBytes: reclaimableMemoryBytes,
    memoryPressure: memoryPressure,
    thermalPressure: thermalPressure,
    lowPowerMode: lowPowerMode
  )
}
