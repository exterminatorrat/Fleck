# Unfiled Width and Folder Selection Polish Design

**Date:** 2026-08-11

**Status:** Approved

## 1. Objective and success criteria

Make the folder navigator leave more room for user-created folders while keeping every folder state visually consistent and keyboard accessible.

The change succeeds when:

- Expanded Unfiled uses intrinsic content width, with the same compact label-to-count spacing as a named folder instead of absorbing unused horizontal space.
- Compact Unfiled still shows only its icon and count.
- The Unfiled disclosure has a forgiving rectangular hit target of at least 28 by 28 points without adding visible button chrome.
- Selected Unfiled and selected named folders use the same filled pill with no additional bright native focus halo.
- Keyboard focus remains visible on an unselected folder through one subtle explicit outline; selected-and-focused rows keep only the selected fill.
- Selection, keyboard navigation, note counts, drop targets, compact-state persistence, folder scrolling, Trash layout, and Reduce Motion behavior remain unchanged.

## 2. Owned files, interfaces, and constraints

Production ownership is limited to:

- `Sources/FleckApp/NotesPanel.swift`

Test ownership is limited to:

- `Tests/FleckAppTests/AppKitEditorTests.swift`

The implementation reuses `FolderNavigator.rootRow`, the named-folder row buttons, and the shared `rowLabel` builder. It must start from exact base `ee49375` on the isolated `codex/unfiled-folder-row-polish` branch and preserve all unrelated work. No dependency, package, preference, data-model, persistence, drag/drop, Trash, editor, or AppKit architecture changes are permitted.

## 3. Required implementation and explicit non-goals

### Required implementation

1. Make the root Unfiled row horizontally intrinsic in both expanded and compact states. Do not constrain the folder strip itself; named folders must continue scrolling horizontally.
2. Increase the disclosure button's invisible hit rectangle to at least 28 by 28 points and apply a rectangular content shape. Preserve the current icon, accessibility label, hover/focus discoverability, and Reduce Motion-aware state transition.
3. Disable the native SwiftUI focus effect on both Unfiled and named-folder row buttons so pointer focus cannot add a second bright selection border.
4. Extend the existing shared row label with one explicit focus presentation. Draw a restrained accent outline only when the row is keyboard-focused and not selected. Use the same shape and inset geometry for Unfiled and named folders.

### Non-goals

- No change to Trash width, folder order, tab order, drag/drop, context menus, selection semantics, or folder creation/deletion.
- No new folder-row component, style framework, AppKit bridge, animation system, or preference.
- No layout redesign beyond the reported Unfiled width, disclosure hit target, and selection/focus treatment.
- No changes to `Package.swift`, `Package.resolved`, generated files, dependencies, note data, or GitHub state.

## 4. Verification and expected evidence

Use red-first regression coverage in the existing AppKit UI suite:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
```

The red evidence must fail because the expanded root row is still flexible, the disclosure hit rectangle is undersized, or the native focus halo is still active. After the minimal production change, rerun the same command and record the exact passing count.

Parent verification after inspecting every changed line:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
swift test --disable-automatic-resolution --no-parallel --filter TabDragReorderTests
swift test --disable-automatic-resolution --no-parallel --quiet
git diff --check ee49375..HEAD
git diff --exit-code ee49375..HEAD -- Package.swift Package.resolved
Scripts/validate-macos.sh
```

Packaged QA must use the exact rebuilt `.build/Fleck.app` and confirm expanded and compact Unfiled sizing, the larger disclosure hit area, selected Unfiled/named-folder parity, visible unselected keyboard focus, horizontal folder scrolling, compact Trash, and unchanged selection/drop behavior. Do not edit personal notes during QA.

## 5. Authority boundaries and handoff

Implementation belongs only to one user-visible GPT-5.6 Luna / Max task titled with the `Agent - ` prefix. The task must write tests first, capture the intended red result, implement only the two owned files, run the focused suites, commit its exact changes, and hand back the commit, diff, commands, results, and known QA gaps.

The primary Sol / High session must inspect the complete diff and independently rerun the required verification. A fresh read-only `sol_advisor_sol_reviewer` at Sol / High must review the actual diff and evidence. Completion requires the reviewer verdict to be exactly `ship`; `fix-first` returns to the same Luna lane with a narrower correction packet, while `rethink` returns to design.
