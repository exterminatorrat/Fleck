@preconcurrency import AVFAudio
import AppKit
import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func processingPathPublishesProvisionalAndCommitsFinalResult() async throws {
  let consumed = ProvisionalUpdateProbe()
  let processing = ProcessingProbe(
    updates: [
      .init(generation: 1, stableText: "", provisionalTail: "send the report"),
      .init(
        generation: 2,
        stableText: "Send the report. ",
        provisionalTail: "today"
      )
    ],
    result: .init(
      rawTranscript: "send the report today",
      dictionaryBaseline: "Send the report today",
      cleanedTranscript: "Send the report today.",
      insertedText: "Send the report today.",
      cleanupOutcome: .cleaned,
      measurements: .empty
    )
  )
  let fixture = try Fixture(
    processing: processing,
    onFocusedProvisionalUpdate: { consumed.record() }
  )

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await processing.emitAll()
  await consumed.waitUntilCount(2)
  await fixture.coordinator.finish()

  #expect(fixture.editor.provisionalTexts == [
    "send the report", "Send the report. today"
  ])
  #expect(fixture.editor.committedTexts == ["Send the report today."])
  #expect(fixture.cleaner.calls == 0)
}

@Test @MainActor
func processingUsesExactDictionaryBaselineForRawFallback() async throws {
  let processing = ProcessingProbe(
    result: .init(
      rawTranscript: "send fleck app",
      dictionaryBaseline: "Send FleckApp",
      cleanedTranscript: nil,
      insertedText: "Send FleckApp",
      cleanupOutcome: .usedRaw,
      measurements: .empty
    )
  )
  let fixture = try Fixture(processing: processing)

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.finish()

  let record = try #require(await fixture.history.list().first)
  #expect(fixture.editor.committedTexts == ["Send FleckApp"])
  #expect(processing.result.dictionaryBaseline == "Send FleckApp")
  #expect(record.rawTranscript == "send fleck app")
  #expect(record.cleanedTranscript == nil)
  #expect(record.cleanupOutcome == .usedRaw)
  #expect(fixture.cleaner.calls == 0)
}

@Test @MainActor
func processingRawRecoveryKeepsRawInsertionAndHistoryFallback() async throws {
  let processing = ProcessingProbe(
    result: .init(
      rawTranscript: "send fleck app",
      dictionaryBaseline: nil,
      cleanedTranscript: nil,
      insertedText: "send fleck app",
      cleanupOutcome: .usedRaw,
      measurements: .empty
    )
  )
  let fixture = try Fixture(processing: processing)

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.finish()

  let record = try #require(await fixture.history.list().first)
  #expect(fixture.editor.committedTexts == ["send fleck app"])
  #expect(processing.result.dictionaryBaseline == nil)
  #expect(record.rawTranscript == "send fleck app")
  #expect(record.cleanedTranscript == nil)
  #expect(record.cleanupOutcome == .usedRaw)
  #expect(fixture.cleaner.calls == 0)
}

@Test @MainActor
func cancellationRejectsLateProcessingUpdateAndResult() async throws {
  let processing = ProcessingProbe()
  let fixture = try Fixture(processing: processing)

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.cancel()
  await processing.emit(.init(
    generation: 99, stableText: "", provisionalTail: "late"
  ))
  processing.complete(with: .init(
    rawTranscript: "late",
    dictionaryBaseline: "late",
    cleanedTranscript: "late.",
    insertedText: "late.",
    cleanupOutcome: .cleaned,
    measurements: .empty
  ))

  #expect(fixture.editor.committedTexts.isEmpty)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(processing.publishedUpdates.isEmpty)
}

enum CancellationEvent: Equatable {
  case focusedEditorRollback
  case finishStarted
  case sessionCancel
  case sourceCancel
  case sourcePhysicalRelease
  case finishUnblocked
  case sessionDrain
  case coordinatorCancelReturned
}

@MainActor
final class CancellationOrderRecorder {
  private(set) var values: [CancellationEvent] = []

  func append(_ event: CancellationEvent) {
    values.append(event)
  }
}

@MainActor
final class ProvisionalUpdateProbe {
  private(set) var count = 0
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func record() {
    count += 1
    let ready = waiters.filter { $0.0 <= count }
    waiters.removeAll { $0.0 <= count }
    ready.forEach { $0.1.resume() }
  }

  func waitUntilCount(_ target: Int) async {
    guard count < target else { return }
    await withCheckedContinuation { continuation in
      waiters.append((target, continuation))
    }
  }
}

@Test @MainActor
func cancellationRollsBackFocusedEditorBeforeSessionAndSourceCancel()
  async throws
{
  let order = CancellationOrderRecorder()
  let processing = ProcessingProbe(
    onSessionCancel: { order.append(.sessionCancel) },
    onSourceCancel: { order.append(.sourceCancel) },
    onSourcePhysicalRelease: { order.append(.sourcePhysicalRelease) }
  )
  let fixture = try Fixture(
    processing: processing,
    onFocusedEditorRollback: { order.append(.focusedEditorRollback) }
  )

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.cancel()

  #expect(order.values == [
    .focusedEditorRollback,
    .sessionCancel,
    .sourceCancel,
    .sourcePhysicalRelease
  ])
  #expect(fixture.editor.committedTexts.isEmpty)
  #expect(fixture.saver.savedTexts.isEmpty)
}

@Test @MainActor
func cancellingEnhancedCaptureDuringBlockedFinishRollsBackBeforeSessionCancelAndDrains()
  async throws
{
  let order = CancellationOrderRecorder()
  let processing = ProcessingProbe(
    finishBlocksUntilCancel: true,
    onFinishStarted: { order.append(.finishStarted) },
    onSessionCancel: { order.append(.sessionCancel) },
    onSourceCancel: { order.append(.sourceCancel) },
    onSourcePhysicalRelease: { order.append(.sourcePhysicalRelease) },
    onFinishUnblocked: { order.append(.finishUnblocked) },
    onSessionDrain: { order.append(.sessionDrain) }
  )
  let fixture = try Fixture(
    processing: processing,
    onFocusedEditorRollback: { order.append(.focusedEditorRollback) }
  )

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  let finishTask = Task { await fixture.coordinator.finish() }
  await processing.waitUntilFinishStarted()
  let cancelTask = Task {
    await fixture.coordinator.cancel()
    order.append(.coordinatorCancelReturned)
  }
  await cancelTask.value
  await finishTask.value

  #expect(order.values.firstIndex(of: .focusedEditorRollback)!
    < order.values.firstIndex(of: .sessionCancel)!)
  #expect(order.values.firstIndex(of: .sessionCancel)!
    < order.values.firstIndex(of: .sourceCancel)!)
  #expect(order.values.firstIndex(of: .sourceCancel)!
    < order.values.firstIndex(of: .finishUnblocked)!)
  #expect(order.values.firstIndex(of: .sessionDrain)!
    < order.values.firstIndex(of: .coordinatorCancelReturned)!)
  #expect(order.values.filter { $0 == .sourceCancel }.count == 1)
  #expect(order.values.filter { $0 == .sourcePhysicalRelease }.count == 1)
  #expect(fixture.editor.provisionalTexts.isEmpty)
  #expect(fixture.editor.committedTexts.isEmpty)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
  #expect(processing.publishedUpdates.isEmpty)
}

@Test @MainActor
func cancellingBlockedFinishWaitsForSessionDrainBeforePublishingAndStartingAgain()
  async throws
{
  let drainGate = Gate()
  let processing = ProcessingProbe(
    finishBlocksUntilCancel: true,
    drainGate: drainGate
  )
  let fixture = try Fixture(processing: processing)
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  let finishTask = Task { await fixture.coordinator.finish() }
  await processing.waitUntilFinishStarted()
  let cancelTask = Task { await fixture.coordinator.cancel() }
  await drainGate.waitUntilWaiting()

  #expect(events.allSatisfy { $0.terminal == nil })
  #expect(!fixture.coordinator.canConfigureShortcut)
  await fixture.coordinator.start(mode: .smartCapture)
  #expect(processing.beginCount == 1)
  #expect(fixture.coordinator.phase == .finalizing)

  await drainGate.openGate()
  await cancelTask.value
  await finishTask.value

  #expect(events.filter { $0.terminal == .cancelled }.count == 1)
  #expect(fixture.coordinator.phase == .idle)
  #expect(fixture.coordinator.canConfigureShortcut)
  await fixture.coordinator.start(mode: .smartCapture)
  #expect(processing.beginCount == 2)
  await fixture.coordinator.cancel()
}

@Test @MainActor
func absentProcessorPreservesLegacyCleanerPath() async throws {
  let fixture = try Fixture(processing: nil)
  fixture.standard.finalText = "Buy tea"
  fixture.cleaner.result = "Buy tea."

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.cleaner.calls == 1)
  #expect(fixture.saver.savedTexts == ["Buy tea."])
}

@Test @MainActor
func cancelDuringLegacySourceFinishDoesNotRollbackOrPublishTerminalState()
  async throws
{
  let fixture = try Fixture()
  let finishGate = Gate()
  fixture.standard.finishGate = finishGate
  fixture.standard.finalText = "Legacy finish"
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  let finishTask = Task { await fixture.coordinator.finish() }
  await finishGate.waitUntilWaiting()

  await fixture.coordinator.cancel()

  #expect(fixture.editor.cancelCount == 0)
  #expect(fixture.standard.cancelCount == 0)
  #expect(fixture.coordinator.phase == .finalizing)
  #expect(events.allSatisfy { $0.terminal == nil })

  await finishGate.openGate()
  await finishTask.value
  #expect(fixture.editor.committedTexts == ["Legacy finish"])
}

@Test @MainActor func coordinatorRequestsStandardByDefault() async throws {
  let fixture = try Fixture()

  await fixture.coordinator.start(mode: .smartCapture)

  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.standard.startCount == 1)
  await fixture.coordinator.cancel()
}

@Test @MainActor func coordinatorForwardsOnlyActiveCaptureLevels() async throws {
  let fixture = try Fixture()
  var levels: [Float] = []
  fixture.coordinator.setLevelObserver { levels.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)
  fixture.standard.emitLevel(0.42)
  await fixture.coordinator.cancel()
  fixture.standard.emitLevel(0.9)

  #expect(levels == [0.42, 0])
}

