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
    let decoded = try LocalWritingExposureLedger.verifyCheckpoint(
      canonicalData: checkpoint.canonicalData
    )
    #expect(decoded == checkpoint)
    #expect(decoded.canonicalData == checkpoint.canonicalData)
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

    var verification = try fixture.ledger.verify(expectedCorpusID: corpusID)
    #expect(verification.scoringEligibility(
      exposure: try exposure(),
      consumedAt: published.currentHeadSHA256
    ) == .admissionEligible)
    #expect(verification.scoringEligibility(
      exposure: try exposure(executionDigest: String(repeating: "5", count: 64)),
      consumedAt: published.currentHeadSHA256
    ) == .diagnosticOnlyPostExposure)

    let laterExposure = try exposure(executionDigest: String(repeating: "5", count: 64))
    _ = try fixture.ledger.appendExposure(
      laterExposure,
      expectedHead: published.currentHeadSHA256
    )
    verification = try fixture.ledger.verify(expectedCorpusID: corpusID)
    #expect(verification.scoringEligibility(
      exposure: laterExposure,
      consumedAt: published.currentHeadSHA256
    ) == .diagnosticOnlyPostExposure)
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

    let source = try makeLedger()
    defer { source.cleanup() }
    let parent = try source.ledger.appendExposure(
      exposure(),
      expectedHead: try source.ledger.checkpoint().currentHeadSHA256
    )
    let second = try source.ledger.appendExposure(
      exposure(executionDigest: String(repeating: "5", count: 64)),
      expectedHead: parent.currentHeadSHA256
    )
    let child = try source.ledger.appendExposure(
      exposure(caseID: caseID2, materialLineageID: materialLineageID2),
      expectedHead: second.currentHeadSHA256
    )
    let ledgerExtension = try source.ledger.exportExtension(after: parent)
    #expect(ledgerExtension.parentCheckpoint == parent)
    #expect(ledgerExtension.childCheckpoint == child)
    #expect(try LocalWritingExposureLedger.verifyExtension(
      canonicalData: ledgerExtension.canonicalData
    ) == ledgerExtension)
    #expect(throws: LocalWritingExposureLedgerError.invalidOrder) {
      try source.ledger.exportExtension(after: child)
    }

    let destination = try makeLedger()
    defer { destination.cleanup() }
    #expect(try destination.ledger.appendExposure(
      exposure(),
      expectedHead: try destination.ledger.checkpoint().currentHeadSHA256
    ) == parent)
    #expect(try destination.ledger.fastForward(ledgerExtension) == child)
    #expect(throws: LocalWritingExposureLedgerError.conflict) {
      try destination.ledger.fastForward(ledgerExtension)
    }

    let staleDestination = try makeLedger()
    defer { staleDestination.cleanup() }
    #expect(throws: LocalWritingExposureLedgerError.conflict) {
      try staleDestination.ledger.fastForward(ledgerExtension)
    }

    let extensionBytes = ledgerExtension.canonicalData
    let missing = try rewriteExtension(extensionBytes) { object in
      var events = object["events"] as! [String]
      events.removeLast()
      object["events"] = events
    }
    let extra = try rewriteExtension(extensionBytes) { object in
      var events = object["events"] as! [String]
      events.append(events[0])
      object["events"] = events
    }
    let extensionReordered = try rewriteExtension(extensionBytes) { object in
      object["events"] = Array((object["events"] as! [String]).reversed())
    }
    let extensionForked = try rewriteExtension(extensionBytes) { object in
      var events = object["events"] as! [String]
      var eventText = String(decoding: Data(base64Encoded: events[0])!, as: UTF8.self)
      eventText = eventText.replacingOccurrences(
        of: #""previousEventSHA256":"[0-9a-f]{64}""#,
        with: #""previousEventSHA256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff""#,
        options: .regularExpression
      )
      events[0] = Data(eventText.utf8).base64EncodedString()
      object["events"] = events
    }
    let wrongCorpus = try rewriteExtension(extensionBytes) { object in
      object["corpusID"] = canonicalUUIDString(otherCorpusID)
    }
    let wrongChild = try rewriteExtension(extensionBytes) { object in
      var checkpoint = object["childCheckpoint"] as! [String: Any]
      checkpoint["eventCount"] = 99
      object["childCheckpoint"] = checkpoint
    }
    for bytes in [
      Data(extensionBytes.dropLast()), Data([0x20]) + extensionBytes,
      missing, extra, extensionReordered, extensionForked, wrongCorpus, wrongChild,
    ] {
      #expect(throws: LocalWritingExposureLedgerError.self) {
        try LocalWritingExposureLedger.verifyExtension(canonicalData: bytes)
      }
    }
  }

  @Test
  func wrongCorpusAndNoncanonicalBytesFailClosed() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let checkpoint = try fixture.ledger.checkpoint()
    let checkpointBytes = checkpoint.canonicalData
    let duplicateKey = Data(
      String(decoding: checkpointBytes, as: UTF8.self).replacingOccurrences(
        of: "{",
        with: "{\"schemaVersion\":1,"
      ).utf8
    )
    let reordered = Data(
      "{\"schemaVersion\":1,\"eventCount\":\(checkpoint.eventCount),\"currentHeadSHA256\":\"\(checkpoint.currentHeadSHA256)\",\"corpusID\":\"\(canonicalUUIDString(checkpoint.corpusID))\"}".utf8
    )
    let unknownKey = try rewriteExtension(checkpointBytes) { object in
      object["unknown"] = true
    }
    let badCorpus = try rewriteExtension(checkpointBytes) { object in
      object["corpusID"] = "not-a-uuid"
    }
    let badDigest = try rewriteExtension(checkpointBytes) { object in
      object["currentHeadSHA256"] = String(repeating: "A", count: 64)
    }
    let badVersion = try rewriteExtension(checkpointBytes) { object in
      object["schemaVersion"] = 2
    }
    let negativeCount = try rewriteExtension(checkpointBytes) { object in
      object["eventCount"] = -1
    }
    let fractionalCount = try rewriteExtension(checkpointBytes) { object in
      object["eventCount"] = 1.5
    }
    for bytes in [
      Data([0x20]) + checkpointBytes, duplicateKey, reordered, unknownKey,
      badCorpus, badDigest, badVersion, negativeCount, fractionalCount,
    ] {
      #expect(throws: LocalWritingExposureLedgerError.self) {
        try LocalWritingExposureLedger.verifyCheckpoint(canonicalData: bytes)
      }
    }
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
      exposure: try exposure(),
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
      exposure: try exposure(),
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
      exposure: try exposure(candidateDigest: String(repeating: "4", count: 64)),
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
      exposure: try exposure(caseID: caseID2, materialLineageID: materialLineageID2),
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

    let stickyRoot = try makePrivateRoot()
    defer { try? FileManager.default.removeItem(at: stickyRoot) }
    #expect(Darwin.chmod(stickyRoot.path, 0o1700) == 0)
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.create(
        at: stickyRoot.appendingPathComponent("ledger.jsonl"),
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

    let setUserIDFixture = try makeLedger()
    defer { setUserIDFixture.cleanup() }
    #expect(Darwin.chmod(setUserIDFixture.url.path, 0o4600) == 0)
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.open(at: setUserIDFixture.url)
    }

    let setGroupIDFixture = try makeLedger()
    defer { setGroupIDFixture.cleanup() }
    #expect(Darwin.chmod(setGroupIDFixture.ledger.lockURL.path, 0o2600) == 0)
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try LocalWritingExposureLedger.open(at: setGroupIDFixture.url)
    }

    let lockReplacementFixture = try makeLedger()
    defer { lockReplacementFixture.cleanup() }
    lockReplacementFixture.ledger.faultHook = { point in
      if point == .afterLockAcquired {
        try replaceLedger(Data(), at: lockReplacementFixture.ledger.lockURL)
      }
    }
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try lockReplacementFixture.ledger.checkpoint()
    }

    let ledgerReplacementFixture = try makeLedger()
    defer { ledgerReplacementFixture.cleanup() }
    ledgerReplacementFixture.ledger.faultHook = { point in
      if point == .afterLockAcquired {
        let bytes = try Data(contentsOf: ledgerReplacementFixture.url)
        try replaceLedger(bytes, at: ledgerReplacementFixture.url)
      }
    }
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try ledgerReplacementFixture.ledger.checkpoint()
    }

    let stageReplacementFixture = try makeLedger()
    defer { stageReplacementFixture.cleanup() }
    stageReplacementFixture.ledger.faultHook = { point in
      if point == .afterStageWriteCloseBeforeReadOpen {
        let stageURL = try #require(
          FileManager.default.contentsOfDirectory(
            at: stageReplacementFixture.root,
            includingPropertiesForKeys: nil
          ).first { $0.lastPathComponent.contains(".stage-") }
        )
        try replaceLedger(Data(contentsOf: stageURL), at: stageURL)
      }
    }
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try stageReplacementFixture.ledger.appendExposure(
        exposure(),
        expectedHead: try stageReplacementFixture.ledger.checkpoint().currentHeadSHA256
      )
    }

    let rootReplacementFixture = try makeLedger()
    let displacedRoot = temporaryRoot()
    defer {
      rootReplacementFixture.cleanup()
      try? FileManager.default.removeItem(at: displacedRoot)
    }
    rootReplacementFixture.ledger.faultHook = { point in
      if point == .afterLockAcquired {
        try FileManager.default.moveItem(at: rootReplacementFixture.root, to: displacedRoot)
        try FileManager.default.createDirectory(
          at: rootReplacementFixture.root,
          withIntermediateDirectories: false
        )
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o700],
          ofItemAtPath: rootReplacementFixture.root.path
        )
        for name in [
          rootReplacementFixture.url.lastPathComponent,
          rootReplacementFixture.ledger.lockURL.lastPathComponent,
        ] {
          let source = displacedRoot.appendingPathComponent(name)
          let destination = rootReplacementFixture.root.appendingPathComponent(name)
          try replaceLedger(Data(contentsOf: source), at: destination)
        }
      }
    }
    #expect(throws: LocalWritingExposureLedgerError.permissions) {
      try rootReplacementFixture.ledger.checkpoint()
    }
  }

  @Test
  func canonicalEventsCannotEncodePrivateContentOrPaths() throws {
    let fixture = try makeLedger()
    defer { fixture.cleanup() }
    let initial = try fixture.ledger.checkpoint()
    let exposed = try fixture.ledger.appendExposure(
      exposure(),
      expectedHead: initial.currentHeadSHA256
    )
    _ = try fixture.ledger.appendInvalidation(
      invalidation(),
      expectedHead: exposed.currentHeadSHA256
    )

    let text = try String(decoding: Data(contentsOf: fixture.url), as: UTF8.self)
    let extensionText = try String(decoding: fixture.ledger.exportExtension(
      after: initial
    ).canonicalData, as: UTF8.self)
    for forbidden in [
      "transcript", "prompt", "noteTitle", "noteBody", "term", "audioPath",
      "modelOutput", "metadata", "/Users/", "https://", "file://",
    ] {
      #expect(!text.contains(forbidden))
      #expect(!extensionText.contains(forbidden))
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

private func canonicalUUIDString(_ value: UUID) -> String {
  value.uuidString.lowercased()
}

private func rewriteExtension(
  _ data: Data,
  mutation: (inout [String: Any]) throws -> Void
) throws -> Data {
  var object = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any]
  )
  try mutation(&object)
  return try JSONSerialization.data(
    withJSONObject: object,
    options: [.sortedKeys, .withoutEscapingSlashes]
  )
}
