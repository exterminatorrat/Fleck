import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Suite("SaveFeedbackPresentation")
@MainActor
struct SaveFeedbackPresentationTests {
  @Test
  func approvedValueWordsDescribeEachQuietState() {
    #expect(SaveFeedbackPresentation.revealDelay == .milliseconds(800))
    #expect(SaveFeedbackState.saved.accessibilityValue == "All changes saved")
    #expect(SaveFeedbackState.pending.accessibilityValue == "Changes pending")
    #expect(SaveFeedbackState.saving.accessibilityValue == "Saving")
    #expect(SaveFeedbackState.failed.accessibilityValue == "Save failed")
    #expect(!SaveFeedbackState.saved.helpText.isEmpty)
    #expect(!SaveFeedbackState.pending.helpText.isEmpty)
    #expect(!SaveFeedbackState.saving.helpText.isEmpty)
    #expect(!SaveFeedbackState.failed.helpText.isEmpty)
  }

  @Test
  func routineSaveStaysQuietAndLateRevealCannotReviveSaving() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.changesScheduled()
    #expect(feedback.state == .pending)
    #expect(scheduler.delays.isEmpty)

    feedback.writeBegan()
    #expect(feedback.state == .pending)
    #expect(scheduler.delays == [SaveFeedbackPresentation.revealDelay])

    feedback.writeEnded()
    feedback.settle(.saved)
    #expect(feedback.state == .saved)

