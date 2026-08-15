import Foundation
import Testing

@testable import FleckApp

@Test @MainActor func unavailableAccessAdapterCannotComplete() async {
  let actions = UnavailableFleckAccessActions()
  #expect(!actions.presentation.hasFullAccess)
  #expect(actions.presentation.localizedLifetimePrice == nil)
  #expect(await actions.startTrial() == .unavailable)
  #expect(await actions.purchaseLifetime() == .unavailable)
  #expect(await actions.restorePurchase() == .unavailable)
  #expect(!actions.presentation.hasFullAccess)
}

@Test func onlyTrialAndPurchaseStatesHaveFullAccess() {
  #expect(!FleckAccessState.loading.hasFullAccess)
  #expect(!FleckAccessState.trialNotStarted.hasFullAccess)
  #expect(FleckAccessState.trialActive(expiresAt: .distantFuture).hasFullAccess)
  #expect(FleckAccessState.purchased.hasFullAccess)
  #expect(!FleckAccessState.unavailable.hasFullAccess)
}

@Test @MainActor func developmentAccessFactoryStartsTrialAndUpdatesPresentation() async {
  let actions = FleckAccessActionsFactory.make(developmentAccessEnabled: true)
  #expect(actions is DevelopmentFleckAccessActions)

  let before = Date()
  let result = await actions.startTrial()
  guard case let .trialActive(expiresAt) = result else {
    Issue.record("Development access should start the placeholder trial")
    return
  }

  #expect(expiresAt >= before.addingTimeInterval(7 * 24 * 60 * 60 - 1))
  #expect(expiresAt <= before.addingTimeInterval(7 * 24 * 60 * 60 + 1))
  #expect(
    actions.presentation.state == FleckAccessState.trialActive(expiresAt: expiresAt)
  )
  #expect(actions.presentation.hasFullAccess)
  #expect(await actions.purchaseLifetime() == .unavailable)
  #expect(await actions.restorePurchase() == .unavailable)
}

@Test @MainActor func accessFactoryKeepsOrdinaryBuildUnavailable() async {
  let actions = FleckAccessActionsFactory.make(developmentAccessEnabled: false)

  #expect(actions is UnavailableFleckAccessActions)
  #expect(!actions.presentation.hasFullAccess)
  #expect(await actions.startTrial() == .unavailable)
}