@Test @MainActor
func processingPathForwardsOnlyActiveCaptureLevels() async throws {
  let processing = ProcessingProbe(synchronousLevel: 0.25)
  let fixture = try Fixture(processing: processing)
  var levels: [Float] = []
  fixture.coordinator.setLevelObserver { levels.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)
  processing.emitLevel(0.5)
  await fixture.coordinator.cancel()
  processing.emitLevel(0.9)

  #expect(levels == [0.25, 0.5, 0])
}

@Test @MainActor func failedStartResetsTheLevel() async throws {
  let fixture = try Fixture()
  fixture.standard.startError = TestError.failed
  var levels: [Float] = []
  fixture.coordinator.setLevelObserver { levels.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)

  #expect(levels == [0])
}

@Test @MainActor func enhancedCaptureStaysBoundToItsSelectedEngine() async throws {
  let fixture = try Fixture(preferred: .enhancedLocal)
  fixture.enhanced.finalText = "Plan lunch"

  await fixture.coordinator.start(mode: .smartCapture)
  fixture.preferred = .standard
  await fixture.coordinator.finish()

  #expect(fixture.provider.requestedKinds == [.enhancedLocal])
  #expect(fixture.enhanced.startCount == 1)
  #expect(fixture.enhanced.finishCount == 1)
  #expect(fixture.standard.startCount == 0)
}

@Test @MainActor func failedStartNeverFailsOverMidCaptureAndChangesNextPreference() async throws {
  let fixture = try Fixture(preferred: .enhancedLocal)
  fixture.enhanced.startError = TestError.failed
  fixture.enhanced.onStart = { fixture.preferred = .standard }

  await fixture.coordinator.start(mode: .smartCapture)

  #expect(fixture.provider.requestedKinds == [.enhancedLocal])
  #expect(fixture.standard.startCount == 0)
  #expect(fixture.preferred == .standard)
  #expect(fixture.enhanced.releaseCount == 1)

  await fixture.coordinator.start(mode: .smartCapture)
  #expect(fixture.provider.requestedKinds == [.enhancedLocal, .standard])
  await fixture.coordinator.cancel()
}

@Test @MainActor func shortShortcutHoldDoesNotStartCapture() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })

  fixture.coordinator.beginShortcut(editor: nil)
  await threshold.waitUntilWaiting()
  await fixture.coordinator.endShortcut()
  await threshold.openGate()
  await Task.yield()

  #expect(fixture.provider.requestedKinds.isEmpty)
  #expect(fixture.standard.startCount == 0)
  #expect(fixture.editor.beginCount == 0)
}

@Test @MainActor func shortcutStartsAtThresholdWhileHeldAndReleaseFinalizes() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  fixture.standard.finalText = "Held dictation"

  fixture.coordinator.beginShortcut(editor: nil)
  #expect(fixture.coordinator.phase == .arming)
  await threshold.waitUntilWaiting()
  await threshold.openGate()
  #expect(await waitForListening(fixture.coordinator, timeout: .seconds(1)))

  #expect(fixture.standard.startCount == 1)
  #expect(fixture.coordinator.phase == .listening(mode: .smartCapture, engine: .standard))

  await fixture.coordinator.endShortcut()

  #expect(fixture.standard.finishCount == 1)
  #expect(fixture.saver.savedTexts == ["Held dictation"])
}

@Test @MainActor func handsFreeShortcutStartsWithoutTheHoldThreshold() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  fixture.standard.finalText = "Hands free"

  let session = try #require(fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  ))

  #expect(await waitForListening(fixture.coordinator, timeout: .seconds(1)))
  #expect(fixture.coordinator.phase == .listening(
    mode: .smartCapture,
    engine: .standard
  ))
  await fixture.coordinator.finishHandsFreeShortcut(session)
  await fixture.coordinator.waitForShortcutTerminal(session)
  #expect(fixture.saver.savedTexts == ["Hands free"])
}

@Test @MainActor func handsFreeShortcutFinishAndCancelRequireTheOwnedSession() async throws {
  let fixture = try Fixture()
  let session = try #require(fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  ))
  let foreignSession = DictationShortcutSession(id: UUID())

  #expect(await waitForListening(fixture.coordinator, timeout: .seconds(1)))
  await fixture.coordinator.finishHandsFreeShortcut(foreignSession)
  await fixture.coordinator.cancelShortcut(foreignSession)

  #expect(fixture.coordinator.phase == .listening(
    mode: .smartCapture,
    engine: .standard
  ))
  await fixture.coordinator.cancelShortcut(session)
  await fixture.coordinator.waitForShortcutTerminal(session)
  #expect(fixture.saver.savedTexts.isEmpty)
}

@Test @MainActor func handsFreeShortcutRejectsToolbarCapture() async throws {
  let fixture = try Fixture()
  await fixture.coordinator.start(mode: .smartCapture)

  let session = fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  )

  #expect(session == nil)
  #expect(fixture.coordinator.phase == .listening(
    mode: .smartCapture,
    engine: .standard
  ))
  await fixture.coordinator.cancel()
}

@Test @MainActor func handsFreeShortcutRejectsRecoveryInFlight() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "First capture"
  fixture.saver.undoGate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  let recovery = Task { await fixture.coordinator.performRecoveryAction() }
  await gate.waitUntilWaiting()

  let session = fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  )

  #expect(session == nil)
  await gate.openGate()
  #expect(await recovery.value == .completed)
}

@Test @MainActor func handsFreeShortcutRejectsAnArmedHold() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  let holdSession = try #require(fixture.coordinator.beginShortcut(editor: nil))
  await threshold.waitUntilWaiting()

  let handsFreeSession = fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  )

  #expect(handsFreeSession == nil)
  await fixture.coordinator.cancelShortcut(holdSession)
}

@Test @MainActor func handsFreeShortcutRejectsAnotherHandsFreeSession() async throws {
  let fixture = try Fixture()
  let session = try #require(fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  ))

  let secondSession = fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  )

  #expect(secondSession == nil)
  await fixture.coordinator.cancelShortcut(session)
}

@MainActor
private func waitForListening(
  _ coordinator: DictationCoordinator,
  timeout: Duration
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if case .listening = coordinator.phase { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  if case .listening = coordinator.phase { return true }
  return false
}

private func waitForCompletion(
  _ probe: CompletionProbe,
  timeout: Duration
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await probe.isComplete { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return await probe.isComplete
}

@Test @MainActor func heldShortcutPublishesEachPhaseExactlyOnceInOrder() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  fixture.standard.finalText = "Held dictation"
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  fixture.coordinator.beginShortcut(editor: nil)
  await threshold.waitUntilWaiting()
  await threshold.openGate()
  for _ in 0..<20 {
    if case .listening = fixture.coordinator.phase { break }
    await Task.yield()
  }
  await fixture.coordinator.endShortcut()

  #expect(events == [
    .init(phase: .arming, terminal: nil),
    .init(phase: .listening(mode: .smartCapture, engine: .standard), terminal: nil),
    .init(phase: .finalizing, terminal: nil),
    .init(phase: .cleaning, terminal: nil),
    .init(phase: .routing, terminal: nil),
    .init(
      phase: .saved(fixture.inbox),
      terminal: .saved(
        mode: .smartCapture,
        cleanup: .cleaned,
        destination: fixture.inbox
      )
    ),
  ])
}

@Test @MainActor func shortcutChoosesFocusedOnlyForActiveFleckEditor() async throws {
  let focusedThreshold = Gate()
  let focused = try Fixture(holdSleeper: { _ in await focusedThreshold.wait() })

  focused.coordinator.beginShortcut(editor: focused.editor)
  await focusedThreshold.waitUntilWaiting()
  await focusedThreshold.openGate()
  for _ in 0..<20 {
    if case .listening = focused.coordinator.phase { break }
    await Task.yield()
  }

  #expect(focused.coordinator.phase == .listening(mode: .focused, engine: .standard))
  #expect(focused.editor.beginCount == 1)
  await focused.coordinator.cancel()

  let smartThreshold = Gate()
  let smart = try Fixture(holdSleeper: { _ in await smartThreshold.wait() })
  smart.coordinator.beginShortcut(editor: nil)
  await smartThreshold.waitUntilWaiting()
  await smartThreshold.openGate()
  for _ in 0..<20 {
    if case .listening = smart.coordinator.phase { break }
    await Task.yield()
  }

  #expect(smart.coordinator.phase == .listening(mode: .smartCapture, engine: .standard))
  #expect(smart.editor.beginCount == 0)
  await smart.coordinator.cancel()
}

@Test @MainActor func ignoresSecondActivationWhileAlreadyActive() async throws {
  let fixture = try Fixture()

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)

  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.editor.beginCount == 0)
  await fixture.coordinator.cancel()
}

@Test @MainActor func cancelRestoresFocusedEditorAndCreatesNoHistory() async throws {
  let fixture = try Fixture()

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  fixture.standard.emitProvisional("A draft")
  await fixture.coordinator.cancel()

  #expect(fixture.editor.provisionalTexts == ["A draft"])
  #expect(fixture.editor.cancelCount == 1)
  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.standard.cancelCount == 1)
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func noSpeechDoesNotInsertOrCreateHistory() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = nil

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func nonemptyFinalCreatesPendingHistoryBeforeCleanup() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Buy tea"
  fixture.cleaner.onClean = {
    let records = try await fixture.history.list()
    #expect(records.count == 1)
    #expect(records[0].rawTranscript == "Buy tea")
    #expect(records[0].cleanupOutcome == .pending)
    #expect(records[0].insertionOutcome == .pending)
    return "Buy tea."
  }

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  let record = try #require(await fixture.history.list().first)
  #expect(record.cleanedTranscript == "Buy tea.")
  #expect(record.cleanupOutcome == .cleaned)
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func cleanupFailureUsesRawTranscript() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Do not cancel 2 meetings"
  fixture.cleaner.error = TestError.failed

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.saver.savedTexts == ["Do not cancel 2 meetings"])
  let record = try #require(await fixture.history.list().first)
  #expect(record.cleanedTranscript == nil)
  #expect(record.cleanupOutcome == .usedRaw)
}

@Test @MainActor func coordinatorObserverPublishesEveryProcessingPhaseAndCleanedSmartOutcome()
  async throws
{
  let fixture = try Fixture()
  fixture.standard.finalText = "raw"
  fixture.cleaner.result = "Clean."
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(events.map(\.phase).contains(.arming))
  #expect(events.map(\.phase).contains(.listening(mode: .smartCapture, engine: .standard)))
  #expect(events.map(\.phase).contains(.finalizing))
  #expect(events.map(\.phase).contains(.cleaning))
  #expect(events.map(\.phase).contains(.routing))
  #expect(events.last == DictationCoordinatorEvent(
    phase: .saved(fixture.inbox),
    terminal: .saved(
      mode: .smartCapture,
      cleanup: .cleaned,
      destination: fixture.inbox
    )
  ))
}

