import Foundation
import Testing

@testable import FleckCore

@Suite struct CompiledPersonalDictionaryTests {
  @Test func compilerRejectsInvalidSnapshotWithoutContentLeakage() {
    let privateTerm = "private customer term"
    let snapshot = PersonalDictionarySnapshotV2(
      entries: [compiledEntry(1, preferredForm: privateTerm, aliases: [" "])]
    )

    do {
      _ = try CompiledPersonalDictionary.compile(snapshot)
      Issue.record("Expected invalid snapshot rejection")
    } catch {
      #expect(error as? PersonalDictionaryResolverError == .invalidEntries)
      #expect(!String(describing: error).contains(privateTerm))
    }
  }

  @Test func compilerProducesAllProductsForSafeClaims() throws {
    let fleckID = compiledID(1)
    let openAIID = compiledID(2)
    let compiled = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        revision: 7,
        entries: [
          compiledEntry(fleckID, preferredForm: "FleckApp", aliases: ["fleck app"]),
          compiledEntry(
            openAIID,
            preferredForm: "OpenAI",
            aliases: ["open_ai", "Open-AI"],
            priority: true
          ),
        ]
      )
    )

    #expect(compiled.revision == 7)
    #expect(compiled.localeIdentifier == "en-US")
    #expect(compiled.compilerPolicyRevision == 1)
    #expect(compiled.contentDigest.count == 64)
    #expect(compiled.contentDigest.allSatisfy { "0123456789abcdef".contains($0) })
    #expect(compiled.recognitionStrings == ["OpenAI", "Open-AI", "open_ai", "FleckApp", "fleck app"])
    #expect(compiled.protectedLexicon == ["FleckApp", "OpenAI"])
    #expect(
      compiled.routingLexicon == [
        .init(exactForm: "fleck app", canonicalClaim: "fleck app", entryID: fleckID),
        .init(exactForm: "FleckApp", canonicalClaim: "fleckapp", entryID: fleckID),
        .init(exactForm: "Open-AI", canonicalClaim: "open-ai", entryID: openAIID),
        .init(exactForm: "open_ai", canonicalClaim: "open_ai", entryID: openAIID),
        .init(exactForm: "OpenAI", canonicalClaim: "openai", entryID: openAIID),
      ]
    )
    #expect(compiled.diagnostics.isEmpty)
  }

  @Test func compilerExcludesPreferredAndAliasCollisionMatrixFromEveryProduct() throws {
    let preferredOwnerID = compiledID(3)
    let competingAliasOwnerID = compiledID(4)
    let leftID = compiledID(5)
    let rightID = compiledID(6)
    let compiled = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        entries: [
          compiledEntry(1, preferredForm: "Acme", aliases: ["a one"]),
          compiledEntry(2, preferredForm: "ACME", aliases: ["a two"]),
          compiledEntry(preferredOwnerID, preferredForm: "FleckApp"),
          compiledEntry(
            competingAliasOwnerID,
            preferredForm: "Other",
            aliases: ["fleckapp", "different"]
          ),
          compiledEntry(leftID, preferredForm: "Left", aliases: ["shared"]),
          compiledEntry(rightID, preferredForm: "Right", aliases: ["SHARED"]),
        ]
      )
    )

    #expect(!compiled.recognitionStrings.contains("Acme"))
    #expect(!compiled.recognitionStrings.contains("ACME"))
    #expect(!compiled.recognitionStrings.contains("a one"))
    #expect(!compiled.recognitionStrings.contains("a two"))
    #expect(!compiled.recognitionStrings.contains("fleckapp"))
    #expect(!compiled.recognitionStrings.contains("shared"))
    #expect(!compiled.recognitionStrings.contains("SHARED"))
    #expect(compiled.protectedLexicon == ["FleckApp", "Left", "Other", "Right"])
    #expect(!compiled.routingLexicon.contains { $0.exactForm == "fleckapp" })
    #expect(!compiled.routingLexicon.contains { $0.exactForm.lowercased() == "shared" })
    #expect(!compiled.routingLexicon.contains { $0.entryID == compiledID(1) || $0.entryID == compiledID(2) })
    #expect(
      compiled.diagnostics == [
        .init(code: .aliasPreferredCollision, count: 1),
        .init(code: .ambiguousAlias, count: 1),
        .init(code: .duplicatePreferredOwner, count: 1),
      ]
    )
  }

  @Test func compilerExcludesCyclesAndKeepsIndependentSafeClaims() throws {
    let alphaID = compiledID(1)
    let betaID = compiledID(2)
    let gammaID = compiledID(3)
    let compiled = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        revision: 9,
        entries: [
          compiledEntry(alphaID, preferredForm: "Alpha", aliases: ["Beta"]),
          compiledEntry(betaID, preferredForm: "Beta", aliases: ["Alpha"]),
          compiledEntry(gammaID, preferredForm: "Gamma", aliases: ["gamma term"]),
        ]
      )
    )

    #expect(Set(compiled.recognitionStrings) == ["Alpha", "Beta", "Gamma", "gamma term"])
    #expect(compiled.routingLexicon.filter { $0.canonicalClaim == "alpha" }.map(\.entryID) == [alphaID])
    #expect(compiled.routingLexicon.filter { $0.canonicalClaim == "beta" }.map(\.entryID) == [betaID])
    #expect(compiled.diagnostics == [.init(code: .aliasPreferredCollision, count: 2)])

    let resolution = PersonalDictionaryResolver.resolve("alpha beta gamma term", compiled: compiled)
    #expect(resolution.baseline == "Alpha Beta Gamma")
    #expect(resolution.appliedEntryIDs == [alphaID, betaID, gammaID])
  }

  @Test func compilerCanonicalizesUnicodeButPreservesPunctuationAndUnderscores() throws {
    let decomposedCafe = "Cafe\u{301}"
    let decomposed = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        entries: [
          compiledEntry(1, preferredForm: "  \(decomposedCafe)  ", aliases: ["CAFÉ"]),
          compiledEntry(2, preferredForm: "snake_case", aliases: ["snake-case"]),
        ]
      )
    )
    let precomposed = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        revision: 99,
        entries: [
          compiledEntry(2, preferredForm: "snake_case", aliases: ["snake-case"]),
          compiledEntry(1, preferredForm: "Café", aliases: ["CAFÉ"]),
        ]
      )
    )

    #expect(decomposed.recognitionStrings.contains("Café"))
    #expect(decomposed.recognitionStrings.first?.unicodeScalars.map(\.value) == [67, 97, 102, 233])
    #expect(decomposed.recognitionStrings.contains("snake_case"))
    #expect(decomposed.recognitionStrings.contains("snake-case"))
    #expect(decomposed.routingLexicon.contains { $0.canonicalClaim == "café" })
    #expect(decomposed.routingLexicon.contains { $0.canonicalClaim == "snake_case" })
    #expect(decomposed.routingLexicon.contains { $0.canonicalClaim == "snake-case" })
    #expect(decomposed.contentDigest == precomposed.contentDigest)
  }

  @Test func compilerRecognitionRankingIsDeterministicAndTruncatesAt100() throws {
    let entries = (0..<102).map { value in
      compiledEntry(
        value + 1,
        preferredForm: String(format: "term%03d", value),
        priority: value == 101,
        usage: .init(useCount: value)
      )
    }

    let first = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(entries: entries)
    )
    let second = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(revision: 41, entries: entries.reversed())
    )

    #expect(first.recognitionStrings.count == 100)
    #expect(first.recognitionStrings.prefix(3) == ["term101", "term100", "term099"])
    #expect(!first.recognitionStrings.contains("term000"))
    #expect(!first.recognitionStrings.contains("term001"))
    #expect(first.recognitionStrings == second.recognitionStrings)
    #expect(first.contentDigest == second.contentDigest)
    #expect(first.diagnostics == [.init(code: .recognitionTruncated, count: 2)])
  }

  @Test func compilerDigestIgnoresEntryAliasOrderLocalRevisionAndIneffectiveEntries() throws {
    let effective = [
      compiledEntry(1, preferredForm: "FleckApp", aliases: ["fleck app", "fleck_app"]),
      compiledEntry(2, preferredForm: "OpenAI", aliases: ["open ai"]),
    ]
    let first = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(revision: 1, entries: effective)
    )
    let second = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        revision: 987,
        entries: [
          compiledEntry(9, preferredForm: "Disabled Secret", enabled: false),
          compiledEntry(8, preferredForm: "Unsupported Secret", locale: "fr-CA"),
          compiledEntry(2, preferredForm: "OpenAI", aliases: ["open ai"]),
          compiledEntry(1, preferredForm: "FleckApp", aliases: ["fleck_app", "fleck app"]),
        ],
        suggestions: [
          PersonalDictionarySuggestion(
            preferredForm: "Suggestion Secret",
            observedForms: ["secret"],
            observationCount: 1
          )
        ]
      )
    )

    #expect(first.contentDigest == second.contentDigest)
    #expect(first.recognitionStrings == second.recognitionStrings)
    #expect(first.protectedLexicon == second.protectedLexicon)
    #expect(first.routingLexicon == second.routingLexicon)
  }

  @Test func compilerOmitsDisabledAndUnsupportedLocaleClaims() throws {
    let effectiveOnly = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(entries: [compiledEntry(1, preferredForm: "Active")])
    )
    let compiled = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        entries: [
          compiledEntry(1, preferredForm: "Active"),
          compiledEntry(2, preferredForm: "Disabled", aliases: ["disabled alias"], enabled: false),
          compiledEntry(3, preferredForm: "British", aliases: ["british alias"], locale: "en-GB"),
          compiledEntry(4, preferredForm: "Both", locale: "zh-CN", enabled: false),
        ]
      )
    )

    #expect(compiled.recognitionStrings == ["Active"])
    #expect(compiled.protectedLexicon == ["Active"])
    #expect(compiled.routingLexicon == [.init(exactForm: "Active", canonicalClaim: "active", entryID: compiledID(1))])
    #expect(
      compiled.diagnostics == [
        .init(code: .disabledEntry, count: 2),
        .init(code: .unsupportedLocaleEntry, count: 2),
      ]
    )
    #expect(compiled.contentDigest == effectiveOnly.contentDigest)
  }

  @Test func compilerRoutingLexiconMapsSafeFormsToOneEntryIdentity() throws {
    let entryID = compiledID(42)
    let compiled = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        entries: [
          compiledEntry(
            entryID,
            preferredForm: "FleckApp",
            aliases: ["fleck app", "fleck_app", "fleckapp"]
          )
        ]
      )
    )

    #expect(
      compiled.routingLexicon == [
        .init(exactForm: "fleck app", canonicalClaim: "fleck app", entryID: entryID),
        .init(exactForm: "fleck_app", canonicalClaim: "fleck_app", entryID: entryID),
        .init(exactForm: "FleckApp", canonicalClaim: "fleckapp", entryID: entryID),
      ]
    )
    #expect(Set(compiled.routingLexicon.map(\.entryID)) == [entryID])
  }

  @Test func compilerDiagnosticsContainOnlyStableCodesAndCounts() throws {
    let privateUUID = compiledID(91)
    let privateTerm = "ConfidentialTerm"
    let compiled = try CompiledPersonalDictionary.compile(
      PersonalDictionarySnapshotV2(
        entries: [
          compiledEntry(privateUUID, preferredForm: privateTerm, aliases: ["secret collision"]),
          compiledEntry(92, preferredForm: privateTerm.uppercased(), aliases: ["other private"]),
          compiledEntry(93, preferredForm: "Disabled Private", enabled: false),
          compiledEntry(94, preferredForm: "Locale Private", locale: "de-DE"),
        ]
      )
    )

    let reflected = String(reflecting: compiled.diagnostics)
    #expect(compiled.diagnostics.map(\.count) == [1, 1, 1])
    #expect(!reflected.contains(privateTerm))
    #expect(!reflected.contains("secret collision"))
    #expect(!reflected.contains(privateUUID.uuidString))
  }
}

private func compiledID(_ value: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
}

private func compiledEntry(
  _ value: Int,
  preferredForm: String,
  aliases: [String] = [],
  locale: String = "en-US",
  priority: Bool = false,
  enabled: Bool = true,
  usage: PersonalDictionaryUsage = .init()
) -> PersonalDictionaryEntry {
  compiledEntry(
    compiledID(value),
    preferredForm: preferredForm,
    aliases: aliases,
    locale: locale,
    priority: priority,
    enabled: enabled,
    usage: usage
  )
}

private func compiledEntry(
  _ id: UUID,
  preferredForm: String,
  aliases: [String] = [],
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
