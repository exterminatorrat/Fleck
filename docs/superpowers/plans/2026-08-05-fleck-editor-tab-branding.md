# Fleck Editor, Tabs, and Branding Implementation Plan

**Goal:** Deliver native tab reorder and overflow behavior, selection-aware rich-text formatting, and the canonical menu-bar-only Fleck identity without changing the workspace or editor architecture.

**Architecture:** `NotesPanel` remains the sole production tab, header, toolbar, and editor surface. `EditorCommands` continues to read and mutate the live `NSTextView`; `Workspace.moveNote(id:to:)` and `AppState.moveNote(_:to:)` remain the sole order and persistence path. The app bundle, rather than SwiftPM resources, receives the canonical mark during the existing assembly script.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSTextView`/`NSTextStorage`, Swift Testing, SwiftPM, macOS shell tooling, macOS 14 deployment target, Xcode 26/macOS 26 SDK.

**Approved design:** [Fleck Editor, Tabs, and Branding Design](../specs/2026-08-05-fleck-editor-tab-branding-design.md)

> **For agentic workers:** Execute one checked task at a time, with a red-green-refactor cycle and the stated commit checkpoint. Production implementation is through the designated Terra lane; the parent Sol session reruns verification and obtains a fresh Sol review.

## Global Constraints

- Retain macOS 14 as the deployment target and compile with Xcode 26/macOS 26 SDK compatibility; use no deployment-newer API without a macOS 14 guard.
- Preserve `NotesPanel`, `NativeRichTextEditor`, `NSTextView.typingAttributes`, and `NSTextStorage` as the production formatting surface and source of truth.
- Preserve `Workspace.moveNote(id:to:)`, `AppState.moveNote(_:to:)`, UUIDs, body, RTF sidecars, pin state, selection, agent permissions, and existing debounced saves. Do not change `Workspace`, `AppState`, `LocalStore`, or their storage schemas.
- A nonempty formatting selection is a document mutation: it uses the existing `NSTextView` undo manager, calls `didChangeText()` exactly once, refreshes state, and follows the existing RTF/onChange persistence route. A zero-length caret formatting command changes only `typingAttributes`, refreshes state, and does not call `didChangeText()` or create a body/RTF persistence revision before text is inserted.
- Reuse `TabDragReorder`, own-process `NSItemProvider`, and `TabDropDelegate` first. A local horizontal `DragGesture` needs a separate approved correction specification after recorded packaged-app evidence proves native drag/drop fails. Do not add a collection view.
- Do not add dependencies, a state store, a formatting model, a migration, automatic sorting, a left chevron, multiple tab rows, compressed-tab redesign, a font preset menu, a stepper, a silent packaged-asset fallback, or logging of note text, selections, colors, or font choices.
- Preserve Enhanced Local as non-shippable and leave dictation, onboarding, launch-at-login, Agent Connector privacy, signing identity, and website mark pixels unchanged.
- `Package.swift` is not an implementation target: ordinary builds exclude `Sources/FleckApp/Resources`, while `Scripts/build-fleck-app.sh` assembles the app bundle directly. Change it only if a recorded build failure proves the direct canonical-PNG copy cannot make the packaged resource available; stop for a correction specification before doing so.
- For every live check, use disposable tabs and notes to the right of the user's leftmost personal tab. Never alter that leftmost tab.

## Future File Map

| File | Responsibility in this implementation |
| --- | --- |
| `Sources/FleckApp/NotesPanel.swift` | Native drag-start selection, deterministic overflow presentation, tab fade/chevron, colored header mark, and formatting toolbar controls. |
| `Sources/FleckApp/NativeRichTextEditor.swift` | Explicit current-format properties and narrow `NSTextView` family, size, foreground, and background mutations. |
| `Sources/FleckApp/FleckApp.swift` | Bundled-mark loading and template menu-bar label. |
| `Sources/FleckApp/Info.plist` | `LSUIElement` bundle contract. |
| `Scripts/build-fleck-app.sh` | Copy `website/public/fleck-mark.png` into the staged app resources before signing. |
| `Scripts/validate-macos.sh` | Reject a missing bundled mark or incorrect `LSUIElement` value. |
| `Tests/FleckAppTests/TabDragReorderTests.swift` | Deterministic selection/reorder and overflow-decision coverage. |
| `Tests/FleckAppTests/AppKitEditorTests.swift` | `EditorCommands` state, selected-mutation undo/redo and one-notification coverage, caret inheritance without premature persistence, and RTF regression coverage. |
| `Tests/FleckAppTests/FleckBrandAuditTests.swift` | Source, plist, packaging-script, and stable-signing contract coverage. |
| `TESTING.md` | Packaged-app manual checklist and release-evidence boundary. |

No copied resource belongs in `Sources/FleckApp/Resources` for the ordinary app path. The build script copies the canonical website PNG to the staged `.app`, so no Package.swift resource declaration is planned.

---

### Task 1: Select the native drag source and retain live reorder semantics

**Files:**

- Modify: `Tests/FleckAppTests/TabDragReorderTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`

**Interfaces:**

- Consume: `TabDragReorder.performLiveMove(draggedID:over:currentNoteIDs:move:)`, `AppState.select(_:)`, and `AppState.moveNote(_:to:)`.
- Produce: `TabDragReorder.beginDrag(noteID:contentType:select:) -> NSItemProvider` as the one tab-drag entry point; it selects `noteID` before passing the supplied panel-private `UTType` to the existing own-process provider.

- [ ] **Step 1: Write failing deterministic tests.** In `TabDragReorderTests.swift`, add `beginningTabDragSelectsTheDraggedIdentityBeforeProvidingIt` with a local selected-ID recorder and a generated panel-private `UTType`; assert the callback receives the dragged UUID exactly once and the returned provider conforms only to that supplied type. Add `liveTabDragRetainsIdentityAndCurrentOrderAcrossLeftAndRightHovers`; use three UUIDs plus per-ID metadata strings, perform first-over-second then first-over-third and third-over-second moves, and assert the final UUID sequence, metadata-by-ID mapping, and one selected UUID are unchanged except for ordering.

- [ ] **Step 2: Establish red evidence.** Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'beginningTabDragSelectsTheDraggedIdentityBeforeProvidingIt|liveTabDragRetainsIdentityAndCurrentOrderAcrossLeftAndRightHovers'
  ```

  Expected red result: compilation fails because `beginDrag(noteID:contentType:select:)` is absent, or the new selection assertion fails because the current `.onDrag` only assigns `draggedNoteID`.

