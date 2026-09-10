# Fleck Dictation Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` for the assigned task. Do not read or implement later tasks; the orchestrator supplies a task brief.

**Goal:** Replace Fleck's generic bottom dictation capsule with the approved Fleck rail: a persistent, nonactivating, click-to-dictate control with truthful pipeline state, Fleck-native visual language, restrained motion, deterministic recovery, and bottom/side docking.

**Architecture:** Keep `DictationCoordinator` authoritative for capture, pipeline, persistence, and terminal outcomes. Make `GlobalHoldShortcut` the single owner of keyboard- and pointer-started shortcut sessions. Keep one `DictationCapsulePanel`, one AppKit event host, and one SwiftUI presentation model alive across every phase; runtime code only maps authoritative coordinator/session state into that model. Pure value types own colors, sizes, stage treatments, gesture classification, and waveform math so the important contracts remain testable without visual snapshots.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, SwiftPM on macOS 14+.

**Spec:** `docs/superpowers/specs/2026-08-30-fleck-dictation-rail-design.md`

## Global Constraints

- Work only in `${FLECK_REPO}/.worktrees/fleck-dictation-rail-design` on `codex/fleck-dictation-rail-design`.
- Preserve unrelated work. Other agents may inspect or edit other files; do not revert their work and adapt to accepted earlier task commits.
- Follow strict red-green-refactor: add the narrow failing test, run it and record the expected failure, implement the minimum behavior, then rerun focused tests.
- Do not call the coordinator directly from pointer handlers. Pointer and modifier input converge through `GlobalHoldShortcut`.
- Do not replace `panel.contentView`, its AppKit event host, or its SwiftUI root after controller initialization.
- Do not activate Fleck or move foreground-app focus when starting, stopping, cancelling, dragging, or right-clicking the rail.
- Do not display or persist transcript text, audio levels, foreground-app identity, or routing candidates in the rail.
- Use `#7C6CF2` as Fleck's default core accent and derive display-only contrast-safe variants without mutating `AppPreferences.accentHex`.
- Do not add gradients, glow, glass, bounce, shimmer, pulse, decorative silence motion, success celebration, failure shake, percentages, dependencies, analytics, telemetry, or speculative configuration.
- Keep exact size tiers and timing contracts from the approved spec. Labels are generation-fenced and may reveal after 450 ms, but timers never manufacture a phase.
- Keep all terminal outcomes truthful. Cleanup fallback is successful `Saved original`; no speech is amber-neutral; saving starts only at the real persistence boundary.
- No packaging, installation, push, pull request, merge, or publication is authorized. Commit each accepted task locally.

---

### Task 1: Authoritative Session, Pipeline, Saving, and Failure Context

**Owned files:**

- Modify: `Sources/FleckApp/DictationCoordinator.swift`
- Modify: `Sources/FleckApp/FleckApp.swift` (compile adapter for typed no-speech only)
- Modify: `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Objective and success criteria:** Coordinator events carry stable capture identity, mode, active pipeline stage, cleanup fallback, and authoritative failure-stage provenance through terminal publication. A distinct `.save` context event is emitted immediately before each real persistence call. Finishing a hands-free session while the engine is still starting cancels; it never creates a no-speech failure.

**Interfaces:**

Add minimal value types alongside the existing phase/event declarations:

```swift
enum DictationPipelineStage: Equatable, Sendable {
  case capture
  case polish
  case organize
  case save
}

struct DictationCoordinatorContext: Equatable, Sendable {
  let sessionID: UUID
  let mode: DictationMode
  let pipelineStage: DictationPipelineStage
  let cleanupOutcome: DictationCleanupOutcome?
  let failureStage: DictationPipelineStage?
}
```

Add externally allocated-token overloads used by the session owner while
preserving the existing convenience methods for source compatibility:

```swift
func beginShortcut(
  session: DictationShortcutSession,
  editor: (any FocusedDictationEditing)?,
  destination: DictationDestination?
) -> Bool

