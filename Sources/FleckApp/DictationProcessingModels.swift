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
  case dictionaryContentMismatch
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
    guard (try? CompiledPersonalDictionary.compile(snapshot)) == compiledDictionary else {
      throw LocalWritingCaptureContextError.dictionaryContentMismatch
    }
    self.captureID = captureID
    self.generation = generation
    self.localeIdentifier = localeIdentifier
    self.speechEngine = speechEngine
    self.snapshot = snapshot
    self.compiledDictionary = compiledDictionary
  }

  init(
    captureID: UUID,
    generation: UInt64,
    localeIdentifier: String,
    speechEngine: DictationSpeechEngine,
    publishedSnapshot: PersonalDictionaryPublishedSnapshot
  ) throws {
    guard publishedSnapshot.snapshot.revision == publishedSnapshot.compiled.revision else {
      throw LocalWritingCaptureContextError.dictionaryRevisionMismatch
    }
    guard localeIdentifier == publishedSnapshot.compiled.localeIdentifier else {
      throw LocalWritingCaptureContextError.localeMismatch
    }
    self.captureID = captureID
    self.generation = generation
    self.localeIdentifier = localeIdentifier
    self.speechEngine = speechEngine
    snapshot = publishedSnapshot.snapshot
    compiledDictionary = publishedSnapshot.compiled
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

enum DictationStopOrigin: Equatable, Sendable {
  case physicalRelease(ContinuousClock.Instant)
  case handsFreeKeyPress(ContinuousClock.Instant)
  case toolbarAction(ContinuousClock.Instant)

  var instant: ContinuousClock.Instant {
    switch self {
    case .physicalRelease(let instant),
      .handsFreeKeyPress(let instant),
      .toolbarAction(let instant):
      instant
    }
  }

  var physicalReleaseAt: ContinuousClock.Instant? {
    guard case .physicalRelease(let instant) = self else { return nil }
    return instant
  }
}

struct DictationRuntimeMeasurements: Equatable, Sendable {
  enum Integrity: String, Codable, Equatable, Sendable {
    case valid
    case nonMonotonicClock = "non_monotonic_clock"
  }

  enum Outcome: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
  }

  enum Failure: String, Codable, Equatable, Sendable {
    case permissionDenied = "permission_denied"
    case missingInput = "missing_input"
    case modelUnavailable = "model_unavailable"
    case modelLoadFailure = "model_load_failure"
    case startupTimeout = "startup_timeout"
    case bufferLimit = "buffer_limit"
    case sourceStartupFailure = "source_startup_failure"
    case sourceFailure = "source_failure"
    case processingFailure = "processing_failure"
    case routingFailure = "routing_failure"
    case persistenceFailure = "persistence_failure"
    case noSpeech = "no_speech"
  }

  enum LoadDisposition: String, Codable, Equatable, Sendable {
    case cold
    case warm
  }

  enum Stage: String, CaseIterable, Codable, Equatable, Sendable {
    case physicalPress = "physical_press"
    case coordinatorEventReceived = "coordinator_event_received"
    case phasePublished = "phase_published"
    case processorStarted = "processor_started"
    case sourceStartRequested = "source_start_requested"
    case audioStartRequested = "audio_start_requested"
    case firstInputBuffer = "first_input_buffer"
    case modelLoadRequested = "model_load_requested"
    case modelReady = "model_ready"
    case audioReadyObserved = "audio_ready_observed"
    case firstMeaningfulPartial = "first_meaningful_partial"
    case physicalRelease = "physical_release"
    case stopRequested = "stop_requested"
    case asrFinal = "asr_final"
    case dictionaryCompleted = "dictionary_completed"
    case cleanupDecisionCompleted = "cleanup_decision_completed"
    case routingRequested = "routing_requested"
    case routingDecision = "routing_decision"
    case insertionCommitted = "insertion_committed"
    case persistenceCompleted = "persistence_completed"
    case ambiguityPresented = "ambiguity_presented"
    case ambiguityMoved = "ambiguity_moved"
    case cancellationRequested = "cancellation_requested"
    case compensationCompleted = "compensation_completed"
    case cancellationDrained = "cancellation_drained"
  }

  private(set) var integrity: Integrity
  private(set) var physicalPressAt: ContinuousClock.Instant?
  private(set) var coordinatorEventReceivedAt: ContinuousClock.Instant?
  private(set) var phasePublishedAt: ContinuousClock.Instant?
  private(set) var processorStartedAt: ContinuousClock.Instant?
  private(set) var sourceStartRequestedAt: ContinuousClock.Instant?
  private(set) var audioStartRequestedAt: ContinuousClock.Instant?
  private(set) var firstInputBufferAt: ContinuousClock.Instant?
  private(set) var modelLoadRequestedAt: ContinuousClock.Instant?
  private(set) var modelReadyAt: ContinuousClock.Instant?
  private(set) var audioReadyObservedAt: ContinuousClock.Instant?
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
  private(set) var outcome: Outcome?
  private(set) var failure: Failure?
  private(set) var loadDisposition: LoadDisposition?
  private var isTerminal: Bool

  init(
    integrity: Integrity = .valid,
    physicalPressAt: ContinuousClock.Instant? = nil,
    coordinatorEventReceivedAt: ContinuousClock.Instant? = nil,
    phasePublishedAt: ContinuousClock.Instant? = nil,
    processorStartedAt: ContinuousClock.Instant? = nil,
    sourceStartRequestedAt: ContinuousClock.Instant? = nil,
    audioStartRequestedAt: ContinuousClock.Instant? = nil,
    firstInputBufferAt: ContinuousClock.Instant? = nil,
    modelLoadRequestedAt: ContinuousClock.Instant? = nil,
    modelReadyAt: ContinuousClock.Instant? = nil,
    audioReadyObservedAt: ContinuousClock.Instant? = nil,
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
    cancellationDrainedAt: ContinuousClock.Instant? = nil,
    outcome: Outcome? = nil,
    failure: Failure? = nil,
    loadDisposition: LoadDisposition? = nil
  ) {
    self.integrity = integrity
    self.physicalPressAt = physicalPressAt
    self.coordinatorEventReceivedAt = coordinatorEventReceivedAt
    self.phasePublishedAt = phasePublishedAt
    self.processorStartedAt = processorStartedAt
    self.sourceStartRequestedAt = sourceStartRequestedAt
    self.audioStartRequestedAt = audioStartRequestedAt
    self.firstInputBufferAt = firstInputBufferAt
    self.modelLoadRequestedAt = modelLoadRequestedAt
    self.modelReadyAt = modelReadyAt
    self.audioReadyObservedAt = audioReadyObservedAt
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
    self.outcome = outcome
    self.failure = failure
    self.loadDisposition = loadDisposition
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

  var diagnostics: Diagnostics {
    Diagnostics(measurements: self)
  }

  func recording(
    _ stage: Stage,
    at instant: ContinuousClock.Instant
  ) -> Self {
    guard integrity == .valid, !isTerminal, value(for: stage) == nil else { return self }
    var candidate = self
    candidate.assign(instant, to: stage)
    guard candidate.hasValidCausalEdges else {
      var invalid = self
      invalid.integrity = .nonMonotonicClock
      return invalid
    }
    return candidate
  }

  func recording(outcome: Outcome) -> Self {
    guard integrity == .valid, !isTerminal, self.outcome == nil else { return self }
    var result = self
    result.outcome = outcome
    return result
  }

  func recording(failure: Failure) -> Self {
    guard integrity == .valid, !isTerminal, self.failure == nil else { return self }
    var result = self
    result.failure = failure
    return result
  }

  func recording(loadDisposition: LoadDisposition) -> Self {
    guard integrity == .valid, !isTerminal, self.loadDisposition == nil else { return self }
    var result = self
    result.loadDisposition = loadDisposition
    return result
  }

  func resolving(outcome: Outcome, failure: Failure?) -> Self {
    guard integrity == .valid, !isTerminal else { return self }
    var result = self
    result.outcome = outcome
    result.failure = failure
    return result
  }

  func overlaying(_ measurements: Self) -> Self {
    guard integrity == .valid, !isTerminal else { return self }
    var result = self
    for stage in Stage.allCases where value(for: stage) == nil {
      guard let incoming = measurements.value(for: stage) else { continue }
      var candidate = result
      candidate.assign(incoming, to: stage)
      guard candidate.hasValidCausalEdges else {
        result.integrity = .nonMonotonicClock
        continue
      }
      result = candidate
    }
    if measurements.integrity == .nonMonotonicClock {
      result.integrity = .nonMonotonicClock
    }
    if result.outcome == nil { result.outcome = measurements.outcome }
    if result.failure == nil { result.failure = measurements.failure }
    if result.loadDisposition == nil { result.loadDisposition = measurements.loadDisposition }
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
    case .coordinatorEventReceived: coordinatorEventReceivedAt
    case .phasePublished: phasePublishedAt
    case .processorStarted: processorStartedAt
    case .sourceStartRequested: sourceStartRequestedAt
    case .audioStartRequested: audioStartRequestedAt
    case .firstInputBuffer: firstInputBufferAt
    case .modelLoadRequested: modelLoadRequestedAt
    case .modelReady: modelReadyAt
    case .audioReadyObserved: audioReadyObservedAt
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

  private var hasValidCausalEdges: Bool {
    let edges: [(Stage, Stage)] = [
      (.physicalPress, .physicalRelease),
      (.physicalPress, .coordinatorEventReceived),
      (.physicalPress, .processorStarted),
      (.coordinatorEventReceived, .phasePublished),
      (.coordinatorEventReceived, .processorStarted),
      (.processorStarted, .sourceStartRequested),
      (.sourceStartRequested, .audioStartRequested),
      (.sourceStartRequested, .audioReadyObserved),
      (.audioStartRequested, .firstInputBuffer),
      (.sourceStartRequested, .modelLoadRequested),
      (.modelLoadRequested, .modelReady),
      (.firstInputBuffer, .asrFinal),
      (.modelReady, .asrFinal),
      (.audioReadyObserved, .asrFinal),
      (.sourceStartRequested, .firstMeaningfulPartial),
      (.physicalRelease, .stopRequested),
      (.processorStarted, .stopRequested),
      (.stopRequested, .asrFinal),
      (.asrFinal, .dictionaryCompleted),
      (.dictionaryCompleted, .cleanupDecisionCompleted),
      (.cleanupDecisionCompleted, .routingRequested),
      (.routingRequested, .routingDecision),
      (.cleanupDecisionCompleted, .insertionCommitted),
      (.routingDecision, .insertionCommitted),
      (.insertionCommitted, .persistenceCompleted),
      (.persistenceCompleted, .ambiguityPresented),
      (.ambiguityPresented, .ambiguityMoved),
      (.cancellationRequested, .compensationCompleted),
      (.cancellationRequested, .cancellationDrained),
    ]
    return edges.allSatisfy { before, after in
      guard let before = value(for: before), let after = value(for: after) else {
        return true
      }
      return before <= after
    }
  }

  private mutating func assign(
    _ instant: ContinuousClock.Instant,
    to stage: Stage
  ) {
    switch stage {
    case .physicalPress: physicalPressAt = instant
    case .coordinatorEventReceived: coordinatorEventReceivedAt = instant
    case .phasePublished: phasePublishedAt = instant
    case .processorStarted: processorStartedAt = instant
    case .sourceStartRequested: sourceStartRequestedAt = instant
    case .audioStartRequested: audioStartRequestedAt = instant
    case .firstInputBuffer: firstInputBufferAt = instant
    case .modelLoadRequested: modelLoadRequestedAt = instant
    case .modelReady: modelReadyAt = instant
    case .audioReadyObserved: audioReadyObservedAt = instant
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

  struct Diagnostics: Equatable, Codable, Sendable {
    let schemaVersion: Int
    let integrity: Integrity
    let outcome: Outcome?
    let failure: Failure?
    let loadDisposition: LoadDisposition?
    let stages: [String: Double?]

    private enum CodingKeys: String, CodingKey {
      case schemaVersion, integrity, outcome, failure, loadDisposition, stages
    }

    init(measurements: DictationRuntimeMeasurements) {
      schemaVersion = 1
      integrity = measurements.integrity
      outcome = measurements.outcome
      failure = measurements.failure
      loadDisposition = measurements.loadDisposition
      let origin = measurements.integrity == .valid
        ? Stage.allCases.compactMap { measurements.value(for: $0) }.min()
        : nil
      stages = Dictionary(uniqueKeysWithValues: Stage.allCases.map { stage in
        let elapsed = origin.flatMap { measurements.milliseconds(from: $0, to: measurements.value(for: stage)) }
        return (stage.rawValue, elapsed)
      })
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      let decodedIntegrity = try container.decode(Integrity.self, forKey: .integrity)
      integrity = decodedIntegrity
      outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome)
      failure = try container.decodeIfPresent(Failure.self, forKey: .failure)
      loadDisposition = try container.decodeIfPresent(LoadDisposition.self, forKey: .loadDisposition)
      let decodedStages = try container.decode([String: Double?].self, forKey: .stages)
      stages = Dictionary(uniqueKeysWithValues: Stage.allCases.map { stage in
        (stage.rawValue, decodedIntegrity == .valid ? decodedStages[stage.rawValue] ?? nil : nil)
      })
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(schemaVersion, forKey: .schemaVersion)
      try container.encode(integrity, forKey: .integrity)
      if let outcome { try container.encode(outcome, forKey: .outcome) }
      else { try container.encodeNil(forKey: .outcome) }
      if let failure { try container.encode(failure, forKey: .failure) }
      else { try container.encodeNil(forKey: .failure) }
      if let loadDisposition { try container.encode(loadDisposition, forKey: .loadDisposition) }
      else { try container.encodeNil(forKey: .loadDisposition) }
      try container.encode(stages, forKey: .stages)
    }
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
