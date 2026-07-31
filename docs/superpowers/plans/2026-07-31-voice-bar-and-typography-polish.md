# Fleck Voice Bar and Typography Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Fleck's static dictation symbol with a compact live audio-reactive voice bar and make Avenir Next at 17 points the migration-safe default note typography.

**Architecture:** Keep microphone buffers inside the existing speech engines and forward only capture-owned normalized levels through `DictationCoordinator` to one persistent `DictationWaveformModel` owned by `DictationCapsuleController`. Render every capsule phase inside the existing non-activating panel with a fixed 32-point active thickness. Add one backward-compatible typography preference version, then centralize preference-derived AppKit fonts and default paragraph rhythm without rewriting explicit RTF formatting.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation level callbacks, Swift Testing, Swift Package Manager; macOS 14 minimum; no new package or asset dependency.

## Global Constraints

- The bottom listening bar is exactly 196 by 32 points.
- The bottom idle mark is exactly 40 by 26 points.
- Side-docked active bars intrude exactly 32 points into screen content.
- Active phases may lengthen along the dock edge but never exceed 32 points in thickness.
- Listening contains a recording indicator, eleven audio-reactive bars, and elapsed time, with no visible `Listening` label.
- Silent pauses retain a subtle deterministic moving baseline and never stop dictation.
- Microphone levels remain ephemeral: never persist, log, add to history, or expose to agents.
- Visual level updates are capped at 30 frames per second and stale capture levels are rejected.
- Reduce Motion uses opacity and a low-rate level indication instead of interpolated bar, frame, or symbol motion.
- Fleck chrome remains in semantic system typography.
- New and untouched-default preferences use Avenir Next Regular at 17 points; note titles use Avenir Next Semibold.
- Existing non-default font families or sizes and explicit RTF formatting remain unchanged.
- Existing dictation, cleanup, routing, recovery, docking, Spaces, privacy, and editor-stability contracts remain authoritative.

---

### Task 1: Backward-Compatible Typography Defaults

**Files:**
- Modify: `Sources/FleckCore/AppPreferences.swift`
- Modify: `Tests/FleckCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Produces: `AppPreferences.currentEditorTypographyVersion: Int`
- Produces: `AppPreferences.editorTypographyVersion: Int`
- Produces: default `fontFamily == "Avenir Next"` and `fontSize == 17`
- Consumes: existing Codable preference persistence

- [ ] **Step 1: Write failing migration tests**

Add focused tests:

```swift
@Test func newPreferencesUseAvenirReadingDefaults() {
  let value = AppPreferences()
  #expect(value.fontFamily == "Avenir Next")
  #expect(value.fontSize == 17)
  #expect(value.editorTypographyVersion == AppPreferences.currentEditorTypographyVersion)
}

@Test func untouchedLegacyTypographyMigratesOnce() throws {
  let data = Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":15}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(value.fontFamily == "Avenir Next")
  #expect(value.fontSize == 17)
  #expect(value.editorTypographyVersion == AppPreferences.currentEditorTypographyVersion)
}