func beginHandsFreeShortcut(
  session: DictationShortcutSession,
  editor: (any FocusedDictationEditing)?,
  destination: DictationDestination?
) -> Bool
```

Keep the existing coarse phase enum stable and add an explicit `.noSpeech` terminal outcome. Add a backward-compatible defaulted `context` parameter to `DictationCoordinatorEvent`:

```swift
struct DictationCoordinatorEvent: Equatable {
  let phase: DictationPhase
  let terminal: DictationTerminalOutcome?
  let context: DictationCoordinatorContext?

  init(
    phase: DictationPhase,
    terminal: DictationTerminalOutcome?,
    context: DictationCoordinatorContext? = nil
  ) {
    self.phase = phase
    self.terminal = terminal
    self.context = context
  }
}
```

The real save boundary is represented as a new event whose context changes to
`.save`; this satisfies the approved "event or phase" contract without making
the coarse phase enum manufacture another operation state.

- [ ] **Step 1: Write failing event-context and saving-boundary tests**

Use existing coordinator fixtures/gates to prove:

1. Smart hands-free and hold-to-talk sessions each use one `sessionID` and one normalized mode from their first arming event through terminal.
2. Smart phases publish capture/finalizing, polish/cleaning, organize/routing, and a distinct `.save` context event in order.
3. Focused dictation skips `.routing` and emits a `.save` context event immediately before `flushFocusedDictationSave` is released.
4. Smart dictation emits a `.save` context event immediately before `saveSmartCapture` is released, and never publishes saved before a receipt.
5. Cleanup failure carries `.usedRaw` into routing, saving, and saved terminal context.
6. Provider/start/finish/no-speech failures report `.capture`; persistence failures report `.save`; no view-facing code infers a stage from text.
7. Genuine empty final text yields terminal `.noSpeech`; finishing a hands-free session during provider or engine start yields terminal `.cancelled`, never `.noSpeech` or `.failed("No speech detected.")`.

Representative assertions:

```swift
#expect(events.contains { $0.context?.pipelineStage == .save && $0.terminal == nil })
#expect(events.last?.context?.sessionID == session.id)
#expect(events.last?.context?.failureStage == .save)
```

- [ ] **Step 2: Run the narrow tests and verify RED**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationCoordinator
```

Expected: compilation or assertions fail because coordinator context and typed no-speech do not yet exist, and startup finish currently becomes no-speech.

- [ ] **Step 3: Add context to capture state and publishers**

- Store `pipelineStage` and `cleanupOutcome` on the active capture rather than in the view.
- Store a pending shortcut context before `beginShortcut` publishes its initial arming event; move that same context into the capture at threshold. Do not keep context solely on `Capture`, which does not exist yet during hold arming.
- Normalize the focused editor before initial arming so the mode is stable.
- Let the future session owner allocate and install the session token before the coordinator publishes arming. Convenience wrappers may allocate their own token for existing direct tests/callers.
- Build event context while the capture/session still exists. Terminal publication must receive the captured context before `capture` is cleared.
- `setPhase` may update the authoritative stage, but it must not derive it from elapsed time or error strings.
- Cleanup success/fallback updates `cleanupOutcome` before moving to routing or saving.
- Extend `terminate`/terminal publication with an explicit optional `failureStage`; call sites provide it based on the failed operation.
- Use `.capture` for provider/start/finish failures and `.save` for editor commit, focused flush, or Smart insertion failures. Cleanup remains fallback, while compensation/history/recovery failures use `nil` because they are not one of the four active pipeline operations.

- [ ] **Step 4: Emit truthful saving and cancel startup finish**

- Publish an event whose authoritative context stage is `.save` immediately before `flushFocusedDictationSave(captureID:)`.
- Publish an event whose authoritative context stage is `.save` immediately before `saveSmartCapture(text:captureID:destinationID:)`.
- Do not publish success until the persistence receipt exists.
- In `finish()`, route an `isStarting` capture through cancellation semantics. Preserve the existing late-engine release and one-capture protections.
- Publish genuine empty final text as `.noSpeech`. Add only the minimum exhaustive-switch adapter in `FleckApp.swift`; Task 4 supplies its amber rail mapping.

