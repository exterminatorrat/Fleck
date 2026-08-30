import Foundation
import FleckCore

enum StreamingDictationProcessorError: Error, Equatable {
  case noSpeech
  case captureContextMismatch
  case recognitionContextMismatch
  case recognitionContextRejected
}

@MainActor
private final class ProcessorMeasurementRecorder {
  enum Stage: Equatable {
    case processorStarted
    case sourceStartRequested
    case firstMeaningfulPartial
    case stopRequested
    case asrFinal
    case dictionaryCompleted
    case cleanupDecisionCompleted
    case cancellationRequested
    case cancellationDrained
  }

  private var integrity: DictationRuntimeMeasurements.Integrity = .valid
  private var lastAcceptedAt: ContinuousClock.Instant?
  private var processorStartedAt: ContinuousClock.Instant?
  private var sourceStartRequestedAt: ContinuousClock.Instant?
  private var firstMeaningfulPartialAt: ContinuousClock.Instant?
  private var stopRequestedAt: ContinuousClock.Instant?
  private var asrFinalAt: ContinuousClock.Instant?
  private var dictionaryCompletedAt: ContinuousClock.Instant?
  private var cleanupDecisionCompletedAt: ContinuousClock.Instant?
  private var cancellationRequestedAt: ContinuousClock.Instant?
  private var cancellationDrainedAt: ContinuousClock.Instant?

  func record(_ stage: Stage, at instant: ContinuousClock.Instant) {
    guard integrity == .valid, value(for: stage) == nil else { return }
    if cancellationRequestedAt != nil,
      stage != .cancellationRequested,
      stage != .cancellationDrained
    {
      return
    }
    if let lastAcceptedAt, instant < lastAcceptedAt {
      integrity = .nonMonotonicClock
      return
    }
    if stage == .cancellationDrained, cancellationRequestedAt == nil { return }
    assign(instant, to: stage)
    lastAcceptedAt = instant
  }

  var snapshot: DictationRuntimeMeasurements {
    DictationRuntimeMeasurements(
      integrity: integrity,
      processorStartedAt: processorStartedAt,
      sourceStartRequestedAt: sourceStartRequestedAt,
      firstMeaningfulPartialAt: firstMeaningfulPartialAt,
      stopRequestedAt: stopRequestedAt,
      asrFinalAt: asrFinalAt,
      dictionaryCompletedAt: dictionaryCompletedAt,
      cleanupDecisionCompletedAt: cleanupDecisionCompletedAt,
      cancellationRequestedAt: cancellationRequestedAt,
      cancellationDrainedAt: cancellationDrainedAt
    )
  }

  private func value(for stage: Stage) -> ContinuousClock.Instant? {
    switch stage {
    case .processorStarted: processorStartedAt
    case .sourceStartRequested: sourceStartRequestedAt
    case .firstMeaningfulPartial: firstMeaningfulPartialAt
    case .stopRequested: stopRequestedAt
    case .asrFinal: asrFinalAt
    case .dictionaryCompleted: dictionaryCompletedAt
    case .cleanupDecisionCompleted: cleanupDecisionCompletedAt
    case .cancellationRequested: cancellationRequestedAt
    case .cancellationDrained: cancellationDrainedAt
    }
  }

  private func assign(_ instant: ContinuousClock.Instant, to stage: Stage) {
    switch stage {
    case .processorStarted: processorStartedAt = instant
    case .sourceStartRequested: sourceStartRequestedAt = instant
    case .firstMeaningfulPartial: firstMeaningfulPartialAt = instant
    case .stopRequested: stopRequestedAt = instant
    case .asrFinal: asrFinalAt = instant
    case .dictionaryCompleted: dictionaryCompletedAt = instant
    case .cleanupDecisionCompleted: cleanupDecisionCompletedAt = instant
    case .cancellationRequested: cancellationRequestedAt = instant
    case .cancellationDrained: cancellationDrainedAt = instant
    }
  }
}

@MainActor
final class StreamingDictationProcessor: DictationProcessing {
  typealias SourceFactory =
    @MainActor (DictationProcessingConfiguration) async throws -> any StreamingSpeechSource
  typealias RecognitionContextAcknowledger = @MainActor (
    DictationProcessingConfiguration
  ) async throws -> DictationRecognitionContextAcknowledgement

  private let makeSource: SourceFactory
  private let recognitionContextAcknowledgement: RecognitionContextAcknowledger?
  private let dictionaryResolver: any TranscriptDictionaryResolving
  private let cleaner: IncrementalTranscriptCleaner
  private let runtime: LocalDictationRuntime?
  private let clock: DictationClock
  private let budget: DictationProcessingBudget
  private let finalizationStartGate: (@MainActor @Sendable () async -> Void)?
  private let onCancellationInvalidated: (@MainActor @Sendable () -> Void)?
  private let onCancellationDrained: (@MainActor @Sendable () -> Void)?

