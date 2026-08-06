#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore

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
          self?.handle(event) ?? event
        }
      }

      func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
      }

      func handle(_ event: NSEvent) -> NSEvent? {
        guard !ShortcutCaptureGate.isActive, !ShortcutCaptureGate.wasConsumed(event) else {
          return event
        }
        guard let command = match(event) else { return event }
        action(command)
        return nil
      }

      private func match(_ event: NSEvent) -> Shortcut.Action? {
        ShortcutMonitor.action(for: event, shortcuts: shortcuts)
      }
    }

    nonisolated static func action(for event: NSEvent, shortcuts: [Shortcut]) -> Shortcut.Action? {
      guard let chord = ShortcutEventNormalizer.chord(for: event) else { return nil }
      let conflicts = Shortcut.conflicts(in: shortcuts)
      return shortcuts.first { shortcut in
        guard shortcut.isValid,
          shortcut.isEnabled,
          !conflicts.contains(shortcut.action),
          shortcut.key == chord.key
        else {
          return false
        }
        return Shortcut.normalizedModifiers(shortcut.modifiers) == chord.modifiers
      }?.action
    }
  }
#endif
