import Foundation

public enum EvaluationLanguageMode: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case english
  case mandarin
  case mixed
}

public enum TranscriptArtifactKind: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case asrRaw
  case dictionaryBaseline
  case cleanedResult
}

public struct EditCounts: Codable, Equatable, Sendable {
  public let substitutions: Int
  public let deletions: Int
  public let insertions: Int
  public let referenceUnits: Int

  public init(
    substitutions: Int,
    deletions: Int,
    insertions: Int,
    referenceUnits: Int
  ) {
    self.substitutions = substitutions
    self.deletions = deletions
    self.insertions = insertions
    self.referenceUnits = referenceUnits
  }

  public var errorRate: Double {
    guard referenceUnits > 0 else {
      return substitutions == 0 && deletions == 0 && insertions == 0 ? 0 : 1
    }
    return Double(substitutions + deletions + insertions)
      / Double(referenceUnits)
  }

  public func adding(_ other: EditCounts) -> EditCounts {
    EditCounts(
      substitutions: substitutions + other.substitutions,
      deletions: deletions + other.deletions,
      insertions: insertions + other.insertions,
      referenceUnits: referenceUnits + other.referenceUnits
    )
  }
}

public enum EvaluationSeverity: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case error
  case warning
}

public enum ProtectedMatchMode: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case exactCase
  case caseInsensitive
  case numericExact
  case negationExact
}

public enum AudioConsentStatus: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case approved
  case revoked
  case pending
}

public enum CaptureTemperature: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case cold
  case warm
}

public enum ThermalState: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical
}

public enum ManualAdjudicationStatus: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case notRequired
  case pending
  case passed
  case failed
}

public enum EvaluationMetricKind: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case englishWordErrorRate
  case mandarinCharacterErrorRate
  case protectedTermAccuracy
}

public struct EvaluationTextSlice: Codable, Equatable, Sendable {
  public var language: EvaluationLanguageMode
  public var text: String

  public init(language: EvaluationLanguageMode, text: String) {
    self.language = language
    self.text = text
  }
}

public struct ProtectedExpectation: Codable, Equatable, Sendable {
  public var id: String
  public var term: String
  public var mode: ProtectedMatchMode
  public var language: EvaluationLanguageMode

  public init(
    id: String,
    term: String,
    mode: ProtectedMatchMode,
    language: EvaluationLanguageMode
  ) {
    self.id = id
    self.term = term
    self.mode = mode
    self.language = language
  }
}

public struct AudioProvenance: Codable, Equatable, Sendable {
  public var assetSHA256: String
  public var source: String
  public var license: String
  public var approved: Bool
  public var speakerLanguage: String
  public var speakerAccent: String?
  public var privacyReview: String
  public var revocationProcess: String

  public init(
    assetSHA256: String,
    source: String,
    license: String,
    approved: Bool,
    speakerLanguage: String,
    speakerAccent: String?,
    privacyReview: String,
    revocationProcess: String
  ) {
    self.assetSHA256 = assetSHA256
    self.source = source
    self.license = license
    self.approved = approved
    self.speakerLanguage = speakerLanguage
    self.speakerAccent = speakerAccent
    self.privacyReview = privacyReview
    self.revocationProcess = revocationProcess
  }
}

public struct AudioConsent: Codable, Equatable, Sendable {
  public var status: AudioConsentStatus
  public var recordID: String
  public var reviewer: String?
  public var reviewedAt: String?

  public init(
    status: AudioConsentStatus,
    recordID: String,
    reviewer: String?,
    reviewedAt: String?
  ) {
    self.status = status
    self.recordID = recordID
    self.reviewer = reviewer
    self.reviewedAt = reviewedAt
  }
}

public struct StandardBaselineIdentity: Codable, Equatable, Sendable {
  public var baselineID: String
  public var baselineRevision: String
  public var engine: String
  public var modelRevision: String
  public var corpusID: String
  public var corpusRevision: String
  public var osVersion: String
  public var hardwareModel: String
  public var architecture: String
  public var appBuild: String
  public var coldObservationCount: Int
  public var warmObservationCount: Int
  public var recordedAt: String

