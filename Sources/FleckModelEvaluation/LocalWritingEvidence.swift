import CryptoKit
import Foundation

import FleckCore

public enum LocalWritingEvidenceError: String, Error, Equatable, Sendable,
  CustomStringConvertible
{
  case invalidCorpus
  case nonCanonicalCorpus
  case invalidHash
  case invalidMeasurement
  case invalidOutcome
  case invalidSummary
  case nonCanonicalSummary
  case corpusMismatch
  case ledgerMismatch
  case nonAncestorLedgerHead
  case invalidatedLineage
  case identityMismatch
  case missingExposure
  case duplicateCase
  case unknownCase
  case materialLineageMismatch
  case executionClassMismatch
  case illegalProofPromotion
  case protectedMeaningViolation
  case aggregateDisagreement

  public var description: String { rawValue }
}

public enum LocalWritingEvidenceOutcome: String, Codable, Equatable, Sendable {
  case pass
  case fail
  case notApplicable
}

public enum LocalWritingEvidenceLevel: String, Codable, Equatable, Sendable {
  case e0, e1, e2, e3, e4, e5
}

public enum LocalWritingExecutionClass: String, Codable, Equatable, Sendable {
  case deterministicSynthetic
  case recordedHumanAudioReplay
  case packagedInjectedAudio
  case packagedLiveMicrophone
}

public struct LocalWritingCorpusEvidenceIdentity: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let corpusID: UUID
  public let revisionSHA256: String
  public let manifestSHA256: String

  public init(canonicalCorpusData: Data) throws {
    let manifest: LocalWritingCorpusManifestEnvelope
    do {
      manifest = try LocalWritingCorpusCodec.decodeCanonical(canonicalCorpusData)
    } catch LocalWritingCorpusError.nonCanonicalEncoding {
      throw LocalWritingEvidenceError.nonCanonicalCorpus
    } catch {
      throw LocalWritingEvidenceError.invalidCorpus
    }
    guard (try? LocalWritingCorpusCodec.canonicalData(for: manifest)) == canonicalCorpusData else {
      throw LocalWritingEvidenceError.nonCanonicalCorpus
    }
    schemaVersion = manifest.schemaVersion
    corpusID = manifest.corpusID
    revisionSHA256 = manifest.revisionSHA256
    manifestSHA256 = localWritingSHA256(canonicalCorpusData)
  }

  private init(
    schemaVersion: Int,
    corpusID: UUID,
    revisionSHA256: String,
    manifestSHA256: String
  ) throws {
    guard schemaVersion == 1,
      localWritingIsHash(revisionSHA256),
      localWritingIsHash(manifestSHA256)
    else { throw LocalWritingEvidenceError.invalidCorpus }
    self.schemaVersion = schemaVersion
    self.corpusID = corpusID
    self.revisionSHA256 = revisionSHA256
    self.manifestSHA256 = manifestSHA256
  }

  fileprivate func validated() throws -> Self {
    try Self(
      schemaVersion: schemaVersion,
      corpusID: corpusID,
      revisionSHA256: revisionSHA256,
      manifestSHA256: manifestSHA256
    )
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, corpusID, revisionSHA256, manifestSHA256
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let corpus = try container.decode(String.self, forKey: .corpusID)
    guard corpus == corpus.lowercased(),
      let corpusID = UUID(uuidString: corpus),
      corpusID.uuidString.lowercased() == corpus
    else { throw LocalWritingEvidenceError.invalidCorpus }
    try self.init(
      schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
      corpusID: corpusID,
      revisionSHA256: container.decode(String.self, forKey: .revisionSHA256),
      manifestSHA256: container.decode(String.self, forKey: .manifestSHA256)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(corpusID.uuidString.lowercased(), forKey: .corpusID)
    try container.encode(revisionSHA256, forKey: .revisionSHA256)
    try container.encode(manifestSHA256, forKey: .manifestSHA256)
  }
}

public struct LocalWritingEvaluationIdentity: Codable, Equatable, Sendable {
  public let candidateIdentitySHA256: String
  public let roleProfileIdentitySHA256: String
  public let configurationIdentitySHA256: String
  public let runtimeIdentitySHA256: String
  public let executionIdentitySHA256: String

  public init(
    candidateIdentitySHA256: String,
    roleProfileIdentitySHA256: String,
    configurationIdentitySHA256: String,
    runtimeIdentitySHA256: String,
    executionIdentitySHA256: String
  ) throws {
    guard [
      candidateIdentitySHA256, roleProfileIdentitySHA256,
      configurationIdentitySHA256, runtimeIdentitySHA256,
      executionIdentitySHA256,
    ].allSatisfy(localWritingIsHash)
    else { throw LocalWritingEvidenceError.invalidHash }
    self.candidateIdentitySHA256 = candidateIdentitySHA256
    self.roleProfileIdentitySHA256 = roleProfileIdentitySHA256
    self.configurationIdentitySHA256 = configurationIdentitySHA256
    self.runtimeIdentitySHA256 = runtimeIdentitySHA256
    self.executionIdentitySHA256 = executionIdentitySHA256
  }

  fileprivate func validated() throws -> Self {
    try Self(
      candidateIdentitySHA256: candidateIdentitySHA256,
      roleProfileIdentitySHA256: roleProfileIdentitySHA256,
      configurationIdentitySHA256: configurationIdentitySHA256,
      runtimeIdentitySHA256: runtimeIdentitySHA256,
      executionIdentitySHA256: executionIdentitySHA256
    )
  }
}

