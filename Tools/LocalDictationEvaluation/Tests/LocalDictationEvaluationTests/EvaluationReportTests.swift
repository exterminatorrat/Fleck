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

private func reportV2Run() throws -> CandidateRun {
  try JSONDecoder().decode(
    CandidateRun.self,
    from: reportFixture("local-dictation-run-sample-v2.json")
  )
}

private func reportV2Corpus() throws -> EvaluationCorpus {
  var corpus = try reportCorpus()
  for index in corpus.cases.indices where corpus.cases[index].language == .mixed {
    corpus.cases[index].categories.append(contentsOf: ["mixed-en-zh", "mixed-zh-en"])
  }
  return corpus
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

private func reportV2Gate(for run: CandidateRun) -> EvaluationGate {
  EvaluationGate(
    schemaVersion: 2,
    maxEnglishWordErrorRate: 0.50,
    maxMandarinCharacterErrorRate: 0.50,
    maxMixedEnglishWordErrorRate: 0.50,
    maxMixedMandarinCharacterErrorRate: 0.50,
    minimumProtectedTermAccuracy: 0.50,
    maximumNumberFailures: 10,
    maximumNegationFailures: 10,
    maximumCleanupPreservationFailures: 0,
    maxColdLatencyMilliseconds: 2_000,
    maxWarmLatencyMilliseconds: 500,
    maxPeakMemoryBytes: 2_000_000_000,
    maxIdleMemoryBytes: 500_000_000,
    maxPostUnloadMemoryBytes: 500_000_000,
    maxEnergyImpact: 2.0,
    maxModelDownloadBytes: 2_000_000_000,
    maxModelInstalledBytes: 2_000_000_000,
    minimumStandardMaterialImprovement: 0.0,
    allowedThermalStates: [.nominal, .fair],
    sliceGates: run.standardBaseline.sliceMetrics.map {
      EvaluationSliceGate(
        sliceID: $0.sliceID,
        metric: $0.metric,
        maximumCandidateValue: 1.0,
        maximumRegressionFromStandard: 1.0
      )
    },
    maxFirstMeaningfulPartialMilliseconds: 500,
    maxProvisionalUpdateIntervalMilliseconds: 500,
    maxProvisionalInstabilityRate: 0.50,
    maxFinalASRMilliseconds: 500,
    maxCleanupMilliseconds: 500,
    maxStopToInsertionMilliseconds: 2_000,
    maxCancellationMilliseconds: 500,
    maxReadyIdleDeltaBytes: 500_000_000,
    maxPostUnloadDeltaBytes: 2_000_000_000,
    maxUnloadMilliseconds: 500,
    minimumRepeatedRunCount: 50
  )
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
  let corpus = admitted(try reportV2Corpus())
  var run = try reportV2Run()
  run.syntheticSample = false
  run.releaseEvidence = true
  var gate = reportV2Gate(for: run)
  let passing = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: gate
  )
  #expect(passing.gateOutcomes.contains { $0.id == "english-wer" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "mixed-language" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "peak-memory" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "ready-idle-delta" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "energy" && $0.passed })
  #expect(passing.gateOutcomes.contains {
    $0.id == "download-size" && $0.passed
  })
  #expect(passing.gateOutcomes.contains {
    $0.id == "standard-improvement-mixed" && $0.passed
  })
  #expect(passing.gateOutcomes.contains { $0.id == "unload-duration" && $0.passed })
  #expect(passing.gateOutcomes.contains {
    $0.id == "failure-cancellation" && $0.passed
  })

  gate.maxEnglishWordErrorRate = 0
  gate.maxPeakMemoryBytes = 1
  gate.maxReadyIdleDeltaBytes = 1
  gate.maxEnergyImpact = 0
  let failing = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: gate
  )
  #expect(failing.releaseDecision == .failed)
  #expect(failing.gateOutcomes.contains { $0.id == "english-wer" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "peak-memory" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "ready-idle-delta" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "energy" && !$0.passed })
}

