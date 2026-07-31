# Responsive Fleck Onboarding Layout Design

## Goal

Make every first-launch onboarding step usable while the window is resized,
without clipping headings, controls, the real Fleck editor, or the persistent
Back/Continue footer. The onboarding should remain comfortably spacious at its
default size and become denser, not smaller in type, at compact sizes.

## Problem

The current onboarding shell advertises a 920 by 620 point minimum, but its
embedded `NotesPanel` still applies the normal saved panel width and height
(520 by 430 points by default). The Dictation step then nests that fixed panel
below two instruction groups and a modifier picker. When the window becomes
shorter, the fixed editor wins the layout negotiation and pushes the heading or
footer outside the visible content area.

The failure is structural:

- The onboarding window can become smaller than the layout can render.
- The embedded real editor uses standalone-window dimensions instead of the
  space offered by onboarding.
- The Dictation step nests a full `liveCanvas` layout inside another padded
  step layout, creating duplicate expansion and padding pressure.
- The footer is visually persistent but is not protected from an oversized
  step body.

## Approved Direction

Use an adaptive contained-canvas layout:

- Keep the left progress rail and bottom navigation footer pinned.
- Let the step body consume only the space between them.
- Let the real Fleck editor grow and shrink with that available body space.
- Keep the editor's own scrolling and controls; do not scale typography or
  build a simplified onboarding-only editor.
- Introduce compact spacing below the regular onboarding size.
- Enforce a true minimum window size at which all required controls remain
  usable.
- Allow static informational content to scroll when text size or localization
  requires more vertical room.

Wrapping the entire onboarding screen in one scroll view is rejected because
it would move the rail/footer and make the editor compete with an outer scroll
container. Merely raising the minimum window size is rejected because it would
avoid clipping without making onboarding meaningfully resizable.

## Layout Contract

### Window

- Default content size remains 1,080 by 700 points.
- Minimum content size becomes 760 by 520 points.
- The window may grow without an onboarding-defined maximum.
- `WindowResizability` must honor the content minimum while permitting normal
  user resizing above it.
- Resizing must not change the persisted normal Fleck panel width or height.

### Shell

The shell owns three regions:

1. Progress rail on the leading edge.
2. Flexible step body filling the remaining area above the footer.
3. Fixed footer at the bottom of the content column.

The step body receives a finite proposed size and may not expand the footer out
of the window. The footer remains at least 64 points tall, retains Back on the
leading edge, progress dots in the center, and Continue on the trailing edge.

### Responsive Tiers

Regular layout applies at 920 points wide and 620 points tall or larger:

- 240-point rail.
- 32- to 48-point content padding, depending on the step.
- 72-point footer.
- Existing onboarding typography and control sizes.

Compact layout applies below either regular threshold:

- 188-point rail.
- 20- to 24-point content padding.
- 64-point footer.
- Tighter vertical spacing between instruction groups.
- Existing semantic text styles and control sizes; text is not geometrically
  scaled down.

The rail keeps all five labels at the 760-point minimum width. It does not
collapse into icons or a separate mobile navigation pattern.

## Real Editor Sizing

`NotesPanel` gains an explicit container-sizing mode in addition to its current
stored-panel sizing. The default remains stored-panel sizing so the menu-bar
panel, pinned notes window, Settings previews, and existing tests retain their
current behavior.

Onboarding alone requests container sizing. In that mode:

- `NotesPanel` accepts the width and height proposed by its parent.
- It fills the available canvas instead of reading
  `preferences.panelWidth` and `preferences.panelHeight` for its outer frame.
- Its real header, tab strip, toolbar, editor, save state, errors, and overlays
  remain unchanged.
- The editor body remains the primary flexible/scrollable region.
- The onboarding canvas supplies a practical minimum editor height, but that
  minimum must fit inside the 760 by 520 onboarding contract.

No second editor, toolbar, dictation state, or screenshot representation is
introduced.

## Step Behavior

### Welcome

