#if os(macOS)
  import SwiftUI
  import FleckCore

  enum AgentNoteAccessLevel: String, CaseIterable, Equatable, Sendable {
    case off
    case read
    case write

    var title: String {
      switch self {
      case .off: "Off"
      case .read: "Read"
      case .write: "Write"
      }
    }

    var authority: AgentAuthority? {
      switch self {
      case .off: nil
      case .read: .read
      case .write: .write
      }
    }
  }

  enum AgentFolderAccessLevel: String, CaseIterable, Equatable, Sendable {
    case off
    case currentNotes
    case includingFutureNotes

    var title: String {
      switch self {
      case .off: "Off"
      case .currentNotes: "Current notes only"
      case .includingFutureNotes: "Including future notes"
      }
    }
  }

  enum AgentCapabilityPresentation {
    static let noToolsOrNotesGranted = "No tools or notes granted"
    static let manageAgentAccessTitle = "Manage Agent Access…"
    static let manageAgentAccessAccessibilityLabel = "Manage Agent Access…"
    static let futureFolderConfirmationMessage =
      "This profile will automatically gain access to notes moved into this folder."
    static let unassignedLegacySharesLabel = "Unassigned legacy shares"
    static let conflictMessage =
      "This capability profile changed. Reload it before saving."
    static let inheritedAccessMessage =
      "Access is inherited from a folder. Edit the profile to change it."

    struct ProfileSummary: Equatable, Sendable {
      let summary: String
      let scopeSummary: String
      let toolsSummary: String
      let accessibilityLabel: String
      let futureFolderSummaries: [String]
    }

    static func requiresBroadGrantConfirmation(
      scope: AgentGrantScope
    ) -> Bool {
      if case .folderIncludingFutureNotes = scope { return true }
      return false
    }

    static func isShared(
      noteID: UUID,
      activeProfiles: [AgentProfileCapabilities],
      workspace: Workspace
    ) -> Bool {
      activeProfiles.contains { profile in
        AgentCapabilityPolicy.authorizationSnapshot(
          for: profile,
          workspace: workspace
        ).readableNoteIDs.contains(noteID)
      }
    }

    static func profileSummary(
      for profile: AgentProfileCapabilities,
      isActive: Bool,
      workspace: Workspace,
      unassignedLegacyNoteIDs: Set<UUID> = []
    ) -> ProfileSummary {
      guard isActive else { return emptySummary }
      let snapshot = AgentCapabilityPolicy.authorizationSnapshot(
        for: profile,
        workspace: workspace
      )
      let hasReadScope = !snapshot.readableNoteIDs.isEmpty
      let hasWriteScope = !snapshot.writableNoteIDs.isEmpty
      let scopeSummary: String
      if hasWriteScope {
        scopeSummary = "Read + Write"
      } else if hasReadScope {
        scopeSummary = "Read"
      } else {
        scopeSummary = noToolsOrNotesGranted
      }
      let toolsSummary: String
      if snapshot.availableCapabilities.isEmpty {
        toolsSummary = "No tools"
      } else if snapshot.availableCapabilities.count == 1 {
        toolsSummary = "1 tool"
      } else {
        toolsSummary = "\(snapshot.availableCapabilities.count) tools"
      }
      let futureFolderSummaries = profile.grants.compactMap { grant -> String? in
        guard
          case let .folderIncludingFutureNotes(folderID) = grant.scope,
          grant.authority.allows(.read),
          let folder = workspace.folders.first(where: { $0.id == folderID })
        else { return nil }
        return futureFolderSummary(folderName: folder.name)
      }
      .sorted()
      let summary = !hasReadScope && snapshot.availableCapabilities.isEmpty
        ? noToolsOrNotesGranted
        : scopeSummary
      let unassignedSuffix = unassignedLegacyNoteIDs.isEmpty
        ? ""
        : ". \(unassignedLegacySharesLabel)"
      return ProfileSummary(
        summary: summary,
        scopeSummary: scopeSummary,
        toolsSummary: toolsSummary,
        accessibilityLabel: "Agent capabilities: \(summary)\(unassignedSuffix)",
        futureFolderSummaries: futureFolderSummaries
      )
    }

    static func futureFolderSummary(folderName: String) -> String {
      "Includes future notes in “\(folderName)”"
    }

    static func noteAccess(
      for noteID: UUID,
      profile: AgentProfileCapabilities,
      workspace: Workspace
    ) -> AgentNoteAccessLevel {
      let snapshot = AgentCapabilityPolicy.authorizationSnapshot(
        for: profile,
        workspace: workspace
      )
      if snapshot.writableNoteIDs.contains(noteID) { return .write }
      if snapshot.readableNoteIDs.contains(noteID) { return .read }
      return .off
    }

    static func explicitNoteAccess(
      for noteID: UUID,
      profile: AgentProfileCapabilities
    ) -> AgentNoteAccessLevel {
      let directGrants = profile.grants.filter { grant in
        if case let .note(grantedNoteID) = grant.scope {
          return grantedNoteID == noteID
        }
        return false
      }
      if directGrants.contains(where: { $0.authority.allows(.write) }) {
        return .write
      }
      if directGrants.contains(where: { $0.authority.allows(.read) }) {
        return .read
      }
      return .off
    }

    static func materializeCurrentFolderNotes(
      folderID: UUID,
      workspace: Workspace,
      directAccess: [UUID: AgentNoteAccessLevel],
      materializedAccess: [UUID: AgentNoteAccessLevel]
    ) -> (
      directAccess: [UUID: AgentNoteAccessLevel],
      materializedAccess: [UUID: AgentNoteAccessLevel]
    ) {
      var updatedDirectAccess = directAccess
      var updatedMaterializedAccess = materializedAccess
      for note in workspace.notes where note.folderID == folderID {
        guard updatedDirectAccess[note.id] != .write else { continue }
        if updatedMaterializedAccess[note.id] == nil {
          updatedMaterializedAccess[note.id] = updatedDirectAccess[note.id] ?? .off
        }
        updatedDirectAccess[note.id] = .write
      }
      return (updatedDirectAccess, updatedMaterializedAccess)
    }

    static func restoreMaterializedCurrentFolderNotes(
      folderID: UUID,
      workspace: Workspace,
      directAccess: [UUID: AgentNoteAccessLevel],
      materializedAccess: [UUID: AgentNoteAccessLevel]
    ) -> (
      directAccess: [UUID: AgentNoteAccessLevel],
      materializedAccess: [UUID: AgentNoteAccessLevel]
    ) {
      var updatedDirectAccess = directAccess
      var updatedMaterializedAccess = materializedAccess
      for note in workspace.notes where note.folderID == folderID {
        guard let previousLevel = updatedMaterializedAccess.removeValue(forKey: note.id)
        else { continue }
        if previousLevel == .off {
          updatedDirectAccess.removeValue(forKey: note.id)
        } else {
          updatedDirectAccess[note.id] = previousLevel
        }
      }
      return (updatedDirectAccess, updatedMaterializedAccess)
    }

    static func capabilityReplacement(
      baseline: AgentProfileCapabilities,
      allowedCapabilities: Set<AgentCapability>,
      expectedGrantRevision: UInt64,
      directAccess: [UUID: AgentNoteAccessLevel],
      folderAccess: [UUID: AgentFolderAccessLevel]
    ) -> AgentProfileCapabilities {
      var grants = baseline.grants
      let directNoteIDs = Set(directAccess.keys)
      let folderIDs = Set(folderAccess.keys)
      grants.removeAll { grant in
        switch grant.scope {
        case let .note(noteID): directNoteIDs.contains(noteID)
        case let .folderIncludingFutureNotes(folderID): folderIDs.contains(folderID)
        }
      }
      for noteID in directAccess.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
        guard let authority = directAccess[noteID]?.authority else { continue }
        grants.append(
          AgentResourceGrant(scope: .note(noteID: noteID), authority: authority)
        )
      }
      for folderID in folderAccess.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
        guard folderAccess[folderID] == .includingFutureNotes else { continue }
        grants.append(
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folderID),
            authority: .write
          )
        )
      }
      return AgentProfileCapabilities(
        profileID: baseline.profileID,
        grantRevision: expectedGrantRevision + 1,
        allowedCapabilities: allowedCapabilities,
        grants: grants
      )
    }

    static func noteAccessReplacement(
      noteID: UUID,
      level: AgentNoteAccessLevel,
      baseline: AgentProfileCapabilities
    ) -> AgentProfileCapabilities {
      var grants = baseline.grants.filter { grant in
        if case let .note(grantedNoteID) = grant.scope {
          return grantedNoteID != noteID
        }
        return true
      }
      if let authority = level.authority {
        grants.append(
          AgentResourceGrant(scope: .note(noteID: noteID), authority: authority)
        )
      }
      return AgentProfileCapabilities(
        profileID: baseline.profileID,
        grantRevision: baseline.grantRevision + 1,
        allowedCapabilities: baseline.allowedCapabilities,
        grants: grants
      )
    }

    static func isNoteAccessInherited(
      for noteID: UUID,
      profile: AgentProfileCapabilities,
      workspace: Workspace
    ) -> Bool {
      guard
        let note = workspace.notes.first(where: { $0.id == noteID }),
        let folderID = note.folderID,
        workspace.folders.contains(where: { $0.id == folderID })
      else { return false }
      return profile.grants.contains { grant in
        guard case let .folderIncludingFutureNotes(grantedFolderID) = grant.scope
        else { return false }
        return grantedFolderID == folderID && grant.authority.allows(.read)
      }
    }

    static func canEditNoteAccess(
      for noteID: UUID,
      profile: AgentProfileCapabilities,
      workspace: Workspace
    ) -> Bool {
      !isNoteAccessInherited(
        for: noteID,
        profile: profile,
        workspace: workspace
      )
    }

    static func canEditNoteAccess(
      for noteID: UUID,
      profileID: UUID,
      baselineCapabilities: [UUID: AgentProfileCapabilities],
      workspace: Workspace
    ) -> Bool {
      guard let baseline = baselineCapabilities[profileID] else { return false }
      return canEditNoteAccess(
        for: noteID,
        profile: baseline,
        workspace: workspace
      )
    }

    static func noteAccessReplacementIfEditable(
      noteID: UUID,
      level: AgentNoteAccessLevel,
      baseline: AgentProfileCapabilities,
      workspace: Workspace
    ) -> AgentProfileCapabilities? {
      guard canEditNoteAccess(
        for: noteID,
        profile: baseline,
        workspace: workspace
      ) else { return nil }
      return noteAccessReplacement(
        noteID: noteID,
        level: level,
        baseline: baseline
      )
    }

    static func folderAccess(
      for folderID: UUID,
      profile: AgentProfileCapabilities,
      workspace: Workspace
    ) -> AgentFolderAccessLevel {
      guard workspace.folders.contains(where: { $0.id == folderID }) else {
        return .off
      }
      if profile.grants.contains(where: {
        if case let .folderIncludingFutureNotes(grantedFolderID) = $0.scope {
          return grantedFolderID == folderID && $0.authority.allows(.read)
        }
        return false
      }) {
        return .includingFutureNotes
      }
      return .off
    }

    static func noteAccessAccessibilityLabel(
      _ level: AgentNoteAccessLevel
    ) -> String {
      let title = level == .off ? "None" : level.title
      return "Agent access: \(title)"
    }

    private static let emptySummary = ProfileSummary(
      summary: noToolsOrNotesGranted,
      scopeSummary: noToolsOrNotesGranted,
      toolsSummary: "No tools",
      accessibilityLabel: "Agent capabilities: \(noToolsOrNotesGranted)",
      futureFolderSummaries: []
    )
  }

  struct AgentCapabilityEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let profile: AgentIntegrationProfile
    let capabilities: AgentProfileCapabilities
    @State private var allowedCapabilities: Set<AgentCapability>
    @State private var expectedGrantRevision: UInt64
    @State private var directAccess: [UUID: AgentNoteAccessLevel] = [:]
    @State private var folderAccess: [UUID: AgentFolderAccessLevel] = [:]
    @State private var materializedDirectAccess: [UUID: AgentNoteAccessLevel] = [:]
    @State private var selectedLegacyNoteIDs: Set<UUID> = []
    @State private var pendingFutureFolderID: UUID?
    @State private var errorMessage: String?

    init(profile: AgentIntegrationProfile, capabilities: AgentProfileCapabilities) {
      self.profile = profile
      self.capabilities = capabilities
      _allowedCapabilities = State(initialValue: capabilities.allowedCapabilities)
      _expectedGrantRevision = State(initialValue: capabilities.grantRevision)
    }

    var body: some View {
      Form {
        Section("Tools") {
          capabilityToggle(.listNotes, title: "List and discover notes")
          capabilityToggle(.readNotes, title: "Read notes and tasks")
          capabilityToggle(.writeNotes, title: "Edit notes and tasks")
          capabilityToggle(.undoChanges, title: "Undo changes")
        }

        Section("Direct notes") {
          if appState.workspace.notes.isEmpty {
            Text("No notes")
              .foregroundStyle(.secondary)
          } else {
            ForEach(appState.workspace.notes) { note in
              Picker(note.displayTitle, selection: directBinding(for: note.id)) {
                ForEach(AgentNoteAccessLevel.allCases, id: \.self) { level in
                  Text(level.title).tag(level)
                }
              }
              .accessibilityValue(
                AgentCapabilityPresentation.noteAccessAccessibilityLabel(
                  directAccess[note.id] ?? .off
                )
              )
            }
          }
        }

        Section("Folders") {
          if appState.workspace.folders.isEmpty {
            Text("No folders")
              .foregroundStyle(.secondary)
          } else {
            ForEach(appState.workspace.folders, id: \.id) { folder in
              Picker(folder.name, selection: folderBinding(for: folder.id)) {
                ForEach(AgentFolderAccessLevel.allCases, id: \.self) { level in
                  Text(level.title).tag(level)
                }
              }
              if folderAccess[folder.id] == .includingFutureNotes {
                Text(
                  AgentCapabilityPresentation.futureFolderSummary(
                    folderName: folder.name
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          }
        }

        if !appState.agentCapabilityState.unassignedLegacyNoteIDs.isEmpty {
          Section(AgentCapabilityPresentation.unassignedLegacySharesLabel) {
            ForEach(
              appState.agentCapabilityState.unassignedLegacyNoteIDs
                .sorted { $0.uuidString < $1.uuidString },
              id: \.self
            ) { noteID in
              if let note = appState.workspace.notes.first(where: { $0.id == noteID }) {
                Toggle(note.displayTitle, isOn: legacyBinding(for: noteID))
              }
            }
            Button("Assign Selected Shares") {
              assignSelectedLegacyShares()
            }
            .disabled(selectedLegacyNoteIDs.isEmpty)
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
      .frame(minWidth: 520, minHeight: 520)
      .onAppear(perform: loadDraft)
      .confirmationDialog(
        AgentCapabilityPresentation.futureFolderConfirmationMessage,
        isPresented: Binding(
          get: { pendingFutureFolderID != nil },
          set: { if !$0 { pendingFutureFolderID = nil } }
        )
      ) {
        Button("Allow Future Notes") {
          if let folderID = pendingFutureFolderID {
            let restored = AgentCapabilityPresentation.restoreMaterializedCurrentFolderNotes(
              folderID: folderID,
              workspace: appState.workspace,
              directAccess: directAccess,
              materializedAccess: materializedDirectAccess
            )
            directAccess = restored.directAccess
            materializedDirectAccess = restored.materializedAccess
            folderAccess[folderID] = .includingFutureNotes
          }
          pendingFutureFolderID = nil
        }
        Button("Cancel", role: .cancel) {
          pendingFutureFolderID = nil
        }
      }
    }

    private func capabilityToggle(
      _ capability: AgentCapability,
      title: String
    ) -> some View {
      Toggle(
        title,
        isOn: Binding(
          get: { allowedCapabilities.contains(capability) },
          set: { enabled in
            if enabled {
              allowedCapabilities.insert(capability)
            } else {
              allowedCapabilities.remove(capability)
            }
          }
        )
      )
    }

    private func directBinding(for noteID: UUID) -> Binding<AgentNoteAccessLevel> {
      Binding(
        get: { directAccess[noteID] ?? .off },
        set: {
          directAccess[noteID] = $0
          materializedDirectAccess.removeValue(forKey: noteID)
        }
      )
    }

    private func folderBinding(for folderID: UUID) -> Binding<AgentFolderAccessLevel> {
      Binding(
        get: { folderAccess[folderID] ?? .off },
        set: { level in
          switch level {
          case .includingFutureNotes:
            pendingFutureFolderID = folderID
          case .currentNotes:
            let materialized = AgentCapabilityPresentation.materializeCurrentFolderNotes(
              folderID: folderID,
              workspace: appState.workspace,
              directAccess: directAccess,
              materializedAccess: materializedDirectAccess
            )
            directAccess = materialized.directAccess
            materializedDirectAccess = materialized.materializedAccess
            folderAccess[folderID] = .currentNotes
          case .off:
            let restored = AgentCapabilityPresentation.restoreMaterializedCurrentFolderNotes(
              folderID: folderID,
              workspace: appState.workspace,
              directAccess: directAccess,
              materializedAccess: materializedDirectAccess
            )
            directAccess = restored.directAccess
            materializedDirectAccess = restored.materializedAccess
            folderAccess[folderID] = level
          }
        }
      )
    }

    private func legacyBinding(for noteID: UUID) -> Binding<Bool> {
      Binding(
        get: { selectedLegacyNoteIDs.contains(noteID) },
        set: { selected in
          if selected {
            selectedLegacyNoteIDs.insert(noteID)
          } else {
            selectedLegacyNoteIDs.remove(noteID)
          }
        }
      )
    }

    private func loadDraft() {
      guard directAccess.isEmpty, folderAccess.isEmpty else { return }
      for note in appState.workspace.notes {
        let level = AgentCapabilityPresentation.explicitNoteAccess(
          for: note.id,
          profile: capabilities
        )
        if level != .off { directAccess[note.id] = level }
      }
      for folder in appState.workspace.folders {
        let level = AgentCapabilityPresentation.folderAccess(
          for: folder.id,
          profile: capabilities,
          workspace: appState.workspace
        )
        if level != .off { folderAccess[folder.id] = level }
      }
    }

    private func replacement() -> AgentProfileCapabilities {
      AgentCapabilityPresentation.capabilityReplacement(
        baseline: capabilities,
        allowedCapabilities: allowedCapabilities,
        expectedGrantRevision: expectedGrantRevision,
        directAccess: directAccess,
        folderAccess: folderAccess
      )
    }

    private func save() {
      errorMessage = nil
      let replacement = replacement()
      Task { @MainActor in
        switch await appState.updateAgentCapabilities(
          replacement,
          expectedGrantRevision: expectedGrantRevision
        ) {
        case .succeeded:
          dismiss()
        case .revisionConflict:
          errorMessage = AgentCapabilityPresentation.conflictMessage
        case .failed:
          errorMessage = "Could not update Agent capabilities. Try again."
        }
      }
    }

    private func assignSelectedLegacyShares() {
      let selected = selectedLegacyNoteIDs
      Task { @MainActor in
        switch await appState.assignUnassignedLegacyNotes(
          selected,
          to: capabilities.profileID,
          expectedGrantRevision: expectedGrantRevision
        ) {
        case .succeeded:
          expectedGrantRevision += 1
          for noteID in selected {
            directAccess[noteID] = .write
          }
          selectedLegacyNoteIDs.removeAll()
        case .revisionConflict:
          errorMessage = AgentCapabilityPresentation.conflictMessage
        case .failed:
          errorMessage = "Could not assign legacy Agent shares. Try again."
        }
      }
    }
  }

#endif
