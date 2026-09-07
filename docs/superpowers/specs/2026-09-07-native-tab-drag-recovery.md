# Native tab drag recovery design

## Outcome and scope

Repair direct dragging of note tabs in the menu-bar panel and pinned note window. Existing Activity dismissal, compact toolbar sizing, note selection, folder transfers, pin partitions, and dictation must remain intact. Work locally on `codex/activity-toolbar-sizing`; do not publish or merge.

The user reported that candidate `318a9ef` cannot drag any tabs. Earlier candidates could reorder but lost the unselected dragged label during the gesture and briefly after release. Neither result is accepted.

## Reference and observation limits

Chrome provides the reference interaction: drag a tab to change its position ([Google help](https://support.google.com/chrome/answer/2391819?hl=en-gb)). The following visual contract is Fleck's design target, not a claim that every detail has been measured in Chrome. Disposable Chrome tabs A/B/C were created for comparison. The current computer-use drag command selected B but did not reorder it on two attempts; therefore it is not yet a validated input driver. Verify that control before using absence of Fleck callbacks as causal evidence.

AppKit offers an explicit frame and image for a native dragging item ([Apple documentation](https://developer.apple.com/documentation/AppKit/NSDraggingItem)). Runtime inspection established that the real NotesPanel session retains `ReorderNativeSource`; NSHostingView replacing the source is a falsified hypothesis.

## Behavior contract

| Phase | Required behavior | Failure to look for |
|---|---|---|
| Press | Entire padded tab body is a hit target; ordinary click still selects | Padding misses, selection lost |
| Threshold | Small movement stays a click; direct native replacement, if needed, uses 4 pt | Drag on every click, dead drag |
| Lift | One readable moving tab, preserving the pointer's horizontal grab offset | Invisible label, duplicate floating tab, jump to center |
| Travel | Pointer-following image is immediate; neighbors slide using existing AppMotion duration | Lag, whole strip jumping, same-slot publications |
| Cross midpoint | Existing reorder model chooses insertion slot and preserves pin partition | Jitter, oscillation, crossing pinned boundary |
| Reverse | Neighbor motion interrupts from presentation position | Snap back before moving |
| Exit/reenter | Preview clears outside strip and resumes only for the current valid session | Hidden source left behind, stale target |
| Release | Commit at most once; moving image hands off to visible settled tab without a blank interval | Half-second disappearance, double commit |
| Escape/outside | Restore original order and visible source; no stale later commit | Lost tab, canceled payload committing |
| Overflow | Existing edge scrolling reveals destinations; ordinary horizontal panning works | Timer persists, scroll escapes strip |
| Selection | Dragging unselected tab preserves current editor; clicking selects | Drag unexpectedly activates another note |
| Accessibility | Button press remains available; Reduce Motion removes displacement animation | Inaccessible tab, mandatory motion |

## Implementation decision

Three approaches were considered: patch SwiftUI's image again; retain native drag sessions but own the note gesture and image explicitly; replace the entire drag/drop interaction with an app-owned overlay. Repeated image patches have not passed visible QA. Replacing the full destination/payload system is excessive. Prefer the smallest proven correction; use a note-only native gesture bridge based on the user's physical no-drag report. Validate the automation separately before making GUI acceptance claims.

The bridge would own mouse-down/drag/up for notes, capture the visible tab once before hiding anything, create NSDraggingItem with the existing note payload, and begin a native session with the actual mouse event. Preserve existing ReorderDropSession validation, destination controller, pin rules, folder source behavior, and public accessibility. A click below threshold invokes the existing note action once; a drag does not invoke it. Retain the source for native session lifetime. Cancellation and completion must restore presentation regardless of callback/load ordering. Do not introduce another global pointer monitor, polling lifetime heuristic, or generic drag framework.

## Evidence gate

First validate the automation against Chrome. Then exercise Fleck with selected and unselected disposable tabs, padded start points, both directions, reversals, release, Escape, outside/reentry, folder transfer, pin boundaries, and overflow in menu and pinned hosts. Capture during drag and immediately after release, with actual native lifecycle observations when necessary. Unit tests and nonblank bitmap inspection alone do not pass this gate. Never call a candidate the newest accepted build without verifying lineage and the running executable. A fresh Sol reviewer must return `ship` after parent verification.
