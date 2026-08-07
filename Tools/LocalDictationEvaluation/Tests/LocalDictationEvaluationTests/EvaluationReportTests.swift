import Foundation
import Testing
@testable import LocalDictationEvaluation

private func reportFixture(_ name: String) throws -> Data {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<8 {
    let candidate = url
      .deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/\(name)")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return try Data(contentsOf: candidate)
    }
    url.deleteLastPathComponent()
  }
  Issue.record("Missing fixture \(name)")
  return Data()
}

private func reportCorpus() throws -> EvaluationCorpus {
  try JSONDecoder().decode(
    EvaluationCorpus.self,
    from: reportFixture("local-dictation-evaluation-v1.json")
  )
}

private func reportRun() throws -> CandidateRun {
  try JSONDecoder().decode(
    CandidateRun.self,
    from: reportFixture("local-dictation-run-sample-v1.json")
  )
}

private func reportGate(
  maxEnglish: Double = 0.25,
  maxMandarin: Double = 0.25,
  maxMixedEnglish: Double = 0.30,
  maxMixedMandarin: Double = 0.30,
  minimumProtected: Double = 0.90,
  maximumNumberFailures: Int = 0,
  maximumNegationFailures: Int = 0,
  maximumCleanupFailures: Int = 0,
  maxCold: Double = 2_000,
  maxWarm: Double = 500,
  maxPeak: Int64 = 2_000_000_000,
  maxIdle: Int64 = 500_000_000,
  maxPostUnload: Int64 = 500_000_000,
  maxEnergy: Double = 2.0,
  maxDownload: Int64 = 2_000_000_000,
  maxInstalled: Int64 = 2_000_000_000,
  minimumStandardImprovement: Double = 0.10,
  thermal: [ThermalState] = [.nominal, .fair]
) -> EvaluationGate {
  EvaluationGate(
    schemaVersion: 1,
    maxEnglishWordErrorRate: maxEnglish,
    maxMandarinCharacterErrorRate: maxMandarin,
    maxMixedEnglishWordErrorRate: maxMixedEnglish,
    maxMixedMandarinCharacterErrorRate: maxMixedMandarin,
    minimumProtectedTermAccuracy: minimumProtected,
    maximumNumberFailures: maximumNumberFailures,
    maximumNegationFailures: maximumNegationFailures,
    maximumCleanupPreservationFailures: maximumCleanupFailures,
    maxColdLatencyMilliseconds: maxCold,
    maxWarmLatencyMilliseconds: maxWarm,
    maxPeakMemoryBytes: maxPeak,
    maxIdleMemoryBytes: maxIdle,
    maxPostUnloadMemoryBytes: maxPostUnload,
    maxEnergyImpact: maxEnergy,
    maxModelDownloadBytes: maxDownload,
    maxModelInstalledBytes: maxInstalled,
    minimumStandardMaterialImprovement: minimumStandardImprovement,
    allowedThermalStates: thermal
  )
}

private func admitted(_ source: EvaluationCorpus) -> EvaluationCorpus {
  var corpus = source
  for index in corpus.cases.indices {
    let id = corpus.cases[index].id
    corpus.cases[index].audioAsset = "admitted-test-\(id).wav"
    corpus.cases[index].audioProvenance = AudioProvenance(
      assetSHA256: String(repeating: "a", count: 64),
      source: "test metadata only",
      license: "test license",
      approved: true,
      speakerLanguage: corpus.cases[index].language.rawValue,
      speakerAccent: nil,
      privacyReview: "test metadata contains no audio",
      revocationProcess: "remove test asset metadata"
    )
    corpus.cases[index].audioConsent = AudioConsent(
      status: .approved,
      recordID: "test-consent-\(id)",
      reviewer: "test",
      reviewedAt: "2026-08-07T00:00:00Z"
    )
  }
  return corpus
}

@Suite("EvaluationReportTests")
struct EvaluationReportTests {

@Test func syntheticReportIsWatermarkedAndNotEligible() throws {
  let report = try EvaluationReportBuilder.build(
    corpus: try reportCorpus(),
    run: try reportRun(),
    gate: reportGate()
  )
  #expect(report.releaseDecision == .notEligible)
  #expect(
    String(
      report.markdown.split(
        separator: "\n",
        omittingEmptySubsequences: false
      ).first ?? ""
    ) == "SAMPLE DATA — NOT MODEL EVIDENCE"
  )
  #expect(report.markdown.contains("Synthetic sample cannot satisfy a release gate."))
  #expect(!report.markdown.contains("fixInputMonitor"))
  #expect(!report.markdown.contains("请在星期五"))
}

