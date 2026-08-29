import AppKit
import Foundation
import FleckCore
import Testing

@testable import FleckApp

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
      == [DictationRoutingCandidate(
        destination: DictationDestination(noteID: active.id, title: "Projects"),
        semanticContext: "",
        contentRevision: active.revision
      )]
  )
}

@Test @MainActor func appStateDictationDestinationsKeepCompleteRawBodyAndRevision() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let beginning = "BEGINNING context"
  let ending = "ENDING context"
  let rawBody =
    "  \(beginning)\n\n\(String(repeating: "middle ", count: 100))\t\(ending)  "
  let note = Note(
    title: "Project",
    body: rawBody,
    revision: 47
  )
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [note.id])

  let candidate = try #require(state.activeDestinations().first)

  #expect(candidate.destination == DictationDestination(noteID: note.id, title: "Project"))
  #expect(candidate.semanticContext == rawBody)
  #expect(candidate.semanticContext.contains("middle middle middle"))
  #expect(candidate.contentRevision == 47)
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
  let blockedSave = BlockingFailureSave(store: store)
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

@Test @MainActor func appStateDictationFailedCaptureDoesNotLeakIntoALaterEditorSave()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects", body: "Existing")
  let editorNote = Note(title: "Editor")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(
      notes: [destination, editorNote],
      selectedNoteID: editorNote.id
    ),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave(store: store)
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
  try await waitUntilLoaded(state, noteIDs: [destination.id, editorNote.id])

  let task = Task { @MainActor in
    try await state.saveSmartCapture(
      text: "Captured",
      captureID: UUID(),
      destinationID: destination.id
    )
  }
  await blockedSave.waitUntilStarted()
  state.updateSelected(body: "Later editor text")
  await blockedSave.fail()

  do {
    _ = try await task.value
    Issue.record("Expected the suspended capture save to fail")
  } catch {}
  await blockedSave.waitUntilSaveCount(2)

  let persisted = try await store.loadWorkspace()
  #expect(persisted.notes.first(where: { $0.id == destination.id })?.body == "Existing")
  #expect(persisted.notes.first(where: { $0.id == editorNote.id })?.body == "Later editor text")
}

@Test @MainActor func appStateDictationSelectedFailedInboxKeepsOnlyTheBlankInboxShell()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let existing = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [existing], selectedNoteID: existing.id),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave(store: store)
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
  try await waitUntilLoaded(state, noteIDs: [existing.id])

  let task = Task { @MainActor in
    try await state.saveSmartCapture(
      text: "Captured",
      captureID: UUID(),
      destinationID: nil
    )
  }
  await blockedSave.waitUntilStarted()
  let inboxID = try #require(
    state.workspace.notes.first(where: {
      $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
    })?.id
  )
  let attemptedInbox = try #require(state.workspace.notes.first(where: { $0.id == inboxID }))
  state.select(inboxID)
  await blockedSave.fail()

  do {
    _ = try await task.value
    Issue.record("Expected the suspended Inbox save to fail")
  } catch {}
  await blockedSave.waitUntilSaveCount(2)

  let inbox = try #require(state.workspace.notes.first(where: { $0.id == inboxID }))
  #expect(state.workspace.selectedNoteID == inboxID)
  #expect(inbox.title == "Inbox")
  #expect(inbox.body.isEmpty)
  #expect(inbox.richTextRTF == nil)
  #expect(inbox.tabColorHex == nil)
  #expect(!inbox.isPinned)
  #expect(inbox.createdAt == attemptedInbox.createdAt)
  #expect(inbox.modifiedAt != attemptedInbox.modifiedAt)
  let persistedInbox = try #require(
    try await store.loadWorkspace().notes.first(where: { $0.id == inboxID })
  )
  #expect(persistedInbox.body.isEmpty)
  #expect(persistedInbox.richTextRTF == nil)
}

