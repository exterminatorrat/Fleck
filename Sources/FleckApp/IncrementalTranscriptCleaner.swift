import Foundation
import FleckCore

struct IncrementalCleanupRequest: Equatable, Sendable {
  let baseline: String
  let protectedForms: [String]
  let replacements: Int
  let deadline: ContinuousClock.Instant
}

enum IncrementalCleanupFallbackReason: Equatable, Sendable {
  case targetTooLarge
  case deadlineExpired
  case requestCancelled
  case generationFailed
  case malformedOutput
  case outputTooLarge
  case validationRejected
}

enum IncrementalCleanupDecision: Equatable, Sendable {
  case accepted(String)
  case baseline(reason: IncrementalCleanupFallbackReason)
}

struct GeneratedCleanupCandidate: Equatable, Sendable {
  let cleaned: String
}

enum CleanupGenerationError: Error, Equatable, Sendable {
  case requestCancelled
  case terminated
  case generationFailed
}

struct CleanupClock: Sendable {
  let now: @Sendable () -> ContinuousClock.Instant
  let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
  let sleepFor: @Sendable (Duration) async throws -> Void

  static let live = Self(
    now: { ContinuousClock().now },
    sleepUntil: { try await ContinuousClock().sleep(until: $0) },
    sleepFor: { try await ContinuousClock().sleep(for: $0) }
  )
}

protocol CleanupGenerationSession: Sendable {
  func result() async throws -> GeneratedCleanupCandidate
  func acknowledgement() async
  func requestCancellation()
  func forceTerminate()
}

protocol BoundedCleanupGenerating: Sendable {
  // This synchronous call only constructs a request-specific session.
  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession
}

enum CleanupTerminationDisposition: Equatable, Sendable {
  case acknowledged
  case forcedTermination
}

