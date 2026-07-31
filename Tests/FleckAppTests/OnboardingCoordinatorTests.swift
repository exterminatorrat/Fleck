import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func freshBootstrapPersistsWelcomeBeforeBecomingRequired() async {
  let fixture = await OnboardingCoordinatorFixture()

  await fixture.coordinator.bootstrap()

  #expect(
    fixture.state.preferences.onboardingProgress
      == OnboardingProgress(status: .inProgress(step: .welcome))
  )
  #expect(fixture.coordinator.gateState == .required)
  #expect(fixture.coordinator.visibleStep == .welcome)
}

@Test @MainActor func firstNoteRequiresARealMutation() async {
  let fixture = await OnboardingCoordinatorFixture()
  await fixture.coordinator.bootstrap()
  await fixture.coordinator.continueFromCurrentStep()
  await fixture.coordinator.prepareFirstNoteIfNeeded()

  #expect(!fixture.coordinator.canContinue)
  fixture.state.updateSelected(body: "A real first thought")
  #expect(fixture.coordinator.canContinue)
}

@Test @MainActor func backIsTransientAndResumeStaysAtFurthestStep() async {
  let fixture = await OnboardingCoordinatorFixture()
  await fixture.coordinator.bootstrap()
  await fixture.coordinator.continueFromCurrentStep()
  await fixture.coordinator.prepareFirstNoteIfNeeded()
  fixture.state.updateSelected(body: "A real first thought")
  await fixture.coordinator.continueFromCurrentStep()

  fixture.coordinator.goBack()

  #expect(fixture.coordinator.visibleStep == .firstNote)
  #expect(fixture.coordinator.persistedStep == .dictation)
}

@Test @MainActor func deferredPermissionAdvancesWithoutBlocking() async {
  let fixture = await OnboardingCoordinatorFixture()
  await fixture.coordinator.bootstrap()

  await fixture.coordinator.deferCurrentPermission()

  #expect(fixture.coordinator.permissionCursor == .speechRecognition)
}

@Test @MainActor func accessRequiresAuthoritativeFullAccess() async {
  let access = OnboardingAccessFake()
  let fixture = await OnboardingCoordinatorFixture(access: access)
  await fixture.coordinator.bootstrap()

  access.nextResult = .cancelled
  await fixture.coordinator.performAccessAction(.purchaseLifetime)
  #expect(fixture.coordinator.gateState == .required)

  access.nextResult = .trialActive(expiresAt: .distantFuture)
  await fixture.coordinator.performAccessAction(.startTrial)
  #expect(fixture.coordinator.gateState == .required)

  access.presentation.state = .purchased
  access.nextResult = .purchased
  await fixture.coordinator.performAccessAction(.purchaseLifetime)
  #expect(fixture.coordinator.gateState == .complete)
  #expect(fixture.state.preferences.onboardingProgress?.status == .completed)
}

@MainActor
private final class OnboardingCoordinatorFixture {
  let root: URL
  let state: AppState
  let coordinator: OnboardingCoordinator

  init(access: OnboardingAccessFake = OnboardingAccessFake()) async {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("onboarding-\(UUID().uuidString)", isDirectory: true)
    state = AppState(store: LocalStore(rootURL: root))
    await state.waitUntilInitialLoad()
    coordinator = OnboardingCoordinator(
      appState: state,
      dictationRuntime: nil,
      accessActions: access
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private final class OnboardingAccessFake: FleckAccessActions {
  var presentation = FleckAccessPresentation(
    state: .trialNotStarted,
    localizedLifetimePrice: "Localized price",
    inFlightAction: nil,
    message: nil
  )
  var nextResult = FleckAccessActionResult.cancelled

  func refresh() async {}
  func startTrial() async -> FleckAccessActionResult { nextResult }
  func purchaseLifetime() async -> FleckAccessActionResult { nextResult }
  func restorePurchase() async -> FleckAccessActionResult { nextResult }
}
