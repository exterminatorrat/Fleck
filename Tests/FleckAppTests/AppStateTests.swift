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

@Test @MainActor func selectedTitleFontFamilySchedulesOneNoteSaveWithoutChangingPreferences() async throws {
  let first = Note(title: "Selected")
  let second = Note(title: "Other", titleFontFamily: "Avenir")
  let recorder = SaveRecorder()
  let state = await folderedState(
    workspace: Workspace(notes: [first, second], selectedNoteID: first.id),
    recorder: recorder
  )
  let originalPreferences = state.preferences

  state.setSelectedTitleFontFamily("Menlo")

  #expect(state.selectedNote?.titleFontFamily == "Menlo")
  #expect(state.workspace.notes[1].titleFontFamily == "Avenir")
  #expect(state.preferences == originalPreferences)
  #expect(state.saveStatus == .saving)
  try await waitForSaveCount(recorder, 1)
  #expect(recorder.generations.count == 1)

  state.setSelectedTitleFontFamily("Menlo")
  try await Task.sleep(for: .milliseconds(450))
  #expect(recorder.generations.count == 1)
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
  #expect(contents.components(separatedBy: "AgentCapabilityStore(").count - 1 == 1)
  #expect(
    contents.components(
      separatedBy: "AgentCapabilityAuthority(store: agentCapabilityStore)"
    ).count - 1 == 1
  )
  #expect(contents.contains("agentCapabilityStore: agentCapabilityStore"))
  #expect(contents.contains("agentCapabilityAuthority: agentCapabilityAuthority"))
  #expect(contents.contains("capabilityAuthority: agentCapabilityAuthority"))
}

@Test @MainActor
func capabilityMigrationRunsAfterWorkspaceAndActiveProfilesLoad() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppStateCapabilityTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Migrated", body: "Body", agentAccess: true)
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Codex",
    createdAt: Date(timeIntervalSince1970: 100),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let profilesURL = root
    .appendingPathComponent("AgentIntegrations", isDirectory: true)
    .appendingPathComponent("profiles.json")
  try FileManager.default.createDirectory(
    at: profilesURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try JSONEncoder().encode([profile]).write(to: profilesURL)
  let state = AppState(
    store: store,
    agentProfileStore: AgentProfileStore(profilesURL: profilesURL),
    agentCapabilityStore: appStateCapabilityStore(root: root)
  )

  await state.waitUntilInitialLoad()

  let capabilities = try #require(state.capabilityProfile(profile.id))
  #expect(
    capabilities.grants.contains {
      $0.scope == .note(noteID: note.id) && $0.authority == .write
    }
  )
  #expect(state.selectedNote?.body == "Body")
  #expect(state.hasFinishedInitialLoad)
  #expect(state.isAgentWorkspaceAvailable)
}

@Test @MainActor
func malformedCapabilityGenerationsKeepNotesUsableAndAgentWorkspaceUnavailable()
  async throws
{
  for previous in [false, true] {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppStateMalformedCapabilityTests-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: "Still usable", body: "Keep this")
    let localStore = LocalStore(rootURL: root)
    try await localStore.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init()
    )
    let malformedURL = previous
      ? root.appendingPathComponent("AgentIntegrations/capabilities.previous.json")
      : root.appendingPathComponent("AgentIntegrations/capabilities.json")
    try FileManager.default.createDirectory(
      at: malformedURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not-json".utf8).write(to: malformedURL)
    let state = AppState(
      store: localStore,
      agentProfileStore: appStateProfileStore(root: root),
      agentCapabilityStore: appStateCapabilityStore(root: root)
    )

    await state.waitUntilInitialLoad()

    #expect(state.hasFinishedInitialLoad)
    #expect(state.selectedNote?.body == "Keep this")
    #expect(!state.isAgentWorkspaceAvailable)
    #expect(state.saveError == nil)
    #expect(
      state.agentCleanupError
        == "Agent workspace is unavailable. Reopen Fleck after resolving capability storage."
    )
    #expect(!(state.agentCleanupError ?? "").contains("not-json"))
    #expect(!(state.agentCleanupError ?? "").contains(root.path))
  }
}

