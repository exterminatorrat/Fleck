import AppKit
import FleckCore
import Foundation
import Testing

@testable import FleckApp

private final class NoteDeletionSnapshotRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [(AppPreferences, [Note])] = []

  var snapshots: [(AppPreferences, [Note])] {
    lock.withLock { recorded }
  }

  func record(preferences: AppPreferences, trashedNotes: [Note]) {
    lock.withLock {
      recorded.append((preferences, trashedNotes))
    }
  }
}

private func noteDeletionSource() throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
}

private func settingsSource() throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
}

@Test func noteTrashEntryPointsShareOneConfirmationDecisionBoundary() throws {
  let source = try noteDeletionSource()
  #expect(source.components(separatedBy: "requestDeletion(note)").count - 1 == 3)
  #expect(source.contains("@State private var dontAskAgainForDeletion = false"))
  #expect(source.contains("if appState.preferences.confirmBeforeMovingNotesToTrash"))
  #expect(source.contains("dontAskAgain: $dontAskAgainForDeletion"))
  #expect(source.contains("Toggle(\"Don't ask me again\", isOn: $dontAskAgain)"))
  #expect(source.contains("$0.confirmBeforeMovingNotesToTrash = false"))

  let request = try #require(source.range(of: "private func requestDeletion(_ note: Note)"))
  let confirm = try #require(source.range(of: "private func confirmDeletion(_ note: Note)"))
  let requestBody = source[request.lowerBound..<confirm.lowerBound]
  let confirmBody = source[confirm.lowerBound...]
  #expect(requestBody.contains("confirmBeforeMovingNotesToTrash"))
  #expect(requestBody.contains("appState.moveToTrash(note.id, activeFolderID: activeFolderID)"))
  #expect(confirmBody.contains("dontAskAgainForDeletion"))
  #expect(confirmBody.contains("confirmBeforeMovingNotesToTrash = false"))
  #expect(confirmBody.contains("appState.moveToTrash(note.id, activeFolderID: activeFolderID)"))

  let cancel = try #require(source.range(of: "onCancel: {"))
  let cancelTail = source[cancel.lowerBound..<confirm.lowerBound]
  #expect(!cancelTail.contains("confirmBeforeMovingNotesToTrash = false"))
}

@Test func settingsRestoresNoteTrashConfirmationPreference() throws {
  let source = try settingsSource()
  #expect(source.contains("Confirm before moving notes to Trash"))
  #expect(source.contains("preferenceBinding(\\.confirmBeforeMovingNotesToTrash)"))
}

@Test @MainActor func disabledConfirmationMovesOnceWithRecoverableTrashSnapshot() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let recorder = NoteDeletionSnapshotRecorder()
  let note = Note(title: "Disposable deletion")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, preferences, trashedNotes, _ in
      recorder.record(preferences: preferences, trashedNotes: trashedNotes)
      return .committed
    }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id)

  state.updatePreferences { $0.confirmBeforeMovingNotesToTrash = false }
  state.moveToTrash(note.id, activeFolderID: nil)

  let deadline = ContinuousClock.now + .seconds(3)
  while recorder.snapshots.isEmpty, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(25))
  }
  let snapshot = try #require(recorder.snapshots.last)
  #expect(recorder.snapshots.count == 1)
  #expect(!snapshot.0.confirmBeforeMovingNotesToTrash)
  #expect(snapshot.1.map(\.id) == [note.id])
  #expect(!state.workspace.notes.contains(where: { $0.id == note.id }))
}
