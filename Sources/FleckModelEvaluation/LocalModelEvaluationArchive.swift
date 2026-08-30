import Foundation

public enum ArchiveFamily: String, Equatable, Sendable {
  case whisper
  case nemotron
  case qwenASR
  case qwenCleanup
}

public enum ArchiveRecordKind: String, Equatable, Sendable {
  case asrBenchmark
  case cleanupQualification
}

public enum ArchiveCorpusClass: String, Equatable, Sendable {
  case historicalASRBenchmark
  case historicalCleanupQualification
}

public enum ArchiveEvidenceTier: String, Equatable, Sendable {
  case historicalBenchmark
  case historicalQualification
}

public enum ArchiveUsage: String, Equatable, Sendable {
  case historicalEvaluationOnly
}

public enum ArchiveSourceRole: String, Comparable, Equatable, Sendable {
  case adapter
  case adapterExperiment
  case benchmark
  case correction
  case hardening
  case hardeningRedo
  case harness
  case helper
  case historicalHardening

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum ArchiveDivergenceReason: String, Equatable, Sendable {
  case notSuccessor
}

public enum ArchiveSupersessionReason: String, Equatable, Sendable {
  case replacedByFinalEvidence
}

public enum ArchiveSourceRelation: Equatable, Sendable {
  case canonical
  case identicalPatchAlias(canonicalCommitSHA1: String)
  case divergent(fromCommitSHA1: String, reason: ArchiveDivergenceReason)
  case superseded(byCommitSHA1: String, reason: ArchiveSupersessionReason)
}

public struct ArchiveSourceRevision: Equatable, Sendable {
  public let commitSHA1: String
  public let roles: [ArchiveSourceRole]
  public let relation: ArchiveSourceRelation

  init(
    commitSHA1: String,
    roles: [ArchiveSourceRole],
    relation: ArchiveSourceRelation
  ) throws {
    guard archiveIsGitSHA1(commitSHA1) else {
      throw ArchiveValidationError.invalidGitSHA1
    }
    try archiveRequireCanonical(roles)
    guard !roles.isEmpty else {
      throw ArchiveValidationError.missingIdentity
    }
    switch relation {
    case .canonical:
      break
    case .identicalPatchAlias(let target),
         .divergent(let target, _),
         .superseded(let target, _):
      guard archiveIsGitSHA1(target), target != commitSHA1 else {
        throw ArchiveValidationError.invalidSourceRelation
      }
    }
    self.commitSHA1 = commitSHA1
    self.roles = roles
    self.relation = relation
  }
}

public struct ArchiveSourceHistory: Equatable, Sendable {
  public let revisions: [ArchiveSourceRevision]

  init(revisions: [ArchiveSourceRevision]) throws {
    guard !revisions.isEmpty else {
      throw ArchiveValidationError.missingIdentity
    }
    let commits = revisions.map(\.commitSHA1)
    try archiveRequireCanonical(commits)
    let commitSet = Set(commits)
    for revision in revisions {
      let target: String?
      switch revision.relation {
      case .canonical:
        target = nil
      case .identicalPatchAlias(let commitSHA1):
        target = commitSHA1
      case .divergent(let commitSHA1, _):
        target = commitSHA1
      case .superseded(let commitSHA1, _):
        target = commitSHA1
      }
      if let target, !commitSet.contains(target) {
        throw ArchiveValidationError.invalidSourceRelation
      }
    }
    self.revisions = revisions
  }
}

public enum ArchiveAvailableBindingKind: String, Comparable, Equatable, Sendable {
  case corpus
  case hardware
  case outcome
  case profile
  case provenance
  case qualificationReport
  case result

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct ArchiveAvailableBinding: Equatable, Sendable {
  public let kind: ArchiveAvailableBindingKind
  public let value: String

  init(kind: ArchiveAvailableBindingKind, value: String) throws {
    guard archiveIsEvidenceSHA256(value) else {
      throw ArchiveValidationError.invalidEvidenceSHA256
    }
    self.kind = kind
    self.value = value
  }
}

public enum ArchiveMissingBindingReason: String, Comparable, Equatable, Sendable {
  case exactFleckSource
  case exactOSBuild
  case hardwareIdentity
  case sourceHarnessBinary
  case sourceHarnessBinding

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct ArchiveTraceableBindings: Equatable, Sendable {
  public let sourceCommitSHA1: String
  public let profileSHA256: String
  public let corpusSHA256: String
  public let hardwareSHA256: String
  public let resultSHA256: String

  init(
    sourceCommitSHA1: String?,
    profileSHA256: String?,
    corpusSHA256: String?,
    hardwareSHA256: String?,
    resultSHA256: String?
  ) throws {
    guard
      let sourceCommitSHA1,
      let profileSHA256,
      let corpusSHA256,
      let hardwareSHA256,
      let resultSHA256
    else {
      throw ArchiveValidationError.incompleteTraceable
    }
    guard archiveIsGitSHA1(sourceCommitSHA1) else {
      throw ArchiveValidationError.invalidGitSHA1
    }
    let evidence = [profileSHA256, corpusSHA256, hardwareSHA256, resultSHA256]
    guard evidence.allSatisfy(archiveIsEvidenceSHA256) else {
      throw ArchiveValidationError.invalidEvidenceSHA256
    }
    guard Set(evidence).count == evidence.count else {
      throw ArchiveValidationError.duplicateIdentity
    }
    self.sourceCommitSHA1 = sourceCommitSHA1
    self.profileSHA256 = profileSHA256
    self.corpusSHA256 = corpusSHA256
    self.hardwareSHA256 = hardwareSHA256
    self.resultSHA256 = resultSHA256
  }
}

public struct ArchiveDocumentedOnlyBindings: Equatable, Sendable {
  public let available: [ArchiveAvailableBinding]
  public let missingReasons: [ArchiveMissingBindingReason]

