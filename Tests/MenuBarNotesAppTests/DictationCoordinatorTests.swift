import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func coordinatorRequestsStandardByDefault() async throws {
  let fixture = try Fixture()

  await fixture.coordinator.start(mode: .smartCapture)

  #expect(fixture.provider.requestedKinds == [.standard])
  #expect(fixture.standard.startCount == 1)
  await fixture.coordinator.cancel()
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
  await Task.yield()

  #expect(fixture.standard.startCount == 1)
  #expect(fixture.coordinator.phase == .listening(mode: .smartCapture, engine: .standard))

  await fixture.coordinator.endShortcut()

  #expect(fixture.standard.finishCount == 1)
  #expect(fixture.saver.savedTexts == ["Held dictation"])
}

@Test @MainActor func shortcutChoosesFocusedOnlyForActiveMotesEditor() async throws {
  let focusedThreshold = Gate()
  let focused = try Fixture(holdSleeper: { _ in await focusedThreshold.wait() })

  focused.coordinator.beginShortcut(editor: focused.editor)
  await focusedThreshold.waitUntilWaiting()
  await focusedThreshold.openGate()
  await Task.yield()

  #expect(focused.coordinator.phase == .listening(mode: .focused, engine: .standard))
  #expect(focused.editor.beginCount == 1)
  await focused.coordinator.cancel()

  let smartThreshold = Gate()
  let smart = try Fixture(holdSleeper: { _ in await smartThreshold.wait() })
  smart.coordinator.beginShortcut(editor: nil)
  await smartThreshold.waitUntilWaiting()
  await smartThreshold.openGate()
  await Task.yield()

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
  #expect(fixture.editor.cancelCount == 1)
  let record = try #require(await fixture.history.list().first)
  #expect(record.insertionOutcome == .unsaved)
  #expect(fixture.standard.releaseCount == 1)
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

  fixture.coordinator.beginShortcut(editor: nil)
  await threshold.waitUntilWaiting()
  await threshold.openGate()
  await startGate.waitUntilWaiting()
  await fixture.coordinator.endShortcut()

  #expect(fixture.standard.finishCount == 0)
  #expect(fixture.coordinator.phase == .arming)
  await startGate.openGate()
  await saveGate.waitUntilWaiting()

  #expect(fixture.standard.finishCount == 1)
  #expect(fixture.coordinator.phase == .routing)
  await saveGate.openGate()
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

@Test @MainActor func EnhancedSpeechRejectsAnUnverifiedModelWithoutStartingAudio() async {
  let inference = EnhancedInferenceSpy()
  let audio = EnhancedAudioSpy(samples: [0.25])
  let capture = EnhancedSpeechCapture(
    verifiedLoadState: { .unavailable },
    makeInference: { inference },
    makeAudio: { _ in audio }
  )

  await #expect(throws: DictationFailure.unavailable) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }

  #expect(inference.loadURLs.isEmpty)
  #expect(inference.releaseCount == 1)
  #expect(audio.startCount == 0)
  #expect(!capture.hasActiveResources)
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
    markRepairRequired: { repairMessages.append($0) },
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
    preferred: DictationSpeechEngine = .standard,
    historyEnabled: Bool = true,
    holdSleeper: @escaping @Sendable (Duration) async -> Void = { _ in }
  ) throws {
    preference = PreferenceBox(value: preferred)
    provider = FakeEngineProvider()
    saver = FakeSaver()
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    history = DictationHistoryStore(rootURL: root)
    saver.destinations = [inbox]
    provider.engines = [.standard: standard, .enhancedLocal: enhanced]
    coordinator = DictationCoordinator(
      engineProvider: provider,
      preferredEngine: { [preference] in preference.value },
      cleaner: cleaner,
      router: router,
      saver: saver,
      historyStore: history,
      historyEnabled: { historyEnabled },
      holdSleeper: holdSleeper
    )
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

private final class FakeCleaner: TranscriptCleaning, @unchecked Sendable {
  var result: String?
  var error: Error?
  var onClean: (() async throws -> String)?
  var gate: Gate?

  func clean(_ rawTranscript: String) async throws -> String {
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
  var flushError: Error?
  var savedTexts: [String] = []
  var destinationIDs: [UUID?] = []
  var flushCount = 0
  var undoCount = 0
  var undoSucceeds = true

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
    if undoSucceeds, !savedTexts.isEmpty { savedTexts.removeLast() }
    return undoSucceeds
  }
  func flushFocusedDictationSave() async throws {
    flushCount += 1
    if let flushError { throw flushError }
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

  func beginFocusedDictation() -> Bool {
    beginCount += 1
    return canBeginFocusedDictation
  }

  func updateFocusedDictation(provisionalText: String) { provisionalTexts.append(provisionalText) }
  func commitFocusedDictation(text: String) -> Bool {
    committedTexts.append(text)
    return commitResult
  }
  func cancelFocusedDictation() { cancelCount += 1 }
}

private enum TestError: Error { case failed }

enum EnhancedTestFailure: Error {
  case failed
}

@MainActor
final class EnhancedInferenceSpy: EnhancedSpeechInferring {
  var result = "Transcript"
  var loadError: Error?
  var transcriptionError: Error?
  private(set) var loadURLs: [URL] = []
  private(set) var transcribedSamples: [[Float]] = []
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0

  func load(from repositoryURL: URL) async throws {
    loadURLs.append(repositoryURL)
    if let loadError { throw loadError }
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    transcribedSamples.append(samples)
    if let transcriptionError { throw transcriptionError }
    return result
  }

  func cancel() async {
    cancelCount += 1
  }

  func releaseResources() async {
    releaseCount += 1
  }
}

@MainActor
final class EnhancedAudioSpy: EnhancedAudioCapturing {
  let samples: [Float]
  let emittedLevel: Float?
  private(set) var startCount = 0
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0

  init(samples: [Float], emittedLevel: Float? = nil) {
    self.samples = samples
    self.emittedLevel = emittedLevel
  }

  func start(level: @escaping @MainActor (Float) -> Void) throws {
    startCount += 1
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
  }
}

@MainActor
private final class PreferenceBox {
  var value: DictationSpeechEngine

  init(value: DictationSpeechEngine) { self.value = value }
}

private actor Gate {
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
