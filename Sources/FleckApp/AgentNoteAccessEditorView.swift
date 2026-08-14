#if os(macOS)
  import SwiftUI
  import FleckCore

  struct AgentNoteAccessEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let note: Note
    let onDismiss: (() -> Void)?
    @State private var accessByProfileID: [UUID: AgentNoteAccessLevel] = [:]
    @State private var baselineCapabilities: [UUID: AgentProfileCapabilities] = [:]
    @State private var baselineWorkspace = Workspace()
    @State private var baselineNoteAccessContext: AgentNoteAccessContext?
    @State private var displayedProfiles: [AgentIntegrationProfile] = []
    @State private var hasLoadedDraft = false
    @State private var errorMessage: String?

    init(note: Note, onDismiss: (() -> Void)? = nil) {
      self.note = note
      self.onDismiss = onDismiss
    }

    var body: some View {
      Form {
        Section("Agent access") {
          if displayedProfiles.isEmpty {
            Text("No active profiles")
              .foregroundStyle(.secondary)
          } else {
            ForEach(displayedProfiles) { profile in
              let rowState = AgentCapabilityPresentation.noteAccessRowState(
                for: note.id,
                profileID: profile.id,
                baselineCapabilities: baselineCapabilities,
                workspace: baselineWorkspace
              )
              let rowMessage = message(for: rowState)
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
              .disabled(rowState != .editable)
              .accessibilityHint(rowMessage ?? "")
              .pickerStyle(.segmented)
              if let rowMessage {
                Text(rowMessage)
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
          Button("Cancel") { closeEditor() }
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

    private func message(for state: AgentNoteAccessRowState) -> String? {
      switch state {
      case .editable:
        nil
      case .inheritedFolder:
        AgentCapabilityPresentation.inheritedAccessMessage
      case .unavailable:
        AgentCapabilityPresentation.unavailableAccessMessage
      }
    }

    private func loadDraft() {
      guard !hasLoadedDraft else { return }
      let workspace = appState.workspace
      baselineWorkspace = workspace
      baselineNoteAccessContext = AgentCapabilityPresentation.noteAccessContext(
        for: note.id,
        in: workspace
      )
      displayedProfiles = AgentCapabilityPresentation.snapshotActiveProfiles(
        appState.agentProfiles
      )
      for profile in displayedProfiles {
        if let capabilities = appState.capabilityProfile(profile.id) {
          baselineCapabilities[profile.id] = capabilities
          accessByProfileID[profile.id] = AgentCapabilityPresentation.noteAccess(
            for: note.id,
            profile: capabilities,
            workspace: workspace
          )
        }
      }
      hasLoadedDraft = true
    }

    private func save() {
      errorMessage = nil
      guard
        hasLoadedDraft,
        let capturedContext = baselineNoteAccessContext,
        displayedProfiles.allSatisfy({ baselineCapabilities[$0.id] != nil })
      else {
        errorMessage = AgentCapabilityPresentation.unavailableAccessMessage
        return
      }
      guard AgentCapabilityPresentation.noteAccessContextIsUnchanged(
        noteID: note.id,
        captured: capturedContext,
        workspace: appState.workspace
      ) else {
        errorMessage = AgentCapabilityPresentation.noteAccessContextChangedMessage
        return
      }

      let currentWorkspace = appState.workspace

      let expectedGrantRevisions = [UUID: UInt64](
        uniqueKeysWithValues: displayedProfiles.compactMap { profile in
          guard let baseline = baselineCapabilities[profile.id] else { return nil }
          return (profile.id, baseline.grantRevision)
        }
      )
      let replacements: [
        (profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)
      ] = baselineCapabilities.values
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
            workspace: baselineWorkspace
          ),
          let replacement = AgentCapabilityPresentation.noteAccessReplacementIfContextUnchanged(
            noteID: note.id,
            level: level,
            baseline: baseline,
            baselineWorkspace: baselineWorkspace,
            capturedContext: capturedContext,
            currentWorkspace: currentWorkspace
          )
        else { return nil }
        return (
          profile: replacement,
          expectedGrantRevision: baseline.grantRevision
        )
      }
      Task { @MainActor in
        guard AgentCapabilityPresentation.noteAccessContextIsUnchanged(
          noteID: note.id,
          captured: capturedContext,
          workspace: appState.workspace
        ) else {
          errorMessage = AgentCapabilityPresentation.noteAccessContextChangedMessage
          return
        }
        switch await appState.updateAgentCapabilitiesForNote(
          noteID: note.id,
          capturedContext: capturedContext,
          replacements: replacements,
          expectedGrantRevisions: expectedGrantRevisions
        ) {
        case .succeeded:
          closeEditor()
        case .revisionConflict:
          errorMessage = AgentCapabilityPresentation.conflictMessage
        case .contextChanged:
          errorMessage = AgentCapabilityPresentation.noteAccessContextChangedMessage
        case .failed:
          errorMessage = "Could not update Agent access. Try again."
        }
      }
    }

    private func closeEditor() {
      if let onDismiss {
        onDismiss()
      } else {
        dismiss()
      }
    }
  }
#endif
