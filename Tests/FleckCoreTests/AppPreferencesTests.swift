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
  #expect(!value.dictationShortcut.isEnabled)
  #expect(value.dictationHistoryEnabled)
  #expect(value.dictationCapsuleEnabled)
  #expect(value.dictationMicrophoneUID == nil)
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

@Test func preferencesDecodeOlderDocumentsWithNewDefaults() throws {
  let old =
    ##"{"fontFamily":"Test","fontSize":14,"accentHex":"#000000","panelOpacity":0.8,"showFormattingBar":true,"automaticLists":true,"shortcuts":[]}"##
    .data(using: .utf8)!
  let preferences = try JSONDecoder().decode(AppPreferences.self, from: old)
  #expect(preferences.theme == .system)
  #expect(preferences.panelWidth == 520)
  #expect(preferences.panelHeight == 430)
  #expect(preferences.editorTextHex == nil)
  #expect(preferences.editorBackgroundHex == nil)
  #expect(!preferences.launchAtLogin)
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