public struct LocalWritingExecutionProof: Codable, Equatable, Sendable {
  public let evidenceLevel: LocalWritingEvidenceLevel
  public let executionClass: LocalWritingExecutionClass
  public let hardwareIdentitySHA256: String
  public let osBuildIdentitySHA256: String
  public let speakerCohortIdentitySHA256: String?
  public let acousticCohortIdentitySHA256: String?
  public let packageIdentitySHA256: String?
  public let secondDeviceHardwareIdentitySHA256: String?
  public let secondDeviceOSBuildIdentitySHA256: String?
  public let signedArtifactIdentitySHA256: String?

  public init(
    evidenceLevel: LocalWritingEvidenceLevel,
    executionClass: LocalWritingExecutionClass,
    hardwareIdentitySHA256: String,
    osBuildIdentitySHA256: String,
    speakerCohortIdentitySHA256: String? = nil,
    acousticCohortIdentitySHA256: String? = nil,
    packageIdentitySHA256: String? = nil,
    secondDeviceHardwareIdentitySHA256: String? = nil,
    secondDeviceOSBuildIdentitySHA256: String? = nil,
    signedArtifactIdentitySHA256: String? = nil
  ) throws {
    let requiredHashes = [hardwareIdentitySHA256, osBuildIdentitySHA256]
    let optionalHashes = [
      speakerCohortIdentitySHA256, acousticCohortIdentitySHA256,
      packageIdentitySHA256, secondDeviceHardwareIdentitySHA256,
      secondDeviceOSBuildIdentitySHA256, signedArtifactIdentitySHA256,
    ].compactMap { $0 }
    guard requiredHashes.allSatisfy(localWritingIsHash),
      optionalHashes.allSatisfy(localWritingIsHash)
    else { throw LocalWritingEvidenceError.invalidHash }
    guard
      (speakerCohortIdentitySHA256 == nil) == (acousticCohortIdentitySHA256 == nil),
      (secondDeviceHardwareIdentitySHA256 == nil)
        == (secondDeviceOSBuildIdentitySHA256 == nil)
    else { throw LocalWritingEvidenceError.illegalProofPromotion }

    let hasHumanCohort = speakerCohortIdentitySHA256 != nil
      && acousticCohortIdentitySHA256 != nil
    let hasPackage = packageIdentitySHA256 != nil
    let hasSecondDevice = secondDeviceHardwareIdentitySHA256 != nil
      && secondDeviceOSBuildIdentitySHA256 != nil
    let hasSignature = signedArtifactIdentitySHA256 != nil
    let valid: Bool
    switch (evidenceLevel, executionClass) {
    case (.e0, .deterministicSynthetic):
      valid = !hasHumanCohort && !hasPackage && !hasSecondDevice && !hasSignature
    case (.e1, .recordedHumanAudioReplay):
      valid = hasHumanCohort && !hasPackage && !hasSecondDevice && !hasSignature
    case (.e2, .packagedInjectedAudio):
      valid = hasHumanCohort && hasPackage && !hasSecondDevice && !hasSignature
    case (.e3, .packagedLiveMicrophone):
      valid = hasHumanCohort && hasPackage && !hasSecondDevice && !hasSignature
    case (.e4, .packagedLiveMicrophone):
      valid = hasHumanCohort && hasPackage && hasSecondDevice && !hasSignature
    case (.e5, .packagedLiveMicrophone):
      valid = hasHumanCohort && hasPackage && hasSecondDevice && hasSignature
    default:
      valid = false
    }
    guard valid else { throw LocalWritingEvidenceError.illegalProofPromotion }

    self.evidenceLevel = evidenceLevel
    self.executionClass = executionClass
    self.hardwareIdentitySHA256 = hardwareIdentitySHA256
    self.osBuildIdentitySHA256 = osBuildIdentitySHA256
    self.speakerCohortIdentitySHA256 = speakerCohortIdentitySHA256
    self.acousticCohortIdentitySHA256 = acousticCohortIdentitySHA256
    self.packageIdentitySHA256 = packageIdentitySHA256
    self.secondDeviceHardwareIdentitySHA256 = secondDeviceHardwareIdentitySHA256
    self.secondDeviceOSBuildIdentitySHA256 = secondDeviceOSBuildIdentitySHA256
    self.signedArtifactIdentitySHA256 = signedArtifactIdentitySHA256
  }

  fileprivate func validated() throws -> Self {
    try Self(
      evidenceLevel: evidenceLevel,
      executionClass: executionClass,
      hardwareIdentitySHA256: hardwareIdentitySHA256,
      osBuildIdentitySHA256: osBuildIdentitySHA256,
      speakerCohortIdentitySHA256: speakerCohortIdentitySHA256,
      acousticCohortIdentitySHA256: acousticCohortIdentitySHA256,
      packageIdentitySHA256: packageIdentitySHA256,
      secondDeviceHardwareIdentitySHA256: secondDeviceHardwareIdentitySHA256,
      secondDeviceOSBuildIdentitySHA256: secondDeviceOSBuildIdentitySHA256,
      signedArtifactIdentitySHA256: signedArtifactIdentitySHA256
    )
  }
}

