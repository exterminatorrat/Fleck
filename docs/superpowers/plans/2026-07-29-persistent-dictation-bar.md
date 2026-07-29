# Fleck Persistent Dictation Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Fleck's chord-only, event-only dictation feedback with a persistent dockable bar and a side-specific single-modifier gesture supporting hold-to-talk and double-tap hands-free dictation.

**Architecture:** Add backward-compatible modifier/dock preferences in `FleckCore`; use a passive, listen-only Core Graphics `flagsChanged` event tap behind an injected adapter; keep gesture ownership in `GlobalHoldShortcut` and transcription ownership in `DictationCoordinator`. Convert the existing single `NSPanel` capsule into a persistent state renderer, then wire settings, permissions, startup/load synchronization, docking persistence, and shutdown through the shared `DictationRuntime`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Core Graphics event taps, Carbon only for capture-scoped Escape, Swift Testing, SwiftPM on macOS 14+.

## Global Constraints

- macOS 14 remains the minimum.
- Right Option is the default modifier for new and migrated preferences.
- Supported triggers are Fn, Left/Right Command, Left/Right Option, and Left/Right Control; Shift is excluded.
- The trigger subscribes only to Core Graphics `flagsChanged`; it never subscribes to ordinary `keyDown` or `keyUp`.
- Hold threshold is exactly 180 milliseconds.
- Double-tap window is exactly 320 milliseconds, measured release-to-next-press with a monotonic clock.
- Double-tap starts hands-free; one later selected-modifier press finishes hands-free; Escape cancels.
- The idle bar contains no shortcut hint and no transcript.
- Exactly one non-activating panel is visible across Spaces while Fleck runs and `dictationCapsuleEnabled` is true.
- Dock choices are exactly bottom, left, and right; only the edge is persisted.
- Saved and saved-without-cleanup remain visible for 1.6 seconds; failure remains visible for 3 seconds; all return to idle.
- Cleanup remains on-device, routing sees active note IDs/titles only, and ambiguity/failure routes to Inbox.
- No cloud service, analytics, telemetry, or new package dependency is added.
- Existing agent-workspace, Trash, rich-text, dictation-history, and storage behavior must remain unchanged.

---

### Task 1: Backward-Compatible Modifier and Dock Preferences

**Files:**
- Modify: `Sources/FleckCore/DictationModels.swift`
- Modify: `Sources/FleckCore/AppPreferences.swift`
- Modify: `Tests/FleckCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Produces: `DictationModifierKey`, `DictationCapsuleDock`, `AppPreferences.dictationModifierKey`, and `AppPreferences.dictationCapsuleDock`.
- Preserves: legacy `DictationShortcut` decoding/source compatibility until later tasks stop using it.

- [ ] **Step 1: Write failing model/default tests**

Add tests proving exact case order, labels, defaults, round-trip encoding, and missing-key migration:

```swift
@Test func dictationModifierAndDockUsePersistentDefaults() throws {
  let value = AppPreferences()
  #expect(value.dictationModifierKey == .rightOption)
  #expect(value.dictationCapsuleDock == .bottom)

  let roundTrip = try JSONDecoder().decode(
    AppPreferences.self,
    from: JSONEncoder().encode(value)
  )
  #expect(roundTrip.dictationModifierKey == .rightOption)
  #expect(roundTrip.dictationCapsuleDock == .bottom)
}

@Test func oldShortcutPreferencesMigrateToRightOptionAndBottomDock() throws {
  let data = Data(
    #"{"fontFamily":".AppleSystemUIFont","fontSize":15,"dictationShortcut":{"keyCode":49,"carbonModifiers":768}}"#.utf8
  )
  let value = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(value.dictationModifierKey == .rightOption)
  #expect(value.dictationCapsuleDock == .bottom)
}

@Test func dictationModifierChoicesKeepPhysicalSidesDistinct() {
  #expect(DictationModifierKey.allCases == [
    .function,
    .leftCommand,
    .rightCommand,
    .leftOption,
    .rightOption,
    .leftControl,
    .rightControl,
  ])
  #expect(Set(DictationModifierKey.allCases.map(\.displayName)).count == 7)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter dictationModifierAndDockUsePersistentDefaults
