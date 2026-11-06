@preconcurrency import AVFAudio
import Foundation
import Testing

@testable import FleckApp

@Test func appleSpeechDiagnosticsCaptureOnlyBoundedSanitizedFirstFault() {
  let diagnostics = AppleSpeechDiagnostics(attempt: 3, sink: { _ in })
  let privateValue = "transcription must not appear"
  diagnostics.record(.permission, .begin)
  diagnostics.record(
    .reservation,
    .failure,
    error: NSError(
      domain: "com.example.speech",
      code: 41,
      userInfo: [NSLocalizedDescriptionKey: privateValue]
    )
  )
  diagnostics.record(
    .engineStart,
    .failure,
    error: NSError(
      domain: "/private/user/device",
      code: 42,
      userInfo: [NSLocalizedDescriptionKey: "private device name"]
    )
  )
  diagnostics.record(
    .release,
    .failure,
    error: NSError(domain: String(repeating: "a", count: 65), code: 43)
  )

  let receipts = diagnostics.snapshot
  #expect(diagnostics.firstFaultReceipt == receipts[1])
  #expect(receipts[1].errorDomain == "redacted")
  #expect(receipts[1].errorCode == 41)
  #expect(receipts[2].errorDomain == "redacted")
  #expect(receipts[2].errorCode == 42)
  #expect(receipts[3].errorDomain == "redacted")
  #expect(receipts[3].errorCode == 43)
  #expect(!String(reflecting: receipts).contains(privateValue))
  #expect(!String(reflecting: receipts).contains("private device name"))
  #expect(!String(reflecting: receipts).contains("com.example.speech"))
}

@Test func appleSpeechDiagnosticsRetainOnlyKnownFixedFrameworkDomains() {
  let diagnostics = AppleSpeechDiagnostics(attempt: 10, sink: { _ in })
  let knownDomains = [
    NSCocoaErrorDomain, NSOSStatusErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain,
    "AVFoundationErrorDomain",
  ]
  let unknownDomains = [
    "DeviceIdentifier123", "user.example", "com.apple.speech.asset-reservation",
    "", String(repeating: "a", count: 65),
  ]
  for domain in knownDomains + unknownDomains {
    diagnostics.record(.sessionConstruction, .failure, error: NSError(domain: domain, code: 42))
  }

  let receipts = diagnostics.snapshot
  #expect(Array(receipts.prefix(knownDomains.count).compactMap(\.errorDomain)) == knownDomains)
  #expect(receipts.dropFirst(knownDomains.count).allSatisfy { $0.errorDomain == "redacted" })
  #expect(receipts.count == knownDomains.count + unknownDomains.count)
  #expect(receipts.allSatisfy { $0.errorCode == 42 })
  #expect(!String(reflecting: receipts).contains("DeviceIdentifier123"))
  #expect(!String(reflecting: receipts).contains("user.example"))
}

@Test func appleSpeechDiagnosticsRemainBoundedAndRetainFirstFaultAtCapacity() {
  let diagnostics = AppleSpeechDiagnostics(attempt: 4, sink: { _ in })
  for _ in 0..<AppleSpeechDiagnostics.maximumReceiptCount {
    diagnostics.record(.permission, .begin)
  }

  diagnostics.record(
    .engineStart,
    .failure,
    error: NSError(domain: "com.example.audio", code: 7)
  )

  #expect(diagnostics.snapshot.count == AppleSpeechDiagnostics.maximumReceiptCount)
  #expect(diagnostics.firstFaultReceipt == diagnostics.snapshot.last)
  #expect(diagnostics.firstFaultReceipt?.stage == .engineStart)
}

