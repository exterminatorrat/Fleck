#if os(macOS)
  import SwiftUI

  struct AppMotion {
    static let quickDuration = 0.10
    static let standardDuration = 0.16

    let reduceMotion: Bool

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
  }
#endif
