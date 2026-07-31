import Foundation
import Testing

@testable import FleckCore

@Test func onboardingProgressRoundTripsEveryCursor() throws {
  for step in OnboardingStep.allCases {
    let value = OnboardingProgress(
      flowVersion: OnboardingProgress.currentFlowVersion,
      status: .inProgress(step: step),
      permissionCursor: .microphone
    )
    let decoded = try JSONDecoder().decode(
      OnboardingProgress.self,
      from: JSONEncoder().encode(value)
    )
    #expect(decoded == value)
  }
}

@Test func onboardingProgressHasStableOrderAndVersion() {
  #expect(OnboardingStep.allCases == [
    .welcome, .firstNote, .dictation, .permissions, .getFleck,
  ])
  #expect(OnboardingPermissionCursor.allCases == [
    .microphone, .speechRecognition, .inputMonitoring, .compatibility,
  ])
  #expect(OnboardingProgress.currentFlowVersion == 1)
}
