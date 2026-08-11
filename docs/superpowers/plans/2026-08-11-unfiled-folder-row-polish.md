# Unfiled Width and Folder Selection Polish Implementation Plan

**Goal:** Give expanded Unfiled intrinsic width, enlarge its disclosure hit target, and make selected/focused folder styling consistent without changing navigator behavior.

**Architecture:** Modify only the existing `FolderNavigator` implementation in `NotesPanel.swift`. Reuse the shared `rowLabel` pill for explicit focus presentation and the existing AppKit UI test file for regression coverage. Native SwiftUI remains the only UI implementation.

## Task 1: Capture the three regressions

**Files:**

- Modify `Tests/FleckAppTests/AppKitEditorTests.swift`

1. Update the compact-Unfiled source contract to require `.fixedSize(horizontal: true, vertical: false)` on the whole root row in both states while the folder strip retains its flexible scrolling width.
2. Add a focused contract requiring a disclosure hit rectangle of at least 28 by 28 points with a rectangular content shape and unchanged accessibility labels.
3. Extend the hosted/shared-row presentation regression to require native focus suppression on both selectable folder buttons and an explicit outline only for focused, unselected rows.
4. Run:

   ```bash
   swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
   ```

   Expected: the new assertions fail for the three reported behaviors while the suite builds and unrelated tests remain green. Record the exact failures before editing production code.

## Task 2: Apply the smallest native SwiftUI correction

**Files:**

- Modify `Sources/FleckApp/NotesPanel.swift`

1. Change only the Unfiled root row width modifier so expanded and compact states both use intrinsic horizontal width.
2. Enlarge the existing disclosure label frame to at least 28 by 28 points and add a rectangular content shape; retain its plain style, accessibility, hover/focus behavior, and current animation path.
3. Apply native focus-effect suppression equally to Unfiled and named-folder buttons.
4. Pass the current row-focus state into `rowLabel` and add one subtle rounded-rectangle accent stroke only for `isFocused && !isSelected`. Keep selection/drop fills unchanged.
5. Do not refactor adjacent navigator, drag/drop, Trash, animation, or persistence code.
6. Rerun the AppKit filter and require exit 0. Then run:

   ```bash
   swift test --disable-automatic-resolution --no-parallel --filter TabDragReorderTests
   ```

   Expected: exit 0 with no regression to tab/folder interactions.

## Task 3: Handoff for parent verification

1. Inspect the exact diff and remove any line not directly required by the three behaviors.
2. Run:

   ```bash
   git diff --check
   git diff --exit-code ee49375 -- Package.swift Package.resolved
   git status --short --branch
   git ls-files -u
   ```

3. Commit only the two owned files with:

   ```bash
   git commit -m "fix: polish unfiled folder navigation"
   ```

4. Hand back the exact commit SHA, red and green evidence, changed-line summary, integrity checks, and any packaged-QA limitation. Do not push, open or update a pull request, merge, launch the app, or alter user data.

## Parent acceptance gate

The primary Sol / High session reads every changed line and independently runs the focused suites, full suite, diff/lock checks, one validator pass, and exact packaged-app QA from the design. A fresh Sol / High reviewer must return exactly `ship` before completion is reported.