    scheduler.fireAll()
    #expect(feedback.state == .saved)
  }

  @Test
  func slowWriteRevealsSavingOnlyAfterTheThreshold() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.changesScheduled()
    feedback.writeBegan()
    #expect(feedback.state == .pending)

    scheduler.fireAll()
    #expect(feedback.state == .saving)

    feedback.writeEnded()
    feedback.settle(.saved)
    #expect(feedback.state == .saved)
  }

  @Test
  func cancelledWriteCancelsItsStaleReveal() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.changesScheduled()
    feedback.writeBegan()
    feedback.writeEnded()
    feedback.writeCancelled()
    #expect(feedback.state == .pending)

    scheduler.fireAll()
    #expect(feedback.state == .pending)
  }

  @Test
  func cancellingARevealedWriteReturnsToPending() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.changesScheduled()
    feedback.writeBegan()
    scheduler.fireAll()
    #expect(feedback.state == .saving)

    feedback.writeEnded()
    feedback.writeCancelled()
    #expect(feedback.state == .pending)
  }

  @Test
  func overlappingWritesRevealOnceAndSettleOnlyWhenTheLastWriteEnds() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.changesScheduled()
    feedback.writeBegan()
    feedback.writeBegan()
    #expect(scheduler.delays.count == 1)

    scheduler.fireAll()
    #expect(feedback.state == .saving)

    feedback.writeEnded()
    feedback.settle(.saved)
    #expect(feedback.state == .saving)

    feedback.writeEnded()
    feedback.settle(.saved)
    #expect(feedback.state == .saved)
  }

  @Test
  func failureStaysVisibleUntilASaveSucceeds() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.changesScheduled()
    feedback.writeBegan()
    feedback.writeEnded()
    feedback.settle(.failed)
    #expect(feedback.state == .failed)

    feedback.changesScheduled()
    #expect(feedback.state == .failed)

    feedback.writeBegan()
    #expect(feedback.state == .pending)

    feedback.writeEnded()
    feedback.settle(.saved)
    #expect(feedback.state == .saved)
  }

  @Test
  func resetDiscardsInFlightWritesAndTheirReveal() {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)

    feedback.writeBegan()
    feedback.reset()
    #expect(feedback.state == .saved)

    scheduler.fireAll()
    #expect(feedback.state == .saved)
    feedback.settle(.saved)
    #expect(feedback.state == .saved)
  }

  @Test
  func quickDebouncedSaveStaysQuiet() async throws {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)
    let fixture = try await SaveFeedbackFixture(feedback: feedback) { _, _, _, _ in
      .committed
    }
    defer { fixture.remove() }

    fixture.state.updateSelected(body: "Quick edit")
    #expect(feedback.state == .pending)

    try await waitForFeedback(feedback, toEqual: .saved)
    scheduler.fireAll()
    #expect(feedback.state == .saved)
  }

  @Test
  func slowWriteRevealsSavingFromTheActualWrite() async throws {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)
    let gate = PersistenceWriteGate()
    let fixture = try await SaveFeedbackFixture(feedback: feedback) { _, _, _, _ in
      await gate.save()
    }
    defer { fixture.remove() }

    fixture.state.updateSelected(body: "Slow edit")
    #expect(feedback.state == .pending)
    #expect(scheduler.delays.isEmpty)

    await gate.waitUntilStarted(1)
    #expect(feedback.state == .pending)
    #expect(scheduler.delays == [SaveFeedbackPresentation.revealDelay])

    scheduler.fireAll()
    #expect(feedback.state == .saving)

    await gate.releaseNext()
    await gate.waitUntilCompleted(1)
    try await waitForFeedback(feedback, toEqual: .saved)
    scheduler.fireAll()
    #expect(feedback.state == .saved)
  }

  @Test
  func olderWriteCompletionKeepsSavingWhileANewerWriteRuns() async throws {
    let scheduler = RevealScheduler()
    let feedback = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)
    let gate = PersistenceWriteGate()
    let fixture = try await SaveFeedbackFixture(feedback: feedback) { _, _, _, _ in
      await gate.save()
    }
    defer { fixture.remove() }

    fixture.state.saveNow()
    fixture.state.saveNow()
    await gate.waitUntilStarted(2)
    #expect(scheduler.delays.count == 1)

    scheduler.fireAll()
    #expect(feedback.state == .saving)

    await gate.releaseNext()
    await gate.waitUntilCompleted(1)
    try await waitForSaveStatus(fixture.state, toEqual: .saved)
    #expect(feedback.state == .saving)

    await gate.releaseNext()
    await gate.waitUntilCompleted(2)
    try await waitForFeedback(feedback, toEqual: .saved)
  }

  @Test
  func failedPersistenceOffersRetryAndKeepsTheErrorUntilASaveSucceeds() async throws {
    let gate = FailingThenHeldSaveGate()
    let fixture = try await SaveFeedbackFixture { _, _, _, _ in
      try await gate.save()
    }
    defer { fixture.remove() }
    let feedback = fixture.state.saveFeedback

    let failedSave = fixture.state.saveNow()
    await gate.waitUntilCompleted(1)
    await #expect(throws: SaveFeedbackTestError.self) {
      try await failedSave.value
    }

    try await waitForFeedback(feedback, toEqual: .failed)
    #expect(fixture.state.saveError != nil)
    #expect(fixture.state.canRetryPersistenceSave)

    fixture.state.retryPersistenceSave()
    await gate.waitUntilStarted(2)
    #expect(fixture.state.saveError != nil)
    #expect(feedback.state == .pending)

    await gate.releaseHeldWrite()
    await gate.waitUntilCompleted(2)
    try await waitForFeedback(feedback, toEqual: .saved)
    #expect(fixture.state.saveError == nil)
    #expect(!fixture.state.canRetryPersistenceSave)
  }

  @Test
  func importErrorOverwritingAPersistenceErrorIsNotRetryable() async throws {
    let gate = FailingThenHeldSaveGate()
    let fixture = try await SaveFeedbackFixture { _, _, _, _ in
      try await gate.save()
    }
    defer { fixture.remove() }

    let failedSave = fixture.state.saveNow()
    await gate.waitUntilCompleted(1)
    _ = try? await failedSave.value
    try await waitForFeedback(fixture.state.saveFeedback, toEqual: .failed)
    #expect(fixture.state.canRetryPersistenceSave)

    fixture.state.inlineNoteImageImportFailed("Import failed: unsupported image")
    #expect(fixture.state.saveError != nil)
    #expect(!fixture.state.canRetryPersistenceSave)
  }

  @Test
  func olderWriteDoesNotDeclareSavedWhileANewerEditIsStillQueued() async throws {
    let gate = PersistenceWriteGate()
    let fixture = try await SaveFeedbackFixture { _, _, _, _ in
      await gate.save()
    }
    defer { fixture.remove() }
    let feedback = fixture.state.saveFeedback

    fixture.state.saveNow()
    await gate.waitUntilStarted(1)

    fixture.state.updateSelected(body: "Newer edit")
    #expect(feedback.state == .pending)

    await gate.releaseNext()
    await gate.waitUntilCompleted(1)
    try await waitForSaveStatus(fixture.state, toEqual: .saved)
    #expect(feedback.state == .pending)

    await gate.waitUntilStarted(2)
    await gate.releaseNext()
    await gate.waitUntilCompleted(2)
    try await waitForFeedback(feedback, toEqual: .saved)
  }

  @Test
  func clearingAnUnrelatedErrorWhileAnEditIsQueuedKeepsChangesPending() async throws {
    let fixture = try await SaveFeedbackFixture { _, _, _, _ in
      .committed
    }
    defer { fixture.remove() }
    let feedback = fixture.state.saveFeedback

    fixture.state.updateSelected(body: "Queued edit")
    #expect(feedback.state == .pending)

    fixture.state.folderActionFailed("Could not open folder", folderID: nil)
    fixture.state.folderActionSucceeded(folderID: nil)
    #expect(fixture.state.saveError == nil)
    #expect(feedback.state == .pending)

    try await waitForFeedback(feedback, toEqual: .saved)
  }

  @Test
  func folderAndImportErrorsAreNotPresentedAsRetryableSaves() async throws {
    let fixture = try await SaveFeedbackFixture { _, _, _, _ in
      .committed
    }
    defer { fixture.remove() }
    let feedback = fixture.state.saveFeedback

    fixture.state.folderActionFailed("Could not open folder", folderID: nil)
    #expect(fixture.state.saveError != nil)
    #expect(!fixture.state.canRetryPersistenceSave)
    #expect(feedback.state == .saved)

    fixture.state.inlineNoteImageImportFailed("Import failed: unsupported image")
    #expect(fixture.state.saveError != nil)
    #expect(!fixture.state.canRetryPersistenceSave)
    #expect(feedback.state == .saved)
  }

  @Test
  func retryWithoutAPersistenceErrorDoesNotStartAWrite() async throws {
    let gate = PersistenceWriteGate()
    let fixture = try await SaveFeedbackFixture { _, _, _, _ in
      await gate.save()
    }
    defer { fixture.remove() }

    let startsBeforeRetry = await gate.startCount()
    fixture.state.retryPersistenceSave()
    for _ in 0..<5 { await Task.yield() }

    #expect(fixture.state.saveFeedback.state == .saved)
    #expect(await gate.startCount() == startsBeforeRetry)
  }
}

