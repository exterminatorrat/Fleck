import Foundation
import Testing
@testable import LocalDictationCandidateCLI
@testable import LocalDictationCandidateRunner

private enum TimelineProviderFailure: Error {
  case injected
}

private enum TimelineProviderStep {
  case sample(ProcessResourceSample)
  case unavailable
  case failure
}

private final class TimelineSequenceProvider: ProcessResourceSamplerProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var steps: [TimelineProviderStep]
  private var identifiers: [Int32] = []

  init(_ steps: [TimelineProviderStep]) {
    self.steps = steps
  }

  func sample(processIdentifier: Int32) throws -> ProcessResourceSample {
    lock.lock()
    defer { lock.unlock() }
    identifiers.append(processIdentifier)
    guard !steps.isEmpty else {
      throw ProcessResourceSamplerError.unavailable("injected process exit")
    }
    switch steps.removeFirst() {
    case .sample(let sample): return sample
    case .unavailable: throw ProcessResourceSamplerError.unavailable("injected process exit")
    case .failure: throw TimelineProviderFailure.injected
    }
  }

  var requestedIdentifiers: [Int32] {
    lock.lock()
    defer { lock.unlock() }
    return identifiers
  }
}

private final class RepeatingTimelineProvider: ProcessResourceSamplerProvider, @unchecked Sendable {
  private let lock = NSLock()
  private let sampleValue: ProcessResourceSample
  private var identifiers: [Int32] = []

  init(_ sample: ProcessResourceSample) {
    sampleValue = sample
  }

  func sample(processIdentifier: Int32) throws -> ProcessResourceSample {
    lock.lock()
    identifiers.append(processIdentifier)
    lock.unlock()
    return sampleValue
  }

  var sampleCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return identifiers.count
  }
}

private final class LatencyTimelineProvider: ProcessResourceSamplerProvider, @unchecked Sendable {
  private let clock: AdvancingTimelineClock

  init(clock: AdvancingTimelineClock) {
    self.clock = clock
  }

  func sample(processIdentifier _: Int32) throws -> ProcessResourceSample {
    clock.advance(by: .milliseconds(30))
    return resourceSample(resident: 1, footprint: 2)
  }
}

private enum BlockingTimelineProviderOutcome {
  case sample
  case failure
}

private final class BlockingTimelineProvider: ProcessResourceSamplerProvider, @unchecked Sendable {
  private let entered = DispatchSemaphore(value: 0)
  private let released = DispatchSemaphore(value: 0)
  private let clock: AdvancingTimelineClock
  private let outcome: BlockingTimelineProviderOutcome

  init(clock: AdvancingTimelineClock, outcome: BlockingTimelineProviderOutcome) {
    self.clock = clock
    self.outcome = outcome
  }

  func sample(processIdentifier _: Int32) throws -> ProcessResourceSample {
    entered.signal()
    released.wait()
    clock.advance(by: .seconds(2))
    switch outcome {
    case .sample: return resourceSample(resident: 1, footprint: 2)
    case .failure: throw TimelineProviderFailure.injected
    }
  }

  func waitUntilEntered() {
    entered.wait()
  }

  func release() {
    released.signal()
  }
}

private final class AdvancingTimelineClock: ProcessResourceSamplerClock, @unchecked Sendable {
  private let lock = NSLock()
  private let origin = ContinuousClock.now
  private var offset = Duration.zero
  private var recordedSleeps: [Duration] = []
  private let cancelOnSleep: Bool
  private let cancelAndReturnOnSleep: Bool

  init(cancelOnSleep: Bool = false, cancelAndReturnOnSleep: Bool = false) {
    self.cancelOnSleep = cancelOnSleep
    self.cancelAndReturnOnSleep = cancelAndReturnOnSleep
  }

  func now() -> ContinuousClock.Instant {
    lock.lock()
    defer { lock.unlock() }
    return origin.advanced(by: offset)
  }

  func sleep(for duration: Duration) async throws {
    if cancelOnSleep { throw CancellationError() }
    lock.withLock {
      recordedSleeps.append(duration)
      offset += duration
    }
    if cancelAndReturnOnSleep {
      withUnsafeCurrentTask { $0?.cancel() }
    }
  }