Keep the existing centered readable column. At compact height, reduce outer
padding first. If accessibility text or localization still exceeds the body,
scroll only the step body while keeping the rail and footer fixed.

### Your First Note

Keep the instruction header above the real editor. The editor fills all
remaining body space. Continue remains visible while the editor scrolls
internally.

### Dictation

Replace the nested `liveCanvas` composition with one responsive vertical
layout:

1. Step title and explanation.
2. Modifier picker.
3. Short “Try it in Fleck” instruction.
4. Flexible real-editor canvas.
5. Optional dictation-success label.

The title and picker have fixed intrinsic height. The editor receives the
remaining space and may not force either the title or footer out of view.

### Permissions and Compatibility

Permission actions remain in a fixed action row immediately above the footer
and keep their existing Not Now and Allow behavior. The explanatory content
above that row may scroll when needed. Compatibility content may scroll inside
the step body, and its rows wrap their details instead of being clipped
horizontally.

### Get Fleck

Keep the final access choices and legal copy centered within a readable width.
The body may scroll at compact height or with larger accessibility text, while
Back stays in the footer. This layout work does not change the unavailable
development access adapter or add StoreKit behavior.

## State and Data Boundaries

This project changes presentation only:

- No onboarding progress, resume, completion, permission, or access semantics
  change.
- No normal Fleck panel preference is rewritten during onboarding resize.
- No new persistent preference or window-size migration is introduced.
- The real editor and dictation runtime remain the only live demo surfaces.
- StoreKit 2, trial entitlement, purchase, restore, expiry, and read-only
  enforcement remain later access-subsystem work.

## Accessibility

- Preserve semantic headings, labels, rail accessibility values, and keyboard
  order.
- Keep Back and Continue reachable without scrolling the step body.
- Do not reduce hit targets or font sizes in compact mode.
- Support Reduce Motion and Reduce Transparency exactly as the current shell
  does.
- Verify VoiceOver order as rail, step heading/content, step-specific actions,
  then footer navigation.
- Verify increased text size at the minimum window size; static content must
  scroll instead of clipping.
- Compatibility details must wrap and remain associated with their capability
  labels.

## Testing Strategy

### Deterministic Tests

Add a small presentation model for regular versus compact layout selection and
test the threshold boundaries. Add source/structure tests that prove:

- Onboarding uses the container-sized `NotesPanel` mode.
- Normal `NotesPanel` call sites retain stored-panel sizing by default.
- The responsive Dictation step does not nest the old full `liveCanvas` layout.
- The footer remains outside any step-body scroll view.
- The declared minimum and default sizes match this specification.

Keep existing onboarding, editor, window, dictation, and source-audit tests
passing.

### Manual Verification

Use a disposable Application Support directory or test account. For every
onboarding step, verify:

- 760 by 520 minimum size.
- 919 by 619 compact boundary.
- 920 by 620 regular boundary.
- 1,080 by 700 default size.
- A larger desktop window.
- Live resizing between those sizes.
- Increased text size, VoiceOver, Reduce Motion, and Reduce Transparency.

At every size, confirm that the complete footer and permission action row stay
visible. Headings, the selected modifier, compatibility details, and access
choices must either remain visible or be reachable through the step-body scroll
area. Confirm the real editor grows, shrinks, edits, saves, formats, and
dictates without changing the user's normal panel-size preferences.

## Acceptance Criteria

- No onboarding step clips required content at or above 760 by 520 points.
- The Dictation title, modifier picker, real editor, and footer are visible
  together at the minimum size.
- The footer never scrolls or leaves the window.
- The progress rail remains legible and complete at the minimum width.
- The embedded editor fills available space instead of forcing a 520 by 430
  outer frame.
- Static content scrolls when localization or increased text needs more room.
- Normal menu-bar and pinned Fleck notes windows retain their saved dimensions.
- No user notes, onboarding progress, permissions, access state, or commerce
  behavior changes as a side effect of resizing.
