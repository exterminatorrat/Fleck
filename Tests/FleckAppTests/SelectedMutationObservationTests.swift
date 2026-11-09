import Combine
import Foundation
import FleckCore
import Testing

@testable import FleckApp

private final class SelectedMutationSaveRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var savedGenerations: [UInt64] = []

  var generations: [UInt64] {
    lock.withLock { savedGenerations }
  }

  func record(generation: UInt64) {
    lock.withLock {
      savedGenerations.append(generation)
    }
  }
}

@MainActor
private struct SelectedMutationFixture {
  let state: AppState
  let selectedNote: Note
  let root: URL
  let recorder: SelectedMutationSaveRecorder
}

@MainActor
private func selectedMutationFixture(
  noteCount: Int,
  selectedIndex: Int
) async -> SelectedMutationFixture {
  let originalDate = Date(timeIntervalSince1970: 100)
  var notes = (0..<noteCount).map { index in
    Note(
      title: "Note \(index)",
      body: String(repeating: "workspace note \(index)\n", count: 8),
      createdAt: originalDate.addingTimeInterval(-1),
      modifiedAt: originalDate,
      revision: 4
    )
  }
  let selectedNote = Note(
    id: notes[selectedIndex].id,
    title: "Selected title",
    body: String(repeating: "selected note body\n", count: 1_024),
    richTextRTF: Data(repeating: 0xA5, count: 4_096),
    createdAt: originalDate.addingTimeInterval(-1),
    modifiedAt: originalDate,
    revision: 12
  )
  notes[selectedIndex] = selectedNote
  let workspace = Workspace(notes: notes, selectedNoteID: selectedNote.id)
  let recorder = SelectedMutationSaveRecorder()
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, generation in
      recorder.record(generation: generation)
      return .committed
    }
  )
  await state.waitUntilInitialLoad()
  state.workspace = workspace

  return SelectedMutationFixture(
    state: state,
    selectedNote: selectedNote,
    root: root,
    recorder: recorder
  )
}

private func waitForSelectedMutationSave(
  _ recorder: SelectedMutationSaveRecorder,
  count: Int
) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while recorder.generations.count < count, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(25))
  }
}

@Test(arguments: [(1, 0), (9, 4), (24, 23)]) @MainActor
func selectedNoOpMutationsDoNotPublishOrScheduleSaves(
  noteCount: Int,
  selectedIndex: Int
) async throws {
  let fixture = await selectedMutationFixture(
    noteCount: noteCount,
    selectedIndex: selectedIndex
  )
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let initialGeneration = fixture.state.persistenceGeneration
  var workspacePublications = 0
  let observation = fixture.state.$workspace.dropFirst().sink { _ in
    workspacePublications += 1
  }

  fixture.state.updateSelected(
    title: fixture.selectedNote.title,
    body: fixture.selectedNote.body
  )
  fixture.state.updateSelected(
    body: fixture.selectedNote.body,
    richTextRTF: fixture.selectedNote.richTextRTF
  )
  fixture.state.updateSelectedRichTextRTF(fixture.selectedNote.richTextRTF)
  try await Task.sleep(for: .milliseconds(550))

  #expect(fixture.state.selectedNote == fixture.selectedNote)
  #expect(fixture.state.persistenceGeneration == initialGeneration)
  #expect(fixture.state.saveStatus == .idle)
  #expect(fixture.recorder.generations.isEmpty)
  #expect(workspacePublications == 0)
  withExtendedLifetime(observation) {}
}

@Test(arguments: [(1, 0), (14, 13)]) @MainActor
func selectedTitleChangeWithNoOpBodyPublishesAndPersistsOnce(
  noteCount: Int,
  selectedIndex: Int
) async throws {
  let fixture = await selectedMutationFixture(
    noteCount: noteCount,
    selectedIndex: selectedIndex
  )
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let initialGeneration = fixture.state.persistenceGeneration
  var workspacePublications = 0
  let observation = fixture.state.$workspace.dropFirst().sink { _ in
    workspacePublications += 1
  }

  fixture.state.updateSelected(
    title: "Changed title",
    body: fixture.selectedNote.body
  )
  try await waitForSelectedMutationSave(fixture.recorder, count: 1)

  #expect(fixture.state.selectedNote?.title == "Changed title")
  #expect(fixture.state.selectedNote?.body == fixture.selectedNote.body)
  #expect(fixture.state.selectedNote?.revision == fixture.selectedNote.revision + 1)
  #expect(fixture.state.selectedNote?.modifiedAt != fixture.selectedNote.modifiedAt)
  #expect(fixture.state.persistenceGeneration == initialGeneration + 1)
  #expect(fixture.recorder.generations == [initialGeneration + 1])
  #expect(workspacePublications == 1)
  withExtendedLifetime(observation) {}
}

