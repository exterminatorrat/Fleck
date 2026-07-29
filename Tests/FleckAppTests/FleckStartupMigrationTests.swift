import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func startupMigrationCompletesBeforeAnyStoreOrSocketUsesFleckRoot() async throws {
  let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckStartupMigrationTests-\(UUID())",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = parent.appendingPathComponent(
    FleckProductPaths.legacyDirectoryName,
    isDirectory: true
  )
  let note = Note(title: "Legacy note", body: "Migrated before load")
  _ = try LocalStoreSnapshotWriter(rootURL: legacy).save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 1
  )

  let startup = FleckStartupContext(
    outcome: FleckProductMigration(
      applicationSupportParent: parent
    ).prepare()
  )
  let state = AppState(
    store: LocalStore(rootURL: startup.applicationSupportURL),
    agentProfileStore: AgentProfileStore(
      profilesURL: startup.applicationSupportURL
        .appendingPathComponent("AgentIntegrations", isDirectory: true)
        .appendingPathComponent("profiles.json")
    ),
    agentActivityStore: AgentActivityStore(
      rootURL: startup.applicationSupportURL
    ),
    startupMigrationError: startup.migrationError
  )

  await state.waitUntilInitialLoad()

  #expect(
    startup.applicationSupportURL.lastPathComponent
      == FleckProductPaths.canonicalDirectoryName
  )
  #expect(state.selectedNote?.id == note.id)
  #expect(state.isAgentWorkspaceAvailable)
  #expect(!state.isPersistenceBlocked)
}

@Test @MainActor
func migrationConflictFinishesInitialLoadButKeepsAgentWorkspaceUnavailable()
  async
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckStartupMigrationTests-\(UUID())",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let error = FleckProductMigrationError.conflictingWorkspaces(
    legacyPath: "/legacy",
    canonicalPath: "/canonical"
  )
  let state = AppState(
    store: LocalStore(rootURL: root),
    startupMigrationError: error
  )

  await state.waitUntilInitialLoad()

  #expect(state.hasFinishedInitialLoad)
  #expect(!state.isAgentWorkspaceAvailable)
  #expect(state.isPersistenceBlocked)
  #expect(state.startupMigrationError == error)
}

@Test @MainActor
func migrationConflictBlocksEditorPersistenceAndPreservesBothRoots()
  async throws
{
  let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckStartupMigrationTests-\(UUID())",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = parent.appendingPathComponent("MenuBarNotes", isDirectory: true)
  let canonical = parent.appendingPathComponent("Fleck", isDirectory: true)
  try FileManager.default.createDirectory(
    at: legacy,
    withIntermediateDirectories: true
  )
  try FileManager.default.createDirectory(
    at: canonical,
    withIntermediateDirectories: true
  )
  let legacyMarker = legacy.appendingPathComponent("workspace.json")
  let canonicalMarker = canonical.appendingPathComponent("workspace.json")
  try Data("legacy".utf8).write(to: legacyMarker)
  try Data("canonical".utf8).write(to: canonicalMarker)
  let error = FleckProductMigrationError.conflictingWorkspaces(
    legacyPath: legacy.path,
    canonicalPath: canonical.path
  )
  let state = AppState(
    store: LocalStore(rootURL: canonical),
    startupMigrationError: error
  )
  await state.waitUntilInitialLoad()

  state.updateSelected(title: "Must not save")
  try await Task.sleep(for: .milliseconds(500))

  #expect(try Data(contentsOf: legacyMarker) == Data("legacy".utf8))
  #expect(try Data(contentsOf: canonicalMarker) == Data("canonical".utf8))
  #expect(state.saveStatus == .idle)
}

