import AppKit
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func personalDictionarySettingsLoadsAllEntriesAndSuggestionsInStableOrder() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  try await store.upsert(settingsEntry(3, "zeta", aliases: ["Last term"]))
  try await store.upsert(settingsEntry(2, "Alpha", enabled: false))
  try await store.upsert(settingsEntry(1, "alpha", aliases: ["First term"]))
  try await store.recordSuggestion(settingsSuggestion(5, "Beta", observed: ["B term"]))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)

  await viewModel.load()

  #expect(viewModel.revision == 4)
  #expect(viewModel.entries.map(\.id) == [settingsUUID(2), settingsUUID(1), settingsUUID(3)])
  #expect(viewModel.suggestions.map(\.preferredForm) == ["Beta"])
  #expect(
    viewModel.visibleEntries.map(\.id) == [settingsUUID(2), settingsUUID(1), settingsUUID(3)]
  )
  #expect(viewModel.visibleEntries.map(\.isEnabled) == [false, true, true])
  #expect(viewModel.visibleSuggestions.isEmpty)

  viewModel.query = "FIRST TERM"
  #expect(viewModel.visibleEntries.map(\.preferredForm) == ["alpha"])

  viewModel.filter = .suggestions
  viewModel.query = "b TERM"
  #expect(viewModel.visibleEntries.isEmpty)
  #expect(viewModel.visibleSuggestions.map(\.preferredForm) == ["Beta"])
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySuggestionHeaderActionTracksQueueAndKeepsAnExitAfterDismissal() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let firstSuggestion = settingsSuggestion(1, "First suggestion")
  let lastSuggestion = settingsSuggestion(2, "Last suggestion")
  try await store.recordSuggestion(firstSuggestion)
  try await store.recordSuggestion(lastSuggestion)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)

  #expect(viewModel.suggestionsHeaderActionTitle == nil)
  await viewModel.load()
  #expect(viewModel.suggestionsHeaderActionTitle == "Review suggestions (2)")

  await viewModel.dismissSuggestion(
    id: firstSuggestion.id,
    expectedRevision: viewModel.revision
  )
  #expect(viewModel.suggestionsHeaderActionTitle == "Review suggestions (1)")

  viewModel.filter = .suggestions
  #expect(viewModel.suggestionsHeaderActionTitle == "Back to words")
  await viewModel.dismissSuggestion(
    id: lastSuggestion.id,
    expectedRevision: viewModel.revision
  )
  #expect(viewModel.suggestions.isEmpty)
  #expect(viewModel.suggestionsHeaderActionTitle == "Back to words")

  viewModel.filter = .all
  #expect(viewModel.suggestionsHeaderActionTitle == nil)
}

@Test @MainActor
func personalDictionarySettingsBindsAddEnableAndDeleteToDisplayedRevision() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.add(
    preferredForm: "  FleckApp \n",
    aliases: " fleck app, Fleck application\n fleck app ",
    expectedRevision: viewModel.revision
  )
  #expect(viewModel.revision == 1)
  #expect(viewModel.entries[0].preferredForm == "FleckApp")
  #expect(viewModel.entries[0].aliases == ["fleck app", "Fleck application"])

  let id = viewModel.entries[0].id
  let enabledRevision = viewModel.revision
  await viewModel.setEnabled(false, id: id, expectedRevision: enabledRevision)
  #expect(viewModel.revision == 2)
  #expect(viewModel.entries[0].isEnabled == false)

  await viewModel.delete(id: id, expectedRevision: viewModel.revision)
  #expect(viewModel.revision == 3)
  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsPriorityUsesDisplayedRevisionAndPersists() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(11, "Fleck")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.setPriority(true, id: entry.id, expectedRevision: viewModel.revision)

  #expect(viewModel.entries.first?.isPriority == true)
  #expect(viewModel.errorMessage == nil)

  let reloadedViewModel = PersonalDictionarySettingsViewModel(store: store)
  await reloadedViewModel.load()
  #expect(reloadedViewModel.entries.first?.isPriority == true)
}

@Test @MainActor
func personalDictionarySettingsDoesNotRebaseConcurrentPriorityChanges() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(12, "Dictionary")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .setPriority(true, id: entry.id)
  )
  await viewModel.setPriority(false, id: entry.id, expectedRevision: displayedRevision)

  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.entries.first?.isPriority == true)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionaryRowDeletionWaitsForConfirmationBeforeMutating() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(13, "Remove only after confirmation")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision

  viewModel.requestEntryDeletion(entry, expectedRevision: displayedRevision)

  #expect(viewModel.pendingEntryDeletion?.id == entry.id)
  #expect(viewModel.pendingEntryDeletion?.expectedRevision == displayedRevision)
  #expect(viewModel.entries.map(\.id) == [entry.id])
  #expect(viewModel.revision == displayedRevision)

  viewModel.cancelEntryDeletion()
  #expect(viewModel.pendingEntryDeletion == nil)
  #expect(viewModel.entries.map(\.id) == [entry.id])
  #expect(viewModel.revision == displayedRevision)

  viewModel.requestEntryDeletion(entry, expectedRevision: displayedRevision)
  await viewModel.confirmEntryDeletion()

  #expect(viewModel.pendingEntryDeletion == nil)
  #expect(!viewModel.isEntryDeletionInFlight)
  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.revision == displayedRevision + 1)
}

