import Foundation
import AppKit
import Combine
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test func settingsSceneReceivesTheSharedPaletteSnapshot() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let appSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  let settingsSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let settingsScene = try #require(
    appSource.components(separatedBy: "      Settings {").last?
      .components(separatedBy: "      .defaultSize(width: 840, height: 600)").first
  )

  #expect(settingsScene.contains(".fleckTheme(appState)"))
  #expect(!settingsScene.contains(".preferredColorScheme"))
  #expect(settingsSource.contains("theme.color(.window)"))
  #expect(settingsSource.contains("theme.color(.sidebar)"))
  #expect(settingsSource.contains("theme.color(.card)"))
  #expect(settingsSource.contains("theme.color(.raised)"))
  #expect(settingsSource.contains("theme.color(.border)"))
  #expect(settingsSource.contains("theme.color(.accent)"))
  #expect(settingsSource.contains(".background(theme.color(.window))"))
  #expect(settingsSource.contains("SettingsSidebarSurface(glassOpacity: appState.preferences.panelOpacity)"))
}

@Test func nativeSceneRootsAndCapsuleUseTheCurrentThemeSnapshot() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let appSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  let observerSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckThemeSnapshot.swift"),
    encoding: .utf8
  )
  let appStateSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/AppState.swift"),
    encoding: .utf8
  )

  #expect(appSource.components(separatedBy: ".fleckTheme(appState)").count - 1 == 3)
  #expect(appSource.contains("DictationCapsuleController(theme: appState.themeSnapshot)"))
  #expect(appSource.contains("themeSnapshotSubscription = appState.$themeSnapshot.sink"))
  #expect(appSource.contains("capsuleController?.updateTheme(snapshot)"))
  #expect(observerSource.contains("appState?.refreshThemeSnapshot()"))
  #expect(!observerSource.contains("window?.effectiveAppearance"))
  #expect(!observerSource.contains("reportAppearance()"))
  #expect(appStateSource.contains("func refreshThemeSnapshot()"))
  #expect(appStateSource.contains("NSApplication.shared.effectiveAppearance"))
  #expect(!appStateSource.contains("effectiveAppearance: NSAppearance"))
  #expect(observerSource.contains("viewDidChangeEffectiveAppearance()"))
  #expect(observerSource.contains("environment(\\.fleckThemeSnapshot, appState.themeSnapshot)"))
}

@Test func globalColorControlsAreRemovedAndPerNoteTabColorRemains() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let searchSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsSearch.swift"),
    encoding: .utf8
  )
  let notesSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )

  #expect(!settingsSource.contains("Accent color"))
  #expect(!settingsSource.contains("Editor text color"))
  #expect(!settingsSource.contains("Editor background"))
  #expect(!searchSource.contains("appearanceAccent"))
  #expect(!searchSource.contains("appearanceEditorText"))
  #expect(!searchSource.contains("appearanceEditorBackground"))
  #expect(notesSource.contains("tabColorPicker(noteID:"))
  #expect(notesSource.contains("appState.setSelectedTabColor(hex)"))
}

@Test func settingsSidebarKeepsAccessibilityAwareChromeFallbacks() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let sidebar = try #require(
    settingsSource.components(separatedBy: "struct SettingsSidebarSurface<Content: View>").last?
      .components(separatedBy: "private struct SettingsSidebarSurfaceProbe").first
  )

  #expect(sidebar.contains("@Environment(\\.accessibilityReduceTransparency)"))
  #expect(sidebar.contains("@Environment(\\.colorSchemeContrast)"))
  #expect(sidebar.contains("FleckChromeMaterialPolicy.current("))
  #expect(sidebar.contains("increasedContrast: colorSchemeContrast == .increased"))
  #expect(sidebar.contains("opacity(glassOpacity)"))
}

