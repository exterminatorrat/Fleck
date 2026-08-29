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
  enum Integrity: Equatable, Sendable {
    case valid
    case nonMonotonicClock
  }

  let integrity: Integrity
  let processorStartedAt: ContinuousClock.Instant?
  let sourceStartRequestedAt: ContinuousClock.Instant?
  let firstMeaningfulPartialAt: ContinuousClock.Instant?
  let stopRequestedAt: ContinuousClock.Instant?
  let asrFinalAt: ContinuousClock.Instant?
  let dictionaryCompletedAt: ContinuousClock.Instant?
  let cleanupDecisionCompletedAt: ContinuousClock.Instant?
  let cancellationRequestedAt: ContinuousClock.Instant?
  let cancellationDrainedAt: ContinuousClock.Instant?

  init(
    integrity: Integrity = .valid,
    processorStartedAt: ContinuousClock.Instant? = nil,
    sourceStartRequestedAt: ContinuousClock.Instant? = nil,
    firstMeaningfulPartialAt: ContinuousClock.Instant? = nil,
    stopRequestedAt: ContinuousClock.Instant? = nil,
    asrFinalAt: ContinuousClock.Instant? = nil,
    dictionaryCompletedAt: ContinuousClock.Instant? = nil,
    cleanupDecisionCompletedAt: ContinuousClock.Instant? = nil,
    cancellationRequestedAt: ContinuousClock.Instant? = nil,
    cancellationDrainedAt: ContinuousClock.Instant? = nil
  ) {
    self.integrity = integrity
    self.processorStartedAt = processorStartedAt
    self.sourceStartRequestedAt = sourceStartRequestedAt
    self.firstMeaningfulPartialAt = firstMeaningfulPartialAt
    self.stopRequestedAt = stopRequestedAt
    self.asrFinalAt = asrFinalAt
    self.dictionaryCompletedAt = dictionaryCompletedAt
    self.cleanupDecisionCompletedAt = cleanupDecisionCompletedAt
    self.cancellationRequestedAt = cancellationRequestedAt
    self.cancellationDrainedAt = cancellationDrainedAt
  }

  var firstMeaningfulPartialMilliseconds: Double? {
    milliseconds(from: processorStartedAt, to: firstMeaningfulPartialAt)
  }

  var finalASRMilliseconds: Double? {
    milliseconds(from: stopRequestedAt, to: asrFinalAt)
  }

  var cleanupMilliseconds: Double? {
    milliseconds(from: dictionaryCompletedAt, to: cleanupDecisionCompletedAt)
  }

  var stopToInsertionMilliseconds: Double? { nil }

  var cancellationMilliseconds: Double? {
    milliseconds(from: cancellationRequestedAt, to: cancellationDrainedAt)
  }

  static let empty = Self()

  private func milliseconds(
    from start: ContinuousClock.Instant?,
    to end: ContinuousClock.Instant?
  ) -> Double? {
    guard integrity == .valid, let start, let end, end >= start else { return nil }
    let components = start.duration(to: end).components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
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
