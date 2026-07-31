# Fleck First-Launch Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Fleck's mandatory, resumable Guided Canvas onboarding around the real notes and dictation runtime, ending at an honest trial/purchase/restore boundary.

**Architecture:** Persist a versioned onboarding cursor inside `AppPreferences`, resolve fresh-versus-existing workspaces after `LocalStore` load, and coordinate navigation through one main-actor `OnboardingCoordinator`. Reuse the existing `pinned-notes` scene, `NotesPanel`, `AppState`, and `DictationRuntime`; add only a narrow access-actions protocol whose current production implementation is explicitly unavailable until the later StoreKit/trial phase.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, Speech, Foundation Models when available, Swift Testing, SwiftPM, macOS 14+.

## Global Constraints

- Start from `codex/fix-agent-setup-migration` commit `de264c5`; preserve unrelated work.
- This plan implements onboarding only. Do not implement StoreKit, trial persistence, Keychain entitlement caching, read-only access gates, RevenueCat, iCloud, sandbox changes, signing, notarization, or App Store Connect.
- Onboarding is mandatory for a fresh store, has no skip, and resumes at the next incomplete rail or permission step.
- Existing root/recovery workspaces with no onboarding marker are exempt from first-launch education; this exemption does not grant an entitlement.
- The fresh `inProgress(.welcome)` marker must be the first persisted change, before another preference change can convert the snapshot from fresh to root.
- The five rail steps are exactly Welcome, Your first note, Dictation, Permissions, and Get Fleck.
- Back is transient; forward progress is persisted before the saved cursor advances.
- Microphone, Speech Recognition, and Input Monitoring are requested individually and only after the matching user action. Every permission can be deferred with `Not Now`.
- Do not create another note editor, workspace, dictation coordinator, permission state machine, or screenshot imitation.
- Dictation copy always uses the selected `DictationModifierKey.displayName`.
- The real `DictationCapsulePanel` remains at its configured screen edge; do not embed a second capsule in onboarding.
- Trial copy must say: no credit card, no Apple purchase sheet, and no automatic charge.
- The lifetime price must come from the later StoreKit provider's localized display price; no currency amount may appear in onboarding source.
- Completion requires the access provider's authoritative state to be active trial or purchased.
- The app target contains no fake access success, launch-argument bypass, hidden completion button, or UserDefaults entitlement.
- The unavailable production access adapter leaves Get Fleck incomplete and makes this branch release-blocked until the later access phase.
- The existing `pinned-notes` scene becomes onboarding while incomplete and normal `NotesPanel(isPinned: true)` after completion; no second notes scene is created.
- The selected visual direction is dark charcoal/glass, left progress rail, focused live canvas, persistent footer, restrained macOS blue, and native spacing.
- macOS 14 remains the deployment minimum.
- Automated evidence must remain separate from physical audio, TCC, Input Monitoring, Apple Intelligence, StoreKit, signing, notarization, and App Store evidence.

## File Map

### New production files

- `Sources/FleckCore/OnboardingProgress.swift` — versioned persisted onboarding model.
- `Sources/FleckApp/FleckAccessActions.swift` — access-facing protocol, result model, and unavailable production adapter.
- `Sources/FleckApp/OnboardingCoordinator.swift` — bootstrap policy, navigation, starter-note preparation, permissions, and completion rules.
- `Sources/FleckApp/OnboardingView.swift` — Guided Canvas shell, rail, step content, permission substeps, compatibility, and Get Fleck UI.
- `Sources/FleckApp/OnboardingWindowPresenter.swift` — native configuration and foregrounding of the existing `pinned-notes` window.

### Modified production files

- `Sources/FleckCore/AppPreferences.swift` — optional onboarding progress encoding.
- `Sources/FleckApp/AppState.swift` — expose initial snapshot source and provide transactional onboarding-progress persistence.
- `Sources/FleckApp/DictationAvailability.swift` — granular permissions and reasoned Foundation Models compatibility.
- `Sources/FleckApp/FleckApp.swift` — construct one onboarding coordinator and gate the two existing notes surfaces.
- `Sources/FleckApp/NotesPanel.swift` — only if a minimal presentation hook is required to keep the live panel usable inside the onboarding canvas.
- `Sources/FleckApp/SettingsView.swift` — consume the shared compatibility presentation without changing Settings scope.

### New tests

- `Tests/FleckCoreTests/OnboardingProgressTests.swift`
- `Tests/FleckAppTests/OnboardingBootstrapTests.swift`
- `Tests/FleckAppTests/OnboardingAccessTests.swift`
- `Tests/FleckAppTests/OnboardingCoordinatorTests.swift`
- `Tests/FleckAppTests/OnboardingPresentationTests.swift`
- `Tests/FleckAppTests/OnboardingWindowTests.swift`
- `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`

### Modified tests

- `Tests/FleckCoreTests/AppPreferencesTests.swift`
- `Tests/FleckAppTests/AppStateTests.swift`
- `Tests/FleckAppTests/AppStateDictationTests.swift`
- `Tests/FleckAppTests/DictationAvailabilityTests.swift`
- `Tests/FleckAppTests/DictationSettingsTests.swift`

---

### Task 1: Persisted Progress and Fresh/Existing Bootstrap

**Files:**
- Create: `Sources/FleckCore/OnboardingProgress.swift`
- Modify: `Sources/FleckCore/AppPreferences.swift`
- Modify: `Sources/FleckApp/AppState.swift`
- Create: `Tests/FleckCoreTests/OnboardingProgressTests.swift`
- Modify: `Tests/FleckCoreTests/AppPreferencesTests.swift`
- Modify: `Tests/FleckAppTests/AppStateTests.swift`

**Interfaces:**
- Produces: `OnboardingStep`, `OnboardingPermissionCursor`, and `OnboardingProgress`.
- Produces: `AppPreferences.onboardingProgress: OnboardingProgress?`.
- Produces: `AppState.initialSnapshotSource: LocalStoreSnapshotSource?`.
- Produces: `AppState.persistOnboardingProgress(_:) async throws`.
- Preserves: the existing atomic workspace/preferences snapshot and optimistic rollback behavior.