public struct LocalWritingStageMeasurements: Equatable, Sendable {
  public let firstPartialMilliseconds: UInt64?
  public let stopToFinalMilliseconds: UInt64?
  public let stopToInsertionMilliseconds: UInt64?
  public let peakResidentBytes: UInt64
  public let peakPhysicalFootprintBytes: UInt64
  public let installedStorageBytes: UInt64
  public let unexpectedNetworkConnectionCount: UInt64

  public init(
    firstPartialMilliseconds: UInt64? = nil,
    stopToFinalMilliseconds: UInt64? = nil,
    stopToInsertionMilliseconds: UInt64? = nil,
    peakResidentBytes: UInt64,
    peakPhysicalFootprintBytes: UInt64,
    installedStorageBytes: UInt64,
    unexpectedNetworkConnectionCount: UInt64
  ) throws {
    let latencies = [
      firstPartialMilliseconds, stopToFinalMilliseconds,
      stopToInsertionMilliseconds,
    ].compactMap { $0 }
    guard latencies.allSatisfy({ $0 <= 1_000_000_000 }),
      peakResidentBytes <= 1_000_000_000_000_000,
      peakPhysicalFootprintBytes <= 1_000_000_000_000_000,
      installedStorageBytes <= 1_000_000_000_000_000,
      unexpectedNetworkConnectionCount <= 1_000_000
    else { throw LocalWritingEvidenceError.invalidMeasurement }
    self.firstPartialMilliseconds = firstPartialMilliseconds
    self.stopToFinalMilliseconds = stopToFinalMilliseconds
    self.stopToInsertionMilliseconds = stopToInsertionMilliseconds
    self.peakResidentBytes = peakResidentBytes
    self.peakPhysicalFootprintBytes = peakPhysicalFootprintBytes
    self.installedStorageBytes = installedStorageBytes
    self.unexpectedNetworkConnectionCount = unexpectedNetworkConnectionCount
  }
}

public struct LocalWritingAccuracyObservation: Equatable, Sendable {
  public let outcome: LocalWritingEvidenceOutcome
  public let edits: UInt64?
  public let referenceUnits: UInt64?

  public init(
    outcome: LocalWritingEvidenceOutcome,
    edits: UInt64?,
    referenceUnits: UInt64?
  ) throws {
    switch outcome {
    case .notApplicable:
      guard edits == nil, referenceUnits == nil else {
        throw LocalWritingEvidenceError.invalidOutcome
      }
    case .pass, .fail:
      guard let edits, let referenceUnits, referenceUnits > 0,
        edits <= 1_000_000_000, referenceUnits <= 1_000_000_000
      else { throw LocalWritingEvidenceError.invalidMeasurement }
    }
    self.outcome = outcome
    self.edits = edits
    self.referenceUnits = referenceUnits
  }

  public static var notApplicable: Self {
    try! Self(outcome: .notApplicable, edits: nil, referenceUnits: nil)
  }
}

public enum LocalWritingCaseExposureReference: Equatable, Sendable {
  case notApplicable
  case exposed(LocalWritingCandidateExposure)
}

public struct LocalWritingCaseOutcomeReference: Equatable, Sendable {
  public let caseID: UUID
  public let materialLineageID: UUID
  public let exposure: LocalWritingCaseExposureReference
  public let executionVariant: LocalWritingExecutionVariant
  public let measurements: LocalWritingStageMeasurements
  public let accuracy: LocalWritingAccuracyObservation
  public let outcome: LocalWritingEvidenceOutcome
  public let protectedMeaningOutcome: LocalWritingEvidenceOutcome
  public let faithfulnessOutcome: LocalWritingEvidenceOutcome
  public let routingOutcome: LocalWritingEvidenceOutcome
  public let cleanupOutcome: LocalWritingEvidenceOutcome
  public let cancellationOutcome: LocalWritingEvidenceOutcome
  public let packageOutcome: LocalWritingEvidenceOutcome

  public init(
    caseID: UUID,
    materialLineageID: UUID,
    exposure: LocalWritingCaseExposureReference,
    executionVariant: LocalWritingExecutionVariant,
    measurements: LocalWritingStageMeasurements,
    accuracy: LocalWritingAccuracyObservation,
    outcome: LocalWritingEvidenceOutcome,
    protectedMeaningOutcome: LocalWritingEvidenceOutcome,
    faithfulnessOutcome: LocalWritingEvidenceOutcome,
    routingOutcome: LocalWritingEvidenceOutcome,
    cleanupOutcome: LocalWritingEvidenceOutcome,
    cancellationOutcome: LocalWritingEvidenceOutcome,
    packageOutcome: LocalWritingEvidenceOutcome
  ) throws {
    if protectedMeaningOutcome == .fail {
      guard cleanupOutcome == .fail, outcome == .fail else {
        throw LocalWritingEvidenceError.protectedMeaningViolation
      }
    }
    let componentOutcomes = [
      protectedMeaningOutcome, faithfulnessOutcome, routingOutcome,
      cleanupOutcome, cancellationOutcome, packageOutcome,
    ]
    let hasFailure = accuracy.outcome == .fail
      || componentOutcomes.contains(.fail)
      || measurements.unexpectedNetworkConnectionCount > 0
    switch outcome {
    case .pass:
      guard !hasFailure,
        accuracy.outcome == .pass || componentOutcomes.contains(.pass)
      else { throw LocalWritingEvidenceError.invalidOutcome }
    case .fail:
      guard hasFailure else { throw LocalWritingEvidenceError.invalidOutcome }
    case .notApplicable:
      guard accuracy.outcome == .notApplicable,
        componentOutcomes.allSatisfy({ $0 == .notApplicable }),
        measurements.unexpectedNetworkConnectionCount == 0
      else { throw LocalWritingEvidenceError.invalidOutcome }
    }
    self.caseID = caseID
    self.materialLineageID = materialLineageID
    self.exposure = exposure
    self.executionVariant = executionVariant
    self.measurements = measurements
    self.accuracy = accuracy
    self.outcome = outcome
    self.protectedMeaningOutcome = protectedMeaningOutcome
    self.faithfulnessOutcome = faithfulnessOutcome
    self.routingOutcome = routingOutcome
    self.cleanupOutcome = cleanupOutcome
    self.cancellationOutcome = cancellationOutcome
    self.packageOutcome = packageOutcome
  }
}