```

Expected: compilation fails because `DictationModifierKey`, `DictationCapsuleDock`, and the two preference properties do not exist.

- [ ] **Step 3: Add the semantic models**

Add to `DictationModels.swift`:

```swift
public enum DictationModifierKey: String, Codable, CaseIterable, Sendable {
  case function
  case leftCommand
  case rightCommand
  case leftOption
  case rightOption
  case leftControl
  case rightControl

  public var displayName: String {
    switch self {
    case .function: "Fn"
    case .leftCommand: "Left Command"
    case .rightCommand: "Right Command"
    case .leftOption: "Left Option"
    case .rightOption: "Right Option"
    case .leftControl: "Left Control"
    case .rightControl: "Right Control"
    }
  }
}

public enum DictationCapsuleDock: String, Codable, CaseIterable, Sendable {
  case bottom
  case left
  case right
}
```

- [ ] **Step 4: Persist both values compatibly**

Add stored properties and initializer parameters:

```swift
public var dictationModifierKey: DictationModifierKey
public var dictationCapsuleDock: DictationCapsuleDock

dictationModifierKey: DictationModifierKey = .rightOption,
dictationCapsuleDock: DictationCapsuleDock = .bottom,
```

Assign them in `init`, add both coding keys, and decode missing values exactly as:

```swift
dictationModifierKey:
  try c.decodeIfPresent(
    DictationModifierKey.self,
    forKey: .dictationModifierKey
  ) ?? .rightOption,
dictationCapsuleDock:
  try c.decodeIfPresent(
    DictationCapsuleDock.self,
    forKey: .dictationCapsuleDock
  ) ?? .bottom,
```

Keep `dictationShortcut` decodable and source-compatible during the feature branch, but mark it deprecated:

```swift
@available(*, deprecated, message: "Use dictationModifierKey")
public var dictationShortcut: DictationShortcut
```

- [ ] **Step 5: Run focused and core tests**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter dictationModifierAndDockUsePersistentDefaults
swift test --disable-automatic-resolution \
  --filter oldShortcutPreferencesMigrateToRightOptionAndBottomDock
swift test --disable-automatic-resolution --filter FleckCoreTests
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FleckCore/DictationModels.swift \
  Sources/FleckCore/AppPreferences.swift \
  Tests/FleckCoreTests/AppPreferencesTests.swift
git commit -m "feat: add dictation modifier and dock preferences"
```

---

### Task 2: Immediate Hands-Free Coordinator Sessions

**Files:**
- Modify: `Sources/FleckApp/DictationCoordinator.swift`
- Modify: `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Interfaces:**
- Consumes: existing `DictationShortcutSession`, focused editor, destination, and one-capture invariant.
- Produces:

```swift
func beginHandsFreeShortcut(
  editor: (any FocusedDictationEditing)?,
  destination: DictationDestination?
) async -> DictationShortcutSession?

func finishHandsFreeShortcut(_ session: DictationShortcutSession) async
```

- [ ] **Step 1: Write failing hands-free tests**

Use existing coordinator fakes to add:

```swift
@Test @MainActor func handsFreeShortcutStartsWithoutTheHoldThreshold() async throws {
  let sleeper = DictationTestGate()
  let fixture = CoordinatorFixture(
    finalText: "hands free",
    holdSleeper: { _ in await sleeper.wait() }
  )

  let session = try #require(await fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  ))

  #expect(fixture.coordinator.phase == .listening(
    mode: .smartCapture,
    engine: .standard
  ))
  await fixture.coordinator.finishHandsFreeShortcut(session)
  await fixture.coordinator.waitForShortcutTerminal(session)
  #expect(fixture.saver.savedTexts == ["hands free"])
}

@Test @MainActor func handsFreeFinishAndCancelRequireTheOwnedSession() async throws {
  let fixture = CoordinatorFixture(finalText: "owned")
  let session = try #require(await fixture.coordinator.beginHandsFreeShortcut(
    editor: nil,
    destination: nil
  ))

  await fixture.coordinator.finishHandsFreeShortcut(
    .init(id: UUID())
  )
  #expect(fixture.coordinator.phase == .listening(
    mode: .smartCapture,
    engine: .standard
  ))

  await fixture.coordinator.cancelShortcut(session)
  await fixture.coordinator.waitForShortcutTerminal(session)
  #expect(fixture.saver.savedTexts.isEmpty)
}
```

Also assert a hands-free request is rejected during toolbar capture, recovery, an armed hold, and another hands-free session.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --filter handsFreeShortcut
```

