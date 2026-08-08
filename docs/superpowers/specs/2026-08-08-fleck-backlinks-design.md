# Fleck Backlinks Design

**Date:** 2026-08-08
**Status:** Proposed for user review
**Base:** `codex/fleck-search-folder-integration` at `b036e149108e53e8959f55255f34220e5d5131f2`

## Objective

Add durable note-to-note links and automatically derived backlinks without replacing Fleck's real `NSTextView`, changing the note schema, or introducing a second relationship database.

The first release optimizes for durability and inspectability. An internal link is visible Markdown in the canonical note body:

```markdown
[Launch Checklist](fleck://note/550e8400-e29b-41d4-a716-446655440000)
```

The label is readable text chosen when the link is inserted. The UUID is the stable destination. Renaming a target note therefore does not break navigation, and Markdown export, plain-text tools, agent edits, recovery, and external editors retain the complete relationship.

## Success Criteria

1. Typing `[[` in the production editor opens a keyboard-first note picker. Choosing a live note replaces the trigger with a valid visible Markdown link in one undoable edit.
2. An accessible Editor menu or context-menu command opens the same picker without requiring the `[[` gesture.
3. Internal Markdown links use Fleck's accent color and native link presentation without changing their canonical text.
4. Command-clicking an internal link opens its UUID target through the existing folder-aware note activation path. Keyboard and accessibility users have an equivalent Open Note action.
5. A compact, collapsed-by-default `Linked from N` section below the editor lists live notes that link to the selected note. Expanding or collapsing it does not recreate the editor or alter editor state.
6. Backlinks are derived from current live note bodies. Trash is excluded, stale work is rejected, and no persisted backlink index or schema migration is introduced.
7. Markdown/plain-text import, export, persistence, agents, rich text, selection, typing attributes, undo, dictation, Search, Folders, and tab behavior remain intact.

## User Experience

### Creating a link

- When the user types `[[`, Fleck opens a note picker anchored to the current editing context.
- The picker searches all live non-Trash notes by the existing stable title/body search conventions, with exact and prefix title matches prioritized.
- The selected note's current display title becomes the Markdown label. Fleck escapes characters that would otherwise terminate the label.
- Choosing a result replaces only the `[[` trigger with `[Current Title](fleck://note/<uuid>)`.
- The replacement is one undo operation. Escape closes the picker and leaves the literal `[[` untouched.
- The picker excludes the current note by default to avoid accidental self-links. A manually typed self-link remains valid but is not shown as a backlink row.
- The Editor menu and editor context menu expose `Link to Note…`, which opens the same picker at the current selection or insertion point.

The picker appears immediately and does not animate. It is a frequent keyboard interaction, so motion would add perceived delay without explaining state.

### Opening a link

- Command-click opens the target note. The current plain click behavior remains text selection and caret placement so editing is not surprising.
- The context menu exposes `Open Note Link` when the insertion point or selection intersects a valid internal link.
- Keyboard users can invoke the same command from the Editor menu.
- Activation uses the existing `activateNoteAndScope` path: resolve the current folder, change transient folder scope, select the UUID, and attach the same real editor to the destination.
- A link to a note currently in Trash or no longer present does not navigate. Fleck leaves the source text unchanged and presents a concise `Note unavailable` status. Restoring a trashed note with the same UUID makes the link work again automatically.

### Link appearance

- The full Markdown token remains visible. Fleck does not hide the UUID or maintain an invisible second representation.
- Valid internal links receive native underline/link affordance using the current accent color.
- A syntactically valid link whose UUID has no live target uses a warning treatment and exposes `Missing note link` to accessibility.
- Presentation attributes must not overwrite user-authored font, foreground color, highlight, paragraph, checklist, selection, or typing attributes. They must not create undo entries or persistence churn merely because a note is displayed.

### Backlinks section

- A single row beneath the editor reads `Linked from N` and uses a disclosure chevron.
- It is collapsed by default for each panel lifetime and is not persisted in preferences.
- When expanded, it shows one row per live source note, ordered by most recently modified and then stable UUID.
- Each row shows the source note's current display title, its folder name when present, a single-line Unicode-safe excerpt around the first matching link, and a count when that source contains multiple links to the target.
- Selecting a row activates the source through `activateNoteAndScope`.
- Empty state is compact: `Linked from 0` remains available but does not reserve an expanded panel.
- The section has no automatic expansion, no entrance animation, and no right-side inspector. This protects the 640-point menu layout and keeps the editor primary.

## Canonical Link Contract

### Syntax

Fleck recognizes only this internal destination form:

```text
fleck://note/<uuid>
```

