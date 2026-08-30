import Foundation
import Testing
import FleckCore

@testable import FleckApp

private func testStopOrigin(
  _ instant: ContinuousClock.Instant = TestDictationClock.fixedInstant
) -> DictationStopOrigin {
  .toolbarAction(instant)
}

private func processorDictionaryContext(
  captureID: UUID = UUID(),
  generation: UInt64 = 1,
  revision: UInt64 = 1,
  preferredForm: String = "FleckApp"
) throws -> LocalWritingCaptureContext {
  let entry = PersonalDictionaryEntry(
    preferredForm: preferredForm,
    aliases: ["fleck app"]
  )
  let snapshot = PersonalDictionarySnapshotV2(revision: revision, entries: [entry])
  return try LocalWritingCaptureContext(
    captureID: captureID,
    generation: generation,
    localeIdentifier: "en-US",
    speechEngine: .standard,
    snapshot: snapshot,
    compiledDictionary: CompiledPersonalDictionary.compile(snapshot)
  )
}

@MainActor
private final class ProcessingBeginErrorBox {
  var error: Error?
}

private func processorDictionaryConfiguration(
  _ context: LocalWritingCaptureContext
) -> DictationProcessingConfiguration {
  DictationProcessingConfiguration(mode: .focused, captureContext: context)
}

private func processorDictionaryContext(
  from context: LocalWritingCaptureContext,
  captureID: UUID? = nil,
  generation: UInt64? = nil,
  speechEngine: DictationSpeechEngine? = nil
) throws -> LocalWritingCaptureContext {
  try LocalWritingCaptureContext(
    captureID: captureID ?? context.captureID,
    generation: generation ?? context.generation,
    localeIdentifier: context.localeIdentifier,
    speechEngine: speechEngine ?? context.speechEngine,
    snapshot: context.snapshot,
    compiledDictionary: context.compiledDictionary
  )
}

@MainActor
private func makeProcessor(
  source: any StreamingSpeechSource,
  onConfiguration: ((DictationProcessingConfiguration) -> Void)? = nil,
  finalizationStartGate: (@MainActor @Sendable () async -> Void)? = nil,
  onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
  onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
) -> StreamingDictationProcessor {
  StreamingDictationProcessor(
    makeSource: { configuration in
      onConfiguration?(configuration)
      return source
    },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "First",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "First"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production,
    finalizationStartGate: finalizationStartGate,
    onCancellationInvalidated: onCancellationInvalidated,
    onCancellationDrained: onCancellationDrained
  )
}

@MainActor
private func firstUpdate(
  from stream: AsyncThrowingStream<DictationTextUpdate, Error>
) async throws -> DictationTextUpdate? {
  var iterator = stream.makeAsyncIterator()
  return try await iterator.next()
}

@MainActor
private func collectUpdates(
  from stream: AsyncThrowingStream<DictationTextUpdate, Error>
) async throws -> [DictationTextUpdate] {
  var collected: [DictationTextUpdate] = []
  for try await update in stream {
    collected.append(update)
  }
  return collected
}

enum StreamingSpeechSourceProbeError: Error, Equatable {
  case failed
}

@MainActor
final class StreamingSpeechSourceProbe: StreamingSpeechSource {
  private let startError: StreamingSpeechSourceProbeError?
  private let finishError: StreamingSpeechSourceProbeError?
  private let finalText: String?
  private let finishBlocksUntilCancel: Bool
  private let finishReturnsNilAfterCancel: Bool
  private let finishBlocksUntilRelease: Bool
  private let synchronousProvisional: String?
  private let synchronousLevel: Float?
  private let onCancel: (@MainActor @Sendable () async -> Void)?
  private let onPhysicalRelease: (@MainActor @Sendable () async -> Void)?
  private var provisional: (@MainActor @Sendable (String) -> Void)?
  private var level: (@MainActor @Sendable (Float) -> Void)?
  private var finishReleased = false
  private var cancellationRequested = false
  private var sourceIsTerminal = false

  init(
    startError: StreamingSpeechSourceProbeError? = nil,
    finishError: StreamingSpeechSourceProbeError? = nil,
    finalText: String? = "First",
    finishBlocksUntilCancel: Bool = false,
    finishReturnsNilAfterCancel: Bool = false,
    finishBlocksUntilRelease: Bool = false,
    synchronousProvisional: String? = nil,
    synchronousLevel: Float? = nil,
    onCancel: (@MainActor @Sendable () async -> Void)? = nil,
    onPhysicalRelease: (@MainActor @Sendable () async -> Void)? = nil
  ) {
    self.startError = startError
    self.finishError = finishError
    self.finalText = finalText
    self.finishBlocksUntilCancel = finishBlocksUntilCancel
    self.finishReturnsNilAfterCancel = finishReturnsNilAfterCancel
    self.finishBlocksUntilRelease = finishBlocksUntilRelease
    self.synchronousProvisional = synchronousProvisional
    self.synchronousLevel = synchronousLevel
    self.onCancel = onCancel
    self.onPhysicalRelease = onPhysicalRelease
  }

  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var finishStarted = false
  private(set) var finishCompleted = false
  private(set) var finishUnblockedByCancel = false
  private(set) var cancelCount = 0
  private(set) var releaseHookCount = 0
  private(set) var physicalReleaseCount = 0
  private(set) var sourceTerminalizationCount = 0
  private(set) var callbacksWereInstalled = false
  private(set) var provisionalCallbackCount = 0
  private(set) var stopOrigins: [DictationStopOrigin] = []

  func emitProvisional(_ text: String) {
    provisional?(text)
  }

  func emitLevel(_ value: Float) {
    level?(value)
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    startCount += 1
    self.provisional = { text in
      self.provisionalCallbackCount += 1
      provisional(text)
    }
    self.level = level
    callbacksWereInstalled = true
    if let synchronousProvisional {
      self.provisional?(synchronousProvisional)
    }
    if let synchronousLevel {
      level(synchronousLevel)
    }
    if let startError { throw startError }
  }

  func finish() async throws -> String? {
    finishCount += 1
    finishStarted = true

    if finishBlocksUntilCancel {
      while !cancellationRequested {
        await Task.yield()
      }
      finishUnblockedByCancel = true
      guard finishReturnsNilAfterCancel else {
        throw CancellationError()
      }
      finishCompleted = true
      return nil
    }

    if finishBlocksUntilRelease {
      while !finishReleased {
        await Task.yield()
      }
    }

    if let finishError {
      finishCompleted = true
      await terminalizeFromFinish()
      throw finishError
    }

    finishCompleted = true
    await terminalizeFromFinish()
    return finalText
  }