@Test @MainActor
func appStateKeepsUnassignedLegacySharesUnassigned() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppStateUnassignedCapabilityTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Legacy share", agentAccess: true)
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let state = AppState(
    store: store,
    agentProfileStore: appStateProfileStore(root: root),
    agentCapabilityStore: appStateCapabilityStore(root: root)
  )

  await state.waitUntilInitialLoad()

  #expect(state.agentCapabilityState.unassignedLegacyNoteIDs == [note.id])
  #expect(state.agentCapabilityState.profiles.isEmpty)
  #expect(state.profilesWithReadAccess(to: note.id).isEmpty)
  #expect(!state.isSharedWithAnyActiveProfile(note.id))
}

@Test @MainActor
func appStateDefaultsAgentStoresToInjectedStoreRoot() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppStateCoherentAgentStorageTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let agentDirectory = root.appendingPathComponent("AgentIntegrations", isDirectory: true)
  try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Isolated profile",
    createdAt: Date(timeIntervalSince1970: 100),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  try JSONEncoder().encode([profile]).write(
    to: agentDirectory.appendingPathComponent("profiles.json")
  )

  let canonicalRoot = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
  )[0].appendingPathComponent(FleckProductPaths.canonicalDirectoryName, isDirectory: true)
  let canonicalProfilesURL = canonicalRoot
    .appendingPathComponent("AgentIntegrations", isDirectory: true)
    .appendingPathComponent("profiles.json")
  let canonicalCapabilitiesURL = canonicalRoot
    .appendingPathComponent("AgentIntegrations", isDirectory: true)
    .appendingPathComponent("capabilities.json")
  let canonicalProfilesBefore = try? Data(contentsOf: canonicalProfilesURL)
  let canonicalCapabilitiesBefore = try? Data(contentsOf: canonicalCapabilitiesURL)

  let store = LocalStore(rootURL: root)
  #expect(store.rootURL == root)
  let state = AppState(store: store)
  await state.waitUntilInitialLoad()

  #expect(state.hasFinishedInitialLoad)
  #expect(state.agentProfiles == [profile])
  #expect(state.agentCapabilityState.profiles[profile.id]?.profileID == profile.id)
  #expect(
    FileManager.default.fileExists(
      atPath: agentDirectory.appendingPathComponent("capabilities.json").path
    )
  )
  #expect(
    FileManager.default.fileExists(
      atPath: root.appendingPathComponent("AgentActivity/Records", isDirectory: true).path
    )
  )
  let canonicalProfilesAfter = try? Data(contentsOf: canonicalProfilesURL)
  let canonicalCapabilitiesAfter = try? Data(contentsOf: canonicalCapabilitiesURL)
  #expect(canonicalProfilesAfter == canonicalProfilesBefore)
  #expect(canonicalCapabilitiesAfter == canonicalCapabilitiesBefore)
}

@Test @MainActor
func bothMalformedCapabilityGenerationsKeepNotesUsableAndAgentWorkspaceUnavailable()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppStateDualMalformedCapabilityTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Still usable", body: "Keep this")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let agentDirectory = root.appendingPathComponent("AgentIntegrations", isDirectory: true)
  try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
  try Data("current-not-json".utf8).write(
    to: agentDirectory.appendingPathComponent("capabilities.json")
  )
  try Data("previous-not-json".utf8).write(
    to: agentDirectory.appendingPathComponent("capabilities.previous.json")
  )

  let state = AppState(store: store)
  await state.waitUntilInitialLoad()

  #expect(state.selectedNote?.body == "Keep this")
  #expect(state.hasFinishedInitialLoad)
  #expect(!state.isAgentWorkspaceAvailable)
  #expect(state.saveError == nil)
  #expect(
    state.agentCleanupError
      == "Agent workspace is unavailable. Reopen Fleck after resolving capability storage."
  )
  #expect(!(state.agentCleanupError ?? "").contains("not-json"))
  #expect(!(state.agentCleanupError ?? "").contains(root.path))
}

