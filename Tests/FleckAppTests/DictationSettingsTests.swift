import AppKit
import Foundation
import FleckCore
import Testing

@testable import FleckApp

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
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .finalizing,
    terminal: nil
  )) == .finalizing)
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .cleaning,
    terminal: nil
  )) == .cleaning)
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .routing,
    terminal: nil
  )) == .routing)
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .idle,
    terminal: .cancelled
  )) == .idle)
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

@Test func dictationModifierSettingsShowsAllPhysicalKeysAndItsRunningStatus() {
  let presentation = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .running,
    canChange: true
  )

  #expect(presentation.rows.count == 7)
  #expect(presentation.recommended == .rightOption)
  #expect(presentation.statusCopy == "Input Monitoring enabled")
  #expect(presentation.isPickerEnabled)
  #expect(presentation.recoveryAction == nil)
}

@Test func dictationModifierSettingsShowsDeniedUnavailableRetryAndActiveCaptureCopy() {
  let denied = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .unauthorized,
    canChange: true
  )
  #expect(denied.statusCopy.contains("required"))
  #expect(denied.recoveryAction == .enableInputMonitoring)
  #expect(denied.recoveryButtonTitle == "Enable Right Option")

  let unavailable = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .stopped,
    canChange: true
  )
  #expect(unavailable.statusCopy.contains("unavailable"))

  let failed = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .failed,
    canChange: true
  )
  #expect(failed.statusCopy.contains("could not start"))
  #expect(failed.recoveryAction == .retry)
  #expect(failed.recoveryButtonTitle == "Retry Right Option")

  let activeCapture = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .running,
    canChange: false
  )
  #expect(!activeCapture.isPickerEnabled)
  #expect(activeCapture.statusCopy.contains("finish"))
  #expect(activeCapture.recoveryButtonTitle == nil)

  let deniedDuringCapture = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .unauthorized,
    canChange: false
  )
  #expect(deniedDuringCapture.recoveryButtonTitle == nil)
}

@Test func notesPanelExposesModifierMonitoringRecoveryBesideTheEditor() throws {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: testsDirectory.appendingPathComponent("Sources/FleckApp/NotesPanel.swift")
  )

  #expect(source.contains("modifierRecoveryPresentation"))
  #expect(source.contains("await dictationRuntime.recoverModifierMonitoring()"))
}

@Test func dictationModifierSettingsExplainsFnAndConflictProneKeys() {
  let function = DictationModifierSettingsPresentation(
    selected: .function,
    monitorStatus: .running,
    canChange: true
  )
  #expect(function.guidanceCopy?.contains("best-effort") == true)

  for key in [
    DictationModifierKey.leftCommand,
    .rightCommand,
    .leftOption,
    .leftControl,
    .rightControl,
  ] {
    let presentation = DictationModifierSettingsPresentation(
      selected: key,
      monitorStatus: .running,
      canChange: true
    )
    #expect(presentation.guidanceCopy?.contains("conflict") == true)
  }
}

@Test func settingsSourceDoesNotInstantiateTheLegacyShortcutRecorder() throws {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: testsDirectory.appendingPathComponent("Sources/FleckApp/SettingsView.swift")
  )

  #expect(!source.contains("DictationShortcutRecorder("))
  #expect(source.contains("Button(\"Enable Input Monitoring\")"))
  #expect(source.contains("await runtime.recoverModifierMonitoring()"))
  #expect(source.contains("runtime.openSystemSettings(settings)"))
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

@Test @MainActor func DictationRuntimeWaitsForLoadedModifierWithoutRequestingAccess()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    preferredModifier: .leftCommand,
    waitForInitialLoadBeforeRuntime: false
  )

  #expect(fixture.runtime.actualModifier == nil)
  #expect(fixture.monitor.requestCount == 0)

  await fixture.appState.waitUntilInitialLoad()
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.actualModifier == .leftCommand)
  #expect(fixture.monitor.requestCount == 0)
}

@Test @MainActor func DictationRuntimeLoadsCapsuleVisibilityAndDockBeforeFirstPresentation()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: false,
    preferredDock: .left,
    waitForInitialLoadBeforeRuntime: false
  )

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)

  await fixture.appState.waitUntilInitialLoad()
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.currentDock == .left)
  #expect(fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)
}

