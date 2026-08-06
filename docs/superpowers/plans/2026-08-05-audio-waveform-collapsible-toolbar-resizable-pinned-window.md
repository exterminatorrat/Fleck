# Fleck Responsive Dictation and Editor Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans`, `test-driven-development`, and `ponytail` to implement this plan task-by-task. Implementation must run only through the Sol Advisor `sol_advisor_terra_implementer` lane.

**Goal:** Make Fleck's listening waveform reflect real microphone amplitude, add an editor-header control that collapses the formatting bar, widen the menu panel to a migrated 640-point default, and make only the pinned window natively resizable with independent persistent dimensions.

**Architecture:** Preserve the existing `SpeechEngine -> DictationRuntime -> DictationCapsuleController -> DictationWaveformModel` level path and change only the waveform display mapping. Keep `NotesPanel`, `FormattingBar`, `EditorCommands`, `NativeRichTextEditor`, and `AppPreferences` as their current sources of truth. Extend the existing pinned-window `NSViewRepresentable` narrowly to observe completed-window live resize endings; do not create a second window system or a custom menu-popover resize gesture.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFAudio scalar RMS input, Swift Testing, Swift Package Manager, existing JSON preference snapshots.

## Global Constraints

- Preserve Fleck's current architecture and all existing editor, dictation, persistence, privacy, menu-bar, and onboarding interfaces.
- Use native SwiftUI/AppKit behavior and existing persistence. Add no dependency.
- Do not group, remove, reorder, or redesign formatting commands.
- Do not make the menu-bar popover user-resizable.
- Pinned-window resizing must never mutate the menu panel's `panelWidth` or `panelHeight`.
- Silence must be represented honestly: no time-driven bar motion when displayed microphone energy is zero.
- Audio callbacks remain scalar levels only; do not retain buffers or log audio levels.
- Preserve note content, RTF sidecars, selection, focus, typing attributes, undo/redo, and agent/dictation insertion.
- Preserve the onboarding window's 1080-by-700 default and 760-by-520 minimum.
- Preserve unrelated user and concurrent edits; do not reformat or clean adjacent code.
- Use designated Fleck QA notes for packaged validation; do not edit the leftmost personal note.

## File Structure and Ownership

The implementation lane may modify only:

- `Sources/FleckApp/DictationWaveform.swift` — scalar energy smoothing, stale-level decay, and static-silence eleven-bar mapping.
- `Tests/FleckAppTests/DictationWaveformTests.swift` — waveform red/green regression coverage.
- `Sources/FleckCore/AppPreferences.swift` — menu sizing migration marker plus independent pinned dimensions.
- `Tests/FleckCoreTests/AppPreferencesTests.swift` — backward-compatible sizing and clamping coverage.
- `Sources/FleckApp/OnboardingWindowPresenter.swift` — completed pinned-window container sizing, native resize observation, clamped presentation, and persistence callback.
- `Tests/FleckAppTests/OnboardingSourceAuditTests.swift` — pinned/menu/onboarding source contracts.
- `Sources/FleckApp/NotesPanel.swift` — accessible formatting-bar header toggle and existing visibility transition.
- `Tests/FleckAppTests/AppKitEditorTests.swift` — toolbar-collapse source contract and editor-state preservation coverage where the existing seam permits it.
- `Sources/FleckApp/SettingsView.swift` — rename the existing width/height labels to `Menu width` and `Menu height` without changing their controls or ranges.

Do not create a new source file. `OnboardingWindowPresenter.Coordinator` owns the narrow notification lifecycle. Do not modify `NativeRichTextEditor.swift`, audio capture engines, `DictationCoordinator.swift`, storage schemas, package dependencies, generated files, signing, packaging, or website files.

---

### Task 1: Make the waveform truthful to real microphone energy

**Files:**
- Modify: `Sources/FleckApp/DictationWaveform.swift`
- Test: `Tests/FleckAppTests/DictationWaveformTests.swift`

