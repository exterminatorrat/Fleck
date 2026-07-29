# Fleck Persistent Dictation Bar Design

## Summary

Fleck will turn its event-only dictation capsule into a persistent, compact desktop bar inspired by the interaction model of Wispr Flow. While Fleck is running and the capsule preference is enabled, the bar remains visible without activating Fleck or taking keyboard focus.

The bar is paired with one side-specific modifier key. Right Option is the default. Holding the configured key starts push-to-talk dictation and releasing it finishes the capture. Double-tapping the key starts hands-free dictation; pressing it once again finishes the hands-free capture. Escape cancels either active capture.

The existing private Clean Dictation pipeline remains authoritative:

`capture → on-device transcript → faithful cleanup → title-only routing → note append`

This project changes the trigger and feedback experience. It does not broaden what Fleck reads, where it writes, or what leaves the Mac.

## Goals

- Keep a restrained Fleck dictation control visible across macOS Spaces while Fleck runs.
- Make dictation reachable through one physical modifier key rather than a multi-key chord.
- Distinguish left and right Command, Option, and Control keys.
- Support both hold-to-talk and double-tap hands-free behavior through the same configured key.
- Keep the current on-device cleanup and conservative title-only Smart Capture routing.
- Let the bar be dragged and docked to the bottom, left, or right edge.
- Remember the selected dock edge between launches.
- Preserve Fleck's non-activating, local-first, no-transcript-overlay behavior.
- Maintain the macOS 14 minimum.

## Non-Goals

This project will not:

- Dictate into other applications.
- Read foreground application content or infer routing from another app.
- Read note bodies for routing.
- Display live transcript text over another application.
- Add cloud speech, cleanup, routing, analytics, or telemetry.
- Add a shortcut hint to the idle bar.
- Add a full keyboard-event recorder, command mode, snippets, or arbitrary voice actions.
- Add a second always-visible panel per display.
- Recreate Wispr Flow's visual identity, branding, or complete feature set.
- Implement free-form placement. Dragging always resolves to one of three supported dock edges.
- Add Shift as a trigger. A standalone Shift trigger would interfere with ordinary capitalization too often.

## User Experience

### Idle

When Fleck finishes startup and `Show status capsule` is enabled, one compact capsule appears:

- It uses a native material and Fleck's existing crisp macOS styling.
- It shows only a small waveform/Fleck mark. It shows no shortcut hint or transcript.
- It is visible on every Space through one non-activating floating panel.
- A click activates Fleck and opens its notes panel.
- A drag moves the capsule. Releasing snaps it to the nearest supported edge.

The idle capsule is 48 by 36 points at the bottom dock and uses the equivalent compact vertical footprint on a side dock.

### Hold-to-Talk

1. Press the configured modifier key.
2. Fleck enters its existing 180-millisecond arming threshold.
3. If the key is released before the threshold, no capture is saved.
4. If the key remains down, the bar expands and shows listening feedback.
5. Releasing the key finalizes, cleans, routes, and saves.
6. The bar briefly shows the destination, then returns to idle.

### Hands-Free

1. Press and release the configured modifier key twice within 320 milliseconds, with each tap shorter than the 180-millisecond hold threshold.
2. Fleck begins listening immediately after the second tap.
3. The key no longer needs to remain held.
4. Pressing the same configured modifier once again finishes the capture.
5. Escape cancels without inserting text.

Input is ignored while Fleck is finalizing, cleaning, routing, saving, or shutting down. A double-tap can never create a second overlapping capture.

### Cleanup and Routing

Focused Dictation and Smart Capture keep the existing behavior:

- If Fleck's note body is the current text editor, dictated text is inserted at that editor selection.
- Otherwise, Smart Capture cleans the transcript on-device when Apple Foundation Models are available.
- Smart Capture routes from the cleaned transcript against active note titles only.
- Ambiguous, unavailable, invalid, or failed routing uses Inbox.
- On systems without local cleanup/routing support, Fleck preserves the raw transcript and saves conservatively to Inbox.

### Statuses

The persistent bar presents:

- Idle: compact mark only.
- Arming/listening: expanded waveform and `Listening`.
- Finalizing/cleanup/routing: expanded progress state with accurate phase copy.
- Saved: destination and recovery action for 1.6 seconds.
- Saved without cleanup: explicit raw-fallback copy for 1.6 seconds.
- Failure: concise error for 3 seconds.
- Model repair: existing repair feedback.

After every transient state, the bar returns to idle instead of disappearing. Reduce Motion uses opacity-only transitions.

## Modifier Key Model

Fleck supports these physical keys:

- Fn
- Left Command
- Right Command
- Left Option
- Right Option
- Left Control
- Right Control

Right Option is the default for new and migrated preferences.

The persisted model stores a semantic key, not raw Carbon flags:

