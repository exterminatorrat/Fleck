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
  let fixture = try Fixture()

  fixture.coordinator.beginShortcut(editor: nil)
  await fixture.coordinator.endShortcut(heldFor: .milliseconds(179))

  #expect(fixture.provider.requestedKinds.isEmpty)
  #expect(fixture.standard.startCount == 0)
  #expect(fixture.editor.beginCount == 0)
}

@Test @MainActor func shortcutChoosesFocusedOnlyForActiveMotesEditor() async throws {
  let focused = try Fixture()

  focused.coordinator.beginShortcut(editor: focused.editor)
  await focused.coordinator.endShortcut(heldFor: .milliseconds(180))

  #expect(focused.coordinator.phase == .listening(mode: .focused, engine: .standard))
  #expect(focused.editor.beginCount == 1)
  await focused.coordinator.cancel()

  let smart = try Fixture()
  smart.coordinator.beginShortcut(editor: nil)
  await smart.coordinator.endShortcut(heldFor: .milliseconds(180))

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

  init(preferred: DictationSpeechEngine = .standard, historyEnabled: Bool = true) throws {
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
      historyEnabled: { historyEnabled }
    )
  }
}

@MainActor
private final class FakeSpeechEngine: SpeechEngine {
  let kind: DictationSpeechEngine
  var startError: Error?
  var onStart: (() -> Void)?
  var finalText: String?
  private var provisional: (@MainActor (String) -> Void)?
  var startCount = 0
  var finishCount = 0
  var cancelCount = 0
  var releaseCount = 0

  init(kind: DictationSpeechEngine) { self.kind = kind }

  func start(provisional: @escaping @MainActor (String) -> Void, level: @escaping @MainActor (Float) -> Void) async throws {
    startCount += 1
    onStart?()
    if let startError { throw startError }
    self.provisional = provisional
  }

  func finish() async throws -> String? {
    finishCount += 1
    return finalText
  }

  func cancel() async { cancelCount += 1 }
  func releaseResources() async { releaseCount += 1 }
  func emitProvisional(_ text: String) { provisional?(text) }
}

@MainActor
private final class FakeEngineProvider: SpeechEngineProviding {
  var engines: [DictationSpeechEngine: any SpeechEngine] = [:]
  var requestedKinds: [DictationSpeechEngine] = []

  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
    requestedKinds.append(preferred)
    guard let engine = engines[preferred] else { throw TestError.failed }
    return engine
  }
}

private final class FakeCleaner: TranscriptCleaning, @unchecked Sendable {
  var result: String?
  var error: Error?
  var onClean: (() async throws -> String)?

  func clean(_ rawTranscript: String) async throws -> String {
    if let onClean { return try await onClean() }
    if let error { throw error }
    return result ?? rawTranscript
  }
}

private final class FakeRouter: DestinationRouting, @unchecked Sendable {
  var result: UUID?

  func route(transcript: String, candidates: [DictationDestination], inboxID: UUID?) async -> UUID? {
    result
  }
}

@MainActor
private final class FakeSaver: DictationSaving {
  var destinations: [DictationDestination] = []
  var saveError: Error?
  var savedTexts: [String] = []
  var destinationIDs: [UUID?] = []
  var flushCount = 0

  func activeDestinations() -> [DictationDestination] { destinations }

  func saveSmartCapture(text: String, captureID: UUID, destinationID: UUID?) async throws -> DictationInsertionReceipt {
    savedTexts.append(text)
    destinationIDs.append(destinationID)
    if let saveError { throw saveError }
    let noteID = destinationID ?? UUID()
    return DictationInsertionReceipt(captureID: captureID, noteID: noteID, insertedSuffix: text)
  }

  func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool { true }
  func flushFocusedDictationSave() async throws { flushCount += 1 }
}

@MainActor
private final class FakeEditor: FocusedDictationEditing {
  var canBeginFocusedDictation = true
  var beginCount = 0
  var provisionalTexts: [String] = []
  var committedTexts: [String] = []
  var cancelCount = 0

  func beginFocusedDictation() -> Bool {
    beginCount += 1
    return canBeginFocusedDictation
  }

  func updateFocusedDictation(provisionalText: String) { provisionalTexts.append(provisionalText) }
  func commitFocusedDictation(text: String) -> Bool {
    committedTexts.append(text)
    return true
  }
  func cancelFocusedDictation() { cancelCount += 1 }
}

private enum TestError: Error { case failed }

@MainActor
private final class PreferenceBox {
  var value: DictationSpeechEngine

  init(value: DictationSpeechEngine) { self.value = value }
}
