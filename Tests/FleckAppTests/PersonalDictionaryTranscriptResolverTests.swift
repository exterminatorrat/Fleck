import Foundation
import FleckCore
import Testing

@testable import FleckApp

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
