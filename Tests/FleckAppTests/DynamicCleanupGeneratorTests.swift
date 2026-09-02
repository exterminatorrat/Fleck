import Foundation
import Testing

@testable import FleckApp

@Test func dynamicCleanupGeneratorPrefersAvailableFoundationWithoutLeasingGemma() async throws {
  let foundation = DynamicCleanupGeneratorProbe(result: "foundation")
  let gemma = DynamicCleanupGeneratorProbe(result: "gemma")
  let gate = GemmaCleanupLeaseGate()
  gate.enable(gemma)
  let generator = DynamicCleanupGenerator(
    foundationIsAvailable: { true },
    foundationGenerator: foundation,
    gemmaGate: gate
  )

  let session = try generator.start(dynamicCleanupRequest(), maximumOutputTokens: 24)
  let candidate = try await session.result()

  #expect(candidate.cleaned == "foundation")
  #expect(foundation.startCount == 1)
  #expect(gemma.startCount == 0)
  await gate.disableAndWait()
}

@Test func dynamicCleanupGeneratorUsesEnabledGemmaOnlyWhenFoundationIsUnavailable() async throws {
  let foundation = DynamicCleanupGeneratorProbe(result: "foundation")
  let gemma = DynamicCleanupGeneratorProbe(result: "gemma")
  let gate = GemmaCleanupLeaseGate()
  gate.enable(gemma)
  let generator = DynamicCleanupGenerator(
    foundationIsAvailable: { false },
    foundationGenerator: foundation,
    gemmaGate: gate
  )

  let session = try generator.start(dynamicCleanupRequest(), maximumOutputTokens: 24)
  let candidate = try await session.result()

  #expect(candidate.cleaned == "gemma")
  #expect(foundation.startCount == 0)
  #expect(gemma.startCount == 1)
  await gate.disableAndWait()
}

@Test func dynamicCleanupGeneratorThrowsWhenNoCleanupModelIsAvailable() throws {
  let gate = GemmaCleanupLeaseGate()
  let generator = DynamicCleanupGenerator(
    foundationIsAvailable: { false },
    foundationGenerator: DynamicCleanupGeneratorProbe(result: "foundation"),
    gemmaGate: gate
  )

  #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
    _ = try generator.start(dynamicCleanupRequest(), maximumOutputTokens: 24)
  }
}

@Test func dynamicCleanupDisablePreventsNewLeasesImmediately() throws {
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(result: "gemma"))
  let generator = dynamicGemmaOnlyGenerator(gate: gate)

  gate.disable()

  #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
    _ = try generator.start(dynamicCleanupRequest(), maximumOutputTokens: 24)
  }
}

@Test func dynamicCleanupDisableAndWaitAlsoDisablesAnIdleGate() async throws {
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(result: "gemma"))
  let generator = dynamicGemmaOnlyGenerator(gate: gate)

  await gate.disableAndWait()

  #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
    _ = try generator.start(dynamicCleanupRequest(), maximumOutputTokens: 24)
  }
}

@Test func dynamicCleanupSuccessWaitsForAcknowledgementBeforeReleasingLease() async throws {
  let acknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let innerSession = DynamicCleanupSessionProbe(
    outcome: .success(.init(cleaned: "gemma")),
    acknowledgement: acknowledgement
  )
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(session: innerSession))
  let session = try dynamicGemmaOnlyGenerator(gate: gate).start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )

  let result = Task { try await session.result() }
  await acknowledgement.waitUntilStarted()
  let resultFinished = DynamicCleanupCompletionProbe()
  let observedResult = Task {
    let value = try await result.value
    resultFinished.finish()
    return value
  }
  gate.disable()
  let drained = DynamicCleanupCompletionProbe()
  let drain = Task {
    await gate.disableAndWait()
    drained.finish()
  }
  await Task.yield()

  #expect(!resultFinished.isFinished)
  #expect(!drained.isFinished)
  acknowledgement.release()

  #expect(try await observedResult.value.cleaned == "gemma")
  await drain.value
  #expect(drained.isFinished)
  #expect(innerSession.acknowledgementCount == 1)
}

