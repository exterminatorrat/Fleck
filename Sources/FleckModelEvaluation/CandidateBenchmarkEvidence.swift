import Foundation

public enum CandidateBenchmarkClaimScope: String, Codable, Equatable, Sendable {
  case candidateBenchmark
}

public enum CandidateBenchmarkEvidenceClass: String, Codable, Comparable, Equatable, Hashable, Sendable {
  case synthetic
  case publicHuman
  case publicHumanComposite
  case operatorLiveHuman

  public static func < (
    lhs: CandidateBenchmarkEvidenceClass,
    rhs: CandidateBenchmarkEvidenceClass
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum CandidateBenchmarkLanguage: String, Codable, Equatable, Hashable, Sendable {
  case english
  case mandarin
  case mixed
  case none
}

public enum CandidateBenchmarkCaseOutcome: String, Codable, Equatable, Sendable {
  case transcribed
  case silence
  case cancelled
}

public enum CandidateBenchmarkCancellationOutcome: String, Codable, Equatable, Sendable {
  case notCancelled
  case cooperative
  case forced
}

public enum CandidateBenchmarkLifecycleOutcome: String, Codable, Equatable, Sendable {
  case succeeded
  case failed
  case cancelled
}

public typealias CandidateBenchmarkProtectedExpectation = ModelEvaluationProtectedExpectation

public struct CandidateBenchmarkCandidate: Codable, Equatable, Sendable {
  public let modelID: String
  public let modelRevision: String
  public let runtimeID: String
  public let runtimeRevision: String
  public let quantization: String
  public let license: String

  public init(
    modelID: String,
    modelRevision: String,
    runtimeID: String,
    runtimeRevision: String,
    quantization: String,
    license: String
  ) {
    self.modelID = modelID
    self.modelRevision = modelRevision
    self.runtimeID = runtimeID
    self.runtimeRevision = runtimeRevision
    self.quantization = quantization
    self.license = license
  }
}

public struct CandidateBenchmarkArtifactReceipt: Codable, Equatable, Sendable {
  public let id: String
  public let revision: String
  public let sha256: String
  public let byteCount: Int64

  public init(id: String, revision: String, sha256: String, byteCount: Int64) {
    self.id = id
    self.revision = revision
    self.sha256 = sha256
    self.byteCount = byteCount
  }
}

public struct CandidateBenchmarkInstalledFile: Codable, Equatable, Sendable {
  public let path: String
  public let sha256: String
  public let byteCount: Int64

  public init(path: String, sha256: String, byteCount: Int64) {
    self.path = path
    self.sha256 = sha256
    self.byteCount = byteCount
  }
}

public struct CandidateBenchmarkArtifacts: Codable, Equatable, Sendable {
  public let archiveReceipt: CandidateBenchmarkArtifactReceipt
  public let artifactReceipt: CandidateBenchmarkArtifactReceipt
  public let installedFiles: [CandidateBenchmarkInstalledFile]
  public let totalInstalledBytes: Int64

  public init(
    archiveReceipt: CandidateBenchmarkArtifactReceipt,
    artifactReceipt: CandidateBenchmarkArtifactReceipt,
    installedFiles: [CandidateBenchmarkInstalledFile],
    totalInstalledBytes: Int64
  ) {
    self.archiveReceipt = archiveReceipt
    self.artifactReceipt = artifactReceipt
    self.installedFiles = installedFiles
    self.totalInstalledBytes = totalInstalledBytes
  }
}

public struct CandidateBenchmarkHardware: Codable, Equatable, Sendable {
  public let hwModel: String
  public let chip: String
  public let architecture: String
  public let memoryBytes: Int64
  public let osBuild: String

  public init(
    hwModel: String,
    chip: String,
    architecture: String,
    memoryBytes: Int64,
    osBuild: String
  ) {
    self.hwModel = hwModel
    self.chip = chip
    self.architecture = architecture
    self.memoryBytes = memoryBytes
    self.osBuild = osBuild
  }
}

public struct CandidateBenchmarkCorpusCaseBinding: Codable, Equatable, Sendable {
  public let caseID: String
  public let audioSHA256: String

  public init(caseID: String, audioSHA256: String) {
    self.caseID = caseID
    self.audioSHA256 = audioSHA256
  }
}

public struct CandidateBenchmarkCorpus: Codable, Equatable, Sendable {
  public let manifestID: String
  public let revision: String
  public let license: String
  public let caseBindings: [CandidateBenchmarkCorpusCaseBinding]

  public init(
    manifestID: String,
    revision: String,
    license: String,
    caseBindings: [CandidateBenchmarkCorpusCaseBinding]
  ) {
    self.manifestID = manifestID
    self.revision = revision
    self.license = license
    self.caseBindings = caseBindings
  }
}

public struct CandidateBenchmarkPrivacy: Codable, Equatable, Sendable {
  public let policy: String
  public let mechanism: String
  public let enforced: Bool
  public let claimsVerifiedOffline: Bool
  public let unexpectedConnectionCount: Int

  public init(
    policy: String,
    mechanism: String,
    enforced: Bool,
    claimsVerifiedOffline: Bool,
    unexpectedConnectionCount: Int
  ) {
    self.policy = policy
    self.mechanism = mechanism
    self.enforced = enforced
    self.claimsVerifiedOffline = claimsVerifiedOffline
    self.unexpectedConnectionCount = unexpectedConnectionCount
  }

  public var unexpectedNetworkConnectionCount: Int {
    unexpectedConnectionCount
  }
}

public struct CandidateBenchmarkCodeSwitchSpan: Codable, Equatable, Sendable {
  public let startMilliseconds: Double
  public let endMilliseconds: Double
  public let language: CandidateBenchmarkLanguage
  public let matched: Bool

  public init(
    startMilliseconds: Double,
    endMilliseconds: Double,
    language: CandidateBenchmarkLanguage,
    matched: Bool
  ) {
    self.startMilliseconds = startMilliseconds
    self.endMilliseconds = endMilliseconds
    self.language = language
    self.matched = matched
  }
}

public struct CandidateBenchmarkTiming: Codable, Equatable, Sendable {
  public let fileDecodeMilliseconds: Double
  public let firstPartialMilliseconds: Double?
  public let isCold: Bool

  public init(
    fileDecodeMilliseconds: Double,
    firstPartialMilliseconds: Double? = nil,
    isCold: Bool
  ) {
    self.fileDecodeMilliseconds = fileDecodeMilliseconds
    self.firstPartialMilliseconds = firstPartialMilliseconds
    self.isCold = isCold
  }
}

public struct CandidateBenchmarkAccuracyEvidence: Codable, Equatable, Sendable {
  public let englishWER: Double?
  public let mandarinCER: Double?
  public let mixedMER: Double?
  public let codeSwitchSpanAccuracy: Double?
  public let protectedViolationCount: Int

  public init(
    englishWER: Double?,
    mandarinCER: Double?,
    mixedMER: Double?,
    codeSwitchSpanAccuracy: Double?,
    protectedViolationCount: Int
  ) {
    self.englishWER = englishWER
    self.mandarinCER = mandarinCER
    self.mixedMER = mixedMER
    self.codeSwitchSpanAccuracy = codeSwitchSpanAccuracy
    self.protectedViolationCount = protectedViolationCount
  }
}

public struct CandidateBenchmarkLatencyDistribution: Codable, Equatable, Sendable {
  public let coldP50Milliseconds: Double?
  public let coldP95Milliseconds: Double?
  public let warmP50Milliseconds: Double?
  public let warmP95Milliseconds: Double?

  public init(
    coldP50Milliseconds: Double?,
    coldP95Milliseconds: Double?,
    warmP50Milliseconds: Double?,
    warmP95Milliseconds: Double?
  ) {
    self.coldP50Milliseconds = coldP50Milliseconds
    self.coldP95Milliseconds = coldP95Milliseconds
    self.warmP50Milliseconds = warmP50Milliseconds
    self.warmP95Milliseconds = warmP95Milliseconds
  }
}

public struct CandidateBenchmarkLifecycleSummary: Codable, Equatable, Sendable {
  public let loadSucceeded: Bool
  public let inferSucceeded: Bool
  public let unloadSucceeded: Bool
  public let reloadSucceeded: Bool
  public let allSucceeded: Bool

  public init(
    loadSucceeded: Bool,
    inferSucceeded: Bool,
    unloadSucceeded: Bool,
    reloadSucceeded: Bool,
    allSucceeded: Bool
  ) {
    self.loadSucceeded = loadSucceeded
    self.inferSucceeded = inferSucceeded
    self.unloadSucceeded = unloadSucceeded
    self.reloadSucceeded = reloadSucceeded
    self.allSucceeded = allSucceeded
  }
}

public struct CandidateBenchmarkAggregateEvidence: Codable, Equatable, Sendable {
  public let accuracy: CandidateBenchmarkAccuracyEvidence
  public let latency: CandidateBenchmarkLatencyDistribution
  public let fileDecodeRTF: Double?
  public let peakResidentBytes: Int64
  public let peakPhysicalFootprintBytes: Int64
  public let totalStorageBytes: Int64
  public let lifecycleSummary: CandidateBenchmarkLifecycleSummary

  public init(
    accuracy: CandidateBenchmarkAccuracyEvidence,
    latency: CandidateBenchmarkLatencyDistribution,
    fileDecodeRTF: Double?,
    peakResidentBytes: Int64,
    peakPhysicalFootprintBytes: Int64,
    totalStorageBytes: Int64,
    lifecycleSummary: CandidateBenchmarkLifecycleSummary
  ) {
    self.accuracy = accuracy
    self.latency = latency
    self.fileDecodeRTF = fileDecodeRTF
    self.peakResidentBytes = peakResidentBytes
    self.peakPhysicalFootprintBytes = peakPhysicalFootprintBytes
    self.totalStorageBytes = totalStorageBytes
    self.lifecycleSummary = lifecycleSummary
  }
}

public struct CandidateBenchmarkGate: Codable, Equatable, Sendable {
  public let automatedCandidatePass: Bool
  public let failureReasons: [String]
  public let releaseAdmitted: Bool

  public init(
    automatedCandidatePass: Bool,
    failureReasons: [String],
    releaseAdmitted: Bool
  ) {
    self.automatedCandidatePass = automatedCandidatePass
    self.failureReasons = failureReasons
    self.releaseAdmitted = releaseAdmitted
  }
}

public struct CandidateBenchmarkCancellation: Codable, Equatable, Sendable {
  public let outcome: CandidateBenchmarkCancellationOutcome
  public let noLateOutput: Bool

  public init(outcome: CandidateBenchmarkCancellationOutcome, noLateOutput: Bool) {
    self.outcome = outcome
    self.noLateOutput = noLateOutput
  }
}

public struct CandidateBenchmarkCase: Codable, Equatable, Sendable {
  public let id: String
  public let language: CandidateBenchmarkLanguage
  public let sourceClass: CandidateBenchmarkEvidenceClass
  public let audioSHA256: String
  public let audioDurationMilliseconds: Double
  public let reference: String
  public let hypothesis: String
  public let protectedExpectations: [CandidateBenchmarkProtectedExpectation]
  public let claimsNaturalCodeSwitch: Bool
  public let codeSwitchSpans: [CandidateBenchmarkCodeSwitchSpan]
  public let captureTemperature: Double
  public let timing: CandidateBenchmarkTiming
  public let peakResidentBytes: Int64
  public let peakPhysicalFootprintBytes: Int64
  public let outcome: CandidateBenchmarkCaseOutcome
  public let cancellation: CandidateBenchmarkCancellation

  public init(
    id: String,
    language: CandidateBenchmarkLanguage,
    sourceClass: CandidateBenchmarkEvidenceClass,
    audioSHA256: String,
    audioDurationMilliseconds: Double,
    reference: String,
    hypothesis: String,
    protectedExpectations: [CandidateBenchmarkProtectedExpectation],
    claimsNaturalCodeSwitch: Bool,
    codeSwitchSpans: [CandidateBenchmarkCodeSwitchSpan],
    captureTemperature: Double,
    timing: CandidateBenchmarkTiming,
    peakResidentBytes: Int64,
    peakPhysicalFootprintBytes: Int64,
    outcome: CandidateBenchmarkCaseOutcome,
    cancellation: CandidateBenchmarkCancellation
  ) {
    self.id = id
    self.language = language
    self.sourceClass = sourceClass
    self.audioSHA256 = audioSHA256
    self.audioDurationMilliseconds = audioDurationMilliseconds
    self.reference = reference
    self.hypothesis = hypothesis
    self.protectedExpectations = protectedExpectations
    self.claimsNaturalCodeSwitch = claimsNaturalCodeSwitch
    self.codeSwitchSpans = codeSwitchSpans
    self.captureTemperature = captureTemperature
    self.timing = timing
    self.peakResidentBytes = peakResidentBytes
    self.peakPhysicalFootprintBytes = peakPhysicalFootprintBytes
    self.outcome = outcome
    self.cancellation = cancellation
  }
}

public struct CandidateBenchmarkLifecyclePhase: Codable, Equatable, Sendable {
  public let outcome: CandidateBenchmarkLifecycleOutcome
  public let durationMilliseconds: Double
  public let peakResidentBytes: Int64
  public let peakPhysicalFootprintBytes: Int64

  public init(
    outcome: CandidateBenchmarkLifecycleOutcome,
    durationMilliseconds: Double,
    peakResidentBytes: Int64,
    peakPhysicalFootprintBytes: Int64
  ) {
    self.outcome = outcome
    self.durationMilliseconds = durationMilliseconds
    self.peakResidentBytes = peakResidentBytes
    self.peakPhysicalFootprintBytes = peakPhysicalFootprintBytes
  }
}

public struct CandidateBenchmarkLifecycle: Codable, Equatable, Sendable {
  public let load: CandidateBenchmarkLifecyclePhase
  public let infer: CandidateBenchmarkLifecyclePhase
  public let unload: CandidateBenchmarkLifecyclePhase
  public let reload: CandidateBenchmarkLifecyclePhase

  public init(
    load: CandidateBenchmarkLifecyclePhase,
    infer: CandidateBenchmarkLifecyclePhase,
    unload: CandidateBenchmarkLifecyclePhase,
    reload: CandidateBenchmarkLifecyclePhase
  ) {
    self.load = load
    self.infer = infer
    self.unload = unload
    self.reload = reload
  }
}

public enum CandidateBenchmarkEvidenceError: Error, Equatable, Sendable, CustomStringConvertible {
  case unsupportedSchemaVersion(Int)
  case invalid(String)

  public var description: String {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported candidate benchmark evidence schema version: \(version)."
    case .invalid(let reason):
      return "Invalid candidate benchmark evidence: \(reason)."
    }
  }
}

public struct CandidateBenchmarkEvidence: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let runID: String
  public let claimScope: CandidateBenchmarkClaimScope
  public let evidenceClasses: [CandidateBenchmarkEvidenceClass]
  public let candidate: CandidateBenchmarkCandidate
  public let artifacts: CandidateBenchmarkArtifacts
  public let hardware: CandidateBenchmarkHardware
  public let corpus: CandidateBenchmarkCorpus
  public let privacy: CandidateBenchmarkPrivacy
  public let aggregate: CandidateBenchmarkAggregateEvidence
  public let gate: CandidateBenchmarkGate
  public let cases: [CandidateBenchmarkCase]
  public let lifecycle: CandidateBenchmarkLifecycle

