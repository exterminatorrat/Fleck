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
}
