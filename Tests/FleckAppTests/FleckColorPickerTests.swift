import AppKit
import Foundation
import Testing

@testable import FleckApp

@Test func fleckPaletteRetainsTheExistingEightColors() {
  #expect(FleckPaletteOption.all.map(\.name) == [
    "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Gray",
  ])
  #expect(FleckPaletteOption.all.map(\.hex) == [
    "#FF4245", "#FF9230", "#FFD600", "#30D158",
    "#0091FF", "#DB34F2", "#FF375F", "#98989D",
  ])
}

@Test func fleckHexNormalizationAcceptsHashedSixDigitRGB() {
  #expect(FleckColorHex.normalized("#ff4245") == "#FF4245")
  #expect(FleckColorHex.normalized("#0091ff") == "#0091FF")
  #expect(FleckColorHex.normalized("#FF424500") == nil)
  #expect(FleckColorHex.normalized("#FFF") == nil)
  #expect(FleckColorHex.normalized("#GGGGGG") == nil)
  #expect(FleckColorHex.normalized("#12 3456") == nil)
}

@Test func userDraftRequiresHashAndCommitsNormalizedRGBHex() {
  var draft = FleckColorDraft(hex: "#FF4245")

  draft.setHex("0091ff")

  #expect(draft.isHexInvalid)
  #expect(draft.committedHex == nil)

  draft.setHex("#0091ff")

  #expect(!draft.isHexInvalid)
  #expect(draft.committedHex == "#0091FF")
}

@Test func invalidDraftHexDoesNotProduceACommitValue() {
  var draft = FleckColorDraft(hex: "#FF4245")

  draft.setHex("#12345678")

  #expect(draft.isHexInvalid)
  #expect(draft.committedHex == nil)
}

@Test func customDraftHexCommitsOnceAsUppercaseRGB() {
  var draft = FleckColorDraft(hex: "#FF4245")

  draft.setHex("#12ab34")

  #expect(!draft.isHexInvalid)
  #expect(draft.committedHex == "#12AB34")
}

@Test @MainActor func alphaColorsCannotBecomeCommittedRGBHex() {
  let translucent = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.5)

  #expect(FleckColorHex.hex(from: translucent) == nil)
}

@Test func blackWhiteAndSaturatedHSBValuesRoundTripToRGBHex() {
  for hex in ["#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF"] {
    let original = FleckColorDraft(hex: hex)
    var roundTrip = FleckColorDraft(hex: nil)

    roundTrip.setHSB(original.hsb)

    #expect(roundTrip.committedHex == hex)
  }
}

@Test @MainActor func paletteNameMatchingUsesTheNormalizedSRGBColor() throws {
  let red = try #require(NSColor(hex: "#ff4245"))
  let custom = try #require(NSColor(hex: "#123456"))

  #expect(FleckPaletteOption.paletteName(for: red) == "Red")
  #expect(FleckPaletteOption.paletteName(for: custom) == nil)
}

@Test func settingsRemovesDuplicateTypographyAndToolbarControls() throws {
  let source = try fleckSource("Sources/FleckApp/SettingsView.swift")

  #expect(!source.contains("ColorPicker(\""))
  #expect(!source.contains("Picker(\"Font\""))
  #expect(!source.contains("Font size:"))
  #expect(!source.contains("Show formatting bar"))
  #expect(source.contains("FleckColorPicker"))
}

@Test func productionUsesOneFleckPickerWithoutSystemPanelOrColorHistory() throws {
  let picker = try fleckSource("Sources/FleckApp/FleckColorPicker.swift")
  let notes = try fleckSource("Sources/FleckApp/NotesPanel.swift")

  #expect(!picker.contains("SwiftUI.ColorPicker"))
  #expect(!picker.contains("NSColorPanel"))
  #expect(!picker.localizedCaseInsensitiveContains("opacity"))
  #expect(!picker.localizedCaseInsensitiveContains("recent"))
  #expect(notes.contains("FleckColorPicker"))
  #expect(notes.contains("Tab Color..."))
  #expect(notes.contains("Editor toolbar"))
  #expect(!notes.contains("TabColorOption"))
}

private func fleckSource(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}