  public init(
    schemaVersion: Int,
    runID: String,
    claimScope: CandidateBenchmarkClaimScope,
    evidenceClasses: [CandidateBenchmarkEvidenceClass],
    candidate: CandidateBenchmarkCandidate,
    artifacts: CandidateBenchmarkArtifacts,
    hardware: CandidateBenchmarkHardware,
    corpus: CandidateBenchmarkCorpus,
    privacy: CandidateBenchmarkPrivacy,
    aggregate: CandidateBenchmarkAggregateEvidence,
    gate: CandidateBenchmarkGate,
    cases: [CandidateBenchmarkCase],
    lifecycle: CandidateBenchmarkLifecycle
  ) throws {
    self.schemaVersion = schemaVersion
    self.runID = runID
    self.claimScope = claimScope
    self.evidenceClasses = evidenceClasses
    self.candidate = candidate
    self.artifacts = artifacts
    self.hardware = hardware
    self.corpus = corpus
    self.privacy = privacy
    self.aggregate = aggregate
    self.gate = gate
    self.cases = cases
    self.lifecycle = lifecycle
    try validate()
  }

  public func validated() throws -> CandidateBenchmarkEvidence {
    try validate()
    return self
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
      runID: try container.decode(String.self, forKey: .runID),
      claimScope: try container.decode(CandidateBenchmarkClaimScope.self, forKey: .claimScope),
      evidenceClasses: try container.decode([CandidateBenchmarkEvidenceClass].self, forKey: .evidenceClasses),
      candidate: try container.decode(CandidateBenchmarkCandidate.self, forKey: .candidate),
      artifacts: try container.decode(CandidateBenchmarkArtifacts.self, forKey: .artifacts),
      hardware: try container.decode(CandidateBenchmarkHardware.self, forKey: .hardware),
      corpus: try container.decode(CandidateBenchmarkCorpus.self, forKey: .corpus),
      privacy: try container.decode(CandidateBenchmarkPrivacy.self, forKey: .privacy),
      aggregate: try container.decode(CandidateBenchmarkAggregateEvidence.self, forKey: .aggregate),
      gate: try container.decode(CandidateBenchmarkGate.self, forKey: .gate),
      cases: try container.decode([CandidateBenchmarkCase].self, forKey: .cases),
      lifecycle: try container.decode(CandidateBenchmarkLifecycle.self, forKey: .lifecycle)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case runID
    case claimScope
    case evidenceClasses
    case candidate
    case artifacts
    case hardware
    case corpus
    case privacy
    case aggregate
    case gate
    case cases
    case lifecycle
  }