- [ ] **Step 1: Write failing progress-model tests**

Add exact model and round-trip expectations:

```swift
@Test func onboardingProgressRoundTripsEveryCursor() throws {
  for step in OnboardingStep.allCases {
    let value = OnboardingProgress(
      flowVersion: OnboardingProgress.currentFlowVersion,
      status: .inProgress(step: step),
      permissionCursor: .microphone
    )
    let decoded = try JSONDecoder().decode(
      OnboardingProgress.self,
      from: JSONEncoder().encode(value)
    )
    #expect(decoded == value)
  }
}

@Test func onboardingProgressHasStableOrderAndVersion() {
  #expect(OnboardingStep.allCases == [
    .welcome, .firstNote, .dictation, .permissions, .getFleck,
  ])
  #expect(OnboardingPermissionCursor.allCases == [
    .microphone, .speechRecognition, .inputMonitoring, .compatibility,
  ])
  #expect(OnboardingProgress.currentFlowVersion == 1)
}
```

Extend `AppPreferencesTests`:

```swift
@Test func oldPreferencesHaveNoOnboardingMarker() throws {
  let old = Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":15}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: old)
  #expect(value.onboardingProgress == nil)
}
```

- [ ] **Step 2: Run the model tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingProgress|oldPreferencesHaveNoOnboardingMarker'
```

Expected: compilation fails because the onboarding types and preference property do not exist.

- [ ] **Step 3: Add the minimal persisted model**

Create:

```swift
import Foundation

public enum OnboardingStep: String, Codable, CaseIterable, Sendable {
  case welcome
  case firstNote
  case dictation
  case permissions
  case getFleck
}

public enum OnboardingPermissionCursor: String, Codable, CaseIterable, Sendable {
  case microphone
  case speechRecognition
  case inputMonitoring
  case compatibility
}

public struct OnboardingProgress: Codable, Equatable, Sendable {
  public static let currentFlowVersion = 1

  public enum Status: Codable, Equatable, Sendable {
    case inProgress(step: OnboardingStep)
    case completed
    case existingUserExempt
  }

  public var flowVersion: Int
  public var status: Status
  public var permissionCursor: OnboardingPermissionCursor

  public init(
    flowVersion: Int = currentFlowVersion,
    status: Status,
    permissionCursor: OnboardingPermissionCursor = .microphone
  ) {
    self.flowVersion = flowVersion
    self.status = status
    self.permissionCursor = permissionCursor
  }
}
```

Add the optional property, initializer parameter, coding key, assignment, and `decodeIfPresent` path to `AppPreferences`. Missing data must remain `nil`; do not silently classify a user in the decoder.

- [ ] **Step 4: Run core tests and verify GREEN**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingProgress|AppPreferences'
```

Expected: all progress and preference tests pass.

- [ ] **Step 5: Write failing AppState source and transactional-save tests**

Add:

```swift
@Test @MainActor func appStateExposesFreshInitialSnapshotSource() async {
  let root = temporaryTestDirectory()
  let state = AppState(store: LocalStore(rootURL: root))
  await state.waitUntilInitialLoad()
  #expect(state.initialSnapshotSource == .fresh)
}

@Test @MainActor func onboardingProgressPersistenceRollsBackAfterFailure() async {
  let state = AppState(
    saveOperation: { _, _, _ in throw TestError.failed }
  )
  await state.waitUntilInitialLoad()
  let progress = OnboardingProgress(status: .inProgress(step: .welcome))

  await #expect(throws: TestError.self) {
    try await state.persistOnboardingProgress(progress)
  }
  #expect(state.preferences.onboardingProgress == nil)
}
```

Also test root and recovery source propagation using existing `LocalStore` fixtures.

- [ ] **Step 6: Run AppState tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'appStateExposesFreshInitialSnapshotSource|onboardingProgressPersistence'
```

Expected: compilation fails because source exposure and persistence do not exist.

- [ ] **Step 7: Implement source exposure and rollback-safe persistence**

Add:

```swift
@Published private(set) var initialSnapshotSource: LocalStoreSnapshotSource?

func persistOnboardingProgress(_ progress: OnboardingProgress) async throws {
  let previous = preferences.onboardingProgress
  updatePreferences { $0.onboardingProgress = progress }
  do {
    try await saveNow(transactionOwned: true).value
  } catch {
    if preferences.onboardingProgress == progress {
      updatePreferences { $0.onboardingProgress = previous }
    }
    throw error
  }
}
```

Set `initialSnapshotSource = snapshot.source` inside successful `load()`. Leave
it `nil` when migration or store loading fails. Ensure the transactional call
cancels the debounced save created by `updatePreferences`.

- [ ] **Step 8: Run Task 1 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingProgress|AppPreferences|AppState'
```

Expected: all selected tests pass.

- [ ] **Step 9: Commit**

```sh
git add Sources/FleckCore/OnboardingProgress.swift \
  Sources/FleckCore/AppPreferences.swift \
  Sources/FleckApp/AppState.swift \
  Tests/FleckCoreTests/OnboardingProgressTests.swift \
  Tests/FleckCoreTests/AppPreferencesTests.swift \
  Tests/FleckAppTests/AppStateTests.swift
git commit -m "feat: persist onboarding progress"
```

---

### Task 2: Honest Access-Actions Boundary

**Files:**
- Create: `Sources/FleckApp/FleckAccessActions.swift`
- Create: `Tests/FleckAppTests/OnboardingAccessTests.swift`

**Interfaces:**
- Produces: `FleckAccessState`, `FleckAccessAction`, `FleckAccessActionResult`, and `FleckAccessPresentation`.
- Produces: `@MainActor protocol FleckAccessActions`.
- Produces: `UnavailableFleckAccessActions`, the only app-target implementation in this project.
- Later StoreKit code replaces the injected implementation without changing onboarding UI.

