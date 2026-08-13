# Checklist Alignment and Empty List Affordance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or **superpowers:executing-plans** to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a single empty current paragraph become a real readable list item with a reversible low-opacity marker, and center-then-clamp the fixed checklist control in the TextKit marker-plus-separator slot while preserving all existing editor, storage, link, and accessibility contracts.

**Architecture:** Keep `EditorListEngine` responsible for text-only list conversion and keep `ListAwareTextView` responsible for selection/caret, attributed replacement, temporary TextKit presentation, TextKit geometry, hit testing, hover, and accessibility. Extend the existing `ChecklistMarkerDrawing` seam only for the stable visual slot and marker opacity. Use the existing empty-item `insertNewline` exit path and the existing note-link/checklist clear-and-reapply lifecycle.

**Tech Stack:** Swift 6, macOS AppKit/TextKit 1, Core Graphics, Swift Testing, Swift Package Manager.

## Global Constraints

- Production and test ownership is limited to:
  - `Sources/FleckApp/ChecklistMarkerDrawing.swift`
  - `Sources/FleckApp/EditorListEngine.swift`
  - `Sources/FleckApp/NativeRichTextEditor.swift`
  - `Tests/FleckAppTests/ChecklistMarkerDrawingTests.swift`
  - `Tests/FleckAppTests/EditorListEngineTests.swift`
  - `Tests/FleckAppTests/AppKitEditorTests.swift`
- Do not modify `NotesPanel.swift`, `EditorFormattingBar.swift`, package files,
  storage/models/schema, dependencies, generated files, or unrelated editor
  and link code. Existing toolbar routing already reaches
  `toggleList(_:)`/`toggleAutomaticList(_:)`.
- Stored list markers remain readable: bullet text uses the existing bullet
  style plus `" "`, number text uses existing explicit/automatic numbering plus
  `" "`, and checklist text remains `"○ "`/`"● "`.
- Completed content continues to use native `.strikethroughStyle` in storage
  and RTF. Never draw a manual text strike, write a baseline offset, or persist
  a presentation opacity.
- The empty marker opacity is one named multiplier constant,
  `ChecklistMarkerDrawing.emptyListMarkerOpacity`, with value `0.45`. For a
  bullet/number marker, temporary alpha is effective/authored color alpha
  multiplied by this constant; it is never an absolute alpha and never
  increases opacity. For custom checklist drawing, the same value is the
  whole-control graphics-context opacity multiplier.
- Empty-list insertion applies only to one empty current paragraph, including a
  one-line newline-terminated paragraph. Blank lines inside multi-line
  selections remain blank.
- Preserve font, paragraph style, indentation, authored foreground/background,
  inline formatting, selection/caret, typing attributes, automatic-number
  metadata, note-link presentation, accessibility, UndoManager grouping, RTF
  round-trips, the existing 0.10-second completion reveal, and Reduce Motion.
- Preserve the existing one-tracking-area lifecycle, `mouseExited` cleanup,
  native `.arrow` over the checklist control, and I-beam behavior over text.
- No layout animation, hover motion, spring/celebration, fake editor, fake
  placeholder, native `NSTextList` migration, schema change, cache/index,
  observer graph, or broad presentation refactor.
- Start from the clean integrated branch/head supplied in the task packet. Do
  not launch Fleck or touch note data. Do not push or open a pull request.

---

## File map and settled seams

| File | Bounded responsibility |
| --- | --- |
| `Sources/FleckApp/EditorListEngine.swift` | Convert exactly one empty paragraph to a real marker item while preserving existing non-empty, multi-line, indentation, and numbering behavior. |
| `Sources/FleckApp/ChecklistMarkerDrawing.swift` | Own the 16-point marker geometry, 28-point minimum target, named empty opacity, and opacity-aware open/completed drawing. |
| `Sources/FleckApp/NativeRichTextEditor.swift` | Pass the marker-plus-space TextKit slot, preserve content-safe hit geometry, select the caret after insertion, apply reversible empty-marker presentation, and reuse existing Return/link/checklist lifecycle. |
| `Tests/FleckAppTests/EditorListEngineTests.swift` | Red/green pure conversion tests for empty explicit/automatic items, terminators, toggling back, and multi-line preservation. |
| `Tests/FleckAppTests/ChecklistMarkerDrawingTests.swift` | Red/green drawing and pure geometry tests for the fixed visual size, target containment, opacity constant, and open/completed rendering. |
| `Tests/FleckAppTests/AppKitEditorTests.swift` | Red/green real `ListAwareTextView` tests for caret/undo/Return/presentation, TextKit flat/nested geometry, hit/cursor/tracking, note-link composition, and RTF behavior. |

