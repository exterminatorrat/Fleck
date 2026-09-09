import Foundation

struct NoteFileReference: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let noteID: UUID
  let bookmarkData: Data
  let cachedFilename: String
}

enum NoteFileReferenceStoreError: Error, Equatable {
  case corruptStore
  case invalidFile
  case duplicateFile
  case duplicateReference
  case referenceNotFound
  case bookmarkCreationFailed
  case bookmarkResolutionFailed
  case saveFailed
}

@MainActor
final class NoteFileReferenceStore {
  typealias AtomicWrite = (_ data: Data, _ destination: URL) throws -> Void

  private static let schemaVersion = 1

  private let sidecarURL: URL
  private let atomicWrite: AtomicWrite
  private var storedReferences: [NoteFileReference]

  init(
    sidecarURL: URL,
    atomicWrite: @escaping AtomicWrite = { data, destination in
      try data.write(to: destination, options: .atomic)
    }
  ) throws {
    self.sidecarURL = sidecarURL
    self.atomicWrite = atomicWrite

    guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
      storedReferences = []
      return
    }

    do {
      let data = try Data(contentsOf: sidecarURL)
      let document = try JSONDecoder().decode(
        NoteFileReferenceDocument.self,
        from: data
      )
      guard Self.isValid(document) else {
        throw NoteFileReferenceStoreError.corruptStore
      }
      storedReferences = document.references
    } catch {
      throw NoteFileReferenceStoreError.corruptStore
    }
  }

  func references(noteID: UUID) -> [NoteFileReference] {
    storedReferences.filter { $0.noteID == noteID }
  }

  @discardableResult
  func add(noteID: UUID, url: URL) throws -> NoteFileReference {
    let target = try inspectedFile(at: url)
    try requireNoDuplicate(
      target: target,
      noteID: noteID,
      excludingReferenceID: nil
    )
    let bookmarkData = try makeBookmark(for: target.url)
    let reference = NoteFileReference(
      id: UUID(),
      noteID: noteID,
      bookmarkData: bookmarkData,
      cachedFilename: target.url.lastPathComponent
    )
    try publish(storedReferences + [reference])
    return reference
  }

  func resolve(referenceID: UUID) throws -> URL {
    guard
      let index = storedReferences.firstIndex(where: { $0.id == referenceID })
    else {
      throw NoteFileReferenceStoreError.referenceNotFound
    }
    let reference = storedReferences[index]
    let resolved: ResolvedBookmark
    do {
      resolved = try resolveBookmark(reference.bookmarkData)
    } catch {
      throw NoteFileReferenceStoreError.bookmarkResolutionFailed
    }

    let filename = resolved.file.url.lastPathComponent
    guard resolved.isStale || filename != reference.cachedFilename else {
      return resolved.file.url
    }

    let bookmarkData: Data
    if resolved.isStale {
      do {
        bookmarkData = try makeBookmark(for: resolved.file.url)
      } catch {
        throw NoteFileReferenceStoreError.bookmarkResolutionFailed
      }
    } else {
      bookmarkData = reference.bookmarkData
    }
    let refreshed = NoteFileReference(
      id: reference.id,
      noteID: reference.noteID,
      bookmarkData: bookmarkData,
      cachedFilename: filename
    )
    var candidate = storedReferences
    candidate[index] = refreshed
    try publish(candidate)
    return resolved.file.url
  }

  @discardableResult
  func relink(referenceID: UUID, url: URL) throws -> NoteFileReference {
    guard
      let index = storedReferences.firstIndex(where: { $0.id == referenceID })
    else {
      throw NoteFileReferenceStoreError.referenceNotFound
    }
    let existing = storedReferences[index]
    let target = try inspectedFile(at: url)
    try requireNoDuplicate(
      target: target,
      noteID: existing.noteID,
      excludingReferenceID: referenceID
    )
    let bookmarkData = try makeBookmark(for: target.url)
    let relinked = NoteFileReference(
      id: existing.id,
      noteID: existing.noteID,
      bookmarkData: bookmarkData,
      cachedFilename: target.url.lastPathComponent
    )
    var candidate = storedReferences
    candidate[index] = relinked
    try publish(candidate)
    return relinked
  }

  @discardableResult
  func remove(referenceID: UUID) throws -> NoteFileReference {
    guard
      let index = storedReferences.firstIndex(where: { $0.id == referenceID })
    else {
      throw NoteFileReferenceStoreError.referenceNotFound
    }
    var candidate = storedReferences
    let removed = candidate.remove(at: index)
    try publish(candidate)
    return removed
  }

  func restore(_ reference: NoteFileReference) throws {
    guard !storedReferences.contains(where: { $0.id == reference.id }) else {
      throw NoteFileReferenceStoreError.duplicateReference
    }
    if let target = try? resolveBookmark(reference.bookmarkData).file {
      try requireNoDuplicate(
        target: target,
        noteID: reference.noteID,
        excludingReferenceID: nil
      )
    }
    try publish(storedReferences + [reference])
  }

  func removeReferences(noteIDs: Set<UUID>) throws {
    guard !noteIDs.isEmpty else { return }
    let candidate = storedReferences.filter { !noteIDs.contains($0.noteID) }
    guard candidate.count != storedReferences.count else { return }
    try publish(candidate)
  }

  private func publish(_ candidate: [NoteFileReference]) throws {
    let document = NoteFileReferenceDocument(
      schemaVersion: Self.schemaVersion,
      references: candidate
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(document)
      try FileManager.default.createDirectory(
        at: sidecarURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try atomicWrite(data, sidecarURL)
    } catch {
      throw NoteFileReferenceStoreError.saveFailed
    }
    storedReferences = candidate
  }

  private func requireNoDuplicate(
    target: InspectedFile,
    noteID: UUID,
    excludingReferenceID: UUID?
  ) throws {
    for reference in storedReferences where
      reference.noteID == noteID && reference.id != excludingReferenceID
    {
      guard let existing = try? resolveBookmark(reference.bookmarkData).file else {
        continue
      }
      if target.isSameFile(as: existing) {
        throw NoteFileReferenceStoreError.duplicateFile
      }
    }
  }

  private func makeBookmark(for url: URL) throws -> Data {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      return try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: [
          .fileResourceIdentifierKey,
          .isRegularFileKey,
          .nameKey,
        ],
        relativeTo: nil
      )
    } catch {
      throw NoteFileReferenceStoreError.bookmarkCreationFailed
    }
  }

  private func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
    var isStale = false
    let resolvedURL = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    let file = try inspectedFile(at: resolvedURL)
    return ResolvedBookmark(file: file, isStale: isStale)
  }

  private func inspectedFile(at url: URL) throws -> InspectedFile {
    guard url.isFileURL else {
      throw NoteFileReferenceStoreError.invalidFile
    }
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let values = try url.resourceValues(forKeys: [
        .fileResourceIdentifierKey,
        .isRegularFileKey,
      ])
      guard values.isRegularFile == true else {
        throw NoteFileReferenceStoreError.invalidFile
      }
      return InspectedFile(
        url: url,
        comparisonURL: url.standardizedFileURL.resolvingSymlinksInPath(),
        resourceIdentifier: values.fileResourceIdentifier as? NSObject
      )
    } catch let error as NoteFileReferenceStoreError {
      throw error
    } catch {
      throw NoteFileReferenceStoreError.invalidFile
    }
  }

  private static func isValid(_ document: NoteFileReferenceDocument) -> Bool {
    guard document.schemaVersion == schemaVersion else { return false }
    let ids = document.references.map(\.id)
    return Set(ids).count == ids.count
      && document.references.allSatisfy {
        !$0.bookmarkData.isEmpty && !$0.cachedFilename.isEmpty
      }
  }
}

private struct NoteFileReferenceDocument: Codable {
  let schemaVersion: Int
  let references: [NoteFileReference]
}

private struct ResolvedBookmark {
  let file: InspectedFile
  let isStale: Bool
}

private struct InspectedFile {
  let url: URL
  let comparisonURL: URL
  let resourceIdentifier: NSObject?

  func isSameFile(as other: InspectedFile) -> Bool {
    if let resourceIdentifier, let otherIdentifier = other.resourceIdentifier {
      return resourceIdentifier.isEqual(otherIdentifier)
    }
    return comparisonURL == other.comparisonURL
  }
}
