import Foundation
import Testing

import FleckCore
@testable import FleckModelEvaluation

@Suite
struct LocalWritingEvidenceTests {
  @Test
  func verifiedHumanReplayProducesContentFreeCanonicalPublicEvidence() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }

    let evidence = try fixture.makeEvidence()
    let canonical = try LocalWritingPublicSummaryCodec.canonicalData(for: evidence.publicSummary)
    let decoded = try LocalWritingPublicSummaryCodec.decodeCanonical(canonical)
    let text = String(decoding: canonical, as: UTF8.self)

    #expect(decoded == evidence.publicSummary)
    #expect(decoded.evidenceLevel == .e1)
    #expect(decoded.executionClass == .recordedHumanAudioReplay)
    #expect(decoded.admissionOutcome == .notApplicable)
    #expect(!text.contains("Call Alice"))
    #expect(!text.contains("audio/case.wav"))
    #expect(!text.contains("transcript"))
    #expect(!text.contains("prompt"))
    #expect(!text.contains("destination"))
  }

  @Test
  func validatorRejectsWrongCheckpointAndDuplicateCases() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let other = try EvidenceFixture()
    defer { other.cleanup() }
    let values = try fixture.values()
    let otherIdentity = values.identity
    _ = try other.ledger.appendExposure(
      LocalWritingCandidateExposure(
        corpusID: LocalWritingEvaluationFixture.corpusID,
        caseID: LocalWritingEvaluationFixture.caseID,
        materialLineageID: LocalWritingEvaluationFixture.lineageID,
        candidateIdentitySHA256: otherIdentity.candidateIdentitySHA256,
        configurationIdentitySHA256: otherIdentity.configurationIdentitySHA256,
        roleProfileIdentitySHA256: otherIdentity.roleProfileIdentitySHA256,
        executionIdentitySHA256: String(repeating: "9", count: 64),
        executionStratum: .e1
      ),
      expectedHead: other.consumedHead.currentHeadSHA256
    )

    #expect(throws: LocalWritingEvidenceError.ledgerMismatch) {
      try fixture.makeEvidence(consumption: try other.consumption())
    }
    #expect(throws: LocalWritingEvidenceError.duplicateCase) {
      try fixture.makeEvidence(cases: [values.caseResult, values.caseResult])
    }
    #expect(throws: LocalWritingEvidenceError.invalidOutcome) {
      try fixture.makeEvidence(cases: [])
    }
  }

  @Test
  func validatorRejectsInvalidatedAndMismatchedExposureLineage() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let values = try fixture.values()
    let invalidation = try LocalWritingMaterialLineageInvalidation(
      corpusID: LocalWritingEvaluationFixture.corpusID,
      caseID: LocalWritingEvaluationFixture.caseID,
      materialLineageID: LocalWritingEvaluationFixture.lineageID,
      reason: .oracleCorrectedAfterExposure
    )
    _ = try fixture.ledger.appendInvalidation(
      invalidation,
      expectedHead: fixture.consumedHead.currentHeadSHA256
    )

    #expect(throws: LocalWritingEvidenceError.invalidatedLineage) {
      try fixture.makeEvidence(
        verification: try fixture.ledger.verify(
          expectedCorpusID: LocalWritingEvaluationFixture.corpusID
        )
      )
    }

    let wrongExposure = try LocalWritingCandidateExposure(
      corpusID: LocalWritingEvaluationFixture.corpusID,
      caseID: LocalWritingEvaluationFixture.caseID,
      materialLineageID: LocalWritingEvaluationFixture.lineageID,
      candidateIdentitySHA256: values.identity.candidateIdentitySHA256,
      configurationIdentitySHA256: String(repeating: "b", count: 64),
      roleProfileIdentitySHA256: values.identity.roleProfileIdentitySHA256,
      executionIdentitySHA256: values.identity.executionIdentitySHA256,
      executionStratum: .e1
    )
    let wrongCase = try values.caseResult.replacing(exposure: .exposed(wrongExposure))
    #expect(throws: LocalWritingEvidenceError.identityMismatch) {
      try fixture.makeEvidence(cases: [wrongCase])
    }
  }

  @Test
  func validatorRequiresTheExactExposureAtOrBeforeTheConsumedHead() throws {
    let fixture = try EvidenceFixture(
      recordExposure: false,
      scoringEligibility: .diagnosticOnlyPostExposure
    )
    defer { fixture.cleanup() }

    #expect(throws: LocalWritingEvidenceError.missingExposure) {
      try fixture.makeEvidence()
    }
  }

  @Test
  func proofLevelsCannotPromoteReplaySyntheticOrInjectedEvidence() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let values = try fixture.values()

    #expect(throws: LocalWritingEvidenceError.illegalProofPromotion) {
      try fixture.makeEvidence(
        proof: try LocalWritingExecutionProof(
          evidenceLevel: .e2,
          executionClass: .recordedHumanAudioReplay,
          hardwareIdentitySHA256: String(repeating: "7", count: 64),
          osBuildIdentitySHA256: String(repeating: "8", count: 64),
          speakerCohortIdentitySHA256: String(repeating: "9", count: 64),
          acousticCohortIdentitySHA256: String(repeating: "a", count: 64),
          packageIdentitySHA256: String(repeating: "b", count: 64)
        )
      )
    }
    #expect(throws: LocalWritingEvidenceError.illegalProofPromotion) {
      try LocalWritingExecutionProof(
        evidenceLevel: .e0,
        executionClass: .deterministicSynthetic,
        hardwareIdentitySHA256: String(repeating: "7", count: 64),
        osBuildIdentitySHA256: String(repeating: "8", count: 64),
        speakerCohortIdentitySHA256: String(repeating: "9", count: 64)
      )
    }
    #expect(throws: LocalWritingEvidenceError.illegalProofPromotion) {
      try LocalWritingExecutionProof(
        evidenceLevel: .e1,
        executionClass: .recordedHumanAudioReplay,
        hardwareIdentitySHA256: String(repeating: "7", count: 64),
        osBuildIdentitySHA256: String(repeating: "8", count: 64),
        speakerCohortIdentitySHA256: String(repeating: "9", count: 64),
        acousticCohortIdentitySHA256: String(repeating: "a", count: 64),
        secondDeviceHardwareIdentitySHA256: String(repeating: "b", count: 64)
      )
    }

    let synthetic = try LocalWritingEvaluationFixture(sourceClass: .synthetic)
    #expect(throws: LocalWritingEvidenceError.executionClassMismatch) {
      try fixture.makeEvidence(canonicalCorpusData: synthetic.canonicalCorpusData)
    }
    #expect(values.proof.signedArtifactIdentitySHA256 == nil)
  }

  @Test
  func protectedMeaningViolationCannotHideBehindPassingCaseOrAggregate() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let values = try fixture.values()
    #expect(throws: LocalWritingEvidenceError.protectedMeaningViolation) {
      try values.caseResult.replacing(
        outcome: .pass,
        protectedMeaningOutcome: .fail,
        cleanupOutcome: .pass
      )
    }

    let failed = try values.caseResult.replacing(
      outcome: .fail,
      protectedMeaningOutcome: .fail,
      cleanupOutcome: .fail
    )
    #expect(throws: LocalWritingEvidenceError.aggregateDisagreement) {
      try fixture.makeEvidence(cases: [failed])
    }
  }

  @Test
  func accuracyAndNetworkFailuresCannotHideBehindAPassingCase() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let values = try fixture.values()
    let failedAccuracy = try LocalWritingAccuracyObservation(
      outcome: .fail,
      edits: 2,
      referenceUnits: 10
    )

    #expect(throws: LocalWritingEvidenceError.invalidOutcome) {
      try values.caseResult.replacing(accuracy: failedAccuracy, outcome: .pass)
    }

    let networkFailure = try LocalWritingStageMeasurements(
      firstPartialMilliseconds: 100,
      stopToFinalMilliseconds: 200,
      stopToInsertionMilliseconds: 300,
      peakResidentBytes: 1_024,
      peakPhysicalFootprintBytes: 2_048,
      installedStorageBytes: 4_096,
      unexpectedNetworkConnectionCount: 1
    )
    #expect(throws: LocalWritingEvidenceError.invalidOutcome) {
      try values.caseResult.replacing(measurements: networkFailure, outcome: .pass)
    }
  }

  @Test
  func publicCodecRejectsUnknownPrivateFieldsUnsafePathsAndNoncanonicalBytes() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let summary = try fixture.makeEvidence().publicSummary
    let canonical = try LocalWritingPublicSummaryCodec.canonicalData(for: summary)
    let text = try #require(String(data: canonical, encoding: .utf8))
    let privateField = text.replacingOccurrences(
      of: #"{"admissionOutcome"#,
      with: #"{"audioPath":"/Users/operator/private.wav","admissionOutcome"#
    )

    #expect(throws: LocalWritingEvidenceError.nonCanonicalSummary) {
      try LocalWritingPublicSummaryCodec.decodeCanonical(Data(privateField.utf8))
    }
    #expect(throws: LocalWritingEvidenceError.nonCanonicalSummary) {
      try LocalWritingPublicSummaryCodec.decodeCanonical(canonical + Data([0x20]))
    }
  }

  @Test
  func evidenceRejectsARawDecodedPublicSummaryWithInvalidSchema() throws {
    let fixture = try EvidenceFixture()
    defer { fixture.cleanup() }
    let canonical = try LocalWritingPublicSummaryCodec.canonicalData(
      for: fixture.makeEvidence().publicSummary
    )
    var text = try #require(String(data: canonical, encoding: .utf8))
    let schema = try #require(text.range(of: #""schemaVersion":1"#, options: .backwards))
    text.replaceSubrange(schema, with: #""schemaVersion":2"#)
    let rawDecoded = try JSONDecoder().decode(
      LocalWritingPublicAggregateSummary.self,
      from: Data(text.utf8)
    )

    #expect(throws: LocalWritingEvidenceError.invalidSummary) {
      try fixture.makeEvidence(publicSummary: rawDecoded)
    }
  }

  @Test
  func legacyEvidenceMapsExactCountsWithoutProofOrAdmissionPromotion() throws {
    let caseID = LocalWritingEvaluationFixture.caseID
    let report = try ModelEvaluationScorer.score(
      ModelEvaluationRunInput(
        schemaVersion: 1,
        modelID: "legacy-model",
        revision: "legacy-revision",
        runtime: "legacy-runtime",
        quantization: "legacy-quantization",
        hardware: "legacy-hardware",
        unexpectedNetworkConnectionCount: 0,
        cases: [
          ModelEvaluationCaseInput(
            id: caseID.uuidString.lowercased(),
            language: .english,
            reference: "hello world",
            hypothesis: "hello"
          )
        ]
      )
    )
    let benchmark = try JSONDecoder().decode(
      CandidateBenchmarkEvidence.self,
      from: try candidateBenchmarkFixtureData()
    )

    #expect(report.localWritingAccuracyObservation(for: caseID, outcome: .fail)?.edits == 1)
    #expect(
      report.localWritingAccuracyObservation(for: caseID, outcome: .fail)?.referenceUnits == 2
    )
    #expect(report.localWritingEvidenceLevel == nil)
    #expect(report.localWritingAdmissionOutcome == .notApplicable)
    #expect(benchmark.localWritingEvidenceLevel == nil)
    #expect(benchmark.localWritingAdmissionOutcome == .notApplicable)
  }

  private func candidateBenchmarkFixtureData() throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/local-dictation-candidate-benchmark-v2.json")
    return try Data(contentsOf: url)
  }
}

