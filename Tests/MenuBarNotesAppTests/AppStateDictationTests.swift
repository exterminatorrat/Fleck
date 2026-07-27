import AppKit
import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func appStateDictationDestinationsExcludeTrash() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let active = Note(title: "Projects")
  let trashed = Note(title: "Deleted")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [active], selectedNoteID: active.id),
    preferences: .init(),
    trashedNotes: [trashed]
  )
  let state = try await loadedState(store: store, noteIDs: [active.id])

  #expect(
    state.activeDestinations()
      == [DictationDestination(noteID: active.id, title: "Projects")]
  )
}

@Test @MainActor func appStateDictationReusesCaseInsensitiveInboxWithoutPinningOrDuplicating()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "iNbOx", body: "Existing")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id])
  let firstCaptureID = UUID()

  let firstReceipt = try await state.saveSmartCapture(
    text: "First capture",
    captureID: firstCaptureID,
    destinationID: nil
  )
  let secondReceipt = try await state.saveSmartCapture(
    text: "Second capture",
    captureID: UUID(),
    destinationID: nil
  )

  #expect(firstReceipt.captureID == firstCaptureID)
  #expect(firstReceipt.noteID == inbox.id)
  #expect(firstReceipt.insertedSuffix == "\n\nFirst capture")
  #expect(secondReceipt.noteID == inbox.id)
  #expect(state.workspace.notes.count == 1)
  #expect(state.workspace.notes[0].title == "iNbOx")
  #expect(!state.workspace.notes[0].isPinned)
  #expect(state.workspace.notes[0].body == "Existing\n\nFirst capture\n\nSecond capture")
  #expect(state.saveStatus == .saved)

  let persisted = try await store.loadWorkspace()
  #expect(persisted.notes.count == 1)
  #expect(persisted.notes[0].id == inbox.id)
  #expect(persisted.notes[0].body == "Existing\n\nFirst capture\n\nSecond capture")
  #expect(persisted.notes[0].richTextRTF == state.workspace.notes[0].richTextRTF)
}

@Test @MainActor func appStateDictationCreatesOneNormalInboxOnDemand() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let existing = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [existing], selectedNoteID: existing.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [existing.id])

  let first = try await state.saveSmartCapture(
    text: "One",
    captureID: UUID(),
    destinationID: nil
  )
  let second = try await state.saveSmartCapture(
    text: "Two",
    captureID: UUID(),
    destinationID: nil
  )

  let inboxNotes = state.workspace.notes.filter {
    $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
  }
  #expect(inboxNotes.count == 1)
  #expect(inboxNotes[0].title == "Inbox")
  #expect(!inboxNotes[0].isPinned)
  #expect(first.noteID == inboxNotes[0].id)
  #expect(second.noteID == inboxNotes[0].id)
}

@Test @MainActor func appStateDictationAppendsRichTextUsingActiveEditorDefaults() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Projects", body: "Existing")
  let preferences = AppPreferences(fontFamily: "Menlo", fontSize: 21)
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: preferences
  )
  let state = try await loadedState(
    store: store,
    noteIDs: [note.id],
    fontFamily: preferences.fontFamily
  )

  _ = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: note.id
  )

  let updated = try #require(state.workspace.notes.first)
  let attributed = try attributedString(from: #require(updated.richTextRTF))
  let suffixLocation = attributed.length - "Captured".utf16.count
  let font = try #require(
    attributed.attribute(.font, at: suffixLocation, effectiveRange: nil) as? NSFont
  )
  #expect(updated.body == "Existing\n\nCaptured")
  #expect(attributed.string == updated.body)
  #expect(font.familyName == "Menlo")
  #expect(font.pointSize == 21)
}

@Test @MainActor func appStateDictationSaveReportsImmediateFailure() async throws {
  let container = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: container) }
  try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
  let blockedRoot = container.appendingPathComponent("not-a-directory")
  try Data("blocked".utf8).write(to: blockedRoot)
  let state = AppState(store: LocalStore(rootURL: blockedRoot))
  let note = Note(title: "Projects")
  let originalWorkspace = Workspace(notes: [note], selectedNoteID: note.id)
  state.workspace = originalWorkspace

  do {
    _ = try await state.saveSmartCapture(
      text: "Cannot persist",
      captureID: UUID(),
      destinationID: note.id
    )
    Issue.record("Expected the injected store save to fail")
  } catch {}

  #expect(state.workspace == originalWorkspace)
  #expect(state.saveError != nil)
  #expect(state.saveStatus == .idle)
}