  private func validate() throws {
    guard schemaVersion == 2 else {
      throw CandidateBenchmarkEvidenceError.unsupportedSchemaVersion(schemaVersion)
    }
    guard !evidenceClasses.isEmpty else {
      throw invalid("evidenceClasses must not be empty")
    }
    guard evidenceClasses == evidenceClasses.sorted() else {
      throw invalid("evidenceClasses must be sorted")
    }
    guard Set(evidenceClasses).count == evidenceClasses.count else {
      throw invalid("evidenceClasses must be unique")
    }

    try requireNonBlank(runID, field: "runID")
    try validateCandidate()
    try validateArtifacts()
    try validateHardware()
    try validateCorpusMetadata()
    try validatePrivacy()
    try validateCases()
    try validateLifecycle()
    try validateAggregate()
    try validateGate()
  }

  private func validateCandidate() throws {
    try requireNonBlank(candidate.modelID, field: "candidate.modelID")
    try requireNonBlank(candidate.modelRevision, field: "candidate.modelRevision")
    try requireNonBlank(candidate.runtimeID, field: "candidate.runtimeID")
    try requireNonBlank(candidate.runtimeRevision, field: "candidate.runtimeRevision")
    try requireNonBlank(candidate.quantization, field: "candidate.quantization")
    try requireNonBlank(candidate.license, field: "candidate.license")
  }

