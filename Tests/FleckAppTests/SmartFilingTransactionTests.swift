import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func smartFilingCommitsTwoNotesAndUndoAsOneSnapshot() async throws {
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let plan = try fixture.plan()
  let receipt = try await fixture.state.saveSmartFiling(plan, captureID: UUID())
  let metadata = try #require(receipt.filing)
  #expect(metadata.insertions.count == 2)
  let persisted = try await fixture.store.loadWorkspace()
  #expect(persisted == fixture.state.workspace)
  #expect(persisted.dictationFilingLedger.commits == [metadata])
  let alpha = try #require(persisted.notes.first(where: { $0.id == fixture.notes[0].id }))
  let captureStart = try #require(alpha.body.range(of: "Alpha planning task.")?.lowerBound)
  let nextHeadingStart = try #require(alpha.body.range(of: "# Later")?.lowerBound)
  #expect(captureStart < nextHeadingStart)
  #expect(await fixture.state.undoSmartCapture(receipt))
  #expect(fixture.state.workspace.notes.map(\.body) == fixture.notes.map(\.body))
  let undone = try await fixture.store.loadWorkspace()
  #expect(undone.dictationFilingLedger.commits.first?.state == .undone)
  #expect(undone.notes.map(\.body) == fixture.notes.map(\.body))
}

@Test @MainActor func smartFilingRetryAndRestartNeverRecommitEvenWhenRoutingChanges() async throws {
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let plan = try fixture.plan()
  let captureID = UUID()
  let receipt = try await fixture.state.saveSmartFiling(plan, captureID: captureID)
  let committed = fixture.state.workspace
  #expect(try await fixture.state.saveSmartFiling(plan, captureID: captureID) == receipt)
  #expect(try await fixture.state.saveSmartCapture(
    text: plan.text, captureID: captureID, destinationID: fixture.notes[1].id
  ) == receipt)
  #expect(fixture.state.workspace == committed)
  let restarted = try await SmartFilingFixture.load(store: fixture.store, notes: fixture.notes)
  #expect(try await restarted.saveSmartFiling(plan, captureID: captureID) == receipt)
  #expect(restarted.workspace == committed)
  #expect(await restarted.undoSmartCapture(receipt))
  do {
    _ = try await restarted.saveSmartFiling(plan, captureID: captureID)
    Issue.record("An undone capture identity must never be replayed")
  } catch DictationFilingSaveError.conflictingCapture {}
  #expect(restarted.workspace.notes.map(\.body) == fixture.notes.map(\.body))
}

@Test @MainActor func smartFilingReceiptIdentitySurvivesReversePlanOrderRetryRestartAndUndo()
  async throws
{
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let text = "Beta cooking task. Alpha planning task."
  let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
  let plan = try #require(DictationFilingPlan.make(
    text: text,
    fragments: zip(chunks, [fixture.notes[1].id, fixture.notes[0].id]).map {
      .init(text: $0.0, destinationID: $0.1)
    },
    candidates: fixture.state.activeDestinations(), inboxID: nil
  ))
  #expect(plan.outputs.first?.destinationID == fixture.notes[1].id)
  let captureID = UUID()
  let receipt = try await fixture.state.saveSmartFiling(plan, captureID: captureID)
  let committed = try #require(receipt.filing)
  let canonicalInsertion = try #require(committed.insertions.first)
  #expect(receipt.noteID == canonicalInsertion.noteID)
  #expect(receipt.noteID == fixture.notes[0].id)
  #expect(receipt.noteID != plan.outputs.first?.destinationID)
  #expect(try await fixture.state.saveSmartCapture(
    text: text, captureID: captureID, destinationID: fixture.notes[1].id
  ) == receipt)

  let restarted = try await SmartFilingFixture.load(store: fixture.store, notes: fixture.notes)
  let recovered = try await restarted.saveSmartFiling(plan, captureID: captureID)
  #expect(recovered == receipt)
  #expect(await restarted.undoSmartCapture(recovered))
  #expect(restarted.workspace.notes.map(\.body) == fixture.notes.map(\.body))
  #expect(restarted.workspace.dictationFilingLedger.commits.first?.state == .undone)
}

@Test @MainActor func smartFilingRebasesMultipleSectionRangesWithinOneDestination() async throws {
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let text = "Alpha later task. Beta cooking task. Alpha planning task."
  let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
  let destinationIDs = [fixture.notes[0].id, fixture.notes[1].id, fixture.notes[0].id]
  let plan = try #require(DictationFilingPlan.make(
    text: text,
    fragments: zip(chunks, destinationIDs).map { .init(text: $0.0, destinationID: $0.1) },
    candidates: fixture.state.activeDestinations(), inboxID: nil
  ))
  let receipt = try await fixture.state.saveSmartFiling(plan, captureID: UUID())
  #expect(receipt.filing?.insertions.count == 3)
  #expect(fixture.state.workspace.dictationFilingLedger.isValid)
  #expect(await fixture.state.undoSmartCapture(receipt))
  #expect(fixture.state.workspace.notes.map(\.body) == fixture.notes.map(\.body))
}