@Test @MainActor func DictationRuntimeSyncsCapsuleWhenModifierMonitorFailsToStart()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: true,
    preferredModifier: .leftCommand,
    waitForInitialLoadBeforeRuntime: false,
    blockInitialLoad: true
  )
  let blocker = try #require(fixture.initialLoadBlocker)
  fixture.monitor.startError = DictationSettingsTestError.failed

  blocker.release()
  await fixture.appState.waitUntilInitialLoad()
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.modifierMonitorState == .failed)
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.panel.isVisible)
}

@Test @MainActor func DictationRuntimeBuffersCapsuleEventsUntilLoadedPreferencesAreApplied()
  async throws
{
  for capsuleEnabled in [false, true] {
    let fixture = try await RuntimeFixture(
      finalText: "saved",
      capsuleEnabled: capsuleEnabled,
      preferredDock: .left,
      waitForInitialLoadBeforeRuntime: false,
      blockInitialLoad: true
    )
    guard let loadBlocker = fixture.initialLoadBlocker else {
      Issue.record("Expected a deterministic initial-load blocker")
      continue
    }
    defer { loadBlocker.release() }
    for _ in 0..<1_000 {
      if loadBlocker.hasBlocked { break }
      await Task.yield()
    }
    guard loadBlocker.hasBlocked else {
      Issue.record("Initial load did not reach the deterministic blocker")
      continue
    }
    let orderProbe = RuntimeCapsuleOrderProbe(panel: fixture.runtime.capsuleController.panel)
    defer { orderProbe.stop() }

    await fixture.runtime.toggle()

    #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
    #expect(fixture.runtime.currentCapsuleStatus == nil)
    #expect(!fixture.runtime.capsuleController.panel.isVisible)
    #expect(orderProbe.count == 0)

    loadBlocker.release()
    await fixture.appState.waitUntilInitialLoad()
    await fixture.runtime.awaitStartupAssessment()

    #expect(fixture.runtime.capsuleController.currentDock == .left)
    if capsuleEnabled {
      #expect(fixture.runtime.currentCapsuleStatus == .listening)
      #expect(fixture.runtime.capsuleController.panel.isVisible)
      #expect(orderProbe.count == 1)
    } else {
      #expect(fixture.runtime.currentCapsuleStatus == nil)
      #expect(!fixture.runtime.capsuleController.panel.isVisible)
      #expect(orderProbe.count == 0)

      fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
      fixture.runtime.preferencesDidChange()
      #expect(fixture.runtime.currentCapsuleStatus == .listening)
      #expect(fixture.runtime.capsuleController.panel.isVisible)
      #expect(orderProbe.count == 1)
    }

    await fixture.runtime.cancel()
  }
}

@Test @MainActor func DictationRuntimeReturnTimersCannotReplaceNewerListeningState()
  async throws
{
  for (finalText, delay) in [
    ("saved", Duration.milliseconds(1_600)),
    (nil, Duration.seconds(3)),
  ] as [(String?, Duration)] {
    let sleeper = RuntimeCapsuleSleeper()
    let fixture = try await RuntimeFixture(
      finalText: finalText,
      capsuleEnabled: true,
      capsuleSleeper: { duration in await sleeper.sleep(duration) }
    )
    await fixture.runtime.awaitStartupAssessment()

    await fixture.runtime.toggle()
    await fixture.runtime.toggle()
    await sleeper.waitForRequest()
    #expect(await sleeper.requestedDurations == [delay])

    await fixture.runtime.toggle()
    #expect(fixture.runtime.currentCapsuleStatus == .listening)
    await sleeper.resumeAll()
    await Task.yield()
    #expect(fixture.runtime.currentCapsuleStatus == .listening)

    await fixture.runtime.cancel()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
  }
}

