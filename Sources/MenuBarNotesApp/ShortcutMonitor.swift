#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore

  /// Routes user-configured shortcuts while the notes panel is active without a
  /// third-party hot-key dependency. The show/hide command closes the active panel;
  /// system-wide activation is intentionally isolated for a future status-item host.
  struct ShortcutMonitor: NSViewRepresentable {
    let shortcuts: [Shortcut]
    let action: (Shortcut.Action) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSView {
      context.coordinator.install(shortcuts: shortcuts)
      return NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
      context.coordinator.action = action
      context.coordinator.shortcuts = shortcuts
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
      coordinator.uninstall()
    }

    final class Coordinator {
      var action: (Shortcut.Action) -> Void
      var shortcuts: [Shortcut] = []
      private var monitor: Any?

      init(action: @escaping (Shortcut.Action) -> Void) {
        self.action = action
      }

      func install(shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
          guard let self, let command = self.match(event) else { return event }
          self.action(command)
          return nil
        }
      }

      func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
      }

      private func match(_ event: NSEvent) -> Shortcut.Action? {
        let key = eventKey(event)
        let acceptedModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let modifiers = event.modifierFlags.intersection(acceptedModifiers)
        let conflicts = Shortcut.conflicts(in: shortcuts)
        return shortcuts.first { shortcut in
          guard shortcut.isValid, !conflicts.contains(shortcut.action), shortcut.key == key else {
            return false
          }
          return eventModifiers(shortcut.modifiers) == modifiers
        }?.action
      }

      private func eventKey(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 48: return "tab"
        default: return event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
      }

      private func eventModifiers(_ values: [String]) -> NSEvent.ModifierFlags {
        values.reduce(into: NSEvent.ModifierFlags()) { result, value in
          switch value {
          case "command": result.insert(.command)
          case "shift": result.insert(.shift)
          case "control": result.insert(.control)
          case "option": result.insert(.option)
          default: break
          }
        }
      }
    }
  }
#endif
