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

  private struct FleckNeutralControlOutline: ViewModifier {
    @Environment(\.fleckThemeSnapshot) private var theme
    let isFocused: Bool
    let cornerRadius: CGFloat
    let idleOpacity: Double

    func body(content: Content) -> some View {
      let isHighContrast = theme.increasedContrast
      return content.overlay {
        if isFocused {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
              Color.primary.opacity(isHighContrast ? 1 : 0.72),
              lineWidth: isHighContrast ? 2 : 1.5
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if idleOpacity > 0 {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
              Color.primary.opacity(
                isHighContrast ? max(idleOpacity, 0.4) : idleOpacity
              ),
              lineWidth: 1
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
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

  struct FleckWindowTheme: NSViewRepresentable {
    @Environment(\.fleckThemeSnapshot) private var theme
    var usesOpaqueBackground = true

    func makeNSView(context: Context) -> FleckWindowThemeView {
      let view = FleckWindowThemeView()
      view.setAccessibilityElement(false)
      view.updateTheme(theme, usesOpaqueBackground: usesOpaqueBackground)
      return view
    }

    func updateNSView(_ view: FleckWindowThemeView, context: Context) {
      view.updateTheme(theme, usesOpaqueBackground: usesOpaqueBackground)
    }
  }

  final class FleckWindowThemeView: NSView {
    private var theme: FleckThemeSnapshot?
    private var usesOpaqueBackground = true

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func updateTheme(_ theme: FleckThemeSnapshot, usesOpaqueBackground: Bool = true) {
      guard self.theme != theme || self.usesOpaqueBackground != usesOpaqueBackground else { return }
      self.theme = theme
      self.usesOpaqueBackground = usesOpaqueBackground
      applyWindowTheme()
    }

    private func applyWindowTheme() {
      guard let theme, let window else { return }
      let appearanceName: NSAppearance.Name = theme.appearance == .dark ? .darkAqua : .aqua
      if window.appearance?.name != appearanceName {
        window.appearance = NSAppearance(named: appearanceName)
      }
      let color = usesOpaqueBackground ? theme.nsColor(.window) : .clear
      if window.backgroundColor != color {
        window.backgroundColor = color
      }
      if window.isOpaque != usesOpaqueBackground {
        window.isOpaque = usesOpaqueBackground
      }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      applyWindowTheme()
    }
  }

  private struct FleckThemedSurface: ViewModifier {
    @Environment(\.fleckThemeSnapshot) private var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
      content.background(
        theme.color(.card),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    }
  }

  struct FleckQuietButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
      FleckQuietButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
  }

  private struct FleckQuietButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.fleckThemeSnapshot) private var theme
    @State private var isHovered = false
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    var body: some View {
      let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      configuration.label
        .contentShape(Rectangle())
        .background {
          shape.fill(
            isEnabled && (isHovered || configuration.isPressed)
              ? Color.primary.opacity(theme.increasedContrast ? 0.18 : configuration.isPressed ? 0.12 : 0.08)
              : Color.clear
          )
        }
        .onHover { isHovered = $0 }
    }
  }

  extension View {
    func fleckThemedSurface(cornerRadius: CGFloat) -> some View {
      modifier(FleckThemedSurface(cornerRadius: cornerRadius))
    }

    func fleckPopoverTheme(_ theme: FleckThemeSnapshot) -> some View {
      environment(\.fleckThemeSnapshot, theme)
        .environment(\.colorScheme, theme.colorScheme)
        .foregroundStyle(theme.color(.textPrimary))
        .tint(theme.color(.accent))
        .presentationBackground(theme.color(.card))
        .background(theme.color(.card))
    }

    func fleckNeutralControlOutline(
      isFocused: Bool,
      cornerRadius: CGFloat,
      idleOpacity: Double = 0
    ) -> some View {
      modifier(
        FleckNeutralControlOutline(
          isFocused: isFocused,
          cornerRadius: cornerRadius,
          idleOpacity: idleOpacity
        )
      )
    }

    func fleckTheme(_ appState: AppState) -> some View {
      environment(\.fleckThemeSnapshot, appState.themeSnapshot)
        .fleckUIFontFamily(appState.preferences.uiFontFamily)
        .environment(\.colorScheme, appState.themeSnapshot.colorScheme)
        .tint(appState.themeSnapshot.color(.accent))
        .animation(nil, value: appState.themeSnapshot.revision)
        .background(FleckThemeAppearanceObserver(appState: appState).frame(width: 0, height: 0))
    }
  }
#endif
