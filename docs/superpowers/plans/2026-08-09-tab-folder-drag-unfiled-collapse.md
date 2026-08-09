# Tab Folder Moves, Manual Ordering, Compact Unfiled, and Trash Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`-`) syntax for tracking.

**Goal:** Let every open note move between Unfiled and named folders by validated drag-and-drop or a keyboard-accessible context submenu, make browser-style manual tab ordering work inside every folder, persist a compact Unfiled navigator presentation, repair selected named-folder styling with hosted visual evidence, and add a note-only persistent Trash-confirmation preference.

**Architecture:** Keep `AppState.moveNote(_:fromFolderID:toFolderID:activeFolderID:)` as the only folder-membership mutation and keep `AppState.moveNote(_:inFolderID:toVisibleIndex:)` as the existing manual-order mutation. `NotesPanel` owns transient note-drop targeting, context-menu generation, the compact Unfiled row, the existing horizontal reorder gesture, the shared folder-row visual treatment, and the note Trash-confirmation presentation. `AppPreferences` owns the persisted compact and confirmation Booleans; `SettingsView` binds the confirmation preference through the existing durable preference path. The implementation starts from the released MCP Capability Profile UX head, semantically ports the accepted folder-creation morph polish onto that head, and then changes only the approved production files.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSItemProvider`/`UTType`, Swift Testing, Swift Package Manager, macOS 14+.

## Global Constraints

- Production ownership is limited to `Sources/FleckApp/NotesPanel.swift`, `Sources/FleckApp/SettingsView.swift`, and `Sources/FleckCore/AppPreferences.swift`.
- Test ownership is limited to `Tests/FleckAppTests/TabDragReorderTests.swift`, `Tests/FleckAppTests/AppStateTests.swift`, `Tests/FleckAppTests/AppKitEditorTests.swift`, `Tests/FleckAppTests/NoteDeletionConfirmationTests.swift`, and `Tests/FleckCoreTests/AppPreferencesTests.swift`.
- The implementation lane is GPT-5.6 Luna/Max only; never substitute Terra/High or another model/reasoning lane.
- The parent must run the Sol Advisor exactness check, confirm the exact native routing roles, and hand the implementation lane a bounded five-part packet: objective/success criteria, owned files/interfaces/constraints, implementation/non-goals, commands/expected evidence, and authority boundaries/handoff.
- Start only from the exact MCP Capability Profile UX Task 7 head after a fresh Sol/High reviewer returns exactly `ship` and the parent releases that accepted head.
- Semantically preserve `29ee2fa7aee08742c874eb52b8ed493469fed3f`; do not blindly cherry-pick its overlapping `NotesPanel.swift` changes over newer MCP work.
- Do not modify `Sources/FleckApp/AppState.swift` unless a new behavioral red test proves a genuine missing invariant; stop for a new narrow specification before doing so.
- Native dual-mode drag remains: the existing local horizontal gesture reorders tabs, while a valid own-process note payload dropped on a folder or Unfiled moves the note.
- Highlight only a compatible note-drop target with the accent color; never spring-open, navigate to, select, or animate a destination folder during hover.
- Every tab exposes `Move to Folder`; Unfiled is first, named folders use current display order, and the current location is checked and disabled.
- Compact Unfiled defaults expanded, persists through `AppPreferences`, remains selectable/droppable/accessibly named, and reveals its chevron on hover or keyboard focus.
- Ordering is manual only: editing, selecting, opening, searching, linking, and agent updates never sort tabs by recency. Pinned notes remain the leading/left partition of their current folder; unpinned notes remain in the user’s manual order and cannot cross that boundary.
- Named-folder pointer reordering must be proven through the real hosted/packaged production tab strip with a red-capable regression, not only through a pure Workspace or source-string seam.
- Selected named-folder shading must match the accepted selected Unfiled treatment while keyboard focus remains independently visible; source audits supplement but cannot replace hosted or packaged visual evidence.
- `confirmBeforeMovingNotesToTrash` defaults to enabled, missing preference fields use the default, malformed values throw under the existing strict preference policy, and the note-only setting can be restored from Settings.
- Drag and menu movement call `AppState.moveNote`; stale, malformed, cancelled, and same-folder actions are no-ops with zero saves.
- Preserve editor state, horizontal tab reorder, folder reorder, search/backlinks, dictation, Smart Capture, Trash, agent-access UI, folder-creation motion, and the existing AppKit editor architecture.
- Do not add spring-open folders, drag-to-Trash, multi-note/cross-window/external drag, tab auto-scroll, a new collection view, dependencies, package changes, note schema changes, generated files, or broad refactors.
- Do not add custom drag previews, folder reorder changes, folder-creation animation redesign, or a second AppKit collection/persistence/mutation system.
- Do not introduce automatic most-recently-edited ordering, a configurable sort mode, a second pinning model, or confirmation suppression for folders, history, models, agents, permanent deletion, or other non-note actions.
- Do not change search, backlinks, dictation, Smart Capture, MCP authority, capability profiles, agent behavior, or add-on behavior.
- Do not push, open or update a pull request, merge, or alter GitHub settings.

---

## File Map and Interfaces

| File | Responsibility in this plan |
| --- | --- |
| `Sources/FleckCore/AppPreferences.swift` | Add persisted `isUnfiledCompact: Bool` and `confirmBeforeMovingNotesToTrash: Bool` fields, defaults, coding keys, strict malformed-value decoding, and initializer arguments. |
| `Sources/FleckApp/NotesPanel.swift` | Preserve the accepted folder morph, add context-menu movement, keep and behaviorally prove the local reorder gesture, add type-specific folder note-drop targeting/highlight, render/operate compact Unfiled, correct shared selected-row/focus presentation, and gate all note Trash entry points through the preference. |
| `Sources/FleckApp/SettingsView.swift` | Add the exact note-only Behavior toggle using the existing `preferenceBinding` path so the confirmation preference can be restored. |
| `Tests/FleckCoreTests/AppPreferencesTests.swift` | Red/green default, missing-field, strict malformed-field, and round-trip coverage for both preferences. |
| `Tests/FleckAppTests/AppStateTests.swift` | Red/green production mutation-path coverage for valid moves, stale/malformed/same-folder no-ops, selection repair, and save counts. |
| `Tests/FleckAppTests/TabDragReorderTests.swift` | Preserve horizontal reorder contracts and add source contracts for the dual-mode tab path, folder movement menu, manual ordering/pinned partition, and compact Unfiled wiring. |
| `Tests/FleckAppTests/AppKitEditorTests.swift` | Preserve editor and accepted motion audits; add the real hosted named-folder pointer interaction, selected-row visual-state reproduction, accent target indication, compact Unfiled accessibility, and folder move wiring. |
| `Tests/FleckAppTests/NoteDeletionConfirmationTests.swift` | Add focused hosted/source regressions for the checkbox, cancel/confirm behavior, all three note deletion entry points, immediate mode, and Settings restoration. |

The existing mutation interfaces remain unchanged:

```swift
@discardableResult
func moveNote(
  _ id: UUID,
  fromFolderID sourceFolderID: UUID?,
  toFolderID targetFolderID: UUID?,
  activeFolderID: UUID? = nil
) -> Bool

