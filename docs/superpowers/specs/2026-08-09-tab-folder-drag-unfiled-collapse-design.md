# Tab Folder Moves, Manual Ordering, Compact Unfiled, and Trash Confirmation Design

**Date:** 2026-08-09

**Status:** Approved interaction design; implementation pending

**Scope:** Repair folder-local tab ordering, move tabs between folders, compact Unfiled, align selected-folder styling, and optionally suppress note-to-Trash confirmation

## 1. Objective and Success Criteria

Fleck should make ordering and moving open notes feel as predictable as browser tabs and Finder files. Manual left/right ordering must work inside every folder, pinned notes must remain a stable leading group, and moving a tab between folders must not weaken either behavior. The Unfiled navigator row should be collapsible, named-folder selection should look as coherent as Unfiled selection, and users who understand Fleck's recoverable Trash should be able to suppress repeated note-deletion confirmation.

The feature succeeds when:

- A note tab can be dragged onto a named folder or Unfiled and is moved only after a valid drop.
- Horizontal dragging within the tab strip reorders tabs in Unfiled and every named folder through the real pointer interaction.
- Tab order remains entirely user-controlled; editing or selecting a note never sorts by recency.
- Pinned notes remain in the leading partition of their current folder, while each partition retains manual order.
- A compatible folder target highlights while the dragged note is over it, but the folder never opens automatically.
- Every note tab has a `Move to Folder` context submenu that can move it to Unfiled or any named folder.
- Drag and context-menu moves share the existing `AppState.moveNote` mutation path.
- Moving the selected note repairs selection predictably, persistence is scheduled once, and malformed, stale, cancelled, or same-folder operations are no-ops.
- Unfiled can be collapsed to its icon and note count, remains selectable and droppable, and can be restored.
- The compact preference survives relaunch and defaults to expanded for existing and new users.
- Selected named folders use the same coherent background treatment as selected Unfiled; keyboard focus remains visible without a clipped or doubled highlight.
- Note-to-Trash confirmation offers `Don't ask me again`, applies consistently to every note-deletion entry point, and can be restored from Settings.
- Accessibility, Reduce Motion, editor state, search, backlinks, folder creation motion, Trash, agent-access UI, and existing reorder behavior remain intact.

## 2. Verified Existing Architecture

The implementation must extend the current SwiftUI/AppKit architecture rather than introduce a second organization system.

- `NotesPanel` renders the real note tabs and each visible tab already emits an own-process `FolderDragPayload` containing `noteID` and `sourceFolderID`.
- The tab strip already uses a local drag gesture for live left/right reordering. Folder moves must coexist with that gesture instead of replacing it.
- `Workspace.reorderNote` and `AppState.moveNote(...toVisibleIndex:)` already preserve pinned and unpinned partitions while persisting manual order. Existing pure tests do not prove the real named-folder pointer path works.
- Folder navigator rows already accept note drops, and Unfiled already has a note-drop destination.
- The current drop handler validates that the note still exists and remains in the payload's source folder before moving it.
- `AppState.moveNote` is the production folder mutation boundary. It validates the destination, treats a same-folder move as a no-op, repairs selected-tab state when necessary, and schedules one save.
- `FolderNavigator.rootRow` currently renders the Unfiled icon, label, spacer, and count. Its compact presentation must be local to Unfiled rather than changing the shared named-folder and Trash row label.
- Unfiled and named folders already call the same `rowLabel` builder for selection fill, so the reported named-folder visual defect must be reproduced at the hosted production wrapper rather than guessed at from source text.
- Tab context menus do not currently expose folder movement.
- `DeleteConfirmationOverlay` currently gates note moves to recoverable Trash from the context menu, formatting controls, and close-note shortcut. `AppPreferences` and the Settings Behavior section are the existing durable-preference path.

Existing source-audit tests are useful as wiring checks, but they are not sufficient proof of Finder-like drag behavior. The correction requires behavioral coverage through the production views and mutation paths wherever the test harness permits.

