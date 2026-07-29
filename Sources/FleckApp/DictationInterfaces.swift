import Foundation
import FleckCore

struct FocusedDictationCommitReceipt: Equatable, Hashable, Sendable {
  let id: UUID

  init(id: UUID = UUID()) {
    self.id = id
  }
}

struct FocusedDictationPersistenceReceipt: Equatable, Sendable {
  let captureID: UUID
}

@MainActor
protocol SpeechEngine: AnyObject {
  var kind: DictationSpeechEngine { get }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  func releaseResources() async
}

@MainActor
protocol SpeechEngineProviding: AnyObject {
  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine
}

protocol TranscriptCleaning: Sendable {
  func clean(_ rawTranscript: String) async throws -> String
}

protocol DestinationRouting: Sendable {
  func route(
    transcript: String,
    candidates: [DictationDestination],
    inboxID: UUID?
  ) async -> UUID?
}

@MainActor
protocol FocusedDictationEditing: AnyObject {
  var canBeginFocusedDictation: Bool { get }
  func beginFocusedDictation() -> Bool
  func updateFocusedDictation(provisionalText: String)
  func commitFocusedDictation(text: String) -> FocusedDictationCommitReceipt?
  func cancelFocusedDictation()
  func rollbackCommittedFocusedDictation(_ receipt: FocusedDictationCommitReceipt) -> Bool
  func finalizeCommittedFocusedDictation(_ receipt: FocusedDictationCommitReceipt)
}

@MainActor
protocol DictationSaving: AnyObject {
  func activeDestinations() -> [DictationDestination]
  func saveSmartCapture(
    text: String,
    captureID: UUID,
    destinationID: UUID?
  ) async throws -> DictationInsertionReceipt
  func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool
  func flushFocusedDictationSave(
    captureID: UUID
  ) async throws -> FocusedDictationPersistenceReceipt
  func compensateFocusedDictationSave(
    _ receipt: FocusedDictationPersistenceReceipt
  ) async -> Bool
}
