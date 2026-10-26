import Foundation
import Testing

@testable import FleckCore

@Test func interfaceFontDefaultsToSystemWithoutChangingEditorDefaults() throws {
  let preferences = AppPreferences()
  #expect(preferences.uiFontFamily == nil)
  #expect(preferences.fontFamily == "Avenir Next")
  #expect(preferences.fontSize == 17)
  let json = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any]
  )
  #expect(json["uiFontFamily"] == nil)
}

@Test(arguments: ["", #", "uiFontFamily": null"#, #", "uiFontFamily": 42"#])
func interfaceFontDecodeIsCompatibleWithOlderAndMalformedOptionalValues(_ field: String) throws {
  let data = Data("{\"fontFamily\":\"Menlo\",\"fontSize\":19\(field)}".utf8)
  let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(preferences.uiFontFamily == nil)
  #expect(preferences.fontFamily == "Menlo")
  #expect(preferences.fontSize == 19)
}

@Test func interfaceFontRoundTripsOnlyTheFamilyAndPreservesEveryOtherPreference() throws {
  let original = AppPreferences(fontFamily: "Menlo", fontSize: 19, showAgentUpdateBanners: false)
  var changed = original
  changed.uiFontFamily = "  Fixture Missing UI  "
  #expect(changed.uiFontFamily == "Fixture Missing UI")
  let data = try JSONEncoder().encode(changed)
  let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(json["uiFontFamily"] as? String == "Fixture Missing UI")
  var decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(decoded.uiFontFamily == "Fixture Missing UI")
  decoded.uiFontFamily = nil
  #expect(decoded == original)
  changed.uiFontFamily = ".AppleSystemUIFont"
  #expect(changed == original)
}

@Test(arguments: ["", " \n ", ".AppleSystemUIFont", "Folder/Font", "Folder\\Font", "Bad\u{0000}Font"])
func interfaceFontRejectsPathsHiddenSystemSentinelsAndControlCharacters(_ family: String) throws {
  #expect(AppPreferences(uiFontFamily: family).uiFontFamily == nil)
  var preferences = AppPreferences(uiFontFamily: "Fixture UI")
  preferences.uiFontFamily = family
  #expect(preferences.uiFontFamily == nil)
  let data = try JSONSerialization.data(withJSONObject: ["uiFontFamily": family])
  #expect(try JSONDecoder().decode(AppPreferences.self, from: data).uiFontFamily == nil)
}
