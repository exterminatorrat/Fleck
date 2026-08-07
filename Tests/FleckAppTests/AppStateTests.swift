import AppKit
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

private enum AppStateTestError: Error {
  case failed
}

private final class SaveRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedGenerations: [UInt64] = []

  var generations: [UInt64] {
    lock.withLock { recordedGenerations }
  }

  func record(generation: UInt64) {
    lock.withLock {
      recordedGenerations.append(generation)
    }
  }
}

private func folder(named name: String) throws -> Folder {
  try Folder(id: UUID(), name: name)
}

@MainActor
private func folderedState(
  workspace: Workspace,
  recorder: SaveRecorder? = nil
) async -> AppState {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, generation in
      recorder?.record(generation: generation)
      return .committed
    }
  )
  await state.waitUntilInitialLoad()
  state.workspace = workspace
  return state
}

private func waitForSaveCount(
  _ recorder: SaveRecorder,
  _ expected: Int
) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while recorder.generations.count < expected, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(25))
  }
}

@Test @MainActor func appStateExposesFreshInitialSnapshotSource() async {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root))

  await state.waitUntilInitialLoad()

  #expect(state.initialSnapshotSource == .fresh)
}

@Test @MainActor func onboardingProgressPersistenceRollsBackAfterFailure() async {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _ in throw AppStateTestError.failed }
  )
  await state.waitUntilInitialLoad()
  let progress = OnboardingProgress(status: .inProgress(step: .welcome))

  await #expect(throws: AppStateTestError.self) {
    try await state.persistOnboardingProgress(progress)
  }
  #expect(state.preferences.onboardingProgress == nil)
}

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

@Test @MainActor func editorContentCallbackIncrementsRevisionOnce() async {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _ in }
  )
  await state.waitUntilInitialLoad()
  let commands = EditorCommands()
  let editor = NativeRichTextEditor(
    text: state.selectedNote!.body,
    richTextRTF: state.selectedNote!.richTextRTF,
    onChange: { body, richTextRTF in
      state.updateSelected(body: body, richTextRTF: richTextRTF)
    },
    fontFamily: state.preferences.fontFamily,
    fontSize: state.preferences.fontSize,
    textColorHex: state.preferences.editorTextHex,
    backgroundColorHex: state.preferences.editorBackgroundHex,
    accentColorHex: state.preferences.accentHex,
    reduceMotion: false,
    automaticLists: state.preferences.automaticLists,
    commands: commands
  )
  let textView = NSTextView()
  textView.string = "Updated"

  editor.makeCoordinator().textDidChange(
    Notification(name: NSText.didChangeNotification, object: textView)
  )

  #expect(state.selectedNote?.body == "Updated")
  #expect(state.selectedNote?.richTextRTF != nil)
  #expect(state.selectedNote?.revision == 1)
}

@Test @MainActor func persistenceGenerationTracksPersistedStateMutationsOnly() async {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _ in }
  )
  await state.waitUntilInitialLoad()
  let noteID = state.selectedNote!.id
  var expectedGeneration = state.persistenceGeneration

  state.updateSelected(title: state.selectedNote!.title)
  #expect(state.persistenceGeneration == expectedGeneration)

  state.updateSelected(title: "Changed")
  expectedGeneration += 1
  #expect(state.persistenceGeneration == expectedGeneration)

  state.updatePreferences { $0.fontSize = $0.fontSize }
  #expect(state.persistenceGeneration == expectedGeneration)

  state.updatePreferences { $0.fontSize += 1 }
  expectedGeneration += 1
  #expect(state.persistenceGeneration == expectedGeneration)

  state.moveToTrash(noteID)
  expectedGeneration += 2
  #expect(state.persistenceGeneration == expectedGeneration)
}

@Test @MainActor func successfulInitialLoadReplacesPersistedStateAndFinishes() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Loaded")
  let preferences = AppPreferences(fontFamily: "Avenir")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: preferences
  )
  let state = AppState(store: store)
  let generationBeforeLoad = state.persistenceGeneration

  await state.waitUntilInitialLoad()

  #expect(state.hasFinishedInitialLoad)
  #expect(state.selectedNote?.id == note.id)
  #expect(state.preferences == preferences)
  #expect(state.persistenceGeneration == generationBeforeLoad + 2)
  await state.waitUntilInitialLoad()
  #expect(state.persistenceGeneration == generationBeforeLoad + 2)
}

