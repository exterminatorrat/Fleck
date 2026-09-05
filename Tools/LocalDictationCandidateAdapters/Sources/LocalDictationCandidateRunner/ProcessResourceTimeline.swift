import Foundation

public struct ProcessResourceTimelineSample: Codable, Equatable, Sendable {
  public let elapsedMilliseconds: Int64
  public let residentBytes: Int64
  public let physicalFootprintBytes: Int64
}

public enum ProcessResourceTimelineCompletion: String, Codable, Equatable, Sendable {
  case complete
  case incomplete
}

public enum ProcessResourceTimelineFailureCategory: String, Codable, Equatable, Sendable {
  case missingProcessStartIdentity
  case processIdentityChanged
  case resourceUnavailable
  case invalidSample
  case providerFailure
}

public struct ProcessResourceTimelineReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let processIdentifier: Int32
  public let processStartIdentity: UInt64?
  public let cadenceMilliseconds: Int64
  public let requestedDurationSeconds: Double
  public let samples: [ProcessResourceTimelineSample]
  public let sampleCount: Int
  public let peakResidentBytes: Int64?
  public let peakPhysicalFootprintBytes: Int64?
  public let completion: ProcessResourceTimelineCompletion
  public let failureCategory: ProcessResourceTimelineFailureCategory?
}

public struct ProcessResourceTimeline: Sendable {
  private let processIdentifier: Int32
  private let duration: Duration
  private let cadence: Duration
  private let provider: any ProcessResourceSamplerProvider
  private let clock: any ProcessResourceSamplerClock

  public init(
    processIdentifier: Int32,
    duration: Duration,
    cadence: Duration = .milliseconds(100),
    provider: any ProcessResourceSamplerProvider = DarwinProcessResourceSamplerProvider(),
    clock: any ProcessResourceSamplerClock = ContinuousProcessResourceSamplerClock()
  ) {
    self.processIdentifier = processIdentifier
    self.duration = duration
    self.cadence = cadence
    self.provider = provider
    self.clock = clock
  }

  public func run() async throws -> ProcessResourceTimelineReport {
    guard duration > .zero, cadence > .zero else {
      throw ProcessResourceSamplerError.invalidInterval
    }

    let startedAt = clock.now()
    let deadline = startedAt.advanced(by: duration)
    var nextSampleAt = startedAt
    var processStartIdentity: UInt64?
    var samples: [ProcessResourceTimelineSample] = []

    while clock.now() < deadline {
      try Task.checkCancellation()
      let sampledAt = clock.now()
      let sample: ProcessResourceSample
      do {
        sample = try provider.sample(processIdentifier: processIdentifier)
        try Task.checkCancellation()
        try validateProcessResourceSample(sample)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as ProcessResourceSamplerError {
        try Task.checkCancellation()
        let category: ProcessResourceTimelineFailureCategory
        switch error {
        case .invalidSample: category = .invalidSample
        case .unavailable: category = .resourceUnavailable
        default: category = .providerFailure
        }
        return report(
          identity: processStartIdentity,
          samples: samples,
          completion: .incomplete,
          failure: category
        )
      } catch {
        try Task.checkCancellation()
        return report(
          identity: processStartIdentity,
          samples: samples,
          completion: .incomplete,
          failure: .providerFailure
        )
      }

      guard let sampleIdentity = sample.processStartIdentity else {
        return report(
          identity: processStartIdentity,
          samples: samples,
          completion: .incomplete,
          failure: .missingProcessStartIdentity
        )
      }
      if let processStartIdentity, processStartIdentity != sampleIdentity {
        return report(
          identity: processStartIdentity,
          samples: samples,
          completion: .incomplete,
          failure: .processIdentityChanged
        )
      }
      processStartIdentity = sampleIdentity
      samples.append(
        ProcessResourceTimelineSample(
          elapsedMilliseconds: milliseconds(startedAt.duration(to: sampledAt)),
          residentBytes: sample.residentBytes,
          physicalFootprintBytes: sample.physicalFootprintBytes
        )
      )

      let now = clock.now()
      guard now < deadline else { break }
      repeat {
        nextSampleAt = nextSampleAt.advanced(by: cadence)
      } while nextSampleAt <= now
      let wakeAt = min(nextSampleAt, deadline)
      try await clock.sleep(for: now.duration(to: wakeAt))
    }

    try Task.checkCancellation()
    return report(
      identity: processStartIdentity,
      samples: samples,
      completion: .complete,
      failure: nil
    )
  }

  private func report(
    identity: UInt64?,
    samples: [ProcessResourceTimelineSample],
    completion: ProcessResourceTimelineCompletion,
    failure: ProcessResourceTimelineFailureCategory?
  ) -> ProcessResourceTimelineReport {
    ProcessResourceTimelineReport(
      schemaVersion: 1,
      processIdentifier: processIdentifier,
      processStartIdentity: identity,
      cadenceMilliseconds: milliseconds(cadence),
      requestedDurationSeconds: seconds(duration),
      samples: samples,
      sampleCount: samples.count,
      peakResidentBytes: samples.map(\.residentBytes).max(),
      peakPhysicalFootprintBytes: samples.map(\.physicalFootprintBytes).max(),
      completion: completion,
      failureCategory: failure
    )
  }
}

private func milliseconds(_ duration: Duration) -> Int64 {
  let components = duration.components
  return components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
}

private func seconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}