@Test func appleSpeechDiagnosticsIncrementallyExportLateFirstFaultWithinCapacity() {
  let collector = DiagnosticReceiptCollector()
  let diagnostics = AppleSpeechDiagnostics(attempt: 9, sink: { collector.append($0) })
  for _ in 0..<AppleSpeechDiagnostics.maximumReceiptCount {
    diagnostics.record(.permission, .begin)
  }

  diagnostics.export()
  let earlyReceipts = collector.receipts
  #expect(diagnostics.snapshot.count == AppleSpeechDiagnostics.maximumReceiptCount - 1)
  #expect(earlyReceipts == diagnostics.snapshot)

  diagnostics.record(
    .reservation,
    .failure,
    error: NSError(domain: "com.apple.speech.asset-reservation", code: 87)
  )
  diagnostics.export()
  let receiptsWithLateFault = collector.receipts
  diagnostics.export()
  diagnostics.record(.finish, .success)
  diagnostics.export()

  #expect(receiptsWithLateFault.count == AppleSpeechDiagnostics.maximumReceiptCount)
  #expect(diagnostics.snapshot.count == AppleSpeechDiagnostics.maximumReceiptCount)
  #expect(collector.receipts == receiptsWithLateFault)
  #expect(receiptsWithLateFault.last?.stage == .reservation)
  #expect(receiptsWithLateFault.last?.errorDomain == "redacted")
  #expect(receiptsWithLateFault.last?.errorCode == 87)
}

@Test func appleSpeechDiagnosticsRecordMonotonicFirstBufferAndFormatScalars() throws {
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16_000,
      channels: 1,
      interleaved: true
    )
  )
  let snapshot = AppleSpeechDiagnosticFormat(format)
  let diagnostics = AppleSpeechDiagnostics(attempt: 5, sink: { _ in })

  diagnostics.observeTapBuffer(frameLength: 0)
  diagnostics.observeTapBuffer(frameLength: 64)
  let tap = try #require(diagnostics.drainTapObservation())
  diagnostics.record(
    .inputFormat,
    .success,
    format: snapshot
  )
  diagnostics.record(
    .firstInputBuffer,
    .success,
    elapsedMilliseconds: tap.elapsedMilliseconds,
    bufferCount: tap.bufferCount,
    firstFrameLengthZero: tap.firstFrameLengthZero
  )

  #expect(snapshot.sampleRate == 16_000)
  #expect(snapshot.channelCount == 1)
  #expect(snapshot.pcmFormat == .int16)
  #expect(snapshot.interleaved)
  #expect(tap.bufferCount == 2)
  #expect(tap.firstFrameLengthZero)
  #expect(tap.elapsedMilliseconds >= 0)
  #expect(diagnostics.drainTapObservation() == nil)
}

@Test func appleSpeechDiagnosticsRequireExactOptInValue() {
  #expect(!AppleSpeechDiagnostics.isEnabled(nil))
  #expect(!AppleSpeechDiagnostics.isEnabled("0"))
  #expect(!AppleSpeechDiagnostics.isEnabled("true"))
  #expect(AppleSpeechDiagnostics.isEnabled("1"))
}

@Test func appleSpeechReservationFailurePreservesOriginalErrorBeforeMasking() async {
  let diagnostics = AppleSpeechDiagnostics(attempt: 1, sink: { _ in })
  let originalError = NSError(
    domain: "com.apple.speech.asset-reservation",
    code: 87,
    userInfo: [NSLocalizedDescriptionKey: "private transcription payload"]
  )
  let readiness = AppleSpeechAssetReadiness(
    equivalentLocale: { _ in nil },
    reserveLocale: { _ in throw originalError },
    releaseLocale: { _ in }
  )

  await #expect(throws: DictationFailure.unavailable) {
    try await readiness.reserveAndVerify(
      locale: Locale(identifier: "en-US"),
      status: { .installed },
      diagnostics: diagnostics
    )
  }

  let receipts = diagnostics.snapshot
  #expect(receipts.map(\.stage) == [.reservation, .reservation])
  #expect(receipts.map(\.marker) == [.begin, .failure])
  #expect(diagnostics.firstFaultReceipt?.errorDomain == "redacted")
  #expect(diagnostics.firstFaultReceipt?.errorCode == 87)
  #expect(!String(reflecting: receipts).contains("private transcription payload"))
}

@Test func appleSpeechReservationTraceKeepsExactStatusAndOwnedReleaseCount() async {
  let releaseProbe = ReservationReleaseProbe()
  let diagnostics = AppleSpeechDiagnostics(attempt: 2, sink: { _ in })
  let readiness = AppleSpeechAssetReadiness(
    equivalentLocale: { _ in nil },
    reserveLocale: { _ in true },
    releaseLocale: { _ in await releaseProbe.release() }
  )

  await #expect(throws: DictationFailure.unavailable) {
    try await readiness.reserveAndVerify(
      locale: Locale(identifier: "en-US"),
      status: { .supported },
      diagnostics: diagnostics
    )
  }

  let status = diagnostics.snapshot.first {
    $0.stage == .reservedStatus && $0.marker == .failure
  }
  #expect(status?.assetStatus == .supported)
  #expect(status?.reservationOwned == true)
  #expect(await releaseProbe.count == 1)
  #expect(
    diagnostics.snapshot.filter { $0.stage == .reservationRelease }.map(\.marker)
      == [.begin, .success]
  )
}