Expected: compilation fails because the hands-free APIs do not exist.

- [ ] **Step 3: Implement immediate session ownership**

Add:

```swift
func beginHandsFreeShortcut(
  editor: (any FocusedDictationEditing)?,
  destination: DictationDestination? = nil
) async -> DictationShortcutSession? {
  guard capture == nil, shortcutID == nil, !recoveryOperationInFlight else {
    return nil
  }
  let session = DictationShortcutSession(id: UUID())
  activeShortcutSessions.insert(session.id)
  let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
  await startCapture(
    id: session.id,
    mode: focusedEditor == nil ? .smartCapture : .focused,
    editor: focusedEditor,
    destination: focusedEditor == nil ? nil : destination
  )
  guard activeShortcutSessions.contains(session.id), capture?.id == session.id else {
    return nil
  }
  return session
}

func finishHandsFreeShortcut(_ session: DictationShortcutSession) async {
  guard activeShortcutSessions.contains(session.id), capture?.id == session.id else {
    return
  }
  await finish()
}
```

Make the focused-mode selection match the existing global hold path. Do not add a second capture state machine.

- [ ] **Step 4: Run coordinator tests**

Run:

```bash
swift test --disable-automatic-resolution --filter handsFreeShortcut
swift test --disable-automatic-resolution --filter DictationCoordinatorTests
```

Expected: all coordinator tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FleckApp/DictationCoordinator.swift \
  Tests/FleckAppTests/DictationCoordinatorTests.swift
git commit -m "feat: add hands-free dictation sessions"
```

---

### Task 3: Side-Specific Modifier Monitor and Gesture Controller

**Files:**
- Create: `Sources/FleckApp/ModifierKeyEventTap.swift`
- Modify: `Sources/FleckApp/GlobalHoldShortcut.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/GlobalHoldShortcutTests.swift`
- Modify: `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Interfaces:**
- Consumes: `DictationModifierKey` and Task 2 hands-free APIs.
- Produces:

```swift
enum ModifierKeyTransition: Equatable, Sendable {
  case pressed(DictationModifierKey)
  case released(DictationModifierKey)
}

@MainActor
protocol ModifierKeyMonitoring: AnyObject {
  var transitionHandler: ((ModifierKeyTransition) -> Void)? { get set }
  var stateHandler: ((ModifierMonitorState) -> Void)? { get set }
  var accessGranted: Bool { get }
  func start() throws
  func stop()
  func requestAccess() -> Bool
}

enum ModifierMonitorState: Equatable, Sendable {
  case stopped
  case unauthorized
  case running
  case failed
}
```

- Preserves: capture-scoped Escape Carbon registration, event serialization, terminal ownership, and uninstall behavior.

- [ ] **Step 1: Replace chord tests with modifier mapping/lifecycle RED tests**

Add assertions for exact physical mapping:

```swift
@Test func modifierVirtualKeyCodesKeepPhysicalSidesDistinct() {
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3F) == .function)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x37) == .leftCommand)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x36) == .rightCommand)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3A) == .leftOption)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3D) == .rightOption)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3B) == .leftControl)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3E) == .rightControl)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x00) == nil)
}
```

Using an injected `ModifierMonitorSpy` and monotonic `GestureClock`, test:

- Only the selected side starts a session.
- A release without a synchronized press is ignored.
- A modifier already down during configuration must return neutral before activation.
- Duplicate presses/releases are ignored.
- A short single tap creates no capture.
- Hold delegates begin/end exactly once.
- Two taps within 320 milliseconds call `beginHandsFreeShortcut`.
- A release after the second tap does not finish hands-free.
- One later press calls `finishHandsFreeShortcut`; its release is ignored.
- A second tap after 320 milliseconds is a new first tap.
- Escape cancels the owned hold/hands-free session.
- Monitor failure/cancellation cancels pending tap and owned session.
- Monitor states contain no key codes, flags, or error descriptions.
- Reconfiguration is rejected during a physical press, queued event, or active session.
- Runtime startup waits for `AppState` initial load and applies a persisted non-default modifier without requiring Settings to open.
- Uninstall stops both monitor and Escape registrar.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --filter GlobalHoldShortcutTests
```

Expected: compilation fails because modifier monitor/gesture APIs do not exist.

- [ ] **Step 3: Implement the passive event-tap adapter**

`ModifierKeyEventTap` must:

```swift
private static let eventMask =
  CGEventMask(1) << CGEventType.flagsChanged.rawValue
