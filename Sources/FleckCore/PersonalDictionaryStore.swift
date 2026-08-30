import Darwin
import Foundation

public enum PersonalDictionaryStoreError: Error, Equatable, Sendable, CustomStringConvertible {
  case corruptData
  case fileTooLarge
  case unsupportedSchemaVersion
  case invalidSnapshot
  case invalidEntry
  case invalidSuggestion
  case missingEntry
  case missingSuggestion
  case revisionConflict
  case revisionOverflow
  case publicationFailed

  public var description: String {
    switch self {
    case .corruptData: "corruptData"
    case .fileTooLarge: "fileTooLarge"
    case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
    case .invalidSnapshot: "invalidSnapshot"
    case .invalidEntry: "invalidEntry"
    case .invalidSuggestion: "invalidSuggestion"
    case .missingEntry: "missingEntry"
    case .missingSuggestion: "missingSuggestion"
    case .revisionConflict: "revisionConflict"
    case .revisionOverflow: "revisionOverflow"
    case .publicationFailed: "publicationFailed"
    }
  }
}

public struct PersonalDictionaryPublishedSnapshot: Equatable, Sendable {
  public let snapshot: PersonalDictionarySnapshotV2
  public let compiled: CompiledPersonalDictionary
}

public enum PersonalDictionaryMutation: Equatable, Sendable {
  case upsert(PersonalDictionaryEntry)
  case delete(id: UUID)
  case setEnabled(Bool, id: UUID)
  case setPriority(Bool, id: UUID)
  case recordSuggestion(PersonalDictionarySuggestion)
  case approveSuggestion(id: UUID)
  case dismissSuggestion(id: UUID)
  case replace(PersonalDictionarySnapshot)
}

enum PersonalDictionaryPublicationPoint: Equatable, Sendable {
  case afterStageSync
  case afterReadback
  case beforeReplace
}

