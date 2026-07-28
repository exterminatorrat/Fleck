import AppKit
import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
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
#endif

@Test func DictationSettingsUsesTheExistingMatchedGeometrySectionSelector() {
  #expect(SettingsSection.allCases == [.appearance, .editing, .shortcuts, .dictation])
  #expect(SettingsSection.selectionEffectID == "settings-section")
}

@Test @MainActor func DictationSettingsHistoryClearRequiresConfirmation() {
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
  let controller = DictationHistoryController(
    records: [record],
    load: { [record] },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let model = DictationHistoryViewModel(controller: controller)

  model.requestClear()

  #expect(model.pendingConfirmation == .clear)
  #expect(controller.records == [record])
}

@Test @MainActor func DictationSettingsHistoryRollsBackOptimisticClearAndDelete() async {
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
  let deleteGate = DictationTestGate()
  let clearGate = DictationTestGate()
  let controller = DictationHistoryController(
    records: [second, first],
    load: { [second, first] },
    save: { _ in },
    delete: { _ in
      await deleteGate.wait()
      throw DictationSettingsTestError.failed
    },
    clear: {
      await clearGate.wait()
      throw DictationSettingsTestError.failed
    }
  )
  let model = DictationHistoryViewModel(controller: controller)

  model.requestDelete(first.id)
  let deletion = Task { await model.confirmRemoval() }
  await deleteGate.waitUntilWaiting()
  #expect(controller.records == [second])
  await deleteGate.open()
  await deletion.value
  #expect(controller.records == [second, first])

  model.requestClear()
  let clearing = Task { await model.confirmRemoval() }
  await clearGate.waitUntilWaiting()
  #expect(controller.records.isEmpty)
  await clearGate.open()
  await clearing.value
  #expect(controller.records == [second, first])
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
  _ = await deletion.value
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

@Test @MainActor func DictationHistoryDelayedLoadCannotResurrectClearedRowsAcrossScenes() async {
  let record = historyRecord(raw: "private", cleaned: nil, cleanup: .usedRaw)
  let loadGate = DictationTestGate()
  let controller = DictationHistoryController(
    records: [record],
    load: {
      await loadGate.wait()
      return [record]
    },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let otherScene = DictationHistoryViewModel(controller: controller)

  let loading = Task { await controller.load() }
  await loadGate.waitUntilWaiting()
  let clearing = Task { await controller.clear() }
  await Task.yield()
  await loadGate.open()
  await loading.value
  await clearing.value

  #expect(controller.records.isEmpty)
  #expect(otherScene.controller.records.isEmpty)
}

@Test @MainActor func DictationHistoryDelayedLoadCannotResurrectDeletedRowsAcrossScenes() async {
  let first = historyRecord(raw: "first", cleaned: nil, cleanup: .usedRaw)
  let second = historyRecord(raw: "second", cleaned: nil, cleanup: .usedRaw)
  let loadGate = DictationTestGate()
  let controller = DictationHistoryController(
    records: [first, second],
    load: {
      await loadGate.wait()
      return [first, second]
    },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let otherScene = DictationHistoryViewModel(controller: controller)

  let loading = Task { await controller.load() }
  await loadGate.waitUntilWaiting()
  let deleting = Task { await controller.delete(first.id) }
  await Task.yield()
  await loadGate.open()
  await loading.value
  _ = await deleting.value

  #expect(controller.records == [second])
  #expect(otherScene.controller.records == [second])
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

@Test @MainActor func DictationRuntimeFocusedToolbarPersistsTheSelectedNoteDestination()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "Focused")
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  commands.textView = textView
  fixture.editorRegistry.register(commands)
  window.makeFirstResponder(textView)
  let selected = try #require(fixture.appState.selectedNote)

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()

  let record = try #require(fixture.history.records.first)
  #expect(record.mode == .focused)
  #expect(record.destination == .init(noteID: selected.id, title: selected.displayTitle))
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func DictationRuntimeFocusedGlobalShortcutPersistsTheSelectedNoteDestination()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "Focused")
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  commands.textView = textView
  fixture.editorRegistry.register(commands)
  window.makeFirstResponder(textView)
  let selected = try #require(fixture.appState.selectedNote)

  fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await fixture.runtime.shortcutController.drainEvents()
  for _ in 0..<20 {
    if case .listening = fixture.runtime.phase { break }
    await Task.yield()
  }
  fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
  await fixture.runtime.shortcutController.drainEvents()
  await fixture.runtime.waitForTerminalSynchronization()

  let record = try #require(fixture.history.records.first)
  #expect(record.mode == .focused)
  #expect(record.destination == .init(noteID: selected.id, title: selected.displayTitle))
  #expect(record.insertionOutcome == .saved)
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

@Test @MainActor func DictationRuntimeReportsUnregisteredAfterReplacementAndRestoreFail()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  let replacement = DictationShortcut(keyCode: 36, carbonModifiers: 256)
  fixture.registrar.failingKeyCodes = [36, 49]
  fixture.appState.preferences.dictationShortcut = replacement
  fixture.runtime.preferencesDidChange()

  #expect(fixture.runtime.actualShortcut == nil)
  #expect(
    fixture.runtime.shortcutError
      == "The new shortcut failed and the previous shortcut could not be restored. No dictation shortcut is registered."
  )

  fixture.registrar.failingKeyCodes.removeAll()
  fixture.runtime.retryShortcutRegistration()
  #expect(fixture.runtime.actualShortcut == replacement)
  #expect(fixture.runtime.shortcutError == nil)
}

@Test @MainActor func DictationRecoveryRemainsReachableWhenCapsuleIsDisabled()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "recoverable", capsuleEnabled: false)

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(fixture.runtime.recoveryAction == .undo)
  #expect(fixture.runtime.recoveryCommand == .init(title: "Undo", isEnabled: true))

  await fixture.runtime.performRecoveryAction()

  #expect(fixture.runtime.recoveryAction == nil)
  #expect(!fixture.runtime.recoveryCommand.isEnabled)
}

