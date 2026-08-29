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

@Test func personalDictionaryV2MigrationCandidatePreservesAllV1Values() throws {
  let entry = PersonalDictionaryEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    preferredForm: "  Flecḱ  ",
    aliases: ["second alias", "first alias"],
    localeIdentifier: "unsupported_SYNTHETIC",
    isPriority: true,
    isEnabled: false,
    origin: .suggested,
    usage: .init(
      useCount: 27,
      lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000.25)
    )
  )
  let suggestion = PersonalDictionarySuggestion(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    preferredForm: "Candidate",
    observedForms: ["second observation", "first observation"],
    localeIdentifier: "unsupported_SYNTHETIC",
    observationCount: 13,
    lastObservedAt: Date(timeIntervalSince1970: 1_700_000_001.5)
  )
  let conflictingEntry = PersonalDictionaryEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
    preferredForm: "second alias",
    localeIdentifier: "unsupported_SYNTHETIC"
  )
  let v1 = PersonalDictionarySnapshot(
    entries: [entry, conflictingEntry],
    suggestions: [suggestion]
  )

  let candidate = try PersonalDictionarySnapshotV2.migrationCandidate(fromV1: v1)

  #expect(candidate.schemaVersion == 2)
  #expect(candidate.revision == 1)
  #expect(PersonalDictionarySnapshot.currentSchemaVersion == 1)
  #expect(v1.schemaVersion == 1)
  #expect(candidate.entries == [entry, conflictingEntry])
  #expect(candidate.suggestions == [suggestion])
  #expect(candidate.entries[0].aliases == ["second alias", "first alias"])
  #expect(candidate.suggestions[0].observedForms == [
    "second observation", "first observation",
  ])
}

@Test func personalDictionaryV2MigrationCandidateRejectsInvalidV1WithoutRepairingIt() {
  let aliases = ["Same Fixture", "same fixture"]
  let invalidV1 = PersonalDictionarySnapshot(entries: [
    PersonalDictionaryEntry(
      preferredForm: "Synthetic Fixture",
      aliases: aliases,
      localeIdentifier: "unsupported_SYNTHETIC"
    )
  ])

  #expect(throws: PersonalDictionaryValidationError.invalidSnapshot([.duplicateAlias])) {
    try PersonalDictionarySnapshotV2.migrationCandidate(fromV1: invalidV1)
  }
  #expect(invalidV1.entries[0].aliases == aliases)
}

@Test func personalDictionaryV2ValuesRejectUnsupportedSchemaWithoutContentLeakage() throws {
  let privateMarker = "SYNTHETIC_PRIVATE_MARKER"
  let empty = PersonalDictionarySnapshotV2()
  let snapshot = PersonalDictionarySnapshotV2(
    schemaVersion: PersonalDictionarySnapshotV2.currentSchemaVersion + 1,
    entries: [PersonalDictionaryEntry(preferredForm: privateMarker)]
  )

  #expect(empty.schemaVersion == 2)
  #expect(empty.revision == 0)
  #expect(empty.entries.isEmpty)
  #expect(empty.suggestions.isEmpty)
  #expect(try JSONDecoder().decode(
    PersonalDictionarySnapshotV2.self,
    from: JSONEncoder().encode(snapshot)
  ) == snapshot)
  #expect(snapshot.validationIssues.map(\.code) == [.unsupportedSchemaVersion])
  #expect(snapshot.validationIssues.allSatisfy {
    !$0.description.contains(privateMarker)
  })
  #expect(throws: PersonalDictionaryValidationError.invalidSnapshot([
    .unsupportedSchemaVersion,
  ])) {
    try snapshot.validate()
  }
}

@Test func personalDictionaryV2ValuesRejectDuplicateEntryAndSuggestionIDs() {
  let entryID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
  let suggestionID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
  let snapshot = PersonalDictionarySnapshotV2(
    entries: [
      PersonalDictionaryEntry(id: entryID, preferredForm: "First"),
      PersonalDictionaryEntry(id: entryID, preferredForm: "Second"),
    ],
    suggestions: [
      PersonalDictionarySuggestion(id: suggestionID, preferredForm: "First"),
      PersonalDictionarySuggestion(id: suggestionID, preferredForm: "Second"),
    ]
  )

  #expect(snapshot.validationIssues.map(\.code) == [
    .duplicateEntryID, .duplicateSuggestionID,
  ])
  #expect(throws: PersonalDictionaryValidationError.invalidSnapshot([
    .duplicateEntryID, .duplicateSuggestionID,
  ])) {
    try snapshot.validate()
  }
}

@Test func personalDictionaryV2RevisionAdvancesByOne() throws {
  let current = PersonalDictionarySnapshotV2(
    revision: 41,
    entries: [PersonalDictionaryEntry(preferredForm: "Synthetic Fixture")]
  )

  let nextRevision: UInt64 = try current.nextRevision()

  #expect(current.revision == 41)
  #expect(nextRevision == 42)
}

@Test func personalDictionaryV2RevisionRejectsOverflow() {
  let maximum = PersonalDictionarySnapshotV2(revision: UInt64.max)

  #expect(throws: PersonalDictionaryRevisionError.overflow) {
    try maximum.nextRevision()
  }
  #expect(maximum.revision == UInt64.max)
}
