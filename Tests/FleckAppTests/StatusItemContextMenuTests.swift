#if os(macOS)
  import AppKit
  import Testing
  @testable import FleckApp

  @MainActor
  private func dispatch(_ item: NSMenuItem) -> Bool {
    guard let action = item.action else { return false }
    return NSApplication.shared.sendAction(action, to: item.target, from: item)
  }

  @MainActor
  private final class MenuUpdateChecker: AppUpdateInformationChecking {
    var canCheckForUpdates = true
    private(set) var starts = 0

    func startInformationCheck(
      completion: @escaping @MainActor (AppUpdateProbeResult) -> Void
    ) {
      starts += 1
    }
  }

  @MainActor
  private func menuUpdates(checker: MenuUpdateChecker) -> AppUpdateController {
    let info: [String: Any] = [
      "SUFeedURL": "https://raw.githubusercontent.com/exterminatorrat/fleck/fixture/appcast.xml",
      "SUPublicEDKey": "PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw=",
      "SURequireSignedFeed": true,
      "SUVerifyUpdateBeforeExtraction": true,
      "SUSignedFeedFailureExpirationInterval": 0,
      "SUEnableAutomaticChecks": false,
      "SUAutomaticallyUpdate": false,
      "SUAllowsAutomaticUpdates": false,
      "SUEnableSystemProfiling": false,
      "SUEnableJavaScript": false,
      "SUShowReleaseNotes": false,
    ]
    let identity = BuildIdentity(
      infoDictionary: [
        "FleckVersion": "1.6.0-beta.1",
        "FleckBuildNumber": "10204",
        "CFBundleVersion": "2.2.3",
        "FleckBuildID": "4c6bf7d2-406f-4d2a-b4ea-0927f0378666",
        "FleckBuildDate": "2026-09-11T14:30:00Z",
        "FleckSourceCommit": String(repeating: "a", count: 40),
        "FleckSourceTree": String(repeating: "b", count: 40),
        "FleckBuildFlavor": "corrected",
        "FleckBuildConfiguration": "Debug",
        "FleckCandidateStatus": "Candidate - not accepted",
        "FleckBaselineManifestSHA256": String(repeating: "c", count: 64),
        "FleckBaselineRecordID": "fixture-accepted",
        "FleckBaselineRegistryStatus": "active",
      ],
      bundleIdentifier: "com.harryjin.fleck"
    )
    return AppUpdateController(
      infoDictionary: info,
      identity: identity,
      checkerFactory: { _, _ in checker }
    )
  }

  @Test @MainActor func statusItemContextMenuOnlyHandlesSecondaryStatusBarClicks() {
    #expect(StatusItemContextMenuController.quitTitle == "Quit Fleck")
    let secondaryStatusBarClick = StatusItemContextMenuController.handles(
      eventType: .rightMouseDown,
      windowLevel: .statusBar
    )
    let primaryStatusBarClick = StatusItemContextMenuController.handles(
      eventType: .leftMouseDown,
      windowLevel: .statusBar
    )
    let secondaryWindowClick = StatusItemContextMenuController.handles(
      eventType: .rightMouseDown,
      windowLevel: .normal
    )
    #expect(secondaryStatusBarClick)
    #expect(!primaryStatusBarClick)
    #expect(!secondaryWindowClick)
  }

  @Test @MainActor func statusItemContextMenuHasExplicitNativeInventory() throws {
    let controller = StatusItemContextMenuController(installEventMonitor: false)
    let menu = controller.contextMenu

    #expect(menu.items.map { $0.isSeparatorItem ? "<separator>" : $0.title } == [
      "Show Notes",
      "Settings…",
      "About Fleck",
      "<separator>",
      "Check for Updates…",
      StatusItemContextMenuController.updateUnavailableExplanation,
      "<separator>",
      StatusItemContextMenuController.quitTitle,
    ])

    let settingsItem = try #require(menu.item(withTitle: "Settings…"))
    #expect(settingsItem.keyEquivalent == ",")
    #expect(settingsItem.keyEquivalentModifierMask == [.command])

    let quitItem = try #require(
      menu.item(withTitle: StatusItemContextMenuController.quitTitle)
    )
    #expect(quitItem.keyEquivalent == "q")
    #expect(quitItem.keyEquivalentModifierMask == [.command])

    let updateItem = try #require(menu.item(withTitle: "Check for Updates…"))
    #expect(!updateItem.isEnabled)
    #expect(updateItem.action == nil)
    #expect(
      updateItem.toolTip == StatusItemContextMenuController.updateUnavailableExplanation
    )

    let updateExplanationItem = try #require(
      menu.item(withTitle: StatusItemContextMenuController.updateUnavailableExplanation)
    )
    #expect(!updateExplanationItem.isEnabled)
    #expect(updateExplanationItem.action == nil)
  }

  @Test @MainActor func statusItemContextMenuDispatchesInstalledActions() throws {
    var dispatched: [String] = []
    let controller = StatusItemContextMenuController(
      installEventMonitor: false,
      quitAction: { dispatched.append("quit") }
    )
    let menu = controller.contextMenu
    let showNotesItem = try #require(menu.item(withTitle: "Show Notes"))
    let settingsItem = try #require(menu.item(withTitle: "Settings…"))
    let aboutItem = try #require(menu.item(withTitle: "About Fleck"))
    let quitItem = try #require(
      menu.item(withTitle: StatusItemContextMenuController.quitTitle)
    )

    #expect(!showNotesItem.isEnabled)
    #expect(!settingsItem.isEnabled)
    #expect(!aboutItem.isEnabled)
    #expect(quitItem.isEnabled)
    #expect(dispatched.isEmpty)

    controller.installActions(
      showNotes: { dispatched.append("notes") },
      openSettings: { dispatched.append("settings-editing") },
      openAbout: { dispatched.append("settings-about") }
    )

    #expect(showNotesItem.isEnabled)
    #expect(settingsItem.isEnabled)
    #expect(aboutItem.isEnabled)
    #expect(dispatched.isEmpty)

    let updateItem = try #require(menu.item(withTitle: "Check for Updates…"))
    let updateExplanationItem = try #require(
      menu.item(withTitle: StatusItemContextMenuController.updateUnavailableExplanation)
    )
    #expect(!updateItem.isEnabled)
    #expect(updateItem.action == nil)
    #expect(!updateExplanationItem.isEnabled)
    #expect(updateExplanationItem.action == nil)

    #expect(dispatch(showNotesItem))
    #expect(dispatch(settingsItem))
    #expect(dispatch(aboutItem))
    #expect(dispatch(quitItem))
    #expect(dispatched == ["notes", "settings-editing", "settings-about", "quit"])
  }
  @Test @MainActor func statusItemContextMenuUpdateBindingPreservesInertPresentation() throws {
    let updates = AppUpdateController()
    let initialStatus = updates.statusText
    let controller = StatusItemContextMenuController(installEventMonitor: false)
    let menu = controller.contextMenu
    let originalTitles = menu.items.map(\.title)

    controller.bindUpdateController(updates)
    _ = AboutSettingsView(updateController: updates)

    let updateItem = try #require(menu.item(withTitle: "Check for Updates…"))
    #expect(updates.statusText == initialStatus)
    #expect(updateItem.isEnabled == updates.canCheckForUpdates)
    #expect(updateItem.toolTip == initialStatus)
    #expect(menu.items.count == originalTitles.count)
    #expect(menu.items[0].title == "Show Notes")
    #expect(menu.items[1].title == "Settings…")
    #expect(menu.items[2].title == "About Fleck")
    #expect(menu.items[7].title == StatusItemContextMenuController.quitTitle)
    #expect(menu.item(withTitle: "Show Notes")?.isEnabled == false)
    #expect(menu.item(withTitle: "Settings…")?.isEnabled == false)
    #expect(menu.item(withTitle: "About Fleck")?.isEnabled == false)
    if !updates.canCheckForUpdates {
      #expect(updateItem.action == nil)
    }
  }

  @Test @MainActor func statusItemContextMenuUpdateRebindingPreservesInstalledActions() throws {
    var dispatched: [String] = []
    let controller = StatusItemContextMenuController(
      installEventMonitor: false,
      quitAction: { dispatched.append("quit") }
    )
    controller.installActions(
      showNotes: { dispatched.append("notes") },
      openSettings: { dispatched.append("settings") },
      openAbout: { dispatched.append("about") }
    )
    let firstUpdates = AppUpdateController()
    let secondUpdates = AppUpdateController()
    let secondStatus = secondUpdates.statusText
    controller.bindUpdateController(firstUpdates)
    controller.bindUpdateController(secondUpdates)

    let menu = controller.contextMenu
    let notesItem = try #require(menu.item(withTitle: "Show Notes"))
    let settingsItem = try #require(menu.item(withTitle: "Settings…"))
    let aboutItem = try #require(menu.item(withTitle: "About Fleck"))
    #expect(dispatched.isEmpty)
    #expect(secondUpdates.statusText == secondStatus)
    #expect(dispatch(notesItem))
    #expect(dispatch(settingsItem))
    #expect(dispatch(aboutItem))
    #expect(dispatched == ["notes", "settings", "about"])
  }

  @Test @MainActor func statusItemContextMenuExplicitCheckDispatchesOnlyOneProbe() throws {
    let checker = MenuUpdateChecker()
    let updates = menuUpdates(checker: checker)
    let controller = StatusItemContextMenuController(installEventMonitor: false)
    controller.bindUpdateController(updates)
    _ = AboutSettingsView(updateController: updates)
    let item = try #require(controller.contextMenu.item(withTitle: "Check for Updates…"))

    #expect(checker.starts == 0)
    #expect(updates.state == .idle)
    #expect(item.isEnabled)
    #expect(dispatch(item))
    #expect(checker.starts == 1)
    #expect(updates.state == .checking)
    #expect(!item.isEnabled)
    #expect(item.action == nil)
    updates.checkForUpdates()
    #expect(checker.starts == 1)
  }
#endif
