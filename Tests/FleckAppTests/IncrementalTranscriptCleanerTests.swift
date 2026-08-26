import Foundation
import Testing

@testable import FleckApp

@Test func cleanerUsesOneRequestAndReturnsTheExactBaselineWhenValidationRejects() async throws {
  let generator = CleanupGeneratorProbe(result: "Send 10 files.")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )
  let request = IncrementalCleanupRequest(
    baseline: "Send 20 files.",
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now.advanced(by: .seconds(1))
  )

  let decision = try await cleaner.clean(request)

  #expect(decision == .baseline(reason: .validationRejected))
  #expect(generator.startCount == 1)
  #expect(generator.resultCount == 1)
}

@Test func unchangedModelOutputUsesTheValidatedDeterministicFillerFallback() async throws {
  let baseline = "I feel like the main things um that we really need to work on for my um chemistry is the lab report."
  let expected = "I feel like the main things that we really need to work on for my chemistry is the lab report."
  let generator = CleanupGeneratorProbe(result: baseline)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(expected))
}

@Test func cleanerPublishesTheUnpunctuatedGemmaSecondTranscriptWithoutStartingGenerator() async throws {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let expected = "I'm not really sure how this works, but can we make it so that it's more technical."
  let generator = CleanupGeneratorProbe(result: baseline)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(expected))
  #expect(generator.startCount == 0)
  #expect(generator.resultCount == 0)
}

@Test func cleanerPublishesThePunctuationSeparatedDeterministicBaselineWithoutStartingGenerator() async throws {
  let baseline = "so, um, I'm not really sure how this works. But, like, can we make it so that's more technical?"
  let expected = "so, I'm not really sure how this works. But can we make it so that's more technical?"
  let originalRequest = request(baseline)
  let generator = CleanupGeneratorProbe(result: expected)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(originalRequest)

  #expect(decision == .accepted(expected))
  #expect(generator.startCount == 0)
  #expect(generator.resultCount == 0)
}

@Test func cleanerPublishesTheDeterministicBaselineWithoutStartingUnsafeGemma() async throws {
  let baseline = "so, um, I'm not really sure how this works. But, like, can we make it so that's more technical?"
  let expected = "so, I'm not really sure how this works. But can we make it so that's more technical?"
  let unsafeCandidate = "I'm not really sure how this works. But, like, can we make it so that's more technical?"
  let originalRequest = request(baseline)
  let generator = CleanupGeneratorProbe(result: unsafeCandidate)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(originalRequest)

  #expect(decision == .accepted(expected))
  #expect(generator.startCount == 0)
  #expect(generator.resultCount == 0)
}

@Test func cleanerPublishesDeterministicFillerCleanupInsteadOfStartingGemma() async throws {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let expected = "I'm not really sure how this works, but can we make it so that it's more technical."
  let generator = CleanupGeneratorProbe(result: "unreachable")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(expected))
  #expect(generator.startCount == 0)
  #expect(generator.resultCount == 0)
}

@Test func cleanerPublishesAnUnpunctuatedDeterministicFillerBaselineWithoutStartingGenerator() async throws {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let deterministicBaseline = "I'm not really sure how this works, but can we make it so that it's more technical"
  let candidate = deterministicBaseline + "."
  let originalRequest = IncrementalCleanupRequest(
    baseline: baseline,
    protectedForms: ["technical"],
    replacements: 2,
    deadline: ContinuousClock().now.advanced(by: .seconds(1))
  )
  let generator = CleanupGeneratorProbe(result: deterministicBaseline)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(originalRequest)

  #expect(decision == .accepted(candidate))
  #expect(generator.startCount == 0)
  #expect(generator.resultCount == 0)
}

@Test func cleanerValidatesAFormattedCandidateAgainstTheOriginalResolution() async throws {
  let baseline = "um, Alice sends the report, uh"
  let candidate = "alice sends the report."
  let generator = CleanupGeneratorProbe(result: candidate)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(candidate))
  #expect(generator.startCount == 1)
  #expect(generator.lastRequest?.baseline == "Alice sends the report,")
}