```

Create the tap with:

```swift
CGEvent.tapCreate(
  tap: .cgSessionEventTap,
  place: .headInsertEventTap,
  options: .listenOnly,
  eventsOfInterest: Self.eventMask,
  callback: callback,
  userInfo: Unmanaged.passUnretained(self).toOpaque()
)
```

The callback returns the original event. For `.flagsChanged`, read only:

```swift
let keyCode = UInt32(
  event.getIntegerValueField(.keyboardEventKeycode)
)
```

Map the seven constants exactly. At start/re-enable, use `CGEventSource.keyState(.combinedSessionState, key:)` for the selected virtual key to enter the unsynchronized-until-neutral state when needed. After synchronization, matching side-specific `flagsChanged` events toggle only that key's tracked state. Never infer side or release from aggregate flags because the opposite physical key may remain held. For `.tapDisabledByTimeout` and `.tapDisabledByUserInput`, resynchronize and re-enable once through `CGEvent.tapEnable`.

Use:

```swift
CGPreflightListenEventAccess()
CGRequestListenEventAccess()
```

for status/request. Tear down the `CFMachPort` and run-loop source deterministically in `stop` and `deinit`.

Publish `.unauthorized` when preflight fails, `.running` only after the tap/run-loop source is installed, `.failed` when a disabled tap cannot be re-enabled, and `.stopped` after teardown. The state callback contains no keyboard-event data.

- [ ] **Step 4: Refactor the controller around semantic transitions**

Keep the file/class name `GlobalHoldShortcut` to avoid needless runtime churn, but change its public configuration:

```swift
func configure(_ modifier: DictationModifierKey) throws
private(set) var registeredModifier: DictationModifierKey?
```

Extend `ShortcutHoldHandling`:

```swift
func beginHandsFreeShortcut(
  editor: (any FocusedDictationEditing)?,
  destination: DictationDestination?
) async -> DictationShortcutSession?
func finishHandsFreeShortcut(_ session: DictationShortcutSession) async
```

Use the existing serialized delivery task. Store:

```swift
static let doubleTapWindow = Duration.milliseconds(320)
private var lastShortRelease: ContinuousClock.Instant?
private var handsFreeSession: DictationShortcutSession?
private var ignoresReleaseAfterHandsFreeStart = false
```

On first selected-key press, call `beginShortcut`. On a short release, end that session, clear its local ownership immediately, and record the monotonic release instant; the later coordinator terminal observation becomes a no-op for that cleared session. On a second press within 320 milliseconds, start hands-free immediately and mark its matching release ignored. On the next selected-key press, finish the hands-free session. Clear tap state after timeout, reconfiguration, monitor loss, cancellation, terminal completion, and uninstall.

Expose one unified reconfiguration gate:

```swift
var canChangeModifier: Bool {
  coordinatorCanConfigure
    && !physicalPrimaryDown
    && pendingDeliveryCount == 0
    && acceptedSession == nil
}
```

A monitor `.failed` or unexpected `.stopped` state clears pending taps and cancels only the controller-owned session. It never finishes or cancels an unrelated toolbar capture.

Keep Carbon only in a narrowed `EscapeHotKeyRegistrar`.

- [ ] **Step 5: Wire runtime to the new preference**

In `DictationRuntime`, replace desired/actual chord state with `DictationModifierKey`, configure `appState.preferences.dictationModifierKey`, and preserve pending-reconfiguration-after-terminal behavior.

Expose:

```swift
var actualModifier: DictationModifierKey? {
  shortcutController.registeredModifier
}

var canChangeModifier: Bool { shortcutController.canChangeModifier }

