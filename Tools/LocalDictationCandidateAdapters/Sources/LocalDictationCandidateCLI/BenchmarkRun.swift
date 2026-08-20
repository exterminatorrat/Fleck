import Foundation
import LocalDictationCandidateProtocol

struct MeasurementArtifact: Codable, Sendable {
  let name: String
  let value: Double
  let unit: String
}

let maximumMeasurementArtifacts = 256

struct PartialTranscriptObservation: Codable, Equatable, Sendable {
  let sequence: Int
  let transcript: String
}

struct BenchmarkRunMetrics: Codable, Sendable {
  let finalTranscript: String?
  let partialObservations: [PartialTranscriptObservation]
  let measurementArtifacts: [MeasurementArtifact]
  let requestToFirstPartialMilliseconds: Double?
  let fileDecodeMilliseconds: Double?
  let audioDurationMilliseconds: Double?
  let realTimeFactor: Double?
}

enum BenchmarkRunError: Error, Equatable, Sendable, CustomStringConvertible {
  case partialSequenceNotIncreasing
  case duplicateFinal
  case duplicateAudioDuration

  var description: String {
    switch self {
    case .partialSequenceNotIncreasing: return "partial-sequence-not-increasing"
    case .duplicateFinal: return "duplicate-final"
    case .duplicateAudioDuration: return "duplicate-audio-duration"
    }
  }
}

struct BenchmarkRun: Sendable {
  private(set) var partialObservations: [PartialTranscriptObservation] = []
  private(set) var finalTranscript: String?
  private(set) var measurementArtifacts: [MeasurementArtifact] = []
  private var lastPartialSequence: Int?
  private var firstPartialAt: ContinuousClock.Instant?
  private var audioDurationMeasurementCount = 0
  private var audioDurationMilliseconds: Double?

  mutating func observe(
    _ event: CandidateAdapterEvent,
    receivedAt: ContinuousClock.Instant
  ) throws {
    switch event {
    case .partial(_, let sequence, let transcript):
      if let lastPartialSequence, sequence <= lastPartialSequence {
        throw BenchmarkRunError.partialSequenceNotIncreasing
      }
      lastPartialSequence = sequence
      partialObservations.append(
        PartialTranscriptObservation(sequence: sequence, transcript: transcript)
      )
      firstPartialAt = firstPartialAt ?? receivedAt
    case .final(_, let transcript):
      guard finalTranscript == nil else {
        throw BenchmarkRunError.duplicateFinal
      }
      finalTranscript = transcript
    case .measurement(_, let name, let value, let unit):
      measurementArtifacts.append(MeasurementArtifact(name: name, value: value, unit: unit))
      guard Self.isAudioDurationMeasurement(name: name, unit: unit) else { return }
      audioDurationMeasurementCount += 1
      guard audioDurationMeasurementCount == 1 else {
        throw BenchmarkRunError.duplicateAudioDuration
      }
      if value.isFinite, value > 0 {
        audioDurationMilliseconds = value
      }
    case .ready, .cancelled, .unloaded, .failure:
      break
    }
  }

  func metrics(
    requestStartedAt: ContinuousClock.Instant,
    terminalAt: ContinuousClock.Instant,
    cancelled: Bool
  ) -> BenchmarkRunMetrics {
    let fileDecodeMilliseconds = Self.elapsedMilliseconds(
      from: requestStartedAt,
      to: terminalAt
    )
    let requestToFirstPartialMilliseconds = firstPartialAt.flatMap {
      Self.elapsedMilliseconds(from: requestStartedAt, to: $0)
    }
    let realTimeFactor: Double?
    if !cancelled,
      let fileDecodeMilliseconds,
      fileDecodeMilliseconds > 0,
      let audioDurationMilliseconds,
      audioDurationMilliseconds > 0
    {
      let value = fileDecodeMilliseconds / audioDurationMilliseconds
      realTimeFactor = value.isFinite ? value : nil
    } else {
      realTimeFactor = nil
    }
    return BenchmarkRunMetrics(
      finalTranscript: cancelled ? nil : finalTranscript,
      partialObservations: partialObservations,
      measurementArtifacts: measurementArtifacts,
      requestToFirstPartialMilliseconds: requestToFirstPartialMilliseconds,
      fileDecodeMilliseconds: fileDecodeMilliseconds,
      audioDurationMilliseconds: audioDurationMilliseconds,
      realTimeFactor: realTimeFactor
    )
  }

  private static func isAudioDurationMeasurement(name: String, unit: String) -> Bool {
    let normalizedName = name.lowercased().filter { $0.isLetter || $0.isNumber }
    let normalizedUnit = unit.lowercased().filter { $0.isLetter || $0.isNumber }
    return ["audioduration", "audiodurationmilliseconds", "audiodurationms"].contains(normalizedName)
      && ["ms", "millisecond", "milliseconds"].contains(normalizedUnit)
  }

  private static func elapsedMilliseconds(
    from start: ContinuousClock.Instant,
    to end: ContinuousClock.Instant
  ) -> Double? {
    let components = start.duration(to: end).components
    let milliseconds = Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    guard milliseconds.isFinite, milliseconds >= 0 else { return nil }
    return milliseconds
  }
}
