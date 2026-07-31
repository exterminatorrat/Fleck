# Fleck First-Launch Onboarding Design

**Status:** Written design for user review
**Date:** 2026-07-31
**Visual direction:** Guided Canvas

## Summary

Fleck will add a mandatory, resumable first-launch onboarding flow that teaches
the product inside Fleck's real notes and dictation surfaces. The flow uses the
existing pinned-notes window while setup is incomplete, so a menu-bar app
cannot appear to launch without a visible destination and onboarding does not
create a second notes scene.

The five rail steps are:

1. Welcome
2. Your first note
3. Dictation
4. Permissions
5. Get Fleck

The user may defer each permission, but there is no onboarding skip. Completion
requires an authoritative access result: an active seven-day trial, a verified
lifetime purchase, or a restored lifetime purchase. The trial choice appears
only after the user has experienced Fleck's value.

This project builds onboarding only. The later StoreKit 2 and trial subsystem
will supply the production access implementation. Until it does, Fleck uses an
explicit unavailable access adapter: the final actions cannot complete, no
price is invented, and no test entitlement can ship in the app target.

## Goals

- Make first launch obvious and useful for a menu-bar app.
- Resume at the last incomplete step after window close, quit, crash, or
  restart.
- Teach note capture in the actual tab, title, formatting, and AppKit editor
  surfaces backed by the real workspace.
- Teach dictation through the one existing `DictationRuntime`,
  `DictationCoordinator`, selected modifier, floating capsule, cleanup/router,
  and focused-editor insertion path.
- Explain and request Microphone, Speech Recognition, and Input Monitoring
  separately, only after a user action.
- Let the user defer or deny any permission without trapping onboarding.
- Show live, truthful compatibility for Apple Speech, cleanup, and Smart
  Capture.
- Keep local-first privacy visible without turning onboarding into a privacy
  policy.
- End with a calm trial, purchase, or restore choice and no subscription,
  account, pricing tier, countdown, or automatic-charge language.
- Transition the onboarding window into the normal Fleck notes UI without
  terminating Fleck or leaving an onboarding window behind.
- Preserve current workspaces and the existing menu-bar, pinned-window, note,
  dictation, and agent lifecycles.

## Non-goals

This project will not:

- Implement StoreKit 2, trial persistence, Keychain entitlement caching,
  transaction listening, expiration gates, or read-only mode.
- Add RevenueCat, a Fleck account, email signup, Sign in with Apple, a
  subscription, or a licensing backend.
- Hard-code a lifetime price or simulate a real purchase in the application
  target.
- Implement iCloud, sandbox migration, signing, notarization, App Store
  Connect, or Apple Developer configuration.
- Force agent setup during onboarding.
- Create a second note editor, a second workspace, a second dictation state
  machine, an embedded transcript recorder, or a screenshot imitation.
- Request a permission on page appearance.
- Require any optional permission or a successful dictation capture to reach
  the final access step.
- Retroactively force existing Fleck users through first-launch education.

## Confirmed Baseline

The design starts from `codex/fix-agent-setup-migration` at `de264c5`.
Inspection confirmed:

- `FleckApp` owns one shared `AppState` and one shared `DictationRuntime`.
- `NotesPanel` renders the real header, tab strip, formatting bar, title field,
  and `NativeRichTextEditor`.
- `NotesPanel` registers its `EditorCommands` with the shared dictation editor
  registry, so focused dictation uses the current AppKit text view.
- `DictationRuntime` already owns the coordinator, modifier monitor, permission
  controller, floating capsule, cleanup/routing availability, and history.
- `AppPreferences` and the workspace are loaded and persisted together through
  `LocalStore`.
- The pinned notes scene already has the stable `pinned-notes` window
  identifier.
- There is no onboarding or access/StoreKit type in the repository.

The current permission API requests Microphone and Speech Recognition as one
sequence, and modifier synchronization may request Input Monitoring during
startup. Onboarding requires those requests to become individually
user-initiated while keeping the same underlying permission and modifier
controllers.

## Product Principles

The flow combines Craft's direct-interaction teaching with Bear's real,
useful starter-note model. It does not import Notion's account-heavy flow,
promotion timing, copy, or visual identity.

Research references:

- Craft Get Started:
  <https://mobbin.com/flows/2d73c8ed-64a5-409f-b368-0ce4e52d3ae9>
