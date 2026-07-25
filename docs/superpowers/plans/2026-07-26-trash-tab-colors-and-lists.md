# Trash, Tab Colors, and Lists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix one-click Trash dismissal, add fluid Settings navigation and persistent per-note tab colors, and provide Word-style nested lists plus clickable Apple Notes-style checklists.

**Architecture:** Keep presentation state owned by `NotesPanel`, extend the existing optional note metadata for tab colors, and isolate list parsing and string transformations in a pure app-internal `EditorListEngine`. `ListAwareTextView` continues to own AppKit ranges, attributes, mouse hit testing, and undo integration.

**Tech Stack:** Swift 6, SwiftUI, AppKit/NSTextView, Swift Testing, macOS 14

## Global Constraints

- Keep the existing native SwiftUI/AppKit editor; do not introduce a block-editor dependency.
- Keep Markdown bodies readable and RTF sidecars responsible for visual text attributes.
- Preserve compatibility with notes whose metadata has no tab color.
- Use four spaces per indentation level.
- Use `• → ◦ → ▪` and `1. → a. → i.` as automatic nesting hierarchies.
- Keep Settings movement at 160 ms ease-out with no bounce.
- Respect Reduce Motion by removing spatial movement while retaining color and opacity feedback.
- Do not animate typing, text selection, panel dimensions, or form layout.

---

### Task 1: Trash Dismissal and Settings Selector

**Files:**
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Modify: `Sources/MenuBarNotesApp/TrashView.swift`
- Modify: `Sources/MenuBarNotesApp/SettingsView.swift`

**Interfaces:**
- `TrashView.init(onDone: @escaping () -> Void)`
- `SettingsSectionSelector` remains private to `SettingsView`.

- [ ] **Step 1: Replace environment dismissal with parent-owned state**

Change the sheet content and Trash initializer to:

```swift
.sheet(isPresented: $isShowingTrash) {
  TrashView(onDone: { isShowingTrash = false })
    .environmentObject(appState)
}
```

```swift
let onDone: () -> Void
```

```swift
Button("Done", action: onDone)
  .keyboardShortcut(.defaultAction)
```

Run: `swift build`

Expected: the app target builds and `TrashView` has no `DismissAction`.

- [ ] **Step 2: Replace the labeled Picker with a matched-geometry selector**

Add a namespace and a private selector:

```swift
@Namespace private var selectedSectionHighlight

private var sectionSelector: some View {
  HStack(spacing: 4) {
    ForEach(SettingsSection.allCases) { section in
      let isSelected = section == selectedSection
      Button {
        withAnimation(motion.spatial) {
          selectedSection = section
        }
      } label: {
        Text(section.rawValue)
          .font(.callout.weight(.medium))
          .foregroundStyle(isSelected ? Color.white : Color.primary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 7)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor)
                .matchedGeometryEffect(
                  id: "settings-section",
                  in: selectedSectionHighlight
                )
            }
          }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
  }
  .padding(3)
  .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
  .padding()
}
```

Replace the segmented Picker with `sectionSelector`. Keep the existing form opacity transition scoped to the form container.

Run: `swift build`

Expected: build passes; the source no longer contains `Picker("Settings section"`.

- [ ] **Step 3: Commit the navigation increment**

```bash
git add Sources/MenuBarNotesApp/NotesPanel.swift \
  Sources/MenuBarNotesApp/TrashView.swift \
  Sources/MenuBarNotesApp/SettingsView.swift
git commit -m "fix: stabilize trash and settings navigation"
```

---

### Task 2: Persist Per-Note Tab Colors

