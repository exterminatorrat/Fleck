import AppKit
import FleckCore
import Foundation
import SwiftUI
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

  @Test func sharingBadgeUsesEffectiveCapabilitiesOnly() {
    let note = Note(agentAccess: true)

    #expect(
      !AgentSharingPresentation.isShared(
        noteID: note.id,
        activeProfiles: [],
        workspace: Workspace(notes: [note])
      )
    )
    #expect(AgentSharingPresentation.sharedBadgeAccessibilityLabel == "Shared with agents")
  }

  @Test func unsharingRemovesNoteFromServiceVisibilityImmediately() {
    let shared = Note(title: "Shared", agentAccess: true)
    let privateNote = Note(title: "Private")
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 1,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: shared.id),
          authority: .read
        )
      ]
    )
    let workspace = Workspace(notes: [shared, privateNote])

    #expect(
      AgentPresentation.visibleNoteIDs(in: workspace, activeProfiles: [profile])
        == [shared.id]
    )
    #expect(AgentPresentation.visibleNoteIDs(in: workspace) == [])
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

  @Test func agentBannerDismissalKeepsIndependentAndNewOccurrencesVisible() {
    let firstChangeID = UUID()
    let first = NotesPanelBannerOccurrence.agentChange(
      changeID: firstChangeID,
      count: 1
    )
    let coalesced = NotesPanelBannerOccurrence.agentChange(
      changeID: firstChangeID,
      count: 2
    )
    let differentChange = NotesPanelBannerOccurrence.agentChange(
      changeID: UUID(),
      count: 1
    )
    let independentFailure = NotesPanelBannerOccurrence.captureFailure(
      message: "Microphone permission is required",
      actionPanes: [.microphone]
    )
    var state = NotesPanelBannerDismissalState()
    state.reconcile(activeOccurrences: [first, independentFailure])
    state.dismiss(first)

    state.reconcile(
      activeOccurrences: [coalesced, differentChange, independentFailure]
    )

    #expect(state.isPresented(coalesced))
    #expect(state.isPresented(differentChange))
    #expect(state.isPresented(independentFailure))
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

  @Test @MainActor func revokedProfileWithRetainedReadGrantCannotProduceSharedBadge() {
    let revoked = profile(name: "Claude", revokedAt: Date())
    let note = Note(title: "Private")
    let capabilities = AgentProfileCapabilities(
      profileID: revoked.id,
      grantRevision: 3,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .read
        )
      ]
    )
    let state = AgentCapabilityState(
      profiles: [revoked.id: capabilities],
      unassignedLegacyNoteIDs: []
    )
    let activeCapabilities = AppState.activeCapabilityProfiles(
      profiles: [revoked],
      state: state
    )

    #expect(activeCapabilities.isEmpty)
    #expect(
      !AgentCapabilityPresentation.isShared(
        noteID: note.id,
        activeProfiles: activeCapabilities,
        workspace: Workspace(notes: [note])
      )
    )
  }

  @Test @MainActor
  func manageAgentAccessPermissionChoicesStayInline() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentAccessPresentation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: "Launch")
    let store = LocalStore(rootURL: root)
    try await store.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init(),
      trashedNotes: []
    )
    let state = AppState(
      store: store,
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()

    let profile = profile(name: "Codex", revokedAt: nil)
    let capabilities = AgentProfileCapabilities(
      profileID: profile.id,
      grantRevision: 0,
      allowedCapabilities: [],
      grants: []
    )
    let (window, host) = await hostedWindow(
      rootView: AgentCapabilityEditorView(
        profile: profile,
        capabilities: capabilities
      )
      .environmentObject(state),
      size: NSSize(width: 640, height: 560)
    )
    defer { window.orderOut(nil) }

    let permissionControl = try #require(
      hostedDescendant(in: host, as: NSSegmentedControl.self)
    )
    #expect(permissionControl.segmentCount == 3)
    #expect(permissionControl.label(forSegment: 0) == "Off")
    #expect(permissionControl.label(forSegment: 1) == "Read")
    #expect(permissionControl.label(forSegment: 2) == "Read & Write")
  }

  @Test @MainActor
  func noteAgentAccessPermissionChoicesStayInline() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteAgentAccessPresentation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: "Launch")
    let profile = profile(name: "Codex", revokedAt: nil)
    let state = try await makeAgentAccessState(
      root: root,
      note: note,
      profile: profile
    )
    let (window, host) = await hostedWindow(
      rootView: AgentNoteAccessEditorView(note: note)
        .environmentObject(state),
      size: NSSize(width: 520, height: 600)
    )
    defer { window.orderOut(nil) }

    let permissionControl = try #require(
      hostedDescendant(in: host, as: NSSegmentedControl.self)
    )
    #expect(permissionControl.segmentCount == 3)
    #expect(permissionControl.label(forSegment: 0) == "Off")
    #expect(permissionControl.label(forSegment: 1) == "Read")
    #expect(permissionControl.label(forSegment: 2) == "Read & Write")
  }

  @Test func clearingActivityRequiresConfirmation() {
    #expect(AgentActivityClearPresentation.requiresConfirmation)
  }

  @Test func agentActivityDismissalControlDeclaresRequiredSemantics() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceRoot = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    let source = try String(
      contentsOf: sourceRoot.appendingPathComponent("AgentActivityView.swift"),
      encoding: .utf8
    )

    #expect(source.contains("@Environment(\\.dismiss) private var dismiss"))
    #expect(source.contains("Button(\"Done\") {"))
    #expect(source.contains("dismiss()"))
    #expect(source.contains(".keyboardShortcut(.cancelAction)"))
    #expect(source.contains(".accessibilityLabel(\"Close Agent Activity\")"))
  }

  @Test @MainActor
  func agentActivityEscapeDismissesPresentedSheet() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentActivityEscape-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(store: LocalStore(rootURL: root))
    await state.waitUntilInitialLoad()
    let initialActivityCount = state.agentActivity.count
    let initialWorkspace = state.workspace
    let (window, host) = await hostedWindow(
      rootView: AgentActivitySheetHarness()
        .environmentObject(state),
      size: NSSize(width: 640, height: 480)
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }

    let sheet = try await presentedAgentActivitySheet(from: window, parent: host)
    sendEscape(to: sheet)
    await settleHostedSheet(sheet, parent: host)

    #expect(window.sheets.isEmpty)
    #expect(window.isVisible)
    #expect(state.agentActivity.count == initialActivityCount)
    #expect(state.workspace == initialWorkspace)
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

  @MainActor
  private func makeAgentAccessState(
    root: URL,
    note: Note,
    profile: AgentIntegrationProfile
  ) async throws -> AppState {
    let store = LocalStore(rootURL: root)
    try await store.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: .init(),
      trashedNotes: []
    )
    let profilesURL = root
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("profiles.json")
    try FileManager.default.createDirectory(
      at: profilesURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode([profile]).write(to: profilesURL)
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.previous.json")
    )
    let state = AppState(
      store: store,
      saveOperation: { _, _, _, _ in .committed },
      agentProfileStore: AgentProfileStore(profilesURL: profilesURL),
      agentCapabilityStore: capabilityStore
    )
    await state.waitUntilInitialLoad()
    return state
  }

  @MainActor
  private func hostedWindow<Content: View>(
    rootView: Content,
    size: NSSize
  ) async -> (window: NSWindow, host: NSHostingView<Content>) {
    let host = NSHostingView(rootView: rootView)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    return (window, host)
  }

  @MainActor
  private func hostedDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
    if let match = view as? T { return match }
    for subview in view.subviews {
      if let match = hostedDescendant(in: subview, as: type) { return match }
    }
    return nil
  }
}

@MainActor
private struct AgentActivitySheetHarness: View {
  @State private var isShowingAgentActivity = true

  var body: some View {
    Color.clear
      .frame(width: 320, height: 240)
      .sheet(isPresented: $isShowingAgentActivity) {
        AgentActivityView { _ in }
      }
  }
}

@MainActor
private func presentedAgentActivitySheet(
  from window: NSWindow,
  parent: NSView
) async throws -> NSWindow {
  for _ in 0..<40 {
    parent.layoutSubtreeIfNeeded()
    if let sheet = window.sheets.first {
      sheet.contentView?.layoutSubtreeIfNeeded()
      return sheet
    }
    await Task.yield()
  }
  return try #require(window.sheets.first)
}

@MainActor
private func sendEscape(to window: NSWindow) {
  guard let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "\u{1b}",
    charactersIgnoringModifiers: "\u{1b}",
    isARepeat: false,
    keyCode: 53
  ) else { return }
  window.sendEvent(event)
}

@MainActor
private func settleHostedSheet(_ sheet: NSWindow, parent: NSView) async {
  for _ in 0..<40 {
    parent.layoutSubtreeIfNeeded()
    sheet.contentView?.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