- [ ] **Step 1: Write failing access contract tests**

Add:

```swift
@Test @MainActor func unavailableAccessAdapterCannotComplete() async {
  let actions = UnavailableFleckAccessActions()
  #expect(!actions.presentation.hasFullAccess)
  #expect(actions.presentation.localizedLifetimePrice == nil)
  #expect(await actions.startTrial() == .unavailable)
  #expect(await actions.purchaseLifetime() == .unavailable)
  #expect(await actions.restorePurchase() == .unavailable)
  #expect(!actions.presentation.hasFullAccess)
}

@Test func onlyTrialAndPurchaseStatesHaveFullAccess() {
  #expect(!FleckAccessState.loading.hasFullAccess)
  #expect(!FleckAccessState.trialNotStarted.hasFullAccess)
  #expect(FleckAccessState.trialActive(expiresAt: .distantFuture).hasFullAccess)
  #expect(FleckAccessState.purchased.hasFullAccess)
  #expect(!FleckAccessState.unavailable.hasFullAccess)
}
```

- [ ] **Step 2: Run access tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingAccess
```

Expected: compilation fails because the access contract does not exist.

- [ ] **Step 3: Implement the minimal access types**

Create:

```swift
import Foundation

enum FleckAccessState: Equatable, Sendable {
  case loading
  case trialNotStarted
  case trialActive(expiresAt: Date)
  case purchased
  case unavailable

  var hasFullAccess: Bool {
    switch self {
    case .trialActive, .purchased: true
    case .loading, .trialNotStarted, .unavailable: false
    }
  }
}

enum FleckAccessAction: Equatable, Sendable {
  case startTrial
  case purchaseLifetime
  case restorePurchase
}

enum FleckAccessActionResult: Equatable, Sendable {
  case trialActive(expiresAt: Date)
  case purchased
  case cancelled
  case pending
  case nothingToRestore
  case unavailable
  case failed(String)
}

struct FleckAccessPresentation: Equatable, Sendable {
  var state: FleckAccessState
  var localizedLifetimePrice: String?
  var inFlightAction: FleckAccessAction?
  var message: String?

  var hasFullAccess: Bool { state.hasFullAccess }
}

@MainActor
protocol FleckAccessActions: AnyObject {
  var presentation: FleckAccessPresentation { get }
  func refresh() async
  func startTrial() async -> FleckAccessActionResult
  func purchaseLifetime() async -> FleckAccessActionResult
  func restorePurchase() async -> FleckAccessActionResult
}
```

Implement `UnavailableFleckAccessActions` with:

```swift
private(set) var presentation = FleckAccessPresentation(
  state: .unavailable,
  localizedLifetimePrice: nil,
  inFlightAction: nil,
  message: "Access setup is unavailable in this development build."
)
```

Every method returns `.unavailable` and does not mutate to a full-access state.

- [ ] **Step 4: Run Task 2 tests**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingAccess
```

Expected: all access boundary tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/FleckApp/FleckAccessActions.swift \
  Tests/FleckAppTests/OnboardingAccessTests.swift
git commit -m "feat: define onboarding access boundary"
```

---

### Task 3: Granular Permissions and Truthful Compatibility

**Files:**
- Modify: `Sources/FleckApp/DictationAvailability.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Tests/FleckAppTests/DictationAvailabilityTests.swift`
- Modify: `Tests/FleckAppTests/AppStateDictationTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Interfaces:**
- Produces: `DictationFoundationModelAvailability`.
- Produces: `DictationCompatibilityPresentation`.
- Produces: `DictationPermissionController.requestMicrophoneAccess()` and `requestSpeechRecognitionAccess()`.
- Produces: runtime permission methods consumed by `OnboardingCoordinator`.
- Changes: startup modifier synchronization preflights but never requests Input Monitoring.
- Preserves: normal toolbar capture's combined permission preflight and Settings recovery.

- [ ] **Step 1: Write failing granular permission tests**

Add:

```swift
@Test @MainActor func permissionsRequestOnlyTheSelectedCapability() async {
  let probe = PermissionProbe()
  let controller = probe.makeController()

  _ = await controller.requestMicrophoneAccess()
  #expect(probe.microphoneRequests == 1)
  #expect(probe.speechRequests == 0)

  _ = await controller.requestSpeechRecognitionAccess()
  #expect(probe.microphoneRequests == 1)
  #expect(probe.speechRequests == 1)
}
```

Keep the existing combined `requestAccess(for:after:)` regression and assert
that Standard still requests microphone before Speech Recognition.

- [ ] **Step 2: Write failing compatibility-reason tests**

Replace the Boolean Foundation Models fixture input with:

```swift
enum DictationFoundationModelAvailability: Equatable, Sendable {
  case available
  case unsupportedOS
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  case modelNotReady
  case unknown
}
```

Add a table asserting exact user-facing rows:

```swift
#expect(
  DictationCompatibilityPresentation(
    availability: .fixture(foundationModel: .deviceNotEligible)
  ).cleanup.detail == "Requires a Mac that supports Apple Intelligence"
)
#expect(
  DictationCompatibilityPresentation(
    availability: .fixture(foundationModel: .appleIntelligenceNotEnabled)
  ).smartCapture.detail == "Saves to Inbox"
)
```

Cover not-determined, denied, restricted, unsupported on-device English,
unsupported OS, model not ready, and available.

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'permissionsRequestOnlyTheSelectedCapability|DictationCompatibility'
```

Expected: granular APIs and reasoned compatibility types are missing.

- [ ] **Step 4: Implement granular permission requests**

Add:

```swift
func requestMicrophoneAccess() async -> DictationPermissionStatus {
  if microphoneStatus() == .notDetermined {
    _ = await requestMicrophone()
  }
  return microphoneStatus()
}

