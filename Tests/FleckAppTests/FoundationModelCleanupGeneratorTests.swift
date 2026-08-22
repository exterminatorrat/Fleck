import Foundation
import Testing

@testable import FleckApp

private actor FoundationModelOperationProbe {
  private(set) var calls = 0
  private(set) var request: IncrementalCleanupRequest?
  private(set) var maximumOutputTokens: Int?
  private var started = false
  private var released = false

  func record(
    request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) {
    calls += 1
    self.request = request
    self.maximumOutputTokens = maximumOutputTokens
    started = true
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func waitUntilReleased() async {
    while !released { await Task.yield() }
  }

  func release(_ text: String) {
    _ = text
    released = true
  }
}

@Test func foundationModelSessionStartsOnlyWhenResultIsRequested() async throws {
  let probe = FoundationModelOperationProbe()
  let generator = FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }
  let session = try generator.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)

  #expect(await probe.calls == 0)
  let first = Task { try await session.result() }
  await probe.waitUntilStarted()
  #expect(await probe.calls == 1)
  #expect(await probe.maximumOutputTokens == 20)

  let concurrent = Task { try await session.result() }
  await probe.release("first")
  _ = try await first.value
  _ = try await concurrent.value
  _ = try await session.result()
  #expect(await probe.calls == 1)
}

@Test func foundationModelPreResultCancellationDoesNotStartGeneration() async throws {
  let probe = FoundationModelOperationProbe()
  let generator = FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }
  let session = try generator.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)

  #expect(await probe.calls == 0)
  session.requestCancellation()
  await session.acknowledgement()
  #expect(await probe.calls == 0)
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await session.result()
  }
  await probe.release("late")
  #expect(await probe.calls == 0)
}

@Test func foundationModelGeneratorReceivesTheCleanupDeadline() async throws {
  let deadline = TestCleanupClock.fixedInstant.advanced(by: .milliseconds(1500))
  let probe = FoundationModelOperationProbe()
  let generator = FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(request: request, maximumOutputTokens: maximumOutputTokens)
    await probe.waitUntilReleased()
    return request.baseline
  }
  let request = IncrementalCleanupRequest(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  )
  let session = try generator.start(request, maximumOutputTokens: 20)
  #expect(await probe.calls == 0)
  let result = Task { try await session.result() }
  await probe.waitUntilStarted()
  #expect(await probe.request?.deadline == deadline)
  #expect(await probe.maximumOutputTokens == 20)
  session.requestCancellation()
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await result.value
  }
  await probe.release("late")
}

@Test func foundationModelCallerCancellationAcknowledgesAndReturnsNoCandidate() async throws {
  let probe = FoundationModelOperationProbe()
  let generator = FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }
  let session = try generator.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)
  let result = Task { try await session.result() }
  await probe.waitUntilStarted()
  session.requestCancellation()
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await result.value
  }
  await probe.release("late")
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await session.result()
  }
}

@Test func foundationModelAcknowledgementCompletesAfterCancellation() async throws {
  let session = try FoundationModelCleanupGenerator { _, _ in "unused" }
    .start(.init(
      baseline: "send the report",
      protectedForms: [],
      replacements: 0,
      deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
    ), maximumOutputTokens: 20)
  let acknowledgement = Task { await session.acknowledgement() }
  session.requestCancellation()
  _ = await acknowledgement.value
  await session.acknowledgement()
}

@Test func foundationModelForceTerminationUnblocksBothWaiters() async throws {
  let probe = FoundationModelOperationProbe()
  let session = try FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)
  let result = Task { try await session.result() }
  let acknowledgement = Task { await session.acknowledgement() }
  await probe.waitUntilStarted()
  session.forceTerminate()
  await #expect(throws: CleanupGenerationError.terminated) {
    try await result.value
  }
  _ = await acknowledgement.value
}

@Test func foundationModelLateUnderlyingWorkCannotPublish() async throws {
  let probe = FoundationModelOperationProbe()
  let session = try FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)
  let result = Task { try await session.result() }
  await probe.waitUntilStarted()
  session.forceTerminate()
  await #expect(throws: CleanupGenerationError.terminated) {
    try await result.value
  }
  await probe.release("late")
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.terminated) {
    try await session.result()
  }
}

private enum TestCleanupClock {
  static let fixedInstant = ContinuousClock().now
}
