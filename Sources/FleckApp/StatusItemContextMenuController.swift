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

    private var eventMonitor: EventMonitorToken?
    private lazy var menu: NSMenu = {
      let menu = NSMenu()
      let quitItem = NSMenuItem(
        title: Self.quitTitle,
        action: #selector(quitApplication),
        keyEquivalent: ""
      )
      quitItem.target = self
      menu.addItem(quitItem)
      return menu
    }()

    override init() {
      super.init()
      if let monitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown],
        handler: { [weak self] event in
          self?.handle(event) ?? event
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

    static func startsPanelPresentationMeasurement(
      eventType: NSEvent.EventType,
      windowLevel: NSWindow.Level?
    ) -> Bool {
      eventType == .leftMouseDown && windowLevel == .statusBar
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      if Self.startsPanelPresentationMeasurement(
        eventType: event.type,
        windowLevel: event.window?.level
      ) {
        FleckPanelPresentationMeasurement.shared.begin()
        return event
      }

      guard
        Self.handles(
          eventType: event.type,
          windowLevel: event.window?.level
        ),
        let view = event.window?.contentView
      else {
        return event
      }

      NSMenu.popUpContextMenu(menu, with: event, for: view)
      return nil
    }

    @objc private func quitApplication() {
      NSApplication.shared.terminate(nil)
    }
  }
#endif