@Test @MainActor func DictationRecoveryCommandDisablesWhileShortcutIsArmed()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "recoverable")

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let session = try #require(fixture.runtime.coordinator.beginShortcut(editor: nil))

  #expect(!fixture.runtime.recoveryCommand.isEnabled)

  await fixture.runtime.coordinator.cancelShortcut(session)
  #expect(fixture.runtime.recoveryCommand.isEnabled)
}

@Test @MainActor func DictationRuntimePreflightsDeniedMicrophoneAndSpeechPermissions()
  async throws
{
  for (microphone, speech, expectedPane, expectedTitle) in [
    (
      DictationPermissionStatus.denied,
      DictationPermissionStatus.authorized,
      DictationPrivacyPane.microphone,
      "Open Microphone Settings"
    ),
    (
      DictationPermissionStatus.authorized,
      DictationPermissionStatus.denied,
      DictationPrivacyPane.speechRecognition,
      "Open Speech Recognition Settings"
    ),
  ] {
    let availability = DictationAvailability.evaluate(.init(
      osMajorVersion: 26,
      architecture: .appleSilicon,
      microphonePermission: microphone,
      speechPermission: speech,
      appleOnDeviceRecognitionSupported: true,
      enhancedModelReady: false,
      foundationModelAvailable: true
    ))
    let fixture = try await RuntimeFixture(finalText: nil, availability: availability)

    await fixture.runtime.toggle()

    guard case .failed(let message) = fixture.runtime.phase else {
      Issue.record("Expected permission preflight failure")
      continue
    }
    #expect(message == availability.standardFailureCopy)
    #expect(fixture.runtime.permissionRecoveryActions().map(\.pane) == [expectedPane])
    #expect(fixture.runtime.captureFailure?.message == message)
    #expect(fixture.runtime.captureFailure?.actions.map(\.title) == [expectedTitle])
    #expect(fixture.provider.requestCount == 0)
  }
}

@Test @MainActor func DictationRuntimePreflightsUnavailableOnDeviceRecognizer()
  async throws
{
  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: false,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  let fixture = try await RuntimeFixture(finalText: nil, availability: availability)

  await fixture.runtime.toggle()

  #expect(
    fixture.runtime.phase
      == .failed(
        "Standard — Apple Speech is unavailable because on-device English recognition is not installed or supported."
      )
  )
  #expect(fixture.runtime.permissionRecoveryActions().isEmpty)
  #expect(
    fixture.runtime.captureFailure?.message
      == "Standard — Apple Speech is unavailable because on-device English recognition is not installed or supported."
  )
  #expect(fixture.runtime.captureFailure?.actions.isEmpty == true)
  #expect(fixture.provider.requestCount == 0)
}

