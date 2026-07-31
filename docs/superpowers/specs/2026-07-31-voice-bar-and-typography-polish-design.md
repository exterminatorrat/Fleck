# Fleck Voice Bar and Typography Polish Design

## Summary

Fleck will replace its static listening symbol with a compact, live audio-reactive waveform and give the note canvas a warmer default reading voice.

The persistent dictation control remains a native, non-activating AppKit panel. While listening at the bottom edge, it becomes a 196-by-32-point pill containing only a recording indicator, a smoothed multi-bar waveform, and elapsed time. It stays open through silent thinking pauses, keeps the same height during finalization and routing, and returns to a smaller idle mark after the transient result.

Fleck's controls, settings, tabs, and toolbar remain in the native macOS system typeface. Note titles and default note bodies move to Avenir Next, with a relaxed 17-point reading rhythm. Existing explicit font choices remain intact.

## Goals

- Make the listening state visibly react to the user's real microphone energy.
- Reduce the dictation bar's vertical footprint so it obscures less content.
- Keep the active bar visibly alive through natural speaking pauses.
- Make listening, processing, success, and failure feel like one continuous motion system.
- Improve long-form note readability without making the application chrome less native.
- Preserve user font customization and rich-text formatting.
- Preserve Fleck's existing dictation, cleanup, routing, recovery, docking, privacy, and accessibility behavior.

## Non-Goals

This work will not:

- Change speech recognition, cleanup, routing, or note selection behavior.
- Display transcript content in the floating bar.
- Copy Wispr Flow's branding, artwork, or exact animation assets.
- Add a new animation dependency, video asset, Lottie runtime, Metal renderer, or cloud service.
- Redesign the notes panel, formatting toolbar, Settings navigation, tabs, or checklist control.
- Force Avenir Next over an explicit custom font selection.
- Rewrite explicitly formatted rich-text runs merely to enforce the new default.
- Add new typography controls beyond the existing font-family and font-size preferences.

## Approved Visual Direction

### Persistent Idle State

The bottom-docked idle control is 40 by 26 points. It contains a quiet Fleck waveform mark with no shortcut hint, label, or transcript. It remains clickable and draggable through the existing hosting view.

The left- and right-docked forms preserve the same 26-point intrusion into screen content. Dock changes, multi-display behavior, Spaces behavior, and right-click docking remain unchanged.

### Listening State

At the bottom dock, listening expands to 196 by 32 points. Its contents are:

1. A seven-point accent recording dot.
2. An eleven-bar waveform.
3. A compact monospaced elapsed timer.

There is no persistent `Listening` label. Motion, the recording dot, and elapsed time communicate the active state while VoiceOver continues to announce `Dictation listening`.

At a side dock, the control is 32 points deep and grows along the display edge. Its waveform follows the dock orientation. The side treatment prioritizes minimal screen intrusion and omits visible phase copy that cannot fit legibly; VoiceOver still exposes the complete status.

### Thinking Pauses

Silence does not collapse, stop, or relabel the bar. The waveform eases toward a subtle moving baseline so the session still appears alive. When speech resumes, the bars respond immediately without a hard visual jump.

### Processing and Completion

Releasing the modifier keeps the pill at 32 points high:

- Finalizing: the waveform compresses into three traveling progress points.
- Cleaning: the progress points gain a restrained accent shimmer.
- Routing: the same progress treatment continues without resetting the animation.
- Saved: progress morphs into a checkmark.
- Failure: progress morphs into an exclamation mark using the existing error color semantics.

The bottom bar may lengthen horizontally for short phase, destination, or recovery copy, up to the existing 280-point maximum. It never grows taller. Side-docked states lengthen along the edge and favor symbols over text.

Success, fallback, failure, recovery actions, idle-return durations, and status ownership remain governed by `DictationRuntime`.

## Audio-Reactive Motion

The existing speech engines already emit normalized RMS microphone levels, but `DictationCoordinator` currently discards them. The coordinator will expose only the current normalized level through a dedicated, ephemeral callback. Audio levels are:

- Never persisted.
- Never included in dictation history.
- Never exposed to agents.
- Never logged.
- Reset to zero when listening ends or capture fails.

A small waveform model converts normalized RMS into display energy:

- Clamp input to `0...1`.
- Apply a low noise floor so ambient noise does not produce a fully active waveform.
- Use a fast attack and slower decay so speech feels immediate without jitter.
- Cap visual updates at 30 frames per second.
- Maintain a low-amplitude deterministic baseline while silent.
- Apply stable per-bar weights so the eleven bars form a balanced center-weighted shape instead of moving identically.

The waveform is rendered with native SwiftUI shapes inside the existing panel. It does not create eleven independently scheduled timers. One display tick updates the shared energy and phase.

Reduce Motion removes bar-height interpolation, pill resizing animation, and symbol morphing. It retains a low-rate level indication and uses opacity changes so listening state remains perceivable. Reduce Transparency continues to use a solid high-contrast fallback rather than depending on material blur.