@Test func appleSpeechReservationTraceDistinguishesInstalledPreexistingAssets() async throws {
  let releaseProbe = ReservationReleaseProbe()
  let diagnostics = AppleSpeechDiagnostics(attempt: 8, sink: { _ in })
  let readiness = AppleSpeechAssetReadiness(
    equivalentLocale: { _ in nil },
    reserveLocale: { _ in false },
    releaseLocale: { _ in await releaseProbe.release() }
  )

  let reservation = try await readiness.reserveAndVerify(
    locale: Locale(identifier: "en-US"),
    status: { .installed },
    diagnostics: diagnostics
  )
  await readiness.release(reservation, diagnostics: diagnostics)

  let status = try #require(
    diagnostics.snapshot.first {
      $0.stage == .reservedStatus && $0.marker == .success
    }
  )
  #expect(status.marker == .success)
  #expect(status.assetStatus == .installed)
  #expect(status.reservationOwned == false)
  #expect(await releaseProbe.count == 0)
  #expect(!diagnostics.snapshot.contains { $0.stage == .reservationRelease })
}

@Test func appleSpeechReservationCancellationReleasesOnlyItsOwnedReservation() async {
  let continueProbe = ReservationContinueProbe()
  let releaseProbe = ReservationReleaseProbe()
  let diagnostics = AppleSpeechDiagnostics(attempt: 6, sink: { _ in })
  let readiness = AppleSpeechAssetReadiness(
    equivalentLocale: { _ in nil },
    reserveLocale: { _ in true },
    releaseLocale: { _ in await releaseProbe.release() }
  )

  await #expect(throws: CancellationError.self) {
    try await readiness.reserveAndVerify(
      locale: Locale(identifier: "en-US"),
      status: { .installed },
      shouldContinue: { await continueProbe.shouldContinue() },
      diagnostics: diagnostics
    )
  }

  #expect(await releaseProbe.count == 1)
  #expect(diagnostics.firstFaultReceipt == nil)
  #expect(
    diagnostics.snapshot.map(\.marker) == [
      .begin,
      .success,
      .cancelled,
      .begin,
      .success,
    ])
}

@Test @MainActor func appleSpeechDiagnosticsSeparateCancelledRetryAndExcludeTranscript()
  async throws
{
  let collector = DiagnosticReceiptCollector()
  let sessionFactory = DiagnosticSessionFactory(
    sessions: [
      DiagnosticSessionProbe(cancelsOnStart: true),
      DiagnosticSessionProbe(cancelsOnStart: false),
    ]
  )
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { await sessionFactory.makeSession() },
    diagnosticsEnabled: true,
    diagnosticSink: { collector.append($0) }
  )

  await #expect(throws: CancellationError.self) {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  try await capture.start(provisional: { _ in }, level: { _ in })
  #expect(try await capture.finish() == "private transcript never enters the trace")

  let receipts = collector.receipts
  let attempts = Array(Set(receipts.map(\.attempt))).sorted()
  let firstOrdinal = try #require(attempts.first)
  let secondOrdinal = try #require(attempts.dropFirst().first)
  let firstAttempt = receipts.filter { $0.attempt == firstOrdinal }
  let secondAttempt = receipts.filter { $0.attempt == secondOrdinal }
  #expect(firstAttempt.contains { $0.stage == .analyzerStart && $0.marker == .cancelled })
  #expect(firstAttempt.contains { $0.stage == .release && $0.marker == .success })
  #expect(secondAttempt.contains { $0.stage == .analyzerStart && $0.marker == .success })
  #expect(secondAttempt.contains { $0.stage == .finish && $0.marker == .success })
  #expect(secondAttempt.contains { $0.stage == .release && $0.marker == .success })
  #expect(attempts.count == 2)
  #expect(secondOrdinal > firstOrdinal)
  #expect(!String(reflecting: receipts).contains("private transcript never enters the trace"))
}