**Files:**
- Modify: `Sources/MenuBarNotesCore/Note.swift`
- Modify: `Sources/MenuBarNotesCore/Workspace.swift`
- Modify: `Sources/MenuBarNotesCore/LocalStore.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Modify: `Tests/MenuBarNotesCoreTests/WorkspaceTests.swift`
- Modify: `Tests/MenuBarNotesCoreTests/LocalStoreTests.swift`

**Interfaces:**
- `Note.tabColorHex: String?`
- `Workspace.setTabColor(id: UUID, hex: String?, now: Date = Date())`
- `AppState.setSelectedTabColor(_ hex: String?)`

- [ ] **Step 1: Write failing workspace and persistence tests**

```swift
@Test func workspaceSetsAndClearsTabColor() {
  var workspace = Workspace()
  let id = workspace.addNote()

  workspace.setTabColor(id: id, hex: "#0A84FF")
  #expect(workspace.notes.first(where: { $0.id == id })?.tabColorHex == "#0A84FF")

  workspace.setTabColor(id: id, hex: nil)
  #expect(workspace.notes.first(where: { $0.id == id })?.tabColorHex == nil)
}
```

```swift
@Test func tabColorRoundTripsThroughTrashAndRestore() async throws {
  let root = temporaryStoreURL()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let deleted = Note(title: "Blue", tabColorHex: "#0A84FF")
  let remaining = Note(title: "Remaining")
  let workspace = Workspace(notes: [remaining], selectedNoteID: remaining.id)

  try await store.save(
    workspace: workspace,
    preferences: .init(),
    trashedNotes: [deleted]
  )
  let trashed = try #require(try await store.loadTrash().first)
  #expect(trashed.note.tabColorHex == "#0A84FF")

  let restored = try await store.restore(trashed, into: workspace, preferences: .init())
  #expect(restored.notes.first(where: { $0.id == deleted.id })?.tabColorHex == "#0A84FF")
}
```

Run: `swift test --filter workspaceSetsAndClearsTabColor`

Expected: FAIL because `tabColorHex` and `setTabColor` do not exist.

- [ ] **Step 2: Add optional metadata with backward-compatible decoding**

Add `tabColorHex` to `Note`:

```swift
public var tabColorHex: String?

public init(
  id: UUID = UUID(),
  title: String = "Untitled",
  body: String = "",
  richTextRTF: Data? = nil,
  tabColorHex: String? = nil,
  createdAt: Date = Date(),
  modifiedAt: Date = Date(),
  isPinned: Bool = false
) {
  self.id = id
  self.title = title
  self.body = body
  self.richTextRTF = richTextRTF
  self.tabColorHex = tabColorHex
  self.createdAt = createdAt
  self.modifiedAt = modifiedAt
  self.isPinned = isPinned
}
```

Add the workspace mutation:

```swift
public mutating func setTabColor(id: UUID, hex: String?, now: Date = Date()) {
  guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
  notes[index].tabColorHex = hex
  notes[index].modifiedAt = now
}
```

Add optional `tabColorHex` to `LocalStore.Metadata` and `TrashMetadata`, write it in `saveActive` and `archiveInTrash`, and pass it into both `Note` reconstruction sites.

Run: `swift test --filter workspaceSetsAndClearsTabColor`

Expected: PASS.

Run: `swift test --filter tabColorRoundTripsThroughTrashAndRestore`

Expected: PASS.

- [ ] **Step 3: Connect AppState**

```swift
func setSelectedTabColor(_ hex: String?) {
  guard let id = workspace.selectedNoteID else { return }
  workspace.setTabColor(id: id, hex: hex)
  scheduleSave()
}
```

Run: `swift test`

Expected: all existing and new tests pass.

- [ ] **Step 4: Commit persistence**

```bash
git add Sources/MenuBarNotesCore/Note.swift \
  Sources/MenuBarNotesCore/Workspace.swift \
  Sources/MenuBarNotesCore/LocalStore.swift \
  Sources/MenuBarNotesApp/AppState.swift \
  Tests/MenuBarNotesCoreTests/WorkspaceTests.swift \
  Tests/MenuBarNotesCoreTests/LocalStoreTests.swift
