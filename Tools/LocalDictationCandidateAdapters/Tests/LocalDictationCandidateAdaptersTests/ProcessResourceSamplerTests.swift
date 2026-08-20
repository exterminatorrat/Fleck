import Foundation
import Testing
@testable import LocalDictationCandidateRunner

private final class ContinuationWaiter: @unchecked Sendable {
  let continuation: CheckedContinuation<Void, Error>

  init(_ continuation: CheckedContinuation<Void, Error>) {
    self.continuation = continuation
  }
}

private final class SequenceResourceProvider: ProcessResourceSamplerProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [ProcessResourceSample]
  private var identifiers: [Int32] = []
  private var sampleCountWaiters: [(expected: Int, waiter: ContinuationWaiter)] = []

  init(_ samples: [ProcessResourceSample]) {
    self.samples = samples
  }

  func sample(processIdentifier: Int32) throws -> ProcessResourceSample {
    lock.lock()
    identifiers.append(processIdentifier)
    let sampleCount = identifiers.count
    let readyWaiters = sampleCountWaiters.filter { $0.expected <= sampleCount }
    sampleCountWaiters.removeAll { $0.expected <= sampleCount }
    guard !samples.isEmpty else {
      lock.unlock()
      readyWaiters.forEach { $0.waiter.continuation.resume() }
      throw ProcessResourceSamplerError.unavailable("injected samples exhausted")
    }
    let sample = samples.removeFirst()
    lock.unlock()
    readyWaiters.forEach { $0.waiter.continuation.resume() }
    return sample
  }

  func waitForSampleCount(_ expected: Int) async throws {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if identifiers.count >= expected {
        lock.unlock()
        continuation.resume()
      } else {
        sampleCountWaiters.append(
          (expected: expected, waiter: ContinuationWaiter(continuation))
        )
        lock.unlock()
      }
    }
  }

  var requestedIdentifiers: [Int32] {
    lock.lock()
    defer { lock.unlock() }
    return identifiers
  }
}

private final class ControlledSleeper: ProcessResourceSamplerClock, @unchecked Sendable {
  private let lock = NSLock()
  private var waiters: [ContinuationWaiter] = []
  private var registrationWaiters: [ContinuationWaiter] = []
  private var registrationWaiterCountWaiters: [(expected: Int, waiter: ContinuationWaiter)] = []
  private var registrationCountWaiters: [(expected: Int, waiter: ContinuationWaiter)] = []
  private var registrationCount = 0
  private var pendingRegistrations = 0
  private var pendingReleases = 0
  private var cancelled = false

  func sleep(for _: Duration) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let waiter = ContinuationWaiter(continuation)
        var registrationWaiter: ContinuationWaiter?
        var releaseImmediately = false
        lock.lock()
        if cancelled || Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        } else {
          registrationCount += 1
          let readyCountWaiters = registrationCountWaiters.filter {
            $0.expected <= registrationCount
          }
          registrationCountWaiters.removeAll { $0.expected <= registrationCount }
          if pendingReleases > 0 {
            pendingReleases -= 1
            releaseImmediately = true
          } else {
            waiters.append(waiter)
          }
          if !registrationWaiters.isEmpty {
            registrationWaiter = registrationWaiters.removeFirst()
          } else {
            pendingRegistrations += 1
          }
          lock.unlock()
          registrationWaiter?.continuation.resume()
          readyCountWaiters.forEach { $0.waiter.continuation.resume() }
          if releaseImmediately {
            continuation.resume()
          }
        }
      }
    } onCancel: {
      self.cancel()
    }
  }

  func releaseOne() {
    lock.lock()
    let waiter: ContinuationWaiter?
    if waiters.isEmpty {
      pendingReleases += 1
      waiter = nil
    } else {
      waiter = waiters.removeFirst()
    }
    lock.unlock()
    waiter?.continuation.resume()
  }

  func waitForSleepRegistration() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let waiter = ContinuationWaiter(continuation)
        lock.lock()
        if cancelled || Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        } else if pendingRegistrations > 0 {
          pendingRegistrations -= 1
          lock.unlock()
          continuation.resume()
        } else {
          registrationWaiters.append(waiter)
          let readyWaiters = registrationWaiterCountWaiters.filter {
            $0.expected <= registrationWaiters.count
          }
          registrationWaiterCountWaiters.removeAll {
            $0.expected <= registrationWaiters.count
          }
          lock.unlock()
          readyWaiters.forEach { $0.waiter.continuation.resume() }
        }
      }
    } onCancel: {
      self.cancel()
    }
  }

  func waitForRegistrationConsumerCount(_ expected: Int) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let waiter = ContinuationWaiter(continuation)
        lock.lock()
        if cancelled || Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        } else if registrationWaiters.count >= expected {
          lock.unlock()
          continuation.resume()
        } else {
          registrationWaiterCountWaiters.append(
            (expected: expected, waiter: waiter)
          )
          lock.unlock()
        }
      }
    } onCancel: {
      self.cancel()
    }
  }

  func waitForRegistrationCount(_ expected: Int) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let waiter = ContinuationWaiter(continuation)
        lock.lock()
        if cancelled || Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        } else if registrationCount >= expected {
          lock.unlock()
          continuation.resume()
        } else {
          registrationCountWaiters.append(
            (expected: expected, waiter: waiter)
          )
          lock.unlock()
        }
      }
    } onCancel: {
      self.cancel()
    }
  }

  var pendingRegistrationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return pendingRegistrations
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let pending = waiters
      + registrationWaiters
      + registrationWaiterCountWaiters.map(\.waiter)
      + registrationCountWaiters.map(\.waiter)
    waiters.removeAll()
    registrationWaiters.removeAll()
    registrationWaiterCountWaiters.removeAll()
    registrationCountWaiters.removeAll()
    lock.unlock()
    pending.forEach { $0.continuation.resume(throwing: CancellationError()) }
  }
}