## 3. Settled Interaction Design

### 3.1 Dual-mode tab dragging

The same note tab supports two outcomes:

| Gesture state | Result |
| --- | --- |
| Drag remains in the tab strip | Existing live horizontal tab reorder |
| Drag enters a compatible folder or Unfiled target | Target row receives the accent-colored drop highlight |
| Valid drop on another location | Move the note through `AppState.moveNote` |
| Drop on its current location | No mutation and no save |
| Drag leaves the target or is cancelled | Remove highlight and preserve all state |
| Stale or malformed payload | Reject the drop without mutation |

The folder row highlight is the only added drag affordance. Fleck will not spring-open folders, switch the visible folder, select the destination, or animate a navigation change during hover. This prevents accidental context changes while still making the destination unambiguous.

The highlight uses the user's accent color and follows the actual drop-target state. It appears and clears immediately; it must not lag behind the pointer or remain after cancellation. In Reduce Motion mode, no spatial motion is introduced.

### 3.2 Context-menu movement

Each note tab gains a `Move to Folder` submenu.

- `Unfiled` appears first.
- Named folders follow the navigator's displayed order.
- The note's current location is marked and disabled.
- Choosing another location performs the same validated `AppState.moveNote` call as a drag-and-drop move.
- Trash is not a folder-move destination. Existing deletion and Trash behavior remain separate.
- The menu is generated from current workspace state when opened; it does not retain stale destination snapshots.

This menu is the precise, keyboard-accessible alternative when dragging is inconvenient.

### 3.3 Compact Unfiled control

Unfiled defaults to its current expanded form. A dedicated collapse control changes only the Unfiled row:

- Expanded at rest: Unfiled icon, `Unfiled` label, count, and collapse affordance.
- Collapsed at rest: Unfiled icon and count only.
- Collapsed while hovered or keyboard-focused: reveal a chevron affordance so expansion is discoverable without permanently consuming width.
- The compact control remains selectable and remains the full drop target for moving notes back to Unfiled.
- The selected, empty, hover, focus, and targeted-drop states remain visually distinct.
- The control's accessibility label continues to announce `Unfiled`, its note count, and relevant selected/empty state even when the visible text is hidden.

The expanded/collapsed choice is stored as an application preference. A missing value decodes as expanded and valid values round-trip. A malformed value follows the normal strict preference policy and rejects the snapshot; tolerance remains restricted to fields that already have an explicit recovery contract.

### 3.4 Manual ordering and pinned partitions

Fleck uses one ordering model in Unfiled and every named folder:

- Order changes only through explicit user actions such as pointer drag, Move Left, Move Right, pin, or unpin.
- Editing, selecting, opening, searching for, linking to, or receiving an agent update for a note never changes its position.
- Pinned notes form the leading partition in the current folder, matching browser pinned-tab behavior.
- Unpinned notes cannot be dragged ahead of the pinned partition, and pinned notes cannot be dragged into the unpinned partition.
- Manual relative order is retained within each partition.
- Pinning or unpinning retains the repository's established partition transition semantics; this feature does not add recency sorting or a configurable sort mode.

The implementation must first establish a deterministic red-capable reproduction of the reported real pointer failure in a named folder. Passing the existing pure `Workspace` reorder tests or scanning for `DragGesture` is not sufficient.

### 3.5 Selected named-folder presentation

A selected named folder uses the same fill color, opacity, corner shape, and inset treatment as selected Unfiled. Pointer selection must not leave a clipped native focus artifact or a doubled selection border.

Keyboard focus remains independently visible for both Unfiled and named folders. If the native focus effect is the proven cause, the implementation may replace it only with one shared explicit focus treatment applied to every folder row. The implementation must not remove keyboard focus indication, special-case a single folder name, or introduce a second row-style system.

