# Fleck Workspace Search Motion Policy Adoption Implementation Plan

> **For agentic workers:** REQUIRED PROCESS: Follow the repository's Sol Advisor user-visible Luna/Max task lane and strict Superpowers TDD. Do not use native subagents.

**Goal:** Make the accepted Workspace Search use Fleck's semantic motion policy so pointer presentation has calm spatial continuity, Reduce Motion crossfades briefly, keyboard presentation stays instant, and dismissal remains faster than entrance.

**Architecture:** Preserve the existing `WorkspaceSearchPresentationKind` and transition geometry. Add one mapping from that accepted presentation decision to `AppInteractionSource`, then let the accepted `AppMotion.presentationAnimation(for:)` choose the entrance animation. Keep the existing 100 ms dismissal path unchanged.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Swift Package Manager, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-26-fleck-native-interface-and-motion-system-design.md`

## Global Constraints

- Preserve the accepted inline Search layout, result behavior, focus fencing, mutual exclusion, accessibility hiding, shortcuts, and transition geometry.
- Pointer normal motion remains `.inline`; pointer Reduce Motion remains `.crossfade`; keyboard remains `.instant`.
- Pointer entrance uses the semantic 220 ms surface role; Reduce Motion entrance uses the 120 ms state role; keyboard entrance is unanimated.
- Animated dismissal remains the existing 100 ms quick animation, making exit faster than entrance.
- Do not alter Search sizing, blur/material, scale endpoint, result rows, filtering, performance, copy, or keyboard behavior.
- Do not touch toolbar layout, folders, tabs, editor behavior, Dictation/Cleanup, packaging source, manifests, dependencies, or unrelated code.
- GitHub writes remain unauthorized.

---

### Task 1: Route Search entrance through the semantic motion policy

**Files:**
- Modify: `Sources/FleckApp/WorkspaceSearchView.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Tests/FleckAppTests/WorkspaceSearchHostingTests.swift`

**Interfaces:**
- `WorkspaceSearchPresentationKind.interactionSource: AppInteractionSource`
- `.inline` and `.crossfade` map to `.pointer`; `.instant` maps to `.keyboard`.
- `NotesPanel.presentWorkspaceSearch` calls `motion.presentationAnimation(for: presentation.interactionSource)`.
- `NotesPanel.dismissWorkspaceSearch` remains unchanged and continues using `motion.quick` for animated dismissal.

- [ ] **Step 1: Write the failing mapping assertions**

In `WorkspaceSearchPresentationSelectsPointerAndKeyboardMotionKinds`, add:

```swift
#expect(WorkspaceSearchPresentationKind.inline.interactionSource == .pointer)
#expect(WorkspaceSearchPresentationKind.crossfade.interactionSource == .pointer)
#expect(WorkspaceSearchPresentationKind.instant.interactionSource == .keyboard)
```

These assertions catch a regression where keyboard Search begins animating, or where the Reduce Motion crossfade loses its pointer-origin policy.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter WorkspaceSearchHostingTests
```

Expected: compilation fails specifically because `interactionSource` is absent. Fix only unrelated test syntax and rerun until the expected missing-property failure is observed.

- [ ] **Step 3: Add the minimal presentation mapping**

In `WorkspaceSearchPresentationKind`, add:

```swift
var interactionSource: AppInteractionSource {
  switch self {
  case .inline, .crossfade:
    return .pointer
  case .instant:
    return .keyboard
  }
}
```

Do not add another enum or change `resolve`, `usesAnimatedDismissal`, transition geometry, or controller state.

- [ ] **Step 4: Adopt the semantic entrance animation**

In `NotesPanel.presentWorkspaceSearch`, replace only the `withAnimation` argument:

```swift
withAnimation(
  motion.presentationAnimation(for: presentation.interactionSource)
) {
```

Keep the contents of that transaction unchanged. Keep `dismissWorkspaceSearch` unchanged so animated dismissal remains `motion.quick` and instant dismissal remains `nil`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter WorkspaceSearchHostingTests
swift test --disable-automatic-resolution --no-parallel --filter WorkspaceSearchPresentationTests
swift test --disable-automatic-resolution --no-parallel --filter AppMotionTests
```

Expected: all selected Search and motion tests pass with exit status 0.

- [ ] **Step 6: Run broader verification**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel
swift build --disable-automatic-resolution -c release --product Fleck
```

Expected:

- The full suite introduces no failure beyond the three independently confirmed base failures: the checklist accent-pixel assertion and two streaming-dictation timing assertions.
- The release Fleck product builds with exit status 0.

- [ ] **Step 7: Inspect scope and commit locally**

Run:

```bash
git diff --check
git status --short --branch
git diff -- Sources/FleckApp/WorkspaceSearchView.swift Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/WorkspaceSearchHostingTests.swift
git add Sources/FleckApp/WorkspaceSearchView.swift Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/WorkspaceSearchHostingTests.swift
git commit -m "feat: apply semantic motion to search"
```

Expected: exactly the three owned files differ before commit and the worktree is clean afterward. Report the exact commit SHA. Do not push or open a pull request.

## Parent Visual and Package Gate

After a fresh Sol reviewer verdict of exactly `ship`, the primary session must integrate the checkpoint serially, build the newest packaged Fleck application, verify the running executable points to that exact accepted artifact, and compare Search under:

- pointer normal motion;
- pointer Reduce Motion;
- Command-F instant presentation;
- rapid open/Escape/reopen interruption;
- Light and Dark Mode at full and compact panel widths.

Capture before/after stills for geometry and a short recording or frame sequence for timing. Verify that the note remains visible, the top-trailing origin stays coherent, focus lands in Search immediately, dismissal finishes faster than entrance, and no stale process or older bundle is running.
