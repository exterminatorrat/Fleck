#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore

  enum AgentPresentation {
    static func visibleNoteIDs(in workspace: Workspace) -> Set<UUID> {
      Set(workspace.notes.filter(\.agentAccess).map(\.id))
    }

    static func bridgeVisibleActivity(
      _ records: [AgentActivityRecord],
      workspace: Workspace
    ) -> [AgentActivityRecord] {
      let visible = visibleNoteIDs(in: workspace)
      return records.filter { visible.contains($0.noteID) }
    }
  }

  struct AgentSharingPresentation {
    static let sharedBadgeAccessibilityLabel = "Shared with agents"
    let requiresEnableConfirmation: Bool

    init(note: Note, hasConfirmedFirstShare: Bool) {
      requiresEnableConfirmation = !note.agentAccess && !hasConfirmedFirstShare
    }
  }

  enum AgentActivityClearPresentation {
    static let requiresConfirmation = true
  }

  struct AgentActivityRowPresentation: Identifiable {
    let record: AgentActivityRecord
    let integrationName: String
    let noteTitle: String
    let operationDescription: String
    let timestamp: Date
    let beforeText: String
    let afterText: String
    let canUndo: Bool

    var id: UUID { record.changeID }

    init(
      record: AgentActivityRecord,
      activeNote: Note?,
      activeProfileIDs: Set<UUID>
    ) {
      self.record = record
      integrationName = Self.actorName(record.actor)
      noteTitle = record.noteTitle
      operationDescription = Self.operationName(record.operation)
      timestamp = record.createdAt
      beforeText = record.patch.beforeText
      afterText = record.patch.afterText
      canUndo =
        activeNote.map { (try? AgentUndoEngine.draft(inverting: record.patch, in: $0.body)) != nil }
        ?? false
    }

    var copiedDetails: String {
      """
      \(integrationName) \(operationDescription.lowercased()) in \(noteTitle)
      \(timestamp.formatted(date: .abbreviated, time: .standard))
      Before: \(beforeText)
      After: \(afterText)
      """
    }

    private static func actorName(_ actor: AgentActivityActor) -> String {
      switch actor {
      case .integration(_, let displayName): displayName
      case .localUser: "Motes"
      }
    }

    private static func operationName(_ operation: AgentActivityOperation) -> String {
      switch operation {
      case .appendText: "Appended text"
      case .insertText: "Inserted text"
      case .replaceLines: "Replaced lines"
      case .addTask: "Added task"
      case .renameTask: "Renamed task"
      case .setTaskState: "Updated task"
      case .removeTask: "Removed task"
      case .undoChange: "Undid change"
      }
    }
  }

  struct AgentActivityView: View {
    @EnvironmentObject private var appState: AppState
    let onOpenNote: (UUID) -> Void
    @State private var showsClearConfirmation = false

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Agent Activity").font(.title2.weight(.semibold))
          Spacer()
          Button("Clear Activity", role: .destructive) {
            showsClearConfirmation = true
          }
          .disabled(appState.agentActivity.isEmpty)
        }

        if appState.agentActivity.isEmpty {
          ContentUnavailableView(
            "No Agent Activity",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("Changes made by authorized integrations appear here.")
          )
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(rows) { row in
                activityRow(row)
              }
            }
          }
        }
      }
      .padding(18)
      .frame(minWidth: 520, minHeight: 380)
      .task { appState.refreshAgentActivity() }
      .confirmationDialog(
        "Clear Agent Activity?",
        isPresented: $showsClearConfirmation
      ) {
        Button("Clear Activity", role: .destructive) {
          appState.clearAgentActivity()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Visible patches are removed. Retry-protection tombstones remain until expiry.")
      }
    }

    private var rows: [AgentActivityRowPresentation] {
      let profiles = Set(appState.agentProfiles.map(\.id))
      return appState.agentActivity.map { record in
        AgentActivityRowPresentation(
          record: record,
          activeNote: appState.workspace.notes.first { $0.id == record.noteID },
          activeProfileIDs: profiles
        )
      }
    }

    private func activityRow(_ row: AgentActivityRowPresentation) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(row.integrationName).font(.headline)
          Text("· \(row.noteTitle)").foregroundStyle(.secondary)
          Spacer()
          Text(row.timestamp, style: .relative).font(.caption).foregroundStyle(.secondary)
        }
        Text(row.operationDescription).font(.callout)
        patch("Before", row.beforeText)
        patch("After", row.afterText)
        HStack {
          Button("Open Note") {
            onOpenNote(row.record.noteID)
          }
          Button("Copy Details") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.copiedDetails, forType: .string)
          }
          Spacer()
          Button("Undo") {
            Task { await appState.undoAgentChange(row.record) }
          }
          .disabled(!row.canUndo)
        }
      }
      .padding(12)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func patch(_ label: String, _ text: String) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        Text(text.isEmpty ? "—" : text)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
    }
  }
#endif