- [ ] **Step 3: Make the smallest native-path change.** Add `beginDrag(noteID:contentType:select:)` to `TabDragReorder`; call `select(noteID)` before `itemProvider(for:contentType:)` using the passed `contentType`. In the existing `.onDrag` closure, retain `draggedNoteID = note.id`, then call the new method with `tabDragContentType` and `appState.select`. Do not introduce a static/global drag type or touch `TabDropDelegate`, `Workspace`, `AppState.moveNote`, the per-panel native content type, or the current live-hover move operation.

- [ ] **Step 4: Establish green and refactor evidence.** Run the same focused command, then:

  ```sh
  swift test --disable-automatic-resolution --filter 'liveTabDrag'
  ```

  Expected green result: all existing and new live-tab-drag tests pass; moves remain `.move`, current-order resolution still works, and no test observes duplicate or substituted IDs. Refactor only duplicated local recorder setup in the test file; retain the public behavior unchanged.

- [ ] **Step 5: Commit checkpoint.** Inspect `git diff --check` and `git diff --name-only`; only the two files above may be present. Commit:

  ```sh
  git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/TabDragReorderTests.swift
  git commit -m "feat: select tabs on native drag"
  ```

### Task 2: Add a testable trailing-overflow decision and presentation

**Files:**

- Modify: `Tests/FleckAppTests/TabDragReorderTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`

