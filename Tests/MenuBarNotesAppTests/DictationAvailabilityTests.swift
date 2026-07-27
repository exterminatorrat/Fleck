import AVFAudio
import Foundation
import Testing
@testable import MenuBarNotesApp

@Test func dictationAvailabilityUsesInjectedCapabilityMatrix() {
  struct Scenario {
    let name: String
    let input: DictationAvailability.Input
    let standard: Bool
    let enhanced: Bool
    let cleanup: Bool
    let routing: DictationRoutingAvailability
    let settings: Set<DictationPrivacyPane>
  }

  let scenarios = [
    Scenario(
      name: "macOS 13 is unsupported",
      input: .init(
        osMajorVersion: 13,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ),
      standard: false,
      enhanced: false,
      cleanup: false,
      routing: .inbox,
      settings: []
    ),
    Scenario(
      name: "macOS 14 Apple silicon uses reduced platform behavior",
      input: .init(
        osMajorVersion: 14,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ),
      standard: true,
      enhanced: true,
      cleanup: false,
      routing: .inbox,
      settings: []
    ),
    Scenario(
      name: "macOS 15 Intel keeps Standard but never Enhanced",
      input: .init(
        osMajorVersion: 15,
        architecture: .intel,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ),
      standard: true,
      enhanced: false,
      cleanup: false,
      routing: .inbox,
      settings: []
    ),
    Scenario(
      name: "Standard never permits an off-device fallback",
      input: .init(
        osMajorVersion: 26,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: false,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ),
      standard: false,
      enhanced: true,
      cleanup: true,
      routing: .foundationModel,
      settings: []
    ),
    Scenario(
      name: "Enhanced requires a ready model",
      input: .init(
        osMajorVersion: 26,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: false,
        foundationModelAvailable: true
      ),
      standard: true,
      enhanced: false,
      cleanup: true,
      routing: .foundationModel,
      settings: []
    ),
    Scenario(
      name: "cleanup and routing do not depend on a speech engine",
      input: .init(
        osMajorVersion: 26,
        architecture: .intel,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: false,
        enhancedModelReady: false,
        foundationModelAvailable: true
      ),
      standard: false,
      enhanced: false,
      cleanup: true,
      routing: .foundationModel,
      settings: []
    ),
    Scenario(
      name: "denied permissions expose both privacy panes",
      input: .init(
        osMajorVersion: 26,
        architecture: .appleSilicon,
        microphonePermission: .denied,
        speechPermission: .denied,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: true,
        foundationModelAvailable: true
      ),
      standard: false,
      enhanced: false,
      cleanup: true,
      routing: .foundationModel,
      settings: [.microphone, .speechRecognition]
    ),
  ]

  for scenario in scenarios {
    let result = DictationAvailability.evaluate(
      scenario.input,
      enhancedCandidateEnabled: true
    )
    #expect(result.standardAvailable == scenario.standard, Comment(rawValue: scenario.name))
    #expect(result.enhancedAvailable == scenario.enhanced, Comment(rawValue: scenario.name))
    #expect(result.cleanupAvailable == scenario.cleanup, Comment(rawValue: scenario.name))
    #expect(result.routing == scenario.routing, Comment(rawValue: scenario.name))
    #expect(Set(result.openSystemSettings.map(\.pane)) == scenario.settings, Comment(rawValue: scenario.name))
    #expect(
      result.openSystemSettings.allSatisfy { $0.title == "Open System Settings" },
      Comment(rawValue: scenario.name)
    )
  }
}

@Test func dictationAvailabilityProvidesLocalizedActionableStandardFailures() {
  let permissionFailure = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  #expect(permissionFailure.standardFailureCopy?.contains("Microphone") == true)
  #expect(permissionFailure.standardFailureCopy?.contains("Open System Settings") == true)

  let recognizerFailure = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: false,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  #expect(recognizerFailure.standardFailureCopy?.contains("on-device English") == true)
}

