import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FleckApp

@Suite("AgentActivityIndicator")
@MainActor
struct AgentActivityIndicatorTests {
  @Test
  func stateCopyDescribesOnlyObservedActivity() {
    #expect(AgentActivityIndicatorState.idle.accessibilityLabel == "Agent Activity")
    #expect(AgentActivityIndicatorState.working.accessibilityLabel == "Agent using Fleck")
    #expect(
      AgentActivityIndicatorState.recentlyUsed.accessibilityLabel
        == "Agent used Fleck just now"
    )
    #expect(AgentActivityIndicatorState.failed.accessibilityLabel == "Agent request failed")
    #expect(
      AgentActivityIndicatorState.cancelled.accessibilityLabel
        == "Agent request cancelled"
    )
    #expect(AgentActivityIndicatorState.idle.statusSymbol == nil)
  }

  @Test
  func indicatorFootprintStaysFixedAcrossIdleWorkingAndRecentStates() {
    let scheduler = IndicatorClearScheduler()
    let presentation = AgentActivityIndicatorPresentation(
      scheduleClear: scheduler.schedule
    )
    let profileID = UUID()
    let requestID = UUID()
    let widths = [
      indicatorWidth(presentation),
      {
        presentation.receive(.began(requestID: requestID, profileID: profileID))
        return indicatorWidth(presentation)
      }(),
      {
        presentation.receive(
          .finished(requestID: requestID, profileID: profileID, outcome: .succeeded)
        )
        return indicatorWidth(presentation)
      }(),
    ]

    #expect(widths.allSatisfy { abs($0 - widths[0]) < 0.5 })
  }

  @Test
  func overlappingRequestsStayWorkingAndUnknownFinishesAreIgnored() {
    let presentation = AgentActivityIndicatorPresentation()
    let profileID = UUID()
    let first = UUID()
    let second = UUID()

    presentation.receive(.began(requestID: first, profileID: profileID))
    presentation.receive(.began(requestID: second, profileID: profileID))
    presentation.receive(
      .finished(requestID: first, profileID: profileID, outcome: .succeeded)
    )
    #expect(presentation.state == .working)

    presentation.receive(
      .finished(requestID: UUID(), profileID: profileID, outcome: .failed)
    )
    #expect(presentation.state == .working)

    presentation.receive(
      .finished(requestID: second, profileID: profileID, outcome: .succeeded)
    )
    #expect(presentation.state == .recentlyUsed)
  }

  @Test
  func repeatedUseInvalidatesStaleClearAndLatestSignalClears() {
    let scheduler = IndicatorClearScheduler()
    let presentation = AgentActivityIndicatorPresentation(
      scheduleClear: scheduler.schedule
    )
    let profileID = UUID()
    let first = UUID()
    let second = UUID()

    presentation.receive(.began(requestID: first, profileID: profileID))
    presentation.receive(
      .finished(requestID: first, profileID: profileID, outcome: .succeeded)
    )
    presentation.receive(.began(requestID: second, profileID: profileID))
    presentation.receive(
      .finished(requestID: second, profileID: profileID, outcome: .succeeded)
    )
    #expect(scheduler.actions.count == 2)
    #expect(scheduler.delays == [.seconds(3), .seconds(3)])

    scheduler.actions[0]()
    #expect(presentation.state == .recentlyUsed)

    scheduler.actions[1]()
    #expect(presentation.state == .idle)
  }

  @Test
  func revokingProfileKeepsUnrelatedActivityAndClearsRevokedSignals() {
    let scheduler = IndicatorClearScheduler()
    let presentation = AgentActivityIndicatorPresentation(
      scheduleClear: scheduler.schedule
    )
    let revokedProfileID = UUID()
    let activeProfileID = UUID()
    let revokedRequest = UUID()
    let activeRequest = UUID()
    presentation.receive(
      .began(requestID: revokedRequest, profileID: revokedProfileID)
    )
    presentation.receive(
      .began(requestID: activeRequest, profileID: activeProfileID)
    )

    presentation.revoke(profileID: revokedProfileID)
    #expect(presentation.state == .working)

    presentation.receive(
      .finished(
        requestID: activeRequest,
        profileID: activeProfileID,
        outcome: .succeeded
      )
    )
    #expect(presentation.state == .recentlyUsed)

    presentation.revoke(profileID: activeProfileID)
    #expect(presentation.state == .idle)
  }

  @Test
  func resetInvalidatesPendingClear() {
    let scheduler = IndicatorClearScheduler()
    let presentation = AgentActivityIndicatorPresentation(
      scheduleClear: scheduler.schedule
    )
    let profileID = UUID()
    let requestID = UUID()
    presentation.receive(.began(requestID: requestID, profileID: profileID))
    presentation.receive(
      .finished(requestID: requestID, profileID: profileID, outcome: .failed)
    )
    #expect(scheduler.actions.count == 1)

    presentation.reset()
    scheduler.actions[0]()

    #expect(presentation.state == .idle)
  }

  @Test
  func failureAndCancellationUseNeutralTemporaryStates() {
    let cases: [(AgentRequestOutcome, AgentActivityIndicatorState)] = [
      (.failed, .failed),
      (.cancelled, .cancelled),
    ]

    for (outcome, expectedState) in cases {
      let scheduler = IndicatorClearScheduler()
      let presentation = AgentActivityIndicatorPresentation(
        scheduleClear: scheduler.schedule
      )
      let profileID = UUID()
      let requestID = UUID()
      presentation.receive(.began(requestID: requestID, profileID: profileID))
      presentation.receive(
        .finished(requestID: requestID, profileID: profileID, outcome: outcome)
      )

      #expect(presentation.state == expectedState)
      #expect(scheduler.delays == [.seconds(3)])
      scheduler.actions[0]()
      #expect(presentation.state == .idle)
    }
  }
}

@MainActor
private func indicatorWidth(
  _ presentation: AgentActivityIndicatorPresentation
) -> CGFloat {
  let host = NSHostingView(
    rootView: AgentActivityIndicator(presentation: presentation, action: {})
  )
  host.layoutSubtreeIfNeeded()
  return host.fittingSize.width
}

@MainActor
private final class IndicatorClearScheduler {
  var delays: [Duration] = []
  var actions: [@MainActor () -> Void] = []

  func schedule(
    after delay: Duration,
    _ action: @escaping @MainActor () -> Void
  ) {
    delays.append(delay)
    actions.append(action)
  }
}