func requestSpeechRecognitionAccess() async -> DictationPermissionStatus {
  if speechStatus() == .notDetermined {
    _ = await requestSpeech()
  }
  return speechStatus()
}
```

Refactor the existing combined method to call these in order without changing
its denial and recovery behavior.

Expose on `DictationRuntime`:

```swift
var microphonePermissionStatus: DictationPermissionStatus
var speechRecognitionPermissionStatus: DictationPermissionStatus
func requestMicrophonePermission() async
func requestSpeechRecognitionPermission() async
func requestInputMonitoringPermission() async -> Bool
```

Each request refreshes `availability` after returning.

- [ ] **Step 5: Remove unsolicited Input Monitoring requests**

In `synchronizePreferences`, replace the startup request block with:

```swift
let hasAccess = shortcutController.preflightAccess()
if hasAccess {
  try? shortcutController.configure(currentDesiredModifier)
  needsModifierApplication = false
}
```

Delete `didRequestModifierAccess`. Keep `changeModifier(to:)` and
`retryModifierMonitoring()` explicitly user-initiated for Settings.

Add a runtime test whose monitor spy returns no access and assert
`requestAccessCount == 0` after initial load and activation.

- [ ] **Step 6: Implement Foundation Models reason mapping**

Change `DictationAvailability.Input` to consume
`DictationFoundationModelAvailability`. Under `#if canImport(FoundationModels)`
and macOS 26:

```swift
switch SystemLanguageModel.default.availability {
case .available:
  return .available
case .unavailable(.deviceNotEligible):
  return .deviceNotEligible
case .unavailable(.appleIntelligenceNotEnabled):
  return .appleIntelligenceNotEnabled
case .unavailable(.modelNotReady):
  return .modelNotReady
@unknown default:
  return .unknown
}
```

Return `.unsupportedOS` before macOS 26. This shape follows Apple's
`SystemLanguageModel.Availability` contract:
<https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum>.

Derive `cleanupAvailable` and `.foundationModel` routing only from `.available`.
Add `DictationCompatibilityPresentation` rows for Fleck notes, Apple Speech,
AI cleanup, and Smart Capture. Update Settings to consume the same presentation
instead of inventing separate availability copy.

- [ ] **Step 7: Run Task 3 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'DictationAvailability|DictationSettings|AppStateDictation'
```

Expected: all permission, runtime, compatibility, and Settings tests pass.

- [ ] **Step 8: Commit**

```sh
git add Sources/FleckApp/DictationAvailability.swift \
  Sources/FleckApp/FleckApp.swift \
  Sources/FleckApp/SettingsView.swift \
  Tests/FleckAppTests/DictationAvailabilityTests.swift \
  Tests/FleckAppTests/AppStateDictationTests.swift \
  Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: expose onboarding permission status"
```

---

### Task 4: Onboarding Coordinator and TDD State Machine

**Files:**
- Create: `Sources/FleckApp/OnboardingCoordinator.swift`
- Create: `Tests/FleckAppTests/OnboardingBootstrapTests.swift`
- Create: `Tests/FleckAppTests/OnboardingCoordinatorTests.swift`
- Modify: `Tests/FleckAppTests/OnboardingAccessTests.swift`

**Interfaces:**
- Consumes: `AppState.initialSnapshotSource`, `persistOnboardingProgress(_:)`, `DictationRuntime`, and `FleckAccessActions`.
- Produces: `OnboardingGateState`, `OnboardingBootstrapPolicy`, and `OnboardingCoordinator`.
- Owns: visible/persisted cursor separation, starter-note baseline, selected modifier, permission advancement, access actions, and save errors.

- [ ] **Step 1: Write failing bootstrap-policy tests**

Add a table:

```swift
@Test func onboardingBootstrapPolicyClassifiesSnapshots() {
  #expect(
    OnboardingBootstrapPolicy.resolve(source: .fresh, progress: nil)
      == .persistAndRequire(
        OnboardingProgress(status: .inProgress(step: .welcome))
      )
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(source: .root, progress: nil)
      == .persistAndSkip(
        OnboardingProgress(status: .existingUserExempt)
      )
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(
      source: .root,
      progress: .init(status: .inProgress(step: .dictation))
    ) == .requireExisting
  )
  #expect(
    OnboardingBootstrapPolicy.resolve(
      source: .recovery,
      progress: .init(status: .completed)
    ) == .skipExisting
  )
}
```

Also prove a completed marker is not replayed merely because
`currentFlowVersion` later differs.

- [ ] **Step 2: Run bootstrap tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingBootstrap
```

Expected: the policy does not exist.

- [ ] **Step 3: Implement the pure bootstrap policy**

Define:

```swift
enum OnboardingBootstrapDecision: Equatable {
  case persistAndRequire(OnboardingProgress)
  case requireExisting
  case persistAndSkip(OnboardingProgress)
  case skipExisting
}

enum OnboardingBootstrapPolicy {
  static func resolve(
    source: LocalStoreSnapshotSource,
    progress: OnboardingProgress?
  ) -> OnboardingBootstrapDecision
}
```

Missing fresh state yields the Welcome marker. Missing root/recovery state
yields `existingUserExempt`. Existing `.inProgress` always resumes. Completed
or exempt always skips.

- [ ] **Step 4: Write failing navigation and starter-note tests**

Use a temporary `LocalStore` and injected access fake:

```swift
@Test @MainActor func freshBootstrapPersistsWelcomeBeforeBecomingRequired() async {
  let fixture = OnboardingFixture(source: .fresh)
  await fixture.coordinator.bootstrap()
  #expect(fixture.persistedProgresses == [
    OnboardingProgress(status: .inProgress(step: .welcome)),
  ])
  #expect(fixture.coordinator.gateState == .required)
  #expect(fixture.coordinator.visibleStep == .welcome)
}

@Test @MainActor func firstNoteRequiresARealMutation() async {
  let fixture = OnboardingFixture(step: .firstNote)
  await fixture.coordinator.prepareFirstNoteIfNeeded()
  #expect(!fixture.coordinator.canContinue)
  fixture.state.updateSelected(body: "A real first thought")
  #expect(fixture.coordinator.canContinue)
}

@Test @MainActor func backIsTransientAndResumeStaysAtFurthestStep() async {
  let fixture = OnboardingFixture(step: .dictation)
  fixture.coordinator.goBack()
  #expect(fixture.coordinator.visibleStep == .firstNote)
  #expect(fixture.coordinator.persistedStep == .dictation)
}
```