func changeModifier(to modifier: DictationModifierKey) async -> Bool
func requestModifierMonitoringAccess() -> Bool
```

`changeModifier(to:)` requests/rechecks access first, leaves the current preference and monitor unchanged when denied, configures only when `canChangeModifier`, and persists `appState.preferences.dictationModifierKey` only after configuration succeeds.

Add one startup synchronization task:

```swift
initialLoadSynchronizationTask = Task { @MainActor [weak self, weak appState] in
  await appState?.waitUntilInitialLoad()
  guard !Task.isCancelled, let self, let appState else { return }
  self.applyLoadedModifier(appState.preferences.dictationModifierKey)
}
```

The runtime preflights but never requests Input Monitoring during ordinary startup. When access is already granted, it applies the persisted non-default modifier after load. It publishes the monitor's content-free state for Settings and awaits/cancels this task during shutdown.

- [ ] **Step 6: Run focused and full debug tests**

Run:

```bash
swift test --disable-automatic-resolution --filter GlobalHoldShortcutTests
swift test --disable-automatic-resolution --filter DictationSettingsTests
swift test --disable-automatic-resolution
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/FleckApp/ModifierKeyEventTap.swift \
  Sources/FleckApp/GlobalHoldShortcut.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/GlobalHoldShortcutTests.swift \
  Tests/FleckAppTests/DictationCoordinatorTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: add single-modifier dictation gestures"
```

---

### Task 4: Persistent Dockable Capsule

**Files:**
- Modify: `Sources/FleckApp/DictationCapsule.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/DictationAccessibilityTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Interfaces:**
- Consumes: `DictationCapsuleDock`.
- Produces:

```swift
case idle
case finalizing
case cleaning
case routing

func presentIdle(
  dock: DictationCapsuleDock,
  onOpenFleck: @escaping @MainActor () -> Void,
  onDockChanged: @escaping @MainActor (DictationCapsuleDock) -> Void
)

func render(
  _ status: DictationCapsuleStatus,
  action: DictationCapsuleAction?,
  onAction: @escaping @MainActor () -> Void
)
```

- [ ] **Step 1: Write persistent presentation and geometry RED tests**

Add idle and phase mapping:

```swift
#expect(DictationCapsuleStatus.idle.presentation.visibleText == nil)
#expect(
  DictationCapsuleStatus.idle.presentation.voiceOverText
    == "Fleck dictation ready"
)
#expect(DictationCapsuleStatus.finalizing.presentation.visibleText == "Finishing")
#expect(DictationCapsuleStatus.cleaning.presentation.visibleText == "Cleaning up")
#expect(DictationCapsuleStatus.routing.presentation.visibleText == "Finding note")
```

Add pure geometry tests:

```swift
let visible = CGRect(x: 100, y: 200, width: 1_000, height: 800)
#expect(DictationCapsuleController.frame(for: .bottom, in: visible).midX == visible.midX)
#expect(DictationCapsuleController.frame(for: .left, in: visible).minX > visible.minX)
#expect(DictationCapsuleController.frame(for: .right, in: visible).maxX < visible.maxX)
#expect(
  DictationCapsuleController.nearestDock(
    to: CGPoint(x: visible.minX, y: visible.midY),
    in: visible
  ) == .left
)
```

Test panel collection behavior includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.stationary`; `canBecomeKey` and `canBecomeMain` remain false even with a recovery action. Test saved/failure delay scheduling with injected runtime sleepers and generation/owner checks so an old timer cannot replace a newer repair/listening state.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --filter DictationAccessibilityTests
swift test --disable-automatic-resolution --filter DictationSettingsTests
```

Expected: compilation fails because idle/phase states, dock geometry, and persistent renderer APIs do not exist.

- [ ] **Step 3: Add idle and distinct processing states**

Change presentation text to optional:

```swift
struct DictationCapsulePresentation: Equatable {
  let visibleText: String?
  let voiceOverText: String
  let symbolName: String
  var isSuccess = false
}
```

Add statuses:

```swift
case idle
case listening
case finalizing
case cleaning
case routing
```

Idle uses `waveform`, no visible text, and `Fleck dictation ready`. Map the other phases to accurate copy.

- [ ] **Step 4: Make the existing panel persistent**

Keep one `DictationCapsulePanel`, add `.stationary`, and split frames:

```swift
static let idleSize = CGSize(width: 48, height: 36)
static let activeSize = CGSize(width: 280, height: 52)
static let edgeInset: CGFloat = 24
```

`presentIdle` orders the panel front and retains open/dock callbacks. `render` replaces only hosted content and animates between the dock-aware idle/active frame. It does not own return timers. `dismiss` is reserved for disabled preference and shutdown.

- [ ] **Step 5: Add drag-to-dock and context-menu fallback**

Add a narrow AppKit hosting/drag bridge that uses `window.performDrag(with:)` only from idle background interaction. After mouse-up:

```swift
let dock = Self.nearestDock(
  to: CGPoint(x: panel.frame.midX, y: panel.frame.midY),
  in: screen.visibleFrame
)
apply(dock, on: screen)
onDockChanged?(dock)
```

Expose `Dock Bottom`, `Dock Left`, and `Dock Right` context menu actions. A click with movement under four points runs `onOpenFleck`; a drag never activates Fleck.

Observe `NSApplication.didChangeScreenParametersNotification`, clamp/redock on an available visible frame, and remove the observer in teardown.

- [ ] **Step 6: Integrate persistent runtime state**

Extend Task 3's initial-load task to apply the loaded dock/visibility and call `presentIdle` if the preference is enabled. Add one runtime-owned return task and presentation generation:

```swift
private enum CapsuleOwner: Equatable {
  case idle
  case dictation
  case model(UUID)
}

private var capsuleReturnTask: Task<Void, Never>?
private var capsuleGeneration: UInt64 = 0

private func scheduleIdle(
  after delay: Duration,
  owner: CapsuleOwner
) {
  capsuleGeneration &+= 1
  let generation = capsuleGeneration
  capsuleReturnTask?.cancel()
  capsuleReturnTask = Task { @MainActor [weak self] in
    try? await Task.sleep(for: delay)
    guard
      !Task.isCancelled,
      let self,
      self.capsuleGeneration == generation,
      self.capsuleOwner == owner
    else { return }
    self.showIdleCapsule()
  }
}
```

Every new presentation first invalidates the current return task by incrementing `capsuleGeneration` and cancelling `capsuleReturnTask`. Model repair, disabled preference, and shutdown do the same. `showIdleCapsule()` sets both `capsuleOwner = .idle` and `currentCapsuleStatus = .idle` before rendering. Use 1.6 seconds for success/fallback and 3 seconds for failure. On events:

```swift
case .idle:
  capsuleController.render(.idle, action: nil, onAction: {})
case .arming, .listening:
  capsuleController.render(.listening, action: nil, onAction: {})
case .finalizing:
  capsuleController.render(.finalizing, action: nil, onAction: {})
case .cleaning:
  capsuleController.render(.cleaning, action: nil, onAction: {})
case .routing:
  capsuleController.render(.routing, action: nil, onAction: {})
```

Cancelled terminal returns immediately to idle. Runtime-owned timers update both `currentCapsuleStatus` and the rendered panel. Dock changes call:

```swift
appState.updatePreferences { $0.dictationCapsuleDock = dock }
```

Clicking idle activates Fleck and opens the existing notes panel. Disabling the preference orders out; re-enabling immediately restores idle at the stored dock.

A startup regression must load a non-default dock and disabled capsule preference before the panel is first shown. Do not render an idle capsule with defaults and then jump after `AppState` loads.

- [ ] **Step 7: Run focused and full debug tests**

Run:

```bash
swift test --disable-automatic-resolution --filter DictationAccessibilityTests
swift test --disable-automatic-resolution --filter DictationSettingsTests
swift test --disable-automatic-resolution
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/FleckApp/DictationCapsule.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/DictationAccessibilityTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: keep dictation capsule visible and dockable"
```

---

### Task 5: Settings, Input Monitoring Recovery, and Release Gates

**Files:**
- Modify: `Sources/FleckApp/DictationAvailability.swift`
- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/DictationAvailabilityTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`
- Modify: `README.md`
- Modify: `TESTING.md`

**Interfaces:**
- Consumes: Tasks 1–4 preferences, monitor status/request, runtime reconfiguration, and docked persistent panel.
- Produces: native modifier picker, Input Monitoring recovery UI, accurate documentation, and release evidence.

- [ ] **Step 1: Write Settings and permission presentation RED tests**

Extend the privacy pane:

```swift
#expect(
  DictationPrivacyPane.inputMonitoring.url.absoluteString
    == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
)
#expect(
  DictationSystemSettingsAction(pane: .inputMonitoring).title
    == "Open Input Monitoring Settings"
)
```

Add a pure presentation model test:

```swift
let presentation = DictationModifierSettingsPresentation(
  selected: .rightOption,
  monitorStatus: .running,
  canChange: true
)
#expect(presentation.rows.count == 7)
#expect(presentation.recommended == .rightOption)
#expect(presentation.statusCopy == "Input Monitoring enabled")
```

Cover denied, unavailable, retry, active-capture-disabled, and Fn best-effort copy. Assert the UI source no longer instantiates `DictationShortcutRecorder`.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --filter DictationAvailabilityTests
swift test --disable-automatic-resolution --filter DictationSettingsTests
```

