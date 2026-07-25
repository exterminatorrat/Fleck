# Trash, Customization, and Toolbar UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make deletion confirmed, instant-feeling, locally recoverable for 30 days, and add a useful Trash and appearance-customization experience with reliably clickable toolbar controls.

**Architecture:** `AppState` removes a confirmed note from the visible workspace immediately but retains its complete value in a pending-trash dictionary. Every save gives pending notes to the `LocalStore` actor, which atomically archives them before committing the active workspace. The core store owns retention, purge, listing, and restore ordering; SwiftUI owns confirmation, sheets, and native controls.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, Swift Testing, local JSON/Markdown/RTF files.

## Global Constraints

- Preserve the existing local-readable Markdown and optional RTF storage contract.
- Do not add accounts, cloud sync, permanent-delete UI, or background daemons.
- Keep existing preference keys and defaults compatible.
- A failed archive must leave the prior active disk generation recoverable.
- A failed restore must leave the Trash entry intact.
- Use `apply_patch` for source edits and run focused tests before the full macOS validation.

---

## Task 1: Add 30-day Trash persistence to the core store

**Files:**
- Create: `Sources/MenuBarNotesCore/TrashedNote.swift`
- Modify: `Sources/MenuBarNotesCore/LocalStore.swift`
- Modify: `Tests/MenuBarNotesCoreTests/LocalStoreTests.swift`

- [ ] **Step 1: Write failing archive, retention, and rich-text tests**

Add deterministic tests using an injected clock:

```swift
let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
let store = LocalStore(rootURL: root, now: { deletedAt })
try await store.save(
  workspace: Workspace(notes: [remaining], selectedNoteID: remaining.id),
  preferences: .init(),
  trashedNotes: [deleted]
)

let trash = try await store.loadTrash()
#expect(trash.first?.note == deleted)
#expect(trash.first?.deletedAt == deletedAt)
```

Verify `metadata.json`, `body.md`, and optional `rich-text.rtf` exist below `Trash/<uuid>/`.

- [ ] **Step 2: Write failing expiry, stable-timestamp, malformed-entry, and restore tests**

Cover these contracts:

```swift
#expect(try await beforeExpiryStore.loadTrash().count == 1)
#expect(try await atExpiryStore.loadTrash().isEmpty)
#expect(retriedTrash.deletedAt == firstDeletedAt)
#expect(validEntriesAreStillReturnedWhenAnotherDirectoryIsMalformed)
#expect(restoredWorkspace.notes.contains(deleted))
#expect(!trashDirectoryExistsAfterSuccessfulRestore)
```

Also verify restore retains the UUID, Markdown body, and RTF data.

- [ ] **Step 3: Run the focused tests and confirm the RED state**

Run:

```bash
swift test --filter LocalStoreTests
```

Expected: compilation failures for the not-yet-created Trash APIs.

- [ ] **Step 4: Add the public Trash value type**

Create:

```swift
public struct TrashedNote: Identifiable, Equatable, Sendable {
  public var note: Note
  public var deletedAt: Date
  public var id: UUID { note.id }
}
```

- [ ] **Step 5: Implement atomic archive, listing, and expiry**

Extend `LocalStore` with:

```swift
public init(
  rootURL: URL,
  fileManager: FileManager = .default,
  now: @escaping @Sendable () -> Date = Date.init
)

public func save(
  workspace: Workspace,
  preferences: AppPreferences,
  trashedNotes: [Note] = []
) throws

public func loadTrash() throws -> [TrashedNote]
```

For each pending note:

1. Skip an already-valid final UUID directory so `deletedAt` remains stable.
2. Write the three files into `Trash/<uuid>.staging`.
3. Move staging to `Trash/<uuid>`.
4. Only then create recovery and commit the active workspace.

Purge valid entries at `deletedAt + 30 days <= now()`. Skip malformed entries without deleting them.

- [ ] **Step 6: Implement restore with safe ordering**

Add:

```swift
public func restore(
  _ trashedNote: TrashedNote,
  into workspace: Workspace,
  preferences: AppPreferences
) throws -> Workspace
```

Build a workspace containing the restored note, save that active generation first, then remove the Trash directory. Return the saved workspace with the restored note selected.

- [ ] **Step 7: Run focused tests and confirm GREEN**

Run:

```bash
swift test --filter LocalStoreTests
```

Expected: all LocalStore tests pass.

- [ ] **Step 8: Commit the core behavior**

```bash
git add Sources/MenuBarNotesCore/TrashedNote.swift Sources/MenuBarNotesCore/LocalStore.swift Tests/MenuBarNotesCoreTests/LocalStoreTests.swift
git commit -m "feat: retain deleted notes in local trash"
```

---

## Task 2: Wire optimistic deletion and restore through app state

**Files:**
- Modify: `Sources/MenuBarNotesApp/AppState.swift`

- [ ] **Step 1: Add observable Trash state and pending archives**

Add:

```swift
@Published private(set) var trashedNotes: [TrashedNote] = []
private var pendingTrashNotes: [UUID: Note] = [:]
```

Replace direct deletion with a note-specific method:

```swift
func moveToTrash(_ id: UUID) {
  guard let note = workspace.notes.first(where: { $0.id == id }) else { return }
  pendingTrashNotes[id] = note
  workspace.deleteNote(id: id)
  saveNow()
}
```

- [ ] **Step 2: Include pending notes in every save**

Capture `Array(pendingTrashNotes.values)` in both immediate and debounced save paths. After a successful, non-cancelled save, remove only the IDs included in that save. Leave pending notes in memory on failure.

- [ ] **Step 3: Add refresh and restore operations**

Add:

```swift
func refreshTrash() async
func restore(_ trashedNote: TrashedNote)
```

Refresh on startup. Restore through `LocalStore.restore`, then publish the returned workspace and refresh the list. Surface failures through `saveError`.

- [ ] **Step 4: Build both targets**

Run:

```bash
swift build
```

Expected: `MenuBarNotesCore` and `MenuBarNotes` build successfully.

---

## Task 3: Add confirmation, Trash UI, native customization, and full hit targets

**Files:**
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Create: `Sources/MenuBarNotesApp/TrashView.swift`
- Modify: `Sources/MenuBarNotesApp/SettingsView.swift`

- [ ] **Step 1: Route every delete entry point through one confirmation**

Track the requested note:

```swift
@State private var notePendingDeletion: Note?
```

Use a single alert:

```swift
.alert(
  "Move “\(notePendingDeletion?.displayTitle ?? "Untitled")” to Trash?",
  isPresented: deletionAlertBinding,
  presenting: notePendingDeletion
) { note in
  Button("Cancel", role: .cancel) {}
  Button("Confirm", role: .destructive) { appState.moveToTrash(note.id) }
} message: { _ in
  Text("This note can be restored from Trash for 30 days.")
}
```

The context menu, shortcut, and formatting-bar trash button must all set this same state.

- [ ] **Step 2: Add Trash to Options and implement its sheet**

Add `Trash…` under the existing import/export menu. The sheet calls `refreshTrash()` on presentation, shows valid entries newest first, displays deletion date and days remaining, and offers `Restore` plus `Done`.

- [ ] **Step 3: Replace the Customize action with `SettingsLink`**

Replace the ineffective environment call with:

```swift
SettingsLink {
  Image(systemName: "slider.horizontal.3")
}
.help("Customize")
```

- [ ] **Step 4: Replace hex text fields with native color controls**

Use `ColorPicker` for accent, editor text, and editor background. For optional colors, retain `Use System` controls that set the stored optional hex value to `nil`. Preserve live bindings through `appState.updatePreferences`.

- [ ] **Step 5: Make every formatting control's full background clickable**

Create a small shared toolbar label:

```swift
private struct ToolbarIconLabel: View {
  let systemImage: String
  var isActive = false

  var body: some View {
    Image(systemName: systemImage)
      .frame(width: 28, height: 26)
      .background(
        isActive ? Color.accentColor.opacity(0.24) : .clear,
        in: RoundedRectangle(cornerRadius: 5)
      )
      .contentShape(RoundedRectangle(cornerRadius: 5))
  }
}
```

Use it as the label for undo, redo, Bold, Italic, Underline, strikethrough, font, bullets, numbers, and delete. Preserve active accessibility values for B/I/U.

- [ ] **Step 6: Build the UI**

Run:

```bash
swift build
```

Expected: the full app builds successfully.

- [ ] **Step 7: Commit the app wiring and UI**

```bash
git add Sources/MenuBarNotesApp/AppState.swift Sources/MenuBarNotesApp/NotesPanel.swift Sources/MenuBarNotesApp/TrashView.swift Sources/MenuBarNotesApp/SettingsView.swift
git commit -m "feat: add recoverable deletion and appearance controls"
```

---

## Task 4: Verify the complete user experience

**Files:**
- Modify only if a verification failure identifies a scoped defect.

- [ ] **Step 1: Run the complete automated validation**

Run:

```bash
Scripts/validate-macos.sh
git diff --check
```

Expected: all Swift tests pass, the release build stays within the 15 MB budget, and there are no whitespace errors.

- [ ] **Step 2: Launch an isolated local UI harness**

Use a temporary Application Support root so test notes never touch the user’s real notes. Build and launch a WindowGroup harness using the production views.

- [ ] **Step 3: Verify deletion behavior live**

Check:

- context menu, configured shortcut, and toolbar trash all show `Cancel` and `Confirm`;
- Cancel leaves the note active;
- Confirm removes it from the tab strip immediately;
- Options → Trash opens the list;
- Restore returns the same note with its content and formatting.

- [ ] **Step 4: Verify customization live**

Check that Customize opens the Settings window and that changing theme, accent, font, text/background colors, opacity, width, and height updates the notes panel.

- [ ] **Step 5: Verify toolbar hit targets live**

Click near the edges of each visible 28 by 26 point button background. Confirm the intended action fires, and verify Bold/Italic/Underline active backgrounds remain visible until toggled off.

- [ ] **Step 6: Review the final diff**

Run:

```bash
git status --short
git diff --stat
git diff --check
```

Confirm every changed line traces to the approved deletion, Trash, customization, alignment, formatting-state, or toolbar-hit-area work.