@Test func reportMarkdownIsDeterministicAndHasFixedSectionOrder() throws {
  let corpus = try reportCorpus()
  let run = try reportRun()
  let first = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  let second = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  #expect(first == second)
  #expect(first.markdown == second.markdown)
  let headings = [
    "## Candidate",
    "## Language Metrics",
    "## Standard Baseline Comparison",
    "## Protected Expectations",
    "## Cleanup Preservation",
    "## Latency",
    "## Resources",
    "## Artifacts",
    "## Failure and Cancellation",
    "## Offline Evidence",
    "## Gate Outcomes",
    "## Decision"
  ]
  var previous = -1
  for heading in headings {
    let current = first.markdown.range(of: heading)!.lowerBound
    let offset = first.markdown.distance(
      from: first.markdown.startIndex,
      to: current
    )
    #expect(offset > previous)
    previous = offset
  }
}

@Test func reportKeepsEnglishAndMandarinMetricsSeparateForMixedCases() throws {
  let report = try EvaluationReportBuilder.build(
    corpus: try reportCorpus(),
    run: try reportRun(),
    gate: reportGate()
  )
  #expect(report.languageMetrics.contains {
    $0.scope == .mixed
      && $0.language == .english
      && $0.metric == .wordErrorRate
  })
  #expect(report.languageMetrics.contains {
    $0.scope == .mixed
      && $0.language == .mandarin
      && $0.metric == .characterErrorRate
  })
  #expect(!report.languageMetrics.contains {
    $0.scope == .mixed && $0.language == .mixed
  })
}

