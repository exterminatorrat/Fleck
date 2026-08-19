import FleckModelEvaluation
import Foundation
import Testing

@Test func scoresEnglishMandarinAndMixedInputsFromLiteralExpectations() throws {
  let report = try ModelEvaluationScorer.score(
    .init(
      schemaVersion: 1,
      modelID: "fixture-asr",
      revision: "0123456789abcdef",
      runtime: "fixture-runtime",
      quantization: "none",
      hardware: "fixture-mac",
      unexpectedNetworkConnectionCount: 0,
      cases: [
        .init(
          id: "en-1",
          language: .english,
          reference: "send the report now",
          hypothesis: "send report now",
          protectedExpectations: [],
          timing: .init(
            isCold: false,
            firstPartialMilliseconds: 100,
            stopToFinalMilliseconds: 200,
            stopToInsertionMilliseconds: 300
          ),
          peakResidentBytes: 1_000
        ),
        .init(
          id: "zh-1",
          language: .mandarin,
          reference: "今天开会",
          hypothesis: "今天会议",
          protectedExpectations: [],
          timing: nil,
          peakResidentBytes: nil
        ),
        .init(
          id: "mixed-1",
          language: .mixed,
          reference: "请 send 2 invoices",
          hypothesis: "请 send 3 invoices",
          protectedExpectations: [
            .init(kind: "number", text: "2", comparison: .exact)
          ],
          timing: nil,
          peakResidentBytes: nil
        ),
      ]
    ))

  #expect(
    report.languageMetrics == [
      .init(language: .english, edits: 1, referenceUnits: 4),
      .init(language: .mandarin, edits: 2, referenceUnits: 4),
      .init(language: .mixed, edits: 1, referenceUnits: 4),
    ])
  #expect(report.protectedViolations.map(\.caseID) == ["mixed-1"])
  #expect(report.languageMetrics[0].errorRate == 0.25)
}

@Test func keepsEnglishApostrophesAndIgnoresCaseAndPunctuation() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "english-formatting",
        language: .english,
        reference: "Don't stop, Alex!",
        hypothesis: "don't stop alex",
        protectedExpectations: []
      )
    ]))

  #expect(
    report.languageMetrics == [
      .init(language: .english, edits: 0, referenceUnits: 3)
    ])
}

@Test func excludesWhitespaceAndPunctuationFromMandarinCharacterError() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "mandarin-formatting",
        language: .mandarin,
        reference: "今天， 开会。",
        hypothesis: "今天开会",
        protectedExpectations: []
      )
    ]))

  #expect(
    report.languageMetrics == [
      .init(language: .mandarin, edits: 0, referenceUnits: 4)
    ])
}

@Test func countsEachHanGraphemeAsOneMixedLanguageToken() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "mixed-graphemes",
        language: .mixed,
        reference: "我 send invoices",
        hypothesis: "我 send invoices",
        protectedExpectations: []
      )
    ]))

  #expect(
    report.languageMetrics == [
      .init(language: .mixed, edits: 0, referenceUnits: 3)
    ])
}

@Test func aggregatesInsertionDeletionSubstitutionAndEmptyHypothesisEdits() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "insertion",
        language: .english,
        reference: "a b",
        hypothesis: "a x b",
        protectedExpectations: []
      ),
      .init(
        id: "deletion",
        language: .english,
        reference: "a b",
        hypothesis: "a",
        protectedExpectations: []
      ),
      .init(
        id: "empty-hypothesis",
        language: .english,
        reference: "a b",
        hypothesis: "",
        protectedExpectations: []
      ),
    ]))

  #expect(
    report.languageMetrics == [
      .init(language: .english, edits: 4, referenceUnits: 6)
    ])
}

@Test func rejectsUnsupportedSchemaVersion() {
  expectError(.unsupportedSchemaVersion(2), input: validInput(schemaVersion: 2))
}

@Test func rejectsEmptyModelIdentityRevisionAndRuntime() {
  expectError(.emptyModelID, input: validInput(modelID: " "))
  expectError(.emptyRevision, input: validInput(revision: "\n"))
  expectError(.emptyRuntime, input: validInput(runtime: ""))
}

