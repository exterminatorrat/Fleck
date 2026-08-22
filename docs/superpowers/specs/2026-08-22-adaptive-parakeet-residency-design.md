# Adaptive Parakeet Residency Design

## Goal

Keep Parakeet TDT responsive on roomy Apple-silicon Macs without allowing its
Core ML resources to remain resident when an 8 GB Mac, memory pressure,
thermal pressure, Low Power Mode, sleep, cancellation, or failure makes that
unsafe.

This design changes only Parakeet residency. It does not change transcription
accuracy, add live partials, address the accepted first-word cold-start
limitation, integrate Gemma, admit a model for release, or bundle weights in
Fleck.app.

## Settled product behavior

- Apple Silicon is the only supported architecture for this test path.
- Installed memory and active processor count set a hard upper bound on how
  long Parakeet may remain warm.
- A fresh reclaimable-memory estimate is sampled whenever a normal capture
  releases the model.
- Memory-pressure, thermal, Low Power Mode, sleep, cancellation, model removal,
  and app termination can only shorten residency. They never load a model or
  extend a timer.
- The 8 GB tier may retain Parakeet for at most 15 seconds when reclaimable
  memory is healthy. Low reclaimable memory or any pressure signal collapses
  that window to zero.
- A subsequent capture before a warm timer expires reuses the same verified
  Parakeet inference resources. It never starts a second model load.
- A pressure event during capture does not tear down active inference. It marks
  the model for immediate unload when the capture finishes or cancels.
- Cancellation and inference failure unload immediately. Only successful idle
  release is eligible for warm retention.
- Apple Speech remains the safe fallback.
- No model files are added to the app bundle or ZIP. The model remains an
  explicit, verified local installation.

Apple Silicon uses unified memory. Fleck therefore uses system memory and
memory-pressure signals rather than pretending macOS exposes a reliable free
GPU-memory value. Active processor count caps the warm tier; thermal state and
Low Power Mode are the live compute-pressure signals. Raw CPU-utilization
percentage is deliberately not used because an idle resident Core ML model
primarily consumes unified memory, and utilization would make residency
oscillate without improving safety.

## Policy

All byte thresholds use binary GiB (`1_024 * 1_024 * 1_024`).

### Fixed ceiling

| Installed memory / active processors | Maximum warm retention |
| --- | ---: |
| At most 4 processors | 5 seconds |
| At most 8 GiB | 15 seconds |
| More than 8 GiB and below 24 GiB | 30 seconds |
| 24 GiB through below 32 GiB | 120 seconds |
| 32 GiB or more | 300 seconds |

### Dynamic reduction

The fixed ceiling is reduced at release time:

| Current condition | Effective retention |
| --- | ---: |
| Critical/warning memory pressure | 0 seconds |
| Serious/critical thermal pressure | 0 seconds |
| Low Power Mode | 0 seconds |
| Reclaimable memory below 3 GiB or below 25% of installed RAM | 0 seconds |
| Reclaimable memory below 5 GiB or below 40% of installed RAM | At most 5 seconds |
| Otherwise | Fixed ceiling |

Sleep, app termination, cancellation, inference failure, and model mutation
always unload immediately. Waking or returning to normal pressure does not
preload Parakeet; the next dictation loads it on demand.

The reclaimable-memory sampler uses Mach VM statistics and adds `free_count`
(which already includes `speculative_count`), inactive, and purgeable pages
with checked arithmetic. It validates that speculative pages do not exceed
free pages, reuses one host port for the sample, and deallocates that right on
every exit. If the sampler cannot produce a valid value, the policy fails
closed to zero seconds.

## Architecture

`DictationResourceProfile` captures installed memory and processor count once.
`DictationResourceSnapshot` captures the current reclaimable-memory,
memory-pressure, thermal, and Low Power state. Both have injectable production
providers so policy tests are deterministic.

`DictationRuntimePolicy` remains the pure decision boundary. Existing
critical-memory and lifecycle target-state behavior remains compatible, while a
new retention decision computes the effective Parakeet warm duration from the
fixed profile and current snapshot.

`AdaptiveEnhancedSpeechInference` is a single main-actor wrapper around the
existing `FluidEnhancedSpeechInference`. The app's engine provider injects this
one shared wrapper into each sequential `EnhancedSpeechCapture`. `load(from:)`
reuses a matching verified warm load; `releaseResources()` schedules or
performs policy-directed unload; cancellation performs an immediate underlying
cancel and unload.

`DictationResourcePressureMonitor` observes Dispatch memory-pressure events,
ProcessInfo thermal/power notifications, and NSWorkspace sleep/wake events.
It forwards snapshots or force-cold events to the adaptive wrapper. Monitoring
starts with the dictation runtime and stops during runtime shutdown.

The model manager's installation-cleanup and removal hooks are asynchronous
barriers. Repair, update cleanup, and removal await the shared inference's
force-cold acknowledgement before mutating installed model paths. A callback
that merely schedules cleanup is insufficient because it can race filesystem
mutation.

The dormant `LocalDictationRuntime` is not wired to a duplicate Parakeet load.
Gemma will later receive a separate phase-aware packet so 8 GB Macs never hold
ASR and open-weight cleanup resources simultaneously.

## Failure and cancellation rules

- Repository identity verification remains authoritative before every cold
  load.
- A repository change forces the old warm instance cold before loading the new
  path.
- A cancelled load or transcription cannot be retained warm.
- Timer generations prevent an expired timer from unloading a newly acquired
  capture.
- Repair, update cleanup, and removal cannot enter filesystem mutation until
  the model-mutation barrier has returned.
- System callbacks never block notification delivery on model cleanup; cleanup
  is serialized on the main actor.
- If monitoring or memory sampling fails, Fleck unloads rather than guessing.

## Verification boundary

Unit tests must prove all fixed tiers, both dynamic thresholds, checked/failing
sampling, reuse before expiry, expiry unload, pressure while idle, pressure
during active capture, cancellation unload, repository substitution, and one
underlying load at a time.

The candidate package must then pass focused tests, the full candidate wrapper,
an arm64 build, strict ad-hoc codesign verification, and a bundle scan proving
no model weights. The final ZIP is a local test artifact, not notarized or
release-ready. MacBook validation remains hands-on evidence for launch,
microphone behavior, first/cold dictation, repeat latency, memory response, and
fallback.

## Deferred work

- Gemma 3 1B 4-bit qualification and integration.
- Phase-aware ASR-to-cleanup handoff that prevents concurrent open-weight model
  residency on constrained Macs.
- The accepted first-word cold-start behavior.
- Developer ID signing, notarization, redistribution approval, release
  admission, and public packaging.