  init(
    makeSource: @escaping SourceFactory,
    recognitionContextAcknowledgement: RecognitionContextAcknowledger? = nil,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?,
    clock: DictationClock = .live,
    budget: DictationProcessingBudget = .production,
    finalizationStartGate: (@MainActor @Sendable () async -> Void)? = nil,
    onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
    onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.makeSource = makeSource
    self.recognitionContextAcknowledgement = recognitionContextAcknowledgement
    self.dictionaryResolver = dictionaryResolver
    self.cleaner = cleaner
    self.runtime = runtime
    self.clock = clock
    self.budget = budget
    self.finalizationStartGate = finalizationStartGate
    self.onCancellationInvalidated = onCancellationInvalidated
    self.onCancellationDrained = onCancellationDrained
  }

  func prepare(for intent: DictationPreparationIntent) async {
    await runtime?.prepare(for: intent)
  }

  func handle(_ signal: DictationRuntimeSignal) async {
    await runtime?.handle(signal)
  }

  func begin(
    configuration: DictationProcessingConfiguration,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws -> any DictationProcessingSession {
    let measurements = ProcessorMeasurementRecorder()
    measurements.record(.processorStarted, at: clock.now())
    try validate(configuration)
    let source = try await makeSource(configuration)
    let acknowledgement: DictationRecognitionContextAcknowledgement?
    if let context = configuration.captureContext {
      do {
        acknowledgement = try await recognitionContextAcknowledgement?(configuration)
          ?? .unsupported(context)
        guard acknowledgement?.context == context else {
          throw StreamingDictationProcessorError.recognitionContextMismatch
        }
        if case .rejected? = acknowledgement {
          throw StreamingDictationProcessorError.recognitionContextRejected
        }
      } catch {
        await source.releaseResources()
        throw error
      }
    } else {
      acknowledgement = nil
    }
    let callbackBuffer = StreamingDictationCallbackBuffer()
    do {
      measurements.record(.sourceStartRequested, at: clock.now())
      try await source.start(
        provisional: { callbackBuffer.provisional($0, receivedAt: self.clock.now()) },
        level: level
      )
      return StreamingDictationSession(
        configuration: configuration,
        source: source,
        callbackBuffer: callbackBuffer,
        measurements: measurements,
        captureContext: configuration.captureContext,
        recognitionContextAcknowledgement: acknowledgement,
        dictionaryResolver: dictionaryResolver,
        cleaner: cleaner,
        runtime: runtime,
        clock: clock,
        budget: budget,
        finalizationStartGate: finalizationStartGate,
        onCancellationInvalidated: onCancellationInvalidated,
        onCancellationDrained: onCancellationDrained
      )
    } catch {
      await source.releaseResources()
      throw error
    }
  }

  private func validate(_ configuration: DictationProcessingConfiguration) throws {
    guard let context = configuration.captureContext else { return }
    guard configuration.captureID == context.captureID,
      configuration.captureGeneration == context.generation,
      configuration.engine == context.speechEngine,
      configuration.recognitionContext.locale.identifier == context.localeIdentifier,
      configuration.recognitionContext.contextualStrings
        == context.compiledDictionary.recognitionStrings
    else {
      throw StreamingDictationProcessorError.captureContextMismatch
    }
  }
}

@MainActor
fileprivate final class StreamingDictationCallbackBuffer {
  private var provisionalTexts: [(text: String, receivedAt: ContinuousClock.Instant)] = []
  private weak var session: StreamingDictationSession?

  func provisional(_ text: String, receivedAt: ContinuousClock.Instant) {
    if let session {
      session.receiveProvisional(text, receivedAt: receivedAt)
    } else {
      provisionalTexts.append((text, receivedAt))
    }
  }

  func attach(to session: StreamingDictationSession) {
    self.session = session
    let buffered = provisionalTexts
    provisionalTexts.removeAll(keepingCapacity: false)
    buffered.forEach { session.receiveProvisional($0.text, receivedAt: $0.receivedAt) }
  }
}

@MainActor
final class StreamingDictationSession: DictationProcessingSession {
  private let source: any StreamingSpeechSource
  private let measurements: ProcessorMeasurementRecorder
  private let captureContext: LocalWritingCaptureContext?
  private let recognitionContextAcknowledgement: DictationRecognitionContextAcknowledgement?
  private let dictionaryResolver: any TranscriptDictionaryResolving
  private let cleaner: IncrementalTranscriptCleaner
  private let runtime: LocalDictationRuntime?
  private let clock: DictationClock
  private let budget: DictationProcessingBudget
  private let finalizationStartGate: (@MainActor @Sendable () async -> Void)?
  private let onCancellationInvalidated: (@MainActor @Sendable () -> Void)?
  private let onCancellationDrained: (@MainActor @Sendable () -> Void)?
  private let updateStream: AsyncThrowingStream<DictationTextUpdate, Error>
  private let continuation: AsyncThrowingStream<DictationTextUpdate, Error>.Continuation
  private var transcriptState = StreamingTranscriptState()
  private var finalizationTask: Task<DictationProcessingResult, Error>?
  private var cancellationTask: Task<Void, Never>?
  private var isCancelled = false
  private var isTerminal = false
  private enum SourceTerminalization: Equatable {
    case open
    case finished
    case cancelled
  }
  private var sourceTerminalization: SourceTerminalization = .open
  private var generation: UInt64 = 0

