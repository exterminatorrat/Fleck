import Foundation
import Testing

@testable import FleckCore

@Test func personalDictionaryStoreMissingFileLoadsEmptyWithoutCreatingDirectory() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let store = PersonalDictionaryStore(rootURL: root)

  #expect(try await store.snapshot() == PersonalDictionarySnapshot())
  #expect(
    !FileManager.default.fileExists(
      atPath: root.appendingPathComponent("PersonalDictionary").path
    )
  )
}

@Test func personalDictionaryStoreRoundTripsAcrossRelaunchAndUsesOneAtomicFile() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let entry = dictionaryStoreEntry(preferredForm: "Fleck", aliases: ["flec"])
  let first = PersonalDictionaryStore(rootURL: root)
  try await first.upsert(entry)

  let second = PersonalDictionaryStore(rootURL: root)
  #expect(try await second.snapshot().entries == [entry])

  let dictionaryURL = root.appendingPathComponent("PersonalDictionary", isDirectory: true)
  let files = try FileManager.default.contentsOfDirectory(
    at: dictionaryURL,
    includingPropertiesForKeys: nil
  )
  #expect(files.map(\.lastPathComponent) == ["dictionary-v1.json"])
}

@Test func personalDictionaryStoreSupportsCRUDAndStateChanges() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let store = PersonalDictionaryStore(rootURL: root)
  let entry = dictionaryStoreEntry(preferredForm: "Fleck")
  try await store.upsert(entry)
  try await store.setEnabled(false, id: entry.id)
  try await store.setPriority(true, id: entry.id)

  var saved = try await store.snapshot().entries[0]
  #expect(saved.isEnabled == false)
  #expect(saved.isPriority == true)

  saved.preferredForm = "FleckApp"
  try await store.upsert(saved)
  #expect(try await store.snapshot().entries[0].preferredForm == "FleckApp")

  try await store.delete(id: entry.id)
  #expect(try await store.snapshot().entries.isEmpty)
}

@Test func personalDictionaryStoreApprovesAndDismissesSuggestionsExplicitly() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let store = PersonalDictionaryStore(rootURL: root)
  let suggestion = PersonalDictionarySuggestion(
    id: UUID(),
    preferredForm: "camelCase",
    observedForms: ["camel case"],
    localeIdentifier: "en-US",
    observationCount: 4,
    lastObservedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
  try await store.recordSuggestion(suggestion)

  let approved = try await store.approveSuggestion(id: suggestion.id)
  #expect(approved.id == suggestion.id)
  #expect(approved.origin == .suggested)
  #expect(approved.isEnabled)
  #expect(approved.aliases == suggestion.observedForms)
  #expect(try await store.snapshot().suggestions.isEmpty)

  let dismissed = PersonalDictionarySuggestion(
    preferredForm: "PascalCase",
    observedForms: ["pascal case"]
  )
  try await store.recordSuggestion(dismissed)
  try await store.dismissSuggestion(id: dismissed.id)
  #expect(try await store.snapshot().suggestions.isEmpty)
}

@Test func personalDictionaryStoreFailsClosedForCorruptAndFutureFiles() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("PersonalDictionary", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent("dictionary-v1.json")

  try Data("not json".utf8).write(to: file)
  let corrupt = PersonalDictionaryStore(rootURL: root)
  await #expect(throws: PersonalDictionaryStoreError.corruptData) {
    try await corrupt.snapshot()
  }
  await #expect(throws: PersonalDictionaryStoreError.corruptData) {
    try await corrupt.upsert(dictionaryStoreEntry(preferredForm: "Fleck"))
  }
  #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "not json")

  try Data(
    "{\"entries\":[],\"schemaVersion\":2,\"suggestions\":[]}".utf8
  ).write(to: file, options: .atomic)
  let futureStore = PersonalDictionaryStore(rootURL: root)
  await #expect(throws: PersonalDictionaryStoreError.unsupportedSchemaVersion) {
    try await futureStore.snapshot()
  }
}

@Test func personalDictionaryStoreReplacesOnlyValidSnapshots() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let valid = PersonalDictionarySnapshot(
    entries: [dictionaryStoreEntry(preferredForm: "Fleck")]
  )
  try await store.replace(with: valid)
  #expect(try await store.snapshot() == valid)

  let invalid = PersonalDictionarySnapshot(
    entries: [dictionaryStoreEntry(preferredForm: " ", aliases: [""])]
  )
  await #expect(throws: PersonalDictionaryStoreError.invalidSnapshot) {
    try await store.replace(with: invalid)
  }
  #expect(try await store.snapshot() == valid)
}

@Test func personalDictionaryStoreRejectsOversizedValidFilesBeforeDecoding() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("PersonalDictionary", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent("dictionary-v1.json")
  let oversizedSnapshot = PersonalDictionarySnapshot(
    entries: [
      PersonalDictionaryEntry(
        preferredForm: String(repeating: "a", count: 64 * 1024)
      )
    ]
  )
  let oversizedData = try PersonalDictionaryCodec.encodeJSON(oversizedSnapshot)
  #expect(oversizedData.count > 64 * 1024)
  try oversizedData.write(to: file)

  let store = PersonalDictionaryStore(rootURL: root)
  await #expect(throws: PersonalDictionaryStoreError.corruptData) {
    try await store.snapshot()
  }
}

@Test func personalDictionaryStoreRejectsOversizedReplaceWithoutTouchingExistingFile() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let valid = PersonalDictionarySnapshot(
    entries: [dictionaryStoreEntry(preferredForm: "Fleck")]
  )
  try await store.replace(with: valid)
  let originalBytes = try Data(contentsOf: store.fileURL)

  let oversized = PersonalDictionarySnapshot(
    entries: [
      PersonalDictionaryEntry(
        preferredForm: String(repeating: "a", count: 64 * 1024)
      )
    ]
  )
  await #expect(throws: PersonalDictionaryStoreError.fileTooLarge) {
    try await store.replace(with: oversized)
  }

  #expect(try Data(contentsOf: store.fileURL) == originalBytes)
  let freshStore = PersonalDictionaryStore(rootURL: root)
  #expect(try await freshStore.snapshot() == valid)
}

private func temporaryDictionaryRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckDictionaryStoreTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func dictionaryStoreEntry(
  id: UUID = UUID(),
  preferredForm: String,
  aliases: [String] = []
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: id,
    preferredForm: preferredForm,
    aliases: aliases,
    localeIdentifier: "en-US",
    isPriority: false,
    isEnabled: true,
    origin: .manual,
    usage: .init()
  )
}
