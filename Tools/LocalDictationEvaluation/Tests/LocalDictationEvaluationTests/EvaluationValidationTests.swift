import Foundation
import Testing
@testable import LocalDictationEvaluation

private func fixture(_ name: String) throws -> Data {
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

private func decodeCorpus() throws -> EvaluationCorpus {
  try JSONDecoder().decode(
    EvaluationCorpus.self,
    from: fixture("local-dictation-evaluation-v1.json")
  )
}

private func decodeSampleRun() throws -> CandidateRun {
  try JSONDecoder().decode(
    CandidateRun.self,
    from: fixture("local-dictation-run-sample-v1.json")
  )
}

private func decodeV2Run() throws -> CandidateRun {
  try JSONDecoder().decode(
    CandidateRun.self,
    from: fixture("local-dictation-run-sample-v2.json")
  )
}

@Suite("EvaluationValidationTests")
struct EvaluationValidationTests {

@Test func checkedInCorpusAndSampleRunDecodeAndValidate() throws {
  let corpus = try decodeCorpus()
  let run = try decodeSampleRun()
  #expect(corpus.schemaVersion == 1)
  #expect(run.schemaVersion == 1)
  #expect(run.syntheticSample)
  #expect(!run.releaseEvidence)
  #expect(run.results.count == 6)
  #expect(Set(run.results.map(\.observationID)).count == 6)
  #expect(run.results.filter { $0.caseID == "english-developer-command" }
    .map(\.captureTemperature) == [.cold, .warm])
  #expect(run.results.filter { $0.caseID == "mandarin-prose-numbers" }
    .map(\.captureTemperature) == [.cold, .warm])
  #expect(run.results.filter { $0.caseID == "mixed-prompt-and-path" }
    .map(\.captureTemperature) == [.cold, .warm])
  #expect(EvaluationValidator.validate(corpus: corpus).isEmpty)
  #expect(EvaluationValidator.validate(run: run, against: corpus).isEmpty)
}

@Test func corpusValidationReportsStableDuplicateAndBlankPaths() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].id = " "
  corpus.cases[1].id = corpus.cases[2].id
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "blank_id" && $0.path == "/cases/0/id"
  })
  #expect(issues.contains {
    $0.code == "duplicate_case_id" && $0.path == "/cases/2/id"
  })
}

@Test func corpusValidationRejectsMissingCategoryAndBlankReference() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].categories = []
  corpus.cases[0].referenceText = " \n"
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "missing_category" && $0.path == "/cases/0/categories"
  })
  #expect(issues.contains {
    $0.code == "blank_reference" && $0.path == "/cases/0/referenceText"
  })
}

@Test func corpusValidationRejectsMissingMetricLanguageSlice() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].metricReferenceSlices = []
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "missing_language"
      && $0.path == "/cases/0/metricReferenceSlices"
  })
}

@Test func corpusValidationRejectsMalformedSpokenAndProtectedExpectations()
  throws
{
  var corpus = try decodeCorpus()
  corpus.cases[1].spokenText = " "
  corpus.cases[0].protectedExpectations[0].id = " "
  corpus.cases[0].protectedExpectations[1].id = "duplicate"
  corpus.cases[0].protectedExpectations[2].id = "duplicate"
  corpus.cases[0].protectedExpectations[3].term = " "
  corpus.cases[0].protectedExpectations[4].language = .mandarin
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "blank_spoken_text" && $0.path == "/cases/1/spokenText"
  })
  #expect(issues.contains {
    $0.code == "blank_protected_expectation_id"
      && $0.path == "/cases/0/protectedExpectations/0/id"
  })
  #expect(issues.contains {
    $0.code == "duplicate_protected_expectation_id"
      && $0.path == "/cases/0/protectedExpectations/2/id"
  })
  #expect(issues.contains {
    $0.code == "blank_protected_term"
      && $0.path == "/cases/0/protectedExpectations/3/term"
  })
  #expect(issues.contains {
    $0.code == "protected_language_mismatch"
      && $0.path == "/cases/0/protectedExpectations/4/language"
  })
}

