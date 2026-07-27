import AppKit
import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test func DictationSettingsSelectsStandardByDefault() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(),
    modelState: .notInstalled,
    isArchitectureSupported: true,
    enhancedIsReady: false
  )

  #expect(presentation.selectedEngine == .standard)
}

@Test func DictationSettingsDisablesEnhancedOnIntel() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(),
    modelState: .ready,
    isArchitectureSupported: false,
    enhancedIsReady: true
  )

  #expect(!presentation.enhancedChoiceEnabled)
  #expect(presentation.architectureCopy == "Enhanced dictation requires Apple silicon.")
}

@Test func DictationSettingsOffersEnhancedDownloadWhenNotInstalled() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(),
    modelState: .notInstalled,
    isArchitectureSupported: true,
    enhancedIsReady: false
  )

  #expect(presentation.primaryAction?.title == "Download Enhanced Model")
}

@Test func DictationSettingsConsentExplainsThePrivateLocalDownload() {
  let consent = DictationModelConsentPresentation.standard

  #expect(consent.downloadSize == "442.9 MiB")
  #expect(consent.installedSize == "442.9 MiB")
  #expect(consent.requirement == "Apple silicon")
  #expect(consent.language == "English")
  #expect(consent.attribution.contains("NVIDIA"))
  #expect(consent.attribution.contains("FluidInference"))
  #expect(consent.privacyCopy.contains("does not upload"))
  #expect(consent.privacyCopy.contains("dictation data"))
}

@Test func DictationSettingsDownloadingShowsProgressAndCancel() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(),
    modelState: .downloading(progress: 0.42),
    isArchitectureSupported: true,
    enhancedIsReady: false
  )

  #expect(presentation.downloadProgress == 0.42)
  #expect(presentation.primaryAction == .cancel)
}

@Test func DictationSettingsFailureOffersRepair() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(dictationSpeechEngine: .enhancedLocal),
    modelState: .repairRequired(message: "Checksum mismatch"),
    isArchitectureSupported: true,
    enhancedIsReady: false
  )

  #expect(presentation.primaryAction == .repair)
  #expect(presentation.statusCopy == "Checksum mismatch")
}

@Test func DictationSettingsReadyAllowsSelectionAndDeletion() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(),
    modelState: .ready,
    isArchitectureSupported: true,
    enhancedIsReady: true
  )

  #expect(presentation.enhancedChoiceEnabled)
  #expect(presentation.primaryAction == .delete)
}

@Test func DictationSettingsDeletionReturnsSelectionToStandard() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(dictationSpeechEngine: .enhancedLocal),
    modelState: .notInstalled,
    isArchitectureSupported: true,
    enhancedIsReady: false
  )

  #expect(presentation.selectedEngine == .standard)
}

@Test func DictationSettingsUpdateRequiresAnExplicitAction() {
  let presentation = DictationSettingsPresentation(
    preferences: AppPreferences(dictationSpeechEngine: .enhancedLocal),
    modelState: .updateAvailable,
    isArchitectureSupported: true,
    enhancedIsReady: true
  )

  #expect(presentation.selectedEngine == .enhancedLocal)
  #expect(presentation.primaryAction == .update)
  #expect(presentation.secondaryAction == .delete)
}

@Test func DictationSettingsUsesTheExistingMatchedGeometrySectionSelector() {
  #expect(SettingsSection.allCases == [.appearance, .editing, .shortcuts, .dictation])
  #expect(SettingsSection.selectionEffectID == "settings-section")
}

@Test func DictationSettingsHistoryClearRequiresConfirmation() {
  let record = DictationHistoryRecord(
    id: UUID(),
    mode: .smartCapture,
    engine: .standard,
    startedAt: Date(timeIntervalSince1970: 1),
    completedAt: Date(timeIntervalSince1970: 2),
    rawTranscript: "raw",
    cleanedTranscript: "clean",
    cleanupOutcome: .cleaned,
    insertionOutcome: .unsaved
  )
  var presentation = DictationHistoryPresentation(records: [record])

  presentation.requestClear()

  #expect(presentation.pendingConfirmation == .clear)
  #expect(presentation.records == [record])
}

