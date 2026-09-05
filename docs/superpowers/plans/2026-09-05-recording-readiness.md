# Packet 1C — Recording Readiness Implementation Plan

> **For agentic workers:** Use subagent-driven-development for this one coherent packet. Current user routing is Codex-native GPT-5.6 Sol / High implementation, primary architecture and independent verification, followed by a fresh Sol / High reviewer whose verdict must be `ship`. Corrections return to the same worker. No Terra.

**Goal:** Deliver truthful recording feedback as soon as the current capture supplies audio evidence, preserving hold interpretation and all stop/cancel ownership.

**Architecture:** Keep the existing speech interfaces, source lifecycle, runtime, capsule, and waveform. The coordinator accepts successful source startup or a real level callback (including zero) as audio readiness evidence. It publishes Listening before forwarding energy, retains at most one pre-hold level, and rejects feedback once the capture is stopped, cancelled, failed, or superseded. Add one observation timestamp to the existing measurement value.

**Tech Stack:** Swift 6, Swift Testing, existing AppKit/SwiftUI capsule and AVFAudio sources.

## Global constraints and authority

- User explicitly authorized planning and implementation of 1C. 1D–1F and Phases 2–3 are not included.
- Refreshed origin/main remains 68b6b429ab4f1f130252d9865a2c616b7224cca7. Continue the clean isolated branch codex/central-orchestrator-validation from c565332, including accepted 1A and 1B (157f737). Never use the unrelated dirty root checkout.
- Apple Silicon/English; preserve Parakeet/Gemma choices, Apple Speech fallback, faithful cleanup, routing, Vocabulary, model eligibility, resource retention, and 1B quarantine/limits.
- Preserve the 180 ms hold threshold, physical gesture receipts, short-tap discard, double-tap ownership, hidden-pill preference, and existing accepted pill/waveform design.
- No additional callback overload, model-readiness protocol, global event bus, telemetry store, source teardown change, new dependency, or production-only test hook.
- No real microphone/model acquisition, installed-app replacement/launch, push, PR, merge, GitHub changes, or release admission. Local source compilation/tests are authorized; source dependency resolution through the existing enhanced runner is permitted, model weights are not.
- One worker owns all source/test edits; it is not alone in the repository and must preserve other edits. Primary owns documentation and local acceptance commits. No edits outside ownership or worker commits.

## Verified source findings

- EnhancedSpeechCapture.start now starts audio before scheduling load and returns at audio-start success. Apple Speech start also returns after session audio startup. Neither return represents model-ready or physical first-buffer time.
- Coordinator legacy and processing level callbacks currently require holdAccepted, losing pre-hold energy. Levels supplied synchronously while start/begin is suspended can reach the runtime while the capsule remains arming; the capsule correctly ignores them until listening.
- FleckApp receives coordinator phase changes synchronously. Publishing listening before forwarding a level allows the existing capsule to display that level immediately.
- Capsule render already resets energy on arming/finalizing/idle and on session changes. Silence uses static minimum bars; no synthetic movement is needed. Hidden-pill and stale-session gates already exist.

## Design choices

1. **Selected: coordinator-local readiness.** Reuse two existing signals, successful start/begin return and valid audio-level callback. Minimal source changes, compatible with both engines and current processing protocol.
2. **Rejected: add another readiness callback through every source.** Duplicates the audio-ready start contract accepted in 1B and introduces lifecycle surface without improving this packet's evidence.
3. **Rejected: wait for nonzero sound or model load.** A silent microphone is ready, and model loading must not delay recording feedback.

A callback timestamp is the coordinator's observation time. It is not hardware first-buffer time, physical-key latency, or model readiness. Those separate measurements remain 1D.

## Exact owned files

Production:
- Sources/FleckApp/DictationCoordinator.swift — capture-scoped readiness, level delivery, guard reuse, immediate quieting where required.
- Sources/FleckApp/DictationProcessingModels.swift — one existing-measurement stage/property for audio readiness observation.

Tests:
- Tests/FleckAppTests/DictationCoordinatorTests.swift — new captureFeedback tests and directly affected level expectations/fakes only.
- Tests/FleckAppTests/DictationProcessingModelsTests.swift — recording/overlay/terminal semantics of the new timestamp only.
- Tests/FleckAppTests/DictationSettingsTests.swift — runtime-to-capsule readiness/visibility tests and minimal RuntimeSpeechEngine gate support only.
- Tests/FleckAppTests/DictationCapsuleVisualCaptureTests.swift — bounded Starting/listening visual matrix across supported docks and light/dark appearances, reusing current capture helpers; no product UI changes.