actor IncrementalTranscriptCleaner {
  private let generator: any BoundedCleanupGenerating
  private let validator: FaithfulCleanupValidator
  private let clock: CleanupClock
  private let cancellationBudget: Duration

  init(
    generator: any BoundedCleanupGenerating,
    validator: FaithfulCleanupValidator = .init(),
    clock: CleanupClock,
    cancellationBudget: Duration = .milliseconds(250)
  ) {
    self.generator = generator
    self.validator = validator
    self.clock = clock
    self.cancellationBudget = cancellationBudget
  }

  func clean(_ request: IncrementalCleanupRequest) async throws -> IncrementalCleanupDecision {
    try Task.checkCancellation()
    let inputCount = CleanupLexeme.tokenCount(request.baseline)
    guard inputCount <= 80 else { return .baseline(reason: .targetTooLarge) }
    guard request.deadline > clock.now() else {
      return deterministicFallbackOrBaseline(for: request, reason: .deadlineExpired)
    }

    let resolution = PersonalDictionaryResolution(
      baseline: request.baseline,
      protectedForms: request.protectedForms,
      replacements: request.replacements
    )
    let deterministicFallback = validator.deterministicFillerFallback(
      against: resolution
    )
    if let deterministicFallback {
      let normalizedFallback = Self.addMissingTerminalPeriod(to: deterministicFallback)
      let fallbackHasSafeTerminal = deterministicFallback.last {
        !$0.isWhitespace
      }.map { character in
        character.isLetter
          || character.isNumber
          || [".", "!", "?", "。", "！", "？"].contains(character)
      } ?? false
      if fallbackHasSafeTerminal,
         CleanupLexeme.tokenCount(normalizedFallback) <= inputCount + 32 {
        let validation = validator.validate(
          candidate: normalizedFallback,
          against: resolution
        )
        if case .accepted(let text, _) = validation {
          try Task.checkCancellation()
          if request.deadline > clock.now() {
            try Task.checkCancellation()
            return .accepted(text)
          }
        }
      }
    }
    let generationRequest: IncrementalCleanupRequest
    if let deterministicFallback {
      generationRequest = .init(
        baseline: deterministicFallback,
        protectedForms: request.protectedForms,
        replacements: request.replacements,
        deadline: request.deadline
      )
    } else {
      generationRequest = request
    }

    let box = CleanupSessionBox()
    do {
      let session = try generator.start(
        generationRequest,
        maximumOutputTokens: inputCount + 32
      )
      box.install(session)
      try Task.checkCancellation()
      guard request.deadline > clock.now() else {
        box.requestCancellation()
        _ = await awaitTermination(
          session: session,
          box: box,
          clock: clock,
          cancellationBudget: cancellationBudget
        )
        try Task.checkCancellation()
        return deterministicFallbackOrBaseline(for: request, reason: .deadlineExpired)
      }

      let event = await withTaskCancellationHandler(operation: {
        await race(
          session: session,
          deadline: request.deadline,
          box: box,
          clock: clock,
          cancellationBudget: cancellationBudget
        )
      }, onCancel: {
        box.requestCancellation()
      })
      try Task.checkCancellation()

      switch event {
      case .deadline:
        return deterministicFallbackOrBaseline(for: request, reason: .deadlineExpired)
      case .requestCancelled, .terminated:
        return .baseline(reason: .requestCancelled)
      case .callerCancelled:
        throw CancellationError()
      case .generationFailed:
        return deterministicFallbackOrBaseline(for: request, reason: .generationFailed)
      case .candidate(let candidate):
        guard request.deadline > clock.now() else {
          box.requestCancellation()
          _ = await awaitTermination(
            session: session,
            box: box,
            clock: clock,
            cancellationBudget: cancellationBudget
          )
          try Task.checkCancellation()
          return deterministicFallbackOrBaseline(for: request, reason: .deadlineExpired)
        }
        guard !candidate.cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return deterministicFallbackOrBaseline(for: request, reason: .malformedOutput)
        }
        let normalizedCandidate = Self.addMissingTerminalPeriod(to: candidate.cleaned)
        guard CleanupLexeme.tokenCount(normalizedCandidate) <= inputCount + 32 else {
          return deterministicFallbackOrBaseline(for: request, reason: .outputTooLarge)
        }
        let validation = validator.validate(candidate: normalizedCandidate, against: resolution)
        try Task.checkCancellation()
        switch validation {
        case .accepted(let text, _):
          if candidate.cleaned == request.baseline,
             let fallback = deterministicFallback {
            return .accepted(fallback)
          }
          return .accepted(text)
        case .rejected:
          return deterministicFallbackOrBaseline(for: request, reason: .validationRejected)
        }
      }
    } catch is CancellationError {
      box.requestCancellation()
      if let session = box.currentSession() {
        _ = await awaitTermination(
          session: session,
          box: box,
          clock: clock,
          cancellationBudget: cancellationBudget
        )
      }
      throw CancellationError()
    } catch {
      do {
        try Task.checkCancellation()
      } catch is CancellationError {
        box.requestCancellation()
        if let session = box.currentSession() {
          _ = await awaitTermination(
            session: session,
            box: box,
            clock: clock,
            cancellationBudget: cancellationBudget
          )
        }
        throw CancellationError()
      }
      return deterministicFallbackOrBaseline(for: request, reason: .generationFailed)
    }
  }

  private func deterministicFallbackOrBaseline(
    for request: IncrementalCleanupRequest,
    reason: IncrementalCleanupFallbackReason
  ) -> IncrementalCleanupDecision {
    if let fallback = deterministicFillerFallback(for: request) {
      return .accepted(fallback)
    }
    return .baseline(reason: reason)
  }

  private func deterministicFillerFallback(
    for request: IncrementalCleanupRequest
  ) -> String? {
    validator.deterministicFillerFallback(
      against: PersonalDictionaryResolution(
        baseline: request.baseline,
        protectedForms: request.protectedForms,
        replacements: request.replacements
      )
    )
  }

  private static func addMissingTerminalPeriod(to candidate: String) -> String {
    guard let lastNonWhitespaceIndex = candidate.lastIndex(where: { !$0.isWhitespace }) else {
      return candidate
    }
    switch candidate[lastNonWhitespaceIndex] {
    case ".", "!", "?", "。", "！", "？":
      return candidate
    default:
      let insertionIndex = candidate.index(after: lastNonWhitespaceIndex)
      return String(candidate[..<insertionIndex]) + "." + String(candidate[insertionIndex...])
    }
  }
}

