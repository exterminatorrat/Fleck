@preconcurrency import AVFAudio
import Foundation
import Testing

@testable import FleckApp

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
  @Test @MainActor
  func enhancedSpeechStartupReturnsWithAudioActiveWhileModelLoadIsSuspended() async throws {
    let loadGate = Gate()
    let inference = EnhancedInferenceSpy()
    inference.loadGate = loadGate
    let audio = EnhancedAudioSpy(samples: [0.25])
    let capture = makeAudioFirstCapture(inference: inference, audio: audio)
    let completion = EnhancedStartupCompletion()

    let start = Task {
      try await capture.start(provisional: { _ in }, level: { _ in })
      completion.markComplete()
    }
    await loadGate.waitUntilWaiting()

    #expect(audio.startCount == 1)
    #expect(completion.isComplete)

    await loadGate.openGate()
    try await start.value
    await capture.cancel()
  }

  @Test @MainActor
  func enhancedSpeechStartupRejectsAnAppendCrossingTheFiveMinuteSampleCeiling() async throws {
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    var failures: [Error] = []
    let converter = try EnhancedAudioStreamConverter(
      inputFormat: format,
      outputFormat: format,
      level: { _ in },
      failure: { failures.append($0) }
    )
    let full = try enhancedStartupBuffer(format: format, frameCount: 4_800_000)
    let overflow = try enhancedStartupBuffer(format: format, frameCount: 1)

    try converter.append(full)
    #expect(throws: EnhancedSpeechCaptureError.sampleLimitExceeded) {
      try converter.append(overflow)
    }
    #expect(throws: EnhancedSpeechCaptureError.sampleLimitExceeded) {
      _ = try converter.finishAndTakeSamples()
    }
    await Task.yield()
    #expect(failures.count == 1)
    #expect(failures.first as? EnhancedSpeechCaptureError == .sampleLimitExceeded)
  }

  @Test @MainActor
  func enhancedSpeechStartupPostFinishAppendDoesNotReportCaptureFailure() async throws {
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    var failures: [Error] = []
    let converter = try EnhancedAudioStreamConverter(
      inputFormat: format,
      outputFormat: format,
      level: { _ in },
      failure: { failures.append($0) }
    )
    let buffer = try enhancedStartupBuffer(format: format, frameCount: 1)
    buffer.floatChannelData?[0][0] = 0.25

    try converter.append(buffer)
    let samples = try converter.finishAndTakeSamples()
    #expect(samples == [0.25])
    #expect(throws: CancellationError.self) {
      try converter.append(buffer)
    }
    await Task.yield()
    #expect(failures.isEmpty)
  }

  @Test @MainActor
  func enhancedSpeechStartupStopsAtReleaseBeforeSuspendedLoadAndPreservesEarlySamples() async throws {
    let loadGate = Gate()
    let inference = AudioFirstInferenceSpy(loadGate: loadGate)
    let audio = EnhancedAudioSpy(samples: [0.25, -0.5, 0.75])
    let capture = makeAudioFirstCapture(inference: inference, audio: audio)
    let completion = EnhancedStartupCompletion()

    try await capture.start(provisional: { _ in }, level: { _ in })
    await loadGate.waitUntilWaiting()
    let finish = Task { @MainActor in
      let result = try await capture.finish()
      completion.markComplete()
      return result
    }
    for _ in 0..<20 { await Task.yield() }

    #expect(audio.stopCount == 1)
    #expect(!completion.isComplete)
    #expect(inference.transcribedSamples.isEmpty)

    await loadGate.openGate()
    #expect(try await finish.value == "Transcript")
    #expect(inference.transcribedSamples == [[0.25, -0.5, 0.75]])
  }

  @Test @MainActor
  func enhancedSpeechStartupCancellationStopsAudioAndQuarantinesIgnoringLoadUntilDrain() async throws {
    let loadGate = Gate()
    let inference = AudioFirstInferenceSpy(loadGate: loadGate)
    let audio = EnhancedAudioSpy(samples: [0.25])
    let capture = makeAudioFirstCapture(inference: inference, audio: audio)
    let completion = EnhancedStartupCompletion()

    try await capture.start(provisional: { _ in }, level: { _ in })
    await loadGate.waitUntilWaiting()
    let cancellation = Task { @MainActor in
      await capture.cancel()
      completion.markComplete()
    }
    for _ in 0..<20 { await Task.yield() }

    #expect(audio.cancelCount == 1)
    #expect(!completion.isComplete)
    #expect(capture.hasActiveResources)
    let measurementsBeforeRejectedStart = capture.runtimeMeasurements
    await #expect(throws: DictationFailure.unavailable) {
      try await capture.start(provisional: { _ in }, level: { _ in })
    }
    #expect(capture.runtimeMeasurements == measurementsBeforeRejectedStart)

    await loadGate.openGate()
    await cancellation.value
    #expect(inference.cancelCount == 1)
    #expect(inference.releaseCount == 1)
    #expect(inference.transcribedSamples.isEmpty)
    #expect(!capture.hasActiveResources)
  }

  @Test @MainActor
  func enhancedSpeechStartupSynchronousAudioFailureBeforeLoadAdmissionStartsNoLateLoad() async throws {
    let inference = AudioFirstInferenceSpy()
    let audio = SynchronousFailureAudioSpy()
    var failures: [Error] = []
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      makeInference: { inference },
      makeAudio: { _ in audio }
    )

    try await capture.start(
      provisional: { _ in },
      level: { _ in },
      failure: { failures.append($0) }
    )
    while capture.hasActiveResources { await Task.yield() }

    #expect(inference.loadCount == 0)
    #expect(audio.cancelCount == 1)
    #expect(failures.count == 1)
    #expect(!capture.hasActiveResources)
  }

  @Test @MainActor
  func enhancedSpeechStartupUnownedLoadCancellationStopsAudioWithoutCorruptingModel() async throws {
    let inference = AudioFirstInferenceSpy()
    inference.loadError = CancellationError()
    let audio = EnhancedAudioSpy(samples: [0.25])
    var failures: [Error] = []
    var repairCount = 0
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      makeInference: { inference },
      makeAudio: { _ in audio },
      markRepairRequired: { _, _ in repairCount += 1 }
    )

    try await capture.start(
      provisional: { _ in },
      level: { _ in },
      failure: { failures.append($0) }
    )
    for _ in 0..<20 { await Task.yield() }

    #expect(failures.count == 1)
    #expect(failures.first is CancellationError)
    #expect(audio.cancelCount == 1)
    #expect(repairCount == 0)
    #expect(!capture.hasActiveResources)
  }

  @Test @MainActor
  func enhancedSpeechStartupCancellationDuringPermissionCannotActivateLateAudio() async throws {
    let permissionGate = Gate()
    let inference = AudioFirstInferenceSpy()
    let audio = EnhancedAudioSpy(samples: [])
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      requestPermission: { _ in
        await permissionGate.wait()
        return .granted
      },
      makeInference: { inference },
      makeAudio: { _ in audio }
    )
    var startError: Error?
    let start = Task { @MainActor in
      do {
        try await capture.start(provisional: { _ in }, level: { _ in })
      } catch {
        startError = error
      }
    }
    await permissionGate.waitUntilWaiting()
    let cancellation = Task { @MainActor in await capture.cancel() }
    for _ in 0..<20 { await Task.yield() }

    #expect(audio.startCount == 0)
    #expect(capture.hasActiveResources)

    await permissionGate.openGate()
    await cancellation.value
    await start.value
    #expect(startError is CancellationError)
    #expect(audio.startCount == 0)
    #expect(capture.runtimeMeasurements.modelLoadRequestedAt == nil)
    #expect(capture.runtimeMeasurements.outcome == nil)
    #expect(capture.runtimeMeasurements.failure == nil)
    #expect(!capture.hasActiveResources)
  }

  @Test @MainActor
  func enhancedSpeechStartupPermissionDenialStartsNeitherAudioNorModelLoad() async {
    let inference = AudioFirstInferenceSpy()
    let audio = EnhancedAudioSpy(samples: [])
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      requestPermission: { _ in .denied([]) },
      makeInference: { inference },
      makeAudio: { _ in audio }
    )

    await #expect(throws: DictationFailure.permissionDenied) {
      try await capture.start(provisional: { _ in }, level: { _ in })
    }

    #expect(audio.startCount == 0)
    #expect(inference.releaseCount == 1)
    #expect(!capture.hasActiveResources)
  }

  @Test @MainActor
  func enhancedSpeechStartupCancellationDuringSuccessfulReleaseDefeatsLateText() async throws {
    let releaseGate = Gate()
    let inference = AudioFirstInferenceSpy(releaseGate: releaseGate)
    let audio = EnhancedAudioSpy(samples: [0.25])
    let capture = makeAudioFirstCapture(inference: inference, audio: audio)
    var finishError: Error?

    try await capture.start(provisional: { _ in }, level: { _ in })
    let finish = Task { @MainActor in
      do {
        _ = try await capture.finish()
      } catch {
        finishError = error
      }
    }
    await releaseGate.waitUntilWaiting()
    let cancellation = Task { @MainActor in await capture.cancel() }
    for _ in 0..<20 { await Task.yield() }

    #expect(inference.cancelCount == 1)
    #expect(capture.hasActiveResources)

    await releaseGate.openGate()
    await cancellation.value
    await finish.value
    #expect(finishError is CancellationError)
    #expect(!capture.hasActiveResources)
  }

  @Test @MainActor
  func enhancedSpeechStartupWatchdogStopsAudioButWaitsForIgnoringLoadToDrain() async throws {
    let loadGate = Gate()
    let timeoutGate = Gate()
    let instant = ContinuousClock().now
    let inference = AudioFirstInferenceSpy(loadGate: loadGate)
    let audio = EnhancedAudioSpy(samples: [0.25])
    var failures: [Error] = []
    var repairCount = 0
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      makeInference: { inference },
      makeAudio: { _ in audio },
      markRepairRequired: { _, _ in repairCount += 1 },
      startupNow: { instant },
      startupSleeper: { duration in
        #expect(duration == .seconds(15))
        await timeoutGate.wait()
      }
    )

    try await capture.start(
      provisional: { _ in },
      level: { _ in },
      failure: { failures.append($0) }
    )
    await loadGate.waitUntilWaiting()
    await timeoutGate.waitUntilWaiting()
    await timeoutGate.openGate()
    while failures.isEmpty { await Task.yield() }

    #expect(failures.count == 1)
    #expect(failures.first as? EnhancedSpeechCaptureError == .startupTimedOut)
    #expect(audio.cancelCount == 1)
    #expect(capture.hasActiveResources)
    #expect(inference.releaseCount == 0)
    #expect(repairCount == 0)

    await loadGate.openGate()
    while capture.hasActiveResources { await Task.yield() }
    #expect(inference.releaseCount == 1)
  }

  @Test @MainActor
  func enhancedSpeechStartupRejectsLoadCompletingAfterAbsoluteWatchdogDeadline() async throws {
    let loadGate = Gate()
    let sleeperGate = Gate()
    let now = EnhancedStartupInstantBox()
    let inference = AudioFirstInferenceSpy(loadGate: loadGate)
    let audio = EnhancedAudioSpy(samples: [0.25])
    var failures: [Error] = []
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      makeInference: { inference },
      makeAudio: { _ in audio },
      startupNow: { now.value },
      startupSleeper: { _ in await sleeperGate.wait() }
    )

    try await capture.start(
      provisional: { _ in },
      level: { _ in },
      failure: { failures.append($0) }
    )
    await loadGate.waitUntilWaiting()
    now.advance(by: .seconds(16))
    await loadGate.openGate()
    while failures.isEmpty { await Task.yield() }

    #expect(failures.first as? EnhancedSpeechCaptureError == .startupTimedOut)
    #expect(inference.transcribedSamples.isEmpty)
    #expect(audio.cancelCount == 1)
    await sleeperGate.openGate()
    while capture.hasActiveResources { await Task.yield() }
  }

  @Test @MainActor
  func dictationDiagnosticsEnhancedRecordsFirstInputBeforeConversionWithoutLevelDelivery() throws {
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let observed = ContinuousClock().now
    var levels: [Float] = []
    let converter = try EnhancedAudioStreamConverter(
      inputFormat: format,
      outputFormat: format,
      level: { levels.append($0) },
      now: { observed }
    )
    let empty = try enhancedStartupBuffer(format: format, frameCount: 0)
    let nonempty = try enhancedStartupBuffer(format: format, frameCount: 1)
    nonempty.floatChannelData?[0][0] = 0.5

    try converter.append(empty)
    #expect(converter.firstInputBufferAt == nil)
    try converter.append(nonempty)

    #expect(converter.firstInputBufferAt == observed)
    #expect(levels.isEmpty)
  }

  @Test @MainActor
  func dictationDiagnosticsEnhancedClassifiesKnownFailuresAndPreservesReleasedSnapshot() async throws {
    let repository = URL(fileURLWithPath: "/verified/parakeet")
    let permissionCapture = EnhancedSpeechCapture(
      verifiedLoadState: { .ready(repositoryURL: repository) },
      requestPermission: { _ in .denied([]) },
      makeInference: { AudioFirstInferenceSpy() },
      makeAudio: { _ in DiagnosticsAudioSpy() }
    )
    await #expect(throws: DictationFailure.permissionDenied) {
      try await permissionCapture.start(provisional: { _ in }, level: { _ in })
    }
    #expect(permissionCapture.runtimeMeasurements.failure == .permissionDenied)

    let unavailableCapture = EnhancedSpeechCapture(
      verifiedLoadState: { .unavailable },
      makeInference: { AudioFirstInferenceSpy() },
      makeAudio: { _ in DiagnosticsAudioSpy() }
    )
    await #expect(throws: DictationFailure.unavailable) {
      try await unavailableCapture.start(provisional: { _ in }, level: { _ in })
    }
    #expect(unavailableCapture.runtimeMeasurements.failure == .modelUnavailable)

    let missingInputCapture = EnhancedSpeechCapture(
      verifiedLoadState: { .ready(repositoryURL: repository) },
      makeInference: { AudioFirstInferenceSpy() },
      makeAudio: { _ in DiagnosticsAudioSpy(startError: EnhancedSpeechCaptureError.missingInput) }
    )
    await #expect(throws: EnhancedSpeechCaptureError.missingInput) {
      try await missingInputCapture.start(provisional: { _ in }, level: { _ in })
    }
    #expect(missingInputCapture.runtimeMeasurements.failure == .missingInput)

    let loadInference = AudioFirstInferenceSpy()
    loadInference.loadError = EnhancedTestFailure.failed
    let loadCapture = EnhancedSpeechCapture(
      verifiedLoadState: { .ready(repositoryURL: repository) },
      makeInference: { loadInference },
      makeAudio: { _ in DiagnosticsAudioSpy() }
    )
    try await loadCapture.start(provisional: { _ in }, level: { _ in })
    while loadCapture.hasActiveResources { await Task.yield() }
    #expect(loadCapture.runtimeMeasurements.failure == .modelLoadFailure)
    #expect(loadCapture.runtimeMeasurements.loadDisposition == .cold)
    #expect(loadCapture.runtimeMeasurements.modelLoadRequestedAt != nil)
    #expect(loadCapture.runtimeMeasurements.modelReadyAt == nil)

    let bufferCapture = EnhancedSpeechCapture(
      verifiedLoadState: { .ready(repositoryURL: repository) },
      makeInference: { AudioFirstInferenceSpy() },
      makeAudio: { _ in
        DiagnosticsAudioSpy(synchronousFailure: EnhancedSpeechCaptureError.sampleLimitExceeded)
      }
    )
    try await bufferCapture.start(
      provisional: { _ in },
      level: { _ in },
      failure: { _ in }
    )
    while bufferCapture.hasActiveResources { await Task.yield() }
    #expect(bufferCapture.runtimeMeasurements.failure == .bufferLimit)
  }

  @Test @MainActor
  func dictationDiagnosticsEnhancedTimeoutAndReleasedFirstBufferRemainContentFree() async throws {
    let loadGate = Gate()
    let timeoutGate = Gate()
    let repository = URL(fileURLWithPath: "/verified/parakeet")
    let inference = AudioFirstInferenceSpy(loadGate: loadGate)
    let observed = ContinuousClock().now
    let audio = DiagnosticsAudioSpy(firstInputBufferAt: observed)
    let capture = EnhancedSpeechCapture(
      verifiedLoadState: { .ready(repositoryURL: repository) },
      makeInference: { inference },
      makeAudio: { _ in audio },
      startupNow: { observed },
      startupSleeper: { _ in await timeoutGate.wait() }
    )

    try await capture.start(provisional: { _ in }, level: { _ in })
    await loadGate.waitUntilWaiting()
    await timeoutGate.openGate()
    while capture.runtimeMeasurements.failure == nil { await Task.yield() }
    #expect(capture.runtimeMeasurements.failure == .startupTimeout)

    await loadGate.openGate()
    while capture.hasActiveResources { await Task.yield() }
    #expect(audio.firstInputBufferAt == nil)
    #expect(capture.runtimeMeasurements.firstInputBufferAt == observed)
    #expect(capture.runtimeMeasurements.failure == .startupTimeout)
  }

  @MainActor
  private func makeAudioFirstCapture(
    inference: any EnhancedSpeechInferring,
    audio: EnhancedAudioSpy
  ) -> EnhancedSpeechCapture {
    EnhancedSpeechCapture(
      verifiedLoadState: {
        .ready(repositoryURL: URL(fileURLWithPath: "/verified/parakeet"))
      },
      makeInference: { inference },
      makeAudio: { _ in audio }
    )
  }

  @MainActor
  private final class AudioFirstInferenceSpy: EnhancedSpeechInferring {
    private let loadGate: Gate?
    private let releaseGate: Gate?
    private(set) var transcribedSamples: [[Float]] = []
    private(set) var loadCount = 0
    private(set) var cancelCount = 0
    private(set) var releaseCount = 0
    var loadError: Error?

    func loadDisposition(for _: URL) -> DictationRuntimeMeasurements.LoadDisposition? {
      .cold
    }

    init(loadGate: Gate? = nil, releaseGate: Gate? = nil) {
      self.loadGate = loadGate
      self.releaseGate = releaseGate
    }

    func load(from _: URL) async throws {
      loadCount += 1
      await loadGate?.wait()
      if let loadError { throw loadError }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
      transcribedSamples.append(samples)
      return "Transcript"
    }

    func cancel() async {
      cancelCount += 1
    }

    func releaseResources() async {
      releaseCount += 1
      await releaseGate?.wait()
    }
  }

  @MainActor
  private final class DiagnosticsAudioSpy: EnhancedAudioCapturing {
    private(set) var firstInputBufferAt: ContinuousClock.Instant?
    private let startError: Error?
    private let synchronousFailure: Error?

    init(
      firstInputBufferAt: ContinuousClock.Instant? = nil,
      startError: Error? = nil,
      synchronousFailure: Error? = nil
    ) {
      self.firstInputBufferAt = firstInputBufferAt
      self.startError = startError
      self.synchronousFailure = synchronousFailure
    }

    func start(level _: @escaping @MainActor (Float) -> Void) throws {
      if let startError { throw startError }
    }

    func start(
      level: @escaping @MainActor (Float) -> Void,
      failure: @escaping @MainActor (Error) -> Void
    ) throws {
      try start(level: level)
      if let synchronousFailure { failure(synchronousFailure) }
    }

    func stopAndTakeSamples() -> [Float] { [0.25] }
    func cancel() { firstInputBufferAt = nil }
    func releaseResources() { firstInputBufferAt = nil }
  }

  @MainActor
  private final class SynchronousFailureAudioSpy: EnhancedAudioCapturing {
    private(set) var cancelCount = 0

    func start(level _: @escaping @MainActor (Float) -> Void) throws {}

    func start(
      level _: @escaping @MainActor (Float) -> Void,
      failure: @escaping @MainActor (Error) -> Void
    ) throws {
      failure(EnhancedTestFailure.failed)
    }

    func stopAndTakeSamples() -> [Float] { [] }

    func cancel() {
      cancelCount += 1
    }

    func releaseResources() {}
  }

  @MainActor
  private final class EnhancedStartupCompletion {
    private(set) var isComplete = false

    func markComplete() {
      isComplete = true
    }
  }

  private func enhancedStartupBuffer(
    format: AVAudioFormat,
    frameCount: AVAudioFrameCount
  ) throws -> AVAudioPCMBuffer {
    let buffer = try #require(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    )
    buffer.frameLength = frameCount
    return buffer
  }

  private final class EnhancedStartupInstantBox: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock().now

    var value: ContinuousClock.Instant {
      lock.withLock { instant }
    }

    func advance(by duration: Duration) {
      lock.withLock { instant = instant.advanced(by: duration) }
    }
  }
#endif