@Test func DictationSettingsHistoryRollsBackOptimisticClearAndDelete() {
  let first = DictationHistoryRecord(
    id: UUID(),
    mode: .smartCapture,
    engine: .standard,
    startedAt: Date(timeIntervalSince1970: 1),
    completedAt: Date(timeIntervalSince1970: 2),
    rawTranscript: "first",
    cleanupOutcome: .usedRaw,
    insertionOutcome: .unsaved
  )
  let second = DictationHistoryRecord(
    id: UUID(),
    mode: .focused,
    engine: .enhancedLocal,
    startedAt: Date(timeIntervalSince1970: 3),
    completedAt: Date(timeIntervalSince1970: 4),
    rawTranscript: "second",
    cleanedTranscript: "Second.",
    cleanupOutcome: .cleaned,
    insertionOutcome: .saved
  )
  var presentation = DictationHistoryPresentation(records: [second, first])

  presentation.requestDelete(first.id)
  presentation.confirmPendingRemoval()
  #expect(presentation.records == [second])
  presentation.rollbackRemoval()
  #expect(presentation.records == [second, first])

  presentation.requestClear()
  presentation.confirmPendingRemoval()
  #expect(presentation.records.isEmpty)
  presentation.rollbackRemoval()
  #expect(presentation.records == [second, first])
}

@Test func DictationToolbarMakesProcessingPrimaryActionsInertButKeepsCancel() {
  let expected: [(DictationPhase, String)] = [
    (.finalizing, "Finalizing Dictation"),
    (.cleaning, "Cleaning Dictation"),
    (.routing, "Routing Dictation"),
  ]

  for (phase, label) in expected {
    let presentation = DictationToolbarPresentation(phase: phase)
    #expect(presentation.primaryLabel == label)
    #expect(presentation.primaryAction == nil)
    #expect(presentation.canCancel)
  }
}

@Test @MainActor func DictationCapsuleMapsTerminalModeCleanupDestinationAndFailures() {
  let destination = DictationDestination(noteID: UUID(), title: "Ideas")
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .saved(destination),
    terminal: .saved(mode: .smartCapture, cleanup: .cleaned, destination: destination)
  )) == .saved(destination: "Ideas"))
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .idle,
    terminal: .saved(mode: .focused, cleanup: .usedRaw, destination: nil)
  )) == .savedWithoutCleanup(destination: "current note"))
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .failed("No speech"),
    terminal: .failed("No speech")
  )) == .failed("No speech"))
}

@Test func DictationHistoryRowDoesNotMislabelOrDuplicateRawFallback() {
  let raw = historyRecord(raw: "raw", cleaned: nil, cleanup: .usedRaw)
  let rawPresentation = DictationHistoryRowPresentation(record: raw)
  #expect(rawPresentation.primaryTitle == "Raw fallback")
  #expect(rawPresentation.primaryTranscript == "raw")
  #expect(rawPresentation.rawTranscript == nil)
  #expect(!rawPresentation.canCopyClean)

  let cleaned = historyRecord(raw: "raw", cleaned: "Clean.", cleanup: .cleaned)
  let cleanPresentation = DictationHistoryRowPresentation(record: cleaned)
  #expect(cleanPresentation.primaryTitle == "Cleaned")
  #expect(cleanPresentation.primaryTranscript == "Clean.")
  #expect(cleanPresentation.rawTranscript == "raw")
  #expect(cleanPresentation.canCopyClean)
}

@Test @MainActor func DictationShortcutRecorderEscapeAndFocusLossRestoreItsShortcutTitle() {
  let shortcut = DictationShortcut(keyCode: 49, carbonModifiers: 256)
  let button = DictationShortcutRecorder.RecorderButton()
  button.update(shortcut)
  let originalTitle = button.title

  button.beginRecording()
  #expect(button.title == "Type shortcut…")
  #expect(button.handleKey(keyCode: 53, modifierFlags: []))
  #expect(button.title == originalTitle)

  button.beginRecording()
  _ = button.resignFirstResponder()
  #expect(button.title == originalTitle)
  #expect(!button.isRecording)
}

