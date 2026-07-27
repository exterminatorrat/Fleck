import AVFoundation
import Foundation
import Speech

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
  let title = "Open System Settings"
  let pane: DictationPrivacyPane
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
  let openSystemSettings: [DictationSystemSettingsAction]

  static func evaluate(_ input: Input) -> Self {
    let supportedOS = input.osMajorVersion >= 14
    let microphoneAvailable = input.microphonePermission.permitsRequestOrUse
    let speechAvailable = input.speechPermission.permitsRequestOrUse
    let foundationModelAvailable = input.osMajorVersion >= 26 && input.foundationModelAvailable
    var settings: [DictationSystemSettingsAction] = []
    if !microphoneAvailable {
      settings.append(.init(pane: .microphone))
    }
    if !speechAvailable {
      settings.append(.init(pane: .speechRecognition))
    }

    return .init(
      standardAvailable: supportedOS
        && microphoneAvailable
        && speechAvailable
        && input.appleOnDeviceRecognitionSupported,
      enhancedAvailable: supportedOS
        && input.architecture == .appleSilicon
        && microphoneAvailable
        && input.enhancedModelReady,
      cleanupAvailable: foundationModelAvailable,
      routing: foundationModelAvailable ? .foundationModel : .inbox,
      openSystemSettings: settings
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

  func requestAccess(after _: DictationPermissionIntent) async -> DictationPermissionResult {
    if microphoneStatus() == .notDetermined {
      _ = await requestMicrophone()
    }
    guard microphoneStatus() == .authorized else {
      return .denied(recoveryActions())
    }

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