@Test @MainActor func smartFilingRejectsChangedInputAndStaleDestinationsWithoutWrites() async throws {
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let plan = try fixture.plan()
  fixture.state.workspace.updateContent(id: fixture.notes[1].id, body: "newer edit", rtf: nil)
  let before = fixture.state.workspace
  do {
    _ = try await fixture.state.saveSmartFiling(plan, captureID: UUID())
    Issue.record("A stale routing snapshot must not commit any output")
  } catch DictationFilingSaveError.invalidPlan {}
  #expect(fixture.state.workspace == before)
  #expect(try await fixture.store.loadWorkspace().notes.map(\.body) == fixture.notes.map(\.body))

  let freshPlan = try fixture.plan()
  let captureID = UUID()
  _ = try await fixture.state.saveSmartFiling(freshPlan, captureID: captureID)
  let committed = fixture.state.workspace
  do {
    _ = try await fixture.state.saveSmartCapture(
      text: "different capture input", captureID: captureID, destinationID: nil
    )
    Issue.record("Changing text cannot reuse a committed identity")
  } catch DictationFilingSaveError.conflictingCapture {}
  #expect(fixture.state.workspace == committed)
}

@Test(arguments: [false, true]) @MainActor
func smartFilingFailureAndSupersededResultRollbackAllOutputs(_ superseded: Bool) async throws {
  let fixture = try await SmartFilingFixture.make(saveOperation: { store in
    { workspace, preferences, trashed, generation in
      if !workspace.dictationFilingLedger.commits.isEmpty {
        if superseded { return .superseded }
        throw SmartFilingFailure.injected
      }
      return try await store.save(
        workspace: workspace, preferences: preferences,
        trashedNotes: trashed, generation: generation
      )
    }
  })
  defer { fixture.removeFiles() }
  let before = fixture.state.workspace
  do {
    _ = try await fixture.state.saveSmartFiling(try fixture.plan(), captureID: UUID())
    Issue.record("A failed or superseded snapshot must not return a commit receipt")
  } catch {}
  #expect(fixture.state.workspace == before)
  #expect(try await fixture.store.loadWorkspace() == before)
}

@Test @MainActor func smartFilingLateCancellationReturnsReceiptForWholeCaptureCompensation()
  async throws
{
  let gate = SmartFilingGate()
  let fixture = try await SmartFilingFixture.make(saveOperation: { store in
    { workspace, preferences, trashed, generation in
      let result = try await store.save(
        workspace: workspace, preferences: preferences,
        trashedNotes: trashed, generation: generation
      )
      if !workspace.dictationFilingLedger.commits.isEmpty { await gate.pause() }
      return result
    }
  })
  defer { fixture.removeFiles() }
  let plan = try fixture.plan()
  let task = Task { try await fixture.state.saveSmartFiling(plan, captureID: UUID()) }
  await gate.waitUntilPaused()
  task.cancel()
  await gate.release()
  let receipt = try await task.value
  #expect(receipt.filing?.insertions.count == 2)
  #expect(await fixture.state.undoSmartCapture(receipt))
  #expect(fixture.state.workspace.notes.map(\.body) == fixture.notes.map(\.body))
}

@Test @MainActor func smartFilingCancellationBeforeEntryCannotMutateNotes() async throws {
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let gate = SmartFilingGate()
  let plan = try fixture.plan()
  let before = fixture.state.workspace
  let task = Task {
    await gate.pause()
    return try await fixture.state.saveSmartFiling(plan, captureID: UUID())
  }
  await gate.waitUntilPaused()
  task.cancel()
  await gate.release()
  do {
    _ = try await task.value
    Issue.record("Cancelled filing must not enter its commit")
  } catch is CancellationError {}
  #expect(fixture.state.workspace == before)
}

@Test @MainActor func smartFilingInFlightRetryCannotReturnAnUndurableReceipt() async throws {
  let gate = SmartFilingGate()
  let fixture = try await SmartFilingFixture.make(saveOperation: { store in
    { workspace, preferences, trashed, generation in
      if !workspace.dictationFilingLedger.commits.isEmpty {
        await gate.pause()
        throw SmartFilingFailure.injected
      }
      return try await store.save(
        workspace: workspace, preferences: preferences,
        trashedNotes: trashed, generation: generation
      )
    }
  })
  defer { fixture.removeFiles() }
  let plan = try fixture.plan()
  let captureID = UUID()
  let task = Task { try await fixture.state.saveSmartFiling(plan, captureID: captureID) }
  await gate.waitUntilPaused()
  do {
    _ = try await fixture.state.saveSmartFiling(plan, captureID: captureID)
    Issue.record("An optimistic in-flight ledger entry is not a durable commit")
  } catch {}
  do {
    _ = try await fixture.state.saveSmartCapture(
      text: plan.text, captureID: captureID, destinationID: nil
    )
    Issue.record("Fallback retry cannot bypass the in-flight commit boundary")
  } catch {}
  await gate.release()
  do { _ = try await task.value } catch {}
  #expect(fixture.state.workspace.dictationFilingLedger.commits.isEmpty)
  let restarted = try await SmartFilingFixture.load(store: fixture.store, notes: fixture.notes)
  let receipt = try await restarted.saveSmartFiling(plan, captureID: captureID)
  #expect(receipt.filing?.captureID == captureID)
  #expect(restarted.workspace.dictationFilingLedger.commits.count == 1)
}