- Bear Welcome Note:
  <https://mobbin.com/flows/4e739681-13ff-4aaa-9f6d-39075bbb26ce>
- Notion Onboarding:
  <https://mobbin.com/flows/5ed77200-e4f1-4053-b071-aa716a704569>

Every rail step has one primary purpose. Back and Continue remain in a stable
footer. Permission substeps use a single permission action plus `Not Now`.
There is no carousel of marketing claims and no progress manipulation.

## Window and Launch Lifecycle

### Reuse the pinned-notes window

On an incomplete fresh install, the existing `pinned-notes` scene renders
`OnboardingFlowView` instead of `NotesPanel`. A small launch presenter waits for
`AppState` to finish its initial load, then brings that existing window forward.
It does not create another `NSWindow` or another notes runtime.

The menu-bar popover shows a compact `Finish setting up Fleck` panel with a
`Resume Setup` button while onboarding is incomplete. Opening the pinned-notes
window resumes the full onboarding view. Neither route exposes a second editor
that could bypass the flow.

The onboarding window may be closed with the native close control and Fleck may
be quit normally. Closing is not a skip: reopening the menu-bar panel or
launching Fleck again resumes the saved incomplete step.

### Completion

After authoritative access succeeds and completion persistence succeeds, the
same `pinned-notes` scene switches from `OnboardingFlowView` to the normal
`NotesPanel(isPinned: true)`. The window title returns to `Fleck`, its content
size returns to the saved panel dimensions, and focus moves to the real note
editor.

The application remains running. No onboarding sheet or secondary scene
remains open. The menu-bar popover simultaneously returns to its normal
`NotesPanel` content.

### Existing users

Onboarding eligibility is resolved only after `LocalStore.loadSnapshot()`:

- A fresh snapshot with no progress marker begins at Welcome.
- A fresh snapshot with incomplete progress resumes its saved cursor.
- A completed or existing-user-exempt marker never reopens this flow.
- An existing root or recovery snapshot with no marker is classified as an
  existing user and does not receive first-launch onboarding.

`flowVersion` supports decoding and an explicit future migration; increasing it
does not automatically replay onboarding for completed users.

The later access subsystem must define entitlement/trial migration for existing
users. The compatibility rule above prevents this onboarding-only branch from
retroactively trapping current workspaces; it does not grant or fake a purchase.

## Visual System

The selected Guided Canvas image is the visual target:

- Native dark charcoal surfaces and system glass/material.
- A left vertical progress rail.
- One large, focused live canvas.
- Stable Back/Continue footer.
- Restrained macOS blue for onboarding progress and primary actions.
- Crisp native spacing, typography, and control sizes.

The onboarding window starts at 1,080 by 700 points and supports a 920 by 620
minimum. The rail is 240 points wide. The content area uses a 32-point outer
inset, 24-point section rhythm, and a maximum readable text width near 640
points. The footer is 72 points high with Back left-aligned, five
noninteractive position dots centered, and Continue or the current primary
access action right-aligned.

The shell deliberately uses dark appearance to match the selected direction.
It uses semantic macOS colors and materials so Increase Contrast and Reduce
Transparency can replace translucent layers with opaque charcoal surfaces.
The embedded notes surface retains Fleck's actual controls and stored accent
preference; onboarding does not rewrite the user's editor preferences.

### Mock corrections

The generated image is directional, not literal:

- Only the outer macOS window shows real traffic-light controls. The live notes
  canvas does not draw fake inner traffic lights.
- The canvas embeds the real `NotesPanel`; it does not reproduce the mock's
  invented editor chrome, typography, or overflow menu.
- The real `DictationCapsulePanel` stays at its configured screen edge. The
  canvas does not draw a second waveform capsule.
- Dictation copy uses the selected
  `AppPreferences.dictationModifierKey.displayName`, never a hard-coded
  `Right Option`.
- Availability and errors come from runtime state, not optimistic mock labels.

### Progress rail

The rail shows all five steps with three states:

- Completed: blue outlined circle with a checkmark.
- Current: blue ring and filled inner dot, white label, optional one-line
  description.
- Upcoming: neutral ring and secondary label.

The rail is informational, not clickable. Users navigate only with Back,
Continue, permission actions, and access actions. This prevents jumping around
required interaction state while preserving a clear sense of place.

A concise privacy anchor remains at the bottom:

> Your notes stay on this Mac.
> Fleck is local-first and has no account.

## Onboarding State and Persistence