@Test func protectedGatesUseSelectedTranscriptNotMetricSlices() throws {
  let corpus = admitted(try reportV2Corpus())
  var run = try reportV2Run()
  run.syntheticSample = false
  run.releaseEvidence = true
  for index in run.results.indices where run.results[index].caseID == "english-developer-command" {
    run.results[index].cleanedResult = "Please run swift test."
  }
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportV2Gate(for: run)
  )
  guard let englishProtected = report.protectedExpectations.first(where: {
    $0.scope == .english
  }) else {
    Issue.record("Missing English protected expectation summary")
    return
  }
  #expect(englishProtected.failed == 12)
  #expect(englishProtected.numberFailures == 2)
  #expect(englishProtected.negationFailures == 2)
  guard let standardProtected = report.standardComparison.metrics.first(where: {
    $0.scope == .english && $0.metric == .protectedTermAccuracy
  }) else {
    Issue.record("Missing English Standard protected accuracy")
    return
  }
  #expect(standardProtected.candidateValue == 0)
  #expect(standardProtected.improvement == -1)
  #expect(report.gateOutcomes.contains {
    $0.id == "protected-terms" && !$0.passed
  })
  #expect(report.gateOutcomes.contains {
    $0.id == "standard-improvement-english" && !$0.passed
  })
}

@Test func unverifiedFailureOrCancellationFailsReleaseGate() throws {
  let corpus = admitted(try reportV2Corpus())
  var run = try reportV2Run()
  run.syntheticSample = false
  run.releaseEvidence = true
  run.failureCancellationEvidence.failureExercised = false
  run.failureCancellationEvidence.failureFallbackVerified = false
  let failure = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportV2Gate(for: run)
  )
  #expect(failure.releaseDecision == .failed)
  #expect(failure.gateOutcomes.contains {
    $0.id == "failure-cancellation" && !$0.passed
  })

  run.failureCancellationEvidence.failureFallbackVerified = true
  run.failureCancellationEvidence.cancellationExercised = false
  run.failureCancellationEvidence.cancellationOutcomeVerified = false
  let cancellation = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportV2Gate(for: run)
  )
  #expect(cancellation.releaseDecision == .failed)
  #expect(cancellation.gateOutcomes.contains {
    $0.id == "failure-cancellation" && !$0.passed
  })
}

@Test func absentManualAdjudicationRequiresReviewAndNeverProvesMeaning() throws {
  let corpus = admitted(try reportV2Corpus())
  var run = try reportV2Run()
  run.syntheticSample = false
  run.releaseEvidence = true
  run.results[0].manualAdjudication = nil
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportV2Gate(for: run)
  )
  #expect(report.cleanupPreservation.manualReviewRequired > 0)
  #expect(report.releaseDecision == .reviewRequired)
  #expect(report.markdown.contains("Manual adjudication is required"))
  #expect(report.markdown.contains("Metrics do not prove semantic fidelity."))
}

