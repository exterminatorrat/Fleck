import AppKit
import FleckCore
import Foundation
import SwiftUI
import Testing

@testable import FleckApp

@Suite(.serialized)
@MainActor
struct NoteFileReferenceUITests {
  @Test func appStateUsesDedicatedSidecarAndKeepsNoteContentUnchanged() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Source", body: "Keep this body")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let fileURL = try fixture.makeFile(named: "outline.pdf")
    let exportBefore = NoteExport(note: note, format: .markdown).data

    #expect(state.addFileReference(noteID: note.id, url: fileURL))
    #expect(state.selectedNoteFileReferences.map(\.filename) == ["outline.pdf"])
    #expect(state.selectedNoteFileReferences.allSatisfy { $0.isAvailable })
    #expect(state.selectedNote?.title == "Source")
    #expect(state.selectedNote?.body == "Keep this body")
    #expect(
      NoteExport(
        note: try #require(state.selectedNote),
        format: .markdown
      ).data == exportBefore
    )
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.rootURL
          .appendingPathComponent("FileReferences/references.json").path
      )
    )
  }

  @Test func movingToTrashAndRestoringTheNoteRetainsItsShortcuts() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Restore")
    let state = AppState(store: LocalStore(rootURL: fixture.rootURL))
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    let fileURL = try fixture.makeFile(named: "retained.txt")
    #expect(state.addFileReference(noteID: note.id, url: fileURL))

    #expect(state.moveToTrash(note.id))
    try await state.saveNow().value
    await state.refreshTrash()
    #expect(state.fileReferences(noteID: note.id).count == 1)
    let trashed = try #require(state.trashedNotes.first(where: { $0.id == note.id }))
    let restore = try #require(state.restore(trashed))
    await restore.value
    state.refreshSelectedNoteFileReferences()

    #expect(state.selectedNote?.id == note.id)
    #expect(state.selectedNoteFileReferences.map(\.filename) == ["retained.txt"])
  }

  @Test func pickerResultKeepsCapturedNoteIdentityAfterSelectionChanges() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let first = Note(title: "First")
    let second = Note(title: "Second")
    let state = await fixture.state(
      workspace: Workspace(
        notes: [first, second],
        selectedNoteID: first.id,
        folders: []
      )
    )
    let fileURL = try fixture.makeFile(named: "first.txt")

    state.workspace.selectedNoteID = second.id
    #expect(state.addFileReference(noteID: first.id, url: fileURL))
    #expect(state.fileReferences(noteID: first.id).count == 1)
    #expect(state.fileReferences(noteID: second.id).isEmpty)

    NotesPanel.completeFileReferenceSelection(
      nil,
      noteID: first.id,
      appState: state
    )
    #expect(state.fileReferences(noteID: first.id).count == 1)

    state.workspace.deleteNote(id: first.id)
    NotesPanel.completeFileReferenceSelection(
      fileURL,
      noteID: first.id,
      appState: state
    )
    #expect(state.fileReferences(noteID: first.id).count == 1)
  }

  @Test func unavailableFilesRemainVisibleAndCanBeRelinked() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Reference")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let originalURL = try fixture.makeFile(named: "missing.txt")
    #expect(state.addFileReference(noteID: note.id, url: originalURL))
    let referenceID = try #require(state.selectedNoteFileReferences.first?.id)
    try FileManager.default.removeItem(at: originalURL)

    state.refreshSelectedNoteFileReferences()
    #expect(state.selectedNoteFileReferences.first?.isAvailable == false)
    #expect(state.selectedNoteFileReferences.first?.filename == "missing.txt")

    let replacementURL = try fixture.makeFile(named: "replacement.txt")
    let other = Note(title: "Other")
    state.workspace.notes.append(other)
    state.workspace.selectedNoteID = other.id
    #expect(state.relinkFileReference(referenceID: referenceID, url: replacementURL))
    state.workspace.selectedNoteID = note.id
    state.refreshSelectedNoteFileReferences()
    #expect(state.selectedNoteFileReferences.first?.isAvailable == true)
    #expect(state.selectedNoteFileReferences.first?.filename == "replacement.txt")

    NotesPanel.completeFileReferenceRelink(
      nil,
      referenceID: referenceID,
      appState: state
    )
    #expect(state.selectedNoteFileReferences.first?.filename == "replacement.txt")
  }

  @Test func noteLockedBeforePickerCompletionRejectsTheResult() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Locked")
    let gate = NoteFileReferenceAsyncGate()
    let state = AppState(
      store: LocalStore(rootURL: fixture.rootURL),
      replaceAgentCapabilities: { _, _ in
        await gate.waitForRelease()
        return AgentCapabilityState(profiles: [:], unassignedLegacyNoteIDs: [])
      }
    )
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    let context = AgentCapabilityPresentation.noteAccessContext(
      for: note.id,
      in: state.workspace
    )
    let transaction = Task {
      await state.updateAgentCapabilitiesForNote(
        noteID: note.id,
        capturedContext: context,
        replacements: [],
        expectedGrantRevisions: [:]
      )
    }
    await gate.waitUntilStarted()
    let fileURL = try fixture.makeFile(named: "locked.txt")

    NotesPanel.completeFileReferenceSelection(
      fileURL,
      noteID: note.id,
      appState: state
    )
    #expect(state.fileReferences(noteID: note.id).isEmpty)
    await gate.release()
    _ = await transaction.value
  }

  @Test func removeRegistersUndoAndRedoWithoutChangingTheNote() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Undo", body: "Unchanged")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let fileURL = try fixture.makeFile(named: "undo.txt")
    #expect(state.addFileReference(noteID: note.id, url: fileURL))
    let referenceID = try #require(state.selectedNoteFileReferences.first?.id)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false

    undoManager.beginUndoGrouping()
    #expect(state.removeFileReference(referenceID: referenceID, undoManager: undoManager))
    undoManager.endUndoGrouping()
    #expect(state.selectedNoteFileReferences.isEmpty)
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(state.selectedNoteFileReferences.count == 1)
    #expect(undoManager.canRedo)
    undoManager.redo()
    #expect(state.selectedNoteFileReferences.isEmpty)
    #expect(state.selectedNote?.body == "Unchanged")
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test func corruptSidecarIsPreservedAndBlocksShortcutWrites() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let sidecarURL = fixture.rootURL
      .appendingPathComponent("FileReferences", isDirectory: true)
      .appendingPathComponent("references.json")
    try FileManager.default.createDirectory(
      at: sidecarURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let corrupt = Data("not-json\n".utf8)
    try corrupt.write(to: sidecarURL)
    let note = Note(title: "Corrupt")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let fileURL = try fixture.makeFile(named: "blocked.txt")

    #expect(state.noteFileReferenceError != nil)
    #expect(!state.addFileReference(noteID: note.id, url: fileURL))
    #expect(try Data(contentsOf: sidecarURL) == corrupt)
  }

  @Test func sidecarSaveFailureKeepsVisibleAssociationsUnchanged() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Write failure")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let firstURL = try fixture.makeFile(named: "first.txt")
    let secondURL = try fixture.makeFile(named: "second.txt")
    #expect(state.addFileReference(noteID: note.id, url: firstURL))
    let sidecarURL = fixture.rootURL.appendingPathComponent("FileReferences/references.json")
    let originalBytes = try Data(contentsOf: sidecarURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o444],
      ofItemAtPath: sidecarURL.path
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: sidecarURL.deletingLastPathComponent().path
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: sidecarURL.deletingLastPathComponent().path
      )
    }

    let renamedURL = fixture.rootURL.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: firstURL, to: renamedURL)
    state.refreshSelectedNoteFileReferences()
    #expect(state.selectedNoteFileReferences.first?.isAvailable == true)
    #expect(state.noteFileReferenceError == "File shortcuts could not be saved.")

    #expect(!state.addFileReference(noteID: note.id, url: secondURL))
    #expect(state.selectedNoteFileReferences.map(\.filename) == ["first.txt"])
    #expect(try Data(contentsOf: sidecarURL) == originalBytes)
    #expect(state.noteFileReferenceError == "File shortcuts could not be saved.")

  }

  @Test func hostedBodyAndTitleSupplyTheirNativeUndoManager() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Native undo", body: "Body")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let commands = EditorCommands()
    let runtime = DictationRuntime(appState: state, applicationSupportURL: fixture.rootURL)
    let host = NSHostingView(
      rootView: NotesPanel(dictationRuntime: runtime, editorCommands: commands)
        .environmentObject(state)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
      styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    await settleReferenceHost(host)
    let body = try #require(referenceDescendant(in: host, as: ListAwareTextView.self))
    let title = try #require(referenceTitleField(in: host, value: note.title))

    #expect(window.makeFirstResponder(body))
    #expect(NotesPanel.fileReferenceUndoManager(commands: commands) === body.undoManager)
    #expect(window.makeFirstResponder(title))
    let fieldEditor = try #require(title.currentEditor() as? NSTextView)
    #expect(
      NotesPanel.fileReferenceUndoManager(commands: commands)
        === fieldEditor.undoManager
    )
  }
}