  public init(
    baselineID: String,
    baselineRevision: String,
    engine: String,
    modelRevision: String,
    corpusID: String,
    corpusRevision: String,
    osVersion: String,
    hardwareModel: String,
    architecture: String,
    appBuild: String,
    coldObservationCount: Int,
    warmObservationCount: Int,
    recordedAt: String
  ) {
    self.baselineID = baselineID
    self.baselineRevision = baselineRevision
    self.engine = engine
    self.modelRevision = modelRevision
    self.corpusID = corpusID
    self.corpusRevision = corpusRevision
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.architecture = architecture
    self.appBuild = appBuild
    self.coldObservationCount = coldObservationCount
    self.warmObservationCount = warmObservationCount
    self.recordedAt = recordedAt
  }
}

public struct StandardBaselineMetric: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var metric: EvaluationMetricKind
  public var value: Double

  public init(
    scope: EvaluationLanguageMode,
    metric: EvaluationMetricKind,
    value: Double
  ) {
    self.scope = scope
    self.metric = metric
    self.value = value
  }
}

public struct StandardBaselineEvidence: Codable, Equatable, Sendable {
  public var identity: StandardBaselineIdentity
  public var metrics: [StandardBaselineMetric]

  public init(
    identity: StandardBaselineIdentity,
    metrics: [StandardBaselineMetric]
  ) {
    self.identity = identity
    self.metrics = metrics
  }
}

public struct UnloadEvidence: Codable, Equatable, Sendable {
  public var unloadAttempted: Bool
  public var unloadSucceeded: Bool
  public var memoryAfterUnloadBytes: Int64
  public var observedAt: String

  public init(
    unloadAttempted: Bool,
    unloadSucceeded: Bool,
    memoryAfterUnloadBytes: Int64,
    observedAt: String
  ) {
    self.unloadAttempted = unloadAttempted
    self.unloadSucceeded = unloadSucceeded
    self.memoryAfterUnloadBytes = memoryAfterUnloadBytes
    self.observedAt = observedAt
  }
}

public struct CorpusProvenance: Codable, Equatable, Sendable {
  public var sourceType: String
  public var createdAt: String
  public var owner: String
  public var privacyReview: String
  public var audioPolicy: String

  public init(
    sourceType: String,
    createdAt: String,
    owner: String,
    privacyReview: String,
    audioPolicy: String
  ) {
    self.sourceType = sourceType
    self.createdAt = createdAt
    self.owner = owner
    self.privacyReview = privacyReview
    self.audioPolicy = audioPolicy
  }
}

public struct EvaluationCase: Codable, Equatable, Sendable {
  public var id: String
  public var language: EvaluationLanguageMode
  public var categories: [String]
  public var referenceText: String
  public var spokenText: String
  public var audioAsset: String?
  public var audioProvenance: AudioProvenance?
  public var audioConsent: AudioConsent?
  public var conditions: [String]
  public var protectedExpectations: [ProtectedExpectation]
  public var metricReferenceSlices: [EvaluationTextSlice]

  public init(
    id: String,
    language: EvaluationLanguageMode,
    categories: [String],
    referenceText: String,
    spokenText: String,
    audioAsset: String?,
    audioProvenance: AudioProvenance?,
    audioConsent: AudioConsent?,
    conditions: [String],
    protectedExpectations: [ProtectedExpectation],
    metricReferenceSlices: [EvaluationTextSlice]
  ) {
    self.id = id
    self.language = language
    self.categories = categories
    self.referenceText = referenceText
    self.spokenText = spokenText
    self.audioAsset = audioAsset
    self.audioProvenance = audioProvenance
    self.audioConsent = audioConsent
    self.conditions = conditions
    self.protectedExpectations = protectedExpectations
    self.metricReferenceSlices = metricReferenceSlices
  }
}

public struct EvaluationCorpus: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var corpusID: String
  public var revision: String
  public var provenance: CorpusProvenance
  public var cases: [EvaluationCase]

  public init(
    schemaVersion: Int,
    corpusID: String,
    revision: String,
    provenance: CorpusProvenance,
    cases: [EvaluationCase]
  ) {
    self.schemaVersion = schemaVersion
    self.corpusID = corpusID
    self.revision = revision
    self.provenance = provenance
    self.cases = cases
  }
}