@discardableResult
func moveNote(
  _ id: UUID,
  toFolderID targetFolderID: UUID?,
  activeFolderID: UUID? = nil
) -> Bool
```

The new preference interface is:

```swift
public var isUnfiledCompact: Bool
public var confirmBeforeMovingNotesToTrash: Bool

public init(
  /* existing arguments */, isUnfiledCompact: Bool = false,
  confirmBeforeMovingNotesToTrash: Bool = true,
  /* existing arguments */
)
```

The transient view-only target state is an internal `NotesPanel.swift` detail:

```swift
private enum NoteDropTarget: Equatable {
  case unfiled
  case folder(UUID)
}
```

It must never become a second persistence or mutation model.

## Execution Hold

The approved design extension is committed at `2ff39a4` on
`codex/fleck-tab-folder-drag-unfiled-collapse-design` and is the source of the
manual-ordering, pinned-left, hosted pointer-reorder, selected-folder visual,
and note-only Trash-confirmation requirements in this revision. The user has
approved that committed design; only the dependent MCP accepted-base gate
remains closed.

- Do not edit production code, create or dispatch an implementation child, or
  integrate any MCP preview/unaccepted head. The dependency gate must first
  provide a brand-new Sol/High `ship` verdict and exact accepted-head/file
  release handoff.
- After that handoff, re-check the exact accepted MCP head, then semantically
  port `29ee2fa7...` onto it and rebuild the bounded Luna/Max packet from this
  revision. Never apply the morph commit blindly to stale `NotesPanel.swift`.

## Dependency Gate: Release and Integrate the Accepted Base

This gate is completed before the feature implementation task starts. It is parent-owned orchestration work and is not satisfied by a child summary alone.

- [ ] Run the Sol Advisor orchestration exactness check and confirm the exact native routing roles before dispatch. Read the active MCP Capability Profile UX Task 7 thread and its fresh Sol/High reviewer handoff. Accept the dependency only when the reviewer’s final verdict is exactly `ship`, the released branch/head and released file set are explicit, and the head includes the accepted `NotesPanel.swift` changes. Do not start from `45c2843`, `90dd20c`, a preview head, or any fix-first intermediate.

- [ ] Inspect the released head read-only before creating the implementation worktree:

```bash
git status --short --branch
git show --no-patch --format='%H%n%P%n%s' <released-mcp-head>
git diff --check <released-mcp-head>^ <released-mcp-head>
```

Expected: the released head is present, the selected starting state is clean, and the dependency handoff identifies the exact branch/ref and commit rather than a title or inferred task state.

- [ ] Create the implementation starting state from that existing accepted MCP branch/ref. Do not start from `80d5e15`, `main`, or a stale `NotesPanel.swift` checkout.

- [ ] Compare the accepted morph commit without applying it blindly:

```bash
git diff 29ee2fa7aee08742c874eb52b8ed493469fed3f^ 29ee2fa7aee08742c874eb52b8ed493469fed3f -- \\
  Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift
```

Port exactly these accepted semantics onto the released MCP structure: `folderMorphAnimation` uses `.smooth(duration: 0.22, extraBounce: 0)` outside Reduce Motion and `nil` under Reduce Motion; folder-action buttons use the accepted accent-colored pill style; the folder-creation container uses `folderMorphAnimation`; and the corresponding source audit remains true. Preserve every unrelated MCP `NotesPanel` hunk.

- [ ] Run the morph preservation gate before adding folder movement:

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppMotionTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
git diff --check
```

Expected: exit 0 for both focused suites, the existing AppKit editor state/lifetime assertions remain present, and the diff contains only the accepted semantic morph port at this gate. Commit the integrated base as `chore: preserve folder creation morph polish` only after the parent inspects the exact diff. This commit is a dependency checkpoint, not the feature implementation.

---
### Task 1: Add the persisted compact-Unfiled and Trash-confirmation preferences

**Files:**

- Modify: `Sources/FleckCore/AppPreferences.swift`
- Test: `Tests/FleckCoreTests/AppPreferencesTests.swift`

**Interfaces:**

- Consumes: the existing `AppPreferences` Codable initializer, strict `decodeIfPresent` behavior for ordinary fields, and the tolerant `decodedSizingField` pattern only for the already-established sizing migration.
- Produces: `AppPreferences.isUnfiledCompact` (default `false`) and `AppPreferences.confirmBeforeMovingNotesToTrash` (default `true`), each encoded under its own key. Missing fields use those defaults; malformed present fields throw rather than silently changing unrelated preferences.

- [ ] **Step 1: Write the failing preference tests**

Add these tests before changing production code:

```swift
@Test func presentationPreferencesHaveSafeDefaultsAndEncode() throws {
  let value = AppPreferences()
  #expect(!value.isUnfiledCompact)
  #expect(value.confirmBeforeMovingNotesToTrash)

  let json = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(value)
  ) as? [String: Any]
  #expect(json?["isUnfiledCompact"] as? Bool == false)
  #expect(json?["confirmBeforeMovingNotesToTrash"] as? Bool == true)
}

@Test func missingPresentationPreferencesUseSafeDefaults() throws {
  let value = try JSONDecoder().decode(
    AppPreferences.self,
    from: Data(#"{"fontFamily":"Menlo"}"#.utf8)
  )
  #expect(!value.isUnfiledCompact)
  #expect(value.confirmBeforeMovingNotesToTrash)
  #expect(value.fontFamily == "Menlo")
}

@Test func presentationPreferencesRoundTrip() throws {
  var value = AppPreferences()
  value.isUnfiledCompact = true
  value.confirmBeforeMovingNotesToTrash = false

  let decoded = try JSONDecoder().decode(
    AppPreferences.self,
    from: JSONEncoder().encode(value)
  )
  #expect(decoded.isUnfiledCompact)
  #expect(!decoded.confirmBeforeMovingNotesToTrash)
}

@Test func malformedUnfiledCompactPreferenceRejectsSnapshot() {
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      AppPreferences.self,
      from: Data(#"{"fontFamily":"Menlo","isUnfiledCompact":"yes"}"#.utf8)
    )
  }
}

@Test func malformedTrashConfirmationPreferenceRejectsSnapshot() {
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      AppPreferences.self,
      from: Data(#"{"confirmBeforeMovingNotesToTrash":"yes"}"#.utf8)
    )
  }
}

@Test func unrelatedMalformedPreferenceStillThrows() {
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      AppPreferences.self,
      from: Data(#"{"isUnfiledCompact":"yes","showFormattingBar":"yes"}"#.utf8)
    )
  }
}
```