@Test @MainActor func DictationRuntimeDoesNotReplayTerminalUpdatesReceivedWhileDisabled()
  async throws
{
  for finalText in ["saved", nil] as [String?] {
    let sleeper = RuntimeCapsuleSleeper()
    let fixture = try await RuntimeFixture(
      finalText: finalText,
      capsuleEnabled: false,
      capsuleSleeper: { duration in await sleeper.sleep(duration) }
    )
    await fixture.runtime.awaitStartupAssessment()

    await fixture.runtime.toggle()
    await fixture.runtime.toggle()
    await Task.yield()
    #expect(fixture.runtime.currentCapsuleStatus == nil)
    #expect(await sleeper.requestedDurations.isEmpty)

    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
    fixture.runtime.preferencesDidChange()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
    if fixture.runtime.currentCapsuleStatus != .idle {
      await sleeper.waitForRequest()
    }
    #expect(await sleeper.requestedDurations.isEmpty)
    await sleeper.resumeAll()
  }

  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  let preflight = try await RuntimeFixture(
    finalText: nil,
    capsuleEnabled: false,
    availability: availability
  )
  await preflight.runtime.awaitStartupAssessment()
  await preflight.runtime.toggle()
  preflight.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  preflight.runtime.preferencesDidChange()
  #expect(preflight.runtime.currentCapsuleStatus == .idle)
}

@Test @MainActor func DictationRuntimeClearsVisibleTerminalReplayWhenDisabled()
  async throws
{
  for (finalText, delay) in [
    ("saved", Duration.milliseconds(1_600)),
    (nil, Duration.seconds(3)),
  ] as [(String?, Duration)] {
    let sleeper = RuntimeCapsuleSleeper()
    let fixture = try await RuntimeFixture(
      finalText: finalText,
      capsuleEnabled: true,
      capsuleSleeper: { duration in await sleeper.sleep(duration) }
    )
    await fixture.runtime.awaitStartupAssessment()

    await fixture.runtime.toggle()
    await fixture.runtime.toggle()
    await sleeper.waitForRequest()
    #expect(await sleeper.requestedDurations == [delay])

    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
    fixture.runtime.preferencesDidChange()
    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
    fixture.runtime.preferencesDidChange()

    #expect(fixture.runtime.currentCapsuleStatus == .idle)
    if fixture.runtime.currentCapsuleStatus != .idle {
      for _ in 0..<1_000 {
        if await sleeper.requestedDurations.count >= 2 { break }
        await Task.yield()
      }
    }
    await sleeper.resumeAll()
    await Task.yield()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
    #expect(await sleeper.requestedDurations == [delay])
  }
}

@Test @MainActor func DictationRuntimeReplaysLiveDictationWhenReenabled() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: false)
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  #expect(fixture.runtime.currentCapsuleStatus == nil)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)

  await fixture.runtime.cancel()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
}

@Test @MainActor func DictationRuntimeForwardsLevelsOnlyToAnActiveVisibleCapsule() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: false)
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  fixture.engine.emitLevel(0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  fixture.engine.emitLevel(0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)

  await fixture.runtime.cancel()
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
  fixture.engine.emitLevel(1)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
}

@Test @MainActor func DictationRuntimeUsesCoordinatorEventsAndAppliesModifierAfterTerminal() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let replacement = DictationModifierKey.leftCommand
  await fixture.runtime.awaitStartupAssessment()
  #expect(!DictationRuntime.usesPeriodicObservation)

  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
  fixture.appState.preferences.dictationModifierKey = replacement
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.actualModifier != replacement)

  await fixture.runtime.toggle()
  await fixture.runtime.waitForTerminalSynchronization()
  #expect(fixture.runtime.actualModifier == replacement)
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
  await fixture.runtime.awaitStartupAssessment()

  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.runtime.shortcutController.drainEvents()
  for _ in 0..<20 {
    if case .listening = fixture.runtime.phase { break }
    await Task.yield()
  }
  fixture.monitor.emit(.released(.rightOption))
  await fixture.runtime.shortcutController.drainEvents()
  await fixture.runtime.waitForTerminalSynchronization()

  let record = try #require(fixture.history.records.first)
  #expect(record.mode == .focused)
  #expect(record.destination == .init(noteID: selected.id, title: selected.displayTitle))
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func DictationRuntimeAppliesPendingModifierAfterSavedAndFailedSessions()
  async throws
{
  for finalText in ["saved", nil] as [String?] {
    let fixture = try await RuntimeFixture(finalText: finalText)
    await fixture.runtime.awaitStartupAssessment()
    let replacement = DictationModifierKey.leftCommand

    fixture.monitor.emit(.pressed(.rightOption))
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

    fixture.appState.updatePreferences { $0.dictationModifierKey = replacement }
    fixture.runtime.preferencesDidChange()
    fixture.monitor.emit(.released(.rightOption))
    await fixture.runtime.shortcutController.drainEvents()
    await fixture.runtime.waitForTerminalSynchronization()

    #expect(fixture.runtime.actualModifier == replacement)
    if finalText == nil {
      #expect(fixture.runtime.phase == .failed("No speech detected."))
    } else {
      let inbox = try #require(
        fixture.appState.activeDestinations().first {
          $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
        }
      )
      #expect(fixture.runtime.phase == .saved(inbox))
    }
  }
}