@Test func settingsFocusAndGlassOpacityControlUseNeutralAccessibleOutlines() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let themeSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckThemeSnapshot.swift"),
    encoding: .utf8
  )
  let sortOption = try #require(
    settingsSource.components(separatedBy: "private func sortOption(").last?
      .components(separatedBy: "private var sortControl").first
  )
  let opacitySlider = settingsSource.components(separatedBy: "struct SettingsGlassOpacitySlider: View").last ?? ""
  let opacitySliderControl = opacitySlider.components(separatedBy: ".overlay {").first ?? ""

  #expect(sortOption.contains(".focusEffectDisabled()"))
  #expect(sortOption.contains(
    ".fleckNeutralControlOutline(isFocused: isFocused, cornerRadius: 7)"
  ))
  #expect(!sortOption.contains("theme.color(.focusRing)"))
  #expect(settingsSource.contains("SettingsGlassOpacitySlider(value: preferenceBinding(\\.panelOpacity))"))
  #expect(themeSource.contains("private struct FleckNeutralControlOutline: ViewModifier"))
  #expect(themeSource.contains("@Environment(\\.fleckThemeSnapshot) private var theme"))
  #expect(themeSource.contains("Color.primary.opacity(isHighContrast ? 1 : 0.72)"))
  #expect(themeSource.contains("lineWidth: isHighContrast ? 2 : 1.5"))
  #expect(opacitySlider.contains("Slider(value: $value, in: 0.55...1)"))
  #expect(opacitySlider.contains(".focusEffectDisabled()"))
  #expect(opacitySlider.contains("@Environment(\\.layoutDirection) private var layoutDirection"))
  #expect(opacitySlider.contains("SettingsGlassOpacitySliderMetrics.resolve("))
  #expect(!opacitySliderControl.contains(".environment(\\.layoutDirection, .leftToRight)"))
  #expect(opacitySlider.contains(".environment(\\.layoutDirection, .leftToRight)"))
  #expect(opacitySlider.contains(".accessibilityLabel(\"Glass opacity\")"))
  #expect(opacitySlider.contains(".accessibilityValue("))
  #expect(opacitySlider.contains("Capsule()"))
  #expect(opacitySlider.contains("Circle()"))
}

@Test func settingsGlassOpacitySliderMetricsMirrorNonMidpointFillAndThumb() {
  let value = 0.7
  let width: CGFloat = 150
  let trackInset: CGFloat = 8
  let leftToRight = SettingsGlassOpacitySliderMetrics.resolve(
    value: value,
    width: width,
    trackInset: trackInset,
    layoutDirection: .leftToRight
  )
  let rightToLeft = SettingsGlassOpacitySliderMetrics.resolve(
    value: value,
    width: width,
    trackInset: trackInset,
    layoutDirection: .rightToLeft
  )

  #expect(leftToRight.thumbX < width / 2)
  #expect(rightToLeft.thumbX > width / 2)
  #expect(abs(leftToRight.thumbX + rightToLeft.thumbX - width) < 0.001)
  #expect(abs(leftToRight.thumbX - (leftToRight.filledTrackMinX + leftToRight.filledTrackWidth)) < 0.001)
  #expect(abs(rightToLeft.thumbX - rightToLeft.filledTrackMinX) < 0.001)
  #expect(leftToRight.filledTrackMinX == trackInset)
  #expect(abs(rightToLeft.filledTrackMinX + rightToLeft.filledTrackWidth - (width - trackInset)) < 0.001)
  #expect(leftToRight.filledTrackWidth == rightToLeft.filledTrackWidth)
}

@Test func systemAndExplicitAppearanceResolveIndependentlyFromColorTheme() {
  let light = FleckThemeSnapshot.resolve(
    colorTheme: .oled,
    mode: .system,
    systemAppearance: .light,
    reduceTransparency: false,
    increasedContrast: false
  )
  let dark = FleckThemeSnapshot.resolve(
    colorTheme: .oled,
    mode: .system,
    systemAppearance: .dark,
    reduceTransparency: false,
    increasedContrast: false
  )
  let fixedLight = FleckThemeSnapshot.resolve(
    colorTheme: .oled,
    mode: .light,
    systemAppearance: .dark,
    reduceTransparency: false,
    increasedContrast: false
  )
  let fixedDark = FleckThemeSnapshot.resolve(
    colorTheme: .oled,
    mode: .dark,
    systemAppearance: .light,
    reduceTransparency: true,
    increasedContrast: true
  )

  #expect(light.appearance == .light)
  #expect(dark.appearance == .dark)
  #expect(light.palette[.window] == "#FFFFFF")
  #expect(dark.palette[.window] == "#000000")
  #expect(fixedLight.appearance == .light)
  #expect(fixedDark.appearance == .dark)
  #expect(fixedDark.reduceTransparency)
  #expect(fixedDark.increasedContrast)
}

