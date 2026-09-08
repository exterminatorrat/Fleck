#if os(macOS)
  import FleckCore

  enum DictationModifierSettingsRecoveryAction: Equatable {
    case enableInputMonitoring
    case retry
  }

  enum DictationShortcutHelpMode: Equatable {
    case readyTutorial
    case recovery
    case activeDestination

    var canDismissGuide: Bool {
      self == .readyTutorial
    }

    static func resolve(
      isReady: Bool,
      isCaptureActive: Bool,
      showsGuide: Bool
    ) -> Self? {
      if isCaptureActive { return .activeDestination }
      if !isReady { return .recovery }
      return showsGuide ? .readyTutorial : nil
    }
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
    let isReady: Bool
    let isPickerEnabled: Bool
    let recoveryAction: DictationModifierSettingsRecoveryAction?
    let recoveryButtonTitle: String?
    let guidanceCopy: String?
    let detailCopy: String?
    let capsuleAccessibilityLabel: String

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
      isReady = monitorStatus == .running
      isPickerEnabled = canChange
      recoveryAction = switch monitorStatus {
      case .unauthorized: .enableInputMonitoring
      case .failed: .retry
      case .stopped, .running: nil
      }
      if canChange {
        recoveryButtonTitle = switch recoveryAction {
        case .enableInputMonitoring: "Open Input Monitoring"
        case .retry: "Retry"
        case nil: nil
        }
      } else {
        recoveryButtonTitle = nil
      }

      let monitorCopy = switch monitorStatus {
      case .running:
        "Hold \(selected.displayName) to dictate."
      case .unauthorized:
        "Enable Input Monitoring to use \(selected.displayName)."
      case .failed:
        "\(selected.displayName) shortcut could not start."
      case .stopped:
        "\(selected.displayName) shortcut is unavailable."
      }
      statusCopy = canChange
        ? monitorCopy
        : "\(monitorCopy) The key cannot change until dictation finishes."

      detailCopy = switch monitorStatus {
      case .running:
        "Double-tap for hands-free."
      case .unauthorized:
        "Turn on Fleck, then return here."
      case .failed, .stopped:
        nil
      }
      capsuleAccessibilityLabel = switch monitorStatus {
      case .running:
        "Fleck dictation ready. \(monitorCopy) Double-tap for hands-free."
      case .unauthorized:
        "Fleck global shortcut unavailable. \(monitorCopy) Turn on Fleck, then return here."
      case .failed, .stopped:
        "Fleck global shortcut unavailable. \(monitorCopy)"
      }

      guidanceCopy = if monitorStatus == .unauthorized {
        detailCopy
      } else {
        switch selected {
        case .function:
          "Fn support is best-effort because some keyboards or system settings consume it first."
        case .leftCommand, .rightCommand, .leftOption, .leftControl, .rightControl:
          "Modifier-only shortcuts can conflict with ordinary use of this key."
        case .rightOption:
          nil
        }
      }
    }
  }
#endif
