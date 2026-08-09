#if os(macOS)
  import SwiftUI
  import FleckCore

  struct AgentNoteAccessEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var accessByProfileID: [UUID: AgentNoteAccessLevel] = [:]
    @State private var baselineCapabilities: [UUID: AgentProfileCapabilities] = [:]
    @State private var errorMessage: String?

    var body: some View {
      Form {
        Section("Agent access") {
          let profiles = AgentProfilesPresentation.active(appState.agentProfiles)
          if profiles.isEmpty {
            Text("No active profiles")
              .foregroundStyle(.secondary)
          } else {
            ForEach(profiles) { profile in
              let editable = AgentCapabilityPresentation.canEditNoteAccess(
                for: note.id,
                profileID: profile.id,
                baselineCapabilities: baselineCapabilities,
                workspace: appState.workspace
              )
              let inherited = !editable
              Picker(
                profile.displayName,
                selection: binding(for: profile.id)
              ) {
                ForEach(AgentNoteAccessLevel.allCases, id: \.self) { level in
                  Text(level.title).tag(level)
                }
              }
              .accessibilityValue(
                AgentCapabilityPresentation.noteAccessAccessibilityLabel(
                  accessByProfileID[profile.id] ?? .off
                )
              )
              .disabled(inherited)
              .accessibilityHint(
                inherited ? AgentCapabilityPresentation.inheritedAccessMessage : ""
              )
              if inherited {
                Text(AgentCapabilityPresentation.inheritedAccessMessage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.orange)
        }

        HStack {
          Spacer()
          Button("Cancel") { dismiss() }
          Button("Save") { save() }
            .keyboardShortcut(.defaultAction)
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: 420, minHeight: 260)
      .onAppear(perform: loadDraft)
    }

    private func binding(for profileID: UUID) -> Binding<AgentNoteAccessLevel> {
      Binding(
        get: { accessByProfileID[profileID] ?? .off },
        set: { accessByProfileID[profileID] = $0 }
      )
    }

    private func loadDraft() {
      guard baselineCapabilities.isEmpty else { return }
      for profile in AgentProfilesPresentation.active(appState.agentProfiles) {
        guard let capabilities = appState.capabilityProfile(profile.id) else { continue }
        baselineCapabilities[profile.id] = capabilities
        accessByProfileID[profile.id] = AgentCapabilityPresentation.noteAccess(
          for: note.id,
          profile: capabilities,
          workspace: appState.workspace
        )
      }
    }

    private func save() {
      let replacements = baselineCapabilities.values
        .sorted { $0.profileID.uuidString < $1.profileID.uuidString }
        .compactMap {
        baseline -> (
          profile: AgentProfileCapabilities,
          expectedGrantRevision: UInt64
        )? in
        guard
          let level = accessByProfileID[baseline.profileID],
          level != AgentCapabilityPresentation.noteAccess(
            for: note.id,
            profile: baseline,
            workspace: appState.workspace
          ),
          let replacement = AgentCapabilityPresentation.noteAccessReplacementIfEditable(
            noteID: note.id,
            level: level,
            baseline: baseline,
            workspace: appState.workspace
          )
        else { return nil }
        return (
          profile: replacement,
          expectedGrantRevision: baseline.grantRevision
        )
      }
      guard !replacements.isEmpty else {
        dismiss()
        return
      }
      errorMessage = nil
      Task { @MainActor in
        switch await appState.updateAgentCapabilities(replacements) {
        case .succeeded:
          dismiss()
        case .revisionConflict:
          errorMessage = AgentCapabilityPresentation.conflictMessage
        case .failed:
          errorMessage = "Could not update Agent access. Try again."
        }
      }
    }
  }
#endif
