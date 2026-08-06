import Foundation
import Testing

@testable import FleckCore

@Test func FleckPerformanceFixtureIsDeterministicForRequiredSizes() {
  let firstPass = FleckPerformanceBaselineFixture.requiredNoteCounts.map {
    FleckPerformanceBaselineFixture.workspace(noteCount: $0)
  }
  let secondPass = FleckPerformanceBaselineFixture.requiredNoteCounts.map {
    FleckPerformanceBaselineFixture.workspace(noteCount: $0)
  }

  #expect(firstPass == secondPass)
  for (workspace, noteCount) in zip(firstPass, FleckPerformanceBaselineFixture.requiredNoteCounts) {
    #expect(workspace.notes.count == noteCount)
    #expect(workspace.notes.allSatisfy { $0.title.hasPrefix("Synthetic note ") })
    #expect(workspace.notes.allSatisfy { $0.body.hasPrefix("Synthetic body ") })
    #expect(workspace.notes.allSatisfy { $0.richTextRTF == nil })
  }
}

@Test func FleckPerformanceBaselineRoundTripsRequiredSizesAndRecordsStorageObservations()
  async throws
{
  for noteCount in FleckPerformanceBaselineFixture.requiredNoteCounts {
    let root = temporaryPerformanceStoreURL(noteCount: noteCount)
    do {
      defer { try? FileManager.default.removeItem(at: root) }

      let workspace = FleckPerformanceBaselineFixture.workspace(noteCount: noteCount)
      let store = LocalStore(rootURL: root)
      let saveStart = DispatchTime.now().uptimeNanoseconds
      try await store.save(
        workspace: workspace,
        preferences: AppPreferences(),
        generation: 1
      )
      let saveMilliseconds = elapsedMilliseconds(since: saveStart)

      let rootFiles = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      )
      #expect(rootFiles.filter { $0.pathExtension == "md" }.count == noteCount)
      #expect(rootFiles.contains { $0.lastPathComponent == "workspace.json" })
      #expect(rootFiles.contains { $0.lastPathComponent == "preferences.json" })

      let loadStart = DispatchTime.now().uptimeNanoseconds
      let loaded = try await store.loadWorkspace()
      let loadMilliseconds = elapsedMilliseconds(since: loadStart)
      #expect(loaded == workspace)
      let markdownFileCount = rootFiles.filter { $0.pathExtension == "md" }.count

      print(
        "FleckPerformanceBaseline note_count=\(noteCount) "
          + "save_ms=\(saveMilliseconds) load_ms=\(loadMilliseconds) "
          + "markdown_files=\(markdownFileCount)"
      )
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
  }
}

@Test func FleckPerformanceCurrentBaselineSaveRewritesUnchangedNoteBodies() async throws {
  let root = temporaryPerformanceStoreURL(noteCount: 10)
  defer { try? FileManager.default.removeItem(at: root) }

  let fileManager = FileManager.default
  let initialWorkspace = FleckPerformanceBaselineFixture.workspace(noteCount: 10)
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: initialWorkspace,
    preferences: AppPreferences(),
    generation: 1
  )

  let unchangedNote = initialWorkspace.notes[1]
  let unchangedBodyURL = root.appendingPathComponent(
    "\(unchangedNote.id.uuidString.lowercased()).md"
  )
  let sentinelDate = Date(timeIntervalSince1970: 1)
  try fileManager.setAttributes(
    [.modificationDate: sentinelDate],
    ofItemAtPath: unchangedBodyURL.path
  )

  var changedWorkspace = initialWorkspace
  changedWorkspace.updateContent(
    id: initialWorkspace.notes[0].id,
    body: "Synthetic body updated",
    rtf: nil,
    now: FleckPerformanceBaselineFixture.baseDate.addingTimeInterval(1001)
  )
  try await store.save(
    workspace: changedWorkspace,
    preferences: AppPreferences(),
    generation: 2
  )

  let attributes = try fileManager.attributesOfItem(atPath: unchangedBodyURL.path)
  let modificationDate = try #require(
    attributes[.modificationDate] as? Date
  )
  #expect(
    try Data(contentsOf: unchangedBodyURL) == Data(unchangedNote.body.utf8)
  )
  #expect(modificationDate > sentinelDate)

  print(
    "FleckPerformanceBaseline current_save_rewrites_unchanged_body=true "
      + "note_count=10"
  )
}

private enum FleckPerformanceBaselineFixture {
  static let requiredNoteCounts = [10, 100, 1_000]
  static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

  static func workspace(noteCount: Int) -> Workspace {
    precondition(requiredNoteCounts.contains(noteCount))
    let notes = (0..<noteCount).map { index in
      let suffix = String(format: "%012d", index + 1)
      let id = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
      let date = baseDate.addingTimeInterval(Double(index))
      return Note(
        id: id,
        title: "Synthetic note \(index + 1)",
        body: "Synthetic body \(index + 1)\nLine two",
        createdAt: date,
        modifiedAt: date
      )
    }
    return Workspace(notes: notes, selectedNoteID: notes.first?.id)
  }
}

private func temporaryPerformanceStoreURL(noteCount: Int) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckPerformanceTests-\(noteCount)-\(UUID().uuidString)"
  )
}

private func elapsedMilliseconds(since start: UInt64) -> String {
  let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
  return String(format: "%.3f", Double(elapsedNanoseconds) / 1_000_000)
}
