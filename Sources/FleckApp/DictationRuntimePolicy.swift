import Foundation

enum DictationRuntimeResidency: Equatable, Sendable {
  case active
  case warm
  case standby
  case cold
}

struct DictationRuntimePolicy: Equatable, Sendable {
  let warmDuration: Duration
  let standbyDuration: Duration

  func parakeetRetention(
    profile: DictationResourceProfile,
    snapshot: DictationResourceSnapshot
  ) -> Duration {
    let fixedMaximum = fixedParakeetMaximum(for: profile)
    guard snapshot.memoryPressure == .normal,
          snapshot.thermalPressure != .serious,
          snapshot.thermalPressure != .critical,
          !snapshot.lowPowerMode,
          let reclaimableMemoryBytes = snapshot.reclaimableMemoryBytes
    else {
      return .zero
    }

    let threeGiB: UInt64 = 3 * 1_024 * 1_024 * 1_024
    let fiveGiB: UInt64 = 5 * 1_024 * 1_024 * 1_024
    if reclaimableMemoryBytes < threeGiB
      || isBelowInstalledPercentage(
        reclaimableMemoryBytes,
        installedMemoryBytes: profile.installedMemoryBytes,
        percentage: 25
      ) {
      return .zero
    }

    if reclaimableMemoryBytes < fiveGiB
      || isBelowInstalledPercentage(
        reclaimableMemoryBytes,
        installedMemoryBytes: profile.installedMemoryBytes,
        percentage: 40
      ) {
      return fixedMaximum > .seconds(5) ? .seconds(5) : fixedMaximum
    }

    return fixedMaximum
  }

  static func policy(memoryBytes: UInt64) -> Self {
    let extended = memoryBytes >= 24 * 1_024 * 1_024 * 1_024
    return Self(
      warmDuration: extended ? .seconds(300) : .seconds(120),
      standbyDuration: extended ? .seconds(1_800) : .seconds(600)
    )
  }

  func targetState(
    after signal: DictationRuntimeSignal,
    activeLease: Bool
  ) -> DictationRuntimeResidency {
    if activeLease { return .active }
    switch signal {
    case .memoryWarning:
      return .standby
    case .memoryCritical, .thermalCritical, .willSleep, .modelMutationWillBegin:
      return .cold
    case .thermalSerious, .lowPowerMode(true):
      return .standby
    case .lowPowerMode(false), .didWake:
      return .cold
    }
  }

  private func fixedParakeetMaximum(
    for profile: DictationResourceProfile
  ) -> Duration {
    guard profile.activeProcessorCount > 4 else { return .seconds(5) }

    let eightGiB: UInt64 = 8 * 1_024 * 1_024 * 1_024
    let twentyFourGiB: UInt64 = 24 * 1_024 * 1_024 * 1_024
    let thirtyTwoGiB: UInt64 = 32 * 1_024 * 1_024 * 1_024

    if profile.installedMemoryBytes <= eightGiB {
      return .seconds(15)
    }
    if profile.installedMemoryBytes < twentyFourGiB {
      return .seconds(30)
    }
    if profile.installedMemoryBytes < thirtyTwoGiB {
      return .seconds(120)
    }
    return .seconds(300)
  }

  private func isBelowInstalledPercentage(
    _ reclaimableMemoryBytes: UInt64,
    installedMemoryBytes: UInt64,
    percentage: UInt64
  ) -> Bool {
    let (whole, remainder) = installedMemoryBytes.quotientAndRemainder(dividingBy: 100)
    let (scaledWhole, wholeOverflow) = whole.multipliedReportingOverflow(by: percentage)
    let (scaledRemainder, remainderOverflow) = remainder.multipliedReportingOverflow(by: percentage)
    guard !wholeOverflow, !remainderOverflow else { return true }

    let (roundedNumerator, roundingOverflow) = scaledRemainder.addingReportingOverflow(99)
    guard !roundingOverflow else { return true }
    let roundedRemainder = roundedNumerator / 100
    let (threshold, thresholdOverflow) = scaledWhole.addingReportingOverflow(roundedRemainder)
    return thresholdOverflow || reclaimableMemoryBytes < threshold
  }
}