@Test func dynamicCleanupFailureWaitsForAcknowledgementBeforeRethrowing() async throws {
  let acknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let innerSession = DynamicCleanupSessionProbe(
    outcome: .failure(.generationFailed),
    acknowledgement: acknowledgement
  )
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(session: innerSession))
  let session = try dynamicGemmaOnlyGenerator(gate: gate).start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )

  let result = Task { try await session.result() }
  await acknowledgement.waitUntilStarted()
  gate.disable()
  let drained = DynamicCleanupCompletionProbe()
  let drain = Task {
    await gate.disableAndWait()
    drained.finish()
  }
  await Task.yield()

  #expect(!drained.isFinished)
  acknowledgement.release()

  await #expect(throws: CleanupGenerationError.generationFailed) {
    try await result.value
  }
  await drain.value
  #expect(drained.isFinished)
}

@Test func dynamicCleanupCancellationAndForceHoldLeaseUntilAcknowledged() async throws {
  for action in DynamicCleanupTerminationAction.allCases {
    let acknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
    let innerSession = DynamicCleanupSessionProbe(
      outcome: .failure(.requestCancelled),
      acknowledgement: acknowledgement
    )
    let gate = GemmaCleanupLeaseGate()
    gate.enable(DynamicCleanupGeneratorProbe(session: innerSession))
    let session = try dynamicGemmaOnlyGenerator(gate: gate).start(
      dynamicCleanupRequest(),
      maximumOutputTokens: 24
    )

    action.apply(to: session)
    await acknowledgement.waitUntilStarted()
    gate.disable()
    let drained = DynamicCleanupCompletionProbe()
    let drain = Task {
      await gate.disableAndWait()
      drained.finish()
    }
    await Task.yield()

    #expect(!drained.isFinished)
    acknowledgement.release()

    await session.acknowledgement()
    await drain.value
    #expect(drained.isFinished)
    #expect(innerSession.acknowledgementCount == 1)
  }
}

@Test func dynamicCleanupCallerCancellationStillWaitsForAcknowledgement() async throws {
  let acknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let innerSession = DynamicCleanupSessionProbe(
    outcome: .waitForCallerCancellation,
    acknowledgement: acknowledgement
  )
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(session: innerSession))
  let session = try dynamicGemmaOnlyGenerator(gate: gate).start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )
  let result = Task { try await session.result() }
  await innerSession.waitUntilResultStarted()

  result.cancel()
  await acknowledgement.waitUntilStarted()
  gate.disable()
  let drained = DynamicCleanupCompletionProbe()
  let drain = Task {
    await gate.disableAndWait()
    drained.finish()
  }
  await Task.yield()

  #expect(!drained.isFinished)
  acknowledgement.release()

  await #expect(throws: CancellationError.self) {
    try await result.value
  }
  await drain.value
  #expect(drained.isFinished)
}

@Test func dynamicCleanupStartFailureReleasesItsLease() async {
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(startError: .generationFailed))
  let generator = dynamicGemmaOnlyGenerator(gate: gate)

  #expect(throws: CleanupGenerationError.generationFailed) {
    _ = try generator.start(dynamicCleanupRequest(), maximumOutputTokens: 24)
  }

  await gate.disableAndWait()
}