private func appStateCapabilityStore(root: URL) -> AgentCapabilityStore {
  let directory = root.appendingPathComponent("AgentIntegrations", isDirectory: true)
  return AgentCapabilityStore(
    capabilitiesURL: directory.appendingPathComponent("capabilities.json"),
    previousCapabilitiesURL: directory.appendingPathComponent(
      "capabilities.previous.json"
    )
  )
}

private func appStateProfileStore(root: URL) -> AgentProfileStore {
  AgentProfileStore(
    profilesURL: root
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("profiles.json")
  )
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

  let hiddenText = editor.string
  let hiddenSelection = editor.selectedRange()
  let hiddenTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let hiddenRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: hiddenText.utf16.count),
    documentAttributes: rtfDocumentAttributes
  )
  let hiddenUndoAvailability = editor.undoManager?.canUndo

  var scoped = state.workspace
  scoped.notes[0].folderID = work.id
  state.workspace = scoped
  await settleHostedFolderView(host)
  #expect(!state.workspace.notes(inFolderID: nil).contains(where: { $0.id == note.id }))
  #expect(window.firstResponder !== editor)

  let hiddenKeyEvent = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "x",
      charactersIgnoringModifiers: "x",
      isARepeat: false,
      keyCode: 7
    )
  )
  window.sendEvent(hiddenKeyEvent)
  await settleHostedFolderView(host)
  #expect(editor.string == hiddenText)
  #expect(editor.selectedRange() == hiddenSelection)
  #expect(
    NSDictionary(dictionary: editor.typingAttributes)
      .isEqual(to: hiddenTypingAttributes)
  )
  let hiddenActualRTF = try editor.textStorage?.data(
    from: NSRange(location: 0, length: hiddenText.utf16.count),
    documentAttributes: rtfDocumentAttributes
  )
  #expect(hiddenActualRTF == hiddenRTF)
  #expect(editor.undoManager?.canUndo == hiddenUndoAvailability)
  #expect(state.selectedNote?.body == hiddenText)

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

  try await Task.sleep(for: .milliseconds(500))
  #expect(recorder.generations.isEmpty)
}

@Test @MainActor func folderMovesUseOneSaveAndRejectStaleOrSameFolderRequests() async throws {
  let recorder = SaveRecorder()
  let source = try folder(named: "Source")
  let target = try folder(named: "Target")
  let unfiled = Note(title: "Unfiled", folderID: nil)
  let filed = Note(title: "Filed", folderID: source.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [unfiled, filed],
      selectedNoteID: filed.id,
      folders: [source, target]
    ),
    recorder: recorder
  )

  #expect(state.moveNote(unfiled.id, fromFolderID: nil, toFolderID: source.id, activeFolderID: nil))
  try await waitForSaveCount(recorder, 1)
  #expect(state.workspace.notes.first(where: { $0.id == unfiled.id })?.folderID == source.id)

  #expect(state.moveNote(filed.id, fromFolderID: source.id, toFolderID: target.id, activeFolderID: source.id))
  try await waitForSaveCount(recorder, 2)
  #expect(state.workspace.notes.first(where: { $0.id == filed.id })?.folderID == target.id)
  #expect(state.workspace.selectedNoteID == unfiled.id)

  #expect(state.moveNote(filed.id, fromFolderID: target.id, toFolderID: nil, activeFolderID: target.id))
  try await waitForSaveCount(recorder, 3)
  #expect(state.workspace.notes.first(where: { $0.id == filed.id })?.folderID == nil)

  #expect(!state.moveNote(filed.id, fromFolderID: source.id, toFolderID: target.id, activeFolderID: nil))
  #expect(!state.moveNote(filed.id, fromFolderID: nil, toFolderID: nil, activeFolderID: nil))
  try await Task.sleep(for: .milliseconds(500))
  #expect(recorder.generations.count == 3)
}