public struct CandidateIdentity: Codable, Equatable, Sendable {
  public var candidateID: String
  public var displayName: String
  public var modelID: String
  public var modelRevision: String
  public var runtimeName: String
  public var runtimeRevision: String
  public var licenseReview: String

  public init(
    candidateID: String,
    displayName: String,
    modelID: String,
    modelRevision: String,
    runtimeName: String,
    runtimeRevision: String,
    licenseReview: String
  ) {
    self.candidateID = candidateID
    self.displayName = displayName
    self.modelID = modelID
    self.modelRevision = modelRevision
    self.runtimeName = runtimeName
    self.runtimeRevision = runtimeRevision
    self.licenseReview = licenseReview
  }
}

public struct RunEnvironment: Codable, Equatable, Sendable {
  public var osVersion: String
  public var hardwareModel: String
  public var architecture: String
  public var appBuild: String
  public var swiftVersion: String
  public var recordedAt: String

  public init(
    osVersion: String,
    hardwareModel: String,
    architecture: String,
    appBuild: String,
    swiftVersion: String,
    recordedAt: String
  ) {
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.architecture = architecture
    self.appBuild = appBuild
    self.swiftVersion = swiftVersion
    self.recordedAt = recordedAt
  }
}

public struct LatencyMeasurement: Codable, Equatable, Sendable {
  public var coldLoadMilliseconds: Double?
  public var asrMilliseconds: Double
  public var cleanupMilliseconds: Double
  public var endToEndMilliseconds: Double

  public init(
    coldLoadMilliseconds: Double?,
    asrMilliseconds: Double,
    cleanupMilliseconds: Double,
    endToEndMilliseconds: Double
  ) {
    self.coldLoadMilliseconds = coldLoadMilliseconds
    self.asrMilliseconds = asrMilliseconds
    self.cleanupMilliseconds = cleanupMilliseconds
    self.endToEndMilliseconds = endToEndMilliseconds
  }
}

public struct ResourceMeasurement: Codable, Equatable, Sendable {
  public var peakMemoryBytes: Int64
  public var idleMemoryBytes: Int64
  public var thermalState: ThermalState
  public var energyImpact: Double
  public var modelDownloadBytes: Int64
  public var modelInstalledBytes: Int64

  public init(
    peakMemoryBytes: Int64,
    idleMemoryBytes: Int64,
    thermalState: ThermalState,
    energyImpact: Double,
    modelDownloadBytes: Int64,
    modelInstalledBytes: Int64
  ) {
    self.peakMemoryBytes = peakMemoryBytes
    self.idleMemoryBytes = idleMemoryBytes
    self.thermalState = thermalState
    self.energyImpact = energyImpact
    self.modelDownloadBytes = modelDownloadBytes
    self.modelInstalledBytes = modelInstalledBytes
  }
}

public struct OfflineEvidence: Codable, Equatable, Sendable {
  public var networkDisabled: Bool
  public var networkRequestsObserved: Int
  public var contentTelemetryObserved: Bool
  public var isolationMethod: String
  public var startedAt: String
  public var endedAt: String
  public var evidenceNote: String

  public init(
    networkDisabled: Bool,
    networkRequestsObserved: Int,
    contentTelemetryObserved: Bool,
    isolationMethod: String,
    startedAt: String,
    endedAt: String,
    evidenceNote: String
  ) {
    self.networkDisabled = networkDisabled
    self.networkRequestsObserved = networkRequestsObserved
    self.contentTelemetryObserved = contentTelemetryObserved
    self.isolationMethod = isolationMethod
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.evidenceNote = evidenceNote
  }
}