@Test func legacyCustomTypographyIsPreserved() throws {
  let family = try JSONDecoder().decode(
    AppPreferences.self,
    from: Data(#"{"fontFamily":"Menlo","fontSize":15}"#.utf8)
  )
  let size = try JSONDecoder().decode(
    AppPreferences.self,
    from: Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":19}"#.utf8)
  )
  #expect(family.fontFamily == "Menlo")
  #expect(family.fontSize == 15)
  #expect(size.fontFamily == ".AppleSystemUIFont")
  #expect(size.fontSize == 19)
}

@Test func explicitSystemChoiceAfterMigrationRoundTrips() throws {
  let value = AppPreferences(
    fontFamily: ".AppleSystemUIFont",
    fontSize: 15,
    editorTypographyVersion: AppPreferences.currentEditorTypographyVersion
  )
  let decoded = try JSONDecoder().decode(
    AppPreferences.self,
    from: JSONEncoder().encode(value)
  )
  #expect(decoded.fontFamily == ".AppleSystemUIFont")
  #expect(decoded.fontSize == 15)
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'newPreferencesUseAvenirReadingDefaults|untouchedLegacyTypographyMigratesOnce|legacyCustomTypographyIsPreserved|explicitSystemChoiceAfterMigrationRoundTrips'
```

Expected: compilation fails because the version property and initializer parameter do not exist, and the old defaults remain System/15.

- [ ] **Step 3: Implement the minimal Codable migration**

Add:

```swift
public static let currentEditorTypographyVersion = 1
public var editorTypographyVersion: Int
```

Extend the initializer:

```swift
fontFamily: String = "Avenir Next",
fontSize: Double = 17,
editorTypographyVersion: Int = AppPreferences.currentEditorTypographyVersion
```

Add `editorTypographyVersion` to `CodingKeys`. In `init(from:)`, decode the raw legacy family, size, and optional version before delegating:

```swift
let decodedFamily =
  try c.decodeIfPresent(String.self, forKey: .fontFamily)
  ?? "Avenir Next"
let decodedSize =
  try c.decodeIfPresent(Double.self, forKey: .fontSize)
  ?? 17
let decodedVersion =
  try c.decodeIfPresent(Int.self, forKey: .editorTypographyVersion)
let migratesUntouchedDefault =
  decodedVersion == nil
  && decodedFamily == ".AppleSystemUIFont"
  && decodedSize == 15

self.init(
  fontFamily: migratesUntouchedDefault ? "Avenir Next" : decodedFamily,
  fontSize: migratesUntouchedDefault ? 17 : decodedSize,
  editorTypographyVersion:
    decodedVersion ?? Self.currentEditorTypographyVersion,
  // preserve every existing decoded field
)
```

- [ ] **Step 4: Update old-default assertions without weakening compatibility**

Existing tests that use System/15 only as a minimal old JSON fixture should assert the new migrated family and size where relevant. Fixtures that verify unrelated dictation defaults remain valid and must not be deleted.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter FleckCoreTests.AppPreferencesTests
git diff --check
```

Expected: all preference tests pass and the diff is clean.

Commit:

```bash
git add Sources/FleckCore/AppPreferences.swift \
  Tests/FleckCoreTests/AppPreferencesTests.swift
git commit -m "feat: migrate default note typography"
```

---

### Task 2: Preference-Derived Note Typography

**Files:**
- Create: `Sources/FleckApp/EditorTypography.swift`
- Create: `Tests/FleckAppTests/EditorTypographyTests.swift`
- Modify: `Sources/FleckApp/NativeRichTextEditor.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/NoteTextAppender.swift`
- Modify: `Sources/FleckApp/AgentRichTextMutator.swift`
- Modify: `Tests/FleckAppTests/FocusedDictationEditorTests.swift`
- Modify: `Tests/FleckAppTests/NoteTextAppenderTests.swift`
- Modify: `Tests/FleckAppTests/AgentRichTextMutatorTests.swift`

**Interfaces:**
- Consumes: `AppPreferences.fontFamily` and `AppPreferences.fontSize`
- Produces: `EditorTypography.bodyFont(family:size:fontProvider:) -> NSFont`
- Produces: `EditorTypography.titleFont(family:) -> Font`
- Produces: `EditorTypography.defaultParagraphStyle(fontSize:) -> NSParagraphStyle`
- Produces: `EditorTypography.defaultAttributes(family:size:) -> [NSAttributedString.Key: Any]`

- [ ] **Step 1: Write failing typography resolution tests**

Create `EditorTypographyTests.swift`:

```swift
@Test @MainActor func editorTypographyUsesAvenirAndOpenBodyRhythm() throws {
  let font = EditorTypography.bodyFont(family: "Avenir Next", size: 17)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: 17)

  #expect(font.familyName == "Avenir Next")
  #expect(font.pointSize == 17)
  #expect(paragraph.minimumLineHeight == 27)
  #expect(paragraph.maximumLineHeight == 27)
}

@Test @MainActor func editorTypographyFallsBackWhenFamilyIsUnavailable() {
  let font = EditorTypography.bodyFont(
    family: "Missing Fleck Font",
    size: 17,
    fontProvider: { _, _ in nil }
  )
  #expect(font.familyName == NSFont.systemFont(ofSize: 17).familyName)
}
```

Add regressions proving:

- Plain editor loads apply body font plus the default paragraph style.
- Existing RTF with an explicit custom font and paragraph style is not rewritten.
- Changing only typography updates typing attributes without replacing text storage, selection, or undo.
- Dictated append and agent append receive the same default body font and paragraph style.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'EditorTypographyTests|FocusedDictationEditorTests|NoteTextAppenderTests|AgentRichTextMutatorTests'
```

Expected: compilation fails because `EditorTypography` does not exist and new paragraph-style assertions fail.

- [ ] **Step 3: Implement the centralized typography helper**

Create:

```swift
import AppKit
import SwiftUI

enum EditorTypography {
  static let defaultLineHeight: CGFloat = 27

  static func bodyFont(
    family: String,
    size: CGFloat,
    fontProvider: (String, CGFloat) -> NSFont? = { family, size in
      NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: size),
        toFamily: family
      )
    }
  ) -> NSFont {
    if family == ".AppleSystemUIFont" {
      return .systemFont(ofSize: size)
    }
    let resolved = fontProvider(family, size)
    guard resolved?.familyName == family else {
      return .systemFont(ofSize: size)
    }
    return resolved!
  }

  static func defaultParagraphStyle(fontSize: CGFloat) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    let lineHeight = fontSize / 17 * defaultLineHeight
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    return style
  }

  static func defaultAttributes(
    family: String,
    size: CGFloat
  ) -> [NSAttributedString.Key: Any] {
    [
      .font: bodyFont(family: family, size: size),
      .paragraphStyle: defaultParagraphStyle(fontSize: size),
    ]
  }

  static func titleFont(family: String) -> Font {
    family == ".AppleSystemUIFont"
      ? .title3.weight(.semibold)
      : .custom(family, size: 20).weight(.semibold)
  }
}
```

Do not add a font bundle or package.

- [ ] **Step 4: Apply defaults without rewriting explicit RTF**

In `NativeRichTextEditor`:

- Replace the local `configuredFont()` implementation with `EditorTypography.bodyFont`.
- Add the default paragraph style to `typingAttributes`.
- Apply font and paragraph style across the document only when loading plain text without an RTF sidecar.
- When loading RTF, preserve storage attributes and update only future typing attributes.
- When the preference changes, update typing attributes without calling `setAttributedString`, moving selection, or clearing undo.

In `NotesPanel`, change only the editable title:

```swift
.font(EditorTypography.titleFont(family: appState.preferences.fontFamily))
```

In `NoteTextAppender` and `AgentRichTextMutator`, include `EditorTypography.defaultParagraphStyle(fontSize:)` in default attributes used for newly appended unformatted content. Preserve inherited explicit attributes when appending to a formatted run.

- [ ] **Step 5: Verify editor stability and commit**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'EditorTypographyTests|FocusedDictationEditorTests|NoteTextAppenderTests|AgentRichTextMutatorTests'
git diff --check
```