@Test @MainActor func permissionsWaitForExplicitUserIntent() async {
  let microphone = PermissionProbe()
  let speech = PermissionProbe()
  let permissions = DictationPermissionController(
    microphoneStatus: { microphone.status },
    speechStatus: { speech.status },
    requestMicrophone: {
      microphone.requests += 1
      microphone.status = .authorized
      return true
    },
    requestSpeech: {
      speech.requests += 1
      speech.status = .authorized
      return true
    }
  )

  #expect(microphone.requests == 0)
  #expect(speech.requests == 0)

  let result = await permissions.requestAccess(after: .toolbarMicrophone)

  #expect(result == .granted)
  #expect(microphone.requests == 1)
  #expect(speech.requests == 1)
}

@Test @MainActor func enhancedPermissionRequestsMicrophoneOnly() async {
  let microphone = PermissionProbe()
  let speech = PermissionProbe()
  let permissions = DictationPermissionController(
    microphoneStatus: { microphone.status },
    speechStatus: { speech.status },
    requestMicrophone: {
      microphone.requests += 1
      microphone.status = .authorized
      return true
    },
    requestSpeech: {
      speech.requests += 1
      speech.status = .authorized
      return true
    }
  )

  let result = await permissions.requestAccess(
    for: .enhancedLocal,
    after: .toolbarMicrophone
  )

  #expect(result == .granted)
  #expect(microphone.requests == 1)
  #expect(speech.requests == 0)
}

@Test @MainActor func deniedPermissionIsNotRepromptedAndOpensItsPrivacyPane() async {
  let microphone = PermissionProbe(status: .authorized)
  let speech = PermissionProbe()
  let permissions = DictationPermissionController(
    microphoneStatus: { microphone.status },
    speechStatus: { speech.status },
    requestMicrophone: {
      microphone.requests += 1
      return true
    },
    requestSpeech: {
      speech.requests += 1
      speech.status = .denied
      return false
    }
  )

  let first = await permissions.requestAccess(after: .shortcutSetupCompleted)
  let second = await permissions.requestAccess(after: .toolbarMicrophone)

  #expect(first == .denied([.init(pane: .speechRecognition)]))
  #expect(second == first)
  #expect(microphone.requests == 0)
  #expect(speech.requests == 1)
}

@MainActor
private final class PermissionProbe {
  var status: DictationPermissionStatus
  var requests = 0

  init(status: DictationPermissionStatus = .notDetermined) {
    self.status = status
  }
}

@Test func microphoneSelectionUsesSavedUIDOrFallsBackToAutomatic() {
  #expect(
    MicrophoneSelection.resolve(savedUID: nil, availableUIDs: ["built-in"])
      == .automatic
  )
  #expect(
    MicrophoneSelection.resolve(savedUID: "usb", availableUIDs: ["built-in", "usb"])
      == .selected(uid: "usb")
  )
  #expect(
    MicrophoneSelection.resolve(savedUID: "missing", availableUIDs: ["built-in"])
      == .missingUsingAutomatic(
        settingsCopy: "The saved microphone is unavailable. Using Automatic."
      )
  )
}

@Test func audioHelpersCopyBuffersAndNormalizeRMS() throws {
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    )
  )
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
  buffer.frameLength = 4
  let samples = try #require(buffer.floatChannelData?[0])
  samples[0] = 0.5
  samples[1] = -0.5
  samples[2] = 0.5
  samples[3] = -0.5

  let copy = try AudioBufferTools.copy(buffer)
  samples[0] = 0

  #expect(copy !== buffer)
  #expect(copy.floatChannelData?[0][0] == 0.5)
  #expect(AudioBufferTools.normalizedRMS(copy) == 0.5)
}