- [ ] **Step 2: Run the preference filter and verify the red state**

Run:

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppPreferencesTests
```

Expected: compilation or assertion failures identify the missing preference behavior; the malformed-field tests must fail if either new field is decoded with `try?`; no dependency-resolution failure is accepted as the red evidence.

- [ ] **Step 3: Implement the smallest Codable field**

In `AppPreferences`, add both properties beside the other UI presentation preferences, add initializer arguments with `false` and `true` defaults respectively, add both coding keys, and use strict `decodeIfPresent` calls in `init(from:)`:

```swift
public var showFormattingBar: Bool
public var isUnfiledCompact: Bool
public var confirmBeforeMovingNotesToTrash: Bool
public var automaticLists: Bool

// In init(...):
isUnfiledCompact: Bool = false,
confirmBeforeMovingNotesToTrash: Bool = true,

// In init(from:):
isUnfiledCompact: try c.decodeIfPresent(Bool.self, forKey: .isUnfiledCompact) ?? false,
confirmBeforeMovingNotesToTrash:
  try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeMovingNotesToTrash) ?? true,
```

Do not make either new Boolean tolerant via `try?`, make unrelated Boolean fields tolerant, change the preference file format, or add a separate `UserDefaults` key in `NotesPanel`.

- [ ] **Step 4: Run the preference filter green**

Run the same `AppPreferencesTests` command. Expected: exit 0, including the exact test count printed by the accepted base plus the new default, missing, round-trip, and strict malformed cases for both fields.

- [ ] **Step 5: Commit the isolated preference change**

```bash
git add Sources/FleckCore/AppPreferences.swift Tests/FleckCoreTests/AppPreferencesTests.swift
git commit -m "feat: persist tab presentation preferences"
```

Report the exact commit SHA and confirm `Package.resolved` is unchanged.

---

### Task 2: Add validated folder movement to the tab context menu

**Files:**

- Modify: `Sources/FleckApp/NotesPanel.swift` in the tab `contextMenu` and nearby movement helpers.
- Test: `Tests/FleckAppTests/TabDragReorderTests.swift`
- Test: `Tests/FleckAppTests/AppStateTests.swift`

**Interfaces:**

- Consumes: `visibleNotes`, `appState.workspace.folders`, `AppState.moveNote(_:fromFolderID:toFolderID:activeFolderID:)`, and the existing horizontal `move(_:offset:)` helper.
- Produces: a `Move to Folder` submenu whose actions resolve the current note at action time and dispatch only through the validated AppState mutation.

- [ ] **Step 1: Add red production wiring tests**

Extend `Tests/FleckAppTests/TabDragReorderTests.swift` with:

```swift
@Test func tabContextMenuExposesCurrentFolderMoveDestinations() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("Move to Folder"))
  #expect(tabStrip.contains("Unfiled"))
  #expect(tabStrip.contains("appState.workspace.folders"))
  #expect(tabStrip.contains("fromFolderID"))
  #expect(tabStrip.contains("toFolderID"))
  #expect(tabStrip.contains(".disabled"))
  #expect(tabStrip.contains("checkmark"))
  #expect(!tabStrip.contains("Trash"))
}
```

Add this AppState regression:

```swift
@Test @MainActor func folderMovesUseOneSaveAndRejectStaleOrSameFolderRequests() async throws {
  let recorder = SaveRecorder()
  let source = try folder(named: "Source")
  let target = try folder(named: "Target")
  let unfiled = Note(title: "Unfiled", folderID: nil)
  let filed = Note(title: "Filed", folderID: source.id)
  let state = await folderedState(
    workspace: Workspace(
      notes: [unfiled, filed],
      selectedNoteID: filed.id,
      folders: [source, target]
    ),
    recorder: recorder
  )

  #expect(state.moveNote(unfiled.id, fromFolderID: nil, toFolderID: source.id, activeFolderID: nil))
  try await waitForSaveCount(recorder, 1)
  #expect(state.workspace.notes.first(where: { $0.id == unfiled.id })?.folderID == source.id)

  #expect(state.moveNote(filed.id, fromFolderID: source.id, toFolderID: target.id, activeFolderID: source.id))
  try await waitForSaveCount(recorder, 2)
  #expect(state.workspace.notes.first(where: { $0.id == filed.id })?.folderID == target.id)
  #expect(state.workspace.selectedNoteID == unfiled.id)

  #expect(state.moveNote(filed.id, fromFolderID: target.id, toFolderID: nil, activeFolderID: target.id))
  try await waitForSaveCount(recorder, 3)
  #expect(state.workspace.notes.first(where: { $0.id == filed.id })?.folderID == nil)

  #expect(!state.moveNote(filed.id, fromFolderID: source.id, toFolderID: target.id, activeFolderID: nil))
  #expect(!state.moveNote(filed.id, fromFolderID: nil, toFolderID: nil, activeFolderID: nil))
  try await Task.sleep(for: .milliseconds(500))
  #expect(recorder.generations.count == 3)
}
```

- [ ] **Step 2: Run both filters and verify the red state**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppStateTests
```

Expected: the new source contract fails because no submenu exists; the AppState regression remains green or identifies only an already-covered mutation contract. The red/green evidence must cover Unfiled → named, named → named, named → Unfiled, selected-note repair, stale source, same-folder, and exact save counts. If it passes before any change, retain it as a regression and use the source-contract failure as the decisive red test.

- [ ] **Step 3: Add the current-state menu dispatch**

Add this private helper in `NotesPanel`:

```swift
private func moveVisibleNote(_ noteID: UUID, toFolderID destinationFolderID: UUID?) {
  guard let current = appState.workspace.notes.first(where: { $0.id == noteID }),
    visibleNotes.contains(where: { $0.id == noteID })
  else { return }
  _ = appState.moveNote(
    noteID,
    fromFolderID: current.folderID,
    toFolderID: destinationFolderID,
    activeFolderID: activeFolderID
  )
}
```

Inside each tab’s existing `.contextMenu`, add:

```swift
Menu("Move to Folder", systemImage: "folder") {
  Button {
    moveVisibleNote(note.id, toFolderID: nil)
  } label: {
    folderMoveMenuLabel("Unfiled", isCurrent: note.folderID == nil)
  }
  .disabled(note.folderID == nil)

  ForEach(appState.workspace.folders, id: \.id) { folder in
    Button {
      moveVisibleNote(note.id, toFolderID: folder.id)
    } label: {
      folderMoveMenuLabel(folder.name, isCurrent: note.folderID == folder.id)
    }
    .disabled(note.folderID == folder.id)
  }
}
```