  private func validateArtifacts() throws {
    try validateReceipt(artifacts.archiveReceipt, field: "archiveReceipt")
    try validateReceipt(artifacts.artifactReceipt, field: "artifactReceipt")
    guard !artifacts.installedFiles.isEmpty else {
      throw invalid("artifacts.installedFiles must not be empty")
    }
    try requireNonNegative(artifacts.totalInstalledBytes, field: "totalInstalledBytes")

    var seenPaths = Set<String>()
    var installedBytes: Int64 = 0
    for file in artifacts.installedFiles {
      try requireNonBlank(file.path, field: "installed file path")
      guard seenPaths.insert(file.path).inserted else {
        throw invalid("duplicate installed file path \(file.path)")
      }
      try requireHash(file.sha256, field: "installed file \(file.path) hash")
      try requireNonNegative(file.byteCount, field: "installed file \(file.path) byteCount")
      let (sum, overflow) = installedBytes.addingReportingOverflow(file.byteCount)
      guard !overflow else {
        throw invalid("installed byte total overflow")
      }
      installedBytes = sum
    }
    guard installedBytes == artifacts.totalInstalledBytes else {
      throw invalid("totalInstalledBytes does not match installed files")
    }
  }

  private func validateReceipt(
    _ receipt: CandidateBenchmarkArtifactReceipt,
    field: String
  ) throws {
    try requireNonBlank(receipt.id, field: "\(field).id")
    try requireNonBlank(receipt.revision, field: "\(field).revision")
    try requireHash(receipt.sha256, field: "\(field).sha256")
    try requireNonNegative(receipt.byteCount, field: "\(field).byteCount")
  }

  private func validateHardware() throws {
    try requireNonBlank(hardware.hwModel, field: "hardware.hwModel")
    try requireNonBlank(hardware.chip, field: "hardware.chip")
    try requireNonBlank(hardware.architecture, field: "hardware.architecture")
    try requireNonNegative(hardware.memoryBytes, field: "hardware.memoryBytes")
    try requireNonBlank(hardware.osBuild, field: "hardware.osBuild")
  }

  private func validateCorpusMetadata() throws {
    try requireNonBlank(corpus.manifestID, field: "corpus.manifestID")
    try requireNonBlank(corpus.revision, field: "corpus.revision")
    try requireNonBlank(corpus.license, field: "corpus.license")
    guard !corpus.caseBindings.isEmpty else {
      throw invalid("corpus.caseBindings must not be empty")
    }

    var seenIDs = Set<String>()
    for binding in corpus.caseBindings {
      try requireNonBlank(binding.caseID, field: "corpus case binding ID")
      guard seenIDs.insert(binding.caseID).inserted else {
        throw invalid("duplicate corpus case binding \(binding.caseID)")
      }
      try requireHash(binding.audioSHA256, field: "corpus case binding \(binding.caseID) hash")
    }
  }

  private func validatePrivacy() throws {
    try requireNonBlank(privacy.policy, field: "privacy.policy")
    try requireNonBlank(privacy.mechanism, field: "privacy.mechanism")
    guard privacy.unexpectedConnectionCount >= 0 else {
      throw invalid("privacy.unexpectedConnectionCount cannot be negative")
    }
    if privacy.claimsVerifiedOffline {
      guard privacy.enforced else {
        throw invalid("verified offline claim requires enforced privacy")
      }
      guard privacy.unexpectedConnectionCount == 0 else {
        throw invalid("verified offline claim requires zero unexpected connections")
      }
    }
  }

