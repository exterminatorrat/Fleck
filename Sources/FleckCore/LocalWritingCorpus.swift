import CryptoKit
import Foundation

public enum LocalWritingCorpusError: String, Error, Equatable, Sendable,
  CustomStringConvertible
{
  case invalidJSON
  case invalidUTF8
  case inputTooLarge
  case excessiveDepth
  case unknownKey
  case duplicateKey
  case explicitNull
  case invalidNumber
  case unsupportedSchemaVersion
  case invalidLanguage
  case invalidClaimScope
  case invalidValue
  case invalidIdentifier
  case invalidHash
  case invalidAudio
  case invalidAudioPath
  case invalidAudioConsent
  case invalidEligibility
  case duplicateAdmissionMaterial
  case conflictingAudioMetadata
  case invalidProtectedExpectation
  case invalidCleanupOracle
  case invalidWorkspace
  case invalidWorkspaceMutation
  case invalidRouting
  case duplicateCanonicalValue
  case digestMismatch
  case nonCanonicalEncoding

  public var description: String { rawValue }
}

public enum LocalWritingClaimScope: String, Equatable, Sendable {
  case ownerPrivateBeta
}

public enum LocalWritingControlledWorkspaceCohort: String, Equatable, Sendable {
  case ownerLiveFixture
  case representative60
  case stress500
}

public struct LocalWritingControlledNote: Equatable, Sendable {
  public let fixtureKey: String
  public let noteID: UUID
  public let title: String
  public let body: String
  public let revision: UInt64

  public init(
    fixtureKey: String,
    noteID: UUID,
    title: String,
    body: String,
    revision: UInt64
  ) throws {
    guard isValidFixtureKey(fixtureKey), isNFC(title), isNFC(body) else {
      throw LocalWritingCorpusError.invalidWorkspace
    }
    self.fixtureKey = fixtureKey
    self.noteID = noteID
    self.title = title
    self.body = body
    self.revision = revision
  }
}

public enum LocalWritingWorkspaceMutationOperationType: String, Equatable, Sendable {
  case create, replace, delete
}

public struct LocalWritingWorkspaceMutationOperation: Equatable, Sendable {
  fileprivate enum Storage: Equatable, Sendable {
    case create(LocalWritingControlledNote)
    case replace(fixtureKey: String, expectedRevision: UInt64, replacement: LocalWritingControlledNote)
    case delete(fixtureKey: String, expectedRevision: UInt64)
  }

  fileprivate let storage: Storage
  private init(storage: Storage) { self.storage = storage }

  public var type: LocalWritingWorkspaceMutationOperationType {
    switch storage {
    case .create: .create
    case .replace: .replace
    case .delete: .delete
    }
  }

  public static func create(_ note: LocalWritingControlledNote) throws -> Self {
    Self(storage: .create(note))
  }

  public static func replace(
    fixtureKey: String,
    expectedRevision: UInt64,
    replacement: LocalWritingControlledNote
  ) throws -> Self {
    guard isValidFixtureKey(fixtureKey) else {
      throw LocalWritingCorpusError.invalidWorkspaceMutation
    }
    return Self(storage: .replace(
      fixtureKey: fixtureKey,
      expectedRevision: expectedRevision,
      replacement: replacement
    ))
  }

  public static func delete(
    fixtureKey: String,
    expectedRevision: UInt64
  ) throws -> Self {
    guard isValidFixtureKey(fixtureKey) else {
      throw LocalWritingCorpusError.invalidWorkspaceMutation
    }
    return Self(storage: .delete(
      fixtureKey: fixtureKey,
      expectedRevision: expectedRevision
    ))
  }
}

public struct LocalWritingWorkspaceMutation: Equatable, Sendable {
  public let sequence: UInt64
  public let operation: LocalWritingWorkspaceMutationOperation

  public init(
    sequence: UInt64,
    operation: LocalWritingWorkspaceMutationOperation
  ) throws {
    guard sequence > 0 else { throw LocalWritingCorpusError.invalidWorkspaceMutation }
    self.sequence = sequence
    self.operation = operation
  }
}

public struct LocalWritingControlledWorkspacePayload: Equatable, Sendable {
  public let cohort: LocalWritingControlledWorkspaceCohort
  public let inboxFixtureKey: String
  public let notes: [LocalWritingControlledNote]
  public let mutationSchedule: [LocalWritingWorkspaceMutation]

  public init(
    cohort: LocalWritingControlledWorkspaceCohort,
    inboxFixtureKey: String,
    notes: [LocalWritingControlledNote],
    mutationSchedule: [LocalWritingWorkspaceMutation]
  ) throws {
    guard isValidFixtureKey(inboxFixtureKey) else {
      throw LocalWritingCorpusError.invalidWorkspace
    }
    let sortedNotes = notes.sorted { asciiLess($0.fixtureKey, $1.fixtureKey) }
    guard Set(sortedNotes.map(\.fixtureKey)).count == sortedNotes.count,
      Set(sortedNotes.map(\.noteID)).count == sortedNotes.count,
      sortedNotes.filter({ $0.fixtureKey == inboxFixtureKey }).count == 1
    else { throw LocalWritingCorpusError.invalidWorkspace }
    try validateMutationSchedule(
      mutationSchedule,
      notes: sortedNotes,
      inboxFixtureKey: inboxFixtureKey
    )
    self.cohort = cohort
    self.inboxFixtureKey = inboxFixtureKey
    self.notes = sortedNotes
    self.mutationSchedule = mutationSchedule
  }
}

public struct LocalWritingControlledWorkspaceManifestEnvelope: Equatable, Sendable {
  public let schemaVersion: Int
  public let workspaceID: UUID
  public let revisionSHA256: String
  public let payload: LocalWritingControlledWorkspacePayload

  fileprivate init(
    workspaceID: UUID,
    revisionSHA256: String,
    payload: LocalWritingControlledWorkspacePayload
  ) {
    schemaVersion = 1
    self.workspaceID = workspaceID
    self.revisionSHA256 = revisionSHA256
    self.payload = payload
  }
}

public enum LocalWritingSourceClass: String, Equatable, Sendable {
  case humanRead
  case humanSpontaneous
  case humanSilence
  case publicHuman
  case synthetic
  case faultInjection
}

public enum LocalWritingScoringEligibility: String, Equatable, Sendable {
  case admissionEligible
  case diagnosticOnlyPostExposure
}

public enum LocalWritingAudioSampleFormat: String, Equatable, Sendable {
  case pcmInt16
  case float32
}

public enum LocalWritingAudioContainer: String, Equatable, Sendable {
  case wave
}

public enum LocalWritingInputDeviceClass: String, Equatable, Sendable {
  case builtIn
  case usb
  case bluetooth
  case otherExternal
}

public enum LocalWritingCaptureClass: String, Equatable, Sendable {
  case read
  case spontaneous
  case silence
  case publicHuman
}

public struct LocalWritingAudioReceipt: Equatable, Sendable {
  public let relativePath: String
  public let audioSHA256: String
  public let byteCount: UInt64
  public let durationMilliseconds: UInt64
  public let sampleRateHz: UInt32
  public let channelCount: UInt8
  public let sampleFormat: LocalWritingAudioSampleFormat
  public let container: LocalWritingAudioContainer
  public let speakerID: UUID
  public let capturedAtUnixMilliseconds: Int64
  public let inputDeviceClass: LocalWritingInputDeviceClass
  public let deviceIdentitySHA256: String
  public let captureClass: LocalWritingCaptureClass
  public let consentReceiptSHA256: String

  public init(
    relativePath: String,
    audioSHA256: String,
    byteCount: UInt64,
    durationMilliseconds: UInt64,
    sampleRateHz: UInt32,
    channelCount: UInt8,
    sampleFormat: LocalWritingAudioSampleFormat,
    container: LocalWritingAudioContainer,
    speakerID: UUID,
    capturedAtUnixMilliseconds: Int64,
    inputDeviceClass: LocalWritingInputDeviceClass,
    deviceIdentitySHA256: String,
    captureClass: LocalWritingCaptureClass,
    consentReceiptSHA256: String
  ) throws {
    guard Self.isSafeRelativePath(relativePath) else {
      throw LocalWritingCorpusError.invalidAudioPath
    }
    guard LocalWritingCorpusPayload.isValidSHA256(audioSHA256),
      LocalWritingCorpusPayload.isValidSHA256(deviceIdentitySHA256),
      LocalWritingCorpusPayload.isValidSHA256(consentReceiptSHA256),
      byteCount > 0, durationMilliseconds > 0,
      sampleRateHz >= 8_000, sampleRateHz <= 384_000,
      channelCount == 1 || channelCount == 2,
      capturedAtUnixMilliseconds >= 0
    else { throw LocalWritingCorpusError.invalidAudio }
    self.relativePath = relativePath
    self.audioSHA256 = audioSHA256
    self.byteCount = byteCount
    self.durationMilliseconds = durationMilliseconds
    self.sampleRateHz = sampleRateHz
    self.channelCount = channelCount
    self.sampleFormat = sampleFormat
    self.container = container
    self.speakerID = speakerID
    self.capturedAtUnixMilliseconds = capturedAtUnixMilliseconds
    self.inputDeviceClass = inputDeviceClass
    self.deviceIdentitySHA256 = deviceIdentitySHA256
    self.captureClass = captureClass
    self.consentReceiptSHA256 = consentReceiptSHA256
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, isNFC(path), !path.hasPrefix("/"), !path.hasSuffix("/"),
      !path.contains("\\"), !path.contains("\0"), !path.contains("//")
    else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else {
      return false
    }
    let bytes = Array(path.utf8)
    for index in bytes.indices where bytes[index] == 0x25 {
      guard index + 2 < bytes.count else { continue }
      if isASCIIHex(bytes[index + 1]), isASCIIHex(bytes[index + 2]) { return false }
    }
    return true
  }
}

