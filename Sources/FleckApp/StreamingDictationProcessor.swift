import Foundation
import FleckCore

enum StreamingDictationProcessorError: Error, Equatable {
  case noSpeech
}

@MainActor
final class StreamingDictationProcessor: DictationProcessing {
  typealias SourceFactory =
    @MainActor () async throws -> any StreamingSpeechSource

  private let makeSource: SourceFactory
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
    let source = try await makeSource()
    let callbackBuffer = StreamingDictationCallbackBuffer()
    do {
      try await source.start(
        provisional: { callbackBuffer.provisional($0) },
        level: level
      )
      return StreamingDictationSession(
        configuration: configuration,
        source: source,
        callbackBuffer: callbackBuffer,
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
}

@MainActor
fileprivate final class StreamingDictationCallbackBuffer {
  private var provisionalTexts: [String] = []
  private weak var session: StreamingDictationSession?

  func provisional(_ text: String) {
    if let session {
      session.receiveProvisional(text)
    } else {
      provisionalTexts.append(text)
    }
  }

  func attach(to session: StreamingDictationSession) {
    self.session = session
    let buffered = provisionalTexts
    provisionalTexts.removeAll(keepingCapacity: false)
    buffered.forEach { session.receiveProvisional($0) }
  }
}

@MainActor
final class StreamingDictationSession: DictationProcessingSession {
  private let source: any StreamingSpeechSource
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

  func finish() async throws -> DictationProcessingResult {
    if let finalizationTask {
      return try await finalizationTask.value
    }
    guard !isCancelled, !isTerminal, cancellationTask == nil else {
      throw CancellationError()
    }

    // Capture the stop boundary before any task suspension or source finalization.
    let stopInstant = clock.now()
    let insertionDeadline = stopInstant.advanced(by: budget.insertion)
    let deadline = DictationDeadline(
      stopInstant: stopInstant,
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

  fileprivate func receiveProvisional(_ text: String) {
    guard !isCancelled, !isTerminal else { return }
    generation &+= 1
    guard let update = try? transcriptState.accept(
      generation: generation,
      fullText: text
    ) else { return }
    guard !isCancelled, !isTerminal else { return }
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
      resolution = try await dictionaryResolver.resolve(rawText)
    } catch {
      try Task.checkCancellation()
      return rawRecoveryResult(rawText)
    }
    try Task.checkCancellation()

    let request = IncrementalCleanupRequest(
      baseline: resolution.baseline,
      protectedForms: resolution.protectedForms,
      replacements: resolution.replacements,
      deadline: deadline.cleanupDeadline
    )
    let decision = try await cleaner.clean(request)
    try Task.checkCancellation()

    switch decision {
    case .accepted(let text):
      return DictationProcessingResult(
        rawTranscript: rawText,
        dictionaryBaseline: resolution.baseline,
        cleanedTranscript: text,
        insertedText: text,
        cleanupOutcome: .cleaned,
        measurements: .empty
      )
    case .baseline:
      return DictationProcessingResult(
        rawTranscript: rawText,
        dictionaryBaseline: resolution.baseline,
        cleanedTranscript: nil,
        insertedText: resolution.baseline,
        cleanupOutcome: .usedRaw,
        measurements: .empty
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
      measurements: .empty
    )
  }

  private func markTerminal() {
    guard !isTerminal else { return }
    isTerminal = true
    generation &+= 1
    continuation.finish()
  }
}