  func finish(stopOrigin: DictationStopOrigin) async throws -> String? {
    stopOrigins.append(stopOrigin)
    return try await finish()
  }

  func cancel() async {
    cancelCount += 1
    cancellationRequested = true
    await onCancel?()
    await terminalizeFromCancellation()
  }

  func releaseFinish() {
    finishReleased = true
  }

  func releaseResources() async {
    releaseHookCount += 1
  }

  func waitUntilFinishStarted() async {
    while !finishStarted {
      await Task.yield()
    }
  }

  private func terminalizeFromFinish() async {
    guard !sourceIsTerminal else { return }
    sourceIsTerminal = true
    sourceTerminalizationCount += 1
    physicalReleaseCount += 1
    await onPhysicalRelease?()
  }

  private func terminalizeFromCancellation() async {
    guard !sourceIsTerminal else { return }
    sourceIsTerminal = true
    sourceTerminalizationCount += 1
    physicalReleaseCount += 1
    await onPhysicalRelease?()
  }
}

@MainActor
private final class FinalizationStartGate {
  private(set) var entered = false
  private var released = false

  func wait() async {
    entered = true
    while !released { await Task.yield() }
  }

  func waitUntilEntered() async {
    while !entered { await Task.yield() }
  }

  func release() {
    released = true
  }
}

@Test @MainActor
func processorMeasurementsRecordSuccessfulStageOrdering() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = (0...6).map { start.advanced(by: .milliseconds($0)) }
  let clock = TestDictationClock(values: samples)
  let source = StreamingSpeechSourceProbe(synchronousProvisional: "First")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "First"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: clock,
    budget: .production
  )

  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)
  let result = try await session.finish(stopOrigin: testStopOrigin())
  let measurements = session.runtimeMeasurements

  #expect(measurements.processorStartedAt == samples[0])
  #expect(measurements.sourceStartRequestedAt == samples[1])
  #expect(measurements.firstMeaningfulPartialAt == samples[2])
  #expect(measurements.stopRequestedAt == samples[3])
  #expect(measurements.asrFinalAt == samples[4])
  #expect(measurements.dictionaryCompletedAt == samples[5])
  #expect(measurements.cleanupDecisionCompletedAt == samples[6])
  #expect(measurements.integrity == .valid)
  #expect(result.measurements == measurements)
  #expect(result.insertedText == "First.")
}

@Test @MainActor
func captureFirstSourceReceivesExactOriginAndDeadlinesUseItsInstant() async throws {
  let clock = TestDictationClock(values: Array(repeating: TestDictationClock.fixedInstant, count: 8))
  let source = StreamingSpeechSourceProbe(finalText: "First")
  let generator = CleanupGeneratorProbe(result: "First")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: generator,
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: clock,
    budget: .production
  )
  let session = try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  )
  let instant = TestDictationClock.fixedInstant.advanced(by: .seconds(3))
  let origin = DictationStopOrigin.physicalRelease(instant)

  _ = try await session.finish(stopOrigin: origin)

  #expect(source.stopOrigins == [origin])
  #expect(generator.requests.first?.deadline == instant.advanced(by: .milliseconds(3_500)))
}

@Test @MainActor
func processorMeasurementsDefaultFinishSamplesOnceAndUsesStopRequestAsDeadlineOrigin() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = (0...5).map { start.advanced(by: .milliseconds($0)) }
  let sequence = InstantSequence(samples)
  let clock = DictationClock(now: { sequence.next() })
  let source = StreamingSpeechSourceProbe()
  let generator = CleanupGeneratorProbe(result: "First")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: generator,
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: clock,
    budget: .production
  )
  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)

  let first = try await session.finish(stopOrigin: testStopOrigin(samples[2]))
  let second = try await session.finish(stopOrigin: testStopOrigin())

  #expect(first == second)
  #expect(session.runtimeMeasurements.stopRequestedAt == samples[2])
  #expect(generator.requests.first?.deadline == samples[2].advanced(by: .milliseconds(3_500)))
  #expect(sequence.callCount == 6)
}

@Test @MainActor
func processorMeasurementsExplicitDeadlineOriginControlsDeadlineSeparatelyFromStopRequest() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = (0...5).map { start.advanced(by: .milliseconds($0)) }
  let sequence = InstantSequence(samples)
  let clock = DictationClock(now: { sequence.next() })
  let deadlineOrigin = start.advanced(by: .seconds(10))
  let generator = CleanupGeneratorProbe(result: "First")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in StreamingSpeechSourceProbe() },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: generator,
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: clock,
    budget: .production
  )
  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)

  let explicit = try await session.finish(stopOrigin: .physicalRelease(deadlineOrigin))
  let repeated = try await session.finish(stopOrigin: testStopOrigin())

  #expect(explicit == repeated)
  #expect(session.runtimeMeasurements.stopRequestedAt == samples[2])
  #expect(generator.requests.first?.deadline == deadlineOrigin.advanced(by: .milliseconds(3_500)))
  #expect(sequence.callCount == 6)
}

@Test @MainActor
func processorMeasurementsRecordCleanupDecisionForRejectedCandidate() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = (0...5).map { start.advanced(by: .milliseconds($0)) }
  let source = StreamingSpeechSourceProbe(finalText: "Do not cancel 2 meetings")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "Do not cancel 2 meetings",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "Cancel the meetings"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: TestDictationClock(values: samples),
    budget: .production
  )
  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)

  let result = try await session.finish(stopOrigin: testStopOrigin())

  #expect(result.cleanupOutcome == .usedRaw)
  #expect(result.insertedText == "Do not cancel 2 meetings")
  #expect(session.runtimeMeasurements.cleanupDecisionCompletedAt == samples[5])
  #expect(result.measurements.cleanupDecisionCompletedAt == samples[5])
}

