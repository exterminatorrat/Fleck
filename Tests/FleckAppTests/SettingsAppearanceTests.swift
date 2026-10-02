import Foundation
import AppKit
import Combine
import CoreGraphics
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
  let menuBarRoot = try #require(
    appSource.components(separatedBy: "MenuBarExtra {").last?
      .components(separatedBy: "      label: {").first
  )
  let pinnedNotesRoot = try #require(
    appSource.components(separatedBy: "Window(\"Fleck\", id: \"pinned-notes\") {").last?
      .components(separatedBy: "      .commands {").first
  )
  let settingsRoot = try #require(
    appSource.components(separatedBy: "      Settings {").last?
      .components(separatedBy: "      .defaultSize(width: 840, height: 600)").first
  )

  #expect(menuBarRoot.contains(".fleckTheme(appState)"))
  #expect(pinnedNotesRoot.contains(".fleckTheme(appState)"))
  #expect(settingsRoot.contains(".fleckTheme(appState)"))
  #expect(appSource.components(separatedBy: ".fleckTheme(appState)").count - 1 == 3)
  #expect(!appSource.contains("Window(\"Models\""))
  #expect(!appSource.contains("ModelLibraryLayout.windowIdentifier"))
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
  let opacitySlider = try #require(
    settingsSource.components(separatedBy: "struct SettingsGlassOpacitySlider: View").last?
      .components(separatedBy: "\n  struct SettingsView").first
  )
  let opacitySliderControl = opacitySlider.components(separatedBy: ".overlay {").first ?? ""

  #expect(sortOption.contains(".focusEffectDisabled()"))
  #expect(sortOption.contains(
    ".fleckNeutralControlOutline(isFocused: isFocused, cornerRadius: 7)"
  ))
  #expect(!sortOption.contains("theme.color(.focusRing)"))
  #expect(settingsSource.contains("SettingsGlassOpacitySlider(value: preferenceBinding(\\.panelOpacity))"))
  #expect(settingsSource.contains(".disabled(appState.preferences.chromeAppearance == .solid)"))
  #expect(themeSource.contains("private struct FleckNeutralControlOutline: ViewModifier"))
  #expect(themeSource.contains("@Environment(\\.fleckThemeSnapshot) private var theme"))
  #expect(themeSource.contains("Color.primary.opacity(isHighContrast ? 1 : 0.72)"))
  #expect(themeSource.contains("lineWidth: isHighContrast ? 2 : 1.5"))
  #expect(opacitySlider.contains("Slider(value: $value, in: 0.55...1)"))
  #expect(opacitySlider.contains("DragGesture(minimumDistance: 0)"))
  #expect(opacitySlider.contains("guard isEnabled, trackWidth > 0 else { return }"))
  #expect(!opacitySlider.contains(".allowsHitTesting(false)"))
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

@Test
func settingsColorThemePickerRetainsEightNamedNativeOptions() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let pickerSource = try #require(
    settingsSource.components(separatedBy: "  struct SettingsColorThemePicker: View").last?
      .components(separatedBy: "\n  struct SettingsView: View").first
  )

  #expect(FleckColorTheme.allCases.map(\.rawValue) == [
    "monochrome", "capy", "absolutely", "oled", "codex", "github", "linear", "notion",
  ])
  #expect(FleckColorTheme.allCases.map(\.title) == [
    "Fleck Monochrome", "Capy", "Absolutely", "OLED", "Codex", "GitHub", "Linear", "Notion",
  ])
  #expect(pickerSource.contains("Picker(\"Color theme\", selection: $selection)"))
  #expect(pickerSource.contains("ForEach(FleckColorTheme.allCases) { theme in"))
  #expect(pickerSource.contains("Text(theme.title)"))
  #expect(pickerSource.contains(".renderingMode(.original)"))
  #expect(pickerSource.contains(".tag(theme)"))
  #expect(pickerSource.contains(".labelsHidden()"))
  #expect(pickerSource.contains(".pickerStyle(.menu)"))
  #expect(!pickerSource.contains("selectionDisabled"))
  #expect(settingsSource.contains("selection: preferenceBinding(\\.colorTheme)"))
  #expect(settingsSource.contains("appearance: theme.appearance"))
}

