# Fleck Backlinks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable visible Markdown note links, keyboard-first link insertion, folder-aware navigation, and automatically derived backlinks while preserving Fleck's real `NSTextView` and current storage schema.

**Architecture:** A pure FleckCore parser recognizes only `[label](fleck://note/<uuid>)`; a cancellable actor derives incoming references from live note snapshots without persistence. The existing AppKit editor owns UTF-16 range editing and responder-chain commands, while SwiftUI owns the note picker, collapsed backlinks section, and calls the existing `activateNoteAndScope` navigation path.

**Tech Stack:** Swift 6, SwiftUI, AppKit/TextKit 1, Swift Testing, Swift Package Manager; no new dependencies.

## Global Constraints

- Base all work on `codex/fleck-backlinks-design` at accepted design commit `9d68b3a` unless the primary supplies a newer exact commit on the same stack.
- Read `docs/superpowers/specs/2026-08-08-fleck-backlinks-design.md` completely before editing.
- Preserve Fleck's production `ListAwareTextView`; do not add a fake editor or a second attributed-text source of truth.
- `Note.body` remains canonical visible Markdown and `richTextRTF` remains the existing optional parallel representation.
- Recognize only `[label](fleck://note/<uuid>)`; do not implement general Markdown rendering, mutable-title wiki links, external URLs, block links, aliases, transclusion, or a graph view.
- Do not add fields to `Note`, `Workspace`, preferences, manifests, recovery records, or Trash records.
- Do not persist a backlink index and do not add a dependency.
- Do not rewrite incoming links when a note is renamed, moved, trashed, restored, or permanently deleted.
- Search and the link picker are mutually exclusive; their underlay and Fleck shortcuts remain inert while either overlay is presented.
- Link styling follows the current accent, retains an underline, and must not overwrite authored attributes or create save/undo churn just by rendering.
- The backlinks section is below the editor, collapsed by default for panel lifetime, and does not animate.
- Use `activateNoteAndScope` for outgoing-link and backlink navigation so folder scope changes before selection.
- Never edit the leftmost personal to-do tab during packaged QA; use a disposable QA tab to its right.
- Do not modify `Package.swift`, `Package.resolved`, dependencies, generated files, AI work, plug-in work, iCloud, or onboarding.

---

## File Map

### Create

- `Sources/FleckCore/NoteLink.swift` — internal-link value, formatter, strict parser, label escaping, UTF-16 ranges, and bounded excerpt helper.
- `Sources/FleckCore/BacklinkIndex.swift` — incoming-reference values, deterministic index, and incremental cancellable `BacklinkIndexer` actor.
- `Sources/FleckApp/BacklinkController.swift` — MainActor generation gate over the core indexer.
- `Sources/FleckApp/NoteLinkPicker.swift` — picker controller, focus origin, and SwiftUI picker view using `WorkspaceSearchEngine`.
- `Sources/FleckApp/BacklinksView.swift` — compact collapsed disclosure and source rows.
- `Tests/FleckCoreTests/NoteLinkTests.swift` — parser/formatter/range/malformed-input coverage.
- `Tests/FleckCoreTests/BacklinkIndexTests.swift` — derived-index, cache, ordering, lifecycle, and cancellation coverage.
- `Tests/FleckAppTests/BacklinkControllerTests.swift` — generation/race/controller coverage.
- `Tests/FleckAppTests/NoteLinkEditorTests.swift` — real `ListAwareTextView` insertion, undo, styling, hit-testing, and responder-command coverage.
- `Tests/FleckAppTests/NotesPanelBacklinksTests.swift` — hosted production picker/backlinks/editor/folder/focus/accessibility behavior.
- `Tests/FleckCoreTests/BacklinkPerformanceTests.swift` — deterministic 10/100/1,000-note measurements and incremental-edit assertions.

### Modify

- `Sources/FleckApp/NativeRichTextEditor.swift` — narrow link callbacks, temporary TextKit presentation, `[[` trigger reporting, one-step replacement, Command-click, and responder/context actions.
- `Sources/FleckApp/NotesPanel.swift` — own controllers, overlay isolation, link validation/insertion/navigation, and backlinks placement.
- `Sources/FleckApp/FleckApp.swift` — add the responder-chain Editor menu commands only.
- `Tests/FleckAppTests/AppKitEditorTests.swift` — retain existing editor-lifetime and attribute/RTF guarantees when links are present.
- `Tests/FleckAppTests/WorkspaceSearchHostingTests.swift` — prove Search/link-picker mutual exclusion and shortcut isolation.

