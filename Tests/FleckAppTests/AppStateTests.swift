import AppKit
import Foundation
import FleckCore
import Testing

@testable import FleckApp

private enum AppStateTestError: Error {
  case failed
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
  let state = AppState(
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
