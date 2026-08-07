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
  #expect(result.protectedForms.isEmpty)
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
  #expect(result.protectedForms == ["New York", "York", "App"])
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