  fileprivate init(
    configuration: DictationProcessingConfiguration,
    source: any StreamingSpeechSource,
    callbackBuffer: StreamingDictationCallbackBuffer,
    measurements: ProcessorMeasurementRecorder,
    captureContext: LocalWritingCaptureContext?,
    recognitionContextAcknowledgement: DictationRecognitionContextAcknowledgement?,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?,
    clock: DictationClock,
    budget: DictationProcessingBudget,
    finalizationStartGate: (@MainActor @Sendable () async -> Void)? = nil,
    onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
    onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
  ) {
    _ = configuration
    self.source = source
    self.measurements = measurements
    self.captureContext = captureContext
    self.recognitionContextAcknowledgement = recognitionContextAcknowledgement
    self.dictionaryResolver = dictionaryResolver
    self.cleaner = cleaner
    self.runtime = runtime
    self.clock = clock
    self.budget = budget
    self.finalizationStartGate = finalizationStartGate
    self.onCancellationInvalidated = onCancellationInvalidated
    self.onCancellationDrained = onCancellationDrained
    var capturedContinuation: AsyncThrowingStream<DictationTextUpdate, Error>.Continuation!
    updateStream = AsyncThrowingStream { capturedContinuation = $0 }
    continuation = capturedContinuation
    callbackBuffer.attach(to: self)
  }

  var updates: AsyncThrowingStream<DictationTextUpdate, Error> {
    updateStream
  }

  var runtimeMeasurements: DictationRuntimeMeasurements {
    measurements.snapshot
  }

  func finish() async throws -> DictationProcessingResult {
    try await finishUsingDeadlineOrigin(nil)
  }

  func finish(
    deadlineOrigin: ContinuousClock.Instant
  ) async throws -> DictationProcessingResult {
    try await finishUsingDeadlineOrigin(deadlineOrigin)
  }

  private func finishUsingDeadlineOrigin(
    _ suppliedDeadlineOrigin: ContinuousClock.Instant?
  ) async throws -> DictationProcessingResult {
    if let finalizationTask {
      return try await finalizationTask.value
    }
    guard !isCancelled, !isTerminal, cancellationTask == nil else {
      throw CancellationError()
    }

    // Capture the stop boundary before any task suspension or source finalization.
    let stopInstant = clock.now()
    measurements.record(.stopRequested, at: stopInstant)
    let deadlineOrigin = suppliedDeadlineOrigin ?? stopInstant
    let insertionDeadline = deadlineOrigin.advanced(by: budget.insertion)
    let deadline = DictationDeadline(
      stopInstant: deadlineOrigin,
      insertionDeadline: insertionDeadline,
      cleanupBudget: budget.cleanup
    )
    let task = Task { @MainActor [weak self] in
      guard let self else { throw CancellationError() }
      if let finalizationStartGate = self.finalizationStartGate {
        await finalizationStartGate()
      }
      return try await self.runFinalization(deadline: deadline)
    }
    finalizationTask = task
    return try await task.value
  }

  func cancel() async {
    if let cancellationTask {
      await cancellationTask.value
      return
    }
    guard !isTerminal else { return }

    // This actor turn is the cancellation winner. No suspension occurs between
    // invalidation and storing the shared task.
    measurements.record(.cancellationRequested, at: clock.now())
    isCancelled = true
    generation &+= 1
    continuation.finish()
    onCancellationInvalidated?()

    let task: Task<Void, Never> = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.completeCancellation()
    }
    cancellationTask = task
    await task.value
  }