git commit -m "feat: persist per-note tab colors"
```

---

### Task 3: Tab Color Interface

**Files:**
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Test: `swift build`

**Interfaces:**
- Consumes `Note.tabColorHex` and `AppState.setSelectedTabColor(_:)`.
- Adds private `TabColorOption` values for None plus eight named colors.

- [ ] **Step 1: Add the stable palette**

```swift
private struct TabColorOption: Identifiable {
  let name: String
  let hex: String?
  var id: String { name }

  static let all = [
    TabColorOption(name: "None", hex: nil),
    TabColorOption(name: "Red", hex: "#FF5A5F"),
    TabColorOption(name: "Orange", hex: "#FF9F0A"),
    TabColorOption(name: "Yellow", hex: "#FFD60A"),
    TabColorOption(name: "Green", hex: "#30D158"),
    TabColorOption(name: "Blue", hex: "#0A84FF"),
    TabColorOption(name: "Purple", hex: "#BF5AF2"),
    TabColorOption(name: "Pink", hex: "#FF375F"),
    TabColorOption(name: "Gray", hex: "#8E8E93"),
  ]
}
```

- [ ] **Step 2: Tint tabs and add the context submenu**

Use the note color when present and the app accent for selection otherwise:

```swift
private func tabColor(for note: Note) -> Color {
  Color(hex: note.tabColorHex ?? appState.preferences.accentHex)
}
```

Render a subtle unselected capsule only for custom colors, and render the stronger matched-geometry capsule for the selected note.

Add to the context menu:

```swift
Menu("Tab Color", systemImage: "paintpalette") {
  ForEach(TabColorOption.all) { option in
    Button {
      appState.select(note.id)
      appState.setSelectedTabColor(option.hex)
    } label: {
      if note.tabColorHex == option.hex {
        Label(option.name, systemImage: "checkmark")
      } else {
        Text(option.name)
      }
    }
  }
}
```

Run: `swift build`

Expected: the app builds and every tab context menu exposes the palette.

- [ ] **Step 3: Commit the tab interface**

```bash
git add Sources/MenuBarNotesApp/NotesPanel.swift
git commit -m "feat: add note tab color palette"
```

---

### Task 4: Pure List Engine

**Files:**
- Create: `Sources/MenuBarNotesApp/EditorListEngine.swift`
- Create: `Tests/MenuBarNotesAppTests/EditorListEngineTests.swift`

**Interfaces:**
- `EditorListFamily`: `.bullets`, `.numbers`
- `EditorBulletStyle`: `.disc`, `.circle`, `.square`, `.dash`
- `EditorNumberStyle`: `.decimal`, `.alphabetic`, `.roman`
- `EditorListStyle`: `.bullet(EditorBulletStyle)`, `.number(EditorNumberStyle)`, `.checklist`
- `EditorListEngine.parse(_:)`
- `EditorListEngine.toggle(style:in:)`
- `EditorListEngine.continuation(after:)`
- `EditorListEngine.indent(_:removing:)`
- `EditorListEngine.normalizeTypedPrefix(_:)`
- `EditorListEngine.toggleChecklist(_:)`

- [ ] **Step 1: Write failing marker and hierarchy tests**

```swift
@Test func automaticStylesFollowDepth() {
  #expect(EditorListEngine.automaticBullet(depth: 0) == .disc)
  #expect(EditorListEngine.automaticBullet(depth: 1) == .circle)
  #expect(EditorListEngine.automaticBullet(depth: 2) == .square)
  #expect(EditorListEngine.automaticNumber(depth: 0) == .decimal)
  #expect(EditorListEngine.automaticNumber(depth: 1) == .alphabetic)
  #expect(EditorListEngine.automaticNumber(depth: 2) == .roman)
}