## State and Ownership Boundaries

`SpeechEngine.start` remains the source of microphone levels. `DictationCoordinator` owns capture validity and ignores levels from stale capture identifiers. `DictationRuntime` forwards valid levels only while its authoritative phase is listening. `DictationCapsuleController` owns the view model used by the one long-lived panel.

The level path is separate from phase events:

`speech engine level → active capture check → runtime → capsule waveform model`

Frequent level updates therefore do not rebuild dictation history, mutate application state, or create new capsule windows. Phase transitions still flow through the existing coordinator event observer.

When the panel is disabled, dismissed, shutting down, or no longer listening, its display updates stop. Re-enabling the capsule replays the current authoritative phase without reviving an old audio level.

## Typography

### Interface Chrome

Fleck's application chrome remains native SF Pro through SwiftUI's semantic text styles. Buttons, settings, tabs, menus, banners, status copy, and formatting controls are not changed to Avenir Next.

### Note Canvas

The default note canvas uses:

- Title: Avenir Next Semibold at the existing semantic title scale.
- Body: Avenir Next Regular at 17 points.
- Default baseline rhythm: approximately 27 points for ordinary body paragraphs.
- Existing text color, background color, selection color, and accent preferences.

The title and body share one reading voice, while weight and size maintain hierarchy.

The body rhythm is a default paragraph treatment, not a destructive normalization pass. Explicit list indentation, checklist layout, custom paragraph styles, font traits, pasted rich text, and user-selected fonts remain authoritative. Newly inserted plain text, dictated text, agent-appended text, and newly created plain notes use the same preference-derived default.

### Preference Migration

New preferences default to Avenir Next and 17 points.

Existing preferences gain a backward-compatible typography migration marker:

- If the marker is absent and both the family and size equal Fleck's old untouched defaults (`.AppleSystemUIFont`, 15 points), migrate to Avenir Next at 17 points.
- If either the family or size differs, preserve the user's values.
- After migration, persist the marker. If the user later chooses System and 15 points, that explicit choice is retained.

Older preference files do not record whether selecting the exact old System/15 combination was deliberate. That state is indistinguishable from an untouched default. Fleck will migrate that exact combination once and keep the System family available so the user can immediately choose it again.

The migration does not rewrite every embedded RTF font run. Existing explicitly formatted RTF remains unchanged; plain notes and future unformatted typing use the new defaults.

If Avenir Next cannot be resolved, Fleck falls back to the macOS system font without changing the saved family preference or crashing.

## Accessibility

- The panel remains non-activating and never steals keyboard focus.
- VoiceOver labels remain phase-accurate even when compact side-docked states omit visible text.
- The listening timer is not announced on every update.
- Success and failure announcements occur only on state transitions.
- Recording state is not communicated by color alone.
- Reduce Motion and Reduce Transparency follow the behavior described above.
- Avenir Next remains user-replaceable, and the existing 10-to-36-point size control remains available.

## Performance and Reliability

- Waveform rendering stops when the panel is hidden or the app shuts down.
- Audio-level callbacks from obsolete capture sessions are ignored.
- Visual update frequency is bounded independently of audio-buffer frequency.
- The view model receives scalar levels only, never audio buffers.
- Capsule frame changes retain the current display, docking, ownership, and generation guards.
- Typography changes must not replace text storage, move the insertion caret, disturb undo history, or reintroduce stale editor-model reloads.

## Validation

Automated coverage will verify:

- RMS smoothing, clamping, silence baseline, stable bar weights, and reset behavior.
- Stale capture levels cannot animate a newer or finished session.
- Listening uses the 196-by-32-point bottom frame and the 32-point side intrusion.
- Idle uses the compact 40-by-26-point frame.
- Processing and terminal states never exceed 32 points in thickness.
- Reduce Motion selects the reduced transition behavior.
- Capsule accessibility remains accurate without a visible listening label.
- Old untouched preferences migrate once to Avenir Next/17.
- Custom family or size choices remain unchanged.
- Re-selecting System after migration is retained.
- Missing Avenir Next falls back safely.
- Titles use Avenir Next Semibold while interface chrome remains semantic system type.
- Plain, dictated, and agent-appended content share the preference-derived default.
- Explicit rich-text fonts, list paragraph styles, checklist geometry, selection, undo, and typing stability are preserved.

Manual macOS validation will cover:

- Speaking softly, loudly, quickly, and with long thinking pauses.
- Hold-to-talk and hands-free dictation from outside Fleck.
- Bottom, left, and right docks across multiple displays and Spaces.
- Visual obstruction over text-heavy applications.
- Light, dark, Reduce Motion, Reduce Transparency, and VoiceOver behavior.
- Long-note typing, selection, scrolling, rich formatting, checklists, dictation insertion, and agent append under the new default typography.
