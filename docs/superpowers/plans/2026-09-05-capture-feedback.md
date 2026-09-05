# Capture and Feedback Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development task-by-task. Current user and AGENTS.md routing override skill defaults: Codex-native GPT-5.6 Sol / High workers, same worker for corrections, fresh Sol / High reviewer with exact `ship` verdict. No Terra or user-visible implementation task.

**Goal:** Make the shortcut immediately understandable and protect speech captured during cold model startup on the 8 GB M1 MacBook Pro.

**Architecture:** Reuse the existing coordinator, enhanced audio capture, inference lifecycle, and capsule. First expose a truthful starting state. Then separate audio readiness from model readiness with bounded ownership and stop/cancel semantics before tuning residency.

**Tech Stack:** Swift 6, AppKit/SwiftUI, AVFAudio, Swift Testing, existing Parakeet/FluidAudio candidate integration.

**Spec:** [Capture and Feedback Design](../specs/2026-09-05-capture-feedback-design.md).

## Global constraints

- Base: verified `68b6b429ab4f1f130252d9865a2c616b7224cca7` or legitimate descendant; use the isolated worktree.
- Preserve all accepted UI and dictation/cleanup/routing/model features.
- Apple Silicon and English; no new dependencies or model choice changes.
- No microphone before explicit user action and granted permission.
- No cloud, transcript upload, hidden fallback, or bundled/downloaded model weights.
- Preserve cancellation, short-tap, double-tap, focused editor, and pointer capture behavior.
- No push, PR, merge, installed-app replacement, or release admission.
- Source code only changes through the assigned worker; parent inspects and independently verifies.
- Each packet must receive fresh Sol/High `ship` before a dependent packet starts.

## Execution boundary

Begin with 1A. Its success permits proceeding to the bounded 1B architecture preflight, not claiming the MacBook issue fixed. Packets 1B–1F remain separately reviewable, and device/package actions obey the existing authorization boundaries.

## Packet 1A — Immediate, truthful starting feedback

### 1. Objective and success criteria

Arming must look different from idle as soon as the coordinator publishes it. It must visibly say “Starting,” preserve the accessible “Starting dictation” message, and show no fake live waveform. No artificial sleep or processing-label delay may gate this feedback.

### 2. Owned files and interfaces

- Modify `Sources/FleckApp/DictationCapsule.swift`: arming presentation/copy, dimensions, and view selection only.
- Create `Tests/FleckAppTests/DictationStartingFeedbackTests.swift`: focused behavioral presentation tests.
- Modify `Tests/FleckAppTests/DictationCapsuleVisualCaptureTests.swift`: update arming capture sizing and add all-dock startup captures if required.
- Modify `Tests/FleckAppTests/DictationAccessibilityTests.swift`: only the existing arming size/text expectation and directly necessary arming assertions; ownership expanded after worker preflight found the old idle-size/nil-text contract.
- Read existing tests that reference capsule sizing/arming. If an existing assertion requires modification outside these paths, report the exact file before editing.
- Preserve `DictationCapsuleStatus.arming`, `DictationCapsuleContext`, `render`, and the coordinator interface. No new application state or setting.

### 3. Implementation and non-goals

Use an existing compact text layout with enough width for Starting. Keep the existing mark and styles. Make the arming branch explicit rather than sharing idleContent. Do not route arming into a waveform or claim Recording. Ensure panel hit testing/corner geometry agrees with the chosen size. Retain dock orientation and recovery actions.

Expected test contract using existing types:

```swift
@Test @MainActor func startingFeedbackIsVisibleAndTruthful() {
  let presentation = DictationCapsulePresentation(status: .arming)
  #expect(presentation.visibleText == "Starting")
  #expect(presentation.voiceOverText == "Starting dictation")
  #expect(presentation.visualMode == .arming)
  #expect(DictationCapsuleController.size(for: .arming).width
    > DictationCapsuleController.size(for: .idle).width)
}
```

Additional tests must render/inspect a real hosted view so a string in the presentation model cannot pass while the UI still shows only the idle mark. Reuse visual capture infrastructure; assert actual bounds and inspect exported PNGs. Check Reduced Motion and all docks. Do not add a test-only production API merely to inspect a string.

Non-goals: audio startup, coordinator semantics, hold threshold, retention, model load, microphone permissions, routing, grammar, Settings redesign.

### 4. Verification sequence

- [ ] Read the owned source and existing presentation/visual tests fully.
- [ ] Add the minimal new test(s); run before production changes and retain the expected assertion failure.
- [ ] Apply the smallest presentation change.
- [ ] Run focused tests through the nonempty runner:

```sh
bash Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(startingFeedback.*|DictationCapsule.*|.*[Cc]apsule.*|.*[Ww]aveform.*)\(.*\)$'
```

