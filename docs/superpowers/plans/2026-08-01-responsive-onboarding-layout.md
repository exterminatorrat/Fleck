# Responsive Fleck Onboarding Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every onboarding step resize from 760 by 520 points upward without clipping its heading, required controls, real editor, progress rail, or persistent footer.

**Architecture:** Add a deterministic layout-presentation value that selects regular or compact metrics from the offered size. Give the existing `NotesPanel` an explicit container sizing mode, then rebuild onboarding around a finite flexible body, pinned rail/footer, native `ViewThatFits` fallback for static content, and a non-nested Dictation canvas. The existing menu-bar and pinned-note call sites keep stored panel sizing by default.

**Tech Stack:** Swift 6, SwiftUI and AppKit on macOS, Swift Testing, existing FleckApp/FleckCore modules; no new dependency.

## Global Constraints

- Default onboarding content size remains exactly 1,080 by 700 points.
- Minimum onboarding content size is exactly 760 by 520 points.
- Regular layout begins only when width is at least 920 points and height is at least 620 points; otherwise use compact layout.
- Regular rail/footer/padding are 240/72/32 points; compact rail/footer/padding are 188/64/20 points.
- Typography and hit targets do not scale down in compact mode.
- The real `NotesPanel`, editor, dictation runtime, permission actions, progress persistence, and access seams remain authoritative.
- Normal Fleck panels keep stored `panelWidth` and `panelHeight`; onboarding resizing must not write either preference.
- StoreKit, trial entitlement, purchase, restore, expiry, and read-only enforcement remain out of scope.
- Preserve the unrelated untracked `.superpowers/brainstorm/` directory.

---

### Task 1: Deterministic responsive metrics and window contract

**Files:**
- Modify: `Tests/FleckAppTests/OnboardingPresentationTests.swift`
- Modify: `Tests/FleckAppTests/OnboardingWindowTests.swift`
- Modify: `Sources/FleckApp/OnboardingView.swift`
- Modify: `Sources/FleckApp/OnboardingWindowPresenter.swift`

**Interfaces:**
- Produces: `OnboardingLayoutPresentation.init(width:height:)`, `tier`, `railWidth`, `contentPadding`, `footerHeight`, `minimumEditorHeight`.
- Produces: `OnboardingWindowPresenter.defaultSize` and `minimumSize` as `NSSize` constants.
- Consumes: Existing SwiftUI and AppKit geometry types only.

- [ ] **Step 1: Write failing responsive-metric tests**

Append to `Tests/FleckAppTests/OnboardingPresentationTests.swift`:

```swift
@Test func onboardingLayoutUsesExactCompactAndRegularBoundaries() {
  let minimum = OnboardingLayoutPresentation(width: 760, height: 520)
  #expect(minimum.tier == .compact)
  #expect(minimum.railWidth == 188)
  #expect(minimum.contentPadding == 20)
  #expect(minimum.footerHeight == 64)
  #expect(minimum.minimumEditorHeight == 180)

  #expect(OnboardingLayoutPresentation(width: 919, height: 620).tier == .compact)
  #expect(OnboardingLayoutPresentation(width: 920, height: 619).tier == .compact)

  let regular = OnboardingLayoutPresentation(width: 920, height: 620)
  #expect(regular.tier == .regular)
  #expect(regular.railWidth == 240)
  #expect(regular.contentPadding == 32)
  #expect(regular.footerHeight == 72)
  #expect(regular.minimumEditorHeight == 240)
}
```

- [ ] **Step 2: Run the metric test and verify red**

Run:

```sh
swift test --disable-automatic-resolution --filter onboardingLayoutUsesExactCompactAndRegularBoundaries
```

Expected: compilation fails because `OnboardingLayoutPresentation` does not exist.

- [ ] **Step 3: Add the minimal layout presentation**

Add near the presentation types at the top of `Sources/FleckApp/OnboardingView.swift`:

```swift
struct OnboardingLayoutPresentation: Equatable {
  enum Tier: Equatable {
    case compact
    case regular
  }

  let tier: Tier

  init(width: CGFloat, height: CGFloat) {
    tier = width >= 920 && height >= 620 ? .regular : .compact
  }

  var railWidth: CGFloat { tier == .regular ? 240 : 188 }
  var contentPadding: CGFloat { tier == .regular ? 32 : 20 }
  var footerHeight: CGFloat { tier == .regular ? 72 : 64 }
  var minimumEditorHeight: CGFloat { tier == .regular ? 240 : 180 }
}
```

- [ ] **Step 4: Run the metric test and verify green**

Run the Step 2 command again.

