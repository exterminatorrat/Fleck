# Fleck Dictation Rail Design

## Summary

Fleck will replace its generic floating dictation capsule with **Fleck Rail**, a
compact, persistent macOS control inspired by the restraint and immediacy of
Wispr Flow while remaining visually and behaviorally specific to Fleck.

The rail uses Fleck's four-tile mark as one continuous shared element across the
entire local dictation pipeline:

`capture -> polish -> organize -> save`

Idle remains nearly invisible. Holding the configured modifier starts
push-to-talk dictation, double-tapping retains the existing hands-free gesture,
and clicking the idle rail starts hands-free dictation directly. During speech,
the rail expands to show a live waveform and elapsed time. After speech, the
same four Fleck tiles communicate processing stages before resolving into a
saved, fallback, or failure result.

This project redesigns the capsule's presentation and direct interaction. It
does not change transcription, cleanup, routing, persistence, recovery, or
privacy policy.

## Reference Synthesis

The design borrows these interaction principles from current dictation tools:

- Wispr Flow: a compact persistent control, direct click-to-dictate behavior,
  hover disclosure, bottom/side docking, and a clear live audio response.
- Superwhisper: unmistakable waveform feedback and discoverable Stop/Cancel
  controls, without adopting its larger utility-window footprint.

Fleck will not copy either product's branding, artwork, colors, exact
silhouette, or animation assets. Fleck Rail uses Fleck's own mark, violet color,
pipeline, terminology, and recovery model.

Reference material:

- <https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android>
- <https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop>
- <https://superwhisper.com/docs/get-started/interface-rec-window>

## Problem Diagnosis

The current capsule is functionally competent but visually reads as a generic
macOS status pill:

- Its detached hosting tree uses `Color.accentColor` without Fleck's preference
  tint, so it can resolve to macOS blue instead of Fleck's default `#7C6CF2`.
- Idle uses the generic `waveform` SF Symbol rather than the Fleck mark.
- A plain regular-material capsule, default panel shadow, and 24-point edge
  inset make it feel like a floating notification instead of an anchored tool.
- Every status installs a new hosting view, preventing shared-element continuity
  between listening, processing, and completion.
- Listening resets immediately when processing begins, then swaps among an SF
  ellipsis, sparkles, routing symbol, and terminal symbol.
- Every non-listening status occupies the same 280-by-32-point frame regardless
  of content.
- Side docking rotates the whole horizontal composition, including text and
  actions, instead of reflowing it for the edge.
- The waveform's eleven bars share a symmetric scalar pattern, and silence is
  contractually static, making the surface resemble a stock equalizer.

The redesign must address those causes rather than merely replacing blue with
violet.

## Goals

- Make the global dictation surface immediately recognizable as Fleck.
- Match Wispr Flow's compactness and perceived responsiveness without copying
  its visual identity.
- Make listening, cleanup, routing, persistence, and completion feel like one
  continuous experience.
- Keep the rail unobtrusive during frequent daily use.
- Preserve truthful, phase-accurate feedback and current recovery actions.
- Preserve non-activating panel behavior, keyboard focus, local processing,
  no-transcript presentation, accessibility, docking, Spaces, and multi-display
  behavior.
- Make direct pointer use genuinely useful through click-to-start hands-free
  dictation.

## Non-Goals

This project will not:

- Change speech engines, transcript quality, cleanup rules, routing rules,
  destination selection, note insertion, persistence, or history retention.
- Dictate into arbitrary third-party applications.
- Display live or final transcript contents in the rail.
- Display the foreground application name or inspect unrelated application
  content.
- Add command mode, writing modes, language selection, meeting controls,
  Notetaker features, or a second floating panel.
- Add gradients, glass spectacle, bloom, glow, decorative particles, video,
  Lottie, Metal, or a third-party animation dependency.
- Redesign the Fleck notes panel, Settings, Dictation History, or menu-bar UI.
- Introduce a new capsule customization surface.

## Core Visual Object

### Fleck Mark

The persistent visual seed is a simplified 14-by-14-point Fleck mark made from
four approximately 6-point rounded tiles with a 2-point internal gap. It must be
drawn from the canonical mark geometry rather than approximated with unrelated
SF Symbols.

The mark is not decorative. It explains the system:

1. Capture.
2. Polish.
3. Organize.
4. Save.

Idle shows the settled 2-by-2 mark. Processing unfolds the same tiles into a
horizontal four-stage rail. Terminal states reform the mark beside the result
glyph. Stable identity must be preserved throughout the transition.

### Shell

The default rail shell is a matte adaptive dark surface:

- Fill: `#17151C` at 96% opacity.
- Primary text: `#F7F5FA`.
- Secondary text: `#B6B1BF`.
- Fleck core violet: `#7C6CF2`.
- Live violet: `#A79DFF`.
- Success: `#5DD68A`.
- Warning: `#FFB24A`.
- Failure: `#FF6B70`.
- One-point inner top highlight at approximately 10% white.
- Native panel shadow only; the SwiftUI content must not add a second wide
  shadow.
- Continuous 10-point idle corners and 12-point active corners. The rail is a
  compact rounded rectangle, not a full generic pill.

Semantic colors affect only a result glyph or one stage tile. The entire shell
never floods green, amber, or red.

When the user chooses a custom Fleck accent, that saved preference remains
unchanged. The rail derives a display core accent by moving it toward white only
as much as needed to preserve at least 3:1 contrast against the shell, then
derives live accent as a lighter contrast-safe variant. Semantic success,
warning, and failure colors do not change with the custom accent.

Reduce Transparency replaces the partially translucent shell with an opaque
`#17151C` surface. Increase Contrast adds a visible one-point border and raises
secondary-text contrast.

### Typography and Spacing

- Status copy: SF Pro Text, 12 points, medium.
- Action copy: SF Pro Text, 11 points, semibold.
- Timer: SF Mono, 10.5 points, medium, tabular digits.
- Horizontal padding: 8 points.
- Primary content gap: 7 points.
- Action divider: one by 16 points, approximately 10% white.
- No all-caps copy.
- No label may wrap.

## State Design

### Idle

- Frame: 46 by 24 points.
- Content: the simplified Fleck mark only.
- Bottom edge inset: 10 points from the visible screen frame.
- No label, shortcut hint, timer, pulse, glow, or idle animation.
- Transparent panel regions outside the visible rail pass clicks through.

Clicking the idle rail begins hands-free dictation without activating Fleck or
stealing keyboard focus. `Open Fleck` moves to the right-click context menu.
The click commits on primary-button mouse-up only when pointer travel remained
below four points. Travel of four points or more captures an idle drag and
permanently
suppresses that click; right-clicks and action-button hit regions never start
dictation.

### Arming

The existing 180-millisecond accidental-press threshold remains authoritative.

- On accepted modifier key-down, one Fleck tile turns core violet in the first
  rendered frame.
- Every accepted pointer or double-tap start activates the same capture tile in
  its first rendered frame with zero-duration color feedback.
- The shell does not expand before capture is accepted.
- Releasing before the threshold returns immediately to idle and produces no
  cancellation toast or flourish.
- Pointer-started and double-tap hands-free sessions bypass only the hold
  threshold. They remain in the compact arming presentation while the engine is
  acquired and started, and enter listening only after the coordinator reports
  that audio capture has actually started.
- A second click or Escape during engine startup cancels the pending session;
  it must not finish an empty capture or surface `No speech heard`.

Arming must be represented separately from listening. It must not be mapped to
the expanded listening presentation.

### Listening

- Frame: 176 by 36 points.
- Content: Fleck mark, seven-bar live waveform, elapsed timer.
- The waveform is the primary visual signal. The timer is tertiary.
- No visible `Listening` label is required; VoiceOver announces the state once.
- Hands-free mode uses the same core surface. Hover reveals compact Stop and
  Cancel affordances without changing the settled non-hover width.
- Clicking the active rail stops hands-free dictation and begins processing.
- Escape cancels either pointer-started, double-tap, or hold-to-talk dictation.

The waveform uses seven bars, each 2.5 points wide with a 2-point gap and a
4-to-17-point height range. It is capped at 30 visual updates per second. It
uses fast attack and slower release, a low ambient noise floor, stable
asymmetric per-bar weights, and a restrained baseline during thinking pauses.

Silence must not generate decorative dancing. The rail remains visibly live
through the persistent recording state, timer, and minimal baseline rather than
synthetic energy.