@Test @MainActor func appleSpeechDiagnosticsIgnoreLateCancelledStartForRetryTrace() async throws {
  let collector = DiagnosticReceiptCollector()
  let gate = DiagnosticSessionStartGate()
  let sessionFactory = DiagnosticSessionFactory(
    sessions: [
      DiagnosticSessionProbe(cancelsOnStart: true, startGate: gate),
      DiagnosticSessionProbe(cancelsOnStart: false),
    ]
  )
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { await sessionFactory.makeSession() },
    diagnosticsEnabled: true,
    diagnosticSink: { collector.append($0) }
  )

  let oldStart = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await gate.waitUntilEntered()
  await capture.cancel()
  let oldAttempt = try #require(collector.receipts.first?.attempt)

  try await capture.start(provisional: { _ in }, level: { _ in })
  await gate.open()
  await #expect(throws: CancellationError.self) {
    try await oldStart.value
  }

  let receiptsAfterOldCompletion = collector.receipts
  #expect(receiptsAfterOldCompletion.allSatisfy { $0.attempt == oldAttempt })
  #expect(
    receiptsAfterOldCompletion.contains {
      $0.attempt == oldAttempt && $0.stage == .cancel && $0.marker == .cancelled
    }
  )

  _ = try await capture.finish()
  let retryReceipts = collector.receipts.filter { $0.attempt != oldAttempt }
  #expect(!retryReceipts.isEmpty)
  #expect(retryReceipts.contains { $0.stage == .analyzerStart && $0.marker == .success })
  #expect(retryReceipts.contains { $0.stage == .finish && $0.marker == .success })
  #expect(retryReceipts.contains { $0.stage == .release && $0.marker == .success })
  #expect(!retryReceipts.contains { $0.stage == .cancel })
}

@Test @MainActor func appleSpeechDiagnosticsBindPendingStartsWhenTheirSessionsActivate() async throws {
  let collector = DiagnosticReceiptCollector()
  let firstPermission = DiagnosticPermissionGate()
  let secondPermission = DiagnosticPermissionGate()
  let permissions = DiagnosticPermissionRequests(gates: [firstPermission, secondPermission])
  let sessionFactory = DiagnosticSessionFactory(
    sessions: [
      DiagnosticSessionProbe(cancelsOnStart: false),
      DiagnosticSessionProbe(cancelsOnStart: false),
    ]
  )
  let capture = AppleSpeechCapture(
    requestPermission: { await permissions.request() },
    makeSession: { await sessionFactory.makeSession() },
    diagnosticsEnabled: true,
    diagnosticSink: { collector.append($0) }
  )

  let firstStart = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await firstPermission.waitUntilRequested()
  let secondStart = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await secondPermission.waitUntilRequested()
  await firstPermission.grant()
  try await firstStart.value
  await capture.cancel()
  let receiptsAfterFirstCancellation = collector.receipts
  await secondPermission.grant()
  try await secondStart.value
  _ = try await capture.finish()

  let receipts = collector.receipts
  let firstAttempt = try #require(receiptsAfterFirstCancellation.first?.attempt)
  let secondAttempt = try #require(receipts.first { $0.attempt != firstAttempt }?.attempt)
  let firstReceipts = receipts.filter { $0.attempt == firstAttempt }
  let secondReceipts = receipts.filter { $0.attempt == secondAttempt }
  #expect(receiptsAfterFirstCancellation.allSatisfy { $0.attempt == firstAttempt })
  #expect(firstReceipts.contains { $0.stage == .permission && $0.marker == .success })
  #expect(firstReceipts.contains { $0.stage == .sessionConstruction && $0.marker == .success })
  #expect(firstReceipts.contains { $0.stage == .deviceSupport && $0.marker == .success })
  #expect(firstReceipts.contains { $0.stage == .analyzerStart && $0.marker == .success })
  #expect(firstReceipts.contains { $0.stage == .cancel && $0.marker == .success })
  #expect(firstReceipts.contains { $0.stage == .release && $0.marker == .success })
  #expect(secondReceipts.contains { $0.stage == .permission && $0.marker == .success })
  #expect(secondReceipts.contains { $0.stage == .analyzerStart && $0.marker == .success })
  #expect(secondReceipts.contains { $0.stage == .finish && $0.marker == .success })
  #expect(secondReceipts.contains { $0.stage == .release && $0.marker == .success })
  #expect(!secondReceipts.contains { $0.stage == .cancel })
}

