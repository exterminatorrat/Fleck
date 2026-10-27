#if os(macOS)
  import AppKit
  import Testing
  @testable import FleckApp

  @MainActor
  private func dispatch(_ item: NSMenuItem) -> Bool {
    guard let action = item.action else { return false }
    return NSApplication.shared.sendAction(action, to: item.target, from: item)
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
#endif