@Test @MainActor func coordinatorObserverDistinguishesFocusedRawFallbackAndFailure() async throws {
  let focused = try Fixture()
  focused.standard.finalText = "raw"
  focused.cleaner.error = TestError.failed
  var focusedEvents: [DictationCoordinatorEvent] = []
  focused.coordinator.setEventObserver { focusedEvents.append($0) }

  await focused.coordinator.start(mode: .focused, editor: focused.editor)
  await focused.coordinator.finish()

  #expect(focusedEvents.last?.terminal == .saved(
    mode: .focused,
    cleanup: .usedRaw,
    destination: nil
  ))

  let failed = try Fixture()
  failed.standard.finalText = nil
  var failedEvents: [DictationCoordinatorEvent] = []
  failed.coordinator.setEventObserver { failedEvents.append($0) }

  await failed.coordinator.start(mode: .smartCapture)
  await failed.coordinator.finish()

  #expect(failedEvents.last?.terminal == .failed("No speech detected."))
}

@Test @MainActor func coordinatorObserverDetachesAndTerminalStateAllowsShortcutConfiguration()
  async throws
{
  let fixture = try Fixture()
  fixture.standard.finalText = "Saved"
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)
  #expect(!fixture.coordinator.canConfigureShortcut)
  await fixture.coordinator.finish()
  #expect(fixture.coordinator.canConfigureShortcut)

  let count = events.count
  fixture.coordinator.setEventObserver(nil)
  await fixture.coordinator.start(mode: .smartCapture)
  #expect(events.count == count)
  await fixture.coordinator.cancel()
}

@Test @MainActor func routingFailureUsesInbox() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Put this somewhere"
  fixture.router.result = nil

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.saver.destinationIDs == [fixture.inbox.noteID])
  #expect(fixture.coordinator.phase == .saved(fixture.inbox))
}

@Test @MainActor func saveFailureIsRecordedAsUnsavedWhenHistoryIsEnabled() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Keep this"
  fixture.saver.saveError = TestError.failed

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  let record = try #require(await fixture.history.list().first)
  #expect(record.insertionOutcome == .unsaved)
  #expect(fixture.coordinator.copyableTranscript == nil)
}

@Test @MainActor func saveFailureExposesCopyOnlyInMemoryWhenHistoryIsOff() async throws {
  let fixture = try Fixture(historyEnabled: false)
  fixture.standard.finalText = "Copy this"
  fixture.saver.saveError = TestError.failed

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.coordinator.copyableTranscript == "Copy this")
  #expect(fixture.coordinator.recoveryAction == .copy)
}

@Test @MainActor func simultaneousHistoryAndDestinationFailurePreservesInMemoryCopy()
  async throws
{
  let fixture = try Fixture(historySaveError: TestError.failed)
  fixture.standard.finalText = "Recover this"
  fixture.saver.saveError = TestError.failed

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.coordinator.copyableTranscript == "Recover this")
  #expect(fixture.coordinator.recoveryAction == .copy)
  #expect(try await fixture.history.list().isEmpty)
}

@Test @MainActor func smartSuccessExposesUndoAndUnsafeUndoOpensDestination() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Saved capture"

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.coordinator.recoveryAction == .undo)
  fixture.saver.undoSucceeds = false
  let result = await fixture.coordinator.performRecoveryAction()
  #expect(result == .openDestination(fixture.inbox.noteID))
  #expect(fixture.saver.savedTexts == ["Saved capture"])
}

@Test @MainActor func smartSuccessUndoRemovesTheCaptureAndRecoveryRecord() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Undo this"

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  let result = await fixture.coordinator.performRecoveryAction()

  #expect(result == .completed)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.coordinator.recoveryAction == nil)
}

@Test @MainActor func concurrentRecoveryActivationPerformsUndoOnlyOnce() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Undo once"
  fixture.saver.undoGate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  let first = Task { await fixture.coordinator.performRecoveryAction() }
  await gate.waitUntilWaiting()
  let second = Task { await fixture.coordinator.performRecoveryAction() }
  await Task.yield()
  await gate.openGate()

  #expect(await first.value == .completed)
  #expect(await second.value == nil)
  #expect(fixture.saver.undoCount == 1)
}

@Test @MainActor func recoveryInFlightRejectsNewCaptureUntilUndoCompletes() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "First capture"
  fixture.saver.undoGate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  let receipt = try #require(fixture.coordinator.recoveryReceipt)
  let recovery = Task { await fixture.coordinator.performRecoveryAction() }
  await gate.waitUntilWaiting()

  await fixture.coordinator.start(mode: .smartCapture)
  let shortcut = fixture.coordinator.beginShortcut(editor: nil)

  #expect(shortcut == nil)
  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.coordinator.recoveryReceipt == receipt)

  await gate.openGate()
  #expect(await recovery.value == .completed)

  fixture.standard.finalText = "Second capture"
  await fixture.coordinator.start(mode: .smartCapture)

  #expect(fixture.provider.requestedKinds == [.standard, .standard])
  #expect(fixture.coordinator.phase == .listening(mode: .smartCapture, engine: .standard))
}

@Test @MainActor func armedShortcutRejectsRecoveryUntilItsSessionCompletes() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  fixture.standard.finalText = "First capture"

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  let session = try #require(fixture.coordinator.beginShortcut(editor: nil))
  await threshold.waitUntilWaiting()

  #expect(await fixture.coordinator.performRecoveryAction() == nil)
  #expect(fixture.coordinator.recoveryAction == .undo)
  #expect(fixture.saver.undoCount == 0)

  await threshold.openGate()
  #expect(await waitForListening(fixture.coordinator, timeout: .seconds(1)))
  await fixture.coordinator.cancelShortcut(session)
}

@Test @MainActor func durableUnsavedRecoveryOpensHistoryInsteadOfCopy() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "History recovery"
  fixture.saver.saveError = TestError.failed

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(fixture.coordinator.recoveryAction == .openHistory)
  #expect(fixture.coordinator.copyableTranscript == nil)
}

@Test @MainActor func focusedCaptureSavesRawThenCleansCommitsFlushesAndUpdatesHistory() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Draft"
  fixture.cleaner.result = "Clean draft"

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  fixture.standard.emitProvisional("Draft")
  await fixture.coordinator.finish()

  #expect(fixture.editor.provisionalTexts == ["Draft"])
  #expect(fixture.editor.committedTexts == ["Clean draft"])
  #expect(fixture.saver.flushCount == 1)
  let record = try #require(await fixture.history.list().first)
  #expect(record.rawTranscript == "Draft")
  #expect(record.cleanedTranscript == "Clean draft")
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func focusedToolbarCapturePersistsItsStartingDestination() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Focused"
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  await fixture.coordinator.start(
    mode: .focused,
    editor: fixture.editor,
    destination: fixture.inbox
  )
  await fixture.coordinator.finish()

  let record = try #require(await fixture.history.list().first)
  #expect(record.destination == fixture.inbox)
  #expect(record.insertionOutcome == .saved)
  #expect(events.last?.terminal == .saved(
    mode: .focused,
    cleanup: .cleaned,
    destination: fixture.inbox
  ))
}

@Test @MainActor func focusedGlobalCapturePersistsItsStartingDestination() async throws {
  let threshold = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  fixture.standard.finalText = "Focused"

  fixture.coordinator.beginShortcut(
    editor: fixture.editor,
    destination: fixture.inbox
  )
  await threshold.waitUntilWaiting()
  await threshold.openGate()
  for _ in 0..<20 {
    if case .listening = fixture.coordinator.phase { break }
    await Task.yield()
  }
  await fixture.coordinator.endShortcut()

  let record = try #require(await fixture.history.list().first)
  #expect(record.destination == fixture.inbox)
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func everyTerminalPathReleasesItsBoundEngine() async throws {
  let finish = try Fixture()
  finish.standard.finalText = "Finished"
  await finish.coordinator.start(mode: .smartCapture)
  await finish.coordinator.finish()

  let cancel = try Fixture()
  await cancel.coordinator.start(mode: .smartCapture)
  await cancel.coordinator.cancel()

  let noSpeech = try Fixture()
  await noSpeech.coordinator.start(mode: .smartCapture)
  await noSpeech.coordinator.finish()

  let failedStart = try Fixture()
  failedStart.standard.startError = TestError.failed
  await failedStart.coordinator.start(mode: .smartCapture)

  #expect(finish.standard.releaseCount == 1)
  #expect(cancel.standard.releaseCount == 1)
  #expect(noSpeech.standard.releaseCount == 1)
  #expect(failedStart.standard.releaseCount == 1)
}

@Test @MainActor func cancelDuringProviderAwaitInvalidatesLateEngineAndIgnoresSecondActivation() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.provider.gate = gate

  let start = Task { await fixture.coordinator.start(mode: .smartCapture) }
  await fixture.provider.waitUntilRequested()
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.cancel()
  await gate.openGate()
  await start.value

  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.standard.startCount == 0)
  #expect(fixture.standard.cancelCount == 1)
  #expect(fixture.standard.releaseCount == 1)
  #expect(fixture.editor.beginCount == 0)
  #expect(fixture.coordinator.phase == .idle)
}

@Test @MainActor func coordinatorWideTerminalWaitIncludesSuspendedProviderStart() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.provider.gate = gate
  let completed = CompletionProbe()

  let start = Task { await fixture.coordinator.start(mode: .smartCapture) }
  await fixture.provider.waitUntilRequested()
  await fixture.coordinator.cancel()
  let terminal = Task {
    await fixture.coordinator.waitForTerminal()
    await completed.complete()
  }
  await Task.yield()

  #expect(!(await completed.isComplete))
  await gate.openGate()
  await start.value
  await terminal.value
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func coordinatorWideTerminalWaitIncludesSuspendedEngineFinish() async throws {
  let finishGate = Gate()
  let releaseGate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Late"
  fixture.standard.finishGate = finishGate
  fixture.standard.releaseGate = releaseGate
  let completed = CompletionProbe()

  await fixture.coordinator.start(mode: .smartCapture)
  let finish = Task { await fixture.coordinator.finish() }
  await finishGate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  let terminal = Task {
    await fixture.coordinator.waitForTerminal()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await finishGate.openGate()
  await releaseGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))
  await releaseGate.openGate()
  await finish.value
  await terminal.value
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func overlappingFinishFinalizesOnce() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "One result"
  fixture.standard.finishGate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  let first = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  let second = Task { await fixture.coordinator.finish() }
  await Task.yield()
  await gate.openGate()
  await first.value
  await second.value

  #expect(fixture.standard.finishCount == 1)
  #expect(fixture.saver.savedTexts == ["One result"])
  #expect(try await fixture.history.list().count == 1)
}

