import Foundation
import Testing

@testable import FleckCore

@Suite struct PersonalDictionaryTransferTests {
  @Test func completeTransferPreviewsDeterministicDeltaAndRebasesLocalRevision() async throws {
    let sourceRoot = transferRoot()
    let targetRoot = transferRoot()
    defer {
      try? FileManager.default.removeItem(at: sourceRoot)
      try? FileManager.default.removeItem(at: targetRoot)
    }

    let updated = transferEntry(1, "Updated", aliases: ["updated alias"])
    let disabledUnsupported = transferEntry(
      2,
      "Disabled",
      locale: "en-GB",
      enabled: false,
      origin: .suggested
    )
    let sourceSuggestion = transferSuggestion(4, "Pending")
    let source = PersonalDictionaryStore(rootURL: sourceRoot)
    try await source.replace(
      with: PersonalDictionarySnapshot(
        entries: [disabledUnsupported, updated],
        suggestions: [sourceSuggestion]
      )
    )

    let previous = transferEntry(1, "Previous")
    let omitted = transferEntry(3, "Omitted")
    let previousSuggestion = PersonalDictionarySuggestion(
      id: sourceSuggestion.id,
      preferredForm: "Previous pending",
      observedForms: ["previous pending"],
      observationCount: 1,
      lastObservedAt: Date(timeIntervalSince1970: 1_600_000_000)
    )
    let omittedSuggestion = transferSuggestion(5, "Omitted suggestion")
    let target = PersonalDictionaryStore(rootURL: targetRoot)
    try await target.replace(
      with: PersonalDictionarySnapshot(
        entries: [previous, omitted],
        suggestions: [previousSuggestion, omittedSuggestion]
      )
    )
    try await target.setPriority(true, id: omitted.id)
    let targetBefore = try await target.publishedSnapshot()
    #expect(targetBefore.snapshot.revision == 2)

    let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let transfer = try await source.exportCanonicalTransfer(exportedAt: exportedAt)
    let preview = try await target.previewCanonicalImport(transfer)

    #expect(preview.sourceRevision == 1)
    #expect(preview.expectedLocalRevision == 2)
    #expect(preview.checkedTargetRevision == 3)
    #expect(preview.exportedAt == exportedAt)
    #expect(
      preview.effectiveContentDigest
        == (try await source.publishedSnapshot()).compiled.contentDigest
    )
    #expect(preview.conflictDiagnostics.isEmpty)
    #expect(
      preview.changes == [
        .updateEntry(current: previous, imported: updated),
        .addEntry(disabledUnsupported),
        .omitEntry(omitted.withPriority(true)),
        .updateSuggestion(current: previousSuggestion, imported: sourceSuggestion),
        .omitSuggestion(omittedSuggestion),
      ]
    )

    let confirmed = try await target.confirmCanonicalImport(preview)
    let sourcePublished = try await source.publishedSnapshot()
    #expect(confirmed.snapshot.revision == 3)
    #expect(confirmed.snapshot.entries == sourcePublished.snapshot.entries)
    #expect(confirmed.snapshot.suggestions == sourcePublished.snapshot.suggestions)
    #expect(confirmed.compiled.contentDigest == sourcePublished.compiled.contentDigest)
  }

  @Test func effectiveDigestIgnoresSourceRevisionAndExportTimestamp() async throws {
    let firstRoot = transferRoot()
    let secondRoot = transferRoot()
    let targetRoot = transferRoot()
    defer {
      try? FileManager.default.removeItem(at: firstRoot)
      try? FileManager.default.removeItem(at: secondRoot)
      try? FileManager.default.removeItem(at: targetRoot)
    }
    let entry = transferEntry(1, "Fleck")
    let first = PersonalDictionaryStore(rootURL: firstRoot)
    let second = PersonalDictionaryStore(rootURL: secondRoot)
    try await first.upsert(entry)
    try await second.upsert(entry)
    try await second.setPriority(true, id: entry.id)
    try await second.setPriority(false, id: entry.id)

    let firstData = try await first.exportCanonicalTransfer(
      exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let secondData = try await second.exportCanonicalTransfer(
      exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    #expect(firstData != secondData)

    let target = PersonalDictionaryStore(rootURL: targetRoot)
    let firstPreview = try await target.previewCanonicalImport(firstData)
    let secondPreview = try await target.previewCanonicalImport(secondData)
    #expect(firstPreview.sourceRevision == 1)
    #expect(secondPreview.sourceRevision == 3)
    #expect(firstPreview.effectiveContentDigest == secondPreview.effectiveContentDigest)
  }

  @Test func previewIsReadOnlyAndDiscardingItDoesNotCreateAuthorityOrRecovery() async throws {
    let sourceRoot = transferRoot()
    let targetRoot = transferRoot()
    defer {
      try? FileManager.default.removeItem(at: sourceRoot)
      try? FileManager.default.removeItem(at: targetRoot)
    }
    let source = PersonalDictionaryStore(rootURL: sourceRoot)
    try await source.upsert(transferEntry(1, "Fleck"))
    let transfer = try await source.exportCanonicalTransfer(
      exportedAt: Date(timeIntervalSince1970: 0)
    )
    let target = PersonalDictionaryStore(rootURL: targetRoot)

    #expect(!FileManager.default.fileExists(atPath: targetRoot.path))
    let preview = try await target.previewCanonicalImport(transfer)

    #expect(preview.expectedLocalRevision == 0)
    #expect(!FileManager.default.fileExists(atPath: targetRoot.path))
    #expect(!FileManager.default.fileExists(atPath: target.fileURL.path))
    #expect(
      !FileManager.default.fileExists(
        atPath: target.fileURL.appendingPathExtension("recovery").path
      )
    )
  }

  @Test func staleAndPrecancelledConfirmationPreservePublishedState() async throws {
    let sourceRoot = transferRoot()
    let targetRoot = transferRoot()
    defer {
      try? FileManager.default.removeItem(at: sourceRoot)
      try? FileManager.default.removeItem(at: targetRoot)
    }
    let source = PersonalDictionaryStore(rootURL: sourceRoot)
    try await source.upsert(transferEntry(1, "Imported"))
    let target = PersonalDictionaryStore(rootURL: targetRoot)
    try await target.upsert(transferEntry(2, "Local"))
    let transfer = try await source.exportCanonicalTransfer(
      exportedAt: Date(timeIntervalSince1970: 0)
    )
    let stale = try await target.previewCanonicalImport(transfer)
    try await target.upsert(transferEntry(3, "Winner"))
    let winner = try await transferState(target)

    await #expect(throws: PersonalDictionaryStoreError.revisionConflict) {
      try await target.confirmCanonicalImport(stale)
    }
    #expect(try await transferState(target) == winner)

    let current = try await target.previewCanonicalImport(transfer)
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await target.confirmCanonicalImport(current)
    }
    switch await cancelled.result {
    case .success:
      Issue.record("Expected pre-cancelled confirmation to fail")
    case .failure(let error):
      #expect(error is CancellationError)
    }
    #expect(try await transferState(target) == winner)
  }

  @Test func identicalHistoricalConflictsArePreservedAndConflictRemovalIsAllowed() async throws {
    let conflictedEntries = [
      transferEntry(1, "Fleck"),
      transferEntry(2, "FLECK"),
      transferEntry(3, "Safe"),
    ]
    let preserved = try await transferBetween(
      sourceEntries: conflictedEntries.reversed(),
      targetEntries: conflictedEntries,
      sourceRevisionBump: true
    )
    #expect(preserved.snapshot.entries == conflictedEntries)
    #expect(preserved.compiled.conflictIdentities.count == 1)

    let removed = try await transferBetween(
      sourceEntries: [transferEntry(3, "Safe")],
      targetEntries: conflictedEntries
    )
    #expect(removed.compiled.conflictIdentities.isEmpty)
  }

  @Test func newOrChangedConflictIdentityIsRejectedWithoutMutation() async throws {
    let cases: [(source: [PersonalDictionaryEntry], target: [PersonalDictionaryEntry])] = [
      (
        [transferEntry(1, "Fleck"), transferEntry(2, "FLECK")],
        [transferEntry(1, "Fleck")]
      ),
      (
        [transferEntry(1, "Fleck"), transferEntry(3, "FLECK")],
        [transferEntry(1, "Fleck"), transferEntry(2, "FLECK")]
      ),
      (
        [transferEntry(1, "Changed"), transferEntry(2, "CHANGED")],
        [transferEntry(1, "Fleck"), transferEntry(2, "FLECK")]
      ),
      (
        [
          transferEntry(1, "Preferred"),
          transferEntry(2, "Alias owner", aliases: ["PREFERRED"]),
        ],
        [transferEntry(1, "Preferred"), transferEntry(2, "Alias owner")]
      ),
      (
        [
          transferEntry(1, "Left", aliases: ["shared"]),
          transferEntry(2, "Right", aliases: ["SHARED"]),
        ],
        [transferEntry(1, "Left"), transferEntry(2, "Right")]
      ),
    ]

    for testCase in cases {
      let sourceRoot = transferRoot()
      let targetRoot = transferRoot()
      defer {
        try? FileManager.default.removeItem(at: sourceRoot)
        try? FileManager.default.removeItem(at: targetRoot)
      }
      let source = PersonalDictionaryStore(rootURL: sourceRoot)
      let target = PersonalDictionaryStore(rootURL: targetRoot)
      try seedTransferStore(source, entries: testCase.source)
      try seedTransferStore(target, entries: testCase.target)
      let transfer = try await source.exportCanonicalTransfer(
        exportedAt: Date(timeIntervalSince1970: 0)
      )
      let preview = try await target.previewCanonicalImport(transfer)
      #expect(preview.conflictDiagnostics.contains { $0.count > 0 })
      let before = try await transferState(target)

      await #expect(throws: PersonalDictionaryStoreError.conflictIntroduced) {
        try await target.confirmCanonicalImport(preview)
      }
      #expect(try await transferState(target) == before)
    }
  }

  @Test func malformedAndNoncanonicalTransfersAreRejectedWithoutMutation() async throws {
    let sourceRoot = transferRoot()
    let targetRoot = transferRoot()
    defer {
      try? FileManager.default.removeItem(at: sourceRoot)
      try? FileManager.default.removeItem(at: targetRoot)
    }
    let source = PersonalDictionaryStore(rootURL: sourceRoot)
    try await source.upsert(transferEntry(1, "PrivateTerm"))
    let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let valid = try await source.exportCanonicalTransfer(exportedAt: exportedAt)
    let validString = try #require(String(data: valid, encoding: .utf8))
    let snapshotBytes = try PersonalDictionaryCodec.encodeCanonicalJSON(
      (try await source.publishedSnapshot()).snapshot
    ).count
    let digest = (try await source.publishedSnapshot()).compiled.contentDigest
    let snapshotData = try PersonalDictionaryCodec.encodeCanonicalJSON(
      (try await source.publishedSnapshot()).snapshot
    )
    let snapshotString = String(decoding: snapshotData, as: UTF8.self)
    let reorderedSnapshot = snapshotString
      .replacingOccurrences(of: "{\"entries\":", with: "{\"revision\":1,\"entries\":")
      .replacingOccurrences(of: ",\"revision\":1,\"schemaVersion\":", with: ",\"schemaVersion\":")
    let csv = try PersonalDictionaryCodec.exportCSV([transferEntry(1, "PrivateTerm")])
    let firstComma = try #require(validString.firstIndex(of: ","))
    let withoutByteCount = "{" + validString[validString.index(after: firstComma)...]
    let reordered = validString.replacingOccurrences(
      of: "{\"byteCount\":\(snapshotBytes),\"compilerPolicyRevision\":1",
      with: "{\"compilerPolicyRevision\":1,\"byteCount\":\(snapshotBytes)"
    )
    let malformed: [Data] = [
      Data([0xFF]),
      Data(withoutByteCount.utf8),
      Data(
        validString.replacingOccurrences(
          of: "{\"byteCount\":",
          with: "{\"byteCount\":1,\"byteCount\":"
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: ",\"snapshot\":",
          with: ",\"path\":\"/private/path\",\"snapshot\":"
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: "\"exportedAt\":\"2023-11-14T22:13:20.000000000Z\"",
          with: "\"exportedAt\":\"invalid\""
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: "\"byteCount\":\(snapshotBytes)",
          with: "\"byteCount\":1.5"
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: "\"contentDigest\":\"\(digest)\"",
          with: "\"contentDigest\":1"
        ).utf8
      ),
      Data((" " + validString).utf8),
      Data(reordered.utf8),
      Data(validString.replacingOccurrences(of: snapshotString, with: reorderedSnapshot).utf8),
      Data(
        validString.replacingOccurrences(
          of: "\"byteCount\":\(snapshotBytes)",
          with: "\"byteCount\":\(snapshotBytes + 1)"
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: "\"localeIdentifier\":\"en-US\"",
          with: "\"localeIdentifier\":\"en-GB\""
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: "\"compilerPolicyRevision\":1",
          with: "\"compilerPolicyRevision\":2"
        ).utf8
      ),
      Data(
        validString.replacingOccurrences(
          of: digest,
          with: String(repeating: "0", count: 64)
        ).utf8
      ),
      Data(csv.utf8),
      Data(repeating: 0x20, count: 64 * 1024 + 257),
    ]

    let target = PersonalDictionaryStore(rootURL: targetRoot)
    try await target.upsert(transferEntry(9, "Local"))
    let before = try await transferState(target)
    for data in malformed {
      await #expect(throws: PersonalDictionaryStoreError.invalidTransfer) {
        try await target.previewCanonicalImport(data)
      }
      #expect(try await transferState(target) == before)
    }
  }
}

