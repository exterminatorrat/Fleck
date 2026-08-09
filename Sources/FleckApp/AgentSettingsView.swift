#if os(macOS)
  import AppKit
  import SwiftUI

  enum AgentProfilesPresentation {
    static func active(_ profiles: [AgentIntegrationProfile]) -> [AgentIntegrationProfile] {
      profiles.filter { !$0.isRevoked }
    }
  }

  enum AgentConnectorPresentation {
    static let sectionTitle = "Agent Connector"
    static let installTitle = "Install Agent Connector"
    static let explanation =
      "A local helper lets authorized tools use only explicitly shared notes. It opens no network listener."

    static func canAddIntegration(
      workspaceAvailable: Bool,
      connectorInstalled: Bool
    ) -> Bool {
      workspaceAvailable && connectorInstalled
    }
  }

  struct AgentSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsClearConfirmation = false
    @State private var showsAgentActivity = false
    @State private var profileForCapabilities: AgentIntegrationProfile?

    var body: some View {
      Section(AgentConnectorPresentation.sectionTitle) {
        LabeledContent(
          "Status",
          value: appState.isAgentConnectorInstalled ? "Installed" : "Not Installed"
        )
        Text(AgentConnectorPresentation.explanation)
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(AgentConnectorPresentation.installTitle) {
          Task { await appState.installAgentBridge() }
        }
        if let error = appState.agentCleanupError {
          Text(error).font(.caption).foregroundStyle(.orange)
        }
      }
      .task {
        await appState.refreshAgentConnectorStatus()
      }

      Section("Integrations") {
        HStack {
          addButton("Add Codex", name: "Codex")
          addButton("Add Claude Code", name: "Claude Code")
          addButton("Add Kimi", name: "Kimi")
          addButton("Generic CLI", name: "Generic CLI")
        }
        ForEach(AgentProfilesPresentation.active(appState.agentProfiles)) { profile in
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(profile.displayName).font(.headline)
              Spacer()
              Button("Revoke", role: .destructive) {
                Task { await appState.revokeAgentProfile(profile) }
              }
            }
            Text(lastConnection(profile))
              .font(.caption)
              .foregroundStyle(.secondary)
            if let capabilities = appState.capabilityProfile(profile.id) {
              let summary = AgentCapabilityPresentation.profileSummary(
                for: capabilities,
                isActive: true,
                workspace: appState.workspace,
                unassignedLegacyNoteIDs: appState.agentCapabilityState.unassignedLegacyNoteIDs
              )
              Text(summary.scopeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(summary.accessibilityLabel)
              Button("Edit Capabilities…") {
                profileForCapabilities = profile
              }
            }
            if let snippet = appState.agentSetupSnippet(profileID: profile.id) {
              HStack {
                Text(snippet)
                  .font(.system(.caption, design: .monospaced))
                  .lineLimit(1)
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

      Section("Activity") {
        Button("Open Agent Activity") {
          showsAgentActivity = true
        }
        .sheet(isPresented: $showsAgentActivity) {
          AgentActivityView { noteID in
            appState.select(noteID)
            showsAgentActivity = false
          }
          .environmentObject(appState)
        }
        Button("Clear Activity", role: .destructive) {
          showsClearConfirmation = true
        }
        .confirmationDialog("Clear Agent Activity?", isPresented: $showsClearConfirmation) {
          Button("Clear Activity", role: .destructive) {
            appState.clearAgentActivity()
          }
          Button("Cancel", role: .cancel) {}
        }
      }

      Section("Access") {
        Text(
          "Only notes with explicit capability grants can be read or edited by authorized integrations. This protects against cooperative tools, not malicious software already running as your macOS user."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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

    private func addButton(_ title: String, name: String) -> some View {
      Button(title) {
        Task { await appState.addAgentProfile(named: name) }
      }
      .disabled(
        !AgentConnectorPresentation.canAddIntegration(
          workspaceAvailable: appState.isAgentWorkspaceAvailable,
          connectorInstalled: appState.isAgentConnectorInstalled
        )
      )
    }

    private func lastConnection(_ profile: AgentIntegrationProfile) -> String {
      guard let date = profile.lastConnectedAt else { return "Never connected" }
      return "Last connected \(date.formatted(date: .abbreviated, time: .shortened))"
    }
  }
#endif