@Test func cleanerAppendsOnePeriodWhenTheGeneratedCandidateLacksTerminalPunctuation() async throws {
  let generator = CleanupGeneratorProbe(result: "Send the report")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request("Send the report"))

  #expect(decision == .accepted("Send the report."))
}

@Test func cleanerPreservesExistingQuestionAndExclamationTerminalPunctuation() async throws {
  for candidate in ["Can we send the report?", "Send the report!"] {
    let generator = CleanupGeneratorProbe(result: candidate)
    let cleaner = IncrementalTranscriptCleaner(
      generator: generator,
      clock: TestCleanupClock.immediate
    )

    let decision = try await cleaner.clean(request(candidate))

    #expect(decision == .accepted(candidate))
  }
}

@Test func cleanerPublishesDeterministicCleanupBeforeConsideringLexicalGemmaChanges() async throws {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let deterministicBaseline = "I'm not really sure how this works, but can we make it so that it's more technical"
  let candidate = "I'm not really sure how this works, but can we make it so that it's more theoretical."
  let generator = CleanupGeneratorProbe(result: candidate)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(deterministicBaseline + "."))
  #expect(decision != .accepted(candidate))
  #expect(generator.startCount == 0)
  #expect(generator.resultCount == 0)
}

@Test func cleanerForwardsTheBoundedOutputBudgetFromTheCleanRequest() async throws {
  let baseline = "send the report"
  let generator = CleanupGeneratorProbe(result: "Send the report.")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted("Send the report."))
  #expect(generator.startCount == 1)
  #expect(
    generator.lastMaximumOutputTokens == CleanupLexeme.tokenCount(baseline) + 32
  )
}

@Test func cleanerReturnsBaselineForAnInputOverTheTargetBound() async throws {
  let generator = CleanupGeneratorProbe(result: "unused")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(.init(
    baseline: String(repeating: "word ", count: 81),
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now.advanced(by: .seconds(1))
  ))

  #expect(decision == .baseline(reason: .targetTooLarge))
  #expect(generator.startCount == 0)
}

@Test func cleanerReturnsBaselineWhenTheDeadlineHasExpired() async throws {
  let generator = CleanupGeneratorProbe(result: "unused")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(.init(
    baseline: "Send the report",
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now
  ))

  #expect(decision == .baseline(reason: .deadlineExpired))
  #expect(generator.startCount == 0)
}

@Test func helperRequestCancellationReturnsTheExactBaseline() async throws {
  let session = CleanupGenerationSessionProbe(
    result: .failure(.requestCancelled)
  )
  let generator = CleanupGeneratorProbe(session: session)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.acknowledgementFirst()
  )

  let decision = try await cleaner.clean(request("send the report"))

  #expect(decision == .baseline(reason: .requestCancelled))
  #expect(session.requestCancellationCalled)
  #expect(session.requestCancellationCount == 1)
  #expect(session.acknowledgementFinished)
  #expect(session.forceTerminateCount == 0)
}

@Test func generationFailureReturnsTheExactBaseline() async throws {
  let generator = CleanupGeneratorProbe(startError: .generationFailed)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request("send the report"))

  #expect(decision == .baseline(reason: .generationFailed))
  #expect(generator.startCount == 1)
}

@Test func generationFailureUsesTheValidatedDeterministicFillerFallback() async throws {
  let baseline = "I feel like the main things um that we really need to work on for my um chemistry is the lab report."
  let expected = "I feel like the main things that we really need to work on for my chemistry is the lab report."
  let generator = CleanupGeneratorProbe(startError: .generationFailed)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(expected))
}

@Test func deterministicFillerCleanupAvoidsGemmaGenerationFailure() async throws {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let expected = "I'm not really sure how this works, but can we make it so that it's more technical."
  let generator = CleanupGeneratorProbe(startError: .generationFailed)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request(baseline))

  #expect(decision == .accepted(expected))
  #expect(generator.startCount == 0)
}

@Test func generationFailureFromTheSessionReturnsTheExactBaseline() async throws {
  let session = CleanupGenerationSessionProbe(
    result: .failure(.generationFailed)
  )
  let generator = CleanupGeneratorProbe(session: session)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request("send the report"))

  #expect(decision == .baseline(reason: .generationFailed))
  #expect(generator.startCount == 1)
  #expect(session.resultCount == 1)
}

