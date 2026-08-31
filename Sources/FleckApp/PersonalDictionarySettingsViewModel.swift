import Foundation
import FleckCore
import SwiftUI

@MainActor
final class PersonalDictionarySettingsViewModel: ObservableObject {
  enum Filter: String, CaseIterable, Identifiable {
    case all = "All"
    case enabled = "Enabled"
    case disabled = "Disabled"
    case suggestions = "Suggestions"

    var id: Self { self }
  }

  struct State: Equatable {
    var revision: UInt64 = 0
    var entries: [PersonalDictionaryEntry] = []
    var suggestions: [PersonalDictionarySuggestion] = []
    var query = ""
    var filter = Filter.all
    var canonicalExportData: Data?
    var csvExportData: Data?
    var entryEdit: EntryEdit?
    var suggestionEdit: SuggestionEdit?
    var importPreviewData: Data?
    var importPreview: PersonalDictionaryImportPreview?
    var isImportPreviewPresented = false
    var statusMessage: String?
    var errorMessage: String?
  }

  struct EntryEdit: Identifiable, Equatable {
    let id: UUID
    let isNew: Bool
    var preferredForm: String
    var aliases: String
    var usesCorrection: Bool
    var isEnabled: Bool
    let localeIdentifier: String
    let isPriority: Bool
    let origin: PersonalDictionaryOrigin
    let usage: PersonalDictionaryUsage

    init() {
      id = UUID()
      isNew = true
      preferredForm = ""
      aliases = ""
      usesCorrection = false
      isEnabled = true
      localeIdentifier = "en-US"
      isPriority = false
      origin = .manual
      usage = .init()
    }

    init(entry: PersonalDictionaryEntry) {
      id = entry.id
      isNew = false
      preferredForm = entry.preferredForm
      aliases = entry.aliases.joined(separator: ", ")
      usesCorrection = !entry.aliases.isEmpty
      isEnabled = entry.isEnabled
      localeIdentifier = entry.localeIdentifier
      isPriority = entry.isPriority
      origin = entry.origin
      usage = entry.usage
    }
  }

  struct SuggestionEdit: Identifiable, Equatable {
    let id: UUID
    var preferredForm: String
    var aliases: String

    init(suggestion: PersonalDictionarySuggestion) {
      id = suggestion.id
      preferredForm = suggestion.preferredForm
      aliases = suggestion.observedForms.joined(separator: ", ")
    }
  }

  struct ImportPreviewRow: Identifiable, Equatable {
    enum Action: String, Equatable {
      case add = "Add"
      case update = "Update"
      case omit = "Omit"
    }

    enum Kind: String, Equatable {
      case entry = "Entry"
      case suggestion = "Suggestion"
    }

    let id: String
    let action: Action
    let kind: Kind
    let title: String
    let detail: String?

    var accessibilityImportLabel: String {
      "\(action.rawValue) \(kind.rawValue.lowercased()): \(title)"
    }
  }

  struct ImportConflictRow: Identifiable, Equatable {
    let code: String
    let count: Int
    var id: String { code }
  }

  @Published private(set) var state = State()

  private let store: PersonalDictionaryStore
  private var mutationTail: Task<Void, Never>?

  init(store: PersonalDictionaryStore) {
    self.store = store
  }

  var revision: UInt64 { state.revision }
  var entries: [PersonalDictionaryEntry] { state.entries }
  var suggestions: [PersonalDictionarySuggestion] { state.suggestions }
  var canonicalExportData: Data? { state.canonicalExportData }
  var csvExportData: Data? { state.csvExportData }
  var entryEdit: EntryEdit? { state.entryEdit }
  var suggestionEdit: SuggestionEdit? { state.suggestionEdit }
  var importPreviewData: Data? { state.importPreviewData }
  var importPreview: PersonalDictionaryImportPreview? { state.importPreview }
  var isImportPreviewPresented: Bool { state.isImportPreviewPresented }
  var statusMessage: String? { state.statusMessage }
  var errorMessage: String? { state.errorMessage }

  var entryEditPreferredForm: String {
    get { state.entryEdit?.preferredForm ?? "" }
    set { state.entryEdit?.preferredForm = newValue }
  }

