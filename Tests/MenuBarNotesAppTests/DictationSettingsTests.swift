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