@Test func corpusValidationRejectsUnadmittedAudioAndMissingConsent() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].audioAsset = "audio/english.wav"
  corpus.cases[0].audioProvenance = AudioProvenance(
    assetSHA256: "not-a-sha",
    source: "",
    license: "",
    approved: false,
    speakerLanguage: "English",
    speakerAccent: nil,
    privacyReview: "",
    revocationProcess: ""
  )
  corpus.cases[0].audioConsent = AudioConsent(
    status: .pending,
    recordID: "",
    reviewer: nil,
    reviewedAt: nil
  )
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "audio_provenance" && $0.path == "/cases/0/audioProvenance"
  })
  #expect(issues.contains {
    $0.code == "audio_consent" && $0.path == "/cases/0/audioConsent"
  })
}

@Test func duplicateCorpusIDsCannotTrapRunValidation() throws {
  var corpus = try decodeCorpus()
  corpus.cases[1].id = corpus.cases[2].id
  let issues = EvaluationValidator.validate(
    run: try decodeSampleRun(),
    against: corpus
  )
  #expect(issues.contains {
    $0.code == "duplicate_case_id" && $0.path == "/cases/2/id"
  })
}

@Test func duplicateObservationIDsAndManualStatusAreRejected() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results[1].observationID = run.results[0].observationID
  run.results[0].manualAdjudication = ManualAdjudication(
    status: .notRequired,
    reviewer: nil,
    notes: nil
  )
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "duplicate_observation_id"
      && $0.path == "/results/1/observationID"
  })
  #expect(issues.contains {
    $0.code == "manual_adjudication_not_required_with_cleanup"
      && $0.path == "/results/0/manualAdjudication/status"
  })
}

@Test func whitespaceAudioAssetCannotBeAdmittedForRealBenchmark() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].audioAsset = "  \n"
  var run = try decodeSampleRun()
  run.syntheticSample = false
  run.releaseEvidence = false
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "real_audio_not_admitted"
      && $0.path == "/cases/0/audioAsset"
  })
}

@Test func nonSyntheticAudioFreeCorpusCannotValidateWithoutReleaseEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.syntheticSample = false
  run.releaseEvidence = false
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.filter { $0.code == "real_audio_not_admitted" }
    .map(\.path) == [
      "/cases/0/audioAsset",
      "/cases/1/audioAsset",
      "/cases/2/audioAsset"
    ])
}

@Test func runValidationReportsMismatchMissingRawAndArtifactOrder() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.corpusRevision = "wrong-revision"
  run.results[0].asrRaw = " "
  run.results[0].artifactOrder = [.asrRaw, .cleanedResult]
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "corpus_run_mismatch" && $0.path == "/corpusRevision"
  })
  #expect(issues.contains {
    $0.code == "missing_asr_raw" && $0.path == "/results/0/asrRaw"
  })
  #expect(issues.contains {
    $0.code == "invalid_artifact_order"
      && $0.path == "/results/0/artifactOrder"
  })
}

@Test func runValidationRejectsMissingBaselineBlankOptionalsAndInvalidOrder()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results[0].dictionaryBaseline = nil
  run.results[0].cleanedResult = "cleaned result"
  run.results[0].artifactOrder = [.asrRaw, .cleanedResult]
  run.results[1].dictionaryBaseline = " "
  run.results[1].cleanedResult = "\n"
  run.results[1].artifactOrder = [.asrRaw, .dictionaryBaseline, .cleanedResult]
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "cleaned_without_baseline"
      && $0.path == "/results/0/cleanedResult"
  })
  #expect(issues.contains {
    $0.code == "invalid_artifact_order"
      && $0.path == "/results/0/artifactOrder"
  })
  #expect(issues.contains {
    $0.code == "blank_dictionary_baseline"
      && $0.path == "/results/1/dictionaryBaseline"
  })
  #expect(issues.contains {
    $0.code == "blank_cleaned_result"
      && $0.path == "/results/1/cleanedResult"
  })
}

@Test func runValidationRequiresCorrectColdAndWarmEvidence() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results[0].latency.coldLoadMilliseconds = nil
  run.results[1].latency.coldLoadMilliseconds = 1
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "missing_cold_load_measurement"
      && $0.path == "/results/0/latency/coldLoadMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "warm_cold_load_present"
      && $0.path == "/results/1/latency/coldLoadMilliseconds"
  })
}