@Test func repeatedObservationsHaveDeterministicCaseBalancedAggregation() throws {
  var corpus = try reportCorpus()
  var run = try reportRun()
  let extraCase = EvaluationCase(
    id: "english-case-balance-extra",
    language: .english,
    categories: ["english-prose"],
    referenceText: "alpha beta",
    spokenText: "alpha beta",
    audioAsset: nil,
    audioProvenance: nil,
    audioConsent: nil,
    conditions: ["synthetic"],
    protectedExpectations: [],
    metricReferenceSlices: [
      EvaluationTextSlice(language: .english, text: "alpha beta")
    ]
  )
  guard let englishCase = corpus.cases.first(where: {
    $0.id == "english-developer-command"
  }) else {
    Issue.record("Missing English reference case")
    return
  }
  let existingEnglishIndices = run.results.indices.filter {
    run.results[$0].caseID == englishCase.id
  }
  guard existingEnglishIndices.count == 2 else {
    Issue.record("Expected two existing English observations")
    return
  }
  for index in existingEnglishIndices {
    run.results[index].metricHypothesisSlices =
      englishCase.metricReferenceSlices
  }
  corpus.cases.append(extraCase)
  let extraResources = run.results[existingEnglishIndices[0]].resources
  // The two existing English observations are set to the exact reference
  // slice above, so their aggregate WER is 0 and they contribute 2 * 39 = 78
  // reference units. Each extra observation has one deletion over two
  // reference words, so its three-observation aggregate WER is 3 / 6 = 0.5.
  run.results.append(contentsOf: [
    UtteranceResult(
      observationID: "english-case-balance-extra-cold",
      caseID: extraCase.id,
      language: .english,
      artifactOrder: [.asrRaw],
      asrRaw: "alpha",
      dictionaryBaseline: nil,
      cleanedResult: nil,
      captureTemperature: .cold,
      latency: LatencyMeasurement(
        coldLoadMilliseconds: 100,
        asrMilliseconds: 20,
        cleanupMilliseconds: 0,
        endToEndMilliseconds: 120
      ),
      resources: extraResources,
      metricHypothesisSlices: [
        EvaluationTextSlice(language: .english, text: "alpha")
      ],
      manualAdjudication: nil
    ),
    UtteranceResult(
      observationID: "english-case-balance-extra-warm-1",
      caseID: extraCase.id,
      language: .english,
      artifactOrder: [.asrRaw],
      asrRaw: "alpha",
      dictionaryBaseline: nil,
      cleanedResult: nil,
      captureTemperature: .warm,
      latency: LatencyMeasurement(
        coldLoadMilliseconds: nil,
        asrMilliseconds: 20,
        cleanupMilliseconds: 0,
        endToEndMilliseconds: 20
      ),
      resources: extraResources,
      metricHypothesisSlices: [
        EvaluationTextSlice(language: .english, text: "alpha")
      ],
      manualAdjudication: nil
    ),
    UtteranceResult(
      observationID: "english-case-balance-extra-warm-2",
      caseID: extraCase.id,
      language: .english,
      artifactOrder: [.asrRaw],
      asrRaw: "alpha",
      dictionaryBaseline: nil,
      cleanedResult: nil,
      captureTemperature: .warm,
      latency: LatencyMeasurement(
        coldLoadMilliseconds: nil,
        asrMilliseconds: 20,
        cleanupMilliseconds: 0,
        endToEndMilliseconds: 20
      ),
      resources: extraResources,
      metricHypothesisSlices: [
        EvaluationTextSlice(language: .english, text: "alpha")
      ],
      manualAdjudication: nil
    )
  ])
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  guard let english = report.languageMetrics.first(where: {
    $0.scope == .english && $0.language == .english
  }) else {
    Issue.record("Missing English language summary")
    return
  }
  #expect(english.caseCount == 2)
  #expect(english.observationCount == 5)
  #expect(english.counts.deletions == 3)
  #expect(english.counts.referenceUnits == 84)
  let caseBalancedErrorRate = (0.0 + 0.5) / 2.0
  #expect(caseBalancedErrorRate == 0.25)
  #expect(english.errorRate == caseBalancedErrorRate)
  #expect(english.aggregation.contains("unweighted mean"))
  let observationWeightedErrorRate = (0.0 + 0.0 + 0.5 + 0.5 + 0.5) / 5.0
  #expect(observationWeightedErrorRate == 0.3)
  #expect(english.errorRate != observationWeightedErrorRate)
  #expect(report.languageMetrics.filter { $0.scope != .english }.allSatisfy {
    $0.caseCount == 1 && $0.observationCount == 2
      && $0.aggregation.contains("unweighted mean")
  })
  #expect(report.latency.coldCount == 4)
  #expect(report.latency.warmCount == 5)
  #expect(report.resources.observationCount == 9)
  #expect(report.standardComparison.metrics.count == 7)
  #expect(report.standardComparison.baselineModelRevision
    == "AppleSpeechCapture-standard-v1-synthetic")
  #expect(report.standardComparison.corpusID
    == "local-dictation-evaluation-v1")
  #expect(report.standardComparison.corpusRevision == "text-contract-v1")
  #expect(report.standardComparison.osVersion == "synthetic")
  #expect(report.standardComparison.hardwareModel == "synthetic")
  #expect(report.standardComparison.architecture == "arm64")
  #expect(report.standardComparison.appBuild == "synthetic")
  #expect(report.standardComparison.coldObservationCount == 3)
  #expect(report.standardComparison.warmObservationCount == 3)
  #expect(report.failureCancellation.failureExercised)
  #expect(report.failureCancellation.failureFallbackVerified)
  #expect(report.failureCancellation.cancellationExercised)
  #expect(report.failureCancellation.cancellationOutcomeVerified)
}

@Test func nonSyntheticWithoutReleaseEvidenceIsNotEligible() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = false
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  #expect(report.releaseDecision == .notEligible)
  #expect(report.markdown.contains(
    "Release evidence was not asserted; metrics cannot make this run eligible."
  ))
}

@Test func incomparableBaselineCannotProduceMaterialImprovement() throws {
  var run = try reportRun()
  run.standardBaseline.identity.appBuild = "different-build"
  #expect(throws: EvaluationReportError.self) {
    _ = try EvaluationReportBuilder.build(
      corpus: try reportCorpus(),
      run: run,
      gate: reportGate()
    )
  }
}