@Test @MainActor func DictationEditorRegistryUsesOnlyTheActualFirstResponder() {
  let registry = DictationEditorRegistry()
  let body = EditorCommands()
  let bodyView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let titleView = NSTextField(frame: NSRect(x: 0, y: 90, width: 200, height: 24))
  let otherView = NSTextField(frame: NSRect(x: 0, y: 115, width: 80, height: 24))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 140),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  let content = NSView(frame: window.contentView?.bounds ?? .zero)
  content.addSubview(bodyView)
  content.addSubview(titleView)
  content.addSubview(otherView)
  window.contentView = content
  body.textView = bodyView
  registry.register(body)

  window.makeFirstResponder(titleView)
  #expect(registry.focusedEditor() == nil)
  window.makeFirstResponder(bodyView)
  #expect(registry.focusedEditor() === body)
  window.makeFirstResponder(otherView)
  #expect(registry.focusedEditor() == nil)
}

@Test @MainActor func DictationHistoryControllerSharesWritesAcrossPresentationsAndSettingsClear()
  async
{
  let record = historyRecord(raw: "raw", cleaned: "Clean.", cleanup: .cleaned)
  let controller = DictationHistoryController(
    records: [record],
    load: { [record] },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let first = DictationHistoryViewModel(controller: controller)
  let second = DictationHistoryViewModel(controller: controller)

  first.requestDelete(record.id)
  await first.confirmRemoval()
  #expect(controller.records.isEmpty)
  #expect(second.controller.records.isEmpty)

  await controller.save(record)
  await controller.clear()
  #expect(first.controller.records.isEmpty)
  #expect(second.controller.records.isEmpty)
}

@Test @MainActor func DictationHistoryControllerSerializesOverlappingMutationsAndRollsBackOnlyFailure()
  async
{
  let first = historyRecord(raw: "first", cleaned: nil, cleanup: .usedRaw)
  let second = historyRecord(raw: "second", cleaned: nil, cleanup: .usedRaw)
  let gate = DictationTestGate()
  let log = DictationOperationLog()
  let controller = DictationHistoryController(
    records: [first, second],
    load: { [first, second] },
    save: { _ in },
    delete: { id in
      await log.append("delete-\(id)")
      await gate.wait()
      throw DictationSettingsTestError.failed
    },
    clear: {
      await log.append("clear")
    }
  )

  let deletion = Task { await controller.delete(first.id) }
  await gate.waitUntilWaiting()
  let clear = Task { await controller.clear() }
  await Task.yield()
  #expect(await log.values.count == 1)
  await gate.open()
  await deletion.value
  await clear.value

  #expect(await log.values == ["delete-\(first.id)", "clear"])
  #expect(controller.records.isEmpty)
  #expect(controller.errorMessage == nil)
}

@Test @MainActor func DictationHistoryControllerSharesFailureAndRestoresOnlyFailedOperation()
  async
{
  let first = historyRecord(raw: "first", cleaned: nil, cleanup: .usedRaw)
  let second = historyRecord(raw: "second", cleaned: nil, cleanup: .usedRaw)
  let controller = DictationHistoryController(
    records: [first, second],
    load: { [first, second] },
    save: { _ in },
    delete: { _ in throw DictationSettingsTestError.failed },
    clear: {}
  )
  let otherPresentation = DictationHistoryViewModel(controller: controller)

  await controller.delete(first.id)

  #expect(controller.records == [first, second])
  #expect(controller.errorMessage?.contains("Could not update") == true)
  #expect(otherPresentation.controller.errorMessage == controller.errorMessage)
}

@Test @MainActor func DictationRuntimeAssessesOnceBeforeAuthoritativeEnhancedDowngrade() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", startupBlocked: true)
  fixture.appState.preferences.dictationSpeechEngine = .enhancedLocal
  fixture.enhancedReady.value = false

  #expect(fixture.appState.preferences.dictationSpeechEngine == .enhancedLocal)
  await fixture.startupGate.waitUntilWaiting()
  #expect(await fixture.startupLog.value == 1)
  let firstWaiter = Task { await fixture.runtime.awaitStartupAssessment() }
  let secondWaiter = Task { await fixture.runtime.awaitStartupAssessment() }
  await fixture.startupGate.open()
  await firstWaiter.value
  await secondWaiter.value

  #expect(fixture.appState.preferences.dictationSpeechEngine == .standard)
  #expect(await fixture.startupLog.value == 1)
}