Read-only: FleckApp.swift, DictationCapsule.swift, DictationWaveform.swift, StreamingDictationProcessor.swift, EnhancedSpeechCapture.swift, AppleSpeechCapture.swift, GlobalHoldShortcut.swift and existing regression tests. Any new mutable path requires an exact justification to the primary before editing.

## Implementation contract

### 1. Capture-scoped readiness and level delivery

Use one readiness flag and one optional latest level in Capture; no state on global runtime or views. An optional level distinguishes absent evidence from actual zero/silence. Keep the observation timestamp in existing measurements rather than use diagnostic integrity as the UI control flag.

```swift
// Capture additions, names may follow local conventions.
var audioReady = false
var pendingAudioLevel: Float?
```

A valid current-session callback (finite Float, clamp to 0...1) establishes readiness before hold acceptance too. Keep only the latest pre-hold level. Do not publish Listening or energy until holdAccepted. NaN/infinite callbacks must not establish readiness.

After start/begin returns successfully, establish readiness even if no level has arrived. This is audio-start success under the existing engine contract; do not synthesize a nonzero level or label this first PCM. On hold acceptance, publish readiness if already known and replay the latest pending real level exactly once. Do not replay the same level again when startup later returns.

The helper must check current capture identity and reject feedback when any of these apply: cancelRequested, isTerminating, isFinishing/isSourceFinishing, releaseRequested or stopOrigin/physical release receipt, sourceFailureTask, deferredStartupFailureMessage. The hold gate controls publication, not whether valid evidence can be retained. Recheck after synchronous observer calls if further state mutation follows; do not restore a stale copied Capture after reentrant callbacks.

Order matters:

```swift
// Inside a current, eligible, hold-accepted capture only:
setPhase(.listening(mode: active.mode, engine: active.selectedEngine))
// The event observer renders the listening capsule synchronously.
levelObserver?(actualLevel)
```

Successful startup and hold acceptance must use the same readiness publication rules rather than their current unconditional listening assignments. Startup ownership (isStarting), source/session attachment, stop queuing, and teardown remain separate from visual readiness. A real audio callback may establish feedback before start returns; it must not make the source appear fully attached/drained.

Stop/cancel/failure cannot be followed by fresh live energy or a new Listening transition from late callbacks. Existing finalizing/failure rendering resets waveform energy. Where cancellation or a deferred physical stop leaves a listening capsule visible during drain, immediately forward zero to quiet it and block further live levels; an idempotent terminal zero is acceptable. Do not publish an early terminal outcome or change gesture/teardown semantics merely to clear feedback.

### 2. Existing measurement extension

Extend DictationRuntimeMeasurements only:

```swift
// Stage
case audioReadyObserved
// Stored value and init default
private(set) var audioReadyObservedAt: ContinuousClock.Instant?
```

Include the stage in value/assign/overlay using the existing first-write and terminal rules. Record it once from the coordinator clock at the first accepted readiness signal, whether before or after hold acceptance. Leave it nil when no readiness was observed. Do not add an estimated duration or model-ready value.

Causal checks may require sourceStartRequested <= audioReadyObserved and audioReadyObserved <= asrFinal when both endpoints exist. Do not require readiness to precede physical release, or impose an ordering relative to firstMeaningfulPartial: callbacks and source return can have different observation order. Preserve partial/cancelled measurements and reject actual causal reversals.

### 3. Runtime and visual integration

Do not change FleckApp or capsule production code. Add a gated RuntimeSpeechEngine test double that stores its callback before awaiting startup completion. Test the actual runtime currentCapsuleStatus and waveformModel.energy:

- before readiness while startup suspended: Starting and zero energy;
- valid live callback before startup completion: Listening, then energy > 0;
- zero callback: Listening with quiet static waveform;
- hidden preference: no rendered capsule/energy, even when readiness arrives;
- cancellation/stop while startup suspended: no later live energy or resurrection;
- new capture: stale prior callback cannot establish readiness for the new session.