@Test @MainActor
func personalDictionaryRowDeletionRejectsAStaleDisplayedRevision() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(14, "Concurrent delete")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision
  viewModel.requestEntryDeletion(entry, expectedRevision: displayedRevision)

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .upsert(settingsEntry(15, "Newer entry"))
  )
  await viewModel.confirmEntryDeletion()

  #expect(viewModel.entries.map(\.id) == [entry.id, settingsUUID(15)])
  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionaryEntryEditorPreservesIdentityAndMetadataWhenSavingCorrections() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let original = PersonalDictionaryEntry(
    id: settingsUUID(9),
    preferredForm: "Fleck",
    aliases: ["flick"],
    localeIdentifier: "en-GB",
    isPriority: true,
    isEnabled: false,
    origin: .suggested,
    usage: .init(useCount: 12, lastUsedAt: Date(timeIntervalSince1970: 4_200))
  )
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  viewModel.beginEditingEntry(original)
  #expect(viewModel.entryEdit?.id == original.id)
  #expect(viewModel.entryEdit?.isNew == false)
  #expect(viewModel.entryEditUsesCorrection == true)
  viewModel.entryEditPreferredForm = "Fleck App"
  viewModel.entryEditAliases = "flick app, fleck application\nflick app"
  await viewModel.submitEntryEdit()

  let saved = try #require(viewModel.entries.first)
  #expect(saved.id == original.id)
  #expect(saved.preferredForm == "Fleck App")
  #expect(saved.aliases == ["flick app", "fleck application"])
  #expect(saved.localeIdentifier == original.localeIdentifier)
  #expect(saved.isPriority == original.isPriority)
  #expect(saved.isEnabled == original.isEnabled)
  #expect(saved.origin == original.origin)
  #expect(saved.usage == original.usage)
  #expect(viewModel.entryEdit == nil)
}

@Test @MainActor
func personalDictionaryEntryEditorMapsCorrectionToggleAndDeletesFromTheEditor() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let original = settingsEntry(7, "Parakeet", aliases: ["parrot key"])
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  viewModel.beginEditingEntry(original)
  viewModel.entryEditUsesCorrection = false
  await viewModel.submitEntryEdit()
  #expect(viewModel.entries.first?.aliases == [])

  viewModel.beginEditingEntry(try #require(viewModel.entries.first))
  await viewModel.deleteEntryEdit()
  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.entryEdit == nil)
}

@Test @MainActor
func personalDictionaryEntryEditorAddsOneWordThroughTheSharedFlow() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()

  viewModel.beginAddingEntry()
  #expect(viewModel.entryEdit?.isNew == true)
  viewModel.entryEditPreferredForm = "Gemma"
  viewModel.entryEditUsesCorrection = true
  viewModel.entryEditAliases = "Jemma"
  await viewModel.submitEntryEdit()

  #expect(viewModel.entries.map(\.preferredForm) == ["Gemma"])
  #expect(viewModel.entries.first?.aliases == ["Jemma"])
  #expect(viewModel.entries.first?.origin == .manual)
  #expect(viewModel.entries.first?.isEnabled == true)
}

@Test @MainActor
func personalDictionaryEntryEditorAllowsOnlyOneSaveAndKeepsTheActiveEditStable() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let gate = PersonalDictionaryEntryMutationGate(store: store)
  let original = settingsEntry(8, "Original")
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(
    store: store,
    entryMutation: { revision, mutation in
      try await gate.perform(expectedRevision: revision, mutation: mutation)
    }
  )
  await viewModel.load()
  viewModel.beginEditingEntry(original)
  let sessionID = try #require(viewModel.entryEdit?.sessionID)
  viewModel.entryEditPreferredForm = "Saved once"

  let firstSave = Task { await viewModel.submitEntryEdit() }
  await gate.waitUntilStarted()
  #expect(viewModel.isEntryEditMutationInFlight)

  viewModel.cancelEntryEdit()
  viewModel.beginAddingEntry()
  await viewModel.submitEntryEdit()

  #expect(viewModel.entryEdit?.sessionID == sessionID)
  #expect(await gate.requestCount == 1)
  await gate.release()
  await firstSave.value

  #expect(viewModel.entries.map(\.preferredForm) == ["Saved once"])
  #expect(viewModel.entryEdit == nil)
  #expect(!viewModel.isEntryEditMutationInFlight)
}

@Test @MainActor
func personalDictionaryEntryEditorAllowsOnlyOneDeleteWhileMutationIsInFlight() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let gate = PersonalDictionaryEntryMutationGate(store: store)
  let original = settingsEntry(6, "Delete once")
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(
    store: store,
    entryMutation: { revision, mutation in
      try await gate.perform(expectedRevision: revision, mutation: mutation)
    }
  )
  await viewModel.load()
  viewModel.beginEditingEntry(original)

  let firstDelete = Task { await viewModel.deleteEntryEdit() }
  await gate.waitUntilStarted()
  await viewModel.deleteEntryEdit()

  #expect(viewModel.isEntryEditMutationInFlight)
  #expect(await gate.requestCount == 1)
  await gate.release()
  await firstDelete.value

  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.entryEdit == nil)
  #expect(!viewModel.isEntryEditMutationInFlight)
}