Expected: 1 test passes and the command exits 0.

- [ ] **Step 5: Write failing onboarding-window size tests**

Append to `Tests/FleckAppTests/OnboardingWindowTests.swift`:

```swift
@Test func OnboardingWindowDeclaresDefaultAndMinimumResponsiveSizes() {
  #expect(OnboardingWindowPresenter.defaultSize == NSSize(width: 1_080, height: 700))
  #expect(OnboardingWindowPresenter.minimumSize == NSSize(width: 760, height: 520))
}
```

Replace `import Foundation` with:

```swift
import AppKit
import Testing
```

keeping only one `import Testing` line.

- [ ] **Step 6: Run the window test and verify red**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingWindowDeclaresDefaultAndMinimumResponsiveSizes
```

Expected: compilation fails because the two size constants do not exist.

- [ ] **Step 7: Add the window constants and enforce the minimum**

Add to `OnboardingWindowPresenter` in `Sources/FleckApp/OnboardingWindowPresenter.swift`:

```swift
nonisolated static let defaultSize = NSSize(width: 1_080, height: 700)
nonisolated static let minimumSize = NSSize(width: 760, height: 520)
```

In `Coordinator.apply`, replace the hard-coded onboarding size with:

```swift
window.contentMinSize = OnboardingWindowPresenter.minimumSize
window.setContentSize(OnboardingWindowPresenter.defaultSize)
```

In the `.complete` case, restore the normal panel floor before setting its size:

```swift
window.contentMinSize = completedSize
window.setContentSize(completedSize)
```

- [ ] **Step 8: Run both focused presentation suites**

Run:

```sh
swift test --disable-automatic-resolution --filter 'OnboardingPresentation|OnboardingWindow'
```

Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 1**

```sh
git add Sources/FleckApp/OnboardingView.swift \
  Sources/FleckApp/OnboardingWindowPresenter.swift \
  Tests/FleckAppTests/OnboardingPresentationTests.swift \
  Tests/FleckAppTests/OnboardingWindowTests.swift
git commit -m "test: define responsive onboarding metrics"
```

---

### Task 2: Let the real NotesPanel fill an onboarding container

**Files:**
- Modify: `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/OnboardingView.swift`

**Interfaces:**
- Produces: `NotesPanelSizing.storedPreferences` and `.container`.
- Produces: `NotesPanel.init(dictationRuntime:isPinned:sizing:)`, with `.storedPreferences` as the default.
- Consumes: Task 1's `OnboardingLayoutPresentation.minimumEditorHeight` in onboarding only.

- [ ] **Step 1: Write a failing source-contract test for explicit container sizing**

In `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`, load `NotesPanel.swift` and add these assertions inside `OnboardingSourceAuditUsesRealFleckSurfaces`:

```swift
let notesPanelSource = try String(
  contentsOf: onboardingSourceURL()
    .deletingLastPathComponent()
    .appendingPathComponent("NotesPanel.swift"),
  encoding: .utf8
)
#expect(source.contains("sizing: .container"))
#expect(notesPanelSource.contains("enum NotesPanelSizing"))
#expect(notesPanelSource.contains("sizing: NotesPanelSizing = .storedPreferences"))
```

- [ ] **Step 2: Run the source audit and verify red**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingSourceAuditUsesRealFleckSurfaces
```

Expected: the three new expectations fail because sizing mode is absent.

- [ ] **Step 3: Add the sizing mode and preserve the default behavior**

In `Sources/FleckApp/NotesPanel.swift`, add immediately above `NotesPanel`:

```swift
enum NotesPanelSizing: Equatable {
  case storedPreferences
  case container
}
```

Add the property and extend the initializer:

```swift
let sizing: NotesPanelSizing

init(
  dictationRuntime: DictationRuntime,
  isPinned: Bool = false,
  sizing: NotesPanelSizing = .storedPreferences
) {
  self.dictationRuntime = dictationRuntime
  self.isPinned = isPinned
  self.sizing = sizing
}
```

Replace the fixed outer frame with:

```swift
.frame(
  width: sizing == .storedPreferences ? appState.preferences.panelWidth : nil,
  height: sizing == .storedPreferences ? appState.preferences.panelHeight : nil
)
.frame(
  maxWidth: sizing == .container ? .infinity : nil,
  maxHeight: sizing == .container ? .infinity : nil
)
```

- [ ] **Step 4: Request container sizing from onboarding**

In the onboarding editor call in `Sources/FleckApp/OnboardingView.swift`, use:

```swift
NotesPanel(
  dictationRuntime: dictationRuntime,
  isPinned: true,
  sizing: .container
)
```

