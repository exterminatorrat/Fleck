#if os(macOS)
  import AppKit
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
    @State private var showsClearConfirmation = false
    @State private var showsAgentActivity = false
    @State private var profileForCapabilities: AgentIntegrationProfile?
    @State private var isActivityExpanded = false
    @State private var isAccessExpanded = false

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        connectorStatus
        availableIntegrations
        connectedProfiles
        setupInstructions
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
      .onChange(of: searchRequest?.id, initial: true) { _, _ in
        revealSearchTarget()
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
          Text(error).font(.caption).foregroundStyle(.orange)
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
        ForEach(AgentIntegrationKind.allCases) { integration in
          integrationRow(integration)
        }
      }
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
              Button("Edit Capabilities…") {
                profileForCapabilities = profile
              }
            }
          }
          if let snippet = appState.agentSetupSnippet(profileID: profile.id) {
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
  }
#endif
