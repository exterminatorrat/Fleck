import AVFoundation
import Foundation
import FleckCore
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

enum DictationFoundationModelAvailability: Equatable, Sendable {
  case available
  case unsupportedOS
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  case modelNotReady
  case unknown
}

enum DictationPrivacyPane: Hashable, Sendable {
  case microphone
  case speechRecognition
  case inputMonitoring

  var url: URL {
    switch self {
    case .microphone:
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    case .speechRecognition:
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    case .inputMonitoring:
      URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
      )!
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
    case .inputMonitoring:
      "Open Input Monitoring Settings"
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
    let foundationModelAvailability: DictationFoundationModelAvailability

    init(
      osMajorVersion: Int,
      architecture: DictationArchitecture,
      microphonePermission: DictationPermissionStatus,
      speechPermission: DictationPermissionStatus,
      appleOnDeviceRecognitionSupported: Bool,
      enhancedModelReady: Bool,
      foundationModelAvailability: DictationFoundationModelAvailability
    ) {
      self.osMajorVersion = osMajorVersion
      self.architecture = architecture
      self.microphonePermission = microphonePermission
      self.speechPermission = speechPermission
      self.appleOnDeviceRecognitionSupported = appleOnDeviceRecognitionSupported
      self.enhancedModelReady = enhancedModelReady
      self.foundationModelAvailability = foundationModelAvailability
    }

    init(
      osMajorVersion: Int,
      architecture: DictationArchitecture,
      microphonePermission: DictationPermissionStatus,
      speechPermission: DictationPermissionStatus,
      appleOnDeviceRecognitionSupported: Bool,
      enhancedModelReady: Bool,
      foundationModelAvailable: Bool
    ) {
      self.init(
        osMajorVersion: osMajorVersion,
        architecture: architecture,
        microphonePermission: microphonePermission,
        speechPermission: speechPermission,
        appleOnDeviceRecognitionSupported: appleOnDeviceRecognitionSupported,
        enhancedModelReady: enhancedModelReady,
        foundationModelAvailability:
          osMajorVersion < 26
          ? .unsupportedOS
          : foundationModelAvailable ? .available : .unknown
      )
    }
  }

  let standardAvailable: Bool
  let enhancedAvailable: Bool
  let cleanupAvailable: Bool
  let routing: DictationRoutingAvailability
  let foundationModelAvailability: DictationFoundationModelAvailability
  let microphonePermission: DictationPermissionStatus
  let speechPermission: DictationPermissionStatus
  let appleOnDeviceRecognitionSupported: Bool
  let osMajorVersion: Int
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
    let foundationModelAvailable = input.foundationModelAvailability == .available
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
        foundationModelAvailability: input.foundationModelAvailability,
        microphonePermission: input.microphonePermission,
        speechPermission: input.speechPermission,
        appleOnDeviceRecognitionSupported: input.appleOnDeviceRecognitionSupported,
        osMajorVersion: input.osMajorVersion,
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
        foundationModelAvailability: input.foundationModelAvailability,
        microphonePermission: input.microphonePermission,
        speechPermission: input.speechPermission,
        appleOnDeviceRecognitionSupported: input.appleOnDeviceRecognitionSupported,
        osMajorVersion: input.osMajorVersion,
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
      foundationModelAvailability: foundationModelAvailability
    ))
  }

  var standardFailureCopy: String? {
    guard !standardAvailable else { return nil }
    if openSystemSettings.contains(where: { $0.pane == .microphone }) {
      return "Standard — Apple Speech needs Microphone access. Open System Settings to allow Fleck."
    }
    if openSystemSettings.contains(where: { $0.pane == .speechRecognition }) {
      return "Standard — Apple Speech needs Speech Recognition access. Open System Settings to allow Fleck."
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
        return "Enhanced Local needs Microphone access. Open System Settings to allow Fleck."
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

  private static var foundationModelAvailability: DictationFoundationModelAvailability {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return .available
        case .unavailable(.deviceNotEligible):
          return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
          return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
          return .modelNotReady
        @unknown default:
          return .unknown
        }
      }
    #endif
    return .unsupportedOS
  }
}

struct DictationCompatibilityRow: Equatable, Sendable {
  let title: String
  let detail: String
  let available: Bool
}

struct DictationCompatibilityPresentation: Equatable, Sendable {
  let notes: DictationCompatibilityRow
  let appleSpeech: DictationCompatibilityRow
  let cleanup: DictationCompatibilityRow
  let smartCapture: DictationCompatibilityRow

  init(availability: DictationAvailability) {
    notes = .init(title: "Fleck notes", detail: "Available", available: true)

    let speechDetail: String
    if availability.osMajorVersion < 14 {
      speechDetail = "Requires macOS 14 or later"
    } else if availability.microphonePermission != .authorized {
      speechDetail = "Needs Microphone"
    } else if availability.speechPermission != .authorized {
      speechDetail = "Needs Speech Recognition"
    } else if !availability.appleOnDeviceRecognitionSupported {
      speechDetail = "On-device English unavailable"
    } else {
      speechDetail = "Available"
    }
    appleSpeech = .init(
      title: "Apple Speech",
      detail: speechDetail,
      available: availability.standardAvailable
    )

    let cleanupDetail: String
    switch availability.foundationModelAvailability {
    case .available:
      cleanupDetail = "Available"
    case .unsupportedOS:
      cleanupDetail = "Requires macOS 26 or later"
    case .deviceNotEligible:
      cleanupDetail = "Requires a Mac that supports Apple Intelligence"
    case .appleIntelligenceNotEnabled:
      cleanupDetail = "Turn on Apple Intelligence in System Settings"
    case .modelNotReady:
      cleanupDetail = "Apple Intelligence model is not ready"
    case .unknown:
      cleanupDetail = "Unavailable"
    }
    cleanup = .init(
      title: "AI cleanup",
      detail: cleanupDetail,
      available: availability.cleanupAvailable
    )
    smartCapture = .init(
      title: "Smart Capture",
      detail: availability.routing == .foundationModel ? "Available" : "Saves to Inbox",
      available: availability.routing == .foundationModel
    )
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
    guard await requestMicrophoneAccess() == .authorized else {
      return .denied(recoveryActions())
    }

    guard engine == .standard else { return .granted }

    guard await requestSpeechRecognitionAccess() == .authorized else {
      return .denied(recoveryActions())
    }
    return .granted
  }

  func requestMicrophoneAccess() async -> DictationPermissionStatus {
    if microphoneStatus() == .notDetermined {
      _ = await requestMicrophone()
    }
    return microphoneStatus()
  }

  func requestSpeechRecognitionAccess() async -> DictationPermissionStatus {
    if speechStatus() == .notDetermined {
      _ = await requestSpeech()
    }
    return speechStatus()
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
