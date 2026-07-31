import FleckCore
import Testing

@testable import FleckApp

@Test func onboardingRailHasExactStepsAndStates() {
  let rail = OnboardingRailPresentation(current: .dictation)
  #expect(rail.items.map(\.title) == [
    "Welcome", "Your first note", "Dictation", "Permissions", "Get Fleck",
  ])
  #expect(rail.items.map(\.state) == [
    .completed, .completed, .current, .upcoming, .upcoming,
  ])
}

@Test func getFleckCopyContainsRequiredPromisesAndNoSkip() {
  let presentation = OnboardingGetFleckPresentation(
    access: FleckAccessPresentation(
      state: .unavailable,
      localizedLifetimePrice: nil,
      inFlightAction: nil,
      message: nil
    )
  )
  #expect(presentation.body.contains("No credit card"))
  #expect(presentation.body.contains("No Apple purchase sheet"))
  #expect(presentation.body.contains("not be charged automatically"))
  #expect(!presentation.actions.map(\.title).contains("Not Now"))
}

@Test func onboardingCopyUsesLocalPrivacyAndSelectedModifier() {
  #expect(OnboardingWelcomePresentation.body.contains("stay on this Mac"))
  #expect(!OnboardingWelcomePresentation.body.contains("account"))
  let permission = OnboardingPermissionPresentation(
    cursor: .inputMonitoring,
    modifier: .leftCommand
  )
  #expect(permission.title.contains(DictationModifierKey.leftCommand.displayName))
  #expect(permission.body.contains("does not read, store, or log ordinary keys"))
}

@Test func onboardingPriceUsesLocalizedAccessPresentation() {
  let loading = OnboardingGetFleckPresentation(
    access: .init(
      state: .loading,
      localizedLifetimePrice: nil,
      inFlightAction: nil,
      message: nil
    )
  )
  #expect(!loading.actions[1].enabled)

  let localized = OnboardingGetFleckPresentation(
    access: .init(
      state: .trialNotStarted,
      localizedLifetimePrice: "Localized price",
      inFlightAction: nil,
      message: nil
    )
  )
  #expect(localized.actions[1].title == "Buy Fleck — Localized price")
  #expect(localized.actions[1].enabled)
}