Use a private label helper that shows a checkmark only for the current location. Do not include Trash in this destination list. The `ForEach` must read `appState.workspace.folders` at menu construction time.

- [ ] **Step 4: Run both filters green and inspect no-op persistence**

Run the same filters. Expected: exit 0; the tab strip still contains `DragGesture`, `TabDragReorder.performLiveMove`, current frame measurement, and the reorder `appState.moveNote` call; the valid mutation test records exactly two saves and stale/same-folder calls record none.

- [ ] **Step 5: Commit menu movement**

```bash
git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/TabDragReorderTests.swift Tests/FleckAppTests/AppStateTests.swift
git commit -m "feat: add note folder move menu"
```

---

### Task 3: Add dual-mode note drops and accent target indication

**Files:**

- Modify: `Sources/FleckApp/NotesPanel.swift` in `FolderNavigator`, `rootRow`, `folderRow`, `rowLabel`, and note-drop handling.
- Test: `Tests/FleckAppTests/TabDragReorderTests.swift`
- Test: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Test: `Tests/FleckAppTests/AppStateTests.swift`

**Interfaces:**

- Consumes: `FolderDragPayload.noteType`, `FolderDragPayload.noteValue(from:)`, existing folder reorder drop handling, and the validated `AppState.moveNote` overload.
- Produces: transient `NoteDropTarget` state, type-specific note drop modifiers on Unfiled/named rows, immediate clear-on-leave/cancel/perform behavior, and no change to the tab strip’s local reorder gesture.

- [ ] **Step 1: Add red drop-target and dual-mode source tests**

Add:

```swift
@Test func tabStripKeepsHorizontalReorderWhileFolderRowsAcceptNoteDrops() throws {
  let source = try tabNotesPanelSource()
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )

  #expect(tabStrip.contains("DragGesture"))
  #expect(tabStrip.contains("TabDragReorder.performLiveMove"))
  #expect(tabStrip.contains("FolderDragPayload.noteProvider"))
  #expect(!tabStrip.contains(".onDrop"))

  #expect(navigator.contains("NoteDropTarget"))
  #expect(navigator.contains("isTargeted:"))
  #expect(navigator.contains("FolderDragPayload.noteType"))
  #expect(navigator.contains("appState.moveNote"))
  #expect(navigator.contains("Color.accentColor"))
  #expect(navigator.contains("Unfiled"))
  #expect(navigator.contains("accessibilityLabel(\"Unfiled\")"))
}
```

Add this AppKit source audit:

```swift
@Test func folderDropHighlightDoesNotReplaceAcceptedFolderMotion() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  #expect(navigator.contains("folderMorphAnimation"))
  #expect(navigator.contains("NoteDropTarget"))
#expect(navigator.contains("accessibilityAction"))
#expect(navigator.contains("Color.accentColor.opacity"))
#expect(navigator.contains("contentShape"))
#expect(!navigator.lowercased().contains("spring"))
}
```

Add a hosted drop-lifecycle regression where the AppKit harness permits
deterministic pointer delivery: enter a named-folder row with a valid note
payload, assert the row's targeted accessibility value/highlight, leave it and
assert the target clears without changing the active folder, cancel and assert
the same no-op, then complete a valid drop and assert one move/save. Repeat
with a stale source and a deleted destination to prove the target clears and no
mutation occurs. Packaged QA remains mandatory even if the test host cannot
deliver the full drag lifecycle.

- [ ] **Step 2: Run the focused filters and verify the red state**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
```

Expected: the new source assertions fail for missing target state/highlight while existing reorder and accepted morph assertions remain green.

- [ ] **Step 3: Add transient target state and type-specific note drops**

Within `FolderNavigator`, add:

```swift
private enum NoteDropTarget: Equatable {
  case unfiled
  case folder(UUID)
}

@State private var noteDropTarget: NoteDropTarget?
@State private var isUnfiledHovered = false
```

Use a binding helper that sets the target only for the corresponding note-type drop interaction:

```swift
private func noteDropTargetBinding(
  _ target: NoteDropTarget
) -> Binding<Bool> {
  Binding(
    get: { noteDropTarget == target },
    set: { targeted in
      if targeted {
        noteDropTarget = target
      } else if noteDropTarget == target {
        noteDropTarget = nil
      }
    }
  )
}
```

Attach a note-type drop modifier with that binding to `rootRow` and each named folder row. Keep the existing folder-type drop path for folder reorder as a separate type-specific modifier. The note modifier calls `handleNoteDrop(providers:targetFolderID:)`; the folder modifier continues to call `handleFolderDrop(providers:beforeFolderID:)`. This separation ensures folder dragging does not light a note destination.

Clear `noteDropTarget` at the start of a performed note drop and after malformed/stale completion on the main actor. Keep the existing payload validation as the final gate:

```swift
guard let note = appState.workspace.notes.first(where: { $0.id == payload.noteID }),
  note.folderID == payload.sourceFolderID,
  targetFolderID == nil
    || appState.workspace.folders.contains(where: { $0.id == targetFolderID }),
  note.folderID != targetFolderID
else {
  noteDropTarget = nil
  return
}
_ = appState.moveNote(
  payload.noteID,
  fromFolderID: payload.sourceFolderID,
  toFolderID: targetFolderID,
  activeFolderID: activeFolderID
)
noteDropTarget = nil
```

Do not write `note.folderID` directly, select or navigate to the destination, or add a second save call.

- [ ] **Step 4: Add accent-only target presentation**

Pass an `isDropTarget` Boolean into shared row-label rendering:

```swift
.background(
  isDropTarget
    ? Color.accentColor.opacity(0.28)
    : (isSelected ? Color.accentColor.opacity(0.18) : .clear),
  in: RoundedRectangle(cornerRadius: 6)
)
```

Include `", Drop target"` in the accessibility value while targeted. Do not use delayed animation, spring, hover-only state, folder navigation, or destination selection for this indication. Existing `AppMotion`/Reduce Motion behavior remains the source of truth.

The target treatment must cover the full practical row hit area with an
explicit shape/content-shape treatment as well as the accent background, so a
subtle color shift is not the only affordance. It must remain visually distinct
from selected, empty, hover, and keyboard-focus states and must clear on leave,
cancel, stale completion, and successful completion.

- [ ] **Step 5: Verify valid and invalid production paths**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppStateTests
```

Expected: all exit 0; horizontal reorder, folder reorder, stale/malformed/same-folder no-op, morph, and editor source contracts remain green.

- [ ] **Step 6: Commit dual-mode drops**

```bash
git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/TabDragReorderTests.swift Tests/FleckAppTests/AppKitEditorTests.swift Tests/FleckAppTests/AppStateTests.swift
git commit -m "feat: support note drops onto folders"
```