@Test @MainActor func DictationRuntimeDeniedModifierChangePreservesActiveAndStoredModifier()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  let old = fixture.appState.preferences.dictationModifierKey
  fixture.monitor.accessGranted = false
  fixture.monitor.requestAccessResult = false

  let changed = await fixture.runtime.changeModifier(to: .leftCommand)

  #expect(!changed)
  #expect(fixture.runtime.actualModifier == old)
  #expect(fixture.appState.preferences.dictationModifierKey == old)
  #expect(fixture.monitor.stopCount == 0)
}

@Test @MainActor func DictationRuntimeEnablesStoredModifierAfterAccessIsGranted()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    preferredModifier: .leftCommand,
    monitorAccessGranted: false,
    monitorRequestAccessResult: false
  )
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.monitor.requestCount == 0)
  #expect(fixture.runtime.modifierMonitorState == .unauthorized)
  #expect(fixture.runtime.actualModifier == nil)
  #expect(fixture.appState.preferences.dictationModifierKey == .leftCommand)

  fixture.monitor.accessGranted = true
  fixture.runtime.applicationDidBecomeActive()
  #expect(fixture.runtime.modifierMonitorState == .running)
  #expect(fixture.runtime.actualModifier == .leftCommand)
  #expect(fixture.appState.preferences.dictationModifierKey == .leftCommand)
}

@Test @MainActor func DictationRuntimeModifierRecoveryReturnsSettingsOnlyWhenAccessIsDenied()
  async throws
{
  let denied = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: false
  )
  await denied.runtime.awaitStartupAssessment()

  let recovery = await denied.runtime.recoverModifierMonitoring()

  #expect(recovery?.pane == .inputMonitoring)
  #expect(denied.monitor.requestCount == 1)
  #expect(denied.runtime.modifierMonitorState == .unauthorized)
  #expect(denied.runtime.actualModifier == nil)

  let granted = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: true
  )
  await granted.runtime.awaitStartupAssessment()

  let noRecovery = await granted.runtime.recoverModifierMonitoring()

  #expect(noRecovery == nil)
  #expect(granted.monitor.requestCount == 1)
  #expect(granted.runtime.modifierMonitorState == .running)
  #expect(granted.runtime.actualModifier == .rightOption)
}

@Test @MainActor func DictationRuntimeNeverRequestsModifierMonitoringAtStartup() async throws {
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: true
  )

  await fixture.runtime.awaitStartupAssessment()
  fixture.runtime.preferencesDidChange()

  #expect(fixture.monitor.requestCount == 0)
  #expect(fixture.runtime.modifierMonitorState == .unauthorized)
  #expect(fixture.runtime.actualModifier == nil)
}

@Test @MainActor func DictationRuntimeRunningMonitorChangesWithoutRestart()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  fixture.monitor.startError = DictationSettingsTestError.failed

  let changed = await fixture.runtime.changeModifier(to: .leftCommand)

  #expect(changed)
  #expect(fixture.runtime.actualModifier == .leftCommand)
  #expect(fixture.appState.preferences.dictationModifierKey == .leftCommand)
  #expect(fixture.monitor.startCount == 1)
  #expect(fixture.monitor.stopCount == 0)
}

@Test @MainActor func DictationRuntimeFailedRestartPreservesStoredSemanticModifier()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  let old = fixture.appState.preferences.dictationModifierKey
  fixture.monitor.publish(.failed)
  await fixture.runtime.shortcutController.drainEvents()
  fixture.monitor.startError = DictationSettingsTestError.failed

  let changed = await fixture.runtime.changeModifier(to: .leftCommand)

  #expect(!changed)
  #expect(fixture.appState.preferences.dictationModifierKey == old)
  #expect(fixture.runtime.shortcutController.registeredModifier == old)
  #expect(fixture.runtime.actualModifier == nil)
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

