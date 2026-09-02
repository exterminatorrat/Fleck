import Darwin
import Foundation
import Testing

@testable import FleckCore

@Test func personalDictionaryStoreMissingFileLoadsEmptyUnderPersistentLock() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let first = PersonalDictionaryStore(rootURL: root)

  #expect(try await first.snapshot() == PersonalDictionarySnapshot())
  #expect(!FileManager.default.fileExists(atPath: first.fileURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: first.fileURL.appendingPathExtension("lock").path
    )
  )

  let entry = dictionaryStoreEntry(preferredForm: "Fleck")
  let second = PersonalDictionaryStore(rootURL: root)
  try await second.upsert(entry)
  let refreshed = try await first.publishedSnapshot()
  #expect(refreshed.snapshot.revision == 1)
  #expect(refreshed.snapshot.entries == [entry])
  #expect(refreshed.compiled == (try CompiledPersonalDictionary.compile(refreshed.snapshot)))
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
  #expect(
    files.map(\.lastPathComponent).sorted() == [
      "dictionary-v1.json",
      "dictionary-v1.json.lock",
    ]
  )
  let lockAttributes = try FileManager.default.attributesOfItem(
    atPath: first.fileURL.appendingPathExtension("lock").path
  )
  #expect(lockAttributes[.type] as? FileAttributeType == .typeRegular)
  #expect(lockAttributes[.ownerAccountID] as? NSNumber == NSNumber(value: geteuid()))
  #expect(lockAttributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600))
  #expect(
    try PersonalDictionaryCodec.decodePublishedJSON(Data(contentsOf: first.fileURL)).revision == 1
  )

  let concurrentEntry = dictionaryStoreEntry(preferredForm: "OpenAI")
  try await second.upsert(concurrentEntry)
  let refreshed = try await first.publishedSnapshot()
  #expect(refreshed.snapshot.revision == 2)
  #expect(Set(refreshed.snapshot.entries.map(\.id)) == [entry.id, concurrentEntry.id])
  #expect(refreshed.compiled == (try CompiledPersonalDictionary.compile(refreshed.snapshot)))
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

  let publishedBeforeMissingDelete = try await store.publishedSnapshot()
  let bytesBeforeMissingDelete = try Data(contentsOf: store.fileURL)
  try await store.delete(id: UUID())
  #expect(try Data(contentsOf: store.fileURL) == bytesBeforeMissingDelete)
  #expect(try await store.publishedSnapshot() == publishedBeforeMissingDelete)
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
  let futureBytes = try Data(contentsOf: file)
  let futureStore = PersonalDictionaryStore(rootURL: root)
  await #expect(throws: PersonalDictionaryStoreError.unsupportedSchemaVersion) {
    try await futureStore.snapshot()
  }
  await #expect(throws: PersonalDictionaryStoreError.unsupportedSchemaVersion) {
    try await futureStore.upsert(dictionaryStoreEntry(preferredForm: "Fleck"))
  }
  #expect(try Data(contentsOf: file) == futureBytes)

  let symlinkRoot = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: symlinkRoot) }
  let symlinkDirectory = symlinkRoot.appendingPathComponent(
    "PersonalDictionary",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: symlinkDirectory,
    withIntermediateDirectories: true
  )
  let lockTarget = symlinkRoot.appendingPathComponent("lock-target")
  try Data("lock sentinel".utf8).write(to: lockTarget)
  let originalTargetAttributes = try FileManager.default.attributesOfItem(atPath: lockTarget.path)
  try FileManager.default.createSymbolicLink(
    at: symlinkDirectory.appendingPathComponent("dictionary-v1.json.lock"),
    withDestinationURL: lockTarget
  )

  let symlinkStore = PersonalDictionaryStore(rootURL: symlinkRoot)
  await #expect(throws: PersonalDictionaryStoreError.publicationFailed) {
    try await symlinkStore.upsert(dictionaryStoreEntry(preferredForm: "Fleck"))
  }
  #expect(try Data(contentsOf: lockTarget) == Data("lock sentinel".utf8))
  #expect(
    try FileManager.default.attributesOfItem(atPath: lockTarget.path)[.posixPermissions]
      as? NSNumber == originalTargetAttributes[.posixPermissions] as? NSNumber
  )
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
  let originalBytes = try Data(contentsOf: file)

  let store = PersonalDictionaryStore(rootURL: root)
  await #expect(throws: PersonalDictionaryStoreError.fileTooLarge) {
    try await store.snapshot()
  }
  await #expect(throws: PersonalDictionaryStoreError.fileTooLarge) {
    try await store.upsert(dictionaryStoreEntry(preferredForm: "Fleck"))
  }
  #expect(try Data(contentsOf: file) == originalBytes)
}

@Test func personalDictionaryStoreAcceptsExactly64KiBAndRejectsTheNextByte() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("PersonalDictionary", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent("dictionary-v1.json")
  let entryID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
  let baseSnapshot = PersonalDictionarySnapshot(
    entries: [PersonalDictionaryEntry(id: entryID, preferredForm: "a")]
  )
  let baseData = try PersonalDictionaryCodec.encodeJSON(baseSnapshot)
  let boundarySnapshot = PersonalDictionarySnapshot(
    entries: [
      PersonalDictionaryEntry(
        id: entryID,
        preferredForm: String(repeating: "a", count: 64 * 1024 - baseData.count + 1)
      )
    ]
  )
  let boundaryData = try PersonalDictionaryCodec.encodeJSON(boundarySnapshot)
  #expect(boundaryData.count == 64 * 1024)
  try boundaryData.write(to: file)

  let boundaryStore = PersonalDictionaryStore(rootURL: root)
  #expect(try await boundaryStore.snapshot() == boundarySnapshot)

  var oversizedData = boundaryData
  oversizedData.append(0)
  #expect(oversizedData.count == 64 * 1024 + 1)
  try oversizedData.write(to: file)
  let oversizedStore = PersonalDictionaryStore(rootURL: root)
  await #expect(throws: PersonalDictionaryStoreError.fileTooLarge) {
    try await oversizedStore.snapshot()
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

@Test func personalDictionaryStoreRejectsDirectConflictIntroductionAcrossMutationPaths() async throws {
  let root = temporaryDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let first = dictionaryStoreEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
    preferredForm: "Fleck"
  )
  let second = dictionaryStoreEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
    preferredForm: "FLECK"
  )
  try await store.upsert(first)
  let before = try await store.publishedSnapshot()
  let bytes = try Data(contentsOf: store.fileURL)

  await #expect(throws: PersonalDictionaryStoreError.conflictIntroduced) {
    try await store.upsert(second)
  }
  #expect(try Data(contentsOf: store.fileURL) == bytes)
  #expect(try await store.publishedSnapshot() == before)

  let disabled = PersonalDictionaryEntry(
    id: second.id,
    preferredForm: second.preferredForm,
    isEnabled: false
  )
  try await store.upsert(disabled)
  let disabledPublished = try await store.publishedSnapshot()
  await #expect(throws: PersonalDictionaryStoreError.conflictIntroduced) {
    try await store.setEnabled(true, id: disabled.id)
  }
  #expect(try await store.publishedSnapshot() == disabledPublished)
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