Keep `.environmentObject(appState)` and all existing editor decoration.

- [ ] **Step 5: Run the source audit and editor-adjacent tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingSourceAudit|AppKitEditor|FocusedDictationEditor|TabDragReorder'
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 2**

```sh
git add Sources/FleckApp/NotesPanel.swift \
  Sources/FleckApp/OnboardingView.swift \
  Tests/FleckAppTests/OnboardingSourceAuditTests.swift
git commit -m "feat: let onboarding contain the real editor"
```

---

### Task 3: Recompose onboarding around a pinned footer and flexible body

**Files:**
- Modify: `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`
- Modify: `Sources/FleckApp/OnboardingView.swift`

**Interfaces:**
- Consumes: `OnboardingLayoutPresentation` from Task 1.
- Consumes: `NotesPanelSizing.container` from Task 2.
- Produces: One flexible `liveEditorCanvas(layout:)` reused by First Note and Dictation.
- Produces: `adaptiveStaticStep(layout:content:)` using native `ViewThatFits` with a body-only `ScrollView` fallback.

- [ ] **Step 1: Write failing source-structure expectations**

Add inside `OnboardingSourceAuditUsesRealFleckSurfaces`:

```swift
for required in [
  "GeometryReader",
  "OnboardingLayoutPresentation(",
  "liveEditorCanvas(layout:",
  "ViewThatFits(in: .vertical)",
  ".layoutPriority(1)",
] {
  #expect(source.contains(required), Comment(rawValue: required))
}
#expect(source.components(separatedBy: "private func liveCanvas").count - 1 == 0)
```

- [ ] **Step 2: Run the source audit and verify red**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingSourceAuditUsesRealFleckSurfaces
```

Expected: the new structure expectations fail and the obsolete `liveCanvas` expectation fails.

- [ ] **Step 3: Make the shell consume finite geometry**

Replace `OnboardingFlowView.body` with a `GeometryReader` that creates
`OnboardingLayoutPresentation(width: geometry.size.width, height: geometry.size.height)`.
Inside it, keep the existing `HStack`, but pass `layout` to rail, step content,
and footer. Apply these constraints:

```swift
stepContent(layout: layout)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .clipped()
  .id(coordinator.visibleStep)
  .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
Divider().opacity(0.45)
OnboardingFooter(coordinator: coordinator, layout: layout)
  .fixedSize(horizontal: false, vertical: true)