### 3.6 Note-to-Trash confirmation preference

The current confirmation overlay gains an unchecked `Don't ask me again` checkbox.

- Confirming with the checkbox unchecked moves the note to recoverable Trash and leaves the preference enabled.
- Confirming with the checkbox checked disables future note-to-Trash confirmation and moves the current note exactly once.
- Cancelling never changes the preference, regardless of checkbox state.
- When confirmation is disabled, every production note-deletion entry point moves the visible note directly to recoverable Trash through the existing `AppState.moveToTrash` path.
- Settings > Editing > Behavior exposes `Confirm before moving notes to Trash`, allowing confirmation to be restored or disabled explicitly.
- The preference applies only to notes. Folder deletion, dictation-history deletion, model deletion, agent-activity clearing, and permanent Trash lifecycle behavior are unchanged.

The default is confirmation enabled. Legacy preferences missing the field decode to enabled. A malformed value follows the normal strict preference policy and rejects the snapshot; tolerance remains restricted to fields that already have an explicit recovery contract.

## 4. Architecture and Data Flow

### 4.1 One movement path

Both entry points converge on the existing application mutation:

```text
tab drag payload ──> validated folder drop ──┐
                                             ├──> AppState.moveNote(noteID, destination)
tab context menu ──> current destination ───┘
```

No view writes `Note.folderID` directly. No new persistence format is needed for folder membership. The existing move operation remains responsible for validation, selected-note repair, workspace mutation, and save scheduling.

### 4.2 Drag state ownership

The folder navigator owns only transient presentation state identifying the currently targeted destination. It does not own a second drag payload model or a speculative folder move.

The existing `FolderDragPayload` remains the transport contract. Drop validation must confirm:

1. The payload is a supported own-process note payload.
2. The note still exists.
3. The note's current folder still matches `sourceFolderID`.
4. The destination folder still exists, unless the destination is Unfiled.
5. Source and destination differ.

Only after validation may the view invoke `AppState.moveNote`.

### 4.3 Preference ownership

The compact-Unfiled Boolean and `confirmBeforeMovingNotesToTrash` Boolean belong in `AppPreferences`. The production UI binds to those persisted values; it must not introduce independent `UserDefaults` keys inside `NotesPanel` or `SettingsView`.

All note-deletion entry points converge on one decision before the existing Trash mutation:

```text
context menu / formatting bar / close-note shortcut
                    |
                    v
        request note deletion while visible
                    |
         +----------+-----------+
         |                      |
 confirmation enabled    confirmation disabled
         |                      |
 overlay confirm          AppState.moveToTrash
         |
 optional preference update + AppState.moveToTrash
```

Checking `Don't ask me again` and confirming must persist a final snapshot containing both the disabled preference and the trashed note. The implementation may reuse the repository's generation-aware save behavior; it must not create a second Trash service or directly mutate persisted files.

### 4.4 Integration base

`NotesPanel.swift` is shared by active accepted work. Implementation must start only after these dependencies are settled:

1. The MCP Capability Profile UX lane receives an exact fresh Sol `ship` verdict and releases its accepted head, including its `NotesPanel` changes.
2. The latest accepted folder-creation morph polish at `29ee2fa7aee08742c874eb52b8ed493469fed3f6` is semantically ported onto that accepted MCP head and independently verified.
3. This feature is implemented from the resulting combined accepted base.

The folder-motion commit must not be blindly cherry-picked over newer `NotesPanel` work. The port must preserve both behaviors explicitly.

## 5. Failure, No-op, and Persistence Semantics

