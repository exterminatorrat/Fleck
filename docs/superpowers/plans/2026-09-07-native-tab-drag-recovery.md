# Native Tab Drag Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Preserve the current native-subagent lane and return corrections to the same worker.

**Goal:** Restore visible, reliable direct tab dragging and verify the complete gesture autonomously.

**Architecture:** Use the user's physical failure report as the behavioral red case; validate the input driver before using automated results to assign a cause. Retain existing reorder and drop validation; if the current source fails real input, replace only note gesture initiation with a native source owning its image and event lifecycle.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, computer-use visual inspection.

## Global Constraints

- Worktree: `${FLECK_REPO}/.worktrees/editor-three-bug-fixes`, base candidate `318a9ef`.
- No external writes. Preserve unrelated edits and accepted Activity/toolbar behavior.
- Same existing implementation worker, active Sol High override; fresh Sol High review after verification.
- Product ownership limited to `Sources/FleckApp/NotesPanel.swift` `Tests/FleckAppTests/FolderReorderInteractionTests.swift`, and the affected hosted drag test in `Tests/FleckAppTests/TabDragReorderTests.swift` (amended to balance its native mouse-up); preserve unrelated tests.
- User authorized autonomous implementation; no further design approval gate.
- The user explicitly authorized the native OS pointer driver; that authorization remains active for this task's GUI verification.

### Task 1: Establish trustworthy red evidence

- [x] Inspect current source ownership: actual native session retains ReorderNativeSource.
- [x] Try disposable Chrome A/B/C with current computer-use drag: no reorder, so driver remains unvalidated.
- [x] Validate a complete pointer sequence in Chrome; capture before, mid-gesture, and after order.
- [x] Repeat identical geometry-aware procedure in Fleck, record selected/unselected state and native begin/move/end callbacks. Chrome and the native AppKit control succeeded while Fleck failed, establishing the red GUI case. The user's physical failure report independently authorized the bounded source repair.

### Task 2: Repair the proven source defect

**Files:** `Sources/FleckApp/NotesPanel.swift`, `Tests/FleckAppTests/FolderReorderInteractionTests.swift`.
**Consumes:** existing ReorderDragHost begin provider/end closure, onBegan/onMoved callbacks, ReorderDropSession acceptance, FluidTabDragController.
**Produces:** a note gesture with visible native image and reliable begin/end lifecycle; existing destination interfaces remain stable.

- [x] Send worker the five-part bounded specification with the observed red trace. Require exact correction design and failing behavior tests before implementation; do not guess callback causes from synthetic events.
- [x] Add focused regression cases for the observed defect. For a direct gesture replacement, cover subthreshold click exactly once, threshold drag without selection, padded hit area, retained source, nonempty image captured before hiding, cancel restore, and load/end completion ordering. Keep existing stale-session, provider validation, partition and no-op update tests.
- [x] Run focused tests and confirm the intended mouse-down event assertion fails rather than merely a build failure or zero tests; the corrected combined suite passed 52 tests.
- [x] Implement the minimal correction. For a bridge, event sequence is `mouseDown -> store event/point; mouseDragged -> distance >= 4 -> create one payload/image/session; mouseUp below threshold -> existing activation`. Capture and use the current bounds as dragging frame; retain current native callback validation. Leave folder dragging on its existing path.
- [x] Run `swift test --filter 'FolderReorderInteractionTests|TabDragReorderTests|NotesPanelActionLifecycleTests'`; inspect all results and nonzero test counts.
- [ ] Parent inspect complete diff, repeat required tests, and build through existing `scripts/build-parakeet-test-app.sh` invocation after checking its current options. Verify codesign, architecture, executable hash and sole running bundle before GUI checks.

### Task 3: Exercise and correct until accepted