**Interfaces:**
- Consumes: `DictationWaveformModel.receive(level:now:)`, normalized RMS values in `0...1`, and `barLevels(at:reduceMotion:)`.
- Produces: the same `[CGFloat]` eleven-bar API; no caller signature changes.

- [ ] **Step 1: Replace the moving-silence test with red-capable truthfulness tests**

Add tests that use fixed dates and separate models so smoothing cannot obscure ordering:

```swift
@Test @MainActor func waveformIsStaticAtMinimumDuringSilence() {
  let model = DictationWaveformModel()
  model.beginListening(at: Date(timeIntervalSince1970: 10))

  let first = model.barLevels(at: Date(timeIntervalSince1970: 10.1), reduceMotion: false)
  let second = model.barLevels(at: Date(timeIntervalSince1970: 10.3), reduceMotion: false)
  let reduced = model.barLevels(at: Date(timeIntervalSince1970: 10.3), reduceMotion: true)

  #expect(first == second)
  #expect(second == reduced)
  #expect(Set(first).count == 1)
  #expect(first.allSatisfy { $0 == 0.05 })
}

@Test @MainActor func waveformAmplitudeIncreasesWithRealInputLevel() {
  let start = Date(timeIntervalSince1970: 30)
  func peak(for level: Float) -> CGFloat {
    let model = DictationWaveformModel()
    model.beginListening(at: start)
    model.receive(level: level, now: start.addingTimeInterval(0.04))
    return model.barLevels(at: start.addingTimeInterval(0.05), reduceMotion: false).max()!
  }

  let quiet = peak(for: 0.01)
  let soft = peak(for: 0.05)
  let loud = peak(for: 0.20)
  #expect(quiet == 0.05)
  #expect(soft > quiet)
  #expect(loud > soft)
}

@Test @MainActor func waveformDecaysToRestWhenLevelsStopArriving() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 40)
  model.beginListening(at: start)
  model.receive(level: 0.20, now: start.addingTimeInterval(0.04))

  let active = model.barLevels(at: start.addingTimeInterval(0.05), reduceMotion: false)
  let stale = model.barLevels(at: start.addingTimeInterval(0.60), reduceMotion: false)
  #expect(active.max()! > 0.05)
  #expect(stale.allSatisfy { $0 == 0.05 })
}
```

Retain and adapt the existing clamping, eleven-bar, throttling, reset, center-weight, and elapsed-time assertions.

- [ ] **Step 2: Run the waveform tests and prove the old behavior is red**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'waveform'
```

Expected: `waveformIsStaticAtMinimumDuringSilence` fails because the old baseline changes with time; the amplitude and stale-level assertions expose any remaining fabricated or frozen motion.

- [ ] **Step 3: Implement the minimum truthful mapping**

In `DictationWaveformModel`:

- retain the existing `0.015` noise floor, `0.24` normalization range, 30 Hz input throttle, and fast-attack/slow-release smoothing;
- add a bounded stale-level display decay using `lastAcceptedLevelAt` so visual energy reaches zero when callbacks stop;
- make `barLevels` use a constant `0.05` minimum and center-weighted displayed energy only;
- do not use elapsed time, sine waves, random values, or Reduce Motion to generate bar amplitude.

The resulting calculation should have this shape:

```swift
private func displayedEnergy(at date: Date) -> CGFloat {
  guard let lastAcceptedLevelAt else { return 0 }
  let staleInterval = max(date.timeIntervalSince(lastAcceptedLevelAt) - 0.12, 0)
  let staleScale = max(1 - CGFloat(staleInterval / 0.30), 0)
  return energy * staleScale
}

func barLevels(at date: Date, reduceMotion _: Bool) -> [CGFloat] {
  let displayedEnergy = displayedEnergy(at: date)
  return (0..<11).map { index in
    let distance = abs(CGFloat(index) - 5) / 5
    let centerWeight = 1 - (distance * 0.58)
    return min(max(0.05 + displayedEnergy * centerWeight * 0.95, 0.05), 1)
  }
}
```

If the exact stale timings need adjustment to satisfy the existing 30 Hz cadence, keep total return-to-rest under 0.5 seconds and record the chosen constants in the implementation report.

- [ ] **Step 4: Run focused waveform and runtime forwarding tests**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'waveform|DictationRuntimeForwardsLevelsOnlyToAnActiveVisibleCapsule'
```

