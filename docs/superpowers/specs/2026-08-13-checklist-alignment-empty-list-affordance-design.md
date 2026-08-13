# Checklist Alignment and Empty List Affordance Design

**Status:** Approved
**Date:** 2026-08-13
**Scope:** One bounded correction to list insertion, marker presentation, and checklist geometry.

## Goal

Make an empty list paragraph behave like a real Fleck list item and make the
custom checklist control occupy the actual marker-and-separator slot. The
correction must preserve the existing `ListAwareTextView`/`NSTextView`
architecture, readable stored markers, attributed editing, and native RTF
behavior.

## Root cause

Two existing seams explain the defects:

- `ChecklistMarkerDrawing.markerRect` uses `glyphRect.maxX - 16`. At Fleck's
  real font metrics, right-aligning a 16-point control to the narrow stored
  marker glyph makes the control appear too far left. The editor's
  `checklistMarkerRect(for:)` also supplies only the marker glyph bounds, so it
  ignores the separator-space glyph.
- `EditorListEngine.toggle` and `toggleAutomatic` leave empty strings
  unchanged. Consequently, a toolbar command on an empty current paragraph
  does not create a list affordance.

`ListAwareTextView.insertNewline` already removes a parsed empty list item and
leaves a plain paragraph. That is the existing exit-list behavior to retain.

## Approved behavior

### Empty list insertion

When the command targets exactly one empty current paragraph, it inserts a
normal stored marker and separator and places the caret immediately after the
separator:

| Command | Stored text |
| --- | --- |
| Explicit bullet | Existing bullet style plus `" "` (for example `"• "`) |
| Explicit number | Existing explicit number style plus `" "` (for example `"1. "`) |
| Explicit checklist | `"○ "` |
| Automatic bullet | Existing automatic bullet style plus `" "` |
| Automatic number | Existing automatic number style plus `" "` |

The existing automatic-number paragraph metadata, indentation, and numbering
rules remain authoritative. A newline-terminated one-line empty paragraph
keeps its terminator, so `"\n"` becomes `"• \n"`, `"1. \n"`, or `"○ \n"`
as appropriate. A second toggle removes the empty marker and separator back to
the plain empty paragraph, preserving the terminator.

Only the sole editable paragraph targeted by the command receives this empty
item treatment. Empty lines inside a multi-line selection remain empty; the
existing non-empty and multi-line conversion behavior is unchanged.

### Empty marker presentation

An empty item is a genuine list item, not a placeholder. Its real marker is
shown at lower opacity using the named multiplier
`ChecklistMarkerDrawing.emptyListMarkerOpacity`, set to `0.45`. The first
typed content character causes the normal full-opacity marker presentation to
return immediately.

For bullet and number items, the lower opacity is a reversible TextKit
temporary foreground attribute applied only to the marker range. Derive the
current effective/authored `NSColor`, then set the temporary color alpha to
`effectiveColor.alphaComponent * ChecklistMarkerDrawing.emptyListMarkerOpacity`.
This relative multiplier must never increase authored/effective opacity and
does not write a new color to storage. Repeated refreshes must derive from the
restored effective/authored color rather than multiply an already dimmed
temporary color.

For checklist items, the stored `○`/`●` marker remains hidden from drawing as
in the existing custom-control path. The custom open or completed control is
drawn with the same `0.45` overall graphics-context opacity multiplier while
the content is empty, covering the complete control including hover, fill,
stroke, and checkmark as appropriate. This is not a new marker image or an
absolute alpha replacement. Opacity is display-only and is never serialized.

Return on an otherwise empty item reuses the current parsed-empty exit path:
the marker and separator are removed and the paragraph becomes plain. Return
on a non-empty item continues using the existing list continuation behavior.

### Checklist geometry and interaction

TextKit derives a visual slot from the stored marker glyph and the immediately
following separator-space glyph. `ListAwareTextView.checklistMarkerRect(for:)`
uses the union of those two glyph rects, rather than the marker glyph alone.
That union's `maxX` is the safe first-content boundary, or the insertion-caret
boundary for an empty item. `ChecklistMarkerDrawing.markerRect(around:)` first
computes the ideal centered x position for an exactly 16 by 16-point control,
then clamps only left when the slot is narrower than 16 points:

```swift
let idealX = slotRect.midX - markerDiameter / 2
let safeRightAlignedX = slotRect.maxX - markerDiameter
let x = min(idealX, safeRightAlignedX)
return CGRect(
  x: x,
  y: slotRect.midY - markerDiameter / 2,
  width: markerDiameter,
  height: markerDiameter
)
```

This centers when the slot is at least 16 points wide and otherwise makes the
minimal left shift needed for `markerRect.maxX == slotRect.maxX`. The boundary
is derived from TextKit geometry, never from a fixed-pixel nudge or a layout
change. Using the marker-plus-separator slot also moves the safe right edge
beyond the old marker-only `maxX` when the metrics allow it.

