import Foundation
import Testing

@testable import FleckApp

@Suite(.serialized)
@MainActor
struct NoteFileReferenceTests {
  @Test func addRemoveReopenAndRestorePersistsWithoutDeletingOriginal() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let noteID = UUID()
    let fileURL = try fixture.makeFile(named: "draft.txt")

    let store = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    let added = try store.add(noteID: noteID, url: fileURL)
    #expect(store.references(noteID: noteID) == [added])

    let reopened = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    #expect(reopened.references(noteID: noteID) == [added])
    let json = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.sidecarURL))
        as? [String: Any]
    )
    let persistedReferences = try #require(json["references"] as? [[String: Any]])
    #expect(Set(json.keys) == ["references", "schemaVersion"])
    #expect(
      Set(try #require(persistedReferences.first).keys)
        == ["bookmarkData", "cachedFilename", "id", "noteID"]
    )

    let removed = try reopened.remove(referenceID: added.id)
    #expect(removed == added)
    #expect(reopened.references(noteID: noteID).isEmpty)
    #expect(FileManager.default.fileExists(atPath: fileURL.path))

    let afterRemoval = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    #expect(afterRemoval.references(noteID: noteID).isEmpty)
    try afterRemoval.restore(removed)

    let afterRestore = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    #expect(afterRestore.references(noteID: noteID) == [added])
  }

  @Test func failedAtomicWritesLeaveEveryMutationUnpublished() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let noteID = UUID()
    let firstURL = try fixture.makeFile(named: "first.txt")
    let secondURL = try fixture.makeFile(named: "second.txt")
    let thirdURL = try fixture.makeFile(named: "third.txt")
    let gate = NoteFileReferenceWriteGate()
    let store = try NoteFileReferenceStore(
      sidecarURL: fixture.sidecarURL,
      atomicWrite: gate.write
    )
    let first = try store.add(noteID: noteID, url: firstURL)
    let baselineBytes = try Data(contentsOf: fixture.sidecarURL)

    gate.shouldFail = true
    #expect(throws: NoteFileReferenceStoreError.saveFailed) {
      _ = try store.add(noteID: noteID, url: secondURL)
    }
    #expect(store.references(noteID: noteID) == [first])
    #expect(try Data(contentsOf: fixture.sidecarURL) == baselineBytes)

    let renamedFirstURL = fixture.rootURL.appendingPathComponent(
      "first-renamed.txt"
    )
    try FileManager.default.moveItem(at: firstURL, to: renamedFirstURL)
    #expect(throws: NoteFileReferenceStoreError.saveFailed) {
      _ = try store.resolve(referenceID: first.id)
    }
    #expect(store.references(noteID: noteID) == [first])

    #expect(throws: NoteFileReferenceStoreError.saveFailed) {
      _ = try store.relink(referenceID: first.id, url: thirdURL)
    }
    #expect(store.references(noteID: noteID) == [first])

    #expect(throws: NoteFileReferenceStoreError.saveFailed) {
      _ = try store.remove(referenceID: first.id)
    }
    #expect(store.references(noteID: noteID) == [first])

    let removedCopy = NoteFileReference(
      id: UUID(),
      noteID: noteID,
      bookmarkData: try thirdURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: [.fileResourceIdentifierKey],
        relativeTo: nil
      ),
      cachedFilename: thirdURL.lastPathComponent
    )
    #expect(throws: NoteFileReferenceStoreError.saveFailed) {
      try store.restore(removedCopy)
    }
    #expect(store.references(noteID: noteID) == [first])

    #expect(throws: NoteFileReferenceStoreError.saveFailed) {
      try store.removeReferences(noteIDs: [noteID])
    }
    #expect(store.references(noteID: noteID) == [first])
  }

  @Test func absentSidecarStartsEmptyAndCorruptSidecarIsPreserved() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let noteID = UUID()

    let empty = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    #expect(empty.references(noteID: noteID).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.sidecarURL.path))

    let corrupt = Data("not-json\n".utf8)
    try corrupt.write(to: fixture.sidecarURL, options: .atomic)
    #expect(throws: NoteFileReferenceStoreError.corruptStore) {
      _ = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    }
    #expect(try Data(contentsOf: fixture.sidecarURL) == corrupt)
  }

  @Test func duplicateNativeFileIdentityIsRejectedOnlyWithinTheSameNote() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let firstNoteID = UUID()
    let secondNoteID = UUID()
    let originalURL = try fixture.makeFile(named: "original.txt")
    let hardLinkURL = fixture.rootURL.appendingPathComponent("hard-link.txt")
    try FileManager.default.linkItem(at: originalURL, to: hardLinkURL)

    let store = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    _ = try store.add(noteID: firstNoteID, url: originalURL)

    #expect(throws: NoteFileReferenceStoreError.duplicateFile) {
      _ = try store.add(noteID: firstNoteID, url: hardLinkURL)
    }
    let secondNoteReference = try store.add(
      noteID: secondNoteID,
      url: hardLinkURL
    )
    #expect(store.references(noteID: secondNoteID) == [secondNoteReference])
  }

  @Test func relinkPreservesReferenceIdentityAndRejectsANoteDuplicate() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let noteID = UUID()
    let firstURL = try fixture.makeFile(named: "first.txt")
    let secondURL = try fixture.makeFile(named: "second.txt")
    let thirdURL = try fixture.makeFile(named: "third.txt")
    let store = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    let first = try store.add(noteID: noteID, url: firstURL)
    let second = try store.add(noteID: noteID, url: secondURL)

    let relinked = try store.relink(referenceID: first.id, url: thirdURL)
    #expect(relinked.id == first.id)
    #expect(relinked.noteID == noteID)
    #expect(relinked.cachedFilename == "third.txt")
    #expect(
      try store.resolve(referenceID: first.id).resolvingSymlinksInPath()
        == thirdURL.resolvingSymlinksInPath()
    )

    #expect(throws: NoteFileReferenceStoreError.duplicateFile) {
      _ = try store.relink(referenceID: first.id, url: secondURL)
    }
    #expect(store.references(noteID: noteID) == [relinked, second])
  }

  @Test func nativeBookmarkFollowsRenameAndMoveThenRetainsMissingReference() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let noteID = UUID()
    let originalURL = try fixture.makeFile(named: "original.txt")
    let store = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    let reference = try store.add(noteID: noteID, url: originalURL)

    let renamedURL = fixture.rootURL.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: originalURL, to: renamedURL)
    #expect(
      try store.resolve(referenceID: reference.id).resolvingSymlinksInPath()
        == renamedURL.resolvingSymlinksInPath()
    )
    #expect(store.references(noteID: noteID).first?.cachedFilename == "renamed.txt")

    let destination = fixture.rootURL.appendingPathComponent(
      "nested",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: destination,
      withIntermediateDirectories: true
    )
    let movedURL = destination.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: renamedURL, to: movedURL)
    #expect(
      try store.resolve(referenceID: reference.id).resolvingSymlinksInPath()
        == movedURL.resolvingSymlinksInPath()
    )

    try FileManager.default.removeItem(at: movedURL)
    #expect(throws: NoteFileReferenceStoreError.bookmarkResolutionFailed) {
      _ = try store.resolve(referenceID: reference.id)
    }
    let retained = try #require(store.references(noteID: noteID).first)
    #expect(retained.id == reference.id)
    #expect(retained.cachedFilename == "renamed.txt")

    let reopened = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)
    #expect(reopened.references(noteID: noteID) == [retained])
  }

  @Test func onlyRegularFileURLsAreAcceptedAndCleanupIsExplicit() throws {
    let fixture = try NoteFileReferenceFixture()
    defer { fixture.remove() }
    let retainedNoteID = UUID()
    let deletedNoteID = UUID()
    let directoryURL = fixture.rootURL.appendingPathComponent(
      "directory",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    let fileURL = try fixture.makeFile(named: "kept.txt")
    let deletedFileURL = try fixture.makeFile(named: "deleted.txt")
    let store = try NoteFileReferenceStore(sidecarURL: fixture.sidecarURL)

    #expect(throws: NoteFileReferenceStoreError.invalidFile) {
      _ = try store.add(
        noteID: retainedNoteID,
        url: URL(string: "https://example.com/file")!
      )
    }
    #expect(throws: NoteFileReferenceStoreError.invalidFile) {
      _ = try store.add(noteID: retainedNoteID, url: directoryURL)
    }

    let retained = try store.add(noteID: retainedNoteID, url: fileURL)
    _ = try store.add(noteID: deletedNoteID, url: deletedFileURL)
    #expect(store.references(noteID: UUID()).isEmpty)
    #expect(store.references(noteID: retainedNoteID) == [retained])

    try store.removeReferences(noteIDs: [deletedNoteID])
    #expect(store.references(noteID: deletedNoteID).isEmpty)
    #expect(store.references(noteID: retainedNoteID) == [retained])
  }
}

@MainActor
private final class NoteFileReferenceWriteGate {
  var shouldFail = false

  func write(_ data: Data, to url: URL) throws {
    if shouldFail {
      throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
  }
}

@MainActor
private struct NoteFileReferenceFixture {
  let rootURL: URL
  let sidecarURL: URL

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "note-file-references-\(UUID().uuidString)",
        isDirectory: true
      )
    sidecarURL = rootURL.appendingPathComponent("references.json")
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
  }

  func makeFile(named name: String) throws -> URL {
    let url = rootURL.appendingPathComponent(name)
    try Data("original contents".utf8).write(to: url)
    return url
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}
