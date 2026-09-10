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

## Native routing evidence and additional references

The user authorized the geometry-aware OS pointer helper. It reordered the disposable Chrome control and completed a plain AppKit drag (`destination.perform`, success count 1, source end operation copy). This distinguishes the original computer-use drag limitation from the current Fleck defect.

On an isolated fixture (Northstar, Relay, Canvas), the same helper produced 38 native source move callbacks and zero destination callbacks. The source offered move within the application; the registered FluidTabDestinationView was present in the hit ancestry. Release ended with operation none and no accepted drop. The compositor captured the moving Relay label and neighbor displacement, but the dark fixture revealed inadequate moving-label contrast. These observations do not yet establish the underlying destination-routing cause.

[bpmn-io drag-tabs](https://github.com/bpmn-io/drag-tabs/blob/816f2cc26e949c0492590fea84a7f0097c486c09/index.js) delegates drag lifecycle events at its parent, emits index changes, and reports cancellation when no drop occurred. Its smaller-tab/wider-target guard prevents immediate swap-back. It does not implement scrolling. [Chrome Tabs](https://github.com/adamschwartz/chrome-tabs/blob/1046a3fd4d164bc3550d82dc46ff1f13c6438e2f/js/chrome-tabs.js) tracks the dragged tab directly along x, rearranges visual children, and animates neighboring tabs. These are behavioral references, not dependencies to add. Preserve Fleck's session validation, pin partitions and edge scrolling while correcting the native destination boundary.


## Proven pinned-host routing boundary

Native controls isolate the destination failure to a zero-sized ancestor. An otherwise identical unclipped AppKit hierarchy with a 0 x 0 ancestor accepted mouse-down and emitted native source movement but received no destination callbacks; giving that ancestor 420 x 190 bounds restored `destination.perform` and source end operation move (16).

The production pinned navigation surface applies `glassEffect` around its interactive content. A minimal SwiftUI control using that same structure reproduced the zero-sized ancestor and failed drop. Adding `.interactive()` still failed. Applying the glass effect to a non-hit-testing background Rectangle removed the zero-sized ancestor from the destination path and completed the native drop. This supports a surgical change to `PinnedNavigationChromeSurface`, preserving the existing native source, payload, reorder controller, and accessibility material fallbacks.

Ignored native evidence under `.build/evidence/native-pointer/`: `native-control-zero-ancestor.jsonl` (no destination, end 0), `native-control-nonzero-ancestor.jsonl` (perform 1, end 16), `native-control-glass.jsonl` and `native-control-glass-interactive.jsonl` (no destination, end 0), and `native-control-glass-background.jsonl` (perform 1, end 16). Production acceptance still requires a real gesture on the corrected Fleck bundle and the full behavior matrix above.


The first production background-glass candidate completed a native move and preserved selection, and Escape left the workspace unchanged. However, compositor capture showed the outer glass container elevated that background over the sibling controls, blurring the navigation row. Two controls restored readable content and native drops: removing the outer glass container, or assigning the row to an AppKit NSGlassEffectView's documented contentView. Prefer removing the unused outer grouping boundary rather than adding another hosting bridge; the pinned surfaces have no glass morph identity and remain separated at spacing zero. Verify the actual panel appearance before accepting this correction.


A leftward native gesture exposed a separate initialization error: `willBeginAt` supplied the true pointer screen position, while reading `session.draggingLocation` inside that callback returned (-1, 1441). Initializing the grab offset from that unavailable session property forced subsequent previews toward the last insertion slot. Use the callback's supplied point for initialization; the acceptance matrix must include leftward as well as rightward movement so a successful native drop into the unchanged slot is not mistaken for a successful reorder.

## Menu-window correction packet

1. **Objective and success criteria.** Restore actual native note-tab reorder and note-to-folder transfer in the menu host using the public NSWindow destination path demonstrated by the diagnostic control. Preserve selection, readable native preview, cancellation, session validation, and existing pinned behavior. A successful control is causal evidence, not product acceptance.
2. **Ownership and constraints.** The same native implementation worker owns only `Sources/FleckApp/NotesPanel.swift` and `Tests/FleckAppTests/FolderReorderInteractionTests.swift`. Preserve concurrent/unrelated edits and the reviewed pinned corrections. No private host mutation, scene replacement, global window-number registry, or source-end acceptance bypass. The parent owns specification/evidence documentation.
3. **Implementation and non-goals.** A menu-only coordinator retains a window delegate proxy while keeping the original delegate and a weak window. A non-hit-testing installer obtains the actual window; teardown restores the delegate only if its own proxy is still installed. Register only the custom note type and never unregister unrelated types. NSWindow provides no public registration-set getter or per-type removal, so leave the added type inert when detaching. Forward unrelated optional selectors and foreign drag selectors, including delegates that implement the selectors without declaring a custom protocol. Preserve the prior entered result when foreign updated is absent. Route valid same-host notes to the existing fluid tab controller or lightweight folder geometry anchors. Intersect target bounds with actual NSClipView ancestors and the window content bounds; do not use inherited visibleRect beneath the broken zero-sized host. Clear the previous hover/target on route changes and cancellation. Share existing note-transfer validation between provider and synchronous Data overloads. Keep all existing SwiftUI drop paths and pinned paths intact.
4. **Verification.** Write meaningful red cases before product edits, covering delegate forwarding/restoration, clipped geometry, tab/folder transitions, valid synchronous folder staging, cancellation, stale IDs/pins/deleted targets, malformed or mismatched payloads, and duplicate staging. Worker and parent run the FolderReorderInteraction/TabDragReorder/NotesPanelActionLifecycle/PinnedChrome filters with nonzero counts. Then build and exercise the exact diagnostic menu bundle using native pointer gestures, with before/held/release evidence and fixture-state checks. Complete the remaining menu/pinned matrix and final clean package checks after trace removal.
5. **Authority and handoff.** The prerequisite clean pinned diff received a fresh Sol `ship` verdict after parent tests and native clean-binary verification. The same worker may now implement this bounded menu packet. Return exact diff, red/green evidence, risks, and build status to the parent; do not launch, install, commit, publish, or alter real user data. The parent verifies, obtains fresh Sol review, and returns corrections through the same worker. No external writes are authorized.


## Corrected visual ownership decision

Native menu evidence distinguishes two separate rendering failures. VibrantDark's cached source pixels contain black foreground intended for live vibrancy composition; a concrete foreground on the existing label HStack fixes the actual cache without rebuilding its content. Separately, an opaque bitmap still becomes translucent as an AppKit dragging image. The public label component does not remove that translucency.

The current bounded implementation therefore retains the accepted native source, payload, session, destination routing, and reorder controller, while a note-only nonactivating preview panel owns the moving visual. The native dragging item's contents are nil using the documented AppKit API. The panel ignores mouse events and displays the source-size opaque image above the source window. Native willBegin/moved callbacks supply its screen position and grab offset; completion, cancellation, and teardown remove it. A minimal real menu-window control proved opaque display, successful native drop, and Escape cleanup before product implementation.

The source image uses concrete light/dark label foreground including icons, the existing rendered source, and an opaque rounded surface. Its bitmap must retain source point/pixel dimensions, with representation size established before bitmap context creation. Required evidence includes vibrant light/dark capture, a 2× raster regression, preview position/lifetime tests, and actual held/release compositor frames. This decision is not final acceptance until the product implementation passes those checks and fresh review.


## Accepted image and native-host resolution

The final note source captures the actual appearance-aware tab into an opaque Retina image, then displays it in a public nonactivating, mouse-ignoring panel while native drag callbacks retain routing authority. The native dragging item's image is suppressed. Completion, cancellation and host teardown close the preview. This avoids CoreDrag's dimmed source image while preserving the original pointer grab position, selected editor and native acceptance rules. Native dark-menu/light-pinned release frames and the fresh Sol ship verdict accepted this resolution; see the plan's final local checkpoint for exact package and proof limits.