@Test @MainActor func DictationRuntimeUsesCoordinatorEventsAndAppliesShortcutAfterTerminal() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let replacement = DictationShortcut(keyCode: 36, carbonModifiers: 256)
  await fixture.runtime.awaitStartupAssessment()
  #expect(!DictationRuntime.usesPeriodicObservation)

  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
  fixture.appState.preferences.dictationShortcut = replacement
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.actualShortcut != replacement)

  await fixture.runtime.toggle()
  await fixture.runtime.waitForTerminalSynchronization()
  #expect(fixture.runtime.actualShortcut == replacement)
  #expect(fixture.runtime.phase != .finalizing)
}

@Test @MainActor func DictationRuntimeAppliesPendingShortcutAfterSavedAndFailedHotkeySessions()
  async throws
{
  for finalText in ["saved", nil] as [String?] {
    let fixture = try await RuntimeFixture(finalText: finalText)
    await fixture.runtime.awaitStartupAssessment()
    let replacement = DictationShortcut(keyCode: 36, carbonModifiers: 256)

    fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
    await fixture.runtime.shortcutController.drainEvents()
    for _ in 0..<20 {
      if case .listening = fixture.runtime.phase { break }
      await Task.yield()
    }
    if case .listening = fixture.runtime.phase {
      // Capture is active, not merely arming.
    } else {
      Issue.record("Expected listening phase, got \(fixture.runtime.phase)")
    }

    fixture.appState.updatePreferences { $0.dictationShortcut = replacement }
    fixture.runtime.preferencesDidChange()
    fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
    await fixture.runtime.shortcutController.drainEvents()
    await fixture.runtime.waitForTerminalSynchronization()

    #expect(fixture.runtime.actualShortcut == replacement)
    if finalText == nil {
      #expect(fixture.runtime.phase == .failed("No speech detected."))
    } else {
      #expect(fixture.runtime.phase == .idle)
    }
  }
}

@Test @MainActor func DictationRuntimePreservesActualShortcutOnConflictAndRetriesExplicitly()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  let old = fixture.appState.preferences.dictationShortcut
  let replacement = DictationShortcut(keyCode: 36, carbonModifiers: 256)
  fixture.registrar.failingKeyCodes.insert(36)
  fixture.appState.preferences.dictationShortcut = replacement
  fixture.runtime.preferencesDidChange()

  #expect(fixture.runtime.actualShortcut == old)
  #expect(fixture.runtime.shortcutError == "That shortcut is already in use.")

  fixture.registrar.failingKeyCodes.remove(36)
  fixture.runtime.retryShortcutRegistration()
  #expect(fixture.runtime.actualShortcut == replacement)
  #expect(fixture.runtime.shortcutError == nil)
}

@Test @MainActor func DictationRuntimeShutdownIsIdempotentAndDoesNotRetainRuntime() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  var runtime: DictationRuntime? = fixture.runtime
  weak let weakRuntime = runtime
  await runtime?.shutdown()
  await runtime?.shutdown()
  #expect(runtime?.shutdownCount == 1)
  runtime = nil
  fixture.releaseRuntime()
  await Task.yield()
  #expect(weakRuntime == nil)
}

private func historyRecord(
  raw: String,
  cleaned: String?,
  cleanup: DictationCleanupOutcome
) -> DictationHistoryRecord {
  DictationHistoryRecord(
    id: UUID(),
    mode: .smartCapture,
    engine: .standard,
    startedAt: Date(timeIntervalSince1970: 1),
    completedAt: Date(timeIntervalSince1970: 2),
    rawTranscript: raw,
    cleanedTranscript: cleaned,
    cleanupOutcome: cleanup,
    insertionOutcome: .saved
  )
}

private enum DictationSettingsTestError: Error {
  case failed
}

private actor DictationTestGate {
  private var openState = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var observers: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !openState else { return }
    let current = observers
    observers.removeAll()
    current.forEach { $0.resume() }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    guard waiters.isEmpty else { return }
    await withCheckedContinuation { observers.append($0) }
  }

  func open() {
    openState = true
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume() }
  }
}