@Test @MainActor func failedInitialLoadStillFinishes() async throws {
  let container = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: container) }
  try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
  let blockedRoot = container.appendingPathComponent("not-a-directory")
  try Data("blocked".utf8).write(to: blockedRoot)
  let state = AppState(store: LocalStore(rootURL: blockedRoot))

  await state.waitUntilInitialLoad()

  #expect(state.hasFinishedInitialLoad)
  #expect(state.saveError != nil)
  let generation = state.persistenceGeneration
  await state.waitUntilInitialLoad()
  #expect(state.persistenceGeneration == generation)
}

@Test @MainActor func appStateUsesInjectedAgentStores() {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let profileStore = AgentProfileStore(
    profilesURL: root.appendingPathComponent("profiles.json")
  )
  let activityStore = AgentActivityStore(rootURL: root)

  let state = AppState(
    store: LocalStore(rootURL: root),
    agentProfileStore: profileStore,
    agentActivityStore: activityStore
  )

  #expect(state.agentProfileStore === profileStore)
  #expect(state.agentActivityStore === activityStore)
}

@Test func productionAgentServiceAndAppStateShareStoreInstances() throws {
  let testFile = URL(fileURLWithPath: #filePath)
  let source = testFile.deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/FleckApp/FleckApp.swift")
  let contents = try String(contentsOf: source, encoding: .utf8)

  #expect(contents.components(separatedBy: "AgentProfileStore(").count - 1 == 1)
  #expect(contents.components(separatedBy: "AgentActivityStore(rootURL: appSupport)").count - 1 == 1)
  #expect(contents.contains("AppState("))
  #expect(contents.contains("agentProfileStore: agentProfileStore"))
  #expect(contents.contains("agentActivityStore: agentActivityStore"))
  #expect(contents.contains("profileStore: agentProfileStore"))
  #expect(contents.contains("activityStore: agentActivityStore"))
}

@Test @MainActor func AppStateFolderDeleteMovesActiveSelectionToUnfiled() async throws {
  let work = try folder(named: "Work")
  let member = Note(
    title: "Member",
    body: "body",
    richTextRTF: Data("{\\rtf1 body}".utf8),
    isPinned: true,
    agentAccess: true,
    revision: 7,
    folderID: work.id
  )
  let other = Note(title: "Other", folderID: work.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [member, other],
      selectedNoteID: member.id,
      folders: [work]
    )
  )

  try state.deleteFolder(id: work.id, activeFolderID: work.id)

  #expect(state.workspace.folders.isEmpty)
  #expect(state.workspace.notes.map(\.id) == [member.id, other.id])
  #expect(state.workspace.notes.allSatisfy { $0.folderID == nil })
  #expect(state.workspace.selectedNoteID == member.id)
  #expect(state.trashedNotes.isEmpty)
}

@Test @MainActor func AppStateFolderDeleteActiveScopePreservesSelectedMemberAndSavesOnce() async throws {
  let recorder = SaveRecorder()
  let work = try folder(named: "Work")
  let member = Note(title: "Member", folderID: work.id)
  let state = await folderedState(
    workspace: Workspace(notes: [member], selectedNoteID: member.id, folders: [work]),
    recorder: recorder
  )

  try state.deleteFolder(id: work.id, activeFolderID: work.id)
  try await waitForSaveCount(recorder, 1)

  #expect(recorder.generations.count == 1)
  #expect(state.workspace.selectedNoteID == member.id)
  #expect(state.workspace.notes.first?.folderID == nil)
}

@Test @MainActor func AppStateFolderDeleteActiveScopeFallsBackToUnfiledOrRetainsDeterministicLiveSelectionAndSavesOnce() async throws {
  let recorder = SaveRecorder()
  let work = try folder(named: "Work")
  let other = try folder(named: "Other")
  let unfiled = Note(title: "Unfiled")
  let selectedElsewhere = Note(title: "Elsewhere", folderID: other.id)
  let emptyActive = try folder(named: "Empty")
  let state = await folderedState(
    workspace: Workspace(
      notes: [selectedElsewhere, unfiled],
      selectedNoteID: selectedElsewhere.id,
      folders: [work, other, emptyActive]
    ),
    recorder: recorder
  )

  try state.deleteFolder(id: emptyActive.id, activeFolderID: emptyActive.id)

  #expect(state.workspace.selectedNoteID == unfiled.id)
  #expect(!state.workspace.folders.contains(where: { $0.id == emptyActive.id }))
  try await waitForSaveCount(recorder, 1)
  #expect(recorder.generations.count == 1)

  let noUnfiledState = await folderedState(
    workspace: Workspace(
      notes: [selectedElsewhere],
      selectedNoteID: selectedElsewhere.id,
      folders: [work, other]
    ),
    recorder: recorder
  )
  try noUnfiledState.deleteFolder(id: work.id, activeFolderID: work.id)
  #expect(noUnfiledState.workspace.selectedNoteID == selectedElsewhere.id)
  #expect(noUnfiledState.workspace.notes.allSatisfy { $0.folderID != nil })
}