The UUID parser is case-insensitive and normalizes to the canonical hyphenated representation when Fleck inserts a link. The Markdown parser accepts escaped label characters created by Fleck and rejects malformed destinations, extra authority components, query items, fragments, non-UUID identifiers, and non-`fleck` schemes.

The first release intentionally does not implement general Markdown rendering, title-only wiki links, aliases, block references, headings, transclusion, or external URL handling.

### Rename and deletion behavior

- The UUID controls navigation; the written label is informational.
- Renaming a target does not rewrite source notes. Avoiding automatic fan-out writes protects undo history, revisions, agent coordination, and persistence performance.
- New links use the target's current title. Existing labels may be manually edited without changing the target.
- Moving a target between folders does not change the link.
- Moving a source or target to Trash excludes that note from the live backlink index. Restoring the same UUID restores the relationship.
- Permanent deletion leaves a visible broken link. Fleck never silently removes user-authored source text.

## Architecture

### Core parser and derived index

Introduce a small pure FleckCore boundary:

- `NoteLink`: target UUID, display label, and UTF-16 source range.
- `NoteLinkParser`: parses only Fleck's internal Markdown syntax from a body snapshot and never mutates notes.
- `BacklinkIndex`: derives incoming edges from live note snapshots and groups them by target UUID and source UUID.

The index is not Codable and is never written to disk. It is a cache over canonical note bodies. Multiple links from one source are preserved internally, while the first UI groups them into one row with a count.

### App controller

A MainActor `BacklinkController` owns presentation state and publishes the accepted derived index. It:

1. snapshots live note IDs, titles, folders, modification dates, revisions, and bodies;
2. computes parsing/index work away from the main actor;
3. cancels superseded work;
4. uses a generation token before publishing so stale results cannot replace a newer workspace snapshot; and
5. incrementally reuses parsed results for source notes whose ID, revision, and body are unchanged.

The controller remains derived state. `Workspace`, `Note`, `LocalStore`, manifests, Markdown files, and recovery formats do not gain backlink fields.

### Existing editor bridge

Extend the existing `NativeRichTextEditor`/`EditorCommands` boundary narrowly:

- Detect the production `[[` trigger and report its replacement range.
- Replace that range through the existing real text storage and undo manager.
- Identify internal-link ranges for presentation and Command-click/context-menu routing.
- Apply link presentation without replacing the `NSTextView`, creating a duplicate attributed model, or disturbing the existing RTF synchronization contract.

SwiftUI owns picker and backlinks presentation. AppKit owns text-system range lookup, responder-chain commands, selection, replacement, and click routing. Any AppKit coordinator state is lifecycle-bound to the existing editor and cannot become a second workspace or navigation source of truth.

### NotesPanel integration

`NotesPanel` owns one link-picker presentation and one backlink disclosure state alongside its existing Search and folder scope state. It supplies:

- the live non-Trash note snapshot for picker results and index computation;
- the selected note UUID for incoming-link lookup;
- `activateNoteAndScope` for opening both outgoing links and backlink rows; and
- the existing accent color for link presentation.

Search and the note-link picker are mutually exclusive overlays. Presenting either makes the normal underlying action surface inert. Escape closes the topmost overlay and restores the prior title/body responder without changing workspace, folder scope, selection, or save generation.

## Data Flow

### Insertion

```text
NSTextView types [[
  -> editor reports trigger range
  -> NotesPanel presents note picker
  -> user chooses live UUID
  -> EditorCommands replaces trigger with Markdown token
  -> existing editor update emits body + RTF once
  -> AppState persists through the existing save path
  -> BacklinkController accepts the new workspace generation
```

### Navigation

```text
Command-click or Open Note Link
  -> parser resolves UUID at character range
  -> NotesPanel validates UUID is currently live
  -> activateNoteAndScope(UUID)
  -> folder scope changes transiently
  -> existing editor attaches to selected note
```

### Incoming links

```text
live workspace snapshot
  -> background parser/index build
  -> generation validation
  -> incoming edges for selected UUID
  -> collapsed Linked from count / expanded source rows
```

## Persistence, Import, Export, and Agents

- `Note.body` remains canonical Markdown/plain text.
- `richTextRTF` remains the optional parallel rich-text representation. Link presentation must round-trip without changing the visible Markdown token or dropping other attributes.
- Markdown and plain-text export preserve the exact token.
- Markdown/plain-text import needs no migration; valid Fleck links become active when their UUID exists in the current workspace.
- Rich-text export may include hyperlink metadata, but the visible token remains complete even when opened by software that ignores Fleck URLs.
- Agent-created or agent-edited links work when they use the exact syntax. No new agent operation is required in the first release.
- Snapshot integrity, recovery candidates, Trash entries, and unchanged-byte reuse continue to operate on the existing body and RTF files.

## Error Handling