@Test func emptyGeneratedOutputReturnsTheExactBaseline() async throws {
  let generator = CleanupGeneratorProbe(result: " \n\t")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request("send the report"))

  #expect(decision == .baseline(reason: .malformedOutput))
}

@Test func generatedOutputOverTheBoundReturnsTheExactBaseline() async throws {
  let generator = CleanupGeneratorProbe(
    result: String(repeating: "word ", count: 36)
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let decision = try await cleaner.clean(request("send the report"))

  #expect(decision == .baseline(reason: .outputTooLarge))
}

@Test func generatorStartIsSynchronousAndOnlyCapturesRequestMetadata() throws {
  let generator = CleanupGeneratorProbe(result: "Send the report.")
  let expectedRequest = request("send the report")

  let session = try generator.start(
    expectedRequest,
    maximumOutputTokens: 35
  )

  #expect(generator.startCount == 1)
  #expect(generator.lastRequest == expectedRequest)
  #expect(generator.lastMaximumOutputTokens == 35)
  #expect(session is CleanupGenerationSessionProbe)
}

@Test func deadlineIsRecheckedBeforePublishingAWinningCandidate() async throws {
  let now = TestCleanupClock.fixedInstant
  let deadline = now.advanced(by: .seconds(1))
  let generator = CleanupGeneratorProbe(result: "Send the report.")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.sequence([now, now, deadline])
  )

  let decision = try await cleaner.clean(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  ))

  #expect(decision == .baseline(reason: .deadlineExpired))
}

@Test func deadlineExpiryAfterStartCancelsAndAcknowledgesBeforeTheRace() async throws {
  let now = TestCleanupClock.fixedInstant
  let deadline = now.advanced(by: .seconds(1))
  let session = CleanupGenerationSessionProbe(
    result: .success(.init(cleaned: "Send the report.")),
    waitsForCancellation: true
  )
  let generator = CleanupGeneratorProbe(session: session)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.sequence([now, deadline])
  )

  let decision = try await cleaner.clean(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  ))

  #expect(decision == .baseline(reason: .deadlineExpired))
  #expect(generator.startCount == 1)
  #expect(session.resultCount == 0)
  #expect(session.requestCancellationCount == 1)
  #expect(session.acknowledgementCallCount == 1)
  #expect(session.acknowledgementFinished)
  #expect(session.forceTerminateCount == 0)
}

@Test func deadlineExpiryUsesTheValidatedDeterministicFillerFallback() async throws {
  let now = TestCleanupClock.fixedInstant
  let deadline = now.advanced(by: .seconds(1))
  let baseline = "I feel like the main things um that we really need to work on for my um chemistry is the lab report."
  let expected = "I feel like the main things that we really need to work on for my chemistry is the lab report."
  let session = CleanupGenerationSessionProbe(
    result: .success(.init(cleaned: baseline)),
    waitsForCancellation: true
  )
  let generator = CleanupGeneratorProbe(session: session)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.sequence([now, deadline])
  )

  let decision = try await cleaner.clean(.init(
    baseline: baseline,
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  ))

  #expect(decision == .accepted(expected))
  #expect(
    generator.lastRequest == .init(
      baseline: expected,
      protectedForms: [],
      replacements: 0,
      deadline: deadline
    )
  )
  #expect(session.requestCancellationCount == 1)
  #expect(session.acknowledgementFinished)
}

@Test func deadlineExpiryCleansTheGemmaSecondTranscript() async throws {
  let now = TestCleanupClock.fixedInstant
  let deadline = now.advanced(by: .seconds(1))
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let expected = "I'm not really sure how this works, but can we make it so that it's more technical"
  let session = CleanupGenerationSessionProbe(
    result: .success(.init(cleaned: baseline)),
    waitsForCancellation: true
  )
  let generator = CleanupGeneratorProbe(session: session)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.sequence([now, deadline])
  )

  let decision = try await cleaner.clean(.init(
    baseline: baseline,
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  ))

  #expect(decision == .accepted(expected))
  #expect(session.requestCancellationCount == 1)
  #expect(session.acknowledgementFinished)
}