@Test @MainActor func smartFilingEditedTargetMakesAggregateUndoFailWithoutPartialRemoval()
  async throws
{
  let fixture = try await SmartFilingFixture.make()
  defer { fixture.removeFiles() }
  let receipt = try await fixture.state.saveSmartFiling(try fixture.plan(), captureID: UUID())
  fixture.state.workspace.updateContent(id: fixture.notes[1].id, body: "newer edit", rtf: nil)
  let edited = fixture.state.workspace
  #expect(!(await fixture.state.undoSmartCapture(receipt)))
  #expect(fixture.state.workspace == edited)
  #expect(fixture.state.workspace.dictationFilingLedger.commits.first?.state == .committed)
}

@Test @MainActor func smartFilingFailedSavePreservesConcurrentUnrelatedWorkspaceEdits()
  async throws
{
  let gate = SmartFilingGate()
  let fixture = try await SmartFilingFixture.make(saveOperation: { store in
    { workspace, preferences, trashed, generation in
      if !workspace.dictationFilingLedger.commits.isEmpty {
        await gate.pause()
        throw SmartFilingFailure.injected
      }
      return try await store.save(
        workspace: workspace, preferences: preferences,
        trashedNotes: trashed, generation: generation
      )
    }
  })
  defer { fixture.removeFiles() }
  let plan = try fixture.plan()
  let task = Task { try await fixture.state.saveSmartFiling(plan, captureID: UUID()) }
  await gate.waitUntilPaused()
  let unrelated = Note(title: "Unrelated", body: "concurrent user edit")
  fixture.state.workspace.notes.append(unrelated)
  await gate.release()
  do { _ = try await task.value } catch {}
  #expect(fixture.state.workspace.notes.contains(unrelated))
  #expect(fixture.state.workspace.notes.prefix(2).map(\.body) == fixture.notes.map(\.body))
  #expect(fixture.state.workspace.dictationFilingLedger.commits.isEmpty)
}

@MainActor
private struct SmartFilingFixture {
  let state: AppState
  let store: LocalStore
  let root: URL
  let notes: [Note]

  func plan() throws -> DictationFilingPlan {
    let text = "Alpha planning task. Beta cooking task."
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    let fragments = chunks.enumerated().map {
      DictationFilingPlan.Fragment(text: $0.element, destinationID: notes[$0.offset].id)
    }
    return try #require(DictationFilingPlan.make(
      text: text, fragments: fragments, candidates: state.activeDestinations(), inboxID: nil
    ))
  }

  func removeFiles() { try? FileManager.default.removeItem(at: root) }

  static func make(
    saveOperation: ((LocalStore) -> AppState.SaveOperation)? = nil
  ) async throws -> Self {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalStore(rootURL: root)
    let notes = [
      Note(title: "Alpha", body: "# Planning\nExisting\n# Later\nTail"),
      Note(title: "Beta", body: "# Cooking\nExisting\n# Later\nTail"),
    ]
    try await store.save(
      workspace: Workspace(notes: notes, selectedNoteID: notes[0].id), preferences: .init()
    )
    let state = try await load(store: store, notes: notes, saveOperation: saveOperation?(store))
    return Self(state: state, store: store, root: root, notes: notes)
  }

  static func load(
    store: LocalStore, notes: [Note], saveOperation: AppState.SaveOperation? = nil
  ) async throws -> AppState {
    let state = AppState(store: store, saveOperation: saveOperation)
    let deadline = ContinuousClock.now + .seconds(2)
    while state.workspace.notes.map(\.id) != notes.map(\.id), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(state.workspace.notes.map(\.id) == notes.map(\.id))
    return state
  }
}

private actor SmartFilingGate {
  private var paused = false
  private var released = false
  private var entered: CheckedContinuation<Void, Never>?
  private var resume: CheckedContinuation<Void, Never>?

  func pause() async {
    guard !released else { return }
    paused = true
    entered?.resume()
    entered = nil
    await withCheckedContinuation { resume = $0 }
  }

  func waitUntilPaused() async {
    if !paused { await withCheckedContinuation { entered = $0 } }
  }

  func release() {
    released = true
    resume?.resume()
    resume = nil
  }
}

private enum SmartFilingFailure: Error {
  case injected
}
