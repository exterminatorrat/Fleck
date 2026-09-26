#if os(macOS)
  import SwiftUI

  @testable import FleckApp

  @MainActor
  struct FleckThemeTestRoot<Content: View>: View {
    @ObservedObject private var state: AppState
    private let content: Content

    init(state: AppState, @ViewBuilder content: () -> Content) {
      _state = ObservedObject(wrappedValue: state)
      self.content = content()
    }

    var body: some View {
      content.environmentObject(state).fleckTheme(state)
    }
  }
#endif