@Test @MainActor func DictationRuntimeClearsVisiblePreflightFailureOnRetryAndSuccess()
  async throws
{
  let availability = RuntimeAvailabilityBox(.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  )))
  let fixture = try await RuntimeFixture(
    finalText: "Saved",
    availabilityProvider: { availability.value }
  )

  await fixture.runtime.toggle()
  #expect(fixture.runtime.captureFailure != nil)

  availability.value = .evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  await fixture.runtime.toggle()

  #expect(fixture.runtime.captureFailure == nil)
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))

  await fixture.runtime.toggle()
  #expect(fixture.runtime.captureFailure == nil)
}

@Test @MainActor func DictationRuntimePublishesGlobalPermissionFailureInNotesPanel()
  async throws
{
  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  let fixture = try await RuntimeFixture(finalText: nil, availability: availability)
  fixture.provider.error = DictationFailure.permissionDenied

  fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await fixture.runtime.shortcutController.drainEvents()
  for _ in 0..<20 {
    if fixture.runtime.captureFailure != nil { break }
    await Task.yield()
  }

  #expect(fixture.runtime.captureFailure?.message == availability.standardFailureCopy)
  #expect(
    fixture.runtime.captureFailure?.actions.map(\.title)
      == ["Open Microphone Settings"]
  )
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor func FocusedEnhancedToolbarFailureUsesOnlyMicrophoneRecoveryAndClearsOnRetry()
  async throws
{
  let availability = RuntimeAvailabilityBox(.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .denied,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: true,
    foundationModelAvailable: true
  ), enhancedCandidateEnabled: true))
  let fixture = try await RuntimeFixture(
    finalText: "Enhanced",
    preferredEngine: .enhancedLocal,
    enhancedReadyAtStartup: true,
    availabilityProvider: { availability.value }
  )
  let focused = focusRuntimeEditor(fixture)
  fixture.provider.error = DictationFailure.permissionDenied

  await fixture.runtime.toggle()

  #expect(fixture.provider.requestedKinds == [.enhancedLocal])
  #expect(
    fixture.runtime.captureFailure?.message
      == "Enhanced Local needs Microphone access. Open System Settings to allow Motes."
  )
  #expect(
    fixture.runtime.captureFailure?.actions.map(\.title)
      == ["Open Microphone Settings"]
  )
  #expect(fixture.runtime.captureFailure?.message.contains("Apple Speech") == false)
  #expect(fixture.runtime.captureFailure?.message.contains("Speech Recognition") == false)
  #expect(!focused.commands.isFocusedDictationActive)

  availability.value = .evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .denied,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: true,
    foundationModelAvailable: true
  ), enhancedCandidateEnabled: true)
  fixture.provider.error = nil
  await fixture.runtime.toggle()

  #expect(fixture.runtime.captureFailure == nil)
  #expect(fixture.runtime.phase == .listening(mode: .focused, engine: .enhancedLocal))
  #expect(focused.commands.isFocusedDictationActive)

  await fixture.runtime.cancel()
  #expect(fixture.runtime.captureFailure == nil)
}

@Test @MainActor func FocusedEnhancedGlobalFailuresExplainModelArchitectureAndStartup()
  async throws
{
  let scenarios: [(DictationAvailability, Error, String)] = [
    (
      .evaluate(.init(
        osMajorVersion: 26,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .denied,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: false,
        foundationModelAvailable: true
      ), enhancedCandidateEnabled: true),
      DictationFailure.unavailable,
      "Enhanced Local is unavailable because its model is not ready. Open Dictation Settings to download or repair it."
    ),
    (
      .evaluate(.init(
        osMajorVersion: 26,
        architecture: .intel,
        microphonePermission: .authorized,
        speechPermission: .denied,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ), enhancedCandidateEnabled: true),
      DictationFailure.unavailable,
      "Enhanced Local requires Apple silicon."
    ),
    (
      .evaluate(.init(
        osMajorVersion: 26,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .denied,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ), enhancedCandidateEnabled: true),
      DictationSettingsTestError.failed,
      "Enhanced Local could not start. Try again, repair the model in Dictation Settings, or switch to Standard."
    ),
  ]

  for (availability, error, expectedMessage) in scenarios {
    let fixture = try await RuntimeFixture(
      finalText: nil,
      preferredEngine: .enhancedLocal,
      enhancedReadyAtStartup: true,
      availability: availability
    )
    let focused = focusRuntimeEditor(fixture)
    fixture.provider.error = error

    fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
    await fixture.runtime.shortcutController.drainEvents()
    for _ in 0..<20 {
      if fixture.runtime.captureFailure != nil { break }
      await Task.yield()
    }

    #expect(fixture.provider.requestedKinds == [.enhancedLocal])
    #expect(fixture.runtime.captureFailure?.message == expectedMessage)
    #expect(fixture.runtime.captureFailure?.actions.isEmpty == true)
    #expect(fixture.runtime.captureFailure?.message.contains("Apple Speech") == false)
    #expect(fixture.runtime.captureFailure?.message.contains("Speech Recognition") == false)
    #expect(!focused.commands.isFocusedDictationActive)

    fixture.registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
    await fixture.runtime.shortcutController.drainEvents()
  }
}