- [ ] Menu host: selected and unselected tab, left/right padded starts, left/right reorder, reversal, same-slot movement, quick release, Escape, outside then reentry. During each gesture confirm the label exists and pointer offset is stable.
- [ ] Pinned host: repeat core gesture at narrow and wide widths; check horizontal pan and edge autoscroll with overflow, pinned boundary, valid folder transfer and invalid outside release.
- [ ] Confirm unchanged note editor selection after unselected drag, no duplicate commit, no missing label after release, no lingering timer or stale session.
- [ ] Confirm ordinary click/keyboard accessibility and Reduce Motion; rerun menu Activity Done/Escape and compact toolbar smoke checks.
- [ ] Record observed results and limitations separately from unit test evidence. If any required case fails, send its concrete evidence to the same worker, rerun focused verification, rebuild, and repeat the failed case plus affected neighbors.
- [ ] Obtain fresh Sol review of actual diff and evidence. `fix-first` or `rethink` returns to the same worker; only `ship` closes the packet.
- [ ] Make a focused local commit, report exact candidate and evidence. Do not push, open PR, merge, or describe unverified native behavior as passing.

## Plan self-review

The behavior table maps to Task 3; driver validity maps to Task 1; source-only implementation and regression tests map to Task 2. Exact repair code depends on the real-event red trace, deliberately avoiding a speculative fourth image patch. That implementation detail must be resolved in the bounded worker packet before product edits.

## Verification amendment

The native bridge entered AppKit drag tracking during the window-dispatch test. The combined run was terminated because the synthetic gesture omitted mouse-up. Ownership now includes only the affected existing hosted TabDragReorderTests gesture to enqueue a matching in-process mouse-up. This is a harness correction, not authorization for OS event synthesis and not visual acceptance.

## Current evidence

Worker and parent each ran the combined Folder/Tab/Lifecycle filter: 52 tests passed. Parent log: `.build/evidence/native-note-bridge-parent.log`. Hosted hit testing and window event routing are covered. The final DEBUG interceptor stops before AppKit session tracking; it proves prepared image/source and cancellation cleanup, not actual OS callbacks. The earlier queued-mouse-up attempt was insufficient to make the Swift test host reliable. Packaging is being rebuilt after preserving the prior bundle in `.build/parakeet-test-before-native-bridge-318a9ef`. Native visible QA and final ship verdict remain open.

## Reviewed implementation checkpoint

Fresh Sol review returned `ship` for the corrected implementation. Original mouse-down event retention fixed the first review's blocking finding; the regression failed with dragged-event type/location and passed after correction. Parent rerun: 52 tests passed in 3.470 seconds (`.build/evidence/native-note-mousedown-parent.log`). The native session receives `press.event`, retained at mouseDown, rather than the threshold-crossing mouseDragged event.

This is implementation review only. The DEBUG interceptor stops before real AppKit tracking. Native menu/pinned gesture acceptance remains open, including visible label continuity, release/cancel behavior, and complete input-driver validation. Packaging and running-bundle evidence are separate. No external publication is authorized.

## Native routing correction packet

Input-driver permission is now explicit. Chrome reorder and a minimal real AppKit destination drop both passed. The isolated Fleck fixture reproduces zero destination callbacks despite native source movement and a registered destination in the hit ancestry. Worker ownership remains NotesPanel.swift and the existing FolderReorderInteractionTests/affected TabDragReorderTests cases; no new drag framework or source-end acceptance bypass is authorized. Require a failing regression, minimal destination correction, parent focused checks, native replay, readable preview, and a fresh Sol verdict.

Diagnostic launches must explicitly request a new application instance: Launch Services can otherwise return a different running app with the same bundle identifier. Verify synthetic fixture contents after launch. The approved installed application remains separate from diagnostic evidence.


### Pinned glass destination correction

Native A/B controls reproduced the missing destination callbacks by inserting a zero-sized ancestor, and by wrapping the interactive row in SwiftUI glass. Normal ancestor bounds or glass applied to a non-hit-testing background restored successful drops. Add a red hosted regression against the actual pinned NotesPanel destination ancestry, then move only the pinned navigation glass effect to its background. Preserve the existing material fallback policy. Parent verification, isolated native gestures, visual contrast/settlement checks, fresh Sol review, final packaging, and local checkpoint remain required.

### Current native evidence and menu fallback decision