@Test @MainActor func cancelDuringCleanupPreventsRoutingSavingAndHistoryUpdate() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Cancel during cleanup"
  fixture.cleaner.gate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.router.callCount == 0)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func cancelDuringRoutingPreventsSavingAndHistoryUpdate() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Cancel during routing"
  fixture.router.gate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
}

@Test @MainActor func finishFailureReleasesBoundEngineWithoutHistory() async throws {
  let fixture = try Fixture()
  fixture.standard.finishError = TestError.failed

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()

  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.standard.cancelCount == 1)
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func focusedFlushFailureRollsBackAndRecordsUnsaved() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Focused failure"
  fixture.saver.flushError = TestError.failed

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.finish()

  #expect(fixture.editor.committedTexts == ["Focused failure"])
  #expect(fixture.editor.rollbackCommittedCount == 1)
  let record = try #require(await fixture.history.list().first)
  #expect(record.insertionOutcome == .unsaved)
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func focusedCancellationDuringSuspendedFlushCompensatesCommittedReceipt()
  async throws
{
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Committed then cancelled"
  fixture.saver.flushGate = gate

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.editor.rollbackCommittedCount == 1)
  #expect(fixture.saver.compensateFocusedCount == 1)
  #expect(fixture.coordinator.phase == .idle)
}

@Test @MainActor func focusedCancellationWithSuccessfulPersistenceFailsWhenEditorRollbackDoesNotMatch()
  async throws
{
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Preserved text"
  fixture.saver.flushGate = gate
  fixture.editor.rollbackCommittedSucceeds = false

  await fixture.coordinator.start(
    mode: .focused,
    editor: fixture.editor,
    destination: fixture.inbox
  )
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(
    fixture.coordinator.phase
      == .failed("Dictation could not be cancelled safely. The text was preserved.")
  )
  #expect(fixture.coordinator.recoveryAction == .openDestination(fixture.inbox.noteID))
  #expect(fixture.saver.compensateFocusedCount == 0)
}

@Test @MainActor func focusedCancellationWithFailedPersistenceStillFailsWhenEditorRollbackDoesNotMatch()
  async throws
{
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Preserved after persistence failure"
  fixture.saver.flushGate = gate
  fixture.saver.flushError = TestError.failed
  fixture.editor.rollbackCommittedSucceeds = false

  await fixture.coordinator.start(
    mode: .focused,
    editor: fixture.editor,
    destination: fixture.inbox
  )
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(
    fixture.coordinator.phase
      == .failed("Dictation could not be cancelled safely. The text was preserved.")
  )
  #expect(fixture.coordinator.recoveryAction == .openDestination(fixture.inbox.noteID))
  #expect(fixture.saver.compensateFocusedCount == 0)
}

@Test @MainActor func focusedCancellationCompensatesRealEditorAndAppStateAcrossFlush()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("focused-compensation-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let note = Note(title: "Projects", body: "Before")
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )
  let suspendedSave = SuspendedFocusedSave(store: store)
  let appState = AppState(
    store: store,
    saveOperation: { workspace, preferences, trashedNotes in
      try await suspendedSave.save(
        workspace: workspace,
        preferences: preferences,
        trashedNotes: trashedNotes
      )
    }
  )
  for _ in 0..<100 {
    if appState.selectedNote?.id == note.id { break }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(appState.selectedNote?.id == note.id)

  let textView = NSTextView()
  textView.string = "Before"
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  let editor = EditorCommands()
  editor.textView = textView
  let bridge = FocusedEditorAppStateBridge(appState: appState)
  textView.delegate = bridge

  let provider = FakeEngineProvider()
  let engine = FakeSpeechEngine(kind: .standard)
  engine.finalText = " committed"
  provider.engines = [.standard: engine]
  let history = DictationHistoryController(
    load: { [] },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let coordinator = DictationCoordinator(
    engineProvider: provider,
    preferredEngine: { .standard },
    cleaner: FakeCleaner(),
    router: FakeRouter(),
    saver: appState,
    historyController: history,
    historyEnabled: { true }
  )

  await coordinator.start(
    mode: .focused,
    editor: editor,
    destination: .init(noteID: note.id, title: note.title)
  )
  let finishing = Task { await coordinator.finish() }
  await suspendedSave.waitUntilFirstSaveStarted()
  await coordinator.cancel()
  await suspendedSave.resumeFirstSave()
  await finishing.value

  #expect(textView.string == "Before")
  #expect(appState.selectedNote?.body == "Before")
  #expect(try await store.loadWorkspace().notes.first?.body == "Before")
  #expect(await suspendedSave.savedBodies == ["Before committed", "Before"])
}

@Test @MainActor func focusedCommitFailureRollsBackAndRecordsUnsaved() async throws {
  let fixture = try Fixture()
  fixture.standard.finalText = "Commit failure"
  fixture.editor.commitResult = false

  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.finish()

  #expect(fixture.saver.flushCount == 0)
  #expect(fixture.editor.cancelCount == 1)
  let record = try #require(await fixture.history.list().first)
  #expect(record.insertionOutcome == .unsaved)
}

@Test @MainActor func cancelDuringSaveCompensatesTheReceiptAndDeletesHistory() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Cancel during save"
  fixture.saver.saveGate = gate

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.saver.undoCount == 1)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.coordinator.phase == .idle)
}

@Test @MainActor func cancelDuringFinalSmartHistoryWriteCompensatesCommittedInsertion()
  async throws
{
  let gate = Gate()
  let fixture = try Fixture(historyFinalSaveGate: gate)
  fixture.standard.finalText = "Committed before final history"

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.saver.undoCount == 1)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().isEmpty)
  #expect(fixture.coordinator.phase == .idle)
}

@Test @MainActor func unsafeCancelDuringFinalSmartHistoryWriteOpensCommittedDestination()
  async throws
{
  let gate = Gate()
  let fixture = try Fixture(historyFinalSaveGate: gate)
  fixture.standard.finalText = "Committed and preserved"
  fixture.saver.undoSucceeds = false

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.saver.undoCount == 1)
  #expect(fixture.saver.savedTexts == ["Committed and preserved"])
  #expect(fixture.coordinator.recoveryAction == .openDestination(fixture.inbox.noteID))
  #expect(
    fixture.coordinator.phase
      == .failed("Dictation was saved but could not be undone.")
  )
}

@Test @MainActor func cancellationHistoryDeleteFailureKeepsOpenHistoryRecovery()
  async throws
{
  let cleaningGate = Gate()
  let fixture = try Fixture(historyDeleteError: TestError.failed)
  fixture.standard.finalText = "Durable transcript"
  fixture.cleaner.gate = cleaningGate

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await cleaningGate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await cleaningGate.openGate()
  await finishing.value

  #expect(try await fixture.history.list().count == 1)
  #expect(fixture.coordinator.recoveryAction == .openHistory)
  #expect(
    fixture.coordinator.phase
      == .failed("Dictation cancellation could not remove its History transcript.")
  )
}

@Test @MainActor func recoveryUndoHistoryDeleteFailureOpensHistoryInsteadOfCompleting()
  async throws
{
  let fixture = try Fixture(historyDeleteError: TestError.failed)
  fixture.standard.finalText = "Undo note but retain history"

  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  let result = await fixture.coordinator.performRecoveryAction()

  #expect(result == .openHistory)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(try await fixture.history.list().count == 1)
  #expect(fixture.coordinator.recoveryAction == .openHistory)
}

@Test @MainActor func failedUndoAfterCancelledSavePreservesHonestRecovery() async throws {
  let gate = Gate()
  let fixture = try Fixture()
  fixture.standard.finalText = "Saved but not undone"
  fixture.saver.saveGate = gate
  fixture.saver.undoSucceeds = false

  await fixture.coordinator.start(mode: .smartCapture)
  let finishing = Task { await fixture.coordinator.finish() }
  await gate.waitUntilWaiting()
  await fixture.coordinator.cancel()
  await gate.openGate()
  await finishing.value

  #expect(fixture.saver.undoCount == 1)
  #expect(fixture.saver.savedTexts == ["Saved but not undone"])
  let record = try #require(await fixture.history.list().first)
  #expect(record.insertionOutcome == .saved)
  #expect(record.destination == fixture.inbox)
  #expect(fixture.coordinator.copyableTranscript == "Saved but not undone")
  #expect(fixture.coordinator.phase == .failed("Dictation was saved but could not be undone."))
  #expect(fixture.standard.releaseCount == 1)
}

@Test @MainActor func shortcutReleaseDuringSuspendedStartDefersFinishUntilStartReturns() async throws {
  let threshold = Gate()
  let startGate = Gate()
  let saveGate = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await threshold.wait() })
  fixture.standard.startGate = startGate
  fixture.standard.finalText = "Released after start"
  fixture.saver.saveGate = saveGate

  let session = try #require(fixture.coordinator.beginShortcut(editor: nil))
  let terminal = CompletionProbe()
  let terminalWait = Task {
    await fixture.coordinator.waitForShortcutTerminal(session)
    await terminal.complete()
  }
  await threshold.waitUntilWaiting()
  await threshold.openGate()
  await startGate.waitUntilWaiting()
  await fixture.coordinator.endShortcut(session)

  #expect(fixture.standard.finishCount == 0)
  #expect(fixture.coordinator.phase == .arming)
  #expect(!(await terminal.isComplete))
  await startGate.openGate()
  await saveGate.waitUntilWaiting()

  #expect(fixture.standard.finishCount == 1)
  #expect(fixture.coordinator.phase == .routing)
  #expect(!(await terminal.isComplete))
  await saveGate.openGate()
  await terminalWait.value
  #expect(await terminal.isComplete)
}

