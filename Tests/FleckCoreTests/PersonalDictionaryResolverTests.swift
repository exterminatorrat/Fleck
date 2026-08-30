import Foundation
import Testing

@testable import FleckCore

@Test func resolverLeavesAmbiguousAliasesUnchanged() throws {
  let entries = [
    dictionaryEntry(preferredForm: "Acme", aliases: ["acme"]),
    dictionaryEntry(preferredForm: "ACME", aliases: ["ACME"]),
  ]

  let result = try PersonalDictionaryResolver.resolve("acme ACME", entries: entries)

  #expect(result.baseline == "acme ACME")
  #expect(result.protectedForms == ["ACME"])
  #expect(result.replacements == 0)
}

@Test func resolverUsesLongestAliasFirstAndPreservesSafePunctuationBoundaries() throws {
  let entries = [
    dictionaryEntry(preferredForm: "New York", aliases: ["new york"]),
    dictionaryEntry(preferredForm: "York", aliases: ["york"]),
    dictionaryEntry(preferredForm: "App", aliases: ["app"]),
  ]

  let result = try PersonalDictionaryResolver.resolve(
    "new york york app.app application _app app_ app2 (app)",
    entries: entries
  )

  #expect(
    result.baseline
      == "New York York App.App application _app app_ app2 (App)"
  )
  #expect(result.replacements == 5)
  #expect(result.protectedForms == ["New York", "York", "York", "App", "App", "App"])
}

@Test func resolverHandlesIdentifierCasingMandarinAndDisabledEntries() throws {
  let entries = [
    dictionaryEntry(preferredForm: "camelCase", aliases: ["camel case"]),
    dictionaryEntry(preferredForm: "小明", aliases: ["小 名"]),
    dictionaryEntry(preferredForm: "Disabled", aliases: ["disabled"], enabled: false),
  ]

  let result = try PersonalDictionaryResolver.resolve(
    "Camel Case 小 名 disabled",
    entries: entries
  )

  #expect(result.baseline == "camelCase 小明 disabled")
  #expect(result.replacements == 2)
  #expect(result.protectedForms == ["camelCase", "小明"])
}

@Test func resolverLeavesShorterUniqueAliasInsideAmbiguousLongerAliasUnchanged() throws {
  let entries = [
    dictionaryEntry(preferredForm: "NewYork", aliases: ["new york"]),
    dictionaryEntry(preferredForm: "NewYorkAlt", aliases: ["NEW YORK"]),
    dictionaryEntry(preferredForm: "York", aliases: ["york"]),
  ]

  let result = try PersonalDictionaryResolver.resolve("new york", entries: entries)

  #expect(result.baseline == "new york")
  #expect(result.replacements == 0)
  #expect(result.protectedForms.isEmpty)
}

@Test func resolverReplacesUniqueAliasOutsideAmbiguousLongerAliasSpan() throws {
  let entries = [
    dictionaryEntry(preferredForm: "NewYork", aliases: ["new york"]),
    dictionaryEntry(preferredForm: "NewYorkAlt", aliases: ["NEW YORK"]),
    dictionaryEntry(preferredForm: "York", aliases: ["york"]),
  ]

  let result = try PersonalDictionaryResolver.resolve(
    "new york then york",
    entries: entries
  )

  #expect(result.baseline == "new york then York")
  #expect(result.replacements == 1)
  #expect(result.protectedForms == ["York"])
}

@Test func resolverProtectsAlreadyCorrectPreferredFormsWithoutReplacements() throws {
  let result = try PersonalDictionaryResolver.resolve(
    "Ship FleckApp today",
    entries: [dictionaryEntry(preferredForm: "FleckApp", aliases: ["fleck app"])]
  )

  #expect(result.baseline == "Ship FleckApp today")
  #expect(result.replacements == 0)
  #expect(result.protectedForms == ["FleckApp"])
}

@Test func resolverProtectsEachRepeatedPreferredOccurrence() throws {
  let result = try PersonalDictionaryResolver.resolve(
    "fleck app and fleck app",
    entries: [dictionaryEntry(preferredForm: "FleckApp", aliases: ["fleck app"])]
  )

  #expect(result.baseline == "FleckApp and FleckApp")
  #expect(result.protectedForms == ["FleckApp", "FleckApp"])
  #expect(!PersonalDictionaryResolver.cleanupPreserves(result.protectedForms, in: "FleckApp"))
  #expect(PersonalDictionaryResolver.cleanupPreserves(result.protectedForms, in: result.baseline))
}

@Test func resolverProtectsOnlySafeExactPreferredOccurrences() throws {
  let result = try PersonalDictionaryResolver.resolve(
    "myFleckApp FleckApp FleckAppish",
    entries: [dictionaryEntry(preferredForm: "FleckApp", aliases: ["fleck app"])]
  )

  #expect(result.baseline == "myFleckApp FleckApp FleckAppish")
  #expect(result.protectedForms == ["FleckApp"])
}

@Test func resolverProtectedFormsRequireExactSafeSpelling() {
  #expect(
    PersonalDictionaryResolver.cleanupPreserves(
      ["PascalCase", "snake_case"],
      in: "Use PascalCase and snake_case"
    )
  )
  #expect(
    !PersonalDictionaryResolver.cleanupPreserves(
      ["PascalCase"],
      in: "Use pascalcase"
    )
  )
  #expect(
    !PersonalDictionaryResolver.cleanupPreserves(
      ["PascalCase"],
      in: "Use PascalCaseValue"
    )
  )
}

