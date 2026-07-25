# Crisp Native Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make state changes feel immediate and polished with restrained macOS-style motion while keeping typing and editor rendering untouched.

**Architecture:** Keep shared timing and Reduce Motion decisions in one small app-only `AppMotion` value. Apply declarative SwiftUI transitions directly to the existing panel, toolbar, Trash, and Settings views; expose save progress from `AppState` so feedback reflects real persistence rather than a timer pretending a save completed.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, macOS 14

## Global Constraints

- Use 100 ms for pressed and formatting-state feedback and 160 ms for structural transitions.
- Use ease-out curves with no bounce.
- Animate only opacity, offset, and scale.
- Never animate keystrokes, editor contents, or panel resizing.
- When Reduce Motion is enabled, remove movement and scaling and retain only brief opacity or color feedback.
- Add no dependencies.

---

### Task 1: Motion Tokens and Save Feedback

**Files:**
- Create: `Sources/MenuBarNotesApp/AppMotion.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Modify: `Package.swift`
- Create: `Tests/MenuBarNotesAppTests/AppMotionTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AppStateTests.swift`

**Interfaces:**
- Produces: `AppMotion.init(reduceMotion:)`, `AppMotion.quick`, `AppMotion.standard`, `AppMotion.pressScale`, and `AppMotion.offset`.
- Produces: `AppState.SaveStatus` with `.idle`, `.saving`, and `.saved`, plus read-only `AppState.saveStatus`.

- [ ] **Step 1: Add the app test target and write failing motion-policy tests**

```swift
@Test func reduceMotionRemovesMovementAndPressScaling() {
  let motion = AppMotion(reduceMotion: true)
  #expect(motion.pressScale == 1)
  #expect(motion.offset == 0)
}

@Test func standardMotionUsesRestrainedNativeValues() {
  let motion = AppMotion(reduceMotion: false)
  #expect(motion.pressScale == 0.97)
  #expect(motion.offset == 4)
}
```

Run: `swift test --filter AppMotionTests`

Expected: FAIL because `MenuBarNotesAppTests` and `AppMotion` do not exist.

- [ ] **Step 2: Add the minimal motion policy**

```swift
struct AppMotion {
  let reduceMotion: Bool
  var quick: Animation? { reduceMotion ? nil : .easeOut(duration: 0.10) }
  var standard: Animation? { reduceMotion ? nil : .easeOut(duration: 0.16) }
  var pressScale: CGFloat { reduceMotion ? 1 : 0.97 }
  var offset: CGFloat { reduceMotion ? 0 : 4 }
}
```

Run: `swift test --filter AppMotionTests`

Expected: PASS.

- [ ] **Step 3: Write a failing save-status test**

```swift
@Test @MainActor func editingReportsSavingThenSaved() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root))

  state.updateSelected(title: "Changed")
  #expect(state.saveStatus == .saving)
  try await Task.sleep(for: .milliseconds(500))
  #expect(state.saveStatus == .saved)
}
```

Run: `swift test --filter editingReportsSavingThenSaved`

Expected: FAIL because `AppState.saveStatus` does not exist.

- [ ] **Step 4: Publish honest save status from the existing save path**

Add `SaveStatus`, `saveStatus`, and a cancellable feedback-reset task. Mark a scheduled or immediate save as `.saving`, a successful write as `.saved`, then reset to `.idle` after 1.2 seconds. On failure, cancel feedback and return to `.idle` while preserving the existing `saveError`.

Run: `swift test --filter editingReportsSavingThenSaved`

Expected: PASS.

---

### Task 2: Notes Panel and Toolbar Motion

**Files:**
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Test: `Tests/MenuBarNotesAppTests/AppMotionTests.swift`

**Interfaces:**
- Consumes: `AppMotion` and `AppState.saveStatus` from Task 1.
- Produces: no reusable API; all transitions remain private to the panel.

- [ ] **Step 1: Add a failing source-level behavior check**

Extend the motion-policy test to assert that normal motion uses the approved four-point offset and 0.97 pressed scale. This test is already red until Task 1 supplies the policy and prevents future accessibility regressions.

Run: `swift test --filter AppMotionTests`

Expected: PASS only with the approved motion policy.

- [ ] **Step 2: Add panel motion without touching the editor**

In `NotesPanel`:

- Read `accessibilityReduceMotion` and construct `AppMotion`.
- Add a matched-geometry capsule for the selected tab and animate its position with `motion.standard`.
- Give tab insertion/removal an opacity plus four-point horizontal transition.
- Add a compact fixed-width save-feedback view in the header that crossfades “Saving…” into a checkmark.
- Transition the delete-confirmation overlay with opacity plus a 0.985 scale using `motion.standard`.
- Do not attach an animation modifier to `NativeRichTextEditor` or its bindings.

Run: `swift build`

Expected: Build succeeds without warnings.

- [ ] **Step 3: Add pressed and active formatting feedback**

Add a private `CrispToolbarButtonStyle` that scales to `motion.pressScale` only while physically pressed. Animate `ToolbarIconLabel.isActive` with `motion.quick`; keyboard formatting remains immediate because it does not drive the pressed state.

Run: `swift test && swift build`

Expected: All tests pass and the app builds.

---

### Task 3: Trash and Settings Continuity

**Files:**
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Modify: `Sources/MenuBarNotesApp/TrashView.swift`
- Modify: `Sources/MenuBarNotesApp/SettingsView.swift`
- Modify: `Tests/MenuBarNotesAppTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `AppMotion`.
- Produces: optimistic Trash row removal backed by the existing local restore operation.