**Interfaces:**

- Consume: the existing horizontal `ScrollView` tab strip and its coordinate-space measurements.
- Produce: `TabOverflowPresentation.hasHiddenTrailingContent(contentTrailingEdge:visibleTrailingEdge:) -> Bool`, a narrow file-local pure helper; true only when content extends beyond the visible trailing edge by a small layout epsilon.

- [ ] **Step 1: Write failing decision tests.** Add `tabOverflowShowsOnlyWhenTrailingContentExceedsVisibleEdge`. Assert false for equal edges and content trailing inside the visible edge; assert true when content trailing exceeds the visible edge by more than the helper's epsilon. Add `tabOverflowDoesNotInferHiddenTrailingContentFromLeadingOffset`, asserting that a leading scroll offset alone does not request a right affordance.

- [ ] **Step 2: Establish red evidence.** Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'tabOverflowShowsOnlyWhenTrailingContentExceedsVisibleEdge|tabOverflowDoesNotInferHiddenTrailingContentFromLeadingOffset'
  ```

  Expected red result: compilation fails because `TabOverflowPresentation` does not exist.

- [ ] **Step 3: Implement the measured single-strip presentation.** Add the pure helper at file scope in `NotesPanel.swift`. Give the existing `ScrollView` a named coordinate space; report its visible trailing edge and the `HStack` content trailing edge with preferences or geometry. Overlay a narrow trailing fade and a compact right-chevron outside the scrollable tab content only when the helper returns true. Give the chevron the label `Reveal hidden tabs`, place it in reserved trailing layout so it cannot cover a tab, and scroll the existing `ScrollViewReader` proxy to the final note ID when activated. Do not add a left affordance, another row, compression rules, or automatic drag scrolling.

- [ ] **Step 4: Establish green and source-contract evidence.** Run the focused overflow command, then:

  ```sh
  swift test --disable-automatic-resolution --filter 'liveTabDrag|tabOverflow'
  ```

  Expected green result: both pure boundary tests and all existing tab-drag tests pass. Inspect the SwiftUI diff to confirm the fade and chevron are conditionally driven by trailing visibility and the chevron has no overlay that covers tab labels. Refactor geometry preference names only if the behavior stays identical.

- [ ] **Step 5: Commit checkpoint.** Verify only `NotesPanel.swift` and `TabDragReorderTests.swift` changed, then commit:

  ```sh
  git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/TabDragReorderTests.swift
  git commit -m "feat: reveal overflowed tabs"
  ```

### Task 3: Make current font family and size state explicit in `EditorCommands`

**Files:**

- Modify: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Modify: `Sources/FleckApp/NativeRichTextEditor.swift`

**Interfaces:**

- Consume: the existing `EditorCommands.textView`, `typingAttributes`, `textStorage`, `refreshFormattingState()`, and `didChangeText()` route.
- Produce: non-generic published command properties `currentFontFamily`, `isFontFamilyMixed`, `currentFontSize`, and `isFontSizeMixed`; `applyFontSize(_:) -> Bool` accepts only finite values in `1...512` points.

- [ ] **Step 1: Write failing AppKit tests.** Add `editorCommandsReportsCaretAndUniformFontState`, which gives a text view a known font at the caret and then a uniform selection, and asserts the current family and point size are reported without mixed flags. Add `editorCommandsReportsMixedFamilyAndSizeWithoutInventingAValue`, which uses two adjacent font runs and asserts both current values are absent and both mixed flags are true. Add `editorCommandsAppliesValidSizeAtCaretAndSelection`, which applies 18 points at a caret then 22 points to a selected range and asserts the caret changes only typing attributes with no delegate/binding notification, while the selected range changes each run and emits exactly one notification. Add `editorCommandsCaretFontFormattingDoesNotNotifyUntilTyping`, which applies family and size at a caret, asserts body/RTF snapshots and notification count remain unchanged, inserts one character, then asserts the inserted character inherits the requested family and size and the normal text edit notifies once. Add `editorCommandsRejectsInvalidSizesWithoutChangingAttributes`, which tries 0, 513, NaN, and infinity and asserts false return, unchanged font attributes, unchanged text, and no notification.

- [ ] **Step 2: Establish red evidence.** Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'editorCommandsReportsCaretAndUniformFontState|editorCommandsReportsMixedFamilyAndSizeWithoutInventingAValue|editorCommandsAppliesValidSizeAtCaretAndSelection|editorCommandsCaretFontFormattingDoesNotNotifyUntilTyping|editorCommandsRejectsInvalidSizesWithoutChangingAttributes'
  ```

  Expected red result: tests cannot find the new state properties or `applyFontSize(_:)`.