@Test func rejectsEmptyQuantizationAndHardwareMetadata() {
  expectError(.emptyQuantization, input: validInput(quantization: " "))
  expectError(.emptyHardware, input: validInput(hardware: "\n"))
}

@Test func rejectsEmptyCaseArray() {
  expectError(.emptyCases, input: validInput(cases: []))
}

@Test func rejectsEmptyAndDuplicateCaseIDs() {
  expectError(
    .emptyCaseID,
    input: validInput(cases: [
      .init(id: "  ", language: .english, reference: "a", hypothesis: "")
    ])
  )
  expectError(
    .duplicateCaseID("same"),
    input: validInput(cases: [
      .init(id: "same", language: .english, reference: "a", hypothesis: ""),
      .init(id: "same", language: .english, reference: "b", hypothesis: ""),
    ])
  )
}

@Test func rejectsEmptyReferencesAndProtectedFields() {
  expectError(
    .emptyReference("case"),
    input: validInput(cases: [
      .init(id: "case", language: .english, reference: "\t", hypothesis: "")
    ])
  )
  expectError(
    .emptyProtectedKind("case"),
    input: validInput(cases: [
      .init(
        id: "case",
        language: .english,
        reference: "a",
        hypothesis: "a",
        protectedExpectations: [.init(kind: " ", text: "a", comparison: .exact)]
      )
    ])
  )
  expectError(
    .emptyProtectedText("case"),
    input: validInput(cases: [
      .init(
        id: "case",
        language: .english,
        reference: "a",
        hypothesis: "a",
        protectedExpectations: [.init(kind: "name", text: "\n", comparison: .exact)]
      )
    ])
  )
}

@Test func rejectsNegativeNetworkCountTimingAndPeakMemory() {
  expectError(
    .negativeNetworkConnectionCount,
    input: validInput(unexpectedNetworkConnectionCount: -1)
  )
  expectError(
    .negativeTiming("firstPartialMilliseconds"),
    input: validInput(
      cases: [
        .init(
          id: "case",
          language: .english,
          reference: "a",
          hypothesis: "a",
          timing: .init(isCold: false, firstPartialMilliseconds: -1)
        )
      ]
    )
  )
  expectError(
    .negativePeakResidentBytes("case"),
    input: validInput(
      cases: [
        .init(
          id: "case",
          language: .english,
          reference: "a",
          hypothesis: "a",
          peakResidentBytes: -1
        )
      ]
    )
  )
}

@Test func rejectsNonFiniteTiming() {
  expectError(
    .nonFiniteTiming("stopToFinalMilliseconds"),
    input: validInput(
      cases: [
        .init(
          id: "case",
          language: .english,
          reference: "a",
          hypothesis: "a",
          timing: .init(isCold: false, stopToFinalMilliseconds: .nan)
        )
      ]
    )
  )
}

@Test func reportsExactProtectedMeaningViolationsInExpectationOrder() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "path-case",
        language: .english,
        reference: "copy /fixture/Notes.txt and ticket #42",
        hypothesis: "copy /fixture/notes.txt and ticket 42",
        protectedExpectations: [
          .init(kind: "path", text: "/fixture/Notes.txt", comparison: .exact),
          .init(kind: "ticket", text: "ticket #42", comparison: .exact),
        ]
      )
    ]))

  #expect(
    report.protectedViolations == [
      .init(
        caseID: "path-case",
        kind: "path",
        expectedText: "/fixture/Notes.txt",
        observedHypothesis: "copy /fixture/notes.txt and ticket 42"
      ),
      .init(
        caseID: "path-case",
        kind: "ticket",
        expectedText: "ticket #42",
        observedHypothesis: "copy /fixture/notes.txt and ticket 42"
      ),
    ])
}

@Test func acceptsCaseAndWhitespaceInsensitiveProtectedText() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "name",
        language: .english,
        reference: "call Priya Shah",
        hypothesis: "call priya   shah",
        protectedExpectations: [
          .init(
            kind: "name",
            text: "Priya Shah",
            comparison: .caseAndWhitespaceInsensitive
          )
        ]
      )
    ]))

  #expect(report.protectedViolations.isEmpty)
}