@Test @MainActor func AppStateFolderDeleteFinalEmptyScopeRepairsCanonicalSelection() async throws {
  let work = try folder(named: "Work")
  let state = await folderedState(
    workspace: Workspace(notes: [], selectedNoteID: nil, folders: [work])
  )

  try state.deleteFolder(id: work.id, activeFolderID: work.id)

  let selected = try #require(state.workspace.selectedNoteID)
  #expect(state.workspace.folders.isEmpty)
  #expect(state.workspace.notes.count == 1)
  #expect(state.workspace.notes[0].id == selected)
  #expect(state.workspace.notes[0].folderID == nil)
}

@Test @MainActor func AppStateFolderScopeDerivesAfterAsynchronousStoreLoad() async throws {
  let work = try folder(named: "Work")
  let loaded = Note(title: "Loaded", folderID: work.id)
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [loaded], selectedNoteID: loaded.id, folders: [work]),
    preferences: .init()
  )

  let state = AppState(store: store, saveOperation: { _, _, _, _ in .committed })
  #expect(state.folderScopeForSelectedNote() == nil)
  await state.waitUntilInitialLoad()

  #expect(state.folderScopeForSelectedNote() == work.id)
  #expect(state.persistenceGeneration > 0)
}

@Test @MainActor func AppStateFolderImportAndRestoreUseActiveScope() async throws {
  let work = try folder(named: "Work")
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let existing = Note(title: "Existing", folderID: work.id)
  let imported = Note(title: "Imported", body: "new")
  let trashed = Note(title: "Restored", folderID: work.id)
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [existing], selectedNoteID: existing.id, folders: [work]),
    preferences: .init(),
    trashedNotes: [trashed]
  )
  let state = AppState(store: store, saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()

  state.importNote(imported, intoFolderID: work.id)
  #expect(state.workspace.notes.first(where: { $0.id == imported.id })?.folderID == work.id)
  state.importNote(Note(title: "Fallback"), intoFolderID: UUID())
  #expect(state.workspace.notes.first(where: { $0.title == "Fallback" })?.folderID == nil)

  await state.refreshTrash()
  let row = try #require(state.trashedNotes.first)
  state.restore(row)
  let deadline = ContinuousClock.now + .seconds(3)
  while !state.workspace.notes.contains(where: { $0.id == trashed.id }),
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(25))
  }
  #expect(state.workspace.notes.contains(where: { $0.id == existing.id }))
  #expect(state.workspace.notes.first(where: { $0.id == trashed.id })?.folderID == work.id)
}

@Test @MainActor func AppStateFolderRestoreFallsBackToUnfiledForDeletedFolder() async throws {
  let work = try folder(named: "Work")
  let existing = Note(title: "Existing", folderID: work.id)
  let restored = Note(title: "Restored", folderID: UUID())
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [existing], selectedNoteID: existing.id, folders: [work]),
    preferences: .init(),
    trashedNotes: [restored]
  )
  let state = AppState(store: store, saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  await state.refreshTrash()

  let row = try #require(state.trashedNotes.first)
  state.restore(row)
  let deadline = ContinuousClock.now + .seconds(3)
  while !state.workspace.notes.contains(where: { $0.id == restored.id }),
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(25))
  }

  #expect(state.workspace.notes.count == 2)
  #expect(state.workspace.notes.first(where: { $0.id == existing.id })?.folderID == work.id)
  #expect(state.workspace.notes.first(where: { $0.id == restored.id })?.folderID == nil)
}

