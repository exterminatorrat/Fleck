# Fleck Native Shortcut Recorder Implementation Plan

> **For the Luna implementation task:** Use `executing-plans`, `test-driven-development`,
> `ponytail`, `emil-design-eng`, `build-macos-apps:appkit-interop`, and
> `build-macos-apps:swiftui-patterns`. Work task-by-task with checkbox tracking and
> red-before-green evidence. Implementation is permitted only in the user-visible
> GPT-5.6 Luna / Max task created by the primary Sol Advisor session.

**Goal:** Replace free-form shortcut text entry with a centered native recorder that
captures a complete keyboard chord, including Tab, Backspace, arrows, Escape,
function keys, and intentionally bare keys.

**Architecture:** Keep `Shortcut` and its existing Codable shape as the persistent
source of truth. Add one focused AppKit event-normalization and capture surface,
reuse that normalization from `ShortcutMonitor`, and keep SwiftUI `SettingsView` as
the owner of which row is recording and when preferences change.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSEvent` local monitors, Swift Testing,
Swift Package Manager, existing JSON preferences.

## Global Constraints

- Preserve the production `Shortcut`, `AppPreferences.shortcuts`,
  `Shortcut.defaults`, `Shortcut.conflicts(in:)`, and `ShortcutMonitor` flow.
- Preserve the persisted `key: String?` and `modifiers: [String]` JSON shape. Add no
  migration.
- A bare key is valid and must show the approved caution rather than being blocked.
- A modifier-only shortcut is not supported.
- Escape is recordable. Clicking elsewhere cancels without mutation.
- Capture and consume exactly one non-repeated, normalizable key-down event.
- Use one shared event normalizer for recording and runtime matching.
- Use only an application-local event monitor while a recorder is active. Add no
  global event tap, permission, dependency, or second shortcut store.
- Keep the recorder content centered and use native focus, semantic colors, and
  accessibility labels/values. Add no keyboard-action animation.
- Do not modify dictation shortcut behavior, `NotesPanel`, note data, the real
  `NSTextView`, tab dragging, accent colors, toolbar behavior, window sizing,
  unrelated Settings sections, generated files, or `Package.resolved`.
- Preserve unrelated and concurrent work. Do not reformat or clean adjacent code.
- Use only disposable QA notes to the right of the protected leftmost personal note.

## File Structure and Ownership

The Luna task owns only:

- `Sources/FleckCore/AppPreferences.swift` — allow intentionally bare shortcuts
  while retaining normalization, conflict, disabled, and Codable behavior.
- `Tests/FleckCoreTests/AppPreferencesTests.swift` — bare-key validity, conflict,
  and special-key round-trip coverage.
- `Sources/FleckApp/ShortcutRecorder.swift` — new focused file containing the
  normalized AppKit chord representation, shared event mapping/display mapping,
  scoped local-monitor bridge, and centered SwiftUI recorder control.
- `Sources/FleckApp/ShortcutMonitor.swift` — replace its private Tab-only mapper
  with the shared event normalizer and expose one internal pure matching seam.
- `Sources/FleckApp/SettingsView.swift` — replace the text field and modifier menu,
  own the single active recording row, update warning/help copy, and retain
  Remove/Restore/conflict behavior.
- `Tests/FleckAppTests/ShortcutRecorderTests.swift` — new focused AppKit behavior,
  lifecycle, runtime matching, display, and Settings contract tests.

Do not modify any other file unless the primary Sol session sends a corrected,
narrowly expanded ownership packet.

Before changing any file, record the exact implementation base with
`FLECK_SHORTCUT_BASE=$(git rev-parse HEAD)` in the retained task shell and include
that SHA in the structured handoff. Every accumulated implementation diff below is
against that recorded SHA.

---

### Task 1: Make bare shortcut chords valid without changing persistence

**Files:**

- Modify: `Sources/FleckCore/AppPreferences.swift`
- Modify: `Tests/FleckCoreTests/AppPreferencesTests.swift`

**Interfaces:**

- Consumes: `Shortcut.init(action:key:modifiers:)`, `Shortcut.isValid`,
  `Shortcut.conflicts(in:)`, and synthesized Codable conformance.
- Produces: the same `Shortcut` type and stored fields; `isValid` returns true for a
  nonempty key with zero or more recognized modifiers.

- [ ] **Step 1: Add the red bare-key and special-key persistence tests**

  Add focused Swift Testing cases with these exact behaviors:

  - `Shortcut(action: .nextNote, key: "tab", modifiers: [])` is valid.
  - `Shortcut(action: .closeNote, key: "backspace", modifiers: [])` is valid.
  - a disabled shortcut with `key == nil` and no modifiers remains valid;
  - a malformed shortcut with `key == nil` and a modifier remains invalid;
  - two bare `tab` chords conflict with one another;
  - bare `tab` does not conflict with Control-Tab;
  - encoding and decoding a shortcut whose key is `backspace` and modifiers are
    Command plus Shift preserves the exact normalized `Shortcut` value.

- [ ] **Step 2: Run the focused tests and capture red evidence**

  Run:

  ```bash
  swift test --disable-automatic-resolution --no-parallel \
    --filter 'shortcut|Shortcut'
  ```

  Expected before implementation: the bare-key validity assertions fail because
  current `isValid` requires at least one modifier. Existing normalization and
  conflict tests remain green.

- [ ] **Step 3: Make the minimum model change**

  Change only `Shortcut.isValid`:

  - if `key` is non-nil, validity depends only on that normalized key being
    nonempty;
  - if `key` is nil, validity still requires the modifier array to be empty.

  Do not change initializer normalization, modifier ordering, conflict signatures,
  defaults, stored fields, CodingKeys, or Codable behavior.

- [ ] **Step 4: Run the focused tests green**

  Run the same command from Step 2.

  Expected: all selected tests pass, including existing normalization and invalid
  disabled-state coverage.

- [ ] **Step 5: Commit the model slice**

  ```bash
  git add Sources/FleckCore/AppPreferences.swift \
    Tests/FleckCoreTests/AppPreferencesTests.swift
  git commit -m "feat: allow bare Fleck shortcuts"
  ```

---

### Task 2: Share truthful AppKit key normalization with runtime matching

**Files:**

- Create: `Sources/FleckApp/ShortcutRecorder.swift`
- Modify: `Sources/FleckApp/ShortcutMonitor.swift`
- Create: `Tests/FleckAppTests/ShortcutRecorderTests.swift`

**Interfaces:**

- Produces an internal `ShortcutChord: Equatable` with `key: String` and
  `modifiers: [String]`.
- Produces an internal `ShortcutEventNormalizer.chord(for: NSEvent) ->
  ShortcutChord?` used by both recorder and runtime.
- Produces an internal `ShortcutEventNormalizer.displayLabel(for: Shortcut?) ->
  String` for Settings presentation.
- Produces an internal `ShortcutMonitor.action(for:shortcuts:) -> Shortcut.Action?`
  pure seam; the existing coordinator calls it before invoking the action callback.

- [ ] **Step 1: Add red event-normalization and display tests**

  In the new test file, add one small synthetic `NSEvent.keyEvent` fixture factory
  that accepts key code, characters, characters ignoring modifiers, modifier flags,
  and repeat state.

  Test these exact mappings:

  | Physical event | Canonical key | Display |
  | --- | --- | --- |
  | key code 48 | `tab` | `⇥` |
  | key code 51 | `backspace` | `⌫` |
  | key code 117 | `forwarddelete` | `⌦` |
  | key code 53 | `escape` | `Esc` |
  | key code 36 | `return` | `Return` |
  | key code 76 | `enter` | `Enter` |
  | key code 49 | `space` | `Space` |
  | key codes 123, 124, 126, 125 | `left`, `right`, `up`, `down` | arrow glyphs |
  | key codes 115, 119, 116, 121 | `home`, `end`, `pageup`, `pagedown` | readable names |
  | key code 122 | `f1` | `F1` |
  | key code 90 | `f20` | `F20` |
  | ordinary `N`/`n` event | `n` | `N` |

  Also prove:

  - Command, Shift, Control, and Option flags produce modifiers in existing
    `Shortcut.Modifier.allCases` order;
  - Caps Lock, Numeric Pad, and Function flags are ignored as modifiers;
  - Shift-Tab remains canonical key `tab` plus modifier `shift`;
  - an unknown key code with empty `charactersIgnoringModifiers` returns nil;
  - a legacy unknown stored string displays uppercased instead of disappearing;
  - a nil shortcut displays `Not set`.

- [ ] **Step 2: Add red production matcher tests**

  Through the planned internal pure matching seam, assert:

  - a bare Backspace event selects an action configured with bare `backspace`;
  - Control-Tab matches the existing `nextNote` default;
  - Shift-Control-Tab matches `previousNote` regardless of NSEvent flag order;
  - a mismatched modifier set does not match;
  - either side of a duplicate chord conflict does not match;
  - an invalid or disabled shortcut does not match.

- [ ] **Step 3: Run the new test file and capture red evidence**

  Run:

  ```bash
  swift test --disable-automatic-resolution --no-parallel \
    --filter 'ShortcutRecorder|shortcutEvent|shortcutMonitor|ShortcutMonitor'
  ```

  Expected before implementation: compilation fails because the shared chord,
  normalizer, display, and pure matcher seams do not yet exist.

- [ ] **Step 4: Implement the shared normalizer minimally**

  In `ShortcutRecorder.swift`:

  - define the two internal types and signatures listed in Interfaces;
  - map the special physical key codes exactly as listed in Step 1;
  - map F1 through F20 using an explicit complete key-code table;
  - for all other keys, use trimmed, lowercased `charactersIgnoringModifiers` and
    return nil when it is absent or empty;
  - build modifier strings only from Command, Shift, Control, and Option, then pass
    them through `Shortcut.normalizedModifiers`;
  - format modifier symbols in canonical order as `⌘`, `⇧`, `⌃`, `⌥` followed by
    the display key;
  - retain a safe uppercase fallback for unknown legacy strings.

  Do not add Carbon, keyboard-layout translation, a key-code persistence field, or
  a second preferences type.

- [ ] **Step 5: Route `ShortcutMonitor` through the shared mapping**

  Replace its private `eventKey` and `eventModifiers` duplication with the planned
  internal pure `action(for:shortcuts:)` seam:

  - normalize the event to one `ShortcutChord`;
  - compute conflicts once;
  - select the first valid, nonconflicting shortcut whose key and normalized
    modifiers equal the chord;
  - keep the current local monitor installation, action callback, event
    consumption, and uninstall lifecycle unchanged.

- [ ] **Step 6: Run the focused event and runtime tests green**

  Run the command from Step 3 and the existing core shortcut tests.

  Expected: all mappings, display values, matcher behaviors, and legacy tests pass.

- [ ] **Step 7: Commit the shared event slice**

  ```bash
  git add Sources/FleckApp/ShortcutRecorder.swift \
    Sources/FleckApp/ShortcutMonitor.swift \
    Tests/FleckAppTests/ShortcutRecorderTests.swift
  git commit -m "feat: normalize native Fleck shortcut events"
  ```

---

### Task 3: Add the scoped recorder and replace free-form Settings entry

**Files:**

- Modify: `Sources/FleckApp/ShortcutRecorder.swift`
- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Tests/FleckAppTests/ShortcutRecorderTests.swift`