@Test func acceptsProtectedNumberBeforeTerminalSentencePunctuation() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "number-period",
        language: .english,
        reference: "send 2",
        hypothesis: "send 2.",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      )
    ]))

  #expect(report.protectedViolations.isEmpty)
}

@Test func acceptsInsensitiveProtectedNameBeforeTerminalSentencePunctuation() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "name-period",
        language: .english,
        reference: "call Alex",
        hypothesis: "Call ALEX.",
        protectedExpectations: [
          .init(kind: "name", text: "Alex", comparison: .caseAndWhitespaceInsensitive)
        ]
      )
    ]))

  #expect(report.protectedViolations.isEmpty)
}

@Test func rejectsPunctuationChangesInInsensitiveProtectedText() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "name-punctuation",
        language: .english,
        reference: "call Alex Morgan",
        hypothesis: "call alex-morgan",
        protectedExpectations: [
          .init(
            kind: "name",
            text: "Alex Morgan",
            comparison: .caseAndWhitespaceInsensitive
          )
        ]
      )
    ]))

  #expect(report.protectedViolations.map(\.caseID) == ["name-punctuation"])
  #expect(report.protectedViolations[0].kind == "name")
  #expect(report.protectedViolations[0].expectedText == "Alex Morgan")
  #expect(report.protectedViolations[0].observedHypothesis == "call alex-morgan")
}

@Test func reportsNearestRankWarmThenColdAndOmitsMissingMeasurements() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "warm-1",
        language: .english,
        reference: "a",
        hypothesis: "a",
        timing: .init(
          isCold: false,
          firstPartialMilliseconds: 300,
          stopToFinalMilliseconds: 600,
          stopToInsertionMilliseconds: 900
        ),
        peakResidentBytes: 1_000
      ),
      .init(
        id: "warm-2",
        language: .english,
        reference: "a",
        hypothesis: "a",
        timing: .init(
          isCold: false,
          firstPartialMilliseconds: 100,
          stopToFinalMilliseconds: 400,
          stopToInsertionMilliseconds: 800
        ),
        peakResidentBytes: 4_000
      ),
      .init(
        id: "warm-3",
        language: .english,
        reference: "a",
        hypothesis: "a",
        timing: .init(
          isCold: false,
          firstPartialMilliseconds: 200,
          stopToFinalMilliseconds: 500,
          stopToInsertionMilliseconds: 700
        ),
        peakResidentBytes: 2_000
      ),
      .init(
        id: "cold-1",
        language: .english,
        reference: "a",
        hypothesis: "a",
        timing: .init(
          isCold: true,
          firstPartialMilliseconds: 900,
          stopToFinalMilliseconds: 300,
          stopToInsertionMilliseconds: 500
        )
      ),
      .init(
        id: "cold-2",
        language: .english,
        reference: "a",
        hypothesis: "a",
        timing: .init(
          isCold: true,
          firstPartialMilliseconds: 700,
          stopToFinalMilliseconds: 100,
          stopToInsertionMilliseconds: 400
        )
      ),
      .init(
        id: "missing",
        language: .english,
        reference: "a",
        hypothesis: "a",
        timing: .init(isCold: false)
      ),
    ]))

  #expect(
    report.latencySummaries == [
      .init(
        isCold: false, kind: .firstPartial, sampleCount: 3, p50Milliseconds: 200,
        p95Milliseconds: 300),
      .init(
        isCold: false, kind: .stopToFinal, sampleCount: 3, p50Milliseconds: 500,
        p95Milliseconds: 600),
      .init(
        isCold: false, kind: .stopToInsertion, sampleCount: 3, p50Milliseconds: 800,
        p95Milliseconds: 900),
      .init(
        isCold: true, kind: .firstPartial, sampleCount: 2, p50Milliseconds: 700,
        p95Milliseconds: 900),
      .init(
        isCold: true, kind: .stopToFinal, sampleCount: 2, p50Milliseconds: 100, p95Milliseconds: 300
      ),
      .init(
        isCold: true, kind: .stopToInsertion, sampleCount: 2, p50Milliseconds: 400,
        p95Milliseconds: 500),
    ])
  #expect(report.maximumObservedPeakResidentBytes == 4_000)
}