Add idempotent pristine-note preparation and non-overwrite tests.

- [ ] **Step 5: Write failing permission and access outcome tests**

Cover:

```swift
await coordinator.deferCurrentPermission()
#expect(coordinator.permissionCursor == .speechRecognition)

await coordinator.performAccessAction(.purchaseLifetime)
#expect(coordinator.gateState == .required) // fake returns cancelled

fake.presentation.state = .purchased
fake.nextResult = .purchased
await coordinator.performAccessAction(.purchaseLifetime)
#expect(coordinator.gateState == .complete)
```

Add matrices for active trial, purchased, restored purchase, cancelled, pending,
nothing to restore, unavailable, failed, and access success followed by
progress-save failure. The failure case must expose `Finish Setup` without
calling the access method again.

- [ ] **Step 6: Run coordinator tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingCoordinator|OnboardingAccess'
```

Expected: coordinator, navigation, and completion APIs are missing.

- [ ] **Step 7: Implement the coordinator**

Use one main-actor observable object:

```swift
enum OnboardingGateState: Equatable {
  case loading
  case required
  case complete
  case blocked(String)
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
  @Published private(set) var gateState: OnboardingGateState = .loading
  @Published private(set) var visibleStep: OnboardingStep = .welcome
  @Published private(set) var permissionCursor: OnboardingPermissionCursor = .microphone
  @Published private(set) var isSaving = false
  @Published private(set) var isPerformingAccessAction = false
  @Published private(set) var message: String?
  @Published var selectedModifier: DictationModifierKey

  let accessActions: any FleckAccessActions

  func bootstrap() async
  func prepareFirstNoteIfNeeded() async
  func continueFromCurrentStep() async
  func goBack()
  func requestCurrentPermission() async
  func deferCurrentPermission() async
  func performAccessAction(_ action: FleckAccessAction) async
  func finishSetupAfterPersistenceFailure() async
}
```

Use constants:

```swift
static let firstNoteTitle = "First Note"
static let firstNoteBody =
  "Fleck lives in your menu bar and keeps this note on your Mac.\n\n"
  + "Add your first thought below."
```

Only prepare when the workspace contains one selected exact default `Untitled`
note with empty body and no RTF. Snapshot the prepared title/body/revision as the
baseline. `canContinue` on First Note compares the live selected note to that
baseline.

On Dictation Continue, persist the selected modifier through `AppState`, call
`runtime.preferencesDidChange()`, and advance without calling an Input
Monitoring request.

Permission request/defer persists the next `permissionCursor`. Compatibility
Continue advances to Get Fleck regardless of permission state.

Access completion requires both a success-shaped result and
`accessActions.presentation.hasFullAccess`. Persist `.completed` before setting
`gateState = .complete`.

- [ ] **Step 8: Run Task 4 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingBootstrap|OnboardingCoordinator|OnboardingAccess'
```

Expected: all state-machine tests pass.

- [ ] **Step 9: Commit**

```sh
git add Sources/FleckApp/OnboardingCoordinator.swift \
  Tests/FleckAppTests/OnboardingBootstrapTests.swift \
  Tests/FleckAppTests/OnboardingCoordinatorTests.swift \
  Tests/FleckAppTests/OnboardingAccessTests.swift
git commit -m "feat: coordinate resumable onboarding"
```

---

### Task 5: Guided Canvas Presentation and Real Notes Surface

**Files:**
- Create: `Sources/FleckApp/OnboardingView.swift`
- Create: `Tests/FleckAppTests/OnboardingPresentationTests.swift`
- Create: `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift` only if the real panel requires a narrowly scoped presentation hook.

**Interfaces:**
- Consumes: `OnboardingCoordinator`, `AppState`, `DictationRuntime`, `DictationCompatibilityPresentation`, and the existing `NotesPanel`.
- Produces: `OnboardingFlowView`, `OnboardingRail`, permission/access presentations, and the menu-bar resume panel.
- Preserves: one actual editor registration and the real workspace/runtime.

- [ ] **Step 1: Write failing rail and copy presentation tests**

Keep copy and enablement in pure values so Swift Testing can assert:

```swift
@Test func onboardingRailHasExactStepsAndStates() {
  let rail = OnboardingRailPresentation(current: .dictation)
  #expect(rail.items.map(\.title) == [
    "Welcome", "Your first note", "Dictation", "Permissions", "Get Fleck",
  ])
  #expect(rail.items.map(\.state) == [
    .completed, .completed, .current, .upcoming, .upcoming,
  ])
}

@Test func getFleckCopyContainsRequiredPromisesAndNoSkip() {
  let presentation = OnboardingGetFleckPresentation(
    access: .unavailableFixture
  )
  #expect(presentation.body.contains("No credit card"))
  #expect(presentation.body.contains("No Apple purchase sheet"))
  #expect(presentation.body.contains("not be charged automatically"))
  #expect(!presentation.actions.map(\.title).contains("Not Now"))
}
```

Add tests for Welcome copy, local privacy anchor, selected-modifier copy,
permission copy, Settings deferral copy, and localized price loading.

- [ ] **Step 2: Write failing real-surface and no-fake-capsule tests**

Add a source/presentation assertion that `OnboardingView.swift` refers to:

```text
NotesPanel(
DictationModifierKey.displayName
DictationCompatibilityPresentation
```

and does not define or instantiate:

```text
NativeRichTextEditor(
DictationCoordinator(
DictationCapsulePanel(
```

This allows the actual component types in their owning files while rejecting
onboarding-local duplicates.