public struct LocalWritingGateSummary: Codable, Equatable, Sendable {
  public let outcome: LocalWritingEvidenceOutcome
  public let applicableCaseCount: Int
  public let failedCaseCount: Int

  public init(
    outcome: LocalWritingEvidenceOutcome,
    applicableCaseCount: Int,
    failedCaseCount: Int
  ) throws {
    guard applicableCaseCount >= 0, applicableCaseCount <= 1_000_000,
      failedCaseCount >= 0, failedCaseCount <= applicableCaseCount
    else { throw LocalWritingEvidenceError.invalidMeasurement }
    switch outcome {
    case .notApplicable:
      guard applicableCaseCount == 0, failedCaseCount == 0 else {
        throw LocalWritingEvidenceError.invalidOutcome
      }
    case .pass:
      guard applicableCaseCount > 0, failedCaseCount == 0 else {
        throw LocalWritingEvidenceError.invalidOutcome
      }
    case .fail:
      guard applicableCaseCount > 0, failedCaseCount > 0 else {
        throw LocalWritingEvidenceError.invalidOutcome
      }
    }
    self.outcome = outcome
    self.applicableCaseCount = applicableCaseCount
    self.failedCaseCount = failedCaseCount
  }

  fileprivate func validated() throws -> Self {
    try Self(
      outcome: outcome,
      applicableCaseCount: applicableCaseCount,
      failedCaseCount: failedCaseCount
    )
  }
}

public struct LocalWritingCorpusCoverage: Codable, Equatable, Sendable {
  public let totalCorpusCaseCount: Int
  public let evaluatedCaseCount: Int
  public let humanSpeechEligibleCaseCount: Int
  public let syntheticCaseCount: Int
  public let faultInjectionCaseCount: Int

  public init(
    totalCorpusCaseCount: Int,
    evaluatedCaseCount: Int,
    humanSpeechEligibleCaseCount: Int,
    syntheticCaseCount: Int,
    faultInjectionCaseCount: Int
  ) throws {
    let counts = [
      totalCorpusCaseCount, evaluatedCaseCount, humanSpeechEligibleCaseCount,
      syntheticCaseCount, faultInjectionCaseCount,
    ]
    guard counts.allSatisfy({ $0 >= 0 && $0 <= 1_000_000 }),
      evaluatedCaseCount <= totalCorpusCaseCount,
      humanSpeechEligibleCaseCount + syntheticCaseCount + faultInjectionCaseCount
        <= evaluatedCaseCount
    else { throw LocalWritingEvidenceError.invalidMeasurement }
    self.totalCorpusCaseCount = totalCorpusCaseCount
    self.evaluatedCaseCount = evaluatedCaseCount
    self.humanSpeechEligibleCaseCount = humanSpeechEligibleCaseCount
    self.syntheticCaseCount = syntheticCaseCount
    self.faultInjectionCaseCount = faultInjectionCaseCount
  }

  fileprivate func validated() throws -> Self {
    try Self(
      totalCorpusCaseCount: totalCorpusCaseCount,
      evaluatedCaseCount: evaluatedCaseCount,
      humanSpeechEligibleCaseCount: humanSpeechEligibleCaseCount,
      syntheticCaseCount: syntheticCaseCount,
      faultInjectionCaseCount: faultInjectionCaseCount
    )
  }
}

