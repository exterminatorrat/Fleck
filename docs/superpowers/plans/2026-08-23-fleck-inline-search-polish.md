# Fleck Inline Search Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Fleck's repository-specific Sol/Luna routing supersedes generic native-subagent instructions.

**Goal:** Replace the centered Workspace Search morph with a compact top-trailing search surface while preserving every existing search behavior and toolbar command.

**Architecture:** Keep `WorkspaceSearchController` and the search engine unchanged as the state and behavior core. Reshape only `WorkspaceSearchView` and its `NotesPanel` presentation: a compact anchored surface, presentation-kind-specific transitions, no matched geometry, and the already accepted semantic toolbar material correction.

**Tech Stack:** Swift 6, SwiftUI, AppKit hosting tests, Swift Testing, SwiftPM, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-23-fleck-inline-search-polish-design.md`

## Global Constraints

- Start from `codex/current-ui-parakeet-integration` commit `7b5f6d5b00b83ba301c3341e8a17e51cbec2f47d` plus the parent-authored planning commit.
- Modify only the six implementation/test paths allowed by the specification.
- Preserve all search data, focus, keyboard, accessibility, activation, race, and Unicode behavior.
- Preserve every toolbar command, order, grouping, spacing, horizontal behavior, shortcut, menu, and Delete location.
- Do not touch Dictation and Cleanup, security, persistence, models, resources, package configuration, or Settings.
- Do not integrate prototype commits `c262ed7`, `b13ba15`, `d44beb1`, `64332f7`, `f6a2afd`, or `19d1c32`.
- No push, PR, merge, rebase, installed-app replacement, branch deletion, or worktree pruning.

---

### Task 1: Replace the shared-element presentation contract

**Files:**
- Modify: `Tests/FleckAppTests/WorkspaceSearchPresentationTests.swift`
- Modify: `Sources/FleckApp/WorkspaceSearchView.swift`

**Interfaces:**
- Consumes: `WorkspaceSearchActivation`, `WorkspaceSearchPresentationKind.resolve`
- Produces: `.inline`, `.crossfade`, and `.instant` presentation kinds

- [ ] **Step 1: Write the failing presentation-kind test**

Change the pointer/default expectation and controller exercise to `.inline`:

```swift
#expect(
  WorkspaceSearchPresentationKind.resolve(
    activation: .pointer,
    reduceMotion: false
  ) == .inline
)

let controller = WorkspaceSearchController()
controller.present(presentation: .inline)
#expect(controller.presentationKind == .inline)
```

Replace the old matched-geometry audit with a contract that the presentation source no longer exposes transition IDs or `matchedGeometryEffect`.

- [ ] **Step 2: Run the RED test**

```bash
swift test --filter WorkspaceSearchPresentationTests
```

Expected: failure because `.inline` does not exist and `.morph` is still the pointer kind.

- [ ] **Step 3: Implement the minimal presentation-kind change**

In `WorkspaceSearchView.swift`:

```swift
enum WorkspaceSearchPresentationKind: Equatable {
  case inline
  case crossfade
  case instant

  static func resolve(
    activation: WorkspaceSearchActivation,
    reduceMotion: Bool
  ) -> Self {
    switch activation {
    case .pointer:
      return reduceMotion ? .crossfade : .inline
    case .keyboard:
      return .instant
    }
  }

