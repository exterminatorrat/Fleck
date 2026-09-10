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
  func indicatorFootprintStaysFixedAcrossAllStates() {
    let scheduler = IndicatorClearScheduler()
    let idlePresentation = AgentActivityIndicatorPresentation(
      scheduleClear: scheduler.schedule
    )
    let profileID = UUID()
    let workingPresentation = AgentActivityIndicatorPresentation(
      scheduleClear: scheduler.schedule
    )
    workingPresentation.receive(.began(requestID: UUID(), profileID: profileID))
    var widths = [
      indicatorWidth(idlePresentation),
      indicatorWidth(workingPresentation),
    ]
    for outcome in [
      AgentRequestOutcome.succeeded,
      .failed,
      .cancelled,
    ] {
      let presentation = AgentActivityIndicatorPresentation(
        scheduleClear: scheduler.schedule
      )
      let requestID = UUID()
      presentation.receive(.began(requestID: requestID, profileID: profileID))
      presentation.receive(
        .finished(requestID: requestID, profileID: profileID, outcome: outcome)
      )
      widths.append(indicatorWidth(presentation))
    }

    #expect(widths.allSatisfy { abs($0 - widths[0]) < 0.5 })
  }

  @Test
  func indicatorReservesEnoughWidthForLiteralLabelAndStatusGlyph() {
    let presentation = AgentActivityIndicatorPresentation()

    #expect(indicatorWidth(presentation) >= requiredIndicatorContentWidth())
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
private func requiredIndicatorContentWidth() -> CGFloat {
  let host = NSHostingView(
    rootView: HStack(spacing: 4) {
      switch FleckMark.load(template: true) {
      case .image(let mark):
        Image(nsImage: mark)
          .resizable()
          .frame(width: 18, height: 18)
      case .missingPackagedResource:
        Text("!")
      }
      Text("MCP")
        .font(.caption2.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 7, weight: .semibold))
        .frame(width: 9, height: 9)
    }
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
