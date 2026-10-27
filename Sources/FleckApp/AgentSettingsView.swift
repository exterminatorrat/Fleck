#if os(macOS)
  import AppKit
  import FleckCore
  import Foundation
  import SwiftUI

  enum AgentProfilesPresentation {
    static func active(_ profiles: [AgentIntegrationProfile]) -> [AgentIntegrationProfile] {
      profiles.filter { !$0.isRevoked }
    }
  }

  enum AgentConnectorPresentation {
    enum Action: Equatable {
      case install
      case refresh
    }

    static let sectionTitle = "Agent Connector"
    static let installTitle = "Install Agent Connector"
    static let refreshTitle = "Refresh Status"
    static let explanation =
      "A local helper lets authorized tools use only explicitly shared notes. It opens no network listener."

    static func primaryActionTitle(installed: Bool) -> String {
      installed ? refreshTitle : installTitle
    }

    static func action(installed: Bool) -> Action {
      installed ? .refresh : .install
    }

    static func canAddIntegration(
      workspaceAvailable: Bool,
      connectorInstalled: Bool
    ) -> Bool {
      workspaceAvailable && connectorInstalled
    }
  }

  enum AgentEventOwnerPresentation {
    static let observationPermissionDescription =
      "Event observation is off by default. Allowing it lets this profile request subscriptions; "
      + "you must separately approve each subscription and, if desired, automatic renewal for the same scope and host."
    static let renewalConsentDescription =
      "Approving or resuming enables delivery. Leave automatic renewal off for delivery-only approval; "
      + "select it only for this same event scope and callback host. Data an agent already received cannot be recalled."
    static let receiptDescription =
      "A callback receipt confirms the endpoint accepted the event; it does not confirm that an agent read or acted on it."
    static let globalPrivacyDescription =
      "These exclusions apply across every agent profile, separately from each profile’s access settings, "
      + "and override existing grants. Turning one off may restore access through an existing grant "
      + "but never creates a new one; folder exclusions also cover notes in that folder."
    static let removalConfirmationDescription =
      "Removing stops future delivery and deletes pending events. Data an agent already received cannot be recalled."
    static let chatGPTConnectionDescription =
      "OpenAI’s Secure MCP Tunnel can connect a configured stdio MCP server without public exposure "
      + "in ChatGPT developer mode. A Fleck connection still needs separate setup and a connection test; "
      + "no tunnel or account is configured here."

    static func operationErrorDescription(_ sanitizedError: String) -> String {
      sanitizedError
    }

    static func eventTitle(_ event: AgentEventName) -> String {
      switch event {
      case .noteCreated: "Note created"
      case .noteUpdated: "Note updated"
      case .taskStateChanged: "Task state changed"
      }
    }

    static func scopeSummary(
      for scope: AgentEventScope,
      in workspace: Workspace
    ) -> String {
      switch scope {
      case .note(let noteID):
        guard let note = workspace.notes.first(where: { $0.id == noteID }) else {
          return "Note unavailable"
        }
        return "Note “\(note.displayTitle)”"
      case .folder(let folderID):
        guard let folder = workspace.folders.first(where: { $0.id == folderID }) else {
          return "Folder unavailable"
        }
        return "Folder “\(folder.name)”"
      }
    }

    static func callbackHost(from callbackHost: String) -> String {
      let candidate =
        callbackHost.contains("://")
        ? callbackHost
        : "https://\(callbackHost)"
      guard let host = URLComponents(string: candidate)?.host, !host.isEmpty else {
        return "Host unavailable"
      }
      return host
    }

    static func statusTitle(for state: AgentEventOwnerState) -> String {
      switch state {
      case .awaitingApproval: "Awaiting owner approval"
      case .awaitingVerification: "Awaiting callback verification"
      case .enabled: "Enabled"
      case .paused: "Paused"
      case .pausedCapacity: "Paused at capacity"
      case .pausedHistory: "Paused for history recovery"
      case .retrying: "Retrying"
      case .stopped: "Stopped"
      case .expired: "Expired"
      case .unavailable: "Unavailable"
      }
    }

    static func statusDetail(for state: AgentEventOwnerState) -> String {
      switch state {
      case .awaitingApproval:
        "Owner approval is required; delivery stays paused."
      case .awaitingVerification:
        "Callback verification is pending; delivery stays paused."
      case .enabled:
        "Owner-approved event delivery is active for this subscription."
      case .paused:
        "Delivery is paused until you approve and resume."
      case .pausedCapacity:
        "Pending events are retained. An in-flight delivery may free capacity; "
          + "a fully blocked backlog cannot be resumed from this row. "
          + "Pause or remove the subscription to stop it."
      case .pausedHistory:
        "Required history is unavailable, so delivery remains paused. "
          + "Fleck cannot replay that history or silently restart this subscription."
      case .retrying:
        "Delivery retry is in progress; a callback receipt is still required."
      case .stopped:
        "This subscription is stopped. Restore its profile and required access, "
          + "then refresh status."
      case .expired:
        "This subscription expired. Ask the client to request a fresh subscription, "
          + "then review and approve that request. New subscriptions start at the "
          + "current event head; Fleck does not replay prior history."
      case .unavailable:
        "This subscription is unavailable. Restore the profile, access, or local "
          + "availability, then refresh status."
      }
    }

    static func approvalActionTitle(
      for state: AgentEventOwnerState,
      allowsAutomaticRenewal: Bool
    ) -> String? {
      switch state {
      case .awaitingApproval, .awaitingVerification, .paused:
        return "Approve & Resume"
      case .enabled, .retrying:
        return allowsAutomaticRenewal ? nil : "Approve Renewal"
      case .pausedCapacity, .pausedHistory, .stopped, .expired, .unavailable:
        return nil
      }
    }

    static func canPause(_ state: AgentEventOwnerState) -> Bool {
      switch state {
      case .paused: false
      default: true
      }
    }
  }

  struct AgentEventOwnerConsentSelection {
    private var optedInSubscriptionIDs: Set<String> = []

    func allowsAutomaticRenewal(for subscription: AgentEventOwnerSummary) -> Bool {
      optedInSubscriptionIDs.contains(subscription.id)
    }

    mutating func setAutomaticRenewal(
      _ enabled: Bool,
      for subscription: AgentEventOwnerSummary
    ) {
      if enabled {
        optedInSubscriptionIDs.insert(subscription.id)
      } else {
        optedInSubscriptionIDs.remove(subscription.id)
      }
    }

    func approvalOptions(
      for subscription: AgentEventOwnerSummary
    ) -> (enabled: Bool, allowsAutomaticRenewal: Bool) {
      (
        enabled: true,
        allowsAutomaticRenewal: allowsAutomaticRenewal(for: subscription)
      )
    }

    mutating func consumeApprovalOptions(
      for subscription: AgentEventOwnerSummary
    ) -> (enabled: Bool, allowsAutomaticRenewal: Bool) {
      let options = approvalOptions(for: subscription)
      setAutomaticRenewal(false, for: subscription)
      return options
    }

    func canApplyApproval(for subscription: AgentEventOwnerSummary) -> Bool {
      switch subscription.state {
      case .enabled, .retrying:
        allowsAutomaticRenewal(for: subscription)
      default:
        true
      }
    }
  }

  enum AgentIntegrationKind: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claudeCode = "Claude Code"
    case kimi = "Kimi"
    case genericCLI = "Generic CLI"

    var id: Self { self }

    var displayName: String { rawValue }

    var description: String {
      switch self {
      case .codex:
        "Connect Codex to explicitly shared notes."
      case .claudeCode:
        "Connect Claude Code to explicitly shared notes."
      case .kimi:
        "Connect Kimi to explicitly shared notes."
      case .genericCLI:
        "Connect another local CLI to explicitly shared notes."
      }
    }

    var addButtonTitle: String { "Add \(displayName)" }
  }

  struct AgentSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.settingsSearchRequest) private var searchRequest
    @Environment(\.fleckThemeSnapshot) private var theme
    @State private var showsClearConfirmation = false
    @State private var showsAgentActivity = false
    @State private var cursorSetupTask: Task<Void, Never>?
    @State private var profileForCapabilities: AgentIntegrationProfile?
    @State private var isActivityExpanded = false
    @State private var isAccessExpanded = false
    @State private var subscriptionPendingRemoval: AgentEventOwnerSummary?
    @State private var ownerConsentSelection = AgentEventOwnerConsentSelection()

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        connectorStatus
        availableIntegrations
        connectedProfiles
        eventSubscriptions
        globalPrivacyControls
        setupInstructions
        VStack(alignment: .leading, spacing: 4) {
          DisclosureGroup("Activity", isExpanded: $isActivityExpanded) {
            VStack(alignment: .leading, spacing: 8) {
              SettingsPreferenceRow(
                "Show agent update banners",
                detail: "Show banners for future agent changes. Turning this on does not replay earlier changes; Agent Activity remains available."
              ) {
                Toggle(
                  isOn: Binding(
                    get: { appState.preferences.showAgentUpdateBanners },
                    set: { enabled in
                      appState.updatePreferences { $0.showAgentUpdateBanners = enabled }
                    }
                  )
                ) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Show agent update banners")
              }
              .settingsSearchAnchor(.agentsUpdateBanners, request: searchRequest)
              Text("Review changes made by authorized local integrations.")
                .font(.caption)
                .foregroundStyle(.secondary)
              Button("Open Agent Activity") {
                showsAgentActivity = true
              }
              .settingsSearchAnchor(.agentsOpenActivity, request: searchRequest)
              .sheet(isPresented: $showsAgentActivity) {
                AgentActivityView(
                  onOpenNote: { noteID in
                    appState.select(noteID)
                    showsAgentActivity = false
                  },
                  onDismiss: { showsAgentActivity = false }
                )
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 380)
              }
              Button("Clear Activity", role: .destructive) {
                showsClearConfirmation = true
              }
              .settingsSearchAnchor(.agentsClearActivity, request: searchRequest)
              .confirmationDialog("Clear Agent Activity?", isPresented: $showsClearConfirmation) {
                Button("Clear Activity", role: .destructive) {
                  appState.clearAgentActivity()
                }
                Button("Cancel", role: .cancel) {}
              }
            }
            .padding(.top, 4)
            .accessibilityIdentifier("settings-agents-activity-content")
            .background(SettingsSearchProbe(identifier: "settings-agents-activity-content"))
          }
          .disclosureGroupStyle(SettingsDisclosureGroupStyle())
          .settingsSearchAnchor(.agentsActivity, request: searchRequest)
          DisclosureGroup("Access", isExpanded: $isAccessExpanded) {
            Text(
              "Only notes with explicit capability grants can be read or edited by authorized integrations. This protects against cooperative tools, not malicious software already running as your macOS user."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityIdentifier("settings-agents-access-content")
            .background(SettingsSearchProbe(identifier: "settings-agents-access-content"))
          }
          .disclosureGroupStyle(SettingsDisclosureGroupStyle())
          .settingsSearchAnchor(.agentsAccess, request: searchRequest)
        }
      }
      .onChange(of: searchRequest?.id, initial: true) { _, _ in
        revealSearchTarget()
      }
      .onDisappear {
        cancelCursorSetup()
      }
      .sheet(item: $profileForCapabilities) { profile in
        if let capabilities = appState.capabilityProfile(profile.id) {
          AgentCapabilityEditorView(
            profile: profile,
            capabilities: capabilities
          )
          .environmentObject(appState)
        }
      }
      .confirmationDialog(
        "Remove event subscription?",
        isPresented: Binding(
          get: { subscriptionPendingRemoval != nil },
          set: { if !$0 { subscriptionPendingRemoval = nil } }
        )
      ) {
        Button("Remove", role: .destructive) {
          guard let subscription = subscriptionPendingRemoval else { return }
          subscriptionPendingRemoval = nil
          ownerConsentSelection.setAutomaticRenewal(false, for: subscription)
          Task {
            await appState.removeAgentEventMonitoringSubscription(
              subscriptionID: subscription.id
            )
          }
        }
        Button("Cancel", role: .cancel) {
          subscriptionPendingRemoval = nil
        }
      } message: {
        Text(AgentEventOwnerPresentation.removalConfirmationDescription)
      }
    }

    private func revealSearchTarget() {
      switch searchRequest?.anchor {
      case .agentsActivity, .agentsUpdateBanners, .agentsOpenActivity, .agentsClearActivity:
        isActivityExpanded = true
      case .agentsAccess:
        isAccessExpanded = true
      default:
        break
      }
    }

    private var connectorStatus: some View {
      VStack(alignment: .leading, spacing: 6) {
        SettingsPreferenceRow(
          AgentConnectorPresentation.sectionTitle,
          detail: AgentConnectorPresentation.explanation
        ) {
          VStack(alignment: .trailing, spacing: 6) {
            Text(appState.isAgentConnectorInstalled ? "Installed" : "Not Installed")
              .font(.caption.weight(.medium))
            Button(
              AgentConnectorPresentation.primaryActionTitle(
                installed: appState.isAgentConnectorInstalled
              )
            ) {
              Task {
                switch AgentConnectorPresentation.action(
                  installed: appState.isAgentConnectorInstalled
                ) {
                case .install:
                  await appState.installAgentBridge()
                case .refresh:
                  await appState.refreshAgentConnectorStatus()
                }
              }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(
              AgentConnectorPresentation.primaryActionTitle(
                installed: appState.isAgentConnectorInstalled
              )
            )
            .accessibilityHint(
              appState.isAgentConnectorInstalled
                ? "Checks the local connector installation status"
                : "Installs the local connector used by authorized integrations"
            )
          }
        }
        if let error = appState.agentCleanupError {
          Text(error).font(.caption).foregroundStyle(theme.color(.error))
        }
      }
      .task {
        await appState.refreshAgentConnectorStatus()
      }
      .settingsSearchAnchor(.agentsConnector, request: searchRequest)
    }

    private var availableIntegrations: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Available Integrations")
          .font(.headline)
        cursorIntegrationRow
        ForEach(AgentIntegrationKind.allCases) { integration in
          integrationRow(integration)
        }
      }
    }

    private var cursorIntegrationRow: some View {
      VStack(alignment: .leading, spacing: 6) {
        SettingsPreferenceRow(
          "Cursor",
          detail:
            "Uses Cursor's documented local MCP install prompt. The helper is installed if needed; new profiles start with no access, and existing access is shown below and never changed. Cursor will ask before installing."
        ) {
          Button("Set up in Cursor…") {
            beginCursorSetup()
          }
          .disabled(isCursorSetupBlocked)
        }
        if let message = appState.cursorSetupStatus.message {
          Text(message)
            .font(.caption)
            .foregroundStyle(
              appState.cursorSetupStatus.isError ? theme.color(.error) : Color.secondary
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        if cursorSetupTask != nil {
          Button("Cancel setup", role: .cancel) {
            cancelCursorSetup()
          }
          .controlSize(.small)
        }
      }
    }

    private var isCursorSetupBlocked: Bool {
      cursorSetupTask != nil
        || appState.cursorSetupStatus.isInProgress
        || !appState.isAgentWorkspaceAvailable
    }

    private func beginCursorSetup(
      profileID: UUID? = nil,
      expectedCapabilities: AgentProfileCapabilities? = nil
    ) {
      guard !isCursorSetupBlocked else { return }
      cursorSetupTask = Task {
        await appState.setUpCursor(
          profileID: profileID,
          expectedCapabilities: expectedCapabilities
        )
        cursorSetupTask = nil
      }
    }

    private func cancelCursorSetup() {
      cursorSetupTask?.cancel()
    }

    private func integrationRow(_ integration: AgentIntegrationKind) -> some View {
      SettingsPreferenceRow(integration.displayName, detail: integration.description) {
        addButton(for: integration)
      }
      .settingsSearchAnchor(.agentIntegration(integration), request: searchRequest)
    }

    private func addButton(for integration: AgentIntegrationKind) -> some View {
      Button(integration.addButtonTitle) {
        Task { await appState.addAgentProfile(named: integration.displayName) }
      }
      .disabled(
        !AgentConnectorPresentation.canAddIntegration(
          workspaceAvailable: appState.isAgentWorkspaceAvailable,
          connectorInstalled: appState.isAgentConnectorInstalled
        )
      )
    }

    private var connectedProfiles: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Connected Profiles")
          .font(.headline)
        Text(
          "Profiles can be prepared before a client accepts an install prompt. Times below reflect only connections Fleck has recorded."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        let profiles = AgentProfilesPresentation.active(appState.agentProfiles)
        if profiles.isEmpty {
          Text("No integrations connected yet. Add one above when the local connector is ready.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(profiles) { profile in
            connectedProfile(profile)
          }
        }
      }
      .settingsSearchAnchor(.agentsConnectedProfiles, request: searchRequest)
    }

    private var eventSubscriptions: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Event subscriptions")
            .font(.headline)
          Spacer()
          Button("Refresh Status") {
            Task { await appState.refreshAgentEventMonitoring() }
          }
          .controlSize(.small)
          .accessibilityLabel("Refresh event subscription status")
        }
        Text(AgentEventOwnerPresentation.renewalConsentDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(AgentEventOwnerPresentation.receiptDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let error = appState.agentEventMonitoringError {
          Text(AgentEventOwnerPresentation.operationErrorDescription(error))
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if appState.agentEventSubscriptions.isEmpty {
          Text(
            appState.agentEventMonitoringError == nil
              ? "No subscriptions are listed. Refresh status to check this Mac."
              : "No saved subscription details are available."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          ForEach(appState.agentEventSubscriptions) { subscription in
            eventSubscriptionRow(subscription)
          }
        }
      }
    }

    private func eventSubscriptionRow(
      _ subscription: AgentEventOwnerSummary
    ) -> some View {
      let eventTitle = AgentEventOwnerPresentation.eventTitle(subscription.event)
      let statusTitle = AgentEventOwnerPresentation.statusTitle(for: subscription.state)
      let statusDetail = AgentEventOwnerPresentation.statusDetail(for: subscription.state)
      let profileName =
        appState.agentProfiles.first {
          $0.id == subscription.profileID
        }?.displayName ?? "Unavailable"
      let scopeSummary = AgentEventOwnerPresentation.scopeSummary(
        for: subscription.scope,
        in: appState.workspace
      )
      let callbackHost = AgentEventOwnerPresentation.callbackHost(from: subscription.callbackHost)
      let approvalTitle = AgentEventOwnerPresentation.approvalActionTitle(
        for: subscription.state,
        allowsAutomaticRenewal: subscription.allowsAutomaticRenewal
      )

      return VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(eventTitle)
            .font(.callout.weight(.medium))
          Spacer()
          Text(statusTitle)
            .font(.caption.weight(.semibold))
            .accessibilityLabel("Subscription status: \(statusTitle)")
        }
        Text("Profile: \(profileName)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Scope: \(scopeSummary)")
          .font(.caption)
        Text("Callback host: \(callbackHost)")
          .font(.caption)
        Text(statusDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
        if approvalTitle != nil {
          Toggle(
            "Allow automatic renewal",
            isOn: Binding(
              get: { ownerConsentSelection.allowsAutomaticRenewal(for: subscription) },
              set: { enabled in
                ownerConsentSelection.setAutomaticRenewal(enabled, for: subscription)
              }
            )
          )
          .accessibilityHint(AgentEventOwnerPresentation.renewalConsentDescription)
        }
        Text(
          subscription.allowsAutomaticRenewal
            ? "Automatic renewal approved for this same scope and host"
            : "Automatic renewal not approved"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Text(
          "Expires \(subscription.expiresAt.formatted(date: .abbreviated, time: .shortened))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if let lastReceiptAt = subscription.lastReceiptAt {
          Text(
            "Last callback receipt: \(lastReceiptAt.formatted(date: .abbreviated, time: .shortened))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
          if let title = approvalTitle {
            Button(title) {
              let options = ownerConsentSelection.consumeApprovalOptions(for: subscription)
              Task {
                await appState.setAgentEventMonitoring(
                  subscriptionID: subscription.id,
                  enabled: options.enabled,
                  allowsAutomaticRenewal: options.allowsAutomaticRenewal
                )
              }
            }
            .disabled(!ownerConsentSelection.canApplyApproval(for: subscription))
            .accessibilityHint(AgentEventOwnerPresentation.renewalConsentDescription)
          }
          Button("Pause") {
            ownerConsentSelection.setAutomaticRenewal(false, for: subscription)
            Task {
              await appState.setAgentEventMonitoring(
                subscriptionID: subscription.id,
                enabled: false,
                allowsAutomaticRenewal: false
              )
            }
          }
          .disabled(!AgentEventOwnerPresentation.canPause(subscription.state))
          Button("Remove…", role: .destructive) {
            subscriptionPendingRemoval = subscription
          }
        }
        .controlSize(.small)
      }
      .padding(.vertical, 8)
    }

    private var globalPrivacyControls: some View {
      DisclosureGroup("Global privacy") {
        VStack(alignment: .leading, spacing: 8) {
          Text(AgentEventOwnerPresentation.globalPrivacyDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          DisclosureGroup("Private notes") {
            if appState.workspace.notes.isEmpty {
              Text("No notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              ForEach(appState.workspace.notes) { note in
                Toggle(
                  "Exclude \(note.displayTitle) from all agents",
                  isOn: privateNoteBinding(for: note.id)
                )
                .accessibilityHint("Overrides note grants for every agent profile")
              }
            }
          }
          DisclosureGroup("Private folders") {
            if appState.workspace.folders.isEmpty {
              Text("No folders")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              ForEach(appState.workspace.folders, id: \.id) { folder in
                Toggle(
                  "Exclude folder “\(folder.name)” from all agents",
                  isOn: privateFolderBinding(for: folder.id)
                )
                .accessibilityHint(
                  "Overrides folder grants for every agent profile and excludes notes in this folder"
                )
              }
            }
          }
        }
        .padding(.top, 4)
      }
    }

    private func connectedProfile(_ profile: AgentIntegrationProfile) -> some View {
      SettingsPreferenceRow(profile.displayName, detail: lastConnection(profile)) {
        VStack(alignment: .trailing, spacing: 7) {
          Button("Revoke", role: .destructive) {
            Task { await appState.revokeAgentProfile(profile) }
          }
          .accessibilityHint("Revokes this local integration profile")
          if let capabilities = appState.capabilityProfile(profile.id) {
            let summary = AgentCapabilityPresentation.profileSummary(
              for: capabilities,
              isActive: true,
              workspace: appState.workspace,
              unassignedLegacyNoteIDs: appState.agentCapabilityState.unassignedLegacyNoteIDs
            )
            VStack(alignment: .trailing, spacing: 4) {
              Text(summary.scopeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(summary.accessibilityLabel)
              if profile.displayName == "Cursor" {
                if let configuration = appState.cursorManualConfiguration(profileID: profile.id) {
                  Button("Copy Cursor JSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configuration, forType: .string)
                  }
                  Text(
                    "Merge this entry under “mcpServers” in Cursor's existing config; preserve unrelated entries."
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
                }
                Button("Open in Cursor…") {
                  beginCursorSetup(
                    profileID: profile.id,
                    expectedCapabilities: capabilities
                  )
                }
                .disabled(isCursorSetupBlocked)
                .accessibilityHint(
                  "Requests Cursor's install prompt using this profile's displayed access scope without changing its grants"
                )
              }
              Button("Edit Capabilities…") {
                profileForCapabilities = profile
              }
            }
          }
          if profile.displayName != "Cursor",
            let snippet = appState.agentSetupSnippet(profileID: profile.id)
          {
            VStack(alignment: .trailing, spacing: 4) {
              Text(snippet)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
              Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snippet, forType: .string)
              }
            }
          }
        }
      }
    }

    private var setupInstructions: some View {
      VStack(alignment: .leading, spacing: 10) {
        Text("Set up a local integration")
          .font(.headline)
        Text("Connect a local tool and grant only the access it needs.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        setupStep(
          number: 1,
          title: "Install the local connector",
          detail: "The connector stays on this Mac and opens no network listener."
        )
        setupStep(
          number: 2,
          title: "Add an integration",
          detail: "Choose one of the available integrations above."
        )
        setupStep(
          number: 3,
          title: "Use the generated local snippet",
          detail: "Copy the snippet and grant only the note capabilities you need."
        )
        Text(AgentEventOwnerPresentation.chatGPTConnectionDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .settingsSearchAnchor(.agentsSetup, request: searchRequest)
    }

    private func setupStep(number: Int, title: String, detail: String) -> some View {
      HStack(alignment: .top, spacing: 10) {
        Text("\(number)")
          .font(.caption.weight(.semibold))
          .frame(width: 20, height: 20)
          .background(Circle().fill(.quaternary))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.callout.weight(.medium))
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    private func lastConnection(_ profile: AgentIntegrationProfile) -> String {
      guard let date = profile.lastConnectedAt else { return "Never connected" }
      return "Last connected \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func privateNoteBinding(for noteID: UUID) -> Binding<Bool> {
      Binding(
        get: { appState.agentPrivateNoteIDs.contains(noteID) },
        set: { isPrivate in
          Task { await appState.setAgentNotePrivate(noteID: noteID, isPrivate: isPrivate) }
        }
      )
    }

    private func privateFolderBinding(for folderID: UUID) -> Binding<Bool> {
      Binding(
        get: { appState.agentPrivateFolderIDs.contains(folderID) },
        set: { isPrivate in
          Task { await appState.setAgentFolderPrivate(folderID: folderID, isPrivate: isPrivate) }
        }
      )
    }
  }
#endif