In hands-free mode, the non-button rail surface is the Stop target. On hover,
Stop and Cancel each receive a fixed 28-by-28-point hit region inside the
176-by-36-point frame; those button events are consumed and never bubble to the
rail. Stop finishes and processes, while Cancel requests cancellation. The same
two operations are always exposed as VoiceOver custom actions even when their
pointer controls are visually hidden.

The listening layout always reserves a fixed 58-by-28-point trailing action
zone. At rest the elapsed timer is centered in that zone. Hover crossfades the
timer to adjacent 28-by-28-point Stop and Cancel controls with a two-point gap;
the mark, waveform, shell, and action zone never move or resize.

### Finalizing

- Frame: 192 by 36 points.
- The waveform settles toward baseline and fades.
- The 2-by-2 Fleck mark unfolds into four horizontal stage tiles.
- The capture tile becomes complete.
- Visible copy is `Finishing` only if the phase lasts at least 450 milliseconds.

### Polishing

- Frame remains 192 by 36 points.
- The second stage tile becomes active in live violet.
- Visible copy is `Polishing`, not the implementation-oriented `Cleaning up`.
- Cleanup fallback still advances normally; it is communicated at the result.
- The label appears only when the phase lasts at least 450 milliseconds.

### Organizing

- Frame remains 192 by 36 points.
- The third stage tile becomes active.
- Visible copy is `Organizing`, not `Finding note` or `Routing`.
- Focused dictation skips this stage truthfully because it does not route.
- Smart Capture routing to Inbox remains a successful organizing result.
- The label appears only when the phase lasts at least 450 milliseconds.

### Saving

- Frame remains 192 by 36 points.
- The fourth stage tile becomes active at the real persistence boundary.
- Visible copy is `Saving` only if the persistence operation lasts at least 450
  milliseconds.

The current coordinator has no distinct saving phase. Implementation must add
an explicit truthful saving event or phase around the real focused persistence
flush and Smart Capture save call. The UI must never infer saving from a timer,
assume routing implies persistence, or show completion before the save receipt.

### Pipeline Tile Treatments

The four-stage rail uses both color and shape so it remains legible without
color:

- Pending: low-contrast solid tile.
- Active: live-accent tile, one point larger than its settled size.
- Complete: core-accent solid tile at settled size.
- Skipped: hollow tile outline.
- Fallback: amber hollow-center tile.
- Failed: failure-color tile with a diagonal cut.

Focused dictation marks Organize as skipped. Cleanup fallback marks Polish as
fallback while allowing Save to complete. A terminal pipeline failure marks the
authoritative failed stage and leaves later stages pending. The label slot is
part of the fixed 192-point processing layout from phase entry; its opacity
changes after the 450-millisecond threshold without inserting content or moving
the tiles.

### Saved

- Frame: up to 264 by 36 points.
- Content: reformed Fleck mark, compact success glyph, `Saved to {destination}`,
  divider, and `Undo` when available.
- Focused dictation uses `Saved to current note`.
- Smart Capture uses `Saved to your notes` when the committed destination title
  is not present in the terminal save outcome.
- Destination titles are tail-truncated to preserve the width ceiling.
- The result remains for the existing 1.6-second success interval, then returns
  to idle.

The saved surface may expose only the destination title. It never exposes the
transcript, note body, foreground application, or routing candidate list.

### Saved Original

- Frame: up to 288 by 36 points.
- Content: amber glyph, `Saved original to {destination}`, and the applicable
  recovery action.
- This state represents successful persistence with cleanup fallback. It must
  not use red failure styling or imply that content was lost.
- The result remains for the existing 1.6-second success interval.

### Failure

- Frame: up to 264 by 36 points.
- Use specific concise copy where the current error taxonomy permits it:
  `Microphone access needed` or `Couldn't save`.
- Pair color with a failure glyph and text; never rely on red alone.
- Preserve only the applicable coordinator recovery action: Undo, Copy,
  History, or Open Destination. Preflight permission and repair errors that do
  not currently carry a capsule action remain non-actionable in the rail; their
  detailed route stays in Settings or History.
- Full technical detail remains in Dictation History, Settings, or VoiceOver; it
  does not expand the rail into a diagnostic window.
