# Accent Checklist Completion Design

## Goal

Make checklist completion feel native and immediately legible without changing the note format or the existing editing behavior.

An incomplete checklist item displays an outlined circle. Completing it replaces that appearance with an accent-filled circle and a white checkmark, while the item text keeps the existing strikethrough treatment. The checkmark receives one short, restrained completion animation.

## References

The interaction follows the compact inline treatment used by:

- [Apple Notes](https://mobbin.com/screens/e9a89d3d-3933-470c-8b4e-20ab524b1358): circular inline checklist controls with a filled completed state;
- [Bear](https://mobbin.com/screens/b3032ba7-6f48-4bd2-9c3b-c082179309de): checklist controls that remain aligned with freely editable text;
- [Craft](https://mobbin.com/screens/f20d9947-0dc2-4b6d-bd39-11d40a930d90): clear accent-color completion feedback.

These products are interaction references only. The app keeps its existing macOS density, typography, accent preference, and AppKit editor.

## Existing Contract

`ListAwareTextView` remains the editor and `EditorListEngine` remains the list parser.

- `○` is the persisted incomplete marker.
- `●` is the persisted completed marker.
- Completed content receives `.strikethroughStyle`.
- Clicking the marker or invoking its accessibility action uses the same toggle path.
- Plain text, Markdown, RTF, undo, selection, continuation, and indentation behavior stay unchanged.

The visual refinement must not introduce text attachments, replacement-object characters, or temporary text attributes that could leak into the RTF sidecar.

## Visual States

### Incomplete

The existing `○` marker remains an outlined circle. It is not filled and does not animate.

### Complete

The completed marker is drawn as:

- a vector circle filled with the current app accent color;
- a small centered white checkmark;
- the same typographic footprint as the stored marker so text alignment and wrapping do not move.

The app accent is passed explicitly from `AppPreferences.accentHex` through `NativeRichTextEditor` to `ListAwareTextView`. SwiftUI tint is not treated as an implicit AppKit color source.

The marker drawing uses the final glyph rectangle produced by the text layout manager. Font family and font size changes therefore keep the custom marker aligned with the text.

## Interaction and Hit Target

Drawing and pointer hit testing share one marker-geometry helper. The visible control remains compact, while its interactive rectangle keeps the existing padding around the glyph.

Only a click inside that shared rectangle toggles completion. Clicking the task text continues to place the caret normally.

The completed state is committed immediately before animation begins. Animation never delays persistence, strikethrough, undo registration, or accessibility feedback.

## Motion

Completion uses purposeful, marker-local motion:

1. The accent-filled circle appears immediately.
2. A white checkmark draws from start to finish over `AppMotion.quickDuration` (`0.10` seconds).
3. The temporary animation layer is removed, revealing the identical static final marker underneath.

The checkmark uses rounded line caps and a strong ease-out timing curve. There is no bounce, halo, confetti, or movement of surrounding text.

Uncompleting an item returns immediately to the outlined circle without a celebratory animation.

When macOS Reduce Motion is enabled, the editor skips the animated overlay and displays the completed state immediately.

Rapid repeated toggles remove any existing marker animation before starting another one. An offscreen marker or unavailable layout skips animation without affecting the completed edit.

## AppKit Rendering

`ListAwareTextView` owns display-only checklist rendering:

1. `draw(_:)` calls the normal text-view drawing first.
2. It enumerates visible completed checklist markers only.
3. For each completed marker, it draws the accent circle over the stored `●` glyph and draws the static white checkmark.

After a successful incomplete-to-complete mutation, the text view adds a temporary, hit-test-transparent child view over the final marker rectangle. Its accent circle covers the static checkmark while a `CAShapeLayer` animates the white check path. The child view is removed when the animation finishes.

No rendering state is written to `NSTextStorage`. The underlying `○` and `●` characters remain the single source of truth.

## Accessibility

- The existing “Toggle checklist item” accessibility action remains available.
- Completion through accessibility uses the same mutation and visual-update path as pointer input.
- The accent fill is supplemented by the checkmark shape, so completion is not communicated by color alone.
- Reduce Motion is read from the macOS accessibility setting.
- The custom drawing does not create a second accessibility element or interfere with text selection.

## Failure Handling

- If text mutation is rejected, neither completion styling nor animation runs.
- If marker geometry cannot be resolved, completion still succeeds and only the animation is skipped.
- If the accent hex is invalid, the control falls back to `NSColor.controlAccentColor`.
- Animation cleanup is idempotent so interrupted or repeated toggles cannot leave stale overlay views.

## Testing

Focused AppKit tests will verify:

- completion still changes `○` to `●`, applies content-only strikethrough, preserves selection, and undoes in one step;
- uncompletion removes strikethrough and does not request completion animation;
- pointer hit testing uses the same marker rectangle as rendering;
- a deterministic accent produces an accent-filled marker with a near-white checkmark;
- RTF round-trip preserves the stored marker and strikethrough without persisting animation or rendering artifacts;
- Reduce Motion disables the animated overlay;
- rapid toggles leave no stale completion overlay.

The existing full macOS validation script remains the release gate.

## Non-Goals

- Replacing the plain-text list engine;
- adding task dates, reminders, priorities, sorting, or completion sounds;
- changing checklist indentation or continuation rules;
- animating ordinary bullets or numbered lists;
- copying another app’s visual styling beyond the referenced checklist interaction.