The intended narrow drawing signatures are:

```swift
enum ChecklistMarkerDrawing {
  static let markerDiameter: CGFloat = 16
  static let hitTargetSize: CGFloat = 28
  static let emptyListMarkerOpacity: CGFloat = 0.45

  static func markerRect(around slotRect: CGRect) -> CGRect

  static func hitRect(around markerRect: CGRect) -> CGRect

  static func drawOpen(
    in rect: NSRect,
    strokeColor: NSColor,
    hoverColor: NSColor?,
    opacity: CGFloat = 1
  )

  static func drawCompleted(
    in rect: NSRect,
    accentColor: NSColor,
    flipped: Bool,
    hoverColor: NSColor? = nil,
    opacity: CGFloat = 1
  )
}
```

`markerRect(around:)` takes the TextKit-derived union slot, not a new layout
parameter or a content-glyph argument. `hitRect(around:)` remains a pure
geometry helper and must contain the entire returned marker. The existing
default opacity keeps current non-empty call sites source-compatible. The
`opacity` drawing argument is a multiplier: it wraps the complete open or
completed control, including hover/fill/stroke/checkmark, rather than replacing
the authored/source color alpha with an absolute value.

## Red-first execution

Before changing production code, add only the focused regressions described in
the following steps and run their focused filters. Record the expected RED
results in the worker handoff; a failing assertion must identify the current
empty conversion, visual-size/containment, or presentation-layer defect. Do
not add source-scanning tests when the existing engine or real
`ListAwareTextView` seam can prove the behavior.

## Task 1 — Empty paragraph conversion in the existing list engine

**Files:**

- `Tests/FleckAppTests/EditorListEngineTests.swift`
- `Sources/FleckApp/EditorListEngine.swift`

**Interfaces:** Keep these existing signatures unchanged:

```swift
static func toggle(style: EditorListStyle, in text: String) -> String
static func toggleAutomatic(family: EditorListFamily, in text: String) -> String
```

Add only a private single-paragraph decision inside the existing methods (or a
private helper local to the enum):

```swift
private static func emptyParagraphToggle(
  style: EditorListStyle,
  text: String
) -> String?

private static func emptyAutomaticToggle(
  family: EditorListFamily,
  text: String
) -> String?
```

The helper returns a value only for exactly one empty line (`""`) or the same
line with its terminal newline (`"\n"`). It returns `nil` for multi-line input
so the current line-by-line behavior remains the authority. Use the existing
marker/automatic-style functions and existing indentation/number rules; do
not duplicate marker parsing or introduce a second list model.

- [ ] Add red tests for explicit bullet, number, and checklist toggles on
  `""`, asserting `"• "`, `"1. "`, and `"○ "` (using the existing explicit
  style/marker conventions).
- [ ] Add red tests for automatic bullet and automatic number toggles on
  `""`, asserting the existing depth-zero automatic marker plus a separator.
- [ ] Add red tests for `"\n"`, asserting the marker and separator precede the
  preserved newline (`"• \n"`, `"1. \n"`, or `"○ \n"`).
- [ ] Add red tests that toggling an empty marker item a second time returns
  `""` or `"\n"` and that a multi-line input with an internal blank line keeps
  that blank line blank.
- [ ] Preserve and rerun existing non-empty, multi-line, indentation, and
  automatic-number metadata tests without changing their expected output.
- [ ] Run the focused engine filter and capture the expected RED before the
  implementation:

```bash
swift test --disable-automatic-resolution --no-parallel --filter EditorListEngineTests
```

- [ ] Implement the two minimal empty-line branches. For automatic numbers,
  choose the existing depth-zero automatic style; for explicit numbers, use
  the existing explicit style. Preserve the terminal newline exactly.
- [ ] Run the same filter and require exit 0 with all selected engine cases
  passing.

