# Fleck Editor, Tabs, and Branding Design

**Status:** Approved implementation design
**Date:** 2026-08-05

## Objective

Make Fleck's existing tab strip, rich-text formatting bar, and packaged identity
behave like one coherent native macOS surface. The work adds live tab reorder
selection, trailing overflow affordances, precise in-editor typography and color
formatting, and the canonical Fleck mark in the packaged app. It keeps Fleck a
menu-bar-only macOS 14 application while preserving every existing reachable
window and runtime.

The implementation target is macOS 14 and later. It must compile against Xcode
26 with the macOS 26 SDK while retaining the repository's macOS 14 deployment
target; no newer deployment-only API is required.

## Existing Architecture

`NotesPanel` is the one production notes surface: it contains the header, tab
strip, `FormattingBar`, title field, and `NativeRichTextEditor`. `AppState`
owns the loaded `Workspace`, selection, and debounced persistence. `Workspace`
stores ordered `Note` values and `selectedNoteID`; `Workspace.moveNote(id:to:)`
and `AppState.moveNote(_:to:)` are the existing order-and-save path.

The tab strip already uses `TabDragReorder`, own-process `NSItemProvider`, and
`TabDropDelegate`. That native path remains the starting implementation path.
`TabDragReorder` tests remain the contract for deterministic identifier order
and move semantics. This document supersedes the earlier drag-design selection
detail: starting a drag now selects the dragged tab.

`EditorCommands` is defined with `NativeRichTextEditor` and holds the live
`NSTextView`. Its `typingAttributes` and `textStorage` are the only formatting
source of truth. The SwiftUI formatting bar observes command state; it does not
mirror document formatting in a new editor model. Calling `NSTextView.didChangeText()`
continues through the existing editor delegate to `NotesPanel`,
`AppState.updateSelected(body:richTextRTF:)`, and the existing local save path.

Notes persist readable Markdown/plain body plus an optional RTF sidecar.
`LocalStoreSnapshotWriter` already writes and reloads the RTF data. Existing
preferences provide default font and editor colors, but per-selection commands
are document formatting, not a new preference or storage field.

`Scripts/build-fleck-app.sh` builds and development-signs `.build/Fleck.app`
from `Sources/FleckApp/Info.plist`; `Scripts/validate-macos.sh` is the packaged
release gate. The canonical logo source is `website/public/fleck-mark.png`.

## User Experience

### Tabs and reorder

- Beginning a native drag first selects that note through the existing
  `AppState` selection path, so the selected-tab highlight travels with the
  dragged identity.
- Hovering over a neighboring tab moves the dragged identifier into that live
  neighbor position. Hovering successively left or right updates the visible
  order before release. Dropping retains the most recent order.
- Reordering preserves the note UUID, body and RTF, pin state, selected note,
  agent-sharing state, and the normal debounced persistence behavior. It never
  alphabetizes or date-sorts tabs.
- The first repair is the smallest change to the existing
  `TabDragReorder`/`NSItemProvider`/`DropDelegate` flow. A local horizontal
  `DragGesture` is permitted only when packaged-app verification demonstrates
  that native drag/drop still fails. An AppKit collection-view rewrite is out
  of scope.

### Trailing tab overflow

The single horizontal tab strip remains scrollable and single-row. When its
content extends beyond the visible trailing edge, it shows a narrow right-edge
fade and a small right-chevron. The chevron has an accessible name describing
that it reveals more tabs; activating it scrolls hidden trailing tabs into
view. It is shown only while tabs remain hidden to the right, and is laid out
beside, rather than over, the final visible tab. Neither affordance appears
when the trailing edge is fully visible.

There is no left-chevron, multi-row layout, tab compression redesign, or
automatic drag edge scrolling. Normal horizontal scrolling remains how users
return left.

### Typography and editor colors

The font menu lists available families and displays a checkmark beside the
family at the caret or a uniform selection. A mixed-family selection displays
no family checkmark. Selecting a family changes selected runs or the typing
font at a zero-length selection and preserves bold, italic, underline,
foreground color, highlight, paragraph style, and list metadata.

The toolbar contains one editable numeric size field, not presets or a
stepper. It displays the current caret or uniform-selection size. Return and
focus loss submit it. Accepted values are finite numeric point sizes in the
inclusive range **1...512**; values outside that range, empty input, and
non-numeric input restore the current displayed size without changing document
content. A valid size applies to selected runs or to subsequent typing at a
zero-length selection, preserving all unrelated attributes.

