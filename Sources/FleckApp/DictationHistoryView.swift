#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore

  enum DictationHistoryConfirmation: Equatable {
    case clear
    case delete(UUID)
  }

  @MainActor
  final class DictationHistoryController: ObservableObject {
    typealias LoadOperation = @Sendable () async throws -> [DictationHistoryRecord]
    typealias SaveOperation = @Sendable (DictationHistoryRecord) async throws -> Void
    typealias DeleteOperation = @Sendable (UUID) async throws -> Void
    typealias ClearOperation = @Sendable () async throws -> Void

    @Published private(set) var records: [DictationHistoryRecord]
    @Published var errorMessage: String?
    @Published private(set) var generation = 0

    private let loadOperation: LoadOperation
    private let saveOperation: SaveOperation
    private let deleteOperation: DeleteOperation
    private let clearOperation: ClearOperation
    private var writeTail: Task<Void, Never>?

    init(
      records: [DictationHistoryRecord] = [],
      load: @escaping LoadOperation,
      save: @escaping SaveOperation,
      delete: @escaping DeleteOperation,
      clear: @escaping ClearOperation
    ) {
      self.records = records
      loadOperation = load
      saveOperation = save
      deleteOperation = delete
      clearOperation = clear
    }

    convenience init(store: DictationHistoryStore) {
      self.init(
        load: { try await store.list() },
        save: { try await store.save($0) },
        delete: { try await store.delete(id: $0) },
        clear: { try await store.clear() }
      )
    }

    func load() async {
      await enqueue {
        do {
          self.records = try await self.loadOperation()
          self.errorMessage = nil
        } catch {
          self.errorMessage = "Could not load dictation history: \(error.localizedDescription)"
        }
      }
    }

    @discardableResult
    func save(_ record: DictationHistoryRecord) async -> Bool {
      var saved = false
      await enqueue {
        let previous = self.records
        self.records.removeAll { $0.id == record.id }
        self.records.append(record)
        self.records.sort { $0.completedAt > $1.completedAt }
        do {
          try await self.saveOperation(record)
          self.errorMessage = nil
          saved = true
        } catch {
          self.records = previous
          self.errorMessage = "Could not update dictation history: \(error.localizedDescription)"
        }
      }
      return saved
    }

    @discardableResult
    func delete(_ id: UUID) async -> Bool {
      var deleted = false
      await enqueue {
        let previous = self.records
        self.records.removeAll { $0.id == id }
        do {
          try await self.deleteOperation(id)
          self.errorMessage = nil
          deleted = true
        } catch {
          self.records = previous
          self.errorMessage = "Could not update dictation history: \(error.localizedDescription)"
        }
      }
      return deleted
    }

    func clear() async {
      await enqueue {
        let previous = self.records
        self.records.removeAll()
        do {
          try await self.clearOperation()
          self.errorMessage = nil
        } catch {
          self.records = previous
          self.errorMessage = "Could not update dictation history: \(error.localizedDescription)"
        }
      }
    }

    func waitForPendingWrites() async {
      await writeTail?.value
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
      let previous = writeTail
      let task = Task { @MainActor in
        await previous?.value
        await operation()
        generation += 1
      }
      writeTail = task
      await task.value
    }
  }

  @MainActor
  final class DictationHistoryViewModel: ObservableObject {
    @Published private(set) var pendingConfirmation: DictationHistoryConfirmation?
    let controller: DictationHistoryController

    init(controller: DictationHistoryController) {
      self.controller = controller
    }

    func requestClear() {
      pendingConfirmation = .clear
    }

    func requestDelete(_ id: UUID) {
      pendingConfirmation = .delete(id)
    }

    func cancelConfirmation() {
      pendingConfirmation = nil
    }

    func confirmRemoval() async {
      guard let removal = pendingConfirmation else { return }
      pendingConfirmation = nil
      switch removal {
      case .clear:
        await controller.clear()
      case .delete(let id):
        await controller.delete(id)
      }
    }
  }

  struct DictationHistoryRowPresentation: Equatable {
    let primaryTitle: String
    let primaryTranscript: String
    let rawTranscript: String?
    let canCopyClean: Bool

    init(record: DictationHistoryRecord) {
      if let cleaned = record.cleanedTranscript, record.cleanupOutcome == .cleaned {
        primaryTitle = "Cleaned"
        primaryTranscript = cleaned
        rawTranscript = record.rawTranscript
        canCopyClean = true
      } else {
        primaryTitle = "Raw fallback"
        primaryTranscript = record.rawTranscript
        rawTranscript = nil
        canCopyClean = false
      }
    }
  }

  struct DictationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DictationHistoryViewModel
    @ObservedObject private var history: DictationHistoryController
    let onOpenDestination: (UUID) -> Void

    init(
      history: DictationHistoryController,
      onOpenDestination: @escaping (UUID) -> Void
    ) {
      _model = StateObject(wrappedValue: DictationHistoryViewModel(controller: history))
      _history = ObservedObject(wrappedValue: history)
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
          .disabled(history.records.isEmpty)
          Button("Done") {
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
        }
        .padding()

        Divider()

        if history.records.isEmpty {
          ContentUnavailableView(
            "No Dictation History",
            systemImage: "waveform",
            description: Text("Successful captures kept for recovery appear here for 30 days.")
          )
        } else {
          List(history.records) { record in
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
        await history.load()
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
          get: { history.errorMessage != nil },
          set: { if !$0 { history.errorMessage = nil } }
        )
      ) {
        Button("OK") {
          history.errorMessage = nil
        }
      } message: {
        Text(history.errorMessage ?? "")
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
      let presentation = DictationHistoryRowPresentation(record: record)
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.headline)
          Spacer()
          Label(destinationTitle, systemImage: destinationSymbol)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        transcript(presentation.primaryTitle, text: presentation.primaryTranscript)
        if let rawTranscript = presentation.rawTranscript {
          transcript("Raw", text: rawTranscript)
        }

        HStack {
          if presentation.canCopyClean {
            Button("Copy Clean") {
              copy(presentation.primaryTranscript)
            }
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