@Test @MainActor func appStateDictationTrashingAnotherNoteCannotPersistAFailedCapture()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects", body: "Existing")
  let deleted = Note(title: "Deleted")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(
      notes: [destination, deleted],
      selectedNoteID: destination.id
    ),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave(store: store)
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
  try await waitUntilLoaded(state, noteIDs: [destination.id, deleted.id])

  let task = Task { @MainActor in
    try await state.saveSmartCapture(
      text: "Captured",
      captureID: UUID(),
      destinationID: destination.id
    )
  }
  await blockedSave.waitUntilStarted()
  state.moveToTrash(deleted.id)
  await blockedSave.fail()

  do {
    _ = try await task.value
    Issue.record("Expected the suspended capture save to fail")
  } catch {}
  await blockedSave.waitUntilSaveCount(2)

  let persisted = try await store.loadWorkspace()
  #expect(persisted.notes.first(where: { $0.id == destination.id })?.body == "Existing")
  #expect(try await store.loadTrash().map(\.id) == [deleted.id])
}

@Test @MainActor func appStateDictationTrashingDestinationCannotArchiveAFailedCapture()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = Note(title: "Projects", body: "Existing")
  let remaining = Note(title: "Remaining")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(
      notes: [destination, remaining],
      selectedNoteID: destination.id
    ),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave(store: store)
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
  try await waitUntilLoaded(state, noteIDs: [destination.id, remaining.id])

  let task = Task { @MainActor in
    try await state.saveSmartCapture(
      text: "Captured",
      captureID: UUID(),
      destinationID: destination.id
    )
  }
  await blockedSave.waitUntilStarted()
  state.moveToTrash(destination.id)
  await blockedSave.fail()

  do {
    _ = try await task.value
    Issue.record("Expected the suspended capture save to fail")
  } catch {}
  await blockedSave.waitUntilSaveCount(2)

  #expect(!state.workspace.notes.contains(where: { $0.id == destination.id }))
  let persisted = try await store.loadWorkspace()
  #expect(!persisted.notes.contains(where: { $0.id == destination.id }))
  let trashedDestination = try #require(
    try await store.loadTrash().first(where: { $0.id == destination.id })
  )
  #expect(trashedDestination.note.body == "Existing")
  #expect(trashedDestination.note.richTextRTF == destination.richTextRTF)
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
  await controlledSave.cancelFirstSave()

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
  state.updateSelected(body: "First edit")
  await controlledSave.waitUntilFirstSaveStarted()

  state.updateSelected(body: "Newer edit")
  await controlledSave.failFirstSave()
  try await Task.sleep(for: .milliseconds(50))

  #expect(state.saveError == nil)
  #expect(state.saveStatus == .saving)
  try await state.flushFocusedDictationSave()
}

@Test @MainActor func appStateDictationMovesCommittedCaptureFromNonemptySource() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox", body: "Existing Inbox")
  let destination = Note(title: "Projects", body: "Existing Project")
  let selected = Note(title: "Selected")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(
      notes: [inbox, destination, selected],
      selectedNoteID: selected.id
    ),
    preferences: .init()
  )
  let state = try await loadedState(
    store: store,
    noteIDs: [inbox.id, destination.id, selected.id]
  )
  let captureID = UUID()
  let receipt = try await state.saveSmartCapture(
    text: "\n\nCaptured",
    captureID: captureID,
    destinationID: inbox.id
  )

  let moved = await state.moveSmartCapture(receipt, to: destination.id)

  #expect(
    moved
      == DictationInsertionReceipt(
        captureID: captureID,
        noteID: destination.id,
        insertedSuffix: "\n\n\n\nCaptured"
      )
  )
  #expect(state.workspace.selectedNoteID == selected.id)
  #expect(state.workspace.notes.first(where: { $0.id == inbox.id })?.body == "Existing Inbox")
  #expect(
    state.workspace.notes.first(where: { $0.id == destination.id })?.body
      == "Existing Project\n\n\n\nCaptured"
  )
  let persisted = try await store.loadWorkspace()
  #expect(persisted.notes.first(where: { $0.id == inbox.id })?.body == "Existing Inbox")
  #expect(
    persisted.notes.first(where: { $0.id == destination.id })?.body
      == "Existing Project\n\n\n\nCaptured"
  )
}