@Test @MainActor func rejectedGlobalShortcutCannotFinishOrCancelToolbarCapture() async throws {
  let fixture = try Fixture()
  let monitor = CoordinatorModifierMonitorSpy()
  let escape = CoordinatorEscapeRegistrarSpy()
  let shortcut = GlobalHoldShortcut(
    handler: fixture.coordinator,
    monitor: monitor,
    escapeRegistrar: escape
  )
  try shortcut.configure(.rightOption)
  await fixture.coordinator.start(mode: .smartCapture)

  monitor.emit(.pressed(.rightOption))
  monitor.emit(.released(.rightOption))
  escape.emit()
  await shortcut.drainEvents()

  #expect(fixture.standard.finishCount == 0)
  #expect(fixture.standard.cancelCount == 0)
  #expect(fixture.coordinator.phase == .listening(mode: .smartCapture, engine: .standard))
  await shortcut.uninstall()
  await fixture.coordinator.cancel()
}

@Test @MainActor func handsFreeStartupOwnsEscapeBeforeProviderReturns() async throws {
  let holdGate = Gate()
  let providerGate = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await holdGate.wait() })
  fixture.provider.gate = providerGate
  let monitor = CoordinatorModifierMonitorSpy()
  let escape = CoordinatorEscapeRegistrarSpy()
  let shortcut = GlobalHoldShortcut(
    handler: fixture.coordinator,
    monitor: monitor,
    escapeRegistrar: escape
  )
  try shortcut.configure(.rightOption)

  monitor.emit(.pressed(.rightOption))
  monitor.emit(.released(.rightOption))
  await shortcut.drainEvents()
  monitor.emit(.pressed(.rightOption))
  await fixture.provider.waitUntilRequested()

  #expect(escape.registerCount == 2)
  escape.emit()
  let drained = CompletionProbe()
  let drain = Task {
    await shortcut.drainEvents()
    await drained.complete()
  }
  #expect(await waitForCompletion(drained, timeout: .seconds(1)))

  await providerGate.openGate()
  await drain.value
  await shortcut.waitForTerminalObservation()
  #expect(fixture.coordinator.phase == .idle)
  #expect(fixture.standard.startCount == 0)
  await holdGate.openGate()
  await shortcut.uninstall()
}

@Test @MainActor func handsFreeStartupMonitorLossCancelsBeforeProviderReturns()
  async throws
{
  let holdGate = Gate()
  let providerGate = Gate()
  let fixture = try Fixture(holdSleeper: { _ in await holdGate.wait() })
  fixture.provider.gate = providerGate
  let monitor = CoordinatorModifierMonitorSpy()
  let escape = CoordinatorEscapeRegistrarSpy()
  let shortcut = GlobalHoldShortcut(
    handler: fixture.coordinator,
    monitor: monitor,
    escapeRegistrar: escape
  )
  try shortcut.configure(.rightOption)

  monitor.emit(.pressed(.rightOption))
  monitor.emit(.released(.rightOption))
  await shortcut.drainEvents()
  monitor.emit(.pressed(.rightOption))
  await fixture.provider.waitUntilRequested()

  monitor.publish(.failed)
  let drained = CompletionProbe()
  let drain = Task {
    await shortcut.drainEvents()
    await drained.complete()
  }
  #expect(await waitForCompletion(drained, timeout: .seconds(1)))

  await providerGate.openGate()
  await drain.value
  await shortcut.waitForTerminalObservation()
  #expect(fixture.coordinator.phase == .idle)
  #expect(fixture.standard.startCount == 0)
  await holdGate.openGate()
  await shortcut.uninstall()
}

@Test @MainActor func captureReservationSurvivesDelayedResourceRelease() async throws {
  let releaseGate = Gate()
  let fixture = try Fixture()
  fixture.standard.releaseGate = releaseGate

  await fixture.coordinator.start(mode: .smartCapture)
  let cancelling = Task { await fixture.coordinator.cancel() }
  await releaseGate.waitUntilWaiting()
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)

  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.coordinator.phase == .listening(mode: .smartCapture, engine: .standard))
  await releaseGate.openGate()
  await cancelling.value

  #expect(fixture.coordinator.phase == .idle)
  await fixture.coordinator.start(mode: .smartCapture)
  #expect(fixture.provider.requestedKinds == [.standard, .standard])
  await fixture.coordinator.cancel()
}

@Test @MainActor func cancelDuringSynchronousAppleSpeechStartPreventsListeningAndOverlap()
  async throws
{
  let observation = CoordinatorBlockingStartObservation()
  let session = CoordinatorBlockingAppleSpeechSession(observation: observation)
  let engine = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { session }
  )
  let fixture = try Fixture()
  fixture.provider.engines[.standard] = engine
  var events: [DictationCoordinatorEvent] = []
  fixture.coordinator.setEventObserver { events.append($0) }

  let start = Task { @MainActor in
    await fixture.coordinator.start(mode: .smartCapture)
  }
  let watchdog = Task.detached {
    guard observation.waitUntilStart(timeout: .now() + 1) else {
      observation.releaseStart()
      return false
    }
    let cancellation = Task {
      await fixture.coordinator.cancel()
      await fixture.coordinator.start(mode: .smartCapture)
      observation.recordCancellationAccepted()
    }
    observation.waitForCancellationWindow()
    observation.releaseStart()
    await cancellation.value
    return true
  }

  await start.value
  #expect(await watchdog.value)
  await fixture.coordinator.waitForTerminal()

  #expect(observation.cancellationWasAcceptedBeforeRelease)
  #expect(!events.contains { if case .listening = $0.phase { true } else { false } })
  #expect(await session.cancelCount == 1)
  #expect(await session.releaseCount == 1)
  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.coordinator.phase == .idle)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor func EnhancedSpeechRejectsAnUnverifiedModelWithoutStartingAudio() async {
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [0.25])
  var standardRecommendations = 0
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: { .unavailable },
    makeInference: { inference },
    makeAudio: { _ in audio },
    recommendStandard: { standardRecommendations += 1 }
  )

  await #expect(throws: DictationFailure.unavailable) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(inference.loadURLs.isEmpty)
  #expect(inference.releaseCount == 1)
  #expect(audio.startCount == 0)
  #expect(standardRecommendations == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechUsesMicrophoneOnlyPermissionAndSavedDeviceSelection()
  async throws
{
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [])
  var requestedEngine: DictationSpeechEngine?
  var selection: MicrophoneSelection?
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    requestPermission: { engine in
      requestedEngine = engine
      return .granted
    },
    microphoneUID: "usb-microphone",
    microphoneSelectionChanged: { selection = $0 },
    makeInference: { inference },
    makeAudio: { _ in audio }
  )

  try await capture.start(provisional: { _ in }, level: { _ in })

  #expect(requestedEngine == .enhancedLocal)
  #expect(audio.selectedMicrophoneUID == "usb-microphone")
  #expect(selection == .selected(uid: "usb-microphone"))
  await capture.cancel()
}

@Test @MainActor func EnhancedSpeechCapturesMemoryOnly16kMonoFloatSamplesAndReturnsFinalText() async throws {
  let repository = URL(fileURLWithPath: "/verified/parakeet-tdt-0.6b-v2-coreml")
  let inference = EnhancedInferenceSpy()
  inference.result = "  Meet at 3 PM.  "
  let audio = EnhancedAudioSpy(samples: [0.25, -0.5, 0.75], emittedLevel: 0.5)
  var configuration: EnhancedAudioConfiguration?
  var provisional: [String] = []
  var levels: [Float] = []
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: { .ready(repositoryURL: repository) },
    makeInference: { inference },
    makeAudio: {
      configuration = $0
      return audio
    }
  )

  try await capture.start(
    provisional: { provisional.append($0) },
    level: { levels.append($0) }
  )
  let result = try await capture.finish()

  #expect(configuration == .inference)
  #expect(inference.loadURLs == [repository])
  #expect(inference.transcribedSamples == [[0.25, -0.5, 0.75]])
  #expect(result == "Meet at 3 PM.")
  #expect(provisional.isEmpty)
  #expect(levels == [0.5])
  #expect(audio.releaseCount == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
  #expect(EnhancedSpeechCapture.isFluidAudioOffline)
}