Expected: focused suites pass, including the stale-model editor regression from `d99859f`.

Commit:

```bash
git add Sources/FleckApp/EditorTypography.swift \
  Sources/FleckApp/NativeRichTextEditor.swift \
  Sources/FleckApp/NotesPanel.swift \
  Sources/FleckApp/NoteTextAppender.swift \
  Sources/FleckApp/AgentRichTextMutator.swift \
  Tests/FleckAppTests/EditorTypographyTests.swift \
  Tests/FleckAppTests/FocusedDictationEditorTests.swift \
  Tests/FleckAppTests/NoteTextAppenderTests.swift \
  Tests/FleckAppTests/AgentRichTextMutatorTests.swift
git commit -m "feat: apply Fleck note typography"
```

---

### Task 3: Capture-Owned Audio Level Boundary

**Files:**
- Modify: `Sources/FleckApp/DictationCoordinator.swift`
- Modify: `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Interfaces:**
- Produces: `DictationCoordinator.setLevelObserver(_:)`
- Consumes: existing `SpeechEngine.start(provisional:level:)`

- [ ] **Step 1: Write failing level-ownership tests**

Extend `FakeSpeechEngine` to retain and emit its level callback:

```swift
private var level: (@MainActor (Float) -> Void)?

func emitLevel(_ value: Float) {
  level?(value)
}
```

Add:

```swift
@Test @MainActor func coordinatorForwardsOnlyActiveCaptureLevels() async throws {
  let fixture = try Fixture()
  var levels: [Float] = []
  fixture.coordinator.setLevelObserver { levels.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)
  fixture.standard.emitLevel(0.42)
  await fixture.coordinator.cancel()
  fixture.standard.emitLevel(0.9)

  #expect(levels == [0.42, 0])
}