  func advance(by duration: Duration) {
    lock.withLock {
      offset += duration
    }
  }

  var sleeps: [Duration] {
    lock.lock()
    defer { lock.unlock() }
    return recordedSleeps
  }
}

private func resourceSample(
  resident: Int64,
  footprint: Int64,
  identity: UInt64? = 7
) -> ProcessResourceSample {
  ProcessResourceSample(
    residentBytes: resident,
    physicalFootprintBytes: footprint,
    processStartIdentity: identity
  )
}

private func temporaryOutput(_ name: String = UUID().uuidString) -> URL {
  URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("fleck-resource-timeline-\(name).json")
}

@Suite("ProcessResourceTimelineTests", .serialized)
struct ProcessResourceTimelineTests {
  @Test func recordsExactPIDOrderedSamplesPeaksAndFiniteDeadline() async throws {
    let provider = TimelineSequenceProvider([
      .sample(resourceSample(resident: 100, footprint: 400)),
      .sample(resourceSample(resident: 300, footprint: 200)),
      .sample(resourceSample(resident: 250, footprint: 500)),
    ])
    let clock = AdvancingTimelineClock()
    let report = try await ProcessResourceTimeline(
      processIdentifier: 42,
      duration: .milliseconds(250),
      cadence: .milliseconds(100),
      provider: provider,
      clock: clock
    ).run()

    #expect(report.processIdentifier == 42)
    #expect(report.processStartIdentity == 7)
    #expect(report.cadenceMilliseconds == 100)
    #expect(report.samples.map(\.elapsedMilliseconds) == [0, 100, 200])
    #expect(report.samples.map(\.residentBytes) == [100, 300, 250])
    #expect(report.samples.map(\.physicalFootprintBytes) == [400, 200, 500])
    #expect(report.sampleCount == 3)
    #expect(report.peakResidentBytes == 300)
    #expect(report.peakPhysicalFootprintBytes == 500)
    #expect(report.completion == .complete)
    #expect(report.failureCategory == nil)
    #expect(provider.requestedIdentifiers == [42, 42, 42])
    #expect(clock.sleeps == [.milliseconds(100), .milliseconds(100), .milliseconds(50)])
  }

  @Test func providerLatencyDoesNotDriftCadenceOrExtendDeadline() async throws {
    let clock = AdvancingTimelineClock()
    let report = try await ProcessResourceTimeline(
      processIdentifier: 43,
      duration: .milliseconds(250),
      cadence: .milliseconds(100),
      provider: LatencyTimelineProvider(clock: clock),
      clock: clock
    ).run()

    #expect(report.samples.map(\.elapsedMilliseconds) == [0, 100, 200])
    #expect(clock.sleeps == [.milliseconds(70), .milliseconds(70), .milliseconds(20)])
    #expect(report.completion == .complete)
  }

  @Test func rejectsMissingIdentityWithoutRecordingSample() async throws {
    let report = try await ProcessResourceTimeline(
      processIdentifier: 8,
      duration: .seconds(1),
      provider: TimelineSequenceProvider([
        .sample(resourceSample(resident: 10, footprint: 20, identity: nil))
      ]),
      clock: AdvancingTimelineClock()
    ).run()

    #expect(report.processStartIdentity == nil)
    #expect(report.samples.isEmpty)
    #expect(report.completion == .incomplete)
    #expect(report.failureCategory == .missingProcessStartIdentity)
  }

  @Test func changedIdentityIsRejectedAfterPreservingValidSamples() async throws {
    let report = try await ProcessResourceTimeline(
      processIdentifier: 9,
      duration: .seconds(1),
      provider: TimelineSequenceProvider([
        .sample(resourceSample(resident: 10, footprint: 20, identity: 11)),
        .sample(resourceSample(resident: 30, footprint: 40, identity: 11)),
        .sample(resourceSample(resident: 900, footprint: 900, identity: 12)),
      ]),
      clock: AdvancingTimelineClock()
    ).run()

    #expect(report.processStartIdentity == 11)
    #expect(report.samples.map(\.residentBytes) == [10, 30])
    #expect(report.peakResidentBytes == 30)
    #expect(report.completion == .incomplete)
    #expect(report.failureCategory == .processIdentityChanged)
  }