private struct TransferStoreState: Equatable {
  let authority: Data?
  let recovery: Data?
  let published: PersonalDictionaryPublishedSnapshot
}

private func transferState(_ store: PersonalDictionaryStore) async throws -> TransferStoreState {
  TransferStoreState(
    authority: try? Data(contentsOf: store.fileURL),
    recovery: try? Data(contentsOf: store.fileURL.appendingPathExtension("recovery")),
    published: try await store.publishedSnapshot()
  )
}

private func transferBetween(
  sourceEntries: [PersonalDictionaryEntry],
  targetEntries: [PersonalDictionaryEntry],
  sourceRevisionBump: Bool = false
) async throws -> PersonalDictionaryPublishedSnapshot {
  let sourceRoot = transferRoot()
  let targetRoot = transferRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try seedTransferStore(source, entries: sourceEntries)
  if sourceRevisionBump, let first = sourceEntries.first {
    try await source.setPriority(true, id: first.id)
    try await source.setPriority(false, id: first.id)
  }
  try seedTransferStore(target, entries: targetEntries)
  let data = try await source.exportCanonicalTransfer(
    exportedAt: Date(timeIntervalSince1970: 0)
  )
  let preview = try await target.previewCanonicalImport(data)
  return try await target.confirmCanonicalImport(preview)
}

