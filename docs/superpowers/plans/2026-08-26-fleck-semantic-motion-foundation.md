# Fleck Semantic Motion Foundation Implementation Plan

> **For agentic workers:** REQUIRED PROCESS: Follow the repository's Sol Advisor user-visible Luna/Max task lane. Use Superpowers test-driven development within the bounded task. Do not use native subagents.

**Goal:** Give Fleck one small, tested semantic motion policy that later UI packets can consume without changing any existing visible behavior.

**Architecture:** Extend the existing value-type `AppMotion` rather than adding a framework, dependency, environment object, or global view modifier. Add named timing and animation roles, plus one interaction-source decision API. Keep `quick`, `standard`, and `spatial` as compatibility behavior so existing Search, tabs, Trash, Settings, checklist completion, and button styles remain unchanged in this packet.

**Tech Stack:** Swift 6, SwiftUI `Animation`, Swift Testing, Swift Package Manager, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-26-fleck-native-interface-and-motion-system-design.md`

## Global Constraints

- Product personality remains calm, capable, and native.
- Keyboard-initiated presentation is instant.
- Reduce Motion removes spatial motion while retaining brief state/crossfade feedback.
- No animation exceeds 280 ms; no bounce or elastic motion.
- No product dependency, package change, UI rewrite, or new persistence/configuration state.
- Preserve exact existing behavior of `quick`, `standard`, `spatial`, `pressScale`, and `offset`.
- Do not touch `NotesPanel.swift`, Search, the toolbar, folders, tabs, Dictation/Cleanup, packaging, or any unrelated source.
- GitHub writes remain unauthorized.

---

## File Structure

- `Sources/FleckApp/AppMotion.swift`: the sole semantic motion policy and compatibility API.
- `Tests/FleckAppTests/AppMotionTests.swift`: behavior-level regression tests for timing, source policy, Reduce Motion, and compatibility.

No files are created. No dependency or manifest changes are allowed.

### Task 1: Add semantic roles without changing current consumers

**Files:**
- Modify: `Sources/FleckApp/AppMotion.swift`
- Modify: `Tests/FleckAppTests/AppMotionTests.swift`

**Interfaces:**
- Produces `AppInteractionSource` with cases `.pointer`, `.keyboard`, and `.programmatic`.
- Produces semantic duration constants on `AppMotion`: `pressDuration`, `stateDuration`, `selectionDuration`, `revealDuration`, `surfaceDuration`, and `rareDuration`.
- Produces semantic animation properties on `AppMotion`: `press`, `state`, `selection`, `reveal`, `surface`, and `rare`.
- Produces `allowsSpatialMotion(for:) -> Bool`.
- Produces `presentationAnimation(for:) -> Animation?`.
- Preserves `quickDuration == 0.10`, `standardDuration == 0.16`, `quick`, `standard`, `spatial`, `pressScale`, and `offset` with their existing observable behavior.

- [ ] **Step 1: Write the failing policy tests**

Replace `Tests/FleckAppTests/AppMotionTests.swift` with focused tests that retain the two existing regressions and add these behavior checks:

```swift
import Testing

@testable import FleckApp

@Test func reduceMotionRemovesMovementAndPressScaling() {
  let motion = AppMotion(reduceMotion: true)

  #expect(motion.pressScale == 1)
  #expect(motion.offset == 0)
  #expect(!motion.allowsSpatialMotion(for: .pointer))
  #expect(motion.presentationAnimation(for: .pointer) != nil)
}

@Test func standardMotionUsesRestrainedNativeValues() {
  let motion = AppMotion(reduceMotion: false)

  #expect(AppMotion.pressDuration == 0.10)
  #expect(AppMotion.stateDuration == 0.12)
  #expect(AppMotion.selectionDuration == 0.16)
  #expect(AppMotion.revealDuration == 0.18)
  #expect(AppMotion.surfaceDuration == 0.22)
  #expect(AppMotion.rareDuration == 0.26)
  #expect(AppMotion.quickDuration == 0.10)
  #expect(AppMotion.standardDuration == 0.16)
  #expect(motion.pressScale == 0.97)
  #expect(motion.offset == 4)
}

@Test func keyboardPresentationIsInstantAndNeverSpatial() {
  let motion = AppMotion(reduceMotion: false)

  #expect(motion.presentationAnimation(for: .keyboard) == nil)
  #expect(!motion.allowsSpatialMotion(for: .keyboard))
}