@Test func runValidationRejectsInvalidBaselineUnloadAndOfflineEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.standardBaseline.metrics[0].scope = .mandarin
  run.standardBaseline.metrics[0].value = .nan
  run.unloadEvidence.memoryAfterUnloadBytes = -1
  run.offlineEvidence.evidenceNote = " "
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "invalid_standard_baseline_metric"
      && $0.path == "/standardBaseline/metrics/0/metric"
  })
  #expect(issues.contains {
    $0.code == "non_finite_standard_baseline_metric"
      && $0.path == "/standardBaseline/metrics/0/value"
  })
  #expect(issues.contains {
    $0.code == "negative_unload_memory"
      && $0.path == "/unloadEvidence/memoryAfterUnloadBytes"
  })
  #expect(issues.contains {
    $0.code == "blank_id"
      && $0.path == "/offlineEvidence/evidenceNote"
  })
}

@Test func runValidationRejectsIncomparableStandardBaseline() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.standardBaseline.identity.corpusID = "different-corpus"
  run.standardBaseline.identity.corpusRevision = "different-revision"
  run.standardBaseline.identity.osVersion = "different-os"
  run.standardBaseline.identity.coldObservationCount = 0
  run.standardBaseline.identity.warmObservationCount = 0
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "baseline_corpus_mismatch"
      && $0.path == "/standardBaseline/identity/corpusID"
  })
  #expect(issues.contains {
    $0.code == "baseline_corpus_mismatch"
      && $0.path == "/standardBaseline/identity/corpusRevision"
  })
  #expect(issues.contains {
    $0.code == "baseline_environment_mismatch"
      && $0.path == "/standardBaseline/identity/osVersion"
  })
  #expect(issues.contains {
    $0.code == "invalid_baseline_coverage"
      && $0.path == "/standardBaseline/identity/coldObservationCount"
  })
  #expect(issues.contains {
    $0.code == "invalid_baseline_coverage"
      && $0.path == "/standardBaseline/identity/warmObservationCount"
  })
}

@Test func runValidationRejectsMalformedFailureCancellationEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.failureCancellationEvidence.failureEvidenceID = " "
  run.failureCancellationEvidence.cancellationObservedAt = "not-a-time"
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "blank_id"
      && $0.path == "/failureCancellationEvidence/failureEvidenceID"
  })
  #expect(issues.contains {
    $0.code == "invalid_failure_cancellation_timestamp"
      && $0.path == "/failureCancellationEvidence/cancellationObservedAt"
  })
}

@Test func runValidationRejectsBadMeasurementsAndSyntheticReleaseEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.releaseEvidence = true
  run.results[0].latency.asrMilliseconds = -1
  run.results[1].latency.cleanupMilliseconds = .infinity
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "negative_measurement"
      && $0.path == "/results/0/latency/asrMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "non_finite_measurement"
      && $0.path == "/results/1/latency/cleanupMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "synthetic_release_evidence"
      && $0.path == "/releaseEvidence"
  })
}

@Test func runValidationFailsClosedForOfflineAndUnknownResults() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results.removeLast()
  run.offlineEvidence.networkDisabled = false
  run.offlineEvidence.networkRequestsObserved = 1
  run.offlineEvidence.contentTelemetryObserved = true
  let unknown = UtteranceResult(
    observationID: "unknown-observation",
    caseID: "not-in-corpus",
    language: .english,
    artifactOrder: [.asrRaw],
    asrRaw: "not persisted",
    dictionaryBaseline: nil,
    cleanedResult: nil,
    captureTemperature: .warm,
    latency: run.results[0].latency,
    resources: run.results[0].resources,
    metricHypothesisSlices: [
      EvaluationTextSlice(language: .english, text: "not persisted")
    ],
    manualAdjudication: nil
  )
  run.results.append(unknown)
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "missing_warm_observation"
      && $0.path == "/cases/2/observations"
  })
  #expect(issues.contains {
    $0.code == "unknown_case_id" && $0.path == "/results/5/caseID"
  })
  #expect(issues.contains {
    $0.code == "offline_network_observed"
      && $0.path == "/offlineEvidence/networkRequestsObserved"
  })
  #expect(issues.contains {
    $0.code == "content_telemetry"
      && $0.path == "/offlineEvidence/contentTelemetryObserved"
  })
}

