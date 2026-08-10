# Compact Trailing Trash Control Implementation Plan

> **For the authorized native implementation task:** REQUIRED SUB-SKILLS: Use
> `test-driven-development`, `ponytail`, `emil-design-eng`,
> `build-macos-apps:swiftui-patterns`, and `verification-before-completion`.
> Follow every checkbox in order and retain red-before-green evidence.

**Goal:** Make the existing trailing Trash control consume only its intrinsic content width so the horizontally scrolling folder strip receives the remaining navigator width.

**Architecture:** Keep the existing `FolderNavigator` composition and shared `rowLabel`. Add one horizontal fixed-size modifier to the existing Trash `Button`, leaving the named-folder `ScrollView` as the flexible-width consumer and preserving every interaction and accessibility modifier on Trash.

**Tech Stack:** Swift 6, SwiftUI, AppKit-hosted SwiftUI, Swift Testing, Swift Package Manager, macOS 14+.

## Global Constraints

- **Execution hold:** Implementation is not authorized until the user explicitly says `start`. Until then, do not edit source/tests, dispatch an implementation or review agent, build, launch Fleck, run UI automation, push, or open/update a pull request.
- The implementation lane must use the exact native GPT-5.6 Sol / High route selected by the user. Do not substitute a different model or reasoning lane.
- Implementation ownership is limited to `Sources/FleckApp/NotesPanel.swift` and `Tests/FleckAppTests/AppKitEditorTests.swift`.
- Preserve unrelated and concurrent work. Do not revert, reformat, or clean adjacent code.
- Preserve the outer navigator order: Unfiled, folder `ScrollView`, new-folder button, divider, Trash.
- Preserve `.frame(maxWidth: .infinity)` on the folder `ScrollView` so it receives the reclaimed width.
- Compact only the Trash `Button`. Do not add horizontal fixed sizing to shared `rowLabel`, named folders, or the Unfiled root row; retain Unfiled's existing conditional compact behavior unchanged.
- Preserve the existing Trash icon, visible `Trash` word, monospaced count, typography, seven-point label spacing, padding, row height, divider, full intrinsic hit target, `onOpenTrash()` action, focus binding, focusability, accessibility label, identifier, and empty/count value.
- Add no animation. Preserve folder-creation motion and Reduce Motion behavior unchanged.
- Add no icon-only state, preference, hover reveal, tooltip, context menu, new component, dependency, package change, generated file, persistence change, or broad test harness.
- Do not modify the duplicate existing `folder-unfiled` accessibility identifier or any adjacent code.
- Do not push, open/update/merge a pull request, rebase, switch branches, or alter GitHub settings without a new explicit authorization.

---

## File Map and Interfaces

| File | Responsibility |
| --- | --- |
| `Sources/FleckApp/NotesPanel.swift` | Add one `.fixedSize(horizontal: true, vertical: false)` modifier to the existing trailing Trash `Button` in `FolderNavigator.body`. |
| `Tests/FleckAppTests/AppKitEditorTests.swift` | Add the deterministic source-structure regression that proves only Trash is intrinsically sized and the folder strip remains flexible. |

The implementation consumes the existing interfaces unchanged:

```swift
let onOpenTrash: () -> Void

private func rowLabel(
  name: String,
  systemImage: String,
  count: Int,
  isSelected: Bool,
  isEmpty: Bool,
  isDropTarget: Bool = false,
  showsName: Bool = true
) -> some View
```

It produces no new type, helper, parameter, state, or public interface.

## Authorization Gate

- [ ] Record the user's explicit `start` authorization in the implementation task. If it is absent, stop without modifying or running anything.

- [ ] Confirm the exact implementation packet and native Sol / High route are active. Record the starting state before editing:

  ```bash
  pwd
  git branch --show-current
  git rev-parse HEAD
  git status --short --branch
  git ls-files -u
  git rev-parse -q --verify MERGE_HEAD
  ```

  Expected: the intended Fleck worktree and branch are explicit, status is clean except for known authorized work, `git ls-files -u` prints nothing, and the `MERGE_HEAD` lookup exits nonzero. Set `FLECK_TRASH_BASE` to the recorded starting SHA in the retained task shell. Stop if the base, ownership, or unrelated-work boundary cannot be preserved.

---

### Task 1: Prove and correct the Trash-only width contract

**Files:**

- Modify: `Tests/FleckAppTests/AppKitEditorTests.swift`, beside the existing compact-Unfiled source regressions.
- Modify: `Sources/FleckApp/NotesPanel.swift`, in the trailing Trash `Button` inside `FolderNavigator.body`.

**Interfaces:**

- Consumes: `notesPanelSource()`, the existing `FolderNavigator.body`, `rootRow`, `folderRow(_:)`, and `rowLabel(...)` source seams.
- Produces: one regression proving the folder strip stays flexible and the Trash button alone opts into horizontal intrinsic sizing; one local SwiftUI modifier satisfying that contract.