public struct LocalWritingLedgerConsumptionHead: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let corpusID: UUID
  public let verifiedEventCount: UInt64
  public let verifiedHeadSHA256: String
  public let verifiedCheckpointSHA256: String
  public let consumedHeadSHA256: String

  public init(
    verification: LocalWritingExposureLedgerVerification,
    consumedHeadSHA256: String
  ) throws {
    guard localWritingIsHash(consumedHeadSHA256),
      verification.isAncestor(consumedHeadSHA256)
    else { throw LocalWritingEvidenceError.nonAncestorLedgerHead }
    let checkpoint = verification.checkpoint
    schemaVersion = checkpoint.schemaVersion
    corpusID = checkpoint.corpusID
    verifiedEventCount = checkpoint.eventCount
    verifiedHeadSHA256 = checkpoint.currentHeadSHA256
    verifiedCheckpointSHA256 = localWritingSHA256(checkpoint.canonicalData)
    self.consumedHeadSHA256 = consumedHeadSHA256
  }

  private init(
    schemaVersion: Int,
    corpusID: UUID,
    verifiedEventCount: UInt64,
    verifiedHeadSHA256: String,
    verifiedCheckpointSHA256: String,
    consumedHeadSHA256: String
  ) throws {
    guard schemaVersion == 1,
      [verifiedHeadSHA256, verifiedCheckpointSHA256, consumedHeadSHA256]
        .allSatisfy(localWritingIsHash)
    else { throw LocalWritingEvidenceError.ledgerMismatch }
    self.schemaVersion = schemaVersion
    self.corpusID = corpusID
    self.verifiedEventCount = verifiedEventCount
    self.verifiedHeadSHA256 = verifiedHeadSHA256
    self.verifiedCheckpointSHA256 = verifiedCheckpointSHA256
    self.consumedHeadSHA256 = consumedHeadSHA256
  }

  fileprivate func validate(
    against verification: LocalWritingExposureLedgerVerification
  ) throws {
    let checkpoint = verification.checkpoint
    guard schemaVersion == checkpoint.schemaVersion,
      corpusID == checkpoint.corpusID,
      verifiedEventCount == checkpoint.eventCount,
      verifiedHeadSHA256 == checkpoint.currentHeadSHA256,
      verifiedCheckpointSHA256 == localWritingSHA256(checkpoint.canonicalData)
    else { throw LocalWritingEvidenceError.ledgerMismatch }
    guard verification.isAncestor(consumedHeadSHA256) else {
      throw LocalWritingEvidenceError.nonAncestorLedgerHead
    }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, corpusID, verifiedEventCount, verifiedHeadSHA256
    case verifiedCheckpointSHA256, consumedHeadSHA256
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let corpus = try container.decode(String.self, forKey: .corpusID)
    guard corpus == corpus.lowercased(),
      let corpusID = UUID(uuidString: corpus),
      corpusID.uuidString.lowercased() == corpus
    else { throw LocalWritingEvidenceError.ledgerMismatch }
    try self.init(
      schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
      corpusID: corpusID,
      verifiedEventCount: container.decode(UInt64.self, forKey: .verifiedEventCount),
      verifiedHeadSHA256: container.decode(String.self, forKey: .verifiedHeadSHA256),
      verifiedCheckpointSHA256: container.decode(
        String.self, forKey: .verifiedCheckpointSHA256
      ),
      consumedHeadSHA256: container.decode(String.self, forKey: .consumedHeadSHA256)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(corpusID.uuidString.lowercased(), forKey: .corpusID)
    try container.encode(verifiedEventCount, forKey: .verifiedEventCount)
    try container.encode(verifiedHeadSHA256, forKey: .verifiedHeadSHA256)
    try container.encode(verifiedCheckpointSHA256, forKey: .verifiedCheckpointSHA256)
    try container.encode(consumedHeadSHA256, forKey: .consumedHeadSHA256)
  }
}

public struct LocalWritingPublicAggregateSummary: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let corpusIdentity: LocalWritingCorpusEvidenceIdentity
  public let ledgerConsumption: LocalWritingLedgerConsumptionHead
  public let evaluationIdentity: LocalWritingEvaluationIdentity
  public let executionProof: LocalWritingExecutionProof
  public let coverage: LocalWritingCorpusCoverage
  public let overallOutcome: LocalWritingEvidenceOutcome
  public let protectedMeaning: LocalWritingGateSummary
  public let faithfulness: LocalWritingGateSummary
  public let routing: LocalWritingGateSummary
  public let cleanup: LocalWritingGateSummary
  public let cancellation: LocalWritingGateSummary
  public let package: LocalWritingGateSummary
  public let admissionOutcome: LocalWritingEvidenceOutcome

  public var evidenceLevel: LocalWritingEvidenceLevel { executionProof.evidenceLevel }
  public var executionClass: LocalWritingExecutionClass { executionProof.executionClass }

  public init(
    corpusIdentity: LocalWritingCorpusEvidenceIdentity,
    ledgerConsumption: LocalWritingLedgerConsumptionHead,
    evaluationIdentity: LocalWritingEvaluationIdentity,
    executionProof: LocalWritingExecutionProof,
    coverage: LocalWritingCorpusCoverage,
    overallOutcome: LocalWritingEvidenceOutcome,
    protectedMeaning: LocalWritingGateSummary,
    faithfulness: LocalWritingGateSummary,
    routing: LocalWritingGateSummary,
    cleanup: LocalWritingGateSummary,
    cancellation: LocalWritingGateSummary,
    package: LocalWritingGateSummary,
    admissionOutcome: LocalWritingEvidenceOutcome
  ) throws {
    guard admissionOutcome == .notApplicable else {
      throw LocalWritingEvidenceError.illegalProofPromotion
    }
    guard corpusIdentity.corpusID == ledgerConsumption.corpusID else {
      throw LocalWritingEvidenceError.corpusMismatch
    }
    let gates = [protectedMeaning, faithfulness, routing, cleanup, cancellation, package]
    if gates.contains(where: { $0.outcome == .fail }), overallOutcome != .fail {
      throw LocalWritingEvidenceError.aggregateDisagreement
    }
    schemaVersion = 1
    self.corpusIdentity = try corpusIdentity.validated()
    self.ledgerConsumption = ledgerConsumption
    self.evaluationIdentity = try evaluationIdentity.validated()
    self.executionProof = try executionProof.validated()
    self.coverage = try coverage.validated()
    self.overallOutcome = overallOutcome
    self.protectedMeaning = try protectedMeaning.validated()
    self.faithfulness = try faithfulness.validated()
    self.routing = try routing.validated()
    self.cleanup = try cleanup.validated()
    self.cancellation = try cancellation.validated()
    self.package = try package.validated()
    self.admissionOutcome = admissionOutcome
  }

  fileprivate func validated() throws -> Self {
    guard schemaVersion == 1 else { throw LocalWritingEvidenceError.invalidSummary }
    return try Self(
      corpusIdentity: corpusIdentity,
      ledgerConsumption: ledgerConsumption,
      evaluationIdentity: evaluationIdentity,
      executionProof: executionProof,
      coverage: coverage,
      overallOutcome: overallOutcome,
      protectedMeaning: protectedMeaning,
      faithfulness: faithfulness,
      routing: routing,
      cleanup: cleanup,
      cancellation: cancellation,
      package: package,
      admissionOutcome: admissionOutcome
    )
  }
}