@Test @MainActor func appStateDictationMovesEmptyInboxCaptureWithRichText() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox")
  let destinationBody = "Existing Project"
  let destination = Note(
    title: "Projects",
    body: destinationBody,
    richTextRTF: NoteTextAppender.appending(destinationBody, to: Note()).richTextRTF
  )
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id, destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )

  let moved = try #require(await state.moveSmartCapture(receipt, to: destination.id))

  #expect(moved.insertedSuffix == "\n\nCaptured")
  let source = try #require(state.workspace.notes.first(where: { $0.id == inbox.id }))
  let target = try #require(state.workspace.notes.first(where: { $0.id == destination.id }))
  #expect(source.body.isEmpty)
  #expect(try attributedString(from: #require(source.richTextRTF)).string.isEmpty)
  #expect(target.body == "Existing Project\n\nCaptured")
  #expect(
    try attributedString(from: #require(target.richTextRTF)).string
      == "Existing Project\n\nCaptured"
  )
  #expect(state.workspace.notes.contains(where: { $0.id == inbox.id }))
}

@Test @MainActor func appStateDictationMoveRefusesStaleBodyOrRichText() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox", body: "Existing")
  let destination = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id, destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let sourceIndex = try #require(state.workspace.notes.firstIndex(where: { $0.id == inbox.id }))
  let committedBody = state.workspace.notes[sourceIndex].body
  let committedRTF = state.workspace.notes[sourceIndex].richTextRTF
  state.workspace.notes[sourceIndex].body += " later"

  #expect(await state.moveSmartCapture(receipt, to: destination.id) == nil)

  state.workspace.notes[sourceIndex].body = committedBody
  state.workspace.notes[sourceIndex].richTextRTF = NoteTextAppender.appending(
    "Different",
    to: Note(body: "Existing")
  ).richTextRTF
  #expect(await state.moveSmartCapture(receipt, to: destination.id) == nil)
  #expect(state.workspace.notes[sourceIndex].body == committedBody)
  #expect(state.workspace.notes[sourceIndex].richTextRTF != committedRTF)
  #expect(state.workspace.notes.first(where: { $0.id == destination.id })?.body.isEmpty == true)
}

@Test @MainActor func appStateDictationMoveRefusesInvalidReceiptOrDestination() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox")
  let destination = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id, destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let committedWorkspace = state.workspace

  #expect(
    await state.moveSmartCapture(
      DictationInsertionReceipt(
        captureID: receipt.captureID,
        noteID: UUID(),
        insertedSuffix: receipt.insertedSuffix
      ),
      to: destination.id
    ) == nil
  )
  #expect(await state.moveSmartCapture(receipt, to: UUID()) == nil)
  #expect(await state.moveSmartCapture(receipt, to: inbox.id) == nil)
  #expect(
    await state.moveSmartCapture(
      DictationInsertionReceipt(
        captureID: receipt.captureID,
        noteID: receipt.noteID,
        insertedSuffix: ""
      ),
      to: destination.id
    ) == nil
  )
  #expect(state.workspace == committedWorkspace)
}

@Test @MainActor func appStateDictationMoveRejectsDuplicateCallback() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox")
  let destination = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id, destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )
  _ = try #require(await state.moveSmartCapture(receipt, to: destination.id))
  let movedWorkspace = state.workspace

  #expect(await state.moveSmartCapture(receipt, to: destination.id) == nil)
  #expect(state.workspace == movedWorkspace)
}

@Test @MainActor func appStateDictationOlderIdenticalReceiptCannotMoveNewerTail() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox")
  let destination = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id, destination.id])
  let older = try await state.saveSmartCapture(
    text: "Same",
    captureID: UUID(),
    destinationID: inbox.id
  )
  _ = try await state.saveSmartCapture(
    text: "Same",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let committedWorkspace = state.workspace

  #expect(await state.moveSmartCapture(older, to: destination.id) == nil)
  #expect(state.workspace == committedWorkspace)
}

