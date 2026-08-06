# Fleck Native Shortcut Recorder Design

Date: 2026-08-06
Status: Approved interaction and architecture; awaiting written-spec review

## Objective

Replace the editable shortcut key text fields in Fleck Settings with a native
press-to-record control. A user clicks the control, presses the complete shortcut
chord they want, and Fleck records the actual key plus held modifiers. This must
support non-text keys such as Tab and Backspace without asking users to spell key
names.

The result must remain a native SwiftUI/AppKit implementation, preserve existing
shortcut preferences, and use the production `ShortcutMonitor` path.

## Current Problem

`SettingsView` currently places `TextField("Key", text:)` inside the macOS grouped
`Form`. AppKit form styling treats it as a labeled field and gives the editable
value trailing-oriented form alignment. The insertion caret after a one-character
value makes the value look even farther to the right.

The field also accepts arbitrary text rather than keyboard events. Users must know
that values such as `tab` are recognized, and keys such as Backspace, Escape,
arrows, or function keys do not have an intuitive text-entry contract.

## Approved Product Behavior

### Complete-Chord Recording

Each shortcut row replaces the text field and separate modifier menu with one
centered recorder control.

- At rest, the control displays the current chord using macOS modifier symbols and
  readable special-key glyphs or names, such as `⌘⇧N`, `⌫`, `⌃⇥`, `←`, `Return`,
  or `F5`.
- Clicking it begins recording and changes its label to `Press shortcut…` with a
  visible native focus ring.
- The first non-modifier key-down records that key together with the Command,
  Shift, Control, and Option modifiers held for the event.
- The captured event is consumed so it does not also activate a menu command,
  traverse focus, edit text, or trigger an existing Fleck shortcut.
- Recording ends immediately after one valid chord is stored.
- Clicking outside while recording cancels without changing the saved shortcut.
- Escape is a recordable key, not an implicit cancellation command. The existing
  Remove action remains the explicit way to clear a shortcut.
- Modifier-only shortcuts are not added. They require `flagsChanged` semantics and
  would overlap Fleck's separate dictation modifier system.

### Bare Keys

Fleck accepts a chord without modifiers when that is what the user records. A bare
key is an intentional advanced choice, not a validation error.

When a shortcut has no modifier, its row shows an inline caution:
`This shortcut may replace normal typing or navigation while Fleck is active.`

The caution does not block saving. The runtime continues to consume a matching
event while the notes panel is active, so the warning states the real tradeoff.

### Conflicts, Removal, and Restoration

Existing duplicate-chord detection remains authoritative. Conflicting shortcuts
show the existing conflict warning, and conflicting actions do not fire.

Remove clears the chord. Restore reinstates that action's existing default chord.
No automatic conflict resolution or shortcut reassignment is introduced.

## Architecture

### Native Capture Boundary

SwiftUI does not expose a reliable shortcut-recording control for command chords,
Tab, Backspace, arrows, Escape, and function keys. Add one narrow AppKit bridge
owned by the Settings shortcut row.

The bridge installs an application-local key-down monitor only while a recorder is
active. Its coordinator owns the monitor token and removes it when recording ends,
is cancelled, or the representable is dismantled. It reports a single normalized
chord to SwiftUI through a callback; SwiftUI remains the owner of recording state
and the preference mutation.

Do not add a global event tap, Input Monitoring requirement, third-party hot-key
package, long-lived global view, or second shortcut state store.

### Shared Event Normalization

The recorder and production `ShortcutMonitor` must use one shared AppKit event-to-
key mapping. It maps common non-text keys to stable canonical strings and otherwise
uses the event's characters ignoring modifiers. At minimum it covers:

- Tab and Backtab
- Backspace/Delete and Forward Delete
- Escape, Return, Enter, and Space
- Left, Right, Up, and Down arrows
- Home, End, Page Up, and Page Down
- F1 through F20
- ordinary letters, numbers, and punctuation

Modifier values use the existing canonical order from `Shortcut.Modifier.allCases`.
The same mapping must be used when recording and matching so a recorded chord is
guaranteed to be representable by the runtime.

The persisted `Shortcut` shape remains `key: String?` plus `modifiers: [String]`.
Existing JSON and defaults, including legacy `tab` values, remain compatible. No
preference migration is needed.

### UI State and Data Flow

`recorder click -> Settings-local recording action -> scoped AppKit key monitor ->
normalized key and modifiers -> AppState.updatePreferences -> existing Shortcut`

`panel key-down -> ShortcutMonitor -> same normalization -> conflict and chord
match -> existing action callback`

Only one row may record at a time. Starting another row cancels the previous row
without mutation. Re-rendering Settings must not duplicate monitors.

## Presentation and Accessibility

- The recorder is a button-like keycap with centered content; it is not a text
  field and has no insertion caret.