@Test @MainActor
func personalDictionarySettingsDoesNotRebaseConcurrentAddsOntoAnUndisplayedRevision() async {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()

  let displayedRevision = viewModel.revision
  await viewModel.add(
    preferredForm: "First",
    aliases: "",
    expectedRevision: displayedRevision
  )
  await viewModel.add(
    preferredForm: "Second",
    aliases: "",
    expectedRevision: displayedRevision
  )

  #expect(viewModel.entries.count == 1)
  #expect(viewModel.revision == 1)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionarySettingsRecoversLatestRevisionWithoutRetryingConflictedMutation() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(1, "Visible term")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .upsert(settingsEntry(2, "Concurrent term"))
  )
  await viewModel.setEnabled(false, id: entry.id, expectedRevision: displayedRevision)

  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent term", "Visible term"])
  #expect(viewModel.entries.first(where: { $0.id == entry.id })?.isEnabled == true)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionarySettingsApprovesAndDismissesSuggestionsExplicitly() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let approved = settingsSuggestion(1, "Approved", observed: ["aproved"], count: 8)
  let dismissed = settingsSuggestion(2, "Dismissed", observed: ["dismised"])
  try await store.recordSuggestion(approved)
  try await store.recordSuggestion(dismissed)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.approveSuggestion(id: approved.id, expectedRevision: viewModel.revision)
  #expect(viewModel.entries.first?.id == approved.id)
  #expect(viewModel.entries.first?.origin == .suggested)
  #expect(viewModel.entries.first?.usage.useCount == 8)
  #expect(viewModel.suggestions.map(\.id) == [dismissed.id])

  await viewModel.dismissSuggestion(id: dismissed.id, expectedRevision: viewModel.revision)
  #expect(viewModel.suggestions.isEmpty)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsEditAndApproveIsAtomicAndPreservesSuggestionOnFailure() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let suggestion = settingsSuggestion(
    2,
    "Suggested",
    observed: ["sugested"],
    count: 4,
    observedAt: Date(timeIntervalSince1970: 4_000)
  )
  try await store.upsert(settingsEntry(1, "Existing", aliases: ["collision"]))
  try await store.recordSuggestion(suggestion)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.editAndApproveSuggestion(
    id: suggestion.id,
    preferredForm: "Collision",
    aliases: "edited, EDITED\nsecond",
    expectedRevision: viewModel.revision
  )

  let failed = try await store.publishedSnapshot()
  #expect(failed.snapshot.entries.map(\.preferredForm) == ["Existing"])
  #expect(failed.snapshot.suggestions.map(\.id) == [suggestion.id])
  #expect(viewModel.errorMessage == "This change would introduce a dictionary conflict.")

  await viewModel.editAndApproveSuggestion(
    id: suggestion.id,
    preferredForm: "Edited suggestion",
    aliases: "edited, EDITED\nsecond",
    expectedRevision: viewModel.revision
  )
  let entry = viewModel.entries.first(where: { $0.id == suggestion.id })
  #expect(entry?.preferredForm == "Edited suggestion")
  #expect(entry?.aliases == ["edited", "second"])
  #expect(entry?.isEnabled == true)
  #expect(entry?.isPriority == false)
  #expect(entry?.origin == .suggested)
  #expect(entry?.usage == .init(useCount: 4, lastUsedAt: suggestion.lastObservedAt))
  #expect(viewModel.suggestions.isEmpty)
}

@Test @MainActor
func personalDictionarySettingsEditAndApproveRetainsDraftForExplicitConflictRetry() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let suggestion = settingsSuggestion(2, "Suggested", observed: ["sugested"], count: 3)
  try await store.recordSuggestion(suggestion)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  viewModel.beginEditingSuggestion(suggestion)
  viewModel.suggestionEditPreferredForm = "Edited suggestion"
  viewModel.suggestionEditAliases = "edited, EDITED\nsecond"
  let displayedRevision = viewModel.revision

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .upsert(settingsEntry(1, "Concurrent entry"))
  )
  await viewModel.submitSuggestionEdit()

  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.suggestionEdit?.preferredForm == "Edited suggestion")
  #expect(viewModel.suggestionEdit?.aliases == "edited, EDITED\nsecond")
  #expect(viewModel.suggestions.map(\.id) == [suggestion.id])
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent entry"])
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")

  await viewModel.submitSuggestionEdit()

  #expect(viewModel.revision == displayedRevision + 2)
  #expect(viewModel.suggestionEdit == nil)
  #expect(viewModel.suggestions.isEmpty)
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent entry", "Edited suggestion"])
  let approved = try #require(viewModel.entries.first { $0.id == suggestion.id })
  #expect(approved.aliases == ["edited", "second"])
  #expect(approved.origin == .suggested)
  #expect(approved.usage.useCount == 3)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsEditAndApproveRejectsIdentifierCollisionAtomically() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let sharedID = settingsUUID(1)
  try await store.upsert(settingsEntry(1, "Existing"))
  try await store.recordSuggestion(settingsSuggestion(1, "Suggested"))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.editAndApproveSuggestion(
    id: sharedID,
    preferredForm: "Edited",
    aliases: "alias",
    expectedRevision: viewModel.revision
  )

  let published = try await store.publishedSnapshot()
  #expect(published.snapshot.entries.map(\.preferredForm) == ["Existing"])
  #expect(published.snapshot.suggestions.map(\.preferredForm) == ["Suggested"])
  #expect(viewModel.errorMessage == "Could not apply that dictionary change.")
}

@Test @MainActor
func personalDictionarySettingsExportsCanonicalDictionaryAndVisibleEntriesOnlyCSV() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  try await store.upsert(settingsEntry(1, "Included"))
  try await store.upsert(settingsEntry(2, "Excluded"))
  try await store.recordSuggestion(settingsSuggestion(3, "Pending suggestion"))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let exportedAt = Date(timeIntervalSince1970: 10_000)

  await viewModel.prepareCanonicalExport(exportedAt: exportedAt)
  #expect(viewModel.canonicalExportData == (try await store.exportCanonicalTransfer(
    exportedAt: exportedAt
  )))

  viewModel.query = "included"
  await viewModel.prepareCSVExport()
  let csv = String(decoding: viewModel.csvExportData ?? Data(), as: UTF8.self)
  #expect(csv.hasPrefix(PersonalDictionaryCodec.csvHeader.joined(separator: ",")))
  #expect(csv.contains("Included"))
  #expect(!csv.contains("Excluded"))
  #expect(!csv.contains("Pending suggestion"))
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsCanonicalPreviewHasDeterministicTypedRowsAndOmissionGate() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try await source.upsert(settingsEntry(1, "Imported update"))
  try await source.upsert(settingsEntry(3, "Imported add"))
  try await source.recordSuggestion(settingsSuggestion(4, "Imported suggestion"))
  try await target.upsert(settingsEntry(1, "Local update"))
  try await target.upsert(settingsEntry(2, "Local omission"))
  try await target.recordSuggestion(settingsSuggestion(5, "Local suggestion omission"))
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()

  let bytes = try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 1))
  await viewModel.previewCanonicalImport(bytes)

  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.importPreviewRows.map(\.action) == [.update, .omit, .add, .add, .omit])
  #expect(viewModel.importPreviewRows.map(\.kind) == [
    .entry, .entry, .entry, .suggestion, .suggestion,
  ])
  #expect(viewModel.importPreviewRows.map(\.title) == [
    "Imported update", "Local omission", "Imported add", "Imported suggestion",
    "Local suggestion omission",
  ])
  #expect(viewModel.importRequiresOmissionConfirmation)
  #expect(viewModel.canConfirmImport)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsZeroChangePreviewCannotBeConfirmed() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  let entry = settingsEntry(1, "Same")
  try await source.upsert(entry)
  try await target.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()

  await viewModel.previewCanonicalImport(
    try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 2))
  )

  #expect(viewModel.importPreviewRows.isEmpty)
  #expect(!viewModel.canConfirmImport)
  #expect(!viewModel.importRequiresOmissionConfirmation)
}