- [ ] **Step 5: Run focused coordinator tests**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationCoordinatorTests
```

Expected: all coordinator tests pass, including existing history, compensation, cancellation, routing, and recovery tests.

- [ ] **Step 6: Self-review and commit**

Check that every terminal event retains context, every failure call site names the correct stage, and `.save` context events wrap real persistence only.

```bash
git add Sources/FleckApp/DictationCoordinator.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/DictationCoordinatorTests.swift
git commit -m "feat: publish truthful dictation pipeline state"
```

**Non-goals:** No capsule UI, shortcut-owner changes, waveform changes, copy rewrite, or new error taxonomy.

---

### Task 2: One Native Owner for Pointer and Keyboard Sessions

**Owned files:**

- Modify: `Sources/FleckApp/GlobalHoldShortcut.swift`
- Modify: `Tests/FleckAppTests/GlobalHoldShortcutTests.swift`

**Objective and success criteria:** `GlobalHoldShortcut` owns exactly one token and its trigger/mode/hands-free state across hold, double-tap, and pointer starts. Pointer start/finish/cancel use explicit entry points. A later configured-modifier press finishes a pointer-owned hands-free session. Escape cancels it. Competing input cannot overlap it.

**Interfaces:**

Add presentation-safe ownership values and explicit pointer commands:

```swift
enum DictationShortcutTrigger: Equatable, Sendable {
  case hold
  case doubleTap
  case pointer
}

struct DictationShortcutOwnership: Equatable, Sendable {
  let session: DictationShortcutSession
  let trigger: DictationShortcutTrigger
  let mode: DictationMode
  let isHandsFree: Bool
}

private(set) var activeOwnership: DictationShortcutOwnership?
var ownershipHandler: @MainActor (DictationShortcutOwnership?) -> Void

@discardableResult
func startPointerHandsFree() -> Bool
func finishOwnedHandsFree() async
func cancelOwnedSession() async
```

- [ ] **Step 1: Write failing ownership tests**

Extend the existing monitor/handler fakes to prove:

- Pointer start calls `beginHandsFreeShortcut` exactly once and exposes `.pointer` ownership.
- A second pointer start, double-tap, or hold press is rejected while the token is owned.
- `finishOwnedHandsFree()` dispatches exactly one finish and retains ownership until terminal observation.
- A selected-modifier press finishes a pointer-started session and ignores its matching release.
- Escape and `cancelOwnedSession()` cancel a pointer-started session exactly once.
- A terminal outcome clears token, ownership, Escape registration, and tap state.
- Mode is captured from the same normalized editor/destination snapshot used to begin the session.
- The first arming event for hold, double-tap, and pointer starts can synchronously observe the correct token, trigger, mode, and hands-free state.

- [ ] **Step 2: Run and verify RED**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter GlobalHoldShortcutTests
```

Expected: new pointer/ownership APIs are absent.

- [ ] **Step 3: Centralize ownership transitions**

- Extract one hands-free start helper used by double-tap and pointer triggers.
- Extract one ownership installation path for hold and hands-free sessions.
- Allocate the `DictationShortcutSession` in the owner, normalize the editor/mode, and install internal ownership before calling the coordinator's externally allocated-token overload. This makes the coordinator's synchronous arming event transactional: runtime can read `activeOwnership` during that first event. Notify `ownershipHandler` only after acceptance; on rejection clear the unannounced provisional ownership.
- Keep the existing serialized delivery queue, monotonic tap clock, Escape registrar, terminal waiter, and uninstall behavior.
- Do not let pointer APIs depend on Carbon delivery; they run directly on `@MainActor`.
- Keep `activeOwnership` until the authoritative terminal waiter completes, not merely until finish/cancel is requested.
- Add an owned-session `finishRequested`/`cancelRequested` guard so rail clicks and modifier repeats cannot dispatch duplicate terminal commands.

- [ ] **Step 4: Run focused shortcut tests**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter GlobalHoldShortcutTests
```

Expected: all existing hold/double-tap/monitor-loss/uninstall tests and all new pointer tests pass.

- [ ] **Step 5: Self-review and commit**

```bash
git add Sources/FleckApp/GlobalHoldShortcut.swift \
  Tests/FleckAppTests/GlobalHoldShortcutTests.swift