@Test @MainActor func EnhancedSpeechTreatsWhitespaceOnlyInferenceAsNoSpeech() async throws {
  let inference = EnhancedInferenceSpy()
  inference.result = " \n "
  let audio = EnhancedAudioSpy(samples: [0.1])
  let capture = makeEnhancedCapture(inference: inference, audio: audio)

  try await capture.start(provisional: { _ in }, level: { _ in })

  #expect(try await capture.finish() == nil)
  #expect(audio.releaseCount == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechReleasesEverythingAfterInferenceFailure() async throws {
  let inference = EnhancedInferenceSpy()
  inference.transcriptionError = EnhancedTestFailure.failed
  let audio = EnhancedAudioSpy(samples: [0.1])
  let capture = makeEnhancedCapture(inference: inference, audio: audio)

  try await capture.start(provisional: { _ in }, level: { _ in })
  await #expect(throws: EnhancedTestFailure.failed) {
    try await capture.finish()
  }

  #expect(audio.releaseCount == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechMarksRepairAndRecommendsStandardAfterLoadFailure() async {
  let inference = EnhancedInferenceSpy()
  inference.loadError = EnhancedTestFailure.failed
  let audio = EnhancedAudioSpy(samples: [])
  var repairMessages: [String] = []
  var standardRecommendations = 0
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { inference },
    makeAudio: { _ in audio },
    markRepairRequired: { message, _ in repairMessages.append(message) },
    recommendStandard: { standardRecommendations += 1 }
  )

  await #expect(throws: EnhancedTestFailure.failed) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(repairMessages.count == 1)
  #expect(standardRecommendations == 1)
  #expect(inference.releaseCount == 1)
  #expect(audio.startCount == 0)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechRecommendsStandardAfterVerifiedRepositoryChangesDuringLoad() async {
  let repository = URL(fileURLWithPath: "/verified/parakeet")
  var state: EnhancedModelVerifiedLoadState = .ready(repositoryURL: repository)
  let inference = EnhancedInferenceSpy()
  inference.onLoad = {
    state = .ready(repositoryURL: URL(fileURLWithPath: "/verified/new-parakeet"))
  }
  let audio = EnhancedAudioSpy(samples: [])
  var standardRecommendations = 0
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: { state },
    makeInference: { inference },
    makeAudio: { _ in audio },
    recommendStandard: { standardRecommendations += 1 }
  )

  await #expect(throws: DictationFailure.unavailable) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(standardRecommendations == 1)
  #expect(inference.releaseCount == 1)
  #expect(audio.startCount == 0)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechRecommendsStandardAfterAudioConstructionFailure() async {
  let inference = EnhancedInferenceSpy()
  var standardRecommendations = 0
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { inference },
    makeAudio: { _ in throw EnhancedTestFailure.failed },
    recommendStandard: { standardRecommendations += 1 }
  )

  await #expect(throws: EnhancedTestFailure.failed) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(standardRecommendations == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechRecommendsStandardAfterAudioStartFailure() async {
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [], startError: EnhancedTestFailure.failed)
  var standardRecommendations = 0
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { inference },
    makeAudio: { _ in audio },
    recommendStandard: { standardRecommendations += 1 }
  )

  await #expect(throws: EnhancedTestFailure.failed) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(standardRecommendations == 1)
  #expect(audio.cancelCount == 1)
  #expect(audio.releaseCount == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechDoesNotRecommendStandardAfterCancelledAudioStart() async {
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [], startError: CancellationError())
  var standardRecommendations = 0
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { inference },
    makeAudio: { _ in audio },
    recommendStandard: { standardRecommendations += 1 }
  )

  await #expect(throws: CancellationError.self) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(standardRecommendations == 0)
  #expect(audio.releaseCount == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechCancellationDropsSamplesAndReleasesEverything() async throws {
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [0.4, -0.2])
  let capture = makeEnhancedCapture(inference: inference, audio: audio)

  try await capture.start(provisional: { _ in }, level: { _ in })
  await capture.cancel()

  #expect(audio.cancelCount == 1)
  #expect(audio.releaseCount == 1)
  #expect(inference.cancelCount == 1)
  #expect(inference.transcribedSamples.isEmpty)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechCancellationDuringLoadReleasesInferenceExactlyOnce() async {
  let loadGate = Gate()
  let lifetime = EnhancedLifetimeTracker()
  var inference: EnhancedInferenceSpy? = EnhancedInferenceSpy(lifetime: lifetime)
  inference?.loadGate = loadGate
  weak let weakInference = inference
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { [weak inference] in inference! },
    makeAudio: { _ in EnhancedAudioSpy(samples: []) }
  )
  let start = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await loadGate.waitUntilWaiting()
  inference = nil

  await capture.cancel()
  await #expect(throws: CancellationError.self) {
    try await start.value
  }

  #expect(lifetime.cancelCount == 1)
  #expect(lifetime.releaseCount == 1)
  #expect(lifetime.deinitCount == 1)
  #expect(weakInference == nil)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechCancellationCleansResourcesReturnedByLateFluidLoad() async {
  let lifetime = EnhancedLifetimeTracker()
  var loadedResources: FluidEnhancedSpeechResourcesSpy? = .init(lifetime: lifetime)
  weak let weakLoadedResources = loadedResources
  let loader = LateFluidResourcesLoader(resources: loadedResources!)
  loadedResources = nil
  let inference = FluidEnhancedSpeechInference(loadResources: { _ in
    await loader.loadIgnoringCancellation()
  })
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { inference },
    makeAudio: { _ in EnhancedAudioSpy(samples: []) }
  )
  let start = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await loader.waitUntilWaiting()

  await inference.cancel()
  let cancellation = Task {
    await capture.cancel()
  }
  await loader.release()
  await cancellation.value
  await #expect(throws: CancellationError.self) {
    try await start.value
  }

  #expect(lifetime.cancelCount == 0)
  #expect(lifetime.releaseCount == 1)
  #expect(lifetime.deinitCount == 1)
  #expect(weakLoadedResources == nil)
  #expect(!inference.hasLoadedResources)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechCancellationDuringTranscriptionHasNoStaleFinish() async throws {
  let transcriptionGate = Gate()
  let inferenceLifetime = EnhancedLifetimeTracker()
  let audioLifetime = EnhancedLifetimeTracker()
  var inference: EnhancedInferenceSpy? = EnhancedInferenceSpy(lifetime: inferenceLifetime)
  inference?.transcriptionGate = transcriptionGate
  inference?.ignoresCancellation = true
  var audio: EnhancedAudioSpy? = EnhancedAudioSpy(
    samples: [0.4],
    lifetime: audioLifetime
  )
  weak let weakInference = inference
  weak let weakAudio = audio
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { [weak inference] in inference! },
    makeAudio: { [weak audio] _ in audio! }
  )
  try await capture.start(provisional: { _ in }, level: { _ in })
  let finish = Task {
    try await capture.finish()
  }
  await transcriptionGate.waitUntilWaiting()
  inference = nil
  audio = nil

  await capture.cancel()
  await #expect(throws: CancellationError.self) {
    try await finish.value
  }

  #expect(inferenceLifetime.cancelCount == 1)
  #expect(inferenceLifetime.releaseCount == 1)
  #expect(inferenceLifetime.deinitCount == 1)
  #expect(audioLifetime.releaseCount == 1)
  #expect(audioLifetime.deinitCount == 1)
  #expect(weakInference == nil)
  #expect(weakAudio == nil)
  #expect(!capture.hasActiveResources)
}

@Test @MainActor func EnhancedSpeechReleaseResourcesIsTerminalAndIdempotent() async throws {
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [0.2])
  let capture = makeEnhancedCapture(inference: inference, audio: audio)

  try await capture.start(provisional: { _ in }, level: { _ in })
  await capture.releaseResources()
  await capture.releaseResources()

  #expect(audio.releaseCount == 1)
  #expect(inference.releaseCount == 1)
  #expect(!capture.hasActiveResources)
}

@Test func EnhancedSpeechSequentialConversionDrainsTheFinalResamplerFrames() throws {
  let inputFormat = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 48_000,
      channels: 1,
      interleaved: false
    )
  )
  let outputFormat = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    )
  )
  let converter = try EnhancedAudioStreamConverter(
    inputFormat: inputFormat,
    outputFormat: outputFormat,
    level: { _ in }
  )

  try converter.append(enhancedAudioBuffer(
    format: inputFormat,
    frameCount: 2_400,
    value: 0.25
  ))
  try converter.append(enhancedAudioBuffer(
    format: inputFormat,
    frameCount: 2_400,
    value: 0.5
  ))
  let samples = try converter.finishAndTakeSamples()

  #expect(samples.count == 1_600)
  #expect(abs((samples.last ?? 0) - 0.5) < 0.05)
}

@MainActor
private func makeEnhancedCapture(
  inference: EnhancedInferenceSpy,
  audio: EnhancedAudioSpy
) -> EnhancedSpeechCapture {
  EnhancedSpeechCapture(
    verifiedLoadState: {
      .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
    },
    makeInference: { inference },
    makeAudio: { _ in audio }
  )
}
#endif

@MainActor
private final class Fixture {
  private let preference: PreferenceBox
  var preferred: DictationSpeechEngine {
    get { preference.value }
    set { preference.value = newValue }
  }
  let standard = FakeSpeechEngine(kind: .standard)
  let enhanced = FakeSpeechEngine(kind: .enhancedLocal)
  let provider: FakeEngineProvider
  let cleaner = FakeCleaner()
  let router = FakeRouter()
  let saver: FakeSaver
  let editor = FakeEditor()
  let history: DictationHistoryStore
  let inbox = DictationDestination(noteID: UUID(), title: "Inbox")
  let coordinator: DictationCoordinator

  init(
    processing: (any DictationProcessing)? = nil,
    onFocusedEditorRollback: (() -> Void)? = nil,
    onFocusedProvisionalUpdate: (() -> Void)? = nil,
    preferred: DictationSpeechEngine = .standard,
    historyEnabled: Bool = true,
    historySaveError: Error? = nil,
    historyFinalSaveGate: Gate? = nil,
    historyDeleteError: Error? = nil,
    holdSleeper: @escaping @Sendable (Duration) async -> Void = { _ in }
  ) throws {
    preference = PreferenceBox(value: preferred)
    provider = FakeEngineProvider()
    saver = FakeSaver()
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    history = DictationHistoryStore(rootURL: root)
    let historyController = DictationHistoryController(
      load: { [history] in try await history.list() },
      save: { [history] record in
        if record.insertionOutcome == .saved, let historyFinalSaveGate {
          await historyFinalSaveGate.wait()
        }
        if let historySaveError { throw historySaveError }
        try await history.save(record)
      },
      delete: { [history] id in
        if let historyDeleteError { throw historyDeleteError }
        try await history.delete(id: id)
      },
      clear: { [history] in try await history.clear() }
    )
    saver.destinations = [inbox]
    editor.onCancelFocusedDictation = onFocusedEditorRollback
    editor.onFocusedProvisionalUpdate = onFocusedProvisionalUpdate
    provider.engines = [.standard: standard, .enhancedLocal: enhanced]
    coordinator = DictationCoordinator(
      engineProvider: provider,
      preferredEngine: { [preference] in preference.value },
      cleaner: cleaner,
      router: router,
      saver: saver,
      historyController: historyController,
      historyEnabled: { historyEnabled },
      processing: processing,
      holdSleeper: holdSleeper
    )
  }
}

@MainActor
private final class CoordinatorModifierMonitorSpy: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  var accessGranted = true

  func start() throws {
    stateHandler?(.running)
  }

  func stop() {
    stateHandler?(.stopped)
  }

  func requestAccess() -> Bool {
    accessGranted
  }

  func emit(_ transition: ModifierKeyTransition) {
    transitionHandler?(transition)
  }

  func publish(_ state: ModifierMonitorState) {
    stateHandler?(state)
  }
}

@MainActor
private final class CoordinatorEscapeRegistrarSpy: EscapeHotKeyRegistering {
  var eventHandler: (() -> Void)?
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  func register() throws {
    registerCount += 1
  }

  func unregister() {
    unregisterCount += 1
  }

  func emit() {
    eventHandler?()
  }
}

@MainActor
private final class FakeSpeechEngine: SpeechEngine {
  let kind: DictationSpeechEngine
  var startError: Error?
  var finishError: Error?
  var onStart: (() -> Void)?
  var finalText: String?
  var startGate: Gate?
  var finishGate: Gate?
  var releaseGate: Gate?
  private var provisional: (@MainActor (String) -> Void)?
  private var level: (@MainActor (Float) -> Void)?
  var startCount = 0
  var finishCount = 0
  var cancelCount = 0
  var releaseCount = 0