@Test @MainActor func appleSpeechDiagnosticsExportLateReservationFailureAfterCancelAndRetry()
  async throws
{
  let collector = DiagnosticReceiptCollector()
  let reservationGate = DiagnosticReservationGate()
  let releaseProbe = ReservationReleaseProbe()
  let readiness = AppleSpeechAssetReadiness(
    equivalentLocale: { _ in nil },
    reserveLocale: { _ in try await reservationGate.reserve() },
    releaseLocale: { _ in await releaseProbe.release() }
  )
  let sessionFactory = DiagnosticSessionFactory(
    sessions: [
      GatedReservationDiagnosticSession(readiness: readiness),
      DiagnosticSessionProbe(cancelsOnStart: false),
    ]
  )
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { await sessionFactory.makeSession() },
    diagnosticsEnabled: true,
    diagnosticSink: { collector.append($0) }
  )

  let oldStart = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await reservationGate.waitUntilEntered()
  await capture.cancel()
  let receiptsAfterCancel = collector.receipts
  let oldAttempt = try #require(receiptsAfterCancel.first?.attempt)
  try await capture.start(provisional: { _ in }, level: { _ in })
  await reservationGate.fail(domain: "com.apple.speech.asset-reservation", code: 87)
  await #expect(throws: DictationFailure.unavailable.self) {
    try await oldStart.value
  }
  let receiptsAfterOldStart = collector.receipts
  #expect(receiptsAfterOldStart.allSatisfy { $0.attempt == oldAttempt })
  #expect(Array(receiptsAfterOldStart.prefix(receiptsAfterCancel.count)) == receiptsAfterCancel)
  let lateFailure = receiptsAfterOldStart.first {
    $0.attempt == oldAttempt && $0.stage == .reservation && $0.marker == .failure
  }
  #expect(lateFailure?.errorDomain == "redacted")
  #expect(lateFailure?.errorCode == 87)
  #expect(await releaseProbe.count == 0)

  _ = try await capture.finish()
  let receipts = collector.receipts
  let retryAttempt = try #require(receipts.first { $0.attempt != oldAttempt }?.attempt)
  let retryReceipts = receipts.filter { $0.attempt == retryAttempt }
  #expect(retryReceipts.contains { $0.stage == .analyzerStart && $0.marker == .success })
  #expect(retryReceipts.contains { $0.stage == .finish && $0.marker == .success })
  #expect(retryReceipts.contains { $0.stage == .release && $0.marker == .success })
  #expect(!retryReceipts.contains { $0.stage == .reservation || $0.stage == .reservationRelease })
  #expect(!retryReceipts.contains { $0.stage == .cancel })
}

@Test @MainActor func appleSpeechDiagnosticsExportLateOwnedReservationCleanupAfterCancelAndRetry()
  async throws
{
  let collector = DiagnosticReceiptCollector()
  let reservationGate = DiagnosticReservationGate()
  let releaseProbe = ReservationReleaseProbe()
  let readiness = AppleSpeechAssetReadiness(
    equivalentLocale: { _ in nil },
    reserveLocale: { _ in try await reservationGate.reserve() },
    releaseLocale: { _ in await releaseProbe.release() }
  )
  let sessionFactory = DiagnosticSessionFactory(
    sessions: [
      GatedReservationDiagnosticSession(readiness: readiness),
      DiagnosticSessionProbe(cancelsOnStart: false),
    ]
  )
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { await sessionFactory.makeSession() },
    diagnosticsEnabled: true,
    diagnosticSink: { collector.append($0) }
  )

  let oldStart = Task {
    try await capture.start(provisional: { _ in }, level: { _ in })
  }
  await reservationGate.waitUntilEntered()
  await capture.cancel()
  let receiptsAfterCancel = collector.receipts
  let oldAttempt = try #require(receiptsAfterCancel.first?.attempt)
  try await capture.start(provisional: { _ in }, level: { _ in })
  await reservationGate.complete(ownsReservation: true)
  await #expect(throws: CancellationError.self) {
    try await oldStart.value
  }
  let receiptsAfterOldStart = collector.receipts
  #expect(receiptsAfterOldStart.allSatisfy { $0.attempt == oldAttempt })
  #expect(Array(receiptsAfterOldStart.prefix(receiptsAfterCancel.count)) == receiptsAfterCancel)
  #expect(await releaseProbe.count == 1)
  #expect(
    receiptsAfterOldStart.filter {
      $0.attempt == oldAttempt && $0.stage == .reservationRelease
    }.map(\.marker) == [.begin, .success]
  )

  _ = try await capture.finish()
  let receipts = collector.receipts
  let retryAttempt = try #require(receipts.first { $0.attempt != oldAttempt }?.attempt)
  let retryReceipts = receipts.filter { $0.attempt == retryAttempt }
  #expect(retryReceipts.contains { $0.stage == .analyzerStart && $0.marker == .success })
  #expect(retryReceipts.contains { $0.stage == .finish && $0.marker == .success })
  #expect(retryReceipts.contains { $0.stage == .release && $0.marker == .success })
  #expect(!retryReceipts.contains { $0.stage == .reservation || $0.stage == .reservationRelease })
  #expect(!retryReceipts.contains { $0.stage == .cancel })
}