---

### Task 1: Strict Internal-Link Parser and Formatter

**Files:**
- Create: `Sources/FleckCore/NoteLink.swift`
- Create: `Tests/FleckCoreTests/NoteLinkTests.swift`

**Interfaces:**
- Produces: `NoteLink(targetNoteID:label:range:destinationRange:)` using UTF-16 `NSRange` values.
- Produces: `NoteLinkParser.links(in:)`, `NoteLinkParser.link(atUTF16Location:in:)`, and `NoteLinkParser.excerpt(around:in:limit:)`.
- Produces: `NoteLinkFormatter.markdown(label:targetNoteID:)` and `NoteLinkFormatter.escapeLabel(_:)`.
- Consumes: Foundation `UUID`, `NSString`, and URL components only.

- [ ] **Step 1: Write failing formatter and parser tests**

```swift
import Foundation
import FleckCore
import Testing

@Test func NoteLinkFormatterEscapesLabelAndUsesCanonicalUUID() {
  let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
  #expect(
    NoteLinkFormatter.markdown(label: #"Plan ] \\ launch"#, targetNoteID: id)
      == #"[Plan \] \\ launch](fleck://note/550E8400-E29B-41D4-A716-446655440000)"#
  )
}

@Test func NoteLinkParserReturnsExactUTF16RangesForUnicode() throws {
  let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
  let body = "🧠 before [Café](fleck://note/\(id.uuidString)) after"
  let link = try #require(NoteLinkParser.links(in: body).only)
  #expect(link.targetNoteID == id)
  #expect((body as NSString).substring(with: link.range).hasPrefix("[Café]"))
  #expect((body as NSString).substring(with: link.destinationRange) == "fleck://note/\(id.uuidString)")
}

@Test func NoteLinkParserRejectsBroadenedOrMalformedDestinations() {
  let invalid = [
    "[A](https://example.com)",
    "[A](fleck://other/550E8400-E29B-41D4-A716-446655440000)",
    "[A](fleck://note/not-a-uuid)",
    "[A](fleck://note/550E8400-E29B-41D4-A716-446655440000?x=1)",
    "[A](fleck://note/550E8400-E29B-41D4-A716-446655440000#x)",
    "[A](fleck://user@note/550E8400-E29B-41D4-A716-446655440000)",
  ]
  for body in invalid { #expect(NoteLinkParser.links(in: body).isEmpty) }
}
```