@Test func callerCancellationThrowsAndMakesLateCandidateUnusable() async {
  let generator = CleanupGeneratorProbe(
    result: "Send the report.",
    waitsForCancellation: true
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.bounded(milliseconds: 1)
  )
  let task = Task {
    try await cleaner.clean(request("send the report"))
  }
  await generator.waitUntilStarted()
  task.cancel()

  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(generator.forceTerminateCount == 1)
  #expect(generator.lateCandidateWasIgnored)
  #expect(generator.acknowledgementFinished)
}

@Test func cooperativeCallerCancellationRequestsOneAcknowledgementAndNoForce() async {
  let cancellationProbe = CancellationStateProbe()
  let session = CleanupGenerationSessionProbe(
    result: .success(.init(cleaned: "Send the report.")),
    waitsForCancellation: true,
    acknowledgementGate: {
      await cancellationProbe.waitUntilSleepForStarted()
    }
  )
  let generator = CleanupGeneratorProbe(session: session)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.acknowledgementFirst(
      onSleepStart: cancellationProbe.record
    )
  )
  let task = Task {
    try await cleaner.clean(request("send the report"))
  }
  await generator.waitUntilStarted()
  task.cancel()

  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(cancellationProbe.sleepForStarted)
  #expect(cancellationProbe.startedWhileCancelled == false)
  #expect(session.requestCancellationCount == 1)
  #expect(session.acknowledgementCallCount == 1)
  #expect(session.forceTerminateCount == 0)
  #expect(session.acknowledgementFinished)
}

@Test func nonCooperativeSessionIsForcedWithinTheInjectedBudget() async throws {
  let now = TestCleanupClock.fixedInstant
  let session = CleanupGenerationSessionProbe(
    result: .success(.init(cleaned: "late")),
    ignoresCancellation: true
  )
  let generator = CleanupGeneratorProbe(session: session)
  let recorder = DurationRecorder()
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.fixed(now: now, onSleep: recorder.append),
    cancellationBudget: .milliseconds(25)
  )

  let decision = try await cleaner.clean(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: now.advanced(by: .seconds(1))
  ))

  #expect(decision == .baseline(reason: .deadlineExpired))
  #expect(session.forceTerminateCalled)
  #expect(session.resultFinished)
  #expect(session.acknowledgementFinished)
  #expect(recorder.values == [.milliseconds(25)])
}

private func request(
  _ baseline: String,
  deadline: ContinuousClock.Instant = ContinuousClock().now.advanced(by: .seconds(1))
) -> IncrementalCleanupRequest {
  IncrementalCleanupRequest(
    baseline: baseline,
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  )
}

private enum TestCleanupClock {
  static let fixedInstant = ContinuousClock().now

  static let immediate = CleanupClock(
    now: { ContinuousClock().now },
    sleepUntil: { deadline in
      try await ContinuousClock().sleep(until: deadline)
    },
    sleepFor: { _ in }
  )

  static func acknowledgementFirst(
    onSleepStart: (@Sendable (Bool) -> Void)? = nil
  ) -> CleanupClock {
    CleanupClock(
      now: { ContinuousClock().now },
      sleepUntil: { deadline in
        try await ContinuousClock().sleep(until: deadline)
      },
      sleepFor: { _ in
        onSleepStart?(Task.isCancelled)
        while true {
          try Task.checkCancellation()
          await Task.yield()
        }
      }
    )
  }

  static func bounded(milliseconds: Int) -> CleanupClock {
    CleanupClock(
      now: { ContinuousClock().now },
      sleepUntil: { deadline in
        try await ContinuousClock().sleep(until: deadline)
      },
      sleepFor: { _ in }
    )
  }

  static func fixed(
    now: ContinuousClock.Instant,
    onSleep: @escaping @Sendable (Duration) -> Void
  ) -> CleanupClock {
    CleanupClock(
      now: { now },
      sleepUntil: { _ in },
      sleepFor: { duration in onSleep(duration) }
    )
  }