@Test @MainActor
func settingsThemeMenuPreviewUsesEightPaletteRolesAtOneAndTwoScale() throws {
  let roles: [FleckThemeColor] = [
    .window, .card, .border, .textPrimary, .accent, .accentText, .selectionFill, .selectionText,
  ]

  for theme in FleckColorTheme.allCases {
    for appearance in [FleckThemeAppearance.light, .dark] {
      let palette = FleckThemePalette.resolve(family: theme, appearance: appearance)
      let preview = SettingsColorThemePicker.previewImage(for: theme, appearance: appearance)
      let representations = preview.representations
        .compactMap { $0 as? NSBitmapImageRep }
        .sorted { $0.pixelsWide < $1.pixelsWide }

      #expect(preview.size == NSSize(width: 15, height: 15))
      #expect(!preview.isTemplate)
      #expect(representations.map(\.pixelsWide) == [15, 30])
      #expect(representations.map(\.pixelsHigh) == [15, 30])
      for representation in representations {
        #expect(representation.size == NSSize(width: 15, height: 15))
        let scale = representation.pixelsWide / 15
        for role in roles {
          let expected = try #require(NSColor(hex: palette[role]))
          let region = try #require(settingsThemePreviewRoleRegion(role))
          let minimumDistance = settingsThemePreviewMinimumPixelDistance(
            in: representation,
            matching: expected,
            within: region
          )

          if scale == 1,
            let backgroundRole = settingsThemePreviewBlendBackgroundRole(role)
          {
            let background = try #require(NSColor(hex: palette[backgroundRole]))
            let blendError = settingsThemePreviewMinimumBlendError(
              in: representation,
              foreground: expected,
              background: background,
              within: region
            )
            #expect(
              blendError.map { $0 <= 0.04 } == true,
              "missing antialiased \(role.rawValue) blend over \(backgroundRole.rawValue) in \(theme.rawValue)/\(appearance.rawValue) at 1×"
            )
          } else if scale == 1, role == .window {
            continue
          } else {
            #expect(
              minimumDistance <= 0.1,
              "\(role.rawValue) is \(minimumDistance) from its expected color in \(theme.rawValue)/\(appearance.rawValue) at \(scale)×"
            )
          }
        }
      }
    }
  }
}