  @Test func processExitPreservesValidIncompleteEvidence() async throws {
    let report = try await ProcessResourceTimeline(
      processIdentifier: 10,
      duration: .seconds(1),
      provider: TimelineSequenceProvider([
        .sample(resourceSample(resident: 10, footprint: 20)),
        .unavailable,
      ]),
      clock: AdvancingTimelineClock()
    ).run()

    #expect(report.sampleCount == 1)
    #expect(report.samples.first?.elapsedMilliseconds == 0)
    #expect(report.completion == .incomplete)
    #expect(report.failureCategory == .resourceUnavailable)
  }

  @Test func invalidAndUnexpectedProviderFailuresAreTyped() async throws {
    let invalid = try await ProcessResourceTimeline(
      processIdentifier: 11,
      duration: .seconds(1),
      provider: TimelineSequenceProvider([
        .sample(resourceSample(resident: 10, footprint: 20)),
        .sample(resourceSample(resident: -1, footprint: 30)),
      ]),
      clock: AdvancingTimelineClock()
    ).run()
    #expect(invalid.sampleCount == 1)
    #expect(invalid.failureCategory == .invalidSample)

    let failed = try await ProcessResourceTimeline(
      processIdentifier: 12,
      duration: .seconds(1),
      provider: TimelineSequenceProvider([.failure]),
      clock: AdvancingTimelineClock()
    ).run()
    #expect(failed.sampleCount == 0)
    #expect(failed.failureCategory == .providerFailure)
  }