@Test @MainActor
func processorMeasurementsRecordSingleCancellationRequestAndDrainForConcurrentCallers() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = (0...4).map { start.advanced(by: .milliseconds($0)) }
  let sequence = InstantSequence(samples)
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    finishBlocksUntilCancel: true,
    onCancel: {
      order.append(.sourceCancelStarted)
      await order.waitUntil(.secondCallerEntered)
    }
  )
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "First"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: DictationClock(now: { sequence.next() }),
    budget: .production
  )
  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)
  let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await source.waitUntilFinishStarted()

  let firstCancellation = Task { await session.cancel() }
  await order.waitUntil(.sourceCancelStarted)
  let secondCancellation = Task {
    order.append(.secondCallerEntered)
    await session.cancel()
  }
  await firstCancellation.value
  await secondCancellation.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(session.runtimeMeasurements.cancellationRequestedAt == samples[3])
  #expect(session.runtimeMeasurements.cancellationDrainedAt == samples[4])
  #expect(session.runtimeMeasurements.cancellationMilliseconds == 1)
  #expect(source.cancelCount == 1)
  #expect(sequence.callCount == 5)

  await session.cancel()
  #expect(sequence.callCount == 5)
}

@Test @MainActor
func processorMeasurementsLeaveFirstMeaningfulPartialAbsentWithoutGenuinePartial() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = (0...6).map { start.advanced(by: .milliseconds($0)) }
  let source = StreamingSpeechSourceProbe(synchronousProvisional: "   \n")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "First"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: TestDictationClock(values: samples),
    budget: .production
  )
  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)

  let result = try await session.finish(stopOrigin: testStopOrigin())

  #expect(session.runtimeMeasurements.firstMeaningfulPartialAt == nil)
  #expect(session.runtimeMeasurements.firstMeaningfulPartialMilliseconds == nil)
  #expect(result.insertedText == "First.")
}

@Test @MainActor
func processorMeasurementsPreserveCompletedFailureBoundariesAndLeaveUnreachedStagesAbsent() async throws {
  for finalText in [nil, ""] as [String?] {
    let start = TestDictationClock.fixedInstant
    let samples = (0...3).map { start.advanced(by: .milliseconds($0)) }
    let processor = StreamingDictationProcessor(
      makeSource: { _ in StreamingSpeechSourceProbe(finalText: finalText) },
      dictionaryResolver: DictionaryResolverProbe(
        resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
      ),
      cleaner: IncrementalTranscriptCleaner(
        generator: CleanupGeneratorProbe(result: "First"),
        clock: TestCleanupClock.immediate
      ),
      runtime: nil,
      clock: TestDictationClock(values: samples),
      budget: .production
    )
    let session = try #require(try await processor.begin(
      configuration: .init(
        captureID: UUID(),
        mode: .focused,
        recognitionContext: .englishDefault
      ),
      level: { _ in }
    ) as? StreamingDictationSession)

    await #expect(throws: StreamingDictationProcessorError.noSpeech) {
      try await session.finish(stopOrigin: testStopOrigin())
    }
    #expect(session.runtimeMeasurements.asrFinalAt == samples[3])
    #expect(session.runtimeMeasurements.dictionaryCompletedAt == nil)
    #expect(session.runtimeMeasurements.cleanupDecisionCompletedAt == nil)
  }

  do {
    let start = TestDictationClock.fixedInstant
    let samples = (0...4).map { start.advanced(by: .milliseconds($0)) }
    let processor = StreamingDictationProcessor(
      makeSource: { _ in StreamingSpeechSourceProbe() },
      dictionaryResolver: DictionaryResolverProbe(error: .failed),
      cleaner: IncrementalTranscriptCleaner(
        generator: CleanupGeneratorProbe(result: "First"),
        clock: TestCleanupClock.immediate
      ),
      runtime: nil,
      clock: TestDictationClock(values: samples),
      budget: .production
    )
    let session = try #require(try await processor.begin(
      configuration: .init(
        captureID: UUID(),
        mode: .focused,
        recognitionContext: .englishDefault
      ),
      level: { _ in }
    ) as? StreamingDictationSession)

    let result = try await session.finish(stopOrigin: testStopOrigin())

    #expect(result.cleanupOutcome == .usedRaw)
    #expect(result.insertedText == "First")
    #expect(session.runtimeMeasurements.dictionaryCompletedAt == samples[4])
    #expect(session.runtimeMeasurements.cleanupDecisionCompletedAt == nil)
  }

  do {
    let start = TestDictationClock.fixedInstant
    let samples = (0...6).map { start.advanced(by: .milliseconds($0)) }
    let generator = CleanupGeneratorProbe(
      result: "First",
      waitsForCancellation: true
    )
    let processor = StreamingDictationProcessor(
      makeSource: { _ in StreamingSpeechSourceProbe() },
      dictionaryResolver: DictionaryResolverProbe(
        resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
      ),
      cleaner: IncrementalTranscriptCleaner(
        generator: generator,
        clock: TestCleanupClock.immediate
      ),
      runtime: nil,
      clock: TestDictationClock(values: samples),
      budget: .production
    )
    let session = try #require(try await processor.begin(
      configuration: .init(
        captureID: UUID(),
        mode: .focused,
        recognitionContext: .englishDefault
      ),
      level: { _ in }
    ) as? StreamingDictationSession)
    let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
    await generator.waitUntilStarted()

    await session.cancel()
    await #expect(throws: CancellationError.self) { try await finalization.value }

    #expect(session.runtimeMeasurements.asrFinalAt == samples[3])
    #expect(session.runtimeMeasurements.dictionaryCompletedAt == samples[4])
    #expect(session.runtimeMeasurements.cleanupDecisionCompletedAt == nil)
    #expect(session.runtimeMeasurements.cancellationRequestedAt == samples[5])
    #expect(session.runtimeMeasurements.cancellationDrainedAt == samples[6])
  }
}