@Test func pointerPresentationMayPreserveSpatialContinuity() {
  let motion = AppMotion(reduceMotion: false)

  #expect(motion.presentationAnimation(for: .pointer) != nil)
  #expect(motion.allowsSpatialMotion(for: .pointer))
}

@Test func programmaticPresentationUsesStateFeedbackWithoutSpatialMotion() {
  let motion = AppMotion(reduceMotion: false)

  #expect(motion.presentationAnimation(for: .programmatic) != nil)
  #expect(!motion.allowsSpatialMotion(for: .programmatic))
}
```

The production mutations these tests catch are: reintroducing spatial motion under Reduce Motion, animating keyboard presentation, allowing system events to move surfaces, losing the restrained timing scale, or breaking compatibility constants used by checklist and existing views.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppMotionTests
```

Expected: compilation fails specifically because `AppInteractionSource`, the semantic durations, `allowsSpatialMotion(for:)`, and `presentationAnimation(for:)` do not exist. Fix only test syntax if the failure is unrelated; rerun until the expected missing-API failure is observed.

- [ ] **Step 3: Add the minimal semantic policy**

Implement only this shape in `Sources/FleckApp/AppMotion.swift`:

```swift
#if os(macOS)
  import SwiftUI

  enum AppInteractionSource: Equatable {
    case pointer
    case keyboard
    case programmatic
  }

  struct AppMotion {
    static let pressDuration = 0.10
    static let stateDuration = 0.12
    static let selectionDuration = 0.16
    static let revealDuration = 0.18
    static let surfaceDuration = 0.22
    static let rareDuration = 0.26

    static let quickDuration = pressDuration
    static let standardDuration = selectionDuration

    let reduceMotion: Bool

    var press: Animation {
      .easeOut(duration: Self.pressDuration)
    }

    var state: Animation {
      .easeOut(duration: Self.stateDuration)
    }

    var selection: Animation {
      .easeInOut(duration: Self.selectionDuration)
    }

    var reveal: Animation {
      .easeOut(duration: Self.revealDuration)
    }

    var surface: Animation {
      .easeOut(duration: Self.surfaceDuration)
    }

    var rare: Animation {
      .easeOut(duration: Self.rareDuration)
    }

    var quick: Animation {
      .easeOut(duration: Self.quickDuration)
    }

    var standard: Animation {
      .easeOut(duration: Self.standardDuration)
    }

    var spatial: Animation? {
      reduceMotion ? nil : standard
    }

    var pressScale: CGFloat {
      reduceMotion ? 1 : 0.97
    }

    var offset: CGFloat {
      reduceMotion ? 0 : 4
    }

    func allowsSpatialMotion(for source: AppInteractionSource) -> Bool {
      !reduceMotion && source == .pointer
    }

    func presentationAnimation(for source: AppInteractionSource) -> Animation? {
      switch source {
      case .keyboard:
        nil
      case .programmatic:
        state
      case .pointer:
        reduceMotion ? state : surface
      }
    }
  }
#endif
```

Do not update consumers in this task. Do not add protocols, generic role enums, environment keys, modifiers, or configuration knobs.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppMotionTests
```

Expected: all five AppMotion tests pass with exit status 0.

- [ ] **Step 5: Run compatibility and broader verification**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter ChecklistMarkerDrawingTests
swift test --disable-automatic-resolution --no-parallel
swift build --disable-automatic-resolution -c release --product Fleck
```

Expected:

- Checklist completion continues to consume `AppMotion.quickDuration` and passes.
- The full Swift test suite passes with no new failure attributable to the diff.
- The release Fleck product builds successfully.

- [ ] **Step 6: Inspect scope and commit locally**

Run:

```bash
git diff --check
git status --short --branch
git diff -- Sources/FleckApp/AppMotion.swift Tests/FleckAppTests/AppMotionTests.swift
git add Sources/FleckApp/AppMotion.swift Tests/FleckAppTests/AppMotionTests.swift
git commit -m "feat: add semantic motion policy"
```

Expected: exactly the two owned files differ before commit; the worktree is clean afterward; report the exact commit SHA. Do not push or open a pull request.

## Parent Integration Gate

The primary Sol session must inspect every changed line, rerun the focused tests and release build, and obtain a fresh `sol_advisor_sol_reviewer` verdict of exactly `ship`. Only then may a dependent notice, navigation, chrome, Search, or destination-surface packet begin. This foundation does not require launching or replacing Fleck because it intentionally changes no current consumer or visible behavior.