public enum LocalWritingPublicSummaryCodec {
  public static func canonicalData(
    for summary: LocalWritingPublicAggregateSummary
  ) throws -> Data {
    _ = try summary.validated()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(summary)
  }

  public static func decodeCanonical(
    _ data: Data
  ) throws -> LocalWritingPublicAggregateSummary {
    let summary: LocalWritingPublicAggregateSummary
    do {
      summary = try JSONDecoder().decode(LocalWritingPublicAggregateSummary.self, from: data)
      _ = try summary.validated()
    } catch let error as LocalWritingEvidenceError {
      throw error
    } catch {
      throw LocalWritingEvidenceError.invalidSummary
    }
    guard try canonicalData(for: summary) == data else {
      throw LocalWritingEvidenceError.nonCanonicalSummary
    }
    return summary
  }
}

public struct LocalWritingEvaluationEvidence: Equatable, Sendable {
  public let corpusIdentity: LocalWritingCorpusEvidenceIdentity
  public let ledgerConsumption: LocalWritingLedgerConsumptionHead
  public let evaluationIdentity: LocalWritingEvaluationIdentity
  public let executionProof: LocalWritingExecutionProof
  public let cases: [LocalWritingCaseOutcomeReference]
  public let coverage: LocalWritingCorpusCoverage
  public let protectedMeaning: LocalWritingGateSummary
  public let faithfulness: LocalWritingGateSummary
  public let routing: LocalWritingGateSummary
  public let cleanup: LocalWritingGateSummary
  public let cancellation: LocalWritingGateSummary
  public let package: LocalWritingGateSummary
  public let publicSummary: LocalWritingPublicAggregateSummary

  public init(
    canonicalCorpusData: Data,
    ledgerVerification: LocalWritingExposureLedgerVerification,
    ledgerConsumption: LocalWritingLedgerConsumptionHead,
    evaluationIdentity: LocalWritingEvaluationIdentity,
    executionProof: LocalWritingExecutionProof,
    cases: [LocalWritingCaseOutcomeReference],
    coverage: LocalWritingCorpusCoverage,
    protectedMeaning: LocalWritingGateSummary,
    faithfulness: LocalWritingGateSummary,
    routing: LocalWritingGateSummary,
    cleanup: LocalWritingGateSummary,
    cancellation: LocalWritingGateSummary,
    package: LocalWritingGateSummary,
    publicSummary: LocalWritingPublicAggregateSummary
  ) throws {
    let corpusIdentity = try LocalWritingCorpusEvidenceIdentity(
      canonicalCorpusData: canonicalCorpusData
    )
    let manifest: LocalWritingCorpusManifestEnvelope
    do {
      manifest = try LocalWritingCorpusCodec.decodeCanonical(canonicalCorpusData)
    } catch {
      throw LocalWritingEvidenceError.invalidCorpus
    }
    guard corpusIdentity.corpusID == ledgerVerification.checkpoint.corpusID else {
      throw LocalWritingEvidenceError.corpusMismatch
    }
    try ledgerConsumption.validate(against: ledgerVerification)
    guard ledgerConsumption.corpusID == corpusIdentity.corpusID else {
      throw LocalWritingEvidenceError.corpusMismatch
    }
    _ = try evaluationIdentity.validated()
    _ = try executionProof.validated()
    _ = try publicSummary.validated()
    try Self.validateCases(
      cases,
      manifest: manifest,
      ledgerVerification: ledgerVerification,
      consumedHeadSHA256: ledgerConsumption.consumedHeadSHA256,
      identity: evaluationIdentity,
      proof: executionProof
    )
    try Self.validateAggregates(
      cases: cases,
      manifest: manifest,
      coverage: coverage,
      protectedMeaning: protectedMeaning,
      faithfulness: faithfulness,
      routing: routing,
      cleanup: cleanup,
      cancellation: cancellation,
      package: package,
      summary: publicSummary,
      corpusIdentity: corpusIdentity,
      ledgerConsumption: ledgerConsumption,
      identity: evaluationIdentity,
      proof: executionProof
    )
    self.corpusIdentity = corpusIdentity
    self.ledgerConsumption = ledgerConsumption
    self.evaluationIdentity = evaluationIdentity
    self.executionProof = executionProof
    self.cases = cases
    self.coverage = coverage
    self.protectedMeaning = protectedMeaning
    self.faithfulness = faithfulness
    self.routing = routing
    self.cleanup = cleanup
    self.cancellation = cancellation
    self.package = package
    self.publicSummary = publicSummary
  }