- [ ] **Step 3: Implement narrow font inspection and mutation.** Extend `refreshFormattingState()` to inspect every effective attribute run in a nonempty selected range and distinguish one uniform family/size from a mixed range; at a zero-length range inspect only `typingAttributes`. Extend the existing run-by-run `.font` mutation path with size replacement that preserves each run's family and font traits. For a selected range, capture the attributed selection, register the narrow inverse/redo operation with the existing `NSTextView.undoManager`, mutate only `.font`, call `didChangeText()` exactly once, and refresh state. At a caret, replace only the `.font` value in `typingAttributes` and refresh state without calling `didChangeText()`. Validate size before reading or mutating any attribute. Do not replace the entire attribute dictionary or use a no-op notification as an undo mechanism.

- [ ] **Step 4: Establish green, preservation, and refactor evidence.** Add `fontFamilyAndSizePreserveTraitsUnderlineForegroundParagraphAndListAttributes`, using a bold-italic font, underline, foreground color, paragraph style, and existing list metadata across the selected range; assert all but the requested family/size remain equal after both commands. Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'editorCommands|fontFamilyAndSizePreserveTraitsUnderlineForegroundParagraphAndListAttributes'
  ```

  Expected green result: all named formatting tests pass; selected font mutations notify exactly once and participate in the existing undo manager, while caret tests observe no notification until typed text is inserted. Refactor the shared run enumeration only inside `EditorCommands`; do not create a general formatting model.

- [ ] **Step 5: Commit checkpoint.** Verify the changed-file set, then commit:

  ```sh
  git add Sources/FleckApp/NativeRichTextEditor.swift Tests/FleckAppTests/AppKitEditorTests.swift
  git commit -m "feat: expose editor font state"
  ```

### Task 4: Apply foreground and highlight attributes without weakening rich-text persistence

**Files:**

- Modify: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Modify: `Sources/FleckApp/NativeRichTextEditor.swift`

**Interfaces:**

- Consume: the font-state refresh behavior from Task 3 and `NativeRichTextEditor.Coordinator.textDidChange(_:)` RTF snapshot path.
- Produce: `currentForegroundColor`, `isForegroundColorMixed`, `currentBackgroundColor`, `isBackgroundColorMixed`, `applyForegroundColor(_:)`, and `applyBackgroundColor(_:)`; `nil` removes only the corresponding explicit color key.

- [ ] **Step 1: Write failing AppKit tests.** Add `editorCommandsAddsAndRemovesForegroundColorForSelectionAndCaret` and `editorCommandsAddsAndRemovesHighlightForSelectionAndCaret`. Each test must assert selection writes use `.foregroundColor` or `.backgroundColor`, call the delegate/binding route exactly once, and `nil` removes rather than writes a replacement color; caret writes alter only `typingAttributes`, make no persistence notification, and are verified by subsequently typed text inheriting the requested attribute. Add `editorCommandsReportsMixedColorsWithoutCheckmarkValue`, using two colors across a selection and asserting the respective mixed flag is true and current color absent. Add `editorFormattingCommandsUndoAndRedoSelectedAttributes`: from one shared attributed-selection fixture, independently apply selected family, size, foreground, and background operations; after each one, assert one undo restores the original attributed selection without changing its string, redo restores that operation's requested attribute, and the selected document mutation notifies through the existing delegate/binding route exactly once. Keep `editorFormattingCommandsNotifyAndRoundTripRTF`, but make it apply selected document mutations before RTF serialization; assert its notification and RTF checks do not depend on caret-only typing attributes.

- [ ] **Step 2: Establish red evidence.** Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'editorCommandsAddsAndRemovesForegroundColorForSelectionAndCaret|editorCommandsAddsAndRemovesHighlightForSelectionAndCaret|editorCommandsReportsMixedColorsWithoutCheckmarkValue|editorFormattingCommandsUndoAndRedoSelectedAttributes|editorFormattingCommandsNotifyAndRoundTripRTF'
  ```

  Expected red result: the color command APIs and state properties are absent, so the tests do not compile.