```

Give the `HStack` a full finite frame, and replace the old minimum frame with:

```swift
.frame(
  minWidth: OnboardingWindowPresenter.minimumSize.width,
  idealWidth: OnboardingWindowPresenter.defaultSize.width,
  minHeight: OnboardingWindowPresenter.minimumSize.height,
  idealHeight: OnboardingWindowPresenter.defaultSize.height
)
```

- [ ] **Step 4: Split the editor decoration from the step headers**

Delete `liveCanvas(title:detail:)`. Add:

```swift
private func liveEditorCanvas(layout: OnboardingLayoutPresentation) -> some View {
  NotesPanel(
    dictationRuntime: dictationRuntime,
    isPinned: true,
    sizing: .container
  )
  .environmentObject(appState)
  .frame(minHeight: layout.minimumEditorHeight, maxHeight: .infinity)
  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  .overlay {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .stroke(.white.opacity(0.1))
  }
  .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
  .layoutPriority(1)
}
```

Rebuild First Note as a `VStack` containing its two instruction texts and
`liveEditorCanvas(layout:)`, with `layout.contentPadding` and compact vertical
spacing.

- [ ] **Step 5: Flatten the Dictation step**

Replace the nested `liveCanvas` call with this order in a single `VStack`:

```swift
Text("Dictate into the note you just made")
Text("Choose the modifier you want to hold. Fleck's real dictation capsule appears at its configured screen edge.")
Picker("Hold to dictate", selection: $coordinator.selectedModifier) {
  ForEach(DictationModifierKey.allCases, id: \.self) { modifier in
    Text(modifier.displayName).tag(modifier)
  }
}
VStack(alignment: .leading, spacing: 4) {
  Text("Try it in Fleck").font(.headline)
  Text(
    "Click in the editor, then use \(coordinator.selectedModifier.displayName) "
      + "or Fleck's microphone button."
  )
  .foregroundStyle(.secondary)
}
liveEditorCanvas(layout: layout)
```

Retain the existing success label and dictation observation hooks. Use
`layout.contentPadding` once on the outer Dictation view and remove the nested
padding.

- [ ] **Step 6: Add body-only static scrolling and fixed permission actions**

Add a native helper:

```swift
@ViewBuilder
private func adaptiveStaticStep<Content: View>(
  layout: OnboardingLayoutPresentation,
  @ViewBuilder content: () -> Content
) -> some View {
  ViewThatFits(in: .vertical) {
    VStack {
      Spacer(minLength: 0)
      content()
      Spacer(minLength: 0)
    }
    .padding(layout.contentPadding)

    ScrollView {
      content()
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
```

Use it for Welcome and Get Fleck. For Permissions, use a `VStack(spacing: 0)`
whose explanatory/compatibility content is inside `ScrollView`, followed by a
fixed Not Now/Allow row when the cursor is not `.compatibility`. Pass compact
padding metrics instead of hard-coded 40 points. In compatibility rows, use
`HStack(alignment: .firstTextBaseline)` and apply:

```swift
Text(row.detail)
  .multilineTextAlignment(.trailing)
  .fixedSize(horizontal: false, vertical: true)
```

- [ ] **Step 7: Make rail and footer consume responsive metrics**

Add `layout: OnboardingLayoutPresentation` to `OnboardingRail` and
`OnboardingFooter`. Replace hard-coded rail width/padding and footer height with:

```swift
.padding(layout.tier == .regular ? 28 : 20)
.frame(width: layout.railWidth)
```

and:

```swift
.padding(.horizontal, layout.tier == .regular ? 24 : 20)
.frame(height: layout.footerHeight)
```

- [ ] **Step 8: Run focused onboarding and editor tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'Onboarding|AppKitEditor|FocusedDictationEditor|DictationAvailability'
```

Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 3**

```sh
git add Sources/FleckApp/OnboardingView.swift \
  Tests/FleckAppTests/OnboardingSourceAuditTests.swift
git commit -m "feat: make onboarding layout responsive"
```

---

### Task 4: Full verification and review

**Files:**
- Modify only files required by failures directly caused by Tasks 1-3.
- Verify: `docs/superpowers/specs/2026-08-01-responsive-onboarding-layout-design.md`
- Verify: `docs/superpowers/plans/2026-08-01-responsive-onboarding-layout.md`

**Interfaces:**
- Consumes: All responsive layout behavior from Tasks 1-3.
- Produces: Verified release bundle and review evidence; no new production abstraction.

- [ ] **Step 1: Run formatting and conflict checks**

```sh
git diff --check
rg -n '^(<<<<<<<|=======|>>>>>>>)' Sources Tests docs/superpowers || true
```

Expected: no whitespace errors or conflict markers.

- [ ] **Step 2: Run the full deterministic suite**

```sh
swift test --disable-automatic-resolution --no-parallel
```

Expected: every test passes with zero failures.

- [ ] **Step 3: Build the production app bundle**

```sh
Scripts/build-fleck-app.sh
```

Expected: exit 0 and `.build/Fleck.app` exists.

- [ ] **Step 4: Perform isolated manual sizing verification**

Using a disposable Application Support directory or a separate macOS test
account, open every onboarding step and verify 760×520, 919×619, 920×620,
1,080×700, and a larger window. At each size verify the rail and footer remain
visible, the Dictation title/picker/editor coexist, permission actions stay
visible, static overflow scrolls, and the normal Fleck panel dimensions remain
unchanged after completion or relaunch. Repeat the minimum-size pass with
increased text size, VoiceOver, Reduce Motion, and Reduce Transparency.

Expected: no required content is clipped at or above 760×520. Record any
permission/audio/VoiceOver boundary that cannot be automated.

- [ ] **Step 5: Review the complete diff against the spec**

```sh
git diff a9bf200..HEAD -- Sources/FleckApp Tests/FleckAppTests
```

Check every changed line for direct traceability to responsive onboarding,
confirm no commerce or persistence logic changed, and fix all critical or
important findings before continuing.

- [ ] **Step 6: Commit any review-only corrections**

If Step 5 required changes:

```sh
git add Sources/FleckApp/FleckApp.swift \
  Sources/FleckApp/NotesPanel.swift \
  Sources/FleckApp/OnboardingView.swift \
  Sources/FleckApp/OnboardingWindowPresenter.swift \
  Tests/FleckAppTests/OnboardingPresentationTests.swift \
  Tests/FleckAppTests/OnboardingSourceAuditTests.swift \
  Tests/FleckAppTests/OnboardingWindowTests.swift
git commit -m "fix: address responsive onboarding review"
```

If no changes were required, do not create an empty commit.

- [ ] **Step 7: Re-run full verification after any correction**

Run Steps 1-3 again after the final code change.

Expected: clean checks, zero test failures, and a successful app bundle build.
