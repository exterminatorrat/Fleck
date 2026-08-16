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
