import Foundation
import MenuBarNotesCore

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
  func commitFocusedDictation(text: String) -> Bool
  func cancelFocusedDictation()
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
  func flushFocusedDictationSave() async throws
}