@Test func releaseEvidenceRequiresSchemaV2AndExactComponents() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.schemaVersion = 1
  run.releaseEvidence = true
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "release_schema_version" && $0.path == "/schemaVersion"
  })

  run = try decodeV2Run()
  run.releaseEvidence = true
  run.components.append(run.components[0])
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "component_roles" && $0.path == "/components"
  })
}

@Test func releaseEvidenceRequiresExactStageComponentCardinality() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.releaseEvidence = true
  run.stage = .asrOnly
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "component_roles" && $0.path == "/components"
  })

  run = try decodeV2Run()
  run.releaseEvidence = true
  run.stage = .cleanupOnly
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "component_roles" && $0.path == "/components"
  })
}

@Test func claimedStreamingRequiresCompleteProvisionalEvidence() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.releaseEvidence = true
  run.claimedCapabilities = [.provisionalResults]
  run.results[0].provisional = nil
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "missing_provisional_evidence"
      && $0.path == "/results/0/provisional"
  })
}

@Test func v2ValidationRejectsMalformedLifecycleAndSupplyChainEvidence() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.releaseEvidence = true
  run.components[0].artifactSHA256 = "not-a-sha"
  run.results[0].resources.modelDownloadBytes += 1
  run.results[0].resources.readyIdleDeltaBytes = 1
  run.unloadEvidence.unloadMilliseconds = nil
  run.reliability?.repeatedRunCount = 49
  run.supplyChain?.redistributionDecision = .pending
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "invalid_component_hash" && $0.path == "/components/0/artifactSHA256"
  })
  #expect(issues.contains {
    $0.code == "ready_idle_delta_mismatch"
      && $0.path == "/results/0/resources/readyIdleDeltaBytes"
  })
  #expect(issues.contains {
    $0.code == "component_byte_totals"
      && $0.path == "/results/0/resources/modelDownloadBytes"
  })
  #expect(issues.contains {
    $0.code == "missing_unload_duration"
      && $0.path == "/unloadEvidence/unloadMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "reliability_repetition_count"
      && $0.path == "/reliability/repeatedRunCount"
  })
  #expect(issues.contains {
    $0.code == "redistribution_not_approved"
      && $0.path == "/supplyChain/redistributionDecision"
  })
}

@Test func cancellationEvidenceMustLinkObservationAndProveNonInsertion() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.releaseEvidence = true
  run.cancellationResourceEvidence?.observationID = "not-an-observation"
  run.cancellationResourceEvidence?.insertionOccurred = true
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "cancellation_observation" && $0.path == "/cancellationResourceEvidence/observationID"
  })
  #expect(issues.contains {
    $0.code == "cancellation_insertion" && $0.path == "/cancellationResourceEvidence/insertionOccurred"
  })
}

@Test func cancellationEvidenceRequiresTimingAndConsistentMemoryDelta() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.releaseEvidence = true
  run.results[0].latency.cancellationMilliseconds = nil
  run.cancellationResourceEvidence?.postCancelUnloadDeltaBytes = 1
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "missing_cancellation_timing"
      && $0.path == "/results/0/latency/cancellationMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "cancellation_memory_delta_mismatch"
      && $0.path == "/cancellationResourceEvidence/postCancelUnloadDeltaBytes"
  })
}

@Test func releaseEvidenceRequiresBothMixedDirectionSliceMetrics() throws {
  let corpus = try decodeCorpus()
  var completeRun = try decodeV2Run()
  completeRun.releaseEvidence = true
  #expect(EvaluationValidator.validate(run: completeRun, against: corpus).contains {
    $0.code == "missing_mixed_direction_category"
  })

  var run = completeRun
  run.standardBaseline.sliceMetrics.removeAll {
    $0.sliceID == "category:mixed-en-zh"
  }
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "missing_baseline_slice_metric"
      && $0.message.contains("category:mixed-en-zh")
  })
}

@Test func schemaV1ReleaseEvidenceIsNeverEligible() throws {
  var run = try decodeSampleRun()
  run.releaseEvidence = true
  let issues = EvaluationValidator.validate(run: run, against: try decodeCorpus())
  #expect(issues.contains {
    $0.code == "release_schema_version" && $0.path == "/schemaVersion"
  })
}
}