- Its accessible label identifies the action, for example `Record shortcut for New
  note`.
- While active, its value or announcement communicates `Press shortcut`.
- Current chord, bare-key caution, conflict warning, Remove, and Restore remain
  available to VoiceOver and keyboard navigation.
- The control uses native focus indication and semantic colors in Light and Dark
  appearances.
- Recording has no animation or artificial delay because it is a frequent keyboard
  interaction.

## Failure and Recovery Behavior

- An event that cannot produce a supported normalized key does not overwrite the
  existing shortcut; recording remains active or reports that the key is
  unsupported.
- Auto-repeated events cannot save a second chord.
- Losing focus, clicking elsewhere, closing Settings, or dismantling the recorder
  removes the monitor and preserves the prior chord if no valid chord was saved.
- A stored legacy key that is not display-specialized remains visible as its
  existing uppercased string rather than being discarded.
- Preference save errors continue through the existing `AppState` error path.

## Interfaces and Constraints

- Preserve `Shortcut`, `AppPreferences.shortcuts`, `Shortcut.defaults`,
  `Shortcut.conflicts(in:)`, and existing Codable compatibility.
- Preserve `ShortcutMonitor` as the runtime action router.
- Preserve all current shortcut actions and their defaults.
- Use the existing `AppState.updatePreferences` mutation path.
- Add no dependency, event tap, global keyboard listener, or new permission.
- Do not change the dictation modifier shortcut system.
- Do not change note content, the real `NSTextView` editor, tab dragging, accent
  colors, toolbar behavior, window sizing, unrelated Settings sections, generated
  files, or `Package.resolved`.
- Preserve unrelated and concurrent work.

## Verification

### Automated Seams

1. Shortcut persistence and normalization:
   - existing letter and `tab` fixtures still decode and round-trip;
   - recorded special-key canonical values round-trip;
   - bare chords are valid;
   - duplicate bare and modified chords remain conflicts.
2. AppKit event normalization:
   - ordinary keys, Command/Shift/Control/Option chords, Tab, Backspace, Escape,
     arrows, Space, Return, and function keys map to expected values;
   - recorder and `ShortcutMonitor` share the same mapping.
3. Recorder lifecycle:
   - recording captures and consumes exactly one valid event;
   - the callback receives normalized key and modifier values once;
   - outside cancellation does not mutate the chord;
   - finish, cancellation, focus loss, and dismantling remove the monitor without
     leaks or duplicate callbacks.
4. Runtime behavior:
   - production matching fires recorded special and bare keys;
   - mismatched modifiers do not fire;
   - conflicts remain disabled.
5. Settings source and behavior:
   - shortcut rows use the recorder rather than an editable key `TextField`;
   - modifier selection is part of capture rather than a separate menu;
   - centered presentation, accessible labels, warning copy, Remove, and Restore
     remain present.

Use vertical red-green slices through these public seams. Prefer real `NSEvent` and
AppKit lifecycle behavior over source-string-only assertions where practical.

### Repository Checks

- Run focused shortcut, preference, Settings, and AppKit tests.
- Run `swift test --disable-automatic-resolution --no-parallel --quiet` and report
  the exact test and suite counts.
- Run `git diff --check` and confirm `Package.resolved` is unchanged.
- Run `Scripts/validate-macos.sh` once after the correction is ready.

### Packaged-App QA

Build and launch the exact `.build/Fleck.app`. Never edit the leftmost personal
to-do note; use a disposable QA note or a safe Settings-only interaction.

1. Verify every shortcut value is visually centered at rest and while recording.
2. Record and trigger a modified special-key chord such as Command-Backspace.
3. Record and trigger a bare key such as Tab, verify the caution, and confirm the
   documented editing/navigation interception while Fleck is active.
4. Record Escape, arrows, Return, and a function key where the available keyboard
   permits.
5. Verify clicking outside cancels without mutation and only one row can record.
6. Verify duplicate conflicts remain disabled and Remove/Restore still work.
7. Quit and reopen the packaged app and confirm the recorded chords persist.
8. Check keyboard navigation, VoiceOver labels, Light/Dark appearance, and that no
   new Input Monitoring prompt appears.

## Non-Goals

- System-wide shortcuts while Fleck is not active.
- Modifier-only application shortcuts.
- Multi-stroke sequences, key-up timing, hold gestures, or macros.
- Automatic conflict resolution.
- A reusable third-party-style shortcut framework.
- Redesigning the rest of Settings.

## Residual Risk

Bare keys intentionally intercept ordinary editing or navigation when the Fleck
panel is active. The warning makes this tradeoff visible, but the behavior still
requires packaged-app verification because AppKit responder-chain and menu-command
precedence cannot be proven completely by model tests alone.