private final class CleanupSessionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var session: (any CleanupGenerationSession)?
  private var cancellationRequested = false
  private var forceRequested = false
  private var terminationDisposition: CleanupTerminationDisposition?

  func install(_ session: any CleanupGenerationSession) {
    let actions = lock.withLock {
      self.session = session
      return (cancellationRequested, forceRequested)
    }
    if actions.0 { session.requestCancellation() }
    if actions.1 { session.forceTerminate() }
  }

  func currentSession() -> (any CleanupGenerationSession)? {
    lock.withLock { session }
  }

  func requestCancellation() {
    let session = lock.withLock { () -> (any CleanupGenerationSession)? in
      guard !cancellationRequested else { return nil }
      cancellationRequested = true
      return self.session
    }
    session?.requestCancellation()
  }

  func forceTerminate() {
    let session = lock.withLock { () -> (any CleanupGenerationSession)? in
      guard !forceRequested else { return nil }
      forceRequested = true
      return self.session
    }
    session?.forceTerminate()
  }

  func forceTerminationRequested() -> Bool {
    lock.withLock { forceRequested }
  }

  func completedTermination() -> CleanupTerminationDisposition? {
    lock.withLock { terminationDisposition }
  }

  func recordTermination(
    _ disposition: CleanupTerminationDisposition
  ) -> CleanupTerminationDisposition {
    lock.withLock {
      if let terminationDisposition { return terminationDisposition }
      terminationDisposition = disposition
      return disposition
    }
  }
}

private enum CleanupRaceEvent: Sendable {
  case candidate(GeneratedCleanupCandidate)
  case deadline
  case requestCancelled
  case terminated
  case generationFailed
  case callerCancelled
}

private enum CleanupTerminationEvent: Sendable {
  case acknowledged
  case budgetExpired
}

private func race(
  session: any CleanupGenerationSession,
  deadline: ContinuousClock.Instant,
  box: CleanupSessionBox,
  clock: CleanupClock,
  cancellationBudget: Duration
) async -> CleanupRaceEvent {
  return await withTaskGroup(of: CleanupRaceEvent.self) { group in
    group.addTask {
      do { return .candidate(try await session.result()) }
      catch let error as CleanupGenerationError {
        switch error {
        case .requestCancelled: return .requestCancelled
        case .terminated: return .terminated
        case .generationFailed: return .generationFailed
        }
      } catch is CancellationError {
        return Task.isCancelled ? .callerCancelled : .generationFailed
      } catch {
        return .generationFailed
      }
    }
    group.addTask {
      do {
        try await clock.sleepUntil(deadline)
        return .deadline
      } catch is CancellationError {
        return Task.isCancelled ? .callerCancelled : .deadline
      } catch {
        return .deadline
      }
    }

    guard let first = await group.next() else { return .generationFailed }
    switch first {
    case .deadline, .callerCancelled, .requestCancelled, .terminated:
      box.requestCancellation()
      _ = await awaitTermination(
        session: session,
        box: box,
        clock: clock,
        cancellationBudget: cancellationBudget
      )
      group.cancelAll()
      while await group.next() != nil { }
      return first
    case .candidate, .generationFailed:
      group.cancelAll()
      while await group.next() != nil { }
      return first
    }
  }
}

private func awaitTermination(
  session: any CleanupGenerationSession,
  box: CleanupSessionBox,
  clock: CleanupClock,
  cancellationBudget: Duration
) async -> CleanupTerminationDisposition {
  if let disposition = box.completedTermination() {
    return disposition
  }

  let shield = Task {
    await withTaskGroup(of: CleanupTerminationEvent.self) { group in
      group.addTask {
        await session.acknowledgement()
        return .acknowledged
      }
      group.addTask {
        do {
          try await clock.sleepFor(cancellationBudget)
          return .budgetExpired
        } catch {
          return .budgetExpired
        }
      }

      guard let first = await group.next() else {
        box.forceTerminate()
        group.cancelAll()
        while await group.next() != nil { }
        return box.recordTermination(.forcedTermination)
      }
      switch first {
      case .acknowledged:
        group.cancelAll()
        while await group.next() != nil { }
        return box.recordTermination(
          box.forceTerminationRequested() ? .forcedTermination : .acknowledged
        )
      case .budgetExpired:
        box.forceTerminate()
        group.cancelAll()
        while await group.next() != nil { }
        return box.recordTermination(.forcedTermination)
      }
    }
  }
  return await shield.value
}