`AppPreferences` adds an optional, versioned `OnboardingProgress` value so
progress uses the existing atomic workspace/preferences snapshot path:

```swift
struct OnboardingProgress: Codable, Equatable, Sendable {
  var flowVersion: Int
  var status: Status
  var permissionCursor: PermissionCursor

  enum Status: Codable, Equatable, Sendable {
    case inProgress(step: OnboardingStep)
    case completed
    case existingUserExempt
  }
}
```

`OnboardingStep` contains `welcome`, `firstNote`, `dictation`,
`permissions`, and `getFleck`. `PermissionCursor` contains `microphone`,
`speechRecognition`, `inputMonitoring`, and `compatibility`.

The model stores the next incomplete rail step and, within Permissions, the next
unreviewed permission. It does not store granted/denied permission truth; that
always comes from macOS at runtime.

For a fresh store, the first persistence operation writes
`inProgress(step: .welcome)` before onboarding becomes interactive and before
any runtime preference synchronization may create a root snapshot. This
distinguishes a new user's interrupted first launch from a pre-existing
workspace that predates onboarding. Existing-user exemption is also persisted
when storage is writable.

Forward navigation awaits persistence before changing the saved cursor. A crash
may repeat the current explanation but cannot skip an unseen step. Back
navigation is transient and does not move the persisted resume cursor
backward. Returning forward over an already completed step does not require the
action again.

The first-note interaction and successful optional dictation demo are tracked
in the in-memory coordinator and derived from real workspace/runtime events.
They are not security or entitlement state.

Completion is written only after the access provider reports full access. If
access succeeds but the Fleck snapshot cannot be saved, onboarding remains on
Get Fleck and offers `Finish Setup` after the save error clears. It does not
start a second trial or repeat a completed StoreKit transaction. On next
launch, an authoritative full-access state may finish the pending completion
write.

## Screen 1: Welcome

Title:

> Notes, one shortcut away

Body:

> Fleck lives in your menu bar and keeps your notes local on this Mac.

Three compact facts:

- No Fleck account.
- No subscription.
- Notes remain readable files on this Mac.

The canvas uses native Fleck/menu-bar symbols and restrained motion rather than
a screenshot. Continue is enabled. Back is visually reserved but disabled.

No trial or price appears on this screen.

## Screen 2: Your First Note

Title:

> Write your first note

Body:

> This is Fleck's real editor. Add one line and it saves automatically.

The live canvas hosts the actual `NotesPanel` using the shared `AppState` and
`DictationRuntime`. It therefore includes the production tab strip, title
field, formatting controls, AppKit editor, autosave, Undo, list behavior, and
stored appearance.

For a pristine fresh workspace, onboarding prepares the existing single empty
note once:

- Title: `First Note`
- Body:

  ```text
  Fleck lives in your menu bar and keeps this note on your Mac.

  Add your first thought below.
  ```

Preparation is idempotent and occurs only when the selected note is the exact
untouched fresh default. It never overwrites or duplicates user content.

Continue becomes enabled after the user changes the real title or body after
the prepared snapshot. Deleting or replacing the starter text counts as a real
edit. The saved note remains in the workspace after onboarding.

## Screen 3: Dictation

Title:

> Dictate naturally

Body template:

> Hold **[selected modifier]** while the editor is focused, then release to
> insert. Double-tap for hands-free dictation. Press Escape to cancel.

The step shows:

- The same live `NotesPanel`, not a recreated editor.
- A native picker for the supported side-specific modifier keys.
- The current real idle capsule at its configured screen edge when enabled.
- A short callout asking the user to place the cursor in `First Note`.

The selected modifier is local view state until Continue. Continue saves it to
`AppPreferences.dictationModifierKey` and tells the existing runtime to adopt
the desired value without requesting Input Monitoring. The visible copy updates
immediately from the selected value.

If Apple Speech permissions and Input Monitoring were already granted, the user
may perform a real capture on this screen. A fresh user will normally continue
to Permissions first. Fleck never feeds a canned transcript through a fake
engine in production onboarding.

The refactor required here is narrow: runtime startup and preference
synchronization may preflight Input Monitoring, but only Settings or the
explicit onboarding permission action may call the system request API.

## Screen 4: Permissions and Compatibility

The progress rail remains on Permissions while four internal substeps advance.
Each permission screen explains one capability and presents one request button
plus `Not Now`. No permission request occurs on appearance, Back, Continue, or
app activation.