@Test @MainActor
func settingsColorThemePickerRendersOpenAndSelectedNativePreviewsAcrossAppearances()
  async throws
{
  let application = NSApplication.shared
  let previousActivationPolicy = application.activationPolicy()
  defer { _ = application.setActivationPolicy(previousActivationPolicy) }
  if previousActivationPolicy != .regular {
    try #require(application.setActivationPolicy(.regular))
  }
  try #require(application.activationPolicy() == .regular)
  application.activate(ignoringOtherApps: true)

  let captureDirectory = ProcessInfo.processInfo.environment["FLECK_THEME_PICKER_CAPTURE_DIR"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }
  if let captureDirectory {
    try FileManager.default.createDirectory(
      at: captureDirectory,
      withIntermediateDirectories: true
    )
  }

  for appearance in [FleckThemeAppearance.light, .dark] {
    let state = SettingsThemePickerSelectionProbe()
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: appearance == .dark ? .dark : .light,
      systemAppearance: appearance,
      reduceTransparency: false,
      increasedContrast: false
    )
    let host = NSHostingView(
      rootView: SettingsThemePickerFixture(state: state, appearance: appearance)
        .environment(\.fleckThemeSnapshot, theme)
        .environment(\.colorScheme, theme.colorScheme)
        .background(theme.color(.window))
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 72),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    window.backgroundColor = theme.nsColor(.window)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    for _ in 0..<30 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    let picker = try #require(settingsThemePickerPopup(in: host))
    let expectedNames = FleckColorTheme.allCases.map(\.title)
    let items = try #require(picker.menu?.items)
    #expect(items.count == 8)
    #expect(items.map(\.title) == expectedNames)
    #expect(items.allSatisfy { $0.accessibilityLabel() == $0.title })
    #expect(items.allSatisfy { $0.image?.size == NSSize(width: 15, height: 15) })
    #expect(items.allSatisfy { $0.image?.isTemplate == false })

    #expect(picker.titleOfSelectedItem == FleckColorTheme.monochrome.title)
    #expect(picker.selectedItem?.image?.size == NSSize(width: 15, height: 15))
    #expect(picker.selectedItem?.image?.isTemplate == false)
    #expect(picker.cell?.image?.size == NSSize(width: 15, height: 15))

    for scale in [1, 2] {
      let closedFrame = try settingsThemePickerCapture(in: host, scale: scale)
      #expect(closedFrame.pixelsWide == Int(host.bounds.width) * scale)
      #expect(closedFrame.pixelsHigh == Int(host.bounds.height) * scale)
      try settingsThemePickerWriteCapture(
        closedFrame,
        name: "theme-picker-\(appearance.rawValue)-closed-monochrome-\(scale)x.png",
        directory: captureDirectory
      )
    }

    let openMenuProbe = SettingsThemePickerOpenMenuProbe()
    do {
      let menuTimer = Timer(timeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
          guard openMenuProbe.menuWindowNumber == nil,
            openMenuProbe.captureError == nil
          else { return }
          do {
            switch try settingsThemePickerCaptureOpenWindows(
              excluding: window,
              appearance: appearance,
              directory: captureDirectory
            ) {
            case .noCandidate:
              openMenuProbe.readinessError = "No live native pop-up menu window is open yet"
            case .captureUnavailable:
              openMenuProbe.readinessError =
                "A live native pop-up menu window is not capturable yet"
            case .captured(let captures):
              guard let capture = captures.first else {
                openMenuProbe.captureError = "The native menu capture returned no windows"
                openMenuProbe.retryTimer?.invalidate()
                return
              }
              openMenuProbe.readinessError = nil
              openMenuProbe.captures = captures.map(\.image)
              openMenuProbe.menuWindowNumber = capture.windowNumber
              openMenuProbe.retryTimer?.invalidate()
              settingsThemePickerPostKey(
                keyCode: 125,
                characters: "\u{F701}",
                windowNumber: capture.windowNumber
              )
              settingsThemePickerPostKey(
                keyCode: 36,
                characters: "\r",
                windowNumber: capture.windowNumber
              )
            }
          } catch {
            openMenuProbe.captureError = String(describing: error)
            openMenuProbe.retryTimer?.invalidate()
          }
        }
      }
      let menuDeadlineTimer = Timer(timeInterval: 5, repeats: false) { _ in
        MainActor.assumeIsolated {
          openMenuProbe.deadlineFired = true
          openMenuProbe.retryTimer?.invalidate()
          picker.menu?.cancelTracking()
        }
      }
      openMenuProbe.retryTimer = menuTimer
      RunLoop.main.add(menuTimer, forMode: .eventTracking)
      for mode in [RunLoop.Mode.eventTracking, .default] {
        RunLoop.main.add(menuDeadlineTimer, forMode: mode)
      }
      defer {
        menuTimer.invalidate()
        menuDeadlineTimer.invalidate()
        openMenuProbe.retryTimer = nil
      }
      picker.performClick(nil)
    }

    _ = try await settingsAppearanceWait(in: host) {
      state.selection == .capy && picker.titleOfSelectedItem == FleckColorTheme.capy.title
    }
    #expect(!openMenuProbe.deadlineFired)
    #expect(openMenuProbe.captureError == nil)
    #expect(openMenuProbe.readinessError == nil)
    #expect(openMenuProbe.menuWindowNumber != nil)
    #expect(!openMenuProbe.captures.isEmpty)
    #expect(state.selection == .capy)
    #expect(picker.titleOfSelectedItem == FleckColorTheme.capy.title)
    #expect(picker.selectedItem?.image?.size == NSSize(width: 15, height: 15))
    for scale in [1, 2] {
      let closedFrame = try settingsThemePickerCapture(in: host, scale: scale)
      try settingsThemePickerWriteCapture(
        closedFrame,
        name: "theme-picker-\(appearance.rawValue)-closed-capy-\(scale)x.png",
        directory: captureDirectory
      )
    }

    let activationProbe = SettingsThemePickerOpenMenuProbe()
    do {
      let activationTimer = Timer(timeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
          guard activationProbe.menuWindowNumber == nil,
            !activationProbe.didActivateMenuItem
          else { return }
          guard let menuWindow = settingsThemePickerOpenMenuWindows(excluding: window).first else {
            activationProbe.readinessError =
              "No live native pop-up menu window is open yet"
            return
          }
          guard let menu = picker.menu else {
            activationProbe.readinessError =
              "The picker menu is unavailable while its native pop-up is open"
            return
          }
          activationProbe.readinessError = nil
          activationProbe.menuWindowNumber = menuWindow.windowNumber
          activationProbe.retryTimer?.invalidate()
          menu.performActionForItem(at: 4)
          activationProbe.didActivateMenuItem = true
          let dismissTimer = Timer(timeInterval: 1.2, repeats: false) { _ in
            MainActor.assumeIsolated {
              guard let menuWindowNumber = activationProbe.menuWindowNumber else { return }
              settingsThemePickerPostKey(
                keyCode: 53,
                characters: "\u{1B}",
                windowNumber: menuWindowNumber
              )
            }
          }
          activationProbe.dismissTimer = dismissTimer
          for mode in [RunLoop.Mode.eventTracking, .default] {
            RunLoop.main.add(dismissTimer, forMode: mode)
          }
        }
      }
      let menuDeadlineTimer = Timer(timeInterval: 5, repeats: false) { _ in
        MainActor.assumeIsolated {
          activationProbe.deadlineFired = true
          activationProbe.retryTimer?.invalidate()
          activationProbe.dismissTimer?.invalidate()
          picker.menu?.cancelTracking()
        }
      }
      activationProbe.retryTimer = activationTimer
      RunLoop.main.add(activationTimer, forMode: .eventTracking)
      for mode in [RunLoop.Mode.eventTracking, .default] {
        RunLoop.main.add(menuDeadlineTimer, forMode: mode)
      }
      defer {
        activationTimer.invalidate()
        activationProbe.dismissTimer?.invalidate()
        menuDeadlineTimer.invalidate()
        activationProbe.retryTimer = nil
        activationProbe.dismissTimer = nil
      }
      picker.performClick(nil)
    }
    _ = try await settingsAppearanceWait(in: host) {
      state.selection == .codex && picker.titleOfSelectedItem == FleckColorTheme.codex.title
    }
    #expect(!activationProbe.deadlineFired)
    #expect(activationProbe.captureError == nil)
    #expect(activationProbe.readinessError == nil)
    #expect(activationProbe.menuWindowNumber != nil)
    #expect(activationProbe.didActivateMenuItem)
    #expect(state.selection == .codex)
    #expect(picker.titleOfSelectedItem == FleckColorTheme.codex.title)
    #expect(picker.selectedItem?.image?.isTemplate == false)

    #expect(picker.menu?.items.map(\.title) == expectedNames)
  }
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
  #expect(!agentIndicatorSource.contains("Text(\"MCP\")"))
  #expect(
    agentIndicatorSource.contains(
      ".accessibilityLabel(presentation.state.accessibilityLabel)"
    )
  )
  #expect(
    agentIndicatorSource.contains(
      ".foregroundStyle(presentation.state.statusColor(in: theme))"
    )
  )
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

