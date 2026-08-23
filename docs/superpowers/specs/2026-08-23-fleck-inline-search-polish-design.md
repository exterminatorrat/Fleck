# Fleck Inline Search Polish Specification

Date: 2026-08-23

Design plan: `docs/design/2026-08-23-fleck-inline-search-polish-design-plan.md`

## 1. Objective and success criteria

Replace Fleck's centered Workspace Search morph with a compact top-trailing search presentation while preserving all accepted search behavior and all unrelated application behavior.

Success requires:

- Pointer search opens as a compact top-trailing surface no wider than 360 points.
- `Command-F` opens search instantly.
- Reduce Motion removes scale and all spatial movement.
- The current note remains visibly present behind search.
- Clicking outside, Escape, explicit dismissal, and result activation retain correct focus restoration.
- Search highlighting, asynchronous generation fencing, keyboard navigation, result activation, note selection, Unicode handling, and the 50-result limit remain unchanged.
- The formatting toolbar changes only from `.thinMaterial` to semantic `.bar`; commands, order, grouping, spacing, horizontal behavior, shortcuts, menus, and Delete remain unchanged.
- Focused tests, broader search tests, release build, package validation, visual captures, and fresh Sol review all pass.

## 2. Owned files, interfaces, and constraints

Implementation may modify only:

- `Sources/FleckApp/WorkspaceSearchView.swift`
- `Sources/FleckApp/NotesPanel.swift`
- `Tests/FleckAppTests/WorkspaceSearchHostingTests.swift`
- `Tests/FleckAppTests/WorkspaceSearchPresentationTests.swift`
- `Tests/FleckAppTests/WorkspaceSearchSourceAuditTests.swift`
- `Tests/FleckAppTests/AppKitEditorTests.swift` only if an existing relevant contract must be updated; do not add a source-text-only material assertion.

Parent-owned planning files:

- `docs/design/2026-08-23-fleck-inline-search-polish-design-plan.md`
- `docs/superpowers/specs/2026-08-23-fleck-inline-search-polish-design.md`
- `docs/superpowers/plans/2026-08-23-fleck-inline-search-polish.md`

Required interface compatibility:

- `WorkspaceSearchController` remains the single source of presentation, query, result, selection, generation, and focus-restoration state.
- `WorkspaceSearchController.present(for:presentation:)`, `dismiss`, `dismiss(ifPresentationID:)`, `setQuery`, `refresh`, `handleKey`, `activateResult`, and `activateHighlighted` retain their callable behavior.
- `WorkspaceSearchActivation` retains pointer and keyboard cases.
- `WorkspaceSearchPresentationKind.resolve(activation:reduceMotion:)` returns `.inline` for pointer/default motion, `.crossfade` for pointer/Reduce Motion, and `.instant` for keyboard.
- `WorkspaceSearchView` remains the NotesPanel-owned search surface and continues receiving the same search data and activation callbacks. The matched-geometry namespace parameter and transition-ID type are removed because no shared-element transition remains.
- `NotesPanel` continues preventing simultaneous Workspace Search and Note Link Picker presentations.

Constraints:

- Base: `codex/current-ui-parakeet-integration` at `7b5f6d5b00b83ba301c3341e8a17e51cbec2f47d`, plus these committed planning documents.
- macOS 14 minimum remains unchanged.
- No package dependency or `Package.resolved` change.
- Preserve adaptive Parakeet candidate integration and ordinary Apple Speech fallback.
- Preserve unrelated user and concurrent work.
- Use semantic macOS material and colors; do not add hard-coded Light/Dark colors.
- Use the existing `AppMotion.quick` 100 ms `easeOut` token.

## 3. Required implementation and explicit non-goals

### Presentation-kind correction

- Replace `.morph` with `.inline` in `WorkspaceSearchPresentationKind`.
- Remove `WorkspaceSearchTransition` and all `matchedGeometryEffect` calls for search.
- Keep `.crossfade` and `.instant` semantics.

### Search surface

