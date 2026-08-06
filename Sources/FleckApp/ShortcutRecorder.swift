#if os(macOS)
  import AppKit
  import FleckCore
  import SwiftUI

  struct ShortcutChord: Equatable {
    let key: String
    let modifiers: [String]
  }

  enum ShortcutEventNormalizer {
    private static let specialKeys: [UInt16: (key: String, display: String)] = [
      48: ("tab", "⇥"),
      51: ("backspace", "⌫"),
      117: ("forwarddelete", "⌦"),
      53: ("escape", "Esc"),
      36: ("return", "Return"),
      76: ("enter", "Enter"),
      49: ("space", "Space"),
      123: ("left", "←"),
      124: ("right", "→"),
      126: ("up", "↑"),
      125: ("down", "↓"),
      115: ("home", "Home"),
      119: ("end", "End"),
      116: ("pageup", "Page Up"),
      121: ("pagedown", "Page Down"),
    ]

    private static let functionKeys: [UInt16: String] = [
      122: "f1",
      120: "f2",
      99: "f3",
      118: "f4",
      96: "f5",
      97: "f6",
      98: "f7",
      100: "f8",
      101: "f9",
      109: "f10",
      103: "f11",
      111: "f12",
      105: "f13",
      107: "f14",
      113: "f15",
      106: "f16",
      64: "f17",
      79: "f18",
      80: "f19",
      90: "f20",
    ]

    static func chord(for event: NSEvent) -> ShortcutChord? {
      guard let key = key(for: event) else { return nil }
      let modifiers = Shortcut.normalizedModifiers([
        event.modifierFlags.contains(.command) ? "command" : nil,
        event.modifierFlags.contains(.shift) ? "shift" : nil,
        event.modifierFlags.contains(.control) ? "control" : nil,
        event.modifierFlags.contains(.option) ? "option" : nil,
      ].compactMap { $0 })
      return ShortcutChord(key: key, modifiers: modifiers)
    }

    static func displayLabel(for shortcut: Shortcut?) -> String {
      guard let shortcut, let key = shortcut.key else { return "Not set" }
      let modifiers = Shortcut.normalizedModifiers(shortcut.modifiers).map { modifier in
        switch modifier {
        case "command": "⌘"
        case "shift": "⇧"
        case "control": "⌃"
        case "option": "⌥"
        default: modifier.uppercased()
        }
      }.joined()
      let displayKey = specialKeys.first { $0.value.key == key }?.value.display
        ?? functionKeys.first { $0.value == key }?.value.uppercased()
        ?? key.uppercased()
      return modifiers + displayKey
    }

    private static func key(for event: NSEvent) -> String? {
      if let special = specialKeys[event.keyCode] {
        return special.key
      }
      if let functionKey = functionKeys[event.keyCode] {
        return functionKey
      }
      let key = event.charactersIgnoringModifiers?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      return key.isEmpty ? nil : key
    }
  }

  struct ShortcutRecorder: View {
    let action: Shortcut.Action
    let shortcut: Shortcut?
    let isRecording: Bool
    let onBegin: () -> Void
    let onCapture: (ShortcutChord) -> Void
    let onCancel: () -> Void

    var body: some View {
      ZStack {
        Button(action: onBegin) {
          Text(isRecording ? "Press shortcut…" : ShortcutEventNormalizer.displayLabel(for: shortcut))
            .frame(minWidth: 112, alignment: .center)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Record shortcut for \(action.title)")
        .accessibilityValue(
          isRecording
            ? "Press shortcut"
            : ShortcutEventNormalizer.displayLabel(for: shortcut)
        )

        if isRecording {
          CaptureBridge(onCapture: onCapture, onCancel: onCancel)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
      }
    }

    struct CaptureBridge: NSViewRepresentable {
      let onCapture: (ShortcutChord) -> Void
      let onCancel: () -> Void

      func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
      }

      func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
      }

      func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
        context.coordinator.start()
      }

      static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
      }

      final class Coordinator {
        var onCapture: (ShortcutChord) -> Void
        var onCancel: () -> Void
        private var monitor: Any?

        var isMonitoring: Bool { monitor != nil }

        init(
          onCapture: @escaping (ShortcutChord) -> Void,
          onCancel: @escaping () -> Void
        ) {
          self.onCapture = onCapture
          self.onCancel = onCancel
        }

        func start() {
          guard monitor == nil else { return }
          monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
          ) { [weak self] event in
            self?.handle(event) ?? event
          }
        }

        func stop() {
          if let monitor {
            NSEvent.removeMonitor(monitor)
          }
          monitor = nil
        }

        @discardableResult
        func handle(_ event: NSEvent) -> NSEvent? {
          guard isMonitoring else { return event }
          switch event.type {
          case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            stop()
            onCancel()
            return event
          case .keyDown:
            guard !event.isARepeat else { return nil }
            guard let chord = ShortcutEventNormalizer.chord(for: event) else { return nil }
            stop()
            onCapture(chord)
            return nil
          default:
            return event
          }
        }

        deinit {
          stop()
        }
      }
    }
  }
#endif