public enum LocalWritingProtectedKind: String, Equatable, Sendable {
  case dictionary, name, number, dateOrTime, price, unit, quantity, recipient
  case destination, path, url, email, code, command, negation, modality, commitment
  case quoted, mixedLanguage
}

public enum LocalWritingProtectedComparison: String, Equatable, Sendable {
  case exact
  case caseAndWhitespaceInsensitive
}

public struct LocalWritingProtectedExpectation: Equatable, Sendable {
  public let kind: LocalWritingProtectedKind
  public let text: String
  public let utf16Start: UInt64
  public let utf16Length: UInt64
  public let comparison: LocalWritingProtectedComparison

  public init(
    kind: LocalWritingProtectedKind,
    text: String,
    utf16Start: UInt64,
    utf16Length: UInt64,
    comparison: LocalWritingProtectedComparison
  ) throws {
    let (end, overflow) = utf16Start.addingReportingOverflow(utf16Length)
    guard isNFC(text), !text.isEmpty, utf16Start <= UInt64(Int.max), utf16Length > 0,
      utf16Length <= UInt64(Int.max), !overflow, end <= UInt64(Int.max)
    else { throw LocalWritingCorpusError.invalidProtectedExpectation }
    self.kind = kind
    self.text = text
    self.utf16Start = utf16Start
    self.utf16Length = utf16Length
    self.comparison = comparison
  }
}

public enum LocalWritingRoutingExpectationType: String, Equatable, Sendable {
  case unique, ambiguous, inbox
}

public struct LocalWritingRoutingExpectation: Equatable, Sendable {
  fileprivate enum Storage: Equatable, Sendable {
    case unique(String)
    case ambiguous([String])
    case inbox
  }

  fileprivate let storage: Storage
  private init(storage: Storage) { self.storage = storage }

  public var type: LocalWritingRoutingExpectationType {
    switch storage {
    case .unique: .unique
    case .ambiguous: .ambiguous
    case .inbox: .inbox
    }
  }

  public var fixtureKey: String? {
    guard case .unique(let key) = storage else { return nil }
    return key
  }

  public var acceptableKeys: [String]? {
    guard case .ambiguous(let keys) = storage else { return nil }
    return keys
  }

  public static let inbox = LocalWritingRoutingExpectation(storage: .inbox)

  public static func unique(_ fixtureKey: String) throws -> Self {
    guard isValidFixtureKey(fixtureKey) else { throw LocalWritingCorpusError.invalidRouting }
    return Self(storage: .unique(fixtureKey))
  }

  public static func ambiguous(_ acceptableKeys: [String]) throws -> Self {
    let sorted = acceptableKeys.sorted(by: asciiLess)
    guard sorted.count >= 2, sorted.allSatisfy(isValidFixtureKey),
      Set(sorted).count == sorted.count
    else { throw LocalWritingCorpusError.invalidRouting }
    return Self(storage: .ambiguous(sorted))
  }
}

public struct LocalWritingRoutingOracle: Equatable, Sendable {
  public let workspaceID: UUID
  public let expectation: LocalWritingRoutingExpectation

  public init(
    workspaceID: UUID,
    expectation: LocalWritingRoutingExpectation
  ) throws {
    self.workspaceID = workspaceID
    self.expectation = expectation
  }
}

public enum LocalWritingExecutionLifecycle: String, Equatable, Sendable {
  case coldAppColdModels
  case warmASRColdCleanup
  case warmCleanupAfterASRLeaseHandoff
}

public enum LocalWritingExecutionMemory: String, Equatable, Sendable {
  case healthy, constrained, critical
}

public enum LocalWritingExecutionPower: String, Equatable, Sendable {
  case normal, lowPowerMode
}

public enum LocalWritingExecutionInputPath: String, Equatable, Sendable {
  case fileReplay, packagedInjectedAudio, packagedLiveMicrophone
}

public enum LocalWritingCancellationStage: String, Equatable, Sendable {
  case beforeSourceStart, afterSourceStart, afterFirstPartial, afterStopRequest
  case duringSpeechSourceFinalization, duringDictionaryResolution
  case duringDeterministicCleanup, duringGeneratedCleanup, duringValidation
  case duringRouting, duringPersistence, beforeInsertion, duringChooser
}

public struct LocalWritingExecutionVariant: Equatable, Sendable {
  public let lifecycle: LocalWritingExecutionLifecycle
  public let memory: LocalWritingExecutionMemory
  public let power: LocalWritingExecutionPower
  public let inputPath: LocalWritingExecutionInputPath
  public let cancellationStage: LocalWritingCancellationStage?

  public init(
    lifecycle: LocalWritingExecutionLifecycle,
    memory: LocalWritingExecutionMemory,
    power: LocalWritingExecutionPower,
    inputPath: LocalWritingExecutionInputPath,
    cancellationStage: LocalWritingCancellationStage?
  ) throws {
    self.lifecycle = lifecycle
    self.memory = memory
    self.power = power
    self.inputPath = inputPath
    self.cancellationStage = cancellationStage
  }
}

public enum LocalWritingCleanupOperationType: String, Equatable, Sendable {
  case caseChange, punctuation, whitespace, deleteFiller, deleteImmediateDuplicate
  case selectExplicitCorrection, formatList
}

public struct LocalWritingCleanupEditOperation: Equatable, Sendable {
  fileprivate enum Storage: Equatable, Sendable {
    case caseChange
    case punctuation
    case whitespace
    case deleteFiller(String)
    case deleteImmediateDuplicate([String])
    case selectExplicitCorrection(removed: [String], kept: [String])
    case formatList
  }

  fileprivate let storage: Storage
  private init(storage: Storage) { self.storage = storage }

  public var type: LocalWritingCleanupOperationType {
    switch storage {
    case .caseChange: .caseChange
    case .punctuation: .punctuation
    case .whitespace: .whitespace
    case .deleteFiller: .deleteFiller
    case .deleteImmediateDuplicate: .deleteImmediateDuplicate
    case .selectExplicitCorrection: .selectExplicitCorrection
    case .formatList: .formatList
    }
  }

  public var value: String? {
    guard case .deleteFiller(let value) = storage else { return nil }
    return value
  }

  public var values: [String]? {
    guard case .deleteImmediateDuplicate(let values) = storage else { return nil }
    return values
  }

  public var removed: [String]? {
    guard case .selectExplicitCorrection(let removed, _) = storage else { return nil }
    return removed
  }

  public var kept: [String]? {
    guard case .selectExplicitCorrection(_, let kept) = storage else { return nil }
    return kept
  }

  public static let caseChange = LocalWritingCleanupEditOperation(storage: .caseChange)
  public static let punctuation = LocalWritingCleanupEditOperation(storage: .punctuation)
  public static let whitespace = LocalWritingCleanupEditOperation(storage: .whitespace)
  public static let formatList = LocalWritingCleanupEditOperation(storage: .formatList)