private func seedTransferStore(
  _ store: PersonalDictionaryStore,
  entries: [PersonalDictionaryEntry]
) throws {
  try FileManager.default.createDirectory(
    at: store.fileURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try PersonalDictionaryCodec.encodeCanonicalJSON(
    PersonalDictionarySnapshotV2(revision: 1, entries: entries)
  ).write(to: store.fileURL)
}

private func transferRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckDictionaryTransferTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func transferID(_ value: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

private func transferEntry(
  _ value: Int,
  _ preferredForm: String,
  aliases: [String] = [],
  locale: String = "en-US",
  enabled: Bool = true,
  origin: PersonalDictionaryOrigin = .manual
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: transferID(value),
    preferredForm: preferredForm,
    aliases: aliases,
    localeIdentifier: locale,
    isPriority: false,
    isEnabled: enabled,
    origin: origin,
    usage: .init()
  )
}

private func transferSuggestion(_ value: Int, _ preferredForm: String) -> PersonalDictionarySuggestion {
  PersonalDictionarySuggestion(
    id: transferID(value),
    preferredForm: preferredForm,
    observedForms: [preferredForm.lowercased()],
    localeIdentifier: "en-US",
    observationCount: 1,
    lastObservedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private extension PersonalDictionaryEntry {
  func withPriority(_ isPriority: Bool) -> PersonalDictionaryEntry {
    var copy = self
    copy.isPriority = isPriority
    return copy
  }
}