Render Starting and quiet/live Listening at bottom/left/right in aqua/darkAqua using existing visual helpers. Use synthetic level inputs explicitly identified as fixtures. Reuse existing Reduced Motion cadence/amplitude/transition tests; do not change the user's macOS accessibility preferences or add a production injection API solely to force a screenshot. Hosted rendering reflects the current host motion preference; Reduced Motion algorithm/transition checks are separate evidence, not a claim of packaged-system visual acceptance.

## Verification steps

- [ ] Read owned code and the existing level/runtime/measurement tests. Capture current branch/status and lock hash.
- [ ] Add deterministic gated regression tests before product edits. Suggested names below; use gates with waitUntilWaiting, not arbitrary sleeps or timing-sensitive yield loops as acceptance witnesses.

```swift
@Test @MainActor func captureFeedbackPublishesListeningBeforeDeliveringEarlyLevel() async throws
@Test @MainActor func captureFeedbackReplaysLatestPreHoldLevelOnce() async throws
@Test @MainActor func captureFeedbackZeroLevelEstablishesReadinessWithoutEnergy() async throws
@Test @MainActor func captureFeedbackRejectsLateLevelsAfterReleaseCancelOrFailure() async throws
@Test @MainActor func captureFeedbackStaleCaptureCannotReadyANewCapture() async throws
@Test func captureFeedbackReadinessMeasurementPreservesFirstObservation() throws
@Test @MainActor func DictationRuntimeCaptureFeedbackRendersEarlyLevelAfterListening() async throws
@Test @MainActor func DictationRuntimeCaptureFeedbackRespectsHiddenPreference() async throws
```

Test both legacy engine and processing paths. Reuse gates/probes; add only required fake controls. Use exact expected phase-before-level ordering, latest-level replay once, timestamp identity, and no-late-publication assertions. Add a successful-start-without-level case, finite-input case, and an immediate-cancel/stop quieting assertion during suspended drain. Verify held source failure before threshold cannot regain Listening on threshold acceptance.

- [ ] Run new tests through the nonempty default runner, save complete expected failing output under .build/capture-feedback-1c/red.log, then implement the smallest shared helper and timestamp extension.

```sh
bash Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(captureFeedback[^()]*|DictationRuntimeCaptureFeedback[^()]*)\(\)$'
```

- [ ] Rerun new tests green, then existing changed-area tests. Build an anchored exact filter from listed identifiers, retaining the filter and matched count beside each log. Required regression coverage: existing active-level tests; synchronous processing levels; short taps; held release while loading; Escape; double-tap; pointer start/stop; event-tap loss; focused editor loss; stale generation; hidden-pill and reenable; waveform silence, attack/decay/reset, Reduced Motion; measurement overlay/integrity; 1B source-failure guard/drain tests.
- [ ] Run the enhanced configuration once for the accepted 1B suite plus new coordinator feedback cases:

```sh
bash Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.(EnhancedSpeech[^()]*|enhancedSpeechStartup[^()]*|captureFeedback[^()]*)\(\)$'
```

- [ ] Run the bounded visual test with FLECK_RAIL_CAPTURE_DIR set to an absolute directory under .build/capture-feedback-1c. Parent inspects generated light/dark Starting/listening dock images and existing Reduced Motion assertions; do not claim changed product artwork or actual microphone evidence.
- [ ] Require a completed Swift Testing summary with nonzero count. An exit-zero incomplete run is not a pass. Keep runner failures, compile failures, and test stalls in the evidence record.
- [ ] Existing shortcutReleaseDuringSuspendedStartCancelsUntilStartReturns has an intermittent 1B verification exception. Run it separately with bounded observation, preserve outcomes, and do not expand 1C into unrelated harness surgery. If a new deterministic defect is demonstrated in the changed readiness path, return the evidence to primary and fix within this packet.
- [ ] Parent inspects the entire final diff, independently reruns meaningful focused/default/enhanced verification, and checks Package.resolved unchanged and no unrelated edits. Avoid repeated full enhanced builds after a tiny unrelated default-only correction; repeat only affected evidence.
- [ ] Fresh Sol/High review of the actual immutable diff plus evidence. For fix-first/rethink, same worker corrects; parent re-verifies; a NEW fresh reviewer must return ship.

## Completion and non-goals

One local source commit after acceptance, with a documentation acceptance record linking logs and exact counts. 1C is implemented/integrated/locally-tested only; no packaged verification or release admission. 1D diagnostic expansion, 1E retention evaluation, 1F device acceptance, onboarding, routing, grammar, and repeated-correction learning remain separate.