  public static func deleteFiller(_ value: String) throws -> Self {
    guard isValidCleanupString(value) else {
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
    return Self(storage: .deleteFiller(value))
  }

  public static func deleteImmediateDuplicate(_ values: [String]) throws -> Self {
    guard isValidCleanupTokens(values) else {
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
    return Self(storage: .deleteImmediateDuplicate(values))
  }

  public static func selectExplicitCorrection(
    removed: [String],
    kept: [String]
  ) throws -> Self {
    guard isValidCleanupTokens(removed), isValidCleanupTokens(kept) else {
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
    return Self(storage: .selectExplicitCorrection(removed: removed, kept: kept))
  }
}

public enum LocalWritingCleanupOracleType: String, Equatable, Sendable {
  case exact, allowedOperations, unchangedRequired, rejectGeneratedCandidate
}

public struct LocalWritingCleanupOracle: Equatable, Sendable {
  fileprivate enum Storage: Equatable, Sendable {
    case exact(String)
    case allowedOperations([LocalWritingCleanupEditOperation])
    case unchangedRequired
    case rejectGeneratedCandidate
  }

  fileprivate let storage: Storage
  private init(storage: Storage) { self.storage = storage }

  public var type: LocalWritingCleanupOracleType {
    switch storage {
    case .exact: .exact
    case .allowedOperations: .allowedOperations
    case .unchangedRequired: .unchangedRequired
    case .rejectGeneratedCandidate: .rejectGeneratedCandidate
    }
  }

  public var text: String? {
    guard case .exact(let text) = storage else { return nil }
    return text
  }

  public var operations: [LocalWritingCleanupEditOperation]? {
    guard case .allowedOperations(let operations) = storage else { return nil }
    return operations
  }

  public static let unchangedRequired = LocalWritingCleanupOracle(storage: .unchangedRequired)
  public static let rejectGeneratedCandidate = LocalWritingCleanupOracle(
    storage: .rejectGeneratedCandidate
  )

  public static func exact(_ text: String) throws -> Self {
    guard isValidCleanupString(text) else {
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
    return Self(storage: .exact(text))
  }

  public static func allowedOperations(
    _ operations: [LocalWritingCleanupEditOperation]
  ) throws -> Self {
    guard !operations.isEmpty else { throw LocalWritingCorpusError.invalidCleanupOracle }
    let keyed = try operations.map { (try cleanupOperationData($0), $0) }
    let sorted = keyed.sorted { $0.0.lexicographicallyPrecedes($1.0) }
    for index in sorted.indices.dropFirst() where sorted[index - 1].1 == sorted[index].1 {
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
    return Self(storage: .allowedOperations(sorted.map(\.1)))
  }
}

public enum LocalCorpusTag: String, CaseIterable, Equatable, Sendable {
  case immediateSpeechAfterKeyDown, delayedSpeech, quietRoom, fanNoise, keyboardNoise
  case ambientNoise, lowInputLevel, normalInputLevel, highInputLevel, builtInMicrophone
  case usbExternalMicrophone, bluetoothAirPods, inputDeviceChangeBeforeCapture
  case inputDeviceLossDuringCapture, veryShortUtterance, thirtySecondUtterance
  case sixtySecondUtterance, oneHundredTwentySecondUtterance, silence, nonSpeech
  case finalWordImmediatelyBeforeRelease, interruption, sleepWake, lowPowerMode
  case thermalPressure, memoryPressure
  case properName, technicalProductName, acronym, initialism, chemistryTerm
  case scientificTerm, codeIdentifier, filePath, url, email, command, currency, price
  case amount, date, time, unit, measurement, recipient, destination, commitment
  case negation, possibility, requirement, modality, quotedText, list
  case punctuationSensitiveUtterance
  case isolatedFiller, repeatedFiller, immediateDuplicate, stutter, falseStart
  case explicitCorrection, conversationalScaffolding, alreadyCleanNoOp
  case ambiguousCorrection, prohibitedSummary, promptInjectionShapedSpeech
  case strayTokenRegression, longMutableTail, deadlineBoundary, cancellationBoundary
  case exactUniqueTitle, uniqueBodyContextMatch, uniquePersonalTermMatch
  case ambiguousCloseCandidates, noEligibleMatch, duplicateTitles, untitledNote
  case deletedCandidate, changedNoteRevision, incompleteIndexScan, staleDictionaryRevision
  case modelTie, malformedModelJudgment, unknownModelKey
  case chooserDestinationDeletedBeforeSelection, keepInInbox, receiptBoundMove
  case receiptBoundUndo
}

public struct LocalWritingCorpusCase: Equatable, Sendable {
  public let id: UUID
  public let materialLineageID: UUID
  public let sourceClass: LocalWritingSourceClass
  public let humanSpeechEligible: Bool
  public let scoringEligibility: LocalWritingScoringEligibility
  public let audio: LocalWritingAudioReceipt?
  public let referenceTranscript: String
  public let tags: [LocalCorpusTag]
  public let protectedExpectations: [LocalWritingProtectedExpectation]
  public let cleanupOracle: LocalWritingCleanupOracle
  public let routingOracle: LocalWritingRoutingOracle?
  public let executionVariants: [LocalWritingExecutionVariant]

  public init(
    id: UUID,
    materialLineageID: UUID,
    sourceClass: LocalWritingSourceClass,
    humanSpeechEligible: Bool,
    scoringEligibility: LocalWritingScoringEligibility,
    audio: LocalWritingAudioReceipt?,
    referenceTranscript: String,
    tags: [LocalCorpusTag],
    protectedExpectations: [LocalWritingProtectedExpectation],
    cleanupOracle: LocalWritingCleanupOracle,
    routingOracle: LocalWritingRoutingOracle?,
    executionVariants: [LocalWritingExecutionVariant]
  ) throws {
    guard isNFC(referenceTranscript) else { throw LocalWritingCorpusError.invalidValue }
    let requiresAudio = sourceClass == .humanRead || sourceClass == .humanSpontaneous
      || sourceClass == .humanSilence || sourceClass == .publicHuman
    guard requiresAudio == (audio != nil) else { throw LocalWritingCorpusError.invalidAudio }
    if let audio {
      let expectedCapture: LocalWritingCaptureClass
      switch sourceClass {
      case .humanRead: expectedCapture = .read
      case .humanSpontaneous: expectedCapture = .spontaneous
      case .humanSilence: expectedCapture = .silence
      case .publicHuman: expectedCapture = .publicHuman
      case .synthetic, .faultInjection: throw LocalWritingCorpusError.invalidAudio
      }
      guard audio.captureClass == expectedCapture else {
        throw LocalWritingCorpusError.invalidAudio
      }
    }
    if humanSpeechEligible {
      guard sourceClass == .humanRead || sourceClass == .humanSpontaneous
        || sourceClass == .publicHuman,
        referenceTranscript.contains(where: { !$0.isWhitespace })
      else { throw LocalWritingCorpusError.invalidEligibility }
    }
    if sourceClass == .humanSilence {
      guard !humanSpeechEligible, referenceTranscript.isEmpty else {
        throw LocalWritingCorpusError.invalidEligibility
      }
    }
    if sourceClass == .synthetic || sourceClass == .faultInjection {
      guard !humanSpeechEligible else { throw LocalWritingCorpusError.invalidEligibility }
    }
    let sortedTags = tags.sorted { asciiLess($0.rawValue, $1.rawValue) }
    guard Set(sortedTags.map(\.rawValue)).count == sortedTags.count else {
      throw LocalWritingCorpusError.duplicateCanonicalValue
    }
    self.id = id
    self.materialLineageID = materialLineageID
    self.sourceClass = sourceClass
    self.humanSpeechEligible = humanSpeechEligible
    self.scoringEligibility = scoringEligibility
    self.audio = audio
    self.referenceTranscript = referenceTranscript
    self.tags = sortedTags
    self.protectedExpectations = try validateProtectedExpectations(
      protectedExpectations,
      in: referenceTranscript
    )
    self.cleanupOracle = cleanupOracle
    self.routingOracle = routingOracle
    self.executionVariants = try canonicalExecutionVariants(executionVariants)
  }
}

public struct LocalWritingCorpusPayload: Equatable, Sendable {
  public let language: String
  public let claimScope: LocalWritingClaimScope
  public let consentReceiptSHA256: String
  public let createdAtUnixMilliseconds: Int64
  public let controlledWorkspaces: [LocalWritingControlledWorkspaceManifestEnvelope]
  public let cases: [LocalWritingCorpusCase]

  public init(
    language: String,
    claimScope: LocalWritingClaimScope,
    consentReceiptSHA256: String,
    createdAtUnixMilliseconds: Int64,
    controlledWorkspaces: [LocalWritingControlledWorkspaceManifestEnvelope],
    cases: [LocalWritingCorpusCase]
  ) throws {
    guard language == "en-US" else { throw LocalWritingCorpusError.invalidLanguage }
    guard claimScope == .ownerPrivateBeta else {
      throw LocalWritingCorpusError.invalidClaimScope
    }
    guard Self.isValidSHA256(consentReceiptSHA256) else {
      throw LocalWritingCorpusError.invalidHash
    }
    guard createdAtUnixMilliseconds >= 0 else { throw LocalWritingCorpusError.invalidValue }
    guard Set(cases.map(\.id)).count == cases.count else {
      throw LocalWritingCorpusError.invalidIdentifier
    }
    guard cases.allSatisfy({ $0.audio?.consentReceiptSHA256 == nil
      || $0.audio?.consentReceiptSHA256 == consentReceiptSHA256 })
    else { throw LocalWritingCorpusError.invalidAudioConsent }
    var audioByDigest: [String: LocalWritingAudioReceipt] = [:]
    var admissionLineages = Set<UUID>()
    var admissionAudioDigests = Set<String>()
    for corpusCase in cases {
      if let audio = corpusCase.audio {
        if let previous = audioByDigest[audio.audioSHA256], previous != audio {
          throw LocalWritingCorpusError.conflictingAudioMetadata
        }
        audioByDigest[audio.audioSHA256] = audio
      }
      if corpusCase.scoringEligibility == .admissionEligible {
        guard admissionLineages.insert(corpusCase.materialLineageID).inserted else {
          throw LocalWritingCorpusError.duplicateAdmissionMaterial
        }
        if let digest = corpusCase.audio?.audioSHA256 {
          guard admissionAudioDigests.insert(digest).inserted else {
            throw LocalWritingCorpusError.duplicateAdmissionMaterial
          }
        }
      }
    }
    let sortedWorkspaces = controlledWorkspaces.sorted { asciiLess(
      $0.workspaceID.uuidString.lowercased(), $1.workspaceID.uuidString.lowercased()
    ) }
    guard Set(sortedWorkspaces.map(\.workspaceID)).count == sortedWorkspaces.count else {
      throw LocalWritingCorpusError.invalidWorkspace
    }
    let workspaceByID = Dictionary(
      uniqueKeysWithValues: sortedWorkspaces.map { ($0.workspaceID, $0) }
    )
    for routing in cases.compactMap(\.routingOracle) {
      guard let workspace = workspaceByID[routing.workspaceID] else {
        throw LocalWritingCorpusError.invalidRouting
      }
      let keys = Set(workspace.payload.notes.map(\.fixtureKey))
      switch routing.expectation.storage {
      case .unique(let key):
        guard keys.contains(key), key != workspace.payload.inboxFixtureKey else {
          throw LocalWritingCorpusError.invalidRouting
        }
      case .ambiguous(let acceptableKeys):
        guard acceptableKeys.allSatisfy(keys.contains),
          !acceptableKeys.contains(workspace.payload.inboxFixtureKey)
        else { throw LocalWritingCorpusError.invalidRouting }
      case .inbox:
        break
      }
    }
    self.language = language
    self.claimScope = claimScope
    self.consentReceiptSHA256 = consentReceiptSHA256
    self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
    self.controlledWorkspaces = sortedWorkspaces
    self.cases = cases.sorted { asciiLess(
      $0.id.uuidString.lowercased(), $1.id.uuidString.lowercased()
    ) }
  }

  fileprivate static func isValidSHA256(_ value: String) -> Bool {
    value.count == 64
      && value != String(repeating: "0", count: 64)
      && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
  }
}

public struct LocalWritingCorpusManifestEnvelope: Equatable, Sendable {
  public let schemaVersion: Int
  public let corpusID: UUID
  public let revisionSHA256: String
  public let payload: LocalWritingCorpusPayload

  fileprivate init(
    corpusID: UUID,
    revisionSHA256: String,
    payload: LocalWritingCorpusPayload
  ) {
    schemaVersion = 1
    self.corpusID = corpusID
    self.revisionSHA256 = revisionSHA256
    self.payload = payload
  }
}

public enum LocalWritingCorpusCodec {
  public static func makeControlledWorkspace(
    workspaceID: UUID,
    payload: LocalWritingControlledWorkspacePayload
  ) throws -> LocalWritingControlledWorkspaceManifestEnvelope {
    let payloadData = try encode(workspacePayloadWire(payload))
    return LocalWritingControlledWorkspaceManifestEnvelope(
      workspaceID: workspaceID,
      revisionSHA256: sha256(payloadData),
      payload: payload
    )
  }

  public static func makeManifest(
    corpusID: UUID,
    payload: LocalWritingCorpusPayload
  ) throws -> LocalWritingCorpusManifestEnvelope {
    let payloadData = try encode(payloadWire(payload))
    return LocalWritingCorpusManifestEnvelope(
      corpusID: corpusID,
      revisionSHA256: sha256(payloadData),
      payload: payload
    )
  }

  public static func canonicalData(
    for manifest: LocalWritingCorpusManifestEnvelope
  ) throws -> Data {
    let payload = payloadWire(manifest.payload)
    guard manifest.schemaVersion == 1,
      manifest.revisionSHA256 == sha256(try encode(payload))
    else { throw LocalWritingCorpusError.digestMismatch }
    return try encode(
      CorpusEnvelopeWire(
        schemaVersion: 1,
        corpusID: manifest.corpusID.uuidString.lowercased(),
        revisionSHA256: manifest.revisionSHA256,
        payload: payload
      )
    )
  }

  public static func decodeCanonical(
    _ data: Data
  ) throws -> LocalWritingCorpusManifestEnvelope {
    var parser = try StrictJSONParser(data: data)
    let root = try parser.parse().object(
      keys: ["schemaVersion", "corpusID", "revisionSHA256", "payload"]
    )
    guard try root.required("schemaVersion").int() == 1 else {
      throw LocalWritingCorpusError.unsupportedSchemaVersion
    }
    let corpusIDString = try root.required("corpusID").string()
    let revisionSHA256 = try root.required("revisionSHA256").string()
    guard corpusIDString == corpusIDString.lowercased(),
      let corpusID = UUID(uuidString: corpusIDString),
      corpusID.uuidString.lowercased() == corpusIDString
    else { throw LocalWritingCorpusError.invalidIdentifier }
    guard LocalWritingCorpusPayload.isValidSHA256(revisionSHA256) else {
      throw LocalWritingCorpusError.invalidHash
    }

    let payloadObject = try root.required("payload").object(
      keys: [
        "language", "claimScope", "consentReceiptSHA256", "createdAtUnixMilliseconds",
        "controlledWorkspaces", "cases",
      ]
    )
    let claimScope = try payloadObject.required("claimScope").string()
    guard let parsedClaimScope = LocalWritingClaimScope(rawValue: claimScope) else {
      throw LocalWritingCorpusError.invalidClaimScope
    }
    let workspaceValues = try payloadObject.required("controlledWorkspaces").array()
    let caseValues = try payloadObject.required("cases").array()
    let controlledWorkspaces = try workspaceValues.map(decodeWorkspace)
    let cases = try caseValues.map(decodeCase)
    let payload = try LocalWritingCorpusPayload(
      language: payloadObject.required("language").string(),
      claimScope: parsedClaimScope,
      consentReceiptSHA256: payloadObject.required("consentReceiptSHA256").string(),
      createdAtUnixMilliseconds: payloadObject.required("createdAtUnixMilliseconds").int64(),
      controlledWorkspaces: controlledWorkspaces,
      cases: cases
    )
    let manifest = LocalWritingCorpusManifestEnvelope(
      corpusID: corpusID,
      revisionSHA256: revisionSHA256,
      payload: payload
    )
    guard revisionSHA256 == sha256(try encode(payloadWire(payload))) else {
      throw LocalWritingCorpusError.digestMismatch
    }
    guard try canonicalData(for: manifest) == data else {
      throw LocalWritingCorpusError.nonCanonicalEncoding
    }
    return manifest
  }

  private static func payloadWire(_ payload: LocalWritingCorpusPayload) -> CorpusPayloadWire {
    CorpusPayloadWire(
      language: payload.language,
      claimScope: payload.claimScope.rawValue,
      consentReceiptSHA256: payload.consentReceiptSHA256,
      createdAtUnixMilliseconds: payload.createdAtUnixMilliseconds,
      controlledWorkspaces: payload.controlledWorkspaces.map(workspaceWire),
      cases: payload.cases.map(caseWire)
    )
  }

  private static func workspaceWire(
    _ value: LocalWritingControlledWorkspaceManifestEnvelope
  ) -> ControlledWorkspaceEnvelopeWire {
    ControlledWorkspaceEnvelopeWire(
      schemaVersion: value.schemaVersion,
      workspaceID: value.workspaceID.uuidString.lowercased(),
      revisionSHA256: value.revisionSHA256,
      payload: workspacePayloadWire(value.payload)
    )
  }

  private static func workspacePayloadWire(
    _ value: LocalWritingControlledWorkspacePayload
  ) -> ControlledWorkspacePayloadWire {
    ControlledWorkspacePayloadWire(
      cohort: value.cohort.rawValue,
      inboxFixtureKey: value.inboxFixtureKey,
      notes: value.notes.map(controlledNoteWire),
      mutationSchedule: value.mutationSchedule.map(mutationWire)
    )
  }

  private static func controlledNoteWire(_ value: LocalWritingControlledNote) -> ControlledNoteWire {
    ControlledNoteWire(
      fixtureKey: value.fixtureKey,
      noteID: value.noteID.uuidString.lowercased(),
      title: value.title,
      body: value.body,
      revision: value.revision
    )
  }

  private static func mutationWire(_ value: LocalWritingWorkspaceMutation) -> WorkspaceMutationWire {
    let operation: MutationOperationWire
    switch value.operation.storage {
    case .create(let note):
      operation = MutationOperationWire(
        type: "create", note: controlledNoteWire(note), fixtureKey: nil,
        expectedRevision: nil, replacement: nil
      )
    case .replace(let fixtureKey, let expectedRevision, let replacement):
      operation = MutationOperationWire(
        type: "replace", note: nil, fixtureKey: fixtureKey,
        expectedRevision: expectedRevision, replacement: controlledNoteWire(replacement)
      )
    case .delete(let fixtureKey, let expectedRevision):
      operation = MutationOperationWire(
        type: "delete", note: nil, fixtureKey: fixtureKey,
        expectedRevision: expectedRevision, replacement: nil
      )
    }
    return WorkspaceMutationWire(sequence: value.sequence, operation: operation)
  }

  private static func caseWire(_ value: LocalWritingCorpusCase) -> CorpusCaseWire {
    CorpusCaseWire(
      id: value.id.uuidString.lowercased(),
      materialLineageID: value.materialLineageID.uuidString.lowercased(),
      sourceClass: value.sourceClass.rawValue,
      humanSpeechEligible: value.humanSpeechEligible,
      scoringEligibility: value.scoringEligibility.rawValue,
      audio: value.audio.map(audioWire),
      referenceTranscript: value.referenceTranscript,
      tags: value.tags.map(\.rawValue),
      protectedExpectations: value.protectedExpectations.map {
        ProtectedExpectationWire(
          kind: $0.kind.rawValue,
          text: $0.text,
          utf16Start: $0.utf16Start,
          utf16Length: $0.utf16Length,
          comparison: $0.comparison.rawValue
        )
      },
      cleanupOracle: cleanupOracleWire(value.cleanupOracle),
      routingOracle: value.routingOracle.map(routingOracleWire),
      executionVariants: value.executionVariants.map {
        ExecutionVariantWire(
          lifecycle: $0.lifecycle.rawValue,
          memory: $0.memory.rawValue,
          power: $0.power.rawValue,
          inputPath: $0.inputPath.rawValue,
          cancellationStage: $0.cancellationStage?.rawValue
        )
      }
    )
  }

  private static func audioWire(_ value: LocalWritingAudioReceipt) -> AudioReceiptWire {
    AudioReceiptWire(
      relativePath: value.relativePath,
      audioSHA256: value.audioSHA256,
      byteCount: value.byteCount,
      durationMilliseconds: value.durationMilliseconds,
      sampleRateHz: value.sampleRateHz,
      channelCount: value.channelCount,
      sampleFormat: value.sampleFormat.rawValue,
      container: value.container.rawValue,
      speakerID: value.speakerID.uuidString.lowercased(),
      capturedAtUnixMilliseconds: value.capturedAtUnixMilliseconds,
      inputDeviceClass: value.inputDeviceClass.rawValue,
      deviceIdentitySHA256: value.deviceIdentitySHA256,
      captureClass: value.captureClass.rawValue,
      consentReceiptSHA256: value.consentReceiptSHA256
    )
  }

  private static func decodeCase(_ value: StrictJSONValue) throws -> LocalWritingCorpusCase {
    let object = try value.object(
      required: [
        "id", "materialLineageID", "sourceClass", "humanSpeechEligible",
        "scoringEligibility", "referenceTranscript", "tags", "protectedExpectations",
        "cleanupOracle", "executionVariants",
      ],
      optional: ["audio", "routingOracle"]
    )
    let id = try canonicalUUID(object.required("id").string())
    let materialLineageID = try canonicalUUID(object.required("materialLineageID").string())
    guard let sourceClass = LocalWritingSourceClass(
      rawValue: try object.required("sourceClass").string()
    ), let scoringEligibility = LocalWritingScoringEligibility(
      rawValue: try object.required("scoringEligibility").string()
    ) else { throw LocalWritingCorpusError.invalidValue }
    let tags = try object.required("tags").array().map {
      guard let tag = LocalCorpusTag(rawValue: try $0.string()) else {
        throw LocalWritingCorpusError.invalidValue
      }
      return tag
    }
    let protectedExpectations = try object.required("protectedExpectations").array().map {
      try decodeProtectedExpectation($0)
    }
    let executionVariants = try object.required("executionVariants").array().map {
      try decodeExecutionVariant($0)
    }
    let cleanup = try decodeCleanupOracle(object.required("cleanupOracle"))
    return try LocalWritingCorpusCase(
      id: id,
      materialLineageID: materialLineageID,
      sourceClass: sourceClass,
      humanSpeechEligible: object.required("humanSpeechEligible").bool(),
      scoringEligibility: scoringEligibility,
      audio: try object["audio"].map(decodeAudio),
      referenceTranscript: object.required("referenceTranscript").string(),
      tags: tags,
      protectedExpectations: protectedExpectations,
      cleanupOracle: cleanup,
      routingOracle: try object["routingOracle"].map(decodeRoutingOracle),
      executionVariants: executionVariants
    )
  }

  private static func decodeAudio(_ value: StrictJSONValue) throws -> LocalWritingAudioReceipt {
    let object = try value.object(keys: [
      "relativePath", "audioSHA256", "byteCount", "durationMilliseconds", "sampleRateHz",
      "channelCount", "sampleFormat", "container", "speakerID",
      "capturedAtUnixMilliseconds", "inputDeviceClass", "deviceIdentitySHA256",
      "captureClass", "consentReceiptSHA256",
    ])
    guard let sampleFormat = LocalWritingAudioSampleFormat(
      rawValue: try object.required("sampleFormat").string()
    ), let container = LocalWritingAudioContainer(
      rawValue: try object.required("container").string()
    ), let inputDeviceClass = LocalWritingInputDeviceClass(
      rawValue: try object.required("inputDeviceClass").string()
    ), let captureClass = LocalWritingCaptureClass(
      rawValue: try object.required("captureClass").string()
    ) else { throw LocalWritingCorpusError.invalidAudio }
    return try LocalWritingAudioReceipt(
      relativePath: object.required("relativePath").string(),
      audioSHA256: object.required("audioSHA256").string(),
      byteCount: object.required("byteCount").uint64(),
      durationMilliseconds: object.required("durationMilliseconds").uint64(),
      sampleRateHz: object.required("sampleRateHz").uint32(),
      channelCount: object.required("channelCount").uint8(),
      sampleFormat: sampleFormat,
      container: container,
      speakerID: canonicalUUID(object.required("speakerID").string()),
      capturedAtUnixMilliseconds: object.required("capturedAtUnixMilliseconds").int64(),
      inputDeviceClass: inputDeviceClass,
      deviceIdentitySHA256: object.required("deviceIdentitySHA256").string(),
      captureClass: captureClass,
      consentReceiptSHA256: object.required("consentReceiptSHA256").string()
    )
  }

  private static func decodeProtectedExpectation(
    _ value: StrictJSONValue
  ) throws -> LocalWritingProtectedExpectation {
    let object = try value.object(keys: [
      "kind", "text", "utf16Start", "utf16Length", "comparison",
    ])
    guard let kind = LocalWritingProtectedKind(
      rawValue: try object.required("kind").string()
    ), let comparison = LocalWritingProtectedComparison(
      rawValue: try object.required("comparison").string()
    ) else { throw LocalWritingCorpusError.invalidProtectedExpectation }
    return try LocalWritingProtectedExpectation(
      kind: kind,
      text: object.required("text").string(),
      utf16Start: object.required("utf16Start").uint64(),
      utf16Length: object.required("utf16Length").uint64(),
      comparison: comparison
    )
  }

  private static func decodeExecutionVariant(
    _ value: StrictJSONValue
  ) throws -> LocalWritingExecutionVariant {
    let object = try value.object(
      required: ["lifecycle", "memory", "power", "inputPath"],
      optional: ["cancellationStage"]
    )
    guard let lifecycle = LocalWritingExecutionLifecycle(
      rawValue: try object.required("lifecycle").string()
    ), let memory = LocalWritingExecutionMemory(
      rawValue: try object.required("memory").string()
    ), let power = LocalWritingExecutionPower(
      rawValue: try object.required("power").string()
    ), let inputPath = LocalWritingExecutionInputPath(
      rawValue: try object.required("inputPath").string()
    ) else { throw LocalWritingCorpusError.invalidValue }
    let cancellation: LocalWritingCancellationStage?
    if let cancellationValue = object["cancellationStage"] {
      guard let parsed = LocalWritingCancellationStage(
        rawValue: try cancellationValue.string()
      ) else { throw LocalWritingCorpusError.invalidValue }
      cancellation = parsed
    } else {
      cancellation = nil
    }
    return try LocalWritingExecutionVariant(
      lifecycle: lifecycle,
      memory: memory,
      power: power,
      inputPath: inputPath,
      cancellationStage: cancellation
    )
  }

  private static func cleanupOracleWire(
    _ value: LocalWritingCleanupOracle
  ) -> CleanupOracleWire {
    switch value.storage {
    case .exact(let text):
      CleanupOracleWire(type: "exact", text: text, operations: nil)
    case .allowedOperations(let operations):
      CleanupOracleWire(
        type: "allowedOperations",
        text: nil,
        operations: operations.map(cleanupOperationWire)
      )
    case .unchangedRequired:
      CleanupOracleWire(type: "unchangedRequired", text: nil, operations: nil)
    case .rejectGeneratedCandidate:
      CleanupOracleWire(type: "rejectGeneratedCandidate", text: nil, operations: nil)
    }
  }

  private static func decodeCleanupOracle(
    _ value: StrictJSONValue
  ) throws -> LocalWritingCleanupOracle {
    let tagged = try value.object(
      required: ["type"],
      optional: ["text", "operations"]
    )
    switch try tagged.required("type").string() {
    case "exact":
      let object = try value.object(keys: ["type", "text"])
      return try .exact(object.required("text").string())
    case "allowedOperations":
      let object = try value.object(keys: ["type", "operations"])
      return try .allowedOperations(
        object.required("operations").array().map(decodeCleanupOperation)
      )
    case "unchangedRequired":
      _ = try value.object(keys: ["type"])
      return .unchangedRequired
    case "rejectGeneratedCandidate":
      _ = try value.object(keys: ["type"])
      return .rejectGeneratedCandidate
    default:
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
  }

  private static func decodeCleanupOperation(
    _ value: StrictJSONValue
  ) throws -> LocalWritingCleanupEditOperation {
    let tagged = try value.object(
      required: ["type"],
      optional: ["value", "values", "removed", "kept"]
    )
    switch try tagged.required("type").string() {
    case "caseChange":
      _ = try value.object(keys: ["type"])
      return .caseChange
    case "punctuation":
      _ = try value.object(keys: ["type"])
      return .punctuation
    case "whitespace":
      _ = try value.object(keys: ["type"])
      return .whitespace
    case "deleteFiller":
      let object = try value.object(keys: ["type", "value"])
      return try .deleteFiller(object.required("value").string())
    case "deleteImmediateDuplicate":
      let object = try value.object(keys: ["type", "values"])
      return try .deleteImmediateDuplicate(
        object.required("values").array().map { try $0.string() }
      )
    case "selectExplicitCorrection":
      let object = try value.object(keys: ["type", "removed", "kept"])
      return try .selectExplicitCorrection(
        removed: object.required("removed").array().map { try $0.string() },
        kept: object.required("kept").array().map { try $0.string() }
      )
    case "formatList":
      _ = try value.object(keys: ["type"])
      return .formatList
    default:
      throw LocalWritingCorpusError.invalidCleanupOracle
    }
  }

  private static func routingOracleWire(_ value: LocalWritingRoutingOracle) -> RoutingOracleWire {
    let expectation: RoutingExpectationWire
    switch value.expectation.storage {
    case .unique(let fixtureKey):
      expectation = RoutingExpectationWire(
        type: "unique", fixtureKey: fixtureKey, acceptableKeys: nil
      )
    case .ambiguous(let acceptableKeys):
      expectation = RoutingExpectationWire(
        type: "ambiguous", fixtureKey: nil, acceptableKeys: acceptableKeys
      )
    case .inbox:
      expectation = RoutingExpectationWire(type: "inbox", fixtureKey: nil, acceptableKeys: nil)
    }
    return RoutingOracleWire(
      workspaceID: value.workspaceID.uuidString.lowercased(),
      expectation: expectation
    )
  }

  private static func decodeRoutingOracle(
    _ value: StrictJSONValue
  ) throws -> LocalWritingRoutingOracle {
    let object = try value.object(keys: ["workspaceID", "expectation"])
    return try LocalWritingRoutingOracle(
      workspaceID: canonicalUUID(object.required("workspaceID").string()),
      expectation: decodeRoutingExpectation(object.required("expectation"))
    )
  }

  private static func decodeRoutingExpectation(
    _ value: StrictJSONValue
  ) throws -> LocalWritingRoutingExpectation {
    let tagged = try value.object(
      required: ["type"],
      optional: ["fixtureKey", "acceptableKeys"]
    )
    switch try tagged.required("type").string() {
    case "unique":
      let object = try value.object(keys: ["type", "fixtureKey"])
      return try .unique(object.required("fixtureKey").string())
    case "ambiguous":
      let object = try value.object(keys: ["type", "acceptableKeys"])
      return try .ambiguous(
        object.required("acceptableKeys").array().map { try $0.string() }
      )
    case "inbox":
      _ = try value.object(keys: ["type"])
      return .inbox
    default:
      throw LocalWritingCorpusError.invalidRouting
    }
  }

  private static func decodeWorkspace(
    _ value: StrictJSONValue
  ) throws -> LocalWritingControlledWorkspaceManifestEnvelope {
    let object = try value.object(
      keys: ["schemaVersion", "workspaceID", "revisionSHA256", "payload"]
    )
    guard try object.required("schemaVersion").int() == 1 else {
      throw LocalWritingCorpusError.unsupportedSchemaVersion
    }
    let workspaceID = try canonicalUUID(object.required("workspaceID").string())
    let revision = try object.required("revisionSHA256").string()
    guard LocalWritingCorpusPayload.isValidSHA256(revision) else {
      throw LocalWritingCorpusError.invalidHash
    }
    let payloadObject = try object.required("payload").object(
      keys: ["cohort", "inboxFixtureKey", "notes", "mutationSchedule"]
    )
    guard let cohort = LocalWritingControlledWorkspaceCohort(
      rawValue: try payloadObject.required("cohort").string()
    ) else { throw LocalWritingCorpusError.invalidWorkspace }
    let notes = try payloadObject.required("notes").array().map(decodeControlledNote)
    let mutations = try payloadObject.required("mutationSchedule").array().map(decodeMutation)
    let payload = try LocalWritingControlledWorkspacePayload(
      cohort: cohort,
      inboxFixtureKey: payloadObject.required("inboxFixtureKey").string(),
      notes: notes,
      mutationSchedule: mutations
    )
    guard revision == sha256(try encode(workspacePayloadWire(payload))) else {
      throw LocalWritingCorpusError.digestMismatch
    }
    let workspace = LocalWritingControlledWorkspaceManifestEnvelope(
      workspaceID: workspaceID,
      revisionSHA256: revision,
      payload: payload
    )
    return workspace
  }

  private static func decodeControlledNote(
    _ value: StrictJSONValue
  ) throws -> LocalWritingControlledNote {
    let note = try value.object(
      keys: ["fixtureKey", "noteID", "title", "body", "revision"]
    )
    return try LocalWritingControlledNote(
      fixtureKey: note.required("fixtureKey").string(),
      noteID: canonicalUUID(note.required("noteID").string()),
      title: note.required("title").string(),
      body: note.required("body").string(),
      revision: note.required("revision").uint64()
    )
  }

  private static func decodeMutation(
    _ value: StrictJSONValue
  ) throws -> LocalWritingWorkspaceMutation {
    let object = try value.object(keys: ["sequence", "operation"])
    return try LocalWritingWorkspaceMutation(
      sequence: object.required("sequence").uint64(),
      operation: decodeMutationOperation(object.required("operation"))
    )
  }

  private static func decodeMutationOperation(
    _ value: StrictJSONValue
  ) throws -> LocalWritingWorkspaceMutationOperation {
    let tagged = try value.object(
      required: ["type"],
      optional: ["note", "fixtureKey", "expectedRevision", "replacement"]
    )
    switch try tagged.required("type").string() {
    case "create":
      let object = try value.object(keys: ["type", "note"])
      return try .create(decodeControlledNote(object.required("note")))
    case "replace":
      let object = try value.object(
        keys: ["type", "fixtureKey", "expectedRevision", "replacement"]
      )
      return try .replace(
        fixtureKey: object.required("fixtureKey").string(),
        expectedRevision: object.required("expectedRevision").uint64(),
        replacement: decodeControlledNote(object.required("replacement"))
      )
    case "delete":
      let object = try value.object(keys: ["type", "fixtureKey", "expectedRevision"])
      return try .delete(
        fixtureKey: object.required("fixtureKey").string(),
        expectedRevision: object.required("expectedRevision").uint64()
      )
    default:
      throw LocalWritingCorpusError.invalidWorkspaceMutation
    }
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      return try encoder.encode(value)
    } catch {
      throw LocalWritingCorpusError.invalidValue
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct CorpusEnvelopeWire: Codable {
  let schemaVersion: Int
  let corpusID: String
  let revisionSHA256: String
  let payload: CorpusPayloadWire
}

private struct CorpusPayloadWire: Codable {
  let language: String
  let claimScope: String
  let consentReceiptSHA256: String
  let createdAtUnixMilliseconds: Int64
  let controlledWorkspaces: [ControlledWorkspaceEnvelopeWire]
  let cases: [CorpusCaseWire]
}

private struct CorpusCaseWire: Codable {
  let id: String
  let materialLineageID: String
  let sourceClass: String
  let humanSpeechEligible: Bool
  let scoringEligibility: String
  let audio: AudioReceiptWire?
  let referenceTranscript: String
  let tags: [String]
  let protectedExpectations: [ProtectedExpectationWire]
  let cleanupOracle: CleanupOracleWire
  let routingOracle: RoutingOracleWire?
  let executionVariants: [ExecutionVariantWire]
}

private struct ControlledWorkspaceEnvelopeWire: Codable {
  let schemaVersion: Int
  let workspaceID: String
  let revisionSHA256: String
  let payload: ControlledWorkspacePayloadWire
}

private struct ControlledWorkspacePayloadWire: Codable {
  let cohort: String
  let inboxFixtureKey: String
  let notes: [ControlledNoteWire]
  let mutationSchedule: [WorkspaceMutationWire]
}

private struct ControlledNoteWire: Codable {
  let fixtureKey: String
  let noteID: String
  let title: String
  let body: String
  let revision: UInt64
}

private struct WorkspaceMutationWire: Codable {
  let sequence: UInt64
  let operation: MutationOperationWire
}

private struct MutationOperationWire: Codable {
  let type: String
  let note: ControlledNoteWire?
  let fixtureKey: String?
  let expectedRevision: UInt64?
  let replacement: ControlledNoteWire?
}

private struct RoutingOracleWire: Codable {
  let workspaceID: String
  let expectation: RoutingExpectationWire
}

private struct RoutingExpectationWire: Codable {
  let type: String
  let fixtureKey: String?
  let acceptableKeys: [String]?
}

private struct ExecutionVariantWire: Codable {
  let lifecycle: String
  let memory: String
  let power: String
  let inputPath: String
  let cancellationStage: String?
}

private struct AudioReceiptWire: Codable {
  let relativePath: String
  let audioSHA256: String
  let byteCount: UInt64
  let durationMilliseconds: UInt64
  let sampleRateHz: UInt32
  let channelCount: UInt8
  let sampleFormat: String
  let container: String
  let speakerID: String
  let capturedAtUnixMilliseconds: Int64
  let inputDeviceClass: String
  let deviceIdentitySHA256: String
  let captureClass: String
  let consentReceiptSHA256: String
}

private struct ProtectedExpectationWire: Codable {
  let kind: String
  let text: String
  let utf16Start: UInt64
  let utf16Length: UInt64
  let comparison: String
}

private struct CleanupOracleWire: Codable {
  let type: String
  let text: String?
  let operations: [CleanupOperationWire]?
}

private struct CleanupOperationWire: Codable {
  let type: String
  let value: String?
  let values: [String]?
  let removed: [String]?
  let kept: [String]?
}

private enum StrictJSONValue: Equatable {
  case object([String: StrictJSONValue])
  case array([StrictJSONValue])
  case string(String)
  case integer(String)
  case bool(Bool)
  case null

  func object(keys: Set<String>) throws -> [String: StrictJSONValue] {
    if case .null = self { throw LocalWritingCorpusError.explicitNull }
    guard case .object(let value) = self else {
      throw LocalWritingCorpusError.invalidValue
    }
    guard Set(value.keys).isSubset(of: keys) else {
      throw LocalWritingCorpusError.unknownKey
    }
    guard Set(value.keys) == keys else {
      throw LocalWritingCorpusError.invalidValue
    }
    return value
  }

  func object(
    required: Set<String>,
    optional: Set<String>
  ) throws -> [String: StrictJSONValue] {
    if case .null = self { throw LocalWritingCorpusError.explicitNull }
    guard case .object(let value) = self else {
      throw LocalWritingCorpusError.invalidValue
    }
    let actual = Set(value.keys)
    guard actual.isSubset(of: required.union(optional)) else {
      throw LocalWritingCorpusError.unknownKey
    }
    guard required.isSubset(of: actual) else { throw LocalWritingCorpusError.invalidValue }
    return value
  }

  func array() throws -> [StrictJSONValue] {
    if case .null = self { throw LocalWritingCorpusError.explicitNull }
    guard case .array(let value) = self else {
      throw LocalWritingCorpusError.invalidValue
    }
    return value
  }

  func string() throws -> String {
    if case .null = self { throw LocalWritingCorpusError.explicitNull }
    guard case .string(let value) = self else {
      throw LocalWritingCorpusError.invalidValue
    }
    return value
  }

  func int() throws -> Int {
    let token = try integerToken()
    guard let value = Int(token) else { throw LocalWritingCorpusError.invalidNumber }
    return value
  }

  func int64() throws -> Int64 {
    let token = try integerToken()
    guard let value = Int64(token) else { throw LocalWritingCorpusError.invalidNumber }
    return value
  }

  func uint64() throws -> UInt64 {
    let token = try integerToken()
    guard let value = UInt64(token) else { throw LocalWritingCorpusError.invalidNumber }
    return value
  }

  func uint32() throws -> UInt32 {
    let token = try integerToken()
    guard let value = UInt32(token) else { throw LocalWritingCorpusError.invalidNumber }
    return value
  }

  func uint8() throws -> UInt8 {
    let token = try integerToken()
    guard let value = UInt8(token) else { throw LocalWritingCorpusError.invalidNumber }
    return value
  }

  func bool() throws -> Bool {
    if case .null = self { throw LocalWritingCorpusError.explicitNull }
    guard case .bool(let value) = self else {
      throw LocalWritingCorpusError.invalidValue
    }
    return value
  }

  private func integerToken() throws -> String {
    if case .null = self { throw LocalWritingCorpusError.explicitNull }
    guard case .integer(let value) = self else {
      throw LocalWritingCorpusError.invalidNumber
    }
    return value
  }
}

private extension Dictionary where Key == String, Value == StrictJSONValue {
  func required(_ key: String) throws -> StrictJSONValue {
    guard let value = self[key] else { throw LocalWritingCorpusError.invalidValue }
    return value
  }
}

private struct StrictJSONParser {
  private let bytes: [UInt8]
  private var index = 0

  init(data: Data) throws {
    guard data.count <= 64 * 1_024 * 1_024 else {
      throw LocalWritingCorpusError.inputTooLarge
    }
    guard String(data: data, encoding: .utf8) != nil else {
      throw LocalWritingCorpusError.invalidUTF8
    }
    bytes = Array(data)
  }

  mutating func parse() throws -> StrictJSONValue {
    skipWhitespace()
    let value = try parseValue(depth: 0)
    skipWhitespace()
    guard index == bytes.count else { throw LocalWritingCorpusError.invalidJSON }
    return value
  }

  private mutating func parseValue(depth: Int) throws -> StrictJSONValue {
    guard index < bytes.count else { throw LocalWritingCorpusError.invalidJSON }
    switch bytes[index] {
    case 0x7B: return try parseObject(depth: depth + 1)
    case 0x5B: return try parseArray(depth: depth + 1)
    case 0x22: return .string(try parseString())
    case 0x74:
      try consumeLiteral("true")
      return .bool(true)
    case 0x66:
      try consumeLiteral("false")
      return .bool(false)
    case 0x6E:
      try consumeLiteral("null")
      return .null
    case 0x2D, 0x30...0x39:
      return .integer(try parseInteger())
    default:
      throw LocalWritingCorpusError.invalidJSON
    }
  }

  private mutating func parseObject(depth: Int) throws -> StrictJSONValue {
    guard depth <= 32 else { throw LocalWritingCorpusError.excessiveDepth }
    try consume(0x7B)
    skipWhitespace()
    var result: [String: StrictJSONValue] = [:]
    if consumeIfPresent(0x7D) { return .object(result) }
    while true {
      guard index < bytes.count, bytes[index] == 0x22 else {
        throw LocalWritingCorpusError.invalidJSON
      }
      let key = try parseString()
      guard result[key] == nil else { throw LocalWritingCorpusError.duplicateKey }
      skipWhitespace()
      try consume(0x3A)
      skipWhitespace()
      result[key] = try parseValue(depth: depth)
      skipWhitespace()
      if consumeIfPresent(0x7D) { return .object(result) }
      try consume(0x2C)
      skipWhitespace()
    }
  }

  private mutating func parseArray(depth: Int) throws -> StrictJSONValue {
    guard depth <= 32 else { throw LocalWritingCorpusError.excessiveDepth }
    try consume(0x5B)
    skipWhitespace()
    var result: [StrictJSONValue] = []
    if consumeIfPresent(0x5D) { return .array(result) }
    while true {
      result.append(try parseValue(depth: depth))
      skipWhitespace()
      if consumeIfPresent(0x5D) { return .array(result) }
      try consume(0x2C)
      skipWhitespace()
    }
  }

  private mutating func parseString() throws -> String {
    try consume(0x22)
    var result: [UInt8] = []
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      switch byte {
      case 0x22:
        guard let value = String(bytes: result, encoding: .utf8) else {
          throw LocalWritingCorpusError.invalidUTF8
        }
        return value
      case 0x5C:
        guard index < bytes.count else { throw LocalWritingCorpusError.invalidJSON }
        let escape = bytes[index]
        index += 1
        switch escape {
        case 0x22, 0x5C, 0x2F: result.append(escape)
        case 0x62: result.append(0x08)
        case 0x66: result.append(0x0C)
        case 0x6E: result.append(0x0A)
        case 0x72: result.append(0x0D)
        case 0x74: result.append(0x09)
        case 0x75:
          var scalar = try parseHexQuad()
          if scalar >= 0xD800 && scalar <= 0xDBFF {
            guard index + 1 < bytes.count, bytes[index] == 0x5C,
              bytes[index + 1] == 0x75
            else { throw LocalWritingCorpusError.invalidJSON }
            index += 2
            let low = try parseHexQuad()
            guard low >= 0xDC00 && low <= 0xDFFF else {
              throw LocalWritingCorpusError.invalidJSON
            }
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
          } else if scalar >= 0xDC00 && scalar <= 0xDFFF {
            throw LocalWritingCorpusError.invalidJSON
          }
          guard let unicode = UnicodeScalar(scalar) else {
            throw LocalWritingCorpusError.invalidJSON
          }
          result.append(contentsOf: String(unicode).utf8)
        default:
          throw LocalWritingCorpusError.invalidJSON
        }
      case 0x00...0x1F:
        throw LocalWritingCorpusError.invalidJSON
      default:
        result.append(byte)
      }
    }
    throw LocalWritingCorpusError.invalidJSON
  }

  private mutating func parseInteger() throws -> String {
    let start = index
    _ = consumeIfPresent(0x2D)
    guard index < bytes.count else { throw LocalWritingCorpusError.invalidNumber }
    if consumeIfPresent(0x30) {
      if index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
        throw LocalWritingCorpusError.invalidNumber
      }
    } else {
      guard index < bytes.count, bytes[index] >= 0x31, bytes[index] <= 0x39 else {
        throw LocalWritingCorpusError.invalidNumber
      }
      index += 1
      while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
        index += 1
      }
    }
    if index < bytes.count, bytes[index] == 0x2E || bytes[index] == 0x65
      || bytes[index] == 0x45
    {
      throw LocalWritingCorpusError.invalidNumber
    }
    return String(decoding: bytes[start..<index], as: UTF8.self)
  }

  private mutating func parseHexQuad() throws -> UInt32 {
    guard index + 4 <= bytes.count else { throw LocalWritingCorpusError.invalidJSON }
    var result: UInt32 = 0
    for _ in 0..<4 {
      let byte = bytes[index]
      index += 1
      let digit: UInt32
      switch byte {
      case 0x30...0x39: digit = UInt32(byte - 0x30)
      case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
      case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
      default: throw LocalWritingCorpusError.invalidJSON
      }
      result = result * 16 + digit
    }
    return result
  }

  private mutating func consumeLiteral(_ literal: StaticString) throws {
    let expected = Array(String(describing: literal).utf8)
    guard index + expected.count <= bytes.count,
      Array(bytes[index..<(index + expected.count)]) == expected
    else { throw LocalWritingCorpusError.invalidJSON }
    index += expected.count
  }

  private mutating func consume(_ expected: UInt8) throws {
    guard consumeIfPresent(expected) else { throw LocalWritingCorpusError.invalidJSON }
  }

  private mutating func consumeIfPresent(_ expected: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == expected else { return false }
    index += 1
    return true
  }

  private mutating func skipWhitespace() {
    while index < bytes.count,
      bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A
        || bytes[index] == 0x0D
    {
      index += 1
    }
  }
}

private func canonicalUUID(_ value: String) throws -> UUID {
  guard value == value.lowercased(), let uuid = UUID(uuidString: value),
    uuid.uuidString.lowercased() == value
  else { throw LocalWritingCorpusError.invalidIdentifier }
  return uuid
}

private func isNFC(_ value: String) -> Bool {
  value == value.precomposedStringWithCanonicalMapping
}

private func isASCIIHex(_ value: UInt8) -> Bool {
  (value >= 0x30 && value <= 0x39) || (value >= 0x41 && value <= 0x46)
    || (value >= 0x61 && value <= 0x66)
}

private func isValidFixtureKey(_ value: String) -> Bool {
  let bytes = Array(value.utf8)
  guard !bytes.isEmpty, bytes.count <= 64, bytes[0] >= 0x61, bytes[0] <= 0x7A else {
    return false
  }
  return bytes.dropFirst().allSatisfy {
    ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D
  }
}

private func asciiLess(_ lhs: String, _ rhs: String) -> Bool {
  lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

private func isValidCleanupString(_ value: String) -> Bool {
  !value.isEmpty && isNFC(value)
}

private func isValidCleanupTokens(_ values: [String]) -> Bool {
  !values.isEmpty && values.allSatisfy(isValidCleanupString)
}

private func cleanupOperationWire(
  _ value: LocalWritingCleanupEditOperation
) -> CleanupOperationWire {
  switch value.storage {
  case .caseChange:
    CleanupOperationWire(
      type: "caseChange", value: nil, values: nil, removed: nil, kept: nil
    )
  case .punctuation:
    CleanupOperationWire(
      type: "punctuation", value: nil, values: nil, removed: nil, kept: nil
    )
  case .whitespace:
    CleanupOperationWire(
      type: "whitespace", value: nil, values: nil, removed: nil, kept: nil
    )
  case .deleteFiller(let value):
    CleanupOperationWire(
      type: "deleteFiller", value: value, values: nil, removed: nil, kept: nil
    )
  case .deleteImmediateDuplicate(let values):
    CleanupOperationWire(
      type: "deleteImmediateDuplicate", value: nil, values: values, removed: nil, kept: nil
    )
  case .selectExplicitCorrection(let removed, let kept):
    CleanupOperationWire(
      type: "selectExplicitCorrection", value: nil, values: nil, removed: removed, kept: kept
    )
  case .formatList:
    CleanupOperationWire(
      type: "formatList", value: nil, values: nil, removed: nil, kept: nil
    )
  }
}

private func cleanupOperationData(
  _ value: LocalWritingCleanupEditOperation
) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  do {
    return try encoder.encode(cleanupOperationWire(value))
  } catch {
    throw LocalWritingCorpusError.invalidCleanupOracle
  }
}

private func canonicalExecutionVariants(
  _ values: [LocalWritingExecutionVariant]
) throws -> [LocalWritingExecutionVariant] {
  func tuple(_ value: LocalWritingExecutionVariant) -> [String] {
    [
      value.lifecycle.rawValue,
      value.memory.rawValue,
      value.power.rawValue,
      value.inputPath.rawValue,
      value.cancellationStage?.rawValue ?? "",
    ]
  }
  let sorted = values.sorted { lhs, rhs in
    let left = tuple(lhs)
    let right = tuple(rhs)
    for index in left.indices where left[index] != right[index] {
      return asciiLess(left[index], right[index])
    }
    return false
  }
  for index in sorted.indices.dropFirst() where sorted[index - 1] == sorted[index] {
    throw LocalWritingCorpusError.duplicateCanonicalValue
  }
  return sorted
}

private func validateProtectedExpectations(
  _ values: [LocalWritingProtectedExpectation],
  in transcript: String
) throws -> [LocalWritingProtectedExpectation] {
  let sorted = values.sorted { lhs, rhs in
    if lhs.utf16Start != rhs.utf16Start { return lhs.utf16Start < rhs.utf16Start }
    if lhs.utf16Length != rhs.utf16Length { return lhs.utf16Length < rhs.utf16Length }
    if lhs.kind.rawValue != rhs.kind.rawValue {
      return asciiLess(lhs.kind.rawValue, rhs.kind.rawValue)
    }
    if lhs.comparison.rawValue != rhs.comparison.rawValue {
      return asciiLess(lhs.comparison.rawValue, rhs.comparison.rawValue)
    }
    return asciiLess(lhs.text, rhs.text)
  }
  let utf16 = transcript.utf16
  for expectation in sorted {
    let start = Int(expectation.utf16Start)
    let length = Int(expectation.utf16Length)
    guard start <= utf16.count, length <= utf16.count - start else {
      throw LocalWritingCorpusError.invalidProtectedExpectation
    }
    let startUTF16 = utf16.index(utf16.startIndex, offsetBy: start)
    let endUTF16 = utf16.index(startUTF16, offsetBy: length)
    guard let stringStart = String.Index(startUTF16, within: transcript),
      let stringEnd = String.Index(endUTF16, within: transcript),
      String(transcript[stringStart..<stringEnd]) == expectation.text
    else { throw LocalWritingCorpusError.invalidProtectedExpectation }
  }
  for firstIndex in sorted.indices {
    for secondIndex in sorted.indices where secondIndex > firstIndex {
      let first = sorted[firstIndex]
      let second = sorted[secondIndex]
      if first == second { throw LocalWritingCorpusError.invalidProtectedExpectation }
      let firstEnd = first.utf16Start + first.utf16Length
      let secondEnd = second.utf16Start + second.utf16Length
      let overlaps = first.utf16Start < secondEnd && second.utf16Start < firstEnd
      guard overlaps else { continue }
      let nested = (first.utf16Start <= second.utf16Start && firstEnd >= secondEnd)
        || (second.utf16Start <= first.utf16Start && secondEnd >= firstEnd)
      guard nested, first.kind != second.kind else {
        throw LocalWritingCorpusError.invalidProtectedExpectation
      }
    }
  }
  return sorted
}

private func validateMutationSchedule(
  _ schedule: [LocalWritingWorkspaceMutation],
  notes: [LocalWritingControlledNote],
  inboxFixtureKey: String
) throws {
  var liveByKey = Dictionary(uniqueKeysWithValues: notes.map { ($0.fixtureKey, $0) })
  var liveIDs = Set(notes.map(\.noteID))
  var tombstonedKeys = Set<String>()
  var tombstonedIDs = Set<UUID>()
  for (offset, mutation) in schedule.enumerated() {
    guard mutation.sequence == UInt64(offset + 1) else {
      throw LocalWritingCorpusError.invalidWorkspaceMutation
    }
    switch mutation.operation.storage {
    case .create(let note):
      guard liveByKey[note.fixtureKey] == nil, !liveIDs.contains(note.noteID),
        !tombstonedKeys.contains(note.fixtureKey), !tombstonedIDs.contains(note.noteID)
      else { throw LocalWritingCorpusError.invalidWorkspaceMutation }
      liveByKey[note.fixtureKey] = note
      liveIDs.insert(note.noteID)
    case .replace(let fixtureKey, let expectedRevision, let replacement):
      guard let current = liveByKey[fixtureKey], current.revision == expectedRevision,
        expectedRevision != UInt64.max, replacement.fixtureKey == fixtureKey,
        replacement.noteID == current.noteID,
        replacement.revision == expectedRevision + 1
      else { throw LocalWritingCorpusError.invalidWorkspaceMutation }
      liveByKey[fixtureKey] = replacement
    case .delete(let fixtureKey, let expectedRevision):
      guard fixtureKey != inboxFixtureKey, let current = liveByKey[fixtureKey],
        current.revision == expectedRevision
      else { throw LocalWritingCorpusError.invalidWorkspaceMutation }
      liveByKey.removeValue(forKey: fixtureKey)
      liveIDs.remove(current.noteID)
      tombstonedKeys.insert(fixtureKey)
      tombstonedIDs.insert(current.noteID)
    }
    guard liveByKey[inboxFixtureKey] != nil else {
      throw LocalWritingCorpusError.invalidWorkspaceMutation
    }
  }
}