@Test @MainActor func DictationRuntimePreflightFailureUsesProtectedCapsuleReturnTimer()
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
  let sleeper = RuntimeCapsuleSleeper()
  let fixture = try await RuntimeFixture(
    finalText: "Saved",
    capsuleEnabled: true,
    availabilityProvider: { availability.value },
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()

  guard
    fixture.runtime.currentCapsuleStatus
      == .failed(availability.value.standardFailureCopy ?? "")
  else {
    Issue.record("Expected preflight failure capsule")
    return
  }
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [Duration.seconds(3)])

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
  #expect(fixture.runtime.currentCapsuleStatus == .listening)

  await sleeper.resumeAll()
  await Task.yield()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)
  await fixture.runtime.cancel()
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
  await fixture.runtime.awaitStartupAssessment()

  fixture.monitor.emit(.pressed(.rightOption))
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
      == "Enhanced Local needs Microphone access. Open System Settings to allow Fleck."
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
    await fixture.runtime.awaitStartupAssessment()

    fixture.monitor.emit(.pressed(.rightOption))
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

    fixture.monitor.emit(.released(.rightOption))
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
@Test @MainActor func DictationRuntimeReplaysOnlyAnActiveModelRepairWhenReenabled()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: false)
  let gate = DictationTestGate()
  await fixture.runtime.awaitStartupAssessment()
  let repair = fixture.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in await gate.wait() }
  )
  await gate.waitUntilWaiting()
  #expect(fixture.runtime.currentCapsuleStatus == nil)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .repairingModel)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .repairingModel)

  await gate.open()
  await repair.value
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
}

@Test @MainActor func DictationRepairCapsuleReturnsToIdleOnSuccessAndCancellation() async throws {
  let success = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  let successfulTask = success.runtime.runModelOperation(
    showsRepairStatus: true,
    operation: { _ in }
  )
  #expect(success.runtime.currentCapsuleStatus == .repairingModel)
  await successfulTask.value
  #expect(success.runtime.currentCapsuleStatus == .idle)

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
  #expect(cancelled.runtime.currentCapsuleStatus == .idle)
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
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
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
  let monitor = RuntimeModifierMonitor()
  let escapeRegistrar = RuntimeEscapeRegistrar()
  let startupGate = DictationTestGate()
  let startupLog = RuntimeCounter()
  let enhancedReady = RuntimeBool()
  let engine: RuntimeSpeechEngine
  let provider: RuntimeEngineProvider
  let history: DictationHistoryController
  let editorRegistry = DictationEditorRegistry()
  let initialLoadBlocker: RuntimeBlockingFileManager?
  var runtime: DictationRuntime!

  init(
    finalText: String?,
    startupBlocked: Bool = false,
    capsuleEnabled: Bool = false,
    preferredEngine: DictationSpeechEngine = .standard,
    preferredModifier: DictationModifierKey = .rightOption,
    preferredDock: DictationCapsuleDock = .bottom,
    waitForInitialLoadBeforeRuntime: Bool = true,
    blockInitialLoad: Bool = false,
    monitorAccessGranted: Bool = true,
    monitorRequestAccessResult: Bool = true,
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
    availabilityProvider: (@MainActor () -> DictationAvailability)? = nil,
    capsuleSleeper: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-\(UUID().uuidString)", isDirectory: true)
    initialLoadBlocker = blockInitialLoad ? RuntimeBlockingFileManager() : nil
    let store: LocalStore
    if let initialLoadBlocker {
      nonisolated(unsafe) let fileManager: FileManager = initialLoadBlocker
      store = LocalStore(rootURL: root, fileManager: fileManager)
    } else {
      store = LocalStore(rootURL: root)
    }
    let preferences = AppPreferences(
      dictationSpeechEngine: preferredEngine,
      dictationModifierKey: preferredModifier,
      dictationCapsuleDock: preferredDock,
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
    initialLoadBlocker?.beginBlocking()
    appState = AppState(store: store, saveOperation: { _, _, _ in })
    if waitForInitialLoadBeforeRuntime {
      for _ in 0..<100 {
        if appState.selectedNote?.id == persistedSelectedNoteID { break }
        try await Task.sleep(for: .milliseconds(1))
      }
      guard appState.selectedNote?.id == persistedSelectedNoteID else {
        throw DictationSettingsTestError.failed
      }
      appState.preferences = preferences
    }
    monitor.accessGranted = monitorAccessGranted
    monitor.requestAccessResult = monitorRequestAccessResult
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
      monitor: monitor,
      escapeRegistrar: escapeRegistrar
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
      availabilityProvider: availabilityProvider ?? { availability },
      capsuleSleeper: capsuleSleeper
    )
  }

  func releaseRuntime() {
    runtime = nil
  }
}