  init(
    available: [ArchiveAvailableBinding],
    missingReasons: [ArchiveMissingBindingReason]
  ) throws {
    guard !available.isEmpty, !missingReasons.isEmpty else {
      throw ArchiveValidationError.missingIdentity
    }
    let keys = available.map { "\($0.kind.rawValue):\($0.value)" }
    try archiveRequireCanonical(keys)
    guard Set(available.map(\.value)).count == available.count else {
      throw ArchiveValidationError.duplicateIdentity
    }
    try archiveRequireCanonical(missingReasons)
    self.available = available
    self.missingReasons = missingReasons
  }
}

public enum ArchiveTraceability: Equatable, Sendable {
  case traceable(ArchiveTraceableBindings)
  case documentedOnly(ArchiveDocumentedOnlyBindings)
}

public enum ArchiveRejectionReason: String, Equatable, Sendable {
  case unexpectedLexicalChange
}

enum ArchiveDispositionKind: String, Equatable, Sendable {
  case historical
  case benchmarkOnly
  case rejected
}

public enum ArchiveDisposition: Equatable, Sendable {
  case historical
  case benchmarkOnly
  case rejected(ArchiveRejectionReason)

  static func validated(
    kind: ArchiveDispositionKind,
    rejectionReason: ArchiveRejectionReason?
  ) throws -> Self {
    switch (kind, rejectionReason) {
    case (.historical, nil):
      return .historical
    case (.benchmarkOnly, nil):
      return .benchmarkOnly
    case (.rejected, .some(let reason)):
      return .rejected(reason)
    case (.historical, .some), (.benchmarkOnly, .some):
      throw ArchiveValidationError.unexpectedRejectionReason
    case (.rejected, nil):
      throw ArchiveValidationError.missingRejectionReason
    }
  }
}

public enum ArchiveValidationError: Error, Equatable {
  case duplicateIdentity
  case duplicateReason
  case incompleteTraceable
  case invalidEvidenceSHA256
  case invalidGitSHA1
  case invalidIdentifier
  case invalidSourceRelation
  case missingIdentity
  case missingRejectionReason
  case noncanonicalOrder
  case unexpectedRejectionReason
}

public struct ArchiveRecord: Equatable, Sendable {
  public let id: String
  public let family: ArchiveFamily
  public let kind: ArchiveRecordKind
  public let corpusClass: ArchiveCorpusClass
  public let evidenceTier: ArchiveEvidenceTier
  public let documentaryLabel: String
  public let sourceHistory: ArchiveSourceHistory
  public let traceability: ArchiveTraceability
  public let disposition: ArchiveDisposition
  public let usage: ArchiveUsage

  fileprivate init(
    id: String,
    family: ArchiveFamily,
    kind: ArchiveRecordKind,
    corpusClass: ArchiveCorpusClass,
    evidenceTier: ArchiveEvidenceTier,
    documentaryLabel: String,
    sourceHistory: ArchiveSourceHistory,
    traceability: ArchiveTraceability,
    disposition: ArchiveDisposition
  ) throws {
    guard archiveIsIdentifier(id) else {
      throw ArchiveValidationError.invalidIdentifier
    }
    guard !documentaryLabel.isEmpty,
      documentaryLabel == documentaryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      throw ArchiveValidationError.missingIdentity
    }
    if case .traceable(let bindings) = traceability {
      guard sourceHistory.revisions.contains(where: {
        $0.commitSHA1 == bindings.sourceCommitSHA1
      }) else {
        throw ArchiveValidationError.incompleteTraceable
      }
    }
    self.id = id
    self.family = family
    self.kind = kind
    self.corpusClass = corpusClass
    self.evidenceTier = evidenceTier
    self.documentaryLabel = documentaryLabel
    self.sourceHistory = sourceHistory
    self.traceability = traceability
    self.disposition = disposition
    usage = .historicalEvaluationOnly
  }
}

struct ArchiveIndex: Sendable {
  let records: [ArchiveRecord]