- [ ] **Step 2: Run the parser tests and retain red evidence**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter NoteLink
```

Expected: compile failure because `NoteLinkParser` and `NoteLinkFormatter` do not exist.

- [ ] **Step 3: Implement the minimal strict parser and formatter**

Implement the public values and signatures shown in Step 1, then use this exact scanner contract:

1. Work against `body as NSString` so every reported range is UTF-16 based.
2. Starting at offset zero, find the next literal `[` and then the next `]` whose immediately preceding backslash run has even length.
3. Require the next two UTF-16 code units to be `](` and find the next unescaped `)`; malformed candidates advance past the opening `[` and scanning continues.
4. Accept the destination only when it begins with the exact ASCII prefix `fleck://note/`, the remainder is exactly one 36-character UUID string accepted by `UUID(uuidString:)`, and it contains no slash, percent escape, query, fragment, credentials, port, whitespace, or trailing characters.
5. Decode the label by converting only `\\]` to `]` and `\\\\` to `\\`; preserve every other backslash literally. Record both the full token range and destination-only range.
6. Resume scanning at the end of the accepted token so multiple links are returned once, in document order.
7. `link(atUTF16Location:in:)` returns the first token containing the location and returns `nil` at the exclusive upper bound.
8. `excerpt(around:in:limit:)` clamps the requested range to the source, expands both ends to composed-character boundaries, converts all whitespace runs to one space, centers up to `limit` visible characters on the linked label, and adds `…` only on a truncated side.

Keep `NoteLinkFormatter` deterministic by escaping backslashes before closing brackets and emitting the UUID's canonical `uuidString`. Do not use a permissive general-Markdown regex or a URL parser that normalizes malformed input into an accepted destination.

- [ ] **Step 4: Add edge-case tests and make the focused suite green**

Add cases for multiple links, escaped `]`, nested-looking ordinary text, incomplete syntax, empty labels, duplicate targets, UTF-16 lookup at both range edges, and excerpts with emoji/ZWJ/newlines.

Run the Step 2 command. Expected: every `NoteLink` test passes.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/FleckCore/NoteLink.swift Tests/FleckCoreTests/NoteLinkTests.swift
git commit -m "feat: parse durable Fleck note links"
```

---

### Task 2: Deterministic Derived Backlink Index

**Files:**
- Create: `Sources/FleckCore/BacklinkIndex.swift`
- Create: `Tests/FleckCoreTests/BacklinkIndexTests.swift`

**Interfaces:**
- Consumes: `NoteLinkParser.links(in:)` from Task 1 and live `[Note]` snapshots.
- Produces: `BacklinkSource`, `BacklinkIndex.incoming(to:)`, and `BacklinkIndexer.build(liveNotes:) async`.
- Guarantees: one source row per source/target pair, reference count retained, first-match excerpt, modified-date/UUID ordering, self-links excluded from incoming UI, and parsed-source reuse only when ID/revision/body match.

- [ ] **Step 1: Write failing derived-index tests**

```swift
@Test func BacklinkIndexerGroupsSourcesAndOrdersThemDeterministically() async throws {
  let target = Note(id: UUID(), title: "Target")
  let older = Note(
    id: UUID(), title: "Older",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: target.id),
    modifiedAt: Date(timeIntervalSince1970: 10)
  )
  let newer = Note(
    id: UUID(), title: "Newer",
    body: [
      NoteLinkFormatter.markdown(label: "Target", targetNoteID: target.id),
      NoteLinkFormatter.markdown(label: "Again", targetNoteID: target.id),
    ].joined(separator: " and "),
    modifiedAt: Date(timeIntervalSince1970: 20)
  )
  let index = await BacklinkIndexer().build(liveNotes: [target, older, newer])
  #expect(index.incoming(to: target.id).map(\.sourceNoteID) == [newer.id, older.id])
  #expect(index.incoming(to: target.id).first?.referenceCount == 2)
}

@Test func BacklinkIndexerDoesNotPublishSelfLinksOrMissingSources() async {
  let targetID = UUID()
  let sourceID = UUID()
  let target = Note(
    id: targetID,
    title: "Target",
    body: NoteLinkFormatter.markdown(label: "Self", targetNoteID: targetID)
  )
  let source = Note(
    id: sourceID,
    title: "Source",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID)
  )
  let indexer = BacklinkIndexer()
  let first = await indexer.build(liveNotes: [target, source])
  #expect(first.incoming(to: targetID).map(\.sourceNoteID) == [sourceID])
  #expect(first.incoming(to: sourceID).isEmpty)
  let second = await indexer.build(liveNotes: [target])
  #expect(second.incoming(to: targetID).isEmpty)
}
```

- [ ] **Step 2: Run and retain red evidence**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter BacklinkIndex
```

Expected: compile failure because the index types do not exist.

- [ ] **Step 3: Implement values and the actor cache**

```swift
public struct BacklinkSource: Equatable, Identifiable, Sendable {
  public let sourceNoteID: UUID
  public let sourceDisplayTitle: String
  public let sourceFolderID: UUID?
  public let targetNoteID: UUID
  public let excerpt: String
  public let referenceCount: Int
  public let sourceModifiedAt: Date
  public var id: UUID { sourceNoteID }
}

public struct BacklinkIndex: Equatable, Sendable {
  private let incomingByTarget: [UUID: [BacklinkSource]]
  public init(incomingByTarget: [UUID: [BacklinkSource]] = [:]) {
    self.incomingByTarget = incomingByTarget
  }
  public func incoming(to targetNoteID: UUID) -> [BacklinkSource] {
    incomingByTarget[targetNoteID] ?? []
  }
}

```

Implement `BacklinkIndexer` as an actor with a `[UUID: CachedSource]` cache whose entry stores `revision`, `body`, and parsed links. Each `build(liveNotes:)` call must:

1. Create the live-ID set and remove cache keys absent from that set.
2. Iterate a deterministic `id.uuidString` ordering. Before each batch of 64 notes, call `Task.checkCancellation()` and `await Task.yield()`.
3. Reuse a cache entry only when both `revision` and `body` match; otherwise parse and replace it. The body comparison prevents stale reuse when callers fail to increment a revision.
4. Ignore self-links. Group remaining links by `(sourceNoteID, targetNoteID)`, retaining the first link's excerpt and counting all matching references.
5. Build each `BacklinkSource` from current note title, folder, modified date, and grouped data; never retain the whole `Note` in the index.
6. Sort every target's rows by `sourceModifiedAt` descending, then lowercase UUID string ascending, and return a complete immutable `BacklinkIndex` only after the final cancellation check.

