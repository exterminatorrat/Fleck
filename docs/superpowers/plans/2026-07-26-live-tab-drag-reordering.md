# Live Tab Drag Reordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorder note tabs continuously as a dragged tab crosses neighboring tab targets, with existing native layout motion and persistence.

**Architecture:** Replace the current drop-only tab handlers with native `onDrag` plus a small `DropDelegate` that invokes the existing `AppState.moveNote(_:to:)` path from `dropEntered`. Keep one dragged-note identifier and one panel-private drag type in `NotesPanel`; resolve the current order at hover time, reuse the tab strip’s existing order animation, and keep the workspace’s bounded move operation.

**Tech Stack:** Swift 6, SwiftUI drag and drop, AppKit `NSItemProvider`, Swift Testing.

## Global Constraints

- Persisted note order remains owned by `Workspace.notes`.
- Reuse `AppState.moveNote(_:to:)` and its debounced save; do not add a preview array or second ordering model.
- Reorder immediately when the drag enters a neighboring tab.
- Use the native `.move` drop operation.
- Reuse `NotesPanel`’s existing `AppMotion.spatial` order animation (`0.16` seconds normally, no spatial animation under Reduce Motion).
- Keep context-menu “Move Left” and “Move Right” actions unchanged.
- Do not select a note merely because it is dragged.
- Unknown, missing, same-tab, and same-index moves are no-ops.
- A cancelled drag may leave the latest live order intact but cannot duplicate, delete, or block later drags.
- Each panel accepts only its own process-private drag type, so cancelled state cannot be activated by external text or another app window.
- Do not add edge auto-scroll, custom drag previews, cross-window dragging, new pinned-tab rules, or dependencies.

## File Structure

- Modify `Sources/MenuBarNotesApp/NotesPanel.swift`: dragged-note state, pure destination resolver, native drop delegate, and tab-strip drag/drop wiring.
- Create `Tests/MenuBarNotesAppTests/TabDragReorderTests.swift`: destination resolution and invalid/no-op coverage.
- Modify `Tests/MenuBarNotesCoreTests/WorkspaceTests.swift`: characterize repeated live moves through the existing workspace order model.

---

### Task 1: Continuous Tab Reordering

**Files:**
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift:8-20, 154-230`
- Create: `Tests/MenuBarNotesAppTests/TabDragReorderTests.swift`
- Modify: `Tests/MenuBarNotesCoreTests/WorkspaceTests.swift:65-80`

**Interfaces:**
- Consumes: `AppState.moveNote(_:to:)`, `Workspace.moveNote(id:to:)`, `NotesPanel.motion.spatial`.
- Produces: `TabDragReorder.destinationIndex(draggedID:over:in:)`, `TabDragReorder.performLiveMove`, a panel-private drag type, and `TabDropDelegate`.

- [ ] **Step 1: Add the failing destination-resolution tests**

Create `Tests/MenuBarNotesAppTests/TabDragReorderTests.swift`:

```swift
import Foundation
import Testing

@testable import MenuBarNotesApp

@Test func liveTabDragResolvesLeftAndRightDestinations() {
  let first = UUID()
  let second = UUID()
  let third = UUID()
  let ids = [first, second, third]

  #expect(
    TabDragReorder.destinationIndex(
      draggedID: first,
      over: third,
      in: ids
    ) == 2
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: third,
      over: first,
      in: ids
    ) == 0
  )
}

@Test func liveTabDragIgnoresInvalidAndSameTabTargets() {
  let first = UUID()
  let second = UUID()
  let missing = UUID()
  let ids = [first, second]

  #expect(
    TabDragReorder.destinationIndex(
      draggedID: nil,
      over: second,
      in: ids
    ) == nil
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: first,
      over: first,
      in: ids
    ) == nil
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: missing,
      over: second,
      in: ids
    ) == nil
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: first,
      over: missing,
      in: ids
    ) == nil
  )
}
```

- [ ] **Step 2: Run the resolver tests and verify RED**

Run:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/menubar-notes-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/menubar-notes-clang-module-cache \
swift test --filter liveTabDrag
```

Expected: compilation fails because `TabDragReorder` does not exist.

- [ ] **Step 3: Add the destination resolver, private provider, and drag state**

Near the top of `NotesPanel.swift`, inside the macOS compilation block and outside `NotesPanel`, add:

```swift
enum TabDragReorder {
  static let dropOperation: DropOperation = .move

  static func makeContentType(id: UUID = UUID()) -> UTType {
    let token = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return UTType(exportedAs: "com.menubarnotes.tabdrag.session\(token)")
  }

  static func destinationIndex(
    draggedID: UUID?,
    over destinationID: UUID,
    in noteIDs: [UUID]
  ) -> Int? {
    guard let draggedID,
      draggedID != destinationID,
      noteIDs.contains(draggedID),
      let destination = noteIDs.firstIndex(of: destinationID)
    else { return nil }
    return destination
  }

  static func itemProvider(for noteID: UUID, contentType: UTType) -> NSItemProvider {
    let provider = NSItemProvider()
    let data = Data(noteID.uuidString.utf8)
    provider.registerDataRepresentation(
      forTypeIdentifier: contentType.identifier,
      visibility: .ownProcess
    ) { completion in
      completion(data, nil)
      return nil
    }
    return provider
  }

  @discardableResult
  static func performLiveMove(
    draggedID: UUID?,
    over destinationID: UUID,
    currentNoteIDs: () -> [UUID],
    move: (UUID, Int) -> Void
  ) -> Bool {
    guard let draggedID,
      let destination = destinationIndex(
        draggedID: draggedID,
        over: destinationID,
        in: currentNoteIDs()
      )
    else { return false }
    move(draggedID, destination)
    return true
  }
}
```

Add this view-local state to `NotesPanel`:

```swift
@State private var draggedNoteID: UUID?
@State private var tabDragContentType = TabDragReorder.makeContentType()
```

- [ ] **Step 4: Add the native hover drop delegate**

Below `NotesPanel` and above the next file-level view type, add:

```swift
private struct TabDropDelegate: DropDelegate {
  let destinationID: UUID
  let currentNoteIDs: () -> [UUID]
  @Binding var draggedNoteID: UUID?
  let move: (UUID, Int) -> Void

  func dropEntered(info: DropInfo) {
    TabDragReorder.performLiveMove(
      draggedID: draggedNoteID,
      over: destinationID,
      currentNoteIDs: currentNoteIDs,
      move: move
    )
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: TabDragReorder.dropOperation)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggedNoteID = nil
    return true
  }
}
```

The delegate does not own animation or persistence. The existing tab-strip `.animation(motion.spatial, value: appState.workspace.notes.map(\.id))` animates each live array mutation, while `AppState.moveNote(_:to:)` continues to debounce persistence.

- [ ] **Step 5: Replace drop-only wiring with live hover wiring**

Replace:

```swift
.draggable(note.id.uuidString)
.dropDestination(for: String.self) { identifiers, _ in
  guard let identifier = identifiers.first,
    let id = UUID(uuidString: identifier),
    let destination = appState.workspace.notes.firstIndex(where: { $0.id == note.id })
  else { return false }
  appState.moveNote(id, to: destination)
  return true
}
```

with:

```swift
.onDrag {
  draggedNoteID = note.id
  return TabDragReorder.itemProvider(for: note.id, contentType: tabDragContentType)
}
.onDrop(
  of: [tabDragContentType],
  delegate: TabDropDelegate(
    destinationID: note.id,
    currentNoteIDs: { appState.workspace.notes.map(\.id) },
    draggedNoteID: $draggedNoteID,
    move: appState.moveNote
  )
)
```

Keep the existing tab-strip order animation and context menu unchanged.

- [ ] **Step 6: Add repeated live-move characterization**

Add to `WorkspaceTests.swift`:

```swift
@Test func repeatedLiveTabMovesPreserveEveryNoteExactlyOnce() {
  var workspace = Workspace()
  let first = workspace.addNote()
  let second = workspace.addNote()
  let third = workspace.addNote()

  workspace.moveNote(id: first, to: 1)
  #expect(workspace.notes.map(\.id) == [second, first, third])

  workspace.moveNote(id: first, to: 2)
  #expect(workspace.notes.map(\.id) == [second, third, first])
  #expect(Set(workspace.notes.map(\.id)) == Set([first, second, third]))
}
```

- [ ] **Step 7: Run focused tests and verify GREEN**

Run:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/menubar-notes-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/menubar-notes-clang-module-cache \
swift test --filter liveTabDrag

SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/menubar-notes-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/menubar-notes-clang-module-cache \
swift test --filter repeatedLiveTabMovesPreserveEveryNoteExactlyOnce
```

Expected: all five focused tests pass.

- [ ] **Step 8: Run the complete macOS validation**

Run:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/menubar-notes-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/menubar-notes-clang-module-cache \
bash Scripts/validate-macos.sh
```

Expected: all Swift tests pass, debug and release builds succeed, and the release executable remains below 15 MB.

- [ ] **Step 9: Commit**

```bash
git add Sources/MenuBarNotesApp/NotesPanel.swift \
  Tests/MenuBarNotesAppTests/TabDragReorderTests.swift \
  Tests/MenuBarNotesCoreTests/WorkspaceTests.swift \
  docs/superpowers/plans/2026-07-26-live-tab-drag-reordering.md
git commit -m "feat: reorder tabs continuously while dragging"
```
