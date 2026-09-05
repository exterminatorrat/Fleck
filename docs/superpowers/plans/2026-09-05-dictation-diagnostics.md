# Packet 1D — Content-free dictation diagnostics

Status: planned; implementation authorized. Base: `503d193`, including accepted 1C source `8e1d1fa`.

Use superpowers subagent-driven development and red-first TDD. The active user-selected lane is native GPT-5.6 Sol / High implementation, the same worker for corrections, parent verification, and a fresh Sol / High reviewer whose verdict must be `ship`.

## 1. Objective and success criteria

Extend `DictationRuntimeMeasurements` to explain one capture's observed startup, finalization, and teardown without retaining or exporting speech content. Reuse the existing measurement merge chain; expose a computed, allowlisted Codable projection from the coordinator's latest measurements. No second telemetry recorder, history, export sink, or UI.

Record coordinator event receipt, phase publication, audio start request, first input buffer, model load request/readiness, stop, ASR final, cleanup, routing, persistence, and cancellation drain where each is actually observable. Preserve unavailable timestamps as explicit JSON nulls. Distinguish known cold/warm load disposition and stable typed failure categories, especially permission denial, missing input, model load failure, startup timeout, and buffer limit. Unknown evidence remains unknown.

## 2. Ownership, interfaces, constraints

Worker owns exactly these production files:

- `Sources/FleckApp/DictationProcessingModels.swift`
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Sources/FleckApp/AppleSpeechStreamingAdapter.swift`
- `Sources/FleckApp/EnhancedSpeechCapture.swift`
- `Sources/FleckApp/AdaptiveEnhancedSpeechInference.swift`

Worker owns directly related tests in:

- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift`
- `Tests/FleckAppTests/EnhancedSpeechStartupTests.swift`
- `Tests/FleckAppTests/AdaptiveEnhancedSpeechInferenceTests.swift`

Parent owns documentation. No other edits without a revised bounded specification. Preserve unrelated and concurrent work; the worker is not alone in the repository. Keep existing source compatibility with default empty/unavailable protocol implementations and initializer defaults. Preserve existing errors and cancellation behavior; do not wrap errors to transport diagnostics.

## 3. Implementation and non-goals

### Measurement value and projection

Add only required stages and bounded enum metadata to the existing value. Preserve first-write observation, causal validation, overlay, and terminal cancellation fencing. Metadata must obey equivalent fencing. Keep actual physical key receipt timestamps distinct from coordinator receipt and phase-publication timestamps. Phase publication is not a rendered frame or proof the pill was visible.

The projection contains a schema version, integrity, stable outcome/failure/load-disposition enums, and all known stage keys mapped to optional elapsed milliseconds from the earliest observed instant. Omit absolute clock instants, capture UUIDs, paths, raw errors, localized text, transcript, Vocabulary, note content, audio, and device identifiers. Missing stages must encode null, not disappear or become zero; invalid-clock timings must not look valid. A zero at the observed origin is legitimate. No export file is written automatically.

### Source and processing propagation

Add default-empty measurement accessors to `SpeechEngine`, `StreamingSpeechSource`, and `DictationProcessingSession`; forward through the existing adapter. Overlay source measurements in the concrete processing session. Retain a single capture-ID-fenced startup measurement snapshot in the processor, readable through a default-empty `runtimeMeasurements(for:)` protocol method, so coordinator startup failures can preserve observations even when no session was returned. Cover factory failure and validation failure without changing original thrown errors. Do not retain sources or audio in this snapshot; stale completions must not overwrite newer captures.

Merge source/session snapshots at observed success, failure, and cancellation boundaries before destructive teardown, and after drain where necessary. Retain only the coordinator's latest capture. Keep late callbacks fenced by capture identity and terminal cancellation state. Preserve late ambiguity resolution measurements; do not freeze successful persistence before an existing user resolution can be observed. Fill missing legacy stop/ASR/cleanup boundaries only at their real call sites.

### Enhanced capture

Store observations with the existing Resources ownership and preserve the latest content-free value after release. Reset on an accepted new start, not a rejected busy start. Use the existing injected startup clock for actor-side observations. Record audio start request immediately before the actual audio start call and model readiness only after successful validated loading.

Expose an optional first-input-buffer timestamp from the converter under its existing lock. Observe a nonempty input buffer at callback receipt, before conversion; use an injectable monotonic clock for deterministic tests. Do not infer it from level callbacks, model readiness, or accumulated samples. Snapshot before cancellation destroys the converter. Add no queue, callback per buffer, content retention, or lock outside the existing discipline.

Expose a narrow load-disposition query with default unavailable. Adaptive inference reports warm only for an idle, loaded matching repository, cold for an actual fresh/replacement load, and unavailable for unsupported/busy evidence. Fluid inference may report cold for its known fresh load. Do not modify residency, reuse, release policy, or timers.

Classify typed failures at their known cause sites, never by matching localized error strings. Validate unusable input format before installing the tap and classify it as missing input. Model load catch, timeout, sample limit, permission denial, and unavailable model must stay distinguishable; cancellation is a separate outcome. Keep existing recovery copy unchanged except any new typed missing-input error's necessary message. Apple internals without a synchronous observation seam remain unavailable; do not refactor the Apple actor capture pipeline for this packet.

No retention-policy tuning, hardware capture, packaged launch, Settings changes, evaluation schema migration, logger, persistent diagnostic store, or new dependency. No claim of physical-key latency, first-word retention, real-microphone performance, or release acceptance.

## 4. Verification and expected evidence

Name new tests `dictationDiagnostics...` and run them red before product changes. Compile failures from genuinely missing new interfaces may establish red, followed by meaningful behavioral green assertions. Use deterministic gates/clocks rather than arbitrary sleeps.

```sh
bash scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.dictationDiagnostics[^()]*\(\)$'
bash scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.dictationDiagnostics[^()]*\(\)$'
```

Save commands, exact filters, matched counts, complete summaries, and logs under `.build/dictation-diagnostics-1d`. Required coverage: all-stage explicit null serialization and content exclusion; observed zero versus unavailable; first-write/overlay/integrity; cold/warm/unknown; permission/missing-input/load/timeout/buffer categories; partial and cancelled sessions; startup failure without a returned session; snapshot survival after release; stale capture and stale resource completion fencing; first input buffer before conversion independent of level delivery; cleanup/routing/save and cancellation drain boundaries. Tests must inspect actual coordinator/source propagation, not just construct a projection directly.

Rerun existing measurement, processor, adapter, Enhanced startup, adaptive inference, cancellation/gesture and accepted 1C feedback coverage using anchored exact listed identifiers and nonempty runners. The two previously baseline-reproduced stalls (`handsFreeStartupOwnsEscapeBeforeProviderReturns`, `handsFreeStartupMonitorLossCancelsBeforeProviderReturns`) are exclusions, not passes; investigate only if changed behavior implicates them. Do not run concurrent Swift configurations. Preserve ordinary `Package.resolved`; test source resolution is authorized, model weights are not.

Parent independently inspects the full diff and reruns focused/default/enhanced checks. Fresh reviewer inspects actual diff and evidence. For fix-first/rethink, send a corrected specification to the same worker, then repeat affected parent checks and obtain a new fresh review.

## 5. Authority and handoff

Worker must not commit, push, open/merge a PR, change branches, install/launch/package apps, download models, or use the microphone. Return changed paths, red/green evidence, exact counts, limitations, and any unresolved issue. Parent makes a focused local source commit only after `ship`, records acceptance and immutable evidence, and reports the exact local status. Packets 1E and 1F remain unstarted.
