#if os(macOS)
  import AppKit

  @MainActor
  final class StatusItemContextMenuController: NSObject {
    private final class EventMonitorToken: @unchecked Sendable {
      let value: Any

      init(_ value: Any) {
        self.value = value
      }
    }

    static let quitTitle = "Quit Fleck"
    static let updateUnavailableExplanation =
      "No trusted signed update feed or checker is configured."

    private var eventMonitor: EventMonitorToken?
    private let quitAction: @MainActor () -> Void
    private var showNotesAction: (@MainActor () -> Void)?
    private var openSettingsAction: (@MainActor () -> Void)?
    private var openAboutAction: (@MainActor () -> Void)?
    private(set) lazy var contextMenu: NSMenu = {
      let menu = NSMenu()
      menu.autoenablesItems = false

      let showNotesItem = addItem(
        "Show Notes",
        action: #selector(showNotes(_:)),
        to: menu
      )
      showNotesItem.isEnabled = false

      let settingsItem = addItem(
        "Settings…",
        action: #selector(openSettings(_:)),
        keyEquivalent: ",",
        to: menu
      )
      settingsItem.keyEquivalentModifierMask = [.command]
      settingsItem.isEnabled = false

      let aboutItem = addItem(
        "About Fleck",
        action: #selector(openAbout(_:)),
        to: menu
      )
      aboutItem.isEnabled = false

      menu.addItem(.separator())

      let updateItem = NSMenuItem(
        title: "Check for Updates…",
        action: nil,
        keyEquivalent: ""
      )
      updateItem.isEnabled = false
      updateItem.toolTip = Self.updateUnavailableExplanation
      menu.addItem(updateItem)

      let updateExplanationItem = NSMenuItem(
        title: Self.updateUnavailableExplanation,
        action: nil,
        keyEquivalent: ""
      )
      updateExplanationItem.isEnabled = false
      menu.addItem(updateExplanationItem)

      menu.addItem(.separator())

      let quitItem = addItem(
        Self.quitTitle,
        action: #selector(quitApplication(_:)),
        keyEquivalent: "q",
        to: menu
      )
      quitItem.keyEquivalentModifierMask = [.command]
      return menu
    }()

    init(
      installEventMonitor: Bool = true,
      quitAction: @escaping @MainActor () -> Void = {
        NSApplication.shared.terminate(nil)
      }
    ) {
      self.quitAction = quitAction
      super.init()
      guard installEventMonitor else { return }
      if let monitor = NSEvent.addLocalMonitorForEvents(
        matching: .rightMouseDown,
        handler: { [weak self] event in
          guard let self else { return event }
          return self.handle(event)
        }
      ) {
        eventMonitor = EventMonitorToken(monitor)
      }
    }

    deinit {
      if let eventMonitor {
        NSEvent.removeMonitor(eventMonitor.value)
      }
    }

    static func handles(
      eventType: NSEvent.EventType,
      windowLevel: NSWindow.Level?
    ) -> Bool {
      eventType == .rightMouseDown && windowLevel == .statusBar
    }

    func installActions(
      showNotes: @escaping @MainActor () -> Void,
      openSettings: @escaping @MainActor () -> Void,
      openAbout: @escaping @MainActor () -> Void
    ) {
      showNotesAction = showNotes
      openSettingsAction = openSettings
      openAboutAction = openAbout
      contextMenu.item(withTitle: "Show Notes")?.isEnabled = true
      contextMenu.item(withTitle: "Settings…")?.isEnabled = true
      contextMenu.item(withTitle: "About Fleck")?.isEnabled = true
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      guard
        Self.handles(
          eventType: event.type,
          windowLevel: event.window?.level
        ),
        let view = event.window?.contentView
      else {
        return event
      }

      NSMenu.popUpContextMenu(contextMenu, with: event, for: view)
      return nil
    }

    private func addItem(
      _ title: String,
      action: Selector,
      keyEquivalent: String = "",
      to menu: NSMenu
    ) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
      item.target = self
      menu.addItem(item)
      return item
    }

    @objc private func showNotes(_ sender: Any?) {
      showNotesAction?()
    }

    @objc private func openSettings(_ sender: Any?) {
      openSettingsAction?()
    }

    @objc private func openAbout(_ sender: Any?) {
      openAboutAction?()
    }

    @objc private func quitApplication(_ sender: Any?) {
      quitAction()
    }
  }
#endif