private actor NoteFileReferenceAsyncGate {
  private var started = false
  private var released = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func waitForRelease() async {
    started = true
    for waiter in startWaiters {
      waiter.resume()
    }
    startWaiters.removeAll()
    guard !released else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    released = true
    for waiter in releaseWaiters {
      waiter.resume()
    }
    releaseWaiters.removeAll()
  }
}

@MainActor
private struct NoteFileReferenceUIFixture {
  let rootURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("note-file-reference-ui-\(UUID().uuidString)")

  init() throws {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  func state(workspace: Workspace) async -> AppState {
    let state = AppState(
      store: LocalStore(rootURL: rootURL),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    state.workspace = workspace
    state.refreshSelectedNoteFileReferences()
    return state
  }

  func makeFile(named name: String) throws -> URL {
    let url = rootURL.appendingPathComponent(name)
    try Data("contents".utf8).write(to: url)
    return url
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

@MainActor
private func settleReferenceHost(_ host: NSView) async {
  for _ in 0..<8 {
    try? await Task.sleep(for: .milliseconds(10))
    await Task.yield()
    host.layoutSubtreeIfNeeded()
  }
}

@MainActor
private func referenceDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = referenceDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func referenceTitleField(in view: NSView, value: String) -> NSTextField? {
  if let field = view as? NSTextField,
    field.stringValue == value,
    field.placeholderString == "Note title"
  {
    return field
  }
  for subview in view.subviews {
    if let match = referenceTitleField(in: subview, value: value) { return match }
  }
  return nil
}