  init(records: [ArchiveRecord]) throws {
    guard !records.isEmpty else {
      throw ArchiveValidationError.missingIdentity
    }
    try archiveRequireCanonical(records.map(\.id))
    self.records = records
  }
}

public enum LocalModelEvaluationArchive {
  public static let records: [ArchiveRecord] = index.records

  public static func record(id: String) -> ArchiveRecord? {
    records.first { $0.id == id }
  }

  private static let index: ArchiveIndex = {
    do {
      return try ArchiveIndex(records: [
        nemotronRecord(),
        qwenASRRecord(),
        qwenCleanupRecord(),
        whisperRecord(),
      ])
    } catch {
      preconditionFailure("Invalid local model evaluation archive: \(error)")
    }
  }()

  private static func whisperRecord() throws -> ArchiveRecord {
    try ArchiveRecord(
      id: "whisper-asr-final-benchmark",
      family: .whisper,
      kind: .asrBenchmark,
      corpusClass: .historicalASRBenchmark,
      evidenceTier: .historicalBenchmark,
      documentaryLabel: "Whisper small control final benchmark",
      sourceHistory: ArchiveSourceHistory(revisions: [
        try source("3c51adf30f737f4f18243af3efb83202939be5e0", [.adapter]),
        try source("85381a88b619121fcb46a5d576b44e59816b1109", [.hardening]),
        try source(
          "a41aef534b626860c9f1e93d3067bc8958674341",
          [.correction],
          relation: .divergent(
            fromCommitSHA1: "85381a88b619121fcb46a5d576b44e59816b1109",
            reason: .notSuccessor
          )
        ),
        try source(
          "af49c07aa1276d54b3d6e7a934e7fbdebc98a7fa",
          [.benchmark],
          relation: .identicalPatchAlias(
            canonicalCommitSHA1: "ecd69f9d8947b74074de30b11864db5f72267b27"
          )
        ),
        try source("ecd69f9d8947b74074de30b11864db5f72267b27", [.benchmark]),
      ]),
      traceability: .documentedOnly(try documented(
        [
          (.corpus, "d3890ec3577d72334157c4fccc27d6dc69a9e3610e8185d7a6bac6cba86893d0"),
          (.hardware, "d0e9e907d90f84ed7c6c3198b948ed5ddac200d0d0b4c9ad58ab6044e6cc1464"),
          (.profile, "1644116843e508b30587968a9e05823c06e134922c0194950d0b2954b0984bbc"),
          (.result, "d88baeb70ffff523b34b58411e309ead2d9fe4803dc813bc96ce1ac436c6c040"),
        ],
        missing: [.exactOSBuild, .sourceHarnessBinary]
      )),
      disposition: .historical
    )
  }

  private static func nemotronRecord() throws -> ArchiveRecord {
    try ArchiveRecord(
      id: "nemotron-asr-final-benchmark",
      family: .nemotron,
      kind: .asrBenchmark,
      corpusClass: .historicalASRBenchmark,
      evidenceTier: .historicalBenchmark,
      documentaryLabel: "Nemotron final benchmark; automated candidate pass false is benchmark-only",
      sourceHistory: ArchiveSourceHistory(revisions: [
        try source("44a9942c96a25c7b117dae4fd49eb3b3dcba64fc", [.helper]),
        try source("84bc6bffbd6c75469764112148a3882a685c31d5", [.hardening]),
        try source("beaef43acec13c3f80ee2fce8fe4a978e0068c56", [.adapter]),
      ]),
      traceability: .documentedOnly(try documented(
        [
          (.corpus, "d3890ec3577d72334157c4fccc27d6dc69a9e3610e8185d7a6bac6cba86893d0"),
          (.hardware, "f98aff6b2c7995a39f6f22293a55d862c9da02f0172e591b442b50a1544678e1"),
          (.profile, "89e49a4a67156595bd352326c42e93c41a997be369e4001dbbb66cf327cf8acd"),
          (.result, "ce3d99da373ccee73eb53e29bc5eddd4f85e2e60d736aabfb895bf3792f9a6f3"),
        ],
        missing: [.sourceHarnessBinding]
      )),
      disposition: .benchmarkOnly
    )
  }

