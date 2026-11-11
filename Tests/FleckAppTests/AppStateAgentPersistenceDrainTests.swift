import CryptoKit
import Foundation
import FleckCore
import Testing

@testable import FleckApp

private enum AgentPersistenceDrainTestError: Error {
  case injectedSaveFailure
}

private struct AgentPersistenceDrainSaveRecord: Equatable {
  let generation: UInt64
  let result: LocalStoreSnapshotWriteResult
}

private actor OneShotPersistencePause {
  private var isArmed = false
  private var isPaused = false
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var continuation: CheckedContinuation<Void, Never>?

  func arm() {
    isArmed = true
    isPaused = false
    continuation = nil
  }

  func pauseIfArmed() async {
    guard isArmed else { return }
    isArmed = false
    isPaused = true
    startedContinuation?.resume()
    startedContinuation = nil
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilPaused() async {
    guard !isPaused else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class AgentPersistenceDrainSaveRecorder: @unchecked Sendable {
  private let store: LocalStore
  private let lock = NSLock()
  private var storeSaveCount = 0
  private var failuresRemaining = 0
  private var recordedSaves: [AgentPersistenceDrainSaveRecord] = []
  let afterCommitPause = OneShotPersistencePause()

  init(store: LocalStore) {
    self.store = store
  }

  var realStoreSaveCount: Int {
    lock.withLock { storeSaveCount }
  }

  var records: [AgentPersistenceDrainSaveRecord] {
    lock.withLock { recordedSaves }
  }

  func failNextSave() {
    lock.withLock { failuresRemaining += 1 }
  }

  func waitUntilAfterCommitPauses() async {
    await afterCommitPause.waitUntilPaused()
  }

  func releaseAfterCommit() async {
    await afterCommitPause.release()
  }

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note],
    generation: UInt64
  ) async throws -> LocalStoreSnapshotWriteResult {
    let shouldFail = lock.withLock {
      guard failuresRemaining > 0 else { return false }
      failuresRemaining -= 1
      return true
    }
    if shouldFail {
      throw AgentPersistenceDrainTestError.injectedSaveFailure
    }

    lock.withLock { storeSaveCount += 1 }
    let result = try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: trashedNotes,
      generation: generation
    )
    lock.withLock {
      recordedSaves.append(
        AgentPersistenceDrainSaveRecord(generation: generation, result: result)
      )
    }
    if result == .committed {
      await afterCommitPause.pauseIfArmed()
    }
    return result
  }
}

@MainActor
private struct AgentPersistenceDrainFixture {
  let root: URL
  let store: LocalStore
  let recorder: AgentPersistenceDrainSaveRecorder
  let beforeSavePause: OneShotPersistencePause
  let state: AppState
}

@MainActor
private func makeAgentPersistenceDrainFixture() async -> AgentPersistenceDrainFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AppStateAgentPersistenceDrainTests-\(UUID().uuidString)",
    isDirectory: true
  )
  let store = LocalStore(rootURL: root)
  let recorder = AgentPersistenceDrainSaveRecorder(store: store)
  let beforeSavePause = OneShotPersistencePause()
  let state = AppState(
    store: store,
    saveOperation: { workspace, preferences, trashedNotes, generation in
      try await recorder.save(
        workspace: workspace,
        preferences: preferences,
        trashedNotes: trashedNotes,
        generation: generation
      )
    },
    beforeSaveOperation: {
      await beforeSavePause.pauseIfArmed()
    }
  )
  await state.waitUntilInitialLoad()
  return AgentPersistenceDrainFixture(
    root: root,
    store: store,
    recorder: recorder,
    beforeSavePause: beforeSavePause,
    state: state
  )
}