- [ ] The runner must list nonzero matching tests and all selected tests must pass. Adjust the anchored identifier regex to actual listed names if needed; never count a zero-test run as success.
- [ ] Render using the existing visual test:

```sh
FLECK_RAIL_CAPTURE_DIR="$PWD/.build/capture-feedback-1a" bash Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationCapsuleVisualCaptureWritesRailStateMatrixWhenRequested\(\)$'
```

- [ ] Parent opens the produced arming images and compares idle/listening/finalizing at every supported dock: bottom, left, right. There is no top dock in the baseline; do not add one. No clipped text or unnecessary animation.
- [ ] Run the existing hold/coordinator regression tests using their actual discovered identifiers; preserve short-tap and cancellation behavior.
- [ ] `git diff --check`; inspect full diff and `git status --short` for scope/lockfile changes.
- [ ] Parent independently reruns relevant checks, then fresh Sol/High review.

### 5. Authority and handoff

The worker is not alone in the codebase. Preserve other edits, adapt to concurrent work, and do not revert unrelated files. No edits outside ownership, no downloads, no install/launch of another app, no external writes, and no commits until parent requests a checkpoint. Report exact diff, red/green commands and counts, artifacts, limitations, and any expanded-ownership request. Corrections return to this worker.

## Packet 1B — Audio-first startup with bounded ownership

**Prerequisite:** 1A accepted; primary completes and reviews a lifecycle amendment before delegation.

The 2026-09-05 resumption uses [the audio-first lifecycle amendment](../specs/2026-09-05-audio-first-startup-amendment.md) as the authoritative 1B interface, ownership, timeout, buffering, and failure contract. It distinguishes prompt microphone shutdown from truthful native inference drain; arbitrary native teardown cannot be force-bounded in-process.

**Source map:** `EnhancedSpeechCapture.swift`, `DictationInterfaces.swift`, `AppleSpeechStreamingAdapter.swift`, `StreamingDictationProcessor.swift`, `DictationCoordinator.swift`; tests in `EnhancedModelManagerTests.swift`, `DictationCoordinatorTests.swift`, and a new `EnhancedSpeechStartupTests.swift` where candidate compilation allows it. Exact mutable subset is fixed after preflight; these are candidate ownership paths, not blanket authorization.

### Preflight deliverable

- [ ] Trace start, physical release, finish, cancel, failed load, repair mutation, and resource teardown across all callers.
- [ ] Document which operation owns the audio buffer while model loading is suspended.
- [ ] Choose an explicit bounded startup timeout and audio buffer limit from current format and existing limits; quantify memory as sampleRate × channels × Float bytes × seconds.
- [ ] Define whether start returns at audio-ready or model-ready. Account for coordinator isStarting behavior and short tap cancellation.
- [ ] Require stop to cease audio before waiting on model readiness; a post-release load must not extend the recorded utterance.
- [ ] Avoid introducing overlapping owners in LoadingResources and Resources that double-release inference or audio.
- [ ] Review the amendment before implementation; if safe ownership cannot fit the bounded packet, split by a stable interface rather than shipping an unsafe reorder.

### Required red-first cases

| Test | Controlled input | Required assertion |
| --- | --- | --- |
| Cold first sample | Inference loader suspended on a continuation | Audio start precedes loader completion; injected early samples reach transcribe in order |
| Permission denied | Permission closure returns denied | Audio never starts; inference does not begin |
| Model unavailable | Verified state unavailable | No audio activation or silent download |
| Stop while loading | User release before loader completes | Audio stops at release; no later samples enter buffer; finite captured samples remain available |
| Cancel while loading | Cancel before loader completion | Audio stops before awaited cleanup; late model completion cannot transcribe or insert |
| Load failure | Loader throws | Audio stopped/released once; existing failure recovery preserved |
| Late old callback | Start/cancel/start sequence | Old level/result cannot affect new capture |
| Hung load/buffer limit | Loader remains suspended | Bounded failure/teardown; no unbounded audio retention |
| Model invalidation | Verified URL changes during startup | No use of invalidated assets; audio stopped safely |
| Short tap | Release before existing hold acceptance | No insertion and no surviving microphone capture |

Tests use fake audio and suspended inference, not real microphone or model downloads. Start with a failure that specifically establishes old load-before-audio ordering. Verify candidate tests are truly compiled; default builds exclude EnhancedSpeechCapture.

Candidate test entry point:

```sh
bash Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.(enhancedSpeechStartup.*|.*Enhanced.*|.*[Cc]ancel.*)\(.*\)$'
```

Read the runner and lockfile policy first. No fixture may load weights. Parent must independently run the same nonempty selection and inspect lifecycle diff; fresh reviewer must say `ship`.

## Packet 1C — Recording readiness and gesture integration

**Prerequisite:** Accepted 1B lifecycle contract.