@Test @MainActor func ShortcutPermissionRequestUsesThePreferredEnhancedEngine()
  async throws
{
  let speechRequests = RuntimeCounter()
  let permissionController = DictationPermissionController(
    microphoneStatus: { .authorized },
    speechStatus: { .notDetermined },
    requestMicrophone: { true },
    requestSpeech: {
      await speechRequests.increment()
      return true
    }
  )
  let fixture = try await RuntimeFixture(
    finalText: nil,
    preferredEngine: .enhancedLocal,
    permissionController: permissionController
  )

  await fixture.runtime.requestPermissionsAfterShortcutSetup()

  #expect(await speechRequests.value == 0)
}
#endif

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor func DictationRepairCapsuleDismissesOnSuccessAndCancellation() async throws {
  let success = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  let successfulTask = success.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in }
  )
  #expect(success.runtime.currentCapsuleStatus == .repairingModel)
  await successfulTask.value
  #expect(success.runtime.currentCapsuleStatus == nil)

  let cancelled = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  let gate = DictationTestGate()
  let cancelledTask = cancelled.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in
      await gate.wait()
      try Task.checkCancellation()
    }
  )
  await gate.waitUntilWaiting()
  #expect(cancelled.runtime.currentCapsuleStatus == .repairingModel)
  cancelled.runtime.cancelModelOperation()
  await gate.open()
  await cancelledTask.value
  #expect(cancelled.runtime.currentCapsuleStatus == nil)
}

@Test @MainActor func DictationRepairCapsuleShowsNonTranscriptFailure() async throws {
  let fixture = try await RuntimeFixture(finalText: "private transcript", capsuleEnabled: true)

  let task = fixture.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in
      throw DictationSettingsTestError.failed
    }
  )
  await task.value

  #expect(fixture.runtime.currentCapsuleStatus == .failed("Enhanced model repair failed."))
  #expect(
    fixture.runtime.currentCapsuleStatus?.presentation.voiceOverText
      .contains("private transcript") == false
  )
}

@Test @MainActor func StaleRepairCompletionCannotDismissANewerRepairStatus() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  let firstGate = DictationTestGate()
  let secondGate = DictationTestGate()
  let first = fixture.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in
      await firstGate.wait()
    }
  )
  await firstGate.waitUntilWaiting()
  let second = fixture.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in
      await secondGate.wait()
    }
  )
  await secondGate.waitUntilWaiting()

  await firstGate.open()
  await first.value
  #expect(fixture.runtime.currentCapsuleStatus == .repairingModel)

  await secondGate.open()
  await second.value
  #expect(fixture.runtime.currentCapsuleStatus == nil)
}

@Test @MainActor func RepairFailureCannotReplaceANewerDictationCapsuleStatus() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  let failureGate = DictationTestGate()
  let repair = fixture.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in
      await failureGate.wait()
      throw DictationSettingsTestError.failed
    }
  )
  await failureGate.waitUntilWaiting()
  #expect(fixture.runtime.currentCapsuleStatus == .repairingModel)

  await fixture.runtime.toggle()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)

  await failureGate.open()
  await repair.value
  #expect(fixture.runtime.currentCapsuleStatus == .listening)

  await fixture.runtime.cancel()
}
#endif