**Interfaces:**

- Produces a SwiftUI `ShortcutRecorder` initialized with action, current shortcut,
  active state, begin callback, chord callback, and cancel callback.
- Produces a narrow `NSViewRepresentable` capture surface whose coordinator owns
  one application-local monitor for key-down and mouse-down events.
- `SettingsView` owns `@State` for `Shortcut.Action?`, ensuring only one row records.
- Preference mutation continues through `AppState.updatePreferences` and constructs
  the existing `Shortcut(action:key:modifiers:)` value.

- [ ] **Step 1: Add red recorder lifecycle tests**

  Exercise the coordinator directly on `@MainActor` with real synthetic AppKit
  events. Prove:

  - activation installs one monitor and repeated activation does not install a
    duplicate;
  - a normalizable non-repeated key-down calls the capture callback exactly once,
    stops monitoring, and returns nil to consume the event;
  - a second event after completion is returned unchanged and cannot call back;
  - a repeated key-down is consumed without saving and leaves recording active;
  - an unsupported key-down is consumed without overwriting and leaves recording
    active;
  - left, right, or other mouse-down calls cancel once, removes the monitor, and
    returns the mouse event so the clicked control still works;
  - explicit stop is idempotent and clears the monitor;
  - dismantling the representable calls the same stop path.

  The coordinator may expose an internal read-only `isMonitoring` property solely
  as the observable lifecycle seam. Do not introduce a protocol or fake global
  event-monitor implementation.

