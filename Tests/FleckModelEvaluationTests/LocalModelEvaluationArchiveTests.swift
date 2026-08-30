import Testing

@testable import FleckModelEvaluation

@Suite
struct LocalModelEvaluationArchiveTests {
  @Test
  func archiveContainsWhisper() throws {
    let record = try #require(
      LocalModelEvaluationArchive.record(id: "whisper-asr-final-benchmark")
    )

    #expect(record.family == .whisper)
    #expect(record.kind == .asrBenchmark)
    #expect(record.corpusClass == .historicalASRBenchmark)
    #expect(record.sourceHistory.revisions.map(\.commitSHA1) == [
      "3c51adf30f737f4f18243af3efb83202939be5e0",
      "85381a88b619121fcb46a5d576b44e59816b1109",
      "a41aef534b626860c9f1e93d3067bc8958674341",
      "af49c07aa1276d54b3d6e7a934e7fbdebc98a7fa",
      "ecd69f9d8947b74074de30b11864db5f72267b27",
    ])
    let documented = try documentedBindings(record)
    #expect(documented.available.map(\.value) == [
      "d3890ec3577d72334157c4fccc27d6dc69a9e3610e8185d7a6bac6cba86893d0",
      "d0e9e907d90f84ed7c6c3198b948ed5ddac200d0d0b4c9ad58ab6044e6cc1464",
      "1644116843e508b30587968a9e05823c06e134922c0194950d0b2954b0984bbc",
      "d88baeb70ffff523b34b58411e309ead2d9fe4803dc813bc96ce1ac436c6c040",
    ])
    #expect(documented.missingReasons == [.exactOSBuild, .sourceHarnessBinary])
  }

  @Test
  func archiveContainsNemotron() throws {
    let record = try #require(
      LocalModelEvaluationArchive.record(id: "nemotron-asr-final-benchmark")
    )

    #expect(record.family == .nemotron)
    #expect(record.disposition == .benchmarkOnly)
    #expect(record.sourceHistory.revisions.map(\.commitSHA1) == [
      "44a9942c96a25c7b117dae4fd49eb3b3dcba64fc",
      "84bc6bffbd6c75469764112148a3882a685c31d5",
      "beaef43acec13c3f80ee2fce8fe4a978e0068c56",
    ])
    let documented = try documentedBindings(record)
    #expect(documented.available.map(\.value) == [
      "d3890ec3577d72334157c4fccc27d6dc69a9e3610e8185d7a6bac6cba86893d0",
      "f98aff6b2c7995a39f6f22293a55d862c9da02f0172e591b442b50a1544678e1",
      "89e49a4a67156595bd352326c42e93c41a997be369e4001dbbb66cf327cf8acd",
      "ce3d99da373ccee73eb53e29bc5eddd4f85e2e60d736aabfb895bf3792f9a6f3",
    ])
    #expect(documented.missingReasons == [.sourceHarnessBinding])
  }

  @Test
  func archiveContainsQwen() throws {
    let record = try #require(
      LocalModelEvaluationArchive.record(id: "qwen-asr-final-benchmark")
    )

    #expect(record.family == .qwenASR)
    #expect(record.sourceHistory.revisions.map(\.commitSHA1) == [
      "01904f8b23bc1376c4aad886126472379704241c",
      "2ca49f3e0f61d79b0fda1d236991db651a78de30",
      "4dfeb922004c8ef099811e3e6fdf2b931e554efe",
      "71739d6a24fc46327950a35370e616b25cb47652",
    ])
    let aliasedRevision = try #require(record.sourceHistory.revisions.last)
    #expect(aliasedRevision.roles == [.adapterExperiment, .historicalHardening])
    let documented = try documentedBindings(record)
    #expect(documented.available.map(\.value) == [
      "afa77705f55efe8afced980a4f01a886dbbccc839e4806c69f6a18c452ec32cd",
      "f98aff6b2c7995a39f6f22293a55d862c9da02f0172e591b442b50a1544678e1",
      "2e73a9b05dd315aa0902360746b4a699abea69b82cd17b8ddfa80c899fe12b42",
      "4ca3aba3ed9122ce9cafe16171970c2f45810524dbf6dbbc6095db81c1725f9b",
    ])
    #expect(documented.missingReasons == [.exactFleckSource, .sourceHarnessBinding])
  }

  @Test
  func archivePreservesDocumentedOnly() throws {
    #expect(LocalModelEvaluationArchive.records.count == 4)
    for record in LocalModelEvaluationArchive.records {
      guard case .documentedOnly(let bindings) = record.traceability else {
        Issue.record("Historical row was upgraded to traceable: \(record.id)")
        continue
      }
      #expect(!bindings.available.isEmpty)
      #expect(!bindings.missingReasons.isEmpty)
    }
  }

  @Test
  func archivePreservesRejected() throws {
    let record = try #require(
      LocalModelEvaluationArchive.record(id: "qwen-cleanup-rejected-qualification")
    )

    #expect(record.family == .qwenCleanup)
    #expect(record.kind == .cleanupQualification)
    #expect(record.disposition == .rejected(.unexpectedLexicalChange))
    let documented = try documentedBindings(record)
    #expect(documented.available.map(\.value) == [
      "08acf8d411d1aa3b2880124cfbb711085bd6b94a2352bfbcc644c0edf8071fd8",
      "3d18bfb90bd08bd423977456967872f7ec6569ccf13bfbb1073638dff7b2452c",
      "95daece6fb1e3a1e8f23cfcbe2f74494f315d307b641033685b50106f7647783",
      "6b94c79eb8e071d2f085c4955ddd600b49da7c818d8422b53e5147a9296d9cbf",
      "9604fe5bc5ce29b04e49eccc7f681c8856591b577cf97e514ba034d988901bdd",
    ])
    #expect(documented.missingReasons == [.hardwareIdentity])
  }

  @Test
  func rejectsMalformedUppercaseAndAllZeroIdentities() {
    #expect(throws: ArchiveValidationError.invalidGitSHA1) {
      try ArchiveSourceRevision(
        commitSHA1: "abc",
        roles: [.adapter],
        relation: .canonical
      )
    }
    #expect(throws: ArchiveValidationError.invalidGitSHA1) {
      try ArchiveSourceRevision(
        commitSHA1: String(repeating: "A", count: 40),
        roles: [.adapter],
        relation: .canonical
      )
    }
    #expect(throws: ArchiveValidationError.invalidGitSHA1) {
      try ArchiveSourceRevision(
        commitSHA1: String(repeating: "0", count: 40),
        roles: [.adapter],
        relation: .canonical
      )
    }
    #expect(throws: ArchiveValidationError.invalidEvidenceSHA256) {
      try ArchiveAvailableBinding(kind: .profile, value: String(repeating: "A", count: 64))
    }
    #expect(throws: ArchiveValidationError.invalidEvidenceSHA256) {
      try ArchiveAvailableBinding(kind: .profile, value: String(repeating: "0", count: 64))
    }
  }

  @Test
  func rejectsDuplicateAndUnsortedIdentities() throws {
    let corpus = try binding(.corpus, "1")
    let result = try binding(.result, "2")

    #expect(throws: ArchiveValidationError.duplicateIdentity) {
      try ArchiveDocumentedOnlyBindings(
        available: [corpus, corpus],
        missingReasons: [.hardwareIdentity]
      )
    }
    #expect(throws: ArchiveValidationError.noncanonicalOrder) {
      try ArchiveDocumentedOnlyBindings(
        available: [result, corpus],
        missingReasons: [.hardwareIdentity]
      )
    }
    #expect(throws: ArchiveValidationError.duplicateReason) {
      try ArchiveDocumentedOnlyBindings(
        available: [corpus],
        missingReasons: [.hardwareIdentity, .hardwareIdentity]
      )
    }
  }

  @Test
  func rejectsIncompleteTraceableConstruction() throws {
    #expect(throws: ArchiveValidationError.incompleteTraceable) {
      try ArchiveTraceableBindings(
        sourceCommitSHA1: "1111111111111111111111111111111111111111",
        profileSHA256: String(repeating: "2", count: 64),
        corpusSHA256: String(repeating: "3", count: 64),
        hardwareSHA256: nil,
        resultSHA256: String(repeating: "5", count: 64)
      )
    }
  }

  @Test
  func rejectedDispositionRequiresAReason() {
    #expect(throws: ArchiveValidationError.missingRejectionReason) {
      try ArchiveDisposition.validated(kind: .rejected, rejectionReason: nil)
    }
    let rejected = try? ArchiveDisposition.validated(
      kind: .rejected,
      rejectionReason: .unexpectedLexicalChange
    )
    #expect(rejected == .rejected(.unexpectedLexicalChange))
  }

  @Test
  func duplicatePatchAliasesAreCollapsed() throws {
    let whisper = try #require(
      LocalModelEvaluationArchive.record(id: "whisper-asr-final-benchmark")
    )
    let alias = try #require(whisper.sourceHistory.revisions.first {
      $0.commitSHA1 == "af49c07aa1276d54b3d6e7a934e7fbdebc98a7fa"
    })

    #expect(alias.relation == .identicalPatchAlias(
      canonicalCommitSHA1: "ecd69f9d8947b74074de30b11864db5f72267b27"
    ))
    #expect(whisper.sourceHistory.revisions.filter {
      $0.roles.contains(.benchmark)
    }.count == 2)
  }

  @Test
  func divergentWhisperCorrectionIsNotASuccessor() throws {
    let whisper = try #require(
      LocalModelEvaluationArchive.record(id: "whisper-asr-final-benchmark")
    )
    let correction = try #require(whisper.sourceHistory.revisions.first {
      $0.commitSHA1 == "a41aef534b626860c9f1e93d3067bc8958674341"
    })

    #expect(correction.relation == .divergent(
      fromCommitSHA1: "85381a88b619121fcb46a5d576b44e59816b1109",
      reason: .notSuccessor
    ))
  }

  @Test
  func sourceHistoryRejectsDuplicateAndUnsortedCommits() throws {
    let first = try ArchiveSourceRevision(
      commitSHA1: "1111111111111111111111111111111111111111",
      roles: [.adapter],
      relation: .canonical
    )
    let second = try ArchiveSourceRevision(
      commitSHA1: "2222222222222222222222222222222222222222",
      roles: [.benchmark],
      relation: .canonical
    )

    #expect(throws: ArchiveValidationError.duplicateIdentity) {
      try ArchiveSourceHistory(revisions: [first, first])
    }
    #expect(throws: ArchiveValidationError.noncanonicalOrder) {
      try ArchiveSourceHistory(revisions: [second, first])
    }
  }

  @Test
  func indexIsDeterministicallyOrderedAndSupportsExactLookup() {
    #expect(LocalModelEvaluationArchive.records.map(\.id) == [
      "nemotron-asr-final-benchmark",
      "qwen-asr-final-benchmark",
      "qwen-cleanup-rejected-qualification",
      "whisper-asr-final-benchmark",
    ])
    #expect(LocalModelEvaluationArchive.record(id: "QWEN-ASR-FINAL-BENCHMARK") == nil)
    #expect(LocalModelEvaluationArchive.record(id: "qwen") == nil)
  }

  @Test
  func indexRejectsDuplicateAndUnsortedRecordIDs() throws {
    let records = LocalModelEvaluationArchive.records

    #expect(throws: ArchiveValidationError.duplicateIdentity) {
      try ArchiveIndex(records: [records[0], records[0]])
    }
    #expect(throws: ArchiveValidationError.noncanonicalOrder) {
      try ArchiveIndex(records: Array(records.reversed()))
    }
  }

  @Test
  func recordsCannotRepresentRuntimeOrReleaseProof() {
    #expect(LocalModelEvaluationArchive.records.allSatisfy {
      $0.usage == .historicalEvaluationOnly
    })
    #expect(LocalModelEvaluationArchive.records.allSatisfy {
      $0.evidenceTier == .historicalBenchmark || $0.evidenceTier == .historicalQualification
    })
  }

  private func documentedBindings(
    _ record: ArchiveRecord
  ) throws -> ArchiveDocumentedOnlyBindings {
    guard case .documentedOnly(let bindings) = record.traceability else {
      throw ArchiveValidationError.incompleteTraceable
    }
    return bindings
  }

  private func binding(
    _ kind: ArchiveAvailableBindingKind,
    _ digit: Character
  ) throws -> ArchiveAvailableBinding {
    try ArchiveAvailableBinding(kind: kind, value: String(repeating: digit, count: 64))
  }
}