@Test @MainActor func appStateDictationFailedMoveRestoresNotesSelectionAndReceiptBinding()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox", body: "Existing Inbox")
  let destination = Note(title: "Projects", body: "Existing Project")
  let selected = Note(title: "Selected")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(
      notes: [inbox, destination, selected],
      selectedNoteID: selected.id
    ),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave(store: store, blockedAttempt: 2)
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
  try await waitUntilLoaded(state, noteIDs: [inbox.id, destination.id, selected.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let committedWorkspace = state.workspace
  let task = Task { @MainActor in
    await state.moveSmartCapture(receipt, to: destination.id)
  }
  await blockedSave.waitUntilStarted()
  await blockedSave.fail()

  #expect(await task.value == nil)
  #expect(state.workspace == committedWorkspace)
  #expect(state.workspace.selectedNoteID == selected.id)

  let retry = await state.moveSmartCapture(receipt, to: destination.id)
  #expect(retry?.noteID == destination.id)
}

@Test @MainActor func appStateDictationFailedMoveDoesNotOverwriteInterleavedEditAfterReorder()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox", body: "Existing Inbox")
  let destination = Note(title: "Projects", body: "Existing Project")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let blockedSave = BlockingFailureSave(store: store, blockedAttempt: 2)
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
  try await waitUntilLoaded(state, noteIDs: [inbox.id, destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let task = Task { @MainActor in
    await state.moveSmartCapture(receipt, to: destination.id)
  }
  await blockedSave.waitUntilStarted()
  state.moveNote(destination.id, to: 0)
  let later = NoteTextAppender.appending("Later destination edit", to: Note())
  state.workspace.updateContent(
    id: destination.id,
    body: later.body,
    rtf: later.richTextRTF
  )
  await blockedSave.fail()

  #expect(await task.value == nil)
  #expect(state.workspace.notes.map(\.id) == [destination.id, inbox.id])
  #expect(
    state.workspace.notes.first(where: { $0.id == inbox.id })?.body
      == "Existing Inbox\n\nCaptured"
  )
  #expect(
    state.workspace.notes.first(where: { $0.id == destination.id })?.body
      == "Later destination edit"
  )
}

@Test @MainActor func appStateDictationCancelledMoveLeavesSourceAuthoritative() async throws {
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox", body: "Existing Inbox")
  let destination = Note(title: "Projects", body: "Existing Project")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let blockedSave = CancellationAwareBlockedSave(store: store)
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
  try await waitUntilLoaded(state, noteIDs: [inbox.id, destination.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let committedWorkspace = state.workspace
  let task = Task { @MainActor in
    await state.moveSmartCapture(receipt, to: destination.id)
  }
  await blockedSave.waitUntilStarted()
  task.cancel()
  await blockedSave.release()

  #expect(await task.value == nil)
  #expect(state.workspace == committedWorkspace)
  let persisted = try await store.loadWorkspace()
  #expect(
    persisted.notes.first(where: { $0.id == inbox.id })?.body
      == "Existing Inbox\n\nCaptured"
  )
  #expect(
    persisted.notes.first(where: { $0.id == destination.id })?.body
      == "Existing Project"
  )
  #expect(await state.moveSmartCapture(receipt, to: destination.id)?.noteID == destination.id)
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

@Test @MainActor func appStateDictationUndoClearsReceiptBindingForIdenticalPriorTail()
  async throws
{
  let root = temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let inbox = Note(title: "Inbox")
  let destination = Note(title: "Projects")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [inbox, destination], selectedNoteID: inbox.id),
    preferences: .init()
  )
  let state = try await loadedState(store: store, noteIDs: [inbox.id, destination.id])
  let older = try await state.saveSmartCapture(
    text: "Same",
    captureID: UUID(),
    destinationID: inbox.id
  )
  let newer = try await state.saveSmartCapture(
    text: "Same",
    captureID: UUID(),
    destinationID: inbox.id
  )

  #expect(await state.undoSmartCapture(newer))
  let afterUndo = state.workspace
  #expect(await state.moveSmartCapture(older, to: destination.id) == nil)
  #expect(!(await state.undoSmartCapture(older)))
  #expect(state.workspace == afterUndo)
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

