# Live Tab Drag Reordering Design

## Goal

Make note tabs reorder continuously while dragged. As the pointer crosses a neighboring tab, that tab slides out of the way and the dragged note takes its place immediately.

The interaction should feel like native Safari or Finder tab reordering while preserving the app’s existing note-order persistence and context-menu controls.

## Existing Behavior

`NotesPanel.tabStrip` already makes every tab draggable and accepts dropped note identifiers. The order changes only after the user releases the dragged tab over a destination.

The underlying reorder path already exists:

1. `NotesPanel` identifies the dragged note and destination index.
2. `AppState.moveNote(_:to:)` updates the workspace and schedules a debounced save.
3. `Workspace.moveNote(id:to:)` removes the note from its current index and inserts it at the bounded destination.

This design keeps that model and changes only when the existing move operation is invoked.

## Interaction

### Drag Start

Beginning a drag stores the dragged note’s stable `UUID` in view-local state and provides its string representation through a native, own-process drag item. Each `NotesPanel` instance uses a unique drag type, so its menu-bar and pinned-window tabs cannot be mistaken for one another.

The existing tab remains the source and preview. No duplicate ghost model or separate preview array is introduced.

### Live Reordering

Each tab becomes a drop target backed by a small `DropDelegate`.

When the dragged tab enters another tab’s bounds:

1. Resolve the dragged and destination indices from the current workspace order.
2. Ignore the event if the identifiers are equal or the indices already match.
3. Call the existing `AppState.moveNote(_:to:)`.
4. Let the existing order animation respond to that workspace mutation.

Because the `ForEach` is driven by the workspace array, neighboring tabs receive new positions and slide left or right automatically.

The drop proposal uses the native `.move` operation so the pointer communicates reordering rather than copying.

### Drop Completion

Dropping clears the view-local dragged identifier and reports success.

The existing debounced save persists the final workspace order. Intermediate hover moves may reschedule that debounce, but only the final settled order needs to reach disk.

Starting a later drag always replaces stale local drag state, so a cancelled drag cannot corrupt note order or block future reordering.

## Motion

The `HStack` order change uses the app’s existing `AppMotion.standard` ease-out animation (`0.16` seconds).

- Neighboring tabs slide to their new positions.
- The surrounding header and editor do not animate.
- No bounce, spring, scale, halo, or custom drag physics is added.
- Under Reduce Motion, the order updates immediately without spatial animation.

The existing selected-tab highlight continues to use its matched geometry effect and follows the selected note without introducing a second selection state.

## Boundaries

- Reordering remains horizontal and operates only among currently visible tab targets.
- Automatic horizontal edge scrolling during a drag is not included.
- Pinned and unpinned tabs retain the app’s current reorder semantics; this feature does not introduce a new pin boundary rule.
- Context-menu “Move Left” and “Move Right” actions remain available.
- Dragging does not change the selected note unless the existing tab button is clicked.
- No changes are required in persistence formats, `Note`, `LocalStore`, or `EditorListEngine`.

## Failure Handling

- Unknown or malformed drag identifiers are ignored.
- Text drags and drags from another `NotesPanel` instance are ignored.
- Missing source or destination notes are ignored.
- Re-entering the current position is a no-op.
- Dropping outside a valid tab target leaves the most recent live order intact and cannot delete or duplicate notes.
- The destination index remains bounded by `Workspace.moveNote(id:to:)`.

## Testing

Focused tests will verify:

- moving a note left and right produces the expected stable identifier order;
- repeated moves across multiple neighbors never duplicate or lose a note;
- moving to the current index is a no-op;
- the drag delegate requests a `.move` operation;
- entering a neighboring target invokes the existing reorder path once and updates the dragged identifier order;
- Reduce Motion selects the immediate-order path while standard motion uses `AppMotion.standard`;
- context-menu and persistence behavior remain unchanged.

The full macOS validation script remains the release gate.

## Non-Goals

- Custom drag previews;
- detached or floating tabs;
- dragging notes between windows;
- edge-triggered auto-scrolling;
- changing pinned-note rules;
- adding a third-party drag-and-drop dependency.