@Test func resolverContextRankingIsDeterministicAndBounded() {
  let recent = Date(timeIntervalSince1970: 1_700_000_100)
  let older = Date(timeIntervalSince1970: 1_700_000_000)
  let entries = [
    dictionaryEntry(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      preferredForm: "zeta",
      aliases: ["z"],
      priority: false,
      usage: .init(useCount: 9, lastUsedAt: recent)
    ),
    dictionaryEntry(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      preferredForm: "Alpha",
      aliases: ["alpha", "A"],
      priority: true,
      usage: .init(useCount: 1, lastUsedAt: older)
    ),
    dictionaryEntry(
      preferredForm: "中文",
      aliases: ["中文别名"],
      locale: "zh-CN",
      usage: .init(useCount: 100, lastUsedAt: recent)
    ),
  ]

  let first = PersonalDictionaryResolver.contextualStrings(
    entries: entries,
    locale: Locale(identifier: "en-US"),
    limit: 4
  )
  let second = PersonalDictionaryResolver.contextualStrings(
    entries: entries.shuffled(),
    locale: Locale(identifier: "en-GB"),
    limit: 4
  )

  #expect(first == ["Alpha", "alpha", "A", "zeta"])
  #expect(second == first)
  #expect(PersonalDictionaryResolver.contextualStrings(entries: entries, locale: .current, limit: 0).isEmpty)
}

@Test func resolverCompiledIndexPreservesLegacyBoundaryAndLongestFirstBehavior() throws {
  let newYorkID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
  let yorkID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
  let appID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
  let compiled = try CompiledPersonalDictionary.compile(
    PersonalDictionarySnapshotV2(
      entries: [
        dictionaryEntry(id: newYorkID, preferredForm: "New York", aliases: ["new york"]),
        dictionaryEntry(id: yorkID, preferredForm: "York", aliases: ["york"]),
        dictionaryEntry(id: appID, preferredForm: "App", aliases: ["app"]),
      ]
    )
  )

  let result = PersonalDictionaryResolver.resolve(
    "new york york app.app application _app app_ app2 (app)",
    compiled: compiled
  )

  #expect(result.baseline == "New York York App.App application _app app_ app2 (App)")
  #expect(result.replacements == 5)
  #expect(result.protectedForms == ["New York", "York", "York", "App", "App", "App"])
  #expect(result.appliedEntryIDs == [newYorkID, yorkID, appID, appID, appID])
}

@Test func resolverCompiledIndexShieldsNestedAliasInsideUnsafeLongerOccurrence() throws {
  let compiled = try CompiledPersonalDictionary.compile(
    PersonalDictionarySnapshotV2(
      entries: [
        dictionaryEntry(preferredForm: "NewYork", aliases: ["new york"]),
        dictionaryEntry(preferredForm: "NewYorkAlt", aliases: ["NEW YORK"]),
        dictionaryEntry(preferredForm: "York", aliases: ["york"]),
      ]
    )
  )

  let result = PersonalDictionaryResolver.resolve("new york", compiled: compiled)

  #expect(result.baseline == "new york")
  #expect(result.replacements == 0)
  #expect(result.protectedForms.isEmpty)
  #expect(result.appliedEntryIDs.isEmpty)
}

@Test func resolverCompiledResolutionReturnsPinnedIdentityAndAppliedEntryIDs() throws {
  let fleckID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
  let openAIID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
  let entries = [
    dictionaryEntry(id: fleckID, preferredForm: "FleckApp", aliases: ["fleck app"]),
    dictionaryEntry(id: openAIID, preferredForm: "OpenAI", aliases: ["open ai"]),
  ]
  let compiled = try CompiledPersonalDictionary.compile(
    PersonalDictionarySnapshotV2(revision: 42, entries: entries)
  )

  let result = PersonalDictionaryResolver.resolve(
    "open ai then fleck app then open ai",
    compiled: compiled
  )
  let noReplacement = PersonalDictionaryResolver.resolve("nothing to replace", compiled: compiled)
  let legacy = try PersonalDictionaryResolver.resolve("nothing to replace", entries: entries)

  #expect(result.dictionaryRevision == 42)
  #expect(result.dictionaryContentDigest == compiled.contentDigest)
  #expect(result.appliedEntryIDs == [openAIID, fleckID, openAIID])
  #expect(noReplacement.dictionaryRevision == 42)
  #expect(noReplacement.dictionaryContentDigest == compiled.contentDigest)
  #expect(noReplacement.appliedEntryIDs.isEmpty)
  #expect(legacy.dictionaryRevision == nil)
  #expect(legacy.dictionaryContentDigest == nil)
  #expect(legacy.appliedEntryIDs.isEmpty)
}

private func dictionaryEntry(
  id: UUID = UUID(),
  preferredForm: String,
  aliases: [String],
  locale: String = "en-US",
  priority: Bool = false,
  enabled: Bool = true,
  usage: PersonalDictionaryUsage = .init()
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: id,
    preferredForm: preferredForm,
    aliases: aliases,
    localeIdentifier: locale,
    isPriority: priority,
    isEnabled: enabled,
    origin: .manual,
    usage: usage
  )
}
