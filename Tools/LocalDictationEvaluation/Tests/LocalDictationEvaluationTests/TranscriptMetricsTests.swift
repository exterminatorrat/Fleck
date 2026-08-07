import Testing
@testable import LocalDictationEvaluation

@Suite("TranscriptMetricsTests")
struct TranscriptMetricsTests {

@Test func emptyEnglishInputsHaveZeroErrorRate() {
  let counts = TranscriptMetrics.englishWordErrorRate(
    reference: "",
    hypothesis: ""
  )
  #expect(counts == EditCounts(
    substitutions: 0,
    deletions: 0,
    insertions: 0,
    referenceUnits: 0
  ))
  #expect(counts.errorRate == 0)
}

@Test func nonemptyHypothesisWithEmptyReferenceHasUnitErrorRate() {
  let counts = TranscriptMetrics.englishWordErrorRate(
    reference: "",
    hypothesis: "one two"
  )
  #expect(counts.insertions == 2)
  #expect(counts.referenceUnits == 0)
  #expect(counts.errorRate == 1)
}

@Test func englishCountsSubstitutionDeletionAndInsertionWithStableTieBreaks() {
  let substitution = TranscriptMetrics.englishWordErrorRate(
    reference: "alpha beta",
    hypothesis: "alpha gamma"
  )
  #expect(substitution == EditCounts(
    substitutions: 1,
    deletions: 0,
    insertions: 0,
    referenceUnits: 2
  ))

  let deletion = TranscriptMetrics.englishWordErrorRate(
    reference: "alpha beta",
    hypothesis: "alpha"
  )
  #expect(deletion == EditCounts(
    substitutions: 0,
    deletions: 1,
    insertions: 0,
    referenceUnits: 2
  ))

  let insertion = TranscriptMetrics.englishWordErrorRate(
    reference: "alpha",
    hypothesis: "alpha beta"
  )
  #expect(insertion == EditCounts(
    substitutions: 0,
    deletions: 0,
    insertions: 1,
    referenceUnits: 1
  ))
}

@Test func englishNormalizationIsLocaleStableAndPunctuationInsensitive() {
  let counts = TranscriptMetrics.englishWordErrorRate(
    reference: "Commit camelCase, now!",
    hypothesis: "commit CAMELCASE now"
  )
  #expect(counts.errorRate == 0)
  #expect(TranscriptMetrics.englishWords("Commit camelCase, now!") == [
    "commit", "camelcase", "now"
  ])
  #expect(TranscriptMetrics.protectedDeveloperTerms(
    "Commit camelCase, PascalCase, snake_case, now!"
  ) == ["camelCase", "PascalCase", "snake_case"])
}

@Test func mandarinUsesCharactersAndRemovesWhitespaceAndPunctuation() {
  let counts = TranscriptMetrics.mandarinCharacterErrorRate(
    reference: "你好，世界",
    hypothesis: "你 好 世界。"
  )
  #expect(counts == EditCounts(
    substitutions: 0,
    deletions: 0,
    insertions: 0,
    referenceUnits: 4
  ))
  #expect(TranscriptMetrics.mandarinCharacters("你 好，世界。") == [
    "你", "好", "世", "界"
  ])
}

@Test func mixedLanguageMetricsRemainSeparate() {
  let english = TranscriptMetrics.englishWordErrorRate(
    reference: "deploy Fleck",
    hypothesis: "deploy Fleck"
  )
  let mandarin = TranscriptMetrics.mandarinCharacterErrorRate(
    reference: "到生产",
    hypothesis: "到生产"
  )
  #expect(english.errorRate == 0)
  #expect(mandarin.errorRate == 0)
  #expect(english.referenceUnits == 2)
  #expect(mandarin.referenceUnits == 3)
}

@Test func nearestRankPercentileHasDeterministicEdges() {
  let values = [10.0, 30.0, 20.0, 40.0]
  #expect(TranscriptMetrics.percentile(0, values: values) == 10)
  #expect(TranscriptMetrics.percentile(50, values: values) == 20)
  #expect(TranscriptMetrics.percentile(95, values: values) == 40)
  #expect(TranscriptMetrics.percentile(100, values: values) == 40)
  #expect(TranscriptMetrics.percentile(50, values: []) == nil)
  #expect(TranscriptMetrics.percentile(.nan, values: values) == nil)
}
}