---
### Task 4: Render and persist compact Unfiled without weakening its row contract

**Files:**

- Modify: `Sources/FleckApp/NotesPanel.swift` in `FolderNavigator.rootRow`, row-label presentation, and compact-control helpers.
- Test: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Test: `Tests/FleckAppTests/TabDragReorderTests.swift`

**Interfaces:**

- Consumes: `appState.preferences.isUnfiledCompact`, `appState.updatePreferences`, `focusedRow`, the existing Unfiled drop target, and `AppMotion`.
- Produces: expanded Unfiled by default, compact icon+count at rest, hover/focus chevron discovery, an accessible action, and a still-selectable/full-row drop target.

- [ ] **Step 1: Add red compact-row source contracts**

Add this contract test to `Tests/FleckAppTests/AppKitEditorTests.swift`:

```swift
@Test func compactUnfiledKeepsSelectionDropAndAccessibilityContracts() throws {
  let source = try notesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  #expect(navigator.contains("isUnfiledCompact"))
  #expect(navigator.contains("updatePreferences"))
  #expect(navigator.contains("isUnfiledHovered"))
  #expect(navigator.contains("focusedRow == .unfiled"))
  #expect(navigator.contains("accessibilityLabel(\"Unfiled\")"))
  #expect(navigator.contains("accessibilityAction"))
  #expect(navigator.contains("FolderDragPayload.noteType"))
  #expect(navigator.contains("count:"))
}
```

Add this preservation test to `Tests/FleckAppTests/TabDragReorderTests.swift`:

```swift
@Test func compactUnfiledDoesNotChangeNamedFolderOrTrashRowLabels() throws {
  let source = try tabNotesPanelSource()
  let navigator = try #require(
    source.components(separatedBy: "private struct FolderNavigator").last
  )
  #expect(navigator.contains("name: \"Trash\""))
  #expect(navigator.contains("name: \"Unfiled\""))
  #expect(navigator.contains("ForEach(appState.workspace.folders"))
  #expect(!navigator.contains("All Notes"))
  #expect(!navigator.contains("Inbox"))
}
```

- [ ] **Step 2: Run the filters and verify the red state**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
```

Expected: the new compact-row contracts fail before the row is changed.

- [ ] **Step 3: Add a dedicated compact-control presentation**

Keep the existing selection button and note-drop target semantics on the Unfiled row. Add a sibling disclosure button inside the row’s local container so the control is not a nested button. Its behavior is:

```swift
private var unfiledCompact: Bool {
  appState.preferences.isUnfiledCompact
}

private var showsUnfiledDisclosure: Bool {
  !unfiledCompact || isUnfiledHovered || focusedRow == .unfiled
}

private func setUnfiledCompact(_ compact: Bool) {
  guard appState.preferences.isUnfiledCompact != compact else { return }
  let update = {
    appState.updatePreferences { $0.isUnfiledCompact = compact }
  }
  if reduceMotion {
    update()
  } else {
    withAnimation(AppMotion(reduceMotion: reduceMotion).quick, content: update)
  }
}
```

Expanded state shows the tray icon, `Unfiled`, count, and a collapse chevron. Compact state shows the tray icon and count at rest; hover or keyboard focus conditionally inserts the expansion chevron. The selection button remains focusable, has a practical full-row hit target, and the outer row retains the full note drop target. The row’s `accessibilityLabel` remains `Unfiled`; its value includes count, selected/empty state, compact state, and targeted-drop state. Add an accessibility action that toggles the same preference at rest, and do not rely on hover as the only discovery mechanism. Keep selected, empty, hover, keyboard-focus, compact, and drop-target presentation states visually distinct.

- [ ] **Step 4: Verify compact rendering and editor-preservation contracts**

Run the same AppKit and tab filters. Expected: exit 0; named folders and Trash continue to use their full labels, Unfiled still has focus, selection, note drop, accessibility name/value, and the existing editor tests remain unchanged except for the new assertions.

- [ ] **Step 5: Commit compact Unfiled**

```bash
git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift Tests/FleckAppTests/TabDragReorderTests.swift
git commit -m "feat: add compact unfiled navigator row"
```

---

### Task 5: Prove and preserve manual browser-style ordering in every folder

This task is mandatory because source audits and pure Workspace coverage do not prove the user-reported browser-style live sorting behavior inside a named folder. The test must exercise the production tab strip through a real hosted AppKit event path, with packaged QA as the fallback evidence when the hosted window cannot deliver pointer events deterministically.

**Files:**

- Modify only the smallest required production subset of `Sources/FleckApp/NotesPanel.swift` if the hosted regression proves a concrete tab-strip defect.
- Test: `Tests/FleckAppTests/TabDragReorderTests.swift`
- Test: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Test: `Tests/FleckAppTests/AppStateTests.swift` only for model invariants and save/no-save evidence.

**Interfaces:**

- Consumes: the production tab-strip view, folder-scoped `visibleNotes`, `TabDragReorder.performLiveMove`, measured tab frames, real pointer coordinates, and the existing `AppState.moveNote(_:inFolderID:toVisibleIndex:)` mutation.
- Produces: manual browser-style order in Unfiled and every named folder, stable pinned-left partitioning, and a red-capable hosted/packaged regression that asserts both visible folder order and global workspace order.

- [ ] **Step 1: Write red-capable model and production-strip regressions**

Add supplementary pure coverage in `TabDragReorderTests.swift`/`AppStateTests.swift` for these invariants: reorder stays within the requested folder; pinned notes stay before unpinned notes; unpinned notes remain in the exact manual order after repeated forward and reverse moves; and editing, selecting, opening, searching, linking, or changing agent access does not sort by `modifiedAt` or any other recency signal. Assert valid reorder saves once and invalid index, stale note, malformed folder scope, cancelled drag, and same-position requests save zero times. Do not change `AppState.swift` to make these tests pass unless a red behavioral test proves a genuine missing invariant and the parent approves a new narrow specification.

Add the hosted regression in `AppKitEditorTests.swift` before changing `NotesPanel.swift`:

1. Build the existing production `NotesPanel` inside `NSHostingView` and a real `NSWindow`.
2. Create a named folder containing one pinned note and three unpinned notes in a known manual order, plus at least one hidden note outside that folder. Select the named folder through its real row interaction and settle the hosted view.
3. Locate the rendered tab controls through their production accessibility identifiers/labels and screen frames. Send an actual `mouseDown` on the first unpinned tab, `mouseDragged` events across the next two unpinned tab centers, then `mouseUp` after the third tab. Assert the named-folder order and the global workspace order are `[pinned, second, third, first]`, with the hidden note untouched.
4. Repeat in reverse by dragging the moved tab back across the other unpinned tabs. Attempt a path toward the pinned tab and assert that the pinned note remains in the leading partition and no unpinned note crosses it.
5. Exercise selection and the existing editor/title update path between reorder gestures, then assert the manual order is unchanged. The test must fail if the real named-folder pointer path does not mutate the production workspace; a pure `TabDragReorder.destination` assertion is supplementary only.

The hosted test may add narrowly scoped stable accessibility identifiers to the existing tab controls or folder rows in `NotesPanel.swift` if that is the only way to target the real views. It must not introduce a test-only reorder model or bypass the production pointer event path.

- [ ] **Step 2: Run the red tests and capture decisive evidence**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppStateTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
```

