#if os(macOS)
  import AppKit
  import Testing
  @testable import FleckApp

  @Test @MainActor func statusItemContextMenuOnlyHandlesSecondaryStatusBarClicks() {
    #expect(StatusItemContextMenuController.quitTitle == "Quit Motes")
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
#endif
