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

enum LocalWritingCaptureContextError: Error, Equatable, Sendable {
  case dictionaryRevisionMismatch
  case localeMismatch
}

struct LocalWritingCaptureContext: Equatable, Sendable {
  let captureID: UUID
  let generation: UInt64
  let localeIdentifier: String
  let speechEngine: DictationSpeechEngine
  let snapshot: PersonalDictionarySnapshotV2
  let compiledDictionary: CompiledPersonalDictionary

  var dictionaryRevision: UInt64 { compiledDictionary.revision }
  var dictionaryContentDigest: String { compiledDictionary.contentDigest }
  var dictionaryCompilerPolicyRevision: Int {
    compiledDictionary.compilerPolicyRevision
  }

  init(
    captureID: UUID,
    generation: UInt64,
    localeIdentifier: String,
    speechEngine: DictationSpeechEngine,
    snapshot: PersonalDictionarySnapshotV2,
    compiledDictionary: CompiledPersonalDictionary
  ) throws {
    guard snapshot.revision == compiledDictionary.revision else {
      throw LocalWritingCaptureContextError.dictionaryRevisionMismatch
    }
    guard localeIdentifier == compiledDictionary.localeIdentifier else {
      throw LocalWritingCaptureContextError.localeMismatch
    }
    self.captureID = captureID
    self.generation = generation
    self.localeIdentifier = localeIdentifier
    self.speechEngine = speechEngine
    self.snapshot = snapshot
    self.compiledDictionary = compiledDictionary
  }
}

enum DictationRecognitionContextAcknowledgement: Equatable, Sendable {
  case applied(LocalWritingCaptureContext)
  case unsupported(LocalWritingCaptureContext)
  case rejected(LocalWritingCaptureContext)

  var context: LocalWritingCaptureContext {
    switch self {
    case .applied(let context), .unsupported(let context), .rejected(let context):
      context
    }
  }
}

struct DictationProcessingConfiguration: Equatable, Sendable {
  let captureID: UUID
  let captureGeneration: UInt64
  let mode: DictationMode
  let recognitionContext: DictationRecognitionContext
  let engine: DictationSpeechEngine
  let captureContext: LocalWritingCaptureContext?

  init(
    captureID: UUID,
    mode: DictationMode,
    recognitionContext: DictationRecognitionContext,
    engine: DictationSpeechEngine = .standard
  ) {
    self.captureID = captureID
    captureGeneration = 0
    self.mode = mode
    self.recognitionContext = recognitionContext
    self.engine = engine
    captureContext = nil
  }

  init(mode: DictationMode, captureContext: LocalWritingCaptureContext) {
    captureID = captureContext.captureID
    captureGeneration = captureContext.generation
    self.mode = mode
    recognitionContext = DictationRecognitionContext(
      locale: Locale(identifier: captureContext.localeIdentifier),
      contextualStrings: captureContext.compiledDictionary.recognitionStrings
    )
    engine = captureContext.speechEngine
    self.captureContext = captureContext
  }
}

struct DictationTextUpdate: Equatable, Sendable {
  let generation: UInt64
  let stableText: String
  let provisionalTail: String
  var displayText: String { stableText + provisionalTail }
}

struct DictationPhysicalGesture: Equatable, Sendable {
  let pressedAt: ContinuousClock.Instant?
  let releasedAt: ContinuousClock.Instant?

  init(
    pressedAt: ContinuousClock.Instant? = nil,
    releasedAt: ContinuousClock.Instant? = nil
  ) {
    self.pressedAt = pressedAt
    self.releasedAt = releasedAt
  }

  static let absent = Self()
}

struct DictationRuntimeMeasurements: Equatable, Sendable {
  enum Integrity: Equatable, Sendable {
    case valid
    case nonMonotonicClock
  }

  enum Stage: CaseIterable, Equatable, Sendable {
    case physicalPress
    case processorStarted
    case sourceStartRequested
    case firstMeaningfulPartial
    case physicalRelease
    case stopRequested
    case asrFinal
    case dictionaryCompleted
    case cleanupDecisionCompleted
    case routingRequested
    case routingDecision
    case insertionCommitted
    case persistenceCompleted
    case ambiguityPresented
    case ambiguityMoved
    case cancellationRequested
    case compensationCompleted
    case cancellationDrained
  }