@Test @MainActor
func settingsGlassOpacitySliderRespondsToThumbDragAndTrackClickAtAnchoredSettingsRow()
  async throws
{
  let application = NSApplication.shared
  let previousActivationPolicy = application.activationPolicy()
  if previousActivationPolicy != .regular {
    #expect(application.setActivationPolicy(.regular))
  }
  #expect(application.activationPolicy() == .regular)
  defer { _ = application.setActivationPolicy(previousActivationPolicy) }

  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .monochrome,
    mode: .light,
    systemAppearance: .light,
    reduceTransparency: false,
    increasedContrast: false
  )

  for layoutDirection in [LayoutDirection.leftToRight, .rightToLeft] {
    let state = SettingsGlassOpacityBindingProbe(value: 0.68)
    let host = NSHostingView(
      rootView: SettingsGlassOpacityRowFixture(
        state: state,
        isEnabled: true,
        request: nil
      )
      .environment(\.fleckThemeSnapshot, theme)
      .environment(\.colorScheme, theme.colorScheme)
      .environment(\.layoutDirection, layoutDirection)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 96),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    let windowReady = try await settingsAppearanceWait(in: host) {
      guard NSApp.isActive,
        window.isKeyWindow,
        NSApp.keyWindow === window,
        window.isVisible,
        let slider = settingsNativeSlider(in: host),
        slider.window === window,
        !slider.isHiddenOrHasHiddenAncestor
      else { return false }
      return slider.bounds.width > 0 && slider.bounds.height > 0
    }
    try #require(windowReady)

    let slider = try #require(settingsNativeSlider(in: host))
    let sliderRect = slider.convert(slider.bounds, to: host)
    func sliderPoint(for value: Double) -> NSPoint {
      let metrics = SettingsGlassOpacitySliderMetrics.resolve(
        value: value,
        width: sliderRect.width,
        trackInset: 8,
        layoutDirection: layoutDirection
      )
      return host.convert(
        NSPoint(x: sliderRect.minX + metrics.thumbX, y: sliderRect.midY),
        to: nil
      )
    }

    try settingsSendMouseSequence(
      [
        (.leftMouseDown, sliderPoint(for: state.value)),
        (.leftMouseDragged, sliderPoint(for: 0.9)),
        (.leftMouseUp, sliderPoint(for: 0.9)),
      ],
      to: window
    )
    _ = try await settingsAppearanceWait(in: host) { state.value > 0.82 }
    #expect(state.value > 0.82)
    let valueAfterDrag = state.value
    let clickedValue = 0.6
    let trackPoint = sliderPoint(for: clickedValue)
    try settingsSendMouseSequence(
      [(.leftMouseDown, trackPoint), (.leftMouseUp, trackPoint)],
      to: window
    )
    _ = try await settingsAppearanceWait(in: host) {
      state.value < valueAfterDrag && abs(state.value - clickedValue) < 0.04
    }

    #expect(valueAfterDrag > 0.82)
    #expect(state.value < valueAfterDrag)
    #expect(abs(state.value - clickedValue) < 0.04)
  }
}

@Test @MainActor
func settingsGlassOpacitySliderRemainsDisabledForSolidAppearance() async throws {
  let application = NSApplication.shared
  let previousActivationPolicy = application.activationPolicy()
  if previousActivationPolicy != .regular {
    #expect(application.setActivationPolicy(.regular))
  }
  #expect(application.activationPolicy() == .regular)
  defer { _ = application.setActivationPolicy(previousActivationPolicy) }

  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .monochrome,
    mode: .light,
    systemAppearance: .light,
    reduceTransparency: false,
    increasedContrast: false
  )
  let state = SettingsGlassOpacityBindingProbe(value: 0.68)
  let host = NSHostingView(
    rootView: SettingsGlassOpacityRowFixture(
      state: state,
      isEnabled: false,
      request: nil
    )
    .environment(\.fleckThemeSnapshot, theme)
    .environment(\.colorScheme, theme.colorScheme)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 96),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  NSApp.activate(ignoringOtherApps: true)
  window.makeKeyAndOrderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }
  for _ in 0..<30 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }

  let slider = try #require(settingsNativeSlider(in: host))
  let sliderRect = slider.convert(slider.bounds, to: host)
  func sliderPoint(for value: Double) -> NSPoint {
    let metrics = SettingsGlassOpacitySliderMetrics.resolve(
      value: value,
      width: sliderRect.width,
      trackInset: 8,
      layoutDirection: .leftToRight
    )
    return host.convert(
      NSPoint(x: sliderRect.minX + metrics.thumbX, y: sliderRect.midY),
      to: nil
    )
  }
  try settingsSendMouseSequence(
    [
      (.leftMouseDown, sliderPoint(for: state.value)),
      (.leftMouseDragged, sliderPoint(for: 0.9)),
      (.leftMouseUp, sliderPoint(for: 0.9)),
    ],
    to: window
  )
  for _ in 0..<20 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }

  #expect(state.value == 0.68)
}

