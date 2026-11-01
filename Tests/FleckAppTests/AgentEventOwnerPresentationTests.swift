import FleckCore
import Foundation
import Testing

@testable import FleckApp

@Suite("AgentEventOwnerPresentation")
struct AgentEventOwnerPresentationTests {
  @Test func callbackHostPresentationOmitsPathQueryAndInvalidValues() {
    let host = AgentEventOwnerPresentation.callbackHost(
      from: "https://events.example.test/callback/private?key=secret"
    )

    #expect(host == "events.example.test")
    #expect(!host.contains("/"))
    #expect(!host.contains("?"))
    #expect(!host.contains("secret"))
    #expect(
      AgentEventOwnerPresentation.callbackHost(from: "https://")
        == "Host unavailable"
    )
  }

  @Test func scopeAndEventPresentationUsesOwnerReadableNames() throws {
    let folder = try Folder(name: "Projects")
    let note = Note(title: "Roadmap", folderID: folder.id)
    let workspace = Workspace(notes: [note], folders: [folder])

    #expect(
      AgentEventOwnerPresentation.scopeSummary(
        for: .note(noteID: note.id),
        in: workspace
      ) == "Note “Roadmap”"
    )
    #expect(
      AgentEventOwnerPresentation.scopeSummary(
        for: .folder(folderID: folder.id),
        in: workspace
      ) == "Folder “Projects”"
    )
    #expect(
      AgentEventOwnerPresentation.scopeSummary(
        for: .note(noteID: UUID()),
        in: workspace
      ) == "Note unavailable"
    )
    #expect(AgentEventOwnerPresentation.eventTitle(.noteUpdated) == "Note updated")
  }

  @Test func pendingAndTimeoutStatusStaysPausedUntilOwnerApproval() {
    #expect(
      AgentEventOwnerPresentation.statusTitle(for: .awaitingApproval)
        == "Awaiting owner approval"
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .awaitingApproval)
        .contains("delivery stays paused")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .awaitingVerification)
        .contains("delivery stays paused")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .retrying)
        .contains("callback receipt")
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .awaitingVerification,
        allowsAutomaticRenewal: false
      ) == "Approve & Resume"
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .enabled,
        allowsAutomaticRenewal: false
      ) == "Approve Renewal"
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .enabled,
        allowsAutomaticRenewal: true
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .awaitingApproval,
        allowsAutomaticRenewal: false
      ) == "Approve & Resume"
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .paused,
        allowsAutomaticRenewal: false
      ) == "Approve & Resume"
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .retrying,
        allowsAutomaticRenewal: false
      ) == "Approve Renewal"
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .retrying,
        allowsAutomaticRenewal: true
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .expired,
        allowsAutomaticRenewal: false
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .stopped,
        allowsAutomaticRenewal: false
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .pausedCapacity,
        allowsAutomaticRenewal: false
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .pausedHistory,
        allowsAutomaticRenewal: false
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: .unavailable,
        allowsAutomaticRenewal: false
      ) == nil
    )
    #expect(
      AgentEventOwnerPresentation.statusTitle(for: .pausedCapacity)
        == "Paused at capacity"
    )
    #expect(
      AgentEventOwnerPresentation.statusTitle(for: .pausedHistory)
        == "Paused for history recovery"
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .pausedCapacity)
        .contains("Pending events are retained")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .pausedCapacity)
        .contains("fully blocked backlog cannot be resumed from this row")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .pausedHistory)
        .contains("Required history is unavailable")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .pausedHistory)
        .contains("cannot replay that history or silently restart this subscription")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .expired)
        .contains("request a fresh subscription")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .expired)
        .contains("review and approve that request")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .stopped)
        .contains("Restore its profile and required access, then refresh status")
    )
    #expect(
      AgentEventOwnerPresentation.statusDetail(for: .unavailable)
        .contains(
          "Restore the profile, access, or local availability, then refresh status"
        )
    )
  }

  @Test func pauseRemainsAvailableToClearConsentForInactiveSubscriptions() {
    #expect(AgentEventOwnerPresentation.canPause(.expired))
    #expect(AgentEventOwnerPresentation.canPause(.stopped))
    #expect(AgentEventOwnerPresentation.canPause(.unavailable))
    #expect(AgentEventOwnerPresentation.canPause(.pausedCapacity))
    #expect(AgentEventOwnerPresentation.canPause(.pausedHistory))
    #expect(!AgentEventOwnerPresentation.canPause(.paused))
  }

  @Test func renewalSelectionDefaultsOffIsReversibleAndSubscriptionScoped() {
    let first = makeSubscriptionSummary(id: "first", state: .paused)
    let second = makeSubscriptionSummary(id: "second", state: .paused)
    var selection = AgentEventOwnerConsentSelection()

    #expect(!selection.allowsAutomaticRenewal(for: first))
    #expect(!selection.allowsAutomaticRenewal(for: second))

    selection.setAutomaticRenewal(true, for: first)

    #expect(selection.allowsAutomaticRenewal(for: first))
    #expect(!selection.allowsAutomaticRenewal(for: second))

    selection.setAutomaticRenewal(false, for: first)

    #expect(!selection.allowsAutomaticRenewal(for: first))
    #expect(!selection.allowsAutomaticRenewal(for: second))
  }

  @Test(
    "Approval and resume preserve explicit renewal choice",
    arguments: [
      AgentEventOwnerState.awaitingApproval,
      .awaitingVerification,
      .paused,
    ]
  )
  func approvalAndResumePreserveExplicitRenewalChoice(state: AgentEventOwnerState) {
    let subscription = makeSubscriptionSummary(id: "approval", state: state)
    var selection = AgentEventOwnerConsentSelection()

    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: state,
        allowsAutomaticRenewal: subscription.allowsAutomaticRenewal
      ) == "Approve & Resume"
    )
    #expect(selection.canApplyApproval(for: subscription))

    let deliveryOnlyApproval = selection.approvalOptions(for: subscription)
    #expect(deliveryOnlyApproval.enabled)
    #expect(!deliveryOnlyApproval.allowsAutomaticRenewal)

    selection.setAutomaticRenewal(true, for: subscription)
    let renewalApproval = selection.approvalOptions(for: subscription)

    #expect(renewalApproval.enabled)
    #expect(renewalApproval.allowsAutomaticRenewal)

    selection.setAutomaticRenewal(false, for: subscription)

    #expect(!selection.approvalOptions(for: subscription).allowsAutomaticRenewal)
    #expect(renewalApproval.allowsAutomaticRenewal)
  }

  @Test func existingRenewalGrantDoesNotSeedAnExplicitOptIn() {
    let subscription = makeSubscriptionSummary(
      id: "existing-grant",
      state: .paused,
      allowsAutomaticRenewal: true
    )
    let selection = AgentEventOwnerConsentSelection()

    #expect(subscription.allowsAutomaticRenewal)
    #expect(!selection.allowsAutomaticRenewal(for: subscription))
    #expect(!selection.approvalOptions(for: subscription).allowsAutomaticRenewal)
  }

  @Test func recreatedSubscriptionRequiresFreshOptInWithoutClearingOtherRows() {
    let original = makeSubscriptionSummary(id: "recreated", state: .awaitingApproval)
    let other = makeSubscriptionSummary(id: "other", state: .paused)
    let recreated = AgentEventOwnerSummary(
      id: original.id,
      profileID: original.profileID,
      event: original.event,
      scope: original.scope,
      callbackHost: original.callbackHost,
      state: original.state,
      expiresAt: original.expiresAt,
      lastReceiptAt: original.lastReceiptAt,
      allowsAutomaticRenewal: original.allowsAutomaticRenewal,
      consentGenerationID: UUID()
    )
    var selection = AgentEventOwnerConsentSelection()
    selection.setAutomaticRenewal(true, for: original)
    selection.setAutomaticRenewal(true, for: other)

    #expect(selection.allowsAutomaticRenewal(for: original))
    #expect(!selection.allowsAutomaticRenewal(for: recreated))
    #expect(!selection.consumeApprovalOptions(for: recreated).allowsAutomaticRenewal)
    #expect(selection.allowsAutomaticRenewal(for: other))

    selection.setAutomaticRenewal(true, for: recreated)

    #expect(selection.allowsAutomaticRenewal(for: recreated))
    #expect(selection.allowsAutomaticRenewal(for: other))
  }

  @Test func missingConsentGenerationCannotRetainARenewalChoice() {
    let subscription = makeSubscriptionSummary(
      id: "unbound", state: .paused, consentGenerationID: nil
    )
    var selection = AgentEventOwnerConsentSelection()
    selection.setAutomaticRenewal(true, for: subscription)

    #expect(!selection.allowsAutomaticRenewal(for: subscription))
    #expect(!selection.approvalOptions(for: subscription).allowsAutomaticRenewal)
  }

  @Test func approvePauseAndResumeRequireFreshRenewalSelection() {
    let subscription = makeSubscriptionSummary(id: "approval-cycle", state: .paused)
    let other = makeSubscriptionSummary(id: "other", state: .paused)
    var selection = AgentEventOwnerConsentSelection()
    selection.setAutomaticRenewal(true, for: subscription)
    selection.setAutomaticRenewal(true, for: other)

    let approval = selection.consumeApprovalOptions(for: subscription)

    #expect(approval.enabled)
    #expect(approval.allowsAutomaticRenewal)
    #expect(!selection.allowsAutomaticRenewal(for: subscription))
    #expect(selection.allowsAutomaticRenewal(for: other))

    selection.setAutomaticRenewal(false, for: subscription)
    let resumed = selection.consumeApprovalOptions(for: subscription)

    #expect(resumed.enabled)
    #expect(!resumed.allowsAutomaticRenewal)
    #expect(!selection.allowsAutomaticRenewal(for: subscription))

    selection.setAutomaticRenewal(true, for: subscription)

    #expect(selection.consumeApprovalOptions(for: subscription).allowsAutomaticRenewal)
    #expect(!selection.allowsAutomaticRenewal(for: subscription))
  }

  @Test(
    "Renewal approval remains available after explicit opt-in",
    arguments: [AgentEventOwnerState.enabled, .retrying]
  )
  func renewalApprovalRequiresExplicitOptIn(state: AgentEventOwnerState) {
    let subscription = makeSubscriptionSummary(id: "renewal", state: state)
    var selection = AgentEventOwnerConsentSelection()

    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: state,
        allowsAutomaticRenewal: subscription.allowsAutomaticRenewal
      ) == "Approve Renewal"
    )
    #expect(!selection.canApplyApproval(for: subscription))

    selection.setAutomaticRenewal(true, for: subscription)

    #expect(selection.canApplyApproval(for: subscription))
    #expect(
      AgentEventOwnerPresentation.approvalActionTitle(
        for: state,
        allowsAutomaticRenewal: subscription.allowsAutomaticRenewal
      ) == "Approve Renewal"
    )
    #expect(selection.approvalOptions(for: subscription).allowsAutomaticRenewal)
  }

  @Test func ownerCopySeparatesRenewalReceiptsPrivacyAndChatGPTSetup() {
    #expect(
      AgentEventOwnerPresentation.renewalConsentDescription
        .contains("same event scope and callback host")
    )
    #expect(
      AgentEventOwnerPresentation.renewalConsentDescription
        .contains("cannot be recalled")
    )
    #expect(
      AgentEventOwnerPresentation.receiptDescription
        .contains("does not confirm that an agent read or acted on it")
    )
    #expect(
      AgentEventOwnerPresentation.globalPrivacyDescription
        .contains("every agent profile")
    )
    #expect(
      AgentEventOwnerPresentation.chatGPTConnectionDescription
        .contains("Secure MCP Tunnel")
    )
    #expect(
      AgentEventOwnerPresentation.chatGPTConnectionDescription
        .contains("connection test")
    )
    #expect(
      AgentEventOwnerPresentation.chatGPTConnectionDescription
        .contains("no tunnel or account is configured")
    )
    let approvalError = "Could not approve event subscription."
    let removalError = "Could not remove event subscription."
    #expect(
      AgentEventOwnerPresentation.operationErrorDescription(approvalError)
        == approvalError
    )
    #expect(
      AgentEventOwnerPresentation.operationErrorDescription(removalError)
        == removalError
    )
  }

  private func makeSubscriptionSummary(
    id: String,
    state: AgentEventOwnerState,
    allowsAutomaticRenewal: Bool = false,
    consentGenerationID: UUID? = UUID()
  ) -> AgentEventOwnerSummary {
    AgentEventOwnerSummary(
      id: id,
      profileID: UUID(),
      event: .noteUpdated,
      scope: .note(noteID: UUID()),
      callbackHost: "events.example.test",
      state: state,
      expiresAt: Date(timeIntervalSince1970: 0),
      lastReceiptAt: nil,
      allowsAutomaticRenewal: allowsAutomaticRenewal,
      consentGenerationID: consentGenerationID
    )
  }
}
