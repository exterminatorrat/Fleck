import Foundation
import Testing

@testable import FleckCore

@Suite struct PersonalDictionaryPublicationTests {
  @Test func compileFailureAfterStagingPreservesAuthorityAndCompiledSnapshot() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = PersonalDictionaryStore(rootURL: root)
    try await original.upsert(publicationEntry(1, "Fleck"))
    let bytes = try Data(contentsOf: original.fileURL)
    let published = try await original.publishedSnapshot()
    let failing = PersonalDictionaryStore(
      rootURL: root,
      compiler: { _ in throw PublicationTestError.injected },
      publicationHook: { _, _ in }
    )

    await #expect(throws: PersonalDictionaryStoreError.publicationFailed) {
      try await failing.upsert(publicationEntry(2, "OpenAI"))
    }

    #expect(try Data(contentsOf: original.fileURL) == bytes)
    #expect(try await original.publishedSnapshot() == published)
    #expect(try publicationStageNames(beside: original.fileURL).isEmpty)
  }

  @Test func failureBeforeAtomicReplacePreservesAuthorityAndCompiledSnapshot() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = PersonalDictionaryStore(rootURL: root)
    try await original.upsert(publicationEntry(1, "Fleck"))
    let bytes = try Data(contentsOf: original.fileURL)
    let published = try await original.publishedSnapshot()
    let failing = PersonalDictionaryStore(
      rootURL: root,
      compiler: CompiledPersonalDictionary.compile,
      publicationHook: { point, _ in
        if point == .beforeReplace { throw PublicationTestError.injected }
      }
    )

    await #expect(throws: PersonalDictionaryStoreError.publicationFailed) {
      try await failing.upsert(publicationEntry(2, "OpenAI"))
    }

    #expect(try Data(contentsOf: original.fileURL) == bytes)
    #expect(try await original.publishedSnapshot() == published)
    #expect(try publicationStageNames(beside: original.fileURL).isEmpty)
  }

  @Test func corruptStagedReadbackPreservesAuthorityAndCompiledSnapshot() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = PersonalDictionaryStore(rootURL: root)
    try await original.upsert(publicationEntry(1, "Fleck"))
    let bytes = try Data(contentsOf: original.fileURL)
    let published = try await original.publishedSnapshot()
    let failing = PersonalDictionaryStore(
      rootURL: root,
      compiler: CompiledPersonalDictionary.compile,
      publicationHook: { point, stageURL in
        if point == .afterStageSync {
          try Data("corrupt".utf8).write(to: stageURL)
        }
      }
    )

    await #expect(throws: PersonalDictionaryStoreError.publicationFailed) {
      try await failing.upsert(publicationEntry(2, "OpenAI"))
    }

    #expect(try Data(contentsOf: original.fileURL) == bytes)
    #expect(try await original.publishedSnapshot() == published)
    #expect(try publicationStageNames(beside: original.fileURL).isEmpty)
  }

  @Test func staleExpectedRevisionAcrossInstancesPreservesWinner() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = PersonalDictionaryStore(rootURL: root)
    let stale = PersonalDictionaryStore(rootURL: root)
    let winner = try await first.mutate(
      expectedRevision: 0,
      .upsert(publicationEntry(1, "Winner"))
    )
    let winnerBytes = try Data(contentsOf: first.fileURL)

    await #expect(throws: PersonalDictionaryStoreError.revisionConflict) {
      try await stale.mutate(
        expectedRevision: 0,
        .upsert(publicationEntry(2, "Loser"))
      )
    }

    #expect(try Data(contentsOf: first.fileURL) == winnerBytes)
    #expect(try await PersonalDictionaryStore(rootURL: root).publishedSnapshot() == winner)
  }

  @Test func revisionOverflowPreservesAuthorityAndCompiledSnapshot() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = publicationFile(in: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let maximum = PersonalDictionarySnapshotV2(
      revision: UInt64.max,
      entries: [publicationEntry(1, "Maximum")]
    )
    let bytes = try PersonalDictionaryCodec.encodeCanonicalJSON(maximum)
    try bytes.write(to: file)
    let store = PersonalDictionaryStore(rootURL: root)
    let published = try await store.publishedSnapshot()

    await #expect(throws: PersonalDictionaryStoreError.revisionOverflow) {
      try await store.mutate(
        expectedRevision: UInt64.max,
        .upsert(publicationEntry(2, "Overflow"))
      )
    }

    #expect(try Data(contentsOf: file) == bytes)
    #expect(try await store.publishedSnapshot() == published)
  }

  @Test func recoveryCopyIsBoundedAndNeverAuthoritative() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(rootURL: root)
    try await store.upsert(publicationEntry(1, "First"))
    let priorBytes = try Data(contentsOf: store.fileURL)
    let failing = PersonalDictionaryStore(
      rootURL: root,
      compiler: CompiledPersonalDictionary.compile,
      publicationHook: { point, _ in
        if point == .beforeReplace { throw PublicationTestError.injected }
      }
    )

    await #expect(throws: PersonalDictionaryStoreError.publicationFailed) {
      try await failing.upsert(publicationEntry(2, "Second"))
    }

    let recoveryURL = store.fileURL.appendingPathExtension("recovery")
    let recoveryBytes = try Data(contentsOf: recoveryURL)
    #expect(recoveryBytes == priorBytes)
    #expect(recoveryBytes.count <= 65_536)
    try Data("broken authority".utf8).write(to: store.fileURL)
    let fresh = PersonalDictionaryStore(rootURL: root)
    await #expect(throws: PersonalDictionaryStoreError.corruptData) {
      try await fresh.publishedSnapshot()
    }
  }

  @Test func canonicalV1MigrationPublishesRevisionOneWithCompiledParity() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = publicationFile(in: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let legacy = PersonalDictionarySnapshot(
      entries: [publicationEntry(2, "OpenAI"), publicationEntry(1, "Fleck")]
    )
    try PersonalDictionaryCodec.encodeJSON(legacy).write(to: file)
    let store = PersonalDictionaryStore(rootURL: root)

    let published = try await store.publishedSnapshot()
    let bytes = try Data(contentsOf: file)
    let decoded = try PersonalDictionaryCodec.decodePublishedJSON(bytes)

    #expect(published.snapshot.revision == 1)
    #expect(decoded == published.snapshot)
    #expect(published.compiled == (try CompiledPersonalDictionary.compile(decoded)))
    #expect(try await store.snapshot().entries.map(\.id) == [publicationID(1), publicationID(2)])
    #expect(try await store.snapshot().suggestions == legacy.suggestions)
  }

  @Test func concurrentImportAndSuggestionEditHasExactlyOneWinner() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let importer = PersonalDictionaryStore(rootURL: root)
    let suggester = PersonalDictionaryStore(rootURL: root)
    let imported = PersonalDictionarySnapshot(
      entries: [publicationEntry(1, "Imported")]
    )
    let suggestion = PersonalDictionarySuggestion(
      id: publicationID(2),
      preferredForm: "Suggested",
      observedForms: ["suggested"]
    )

    async let importResult = publicationAttempt(
      importer,
      expectedRevision: 0,
      mutation: .replace(imported)
    )
    async let suggestionResult = publicationAttempt(
      suggester,
      expectedRevision: 0,
      mutation: .recordSuggestion(suggestion)
    )
    let results = await [importResult, suggestionResult]
    let successes = results.compactMap { try? $0.get() }
    let conflicts = results.compactMap { result -> PersonalDictionaryStoreError? in
      guard case .failure(let error) = result else { return nil }
      return error
    }
    let winner = try await PersonalDictionaryStore(rootURL: root).publishedSnapshot()

    #expect(successes.count == 1)
    #expect(conflicts == [.revisionConflict])
    #expect(winner.snapshot.revision == 1)
    #expect((winner.snapshot.entries.isEmpty) != (winner.snapshot.suggestions.isEmpty))
  }

  @Test func publishedBytesStrictlyDecodeToPublishedCompiledIdentity() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(rootURL: root)
    try await store.upsert(publicationEntry(2, "OpenAI"))
    try await store.upsert(publicationEntry(1, "Fleck"))

    let published = try await store.publishedSnapshot()
    let bytes = try Data(contentsOf: store.fileURL)
    let decoded = try PersonalDictionaryCodec.decodePublishedJSON(bytes)

    #expect(decoded == published.snapshot)
    #expect(try PersonalDictionaryCodec.encodeCanonicalJSON(decoded) == bytes)
    #expect(published.compiled.revision == decoded.revision)
    #expect(published.compiled == (try CompiledPersonalDictionary.compile(decoded)))
  }

  @Test func everyLegacyMutationUsesCompileBeforePublish() async throws {
    let root = publicationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let counter = PublicationCompilerCounter()
    let store = PersonalDictionaryStore(
      rootURL: root,
      compiler: { snapshot in
        counter.increment()
        return try CompiledPersonalDictionary.compile(snapshot)
      },
      publicationHook: { _, _ in }
    )
    let entry = publicationEntry(1, "Fleck")
    let approved = publicationSuggestion(2, "Approved")
    let dismissed = publicationSuggestion(3, "Dismissed")

    try await store.upsert(entry)
    try await store.setEnabled(false, id: entry.id)
    try await store.setPriority(true, id: entry.id)
    try await store.recordSuggestion(approved)
    _ = try await store.approveSuggestion(id: approved.id)
    try await store.recordSuggestion(dismissed)
    try await store.dismissSuggestion(id: dismissed.id)
    try await store.replace(with: PersonalDictionarySnapshot(entries: [entry]))
    try await store.delete(id: entry.id)

    let published = try await store.publishedSnapshot()
    #expect(counter.value == 9)
    #expect(published.snapshot.revision == 9)
    #expect(published.compiled.revision == 9)
  }
}