- [ ] **Step 3: Run presentation tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingPresentation|OnboardingSourceAudit'
```

Expected: presentation and view types do not exist.

- [ ] **Step 4: Implement pure presentation values**

Define:

```swift
enum OnboardingRailItemState: Equatable {
  case completed
  case current
  case upcoming
}

struct OnboardingRailItemPresentation: Equatable, Identifiable {
  let step: OnboardingStep
  let title: String
  let subtitle: String?
  let state: OnboardingRailItemState
  var id: OnboardingStep { step }
}

struct OnboardingRailPresentation: Equatable {
  let items: [OnboardingRailItemPresentation]
  init(current: OnboardingStep)
}
```

Add similarly small `OnboardingPermissionPresentation` and
`OnboardingGetFleckPresentation` value types. Keep all exact copy from the
approved design in these types rather than scattering string literals through
view branches.

- [ ] **Step 5: Implement the Guided Canvas shell**

Create:

```swift
struct OnboardingFlowView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject var coordinator: OnboardingCoordinator
  @ObservedObject var dictationRuntime: DictationRuntime

  var body: some View {
    HStack(spacing: 0) {
      OnboardingRail(
        presentation: .init(current: coordinator.visibleStep)
      )
      Divider().opacity(0.45)
      VStack(spacing: 0) {
        stepContent
        Divider().opacity(0.45)
        OnboardingFooter(coordinator: coordinator)
      }
    }
    .frame(minWidth: 920, idealWidth: 1_080, minHeight: 620, idealHeight: 700)
    .preferredColorScheme(.dark)
  }
}
```

Use native semantic materials/colors. The rail is 240 points, outer content
inset 32, section spacing 24, and footer height 72. Use macOS system blue only
for onboarding progress/primary actions; do not rewrite
`AppPreferences.accentHex`.

- [ ] **Step 6: Implement all five step views**

Use exact approved copy. For First Note and Dictation/compatibility live areas,
instantiate:

```swift
NotesPanel(dictationRuntime: dictationRuntime, isPinned: true)
  .environmentObject(appState)
```

Do not create `NativeRichTextEditor`, `EditorCommands`,
`DictationCoordinator`, or a capsule controller in onboarding.

Dictation shows the modifier picker bound to
`coordinator.selectedModifier`. Permission substeps call only
`requestCurrentPermission()` or `deferCurrentPermission()`. Compatibility uses
the runtime's shared presentation. Get Fleck uses the access presentation,
loading/disabled localized price behavior, and the three exact actions.

If the full `NotesPanel` cannot fit without clipping, add only a presentation
parameter that affects frame sizing:

```swift
enum NotesPanelPresentation {
  case standard
  case onboardingCanvas
}
```

The onboarding case may accept the canvas frame but must reuse the same header,
tab strip, formatting bar, title field, `NativeRichTextEditor`, bindings, and
runtime registration.

- [ ] **Step 7: Add accessibility and motion behavior**

Set:

```swift
.accessibilityLabel("\(item.title), \(item.state.accessibilityValue)")
.accessibilityHeading(.h1)
.accessibilityHidden(true) // decorative footer dots only
```

Use `accessibilityReduceMotion` to select opacity-only transitions. Use
`accessibilityReduceTransparency` to replace material with an opaque semantic
charcoal fill. Preserve native keyboard order; do not make the progress rail
clickable.

- [ ] **Step 8: Run Task 5 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingPresentation|OnboardingSourceAudit'
swift build
```

Expected: presentation/audit tests pass and the app target builds.

- [ ] **Step 9: Commit**

```sh
git add Sources/FleckApp/OnboardingView.swift \
  Sources/FleckApp/NotesPanel.swift \
  Tests/FleckAppTests/OnboardingPresentationTests.swift \
  Tests/FleckAppTests/OnboardingSourceAuditTests.swift
git commit -m "feat: build guided canvas onboarding"
```

Omit `NotesPanel.swift` from the commit if no presentation hook was required.

---

### Task 6: Reuse the Existing Window and Gate Normal Notes

**Files:**
- Create: `Sources/FleckApp/OnboardingWindowPresenter.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Create: `Tests/FleckAppTests/OnboardingWindowTests.swift`
- Modify: `Tests/FleckAppTests/OnboardingPresentationTests.swift`

**Interfaces:**
- Consumes: the single `AppState`, `DictationRuntime`, and `OnboardingCoordinator`.
- Produces: `FleckMenuBarRoot`, `FleckPinnedNotesRoot`, `OnboardingResumePanel`, and `OnboardingWindowPresenter`.
- Preserves: scene identifier `pinned-notes`, menu-bar lifecycle, pin behavior after onboarding, and app termination behavior.

- [ ] **Step 1: Write failing window-decision tests**

Add a pure presentation decision:

```swift
@Test func windowContentFollowsTheOnboardingGate() {
  #expect(FleckRootPresentation.menuBar(for: .loading) == .loading)
  #expect(FleckRootPresentation.menuBar(for: .required) == .resumeOnboarding)
  #expect(FleckRootPresentation.menuBar(for: .complete) == .notes)
  #expect(FleckRootPresentation.pinned(for: .required) == .onboarding)
  #expect(FleckRootPresentation.pinned(for: .complete) == .notes)
}