@Test @MainActor
func settingsSearchAnchorKeepsAppearanceCardFocusedWithoutSystemHalo() async throws {
  let application = NSApplication.shared
  let previousActivationPolicy = application.activationPolicy()
  if previousActivationPolicy != .regular {
    #expect(application.setActivationPolicy(.regular))
  }
  #expect(application.activationPolicy() == .regular)
  defer { _ = application.setActivationPolicy(previousActivationPolicy) }

  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .monochrome,
    mode: .light,
    systemAppearance: .light,
    reduceTransparency: false,
    increasedContrast: false
  )
  let state = SettingsGlassOpacityBindingProbe(value: 0.68)
  let request = SettingsSearchRequest(target: .appearanceGlassOpacity)
  let host = NSHostingView(
    rootView: SettingsGlassOpacityRowFixture(
      state: state,
      isEnabled: true,
      request: request
    )
    .environment(\.fleckThemeSnapshot, theme)
    .environment(\.colorScheme, theme.colorScheme)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 96),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  NSApp.activate(ignoringOtherApps: true)
  window.makeKeyAndOrderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }
  for _ in 0..<30 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }

  let focusIdentifier =
    "settings-keyboard-focus-\(SettingsSearchTarget.appearanceGlassOpacity.identifier)"
  let cueIdentifier =
    "settings-keyboard-focus-cue-\(SettingsSearchTarget.appearanceGlassOpacity.identifier)"
  #expect(settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil)
  #expect(settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil)
  let image = try settingsHostedCapture(in: host)
  #expect(settingsSurfacePixelCount(in: image, matching: NSColor.keyboardFocusIndicatorColor) == 0)

  if let capturePath = ProcessInfo.processInfo.environment["FLECK_CONTROL_FOCUS_CAPTURE_DIR"] {
    let captureDirectory = URL(fileURLWithPath: capturePath, isDirectory: true)
    try FileManager.default.createDirectory(
      at: captureDirectory,
      withIntermediateDirectories: true
    )
    let png = try #require(image.representation(using: .png, properties: [:]))
    try png.write(to: captureDirectory.appendingPathComponent("appearance-card-focus.png"))
  }
}

