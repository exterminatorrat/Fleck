# Compact Trailing Trash Control Design

**Date:** 2026-08-10

**Status:** Approved design; implementation is not authorized until the user says `start`

**Scope:** Compact only the trailing Trash control in Fleck's folder navigator so the folder strip receives the reclaimed horizontal space.

## Problem and Current Cause

`FolderNavigator` lays out, from leading to trailing, the Unfiled root row, a horizontally scrolling named-folder strip, the new-folder button, a divider, and the Trash button. The folder strip already declares `.frame(maxWidth: .infinity)`, so it is the intended flexible-width consumer.

The trailing Trash button uses the shared `rowLabel` builder. That label contains a `Spacer`, and the Trash button has no local horizontal intrinsic-size constraint. In the outer `HStack`, Trash can therefore accept flexible width that should instead remain available to the named-folder `ScrollView`. Changing `rowLabel` would also affect Unfiled and every named folder, so the correction must stay local to Trash.

## User-Visible Outcome

At every supported navigator width, the Trash control occupies only the intrinsic width required by its existing trash icon, visible `Trash` word, monospaced note count, existing seven-point label spacing, and existing horizontal padding. It remains at the far trailing edge after the divider. The named-folder strip receives all horizontal space reclaimed from Trash and continues to scroll horizontally when its content exceeds that viewport.

## Exact Layout Contract

- Keep the navigator order unchanged: Unfiled, named-folder `ScrollView`, new-folder button, divider, Trash.
- Keep `.frame(maxWidth: .infinity)` on the named-folder `ScrollView`; it remains the designated consumer of width reclaimed from Trash.
- Apply horizontal intrinsic/fixed-size behavior to the existing Trash `Button` only. The expected production shape is:

  ```swift
  Button {
    onOpenTrash()
  } label: {
    rowLabel(
      name: "Trash",
      systemImage: "trash",
      count: appState.trashedNotes.count,
      isSelected: false,
      isEmpty: appState.trashedNotes.isEmpty
    )
  }
  .fixedSize(horizontal: true, vertical: false)
  ```

- Do not add fixed sizing to the shared `rowLabel`, the named-folder rows, or the Unfiled root row. Preserve Unfiled's existing conditional `.fixedSize(horizontal: isUnfiledCompact, vertical: false)` behavior exactly.
- Keep the shared row typography, icon width, `HStack` spacing, count formatting, padding, background, content shape, navigator height, and divider height unchanged.
- Do not introduce a minimum or maximum Trash width. Its existing visible content and padding define its width.

## Interaction, Keyboard, and Accessibility

The full intrinsic Trash label, including its existing padding and content shape, remains the button's hit target. Pointer activation continues to call `onOpenTrash()` exactly once and opens the existing Trash surface.

Keyboard behavior remains unchanged:

- Trash stays `.focusable()` and bound to `FocusedRow.trash`.
- Existing folder-navigator move commands can still move focus to Trash.
- Return and Space still activate the focused Trash row through the existing `activateFocusedRow()` path.

Accessibility remains unchanged:

- Visible label: `Trash`.
- Accessibility label: `Trash`.
- Accessibility identifier: `folder-trash`.
- Accessibility value: `Empty` when there are no trashed notes, otherwise the existing `N notes` value.
- The icon and monospaced count remain visible for both empty and non-empty states.

No duplicate accessibility element, tooltip, hover-only affordance, or alternate action is added.

## Motion Decision

This is a static layout correction on a frequently used navigation surface. It adds no animation or transition. The existing folder-creation animation and Reduce Motion behavior remain untouched.

## Explicit Non-Goals

- No icon-only Trash mode, user preference, collapse/expand state, hover reveal, tooltip, context menu, or new component.
- No change to the visible `Trash` text, icon, note count, empty-state wording, typography, spacing, padding, divider, row height, selection/focus behavior, action, or Trash navigation.
- No change to `rowLabel`, named-folder sizing, Unfiled sizing, folder creation, folder drag/drop, tab drag/reorder, note deletion, Trash lifecycle, persistence, package dependencies, or build configuration.
- No broad hosted geometry harness. The current hosted navigator pixel seam detects selected accent fills, while Trash is an unselected private SwiftUI button without a stable AppKit descendant frame. The exact source-structure regression is the deterministic automated layout contract; packaged-app visual QA supplies the real rendered-width evidence.

## Owned Files

This documentation-only task owns only:

- `docs/superpowers/specs/2026-08-10-compact-trash-control-design.md`
- `docs/superpowers/plans/2026-08-10-compact-trash-control.md`

After the user explicitly says `start`, a separately authorized implementation may own only:

- `Sources/FleckApp/NotesPanel.swift`
- `Tests/FleckAppTests/AppKitEditorTests.swift`

No other file is in scope. Preserve unrelated and concurrent work.

## Verification Contract for the Later Implementation

The later implementation must proceed red-first:

1. Add a focused `AppKitEditorTests` regression that isolates `FolderNavigator`, proves Trash alone has `.fixedSize(horizontal: true, vertical: false)` after the divider, proves the folder `ScrollView` retains `.frame(maxWidth: .infinity)`, and proves shared `rowLabel`, named folders, and Unfiled did not gain the same fixed-size behavior.
2. Run `swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests` and record the expected failing assertion before production code changes.
3. Add the one Trash-only modifier and rerun the focused test green.
4. Run `TabDragReorderTests`, the complete Swift package suite, `Scripts/validate-macos.sh`, `git diff --check`, package-lock identity, scope, unmerged-entry, and merge-state checks.
5. Build the exact packaged `.build/Fleck.app` and manually verify at a 640-point panel width that Trash is compact at the trailing edge, the folder viewport is nonzero and receives the reclaimed width, horizontal folder scrolling still works, and Trash remains clickable, keyboard-focusable, and correctly announced.
6. Require a fresh Sol reviewer to inspect the actual implementation diff and evidence. Completion requires the exact verdict `ship`.

Implementation, build, launch, UI automation, publication, and review dispatch remain prohibited until the user explicitly says `start`.
