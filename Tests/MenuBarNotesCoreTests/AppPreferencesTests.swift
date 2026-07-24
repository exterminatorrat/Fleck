import Foundation
import Testing

@testable import MenuBarNotesCore

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