@Test @MainActor
func staleLightWindowAppearanceCannotReplaceSystemDarkSnapshot() async throws {
  let application = NSApplication.shared
  let previousApplicationAppearance = application.appearance
  defer { application.appearance = previousApplicationAppearance }
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("system-theme-window-authority-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updatePreferences { $0.theme = .system }
  application.appearance = NSAppearance(named: .aqua)
  state.refreshThemeSnapshot()
  #expect(state.themeSnapshot.appearance == .light)

  var publishedSnapshots = 0
  let snapshotObservation = state.$themeSnapshot.dropFirst().sink { _ in
    publishedSnapshots += 1
  }
  application.appearance = NSAppearance(named: .darkAqua)
  state.refreshThemeSnapshot()
  #expect(state.themeSnapshot.appearance == .dark)
  #expect(publishedSnapshots == 1)

  let host = NSHostingView(
    rootView: FleckThemeTestRoot(state: state) { Color.clear }
      .frame(width: 120, height: 80)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.appearance = NSAppearance(named: .aqua)
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  for _ in 0..<40 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }

  #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
  #expect(state.themeSnapshot.appearance == .dark)
  #expect(publishedSnapshots == 1)
  snapshotObservation.cancel()
  window.contentView = nil
  window.orderOut(nil)
}

@Test func nativeErrorAndAgentScrollColorsUseThemeRoles() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let sources = try [
    "Sources/FleckApp/FleckColorPicker.swift",
    "Sources/FleckApp/EditorWebLink.swift",
    "Sources/FleckApp/TrashView.swift",
    "Sources/FleckApp/AgentActivityView.swift",
    "Sources/FleckApp/NativeRichTextEditor.swift",
  ].map {
    try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8)
  }

  #expect(!sources[0].contains(".foregroundStyle(.red)"))
  #expect(sources[1].contains(".foregroundStyle(theme.color(.error))"))
  #expect(!sources[1].contains(".foregroundStyle(.red)"))
  #expect(sources[2].contains(".foregroundStyle(theme.color(.error))"))
  #expect(!sources[2].contains(".foregroundStyle(.red)"))
  #expect(sources[3].contains("theme.nsColor(.textSecondary)"))
  #expect(sources[4].contains("theme.nsColor(.warning)"))
  #expect(!sources[4].contains(".systemOrange"))
}

@Test func secondaryAndCaptionLabelsUseThemeRolesInScopedComponents() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let notesSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let agentActivitySource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/AgentActivityView.swift"),
    encoding: .utf8
  )
  let agentIndicatorSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/AgentActivityIndicator.swift"),
    encoding: .utf8
  )
  func component(_ source: String, from start: String, until end: String) throws -> String {
    let startRange = try #require(source.range(of: start))
    let content = source[startRange.lowerBound...]
    let endRange = try #require(content.range(of: end))
    return String(content[..<endRange.lowerBound])
  }

  let settingsHeader = try component(
    settingsSource,
    from: "struct SettingsPageHeader: View",
    until: "struct SettingsSectionCard"
  )
  let settingsRow = try component(
    settingsSource,
    from: "struct SettingsPreferenceRow<Accessory: View>",
    until: "private enum SettingsToggleRowStyle"
  )
  let settingsToggle = try component(
    settingsSource,
    from: "private struct SettingsToggleRow: View",
    until: "struct SettingsView: View"
  )
  let dictionaryEmptyState = try component(
    settingsSource,
    from: "private var emptyState: some View {",
    until: "private func entryRow("
  )
  let notesHelpRow = try component(
    notesSource,
    from: "struct DictationShortcutHelpRow: View",
    until: "private struct FormattingBar"
  )
  let saveFeedback = try component(
    notesSource,
    from: "private struct SaveFeedbackView: View",
    until: "struct FluidTabReorder"
  )
  let activityRow = try component(
    agentActivitySource,
    from: "private func activityRow(",
    until: "private func patch("
  )
  let activityPatch = try component(
    agentActivitySource,
    from: "private func patch(",
    until: "\n  }\n#endif"
  )

  #expect(settingsHeader.contains("theme.color(.textSecondary)"))
  #expect(settingsRow.contains("theme.color(.caption)"))
  #expect(settingsToggle.contains("theme.color(.textSecondary)"))
  #expect(dictionaryEmptyState.contains("theme.color(.textSecondary)"))
  #expect(!dictionaryEmptyState.contains("foregroundStyle(.secondary)"))
  #expect(dictionaryEmptyState.contains("theme.color(.textSecondary)"))
  #expect(!dictionaryEmptyState.contains("foregroundStyle(.secondary)"))
  #expect(notesHelpRow.contains("theme.color(.caption)"))
  #expect(notesHelpRow.contains("theme.color(.textSecondary)"))
  #expect(saveFeedback.contains("theme.color(.caption)"))
  #expect(activityRow.contains("theme.color(.textSecondary)"))
  #expect(activityRow.contains("theme.color(.caption)"))
  #expect(activityPatch.contains("theme.color(.caption)"))
  #expect(agentIndicatorSource.contains("Text(\"MCP\")"))
  #expect(agentIndicatorSource.contains("theme.color(.caption)"))
}