@Test func parserRecognizesSupportedMarkers() {
  #expect(EditorListEngine.parse("• Item")?.style == .bullet(.disc))
  #expect(EditorListEngine.parse("    ◦ Child")?.depth == 1)
  #expect(EditorListEngine.parse("2. Item")?.style == .number(.decimal))
  #expect(EditorListEngine.parse("    b. Child")?.style == .number(.alphabetic))
  #expect(EditorListEngine.parse("        ii. Child")?.style == .number(.roman))
  #expect(EditorListEngine.parse("○ Task")?.style == .checklist)
}
```

Run: `swift test --filter automaticStylesFollowDepth`

Expected: FAIL because `EditorListEngine` does not exist.

- [ ] **Step 2: Implement marker models, parsing, and formatting**

Create `EditorListFamily`, the three style enums, and a parsed-line value containing `depth`, `style`, `content`, and checklist completion. Implement:

```swift
static func automaticBullet(depth: Int) -> EditorBulletStyle {
  [.disc, .circle, .square][max(0, depth) % 3]
}

static func automaticNumber(depth: Int) -> EditorNumberStyle {
  [.decimal, .alphabetic, .roman][max(0, depth) % 3]
}
```

Parsing accepts the new markers plus legacy `-`, `*`, `+`, decimal `1)`, and decimal `1.` forms. Malformed markers return `nil`.

Run: `swift test --filter automaticStylesFollowDepth`

Expected: PASS.

Run: `swift test --filter parserRecognizesSupportedMarkers`

Expected: PASS.

- [ ] **Step 3: Write failing transformation tests**

```swift
@Test func togglingListsReplacesOrRemovesMarkers() {
  #expect(
    EditorListEngine.toggle(style: .bullet(.square), in: "One\nTwo")
      == "▪ One\n▪ Two"
  )
  #expect(
    EditorListEngine.toggle(style: .bullet(.square), in: "▪ One\n▪ Two")
      == "One\nTwo"
  )
  #expect(
    EditorListEngine.toggle(style: .number(.alphabetic), in: "• One\n• Two")
      == "a. One\nb. Two"
  )
}

@Test func returnAndIndentUseListHierarchy() {
  #expect(EditorListEngine.continuation(after: "1. Parent") == "2. ")
  #expect(EditorListEngine.continuation(after: "● Done") == "○ ")
  #expect(EditorListEngine.indent("• Child", removing: false) == "    ◦ Child")
  #expect(EditorListEngine.indent("    a. Child", removing: true) == "1. Child")
}

@Test func typedPrefixesAndChecklistsNormalize() {
  #expect(EditorListEngine.normalizeTypedPrefix("- ") == "• ")
  #expect(EditorListEngine.normalizeTypedPrefix("1) ") == "1. ")
  #expect(EditorListEngine.normalizeTypedPrefix("[ ] ") == "○ ")
  #expect(EditorListEngine.toggleChecklist("○ Task") == "● Task")
  #expect(EditorListEngine.toggleChecklist("● Task") == "○ Task")
}
```

Run: `swift test --filter togglingListsReplacesOrRemovesMarkers`

Expected: FAIL because transformation methods do not exist.

- [ ] **Step 4: Implement transformations**

Implement transformations as pure line/string operations:

- preserve four-space indentation;
- strip any recognized marker before applying a new style;
- number non-empty selected lines from one;
- leave empty lines empty;
- use the current marker for continuation, except completed checklists continue as incomplete;
- exit an empty item by returning no continuation;
- change bullet/number markers to the automatic target-depth style during indent/outdent;
- normalize only an entire recognized prefix;
- toggle only checklist markers.

Run: `swift test`

Expected: all list-engine tests pass.

- [ ] **Step 5: Commit the pure engine**

```bash
git add Sources/MenuBarNotesApp/EditorListEngine.swift \
  Tests/MenuBarNotesAppTests/EditorListEngineTests.swift