  private static func validateCases(
    _ cases: [LocalWritingCaseOutcomeReference],
    manifest: LocalWritingCorpusManifestEnvelope,
    ledgerVerification: LocalWritingExposureLedgerVerification,
    consumedHeadSHA256: String,
    identity: LocalWritingEvaluationIdentity,
    proof: LocalWritingExecutionProof
  ) throws {
    guard !cases.isEmpty else { throw LocalWritingEvidenceError.invalidOutcome }
    guard Set(cases.map(\.caseID)).count == cases.count else {
      throw LocalWritingEvidenceError.duplicateCase
    }
    let corpusCases = Dictionary(uniqueKeysWithValues: manifest.payload.cases.map { ($0.id, $0) })
    for result in cases {
      guard let corpusCase = corpusCases[result.caseID] else {
        throw LocalWritingEvidenceError.unknownCase
      }
      guard corpusCase.materialLineageID == result.materialLineageID else {
        throw LocalWritingEvidenceError.materialLineageMismatch
      }
      guard corpusCase.executionVariants.contains(result.executionVariant) else {
        throw LocalWritingEvidenceError.executionClassMismatch
      }
      try validateSource(corpusCase, result: result, proof: proof)
      switch (proof.evidenceLevel, result.exposure) {
      case (.e0, .notApplicable):
        break
      case (.e0, .exposed):
        throw LocalWritingEvidenceError.executionClassMismatch
      case (_, .notApplicable):
        throw LocalWritingEvidenceError.missingExposure
      case (_, .exposed(let exposure)):
        guard exposure.corpusID == manifest.corpusID,
          exposure.caseID == result.caseID,
          exposure.materialLineageID == result.materialLineageID
        else { throw LocalWritingEvidenceError.materialLineageMismatch }
        guard exposure.candidateIdentitySHA256 == identity.candidateIdentitySHA256,
          exposure.configurationIdentitySHA256 == identity.configurationIdentitySHA256,
          exposure.roleProfileIdentitySHA256 == identity.roleProfileIdentitySHA256,
          exposure.executionIdentitySHA256 == identity.executionIdentitySHA256
        else { throw LocalWritingEvidenceError.identityMismatch }
        guard exposure.executionStratum == expectedStratum(for: proof.evidenceLevel) else {
          throw LocalWritingEvidenceError.executionClassMismatch
        }
        guard exposureExists(
          exposure,
          atOrBefore: consumedHeadSHA256,
          in: ledgerVerification
        ) else { throw LocalWritingEvidenceError.missingExposure }
        guard !lineageWasInvalidated(
          caseID: result.caseID,
          materialLineageID: result.materialLineageID,
          in: ledgerVerification
        ), ledgerVerification.scoringEligibility(
          exposure: exposure,
          consumedAt: consumedHeadSHA256
        ) == corpusCase.scoringEligibility
        else { throw LocalWritingEvidenceError.invalidatedLineage }
      }
    }
  }

  private static func lineageWasInvalidated(
    caseID: UUID,
    materialLineageID: UUID,
    in verification: LocalWritingExposureLedgerVerification
  ) -> Bool {
    verification.events.contains { event in
      guard case .materialLineageInvalidation(let invalidation) = event.payload else {
        return false
      }
      return invalidation.caseID == caseID
        && invalidation.materialLineageID == materialLineageID
    }
  }

  private static func exposureExists(
    _ exposure: LocalWritingCandidateExposure,
    atOrBefore consumedHeadSHA256: String,
    in verification: LocalWritingExposureLedgerVerification
  ) -> Bool {
    guard let consumedIndex = verification.events.firstIndex(where: {
      $0.eventSHA256 == consumedHeadSHA256
    }) else { return false }
    return verification.events.prefix(through: consumedIndex).contains { event in
      guard case .candidateExposure(let recorded) = event.payload else { return false }
      return recorded == exposure
    }
  }

  private static func validateSource(
    _ corpusCase: LocalWritingCorpusCase,
    result: LocalWritingCaseOutcomeReference,
    proof: LocalWritingExecutionProof
  ) throws {
    switch proof.executionClass {
    case .deterministicSynthetic:
      guard corpusCase.sourceClass == .synthetic || corpusCase.sourceClass == .faultInjection,
        !corpusCase.humanSpeechEligible, result.accuracy.outcome == .notApplicable,
        result.executionVariant.inputPath == .fileReplay
      else { throw LocalWritingEvidenceError.executionClassMismatch }
    case .recordedHumanAudioReplay:
      guard corpusCase.sourceClass != .synthetic, corpusCase.sourceClass != .faultInjection,
        corpusCase.audio != nil, result.executionVariant.inputPath == .fileReplay
      else { throw LocalWritingEvidenceError.executionClassMismatch }
      if !corpusCase.humanSpeechEligible, result.accuracy.outcome != .notApplicable {
        throw LocalWritingEvidenceError.executionClassMismatch
      }
    case .packagedInjectedAudio:
      guard corpusCase.sourceClass != .synthetic, corpusCase.sourceClass != .faultInjection,
        corpusCase.audio != nil, result.executionVariant.inputPath == .packagedInjectedAudio
      else { throw LocalWritingEvidenceError.executionClassMismatch }
      if !corpusCase.humanSpeechEligible, result.accuracy.outcome != .notApplicable {
        throw LocalWritingEvidenceError.executionClassMismatch
      }
    case .packagedLiveMicrophone:
      guard corpusCase.sourceClass != .synthetic, corpusCase.sourceClass != .faultInjection,
        corpusCase.audio != nil, result.executionVariant.inputPath == .packagedLiveMicrophone
      else { throw LocalWritingEvidenceError.executionClassMismatch }
      if !corpusCase.humanSpeechEligible, result.accuracy.outcome != .notApplicable {
        throw LocalWritingEvidenceError.executionClassMismatch
      }
    }
    let expectsPackage = proof.evidenceLevel != .e0 && proof.evidenceLevel != .e1
    guard expectsPackage == (result.packageOutcome != .notApplicable) else {
      throw LocalWritingEvidenceError.executionClassMismatch
    }
  }