  init(kind: DictationSpeechEngine) { self.kind = kind }

  func start(provisional: @escaping @MainActor (String) -> Void, level: @escaping @MainActor (Float) -> Void) async throws {
    startCount += 1
    onStart?()
    if let startGate { await startGate.wait() }
    if let startError { throw startError }
    self.provisional = provisional
    self.level = level
  }

  func finish() async throws -> String? {
    finishCount += 1
    if let finishGate { await finishGate.wait() }
    if let finishError { throw finishError }
    return finalText
  }

  func cancel() async { cancelCount += 1 }
  func releaseResources() async {
    releaseCount += 1
    if let releaseGate { await releaseGate.wait() }
  }
  func emitProvisional(_ text: String) { provisional?(text) }
  func emitLevel(_ value: Float) { level?(value) }
}

@MainActor
private final class FakeEngineProvider: SpeechEngineProviding {
  var engines: [DictationSpeechEngine: any SpeechEngine] = [:]
  var requestedKinds: [DictationSpeechEngine] = []
  var gate: Gate?
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []

  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
    requestedKinds.append(preferred)
    let waiters = requestWaiters
    requestWaiters = []
    waiters.forEach { $0.resume() }
    if let gate { await gate.wait() }
    guard let engine = engines[preferred] else { throw TestError.failed }
    return engine
  }

  func waitUntilRequested() async {
    guard requestedKinds.isEmpty else { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }
}

private final class CoordinatorBlockingStartObservation: @unchecked Sendable {
  private let condition = NSCondition()
  private let startGate = DispatchSemaphore(value: 0)
  private var didStart = false
  private var didReleaseStart = false
  private var _cancellationWasAcceptedBeforeRelease = false

  var cancellationWasAcceptedBeforeRelease: Bool {
    condition.withLock { _cancellationWasAcceptedBeforeRelease }
  }

  func blockStart() {
    condition.withLock {
      didStart = true
      condition.broadcast()
    }
    startGate.wait()
  }

  func waitUntilStart(timeout: DispatchTime) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    while !didStart {
      _ = condition.wait(until: Date(timeIntervalSinceNow: 0.01))
      if DispatchTime.now() >= timeout { return false }
    }
    return true
  }

  func waitForCancellationWindow() {
    condition.lock()
    _ = condition.wait(until: Date(timeIntervalSinceNow: 0.1))
    condition.unlock()
  }

  func recordCancellationAccepted() {
    condition.withLock {
      _cancellationWasAcceptedBeforeRelease = !didReleaseStart
    }
  }

  func releaseStart() {
    let shouldSignal = condition.withLock {
      guard !didReleaseStart else { return false }
      didReleaseStart = true
      return true
    }
    if shouldSignal { startGate.signal() }
  }
}

private actor CoordinatorBlockingAppleSpeechSession: AppleSpeechSession {
  nonisolated let supportsOnDeviceRecognition = true
  private let observation: CoordinatorBlockingStartObservation
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0

  init(observation: CoordinatorBlockingStartObservation) {
    self.observation = observation
  }

  func start(
    provisional _: @escaping @MainActor @Sendable (String) -> Void,
    level _: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    observation.blockStart()
  }

  func finish() async throws -> String? { "late result" }
  func cancel() async { cancelCount += 1 }
  func releaseResources() async { releaseCount += 1 }
}

@MainActor
final class ProcessingProbe: DictationProcessing {
  private let updates: [DictationTextUpdate]
  private(set) var result: DictationProcessingResult
  private let finishBlocksUntilCancel: Bool
  private let synchronousLevel: Float?
  private let drainGate: Gate?
  private let onFinishStarted: (() -> Void)?
  private let onSessionCancel: (() -> Void)?
  private let onSourceCancel: (() -> Void)?
  private let onSourcePhysicalRelease: (() -> Void)?
  private let onFinishUnblocked: (() -> Void)?
  private let onSessionDrain: (() -> Void)?
  private var session: ProcessingSessionProbe?
  private var levelCallback: (@MainActor @Sendable (Float) -> Void)?
  private var finishStarted = false
  private var finishWaiters: [CheckedContinuation<Void, Never>] = []

  private(set) var publishedUpdates: [DictationTextUpdate] = []
  private(set) var beginCount = 0

  init(
    updates: [DictationTextUpdate] = [],
    result: DictationProcessingResult = .init(
      rawTranscript: "",
      dictionaryBaseline: "",
      cleanedTranscript: nil,
      insertedText: "",
      cleanupOutcome: .usedRaw,
      measurements: .empty
    ),
    finishBlocksUntilCancel: Bool = false,
    synchronousLevel: Float? = nil,
    drainGate: Gate? = nil,
    onFinishStarted: (() -> Void)? = nil,
    onSessionCancel: (() -> Void)? = nil,
    onSourceCancel: (() -> Void)? = nil,
    onSourcePhysicalRelease: (() -> Void)? = nil,
    onFinishUnblocked: (() -> Void)? = nil,
    onSessionDrain: (() -> Void)? = nil
  ) {
    self.updates = updates
    self.result = result
    self.finishBlocksUntilCancel = finishBlocksUntilCancel
    self.synchronousLevel = synchronousLevel
    self.drainGate = drainGate
    self.onFinishStarted = onFinishStarted
    self.onSessionCancel = onSessionCancel
    self.onSourceCancel = onSourceCancel
    self.onSourcePhysicalRelease = onSourcePhysicalRelease
    self.onFinishUnblocked = onFinishUnblocked
    self.onSessionDrain = onSessionDrain
  }

  func prepare(for intent: DictationPreparationIntent) async {
    _ = intent
  }

  func begin(
    configuration: DictationProcessingConfiguration,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws -> any DictationProcessingSession {
    _ = configuration
    levelCallback = level
    if let synchronousLevel { level(synchronousLevel) }
    beginCount += 1
    let session = ProcessingSessionProbe(
      result: result,
      finishBlocksUntilCancel: finishBlocksUntilCancel,
      drainGate: drainGate,
      onFinishStarted: { [weak self] in self?.markFinishStarted() },
      onSessionCancel: onSessionCancel,
      onSourceCancel: onSourceCancel,
      onSourcePhysicalRelease: onSourcePhysicalRelease,
      onFinishUnblocked: onFinishUnblocked,
      onSessionDrain: onSessionDrain,
      onPublishedUpdate: { [weak self] update in
        self?.publishedUpdates.append(update)
      }
    )
    self.session = session
    return session
  }

  func handle(_ signal: DictationRuntimeSignal) async {
    _ = signal
  }

  func emit(_ update: DictationTextUpdate) async {
    session?.emit(update)
    await Task.yield()
  }

  func emitAll() async {
    for update in updates {
      await emit(update)
    }
  }

  func emitLevel(_ value: Float) {
    levelCallback?(value)
  }

  func complete(with result: DictationProcessingResult) {
    self.result = result
    session?.setResult(result)
  }

  func waitUntilFinishStarted() async {
    guard !finishStarted else { return }
    await withCheckedContinuation { continuation in
      finishWaiters.append(continuation)
    }
  }

  private func markFinishStarted() {
    finishStarted = true
    let waiters = finishWaiters
    finishWaiters.removeAll()
    waiters.forEach { $0.resume() }
    onFinishStarted?()
  }
}

@MainActor
private final class ProcessingSessionProbe: DictationProcessingSession {
  let updates: AsyncThrowingStream<DictationTextUpdate, Error>

  private let continuation: AsyncThrowingStream<DictationTextUpdate, Error>.Continuation
  private let finishBlocksUntilCancel: Bool
  private let drainGate: Gate?
  private let onFinishStarted: () -> Void
  private let onSessionCancel: (() -> Void)?
  private let onSourceCancel: (() -> Void)?
  private let onSourcePhysicalRelease: (() -> Void)?
  private let onFinishUnblocked: (() -> Void)?
  private let onSessionDrain: (() -> Void)?
  private let onPublishedUpdate: (DictationTextUpdate) -> Void
  private var result: DictationProcessingResult
  private var finishContinuation: CheckedContinuation<DictationProcessingResult, Never>?
  private var isCancelled = false

  init(
    result: DictationProcessingResult,
    finishBlocksUntilCancel: Bool,
    drainGate: Gate?,
    onFinishStarted: @escaping () -> Void,
    onSessionCancel: (() -> Void)?,
    onSourceCancel: (() -> Void)?,
    onSourcePhysicalRelease: (() -> Void)?,
    onFinishUnblocked: (() -> Void)?,
    onSessionDrain: (() -> Void)?,
    onPublishedUpdate: @escaping (DictationTextUpdate) -> Void
  ) {
    self.finishBlocksUntilCancel = finishBlocksUntilCancel
    self.drainGate = drainGate
    self.onFinishStarted = onFinishStarted
    self.onSessionCancel = onSessionCancel
    self.onSourceCancel = onSourceCancel
    self.onSourcePhysicalRelease = onSourcePhysicalRelease
    self.onFinishUnblocked = onFinishUnblocked
    self.onSessionDrain = onSessionDrain
    self.onPublishedUpdate = onPublishedUpdate
    self.result = result
    var capturedContinuation: AsyncThrowingStream<DictationTextUpdate, Error>.Continuation!
    updates = AsyncThrowingStream { capturedContinuation = $0 }
    continuation = capturedContinuation
  }

  func finish() async throws -> DictationProcessingResult {
    onFinishStarted()
    if finishBlocksUntilCancel, !isCancelled {
      return await withCheckedContinuation { continuation in
        finishContinuation = continuation
      }
    }
    continuation.finish()
    return result
  }

  func cancel() async {
    guard !isCancelled else { return }
    isCancelled = true
    onSessionCancel?()
    continuation.finish()
    onSourceCancel?()
    onSourcePhysicalRelease?()
    if let finishContinuation {
      self.finishContinuation = nil
      finishContinuation.resume(returning: result)
      onFinishUnblocked?()
    }
    await drainGate?.wait()
    if let onSessionDrain {
      await Task.yield()
      onSessionDrain()
    }
  }

  func emit(_ update: DictationTextUpdate) {
    if case .enqueued = continuation.yield(update) {
      onPublishedUpdate(update)
    }
  }

  func setResult(_ result: DictationProcessingResult) {
    self.result = result
  }
}

private final class FakeCleaner: TranscriptCleaning, @unchecked Sendable {
  var result: String?
  var error: Error?
  var onClean: (() async throws -> String)?
  var gate: Gate?
  private(set) var calls = 0

