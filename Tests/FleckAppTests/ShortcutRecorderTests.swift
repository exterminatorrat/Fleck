#if os(macOS)
  import AppKit
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
#endif
