# Inline folder creation and overflow-only navigation

> **Historical record:** The original provenance, authorization, and evidence
> below describe the pre-Build 75 implementation. For the current
> root-authorized public-bottom replay, use
> [Bounded publication-port provenance](#bounded-publication-port-provenance).

## Approved outcome

Replace the separate New folder editor row with a trailing composer in the
existing folder band. The user explicitly requires left/right arrows **only
when measured folder content overflows**; two fitting folders must not show
arrows or permanently surrender a 56-point rail. This is a local, uncommitted
feature implementation, not a packaged or accepted build.

## Historical provenance and authority (pre-Build 75)

- Original implementation checkout: private local worktree (path intentionally omitted from
  public artifacts).
- Clean starting commit: `baf7f7885b64fcde4d3caec23dbbad7ca361b586`.
- Starting tree: `7866122b5d8ac9917898e843b3a313ac3983e312`.
- Accepted record: `fleck-dd5c3e2-accepted-source-measurement-package`, source
  `dd5c3e2d027d6adde6ad79a3f7d91cc1c9d33e21`, tree
  `a8d6c703750d83651dacb96773f3d3c0e4a8034d`.
- Explicit feature delta: the reviewed descendant through `baf7f7885…`, including
  accumulated versioning, editor, banner, and capsule changes. Those features
  remain intact; this work never substitutes `main` or another checkout.
- Canonical manifest SHA-256:
  `07c15a3e41562f12b1dbc87eac8f708c60f3577c3281862035c2f8fc420e857a`.
  The active registry, sidecar, 13 preserved artifacts, 3 support files, accepted
  ancestry, and clean development tree passed read-only verification at startup.
- Existing development package: `1.0.3-beta.1` Build 17, UUID
  `6b50e1cc-850e-4c98-851b-ad80ececf667`; executable SHA-256
  `fded25fa3097b972a2e3dfdae332ef9ca2e805b8b7dfef1e749b9aaf6e9bd258`, ZIP
  SHA-256 `5ec87f51eb6783124d4f727cb8dbaf476d2444ef7a47d28e8bfb362cd40a5a68`.
  These are preservation evidence, not outputs of this work.

Stop if the canonical manifest or development pointer changes. Never touch the
unrelated primary checkout. No commits, packaging, app or
standalone QA-host launch/quit/install, external writes, PR, merge, release,
acceptance, or pointer/guidance updates are authorized. Ordinary compilation,
automated fixture tests, and offscreen rendering are permitted.

## Interaction and appearance

The navigator has a stable 32-point content band plus its existing horizontal
12-point and vertical 5-point padding. Trash and its divider stay outside the
composer's usable region. The same mounted `folder.badge.plus` control moves
left as a plain native, underlined text field and check/X actions appear to its
right. There is no new pill, opaque cover, separate top row, or success flourish.
The field may cover Unfiled at narrow widths; its maximum usable width comes
from the entire navigation band before Trash, not the leftover folder viewport.

Pointer open/close uses the existing smooth 0.22-second, zero-bounce vocabulary,
with reversible slide/fade. Keyboard presentation is instant; Reduce Motion is
nonspatial, using the existing AppMotion policy. Focus is requested when the
field mounts, never after the animation. Any necessary deferred focus is
guarded/cancellable so a close cannot later steal focus. Native selection,
keyboard editing, IME, and accessibility semantics remain native.

Enter and check create; Escape and X cancel. A trimmed-empty draft cannot submit
through either path. Failed validation, including duplicates, preserves the
draft and editing state. Reopening an already-open composer must not erase the
draft. Successful creation/cancellation reverses presentation, clears draft,
and retains existing no-auto-select creation semantics. Rename keeps its
existing editor, Save/Cancel actions, and behavior.

## Geometry and overflow

Keep one mounted horizontal scroll view and stable folder identities. Measure
the actual intrinsic folder-content width, including spacing and the active
rename editor, rather than folder count. Prevent chip compression/reflow by
measuring and laying out the intrinsic content, not by fixing the scroll view.

Let `referenceWidth` be the folder viewport that would be available with **no
arrows** in the resting band, accounting for actual Unfiled width, the resting
24-point New folder control, and existing spacing. Overflow is strictly
`contentWidth > referenceWidth`; exact fit does not overflow. Never compare
against the viewport already reduced by the arrow rail. This independent
reference prevents feedback loops and allows arrows to disappear on resize,
rename, creation/deletion, and compact/expanded Unfiled changes.

When overflow is true, reserve a 56-point rail of paired 28-point plain chevron
actions. Match the note-tab controls' leading/trailing endpoint behavior and
style without modifying note tabs. When false, reserve zero rail width and
restore the leading scroll origin if previously scrolled content now fully
fits. A small-folder long-name case can overflow; many short folders can fit.

While composing, preserve the baseline mounted viewport and rail allocation;
the overlay must not relayout or scroll the folder strip. Hide/disable arrows
without collapsing their reserved space. Freeze the pre-composition rail
decision, not the whole band dimensions: resizing still fits the window.
Reconcile current measurements when composition closes.

## Occlusion and interaction safety

Apply an alpha mask to the underlying navigation content: a short fade just
before the composer's leading edge, then zero alpha for covered content. Do
not paint an opaque background over the pinned material. Keep the composer
above the masked content and wholly before the Trash divider.

Use geometry in one common pre-Trash coordinate space to classify covered
targets. Conservatively gate a partly covered control as well. Covered rows
must be removed from pointer, keyboard-focus/activation, and accessibility
interaction. Guard both SwiftUI and native menu-window note-drop acceptance,
hover, and perform callbacks, plus folder reorder entry/perform callbacks;
masking and `allowsHitTesting` alone do not gate native registered anchors.
Clear stale hover/reorder state on opening. Uncovered controls and Trash retain
their normal behavior. Parent Return/Space/move/Delete/F2 handlers must not
consume text editing or IME commands.

## Ownership and implementation shape

Only these files are owned:

- `Sources/FleckApp/NotesPanel.swift`: FolderNavigator and a narrowly scoped
  presentation/geometry or native-field helper only.
- New `Tests/FleckAppTests/FolderNavigatorPresentationTests.swift`: functional
  layout/state and hosted fixture regression tests.
- `Tests/FleckAppTests/AppKitEditorTests.swift`: directly obsolete
  creation-specific source-audit assertions only; retain meaningful rename,
  motion, accessibility, flexible-scroll, and Trash intrinsic-width checks.
- `VERSION` and `CHANGELOG.md`: paired `1.0.4-beta.1`, dated `2026-09-16`.
- This specification and its corresponding implementation plan.

Prefer existing SwiftUI state, native text input, small value geometry, and
ScrollViewReader endpoints. A small AppKit bridge is allowed only for a proven
native capability gap. Do not add dependencies, general drag architecture,
persistence changes, a new product register, or a broad view-model extraction.

## Historical implementation evidence and open acceptance (pre-Build 75)

Write and run a failing functional regression before production changes. Verify
380/520/640-point fixtures with few/many/long folders, exact fit, both resize
directions, nonzero offset becoming fitting, Unfiled modes, rename, create/delete,
stable band height, scroll identity/offset through composition, immediate field
readiness, cancel/reopen, whitespace/duplicate handling, and covered native
drop/reorder/keyboard/accessibility behavior. Use pure layout tests for exact
boundaries and hosted real views for wiring; source-text checks are not a
substitute for new functional coverage.

Run the repository nonempty test runner for the new suite and required related
selectors, the build-identity check, and relevant compilation/lint. Preserve
logs in a private local `${FLECK_FOLDER_CAPTURE_DIR}` or this worktree's ignored `.build`.
The integrator independently inspects/reruns evidence, then a fresh read-only
GPT-6 Astra reviewer at xhigh reviews the actual diff and evidence. Interactive
native typing/IME, visual motion, and VoiceOver QA still require separately
authorized presentation; do not claim they were exercised from pure tests.

### Historical baseline audit result

`compactUnfiledDoesNotChangeNamedFolderOrTrashRowLabels` failed against the
original untouched development source because its source slice started at
FolderNavigator and continued through EOF, finding the unrelated later phrase
“saves to Inbox.” The publication-port base already uses a bounded navigator
source helper with mutation guards. Preserve that public-bottom audit unchanged
and do not treat the historical Inbox failure as an expected port failure.

## Bounded publication-port provenance

The reviewed feature delta was committed as
`957172c29442e037ded80d159aab8c2ec7b25cc1`, whose parent is the development
source `baf7f7885b64fcde4d3caec23dbbad7ca361b586`. This publication port initially
replayed only that seven-path delta onto public-bottom commit
`1f44352184d0b82d0a763fc1a60c6e19c4314da9`, tree
`206224959f64fb5f6c5e41a6b45e2caff88b383f`, without importing the historical
parent. The product version becomes `1.0.17-beta.1`, following the bottom's
`1.0.16-beta.1`, while public-bottom behavior outside the owned navigator scope
remains authoritative.

The root integrator then authorized local feature checkpoints and an ordinary
merge of the bottom owner's test-isolation fix. That intermediate PR 51 base is
`f7fdd32e51b4e99f7a9eae166684c979c0ee5019`, tree
`e84f20d3236765acbba1d9a9e6c5da1254fecd9e`, on the same bottom branch. The top
branch is `capy/inline-folder-creation-pr`; it preserves both bottom fixture
files, without changing bottom production code or version. Root owns publication
and the serialized native-fixture verification slot. No bottom branch rewrite or
historical feature-parent import is part of this reconciliation.

The final current PR 51 base is
`173f29aa6f852518a119dd990c3375f97de4d264`, tree
`5af9a085544563952ab5d65925eb894d0d56a4ac`. The bottom owner changed only the
ordinary macOS CI timeout from 30 to 60 minutes, without removing a gate or
changing any source, test, version, or package blob. A root-authorized ordinary
merge preserves the completed native and non-native receipts by exact blob
comparison; it does not require another native run or imply a green CI result.

The root integrator separately authorized one directly obsolete composition
audit in `Tests/FleckAppTests/TabDragReorderTests.swift`, making the final scope
eight files. Its raw source-order assertion fails on both the original feature
and this replay because `rootRow` moved into the later `folderNavigationLayer`
helper. The bounded replacement checks the actual layer/divider/Trash and
root/scroll composition, with mutation guards rejecting reversed order. It
retains all existing payload, drop, keyboard, and label checks without changing
production behavior or the unrelated compact-Unfiled audit. See the plan's
integration record for the exact evidence and scope.

Historical Build 75 source, test, executable, and ZIP evidence preserved in
the independent private `preservation-before.json` record remains historical
and is not modified, promoted, or used as an acceptance claim by this replay.
The port does not package, launch, publish, accept, or advance a development or
accepted-build pointer. Private implementation and evidence paths are omitted
or represented by placeholders in this public specification.