@Test @MainActor func appStateDictationFailedUndoPreservesLaterEditsAfterReordering()
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
  let blockedSave = BlockingFailureSave(store: store, blockedAttempt: 2)
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
  try await waitUntilLoaded(state, noteIDs: [destination.id, other.id])
  let receipt = try await state.saveSmartCapture(
    text: "Captured",
    captureID: UUID(),
    destinationID: destination.id
  )

  let task = Task { @MainActor in
    await state.undoSmartCapture(receipt)
  }
  await blockedSave.waitUntilStarted()
  state.moveNote(destination.id, to: 1)
  state.updateSelected(body: "Later edit")
  let laterRTF = NoteTextAppender.appending("Later edit", to: Note()).richTextRTF
  state.updateSelectedRichTextRTF(laterRTF)
  await blockedSave.fail()

  #expect(!(await task.value))
  let updated = try #require(state.workspace.notes.first(where: { $0.id == destination.id }))
  #expect(state.workspace.notes.map(\.id) == [other.id, destination.id])
  #expect(state.workspace.selectedNoteID == destination.id)
  #expect(updated.body == "Later edit")
  #expect(updated.richTextRTF == laterRTF)
  try await state.flushFocusedDictationSave()
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
  private let store: LocalStore
  private let blockedAttempt: Int
  private var saveCount = 0
  private var started = false
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var saveCountTarget: Int?
  private var saveCountContinuation: CheckedContinuation<Void, Never>?
  private var continuation: CheckedContinuation<Void, Never>?

  init(store: LocalStore, blockedAttempt: Int = 1) {
    self.store = store
    self.blockedAttempt = blockedAttempt
  }

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note]
  ) async throws {
    saveCount += 1
    signalSaveCountIfNeeded()
    if saveCount == blockedAttempt {
      started = true
      startedContinuation?.resume()
      startedContinuation = nil
      await withCheckedContinuation { continuation = $0 }
      throw AppStateDictationTestError.failed
    }
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: trashedNotes
    )
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func waitUntilSaveCount(_ expectedCount: Int) async {
    guard saveCount < expectedCount else { return }
    saveCountTarget = expectedCount
    await withCheckedContinuation { saveCountContinuation = $0 }
  }

  func fail() {
    continuation?.resume()
    continuation = nil
  }

  private func signalSaveCountIfNeeded() {
    guard let saveCountTarget, saveCount >= saveCountTarget else { return }
    self.saveCountTarget = nil
    saveCountContinuation?.resume()
    saveCountContinuation = nil
  }
}

private actor CancellationAwareBlockedSave {
  private let store: LocalStore
  private var saveCount = 0
  private var started = false
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(store: LocalStore) {
    self.store = store
  }

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note]
  ) async throws {
    saveCount += 1
    if saveCount == 2 {
      started = true
      startedContinuation?.resume()
      startedContinuation = nil
      await withCheckedContinuation { releaseContinuation = $0 }
      try Task.checkCancellation()
    }
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: trashedNotes
    )
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor CancelFirstThenPersist {
  private let store: LocalStore
  private var saveCount = 0
  private var firstSaveStarted = false
  private var firstSaveStartedContinuation: CheckedContinuation<Void, Never>?
  private var firstSaveContinuation: CheckedContinuation<Void, Never>?

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
      firstSaveStartedContinuation?.resume()
      firstSaveStartedContinuation = nil
      await withCheckedContinuation { firstSaveContinuation = $0 }
      throw CancellationError()
    }
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: trashedNotes
    )
  }

  func waitUntilFirstSaveStarted() async {
    guard !firstSaveStarted else { return }
    await withCheckedContinuation { firstSaveStartedContinuation = $0 }
  }

  func cancelFirstSave() {
    firstSaveContinuation?.resume()
    firstSaveContinuation = nil
  }
}

private actor CancelledGenericFailureSave {
  private var saveCount = 0
  private var firstSaveStarted = false
  private var firstSaveStartedContinuation: CheckedContinuation<Void, Never>?
  private var firstSaveContinuation: CheckedContinuation<Void, Never>?

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note]
  ) async throws {
    saveCount += 1
    if saveCount == 1 {
      firstSaveStarted = true
      firstSaveStartedContinuation?.resume()
      firstSaveStartedContinuation = nil
      await withCheckedContinuation { firstSaveContinuation = $0 }
      throw AppStateDictationTestError.failed
    }
  }

  func waitUntilFirstSaveStarted() async {
    guard !firstSaveStarted else { return }
    await withCheckedContinuation { firstSaveStartedContinuation = $0 }
  }

  func failFirstSave() {
    firstSaveContinuation?.resume()
    firstSaveContinuation = nil
  }
}