### Microphone

Title:

> Let Fleck hear dictation

Body:

> Fleck uses the microphone only while you dictate. Audio stays in memory and
> is discarded when capture ends, is cancelled, or fails.

Actions:

- `Allow Microphone` when not determined.
- `Open Microphone Settings` when denied or restricted.
- `Not Now` in every non-authorized state.

### Speech Recognition

Title:

> Turn speech into text

Body:

> Apple Speech turns your audio into text on this Mac. Fleck requires
> on-device recognition and does not use a cloud fallback.

Actions:

- `Allow Speech Recognition` when not determined.
- `Open Speech Recognition Settings` when denied or restricted.
- `Not Now` in every non-authorized state.

### Input Monitoring

Title:

> Use [selected modifier] anywhere

Body:

> Input Monitoring lets Fleck see press and release changes for your selected
> modifier. Fleck does not read, store, or log ordinary keys.

Actions:

- `Allow Input Monitoring` or `Recheck Access`.
- `Open Input Monitoring Settings` when macOS requires manual recovery.
- `Not Now` whenever the monitor is not running.

The existing `GlobalHoldShortcut` and `ModifierKeyEventTap` remain the only
Input Monitoring boundary.

### Granular permission API

`DictationPermissionController` gains individual microphone and Speech
Recognition request methods while retaining its combined capture preflight for
normal toolbar use. `DictationRuntime` exposes those methods and the existing
modifier request/retry operation to onboarding. There is no second permission
state machine.

After each request returns, the runtime refreshes status from the operating
system. Denial, restriction, prompt dismissal, revocation, or a failed event
tap remains recoverable and advances when the user selects `Not Now`.

### Compatibility

The final substep reads the same expanded `DictationAvailability` model used by
Settings:

- `Fleck notes` — Available.
- `Apple Speech` — Available, Needs Microphone, Needs Speech Recognition, or
  On-device English unavailable.
- `AI cleanup` — Available or an accurate unavailable reason.
- `Smart Capture` — Available or `Saves to Inbox`.

On macOS 26 or later, cleanup and routing map the real
`SystemLanguageModel.default.availability` cases: available, device not
eligible, Apple Intelligence not enabled, or model not ready. Earlier macOS
versions report the operating-system requirement. Permission state,
architecture, and recognizer support remain independent inputs; an OS version
alone never produces an Available label.

Copy below the list states:

> If cleanup is unavailable, Fleck keeps the original transcript. If Smart
> Capture is unavailable, Fleck saves safely to Inbox.

When Apple Speech is available, the same live note canvas offers an optional
real dictation tryout. The user clicks in the actual editor and either uses the
configured modifier when Input Monitoring is running or the real microphone
button in Fleck's formatting bar. The shared coordinator drives the real
floating capsule, local cleanup, routing fallback, persistence, and editor
insertion.

Successful focused insertion shows a small confirmation derived from the
coordinator's terminal event. The demo is not required. If permissions are
deferred, denied, or unavailable, the screen says that setup remains available
under `Settings → Dictation` and Continue stays enabled.

## Screen 5: Get Fleck

Title:

> Get Fleck

Primary message:

> Try everything free for 7 days.

Supporting copy:

> Full access to notes, dictation, Smart Capture, customization, and agent
> connections. No credit card. No Apple purchase sheet. You will not be
> charged automatically.

The calm choice stack is:

1. `Start 7-Day Free Trial`
2. `Buy Fleck — [StoreKit-localized price]`
3. `Restore Purchase`

Secondary copy:

> One lifetime purchase. No subscription. No Fleck account.

There is no `Not Now`, close-as-complete behavior, pricing tier, promotional
countdown, crossed-out price, or preselected subscription.

The lifetime button shows a loading label until a localized StoreKit
`Product.displayPrice` is available. It never displays a repository constant.
Product-load failure shows a quiet inline error and Retry. Purchase cancellation
or a pending transaction remains on this screen without presenting failure as
success. Restore with no prior purchase shows a concise inline result and
preserves all three choices.

## Access Action Boundary

Onboarding depends on a narrow injected interface owned by the later access
subsystem:

```swift
@MainActor
protocol FleckAccessActions: AnyObject {
  var presentation: FleckAccessPresentation { get }
  func refresh() async
  func startTrial() async -> FleckAccessActionResult
  func purchaseLifetime() async -> FleckAccessActionResult
  func restorePurchase() async -> FleckAccessActionResult
}
```

