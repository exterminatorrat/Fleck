# Fleck Audio Waveform, Collapsible Toolbar, and Window Sizing Design

Date: 2026-08-05
Status: Approved architecture; awaiting written-spec review

## Objective

Improve Fleck's existing note and dictation surfaces without replacing their architecture:

- Make the listening waveform respond only to real microphone energy, with visibly different heights for quieter and louder speech.
- Let users collapse and restore the rich-text formatting bar directly from the editor.
- Increase the menu-bar notes panel's comfortable default width from 520 to 640 points.
- Make only the pinned Fleck window resize like a normal macOS window and remember its own size.

The result remains a native SwiftUI/AppKit menu-bar notes app. The production `NotesPanel`, `DictationWaveformModel`, `NSTextView` editor, `AppPreferences`, and pinned `Window` scene remain the owning surfaces.

## Approved Product Behavior

### Truthful Audio Waveform

The listening capsule retains its recording dot and elapsed timer. Those elements communicate that capture is active even during silence.

The eleven waveform bars no longer receive a time-driven moving baseline. At or below the microphone noise floor, the bars remain at a small, static minimum height. Above the noise floor:

- normalized RMS controls total bar height;
- quieter speech produces smaller bars than louder speech;
- the existing center-weighted shape is retained;
- attack remains faster than release so speech feels responsive without jitter;
- release returns smoothly to the static minimum instead of continuing decorative motion;
- Reduce Motion keeps the same truthful amplitude response because amplitude is status information, not decorative positional animation.

Audio callbacks remain scalar levels only. Fleck does not retain audio buffers, add audio logging, or infer speech content from the visualizer.

### Collapsible Formatting Bar

Add one compact toggle to the existing `NotesPanel` header, near the other editor/window controls. Its icon points toward the resulting state and its accessible label is explicit: `Hide formatting controls` while expanded and `Show formatting controls` while collapsed.

The toggle reuses `AppPreferences.showFormattingBar`, which already persists and is already exposed in Settings. When collapsed, the complete formatting bar is removed so it consumes no vertical space. The header toggle remains reachable, so the user is never trapped in the collapsed state.

The preference is shared between the menu-bar and pinned note presentations, matching the existing Settings behavior. Formatting commands, keyboard shortcuts, editor selection, typing attributes, undo history, and stored rich text are unchanged.

The transition is short and native. With Reduce Motion enabled, the visibility change is immediate or opacity-only; no movement is required.

### Menu-Bar Panel Width

The menu-bar notes panel uses a 640-by-430-point default. It remains a stable `MenuBarExtra` window and does not receive custom resize handles or fake window chrome.

Existing users whose saved dimensions are exactly Fleck's untouched legacy default of 520 by 430 points migrate once to 640 by 430 points. Any other saved width or height is treated as a user customization and is preserved. A persisted sizing-version marker distinguishes the one-time migration from a later explicit choice of 520 points.

The formatting bar remains a single horizontal command surface. Horizontal scrolling stays as the supported fallback for deliberately narrow custom widths and accessibility enlargement; the 640-point default reduces routine sideways scrolling without hiding or regrouping commands.

### Independently Resizable Pinned Window

Only the pinned Fleck window becomes natively resizable from its edges and corners. It starts at 640 by 430 points for new or migrated preferences and remembers its last user-selected size across relaunches.

Pinned-window dimensions are stored separately from the menu-bar panel dimensions. Resizing the pinned window never changes the menu-bar popover. Opening the pinned window again restores its pinned dimensions.

The completed pinned notes window uses:

- a minimum content size of 480 by 320 points, large enough to keep the header, selected tab, title, and editor usable;
- a practical maximum enforced by the current screen rather than a fixed application cap;
- the existing fixed onboarding size and minimum while onboarding is active;
- native macOS resizing rather than a custom drag gesture.

Window-size observation writes only after an actual completed-state resize and is coalesced so continuous dragging does not trigger excessive disk writes. Programmatic onboarding-to-notes sizing must not be mistaken for a user resize.

## Architecture and Data Flow

### Waveform

`audio engine RMS -> existing level callback -> DictationRuntime active-session guard -> DictationCapsuleController visibility guard -> DictationWaveformModel smoothing -> eleven native SwiftUI bars`

No new timer, capture session, audio service, or waveform state store is introduced. `TimelineView` may continue supplying render timestamps for the elapsed timer, but zero energy produces identical bar levels at different timestamps.

### Toolbar

`NotesPanel header toggle -> AppState.updatePreferences -> AppPreferences.showFormattingBar -> existing conditional FormattingBar`

The `NSTextView` remains the sole formatting source of truth. Collapsing chrome does not detach, recreate, or mutate the editor command state.

### Window Sizes

`menu panel -> existing panelWidth/panelHeight`

`pinned NSWindow completed-state resize -> narrow window-size observer -> pinnedPanelWidth/pinnedPanelHeight`

