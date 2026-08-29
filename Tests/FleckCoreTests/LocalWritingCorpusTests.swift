import Foundation
import Testing

@testable import FleckCore

@Suite
struct LocalWritingCorpusTests {
  @Test
  func localWritingCorpusValuesRoundTripThroughCanonicalCodec() throws {
    let manifest = try makeMinimalManifest()

    let encoded = try LocalWritingCorpusCodec.canonicalData(for: manifest)
    let decoded = try LocalWritingCorpusCodec.decodeCanonical(encoded)

    #expect(decoded == manifest)
    #expect(try LocalWritingCorpusCodec.canonicalData(for: decoded) == encoded)
  }

  @Test
  func localWritingCorpusDigestCoversOnlyCanonicalPayloadBytes() throws {
    let manifest = try makeMinimalManifest()
    let expectedPayload = #"{"cases":[],"claimScope":["ownerPrivateBeta"],"consentReceiptSHA256":"1111111111111111111111111111111111111111111111111111111111111111","controlledWorkspaces":[],"createdAtUnixMilliseconds":1,"language":"en-US"}"#
    let expectedEnvelope = #"{"corpusID":"00000000-0000-0000-0000-000000000001","payload":{"cases":[],"claimScope":["ownerPrivateBeta"],"consentReceiptSHA256":"1111111111111111111111111111111111111111111111111111111111111111","controlledWorkspaces":[],"createdAtUnixMilliseconds":1,"language":"en-US"},"revisionSHA256":"78930601a37a05ced1ecd0040ca74d021c41b8d33ab80a385b3e2ae60a65abc6","schemaVersion":1}"#

    #expect(manifest.revisionSHA256 == "78930601a37a05ced1ecd0040ca74d021c41b8d33ab80a385b3e2ae60a65abc6")
    #expect(Data(expectedPayload.utf8).count < Data(expectedEnvelope.utf8).count)
    #expect(try LocalWritingCorpusCodec.canonicalData(for: manifest) == Data(expectedEnvelope.utf8))
  }