@Test @MainActor
func processorMeasurementsRejectBackwardClockSamplesWithoutChangingText() async throws {
  let start = TestDictationClock.fixedInstant
  let samples = [
    start,
    start.advanced(by: .milliseconds(-1)),
    start.advanced(by: .milliseconds(1)),
    start.advanced(by: .milliseconds(2)),
    start.advanced(by: .milliseconds(3)),
    start.advanced(by: .milliseconds(4)),
  ]
  let processor = StreamingDictationProcessor(
    makeSource: { _ in StreamingSpeechSourceProbe() },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(baseline: "First", protectedForms: [], replacements: 0)
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "First"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: TestDictationClock(values: samples),
    budget: .production
  )
  let session = try #require(try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { _ in }
  ) as? StreamingDictationSession)

  let result = try await session.finish(stopOrigin: testStopOrigin())
  let measurements = session.runtimeMeasurements

  #expect(result.insertedText == "First.")
  #expect(measurements.integrity == .nonMonotonicClock)
  #expect(measurements.processorStartedAt == samples[0])
  #expect(measurements.sourceStartRequestedAt == nil)
  #expect(measurements.stopRequestedAt == nil)
  #expect(measurements.asrFinalAt == nil)
  #expect(measurements.dictionaryCompletedAt == nil)
  #expect(measurements.cleanupDecisionCompletedAt == nil)
  #expect(measurements.finalASRMilliseconds == nil)
  #expect(result.measurements == measurements)
}

@Test @MainActor
func beginStartsTheSoleSourceOnceBeforeReturningAndWiresCallbacks() async throws {
  let source = StreamingSpeechSourceProbe()
  let processor = makeProcessor(source: source)

  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  #expect(source.startCount == 1)
  #expect(source.callbacksWereInstalled)
  source.emitProvisional("First")
  #expect(source.provisionalCallbackCount == 1)
  await session.cancel()
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
}

@Test @MainActor
func beginPassesSelectedEngineToSourceFactory() async throws {
  let source = StreamingSpeechSourceProbe()
  var receivedConfiguration: DictationProcessingConfiguration?
  let processor = makeProcessor(
    source: source,
    onConfiguration: { receivedConfiguration = $0 }
  )

  let session = try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault,
      engine: .enhancedLocal
    ),
    level: { _ in }
  )

  #expect(receivedConfiguration?.engine == .enhancedLocal)
  await session.cancel()
}

@Test @MainActor
func beginForwardsSynchronousAndLaterSourceLevelsExactlyOnce() async throws {
  var levels: [Float] = []
  let source = StreamingSpeechSourceProbe(synchronousLevel: 0.25)
  let processor = makeProcessor(source: source)

  let session = try await processor.begin(
    configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ),
    level: { levels.append($0) }
  )
  source.emitLevel(0.75)

  #expect(levels == [0.25, 0.75])
  await session.cancel()
}

@Test @MainActor
func beginRetainsSynchronousCallbacksUntilTheSessionAttaches() async throws {
  let source = StreamingSpeechSourceProbe(synchronousProvisional: "First")
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  let update = try await firstUpdate(from: session.updates)
  #expect(update?.displayText == "First")
  await session.cancel()
}

@Test @MainActor
func beginReleasesTheSourceWhenStartFails() async {
  let source = StreamingSpeechSourceProbe(startError: .failed)
  let processor = makeProcessor(source: source)

  await #expect(throws: StreamingSpeechSourceProbeError.failed) {
    _ = try await processor.begin(configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ), level: { _ in })
  }
  #expect(source.startCount == 1)
  #expect(source.releaseHookCount == 1)
  #expect(source.physicalReleaseCount == 0)
}

@Test @MainActor
func successfulFinishUsesSourceOwnedTerminalizationWithoutSecondRelease() async throws {
  let source = StreamingSpeechSourceProbe()
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  _ = try await session.finish(stopOrigin: testStopOrigin())
  source.emitProvisional("late")

  #expect(source.cancelCount == 0)
  #expect(source.finishCount == 1)
  #expect(source.finishCompleted)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
  await session.cancel()
  #expect(source.cancelCount == 0)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func emptyFinalTextThrowsStreamingProcessorNoSpeech() async throws {
  let source = StreamingSpeechSourceProbe(finalText: nil)
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  await #expect(throws: StreamingDictationProcessorError.noSpeech) {
    _ = try await session.finish(stopOrigin: testStopOrigin())
  }
  #expect(source.finishCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func failedFinishUsesSourceOwnedTerminalizationAndPublishesNoLateUpdate() async throws {
  let source = StreamingSpeechSourceProbe(finishError: .failed)
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let updates = Task { @MainActor in
    try await collectUpdates(from: session.updates)
  }

  await #expect(throws: StreamingSpeechSourceProbeError.failed) {
    _ = try await session.finish(stopOrigin: testStopOrigin())
  }
  source.emitProvisional("late")

  #expect(source.cancelCount == 0)
  #expect(source.finishCount == 1)
  #expect(source.finishCompleted)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
  await session.cancel()
  #expect(source.cancelCount == 0)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func cancellingAfterSourceFinishAwaitsCleanupWithoutSecondSourceTerminalization() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
  )
  let helper = CleanupGeneratorProbe(
    result: "Send the report.",
    waitsForCancellation: true,
    onAcknowledgementFinished: {
      await order.append(.helperAcknowledged)
    }
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: helper,
    clock: TestCleanupClock.bounded(milliseconds: 1),
    cancellationBudget: .milliseconds(25)
  )
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "Send the report",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let updates = Task { @MainActor in
    try await collectUpdates(from: session.updates)
  }
  let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await helper.waitUntilStarted()

  #expect(source.finishCount == 1)
  #expect(source.finishCompleted)
  #expect(source.cancelCount == 0)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)

  await session.cancel()
  await order.append(.firstCallerReturned)

  #expect(helper.acknowledgementFinished)
  await #expect(throws: CancellationError.self) { try await finalization.value }
  #expect(source.cancelCount == 0)
  #expect(source.finishCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let physicalReleaseIndex = try #require(
    events.firstIndex(of: .sourcePhysicalRelease)
  )
  let helperIndex = try #require(events.firstIndex(of: .helperAcknowledged))
  let returnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  #expect(physicalReleaseIndex < helperIndex)
  #expect(helperIndex < returnIndex)
  #expect(!events.contains(.sourceCancelStarted))
}

enum CancellationDrainEvent: Equatable {
  case sourceCancelStarted
  case sourcePhysicalRelease
  case helperAcknowledged
  case sharedDrainCompleted
  case secondCallerEntered
  case firstCallerReturned
  case secondCallerReturned
}

@MainActor
final class CancellationDrainRecorder {
  private(set) var events: [CancellationDrainEvent] = []

  func append(_ event: CancellationDrainEvent) {
    events.append(event)
  }

  func waitUntil(_ event: CancellationDrainEvent) async {
    while !events.contains(event) { await Task.yield() }
  }
}