Candidate files: `DictationInterfaces.swift`, `DictationProcessingModels.swift`, `StreamingDictationProcessor.swift`, `DictationCoordinator.swift`, `FleckApp.swift`, `DictationCapsule.swift`, and directly corresponding tests. Fix exact ownership from the accepted interface; do not spread ad hoc booleans across these files.

- [ ] Reuse or minimally extend existing capture measurements to represent actual audio readiness separately from model readiness.
- [ ] Show live energy only after a current-session audio callback/readiness event; maintain honest Starting before that point.
- [ ] Ensure a quiet microphone is a quiet waveform and stale callbacks are ignored.
- [ ] Test held startup, release while loading, Escape, pointer start/stop, double tap, fast repeat, focused editor loss, and event-tap loss.
- [ ] Maintain existing 180 ms short-tap interpretation unless separate device evidence justifies a change.
- [ ] Test hidden capsule preference; do not force the pill on as a workaround.
- [ ] Render all docks with Reduced Motion and dark/light appearances; compare accepted listening design.
- [ ] Parent test rerun and fresh `ship` review.

## Packet 1D — Diagnostic evidence without transcript collection

**Prerequisite:** Stable 1B/1C timing boundaries.

Candidate files: existing `DictationProcessingModels.swift`, coordinator measurement code, and existing diagnostic/evaluation consumers. Do not create a parallel telemetry system.

- [ ] Record event received, feedback published, audio start requested, first audio buffer, model-ready, stop, ASR final, cleanup, route, save, and cancellation teardown where observable.
- [ ] Mark unobserved stages unavailable; never substitute zero or synthetic timings.
- [ ] Distinguish model cold/warm, permission denied, missing device, load failure, timeout, and buffer limit.
- [ ] Keep event timing separate from external physical-key/video measurements.
- [ ] Preserve per-session isolation and bounded retention; exclude audio, transcript, personal Vocabulary, and note bodies from diagnostic exports.
- [ ] Test partial/cancelled sessions and failed stages; report limitations explicitly.

## Packet 1E — Resource policy after capture correctness

- [ ] Run the same cold/warm/after-Gemma scenarios before and after 1B/1C.
- [ ] Measure 8 GB M1 at normal and low reclaimable memory, Low Power Mode, after idle, and after wake; use Mac mini control separately.
- [ ] Compare first-buffer latency, first-word recall, model-ready time, final output latency, peak RSS, and residual RSS.
- [ ] Change retention only if repeatable evidence supports a bounded improvement; preserve memory/thermal/sleep invalidation.
- [ ] Do not keep Gemma and Parakeet co-resident by default without evidence and a separate reviewed policy packet.
- [ ] If current retention is acceptable after audio-first repair, leave policy unchanged and record that decision.

## Packet 1F — Exact packaged-app and device acceptance

No installed-app replacement is implied by source work. Prepare a separately named local candidate only when packaging is authorized; do not overwrite the canonical app. Model acquisition remains separately authorized.

Before capture: record commit/tree, clean source state, build flags, executable/helper hashes, manifests, OS/RAM, microphone, selected engines, model receipts, and power/pressure state.

| Scenario | Repetitions per Mac | Pass signal |
| --- | --- | --- |
| Cold model, immediate first word | 10 | First word retained; visible Starting promptly; actual audio readiness measured |
| Warm repeat | 10 | Same correctness, stage timing distribution recorded |
| Capture after Gemma | 10 | No missing beginning after ASR unload |
| Short tap, hold, double tap, pointer | 5 each | Intended gesture and exactly one terminal result |
| Escape during load/capture/finalization | 5 each | No late insertion; microphone stops promptly |
| Silence | 5 | No invented transcript/waveform |
| Long speech, 30 seconds and 2 minutes | 3 each | Complete ordered audio, bounded memory, honest downstream cleanup result |
| Sleep/wake and microphone switch | 5 each | Recoverable state, no stuck microphone or pill |
| Low Power Mode and memory pressure | 5 each | Capture remains safe; failures explained; no unsupported latency claim |

Record every trial, including failures. Initial target: feedback p95 ≤100 ms after event delivery; audio readiness p95 ≤200 ms with permission already granted. These are evaluation targets, not promises. Report physical-key-to-feedback independently using device observation. Any lost first word, late insertion, or microphone surviving cancellation blocks phase acceptance.

## Dependency and status ledger

| Packet | Depends on | Shared boundary | Status |
| --- | --- | --- | --- |
| 1A | baseline | Capsule presentation only | Implemented; parent verified; fresh Sol/High ship |
| 1B | 1A review + lifecycle amendment | Speech source/coordinator startup ownership | Implemented locally; parent verified; fresh Sol/High ship |
| 1C | 1B review | Startup readiness and current session identity | Planned |
| 1D | 1B/1C reviews | Actual stage boundaries | Planned |
| 1E | 1B–1D evidence | Residency and measured memory | Planned |
| 1F | Accepted source packets + packaging authority | Exact artifact and real microphone | Pending device/package work |