@Test @MainActor
func settingsContentKeepsOpaquePaletteSurfacesUnderGlassAndAccessibilityOverrides()
  async throws
{
  let application = NSApplication.shared
  let previousApplicationAppearance = application.appearance
  defer { application.appearance = previousApplicationAppearance }

  for palette in [FleckColorTheme.capy, .absolutely] {
    for (mode, appearance, windowAppearance) in [
      (AppTheme.light, FleckThemeAppearance.light, NSAppearance.Name.aqua),
      (AppTheme.dark, FleckThemeAppearance.dark, NSAppearance.Name.darkAqua),
    ] {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-glass-surface-" + UUID().uuidString, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
      await state.waitUntilInitialLoad()
      state.updatePreferences {
        $0.colorTheme = palette
        $0.theme = mode
        $0.chromeAppearance = .glass
      }
      let theme = state.themeSnapshot
      #expect(theme.appearance == appearance)

      let backdrop: NSColor = mode == .light ? .black : .white
      let host = NSHostingView(
        rootView: FleckThemeTestRoot(state: state) {
          ZStack {
            Color(nsColor: backdrop)
            VStack(spacing: 12) {
              SettingsSectionCard("Palette card") {
                Text("Card content").frame(height: 32)
              }
              SettingsPreferenceRow(
                "Raised preference",
                detail: "The raised content surface stays fully opaque under Glass."
              ) {
                Text("Value")
              }
            }
            .environment(\.fleckChromeAppearance, .glass)
            .padding(18)
          }
          .frame(width: 360, height: 220)
        }
      )
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.appearance = NSAppearance(named: windowAppearance)
      window.backgroundColor = backdrop
      window.contentView = host
      window.makeKeyAndOrderFront(nil)
      for _ in 0..<30 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
      }
      let scale = window.backingScaleFactor
      let image = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: Int(host.bounds.width * scale),
          pixelsHigh: Int(host.bounds.height * scale),
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .calibratedRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        )
      )
      image.size = host.bounds.size
      host.cacheDisplay(in: host.bounds, to: image)

      #expect(settingsSurfacePixelCount(in: image, matching: theme.nsColor(.card)) > 80)
      #expect(settingsSurfacePixelCount(in: image, matching: theme.nsColor(.raised)) > 80)

      window.contentView = nil
      window.orderOut(nil)
    }
  }
}

@Test @MainActor
func settingsGlassOpacitySliderRendersNeutralTrackAcrossAppearancesAndContrast() async throws {
  let application = NSApplication.shared
  let previousApplicationAppearance = application.appearance
  defer { application.appearance = previousApplicationAppearance }
  let captureDirectory = ProcessInfo.processInfo.environment["FLECK_CONTROL_FOCUS_CAPTURE_DIR"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }
  if let captureDirectory {
    try FileManager.default.createDirectory(
      at: captureDirectory,
      withIntermediateDirectories: true
    )
  }

  for (mode, isHighContrast, layoutDirection) in [
    (AppTheme.light, false, LayoutDirection.leftToRight),
    (AppTheme.light, false, .rightToLeft),
    (AppTheme.dark, false, .leftToRight),
    (AppTheme.dark, false, .rightToLeft),
    (AppTheme.light, true, .leftToRight),
    (AppTheme.light, true, .rightToLeft),
    (AppTheme.dark, true, .leftToRight),
    (AppTheme.dark, true, .rightToLeft),
  ] {
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: mode,
      systemAppearance: .light,
      reduceTransparency: false,
      increasedContrast: isHighContrast
    )
    let windowAppearance: NSAppearance.Name =
      theme.appearance == .dark ? .darkAqua : .aqua
    let host = NSHostingView(
      rootView: SettingsGlassOpacitySlider(value: .constant(0.82))
        .environment(\.fleckThemeSnapshot, theme)
        .environment(\.colorScheme, theme.colorScheme)
        .environment(\.layoutDirection, layoutDirection)
        .background(theme.color(.window))
        .frame(width: 180, height: 36)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.appearance = NSAppearance(named: windowAppearance)
    window.backgroundColor = theme.nsColor(.window)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    for _ in 0..<30 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    let image = try settingsHostedCapture(in: host)
    let sliderMetrics = SettingsGlassOpacitySliderMetrics.resolve(
      value: 0.82,
      width: 150,
      trackInset: 8,
      layoutDirection: layoutDirection
    )
    let scale = CGFloat(image.pixelsWide) / 180
    let expectedThumbX = (15 + sliderMetrics.thumbX) * scale
    let thumbCenters = settingsSliderThumbTopCenters(
      in: image,
      against: theme.nsColor(.window),
      containerHeight: 36
    )

    #expect(settingsNonBackgroundPixelCount(in: image, against: theme.nsColor(.window)) > 40)
    #expect(thumbCenters.count == 1)
    if let thumbCenter = thumbCenters.first {
      #expect(abs(thumbCenter - expectedThumbX) <= 2 * scale)
    }

    if let captureDirectory {
      let appearanceName = theme.appearance == .dark ? "dark" : "light"
      let contrastName = isHighContrast ? "increased" : "standard"
      let directionName = layoutDirection == .rightToLeft ? "rtl" : "ltr"
      let url = captureDirectory
        .appendingPathComponent(
          "opacity-slider-\(appearanceName)-\(contrastName)-\(directionName).png"
        )
      let png = try #require(image.representation(using: .png, properties: [:]))
      try png.write(to: url)
    }

    window.contentView = nil
    window.orderOut(nil)
  }
}

