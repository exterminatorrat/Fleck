import FleckCore
import Testing

@testable import FleckApp

@Test func onboardingBootstrapPolicyClassifiesSnapshots() {
  #expect(
    OnboardingBootstrapPolicy.resolve(source: .fresh, progress: nil)
      == .persistAndRequire(
        OnboardingProgress(status: .inProgress(step: .welcome))
      )
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(source: .root, progress: nil)
      == .persistAndSkip(
        OnboardingProgress(status: .existingUserExempt)
      )
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(
      source: .root,
      progress: .init(status: .inProgress(step: .dictation))
    ) == .requireExisting
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(
      source: .recovery,
      progress: .init(status: .completed)
    ) == .skipExisting
  )
}

@Test func completedOldFlowVersionDoesNotReplay() {
  let completed = OnboardingProgress(
    flowVersion: 0,
    status: .completed
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(source: .root, progress: completed)
      == .skipExisting
  )
}