  private func validateCases() throws {
    guard !cases.isEmpty else {
      throw invalid("cases must not be empty")
    }

    var seenIDs = Set<String>()
    var caseClasses = Set<CandidateBenchmarkEvidenceClass>()
    var caseHashes = [String: String]()
    for evaluationCase in cases {
      try requireNonBlank(evaluationCase.id, field: "case ID")
      guard seenIDs.insert(evaluationCase.id).inserted else {
        throw invalid("duplicate case ID \(evaluationCase.id)")
      }
      caseClasses.insert(evaluationCase.sourceClass)
      caseHashes[evaluationCase.id] = evaluationCase.audioSHA256
      try validateCase(evaluationCase)
    }

    guard caseClasses == Set(evidenceClasses) else {
      throw invalid("evidenceClasses must match case source classes")
    }

    var bindingIDs = Set<String>()
    for binding in corpus.caseBindings {
      bindingIDs.insert(binding.caseID)
      guard let audioSHA256 = caseHashes[binding.caseID] else {
        throw invalid("corpus binding has no matching case \(binding.caseID)")
      }
      guard audioSHA256 == binding.audioSHA256 else {
        throw invalid("corpus hash does not match case \(binding.caseID)")
      }
    }
    guard bindingIDs == seenIDs else {
      throw invalid("corpus case bindings must cover every case exactly once")
    }
  }

  private func validateCase(_ evaluationCase: CandidateBenchmarkCase) throws {
    try requireHash(evaluationCase.audioSHA256, field: "case \(evaluationCase.id) audio hash")
    try requireFiniteNonNegative(
      evaluationCase.audioDurationMilliseconds,
      field: "case \(evaluationCase.id) audio duration"
    )
    try requireFiniteNonNegative(
      evaluationCase.captureTemperature,
      field: "case \(evaluationCase.id) capture temperature"
    )
    try requireNonNegative(
      evaluationCase.peakResidentBytes,
      field: "case \(evaluationCase.id) peak resident bytes"
    )
    try requireNonNegative(
      evaluationCase.peakPhysicalFootprintBytes,
      field: "case \(evaluationCase.id) peak physical footprint bytes"
    )
    try requireFiniteNonNegative(
      evaluationCase.timing.fileDecodeMilliseconds,
      field: "case \(evaluationCase.id) file decode timing"
    )
    if let firstPartialMilliseconds = evaluationCase.timing.firstPartialMilliseconds {
      try requireFiniteNonNegative(
        firstPartialMilliseconds,
        field: "case \(evaluationCase.id) first partial timing"
      )
    }

    try validateSourceLanguagePair(evaluationCase)
    try validateReference(evaluationCase)
    try validateProtectedExpectations(evaluationCase)
    try validateCodeSwitches(evaluationCase)
    try validateCancellation(evaluationCase)
  }

  private func validateSourceLanguagePair(_ evaluationCase: CandidateBenchmarkCase) throws {
    switch evaluationCase.sourceClass {
    case .synthetic:
      return
    case .publicHuman, .operatorLiveHuman:
      guard evaluationCase.language != .none else {
        throw invalid("human speech case \(evaluationCase.id) requires an applicable language")
      }
    case .publicHumanComposite:
      guard evaluationCase.language == .mixed else {
        throw invalid("composite case \(evaluationCase.id) must use mixed language")
      }
    }
  }

  private func validateReference(_ evaluationCase: CandidateBenchmarkCase) throws {
    let referenceIsBlank = evaluationCase.reference
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    if evaluationCase.language == .none {
      guard evaluationCase.sourceClass == .synthetic, evaluationCase.reference.isEmpty else {
        throw invalid("empty references are reserved for synthetic language-none cases")
      }
    } else {
      guard !referenceIsBlank else {
        throw invalid("case \(evaluationCase.id) reference is required")
      }
    }
  }

  private func validateProtectedExpectations(_ evaluationCase: CandidateBenchmarkCase) throws {
    var seen = [CandidateBenchmarkProtectedExpectation]()
    for expectation in evaluationCase.protectedExpectations {
      try requireNonBlank(
        expectation.kind,
        field: "case \(evaluationCase.id) protected expectation kind"
      )
      try requireNonBlank(
        expectation.text,
        field: "case \(evaluationCase.id) protected expectation text"
      )
      guard !seen.contains(expectation) else {
        throw invalid("duplicate protected expectation in case \(evaluationCase.id)")
      }
      seen.append(expectation)
    }
  }

  private func validateCodeSwitches(_ evaluationCase: CandidateBenchmarkCase) throws {
    if evaluationCase.sourceClass == .publicHumanComposite {
      guard evaluationCase.language == .mixed else {
        throw invalid("composite case \(evaluationCase.id) must be mixed language")
      }
      guard !evaluationCase.codeSwitchSpans.isEmpty else {
        throw invalid("composite case \(evaluationCase.id) requires code-switch spans")
      }
      guard !evaluationCase.claimsNaturalCodeSwitch else {
        throw invalid("composite case \(evaluationCase.id) cannot claim a natural code switch")
      }
    } else {
      guard evaluationCase.codeSwitchSpans.isEmpty else {
        throw invalid("non-composite case \(evaluationCase.id) cannot contain code-switch spans")
      }
    }

    guard !evaluationCase.codeSwitchSpans.isEmpty else { return }
    var languages = Set<CandidateBenchmarkLanguage>()
    var previousEnd: Double?
    for span in evaluationCase.codeSwitchSpans {
      try requireFiniteNonNegative(
        span.startMilliseconds,
        field: "case \(evaluationCase.id) switch span start"
      )
      try requireFiniteNonNegative(
        span.endMilliseconds,
        field: "case \(evaluationCase.id) switch span end"
      )
      guard span.endMilliseconds > span.startMilliseconds else {
        throw invalid("case \(evaluationCase.id) switch spans must have positive duration")
      }
      if let previousEnd {
        guard span.startMilliseconds >= previousEnd else {
          throw invalid("case \(evaluationCase.id) switch spans overlap or are unordered")
        }
      }
      guard span.endMilliseconds <= evaluationCase.audioDurationMilliseconds else {
        throw invalid("case \(evaluationCase.id) switch span exceeds audio duration")
      }
      guard span.language == .english || span.language == .mandarin else {
        throw invalid("case \(evaluationCase.id) switch span language must be english or mandarin")
      }
      languages.insert(span.language)
      previousEnd = span.endMilliseconds
    }
    guard languages == [.english, .mandarin] else {
      throw invalid("case \(evaluationCase.id) switch spans must cover both languages")
    }
  }

