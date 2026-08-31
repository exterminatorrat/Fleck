import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func personalDictionarySettingsLoadsAndFiltersEntriesAndSuggestionsInStableOrder() async throws {
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
  #expect(viewModel.visibleEntries.count == 3)
  #expect(viewModel.visibleSuggestions.isEmpty)

  viewModel.filter = .disabled
  #expect(viewModel.visibleEntries.map(\.preferredForm) == ["Alpha"])

  viewModel.filter = .all
  viewModel.query = "FIRST TERM"
  #expect(viewModel.visibleEntries.map(\.preferredForm) == ["alpha"])

  viewModel.filter = .suggestions
  viewModel.query = "b TERM"
  #expect(viewModel.visibleEntries.isEmpty)
  #expect(viewModel.visibleSuggestions.map(\.preferredForm) == ["Beta"])
  #expect(viewModel.errorMessage == nil)
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
    aliases: " fleck app, Fleck application\n fleck app "
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
func personalDictionarySettingsDoesNotRebaseConcurrentAddsOntoAnUndisplayedRevision() async {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()

  async let first: Void = viewModel.add(preferredForm: "First", aliases: "")
  async let second: Void = viewModel.add(preferredForm: "Second", aliases: "")
  await first
  await second

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
  await viewModel.previewCanonicalImport(
    try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 3))
  )
  let staleRevision = viewModel.importPreview?.expectedLocalRevision

  _ = try await target.mutate(
    expectedRevision: viewModel.revision,
    .upsert(settingsEntry(2, "Concurrent local"))
  )
  await viewModel.confirmCanonicalImport()

  #expect(viewModel.importPreview != nil)
  #expect(viewModel.importPreview?.expectedLocalRevision != staleRevision)
  #expect(viewModel.statusMessage == "Dictionary changed; review the updated preview.")
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent local"])

  await viewModel.confirmCanonicalImport()
  #expect(viewModel.entries.map(\.preferredForm) == ["Imported"])
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
  #expect(viewModel.statusMessage == "Dictionary imported.")
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
  await viewModel.confirmCanonicalImport()

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

  #expect(viewModel.errorMessage == "Could not read that dictionary file.")
  #expect(!viewModel.errorMessage!.contains("/private/path"))
  #expect(!viewModel.errorMessage!.contains("SecretTerm"))
  let before = viewModel.state

  viewModel.handleFileOperationFailure(CocoaError(.userCancelled))
  #expect(viewModel.state == before)
  #expect(viewModel.errorMessage == "Could not read that dictionary file.")

  viewModel.cancelImportPreview()
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
  #expect(viewModel.errorMessage == nil)
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
  #expect(settingsSource.contains("Section(\"Personal Dictionary\")"))
  #expect(settingsSource.contains(".searchable("))
  #expect(settingsSource.contains("Picker(\"Show\""))
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

private func settingsUUID(_ number: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
}

private func temporarySettingsDictionaryRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckSettingsTests-\(UUID().uuidString)", isDirectory: true)
}
