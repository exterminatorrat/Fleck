import Darwin
import Foundation
import Testing

@testable import FleckCore

@Suite
struct LocalWritingExposureLedgerTests {
  @Test
  func emptyLedgerPublishesCanonicalCorpusBoundCheckpoint() throws {
    let first = try makeLedger(corpusID: corpusID)
    defer { first.cleanup() }
    let second = try makeLedger(corpusID: corpusID)
    defer { second.cleanup() }
    let other = try makeLedger(corpusID: otherCorpusID)
    defer { other.cleanup() }

    let checkpoint = try first.ledger.checkpoint()
    let secondCheckpoint = try second.ledger.checkpoint()
    let otherCheckpoint = try other.ledger.checkpoint()
    #expect(checkpoint.schemaVersion == 1)
    #expect(checkpoint.corpusID == corpusID)
    #expect(checkpoint.eventCount == 0)
    #expect(checkpoint.currentHeadSHA256 == secondCheckpoint.currentHeadSHA256)
    #expect(checkpoint.currentHeadSHA256 != otherCheckpoint.currentHeadSHA256)
    #expect(try first.ledger.verify(expectedCorpusID: corpusID).checkpoint == checkpoint)
    #expect(try ledgerMode(at: first.url) == 0o600)
    #expect(try ledgerMode(at: first.ledger.lockURL) == 0o600)

    let text = try String(decoding: Data(contentsOf: first.url), as: UTF8.self)
    #expect(text.hasSuffix("\n"))
    #expect(!text.contains(" "))
    #expect(!text.contains("\t"))
    #expect(text.contains(#""corpusID":"00000000-0000-0000-0000-000000000001""#))
  }

  @Test
  func exposureIsDurableBeforeCandidateAccess() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let initial = try fixture.ledger.checkpoint()
    var observed: LocalWritingExposureLedgerCheckpoint?

    let published = try fixture.ledger.appendExposureThenAccess(
      exposure(),
      expectedHead: initial.currentHeadSHA256
    ) {
      observed = try fixture.ledger.verify(expectedCorpusID: corpusID).checkpoint
    }