@Test func reusedAudioConverterProducesEverySequentialBuffer() throws {
  let inputFormat = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 48_000,
      channels: 1,
      interleaved: false
    )
  )
  let outputFormat = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    )
  )
  let converter = try #require(AVAudioConverter(from: inputFormat, to: outputFormat))

  let first = try AudioBufferTools.convert(
    speechBuffer(format: inputFormat, frames: 4_800),
    using: converter,
    to: outputFormat
  )
  let second = try AudioBufferTools.convert(
    speechBuffer(format: inputFormat, frames: 4_800),
    using: converter,
    to: outputFormat
  )

  #expect(first.frameLength > 0)
  #expect(second.frameLength > 0)
}

@Test func installedSpeechLocaleUsesCanonicalLanguageComponents() {
  #expect(
    AppleSpeechLocale.containsEquivalent(
      Locale(identifier: "en-US"),
      in: [Locale(identifier: "en_US")]
    )
  )
  #expect(
    !AppleSpeechLocale.containsEquivalent(
      Locale(identifier: "en-US"),
      in: [Locale(identifier: "en-GB")]
    )
  )
}

@Test func boundedAudioIngressDrainsAcceptedBuffersAndFailsOverflow() async throws {
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    )
  )
  let draining = BoundedAudioIngress(capacity: 2)
  let first = try speechBuffer(format: format, frames: 4)
  let second = try speechBuffer(format: format, frames: 4)
  #expect(draining.yield(first))
  #expect(draining.yield(second))
  draining.finish()
  var drained = 0
  for try await _ in draining.buffers {
    drained += 1
  }
  #expect(drained == 2)

  let overflowing = BoundedAudioIngress(capacity: 1)
  let third = try speechBuffer(format: format, frames: 4)
  let fourth = try speechBuffer(format: format, frames: 4)
  #expect(overflowing.yield(third))
  #expect(!overflowing.yield(fourth))
  await #expect(throws: DictationFailure.transcriptionFailed) {
    for try await _ in overflowing.buffers {}
  }
}

@Test @MainActor func appleSpeechCaptureEmitsProvisionalRetainsFinalAndReleases() async throws {
  let session = AppleSpeechSessionProbe()
  session.finishResult = .success("final words")
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { session }
  )
  var provisional: [String] = []
  var levels: [Float] = []

  try await capture.start(
    provisional: { provisional.append($0) },
    level: { levels.append($0) }
  )
  session.emitProvisional("provisional words")
  session.emitLevel(0.25)
  let final = try await capture.finish()

  #expect(provisional == ["provisional words"])
  #expect(levels == [0.25])
  #expect(final == "final words")
  #expect(session.finishCount == 1)
  #expect(session.releaseCount == 1)
  await capture.releaseResources()
  #expect(session.finishCount == 1)
  #expect(session.cancelCount == 0)
  #expect(session.releaseCount == 1)
}

@Test @MainActor func appleSpeechCaptureHandlesNoSpeechErrorAndCancellation() async throws {
  let noSpeechSession = AppleSpeechSessionProbe()
  noSpeechSession.finishResult = .success("   ")
  let noSpeech = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { noSpeechSession }
  )
  try await noSpeech.start(provisional: { _ in }, level: { _ in })
  #expect(try await noSpeech.finish() == nil)
  #expect(noSpeechSession.releaseCount == 1)

  let errorSession = AppleSpeechSessionProbe()
  errorSession.finishResult = .failure(SpeechProbeError.failed)
  let failing = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { errorSession }
  )
  try await failing.start(provisional: { _ in }, level: { _ in })
  await #expect(throws: SpeechProbeError.failed) {
    try await failing.finish()
  }
  #expect(errorSession.releaseCount == 1)

  let cancelledSession = AppleSpeechSessionProbe()
  let cancelled = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { cancelledSession }
  )
  try await cancelled.start(provisional: { _ in }, level: { _ in })
  await cancelled.cancel()
  #expect(cancelledSession.cancelCount == 1)
  #expect(cancelledSession.releaseCount == 1)
  await cancelled.releaseResources()
  #expect(cancelledSession.cancelCount == 1)
  #expect(cancelledSession.releaseCount == 1)
}