  static func sequence(_ values: [ContinuousClock.Instant]) -> CleanupClock {
    let sequence = InstantSequence(values)
    return CleanupClock(
      now: { sequence.next() },
      sleepUntil: { deadline in
        try await ContinuousClock().sleep(until: deadline)
      },
      sleepFor: { _ in
        while true {
          try Task.checkCancellation()
          await Task.yield()
        }
      }
    )
  }
}

private final class CleanupGeneratorProbe: BoundedCleanupGenerating, @unchecked Sendable {
  private let lock = NSLock()
  private let session: CleanupGenerationSessionProbe
  private let startError: CleanupGenerationError?
  private var startCountStorage = 0
  private var lastRequestStorage: IncrementalCleanupRequest?
  private var lastMaximumOutputTokensStorage: Int?

  init(
    result: String,
    waitsForCancellation: Bool = false
  ) {
    self.session = CleanupGenerationSessionProbe(
      result: .success(.init(cleaned: result)),
      waitsForCancellation: waitsForCancellation,
      lateCandidateOnCancellation: waitsForCancellation
    )
    self.startError = nil
  }

  init(session: CleanupGenerationSessionProbe) {
    self.session = session
    self.startError = nil
  }

  init(startError: CleanupGenerationError) {
    self.session = CleanupGenerationSessionProbe(
      result: .failure(.generationFailed)
    )
    self.startError = startError
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    lock.testWithLock {
      startCountStorage += 1
      lastRequestStorage = request
      lastMaximumOutputTokensStorage = maximumOutputTokens
    }
    if let startError { throw startError }
    return session
  }

  var startCount: Int {
    lock.testWithLock { startCountStorage }
  }

  var lastRequest: IncrementalCleanupRequest? {
    lock.testWithLock { lastRequestStorage }
  }

  var lastMaximumOutputTokens: Int? {
    lock.testWithLock { lastMaximumOutputTokensStorage }
  }

  var resultCount: Int { session.resultCount }
  var forceTerminateCount: Int { session.forceTerminateCount }
  var lateCandidateWasIgnored: Bool { session.lateCandidateWasIgnored }
  var acknowledgementFinished: Bool { session.acknowledgementFinished }

  func waitUntilStarted() async {
    await session.waitUntilStarted()
  }
}

private final class CleanupGenerationSessionProbe: CleanupGenerationSession, @unchecked Sendable {
  enum Outcome: Sendable {
    case success(GeneratedCleanupCandidate)
    case failure(CleanupGenerationError)
  }

  private let lock = NSLock()
  private let initialOutcome: Outcome
  private let waitsForCancellation: Bool
  private let ignoresCancellation: Bool
  private let lateCandidateOnCancellation: Bool
  private let acknowledgementGate: (@Sendable () async -> Void)?
  private var resultCountStorage = 0
  private var resultOutcomeStorage: Outcome?
  private var startedStorage = false
  private var resultFinishedStorage = false
  private var acknowledgementSignaledStorage = false
  private var acknowledgementFinishedStorage = false
  private var requestCancellationCalledStorage = false
  private var requestCancellationCountStorage = 0
  private var acknowledgementCallCountStorage = 0
  private var forceTerminateCalledStorage = false
  private var forceTerminateCountStorage = 0
  private var lateCandidateWasIgnoredStorage = false

  init(
    result: Result<GeneratedCleanupCandidate, CleanupGenerationError>,
    waitsForCancellation: Bool = false,
    ignoresCancellation: Bool = false,
    lateCandidateOnCancellation: Bool = false,
    acknowledgementGate: (@Sendable () async -> Void)? = nil
  ) {
    switch result {
    case .success(let candidate):
      self.initialOutcome = .success(candidate)
    case .failure(let error):
      self.initialOutcome = .failure(error)
    }
    self.waitsForCancellation = waitsForCancellation
    self.ignoresCancellation = ignoresCancellation
    self.lateCandidateOnCancellation = lateCandidateOnCancellation
    self.acknowledgementGate = acknowledgementGate
    self.resultOutcomeStorage = waitsForCancellation || ignoresCancellation ? nil : initialOutcome
  }