private actor DictationOperationLog {
  private(set) var values: [String] = []

  func append(_ value: String) {
    values.append(value)
  }
}

@MainActor
private final class RuntimeFixture {
  let appState: AppState
  let registrar = RuntimeRegistrar()
  let startupGate = DictationTestGate()
  let startupLog = RuntimeCounter()
  let enhancedReady = RuntimeBool()
  var runtime: DictationRuntime!

  init(finalText: String?, startupBlocked: Bool = false) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-\(UUID().uuidString)", isDirectory: true)
    let store = LocalStore(rootURL: root)
    let preferences = AppPreferences(
      dictationShortcut: DictationShortcut(keyCode: 49, carbonModifiers: 768),
      dictationCapsuleEnabled: false
    )
    var workspace = Workspace()
    workspace.ensureNoteExists()
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: []
    )
    appState = AppState(store: store, saveOperation: { _, _, _ in })
    try await Task.sleep(for: .milliseconds(20))
    appState.preferences = preferences
    let engine = RuntimeSpeechEngine(finalText: finalText)
    let provider = RuntimeEngineProvider(engine: engine)
    let history = DictationHistoryController(
      load: { [] },
      save: { _ in },
      delete: { _ in },
      clear: {}
    )
    let coordinator = DictationCoordinator(
      engineProvider: provider,
      preferredEngine: { .standard },
      cleaner: RuntimeCleaner(),
      router: RuntimeRouter(),
      saver: appState,
      historyController: history,
      historyEnabled: { true },
      holdThreshold: .zero,
      holdSleeper: { _ in }
    )
    let shortcut = GlobalHoldShortcut(handler: coordinator, registrar: registrar)
    let modelRoot = root.appendingPathComponent("model", isDirectory: true)
    let modelManager = EnhancedModelManager(
      modelRootURL: modelRoot,
      architectureProvider: { true }
    )
    let gate = startupGate
    let log = startupLog
    runtime = DictationRuntime(
      appState: appState,
      modelManager: modelManager,
      engineProvider: provider,
      coordinator: coordinator,
      shortcutController: shortcut,
      capsuleController: DictationCapsuleController(),
      historyController: history,
      permissionController: DictationPermissionController(),
      editorRegistry: DictationEditorRegistry(),
      startupAssessment: {
        await log.increment()
        if startupBlocked { await gate.wait() }
      },
      enhancedIsReady: { [enhancedReady] in enhancedReady.value }
    )
  }

  func releaseRuntime() {
    runtime = nil
  }
}

@MainActor
private final class RuntimeRegistrar: GlobalHotKeyRegistering {
  var eventHandler: ((UInt32, Bool) -> Void)?
  var failingKeyCodes = Set<UInt32>()
  private(set) var registrations = Set<UInt32>()

  func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
    if failingKeyCodes.contains(keyCode) {
      throw GlobalHoldShortcut.RegistrationError.conflict(-9876)
    }
    registrations.insert(id)
  }

  func unregister(id: UInt32) {
    registrations.remove(id)
  }

  func emit(id: UInt32, pressed: Bool) {
    eventHandler?(id, pressed)
  }
}

@MainActor
private final class RuntimeEngineProvider: SpeechEngineProviding {
  let engine: RuntimeSpeechEngine

  init(engine: RuntimeSpeechEngine) {
    self.engine = engine
  }

  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
    engine
  }
}

@MainActor
private final class RuntimeSpeechEngine: SpeechEngine {
  let kind = DictationSpeechEngine.standard
  let finalText: String?

  init(finalText: String?) {
    self.finalText = finalText
  }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {}

  func finish() async throws -> String? {
    finalText
  }

  func cancel() async {}
  func releaseResources() async {}
}

private struct RuntimeCleaner: TranscriptCleaning {
  func clean(_ transcript: String) async throws -> String {
    transcript
  }
}

private struct RuntimeRouter: DestinationRouting {
  func route(
    transcript: String,
    candidates: [DictationDestination],
    inboxID: UUID?
  ) async -> UUID? {
    inboxID
  }
}

private actor RuntimeCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

@MainActor
private final class RuntimeBool {
  var value = false
}