  fileprivate func receiveProvisional(
    _ text: String,
    receivedAt: ContinuousClock.Instant
  ) {
    guard !isCancelled, !isTerminal else { return }
    generation &+= 1
    guard let update = try? transcriptState.accept(
      generation: generation,
      fullText: text
    ) else { return }
    guard !isCancelled, !isTerminal else { return }
    if update.displayText.contains(where: { !$0.isWhitespace }) {
      measurements.record(.firstMeaningfulPartial, at: receivedAt)
    }
    continuation.yield(update)
  }

  private func completeCancellation() async {
    finalizationTask?.cancel()
    if sourceTerminalization == .open {
      sourceTerminalization = .cancelled
      // Apple Speech may suspend finish() on its session continuation. The
      // source's cancel() owns the physical release and unblocks that finish.
      await source.cancel()
    }
    if let finalizationTask {
      _ = try? await finalizationTask.value
    }
    measurements.record(.cancellationDrained, at: clock.now())
    onCancellationDrained?()
    markTerminal()
  }

  private func runFinalization(
    deadline: DictationDeadline
  ) async throws -> DictationProcessingResult {
    do {
      let result = try await finalizeBody(deadline: deadline)
      try Task.checkCancellation()
      guard !isCancelled, !isTerminal else {
        throw CancellationError()
      }
      markTerminal()
      try Task.checkCancellation()
      return result
    } catch {
      markTerminal()
      throw error
    }
  }

  private func finalizeBody(
    deadline: DictationDeadline
  ) async throws -> DictationProcessingResult {
    try Task.checkCancellation()

    let rawText: String?
    do {
      let returnedText = try await source.finish()
      try Task.checkCancellation()
      measurements.record(.asrFinal, at: clock.now())
      rawText = returnedText
      if sourceTerminalization == .open {
        sourceTerminalization = .finished
      }
    } catch {
      if sourceTerminalization == .open {
        sourceTerminalization = .finished
      }
      throw error
    }

    try Task.checkCancellation()
    guard let rawText, !rawText.isEmpty else {
      throw StreamingDictationProcessorError.noSpeech
    }

    let resolution: PersonalDictionaryResolution
    do {
      if let captureContext {
        resolution = try await dictionaryResolver.resolve(
          rawText,
          context: captureContext
        )
        guard resolution.dictionaryRevision == captureContext.dictionaryRevision,
          resolution.dictionaryContentDigest == captureContext.dictionaryContentDigest
        else {
          throw StreamingDictationProcessorError.captureContextMismatch
        }
      } else {
        resolution = try await dictionaryResolver.resolve(rawText)
      }
    } catch {
      try Task.checkCancellation()
      measurements.record(.dictionaryCompleted, at: clock.now())
      return rawRecoveryResult(rawText)
    }
    try Task.checkCancellation()
    measurements.record(.dictionaryCompleted, at: clock.now())

    let request = IncrementalCleanupRequest(
      baseline: resolution.baseline,
      protectedForms: resolution.protectedForms,
      replacements: resolution.replacements,
      deadline: deadline.cleanupDeadline
    )
    let decision = try await cleaner.clean(request)
    try Task.checkCancellation()
    measurements.record(.cleanupDecisionCompleted, at: clock.now())

    switch decision {
    case .accepted(let text):
      return DictationProcessingResult(
        rawTranscript: rawText,
        dictionaryBaseline: resolution.baseline,
        cleanedTranscript: text,
        insertedText: text,
        cleanupOutcome: .cleaned,
        measurements: runtimeMeasurements,
        captureContext: captureContext,
        recognitionContextAcknowledgement: recognitionContextAcknowledgement,
        protectedDictionaryForms: resolution.protectedForms,
        appliedDictionaryEntryIDs: resolution.appliedEntryIDs
      )
    case .baseline:
      return DictationProcessingResult(
        rawTranscript: rawText,
        dictionaryBaseline: resolution.baseline,
        cleanedTranscript: nil,
        insertedText: resolution.baseline,
        cleanupOutcome: .usedRaw,
        measurements: runtimeMeasurements,
        captureContext: captureContext,
        recognitionContextAcknowledgement: recognitionContextAcknowledgement,
        protectedDictionaryForms: resolution.protectedForms,
        appliedDictionaryEntryIDs: resolution.appliedEntryIDs
      )
    }
  }

  private func rawRecoveryResult(_ rawText: String) -> DictationProcessingResult {
    DictationProcessingResult(
      rawTranscript: rawText,
      dictionaryBaseline: nil,
      cleanedTranscript: nil,
      insertedText: rawText,
      cleanupOutcome: .usedRaw,
      measurements: runtimeMeasurements,
      captureContext: captureContext,
      recognitionContextAcknowledgement: recognitionContextAcknowledgement
    )
  }

  private func markTerminal() {
    guard !isTerminal else { return }
    isTerminal = true
    generation &+= 1
    continuation.finish()
  }
}