@Test @MainActor func AppStateFolderNewMoveAndInvalidTargetsUseExplicitContracts() async throws {
  let first = try folder(named: "First")
  let second = try folder(named: "Second")
  let note = Note(
    title: "Formatted",
    body: "body",
    richTextRTF: Data([1, 2, 3]),
    tabColorHex: "#123456",
    createdAt: Date(timeIntervalSince1970: 10),
    modifiedAt: Date(timeIntervalSince1970: 20),
    isPinned: true,
    agentAccess: true,
    revision: 9,
    folderID: first.id
  )
  let state = await folderedState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [first, second])
  )

  let newID = state.addNote(inFolderID: second.id)
  #expect(state.workspace.notes.first(where: { $0.id == newID })?.folderID == second.id)
  let fallbackID = state.addNote(inFolderID: UUID())
  #expect(state.workspace.notes.first(where: { $0.id == fallbackID })?.folderID == nil)

  #expect(state.moveNote(note.id, toFolderID: second.id, activeFolderID: first.id))
  let moved = try #require(state.workspace.notes.first(where: { $0.id == note.id }))
  #expect(moved.folderID == second.id)
  #expect(moved.body == note.body)
  #expect(moved.richTextRTF == note.richTextRTF)
  #expect(moved.modifiedAt == note.modifiedAt)
  #expect(moved.revision == note.revision)
  #expect(!state.moveNote(note.id, toFolderID: UUID(), activeFolderID: second.id))
  #expect(state.workspace.notes.first(where: { $0.id == note.id })?.folderID == second.id)
}

@Test @MainActor func AppStateFolderImportCollisionAllocatesANewNoteID() async throws {
  let work = try folder(named: "Work")
  let existing = Note(title: "Existing", body: "old")
  let state = await folderedState(
    workspace: Workspace(notes: [existing], selectedNoteID: existing.id, folders: [work])
  )
  let imported = Note(
    id: existing.id,
    title: "Existing",
    body: "imported",
    folderID: work.id
  )

  state.importNote(imported, intoFolderID: work.id)

  #expect(state.workspace.notes.count == 2)
  #expect(state.workspace.notes.contains(where: { $0.id == existing.id && $0.body == "old" }))
  #expect(state.workspace.notes.contains(where: { $0.id != existing.id && $0.body == "imported" }))
}

@Test @MainActor func AppStateFolderCreateRenameReorderMoveAndDeleteEachSaveOnce() async throws {
  let recorder = SaveRecorder()
  let first = try folder(named: "First")
  let second = try folder(named: "Second")
  let note = Note(title: "Move me", folderID: first.id)
  let state = await folderedState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [first, second]),
    recorder: recorder
  )

  let created = try state.createFolder(named: "Third")
  try await waitForSaveCount(recorder, 1)
  try state.renameFolder(id: created.id, name: "Renamed")
  try await waitForSaveCount(recorder, 2)
  try state.reorderFolder(id: created.id, to: 0)
  try await waitForSaveCount(recorder, 3)
  #expect(state.moveNote(note.id, toFolderID: second.id, activeFolderID: first.id))
  try await waitForSaveCount(recorder, 4)
  try state.deleteFolder(id: created.id, activeFolderID: nil)
  try await waitForSaveCount(recorder, 5)

  #expect(recorder.generations.count == 5)
  #expect(!state.workspace.folders.contains(where: { $0.id == created.id }))
}

@Test @MainActor func AppStateFolderScopeNavigationStaysWithinVisibleNotes() async throws {
  let work = try folder(named: "Work")
  let other = try folder(named: "Other")
  let first = Note(title: "First", folderID: work.id)
  let second = Note(title: "Second", folderID: work.id)
  let hidden = Note(title: "Hidden", folderID: other.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [first, second, hidden],
      selectedNoteID: first.id,
      folders: [work, other]
    )
  )

  state.selectAdjacentNote(forward: true, inFolderID: work.id)
  #expect(state.workspace.selectedNoteID == second.id)
  state.selectAdjacentNote(forward: true, inFolderID: work.id)
  #expect(state.workspace.selectedNoteID == first.id)
  state.selectAdjacentNote(forward: false, inFolderID: work.id)
  #expect(state.workspace.selectedNoteID == second.id)
  #expect(state.workspace.notes(inFolderID: work.id).map(\.id) == [first.id, second.id])
}

@Test @MainActor func AppStateFolderSmartCaptureKeepsTitleFallbackAndDoesNotCreateFolder() async throws {
  let inbox = Note(title: "Inbox", body: "existing")
  let work = try folder(named: "Work")
  let state = await folderedState(
    workspace: Workspace(notes: [inbox], selectedNoteID: inbox.id, folders: [work])
  )
  let captureID = UUID()

  _ = try await state.saveSmartCapture(
    text: " captured",
    captureID: captureID,
    destinationID: nil
  )

  #expect(state.workspace.folders == [work])
  #expect(state.workspace.notes.count == 1)
  #expect(state.workspace.notes[0].body.contains("captured"))
  #expect(state.workspace.notes[0].folderID == nil)
}