- Failures without an action use the current failure interval. Action-bearing
  failures remain until the user invokes the action, explicitly dismisses the
  result, or begins a newer capture; they never silently discard recovery on a
  timer.
- Clicking the non-action failure shell dismisses it. `Dismiss` is also present
  in the context menu and as a VoiceOver custom action; recovery-button hit
  regions never trigger dismissal.

Dismissal clears only the visible failure owner and returns the rail to idle.
It does not invoke, delete, or mark the recovery action completed; existing
History remains the durable route to the record.

### No Speech

- Frame: up to 192 by 36 points.
- Content: amber neutral glyph and `No speech heard`.
- This is a no-input result, not a red system failure.
- It exposes no recovery action and returns to idle after the current failure
  interval.

### Model Repair

- Frame: up to 224 by 36 points.
- Content: settled Fleck mark, compact repair glyph, and `Repairing enhanced
  model`.
- This maintenance operation does not unfold into the four-stage dictation
  pipeline and does not imitate live audio activity.
- Successful or cancelled repair returns to idle. Repair failure resolves to
  the normal failure surface with `Model repair failed`; it adds no recovery
  action that the current runtime does not provide.

### Cancelled

An authoritative terminal `cancelled` outcome returns directly to idle. It does
not show a message, shrink flourish, checkmark, error, or celebration. If
cancellation compensation fails after an editor commit or durable save, the
rail must preserve the coordinator's truthful failure and recovery result
instead of presenting cancellation or idle.

## Direct Interaction

### Pointer

- Click idle: on a qualifying primary-button mouse-up, start one hands-free
  session.
- Click listening rail during hands-free: on a qualifying non-button mouse-up,
  finish and process that session.
- Hover listening: disclose Stop and Cancel controls.
- Drag idle background: reposition and snap to the nearest supported edge.
- Right-click: Open Fleck, Dictation History, Dictation Settings, and the
  existing docking choices where relevant.
- Buttons and recovery actions never initiate a drag.

Click-to-start must not activate Fleck or move the insertion focus in the front
application. The current focused editor or Smart Capture destination behavior
remains authoritative.

Pointer and drag recognition share one four-point movement threshold. Once a
gesture becomes a drag, releasing it can only complete docking; it cannot start
or stop dictation. Stop, Cancel, recovery, and context-menu hit regions consume
their events and never fall through to the rail-wide click target.

### Keyboard

- Hold configured modifier: existing push-to-talk behavior.
- Double-tap configured modifier: existing hands-free behavior.
- Press configured modifier again during any hands-free session, including one
  started by clicking the rail: finish that owned session without beginning a
  new hold session.
- Escape: cancel the owned active capture.
- Keyboard-initiated opening and closing receives no entrance animation.

Pointer and keyboard triggers converge on the same coordinator. They cannot
create overlapping captures or independent visual state machines.

## Motion System

Motion exists only to preserve state continuity and explain system-driven
transitions:

- Input acknowledgement: first rendered frame, no delayed entrance.
- Color and opacity feedback: 90 milliseconds, strong ease-out.
- Shared Fleck-tile and internal layout morph: 140 milliseconds, ease-in-out.
- Fast content exit: 70 milliseconds.
- Result transition: 100 to 120 milliseconds.
- Success-to-idle: text exits in 70 milliseconds while the shell settles over
  120 milliseconds, overlapping rather than serial.
- Dock snap after drag: 180 milliseconds, critically damped, zero bounce.
- Reduce Motion: 100-millisecond opacity changes only; geometry snaps.

For keyboard arming, the first tile changes color with zero-duration feedback.
Accepted listening content appears in the first frame that audio capture is
reported active; trailing shell interpolation may settle around it but can
never gate capture or visual acknowledgement. A sub-threshold hold release
returns to idle with zero-duration geometry and color changes.

Under Reduce Motion, layout geometry and docking snap, settled layouts
crossfade, and the Fleck tiles do not travel or unfold. Live input uses the same
seven-bar shape at no more than 15 smoothed updates per second with a reduced
height range and no spring response. It remains truthful feedback rather than
decorative animation.

All system-driven transitions must be interruptible and retarget from the
current visual state. Rapid cancel, failure, shutdown, or a newer capture must
not restart an old keyframe sequence from frame zero.