@Test @MainActor
func concurrentCancelCallersShareOneTaskDuringBlockedFinish() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    finishBlocksUntilCancel: true,
    onCancel: {
      await order.append(.sourceCancelStarted)
      await order.waitUntil(.secondCallerEntered)
    },
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
  )
  let processor = makeProcessor(
    source: source,
    onCancellationDrained: { order.append(.sharedDrainCompleted) }
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let updates = Task { @MainActor in
    try await collectUpdates(from: session.updates)
  }
  let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await source.waitUntilFinishStarted()

  let first = Task {
    await session.cancel()
    await order.append(.firstCallerReturned)
  }
  await order.waitUntil(.sourceCancelStarted)
  let second = Task {
    await order.append(.secondCallerEntered)
    await session.cancel()
    await order.append(.secondCallerReturned)
  }
  await first.value
  await second.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.finishCompleted == false)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let cancelIndex = try #require(events.firstIndex(of: .sourceCancelStarted))
  let secondEntryIndex = try #require(events.firstIndex(of: .secondCallerEntered))
  let physicalReleaseIndex = try #require(
    events.firstIndex(of: .sourcePhysicalRelease)
  )
  let sharedDrainIndex = try #require(
    events.firstIndex(of: .sharedDrainCompleted)
  )
  let firstReturnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  let secondReturnIndex = try #require(events.firstIndex(of: .secondCallerReturned))
  #expect(cancelIndex < secondEntryIndex)
  #expect(physicalReleaseIndex < firstReturnIndex)
  #expect(physicalReleaseIndex < secondReturnIndex)
  #expect(sharedDrainIndex < firstReturnIndex)
  #expect(sharedDrainIndex < secondReturnIndex)
}

@Test @MainActor
func cancellingBeforeFinalizationBodyStartsSkipsSourceFinish() async throws {
  let order = CancellationDrainRecorder()
  let gate = FinalizationStartGate()
  let source = StreamingSpeechSourceProbe(
    onCancel: {
      await order.append(.sourceCancelStarted)
      await order.waitUntil(.secondCallerEntered)
    },
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
  )
  let processor = makeProcessor(
    source: source,
    finalizationStartGate: { await gate.wait() },
    onCancellationDrained: { order.append(.sharedDrainCompleted) }
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let updates = Task { @MainActor in
    try await collectUpdates(from: session.updates)
  }
  let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await gate.waitUntilEntered()
  #expect(source.finishCount == 0)

  let first = Task {
    await session.cancel()
    await order.append(.firstCallerReturned)
  }
  await order.waitUntil(.sourceCancelStarted)
  let second = Task {
    await order.append(.secondCallerEntered)
    await session.cancel()
    await order.append(.secondCallerReturned)
  }
  await order.waitUntil(.secondCallerEntered)
  gate.release()

  await first.value
  await second.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(source.finishStarted == false)
  #expect(source.finishCount == 0)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let sharedDrainIndex = try #require(
    events.firstIndex(of: .sharedDrainCompleted)
  )
  let firstReturnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  let secondReturnIndex = try #require(events.firstIndex(of: .secondCallerReturned))
  #expect(sharedDrainIndex < firstReturnIndex)
  #expect(sharedDrainIndex < secondReturnIndex)
}

@Test @MainActor
func cancellingBlockedFinishReturningNilWinsWithoutNoSpeechResult() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    finalText: nil,
    finishBlocksUntilCancel: true,
    finishReturnsNilAfterCancel: true,
    onCancel: {
      await order.append(.sourceCancelStarted)
      await order.waitUntil(.secondCallerEntered)
    },
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
  )
  let processor = makeProcessor(
    source: source,
    onCancellationDrained: { order.append(.sharedDrainCompleted) }
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let updates = Task { @MainActor in
    try await collectUpdates(from: session.updates)
  }
  let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await source.waitUntilFinishStarted()

  let first = Task {
    await session.cancel()
    await order.append(.firstCallerReturned)
  }
  await order.waitUntil(.sourceCancelStarted)
  let second = Task {
    await order.append(.secondCallerEntered)
    await session.cancel()
    await order.append(.secondCallerReturned)
  }
  await first.value
  await second.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(source.finishCount == 1)
  #expect(source.finishUnblockedByCancel)
  #expect(source.finishCompleted)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let sharedDrainIndex = try #require(
    events.firstIndex(of: .sharedDrainCompleted)
  )
  let firstReturnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  let secondReturnIndex = try #require(events.firstIndex(of: .secondCallerReturned))
  #expect(sharedDrainIndex < firstReturnIndex)
  #expect(sharedDrainIndex < secondReturnIndex)
}

@Test @MainActor
func cancellingSessionUnblocksInFlightSourceFinishWithSourceOwnedRelease() async throws {
  let source = StreamingSpeechSourceProbe(finishBlocksUntilCancel: true)
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let updates = Task { @MainActor in
    try await collectUpdates(from: session.updates)
  }
  let firstFinish = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await source.waitUntilFinishStarted()
  #expect(source.finishCompleted == false)
  #expect(source.physicalReleaseCount == 0)
  let secondFinish = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await Task.yield()

  await session.cancel()

  await #expect(throws: CancellationError.self) { try await firstFinish.value }
  await #expect(throws: CancellationError.self) { try await secondFinish.value }
  #expect(source.finishCount == 1)
  #expect(source.finishUnblockedByCancel)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.finishCompleted == false)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
}

@Test @MainActor
func cancellingBeforeFinishCannotStartFinalizationWork() async throws {
  let source = StreamingSpeechSourceProbe()
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  await session.cancel()

  await #expect(throws: CancellationError.self) { try await session.finish(stopOrigin: testStopOrigin()) }
  #expect(source.finishCount == 0)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
}

@MainActor
private final class CancellationRaceRecorder {
  private(set) var invalidated = false

  func recordInvalidation() {
    invalidated = true
  }

  func waitUntilInvalidated() async {
    while !invalidated { await Task.yield() }
  }
}

