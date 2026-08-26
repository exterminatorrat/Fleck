import Foundation
import FleckCore

enum DictationPreparationIntent: Equatable, Sendable {
  case likelyCapture
  case immediateCapture
}

enum DictationRuntimeSignal: Equatable, Sendable {
  case memoryWarning
  case memoryCritical
  case thermalSerious
  case thermalCritical
  case lowPowerMode(Bool)
  case willSleep
  case didWake
  case modelMutationWillBegin
}

struct DictationRecognitionContext: Equatable, Sendable {
  let locale: Locale
  let contextualStrings: [String]

  init(locale: Locale, contextualStrings: [String] = []) {
    self.locale = locale
    var unique: [String] = []
    var seen = Set<String>()
    for value in contextualStrings
    where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      guard seen.insert(value).inserted else { continue }
      unique.append(value)
      if unique.count == 100 { break }
    }
    self.contextualStrings = unique
  }

  static let englishDefault = Self(locale: Locale(identifier: "en-US"))
}

struct DictationProcessingConfiguration: Equatable, Sendable {
  let captureID: UUID
  let mode: DictationMode
  let recognitionContext: DictationRecognitionContext
  let engine: DictationSpeechEngine

  init(
    captureID: UUID,
    mode: DictationMode,
    recognitionContext: DictationRecognitionContext,
    engine: DictationSpeechEngine = .standard
  ) {
    self.captureID = captureID
    self.mode = mode
    self.recognitionContext = recognitionContext
    self.engine = engine
  }
}

struct DictationTextUpdate: Equatable, Sendable {
  let generation: UInt64
  let stableText: String
  let provisionalTail: String
  var displayText: String { stableText + provisionalTail }
}

struct DictationRuntimeMeasurements: Equatable, Sendable {
  var firstMeaningfulPartialMilliseconds: Double? = nil
  var finalASRMilliseconds: Double? = nil
  var cleanupMilliseconds: Double? = nil
  var stopToInsertionMilliseconds: Double? = nil
  var cancellationMilliseconds: Double? = nil

  static let empty = Self()
}

struct DictationProcessingResult: Equatable, Sendable {
  let rawTranscript: String
  let dictionaryBaseline: String?
  let cleanedTranscript: String?
  let insertedText: String
  let cleanupOutcome: DictationCleanupOutcome
  let measurements: DictationRuntimeMeasurements
}

struct DictationProcessingBudget: Equatable, Sendable {
  let insertion: Duration
  let cleanup: Duration

  static let production = Self(
    insertion: .seconds(4),
    cleanup: .milliseconds(3_500)
  )
}

struct DictationClock: Sendable {
  let now: @Sendable () -> ContinuousClock.Instant

  static let live = Self(now: { ContinuousClock().now })
}

struct DictationDeadline: Sendable {
  let stopInstant: ContinuousClock.Instant
  let insertionDeadline: ContinuousClock.Instant
  let cleanupDeadline: ContinuousClock.Instant

  init(
    stopInstant: ContinuousClock.Instant,
    insertionDeadline: ContinuousClock.Instant,
    cleanupBudget: Duration
  ) {
    self.stopInstant = stopInstant
    self.insertionDeadline = insertionDeadline
    cleanupDeadline = min(
      stopInstant.advanced(by: cleanupBudget),
      insertionDeadline
    )
  }
}