Only 1A is an executable implementation packet at plan creation. Later ownership/interface contracts are deliberately gated on accepted prerequisite evidence; the broad program must not be mistaken for authority to edit every listed file.

## Packet 1A acceptance record — 2026-09-05

- Changed only DictationCapsule.swift and three owned test files. Starting is visible at 104×36, has the hosted Starting dictation accessibility label, and has zero entrance duration in normal/Reduced Motion. No audio/model changes.
- Worker observed the expected failing assertions before production edits, then passing focused and gesture tests.
- Parent inspected the complete diff and independently completed 35/35 focused tests, including the changed accessibility contract, plus a separate 1/1 visual export. Bottom/left/right images were inspected.
- An exploratory 88-test accessibility selection exited without a complete Swift Testing result; it is not counted as passing. No unrelated harness or chooser changes were made.
- Fresh Sol/High reviewer verdict: `ship`, no required corrections. Reviewed patch SHA-256: `775bde36bf35d0164bd32a3b002e7a38d28161823e8b0e700488628d7b65470d`.
- Local evidence: `.build/capture-feedback-1a/parent-focused.log`, `parent-visual.log`, `parent-verification.log`, `red.txt`, `green.txt`, and `parent-visual/` PNGs.
- Package.resolved remained unchanged. Canonical installed executable still hashes to `51983a0685e904781dd252278380d1cda093a641beb6d5336013049645887ef0`.
- Next: packet 1B lifecycle amendment and red-first audio-first startup work. This record does not claim microphone latency improvement, first-word recovery, packaged verification, or phase completion.


## Packet 1B acceptance record — 2026-09-05

- Local source commit: `157f737`. Eight owned source/test files; no change to residency policy, Settings, capsule, cleanup, routing, model selection, or dependency lock.
- Enhanced capture starts audio before model load, retains early samples in order, and stops/takes audio before awaiting load on finish. Permission cancellation and late callbacks cannot activate a stale capture. Source failure reaches the processor/coordinator without another key press.
- Startup deadline: 15 seconds. Converted audio ceiling: 4,800,000 mono Float32 samples (five minutes at 16 kHz). Overflow fails the entire capture. These are safety bounds, not measured performance or quality claims.
- Cancellation/failure stops audio and clears pending owner-held samples before native drain. A non-cooperative native operation keeps the owner reserved until actual teardown; no force-kill or bounded native drain is claimed.
- Parent independently inspected the complete diff and completed 59/59 enhanced tests on the final correction, including adaptive/shared inference and converter tests, plus 24/24 default lifecycle/shortcut regressions. Full logs: `.build/capture-feedback-1b/parent-enhanced-atomic.log` and `parent-default-24.log`; filters are retained alongside them. Converter-only final corrections do not change the default build.
- Verification exception: the expanded 25-test default selection repeatedly stalled at `shortcutReleaseDuringSuspendedStartCancelsUntilStartReturns`; a current isolated run also stalled, while later uninstrumented current and exact pre-1B baseline isolated runs completed 1/1. Cause remains unresolved. No 25/25 claim, no dismissed baseline-bug claim, and no test suppression or product workaround. Logs include `parent-default-pty.log`, `parent-shortcut-isolated.log`, `baseline-df77d2b-shortcut-suspended-start.log`, and `current-shortcut-suspended-start-uninstrumented.log`.
- Valid red-first evidence covers startup order, cap, failure buffering/drain, late finalization failure, load admission, independent loader cancellation, and synchronous legacy-start failure. The converter lock-race corrections use semantic regressions plus direct atomicity inspection; no forced-interleaving RED is claimed.
- Two fresh reviews requested converter atomicity corrections; both returned to the same Sol/High worker. Final fresh reviewer `audio_first_atomic_review` verdict: `ship`. Reviewed patch SHA-256: `51df6638e5462f30ed665bc951af13f363c3cca1abeb1b7ba006155e962ad5f7`.
- Package.resolved unchanged at `ccf30f62d44719e9859266a373bb0219dbbd1e0f73d17667b50d7d87715a09f7`. Canonical installed executable unchanged at `51983a0685e904781dd252278380d1cda093a641beb6d5336013049645887ef0`.
- Status: implemented and integrated on the isolated local branch; locally tested with the exception above. Not packaged-verified or release-admitted. No real microphone, model weights, physical-key latency, first-word accuracy, or MacBook memory-pressure evidence was collected. No model download, push, PR, merge, or installed-app mutation.
- Packet 1C remains next and has not started. Phase 1 remains open.