@Test @MainActor func appleSpeechCaptureRejectsCloudFallbackAndDeniedPermission() async {
  let unsupported = AppleSpeechSessionProbe()
  unsupported.supportsOnDeviceRecognition = false
  let unavailable = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { unsupported }
  )
  await #expect(throws: DictationFailure.unavailable) {
    try await unavailable.start(provisional: { _ in }, level: { _ in })
  }
  #expect(unsupported.startCount == 0)
  #expect(unsupported.releaseCount == 1)

  let deniedSession = AppleSpeechSessionProbe()
  let denied = AppleSpeechCapture(
    requestPermission: { .denied([.init(pane: .microphone)]) },
    makeSession: { deniedSession }
  )
  await #expect(throws: DictationFailure.permissionDenied) {
    try await denied.start(provisional: { _ in }, level: { _ in })
  }
  #expect(deniedSession.startCount == 0)
}

@Test @MainActor func interruptionTerminatesOnceAndUnblocksFinish() async throws {
  let interruptions = AppleSpeechInterruptionSourceProbe()
  let session = AppleSpeechSessionProbe()
  session.waitsForCancellation = true
  let capture = AppleSpeechCapture(
    requestPermission: { .granted },
    makeSession: { session },
    interruptions: interruptions
  )
  try await capture.start(provisional: { _ in }, level: { _ in })
  let finishTask = Task { @MainActor in
    try await capture.finish()
  }
  while session.finishCount == 0 {
    await Task.yield()
  }

  interruptions.emit()

  await #expect(throws: DictationFailure.interrupted) {
    try await finishTask.value
  }
  #expect(session.cancelCount == 1)
  #expect(session.releaseCount == 1)
  #expect(interruptions.stopCount == 1)
  interruptions.emit()
  await capture.releaseResources()
  #expect(session.cancelCount == 1)
  #expect(session.releaseCount == 1)
}

private enum SpeechProbeError: Error {
  case failed
}

@MainActor
private final class AppleSpeechSessionProbe: AppleSpeechSession {
  var supportsOnDeviceRecognition = true
  var finishResult: Result<String?, Error> = .success(nil)
  var startCount = 0
  var finishCount = 0
  var cancelCount = 0
  var releaseCount = 0
  var waitsForCancellation = false
  private var finishContinuation: CheckedContinuation<String?, Error>?
  private var provisional: (@MainActor (String) -> Void)?
  private var level: (@MainActor (Float) -> Void)?

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {
    startCount += 1
    self.provisional = provisional
    self.level = level
  }

  func finish() async throws -> String? {
    finishCount += 1
    if waitsForCancellation {
      return try await withCheckedThrowingContinuation { finishContinuation = $0 }
    }
    return try finishResult.get()
  }

  func cancel() async {
    cancelCount += 1
    finishContinuation?.resume(throwing: DictationFailure.interrupted)
    finishContinuation = nil
  }

  func releaseResources() async {
    releaseCount += 1
    provisional = nil
    level = nil
  }

  func emitProvisional(_ text: String) {
    provisional?(text)
  }

  func emitLevel(_ value: Float) {
    level?(value)
  }
}

@MainActor
private final class AppleSpeechInterruptionSourceProbe: AppleSpeechInterruptionSource {
  private var handler: (@MainActor @Sendable () -> Void)?
  var stopCount = 0

  func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
    self.handler = handler
  }

  func stop() {
    stopCount += 1
    handler = nil
  }

  func emit() {
    handler?()
  }
}

private func speechBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) throws
  -> AVAudioPCMBuffer
{
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
  buffer.frameLength = frames
  if let samples = buffer.floatChannelData?[0] {
    for index in 0..<Int(frames) {
      samples[index] = 0.25
    }
  }
  return buffer
}
