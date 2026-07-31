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
