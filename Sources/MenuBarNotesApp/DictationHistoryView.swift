#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore

  enum DictationHistoryConfirmation: Equatable {
    case clear
    case delete(UUID)
  }

  struct DictationHistoryPresentation {
    private(set) var records: [DictationHistoryRecord]
    private(set) var pendingConfirmation: DictationHistoryConfirmation?
    private var rollbackRecords: [DictationHistoryRecord]?

    init(records: [DictationHistoryRecord] = []) {
      self.records = records
    }

    mutating func replaceRecords(_ records: [DictationHistoryRecord]) {
      self.records = records
    }

    mutating func requestClear() {
      pendingConfirmation = .clear
    }

    mutating func requestDelete(_ id: UUID) {
      pendingConfirmation = .delete(id)
    }

    mutating func cancelConfirmation() {
      pendingConfirmation = nil
    }

    @discardableResult
    mutating func confirmPendingRemoval() -> DictationHistoryConfirmation? {
      guard let pendingConfirmation else { return nil }
      rollbackRecords = records
      switch pendingConfirmation {
      case .clear:
        records.removeAll()
      case .delete(let id):
        records.removeAll { $0.id == id }
      }
      self.pendingConfirmation = nil
      return pendingConfirmation
    }

    mutating func rollbackRemoval() {
      guard let rollbackRecords else { return }
      records = rollbackRecords
      self.rollbackRecords = nil
    }

    mutating func finishRemoval() {
      rollbackRecords = nil
    }
  }

  @MainActor
  final class DictationHistoryViewModel: ObservableObject {
    typealias LoadOperation = @Sendable () async throws -> [DictationHistoryRecord]
    typealias DeleteOperation = @Sendable (UUID) async throws -> Void
    typealias ClearOperation = @Sendable () async throws -> Void

    @Published private(set) var presentation: DictationHistoryPresentation
    @Published var errorMessage: String?

    private let loadOperation: LoadOperation
    private let deleteOperation: DeleteOperation
    private let clearOperation: ClearOperation

    init(
      records: [DictationHistoryRecord] = [],
      load: @escaping LoadOperation,
      delete: @escaping DeleteOperation,
      clear: @escaping ClearOperation
    ) {
      presentation = DictationHistoryPresentation(records: records)
      loadOperation = load
      deleteOperation = delete
      clearOperation = clear
    }

    convenience init(store: DictationHistoryStore) {
      self.init(
        load: { try await store.list() },
        delete: { try await store.delete(id: $0) },
        clear: { try await store.clear() }
      )
    }

    var records: [DictationHistoryRecord] {
      presentation.records
    }

    var pendingConfirmation: DictationHistoryConfirmation? {
      presentation.pendingConfirmation
    }

    func load() async {
      do {
        presentation.replaceRecords(try await loadOperation())
        errorMessage = nil
      } catch {
        errorMessage = "Could not load dictation history: \(error.localizedDescription)"
      }
    }

    func requestClear() {
      presentation.requestClear()
    }

    func requestDelete(_ id: UUID) {
      presentation.requestDelete(id)
    }

    func cancelConfirmation() {
      presentation.cancelConfirmation()
    }

    func confirmRemoval() async {
      guard let removal = presentation.confirmPendingRemoval() else { return }
      do {
        switch removal {
        case .clear:
          try await clearOperation()
        case .delete(let id):
          try await deleteOperation(id)
        }
        presentation.finishRemoval()
        errorMessage = nil
      } catch {
        presentation.rollbackRemoval()
        errorMessage = "Could not update dictation history: \(error.localizedDescription)"
      }
    }
  }

  struct DictationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DictationHistoryViewModel
    let onOpenDestination: (UUID) -> Void

    init(
      historyStore: DictationHistoryStore,
      onOpenDestination: @escaping (UUID) -> Void
    ) {
      _model = StateObject(wrappedValue: DictationHistoryViewModel(store: historyStore))
      self.onOpenDestination = onOpenDestination
    }

    var body: some View {
      VStack(spacing: 0) {
        HStack {
          Text("Dictation History")
            .font(.title2.weight(.semibold))
          Spacer()
          Button("Clear History", role: .destructive) {
            model.requestClear()
          }
          .disabled(model.records.isEmpty)
          Button("Done") {
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
        }
        .padding()

        Divider()

        if model.records.isEmpty {
          ContentUnavailableView(
            "No Dictation History",
            systemImage: "waveform",
            description: Text("Successful captures kept for recovery appear here for 30 days.")
          )
        } else {
          List(model.records) { record in
            HistoryRow(
              record: record,
              onOpenDestination: onOpenDestination,
              onDelete: { model.requestDelete(record.id) }
            )
          }
          .listStyle(.inset)
        }
      }
      .frame(minWidth: 640, minHeight: 440)
      .task {
        await model.load()
      }
      .confirmationDialog(
        confirmationTitle,
        isPresented: Binding(
          get: { model.pendingConfirmation != nil },
          set: { if !$0 { model.cancelConfirmation() } }
        )
      ) {
        Button(confirmationButtonTitle, role: .destructive) {
          Task { await model.confirmRemoval() }
        }
        Button("Cancel", role: .cancel) {
          model.cancelConfirmation()
        }
      } message: {
        Text(confirmationMessage)
      }
      .alert(
        "Dictation History",
        isPresented: Binding(
          get: { model.errorMessage != nil },
          set: { if !$0 { model.errorMessage = nil } }
        )
      ) {
        Button("OK") {
          model.errorMessage = nil
        }
      } message: {
        Text(model.errorMessage ?? "")
      }
    }

    private var confirmationTitle: String {
      switch model.pendingConfirmation {
      case .delete:
        "Delete this history item?"
      case .clear:
        "Clear all dictation history?"
      case nil:
        ""
      }
    }

    private var confirmationButtonTitle: String {
      switch model.pendingConfirmation {
      case .delete:
        "Delete"
      case .clear:
        "Clear History"
      case nil:
        ""
      }
    }

    private var confirmationMessage: String {
      switch model.pendingConfirmation {
      case .delete:
        "This removes the local transcript record. This cannot be undone."
      case .clear:
        "This removes all local transcript records. This cannot be undone."
      case nil:
        ""
      }
    }
  }

  private struct HistoryRow: View {
    let record: DictationHistoryRecord
    let onOpenDestination: (UUID) -> Void
    let onDelete: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.headline)
          Spacer()
          Label(destinationTitle, systemImage: destinationSymbol)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        transcript("Cleaned", text: record.cleanedTranscript ?? record.rawTranscript)
        transcript("Raw", text: record.rawTranscript)

        HStack {
          Button("Copy Clean") {
            copy(record.cleanedTranscript ?? record.rawTranscript)
          }
          Button("Copy Raw") {
            copy(record.rawTranscript)
          }
          Button("Open Destination") {
            guard let id = record.destination?.noteID else { return }
            onOpenDestination(id)
          }
          .disabled(record.destination == nil || record.insertionOutcome != .saved)
          Spacer()
          Button("Delete", role: .destructive, action: onDelete)
        }
        .buttonStyle(.borderless)
      }
      .padding(.vertical, 8)
    }

    private var destinationTitle: String {
      guard record.insertionOutcome == .saved else { return "Unsaved" }
      return record.destination?.title ?? "Unsaved"
    }

    private var destinationSymbol: String {
      record.insertionOutcome == .saved ? "note.text" : "exclamationmark.triangle"
    }

    @ViewBuilder
    private func transcript(_ title: String, text: String) -> some View {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(text)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    private func copy(_ text: String) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    }
  }
#endif