  func result() async throws -> GeneratedCleanupCandidate {
    lock.testWithLock {
      resultCountStorage += 1
      startedStorage = true
    }
    defer {
      lock.testWithLock { resultFinishedStorage = true }
    }

    while true {
      if let outcome = lock.testWithLock({ resultOutcomeStorage }) {
        return try outcome.asResult().get()
      }
      await Task.yield()
    }
  }

  func acknowledgement() async {
    lock.testWithLock { acknowledgementCallCountStorage += 1 }
    while !lock.testWithLock({ acknowledgementSignaledStorage }) {
      await Task.yield()
    }
    await acknowledgementGate?()
    lock.testWithLock { acknowledgementFinishedStorage = true }
  }

  func requestCancellation() {
    lock.testWithLock {
      requestCancellationCountStorage += 1
      guard !requestCancellationCalledStorage else { return }
      requestCancellationCalledStorage = true
      if ignoresCancellation { return }
      if waitsForCancellation {
        if lateCandidateOnCancellation {
          lateCandidateWasIgnoredStorage = true
          if case .success(let candidate) = initialOutcome {
            resultOutcomeStorage = .success(candidate)
          }
        } else {
          resultOutcomeStorage = .failure(.requestCancelled)
          acknowledgementSignaledStorage = true
        }
      } else {
        acknowledgementSignaledStorage = true
      }
    }
  }

  func forceTerminate() {
    lock.testWithLock {
      guard !forceTerminateCalledStorage else { return }
      forceTerminateCalledStorage = true
      forceTerminateCountStorage += 1
      if resultOutcomeStorage == nil {
        resultOutcomeStorage = .failure(.terminated)
      }
      acknowledgementSignaledStorage = true
    }
  }

  func waitUntilStarted() async {
    while !lock.testWithLock({ startedStorage }) {
      await Task.yield()
    }
  }

  var resultCount: Int {
    lock.testWithLock { resultCountStorage }
  }

  var resultFinished: Bool {
    lock.testWithLock { resultFinishedStorage }
  }

  var acknowledgementFinished: Bool {
    lock.testWithLock { acknowledgementFinishedStorage }
  }

  var requestCancellationCalled: Bool {
    lock.testWithLock { requestCancellationCalledStorage }
  }

  var requestCancellationCount: Int {
    lock.testWithLock { requestCancellationCountStorage }
  }

  var acknowledgementCallCount: Int {
    lock.testWithLock { acknowledgementCallCountStorage }
  }

  var forceTerminateCalled: Bool {
    lock.testWithLock { forceTerminateCalledStorage }
  }

  var forceTerminateCount: Int {
    lock.testWithLock { forceTerminateCountStorage }
  }

  var lateCandidateWasIgnored: Bool {
    lock.testWithLock { lateCandidateWasIgnoredStorage }
  }
}

private extension CleanupGenerationSessionProbe.Outcome {
  func asResult() -> Result<GeneratedCleanupCandidate, CleanupGenerationError> {
    switch self {
    case .success(let candidate): return .success(candidate)
    case .failure(let error): return .failure(error)
    }
  }
}

private final class DurationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var valuesStorage: [Duration] = []

  func append(_ value: Duration) {
    lock.testWithLock { valuesStorage.append(value) }
  }

  var values: [Duration] {
    lock.testWithLock { valuesStorage }
  }
}

private final class CancellationStateProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var sleepForStartedStorage = false
  private var startedWhileCancelledStorage: Bool?

  func record(_ isCancelled: Bool) {
    lock.testWithLock {
      sleepForStartedStorage = true
      startedWhileCancelledStorage = isCancelled
    }
  }

  func waitUntilSleepForStarted() async {
    while !sleepForStarted {
      await Task.yield()
    }
  }

  var sleepForStarted: Bool {
    lock.testWithLock { sleepForStartedStorage }
  }

  var startedWhileCancelled: Bool? {
    lock.testWithLock { startedWhileCancelledStorage }
  }
}

private final class InstantSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [ContinuousClock.Instant]
  private var index = 0

  init(_ values: [ContinuousClock.Instant]) {
    self.values = values
  }

  func next() -> ContinuousClock.Instant {
    lock.testWithLock {
      let value = values[min(index, values.count - 1)]
      index += 1
      return value
    }
  }
}

private extension NSLock {
  func testWithLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