The presentation supplies:

- Authoritative access state.
- Whether each action is available or in flight.
- The localized lifetime display price when loaded.
- A safe reader-facing status or error.

An action result may report active trial, purchased, cancelled, pending,
no purchase to restore, unavailable, or failed. Onboarding marks completion
only when the provider's authoritative state is active trial or purchased.

### Current production adapter

Because StoreKit/trial infrastructure is deliberately out of scope, this
project ships an `UnavailableFleckAccessActions` implementation in the app
target. It:

- Provides no display price.
- Performs no StoreKit call.
- Starts no local trial.
- Never returns full access.
- Explains that access setup is unavailable in this development build.

The final screen remains visible with unavailable actions and cannot be
completed. This branch is therefore not release-ready until the later access
phase replaces the adapter.

Test doubles live only in the test target and are injected directly into the
onboarding coordinator. There is no production launch argument, hidden button,
UserDefaults entitlement, hard-coded receipt, or debug menu that can mark a
real onboarding complete.

## Error and Recovery Behavior

- Workspace migration failure remains authoritative and replaces onboarding
  with the existing migration-recovery UI.
- Progress save failure leaves the current step visible with Retry; it never
  silently advances.
- Closing or quitting during an active dictation uses the existing runtime
  cancellation and resource-release path.
- Returning to an earlier step never rolls back note content, permission state,
  or a successful access action.
- Permission denial never disables Back, `Not Now`, or forward progression.
- Revoked permissions are reflected the next time Fleck becomes active.
- Apple Speech unavailable never discards audio through a fake fallback; the
  demo stays unavailable.
- Cleanup failure keeps the raw transcript through the existing coordinator.
- Routing failure or unavailability saves to Inbox through the existing router.
- Purchase cancellation, pending state, unverified state, and failure never
  write onboarding completion.
- Successful access plus failed onboarding persistence offers only completion
  retry, not another purchase/trial action.

## Accessibility, Keyboard, and Motion

- The progress rail exposes one ordered accessibility group with current,
  completed, and upcoming state; decorative footer dots are hidden.
- Every step title becomes the initial VoiceOver focus after forward
  navigation.
- Full Keyboard Access reaches the live editor, modifier picker, permission
  controls, Back, and Continue in reading order.
- The embedded editor retains its existing `Note body` accessibility label and
  native text behavior.
- Permission status never relies on color alone.
- Buttons use native control sizes with at least a 28-point hit area.
- Escape cancels active dictation only. It does not mark onboarding complete.
- Command-W closes the onboarding window without changing progress. Command-Q
  quits and resumes later.
- Reduce Motion uses opacity-only transitions and no rail drawing animation.
- Reduce Transparency uses opaque semantic backgrounds instead of blurred
  material.
- No transition moves focus into the non-activating dictation capsule.

## Implementation Boundaries

Expected owned changes are limited to:

- A versioned onboarding model and fresh/existing bootstrap policy.
- An onboarding coordinator and Guided Canvas SwiftUI views.
- Conditional content in the existing menu-bar and pinned-notes scenes.
- A small presenter that foregrounds the existing pinned-notes window for an
  incomplete fresh install.
- Reuse of `NotesPanel`, `AppState`, and `DictationRuntime`.
- Granular permission request methods and removal of unsolicited Input
  Monitoring requests during startup.
- Expanded shared compatibility presentation.
- The access-action protocol and unavailable production adapter.
- Deterministic tests and onboarding documentation.

Implementation must not refactor unrelated note, agent, storage, dictation, or
window code. Any extraction from `NotesPanel` is allowed only when needed to
embed the exact production surface without duplication.

## Automated Validation

Focused tests must cover:

### Progress and launch

- Fresh snapshot without progress begins at Welcome.
- The fresh bootstrap marker is the first saved change and survives relaunch.
- An interrupted bootstrap cannot be mistaken for an existing-user exemption.
- Existing root/recovery snapshot without progress is exempt.
- Each Continue persists the next incomplete cursor before navigation.
- Permission substep resume is exact.
- Back does not regress the persisted resume cursor.
- Close/relaunch and interrupted-save fixtures resume safely.
- Completion cannot be written without authoritative full access.
- The existing `pinned-notes` window is reused and no extra notes scene is
  created.

### Real note surface