@Test func dynamicCleanupConcurrentTerminalCallsReleaseExactlyOnce() async throws {
  let acknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let innerSession = DynamicCleanupSessionProbe(
    outcome: .success(.init(cleaned: "gemma")),
    acknowledgement: acknowledgement
  )
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(session: innerSession))
  let session = try dynamicGemmaOnlyGenerator(gate: gate).start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )

  let firstResult = Task { try await session.result() }
  let secondResult = Task { try await session.result() }
  let firstAcknowledgement = Task { await session.acknowledgement() }
  let secondAcknowledgement = Task { await session.acknowledgement() }
  session.requestCancellation()
  session.requestCancellation()
  session.forceTerminate()
  session.forceTerminate()
  await acknowledgement.waitUntilStarted()
  gate.disable()
  let drain = Task { await gate.disableAndWait() }

  acknowledgement.release()

  _ = try await firstResult.value
  _ = try await secondResult.value
  await firstAcknowledgement.value
  await secondAcknowledgement.value
  await drain.value
  #expect(innerSession.acknowledgementCount == 1)
  #expect(innerSession.cancellationCount == 1)
  #expect(innerSession.forceCount == 1)

  gate.enable(DynamicCleanupGeneratorProbe(result: "replacement"))
  let replacement = try dynamicGemmaOnlyGenerator(gate: gate).start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )
  #expect(try await replacement.result().cleaned == "replacement")
  await gate.disableAndWait()
}

@Test func dynamicCleanupGeneratorReplacementKeepsOlderLeaseAccounting() async throws {
  let oldAcknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let oldSession = DynamicCleanupSessionProbe(
    outcome: .success(.init(cleaned: "old")),
    acknowledgement: oldAcknowledgement
  )
  let oldGenerator = DynamicCleanupGeneratorProbe(session: oldSession)
  let replacementGenerator = DynamicCleanupGeneratorProbe(result: "new")
  let gate = GemmaCleanupLeaseGate()
  gate.enable(oldGenerator)
  let generator = dynamicGemmaOnlyGenerator(gate: gate)
  let leasedOldSession = try generator.start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )
  let oldResult = Task { try await leasedOldSession.result() }
  await oldAcknowledgement.waitUntilStarted()

  gate.enable(replacementGenerator)
  let replacementSession = try generator.start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )
  #expect(try await replacementSession.result().cleaned == "new")
  #expect(oldGenerator.startCount == 1)
  #expect(replacementGenerator.startCount == 1)

  gate.disable()
  let drained = DynamicCleanupCompletionProbe()
  let drain = Task {
    await gate.disableAndWait()
    drained.finish()
  }
  await Task.yield()
  #expect(!drained.isFinished)

  oldAcknowledgement.release()
  #expect(try await oldResult.value.cleaned == "old")
  await drain.value
  #expect(drained.isFinished)
}

@Test func dynamicCleanupOnlyEnableLeavesRouteUnavailable() throws {
  let gate = GemmaCleanupLeaseGate()
  gate.enable(DynamicCleanupGeneratorProbe(result: "gemma"))

  #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
    _ = try gate.startRoute(
      baseline: "send the report",
      plainPrompt: "route prompt",
      deadline: ContinuousClock().now.advanced(by: .seconds(1)),
      maximumOutputTokens: 24
    )
  }
}

@Test func dynamicCleanupAndRouteShareOneDrainGate() async throws {
  let cleanupAcknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let routeAcknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let cleanupSession = DynamicCleanupSessionProbe(
    outcome: .failure(.requestCancelled),
    acknowledgement: cleanupAcknowledgement
  )
  let routeSession = DynamicCleanupSessionProbe(
    outcome: .failure(.terminated),
    acknowledgement: routeAcknowledgement
  )
  let routeGenerator = DynamicRouteGeneratorProbe(
    cleanupSession: cleanupSession,
    routeSession: routeSession
  )
  let gate = GemmaCleanupLeaseGate()
  gate.enable(routeGenerator)
  let cleanup = try dynamicGemmaOnlyGenerator(gate: gate).start(
    dynamicCleanupRequest(),
    maximumOutputTokens: 24
  )
  let route = try gate.startRoute(
    baseline: "send the report",
    plainPrompt: "route prompt",
    deadline: ContinuousClock().now.advanced(by: .seconds(1)),
    maximumOutputTokens: 24
  )

  cleanup.requestCancellation()
  route.forceTerminate()
  await cleanupAcknowledgement.waitUntilStarted()
  await routeAcknowledgement.waitUntilStarted()
  let drained = DynamicCleanupCompletionProbe()
  let drain = Task {
    await gate.disableAndWait()
    drained.finish()
  }
  await Task.yield()
  #expect(!drained.isFinished)

  cleanupAcknowledgement.release()
  await cleanup.acknowledgement()
  await Task.yield()
  #expect(!drained.isFinished)

  routeAcknowledgement.release()
  await route.acknowledgement()
  await drain.value
  #expect(drained.isFinished)
  #expect(cleanupSession.acknowledgementCount == 1)
  #expect(routeSession.acknowledgementCount == 1)
  #expect(cleanupSession.cancellationCount == 1)
  #expect(routeSession.forceCount == 1)
}

