# Trash, Customization, and Toolbar UX Design

**Date:** 2026-07-25
**Status:** Approved

## Goal

Make note deletion deliberate, immediately responsive, and recoverable for 30 days; make
the existing Customize control reliably open useful appearance settings; and make every
formatting control easy to click across its full visible background.

## Scope

This design covers:

- Delete confirmation from every delete entry point.
- Optimistic removal from active tabs after confirmation.
- Local 30-day Trash retention and restore.
- Automatic expiry without a background daemon.
- A Trash sheet opened from the existing ellipsis Options menu.
- Reliable Settings presentation from the top-right Customize control.
- Native appearance controls for the preferences the app already stores.
- Full toolbar hit targets and active-state feedback.

It does not add cloud storage, accounts, synchronization, encryption claims, permanent
delete controls, revision browsing, or new appearance properties beyond the existing
preference model.

## Deletion Experience

The trash button, tab context-menu close action, and configured close-note shortcut all
route through one deletion request in `NotesPanel`.

The request presents a visible confirmation dialog:

- Title: `Move “<note title>” to Trash?`
- Message: `This note can be restored from Trash for 30 days.`
- Actions: `Cancel` and destructive `Confirm`

Nothing changes when the dialog first appears. After the user chooses `Confirm`, the note
disappears from active tabs immediately. `AppState` keeps the complete `Note` value in a
pending-trash collection and starts an immediate background save.

Every save includes the pending-trash values. `LocalStore` writes each complete note to
Trash before it writes the active workspace or removes obsolete live files. A pending
entry is removed from memory only after the store operation succeeds. If the process
stops before the background operation begins, the previous live manifest and note files
remain intact, so the note returns on the next launch instead of being lost.

Save failures continue to use the existing visible error area. The pending item remains
eligible for the next save attempt.

## Trash Storage

Trash lives inside:

```text
~/Library/Application Support/MenuBarNotes/Trash/
└── <note-uuid>/
    ├── metadata.json
    ├── body.md
    └── rich-text.rtf       # only when rich text exists
```

`metadata.json` stores the note UUID, title, creation and modification dates, pin state,
and `deletedAt`. Body and RTF remain separate so the readable local-file contract is
preserved.

Writes use a sibling staging directory followed by a move into the final UUID directory.
Re-saving a still-pending deletion does not reset `deletedAt`; retention always begins
from the first successful move to Trash.

Trash entries expire 30 days after `deletedAt`. Expired directories are removed:

- during app startup;
- before normal saves;
- when the Trash sheet loads.

An app that is not running cannot remove local files at the exact expiry instant. Such
entries are removed automatically the next time the app launches. No polling process or
background daemon is introduced.

## Trash Sheet and Restore

The existing ellipsis Options menu gains `Trash…`. Selecting it opens a sheet attached to
the current notes panel.

The sheet contains:

- a `Trash` title and explanation of the 30-day policy;
- one row per deleted note, newest deletion first;
- note title, deletion date, and days remaining;
- a `Restore` button;
- an empty state when there are no deleted notes;
- a `Done` button.

Restore loads the complete note, saves a workspace containing that note, and removes the
Trash directory only after the active save succeeds. The restored note becomes the
selected tab and keeps its original UUID and formatting.

## Customize and Appearance

The top-right slider control becomes a native `SettingsLink`, allowing SwiftUI to manage
the Settings scene rather than issuing an environment action that currently fails to
surface a window reliably.

The Appearance section continues to update the app immediately and exposes:

- system, light, and dark theme;
- accent color through a native color picker;
- any installed font family;
- font size;
- optional editor text and background colors through native color pickers plus
  `Use System` controls;
- glass opacity;
- panel width and height.

The existing persistence keys and defaults remain unchanged. Editing behavior, launch at
login, and shortcuts stay in their existing sections.

## Toolbar Hit Targets

Every formatting-bar icon uses a shared label with:

- a 28 by 26 point frame;
- a rounded rectangular content shape covering the whole frame;
- the existing icon and accessibility label;
- an accent background when Bold, Italic, or Underline is active.

The button label owns the frame and background. Applying a frame outside a plain SwiftUI
button is insufficient because the glyph can remain the only hit-tested content.

Undo, redo, Bold, Italic, Underline, strikethrough, font, bullets, numbering, and delete
all receive the enlarged label target.

## Error Handling

- A Trash write failure does not remove the previous live disk generation.
- A restore failure leaves the Trash entry in place and reports the error.
- Malformed Trash metadata is skipped rather than blocking valid entries.
- A missing optional RTF file restores the readable Markdown body.
- Expiry cleanup ignores malformed records rather than deleting them prematurely.

## Verification

Portable tests cover:

- body, metadata, and optional RTF retention;
- retention before 30 days;
- purge at 30 days;
- stable deletion timestamps across retries;
- restore preserving UUID, content, and formatting;
- malformed Trash records not blocking valid entries.

Live macOS verification covers:

- every delete entry point showing Cancel and Confirm;
- Cancel preserving the note;
- Confirm removing the note immediately;
- Trash opening from Options and restoring a note;
- Customize opening Settings;
- appearance controls updating the notes panel;
- clicks near the edge of every toolbar background activating its control.

Final validation uses `Scripts/validate-macos.sh` and `git diff --check`.
