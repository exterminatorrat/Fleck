import Foundation

public enum OnboardingStep: String, Codable, CaseIterable, Sendable {
  case welcome
  case firstNote
  case dictation
  case permissions
  case getFleck
}

public enum OnboardingPermissionCursor: String, Codable, CaseIterable, Sendable {
  case microphone
  case speechRecognition
  case inputMonitoring
  case compatibility
}

public struct OnboardingProgress: Codable, Equatable, Sendable {
  public static let currentFlowVersion = 1

  public enum Status: Codable, Equatable, Sendable {
    case inProgress(step: OnboardingStep)
    case completed
    case existingUserExempt
  }

  public var flowVersion: Int
  public var status: Status
  public var permissionCursor: OnboardingPermissionCursor

  public init(
    flowVersion: Int = currentFlowVersion,
    status: Status,
    permissionCursor: OnboardingPermissionCursor = .microphone
  ) {
    self.flowVersion = flowVersion
    self.status = status
    self.permissionCursor = permissionCursor
  }
}