  private static func expectedStratum(
    for level: LocalWritingEvidenceLevel
  ) -> LocalWritingExposureExecutionStratum {
    switch level {
    case .e0, .e1: .e1
    case .e2: .e2
    case .e3, .e4, .e5: .e3
    }
  }

  private static func validateAggregates(
    cases: [LocalWritingCaseOutcomeReference],
    manifest: LocalWritingCorpusManifestEnvelope,
    coverage: LocalWritingCorpusCoverage,
    protectedMeaning: LocalWritingGateSummary,
    faithfulness: LocalWritingGateSummary,
    routing: LocalWritingGateSummary,
    cleanup: LocalWritingGateSummary,
    cancellation: LocalWritingGateSummary,
    package: LocalWritingGateSummary,
    summary: LocalWritingPublicAggregateSummary,
    corpusIdentity: LocalWritingCorpusEvidenceIdentity,
    ledgerConsumption: LocalWritingLedgerConsumptionHead,
    identity: LocalWritingEvaluationIdentity,
    proof: LocalWritingExecutionProof
  ) throws {
    let selected = Set(cases.map(\.caseID))
    let selectedCorpusCases = manifest.payload.cases.filter { selected.contains($0.id) }
    let expectedCoverage = try LocalWritingCorpusCoverage(
      totalCorpusCaseCount: manifest.payload.cases.count,
      evaluatedCaseCount: cases.count,
      humanSpeechEligibleCaseCount: selectedCorpusCases.filter(\.humanSpeechEligible).count,
      syntheticCaseCount: selectedCorpusCases.filter { $0.sourceClass == .synthetic }.count,
      faultInjectionCaseCount: selectedCorpusCases.filter { $0.sourceClass == .faultInjection }.count
    )
    guard coverage == expectedCoverage else {
      throw LocalWritingEvidenceError.aggregateDisagreement
    }
    let expectedProtected = try gate(cases.map(\.protectedMeaningOutcome))
    let expectedFaithfulness = try gate(cases.map(\.faithfulnessOutcome))
    let expectedRouting = try gate(cases.map(\.routingOutcome))
    let expectedCleanup = try gate(cases.map(\.cleanupOutcome))
    let expectedCancellation = try gate(cases.map(\.cancellationOutcome))
    let expectedPackage = try gate(cases.map(\.packageOutcome))
    guard protectedMeaning == expectedProtected,
      faithfulness == expectedFaithfulness,
      routing == expectedRouting,
      cleanup == expectedCleanup,
      cancellation == expectedCancellation,
      package == expectedPackage
    else { throw LocalWritingEvidenceError.aggregateDisagreement }
    let overall: LocalWritingEvidenceOutcome = cases.contains { $0.outcome == .fail }
      ? .fail
      : cases.contains { $0.outcome == .pass } ? .pass : .notApplicable
    guard summary.corpusIdentity == corpusIdentity,
      summary.ledgerConsumption == ledgerConsumption,
      summary.evaluationIdentity == identity,
      summary.executionProof == proof,
      summary.coverage == coverage,
      summary.overallOutcome == overall,
      summary.protectedMeaning == protectedMeaning,
      summary.faithfulness == faithfulness,
      summary.routing == routing,
      summary.cleanup == cleanup,
      summary.cancellation == cancellation,
      summary.package == package,
      summary.admissionOutcome == .notApplicable
    else { throw LocalWritingEvidenceError.aggregateDisagreement }
  }

  private static func gate(
    _ outcomes: [LocalWritingEvidenceOutcome]
  ) throws -> LocalWritingGateSummary {
    let applicable = outcomes.filter { $0 != .notApplicable }
    let failures = applicable.filter { $0 == .fail }.count
    let outcome: LocalWritingEvidenceOutcome = applicable.isEmpty
      ? .notApplicable
      : failures == 0 ? .pass : .fail
    return try LocalWritingGateSummary(
      outcome: outcome,
      applicableCaseCount: applicable.count,
      failedCaseCount: failures
    )
  }
}

private func localWritingIsHash(_ value: String) -> Bool {
  value.count == 64
    && value != String(repeating: "0", count: 64)
    && value.utf8.allSatisfy {
      ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
    }
}

private func localWritingSHA256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
