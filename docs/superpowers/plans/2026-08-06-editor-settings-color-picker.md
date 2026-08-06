# Fleck Editor Settings and Shared Color Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Follow this plan task-by-task with strict red-green TDD. Implementation is owned by the dispatched Luna / Max task; the primary Sol task owns architecture, verification, and final review.

**Goal:** Remove duplicate typography/toolbar settings and provide one accessible Fleck color-picker popover for every existing color context.

**Architecture:** Add one shared SwiftUI color-picker module that owns palette presentation and temporary HSB/hex draft state while existing callers retain durable state and commit through `AppState` or `EditorCommands`. Keep all existing Codable fields and persistence seams; only settings and picker presentation change.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSColor` conversion, Swift Testing, native macOS popovers, existing `AppState`, `EditorCommands`, and RTF persistence.

## Global Constraints

- Target macOS 14 or later and compile with the repository's current Xcode toolchain.
- Add no package dependency and do not change `Package.resolved`.
- Do not invoke SwiftUI `ColorPicker`, `NSColorPanel`, or another detached system color window.
- Preserve every `AppPreferences` Codable field and default, including `fontFamily`, `fontSize`, and `showFormattingBar`.
- Preserve editor selection, typing attributes, RTF, undo, tab identity, and existing save paths.
- Never alter the protected leftmost personal tab during packaged QA.
- Do not push, open a PR, or modify unrelated/concurrent work.

---

### Task 1: Shared color model, palette, and picker

**Files:**
- Create: `Sources/FleckApp/FleckColorPicker.swift`
- Create: `Tests/FleckAppTests/FleckColorPickerTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/NativeRichTextEditor.swift`

**Interfaces:**
- Produce a shared palette option type replacing the tab-specific
  `TabColorOption` name while retaining the exact eight existing colors.
- Produce normalized sRGB `#RRGGBB` conversion shared by `Color`, `NSColor`,
  palette matching, and picker draft state.
- Produce a `FleckColorDraft`-style value interface that can initialize from an
  optional hex value, edit Hue/Saturation/Brightness, validate typed hex, and
  return one uppercase committed hex string.
- Produce a reusable `FleckColorPicker` SwiftUI view consuming current color,
  reset title/availability, and commit/cancel callbacks.

- [ ] **Step 1: Add failing model and source-contract tests**

  Cover all palette values, case-insensitive valid hex normalization, invalid and
  alpha hex rejection, black/white/saturated HSB round trips, palette-name matching,
  and the absence of opacity/recent-color state.

- [ ] **Step 2: Run the focused tests and record the expected failures**

  Run:

  ```sh
  swift test --disable-automatic-resolution --no-parallel --filter FleckColorPickerTests
  ```

  Expected: fail because the shared types and picker do not yet exist.

- [ ] **Step 3: Implement the minimum shared model and palette**

  Move the existing palette and color conversion behavior rather than duplicating
  it. Normalize all successful conversions to uppercase six-digit sRGB hex. Reject
  malformed input without choosing a fallback color.

- [ ] **Step 4: Implement the picker popover content**

  Use native SwiftUI buttons, text input, and keyboard-adjustable Hue, Saturation,
  and Brightness controls. Palette/reset actions call the commit callback
  immediately. Custom controls mutate only local draft state; Apply emits one
  normalized value and Cancel emits no mutation.

- [ ] **Step 5: Rerun focused tests**

  Expected: the new model/picker tests pass with no warning or unexpected output.

### Task 2: Simplify Settings and use the shared picker