@Test func onboardingReusesThePinnedWindowIdentifier() {
  #expect(OnboardingWindowPresenter.windowIdentifier == "pinned-notes")
  #expect(OnboardingWindowPresenter.onboardingTitle == "Welcome to Fleck")
  #expect(OnboardingWindowPresenter.completedTitle == "Fleck")
}
```

Add a source audit asserting there is still only one `Window("Fleck",
id: "pinned-notes")` scene and no `Window("Onboarding"` scene.

- [ ] **Step 2: Run window tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution --filter OnboardingWindow
```

Expected: root/presenter types do not exist.

- [ ] **Step 3: Construct one coordinator in `FleckApp.init`**

Keep local references before assigning state objects:

```swift
let dictationRuntime = DictationRuntime(
  appState: appState,
  applicationSupportURL: appSupport
)
let accessActions = UnavailableFleckAccessActions()
let onboarding = OnboardingCoordinator(
  appState: appState,
  dictationRuntime: dictationRuntime,
  accessActions: accessActions
)
_dictationRuntime = StateObject(wrappedValue: dictationRuntime)
_onboarding = StateObject(wrappedValue: onboarding)
```

Start `await onboarding.bootstrap()` once through a root `.task`.

- [ ] **Step 4: Gate the two existing notes roots**

Replace direct `NotesPanel` scene content with:

```swift
MenuBarExtra("Fleck", systemImage: "note.text") {
  FleckMenuBarRoot(
    onboarding: onboarding,
    dictationRuntime: dictationRuntime
  )
  .environmentObject(appState)
}

Window("Fleck", id: "pinned-notes") {
  FleckPinnedNotesRoot(
    onboarding: onboarding,
    dictationRuntime: dictationRuntime
  )
  .environmentObject(appState)
}
```

`FleckMenuBarRoot` shows loading, `OnboardingResumePanel`, or normal
`NotesPanel`. Its Resume button uses the existing `openWindow(id:
"pinned-notes")` action.

`FleckPinnedNotesRoot` shows loading, `OnboardingFlowView`, or
`NotesPanel(isPinned: true)`. Migration failure remains authoritative and must
not be hidden by onboarding.

- [ ] **Step 5: Implement native pinned-window presentation**

Use an `NSViewRepresentable` to capture only its containing existing window.
When required:

```swift
window.title = "Welcome to Fleck"
window.setContentSize(NSSize(width: 1_080, height: 700))
NSApp.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
```

When complete:

```swift
window.title = "Fleck"
window.setContentSize(NSSize(
  width: appState.preferences.panelWidth,
  height: appState.preferences.panelHeight
))
```

Do not allocate another `NSWindow`, `NSWindowController`, `AppState`,
`DictationRuntime`, or `NotesPanel` owner. Native close remains available;
relaunch/resume is enforced by persisted state.

- [ ] **Step 6: Test completion transition and lifecycle**

Add coordinator/root tests proving:

- Required state yields onboarding in the pinned root and Resume in the menu
  root.
- Completion changes both roots to notes.
- Closing the window does not alter progress.
- Bootstrap is idempotent when SwiftUI recreates a root.
- Migration failure produces blocked/recovery state instead of onboarding.
- The unavailable access adapter cannot trigger the content switch.

- [ ] **Step 7: Run Task 6 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'OnboardingWindow|OnboardingPresentation|OnboardingCoordinator'
swift build
```

Expected: all window/root tests pass and Fleck builds.

- [ ] **Step 8: Commit**

```sh
git add Sources/FleckApp/OnboardingWindowPresenter.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/OnboardingWindowTests.swift \
  Tests/FleckAppTests/OnboardingPresentationTests.swift
git commit -m "feat: gate Fleck launch with onboarding"
```

---

### Task 7: Real Dictation Demo, Resume Regressions, and Source Guardrails

**Files:**
- Modify: `Sources/FleckApp/OnboardingCoordinator.swift`
- Modify: `Sources/FleckApp/OnboardingView.swift`
- Modify: `Tests/FleckAppTests/OnboardingCoordinatorTests.swift`
- Modify: `Tests/FleckAppTests/OnboardingSourceAuditTests.swift`
- Modify: `Tests/FleckAppTests/FocusedDictationEditorTests.swift` only if a regression is needed at the real AppKit insertion boundary.

**Interfaces:**
- Consumes: `DictationRuntime.phase`, `DictationEditorRegistry`, real `NotesPanel`, and selected-note revision.
- Produces: optional demo success/fallback presentation without another capture engine.
- Enforces: no hard-coded price, fake editor, fake capsule, fake access, or unsolicited permission request.

- [ ] **Step 1: Write failing demo outcome tests**

Use the existing injected runtime/coordinator fakes:

```swift
@Test @MainActor func onboardingDemoRecognizesRealFocusedInsertion() async {
  let fixture = OnboardingDictationFixture()
  let revision = fixture.state.selectedNote!.revision

  fixture.editor.makeFirstResponder()
  await fixture.runtime.toggle()
  fixture.speech.finalText = "Added through real dictation"
  await fixture.runtime.toggle()
  await fixture.runtime.waitForTerminalSynchronization()

  fixture.coordinator.observeDictationTerminalState()
  #expect(fixture.state.selectedNote!.revision == revision + 1)
  #expect(fixture.coordinator.dictationDemoSucceeded)
}
```

Add:

- Permission unavailable leaves the demo optional and Continue enabled.
- Cleanup failure inserts the raw transcript.
- Unfocused capture uses existing Smart Capture/Inbox behavior.
- Escape/cancel produces no success state and no note mutation.
- Back/quit during active capture uses existing cancellation.

- [ ] **Step 2: Run demo tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'onboardingDemo|FocusedDictationEditor'
```

Expected: onboarding does not yet derive demo success.

- [ ] **Step 3: Implement derived demo presentation**

Record the selected note ID/revision when the compatibility tryout begins.
After the shared runtime returns to a saved terminal state, report success only
when that exact note's revision increased. Do not call coordinator internals or
inject transcript text from onboarding.

Expose:

```swift
@Published private(set) var dictationDemoSucceeded = false

func beginObservingDictationDemo()
func observeDictationTerminalState()
```

The view shows a compact `Dictation added to First Note` confirmation when true.
When Standard is unavailable, it shows the Settings deferral copy and leaves
Continue enabled.

- [ ] **Step 4: Add source guardrail tests**

Read current onboarding source files and assert:

```swift
let forbidden = [
  "$2.99", "$4.99", "USD", "SKTestSession",
  "--onboarding-complete", "hasFullAccess = true",
  "UserDefaults.standard.set(true",
  "NativeRichTextEditor(", "DictationCoordinator(", "DictationCapsulePanel(",
]
for token in forbidden {
  #expect(!onboardingSources.contains(token), Comment(rawValue: token))
}
```

Also assert:

```text
UnavailableFleckAccessActions
localizedLifetimePrice
No credit card
No Apple purchase sheet
not be charged automatically
Settings → Dictation
```

`localizedLifetimePrice` is the provider-facing display-price seam. This phase
must not import StoreKit or refer to `Product` from onboarding production code.

- [ ] **Step 5: Add exact resume regression matrix**

For every rail step and every permission cursor:

1. Persist progress.
2. Reconstruct `AppState` and `OnboardingCoordinator` from the same temporary
   store.
3. Bootstrap.
4. Assert the exact next incomplete screen.

Also simulate failure before the fresh marker commit and prove the coordinator
does not report complete or existing-user-exempt.

- [ ] **Step 6: Run Task 7 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'Onboarding|FocusedDictationEditor|DictationCoordinator'
```

Expected: all onboarding, real insertion, guardrail, and resume tests pass.

- [ ] **Step 7: Commit**

```sh
git add Sources/FleckApp/OnboardingCoordinator.swift \
  Sources/FleckApp/OnboardingView.swift \
  Tests/FleckAppTests/OnboardingCoordinatorTests.swift \
  Tests/FleckAppTests/OnboardingSourceAuditTests.swift \
  Tests/FleckAppTests/FocusedDictationEditorTests.swift
git commit -m "test: harden onboarding runtime boundaries"
```

Omit `FocusedDictationEditorTests.swift` if existing focused-insertion coverage
already proves the boundary without changes.

---

### Task 8: Focused Verification, Full Validation, and Final Review

**Files:**
- Modify: `README.md` only if the new first-launch/manual-test workflow needs a concise note.
- Modify: `TESTING.md` to record the onboarding manual matrix and later access blockers.
- Modify: `IMPLEMENTATION_STATUS.md` to state that onboarding UI is implemented but release-blocked on the access subsystem.

**Interfaces:**
- Produces: exact developer validation commands and an honest release-boundary record.
- Does not change: StoreKit/trial implementation status.

- [ ] **Step 1: Run every focused suite**

Run:

```sh
swift test --disable-automatic-resolution --filter Onboarding
swift test --disable-automatic-resolution --filter AppPreferences
swift test --disable-automatic-resolution --filter AppState
swift test --disable-automatic-resolution --filter DictationAvailability
swift test --disable-automatic-resolution --filter DictationSettings
swift test --disable-automatic-resolution --filter GlobalHoldShortcut
swift test --disable-automatic-resolution --filter DictationCoordinator
```

Expected: every command exits 0.

- [ ] **Step 2: Review the complete diff before broad validation**

Run:

```sh
git diff --check
git status --short
git diff --stat codex/fix-agent-setup-migration...HEAD
git diff codex/fix-agent-setup-migration...HEAD -- Sources Tests docs
```

Review every changed line against the approved spec. Remove unused imports,
orphaned test helpers, duplicate copy, extra abstractions, and any unrelated
formatting change introduced by this branch.

- [ ] **Step 3: Update testing and status documentation**

Document:

- Packaged launch commands.
- Disposable-store/test-account requirement.
- Fresh, resume, permission, actual audio, VoiceOver, motion, and compatibility
  manual checks.
- That the production access adapter is unavailable.
- That completion transition needs automated fake coverage now and real
  StoreKit/manual evidence later.
- The exact later StoreKit/trial boundaries from the approved design.

Do not claim a real trial, purchase, restore, price, read-only mode, signed app,
or App Store setup.

- [ ] **Step 4: Run the complete repository gate**

Run with `FLECK_ENHANCED_CANDIDATE` unset:

```sh
swift test --disable-automatic-resolution --no-parallel
swift build
swift build -c release
Scripts/audit-agent-boundary.sh
Scripts/validate-macos.sh
git diff --check
git status --short
```

Expected:

- All tests pass.
- Debug and release builds pass.
- Agent boundary audit passes.
- `Scripts/validate-macos.sh` passes.
- `git diff --check` is silent.
- `git status --short` contains only the intended onboarding/documentation
  changes before the final commit.

- [ ] **Step 5: Build the packaged app for read-only visual inspection**

Run:

```sh
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

Use a disposable Application Support fixture or separate macOS test account.
Do not delete or overwrite the user's real Fleck data. Do not accept real
Microphone, Speech Recognition, or Input Monitoring prompts unless the user
explicitly authorizes that manual test.

Verify the Guided Canvas hierarchy, rail/footer stability, real notes panel,
selected modifier copy, permission deferral, unavailable Get Fleck state, close
and resume, and no duplicate window/capsule.

- [ ] **Step 6: Perform final code review**

Check:

- Every changed production line traces to onboarding.
- Fresh marker ordering cannot classify an interrupted new user as existing.
- Existing-user exemption does not imply full access.
- No permission request occurs on appearance, startup, Back, Continue, or app
  activation.
- `NotesPanel` and `DictationRuntime` each have one shared owner.
- Completion is impossible through the unavailable adapter.
- The localized price is never hard-coded.
- Window completion replaces onboarding in `pinned-notes`.
- Save and access failures cannot produce false completion.
- Manual-only boundaries are named honestly.

- [ ] **Step 7: Commit documentation/final cleanup**

```sh
git add README.md TESTING.md IMPLEMENTATION_STATUS.md \
  Sources/FleckCore Sources/FleckApp Tests
git commit -m "docs: record onboarding verification boundaries"
```

Stage only files actually changed by the final review. If documentation already
contains the complete truth and no cleanup was needed, omit this commit.

- [ ] **Step 8: Prepare the final report**

Report:

- Commits created.
- Exact focused and full commands with results.
- Packaged-build result.
- Automated coverage for fresh/resume/note/dictation/permission/access/window
  behavior.
- Manual checks performed and not performed.
- The production-unavailable access adapter and every later StoreKit/trial
  blocker.
- Any pre-existing warning or failure kept outside onboarding scope.