@Test func dynamicRouteConcurrentTerminalCallsReleaseExactlyOnce() async throws {
  let acknowledgement = DynamicCleanupAcknowledgementGate(blocked: true)
  let routeSession = DynamicCleanupSessionProbe(
    outcome: .success(.init(cleaned: "high:destination")),
    acknowledgement: acknowledgement
  )
  let routeGenerator = DynamicRouteGeneratorProbe(
    cleanupSession: DynamicCleanupSessionProbe(
      outcome: .success(.init(cleaned: "cleanup")),
      acknowledgement: DynamicCleanupAcknowledgementGate(blocked: false)
    ),
    routeSession: routeSession
  )
  let gate = GemmaCleanupLeaseGate()
  gate.enable(routeGenerator)
  let route = try gate.startRoute(
    baseline: "send the report",
    plainPrompt: "route prompt",
    deadline: ContinuousClock().now.advanced(by: .seconds(1)),
    maximumOutputTokens: 24
  )

  let result = Task { try await route.result() }
  let firstAcknowledgement = Task { await route.acknowledgement() }
  let secondAcknowledgement = Task { await route.acknowledgement() }
  route.requestCancellation()
  route.requestCancellation()
  route.forceTerminate()
  route.forceTerminate()
  await acknowledgement.waitUntilStarted()
  let drain = Task { await gate.disableAndWait() }

  acknowledgement.release()

  #expect(try await result.value.cleaned == "high:destination")
  await firstAcknowledgement.value
  await secondAcknowledgement.value
  await drain.value
  #expect(routeSession.acknowledgementCount == 1)
  #expect(routeSession.cancellationCount == 1)
  #expect(routeSession.forceCount == 1)
}

@Test func dynamicCleanupUnavailableGateFallsBackThroughIncrementalCleaner() async throws {
  let now = ContinuousClock().now
  let generator = DynamicCleanupGenerator(
    foundationIsAvailable: { false },
    foundationGenerator: DynamicCleanupGeneratorProbe(result: "foundation"),
    gemmaGate: GemmaCleanupLeaseGate()
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: .live
  )

  let decision = try await cleaner.clean(.init(
    baseline: "keep the dictionary baseline",
    protectedForms: ["dictionary"],
    replacements: 1,
    deadline: now.advanced(by: .seconds(1))
  ))

  #expect(decision == .baseline(reason: .generationFailed))
}

private func dynamicGemmaOnlyGenerator(
  gate: GemmaCleanupLeaseGate
) -> DynamicCleanupGenerator {
  DynamicCleanupGenerator(
    foundationIsAvailable: { false },
    foundationGenerator: DynamicCleanupGeneratorProbe(result: "foundation"),
    gemmaGate: gate
  )
}

private func dynamicCleanupRequest() -> IncrementalCleanupRequest {
  IncrementalCleanupRequest(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now.advanced(by: .seconds(1))
  )
}

private enum DynamicCleanupTerminationAction: CaseIterable {
  case cancellation
  case force

  func apply(to session: any CleanupGenerationSession) {
    switch self {
    case .cancellation: session.requestCancellation()
    case .force: session.forceTerminate()
    }
  }
}

private final class DynamicCleanupGeneratorProbe: BoundedCleanupGenerating, @unchecked Sendable {
  private let lock = NSLock()
  private let session: DynamicCleanupSessionProbe
  private let startError: CleanupGenerationError?
  private var startCountStorage = 0