- [ ] **Step 2: Add red Settings/UI contract tests**

  Add a focused source contract plus any practical hosted-view behavior assertion
  proving:

  - `SettingsView` no longer uses `TextField("Key"` or the separate modifier menu;
  - it holds one optional active shortcut action;
  - each row uses `ShortcutRecorder` and records the complete returned chord;
  - the value label uses a centered frame with a minimum width sufficient for
    `Press shortcut…` rather than a trailing-aligned editable field;
  - the accessible label includes the action title and the accessible value changes
    to `Press shortcut` while active;
  - the exact bare-key caution copy from the design is present only for enabled
    shortcuts whose modifier list is empty;
  - the footer instructs the user to click a shortcut and press the complete chord;
  - Remove, Restore, and the existing conflict warning remain;
  - there is no animation attached to recording state.

- [ ] **Step 3: Run the recorder tests and capture red evidence**

  Run:

  ```bash
  swift test --disable-automatic-resolution --no-parallel \
    --filter 'ShortcutRecorder|shortcutRecorder|shortcutSettings|ShortcutSettings'
  ```

  Expected before implementation: lifecycle and Settings assertions fail because
  only the shared mapping exists and Settings still uses the text field/menu.

- [ ] **Step 4: Implement the narrow local-monitor bridge**

  In `ShortcutRecorder.swift`:

  - install the monitor only while active, covering `.keyDown`, `.leftMouseDown`,
    `.rightMouseDown`, and `.otherMouseDown`;
  - on mouse-down, stop, call cancel once, and return the original event;
  - on a repeated or unsupported key-down, consume it and remain active;
  - on a valid key-down, stop before invoking capture, invoke capture once, and
    return nil;
  - make start and stop idempotent;
  - update callbacks when SwiftUI updates the representable;
  - stop from `dismantleNSView` and coordinator deinitialization;
  - keep the AppKit view zero-sized and keep all long-lived ownership in its
    coordinator.