- Same-folder drops and current-location menu choices perform zero workspace mutations and schedule zero saves.
- A cancelled drag changes no model state and clears transient target state.
- A payload whose note was deleted or moved after drag start is rejected.
- A payload with an unavailable or deleted destination is rejected.
- A failed move does not change the selected folder, selected note, editor contents, selection, undo stack, or scroll position.
- A successful move schedules exactly one persistence operation through the existing mutation path.
- If the selected note leaves the visible folder, the existing nearest-remaining-tab selection rule is preserved; no duplicate selection policy is added in the view.
- Dropping on Unfiled while it is compact uses identical validation and persistence semantics to the expanded row.
- A pointer drag that does not cross a valid tab target leaves manual order unchanged. A valid folder-local reorder schedules exactly one existing reorder save.
- Dragging across the pinned boundary clamps to the correct partition and never toggles pin state.
- Cancelling note deletion changes neither the note nor the confirmation preference.
- A stale or no-longer-visible pending note is not deleted when its overlay is confirmed.
- Disabling confirmation bypasses only the presentation step; existing locked-note, visibility, Trash, save, and selection guards remain authoritative.

## 6. Accessibility and Motion

- Every folder target exposes a meaningful accessibility label and drop behavior through the production row.
- The context submenu is fully keyboard reachable and uses the same destination names shown in the navigator.
- Compact Unfiled retains a minimum practical hit target and never relies on the icon alone for its accessibility name.
- Hover is not the only way to discover expansion: keyboard focus also exposes the affordance, and the accessibility action remains available at rest.
- Target indication uses both shape/background treatment and existing semantic row state; it must not depend solely on a subtle color shift.
- Selection and focus are separate states: the selected fill matches across Unfiled and named folders, while focus remains visible and accessible without a double highlight.
- The `Don't ask me again` checkbox and Settings toggle have explicit labels, values, and keyboard access; destructive confirmation retains the default/cancel keyboard contract.
- Any compact/expanded transition uses the app's existing restrained local motion. Reduce Motion takes a direct state-change path with no spatial animation.
- Folder creation morph timing and formatting-toolbar motion are preserved as accepted; this feature does not retune them.

## 7. Bounded Ownership for Implementation

Expected production ownership is limited to:

- `Sources/FleckApp/NotesPanel.swift`
- `Sources/FleckApp/SettingsView.swift`
- `Sources/FleckCore/AppPreferences.swift`

Expected test ownership is limited to the smallest relevant subset of:

- `Tests/FleckAppTests/TabDragReorderTests.swift`
- `Tests/FleckAppTests/AppStateTests.swift`
- `Tests/FleckAppTests/AppKitEditorTests.swift`
- `Tests/FleckAppTests/NoteDeletionConfirmationTests.swift` if a focused new file is smaller than expanding an unrelated suite
- `Tests/FleckCoreTests/AppPreferencesTests.swift`

`AppState.swift` should not need production modification because `moveNote` already supplies the required semantics. If a behavioral test proves a genuine missing invariant, any expansion must stop for a new narrow specification before editing it.

Every later implementation task must preserve unrelated changes, adapt to the accepted integration base, and avoid rewriting adjacent `NotesPanel` code.

## 8. Verification Contract

### 8.1 Red-first focused regressions

Where practical, each behavior begins with a failing regression:

- Moving Unfiled to a named folder, named folder to another folder, and named folder to Unfiled.
- Real pointer-driven manual reorder inside Unfiled and a named folder, including more than two tabs and repeated direction changes.
- Pinned-leading enforcement and stable manual order inside both pinned and unpinned partitions.
- Editing and selecting a note do not reorder it by `modifiedAt` or recency.
- Same-folder, stale-note, stale-source, malformed-payload, and cancelled-drop no-ops.
- Exactly one scheduled save for a valid move and zero for a no-op.
- Selected-note repair through the existing application path.
- Context submenu ordering, current-location marking/disablement, and production move dispatch.
- Target highlight entering, leaving, cancelling, and completing a drop.
- Horizontal tab reorder remains functional after folder-drop support is enabled.
- Compact preference default, missing-field decode, round-trip, and strict malformed-type rejection.
- Expanded and compact Unfiled rendering, selection, count, hover/focus affordance, accessibility naming, and active drop target.
- Hosted selected-state parity between Unfiled and named folders, plus a distinct non-clipped keyboard-focus state. The screenshot-reported wrapper path must be exercised; a shared-builder source audit alone is not proof.
- Confirmation default/missing-field decode, valid round-trip, strict malformed-type rejection, checkbox confirm/cancel behavior, immediate mode, Settings restoration, and all three note-deletion entry points.
- The final saved snapshot includes both the disabled confirmation preference and the one intended Trash mutation when `Don't ask me again` is confirmed.
- Real editor contents, selection, typing attributes, command attachment, and undo availability survive moving an open note and compacting/restoring Unfiled where the hosted AppKit harness can observe them.