Expected: the hosted test reports the actual named-folder pointer/order mismatch if one exists; otherwise it passes with concrete pointer and order assertions. A source-string-only result is not acceptance evidence. Preserve any existing pure helper coverage even when the hosted test is the decisive gate.

- [ ] **Step 3: Implement only a proven production correction**

If the hosted regression is red, correct the smallest `NotesPanel.swift` path needed to keep the active folder’s measured tab frames, visible-note indices, and live pointer updates synchronized. Reuse `TabDragReorder.performLiveMove` and `AppState.moveNote(_:inFolderID:toVisibleIndex:)`; do not sort by recency, move through a new order model, alter pin transitions, or add automatic background reorder. If the regression is green, do not edit production merely to add abstractions. Do not touch `AppState.swift` without a new narrow specification.

- [ ] **Step 4: Rerun hosted and focused preservation suites**

Run the three filters from Step 2. Expected: named-folder and Unfiled pointer reorder pass with repeated direction changes, hidden notes remain outside the active folder, pinned notes remain left, horizontal tab reorder and folder reorder remain intact, editor/search/backlinks/dictation/Smart Capture/Trash/agent-access paths remain covered, and no automatic most-recent ordering is introduced.

- [ ] **Step 5: Commit the manual-ordering checkpoint**

```bash
git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/TabDragReorderTests.swift Tests/FleckAppTests/AppKitEditorTests.swift Tests/FleckAppTests/AppStateTests.swift
git commit -m "test: prove manual folder tab ordering"
```

If no production correction was required, omit `NotesPanel.swift` from the commit and report that the hosted regression proved the existing path.

---

### Task 6: Correct selected named-folder shading with hosted visual evidence

**Files:**

- Modify: `Sources/FleckApp/NotesPanel.swift` only after the red hosted visual reproduction identifies the smallest shared-row correction.
- Test: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Test: `Tests/FleckAppTests/TabDragReorderTests.swift` for narrow source/accessibility preservation contracts.

**Interfaces:**

- Consumes: the existing shared `rowLabel`, `FocusedRow`, selected/focus state, accessibility identifiers, and the actual SwiftUI-to-AppKit hosted window.
- Produces: selected named-folder presentation matching selected Unfiled fill, opacity, corner radius, and inset, while keyboard focus remains a distinct visible treatment and the row keeps its selected accessibility trait/value.

- [ ] **Step 1: Reproduce the bug through the hosted production view before editing**

Add a red-capable `@MainActor` hosted test that renders a workspace with Unfiled and one named folder, opens the real `NotesPanel` in an `NSWindow`, selects each row through its actual UI action, and settles layout. Capture the rendered row regions from the hosted view as disposable `NSBitmapImageRep` screenshots. Compare equivalent interior and corner pixels for selected Unfiled versus selected named-folder rows, and assert both rows expose the same accessibility label/value, selected trait, and drop behavior. Also focus the named row through the keyboard path and assert that the focus indication remains visible independently of the selected fill without a clipped native double border.

The test must use the hosted rendered view and window state, not a source scan or a guessed `rowLabel` root cause. If the CI window cannot produce stable pixels, retain the hosted accessibility/focus assertions and make the packaged QA screenshot comparison in Task 8 the mandatory visual gate; do not treat a source audit as a substitute.

- [ ] **Step 2: Run the visual regression red**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
```

Expected: the named-folder reproduction fails with concrete rendered/accessibility evidence if the reported shading defect is present. Record the captured disposable screenshot paths or measured color/frame mismatch in the parent checkpoint; do not infer the cause from the existing shared source alone.

- [ ] **Step 3: Apply the smallest shared-row visual correction**

Update the existing shared row-label presentation so selected Unfiled and selected named folders use one identical explicit fill/opacity/corner/inset treatment. Keep focus as an independent, visible treatment on every focusable folder row; if native focus is proven to create the double border, disable or replace only that native effect with the shared explicit focus treatment. Do not special-case a folder name, add a second row implementation, remove the selected trait, or make hover the only focus/discovery mechanism.

- [ ] **Step 4: Rerun hosted visual/accessibility and editor preservation gates**

Run the same two focused filters. Expected: hosted selected-row parity and focus assertions pass for Unfiled and named folders, row selection/drop/accessibility remain intact, and accepted editor state/lifetime, folder motion, and tab interaction tests remain green.

- [ ] **Step 5: Commit selected-row correction**

```bash
git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift Tests/FleckAppTests/TabDragReorderTests.swift
git commit -m "fix: align selected folder row styling"
```

---

### Task 7: Add note-only Trash confirmation suppression and Settings restoration

**Files:**

- Modify: `Sources/FleckApp/NotesPanel.swift` in the existing `requestDeletion`, `confirmDeletion`, and `DeleteConfirmationOverlay` path.
- Modify: `Sources/FleckApp/SettingsView.swift` in the existing Editing > Behavior section.
- Test: `Tests/FleckAppTests/NoteDeletionConfirmationTests.swift`
- Test: `Tests/FleckCoreTests/AppPreferencesTests.swift` for persistence cases from Task 1.

**Interfaces:**

- Consumes: `AppPreferences.confirmBeforeMovingNotesToTrash`, `AppState.updatePreferences`, existing `AppState.moveToTrash(_:activeFolderID:)`, the context-menu delete action, `FormattingBar` delete action, and `.closeNote` shortcut.
- Produces: a default-unchecked `Don't ask me again` checkbox that persists only after confirmation, immediate note-to-Trash behavior when disabled, and the exact Settings label `Confirm before moving notes to Trash` that restores confirmation.

- [ ] **Step 1: Write red preference, source, and hosted behavior tests**

In `NoteDeletionConfirmationTests.swift`, add focused tests that:

- render `DeleteConfirmationOverlay` through the production `NotesPanel` and verify the checkbox is present and unchecked by default;
- cancel after checking it and assert the note remains live and the preference stays enabled;
- confirm after checking it and assert the current note moves through `AppState.moveToTrash`, the preference becomes disabled, and the captured final saved snapshot contains both the disabled preference and the trashed note;
- exercise all three existing note deletion entry points (tab context menu, formatting-bar delete, and close-note shortcut) through the hosted production window, proving that each uses the same confirmation/immediate decision path;
- set the preference disabled, exercise each entry point again, and assert that no overlay is presented and the note is moved recoverably to Trash;
- host `SettingsView`, locate the exact Behavior toggle, turn it on after immediate mode, and assert the preference is restored and the next note deletion presents confirmation.

