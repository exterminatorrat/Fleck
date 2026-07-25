# Trash Navigation, Tab Colors, and Lists Design

## Goal

Make Trash return reliably to the notes editor, let each note carry a persistent tab color, and upgrade lists to feel familiar to users of Microsoft Word and Apple Notes without replacing the existing native AppKit text editor.

## Scope

This change contains four bounded pieces:

1. Correct Trash dismissal inside both the transient menu-bar panel and pinned notes window.
2. Add optional per-note tab colors that persist through saving, deletion, and restoration.
3. Expand the existing plain-text list engine with selectable markers, automatic nested styles, and clickable checklist items.
4. Refine Settings navigation with a clean, animated section selector.

It does not introduce a custom block editor, collaborative editing, tables, images, or cloud synchronization.

## Trash Navigation

`TrashView` will no longer call the environment `DismissAction`. Its initializer will accept an `onDone` closure from `NotesPanel`, and Done will set that panel's `isShowingTrash` state to `false` directly.

This keeps the existing sheet presentation and visual design. It removes ambiguity between dismissing the sheet and dismissing the transient `MenuBarExtra` host window. Closing the sheet by another system-supported method must also leave `isShowingTrash` synchronized with the presentation.

Success criteria:

- One click on Done closes Trash and reveals the notes editor.
- Reopening the menu-bar panel opens on the notes editor.
- The same behavior works from the pinned notes window.
- Restore remains optimistic and keeps the Trash sheet open.

## Settings Section Selector

The visible “Settings section” label is removed. Appearance, Editing, and Shortcuts remain the only three section names.

The stock segmented Picker is replaced by a compact SwiftUI selector built from three equal-width buttons. A single accent-colored rounded selection capsule uses `matchedGeometryEffect` to move between the buttons, so the blue background visibly travels from the previous section to the next instead of disappearing and reappearing.

The selector uses the existing crisp native motion policy:

- 160 ms ease-out movement;
- no bounce or overshoot;
- interruptible state-driven animation that retargets during rapid clicks;
- movement disabled when Reduce Motion is enabled, while color and opacity feedback remain;
- no animation on keyboard focus changes.

The form below retains its existing short opacity transition. Panel dimensions and form layout are not animated. Every segment uses its full visual area as the hit target and exposes its section name and selected state to accessibility.

The custom selector is preferred over hiding the stock Picker label because the stock control does not provide control over the requested sliding highlight. An AppKit `NSSegmentedControl` wrapper is unnecessary for this three-item SwiftUI state change.

## Per-Note Tab Colors

### Data

`Note` gains an optional `tabColorHex` value. `nil` means the app accent color.

The optional value is copied through:

- active workspace save and load;
- recovery snapshots;
- Trash metadata;
- Trash restoration.

Existing documents remain compatible because missing color metadata decodes as `nil`. Imported files start with no custom tab color. Tab color is application metadata and is not included in Markdown, plain-text, or RTF exports.

### Palette and Interaction

Each tab's context menu gains a Tab Color submenu with:

- None
- Red
- Orange
- Yellow
- Green
- Blue
- Purple
- Pink
- Gray

The palette uses fixed, named hex values so choices are stable across launches and accessible without interpreting raw color codes. The selected menu item displays a checkmark.

Unselected colored tabs receive a low-contrast capsule tint. The selected tab uses a stronger tint while retaining the existing matched-geometry selection animation. The note title remains visible, so color is never the only identifier.

## List Architecture

The existing `ListAwareTextView` remains the editor. List content continues to use readable text markers in `Note.body`, while RTF stores visual attributes such as strikethrough.

A small, app-internal list engine will own pure list parsing and transformations. It will:

- recognize list markers and indentation;
- apply or remove a chosen list style;
- continue a list on Return;
- indent or outdent selected list paragraphs;
- choose the automatic marker for a nesting depth;
- normalize common typed prefixes;
- toggle checklist completion.

`ListAwareTextView` will remain responsible for AppKit selection ranges, mouse hit testing, undo registration, replacing text, and notifying its delegate. This boundary keeps list logic testable without building a second editor model.

## Supported List Styles

### Bullets

Selectable bullet markers:

- `•`
- `◦`
- `▪`
- `–`

Automatic nesting cycles through `• → ◦ → ▪`, repeating for deeper levels. The dash style is a manual alternative and continues on Return when selected.

### Numbered Lists

Selectable numbered markers:

- decimal: `1.`, `2.`, `3.`
- lowercase alphabetic: `a.`, `b.`, `c.`
- lowercase Roman: `i.`, `ii.`, `iii.`

Automatic nesting cycles through decimal → alphabetic → Roman, repeating for deeper levels. Numbered siblings are recomputed for the affected contiguous list block after applying a style, pressing Return, or changing indentation.

### Checklists

Checklist text uses:

- `○` for incomplete;
- `●` for complete.

Clicking either marker toggles the state. A complete item applies strikethrough only to that paragraph's content, not to the marker or indentation. Clicking again removes the strikethrough. The content remains editable in both states.

Return after a checklist item creates a new incomplete item. A completed item's strikethrough does not carry into the new item.

## Toolbar

The formatting bar gains three list controls:

- Bullets
- Numbering
- Checklist

Bullets and Numbering expose their available styles in menus. Their primary action applies the automatic style for the current indentation depth. Choosing a specific style applies that marker to the current paragraph or selected paragraphs.

Checklist applies or removes checklist formatting for the current paragraph or selection. Completion is controlled by clicking the marker.

All controls retain the existing full-size hit targets, accessibility labels, and crisp press feedback.

## Keyboard Behavior

### Return

When the caret is in a non-empty list item, Return inserts a new item at the same indentation and continues the current style.

When the caret is in an empty list item, Return removes that marker and exits the list at that indentation.

### Tab and Shift-Tab

For list paragraphs:

- Tab adds one four-space indentation level and converts the marker to the automatic style for the new depth.
- Shift-Tab removes one indentation level and converts the marker to the automatic style for the new depth.
- At depth zero, Shift-Tab leaves the paragraph unchanged.

For non-list paragraphs, the editor preserves its existing four-space indentation behavior.

### Typed Prefix Normalization

When automatic lists are enabled and the user types a recognized prefix followed by a space at the start of a paragraph:

- `-`, `*`, or `+` becomes `•`;
- `1.` or `1)` begins decimal numbering;
- `[]` or `[ ]` becomes `○`.

Automatic-list behavior remains controlled by the existing “Create lists automatically” setting. Toolbar commands and manual indentation remain available when that setting is off.

## Selection and Editing Rules

- Applying a list style affects every selected paragraph.
- Applying the same active style removes list markers from the selection.
- Applying a different style replaces existing bullet, numbered, or checklist markers.
- Mixed selections become the chosen style.
- Empty paragraphs in a multi-paragraph selection remain empty.
- List transformations preserve selected text as closely as AppKit range changes allow.
- All list edits participate in the text view's existing undo manager.

## Persistence and Compatibility

The Markdown body remains the readable source for markers and indentation. Existing `-`, `*`, `+`, `1.`, and `1)` lists continue to parse and can be restyled.

RTF remains the source for font traits and checklist strikethrough. If an RTF sidecar is missing or invalid, checklist markers still load as readable text; completed markers remain visible even if strikethrough is unavailable.

No storage format version bump is required because tab color metadata is optional and list content remains text.

## Error Handling

- Invalid or unknown tab color values fall back to the app accent color without preventing the note from loading.
- A failed save uses the existing save-error message and does not discard the in-memory color or list edit.
- A failed Trash restore reloads Trash from disk using the existing recovery behavior.
- A malformed list marker is treated as ordinary text.

## Testing

Core tests will verify:

- old note metadata decodes without a tab color;
- tab colors round-trip through workspace persistence;
- tab colors survive Trash and restoration.

App tests will verify:

- recognition of every supported marker;
- bullet and numbered style application and removal;
- automatic depth-to-marker selection;
- Return continuation and empty-item exit;
- Tab and Shift-Tab marker conversion;
- typed-prefix normalization;
- checklist creation and completion toggling;
- numbered sibling recomputation;
- Reduce Motion policy remains unchanged.

Manual macOS checks will verify:

- Done returns from Trash with one click in both window types;
- the Settings selector has no visible “Settings section” label;
- the blue Settings selection capsule moves fluidly between all three sections;
- Reduce Motion removes the capsule movement without hiding the selected state;
- menu and toolbar hit targets;
- matched tab-color animation and readable contrast;
- clicking checklist markers toggles only the intended item;
- typing, selection, undo, and rich formatting remain responsive.

## Delivery Boundary

The implementation is complete when all automated tests and the macOS validation script pass, the release executable remains within its existing size budget, and the manual checks above show no regression in text entry or window behavior.