@Test func gatePassAndFailAreExplicitAndHaveNoThresholdDefaults() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = true
  let passing = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  #expect(passing.gateOutcomes.contains { $0.id == "english-wer" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "mixed-language" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "peak-memory" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "idle-memory" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "energy" && $0.passed })
  #expect(passing.gateOutcomes.contains {
    $0.id == "model-download-size" && $0.passed
  })
  #expect(passing.gateOutcomes.contains {
    $0.id == "standard-improvement-mixed" && $0.passed
  })
  #expect(passing.gateOutcomes.contains { $0.id == "unload-behavior" && $0.passed })
  #expect(passing.gateOutcomes.contains {
    $0.id == "failure-cancellation-behavior" && $0.passed
  })

  let failing = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate(maxEnglish: 0, maxPeak: 1, maxIdle: 1, maxEnergy: 0)
  )
  #expect(failing.releaseDecision == .failed)
  #expect(failing.gateOutcomes.contains { $0.id == "english-wer" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "peak-memory" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "idle-memory" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "energy" && !$0.passed })
}

@Test func unverifiedFailureOrCancellationFailsReleaseGate() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = true
  run.failureCancellationEvidence.failureExercised = false
  run.failureCancellationEvidence.failureFallbackVerified = false
  let failure = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  #expect(failure.releaseDecision == .failed)
  #expect(failure.gateOutcomes.contains {
    $0.id == "failure-cancellation-behavior" && !$0.passed
  })

  run.failureCancellationEvidence.failureFallbackVerified = true
  run.failureCancellationEvidence.cancellationExercised = false
  run.failureCancellationEvidence.cancellationOutcomeVerified = false
  let cancellation = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  #expect(cancellation.releaseDecision == .failed)
  #expect(cancellation.gateOutcomes.contains {
    $0.id == "failure-cancellation-behavior" && !$0.passed
  })
}

@Test func absentManualAdjudicationRequiresReviewAndNeverProvesMeaning() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = true
  run.results[0].manualAdjudication = nil
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  #expect(report.cleanupPreservation.manualReviewRequired > 0)
  #expect(report.releaseDecision == .reviewRequired)
  #expect(report.markdown.contains("Manual adjudication is required"))
  #expect(report.markdown.contains("Metrics do not prove semantic fidelity."))
}

@Test func pendingAndFailedCleanupAdjudicationHaveDistinctPrecedence() throws {
  let corpus = admitted(try reportCorpus())
  var pendingRun = try reportRun()
  pendingRun.syntheticSample = false
  pendingRun.releaseEvidence = true
  pendingRun.results[0].manualAdjudication = ManualAdjudication(
    status: .pending,
    reviewer: nil,
    notes: nil
  )
  let pending = try EvaluationReportBuilder.build(
    corpus: corpus, run: pendingRun, gate: reportGate()
  )
  #expect(pending.releaseDecision == .reviewRequired)

  var failedRun = pendingRun
  failedRun.results[0].manualAdjudication = ManualAdjudication(
    status: .failed,
    reviewer: "reviewer",
    notes: "meaning changed"
  )
  let failed = try EvaluationReportBuilder.build(
    corpus: corpus, run: failedRun, gate: reportGate()
  )
  #expect(failed.releaseDecision == .failed)
}

@Test func invalidDiagnosticsNeverContainTranscriptContent() throws {
  let corpus = try reportCorpus()
  var run = try reportRun()
  let secret = "PRIVATE_TRANSCRIPT_SHOULD_NOT_BE_LOGGED"
  run.results[0].asrRaw = secret
  run.results[0].dictionaryBaseline = nil
  run.results[0].cleanedResult = " "
  run.results[0].artifactOrder = [.asrRaw, .cleanedResult]
  do {
    _ = try EvaluationReportBuilder.build(
      corpus: corpus,
      run: run,
      gate: reportGate()
    )
    Issue.record("Expected invalid artifact ordering")
  } catch let error as EvaluationReportError {
    #expect(!String(describing: error).contains(secret))
    #expect(!String(describing: error).contains("PRIVATE_TRANSCRIPT"))
    if case .invalid(let issues) = error {
      #expect(issues.contains {
        $0.code == "cleaned_without_baseline"
          && $0.path == "/results/0/cleanedResult"
      })
      #expect(issues.contains {
        $0.code == "blank_cleaned_result"
          && $0.path == "/results/0/cleanedResult"
      })
    } else {
      Issue.record("Expected validation issues")
    }
  }
}