  private func validateCancellation(_ evaluationCase: CandidateBenchmarkCase) throws {
    switch evaluationCase.cancellation.outcome {
    case .notCancelled:
      guard !evaluationCase.cancellation.noLateOutput else {
        throw invalid("case \(evaluationCase.id) cannot claim no late output without cancellation")
      }
      guard evaluationCase.outcome != .cancelled else {
        throw invalid("cancelled case \(evaluationCase.id) needs cancellation evidence")
      }
    case .cooperative:
      guard evaluationCase.cancellation.noLateOutput else {
        throw invalid("cooperative cancellation for case \(evaluationCase.id) has late output")
      }
      guard evaluationCase.outcome == .cancelled else {
        throw invalid("cooperative cancellation must mark case \(evaluationCase.id) cancelled")
      }
    case .forced:
      guard evaluationCase.outcome == .cancelled else {
        throw invalid("forced cancellation must mark case \(evaluationCase.id) cancelled")
      }
    }

    if evaluationCase.outcome == .silence {
      guard evaluationCase.hypothesis.isEmpty else {
        throw invalid("silence case \(evaluationCase.id) must preserve an empty hypothesis")
      }
      guard evaluationCase.cancellation.outcome == .notCancelled else {
        throw invalid("silence case \(evaluationCase.id) cannot also be cancelled")
      }
    }
  }

  private func validateLifecycle() throws {
    let phases: [(String, CandidateBenchmarkLifecyclePhase)] = [
      ("load", lifecycle.load),
      ("infer", lifecycle.infer),
      ("unload", lifecycle.unload),
      ("reload", lifecycle.reload),
    ]
    for (name, phase) in phases {
      try requireFiniteNonNegative(
        phase.durationMilliseconds,
        field: "lifecycle \(name) duration"
      )
      try requireNonNegative(phase.peakResidentBytes, field: "lifecycle \(name) peak resident bytes")
      try requireNonNegative(
        phase.peakPhysicalFootprintBytes,
        field: "lifecycle \(name) peak physical footprint bytes"
      )
    }

    guard lifecycle.load.outcome == .succeeded || lifecycle.infer.outcome != .succeeded else {
      throw invalid("inference cannot succeed after a failed or cancelled load")
    }
    guard lifecycle.unload.outcome != .succeeded || lifecycle.load.outcome == .succeeded else {
      throw invalid("unload cannot succeed without a successful load")
    }
    guard lifecycle.reload.outcome != .succeeded || lifecycle.unload.outcome == .succeeded else {
      throw invalid("reload cannot succeed after a failed or cancelled unload")
    }
  }

  private func validateAggregate() throws {
    let accuracyCases = cases.filter { evaluationCase in
      guard evaluationCase.outcome != .cancelled,
        !evaluationCase.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return false
      }
      switch (evaluationCase.sourceClass, evaluationCase.language) {
      case (.publicHuman, .english), (.publicHuman, .mandarin), (.publicHuman, .mixed),
        (.operatorLiveHuman, .english), (.operatorLiveHuman, .mandarin),
        (.operatorLiveHuman, .mixed),
        (.publicHumanComposite, .mixed):
        return true
      default:
        // Case validation rejects every unsupported non-synthetic human pair.
        return false
      }
    }
    let report = try scoreAccuracyCases(accuracyCases)
    try validateDerivedErrorRate(
      aggregate.accuracy.englishWER,
      derived: report?.languageMetrics.first(where: { $0.language == .english })?.errorRate,
      field: "aggregate.accuracy.englishWER"
    )
    try validateDerivedErrorRate(
      aggregate.accuracy.mandarinCER,
      derived: report?.languageMetrics.first(where: { $0.language == .mandarin })?.errorRate,
      field: "aggregate.accuracy.mandarinCER"
    )
    try validateDerivedErrorRate(
      aggregate.accuracy.mixedMER,
      derived: report?.languageMetrics.first(where: { $0.language == .mixed })?.errorRate,
      field: "aggregate.accuracy.mixedMER"
    )
    let codeSwitchSpans = accuracyCases
      .filter { $0.sourceClass == .publicHumanComposite }
      .flatMap { $0.codeSwitchSpans }
    let derivedCodeSwitchAccuracy = codeSwitchSpans.isEmpty
      ? nil
      : Double(codeSwitchSpans.filter(\.matched).count) / Double(codeSwitchSpans.count)
    try validateDerivedProportion(
      aggregate.accuracy.codeSwitchSpanAccuracy,
      derived: derivedCodeSwitchAccuracy,
      field: "aggregate.accuracy.codeSwitchSpanAccuracy"
    )
    let derivedProtectedViolationCount = report?.protectedViolations.count ?? 0
    guard aggregate.accuracy.protectedViolationCount == derivedProtectedViolationCount else {
      throw invalid("aggregate.accuracy.protectedViolationCount does not match detailed cases")
    }
    guard aggregate.accuracy.protectedViolationCount <= Self.maximumAggregateCount else {
      throw invalid("aggregate.accuracy.protectedViolationCount is out of bounds")
    }

