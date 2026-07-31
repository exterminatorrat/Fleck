# Native Checklist Control Design

## Goal

Make Fleck checklist markers feel like compact Apple Notes controls instead of
small text glyphs, while preserving the existing plain-text note format and
editing behavior.

## Interaction

- Render a 16-point circular control centered on the checklist marker glyph.
- Give each control a 28-by-28-point clickable target.
- Show a pointing-hand cursor over the target.
- Clicking anywhere in the target completes or reopens the checklist item.
- Preserve the existing keyboard command, Undo behavior, strikethrough update,
  and completion animation.

## Appearance

- Open items use a thin neutral ring rather than exposing the `○` text glyph.
- Hovering an open or completed control adds a restrained accent-tinted
  background treatment.
- Completed items use the selected accent color with the existing animated
  white checkmark.
- Reduce Motion continues to disable the completion overlay animation.

## Architecture

The note body continues to store `○` and `●` markers. `EditorListEngine`, note
files, Markdown export, agent task handles, and Undo therefore remain
compatible.

`ListAwareTextView` owns marker geometry, pointer hit testing, hover state, and
cursor behavior. `ChecklistMarkerDrawing` draws both open and completed states.
No text attachments, embedded `NSButton` objects, or new persistence model are
introduced.

## Validation

Focused tests will prove:

- marker geometry is 16 points and the hit target is 28 points;
- the open state draws a visible neutral ring without an accent fill;
- the completed state retains its accent fill and white check;
- clicking near the edge of the 28-point target toggles the item;
- existing Undo, strikethrough, and Reduce Motion tests remain green.

The full macOS validation script must pass before completion.