@Suite("ProcessResourceSamplerTests")
struct ProcessResourceSamplerTests {

  @Test func retainsTwoUnconsumedSleepRegistrationsAndCleansCancellation() async throws {
    let sleeper = ControlledSleeper()
    let firstSleep = Task { try await sleeper.sleep(for: .seconds(1)) }
    let secondSleep = Task { try await sleeper.sleep(for: .seconds(1)) }

    try await sleeper.waitForRegistrationCount(2)
    let pendingRegistrationCount = sleeper.pendingRegistrationCount
    #expect(pendingRegistrationCount == 2)
    guard pendingRegistrationCount == 2 else {
      sleeper.cancel()
      _ = await firstSleep.result
      _ = await secondSleep.result
      return
    }

    try await sleeper.waitForSleepRegistration()
    try await sleeper.waitForSleepRegistration()
    sleeper.releaseOne()
    sleeper.releaseOne()
    try await firstSleep.value
    try await secondSleep.value
    #expect(sleeper.pendingRegistrationCount == 0)

    let firstCancelled = Task { try await sleeper.waitForSleepRegistration() }
    let secondCancelled = Task { try await sleeper.waitForSleepRegistration() }
    try await sleeper.waitForRegistrationConsumerCount(2)
    sleeper.cancel()
    await #expect(throws: CancellationError.self) {
      try await firstCancelled.value
    }
    await #expect(throws: CancellationError.self) {
      try await secondCancelled.value
    }
    sleeper.cancel()
  }

  @Test func reportsMonotonicResidentAndPhysicalFootprintPeaksForExactPID() async throws {
    let provider = SequenceResourceProvider([
      ProcessResourceSample(residentBytes: 100, physicalFootprintBytes: 200),
      ProcessResourceSample(residentBytes: 80, physicalFootprintBytes: 250),
      ProcessResourceSample(residentBytes: 300, physicalFootprintBytes: 150),
    ])
    let sleeper = ControlledSleeper()
    let sampler = ProcessResourceSampler(
      processIdentifier: 42,
      interval: .seconds(1),
      provider: provider,
      clock: sleeper
    )

    sleeper.releaseOne()
    try await sampler.start()
    try await sleeper.waitForSleepRegistration()
    try await provider.waitForSampleCount(2)
    try await sleeper.waitForSleepRegistration()
    sleeper.releaseOne()
    try await provider.waitForSampleCount(3)

    let peaks = try await sampler.stop()

    #expect(peaks == ProcessResourcePeaks(peakResidentBytes: 300, peakPhysicalFootprintBytes: 250))
    #expect(provider.requestedIdentifiers == [42, 42, 42])
  }

  @Test func rejectsInvalidSamplesAndJoinsCancelledSamplingTask() async throws {
    let provider = SequenceResourceProvider([
      ProcessResourceSample(residentBytes: -1, physicalFootprintBytes: 10),
    ])
    let sampler = ProcessResourceSampler(
      processIdentifier: 42,
      provider: provider,
      clock: ControlledSleeper()
    )

    await #expect(throws: ProcessResourceSamplerError.self) {
      try await sampler.start()
    }
  }

  @Test func reportsProviderUnavailabilityAfterChildExit() async throws {
    let provider = SequenceResourceProvider([
      ProcessResourceSample(residentBytes: 10, physicalFootprintBytes: 20),
      // The next sample fails explicitly, just as an exited child would.
    ])
    let sleeper = ControlledSleeper()
    let sampler = ProcessResourceSampler(
      processIdentifier: 99,
      interval: .seconds(1),
      provider: provider,
      clock: sleeper
    )

    try await sampler.start()
    try await sleeper.waitForSleepRegistration()
    sleeper.releaseOne()
    try await provider.waitForSampleCount(2)

    await #expect(throws: ProcessResourceSamplerError.self) {
      try await sampler.stop()
    }
  }
}