@Test @MainActor func failedStartResetsTheLevel() async throws {
  let fixture = try Fixture()
  fixture.standard.startError = TestError.failed
  var levels: [Float] = []
  fixture.coordinator.setLevelObserver { levels.append($0) }

  await fixture.coordinator.start(mode: .smartCapture)

  #expect(levels.last == 0)
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'coordinatorForwardsOnlyActiveCaptureLevels|failedStartResetsTheLevel'
```

Expected: compilation fails because `setLevelObserver` and fake level emission do not exist.

- [ ] **Step 3: Implement capture-ID-guarded forwarding**

In `DictationCoordinator` add:

```swift
private var levelObserver: (@MainActor (Float) -> Void)?

func setLevelObserver(_ observer: (@MainActor (Float) -> Void)?) {
  levelObserver = observer
}
```

Pass a capture-bound closure to the engine:

```swift
level: { [weak self] level in
  guard let self, self.capture?.id == id else { return }
  self.levelObserver?(level)
}
```

Emit `0` exactly once when the active capture leaves listening through finish, cancellation, failed start, resource release, or shutdown. Do not add levels to `DictationCoordinatorEvent`.

- [ ] **Step 4: Verify coordinator behavior**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'DictationCoordinatorTests'
```

Expected: all coordinator tests pass; no old capture emits levels into a later session.

- [ ] **Step 5: Commit**

```bash
git add Sources/FleckApp/DictationCoordinator.swift \
  Tests/FleckAppTests/DictationCoordinatorTests.swift
git commit -m "feat: forward active dictation levels"
```

---

### Task 4: Compact Audio-Reactive Capsule

**Files:**
- Create: `Sources/FleckApp/DictationWaveform.swift`
- Create: `Tests/FleckAppTests/DictationWaveformTests.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Sources/FleckApp/DictationCapsule.swift`
- Modify: `Tests/FleckAppTests/DictationAccessibilityTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Interfaces:**
- Consumes: `DictationCoordinator.setLevelObserver(_:)` from Task 3
- Produces: `DictationWaveformModel.receive(level:now:)`
- Produces: `DictationWaveformModel.reset()`
- Produces: `DictationWaveformModel.barLevels(at:reduceMotion:) -> [CGFloat]`
- Produces: `DictationCapsuleController.updateAudioLevel(_:)`

- [ ] **Step 1: Write failing waveform model tests**

Create deterministic tests with injected timestamps:

```swift
@Test @MainActor func waveformClampsSmoothsAndKeepsElevenBars() {
  let model = DictationWaveformModel()
  model.beginListening(at: .init(timeIntervalSince1970: 100))
  model.receive(level: 2, now: .init(timeIntervalSince1970: 100.04))
  let loud = model.barLevels(
    at: .init(timeIntervalSince1970: 100.05),
    reduceMotion: false
  )
  #expect(loud.count == 11)
  #expect(loud.allSatisfy { (0...1).contains($0) })
  #expect(loud[5] > loud[0])
}

@Test @MainActor func waveformUsesAQuietMovingBaselineDuringSilence() {
  let model = DictationWaveformModel()
  model.beginListening(at: .init(timeIntervalSince1970: 10))
  let first = model.barLevels(
    at: .init(timeIntervalSince1970: 10.1),
    reduceMotion: false
  )
  let second = model.barLevels(
    at: .init(timeIntervalSince1970: 10.2),
    reduceMotion: false
  )
  #expect(first != second)
  #expect(first.max()! < 0.25)
}

@Test @MainActor func waveformThrottlesAndResets() {
  let model = DictationWaveformModel()
  let start = Date(timeIntervalSince1970: 20)
  model.beginListening(at: start)
  model.receive(level: 0.7, now: start.addingTimeInterval(0.04))
  let accepted = model.energy
  model.receive(level: 0.1, now: start.addingTimeInterval(0.05))
  #expect(model.energy == accepted)
  model.reset()
  #expect(model.energy == 0)
  #expect(model.listeningStartedAt == nil)
}
```

Update geometry/accessibility tests to require:

```swift
#expect(DictationCapsuleController.idleSize == CGSize(width: 40, height: 26))
#expect(DictationCapsuleController.listeningSize == CGSize(width: 196, height: 32))
#expect(DictationCapsuleStatus.listening.presentation.visibleText == nil)
#expect(DictationCapsuleStatus.listening.presentation.voiceOverText == "Dictation listening")
```

Add bottom and side frame assertions for every active status.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'DictationWaveformTests|DictationAccessibilityTests'
```

Expected: compilation fails for the missing model and old 48-by-36 / 280-by-52 geometry fails.

- [ ] **Step 3: Implement one bounded waveform model**

Create a `@MainActor final class DictationWaveformModel: ObservableObject` with:

```swift
@Published private(set) var energy: CGFloat = 0
private(set) var listeningStartedAt: Date?
private var lastAcceptedLevelAt: Date?

func beginListening(at now: Date = Date()) {
  listeningStartedAt = now
  lastAcceptedLevelAt = nil
  energy = 0
}

func receive(level: Float, now: Date = Date()) {
  guard listeningStartedAt != nil else { return }
  if let lastAcceptedLevelAt,
    now.timeIntervalSince(lastAcceptedLevelAt) < 1.0 / 30.0
  {
    return
  }
  self.lastAcceptedLevelAt = now
  let normalized = min(max((CGFloat(level) - 0.015) / 0.24, 0), 1)
  let coefficient: CGFloat = normalized > energy ? 0.65 : 0.18
  energy += (normalized - energy) * coefficient
}

func reset() {
  energy = 0
  listeningStartedAt = nil
  lastAcceptedLevelAt = nil
}
```

Use eleven stable center-weighted bar coefficients. `barLevels` combines those coefficients with a deterministic low-amplitude sine baseline when `energy` is near zero. Under Reduce Motion, remove phase interpolation and return a low-rate symmetric level shape.

- [ ] **Step 4: Replace the static symbol with one continuous capsule composition**

In `DictationCapsuleController`:

```swift
static let idleSize = CGSize(width: 40, height: 26)
static let listeningSize = CGSize(width: 196, height: 32)
static let activeSize = CGSize(width: 280, height: 32)
let waveformModel: DictationWaveformModel

func updateAudioLevel(_ level: Float) {
  waveformModel.receive(level: level)
}
```

Begin/reset the waveform model when entering/leaving `.listening`. Do not recreate it in `installContent`.

Update `DictationCapsulePresentation` with an explicit visual mode:

```swift
enum DictationCapsuleVisualMode: Equatable {
  case idle
  case listening
  case progress
  case success
  case warning
  case failure
}
```

Render:

- Idle: compact waveform mark.
- Listening: accent dot, eleven-bar waveform, monospaced elapsed timer.
- Finalizing/cleaning/routing/repair: three-point native progress treatment plus existing concise copy.
- Saved: checkmark plus destination and recovery action.
- Failure: exclamation mark plus concise copy.

Use `TimelineView(.animation(minimumInterval: 1.0 / 30.0))` only for the listening subtree. The elapsed timer renders whole seconds and has `.accessibilityHidden(true)`.

Keep `.regularMaterial` with the existing capsule shape. When `accessibilityReduceTransparency` is true, substitute a high-contrast opaque system background. Keep panel focus and action behavior unchanged.

- [ ] **Step 5: Make geometry phase- and dock-aware**

Replace the binary idle/active size selection with:

```swift
private func size(for status: DictationCapsuleStatus) -> CGSize {
  switch status {
  case .idle:
    Self.idleSize
  case .listening:
    Self.listeningSize
  case .finalizing, .cleaning, .routing, .saved,
       .savedWithoutCleanup, .repairingModel, .failed:
    Self.activeSize
  }
}
```

The existing `frame(for:size:in:)` orientation swap preserves 32-point side intrusion. Reduce Motion sets the final frame directly and crossfades content; it does not animate the frame.

- [ ] **Step 6: Connect authoritative runtime levels**

In `DictationRuntime.init`, register the Task 3 observer:

```swift
coordinator.setLevelObserver { [weak self] level in
  guard let self else { return }
  switch self.phase {
  case .arming, .listening:
    self.capsuleController.updateAudioLevel(level)
  case .idle, .finalizing, .cleaning, .routing, .saved, .failed:
    self.capsuleController.updateAudioLevel(0)
  }
}
```

Add a runtime test proving `.arming`/`.listening` levels reach the model, terminal phases reset it, disabling the capsule stops display updates, and re-enabling it cannot revive an old energy value.

- [ ] **Step 7: Verify focused capsule behavior**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter 'DictationWaveformTests|DictationAccessibilityTests|DictationSettingsTests'
git diff --check
```

Expected: waveform, geometry, lifecycle, accessibility, and runtime tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/FleckApp/DictationWaveform.swift \
  Sources/FleckApp/FleckApp.swift \
  Sources/FleckApp/DictationCapsule.swift \
  Tests/FleckAppTests/DictationWaveformTests.swift \
  Tests/FleckAppTests/DictationAccessibilityTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: polish the Fleck voice bar"
```

---

### Task 5: Integrated Regression and Packaged-App Validation

**Files:**
- Modify only if a failing integration test proves necessary:
  - `Sources/FleckApp/DictationCapsule.swift`
  - `Sources/FleckApp/DictationWaveform.swift`
  - `Sources/FleckApp/NativeRichTextEditor.swift`
  - Corresponding focused test file

**Interfaces:**
- Consumes all Tasks 1–4 outputs
- Produces a release-built `.build/Fleck.app`

- [ ] **Step 1: Run the complete serialized debug suite**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel
```

Expected: every suite passes. Keep `--no-parallel`; repository commit `658f6da` established serialized macOS validation because IPC tests share process resources.

- [ ] **Step 2: Run the release build**

Run:

```bash
swift build -c release --disable-automatic-resolution --product Fleck
```

Expected: release product builds without warnings introduced by this plan.

- [ ] **Step 3: Build the packaged app**

Run:

```bash
Scripts/build-fleck-app.sh
test -d .build/Fleck.app
test -x .build/Fleck.app/Contents/MacOS/Fleck
```

Expected: `.build/Fleck.app` exists with an executable Fleck binary.

- [ ] **Step 4: Run surgical diff and repository checks**

Run:

```bash
git diff --check
git status --short
git diff --stat HEAD~4..HEAD
```

Expected: only the files named by Tasks 1–4 plus this plan/spec are changed; `.superpowers/brainstorm/` remains untracked and is not committed.

- [ ] **Step 5: Perform manual macOS smoke testing**

Open:

```bash
open -n .build/Fleck.app
```

Verify:

1. Idle bottom bar is visibly thinner and does not take focus.
2. Right Option hold and double-tap both activate the 196-by-32 listening bar outside Fleck.
3. Soft/loud speech changes bar heights; a ten-second pause keeps a calm moving baseline.
4. Release preserves 32-point height through cleanup, routing, success, and failure.
5. Bottom/left/right docking, multiple Spaces, and a second display retain correct intrusion.
6. Reduce Motion and Reduce Transparency remain legible.
7. A new note uses Avenir Next Semibold title and 17-point Avenir Next body.
8. A custom font preference, rich formatting, lists, checklists, selection, undo, long-note bottom typing, dictation insertion, and agent append remain correct.

- [ ] **Step 6: Create the final checkpoint**

If manual testing requires no correction, no extra source commit is needed. If it reveals a reproducible issue, return to the owning task, add one focused failing regression beside that task's existing tests, make the smallest correction in the exact source file named by that task, and rerun Steps 1–4 before committing the corrected source and its regression together.
