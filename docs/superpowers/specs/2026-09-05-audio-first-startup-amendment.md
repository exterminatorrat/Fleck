# Packet 1B — Audio-first startup lifecycle amendment

**Status:** Architecture reviewed `ship` by fresh Sol/High reviewer; implementation authorized, 2026-09-05. User explicitly authorized packet 1B. Prerequisite 1A is accepted at c23cb21; starting HEAD 68e6528 descends from current origin/main 68b6b429.

## Objective

For an eligible, permission-granted enhanced capture, start the microphone before waiting for Parakeet model load. Retain early samples in order. Release stops capture immediately even while the model loads; Escape stops capture before any asynchronous model teardown. No late work may insert text or change a newer capture.

## Architectural decision

`EnhancedSpeechCapture.start` will complete when audio capture is active, not when the model is ready. It schedules one owned model-loading task and keeps that task with the same resource owner as the audio device. `finish` synchronously stops/takes the audio before awaiting model readiness. Consequently the existing coordinator receives a processing session promptly and does not defer a physical stop behind model load.

Reuse the existing SpeechEngine, StreamingSpeechSource, adapter, processing session, and coordinator. Do not add a second capture engine or a global event bus. The accepted Starting UI remains unchanged; after start returns the existing Listening state truthfully represents active audio even while the model loads. Explicit model-ready diagnostics belong to 1D.

## Required interface changes

Add a failure-aware overload to SpeechEngine and StreamingSpeechSource:

```swift
func start(
  provisional: @escaping @MainActor @Sendable (String) -> Void,
  level: @escaping @MainActor @Sendable (Float) -> Void,
  failure: @escaping @MainActor @Sendable (Error) -> Void
) async throws
```

Default protocol implementations forward to the existing two-callback start for unchanged Apple Speech engines/test doubles. EnhancedSpeechCapture implements the new overload; its old overload forwards into it with an empty failure callback, so both enhanced overloads use audio-first semantics. AppleSpeechStreamingAdapter forwards the new overload to its engine.

StreamingDictationCallbackBuffer must buffer the first source failure until its session attaches, discard subsequent provisional updates after failure, and deliver the failure once. The session closes its updates with the error and stores it as terminal source failure; finalization must not turn that failure into successful text. The coordinator handles a source failure through an independent task, guarded by capture identity and cancellation state, without awaiting its own processingUpdatesTask. Cancellation must win over a competing failure.

The legacy non-processing coordinator path also supplies the failure callback and uses the same identity/cancellation guards. Do not silently leave enhanced callers without asynchronous failure handling.

## One owner, bounded capture, truthful drain

- Reserve a generation before awaiting permission. Cancellation while permission is pending must prevent later audio activation. A second start cannot overlap a pending start or draining resource owner.
- Check verified local model eligibility and permission before audio starts. Recheck the verified repository after load and before transcription. No downloads or fallback transcription is attempted in the current capture.
- One resource owner contains audio, inference, load task, timeout task, transcript task, first failure, and release ownership. Exactly-once release replaces separate loading/loaded owners where possible.
- Start audio, then schedule load. First buffer order is preserved; no trimming of initial silence or samples is introduced.
- Failure or cancellation synchronously disables level delivery, stops audio, and drops capture samples before awaiting inference cancellation/release.
- On normal finish, stop/take samples once before awaiting loading. Do not record extra samples after the user's stop. Model completion may consume only the frozen sample array.
- A startup watchdog expires after **15 seconds** from audio start if model readiness has not been established. It records a distinct local startup timeout, stops audio, and requests inference cancellation. Use an injected sleeper/clock for deterministic tests; no wall-clock waits in the suite.
- Raw converted audio is capped at **4,800,000 mono Float32 samples** (five minutes at 16 kHz; 19,200,000 payload bytes, excluding array capacity/converter and inference allocations). Overflow fails the whole capture; never silently truncate and save incomplete text. Detect the bound before append and report once through the live failure path. The five-minute ceiling is an initial explicit safety bound, not a promise of five-minute inference quality.
- Audio conversion/device errors must be reported once, not swallowed by the tap's existing `try?`, while retaining off-main audio-tap safety. Do not enqueue one failure per incoming buffer.
- A loader that ignores cancellation cannot be force-killed safely inside this process. Audio capture and buffer growth must already have stopped. Keep the resource owner reserved/quarantined until real inference drain completes; do not claim cancellationDrained, free references prematurely, or admit an overlapping load. Native inference teardown may outlast the watchdog; the watchdog bounds recording, not arbitrary OS/model teardown. This is an explicit limitation to test and report, not an invented hard teardown guarantee.
- Show a source failure state promptly where safe, but retain the coordinator capture reservation until actual drain. Do not publish a successful or fully drained terminal record while resources remain in flight.