private enum PublicationTestError: Error {
  case injected
}

private final class PublicationCompilerCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }

  func increment() {
    lock.withLock { count += 1 }
  }
}

private func publicationAttempt(
  _ store: PersonalDictionaryStore,
  expectedRevision: UInt64,
  mutation: PersonalDictionaryMutation
) async -> Result<PersonalDictionaryPublishedSnapshot, PersonalDictionaryStoreError> {
  do {
    return .success(try await store.mutate(expectedRevision: expectedRevision, mutation))
  } catch let error as PersonalDictionaryStoreError {
    return .failure(error)
  } catch {
    return .failure(.publicationFailed)
  }
}

private func publicationRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckDictionaryPublicationTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func publicationFile(in root: URL) -> URL {
  root.appendingPathComponent("PersonalDictionary", isDirectory: true)
    .appendingPathComponent("dictionary-v1.json")
}

private func publicationStageNames(beside fileURL: URL) throws -> [String] {
  try FileManager.default.contentsOfDirectory(
    at: fileURL.deletingLastPathComponent(),
    includingPropertiesForKeys: nil
  ).map(\.lastPathComponent).filter { $0.contains(".stage.") }
}

private func publicationID(_ value: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

private func publicationEntry(
  _ value: Int,
  _ preferredForm: String
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: publicationID(value),
    preferredForm: preferredForm,
    aliases: [preferredForm.lowercased()],
    localeIdentifier: "en-US"
  )
}

private func publicationSuggestion(
  _ value: Int,
  _ preferredForm: String
) -> PersonalDictionarySuggestion {
  PersonalDictionarySuggestion(
    id: publicationID(value),
    preferredForm: preferredForm,
    observedForms: [preferredForm.lowercased()]
  )
}