The design prohibits entrance bounce, idle pulse, shimmer, animated gradient,
glow, success celebration, failure shake, and progress percentages.

## Docking and Displays

- Supported docks remain bottom, left, and right.
- Bottom expands symmetrically around its anchored center.
- Left and right expand inward from the screen edge.
- Side states retain the same width and height tier as their bottom equivalent,
  anchored to the side inset. The Fleck mark stays nearest the dock edge and
  all additional content grows inward. The right-edge content order mirrors
  the left-edge order so the mark does not jump away from its anchor.
- Side layouts reflow the mark, waveform, stage rail, text, and actions. Text
  remains horizontal and readable; the whole bottom layout is never rotated.
- The rail remains clamped to the selected display's visible frame and preserves
  existing Spaces and full-screen auxiliary behavior.
- The bottom inset is 10 points. Side insets use the same apparent distance from
  the visible edge.
- Dragging presents supported drop zones only while a drag is active.

## Accessibility

- The panel remains non-activating, non-key, and non-main.
- No transition moves VoiceOver or keyboard focus.
- VoiceOver announces listening once and terminal success or failure once.
- The waveform bars and elapsed timer updates are hidden from repeated
  VoiceOver announcement.
- Processing phases shorter than one second are coalesced rather than spoken in
  rapid succession. The 450-millisecond visual-label threshold does not enqueue
  VoiceOver speech.
- Stop, Cancel, Undo, Copy, History, Settings, and Open Destination remain
  available through menus or global commands because the panel cannot depend on
  Tab focus.
- Color is always paired with shape, glyph, or concise copy.
- Reduce Motion, Reduce Transparency, and Increase Contrast follow the visual
  contracts above.
- Idle pointer hit testing is exactly the visible 46-by-24-point shell. The
  panel has no invisible click-catching margin, and transparent regions outside
  that shell pass through to the underlying application. Keyboard and
  VoiceOver actions provide non-pointer alternatives without enlarging the
  blocking overlay.

## State and Ownership Boundaries

The design retains one long-lived `DictationCapsulePanel` and one persistent
SwiftUI view identity. State changes update a stable presentation model rather
than replacing `panel.contentView` per phase.

The existing `GlobalHoldShortcut` becomes the single session owner for both
keyboard and pointer starts. Pointer commands call explicit start, finish, and
cancel entry points on that owner rather than invoking the coordinator
directly. The owner holds the session token, trigger kind, selected dictation
mode, Escape monitor, terminal observation, and Stop/Cancel dispatch until the
authoritative terminal outcome. It rejects every competing start while a token
is owned.

The authoritative terminal failure outcome carries an optional `failureStage`
for capture, polish, organize, or save. The session owner supplies that value to
the presentation. The view never reconstructs a failed stage from the error
string or its last locally rendered phase.

The presentation boundary receives explicit inputs for:

- Authoritative dictation phase.
- Authoritative pipeline stage and failed-stage provenance when a terminal
  failure is attributable to capture, polish, organize, or save.
- Stable session identity, trigger kind, dictation mode, and hands-free
  ownership from arming through terminal completion.
- Audio level scalar while listening.
- Fleck accent and adaptive appearance.
- Destination display title at terminal success.
- Recovery action and handler.
- Dock and display placement.
- Accessibility environment.

The capsule never discovers product state from timers, animation completion,
view-local guesses, or raw audio buffers. Timers may delay phase labels and
return terminal results to idle, but cannot manufacture pipeline phases.

Audio levels remain ephemeral, unlogged, unpersisted, absent from Dictation
History, and unavailable to agents. Hiding, disabling, or shutting down the rail
stops visual refresh and resets its level state.

Fleck's saved `accentHex` is resolved outside the detached hosting tree and
injected explicitly. The rail must not rely on an inherited system accent.

## Verification

### Automated Contracts

Automated coverage must verify:

- The default Fleck accent resolves to `#7C6CF2`, not system blue.
- A custom saved Fleck accent reaches the detached rail presentation.
- Default and custom display core/live accents retain at least 3:1 contrast
  against the shell without rewriting the saved accent preference.
- Idle, arming, listening, processing, saved, fallback, no-speech, model-repair,
  failure, and cancelled states map to the specified width tiers and copy.