@Test @MainActor func appStateDictationFailedSaveDoesNotOverwriteAnInterleavedLaterEdit()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Projects", body: "Existing")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave()
  let state = AppState(
    store: store,
    saveOperation: { workspace, preferences, trashedNotes in
      try await blockedSave.save(
        workspace: workspace,
        preferences: preferences,
        trashedNotes: trashedNotes
      )
    }
  )
  try await waitUntilLoaded(state, noteIDs: [note.id])

  let task = Task { @MainActor in
    try await state.saveSmartCapture(
      text: "Captured",
      captureID: UUID(),
      destinationID: note.id
    )
  }
  await blockedSave.waitUntilStarted()
  let index = try #require(state.workspace.notes.firstIndex(where: { $0.id == note.id }))
  let later = NoteTextAppender.appending("Later edit", to: state.workspace.notes[index])
  state.workspace.notes[index].body = later.body
  state.workspace.notes[index].richTextRTF = later.richTextRTF
  let laterEditedNote = state.workspace.notes[index]
  await blockedSave.fail()

  do {
    _ = try await task.value
    Issue.record("Expected the suspended save to fail")
  } catch {}

  #expect(state.workspace.notes[index] == laterEditedNote)
}

@Test @MainActor func appStateDictationTrashRefreshFailureDoesNotFailACommittedCapture()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects")
  let deleted = Note(title: "Deleted")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(
      notes: [destination, deleted],
      selectedNoteID: destination.id
    ),
    preferences: .init()
  )
  let controlledSave = CancelFirstThenPersist(store: store)
  let state = AppState(
    store: store,
    saveOperation: { workspace, preferences, trashedNotes in
      try await controlledSave.save(
        workspace: workspace,
        preferences: preferences,
        trashedNotes: trashedNotes
      )
    },
    loadTrashOperation: {
      throw AppStateDictationTestError.failed
    }
  )
  try await waitUntilLoaded(state, noteIDs: [destination.id, deleted.id])
  state.moveToTrash(deleted.id)
  await controlledSave.waitUntilFirstSaveStarted()

  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: destination.id
  )

  #expect(receipt.noteID == destination.id)
  #expect(state.saveStatus == .saved)
  #expect(try await store.loadWorkspace().notes[0].body == "Captured")
  #expect(try await store.loadTrash().map(\.id) == [deleted.id])
}

@Test @MainActor func appStateDictationCancelledSaveDoesNotPublishItsLaterGenericError()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let controlledSave = CancelledGenericFailureSave()
  let state = AppState(
    store: store,
    saveOperation: { workspace, preferences, trashedNotes in
      try await controlledSave.save(
        workspace: workspace,
        preferences: preferences,
        trashedNotes: trashedNotes
      )
    }
  )
  try await waitUntilLoaded(state, noteIDs: [note.id])
  state.saveNow()
  await controlledSave.waitUntilFirstSaveStarted()

  state.updateSelected(body: "Newer edit")
  await controlledSave.failFirstSave()
  try await Task.sleep(for: .milliseconds(50))

  #expect(state.saveError == nil)
  #expect(state.saveStatus == .saving)
  try await state.flushFocusedDictationSave()
}

@Test @MainActor func appStateDictationUndoRemovesOnlyTheRecordedSuffixAndPersists() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects", body: "Existing")
  let other = Note(title: "Other")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [destination, other], selectedNoteID: other.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [destination.id, other.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: destination.id
  )
  state.workspace.selectedNoteID = other.id

  let removed = await state.undoSmartCapture(receipt)

  #expect(removed)
  #expect(state.workspace.selectedNoteID == destination.id)
  let restored = try #require(state.workspace.notes.first(where: { $0.id == destination.id }))
  #expect(restored.body == "Existing")
  #expect(try attributedString(from: #require(restored.richTextRTF)).string == "Existing")
  let persisted = try await store.loadWorkspace()
  #expect(persisted.notes.first(where: { $0.id == destination.id })?.body == "Existing")
}

@Test @MainActor func appStateDictationUndoRefusesAfterLaterEditsAndSelectsDestination()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects", body: "Existing")
  let other = Note(title: "Other")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [destination, other], selectedNoteID: other.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [destination.id, other.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: destination.id
  )
  let index = try #require(state.workspace.notes.firstIndex(where: { $0.id == destination.id }))
  let later = NoteTextAppender.appending("Later edit", to: state.workspace.notes[index])
  state.workspace.notes[index].body = later.body
  state.workspace.notes[index].richTextRTF = later.richTextRTF
  state.workspace.selectedNoteID = other.id
  let bodyBeforeUndo = state.workspace.notes[index].body
  let richTextBeforeUndo = state.workspace.notes[index].richTextRTF

  let removed = await state.undoSmartCapture(receipt)

  #expect(!removed)
  #expect(state.workspace.selectedNoteID == destination.id)
  #expect(state.workspace.notes[index].body == bodyBeforeUndo)
  #expect(state.workspace.notes[index].richTextRTF == richTextBeforeUndo)
}