The pinned candidate also corrected the initial pointer coordinate and staged native payload validation synchronously before source completion. Parent focused tests passed 59/59 (`.build/evidence/native-pointer/parent-sync-end-tests.log`). On diagnostic PID 97503, unselected Canvas reordered both ways while Relay stayed selected; observed release frames had neither a blank source tab nor duplicate neighbor displacement. Escape, reversal, outside release, reentry, and the pinned boundary preserved fixture generation/order. Canvas transferred to Unfiled successfully. These are bounded observed cases; overflow, the remaining matrix, final cleanup/review, and final bundle acceptance remain open.

A minimal actual `MenuBarExtra(.window)` control reproduced zero destination callbacks with default, clear, material, and SwiftUI `onDrop` variants. Registering the custom note type on the actual NSWindow and forwarding its destination callbacks through a retained delegate proxy produced `prepare`, `perform`, `conclude`, and source end with `.move`. Escape produced exit/end with no commit. Evidence: `.build/evidence/native-pointer/native-control-menu-window-drop.jsonl`, PID 98668. This establishes a public API path around the host's zero-sized ancestor; it does not yet approve a production proxy. Production design must preserve the original window delegate and unrelated drag registrations, use clipped target geometry, reuse session/payload validation, and retain note-to-folder behavior.

The prerequisite review requested trace removal before acceptance. The same worker removed the temporary `TabDragTrace` implementation/call sites while retaining the native-session test interceptor. Parent rerun passed 59/59 (`parent-clean-sync-tests.log`) and `swift build --product Fleck` passed. The clean executable was copied into the diagnostic bundle, signed with the repository's standard identifier requirement, and passed deep strict signature verification. Native PID 1424 repeated right/left Canvas reorders in the pinned window with Northstar selected: fixture generation 13 → 14 → 15, correct order, unchanged selection. The `clean-pinned-{right,left}` captures show readable held/released labels and no observed duplicate neighbor displacement. This is fresh clean-binary evidence, still separate from the pending menu correction and final full package.

Fresh Sol review accepted the clean pinned prerequisite (`ship`), checkpointed locally as `5008f47`. Additional clean-binary checks passed Escape (generation unchanged) and a right-padding start with immediate release (one reorder). At 500-point window width, three additional disposable notes forced overflow. Holding Relay at the right edge scrolled to the end and committed once; holding it at the left edge scrolled back and restored the first unpinned slot. Generation advanced 79 → 80 → 81 with Charlie still selected. Evidence: `clean-pinned-overflow{,-left}` captures/state under the native-pointer evidence directory. The left-edge held frame also exposes a remaining visual question: the transparent unselected drag image overlaps the pinned tab text while outside its valid slot. Release is correct; held-label readability at that boundary still needs evaluation before final acceptance.


### Menu candidate and intermittent layout crash

Parent menu-window verification passed 64/64 focused tests and the clean diagnostic build/signature checks. The delegate proxy keeps the original delegate weak, matching NSWindow.delegate ownership, while the coordinator retains the proxy. Native menu reorders in both directions committed correctly with the selected note preserved. A subsequent cancellation/boundary sequence crashed PID 5563 with EXC_BAD_ACCESS at 0x10020 in Swift exclusivity bookkeeping, through AppKit layout and CoreDrag tracking (`Fleck-2026-09-07-190438.ips`). No Fleck frame identifies the cause. This blocks acceptance; successful reorders alone do not clear it.

The same binary relaunched as PID 6259 survived isolated boundary checks, the five cancellation/boundary gestures, and a repeat including the preceding successful right/left reorders. Native folder transfer then moved Relay to Unfiled (generation 87) and back to Projects (generation 89). Evidence: `menu-history-*`, `menu-folder-transfer-settled-state.json`, and `menu-folder-return-settled-state.json`. Immediate post-driver snapshots can precede persistence; use settled state plus AX observations.

A bounded correction now targets redundant 60 Hz scrolling at a clamped edge: when the target offset equals the current offset, do not invoke scroll/reflect or republish preview state. Require a failing controller regression, parent verification, and native repetition. This removes unnecessary AppKit layout work but is only a possible contributor to the intermittent crash, not a proven root cause. The held menu drag image also has black text on a dark background and transparent overlap; appearance-aware opaque image composition remains a dependent visual packet after menu review.