@Test @MainActor func appleSpeechDiagnosticsOffDoesNotAttachOrExportATrace() async throws {
  let collector = DiagnosticReceiptCollector()
  let session = DiagnosticSessionProbe(cancelsOnStart: false)
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { session },
    diagnosticsEnabled: false,
    diagnosticSink: { collector.append($0) }
  )

  try await capture.start(provisional: { _ in }, level: { _ in })
  _ = try await capture.finish()

  #expect(await session.configurationCount == 0)
  #expect(collector.receipts.isEmpty)
}

@Test @MainActor func appleSpeechDiagnosticsBalanceOverlappingResourceReleaseReceipts() async throws {
  let collector = DiagnosticReceiptCollector()
  let releaseGate = DiagnosticReleaseGate()
  let session = DiagnosticSessionProbe(cancelsOnStart: false, releaseGate: releaseGate)
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { session },
    diagnosticsEnabled: true,
    diagnosticSink: { collector.append($0) }
  )
  try await capture.start(provisional: { _ in }, level: { _ in })

  let firstRelease = Task { await capture.releaseResources() }
  await releaseGate.waitUntilEntered(count: 1)
  let secondRelease = Task { await capture.releaseResources() }
  await releaseGate.waitUntilEntered(count: 2)
  await releaseGate.open()
  await firstRelease.value
  await secondRelease.value

  let releases = collector.receipts.filter { $0.stage == .release }
  #expect(releases.filter { $0.marker == .begin }.count == 2)
  #expect(releases.filter { $0.marker == .success }.count == 2)
  #expect(Set(releases.map(\.attempt)).count == 1)
}

private final class DiagnosticReceiptCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [AppleSpeechDiagnosticReceipt] = []

  func append(_ receipt: AppleSpeechDiagnosticReceipt) {
    lock.withLock { storage.append(receipt) }
  }

  var receipts: [AppleSpeechDiagnosticReceipt] {
    lock.withLock { storage }
  }
}

private actor DiagnosticSessionFactory {
  private var sessions: [any AppleSpeechSession]
  private var nextSession = 0

  init(sessions: [any AppleSpeechSession]) {
    self.sessions = sessions
  }

  func makeSession() -> any AppleSpeechSession {
    defer { nextSession += 1 }
    return sessions[nextSession]
  }
}

private actor ReservationReleaseProbe {
  private(set) var count = 0

  func release() {
    count += 1
  }
}

private actor ReservationContinueProbe {
  private var checks = 0

  func shouldContinue() -> Bool {
    checks += 1
    return checks == 1
  }
}

private actor DiagnosticPermissionGate {
  private var isRequested = false
  private var requestContinuation: CheckedContinuation<DictationPermissionResult, Never>?
  private var requestedContinuation: CheckedContinuation<Void, Never>?

  func request() async -> DictationPermissionResult {
    isRequested = true
    requestedContinuation?.resume()
    requestedContinuation = nil
    return await withCheckedContinuation { requestContinuation = $0 }
  }

  func waitUntilRequested() async {
    guard !isRequested else { return }
    await withCheckedContinuation { requestedContinuation = $0 }
  }

  func grant() {
    requestContinuation?.resume(returning: .granted)
    requestContinuation = nil
  }
}

