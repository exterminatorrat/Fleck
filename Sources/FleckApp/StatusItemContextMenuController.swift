#if os(macOS)
  import AppKit
  import Combine

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
    private weak var updateController: AppUpdateController?
    private var updateObservation: AnyCancellable?
    private var updateMenuItem: NSMenuItem?
    private var updateExplanationItem: NSMenuItem?
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
      updateMenuItem = updateItem

      let updateExplanationItem = NSMenuItem(
        title: Self.updateUnavailableExplanation,
        action: nil,
        keyEquivalent: ""
      )
      updateExplanationItem.isEnabled = false
      menu.addItem(updateExplanationItem)
      self.updateExplanationItem = updateExplanationItem

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

    func bindUpdateController(_ controller: AppUpdateController) {
      updateObservation = nil
      updateController = controller
      refreshUpdateItems()
      updateObservation = controller.$state.sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshUpdateItems()
        }
      }
    }

    private func refreshUpdateItems() {
      _ = contextMenu
      guard let updateController else {
        updateMenuItem?.isEnabled = false
        updateMenuItem?.action = nil
        updateMenuItem?.toolTip = Self.updateUnavailableExplanation
        updateExplanationItem?.title = Self.updateUnavailableExplanation
        return
      }
      updateMenuItem?.isEnabled = updateController.canCheckForUpdates
      updateMenuItem?.action = updateController.canCheckForUpdates
        ? #selector(checkForUpdateInformation(_:)) : nil
      updateMenuItem?.target = self
      updateMenuItem?.toolTip = updateController.statusText
      if case .newVersionAvailable = updateController.state {
        updateExplanationItem?.title = "A newer release is listed; installation is unavailable."
      } else {
        updateExplanationItem?.title = updateController.statusText
      }
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

      refreshUpdateItems()
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

    @objc private func checkForUpdateInformation(_ sender: Any?) {
      updateController?.checkForUpdates()
      refreshUpdateItems()
    }

    @objc private func quitApplication(_ sender: Any?) {
      quitAction()
    }
  }
#endif
