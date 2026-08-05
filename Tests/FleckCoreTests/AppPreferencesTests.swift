import Foundation
import Testing

@testable import FleckCore

@Test func packageGraphControlsEnhancedCandidateEvaluation() {
  let optedIn = ProcessInfo.processInfo.environment["FLECK_ENHANCED_CANDIDATE"] == "1"
  #expect(CleanDictationFeatures.enhancedLocalCandidateEnabled == optedIn)
}

@Test func dictationPreferencesUseStandardPrivateDefaults() throws {
  let value = AppPreferences()
  #expect(value.dictationSpeechEngine == .standard)
  #expect(value.dictationHistoryEnabled)
  #expect(value.dictationCapsuleEnabled)
  #expect(value.dictationMicrophoneUID == nil)
  let encoded = try JSONEncoder().encode(value)
  let json = try #require(
    JSONSerialization.jsonObject(with: encoded) as? [String: Any]
  )
  #expect(json["dictationShortcut"] != nil)
}

@Test func newPreferencesUseAvenirReadingDefaults() {
  let value = AppPreferences()

  #expect(value.fontFamily == "Avenir Next")
  #expect(value.fontSize == 17)
  #expect(value.editorTypographyVersion == AppPreferences.currentEditorTypographyVersion)
}

@Test func untouchedLegacyTypographyMigratesOnce() throws {
  let data = Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":15}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: data)

  #expect(value.fontFamily == "Avenir Next")
  #expect(value.fontSize == 17)
  #expect(value.editorTypographyVersion == AppPreferences.currentEditorTypographyVersion)
}

@Test func legacyCustomTypographyIsPreserved() throws {
  let family = try JSONDecoder().decode(
    AppPreferences.self,
    from: Data(#"{"fontFamily":"Menlo","fontSize":15}"#.utf8)
  )
  let size = try JSONDecoder().decode(
    AppPreferences.self,
    from: Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":19}"#.utf8)
  )

  #expect(family.fontFamily == "Menlo")
  #expect(family.fontSize == 15)
  #expect(size.fontFamily == ".AppleSystemUIFont")
  #expect(size.fontSize == 19)
}

@Test func explicitSystemChoiceAfterMigrationRoundTrips() throws {
  let value = AppPreferences(
    fontFamily: ".AppleSystemUIFont",
    fontSize: 15,
    editorTypographyVersion: AppPreferences.currentEditorTypographyVersion
  )
  let decoded = try JSONDecoder().decode(
    AppPreferences.self,
    from: JSONEncoder().encode(value)
  )

  #expect(decoded.fontFamily == ".AppleSystemUIFont")
  #expect(decoded.fontSize == 15)
}

@Test func dictationModifierAndDockUsePersistentDefaults() throws {
  let value = AppPreferences()
  #expect(value.dictationModifierKey == .rightOption)
  #expect(value.dictationCapsuleDock == .bottom)

  let roundTrip = try JSONDecoder().decode(
    AppPreferences.self,
    from: JSONEncoder().encode(value)
  )
  #expect(roundTrip.dictationModifierKey == .rightOption)
  #expect(roundTrip.dictationCapsuleDock == .bottom)
}

@Test func oldShortcutPreferencesMigrateToRightOptionAndBottomDock() throws {
  let data = Data(
    #"{"fontFamily":".AppleSystemUIFont","fontSize":15,"dictationShortcut":{"keyCode":49,"carbonModifiers":768}}"#.utf8
  )
  let value = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(value.dictationModifierKey == .rightOption)
  #expect(value.dictationCapsuleDock == .bottom)
}

@Test func dictationModifierChoicesKeepPhysicalSidesDistinct() {
  #expect(DictationModifierKey.allCases == [
    .function,
    .leftCommand,
    .rightCommand,
    .leftOption,
    .rightOption,
    .leftControl,
    .rightControl,
  ])
  #expect(Set(DictationModifierKey.allCases.map(\.displayName)).count == 7)
}

@Test func oldPreferencesDecodeWithDictationDefaults() throws {
  let data = Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":15}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(value.dictationSpeechEngine == .standard)
  #expect(value.dictationHistoryEnabled)
}

@Test func oldPreferencesHaveNoOnboardingMarker() throws {
  let old = Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":15}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: old)
  #expect(value.onboardingProgress == nil)
}