private final class EvidenceFixture {
  let corpus: LocalWritingEvaluationFixture
  let ledger: LocalWritingExposureLedger
  let directory: URL
  let consumedHead: LocalWritingExposureLedgerCheckpoint

  init(
    recordExposure: Bool = true,
    scoringEligibility: LocalWritingScoringEligibility = .admissionEligible
  ) throws {
    corpus = try LocalWritingEvaluationFixture(scoringEligibility: scoringEligibility)
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-evidence-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: directory.path
    )
    ledger = try LocalWritingExposureLedger.create(
      at: directory.appendingPathComponent("exposure-ledger.jsonl"),
      corpusID: LocalWritingEvaluationFixture.corpusID
    )
    let initial = try ledger.checkpoint()
    if recordExposure {
      consumedHead = try ledger.appendExposure(
        try Self.exposure(),
        expectedHead: initial.currentHeadSHA256
      )
    } else {
      consumedHead = initial
    }
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: directory)
  }

  func consumption() throws -> LocalWritingLedgerConsumptionHead {
    try LocalWritingLedgerConsumptionHead(
      verification: ledger.verify(expectedCorpusID: LocalWritingEvaluationFixture.corpusID),
      consumedHeadSHA256: consumedHead.currentHeadSHA256
    )
  }

  func values() throws -> (
    identity: LocalWritingEvaluationIdentity,
    proof: LocalWritingExecutionProof,
    caseResult: LocalWritingCaseOutcomeReference
  ) {
    let identity = try Self.identity()
    let proof = try Self.proof()
    let result = try LocalWritingCaseOutcomeReference(
      caseID: LocalWritingEvaluationFixture.caseID,
      materialLineageID: LocalWritingEvaluationFixture.lineageID,
      exposure: .exposed(Self.exposure()),
      executionVariant: try LocalWritingExecutionVariant(
        lifecycle: .coldAppColdModels,
        memory: .healthy,
        power: .normal,
        inputPath: .fileReplay,
        cancellationStage: nil
      ),
      measurements: try LocalWritingStageMeasurements(
        firstPartialMilliseconds: 100,
        stopToFinalMilliseconds: 200,
        stopToInsertionMilliseconds: 300,
        peakResidentBytes: 1_024,
        peakPhysicalFootprintBytes: 2_048,
        installedStorageBytes: 4_096,
        unexpectedNetworkConnectionCount: 0
      ),
      accuracy: try LocalWritingAccuracyObservation(
        outcome: .pass,
        edits: 1,
        referenceUnits: 10
      ),
      outcome: .pass,
      protectedMeaningOutcome: .pass,
      faithfulnessOutcome: .pass,
      routingOutcome: .notApplicable,
      cleanupOutcome: .pass,
      cancellationOutcome: .pass,
      packageOutcome: .notApplicable
    )
    return (identity, proof, result)
  }

  func makeEvidence(
    canonicalCorpusData: Data? = nil,
    verification: LocalWritingExposureLedgerVerification? = nil,
    consumption: LocalWritingLedgerConsumptionHead? = nil,
    proof: LocalWritingExecutionProof? = nil,
    cases: [LocalWritingCaseOutcomeReference]? = nil,
    publicSummary: LocalWritingPublicAggregateSummary? = nil
  ) throws -> LocalWritingEvaluationEvidence {
    let values = try values()
    let selectedCases = cases ?? [values.caseResult]
    let selectedProof = proof ?? values.proof
    let selectedConsumption = try consumption ?? self.consumption()
    let corpusIdentity = try LocalWritingCorpusEvidenceIdentity(
      canonicalCorpusData: canonicalCorpusData ?? corpus.canonicalCorpusData
    )
    let coverage = try LocalWritingCorpusCoverage(
      totalCorpusCaseCount: 1,
      evaluatedCaseCount: min(selectedCases.count, 1),
      humanSpeechEligibleCaseCount: selectedCases.isEmpty ? 0 : 1,
      syntheticCaseCount: 0,
      faultInjectionCaseCount: 0
    )
    let passGate = try LocalWritingGateSummary(
      outcome: selectedCases.isEmpty ? .notApplicable : .pass,
      applicableCaseCount: selectedCases.count,
      failedCaseCount: 0
    )
    let routingGate = try LocalWritingGateSummary(
      outcome: .notApplicable,
      applicableCaseCount: 0,
      failedCaseCount: 0
    )
    let summary = try publicSummary ?? LocalWritingPublicAggregateSummary(
      corpusIdentity: corpusIdentity,
      ledgerConsumption: selectedConsumption,
      evaluationIdentity: values.identity,
      executionProof: selectedProof,
      coverage: coverage,
      overallOutcome: selectedCases.isEmpty ? .notApplicable : .pass,
      protectedMeaning: passGate,
      faithfulness: passGate,
      routing: routingGate,
      cleanup: passGate,
      cancellation: passGate,
      package: routingGate,
      admissionOutcome: .notApplicable
    )
    return try LocalWritingEvaluationEvidence(
      canonicalCorpusData: canonicalCorpusData ?? corpus.canonicalCorpusData,
      ledgerVerification: verification ?? ledger.verify(
        expectedCorpusID: LocalWritingEvaluationFixture.corpusID
      ),
      ledgerConsumption: selectedConsumption,
      evaluationIdentity: values.identity,
      executionProof: selectedProof,
      cases: selectedCases,
      coverage: coverage,
      protectedMeaning: passGate,
      faithfulness: passGate,
      routing: routingGate,
      cleanup: passGate,
      cancellation: passGate,
      package: routingGate,
      publicSummary: summary
    )
  }

  private static func identity() throws -> LocalWritingEvaluationIdentity {
    try LocalWritingEvaluationIdentity(
      candidateIdentitySHA256: String(repeating: "4", count: 64),
      roleProfileIdentitySHA256: String(repeating: "5", count: 64),
      configurationIdentitySHA256: String(repeating: "6", count: 64),
      runtimeIdentitySHA256: String(repeating: "7", count: 64),
      executionIdentitySHA256: String(repeating: "8", count: 64)
    )
  }

  private static func exposure() throws -> LocalWritingCandidateExposure {
    let identity = try identity()
    return try LocalWritingCandidateExposure(
      corpusID: LocalWritingEvaluationFixture.corpusID,
      caseID: LocalWritingEvaluationFixture.caseID,
      materialLineageID: LocalWritingEvaluationFixture.lineageID,
      candidateIdentitySHA256: identity.candidateIdentitySHA256,
      configurationIdentitySHA256: identity.configurationIdentitySHA256,
      roleProfileIdentitySHA256: identity.roleProfileIdentitySHA256,
      executionIdentitySHA256: identity.executionIdentitySHA256,
      executionStratum: .e1
    )
  }

  private static func proof() throws -> LocalWritingExecutionProof {
    try LocalWritingExecutionProof(
      evidenceLevel: .e1,
      executionClass: .recordedHumanAudioReplay,
      hardwareIdentitySHA256: String(repeating: "7", count: 64),
      osBuildIdentitySHA256: String(repeating: "8", count: 64),
      speakerCohortIdentitySHA256: String(repeating: "9", count: 64),
      acousticCohortIdentitySHA256: String(repeating: "a", count: 64)
    )
  }
}

private extension LocalWritingCaseOutcomeReference {
  func replacing(
    exposure: LocalWritingCaseExposureReference? = nil,
    measurements: LocalWritingStageMeasurements? = nil,
    accuracy: LocalWritingAccuracyObservation? = nil,
    outcome: LocalWritingEvidenceOutcome? = nil,
    protectedMeaningOutcome: LocalWritingEvidenceOutcome? = nil,
    cleanupOutcome: LocalWritingEvidenceOutcome? = nil
  ) throws -> Self {
    try Self(
      caseID: caseID,
      materialLineageID: materialLineageID,
      exposure: exposure ?? self.exposure,
      executionVariant: executionVariant,
      measurements: measurements ?? self.measurements,
      accuracy: accuracy ?? self.accuracy,
      outcome: outcome ?? self.outcome,
      protectedMeaningOutcome: protectedMeaningOutcome ?? self.protectedMeaningOutcome,
      faithfulnessOutcome: faithfulnessOutcome,
      routingOutcome: routingOutcome,
      cleanupOutcome: cleanupOutcome ?? self.cleanupOutcome,
      cancellationOutcome: cancellationOutcome,
      packageOutcome: packageOutcome
    )
  }
}