@Test @MainActor
func personalDictionarySettingsStaleConfirmationRepreviewsAndRequiresAnotherConfirmation() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try await source.upsert(settingsEntry(1, "Imported"))
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()
  let bytes = try await source.exportCanonicalTransfer(
    exportedAt: Date(timeIntervalSince1970: 3)
  )
  await viewModel.previewCanonicalImport(bytes)
  let displayedPreview = try #require(viewModel.importPreview)
  let staleRevision = displayedPreview.expectedLocalRevision
  #expect(viewModel.isImportPreviewPresented)

  _ = try await target.mutate(
    expectedRevision: viewModel.revision,
    .upsert(settingsEntry(2, "Concurrent local"))
  )
  await viewModel.confirmCanonicalImport(displayedPreview)

  #expect(viewModel.importPreview != nil)
  #expect(viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.importPreview?.expectedLocalRevision != staleRevision)
  #expect(viewModel.importRequiresOmissionConfirmation)
  #expect(viewModel.statusMessage == "Dictionary changed; review the updated preview.")
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent local"])

  let updatedPreview = try #require(viewModel.importPreview)
  await viewModel.confirmCanonicalImport(updatedPreview)
  #expect(viewModel.entries.map(\.preferredForm) == ["Imported"])
  #expect(!viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
  #expect(viewModel.statusMessage == "Dictionary imported.")
}

@Test @MainActor
func personalDictionarySettingsQueuedConfirmationsUseExactDisplayedPreview() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try await source.upsert(settingsEntry(1, "Imported"))
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()
  let bytes = try await source.exportCanonicalTransfer(
    exportedAt: Date(timeIntervalSince1970: 3)
  )
  await viewModel.previewCanonicalImport(bytes)
  let displayedPreview = try #require(viewModel.importPreview)
  #expect(!viewModel.importRequiresOmissionConfirmation)

  _ = try await target.mutate(
    expectedRevision: viewModel.revision,
    .upsert(settingsEntry(2, "Concurrent local"))
  )
  await viewModel.confirmCanonicalImport(displayedPreview)
  await viewModel.confirmCanonicalImport(displayedPreview)

  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent local"])
  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreview != displayedPreview)
  #expect(viewModel.importRequiresOmissionConfirmation)
  #expect(viewModel.statusMessage == "Dictionary changed; review the updated preview.")

  let updatedPreview = try #require(viewModel.importPreview)
  await viewModel.confirmCanonicalImport(updatedPreview)
  #expect(viewModel.entries.map(\.preferredForm) == ["Imported"])
  #expect(!viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
}

@Test @MainActor
func personalDictionarySettingsRejectsIntroducedImportConflictAndRetainsPreview() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let conflicting = PersonalDictionarySnapshotV2(
    revision: 7,
    entries: [settingsEntry(1, "Conflict"), settingsEntry(2, "conflict")]
  )
  let sourceURL = source.fileURL
  try FileManager.default.createDirectory(
    at: sourceURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try PersonalDictionaryCodec.encodeCanonicalJSON(conflicting).write(to: sourceURL)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()
  let bytes = try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 4))
  await viewModel.previewCanonicalImport(bytes)

  #expect(viewModel.importConflictRows.map(\.code) == ["duplicatePreferredOwner"])
  #expect(viewModel.importConflictRows.map(\.count) == [1])
  let preview = try #require(viewModel.importPreview)
  await viewModel.confirmCanonicalImport(preview)

  #expect(viewModel.errorMessage == "This import would introduce a dictionary conflict.")
  #expect(viewModel.importPreview != nil)
  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.entries.isEmpty)
}

@Test @MainActor
func personalDictionarySettingsCancellationIsSilentAndErrorsNeverExposeContent() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()
  await viewModel.previewCanonicalImport(Data("/private/path/SecretTerm".utf8))

  #expect(viewModel.errorMessage == "That file is not a valid Fleck dictionary.")
  #expect(!viewModel.errorMessage!.contains("/private/path"))
  #expect(!viewModel.errorMessage!.contains("SecretTerm"))
  let before = viewModel.state

  viewModel.handleFileOperationFailure(CocoaError(.userCancelled))
  #expect(viewModel.state == before)
  #expect(viewModel.errorMessage == "That file is not a valid Fleck dictionary.")

  viewModel.cancelImportPreview()
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsMapsRequiredErrorCategoriesToDistinctContentFreeMessages() {
  let cases: [(PersonalDictionaryStoreError, PersonalDictionarySettingsViewModel.Action, String)] = [
    (.invalidTransfer, .previewImport, "That file is not a valid Fleck dictionary."),
    (.revisionConflict, .entry, "Dictionary changed; try again."),
    (.revisionOverflow, .entry, "Personal dictionary cannot accept another change."),
    (.conflictIntroduced, .entry, "This change would introduce a dictionary conflict."),
    (.corruptData, .previewImport, "Dictionary data is corrupted."),
    (.fileTooLarge, .previewImport, "That dictionary file is too large."),
    (.publicationFailed, .entry, "Could not save personal dictionary. Try again."),
    (.invalidEntry, .entry, "Check the preferred form and aliases."),
    (.invalidSuggestion, .suggestion, "Could not update that suggestion."),
  ]

  let messages = cases.map { error, action, expected in
    let message = PersonalDictionarySettingsViewModel.message(for: error, action: action)
    #expect(message == expected)
    #expect(!message.contains("SecretTerm"))
    #expect(!message.contains("/private/path"))
    return message
  }

  #expect(Set(messages).count == messages.count)
}

