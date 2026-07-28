import AVFoundation
import Foundation
import MenuBarNotesCore
import Speech

#if canImport(FoundationModels)
  import FoundationModels
#endif

enum DictationArchitecture: Equatable, Sendable {
  case appleSilicon
  case intel
}

enum DictationPermissionStatus: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted

  var permitsRequestOrUse: Bool {
    self == .notDetermined || self == .authorized
  }
}

enum DictationRoutingAvailability: Equatable, Sendable {
  case inbox
  case foundationModel
}

enum DictationPrivacyPane: Hashable, Sendable {
  case microphone
  case speechRecognition

  var url: URL {
    switch self {
    case .microphone:
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    case .speechRecognition:
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    }
  }
}

struct DictationSystemSettingsAction: Equatable, Sendable {
  let pane: DictationPrivacyPane
  var title: String {
    switch pane {
    case .microphone:
      "Open Microphone Settings"
    case .speechRecognition:
      "Open Speech Recognition Settings"
    }
  }
  var url: URL { pane.url }
}

struct DictationAvailability: Equatable, Sendable {
  struct Input: Equatable, Sendable {
    let osMajorVersion: Int
    let architecture: DictationArchitecture
    let microphonePermission: DictationPermissionStatus
    let speechPermission: DictationPermissionStatus
    let appleOnDeviceRecognitionSupported: Bool
    let enhancedModelReady: Bool
    let foundationModelAvailable: Bool
  }

  let standardAvailable: Bool
  let enhancedAvailable: Bool
  let cleanupAvailable: Bool
  let routing: DictationRoutingAvailability
  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    let enhancedFailureCopy: String?
  #endif
  let openSystemSettings: [DictationSystemSettingsAction]

  static func evaluate(
    _ input: Input,
    enhancedCandidateEnabled: Bool =
      CleanDictationFeatures.enhancedLocalCandidateEnabled
  ) -> Self {
    let supportedOS = input.osMajorVersion >= 14
    let microphoneAvailable = input.microphonePermission.permitsRequestOrUse
    let speechAvailable = input.speechPermission.permitsRequestOrUse
    let foundationModelAvailable = input.osMajorVersion >= 26 && input.foundationModelAvailable
    let enhancedAvailable = supportedOS
      && enhancedCandidateEnabled
      && input.architecture == .appleSilicon
      && microphoneAvailable
      && input.enhancedModelReady
    var settings: [DictationSystemSettingsAction] = []
    if !microphoneAvailable {
      settings.append(.init(pane: .microphone))
    }
    if !speechAvailable {
      settings.append(.init(pane: .speechRecognition))
    }

    let standardAvailable = supportedOS
      && microphoneAvailable
      && speechAvailable
      && input.appleOnDeviceRecognitionSupported
    let routing: DictationRoutingAvailability =
      foundationModelAvailable ? .foundationModel : .inbox

    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      return .init(
        standardAvailable: standardAvailable,
        enhancedAvailable: enhancedAvailable,
        cleanupAvailable: foundationModelAvailable,
        routing: routing,
        enhancedFailureCopy: enhancedFailureCopy(
          input,
          enhancedCandidateEnabled: enhancedCandidateEnabled,
          microphoneAvailable: microphoneAvailable,
          enhancedAvailable: enhancedAvailable
        ),
        openSystemSettings: settings
      )
    #else
      return .init(
        standardAvailable: standardAvailable,
        enhancedAvailable: enhancedAvailable,
        cleanupAvailable: foundationModelAvailable,
        routing: routing,
        openSystemSettings: settings
      )
    #endif
  }

  @MainActor
  static func current(
    permissions: DictationPermissionController,
    enhancedModelReady: Bool
  ) -> Self {
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    return evaluate(.init(
      osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
      architecture: currentArchitecture(),
      microphonePermission: permissions.currentMicrophoneStatus,
      speechPermission: permissions.currentSpeechStatus,
      appleOnDeviceRecognitionSupported: recognizer?.supportsOnDeviceRecognition == true,
      enhancedModelReady: enhancedModelReady,
      foundationModelAvailable: foundationModelIsAvailable
    ))
  }

