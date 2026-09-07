# Native Tab Drag Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Preserve the current native-subagent lane and return corrections to the same worker.

**Goal:** Restore visible, reliable direct tab dragging and verify the complete gesture autonomously.

**Architecture:** Use the user's physical failure report as the behavioral red case; validate the input driver before using automated results to assign a cause. Retain existing reorder and drop validation; if the current source fails real input, replace only note gesture initiation with a native source owning its image and event lifecycle.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, computer-use visual inspection.

## Global Constraints

- Worktree: `/Users/harryjin/Fleck/.worktrees/editor-three-bug-fixes`, base candidate `318a9ef`.
- No external writes. Preserve unrelated edits and accepted Activity/toolbar behavior.
- Same existing implementation worker, active Sol High override; fresh Sol High review after verification.
- Product ownership limited to `Sources/FleckApp/NotesPanel.swift` `Tests/FleckAppTests/FolderReorderInteractionTests.swift`, and the affected hosted drag test in `Tests/FleckAppTests/TabDragReorderTests.swift` (amended to balance its native mouse-up); preserve unrelated tests.
- User authorized autonomous implementation; no further design approval gate.
- Alternative OS pointer driver requires the currently pending explicit authorization under computer-use rules.

### Task 1: Establish trustworthy red evidence

- [x] Inspect current source ownership: actual native session retains ReorderNativeSource.
- [x] Try disposable Chrome A/B/C with current computer-use drag: no reorder, so driver remains unvalidated.
- [ ] Validate a complete pointer sequence in Chrome; capture before, mid-gesture, and after order.
- [ ] Repeat identical geometry-aware procedure in Fleck, record selected/unselected state and native begin/move/end callbacks. If Chrome succeeds and Fleck fails, this establishes the red GUI case. If both fail, repair the test driver before claiming GUI acceptance. The user's physical failure report independently authorizes the bounded source repair.

### Task 2: Repair the proven source defect

**Files:** `Sources/FleckApp/NotesPanel.swift`, `Tests/FleckAppTests/FolderReorderInteractionTests.swift`.
**Consumes:** existing ReorderDragHost begin provider/end closure, onBegan/onMoved callbacks, ReorderDropSession acceptance, FluidTabDragController.
**Produces:** a note gesture with visible native image and reliable begin/end lifecycle; existing destination interfaces remain stable.

- [x] Send worker the five-part bounded specification with the observed red trace. Require exact correction design and failing behavior tests before implementation; do not guess callback causes from synthetic events.
- [ ] Add focused regression cases for the observed defect. For a direct gesture replacement, cover subthreshold click exactly once, threshold drag without selection, padded hit area, retained source, nonempty image captured before hiding, cancel restore, and load/end completion ordering. Keep existing stale-session, provider validation, partition and no-op update tests.
- [ ] Run `swift test --filter FolderReorderInteractionTests` and confirm the intended new assertions fail rather than merely a build failure or zero tests.
- [ ] Implement the minimal correction. For a bridge, event sequence is `mouseDown -> store event/point; mouseDragged -> distance >= 4 -> create one payload/image/session; mouseUp below threshold -> existing activation`. Capture and use the current bounds as dragging frame; retain current native callback validation. Leave folder dragging on its existing path.
- [ ] Run `swift test --filter 'FolderReorderInteractionTests|TabDragReorderTests|NotesPanelActionLifecycleTests'`; inspect all results and nonzero test counts.
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