git commit -m "feat: add hierarchical list engine"
```

---

### Task 5: AppKit List and Checklist Integration

**Files:**
- Modify: `Sources/MenuBarNotesApp/NativeRichTextEditor.swift`
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Modify: `Tests/MenuBarNotesAppTests/EditorListEngineTests.swift`

**Interfaces:**
- `EditorCommands.applyList(_ style: EditorListStyle)`
- `EditorCommands.applyAutomaticList(_ family: EditorListFamily)`
- `ListAwareTextView.toggleList(_:)`
- `ListAwareTextView.toggleAutomaticList(_:)`

- [ ] **Step 1: Replace the old two-case list model**

Remove the old `.bullets`/`.numbers` enum. Route command calls through the list engine and use a shared text-replacement helper that calls `shouldChangeText(in:replacementString:)`, updates selection, and calls `didChangeText()`.

Run: `swift build`

Expected: build fails only at the two old toolbar call sites, proving the command API changed.

- [ ] **Step 2: Add Bullets, Numbering, and Checklist controls**

Replace the two list buttons with:

- a Bullets menu whose primary action calls `applyAutomaticList(.bullets)` and whose items apply `.disc`, `.circle`, `.square`, or `.dash`;
- a Numbering menu whose primary action calls `applyAutomaticList(.numbers)` and whose items apply `.decimal`, `.alphabetic`, or `.roman`;
- a Checklist button that applies `.checklist`.

Every label continues to use `ToolbarIconLabel`, `.buttonStyle(CrispToolbarButtonStyle)`, and explicit accessibility labels.

Run: `swift build`

Expected: build passes.

- [ ] **Step 3: Integrate Return, Tab, Shift-Tab, and typed prefixes**

Update `ListAwareTextView`:

- `insertNewline` uses `EditorListEngine.continuation(after:)`; an empty item removes its marker and exits;
- `insertTab` and `insertBacktab` transform the selected line range with `EditorListEngine.indent`;
- `insertText` normalizes a recognized typed prefix only when `automaticLists` is enabled.

Run: `swift test --filter EditorListEngineTests`

Expected: all list behavior tests pass.

- [ ] **Step 4: Add clickable checklist completion**

Override `mouseDown(with:)` to map the click to a character index. If the click lands on the `○` or `●` marker of that paragraph:

1. replace the marker through the standard text replacement helper;
2. apply or remove `.strikethroughStyle` across the paragraph content range;
3. leave the marker unstruck;
4. notify the delegate and return without moving the caret.

All other clicks call `super.mouseDown(with:)`.

Run: `swift build`

Expected: build passes.

- [ ] **Step 5: Run the complete suite and commit integration**

Run: `swift test`

Expected: all core and app tests pass.

```bash
git add Sources/MenuBarNotesApp/NativeRichTextEditor.swift \
  Sources/MenuBarNotesApp/NotesPanel.swift \
  Tests/MenuBarNotesAppTests/EditorListEngineTests.swift
git commit -m "feat: add rich list and checklist editing"
```

---

### Task 6: Full Validation

**Files:**
- Modify only files already named if validation exposes a scoped defect.

**Interfaces:**
- Consumes completed Tasks 1–5.

- [ ] **Step 1: Run repository validation**

Run: `bash Scripts/validate-macos.sh`

Expected: all tests pass, debug and release builds succeed, and the release executable remains below 15 MB.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 2: Inspect the final diff against the specification**

Run:

```bash
git diff origin/main...HEAD -- \
  Sources Tests Package.swift \
  docs/superpowers/specs/2026-07-26-trash-tab-colors-and-lists-design.md
```

Expected: every production change maps to Trash dismissal, Settings navigation, tab colors, lists, or their tests.

- [ ] **Step 3: Perform manual macOS checks**

Launch `.build/release/MenuBarNotes` and verify:

- Done closes Trash once in the transient and pinned windows.
- The Settings label is absent and the blue capsule moves fluidly.
- Tab colors persist after relaunch and Trash restoration.
- Bullet and numbered menus apply every style.
- Return, Tab, and Shift-Tab follow the approved hierarchy.
- Checklist markers toggle strikethrough without moving the caret.
- Undo, typing, and existing rich-text formatting remain responsive.
- Reduce Motion removes selector and tab movement.