@Test @MainActor func DictationRuntimeShutdownAwaitsCancelledStartupAssessment() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", startupBlocked: true)
  await fixture.startupGate.waitUntilWaiting()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await fixture.startupGate.open()
  await shutdown.value
  #expect(await completed.isComplete)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor func DictationRuntimeShutdownAwaitsModelOperationFilesystemCleanup() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let operationGate = DictationTestGate()
  let cleanupGate = DictationTestGate()
  let file = FileManager.default.temporaryDirectory
    .appendingPathComponent("model-cleanup-\(UUID().uuidString)")
  try Data("partial".utf8).write(to: file)
  let operation = fixture.runtime.runModelOperation(
    operation: { _ in
      await operationGate.wait()
      if Task.isCancelled {
        await cleanupGate.wait()
        try? FileManager.default.removeItem(at: file)
        throw CancellationError()
      }
    }
  )
  await operationGate.waitUntilWaiting()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await operationGate.open()
  await cleanupGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))
  await cleanupGate.open()
  await operation.value
  await shutdown.value
  #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test @MainActor func DictationRuntimeShutdownAwaitsEverySupersededModelCleanup() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let firstOperationGate = DictationTestGate()
  let firstCleanupGate = DictationTestGate()
  let secondOperationGate = DictationTestGate()
  let secondCleanupGate = DictationTestGate()
  let first = fixture.runtime.runModelOperation(
    operation: { _ in
      await firstOperationGate.wait()
      if Task.isCancelled {
        await firstCleanupGate.wait()
        throw CancellationError()
      }
    }
  )
  await firstOperationGate.waitUntilWaiting()

  let second = fixture.runtime.runModelOperation(
    operation: { _ in
      await secondOperationGate.wait()
      if Task.isCancelled {
        await secondCleanupGate.wait()
        throw CancellationError()
      }
    }
  )
  await secondOperationGate.waitUntilWaiting()
  await firstOperationGate.open()
  await firstCleanupGate.waitUntilWaiting()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await secondOperationGate.open()
  await secondCleanupGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))

  await secondCleanupGate.open()
  await second.value
  for _ in 0..<20 {
    if await completed.isComplete { break }
    await Task.yield()
  }
  #expect(!(await completed.isComplete))

  await firstCleanupGate.open()
  await first.value
  await shutdown.value
  #expect(await completed.isComplete)
}
#endif

@Test @MainActor func DictationRuntimeShutdownAwaitsSuspendedProviderAndLateRelease() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let providerGate = DictationTestGate()
  let releaseGate = DictationTestGate()
  fixture.provider.gate = providerGate
  fixture.engine.releaseGate = releaseGate
  let starting = Task { await fixture.runtime.toggle() }
  await fixture.provider.waitUntilRequested()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await providerGate.open()
  await releaseGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))
  await releaseGate.open()
  await starting.value
  await shutdown.value
  #expect(fixture.engine.releaseCount == 1)
}

@Test @MainActor func DictationRuntimeShutdownAwaitsSuspendedFinishAndLateRelease() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let finishGate = DictationTestGate()
  let releaseGate = DictationTestGate()
  fixture.engine.finishGate = finishGate
  fixture.engine.releaseGate = releaseGate
  await fixture.runtime.toggle()
  let finishing = Task { await fixture.runtime.toggle() }
  await finishGate.waitUntilWaiting()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await finishGate.open()
  await releaseGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))
  await releaseGate.open()
  await finishing.value
  await shutdown.value
  #expect(fixture.engine.releaseCount == 1)
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

