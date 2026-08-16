import Foundation

struct FoundationModelCleanupGenerator: BoundedCleanupGenerating {
  private let generate:
    @Sendable (IncrementalCleanupRequest, Int) async throws -> String

  init(dictation: FoundationModelDictation) {
    generate = { request, maximumOutputTokens in
      await dictation.cleanupResult(
        request.baseline,
        maximumOutputTokens: maximumOutputTokens
      ).text
    }
  }

  init(
    generate: @escaping @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  ) {
    self.generate = generate
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    FoundationModelCleanupSession(
      request: request,
      maximumOutputTokens: maximumOutputTokens,
      responder: generate
    )
  }
}

private final class FoundationModelCleanupSession: CleanupGenerationSession, @unchecked Sendable {
  private let request: IncrementalCleanupRequest
  private let maximumOutputTokens: Int
  private let responder:
    @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  private let gate: FoundationModelPublicationGate
  private let lock = NSLock()
  private var generationTask: Task<Void, Never>?
  private var cancellationRequested = false

  init(
    request: IncrementalCleanupRequest,
    maximumOutputTokens: Int,
    responder: @escaping @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  ) {
    self.request = request
    self.maximumOutputTokens = maximumOutputTokens
    self.responder = responder
    gate = FoundationModelPublicationGate()
  }

  func result() async throws -> GeneratedCleanupCandidate {
    startGenerationIfNeeded()
    return try await gate.result()
  }

  func acknowledgement() async {
    await gate.acknowledgement()
  }

  func requestCancellation() {
    let task: Task<Void, Never>?
    lock.lock()
    cancellationRequested = true
    task = generationTask
    lock.unlock()
    gate.close(.requestCancelled)
    task?.cancel()
  }

  func forceTerminate() {
    let task: Task<Void, Never>?
    lock.lock()
    cancellationRequested = true
    task = generationTask
    lock.unlock()
    gate.close(.terminated)
    task?.cancel()
  }

  private func startGenerationIfNeeded() {
    lock.lock()
    guard generationTask == nil, !cancellationRequested else {
      lock.unlock()
      return
    }
    let request = self.request
    let maximumOutputTokens = self.maximumOutputTokens
    let responder = self.responder
    let gate = self.gate
    generationTask = Task {
      do {
        let text = try await responder(request, maximumOutputTokens)
        _ = gate.publish(.init(cleaned: text))
      } catch is CancellationError {
        gate.close(.requestCancelled)
      } catch {
        gate.close(.generationFailed)
      }
    }
    lock.unlock()
  }
}

private final class FoundationModelPublicationGate: @unchecked Sendable {
  private enum State {
    case open
    case published(GeneratedCleanupCandidate)
    case closed(CleanupGenerationError)
  }

  private let lock = NSLock()
  private let resultWaiter = FoundationModelResultWaiter()
  private let acknowledgementWaiter = FoundationModelAcknowledgementWaiter()
  private var state: State = .open
  private var resultTask: Task<GeneratedCleanupCandidate, Error>?
  private var acknowledgementTask: Task<Void, Never>?

  func publish(_ candidate: GeneratedCleanupCandidate) -> Bool {
    lock.lock()
    guard case .open = state else {
      lock.unlock()
      return false
    }
    state = .published(candidate)
    lock.unlock()
    resultWaiter.resolve(.success(candidate))
    acknowledgementWaiter.resume()
    return true
  }

  func close(_ error: CleanupGenerationError) {
    lock.lock()
    guard case .open = state else {
      lock.unlock()
      return
    }
    state = .closed(error)
    lock.unlock()
    resultWaiter.resolve(.failure(error))
    acknowledgementWaiter.resume()
  }

  func result() async throws -> GeneratedCleanupCandidate {
    let task = resultTaskForAwait()
    return try await task.value
  }

  func acknowledgement() async {
    let task = acknowledgementTaskForAwait()
    await task.value
  }

  private func resultTaskForAwait() -> Task<GeneratedCleanupCandidate, Error> {
    lock.lock()
    defer { lock.unlock() }
    if let resultTask {
      return resultTask
    }
    let waiter = resultWaiter
    let task = Task { try await waiter.value() }
    resultTask = task
    return task
  }

  private func acknowledgementTaskForAwait() -> Task<Void, Never> {
    lock.lock()
    defer { lock.unlock() }
    if let acknowledgementTask {
      return acknowledgementTask
    }
    let waiter = acknowledgementWaiter
    let task = Task { await waiter.value() }
    acknowledgementTask = task
    return task
  }
}

private final class FoundationModelResultWaiter: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<GeneratedCleanupCandidate, Error>?
  private var continuation: CheckedContinuation<GeneratedCleanupCandidate, Error>?

  func value() async throws -> GeneratedCleanupCandidate {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      let result = self.result
      if result == nil {
        self.continuation = continuation
      }
      lock.unlock()
      if let result {
        continuation.resume(with: result)
      }
    }
  }

  func resolve(_ result: Result<GeneratedCleanupCandidate, Error>) {
    lock.lock()
    guard self.result == nil else {
      lock.unlock()
      return
    }
    self.result = result
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }
}

private final class FoundationModelAcknowledgementWaiter: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false
  private var continuation: CheckedContinuation<Void, Never>?

  func value() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      let completed = self.completed
      if !completed {
        self.continuation = continuation
      }
      lock.unlock()
      if completed {
        continuation.resume()
      }
    }
  }

  func resume() {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume()
  }
}