@Test @MainActor func manualFolderReorderSavesOnceAndRejectsInvalidOrSamePositionRequests() async throws {
  let recorder = SaveRecorder()
  let manualFolder = try folder(named: "Manual")
  let otherFolder = try folder(named: "Other")
  let pinned = Note(title: "Pinned", isPinned: true, folderID: manualFolder.id)
  let first = Note(title: "First", folderID: manualFolder.id)
  let second = Note(title: "Second", folderID: manualFolder.id)
  let third = Note(title: "Third", folderID: manualFolder.id)
  let hidden = Note(title: "Hidden", folderID: otherFolder.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [pinned, first, second, third, hidden],
      selectedNoteID: first.id,
      folders: [manualFolder, otherFolder]
    ),
    recorder: recorder
  )

  #expect(state.moveNote(first.id, inFolderID: manualFolder.id, toVisibleIndex: 2))
  try await waitForSaveCount(recorder, 1)
  #expect(state.workspace.notes(inFolderID: manualFolder.id).map(\.id) == [pinned.id, second.id, third.id, first.id])
  #expect(state.workspace.notes.map(\.id) == [pinned.id, second.id, third.id, first.id, hidden.id])

  #expect(!state.moveNote(first.id, inFolderID: manualFolder.id, toVisibleIndex: 2))
  #expect(!state.moveNote(first.id, inFolderID: manualFolder.id, toVisibleIndex: 99))
  #expect(!state.moveNote(first.id, inFolderID: otherFolder.id, toVisibleIndex: 0))

  state.updateSelected(title: "First edited")
  #expect(state.workspace.notes(inFolderID: manualFolder.id).map(\.id) == [pinned.id, second.id, third.id, first.id])
  try await waitForSaveCount(recorder, 2)
  #expect(recorder.generations.count == 2)
}

@Test @MainActor func AppStateFolderAwareTrashDeletionSelectsNearestVisibleMemberAndSavesOnce() async throws {
  let recorder = SaveRecorder()
  let work = try folder(named: "Work")
  let other = try folder(named: "Other")
  let first = Note(title: "Work A", folderID: work.id)
  let hidden = Note(title: "Other X", folderID: other.id)
  let next = Note(title: "Work B", folderID: work.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [first, hidden, next],
      selectedNoteID: first.id,
      folders: [work, other]
    ),
    recorder: recorder
  )

  state.moveToTrash(first.id, activeFolderID: work.id)

  #expect(state.workspace.selectedNoteID == next.id)
  #expect(state.workspace.notes(inFolderID: work.id).map(\.id) == [next.id])
  #expect(state.workspace.notes(inFolderID: other.id).map(\.id) == [hidden.id])
  #expect(!state.workspace.notes.contains(where: { $0.id == first.id }))
  try await waitForSaveCount(recorder, 1)
  try await Task.sleep(for: .milliseconds(100))
  #expect(recorder.generations.count == 1)
}

@Test @MainActor func AppStateFolderAwareTrashDeletionKeepsValidGlobalSelectionWhenScopeEmpties() async throws {
  let recorder = SaveRecorder()
  let work = try folder(named: "Work")
  let other = try folder(named: "Other")
  let deleted = Note(title: "Work A", folderID: work.id)
  let hidden = Note(title: "Other X", folderID: other.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [deleted, hidden],
      selectedNoteID: deleted.id,
      folders: [work, other]
    ),
    recorder: recorder
  )

  state.moveToTrash(deleted.id, activeFolderID: work.id)

  #expect(state.workspace.notes(inFolderID: work.id).isEmpty)
  #expect(state.workspace.selectedNoteID == hidden.id)
  #expect(state.workspace.notes.count == 1)
  try await waitForSaveCount(recorder, 1)
  try await Task.sleep(for: .milliseconds(100))
  #expect(recorder.generations.count == 1)
}

@Test @MainActor func AppStateFolderLegacyTrashRemainsGlobalWhileExplicitUnfiledUsesNearestVisible() async throws {
  let work = try folder(named: "Work")
  let unfiledFirst = Note(title: "Unfiled A")
  let hidden = Note(title: "Work X", folderID: work.id)
  let unfiledNext = Note(title: "Unfiled B")
  let workspace = Workspace(
    notes: [unfiledFirst, hidden, unfiledNext],
    selectedNoteID: unfiledFirst.id,
    folders: [work]
  )
  let globalState = await folderedState(workspace: workspace)

  globalState.moveToTrash(unfiledFirst.id)

  #expect(globalState.workspace.selectedNoteID == hidden.id)

  let explicitState = await folderedState(workspace: workspace)
  explicitState.moveToTrash(unfiledFirst.id, activeFolderID: nil)

  #expect(explicitState.workspace.selectedNoteID == unfiledNext.id)
}