@MainActor
private final class RuntimeModifierMonitor: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  var accessGranted = true
  var requestAccessResult = true
  var startError: Error?
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var requestCount = 0

  func start() throws {
    startCount += 1
    if let startError { throw startError }
    stateHandler?(.running)
  }

  func stop() {
    stopCount += 1
    stateHandler?(.stopped)
  }

  func requestAccess() -> Bool {
    requestCount += 1
    accessGranted = requestAccessResult
    return requestAccessResult
  }

  func emit(_ transition: ModifierKeyTransition) {
    transitionHandler?(transition)
  }

  func publish(_ state: ModifierMonitorState) {
    stateHandler?(state)
  }
}

@MainActor
private final class RuntimeEscapeRegistrar: EscapeHotKeyRegistering {
  var eventHandler: (() -> Void)?

  func register() throws {}
  func unregister() {}
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
  private var level: (@MainActor (Float) -> Void)?

  init(finalText: String?, kind: DictationSpeechEngine = .standard) {
    self.finalText = finalText
    self.kind = kind
  }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {
    self.level = level
  }

  func finish() async throws -> String? {
    if let finishGate { await finishGate.wait() }
    return finalText
  }

  func cancel() async {}
  func emitLevel(_ value: Float) { level?(value) }
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

private actor RuntimeCapsuleSleeper {
  private(set) var requestedDurations: [Duration] = []
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var requestObservers: [CheckedContinuation<Void, Never>] = []

  func sleep(_ duration: Duration) async {
    requestedDurations.append(duration)
    let observers = requestObservers
    requestObservers.removeAll()
    observers.forEach { $0.resume() }
    await withCheckedContinuation { continuations.append($0) }
  }

  func waitForRequest() async {
    guard requestedDurations.isEmpty else { return }
    await withCheckedContinuation { requestObservers.append($0) }
  }

  func resumeAll() {
    let pending = continuations
    continuations.removeAll()
    pending.forEach { $0.resume() }
  }
}

private final class RuntimeBlockingFileManager: FileManager, @unchecked Sendable {
  private let lock = NSLock()
  private let releaseSemaphore = DispatchSemaphore(value: 0)
  private var isBlocking = false
  private var didBlock = false

  var hasBlocked: Bool {
    lock.withLock { didBlock }
  }

  func beginBlocking() {
    lock.withLock {
      isBlocking = true
      didBlock = false
    }
  }

  func release() {
    let shouldSignal = lock.withLock {
      let shouldSignal = isBlocking
      isBlocking = false
      return shouldSignal
    }
    if shouldSignal {
      releaseSemaphore.signal()
    }
  }

  override func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]? = nil
  ) throws {
    try super.createDirectory(
      at: url,
      withIntermediateDirectories: createIntermediates,
      attributes: attributes
    )
    let shouldBlock = lock.withLock {
      guard isBlocking else { return false }
      didBlock = true
      return true
    }
    if shouldBlock {
      releaseSemaphore.wait()
    }
  }
}

@MainActor
private final class RuntimeCapsuleOrderProbe: NSObject {
  private(set) var count = 0
  private let panel: NSPanel

  init(panel: NSPanel) {
    self.panel = panel
    super.init()
    panel.addObserver(
      self,
      forKeyPath: "visible",
      options: [.new],
      context: nil
    )
  }

  func stop() {
    panel.removeObserver(self, forKeyPath: "visible")
  }

  override nonisolated func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    guard
      keyPath == "visible",
      change?[.newKey] as? Bool == true
    else { return }
    MainActor.assumeIsolated {
      count += 1
    }
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
