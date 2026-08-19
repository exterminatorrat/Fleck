import FleckModelEvaluation
import Testing

@Test func scoresEnglishMandarinAndMixedInputsFromLiteralExpectations() throws {
    let report = try ModelEvaluationScorer.score(.init(
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
                    .init(kind: "number", text: "2", comparison: .exact),
                ],
                timing: nil,
                peakResidentBytes: nil
            ),
        ]
    ))

    #expect(report.languageMetrics == [
        .init(language: .english, edits: 1, referenceUnits: 4),
        .init(language: .mandarin, edits: 2, referenceUnits: 4),
        .init(language: .mixed, edits: 1, referenceUnits: 4),
    ])
    #expect(report.protectedViolations.map(\.caseID) == ["mixed-1"])
    #expect(report.languageMetrics[0].errorRate == 0.25)
}

@Test func keepsEnglishApostrophesAndIgnoresCaseAndPunctuation() throws {
    let report = try ModelEvaluationScorer.score(validInput(cases: [
        .init(
            id: "english-formatting",
            language: .english,
            reference: "Don't stop, Alex!",
            hypothesis: "don't stop alex",
            protectedExpectations: []
        )
    ]))

    #expect(report.languageMetrics == [
        .init(language: .english, edits: 0, referenceUnits: 3)
    ])
}

@Test func excludesWhitespaceAndPunctuationFromMandarinCharacterError() throws {
    let report = try ModelEvaluationScorer.score(validInput(cases: [
        .init(
            id: "mandarin-formatting",
            language: .mandarin,
            reference: "今天， 开会。",
            hypothesis: "今天开会",
            protectedExpectations: []
        )
    ]))

    #expect(report.languageMetrics == [
        .init(language: .mandarin, edits: 0, referenceUnits: 4)
    ])
}

@Test func countsEachHanGraphemeAsOneMixedLanguageToken() throws {
    let report = try ModelEvaluationScorer.score(validInput(cases: [
        .init(
            id: "mixed-graphemes",
            language: .mixed,
            reference: "我 send invoices",
            hypothesis: "我 send invoices",
            protectedExpectations: []
        )
    ]))

    #expect(report.languageMetrics == [
        .init(language: .mixed, edits: 0, referenceUnits: 3)
    ])
}

@Test func aggregatesInsertionDeletionSubstitutionAndEmptyHypothesisEdits() throws {
    let report = try ModelEvaluationScorer.score(validInput(cases: [
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
        )
    ]))

    #expect(report.languageMetrics == [
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
            .init(id: "same", language: .english, reference: "b", hypothesis: "")
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
    let report = try ModelEvaluationScorer.score(validInput(cases: [
        .init(
            id: "path-case",
            language: .english,
            reference: "copy /fixture/Notes.txt and ticket #42",
            hypothesis: "copy /fixture/notes.txt and ticket 42",
            protectedExpectations: [
                .init(kind: "path", text: "/fixture/Notes.txt", comparison: .exact),
                .init(kind: "ticket", text: "ticket #42", comparison: .exact)
            ]
        )
    ]))

    #expect(report.protectedViolations == [
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
        )
    ])
}

@Test func acceptsCaseAndWhitespaceInsensitiveProtectedText() throws {
    let report = try ModelEvaluationScorer.score(validInput(cases: [
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

@Test func rejectsPunctuationChangesInInsensitiveProtectedText() throws {
    let report = try ModelEvaluationScorer.score(validInput(cases: [
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
    let report = try ModelEvaluationScorer.score(validInput(cases: [
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
        )
    ]))

    #expect(report.latencySummaries == [
        .init(isCold: false, kind: .firstPartial, sampleCount: 3, p50Milliseconds: 200, p95Milliseconds: 300),
        .init(isCold: false, kind: .stopToFinal, sampleCount: 3, p50Milliseconds: 500, p95Milliseconds: 600),
        .init(isCold: false, kind: .stopToInsertion, sampleCount: 3, p50Milliseconds: 800, p95Milliseconds: 900),
        .init(isCold: true, kind: .firstPartial, sampleCount: 2, p50Milliseconds: 700, p95Milliseconds: 900),
        .init(isCold: true, kind: .stopToFinal, sampleCount: 2, p50Milliseconds: 100, p95Milliseconds: 300),
        .init(isCold: true, kind: .stopToInsertion, sampleCount: 2, p50Milliseconds: 400, p95Milliseconds: 500)
    ])
    #expect(report.maximumObservedPeakResidentBytes == 4_000)
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
