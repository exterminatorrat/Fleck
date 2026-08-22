import Darwin
import Foundation

public struct ProcessResourceSample: Equatable, Sendable {
  public let residentBytes: Int64
  public let physicalFootprintBytes: Int64

  public init(residentBytes: Int64, physicalFootprintBytes: Int64) {
    self.residentBytes = residentBytes
    self.physicalFootprintBytes = physicalFootprintBytes
  }
}

public struct ProcessResourcePeaks: Equatable, Sendable {
  public let peakResidentBytes: Int64
  public let peakPhysicalFootprintBytes: Int64

  public init(peakResidentBytes: Int64, peakPhysicalFootprintBytes: Int64) {
    self.peakResidentBytes = peakResidentBytes
    self.peakPhysicalFootprintBytes = peakPhysicalFootprintBytes
  }
}

public protocol ProcessResourceSamplerProvider: Sendable {
  func sample(processIdentifier: Int32) throws -> ProcessResourceSample
}

public protocol ProcessResourceSamplerClock: Sendable {
  func sleep(for duration: Duration) async throws
}

public struct ContinuousProcessResourceSamplerClock: ProcessResourceSamplerClock {
  public init() {}

  public func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}

public enum ProcessResourceSamplerError: Error, Equatable, Sendable, CustomStringConvertible {
  case alreadyStarted
  case notStarted
  case alreadyStopped
  case invalidInterval
  case unavailable(String)
  case invalidSample(residentBytes: Int64, physicalFootprintBytes: Int64)
  case providerFailure(String)

  public var description: String {
    switch self {
    case .alreadyStarted: return "resource sampler already started"
    case .notStarted: return "resource sampler not started"
    case .alreadyStopped: return "resource sampler already stopped"
    case .invalidInterval: return "resource sampler interval must be positive"
    case .unavailable(let detail): return "resource metrics unavailable: \(detail)"
    case .invalidSample(let residentBytes, let physicalFootprintBytes):
      return "invalid resource sample: resident=\(residentBytes), physical-footprint=\(physicalFootprintBytes)"
    case .providerFailure(let detail): return "resource provider failed: \(detail)"
    }
  }
}

public struct DarwinProcessResourceSamplerProvider: ProcessResourceSamplerProvider {
  public init() {}

  public func sample(processIdentifier: Int32) throws -> ProcessResourceSample {
    guard processIdentifier > 0 else {
      throw ProcessResourceSamplerError.unavailable(
        "invalid child process identifier \(processIdentifier)"
      )
    }

    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, $0)
      }
    }
    guard result == 0 else {
      throw ProcessResourceSamplerError.unavailable(
        "proc_pid_rusage failed for \(processIdentifier) with errno \(Darwin.errno)"
      )
    }
    guard let residentBytes = Int64(exactly: usage.ri_resident_size),
      let physicalFootprintBytes = Int64(exactly: usage.ri_phys_footprint)
    else {
      throw ProcessResourceSamplerError.unavailable(
        "proc_pid_rusage returned a value outside Int64"
      )
    }
    return ProcessResourceSample(
      residentBytes: residentBytes,
      physicalFootprintBytes: physicalFootprintBytes
    )
  }
}

public actor ProcessResourceSampler {
  private let processIdentifier: Int32
  private let interval: Duration
  private let provider: any ProcessResourceSamplerProvider
  private let clock: any ProcessResourceSamplerClock
  private var samplingTask: Task<Void, Never>?
  private var peaks: ProcessResourcePeaks?
  private var samplingError: ProcessResourceSamplerError?
  private var started = false
  private var stopped = false

  public init(
    processIdentifier: Int32,
    interval: Duration = .milliseconds(100),
    provider: any ProcessResourceSamplerProvider = DarwinProcessResourceSamplerProvider(),
    clock: any ProcessResourceSamplerClock = ContinuousProcessResourceSamplerClock()
  ) {
    self.processIdentifier = processIdentifier
    self.interval = interval
    self.provider = provider
    self.clock = clock
  }

  deinit {
    samplingTask?.cancel()
  }

  public func start() async throws {
    guard !started else {
      throw ProcessResourceSamplerError.alreadyStarted
    }
    guard interval > .zero else {
      throw ProcessResourceSamplerError.invalidInterval
    }

    let initialSample = try sample()
    try Self.validate(initialSample)
    peaks = ProcessResourcePeaks(
      peakResidentBytes: initialSample.residentBytes,
      peakPhysicalFootprintBytes: initialSample.physicalFootprintBytes
    )
    started = true

    let processIdentifier = self.processIdentifier
    let interval = self.interval
    let provider = self.provider
    let clock = self.clock
    samplingTask = Task.detached { [weak self, processIdentifier, interval, provider, clock] in
      do {
        while !Task.isCancelled {
          guard self != nil else { return }
          try await clock.sleep(for: interval)
          try Task.checkCancellation()
          let sample = try provider.sample(processIdentifier: processIdentifier)
          try Self.validate(sample)
          guard let self else { return }
          await self.record(sample)
        }
      } catch is CancellationError {
      } catch let error as ProcessResourceSamplerError {
        await self?.record(error: error)
      } catch {
        await self?.record(error: .providerFailure(String(describing: error)))
      }
    }
  }

  public func stop() async throws -> ProcessResourcePeaks {
    guard started else {
      throw ProcessResourceSamplerError.notStarted
    }
    guard !stopped else {
      throw ProcessResourceSamplerError.alreadyStopped
    }
    stopped = true
    samplingTask?.cancel()
    if let samplingTask {
      await samplingTask.value
    }
    self.samplingTask = nil
    if let samplingError {
      throw samplingError
    }
    guard let peaks else {
      throw ProcessResourceSamplerError.unavailable("no resource samples captured")
    }
    return peaks
  }

  private func sample() throws -> ProcessResourceSample {
    do {
      return try provider.sample(processIdentifier: processIdentifier)
    } catch let error as ProcessResourceSamplerError {
      throw error
    } catch {
      throw ProcessResourceSamplerError.providerFailure(String(describing: error))
    }
  }

  private static func validate(_ sample: ProcessResourceSample) throws {
    guard sample.residentBytes >= 0, sample.physicalFootprintBytes >= 0 else {
      throw ProcessResourceSamplerError.invalidSample(
        residentBytes: sample.residentBytes,
        physicalFootprintBytes: sample.physicalFootprintBytes
      )
    }
  }

  private func record(_ sample: ProcessResourceSample) {
    guard let peaks else { return }
    self.peaks = ProcessResourcePeaks(
      peakResidentBytes: max(peaks.peakResidentBytes, sample.residentBytes),
      peakPhysicalFootprintBytes: max(
        peaks.peakPhysicalFootprintBytes,
        sample.physicalFootprintBytes
      )
    )
  }

  private func record(error: ProcessResourceSamplerError) {
    samplingError = error
  }
}