git commit -m "feat: unify dictation shortcut session ownership"
```

**Non-goals:** No AppKit pointer tracking, runtime mapping, capsule visuals, modifier semantics, or coordinator persistence changes.

---

### Task 3: Persistent Fleck Rail Model, Geometry, Color, and Host

**Owned files:**

- Modify: `Sources/FleckApp/DictationCapsule.swift`
- Modify: `Tests/FleckAppTests/DictationAccessibilityTests.swift`

**Objective and success criteria:** One panel, one event host, and one SwiftUI root survive every phase. Pure presentation values implement the approved state copy, size ceilings, Fleck colors, stage treatments, horizontal side-dock reflow, and nonactivating accessibility contracts without system-blue leakage.

**Interfaces:**

Keep the existing source-compatible status cases so Task 3 remains buildable
before runtime integration. Add only the missing explicit rail states and put
mode/ownership/pipeline detail in a separate context value:

```swift
enum DictationCapsuleStatus: Equatable {
  case idle
  case arming
  case listening
  case finalizing
  case cleaning
  case routing
  case saving
  case saved(destination: String)
  case savedWithoutCleanup(destination: String)
  case noSpeech
  case repairingModel
  case failed(String)
}

struct DictationCapsuleContext: Equatable {
  let status: DictationCapsuleStatus
  let sessionID: UUID?
  let trigger: DictationShortcutTrigger?
  let mode: DictationMode?
  let isHandsFree: Bool
  let pipelineStage: DictationPipelineStage?
  let cleanupOutcome: DictationCleanupOutcome?
  let failureStage: DictationPipelineStage?
}

enum FleckRailStageTreatment: Equatable {
  case pending, active, complete, skipped, fallback, failed
}
```

Introduce a persistent `ObservableObject` presentation model and construct the AppKit/SwiftUI host exactly once in `DictationCapsuleController.init`.

- [ ] **Step 1: Write failing pure presentation tests**

Prove:

- Exact tiers: idle 46×24; arming 46×24; listening 176×36; finalizing/cleaning/routing/saving 192×36; saved ≤264×36; saved-without-cleanup presentation ≤288×36; no-speech ≤192×36; repair 224×36; failure ≤264×36.
- Bottom and side frames remain horizontal; dimensions are never swapped and the entire view is never rotated. Edge inset is 10 points.
- A pure `DictationCapsuleContext` with focused mode marks Organize skipped; cleanup fallback marks Polish fallback; failures mark only authoritative `failureStage` failed with later tiles pending.
- Focused and Smart save failures with the same `failureStage` retain distinct Organize skipped/complete treatments because session ID, mode, cleanup outcome, and failed stage all reach the presentation.
- Visible copy is `Finishing`, `Polishing`, `Organizing`, `Saving`, `Saved to …`, `Saved original to …`, `No speech heard`, and the concise failure/repair copy from the spec.
- The code-drawn mark uses a 14×14 frame, four approximately 6-point tiles, a 2-point gap, stable tile IDs, and the approved restrained one-point inner highlight.
- Action-bearing results use a 1×16 divider. Long destination copy is tail-truncated and the measured surface never exceeds its status width ceiling.
- The default accent is `#7C6CF2`. Custom core/live display colors have at least 3:1 contrast against `#17151C` while the stored hex remains unchanged.
- `DictationCapsulePanel` stays nonactivating, non-key, non-main, floating, and Spaces/full-screen compatible.
- `panel.contentView` identity is identical across idle, listening, processing, terminal, and dock changes.

- [ ] **Step 2: Run and verify RED**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationAccessibility
```

Expected: old sizes/copy/system symbols and content replacement violate the new tests.

- [ ] **Step 3: Implement pure rail presentation values**

- Add `FleckRailColors` that resolves a saved hex into display-only core/live colors plus fixed shell/semantic colors. Make contrast calculation pure and testable.
- Add a code-drawn four-tile `FleckRailMark` with stable tile IDs, 14×14 geometry, approximately 6-point tiles, 2-point gap, and restrained one-point inner highlight. Do not use an SF Symbol as the Fleck mark and do not modify the packaged PNG.
- Add pure pipeline-treatment mapping driven only by `DictationCapsuleContext`.
- Use continuous rounded rectangles with 10-point idle and 12-point active radii; default shell is `#17151C` at 96% opacity.
- Keep text at SF Pro Text 12 medium, actions 11 semibold, timer SF Mono 10.5 medium/tabular; no wrapping.
- Add the 1×16 low-contrast action divider and tail truncation for destination/result copy. Width calculations must clamp to each status ceiling rather than expanding the panel.

