import Foundation

public struct EvaluationSliceGate: Codable, Equatable, Sendable {
  public var sliceID: String
  public var metric: EvaluationMetricKind
  public var maximumCandidateValue: Double
  public var maximumRegressionFromStandard: Double

  public init(
    sliceID: String,
    metric: EvaluationMetricKind,
    maximumCandidateValue: Double,
    maximumRegressionFromStandard: Double
  ) {
    self.sliceID = sliceID
    self.metric = metric
    self.maximumCandidateValue = maximumCandidateValue
    self.maximumRegressionFromStandard = maximumRegressionFromStandard
  }
}

public struct EvaluationGate: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var maxEnglishWordErrorRate: Double
  public var maxMandarinCharacterErrorRate: Double
  public var maxMixedEnglishWordErrorRate: Double
  public var maxMixedMandarinCharacterErrorRate: Double
  public var minimumProtectedTermAccuracy: Double
  public var maximumNumberFailures: Int
  public var maximumNegationFailures: Int
  public var maximumCleanupPreservationFailures: Int
  public var maxColdLatencyMilliseconds: Double
  public var maxWarmLatencyMilliseconds: Double
  public var maxPeakMemoryBytes: Int64
  public var maxIdleMemoryBytes: Int64
  public var maxPostUnloadMemoryBytes: Int64
  public var maxEnergyImpact: Double
  public var maxModelDownloadBytes: Int64
  public var maxModelInstalledBytes: Int64
  public var minimumStandardMaterialImprovement: Double
  public var allowedThermalStates: [ThermalState]
  public var sliceGates: [EvaluationSliceGate]
  public var maxFirstMeaningfulPartialMilliseconds: Double
  public var maxProvisionalUpdateIntervalMilliseconds: Double
  public var maxProvisionalInstabilityRate: Double
  public var maxFinalASRMilliseconds: Double
  public var maxCleanupMilliseconds: Double
  public var maxStopToInsertionMilliseconds: Double
  public var maxCancellationMilliseconds: Double
  public var maxReadyIdleDeltaBytes: Int64
  public var maxPostUnloadDeltaBytes: Int64
  public var maxUnloadMilliseconds: Double
  public var minimumRepeatedRunCount: Int

  public init(
    schemaVersion: Int,
    maxEnglishWordErrorRate: Double,
    maxMandarinCharacterErrorRate: Double,
    maxMixedEnglishWordErrorRate: Double,
    maxMixedMandarinCharacterErrorRate: Double,
    minimumProtectedTermAccuracy: Double,
    maximumNumberFailures: Int,
    maximumNegationFailures: Int,
    maximumCleanupPreservationFailures: Int,
    maxColdLatencyMilliseconds: Double,
    maxWarmLatencyMilliseconds: Double,
    maxPeakMemoryBytes: Int64,
    maxIdleMemoryBytes: Int64,
    maxPostUnloadMemoryBytes: Int64,
    maxEnergyImpact: Double,
    maxModelDownloadBytes: Int64,
    maxModelInstalledBytes: Int64,
    minimumStandardMaterialImprovement: Double,
    allowedThermalStates: [ThermalState],
    sliceGates: [EvaluationSliceGate] = [],
    maxFirstMeaningfulPartialMilliseconds: Double = 0,
    maxProvisionalUpdateIntervalMilliseconds: Double = 0,
    maxProvisionalInstabilityRate: Double = 0,
    maxFinalASRMilliseconds: Double = 0,
    maxCleanupMilliseconds: Double = 0,
    maxStopToInsertionMilliseconds: Double = 0,
    maxCancellationMilliseconds: Double = 0,
    maxReadyIdleDeltaBytes: Int64 = 0,
    maxPostUnloadDeltaBytes: Int64 = 0,
    maxUnloadMilliseconds: Double = 0,
    minimumRepeatedRunCount: Int = 50
  ) {
    self.schemaVersion = schemaVersion
    self.maxEnglishWordErrorRate = maxEnglishWordErrorRate
    self.maxMandarinCharacterErrorRate = maxMandarinCharacterErrorRate
    self.maxMixedEnglishWordErrorRate = maxMixedEnglishWordErrorRate
    self.maxMixedMandarinCharacterErrorRate = maxMixedMandarinCharacterErrorRate
    self.minimumProtectedTermAccuracy = minimumProtectedTermAccuracy
    self.maximumNumberFailures = maximumNumberFailures
    self.maximumNegationFailures = maximumNegationFailures
    self.maximumCleanupPreservationFailures = maximumCleanupPreservationFailures
    self.maxColdLatencyMilliseconds = maxColdLatencyMilliseconds
    self.maxWarmLatencyMilliseconds = maxWarmLatencyMilliseconds
    self.maxPeakMemoryBytes = maxPeakMemoryBytes
    self.maxIdleMemoryBytes = maxIdleMemoryBytes
    self.maxPostUnloadMemoryBytes = maxPostUnloadMemoryBytes
    self.maxEnergyImpact = maxEnergyImpact
    self.maxModelDownloadBytes = maxModelDownloadBytes
    self.maxModelInstalledBytes = maxModelInstalledBytes
    self.minimumStandardMaterialImprovement = minimumStandardMaterialImprovement
    self.allowedThermalStates = allowedThermalStates
    self.sliceGates = sliceGates
    self.maxFirstMeaningfulPartialMilliseconds = maxFirstMeaningfulPartialMilliseconds
    self.maxProvisionalUpdateIntervalMilliseconds = maxProvisionalUpdateIntervalMilliseconds
    self.maxProvisionalInstabilityRate = maxProvisionalInstabilityRate
    self.maxFinalASRMilliseconds = maxFinalASRMilliseconds
    self.maxCleanupMilliseconds = maxCleanupMilliseconds
    self.maxStopToInsertionMilliseconds = maxStopToInsertionMilliseconds
    self.maxCancellationMilliseconds = maxCancellationMilliseconds
    self.maxReadyIdleDeltaBytes = maxReadyIdleDeltaBytes
    self.maxPostUnloadDeltaBytes = maxPostUnloadDeltaBytes
    self.maxUnloadMilliseconds = maxUnloadMilliseconds
    self.minimumRepeatedRunCount = minimumRepeatedRunCount
  }
}

private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