- Keep the full-panel clear dismissal layer.
- Align the actual search surface `.topTrailing`.
- Apply 10-point horizontal inset and 8-point top inset.
- Set the search surface maximum width to 360 points.
- Use a 10-point rounded rectangle with `.regularMaterial`, a quaternary stroke, and shadow radius 8 with vertical offset 4.
- Preserve the current text field, magnifier, close button, result-count accessibility, result rows, empty/no-result copy, and keyboard handlers.

### Transition

- `.inline`: opacity plus `scale(scale: 0.98, anchor: .topTrailing)`.
- `.crossfade`: opacity only.
- `.instant`: identity.
- Parent animation remains `AppMotion.quick` for non-instant presentation and dismissal.

### NotesPanel integration

- Remove the search matched-geometry namespace and header source effects.
- The closed search trigger remains visually and behaviorally unchanged except that it no longer paints a dedicated matched-geometry shell.
- Preserve its `Command-F`, pointer activation, accessibility label/hint, and help text.
- Preserve the full-panel noninteraction and focus-restoration contract while search is open.
- Change only the formatting bar background from `.thinMaterial` to `.bar`.

Explicit non-goals are the complete list in the design plan. In particular, do not reproduce the rejected toolbar consolidation, add a main window, alter Settings, or touch Dictation and Cleanup code.

## 4. Verification commands and expected evidence

TDD RED/GREEN:

- Update `WorkspaceSearchPresentationSelectsPointerAndKeyboardMotionKinds` to require `.inline`; RED must show `.morph` is still returned.
- Replace the matched-geometry source audit with a behavior or presentation contract requiring no shared-element transition and correct transition selection; RED must fail against the old implementation.
- Add a hosted geometry test that presents search in a 640-by-430 `NotesPanel`, locates the real search `NSTextField`, and asserts its width is at most 320 points and that the search surface fits the trailing 360-point region. RED must fail because the old field is substantially wider.
- Add or adapt a minimum-width hosted test at 380 by 430 points proving the search field and dismiss control remain within host bounds.

Focused checks:

```bash
swift test --filter WorkspaceSearchPresentationTests
swift test --filter WorkspaceSearchHostingTests
swift test --filter WorkspaceSearchSourceAuditTests
swift test --filter WorkspaceSearchPerformanceTests
swift test --filter NotesPanelBacklinksTests
```

Expected: selected Swift Testing tests pass with zero failures. A filter selecting zero tests is not accepted evidence.

Broader checks:

```bash
swift test --filter AppKitEditorTests
swift test
swift build -c release --product Fleck
git diff --check
```

Expected: exit 0, with any pre-existing baseline warning or failure compared explicitly against the exact base.

Package and runtime:

```bash
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
  Scripts/build-parakeet-test-app.sh
codesign --verify --deep --strict --verbose=2 .build/parakeet-test/Fleck.app
```

Expected: arm64 app and helper, SDK 26.5 metadata, strict deep signature, no packaged model weights, expected manifest/notices/mark resources, and binary strings proving adaptive Parakeet plus current UI markers.

Visual evidence:

- Launch only the freshly packaged bundle.
- Capture the five states listed in the design plan.
- Inspect screenshots for placement, clipping, contrast, hierarchy, unchanged toolbar commands, and minimum-width fit.

## 5. Authority boundaries and required handoff

- Primary Sol owns architecture, planning documents, diff inspection, independent verification, packaging, runtime provenance, visual review, integration decision, and final acceptance.
- GPT-5.6 Luna/Max owns implementation only within the listed implementation files in its isolated worktree.
- Luna must use red-first TDD and must not edit planning documents, other source, package configuration, Dictation and Cleanup, security, persistence, or Settings.
- No push, PR, merge, rebase, GitHub mutation, installed `/Applications/Fleck.app` replacement, branch deletion, or worktree pruning is authorized.
- Luna may make a focused local commit and must return its SHA, actual base, full changed-file list, verification output, and gaps.
- A fresh `sol_advisor_sol_reviewer` must inspect the actual accumulated diff and parent evidence and return exactly `VERDICT: ship` before acceptance.
