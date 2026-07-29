import Foundation
import Testing

@testable import FleckCore

@Test func dictationHistoryStoreWritesOneSortedJSONRecordWithoutAudioKeys() async throws {
  let root = temporaryHistoryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let store = DictationHistoryStore(rootURL: root, now: { Date(timeIntervalSince1970: 1_700_000_000) })
  let record = historyRecord()

  try await store.save(record)

  let historyURL = root.appendingPathComponent("DictationHistory", isDirectory: true)
  let files = try FileManager.default.contentsOfDirectory(
    at: historyURL,
    includingPropertiesForKeys: nil
  )
  #expect(files.map(\.lastPathComponent) == ["\(record.id.uuidString.lowercased()).json"])

  let data = try Data(contentsOf: try #require(files.first))
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let keys = serializedKeys(in: object)
  let rootKeys = rootJSONKeys(in: data)
  #expect(rootKeys == rootKeys.sorted())
  #expect(!keys.contains { $0.localizedCaseInsensitiveContains("audio") })
  #expect(try await store.list() == [record])
}

@Test func dictationHistoryStoreUpdatesTheExistingCaptureRecord() async throws {
  let root = temporaryHistoryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let store = DictationHistoryStore(rootURL: root, now: { now })
  let record = historyRecord()
  try await store.save(record)

  var updated = record
  updated.rawTranscript = "updated transcript"
  updated.insertionOutcome = .saved
  try await store.save(updated)

  #expect(try await store.list() == [updated])
  let files = try FileManager.default.contentsOfDirectory(
    at: root.appendingPathComponent("DictationHistory", isDirectory: true),
    includingPropertiesForKeys: nil
  )
  #expect(files.map(\.lastPathComponent) == ["\(record.id.uuidString.lowercased()).json"])
}

@Test func dictationHistoryStorePurgesRecordsAtThirtyDaysExactly() async throws {
  let root = temporaryHistoryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let expired = historyRecord(completedAt: completedAt)
  let current = historyRecord(completedAt: completedAt.addingTimeInterval(1))
  let initialStore = DictationHistoryStore(rootURL: root, now: { completedAt })
  try await initialStore.save(expired)
  try await initialStore.save(current)

  let expiry = completedAt.addingTimeInterval(30 * 24 * 60 * 60)
  let store = DictationHistoryStore(rootURL: root, now: { expiry })
  try await store.purgeExpired()

  #expect(try await store.list() == [current])
}

@Test func dictationHistoryStoreListsValidRecordsAlongsideMalformedFiles() async throws {
  let root = temporaryHistoryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let store = DictationHistoryStore(rootURL: root, now: { now })
  let record = historyRecord()
  try await store.save(record)
  try Data("not json".utf8).write(
    to: root.appendingPathComponent("DictationHistory/invalid.json"))

  #expect(try await store.list() == [record])
}

@Test func dictationHistoryStoreDeletesRecordsIdempotently() async throws {
  let root = temporaryHistoryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let store = DictationHistoryStore(rootURL: root, now: { now })
  let record = historyRecord()
  try await store.save(record)

  try await store.delete(id: record.id)
  try await store.delete(id: record.id)

  #expect(try await store.list().isEmpty)
}

@Test func dictationHistoryStoreClearsRecordsIdempotently() async throws {
  let root = temporaryHistoryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }

  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let store = DictationHistoryStore(rootURL: root, now: { now })
  try await store.clear()
  try await store.save(historyRecord())

  try await store.clear()
  try await store.clear()

  #expect(try await store.list().isEmpty)
}

private func temporaryHistoryStoreURL() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckHistoryTests-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func historyRecord(
  id: UUID = UUID(),
  completedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> DictationHistoryRecord {
  DictationHistoryRecord(
    id: id,
    mode: .focused,
    engine: .standard,
    startedAt: completedAt.addingTimeInterval(-10),
    completedAt: completedAt,
    rawTranscript: "Buy tea",
    cleanedTranscript: "Buy tea.",
    cleanupOutcome: .cleaned,
    destination: DictationDestination(noteID: UUID(), title: "Inbox"),
    insertionOutcome: .pending
  )
}

private func serializedKeys(in object: [String: Any]) -> [String] {
  object.flatMap { key, value in
    [key] + ((value as? [String: Any]).map(serializedKeys) ?? [])
  }
}

private func rootJSONKeys(in data: Data) -> [String] {
  String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
    guard line.hasPrefix("  \"") else { return nil }
    return line.dropFirst(3).prefix { $0 != "\"" }.description
  }
}