- Arming remains compact and a sub-threshold release never presents listening.
- Pointer and double-tap starts remain arming until audio capture actually
  begins; stop or Escape during startup produces cancellation, not no-speech.
- Click idle starts exactly one hands-free coordinator session without
  activating Fleck.
- Clicking or keyboard-finishing that session produces exactly one finish.
- Crossing the four-point drag threshold suppresses start or stop, while
  right-click and action hit regions never fall through to a rail click.
- Pointer, double-tap, and hold triggers cannot overlap captures.
- `GlobalHoldShortcut` owns one session token, mode, trigger, Escape monitor,
  and terminal observation across pointer and keyboard input.
- One persistent view identity survives all phase transitions.
- Focused dictation skips organizing while Smart Capture uses it.
- Pending, active, complete, skipped, fallback, and failed stage tiles map to
  the authoritative session outcome without color-only distinctions.
- Saving begins only at the real focused or Smart Capture persistence boundary.
- No success appears before a durable save receipt.
- Cleanup fallback resolves to `Saved original`, not failure.
- Missing Smart Capture destination titles resolve to `Saved to your notes`.
- Destination copy truncates without exceeding the width ceiling.
- The waveform has seven stable asymmetric bars, bounded refresh cadence, noise
  floor, attack/release behavior, pause baseline, and reset semantics.
- Processing labels appear only after their 450-millisecond threshold.
- Obsolete capture levels, 450-millisecond phase-label timers, and return timers
  cannot affect a newer presentation generation.
- Action-bearing failures do not time out and lose their recovery action.
- Reduce Motion snaps geometry and docking, removes tile travel, crossfades
  settled layouts, and limits live levels to 15 smoothed updates per second.
- Side docks reflow content without rotating text or moving the Fleck mark away
  from its edge anchor.
- Accessibility labels and announcements remain phase-accurate and coalesced.
- The idle hit region equals the visible 46-by-24-point shell and all other
  transparent panel areas pass pointer events through.

### Manual Visual Acceptance

Manual validation must cover the exact built Fleck app, not a standalone demo:

- Idle, hover, arming, listening, long pauses, finalizing, polishing,
  organizing, saving, success, raw fallback, failure, cancellation, and model
  repair.
- Pointer-started hands-free, double-tap hands-free, hold-to-talk, repeat press,
  click stop, startup cancel, hover Stop/Cancel, drag-versus-click, Escape,
  Undo, and recovery actions.
- Fast phases that skip visible labels and slow phases that reveal them.
- Soft, loud, clipped, noisy, and silent microphone input.
- Bottom, left, and right docking on multiple displays and Spaces.
- Light and dark host applications, visible Dock, hidden Dock, full-screen apps,
  and screen sharing.
- Default and custom Fleck accents.
- Reduce Motion, Reduce Transparency, Increase Contrast, and VoiceOver.
- Four-times-slow-motion recording to inspect continuity, retargeting, frame
  jumps, label flicker, and accidental double shadows.

## Acceptance Criteria

The design is accepted for implementation only when:

1. Idle reads as Fleck without text or a generic waveform symbol.
2. No default state uses accidental macOS system blue.
3. The same Fleck mark remains visually continuous from idle through terminal
   result.
4. Keyboard and pointer triggers respond immediately without decorative entry
   motion.
5. Listening provides truthful real-audio feedback without showing transcript
   content.
6. Processing stages are accurate, do not flicker, and never imply persistence
   before the real save boundary.
7. Cleanup fallback reads as a successful original-text save.
8. Click-to-start hands-free never activates Fleck or creates an overlapping
   session.
9. Click, drag, Stop, Cancel, and right-click are mutually exclusive pointer
   targets with deterministic session ownership.
10. Side-docked text remains horizontal and usable, with the Fleck mark fixed
    to its dock-edge anchor.
11. Reduce Motion, transparency, contrast, VoiceOver, pointer pass-through, and
    screen-edge behavior are verified in the exact built app.

## Implementation Boundary

This document defines the approved product and visual behavior only. It does not
authorize implementation, packaging, installation, distribution, or release.
Implementation requires a separate bounded plan, isolated worktree, focused
tests, parent verification, and the repository's required review workflow.