    #expect(observed == published)
    #expect(published.eventCount == 1)
  }

  @Test
  func appendFailureBlocksCandidateAccess() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let initial = try fixture.ledger.checkpoint()
    var accessed = false
    fixture.ledger.faultHook = { point in
      if point == .beforeRename { throw TestFailure.injected }
    }

    #expect(throws: TestFailure.injected) {
      try fixture.ledger.appendExposureThenAccess(
        exposure(),
        expectedHead: initial.currentHeadSHA256
      ) {
        accessed = true
      }
    }
    #expect(!accessed)
    #expect(try fixture.ledger.checkpoint() == initial)

    fixture.ledger.faultHook = { point in
      if point == .afterRenameBeforeDirectorySync { throw TestFailure.injected }
    }
    #expect(throws: TestFailure.injected) {
      try fixture.ledger.appendExposureThenAccess(
        exposure(),
        expectedHead: initial.currentHeadSHA256
      ) {
        accessed = true
      }
    }
    #expect(!accessed)
    let committed = try fixture.ledger.verify(expectedCorpusID: corpusID).checkpoint
    #expect(committed.eventCount == 1)

    var directorySynced = false
    fixture.ledger.faultHook = nil
    fixture.ledger.directorySyncObserver = { directorySynced = true }
    let successful = try fixture.ledger.appendExposureThenAccess(
      exposure(executionDigest: String(repeating: "5", count: 64)),
      expectedHead: committed.currentHeadSHA256
    ) {
      #expect(directorySynced)
      accessed = true
    }
    #expect(accessed)
    #expect(successful.eventCount == 2)
  }

  @Test
  func crashAfterExposureRetainsDurableEvent() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let initial = try fixture.ledger.checkpoint()

    #expect(throws: TestFailure.injected) {
      try fixture.ledger.appendExposureThenAccess(
        exposure(),
        expectedHead: initial.currentHeadSHA256
      ) {
        throw TestFailure.injected
      }
    }

    let reopened = try LocalWritingExposureLedger.open(at: fixture.url)
    #expect(try reopened.verify(expectedCorpusID: corpusID).checkpoint.eventCount == 1)
  }

  @Test
  func staleExpectedHeadAcrossInstancesPreservesWinner() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let other = try LocalWritingExposureLedger.open(at: fixture.url)
    let initial = try fixture.ledger.checkpoint()

    let winner = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: initial.currentHeadSHA256
    )
    #expect(throws: LocalWritingExposureLedgerError.conflict) {
      try other.appendExposure(
        exposure(executionDigest: String(repeating: "5", count: 64)),
        expectedHead: initial.currentHeadSHA256
      )
    }
    #expect(try other.checkpoint() == winner)

    let repeatedExecution = try other.appendExposure(
      exposure(executionDigest: String(repeating: "5", count: 64)),
      expectedHead: winner.currentHeadSHA256
    )
    #expect(repeatedExecution.eventCount == 2)
    #expect(throws: LocalWritingExposureLedgerError.conflict) {
      try fixture.ledger.appendExposure(
        exposure(executionDigest: String(repeating: "5", count: 64)),
        expectedHead: repeatedExecution.currentHeadSHA256
      )
    }
    #expect(try fixture.ledger.checkpoint() == repeatedExecution)
  }

  @Test
  func truncatedReorderedDuplicateAndForkedChainsFailClosed() throws {
    let canonical = try twoEventLedgerBytes()
    let lines = splitLines(canonical)
    #expect(lines.count == 3)

    let truncated = Data(canonical.dropLast(7))
    let reordered = joinedLines([lines[0], lines[2], lines[1]])
    let duplicated = joinedLines([lines[0], lines[1], lines[1], lines[2]])
    let forkedText = String(decoding: lines[2], as: UTF8.self).replacingOccurrences(
      of: #""previousEventSHA256":"[0-9a-f]{64}""#,
      with: #""previousEventSHA256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff""#,
      options: .regularExpression
    )
    let forked = joinedLines([lines[0], lines[1], Data(forkedText.utf8)])

    for bytes in [truncated, reordered, duplicated, forked] {
      let fixture = try makeLedger()
      defer { fixture.cleanup() }
      try replaceLedger(bytes, at: fixture.url)
      #expect(throws: LocalWritingExposureLedgerError.self) {
        try fixture.ledger.verify(expectedCorpusID: corpusID)
      }
    }
  }

  @Test
  func wrongCorpusAndNoncanonicalBytesFailClosed() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    #expect(throws: LocalWritingExposureLedgerError.identityMismatch) {
      try fixture.ledger.verify(expectedCorpusID: otherCorpusID)
    }

    let canonical = try Data(contentsOf: fixture.url)
    try replaceLedger(Data([0x20]) + canonical, at: fixture.url)
    #expect(throws: LocalWritingExposureLedgerError.nonCanonicalData) {
      try fixture.ledger.verify(expectedCorpusID: corpusID)
    }
  }

  @Test
  func lineageInvalidationMustPublishBeforeMutation() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let exposed = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
    )
    var mutated = false
    fixture.ledger.faultHook = { point in
      if point == .beforeRename { throw TestFailure.injected }
    }

    #expect(throws: TestFailure.injected) {
      try fixture.ledger.appendInvalidationThenMutation(
        invalidation(),
        expectedHead: exposed.currentHeadSHA256
      ) {
        mutated = true
      }
    }
    #expect(!mutated)

    fixture.ledger.faultHook = nil
    _ = try fixture.ledger.appendInvalidationThenMutation(
      invalidation(),
      expectedHead: exposed.currentHeadSHA256
    ) {
      let verification = try fixture.ledger.verify(expectedCorpusID: corpusID)
      mutated = verification.hasLaterInvalidation(
        materialLineageID: materialLineageID,
        after: exposed.currentHeadSHA256
      )
    }
    #expect(mutated)
  }

  @Test
  func oldHeadRemainsAncestorButConsumedLineageBecomesIneligible() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let exposureHead = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
    )
    _ = try fixture.ledger.appendInvalidation(
      invalidation(),
      expectedHead: exposureHead.currentHeadSHA256
    )

    let verification = try fixture.ledger.verify(expectedCorpusID: corpusID)
    #expect(verification.isAncestor(exposureHead.currentHeadSHA256))
    #expect(verification.hasLaterInvalidation(
      materialLineageID: materialLineageID,
      after: exposureHead.currentHeadSHA256
    ))
    #expect(verification.scoringEligibility(
      materialLineageID: materialLineageID,
      consumedAt: exposureHead.currentHeadSHA256
    ) == .diagnosticOnlyPostExposure)
  }

  @Test
  func unrelatedExposureSuffixDoesNotRestoreInvalidatedLineageEligibility() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let consumed = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
    )
    let invalidated = try fixture.ledger.appendInvalidation(
      invalidation(),
      expectedHead: consumed.currentHeadSHA256
    )
    let suffix = try fixture.ledger.appendExposure(
      exposure(caseID: caseID2, materialLineageID: materialLineageID2),
      expectedHead: invalidated.currentHeadSHA256
    )

    let verification = try fixture.ledger.verify(expectedCorpusID: corpusID)
    #expect(verification.checkpoint == suffix)
    #expect(verification.isAncestor(invalidated.currentHeadSHA256))
    #expect(verification.scoringEligibility(
      materialLineageID: materialLineageID,
      consumedAt: consumed.currentHeadSHA256
    ) == .diagnosticOnlyPostExposure)
  }

  @Test
  func sameMaterialPostExposureCorrectionIsDiagnosticOnly() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let consumed = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
    )
    let invalidated = try fixture.ledger.appendInvalidation(
      invalidation(reason: .oracleCorrectedAfterExposure),
      expectedHead: consumed.currentHeadSHA256
    )
    let reexposed = try fixture.ledger.appendExposure(
      exposure(candidateDigest: String(repeating: "4", count: 64)),
      expectedHead: invalidated.currentHeadSHA256
    )

    #expect(try fixture.ledger.verify(expectedCorpusID: corpusID).scoringEligibility(
      materialLineageID: materialLineageID,
      consumedAt: reexposed.currentHeadSHA256
    ) == .diagnosticOnlyPostExposure)
  }

  @Test
  func freshMaterialLineageCanRegainAdmissionEligibility() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let old = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
    )
    let invalidated = try fixture.ledger.appendInvalidation(
      invalidation(),
      expectedHead: old.currentHeadSHA256
    )
    let fresh = try fixture.ledger.appendExposure(
      exposure(caseID: caseID2, materialLineageID: materialLineageID2),
      expectedHead: invalidated.currentHeadSHA256
    )

    let verification = try fixture.ledger.verify(expectedCorpusID: corpusID)
    #expect(verification.scoringEligibility(
      materialLineageID: materialLineageID2,
      consumedAt: fresh.currentHeadSHA256
    ) == .admissionEligible)
  }

  @Test
  func ledgerRejectsSymlinksPermissionsBoundsAndNonregularFiles() throws {
    let insecureRoot = temporaryRoot()
    try FileManager.default.createDirectory(at: insecureRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: insecureRoot) }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: insecureRoot.path)
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.create(
        at: insecureRoot.appendingPathComponent("ledger.jsonl"),
        corpusID: corpusID
      )
    }

    let symlinkTarget = try makePrivateRoot()
    defer { try? FileManager.default.removeItem(at: symlinkTarget) }
    let symlinkRoot = temporaryRoot()
    try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: symlinkTarget)
    defer { try? FileManager.default.removeItem(at: symlinkRoot) }
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.create(
        at: symlinkRoot.appendingPathComponent("ledger.jsonl"),
        corpusID: corpusID
      )
    }

    let escapedRoot = try makePrivateRoot()
    defer { try? FileManager.default.removeItem(at: escapedRoot) }
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.create(
        at: escapedRoot.appendingPathComponent("../escaped-ledger.jsonl"),
        corpusID: corpusID
      )
    }

    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    try replaceLedger(Data(repeating: 0x20, count: LocalWritingExposureLedger.maximumLedgerBytes + 1), at: fixture.url)
    #expect(throws: LocalWritingExposureLedgerError.corruption) {
      try fixture.ledger.verify(expectedCorpusID: corpusID)
    }

    let directoryFixture = try makeLedger()
    defer { directoryFixture.cleanup() }
    try FileManager.default.removeItem(at: directoryFixture.url)
    try FileManager.default.createDirectory(at: directoryFixture.url, withIntermediateDirectories: false)
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.open(at: directoryFixture.url)
    }

    let ledgerSymlinkFixture = try makeLedger()
    defer { ledgerSymlinkFixture.cleanup() }
    try FileManager.default.removeItem(at: ledgerSymlinkFixture.url)
    try FileManager.default.createSymbolicLink(
      at: ledgerSymlinkFixture.url,
      withDestinationURL: ledgerSymlinkFixture.ledger.lockURL
    )
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.open(at: ledgerSymlinkFixture.url)
    }

    let lockSymlinkFixture = try makeLedger()
    defer { lockSymlinkFixture.cleanup() }
    try FileManager.default.removeItem(at: lockSymlinkFixture.ledger.lockURL)
    try FileManager.default.createSymbolicLink(
      at: lockSymlinkFixture.ledger.lockURL,
      withDestinationURL: lockSymlinkFixture.url
    )
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.open(at: lockSymlinkFixture.url)
    }

    let permissionFixture = try makeLedger()
    defer { permissionFixture.cleanup() }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: permissionFixture.url.path
    )
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.open(at: permissionFixture.url)
    }
  }

  @Test
  func canonicalEventsCannotEncodePrivateContentOrPaths() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let exposed = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
    )
    _ = try fixture.ledger.appendInvalidation(
      invalidation(),
      expectedHead: exposed.currentHeadSHA256
    )

    let text = try String(decoding: Data(contentsOf: fixture.url), as: UTF8.self)
    for forbidden in [
      "transcript", "prompt", "noteTitle", "noteBody", "term", "audioPath",
      "modelOutput", "metadata", "/Users/", "https://", "file://",
    ] {
      #expect(!text.contains(forbidden))
    }
    #expect(text.split(separator: "\n").count == 3)
  }
}