@Test @MainActor func AppStateFolderNoteScopeActivationResolvesExistingOrUnfiledFolder() async throws {
  let work = try folder(named: "Work")
  let inWork = Note(title: "Work note", folderID: work.id)
  let unfiled = Note(title: "Unfiled note")
  let stale = Note(title: "Stale note", folderID: UUID())
  let state = await folderedState(
    workspace: Workspace(
      notes: [inWork, unfiled, stale],
      selectedNoteID: inWork.id,
      folders: [work]
    )
  )

  #expect(state.folderID(for: inWork.id) == work.id)
  #expect(state.folderID(for: unfiled.id) == nil)
  #expect(state.folderID(for: stale.id) == nil)
  #expect(state.folderID(for: UUID()) == nil)
}

@Test @MainActor func AppStateFolderRestoreChangesSelectionWithoutExtraSaveAndResolvesScope() async throws {
  let work = try folder(named: "Work")
  let existing = Note(title: "Existing", folderID: work.id)
  let restored = Note(title: "Restored", body: "body", folderID: work.id)
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [existing], selectedNoteID: existing.id, folders: [work]),
    preferences: .init(),
    trashedNotes: [restored]
  )
  let recorder = SaveRecorder()
  let state = AppState(
    store: store,
    saveOperation: { _, _, _, generation in
      recorder.record(generation: generation)
      return .committed
    }
  )
  await state.waitUntilInitialLoad()
  await state.refreshTrash()
  let row = try #require(state.trashedNotes.first)

  state.restore(row)

  #expect(state.workspace.selectedNoteID == restored.id)
  #expect(state.folderID(for: restored.id) == work.id)
  #expect(recorder.generations.isEmpty)
  let deadline = ContinuousClock.now + .seconds(3)
  while !state.workspace.notes.contains(where: { $0.id == restored.id }),
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(25))
  }
  #expect(state.workspace.notes.contains(where: { $0.id == existing.id }))
  #expect(state.workspace.notes.contains(where: { $0.id == restored.id }))
  #expect(recorder.generations.isEmpty)
}

@Test @MainActor func NotesPanelFolderNavigatorBoundsFoldersAtCompactAndRegularHeights() async throws {
  for height in [CGFloat(300), CGFloat(430)] {
    let metrics = try await hostedFolderPanelMetrics(height: height)
    // At the supported 300-point compact height, 48 points is the smallest
    // hosted clip viewport that still leaves the real editor usable.
    #expect(metrics.editorViewportHeight >= 48)
    #expect(metrics.folderNavigatorScrollHeight > 0)
  }
}

@MainActor
private func hostedFolderPanelMetrics(
  height: CGFloat
) async throws -> (
  editorDocumentHeight: CGFloat,
  folderNavigatorScrollHeight: CGFloat,
  hostedPanelHeight: CGFloat,
  editorScrollViewHeight: CGFloat,
  editorViewportHeight: CGFloat
) {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let folders = try (0..<24).map { index in
    try folder(named: "Folder \(index)")
  }
  let note = Note(title: "Editor", body: "Usable editor", folderID: nil)
  let state = await folderedState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: folders)
  )
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: height),
    styleMask: [.borderless], backing: .buffered, defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleHostedFolderView(host)
  let editor = try #require(hostedFolderEditor(in: host))
  let scrollView = try #require(editor.enclosingScrollView)
  let folderScrollView = try #require(
    hostedFolderScrollViews(in: host).first(where: { $0 !== scrollView })
  )
  return (
    editor.frame.height,
    folderScrollView.frame.height,
    host.bounds.height,
    scrollView.frame.height,
    scrollView.contentView.bounds.height
  )
}

@MainActor
private func hostedFolderScrollViews(in view: NSView) -> [NSScrollView] {
  var result: [NSScrollView] = []
  if let scrollView = view as? NSScrollView {
    result.append(scrollView)
  }
  for subview in view.subviews {
    result.append(contentsOf: hostedFolderScrollViews(in: subview))
  }
  return result
}