@Test
func personalDictionaryRuntimeAndSettingsUseOneStoreAndNativeFormSurface() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let runtimeSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let viewModelSource = try String(
    contentsOf: repository.appendingPathComponent(
      "Sources/FleckApp/PersonalDictionarySettingsViewModel.swift"
    ),
    encoding: .utf8
  )

  #expect(runtimeSource.contains(
    "let personalDictionaryStore = PersonalDictionaryStore(rootURL: applicationSupportURL)"
  ))
  #expect(runtimeSource.contains(
    "try await personalDictionaryStore.snapshot().entries"
  ))
  #expect(runtimeSource.contains(
    "let personalDictionarySettingsViewModel = PersonalDictionarySettingsViewModel("
  ))
  #expect(runtimeSource.contains("store: personalDictionaryStore"))
  #expect(settingsSource.contains("suggestionRow(suggestion, expectedRevision: viewModel.revision)"))
  #expect(settingsSource.contains("expectedRevision: expectedRevision"))
  #expect(settingsSource.contains("case vocabulary = \"Vocabulary\""))
  #expect(settingsSource.contains("Text(\"Dictionary\")"))
  #expect(settingsSource.contains("Button(\"Import / Export…\")"))
  #expect(settingsSource.contains("Button(\"Add new\")"))
  #expect(settingsSource.contains("private func entryTitle("))
  #expect(settingsSource.contains("viewModel.beginEditingEntry(entry)"))
  #expect(settingsSource.contains("viewModel.requestEntryDeletion("))
  #expect(viewModelSource.contains("func setPriority("))
  #expect(viewModelSource.contains("mutation: .setPriority(priority, id: id)"))
  #expect(viewModelSource.contains("func requestEntryDeletion("))
  #expect(viewModelSource.contains("func confirmEntryDeletion() async"))
  #expect(viewModelSource.contains("expectedRevision: request.expectedRevision"))
  #expect(settingsSource.contains("PersonalDictionaryEntryEditSheet("))
  #expect(settingsSource.contains("Toggle(\"Correct a misspelling\""))
  #expect(settingsSource.contains("TextField(\"Correct from\""))
  #expect(settingsSource.contains("Button(\"Delete Word\", role: .destructive)"))
  #expect(settingsSource.contains("Image(systemName: \"xmark\")"))
  #expect(!settingsSource.contains(".searchable("))
  #expect(settingsSource.contains("private var optionsPopover: some View"))
  #expect(settingsSource.contains("viewModel.suggestionsHeaderActionTitle"))
  #expect(settingsSource.contains("private var transferFooter: some View"))
  #expect(settingsSource.contains("Button(\"Approve\""))
  #expect(settingsSource.contains("Button(\"Edit and Approve\""))
  #expect(settingsSource.contains("Button(\"Dismiss\""))
  #expect(settingsSource.contains("Button(\"Export Dictionary\""))
  #expect(settingsSource.contains("Button(\"Export Entries (CSV)\""))
  #expect(settingsSource.contains("Button(\"Import Dictionary\""))
  #expect(settingsSource.contains(".fileImporter("))
  #expect(settingsSource.contains(".fileExporter("))
  #expect(settingsSource.contains("filenameExtension: \"fleckdict\""))
  #expect(settingsSource.contains(".confirmationDialog("))
  #expect(settingsSource.contains(".sheet("))
  #expect(settingsSource.contains("get: { viewModel.isImportPreviewPresented }"))
  #expect(settingsSource.contains("presenting: omissionPreview"))
  #expect(settingsSource.contains("viewModel.confirmCanonicalImport(preview)"))
}

@Test
func personalDictionaryBooleanControlsUseCompactNativeSwitches() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("Text(\"Disabled\")"))
  #expect(settingsSource.contains("Toggle(\"Correct a misspelling\""))
  #expect(settingsSource.contains("Toggle(\"Use this word in dictation\""))
  #expect(settingsSource.contains(".toggleStyle(.switch)"))
  #expect(settingsSource.contains(".controlSize(.small)"))
}

@Test
func personalDictionaryVocabularyUsesTheTaskFlowAndLocalSortControls() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("Text(\"Dictionary\")"))
  #expect(settingsSource.contains("Button(\"Import / Export…\")"))
  #expect(settingsSource.contains("Button(\"Add new\")"))
  #expect(!settingsSource.contains("Teach Fleck the words and phrases that matter to you"))
  #expect(settingsSource.contains("@AppStorage(\"settings.vocabularySortOrder\")"))
  #expect(settingsSource.contains("Image(systemName: \"arrow.up.arrow.down\")"))
  #expect(settingsSource.contains("SettingsVocabularySortOrder"))
  #expect(settingsSource.contains("case aToZ"))
  #expect(settingsSource.contains("case zToA"))
  #expect(settingsSource.contains(".settingsSearchAnchor(.vocabularySort, request: visibleSearchRequest)"))
  #expect(settingsSource.contains(".settingsSearchAnchor(.vocabularyReload, request: visibleSearchRequest)"))
  #expect(settingsSource.contains("viewModel.load()"))
  #expect(settingsSource.contains("isReloading"))
  #expect(settingsSource.contains("isSearchExpanded"))
  #expect(settingsSource.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
  #expect(settingsSource.contains("!hasModalPresentation"))
  #expect(settingsSource.contains("isSettingsSearchFieldFocused"))
  #expect(!settingsSource.contains(".onKeyPress(phases: .down)"))
  #expect(settingsSource.contains("Section(isNew ? \"Add New\" : \"Edit Word\")"))
  #expect(settingsSource.contains("Use this word in dictation"))
  #expect(!settingsSource.contains("Sync"))
  #expect(!settingsSource.contains("Synced"))
}