`ChecklistMarkerDrawing.hitRect(around:)` remains at least 28 by 28 points,
contains the complete drawn marker, left-expands from `markerRect.maxX`, and
ends at or before that same content boundary. It must work for flat and
indented/nested checklist paragraphs
without changing `textContainerInset`, `lineFragmentPadding`, font, baseline,
stored marker text, or paragraph layout. The marker stays in its glyph slot and
text clicks remain text clicks.

The existing restrained hover treatment, one tracking area, `mouseExited`
cleanup, native arrow cursor over the control, and I-beam cursor over text are
preserved. No hover motion or new animation is introduced. The existing
0.10-second completion reveal and Reduce Motion behavior remain authoritative.

## Presentation-layer invariants

The completed-content recession remains reversible display-only TextKit
presentation:

1. Derive the effective foreground color before applying the temporary layer.
2. Apply approximately 72% prominence (`0.72`) and a matching temporary
   strikethrough color only to completed non-link content.
3. Keep authored foreground/background and native `.strikethroughStyle` in
   `NSTextStorage` unchanged.
4. Clear only checklist-owned temporary slices before reapplying them after
   edits, reload, color changes, undo/redo, and round-trip. Never compound
   opacity by dimming an already dimmed temporary color; for an authored
   semi-transparent marker, the empty-item temporary alpha is exactly authored
   alpha multiplied by `0.45`.
5. Preserve note-link temporary foreground and underline presentation. When a
   completed item contains a real note-link token, the link layer remains the
   link presentation while non-link completed text receives the 72% recession.

The same clear/reapply sequence must be safe to repeat. A regression will
refresh the combination repeatedly, clear it, and reapply it, proving that
link attributes remain correct, non-link text remains one 72% layer, and
storage attributes remain unchanged.

## Editing and data contracts

- Storage continues to use readable `○` and `●` checklist markers and the
  existing bullet/number strings.
- Completed content continues to use native `.strikethroughStyle` in RTF.
- Undo and redo include empty-list insertion/removal and preserve the caret,
  selection, typing attributes, and existing undo grouping.
- Attributed inline formatting, authored foreground/background, paragraph
  style, automatic numbering metadata, indentation, note links, accessibility,
  and RTF round-trips remain intact.
- Empty checklist items remain genuine checklist paragraphs, so the existing
  accessibility toggle and custom-control hit path remain available.
- The first typed character must not create a layout jump or lose the marker's
  stored formatting; it only removes the temporary low-opacity presentation.

## Implementation boundary

The correction is limited to these implementation and test files:

- `Sources/FleckApp/ChecklistMarkerDrawing.swift`
- `Sources/FleckApp/EditorListEngine.swift`
- `Sources/FleckApp/NativeRichTextEditor.swift`
- `Tests/FleckAppTests/ChecklistMarkerDrawingTests.swift`
- `Tests/FleckAppTests/EditorListEngineTests.swift`
- `Tests/FleckAppTests/AppKitEditorTests.swift`

Existing toolbar routing already reaches `toggleList` and
`toggleAutomaticList`; `NotesPanel.swift` and `EditorFormattingBar.swift` do
not need changes. No storage/model/schema, package, dependency, native
`NSTextList` migration, fake editor, custom caret mapper, or broad presentation
refactor is part of this correction.

## Acceptance criteria

The implementation is accepted when focused tests prove all of the following:

- Explicit and automatic bullet/number/checklist commands create real markers
  on a single empty paragraph, preserve a newline terminator, put the caret
  after the separator, and toggle back to plain empty text.
- Internal blank lines in multi-line selections remain blank and existing
  non-empty/multi-line list behavior is unchanged.
- The named empty-marker opacity multiplier is `0.45`; empty bullet and number
  marker alpha is effective/authored alpha multiplied by `0.45` (including a
  semi-transparent authored marker), and empty open/completed checklist
  controls use the same whole-control graphics-context multiplier. Non-empty
  markers use multiplier `1`, and the first typed character restores it.
- Flat and nested checklist controls are exactly 16 by 16 points; each 28 by
  28-or-larger hit rect contains its marker and ends before the first content
  glyph/caret boundary. Wide slots center the marker exactly; narrow slots
  apply only the minimal left clamp so the marker ends at the slot boundary.
- Hover/cursor/tracking behavior remains single-area and leak-free, with arrow
  over controls and I-beam over text.
- Undo/redo, Return exit, rapid toggles, authored colors, native strike
  storage, note-link layering, and RTF reopen remain correct.

## Non-goals

This correction does not add a fake placeholder, alternate marker image, blur,
schema field, opacity persistence, layout animation, spring/celebration,
baseline offset, manual strike rendering, native `NSTextList`, dependency, or
new list architecture. It does not change toolbar routing, unrelated editor or
link behavior, folder UI, persistence, or note data.