@MainActor
private func focusRuntimeEditor(
  _ fixture: RuntimeFixture
) -> (commands: EditorCommands, window: NSWindow) {
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  commands.textView = textView
  fixture.editorRegistry.register(commands)
  window.makeFirstResponder(textView)
  return (commands, window)
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
  let engine: RuntimeSpeechEngine
  let provider: RuntimeEngineProvider
  let history: DictationHistoryController
  let editorRegistry = DictationEditorRegistry()
  var runtime: DictationRuntime!

  init(
    finalText: String?,
    startupBlocked: Bool = false,
    capsuleEnabled: Bool = false,
    preferredEngine: DictationSpeechEngine = .standard,
    enhancedReadyAtStartup: Bool = false,
    permissionController: DictationPermissionController = .init(),
    availability: DictationAvailability = .evaluate(.init(
      osMajorVersion: 26,
      architecture: .appleSilicon,
      microphonePermission: .authorized,
      speechPermission: .authorized,
      appleOnDeviceRecognitionSupported: true,
      enhancedModelReady: true,
      foundationModelAvailable: true
    )),
    availabilityProvider: (@MainActor () -> DictationAvailability)? = nil
  ) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-\(UUID().uuidString)", isDirectory: true)
    let store = LocalStore(rootURL: root)
    let preferences = AppPreferences(
      dictationSpeechEngine: preferredEngine,
      dictationShortcut: DictationShortcut(keyCode: 49, carbonModifiers: 768),
      dictationCapsuleEnabled: capsuleEnabled
    )
    var workspace = Workspace()
    workspace.ensureNoteExists()
    let persistedSelectedNoteID = workspace.selectedNoteID
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: []
    )
    appState = AppState(store: store, saveOperation: { _, _, _ in })
    for _ in 0..<100 {
      if appState.selectedNote?.id == persistedSelectedNoteID { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    guard appState.selectedNote?.id == persistedSelectedNoteID else {
      throw DictationSettingsTestError.failed
    }
    appState.preferences = preferences
    enhancedReady.value = enhancedReadyAtStartup
    engine = RuntimeSpeechEngine(finalText: finalText, kind: preferredEngine)
    provider = RuntimeEngineProvider(engine: engine)
    history = DictationHistoryController(
      load: { [] },
      save: { _ in },
      delete: { _ in },
      clear: {}
    )
    let coordinator = DictationCoordinator(
      engineProvider: provider,
      preferredEngine: { [weak appState] in
        appState?.preferences.dictationSpeechEngine ?? .standard
      },
      cleaner: RuntimeCleaner(),
      router: RuntimeRouter(),
      saver: appState,
      historyController: history,
      historyEnabled: { true },
      holdThreshold: .zero,
      holdSleeper: { _ in }
    )
    let shortcut = GlobalHoldShortcut(
      handler: coordinator,
      editorProvider: { [editorRegistry] in editorRegistry.focusedEditor() },
      destinationProvider: { [weak appState] in
        appState?.selectedNote.map {
          DictationDestination(noteID: $0.id, title: $0.displayTitle)
        }
      },
      registrar: registrar
    )
    let modelRoot = root.appendingPathComponent("model", isDirectory: true)
    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      let modelManager = DictationModelCapability(
        modelRootURL: modelRoot,
        candidateEnabled: true,
        architectureProvider: { true }
      )
    #else
      let modelManager = DictationModelCapability()
    #endif
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
      permissionController: permissionController,
      editorRegistry: editorRegistry,
      startupAssessment: {
        await log.increment()
        if startupBlocked { await gate.wait() }
      },
      enhancedIsReady: { [enhancedReady] in enhancedReady.value },
      availabilityProvider: availabilityProvider ?? { availability }
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
  var gate: DictationTestGate?
  var error: Error?
  private(set) var requestedKinds: [DictationSpeechEngine] = []
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requestCount = 0

  init(engine: RuntimeSpeechEngine) {
    self.engine = engine
  }

  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
    requestCount += 1
    requestedKinds.append(preferred)
    let waiters = requestWaiters
    requestWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if let gate { await gate.wait() }
    if let error { throw error }
    return engine
  }

  func waitUntilRequested() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }
}

@MainActor
private final class RuntimeSpeechEngine: SpeechEngine {
  let kind: DictationSpeechEngine
  let finalText: String?
  var finishGate: DictationTestGate?
  var releaseGate: DictationTestGate?
  private(set) var releaseCount = 0

  init(finalText: String?, kind: DictationSpeechEngine = .standard) {
    self.finalText = finalText
    self.kind = kind
  }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {}

  func finish() async throws -> String? {
    if let finishGate { await finishGate.wait() }
    return finalText
  }

  func cancel() async {}
  func releaseResources() async {
    releaseCount += 1
    if let releaseGate { await releaseGate.wait() }
  }
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

@MainActor
private final class RuntimeAvailabilityBox {
  var value: DictationAvailability

  init(_ value: DictationAvailability) {
    self.value = value
  }
}

private actor RuntimeCompletionProbe {
  private(set) var isComplete = false

  func complete() {
    isComplete = true
  }
}