@Test
func personalDictionaryVocabularySearchUsesFixedCustomOverlayAndAccessibleDismissal() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(!settingsSource.contains("ViewThatFits(in: .horizontal)"))
  #expect(!settingsSource.contains("private var toolbarRows: some View"))
  #expect(settingsSource.contains(".textFieldStyle(.plain)"))
  #expect(settingsSource.contains("private var searchSurface: some View"))
  #expect(settingsSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
  #expect(settingsSource.contains("AppMotion(reduceMotion: reduceMotion)"))
  #expect(settingsSource.contains("openSearch(source: isCommandF ? .keyboard : .pointer)"))
  #expect(settingsSource.contains("withAnimation(motion.presentationAnimation(for: source))"))
  #expect(settingsSource.contains(".onExitCommand"))
  #expect(settingsSource.contains("closeSearch(source: .keyboard)"))
  #expect(settingsSource.contains("viewModel.query = \"\""))
  #expect(settingsSource.contains("Clear vocabulary search"))
  #expect(settingsSource.contains("xmark"))

  let optionsStart = try #require(settingsSource.range(of: "private var optionsPopover: some View"))
  let sortStart = try #require(settingsSource.range(
    of: "private var sortControl: some View",
    range: optionsStart.upperBound..<settingsSource.endIndex
  ))
  let optionsSource = settingsSource[optionsStart.lowerBound..<sortStart.lowerBound]
  #expect(optionsSource.contains("Text(\"Transfer\")"))
  #expect(!optionsSource.contains("ForEach(PersonalDictionarySettingsViewModel.Filter.allCases)"))
  #expect(!optionsSource.contains("Button(\"Find in Dictionary\")"))
  #expect(!optionsSource.contains("sortControl"))
  #expect(!optionsSource.contains("reloadControl"))
  #expect(optionsSource.contains("settingsSearchAnchor(.vocabularyTransfer"))
  #expect(optionsSource.contains("presentAfterClosingOptions"))
  #expect(!settingsSource.contains("vocabularyFilter"))
  #expect(settingsSource.contains("private var optionsPresentation: Binding<Bool>"))
  #expect(settingsSource.contains("private func optionsPopoverDidDisappear()"))
}

@Test
func personalDictionaryVocabularySearchDefersQueryClearUntilFieldTeardown() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("private func clearSearchQueryAfterTeardown()"))
  #expect(settingsSource.contains("Task { @MainActor in"))
  #expect(settingsSource.contains("await Task.yield()"))
  #expect(settingsSource.contains("clearSearchQueryAfterTeardown()"))
  #expect(settingsSource.contains("closeSearch(source: .pointer)"))
  #expect(settingsSource.contains("closeSearch(source: .keyboard)"))
}

@Test
func personalDictionaryFocusIsNeutralAndKeepsControlsKeyboardAccessible() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let searchSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsSearch.swift"),
    encoding: .utf8
  )

  #expect(searchSource.contains("field.focusRingType = .none"))
  #expect(searchSource.contains("onFocusChange(true)"))
  #expect(searchSource.contains(".focusEffectDisabled(usesNeutralKeyboardFocus)"))
  #expect(searchSource.contains("Color.primary.opacity(0.72)"))
  #expect(searchSource.contains(".overlay(alignment: .bottom)"))
  #expect(!searchSource.contains("vocabularyFilter"))
  #expect(!searchSource.contains("usesFilterUnderlineFocusStyle"))
  #expect(settingsSource.contains(".focused($focusedAction"))
  #expect(
    settingsSource.contains(
      ".underline(focusedAction == .edit || accessibilityFocusedAction == .edit)"
    )
  )
  #expect(
    settingsSource.contains(
      ".padding(.horizontal, 12)\n      .frame(maxWidth: .infinity"
    )
  )
  #expect(settingsSource.contains(": \"Star \\(entry.preferredForm)\""))
  #expect(settingsSource.contains(".accessibilityHidden(true)"))
  #expect(settingsSource.contains(".accessibilityLabel(\"Edit \\(entry.preferredForm)\")"))
  #expect(settingsSource.contains("suggestionsHeaderActionTitle"))
  #expect(!settingsSource.contains("Personal dictionary filter"))
  #expect(!settingsSource.contains("Color.accentColor.opacity(0.12)"))
}