@Test func keepsCatastrophicCaseVisibleAlongsideAcceptableAggregate() throws {
  let goodCases = (0..<9).map { index in
    ModelEvaluationCaseInput(
      id: "good-\(index)",
      language: .english,
      reference: "a",
      hypothesis: "a"
    )
  }
  let report = try ModelEvaluationScorer.score(
    validInput(
      cases: goodCases + [
        .init(
          id: "catastrophic",
          language: .english,
          reference: "a b c d",
          hypothesis: ""
        )
      ]))

  #expect(
    report.languageMetrics == [
      .init(language: .english, edits: 4, referenceUnits: 13)
    ])
  #expect(
    report.caseMetrics.first
      == .init(
        caseID: "good-0",
        language: .english,
        edits: 0,
        referenceUnits: 1
      ))
  #expect(
    report.caseMetrics.last
      == .init(
        caseID: "catastrophic",
        language: .english,
        edits: 4,
        referenceUnits: 4
      ))

  let reportObject =
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
  guard let caseMetrics = reportObject?["caseMetrics"] as? [[String: Any]] else {
    Issue.record("Expected deterministic per-case metrics in the report.")
    return
  }
  #expect(caseMetrics.count == 10)
  #expect(caseMetrics.first?["caseID"] as? String == "good-0")
  #expect(caseMetrics.last?["caseID"] as? String == "catastrophic")
  #expect(caseMetrics.last?["language"] as? String == "english")
  #expect(caseMetrics.last?["edits"] as? Int == 4)
  #expect(caseMetrics.last?["referenceUnits"] as? Int == 4)
  #expect(caseMetrics.last?["errorRate"] as? Double == 1)
}

@Test func rejectsNonblankReferencesWithNoLanguageScoringUnits() {
  expectError(
    .emptyReferenceUnits("english-punctuation"),
    input: validInput(cases: [
      .init(id: "english-punctuation", language: .english, reference: "!!!", hypothesis: "")
    ])
  )
  expectError(
    .emptyReferenceUnits("mandarin-punctuation"),
    input: validInput(cases: [
      .init(id: "mandarin-punctuation", language: .mandarin, reference: "，。", hypothesis: "")
    ])
  )
  expectError(
    .emptyReferenceUnits("mixed-punctuation"),
    input: validInput(cases: [
      .init(id: "mixed-punctuation", language: .mixed, reference: "!!!", hypothesis: "")
    ])
  )
}

@Test func requiresProtectedNumbersToHaveLiteralBoundaries() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "number-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send 20 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-decimal-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send 2.0 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-currency-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send $2 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-percent-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send 2% invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-negative-sign-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send -2 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-positive-sign-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send +2 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-range-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send 2-3 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "number-non-dollar-currency-embedded",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send ₽2 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
    ]))

  #expect(
    report.protectedViolations.map(\.caseID) == [
      "number-embedded",
      "number-decimal-embedded",
      "number-currency-embedded",
      "number-percent-embedded",
      "number-negative-sign-embedded",
      "number-positive-sign-embedded",
      "number-range-embedded",
      "number-non-dollar-currency-embedded",
    ])
}