  var standardFailureCopy: String? {
    guard !standardAvailable else { return nil }
    if openSystemSettings.contains(where: { $0.pane == .microphone }) {
      return "Standard — Apple Speech needs Microphone access. Open System Settings to allow Motes."
    }
    if openSystemSettings.contains(where: { $0.pane == .speechRecognition }) {
      return "Standard — Apple Speech needs Speech Recognition access. Open System Settings to allow Motes."
    }
    return "Standard — Apple Speech is unavailable because on-device English recognition is not installed or supported."
  }

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    private static func enhancedFailureCopy(
      _ input: Input,
      enhancedCandidateEnabled: Bool,
      microphoneAvailable: Bool,
      enhancedAvailable: Bool
    ) -> String? {
      guard !enhancedAvailable else { return nil }
      if !microphoneAvailable {
        return "Enhanced Local needs Microphone access. Open System Settings to allow Motes."
      }
      if input.osMajorVersion < 14 {
        return "Enhanced Local requires macOS 14 or later."
      }
      if !enhancedCandidateEnabled {
        return "Enhanced Local is unavailable in this build."
      }
      if input.architecture == .intel {
        return "Enhanced Local requires Apple silicon."
      }
      return "Enhanced Local is unavailable because its model is not ready. Open Dictation Settings to download or repair it."
    }
  #endif

  private static func currentArchitecture() -> DictationArchitecture {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
    return machine == "arm64" ? .appleSilicon : .intel
  }

  private static var foundationModelIsAvailable: Bool {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return SystemLanguageModel.default.isAvailable
      }
    #endif
    return false
  }
}

enum DictationPermissionIntent: Equatable, Sendable {
  case toolbarMicrophone
  case shortcutSetupCompleted
}

enum DictationPermissionResult: Equatable, Sendable {
  case granted
  case denied([DictationSystemSettingsAction])
}

@MainActor
final class DictationPermissionController {
  private let microphoneStatus: () -> DictationPermissionStatus
  private let speechStatus: () -> DictationPermissionStatus
  private let requestMicrophone: () async -> Bool
  private let requestSpeech: () async -> Bool

  var currentMicrophoneStatus: DictationPermissionStatus { microphoneStatus() }
  var currentSpeechStatus: DictationPermissionStatus { speechStatus() }

  init(
    microphoneStatus: @escaping () -> DictationPermissionStatus = {
      DictationPermissionController.permissionStatus(
        AVCaptureDevice.authorizationStatus(for: .audio)
      )
    },
    speechStatus: @escaping () -> DictationPermissionStatus = {
      DictationPermissionController.permissionStatus(SFSpeechRecognizer.authorizationStatus())
    },
    requestMicrophone: @escaping () async -> Bool = {
      await AVCaptureDevice.requestAccess(for: .audio)
    },
    requestSpeech: @escaping () async -> Bool = {
      await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status == .authorized)
        }
      }
    }
  ) {
    self.microphoneStatus = microphoneStatus
    self.speechStatus = speechStatus
    self.requestMicrophone = requestMicrophone
    self.requestSpeech = requestSpeech
  }

  func requestAccess(
    for engine: DictationSpeechEngine = .standard,
    after _: DictationPermissionIntent
  ) async -> DictationPermissionResult {
    if microphoneStatus() == .notDetermined {
      _ = await requestMicrophone()
    }
    guard microphoneStatus() == .authorized else {
      return .denied(recoveryActions())
    }

    guard engine == .standard else { return .granted }

    if speechStatus() == .notDetermined {
      _ = await requestSpeech()
    }
    guard speechStatus() == .authorized else {
      return .denied(recoveryActions())
    }
    return .granted
  }

  func recoveryActions() -> [DictationSystemSettingsAction] {
    var result: [DictationSystemSettingsAction] = []
    if !microphoneStatus().permitsRequestOrUse {
      result.append(.init(pane: .microphone))
    }
    if !speechStatus().permitsRequestOrUse {
      result.append(.init(pane: .speechRecognition))
    }
    return result
  }

  private static func permissionStatus(_ status: AVAuthorizationStatus) -> DictationPermissionStatus {
    switch status {
    case .notDetermined:
      .notDetermined
    case .authorized:
      .authorized
    case .denied:
      .denied
    case .restricted:
      .restricted
    @unknown default:
      .restricted
    }
  }

  private static func permissionStatus(
    _ status: SFSpeechRecognizerAuthorizationStatus
  ) -> DictationPermissionStatus {
    switch status {
    case .notDetermined:
      .notDetermined
    case .authorized:
      .authorized
    case .denied:
      .denied
    case .restricted:
      .restricted
    @unknown default:
      .restricted
    }
  }
}
