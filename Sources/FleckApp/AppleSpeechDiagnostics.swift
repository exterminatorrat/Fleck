import AVFAudio
import Foundation
import os

enum AppleSpeechDiagnosticStage: String, Sendable {
  case permission
  case sessionConstruction
  case deviceSupport
  case supportedLocale
  case inputFormat
  case reservation
  case reservedStatus
  case bestFormat
  case analyzerPrepare
  case converter
  case tapInstallation
  case enginePrepare
  case engineStart
  case analyzerStart
  case firstInputBuffer
  case firstConversion
  case resultsTermination
  case finish
  case cancel
  case reservationRelease
  case release
}

enum AppleSpeechDiagnosticMarker: String, Sendable {
  case begin
  case success
  case failure
  case cancelled
}

enum AppleSpeechDiagnosticPCMFormat: String, Sendable {
  case float32
  case float64
  case int16
  case int32
  case other
}

struct AppleSpeechDiagnosticReceipt: Equatable, Sendable {
  let attempt: Int
  let stage: AppleSpeechDiagnosticStage
  let marker: AppleSpeechDiagnosticMarker
  let elapsedMilliseconds: Int64
  let errorDomain: String?
  let errorCode: Int?
  let sampleRate: Double?
  let channelCount: UInt32?
  let pcmFormat: AppleSpeechDiagnosticPCMFormat?
  let interleaved: Bool?
  let reservationOwned: Bool?
  let assetStatus: AppleSpeechAssetStatus?
  let bufferCount: UInt16?
  let firstFrameLengthZero: Bool?
}

struct AppleSpeechDiagnosticFormat: Equatable, Sendable {
  let sampleRate: Double
  let channelCount: UInt32
  let pcmFormat: AppleSpeechDiagnosticPCMFormat
  let interleaved: Bool

  init(_ format: AVAudioFormat) {
    sampleRate = format.sampleRate
    channelCount = format.channelCount
    pcmFormat =
      switch format.commonFormat {
      case .pcmFormatFloat32: .float32
      case .pcmFormatFloat64: .float64
      case .pcmFormatInt16: .int16
      case .pcmFormatInt32: .int32
      case .otherFormat: .other
      @unknown default: .other
      }
    interleaved = format.isInterleaved
  }
}

struct AppleSpeechTapObservation: Equatable, Sendable {
  let bufferCount: UInt16
  let firstFrameLengthZero: Bool
  let elapsedMilliseconds: Int64
}

final class AppleSpeechDiagnostics: @unchecked Sendable {
  static let environmentKey = "FLECK_APPLE_SPEECH_DIAGNOSTICS"
  static let maximumReceiptCount = 64

  private static let logger = Logger(
    subsystem: "com.harryjin.fleck",
    category: "AppleSpeechDiagnostics"
  )

  private let attempt: Int
  private let startUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
  private let sink: @Sendable (AppleSpeechDiagnosticReceipt) -> Void
  private let receiptLock = NSLock()
  private let exportLock = NSLock()
  private var receipts: [AppleSpeechDiagnosticReceipt] = []
  private var firstFault: AppleSpeechDiagnosticReceipt?
  private var exportedReceiptCount = 0
  private let tapLock = NSLock()
  private var tapBufferCount: UInt16 = 0
  private var firstFrameLengthZero: Bool?
  private var firstBufferElapsedMilliseconds: Int64?
  private var didDrainTapObservation = false

  init(
    attempt: Int,
    sink: @escaping @Sendable (AppleSpeechDiagnosticReceipt) -> Void = AppleSpeechDiagnostics.log
  ) {
    self.attempt = attempt
    self.sink = sink
    receipts.reserveCapacity(Self.maximumReceiptCount)
  }

  static var isEnabledInEnvironment: Bool {
    isEnabled(ProcessInfo.processInfo.environment[environmentKey])
  }

  static func isEnabled(_ value: String?) -> Bool {
    value == "1"
  }

  func record(
    _ stage: AppleSpeechDiagnosticStage,
    _ marker: AppleSpeechDiagnosticMarker,
    error: Error? = nil,
    elapsedMilliseconds: Int64? = nil,
    format: AppleSpeechDiagnosticFormat? = nil,
    reservationOwned: Bool? = nil,
    assetStatus: AppleSpeechAssetStatus? = nil,
    bufferCount: UInt16? = nil,
    firstFrameLengthZero: Bool? = nil
  ) {
    receiptLock.lock()
    defer { receiptLock.unlock() }
    if receipts.count == Self.maximumReceiptCount, marker != .failure {
      return
    }

    let underlyingError = error.map { $0 as NSError }
    let receipt = AppleSpeechDiagnosticReceipt(
      attempt: attempt,
      stage: stage,
      marker: marker,
      elapsedMilliseconds: elapsedMilliseconds
        ?? Self.elapsedMilliseconds(
          since: startUptimeNanoseconds
        ),
      errorDomain: underlyingError.map { Self.sanitizedDomain($0.domain) },
      errorCode: underlyingError?.code,
      sampleRate: format?.sampleRate,
      channelCount: format?.channelCount,
      pcmFormat: format?.pcmFormat,
      interleaved: format?.interleaved,
      reservationOwned: reservationOwned,
      assetStatus: assetStatus,
      bufferCount: bufferCount,
      firstFrameLengthZero: firstFrameLengthZero
    )
    if marker == .failure, firstFault == nil {
      firstFault = receipt
    }
    let capacity = firstFault == nil ? Self.maximumReceiptCount - 1 : Self.maximumReceiptCount
    guard receipts.count < capacity else { return }
    receipts.append(receipt)
  }

