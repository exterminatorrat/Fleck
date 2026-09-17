# Inline Folder Creation Implementation Plan

> **Historical record:** This plan records the original pre-Build 75
> implementation and its then-current authorization and evidence boundaries.
> For the current root-authorized public-bottom replay, use
> [Bounded publication-port provenance](#bounded-publication-port-provenance).

> **For agentic workers:** Execute this bounded task through the authorized
> Astra architecture → shared-worktree Sol implementation → integrator
> verification → fresh independent Astra xhigh review sequence. This explicit
> task routing supersedes generic execution-choice or commit steps. Do not ask
> for another plan approval and do not commit.

**Goal:** Deliver a same-row folder composer and show paired navigation arrows
only when actual folder content exceeds the stable no-arrow viewport.

**Architecture:** Keep the existing native folder scroll mounted and lay out its
content at intrinsic width. Place a trailing composer overlay across the band
before Trash, using a measured alpha mask and interaction gates underneath it.
Derive overflow from an independent no-arrow reference; preserve the resting
rail allocation while composition is open.

**Tech Stack:** Swift 6, macOS 14+, SwiftUI/AppKit, Swift Testing, existing AppMotion.

## Historical implementation constraints (pre-Build 75)

- Specification: `docs/superpowers/specs/2026-09-16-inline-folder-creation-design.md`.
- Original implementation checkout: private local worktree (path intentionally omitted from
  public artifacts).
- Base commit/tree: `baf7f7885b64fcde4d3caec23dbbad7ca361b586` /
  `7866122b5d8ac9917898e843b3a313ac3983e312` (clean startup verified).
- Accepted base: record `fleck-dd5c3e2-accepted-source-measurement-package`, commit
  `dd5c3e2d027d6adde6ad79a3f7d91cc1c9d33e21`, tree
  `a8d6c703750d83651dacb96773f3d3c0e4a8034d`; canonical manifest hash
  `07c15a3e41562f12b1dbc87eac8f708c60f3577c3281862035c2f8fc420e857a`.
- Preserve the explicit reviewed feature delta through the development base:
  versioning, editor, banner, and capsule features. Stop on changed authority.
- No commits or external writes. No packaging, launch/quit/install, standalone
  QA presentation, real user data, pointer update, or new build number.
- Integrator writes only the two documents; Sol owns all product/test changes
  and corrections. Work remains together and uncommitted.
- Preserve the unrelated
  `compactUnfiledDoesNotChangeNamedFolderOrTrashRowLabels` audit unchanged. The
  publication-port base already bounds its navigator source and includes
  mutation guards, so the historical unbounded-slice failure is not an expected
  port failure.
- Exact source ownership is FolderNavigator/narrow helper in NotesPanel.swift,
  new FolderNavigatorPresentationTests.swift, directly obsolete creation audit
  assertions in AppKitEditorTests.swift, VERSION, and CHANGELOG.md. Request
  permission before any other path or wider test change.

## Task 1: Establish the regression before implementation

**Files:** New `Tests/FleckAppTests/FolderNavigatorPresentationTests.swift`.
**Consumes:** Existing NotesPanel hosted fixture patterns, temporary LocalStore,
native NSHostingView/NSWindow without standalone app/QA-host presentation.
**Produces:** A named `FolderNavigatorPresentationTests` suite of functional
assertions and preserved red evidence, not only source-string checks.

- [x] Read the owned navigator/editor, AppMotion, native drop callbacks, existing
  tests, and applicable instructions/selected native skill references.
- [x] Add a failing hosted regression that finds the real folder band and New
  folder control, opens creation, and asserts stable 32-point content height
  with a same-row field rather than the old inserted row. Keep data fixture-only.
- [x] Add overflow assertions for actual content/reference widths, including
  exact fit and a small count of long names; prefer a small production-used
  geometry value if hosted measurement needs deterministic boundary coverage.
- [x] Run `Scripts/run-nonempty-swift-tests.sh
  '^FleckAppTests\.FolderNavigatorPresentationTests/.*\(.*\)$'`, inspect exact
  matched IDs/count, and preserve a genuine failing assertion before changing
  production. A compile error alone is not the requested regression evidence.

## Task 2: Implement the band, composer, and stable overflow reference

**Files:** `Sources/FleckApp/NotesPanel.swift` (owned region only), new test suite.
**Consumes:** Existing folder data/actions, native text semantics, tab-rail style.
**Produces:** Same-row composer, intrinsic scroll content, independent width
measurement, overflow-only endpoint actions, and geometry-driven occlusion.

- [x] Replace only the creation-row layout with a 32-point band. Keep rootRow,
  one mounted folder ScrollView, and an intrinsic Trash/divider outside the
  pre-Trash overlay region. Preserve flexible viewport behavior and rename UI.
- [x] Measure intrinsic content and resting no-arrow reference independently:
  `overflow = contentWidth > noArrowViewportWidth`. Make the effective rail
  width zero when fitting and 56 only when overflowing. Do not use folder count
  or the already-reduced scroll viewport to decide overflow.
- [x] Add 28-point left/right plain chevrons with leading/trailing sentinels and
  descriptive accessibility names, matching tabs without changing tab code.
  Restore leading origin when a nonzero offset becomes fully fitting.
- [x] Keep the same folder-plus icon mounted in a trailing overlay. Opening
  reveals the plain underlined field and check/X to its right, so the icon slides
  left. Bound composer width by the whole pre-Trash band, not folder viewport.
- [x] Capture pre-composition rail allocation and retain it while open; hide its
  arrows without layout collapse. Do not change scroll identity or call scroll
  endpoints merely because composition opens/closes. Reconcile on close.
- [x] Mask underlying content with a short leading alpha fade and zero covered
  alpha. Measure row frames in the same band coordinates; gate every partially
  or wholly covered target conservatively without an opaque cover.
- [x] Extend fixtures at 380/520/640 widths for few/many/long names, compact and
  expanded Unfiled, stable height and scroll identity/offset, resize both ways,
  rename width changes, creation/deletion, and overflow → exact-fit recovery.

## Task 3: Preserve input, motion, and covered-target safety

**Files:** Same owned source region and new test suite; only directly obsolete
creation audit assertions in `Tests/FleckAppTests/AppKitEditorTests.swift`.
**Consumes:** Mounted field, row geometry, current AppState folder operations.
**Produces:** Immediate native editing and safe interaction across all paths.

- [x] Request field focus on mount without waiting for animation. If a native
  bridge is required, keep it narrow and cancel stale deferred requests on
  disappearance. Test initial readiness and open/cancel/reopen.
- [x] Centralize trimmed-empty validation for Enter/check; preserve duplicate
  draft on failure; make repeated open idempotent. Successful create must not
  select the new folder. Keep existing rename Save/Cancel UI unchanged.
- [x] Use 0.22-second smooth zero-bounce pointer motion; keyboard open/close is
  instant and Reduce Motion never moves spatially. Reverse slide/fade on close.
- [x] Prevent ancestor Return/Space/move/Delete/F2 commands from consuming native
  text/IME edits. Covered controls cannot receive focus, activation, AX actions,
  context/reorder actions, or pointer actions; leave uncovered rows operational.
- [x] Gate both acceptance and perform callbacks for SwiftUI and native
  menu-window drops, plus hover and folder reorder callbacks. Clear stale drag
  presentation on open. Test masking cannot leave a native registered target
  accepting drops behind the composer.
- [x] Adjust only obsolete creation-specific audit expectations. Preserve
  rename pills, motion/accessibility intent, flexible scroll and intrinsic Trash
  assertions. If existing audit structure conflicts, report before broadening.
- [x] Re-run the new suite to green and capture offscreen fixture snapshots of
  fitting/overflow/resting/composing states using synthetic names only.

## Task 4: Version and focused verification

**Files:** `VERSION`, `CHANGELOG.md`; read-only checks against remaining source.

- [x] Update VERSION to `1.0.4-beta.1`; add the matching `2026-09-16` changelog
  section describing same-row creation and overflow-only folder navigation.
  Leave both uncommitted with the feature; no allocator/build identity output.
- [x] Run `swift test list --disable-automatic-resolution` and inspect exact
  canonical IDs. Run the new suite with the repository nonempty runner; reject
  zero matches. Log the executed count and failures.
- [x] Run required related selectors through the same runner: folderCreationPolish,
  NotesPanelFolderScope, compactUnfiled, compactTrash, unfiledCompact,
  FolderNavigatorFocus, tabStrip, hostedNotesPanelTabOverflow, menuWindowDrop,
  pinnedChrome, and NotesPanelActionLifecycleTests. Preserve existing tests.
- [x] Run `python3 -B Scripts/fleck-build-identity.py check`, relevant ordinary
  compilation, available configured lint, and `git diff --check`. Do not package.
- [x] Report paths, exact commands/counts/logs, red/green evidence, screenshots,
  and any unverified native interactive behaviors. Do not call that acceptance.

## Task 5: Independent verification and fresh review

**Owners:** Astra integrator, then a newly created read-only Astra xhigh reviewer.

- [x] Integrator inspects actual diff against the owned scope and independently
  reruns the new/related tests and identity checks, rather than accepting a child
  report as verification. Inspect offscreen rendered evidence.
- [x] Re-read canonical manifest/sidecar and development pointer; verify no
  advancement. Confirm baseline commit/tree and unrelated features unchanged.
- [x] Create a fresh shared read-only `codex/gpt-6-astra` reviewer with xhigh
  reasoning on the exact diff, specification, and independent evidence. Review
  architecture, width feedback, focus/IME, native drops, regressions, and scope.
- [x] Send any substantive corrections to the same Sol implementer. Independently
  rerun affected checks, then obtain a fresh Astra review of the changed diff.
- [x] Deliver the uncommitted patch with docs/worktree paths, base and dirty state,
  version, evidence/counts, reviewer disposition, and remaining permitted QA.

## Plan self-review

- [x] Overflow is based on actual intrinsic width against a stable no-arrow
  reference; exact fit has neither arrows nor reserved 56-point space.
- [x] Resize, Unfiled modes, rename, creation/deletion, and previously scrolled
  content becoming fitting have explicit implementation and test steps.
- [x] Composition preserves the scroll and baseline rail; overlay width can
  cover Unfiled but cannot reach Trash/divider.
- [x] Pointer, keyboard, AX, and native menu-window drop/reorder paths are included.
- [x] Native input, validation, immediate focus, motion policy, and rename
  preservation are covered without touching persistence or note tabs.
- [x] Source and authority boundaries, red/green verification, independent review,
  and the no-commit/no-package handoff are explicit.

## Historical implementation verification recorded 2026-09-16

Evidence directory: private local `${FLECK_FOLDER_CAPTURE_DIR}` outside the repository.

- Pre-production regression: `red-folder-navigator-final.log`, exactly one
  matched functional test; old creation shifts Unfiled and Trash by 8.414 points.
- Integrator final rerun: `integrator-final-50-rerun.log`, 50 matched tests, 49 pass,
  exactly one baseline Inbox audit failure in the original development source.
  All 19 new suite tests pass. This historical failure is not carried into the
  publication port because its public-bottom test already uses a bounded source slice.
- Command:
  `Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(FolderNavigatorPresentationTests/.*|folderCreationPolish.*|NotesPanelFolderScope.*|compactUnfiled.*|compactTrash.*|unfiledCompact.*|hostedCompactUnfiled.*|FolderNavigatorFocus.*|tabStrip.*|hostedNotesPanelTabOverflow.*|menuWindowDrop.*|pinnedChrome.*|NotesPanelActionLifecycleTests/.*)\(.*\)$'`.
- Ordinary compile: `swift build --disable-automatic-resolution`, exit 0,
  `integrator-final-swift-build.log`. No separate configured Swift lint was found;
  `git diff --check` passes. No package or app launch was performed.
- Version policy: `python3 -B Scripts/fleck-build-identity.py check`, exit 0,
  `integrator-final-identity.log`; `python3 -B -m unittest discover -s Tests/Scripts
  -p test_build_identity.py`, 26 passing tests, `integrator-final-identity-tests.log`.
- Preservation: `integrator-final-authority.log` verifies the canonical sidecar,
  13 artifacts and 3 support files, accepted-source ancestry, exact development
  HEAD/tree, and only seven explicit dirty paths. The development pointer hash
  is unchanged. Source before/after FolderNavigator and its narrow helpers is
  byte-identical to the base; the unrelated baseline audit is unchanged.
- Review input product hashes: `review-final-input-sha256.json`; final
  NotesPanel SHA-256 is
  `64568db102dfc3a5cd7b67cdf7272b50b56c007fa807ab9eaefb18906b9d2789`.
- Integrator-rendered fixtures: `integrator-final-snapshots-v2/` contains
  `fitting-two-short-ab-520-resting.png`,
  `fitting-two-short-ab-520-composing.png`,
  `overflow-many-folders-520-resting.png`,
  `overflow-many-folders-520-composing.png`, and `narrow-composing-380.png`.
  A/B at 520 has no paired folder rail; many folders have the paired rail;
  narrow composition stays before Trash with no underlying content visible.
- The first independent Astra review found two reproducible issues: compact
  Unfiled lost its 28-point disclosure allocation on field focus, and Escape
  stopped cancelling after focus moved to an uncovered row. Both now have
  test-first regressions and fixes. Only disclosure frame allocation is frozen;
  its baseline visibility getter and existing audit remain unchanged. Native
  command suppression follows field-editor ownership, with additional initial
  Space and unchanged-draft refocus/Return regressions. Red evidence is in
  `astra-findings-red.log`, `focus-ownership-red-final.log`, `initial-space-red.log`,
  and `refocus-return-red.log`; the integrator's final run verifies all fixes.
- A first final run (`integrator-final-50.log`) also missed an intermediate
  animation frame in the unchanged tab test. That test passed without code
  changes in `integrator-tab-timing-rerun.log` and in the full final rerun above.
  Preserve this timing-sensitive result rather than claiming every run passed.

The evidence is automated/offscreen. Interactive pointer animation, hardware
IME, and VoiceOver remain unverified and need separate authorization. There is
no new package, build number, acceptance, GitHub CI result, or publication.

### Final independent review

A newly created read-only `codex/gpt-6-astra` reviewer at `xhigh` accepted the
exact final product diff after integrator verification, with no substantive
findings. Its independent `final-review/reviewer-50.log` reproduces 50 matched,
49 passing, and only the unchanged baseline audit failure. Its additional
offscreen cases cover long drafts, resizing during composition, explicit
compact-mode changes, and native rename submission after explicit focus.
`final-review/final-preservation.json` confirms the supplied product hashes,
seven-path scope, exact base, and unchanged active accepted authority.

The reviewer preserved a separate offscreen F2-autofocus probe that fails on
both candidate and scratch-compiled baseline navigator; it is not established
as a new regression. Full Keyboard Access and interactive native drag testing
remain open alongside the native QA limitations above. Review acceptance is
source/offscreen acceptance only. Any subsequent commit, package, or launch
handoff is owned by the root agent under its applicable user authorization.

## Bounded publication-port provenance

The reviewed feature delta was committed as
`957172c29442e037ded80d159aab8c2ec7b25cc1`, whose parent is the development
source `baf7f7885b64fcde4d3caec23dbbad7ca361b586`. Its seven-path patch was
replayed without its historical parent onto public-bottom commit
`1f44352184d0b82d0a763fc1a60c6e19c4314da9`, tree
`206224959f64fb5f6c5e41a6b45e2caff88b383f`. The port retains the original
feature behavior and tests while preserving the public-bottom changes outside
the navigator; its version is `1.0.17-beta.1`, following the bottom's
`1.0.16-beta.1`.

The publication stack is public `main` at
`d5f35ae24bc4bb78612aa348542b3c6a694776a7`, then PR 51
(`capy/menu-panel-resize-public-pr`), then this feature. Publication and stack
linking remain root-owned; this source task leaves its changes uncommitted and
does not write the bottom branch or import the original feature's parent history.

### Authorized eight-file scope and integration audit

The port owns the original seven paths listed above plus only
`TabDragReorderFolderNavigatorUsesLocalPayloadsAndKeyboardContracts` and its
local assertion logic in `Tests/FleckAppTests/TabDragReorderTests.swift`.
Independent verification passed all 19 feature tests, but the first 175-test
integration run reported one failure at that audit's original line 593. Its
whole-source text comparison placed `rootRow` before `Divider()`. That predicate
passes on the bottom source but fails on both original feature commit
`957172c` and this exact replay: the actual body now composes
`folderNavigationLayer`, `Divider()`, then `trashRow`, and `rootRow` is declared
inside the later navigation-layer helper.

The root integrator explicitly authorized this directly obsolete composition
audit to follow the new bounded body and navigation-layer fragments. The same
Sol worker retains every existing payload, drop, keyboard, label, and negative
label assertion; checks layer-before-divider-before-Trash and
root-before-scroll composition; and adds mutation guards rejecting each reversed
order. Production declarations are not shuffled to satisfy a textual audit.
The unrelated compact-Unfiled/Inbox audit remains unchanged and is not an
expected failure. No other existing test change is authorized.

### Publication-port verification commands

The integration selection is derived from `swift test list
--disable-automatic-resolution`, then supplied as an anchored alternation of
the exact discovered identifiers to the repository's nonempty AppKit runner.
It covers 175 existing tests across folder reorder, tab appearance/reorder/
selection, pinned chrome, panel action lifecycle, related AppKit editor audits
and hosted fixtures, all 63 menu-panel resize tests, and all three measured
formatting-toolbar overflow tests. The 19 original feature tests run separately.
The initial failure, the audit's isolated red/green logs, exact selectors,
independent reruns, and current synthetic captures are retained outside Git.

```sh
unset FLECK_ENHANCED_CANDIDATE
swift test list --disable-automatic-resolution
Scripts/run-nonempty-swift-tests.sh \
  '^FleckAppTests\.FolderNavigatorPresentationTests/.*\(.*\)$'
Scripts/run-nonempty-swift-tests.sh "$ANCHORED_INTEGRATION_IDENTIFIERS"
python3 -B -m unittest discover -s Tests/Scripts -p test_build_identity.py
python3 -B Scripts/fleck-build-identity.py check
swift build -c debug --product Fleck --disable-automatic-resolution
swift build -c release --product Fleck --disable-automatic-resolution
swift build -c release --product fleck-agent --disable-automatic-resolution
git diff --check
```

`ANCHORED_INTEGRATION_IDENTIFIERS` denotes the recorded exact selection, not a
wildcard or an empty default. Fresh independent Astra xhigh review must cover the
final eight-file diff and these receipts. This is focused source/offscreen
verification, not a full ordinary-suite, GitHub CI, package, live-app, hardware
IME, VoiceOver, or acceptance result.

This replay does not revise or supersede historical Build 75 source, test,
executable, or ZIP evidence preserved in the independent private
`preservation-before.json` record, and it does not package, launch, publish,
accept, or advance any development or accepted-build pointer. Paths and
evidence locations from the private implementation environment are
intentionally represented by placeholders in this public document.