**Files:**
- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Tests/FleckAppTests/FleckColorPickerTests.swift`
- Modify: `Tests/FleckCoreTests/AppPreferencesTests.swift` only if compatibility
  coverage needs an explicit assertion; do not change production preference fields.

**Interfaces:**
- Consume `FleckColorPicker` for required accent and optional editor text/background
  preferences.
- Continue writes through `AppState.updatePreferences`.
- Preserve existing `AppPreferences` decoding and defaults.

- [ ] **Step 1: Add failing Settings source and compatibility tests**

  Assert that Settings contains no Font picker, Font Size stepper, `Show formatting
  bar` toggle, or production `ColorPicker`. Assert that saved typography and toolbar
  visibility still round-trip through `AppPreferences`.

- [ ] **Step 2: Run the focused tests and confirm they fail for current UI**

  Run the new Settings-focused tests plus `AppPreferencesTests`.

- [ ] **Step 3: Remove only the duplicate Settings controls**

  Delete the visible font-family picker, font-size stepper, and toolbar-visibility
  toggle. Do not delete bindings, Codable fields, defaults, migration logic, or
  editor consumers required for compatibility.

- [ ] **Step 4: Replace Appearance color controls**

  Use compact labeled swatch triggers and the shared popover for accent, editor text,
  and editor background. Put `Use System` inside the optional-color picker contexts
  and remove the adjacent reset buttons and obsolete `Binding<Color>` helpers.

- [ ] **Step 5: Rerun Settings and preference tests**

  Expected: all focused tests pass and old preference fixtures decode unchanged.

### Task 3: Integrate editor formatting and tab colors

**Files:**
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Modify: `Tests/FleckAppTests/FleckColorPickerTests.swift`
- Modify: `Tests/FleckAppTests/TabDragReorderTests.swift` only if its source contracts
  directly reference the old tab palette surface.

**Interfaces:**
- Font color commits call `EditorCommands.applyForegroundColor(_:)`.
- Highlight commits call `EditorCommands.applyBackgroundColor(_:)`.
- Tab commits select the intended live note and call the existing
  `AppState.setSelectedTabColor(_:)` mutation path.
- Toolbar show/hide continues to mutate only `showFormattingBar` through the header.

- [ ] **Step 1: Add failing integration tests**

  Cover shared picker use for font/highlight/tab color; arbitrary custom font and
  highlight colors; context-specific `Automatic`, `No Highlight`, and `None` reset
  behavior; stale tab no-op behavior; and user-facing `Editor toolbar` copy.

- [ ] **Step 2: Run focused AppKit, tab, and picker tests and confirm failures**

  Expected: failures point to the old fixed menus, old naming, and missing shared
  picker presentation.

- [ ] **Step 3: Replace toolbar color menus**

  Keep the existing toolbar positions, live command-state accessibility values, and
  `EditorCommands` mutation methods. Mixed selections remain mixed until a commit.

- [ ] **Step 4: Replace the tab nested palette**

  Change the context-menu action to `Tab Color...`, then present the shared popover
  anchored to that exact tab. Revalidate the note identity before selecting and
  committing so a removed/stale note is a no-op.

- [ ] **Step 5: Rename toolbar presentation copy**

  Change the header help/accessibility labels and toolbar container label to
  `Editor toolbar`. Do not reconstruct or re-identify the real editor when toggled.

- [ ] **Step 6: Rerun focused tests**

  Expected: picker, AppKit editor, and tab suites pass.

### Task 4: Full verification and packaged evidence

**Files:**
- Modify documentation only if verified behavior requires an exact checklist update.
- Do not change unrelated product surfaces to satisfy broad checks.

- [ ] **Step 1: Run the complete locked test suite**

  ```sh
  swift test --disable-automatic-resolution --no-parallel --quiet
  ```

  Expected: exit 0 with exact test/suite counts reported.

- [ ] **Step 2: Run packaged macOS validation**

  ```sh
  Scripts/validate-macos.sh
  ```

  Expected: exit 0, valid development-signed `.build/Fleck.app`, passing launch
  smoke test, size checks, and complete tests.

- [ ] **Step 3: Run repository integrity checks**

  ```sh
  git diff --check
  git diff --exit-code -- Package.resolved
  git status --short --branch
  ```

  Expected: no whitespace errors, no resolver change, and only owned files changed.

- [ ] **Step 4: Record packaged-app QA boundaries**

  Exercise a disposable tab to the right of the protected leftmost tab if UI control
  permission is available. Verify six picker contexts, Apply/Cancel, invalid hex,
  toolbar show/hide, relaunch persistence, and no system color panel. If live control
  is unavailable, report that boundary explicitly rather than inferring success from
  builds or source tests.

- [ ] **Step 5: Commit the focused implementation**

  Commit only owned files with an intentional message. Do not push or open a PR.

## Plan Self-Review

- Every acceptance criterion in the approved specification maps to Tasks 1-4.
- No persistence migration, alpha/recent-color feature, dependency, or unrelated
  refactor is included.
- The shared picker owns presentation/draft state only; durable mutations stay in
  existing `AppState` and `EditorCommands` seams.
- Focused tests establish red-green evidence before production changes, followed by
  the complete packaged validation gate.