public struct FailureCancellationEvidence: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var failureExercised: Bool
  public var failureFallbackVerified: Bool
  public var failureEvidenceID: String
  public var failureObservedAt: String
  public var cancellationExercised: Bool
  public var cancellationOutcomeVerified: Bool
  public var cancellationEvidenceID: String
  public var cancellationObservedAt: String
  public var evidenceNote: String

  public init(
    schemaVersion: Int,
    failureExercised: Bool,
    failureFallbackVerified: Bool,
    failureEvidenceID: String,
    failureObservedAt: String,
    cancellationExercised: Bool,
    cancellationOutcomeVerified: Bool,
    cancellationEvidenceID: String,
    cancellationObservedAt: String,
    evidenceNote: String
  ) {
    self.schemaVersion = schemaVersion
    self.failureExercised = failureExercised
    self.failureFallbackVerified = failureFallbackVerified
    self.failureEvidenceID = failureEvidenceID
    self.failureObservedAt = failureObservedAt
    self.cancellationExercised = cancellationExercised
    self.cancellationOutcomeVerified = cancellationOutcomeVerified
    self.cancellationEvidenceID = cancellationEvidenceID
    self.cancellationObservedAt = cancellationObservedAt
    self.evidenceNote = evidenceNote
  }
}

public struct ManualAdjudication: Codable, Equatable, Sendable {
  public var status: ManualAdjudicationStatus
  public var reviewer: String?
  public var notes: String?

  public init(
    status: ManualAdjudicationStatus,
    reviewer: String?,
    notes: String?
  ) {
    self.status = status
    self.reviewer = reviewer
    self.notes = notes
  }
}

public struct UtteranceResult: Codable, Equatable, Sendable {
  public var observationID: String
  public var caseID: String
  public var language: EvaluationLanguageMode
  public var artifactOrder: [TranscriptArtifactKind]
  public var asrRaw: String
  public var dictionaryBaseline: String?
  public var cleanedResult: String?
  public var captureTemperature: CaptureTemperature
  public var latency: LatencyMeasurement
  public var resources: ResourceMeasurement
  public var metricHypothesisSlices: [EvaluationTextSlice]
  public var manualAdjudication: ManualAdjudication?

  public init(
    observationID: String,
    caseID: String,
    language: EvaluationLanguageMode,
    artifactOrder: [TranscriptArtifactKind],
    asrRaw: String,
    dictionaryBaseline: String?,
    cleanedResult: String?,
    captureTemperature: CaptureTemperature,
    latency: LatencyMeasurement,
    resources: ResourceMeasurement,
    metricHypothesisSlices: [EvaluationTextSlice],
    manualAdjudication: ManualAdjudication?
  ) {
    self.observationID = observationID
    self.caseID = caseID
    self.language = language
    self.artifactOrder = artifactOrder
    self.asrRaw = asrRaw
    self.dictionaryBaseline = dictionaryBaseline
    self.cleanedResult = cleanedResult
    self.captureTemperature = captureTemperature
    self.latency = latency
    self.resources = resources
    self.metricHypothesisSlices = metricHypothesisSlices
    self.manualAdjudication = manualAdjudication
  }
}

public struct CandidateRun: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var runID: String
  public var corpusID: String
  public var corpusRevision: String
  public var candidate: CandidateIdentity
  public var environment: RunEnvironment
  public var standardBaseline: StandardBaselineEvidence
  public var unloadEvidence: UnloadEvidence
  public var results: [UtteranceResult]
  public var offlineEvidence: OfflineEvidence
  public var failureCancellationEvidence: FailureCancellationEvidence
  public var syntheticSample: Bool
  public var releaseEvidence: Bool

  public init(
    schemaVersion: Int,
    runID: String,
    corpusID: String,
    corpusRevision: String,
    candidate: CandidateIdentity,
    environment: RunEnvironment,
    standardBaseline: StandardBaselineEvidence,
    unloadEvidence: UnloadEvidence,
    results: [UtteranceResult],
    offlineEvidence: OfflineEvidence,
    failureCancellationEvidence: FailureCancellationEvidence,
    syntheticSample: Bool,
    releaseEvidence: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.runID = runID
    self.corpusID = corpusID
    self.corpusRevision = corpusRevision
    self.candidate = candidate
    self.environment = environment
    self.standardBaseline = standardBaseline
    self.unloadEvidence = unloadEvidence
    self.results = results
    self.offlineEvidence = offlineEvidence
    self.failureCancellationEvidence = failureCancellationEvidence
    self.syntheticSample = syntheticSample
    self.releaseEvidence = releaseEvidence
  }
}