extension EvaluationGate {
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case maxEnglishWordErrorRate
    case maxMandarinCharacterErrorRate
    case maxMixedEnglishWordErrorRate
    case maxMixedMandarinCharacterErrorRate
    case minimumProtectedTermAccuracy
    case maximumNumberFailures
    case maximumNegationFailures
    case maximumCleanupPreservationFailures
    case maxColdLatencyMilliseconds
    case maxWarmLatencyMilliseconds
    case maxPeakMemoryBytes
    case maxIdleMemoryBytes
    case maxPostUnloadMemoryBytes
    case maxEnergyImpact
    case maxModelDownloadBytes
    case maxModelInstalledBytes
    case minimumStandardMaterialImprovement
    case allowedThermalStates
    case sliceGates
    case maxFirstMeaningfulPartialMilliseconds
    case maxProvisionalUpdateIntervalMilliseconds
    case maxProvisionalInstabilityRate
    case maxFinalASRMilliseconds
    case maxCleanupMilliseconds
    case maxStopToInsertionMilliseconds
    case maxCancellationMilliseconds
    case maxReadyIdleDeltaBytes
    case maxPostUnloadDeltaBytes
    case maxUnloadMilliseconds
    case minimumRepeatedRunCount
  }

  public init(from decoder: Decoder) throws {
    let all = try decoder.container(keyedBy: AnyCodingKey.self)
    let allowed = Set(CodingKeys.allCases.map(\.stringValue))
    if let unknown = all.allKeys.first(where: {
      !allowed.contains($0.stringValue)
    }) {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath + [unknown],
          debugDescription: "Unknown EvaluationGate key \(unknown.stringValue)."
        )
      )
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    self.init(
      schemaVersion: schemaVersion,
      maxEnglishWordErrorRate: try container.decode(
        Double.self, forKey: .maxEnglishWordErrorRate
      ),
      maxMandarinCharacterErrorRate: try container.decode(
        Double.self, forKey: .maxMandarinCharacterErrorRate
      ),
      maxMixedEnglishWordErrorRate: try container.decode(
        Double.self, forKey: .maxMixedEnglishWordErrorRate
      ),
      maxMixedMandarinCharacterErrorRate: try container.decode(
        Double.self, forKey: .maxMixedMandarinCharacterErrorRate
      ),
      minimumProtectedTermAccuracy: try container.decode(
        Double.self, forKey: .minimumProtectedTermAccuracy
      ),
      maximumNumberFailures: try container.decode(
        Int.self, forKey: .maximumNumberFailures
      ),
      maximumNegationFailures: try container.decode(
        Int.self, forKey: .maximumNegationFailures
      ),
      maximumCleanupPreservationFailures: try container.decode(
        Int.self, forKey: .maximumCleanupPreservationFailures
      ),
      maxColdLatencyMilliseconds: try container.decode(
        Double.self, forKey: .maxColdLatencyMilliseconds
      ),
      maxWarmLatencyMilliseconds: try container.decode(
        Double.self, forKey: .maxWarmLatencyMilliseconds
      ),
      maxPeakMemoryBytes: try container.decode(
        Int64.self, forKey: .maxPeakMemoryBytes
      ),
      maxIdleMemoryBytes: try container.decode(
        Int64.self, forKey: .maxIdleMemoryBytes
      ),
      maxPostUnloadMemoryBytes: try container.decode(
        Int64.self, forKey: .maxPostUnloadMemoryBytes
      ),
      maxEnergyImpact: try container.decode(
        Double.self, forKey: .maxEnergyImpact
      ),
      maxModelDownloadBytes: try container.decode(
        Int64.self, forKey: .maxModelDownloadBytes
      ),
      maxModelInstalledBytes: try container.decode(
        Int64.self, forKey: .maxModelInstalledBytes
      ),
      minimumStandardMaterialImprovement: try container.decode(
        Double.self, forKey: .minimumStandardMaterialImprovement
      ),
      allowedThermalStates: try container.decode(
        [ThermalState].self, forKey: .allowedThermalStates
      ),
      sliceGates: try container.decodeIfPresent(
        [EvaluationSliceGate].self, forKey: .sliceGates
      ) ?? [],
      maxFirstMeaningfulPartialMilliseconds: try Self.decodeV2(
        .maxFirstMeaningfulPartialMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxProvisionalUpdateIntervalMilliseconds: try Self.decodeV2(
        .maxProvisionalUpdateIntervalMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxProvisionalInstabilityRate: try Self.decodeV2(
        .maxProvisionalInstabilityRate,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxFinalASRMilliseconds: try Self.decodeV2(
        .maxFinalASRMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxCleanupMilliseconds: try Self.decodeV2(
        .maxCleanupMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxStopToInsertionMilliseconds: try Self.decodeV2(
        .maxStopToInsertionMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxCancellationMilliseconds: try Self.decodeV2(
        .maxCancellationMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      maxReadyIdleDeltaBytes: try Self.decodeV2(
        .maxReadyIdleDeltaBytes,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: Int64(0)
      ),
      maxPostUnloadDeltaBytes: try Self.decodeV2(
        .maxPostUnloadDeltaBytes,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: Int64(0)
      ),
      maxUnloadMilliseconds: try Self.decodeV2(
        .maxUnloadMilliseconds,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 0.0
      ),
      minimumRepeatedRunCount: try Self.decodeV2(
        .minimumRepeatedRunCount,
        from: container,
        schemaVersion: schemaVersion,
        defaultValue: 50
      )
    )
  }

  private static func decodeV2<T: Decodable>(
    _ key: CodingKeys,
    from container: KeyedDecodingContainer<CodingKeys>,
    schemaVersion: Int,
    defaultValue: T
  ) throws -> T {
    if schemaVersion == 2 {
      return try container.decode(T.self, forKey: key)
    }
    return defaultValue
  }
}

public enum ReportMetric: String, Codable, Equatable, Sendable {
  case wordErrorRate
  case characterErrorRate
}

public enum ReleaseDecision: String, Codable, Equatable, Sendable {
  case passed
  case failed
  case reviewRequired
  case notEligible
}

public struct LanguageMetricSummary: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var language: EvaluationLanguageMode
  public var metric: ReportMetric
  public var caseCount: Int
  public var observationCount: Int
  public var counts: EditCounts
  public var errorRate: Double
  public var aggregation: String

  public init(
    scope: EvaluationLanguageMode,
    language: EvaluationLanguageMode,
    metric: ReportMetric,
    caseCount: Int,
    observationCount: Int,
    counts: EditCounts,
    errorRate: Double,
    aggregation: String
  ) {
    self.scope = scope
    self.language = language
    self.metric = metric
    self.caseCount = caseCount
    self.observationCount = observationCount
    self.counts = counts
    self.errorRate = errorRate
    self.aggregation = aggregation
  }
}

public struct ProtectedExpectationSummary: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var caseCount: Int
  public var observationCount: Int
  public var total: Int
  public var passed: Int
  public var failed: Int
  public var accuracy: Double
  public var numberFailures: Int
  public var negationFailures: Int

  public init(
    scope: EvaluationLanguageMode,
    caseCount: Int,
    observationCount: Int,
    total: Int,
    passed: Int,
    failed: Int,
    accuracy: Double,
    numberFailures: Int,
    negationFailures: Int
  ) {
    self.scope = scope
    self.caseCount = caseCount
    self.observationCount = observationCount
    self.total = total
    self.passed = passed
    self.failed = failed
    self.accuracy = accuracy
    self.numberFailures = numberFailures
    self.negationFailures = negationFailures
  }
}

public struct CleanupPreservationSummary: Codable, Equatable, Sendable {
  public var resultsWithCleanup: Int
  public var preservationFailures: Int
  public var manualReviewRequired: Int
  public var meaningProvenAutomatically: Bool

  public init(
    resultsWithCleanup: Int,
    preservationFailures: Int,
    manualReviewRequired: Int,
    meaningProvenAutomatically: Bool
  ) {
    self.resultsWithCleanup = resultsWithCleanup
    self.preservationFailures = preservationFailures
    self.manualReviewRequired = manualReviewRequired
    self.meaningProvenAutomatically = meaningProvenAutomatically
  }
}

public struct LatencySummary: Codable, Equatable, Sendable {
  public var coldCount: Int
  public var warmCount: Int
  public var coldP50Milliseconds: Double?
  public var coldP95Milliseconds: Double?
  public var warmP50Milliseconds: Double?
  public var warmP95Milliseconds: Double?

  public init(
    coldCount: Int,
    warmCount: Int,
    coldP50Milliseconds: Double?,
    coldP95Milliseconds: Double?,
    warmP50Milliseconds: Double?,
    warmP95Milliseconds: Double?
  ) {
    self.coldCount = coldCount
    self.warmCount = warmCount
    self.coldP50Milliseconds = coldP50Milliseconds
    self.coldP95Milliseconds = coldP95Milliseconds
    self.warmP50Milliseconds = warmP50Milliseconds
    self.warmP95Milliseconds = warmP95Milliseconds
  }
}

public struct ResourceSummary: Codable, Equatable, Sendable {
  public var maximumPeakMemoryBytes: Int64
  public var maximumIdleMemoryBytes: Int64
  public var maximumPostUnloadMemoryBytes: Int64
  public var maximumEnergyImpact: Double
  public var maximumModelDownloadBytes: Int64
  public var maximumModelInstalledBytes: Int64
  public var unloadAttempted: Bool
  public var unloadSucceeded: Bool
  public var thermalStates: [ThermalState]
  public var observationCount: Int

  public init(
    maximumPeakMemoryBytes: Int64,
    maximumIdleMemoryBytes: Int64,
    maximumPostUnloadMemoryBytes: Int64,
    maximumEnergyImpact: Double,
    maximumModelDownloadBytes: Int64,
    maximumModelInstalledBytes: Int64,
    unloadAttempted: Bool,
    unloadSucceeded: Bool,
    thermalStates: [ThermalState],
    observationCount: Int
  ) {
    self.maximumPeakMemoryBytes = maximumPeakMemoryBytes
    self.maximumIdleMemoryBytes = maximumIdleMemoryBytes
    self.maximumPostUnloadMemoryBytes = maximumPostUnloadMemoryBytes
    self.maximumEnergyImpact = maximumEnergyImpact
    self.maximumModelDownloadBytes = maximumModelDownloadBytes
    self.maximumModelInstalledBytes = maximumModelInstalledBytes
    self.unloadAttempted = unloadAttempted
    self.unloadSucceeded = unloadSucceeded
    self.thermalStates = thermalStates
    self.observationCount = observationCount
  }
}

public struct ArtifactCompletenessSummary: Codable, Equatable, Sendable {
  public var totalObservations: Int
  public var asrRawObservationCount: Int
  public var dictionaryBaselineObservationCount: Int
  public var cleanedResultObservationCount: Int

  public init(
    totalObservations: Int,
    asrRawObservationCount: Int,
    dictionaryBaselineObservationCount: Int,
    cleanedResultObservationCount: Int
  ) {
    self.totalObservations = totalObservations
    self.asrRawObservationCount = asrRawObservationCount
    self.dictionaryBaselineObservationCount =
      dictionaryBaselineObservationCount
    self.cleanedResultObservationCount = cleanedResultObservationCount
  }
}

public struct OfflineSummary: Codable, Equatable, Sendable {
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

public struct GateOutcome: Codable, Equatable, Sendable {
  public var id: String
  public var passed: Bool
  public var reviewRequired: Bool
  public var applicable: Bool
  public var observed: String
  public var limit: String
  public var detail: String

  public init(
    id: String,
    passed: Bool,
    reviewRequired: Bool,
    applicable: Bool = true,
    observed: String,
    limit: String,
    detail: String
  ) {
    self.id = id
    self.passed = passed
    self.reviewRequired = reviewRequired
    self.applicable = applicable
    self.observed = observed
    self.limit = limit
    self.detail = detail
  }
}

public struct StandardImprovementMetric: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var metric: EvaluationMetricKind
  public var baselineValue: Double
  public var candidateValue: Double
  public var improvement: Double

  public init(
    scope: EvaluationLanguageMode,
    metric: EvaluationMetricKind,
    baselineValue: Double,
    candidateValue: Double,
    improvement: Double
  ) {
    self.scope = scope
    self.metric = metric
    self.baselineValue = baselineValue
    self.candidateValue = candidateValue
    self.improvement = improvement
  }
}

public struct StandardComparisonSummary: Codable, Equatable, Sendable {
  public var baselineID: String
  public var baselineRevision: String
  public var baselineModelRevision: String
  public var corpusID: String
  public var corpusRevision: String
  public var osVersion: String
  public var hardwareModel: String
  public var architecture: String
  public var appBuild: String
  public var coldObservationCount: Int
  public var warmObservationCount: Int
  public var minimumRequiredImprovement: Double
  public var metrics: [StandardImprovementMetric]

  public init(
    baselineID: String,
    baselineRevision: String,
    baselineModelRevision: String,
    corpusID: String,
    corpusRevision: String,
    osVersion: String,
    hardwareModel: String,
    architecture: String,
    appBuild: String,
    coldObservationCount: Int,
    warmObservationCount: Int,
    minimumRequiredImprovement: Double,
    metrics: [StandardImprovementMetric]
  ) {
    self.baselineID = baselineID
    self.baselineRevision = baselineRevision
    self.baselineModelRevision = baselineModelRevision
    self.corpusID = corpusID
    self.corpusRevision = corpusRevision
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.architecture = architecture
    self.appBuild = appBuild
    self.coldObservationCount = coldObservationCount
    self.warmObservationCount = warmObservationCount
    self.minimumRequiredImprovement = minimumRequiredImprovement
    self.metrics = metrics
  }
}

public struct FailureCancellationSummary: Codable, Equatable, Sendable {
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

public struct EvaluationReport: Codable, Equatable, Sendable {
  public var candidateID: String
  public var runID: String
  public var syntheticSample: Bool
  public var languageMetrics: [LanguageMetricSummary]
  public var protectedExpectations: [ProtectedExpectationSummary]
  public var standardComparison: StandardComparisonSummary
  public var cleanupPreservation: CleanupPreservationSummary
  public var latency: LatencySummary
  public var resources: ResourceSummary
  public var artifacts: ArtifactCompletenessSummary
  public var offline: OfflineSummary
  public var failureCancellation: FailureCancellationSummary
  public var gateOutcomes: [GateOutcome]
  public var releaseDecision: ReleaseDecision
  public var markdown: String

  public init(
    candidateID: String,
    runID: String,
    syntheticSample: Bool,
    languageMetrics: [LanguageMetricSummary],
    protectedExpectations: [ProtectedExpectationSummary],
    standardComparison: StandardComparisonSummary,
    cleanupPreservation: CleanupPreservationSummary,
    latency: LatencySummary,
    resources: ResourceSummary,
    artifacts: ArtifactCompletenessSummary,
    offline: OfflineSummary,
    failureCancellation: FailureCancellationSummary,
    gateOutcomes: [GateOutcome],
    releaseDecision: ReleaseDecision,
    markdown: String
  ) {
    self.candidateID = candidateID
    self.runID = runID
    self.syntheticSample = syntheticSample
    self.languageMetrics = languageMetrics
    self.protectedExpectations = protectedExpectations
    self.standardComparison = standardComparison
    self.cleanupPreservation = cleanupPreservation
    self.latency = latency
    self.resources = resources
    self.artifacts = artifacts
    self.offline = offline
    self.failureCancellation = failureCancellation
    self.gateOutcomes = gateOutcomes
    self.releaseDecision = releaseDecision
    self.markdown = markdown
  }
}

public enum EvaluationReportError: Error, Equatable, Sendable {
  case invalid([EvaluationIssue])
  case invalidGate(String)
}

public enum EvaluationReportWriter {
  public static func atomicWrite(_ text: String, to target: URL) throws {
    try Data(text.utf8).write(to: target, options: .atomic)
  }
}

public enum EvaluationReportBuilder {
  private struct MetricSpec {
    let scope: EvaluationLanguageMode
    let language: EvaluationLanguageMode
    let reportMetric: ReportMetric
    let metricKind: EvaluationMetricKind
  }

  private struct ProtectedBuild {
    let summaries: [ProtectedExpectationSummary]
    let totalNumberFailures: Int
    let totalNegationFailures: Int
    let total: Int
  }

  private struct CleanupBuild {
    let summary: CleanupPreservationSummary
    let manualFailures: Int
  }

  private struct StandardBuild {
    let summary: StandardComparisonSummary
    let available: [String: Bool]
  }

  private static let metricSpecs = [
    MetricSpec(
      scope: .english,
      language: .english,
      reportMetric: .wordErrorRate,
      metricKind: .englishWordErrorRate
    ),
    MetricSpec(
      scope: .mandarin,
      language: .mandarin,
      reportMetric: .characterErrorRate,
      metricKind: .mandarinCharacterErrorRate
    ),
    MetricSpec(
      scope: .mixed,
      language: .english,
      reportMetric: .wordErrorRate,
      metricKind: .englishWordErrorRate
    ),
    MetricSpec(
      scope: .mixed,
      language: .mandarin,
      reportMetric: .characterErrorRate,
      metricKind: .mandarinCharacterErrorRate
    )
  ]

  public static func build(
    corpus: EvaluationCorpus,
    run: CandidateRun,
    gate: EvaluationGate
  ) throws -> EvaluationReport {
    try validate(gate: gate, run: run)
    let issues = EvaluationValidator.validate(run: run, against: corpus)
    if !issues.isEmpty {
      throw EvaluationReportError.invalid(issues)
    }

    let orderedResults = ordered(run.results, for: corpus)
    let languageMetrics = buildLanguageMetrics(
      corpus: corpus,
      results: orderedResults
    )
    let protected = buildProtectedExpectations(
      corpus: corpus,
      results: orderedResults
    )
    let cleanup = buildCleanup(
      corpus: corpus,
      results: orderedResults
    )
    let latency = buildLatency(results: orderedResults)
    let resources = buildResources(run: run, results: orderedResults)
    let artifacts = ArtifactCompletenessSummary(
      totalObservations: orderedResults.count,
      asrRawObservationCount: orderedResults.count,
      dictionaryBaselineObservationCount: orderedResults.filter {
        $0.dictionaryBaseline != nil
      }.count,
      cleanedResultObservationCount: orderedResults.filter {
        $0.cleanedResult != nil
      }.count
    )
    let offline = OfflineSummary(
      networkDisabled: run.offlineEvidence.networkDisabled,
      networkRequestsObserved: run.offlineEvidence.networkRequestsObserved,
      contentTelemetryObserved: run.offlineEvidence.contentTelemetryObserved,
      isolationMethod: run.offlineEvidence.isolationMethod,
      startedAt: run.offlineEvidence.startedAt,
      endedAt: run.offlineEvidence.endedAt,
      evidenceNote: run.offlineEvidence.evidenceNote
    )
    let failureCancellation = FailureCancellationSummary(
      schemaVersion: run.failureCancellationEvidence.schemaVersion,
      failureExercised: run.failureCancellationEvidence.failureExercised,
      failureFallbackVerified: run.failureCancellationEvidence.failureFallbackVerified,
      failureEvidenceID: run.failureCancellationEvidence.failureEvidenceID,
      failureObservedAt: run.failureCancellationEvidence.failureObservedAt,
      cancellationExercised: run.failureCancellationEvidence.cancellationExercised,
      cancellationOutcomeVerified: run.failureCancellationEvidence.cancellationOutcomeVerified,
      cancellationEvidenceID: run.failureCancellationEvidence.cancellationEvidenceID,
      cancellationObservedAt: run.failureCancellationEvidence.cancellationObservedAt,
      evidenceNote: run.failureCancellationEvidence.evidenceNote
    )
    let standard = try buildStandardComparison(
      corpus: corpus,
      run: run,
      languageMetrics: languageMetrics,
      protected: protected,
      gate: gate
    )
    if run.schemaVersion == 2 && run.releaseEvidence {
      let sliceIssues = validateV2SliceGates(gate, corpus: corpus)
      if !sliceIssues.isEmpty {
        throw EvaluationReportError.invalid(sliceIssues)
      }
    }
    let outcomes: [GateOutcome]
    if run.schemaVersion == 2 {
      outcomes = buildV2Outcomes(
        corpus: corpus,
        gate: gate,
        languageMetrics: languageMetrics,
        protected: protected,
        cleanup: cleanup,
        latency: latency,
        resources: resources,
        standard: standard,
        run: run
      )
    } else {
      outcomes = buildOutcomes(
        gate: gate,
        languageMetrics: languageMetrics,
        protected: protected,
        cleanup: cleanup,
        latency: latency,
        resources: resources,
        standard: standard,
        run: run
      )
    }
    let hasFailure = cleanup.manualFailures > 0 || outcomes.contains {
      $0.applicable && !$0.passed && !$0.reviewRequired
    }
    let hasReview = cleanup.summary.manualReviewRequired > 0
      || outcomes.contains { $0.applicable && $0.reviewRequired }
    let releaseDecision: ReleaseDecision
    if run.syntheticSample || !run.releaseEvidence {
      releaseDecision = .notEligible
    } else if hasFailure {
      releaseDecision = .failed
    } else if hasReview {
      releaseDecision = .reviewRequired
    } else {
      releaseDecision = .passed
    }
    let markdown = renderMarkdown(
      corpus: corpus,
      run: run,
      languageMetrics: languageMetrics,
      protected: protected,
      standard: standard.summary,
      cleanup: cleanup.summary,
      latency: latency,
      resources: resources,
      artifacts: artifacts,
      offline: offline,
      failureCancellation: failureCancellation,
      outcomes: outcomes,
      releaseDecision: releaseDecision
    )
    return EvaluationReport(
      candidateID: run.candidate.candidateID,
      runID: run.runID,
      syntheticSample: run.syntheticSample,
      languageMetrics: languageMetrics,
      protectedExpectations: protected.summaries,
      standardComparison: standard.summary,
      cleanupPreservation: cleanup.summary,
      latency: latency,
      resources: resources,
      artifacts: artifacts,
      offline: offline,
      failureCancellation: failureCancellation,
      gateOutcomes: outcomes,
      releaseDecision: releaseDecision,
      markdown: markdown
    )
  }

  private static func validate(gate: EvaluationGate, run: CandidateRun) throws {
    let fields: [(String, Bool)] = [
      ("schemaVersion", gate.schemaVersion == 1 || gate.schemaVersion == 2),
      ("maxEnglishWordErrorRate", gate.maxEnglishWordErrorRate.isFinite),
      ("maxMandarinCharacterErrorRate", gate.maxMandarinCharacterErrorRate.isFinite),
      ("maxMixedEnglishWordErrorRate", gate.maxMixedEnglishWordErrorRate.isFinite),
      ("maxMixedMandarinCharacterErrorRate", gate.maxMixedMandarinCharacterErrorRate.isFinite),
      ("minimumProtectedTermAccuracy", gate.minimumProtectedTermAccuracy.isFinite),
      ("maximumNumberFailures", true),
      ("maximumNegationFailures", true),
      ("maximumCleanupPreservationFailures", true),
      ("maxColdLatencyMilliseconds", gate.maxColdLatencyMilliseconds.isFinite),
      ("maxWarmLatencyMilliseconds", gate.maxWarmLatencyMilliseconds.isFinite),
      ("maxPeakMemoryBytes", true),
      ("maxIdleMemoryBytes", true),
      ("maxPostUnloadMemoryBytes", true),
      ("maxEnergyImpact", gate.maxEnergyImpact.isFinite),
      ("maxModelDownloadBytes", true),
      ("maxModelInstalledBytes", true),
      ("minimumStandardMaterialImprovement", gate.minimumStandardMaterialImprovement.isFinite),
      ("allowedThermalStates", !gate.allowedThermalStates.isEmpty)
    ]
    if run.schemaVersion == 2 && run.releaseEvidence && gate.schemaVersion != 2 {
      throw EvaluationReportError.invalidGate("schemaVersion")
    }
    if let invalid = fields.first(where: { !$0.1 }) {
      throw EvaluationReportError.invalidGate(invalid.0)
    }
    let nonnegative: [(String, Bool)] = [
      ("maxEnglishWordErrorRate", gate.maxEnglishWordErrorRate >= 0),
      ("maxMandarinCharacterErrorRate", gate.maxMandarinCharacterErrorRate >= 0),
      ("maxMixedEnglishWordErrorRate", gate.maxMixedEnglishWordErrorRate >= 0),
      ("maxMixedMandarinCharacterErrorRate", gate.maxMixedMandarinCharacterErrorRate >= 0),
      ("minimumProtectedTermAccuracy", (0...1).contains(gate.minimumProtectedTermAccuracy)),
      ("maximumNumberFailures", gate.maximumNumberFailures >= 0),
      ("maximumNegationFailures", gate.maximumNegationFailures >= 0),
      ("maximumCleanupPreservationFailures", gate.maximumCleanupPreservationFailures >= 0),
      ("maxColdLatencyMilliseconds", gate.maxColdLatencyMilliseconds > 0),
      ("maxWarmLatencyMilliseconds", gate.maxWarmLatencyMilliseconds > 0),
      ("maxPeakMemoryBytes", gate.maxPeakMemoryBytes >= 0),
      ("maxIdleMemoryBytes", gate.maxIdleMemoryBytes >= 0),
      ("maxPostUnloadMemoryBytes", gate.maxPostUnloadMemoryBytes >= 0),
      ("maxEnergyImpact", gate.maxEnergyImpact >= 0),
      ("maxModelDownloadBytes", gate.maxModelDownloadBytes >= 0),
      ("maxModelInstalledBytes", gate.maxModelInstalledBytes >= 0),
      ("minimumStandardMaterialImprovement", (0...1).contains(gate.minimumStandardMaterialImprovement))
    ]
    if let invalid = nonnegative.first(where: { !$0.1 }) {
      throw EvaluationReportError.invalidGate(invalid.0)
    }
    if gate.schemaVersion == 2 {
      let v2Fields: [(String, Bool)] = [
        ("maxFirstMeaningfulPartialMilliseconds", gate.maxFirstMeaningfulPartialMilliseconds.isFinite),
        ("maxProvisionalUpdateIntervalMilliseconds", gate.maxProvisionalUpdateIntervalMilliseconds.isFinite),
        ("maxProvisionalInstabilityRate", gate.maxProvisionalInstabilityRate.isFinite),
        ("maxFinalASRMilliseconds", gate.maxFinalASRMilliseconds.isFinite),
        ("maxCleanupMilliseconds", gate.maxCleanupMilliseconds.isFinite),
        ("maxStopToInsertionMilliseconds", gate.maxStopToInsertionMilliseconds.isFinite),
        ("maxCancellationMilliseconds", gate.maxCancellationMilliseconds.isFinite),
        ("maxReadyIdleDeltaBytes", gate.maxReadyIdleDeltaBytes >= 0),
        ("maxPostUnloadDeltaBytes", gate.maxPostUnloadDeltaBytes >= 0),
        ("maxUnloadMilliseconds", gate.maxUnloadMilliseconds.isFinite),
        ("minimumRepeatedRunCount", gate.minimumRepeatedRunCount >= 50),
        ("maxProvisionalInstabilityRate", (0...1).contains(gate.maxProvisionalInstabilityRate)),
        ("sliceGates", !gate.sliceGates.isEmpty)
      ]
      if let invalid = v2Fields.first(where: { !$0.1 }) {
        throw EvaluationReportError.invalidGate(invalid.0)
      }
      var seen: Set<String> = []
      for gate in gate.sliceGates {
        let key = "\(gate.sliceID):\(gate.metric.rawValue)"
        if !seen.insert(key).inserted {
          throw EvaluationReportError.invalidGate("sliceGates")
        }
        if gate.sliceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !gate.maximumCandidateValue.isFinite
          || gate.maximumCandidateValue < 0
          || !gate.maximumRegressionFromStandard.isFinite
          || gate.maximumRegressionFromStandard < 0
        {
          throw EvaluationReportError.invalidGate("sliceGates")
        }
      }
    }
  }

  private static func ordered(
    _ results: [UtteranceResult],
    for corpus: EvaluationCorpus
  ) -> [UtteranceResult] {
    let caseOrder = Dictionary(
      uniqueKeysWithValues: corpus.cases.enumerated().map { ($1.id, $0) }
    )
    return results.sorted {
      let lhsCase = caseOrder[$0.caseID] ?? Int.max
      let rhsCase = caseOrder[$1.caseID] ?? Int.max
      if lhsCase != rhsCase { return lhsCase < rhsCase }
      return $0.observationID < $1.observationID
    }
  }

  private static func buildLanguageMetrics(
    corpus: EvaluationCorpus,
    results: [UtteranceResult]
  ) -> [LanguageMetricSummary] {
    var summaries: [LanguageMetricSummary] = []
    for spec in metricSpecs {
      var counts = EditCounts(
        substitutions: 0,
        deletions: 0,
        insertions: 0,
        referenceUnits: 0
      )
      var caseRates: [Double] = []
      var caseCount = 0
      var observationCount = 0
      for item in corpus.cases where item.language == spec.scope {
        let observations = results.filter { $0.caseID == item.id }
        guard let reference = item.metricReferenceSlices.first(where: {
          $0.language == spec.language
        }), !observations.isEmpty else { continue }
        var caseCounts = EditCounts(
          substitutions: 0,
          deletions: 0,
          insertions: 0,
          referenceUnits: 0
        )
        for result in observations {
          let hypothesis = result.metricHypothesisSlices.first(where: {
            $0.language == spec.language
          })?.text ?? ""
          let editCounts: EditCounts
          switch spec.metricKind {
          case .englishWordErrorRate:
            editCounts = TranscriptMetrics.englishWordErrorRate(
              reference: reference.text,
              hypothesis: hypothesis
            )
          case .mandarinCharacterErrorRate:
            editCounts = TranscriptMetrics.mandarinCharacterErrorRate(
              reference: reference.text,
              hypothesis: hypothesis
            )
          case .protectedTermAccuracy:
            continue
          }
          caseCounts = caseCounts.adding(editCounts)
        }
        counts = counts.adding(caseCounts)
        caseRates.append(caseCounts.errorRate)
        caseCount += 1
        observationCount += observations.count
      }
      guard caseCount > 0 else { continue }
      summaries.append(LanguageMetricSummary(
        scope: spec.scope,
        language: spec.language,
        metric: spec.reportMetric,
        caseCount: caseCount,
        observationCount: observationCount,
        counts: counts,
        errorRate: caseRates.reduce(0, +) / Double(caseRates.count),
        aggregation: "unweighted mean of case-level aggregate error rates."
      ))
    }
    return summaries
  }

  private static func buildProtectedExpectations(
    corpus: EvaluationCorpus,
    results: [UtteranceResult]
  ) -> ProtectedBuild {
    var summaries: [ProtectedExpectationSummary] = []
    var totalNumberFailures = 0
    var totalNegationFailures = 0
    var total = 0
    for scope in [EvaluationLanguageMode.english, .mandarin, .mixed] {
      let cases = corpus.cases.filter { $0.language == scope }
      var caseCount = 0
      var observationCount = 0
      var passed = 0
      var failed = 0
      var numberFailures = 0
      var negationFailures = 0
      for item in cases {
        let observations = results.filter { $0.caseID == item.id }
        guard !observations.isEmpty else { continue }
        caseCount += 1
        observationCount += observations.count
        for result in observations {
          let selected = selectedTranscript(result)
          for expectation in item.protectedExpectations {
            if matches(expectation, in: selected) {
              passed += 1
            } else {
              failed += 1
              if expectation.mode == .numericExact {
                numberFailures += 1
              }
              if expectation.mode == .negationExact {
                negationFailures += 1
              }
            }
          }
        }
      }
      guard caseCount > 0 else { continue }
      totalNumberFailures += numberFailures
      totalNegationFailures += negationFailures
      total += passed + failed
      summaries.append(ProtectedExpectationSummary(
        scope: scope,
        caseCount: caseCount,
        observationCount: observationCount,
        total: passed + failed,
        passed: passed,
        failed: failed,
        accuracy: passed + failed == 0
          ? 0
          : Double(passed) / Double(passed + failed),
        numberFailures: numberFailures,
        negationFailures: negationFailures
      ))
    }
    return ProtectedBuild(
      summaries: summaries,
      totalNumberFailures: totalNumberFailures,
      totalNegationFailures: totalNegationFailures,
      total: total
    )
  }

  private static func buildCleanup(
    corpus: EvaluationCorpus,
    results: [UtteranceResult]
  ) -> CleanupBuild {
    var resultsWithCleanup = 0
    var preservationFailures = 0
    var manualReviewRequired = 0
    var manualFailures = 0
    let cases = Dictionary(uniqueKeysWithValues: corpus.cases.map { ($0.id, $0) })
    for result in results where result.cleanedResult != nil {
      resultsWithCleanup += 1
      if let item = cases[result.caseID], let baseline = result.dictionaryBaseline,
        let cleaned = result.cleanedResult
      {
        for expectation in item.protectedExpectations {
          if matches(expectation, in: baseline)
            && !matches(expectation, in: cleaned)
          {
            preservationFailures += 1
          }
        }
      }
      switch result.manualAdjudication?.status {
      case .passed:
        break
      case .failed:
        manualFailures += 1
      case .pending, .none:
        manualReviewRequired += 1
      case .notRequired:
        break
      }
    }
    return CleanupBuild(
      summary: CleanupPreservationSummary(
        resultsWithCleanup: resultsWithCleanup,
        preservationFailures: preservationFailures,
        manualReviewRequired: manualReviewRequired,
        meaningProvenAutomatically: false
      ),
      manualFailures: manualFailures
    )
  }

  private static func buildLatency(
    results: [UtteranceResult]
  ) -> LatencySummary {
    let cold = results.filter { $0.captureTemperature == .cold }
      .map { $0.latency.endToEndMilliseconds }
    let warm = results.filter { $0.captureTemperature == .warm }
      .map { $0.latency.endToEndMilliseconds }
    return LatencySummary(
      coldCount: cold.count,
      warmCount: warm.count,
      coldP50Milliseconds: TranscriptMetrics.percentile(50, values: cold),
      coldP95Milliseconds: TranscriptMetrics.percentile(95, values: cold),
      warmP50Milliseconds: TranscriptMetrics.percentile(50, values: warm),
      warmP95Milliseconds: TranscriptMetrics.percentile(95, values: warm)
    )
  }

  private static func buildResources(
    run: CandidateRun,
    results: [UtteranceResult]
  ) -> ResourceSummary {
    ResourceSummary(
      maximumPeakMemoryBytes: results.map(\.resources.peakMemoryBytes).max() ?? 0,
      maximumIdleMemoryBytes: results.map(\.resources.idleMemoryBytes).max() ?? 0,
      maximumPostUnloadMemoryBytes: run.unloadEvidence.memoryAfterUnloadBytes,
      maximumEnergyImpact: results.map(\.resources.energyImpact).max() ?? 0,
      maximumModelDownloadBytes: results.map(\.resources.modelDownloadBytes).max() ?? 0,
      maximumModelInstalledBytes: results.map(\.resources.modelInstalledBytes).max() ?? 0,
      unloadAttempted: run.unloadEvidence.unloadAttempted,
      unloadSucceeded: run.unloadEvidence.unloadSucceeded,
      thermalStates: results.reduce(into: [ThermalState]()) { states, result in
        if !states.contains(result.resources.thermalState) {
          states.append(result.resources.thermalState)
        }
      },
      observationCount: results.count
    )
  }

  private static func buildStandardComparison(
    corpus: EvaluationCorpus,
    run: CandidateRun,
    languageMetrics: [LanguageMetricSummary],
    protected: ProtectedBuild,
    gate: EvaluationGate
  ) throws -> StandardBuild {
    let specs: [(EvaluationLanguageMode, EvaluationMetricKind)] = [
      (.english, .englishWordErrorRate),
      (.english, .protectedTermAccuracy),
      (.mandarin, .mandarinCharacterErrorRate),
      (.mandarin, .protectedTermAccuracy),
      (.mixed, .englishWordErrorRate),
      (.mixed, .mandarinCharacterErrorRate),
      (.mixed, .protectedTermAccuracy)
    ]
    var comparisonMetrics: [StandardImprovementMetric] = []
    var available: [String: Bool] = [:]
    for (scope, metric) in specs {
      let key = metricKey(scope: scope, metric: metric)
      guard let baseline = run.standardBaseline.metrics.first(where: {
        $0.scope == scope && $0.metric == metric
      }) else {
        throw EvaluationReportError.invalid([
          EvaluationIssue(
            code: "missing_standard_baseline_metric",
            path: "/standardBaseline/metrics",
            message: "Required standard baseline metric is missing."
          )
        ])
      }
      let candidate = candidateValue(
        scope: scope,
        metric: metric,
        languageMetrics: languageMetrics,
        protected: protected
      )
      available[key] = candidate != nil
      let candidateValue = candidate ?? 0
      let improvement = improvement(
        baseline: baseline.value,
        candidate: candidateValue,
        metric: metric
      )
      comparisonMetrics.append(StandardImprovementMetric(
        scope: scope,
        metric: metric,
        baselineValue: baseline.value,
        candidateValue: candidateValue,
        improvement: improvement
      ))
    }
    guard !comparisonMetrics.isEmpty else {
      throw EvaluationReportError.invalid([
        EvaluationIssue(
          code: "missing_standard_baseline_metric",
          path: "/standardBaseline/metrics",
          message: "Standard baseline comparison requires metrics."
        )
      ])
    }
    return StandardBuild(
      summary: StandardComparisonSummary(
        baselineID: run.standardBaseline.identity.baselineID,
        baselineRevision: run.standardBaseline.identity.baselineRevision,
        baselineModelRevision: run.standardBaseline.identity.modelRevision,
        corpusID: run.standardBaseline.identity.corpusID,
        corpusRevision: run.standardBaseline.identity.corpusRevision,
        osVersion: run.standardBaseline.identity.osVersion,
        hardwareModel: run.standardBaseline.identity.hardwareModel,
        architecture: run.standardBaseline.identity.architecture,
        appBuild: run.standardBaseline.identity.appBuild,
        coldObservationCount: run.standardBaseline.identity.coldObservationCount,
        warmObservationCount: run.standardBaseline.identity.warmObservationCount,
        minimumRequiredImprovement: gate.minimumStandardMaterialImprovement,
        metrics: comparisonMetrics
      ),
      available: available
    )
  }

  private static func metricKey(
    scope: EvaluationLanguageMode,
    metric: EvaluationMetricKind
  ) -> String {
    "\(scope.rawValue):\(metric.rawValue)"
  }

  private static func candidateValue(
    scope: EvaluationLanguageMode,
    metric: EvaluationMetricKind,
    languageMetrics: [LanguageMetricSummary],
    protected: ProtectedBuild
  ) -> Double? {
    switch metric {
    case .englishWordErrorRate:
      return languageMetrics.first(where: {
        $0.scope == scope && $0.language == .english
          && $0.metric == .wordErrorRate
      })?.errorRate
    case .mandarinCharacterErrorRate:
      return languageMetrics.first(where: {
        $0.scope == scope && $0.language == .mandarin
          && $0.metric == .characterErrorRate
      })?.errorRate
    case .protectedTermAccuracy:
      return protected.summaries.first(where: { $0.scope == scope })
        .flatMap { $0.total == 0 ? nil : $0.accuracy }
    }
  }

  private static func improvement(
    baseline: Double,
    candidate: Double,
    metric: EvaluationMetricKind
  ) -> Double {
    switch metric {
    case .englishWordErrorRate, .mandarinCharacterErrorRate:
      guard baseline != 0 else { return candidate == 0 ? 0 : -candidate }
      return (baseline - candidate) / baseline
    case .protectedTermAccuracy:
      guard baseline != 0 else { return candidate == 0 ? 0 : candidate }
      return (candidate - baseline) / baseline
    }
  }

  private static func buildOutcomes(
    gate: EvaluationGate,
    languageMetrics: [LanguageMetricSummary],
    protected: ProtectedBuild,
    cleanup: CleanupBuild,
    latency: LatencySummary,
    resources: ResourceSummary,
    standard: StandardBuild,
    run: CandidateRun
  ) -> [GateOutcome] {
    var outcomes: [GateOutcome] = []
    let english = languageMetrics.first(where: {
      $0.scope == .english && $0.language == .english
        && $0.metric == .wordErrorRate
    })
    let mandarin = languageMetrics.first(where: {
      $0.scope == .mandarin && $0.language == .mandarin
        && $0.metric == .characterErrorRate
    })
    let mixedEnglish = languageMetrics.first(where: {
      $0.scope == .mixed && $0.language == .english
        && $0.metric == .wordErrorRate
    })
    let mixedMandarin = languageMetrics.first(where: {
      $0.scope == .mixed && $0.language == .mandarin
        && $0.metric == .characterErrorRate
    })

    outcomes.append(thresholdOutcome(
      id: "english-wer",
      value: english?.errorRate,
      limit: gate.maxEnglishWordErrorRate,
      detail: "English word error rate must not exceed the declared gate."
    ))
    outcomes.append(thresholdOutcome(
      id: "mandarin-cer",
      value: mandarin?.errorRate,
      limit: gate.maxMandarinCharacterErrorRate,
      detail: "Mandarin character error rate must not exceed the declared gate."
    ))
    outcomes.append(compoundOutcome(
      id: "mixed-language",
      values: [mixedEnglish?.errorRate, mixedMandarin?.errorRate],
      limits: [
        gate.maxMixedEnglishWordErrorRate,
        gate.maxMixedMandarinCharacterErrorRate
      ],
      detail: "Mixed language requires both English WER and Mandarin CER to pass."
    ))

    let protectedSummaries = protected.summaries.filter { $0.total > 0 }
    if protected.total == 0 {
      outcomes.append(reviewOutcome(
        id: "protected-terms",
        observed: "no expectation occurrences",
        limit: format(gate.minimumProtectedTermAccuracy),
        detail: "Protected-term evidence is required."
      ))
    } else {
      let accuracy = Double(protected.total - protected.summaries.reduce(0) {
        $0 + $1.failed
      }) / Double(protected.total)
      let passed = protectedSummaries.allSatisfy {
        $0.accuracy >= gate.minimumProtectedTermAccuracy
      }
      outcomes.append(GateOutcome(
        id: "protected-terms",
        passed: passed,
        reviewRequired: false,
        observed: format(accuracy),
        limit: format(gate.minimumProtectedTermAccuracy),
        detail: "Protected-term accuracy is measured per scope."
      ))
    }
    outcomes.append(countOutcome(
      id: "numbers",
      value: protected.totalNumberFailures,
      limit: gate.maximumNumberFailures,
      detail: "Number failures must not exceed the declared gate."
    ))
    outcomes.append(countOutcome(
      id: "negations",
      value: protected.totalNegationFailures,
      limit: gate.maximumNegationFailures,
      detail: "Negation failures must not exceed the declared gate."
    ))

    outcomes.append(standardOutcome(
      id: "standard-improvement-english",
      keys: [
        metricKey(scope: .english, metric: .englishWordErrorRate),
        metricKey(scope: .english, metric: .protectedTermAccuracy)
      ],
      standard: standard,
      minimum: gate.minimumStandardMaterialImprovement
    ))
    outcomes.append(standardOutcome(
      id: "standard-improvement-mandarin",
      keys: [
        metricKey(scope: .mandarin, metric: .mandarinCharacterErrorRate),
        metricKey(scope: .mandarin, metric: .protectedTermAccuracy)
      ],
      standard: standard,
      minimum: gate.minimumStandardMaterialImprovement
    ))
    outcomes.append(standardOutcome(
      id: "standard-improvement-mixed",
      keys: [
        metricKey(scope: .mixed, metric: .englishWordErrorRate),
        metricKey(scope: .mixed, metric: .mandarinCharacterErrorRate),
        metricKey(scope: .mixed, metric: .protectedTermAccuracy)
      ],
      standard: standard,
      minimum: gate.minimumStandardMaterialImprovement
    ))

    let cleanupFailed = cleanup.summary.preservationFailures
      > gate.maximumCleanupPreservationFailures || cleanup.manualFailures > 0
    outcomes.append(GateOutcome(
      id: "cleanup-preservation",
      passed: !cleanupFailed && cleanup.summary.manualReviewRequired == 0,
      reviewRequired: !cleanupFailed && cleanup.summary.manualReviewRequired > 0,
      observed: "failures=\(cleanup.summary.preservationFailures), review=\(cleanup.summary.manualReviewRequired)",
      limit: "failures<=\(gate.maximumCleanupPreservationFailures)",
      detail: cleanup.manualFailures > 0
        ? "Manual adjudication failed for a cleaned observation."
        : "Cleaned output must preserve protected baseline terms and receive manual review."
    ))
    outcomes.append(thresholdOutcome(
      id: "cold-latency",
      value: latency.coldP95Milliseconds,
      limit: gate.maxColdLatencyMilliseconds,
      detail: "Cold p95 end-to-end latency must not exceed the declared gate."
    ))
    outcomes.append(thresholdOutcome(
      id: "warm-latency",
      value: latency.warmP95Milliseconds,
      limit: gate.maxWarmLatencyMilliseconds,
      detail: "Warm p95 end-to-end latency must not exceed the declared gate."
    ))
    outcomes.append(int64Outcome(
      id: "peak-memory",
      value: resources.maximumPeakMemoryBytes,
      limit: gate.maxPeakMemoryBytes,
      detail: "Peak memory must not exceed the declared gate."
    ))
    outcomes.append(int64Outcome(
      id: "idle-memory",
      value: resources.maximumIdleMemoryBytes,
      limit: gate.maxIdleMemoryBytes,
      detail: "Idle memory must not exceed the declared gate."
    ))
    outcomes.append(GateOutcome(
      id: "unload-behavior",
      passed: resources.unloadAttempted && resources.unloadSucceeded,
      reviewRequired: false,
      observed: "attempted=\(resources.unloadAttempted), succeeded=\(resources.unloadSucceeded)",
      limit: "attempted=true, succeeded=true",
      detail: "Release evidence requires an attempted and verified unload."
    ))
    outcomes.append(int64Outcome(
      id: "post-unload-memory",
      value: resources.maximumPostUnloadMemoryBytes,
      limit: gate.maxPostUnloadMemoryBytes,
      detail: "Post-unload memory must not exceed the declared gate."
    ))
    let thermalReview = resources.thermalStates.isEmpty
    let thermalPassed = !thermalReview && resources.thermalStates.allSatisfy {
      gate.allowedThermalStates.contains($0)
    }
    outcomes.append(GateOutcome(
      id: "thermal-state",
      passed: thermalPassed,
      reviewRequired: thermalReview,
      observed: resources.thermalStates.map(\.rawValue).joined(separator: ","),
      limit: gate.allowedThermalStates.map(\.rawValue).joined(separator: ","),
      detail: "Every observed thermal state must be explicitly allowed."
    ))
    outcomes.append(thresholdOutcome(
      id: "energy",
      value: resources.maximumEnergyImpact,
      limit: gate.maxEnergyImpact,
      detail: "Energy impact must not exceed the declared gate."
    ))
    outcomes.append(int64Outcome(
      id: "model-download-size",
      value: resources.maximumModelDownloadBytes,
      limit: gate.maxModelDownloadBytes,
      detail: "Model download size must not exceed the declared gate."
    ))
    outcomes.append(int64Outcome(
      id: "model-installed-size",
      value: resources.maximumModelInstalledBytes,
      limit: gate.maxModelInstalledBytes,
      detail: "Installed model size must not exceed the declared gate."
    ))
    let failureCancellationPassed = run.failureCancellationEvidence.failureExercised
      && run.failureCancellationEvidence.failureFallbackVerified
      && run.failureCancellationEvidence.cancellationExercised
      && run.failureCancellationEvidence.cancellationOutcomeVerified
    outcomes.append(GateOutcome(
      id: "failure-cancellation-behavior",
      passed: failureCancellationPassed,
      reviewRequired: false,
      observed: "failure=\(run.failureCancellationEvidence.failureExercised && run.failureCancellationEvidence.failureFallbackVerified), cancellation=\(run.failureCancellationEvidence.cancellationExercised && run.failureCancellationEvidence.cancellationOutcomeVerified)",
      limit: "failure=true, cancellation=true",
      detail: "Both failure fallback and cancellation behavior must be exercised and verified."
    ))
    outcomes.append(GateOutcome(
      id: "offline-evidence",
      passed: run.offlineEvidence.networkDisabled
        && run.offlineEvidence.networkRequestsObserved == 0
        && !run.offlineEvidence.contentTelemetryObserved,
      reviewRequired: false,
      observed: "networkDisabled=\(run.offlineEvidence.networkDisabled), requests=\(run.offlineEvidence.networkRequestsObserved), contentTelemetry=\(run.offlineEvidence.contentTelemetryObserved)",
      limit: "networkDisabled=true, requests=0, contentTelemetry=false",
      detail: "Inference evidence must remain local and content-telemetry-free."
    ))
    return outcomes
  }

  private static func buildV2Outcomes(
    corpus: EvaluationCorpus,
    gate: EvaluationGate,
    languageMetrics: [LanguageMetricSummary],
    protected: ProtectedBuild,
    cleanup: CleanupBuild,
    latency: LatencySummary,
    resources: ResourceSummary,
    standard: StandardBuild,
    run: CandidateRun
  ) -> [GateOutcome] {
    let stage = run.stage ?? .asrOnly
    let asrApplicable = stage == .asrOnly || stage == .combined
    let cleanupApplicable = stage == .cleanupOnly || stage == .combined
    var outcomes: [GateOutcome] = []

    let english = languageMetrics.first(where: {
      $0.scope == .english && $0.language == .english
        && $0.metric == .wordErrorRate
    })?.errorRate
    let mandarin = languageMetrics.first(where: {
      $0.scope == .mandarin && $0.language == .mandarin
        && $0.metric == .characterErrorRate
    })?.errorRate
    let mixedEnglish = languageMetrics.first(where: {
      $0.scope == .mixed && $0.language == .english
        && $0.metric == .wordErrorRate
    })?.errorRate
    let mixedMandarin = languageMetrics.first(where: {
      $0.scope == .mixed && $0.language == .mandarin
        && $0.metric == .characterErrorRate
    })?.errorRate

    outcomes.append(v2ThresholdOutcome(
      id: "english-wer",
      value: english,
      limit: gate.maxEnglishWordErrorRate,
      applicable: asrApplicable,
      detail: "English word error rate must not exceed the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "mandarin-cer",
      value: mandarin,
      limit: gate.maxMandarinCharacterErrorRate,
      applicable: asrApplicable,
      detail: "Mandarin character error rate must not exceed the declared gate."
    ))
    outcomes.append(v2CompoundOutcome(
      id: "mixed-language",
      values: [mixedEnglish, mixedMandarin],
      limits: [gate.maxMixedEnglishWordErrorRate, gate.maxMixedMandarinCharacterErrorRate],
      applicable: asrApplicable,
      detail: "Mixed language requires both English WER and Mandarin CER to pass."
    ))

    let protectedApplicable = asrApplicable || cleanupApplicable
    if protected.total == 0 {
      outcomes.append(v2ReviewOrNotApplicable(
        id: "protected-terms",
        applicable: protectedApplicable,
        observed: "no expectation occurrences",
        limit: format(gate.minimumProtectedTermAccuracy),
        detail: "Protected-term evidence is required."
      ))
    } else {
      let accuracy = Double(protected.total - protected.summaries.reduce(0) {
        $0 + $1.failed
      }) / Double(protected.total)
      let passed = protected.summaries.filter { $0.total > 0 }.allSatisfy {
        $0.accuracy >= gate.minimumProtectedTermAccuracy
      }
      outcomes.append(GateOutcome(
        id: "protected-terms",
        passed: protectedApplicable && passed,
        reviewRequired: false,
        applicable: protectedApplicable,
        observed: format(accuracy),
        limit: format(gate.minimumProtectedTermAccuracy),
        detail: "Protected-term accuracy is measured per scope."
      ))
    }
    outcomes.append(v2CountOutcome(
      id: "numbers",
      value: protected.totalNumberFailures,
      limit: gate.maximumNumberFailures,
      applicable: protectedApplicable,
      detail: "Number failures must not exceed the declared gate."
    ))
    outcomes.append(v2CountOutcome(
      id: "negations",
      value: protected.totalNegationFailures,
      limit: gate.maximumNegationFailures,
      applicable: protectedApplicable,
      detail: "Negation failures must not exceed the declared gate."
    ))

    let hasSilenceOrNoise = corpus.cases.contains { item in
      item.categories.contains { category in
        category.localizedCaseInsensitiveContains("silence")
          || category.localizedCaseInsensitiveContains("noise")
      } || item.conditions.contains { condition in
        condition.localizedCaseInsensitiveContains("silence")
          || condition.localizedCaseInsensitiveContains("noise")
      }
    }
    outcomes.append(v2BooleanOutcome(
      id: "silence-noise",
      passed: hasSilenceOrNoise && !run.results.isEmpty,
      applicable: hasSilenceOrNoise,
      observed: hasSilenceOrNoise ? "observed" : "not-applicable",
      limit: "case evidence present",
      detail: "Silence and noise cases must remain free of prompt leakage."
    ))

    let claimsProvisional = run.claimedCapabilities.contains(.provisionalResults)
    let provisionalApplicable = claimsProvisional && asrApplicable
    let provisional = run.results.compactMap(\.provisional)
    outcomes.append(v2ThresholdOutcome(
      id: "first-meaningful-partial",
      value: provisional.count == run.results.count
        ? provisional.map(\.firstMeaningfulPartialMilliseconds).max()
        : nil,
      limit: gate.maxFirstMeaningfulPartialMilliseconds,
      applicable: provisionalApplicable,
      detail: "The first meaningful partial is measured from first accepted audio."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "partial-interval",
      value: provisional.count == run.results.count
        ? provisional.map(\.updateIntervalP95Milliseconds).max()
        : nil,
      limit: gate.maxProvisionalUpdateIntervalMilliseconds,
      applicable: provisionalApplicable,
      detail: "Provisional update interval p95 must remain within the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "partial-instability",
      value: provisional.count == run.results.count
        ? provisional.map(\.instabilityRate).max()
        : nil,
      limit: gate.maxProvisionalInstabilityRate,
      applicable: provisionalApplicable,
      detail: "Provisional instability must remain within the declared gate."
    ))

    outcomes.append(v2ThresholdOutcome(
      id: "final-asr-latency",
      value: maximumOptional(run.results.map(\.latency.finalASRMilliseconds)),
      limit: gate.maxFinalASRMilliseconds,
      applicable: asrApplicable,
      detail: "Final ASR latency must remain within the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "cleanup-latency",
      value: run.results.map { $0.latency.cleanupMilliseconds }.max(),
      limit: gate.maxCleanupMilliseconds,
      applicable: cleanupApplicable,
      detail: "Cleanup latency must remain within the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "stop-to-insertion",
      value: maximumOptional(run.results.map(\.latency.stopToInsertionMilliseconds)),
      limit: gate.maxStopToInsertionMilliseconds,
      applicable: stage == .combined,
      detail: "Combined stop-to-insertion latency must remain within the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "cancellation-latency",
      value: run.cancellationResourceEvidence?.requestToControlMilliseconds,
      limit: gate.maxCancellationMilliseconds,
      applicable: true,
      detail: "Cancellation must return control within the declared gate."
    ))

    outcomes.append(v2Int64Outcome(
      id: "peak-memory",
      value: resources.maximumPeakMemoryBytes,
      limit: gate.maxPeakMemoryBytes,
      applicable: true,
      detail: "Peak memory must not exceed the declared gate."
    ))
    outcomes.append(v2Int64Outcome(
      id: "ready-idle-delta",
      value: maximumOptional(run.results.map(\.resources.readyIdleDeltaBytes)),
      limit: gate.maxReadyIdleDeltaBytes,
      applicable: true,
      detail: "Ready-idle memory delta must not exceed the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "unload-duration",
      value: run.unloadEvidence.unloadMilliseconds,
      limit: gate.maxUnloadMilliseconds,
      applicable: true,
      detail: "Unload duration must remain within the declared gate."
    ))
    outcomes.append(v2Int64Outcome(
      id: "post-unload-delta",
      value: run.unloadEvidence.postUnloadDeltaBytes,
      limit: gate.maxPostUnloadDeltaBytes,
      applicable: true,
      detail: "Post-unload memory delta must remain within the declared gate."
    ))
    outcomes.append(v2ThresholdOutcome(
      id: "energy",
      value: resources.maximumEnergyImpact,
      limit: gate.maxEnergyImpact,
      applicable: true,
      detail: "Energy impact must not exceed the declared gate."
    ))
    let thermalPassed = !resources.thermalStates.isEmpty
      && resources.thermalStates.allSatisfy { gate.allowedThermalStates.contains($0) }
    outcomes.append(v2BooleanOutcome(
      id: "thermal",
      passed: thermalPassed,
      applicable: true,
      observed: resources.thermalStates.map(\.rawValue).joined(separator: ","),
      limit: gate.allowedThermalStates.map(\.rawValue).joined(separator: ","),
      detail: "Every observed thermal state must be explicitly allowed."
    ))
    outcomes.append(v2Int64Outcome(
      id: "download-size",
      value: resources.maximumModelDownloadBytes,
      limit: gate.maxModelDownloadBytes,
      applicable: true,
      detail: "Model download size must not exceed the declared gate."
    ))
    outcomes.append(v2Int64Outcome(
      id: "installed-size",
      value: resources.maximumModelInstalledBytes,
      limit: gate.maxModelInstalledBytes,
      applicable: true,
      detail: "Installed model size must not exceed the declared gate."
    ))
    outcomes.append(v2BooleanOutcome(
      id: "offline",
      passed: run.offlineEvidence.networkDisabled
        && run.offlineEvidence.networkRequestsObserved == 0
        && !run.offlineEvidence.contentTelemetryObserved,
      applicable: true,
      observed: "networkDisabled=\(run.offlineEvidence.networkDisabled), requests=\(run.offlineEvidence.networkRequestsObserved), contentTelemetry=\(run.offlineEvidence.contentTelemetryObserved)",
      limit: "networkDisabled=true, requests=0, contentTelemetry=false",
      detail: "Inference evidence must remain local and content-telemetry-free."
    ))

    let reliability = run.reliability
    outcomes.append(v2CountAtLeastOutcome(
      id: "reliability-repetition",
      value: reliability?.repeatedRunCount,
      minimum: gate.minimumRepeatedRunCount,
      applicable: true,
      detail: "Reliability requires at least the declared repeated-run count."
    ))
    let reliabilityFailures = reliability.map {
      $0.crashCount + $0.hangCount + $0.metalOOMCount
        + $0.corruptedModelAcceptedCount
    }
    outcomes.append(v2CountOutcome(
      id: "reliability-failures",
      value: reliabilityFailures ?? 0,
      limit: 0,
      applicable: true,
      detail: "Reliability requires zero crash, hang, OOM, or corrupted-model acceptance failures."
    ))
    let cancellation = run.cancellationResourceEvidence
    outcomes.append(v2BooleanOutcome(
      id: "cancellation-no-insertion",
      passed: cancellation != nil && cancellation?.insertionOccurred == false,
      applicable: true,
      observed: cancellation.map { "insertionOccurred=\($0.insertionOccurred)" } ?? "missing",
      limit: "insertionOccurred=false",
      detail: "Cancellation must prove that no insertion occurred."
    ))
    let cancellationWithinBounds = cancellation.map {
      $0.postCancelUnloadDeltaBytes <= gate.maxPostUnloadDeltaBytes
        && $0.cancelUnloadMilliseconds <= gate.maxUnloadMilliseconds
        && $0.memoryAfterCancelUnloadBytes >= 0
    } ?? false
    outcomes.append(v2BooleanOutcome(
      id: "cancellation-post-unload",
      passed: cancellationWithinBounds,
      applicable: true,
      observed: cancellation.map {
        "delta=\($0.postCancelUnloadDeltaBytes), milliseconds=\($0.cancelUnloadMilliseconds)"
      } ?? "missing",
      limit: "delta<=\(gate.maxPostUnloadDeltaBytes), milliseconds<=\(format(gate.maxUnloadMilliseconds))",
      detail: "Cancellation unload must satisfy post-cancel resource bounds."
    ))

    let supplyChain = run.supplyChain
    let hasSupplyIdentity = supplyChain?.runtimeBinaries.isEmpty == false
      && supplyChain?.runtimeBinaries.allSatisfy {
        !$0.binaryID.isEmpty && !$0.sourceRevision.isEmpty
      } == true
    outcomes.append(v2BooleanOutcome(
      id: "supply-chain-identity",
      passed: hasSupplyIdentity,
      applicable: true,
      observed: hasSupplyIdentity ? "identified" : "missing",
      limit: "runtime binary identity present",
      detail: "Runtime source, build, and binary identities must be recorded."
    ))
    outcomes.append(v2BooleanOutcome(
      id: "supply-chain-redistribution",
      passed: supplyChain?.redistributionDecision == .approved,
      applicable: true,
      observed: supplyChain?.redistributionDecision.rawValue ?? "missing",
      limit: RedistributionDecision.approved.rawValue,
      detail: "Redistribution must be explicitly approved."
    ))
    let removalRollback = supplyChain?.removalPlanRevision.isEmpty == false
      && supplyChain?.rollbackPlanRevision.isEmpty == false
    outcomes.append(v2BooleanOutcome(
      id: "supply-chain-removal-rollback",
      passed: removalRollback,
      applicable: true,
      observed: removalRollback ? "versioned" : "missing",
      limit: "removal and rollback revisions present",
      detail: "Removal and rollback procedures must be versioned."
    ))

    let failureCancellationPassed = run.failureCancellationEvidence.failureExercised
      && run.failureCancellationEvidence.failureFallbackVerified
      && run.failureCancellationEvidence.cancellationExercised
      && run.failureCancellationEvidence.cancellationOutcomeVerified
    outcomes.append(v2BooleanOutcome(
      id: "failure-cancellation",
      passed: failureCancellationPassed,
      applicable: true,
      observed: "failure=\(run.failureCancellationEvidence.failureExercised && run.failureCancellationEvidence.failureFallbackVerified), cancellation=\(run.failureCancellationEvidence.cancellationExercised && run.failureCancellationEvidence.cancellationOutcomeVerified)",
      limit: "failure=true, cancellation=true",
      detail: "Both failure fallback and cancellation behavior must be exercised and verified."
    ))

    outcomes.append(cleanupApplicable
      ? GateOutcome(
        id: "cleanup-preservation",
        passed: cleanup.summary.preservationFailures <= gate.maximumCleanupPreservationFailures
          && cleanup.manualFailures == 0
          && cleanup.summary.manualReviewRequired == 0,
        reviewRequired: cleanup.manualFailures == 0
          && cleanup.summary.manualReviewRequired > 0,
        observed: "failures=\(cleanup.summary.preservationFailures), review=\(cleanup.summary.manualReviewRequired)",
        limit: "failures<=\(gate.maximumCleanupPreservationFailures)",
        detail: "Cleaned output must preserve protected baseline terms and receive manual review."
      )
      : notApplicableOutcome(
        id: "cleanup-preservation",
        detail: "Cleanup preservation is not applicable to an ASR-only run."
      ))

    if asrApplicable {
      outcomes.append(standardOutcome(
        id: "standard-improvement-english",
        keys: [
          metricKey(scope: .english, metric: .englishWordErrorRate),
          metricKey(scope: .english, metric: .protectedTermAccuracy)
        ],
        standard: standard,
        minimum: gate.minimumStandardMaterialImprovement
      ))
      outcomes.append(standardOutcome(
        id: "standard-improvement-mandarin",
        keys: [
          metricKey(scope: .mandarin, metric: .mandarinCharacterErrorRate),
          metricKey(scope: .mandarin, metric: .protectedTermAccuracy)
        ],
        standard: standard,
        minimum: gate.minimumStandardMaterialImprovement
      ))
      outcomes.append(standardOutcome(
        id: "standard-improvement-mixed",
        keys: [
          metricKey(scope: .mixed, metric: .englishWordErrorRate),
          metricKey(scope: .mixed, metric: .mandarinCharacterErrorRate),
          metricKey(scope: .mixed, metric: .protectedTermAccuracy)
        ],
        standard: standard,
        minimum: gate.minimumStandardMaterialImprovement
      ))
    } else {
      for id in [
        "standard-improvement-english",
        "standard-improvement-mandarin",
        "standard-improvement-mixed"
      ] {
        outcomes.append(notApplicableOutcome(
          id: id,
          detail: "ASR baseline comparison is not applicable to a cleanup-only run."
        ))
      }
    }

    let sortedSliceGates = gate.sliceGates.sorted {
      let left = "\($0.sliceID):\($0.metric.rawValue)"
      let right = "\($1.sliceID):\($1.metric.rawValue)"
      return left < right
    }
    for sliceGate in sortedSliceGates {
      let id = "slice:\(sliceGate.sliceID):\(sliceGate.metric.rawValue)"
      let sliceApplicable: Bool
      switch sliceGate.metric {
      case .englishWordErrorRate, .mandarinCharacterErrorRate:
        sliceApplicable = asrApplicable
      case .protectedTermAccuracy:
        sliceApplicable = true
      }
      guard sliceApplicable else {
        outcomes.append(notApplicableOutcome(
          id: id,
          detail: "ASR category slices are not applicable to a cleanup-only run."
        ))
        continue
      }
      let candidate = candidateSliceMetric(
        corpus: corpus,
        results: run.results,
        sliceID: sliceGate.sliceID,
        metric: sliceGate.metric
      )
      let baseline = run.standardBaseline.sliceMetrics.first {
        $0.sliceID == sliceGate.sliceID && $0.metric == sliceGate.metric
      }?.value
      guard let candidate, let baseline else {
        outcomes.append(reviewOutcome(
          id: id,
          observed: "missing",
          limit: format(sliceGate.maximumCandidateValue),
          detail: "Category slice candidate and baseline metrics are both required."
        ))
        continue
      }
      let regression: Double
      switch sliceGate.metric {
      case .protectedTermAccuracy:
        regression = baseline - candidate
      case .englishWordErrorRate, .mandarinCharacterErrorRate:
        regression = candidate - baseline
      }
      outcomes.append(GateOutcome(
        id: id,
        passed: candidate <= sliceGate.maximumCandidateValue
          && regression <= sliceGate.maximumRegressionFromStandard,
        reviewRequired: false,
        observed: "candidate=\(format(candidate)), regression=\(format(regression))",
        limit: "candidate<=\(format(sliceGate.maximumCandidateValue)), regression<=\(format(sliceGate.maximumRegressionFromStandard))",
        detail: "Category slice gates prevent aggregate scores from hiding regressions."
      ))
    }
    return outcomes
  }

  private static func validateV2SliceGates(
    _ gate: EvaluationGate,
    corpus: EvaluationCorpus
  ) -> [EvaluationIssue] {
    var issues: [EvaluationIssue] = []
    let actual = Set(gate.sliceGates.map {
      "\($0.sliceID):\($0.metric.rawValue)"
    })
    for key in requiredV2SliceKeys(corpus) where !actual.contains(key) {
      issues.append(EvaluationIssue(
        code: "missing_slice_gate",
        path: "/sliceGates",
        message: "Missing category slice gate \(key)."
      ))
    }
    return issues
  }

  private static func requiredV2SliceKeys(
    _ corpus: EvaluationCorpus
  ) -> Set<String> {
    var keys: Set<String> = []
    for item in corpus.cases {
      for category in item.categories {
        let prefix = "category:\(category):"
        switch item.language {
        case .english:
          keys.insert(prefix + EvaluationMetricKind.englishWordErrorRate.rawValue)
          keys.insert(prefix + EvaluationMetricKind.protectedTermAccuracy.rawValue)
        case .mandarin:
          keys.insert(prefix + EvaluationMetricKind.mandarinCharacterErrorRate.rawValue)
          keys.insert(prefix + EvaluationMetricKind.protectedTermAccuracy.rawValue)
        case .mixed:
          keys.insert(prefix + EvaluationMetricKind.englishWordErrorRate.rawValue)
          keys.insert(prefix + EvaluationMetricKind.mandarinCharacterErrorRate.rawValue)
          keys.insert(prefix + EvaluationMetricKind.protectedTermAccuracy.rawValue)
        }
      }
    }
    if corpus.cases.contains(where: { $0.language == .mixed }) {
      for category in ["mixed-en-zh", "mixed-zh-en"] {
        let prefix = "category:\(category):"
        keys.insert(prefix + EvaluationMetricKind.englishWordErrorRate.rawValue)
        keys.insert(prefix + EvaluationMetricKind.mandarinCharacterErrorRate.rawValue)
        keys.insert(prefix + EvaluationMetricKind.protectedTermAccuracy.rawValue)
      }
    }
    return keys
  }

  private static func candidateSliceMetric(
    corpus: EvaluationCorpus,
    results: [UtteranceResult],
    sliceID: String,
    metric: EvaluationMetricKind
  ) -> Double? {
    let prefix = "category:"
    guard sliceID.hasPrefix(prefix) else { return nil }
    let category = String(sliceID.dropFirst(prefix.count))
    let cases = corpus.cases.filter { $0.categories.contains(category) }
    guard !cases.isEmpty else { return nil }
    switch metric {
    case .englishWordErrorRate, .mandarinCharacterErrorRate:
      let rates = cases.compactMap { item -> Double? in
        let observations = results.filter { $0.caseID == item.id }
        guard let reference = item.metricReferenceSlices.first(where: {
          $0.language == (metric == .englishWordErrorRate ? .english : .mandarin)
        }), !observations.isEmpty else { return nil }
        var counts = EditCounts(
          substitutions: 0, deletions: 0, insertions: 0, referenceUnits: 0
        )
        for result in observations {
          let hypothesis = result.metricHypothesisSlices.first(where: {
            $0.language == reference.language
          })?.text ?? ""
          let next: EditCounts
          switch metric {
          case .englishWordErrorRate:
            next = TranscriptMetrics.englishWordErrorRate(
              reference: reference.text,
              hypothesis: hypothesis
            )
          case .mandarinCharacterErrorRate:
            next = TranscriptMetrics.mandarinCharacterErrorRate(
              reference: reference.text,
              hypothesis: hypothesis
            )
          case .protectedTermAccuracy:
            return nil
          }
          counts = counts.adding(next)
        }
        return counts.errorRate
      }
      return rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
    case .protectedTermAccuracy:
      var passed = 0
      var total = 0
      for item in cases {
        for result in results where result.caseID == item.id {
          let selected = selectedTranscript(result)
          for expectation in item.protectedExpectations {
            total += 1
            if matches(expectation, in: selected) { passed += 1 }
          }
        }
      }
      return total == 0 ? nil : Double(passed) / Double(total)
    }
  }

  private static func maximumOptional(_ values: [Double?]) -> Double? {
    guard values.allSatisfy({ $0 != nil }) else { return nil }
    return values.compactMap { $0 }.max()
  }

  private static func maximumOptional(_ values: [Int64?]) -> Int64? {
    guard values.allSatisfy({ $0 != nil }) else { return nil }
    return values.compactMap { $0 }.max()
  }

  private static func v2ThresholdOutcome(
    id: String,
    value: Double?,
    limit: Double,
    applicable: Bool,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    return thresholdOutcome(id: id, value: value, limit: limit, detail: detail)
  }

  private static func v2Int64Outcome(
    id: String,
    value: Int64?,
    limit: Int64,
    applicable: Bool,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    guard let value else {
      return reviewOutcome(
        id: id,
        observed: "missing",
        limit: String(limit),
        detail: detail
      )
    }
    return int64Outcome(id: id, value: value, limit: limit, detail: detail)
  }

  private static func v2CountOutcome(
    id: String,
    value: Int,
    limit: Int,
    applicable: Bool,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    return countOutcome(id: id, value: value, limit: limit, detail: detail)
  }

  private static func v2CountAtLeastOutcome(
    id: String,
    value: Int?,
    minimum: Int,
    applicable: Bool,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    guard let value else {
      return reviewOutcome(
        id: id, observed: "missing", limit: ">=\(minimum)", detail: detail
      )
    }
    return GateOutcome(
      id: id,
      passed: value >= minimum,
      reviewRequired: false,
      observed: String(value),
      limit: ">=\(minimum)",
      detail: detail
    )
  }

  private static func v2CompoundOutcome(
    id: String,
    values: [Double?],
    limits: [Double],
    applicable: Bool,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    return compoundOutcome(id: id, values: values, limits: limits, detail: detail)
  }

  private static func v2BooleanOutcome(
    id: String,
    passed: Bool,
    applicable: Bool,
    observed: String,
    limit: String,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    return GateOutcome(
      id: id,
      passed: passed,
      reviewRequired: false,
      observed: observed,
      limit: limit,
      detail: detail
    )
  }

  private static func v2ReviewOrNotApplicable(
    id: String,
    applicable: Bool,
    observed: String,
    limit: String,
    detail: String
  ) -> GateOutcome {
    guard applicable else { return notApplicableOutcome(id: id, detail: detail) }
    return reviewOutcome(id: id, observed: observed, limit: limit, detail: detail)
  }

  private static func notApplicableOutcome(
    id: String,
    detail: String
  ) -> GateOutcome {
    GateOutcome(
      id: id,
      passed: false,
      reviewRequired: false,
      applicable: false,
      observed: "not-applicable",
      limit: "not-applicable",
      detail: detail
    )
  }

  private static func thresholdOutcome(
    id: String,
    value: Double?,
    limit: Double,
    detail: String
  ) -> GateOutcome {
    guard let value else {
      return reviewOutcome(
        id: id,
        observed: "missing",
        limit: format(limit),
        detail: "Required measurement is missing."
      )
    }
    return GateOutcome(
      id: id,
      passed: value <= limit,
      reviewRequired: false,
      observed: format(value),
      limit: format(limit),
      detail: detail
    )
  }

  private static func int64Outcome(
    id: String,
    value: Int64,
    limit: Int64,
    detail: String
  ) -> GateOutcome {
    GateOutcome(
      id: id,
      passed: value <= limit,
      reviewRequired: false,
      observed: String(value),
      limit: String(limit),
      detail: detail
    )
  }

  private static func countOutcome(
    id: String,
    value: Int,
    limit: Int,
    detail: String
  ) -> GateOutcome {
    GateOutcome(
      id: id,
      passed: value <= limit,
      reviewRequired: false,
      observed: String(value),
      limit: String(limit),
      detail: detail
    )
  }

  private static func compoundOutcome(
    id: String,
    values: [Double?],
    limits: [Double],
    detail: String
  ) -> GateOutcome {
    guard values.count == limits.count,
      values.allSatisfy({ $0 != nil })
    else {
      return reviewOutcome(
        id: id,
        observed: "missing component",
        limit: limits.map(format).joined(separator: ","),
        detail: "Every mixed-language component is required."
      )
    }
    let unwrapped = values.compactMap { $0 }
    return GateOutcome(
      id: id,
      passed: zip(unwrapped, limits).allSatisfy { $0 <= $1 },
      reviewRequired: false,
      observed: unwrapped.map(format).joined(separator: ","),
      limit: limits.map(format).joined(separator: ","),
      detail: detail
    )
  }

  private static func standardOutcome(
    id: String,
    keys: [String],
    standard: StandardBuild,
    minimum: Double
  ) -> GateOutcome {
    let metrics = standard.summary.metrics.filter {
      keys.contains(metricKey(scope: $0.scope, metric: $0.metric))
    }
    if metrics.count != keys.count || keys.contains(where: {
      standard.available[$0] != true
    }) {
      return reviewOutcome(
        id: id,
        observed: "missing candidate metric",
        limit: format(minimum),
        detail: "Comparable candidate metrics are required for material improvement."
      )
    }
    let passed = metrics.allSatisfy { $0.improvement >= minimum }
    return GateOutcome(
      id: id,
      passed: passed,
      reviewRequired: false,
      observed: metrics.map { format($0.improvement) }.joined(separator: ","),
      limit: format(minimum),
      detail: "Every required metric in this scope must materially improve over Standard."
    )
  }

  private static func reviewOutcome(
    id: String,
    observed: String,
    limit: String,
    detail: String
  ) -> GateOutcome {
    GateOutcome(
      id: id,
      passed: false,
      reviewRequired: true,
      observed: observed,
      limit: limit,
      detail: detail
    )
  }

  private static func selectedTranscript(_ result: UtteranceResult) -> String {
    result.cleanedResult ?? result.dictionaryBaseline ?? result.asrRaw
  }

  private static func matches(
    _ expectation: ProtectedExpectation,
    in text: String
  ) -> Bool {
    guard !expectation.term.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty else { return false }
    switch expectation.mode {
    case .exactCase:
      if expectation.language == .english {
        return containsBounded(text: text, term: expectation.term)
      }
      return text.range(of: expectation.term, options: [.literal]) != nil
    case .caseInsensitive:
      return containsBounded(
        text: text,
        term: expectation.term,
        caseInsensitive: true
      )
    case .numericExact:
      let expected = decimalRuns(expectation.term)
      let actual = decimalRuns(text)
      guard !expected.isEmpty, actual.count >= expected.count else {
        return false
      }
      if actual.count == expected.count { return actual == expected }
      for start in 0...(actual.count - expected.count) {
        if Array(actual[start..<(start + expected.count)]) == expected {
          return true
        }
      }
      return false
    case .negationExact:
      if expectation.language == .english {
        return containsBounded(
          text: text,
          term: expectation.term,
          caseInsensitive: true
        )
      }
      return text.range(of: expectation.term, options: [.literal]) != nil
    }
  }

  private static func containsBounded(
    text: String,
    term: String,
    caseInsensitive: Bool = false
  ) -> Bool {
    guard !term.isEmpty else { return false }
    let locale = Locale(identifier: "en_US_POSIX")
    let normalizedText = text.precomposedStringWithCompatibilityMapping
    let normalizedTerm = term.precomposedStringWithCompatibilityMapping
    let searchText = caseInsensitive
      ? normalizedText.lowercased(with: locale)
      : normalizedText
    let searchTerm = caseInsensitive
      ? normalizedTerm.lowercased(with: locale)
      : normalizedTerm
    guard !searchText.isEmpty else { return false }
    var start = searchText.startIndex
    while start < searchText.endIndex,
      let range = searchText.range(
        of: searchTerm,
        options: [.literal],
        range: start..<searchText.endIndex
      )
    {
      let beforeIsBoundary = range.lowerBound == searchText.startIndex
        || !isTokenCharacter(searchText[searchText.index(before: range.lowerBound)])
      let afterIsBoundary = range.upperBound == searchText.endIndex
        || !isTokenCharacter(searchText[range.upperBound])
      if beforeIsBoundary && afterIsBoundary { return true }
      if range.lowerBound == searchText.endIndex { break }
      start = searchText.index(after: range.lowerBound)
    }
    return false
  }

  private static func isTokenCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      CharacterSet.letters.contains(scalar)
        || CharacterSet.decimalDigits.contains(scalar)
        || scalar.value == 0x5F
    }
  }

  private static func decimalRuns(_ text: String) -> [String] {
    var runs: [String] = []
    var current = ""
    for scalar in text.unicodeScalars {
      if CharacterSet.decimalDigits.contains(scalar) {
        current.unicodeScalars.append(scalar)
      } else if !current.isEmpty {
        runs.append(current)
        current = ""
      }
    }
    if !current.isEmpty { runs.append(current) }
    return runs
  }

  private static func renderMarkdown(
    corpus _: EvaluationCorpus,
    run: CandidateRun,
    languageMetrics: [LanguageMetricSummary],
    protected: ProtectedBuild,
    standard: StandardComparisonSummary,
    cleanup: CleanupPreservationSummary,
    latency: LatencySummary,
    resources: ResourceSummary,
    artifacts: ArtifactCompletenessSummary,
    offline: OfflineSummary,
    failureCancellation: FailureCancellationSummary,
    outcomes: [GateOutcome],
    releaseDecision: ReleaseDecision
  ) -> String {
    var lines: [String] = []
    if run.syntheticSample {
      lines.append("SAMPLE DATA — NOT MODEL EVIDENCE")
    }
    lines.append("# Fleck Local Dictation Evaluation Report")
    lines.append("")
    lines.append("## Candidate")
    lines.append("")
    lines.append("- candidateID: \(run.candidate.candidateID)")
    lines.append("- runID: \(run.runID)")
    lines.append("- syntheticSample: \(run.syntheticSample)")
    lines.append("- releaseEvidence: \(run.releaseEvidence)")
    lines.append("- stage: \(run.stage?.rawValue ?? "missing")")
    lines.append(
      "- claimedCapabilities: \(run.claimedCapabilities.map(\.rawValue).sorted().joined(separator: ","))"
    )
    lines.append("")
    lines.append("## Language Metrics")
    lines.append("")
    if languageMetrics.isEmpty {
      lines.append("- no language metrics")
    } else {
      for metric in languageMetrics {
        lines.append(
          "- scope=\(metric.scope.rawValue), language=\(metric.language.rawValue), metric=\(metric.metric.rawValue), cases=\(metric.caseCount), observations=\(metric.observationCount), errorRate=\(format(metric.errorRate)), substitutions=\(metric.counts.substitutions), deletions=\(metric.counts.deletions), insertions=\(metric.counts.insertions), referenceUnits=\(metric.counts.referenceUnits)"
        )
      }
    }
    lines.append("")
    lines.append("## Standard Baseline Comparison")
    lines.append("")
    lines.append("- baselineID: \(standard.baselineID)")
    lines.append("- baselineRevision: \(standard.baselineRevision)")
    lines.append("- baselineModelRevision: \(standard.baselineModelRevision)")
    lines.append("- corpusID: \(standard.corpusID)")
    lines.append("- corpusRevision: \(standard.corpusRevision)")
    lines.append("- osVersion: \(standard.osVersion)")
    lines.append("- hardwareModel: \(standard.hardwareModel)")
    lines.append("- architecture: \(standard.architecture)")
    lines.append("- appBuild: \(standard.appBuild)")
    lines.append("- coldObservationCount: \(standard.coldObservationCount)")
    lines.append("- warmObservationCount: \(standard.warmObservationCount)")
    lines.append("- minimumRequiredImprovement: \(format(standard.minimumRequiredImprovement))")
    for metric in standard.metrics {
      lines.append(
        "- scope=\(metric.scope.rawValue), metric=\(metric.metric.rawValue), baseline=\(format(metric.baselineValue)), candidate=\(format(metric.candidateValue)), improvement=\(format(metric.improvement))"
      )
    }
    lines.append("")
    lines.append("## Protected Expectations")
    lines.append("")
    if protected.summaries.isEmpty {
      lines.append("- no protected expectation summaries")
    } else {
      for summary in protected.summaries {
        lines.append(
          "- scope=\(summary.scope.rawValue), cases=\(summary.caseCount), observations=\(summary.observationCount), total=\(summary.total), passed=\(summary.passed), failed=\(summary.failed), accuracy=\(format(summary.accuracy)), numberFailures=\(summary.numberFailures), negationFailures=\(summary.negationFailures)"
        )
      }
    }
    lines.append("")
    lines.append("## Cleanup Preservation")
    lines.append("")
    lines.append("- resultsWithCleanup: \(cleanup.resultsWithCleanup)")
    lines.append("- preservationFailures: \(cleanup.preservationFailures)")
    lines.append("- manualReviewRequired: \(cleanup.manualReviewRequired)")
    lines.append("- meaningProvenAutomatically: \(cleanup.meaningProvenAutomatically)")
    lines.append("- Metrics do not prove semantic fidelity.")
    lines.append("")
    lines.append("## Latency")
    lines.append("")
    lines.append("- coldCount: \(latency.coldCount)")
    lines.append("- coldP50Milliseconds: \(optionalFormat(latency.coldP50Milliseconds))")
    lines.append("- coldP95Milliseconds: \(optionalFormat(latency.coldP95Milliseconds))")
    lines.append("- warmCount: \(latency.warmCount)")
    lines.append("- warmP50Milliseconds: \(optionalFormat(latency.warmP50Milliseconds))")
    lines.append("- warmP95Milliseconds: \(optionalFormat(latency.warmP95Milliseconds))")
    lines.append("")
    lines.append("## Resources")
    lines.append("")
    lines.append("- maximumPeakMemoryBytes: \(resources.maximumPeakMemoryBytes)")
    lines.append("- maximumIdleMemoryBytes: \(resources.maximumIdleMemoryBytes)")
    lines.append("- maximumPostUnloadMemoryBytes: \(resources.maximumPostUnloadMemoryBytes)")
    lines.append("- maximumEnergyImpact: \(format(resources.maximumEnergyImpact))")
    lines.append("- maximumModelDownloadBytes: \(resources.maximumModelDownloadBytes)")
    lines.append("- maximumModelInstalledBytes: \(resources.maximumModelInstalledBytes)")
    lines.append("- unloadAttempted: \(resources.unloadAttempted)")
    lines.append("- unloadSucceeded: \(resources.unloadSucceeded)")
    lines.append("- thermalStates: \(resources.thermalStates.map(\.rawValue).joined(separator: ","))")
    lines.append("- observationCount: \(resources.observationCount)")
    lines.append("")
    lines.append("## Artifacts")
    lines.append("")
    lines.append("- totalObservations: \(artifacts.totalObservations)")
    lines.append("- asrRawObservationCount: \(artifacts.asrRawObservationCount)")
    lines.append("- dictionaryBaselineObservationCount: \(artifacts.dictionaryBaselineObservationCount)")
    lines.append("- cleanedResultObservationCount: \(artifacts.cleanedResultObservationCount)")
    lines.append("")
    lines.append("## Failure and Cancellation")
    lines.append("")
    lines.append("- schemaVersion: \(failureCancellation.schemaVersion)")
    lines.append("- failureExercised: \(failureCancellation.failureExercised)")
    lines.append("- failureFallbackVerified: \(failureCancellation.failureFallbackVerified)")
    lines.append("- failureEvidenceID: \(failureCancellation.failureEvidenceID)")
    lines.append("- failureObservedAt: \(failureCancellation.failureObservedAt)")
    lines.append("- cancellationExercised: \(failureCancellation.cancellationExercised)")
    lines.append("- cancellationOutcomeVerified: \(failureCancellation.cancellationOutcomeVerified)")
    lines.append("- cancellationEvidenceID: \(failureCancellation.cancellationEvidenceID)")
    lines.append("- cancellationObservedAt: \(failureCancellation.cancellationObservedAt)")
    lines.append("- evidenceNote: \(failureCancellation.evidenceNote)")
    lines.append("")
    lines.append("## Offline Evidence")
    lines.append("")
    lines.append("- networkDisabled: \(offline.networkDisabled)")
    lines.append("- networkRequestsObserved: \(offline.networkRequestsObserved)")
    lines.append("- contentTelemetryObserved: \(offline.contentTelemetryObserved)")
    lines.append("- isolationMethod: \(offline.isolationMethod)")
    lines.append("- startedAt: \(offline.startedAt)")
    lines.append("- endedAt: \(offline.endedAt)")
    lines.append("- evidenceNote: \(offline.evidenceNote)")
    lines.append("")
    lines.append("## Gate Outcomes")
    lines.append("")
    for outcome in outcomes {
      lines.append(
        "- \(outcome.id): applicable=\(outcome.applicable), passed=\(outcome.passed), reviewRequired=\(outcome.reviewRequired), observed=\(outcome.observed), limit=\(outcome.limit), detail=\(outcome.detail)"
      )
    }
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    lines.append("- releaseDecision: \(releaseDecision.rawValue)")
    if run.syntheticSample {
      lines.append("- Synthetic sample cannot satisfy a release gate.")
    }
    if !run.syntheticSample && !run.releaseEvidence {
      lines.append("- Release evidence was not asserted; metrics cannot make this run eligible.")
    }
    if cleanup.manualReviewRequired > 0 {
      lines.append("- Manual adjudication is required for cleaned observations.")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private static func optionalFormat(_ value: Double?) -> String {
    value.map(format) ?? "missing"
  }
}
