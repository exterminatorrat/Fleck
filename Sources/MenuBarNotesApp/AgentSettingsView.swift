#if os(macOS)
  import AppKit
  import SwiftUI

  enum AgentProfilesPresentation {
    static func active(_ profiles: [AgentIntegrationProfile]) -> [AgentIntegrationProfile] {
      profiles.filter { !$0.isRevoked }
    }
  }

  struct AgentSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsClearConfirmation = false
    @State private var showsAgentActivity = false

    var body: some View {
      Section("Command Bridge") {
        LabeledContent(
          "Status",
          value: appState.isAgentBridgeInstalled ? "Installed" : "Not Installed"
        )
        Button("Install Command Bridge") {
          Task { await appState.installAgentBridge() }
        }
        if let error = appState.agentCleanupError {
          Text(error).font(.caption).foregroundStyle(.orange)
        }
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
          "Only notes where you enable Agent Access can be read and edited by authorized integrations. This protects against cooperative tools, not malicious software already running as your macOS user."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }

    private func addButton(_ title: String, name: String) -> some View {
      Button(title) {
        Task { await appState.addAgentProfile(named: name) }
      }
    }

    private func lastConnection(_ profile: AgentIntegrationProfile) -> String {
      guard let date = profile.lastConnectedAt else { return "Never connected" }
      return "Last connected \(date.formatted(date: .abbreviated, time: .shortened))"
    }
  }
#endif