## Task 2 — Stable marker slot and opacity-aware drawing

**Files:**

- `Tests/FleckAppTests/ChecklistMarkerDrawingTests.swift`
- `Sources/FleckApp/ChecklistMarkerDrawing.swift`

The visual marker is always exactly 16 by 16 points. The supplied `slotRect` is
the TextKit union of the stored marker glyph and separator-space glyph; its
`maxX` is the safe first-content/caret boundary. Compute the ideal centered x,
the safe right-aligned x, and choose the leftmost value only when centering
would cross the boundary:

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

This centers exactly when `slotRect.width >= markerDiameter`; otherwise it
performs the minimal left clamp and yields `markerRect.maxX == slotRect.maxX`.
Do not add a separate content-boundary argument: `slotRect.maxX` is the
boundary. The marker-plus-separator slot also moves the safe right edge beyond
the old marker-only `maxX` when the font metrics permit it.

Keep the target left-expanding around the marker’s right edge, as the current
editor hit path expects, while preserving the minimum-size contract:

```swift
let width = max(hitTargetSize, markerRect.width + 8)
let height = max(hitTargetSize, markerRect.height + 8)
return CGRect(
  x: markerRect.maxX - width,
  y: markerRect.midY - height / 2,
  width: width,
  height: height
)
```

The editor-level geometry tests in Task 3, not this pure helper, prove the
content-boundary constraint for flat and nested TextKit layouts.

- [ ] Strengthen the pure geometry tests so `markerRect` is exactly 16 by 16,
  `hitRect` is at least 28 by 28, and a hit rect contains the complete marker.
  Assert exact center when the slot width is at least 16 points; for a
  narrower slot, assert the minimal left clamp and
  `markerRect.maxX == slotRect.maxX`. Replace any expectation that relies on
  right-aligning to the old narrow marker glyph.
- [ ] Add a test for the named multiplier
  `emptyListMarkerOpacity == 0.45` and for a semi-transparent authored color:
  the temporary marker alpha must equal `authoredAlpha * 0.45`, never exceed
  authored alpha, and restore to authored alpha after clearing/reapplying.
- [ ] Add raster/drawing coverage that open and completed markers remain
  visible, and that the `0.45` multiplier is applied to the complete custom
  control without changing its 16-point geometry. Keep the existing accent
  fill, white check, hover treatment, and Reduce Motion timing tests.
- [ ] Run the drawing filter and capture the expected RED against the current
  glyph-aligned geometry/opacity API:

```bash
swift test --disable-automatic-resolution --no-parallel --filter ChecklistMarkerDrawingTests
```

- [ ] Change `markerRect(around:)` to center-then-clamp in the provided slot
  and retain a pure 28-point-or-larger `hitRect(around:)` that contains it and
  left-expands from `markerRect.maxX`.
- [ ] Add the named constant and apply opacity with the current graphics
  context state (`saveGState`/`restoreGState`); do not alter path coordinates,
  marker size, or layout metrics. Preserve default full opacity for existing
  non-empty callers.
- [ ] Rerun the drawing filter and require exit 0.

## Task 3 — TextKit slot geometry and content-safe hit behavior

**Files:**

- `Tests/FleckAppTests/AppKitEditorTests.swift`
- `Sources/FleckApp/NativeRichTextEditor.swift`

Keep `ListAwareTextView.checklistMarkerRect(for:)` and
`checklistHitRect(for:)` as the existing testable seams. Inside the existing
marker lookup, request the glyph range for the stored marker and its
immediately following separator:

```swift
let markerAndSeparatorRange = NSRange(
  location: markerRange.location,
  length: 2
)
let glyphRange = layoutManager.glyphRange(
  forCharacterRange: markerAndSeparatorRange,
  actualCharacterRange: nil
)
let slotRect = layoutManager.boundingRect(
  forGlyphRange: glyphRange,
  in: textContainer
)
```

Retain the existing coordinate conversion and used-rect handling around this
calculation. Pass the resulting marker-plus-space slot to
`ChecklistMarkerDrawing.markerRect(around:)`. The slot’s `maxX` is the content
boundary: it is the first content glyph’s minimum x when content exists, or the
TextKit caret boundary immediately after the separator for an empty item. The
returned marker must end at or before `slotRect.maxX`; the returned hit rect
must contain the marker, left-expand from `markerRect.maxX`, and end at or
before `slotRect.maxX`. Do not pass a separate content-boundary argument into
the drawing helper, change a text inset, or add a cache.