The rebuilt guard candidate (PID 7499, executable SHA-256 `6cd607798b672f1ba1f1dd950b539e1f1c628fcc5c98ac1651ec55df7f478ba7`) passed 61 focused tests plus 4 lifecycle tests, but reproduced the same crash during the tight native sequence (`Fleck-2026-09-07-192011.ips`). Both crashes occurred about 1.32 seconds after the final posted mouse-up while CoreDrag was still tracking. The guard is disproven as a sufficient correction. Fresh Sol review returned `fix-first`; no dependent image implementation is accepted yet.

The same guard binary in a fresh process (PID 8127) survived the exact seven gestures when each was followed by a 2.5-second wait and explicit process-survival check. That timing difference suggests overlap or delayed completion, but callback evidence is still required. The native driver logs event submission, not source completion. Temporary opt-in callback logging is the next diagnostic step; debugger attachment was stopped when macOS requested authorization.


### Edge-hover isolation and coordinate noise

A traced failure showed the previous source completing 1.596 seconds before the failing source began, ruling out session overlap for that captured failure. A five-second held drag then crashed about 3.4 seconds before mouse-up, narrowing the trigger to active left-edge hover. The minimal menu-window control without a scroll view survived the same held position.

A DEBUG-only timer-disabled A/B passed the full sequence and five-second hold (PID 11231, final operation move). The same executable with its normal timer failed in a fresh process (PID 11439). The failing tick logged `clipX=-4.973799150320701e-14`, `targetX=0.0`, and `actualClipX=0.0` after scroll/reflect. The exact equality guard treated floating-point coordinate noise as real movement, so the earlier stop-at-clamp experiment never reached its clamped branch.

The corrected packet requires a real-controller red regression using this tiny negative offset, a minimal numerical-noise guard, and preservation of normal overflow scrolling. Parent tests, repeated unflagged native edge holds, diagnostic cleanup, and a new fresh Sol review remain required before calling the crash resolved.


The corrected guard passed 65 parent checks (`parent-noise-guard-tests.log`). With the normal timer enabled, PID 12448 reproduced the exact negative offset during a five-second native edge hold; the trace now reached the no-op guard, made no scroll/reflect call, completed with operation move, and remained alive (`menu-noise-fixed-callbacks.log`). This is a matched native correction result against the failing geometry. Temporary trace/diagnostic flags are now being removed, followed by fresh clean-binary repetition and independent review.


Two fresh clean processes (13260 and 13559) passed the full seven-gesture sequence and five-second hold (`menu-clean-noise-{1,2}-*`). A required real overflow check then cancelled without moving the note (generation 116). A long drag away from the edge succeeded (117), and its return succeeded (118). Independent review correctly remained `fix-first` for the overflow failure.

The overflow trace (`menu-overflow-invalid.log`) isolated the cancellation to source frame index 4 changing from 156×37 to 155×37; IDs, pins, and the 744×37 viewport were unchanged. The active display has scale 1, so this is one backing pixel. The corrected packet keeps frozen preview geometry and tolerates at most one backing pixel of source-size alignment drift, while preserving exact model and viewport invalidation. It requires scale-1/scale-2 boundary tests, a real-controller overflow regression with the drift, and native scrolling/commit evidence before cleanup and another review.


The one-pixel tolerance candidate passed native overflow in both directions in the actual menu window (PID 15148, window 10295). Relay moved from first unpinned to last after a three-second right-edge hold (generation 119), then returned to first unpinned after a three-second left-edge hold (generation 120). Northstar stayed selected and pinned. Both callbacks ended with operation move and no invalidation; the process survived. Evidence: `menu-overflow-pixel-{right,left}-state.json`, corresponding PNGs, and `menu-overflow-pixel-fixed.log`. Diagnostic removal, parent checks, clean-binary native repetition, and renewed independent review remain pending.


