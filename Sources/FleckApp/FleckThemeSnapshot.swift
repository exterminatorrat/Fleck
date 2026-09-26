#if os(macOS)
  import AppKit
  import Combine
  import FleckCore
  import SwiftUI

  struct FleckThemeSnapshot: Equatable {
    static let initial = resolve(
      colorTheme: .monochrome,
      mode: .system,
      systemAppearance: .light,
      reduceTransparency: false,
      increasedContrast: false
    )

    let revision: UInt64
    let colorTheme: FleckColorTheme
    let mode: AppTheme
    let appearance: FleckThemeAppearance
    let palette: FleckThemePalette
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var colorScheme: ColorScheme {
      appearance == .dark ? .dark : .light
    }

    func color(_ role: FleckThemeColor) -> Color {
      Color(nsColor: nsColor(role))
    }

    func nsColor(_ role: FleckThemeColor) -> NSColor {
      NSColor(hex: palette[role])!
    }

    static func resolve(
      colorTheme: FleckColorTheme,
      mode: AppTheme,
      systemAppearance: FleckThemeAppearance,
      reduceTransparency: Bool,
      increasedContrast: Bool,
      revision: UInt64 = 0
    ) -> Self {
      let appearance: FleckThemeAppearance
      switch mode {
      case .system:
        appearance = systemAppearance
      case .light:
        appearance = .light
      case .dark:
        appearance = .dark
      }
      return Self(
        revision: revision,
        colorTheme: colorTheme,
        mode: mode,
        appearance: appearance,
        palette: FleckThemePalette.resolve(family: colorTheme, appearance: appearance),
        reduceTransparency: reduceTransparency,
        increasedContrast: increasedContrast
      )
    }
  }

  private struct FleckThemeSnapshotEnvironmentKey: EnvironmentKey {
    static let defaultValue = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .system,
      systemAppearance: .light,
      reduceTransparency: false,
      increasedContrast: false
    )
  }

  extension EnvironmentValues {
    var fleckThemeSnapshot: FleckThemeSnapshot {
      get { self[FleckThemeSnapshotEnvironmentKey.self] }
      set { self[FleckThemeSnapshotEnvironmentKey.self] = newValue }
    }
  }

  @MainActor
  final class FleckThemeSystemObserver {
    private let didChange: @MainActor () -> Void
    private var appearanceObservation: NSKeyValueObservation?
    private var accessibilityObservation: AnyCancellable?

    init(didChange: @escaping @MainActor () -> Void) {
      self.didChange = didChange
      appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) {
        [weak self] _, _ in
        Task { @MainActor [weak self] in
          self?.didChange()
        }
      }
      accessibilityObservation = NSWorkspace.shared.notificationCenter
        .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        .sink { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.didChange()
          }
        }
    }
  }

  @MainActor
  struct FleckThemeAppearanceObserver: NSViewRepresentable {
    @ObservedObject var appState: AppState

    func makeNSView(context: Context) -> FleckThemeAppearanceObservationView {
      let view = FleckThemeAppearanceObservationView()
      view.onAppearanceChange = { [weak appState] in
        appState?.refreshThemeSnapshot()
      }
      view.requestThemeSnapshotRefresh()
      return view
    }

    func updateNSView(_ view: FleckThemeAppearanceObservationView, context: Context) {
      view.onAppearanceChange = { [weak appState] in
        appState?.refreshThemeSnapshot()
      }
    }
  }

  @MainActor
  final class FleckThemeAppearanceObservationView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      requestThemeSnapshotRefresh()
    }

    override func viewDidChangeEffectiveAppearance() {
      super.viewDidChangeEffectiveAppearance()
      requestThemeSnapshotRefresh()
    }

    func requestThemeSnapshotRefresh() {
      onAppearanceChange?()
    }
  }

  extension View {
    func fleckTheme(_ appState: AppState) -> some View {
      environment(\.fleckThemeSnapshot, appState.themeSnapshot)
        .environment(\.colorScheme, appState.themeSnapshot.colorScheme)
        .tint(appState.themeSnapshot.color(.accent))
        .animation(nil, value: appState.themeSnapshot.revision)
        .background(FleckThemeAppearanceObserver(appState: appState).frame(width: 0, height: 0))
    }
  }
#endif
