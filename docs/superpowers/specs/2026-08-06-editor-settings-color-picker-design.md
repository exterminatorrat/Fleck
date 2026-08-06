# Fleck Editor Settings and Shared Color Picker Design

**Status:** Approved
**Date:** 2026-08-06

## Objective

Remove the duplicate font-family and font-size controls from Fleck Settings,
make the editor toolbar the only visible typography surface, replace every
system `ColorPicker` and fixed color menu with one Fleck-designed in-app color
picker, and clarify the toolbar's visibility language.

The result must preserve existing notes, rich-text attributes, user preferences,
and the local-first persistence model. It must remain a native macOS 14 SwiftUI
and AppKit application with no new dependency or system color-panel presentation.

## Settled Product Behavior

### Typography settings

- Remove Font and Font Size from Settings > Appearance.
- Keep the editor toolbar's font-family menu and numeric size field unchanged as
  the only visible typography controls.
- Preserve stored `fontFamily` and `fontSize` preferences for compatibility.
  Existing installations retain their saved defaults; new installations continue
  to begin with Avenir Next at 17 points.
- Do not migrate or rewrite existing notes, RTF sidecars, titles, or preferences.
- Toolbar font and size changes remain selection- or caret-scoped document
  formatting. They do not silently become global defaults.

### Editor toolbar visibility and naming

- Remove `Show formatting bar` from Settings > Editing.
- Keep the existing header chevron as the direct show/hide control.
- Preserve the stored `showFormattingBar` preference and its current default.
- Replace user-facing `formatting bar` / `formatting controls` terminology on
  this surface with `Editor toolbar`, including help and accessibility copy.
- Showing or hiding the toolbar must continue to preserve the live `NSTextView`,
  selection, typing attributes, rich text, and undo manager.

### Shared in-app color picker

Use one reusable Fleck color-picker surface for:

- application accent color;
- default editor text color;
- default editor background color;
- selection/caret font color;
- selection/caret highlight color; and
- per-note tab color.

The picker appears as a compact popover anchored to the invoking control or tab.
It never invokes SwiftUI `ColorPicker`, `NSColorPanel`, or a detached system color
window.

The popover contains:

1. The existing Fleck palette: Red, Orange, Yellow, Green, Blue, Purple, Pink,
   and Gray.
2. A visible current/draft color preview.
3. In-app Hue, Saturation, and Brightness controls.
4. An editable six-digit `#RRGGBB` hexadecimal field.
5. Context-specific reset behavior: `Use System`, `Automatic`, `No Highlight`,
   or `None`.
6. Apply and Cancel for custom edits.

Palette choices and reset choices apply immediately and dismiss the popover.
Custom Hue/Saturation/Brightness and hexadecimal edits update only the picker's
preview. Apply commits one color change and dismisses; Cancel dismisses without
changing the original value. Invalid hexadecimal input does not commit and keeps
the picker open with accessible validation feedback.

Opacity and recent-color history are explicitly excluded. Every committed custom
color is normalized to uppercase `#RRGGBB` in sRGB.

## Existing Architecture and Seam Placement

`SettingsView` owns preference presentation and writes through
`AppState.updatePreferences`. `NotesPanel` owns the production tabs, header,
editor toolbar, and `NativeRichTextEditor`. `EditorCommands` owns selection- and
caret-scoped AppKit text mutations. `Workspace` and `AppState` own tab colors.

Add one shared SwiftUI color-picker module in `FleckApp`. It owns palette display,
draft color editing, validation, and normalized color conversion. Callers continue
to own durable state and the meaning of `nil`:

- Settings commits preference hex strings through `AppState.updatePreferences`.
- Font and highlight commits call the existing `EditorCommands` color methods.
- Tab color commits call the existing `AppState.setSelectedTabColor` path.

The shared picker does not own preferences, notes, `NSTextView`, workspace state,
or persistence. It receives a current optional hex color, context-specific reset
copy, and commit/cancel callbacks. This keeps SwiftUI presentation state local and
avoids a second color state store.

The existing palette type should move out of `NotesPanel.swift` and receive a
shared name because it is no longer tab-specific. Existing hex and `NSColor`
helpers should move with it rather than being duplicated.

## Per-Surface Interaction

### Settings