@Test func gateJSONUsesOnlyThePredeclaredCallerSuppliedFields() throws {
  let data = Data(
    """
    {
      "schemaVersion": 1,
      "maxEnglishWordErrorRate": 0.2,
      "maxMandarinCharacterErrorRate": 0.2,
      "maxMixedEnglishWordErrorRate": 0.3,
      "maxMixedMandarinCharacterErrorRate": 0.3,
      "minimumProtectedTermAccuracy": 0.9,
      "maximumNumberFailures": 0,
      "maximumNegationFailures": 0,
      "maximumCleanupPreservationFailures": 0,
      "maxColdLatencyMilliseconds": 2000,
      "maxWarmLatencyMilliseconds": 500,
      "maxPeakMemoryBytes": 2000000000,
      "maxIdleMemoryBytes": 500000000,
      "maxPostUnloadMemoryBytes": 500000000,
      "maxEnergyImpact": 2.0,
      "maxModelDownloadBytes": 2000000000,
      "maxModelInstalledBytes": 2000000000,
      "minimumStandardMaterialImprovement": 0.1,
      "allowedThermalStates": ["nominal", "fair"]
    }
    """.utf8
  )
  let decoded = try JSONDecoder().decode(EvaluationGate.self, from: data)
  #expect(decoded == reportGate(
    maxEnglish: 0.2,
    maxMandarin: 0.2,
    maxMixedEnglish: 0.3,
    maxMixedMandarin: 0.3,
    minimumProtected: 0.9,
    maximumNumberFailures: 0,
    maximumNegationFailures: 0,
    maximumCleanupFailures: 0,
    maxCold: 2000,
    maxWarm: 500,
    maxPeak: 2_000_000_000,
    maxIdle: 500_000_000,
    maxPostUnload: 500_000_000,
    maxEnergy: 2.0,
    maxDownload: 2_000_000_000,
    maxInstalled: 2_000_000_000,
    minimumStandardImprovement: 0.1,
    thermal: [.nominal, .fair]
  ))
}

@Test func gateJSONRejectsUnknownFieldsAndInvalidValues() throws {
  var object: [String: Any] = [
    "schemaVersion": 1,
    "maxEnglishWordErrorRate": 0.2,
    "maxMandarinCharacterErrorRate": 0.2,
    "maxMixedEnglishWordErrorRate": 0.3,
    "maxMixedMandarinCharacterErrorRate": 0.3,
    "minimumProtectedTermAccuracy": 0.9,
    "maximumNumberFailures": 0,
    "maximumNegationFailures": 0,
    "maximumCleanupPreservationFailures": 0,
    "maxColdLatencyMilliseconds": 2000,
    "maxWarmLatencyMilliseconds": 500,
    "maxPeakMemoryBytes": 2000000000,
    "maxIdleMemoryBytes": 500000000,
    "maxPostUnloadMemoryBytes": 500000000,
    "maxEnergyImpact": 2.0,
    "maxModelDownloadBytes": 2000000000,
    "maxModelInstalledBytes": 2000000000,
    "minimumStandardMaterialImprovement": 0.1,
    "allowedThermalStates": ["nominal", "fair"]
  ]
  object["unexpected"] = true
  let data = try JSONSerialization.data(withJSONObject: object)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(EvaluationGate.self, from: data)
  }
  var invalid = reportGate()
  invalid.maxIdleMemoryBytes = -1
  #expect(throws: EvaluationReportError.self) {
    _ = try EvaluationReportBuilder.build(
      corpus: try reportCorpus(), run: try reportRun(), gate: invalid
    )
  }
}

@Test func atomicReportWriteReplacesExistingTarget() throws {
  let target = FileManager.default.temporaryDirectory
    .appendingPathComponent("local-dictation-report-\(UUID().uuidString).md")
  defer { try? FileManager.default.removeItem(at: target) }
  try Data("old report".utf8).write(to: target)
  try EvaluationReportWriter.atomicWrite("new report", to: target)
  #expect(
    String(data: try Data(contentsOf: target), encoding: .utf8) == "new report"
  )
}
}
