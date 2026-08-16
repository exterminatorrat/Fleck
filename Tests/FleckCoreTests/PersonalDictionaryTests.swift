import Foundation
import Testing

@testable import FleckCore

@Test func personalDictionaryEntryValidationUsesStableCodesWithoutEntryContent() {
  let entry = PersonalDictionaryEntry(
    id: UUID(),
    preferredForm: "  secretName  ",
    aliases: ["", "Alias", "alias"],
    localeIdentifier: "en-US",
    isPriority: false,
    isEnabled: true,
    origin: .manual,
    usage: .init(useCount: -1)
  )

  let codes = Set(entry.validationIssues.map(\.code))

  #expect(codes.contains(.blankAlias))
  #expect(codes.contains(.duplicateAlias))
  #expect(codes.contains(.negativeUseCount))
  #expect(entry.validationIssues.allSatisfy { !$0.description.contains("secretName") })
}

@Test func personalDictionarySnapshotRejectsUnsupportedVersionsAndUnboundedUsage() {
  let snapshot = PersonalDictionarySnapshot(
    schemaVersion: PersonalDictionarySnapshot.currentSchemaVersion + 1,
    entries: [
      PersonalDictionaryEntry(
        preferredForm: "Fleck",
        aliases: [],
        localeIdentifier: "en-US",
        usage: .init(useCount: PersonalDictionaryUsage.maximumUseCount + 1)
      )
    ],
    suggestions: []
  )

  let codes = Set(snapshot.validationIssues.map(\.code))

  #expect(codes.contains(.unsupportedSchemaVersion))
  #expect(codes.contains(.useCountExceedsMaximum))
}

@Test func personalDictionaryValuesRoundTripThroughCodable() throws {
  let entry = PersonalDictionaryEntry(
    id: UUID(),
    preferredForm: "camelCase",
    aliases: ["camel case"],
    localeIdentifier: "en-US",
    isPriority: true,
    isEnabled: true,
    origin: .suggested,
    usage: .init(useCount: 3, lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000))
  )
  let suggestion = PersonalDictionarySuggestion(
    id: UUID(),
    preferredForm: "PascalCase",
    observedForms: ["pascal case"],
    localeIdentifier: "en-US",
    observationCount: 2,
    lastObservedAt: Date(timeIntervalSince1970: 1_700_000_001)
  )
  let snapshot = PersonalDictionarySnapshot(
    schemaVersion: PersonalDictionarySnapshot.currentSchemaVersion,
    entries: [entry],
    suggestions: [suggestion]
  )

  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601

  #expect(try decoder.decode(
    PersonalDictionarySnapshot.self,
    from: encoder.encode(snapshot)
  ) == snapshot)
}