- Malformed Markdown, malformed UUIDs, and unrelated URL schemes remain ordinary editable text.
- Picker activation revalidates the selected UUID immediately before insertion.
- Link navigation revalidates the target against current live notes immediately before changing scope.
- Backlink results carry source UUIDs and are revalidated before activation so deletion, Trash, or concurrent folder changes cannot open stale entries.
- A cancelled or stale background index result is discarded without changing the published index.
- No parsing failure can invalidate a note, workspace snapshot, or preferences decode.

## Accessibility and Interaction

- `[[` is a convenience, not the only entry point.
- `Link to Note…` and `Open Note Link` are reachable from the Editor menu and editor context menu with normal menu validation.
- The picker exposes its search field, result count, highlighted result, and each result's title/folder context.
- Backlink disclosure announces count and expanded state. Rows announce source title, folder, excerpt, and reference count.
- Link presentation meets contrast requirements for the selected accent and does not rely on color alone; underline distinguishes valid links and a warning trait distinguishes missing targets.
- Full Keyboard Access and VoiceOver can create, open, expand, navigate, and dismiss without mouse-only behavior.

## Performance

- Parsing never runs synchronously across the full workspace on every keystroke.
- Changed-note parsing is cancellable and performed from immutable snapshots off the main actor.
- Cached parse results are keyed by source UUID plus revision/body identity.
- UI publication is generation-checked and coalesced.
- Performance tests cover 10, 100, and 1,000-note workspaces, including dense-link fixtures, a single-note edit, picker first-result latency, and backlink publication latency.
- No persistent index is introduced unless measurements later prove the derived cache insufficient.

## Verification Strategy

### FleckCore tests

- valid internal Markdown links, Unicode labels, escaped label delimiters, multiple links, and UTF-16 ranges;
- rejection of malformed schemes, authorities, UUIDs, query/fragment variants, and incomplete syntax;
- deterministic grouping/order, duplicate-source counts, self-link UI exclusion, Trash/live filtering, rename stability, move stability, missing targets, and restore-by-UUID;
- cancellation/generation and incremental reuse behavior;
- 10/100/1,000-note performance fixtures.

### Real AppKit editor tests

- `[[` trigger detection and exact replacement range;
- one-step undo/redo of insertion;
- exact body and RTF round-trip;
- selection, typing attributes, font, color, highlight, paragraph/list/checklist state, and undo availability preserved;
- internal link presentation follows accent without overwriting authored attributes;
- Command-click and menu routing use the production `NSTextView` and exact UUID;
- invalid/missing links do not navigate or mutate workspace;
- editor lifetime remains identical when the backlinks section expands and collapses.

### Hosted NotesPanel tests

- picker presentation/dismissal restores title and body focus exactly;
- Search and picker isolation prevents shortcut or underlay mutation;
- insertion persists once and creates the expected incoming relationship;
- outgoing and backlink navigation change folder scope through `activateNoteAndScope`;
- stale, trashed, and deleted source/target results reject;
- disclosure state changes without editor recreation, save-generation changes, or note mutation;
- folder labels, ordering, counts, snippets, accessibility, and compact 640×430 layout.

### Full and packaged verification

- focused parser/index/editor/NotesPanel regressions;
- complete Swift test suite;
- `git diff --check` and unchanged `Package.resolved`;
- `Scripts/validate-macos.sh` once when the complete implementation is correction-ready;
- strict code-sign verification;
- exact packaged `.build/Fleck.app` QA using only a disposable QA note/tab, never the leftmost personal to-do tab;
- physical Command-click, keyboard menu navigation, VoiceOver, folder transitions, rename, Trash/restore, relaunch, and Markdown export/import.

## Explicit Non-Goals

- Hidden title-only links or an invisible UUID representation.
- General Markdown rendering or an alternate editor.
- `[[Title]]` resolution by mutable title.
- Automatic rewriting of link labels after rename.
- Block references, heading anchors, transclusion, graph view, tags, or web URLs.
- Persisted backlink tables, note-schema changes, migrations, or new dependencies.
- Plug-in architecture, AI model work, iCloud sync, or onboarding changes.

## Delivery Boundaries

- Backlinks is stacked after Search–Folder integration PR #16.
- Product changes must use the explicitly configured Luna / Max app-task implementation lane. The primary Sol task owns architecture, complete task packets, diff inspection, verification, correction decisions, and PR authorization.
- Shared editor and `NotesPanel` ownership is serial. No concurrent writer may modify those files during Backlinks implementation.
- The implementation cannot be reported complete until primary verification is green and the applicable final acceptance workflow returns `ship`.
- The Backlinks PR may be pushed and opened after acceptance, but it must not be merged without explicit user authorization and green exact-head GitHub CI.