  private(set) var integrity: Integrity
  private(set) var physicalPressAt: ContinuousClock.Instant?
  private(set) var processorStartedAt: ContinuousClock.Instant?
  private(set) var sourceStartRequestedAt: ContinuousClock.Instant?
  private(set) var firstMeaningfulPartialAt: ContinuousClock.Instant?
  private(set) var physicalReleaseAt: ContinuousClock.Instant?
  private(set) var stopRequestedAt: ContinuousClock.Instant?
  private(set) var asrFinalAt: ContinuousClock.Instant?
  private(set) var dictionaryCompletedAt: ContinuousClock.Instant?
  private(set) var cleanupDecisionCompletedAt: ContinuousClock.Instant?
  private(set) var routingRequestedAt: ContinuousClock.Instant?
  private(set) var routingDecisionAt: ContinuousClock.Instant?
  private(set) var insertionCommittedAt: ContinuousClock.Instant?
  private(set) var persistenceCompletedAt: ContinuousClock.Instant?
  private(set) var ambiguityPresentedAt: ContinuousClock.Instant?
  private(set) var ambiguityMovedAt: ContinuousClock.Instant?
  private(set) var cancellationRequestedAt: ContinuousClock.Instant?
  private(set) var compensationCompletedAt: ContinuousClock.Instant?
  private(set) var cancellationDrainedAt: ContinuousClock.Instant?
  private var isTerminal: Bool

