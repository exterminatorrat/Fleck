import Foundation
import FleckCore
import Testing

@testable import FleckApp

private func resolverCaptureContext(
  captureID: UUID = UUID(),
  generation: UInt64 = 1,
  revision: UInt64,
  entry: PersonalDictionaryEntry
) throws -> LocalWritingCaptureContext {
  let snapshot = PersonalDictionarySnapshotV2(revision: revision, entries: [entry])
  return try LocalWritingCaptureContext(
    captureID: captureID,
    generation: generation,
    localeIdentifier: "en-US",
    speechEngine: .standard,
    snapshot: snapshot,
    compiledDictionary: CompiledPersonalDictionary.compile(snapshot)
  )
}

@Test
func resolverPinnedDictionaryMutationAppliesOnlyToNextCapture() async throws {
  let entry = PersonalDictionaryEntry(
    preferredForm: "FleckApp",
    aliases: ["fleck app"]
  )
  let replacement = PersonalDictionaryEntry(
    id: entry.id,
    preferredForm: "Fleck",
    aliases: ["fleck app"]
  )
  let pinned = try resolverCaptureContext(revision: 4, entry: entry)
  let next = try resolverCaptureContext(revision: 5, entry: replacement)
  let resolver = PersonalDictionaryTranscriptResolver()

  let current = try await resolver.resolve("open fleck app", context: pinned)
  let following = try await resolver.resolve("open fleck app", context: next)

  #expect(current.baseline == "open FleckApp")
  #expect(current.protectedForms == ["FleckApp"])
  #expect(current.appliedEntryIDs == [entry.id])
  #expect(current.dictionaryRevision == 4)
  #expect(current.dictionaryContentDigest == pinned.dictionaryContentDigest)
  #expect(following.baseline == "open Fleck")
  #expect(following.dictionaryRevision == 5)
}

@Test
func resolverDictionaryContextRejectsIdentityMismatches() throws {
  let entry = PersonalDictionaryEntry(
    preferredForm: "FleckApp",
    aliases: ["fleck app"]
  )
  let snapshot = PersonalDictionarySnapshotV2(revision: 7, entries: [entry])
  let mismatched = PersonalDictionarySnapshotV2(revision: 8, entries: [entry])
  let compiled = try CompiledPersonalDictionary.compile(mismatched)

  #expect(throws: LocalWritingCaptureContextError.dictionaryRevisionMismatch) {
    try LocalWritingCaptureContext(
      captureID: UUID(),
      generation: 1,
      localeIdentifier: "en-US",
      speechEngine: .standard,
      snapshot: snapshot,
      compiledDictionary: compiled
    )
  }
  #expect(throws: LocalWritingCaptureContextError.localeMismatch) {
    try LocalWritingCaptureContext(
      captureID: UUID(),
      generation: 1,
      localeIdentifier: "fr-FR",
      speechEngine: .standard,
      snapshot: mismatched,
      compiledDictionary: compiled
    )
  }
}

@Test
func resolverDictionaryContextRejectsSameRevisionContentDrift() throws {
  let revision: UInt64 = 9
  let snapshot = PersonalDictionarySnapshotV2(
    revision: revision,
    entries: [PersonalDictionaryEntry(preferredForm: "FleckApp", aliases: ["fleck app"])]
  )
  let differentSnapshot = PersonalDictionarySnapshotV2(
    revision: revision,
    entries: [PersonalDictionaryEntry(preferredForm: "Fleck", aliases: ["fleck app"])]
  )

  #expect(throws: LocalWritingCaptureContextError.dictionaryContentMismatch) {
    try LocalWritingCaptureContext(
      captureID: UUID(),
      generation: 1,
      localeIdentifier: "en-US",
      speechEngine: .standard,
      snapshot: snapshot,
      compiledDictionary: CompiledPersonalDictionary.compile(differentSnapshot)
    )
  }
}

@Test
func resolverPreservesTheRawBaselineWithNoEntries() async throws {
  let resolver = PersonalDictionaryTranscriptResolver(entries: { [] })

  let result = try await resolver.resolve("say the report")

  #expect(result == .init(
    baseline: "say the report",
    protectedForms: [],
    replacements: 0
  ))
}

@Test
func resolverUsesTheExactPreferredFormFromTheResolutionCore() async throws {
  let entry = PersonalDictionaryEntry(
    preferredForm: "FleckApp",
    aliases: ["fleck app"]
  )
  let resolver = PersonalDictionaryTranscriptResolver(entries: { [entry] })

  let result = try await resolver.resolve("open fleck app")

  #expect(result.baseline == "open FleckApp")
  #expect(result.protectedForms == ["FleckApp"])
  #expect(result.replacements == 1)
}

private enum ResolverProbeError: Error, Equatable {
  case failed
}

@Test
func resolverPropagatesResolutionFailure() async throws {
  let resolver = PersonalDictionaryTranscriptResolver(
    entries: { [] },
    resolveEntries: { _, _ in throw ResolverProbeError.failed }
  )

  await #expect(throws: ResolverProbeError.failed) {
    try await resolver.resolve("raw")
  }
}

@Test
func resolverLoadsCurrentStoreEntriesForEveryCapture() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckResolverTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = PersonalDictionaryStore(rootURL: root)
  let entry = PersonalDictionaryEntry(
    preferredForm: "FleckApp",
    aliases: ["fleck app"]
  )
  let resolver = PersonalDictionaryTranscriptResolver(entries: {
    try await store.snapshot().entries
  })

  #expect(try await resolver.resolve("open fleck app").baseline == "open fleck app")
  try await store.upsert(entry)
  #expect(try await resolver.resolve("open fleck app").baseline == "open FleckApp")
  try await store.setEnabled(false, id: entry.id)
  #expect(try await resolver.resolve("open fleck app").baseline == "open fleck app")
}

@Test
func resolverPropagatesDictionaryLoadFailure() async {
  let resolver = PersonalDictionaryTranscriptResolver(entries: {
    throw ResolverProbeError.failed
  })

  await #expect(throws: ResolverProbeError.failed) {
    try await resolver.resolve("raw")
  }
}

@Test
func resolverDoesNotTurnCorruptStoreDataIntoAnEmptyDictionary() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckResolverTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("PersonalDictionary", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("not json".utf8).write(
    to: directory.appendingPathComponent("dictionary-v1.json")
  )

  let store = PersonalDictionaryStore(rootURL: root)
  let resolver = PersonalDictionaryTranscriptResolver(entries: {
    try await store.snapshot().entries
  })

  await #expect(throws: PersonalDictionaryStoreError.corruptData) {
    try await resolver.resolve("raw")
  }
}