    let completedDecodeCases = cases.filter {
      $0.outcome == .transcribed || $0.outcome == .silence
    }
    try validateLatencyPair(
      aggregate.latency.coldP50Milliseconds,
      aggregate.latency.coldP95Milliseconds,
      samples: completedDecodeCases.filter { $0.timing.isCold }
        .map { $0.timing.fileDecodeMilliseconds },
      field: "aggregate.latency.cold"
    )
    try validateLatencyPair(
      aggregate.latency.warmP50Milliseconds,
      aggregate.latency.warmP95Milliseconds,
      samples: completedDecodeCases.filter { !$0.timing.isCold }
        .map { $0.timing.fileDecodeMilliseconds },
      field: "aggregate.latency.warm"
    )

    let positiveDurationCases = completedDecodeCases.filter { $0.audioDurationMilliseconds > 0 }
    let derivedRTF: Double?
    if positiveDurationCases.isEmpty {
      derivedRTF = nil
    } else {
      let totalDecodeMilliseconds = positiveDurationCases.reduce(0.0) {
        $0 + $1.timing.fileDecodeMilliseconds
      }
      let totalAudioMilliseconds = positiveDurationCases.reduce(0.0) {
        $0 + $1.audioDurationMilliseconds
      }
      guard totalDecodeMilliseconds.isFinite, totalAudioMilliseconds.isFinite,
        totalAudioMilliseconds > 0
      else {
        throw invalid("aggregate.fileDecodeRTF cannot be derived from detailed cases")
      }
      derivedRTF = totalDecodeMilliseconds / totalAudioMilliseconds
    }
    try validateDerivedMeasurement(
      aggregate.fileDecodeRTF,
      derived: derivedRTF,
      field: "aggregate.fileDecodeRTF"
    )
    try requireAggregateBytes(aggregate.peakResidentBytes, field: "aggregate.peakResidentBytes")
    try requireAggregateBytes(
      aggregate.peakPhysicalFootprintBytes,
      field: "aggregate.peakPhysicalFootprintBytes"
    )
    try requireAggregateBytes(aggregate.totalStorageBytes, field: "aggregate.totalStorageBytes")
    guard aggregate.totalStorageBytes == artifacts.totalInstalledBytes else {
      throw invalid("aggregate.totalStorageBytes must match artifacts.totalInstalledBytes")
    }

    let observedResidentBytes = ([
      lifecycle.load.peakResidentBytes,
      lifecycle.infer.peakResidentBytes,
      lifecycle.unload.peakResidentBytes,
      lifecycle.reload.peakResidentBytes,
    ] + cases.map(\.peakResidentBytes)).max() ?? 0
    guard aggregate.peakResidentBytes == observedResidentBytes else {
      throw invalid("aggregate.peakResidentBytes must match the observed peak")
    }

    let observedPhysicalBytes = ([
      lifecycle.load.peakPhysicalFootprintBytes,
      lifecycle.infer.peakPhysicalFootprintBytes,
      lifecycle.unload.peakPhysicalFootprintBytes,
      lifecycle.reload.peakPhysicalFootprintBytes,
    ] + cases.map(\.peakPhysicalFootprintBytes)).max() ?? 0
    guard aggregate.peakPhysicalFootprintBytes == observedPhysicalBytes else {
      throw invalid("aggregate.peakPhysicalFootprintBytes must match the observed peak")
    }