@Test @MainActor func agentWriteDrainSkipsOnlyKnownCleanCommittedGeneration() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 1)
  #expect(fixture.recorder.records.map(\.result) == [.committed])

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 1)

  try await fixture.state.flushPendingPersistenceForAgent()
  #expect(fixture.recorder.realStoreSaveCount == 2)
  try await fixture.state.flushPendingPersistenceForAgent()
  #expect(fixture.recorder.realStoreSaveCount == 3)

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 3)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func knownDurableWriteDrainSettlesSameIDSelectionSaveStatus() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  let selectedNoteID = try #require(fixture.state.workspace.selectedNoteID)
  let generation = fixture.state.persistenceGeneration
  let saveCount = fixture.recorder.realStoreSaveCount

  fixture.state.select(selectedNoteID)
  #expect(fixture.state.workspace.selectedNoteID == selectedNoteID)
  #expect(fixture.state.persistenceGeneration == generation)
  #expect(fixture.state.saveStatus == .saving)

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == saveCount)
  #expect(fixture.state.saveStatus == .saved)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func bodyAndPreferenceMutationsRequireFreshWriteDrainSaves() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()

  fixture.state.updateSelected(body: "Changed note body")
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 2)

  fixture.state.updatePreferences { $0.panelWidth += 1 }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 3)

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 3)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func pendingTrashStillWritesTheActualStoreSnapshot() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  let previousSaves = fixture.recorder.realStoreSaveCount
  let noteID = try #require(fixture.state.workspace.selectedNoteID)

  #expect(fixture.state.moveToTrash(noteID, suppressConfirmation: true))
  try await fixture.state.flushPendingPersistenceForAgentWrite()

  #expect(fixture.recorder.realStoreSaveCount > previousSaves)
  #expect(try await fixture.store.loadTrash().contains(where: { $0.id == noteID }))
  #expect(
    fixture.recorder.records.contains {
      $0.generation == fixture.state.persistenceGeneration && $0.result == .committed
    }
  )
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func failedSaveDoesNotCertifyItsGeneration() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  fixture.state.updateSelected(body: "Must reach the retry save")
  fixture.recorder.failNextSave()

  let failedSave = fixture.state.saveNow()
  var didFail = false
  do {
    try await failedSave.value
  } catch {
    didFail = true
  }
  #expect(didFail)
  #expect(fixture.state.saveError != nil)
  let savesAfterFailure = fixture.recorder.realStoreSaveCount
  #expect(savesAfterFailure == 1)
  fixture.state.saveError = nil

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == savesAfterFailure + 1)
  #expect(fixture.recorder.records.last?.result == .committed)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func supersededSaveDoesNotCertifyItsGeneration() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let generation = fixture.state.persistenceGeneration
  let seedResult = try await fixture.store.save(
    workspace: fixture.state.workspace,
    preferences: fixture.state.preferences,
    generation: generation + 1
  )
  #expect(seedResult == .committed)

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.records.last?.result == .superseded)
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 2)
  #expect(fixture.recorder.records.map(\.result) == [.superseded, .superseded])
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func cancelledBeforeCommitSaveDoesNotCertifyItsGeneration() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  fixture.state.updateSelected(body: "Cancelled before commit")
  await fixture.beforeSavePause.arm()

  let cancelledSave = fixture.state.saveNow()
  await fixture.beforeSavePause.waitUntilPaused()
  cancelledSave.cancel()
  await fixture.beforeSavePause.release()
  var wasCancelled = false
  do {
    try await cancelledSave.value
  } catch is CancellationError {
    wasCancelled = true
  }
  #expect(wasCancelled)
  #expect(fixture.recorder.realStoreSaveCount == 1)

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 2)
  #expect(fixture.recorder.records.last?.result == .committed)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func activeSameGenerationSavePreventsWriteDrainFastReturn() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  await fixture.beforeSavePause.arm()

  let activeSave = fixture.state.saveNow()
  await fixture.beforeSavePause.waitUntilPaused()

  do {
    try await fixture.state.flushPendingPersistenceForAgentWrite()
  } catch {
    await fixture.beforeSavePause.release()
    _ = await activeSave.result
    throw error
  }
  #expect(fixture.recorder.realStoreSaveCount == 2)

  await fixture.beforeSavePause.release()
  try await activeSave.value
  #expect(fixture.recorder.realStoreSaveCount == 3)
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 3)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func olderCommittedSaveCompletionCannotReplaceNewerDurableGeneration()
  async throws
{
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  let olderGeneration = fixture.state.persistenceGeneration
  await fixture.recorder.afterCommitPause.arm()

  let olderSave = fixture.state.saveNow()
  await fixture.recorder.waitUntilAfterCommitPauses()

  fixture.state.updateSelected(body: "Newer durable generation")
  let newerGeneration = fixture.state.persistenceGeneration
  do {
    try await fixture.state.flushPendingPersistenceForAgentWrite()
  } catch {
    await fixture.recorder.releaseAfterCommit()
    _ = await olderSave.result
    throw error
  }
  #expect(fixture.recorder.records.map(\.generation) == [
    olderGeneration,
    olderGeneration,
    newerGeneration,
  ])

  await fixture.recorder.releaseAfterCommit()
  try await olderSave.value
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == 3)
  await fixture.state.quiescePersistenceForTesting()
}

@Test @MainActor func synchronousAgentCommitCertifiesItsCommittedGeneration() async throws {
  let fixture = await makeAgentPersistenceDrainFixture()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  try await fixture.state.flushPendingPersistenceForAgentWrite()
  let originalNote = try #require(fixture.state.workspace.notes.first)
  var committedWorkspace = fixture.state.workspace
  _ = committedWorkspace.updateContent(
    id: originalNote.id,
    body: "Synchronous agent commit",
    rtf: nil
  )
  let committedNote = try #require(
    committedWorkspace.notes.first(where: { $0.id == originalNote.id })
  )
  let bodySHA256 = SHA256.hash(data: Data(committedNote.body.utf8))
    .map { String(format: "%02x", $0) }
    .joined()
  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(),
    noteID: committedNote.id,
    resultingRevision: committedNote.revision,
    bodySHA256: bodySHA256,
    actor: .localUser,
    operationID: UUID(),
    expiresAt: Date().addingTimeInterval(600)
  )

  try fixture.state.commitAgentWorkspace(
    committedWorkspace,
    expectedGeneration: fixture.state.persistenceGeneration,
    commitProof: proof
  )
  #expect(try await fixture.store.loadSnapshot().workspace.notes.first?.body == committedNote.body)
  let savesAfterAgentCommit = fixture.recorder.realStoreSaveCount

  try await fixture.state.flushPendingPersistenceForAgentWrite()
  #expect(fixture.recorder.realStoreSaveCount == savesAfterAgentCommit)
  await fixture.state.quiescePersistenceForTesting()
}
