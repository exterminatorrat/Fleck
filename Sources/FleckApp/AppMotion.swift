#if os(macOS)
  import SwiftUI

  enum AppInteractionSource: Equatable {
    case pointer
    case keyboard
    case programmatic
  }

  struct AppMotion {
    static let pressDuration = 0.10
    static let stateDuration = 0.12
    static let selectionDuration = 0.16
    static let revealDuration = 0.18
    static let surfaceDuration = 0.22
    static let rareDuration = 0.26

    static let quickDuration = pressDuration
    static let standardDuration = selectionDuration

    let reduceMotion: Bool

    var press: Animation {
      .easeOut(duration: Self.pressDuration)
    }

    var state: Animation {
      .easeOut(duration: Self.stateDuration)
    }

    var selection: Animation {
      .easeInOut(duration: Self.selectionDuration)
    }

    var reveal: Animation {
      .easeOut(duration: Self.revealDuration)
    }

    var surface: Animation {
      .easeOut(duration: Self.surfaceDuration)
    }

    var rare: Animation {
      .easeOut(duration: Self.rareDuration)
    }

    var quick: Animation {
      .easeOut(duration: Self.quickDuration)
    }

    var standard: Animation {
      .easeOut(duration: Self.standardDuration)
    }

    var spatial: Animation? {
      reduceMotion ? nil : standard
    }

    var pressScale: CGFloat {
      reduceMotion ? 1 : 0.97
    }

    var offset: CGFloat {
      reduceMotion ? 0 : 4
    }

    func allowsSpatialMotion(for source: AppInteractionSource) -> Bool {
      !reduceMotion && source == .pointer
    }

    func presentationAnimation(for source: AppInteractionSource) -> Animation? {
      switch source {
      case .keyboard:
        return nil
      case .programmatic:
        return state
      case .pointer:
        return reduceMotion ? state : surface
      }
    }
  }
#endif
