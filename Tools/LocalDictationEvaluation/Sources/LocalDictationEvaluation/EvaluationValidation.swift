import Foundation

public struct EvaluationIssue: Codable, Equatable, Sendable {
  public var code: String
  public var path: String
  public var message: String
  public var severity: EvaluationSeverity

  public init(
    code: String,
    path: String,
    message: String,
    severity: EvaluationSeverity = .error
  ) {
    self.code = code
    self.path = path
    self.message = message
    self.severity = severity
  }
}

public enum EvaluationValidator {
  public static func validate(
    corpus: EvaluationCorpus
  ) -> [EvaluationIssue] {
    var issues: [EvaluationIssue] = []
    if corpus.schemaVersion != 1 {
      issue(&issues, "unsupported_schema_version", "/schemaVersion",
        "Corpus schemaVersion must be 1.")
    }
    requireID(corpus.corpusID, "/corpusID", &issues)
    requireID(corpus.revision, "/revision", &issues)
    var seen: Set<String> = []
    for (index, item) in corpus.cases.enumerated() {
      let path = "/cases/\(index)"
      requireID(item.id, "\(path)/id", &issues)
      if !seen.insert(item.id).inserted, !item.id.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty {
        issue(&issues, "duplicate_case_id", "\(path)/id",
          "Case ID is duplicated.")
      }
      if item.categories.isEmpty || item.categories.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        issue(&issues, "missing_category", "\(path)/categories",
          "Each case needs a nonblank category.")
      }
      if item.referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "blank_reference", "\(path)/referenceText",
          "Reference text must be nonblank.")
      }
      if item.spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "blank_spoken_text", "\(path)/spokenText",
          "Spoken text must be nonblank.")
      }
      validateProtectedExpectations(
        item.protectedExpectations,
        caseLanguage: item.language,
        path: "\(path)/protectedExpectations",
        issues: &issues
      )
      validateSlices(
        item.metricReferenceSlices,
        expected: item.language,
        path: "\(path)/metricReferenceSlices",
        issues: &issues
      )
      validateAudio(item, path: path, issues: &issues)
    }
    return sorted(issues)
  }

  public static func validate(
    run: CandidateRun,
    against corpus: EvaluationCorpus
  ) -> [EvaluationIssue] {
    var issues = validate(corpus: corpus)
    requireID(run.runID, "/runID", &issues)
    requireID(run.candidate.candidateID, "/candidate/candidateID", &issues)
    requireID(run.candidate.displayName, "/candidate/displayName", &issues)
    requireID(run.candidate.modelID, "/candidate/modelID", &issues)
    requireID(run.candidate.modelRevision,
      "/candidate/modelRevision", &issues)
    requireID(run.candidate.runtimeName, "/candidate/runtimeName", &issues)
    requireID(run.candidate.runtimeRevision,
      "/candidate/runtimeRevision", &issues)
    requireID(run.candidate.licenseReview, "/candidate/licenseReview", &issues)
    requireID(run.environment.osVersion, "/environment/osVersion", &issues)
    requireID(run.environment.hardwareModel,
      "/environment/hardwareModel", &issues)
    requireID(run.environment.architecture, "/environment/architecture", &issues)
    requireID(run.environment.appBuild, "/environment/appBuild", &issues)
    requireID(run.environment.swiftVersion,
      "/environment/swiftVersion", &issues)
    requireID(run.environment.recordedAt, "/environment/recordedAt", &issues)
    if run.schemaVersion != 1 && run.schemaVersion != 2 {
      issue(&issues, "unsupported_schema_version", "/schemaVersion",
        "Run schemaVersion must be 1 or 2.")
    }
    if run.releaseEvidence && run.schemaVersion != 2 {
      issue(&issues, "release_schema_version", "/schemaVersion",
        "Release evidence requires run schemaVersion 2.")
    }
    if run.corpusID != corpus.corpusID {
      issue(&issues, "corpus_run_mismatch", "/corpusID",
        "Run corpusID does not match the corpus.")
    }
    if run.corpusRevision != corpus.revision {
      issue(&issues, "corpus_run_mismatch", "/corpusRevision",
        "Run corpus revision does not match the corpus.")
    }
    validateStandardBaseline(
      run.standardBaseline,
      run: run,
      corpus: corpus,
      issues: &issues
    )
    validateUnloadEvidence(run.unloadEvidence, issues: &issues)
    validateOfflineEvidence(run.offlineEvidence, issues: &issues)
    validateFailureCancellationEvidence(
      run.failureCancellationEvidence,
      issues: &issues
    )
    if run.offlineEvidence.networkDisabled == false
      || run.offlineEvidence.networkRequestsObserved != 0
    {
      issue(&issues, "offline_network_observed",
        "/offlineEvidence/networkRequestsObserved",
        "Offline evidence does not prove zero network inference.")
    }
    if run.offlineEvidence.contentTelemetryObserved {
      issue(&issues, "content_telemetry",
        "/offlineEvidence/contentTelemetryObserved",
        "Content telemetry was observed.")
    }

    var casesByID: [String: EvaluationCase] = [:]
    for item in corpus.cases where casesByID[item.id] == nil {
      casesByID[item.id] = item
    }
    var seenObservationIDs: Set<String> = []
    var temperaturesByCase: [String: Set<CaptureTemperature>] = [:]
    for (index, result) in run.results.enumerated() {
      let path = "/results/\(index)"
      requireID(result.observationID, "\(path)/observationID", &issues)
      if !seenObservationIDs.insert(result.observationID).inserted {
        issue(&issues, "duplicate_observation_id",
          "\(path)/observationID", "Observation ID is duplicated.")
      }
      guard let item = casesByID[result.caseID] else {
        issue(&issues, "unknown_case_id", "\(path)/caseID",
          "Result case ID is not in the corpus.")
        continue
      }
      if result.language != item.language {
        issue(&issues, "language_mismatch", "\(path)/language",
          "Result language does not match its case.")
      }
      temperaturesByCase[result.caseID, default: []].insert(
        result.captureTemperature
      )
      if result.asrRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "missing_asr_raw", "\(path)/asrRaw",
          "ASR raw must be present.")
      }
      if result.dictionaryBaseline?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty == true {
        issue(&issues, "blank_dictionary_baseline",
          "\(path)/dictionaryBaseline",
          "Dictionary baseline must be nonblank when present.")
      }
      if result.cleanedResult?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty == true {
        issue(&issues, "blank_cleaned_result", "\(path)/cleanedResult",
          "Cleaned result must be nonblank when present.")
      }
      if result.cleanedResult != nil && result.dictionaryBaseline == nil {
        issue(&issues, "cleaned_without_baseline",
          "\(path)/cleanedResult",
          "Cleaned result requires a dictionary baseline.")
      }
      if let adjudication = result.manualAdjudication {
        if result.cleanedResult == nil && adjudication.status == .notRequired {
          // This is the only valid use of notRequired.
        } else if result.cleanedResult != nil
          && adjudication.status == .notRequired
        {
          issue(&issues, "manual_adjudication_not_required_with_cleanup",
            "\(path)/manualAdjudication/status",
            "A cleaned result requires passed, pending, or failed manual adjudication.")
        }
      }
      var expectedOrder: [TranscriptArtifactKind] = [.asrRaw]
      if result.dictionaryBaseline != nil || result.cleanedResult != nil {
        expectedOrder.append(.dictionaryBaseline)
      }
      if result.cleanedResult != nil {
        expectedOrder.append(.cleanedResult)
      }
      if result.artifactOrder != expectedOrder {
        issue(&issues, "invalid_artifact_order", "\(path)/artifactOrder",
          "Artifact order must be ASR raw, dictionary baseline, then cleaned result.")
      }
      validateSlices(
        result.metricHypothesisSlices,
        expected: item.language,
        path: "\(path)/metricHypothesisSlices",
        issues: &issues
      )
      validateMeasurements(result, path: path, issues: &issues)
    }
    for (index, item) in corpus.cases.enumerated() {
      let temperatures = temperaturesByCase[item.id, default: []]
      if !temperatures.contains(.cold) {
        issue(&issues, "missing_cold_observation",
          "/cases/\(index)/observations",
          "Each corpus case requires a cold observation.")
      }
      if !temperatures.contains(.warm) {
        issue(&issues, "missing_warm_observation",
          "/cases/\(index)/observations",
          "Each corpus case requires a warm observation.")
      }
    }
    if run.syntheticSample && run.releaseEvidence {
      issue(&issues, "synthetic_release_evidence", "/releaseEvidence",
        "Synthetic samples cannot claim release evidence.")
    }
    if !run.syntheticSample {
      for (index, item) in corpus.cases.enumerated()
        where !isAdmittedAudio(item)
      {
        issue(&issues, "real_audio_not_admitted",
          "/cases/\(index)/audioAsset",
          "Non-synthetic runs require admitted audio for every corpus case.")
      }
    }
    if run.releaseEvidence {
      if !run.unloadEvidence.unloadAttempted {
        issue(&issues, "unload_not_attempted",
          "/unloadEvidence/unloadAttempted",
          "Release evidence requires an unload attempt.")
      }
      if !run.unloadEvidence.unloadSucceeded {
        issue(&issues, "unload_not_verified",
          "/unloadEvidence/unloadSucceeded",
          "Release evidence requires verified unload behavior.")
      }
    }
    if run.schemaVersion == 2 {
      validateSchemaV2(run: run, against: corpus, issues: &issues)
    }
    return sorted(issues)
  }

  private static func validateSchemaV2(
    run: CandidateRun,
    against corpus: EvaluationCorpus,
    issues: inout [EvaluationIssue]
  ) {
    validateComponents(run, issues: &issues)
    let stage = run.stage
    let claimsProvisional = run.claimedCapabilities.contains(.provisionalResults)
    for (index, result) in run.results.enumerated() {
      let path = "/results/\(index)"
      validateV2Measurements(
        result,
        path: path,
        stage: stage,
        claimsProvisional: claimsProvisional,
        issues: &issues
      )
      validateComponentTotals(
        result.resources,
        components: run.components,
        path: path,
        issues: &issues
      )
    }
    if run.releaseEvidence {
      guard let stage else {
        issue(&issues, "missing_run_stage", "/stage",
          "Release evidence requires a declared run stage.")
        return
      }
      validateStageArtifacts(run, stage: stage, issues: &issues)
      validateSliceMetrics(
        run.standardBaseline.sliceMetrics,
        corpus: corpus,
        issues: &issues
      )
      validateReliability(run.reliability, issues: &issues)
      validateCancellationResourceEvidence(
        run.cancellationResourceEvidence,
        results: run.results,
        issues: &issues
      )
      validateSupplyChain(run.supplyChain, issues: &issues)
      validateUnloadV2(run.unloadEvidence, issues: &issues)
      if stage == .asrOnly || stage == .combined {
        for (index, result) in run.results.enumerated()
          where result.latency.finalASRMilliseconds == nil
        {
          issue(&issues, "missing_final_asr_latency",
            "/results/\(index)/latency/finalASRMilliseconds",
            "ASR stages require final ASR latency evidence.")
        }
      }
      if stage == .combined {
        for (index, result) in run.results.enumerated()
          where result.latency.stopToInsertionMilliseconds == nil
        {
          issue(&issues, "missing_stop_to_insertion_latency",
            "/results/\(index)/latency/stopToInsertionMilliseconds",
            "Combined stages require stop-to-insertion latency evidence.")
        }
      }
      for (index, result) in run.results.enumerated() {
        let resourcePath = "/results/\(index)/resources"
        if result.resources.preLoadMemoryBytes == nil {
          issue(&issues, "missing_ready_idle_evidence",
            "\(resourcePath)/preLoadMemoryBytes",
            "Release evidence requires pre-load memory for ready-idle comparison.")
        }
        if result.resources.readyIdleMemoryBytes == nil {
          issue(&issues, "missing_ready_idle_evidence",
            "\(resourcePath)/readyIdleMemoryBytes",
            "Release evidence requires ready-idle memory evidence.")
        }
        if result.resources.readyIdleDeltaBytes == nil {
          issue(&issues, "missing_ready_idle_evidence",
            "\(resourcePath)/readyIdleDeltaBytes",
            "Release evidence requires ready-idle delta evidence.")
        }
      }
    }
  }

  private static func validateComponents(
    _ run: CandidateRun,
    issues: inout [EvaluationIssue]
  ) {
    var roles: Set<CandidateComponentRole> = []
    for (index, component) in run.components.enumerated() {
      let path = "/components/\(index)"
      if !roles.insert(component.role).inserted {
        issue(&issues, "component_roles", "/components",
          "Each component role must occur at most once.")
      }
      requireID(component.componentID, "\(path)/componentID", &issues)
      requireID(component.modelID, "\(path)/modelID", &issues)
      requireID(component.modelRevision, "\(path)/modelRevision", &issues)
      requireID(component.runtimeName, "\(path)/runtimeName", &issues)
      requireID(component.runtimeRevision, "\(path)/runtimeRevision", &issues)
      requireID(component.runtimeABI, "\(path)/runtimeABI", &issues)
      requireID(component.quantization, "\(path)/quantization", &issues)
      requireID(component.licenseReview, "\(path)/licenseReview", &issues)
      for (field, value) in [
        ("artifactSHA256", component.artifactSHA256),
        ("conversionRecipeSHA256", component.conversionRecipeSHA256),
        ("provenanceRecordSHA256", component.provenanceRecordSHA256)
      ] where value.range(
        of: "^[A-Fa-f0-9]{64}$",
        options: .regularExpression
      ) == nil {
        issue(&issues, "invalid_component_hash", "\(path)/\(field)",
          "Component evidence requires a SHA-256 hash.")
      }
      if component.downloadBytes < 0 {
        issue(&issues, "negative_component_bytes", "\(path)/downloadBytes",
          "Component download bytes must not be negative.")
      }
      if component.installedBytes < 0 {
        issue(&issues, "negative_component_bytes", "\(path)/installedBytes",
          "Component installed bytes must not be negative.")
      }
    }
    guard let stage = run.stage else {
      if run.releaseEvidence {
        issue(&issues, "missing_run_stage", "/stage",
          "Release evidence requires a declared run stage.")
      }
      return
    }
    let asrCount = run.components.filter { $0.role == .asr }.count
    let cleanupCount = run.components.filter { $0.role == .cleanup }.count
    let valid: Bool
    switch stage {
    case .asrOnly:
      valid = asrCount == 1 && cleanupCount == 0
    case .cleanupOnly:
      valid = asrCount == 0 && cleanupCount == 1
    case .combined:
      valid = asrCount == 1 && cleanupCount == 1
    }
    if !valid {
      issue(&issues, "component_roles", "/components",
        "Component cardinality must match the declared run stage.")
    }
  }

  private static func validateV2Measurements(
    _ result: UtteranceResult,
    path: String,
    stage: CandidateRunStage?,
    claimsProvisional: Bool,
    issues: inout [EvaluationIssue]
  ) {
    let optionalLatency: [(String, Double?)] = [
      ("finalASRMilliseconds", result.latency.finalASRMilliseconds),
      ("stopToInsertionMilliseconds", result.latency.stopToInsertionMilliseconds),
      ("cancellationMilliseconds", result.latency.cancellationMilliseconds)
    ]
    for (name, value) in optionalLatency {
      if let value {
        validateFiniteNonnegative(
          value,
          path: "\(path)/latency/\(name)",
          issues: &issues
        )
      }
    }
    let optionalMemory: [(String, Int64?)] = [
      ("preLoadMemoryBytes", result.resources.preLoadMemoryBytes),
      ("readyIdleMemoryBytes", result.resources.readyIdleMemoryBytes),
      ("readyIdleDeltaBytes", result.resources.readyIdleDeltaBytes)
    ]
    for (name, value) in optionalMemory {
      if let value, value < 0 {
        issue(&issues, "negative_measurement",
          "\(path)/resources/\(name)",
          "Measurement must not be negative.")
      }
    }
    if let preLoad = result.resources.preLoadMemoryBytes,
      let readyIdle = result.resources.readyIdleMemoryBytes,
      let delta = result.resources.readyIdleDeltaBytes,
      readyIdle - preLoad != delta
    {
      issue(&issues, "ready_idle_delta_mismatch",
        "\(path)/resources/readyIdleDeltaBytes",
        "Ready-idle delta must equal ready-idle memory minus pre-load memory.")
    }
    if claimsProvisional {
      guard let provisional = result.provisional else {
        issue(&issues, "missing_provisional_evidence", "\(path)/provisional",
          "A provisional-results claim requires provisional evidence.")
        return
      }
      validateFiniteNonnegative(
        provisional.firstMeaningfulPartialMilliseconds,
        path: "\(path)/provisional/firstMeaningfulPartialMilliseconds",
        issues: &issues
      )
      validateFiniteNonnegative(
        provisional.updateIntervalP95Milliseconds,
        path: "\(path)/provisional/updateIntervalP95Milliseconds",
        issues: &issues
      )
      if provisional.firstMeaningfulPartialMilliseconds <= 0
        || provisional.emittedPartialCount <= 0
      {
        issue(&issues, "non_meaningful_partial",
          "\(path)/provisional/firstMeaningfulPartialMilliseconds",
          "The first partial must contain meaningful final-surviving content.")
      }
      if provisional.revisedPartialCount < 0 {
        issue(&issues, "negative_provisional_count",
          "\(path)/provisional/revisedPartialCount",
          "Revised partial count must not be negative.")
      }
      if !provisional.instabilityRate.isFinite
        || !(0...1).contains(provisional.instabilityRate)
      {
        issue(&issues, "invalid_provisional_instability",
          "\(path)/provisional/instabilityRate",
          "Provisional instability must be within 0 and 1.")
      }
    } else if result.provisional != nil {
      issue(&issues, "unclaimed_provisional_evidence", "\(path)/provisional",
        "Provisional evidence requires the provisional-results capability claim.")
    }
    if let stage, stage == .asrOnly, result.cleanedResult != nil {
      issue(&issues, "stage_cleanup_artifact", "\(path)/cleanedResult",
        "ASR-only evidence must not contain a cleanup artifact.")
    }
  }

  private static func validateComponentTotals(
    _ resources: ResourceMeasurement,
    components: [CandidateComponentIdentity],
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    var download = Int64(0)
    var installed = Int64(0)
    for component in components {
      let (nextDownload, downloadOverflow) = download.addingReportingOverflow(
        component.downloadBytes
      )
      let (nextInstalled, installedOverflow) = installed.addingReportingOverflow(
        component.installedBytes
      )
      if downloadOverflow || installedOverflow {
        issue(&issues, "component_byte_totals", "/components",
          "Component byte totals overflow Int64.")
        return
      }
      download = nextDownload
      installed = nextInstalled
    }
    if resources.modelDownloadBytes != download {
      issue(&issues, "component_byte_totals",
        "\(path)/resources/modelDownloadBytes",
        "Model download bytes must equal the component total.")
    }
    if resources.modelInstalledBytes != installed {
      issue(&issues, "component_byte_totals",
        "\(path)/resources/modelInstalledBytes",
        "Model installed bytes must equal the component total.")
    }
  }

  private static func validateStageArtifacts(
    _ run: CandidateRun,
    stage: CandidateRunStage,
    issues: inout [EvaluationIssue]
  ) {
    for (index, result) in run.results.enumerated() {
      switch stage {
      case .asrOnly:
        if result.cleanedResult != nil {
          issue(&issues, "stage_cleanup_artifact", "/results/\(index)/cleanedResult",
            "ASR-only evidence must not contain a cleanup artifact.")
        }
      case .cleanupOnly, .combined:
        if result.cleanedResult == nil {
          issue(&issues, "missing_cleanup_result", "/results/\(index)/cleanedResult",
            "Cleanup stages require a cleaned result for every observation.")
        }
      }
    }
  }

  private static func validateSliceMetrics(
    _ metrics: [EvaluationSliceMetric],
    corpus: EvaluationCorpus,
    issues: inout [EvaluationIssue]
  ) {
    if metrics.isEmpty {
      issue(&issues, "missing_baseline_slice_metrics", "/standardBaseline/sliceMetrics",
        "Release evidence requires category baseline slice metrics.")
      return
    }
    var seen: Set<String> = []
    for (index, metric) in metrics.enumerated() {
      let path = "/standardBaseline/sliceMetrics/\(index)"
      let key = "\(metric.sliceID):\(metric.metric.rawValue)"
      if !seen.insert(key).inserted {
        issue(&issues, "duplicate_baseline_slice_metric", path,
          "Baseline slice metric pairs must be unique.")
      }
      requireID(metric.sliceID, "\(path)/sliceID", &issues)
      if !metric.value.isFinite || metric.value < 0
        || (metric.metric == .protectedTermAccuracy && metric.value > 1)
      {
        issue(&issues, "invalid_baseline_slice_metric", "\(path)/value",
          "Baseline slice metric is outside its valid range.")
      }
    }
    let required = requiredSliceKeys(corpus)
    for key in required where !seen.contains(key) {
      issue(&issues, "missing_baseline_slice_metric",
        "/standardBaseline/sliceMetrics",
        "Missing baseline slice metric \(key).")
    }
    let mixedCategories = Set(corpus.cases.filter { $0.language == .mixed }
      .flatMap(\.categories))
    for direction in ["mixed-en-zh", "mixed-zh-en"]
      where corpus.cases.contains(where: { $0.language == .mixed })
        && !mixedCategories.contains(direction)
    {
      issue(&issues, "missing_mixed_direction_category", "/cases/categories",
        "Mixed-language release evidence requires category:\(direction).")
    }
  }

  private static func requiredSliceKeys(
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

  private static func validateReliability(
    _ reliability: ReliabilityEvidence?,
    issues: inout [EvaluationIssue]
  ) {
    guard let reliability else {
      issue(&issues, "missing_reliability", "/reliability",
        "Release evidence requires repeated lifecycle reliability evidence.")
      return
    }
    let values: [(String, Int)] = [
      ("repeatedRunCount", reliability.repeatedRunCount),
      ("crashCount", reliability.crashCount),
      ("hangCount", reliability.hangCount),
      ("metalOOMCount", reliability.metalOOMCount),
      ("corruptedModelAcceptedCount", reliability.corruptedModelAcceptedCount)
    ]
    for (field, value) in values where value < 0 {
      issue(&issues, "negative_reliability_count", "/reliability/\(field)",
        "Reliability counts must not be negative.")
    }
    if reliability.repeatedRunCount < 50 {
      issue(&issues, "reliability_repetition_count", "/reliability/repeatedRunCount",
        "Reliability evidence requires at least 50 repeated runs.")
    }
    if reliability.crashCount != 0 || reliability.hangCount != 0
      || reliability.metalOOMCount != 0
      || reliability.corruptedModelAcceptedCount != 0
    {
      issue(&issues, "reliability_failures", "/reliability",
        "Reliability evidence requires zero crashes, hangs, Metal OOMs, and corrupted-model acceptance.")
    }
  }

  private static func validateCancellationResourceEvidence(
    _ evidence: CancellationResourceEvidence?,
    results: [UtteranceResult],
    issues: inout [EvaluationIssue]
  ) {
    guard let evidence else {
      issue(&issues, "missing_cancellation_resource_evidence",
        "/cancellationResourceEvidence",
        "Release evidence requires linked cancellation resource evidence.")
      return
    }
    requireID(evidence.observationID,
      "/cancellationResourceEvidence/observationID", &issues)
    let observationIndex = results.firstIndex(where: {
      $0.observationID == evidence.observationID
    })
    if let observationIndex {
      if results[observationIndex].latency.cancellationMilliseconds == nil {
        issue(&issues, "missing_cancellation_timing",
          "/results/\(observationIndex)/latency/cancellationMilliseconds",
          "The linked cancellation observation requires cancellation timing.")
      }
    } else {
      issue(&issues, "cancellation_observation",
        "/cancellationResourceEvidence/observationID",
        "Cancellation evidence must link an observed result.")
    }
    if evidence.insertionOccurred {
      issue(&issues, "cancellation_insertion",
        "/cancellationResourceEvidence/insertionOccurred",
        "Cancellation evidence must prove that no insertion occurred.")
    }
    validateFiniteNonnegative(
      evidence.requestToControlMilliseconds,
      path: "/cancellationResourceEvidence/requestToControlMilliseconds",
      issues: &issues
    )
    validateFiniteNonnegative(
      evidence.cancelUnloadMilliseconds,
      path: "/cancellationResourceEvidence/cancelUnloadMilliseconds",
      issues: &issues
    )
    for (field, value) in [
      ("preCancelMemoryBytes", evidence.preCancelMemoryBytes),
      ("memoryAfterCancelUnloadBytes", evidence.memoryAfterCancelUnloadBytes),
      ("postCancelUnloadDeltaBytes", evidence.postCancelUnloadDeltaBytes)
    ] where value < 0 {
      issue(&issues, "negative_cancellation_memory",
        "/cancellationResourceEvidence/\(field)",
        "Cancellation memory evidence must not be negative.")
    }
    if evidence.preCancelMemoryBytes - evidence.memoryAfterCancelUnloadBytes
      != evidence.postCancelUnloadDeltaBytes
    {
      issue(&issues, "cancellation_memory_delta_mismatch",
        "/cancellationResourceEvidence/postCancelUnloadDeltaBytes",
        "Post-cancel unload delta must equal pre-cancel memory minus memory after unload.")
    }
  }

  private static func validateSupplyChain(
    _ supplyChain: SupplyChainEvidence?,
    issues: inout [EvaluationIssue]
  ) {
    guard let supplyChain else {
      issue(&issues, "missing_supply_chain", "/supplyChain",
        "Release evidence requires structured supply-chain evidence.")
      return
    }
    if supplyChain.runtimeBinaries.isEmpty {
      issue(&issues, "supply_chain_identity", "/supplyChain/runtimeBinaries",
        "At least one runtime binary identity is required.")
    }
    var seen: Set<String> = []
    for (index, binary) in supplyChain.runtimeBinaries.enumerated() {
      let path = "/supplyChain/runtimeBinaries/\(index)"
      requireID(binary.binaryID, "\(path)/binaryID", &issues)
      requireID(binary.sourceRevision, "\(path)/sourceRevision", &issues)
      if !seen.insert(binary.binaryID).inserted {
        issue(&issues, "supply_chain_identity", "\(path)/binaryID",
          "Runtime binary identities must be unique.")
      }
      for field in ["buildRecipeSHA256", "binarySHA256"] {
        let value = field == "buildRecipeSHA256"
          ? binary.buildRecipeSHA256
          : binary.binarySHA256
        if value.range(
          of: "^[A-Fa-f0-9]{64}$",
          options: .regularExpression
        ) == nil {
          issue(&issues, "supply_chain_identity", "\(path)/\(field)",
            "Runtime binary identity requires a SHA-256 hash.")
        }
      }
    }
    if supplyChain.redistributionDecision != .approved {
      issue(&issues, "redistribution_not_approved",
        "/supplyChain/redistributionDecision",
        "Redistribution must be explicitly approved.")
    }
    if supplyChain.attributionNoticeSHA256.range(
      of: "^[A-Fa-f0-9]{64}$",
      options: .regularExpression
    ) == nil {
      issue(&issues, "supply_chain_identity",
        "/supplyChain/attributionNoticeSHA256",
        "Attribution evidence requires a SHA-256 hash.")
    }
    requireID(supplyChain.removalPlanRevision,
      "/supplyChain/removalPlanRevision", &issues)
    requireID(supplyChain.rollbackPlanRevision,
      "/supplyChain/rollbackPlanRevision", &issues)
  }

  private static func validateUnloadV2(
    _ evidence: UnloadEvidence,
    issues: inout [EvaluationIssue]
  ) {
    if let value = evidence.preLoadMemoryBytes, value < 0 {
      issue(&issues, "negative_unload_memory",
        "/unloadEvidence/preLoadMemoryBytes",
        "Pre-load memory must not be negative.")
    }
    if let value = evidence.postUnloadDeltaBytes, value < 0 {
      issue(&issues, "negative_unload_memory",
        "/unloadEvidence/postUnloadDeltaBytes",
        "Post-unload memory delta must not be negative.")
    }
    if let value = evidence.unloadMilliseconds {
      validateFiniteNonnegative(
        value,
        path: "/unloadEvidence/unloadMilliseconds",
        issues: &issues
      )
    } else {
      issue(&issues, "missing_unload_duration",
        "/unloadEvidence/unloadMilliseconds",
        "Release evidence requires unload duration.")
    }
    if evidence.preLoadMemoryBytes == nil {
      issue(&issues, "missing_unload_memory_delta",
        "/unloadEvidence/preLoadMemoryBytes",
        "Release evidence requires pre-load memory for unload comparison.")
    }
    if evidence.postUnloadDeltaBytes == nil {
      issue(&issues, "missing_unload_memory_delta",
        "/unloadEvidence/postUnloadDeltaBytes",
        "Release evidence requires post-unload memory delta.")
    }
  }

  private static func validateFiniteNonnegative(
    _ value: Double,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    if !value.isFinite {
      issue(&issues, "non_finite_measurement", path,
        "Measurement must be finite.")
    } else if value < 0 {
      issue(&issues, "negative_measurement", path,
        "Measurement must not be negative.")
    }
  }

  private static func validateProtectedExpectations(
    _ expectations: [ProtectedExpectation],
    caseLanguage: EvaluationLanguageMode,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let allowedLanguages: Set<EvaluationLanguageMode> =
      caseLanguage == .mixed ? [.english, .mandarin] : [caseLanguage]
    var seenIDs: Set<String> = []
    for (index, expectation) in expectations.enumerated() {
      let itemPath = "\(path)/\(index)"
      let trimmedID = expectation.id.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if trimmedID.isEmpty {
        issue(&issues, "blank_protected_expectation_id",
          "\(itemPath)/id", "Protected expectation ID must be nonblank.")
      } else if !seenIDs.insert(trimmedID).inserted {
        issue(&issues, "duplicate_protected_expectation_id",
          "\(itemPath)/id", "Protected expectation ID is duplicated in its case.")
      }
      if expectation.term.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "blank_protected_term", "\(itemPath)/term",
          "Protected expectation term must be nonblank.")
      }
      if !allowedLanguages.contains(expectation.language) {
        issue(&issues, "protected_language_mismatch",
          "\(itemPath)/language",
          "Protected expectation language is not a member of the case language mode.")
      }
    }
  }

  private static func validateStandardBaseline(
    _ baseline: StandardBaselineEvidence,
    run: CandidateRun,
    corpus: EvaluationCorpus,
    issues: inout [EvaluationIssue]
  ) {
    requireID(baseline.identity.baselineID,
      "/standardBaseline/identity/baselineID", &issues)
    requireID(baseline.identity.baselineRevision,
      "/standardBaseline/identity/baselineRevision", &issues)
    requireID(baseline.identity.engine,
      "/standardBaseline/identity/engine", &issues)
    requireID(baseline.identity.modelRevision,
      "/standardBaseline/identity/modelRevision", &issues)
    requireID(baseline.identity.corpusID,
      "/standardBaseline/identity/corpusID", &issues)
    requireID(baseline.identity.corpusRevision,
      "/standardBaseline/identity/corpusRevision", &issues)
    requireID(baseline.identity.osVersion,
      "/standardBaseline/identity/osVersion", &issues)
    requireID(baseline.identity.hardwareModel,
      "/standardBaseline/identity/hardwareModel", &issues)
    requireID(baseline.identity.architecture,
      "/standardBaseline/identity/architecture", &issues)
    requireID(baseline.identity.appBuild,
      "/standardBaseline/identity/appBuild", &issues)
    requireID(baseline.identity.recordedAt,
      "/standardBaseline/identity/recordedAt", &issues)
    if baseline.identity.corpusID != corpus.corpusID
      || baseline.identity.corpusID != run.corpusID
    {
      issue(&issues, "baseline_corpus_mismatch",
        "/standardBaseline/identity/corpusID",
        "Standard baseline corpusID must match the candidate run and corpus.")
    }
    if baseline.identity.corpusRevision != corpus.revision
      || baseline.identity.corpusRevision != run.corpusRevision
    {
      issue(&issues, "baseline_corpus_mismatch",
        "/standardBaseline/identity/corpusRevision",
        "Standard baseline corpusRevision must match the candidate run and corpus.")
    }
    let environmentFields: [(String, String, String)] = [
      ("osVersion", baseline.identity.osVersion, run.environment.osVersion),
      ("hardwareModel", baseline.identity.hardwareModel, run.environment.hardwareModel),
      ("architecture", baseline.identity.architecture, run.environment.architecture),
      ("appBuild", baseline.identity.appBuild, run.environment.appBuild)
    ]
    for (field, baselineValue, runValue) in environmentFields
      where baselineValue != runValue
    {
      issue(&issues, "baseline_environment_mismatch",
        "/standardBaseline/identity/\(field)",
        "Standard baseline environment must match the candidate run.")
    }
    if baseline.identity.coldObservationCount <= 0 {
      issue(&issues, "invalid_baseline_coverage",
        "/standardBaseline/identity/coldObservationCount",
        "Standard baseline must include positive cold observation coverage.")
    }
    if baseline.identity.warmObservationCount <= 0 {
      issue(&issues, "invalid_baseline_coverage",
        "/standardBaseline/identity/warmObservationCount",
        "Standard baseline must include positive warm observation coverage.")
    }
    let required: Set<String> = [
      "english:englishWordErrorRate",
      "english:protectedTermAccuracy",
      "mandarin:mandarinCharacterErrorRate",
      "mandarin:protectedTermAccuracy",
      "mixed:englishWordErrorRate",
      "mixed:mandarinCharacterErrorRate",
      "mixed:protectedTermAccuracy"
    ]
    var seen: Set<String> = []
    let allowed: Set<String> = [
      "english:englishWordErrorRate",
      "english:protectedTermAccuracy",
      "mandarin:mandarinCharacterErrorRate",
      "mandarin:protectedTermAccuracy",
      "mixed:englishWordErrorRate",
      "mixed:mandarinCharacterErrorRate",
      "mixed:protectedTermAccuracy"
    ]
    for (index, metric) in baseline.metrics.enumerated() {
      let path = "/standardBaseline/metrics/\(index)"
      let key = "\(metric.scope.rawValue):\(metric.metric.rawValue)"
      if !allowed.contains(key) {
        issue(&issues, "invalid_standard_baseline_metric",
          "\(path)/metric",
          "Standard baseline metric is not valid for its scope.")
      }
      if !seen.insert(key).inserted {
        issue(&issues, "duplicate_standard_baseline_metric", path,
          "Standard baseline metric is duplicated.")
      }
      if !metric.value.isFinite {
        issue(&issues, "non_finite_standard_baseline_metric",
          "\(path)/value", "Standard baseline metric must be finite.")
      } else if metric.value < 0
        || (metric.metric == .protectedTermAccuracy && metric.value > 1)
      {
        issue(&issues, "invalid_standard_baseline_metric",
          "\(path)/value", "Standard baseline metric is outside its range.")
      }
    }
    for missing in required.subtracting(seen).sorted() {
      issue(&issues, "missing_standard_baseline_metric",
        "/standardBaseline/metrics",
        "Missing standard baseline metric \(missing).")
    }
  }

  private static func validateUnloadEvidence(
    _ evidence: UnloadEvidence,
    issues: inout [EvaluationIssue]
  ) {
    if evidence.memoryAfterUnloadBytes < 0 {
      issue(&issues, "negative_unload_memory",
        "/unloadEvidence/memoryAfterUnloadBytes",
        "Memory after unload must not be negative.")
    }
    requireID(evidence.observedAt, "/unloadEvidence/observedAt", &issues)
  }

  private static func validateOfflineEvidence(
    _ evidence: OfflineEvidence,
    issues: inout [EvaluationIssue]
  ) {
    requireID(evidence.isolationMethod,
      "/offlineEvidence/isolationMethod", &issues)
    requireID(evidence.startedAt, "/offlineEvidence/startedAt", &issues)
    requireID(evidence.endedAt, "/offlineEvidence/endedAt", &issues)
    requireID(evidence.evidenceNote, "/offlineEvidence/evidenceNote", &issues)
    if evidence.networkRequestsObserved < 0 {
      issue(&issues, "negative_measurement",
        "/offlineEvidence/networkRequestsObserved",
        "Network request count must not be negative.")
    }
    let formatter = ISO8601DateFormatter()
    guard let started = formatter.date(from: evidence.startedAt),
      let ended = formatter.date(from: evidence.endedAt)
    else {
      issue(&issues, "invalid_offline_timestamp",
        "/offlineEvidence",
        "Offline evidence timestamps must be ISO-8601.")
      return
    }
    if ended <= started {
      issue(&issues, "invalid_offline_interval",
        "/offlineEvidence/endedAt",
        "Offline evidence must end after it starts.")
    }
  }

  private static func validateFailureCancellationEvidence(
    _ evidence: FailureCancellationEvidence,
    issues: inout [EvaluationIssue]
  ) {
    if evidence.schemaVersion != 1 {
      issue(&issues, "unsupported_schema_version",
        "/failureCancellationEvidence/schemaVersion",
        "Failure/cancellation evidence schemaVersion must be 1.")
    }
    requireID(evidence.failureEvidenceID,
      "/failureCancellationEvidence/failureEvidenceID", &issues)
    requireID(evidence.failureObservedAt,
      "/failureCancellationEvidence/failureObservedAt", &issues)
    requireID(evidence.cancellationEvidenceID,
      "/failureCancellationEvidence/cancellationEvidenceID", &issues)
    requireID(evidence.cancellationObservedAt,
      "/failureCancellationEvidence/cancellationObservedAt", &issues)
    requireID(evidence.evidenceNote,
      "/failureCancellationEvidence/evidenceNote", &issues)
    let formatter = ISO8601DateFormatter()
    if formatter.date(from: evidence.failureObservedAt) == nil {
      issue(&issues, "invalid_failure_cancellation_timestamp",
        "/failureCancellationEvidence/failureObservedAt",
        "Failure evidence timestamp must be ISO-8601.")
    }
    if formatter.date(from: evidence.cancellationObservedAt) == nil {
      issue(&issues, "invalid_failure_cancellation_timestamp",
        "/failureCancellationEvidence/cancellationObservedAt",
        "Cancellation evidence timestamp must be ISO-8601.")
    }
  }

  private static func validateAudio(
    _ item: EvaluationCase,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let hasAsset = hasNonblankAudioAsset(item)
    if !hasAsset {
      if item.audioProvenance != nil {
        issue(&issues, "audio_provenance", "\(path)/audioProvenance",
          "Audio provenance requires an audio asset.")
      }
      if item.audioConsent != nil {
        issue(&issues, "audio_consent", "\(path)/audioConsent",
          "Audio consent requires an audio asset.")
      }
      return
    }
    let validProvenance: Bool = {
      guard let provenance = item.audioProvenance,
      provenance.approved,
      provenance.assetSHA256.range(
        of: "^[A-Fa-f0-9]{64}$",
        options: .regularExpression
      ) != nil,
      !provenance.source.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !provenance.license.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !provenance.privacyReview.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !provenance.revocationProcess.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      else {
        return false
      }
      return true
    }()
    if !validProvenance {
      issue(&issues, "audio_provenance", "\(path)/audioProvenance",
        "Audio provenance is not approved, hashed, licensed, and privacy-reviewed.")
    }
    let validConsent: Bool = {
      guard let consent = item.audioConsent,
        consent.status == .approved,
        !consent.recordID.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty,
        consent.reviewer?.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty == false,
        consent.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty == false
      else {
        return false
      }
      return true
    }()
    if !validConsent {
      issue(&issues, "audio_consent", "\(path)/audioConsent",
        "Admitted audio requires approved, recorded consent.")
    }
  }

  private static func isAdmittedAudio(_ item: EvaluationCase) -> Bool {
    var copy: [EvaluationIssue] = []
    validateAudio(item, path: "/case", issues: &copy)
    return hasNonblankAudioAsset(item) && copy.isEmpty
  }

  private static func hasNonblankAudioAsset(_ item: EvaluationCase) -> Bool {
    item.audioAsset?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty == false
  }

  private static func validateSlices(
    _ slices: [EvaluationTextSlice],
    expected: EvaluationLanguageMode,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let expectedLanguages: [EvaluationLanguageMode] =
      expected == .mixed ? [.english, .mandarin] : [expected]
    let actualLanguages = slices.map(\.language)
    if slices.isEmpty {
      issue(&issues, "missing_language", path,
        "At least one language-specific metric slice is required.")
      return
    }
    if actualLanguages != expectedLanguages {
      issue(&issues, "missing_language", path,
        "Metric slices must cover the declared language mode.")
    }
    if slices.contains(where: {
      $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issue(&issues, "invalid_metric_slices", path,
        "Metric slices must contain the language-specific nonblank text in order.")
    }
  }

  private static func validateMeasurements(
    _ result: UtteranceResult,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let latency: [(String, Double)] = [
      ("asrMilliseconds", result.latency.asrMilliseconds),
      ("cleanupMilliseconds", result.latency.cleanupMilliseconds),
      ("endToEndMilliseconds", result.latency.endToEndMilliseconds)
    ]
    for (name, value) in latency {
      if !value.isFinite {
        issue(&issues, "non_finite_measurement",
          "\(path)/latency/\(name)", "Measurement must be finite.")
      } else if value < 0 {
        issue(&issues, "negative_measurement",
          "\(path)/latency/\(name)", "Measurement must not be negative.")
      }
    }
    if let cold = result.latency.coldLoadMilliseconds {
      if !cold.isFinite {
        issue(&issues, "non_finite_measurement",
          "\(path)/latency/coldLoadMilliseconds",
          "Measurement must be finite.")
      } else if cold < 0 {
        issue(&issues, "negative_measurement",
          "\(path)/latency/coldLoadMilliseconds",
          "Measurement must not be negative.")
      }
    }
    switch result.captureTemperature {
    case .cold:
      if result.latency.coldLoadMilliseconds == nil {
        issue(&issues, "missing_cold_load_measurement",
          "\(path)/latency/coldLoadMilliseconds",
          "Cold captures require a finite cold-load measurement.")
      }
    case .warm:
      if result.latency.coldLoadMilliseconds != nil {
        issue(&issues, "warm_cold_load_present",
          "\(path)/latency/coldLoadMilliseconds",
          "Warm captures must not include a cold-load measurement.")
      }
    }
    if !result.resources.energyImpact.isFinite {
      issue(&issues, "non_finite_measurement",
        "\(path)/resources/energyImpact", "Measurement must be finite.")
    } else if result.resources.energyImpact < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/energyImpact", "Measurement must not be negative.")
    }
    if result.resources.peakMemoryBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/peakMemoryBytes",
        "Measurement must not be negative.")
    }
    if result.resources.idleMemoryBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/idleMemoryBytes",
        "Measurement must not be negative.")
    }
    if result.resources.modelDownloadBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/modelDownloadBytes",
        "Measurement must not be negative.")
    }
    if result.resources.modelInstalledBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/modelInstalledBytes",
        "Measurement must not be negative.")
    }
  }

  private static func requireID(
    _ value: String,
    _ path: String,
    _ issues: inout [EvaluationIssue]
  ) {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issue(&issues, "blank_id", path, "Stable ID must be nonblank.")
    }
  }

  private static func issue(
    _ issues: inout [EvaluationIssue],
    _ code: String,
    _ path: String,
    _ message: String
  ) {
    issues.append(EvaluationIssue(code: code, path: path, message: message))
  }

  private static func sorted(
    _ issues: [EvaluationIssue]
  ) -> [EvaluationIssue] {
    issues.sorted {
      if $0.path == $1.path { return $0.code < $1.code }
      return $0.path < $1.path
    }
  }
}