Expected: all selected tests pass; quiet timestamps are identical, soft/loud peaks are ordered, stale input returns to rest, and inactive/hidden sessions remain unable to animate the capsule.

- [ ] **Step 5: Commit the waveform unit**

```bash
git add Sources/FleckApp/DictationWaveform.swift Tests/FleckAppTests/DictationWaveformTests.swift
git commit -m "fix: make dictation waveform follow speech"
```

---

### Task 2: Add backward-compatible independent sizing preferences

**Files:**
- Modify: `Sources/FleckCore/AppPreferences.swift`
- Test: `Tests/FleckCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Consumes: existing Codable `AppPreferences`, `panelWidth`, and `panelHeight`.
- Produces: `AppPreferences.currentPanelSizingVersion`, `panelSizingVersion`, `pinnedPanelWidth`, and `pinnedPanelHeight`; existing menu fields remain source-compatible.

- [ ] **Step 1: Write red preference migration and independence tests**

Cover these exact cases:

```swift
@Test func newPreferencesUseBalancedIndependentPanelDefaults() {
  let value = AppPreferences()
  #expect(value.panelWidth == 640)
  #expect(value.panelHeight == 430)
  #expect(value.pinnedPanelWidth == 640)
  #expect(value.pinnedPanelHeight == 430)
  #expect(value.panelSizingVersion == AppPreferences.currentPanelSizingVersion)
}

@Test func untouchedLegacyPanelSizeMigratesOnce() throws {
  let legacy = Data(#"{"panelWidth":520,"panelHeight":430}"#.utf8)
  let migrated = try JSONDecoder().decode(AppPreferences.self, from: legacy)
  #expect(migrated.panelWidth == 640)
  #expect(migrated.panelHeight == 430)
  #expect(migrated.pinnedPanelWidth == 640)
  #expect(migrated.pinnedPanelHeight == 430)
}

@Test func customLegacyPanelSizeIsPreservedAndSeedsPinnedSize() throws {
  let legacy = Data(#"{"panelWidth":700,"panelHeight":500}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: legacy)
  #expect(value.panelWidth == 700)
  #expect(value.panelHeight == 500)
  #expect(value.pinnedPanelWidth == 700)
  #expect(value.pinnedPanelHeight == 500)
}

@Test func explicitLegacyWidthAfterSizingMigrationRoundTrips() throws {
  let value = AppPreferences(panelWidth: 520, panelHeight: 430)
  let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(value))
  #expect(decoded.panelWidth == 520)
  #expect(decoded.panelHeight == 430)
}

@Test func pinnedAndMenuPanelSizesRoundTripIndependently() throws {
  let value = AppPreferences(
    panelWidth: 640,
    panelHeight: 430,
    pinnedPanelWidth: 760,
    pinnedPanelHeight: 540
  )
  let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(value))
  #expect(decoded.panelWidth == 640)
  #expect(decoded.panelHeight == 430)
  #expect(decoded.pinnedPanelWidth == 760)
  #expect(decoded.pinnedPanelHeight == 540)
}
```

Add this direct-initializer clamp fixture; do not add an arbitrary fixed maximum to pinned dimensions in `FleckCore`:

```swift
@Test func panelDimensionsClampToTheirSupportedMinimumsAndMenuMaximums() {
  let value = AppPreferences(
    panelWidth: 12,
    panelHeight: 9_000,
    pinnedPanelWidth: 1,
    pinnedPanelHeight: 2
  )
  #expect(value.panelWidth == 380)
  #expect(value.panelHeight == 800)
  #expect(value.pinnedPanelWidth == 480)
  #expect(value.pinnedPanelHeight == 320)
}
```

- [ ] **Step 2: Run the preference tests and prove missing fields/defaults are red**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'Preferences|PanelSize|panelSize'
```

Expected: new default, migration, and independent-pinned assertions fail before implementation while existing older-document decoding remains green.