- [ ] **Step 3: Implement attribute-specific commands.** Enumerate only the selected ranges for nonempty selections and add or remove exactly `.foregroundColor` or `.backgroundColor`. For each selected document mutation, capture the attributed selection and register its one-step inverse/redo with the existing `NSTextView.undoManager`, mutate only that key, call `didChangeText()` exactly once, and refresh state. At a caret, add or remove only that key in `typingAttributes` and refresh state without calling `didChangeText()` or creating a persistence/body revision; the next typed character remains the proof of the requested inheritance. Update current-state inspection to require a uniform effective color across a selection. Do not write `AppPreferences.editorTextHex` or `editorBackgroundHex`, replace a paragraph style, or emit logs.

- [ ] **Step 4: Establish green and regression evidence.** Run the focused color command above, then:

  ```sh
  swift test --disable-automatic-resolution --filter 'editorCommands|editorFormattingCommandsUndoAndRedoSelectedAttributes|editorFormattingCommandsNotifyAndRoundTripRTF|listFormattingPreservesInlineAttributes|completedChecklistRoundTripsWithoutRenderingArtifacts'
  ```

  Expected green result: the new tests and all prior native-editor/list tests pass, including selected-range one-undo/redo, exactly-one notification, caret inheritance without premature persistence, and RTF restoration assertions. Refactor only duplicated attribute-key mutation inside `EditorCommands`, keeping separate explicit foreground and background methods.

- [ ] **Step 5: Commit checkpoint.** Verify only the AppKit editor source and tests changed, then commit:

  ```sh
  git add Sources/FleckApp/NativeRichTextEditor.swift Tests/FleckAppTests/AppKitEditorTests.swift
  git commit -m "feat: add rich text colors"
  ```

### Task 5: Bind the formatting state to accessible native SwiftUI controls

**Files:**

- Modify: `Tests/FleckAppTests/AppKitEditorTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`

**Interfaces:**

- Consume: the explicit `EditorCommands` properties and commands from Tasks 3 and 4, plus `TabColorOption.all` as the established Fleck color palette.
- Produce: a family `Menu` with uniform-family checkmarks, one numeric-only size field, Font Color and Highlight menus, and accessible values for uniform and mixed state.

- [ ] **Step 1: Write failing source-contract tests.** Add `formattingBarUsesCurrentCommandStateAndOnlyNumericSizeInput`. Read `NotesPanel.swift` from the package root and assert it references `currentFontFamily`, `isFontFamilyMixed`, `currentFontSize`, `isFontSizeMixed`, `applyFontSize`, and an accessibility value for mixed size. Assert it does not contain a size `Stepper` or a font-size preset menu. Add `formattingBarUsesFleckPaletteForForegroundAndHighlight`. Assert the Font Color menu includes `Automatic`, Highlight includes `No Highlight`, both iterate `TabColorOption.all` excluding its `None` item, and their checkmarks use the matching command state.