The frozen trace-free candidate passed parent serial verification: 65 tests in 3.834 seconds (`parent-clean-pixel-serial-tests.log`). An initial default-parallel parent invocation failed two presentation-layer animation timing assertions; that result is retained in `parent-clean-pixel-tests.log`. No code changed before the required serial command passed. Debug executable SHA-256: `b04909bc159d6519c7cabe17254b64247b45589c92d76856bf6595bcb7017e2e`; signed native executable: `012900322db9d585b8e55e385c6745c639dff5139b81ae11d032a908b696a8b4`.

Clean PID 15990/window 10418 passed the seven-gesture sequence with 0.7-second gaps and a final five-second edge hold, remaining alive (`menu-clean-pixel-*`). Normal right/left reorder committed generations 121/122; cancellation, reversal, outside release, reentry to the original position, and pinned-boundary hold made no unexpected mutation. Three-second overflow holds committed Relay last (123) then first unpinned (124), preserving Northstar selection and pin. Folder transfer to Unfiled (125) and return to Projects (127, after opening Unfiled) also succeeded. A renewed independent review is pending; drag-image appearance and final full package acceptance remain open.


Fresh independent Sol review returned **ship** for menu routing and edge scrolling after inspecting the frozen diff, required serial checks, codesign, live PID, and native mutation evidence. No post-launch crash report was found. This closes that functional packet and permits the separate image correction; it does not close final visual/package acceptance.

### Drag-image appearance packet

1. **Objective:** Keep selected and unselected dragged labels readable in light/dark appearance and prevent neighboring text from showing through the moving tab. Preserve source dimensions, pointer offset, captured content, and end/cancel continuity.
2. **Ownership:** The same implementation worker owns only `NotesPanel.swift` image construction and the existing `TabDragReorderTests.swift` hosted-image tests. Preserve the accepted routing/scroll changes and concurrent parent documentation.
3. **Implementation:** The current compositor images `menu-clean-pixel-image.png` and `menu-clean-pixel-selected-image.png` reproduce black text and transparent overlap. Capture under the source view's effective appearance and composite over an opaque native surface with a modest rounded outline. Preserve existing selected tint and text/icons; do not change layout, routing, lifecycle, or animation.
4. **Verification:** Establish a meaningful red image test for appearance mismatch and opaque/readable interior, then run the required serial focused suite, build, and diff check. Parent inspects held compositor frames in both hosts and verifies release/cancel continuity on the exact clean binary. Nonempty bitmap tests alone do not pass the gate.
5. **Handoff:** Return frozen diff, red/green results, and executable hash. No launch, commit, or external writes by the worker. Obtain fresh independent review after parent verification, then finish the full enhanced package and remaining interaction matrix.


The appearance regression is red: the existing real hosted NotesPanel/native dragging-item test found an opaque interior fraction of 0.0 against >0.98. Parent also captured a real light pinned host (`pinned-light-image-before.png`, PID 18117/window 10546) using a separate disposable light fixture. The menu host remains system-dark even with that fixture's light preference; native light acceptance will use the pinned host, without expanding this packet into theme propagation.


The first image correction passed 65 parent checks but failed native visual acceptance: `menu-image-fixed-{unselected,selected}.png` still shows black text and underlying label bleed. Native dumps establish `effective=VibrantDark`, while the hosted matrix used ordinary DarkAqua. Both raw cache and layer images already contain black foreground. Mapping only the current drawing appearance to DarkAqua remained insufficient (`menu-image-nonvibrant-*`); a detached windowless NSHostingView produced empty content (`menu-image-detached-*`). Neither experiment is accepted product behavior. A separate 2× bitmap probe found that representation.size must be set before NSGraphicsContext creation; the current image patch must correct that ordering and cover it with a regression.

Opaque-image controls isolate the opacity limitation: both default icon and public label components remain translucent (`control-image-icon.png`, `control-image-label-magenta.png`). A public nonactivating, mouse-ignoring preview NSPanel with native item contents nil stayed fully opaque (`control-image-panel.png`), while actual menu destination perform succeeded and source ended move. A subsequent Escape ended none and removed the panel. This permits a bounded visual-ownership rethink while retaining all accepted native drag/drop routing and session validation. Correct foreground capture remains to be proven before that product packet.