Keep the accepted nonthrowing `build(liveNotes:) async -> BacklinkIndex` signature. Store `lastCompletedIndex` inside the actor; when cancellation is observed, stop immediately and return that prior complete value. Assign the newly built index to `lastCompletedIndex` only after grouping, sorting, and the final cancellation check. The controller's task/generation guard then suppresses the cancelled return value. Never publish a partially grouped result.

- [ ] **Step 4: Cover lifecycle and cancellation**

Add tests for rename without body rewrite, folder move, source removal/Trash filtering by caller-supplied live set, target removal/reappearance with the same UUID, duplicate links, equal-date UUID ordering, cache invalidation when body changes without revision change, and cancellation returning no stale partial publication.

Run Step 2. Expected: all index tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/FleckCore/BacklinkIndex.swift Tests/FleckCoreTests/BacklinkIndexTests.swift
git commit -m "feat: derive Fleck backlinks from live notes"
```

---

### Task 3: Generation-Safe App Controller

**Files:**
- Create: `Sources/FleckApp/BacklinkController.swift`
- Create: `Tests/FleckAppTests/BacklinkControllerTests.swift`

**Interfaces:**
- Consumes: `BacklinkIndexer.build(liveNotes:)` and live `[Note]` snapshots.
- Produces: MainActor `BacklinkController.index`, `refresh(liveNotes:)`, `incoming(to:)`, and `cancel()`.
- Later tasks rely on constructor injection of an async build operation for deterministic race tests.

- [ ] **Step 1: Write red race and publication tests**

```swift
@Test @MainActor func BacklinkControllerRejectsSupersededResults() async {
  let gate = BacklinkBuildGate()
  let controller = BacklinkController(build: gate.build)
  controller.refresh(liveNotes: [firstSnapshot])
  controller.refresh(liveNotes: [secondSnapshot])
  await gate.completeSecond(with: secondIndex)
  await gate.completeFirst(with: firstIndex)
  await Task.yield()
  #expect(controller.index == secondIndex)
}

@Test @MainActor func BacklinkControllerCancellationKeepsPublishedIndex() async {
  let gate = BacklinkBuildGate()
  let controller = BacklinkController(build: gate.build)
  controller.refresh(liveNotes: [publishedSnapshot])
  await gate.completeNext(with: publishedIndex)
  await gate.waitUntilPublished()
  #expect(controller.index == publishedIndex)
  controller.refresh(liveNotes: [blockedSnapshot])
  await gate.waitUntilBuildStarted()
  controller.cancel()
  await gate.completeNext(with: blockedIndex)
  await Task.yield()
  #expect(controller.index == publishedIndex)
}
```

- [ ] **Step 2: Run and retain red evidence**

```bash
swift test --disable-automatic-resolution --no-parallel --filter BacklinkController
```

Expected: compile failure because `BacklinkController` does not exist.

- [ ] **Step 3: Implement the minimal generation gate**

```swift
@MainActor
final class BacklinkController: ObservableObject {
  typealias Build = @Sendable ([Note]) async -> BacklinkIndex

  @Published private(set) var index = BacklinkIndex()
  private let build: Build
  private var task: Task<Void, Never>?
  private var generation: UInt64 = 0

  init(indexer: BacklinkIndexer = BacklinkIndexer()) {
    build = { notes in await indexer.build(liveNotes: notes) }
  }

  init(build: @escaping Build) { self.build = build }

  func refresh(liveNotes: [Note]) {
    task?.cancel()
    generation &+= 1
    let requestGeneration = generation
    let operation = build
    task = Task { [weak self] in
      let result = await operation(liveNotes)
      guard let self, !Task.isCancelled, generation == requestGeneration else { return }
      index = result
    }
  }

  func incoming(to noteID: UUID?) -> [BacklinkSource] {
    noteID.map(index.incoming(to:)) ?? []
  }

  func cancel() {
    task?.cancel()
    task = nil
    generation &+= 1
  }