  var usesAnimatedDismissal: Bool { self != .instant }
}
```

Delete `WorkspaceSearchTransition`. Do not change controller search or focus behavior.

- [ ] **Step 4: Run the GREEN test**

```bash
swift test --filter WorkspaceSearchPresentationTests
```

Expected: all selected tests pass and the output names at least the presentation tests.

### Task 2: Anchor and resize the real hosted search surface

**Files:**
- Modify: `Tests/FleckAppTests/WorkspaceSearchHostingTests.swift`
- Modify: `Sources/FleckApp/WorkspaceSearchView.swift`

**Interfaces:**
- Consumes: existing `WorkspaceSearchView` inputs and controller callbacks
- Produces: a top-trailing surface with a maximum 360-point footprint

- [ ] **Step 1: Add the failing hosted geometry tests**

Host `NotesPanel` at 640 by 430, present search, locate the real `NSTextField` whose placeholder is `Search notes`, convert its frame into host coordinates, and require a field width at most 320 points. Repeat at 380 by 430 and require the field plus dismiss control to remain inside `host.bounds`.

The regression caught is the old centered field whose hosted width is substantially greater than 320 points.

- [ ] **Step 2: Run the hosted RED tests**

```bash
swift test --filter WorkspaceSearchHostingTests
```

Expected: the new width/placement test fails against the 560-point centered surface while existing hosting tests pass.

- [ ] **Step 3: Implement the compact surface**

Keep the full-frame clear outside-click dismissal target. Change the actual surface to:

```swift
.padding(10)
.frame(maxWidth: 360, alignment: .leading)
.background {
  RoundedRectangle(cornerRadius: 10)
    .fill(.regularMaterial)
}
.overlay {
  RoundedRectangle(cornerRadius: 10)
    .strokeBorder(.quaternary)
}
.shadow(color: .black.opacity(0.14), radius: 8, y: 4)
```

Align the outer container `.topTrailing`, apply `.padding(.horizontal, 10)` and `.padding(.top, 8)`, and remove matched-geometry branches from the magnifier and shell.

- [ ] **Step 4: Run the hosted GREEN tests**

```bash
swift test --filter WorkspaceSearchHostingTests
```

Expected: all hosted geometry, focus restoration, activation, Unicode, and link-picker coexistence tests pass.

### Task 3: Connect the restrained transition in NotesPanel

**Files:**
- Modify: `Tests/FleckAppTests/WorkspaceSearchSourceAuditTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`

**Interfaces:**
- Consumes: `WorkspaceSearchPresentationKind`
- Produces: `.inline` top-trailing scale/opacity, `.crossfade` opacity, `.instant` identity

- [ ] **Step 1: Write the failing integration contract**

Update the existing source audit to reject `matchedGeometryEffect` and the old search-transition namespace, and require the NotesPanel transition switch to include top-trailing anchored scale only for `.inline`. Retain source audits only for wiring that a hosted behavior test cannot distinguish cheaply; geometry and focus remain covered by hosted tests.

- [ ] **Step 2: Run the integration RED test**

```bash
swift test --filter WorkspaceSearchSourceAuditTests
```

Expected: failure because NotesPanel still contains the matched-geometry source and old transition.

- [ ] **Step 3: Implement the NotesPanel wiring**

- Remove `workspaceSearchTransition`.
- Remove matched-geometry and dedicated search-trigger material branches from the closed header button.
- Remove `transitionNamespace` from `WorkspaceSearchView` construction.
- Select the transition with a small helper or inline switch:

```swift
switch searchController.presentationKind {
case .inline:
  .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
case .crossfade:
  .opacity
case .instant:
  .identity
}
```

Keep the existing parent animation token and full-panel focus-restoration behavior.

- [ ] **Step 4: Carry forward the accepted toolbar contrast correction**

Change only:

```swift
.background(.thinMaterial)
```

to:

```swift
.background(.bar)
```

inside `FormattingBar`. Do not change any toolbar content or layout.

- [ ] **Step 5: Run the integration GREEN tests**

```bash
swift test --filter WorkspaceSearchSourceAuditTests
swift test --filter WorkspaceSearchPresentationTests
swift test --filter WorkspaceSearchHostingTests
swift test --filter NotesPanelBacklinksTests
```

Expected: all selected tests pass with nonzero selected-test counts.

### Task 4: Complete regression, build, and diff verification

**Files:**
- Inspect only: all owned source and test files

**Interfaces:**
- Consumes: Tasks 1-3 accumulated diff
- Produces: verifiable local implementation checkpoint

- [ ] **Step 1: Run focused performance and editor suites**

```bash
swift test --filter WorkspaceSearchPerformanceTests
swift test --filter AppKitEditorTests
```

Expected: all selected tests pass.

- [ ] **Step 2: Run the full ordinary suite and release build**

```bash
swift test
swift build -c release --product Fleck
```

Expected: exit 0, or an exact pre-existing base failure reproduced and reported separately. New failures are blockers.

- [ ] **Step 3: Inspect the complete diff**

```bash
git diff --check
git diff --stat
git diff -- Sources/FleckApp/WorkspaceSearchView.swift Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/WorkspaceSearchHostingTests.swift Tests/FleckAppTests/WorkspaceSearchPresentationTests.swift Tests/FleckAppTests/WorkspaceSearchSourceAuditTests.swift Tests/FleckAppTests/AppKitEditorTests.swift
git status --short --branch
```

Expected: no whitespace errors, no files outside ownership, no package changes, and no toolbar-command/layout changes.

- [ ] **Step 4: Commit the focused implementation**

```bash
git add Sources/FleckApp/WorkspaceSearchView.swift Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/WorkspaceSearchHostingTests.swift Tests/FleckAppTests/WorkspaceSearchPresentationTests.swift Tests/FleckAppTests/WorkspaceSearchSourceAuditTests.swift Tests/FleckAppTests/AppKitEditorTests.swift
git commit -m "Polish workspace search presentation"
```

Stage only files actually changed. Report the exact commit SHA and clean/dirty status. Do not push.

### Task 5: Parent-owned package, launch, visual review, and final gate

**Files:**
- Parent inspection only; no worker edits

**Interfaces:**
- Consumes: accepted Luna commit and verification evidence
- Produces: package/runtime/visual evidence and fresh Sol verdict

- [ ] **Step 1: Parent independently inspects and reruns verification**

The primary checks base, branch, full diff, commit, Package.resolved, unmerged entries, and MERGE_HEAD, then reruns all focused search suites, `AppKitEditorTests`, release build, and `git diff --check`.

- [ ] **Step 2: Build the adaptive Parakeet package**

```bash
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
  Scripts/build-parakeet-test-app.sh
codesign --verify --deep --strict --verbose=2 .build/parakeet-test/Fleck.app
```

Verify arm64 architecture, SDK 26.5, bundle identifiers, resources, no model weights, and current UI/model marker strings.

- [ ] **Step 3: Launch only the packaged app and capture screenshots**

Terminate only processes whose bundle path is proven to be an older Fleck bundle. Launch the accepted packaged bundle, capture closed/open/results/minimum-width states, and visually inspect them using the design-plan acceptance criteria.

- [ ] **Step 4: Obtain a fresh Sol review**

Send the exact accumulated diff and parent evidence to a fresh read-only `sol_advisor_sol_reviewer`. Only `VERDICT: ship` permits acceptance; `fix-first` returns to the same Luna task.
