import Foundation
import Testing
import FleckCore

@testable import FleckApp

@MainActor
private func makeProcessor(
  source: any StreamingSpeechSource,
  finalizationStartGate: (@MainActor @Sendable () async -> Void)? = nil,
  onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
  onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
) -> StreamingDictationProcessor {
  StreamingDictationProcessor(
    makeSource: { source },
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

  _ = try await session.finish()
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
    _ = try await session.finish()
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
    _ = try await session.finish()
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
    makeSource: { source },
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
  let finalization = Task { try await session.finish() }
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
  let finalization = Task { try await session.finish() }
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
  let finalization = Task { try await session.finish() }
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
  let finalization = Task { try await session.finish() }
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
  let firstFinish = Task { try await session.finish() }
  await source.waitUntilFinishStarted()
  #expect(source.finishCompleted == false)
  #expect(source.physicalReleaseCount == 0)
  let secondFinish = Task { try await session.finish() }
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

  await #expect(throws: CancellationError.self) { try await session.finish() }
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
  let finish = Task { try await session.finish() }
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
    makeSource: { AppleSpeechStreamingAdapter(engine: engine) },
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
  let result = try await session.finish()
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
    makeSource: { AppleSpeechStreamingAdapter(engine: engine) },
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

  let result = try await session.finish()
  #expect(result.rawTranscript == raw)
  #expect(result.dictionaryBaseline == nil)
  #expect(result.cleanedTranscript == nil)
  #expect(result.insertedText == raw)
  #expect(result.cleanupOutcome == .usedRaw)
}

@Test @MainActor
func processorCapturesStopBeforeDelayedSourceFinalization() async throws {
  let stop = TestDictationClock.fixedInstant
  let sourceFinishedAt = stop.advanced(by: .seconds(2))
  let clock = TestDictationClock(values: [stop, sourceFinishedAt])
  let source = StreamingSpeechSourceProbe(finishBlocksUntilRelease: true)
  let generator = CleanupGeneratorProbe(result: "send the report")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { source },
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
    budget: .production
  )

  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ), level: { _ in })
  let finalization = Task { try await session.finish() }
  await source.waitUntilFinishStarted()
  #expect(source.finishCompleted == false)

  // The second deterministic instant represents two seconds spent inside
  // source.finish(). It is observed before releasing the source gate; no
  // production wall clock or sleep is involved.
  #expect(clock.now() == sourceFinishedAt)
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
