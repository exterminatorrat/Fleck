import Foundation

enum DynamicCleanupGeneratorError: Error, Equatable {
  case gemmaUnavailable
}

struct DynamicCleanupGenerator: BoundedCleanupGenerating {
  private let foundationIsAvailable: @Sendable () -> Bool
  private let foundationGenerator: any BoundedCleanupGenerating
  private let gemmaGate: GemmaCleanupLeaseGate

  init(
    foundationIsAvailable: @escaping @Sendable () -> Bool,
    foundationGenerator: any BoundedCleanupGenerating,
    gemmaGate: GemmaCleanupLeaseGate
  ) {
    self.foundationIsAvailable = foundationIsAvailable
    self.foundationGenerator = foundationGenerator
    self.gemmaGate = gemmaGate
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    if foundationIsAvailable() {
      return try foundationGenerator.start(
        request,
        maximumOutputTokens: maximumOutputTokens
      )
    }
    return try gemmaGate.start(
      request,
      maximumOutputTokens: maximumOutputTokens
    )
  }
}
final class GemmaCleanupLeaseGate: GemmaRouteGenerating, @unchecked Sendable {
  private let lock = NSLock()
  private var generator: (any BoundedCleanupGenerating)?
  private var routeGenerator: (any GemmaRouteGenerating)?
  private var leases: Set<UUID> = []
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []

  func enable(_ generator: any BoundedCleanupGenerating) {
    lock.withLock {
      self.generator = generator
      routeGenerator = generator as? any GemmaRouteGenerating
    }
  }

  func disable() {
    lock.withLock {
      generator = nil
      routeGenerator = nil
    }
  }

  func disableAndWait() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock {
        generator = nil
        routeGenerator = nil
        guard !leases.isEmpty else { return true }
        drainWaiters.append(continuation)
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
  }

  func startRoute(
    baseline: String,
    plainPrompt: String,
    deadline: ContinuousClock.Instant,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    let (leaseID, generator) = try acquireRoute()
    do {
      let session = try generator.startRoute(
        baseline: baseline,
        plainPrompt: plainPrompt,
        deadline: deadline,
        maximumOutputTokens: maximumOutputTokens
      )
      return GemmaLeasedCleanupSession(
        inner: session,
        releaseLease: { [self] in release(leaseID) }
      )
    } catch {
      release(leaseID)
      throw error
    }
  }

  fileprivate func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    let (leaseID, generator) = try acquire()
    do {
      let session = try generator.start(
        request,
        maximumOutputTokens: maximumOutputTokens
      )
      return GemmaLeasedCleanupSession(
        inner: session,
        releaseLease: { [self] in release(leaseID) }
      )
    } catch {
      release(leaseID)
      throw error
    }
  }

  private func acquire() throws -> (UUID, any BoundedCleanupGenerating) {
    try lock.withLock {
      guard let generator else {
        throw DynamicCleanupGeneratorError.gemmaUnavailable
      }
      let leaseID = UUID()
      leases.insert(leaseID)
      return (leaseID, generator)
    }
  }

  private func acquireRoute() throws -> (UUID, any GemmaRouteGenerating) {
    try lock.withLock {
      guard let routeGenerator else {
        throw DynamicCleanupGeneratorError.gemmaUnavailable
      }
      let leaseID = UUID()
      leases.insert(leaseID)
      return (leaseID, routeGenerator)
    }
  }

  private func release(_ leaseID: UUID) {
    let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      guard leases.remove(leaseID) != nil, leases.isEmpty else { return [] }
      let waiters = drainWaiters
      drainWaiters = []
      return waiters
    }
    waiters.forEach { $0.resume() }
  }
}

private final class GemmaLeasedCleanupSession: CleanupGenerationSession, @unchecked Sendable {
  private let inner: any CleanupGenerationSession
  private let releaseLease: @Sendable () -> Void
  private let lock = NSLock()
  private var acknowledgementTask: Task<Void, Never>?
  private var cancellationRequested = false
  private var forceRequested = false

  init(
    inner: any CleanupGenerationSession,
    releaseLease: @escaping @Sendable () -> Void
  ) {
    self.inner = inner
    self.releaseLease = releaseLease
  }

  func result() async throws -> GeneratedCleanupCandidate {
    do {
      let candidate = try await inner.result()
      await acknowledgement()
      return candidate
    } catch {
      await acknowledgement()
      throw error
    }
  }

  func acknowledgement() async {
    await acknowledgementTaskForAwait().value
  }

  func requestCancellation() {
    let shouldRequest = lock.withLock {
      guard !cancellationRequested else { return false }
      cancellationRequested = true
      return true
    }
    if shouldRequest { inner.requestCancellation() }
    _ = acknowledgementTaskForAwait()
  }

  func forceTerminate() {
    let shouldForce = lock.withLock {
      guard !forceRequested else { return false }
      forceRequested = true
      return true
    }
    if shouldForce { inner.forceTerminate() }
    _ = acknowledgementTaskForAwait()
  }

  private func acknowledgementTaskForAwait() -> Task<Void, Never> {
    lock.withLock {
      if let acknowledgementTask { return acknowledgementTask }
      let inner = self.inner
      let releaseLease = self.releaseLease
      let task = Task {
        await inner.acknowledgement()
        releaseLease()
      }
      acknowledgementTask = task
      return task
    }
  }
}
