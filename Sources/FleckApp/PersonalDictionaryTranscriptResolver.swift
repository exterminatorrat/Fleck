import Foundation
import FleckCore

struct PersonalDictionaryTranscriptResolver: TranscriptDictionaryResolving {
  private let entries: (@Sendable () async throws -> [PersonalDictionaryEntry])?
  private let resolveEntries:
    @Sendable (String, [PersonalDictionaryEntry]) throws
      -> PersonalDictionaryResolution

  init() {
    entries = nil
    resolveEntries = { raw, entries in
      try PersonalDictionaryResolver.resolve(raw, entries: entries)
    }
  }

  init(
    entries: @escaping @Sendable () async throws -> [PersonalDictionaryEntry],
    resolveEntries: @escaping @Sendable (String, [PersonalDictionaryEntry])
      throws -> PersonalDictionaryResolution =
      { raw, entries in try PersonalDictionaryResolver.resolve(
        raw, entries: entries
      ) }
  ) {
    self.entries = entries
    self.resolveEntries = resolveEntries
  }

  func resolve(_ rawTranscript: String) async throws
    -> PersonalDictionaryResolution {
    try resolveEntries(rawTranscript, try await entries?() ?? [])
  }

  func resolve(
    _ rawTranscript: String,
    context: LocalWritingCaptureContext
  ) async throws -> PersonalDictionaryResolution {
    PersonalDictionaryResolver.resolve(
      rawTranscript,
      compiled: context.compiledDictionary
    )
  }
}