@Test(arguments: [(9, 4), (24, 0)]) @MainActor
func selectedBodyChangeWithNoOpTitleRetainsRichTextAndPublishesOnce(
  noteCount: Int,
  selectedIndex: Int
) async throws {
  let fixture = await selectedMutationFixture(
    noteCount: noteCount,
    selectedIndex: selectedIndex
  )
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let initialGeneration = fixture.state.persistenceGeneration
  let changedBody = String(repeating: "updated body\n", count: 1_024)
  var workspacePublications = 0
  let observation = fixture.state.$workspace.dropFirst().sink { _ in
    workspacePublications += 1
  }

  fixture.state.updateSelected(
    title: fixture.selectedNote.title,
    body: changedBody
  )
  try await waitForSelectedMutationSave(fixture.recorder, count: 1)

  #expect(fixture.state.selectedNote?.body == changedBody)
  #expect(fixture.state.selectedNote?.richTextRTF == fixture.selectedNote.richTextRTF)
  #expect(fixture.state.selectedNote?.revision == fixture.selectedNote.revision + 1)
  #expect(fixture.state.selectedNote?.modifiedAt != fixture.selectedNote.modifiedAt)
  #expect(fixture.state.persistenceGeneration == initialGeneration + 1)
  #expect(fixture.recorder.generations == [initialGeneration + 1])
  #expect(workspacePublications == 1)
  withExtendedLifetime(observation) {}
}

@Test(arguments: [(3, 2), (22, 21)]) @MainActor
func selectedRTFOnlyMutationPublishesAndPersistsOnce(
  noteCount: Int,
  selectedIndex: Int
) async throws {
  let fixture = await selectedMutationFixture(
    noteCount: noteCount,
    selectedIndex: selectedIndex
  )
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let initialGeneration = fixture.state.persistenceGeneration
  let changedRTF = Data(repeating: 0x5A, count: 4_096)
  var workspacePublications = 0
  let observation = fixture.state.$workspace.dropFirst().sink { _ in
    workspacePublications += 1
  }

  fixture.state.updateSelectedRichTextRTF(changedRTF)
  try await waitForSelectedMutationSave(fixture.recorder, count: 1)

  #expect(fixture.state.selectedNote?.body == fixture.selectedNote.body)
  #expect(fixture.state.selectedNote?.richTextRTF == changedRTF)
  #expect(fixture.state.selectedNote?.revision == fixture.selectedNote.revision + 1)
  #expect(fixture.state.selectedNote?.modifiedAt != fixture.selectedNote.modifiedAt)
  #expect(fixture.state.persistenceGeneration == initialGeneration + 1)
  #expect(fixture.recorder.generations == [initialGeneration + 1])
  #expect(workspacePublications == 1)
  withExtendedLifetime(observation) {}
}

@Test(arguments: [(1, 0), (12, 6), (24, 23)]) @MainActor
func selectedTitleAndBodyMutationPreservesTwoRevisionUpdates(
  noteCount: Int,
  selectedIndex: Int
) async throws {
  let fixture = await selectedMutationFixture(
    noteCount: noteCount,
    selectedIndex: selectedIndex
  )
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let initialGeneration = fixture.state.persistenceGeneration
  var workspacePublications = 0
  let observation = fixture.state.$workspace.dropFirst().sink { _ in
    workspacePublications += 1
  }

  fixture.state.updateSelected(title: "Changed title", body: "Changed body")
  try await waitForSelectedMutationSave(fixture.recorder, count: 1)

  #expect(fixture.state.selectedNote?.title == "Changed title")
  #expect(fixture.state.selectedNote?.body == "Changed body")
  #expect(fixture.state.selectedNote?.richTextRTF == fixture.selectedNote.richTextRTF)
  #expect(fixture.state.selectedNote?.revision == fixture.selectedNote.revision + 2)
  #expect(fixture.state.selectedNote?.modifiedAt != fixture.selectedNote.modifiedAt)
  #expect(fixture.state.persistenceGeneration == initialGeneration + 2)
  #expect(fixture.recorder.generations == [initialGeneration + 2])
  #expect(workspacePublications == 2)
  withExtendedLifetime(observation) {}
}

@Test @MainActor
func directWorkspaceAssignmentDetectsContentWithEqualRevision() async throws {
  let fixture = await selectedMutationFixture(noteCount: 10, selectedIndex: 5)
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let initialGeneration = fixture.state.persistenceGeneration
  var updatedWorkspace = fixture.state.workspace
  let selectedIndex = try #require(
    updatedWorkspace.notes.firstIndex(where: { $0.id == fixture.selectedNote.id })
  )
  updatedWorkspace.notes[selectedIndex].body += " external change"

  fixture.state.workspace = updatedWorkspace

  #expect(fixture.state.persistenceGeneration == initialGeneration + 1)
  #expect(fixture.state.selectedNote?.body == fixture.selectedNote.body + " external change")
  #expect(fixture.state.selectedNote?.revision == fixture.selectedNote.revision)
  #expect(fixture.state.selectedNote?.modifiedAt == fixture.selectedNote.modifiedAt)
}