private enum TestFailure: Error {
  case injected
}

private struct LedgerFixture {
  let root: URL
  let url: URL
  let ledger: LocalWritingExposureLedger

  func cleanup() {
    try? FileManager.default.removeItem(at: root)
  }
}

private let corpusID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let otherCorpusID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let caseID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
private let caseID2 = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
private let materialLineageID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
private let materialLineageID2 = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

private func makeLedger(corpusID: UUID = corpusID) throws -> LedgerFixture {
  let root = try makePrivateRoot()
  let url = root.appendingPathComponent("eligibility-ledger.jsonl")
  return LedgerFixture(
    root: root,
    url: url,
    ledger: try LocalWritingExposureLedger.create(at: url, corpusID: corpusID)
  )
}

private func makePrivateRoot() throws -> URL {
  let root = temporaryRoot()
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
  return root
}

private func temporaryRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckLocalWritingExposureLedgerTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func exposure(
  caseID: UUID = caseID,
  materialLineageID: UUID = materialLineageID,
  candidateDigest: String = String(repeating: "1", count: 64),
  executionDigest: String = String(repeating: "4", count: 64)
) throws -> LocalWritingCandidateExposure {
  try LocalWritingCandidateExposure(
    corpusID: corpusID,
    caseID: caseID,
    materialLineageID: materialLineageID,
    candidateIdentitySHA256: candidateDigest,
    configurationIdentitySHA256: String(repeating: "2", count: 64),
    roleProfileIdentitySHA256: String(repeating: "3", count: 64),
    executionIdentitySHA256: executionDigest,
    executionStratum: .e1
  )
}