Add source assertions only as supplementary checks: there must be one `requestDeletion` decision boundary, the overlay checkbox must bind to transient state, all three entry points must still route through it, and non-note deletion actions must not read or change this preference. Use an actual save recorder for the combined preference-plus-Trash snapshot; do not accept only in-memory state.

- [ ] **Step 2: Run the deletion tests red**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter NoteDeletionConfirmationTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppPreferencesTests
```

Expected: the checkbox, missing preference, Settings label, or hosted entry-point assertions fail before implementation. A source-string-only pass is not sufficient for the hosted note deletion behavior.

- [ ] **Step 3: Implement the smallest preference-gated presentation**

Add the exact Behavior toggle in `SettingsView` using the existing generic `preferenceBinding` so changing it calls `appState.updatePreferences` and persists through the normal AppState path. In `NotesPanel`, keep a transient checkbox value scoped to the current overlay and reset it when presenting a new deletion request. `requestDeletion` must verify visibility, then either present the overlay when `confirmBeforeMovingNotesToTrash` is true or call the existing `appState.moveToTrash(note.id, activeFolderID: activeFolderID)` directly when false. `confirmDeletion` must revalidate the note, apply the preference update only when the checkbox is checked, clear the overlay, and call the same existing Trash mutation exactly once. Because `updatePreferences` schedules a save and `moveToTrash` immediately captures the current snapshot, verify that the final saved snapshot contains both mutations without changing `AppState.swift`.

The overlay text and checkbox must be accessibly named; cancel must never write the preference; the setting applies only to notes and never to folder/history/model/agent/permanent deletion. A missing legacy `confirmBeforeMovingNotesToTrash` field decodes enabled and malformed values reject the snapshot as required by Task 1.

- [ ] **Step 4: Rerun hosted deletion and full preference gates**

Run both filters from Step 2. Expected: all three entry points share the same default confirmation, checked confirmation suppresses only subsequent note confirmations, immediate mode reaches recoverable Trash, Settings restores the default behavior, cancellation produces no save, and the final combined save evidence is present.

- [ ] **Step 5: Commit note deletion preference**

```bash
git add Sources/FleckApp/NotesPanel.swift Sources/FleckApp/SettingsView.swift Tests/FleckAppTests/NoteDeletionConfirmationTests.swift
git commit -m "feat: add note trash confirmation preference"
```

---

### Task 8: Run the complete verification and disposable packaged-app QA gate

- [ ] **Step 1: Inspect scope and formatting before packaging**

```bash
git status --short --branch
git diff --check <accepted-mcp-head>..HEAD
git diff --name-status <accepted-mcp-head>..HEAD
git diff --exit-code <accepted-mcp-head> -- Package.resolved
```

Expected: only the approved production/test/specification checkpoint files are changed, `git diff --check` is clean, and `Package.resolved` is byte-identical to the accepted MCP head. Preserve any unrelated concurrent edits and stop if the scope expands.

- [ ] **Step 2: Run focused and full serial test suites**

```bash
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppPreferencesTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppStateTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter TabDragReorderTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppKitEditorTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter NoteDeletionConfirmationTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter AppMotionTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel --filter NotesPanelBacklinksTests
swift test --disable-automatic-resolution --disable-sandbox --no-parallel
```

Expected: every focused and full serial suite exits 0; no test relies on automatic package resolution, parallel execution, source-string audits alone, or a stale `NotesPanel.swift`.

- [ ] **Step 3: Build, validate, sign, and inspect the packaged app**

Run `Scripts/validate-macos.sh` exactly once when all code/tests are ready, then verify the produced packaged app:

```bash
Scripts/validate-macos.sh
/usr/bin/codesign --verify --deep --strict --verbose=2 .build/Fleck.app
```

Expected: the validation script exits 0, the app is signed and strict-verifiable, and the exact `.build/Fleck.app` is the artifact used for QA. Do not silently substitute a debug-only or differently built app.

- [ ] **Step 4: Perform disposable packaged-app QA**

Launch the signed app with a disposable store and verify, using real pointer/keyboard interaction and screenshots where specified: live reorder in Unfiled and a named folder with at least three notes; repeated forward/reverse movement; pinned notes left and no recency sorting after editing/selecting/searching/linking/agent updates; valid folder note drops with accent-only compatible highlighting and no spring-open/navigation; Move to Folder submenu order/current disabled state; selected Unfiled/named shading parity and distinct keyboard focus; compact Unfiled persistence and accessibility; all three note deletion entry points, checkbox/cancel/immediate behavior, Trash restoration, and Settings restoration; editor rich-text/focus/selection/undo state; folder reorder/morph; search/backlinks; dictation/Smart Capture; agent access; and Trash behavior. Remove only the disposable QA store after recording evidence.

- [ ] **Step 5: Parent verification and fresh Sol/High review**

The parent reads every changed line, independently verifies the exact accepted base and all evidence, and checks that no shared file was overwritten across concurrent work. A fresh read-only Sol/High reviewer must inspect the actual diff and evidence and return exactly `ship`. `fix-first` returns the corrected bounded packet to the same Luna/Max implementation lane; `rethink` returns to the parent architecture. No push, PR, merge, or release claim occurs before `ship`.

## Settled Extension Requirements

- Manual browser-style ordering is authoritative; never introduce automatic most-recently-edited sorting.
- Pinned notes remain in the leading/left partition of their current folder.
- Unpinned notes remain exactly where the user manually places them.
- Folder-local pointer reordering must be proven through the production tab strip, not only through the pure Workspace or TabDragReorder seam.
- The selected named-folder row must match the accepted selected Unfiled treatment. The fix must be driven by a red-capable hosted or packaged visual-state reproduction, retain visible keyboard focus, and preserve the row accessibility label/value and selected trait.
- Do not infer the named-folder shading root cause from source scans alone; source audits supplement, but do not replace, hosted or packaged visual evidence.
- Note Trash confirmation is note-only, defaults enabled, is suppressible only after a confirmed checkbox choice, and is restorable from Settings.

## Active Hold Boundary

The user has approved the committed design extension. The implementation hold
now applies only to the dependent MCP Capability Profile UX Task 7 base gate:

- Do not edit `Sources/FleckApp/NotesPanel.swift`, `Sources/FleckApp/SettingsView.swift`, `Sources/FleckCore/AppPreferences.swift`, or any feature test until the owning MCP task provides a brand-new exact Sol/High `ship` verdict and an exact accepted-head/file-release handoff.
- Do not start from `45c2843`, `90dd20c`, a preview/unaccepted head, or a stale `NotesPanel.swift`; preserve all unrelated and concurrent work.
- After the accepted handoff, port `29ee2fa7aee08742c874eb52b8ed493469fed3f6` semantically onto that final MCP head, have the parent verify the integration diff, and only then begin the red-first implementation tasks.
- The revised plan is ready to commit now. Once committed, keep the worktree clean while waiting for the dependent release; do not create or dispatch a replacement implementation task.


## Self-Review Against the Approved Specification

- Folder drag and context-menu movement converge on the existing AppState mutation, with source/destination validation and no-op save semantics covered by `AppStateTests`.
- Horizontal tab reorder remains local to the existing `DragGesture`; the plan explicitly rejects adding `.onDrop` to the tab strip.
- Target highlighting is transient, accent-colored, type-specific, and does not navigate or spring-open folders.
- Compact Unfiled is a persisted presentation preference with expanded default, hover/focus discovery, accessibility action, selection, count, and full drop target preserved.
- Manual order is authoritative in Unfiled and every named folder; pinned notes stay in the leading partition and recency-driven sorting is explicitly prohibited. A real hosted pointer regression is the decisive named-folder gate.
- Selected named-folder shading is verified through hosted rendered state or packaged screenshots, uses the same selected treatment as Unfiled, and retains independent visible keyboard focus.
- Note Trash confirmation is a strict Codable preference with a default-enabled, note-only checkbox flow, all three deletion entry points, immediate mode, combined save evidence, and Settings restoration.
- Existing folder reorder remains a separate folder payload path.
- Editor, search/backlinks, dictation, Smart Capture, Trash, agent-access, folder morph, motion, and AppKit lifetime behavior are explicitly preserved and rechecked.
- No production `AppState.swift` change is planned unless a new behavioral red test proves a genuine missing invariant and the parent approves a narrow specification; no new dependency, package change, note schema, external drag, drag-to-Trash, or broad refactor is planned.
- Every step contains concrete files, interfaces, red/green commands, expected evidence, and commit boundaries; no implementation step depends on a stale `NotesPanel.swift`.

## Plan Self-Review

- Spec coverage: the dependency gate covers accepted MCP release and morph integration; Tasks 1–4 cover preference/menu/drop/highlight/compact behavior; Task 5 covers manual ordering and named-folder pointer behavior; Task 6 covers hosted selected-row parity; Task 7 covers note-only Trash confirmation and Settings restoration; Task 8 covers serial tests, validation, signing, packaged QA, parent verification, and fresh Sol/High review.
- Placeholder scan: no step uses `TBD`, `TODO`, or an unbounded “handle edge cases” instruction. The only angle-bracket tokens are explicit command arguments whose concrete accepted SHA is selected by the parent after the hold is released.
- Type consistency: `isUnfiledCompact`, `confirmBeforeMovingNotesToTrash`, `NoteDropTarget`, `noteDropTargetBinding`, `moveVisibleNote`, the existing AppState move signatures, and the Settings generic preference binding are used consistently.
- Scope check: production ownership remains limited to NotesPanel, SettingsView, and AppPreferences; AppState is protected by the red-test/new-spec gate; no non-note confirmation, external drag, dependency, package, schema, or broad refactor is included.

## Final Spec Traceability: `2ff39a4`

- **§1 Objective and success criteria:** Tasks 2–7 cover validated folder moves, real Unfiled/named-folder pointer reorder, manual/pinned order, compact Unfiled, selected-row parity, note-only Trash suppression, accessibility, motion, and preservation of editor/search/backlinks/dictation/Smart Capture/Trash/agent-access behavior.
- **§2 Verified architecture:** Tasks 2–3 retain the own-process `FolderDragPayload` and dual-mode local gesture/drop paths; Tasks 5–6 use hosted `NotesPanel`/`NSWindow` evidence; Task 7 extends the existing `DeleteConfirmationOverlay` and Settings preference path without introducing a second organization or Trash service.
- **§3 Settled interaction design:** Task 2 specifies menu order/current disablement; Task 3 specifies compatible-only accent targeting, immediate lifecycle clearing, no spring-open/navigation, and separate folder reorder payloads; Task 4 specifies every compact Unfiled state; Task 5 specifies exact named-folder pointer sequences and pinned-boundary behavior; Task 6 specifies shared selected fill with independent focus; Task 7 specifies checkbox/cancel/immediate/Settings behavior.
- **§4 Architecture and data flow:** Tasks 2–3 route movement through `AppState.moveNote`, validate note/source/destination/current-folder state, and keep target state transient; Task 1 owns both Codable Booleans; Task 7 binds them through `SettingsView`/`AppState.updatePreferences` and verifies the combined saved snapshot.
- **§5 Failure/no-op/persistence semantics:** Tasks 2–3 and 5 cover named/unfiled moves, stale/malformed/cancelled/same-folder cases, zero-save no-ops, one-save valid moves/reorders, selected-note repair, failed-move state preservation, and pinned-boundary clamping; Task 7 covers stale pending deletion, cancel no-op, immediate recoverable Trash, and preference-only suppression.
- **§6 Accessibility and motion:** Tasks 3–4 cover semantic folder/drop states, compact hit target, label/count/selected/empty values, focus discovery, content shape, Reduce Motion, and target lifecycle; Task 6 covers selected trait and non-clipped independent keyboard focus; Task 7 covers checkbox/toggle labels and keyboard access; the dependency gate preserves accepted folder morph and toolbar motion.
- **§7 Bounded ownership:** The file map and global constraints limit production changes to `NotesPanel.swift`, `SettingsView.swift`, and `AppPreferences.swift`, limit tests to the smallest named subset, and stop for a new parent specification before any `AppState.swift` edit.
- **§8 Red-first verification:** Tasks 1–7 each begin with focused red-capable tests where practical; Tasks 5–6 explicitly reject pure Workspace/source-string-only proof and require hosted pointer/rendered-state evidence, with packaged fallback/QA mandatory.
- **§9 Packaged verification:** Task 8 runs focused suites, the full serial suite, `git diff --check`, the byte-identical `Package.resolved` check, exactly one `Scripts/validate-macos.sh`, strict `.build/Fleck.app` signing verification, and disposable-app QA for every listed interaction.
- **§10 Non-goals and handoff:** Global constraints and Task 8 exclude spring-open/navigation, multi-note/external/Trash drags, auto-scroll/previews, new models/services/dependencies/schema/refactors, recency sorting, non-note confirmation, and unrelated MCP/agent behavior; the dependency gate and final review require Luna/Max implementation and a fresh exact Sol/High `ship` verdict before any external publication.