@Test @MainActor func NotesPanelFolderNavigatorPreservesRealEditorLifetime() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let work = try folder(named: "Work")
  let title = "Focus title"
  let text = "Keep editor rich text"
  let selectedRange = NSRange(location: 5, length: 6)
  let boldFont = try #require(NSFont(name: "Helvetica-Bold", size: 18))
  let rtfDocumentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
    .documentType: NSAttributedString.DocumentType.rtf
  ]
  let attributed = NSMutableAttributedString(string: text)
  attributed.addAttributes(
    [.font: boldFont, .foregroundColor: NSColor.systemRed],
    range: NSRange(location: 0, length: text.utf16.count)
  )
  let rtf = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: rtfDocumentAttributes
  )
  let note = Note(title: title, body: text, richTextRTF: rtf, folderID: nil)
  let state = await folderedState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [work])
  )
  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
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
  await settleHostedFolderView(host)
  let editor = try #require(hostedFolderEditor(in: host))
  let titleField = try #require(hostedFolderTextField(with: title, in: host))

  editor.setSelectedRange(selectedRange)
  editor.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.refreshFormattingState()
  commands.applyBackgroundColor(.systemYellow)
  let expectedText = editor.string
  let expectedSelection = editor.selectedRange()
  let expectedTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let expectedRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: expectedText.utf16.count),
    documentAttributes: rtfDocumentAttributes
  )
  let undoManager = try #require(editor.undoManager)
  let expectedUndoAvailability = undoManager.canUndo

  #expect(expectedSelection == selectedRange)
  #expect(expectedUndoAvailability)
  #expect(commands.textView === editor)
  #expect(commands.isBold)
  #expect(window.makeFirstResponder(editor))
  #expect(window.firstResponder === editor)
  #expect(titleField.stringValue == title)

  var scoped = state.workspace
  scoped.notes[0].folderID = work.id
  state.workspace = scoped
  await settleHostedFolderView(host)
  #expect(!state.workspace.notes(inFolderID: nil).contains(where: { $0.id == note.id }))

  scoped.notes[0].folderID = nil
  state.workspace = scoped
  await settleHostedFolderView(host)

  #expect(hostedFolderEditor(in: host) === editor)
  #expect(commands.textView === editor)
  #expect(editor.string == expectedText)
  #expect(editor.selectedRange() == expectedSelection)
  #expect(
    NSDictionary(dictionary: editor.typingAttributes)
      .isEqual(to: expectedTypingAttributes)
  )
  let actualRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: expectedText.utf16.count),
    documentAttributes: rtfDocumentAttributes
  )
  #expect(actualRTF == expectedRTF)
  #expect(editor.undoManager === undoManager)
  #expect(editor.undoManager?.canUndo == expectedUndoAvailability)
  #expect(commands.isBold)
  #expect(window.firstResponder === editor)
  #expect(titleField.stringValue == title)
}

@MainActor
private func hostedFolderEditor(in view: NSView) -> ListAwareTextView? {
  if let editor = view as? ListAwareTextView { return editor }
  for subview in view.subviews {
    if let editor = hostedFolderEditor(in: subview) { return editor }
  }
  return nil
}

@MainActor
private func hostedFolderTextField(with value: String, in view: NSView) -> NSTextField? {
  if let field = view as? NSTextField, field.stringValue == value {
    return field
  }
  for subview in view.subviews {
    if let field = hostedFolderTextField(with: value, in: subview) { return field }
  }
  return nil
}

@MainActor
private func settleHostedFolderView(_ view: NSView) async {
  for _ in 0..<5 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@Test @MainActor func AppStateFolderDropPayloadRejectionsAreNoOpsAndDoNotSave() async throws {
  let recorder = SaveRecorder()
  let source = try folder(named: "Source")
  let target = try folder(named: "Target")
  let note = Note(title: "Move me", folderID: source.id)
  let state = await folderedState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [source, target]),
    recorder: recorder
  )
  let before = state.workspace

  #expect(
    !state.moveNote(
      note.id,
      fromFolderID: UUID(),
      toFolderID: target.id,
      activeFolderID: source.id
    )
  )
  #expect(state.workspace == before)
  #expect(FolderDragPayload.noteValue(from: Data("not-json".utf8)) == nil)
  #expect(FolderDragPayload.noteValue(from: Data("{\"unknown\":true}".utf8)) == nil)
  #expect(FolderDragPayload.folderID(from: Data("{\"unknown\":true}".utf8)) == nil)
  #expect(state.workspace == before)

  try await Task.sleep(for: .milliseconds(150))
  #expect(recorder.generations.isEmpty)
}