  func clean(_ rawTranscript: String) async throws -> String {
    calls += 1
    if let gate { await gate.wait() }
    if let onClean { return try await onClean() }
    if let error { throw error }
    return result ?? rawTranscript
  }
}

private final class FakeRouter: DestinationRouting, @unchecked Sendable {
  var result: UUID?
  var gate: Gate?
  private(set) var callCount = 0

  func route(transcript: String, candidates: [DictationDestination], inboxID: UUID?) async -> UUID? {
    callCount += 1
    if let gate { await gate.wait() }
    return result
  }
}

@MainActor
private final class FakeSaver: DictationSaving {
  var destinations: [DictationDestination] = []
  var saveError: Error?
  var saveGate: Gate?
  var flushGate: Gate?
  var flushError: Error?
  var savedTexts: [String] = []
  var destinationIDs: [UUID?] = []
  var flushCount = 0
  var undoCount = 0
  var compensateFocusedCount = 0
  var undoSucceeds = true
  var undoGate: Gate?

  func activeDestinations() -> [DictationDestination] { destinations }

  func saveSmartCapture(text: String, captureID: UUID, destinationID: UUID?) async throws -> DictationInsertionReceipt {
    if let saveGate { await saveGate.wait() }
    savedTexts.append(text)
    destinationIDs.append(destinationID)
    if let saveError { throw saveError }
    let noteID = destinationID ?? UUID()
    return DictationInsertionReceipt(captureID: captureID, noteID: noteID, insertedSuffix: text)
  }

  func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool {
    undoCount += 1
    if let undoGate { await undoGate.wait() }
    if undoSucceeds, !savedTexts.isEmpty { savedTexts.removeLast() }
    return undoSucceeds
  }
  func flushFocusedDictationSave(
    captureID: UUID
  ) async throws -> FocusedDictationPersistenceReceipt {
    flushCount += 1
    if let flushGate { await flushGate.wait() }
    if let flushError { throw flushError }
    return FocusedDictationPersistenceReceipt(captureID: captureID)
  }

  func compensateFocusedDictationSave(
    _ receipt: FocusedDictationPersistenceReceipt
  ) async -> Bool {
    compensateFocusedCount += 1
    return true
  }
}

@MainActor
private final class FakeEditor: FocusedDictationEditing {
  var canBeginFocusedDictation = true
  var beginCount = 0
  var provisionalTexts: [String] = []
  var committedTexts: [String] = []
  var cancelCount = 0
  var commitResult = true
  var rollbackCommittedCount = 0
  var rollbackCommittedSucceeds = true
  var onCancelFocusedDictation: (() -> Void)?
  var onFocusedProvisionalUpdate: (() -> Void)?

  func beginFocusedDictation() -> Bool {
    beginCount += 1
    return canBeginFocusedDictation
  }

  func updateFocusedDictation(provisionalText: String) {
    provisionalTexts.append(provisionalText)
    onFocusedProvisionalUpdate?()
  }
  func commitFocusedDictation(text: String) -> FocusedDictationCommitReceipt? {
    committedTexts.append(text)
    return commitResult ? FocusedDictationCommitReceipt() : nil
  }
  func cancelFocusedDictation() {
    cancelCount += 1
    onCancelFocusedDictation?()
  }
  func rollbackCommittedFocusedDictation(
    _ receipt: FocusedDictationCommitReceipt
  ) -> Bool {
    rollbackCommittedCount += 1
    return rollbackCommittedSucceeds
  }
  func finalizeCommittedFocusedDictation(
    _ receipt: FocusedDictationCommitReceipt
  ) {}
}

private enum TestError: Error { case failed }

@MainActor
private final class FocusedEditorAppStateBridge: NSObject, NSTextViewDelegate {
  private weak var appState: AppState?

  init(appState: AppState) {
    self.appState = appState
  }

  func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }
    appState?.updateSelected(body: textView.string)
  }
}

private actor SuspendedFocusedSave {
  private let store: LocalStore
  private var saveCount = 0
  private var firstSaveStarted = false
  private var firstSaveStartedWaiter: CheckedContinuation<Void, Never>?
  private var firstSaveWaiter: CheckedContinuation<Void, Never>?
  private(set) var savedBodies: [String] = []

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
      firstSaveStartedWaiter?.resume()
      firstSaveStartedWaiter = nil
      await withCheckedContinuation { firstSaveWaiter = $0 }
    }
    savedBodies.append(workspace.notes.first?.body ?? "")
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: trashedNotes
    )
  }

  func waitUntilFirstSaveStarted() async {
    guard !firstSaveStarted else { return }
    await withCheckedContinuation { firstSaveStartedWaiter = $0 }
  }

  func resumeFirstSave() {
    firstSaveWaiter?.resume()
    firstSaveWaiter = nil
  }
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
enum EnhancedTestFailure: Error {
  case failed
}

@MainActor
final class EnhancedInferenceSpy: EnhancedSpeechInferring {
  var result = "Transcript"
  var loadError: Error?
  var transcriptionError: Error?
  var loadGate: Gate?
  var transcriptionGate: Gate?
  var onLoad: (() -> Void)?
  var ignoresCancellation = false
  private let lifetime: EnhancedLifetimeTracker?
  private var isCancelled = false
  private(set) var loadURLs: [URL] = []
  private(set) var transcribedSamples: [[Float]] = []
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0

  init(lifetime: EnhancedLifetimeTracker? = nil) {
    self.lifetime = lifetime
  }

  func load(from repositoryURL: URL) async throws {
    loadURLs.append(repositoryURL)
    if let loadGate { await loadGate.wait() }
    if isCancelled { throw CancellationError() }
    if let loadError { throw loadError }
    onLoad?()
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    transcribedSamples.append(samples)
    if let transcriptionGate { await transcriptionGate.wait() }
    if isCancelled, !ignoresCancellation { throw CancellationError() }
    if let transcriptionError { throw transcriptionError }
    return result
  }

  func cancel() async {
    cancelCount += 1
    lifetime?.recordCancel()
    isCancelled = true
    await loadGate?.openGate()
    await transcriptionGate?.openGate()
  }

  func releaseResources() async {
    releaseCount += 1
    lifetime?.recordRelease()
  }

  deinit {
    lifetime?.recordDeinit()
  }
}

@MainActor
final class EnhancedAudioSpy: EnhancedAudioCapturing {
  let samples: [Float]
  let emittedLevel: Float?
  let startError: Error?
  private let lifetime: EnhancedLifetimeTracker?
  private(set) var startCount = 0
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0
  private(set) var selectedMicrophoneUID: String?

  init(
    samples: [Float],
    emittedLevel: Float? = nil,
    startError: Error? = nil,
    lifetime: EnhancedLifetimeTracker? = nil
  ) {
    self.samples = samples
    self.emittedLevel = emittedLevel
    self.startError = startError
    self.lifetime = lifetime
  }

  func selectMicrophone(savedUID: String?) -> MicrophoneSelection {
    selectedMicrophoneUID = savedUID
    return savedUID.map { .selected(uid: $0) } ?? .automatic
  }

  func start(level: @escaping @MainActor (Float) -> Void) throws {
    startCount += 1
    if let startError { throw startError }
    if let emittedLevel { level(emittedLevel) }
  }

  func stopAndTakeSamples() -> [Float] {
    samples
  }

  func cancel() {
    cancelCount += 1
  }

  func releaseResources() {
    releaseCount += 1
    lifetime?.recordRelease()
  }

  deinit {
    lifetime?.recordDeinit()
  }
}

@MainActor
private final class FluidEnhancedSpeechResourcesSpy: FluidEnhancedSpeechResources {
  private let lifetime: EnhancedLifetimeTracker

  init(lifetime: EnhancedLifetimeTracker) {
    self.lifetime = lifetime
  }

  func prepare() async throws {}

  func transcribe(_: [Float]) async throws -> String {
    "Transcript"
  }

  func cleanup() async {
    lifetime.recordRelease()
  }

  deinit {
    lifetime.recordDeinit()
  }
}

private actor LateFluidResourcesLoader {
  private var resources: (any FluidEnhancedSpeechResources)?
  private var continuation: CheckedContinuation<Void, Never>?
  private var waitingObservers: [CheckedContinuation<Void, Never>] = []

  init(resources: any FluidEnhancedSpeechResources) {
    self.resources = resources
  }

  func loadIgnoringCancellation() async -> any FluidEnhancedSpeechResources {
    let observers = waitingObservers
    waitingObservers.removeAll()
    observers.forEach { $0.resume() }
    await withCheckedContinuation { continuation = $0 }
    let result = resources!
    resources = nil
    return result
  }

  func waitUntilWaiting() async {
    guard continuation == nil else { return }
    await withCheckedContinuation { waitingObservers.append($0) }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

final class EnhancedLifetimeTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var cancels = 0
  private var releases = 0
  private var deinits = 0

  var cancelCount: Int { lock.withLock { cancels } }
  var releaseCount: Int { lock.withLock { releases } }
  var deinitCount: Int { lock.withLock { deinits } }

  func recordCancel() {
    lock.withLock { cancels += 1 }
  }

  func recordRelease() {
    lock.withLock { releases += 1 }
  }

  func recordDeinit() {
    lock.withLock { deinits += 1 }
  }
}

private func enhancedAudioBuffer(
  format: AVAudioFormat,
  frameCount: AVAudioFrameCount,
  value: Float
) throws -> AVAudioPCMBuffer {
  let buffer = try #require(
    AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
  )
  buffer.frameLength = frameCount
  let channel = try #require(buffer.floatChannelData?[0])
  for index in 0..<Int(frameCount) {
    channel[index] = value
  }
  return buffer
}
#endif

@MainActor
private final class PreferenceBox {
  var value: DictationSpeechEngine

  init(value: DictationSpeechEngine) { self.value = value }
}

actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waitingObservers: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    let observers = waitingObservers
    waitingObservers = []
    observers.forEach { $0.resume() }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    guard waiters.isEmpty else { return }
    await withCheckedContinuation { waitingObservers.append($0) }
  }

  func openGate() {
    isOpen = true
    let pending = waiters
    waiters = []
    pending.forEach { $0.resume() }
  }
}

private actor CompletionProbe {
  private(set) var isComplete = false

  func complete() {
    isComplete = true
  }
}