private actor DiagnosticPermissionRequests {
  private let gates: [DiagnosticPermissionGate]
  private var nextGate = 0

  init(gates: [DiagnosticPermissionGate]) {
    self.gates = gates
  }

  func request() async -> DictationPermissionResult {
    let gate = gates[nextGate]
    nextGate += 1
    return await gate.request()
  }
}

private actor DiagnosticReservationGate {
  private var isEntered = false
  private var reservationContinuation: CheckedContinuation<Bool, any Error>?
  private var enteredContinuation: CheckedContinuation<Void, Never>?

  func reserve() async throws -> Bool {
    isEntered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    return try await withCheckedThrowingContinuation {
      reservationContinuation = $0
    }
  }

  func waitUntilEntered() async {
    guard !isEntered else { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func complete(ownsReservation: Bool) {
    reservationContinuation?.resume(returning: ownsReservation)
    reservationContinuation = nil
  }

  func fail(domain: String, code: Int) {
    reservationContinuation?.resume(throwing: NSError(domain: domain, code: code))
    reservationContinuation = nil
  }
}

private actor DiagnosticSessionStartGate {
  private var isEntered = false
  private var isOpen = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var openContinuation: CheckedContinuation<Void, Never>?

  func wait() async {
    guard !isOpen else { return }
    isEntered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    await withCheckedContinuation { openContinuation = $0 }
  }

  func waitUntilEntered() async {
    guard !isEntered else { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func open() {
    isOpen = true
    openContinuation?.resume()
    openContinuation = nil
  }
}

private actor GatedReservationDiagnosticSession: AppleSpeechDiagnosticSession {
  private let readiness: AppleSpeechAssetReadiness
  private var diagnostics: AppleSpeechDiagnostics?
  private var cancelled = false

  var supportsOnDeviceRecognition: Bool { true }

  init(readiness: AppleSpeechAssetReadiness) {
    self.readiness = readiness
  }

  func configureDiagnostics(_ diagnostics: AppleSpeechDiagnostics) {
    self.diagnostics = diagnostics
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    _ = try await readiness.reserveAndVerify(
      locale: Locale(identifier: "en-US"),
      status: { .installed },
      shouldContinue: { [weak self] in
        guard let self else { return false }
        return await self.canContinue()
      },
      diagnostics: diagnostics
    )
  }

  func finish() async throws -> String? {
    nil
  }

  func cancel() {
    cancelled = true
  }

  func releaseResources() {}

  private func canContinue() -> Bool {
    !cancelled
  }
}

private actor DiagnosticReleaseGate {
  private var enteredCount = 0
  private var isOpen = false
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  private var entryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func wait() async {
    enteredCount += 1
    let observers = entryWaiters.filter { $0.0 <= enteredCount }
    entryWaiters.removeAll { $0.0 <= enteredCount }
    observers.forEach { $0.1.resume() }
    guard !isOpen else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilEntered(count: Int) async {
    guard enteredCount < count else { return }
    await withCheckedContinuation { entryWaiters.append((count, $0)) }
  }

  func open() {
    isOpen = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}

private actor DiagnosticSessionProbe: AppleSpeechDiagnosticSession {
  private let cancelsOnStart: Bool
  private let startGate: DiagnosticSessionStartGate?
  private let releaseGate: DiagnosticReleaseGate?
  private var diagnostics: AppleSpeechDiagnostics?
  private(set) var configurationCount = 0

  var supportsOnDeviceRecognition: Bool { true }

  init(
    cancelsOnStart: Bool,
    startGate: DiagnosticSessionStartGate? = nil,
    releaseGate: DiagnosticReleaseGate? = nil
  ) {
    self.cancelsOnStart = cancelsOnStart
    self.startGate = startGate
    self.releaseGate = releaseGate
  }

  func configureDiagnostics(_ diagnostics: AppleSpeechDiagnostics) {
    self.diagnostics = diagnostics
    configurationCount += 1
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    diagnostics?.record(.analyzerStart, .begin)
    await startGate?.wait()
    if cancelsOnStart {
      diagnostics?.record(.analyzerStart, .cancelled)
      throw CancellationError()
    }
    diagnostics?.record(.analyzerStart, .success)
  }

  func finish() async throws -> String? {
    "private transcript never enters the trace"
  }

  func cancel() async {}

  func releaseResources() async {
    await releaseGate?.wait()
  }
}