  @Test
  func localWritingCorpusCodecRejectsUnknownDuplicateNullFloatAndNoncanonicalJSON() throws {
    let canonical = try LocalWritingCorpusCodec.canonicalData(for: makeMinimalManifest())
    let text = try #require(String(data: canonical, encoding: .utf8))
    let unknown = text.replacingOccurrences(
      of: #""schemaVersion":1"#,
      with: #""schemaVersion":1,"unknown":true"#
    )
    let duplicate = text.replacingOccurrences(
      of: #""schemaVersion":1"#,
      with: #""schemaVersion":1,"\u0073chemaVersion":1"#
    )
    let explicitNull = text.replacingOccurrences(of: #""language":"en-US""#, with: #""language":null"#)
    let float = text.replacingOccurrences(
      of: #""createdAtUnixMilliseconds":1"#,
      with: #""createdAtUnixMilliseconds":1.0"#
    )

    #expect(throws: LocalWritingCorpusError.unknownKey) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(unknown.utf8))
    }
    #expect(throws: LocalWritingCorpusError.duplicateKey) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(duplicate.utf8))
    }
    #expect(throws: LocalWritingCorpusError.explicitNull) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(explicitNull.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidNumber) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(float.utf8))
    }
    #expect(throws: LocalWritingCorpusError.nonCanonicalEncoding) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(" \(text)".utf8))
    }
  }

  @Test
  func localWritingCorpusCodecRejectsInvalidUTF8SurrogatesOverflowAndExcessiveDepth() throws {
    let canonical = try LocalWritingCorpusCodec.canonicalData(for: makeMinimalManifest())
    let text = try #require(String(data: canonical, encoding: .utf8))
    let surrogate = text.replacingOccurrences(
      of: #""language":"en-US""#,
      with: #""language":"\uD800""#
    )
    let overflow = text.replacingOccurrences(
      of: #""createdAtUnixMilliseconds":1"#,
      with: #""createdAtUnixMilliseconds":9223372036854775808"#
    )
    let deepValue = String(repeating: "[", count: 40) + "0"
      + String(repeating: "]", count: 40)
    let excessiveDepth = text.replacingOccurrences(
      of: #""cases":[]"#,
      with: #""cases":\#(deepValue)"#
    )

    #expect(throws: LocalWritingCorpusError.invalidUTF8) {
      try LocalWritingCorpusCodec.decodeCanonical(Data([0xFF]))
    }
    #expect(throws: LocalWritingCorpusError.invalidJSON) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(surrogate.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidNumber) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(overflow.utf8))
    }
    #expect(throws: LocalWritingCorpusError.excessiveDepth) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(excessiveDepth.utf8))
    }
    #expect(throws: LocalWritingCorpusError.inputTooLarge) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(repeating: 0x20, count: 64 * 1_024 * 1_024 + 1))
    }
  }

  @Test
  func localWritingCorpusRejectsUnsupportedSchemaLanguageClaimIdentifiersAndHashes() throws {
    let canonical = try LocalWritingCorpusCodec.canonicalData(for: makeMinimalManifest())
    let text = try #require(String(data: canonical, encoding: .utf8))
    let schema = text.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#)
    let language = text.replacingOccurrences(of: #""language":"en-US""#, with: #""language":"en-GB""#)
    let claim = text.replacingOccurrences(
      of: #""claimScope":["ownerPrivateBeta"]"#,
      with: #""claimScope":["publicBenchmark"]"#
    )
    let identifier = text.replacingOccurrences(
      of: "00000000-0000-0000-0000-000000000001",
      with: "00000000-0000-0000-0000-00000000000A"
    )
    let zeroHash = text.replacingOccurrences(
      of: String(repeating: "1", count: 64),
      with: String(repeating: "0", count: 64)
    )

    #expect(throws: LocalWritingCorpusError.unsupportedSchemaVersion) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(schema.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidLanguage) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(language.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidClaimScope) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(claim.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidIdentifier) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(identifier.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidHash) {
      try LocalWritingCorpusCodec.decodeCanonical(Data(zeroHash.utf8))
    }
    #expect(throws: LocalWritingCorpusError.invalidLanguage) {
      try LocalWritingCorpusPayload(
        language: "en-GB",
        claimScope: [.ownerPrivateBeta],
        consentReceiptSHA256: String(repeating: "1", count: 64),
        createdAtUnixMilliseconds: 1,
        controlledWorkspaces: [],
        cases: []
      )
    }
  }

  @Test
  func localWritingCorpusRequiresCompleteAudioAndMatchingConsentForHumanSources() throws {
    let consent = String(repeating: "2", count: 64)
    let audio = try LocalWritingAudioReceipt(
      relativePath: "synthetic/read.wav",
      audioSHA256: String(repeating: "3", count: 64),
      byteCount: 4_096,
      durationMilliseconds: 1_200,
      sampleRateHz: 48_000,
      channelCount: 1,
      sampleFormat: .pcmInt16,
      container: .wave,
      speakerID: try uuid("00000000-0000-0000-0000-000000000020"),
      capturedAtUnixMilliseconds: 2,
      inputDeviceClass: .builtIn,
      deviceIdentitySHA256: String(repeating: "4", count: 64),
      captureClass: .read,
      consentReceiptSHA256: consent
    )
    let humanCase = try LocalWritingCorpusCase(
      id: try uuid("00000000-0000-0000-0000-000000000021"),
      materialLineageID: try uuid("00000000-0000-0000-0000-000000000022"),
      sourceClass: .humanRead,
      humanSpeechEligible: true,
      scoringEligibility: .admissionEligible,
      audio: audio,
      referenceTranscript: "Read this sentence.",
      tags: [],
      protectedExpectations: [],
      cleanupOracle: .unchangedRequired,
      routingOracle: nil,
      executionVariants: []
    )
    let payload = try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: [.ownerPrivateBeta],
      consentReceiptSHA256: consent,
      createdAtUnixMilliseconds: 2,
      controlledWorkspaces: [],
      cases: [humanCase]
    )
    let manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: try uuid("00000000-0000-0000-0000-000000000023"),
      payload: payload
    )

    #expect(try LocalWritingCorpusCodec.decodeCanonical(
      LocalWritingCorpusCodec.canonicalData(for: manifest)
    ) == manifest)
    #expect(throws: LocalWritingCorpusError.invalidAudio) {
      try LocalWritingCorpusCase(
        id: self.uuid("00000000-0000-0000-0000-000000000024"),
        materialLineageID: self.uuid("00000000-0000-0000-0000-000000000025"),
        sourceClass: .humanRead,
        humanSpeechEligible: true,
        scoringEligibility: .admissionEligible,
        audio: nil,
        referenceTranscript: "Missing audio.",
        tags: [],
        protectedExpectations: [],
        cleanupOracle: .unchangedRequired,
        routingOracle: nil,
        executionVariants: []
      )
    }
    #expect(throws: LocalWritingCorpusError.invalidAudioConsent) {
      try LocalWritingCorpusPayload(
        language: "en-US",
        claimScope: [.ownerPrivateBeta],
        consentReceiptSHA256: String(repeating: "5", count: 64),
        createdAtUnixMilliseconds: 2,
        controlledWorkspaces: [],
        cases: [humanCase]
      )
    }
  }

  @Test
  func localWritingCorpusNeverMarksSilenceSyntheticOrFaultMaterialHumanSpeechEligible() throws {
    let silenceAudio = try makeAudio(
      captureClass: .silence,
      audioDigest: String(repeating: "6", count: 64)
    )
    let silence = try LocalWritingCorpusCase(
      id: try uuid("00000000-0000-0000-0000-000000000030"),
      materialLineageID: try uuid("00000000-0000-0000-0000-000000000031"),
      sourceClass: .humanSilence,
      humanSpeechEligible: false,
      scoringEligibility: .diagnosticOnlyPostExposure,
      audio: silenceAudio,
      referenceTranscript: "",
      tags: [.silence],
      protectedExpectations: [],
      cleanupOracle: .unchangedRequired,
      routingOracle: nil,
      executionVariants: []
    )
    #expect(silence.referenceTranscript.isEmpty)

    for source in [LocalWritingSourceClass.synthetic, .faultInjection] {
      #expect(throws: LocalWritingCorpusError.invalidEligibility) {
        try LocalWritingCorpusCase(
          id: self.uuid("00000000-0000-0000-0000-000000000032"),
          materialLineageID: self.uuid("00000000-0000-0000-0000-000000000033"),
          sourceClass: source,
          humanSpeechEligible: true,
          scoringEligibility: .diagnosticOnlyPostExposure,
          audio: nil,
          referenceTranscript: "Synthetic text.",
          tags: [],
          protectedExpectations: [],
          cleanupOracle: .unchangedRequired,
          routingOracle: nil,
          executionVariants: []
        )
      }
    }
    #expect(throws: LocalWritingCorpusError.invalidEligibility) {
      try LocalWritingCorpusCase(
        id: self.uuid("00000000-0000-0000-0000-000000000034"),
        materialLineageID: self.uuid("00000000-0000-0000-0000-000000000035"),
        sourceClass: .humanSilence,
        humanSpeechEligible: false,
        scoringEligibility: .diagnosticOnlyPostExposure,
        audio: silenceAudio,
        referenceTranscript: "not silence",
        tags: [],
        protectedExpectations: [],
        cleanupOracle: .unchangedRequired,
        routingOracle: nil,
        executionVariants: []
      )
    }
    #expect(throws: LocalWritingCorpusError.invalidEligibility) {
      try LocalWritingCorpusCase(
        id: self.uuid("00000000-0000-0000-0000-000000000037"),
        materialLineageID: self.uuid("00000000-0000-0000-0000-000000000038"),
        sourceClass: .humanSilence,
        humanSpeechEligible: false,
        scoringEligibility: .admissionEligible,
        audio: silenceAudio,
        referenceTranscript: "",
        tags: [.silence],
        protectedExpectations: [],
        cleanupOracle: .unchangedRequired,
        routingOracle: nil,
        executionVariants: []
      )
    }
  }

  @Test
  func localWritingCorpusRejectsAdmissionMaterialReuseAndConflictingAudioMetadata() throws {
    let lineage = try uuid("00000000-0000-0000-0000-000000000040")
    let firstAudio = try makeAudio(
      captureClass: .read,
      audioDigest: String(repeating: "8", count: 64)
    )
    let secondAudio = try makeAudio(
      captureClass: .read,
      audioDigest: String(repeating: "9", count: 64)
    )
    let first = try makeHumanReadCase(
      id: uuid("00000000-0000-0000-0000-000000000041"),
      lineage: lineage,
      audio: firstAudio,
      scoring: .admissionEligible
    )
    let reusedLineage = try makeHumanReadCase(
      id: uuid("00000000-0000-0000-0000-000000000042"),
      lineage: lineage,
      audio: secondAudio,
      scoring: .admissionEligible
    )

    #expect(throws: LocalWritingCorpusError.duplicateAdmissionMaterial) {
      try self.makePayload(cases: [first, reusedLineage])
    }

    let conflictingAudio = try LocalWritingAudioReceipt(
      relativePath: "synthetic/conflict.wav",
      audioSHA256: firstAudio.audioSHA256,
      byteCount: firstAudio.byteCount + 1,
      durationMilliseconds: firstAudio.durationMilliseconds,
      sampleRateHz: firstAudio.sampleRateHz,
      channelCount: firstAudio.channelCount,
      sampleFormat: firstAudio.sampleFormat,
      container: firstAudio.container,
      speakerID: firstAudio.speakerID,
      capturedAtUnixMilliseconds: firstAudio.capturedAtUnixMilliseconds,
      inputDeviceClass: firstAudio.inputDeviceClass,
      deviceIdentitySHA256: firstAudio.deviceIdentitySHA256,
      captureClass: firstAudio.captureClass,
      consentReceiptSHA256: firstAudio.consentReceiptSHA256
    )
    let diagnosticFirst = try makeHumanReadCase(
      id: uuid("00000000-0000-0000-0000-000000000043"),
      lineage: uuid("00000000-0000-0000-0000-000000000044"),
      audio: firstAudio,
      scoring: .diagnosticOnlyPostExposure
    )
    let diagnosticConflict = try makeHumanReadCase(
      id: uuid("00000000-0000-0000-0000-000000000045"),
      lineage: uuid("00000000-0000-0000-0000-000000000046"),
      audio: conflictingAudio,
      scoring: .diagnosticOnlyPostExposure
    )
    #expect(throws: LocalWritingCorpusError.conflictingAudioMetadata) {
      try self.makePayload(cases: [diagnosticFirst, diagnosticConflict])
    }
  }

  @Test
  func localWritingCorpusRejectsUnsafeLexicalAudioPaths() throws {
    let unsafePaths = [
      "", "/absolute.wav", "folder\\clip.wav", "folder/clip\0.wav", "folder//clip.wav",
      "folder/", ".", "..", "./clip.wav", "folder/./clip.wav", "folder/../clip.wav",
      "folder/%2e%2e/clip.wav", "folder/%2Fclip.wav",
    ]
    for path in unsafePaths {
      #expect(throws: LocalWritingCorpusError.invalidAudioPath) {
        try self.makeAudio(
          captureClass: .read,
          audioDigest: String(repeating: "a", count: 64),
          relativePath: path
        )
      }
    }

    let literalPercent = try makeAudio(
      captureClass: .read,
      audioDigest: String(repeating: "b", count: 64),
      relativePath: "folder/100%ready.wav"
    )
    #expect(literalPercent.relativePath == "folder/100%ready.wav")
  }

  @Test
  func localWritingCorpusRejectsInvalidOverlappingOrMismatchedProtectedExpectations() throws {
    let number = try LocalWritingProtectedExpectation(
      kind: .number,
      text: "12",
      utf16Start: 4,
      utf16Length: 2,
      comparison: .exact
    )
    let quantity = try LocalWritingProtectedExpectation(
      kind: .quantity,
      text: "12 kg",
      utf16Start: 4,
      utf16Length: 5,
      comparison: .caseAndWhitespaceInsensitive
    )
    let valid = try makeSyntheticCase(
      id: uuid("00000000-0000-0000-0000-000000000050"),
      lineage: uuid("00000000-0000-0000-0000-000000000051"),
      transcript: "Buy 12 kg for Alice.",
      protectedExpectations: [quantity, number]
    )
    #expect(valid.protectedExpectations.map(\.kind) == [.number, .quantity])

    let mismatch = try LocalWritingProtectedExpectation(
      kind: .number,
      text: "13",
      utf16Start: 4,
      utf16Length: 2,
      comparison: .exact
    )
    #expect(throws: LocalWritingCorpusError.invalidProtectedExpectation) {
      try self.makeSyntheticCase(
        id: self.uuid("00000000-0000-0000-0000-000000000052"),
        lineage: self.uuid("00000000-0000-0000-0000-000000000053"),
        transcript: "Buy 12 kg for Alice.",
        protectedExpectations: [mismatch]
      )
    }
    let splitSurrogate = try LocalWritingProtectedExpectation(
      kind: .quoted,
      text: "x",
      utf16Start: 1,
      utf16Length: 1,
      comparison: .exact
    )
    #expect(throws: LocalWritingCorpusError.invalidProtectedExpectation) {
      try self.makeSyntheticCase(
        id: self.uuid("00000000-0000-0000-0000-000000000054"),
        lineage: self.uuid("00000000-0000-0000-0000-000000000055"),
        transcript: "😀x",
        protectedExpectations: [splitSurrogate]
      )
    }
    let crossingA = try LocalWritingProtectedExpectation(
      kind: .name,
      text: "abcd",
      utf16Start: 0,
      utf16Length: 4,
      comparison: .exact
    )
    let crossingB = try LocalWritingProtectedExpectation(
      kind: .quoted,
      text: "cdef",
      utf16Start: 2,
      utf16Length: 4,
      comparison: .exact
    )
    #expect(throws: LocalWritingCorpusError.invalidProtectedExpectation) {
      try self.makeSyntheticCase(
        id: self.uuid("00000000-0000-0000-0000-000000000056"),
        lineage: self.uuid("00000000-0000-0000-0000-000000000057"),
        transcript: "abcdef",
        protectedExpectations: [crossingA, crossingB]
      )
    }
    #expect(throws: LocalWritingCorpusError.invalidProtectedExpectation) {
      try LocalWritingProtectedExpectation(
        kind: .path,
        text: "x",
        utf16Start: UInt64.max,
        utf16Length: 1,
        comparison: .exact
      )
    }
  }

  @Test
  func localWritingCorpusRejectsMalformedOrDuplicateCleanupPermissions() throws {
    let filler = try LocalWritingCleanupEditOperation.deleteFiller("um")
    let duplicate = try LocalWritingCleanupEditOperation.deleteImmediateDuplicate(["send", "this"])
    let correction = try LocalWritingCleanupEditOperation.selectExplicitCorrection(
      removed: ["red"],
      kept: ["blue"]
    )
    let oracle = try LocalWritingCleanupOracle.allowedOperations([
      .whitespace, correction, filler, .caseChange, duplicate, .formatList, .punctuation,
    ])
    let corpusCase = try makeSyntheticCase(
      id: uuid("00000000-0000-0000-0000-000000000060"),
      lineage: uuid("00000000-0000-0000-0000-000000000061"),
      transcript: "Um send this red, blue.",
      cleanupOracle: oracle
    )
    let manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: uuid("00000000-0000-0000-0000-000000000062"),
      payload: makePayload(cases: [corpusCase])
    )
    #expect(try LocalWritingCorpusCodec.decodeCanonical(
      LocalWritingCorpusCodec.canonicalData(for: manifest)
    ) == manifest)

    #expect(throws: LocalWritingCorpusError.invalidCleanupOracle) {
      try LocalWritingCleanupEditOperation.deleteFiller("")
    }
    #expect(throws: LocalWritingCorpusError.invalidCleanupOracle) {
      try LocalWritingCleanupEditOperation.deleteImmediateDuplicate([])
    }
    #expect(throws: LocalWritingCorpusError.invalidCleanupOracle) {
      try LocalWritingCleanupEditOperation.selectExplicitCorrection(removed: [""], kept: ["blue"])
    }
    #expect(throws: LocalWritingCorpusError.invalidCleanupOracle) {
      try LocalWritingCleanupOracle.exact("")
    }
    #expect(throws: LocalWritingCorpusError.invalidCleanupOracle) {
      try LocalWritingCleanupOracle.allowedOperations([])
    }
    #expect(throws: LocalWritingCorpusError.invalidCleanupOracle) {
      try LocalWritingCleanupOracle.allowedOperations([filler, filler])
    }
  }

  @Test
  func localWritingCorpusRejectsRoutingKeysOutsideTheSelectedControlledWorkspace() throws {
    let workspaceID = try uuid("00000000-0000-0000-0000-000000000070")
    let workspace = try makeWorkspace(
      id: workspaceID,
      notes: [
        makeNote(key: "target-b", id: uuid("00000000-0000-0000-0000-000000000071")),
        makeNote(key: "inbox", id: uuid("00000000-0000-0000-0000-000000000072")),
        makeNote(key: "target-a", id: uuid("00000000-0000-0000-0000-000000000073")),
      ]
    )
    let routing = try LocalWritingRoutingOracle(
      workspaceID: workspaceID,
      expectation: .unique("target-a")
    )
    let corpusCase = try makeSyntheticCase(
      id: uuid("00000000-0000-0000-0000-000000000074"),
      lineage: uuid("00000000-0000-0000-0000-000000000075"),
      transcript: "Route this fixture.",
      routingOracle: routing
    )
    let validPayload = try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: [.ownerPrivateBeta],
      consentReceiptSHA256: String(repeating: "2", count: 64),
      createdAtUnixMilliseconds: 5,
      controlledWorkspaces: [workspace],
      cases: [corpusCase]
    )
    let manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: uuid("00000000-0000-0000-0000-000000000076"),
      payload: validPayload
    )
    #expect(try LocalWritingCorpusCodec.decodeCanonical(
      LocalWritingCorpusCodec.canonicalData(for: manifest)
    ) == manifest)

    for expectation in [
      try LocalWritingRoutingExpectation.unique("missing"),
      try LocalWritingRoutingExpectation.unique("inbox"),
      try LocalWritingRoutingExpectation.ambiguous(["inbox", "target-a"]),
      try LocalWritingRoutingExpectation.ambiguous(["target-a", "missing"]),
    ] {
      let invalidCase = try makeSyntheticCase(
        id: uuid("00000000-0000-0000-0000-000000000077"),
        lineage: uuid("00000000-0000-0000-0000-000000000078"),
        transcript: "Invalid route.",
        routingOracle: LocalWritingRoutingOracle(
          workspaceID: workspaceID,
          expectation: expectation
        )
      )
      #expect(throws: LocalWritingCorpusError.invalidRouting) {
        try LocalWritingCorpusPayload(
          language: "en-US",
          claimScope: [.ownerPrivateBeta],
          consentReceiptSHA256: String(repeating: "2", count: 64),
          createdAtUnixMilliseconds: 5,
          controlledWorkspaces: [workspace],
          cases: [invalidCase]
        )
      }
    }
  }

  @Test
  func localWritingCorpusRejectsDuplicateMissingInboxOrInvalidWorkspaceMutations() throws {
    let inbox = try makeNote(
      key: "inbox",
      id: uuid("00000000-0000-0000-0000-000000000080")
    )
    let target = try makeNote(
      key: "target",
      id: uuid("00000000-0000-0000-0000-000000000081"),
      revision: 1
    )
    let replacement = try LocalWritingControlledNote(
      fixtureKey: target.fixtureKey,
      noteID: target.noteID,
      title: "Replacement",
      body: "Replacement body",
      revision: 2
    )
    let created = try makeNote(
      key: "created",
      id: uuid("00000000-0000-0000-0000-000000000082")
    )
    let validMutations = [
      try LocalWritingWorkspaceMutation(
        sequence: 1,
        operation: .replace(
          fixtureKey: "target",
          expectedRevision: 1,
          replacement: replacement
        )
      ),
      try LocalWritingWorkspaceMutation(sequence: 2, operation: .create(created)),
      try LocalWritingWorkspaceMutation(
        sequence: 3,
        operation: .delete(fixtureKey: "created", expectedRevision: 0)
      ),
    ]
    let workspace = try makeWorkspace(
      id: uuid("00000000-0000-0000-0000-000000000083"),
      notes: [target, inbox],
      mutations: validMutations
    )
    let manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: uuid("00000000-0000-0000-0000-000000000084"),
      payload: LocalWritingCorpusPayload(
        language: "en-US",
        claimScope: [.ownerPrivateBeta],
        consentReceiptSHA256: String(repeating: "2", count: 64),
        createdAtUnixMilliseconds: 6,
        controlledWorkspaces: [workspace],
        cases: []
      )
    )
    #expect(try LocalWritingCorpusCodec.decodeCanonical(
      LocalWritingCorpusCodec.canonicalData(for: manifest)
    ) == manifest)

    #expect(throws: LocalWritingCorpusError.invalidWorkspace) {
      try LocalWritingControlledWorkspacePayload(
        cohort: .ownerLiveFixture,
        inboxFixtureKey: "inbox",
        notes: [target],
        mutationSchedule: []
      )
    }
    #expect(throws: LocalWritingCorpusError.invalidWorkspace) {
      try LocalWritingControlledWorkspacePayload(
        cohort: .ownerLiveFixture,
        inboxFixtureKey: "inbox",
        notes: [inbox, self.makeNote(
          key: "inbox",
          id: self.uuid("00000000-0000-0000-0000-000000000085")
        )],
        mutationSchedule: []
      )
    }
    #expect(throws: LocalWritingCorpusError.invalidWorkspaceMutation) {
      try LocalWritingControlledWorkspacePayload(
        cohort: .ownerLiveFixture,
        inboxFixtureKey: "inbox",
        notes: [inbox, target],
        mutationSchedule: [LocalWritingWorkspaceMutation(
          sequence: 2,
          operation: .delete(fixtureKey: "target", expectedRevision: 1)
        )]
      )
    }
    #expect(throws: LocalWritingCorpusError.invalidWorkspaceMutation) {
      try LocalWritingControlledWorkspacePayload(
        cohort: .ownerLiveFixture,
        inboxFixtureKey: "inbox",
        notes: [inbox, target],
        mutationSchedule: [LocalWritingWorkspaceMutation(
          sequence: 1,
          operation: .delete(fixtureKey: "inbox", expectedRevision: 0)
        )]
      )
    }
    let deletedThenReused = [
      try LocalWritingWorkspaceMutation(
        sequence: 1,
        operation: .delete(fixtureKey: "target", expectedRevision: 1)
      ),
      try LocalWritingWorkspaceMutation(sequence: 2, operation: .create(
        makeNote(
          key: "target",
          id: uuid("00000000-0000-0000-0000-000000000086")
        )
      )),
    ]
    #expect(throws: LocalWritingCorpusError.invalidWorkspaceMutation) {
      try LocalWritingControlledWorkspacePayload(
        cohort: .ownerLiveFixture,
        inboxFixtureKey: "inbox",
        notes: [inbox, target],
        mutationSchedule: deletedThenReused
      )
    }
  }

  @Test
  func localWritingCorpusCanonicalizesTagsOperationsScenariosCasesAndWorkspaces() throws {
    let rawTags = [
      "immediateSpeechAfterKeyDown", "delayedSpeech", "quietRoom", "fanNoise",
      "keyboardNoise", "ambientNoise", "lowInputLevel", "normalInputLevel",
      "highInputLevel", "builtInMicrophone", "usbExternalMicrophone", "bluetoothAirPods",
      "inputDeviceChangeBeforeCapture", "inputDeviceLossDuringCapture", "veryShortUtterance",
      "thirtySecondUtterance", "sixtySecondUtterance", "oneHundredTwentySecondUtterance",
      "silence", "nonSpeech", "finalWordImmediatelyBeforeRelease", "interruption",
      "sleepWake", "lowPowerMode", "thermalPressure", "memoryPressure", "properName",
      "technicalProductName", "acronym", "initialism", "chemistryTerm", "scientificTerm",
      "codeIdentifier", "filePath", "url", "email", "command", "currency", "price",
      "amount", "date", "time", "unit", "measurement", "recipient", "destination",
      "commitment", "negation", "possibility", "requirement", "modality", "quotedText",
      "list", "punctuationSensitiveUtterance", "isolatedFiller", "repeatedFiller",
      "immediateDuplicate", "stutter", "falseStart", "explicitCorrection",
      "conversationalScaffolding", "alreadyCleanNoOp", "ambiguousCorrection",
      "prohibitedSummary", "promptInjectionShapedSpeech", "strayTokenRegression",
      "longMutableTail", "deadlineBoundary", "cancellationBoundary", "exactUniqueTitle",
      "uniqueBodyContextMatch", "uniquePersonalTermMatch", "ambiguousCloseCandidates",
      "noEligibleMatch", "duplicateTitles", "untitledNote", "deletedCandidate",
      "changedNoteRevision", "incompleteIndexScan", "staleDictionaryRevision", "modelTie",
      "malformedModelJudgment", "unknownModelKey", "chooserDestinationDeletedBeforeSelection",
      "keepInInbox", "receiptBoundMove", "receiptBoundUndo",
    ]
    #expect(LocalCorpusTag.allCases.map(\.rawValue) == rawTags)

    let operations = try LocalWritingCleanupOracle.allowedOperations([
      .whitespace,
      .formatList,
      .punctuation,
      .deleteImmediateDuplicate(["a"]),
      .deleteFiller("um"),
      .selectExplicitCorrection(removed: ["red"], kept: ["blue"]),
      .caseChange,
    ])
    #expect(operations.operations?.map(\.type) == [
      .selectExplicitCorrection, .caseChange, .deleteFiller, .deleteImmediateDuplicate,
      .formatList, .punctuation, .whitespace,
    ])

    let noCancellation = try LocalWritingExecutionVariant(
      lifecycle: .warmASRColdCleanup,
      memory: .healthy,
      power: .normal,
      inputPath: .fileReplay,
      cancellationStage: nil
    )
    let routingCancellation = try LocalWritingExecutionVariant(
      lifecycle: .warmASRColdCleanup,
      memory: .healthy,
      power: .normal,
      inputPath: .fileReplay,
      cancellationStage: .duringRouting
    )
    let cold = try LocalWritingExecutionVariant(
      lifecycle: .coldAppColdModels,
      memory: .critical,
      power: .lowPowerMode,
      inputPath: .packagedLiveMicrophone,
      cancellationStage: .beforeSourceStart
    )
    let laterWorkspace = try makeWorkspace(
      id: uuid("00000000-0000-0000-0000-000000000091"),
      notes: [
        makeNote(key: "z-note", id: uuid("00000000-0000-0000-0000-000000000092")),
        makeNote(key: "inbox", id: uuid("00000000-0000-0000-0000-000000000093")),
      ]
    )
    let earlierWorkspace = try makeWorkspace(
      id: uuid("00000000-0000-0000-0000-000000000090"),
      notes: [
        makeNote(key: "inbox", id: uuid("00000000-0000-0000-0000-000000000094")),
      ]
    )
    let goldenWorkspacePayload = #"{"cohort":"ownerLiveFixture","inboxFixtureKey":"inbox","mutationSchedule":[],"notes":[{"body":"Body inbox","fixtureKey":"inbox","noteID":"00000000-0000-0000-0000-000000000094","revision":0,"title":"Title inbox"}]}"#
    #expect(earlierWorkspace.revisionSHA256 == "c553112be0dd1cb12b7ab68785a7e1b1ffe1af2f89c56a67bdf6fdd1320bf682")
    let laterCase = try makeSyntheticCase(
      id: uuid("00000000-0000-0000-0000-000000000096"),
      lineage: uuid("00000000-0000-0000-0000-000000000097"),
      transcript: "Later case.",
      cleanupOracle: operations,
      tags: [.url, .properName],
      executionVariants: [routingCancellation, cold, noCancellation]
    )
    let earlierCase = try makeSyntheticCase(
      id: uuid("00000000-0000-0000-0000-000000000095"),
      lineage: uuid("00000000-0000-0000-0000-000000000098"),
      transcript: "Earlier case."
    )
    let payload = try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: [.ownerPrivateBeta],
      consentReceiptSHA256: String(repeating: "2", count: 64),
      createdAtUnixMilliseconds: 7,
      controlledWorkspaces: [laterWorkspace, earlierWorkspace],
      cases: [laterCase, earlierCase]
    )
    #expect(payload.controlledWorkspaces.map(\.workspaceID) == [
      earlierWorkspace.workspaceID, laterWorkspace.workspaceID,
    ])
    #expect(payload.cases.map(\.id) == [earlierCase.id, laterCase.id])
    #expect(payload.cases[1].tags == [.properName, .url])
    #expect(payload.cases[1].executionVariants == [cold, noCancellation, routingCancellation])
    let manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: uuid("00000000-0000-0000-0000-000000000099"),
      payload: payload
    )
    let encoded = try LocalWritingCorpusCodec.canonicalData(for: manifest)
    #expect(try #require(String(data: encoded, encoding: .utf8)).contains(
      #""payload":\#(goldenWorkspacePayload),"revisionSHA256":"c553112be0dd1cb12b7ab68785a7e1b1ffe1af2f89c56a67bdf6fdd1320bf682""#
    ))
    #expect(try LocalWritingCorpusCodec.decodeCanonical(encoded) == manifest)

    #expect(throws: LocalWritingCorpusError.duplicateCanonicalValue) {
      try self.makeSyntheticCase(
        id: self.uuid("00000000-0000-0000-0000-00000000009a"),
        lineage: self.uuid("00000000-0000-0000-0000-00000000009b"),
        transcript: "Duplicate tags.",
        tags: [.url, .url]
      )
    }
    #expect(throws: LocalWritingCorpusError.duplicateCanonicalValue) {
      try self.makeSyntheticCase(
        id: self.uuid("00000000-0000-0000-0000-00000000009c"),
        lineage: self.uuid("00000000-0000-0000-0000-00000000009d"),
        transcript: "Duplicate scenarios.",
        executionVariants: [noCancellation, noCancellation]
      )
    }
  }

  private func makeMinimalManifest() throws -> LocalWritingCorpusManifestEnvelope {
    let payload = try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: [.ownerPrivateBeta],
      consentReceiptSHA256: String(repeating: "1", count: 64),
      createdAtUnixMilliseconds: 1,
      controlledWorkspaces: [],
      cases: []
    )
    return try LocalWritingCorpusCodec.makeManifest(
      corpusID: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
      payload: payload
    )
  }

  private func uuid(_ value: String) throws -> UUID {
    try #require(UUID(uuidString: value))
  }

  private func makeAudio(
    captureClass: LocalWritingCaptureClass,
    audioDigest: String,
    consent: String = String(repeating: "2", count: 64),
    relativePath: String = "synthetic/fixture.wav"
  ) throws -> LocalWritingAudioReceipt {
    try LocalWritingAudioReceipt(
      relativePath: relativePath,
      audioSHA256: audioDigest,
      byteCount: 2_048,
      durationMilliseconds: 500,
      sampleRateHz: 16_000,
      channelCount: 1,
      sampleFormat: .pcmInt16,
      container: .wave,
      speakerID: uuid("00000000-0000-0000-0000-000000000036"),
      capturedAtUnixMilliseconds: 3,
      inputDeviceClass: .builtIn,
      deviceIdentitySHA256: String(repeating: "7", count: 64),
      captureClass: captureClass,
      consentReceiptSHA256: consent
    )
  }

  private func makeHumanReadCase(
    id: UUID,
    lineage: UUID,
    audio: LocalWritingAudioReceipt,
    scoring: LocalWritingScoringEligibility
  ) throws -> LocalWritingCorpusCase {
    try LocalWritingCorpusCase(
      id: id,
      materialLineageID: lineage,
      sourceClass: .humanRead,
      humanSpeechEligible: true,
      scoringEligibility: scoring,
      audio: audio,
      referenceTranscript: "Read this sentence.",
      tags: [],
      protectedExpectations: [],
      cleanupOracle: .unchangedRequired,
      routingOracle: nil,
      executionVariants: []
    )
  }

  private func makePayload(
    cases: [LocalWritingCorpusCase]
  ) throws -> LocalWritingCorpusPayload {
    try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: [.ownerPrivateBeta],
      consentReceiptSHA256: String(repeating: "2", count: 64),
      createdAtUnixMilliseconds: 4,
      controlledWorkspaces: [],
      cases: cases
    )
  }

  private func makeSyntheticCase(
    id: UUID,
    lineage: UUID,
    transcript: String,
    protectedExpectations: [LocalWritingProtectedExpectation] = [],
    cleanupOracle: LocalWritingCleanupOracle = .unchangedRequired,
    routingOracle: LocalWritingRoutingOracle? = nil,
    tags: [LocalCorpusTag] = [],
    executionVariants: [LocalWritingExecutionVariant] = []
  ) throws -> LocalWritingCorpusCase {
    try LocalWritingCorpusCase(
      id: id,
      materialLineageID: lineage,
      sourceClass: .synthetic,
      humanSpeechEligible: false,
      scoringEligibility: .diagnosticOnlyPostExposure,
      audio: nil,
      referenceTranscript: transcript,
      tags: tags,
      protectedExpectations: protectedExpectations,
      cleanupOracle: cleanupOracle,
      routingOracle: routingOracle,
      executionVariants: executionVariants
    )
  }

  private func makeNote(key: String, id: UUID, revision: UInt64 = 0) throws
    -> LocalWritingControlledNote
  {
    try LocalWritingControlledNote(
      fixtureKey: key,
      noteID: id,
      title: "Title \(key)",
      body: "Body \(key)",
      revision: revision
    )
  }

  private func makeWorkspace(
    id: UUID,
    notes: [LocalWritingControlledNote],
    mutations: [LocalWritingWorkspaceMutation] = []
  ) throws -> LocalWritingControlledWorkspaceManifestEnvelope {
    let payload = try LocalWritingControlledWorkspacePayload(
      cohort: .ownerLiveFixture,
      inboxFixtureKey: "inbox",
      notes: notes,
      mutationSchedule: mutations
    )
    return try LocalWritingCorpusCodec.makeControlledWorkspace(
      workspaceID: id,
      payload: payload
    )
  }
}
