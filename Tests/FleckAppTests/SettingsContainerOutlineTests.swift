import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test func settingsRestingContainersShareSemanticOutlineWithoutChangingFocus() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  for radius in [22, 12, 14, 10] {
    #expect(source.contains(".overlay { SettingsContainerOutline(cornerRadius: \(radius)) }"))
  }
  #expect(source.contains("theme.increasedContrast || colorSchemeContrast == .increased"))
  #expect(source.contains("? theme.color(.border) : Color(nsColor: .separatorColor)"))
}

@Test @MainActor
func settingsRestingContainerOutlinesRenderLightDarkAndIncreasedContrast() async throws {
  for family in [FleckColorTheme.monochrome, .capy] {
    for appearance in [FleckThemeAppearance.light, .dark] {
      var standardEdgeBrightness: CGFloat?
      for increasedContrast in [false, true] {
        let theme = FleckThemeSnapshot.resolve(
          colorTheme: family,
          mode: appearance == .dark ? .dark : .light,
          systemAppearance: appearance,
          reduceTransparency: true,
          increasedContrast: increasedContrast
        )
        let host = NSHostingView(
          rootView: HStack(spacing: 24) {
            SettingsSidebarSurface {
              Text("General")
              Text("Appearance")
            }
            .frame(width: 180, height: 280)
            VStack(alignment: .leading, spacing: 16) {
              SettingsSectionCard("Startup") {
                Text("Launch at login")
                Text("Start Fleck automatically.")
              }
              SettingsPreferenceRow("Appearance", detail: "Use the system appearance.") {
                Text("System")
              }
              TextField("Search settings", text: .constant(""))
                .fleckNeutralControlOutline(isFocused: true, cornerRadius: 6)
            }
            .frame(width: 360)
          }
          .padding(24)
          .foregroundStyle(theme.color(.textPrimary))
          .background(theme.color(.window))
          .environment(\.fleckThemeSnapshot, theme)
          .environment(\.colorScheme, theme.colorScheme)
          .environment(\.colorSchemeContrast, increasedContrast ? .increased : .standard)
          .environment(\._accessibilityReduceTransparency, true)
          .frame(width: 612, height: 340)
        )
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 612, height: 340),
          styleMask: [.borderless],
          backing: .buffered,
          defer: false
        )
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        window.contentView = host
        defer {
          window.contentView = nil
          window.orderOut(nil)
        }
        for _ in 0..<30 {
          host.layoutSubtreeIfNeeded()
          await Task.yield()
        }
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        let scaleX = CGFloat(image.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(image.pixelsHigh) / host.bounds.height
        let edge = try #require(
          image.colorAt(x: Int(24 * scaleX), y: Int(170 * scaleY))?
            .usingColorSpace(.sRGB)
        )
        let brightness = (edge.redComponent + edge.greenComponent + edge.blueComponent) / 3
        if increasedContrast {
          let standard = try #require(standardEdgeBrightness)
          #expect(abs(brightness - standard) > 0.08)
          #expect(appearance == .dark ? brightness > standard : brightness < standard)
        } else {
          standardEdgeBrightness = brightness
        }
        if let capturePath = ProcessInfo.processInfo.environment["FLECK_SETTINGS_OUTLINE_CAPTURE_DIR"] {
          let directory = URL(fileURLWithPath: capturePath, isDirectory: true)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let name = "settings-containers-\(family.rawValue)-\(appearance.rawValue)-\(increasedContrast ? "increased" : "standard").png"
          try #require(image.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name))
        }
      }
    }
  }
}