  deinit { task?.cancel() }
}
```

- [ ] **Step 4: Make focused controller tests green and commit**

Run Step 2. Expected: all controller tests pass.

```bash
git add Sources/FleckApp/BacklinkController.swift Tests/FleckAppTests/BacklinkControllerTests.swift
git commit -m "feat: publish generation-safe backlinks"
```

---

### Task 4: Native Editor Link Editing and Navigation

**Files:**
- Modify: `Sources/FleckApp/NativeRichTextEditor.swift`
- Create: `Tests/FleckAppTests/NoteLinkEditorTests.swift`
- Modify: `Tests/FleckAppTests/AppKitEditorTests.swift`

**Interfaces:**
- Consumes: `NoteLinkParser`, `NoteLinkFormatter`, live target IDs, current accent, and the existing `EditorCommands.textView`.
- Produces on `EditorCommands`: `insertNoteLink(replacing:label:targetNoteID:) -> Bool`, `noteLinkAtSelection() -> NoteLink?`, and responder-chain selectors.
- Adds to `NativeRichTextEditor`: `liveNoteIDs`, `onRequestNoteLink`, `onOpenNoteLink`, and `onUnavailableNoteLink` callbacks.
- Adds to `ListAwareTextView`: parsed link ranges and closures only; it never owns workspace/navigation state.

- [ ] **Step 1: Write red production-editor tests**

```swift
@Test @MainActor func NoteLinkEditorInsertionIsOneUndoableRealTextViewEdit() throws {
  let fixture = makeRealEditorFixture(text: "Before [[ after")
  let trigger = NSRange(location: 7, length: 2)
  let target = UUID()
  #expect(fixture.commands.insertNoteLink(replacing: trigger, label: "Target", targetNoteID: target))
  #expect(fixture.textView.string == "Before \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) after")
  #expect(fixture.textView.undoManager?.canUndo == true)
  fixture.textView.undoManager?.undo()
  #expect(fixture.textView.string == "Before [[ after")
}
```

In the second red test, use the existing real-editor fixture to set attributed link text with a non-default font, foreground color, background highlight, paragraph/list metadata, typing attributes, a nontrivial selection, and an already-available undo operation. Capture the canonical string, serialized RTF, complete authored attributes, typing attributes, selection, undo availability, and `onChange` count. Refresh link presentation and change the accent. Assert every captured value is byte-for-byte or value-for-value unchanged, `onChange` did not fire, and the layout manager exposes the new temporary foreground plus underline attributes over only the parsed link range.

- [ ] **Step 2: Run and retain red evidence**

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'NoteLinkEditor|AppKitEditor.*Link'
```

Expected: compile failure because the editor interfaces do not exist.

- [ ] **Step 3: Add one-step replacement to `EditorCommands`**

```swift
@discardableResult
func insertNoteLink(
  replacing range: NSRange,
  label: String,
  targetNoteID: UUID
) -> Bool {
  guard let textView,
    range.location != NSNotFound,
    NSMaxRange(range) <= (textView.string as NSString).length
  else { return false }
  let replacement = NoteLinkFormatter.markdown(label: label, targetNoteID: targetNoteID)
  guard textView.shouldChangeText(in: range, replacementString: replacement) else { return false }
  textView.insertText(replacement, replacementRange: range)
  textView.didChangeText()
  textView.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
  return true
}
```

Use the real text system and verify whether `insertText` already sends the change notification; do not double-send `didChangeText`. The final implementation must pass the exact once-only `onChange` and undo tests.

- [ ] **Step 4: Detect `[[` once and add temporary presentation**

After `Coordinator.textDidChange` takes its binding snapshot, compute the current insertion point and detect an immediately preceding literal `[[` only when the text view has no marked text and the selection length is zero. Retain the last reported `(noteID, range, sourceRevision)` tuple so repeated SwiftUI updates cannot reopen the picker; clear the tuple when text or selection invalidates the trigger.

`refreshNoteLinks` must first remove only Fleck-owned temporary attributes from the layout manager across the previous presentation ranges, parse the current canonical string, and then add temporary foreground plus single-underline attributes across each accepted token. Use the current accent for live targets and a muted warning color for missing targets. It must not add `.link` to text storage, mutate RTF, call `didChangeText`, or register undo. Validity is `parent.liveNoteIDs.contains(link.targetNoteID)`.

- [ ] **Step 5: Add Command-click and responder/context commands**