@Test @MainActor
func cancellationWinnerClosesTheFinishRaceBeforeAnyFinalizationOrSourceFinish() async throws {
  let source = StreamingSpeechSourceProbe()
  let recorder = CancellationRaceRecorder()
  let processor = makeProcessor(
    source: source,
    onCancellationInvalidated: { recorder.recordInvalidation() }
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  let cancellation = Task { await session.cancel() }
  await recorder.waitUntilInvalidated()
  let finish = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await cancellation.value
  await #expect(throws: CancellationError.self) { try await finish.value }
  #expect(source.finishCount == 0)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func processorUsesExactBaselineWhenCleanupIsRejected() async throws {
  let engine = SpeechEngineProbe(finalText: "Do not cancel 2 meetings")
  let cleaner = IncrementalTranscriptCleaner(
    generator: CleanupGeneratorProbe(result: "Cancel the meetings"),
    clock: TestCleanupClock.immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { _ in AppleSpeechStreamingAdapter(engine: engine) },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "Do not cancel 2 meetings",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let result = try await session.finish(stopOrigin: testStopOrigin())
  #expect(result.insertedText == "Do not cancel 2 meetings")
  #expect(result.cleanedTranscript == nil)
}

@Test @MainActor
func processorUsesRawRecoveryWhenDictionaryResolutionFails() async throws {
  let raw = "Do not cancel 2 meetings"
  let engine = SpeechEngineProbe(finalText: raw)
  let cleaner = IncrementalTranscriptCleaner(
    generator: CleanupGeneratorProbe(result: "Cancel the meetings"),
    clock: TestCleanupClock.immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { _ in AppleSpeechStreamingAdapter(engine: engine) },
    dictionaryResolver: DictionaryResolverProbe(error: .failed),
    cleaner: cleaner,
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })

  let result = try await session.finish(stopOrigin: testStopOrigin())
  #expect(result.rawTranscript == raw)
  #expect(result.dictionaryBaseline == nil)
  #expect(result.cleanedTranscript == nil)
  #expect(result.insertedText == raw)
  #expect(result.cleanupOutcome == .usedRaw)
}

@Test @MainActor
func processorUnsupportedDictionaryRecognitionStillUsesPinnedResolution() async throws {
  let context = try processorDictionaryContext(revision: 11)
  let source = StreamingSpeechSourceProbe(finalText: "open fleck app")
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    recognitionContextAcknowledgement: { configuration in
      .unsupported(try #require(configuration.captureContext))
    },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "open FleckApp"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )

  let result = try await processor.begin(
    configuration: processorDictionaryConfiguration(context),
    level: { _ in }
  ).finish(stopOrigin: testStopOrigin())

  #expect(source.startCount == 1)
  #expect(result.dictionaryBaseline == "open FleckApp")
  #expect(result.captureContext == context)
  #expect(result.recognitionContextAcknowledgement == .unsupported(context))
  #expect(result.dictionaryRevision == 11)
  #expect(result.dictionaryContentDigest == context.dictionaryContentDigest)
  #expect(result.appliedDictionaryEntryIDs == context.snapshot.entries.map(\.id))
}

@Test @MainActor
func processorNilDictionaryContextFailsBeforeSourceCreation() async throws {
  let source = StreamingSpeechSourceProbe()
  var makeSourceCount = 0
  var acknowledgementCount = 0
  let processor = StreamingDictationProcessor(
    makeSource: { _ in
      makeSourceCount += 1
      return source
    },
    recognitionContextAcknowledgement: { _ in
      acknowledgementCount += 1
      throw StreamingSpeechSourceProbeError.failed
    },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "unused"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )

  do {
    let configuration = DictationProcessingConfiguration(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    )
    let session = try await processor.begin(
      configuration: configuration,
      level: { _ in },
      startAuthorized: { true }
    )
    Issue.record("Expected missing capture context")
    await session.cancel()
  } catch {
    #expect(error as? StreamingDictationProcessorError == .captureContextMismatch)
  }

  #expect(makeSourceCount == 0)
  #expect(acknowledgementCount == 0)
  #expect(source.startCount == 0)
  #expect(source.releaseHookCount == 0)
}

@Test @MainActor
func processorRejectedDictionaryRecognitionConsumesNoAudio() async throws {
  let context = try processorDictionaryContext()
  let source = StreamingSpeechSourceProbe()
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    recognitionContextAcknowledgement: { _ in .rejected(context) },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "unused"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )

  do {
    _ = try await processor.begin(
      configuration: processorDictionaryConfiguration(context),
      level: { _ in }
    )
    Issue.record("Expected rejected recognition context")
  } catch {
    #expect(error as? StreamingDictationProcessorError == .recognitionContextRejected)
  }
  #expect(source.startCount == 0)
  #expect(source.releaseHookCount == 1)
}

@Test @MainActor
func processorThrowingDictionaryAcknowledgementReleasesSourceWithoutAudio() async throws {
  let context = try processorDictionaryContext()
  let source = StreamingSpeechSourceProbe()
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    recognitionContextAcknowledgement: { _ in throw StreamingSpeechSourceProbeError.failed },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "unused"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )

  await #expect(throws: StreamingSpeechSourceProbeError.failed) {
    _ = try await processor.begin(
      configuration: processorDictionaryConfiguration(context),
      level: { _ in }
    )
  }
  #expect(source.startCount == 0)
  #expect(source.releaseHookCount == 1)
}

@Test @MainActor
func processorDictionaryCancellationWhileSourceCreationIsSuspendedConsumesNoAudio() async throws {
  let context = try processorDictionaryContext()
  let sourceGate = Gate()
  let source = StreamingSpeechSourceProbe()
  var startAuthorized = true
  let processor = StreamingDictationProcessor(
    makeSource: { _ in
      await sourceGate.wait()
      return source
    },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "unused"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )
  let errorBox = ProcessingBeginErrorBox()
  let begin = Task {
    do {
      _ = try await processor.begin(
        configuration: processorDictionaryConfiguration(context),
        level: { _ in },
        startAuthorized: { startAuthorized }
      )
    } catch {
      errorBox.error = error
    }
  }
  await sourceGate.waitUntilWaiting()

  startAuthorized = false
  await sourceGate.openGate()
  await begin.value

  #expect(errorBox.error is CancellationError)
  #expect(source.startCount == 0)
  #expect(source.releaseHookCount == 1)
}