@Test func pendingAndFailedCleanupAdjudicationHaveDistinctPrecedence() throws {
  let corpus = admitted(try reportV2Corpus())
  var pendingRun = try reportV2Run()
  pendingRun.syntheticSample = false
  pendingRun.releaseEvidence = true
  pendingRun.results[0].manualAdjudication = ManualAdjudication(
    status: .pending,
    reviewer: nil,
    notes: nil
  )
  let pending = try EvaluationReportBuilder.build(
    corpus: corpus, run: pendingRun, gate: reportV2Gate(for: pendingRun)
  )
  #expect(pending.releaseDecision == .reviewRequired)

  var failedRun = pendingRun
  failedRun.results[0].manualAdjudication = ManualAdjudication(
    status: .failed,
    reviewer: "reviewer",
    notes: "meaning changed"
  )
  let failed = try EvaluationReportBuilder.build(
    corpus: corpus, run: failedRun, gate: reportV2Gate(for: failedRun)
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

@Test func v2ReportEmitsCompleteStageAwareGateOutcomes() throws {
  let run = try reportV2Run()
  let report = try EvaluationReportBuilder.build(
    corpus: try reportV2Corpus(),
    run: run,
    gate: reportV2Gate(for: run)
  )
  let expectedGateIDs: Set<String> = [
    "english-wer", "mandarin-cer", "mixed-language",
    "protected-terms", "numbers", "negations", "silence-noise",
    "first-meaningful-partial", "partial-interval", "partial-instability",
    "final-asr-latency", "cleanup-latency", "stop-to-insertion",
    "cancellation-latency", "peak-memory", "ready-idle-delta",
    "unload-duration", "post-unload-delta", "energy", "thermal",
    "download-size", "installed-size", "offline", "reliability-repetition",
    "reliability-failures", "cancellation-no-insertion",
    "cancellation-post-unload", "supply-chain-identity",
    "supply-chain-redistribution", "supply-chain-removal-rollback",
    "failure-cancellation"
  ]
  #expect(expectedGateIDs.isSubset(of: Set(report.gateOutcomes.map(\.id))))
  #expect(report.gateOutcomes.contains { $0.id == "cleanup-latency" && $0.applicable })
  #expect(report.gateOutcomes.contains { $0.id.hasPrefix("slice:category:") })
}

@Test func v2ReportMarksStageSpecificGatesNotApplicable() throws {
  var run = try reportV2Run()
  run.stage = .asrOnly
  run.components = [run.components[0]]
  run.claimedCapabilities = []
  for index in run.results.indices {
    run.results[index].provisional = nil
    run.results[index].cleanedResult = nil
    run.results[index].artifactOrder = [.asrRaw, .dictionaryBaseline]
    run.results[index].manualAdjudication = nil
    run.results[index].resources.modelDownloadBytes = run.components[0].downloadBytes
    run.results[index].resources.modelInstalledBytes = run.components[0].installedBytes
  }
  let report = try EvaluationReportBuilder.build(
    corpus: try reportV2Corpus(),
    run: run,
    gate: reportV2Gate(for: run)
  )
  #expect(report.gateOutcomes.contains {
    $0.id == "cleanup-latency" && !$0.applicable && !$0.passed
  })
  #expect(report.gateOutcomes.contains {
    $0.id == "stop-to-insertion" && !$0.applicable && !$0.passed
  })
  #expect(report.gateOutcomes.contains {
    $0.id == "first-meaningful-partial" && !$0.applicable && !$0.passed
  })
}

@Test func v2ReleaseRequiresEveryCategoryGate() throws {
  var run = try reportV2Run()
  run.syntheticSample = false
  run.releaseEvidence = true
  var gate = reportV2Gate(for: run)
  gate.sliceGates.removeAll {
    $0.sliceID == "category:mixed-en-zh"
  }
  #expect(throws: EvaluationReportError.self) {
    _ = try EvaluationReportBuilder.build(
      corpus: admitted(try reportV2Corpus()),
      run: run,
      gate: gate
    )
  }
}

@Test func v2ReportFailsIndependentLifecycleAndCategoryThresholds() throws {
  let corpus = admitted(try reportV2Corpus())
  var run = try reportV2Run()
  run.syntheticSample = false
  run.releaseEvidence = true
  var gate = reportV2Gate(for: run)
  gate.maxFirstMeaningfulPartialMilliseconds = 100
  gate.maxStopToInsertionMilliseconds = 100
  gate.sliceGates = gate.sliceGates.map { gate in
    guard gate.sliceID == "category:english-prose",
      gate.metric == .englishWordErrorRate else { return gate }
    var changed = gate
    changed.maximumCandidateValue = 0
    return changed
  }
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: gate
  )
  #expect(report.releaseDecision == .failed)
  #expect(report.gateOutcomes.contains {
    $0.id == "first-meaningful-partial" && !$0.passed
  })
  #expect(report.gateOutcomes.contains {
    $0.id == "stop-to-insertion" && !$0.passed
  })
  #expect(report.gateOutcomes.contains {
    $0.id == "slice:category:english-prose:englishWordErrorRate" && !$0.passed
  })
}
}
