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
    if run.schemaVersion != 1 {
      issue(&issues, "unsupported_schema_version", "/schemaVersion",
        "Run schemaVersion must be 1.")
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
    return sorted(issues)
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