- [ ] **Step 5: Implement the centered SwiftUI recorder**

  Build one bordered button with:

  - current shared display label while idle;
  - `Press shortcut…` while active;
  - a centered label frame with a minimum width of 112 points so the prompt does
    not shift or truncate under normal text size;
  - native button focus styling and no custom animation;
  - accessible label formed as `Record shortcut for ` plus the action's title;
  - accessible value equal to `Press shortcut` while active and the displayed
    chord while idle;
  - the capture representable attached only to the active control.

  Do not imitate a text field, draw a custom caret, or manually paint a focus ring.

- [ ] **Step 6: Integrate the recorder into Settings**

  In `SettingsView`:

  - add one optional active-action `@State` property;
  - replace both the key text field and modifier menu with `ShortcutRecorder`;
  - beginning a row assigns that action and therefore cancels any prior row;
  - capture replaces the action's complete `Shortcut` key and modifiers through
    `AppState.updatePreferences`, then clears active state;
  - cancel clears active state without preference mutation;
  - Remove/Restore first clears active state and then performs the existing action;
  - delete the obsolete key binding, modifier binding, and local label formatter;
  - add the approved bare-key caution and updated instructional footer;
  - preserve the exact existing conflict label and action ordering.

- [ ] **Step 7: Run focused Settings and shortcut tests green**

  Run:

  ```bash
  swift test --disable-automatic-resolution --no-parallel \
    --filter 'ShortcutRecorder|shortcut|Shortcut|Settings'
  ```

  Expected: the new lifecycle, Settings, mapping, persistence, matching, and existing
  shortcut tests all pass.

- [ ] **Step 8: Commit the recorder UI slice**

  ```bash
  git add Sources/FleckApp/ShortcutRecorder.swift \
    Sources/FleckApp/SettingsView.swift \
    Tests/FleckAppTests/ShortcutRecorderTests.swift
  git commit -m "feat: record complete Fleck shortcut chords"
  ```

---

### Task 4: Verify the integrated source, package, and exact app bundle

**Files:**

- Inspect only: every owned file above, the accumulated diff from the recorded
  `$FLECK_SHORTCUT_BASE`,
  `Package.resolved`, and `.build/Fleck.app`.

