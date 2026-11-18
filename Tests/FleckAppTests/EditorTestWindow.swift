import AppKit

/// Removes a fixture's key window as well as its editor. Detaching the view alone
/// leaves an ordered window in the shared AppKit host for the next test.
@MainActor
func closeEditorTestWindow(_ window: NSWindow) {
  window.contentView = nil
  window.orderOut(nil)
  window.close()
}