Implement UTF-16 character lookup through the existing layout manager/text container. In `ListAwareTextView.mouseDown(with:)`, only intercept `.command` clicks that hit a parsed internal link; ordinary click selection continues to `super`.

Add responder methods:

```swift
@objc func requestNoteLinkFromMenu(_ sender: Any?) {
  onRequestNoteLink?(selectedRange())
}

@objc func openNoteLinkFromMenu(_ sender: Any?) {
  guard let link = noteLinkAtSelection() else { return }
  if liveNoteIDs.contains(link.targetNoteID) {
    onOpenNoteLink?(link.targetNoteID)
  } else {
    onUnavailableNoteLink?()
  }
}
```

Override `menu(for:)` to append `Link to Note…` and conditionally `Open Note Link` using these same selectors. Validate actions from the current selection and never store workspace objects in the menu.

- [ ] **Step 6: Make editor tests green and commit**

Cover trigger deduplication, marked-text/IME safety, trigger cancellation, replacement-range validation, exact one callback/save, undo/redo, Command-click valid/missing target, plain-click selection, context-menu validation, accent change, RTF round-trip, and hidden-editor detachment.

Run Step 2 plus:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppKitEditor
```

Expected: all selected tests pass.

```bash
git add Sources/FleckApp/NativeRichTextEditor.swift Tests/FleckAppTests/NoteLinkEditorTests.swift Tests/FleckAppTests/AppKitEditorTests.swift
git commit -m "feat: edit and open note links natively"
```

---

### Task 5: Picker, Backlinks Disclosure, Folder-Aware Integration, and Menus

**Files:**
- Create: `Sources/FleckApp/NoteLinkPicker.swift`
- Create: `Sources/FleckApp/BacklinksView.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Create: `Tests/FleckAppTests/NotesPanelBacklinksTests.swift`
- Modify: `Tests/FleckAppTests/WorkspaceSearchHostingTests.swift`

**Interfaces:**
- Consumes: `WorkspaceSearchEngine`, `BacklinkController`, `EditorCommands`, current live notes/folders/accent, and `activateNoteAndScope`.
- Produces: `NoteLinkPickerController.present(sourceNoteID:replacementRange:)`, `setQuery(_:notes:)`, `activateHighlighted(currentNoteIDs:onChoose:)`, `dismiss()`, and focus restoration.
- Produces: `BacklinksView(entries:foldersByID:isExpanded:onToggle:onOpen:)`.
- NotesPanel tests may inject picker/backlink controllers through source-compatible optional initializer parameters.

- [ ] **Step 1: Write red hosted picker and backlinks tests**

Add these three production-hosted tests with the existing AppKit/SwiftUI hosting helpers:

1. `NotesPanelDoubleBracketPickerInsertsAndDerivesBacklink`: host `NotesPanel` with real `EditorCommands`, a named-folder target, and injected deterministic picker/index controllers; type `[[` into `ListAwareTextView`, query and choose the target, then assert the body contains the exact visible token, RTF remains synchronized, the editor reports exactly one change/save generation, target activation changes folder scope before selection, and the target shows one incoming source.
2. `NotesPanelBacklinksDisclosurePreservesExactEditorState`: establish attributed content, a nontrivial selection, typing attributes, undo availability, first-responder focus, commands attachment, dictation availability, workspace value, and persistence generation. Toggle the production disclosure open and closed, then assert every captured value is unchanged and the same `NSTextView` instance remains attached.
3. `NotesPanelSearchAndLinkPickerAreMutuallyExclusiveAndInert`: present each overlay in turn, attempt to present the other, dispatch all five production `ShortcutMonitor` actions, and assert only one overlay is visible while query, focus origin, workspace, folder scope, selected note, and persistence generation remain exact.