- [ ] **Step 4: Install one stable host and dock-aware layout**

- Replace `installContent` with model mutation. Preserve a source-compatible `render(_:action:onAction:)` adapter until Task 4 supplies the full context. `panel.contentView` is assigned once.
- Use one persistent AppKit event host containing one `NSHostingView`/SwiftUI root.
- Keep mark nearest the dock edge. Mirror left/right content order rather than rotating text or swapping width/height.
- Keep screen selection, visible-frame clamping, screen-change redocking, and nearest-dock behavior.
- Hide timer/waveform internals from repeated VoiceOver announcements and expose concise state labels.

- [ ] **Step 5: Run focused tests and commit**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationAccessibility
```

```bash
git add Sources/FleckApp/DictationCapsule.swift \
  Tests/FleckAppTests/DictationAccessibilityTests.swift
git commit -m "feat: build persistent Fleck dictation rail"
```

**Non-goals:** No runtime event mapping, no coordinator calls, no pointer-start wiring, no new image asset, and no standalone mock app.

---

### Task 4: Runtime Wiring, Pointer Arbitration, Menus, and Recovery Lifetime

**Owned files:**

- Modify: `Sources/FleckApp/DictationCapsule.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Tests/FleckAppTests/DictationAccessibilityTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Objective and success criteria:** Qualifying rail clicks start/finish one owner-managed hands-free session without app activation; four-point drag arbitration and action consumption are deterministic; status mapping is authoritative; menus expose Fleck/History/Dictation Settings/docking/dismiss; action-bearing failures persist.

**Interfaces:**

Add a pure pointer reducer/test seam around primary down/drag/up:

```swift
enum FleckRailPointerResult: Equatable {
  case none
  case primaryClick
  case drag
}

struct FleckRailPointerGesture {
  static let dragThreshold: CGFloat = 4
  mutating func mouseDown(at point: CGPoint, consumed: Bool)
  mutating func mouseDragged(to point: CGPoint)
  mutating func mouseUp(at point: CGPoint) -> FleckRailPointerResult
}
```

- [ ] **Step 1: Write failing gesture, menu, runtime, and timer tests**

Prove:

- Travel below 4 points commits one primary click on mouse-up; travel at or above 4 points becomes drag and permanently suppresses click.
- Right-click, Stop, Cancel, recovery, and context-menu regions are consumed and never fall through.
- Idle primary click calls `shortcutController.startPointerHandsFree()` once and does not call `NSApp.activate`/`openFleckPanel`.
- Hands-free arming/listening rail click calls `finishOwnedHandsFree()` once; Task 1 guarantees startup finish resolves as cancellation. Hold-to-talk arming/listening ignores rail-wide primary clicks and exposes no hover Stop controls.
- Stop finishes; Cancel calls `cancelOwnedSession()`; VoiceOver exposes both even before hover.
- Runtime maps `.arming` to compact arming, not listening; maps each coordinator pipeline stage/context; maps no-speech to amber-neutral; maps missing Smart destination to `your notes`; maps cleanup fallback to saved-original.
- Action-bearing failures do not schedule the three-second idle return. Non-action failures/no-speech still use the existing interval. A newer capture invalidates old result timers.
- Clearing shortcut ownership after terminal observation does not replace focused saved, saved-original, timed failure, or persistent action-bearing failure status before its runtime-owned lifecycle completes.
- The context menu order includes `Open Fleck`, `Dictation History`, `Dictation Settings`, docking choices, and applicable `Dismiss`/recovery items.
- The first arming presentation already contains the owner-provided session ID, trigger, mode, and hands-free value for hold, double-tap, and pointer starts.
- Idle hit testing uses the rounded 46×24 visible shell: transparent rounded corners and every point outside the shell pass through. Drag affordances/drop-zone indicators are hidden before threshold, visible only while drag state is active, and cleared on release/cancel.
- Dictation Settings stores a durable pending `.dictation` route, opens the app's Settings scene through an `OpenSettingsAction` bridge, and consumes the route when `SettingsView` appears; it works even when the view did not exist when the menu command fired.
- `accentHex` is resolved outside the detached view and updated through `preferencesDidChange` without rewriting the preference.
- Concise failure mapping is pure and tested: known microphone permission/unavailable capture errors become `Microphone access needed`, save-stage errors become `Couldn't save`, and repair failure becomes `Model repair failed`; technical detail stays in Settings, History, or VoiceOver.