Expected: compilation fails because Input Monitoring and modifier settings presentation do not exist.

- [ ] **Step 3: Add Input Monitoring recovery action**

Extend:

```swift
enum DictationPrivacyPane: Hashable, Sendable {
  case microphone
  case speechRecognition
  case inputMonitoring
}
```

Map Input Monitoring to:

```swift
URL(
  string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
)!
```

Keep it separate from speech-engine availability; modifier permission failure must not mark microphone/on-device speech unavailable.

- [ ] **Step 4: Replace the chord recorder with a native picker**

Use:

```swift
Picker("Modifier key", selection: dictationModifierBinding) {
  ForEach(DictationModifierKey.allCases, id: \.self) { key in
    Text(
      key == .rightOption
        ? "\(key.displayName) — Recommended"
        : key.displayName
    ).tag(key)
  }
}
```

The binding:

```swift
private var dictationModifierBinding: Binding<DictationModifierKey> {
  Binding(
    get: { appState.preferences.dictationModifierKey },
    set: { modifier in
      Task { @MainActor in
        guard await runtime.changeModifier(to: modifier) else { return }
        await runtime.requestPermissionsAfterShortcutSetup()
        recoveryActions = runtime.recoveryActions()
      }
    }
  )
}
```

`changeModifier(to:)` requests Input Monitoring if necessary, applies the monitor configuration, and only then persists the selected modifier. A failed or cancelled authorization leaves both the active and stored modifier unchanged. Disable the picker while `!runtime.canChangeModifier`. Show:

- Authorized: `Input Monitoring enabled`.
- Denied: explanatory copy plus `Open Input Monitoring Settings`.
- Failed after grant: explanatory copy plus `Retry`.
- Fn: best-effort hardware note.
- Command/Control/Left Option: conflict warning.

Remove `DictationShortcutRecorder` and its tests after all runtime references are gone.

- [ ] **Step 5: Update documentation and manual gates**

README must describe:

- persistent bar;
- Right Option default;
- hold and double-tap behaviors;
- Input Monitoring observes modifier transitions only;
- on-device cleanup/title-only routing;
- capsule toggle and docking.

TESTING must list physical/manual checks from the spec, including left/right keys, Fn keyboards, permission lifecycle, ordinary modifier conflicts, Spaces/full-screen/multiple displays, sleep/wake, VoiceOver, Reduce Motion, cleanup, routing, and Inbox fallback.

- [ ] **Step 6: Run repository gates**

Run:

```bash
swift test --disable-automatic-resolution
swift build -c release --disable-automatic-resolution --product Fleck
swift build -c release --disable-automatic-resolution --product fleck-agent
./scripts/validate_macos.sh
git diff --check
```

Expected:

- All Swift tests pass.
- Both release products build.
- macOS validation passes its ordinary graph, privacy boundary, package inspection, and candidate rejection checks.
- No whitespace errors.

- [ ] **Step 7: Commit**

```bash
git add Sources/FleckApp/DictationAvailability.swift \
  Sources/FleckApp/SettingsView.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/DictationAvailabilityTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift \
  README.md TESTING.md
git commit -m "feat: finish persistent modifier dictation experience"
```

---

## Final Review and Verification

- [ ] Generate a whole-branch diff package from the pre-spec baseline through `HEAD`.
- [ ] Run an independent review focused on modifier permission/lifecycle, gesture races, one-session ownership, panel activation/focus, stale timers, docking persistence, and privacy boundaries.
- [ ] Fix every Critical or Important finding in one bounded test-first correction wave.
- [ ] Re-run focused tests covering every fix.
- [ ] Re-run:

```bash
swift test --disable-automatic-resolution
swift build -c release --disable-automatic-resolution --product Fleck
swift build -c release --disable-automatic-resolution --product fleck-agent
./scripts/validate_macos.sh
git diff --check
git status --short --branch
```

- [ ] Record physical-only validation as still manual unless it was actually performed on the user's Mac with Input Monitoring, microphone, Apple Intelligence, multiple Spaces/displays, and accessibility settings.