  init(
    integrity: Integrity = .valid,
    physicalPressAt: ContinuousClock.Instant? = nil,
    processorStartedAt: ContinuousClock.Instant? = nil,
    sourceStartRequestedAt: ContinuousClock.Instant? = nil,
    firstMeaningfulPartialAt: ContinuousClock.Instant? = nil,
    physicalReleaseAt: ContinuousClock.Instant? = nil,
    stopRequestedAt: ContinuousClock.Instant? = nil,
    asrFinalAt: ContinuousClock.Instant? = nil,
    dictionaryCompletedAt: ContinuousClock.Instant? = nil,
    cleanupDecisionCompletedAt: ContinuousClock.Instant? = nil,
    routingRequestedAt: ContinuousClock.Instant? = nil,
    routingDecisionAt: ContinuousClock.Instant? = nil,
    insertionCommittedAt: ContinuousClock.Instant? = nil,
    persistenceCompletedAt: ContinuousClock.Instant? = nil,
    ambiguityPresentedAt: ContinuousClock.Instant? = nil,
    ambiguityMovedAt: ContinuousClock.Instant? = nil,
    cancellationRequestedAt: ContinuousClock.Instant? = nil,
    compensationCompletedAt: ContinuousClock.Instant? = nil,
    cancellationDrainedAt: ContinuousClock.Instant? = nil
  ) {
    self.integrity = integrity
    self.physicalPressAt = physicalPressAt
    self.processorStartedAt = processorStartedAt
    self.sourceStartRequestedAt = sourceStartRequestedAt
    self.firstMeaningfulPartialAt = firstMeaningfulPartialAt
    self.physicalReleaseAt = physicalReleaseAt
    self.stopRequestedAt = stopRequestedAt
    self.asrFinalAt = asrFinalAt
    self.dictionaryCompletedAt = dictionaryCompletedAt
    self.cleanupDecisionCompletedAt = cleanupDecisionCompletedAt
    self.routingRequestedAt = routingRequestedAt
    self.routingDecisionAt = routingDecisionAt
    self.insertionCommittedAt = insertionCommittedAt
    self.persistenceCompletedAt = persistenceCompletedAt
    self.ambiguityPresentedAt = ambiguityPresentedAt
    self.ambiguityMovedAt = ambiguityMovedAt
    self.cancellationRequestedAt = cancellationRequestedAt
    self.compensationCompletedAt = compensationCompletedAt
    self.cancellationDrainedAt = cancellationDrainedAt
    isTerminal = false
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

  var stopToInsertionMilliseconds: Double? {
    milliseconds(
      from: physicalReleaseAt ?? stopRequestedAt,
      to: insertionCommittedAt
    )
  }

  var cancellationMilliseconds: Double? {
    milliseconds(from: cancellationRequestedAt, to: cancellationDrainedAt)
  }

  static let empty = Self()

  func recording(
    _ stage: Stage,
    at instant: ContinuousClock.Instant
  ) -> Self {
    guard integrity == .valid, !isTerminal, value(for: stage) == nil else { return self }
    var candidate = self
    if let latest = Stage.allCases.compactMap({ value(for: $0) }).max(),
      instant < latest
    {
      candidate = self
      candidate.integrity = .nonMonotonicClock
      return candidate
    }
    candidate.assign(instant, to: stage)
    return candidate
  }

  func overlaying(_ measurements: Self) -> Self {
    guard integrity == .valid, !isTerminal else { return self }
    var result = self
    var previous: ContinuousClock.Instant?
    var hasViolation = measurements.integrity == .nonMonotonicClock
    for (index, stage) in Stage.allCases.enumerated() {
      if let existing = value(for: stage) {
        if let previous, existing < previous {
          hasViolation = true
        }
        previous = max(previous ?? existing, existing)
        continue
      }
      guard let incoming = measurements.value(for: stage) else { continue }
      let nextExisting = Stage.allCases.dropFirst(index + 1)
        .compactMap { value(for: $0) }
        .first
      if previous.map({ incoming < $0 }) == true
        || nextExisting.map({ incoming > $0 }) == true
      {
        hasViolation = true
        continue
      }
      result.assign(incoming, to: stage)
      previous = incoming
    }
    if hasViolation {
      result.integrity = .nonMonotonicClock
    }
    return result
  }

  func terminal() -> Self {
    var result = self
    result.isTerminal = true
    return result
  }

  private func value(for stage: Stage) -> ContinuousClock.Instant? {
    switch stage {
    case .physicalPress: physicalPressAt
    case .processorStarted: processorStartedAt
    case .sourceStartRequested: sourceStartRequestedAt
    case .firstMeaningfulPartial: firstMeaningfulPartialAt
    case .physicalRelease: physicalReleaseAt
    case .stopRequested: stopRequestedAt
    case .asrFinal: asrFinalAt
    case .dictionaryCompleted: dictionaryCompletedAt
    case .cleanupDecisionCompleted: cleanupDecisionCompletedAt
    case .routingRequested: routingRequestedAt
    case .routingDecision: routingDecisionAt
    case .insertionCommitted: insertionCommittedAt
    case .persistenceCompleted: persistenceCompletedAt
    case .ambiguityPresented: ambiguityPresentedAt
    case .ambiguityMoved: ambiguityMovedAt
    case .cancellationRequested: cancellationRequestedAt
    case .compensationCompleted: compensationCompletedAt
    case .cancellationDrained: cancellationDrainedAt
    }
  }

  private mutating func assign(
    _ instant: ContinuousClock.Instant,
    to stage: Stage
  ) {
    switch stage {
    case .physicalPress: physicalPressAt = instant
    case .processorStarted: processorStartedAt = instant
    case .sourceStartRequested: sourceStartRequestedAt = instant
    case .firstMeaningfulPartial: firstMeaningfulPartialAt = instant
    case .physicalRelease: physicalReleaseAt = instant
    case .stopRequested: stopRequestedAt = instant
    case .asrFinal: asrFinalAt = instant
    case .dictionaryCompleted: dictionaryCompletedAt = instant
    case .cleanupDecisionCompleted: cleanupDecisionCompletedAt = instant
    case .routingRequested: routingRequestedAt = instant
    case .routingDecision: routingDecisionAt = instant
    case .insertionCommitted: insertionCommittedAt = instant
    case .persistenceCompleted: persistenceCompletedAt = instant
    case .ambiguityPresented: ambiguityPresentedAt = instant
    case .ambiguityMoved: ambiguityMovedAt = instant
    case .cancellationRequested: cancellationRequestedAt = instant
    case .compensationCompleted: compensationCompletedAt = instant
    case .cancellationDrained: cancellationDrainedAt = instant
    }
  }

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
  let captureContext: LocalWritingCaptureContext?
  let recognitionContextAcknowledgement: DictationRecognitionContextAcknowledgement?
  let protectedDictionaryForms: [String]
  let appliedDictionaryEntryIDs: [UUID]

  var dictionaryRevision: UInt64? { captureContext?.dictionaryRevision }
  var dictionaryContentDigest: String? { captureContext?.dictionaryContentDigest }

  init(
    rawTranscript: String,
    dictionaryBaseline: String?,
    cleanedTranscript: String?,
    insertedText: String,
    cleanupOutcome: DictationCleanupOutcome,
    measurements: DictationRuntimeMeasurements,
    captureContext: LocalWritingCaptureContext? = nil,
    recognitionContextAcknowledgement: DictationRecognitionContextAcknowledgement? = nil,
    protectedDictionaryForms: [String] = [],
    appliedDictionaryEntryIDs: [UUID] = []
  ) {
    self.rawTranscript = rawTranscript
    self.dictionaryBaseline = dictionaryBaseline
    self.cleanedTranscript = cleanedTranscript
    self.insertedText = insertedText
    self.cleanupOutcome = cleanupOutcome
    self.measurements = measurements
    self.captureContext = captureContext
    self.recognitionContextAcknowledgement = recognitionContextAcknowledgement
    self.protectedDictionaryForms = protectedDictionaryForms
    self.appliedDictionaryEntryIDs = appliedDictionaryEntryIDs
  }
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