@Test @MainActor func appStateDictationUndoRequiresTheRichTextSuffixToMatch() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects", body: "Existing")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [destination], selectedNoteID: destination.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: destination.id
  )
  let mismatchedRTF = NoteTextAppender.appending(
    "Different",
    to: Note(body: "Existing")
  ).richTextRTF
  state.workspace.notes[0].richTextRTF = mismatchedRTF

  let removed = await state.undoSmartCapture(receipt)

  #expect(!removed)
  #expect(state.workspace.notes[0].body == "Existing\n\nCaptured")
  #expect(state.workspace.notes[0].richTextRTF == mismatchedRTF)
}

@Test @MainActor func appStateDictationFocusedFlushAwaitsTheActualSaveOutcome() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [note.id])
  state.updateSelected(body: "Focused text")

  try await state.flushFocusedDictationSave()

  #expect(state.saveStatus == .saved)
  #expect(try await store.loadWorkspace().notes[0].body == "Focused text")
}

@Test @MainActor func appStateDictationFocusedFlushThrowsTheActualSaveFailure() async throws {
  let container = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: container) }
  try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
  let blockedRoot = container.appendingPathComponent("not-a-directory")
  try Data("blocked".utf8).write(to: blockedRoot)
  let state = AppState(store: LocalStore(rootURL: blockedRoot))
  let note = Note(title: "Projects")
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id)
  state.updateSelected(body: "Focused text")

  do {
    try await state.flushFocusedDictationSave()
    Issue.record("Expected the injected store flush to fail")
  } catch {}

  #expect(state.saveError != nil)
  #expect(state.saveStatus == .idle)
}

@MainActor
private func loadedState(
  store: LocalStore,
  noteIDs: [UUID],
  fontFamily: String = AppPreferences().fontFamily
) async throws -> AppState {
  let state = AppState(store: store)
  try await waitUntilLoaded(state, noteIDs: noteIDs, fontFamily: fontFamily)
  return state
}

@MainActor
private func waitUntilLoaded(
  _ state: AppState,
  noteIDs: [UUID],
  fontFamily: String = AppPreferences().fontFamily
) async throws {
  let deadline = ContinuousClock.now + .seconds(2)
  while (
    state.workspace.notes.map(\.id) != noteIDs
      || state.preferences.fontFamily != fontFamily
  ), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(state.workspace.notes.map(\.id) == noteIDs)
  #expect(state.preferences.fontFamily == fontFamily)
}

private func temporaryStoreRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@MainActor
private func attributedString(from rtf: Data) throws -> NSAttributedString {
  try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
}

private enum AppStateDictationTestError: Error {
  case failed
}

private actor BlockingFailureSave {
  private var started = false
  private var continuation: CheckedContinuation<Void, Never>?

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note]
  ) async throws {
    started = true
    await withCheckedContinuation { continuation = $0 }
    throw AppStateDictationTestError.failed
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func fail() {
    continuation?.resume()
    continuation = nil
  }
}

private actor CancelFirstThenPersist {
  private let store: LocalStore
  private var saveCount = 0
  private var firstSaveStarted = false

  init(store: LocalStore) {
    self.store = store
  }

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note]
  ) async throws {
    saveCount += 1
    if saveCount == 1 {
      firstSaveStarted = true
      try await Task.sleep(for: .seconds(30))
      return
    }
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: trashedNotes
    )
  }

  func waitUntilFirstSaveStarted() async {
    while !firstSaveStarted { await Task.yield() }
  }
}

private actor CancelledGenericFailureSave {
  private var saveCount = 0
  private var firstSaveStarted = false
  private var firstSaveContinuation: CheckedContinuation<Void, Never>?

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note]
  ) async throws {
    saveCount += 1
    if saveCount == 1 {
      firstSaveStarted = true
      await withCheckedContinuation { firstSaveContinuation = $0 }
      throw AppStateDictationTestError.failed
    }
  }

  func waitUntilFirstSaveStarted() async {
    while !firstSaveStarted { await Task.yield() }
  }

  func failFirstSave() {
    firstSaveContinuation?.resume()
    firstSaveContinuation = nil
  }
}