- [ ] **Step 2: Run and verify RED**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationAccessibility
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationSettingsTests
```

- [ ] **Step 3: Implement event-host pointer routing**

- Track down/drag/up in the persistent AppKit host.
- Only idle background drags move/dock the panel. A threshold-crossing active gesture suppresses stop but does not invent another operation.
- Rail-wide primary clicks call runtime callbacks; SwiftUI/AppKit action regions consume their events first.
- Use a rounded-path hit-test helper for the visible shell, returning `nil` for transparent corners/outside points so the underlying app receives them. Toggle the presentation model's supported dock indicators only between drag threshold crossing and drag completion/cancellation; do not create extra overlay panels.
- Hover only crossfades the fixed 58×28 listening action zone between timer and two fixed 28×28 Stop/Cancel targets. It never resizes or shifts mark/waveform.

- [ ] **Step 4: Wire authoritative runtime mapping**

- Map `DictationCoordinatorEvent.context` and `GlobalHoldShortcut.activeOwnership` into one full `DictationCapsuleContext`, including the very first synchronous arming event. Install `ownershipHandler` so non-coordinator ownership changes can re-render without polling.
- Retain the last coordinator event/context in runtime. When `ownershipHandler(nil)` arrives after terminal observation, merge the ownership change into internal state but do not re-render over the active terminal result; only the runtime-owned result timer, explicit dismissal/action, or a newer capture may replace it.
- Inject current accent, dock, recovery action, and callbacks into the stable model.
- Use owner entry points for pointer start/finish/cancel. Gate rail-wide Stop/hover controls on `isHandsFree`; a hold-to-talk context never finishes from a rail click. Keep toolbar behavior unchanged unless required for exhaustive phase switches.
- Make action-bearing failures persistent; shell click/context menu/VoiceOver Dismiss only clears the visible owner and leaves recovery/history intact.
- Add a durable runtime-owned pending `SettingsSection?` route with `requestSettings(_:)` and `consumePendingSettingsSection()`. Install an `@Environment(\.openSettings)` bridge from the Fleck app scene; `SettingsView` consumes the pending route on appearance/change and selects `.dictation`. Do not use a fire-and-forget notification and do not redesign Settings.
- Keep runtime as the sole owner of terminal success/failure return timers. Map concise rail failure copy in one pure adapter while preserving full detail for existing recovery surfaces.

- [ ] **Step 5: Run focused integration tests and commit**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationAccessibility
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationSettingsTests
swift test --disable-automatic-resolution --no-parallel \
  --filter GlobalHoldShortcutTests
```

```bash
git add Sources/FleckApp/DictationCapsule.swift \
  Sources/FleckApp/FleckApp.swift \
  Sources/FleckApp/SettingsView.swift \
  Tests/FleckAppTests/DictationAccessibilityTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: connect Fleck rail interactions"
```

**Non-goals:** No new dictation command, no transcript preview, no expanded diagnostics, no change to note focus/routing selection rules, and no timer-derived pipeline state.

---

### Task 5: Seven-Bar Waveform, Generation-Fenced Motion, and Accessibility Polish

**Owned files:**