- Pristine-note preparation is exact, idempotent, and never overwrites content.
- Continue is disabled until a real title/body mutation occurs.
- The prepared and edited note uses the normal workspace and persists through
  `LocalStore`.
- The onboarding canvas instantiates `NotesPanel`, not another editor type.

### Dictation and permissions

- Modifier copy reflects every `DictationModifierKey.displayName`.
- Selecting a modifier does not request Input Monitoring.
- Startup preflights but does not request Input Monitoring.
- Microphone, Speech Recognition, and Input Monitoring requests are individually
  invoked only by their matching action.
- `Not Now`, denial, restriction, and failed monitor setup all advance.
- Compatibility maps real permission, recognizer, cleanup, and routing state.
- The optional demo uses the shared coordinator/editor registry and focused
  insertion path.
- Existing cleanup, raw fallback, Inbox routing, capsule, and cancellation
  tests remain green.

### Access

- No price is shown until the injected presentation supplies a localized value.
- Trial success, purchase success, and restore success complete onboarding.
- Cancelled, pending, no-purchase, unavailable, and failure results do not.
- Only one access action may be in flight.
- Successful access followed by progress-save failure does not repeat the
  action.
- The production unavailable adapter cannot complete onboarding.
- A source/string audit rejects hard-coded currency prices and production test
  bypasses in onboarding files.

### Presentation and accessibility

- Rail state, labels, button availability, permission copy, privacy copy, and
  no-skip behavior have presentation tests.
- VoiceOver labels and order are deterministic.
- Reduce Motion and Reduce Transparency select their safe presentations.
- Completing onboarding changes the existing window content to normal
  `NotesPanel` and clears the menu-bar resume gate.

## Manual macOS Validation

Manual validation must use the packaged app:

```sh
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

Use a disposable Application Support fixture or test account; never delete or
overwrite a real Fleck workspace merely to reproduce first launch.

Record evidence for:

- Fresh launch foregrounding the onboarding window.
- Window close, menu-bar Resume Setup, quit, crash, and exact-step resume.
- Actual note editing, autosave, formatting, Undo, and relaunch persistence.
- Every modifier label and physical configured modifier behavior.
- Microphone, Speech Recognition, and Input Monitoring grant, denial,
  `Not Now`, Settings recovery, revocation, and relaunch.
- Real microphone capture, live capsule phases, focused insertion, Escape,
  cleanup fallback, and Inbox fallback.
- Apple Speech and Apple Intelligence availability on representative supported
  and unsupported Macs.
- VoiceOver, Full Keyboard Access, Reduce Motion, Increase Contrast, and Reduce
  Transparency.
- Completion transition after the later access subsystem is available.

Automated tests cannot prove physical audio, real TCC prompts, Input Monitoring,
Apple Speech language installation, Apple Intelligence availability, StoreKit
product loading, purchase sheets, restoration, or App Store receipt behavior.

## Verification Commands

During implementation, run focused suites first:

```sh
swift test --filter Onboarding
swift test --filter AppPreferences
swift test --filter AppState
swift test --filter DictationAvailability
swift test --filter DictationSettings
swift test --filter GlobalHoldShortcut
swift test --filter DictationCoordinator
```

Then run repository validation:

```sh
swift test --disable-automatic-resolution --no-parallel
swift build
swift build -c release
Scripts/audit-agent-boundary.sh
Scripts/validate-macos.sh
git diff --check
git status --short
```

The final report must name the exact focused tests and full commands run, and
must keep automated evidence separate from manual permission, audio, device,
StoreKit, signing, notarization, and App Store evidence.

## Later Access and Release Blockers

The following remain explicitly blocked on the later StoreKit/trial phase:

- StoreKit product identifier and localized `Product.displayPrice` loading.
- `Product.purchase()` handling for verified, unverified, pending, cancelled,
  and failed results.
- `Transaction.currentEntitlements` and `Transaction.updates`.
- User-initiated `AppStore.sync()` restoration.
- Seven-day start/expiry calculation and clock-rollback resistance.
- Keychain-backed verified purchase cache and offline behavior.
- Existing-user entitlement/trial migration.
- Central full-access gating and expired-trial read-only behavior.
- StoreKit configuration and deterministic StoreKit scenario tests.
- App Store Connect product setup and real sandbox purchase/restore evidence.
- Signed/exported-app verification.

Until those boundaries are implemented and validated, this onboarding branch
must not be presented as a releasable purchase or trial experience.