- [ ] **Step 3: Extend `AppPreferences` minimally**

Add:

```swift
public static let currentPanelSizingVersion = 1
public var panelSizingVersion: Int
public var pinnedPanelWidth: Double
public var pinnedPanelHeight: Double
```

Extend the initializer with current-version defaults and add all three keys to `CodingKeys`. During decode:

1. Read old menu dimensions with legacy fallbacks `520` and `430`.
2. If `panelSizingVersion` is absent and both dimensions exactly equal `520` and `430`, resolve the menu size to `640` by `430`.
3. Otherwise preserve the custom legacy dimensions after range validation.
4. If pinned dimensions are absent, seed them from the resolved menu dimensions.
5. Persist `currentPanelSizingVersion` so a later explicit 520-point choice is not migrated again.

Use one private finite-clamp helper rather than duplicating validation. Menu bounds remain 380...800 and 300...800. Pinned lower bounds are 480 and 320; screen-relative upper clamping belongs to AppKit presentation.

- [ ] **Step 4: Run the focused preference and persistence tests**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'AppPreferences|Preferences|PanelSize|panelSize|storeRoundTripsWorkspaceAndPreferences|snapshotIntegrity'
```

Expected: new and old preference fixtures pass; ordinary snapshot persistence remains backward-compatible.

- [ ] **Step 5: Commit the sizing model unit**

```bash
git add Sources/FleckCore/AppPreferences.swift Tests/FleckCoreTests/AppPreferencesTests.swift
git commit -m "feat: separate menu and pinned window sizes"
```

---

### Task 3: Make only the completed pinned window natively resizable and persistent

**Files:**
- Modify: `Sources/FleckApp/OnboardingWindowPresenter.swift`
- Test: `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`

**Interfaces:**
- Consumes: `NotesPanel(..., sizing: .container)`, `AppPreferences.pinnedPanelWidth`, `AppPreferences.pinnedPanelHeight`, and `AppState.updatePreferences`.
- Produces: a completed-window resize callback owned by `OnboardingWindowPresenter.Coordinator`; menu-bar `NotesPanel` remains `.storedPreferences`.

- [ ] **Step 1: Add red source and pure-sizing contracts**

Extend `OnboardingSourceAuditTests` to assert:

- `FleckMenuBarRoot` still calls `NotesPanel(dictationRuntime: dictationRuntime)` without `.container`;
- completed and blocked pinned-note content call `NotesPanel(dictationRuntime: dictationRuntime, isPinned: true, sizing: .container)` so the native window owns their dimensions;
- `completedSize` reads `pinnedPanelWidth` and `pinnedPanelHeight`;
- the completed minimum is exactly 480 by 320 while onboarding constants remain 1080 by 700 and 760 by 520;
- the presenter observes `NSWindow.didEndLiveResizeNotification`, filters to `.complete`, and writes only pinned dimensions through its callback;
- no `DragGesture` or menu-bar resize handle is introduced.

Add an internal pure `OnboardingWindowPresenter.clampedCompletedSize(_:visibleFrame:) -> NSSize` and test that stored sizes below the minimum become 480 by 320 and sizes above the supplied visible frame are bounded to that frame.

- [ ] **Step 2: Run the pinned-window audit and prove the old fixed sizing is red**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'OnboardingSourceAudit|PinnedWindow|pinnedWindow'
```

Expected: tests fail because completed notes still use stored fixed sizing and no completed resize observer/pinned fields exist.

- [ ] **Step 3: Implement the narrow native resize lifecycle**

In `FleckPinnedNotesRoot`:

- pass `.container` only for completed/blocked pinned notes;
- construct `completedSize` from the new pinned fields;
- pass an `onCompletedResize` closure that updates only `pinnedPanelWidth` and `pinnedPanelHeight` when the values actually change.

In `OnboardingWindowPresenter`:

- keep onboarding constants and behavior unchanged;
- add `completedMinimumSize = NSSize(width: 480, height: 320)`;
- clamp the initial completed content size against the minimum and the active screen's visible frame;
- set the completed window's `contentMinSize` and flexible maximum for its current screen;
- keep the window's native resizable style; do not add gesture handling;
- let `Coordinator` own and remove the notification observer;
- observe only the presented `NSWindow` and call back on `didEndLiveResizeNotification` only when the current gate is `.complete`;
- ignore programmatic onboarding/completed `setContentSize` calls and no-op dimensions.

Use the existing representable coordinator as the sole AppKit boundary. Do not store an `NSWindow` globally.

- [ ] **Step 4: Run pinned-window and preference integration tests**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'OnboardingSourceAudit|PinnedWindow|pinnedWindow|PanelSize|panelSize'
```

Expected: the menu remains fixed, pinned content is flexible, onboarding constants are intact, and independent dimensions pass their contracts.

- [ ] **Step 5: Commit the pinned-window unit**

```bash
git add Sources/FleckApp/OnboardingWindowPresenter.swift Tests/FleckAppTests/OnboardingSourceAuditTests.swift
git commit -m "feat: resize pinned Fleck window natively"
```

---

### Task 4: Add the always-reachable formatting-bar collapse control

**Files:**
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/SettingsView.swift`
- Test: `Tests/FleckAppTests/AppKitEditorTests.swift`

**Interfaces:**
- Consumes: existing `AppPreferences.showFormattingBar` and `AppState.updatePreferences`.
- Produces: one header toggle; the existing conditional `FormattingBar` remains the only command surface and `EditorCommands` remains unchanged.

- [ ] **Step 1: Add a red collapse-control source contract**

Add `formattingBarCanAlwaysBeCollapsedAndRestoredFromTheHeader` that reads `NotesPanel.swift` and asserts:

```swift
#expect(source.contains("Hide formatting controls"))
#expect(source.contains("Show formatting controls"))
#expect(source.contains("showFormattingBar.toggle()"))
#expect(source.contains("if appState.preferences.showFormattingBar"))
#expect(source.contains("\"chevron.up\""))
#expect(source.contains("\"chevron.down\""))
```

Keep the existing `formattingBarKeepsOneReachableCommandSurfaceAtSupportedWidths` assertions. Extend the source contract to prove `@StateObject private var editorCommands = EditorCommands()` remains owned by `NotesPanel`, outside `if appState.preferences.showFormattingBar`, and that toolbar visibility is not used as an `.id(...)` for the editor. Preserve the existing editor-command regression suite and verify selection/RTF nonmutation in the packaged app instead of building a duplicate editor model.

- [ ] **Step 2: Run the formatting-bar tests and prove the missing header control is red**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'formattingBar|FormattingBar'
```

Expected: the new header-control assertions fail before implementation; existing formatting command behavior remains green.

- [ ] **Step 3: Implement the minimal header toggle**

In the existing header, near Customize/Options, add one plain button:

```swift
Button {
  appState.updatePreferences { $0.showFormattingBar.toggle() }
} label: {
  Image(
    systemName: appState.preferences.showFormattingBar
      ? "chevron.up"
      : "chevron.down"
  )
}
.accessibilityLabel(
  appState.preferences.showFormattingBar
    ? "Hide formatting controls"
    : "Show formatting controls"
)
.help(
  appState.preferences.showFormattingBar
    ? "Hide formatting controls"
    : "Show formatting controls"
)
```

Keep the button outside the conditional bar so it is always reachable. Give the existing `FormattingBar` conditional an opacity-only transition and use the existing `AppMotion`/Reduce Motion behavior; do not detach or recreate `EditorCommands`. Rename the Settings labels to `Menu width` and `Menu height` without changing their controls or ranges.

- [ ] **Step 4: Run formatting and editor regression tests**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'formattingBar|FormattingBar|editorCommands|EditorCommands|fontFamilyAndSize'
```

Expected: the header toggle is always reachable, the single existing formatting surface remains intact, and formatting/editor state tests pass.

- [ ] **Step 5: Commit the toolbar unit**

```bash
git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift Sources/FleckApp/SettingsView.swift
git commit -m "feat: collapse Fleck formatting controls"
```