Compact Font Color and Highlight menus reuse the existing Fleck palette used
for tab colors: Red, Orange, Yellow, Green, Blue, Purple, Pink, and Gray.
Font Color also includes `Automatic`; Highlight also includes `No Highlight`.
Each menu checkmarks the uniform caret/selection value and has no color
checkmark for mixed selections. Font Color writes
`NSAttributedString.Key.foregroundColor`; `Automatic` removes that explicit
attribute. Highlight writes `NSAttributedString.Key.backgroundColor`; `No
Highlight` removes that explicit attribute. These commands apply to selected
text or `typingAttributes` for subsequent text at a zero-length selection.

### Branding and Dock behavior

The website mark is reused without redesign. Packaging copies
`website/public/fleck-mark.png` into `Fleck.app/Contents/Resources`, and
production code loads that bundled resource. The menu-bar image is rendered as
a monochrome template mark. The `NotesPanel` header's top-left area shows the
colored, non-template mark beside the `Fleck` title.

`LSUIElement` is `true` in the packaged app. Fleck therefore intentionally has
no Dock or Command-Tab presence. This does not make its application windows
unreachable: `MenuBarExtra`, the pinned notes window, Settings, onboarding,
launch-at-login behavior, the dictation capsule, and Agent Connector retain
their current entry points and lifecycles.

## Architecture and Data Flow

SwiftUI owns presentation state for the trailing overflow fade and chevron,
menus, current command labels, and the numeric size field. `EditorCommands`
owns narrowly scoped AppKit mutation and reads current attributes from the
live `NSTextView`. Its current-format query reads `textStorage` at the selected
run when nonempty and `typingAttributes` at a caret; a selection with differing
values reports mixed rather than inventing a representative value.

For a nonempty range, font family/size changes enumerate font runs and replace
only `.font`; color commands add or remove only their corresponding color
attribute. For a zero-length range, the same change is made only to
`typingAttributes`. Each successful document mutation calls `didChangeText()`;
therefore existing undo registration, delegate snapshots, RTF serialization,
`AppState` update, and debounced save remain in force. A rejected size input
does not mutate the text view and does not call `didChangeText()`.

The native drag drop delegate resolves indices against the current workspace
on every hover, calls the existing `AppState.moveNote(_:to:)`, and clears its
local dragged identifier on drop. No preview array, alternative selection
store, reorder persistence path, or sorting rule is introduced.

Packaging has one asset flow: the build script copies the canonical public PNG
into the app resources before signing, and code resolves that bundle resource.
An explicit development-only fallback may remain for bare `swift run`, which
is not an interactive production path. Packaged Fleck must never silently omit
the mark.

No dependency, storage format, editor model, state store, migration, or generic
formatting abstraction is added.

## Failure Handling

- Unknown, self, missing, or stale native drag identities are no-ops. A failed
  or cancelled drop cannot delete or duplicate a note; the latest valid live
  workspace order remains selected and persistable.
- If overflow measurement cannot establish hidden trailing content, the fade
  and chevron stay absent. The chevron only attempts the existing scroll view's
  trailing reveal; it does not cover a tab or create a second strip.
- An unavailable font conversion leaves the existing font unchanged. Invalid
  numeric size input restores its prior visible value, leaves content and
  selection intact, and produces no persistence change.
- Removing `foregroundColor` or `backgroundColor` removes only that explicit
  attribute. The text system supplies its normal effective color afterward;
  no global editor preference is changed.
- If RTF encoding fails after a successful text-system mutation, existing
  `onChange` behavior supplies the plain body and existing save-error handling
  remains the user-visible error path. This feature does not log note text,
  selections, colors, font family, or font size.
- A missing canonical asset, missing bundled resource, missing `LSUIElement`,
  or signing-identity regression is a packaging validation failure, not a
  blank-logo fallback.

## Accessibility

All new controls have explicit accessible names and values: the chevron
announces hidden trailing tabs, font and color menus announce their current
uniform value or mixed state, and the numeric field announces its point value
and accepted 1 through 512 range. Menu checkmarks are not the sole state
signal. Keyboard focus can reach the numeric field and menus; Return submits
the field and focus loss applies the same validation. The tab strip retains
native keyboard and scroll interaction. The fade is decorative and ignored by
accessibility.

Reduce Motion preserves the existing immediate reorder behavior. The visual
mark does not carry unique control meaning, and the text title remains exposed
beside it.

## Persistence and Compatibility

Workspace ordering and selection keep their current `Workspace` and `AppState`
representation. Moving a tab persists through the existing debounced save;
its note content, RTF, pin state, UUID, agent permissions, and revision rules
are not transformed.