The existing preference snapshot remains the sole persistent configuration document. Decoding older preferences supplies backward-compatible defaults and applies the one-time untouched-size migration. No database migration or new persistence file is added.

## Interfaces and Invariants

- `SpeechEngine.start(provisional:level:)` and all capture-session lifecycle guards remain unchanged.
- Obsolete, inactive, hidden, canceled, and completed capture sessions cannot animate the waveform.
- Silence is represented honestly; the recording dot and timer remain visible while listening.
- `NotesPanel`, `FormattingBar`, `EditorCommands`, `NativeRichTextEditor`, and `NSTextView` retain their existing responsibilities.
- `showFormattingBar` remains backward-compatible and Settings continues to control the same preference.
- Existing custom menu-panel sizes are preserved.
- Pinned-window resizing never mutates menu-panel dimensions.
- Onboarding retains its current 1080-by-700 default and 760-by-520 minimum.
- Note content, RTF sidecars, selection, focus, undo/redo, and agent/dictation insertion are unaffected by window or toolbar state.
- No note text, audio levels, precise window history, or other sensitive content is logged.

## Constraints and Non-Goals

- Preserve Fleck's current architecture; do not replace the production editor, waveform pipeline, or scene structure.
- Use native SwiftUI/AppKit behavior and existing persistence. Add no dependency.
- Do not group, remove, reorder, or redesign formatting commands.
- Do not make the menu-bar popover user-resizable.
- Do not make menu and pinned window sizes share live resize state.
- Do not alter dictation recognition, transcription, routing, or saved audio behavior.
- Do not add voice-activity detection, calibration UI, gain controls, or microphone-specific profiles.
- Do not broaden the change into unrelated window-management or toolbar cleanup.

## Failure and Recovery Behavior

- Missing or malformed new sizing fields decode to safe defaults without blocking Fleck startup.
- Invalid persisted dimensions are clamped to the supported minimum and the available screen before presentation.
- If a screen is removed or its resolution changes, normal macOS window placement and existing presentation logic keep the pinned window reachable; its next valid completed-state size becomes the persisted size.
- If no new audio level arrives, smoothed energy decays to the static minimum rather than freezing at a loud value.
- Hiding and restoring the formatting bar does not fabricate save success or change note persistence state.

## Verification

### Automated

- Waveform tests prove:
  - two silent timestamps produce identical minimum bar levels;
  - below-noise-floor input remains visually quiet;
  - soft, medium, and loud RMS inputs produce strictly increasing displayed energy;
  - attack, release, throttling, clamping, eleven-bar shape, reset, and elapsed time remain correct;
  - Reduce Motion does not introduce fabricated silence movement.
- Runtime tests retain active/visible/session guards for forwarded audio levels.
- Preference tests prove:
  - new menu and pinned defaults are 640 by 430;
  - untouched legacy 520-by-430 preferences migrate once;
  - custom legacy dimensions remain unchanged;
  - an explicit post-migration 520-point choice round-trips without remigration;
  - pinned and menu dimensions round-trip independently;
  - malformed or out-of-range sizes clamp safely.
- Source/component tests prove:
  - the header always exposes an accessible formatting-bar toggle;
  - the existing `FormattingBar` conditional still uses `showFormattingBar`;
  - the menu-bar panel has no custom resize gesture;
  - the completed pinned window uses container sizing and the narrow native window-size bridge;
  - onboarding sizing remains unchanged.
- Focused editor tests confirm toolbar visibility changes do not mutate text or rich-text state.
- Run focused tests, the deterministic full Swift test suite, `Scripts/validate-macos.sh`, and GitHub CI.

### Packaged macOS Validation

Using the exact packaged `.build/Fleck.app` and only designated QA notes:

1. Start dictation in a quiet room and confirm bars remain still at their minimum while the recording dot and timer continue.
2. Speak softly, normally, and loudly; confirm visibly increasing amplitudes and a smooth return to rest.
3. Repeat with Reduce Motion enabled.
4. Collapse and restore the formatting bar from the header; verify the bar consumes no collapsed space and formatting state persists.
5. Relaunch and confirm the toolbar preference persists.
6. Confirm the menu-bar panel opens at 640 by 430 and remains a normal non-resizable popover.
7. Open the pinned window, resize from edges and corners, close and reopen it, and confirm its size persists.
8. Confirm pinned resizing never changes the menu-bar panel size.
9. Verify minimum-size behavior, Light/Dark appearances, keyboard navigation, VoiceOver labels, editor focus, typing, undo/redo, and dictation insertion.

## Residual Risk

Microphone RMS ranges vary by hardware, input gain, distance, and ambient noise. The existing normalized scalar pipeline and conservative noise floor should provide honest relative motion, but packaged testing should cover at least the active built-in microphone and one user-selected external microphone when available. Multi-display window restoration and older supported macOS versions remain manual platform boundaries.