```swift
public enum DictationModifierKey: String, Codable, CaseIterable, Sendable {
  case function
  case leftCommand
  case rightCommand
  case leftOption
  case rightOption
  case leftControl
  case rightControl
}
```

The existing chord-based `DictationShortcut` is legacy data. The preferences decoder accepts old files, ignores the obsolete chord for activation, and supplies Right Option when the new key is absent. New preference writes use `dictationModifierKey`.

Settings replaces the chord recorder with a native picker showing the exact physical side. Copy below the picker explains that modifier-only shortcuts can conflict with normal use of that modifier; Right Option is recommended.

Fn is best-effort because some keyboards or system settings may consume it before Fleck receives an event. Settings must not claim Fn is active until the modifier monitor starts successfully.

## Modifier Event Boundary

Carbon hot-key registration cannot represent a modifier-only, side-specific key. Fleck will use a passive Core Graphics session event tap for `flagsChanged` events only.

The event boundary:

- Requests macOS Input Monitoring only after the user enables or changes the modifier trigger.
- Reads only modifier transition events.
- Uses the event virtual key code to distinguish left and right physical keys.
- Passes every event through unchanged.
- Never subscribes to ordinary `keyDown` or `keyUp` events.
- Never stores, logs, or exposes keyboard events.
- Performs constant-time mapping in the event-tap callback and forwards semantic press/release events to the main actor.
- Re-enables itself after timeout/user-input disable notifications.
- Tears down its run-loop source and event tap deterministically during shutdown.

Because the privacy boundary intentionally excludes ordinary key events, Fleck cannot determine whether the chosen modifier is being held as part of another keyboard shortcut. Settings warns that Command, Control, and Left Option are more likely to conflict. Right Option remains the default.

On installation or reconfiguration, if the selected modifier family is already physically down, the monitor remains unsynchronized until that family returns to neutral. A release can never be mistaken for a new press.

Input Monitoring denial, revocation, or event-tap failure leaves the bar visible but disables modifier activation. Settings provides `Open Input Monitoring Settings` and `Retry`.

Escape cancellation continues through the existing capture-scoped Carbon registration. Escape is registered only while Fleck owns an accepted dictation session and is removed at terminal completion.

## Gesture State Machine

A new modifier gesture controller owns input interpretation independently of transcription:

`idle → firstPress → holding | firstTap → handsFree → finishing → idle`

Rules:

- Duplicate down/up events are ignored.
- A first press immediately creates the existing coordinator shortcut session so the established 180-millisecond hold behavior remains authoritative.
- A short first release cancels that session and records one tap.
- A second press within 320 milliseconds starts one immediate hands-free shortcut session instead of another armed hold session.
- Releasing the second tap does not finish hands-free capture.
- The next press of the selected key finishes the owned hands-free session; its matching release is consumed by the gesture state machine.
- Escape cancels the owned hold or hands-free session.
- Reconfiguration waits until no session, pending delivery, or physical modifier press is active.
- Monitor loss cancels pending taps and safely cancels an active owned capture.
- All event delivery is serialized, preserving the coordinator's one-capture invariant.

Timing uses an injected monotonic clock/sleeper in tests. Wall-clock changes do not affect gesture recognition.

## Persistent Capsule Architecture

`DictationCapsulePanel` remains the single long-lived AppKit object. It stays:

- Borderless.
- Non-activating.
- Floating.
- Visible across Spaces.
- Available alongside full-screen applications.
- Opaque only through native material content.
- Unable to become the main window.

`DictationCapsuleController` becomes a persistent state renderer rather than a show/dismiss toast controller.

```swift
enum DictationCapsuleDock: String, Codable, CaseIterable, Sendable {
  case bottom
  case left
  case right
}
```

The controller receives the stored dock and an `onDockChanged` callback. It:

- Shows idle once startup/preferences synchronization finishes.
- Renders transient statuses without creating another panel.
- Returns to idle after bounded saved/failure delays.
- Snaps to the nearest supported edge after a drag.
- Uses bottom-center, left-center, or right-center frames inset from the screen's visible frame.
- Changes to a vertical layout for side docks.
- Persists only the dock edge, not an unstable display identifier.
- Falls back to the active/pointer/primary display when the previous screen no longer exists.
- Clamps every frame to the current visible screen after display configuration changes.

Dragging is available from the idle bar background. Buttons in transient recovery states remain clickable and do not start a drag.

When the capsule preference is disabled, the panel is ordered out and the modifier trigger may continue to work. Re-enabling the preference immediately restores the idle bar.

## Persistence

`AppPreferences` adds:

```swift
public var dictationModifierKey: DictationModifierKey
public var dictationCapsuleDock: DictationCapsuleDock
```

Defaults:

- `dictationModifierKey = .rightOption`
- `dictationCapsuleDock = .bottom`
- `dictationCapsuleEnabled = true`