@Test @MainActor
func processorDictionaryCancellationWhileAcknowledgementIsSuspendedConsumesNoAudio() async throws {
  let context = try processorDictionaryContext()
  let acknowledgementGate = Gate()
  let source = StreamingSpeechSourceProbe()
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    recognitionContextAcknowledgement: { _ in
      await acknowledgementGate.wait()
      return .unsupported(context)
    },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "unused"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )
  let errorBox = ProcessingBeginErrorBox()
  let begin = Task {
    do {
      _ = try await processor.begin(
        configuration: processorDictionaryConfiguration(context),
        level: { _ in }
      )
    } catch {
      errorBox.error = error
    }
  }
  await acknowledgementGate.waitUntilWaiting()

  begin.cancel()
  await acknowledgementGate.openGate()
  await begin.value

  #expect(errorBox.error is CancellationError)
  #expect(source.startCount == 0)
  #expect(source.releaseHookCount == 1)
}

@Test @MainActor
func processorMismatchedDictionaryAcknowledgementConsumesNoAudio() async throws {
  let context = try processorDictionaryContext(captureID: UUID())
  let mismatches = try [
    processorDictionaryContext(from: context, captureID: UUID()),
    processorDictionaryContext(from: context, generation: context.generation + 1),
    processorDictionaryContext(revision: context.dictionaryRevision + 1),
    processorDictionaryContext(from: context, speechEngine: .enhancedLocal),
  ]

  for mismatch in mismatches {
    let source = StreamingSpeechSourceProbe()
    let processor = StreamingDictationProcessor(
      makeSource: { _ in source },
      recognitionContextAcknowledgement: { _ in .applied(mismatch) },
      dictionaryResolver: PersonalDictionaryTranscriptResolver(),
      cleaner: IncrementalTranscriptCleaner(
        generator: CleanupGeneratorProbe(result: "unused"),
        clock: TestCleanupClock.immediate
      ),
      runtime: nil
    )

    do {
      _ = try await processor.begin(
        configuration: processorDictionaryConfiguration(context),
        level: { _ in }
      )
      Issue.record("Expected mismatched recognition context")
    } catch {
      #expect(error as? StreamingDictationProcessorError == .recognitionContextMismatch)
    }
    #expect(source.startCount == 0)
    #expect(source.releaseHookCount == 1)
  }
}

@Test @MainActor
func processorDictionaryResolutionMismatchUsesExactRawBaseline() async throws {
  let context = try processorDictionaryContext(revision: 3)
  let raw = "open fleck app"
  let processor = StreamingDictationProcessor(
    makeSource: { _ in StreamingSpeechSourceProbe(finalText: raw) },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "open Wrong",
        protectedForms: ["Wrong"],
        replacements: 1,
        dictionaryRevision: 99,
        dictionaryContentDigest: "wrong"
      )
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "must not run"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )

  let result = try await processor.begin(
    configuration: processorDictionaryConfiguration(context),
    level: { _ in }
  ).finish(stopOrigin: testStopOrigin())

  #expect(result.dictionaryBaseline == nil)
  #expect(result.insertedText == raw)
  #expect(result.appliedDictionaryEntryIDs.isEmpty)
  #expect(result.captureContext == context)
}

@Test @MainActor
func processorCleanupRejectedDictionaryCandidateUsesPinnedBaselineAndEvidence() async throws {
  let context = try processorDictionaryContext(revision: 14)
  let processor = StreamingDictationProcessor(
    makeSource: { _ in StreamingSpeechSourceProbe(finalText: "open fleck app") },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "close the app"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )

  let result = try await processor.begin(
    configuration: processorDictionaryConfiguration(context),
    level: { _ in }
  ).finish(stopOrigin: testStopOrigin())

  #expect(result.cleanupOutcome == .usedRaw)
  #expect(result.insertedText == "open FleckApp")
  #expect(result.protectedDictionaryForms == ["FleckApp"])
  #expect(result.appliedDictionaryEntryIDs == context.snapshot.entries.map(\.id))
  #expect(result.dictionaryRevision == context.dictionaryRevision)
  #expect(result.dictionaryContentDigest == context.dictionaryContentDigest)
}

@Test @MainActor
func processorDictionarySettingsMutationDoesNotAlterInflightContext() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckProcessorDictionary-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let first = PersonalDictionaryEntry(preferredForm: "FleckApp", aliases: ["fleck app"])
  try await store.upsert(first)
  let published = try await store.publishedSnapshot()
  let context = try LocalWritingCaptureContext(
    captureID: UUID(),
    generation: 1,
    localeIdentifier: published.compiled.localeIdentifier,
    speechEngine: .standard,
    snapshot: published.snapshot,
    compiledDictionary: published.compiled
  )
  var receivedRecognitionContext: DictationRecognitionContext?
  let processor = StreamingDictationProcessor(
    makeSource: { configuration in
      receivedRecognitionContext = configuration.recognitionContext
      return StreamingSpeechSourceProbe(finalText: "open fleck app")
    },
    dictionaryResolver: PersonalDictionaryTranscriptResolver(),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "open FleckApp"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil
  )
  let session = try await processor.begin(
    configuration: processorDictionaryConfiguration(context),
    level: { _ in }
  )

  try await store.setEnabled(false, id: first.id)
  let result = try await session.finish(stopOrigin: testStopOrigin())

  #expect(receivedRecognitionContext?.contextualStrings == context.compiledDictionary.recognitionStrings)
  #expect(result.dictionaryBaseline == "open FleckApp")
  #expect(result.dictionaryRevision == context.dictionaryRevision)
}

@Test @MainActor
func processorCapturesStopBeforeDelayedSourceFinalization() async throws {
  let stop = TestDictationClock.fixedInstant
  let manualClock = ManuallyAdvancedInstant(stop)
  let clock = DictationClock(now: { manualClock.now })
  let source = StreamingSpeechSourceProbe(finishBlocksUntilRelease: true)
  let generator = CleanupGeneratorProbe(result: "send the report")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { _ in source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "send the report",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil,
    clock: clock,
    budget: .init(insertion: .seconds(4), cleanup: .milliseconds(1_500))
  )

  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let finalization = Task { try await session.finish(stopOrigin: testStopOrigin()) }
  await source.waitUntilFinishStarted()
  #expect(source.finishCompleted == false)

  manualClock.advance(by: .seconds(2))
  let sourceFinishedAt = manualClock.now
  source.releaseFinish()
  _ = try await finalization.value

  #expect(await generator.requests.first?.deadline == stop.advanced(by: .milliseconds(1500)))
  #expect(await generator.requests.first?.deadline != sourceFinishedAt.advanced(by: .milliseconds(1500)))
  #expect(sourceFinishedAt.advanced(by: .seconds(1)) == stop.advanced(by: .seconds(3)))
}