private func invalidation(
  reason: LocalWritingMaterialLineageInvalidationReason = .oracleCorrectedAfterExposure
) throws -> LocalWritingMaterialLineageInvalidation {
  try LocalWritingMaterialLineageInvalidation(
    corpusID: corpusID,
    caseID: caseID,
    materialLineageID: materialLineageID,
    reason: reason
  )
}

private func twoEventLedgerBytes() throws -> Data {
  let fixture = try makeLedger()
  defer { fixture.cleanup() }
  let first = try fixture.ledger.appendExposure(
    exposure(),
    expectedHead: try fixture.ledger.checkpoint().currentHeadSHA256
  )
  _ = try fixture.ledger.appendExposure(
    exposure(caseID: caseID2, materialLineageID: materialLineageID2),
    expectedHead: first.currentHeadSHA256
  )
  return try Data(contentsOf: fixture.url)
}

private func splitLines(_ data: Data) -> [Data] {
  String(decoding: data, as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map { Data($0.utf8) }
}

private func joinedLines(_ lines: [Data]) -> Data {
  var result = Data()
  for line in lines {
    result.append(line)
    result.append(0x0A)
  }
  return result
}

private func replaceLedger(_ data: Data, at url: URL) throws {
  try data.write(to: url, options: .atomic)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

private func ledgerMode(at url: URL) throws -> mode_t {
  var status = stat()
  guard lstat(url.path, &status) == 0 else { throw TestFailure.injected }
  return status.st_mode & 0o777
}