  func recordFailure(_ stage: AppleSpeechDiagnosticStage, error: Error) {
    if error is CancellationError {
      record(stage, .cancelled)
    } else {
      record(stage, .failure, error: error)
    }
  }

  var snapshot: [AppleSpeechDiagnosticReceipt] {
    receiptLock.withLock { receipts }
  }

  var firstFaultReceipt: AppleSpeechDiagnosticReceipt? {
    receiptLock.withLock { firstFault }
  }

  func observeTapBuffer(frameLength: AVAudioFrameCount) {
    guard tapLock.try() else { return }
    defer { tapLock.unlock() }
    if firstFrameLengthZero == nil {
      firstFrameLengthZero = frameLength == 0
      firstBufferElapsedMilliseconds = Self.elapsedMilliseconds(since: startUptimeNanoseconds)
    }
    if tapBufferCount < .max {
      tapBufferCount += 1
    }
  }

  func drainTapObservation() -> AppleSpeechTapObservation? {
    tapLock.lock()
    defer { tapLock.unlock() }
    guard !didDrainTapObservation else { return nil }
    didDrainTapObservation = true
    return tapObservationLocked()
  }

  func tapObservation() -> AppleSpeechTapObservation? {
    tapLock.lock()
    defer { tapLock.unlock() }
    return tapObservationLocked()
  }

  private func tapObservationLocked() -> AppleSpeechTapObservation? {
    guard tapBufferCount > 0, let firstFrameLengthZero else { return nil }
    return AppleSpeechTapObservation(
      bufferCount: tapBufferCount,
      firstFrameLengthZero: firstFrameLengthZero,
      elapsedMilliseconds: firstBufferElapsedMilliseconds ?? 0
    )
  }

  func export() {
    exportLock.withLock {
      let newReceipts = receiptLock.withLock { () -> [AppleSpeechDiagnosticReceipt] in
        let newReceipts = Array(receipts.dropFirst(exportedReceiptCount))
        exportedReceiptCount = receipts.count
        return newReceipts
      }
      newReceipts.forEach(sink)
    }
  }

  private static func sanitizedDomain(_ domain: String) -> String {
    switch domain {
    case NSCocoaErrorDomain, NSOSStatusErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain,
      "AVFoundationErrorDomain":
      return domain
    default:
      return "redacted"
    }
  }

  static func log(_ receipt: AppleSpeechDiagnosticReceipt) {
    let domain = receipt.errorDomain ?? "-"
    let code = receipt.errorCode.map { String($0) } ?? "-"
    let sampleRate = receipt.sampleRate.map { String($0) } ?? "-"
    let channelCount = receipt.channelCount.map { String($0) } ?? "-"
    let pcmFormat = receipt.pcmFormat?.rawValue ?? "-"
    let interleaved = receipt.interleaved.map { $0 ? "true" : "false" } ?? "-"
    let reservationOwned = receipt.reservationOwned.map { $0 ? "true" : "false" } ?? "-"
    let assetStatus = receipt.assetStatus.map { String(describing: $0) } ?? "-"
    let bufferCount = receipt.bufferCount.map { String($0) } ?? "-"
    let firstFrameLengthZero = receipt.firstFrameLengthZero.map { $0 ? "true" : "false" } ?? "-"
    let message =
      "attempt=\(receipt.attempt) stage=\(receipt.stage.rawValue) "
      + "marker=\(receipt.marker.rawValue) elapsed_ms=\(receipt.elapsedMilliseconds) "
      + "error_domain=\(domain) error_code=\(code) sample_rate=\(sampleRate) "
      + "channels=\(channelCount) pcm=\(pcmFormat) interleaved=\(interleaved) "
      + "reservation_owned=\(reservationOwned) asset_status=\(assetStatus) "
      + "buffer_count=\(bufferCount) first_frame_length_zero=\(firstFrameLengthZero)"
    logger.info("\(message, privacy: .public)")
  }

  private static func elapsedMilliseconds(since startUptime: UInt64) -> Int64 {
    let now = DispatchTime.now().uptimeNanoseconds
    return Int64(now >= startUptime ? (now - startUptime) / 1_000_000 : 0)
  }
}