  init(result: String) {
    session = DynamicCleanupSessionProbe(
      outcome: .success(.init(cleaned: result)),
      acknowledgement: DynamicCleanupAcknowledgementGate(blocked: false)
    )
    startError = nil
  }

  init(session: DynamicCleanupSessionProbe) {
    self.session = session
    startError = nil
  }

  init(startError: CleanupGenerationError) {
    session = DynamicCleanupSessionProbe(
      outcome: .failure(startError),
      acknowledgement: DynamicCleanupAcknowledgementGate(blocked: false)
    )
    self.startError = startError
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    _ = request
    _ = maximumOutputTokens
    lock.withLock { startCountStorage += 1 }
    if let startError { throw startError }
    return session
  }

  var startCount: Int {
    lock.withLock { startCountStorage }
  }
}

private struct DynamicRouteGeneratorProbe:
  BoundedCleanupGenerating,
  GemmaRouteGenerating
{
  let cleanupSession: DynamicCleanupSessionProbe
  let routeSession: DynamicCleanupSessionProbe

  func start(
    _: IncrementalCleanupRequest,
    maximumOutputTokens _: Int
  ) throws -> any CleanupGenerationSession {
    return cleanupSession
  }

  func startRoute(
    baseline _: String,
    plainPrompt _: String,
    deadline _: ContinuousClock.Instant,
    maximumOutputTokens _: Int
  ) throws -> any CleanupGenerationSession {
    return routeSession
  }
}

private final class DynamicCleanupSessionProbe: CleanupGenerationSession, @unchecked Sendable {
  enum Outcome: Sendable {
    case success(GeneratedCleanupCandidate)
    case failure(CleanupGenerationError)
    case waitForCallerCancellation
  }

  private let lock = NSLock()
  private let outcome: Outcome
  private let acknowledgementGate: DynamicCleanupAcknowledgementGate
  private var resultStartedStorage = false
  private var acknowledgementCountStorage = 0
  private var cancellationCountStorage = 0
  private var forceCountStorage = 0

  init(
    outcome: Outcome,
    acknowledgement: DynamicCleanupAcknowledgementGate
  ) {
    self.outcome = outcome
    self.acknowledgementGate = acknowledgement
  }

  func result() async throws -> GeneratedCleanupCandidate {
    lock.withLock { resultStartedStorage = true }
    switch outcome {
    case .success(let candidate): return candidate
    case .failure(let error): throw error
    case .waitForCallerCancellation:
      while true {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func acknowledgement() async {
    lock.withLock { acknowledgementCountStorage += 1 }
    await acknowledgementGate.wait()
  }

  func requestCancellation() {
    lock.withLock { cancellationCountStorage += 1 }
  }

  func forceTerminate() {
    lock.withLock { forceCountStorage += 1 }
  }

  func waitUntilResultStarted() async {
    while !lock.withLock({ resultStartedStorage }) { await Task.yield() }
  }

  var acknowledgementCount: Int {
    lock.withLock { acknowledgementCountStorage }
  }

  var cancellationCount: Int {
    lock.withLock { cancellationCountStorage }
  }

  var forceCount: Int {
    lock.withLock { forceCountStorage }
  }
}

private final class DynamicCleanupAcknowledgementGate: @unchecked Sendable {
  private let lock = NSLock()
  private var blocked: Bool
  private var started = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  init(blocked: Bool) {
    self.blocked = blocked
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      started = true
      if blocked {
        continuations.append(continuation)
        lock.unlock()
      } else {
        lock.unlock()
        continuation.resume()
      }
    }
  }

  func waitUntilStarted() async {
    while !lock.withLock({ started }) { await Task.yield() }
  }

  func release() {
    lock.lock()
    blocked = false
    let continuations = self.continuations
    self.continuations = []
    lock.unlock()
    continuations.forEach { $0.resume() }
  }
}

private final class DynamicCleanupCompletionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false

  func finish() {
    lock.withLock { finished = true }
  }

  var isFinished: Bool {
    lock.withLock { finished }
  }
}