@Test func preferencesDecodeOlderDocumentsWithNewDefaults() throws {
  let old =
    ##"{"fontFamily":"Test","fontSize":14,"accentHex":"#000000","panelOpacity":0.8,"showFormattingBar":true,"automaticLists":true,"shortcuts":[]}"##
    .data(using: .utf8)!
  let preferences = try JSONDecoder().decode(AppPreferences.self, from: old)
  #expect(preferences.theme == .system)
  #expect(preferences.panelWidth == 640)
  #expect(preferences.panelHeight == 430)
  #expect(preferences.editorTextHex == nil)
  #expect(preferences.editorBackgroundHex == nil)
  #expect(!preferences.launchAtLogin)
}

@Test func newPreferencesUseBalancedIndependentPanelDefaults() {
  let value = AppPreferences()
  #expect(value.panelWidth == 640)
  #expect(value.panelHeight == 430)
  #expect(value.pinnedPanelWidth == 640)
  #expect(value.pinnedPanelHeight == 430)
  #expect(value.panelSizingVersion == AppPreferences.currentPanelSizingVersion)
}

@Test func untouchedLegacyPanelSizeMigratesOnce() throws {
  let legacy = Data(#"{"panelWidth":520,"panelHeight":430}"#.utf8)
  let migrated = try JSONDecoder().decode(AppPreferences.self, from: legacy)
  #expect(migrated.panelWidth == 640)
  #expect(migrated.panelHeight == 430)
  #expect(migrated.pinnedPanelWidth == 640)
  #expect(migrated.pinnedPanelHeight == 430)
}

@Test func customLegacyPanelSizeIsPreservedAndUsesIndependentPinnedDefault() throws {
  let legacy = Data(#"{"panelWidth":700,"panelHeight":500}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: legacy)
  #expect(value.panelWidth == 700)
  #expect(value.panelHeight == 500)
  #expect(value.pinnedPanelWidth == 640)
  #expect(value.pinnedPanelHeight == 430)
}

@Test func malformedPanelSizingFieldsFallBackWithoutDiscardingPreferences() throws {
  let malformed = Data(
    #"{"fontFamily":"Menlo","panelWidth":"wide","panelHeight":false,"panelSizingVersion":"current","pinnedPanelWidth":[],"pinnedPanelHeight":{}}"#.utf8
  )
  let value = try JSONDecoder().decode(AppPreferences.self, from: malformed)

  #expect(value.fontFamily == "Menlo")
  #expect(value.panelWidth == 640)
  #expect(value.panelHeight == 430)
  #expect(value.panelSizingVersion == AppPreferences.currentPanelSizingVersion)
  #expect(value.pinnedPanelWidth == 640)
  #expect(value.pinnedPanelHeight == 430)
}

@Test func unrelatedMalformedPreferenceFieldStillThrows() {
  let malformed = Data(#"{"panelWidth":"wide","showFormattingBar":"yes"}"#.utf8)

  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(AppPreferences.self, from: malformed)
  }
}

@Test func explicitLegacyWidthAfterSizingMigrationRoundTrips() throws {
  let value = AppPreferences(panelWidth: 520, panelHeight: 430)
  let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(value))
  #expect(decoded.panelWidth == 520)
  #expect(decoded.panelHeight == 430)
}

@Test func pinnedAndMenuPanelSizesRoundTripIndependently() throws {
  let value = AppPreferences(
    panelWidth: 640,
    panelHeight: 430,
    pinnedPanelWidth: 760,
    pinnedPanelHeight: 540
  )
  let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(value))
  #expect(decoded.panelWidth == 640)
  #expect(decoded.panelHeight == 430)
  #expect(decoded.pinnedPanelWidth == 760)
  #expect(decoded.pinnedPanelHeight == 540)
}

@Test func panelDimensionsClampToTheirSupportedMinimumsAndMenuMaximums() {
  let value = AppPreferences(
    panelWidth: 12,
    panelHeight: 9_000,
    pinnedPanelWidth: 1,
    pinnedPanelHeight: 2
  )
  #expect(value.panelWidth == 380)
  #expect(value.panelHeight == 800)
  #expect(value.pinnedPanelWidth == 480)
  #expect(value.pinnedPanelHeight == 320)
}

@Test func shortcutsNormalizeAndDetectConflicts() {
  let first = Shortcut(action: .newNote, key: " T ", modifiers: ["shift", "command", "bogus"])
  let second = Shortcut(action: .closeNote, key: "t", modifiers: ["command", "shift"])
  #expect(first.key == "t")
  #expect(first.modifiers == ["command", "shift"])
  #expect(Shortcut.conflicts(in: [first, second]) == [.newNote, .closeNote])
}

@Test func shortcutWithoutModifierIsInvalid() {
  #expect(!Shortcut(action: .newNote, key: "t", modifiers: []).isValid)
  #expect(Shortcut(action: .newNote, key: nil, modifiers: []).isValid)
}