@Test @MainActor
func settingsSearchAnchorFocusCueDistinguishesTabFromPointer() async throws {
  let application = NSApplication.shared
  let previousActivationPolicy = application.activationPolicy()
  if previousActivationPolicy != .regular {
    #expect(application.setActivationPolicy(.regular))
  }
  #expect(application.activationPolicy() == .regular)
  defer { _ = application.setActivationPolicy(previousActivationPolicy) }

  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .monochrome,
    mode: .light,
    systemAppearance: .light,
    reduceTransparency: false,
    increasedContrast: false
  )
  let state = SettingsGlassOpacityBindingProbe(value: 0.68)
  let host = NSHostingView(
    rootView: SettingsAppearanceFocusHostFixture(
      state: state,
      request: nil
    )
    .environment(\.fleckThemeSnapshot, theme)
    .environment(\.colorScheme, theme.colorScheme)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 132),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  NSApp.activate(ignoringOtherApps: true)
  window.makeKeyAndOrderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }
  let windowReady = try await settingsAppearanceWait(in: host) {
    guard NSApp.isActive,
      window.isKeyWindow,
      NSApp.keyWindow === window,
      window.isVisible,
      let searchField = settingsNativeView(
        withAccessibilityIdentifier: "settings-search-field",
        in: host
      ) as? NSSearchField,
      searchField.window === window,
      !searchField.isHiddenOrHasHiddenAncestor
    else { return false }
    return searchField.bounds.width > 0 && searchField.bounds.height > 0
  }
  try #require(windowReady)

  let focusIdentifier =
    "settings-keyboard-focus-\(SettingsSearchTarget.appearanceGlassOpacity.identifier)"
  let cueIdentifier =
    "settings-keyboard-focus-cue-\(SettingsSearchTarget.appearanceGlassOpacity.identifier)"
  let searchField = try #require(
    settingsNativeView(withAccessibilityIdentifier: "settings-search-field", in: host)
      as? NSSearchField
  )
  #expect(window.makeFirstResponder(searchField))
  _ = try await settingsAppearanceWait(in: host) {
    settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) == nil
      && settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil
  }
  #expect(settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) == nil)
  #expect(settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil)
  let appearanceRow = try #require(
    settingsNativeView(
      withAccessibilityIdentifier: SettingsSearchTarget.appearanceGlassOpacity.accessibilityIdentifier,
      in: host
    )
  )
  let rowFrame = appearanceRow.convert(appearanceRow.bounds, to: host)
  let clickPoint = host.convert(NSPoint(x: rowFrame.minX + 36, y: rowFrame.midY), to: nil)
  let tabEvent = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      isARepeat: false,
      keyCode: 48
    )
  )
  let tabReady = try await settingsAppearanceWait(in: host) {
    guard NSApp.isActive,
      window.isKeyWindow,
      NSApp.keyWindow === window,
      window.isVisible,
      searchField.window === window,
      !searchField.isHiddenOrHasHiddenAncestor,
      searchField.bounds.width > 0,
      searchField.bounds.height > 0,
      let editor = searchField.currentEditor()
    else { return false }
    return editor === window.firstResponder
  }
  try #require(tabReady)
  try #require(
    searchField.currentEditor() != nil && searchField.currentEditor() === window.firstResponder
  )
  NSApp.sendEvent(tabEvent)
  _ = try await settingsAppearanceWait(in: host) {
    settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil
      && settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) != nil
  }
  #expect(settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil)
  #expect(settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) != nil)
  let tabFocusImage = try settingsHostedCapture(in: host)
  try settingsSendMouseSequence(
    [(.leftMouseDown, clickPoint), (.leftMouseUp, clickPoint)],
    to: window,
    throughApplication: true
  )
  _ = try await settingsAppearanceWait(in: host) {
    settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil
      && settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil
  }
  #expect(settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil)
  #expect(settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil)
  #expect(window.makeFirstResponder(searchField))
  _ = try await settingsAppearanceWait(in: host) {
    settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) == nil
      && settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil
  }
  #expect(settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) == nil)
  #expect(settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil)
  try settingsSendMouseSequence(
    [(.leftMouseDown, clickPoint), (.leftMouseUp, clickPoint)],
    to: window,
    throughApplication: true
  )
  _ = try await settingsAppearanceWait(in: host) {
    settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil
      && settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil
  }
  #expect(settingsNativeView(withAccessibilityIdentifier: focusIdentifier, in: host) != nil)
  #expect(settingsNativeView(withAccessibilityIdentifier: cueIdentifier, in: host) == nil)
  let pointerFocusImage = try settingsHostedCapture(in: host)

  if let capturePath = ProcessInfo.processInfo.environment["FLECK_CONTROL_FOCUS_CAPTURE_DIR"] {
    let captureDirectory = URL(fileURLWithPath: capturePath, isDirectory: true)
    try FileManager.default.createDirectory(
      at: captureDirectory,
      withIntermediateDirectories: true
    )
    let tabPNG = try #require(tabFocusImage.representation(using: .png, properties: [:]))
    let pointerPNG = try #require(pointerFocusImage.representation(using: .png, properties: [:]))
    try tabPNG.write(to: captureDirectory.appendingPathComponent("appearance-card-tab-focus.png"))
    try pointerPNG.write(
      to: captureDirectory.appendingPathComponent("appearance-card-pointer-focus.png")
    )
  }
}

@MainActor
private final class SettingsThemePickerSelectionProbe: ObservableObject {
  @Published var selection: FleckColorTheme = .monochrome
}

@MainActor
private final class SettingsThemePickerOpenMenuProbe {
  var captures: [NSBitmapImageRep] = []
  var captureError: String?
  var readinessError: String?
  var didActivateMenuItem = false
  var menuWindowNumber: Int?
  var deadlineFired = false
  var retryTimer: Timer?
  var dismissTimer: Timer?
}

private struct SettingsThemePickerFixture: View {
  @ObservedObject var state: SettingsThemePickerSelectionProbe
  let appearance: FleckThemeAppearance

  var body: some View {
    SettingsColorThemePicker(selection: $state.selection, appearance: appearance)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .frame(width: 460, height: 72, alignment: .leading)
  }
}

@MainActor
private func settingsThemePickerPopup(in view: NSView) -> NSPopUpButton? {
  if let picker = view as? NSPopUpButton { return picker }
  for subview in view.subviews {
    if let picker = settingsThemePickerPopup(in: subview) {
      return picker
    }
  }
  return nil
}

@MainActor
private func settingsThemePickerCapture<Content: View>(
  in host: NSHostingView<Content>,
  scale: Int
) throws -> NSBitmapImageRep {
  let image = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(host.bounds.width) * scale,
      pixelsHigh: Int(host.bounds.height) * scale,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
  image.size = host.bounds.size
  host.cacheDisplay(in: host.bounds, to: image)
  return image
}

@MainActor
private func settingsThemePickerWriteCapture(
  _ image: NSBitmapImageRep,
  name: String,
  directory: URL?
) throws {
  guard let directory else { return }
  let data = try #require(image.representation(using: .png, properties: [:]))
  try data.write(to: directory.appendingPathComponent(name))
}

