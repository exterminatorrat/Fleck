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
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
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

@MainActor
protocol DictationProcessing: AnyObject {
  func prepare(for intent: DictationPreparationIntent) async
  func begin(
    configuration: DictationProcessingConfiguration,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws -> any DictationProcessingSession
  func handle(_ signal: DictationRuntimeSignal) async
}

@MainActor
protocol DictationProcessingSession: AnyObject {
  var updates: AsyncThrowingStream<DictationTextUpdate, Error> { get }
  func finish() async throws -> DictationProcessingResult
  func finish(
    deadlineOrigin: ContinuousClock.Instant
  ) async throws -> DictationProcessingResult
  // All callers await one source-unblocking/finalization/cleanup cancellation
  // task before terminal cancellation returns.
  func cancel() async
}

extension DictationProcessingSession {
  func finish(
    deadlineOrigin: ContinuousClock.Instant
  ) async throws -> DictationProcessingResult {
    try await finish()
  }
}

protocol TranscriptDictionaryResolving: Sendable {
  func resolve(_ rawTranscript: String) async throws -> PersonalDictionaryResolution
}

struct DictationRoutingCandidate: Equatable, Sendable {
  let destination: DictationDestination
  let semanticContext: String
  let contentRevision: UInt64

  init(
    destination: DictationDestination,
    semanticContext: String,
    contentRevision: UInt64 = 0
  ) {
    self.destination = destination
    self.semanticContext = semanticContext
    self.contentRevision = contentRevision
  }
}

struct DictationRoutingChoice: Equatable, Sendable {
  let destination: DictationDestination
  let contextHint: String

  static func boundedContextHint(from excerpt: String) -> String {
    let normalized = excerpt.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    return String(normalized.prefix(160))
  }
}

enum DictationRoutingDecision: Equatable, Sendable {
  case resolved(UUID)
  case ambiguous([DictationRoutingChoice])
  case inbox
}

struct DictationRoutingAmbiguity: Equatable, Sendable {
  let captureID: UUID
  let choices: [DictationRoutingChoice]
}

@MainActor
protocol StreamingSpeechSource: AnyObject {
  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  func releaseResources() async
}

protocol DestinationRouting: Sendable {
  func route(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    inboxID: UUID?
  ) async -> DictationRoutingDecision
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
  func activeDestinations() -> [DictationRoutingCandidate]
  func saveSmartCapture(
    text: String,
    captureID: UUID,
    destinationID: UUID?
  ) async throws -> DictationInsertionReceipt
  func moveSmartCapture(
    _ receipt: DictationInsertionReceipt,
    to destinationID: UUID
  ) async -> DictationInsertionReceipt?
  func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool
  func flushFocusedDictationSave(
    captureID: UUID
  ) async throws -> FocusedDictationPersistenceReceipt
  func compensateFocusedDictationSave(
    _ receipt: FocusedDictationPersistenceReceipt
  ) async -> Bool
}

extension DictationSaving {
  func moveSmartCapture(
    _ receipt: DictationInsertionReceipt,
    to destinationID: UUID
  ) async -> DictationInsertionReceipt? {
    nil
  }
}
