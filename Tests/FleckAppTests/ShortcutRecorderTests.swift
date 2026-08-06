#if os(macOS)
  import AppKit
  import Foundation
  import FleckCore
  import Testing

  @testable import FleckApp

  private func shortcutEvent(
    keyCode: UInt16,
    characters: String = "n",
    charactersIgnoringModifiers: String = "n",
    modifierFlags: NSEvent.ModifierFlags = [],
    isARepeat: Bool = false
  ) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers,
        isARepeat: isARepeat,
        keyCode: keyCode
      )
    )
  }

  private func mouseEvent(type: NSEvent.EventType) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
      )
    )
  }

  @Test func normalizerMapsSpecialKeysAndOrdinaryCharacters() throws {
    let cases: [(UInt16, String, String, String)] = [
      (48, "\t", "\t", "tab"),
      (51, "\u{8}", "\u{8}", "backspace"),
      (117, "", "", "forwarddelete"),
      (53, "\u{1b}", "\u{1b}", "escape"),
      (36, "\r", "\r", "return"),
      (76, "\r", "\r", "enter"),
      (49, " ", " ", "space"),
      (123, "←", "←", "left"),
      (124, "→", "→", "right"),
      (126, "↑", "↑", "up"),
      (125, "↓", "↓", "down"),
      (115, "", "", "home"),
      (119, "", "", "end"),
      (116, "", "", "pageup"),
      (121, "", "", "pagedown"),
      (122, "", "", "f1"),
      (90, "", "", "f20"),
      (8, "N", "n", "n"),
    ]

    for (keyCode, characters, ignoringModifiers, key) in cases {
      let event = try shortcutEvent(
        keyCode: keyCode,
        characters: characters,
        charactersIgnoringModifiers: ignoringModifiers
      )
      #expect(
        ShortcutEventNormalizer.chord(for: event)
          == ShortcutChord(key: key, modifiers: [])
      )
    }
  }

  @Test func normalizerUsesCanonicalModifierOrderAndIgnoresIrrelevantFlags() throws {
    let event = try shortcutEvent(
      keyCode: 8,
      modifierFlags: [.option, .function, .capsLock, .numericPad, .control, .shift, .command]
    )

    #expect(
      ShortcutEventNormalizer.chord(for: event)
        == ShortcutChord(
          key: "n",
          modifiers: ["command", "shift", "control", "option"]
        )
    )
  }

  @Test func normalizerKeepsShiftTabAsTabWithShift() throws {
    let event = try shortcutEvent(
      keyCode: 48,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      modifierFlags: [.shift]
    )

    #expect(
      ShortcutEventNormalizer.chord(for: event)
        == ShortcutChord(key: "tab", modifiers: ["shift"])
    )
  }

  @Test func normalizerRejectsAnUnknownKeyWithoutCharacters() throws {
    let event = try shortcutEvent(
      keyCode: 200,
      characters: "",
      charactersIgnoringModifiers: ""
    )

    #expect(ShortcutEventNormalizer.chord(for: event) == nil)
  }

  @Test func displayLabelsUseReadableSpecialNamesAndLegacyFallbacks() {
    let expected: [(String, String)] = [
      ("tab", "⇥"),
      ("backspace", "⌫"),
      ("forwarddelete", "⌦"),
      ("escape", "Esc"),
      ("return", "Return"),
      ("enter", "Enter"),
      ("space", "Space"),
      ("left", "←"),
      ("right", "→"),
      ("up", "↑"),
      ("down", "↓"),
      ("home", "Home"),
      ("end", "End"),
      ("pageup", "Page Up"),
      ("pagedown", "Page Down"),
      ("f1", "F1"),
      ("f20", "F20"),
      ("n", "N"),
    ]

    for (key, display) in expected {
      let shortcut = Shortcut(action: .newNote, key: key, modifiers: [])
      #expect(ShortcutEventNormalizer.displayLabel(for: shortcut) == display)
    }

    #expect(
      ShortcutEventNormalizer.displayLabel(
        for: Shortcut(action: .newNote, key: "legacy-key", modifiers: ["command"])
      ) == "⌘LEGACY-KEY"
    )
    #expect(ShortcutEventNormalizer.displayLabel(for: nil) == "Not set")
  }

  @Test func shortcutMonitorMatchesRecordedSpecialAndModifiedChords() throws {
    let bareBackspace = try shortcutEvent(
      keyCode: 51,
      characters: "\u{8}",
      charactersIgnoringModifiers: "\u{8}"
    )
    #expect(
      ShortcutMonitor.action(
        for: bareBackspace,
        shortcuts: [Shortcut(action: .closeNote, key: "backspace", modifiers: [])]
      ) == .closeNote
    )

    let controlTab = try shortcutEvent(
      keyCode: 48,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      modifierFlags: [.control]
    )
    #expect(
      ShortcutMonitor.action(for: controlTab, shortcuts: Shortcut.defaults) == .nextNote
    )

    let shiftControlTab = try shortcutEvent(
      keyCode: 48,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      modifierFlags: [.shift, .control]
    )
    #expect(
      ShortcutMonitor.action(for: shiftControlTab, shortcuts: Shortcut.defaults)
        == .previousNote
    )
  }

  @Test func shortcutMonitorRejectsMismatchedModifiersConflictsAndInvalidShortcuts() throws {
    let controlTab = try shortcutEvent(
      keyCode: 48,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      modifierFlags: [.control]
    )
    let commandTab = try shortcutEvent(
      keyCode: 48,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      modifierFlags: [.command]
    )
    let duplicateShortcuts = [
      Shortcut(action: .nextNote, key: "tab", modifiers: ["control"]),
      Shortcut(action: .previousNote, key: "tab", modifiers: ["control"]),
    ]

    #expect(
      ShortcutMonitor.action(
        for: commandTab,
        shortcuts: [Shortcut(action: .nextNote, key: "tab", modifiers: ["control"])]
      ) == nil
    )
    #expect(ShortcutMonitor.action(for: controlTab, shortcuts: duplicateShortcuts) == nil)
    #expect(
      ShortcutMonitor.action(
        for: controlTab,
        shortcuts: [Shortcut(action: .nextNote, key: nil, modifiers: ["control"])]
      ) == nil
    )
    #expect(
      ShortcutMonitor.action(
        for: controlTab,
        shortcuts: [Shortcut(action: .nextNote, key: nil, modifiers: [])]
      ) == nil
    )
  }

  @Test @MainActor func captureCoordinatorCapturesOneValidEventAndConsumesLaterEvents() throws {
    var captured: [ShortcutChord] = []
    var cancellations = 0
    let coordinator = ShortcutRecorder.CaptureBridge.Coordinator(
      onCapture: { captured.append($0) },
      onCancel: { cancellations += 1 }
    )

    coordinator.start()
    coordinator.start()
    #expect(coordinator.isMonitoring)

    let first = try shortcutEvent(keyCode: 8)
    #expect(coordinator.handle(first) == nil)
    #expect(captured == [ShortcutChord(key: "n", modifiers: [])])
    #expect(cancellations == 0)
    #expect(!coordinator.isMonitoring)

    let second = try shortcutEvent(keyCode: 9, characters: "m", charactersIgnoringModifiers: "m")
    #expect(coordinator.handle(second) === second)
    #expect(captured.count == 1)
  }

  @Test @MainActor func captureCoordinatorConsumesRepeatAndUnsupportedEventsWithoutSaving() throws {
    var captured: [ShortcutChord] = []
    let coordinator = ShortcutRecorder.CaptureBridge.Coordinator(
      onCapture: { captured.append($0) },
      onCancel: {}
    )

    coordinator.start()
    let repeated = try shortcutEvent(keyCode: 8, isARepeat: true)
    #expect(coordinator.handle(repeated) == nil)
    #expect(coordinator.isMonitoring)

    let unsupported = try shortcutEvent(
      keyCode: 200,
      characters: "",
      charactersIgnoringModifiers: ""
    )
    #expect(coordinator.handle(unsupported) == nil)
    #expect(coordinator.isMonitoring)
    #expect(captured.isEmpty)

    coordinator.stop()
  }

  @Test @MainActor func captureCoordinatorCancelsOnMouseDownAndReturnsTheMouseEvent() throws {
    var cancellations = 0
    let coordinator = ShortcutRecorder.CaptureBridge.Coordinator(
      onCapture: { _ in },
      onCancel: { cancellations += 1 }
    )
    coordinator.start()

    let click = try mouseEvent(type: .leftMouseDown)
    #expect(coordinator.handle(click) === click)
    #expect(cancellations == 1)
    #expect(!coordinator.isMonitoring)

    let secondClick = try mouseEvent(type: .rightMouseDown)
    #expect(coordinator.handle(secondClick) === secondClick)
    #expect(cancellations == 1)
  }

  @Test @MainActor func captureCoordinatorStopAndDismantleAreIdempotent() {
    let bridge = ShortcutRecorder.CaptureBridge(onCapture: { _ in }, onCancel: {})
    let coordinator = bridge.makeCoordinator()
    coordinator.start()
    coordinator.stop()
    coordinator.stop()
    #expect(!coordinator.isMonitoring)

    coordinator.start()
    ShortcutRecorder.CaptureBridge.dismantleNSView(
      NSView(frame: .zero),
      coordinator: coordinator
    )
    #expect(!coordinator.isMonitoring)
  }

  @Test func settingsUsesTheCenteredNativeShortcutRecorderContract() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let settingsSource = try String(
      contentsOf: sourceRoot.appendingPathComponent("Sources/FleckApp/SettingsView.swift")
    )
    let recorderSource = try String(
      contentsOf: sourceRoot.appendingPathComponent("Sources/FleckApp/ShortcutRecorder.swift")
    )

    #expect(!settingsSource.contains("TextField(\"Key\""))
    #expect(!settingsSource.contains("shortcutKeyBinding"))
    #expect(!settingsSource.contains("modifierBinding"))
    #expect(settingsSource.contains("@State private var recordingShortcutAction: Shortcut.Action?"))
    #expect(settingsSource.contains("ShortcutRecorder("))
    #expect(
      settingsSource.contains(
        "This shortcut may replace normal typing or navigation while Fleck is active."
      )
    )
    #expect(
      settingsSource.contains(
        "Click a shortcut and press the complete chord. Conflicting combinations are highlighted and disabled shortcuts can be restored at any time."
      )
    )
    #expect(settingsSource.contains("setShortcutEnabled"))
    #expect(recorderSource.contains(".frame(minWidth: 112"))
    #expect(recorderSource.contains("Record shortcut for "))
    #expect(recorderSource.contains("Press shortcut"))
    #expect(!recorderSource.contains(".animation"))
  }

  @Test @MainActor func settingsSectionTransitionCancelsRecordingWithoutMutatingSavedChord() throws {
    let savedShortcut = Shortcut(
      action: .newNote,
      key: "n",
      modifiers: ["command"]
    )
    let savedKey = savedShortcut.key
    let savedModifiers = savedShortcut.modifiers

    #expect(
      SettingsView.recordingAction(
        afterSelecting: .appearance,
        currentAction: .newNote
      ) == nil
    )
    #expect(savedShortcut.key == savedKey)
    #expect(savedShortcut.modifiers == savedModifiers)

    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let settingsSource = try String(
      contentsOf: sourceRoot.appendingPathComponent("Sources/FleckApp/SettingsView.swift")
    )
    #expect(settingsSource.contains("recordingShortcutAction = Self.recordingAction("))
    #expect(settingsSource.contains("afterSelecting: newSection"))
    #expect(settingsSource.contains(".onDisappear { recordingShortcutAction = nil }"))
  }
#endif
