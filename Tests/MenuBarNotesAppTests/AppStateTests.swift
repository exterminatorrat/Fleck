import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func editingReportsSavingThenSaved() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root))

  state.updateSelected(title: "Changed")

  #expect(state.saveStatus == .saving)
  let deadline = ContinuousClock.now + .seconds(3)
  while state.saveStatus == .saving, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(50))
  }
  #expect(state.saveStatus == .saved)
}

@Test @MainActor func restoringRemovesTrashRowImmediately() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let remaining = Note(title: "Remaining")
  let deleted = Note(title: "Deleted")
  try await store.save(
    workspace: Workspace(notes: [remaining], selectedNoteID: remaining.id),
    preferences: .init(),
    trashedNotes: [deleted]
  )
  let state = AppState(store: store)
  await state.refreshTrash()
  let trashedNote = try #require(state.trashedNotes.first)
  state.updateSelected(title: "Pending edit")
  #expect(state.saveStatus == .saving)

  state.restore(trashedNote)

  #expect(state.selectedNote?.id == deleted.id)
  #expect(!state.trashedNotes.contains(where: { $0.id == deleted.id }))
  #expect(state.saveStatus == .idle)

  state.updateSelected(title: "Edited after restore")
  #expect(state.saveStatus == .saving)
  try await Task.sleep(for: .milliseconds(100))
  #expect(state.saveStatus == .saving)
}