- [ ] **Step 2: Establish red evidence.** Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'formattingBarUsesCurrentCommandStateAndOnlyNumericSizeInput|formattingBarUsesFleckPaletteForForegroundAndHighlight'
  ```

  Expected red result: the current formatting bar has only an unchecked font-family menu and none of the size/color control contracts.

- [ ] **Step 3: Implement the toolbar surface.** Replace the font-family menu labels with a label that appends a checkmark only when `currentFontFamily == family` and `isFontFamilyMixed` is false. Add one narrow editable numeric `TextField` bound to view-local text initialized from a uniform current size; submit on Return and focus loss. Parse a finite numeric value, call `applyFontSize`, and restore the displayed uniform current value after an invalid submission. For mixed size, present an empty numeric field with the accessibility value `Mixed`; it remains editable and accepts only a valid numeric submission. Add compact Font Color and Highlight menus from `TabColorOption.all` except `None`, with `Automatic` and `No Highlight` actions respectively. Give every control an explicit label, value, and mixed-state announcement.

- [ ] **Step 4: Establish green and focused regression evidence.** Run the focused source-contract command, then:

  ```sh
  swift test --disable-automatic-resolution --filter 'editorCommands|formattingBar'
  ```

  Expected green result: toolbar source contracts and command behavior tests pass. Inspect the diff to confirm it has one numeric field, no preset list or stepper, no duplicate editor state, and no use of global editor color preferences for per-selection commands. Refactor only repeated SwiftUI menu-label layout.

- [ ] **Step 5: Commit checkpoint.** Verify only `NotesPanel.swift` and `AppKitEditorTests.swift` changed, then commit:

  ```sh
  git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift
  git commit -m "feat: add editor formatting controls"
  ```

### Task 6: Package and render the canonical mark while making Fleck menu-bar-only

**Files:**

- Modify: `Tests/FleckAppTests/FleckBrandAuditTests.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/Info.plist`
- Modify: `Scripts/build-fleck-app.sh`
- Modify: `Scripts/validate-macos.sh`
- Modify: `TESTING.md`

**Interfaces:**

- Consume: `website/public/fleck-mark.png`, the existing app-bundle staging path, current `MenuBarExtra`, current `NotesPanel.header`, and stable `com.harryjin.fleck` signing checks.
- Produce: a module-local `FleckMark` loader in `FleckApp.swift` that resolves the bundled `fleck-mark.png`; its menu-bar image is template-rendered and its header image is non-template. A bare `swift run` development fallback may be explicit, but a packaged bundle receives no silent fallback.

- [ ] **Step 1: Write failing brand/package tests.** Extend `canonicalBundleAndVisibleIdentityAreFleck` to assert `Info.plist` has boolean `LSUIElement == true`, `FleckApp.swift` loads `fleck-mark.png` and marks the menu-bar image template, and `NotesPanel.swift` renders the same mark as non-template beside the textual Fleck header title. Extend `packagedDevelopmentBuildUsesStableFleckCodeIdentity` to assert the build script copies `website/public/fleck-mark.png` to `Contents/Resources/fleck-mark.png` before codesigning, and the validation script checks both the packaged resource and `LSUIElement` while retaining its identifier and designated-requirement checks.

- [ ] **Step 2: Establish red evidence.** Run:

  ```sh
  swift test --disable-automatic-resolution --filter 'canonicalBundleAndVisibleIdentityAreFleck|packagedDevelopmentBuildUsesStableFleckCodeIdentity'
  ```

  Expected red result: the plist has no `LSUIElement`, the source still uses the system `note.text` menu-bar image, and the build/validation scripts have no canonical-mark checks.

- [ ] **Step 3: Implement the single asset path and reachability-preserving bundle behavior.** In `FleckApp.swift`, replace the system-image `MenuBarExtra` label with the bundled-mark template label while retaining the existing popover content. In `NotesPanel.header`, show the same bundled image with `isTemplate = false` next to the existing `Fleck` title. In `Info.plist`, add `LSUIElement` as a boolean true. In `build-fleck-app.sh`, create `Contents/Resources`, require the canonical website PNG, and copy it to `Contents/Resources/fleck-mark.png` before app signing. In `validate-macos.sh`, fail if the resource is absent/empty or differs from the canonical PNG, and fail unless `LSUIElement` reads as true. Preserve existing helper/app signing order and identifier checks. In `TESTING.md`, add the exact packaged manual checklist from Step 4 below; do not claim a SwiftPM process proves Dock, Command-Tab, or resource behavior.

- [ ] **Step 4: Establish green package evidence.** Run the focused brand tests, then:

  ```sh
  Scripts/build-fleck-app.sh
  test -s .build/Fleck.app/Contents/Resources/fleck-mark.png
  cmp -s website/public/fleck-mark.png .build/Fleck.app/Contents/Resources/fleck-mark.png
  /usr/bin/plutil -extract LSUIElement raw -o - .build/Fleck.app/Contents/Info.plist
  ```

  Expected green result: focused brand tests pass, the resource exists and byte-matches the canonical PNG, and `plutil` prints `true`. Refactor only image-loading duplication; leave `Package.swift` unchanged because direct bundle assembly supplies the resource.

- [ ] **Step 5: Commit checkpoint.** Verify the seven files listed for this task are the only changes, then commit:

  ```sh
  git add Sources/FleckApp/FleckApp.swift Sources/FleckApp/NotesPanel.swift Sources/FleckApp/Info.plist Scripts/build-fleck-app.sh Scripts/validate-macos.sh Tests/FleckAppTests/FleckBrandAuditTests.swift TESTING.md
  git commit -m "feat: package Fleck brand mark"
  ```

### Task 7: Run the complete automated gate and record the live packaged-app evidence

**Files:**

- Modify: `TESTING.md` only if Task 6 did not already record every checklist item exactly once.
- Test: the focused test files from Tasks 1 through 6, the full package suite, package validator, hosted CI, and a disposable packaged-app session.

**Interfaces:**

- Consume: the completed native tab, formatting, branding, packaging, and signing contracts.
- Produce: an evidence record identifying the source commit, macOS/Xcode/Swift versions, automated command outcomes, hosted CI run, and live manual results without note content, selection details, color values, or credentials.

- [ ] **Step 1: Run the focused suite before the full gate.** Execute:

  ```sh
  swift test --disable-automatic-resolution --filter 'liveTabDrag|tabOverflow|editorCommands|fontFamilyAndSize|formattingBar|canonicalBundleAndVisibleIdentityAreFleck|packagedDevelopmentBuildUsesStableFleckCodeIdentity'
  ```

  Expected green result: every targeted test from this plan passes. A failure is red evidence for the named contract and must be corrected in the owning task before continuing.

- [ ] **Step 2: Run full deterministic and package gates.** Execute:

  ```sh
  swift test --disable-automatic-resolution --no-parallel
  Scripts/validate-macos.sh
  git diff --check
  ```

  Expected green result: the full ordinary suite succeeds, the validator reports its development-signed `.build/Fleck.app` success after resource, plist, signing, helper, and smoke checks, and `git diff --check` has no output. Refactor only after focused and full gates remain green.

- [ ] **Step 3: Record the hosted CI boundary.** Push the implementation branch, wait for the existing hosted CI workflow to finish green, and record the workflow URL, commit SHA, workflow name, and result. A local package pass is not a substitute for hosted CI.

- [ ] **Step 4: Run and record the exact live packaged-app checklist.** Launch only the packaged app:

  ```sh
  /usr/bin/open -n .build/Fleck.app
  ```

  On disposable tabs to the right of the leftmost personal tab, verify and record pass/fail for all of the following:

  1. Drag a selected disposable tab over its immediate left neighbor and immediate right neighbor; neighboring tabs move live before release, the selected highlight follows, and final order persists after relaunch.
  2. Create enough disposable tabs to hide trailing tabs; the right fade and `Reveal hidden tabs` chevron appear only then, the chevron reveals the trailing tab without obscuring the visible final tab, and neither control remains once the trailing edge is visible.
  3. At a caret and a uniform selection, confirm the font menu checks the actual family; across a mixed-family selection it checks none. Enter a valid numeric size with Return and with focus loss; verify 1 and 512 apply. Enter 0, 513, empty input, and non-numeric input; verify the displayed current size restores and document content does not change.
  4. Apply Font Color, `Automatic`, Highlight, and `No Highlight` to a selection and a caret; type new text after caret commands; relaunch and verify rich text retains the intended attributes while Markdown/plain export remains text-only.
  5. Confirm the menu bar uses the monochrome template mark and the `NotesPanel` header uses the colored mark next to `Fleck`.
  6. Confirm Fleck is absent from Dock and Command-Tab while the menu bar, pinned notes window, Settings, onboarding entry, launch-at-login setting, dictation capsule, and Agent Connector remain reachable through their existing paths.
  7. With VoiceOver and Full Keyboard Access, confirm names, values, mixed-state announcements, and field focus for the chevron and formatting controls. With Reduce Motion enabled, confirm reordering remains immediate.

  Do not include note text, screenshots of private notes, credentials, selection contents, or agent information in the report.

- [ ] **Step 5: Commit checkpoint.** If Task 6 already updated `TESTING.md`, this task creates no content commit. Otherwise, after the checklist text is added, commit only that documentation update:

  ```sh
  git add TESTING.md
  git commit -m "docs: document editor branding verification"
  ```

## Parent Verification, Review, and Delivery Gates

The Terra implementation lane must stop after Task 7 and provide the parent Sol session: changed-file list, commits, focused/full/validator command output, selected-range one-notification and undo/redo evidence, caret inheritance-without-premature-persistence evidence, selected-mutation RTF evidence, packaged-resource and plist evidence, hosted CI URL/result, manual checklist results, and every unavailable or failed boundary. It must not declare the feature ready, open a pull request, merge, or alter GitHub settings.

The parent Sol session must inspect the actual parent diff, confirm the changed files match this plan and constraints, rerun the focused tests, `swift test --disable-automatic-resolution --no-parallel`, `Scripts/validate-macos.sh`, `git diff --check`, packaging resource checks, final status, `git ls-files -u`, and `MERGE_HEAD`. It must specifically confirm that selected formatting mutations each notify once and undo/redo through the existing text-view undo manager, while caret-only commands create neither an immediate body/RTF persistence revision nor a notification before the next typed character. It must independently compare the evidence against the approved design and must treat the live packaged-app/Dock/Command-Tab results as manual evidence, not build inference.

After parent verification, spawn a fresh Sol reviewer with the final diff and command evidence. The reviewer verdict must be `ship` before release/PR readiness. If the verdict is `fix-first` or `rethink`, the parent returns a corrected bounded specification to the same Terra implementation lane, repeats parent verification, and obtains a new fresh Sol review. The parent must not silently repair a Terra patch.

GitHub gates follow repository policy: current-user authorization is required before pushing, opening/updating a pull request, or any merge. Before merge, require relevant local checks, green hosted CI, and the final fresh Sol `ship` verdict. Merge through GitHub only after explicit authorization. Then fetch and fast-forward local `main` to `origin/main`; verify clean `git status --short --branch`, zero unmerged entries from `git ls-files -u`, no `.git/MERGE_HEAD`, and the expected ahead/behind state. Do not push, open a PR, merge, or modify GitHub settings as part of executing this plan without that authorization.
