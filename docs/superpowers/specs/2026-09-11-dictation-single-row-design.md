# Single-row dictation capsule design

## Decision

Harry confirmed that neither focused dictation nor Smart Capture should show a
destination/mode header. Both modes use the same compact listening and processing
structure. This supersedes the earlier decision to retain a Smart Capture header.

| State | Visible content | Size and placement |
| --- | --- | --- |
| Idle | Existing Fleck mark | Existing 46 × 24 points |
| Starting | Existing mark and truthful Starting status | Existing 104 × 36 points |
| Listening, either mode | Mark, centered waveform, timer; Stop/Cancel replace the timer on hands-free hover | 176 × 36 points |
| Finishing, polishing, organizing, saving | Existing progress mark and delayed status label | 192 × 36 points |
| Saved, warning, failure, recovery, chooser | Existing result text, details, actions, and chooser | Existing content-aware widths and 36-point height |

“No header” does not mean no status feedback: Starting, Polishing, Saved to Inbox,
errors, and Choose note remain. Only the extra active destination/mode row is
removed. The waveform-only row previously shown beneath a comparison image was a
separate fixture, not a second simultaneous app capsule; final evidence should
avoid that confusing presentation.

## Visual and interaction contract

- There is no visible active `Smart Capture`, focused-note title, or equivalent
  destination header, including when detail strings are nonempty, long, or absent.
- Listening keeps its existing centered waveform, dock mirroring, 58-point
  timer/control zone, and 28 × 28-point Stop/Cancel targets. Hover and audio levels
  do not move the shell or its fixed controls.
- Keep the existing mark, colors, rounded shell, typography, and 13-bar waveform.
  Do not change signal scaling, shape, smoothing, cadence, decay, or reset.
- Processing uses the existing core, including its truthful stage labels, delay,
  generation fencing, reduced-motion behavior, and progress-mark treatment.
- Preserve the captured destination and mode in runtime context and accessibility
  feedback. This is a visual simplification, not a change to capture or routing.
- Preserve the controller-owned native sizing and chooser-aware width calculation
  that fixed the rightward saved/chooser shift. All settled bottom-dock panels
  remain centered within 0.5 points; left/right docks retain their existing inset.

## Architecture

Delete the conditional active-header branch and its dedicated height. Listening
renders the existing `listeningCore(at:)`; processing renders `processingCore`.
Remove `activeHeaderText`, `contextualActiveHeight`, `capturedContextText`, and
header-only wrappers. Remove the context-aware size overload if its only remaining
purpose is forwarding the status, then update its owned callers to the status
API. Do not replace the old branch with a flag, an always-nil property, or hidden
layout space.

Keep `detailText`, `compactDetailText`, `secondaryVisibleText`, and VoiceOver
generation: terminal states and accessibility still consume them. Keep
`widthCeiling`, chooser measurement, constrained terminal layouts, and
`NSHostingView.sizingOptions = []` intact.

No library is needed. CSS/web mockups, a new component framework, and a waveform
redesign do not address this request.

## Baseline and preservation

The maintainer's external accepted-build registry remains unchanged, SHA-256
`07c15a3e41562f12b1dbc87eac8f708c60f3577c3281862035c2f8fc420e857a`.
The accepted source is `dd5c3e2d027d6adde6ad79a3f7d91cc1c9d33e21`, tree
`a8d6c703750d83651dacb96773f3d3c0e4a8034d`.

The feature baseline adds the exact reviewed 11-file running-candidate delta,
full-index diff SHA-256
`0c14cc7ea69b640c9926f9a7c55ad9dc20b612585722b2501f1c5fb275875943`,
from the preserved `codex/capsule-editor-replacement-flec5` worktree.
It preserves seven editor-polish files and four capsule source/test files. No
newer main, OSS, or source-preview changes are included.

Implementation is isolated in the worktree identified by `$FLECK_WORKTREE`, branch
`codex/capsule-single-row-flec5`. Preserve the old worktrees and running bundle.
The current rollback candidate executable is
`34ac4eb94048331fbb0e257b3915bf1db2f256f2b1a18c41a0862a31e9989500`.

## Scope and authority

The primary owns these design/implementation documents, diagnosis, verification,
and integration. The same sequential Sol High worker owns product changes in:

- `Sources/FleckApp/DictationCapsule.swift`
- `Tests/FleckAppTests/DictationCapsuleVisualCaptureTests.swift`

All other inherited source/test files must remain byte-identical to the running
candidate baseline. The copied native test host is verification-only. Do not
edit the coordinator, runtime, routing, model management, dependency pins, shared
runners, or unrelated editor code. Do not commit, publish, promote the accepted
registry, change permissions, or perform a microphone/model trial.

Astra High remains the orchestrator and fresh independent reviewer; Sol High
remains the implementer. No Terra or silent model fallback. Capy returns child
model, task, and machine metadata; High is explicitly requested, with the host's
effective-reasoning metadata limitation already acknowledged by Harry.

## Acceptance evidence

1. A new regression fails on the inherited Smart Capture header/52-point layout,
   then passes for both modes and all active states after removal.
2. Existing capture/readiness/cancellation, waveform, accessibility, chooser,
   editor-polish, and actual settled-position tests pass with nonempty matching
   and actual execution counts.
3. Synthetic native captures show the same compact single row for both modes,
   including quiet/live/hover, all docks, and light/dark appearance. Visual
   evidence is labeled synthetic and does not claim microphone performance.
4. Parent independently reruns focused enhanced checks and verifies the exact
   built bundle; a new fresh Astra High reviewer returns `ship`.
5. The final local replacement follows the already-authorized build-and-switch
   workflow: retain the current bundle, recheck its exact identity and idle state,
   request normal termination, launch the exact reviewed new bundle, and verify
   the new PID/path/hash and visible idle capsule. Never force-quit or bypass a
   permission prompt. Stop for Harry if idle state or graceful shutdown cannot be
   confirmed.

Source review, synthetic rendering, local process replacement, microphone/device
behavior, and release acceptance remain separate claims.

## Publication note

The maintainer subsequently authorized publishing this candidate and its plans.
Local machine paths and personal runtime receipts are intentionally excluded
from this public copy. The implementation constraints above describe the original
local-only work; publication does not authorize a merge or acceptance promotion.
At initial publication, `main` already included the editor polish and later
source-preview fixes. The draft preserved its reviewed baseline and required
separate integration verification before merging into that newer source tree.
Subsequent integration and merge-readiness evidence is recorded in
[PR #31](https://github.com/exterminatorrat/Fleck/pull/31); this document records
the original local design rather than a release or acceptance promotion.