The concrete foreground diagnostic passed: `menu-image-explicit-{unselected,selected}.png` and final dumps at prefixes 215671/215676 contain readable light text and the expected pin/selection styling. The final corrected packet is now authorized through the same worker: make that label foreground production, retain real-source capture, fix 2× bitmap ordering, and use the proven note-only mouse-ignoring preview panel while native item contents are nil. Preserve native payload/session/drop routing and source window level/point geometry. Show/move through native callbacks; close on end, abort, and teardown without an orphan panel. Remove all diagnostic flags and rejected rendering paths. Require vibrant appearance and 2× raster regressions, preview lifetime/position checks, parent native dark-menu/light-pinned capture, and fresh independent review.


## Final accepted local checkpoint — 2026-09-07

The fresh Sol review returned **ship** for the frozen cumulative source/test diff and native evidence. Parent serial verification passed **67 tests** in 6.444 seconds (`.build/evidence/native-pointer/parent-panel-image-tests.log`). The final image change uses an appearance-aware captured tab, correct Retina compositing order, and a public mouse-ignoring preview panel whose lifetime follows the native source. No diagnostic flags, dumps, private APIs, or model installs remain in the product change.

Observed native evidence in `.build/evidence/native-pointer/`:

- `clean-dark-unselected`, `clean-dark-selected`, and `clean-dark-escape`: readable opaque preview, selected editor preserved, committed reorder, and unchanged generation on Escape.
- `clean-final-menu-*`: right/left reorder, reverse, Escape, outside release, reentry, and five-second pinned-boundary hold. Only the intended right/left reorders changed generations; the process remained alive.
- `clean-pad-left` and `full-light-wide`: successful starts in tab padding. `clean-pad-right` actually grabbed the adjacent Overflow Alpha tab, so it is not evidence for Relay's right edge. The final packaged `full-menu-final` starts at Relay's right edge and successfully restores its order. `clean-same-slot` leaves generation unchanged.
- `clean-light-unselected`, `full-light-selected`, `full-light-return`, and `full-light-wide`: narrow 500-point and wide 800-point pinned hosts, readable source throughout the gesture, clean committed tab through release. The earlier AX-click run's residual black outline was AccessibilityVisualsAgent feedback; fresh native-input packaged runs have no outline and no remaining preview window.
- `clean-light-edge`, `clean-light-pan-right`, and `clean-light-pan-left`: stationary edge drag reaches the last tab, returning left restores position, ordinary horizontal scrolling reveals/clips overflow without a drop.
- `full-light-outside`: invalid drop leaves generation unchanged. `full-folder-transfer` and `full-folder-return`: Relay moves to Unfiled and returns to Projects in the disposable fixture.
- Final packaged menu Activity opens and closes using its Close button and Escape; both return to the same editor host. At 500 points More formatting contains Font Size, Strikethrough, Bullets, Numbers and Checklist; at 800 points the direct controls return. Ordinary native clicks select the expected folder/note; accessibility button actions remain available.

Reduce Motion's immediate settlement path and keyboard/accessibility contracts are covered by the focused suite. System-wide Reduce Motion and a complete assistive-technology acceptance run were not exercised; do not promote these focused checks to that proof level.

Full enhanced package build succeeded via `bash scripts/build-parakeet-test-app.sh` (`final-enhanced-package.log`). The package at `.build/parakeet-test/Fleck.app` passes deep strict ad-hoc signature verification. App, Gemma helper and fleck-agent are arm64; no model weights are bundled. Executable SHA-256: `3eea301399c145bef70af05811b9979daa60e155f658c86c77c35ecff7339663`. Final verified PID 33592 runs this exact bundle against the disposable light fixture; the menu remains dark and the pinned host is light. The ordinary user workspace and original app process were not used for mutations. No real-microphone, release, recipient-install, GitHub publication, or model-quality claim follows from this UI check.

The earlier open checklist entries above describe the original test plan. This final evidence is the authoritative completion record and explicitly identifies the unexercised broader accessibility checks. Product source/test hashes remain those reviewed; the local commit contains only the focused source/tests and these design/verification documents. No external writes are authorized or performed.
