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

  @Test func agentSettingsUsesDirectIntegrationsAndHonestPrimaryStatusAction() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceRoot = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    let settings = try String(
      contentsOf: sourceRoot.appendingPathComponent("AgentSettingsView.swift"),
      encoding: .utf8
    )

    #expect(
      AgentConnectorPresentation.primaryActionTitle(installed: false)
        == "Install Agent Connector"
    )
    #expect(
      AgentConnectorPresentation.primaryActionTitle(installed: true)
        == "Refresh Status"
    )
    #expect(AgentIntegrationKind.allCases.map(\.displayName) == [
      "Codex", "Claude Code", "Kimi", "Generic CLI",
    ])
    #expect(AgentIntegrationKind.allCases.map(\.description) == [
      "Connect Codex to explicitly shared notes.",
      "Connect Claude Code to explicitly shared notes.",
      "Connect Kimi to explicitly shared notes.",
      "Connect another local CLI to explicitly shared notes.",
    ])
    #expect(settings.contains("ForEach(AgentIntegrationKind.allCases)"))
    #expect(settings.contains("appState.addAgentProfile(named: integration.displayName)"))
    #expect(settings.contains("Connected Profiles"))
    #expect(settings.contains("Set up a local integration"))
    #expect(settings.contains("DisclosureGroup(\"Activity\")"))
    #expect(settings.contains("Show agent update banners"))
    #expect(settings.contains("appState.preferences.showAgentUpdateBanners"))
    #expect(settings.contains("banners for future agent changes"))
    #expect(settings.contains("does not replay earlier changes"))
    #expect(settings.contains("Agent Activity remains available"))
    #expect(settings.contains("DisclosureGroup(\"Access\")"))
    #expect(!settings.contains("HStack {\n            addButton(\"Add Codex\""))
  }

  @Test func agentSettingsUsesConsumerPreferenceRowsForVisibleConnectorContent() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceRoot = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    let settings = try String(
      contentsOf: sourceRoot.appendingPathComponent("AgentSettingsView.swift"),
      encoding: .utf8
    )

    #expect(settings.contains("SettingsPreferenceRow("))
    #expect(settings.contains(
      "SettingsPreferenceRow(\n          AgentConnectorPresentation.sectionTitle"
    ))
    #expect(settings.contains("SettingsPreferenceRow(integration.displayName"))
    #expect(settings.contains("SettingsPreferenceRow(profile.displayName"))
    #expect(settings.contains("SettingsPreferenceRow(\n        \"Set up a local integration\""))
  }

  @Test func agentConnectorActionDecisionMatchesInstalledStateAndIsDispatched() throws {
    #expect(AgentConnectorPresentation.action(installed: false) == .install)
    #expect(AgentConnectorPresentation.action(installed: true) == .refresh)

    let testFile = URL(fileURLWithPath: #filePath)
    let sourceRoot = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    let settings = try String(
      contentsOf: sourceRoot.appendingPathComponent("AgentSettingsView.swift"),
      encoding: .utf8
    )

    #expect(settings.contains(
      "switch AgentConnectorPresentation.action(\n                  installed:"
    ))
    #expect(settings.contains("case .install:"))
    #expect(settings.contains("await appState.installAgentBridge()"))
    #expect(settings.contains("case .refresh:"))
    #expect(settings.contains("await appState.refreshAgentConnectorStatus()"))
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

  @Test @MainActor
  func agentUpdateBannerPreferencePersistsWithoutReplayingSuppressedActivity() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentBannerPreference-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: "Shared", body: "after", revision: 7)
    var preferences = AppPreferences()
    preferences.showAgentUpdateBanners = false
    let store = LocalStore(rootURL: root)
    try await store.save(
      workspace: Workspace(notes: [note], selectedNoteID: note.id),
      preferences: preferences,
      trashedNotes: []
    )
    let activityStore = AgentActivityStore(rootURL: root)
    let transaction = PreparedAgentTransaction(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actor: .integration(profileID: UUID(), displayName: "Codex"),
      operationID: UUID(),
      createdAt: Date(),
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
    let receipt = AgentWriteReceipt(
      changeID: transaction.changeID,
      noteID: note.id,
      previousRevision: 6,
      resultingRevision: 7
    )
    try activityStore.prepare(transaction)
    try activityStore.commit(changeID: transaction.changeID, receipt: receipt)
    let state = AppState(
      store: store,
      agentActivityStore: activityStore
    )
    await state.waitUntilInitialLoad()
    #expect(!state.preferences.showAgentUpdateBanners)
    #expect(state.agentActivity.count == 1)

    let first = feedback(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actorName: "Codex"
    )
    let second = feedback(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actorName: "Claude"
    )
    state.publishAgentFeedback(first)
    state.publishAgentFeedback(second)
    #expect(state.agentBannerPresentation == nil)
    #expect(state.latestAgentFeedback == second)
    #expect(state.agentActivity.count == 1)

    state.saveError = "Keep save error"
    state.agentCleanupError = "Keep agent error"
    state.updatePreferences { $0.showAgentUpdateBanners = true }
    #expect(state.agentBannerPresentation == nil)
    let future = feedback(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actorName: "Kimi"
    )
    state.publishAgentFeedback(future)
    #expect(state.agentBannerPresentation?.feedback == future)
    #expect(state.agentBannerPresentation?.count == 1)

    state.updatePreferences { $0.showAgentUpdateBanners = false }
    #expect(state.agentBannerPresentation == nil)
    #expect(state.latestAgentFeedback == future)
    #expect(state.agentActivity.count == 1)
    #expect(state.saveError == "Keep save error")
    #expect(state.agentCleanupError == "Keep agent error")
    try await state.saveNow().value

    let relaunched = AppState(store: LocalStore(rootURL: root))
    await relaunched.waitUntilInitialLoad()
    #expect(!relaunched.preferences.showAgentUpdateBanners)
    #expect(relaunched.agentActivity.count == 1)
    let afterRelaunch = feedback(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actorName: "Codex"
    )
    relaunched.publishAgentFeedback(afterRelaunch)
    #expect(relaunched.agentBannerPresentation == nil)
    #expect(relaunched.latestAgentFeedback == afterRelaunch)
    #expect(relaunched.agentActivity.count == 1)
  }

  @Test @MainActor
  func disablingAgentUpdateBannersClearsMenuAndPinnedHostsTogether() async throws {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentBannerHosts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = Note(title: "Shared")
    let state = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [note], selectedNoteID: note.id)
    let menuRuntime = DictationRuntime(
      appState: state,
      applicationSupportURL: root.appendingPathComponent("Menu", isDirectory: true)
    )
    let pinnedRuntime = DictationRuntime(
      appState: state,
      applicationSupportURL: root.appendingPathComponent("Pinned", isDirectory: true)
    )
    let (menuWindow, menuHost) = await hostedWindow(
      rootView: NotesPanel(
        dictationRuntime: menuRuntime,
        isPinned: false,
        sizing: .container
      )
      .environmentObject(state),
      size: NSSize(width: 800, height: 430)
    )
    let (pinnedWindow, pinnedHost) = await hostedWindow(
      rootView: NotesPanel(
        dictationRuntime: pinnedRuntime,
        isPinned: true,
        sizing: .container
      )
      .environmentObject(state),
      size: NSSize(width: 800, height: 430)
    )
    defer {
      menuWindow.contentView = nil
      pinnedWindow.contentView = nil
      menuWindow.orderOut(nil)
      pinnedWindow.orderOut(nil)
    }
    let update = feedback(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actorName: "Codex"
    )
    state.publishAgentFeedback(update)
    await settleAgentActivityHost(menuHost)
    await settleAgentActivityHost(pinnedHost)
    let message = "Codex updated Shared"
    let dismissLabel = "Dismiss Agent Activity update"
    #expect(state.agentBannerPresentation?.message == message)
    #expect(agentActivityAccessibilityElement(menuHost, label: dismissLabel) != nil)
    #expect(agentActivityAccessibilityElement(pinnedHost, label: dismissLabel) != nil)

    state.updatePreferences { $0.showAgentUpdateBanners = false }
    try await Task.sleep(for: .milliseconds(200))
    await settleAgentActivityHost(menuHost)
    await settleAgentActivityHost(pinnedHost)
    #expect(agentActivityAccessibilityElement(menuHost, label: dismissLabel) == nil)
    #expect(agentActivityAccessibilityElement(pinnedHost, label: dismissLabel) == nil)
    #expect(menuWindow.isVisible)
    #expect(pinnedWindow.isVisible)
    await menuRuntime.shutdown()
    await pinnedRuntime.shutdown()
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

  @Test @MainActor
  func agentActivityDoneClearsOwningStateWithoutClosingParentWindow() async throws {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentActivityDone-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(store: LocalStore(rootURL: root))
    await state.waitUntilInitialLoad()
    let presentation = AgentActivitySheetPresentation()
    let (window, host) = await hostedWindow(
      rootView: AgentActivitySheetHarness(presentation: presentation)
        .environmentObject(state),
      size: NSSize(width: 640, height: 480)
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }

    let sheet = try await presentedAgentActivitySheet(from: window, parent: host)
    let done = try #require(
      agentActivityAccessibilityElement(sheet.contentView, label: "Close Agent Activity")
    )
    _ = done.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleHostedSheet(sheet, parent: host)

    #expect(!presentation.isPresented)
    #expect(presentation.dismissalCount == 1)
    #expect(window.sheets.isEmpty)
    #expect(window.isVisible)
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
    let presentation = AgentActivitySheetPresentation()
    let (window, host) = await hostedWindow(
      rootView: AgentActivitySheetHarness(presentation: presentation)
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
    #expect(!presentation.isPresented)
    #expect(presentation.dismissalCount == 1)
    #expect(state.agentActivity.count == initialActivityCount)
    #expect(state.workspace == initialWorkspace)
  }

  @Test @MainActor
  func unpinnedNotesPanelKeepsAgentActivityInsideItsVisibleHost() async throws {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    for size in [NSSize(width: 380, height: 300), NSSize(width: 800, height: 430)] {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentActivityPanel-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let note = Note(title: "Underlying editor fixture")
      let state = AppState(
        store: LocalStore(rootURL: root),
        saveOperation: { _, _, _, _ in .committed }
      )
      await state.waitUntilInitialLoad()
      state.workspace = Workspace(notes: [note], selectedNoteID: note.id)
      let initialWorkspace = state.workspace
      let initialActivityCount = state.agentActivity.count
      let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
      let (window, host) = await hostedWindow(
        rootView: NotesPanel(
          dictationRuntime: runtime,
          isPinned: false,
          sizing: .container
        )
        .environmentObject(state),
        size: size
      )
      let initialFrame = window.frame

      let indicator = try #require(
        agentActivityAccessibilityElement(host, identifier: "agent-activity-indicator")
      )
      try clickAgentActivityElement(indicator, in: window)
      await settleAgentActivityHost(host)

      #expect(window.sheets.isEmpty)
      #expect(agentActivityAccessibilityElement(host, label: "Close Agent Activity") != nil)
      #expect(agentActivityAccessibilityElement(host, label: note.title) == nil)

      let done = try #require(
        agentActivityAccessibilityElement(host, label: "Close Agent Activity")
      )
      try clickAgentActivityElement(done, in: window)
      await settleAgentActivityHost(host)

      #expect(window.sheets.isEmpty)
      #expect(window.isVisible)
      #expect(window.frame == initialFrame)
      #expect(agentActivityAccessibilityElement(host, label: "Close Agent Activity") == nil)
      #expect(state.workspace == initialWorkspace)
      #expect(state.agentActivity.count == initialActivityCount)

      let reopenedIndicator = try #require(
        agentActivityAccessibilityElement(host, identifier: "agent-activity-indicator")
      )
      try clickAgentActivityElement(reopenedIndicator, in: window)
      await settleAgentActivityHost(host)
      #expect(agentActivityAccessibilityElement(host, label: "Close Agent Activity") != nil)

      sendEscape(to: window)
      await settleAgentActivityHost(host)
      #expect(agentActivityAccessibilityElement(host, label: "Close Agent Activity") == nil)
      #expect(window.isVisible)
      #expect(window.frame == initialFrame)
      #expect(state.workspace == initialWorkspace)
      #expect(state.agentActivity.count == initialActivityCount)

      window.contentView = nil
      window.orderOut(nil)
      await runtime.shutdown()
    }
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
    noteID: UUID = UUID(),
    noteTitle: String,
    actorName: String,
    createdAt: Date = Date()
  ) -> AgentChangeFeedback {
    AgentChangeFeedback(
      changeID: changeID,
      noteID: noteID,
      noteTitle: noteTitle,
      actor: .integration(profileID: UUID(), displayName: actorName),
      resultingRevision: 1,
      createdAt: createdAt
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
private final class AgentActivitySheetPresentation: ObservableObject {
  @Published var isPresented = true
  private(set) var dismissalCount = 0

  func dismiss() {
    dismissalCount += 1
    isPresented = false
  }
}

@MainActor
private struct AgentActivitySheetHarness: View {
  @ObservedObject var presentation: AgentActivitySheetPresentation

  var body: some View {
    Color.clear
      .frame(width: 320, height: 240)
      .sheet(isPresented: $presentation.isPresented) {
        AgentActivityView(onOpenNote: { _ in }, onDismiss: presentation.dismiss)
      }
  }
}

@MainActor
private func agentActivityAccessibilityElement(_ value: Any?, label: String) -> NSObject? {
  guard let element = value as? NSObject else { return nil }
  let labelSelector = NSSelectorFromString("accessibilityLabel")
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let name = element.responds(to: labelSelector)
    ? element.perform(labelSelector)?.takeUnretainedValue() as? String : nil
  if name == label { return element }
  let children = element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in children ?? [] {
    if let found = agentActivityAccessibilityElement(child, label: label) { return found }
  }
  return nil
}

@MainActor
private func agentActivityAccessibilityElement(_ value: Any?, identifier: String) -> NSObject? {
  guard let element = value as? NSObject else { return nil }
  let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let value = element.responds(to: identifierSelector)
    ? element.perform(identifierSelector)?.takeUnretainedValue() as? String : nil
  if value == identifier { return element }
  let children = element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in children ?? [] {
    if let found = agentActivityAccessibilityElement(child, identifier: identifier) { return found }
  }
  return nil
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
  _ = window.performKeyEquivalent(with: event)
}

@MainActor
private func clickAgentActivityElement(_ element: NSObject, in window: NSWindow) throws {
  let frame = try #require(
    element.value(forKey: "accessibilityFrame") as? NSValue
  ).rectValue
  let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
  for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    let event = try #require(
      NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: type == .leftMouseDown ? 1 : 0
      )
    )
    window.sendEvent(event)
  }
}

@MainActor
private func settleAgentActivityHost(_ host: NSView) async {
  for _ in 0..<40 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func settleHostedSheet(_ sheet: NSWindow, parent: NSView) async {
  for _ in 0..<40 {
    parent.layoutSubtreeIfNeeded()
    sheet.contentView?.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