  var entryEditAliases: String {
    get { state.entryEdit?.aliases ?? "" }
    set { state.entryEdit?.aliases = newValue }
  }

  var entryEditUsesCorrection: Bool {
    get { state.entryEdit?.usesCorrection ?? false }
    set { state.entryEdit?.usesCorrection = newValue }
  }

  var entryEditIsEnabled: Bool {
    get { state.entryEdit?.isEnabled ?? true }
    set { state.entryEdit?.isEnabled = newValue }
  }

  var suggestionEditPreferredForm: String {
    get { state.suggestionEdit?.preferredForm ?? "" }
    set { state.suggestionEdit?.preferredForm = newValue }
  }

  var suggestionEditAliases: String {
    get { state.suggestionEdit?.aliases ?? "" }
    set { state.suggestionEdit?.aliases = newValue }
  }

  var query: String {
    get { state.query }
    set { state.query = newValue }
  }

  var filter: Filter {
    get { state.filter }
    set { state.filter = newValue }
  }

  var visibleEntries: [PersonalDictionaryEntry] {
    guard filter != .suggestions else { return [] }
    return entries.filter { entry in
      let matchesFilter = switch filter {
      case .all: true
      case .enabled: entry.isEnabled
      case .disabled: !entry.isEnabled
      case .suggestions: false
      }
      return matchesFilter && matchesQuery([entry.preferredForm] + entry.aliases)
    }
  }

  var visibleSuggestions: [PersonalDictionarySuggestion] {
    guard filter == .suggestions else { return [] }
    return suggestions.filter {
      matchesQuery([$0.preferredForm] + $0.observedForms)
    }
  }

  var importPreviewRows: [ImportPreviewRow] {
    importPreview?.changes.map(Self.previewRow) ?? []
  }

  var importConflictRows: [ImportConflictRow] {
    (importPreview?.conflictDiagnostics ?? [])
      .map { ImportConflictRow(code: $0.code.rawValue, count: $0.count) }
      .sorted { $0.code < $1.code }
  }

  var canConfirmImport: Bool {
    importPreview?.changes.isEmpty == false
  }

  var importRequiresOmissionConfirmation: Bool {
    importPreview?.changes.contains { change in
      switch change {
      case .omitEntry, .omitSuggestion: true
      default: false
      }
    } == true
  }

  func load() async {
    await enqueue {
      do {
        self.publish(try await self.store.publishedSnapshot())
        self.clearMessages()
      } catch {
        self.state.errorMessage = Self.message(for: error, action: .load)
      }
    }
  }

