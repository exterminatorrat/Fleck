#if os(macOS)
  import Foundation
  import SwiftUI
  import Testing

  @testable import FleckApp

  @Test @MainActor
  func interfaceFontCatalogCachesUnchangedSelectionsAndDoesNotEnumerateForSystem() {
    var enumerations = 0
    var resolutions = 0
    let catalog = FleckUIFontCatalog(
      installedFamilies: {
        enumerations += 1
        return ["Fixture UI", "Fixture Unresolvable UI"]
      },
      fontNameForFamily: { family in
        resolutions += 1
        return family == "Fixture UI" ? "FixtureUI-Regular" : nil
      }
    )
    for _ in 0..<20 {
      #expect(catalog.typography(for: nil) == .system)
    }
    #expect(enumerations == 0)
    for _ in 0..<20 {
      #expect(catalog.typography(for: "Fixture UI").fontName == "FixtureUI-Regular")
    }
    #expect(enumerations == 1)
    #expect(resolutions == 1)
    for _ in 0..<20 {
      #expect(catalog.typography(for: "Fixture Missing UI") == .system)
    }
    #expect(enumerations == 2)
    #expect(resolutions == 1)
    #expect(catalog.typography(for: "Fixture Unresolvable UI") == .system)
    #expect(enumerations == 3)
    #expect(resolutions == 2)
    #expect(catalog.typography(for: nil) == .system)
    #expect(enumerations == 3)
    #expect(catalog.typography(for: "Fixture UI").fontName == "FixtureUI-Regular")
    #expect(enumerations == 4)
    #expect(resolutions == 3)
  }

  @Test(arguments: [Font.TextStyle.body, .headline, .title2, .callout, .caption, .caption2, .footnote])
  func interfaceFontSystemFallbackPreservesSemanticStyles(_ style: Font.TextStyle) {
    #expect(FleckUIFont.system.font(style) == Font.system(style))
    #expect(FleckUIFont.system.font(style, weight: .semibold) == Font.system(style).weight(.semibold))
    #expect(FleckUIFont.system.font(size: 16) == Font.system(size: 16, weight: .regular))
  }

  @Test func interfaceFontCustomStylesRemainRelativeAndScaledSizeValuesAreNotRescaled() {
    let typography = FleckUIFont(fontName: "FixtureUI-Regular")
    #expect(typography.font(.body) == Font.custom("FixtureUI-Regular", size: 13, relativeTo: .body).weight(.regular))
    #expect(typography.font(.caption) == Font.custom("FixtureUI-Regular", size: 11, relativeTo: .caption).weight(.regular))
    #expect(typography.font(.headline) == Font.custom("FixtureUI-Regular", size: 13, relativeTo: .headline).weight(.semibold))
    #expect(typography.font(size: 16, weight: .medium) == Font.custom("FixtureUI-Regular", fixedSize: 16).weight(.medium))
    var environment = EnvironmentValues()
    #expect(environment.fleckUIFont == .system)
    environment.fleckUIFont = typography
    #expect(environment.fleckUIFont == typography)
  }

  @Test(arguments: [Font.Weight.regular, .medium, .semibold, .bold])
  func interfaceFontFixedTextPreservesWeightsAndSystemDesign(_ weight: Font.Weight) {
    #expect(
      FleckUIFont.system.font(size: 10, weight: weight, design: .rounded)
        == Font.system(size: 10, weight: weight, design: .rounded)
    )
    #expect(
      FleckUIFont(fontName: "FixtureUI-Regular").font(size: 10, weight: weight, design: .rounded)
        == Font.custom("FixtureUI-Regular", fixedSize: 10).weight(weight)
    )
    #expect(
      FleckUIFont.system.font(.caption).monospacedDigit()
        == Font.system(.caption).monospacedDigit()
    )
  }

  @Test func interfaceFontExplicitTextStylesKeepTheSelectedFamilyAndPreserveStyleExceptions() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let settings = try String(contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"), encoding: .utf8)
    let notes = try String(contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"), encoding: .utf8)

    for style in ["body", "caption", "caption2", "callout", "headline", "footnote", "title2"] {
      #expect(!settings.contains(".font(.\(style)"))
    }
    #expect(settings.contains(".fleckUIFont(.callout, weight: .medium)"))
    #expect(settings.contains(".fleckUIFont(.footnote, weight: .medium)"))
    #expect(settings.contains(".fleckUIFont(.title2, weight: .semibold)"))
    #expect(settings.contains(".font(uiFont.font(size: 10, weight: .bold, design: .rounded))"))
    #expect(settings.contains(".font(uiFont.font(size: 13, weight: isSelected ? .semibold : .regular))"))

    #expect(notes.contains("Text(\"Could not save: \\(error)\")\n                .fleckUIFont(.caption)"))
    #expect(notes.contains("Text(error)\n                .fleckUIFont(.caption)"))
    #expect(notes.contains("Text(\"Fleck needs your help\")\n          .fleckUIFont(.headline)"))
    #expect(notes.contains(".fleckUIFont(.caption, weight: isSave ? .semibold : .medium)"))
    #expect(notes.contains("Text(presentation.statusCopy)\n            .fleckUIFont(.caption)"))
    #expect(notes.contains("Text(\"Smart Capture\")\n                    .fleckUIFont(.headline)"))
    #expect(notes.contains(".font(uiFont.font(.caption).monospacedDigit())"))
    #expect(notes.contains(".font(.caption2.monospaced())"))
    #expect(notes.contains("Image(systemName: \"pin.fill\")\n                    .font(.caption2)"))
    #expect(notes.contains("Image(systemName: \"externaldrive.badge.exclamationmark\")\n          .font(.system(size: 28))"))
    #expect(settings.contains("Image(systemName: systemImage)\n          .font(.system(size: 13, weight: .medium))"))
  }

  @Test func interfaceFontUsesExistingSceneAndPickerSeamsWithoutEditorMutation() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let theme = try String(contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckThemeSnapshot.swift"), encoding: .utf8)
    let settings = try String(contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"), encoding: .utf8)
    let typography = try String(contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckUIFont.swift"), encoding: .utf8)
    let rowStart = try #require(settings.range(of: "        SettingsPreferenceRow(\n          \"Interface font\","))
    let suffix = settings[rowStart.lowerBound...]
    let rowEnd = try #require(suffix.range(of: "        SettingsPreferenceRow(\n          \"Window appearance\","))
    let row = suffix[..<rowEnd.lowerBound]
    #expect(theme.contains(".fleckUIFontFamily(appState.preferences.uiFontFamily)"))
    #expect(row.contains("FontFamilyPicker("))
    #expect(row.contains("appState.updatePreferences { $0.uiFontFamily = family }"))
    #expect(!row.contains("$0.fontFamily"))
    #expect(!row.contains("commands."))
    #expect(settings.contains("(unavailable — using System)"))
    #expect(settings.contains("@ScaledMetric(relativeTo: .body) private var generalTitleSize"))
    #expect(settings.contains("uiFont.font(size: generalTitleSize"))
    #expect(typography.contains(".transformEnvironment(\\.font)"))
    #expect(typography.contains("guard typography.fontName != nil else { return }"))
    #expect(typography.contains("relativeTo: style"))
  }
#endif