- [ ] **Step 1: Inspect scope and complete diff**

  Run:

  ```bash
  git status --short --branch
  git diff --check
  git diff --stat "$FLECK_SHORTCUT_BASE"..HEAD
  git diff "$FLECK_SHORTCUT_BASE"..HEAD -- Sources/FleckCore/AppPreferences.swift \
    Sources/FleckApp/ShortcutRecorder.swift \
    Sources/FleckApp/ShortcutMonitor.swift \
    Sources/FleckApp/SettingsView.swift \
    Tests/FleckCoreTests/AppPreferencesTests.swift \
    Tests/FleckAppTests/ShortcutRecorderTests.swift
  git diff "$FLECK_SHORTCUT_BASE"..HEAD -- Package.resolved
  git ls-files -u
  git rev-parse -q --verify MERGE_HEAD
  ```

  Expected: only owned files changed after the plan base; `Package.resolved` diff,
  unmerged output, and `MERGE_HEAD` are empty; `git diff --check` passes.

- [ ] **Step 2: Run the complete focused regression set**

  Run:

  ```bash
  swift test --disable-automatic-resolution --no-parallel \
    --filter 'ShortcutRecorder|shortcut|Shortcut|AppPreferences|Settings'
  ```

  Expected: all selected tests pass with zero failures. Report the exact count.

- [ ] **Step 3: Run the deterministic full suite**

  Run:

  ```bash
  swift test --disable-automatic-resolution --no-parallel --quiet
  ```

  Expected: all 673 existing tests plus the new shortcut regressions pass across all
  suites. Report the resulting exact counts.

- [ ] **Step 4: Confirm dependency-lock integrity**

  Record the SHA-256 of `Package.resolved` before validation. Run validation only
  once after all focused/full checks are green:

  ```bash
  shasum -a 256 Package.resolved
  Scripts/validate-macos.sh
  shasum -a 256 Package.resolved
  ```

  Expected: validation exits 0 through tests, Fleck and fleck-agent release builds,
  signed app packaging, size/privacy/candidate audits, bounded smoke, lock restore,
  and candidate rejection. The lock hashes are identical. Retain the process and
  final exit status; do not repeat validation merely to recover output.

- [ ] **Step 5: Build and test the exact packaged app**

  Build with `Scripts/build-fleck-app.sh`, terminate only a process whose resolved
  executable is the exact repository `.build/Fleck.app/Contents/MacOS/Fleck`, then
  launch that bundle.

  In Settings and disposable QA tabs only:

  1. Confirm all five idle recorder labels and `Press shortcut…` are centered.
  2. Record Command-Backspace for a safe action and prove the action fires once.
  3. Record bare Tab for next-note, verify the caution, and prove Tab changes between
     QA tabs instead of editing the protected note.
  4. Record Escape, an arrow, Return, and one function key where available.
  5. Click outside during recording and confirm the prior chord is unchanged.
  6. Begin one row then another and confirm only the latter records.
  7. Create a duplicate, confirm both are marked conflicting and neither fires,
     then Restore the affected defaults.
  8. Quit/relaunch and confirm a deliberately retained QA chord persists.
  9. Check keyboard focus and accessibility labels/values; inspect Light and Dark
     appearance; confirm no new Input Monitoring prompt.
  10. Restore all shortcut defaults and remove disposable QA notes recoverably.

  Never edit or activate an action that mutates the protected leftmost personal
  note. Report any unavailable VoiceOver, keyboard, or appearance boundary rather
  than claiming it passed.

- [ ] **Step 6: Return the structured Luna handoff**

  Return exact task identity, worktree path, base and branch, file-by-file changes,
  red/green commands and counts, full suite result, validation exit and lock hashes,
  packaged observations, commit SHAs, `git status`, judgment calls, and remaining
  gaps. Do not push, open/update a PR, merge, or modify GitHub.

## Sol Advisor Acceptance Boundary

The primary GPT-5.6 Sol / High session will inspect every changed line in the Luna
worktree, independently rerun focused tests, the deterministic full suite,
integrity checks, one final validation only when needed, and the exact packaged-app
QA. It will then run the Sol Advisor exactness check and obtain a fresh
`sol_advisor_sol_reviewer` verdict on GPT-5.6 Sol / High. Any correction returns to
the same Luna task and invalidates the prior verdict. The feature is not complete
unless the fresh verdict is exactly `ship`.

After `ship`, green GitHub CI, and resolution of any remaining PR review gates, the
primary may push the focused commits and update PR #7 under the user's existing
authorization. Do not merge PR #7 until its broader physical tab-drag gate and all
GitHub branch-protection requirements are independently clear.
