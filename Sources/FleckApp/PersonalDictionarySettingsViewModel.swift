import Foundation
import FleckCore
import SwiftUI

@MainActor
final class PersonalDictionarySettingsViewModel: ObservableObject {
  @Published private(set) var entries: [PersonalDictionaryEntry] = []
  @Published private(set) var errorMessage: String?

  private let store: PersonalDictionaryStore
  private var mutationTail: Task<Void, Never>?

  init(store: PersonalDictionaryStore) {
    self.store = store
  }

  func load() async {
    await enqueue {
      do {
        try await self.reload()
        self.errorMessage = nil
      } catch {
        self.errorMessage = Self.message(for: error, action: "load")
      }
    }
  }

  func add(preferredForm: String, aliases: String) async {
    await enqueue {
      let preferredForm = preferredForm.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !preferredForm.isEmpty else {
        self.errorMessage = "Enter a preferred form before adding the entry."
        return
      }

      do {
        let snapshot = try await self.store.snapshot()
        let existing = snapshot.entries.first {
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
        try await self.store.upsert(entry)
        try await self.reload()
        self.errorMessage = nil
      } catch {
        self.errorMessage = Self.message(for: error, action: "add")
      }
    }
  }

  func setEnabled(_ enabled: Bool, id: UUID) async {
    await enqueue {
      do {
        try await self.store.setEnabled(enabled, id: id)
        try await self.reload()
        self.errorMessage = nil
      } catch {
        self.errorMessage = Self.message(for: error, action: "update")
      }
    }
  }

  func delete(id: UUID) async {
    await enqueue {
      do {
        try await self.store.delete(id: id)
        try await self.reload()
        self.errorMessage = nil
      } catch {
        self.errorMessage = Self.message(for: error, action: "delete")
      }
    }
  }

  private func reload() async throws {
    let snapshot = try await store.snapshot()
    entries = Self.sorted(snapshot.entries)
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

  private static func parseAliases(_ text: String) -> [String] {
    var seen = Set<String>()
    return text
      .components(separatedBy: CharacterSet(charactersIn: ",\n"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { seen.insert(normalized($0)).inserted }
  }

  private static func sorted(_ entries: [PersonalDictionaryEntry])
    -> [PersonalDictionaryEntry] {
    entries.sorted { lhs, rhs in
      let left = normalized(lhs.preferredForm)
      let right = normalized(rhs.preferredForm)
      if left != right { return left < right }
      if lhs.preferredForm != rhs.preferredForm {
        return lhs.preferredForm < rhs.preferredForm
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private static func normalized(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }

  private static func message(for error: Error, action: String) -> String {
    switch error as? PersonalDictionaryStoreError {
    case .invalidEntry:
      return "Could not add personal dictionary entry. Check the preferred form and aliases."
    case .corruptData, .fileTooLarge, .unsupportedSchemaVersion, .invalidSnapshot:
      return "Could not \(action) personal dictionary. The saved dictionary is invalid or unsupported."
    default:
      return "Could not \(action) personal dictionary. Try again."
    }
  }
}