  @Test func propagatesCancellation() async {
    await #expect(throws: CancellationError.self) {
      _ = try await ProcessResourceTimeline(
        processIdentifier: 13,
        duration: .seconds(1),
        provider: RepeatingTimelineProvider(resourceSample(resident: 1, footprint: 2)),
        clock: AdvancingTimelineClock(cancelOnSleep: true)
      ).run()
    }
  }

  @Test func cancellationDuringBlockedProviderTakesPrecedenceOverResultOrFailure() async {
    for outcome in [BlockingTimelineProviderOutcome.sample, .failure] {
      let clock = AdvancingTimelineClock()
      let provider = BlockingTimelineProvider(clock: clock, outcome: outcome)
      let sampling = Task {
        try await ProcessResourceTimeline(
          processIdentifier: 14,
          duration: .seconds(1),
          provider: provider,
          clock: clock
        ).run()
      }
      await Task.detached { provider.waitUntilEntered() }.value

      sampling.cancel()
      provider.release()

      await #expect(throws: CancellationError.self) {
        _ = try await sampling.value
      }
    }
  }

  @Test func cancellationAtDeadlineTakesPrecedenceOverSuccessfulCompletion() async {
    let sampling = Task {
      try await ProcessResourceTimeline(
        processIdentifier: 15,
        duration: .milliseconds(100),
        provider: RepeatingTimelineProvider(resourceSample(resident: 1, footprint: 2)),
        clock: AdvancingTimelineClock(cancelAndReturnOnSleep: true)
      ).run()
    }
    await #expect(throws: CancellationError.self) {
      _ = try await sampling.value
    }
  }

  @Test func cliStrictlyRejectsInvalidArgumentsBeforeSampling() async {
    let invalidArguments = [
      ["sample-resources"],
      ["sample-resources", "--pid", "1", "--duration-seconds", "1", "--output"],
      ["sample-resources", "--pid", "1", "--pid", "2", "--duration-seconds", "1", "--output", temporaryOutput().path],
      ["sample-resources", "--pid", "1", "--duration-seconds", "1", "--unknown", "x", "--output", temporaryOutput().path],
      ["sample-resources", "--pid", "0", "--duration-seconds", "1", "--output", temporaryOutput().path],
      ["sample-resources", "--pid", "2147483648", "--duration-seconds", "1", "--output", temporaryOutput().path],
      ["sample-resources", "--pid", "1", "--duration-seconds", "0", "--output", temporaryOutput().path],
      ["sample-resources", "--pid", "1", "--duration-seconds", "601", "--output", temporaryOutput().path],
    ]
    let provider = RepeatingTimelineProvider(resourceSample(resident: 1, footprint: 2))
    for arguments in invalidArguments {
      let status = await LocalDictationCandidateCLI.run(
        arguments,
        diagnosticSink: { _ in },
        resourceProvider: provider,
        resourceClock: AdvancingTimelineClock()
      )
      #expect(status == 2)
    }
    #expect(provider.sampleCount == 0)
  }

  @Test func cliRejectsOccupiedOutputBeforeSampling() async throws {
    let output = temporaryOutput()
    try Data("occupied".utf8).write(to: output)
    defer { try? FileManager.default.removeItem(at: output) }
    let provider = RepeatingTimelineProvider(resourceSample(resident: 1, footprint: 2))

    let status = await LocalDictationCandidateCLI.run(
      ["sample-resources", "--pid", "77", "--duration-seconds", "1", "--output", output.path],
      diagnosticSink: { _ in },
      resourceProvider: provider,
      resourceClock: AdvancingTimelineClock()
    )

    #expect(status == 2)
    #expect(provider.sampleCount == 0)
    #expect(try Data(contentsOf: output) == Data("occupied".utf8))
  }

  @Test func cliRejectsDanglingSymlinkOutputBeforeSampling() async throws {
    let output = temporaryOutput()
    try FileManager.default.createSymbolicLink(
      atPath: output.path,
      withDestinationPath: output.path + ".missing"
    )
    defer { try? FileManager.default.removeItem(at: output) }
    let provider = RepeatingTimelineProvider(resourceSample(resident: 1, footprint: 2))

    let status = await LocalDictationCandidateCLI.run(
      ["sample-resources", "--pid", "78", "--duration-seconds", "1", "--output", output.path],
      diagnosticSink: { _ in },
      resourceProvider: provider,
      resourceClock: AdvancingTimelineClock()
    )

    #expect(status == 2)
    #expect(provider.sampleCount == 0)
  }

  @Test func cliPublishesMachineReadableTimelineAndReturnsNonzeroWhenIncomplete() async throws {
    let completeOutput = temporaryOutput()
    let incompleteOutput = temporaryOutput()
    defer {
      try? FileManager.default.removeItem(at: completeOutput)
      try? FileManager.default.removeItem(at: incompleteOutput)
    }

    let completeStatus = await LocalDictationCandidateCLI.run(
      ["sample-resources", "--pid", "88", "--duration-seconds", "1", "--output", completeOutput.path],
      diagnosticSink: { _ in },
      resourceProvider: RepeatingTimelineProvider(resourceSample(resident: 12, footprint: 34, identity: 56)),
      resourceClock: AdvancingTimelineClock()
    )
    #expect(completeStatus == 0)
    let complete = try JSONSerialization.jsonObject(with: Data(contentsOf: completeOutput)) as! [String: Any]
    #expect(complete["schemaVersion"] as? Int == 1)
    #expect(complete["processIdentifier"] as? Int == 88)
    #expect(complete["processStartIdentity"] as? Int == 56)
    #expect(complete["cadenceMilliseconds"] as? Int == 100)
    #expect(complete["requestedDurationSeconds"] as? Int == 1)
    #expect(complete["sampleCount"] as? Int == 10)
    #expect(complete["completion"] as? String == "complete")
    #expect(complete["failureCategory"] == nil)

    let incompleteStatus = await LocalDictationCandidateCLI.run(
      ["sample-resources", "--pid", "89", "--duration-seconds", "1", "--output", incompleteOutput.path],
      diagnosticSink: { _ in },
      resourceProvider: TimelineSequenceProvider([
        .sample(resourceSample(resident: 12, footprint: 34, identity: 57)),
        .unavailable,
      ]),
      resourceClock: AdvancingTimelineClock()
    )
    #expect(incompleteStatus != 0)
    let incomplete = try JSONSerialization.jsonObject(with: Data(contentsOf: incompleteOutput)) as! [String: Any]
    #expect(incomplete["sampleCount"] as? Int == 1)
    #expect(incomplete["completion"] as? String == "incomplete")
    #expect(incomplete["failureCategory"] as? String == "resourceUnavailable")
  }
}