    let summary = aggregate.lifecycleSummary
    let phaseSuccesses = [
      lifecycle.load.outcome == .succeeded,
      lifecycle.infer.outcome == .succeeded,
      lifecycle.unload.outcome == .succeeded,
      lifecycle.reload.outcome == .succeeded,
    ]
    guard [
      summary.loadSucceeded,
      summary.inferSucceeded,
      summary.unloadSucceeded,
      summary.reloadSucceeded,
    ] == phaseSuccesses else {
      throw invalid("aggregate.lifecycleSummary does not match lifecycle outcomes")
    }
    guard summary.allSucceeded == phaseSuccesses.allSatisfy({ $0 }) else {
      throw invalid("aggregate.lifecycleSummary.allSucceeded is inconsistent")
    }
  }

  private func validateGate() throws {
    guard !gate.releaseAdmitted else {
      throw invalid("releaseAdmitted must remain false for candidate benchmark evidence")
    }
    guard !gate.automatedCandidatePass else {
      throw invalid("automatedCandidatePass must remain false until an admission scorer exists")
    }

    var seenReasons = Set<String>()
    for reason in gate.failureReasons {
      try requireNonBlank(reason, field: "gate.failureReason")
      guard seenReasons.insert(reason).inserted else {
        throw invalid("gate.failureReasons must be unique")
      }
    }

    guard !gate.failureReasons.isEmpty else {
      throw invalid("a failing candidate must have at least one failure reason")
    }
  }

  private func scoreAccuracyCases(
    _ accuracyCases: [CandidateBenchmarkCase]
  ) throws -> ModelEvaluationReport? {
    guard !accuracyCases.isEmpty else { return nil }
    let input = ModelEvaluationRunInput(
      schemaVersion: 1,
      modelID: candidate.modelID,
      revision: candidate.modelRevision,
      runtime: candidate.runtimeID,
      quantization: candidate.quantization,
      hardware: hardware.hwModel,
      unexpectedNetworkConnectionCount: privacy.unexpectedConnectionCount,
      cases: accuracyCases.map { evaluationCase in
        ModelEvaluationCaseInput(
          id: evaluationCase.id,
          language: modelEvaluationLanguage(evaluationCase.language),
          reference: evaluationCase.reference,
          hypothesis: evaluationCase.hypothesis,
          protectedExpectations: evaluationCase.protectedExpectations
        )
      }
    )
    do {
      return try ModelEvaluationScorer.score(input)
    } catch {
      throw invalid("detailed transcribed cases cannot be scored: \(error)")
    }
  }

  private func modelEvaluationLanguage(
    _ language: CandidateBenchmarkLanguage
  ) -> ModelEvaluationLanguage {
    switch language {
    case .english:
      return .english
    case .mandarin:
      return .mandarin
    case .mixed:
      return .mixed
    case .none:
      preconditionFailure("language-none cases are not scored")
    }
  }

  private func validateLatencyPair(
    _ p50: Double?,
    _ p95: Double?,
    samples: [Double],
    field: String
  ) throws {
    let derivedP50 = samples.isEmpty ? nil : nearestRank(samples, percentile: 0.50)
    let derivedP95 = samples.isEmpty ? nil : nearestRank(samples, percentile: 0.95)
    guard (p50 == nil) == (derivedP50 == nil),
      (p95 == nil) == (derivedP95 == nil)
    else {
      throw invalid("\(field) latency applicability does not match detailed cases")
    }
    guard (p50 == nil) == (p95 == nil) else {
      throw invalid("\(field) p50 and p95 must be provided together")
    }
    if let p50, let derivedP50, let p95, let derivedP95 {
      try requireAggregateMeasurement(p50, field: "\(field) p50")
      try requireAggregateMeasurement(p95, field: "\(field) p95")
      guard approximatelyEqual(p50, derivedP50), approximatelyEqual(p95, derivedP95) else {
        throw invalid("\(field) latency does not match detailed file-decode timings")
      }
    }
  }

  private func validateDerivedErrorRate(
    _ value: Double?,
    derived: Double?,
    field: String
  ) throws {
    guard (value == nil) == (derived == nil) else {
      throw invalid("\(field) applicability does not match detailed cases")
    }
    if let value, let derived {
      guard value.isFinite, value >= 0, value <= Self.maximumAggregateMeasurement,
        derived.isFinite, derived >= 0, derived <= Self.maximumAggregateMeasurement
      else {
        throw invalid("\(field) must be finite, nonnegative, and bounded")
      }
      guard approximatelyEqual(value, derived) else {
        throw invalid("\(field) does not match detailed cases")
      }
    }
  }

  private func validateDerivedProportion(
    _ value: Double?,
    derived: Double?,
    field: String
  ) throws {
    guard (value == nil) == (derived == nil) else {
      throw invalid("\(field) applicability does not match detailed cases")
    }
    if let value, let derived {
      guard value.isFinite, value >= 0, value <= 1 else {
        throw invalid("\(field) must be finite and within 0...1")
      }
      guard approximatelyEqual(value, derived) else {
        throw invalid("\(field) does not match detailed code-switch spans")
      }
    }
  }

  private func validateDerivedMeasurement(
    _ value: Double?,
    derived: Double?,
    field: String
  ) throws {
    guard (value == nil) == (derived == nil) else {
      throw invalid("\(field) applicability does not match detailed cases")
    }
    if let value, let derived {
      try requireAggregateMeasurement(value, field: field)
      try requireAggregateMeasurement(derived, field: "derived \(field)")
      guard approximatelyEqual(value, derived) else {
        throw invalid("\(field) does not match detailed cases")
      }
    }
  }

  private func nearestRank(_ values: [Double], percentile: Double) -> Double {
    let sorted = values.sorted()
    let rank = Int(ceil(percentile * Double(sorted.count)))
    return sorted[min(max(rank - 1, 0), sorted.count - 1)]
  }

  private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= 1e-12 * max(1, abs(lhs), abs(rhs))
  }

  private func requireAggregateMeasurement(_ value: Double, field: String) throws {
    guard value.isFinite, value >= 0, value <= Self.maximumAggregateMeasurement else {
      throw invalid("\(field) must be finite, nonnegative, and bounded")
    }
  }

  private func requireAggregateBytes(_ value: Int64, field: String) throws {
    guard value >= 0, value <= Self.maximumAggregateBytes else {
      throw invalid("\(field) must be nonnegative and bounded")
    }
  }

  private static let maximumAggregateMeasurement = 1_000_000_000.0
  private static let maximumAggregateBytes: Int64 = 1_000_000_000_000_000
  private static let maximumAggregateCount = 1_000_000

  private func requireNonBlank(_ value: String, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw invalid("\(field) is required")
    }
  }

  private func requireHash(_ value: String, field: String) throws {
    guard value.utf8.count == 64,
      value.utf8.allSatisfy({ byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
      })
    else {
      throw invalid("\(field) must be a canonical lowercase 64-hex SHA-256")
    }
  }

  private func requireNonNegative(_ value: Int64, field: String) throws {
    guard value >= 0 else {
      throw invalid("\(field) cannot be negative")
    }
  }

  private func requireFiniteNonNegative(_ value: Double, field: String) throws {
    guard value.isFinite else {
      throw invalid("\(field) must be finite")
    }
    guard value >= 0 else {
      throw invalid("\(field) cannot be negative")
    }
  }

  private func invalid(_ reason: String) -> CandidateBenchmarkEvidenceError {
    .invalid(reason)
  }
}

extension CandidateBenchmarkEvidence {
  public var localWritingEvidenceLevel: LocalWritingEvidenceLevel? { nil }

  public var localWritingAdmissionOutcome: LocalWritingEvidenceOutcome {
    .notApplicable
  }
}