public actor PersonalDictionaryStore {
  public nonisolated let fileURL: URL

  private let fileManager: FileManager
  private let compiler: @Sendable (PersonalDictionarySnapshotV2) throws -> CompiledPersonalDictionary
  private let publicationHook: @Sendable (PersonalDictionaryPublicationPoint, URL) throws -> Void
  private var cachedPublished: PersonalDictionaryPublishedSnapshot?
  private static let maximumFileBytes = 64 * 1024
  private static let processMutationLock = NSLock()

  public init(rootURL: URL, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    compiler = CompiledPersonalDictionary.compile
    publicationHook = { _, _ in }
    fileURL = rootURL
      .appendingPathComponent("PersonalDictionary", isDirectory: true)
      .appendingPathComponent("dictionary-v1.json")
  }

  init(
    rootURL: URL,
    fileManager: FileManager = .default,
    compiler: @escaping @Sendable (PersonalDictionarySnapshotV2) throws -> CompiledPersonalDictionary,
    publicationHook: @escaping @Sendable (PersonalDictionaryPublicationPoint, URL) throws -> Void
  ) {
    self.fileManager = fileManager
    self.compiler = compiler
    self.publicationHook = publicationHook
    fileURL = rootURL
      .appendingPathComponent("PersonalDictionary", isDirectory: true)
      .appendingPathComponent("dictionary-v1.json")
  }

  public func snapshot() throws -> PersonalDictionarySnapshot {
    let published = try publishedSnapshot()
    return PersonalDictionarySnapshot(
      entries: published.snapshot.entries,
      suggestions: published.snapshot.suggestions
    )
  }

  public func publishedSnapshot() throws -> PersonalDictionaryPublishedSnapshot {
    if let cachedPublished { return cachedPublished }
    guard fileManager.fileExists(atPath: fileURL.path) else {
      let empty = PersonalDictionarySnapshotV2()
      let published = try compile(empty)
      cachedPublished = published
      return published
    }

    return try withMutationLock {
      removeStaleStages()
      guard let authority = try readAuthority() else {
        let empty = PersonalDictionarySnapshotV2()
        let published = try compile(empty)
        cachedPublished = published
        return published
      }
      if authority.isLegacy {
        return try stageAndPublish(authority.snapshot, priorBytes: authority.bytes)
      }
      let published = try compile(authority.snapshot)
      cachedPublished = published
      return published
    }
  }

  public func mutate(
    expectedRevision: UInt64,
    _ mutation: PersonalDictionaryMutation
  ) throws -> PersonalDictionaryPublishedSnapshot {
    try transact(expectedRevision: expectedRevision, mutation)
  }

  public func upsert(_ entry: PersonalDictionaryEntry) throws {
    _ = try transact(expectedRevision: nil, .upsert(entry))
  }

  public func delete(id: UUID) throws {
    _ = try transact(expectedRevision: nil, .delete(id: id))
  }

  public func setEnabled(_ enabled: Bool, id: UUID) throws {
    _ = try transact(expectedRevision: nil, .setEnabled(enabled, id: id))
  }

  public func setPriority(_ priority: Bool, id: UUID) throws {
    _ = try transact(expectedRevision: nil, .setPriority(priority, id: id))
  }

  public func recordSuggestion(_ suggestion: PersonalDictionarySuggestion) throws {
    _ = try transact(expectedRevision: nil, .recordSuggestion(suggestion))
  }

  public func approveSuggestion(id: UUID) throws -> PersonalDictionaryEntry {
    let published = try transact(expectedRevision: nil, .approveSuggestion(id: id))
    guard let entry = published.snapshot.entries.first(where: { $0.id == id }) else {
      throw PersonalDictionaryStoreError.publicationFailed
    }
    return entry
  }

  public func dismissSuggestion(id: UUID) throws {
    _ = try transact(expectedRevision: nil, .dismissSuggestion(id: id))
  }

  public func replace(with snapshot: PersonalDictionarySnapshot) throws {
    _ = try transact(expectedRevision: nil, .replace(snapshot))
  }

  private func transact(
    expectedRevision: UInt64?,
    _ mutation: PersonalDictionaryMutation
  ) throws -> PersonalDictionaryPublishedSnapshot {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      throw PersonalDictionaryStoreError.publicationFailed
    }
    return try withMutationLock {
      removeStaleStages()
      let authority = try readAuthority()
      let current = authority?.snapshot ?? PersonalDictionarySnapshotV2()
      if let expectedRevision, expectedRevision != current.revision {
        throw PersonalDictionaryStoreError.revisionConflict
      }
      let revision: UInt64
      if authority?.isLegacy == true {
        revision = current.revision
      } else {
        let (next, overflow) = current.revision.addingReportingOverflow(1)
        guard !overflow else { throw PersonalDictionaryStoreError.revisionOverflow }
        revision = next
      }
      let candidate = try applying(mutation, to: current, revision: revision)
      return try stageAndPublish(candidate, priorBytes: authority?.bytes)
    }
  }

  private func applying(
    _ mutation: PersonalDictionaryMutation,
    to current: PersonalDictionarySnapshotV2,
    revision: UInt64
  ) throws -> PersonalDictionarySnapshotV2 {
    var entries = current.entries
    var suggestions = current.suggestions
    switch mutation {
    case .upsert(let entry):
      guard entry.validationIssues.isEmpty else {
        throw PersonalDictionaryStoreError.invalidEntry
      }
      entries.removeAll { $0.id == entry.id }
      entries.append(entry)
    case .delete(let id):
      entries.removeAll { $0.id == id }
    case .setEnabled(let enabled, let id):
      guard let index = entries.firstIndex(where: { $0.id == id }) else {
        throw PersonalDictionaryStoreError.missingEntry
      }
      entries[index].isEnabled = enabled
    case .setPriority(let priority, let id):
      guard let index = entries.firstIndex(where: { $0.id == id }) else {
        throw PersonalDictionaryStoreError.missingEntry
      }
      entries[index].isPriority = priority
    case .recordSuggestion(let suggestion):
      guard suggestion.validationIssues.isEmpty else {
        throw PersonalDictionaryStoreError.invalidSuggestion
      }
      suggestions.removeAll { $0.id == suggestion.id }
      suggestions.append(suggestion)
    case .approveSuggestion(let id):
      guard let index = suggestions.firstIndex(where: { $0.id == id }) else {
        throw PersonalDictionaryStoreError.missingSuggestion
      }
      let suggestion = suggestions.remove(at: index)
      guard !entries.contains(where: { $0.id == suggestion.id }) else {
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
      entries.append(entry)
    case .dismissSuggestion(let id):
      suggestions.removeAll { $0.id == id }
    case .replace(let snapshot):
      guard snapshot.schemaVersion == PersonalDictionarySnapshot.currentSchemaVersion else {
        throw PersonalDictionaryStoreError.unsupportedSchemaVersion
      }
      guard snapshot.validationIssues.isEmpty else {
        throw PersonalDictionaryStoreError.invalidSnapshot
      }
      entries = snapshot.entries
      suggestions = snapshot.suggestions
    }
    return PersonalDictionarySnapshotV2(
      revision: revision,
      entries: entries,
      suggestions: suggestions
    )
  }

  private func stageAndPublish(
    _ candidate: PersonalDictionarySnapshotV2,
    priorBytes: Data?
  ) throws -> PersonalDictionaryPublishedSnapshot {
    let bytes: Data
    do {
      bytes = try PersonalDictionaryCodec.encodeCanonicalJSON(candidate)
    } catch PersonalDictionaryCodecError.jsonByteLimitExceeded {
      throw PersonalDictionaryStoreError.fileTooLarge
    } catch PersonalDictionaryCodecError.unsupportedSchemaVersion {
      throw PersonalDictionaryStoreError.unsupportedSchemaVersion
    } catch {
      throw PersonalDictionaryStoreError.invalidSnapshot
    }

    let stageURL = fileURL.deletingLastPathComponent().appendingPathComponent(
      "\(fileURL.lastPathComponent).stage.\(UUID().uuidString)"
    )
    defer { try? fileManager.removeItem(at: stageURL) }
    do {
      try writeSynced(bytes, to: stageURL)
      try publicationHook(.afterStageSync, stageURL)
      let reread = try readBounded(stageURL)
      guard reread == bytes else { throw PersonalDictionaryStoreError.publicationFailed }
      let decoded = try PersonalDictionaryCodec.decodePublishedJSON(reread)
      guard decoded.revision == candidate.revision else {
        throw PersonalDictionaryStoreError.publicationFailed
      }
      try publicationHook(.afterReadback, stageURL)
      let compiled = try compiler(decoded)
      let published = PersonalDictionaryPublishedSnapshot(snapshot: decoded, compiled: compiled)
      if let priorBytes {
        guard priorBytes.count <= Self.maximumFileBytes else {
          throw PersonalDictionaryStoreError.publicationFailed
        }
        let recoveryURL = fileURL.appendingPathExtension("recovery")
        try priorBytes.write(to: recoveryURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
      }
      try publicationHook(.beforeReplace, stageURL)
      guard Darwin.rename(stageURL.path, fileURL.path) == 0 else {
        throw PersonalDictionaryStoreError.publicationFailed
      }
      cachedPublished = published
      return published
    } catch let error as PersonalDictionaryStoreError {
      throw error
    } catch {
      throw PersonalDictionaryStoreError.publicationFailed
    }
  }

  private func compile(
    _ snapshot: PersonalDictionarySnapshotV2
  ) throws -> PersonalDictionaryPublishedSnapshot {
    do {
      return PersonalDictionaryPublishedSnapshot(
        snapshot: snapshot,
        compiled: try compiler(snapshot)
      )
    } catch {
      throw PersonalDictionaryStoreError.publicationFailed
    }
  }

  private struct Authority {
    let snapshot: PersonalDictionarySnapshotV2
    let bytes: Data
    let isLegacy: Bool
  }

  private func readAuthority() throws -> Authority? {
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
    let bytes = try readBounded(fileURL)
    do {
      let snapshot = try PersonalDictionaryCodec.decodeCandidateJSON(bytes)
      let isPublished = (try? PersonalDictionaryCodec.encodeCanonicalJSON(snapshot)) == bytes
      return Authority(snapshot: snapshot, bytes: bytes, isLegacy: !isPublished)
    } catch PersonalDictionaryCodecError.jsonByteLimitExceeded {
      throw PersonalDictionaryStoreError.fileTooLarge
    } catch PersonalDictionaryCodecError.unsupportedSchemaVersion {
      throw PersonalDictionaryStoreError.unsupportedSchemaVersion
    } catch {
      do {
        _ = try PersonalDictionaryCodec.decodeJSON(bytes)
      } catch PersonalDictionaryCodecError.unsupportedSchemaVersion {
        throw PersonalDictionaryStoreError.unsupportedSchemaVersion
      } catch {}
      throw PersonalDictionaryStoreError.corruptData
    }
  }

  private func readBounded(_ url: URL) throws -> Data {
    do {
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      let data = try file.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
      guard data.count <= Self.maximumFileBytes else {
        throw PersonalDictionaryStoreError.fileTooLarge
      }
      return data
    } catch let error as PersonalDictionaryStoreError {
      throw error
    } catch {
      throw PersonalDictionaryStoreError.corruptData
    }
  }

  private func writeSynced(_ data: Data, to url: URL) throws {
    let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { throw PersonalDictionaryStoreError.publicationFailed }
    var closeRequired = true
    defer { if closeRequired { _ = Darwin.close(descriptor) } }
    try data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return }
      var written = 0
      while written < rawBuffer.count {
        let result = Darwin.write(descriptor, base.advanced(by: written), rawBuffer.count - written)
        if result < 0, errno == EINTR { continue }
        guard result > 0 else { throw PersonalDictionaryStoreError.publicationFailed }
        written += result
      }
    }
    guard Darwin.fsync(descriptor) == 0 else {
      throw PersonalDictionaryStoreError.publicationFailed
    }
    guard Darwin.close(descriptor) == 0 else {
      throw PersonalDictionaryStoreError.publicationFailed
    }
    closeRequired = false
  }

  private func withMutationLock<T>(_ body: () throws -> T) throws -> T {
    Self.processMutationLock.lock()
    defer { Self.processMutationLock.unlock() }
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      throw PersonalDictionaryStoreError.publicationFailed
    }
    let lockURL = fileURL.appendingPathExtension("lock")
    let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw PersonalDictionaryStoreError.publicationFailed }
    defer { _ = Darwin.close(descriptor) }
    guard Darwin.fchmod(descriptor, 0o600) == 0,
      Darwin.lockf(descriptor, F_LOCK, 0) == 0
    else {
      throw PersonalDictionaryStoreError.publicationFailed
    }
    defer { _ = Darwin.lockf(descriptor, F_ULOCK, 0) }
    return try body()
  }

  private func removeStaleStages() {
    let directory = fileURL.deletingLastPathComponent()
    let prefix = "\(fileURL.lastPathComponent).stage."
    guard let urls = try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ) else { return }
    for url in urls where url.lastPathComponent.hasPrefix(prefix) {
      try? fileManager.removeItem(at: url)
    }
  }
}