  private static func qwenASRRecord() throws -> ArchiveRecord {
    try ArchiveRecord(
      id: "qwen-asr-final-benchmark",
      family: .qwenASR,
      kind: .asrBenchmark,
      corpusClass: .historicalASRBenchmark,
      evidenceTier: .historicalBenchmark,
      documentaryLabel: "Qwen ASR final benchmark",
      sourceHistory: ArchiveSourceHistory(revisions: [
        try source("01904f8b23bc1376c4aad886126472379704241c", [.benchmark]),
        try source("2ca49f3e0f61d79b0fda1d236991db651a78de30", [.helper]),
        try source("4dfeb922004c8ef099811e3e6fdf2b931e554efe", [.hardeningRedo]),
        try source(
          "71739d6a24fc46327950a35370e616b25cb47652",
          [.adapterExperiment, .historicalHardening]
        ),
      ]),
      traceability: .documentedOnly(try documented(
        [
          (.corpus, "afa77705f55efe8afced980a4f01a886dbbccc839e4806c69f6a18c452ec32cd"),
          (.hardware, "f98aff6b2c7995a39f6f22293a55d862c9da02f0172e591b442b50a1544678e1"),
          (.profile, "2e73a9b05dd315aa0902360746b4a699abea69b82cd17b8ddfa80c899fe12b42"),
          (.result, "4ca3aba3ed9122ce9cafe16171970c2f45810524dbf6dbbc6095db81c1725f9b"),
        ],
        missing: [.exactFleckSource, .sourceHarnessBinding]
      )),
      disposition: .historical
    )
  }

  private static func qwenCleanupRecord() throws -> ArchiveRecord {
    try ArchiveRecord(
      id: "qwen-cleanup-rejected-qualification",
      family: .qwenCleanup,
      kind: .cleanupQualification,
      corpusClass: .historicalCleanupQualification,
      evidenceTier: .historicalQualification,
      documentaryLabel: "Qwen cleanup qualification rejected for unexpected lexical change",
      sourceHistory: ArchiveSourceHistory(revisions: [
        try source("e662b1fad117ef2eab32c578db2edf9743bba81b", [.harness]),
      ]),
      traceability: .documentedOnly(try documented(
        [
          (.corpus, "08acf8d411d1aa3b2880124cfbb711085bd6b94a2352bfbcc644c0edf8071fd8"),
          (.outcome, "3d18bfb90bd08bd423977456967872f7ec6569ccf13bfbb1073638dff7b2452c"),
          (.profile, "95daece6fb1e3a1e8f23cfcbe2f74494f315d307b641033685b50106f7647783"),
          (.provenance, "6b94c79eb8e071d2f085c4955ddd600b49da7c818d8422b53e5147a9296d9cbf"),
          (.qualificationReport, "9604fe5bc5ce29b04e49eccc7f681c8856591b577cf97e514ba034d988901bdd"),
        ],
        missing: [.hardwareIdentity]
      )),
      disposition: .rejected(.unexpectedLexicalChange)
    )
  }

  private static func source(
    _ commitSHA1: String,
    _ roles: [ArchiveSourceRole],
    relation: ArchiveSourceRelation = .canonical
  ) throws -> ArchiveSourceRevision {
    try ArchiveSourceRevision(commitSHA1: commitSHA1, roles: roles, relation: relation)
  }

  private static func documented(
    _ bindings: [(ArchiveAvailableBindingKind, String)],
    missing: [ArchiveMissingBindingReason]
  ) throws -> ArchiveDocumentedOnlyBindings {
    try ArchiveDocumentedOnlyBindings(
      available: bindings.map { try ArchiveAvailableBinding(kind: $0.0, value: $0.1) },
      missingReasons: missing
    )
  }
}

private func archiveRequireCanonical<T: Comparable & Hashable>(_ values: [T]) throws {
  guard Set(values).count == values.count else {
    if T.self == ArchiveMissingBindingReason.self {
      throw ArchiveValidationError.duplicateReason
    }
    throw ArchiveValidationError.duplicateIdentity
  }
  guard values == values.sorted() else {
    throw ArchiveValidationError.noncanonicalOrder
  }
}

private func archiveIsGitSHA1(_ value: String) -> Bool {
  archiveIsLowercaseHex(value, count: 40)
}

private func archiveIsEvidenceSHA256(_ value: String) -> Bool {
  archiveIsLowercaseHex(value, count: 64)
}

private func archiveIsLowercaseHex(_ value: String, count: Int) -> Bool {
  value.count == count
    && value != String(repeating: "0", count: count)
    && value.utf8.allSatisfy {
      ($0 >= Character("0").asciiValue! && $0 <= Character("9").asciiValue!)
        || ($0 >= Character("a").asciiValue! && $0 <= Character("f").asciiValue!)
    }
}

private func archiveIsIdentifier(_ value: String) -> Bool {
  !value.isEmpty
    && value.first != "-"
    && value.last != "-"
    && !value.contains("--")
    && value.utf8.allSatisfy {
      ($0 >= Character("a").asciiValue! && $0 <= Character("z").asciiValue!)
        || ($0 >= Character("0").asciiValue! && $0 <= Character("9").asciiValue!)
        || $0 == Character("-").asciiValue!
    }
}