- [ ] Add red real-editor geometry tests at 11-point and the normal configured
  editor size. For both a flat `"○ content"` paragraph and an indented/nested
  checklist paragraph, extract the marker and separator glyph rects from the
  real `NSLayoutManager`, form their union slot, and assert:
  - the drawn marker is exactly 16 by 16;
  - if the slot width is at least 16 points, its center matches the slot center
    within the test’s small TextKit tolerance;
  - if the slot is narrower than 16 points, the marker uses the minimal left
    clamp and `markerRect.maxX == slotRect.maxX`;
  - in both cases, `markerRect.maxX` is at or before the first content glyph
    minimum x;
  - the hit rect contains the entire marker;
  - the hit rect is at least 28 by 28, left-expands from the marker, and
    `hitRect.maxX` is at or before the first content glyph minimum x.
- [ ] Add an empty-item geometry case using the caret boundary after `"○ "`;
  it must not steal the first typed character’s text click.
- [ ] Add/retain the real click test at the edge of the shared hit rect and
  the tracking-area replacement test. Repeated `updateTrackingAreas()` calls
  must leave one custom area; `mouseExited` must clear hover. The cursor test
  must require `.arrow` over the control and the normal I-beam over text.
- [ ] Run the focused editor filter and capture the expected geometry RED
  before changing the marker-range lookup:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
```

- [ ] Replace the marker-only glyph request with the two-character
  marker-plus-separator request, pass its union slot to the drawing helper,
  and preserve the existing visible/point-local lookup and tracking lifecycle.
  The center-then-clamp rule must use only `slotRect.maxX` as the safe edge;
  do not introduce a separate content-glyph argument or fixed pixel nudge.
- [ ] Ensure the hit calculation is derived from the returned marker rect and
  is content-safe for both flat and nested paragraphs; do not use a fixed
  pixel shift to hide a geometry failure.
- [ ] Rerun the focused editor filter and require all existing and new cases to
  pass.

## Task 4 — Empty-item editor integration and reversible presentation

**Files:**

- `Tests/FleckAppTests/AppKitEditorTests.swift`
- `Sources/FleckApp/NativeRichTextEditor.swift`

Keep the existing public/internal editor entry points:

```swift
func toggleList(_ style: EditorListStyle)
func toggleAutomaticList(_ family: EditorListFamily)
override func insertNewline(_ sender: Any?)
func refreshChecklistPresentation()
func clearNoteLinkPresentation()
func refreshNoteLinks(...)
```

Extend the existing `replaceSelectedLines` seam with only the selection needed
for a one-line empty insertion. The selection for an empty replacement is a
caret, not a selected prefix:

```swift
let caretOffset = changed.hasSuffix("\n")
  ? changed.utf16.count - 1
  : changed.utf16.count