@Test func classifiesSignedProtectedValuesAsNumeric() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "signed-negative-decimal-embedded",
        language: .english,
        reference: "send -2 invoices",
        hypothesis: "send -2.0 invoices",
        protectedExpectations: [.init(kind: "number", text: "-2", comparison: .exact)]
      ),
      .init(
        id: "signed-positive-embedded",
        language: .english,
        reference: "send +2 invoices",
        hypothesis: "send +20 invoices",
        protectedExpectations: [.init(kind: "number", text: "+2", comparison: .exact)]
      ),
      .init(
        id: "signed-negative-boundary",
        language: .english,
        reference: "send -2 invoices",
        hypothesis: "send -2.",
        protectedExpectations: [.init(kind: "number", text: "-2", comparison: .exact)]
      ),
      .init(
        id: "signed-positive-boundary",
        language: .english,
        reference: "send +2 invoices",
        hypothesis: "send +2.",
        protectedExpectations: [.init(kind: "number", text: "+2", comparison: .exact)]
      ),
    ]))

  #expect(
    report.protectedViolations.map(\.caseID) == [
      "signed-negative-decimal-embedded",
      "signed-positive-embedded",
    ])
}

@Test func requiresProtectedWordsToHaveLiteralBoundaries() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "word-embedded",
        language: .english,
        reference: "call Alex",
        hypothesis: "call Alexander",
        protectedExpectations: [
          .init(kind: "name", text: "Alex", comparison: .caseAndWhitespaceInsensitive)
        ]
      )
    ]))

  #expect(report.protectedViolations.map(\.caseID) == ["word-embedded"])
}

@Test func requiresProtectedPathsToHaveLiteralBoundaries() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "path-embedded",
        language: .english,
        reference: "copy /tmp/foo",
        hypothesis: "copy /tmp/foobar",
        protectedExpectations: [.init(kind: "path", text: "/tmp/foo", comparison: .exact)]
      ),
      .init(
        id: "path-separator-embedded",
        language: .english,
        reference: "copy /tmp/foo",
        hypothesis: "copy /tmp/foo/bar",
        protectedExpectations: [.init(kind: "path", text: "/tmp/foo", comparison: .exact)]
      ),
    ]))

  #expect(
    report.protectedViolations.map(\.caseID) == [
      "path-embedded",
      "path-separator-embedded",
    ])
}

@Test func acceptsProtectedTextAtLiteralBoundaries() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "number-boundary",
        language: .english,
        reference: "send 2 invoices",
        hypothesis: "send 2 invoices",
        protectedExpectations: [.init(kind: "number", text: "2", comparison: .exact)]
      ),
      .init(
        id: "path-boundary",
        language: .english,
        reference: "copy /tmp/foo",
        hypothesis: "copy /tmp/foo",
        protectedExpectations: [.init(kind: "path", text: "/tmp/foo", comparison: .exact)]
      ),
    ]))

  #expect(report.protectedViolations.isEmpty)
}

@Test func scoresMixedLanguageLatinWordsWithoutCaseDifferences() throws {
  let report = try ModelEvaluationScorer.score(
    validInput(cases: [
      .init(
        id: "mixed-case",
        language: .mixed,
        reference: "Send invoices",
        hypothesis: "send invoices"
      )
    ]))

  #expect(
    report.languageMetrics == [
      .init(language: .mixed, edits: 0, referenceUnits: 2)
    ])
}

private func validInput(
  schemaVersion: Int = 1,
  modelID: String = "fixture-asr",
  revision: String = "fixture-revision",
  runtime: String = "fixture-runtime",
  quantization: String = "none",
  hardware: String = "fixture-mac",
  unexpectedNetworkConnectionCount: Int = 0,
  cases: [ModelEvaluationCaseInput]? = nil
) -> ModelEvaluationRunInput {
  ModelEvaluationRunInput(
    schemaVersion: schemaVersion,
    modelID: modelID,
    revision: revision,
    runtime: runtime,
    quantization: quantization,
    hardware: hardware,
    unexpectedNetworkConnectionCount: unexpectedNetworkConnectionCount,
    cases: cases ?? [
      .init(id: "case", language: .english, reference: "a", hypothesis: "a")
    ]
  )
}

private func expectError(
  _ expected: ModelEvaluationError,
  input: ModelEvaluationRunInput
) {
  do {
    _ = try ModelEvaluationScorer.score(input)
    Issue.record("Expected ModelEvaluationError \(expected).")
  } catch let error as ModelEvaluationError {
    #expect(error == expected)
  } catch {
    Issue.record("Unexpected error: \(error).")
  }
}
