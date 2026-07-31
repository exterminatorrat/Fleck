#if os(macOS)
  import FleckCore

  enum DictationModifierSettingsRecoveryAction: Equatable {
    case enableInputMonitoring
    case retry
  }

  struct DictationModifierSettingsPresentation: Equatable {
    struct Row: Equatable, Identifiable {
      let key: DictationModifierKey
      let title: String

      var id: DictationModifierKey { key }
    }

    let rows: [Row]
    let recommended: DictationModifierKey
    let statusCopy: String
    let isPickerEnabled: Bool
    let recoveryAction: DictationModifierSettingsRecoveryAction?
    let recoveryButtonTitle: String?
    let guidanceCopy: String?

    init(
      selected: DictationModifierKey,
      monitorStatus: ModifierMonitorState,
      canChange: Bool
    ) {
      rows = DictationModifierKey.allCases.map {
        .init(
          key: $0,
          title: $0 == .rightOption
            ? "\($0.displayName) — Recommended"
            : $0.displayName
        )
      }
      recommended = .rightOption
      isPickerEnabled = canChange
      recoveryAction = switch monitorStatus {
      case .unauthorized: .enableInputMonitoring
      case .failed: .retry
      case .stopped, .running: nil
      }
      if canChange {
        recoveryButtonTitle = switch recoveryAction {
        case .enableInputMonitoring: "Enable \(selected.displayName)"
        case .retry: "Retry \(selected.displayName)"
        case nil: nil
        }
      } else {
        recoveryButtonTitle = nil
      }

      let monitorCopy = switch monitorStatus {
      case .running:
        "Input Monitoring enabled"
      case .unauthorized:
        "Input Monitoring is required. Enable it to use the modifier key."
      case .failed:
        "Input Monitoring could not start. Retry to use the modifier key."
      case .stopped:
        "Input Monitoring is unavailable."
      }
      statusCopy = canChange
        ? monitorCopy
        : "\(monitorCopy) The modifier key cannot change until dictation finishes."

      guidanceCopy = switch selected {
      case .function:
        "Fn support is best-effort because some keyboards or system settings consume it first."
      case .leftCommand, .rightCommand, .leftOption, .leftControl, .rightControl:
        "Modifier-only shortcuts can conflict with ordinary use of this key."
      case .rightOption:
        nil
      }
    }
  }
#endif