let caret = NSRange(
  location: lineRange.location + caretOffset,
  length: 0
)
```

Keep the current selection behavior for non-empty and multi-line replacements.
Use the existing `performUndoGroup`, attributed replacement, number metadata
synchronization, and renumbering calls.

- [ ] Add red real-editor tests for `toggleList` and `toggleAutomaticList` on
  an empty document and a newline-terminated empty paragraph. Assert the
  stored marker, caret after the separator and before a preserved newline,
  one undo removing the marker, and redo restoring it.
- [ ] Add red Return tests for empty bullet, number, and checklist items. The
  result must be a plain empty paragraph using the existing `insertNewline`
  parsed-empty branch. Preserve the existing Return continuation tests for
  non-empty items.
- [ ] Add red opacity tests for empty bullet, number, open checklist, and
  completed checklist markers. Assert the named `0.45` multiplier, including
  `authoredAlpha * 0.45` for an authored semi-transparent bullet/number color,
  full multiplier `1` after the first typed character, restoration to authored
  alpha after clearing/reapplying, and no storage-color mutation.
- [ ] Ensure empty checklist click and accessibility actions still toggle the
  genuine stored item. Keep existing completed toggle, rapid-toggle,
  selection/caret, UndoManager, and Reduce Motion tests green.
- [ ] Add the focused link-layering regression using the existing real note-link
  test seam:
  1. Build a completed checklist with a real NoteLink token and an authored
     custom foreground color on non-link text.
  2. Apply note-link presentation, then refresh checklist presentation several
     times.
  3. Assert the link’s temporary foreground and underline remain the exact
     link presentation, while non-link completed text has one reversible 72%
     temporary foreground and matching temporary strike color.
  4. Inspect storage attributes and assert authored colors and stored
     `.strikethroughStyle` are unchanged.
  5. Clear and reapply the existing temporary layers, then assert the same
     values without cumulative dimming or lost link styling.
- [ ] Add/retain the completed RTF reopen case and assert storage still has
  native `.strikethroughStyle` while presentation-only layers are rebuilt.
- [ ] Run the focused editor filter and capture the expected RED before making
  the integration changes.
- [ ] In `toggleList` and `toggleAutomaticList`, use the empty-line result from
  Task 1 and select the caret calculated above only for the one-line empty
  case. Leave the existing multi-line selection and number metadata path
  unchanged.
- [ ] Reuse the current empty parsed-item Return branch; do not add a second
  exit-list implementation.
- [ ] Extend the current checklist presentation refresh with a bounded scan of
  the already visible/changed list paragraphs. For empty bullet/number marker
  ranges, capture the restored current effective foreground and set temporary
  alpha to `effectiveColor.alphaComponent *
  ChecklistMarkerDrawing.emptyListMarkerOpacity`; never replace it with an
  absolute `0.45` alpha. For empty checklist items, keep the stored marker
  hidden and pass the `0.45` multiplier to `drawOpen`/`drawCompleted` so the
  complete control receives the same relative graphics-context treatment.
- [ ] Clear only the temporary layers owned by this presentation before every
  refresh, restore/derive effective colors, and reapply note-link and checklist
  layers in their existing order. The authored storage attributes and note-link
  temporary underline must survive every refresh; repeated refreshes must
  produce `authoredAlpha * 0.45`, not compound the multiplier.
- [ ] Let the existing text-change/reload/color/undo/redo/RTF refresh hooks
  remove the empty layer as soon as content is present. Do not add an observer
  graph or duplicate a full-document draw/parser path.
- [ ] Rerun the focused editor filter and require exit 0 with all selected
  checklist, link, editing, and inherited feature-stack cases passing.

## Task 5 — Focused verification and handoff evidence

No broad suite or packaged/manual QA is part of this implementation plan; the
parent owns those later gates. After this plan, the parent also owns the full
suite, one validator run, packaged rebuild, manual QA, and a fresh Sol ship
review. The worker must run the exact focused commands below after the
red/green implementation loop:

- [ ] `swift test --disable-automatic-resolution --no-parallel --filter EditorListEngineTests`
  — exit 0.
- [ ] `swift test --disable-automatic-resolution --no-parallel --filter ChecklistMarkerDrawingTests`
  — exit 0.
- [ ] `swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests`
  — exit 0, including inherited editor/folder/toolbar regressions and all
  checklist behavior.
- [ ] `swift build --disable-automatic-resolution` — exit 0.
- [ ] `git diff --check` — exit 0.
- [ ] Inspect the final diff and confirm only the six allowed implementation
  and test paths changed, with no model/schema/layout/dependency churn.
- [ ] Report exact RED and GREEN command output, test counts, branch/base,
  changed files, uncommitted status, and remaining packaged/full-suite/manual
  QA gaps. Do not report unperformed live or packaged QA as complete.

## Explicit non-goals

- No `NotesPanel.swift` or `EditorFormattingBar.swift` change; current toolbar
  routing is sufficient.
- No fake placeholder, alternate image, blur, text attachment, or persisted
  opacity.
- No native `NSTextList`, schema/model/storage migration, dependency, custom
  caret mapper, layout inset/font/baseline change, or broad list abstraction.
- No new animation, spring, hover motion, auto-sort, or unrelated editor/link
  cleanup.
- No changes to folder UI, persistence/store code, note data, generated files,
  package resolution, or project configuration.