- [ ] **Step 1: Write a failing optimistic-restore test**

Create a trashed note in `LocalStore`, refresh `AppState.trashedNotes`, call `restore`, and assert synchronously that the restored note is selected and no longer appears in `trashedNotes`.

Run: `swift test --filter restoringRemovesTrashRowImmediately`

Expected: FAIL because the current row remains until disk restoration finishes.

- [ ] **Step 2: Remove restored Trash rows optimistically**

In `AppState.restore`, remove the matching `TrashedNote` from published state before starting the existing storage task. If storage fails, reload Trash from disk before exposing the error.

Run: `swift test --filter restoringRemovesTrashRowImmediately`

Expected: PASS.

- [ ] **Step 3: Animate Trash and Settings view changes**

In `TrashView`, animate list identity changes with `motion.standard` and use an opacity plus four-point horizontal transition. In `SettingsView`, crossfade the three existing section forms with `motion.standard`; do not animate preference controls or panel dimensions.

Run: `swift test && swift build`

Expected: All tests pass and the app builds.

---

### Task 4: Full Verification

**Files:**
- Modify only files already listed if verification exposes a scoped defect.

**Interfaces:**
- Consumes: completed Tasks 1–3.
- Produces: verified release-ready motion behavior.

- [ ] **Step 1: Run automated validation**

Run: `swift test`

Expected: All tests pass.

Run: `bash Scripts/validate-macos.sh`

Expected: Debug and release builds succeed, tests pass, and the release-size check passes.

Run: `git diff --check`

Expected: No whitespace errors.

- [ ] **Step 2: Run the app and inspect both accessibility modes**

Launch the debug app, then verify:

- Tab selection moves only the capsule and never delays the editor.
- B/I/U state changes crossfade and pointer presses scale subtly.
- Delete confirmation appears and disappears without flicker.
- Confirm removes the note immediately and the save indicator reflects the real write.
- Restore removes the Trash row immediately.
- Settings sections crossfade without animating panel dimensions.
- Reduce Motion removes all offset and scale effects.

- [ ] **Step 3: Review the final diff**

Run: `git diff -- Sources/MenuBarNotesApp Package.swift Tests/MenuBarNotesAppTests docs/superpowers/plans/2026-07-25-crisp-native-motion.md`

Expected: Every changed production line maps directly to the approved motion specification.