## Failure distinctions

Permission denial never starts audio. Ineligible/changed model uses existing unavailable/repair recovery as appropriate. Model load/transcription failure retains existing model repair behavior. Cancellation, audio-device failure, capture-length overflow, and startup timeout must not mark valid model files corrupt merely because they occurred during an enhanced capture. Preserve any existing fallback recommendation policy unless a test demonstrates it conflates device/cancellation failure with model corruption; scope such a correction to this lifecycle.

## Exact implementation ownership

- Sources/FleckApp/EnhancedSpeechCapture.swift
- Sources/FleckApp/DictationInterfaces.swift
- Sources/FleckApp/AppleSpeechStreamingAdapter.swift
- Sources/FleckApp/StreamingDictationProcessor.swift
- Sources/FleckApp/DictationCoordinator.swift
- Tests/FleckAppTests/DictationCoordinatorTests.swift (existing enhanced fakes/assertions and directly affected lifecycle tests only)
- Tests/FleckAppTests/StreamingDictationProcessorTests.swift (failure callback buffering/finalization only, if file exists)
- Tests/FleckAppTests/EnhancedSpeechStartupTests.swift (new focused candidate tests)

Any additional path requires primary approval before modification. No changes to DictationCapsule, resource-retention policy, Settings, routing, grammar, model selection, lockfiles, or build configuration.

## Red-first verification

1. Gated model load: start returns and audio is already active while load is suspended. Early injected samples arrive unchanged at transcribe after release.
2. Physical release while loading: audio stop precedes load completion; no post-release sample accepted; exactly one result after load succeeds.
3. Escape while loading/finishing: audio is stopped before the cancellation-ignoring loader gate opens; no late output; resources remain reserved until drain and release exactly once.
4. Permission suspended then cancelled: granting permission later cannot open audio.
5. Model unavailable, permission denied, audio construction/start failure: no unexpected load, leak, repair flag, or late callback.
6. Model load failure or repository invalidation: current capture fails, audio stops, no transcription, no stale error in subsequent capture.
7. Injected watchdog expiry with non-cooperative load: audio stops, failure is observable, teardown remains truthfully pending until loader releases; no overlap or false drained measurement.
8. Converter receives an append that crosses the sample ceiling: no over-limit storage, no truncated successful output, one error callback; existing exact sample conversion/drain tests still pass.
9. Source failure before session attachment and after attachment: delivered once; coordinator reaches failure without waiting for another key press; no self-await deadlock.
10. Existing short-tap, double-tap, pointer, focused capture, cancellation, and stale-generation regressions pass. Old tests requiring model failure to precede any audio are updated explicitly to require audio start followed by safe stop under the new contract.

Use existing gates/fakes. Do not invoke real microphones, weights, or helper acquisition. Enhanced tests must actually compile the enhanced candidate, enumerate nonzero matches, and end with a completed Swift Testing summary; an exit-zero incomplete run is not a pass.

## Review and authority

Primary independently inspects all source/test changes and reruns selected enhanced and default regression suites. A fresh Sol/High reviewer must return `ship`. Corrections go to the same Sol/High worker. No commit until requested, no model download, no app build/install/launch, no push/PR/merge, no GitHub writes. Local compilation/tests may resolve pinned source dependencies through the existing enhanced runner; that is not permission to acquire model weights. The installed canonical app remains unchanged.

## Evidence boundary

Source-level acceptance demonstrates ordering, sample preservation with fakes, resource ownership, and failure handling. Actual physical-key-to-audio latency, real Parakeet first-word quality, memory-pressure behavior, and MacBook package acceptance remain device gates. This packet does not complete Phase 1 or release admission.
