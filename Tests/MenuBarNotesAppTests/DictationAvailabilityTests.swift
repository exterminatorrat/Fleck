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
    let result = DictationAvailability.evaluate(scenario.input)
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
    return try finishResult.get()
  }

  func cancel() async {
    cancelCount += 1
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