Rich text continues to round-trip through optional RTF sidecars, preserving
font, foreground, and background attributes. Markdown and plain body exports
remain text-only and do not gain color or typography schema. No storage schema
or migration is necessary.

This work preserves local-first and agent privacy boundaries: no note content
or formatting state is exposed to logs, analytics, new services, or the agent
bridge. Enhanced Local remains non-shippable under its existing release
boundary. Dictation capture, cleanup, permission, capsule, and focused-editor
paths remain unchanged apart from inheriting the already-current typing
attributes for new text.

## Verification

Use TDD: first write focused failing tests, then make them pass. The focused
suite covers current font state; caret and selection family/size application;
invalid numeric sizes; foreground and highlight apply/removal; preservation of
unrelated font traits, underline, paragraph, and list attributes; and RTF
round-trip preservation. Retain existing `TabDragReorder` tests and add pure,
deterministic tests for overflow visibility decisions and live reorder where
possible.

Brand/package coverage verifies canonical asset copy, source-level template
menu-bar and colored `NotesPanel` usage, `LSUIElement=true`, stable existing
signing requirements, and the packaged resource at
`Contents/Resources/fleck-mark.png`. Extend `Scripts/validate-macos.sh` so any
missing mark or `LSUIElement` contract fails validation.

Run focused tests, then:

```sh
swift test --disable-automatic-resolution --no-parallel
Scripts/validate-macos.sh
```

Run hosted CI after the branch is pushed. In a live packaged `.build/Fleck.app`,
use disposable tabs and notes to verify dragging left and right, fade and
chevron appearance/reveal, numeric size submission, font menu checkmark, text
color and highlight persistence across relaunch, colored/header and template
menu-bar marks, and absence from both Dock and Command-Tab. Never use or alter
the leftmost personal tab; choose a testing tab to its right.

`swift run` and source inspection are not evidence for packaged interaction,
resource, Dock, Command-Tab, signing, or privacy behavior.

## Non-Goals

- An AppKit collection-view tab implementation, custom tab model, custom drag
  physics, cross-window drag, drag edge scrolling, automatic sorting, tab
  compression, multi-row tabs, or a left overflow chevron.
- Font preset menus, a size stepper, an unconstrained size field, replacement
  of selected attributes as a whole, global per-document color settings, or a
  new formatting persistence format.
- A new logo, an external asset pipeline, a Dock icon mode, removal of
  Command-Tab exclusion, or a production asset fallback that hides a package
  error.
- Changes to Enhanced Local shipping eligibility, Agent Connector privacy or
  permissions, dictation behavior, onboarding flow, launch-at-login behavior,
  or existing signing identity rules.

## Acceptance Criteria

1. Drag start selects the dragged tab; hovering each adjacent tab live-reorders
   left or right through the existing native path; drop retains the final
   sequence without loss, duplication, sorting, or changes to note identity,
   body, RTF, pin state, selection, or persistence.
2. A trailing fade and accessible right-chevron appear only when tabs are
   hidden on the right. Activating the chevron reveals them without covering the
   final visible tab; no left-chevron, compression, or second row exists.
3. The font menu checks the uniform caret/selection family and shows none for
   mixed families. The only size control is a 1...512 numeric field whose
   valid submit changes selected text or future typing while retaining unrelated
   attributes; invalid input restores the prior value without content change.
4. Font Color and Highlight use the existing Fleck palette, correctly report
   uniform/mixed state, add or remove only `foregroundColor` and
   `backgroundColor`, and affect selected text or future typing as applicable.
5. Successful formatting mutation calls `didChangeText()`, participates in
   existing undo and persistence, preserves RTF through relaunch, and leaves
   Markdown/plain body text-only.
6. The packaged app contains the canonical mark in `Contents/Resources`, uses
   it as a template menu-bar mark and colored `NotesPanel` mark/title, and
   validation fails when that resource or its required source contract is
   absent.
7. Packaged Info.plist has `LSUIElement=true`, Fleck is absent from Dock and
   Command-Tab, and its menu bar, pinned notes, Settings, onboarding,
   launch-at-login, dictation capsule, and Agent Connector remain reachable.
8. Focused TDD tests, the full ordinary Swift test command,
   `Scripts/validate-macos.sh`, hosted CI, and the stated disposable-tab live
   packaged-app checklist all pass before release consideration.
9. The implementation adds no dependency, migration, state store, alternate
   editor, storage schema, new logging of private formatting or note data, or
   change to Enhanced Local, agent boundaries, and unrelated dictation paths.
