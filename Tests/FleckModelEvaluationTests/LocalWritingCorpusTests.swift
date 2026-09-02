import Foundation
import Testing

import FleckCore
@testable import FleckModelEvaluation

@Suite
struct LocalWritingCorpusTests {
  @Test
  func evaluationIdentityUsesTheCanonicalFleckCoreCorpus() throws {
    let fixture = try LocalWritingEvaluationFixture()
    let identity = try LocalWritingCorpusEvidenceIdentity(
      canonicalCorpusData: fixture.canonicalCorpusData
    )

    #expect(identity.schemaVersion == fixture.manifest.schemaVersion)
    #expect(identity.corpusID == fixture.manifest.corpusID)
    #expect(identity.revisionSHA256 == fixture.manifest.revisionSHA256)
    #expect(identity.manifestSHA256.count == 64)

    #expect(throws: LocalWritingEvidenceError.nonCanonicalCorpus) {
      try LocalWritingCorpusEvidenceIdentity(
        canonicalCorpusData: fixture.canonicalCorpusData + Data([0x20])
      )
    }
  }

  @Test
  func evaluationIdentityRejectsACorpusWithTheWrongCanonicalDigest() throws {
    let fixture = try LocalWritingEvaluationFixture()
    let text = try #require(String(data: fixture.canonicalCorpusData, encoding: .utf8))
    let corrupted = text.replacingOccurrences(
      of: fixture.manifest.revisionSHA256,
      with: String(repeating: "f", count: 64)
    )

    #expect(throws: LocalWritingEvidenceError.invalidCorpus) {
      try LocalWritingCorpusEvidenceIdentity(canonicalCorpusData: Data(corrupted.utf8))
    }
  }
}

struct LocalWritingEvaluationFixture {
  static let corpusID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
  static let caseID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
  static let lineageID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
  static let speakerID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!

  let manifest: LocalWritingCorpusManifestEnvelope
  let canonicalCorpusData: Data

  init(
    sourceClass: LocalWritingSourceClass = .humanRead,
    scoringEligibility: LocalWritingScoringEligibility = .admissionEligible
  ) throws {
    let isSynthetic = sourceClass == .synthetic || sourceClass == .faultInjection
    let consent = String(repeating: "1", count: 64)
    let audio: LocalWritingAudioReceipt?
    if isSynthetic {
      audio = nil
    } else {
      audio = try LocalWritingAudioReceipt(
        relativePath: "audio/case.wav",
        audioSHA256: String(repeating: "2", count: 64),
        byteCount: 128,
        durationMilliseconds: 1_000,
        sampleRateHz: 16_000,
        channelCount: 1,
        sampleFormat: .pcmInt16,
        container: .wave,
        speakerID: Self.speakerID,
        capturedAtUnixMilliseconds: 1,
        inputDeviceClass: .builtIn,
        deviceIdentitySHA256: String(repeating: "3", count: 64),
        captureClass: sourceClass == .humanSilence ? .silence : .read,
        consentReceiptSHA256: consent
      )
    }
    let reference = sourceClass == .humanSilence ? "" : "Call Alice tomorrow"
    let corpusCase = try LocalWritingCorpusCase(
      id: Self.caseID,
      materialLineageID: Self.lineageID,
      sourceClass: sourceClass,
      humanSpeechEligible: !isSynthetic && sourceClass != .humanSilence,
      scoringEligibility: scoringEligibility,
      audio: audio,
      referenceTranscript: reference,
      tags: isSynthetic ? [.cancellationBoundary] : [.properName],
      protectedExpectations: [],
      cleanupOracle: try .exact(reference),
      routingOracle: nil,
      executionVariants: [
        try LocalWritingExecutionVariant(
          lifecycle: .coldAppColdModels,
          memory: .healthy,
          power: .normal,
          inputPath: isSynthetic ? .fileReplay : .fileReplay,
          cancellationStage: nil
        )
      ]
    )
    let payload = try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: .ownerPrivateBeta,
      consentReceiptSHA256: consent,
      createdAtUnixMilliseconds: 1,
      controlledWorkspaces: [],
      cases: [corpusCase]
    )
    manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: Self.corpusID,
      payload: payload
    )
    canonicalCorpusData = try LocalWritingCorpusCodec.canonicalData(for: manifest)
  }
}
