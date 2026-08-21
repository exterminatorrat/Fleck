import Foundation

public enum PersonalDictionaryStoreError: Error, Equatable, Sendable, CustomStringConvertible {
  case corruptData
  case unsupportedSchemaVersion
  case invalidSnapshot
  case invalidEntry
  case invalidSuggestion
  case missingEntry
  case missingSuggestion

  public var description: String {
    switch self {
    case .corruptData: "corruptData"
    case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
    case .invalidSnapshot: "invalidSnapshot"
    case .invalidEntry: "invalidEntry"
    case .invalidSuggestion: "invalidSuggestion"
    case .missingEntry: "missingEntry"
    case .missingSuggestion: "missingSuggestion"
    }
  }
}

public actor PersonalDictionaryStore {
  public nonisolated let fileURL: URL

  private let fileManager: FileManager
  private var cachedSnapshot: PersonalDictionarySnapshot?
  private static let maximumReadBytes = 64 * 1024

  public init(rootURL: URL, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    fileURL = rootURL
      .appendingPathComponent("PersonalDictionary", isDirectory: true)
      .appendingPathComponent("dictionary-v1.json")
  }

  public func snapshot() throws -> PersonalDictionarySnapshot {
    if let cachedSnapshot { return cachedSnapshot }
    let snapshot = try loadFromDisk()
    cachedSnapshot = snapshot
    return snapshot
  }

  public func upsert(_ entry: PersonalDictionaryEntry) throws {
    guard entry.validationIssues.isEmpty else { throw PersonalDictionaryStoreError.invalidEntry }
    var snapshot = try currentSnapshot()
    snapshot.entries.removeAll { $0.id == entry.id }
    snapshot.entries.append(entry)
    try persist(snapshot)
  }

  public func delete(id: UUID) throws {
    var snapshot = try currentSnapshot()
    let originalCount = snapshot.entries.count
    snapshot.entries.removeAll { $0.id == id }
    guard snapshot.entries.count != originalCount else { return }
    try persist(snapshot)
  }

  public func setEnabled(_ enabled: Bool, id: UUID) throws {
    var snapshot = try currentSnapshot()
    guard let index = snapshot.entries.firstIndex(where: { $0.id == id }) else {
      throw PersonalDictionaryStoreError.missingEntry
    }
    snapshot.entries[index].isEnabled = enabled
    try persist(snapshot)
  }

  public func setPriority(_ priority: Bool, id: UUID) throws {
    var snapshot = try currentSnapshot()
    guard let index = snapshot.entries.firstIndex(where: { $0.id == id }) else {
      throw PersonalDictionaryStoreError.missingEntry
    }
    snapshot.entries[index].isPriority = priority
    try persist(snapshot)
  }

  public func recordSuggestion(_ suggestion: PersonalDictionarySuggestion) throws {
    guard suggestion.validationIssues.isEmpty else {
      throw PersonalDictionaryStoreError.invalidSuggestion
    }
    var snapshot = try currentSnapshot()
    snapshot.suggestions.removeAll { $0.id == suggestion.id }
    snapshot.suggestions.append(suggestion)
    try persist(snapshot)
  }

  public func approveSuggestion(id: UUID) throws -> PersonalDictionaryEntry {
    var snapshot = try currentSnapshot()
    guard let index = snapshot.suggestions.firstIndex(where: { $0.id == id }) else {
      throw PersonalDictionaryStoreError.missingSuggestion
    }
    let suggestion = snapshot.suggestions.remove(at: index)
    guard !snapshot.entries.contains(where: { $0.id == suggestion.id }) else {
      throw PersonalDictionaryStoreError.invalidSnapshot
    }
    let entry = PersonalDictionaryEntry(
      id: suggestion.id,
      preferredForm: suggestion.preferredForm,
      aliases: suggestion.observedForms,
      localeIdentifier: suggestion.localeIdentifier,
      origin: .suggested,
      usage: .init(
        useCount: suggestion.observationCount,
        lastUsedAt: suggestion.lastObservedAt
      )
    )
    guard entry.validationIssues.isEmpty else {
      throw PersonalDictionaryStoreError.invalidSuggestion
    }
    snapshot.entries.append(entry)
    try persist(snapshot)
    return entry
  }

  public func dismissSuggestion(id: UUID) throws {
    var snapshot = try currentSnapshot()
    snapshot.suggestions.removeAll { $0.id == id }
    try persist(snapshot)
  }

  public func replace(with snapshot: PersonalDictionarySnapshot) throws {
    guard snapshot.schemaVersion == PersonalDictionarySnapshot.currentSchemaVersion else {
      throw PersonalDictionaryStoreError.unsupportedSchemaVersion
    }
    guard snapshot.validationIssues.isEmpty else {
      throw PersonalDictionaryStoreError.invalidSnapshot
    }
    try persist(snapshot)
  }

  private func currentSnapshot() throws -> PersonalDictionarySnapshot {
    if let cachedSnapshot { return cachedSnapshot }
    return try loadFromDisk()
  }

  private func loadFromDisk() throws -> PersonalDictionarySnapshot {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return PersonalDictionarySnapshot()
    }
    let data: Data
    do {
      let file = try FileHandle(forReadingFrom: fileURL)
      defer { try? file.close() }
      data = try file.read(upToCount: Self.maximumReadBytes + 1) ?? Data()
    } catch {
      throw PersonalDictionaryStoreError.corruptData
    }
    guard data.count <= Self.maximumReadBytes else {
      throw PersonalDictionaryStoreError.corruptData
    }
    do {
      return try PersonalDictionaryCodec.decodeJSON(data)
    } catch PersonalDictionaryCodecError.unsupportedSchemaVersion {
      throw PersonalDictionaryStoreError.unsupportedSchemaVersion
    } catch {
      throw PersonalDictionaryStoreError.corruptData
    }
  }

  private func persist(_ snapshot: PersonalDictionarySnapshot) throws {
    let data: Data
    do {
      data = try PersonalDictionaryCodec.encodeJSON(snapshot)
    } catch PersonalDictionaryCodecError.unsupportedSchemaVersion {
      throw PersonalDictionaryStoreError.unsupportedSchemaVersion
    } catch {
      throw PersonalDictionaryStoreError.invalidSnapshot
    }
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw PersonalDictionaryStoreError.corruptData
    }
    cachedSnapshot = PersonalDictionaryCodec.sorted(snapshot)
  }
}