Appearance retains Theme, Accent Color, Editor Text Color, Editor Background,
glass opacity, and menu dimensions. The three colors use compact labeled swatch
buttons that open the shared picker. Optional editor colors expose `Use System` in
the picker rather than adjacent reset buttons.

### Editor toolbar

Font Color and Highlight remain in their current toolbar positions. Their buttons
open the shared picker. The picker reads the live `EditorCommands` state; mixed
selections announce `Mixed` and begin from a sensible palette/custom draft without
inventing a document-wide value. Commits continue through
`applyForegroundColor(_:)` and `applyBackgroundColor(_:)`, preserving existing RTF,
undo, and typing-attribute behavior.

### Tabs

The tab context menu replaces its nested fixed palette with `Tab Color...`.
Selecting it opens the same anchored picker for that exact note. The note becomes
the selected tab before the existing selected-tab-color mutation path runs. A
stale or removed note is a no-op.

## Accessibility and Motion

- Every trigger exposes its purpose and current value, including `Mixed`,
  `Automatic`, `No Highlight`, `None`, and named palette colors.
- Palette swatches have text labels or equivalent accessible names; color alone is
  never the only state signal.
- Hue, Saturation, and Brightness have accessible labels, numeric values, and
  keyboard-adjustable native controls.
- The hexadecimal field announces its accepted `#RRGGBB` format and invalid state.
- Apply, Cancel, and context-specific reset controls are keyboard reachable.
- Popover presentation uses native behavior without decorative motion. Reduce
  Motion introduces no alternate behavior because no functional animation is
  added.

## Failure Handling

- Invalid or non-sRGB colors do not commit.
- Invalid hexadecimal input remains local to the picker and never mutates notes or
  preferences.
- Cancel, outside dismissal, tab removal, and view teardown preserve the original
  value.
- Mixed editor selections remain mixed until the user explicitly commits a color.
- A failed preference or note save continues through the existing `AppState`
  error path.
- Picker state contains colors only and never logs note text, titles, selections,
  credentials, or agent data.

## Persistence and Compatibility

No persistence schema changes. Keep `AppPreferences.fontFamily`, `fontSize`,
`showFormattingBar`, accent/editor color fields, and all Codable defaults intact.
Tab colors remain optional note metadata. Rich-text font and highlight colors
remain RTF attributes. Markdown and plain-text exports remain text-only.

## Verification

Use TDD for normalized hex/HSB conversion, invalid input, palette matching, reset
semantics, and source/runtime integration. Extend focused AppKit/editor tests for
custom font and highlight colors, toolbar naming, and preservation across hide/show.
Add source-contract coverage that Settings no longer exposes font/size or the old
toolbar toggle and that no production `ColorPicker` remains.

Run:

```sh
swift test --disable-automatic-resolution --no-parallel --quiet
Scripts/validate-macos.sh
git diff --check
git diff --exit-code -- Package.resolved
```

Packaged-app QA must use `.build/Fleck.app` and a disposable tab to the right of
the protected leftmost personal tab. Verify all six color contexts, custom Apply
and Cancel, invalid hex, Light/Dark appearance, keyboard navigation, toolbar
hide/show preservation, relaunch persistence, and absence of a system color panel.

## Non-Goals

- Opacity, alpha-channel hex, recent colors, saved palettes, eyedropper, gradients,
  or color-space selection.
- Changing typography defaults, applying toolbar typography globally, or removing
  compatibility fields from `AppPreferences`.
- Replacing the native rich-text editor, changing RTF/Markdown storage, or altering
  dictation, agent access, onboarding, shortcut recording, window sizing, tab
  ordering, or persistence architecture.
- A dependency, reusable cross-product design system, or AppKit color-panel bridge.

## Acceptance Criteria

1. Settings exposes no font-family, font-size, or toolbar-visibility control.
2. The header chevron remains the direct control and uses `Editor toolbar` copy.
3. No production `ColorPicker` or `NSColorPanel` path remains.
4. All six color contexts open the same Fleck picker and preserve their existing
   mutation/persistence seams.
5. Palette/reset commits are immediate; custom changes commit once with Apply and
   cancel cleanly.
6. Hex input accepts and normalizes valid `#RRGGBB`, rejects invalid input, and
   supports keyboard and accessibility use.
7. Existing preferences and notes load without migration or restyling.
8. Focused tests, the full Swift test suite, packaged validation, diff checks, and
   the fresh Sol review all pass before completion is claimed.