Missing keys decode to those defaults. Unknown future enum values fail only that preferences load through the existing recovery behavior; no note data is affected.

Dock changes use the existing AppState preference update and debounced persistence path. The panel moves immediately before disk I/O completes.

## Settings

The Dictation settings section includes:

- `Modifier key` picker with all supported physical keys.
- Recommended label beside Right Option.
- Input Monitoring status.
- `Open Input Monitoring Settings` when denied or revoked.
- `Retry` when the monitor could not start.
- Existing speech engine, microphone, history, and capsule settings.
- Existing `Show status capsule` toggle.

Changing the modifier:

1. Finishes or cancels no active capture.
2. Is disabled while a capture or recovery action is active.
3. Tears down the previous monitor after the selected key is neutral.
4. Persists the new preference.
5. Requests/rechecks Input Monitoring.
6. Starts the new monitor or surfaces a recoverable error.

## Accessibility and Motion

- Idle VoiceOver label: `Fleck dictation ready`.
- Listening, processing, saved, fallback, repair, and failure keep concise phase labels.
- The idle bar's click action is `Open Fleck`.
- Recovery buttons remain keyboard and VoiceOver accessible.
- Dragging has a context menu fallback with `Dock Bottom`, `Dock Left`, and `Dock Right`.
- Reduce Motion uses opacity-only state changes and immediate dock snapping.
- Normal motion uses the existing crisp 80–160 millisecond easing range.
- No status change moves keyboard focus into the bar.

## Failure Handling

- Input Monitoring unavailable: keep idle bar visible, show recoverable Settings status, do not fall back to a broader monitor.
- Event tap disabled: re-enable once; if it fails again, stop the monitor and surface Retry.
- Selected modifier held during startup/reconfiguration: wait for neutral.
- Short single tap: no dictation and no error.
- Microphone/speech failure: use existing recovery copy and return to idle after the failure interval.
- Cleanup failure: save the raw transcript and label the result accurately.
- Routing failure or ambiguity: save to Inbox.
- App shutdown: cancel active/pending gesture work, cancel capture safely, stop the event tap, then dismiss the panel.
- Screen removal or resolution change: clamp and redock on an available screen.

## Testing

Automated tests cover:

- Default and backward-compatible preference decoding.
- Every physical modifier key mapping.
- Left/right independence within the same modifier family.
- Held-on-install neutral synchronization.
- Duplicate, reordered, and rapid transition handling.
- 180-millisecond hold threshold.
- 320-millisecond double-tap window.
- Short single tap no-op.
- Double-tap immediate hands-free start.
- Single selected-key press finishes hands-free.
- Escape cancellation.
- Reconfiguration and monitor-loss cancellation.
- Input Monitoring denied/retry presentation.
- Event tap lifecycle and timeout re-enable behavior through an injected adapter.
- Idle capsule presentation and VoiceOver copy.
- Persistent idle rendering after startup, save, failure, cancellation, and recovery actions.
- Bottom/left/right frame calculation, orientation, snap selection, and screen clamping.
- Dock persistence and old-preference defaults.
- Disabled capsule behavior.
- Reduce Motion transitions.
- Existing cleanup, focused insertion, title-only routing, Inbox fallback, and history behavior.

Manual macOS validation covers:

- Right Option default on a physical Mac keyboard.
- Every left/right Command, Option, and Control key.
- Fn on built-in and external keyboards where available.
- Input Monitoring grant, denial, revocation, retry, app restart, sleep, and wake.
- Ordinary modifier use and documented conflict behavior.
- Hold, short tap, double-tap hands-free, finish, and Escape.
- Fleck foreground/background behavior.
- All Spaces, full-screen apps, multiple displays, display removal, and docking.
- VoiceOver, Reduce Motion, keyboard access, and recovery actions.
- Cleanup and routing on supported Apple Intelligence hardware.

## Acceptance Criteria

- While Fleck runs and the capsule toggle is enabled, exactly one idle bar remains visible across Spaces.
- The idle bar shows no shortcut hint and no transcript.
- Right Option is the default modifier for new and migrated preferences.
- Left/right Command, Option, and Control are distinct choices; Fn is available best-effort.
- Holding the selected key beyond 180 milliseconds records until release.
- Double-tapping within 320 milliseconds starts hands-free recording.
- Pressing the selected key once finishes hands-free recording.
- Escape cancels any owned capture.
- The trigger observes modifier transitions only and never observes ordinary key events.
- Dictation cleanup and routing remain entirely on-device and retain title-only/Inbox boundaries.
- Dragging docks the bar to bottom, left, or right and persists that edge.
- Transient status always returns to idle rather than hiding the bar.
- The bar never activates Fleck except when the user explicitly clicks `Open Fleck`.
- Focused and full automated tests pass, and physical-device-only boundaries remain explicitly documented.