If `SettingsView.swift` is unchanged, omit it from `git add`.

---

### Task 5: Verify the integrated packaged behavior

**Files:**
- Inspect only: every file owned above, `Package.resolved`, generated `.build/Fleck.app`, and the accumulated diff from plan-start commit.

**Interfaces:**
- Consumes: completed Tasks 1-4.
- Produces: verification evidence only; no cleanup refactor.

- [ ] **Step 1: Run focused integration coverage**

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'waveform|DictationRuntimeForwardsLevelsOnlyToAnActiveVisibleCapsule|AppPreferences|PanelSize|panelSize|OnboardingSourceAudit|PinnedWindow|pinnedWindow|formattingBar|FormattingBar|editorCommands'
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 2: Run the deterministic full test suite**

```bash
swift test --disable-automatic-resolution --no-parallel --quiet
```

Expected: every suite and test passes; report the exact counts.

- [ ] **Step 3: Run the complete repository validation gate**

```bash
Scripts/validate-macos.sh
```

Expected: tests, Fleck release, fleck-agent release, development-signed package, executable-size budget, privacy/candidate audits, smoke checks, lock preservation, and candidate-release rejection all pass. If the sandbox blocks Swift caches, rerun the identical command with the required cache access and report both attempts honestly.

- [ ] **Step 4: Inspect integrity and scope**

```bash
git diff --check
git status --short --branch
git ls-files -u
git diff --stat <plan-start-commit>..HEAD
git diff <plan-start-commit>..HEAD -- Package.resolved
test ! -e .git/MERGE_HEAD
```

Expected: only owned source/tests and the approved spec/plan commits are present; `Package.resolved` is unchanged; no unmerged entries or merge are active.

- [ ] **Step 5: Build and validate the exact packaged app manually**

Use `Scripts/build-fleck-app.sh`. Resolve the executable path of every running Fleck process; terminate only a process whose executable is the known `/Users/harryjin/menubar-notes/.build/Fleck.app/Contents/MacOS/Fleck`, then launch that exact bundle. In designated Fleck QA notes only:

1. Confirm silent listening bars are static while the dot and timer continue.
2. Confirm soft, normal, and loud speech yield visibly increasing amplitudes and decay to rest.
3. Repeat the waveform check with Reduce Motion.
4. Collapse/restore the toolbar, confirm no collapsed vertical space, preserve selection/formatting, and relaunch to verify persistence.
5. Confirm the menu panel is 640 by 430 and has no resize affordance.
6. Resize only the pinned window from edges/corner, close/reopen it, and confirm its size persists independently.
7. Confirm pinned minimum sizing, Light/Dark, keyboard focus, accessible labels, typing, undo/redo, and dictation insertion.

Record unavailable hardware/display/accessibility conditions rather than claiming them passed.

- [ ] **Step 6: Return the implementation report to the primary Sol session**

Report:

```text
STATUS: complete | partial | blocked
OBJECTIVE: truthful waveform, collapsible formatting bar, 640-point menu default, independently resizable pinned window
CHANGES: file-by-file summary from the actual diff
VERIFIED: exact commands, test counts, build/package results, and manual packaged-app observations
JUDGMENT CALLS: constants, migration behavior, observer lifecycle, or none
GAPS: unavailable microphones, displays, accessibility modes, older macOS, or none
COMMITS: exact local commit hashes
```

Do not push, merge, open/close a PR, or modify GitHub settings. The primary Sol session owns parent verification, GitHub checkpoints, CI, fresh Sol review, merge authorization, and main synchronization.

## Sol Advisor Acceptance Boundary

The primary GPT-5.6 Sol / High session must inspect the complete diff and every changed file, confirm all ownership and invariants, rerun focused tests, the full deterministic suite, `Scripts/validate-macos.sh`, packaged-app verification, integrity checks, and GitHub CI. It must then invoke a fresh `sol_advisor_sol_reviewer` on GPT-5.6 Sol / High with the actual diff and evidence. The task is not complete and the PR must not merge unless the final verdict is `ship`.