@Test @MainActor
func personalDictionaryCommandFRoutesFromSidebarAndContentWithoutBreakingSearchOrSheets()
  async throws
{
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appState = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await appState.waitUntilInitialLoad()
  appState.preferences.dictationCapsuleEnabled = false
  let runtime = DictationRuntime(appState: appState, applicationSupportURL: root)
  runtime.requestSettings(.vocabulary)

  let host = NSHostingView(
    rootView: SettingsView(runtime: runtime)
      .environmentObject(appState)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settlePersonalDictionarySettingsHost(host)

  let settingsSearchField = try #require(
    personalDictionarySettingsView(
      withAccessibilityIdentifier: "settings-search-field",
      in: host
    ) as? NSSearchField
  )
  let sidebarList = try #require(personalDictionarySettingsTableView(in: host))
  #expect(runtime.pendingSettingsSection == nil)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  #expect(window.makeFirstResponder(sidebarList))
  #expect(window.firstResponder === sidebarList)
  window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) != nil)

  window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  #expect(window.makeFirstResponder(settingsSearchField))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsFieldIsFocused(settingsSearchField, in: window))
  window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsFieldIsFocused(settingsSearchField, in: window))
  #expect(settingsSearchField.stringValue.isEmpty)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  #expect(window.makeFirstResponder(host))
  #expect(window.firstResponder === host)
  window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) != nil)

  window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)
  runtime.personalDictionarySettingsViewModel.beginAddingEntry()
  await settlePersonalDictionarySettingsHost(host)
  let sheet = try #require(window.attachedSheet)
  sheet.sendEvent(try #require(personalDictionaryCommandFEvent(for: sheet)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  runtime.personalDictionarySettingsViewModel.cancelEntryEdit()
  await settlePersonalDictionarySettingsHost(host)
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test
func personalDictionaryUsesACompactHeaderAndRetainsSuggestionReviewSurfaces() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  let headerStart = try #require(
    settingsSource.range(of: "private var dictionaryHeader: some View")
  )
  let searchControlStart = try #require(
    settingsSource.range(
      of: "private var searchTrigger: some View",
      range: headerStart.upperBound..<settingsSource.endIndex
    )
  )
  let headerSource = settingsSource[headerStart.lowerBound..<searchControlStart.lowerBound]

  #expect(!settingsSource.contains("private var dictionaryToolbar: some View"))
  #expect(!settingsSource.contains("ForEach(PersonalDictionarySettingsViewModel.Filter.allCases)"))
  #expect(headerSource.contains("if let title = viewModel.suggestionsHeaderActionTitle"))
  #expect(headerSource.contains("Button(title)"))
  #expect(headerSource.contains(".controlSize(.small)"))
  #expect(headerSource.contains(".accessibilityLabel(title)"))
  #expect(headerSource.contains(".accessibilityHint("))
  #expect(headerSource.contains("searchTrigger"))
  #expect(headerSource.contains("sortControl"))
  #expect(headerSource.contains("reloadControl"))
  #expect(headerSource.contains("Button(\"Add new\")"))
  #expect(!settingsSource.contains("vocabularyFilter"))
  #expect(settingsSource.contains(".popover(isPresented: optionsPresentation"))
  #expect(settingsSource.contains("Color(nsColor: .controlBackgroundColor)"))
  #expect(settingsSource.contains("RoundedRectangle(cornerRadius: 12, style: .continuous)"))
  #expect(settingsSource.contains(".frame(maxWidth: .infinity, minHeight: 48"))
  #expect(settingsSource.contains("Divider().padding(.leading, 12)"))
  #expect(!settingsSource.contains(".frame(maxWidth: .infinity, minHeight: 280"))
  #expect(!settingsSource.contains("private var dictionaryPanel: some View"))
  #expect(settingsSource.contains("private var transferFooter: some View"))
  #expect(settingsSource.contains(".id(SettingsSearchTarget.vocabularyTransferFooter)"))
  #expect(settingsSource.contains("private struct PersonalDictionaryEntryRow: View"))
  #expect(settingsSource.contains("focusedAction"))
  #expect(settingsSource.contains("onHover"))
  #expect(settingsSource.contains("Button(\"Delete\", role: .destructive)"))
  #expect(settingsSource.contains("viewModel.confirmEntryDeletion()"))
  #expect(settingsSource.contains("accessibilityLabel: entry.isPriority\n"))
  #expect(settingsSource.contains(": \"Star \\(entry.preferredForm)\""))
  #expect(settingsSource.contains("Text(\"Transfer\")"))
  #expect(!settingsSource.contains("DisclosureGroup(\"Transfer\""))
}

@Test
func personalDictionaryVocabularySortOrdersEntriesInBothDirections() {
  let entries = [
    settingsEntry(1, "zulu"),
    settingsEntry(2, "Alpha"),
    settingsEntry(3, "bravo"),
    PersonalDictionaryEntry(
      id: settingsUUID(4),
      preferredForm: "Beta",
      isPriority: true
    ),
  ]

  #expect(
    SettingsVocabularySortOrder.aToZ
      .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority)
      .map(\.preferredForm) == ["Beta", "Alpha", "bravo", "zulu"]
  )
  #expect(
    SettingsVocabularySortOrder.zToA
      .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority)
      .map(\.preferredForm) == ["Beta", "zulu", "bravo", "Alpha"]
  )

  let ties = [settingsEntry(5, "same"), settingsEntry(6, "Same")]
  let ascendingTies = SettingsVocabularySortOrder.aToZ
    .sorted(ties, by: \.preferredForm, id: \.id)
    .map(\.id)
  let descendingTies = SettingsVocabularySortOrder.zToA
    .sorted(ties, by: \.preferredForm, id: \.id)
    .map(\.id)
  #expect(ascendingTies == [settingsUUID(6), settingsUUID(5)])
  #expect(descendingTies == ascendingTies)
}

@Test
func personalDictionaryVocabularyUsageSortOrdersPinEntriesAndBreakTiesDeterministically() {
  let latestUse = Date(timeIntervalSince1970: 300)
  let earlierUse = Date(timeIntervalSince1970: 200)
  let entries = [
    PersonalDictionaryEntry(
      id: settingsUUID(1),
      preferredForm: "Zulu",
      usage: .init(useCount: 5, lastUsedAt: earlierUse)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(2),
      preferredForm: "Alpha",
      usage: .init(useCount: 8, lastUsedAt: latestUse)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(3),
      preferredForm: "alpha",
      usage: .init(useCount: 8, lastUsedAt: latestUse)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(4),
      preferredForm: "Beta",
      usage: .init(useCount: 12)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(5),
      preferredForm: "Pinned",
      isPriority: true,
      usage: .init(useCount: 0)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(6),
      preferredForm: "Bravo",
      usage: .init(useCount: 8, lastUsedAt: latestUse)
    ),
  ]

  let recentlyUsed = SettingsVocabularySortOrder.recentlyUsed
    .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority, usage: \.usage)
    .map(\.id)
  let mostUsed = SettingsVocabularySortOrder.mostUsed
    .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority, usage: \.usage)
    .map(\.id)

  #expect(
    recentlyUsed == [
      settingsUUID(5), settingsUUID(2), settingsUUID(3), settingsUUID(6), settingsUUID(1),
      settingsUUID(4),
    ]
  )
  #expect(
    mostUsed == [
      settingsUUID(5), settingsUUID(4), settingsUUID(2), settingsUUID(3), settingsUUID(6),
      settingsUUID(1),
    ]
  )
  #expect(SettingsVocabularySortOrder.recentlyUsed.suggestionSortOrder == .aToZ)
  #expect(SettingsVocabularySortOrder.mostUsed.suggestionSortOrder == .aToZ)
  #expect(SettingsVocabularySortOrder.zToA.suggestionSortOrder == .zToA)
  #expect(SettingsVocabularySortOrder(rawValue: "A–Z") == .aToZ)
  #expect(SettingsVocabularySortOrder(rawValue: "Z–A") == .zToA)
}