- [ ] **Step 1: Write the failing source-structure regression**

  Add this test immediately after `compactUnfiledReleasesOnlyItsFlexibleRootRowWidth` and before changing production code:

  ```swift
  @Test func compactTrashAloneUsesIntrinsicWidthAndLeavesFolderStripFlexible() throws {
    let source = try notesPanelSource()
    let navigator = try #require(
      source.components(separatedBy: "private struct FolderNavigator").last
    )
    let bodyStart = try #require(navigator.range(of: "var body: some View"))
    let rootDefinition = try #require(navigator.range(of: "private var rootRow"))
    let body = String(navigator[bodyStart.upperBound..<rootDefinition.lowerBound])
    let folderScroll = try #require(
      body.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").last?
        .components(separatedBy: "beginNewFolder()").first
    )
    let trashBlock = try #require(
      body.components(separatedBy: "Divider()").last?
        .components(separatedBy: ".accessibilityValue(").first
    )
    let rootRow = try #require(
      navigator.components(separatedBy: "private var rootRow").last?
        .components(separatedBy: "@ViewBuilder\n    private func folderRow").first
    )
    let folderRow = try #require(
      navigator.components(separatedBy: "private func folderRow").last?
        .components(separatedBy: "private struct FolderActionButtonStyle").first
    )
    let rowLabel = try #require(
      navigator.components(separatedBy: "private func rowLabel").last?
        .components(separatedBy: "private func noteDropTargetBinding").first
    )

    #expect(folderScroll.contains(".frame(maxWidth: .infinity)"))
    #expect(trashBlock.contains("onOpenTrash()"))
    #expect(trashBlock.contains("name: \"Trash\""))
    #expect(trashBlock.contains(".fixedSize(horizontal: true, vertical: false)"))
    #expect(
      body.components(separatedBy: ".fixedSize(horizontal: true, vertical: false)").count - 1 == 1
    )
    #expect(!rootRow.contains(".fixedSize(horizontal: true, vertical: false)"))
    #expect(rootRow.contains(".fixedSize(horizontal: isUnfiledCompact, vertical: false)"))
    #expect(!folderRow.contains(".fixedSize(horizontal: true, vertical: false)"))
    #expect(!rowLabel.contains(".fixedSize(horizontal: true, vertical: false)"))
  }
  ```

  This is intentionally an exact structural regression. The current hosted pixel helper identifies selected accent fills, while the unselected private SwiftUI Trash button has no stable AppKit descendant frame. Do not add a broad geometry harness for this one-line layout contract.

- [ ] **Step 2: Run the focused test and capture the red state**

  ```bash
  swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
  ```

  Expected: nonzero exit in `compactTrashAloneUsesIntrinsicWidthAndLeavesFolderStripFlexible` because `trashBlock` does not yet contain `.fixedSize(horizontal: true, vertical: false)`. The other assertions should not identify a compile error, typo, missing source seam, or changed folder-strip contract. Record the exact failing expectation and suite counts.

- [ ] **Step 3: Implement the minimum production change**

  In `FolderNavigator.body`, add exactly one modifier to the existing trailing Trash `Button`, before its existing `.buttonStyle(.plain)` modifier:

  ```swift
  .fixedSize(horizontal: true, vertical: false)
  ```

  Do not change the label closure, shared `rowLabel`, its `Spacer`, any frame, spacing, padding, divider, focus/accessibility modifier, action, or adjacent identifier.

- [ ] **Step 4: Run focused green verification**

  ```bash
  swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
  swift test --disable-automatic-resolution --no-parallel --filter TabDragReorderTests
  ```

  Expected: both commands exit 0. Record the exact test count from each run. The AppKit suite must include the new Trash-only regression plus the existing compact-Unfiled, selected-folder, focus, drop, and editor assertions; the tab-drag suite must remain unchanged and green.

- [ ] **Step 5: Review the two-file implementation diff**

  ```bash
  git diff -- Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift
  git diff --check
  git diff --name-only "$FLECK_TRASH_BASE"
  git diff --exit-code "$FLECK_TRASH_BASE" -- Package.resolved
  ```

  Expected: the production diff is the single Trash-only modifier; the test diff is the focused regression; whitespace check is silent; changed files are exactly the two owned implementation files; `Package.resolved` is byte-identical to the recorded base.

- [ ] **Step 6: Commit the focused implementation**

  ```bash
  git add Sources/FleckApp/NotesPanel.swift Tests/FleckAppTests/AppKitEditorTests.swift
  git diff --cached --name-only
  git commit -m "fix: compact trailing trash control"
  ```

  Expected staged paths are exactly the two owned implementation files. Record the commit SHA. Do not push or open a pull request.