Source audits may verify that production modifiers and accessibility contracts are attached, but they supplement rather than replace hosted behavioral tests.

### 8.2 Parent verification

The primary Sol session must inspect every changed line and independently run:

1. The focused preference, application-state, drag/reorder, and AppKit editor regressions.
2. The full serial Swift test suite with automatic dependency resolution disabled.
3. `git diff --check`.
4. A byte comparison confirming `Package.resolved` is unchanged.
5. `Scripts/validate-macos.sh` once after the correction is ready.
6. Strict code-sign verification for the rebuilt `.build/Fleck.app`.

Exact commands and expected test counts belong in the implementation plan after the final integration base is known.

### 8.3 Packaged-app QA

Use only disposable QA notes and never edit a personal note. In the exact rebuilt `.build/Fleck.app`, verify:

1. Existing left/right tab reordering still works.
2. The same live left/right behavior works inside a named folder with at least three disposable notes.
3. Pinned notes remain at the left, and editing notes never changes order.
4. Dragging an Unfiled tab over a folder highlights only that destination.
5. Leaving or cancelling clears the highlight and changes nothing.
6. Dropping moves the note without opening the destination folder.
7. Moving a named-folder tab to another folder and back to Unfiled works.
8. The context submenu performs the same moves and disables the current location.
9. Selected Unfiled and selected named-folder shading match; pointer focus does not create a broken outline, while keyboard focus remains visible.
10. Collapsing Unfiled shows only its icon and count at rest; hover and keyboard focus reveal expansion.
11. Compact Unfiled remains selectable and accepts drops.
12. Relaunch preserves the compact state, and expansion restores the full row.
13. Confirming a disposable note with `Don't ask me again` moves it once; subsequent context-menu, toolbar, and shortcut deletions bypass confirmation and remain recoverable in Trash.
14. Re-enabling `Confirm before moving notes to Trash` in Settings restores the overlay.
15. Editor text, selection, undo, search/backlinks, folder creation, agent-access UI, Trash, and pinned/menu presentation remain intact.

## 9. Explicit Non-goals

This change does not add:

- Spring-loaded folder opening or automatic destination navigation.
- Multi-note drag, cross-window drag, external file drag, or attachments.
- Drag-to-Trash behavior.
- Tab-strip auto-scroll, custom drag previews, or a new AppKit collection view.
- A second folder mutation or persistence service.
- Folder reorder changes or folder creation animation redesign.
- Automatic most-recently-edited sorting, configurable sort modes, or any background reorder.
- Removing pinning, compacting pinned tab labels, or changing the established pin/unpin partition transition.
- Suppressing folder, history, model, agent-activity, or permanent-deletion confirmation.
- Search, backlink, dictation, Smart Capture, MCP authority, capability-profile, agent, or add-on behavior.
- New dependencies, package changes, generated files, note schema changes, or broad UI refactors.

## 10. Required Handoff

After this specification is approved in its committed form, write a bounded implementation plan from the final accepted integration head. Implementation is delegated only through the configured Luna/Max task lane. The primary Sol session verifies the resulting diff and evidence, and a fresh Sol/High reviewer must return exactly `ship` before completion, push, PR, or merge is claimed.