@MainActor
private func settingsSurfacePixelCount(
  in image: NSBitmapImageRep,
  matching targetColor: NSColor
) -> Int {
  guard let target = targetColor.usingColorSpace(.sRGB) else { return 0 }
  var matches = 0
  for y in 0..<image.pixelsHigh {
    for x in 0..<image.pixelsWide {
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
        color.alphaComponent > 0.5
      else { continue }
      let distance = max(
        abs(color.redComponent - target.redComponent),
        max(
          abs(color.greenComponent - target.greenComponent),
          abs(color.blueComponent - target.blueComponent)
        )
      )
      if distance < 0.04 { matches += 1 }
    }
  }
  return matches
}

@MainActor
private func settingsHostedCapture<Content: View>(
  in host: NSHostingView<Content>
) throws -> NSBitmapImageRep {
  let scale = host.window?.backingScaleFactor ?? 1
  let image = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(host.bounds.width * scale),
      pixelsHigh: Int(host.bounds.height * scale),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .calibratedRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
  image.size = host.bounds.size
  host.cacheDisplay(in: host.bounds, to: image)
  return image
}

@MainActor
private func settingsNonBackgroundPixelCount(
  in image: NSBitmapImageRep,
  against targetColor: NSColor
) -> Int {
  guard let target = targetColor.usingColorSpace(.sRGB) else { return 0 }
  var matches = 0
  for y in 0..<image.pixelsHigh {
    for x in 0..<image.pixelsWide {
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
        color.alphaComponent > 0.5
      else { continue }
      let distance = max(
        abs(color.redComponent - target.redComponent),
        max(
          abs(color.greenComponent - target.greenComponent),
          abs(color.blueComponent - target.blueComponent)
        )
      )
      if distance > 0.12 { matches += 1 }
    }
  }
  return matches
}

@MainActor
private func settingsSliderThumbTopCenters(
  in image: NSBitmapImageRep,
  against targetColor: NSColor,
  containerHeight: CGFloat
) -> [CGFloat] {
  guard let target = targetColor.usingColorSpace(.sRGB) else { return [] }
  let scale = CGFloat(image.pixelsHigh) / containerHeight
  let y = image.pixelsHigh / 2 - Int((8 * scale).rounded())
  guard (0..<image.pixelsHigh).contains(y) else { return [] }

  var centers: [CGFloat] = []
  var runStart: Int?
  var runEnd: Int?
  let minimumRunWidth = max(2, Int((3 * scale).rounded()))

  func finishRun() {
    guard let start = runStart, let end = runEnd, end - start + 1 >= minimumRunWidth else {
      runStart = nil
      runEnd = nil
      return
    }
    centers.append(CGFloat(start + end) / 2)
    runStart = nil
    runEnd = nil
  }

  for x in 0..<image.pixelsWide {
    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
      color.alphaComponent > 0.5
    else {
      finishRun()
      continue
    }
    let distance = max(
      abs(color.redComponent - target.redComponent),
      max(
        abs(color.greenComponent - target.greenComponent),
        abs(color.blueComponent - target.blueComponent)
      )
    )
    if distance > 0.12 {
      if runStart == nil { runStart = x }
      runEnd = x
    } else {
      finishRun()
    }
  }
  finishRun()
  return centers
}