@MainActor
private func settingsThemePickerCaptureOpenWindows(
  excluding hostWindow: NSWindow,
  appearance: FleckThemeAppearance,
  directory: URL?
) throws -> SettingsThemePickerOpenMenuCaptureAttempt {
  let menuWindows = settingsThemePickerOpenMenuWindows(excluding: hostWindow)
  guard !menuWindows.isEmpty else { return .noCandidate }
  var captures: [SettingsThemePickerOpenWindowCapture] = []
  for menuWindow in menuWindows {
    guard let number = UInt32(exactly: menuWindow.windowNumber),
      let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        number,
        .bestResolution
      )
    else { continue }
    let representation = NSBitmapImageRep(cgImage: image)
    captures.append(
      SettingsThemePickerOpenWindowCapture(
        windowNumber: menuWindow.windowNumber,
        image: representation
      )
    )
    try settingsThemePickerWriteCapture(
      representation,
      name: "theme-picker-\(appearance.rawValue)-open-menu-\(number).png",
      directory: directory
    )
  }
  guard !captures.isEmpty else { return .captureUnavailable }
  return .captured(captures)
}

private enum SettingsThemePickerOpenMenuCaptureAttempt {
  case noCandidate
  case captureUnavailable
  case captured([SettingsThemePickerOpenWindowCapture])
}

private struct SettingsThemePickerOpenWindowCapture {
  let windowNumber: Int
  let image: NSBitmapImageRep
}

@MainActor
private func settingsThemePickerOpenMenuWindows(excluding hostWindow: NSWindow) -> [NSWindow] {
  NSApp.windows.filter {
    $0 !== hostWindow && $0.isVisible && $0.level == .popUpMenu
  }
}

@MainActor
private func settingsThemePickerPostKey(
  keyCode: UInt16,
  characters: String,
  windowNumber: Int
) {
  guard let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: windowNumber,
    context: nil,
    characters: characters,
    charactersIgnoringModifiers: characters,
    isARepeat: false,
    keyCode: keyCode
  ) else { return }
  NSApp.postEvent(event, atStart: false)
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
private func settingsThemePreviewMinimumPixelDistance(
  in image: NSBitmapImageRep,
  matching targetColor: NSColor,
  within rect: CGRect
) -> CGFloat {
  guard let target = targetColor.usingColorSpace(.sRGB) else { return .infinity }
  let scale = CGFloat(image.pixelsWide) / 15
  let minX = max(0, Int(floor(rect.minX * scale)))
  let maxX = min(image.pixelsWide - 1, Int(ceil(rect.maxX * scale)) - 1)
  let minY = max(0, Int(floor(CGFloat(image.pixelsHigh) - rect.maxY * scale)))
  let maxY = min(image.pixelsHigh - 1, Int(ceil(CGFloat(image.pixelsHigh) - rect.minY * scale)) - 1)
  var minimum = CGFloat.infinity
  for y in minY...maxY {
    for x in minX...maxX {
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
        color.alphaComponent > 0.05
      else { continue }
      minimum = min(minimum, settingsThemePreviewRGBDistance(color, target))
    }
  }
  return minimum
}

@MainActor
private func settingsThemePreviewMinimumBlendError(
  in image: NSBitmapImageRep,
  foreground foregroundColor: NSColor,
  background backgroundColor: NSColor,
  within rect: CGRect
) -> CGFloat? {
  guard let foreground = foregroundColor.usingColorSpace(.sRGB),
    let background = backgroundColor.usingColorSpace(.sRGB)
  else { return nil }
  let scale = CGFloat(image.pixelsWide) / 15
  let minX = max(0, Int(floor(rect.minX * scale)))
  let maxX = min(image.pixelsWide - 1, Int(ceil(rect.maxX * scale)) - 1)
  let minY = max(0, Int(floor(CGFloat(image.pixelsHigh) - rect.maxY * scale)))
  let maxY = min(image.pixelsHigh - 1, Int(ceil(CGFloat(image.pixelsHigh) - rect.minY * scale)) - 1)
  let foregroundComponents = [
    foreground.redComponent, foreground.greenComponent, foreground.blueComponent,
  ]
  let backgroundComponents = [
    background.redComponent, background.greenComponent, background.blueComponent,
  ]
  let direction = zip(foregroundComponents, backgroundComponents).map { $0.0 - $0.1 }
  let magnitude = direction.reduce(CGFloat.zero) { $0 + $1 * $1 }
  guard magnitude > 0 else { return nil }

  var minimum = CGFloat.infinity
  for y in minY...maxY {
    for x in minX...maxX {
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
        color.alphaComponent > 0.05
      else { continue }
      let colorComponents = [color.redComponent, color.greenComponent, color.blueComponent]
      let coverage = (0..<3).reduce(CGFloat.zero) { result, index in
        result + (colorComponents[index] - backgroundComponents[index]) * direction[index]
      } / magnitude
      guard coverage > 0.05, coverage <= 1.05 else { continue }
      let error = (0..<3).reduce(CGFloat.zero) { result, index in
        let projected = backgroundComponents[index] + coverage * direction[index]
        return max(result, abs(colorComponents[index] - projected))
      }
      minimum = min(minimum, error)
    }
  }
  return minimum.isFinite ? minimum : nil
}

private func settingsThemePreviewRGBDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
  max(
    abs(lhs.redComponent - rhs.redComponent),
    max(
      abs(lhs.greenComponent - rhs.greenComponent),
      abs(lhs.blueComponent - rhs.blueComponent)
    )
  )
}

private func settingsThemePreviewRoleRegion(_ role: FleckThemeColor) -> CGRect? {
  switch role {
  case .window: NSRect(x: 0.85, y: 7, width: 0.45, height: 1)
  case .card: NSRect(x: 5.5, y: 11.8, width: 4, height: 0.7)
  case .border: NSRect(x: 3.5, y: 14.2, width: 8, height: 0.6)
  case .textPrimary: NSRect(x: 3.4, y: 10.4, width: 5.8, height: 0.9)
  case .accent: NSRect(x: 8, y: 7.4, width: 2.5, height: 2)
  case .accentText: NSRect(x: 4, y: 8.05, width: 3.1, height: 0.7)
  case .selectionFill: NSRect(x: 8, y: 4.2, width: 2.5, height: 2)
  case .selectionText: NSRect(x: 4, y: 4.85, width: 3.1, height: 0.7)
  default: nil
  }
}

private func settingsThemePreviewBlendBackgroundRole(
  _ role: FleckThemeColor
) -> FleckThemeColor? {
  switch role {
  case .border: .window
  case .textPrimary: .card
  case .accentText: .accent
  case .selectionText: .selectionFill
  default: nil
  }
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

@MainActor
private final class SettingsGlassOpacityBindingProbe: ObservableObject {
  @Published var value: Double

  init(value: Double) {
    self.value = value
  }
}

private struct SettingsAppearanceFocusHostFixture: View {
  @ObservedObject var state: SettingsGlassOpacityBindingProbe
  let request: SettingsSearchRequest?
  @State private var query = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSearchField(
        query: $query,
        onMove: { _ in },
        onSubmit: {},
        onBeginEditing: {},
        onFocusChange: { _ in }
      )
      .frame(height: 28)
      SettingsGlassOpacityRowFixture(state: state, isEnabled: true, request: request)
    }
    .frame(width: 420, height: 132, alignment: .topLeading)
  }
}

private struct SettingsGlassOpacityRowFixture: View {
  @ObservedObject var state: SettingsGlassOpacityBindingProbe
  let isEnabled: Bool
  let request: SettingsSearchRequest?

  var body: some View {
    SettingsPreferenceRow(
      "Glass opacity",
      detail: "Adjust how much of the window shows through when Glass is selected."
    ) {
      SettingsGlassOpacitySlider(value: $state.value)
        .disabled(!isEnabled)
    }
    .settingsSearchAnchor(.appearanceGlassOpacity, request: request)
    .padding(12)
    .frame(width: 420, height: 96)
  }
}

@MainActor
private func settingsNativeSlider(in view: NSView) -> NSSlider? {
  if let slider = view as? NSSlider { return slider }
  for subview in view.subviews {
    if let slider = settingsNativeSlider(in: subview) {
      return slider
    }
  }
  return nil
}

@MainActor
private func settingsNativeView(withAccessibilityIdentifier identifier: String, in view: NSView)
  -> NSView?
{
  if view.accessibilityIdentifier() == identifier { return view }
  for subview in view.subviews {
    if let match = settingsNativeView(withAccessibilityIdentifier: identifier, in: subview) {
      return match
    }
  }
  return nil
}

@MainActor
private func settingsAppearanceWait(
  in host: NSView,
  predicate: () -> Bool
) async throws -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(2))
  while clock.now < deadline {
    try Task.checkCancellation()
    host.layoutSubtreeIfNeeded()
    guard clock.now < deadline else { break }
    if predicate() {
      try Task.checkCancellation()
      return true
    }
    let remaining = clock.now.duration(to: deadline)
    guard remaining > .zero else { break }
    try await Task.sleep(for: min(.milliseconds(25), remaining))
  }
  try Task.checkCancellation()
  return false
}

@MainActor
private func settingsSendMouseSequence(
  _ events: [(NSEvent.EventType, NSPoint)],
  to window: NSWindow,
  throughApplication: Bool = false
) throws {
  let timestamp = ProcessInfo.processInfo.systemUptime
  let nativeEvents = try events.enumerated().map { index, event in
    let (type, point) = event
    return try #require(
      NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: timestamp + Double(index) * 0.01,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: index,
        clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1
      )
    )
  }
  for event in nativeEvents {
    if throughApplication {
      NSApp.sendEvent(event)
    } else {
      window.sendEvent(event)
    }
  }
}