  func add(preferredForm: String, aliases: String, expectedRevision: UInt64) async {
    await enqueue {
      let preferredForm = preferredForm.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !preferredForm.isEmpty else {
        self.state.errorMessage = "Enter a preferred form before adding the entry."
        return
      }
      let existing = self.entries.first {
        Self.normalized($0.preferredForm) == Self.normalized(preferredForm)
      }
      let entry = PersonalDictionaryEntry(
        id: existing?.id ?? UUID(),
        preferredForm: preferredForm,
        aliases: Self.parseAliases(aliases),
        localeIdentifier: existing?.localeIdentifier ?? "en-US",
        isPriority: existing?.isPriority ?? false,
        isEnabled: existing?.isEnabled ?? true,
        origin: existing?.origin ?? .manual,
        usage: existing?.usage ?? .init()
      )
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .upsert(entry),
        action: .entry
      )
    }
  }

  func setEnabled(_ enabled: Bool, id: UUID, expectedRevision: UInt64) async {
    await enqueue {
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .setEnabled(enabled, id: id),
        action: .entry
      )
    }
  }

  func delete(id: UUID, expectedRevision: UInt64) async {
    await enqueue {
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .delete(id: id),
        action: .entry
      )
    }
  }

  func beginAddingEntry() {
    state.entryEdit = EntryEdit()
    clearMessages()
  }

  func beginEditingEntry(_ entry: PersonalDictionaryEntry) {
    state.entryEdit = EntryEdit(entry: entry)
    clearMessages()
  }

  func cancelEntryEdit() {
    state.entryEdit = nil
    clearMessages()
  }

  func submitEntryEdit() async {
    guard let edit = entryEdit else { return }
    let preferredForm = edit.preferredForm.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !preferredForm.isEmpty else {
      state.errorMessage = "Enter a word or phrase before saving."
      return
    }
    let entry = PersonalDictionaryEntry(
      id: edit.id,
      preferredForm: preferredForm,
      aliases: edit.usesCorrection ? Self.parseAliases(edit.aliases) : [],
      localeIdentifier: edit.localeIdentifier,
      isPriority: edit.isPriority,
      isEnabled: edit.isEnabled,
      origin: edit.origin,
      usage: edit.usage
    )
    let expectedRevision = revision
    await enqueue {
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .upsert(entry),
        action: .entry
      )
    }
    if errorMessage == nil {
      state.entryEdit = nil
    }
  }

  func deleteEntryEdit() async {
    guard let edit = entryEdit else { return }
    guard !edit.isNew else {
      state.entryEdit = nil
      return
    }
    let expectedRevision = revision
    await enqueue {
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .delete(id: edit.id),
        action: .entry
      )
    }
    if errorMessage == nil {
      state.entryEdit = nil
    }
  }

  func approveSuggestion(id: UUID, expectedRevision: UInt64) async {
    await enqueue {
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .approveSuggestion(id: id),
        action: .suggestion
      )
    }
  }

  func dismissSuggestion(id: UUID, expectedRevision: UInt64) async {
    await enqueue {
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .dismissSuggestion(id: id),
        action: .suggestion
      )
    }
  }

  func beginEditingSuggestion(_ suggestion: PersonalDictionarySuggestion) {
    state.suggestionEdit = SuggestionEdit(suggestion: suggestion)
  }

  func cancelSuggestionEdit() {
    state.suggestionEdit = nil
  }

  func submitSuggestionEdit() async {
    guard let edit = suggestionEdit else { return }
    let expectedRevision = revision
    await editAndApproveSuggestion(
      id: edit.id,
      preferredForm: edit.preferredForm,
      aliases: edit.aliases,
      expectedRevision: expectedRevision
    )
    if errorMessage == nil {
      state.suggestionEdit = nil
    }
  }

  func editAndApproveSuggestion(
    id: UUID,
    preferredForm: String,
    aliases: String,
    expectedRevision: UInt64
  ) async {
    await enqueue {
      guard let suggestion = self.suggestions.first(where: { $0.id == id }) else {
        self.state.errorMessage = "That suggestion is no longer available."
        return
      }
      let preferredForm = preferredForm.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !preferredForm.isEmpty else {
        self.state.errorMessage = "Enter a preferred form before approving the suggestion."
        return
      }
      let entry = PersonalDictionaryEntry(
        id: suggestion.id,
        preferredForm: preferredForm,
        aliases: Self.parseAliases(aliases),
        localeIdentifier: suggestion.localeIdentifier,
        isPriority: false,
        isEnabled: true,
        origin: .suggested,
        usage: .init(
          useCount: suggestion.observationCount,
          lastUsedAt: suggestion.lastObservedAt
        )
      )
      let replacement = PersonalDictionarySnapshot(
        entries: self.entries + [entry],
        suggestions: self.suggestions.filter { $0.id != id }
      )
      await self.mutate(
        expectedRevision: expectedRevision,
        mutation: .replace(replacement),
        action: .suggestion
      )
    }
  }

  func prepareCanonicalExport(exportedAt: Date = Date()) async {
    await enqueue {
      do {
        self.state.canonicalExportData = try await self.store.exportCanonicalTransfer(
          exportedAt: exportedAt
        )
        self.clearMessages()
      } catch {
        self.state.canonicalExportData = nil
        self.state.errorMessage = Self.message(for: error, action: .exportDictionary)
      }
    }
  }

  func prepareCSVExport() async {
    do {
      state.csvExportData = Data(try PersonalDictionaryCodec.exportCSV(visibleEntries).utf8)
      clearMessages()
    } catch {
      state.csvExportData = nil
      state.errorMessage = "Could not export visible dictionary entries."
    }
  }

  func previewCanonicalImport(_ data: Data) async {
    await enqueue {
      self.state.importPreviewData = data
      self.state.importPreview = nil
      self.state.isImportPreviewPresented = false
      self.clearMessages()
      do {
        self.state.importPreview = try await self.store.previewCanonicalImport(data)
        self.state.isImportPreviewPresented = true
      } catch {
        self.state.errorMessage = Self.message(for: error, action: .previewImport)
      }
    }
  }

  func confirmCanonicalImport(_ preview: PersonalDictionaryImportPreview) async {
    await enqueue {
      guard !preview.changes.isEmpty else { return }
      do {
        self.publish(try await self.store.confirmCanonicalImport(preview))
        self.state.importPreviewData = nil
        self.state.importPreview = nil
        self.state.isImportPreviewPresented = false
        self.state.errorMessage = nil
        self.state.statusMessage = "Dictionary imported."
      } catch PersonalDictionaryStoreError.revisionConflict {
        await self.repreviewAfterRevisionConflict()
      } catch PersonalDictionaryStoreError.conflictIntroduced {
        self.state.statusMessage = nil
        self.state.errorMessage = "This import would introduce a dictionary conflict."
      } catch {
        self.state.statusMessage = nil
        self.state.errorMessage = Self.message(for: error, action: .confirmImport)
      }
    }
  }

  func cancelImportPreview() {
    state.importPreviewData = nil
    state.importPreview = nil
    state.isImportPreviewPresented = false
    clearMessages()
  }

  func handleFileOperationFailure(_ error: Error) {
    let cocoaError = error as NSError
    if cocoaError.domain == NSCocoaErrorDomain,
      cocoaError.code == CocoaError.Code.userCancelled.rawValue
    {
      return
    }
    state.statusMessage = nil
    state.errorMessage = if error as? PersonalDictionaryStoreError == .fileTooLarge {
      "That dictionary file is too large."
    } else {
      "Could not complete the dictionary file operation."
    }
  }

  private func mutate(
    expectedRevision: UInt64,
    mutation: PersonalDictionaryMutation,
    action: Action
  ) async {
    do {
      publish(try await store.mutate(expectedRevision: expectedRevision, mutation))
      clearMessages()
    } catch PersonalDictionaryStoreError.revisionConflict {
      do {
        publish(try await store.publishedSnapshot())
        state.statusMessage = nil
        state.errorMessage = "Dictionary changed; try again."
      } catch {
        state.statusMessage = nil
        state.errorMessage = Self.message(for: error, action: .load)
      }
    } catch {
      state.statusMessage = nil
      state.errorMessage = Self.message(for: error, action: action)
    }
  }

  private func repreviewAfterRevisionConflict() async {
    guard let data = importPreviewData else {
      state.importPreview = nil
      state.isImportPreviewPresented = false
      state.statusMessage = nil
      state.errorMessage = "Dictionary changed; import it again."
      return
    }
    state.importPreview = nil
    do {
      publish(try await store.publishedSnapshot())
      state.importPreview = try await store.previewCanonicalImport(data)
      state.errorMessage = nil
      state.statusMessage = "Dictionary changed; review the updated preview."
    } catch {
      state.errorMessage = Self.message(for: error, action: .previewImport)
      state.statusMessage = nil
    }
  }

  private func publish(_ published: PersonalDictionaryPublishedSnapshot) {
    state.revision = published.snapshot.revision
    state.entries = Self.sorted(published.snapshot.entries)
    state.suggestions = Self.sorted(published.snapshot.suggestions)
  }

  private func clearMessages() {
    state.errorMessage = nil
    state.statusMessage = nil
  }

  private func matchesQuery(_ values: [String]) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    let foldedQuery = Self.normalized(query)
    return values.contains { Self.normalized($0).contains(foldedQuery) }
  }

  private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
    let previous = mutationTail
    let task = Task { @MainActor in
      await previous?.value
      await operation()
    }
    mutationTail = task
    await task.value
  }

  private static func previewRow(_ change: PersonalDictionaryImportChange)
    -> ImportPreviewRow
  {
    switch change {
    case .addEntry(let entry):
      row(action: .add, entry: entry)
    case .updateEntry(_, let imported):
      row(action: .update, entry: imported)
    case .omitEntry(let entry):
      row(action: .omit, entry: entry)
    case .addSuggestion(let suggestion):
      row(action: .add, suggestion: suggestion)
    case .updateSuggestion(_, let imported):
      row(action: .update, suggestion: imported)
    case .omitSuggestion(let suggestion):
      row(action: .omit, suggestion: suggestion)
    }
  }

  private static func row(
    action: ImportPreviewRow.Action,
    entry: PersonalDictionaryEntry
  ) -> ImportPreviewRow {
    ImportPreviewRow(
      id: "entry-\(action.rawValue)-\(entry.id.uuidString)",
      action: action,
      kind: .entry,
      title: entry.preferredForm,
      detail: entry.aliases.isEmpty ? nil : entry.aliases.joined(separator: ", ")
    )
  }

  private static func row(
    action: ImportPreviewRow.Action,
    suggestion: PersonalDictionarySuggestion
  ) -> ImportPreviewRow {
    ImportPreviewRow(
      id: "suggestion-\(action.rawValue)-\(suggestion.id.uuidString)",
      action: action,
      kind: .suggestion,
      title: suggestion.preferredForm,
      detail: suggestion.observedForms.isEmpty
        ? nil
        : suggestion.observedForms.joined(separator: ", ")
    )
  }

  private static func parseAliases(_ text: String) -> [String] {
    var seen = Set<String>()
    return text
      .components(separatedBy: CharacterSet(charactersIn: ",\n"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { seen.insert(normalized($0)).inserted }
  }

  private static func sorted(_ entries: [PersonalDictionaryEntry])
    -> [PersonalDictionaryEntry]
  {
    entries.sorted { lhs, rhs in
      stableLess(lhs.preferredForm, lhs.id, rhs.preferredForm, rhs.id)
    }
  }

  private static func sorted(_ suggestions: [PersonalDictionarySuggestion])
    -> [PersonalDictionarySuggestion]
  {
    suggestions.sorted { lhs, rhs in
      stableLess(lhs.preferredForm, lhs.id, rhs.preferredForm, rhs.id)
    }
  }

  private static func stableLess(
    _ lhs: String,
    _ lhsID: UUID,
    _ rhs: String,
    _ rhsID: UUID
  ) -> Bool {
    let left = normalized(lhs)
    let right = normalized(rhs)
    if left != right { return left < right }
    if lhs != rhs { return lhs < rhs }
    return lhsID.uuidString < rhsID.uuidString
  }

  private static func normalized(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }

  enum Action {
    case load
    case entry
    case suggestion
    case exportDictionary
    case previewImport
    case confirmImport
  }

  static func message(for error: Error, action: Action) -> String {
    switch error as? PersonalDictionaryStoreError {
    case .invalidTransfer:
      "That file is not a valid Fleck dictionary."
    case .revisionConflict:
      "Dictionary changed; try again."
    case .revisionOverflow:
      "Personal dictionary cannot accept another change."
    case .conflictIntroduced:
      "This change would introduce a dictionary conflict."
    case .invalidEntry:
      "Check the preferred form and aliases."
    case .invalidSuggestion:
      "Could not update that suggestion."
    case .invalidSnapshot, .unsupportedSchemaVersion:
      "Could not apply that dictionary change."
    case .missingEntry:
      "That entry is no longer available."
    case .missingSuggestion:
      "That suggestion is no longer available."
    case .corruptData:
      "Dictionary data is corrupted."
    case .fileTooLarge:
      "That dictionary file is too large."
    case .publicationFailed:
      action == .exportDictionary
        ? "Could not export the personal dictionary."
        : "Could not save personal dictionary. Try again."
    case nil:
      switch action {
      case .previewImport, .confirmImport: "Could not read that dictionary file."
      case .exportDictionary: "Could not export the personal dictionary."
      default: "Could not update personal dictionary. Try again."
      }
    }
  }
}