- Modify: `Sources/FleckApp/DictationWaveform.swift`
- Modify: `Sources/FleckApp/DictationCapsule.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/DictationWaveformTests.swift`
- Modify: `Tests/FleckAppTests/DictationAccessibilityTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Objective and success criteria:** The rail has a truthful seven-bar real-audio waveform, restrained/generation-safe phase motion, Reduce Motion/Transparency/Contrast behavior, coalesced VoiceOver state, and no stale timer or level can mutate a newer session.

- [ ] **Step 1: Write failing waveform and generation tests**

Prove:

- Exactly seven bars with stable asymmetric weights, 2.5-point width, 2-point gap, and 4–17-point rendered height.
- Real input uses a low noise floor, fast attack, slower release, bounded output, and stale decay; silence is a stable minimal baseline with no synthetic dance.
- Normal input accepts at most 30 updates/second; reduced motion accepts at most 15 and uses smoothed reduced amplitude.
- `reset()` clears energy, accepted-level time, and elapsed timer.
- Processing label slots exist immediately but text opacity appears only after a generation-fenced 450 ms delay.
- A stale label task or waveform level cannot affect a newer presentation generation; existing runtime-owned saved/failure return and model-repair generation guards remain authoritative and continue to reject stale completion.
- Reduce Motion snaps geometry/docking and removes tile travel; settled content may crossfade. Reduce Transparency uses opaque shell; Increase Contrast strengthens outlines/text.
- VoiceOver announces listening and terminal outcomes once; it does not repeatedly announce elapsed time, waveform bars, or short processing phases.

- [ ] **Step 2: Run and verify RED**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationWaveformTests
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationAccessibility
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationSettingsTests
```

- [ ] **Step 3: Implement minimal waveform math**

Use one scalar accepted level and fixed seven-element weights. Do not synthesize phase or random motion. Preserve the existing elapsed-time origin and make the accepted input cadence depend on Reduce Motion through an explicit method parameter or model setting.

- [ ] **Step 4: Implement restrained, fenced motion**

- Immediate input acknowledgement; 90 ms color/opacity; 140 ms shared tile/internal morph; 70 ms exit; 100–120 ms result; 180 ms zero-bounce dock snap.
- Use presentation-generation tokens only for the 450 ms label, waveform, and motion work. Runtime remains the sole terminal-return timer owner; do not add a second success/failure timer in the view/model. Cancel obsolete presentation tasks and validate generation plus current owner/status before mutation.
- Reduce Motion snaps geometry/docking, uses settled-layout crossfades, removes tile travel, and caps visual/audio updates at 15 Hz.
- Do not add bounce, spring overshoot, blur/glow, gradient animation, symbol effects, or idle animation.

- [ ] **Step 5: Run the full focused rail suite**

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationCoordinatorTests
swift test --disable-automatic-resolution --no-parallel \
  --filter GlobalHoldShortcutTests
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationWaveformTests
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationAccessibility
swift test --disable-automatic-resolution --no-parallel \
  --filter DictationSettingsTests
```

- [ ] **Step 6: Self-review and commit**

```bash
git add Sources/FleckApp/DictationWaveform.swift \
  Sources/FleckApp/DictationCapsule.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/DictationWaveformTests.swift \
  Tests/FleckAppTests/DictationAccessibilityTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: polish Fleck dictation rail feedback"
```

**Non-goals:** No audio persistence/logging, no procedural animation, no app-wide design-system refactor, and no unrelated accessibility cleanup.

---

## Parent Verification and Handoff

After all five tasks have clean task reviews:

1. Inspect `git diff origin/main...HEAD` for scope, secrets, generated artifacts, stale old status cases, direct pointer-to-coordinator calls, and `panel.contentView` replacement.
2. Run:

```bash
swift test --disable-automatic-resolution --no-parallel
swift build --disable-automatic-resolution
```

3. Launch/build only the exact Fleck app if safe, and perform the manual rail matrix in the approved spec without installing or replacing a packaged app.
4. Obtain a fresh whole-branch code review and the required fresh `sol_advisor_sol_reviewer` verdict of `ship`. Return any findings to the active native implementation worker lane; do not repair them silently in the orchestrator.
5. Report local commits, exact checks, visual/manual evidence actually observed, and remaining packaged-app/real-speech/release gates. Do not push, open a pull request, merge, package, install, or publish without new authorization.