@MainActor
private struct SaveFeedbackFixture {
  let root: URL
  let state: AppState

  init(
    feedback: SaveFeedbackPresentation = SaveFeedbackPresentation(),
    saveOperation: @escaping AppState.SaveOperation
  ) async throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let note = Note(title: "Quiet save", body: "Body")
    let store = LocalStore(rootURL: root)
    try await store.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: []),
      preferences: .init()
    )
    state = AppState(
      store: store,
      saveOperation: saveOperation,
      saveFeedback: feedback
    )
    await state.waitUntilInitialLoad()
    #expect(state.workspace.selectedNoteID == note.id)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private func waitForSaveStatus(
  _ state: AppState,
  toEqual expected: AppState.SaveStatus,
  timeout: Duration = .seconds(2)
) async throws {
  let deadline = ContinuousClock.now + timeout
  while state.saveStatus != expected, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(state.saveStatus == expected)
}

@MainActor
private func waitForFeedback(
  _ feedback: SaveFeedbackPresentation,
  toEqual expected: SaveFeedbackState,
  timeout: Duration = .seconds(2)
) async throws {
  let deadline = ContinuousClock.now + timeout
  while feedback.state != expected, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(feedback.state == expected)
}

private enum SaveFeedbackTestError: Error {
  case failed
}

private actor PersistenceWriteGate {
  private var started = 0
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var openWrites: [CheckedContinuation<LocalStoreSnapshotWriteResult, Never>] = []
  private var completed = 0
  private var completedContinuation: CheckedContinuation<Void, Never>?

  func save() async -> LocalStoreSnapshotWriteResult {
    started += 1
    startedContinuation?.resume()
    startedContinuation = nil
    let result = await withCheckedContinuation { continuation in
      openWrites.append(continuation)
    }
    completed += 1
    completedContinuation?.resume()
    completedContinuation = nil
    return result
  }

  func waitUntilStarted(_ expected: Int) async {
    while started < expected {
      await withCheckedContinuation { startedContinuation = $0 }
    }
  }

  func releaseNext() {
    guard !openWrites.isEmpty else { return }
    openWrites.removeFirst().resume(returning: .committed)
  }

  func waitUntilCompleted(_ expected: Int) async {
    while completed < expected {
      await withCheckedContinuation { completedContinuation = $0 }
    }
  }

  func startCount() -> Int { started }
}

private actor FailingThenHeldSaveGate {
  private var attempts = 0
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var heldWrite: CheckedContinuation<Void, Never>?
  private var completed = 0
  private var completedContinuation: CheckedContinuation<Void, Never>?

  func save() async throws -> LocalStoreSnapshotWriteResult {
    attempts += 1
    startedContinuation?.resume()
    startedContinuation = nil
    if attempts == 1 {
      completed += 1
      completedContinuation?.resume()
      completedContinuation = nil
      throw SaveFeedbackTestError.failed
    }
    await withCheckedContinuation { heldWrite = $0 }
    completed += 1
    completedContinuation?.resume()
    completedContinuation = nil
    return .committed
  }

  func waitUntilStarted(_ expected: Int) async {
    while attempts < expected {
      await withCheckedContinuation { startedContinuation = $0 }
    }
  }

  func releaseHeldWrite() {
    heldWrite?.resume()
    heldWrite = nil
  }

  func waitUntilCompleted(_ expected: Int) async {
    while completed < expected {
      await withCheckedContinuation { completedContinuation = $0 }
    }
  }
}

@MainActor
private final class RevealScheduler {
  private(set) var delays: [Duration] = []
  private var actions: [@MainActor () -> Void] = []

  func schedule(
    after delay: Duration,
    _ action: @escaping @MainActor () -> Void
  ) {
    delays.append(delay)
    actions.append(action)
  }

  func fireAll() {
    let pending = actions
    actions.removeAll()
    for action in pending { action() }
  }
}