@Test
func personalDictionaryEntryListSortPassesUsageMetadata() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let sortStart = try #require(
    settingsSource.range(of: "private var sortedEntries: [PersonalDictionaryEntry]")
  )
  let suggestionsStart = try #require(
    settingsSource.range(
      of: "private var sortedSuggestions: [PersonalDictionarySuggestion]",
      range: sortStart.upperBound..<settingsSource.endIndex
    )
  )
  let sortedEntriesSource = settingsSource[sortStart.lowerBound..<suggestionsStart.lowerBound]

  #expect(sortedEntriesSource.contains("sortOrder.sorted("))
  #expect(sortedEntriesSource.contains("priority: \\.isPriority"))
  #expect(sortedEntriesSource.contains("usage: \\.usage"))
}

@Test
func personalDictionarySortSettingsSearchAliasesFindSortByUsage() {
  for query in ["recently used", "most used"] {
    #expect(
      SettingsSearchIndex.results(for: query).contains { $0.target == .vocabularySort }
    )
  }
}

@Test
func personalDictionarySortPopoverKeepsSearchAndKeyboardInteractionsAccessible() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let sortStart = try #require(settingsSource.range(of: "private var sortPopover: some View"))
  let reloadStart = try #require(
    settingsSource.range(
      of: "private var reloadControl: some View",
      range: sortStart.upperBound..<settingsSource.endIndex
    )
  )
  let sortSource = settingsSource[sortStart.lowerBound..<reloadStart.lowerBound]

  #expect(sortSource.contains("Text(\"SORT BY\")"))
  #expect(sortSource.contains(".background(.regularMaterial"))
  #expect(sortSource.contains("sortOrdersForCurrentFilter"))
  #expect(sortSource.contains("SettingsVocabularySortOrder.allCases"))
  #expect(sortSource.contains("viewModel.filter == .suggestions"))
  #expect(sortSource.contains("sortOrder.suggestionSortOrder"))
  #expect(sortSource.contains("if viewModel.filter != .suggestions"))
  #expect(sortSource.contains("Text(\"Usage reflects saved data, not live dictation.\")"))
  #expect(sortSource.contains("sortOrder = order"))
  #expect(sortSource.contains("Image(systemName: \"checkmark\")"))
  #expect(sortSource.contains("isHovered || isFocused"))
  #expect(sortSource.contains(".onHover"))
  #expect(sortSource.contains(".focused($focusedSortOrder, equals: order)"))
  #expect(sortSource.contains(".accessibilityLabel(\"Sort by \\(order.rawValue)\")"))
  #expect(
    sortSource.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")")
  )
  #expect(sortSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
  #expect(sortSource.contains(".popover(isPresented: $isSortPresented, arrowEdge: .bottom)"))
  #expect(sortSource.contains(".onExitCommand"))
  #expect(sortSource.contains("isSortPresented = false"))
  #expect(!sortSource.contains("Picker("))
  #expect(!sortSource.contains(".animation("))
  #expect(
    settingsSource.contains(
      ".settingsSearchAnchor(.vocabularySort, request: visibleSearchRequest)"
    )
  )
  #expect(settingsSource.contains("!isSortPresented"))
  #expect(settingsSource.contains(".onChange(of: searchRequest?.id, initial: true)"))
  #expect(settingsSource.contains(".onChange(of: hasModalPresentation)"))
}

private func settingsEntry(
  _ number: UInt8,
  _ preferredForm: String,
  aliases: [String] = [],
  enabled: Bool = true
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: settingsUUID(number),
    preferredForm: preferredForm,
    aliases: aliases,
    isEnabled: enabled
  )
}

private func settingsSuggestion(
  _ number: UInt8,
  _ preferredForm: String,
  observed: [String] = [],
  count: Int = 1,
  observedAt: Date = Date(timeIntervalSince1970: 1_000)
) -> PersonalDictionarySuggestion {
  PersonalDictionarySuggestion(
    id: settingsUUID(number),
    preferredForm: preferredForm,
    observedForms: observed,
    observationCount: count,
    lastObservedAt: observedAt
  )
}

private actor PersonalDictionaryEntryMutationGate {
  let store: PersonalDictionaryStore
  private(set) var requestCount = 0
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(store: PersonalDictionaryStore) {
    self.store = store
  }

  func perform(
    expectedRevision: UInt64,
    mutation: PersonalDictionaryMutation
  ) async throws -> PersonalDictionaryPublishedSnapshot {
    requestCount += 1
    startedWaiters.forEach { $0.resume() }
    startedWaiters.removeAll()
    await withCheckedContinuation { releaseContinuation = $0 }
    return try await store.mutate(expectedRevision: expectedRevision, mutation)
  }

  func waitUntilStarted() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private func settingsUUID(_ number: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
}

private func temporarySettingsDictionaryRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckSettingsTests-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
private func personalDictionarySettingsView(
  withAccessibilityIdentifier identifier: String,
  in view: NSView
) -> NSView? {
  if view.accessibilityIdentifier() == identifier {
    return view
  }
  for subview in view.subviews {
    if let match = personalDictionarySettingsView(
      withAccessibilityIdentifier: identifier,
      in: subview
    ) {
      return match
    }
  }
  return nil
}

@MainActor
private func personalDictionarySettingsTableView(in view: NSView) -> NSTableView? {
  if let tableView = view as? NSTableView {
    return tableView
  }
  for subview in view.subviews {
    if let tableView = personalDictionarySettingsTableView(in: subview) {
      return tableView
    }
  }
  return nil
}

@MainActor
private func personalDictionarySettingsFieldIsFocused(
  _ field: NSTextField,
  in window: NSWindow
) -> Bool {
  if window.firstResponder === field { return true }
  guard let fieldEditor = field.currentEditor() else { return false }
  return window.firstResponder === fieldEditor
}

@MainActor
private func personalDictionaryCommandFEvent(for window: NSWindow) -> NSEvent? {
  NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [.command],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "f",
    charactersIgnoringModifiers: "f",
    isARepeat: false,
    keyCode: 3
  )
}

@MainActor
private func personalDictionaryEscapeEvent(for window: NSWindow) -> NSEvent? {
  NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "\u{1b}",
    charactersIgnoringModifiers: "\u{1b}",
    isARepeat: false,
    keyCode: 53
  )
}

@MainActor
private func settlePersonalDictionarySettingsHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
