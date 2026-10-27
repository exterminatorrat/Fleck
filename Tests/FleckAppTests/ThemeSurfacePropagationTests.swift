#if os(macOS)
  import AppKit
  import FleckCore
  import Testing

  @testable import FleckApp

  @Suite("Theme surface propagation", .serialized)
  @MainActor
  struct ThemeSurfacePropagationTests {
    @Test func nativeWindowTracksPaletteOnAttachmentAndThemeChanges() {
      let applicationAppearance = NSApplication.shared.appearance
      let view = FleckWindowThemeView()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 480, height: 320),
        styleMask: [.titled], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      defer { window.contentView = nil; window.orderOut(nil) }
      let initial = snapshot(.monochrome, .dark)
      view.updateTheme(initial)
      window.backgroundColor = .purple
      window.appearance = NSAppearance(named: .aqua)
      window.contentView = view
      #expect(window.backgroundColor == initial.nsColor(.window))
      #expect(window.appearance?.name == .darkAqua)

      for family in FleckColorTheme.allCases {
        for appearance in [FleckThemeAppearance.light, .dark] {
          let theme = snapshot(family, appearance)
          view.updateTheme(theme)
          #expect(window.backgroundColor == theme.nsColor(.window))
          #expect(window.appearance?.name == (appearance == .dark ? .darkAqua : .aqua))
        }
      }
      for appearance in [FleckThemeAppearance.light, .dark] {
        view.updateTheme(.resolve(
          colorTheme: .monochrome, mode: appearance == .dark ? .dark : .light,
          systemAppearance: appearance, reduceTransparency: true, increasedContrast: true
        ))
        #expect(window.appearance?.name == (
          appearance == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
        ))
      }
      #expect(NSApplication.shared.appearance === applicationAppearance)
    }

    @Test func nativeGlassBackingTracksPaletteAndRestoresOpaquePolicyWithoutAThemeChange() {
      let view = FleckWindowThemeView()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 380, height: 300),
        styleMask: [.titled], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      defer { window.contentView = nil; window.orderOut(nil) }
      view.updateTheme(snapshot(.monochrome, .dark), usesOpaqueBackground: false)
      window.contentView = view
      #expect(window.backgroundColor == .clear && !window.isOpaque)
      for family in FleckColorTheme.allCases {
        for appearance in [FleckThemeAppearance.light, .dark] {
          let theme = snapshot(family, appearance)
          view.updateTheme(theme, usesOpaqueBackground: false)
          #expect(window.backgroundColor == .clear && !window.isOpaque)
          #expect(window.appearance?.name == (appearance == .dark ? .darkAqua : .aqua))
          view.updateTheme(theme, usesOpaqueBackground: true)
          #expect(window.backgroundColor == theme.nsColor(.window) && window.isOpaque)
          view.updateTheme(theme, usesOpaqueBackground: false)
          #expect(window.backgroundColor == .clear && !window.isOpaque)
        }
      }
    }

    private func snapshot(_ family: FleckColorTheme, _ appearance: FleckThemeAppearance) -> FleckThemeSnapshot {
      .resolve(
        colorTheme: family, mode: appearance == .dark ? .dark : .light,
        systemAppearance: appearance, reduceTransparency: false, increasedContrast: false
      )
    }
  }
#endif