private struct DictionaryResolverProbe: TranscriptDictionaryResolving {
  enum Error: Swift.Error, Equatable {
    case failed
  }

  let resolution: PersonalDictionaryResolution?
  let error: Error?

  init(resolution: PersonalDictionaryResolution) {
    self.resolution = resolution
    self.error = nil
  }

  init(error: Error) {
    self.resolution = nil
    self.error = error
  }

  func resolve(_ rawTranscript: String) async throws -> PersonalDictionaryResolution {
    if let error { throw error }
    return resolution ?? .init(baseline: rawTranscript, protectedForms: [], replacements: 0)
  }
}

private enum TestCleanupClock {
  static let immediate = CleanupClock(
    now: { ContinuousClock().now },
    sleepUntil: { deadline in
      try await ContinuousClock().sleep(until: deadline)
    },
    sleepFor: { _ in }
  )

  static func bounded(milliseconds: Int) -> CleanupClock {
    CleanupClock(
      now: { ContinuousClock().now },
      sleepUntil: { deadline in
        try await ContinuousClock().sleep(until: deadline)
      },
      sleepFor: { _ in }
    )
  }
}

private typealias TestDictationClock = DictationClock

private extension DictationClock {
  static let fixedInstant = ContinuousClock().now
  static let immediate = Self(now: { ContinuousClock().now })

  init(values: [ContinuousClock.Instant]) {
    let sequence = InstantSequence(values)
    self.init(now: { sequence.next() })
  }
}

private final class InstantSequence: @unchecked Sendable {
  private let lock = NSLock()
  private let values: [ContinuousClock.Instant]
  private var index = 0

  init(_ values: [ContinuousClock.Instant]) {
    self.values = values
  }

  func next() -> ContinuousClock.Instant {
    lock.lock()
    defer { lock.unlock() }
    let value = values[min(index, values.count - 1)]
    index += 1
    return value
  }

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return index
  }
}

private final class ManuallyAdvancedInstant: @unchecked Sendable {
  private let lock = NSLock()
  private var value: ContinuousClock.Instant

  init(_ value: ContinuousClock.Instant) {
    self.value = value
  }

  var now: ContinuousClock.Instant {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func advance(by duration: Duration) {
    lock.lock()
    value = value.advanced(by: duration)
    lock.unlock()
  }
}

private final class CleanupGeneratorProbe: BoundedCleanupGenerating, @unchecked Sendable {
  private let lock = NSLock()
  private let resultText: String
  private let waitsForCancellation: Bool
  private let onAcknowledgementFinished: (@Sendable () async -> Void)?
  private var session: CleanupGenerationSessionProbe?
  private var requestsStorage: [IncrementalCleanupRequest] = []
  private var startedStorage = false

  init(
    result: String,
    waitsForCancellation: Bool = false,
    onAcknowledgementFinished: (@Sendable () async -> Void)? = nil
  ) {
    self.resultText = result
    self.waitsForCancellation = waitsForCancellation
    self.onAcknowledgementFinished = onAcknowledgementFinished
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    let session = CleanupGenerationSessionProbe(
      result: .init(cleaned: resultText),
      waitsForCancellation: waitsForCancellation,
      onAcknowledgementFinished: onAcknowledgementFinished
    )
    lock.lock()
    requestsStorage.append(request)
    startedStorage = true
    self.session = session
    lock.unlock()
    _ = maximumOutputTokens
    return session
  }

  var requests: [IncrementalCleanupRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requestsStorage
  }

  func waitUntilStarted() async {
    while !isStarted() {
      await Task.yield()
    }
  }

  var acknowledgementFinished: Bool {
    lock.lock()
    let value = session?.acknowledgementFinished ?? false
    lock.unlock()
    return value
  }

  private func isStarted() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return startedStorage
  }
}

private final class CleanupGenerationSessionProbe: CleanupGenerationSession, @unchecked Sendable {
  private let lock = NSLock()
  private let candidate: GeneratedCleanupCandidate
  private let waitsForCancellation: Bool
  private let onAcknowledgementFinished: (@Sendable () async -> Void)?
  private var resultAvailable = false
  private var cancelled = false
  private var terminated = false
  private var acknowledgementSignaled = false
  private var acknowledgementFinishedStorage = false
  private var startedStorage = false

  init(
    result: GeneratedCleanupCandidate,
    waitsForCancellation: Bool,
    onAcknowledgementFinished: (@Sendable () async -> Void)?
  ) {
    self.candidate = result
    self.waitsForCancellation = waitsForCancellation
    self.onAcknowledgementFinished = onAcknowledgementFinished
    self.resultAvailable = !waitsForCancellation
  }

  func result() async throws -> GeneratedCleanupCandidate {
    markStarted()
    while true {
      let outcome = currentOutcome()
      if let outcome { return try outcome.get() }
      await Task.yield()
    }
  }

  func acknowledgement() async {
    while !isAcknowledgementSignaled() {
      await Task.yield()
    }
    await onAcknowledgementFinished?()
    markAcknowledgementFinished()
  }

  func requestCancellation() {
    lock.lock()
    cancelled = true
    acknowledgementSignaled = true
    lock.unlock()
  }

  func forceTerminate() {
    lock.lock()
    terminated = true
    acknowledgementSignaled = true
    lock.unlock()
  }

  func waitUntilStarted() async {
    while !isStarted() {
      await Task.yield()
    }
  }

  var acknowledgementFinished: Bool {
    lock.lock()
    defer { lock.unlock() }
    return acknowledgementFinishedStorage
  }

  private func markStarted() {
    lock.lock()
    startedStorage = true
    lock.unlock()
  }

  private func currentOutcome() -> Result<GeneratedCleanupCandidate, CleanupGenerationError>? {
    lock.lock()
    defer { lock.unlock() }
    if terminated {
      return .failure(.terminated)
    }
    if cancelled {
      return .failure(.requestCancelled)
    }
    if resultAvailable {
      return .success(candidate)
    }
    return nil
  }

  private func isAcknowledgementSignaled() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return acknowledgementSignaled
  }

  private func markAcknowledgementFinished() {
    lock.lock()
    acknowledgementFinishedStorage = true
    lock.unlock()
  }

  private func isStarted() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return startedStorage
  }
}