---

### Task 2: Run release-proportional verification and obtain a fresh review

**Files:**

- Verify only: committed `Sources/FleckApp/NotesPanel.swift` and `Tests/FleckAppTests/AppKitEditorTests.swift`.
- Build artifact: `.build/Fleck.app`; never stage it.

**Interfaces:**

- Consumes: the committed two-file implementation, Swift package tests, repository macOS validator, packaged app, and Sol Advisor review gate.
- Produces: focused/full/validator results, exact packaged visual observations, repository-integrity evidence, and a fresh Sol verdict.

- [ ] **Step 1: Run the complete automated gate from the implementation commit**

  ```bash
  swift test --disable-automatic-resolution --no-parallel
  Scripts/validate-macos.sh
  git diff --check "$FLECK_TRASH_BASE"..HEAD
  git diff --exit-code "$FLECK_TRASH_BASE"..HEAD -- Package.resolved
  ```

  Expected: the full suite exits 0 with its exact test count recorded; `Scripts/validate-macos.sh` exits 0 and produces its development-signed `.build/Fleck.app`; diff check is silent; package-lock comparison is silent and exits 0. A dependency-resolution, signing, packaging, or unrelated test failure is not accepted as evidence for this UI change.

- [ ] **Step 2: Confirm the exact repository boundary**

  ```bash
  git status --short --branch
  git diff --name-only "$FLECK_TRASH_BASE"..HEAD
  git ls-files -u
  git rev-parse -q --verify MERGE_HEAD
  git show --stat --oneline --decorate --no-renames HEAD
  ```

  Expected: the worktree is clean; the implementation range contains only `Sources/FleckApp/NotesPanel.swift` and `Tests/FleckAppTests/AppKitEditorTests.swift`; there are no unmerged entries; `MERGE_HEAD` is absent; the implementation commit is `fix: compact trailing trash control`.

- [ ] **Step 3: Perform fail-closed packaged visual and interaction QA**

  Use only the exact `.build/Fleck.app` produced by the successful validator. Do not terminate, replace, or automate an existing Fleck process. If another Fleck instance with the same bundle identity is active, or if the available workspace has no named folder with which to observe a nonzero folder viewport, record packaged QA as blocked and do not claim completion.

  With an authorized disposable QA workspace, launch:

  ```bash
  /usr/bin/open -n .build/Fleck.app
  ```

  Set the panel content width to 640 points and record a screenshot plus these exact observations:

  1. Trash remains after the 20-point divider at the far trailing edge.
  2. Trash width hugs the existing icon, visible `Trash` text, count, and padding; it does not consume the unused center of the navigator.
  3. The named-folder viewport is visibly nonzero, receives the reclaimed width, and still scrolls horizontally when its contents overflow.
  4. Empty and non-empty Trash counts retain the existing presentation.
  5. Clicking anywhere inside the padded Trash pill opens Trash exactly once.
  6. Keyboard navigation can focus Trash; Return and Space open it; the focus treatment remains visible and unclipped.
  7. VoiceOver announces `Trash` and either `Empty` or the current `N notes` value for the element identified as `folder-trash`.
  8. Unfiled and named-folder widths, selection fills, drop behavior, new-folder control, and divider remain visually unchanged.

  Do not create, rename, move, Trash, or permanently delete personal notes for this verification. Quit only the disposable QA instance after recording evidence.

- [ ] **Step 4: Obtain the required fresh Sol review**

  The primary Sol session must independently inspect the actual implementation commit and rerun at least:

  ```bash
  swift test --disable-automatic-resolution --no-parallel --filter AppKitEditorTests
  swift test --disable-automatic-resolution --no-parallel --filter TabDragReorderTests
  git diff --check "$FLECK_TRASH_BASE"..HEAD
  git diff --name-only "$FLECK_TRASH_BASE"..HEAD
  git ls-files -u
  git rev-parse -q --verify MERGE_HEAD
  ```

  Dispatch a fresh `sol_advisor_sol_reviewer` with the exact base/head, two-file diff, red failure, focused/full/validator counts, package-lock evidence, and packaged QA observations. Completion requires the reviewer verdict exactly `ship`. For `fix-first` or `rethink`, return the corrected bounded specification to the same authorized native implementation lane, rerun parent verification, and request another fresh review. Do not silently repair the implementation in the parent session.

## Required Handoff

Report exact worktree, branch, base, head, implementation commit, changed files, the red command and exact failing expectation, the one-line production change, focused and full test counts, validator/package result, packaged visual/keyboard/VoiceOver observations, `Package.resolved` identity, diff/status/unmerged/MERGE_HEAD evidence, reviewer verdict, and every blocked or unavailable boundary.

Do not claim completion unless automated verification is green, packaged QA is recorded rather than inferred, and the fresh reviewer verdict is exactly `ship`.
