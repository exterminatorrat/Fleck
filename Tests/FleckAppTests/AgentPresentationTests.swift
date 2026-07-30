import FleckCore
import Foundation
import Testing

@testable import FleckApp

@Suite("AgentPresentation")
struct AgentPresentationTests {
  @Test func agentConnectorExplainsScopeAndGatesIntegrationSetup() {
    #expect(AgentConnectorPresentation.sectionTitle == "Agent Connector")
    #expect(
      AgentConnectorPresentation.installTitle == "Install Agent Connector"
    )
    #expect(AgentConnectorPresentation.explanation.contains("local helper"))
    #expect(AgentConnectorPresentation.explanation.contains("explicitly shared"))
    #expect(AgentConnectorPresentation.explanation.contains("no network listener"))
    #expect(
      !AgentConnectorPresentation.canAddIntegration(
        workspaceAvailable: true,
        connectorInstalled: false
      )
    )
    #expect(
      !AgentConnectorPresentation.canAddIntegration(
        workspaceAvailable: false,
        connectorInstalled: true
      )
    )
    #expect(
      AgentConnectorPresentation.canAddIntegration(
        workspaceAvailable: true,
        connectorInstalled: true
      )
    )
  }

  @Test func agentConnectorInstallStatusIsCachedAndRefreshedAsynchronously() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceRoot = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    let appState = try String(
      contentsOf: sourceRoot.appendingPathComponent("AppState.swift"),
      encoding: .utf8
    )
    let settings = try String(
      contentsOf: sourceRoot.appendingPathComponent("AgentSettingsView.swift"),
      encoding: .utf8
    )

    #expect(
      appState.contains(
        "@Published private(set) var isAgentConnectorInstalled = false"
      )
    )
    #expect(!appState.contains("var isAgentConnectorInstalled: Bool {"))
    #expect(appState.contains("Task.detached(priority: .utility)"))
    #expect(settings.contains("await appState.refreshAgentConnectorStatus()"))
    #expect(
      appState.components(
        separatedBy: "await refreshAgentConnectorStatus()"
      ).count >= 4
    )
  }

  @Test func agentWorkspaceErrorsAreShortAndActionable() {
    let error = AgentWorkspaceError(code: .internalSaveFailure)

    #expect(
      error.localizedDescription
        == "Fleck could not update its local agent data."
    )
    for forbidden in [
      "FleckApp.",
      "FleckCore.",
      "MenuBarNotes",
      "error 1",
      "/Users/",
    ] {
      #expect(!error.localizedDescription.contains(forbidden))
    }
  }

  @Test func sharingStartsPrivateAndFirstEnableRequiresConfirmation() {
    let note = Note()

    #expect(!note.agentAccess)
    #expect(
      AgentSharingPresentation(
        note: note,
        hasConfirmedFirstShare: false
      ).requiresEnableConfirmation
    )
    #expect(
      !AgentSharingPresentation(
        note: note,
        hasConfirmedFirstShare: true
      ).requiresEnableConfirmation
    )
    #expect(AgentSharingPresentation.sharedBadgeAccessibilityLabel == "Shared with agents")
  }

  @Test func unsharingRemovesNoteFromServiceVisibilityImmediately() {
    let shared = Note(title: "Shared", agentAccess: true)
    let privateNote = Note(title: "Private")

    #expect(
      AgentPresentation.visibleNoteIDs(in: Workspace(notes: [shared, privateNote]))
        == [shared.id]
    )
  }

  @Test func activityRowsExposeDetailsAndLocalUndoSurvivesUnshareAndRevoke() throws {
    let profileID = UUID()
    let note = Note(title: "Launch", body: "after", agentAccess: false, revision: 7)
    let record = makeRecord(
      note: note,
      actor: .integration(profileID: profileID, displayName: "Codex")
    )

    let row = AgentActivityRowPresentation(
      record: record,
      activeNote: note,
      activeProfileIDs: []
    )

    #expect(row.integrationName == "Codex")
    #expect(row.noteTitle == "Launch")
    #expect(row.operationDescription == "Appended text")
    #expect(row.timestamp == record.createdAt)
    #expect(row.beforeText == "")
    #expect(row.afterText == "after")
    #expect(row.canUndo)
  }

  @Test func bridgeActivityCannotExposeAnUnsharedNote() {
    let note = Note(title: "Private")
    let record = makeRecord(note: note)

    #expect(
      AgentPresentation.bridgeVisibleActivity(
        [record],
        workspace: Workspace(notes: [note])
      ).isEmpty
    )
  }

  @Test func feedbackCoalescesBannerCountWithoutChangingActivityCount() {
    let firstID = UUID()
    let latestID = UUID()
    var banner = AgentBannerPresentation(
      feedback: feedback(changeID: firstID, noteTitle: "Launch", actorName: "Codex"))
    let records = [UUID(), UUID()]

    banner.coalesce(
      feedback: feedback(changeID: latestID, noteTitle: "Release", actorName: "Claude"))

    #expect(banner.count == 2)
    #expect(records.count == 2)
    #expect(banner.feedback.changeID == latestID)
    #expect(banner.feedback.noteTitle == "Release")
    #expect(banner.message == "Claude updated Release (2)")
    #expect(!banner.message.contains("body"))
  }

  @Test func reduceMotionUsesCrossfadeInsteadOfSpatialTransition() {
    #expect(AgentBannerPresentation.transition(reduceMotion: true) == .crossfade)
    #expect(AgentBannerPresentation.transition(reduceMotion: false) == .spatial)
  }

  @Test func agentChangeUndoRemainsKeyboardFocusable() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let source = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp/AgentChangeBanner.swift")
    let contents = try String(contentsOf: source, encoding: .utf8)

    #expect(!contents.contains(".focusable(false)"))
  }

  @Test func revokedProfilesNeverAppearActive() {
    let active = profile(name: "Codex", revokedAt: nil)
    let revoked = profile(name: "Claude", revokedAt: Date())

    #expect(AgentProfilesPresentation.active([revoked, active]) == [active])
  }

  @Test func clearingActivityRequiresConfirmation() {
    #expect(AgentActivityClearPresentation.requiresConfirmation)
  }

  private func makeRecord(
    note: Note,
    actor: AgentActivityActor = .integration(profileID: UUID(), displayName: "Codex")
  ) -> AgentActivityRecord {
    let transaction = PreparedAgentTransaction(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actor: actor,
      operationID: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      operation: .appendText,
      patch: AgentTextPatch(
        beforeText: "",
        afterText: "after",
        range: NSRange(location: 0, length: 0),
        prefixContext: "",
        suffixContext: ""
      ),
      previousRevision: 6,
      resultingRevision: 7,
      resultingBodySHA256: ""
    )
    return AgentActivityRecord(
      transaction: transaction,
      receipt: AgentWriteReceipt(
        changeID: transaction.changeID,
        noteID: note.id,
        previousRevision: 6,
        resultingRevision: 7
      )
    )
  }

  private func feedback(
    changeID: UUID,
    noteTitle: String,
    actorName: String
  ) -> AgentChangeFeedback {
    AgentChangeFeedback(
      changeID: changeID,
      noteID: UUID(),
      noteTitle: noteTitle,
      actor: .integration(profileID: UUID(), displayName: actorName),
      resultingRevision: 1,
      createdAt: Date()
    )
  }

  private func profile(name: String, revokedAt: Date?) -> AgentIntegrationProfile {
    AgentIntegrationProfile(
      id: UUID(),
      displayName: name,
      createdAt: Date(),
      lastConnectedAt: nil,
      revokedAt: revokedAt
    )
  }
}