- [ ] **Step 2: Run and retain red evidence**

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'NotesPanelBacklinks|WorkspaceSearchHosting.*LinkPicker'
```

Expected: compile failure because picker/view integration does not exist.

- [ ] **Step 3: Implement picker controller using the accepted search engine**

Implement a MainActor `NoteLinkPickerController: ObservableObject` with published read-only `isPresented`, `results`, and `highlightedNoteID`, a published writable `query`, and private(set) `sourceNoteID` plus `replacementRange`. Its injected search operation has the same `(String, [Note], Int) async -> [WorkspaceSearchResult]` shape as the existing controller.

Copy only the accepted behavior, not the state object: cancellation plus monotonically increasing generations; a 50-result limit; exact query/generation checks before publication; stable UUID highlighting; bounded Up/Down navigation; Return activation only when the highlighted UUID is still in the supplied live-note set; and captured responder restoration after dismissal. `present` captures source note, replacement range, window, and focus origin atomically. `dismiss` cancels work and clears the entire presentation tuple. Search activation changes notes, while picker activation inserts into the captured source editor, so the controller must not own `WorkspaceSearchController` or call `activateNoteAndScope`.

- [ ] **Step 4: Implement the compact SwiftUI surfaces**

`NoteLinkPickerView` uses an immediate search field, Up/Down/Return/Escape handling, title plus folder context, stable UUID highlight, and no animation.

`BacklinksView` renders:

```swift
DisclosureGroup(isExpanded: $isExpanded) {
  ForEach(entries) { entry in
    Button { onOpen(entry.sourceNoteID) } label: {
      BacklinkRow(
        title: entry.sourceDisplayTitle,
        folderName: entry.sourceFolderID.flatMap { foldersByID[$0] },
        excerpt: entry.excerpt,
        referenceCount: entry.referenceCount
      )
    }
  }
} label: {
  Text("Linked from \(entries.count)")
}
```

Use a plain button style, bounded height/scrolling when expanded, folder labels for disambiguation, and explicit accessibility labels/count/expanded state. Do not persist `isExpanded`.

- [ ] **Step 5: Wire `NotesPanel` without duplicating editor or navigation state**

Add optional injected controllers and local disclosure state. Define one computed `isBlockingOverlayPresented` value as the logical OR of `searchController.isPresented` and `noteLinkPickerController.isPresented`; do not duplicate that expression at call sites.

Use it for `.allowsHitTesting`, `.disabled`, `.accessibilityHidden`, and the existing `performShortcut` guard.

Pass the live note-ID set and three narrow callbacks into `NativeRichTextEditor`: request the picker with the triggering range plus current source ID; open through `activateNoteAndScope`; and show the existing nonfatal save-error presentation with the message `Note unavailable` for broken targets.

On picker choice, revalidate the source note is still selected/visible, target is live, replacement range remains valid in the same editor, and insertion succeeds. Dismiss, preserve the editor responder, and let the existing single `onChange` path persist.

Refresh `BacklinkController` from `appState.workspace.notes` on initial load and on relevant workspace changes. Place `BacklinksView` below the `NativeRichTextEditor` inside the same note-scoped editor `VStack`; expanding it must not change `.id(note.id)` or command ownership.

- [ ] **Step 6: Add responder-chain Editor menu commands**

In `FleckApp.swift`, add an Editor command menu whose buttons send the exact selectors to the current responder:

```swift
CommandMenu("Editor") {
  Button("Link to Note…") {
    NSApp.sendAction(#selector(ListAwareTextView.requestNoteLinkFromMenu(_:)), to: nil, from: nil)
  }
  Button("Open Note Link") {
    NSApp.sendAction(#selector(ListAwareTextView.openNoteLinkFromMenu(_:)), to: nil, from: nil)
  }
}
```

The real text view and normal responder-chain validation own availability. Do not introduce a global editor singleton.

- [ ] **Step 7: Make hosted tests green and commit**

Add stale/deleted/Trash/restore target behavior, cross-folder outgoing/backlink activation, label rename stability, one row per source with count, ordering/snippets/folder labels, compact 640×430 layout, Escape/focus restoration from body and title, VoiceOver labels, keyboard-only creation/opening, and exact editor lifetime.

Run Step 2 plus:

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'WorkspaceSearch|AppStateFolder|NotesPanelFolder|AppKitEditorFolder|TabDragReorderFolder|FolderNavigatorFocus|ShortcutMonitor'
```

Expected: all selected tests pass.

```bash
git add Sources/FleckApp/NoteLinkPicker.swift Sources/FleckApp/BacklinksView.swift Sources/FleckApp/NotesPanel.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/NotesPanelBacklinksTests.swift Tests/FleckAppTests/WorkspaceSearchHostingTests.swift
git commit -m "feat: present Fleck note links and backlinks"
```

---

### Task 6: Scale Evidence, Import/Export Contracts, and Release Verification

**Files:**
- Create: `Tests/FleckCoreTests/BacklinkPerformanceTests.swift`
- Modify: `Tests/FleckCoreTests/NoteTransferTests.swift`
- Modify: `TESTING.md` only if the new exact commands/results need a documented permanent gate.

**Interfaces:**
- Consumes all accepted Tasks 1–5 behavior.
- Produces deterministic scale fixtures and final verification evidence; no new product API.

- [ ] **Step 1: Add failing scale and transfer regressions**

```swift
@Test func BacklinkPerformanceBuildsDenseDeterministicFixtures() async {
  for count in [10, 100, 1_000] {
    let fixture = BacklinkScaleFixture.notes(count: count, linksPerNote: 4)
    let clock = ContinuousClock()
    let duration = await clock.measure {
      _ = await BacklinkIndexer().build(liveNotes: fixture)
    }
    print("BacklinkPerformance note_count=\(count) duration_ms=\(duration.milliseconds)")
  }
}

@Test func NoteTransferPreservesVisibleInternalLinkInMarkdownAndPlainText() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let note = Note(body: "Before \(token) after")
  #expect(String(decoding: NoteExport(note: note, format: .markdown).data, as: UTF8.self) == note.body)
  #expect(String(decoding: NoteExport(note: note, format: .plainText).data, as: UTF8.self) == note.body)
}
```

- [ ] **Step 2: Run focused final regressions**

```bash
swift test --disable-automatic-resolution --no-parallel --filter 'NoteLink|Backlink|WorkspaceSearch|AppStateFolder|NotesPanelFolder|AppKitEditorFolder|TabDragReorderFolder|FolderNavigatorFocus|ShortcutMonitor|NoteTransfer'
```

Expected: every selected test passes with no crash, race warning, or leaked monitor/window.

- [ ] **Step 3: Run the full suite once at the correction-ready head**

```bash
swift test --disable-automatic-resolution --no-parallel --quiet
```

Expected: all existing and new tests pass in all suites. Retain the exact count and exit status.

- [ ] **Step 4: Run repository and package gates**

```bash
git diff --check
git diff --exit-code 9d68b3a..HEAD -- Package.resolved
Scripts/validate-macos.sh
/usr/bin/codesign --verify --deep --strict --verbose=2 .build/Fleck.app
```

Expected: every command exits zero; the validator runs once only after the complete implementation is correction-ready; the bundle is valid on disk and satisfies its designated requirement; the dependency lock is unchanged.

- [ ] **Step 5: Perform exact packaged-app QA safely**

Use the exact `.build/Fleck.app`. If another Fleck instance with the same bundle identity is active, stop rather than touching shared note data. Otherwise, use only a disposable QA tab to the right of the personal leftmost tab and verify:

1. `[[` opens instantly, filters notes, and inserts visible Markdown.
2. Undo/redo is one step and formatting/selection remain exact.
3. Command-click and Editor/context-menu actions open the correct note and folder.
4. `Linked from N` expands/collapses without editor recreation.
5. Rename, move, Trash, restore, broken target, relaunch, and Markdown export/import follow the spec.
6. Accent, Full Keyboard Access, VoiceOver labels, and 640×430 compact layout are correct.

Record every unverified physical boundary honestly; never infer it from tests or source.

- [ ] **Step 6: Commit verification additions**

```bash
git add Tests/FleckCoreTests/BacklinkPerformanceTests.swift Tests/FleckCoreTests/NoteTransferTests.swift TESTING.md
git commit -m "test: verify Fleck backlink durability and scale"
```

Omit `TESTING.md` from `git add` when no documentation change was necessary.

- [ ] **Step 7: Return the structured implementation handoff**

Report exact base/head, commits, changed files, red evidence, focused/full counts, performance observations, validator/build/signing output, packaged QA, `Package.resolved` identity, clean status, zero unmerged entries, absent `MERGE_HEAD`, judgment calls, and remaining gaps. Do not push, open a PR, merge, rebase, or start Plug-ins until the primary explicitly authorizes the next boundary.

---

## Plan Self-Review Result

- Every accepted spec requirement maps to Tasks 1–6.
- The parser, index, controller, editor bridge, SwiftUI surfaces, and final validation have explicit file ownership and interfaces.
- Search, Folder scope, editor lifetime, RTF/attributes/undo, persistence, accessibility, scale, Trash/restore, import/export, and packaged QA have production-path coverage.
- No note schema, persisted index, dependency, hidden-link representation, general Markdown renderer, or unrelated roadmap feature is introduced.
- Every nontrivial algorithm has explicit acceptance rules and production-path tests; no implementation decision is deferred to a later phase.
