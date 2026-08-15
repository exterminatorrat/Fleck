# Local Dictation Streaming and App Integration Implementation Plan

> **For agentic workers:** REQUIRED ROUTE: Workstream B is a dependency-ordered phase, not one task. Each numbered task below is its own separate user-visible Codex task running GPT-5.6 Luna/Max with a title of `Agent - <singular task>`; the parent Sol task inspects and reruns that task, and a fresh `sol_advisor_sol_reviewer` must return exactly `ship` before the next dependent numbered task. Terra/native subagents are forbidden. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile the restored streaming runtime with the accepted cleanup
seam, adapt the existing Apple Speech engine as the only live microphone source,
and make DictationCoordinator own one cancellable incremental transaction.

**Dependency:** Start only after Workstream A Task 2 is committed on top of
`4212314398853091fa85e7aec18318b9650e8604`; Workstream A Task 0 must already
have restored the four final `898ceae` personal-dictionary files. The parent
records the dependent SHA, reruns Workstream A's checks, and obtains a fresh Sol
ship verdict before Workstream B Task 1.

**Architecture:** The coordinator receives one optional
`DictationProcessing` dependency. The standard incremental path creates an
`AppleSpeechStreamingAdapter` around the already-created `SpeechEngine` from
`DictationSpeechEngineProvider`. The adapter forwards provisional text, level,
final text, cancellation, and resource release; it creates no audio engine,
recognizer, tap, or second microphone session. The legacy path remains the
existing `SpeechEngine` plus final `TranscriptCleaning` path, and one capture
selects exactly one path.

**Tech Stack:** Swift 6, Foundation, Swift Concurrency, Speech/AVFAudio only
through `AppleSpeechCapture.swift`, Swift Testing, and the existing SwiftUI
application. No package dependency, downloader, model weight, or audio
replay/archive buffer is introduced.

## Global constraints

- Reconcile the historical evidence in `da0f297`, `77d8320`, `470cd01`,
  `d89d8b3`, and `c4d87a4`; port only behavior that fits the current
  `SpeechEngine` boundary.
- DictationCoordinator remains transaction owner for capture UUID, editor
  provisional state, cancellation generation, history, routing, insertion, and
  recovery presentation.
- Apple Speech requests require on-device recognition and fail when the locale
  or device cannot provide it. There is no network recognition or hidden
  fallback.
- Stable text is append-only. Only the newest two clauses or 80 lexical words
  remain mutable. A stale generation or stable-prefix regression is rejected
  before editor publication.
- Dictionary resolution precedes cleanup. A valid
  Workstream A Task 0's `PersonalDictionaryResolution.baseline` is the only cleanup input. Unsafe or
  unavailable cleanup inserts that exact baseline. Dictionary failure before a
  baseline returns raw ASR text and makes no cleanup request.
- `IncrementalTranscriptCleaner` is the only cleanup authority in the
  incremental path. The coordinator never calls legacy
  `TranscriptCleaning.clean(_:)` after a processing result.
- After cancellation, no update, result, history mutation, route, insertion, or
  recovery receipt may publish. Every guard is repeated after an `await`.
- `FoundationModelDictation.cleanupResult(_:)` remains the Apple Foundation
  Models/deterministic control. Workstream B adds only a bounded wrapper.
- The ordinary application path is model-free and does not load, download,
  select, log, persist, or route through custom models.
- No Settings, installer, EnhancedModelManager, manifest, package, resource,
  script, candidate, analytics, transcript persistence, audio persistence, or
  cloud file is in this workstream.
- Do not add `DictationAudioReplayBuffer.swift` from the historical branch:
  `AppleSpeechCapture` already owns live audio ingress, and a second buffer
  would create a second capture responsibility.
- No push, PR, merge, GitHub mutation, model download, model-weight write,
  candidate selection, release admission, or signed-app claim is authorized.
- Automated checks are serialized and offline-safe:
  `swift test --disable-automatic-resolution --no-parallel [--filter ...]`.
- Preserve the known unrelated `AppStateTests.swift` viewport assertion around
  line 916 (`18.0 >= 48.0`) if inherited; report it separately and do not
  weaken or conceal it.

## File map

### Create

- `Sources/FleckApp/DictationProcessingModels.swift` — processing values,
  updates, results, runtime signals, and deadlines.
- `Sources/FleckApp/StreamingTranscriptState.swift` — generation ordering,
  append-only stable prefix, and bounded mutable tail.
- `Sources/FleckApp/DictationRuntimePolicy.swift` — residency and transition
  policy.
- `Sources/FleckApp/DictationInferenceScheduler.swift` — live/final priority.
- `Sources/FleckApp/LocalDictationRuntime.swift` — fake-backed leases,
  lifecycle signals, health, and model-mutation gate.
- `Sources/FleckApp/AppleSpeechStreamingAdapter.swift` — adapter over an
  injected existing `SpeechEngine`.
- `Sources/FleckApp/FoundationModelCleanupGenerator.swift` — bounded wrapper
  over existing Apple/deterministic cleanup.
- `Sources/FleckApp/StreamingDictationProcessor.swift` — one live session,
  state updates, dictionary resolution, cleanup decision, and final artifact.
- `Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift` — thin
  adapter over the Task 0 resolution core; the milestone injects empty entries.
- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`
- `Tests/FleckAppTests/StreamingTranscriptStateTests.swift`
- `Tests/FleckAppTests/DictationRuntimePolicyTests.swift`
- `Tests/FleckAppTests/DictationInferenceSchedulerTests.swift`
- `Tests/FleckAppTests/LocalDictationRuntimeTests.swift`
- `Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift`
- `Tests/FleckAppTests/FoundationModelCleanupGeneratorTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/PersonalDictionaryTranscriptResolverTests.swift`

### Modify

- `Sources/FleckApp/DictationInterfaces.swift` — add processing and dictionary
  resolver seams only.
- `Sources/FleckApp/DictationCoordinator.swift` — select one path and enforce
  generation/cancellation guards.
- `Sources/FleckApp/FleckApp.swift` — construct the processor from the existing
  provider and an explicitly empty dictionary-entry provider.
- `Tests/FleckAppTests/DictationCoordinatorTests.swift` — both-path,
  provisional, result, and cancellation integration tests.

### Explicitly excluded

`Sources/FleckApp/AppleSpeechCapture.swift`, all AVFAudio/Speech implementation,
`EnhancedModelManager.swift`, `EnhancedSpeechCapture.swift`,
`DictationModelCapability.swift`, `SettingsView.swift`,
`DictationSettingsPresentation.swift`, `Package.swift`,
`Package.resolved`, resources, scripts, model manifests, candidate adapters,
weights, installers, and all files outside the map.

## Interfaces produced

The coordinator-facing seam is:

~~~swift
@MainActor
protocol DictationProcessing: AnyObject {
  func prepare(for intent: DictationPreparationIntent) async
  func begin(
    configuration: DictationProcessingConfiguration
  ) async throws -> any DictationProcessingSession
  func handle(_ signal: DictationRuntimeSignal) async
}

@MainActor
protocol DictationProcessingSession: AnyObject {
  var updates: AsyncThrowingStream<DictationTextUpdate, Error> { get }
  func finish() async throws -> DictationProcessingResult
  func cancel() async
}

protocol TranscriptDictionaryResolving: Sendable {
  func resolve(_ rawTranscript: String) async throws
    -> PersonalDictionaryResolution
}
~~~

The source seam matches the current speech abstraction and has no audio-chunk
API:

~~~swift
@MainActor
protocol StreamingSpeechSource: AnyObject {
  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  func releaseResources() async
}
~~~

## Task 1: Define processing contracts and final artifacts

**Separate user-visible task title:** `Agent - processing contracts`

**Dependency:** Begin only after Workstream A Task 2's fresh Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/DictationProcessingModels.swift` and
`Tests/FleckAppTests/DictationProcessingModelsTests.swift`; modify only
`Sources/FleckApp/DictationInterfaces.swift`.

**Excluded files:** Every other Workstream B path, especially
`AppleSpeechCapture.swift`, `DictationCoordinator.swift`,
`StreamingDictationProcessor.swift`, and all runtime/UI/model files.

**Consumes:** Existing `DictationMode`, `DictationCleanupOutcome`,
`PersonalDictionaryResolution`, `SpeechEngine`, and destination types.

**Produces:** `DictationPreparationIntent`, `DictationRuntimeSignal`,
`DictationRecognitionContext`, `DictationProcessingConfiguration`,
`DictationTextUpdate`, `DictationRuntimeMeasurements`,
`DictationProcessingResult`, `DictationDeadline`,
`DictationProcessing`, `DictationProcessingSession`, and
`TranscriptDictionaryResolving`.

### TDD red

- [ ] **Step 1: Write contract tests.**

~~~swift
@Test func updateDisplayIsStablePrefixPlusTail() {
  #expect(DictationTextUpdate(
    generation: 4,
    stableText: "First. ",
    provisionalTail: "Second"
  ).displayText == "First. Second")
}

@Test func resultKeepsBaselineSeparateFromRawRecovery() {
  let result = DictationProcessingResult(
    rawTranscript: "send the report",
    dictionaryBaseline: nil,
    cleanedTranscript: nil,
    insertedText: "send the report",
    cleanupOutcome: .usedRaw,
    measurements: .empty
  )
  #expect(result.dictionaryBaseline == nil)
  #expect(result.insertedText == result.rawTranscript)
}
~~~

- [ ] **Step 2: Run the red command.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter DictationProcessingModelsTests
~~~

Expected failure: the test target cannot compile because the processing values
and protocols do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Add the exact values.**

~~~swift
struct DictationTextUpdate: Equatable, Sendable {
  let generation: UInt64
  let stableText: String
  let provisionalTail: String
  var displayText: String { stableText + provisionalTail }
}

struct DictationProcessingConfiguration: Equatable, Sendable {
  let captureID: UUID
  let mode: DictationMode
  let recognitionContext: DictationRecognitionContext
}

struct DictationProcessingResult: Equatable, Sendable {
  let rawTranscript: String
  let dictionaryBaseline: String?
  let cleanedTranscript: String?
  let insertedText: String
  let cleanupOutcome: DictationCleanupOutcome
  let measurements: DictationRuntimeMeasurements
}

struct DictationDeadline: Sendable {
  let stopInstant: ContinuousClock.Instant
  let insertionDeadline: ContinuousClock.Instant

  init(stopInstant: ContinuousClock.Instant, budget: Duration) {
    self.stopInstant = stopInstant
    self.insertionDeadline = stopInstant.advanced(by: budget)
  }
}
~~~

Add the remaining enums/measurement/context values and the three protocols
from the interface section. Preserve current interfaces; do not add audio
chunks or a second source abstraction.

- [ ] **Step 4: Run green and broader checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter DictationProcessingModelsTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
~~~

Expected: both pass; the optional processing dependency has not changed the
legacy coordinator behavior.

- [ ] **Step 5: Inspect and commit.**

~~~bash
git diff --check
git diff -- Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/DictationProcessingModels.swift Tests/FleckAppTests/DictationProcessingModelsTests.swift
git add Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/DictationProcessingModels.swift Tests/FleckAppTests/DictationProcessingModelsTests.swift
git commit -m "feat: define streaming dictation contracts"
~~~

The parent reruns the focused and legacy checks and obtains a fresh Sol ship
verdict before Workstream B Task 2.

## Task 2: Enforce append-only stable text and a bounded mutable tail

**Separate user-visible task title:** `Agent - transcript stable state`

**Dependency:** Begin only after Workstream B Task 1's parent rerun and fresh
Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/StreamingTranscriptState.swift` and
`Tests/FleckAppTests/StreamingTranscriptStateTests.swift`.

**Excluded files:** All other Workstream B files, especially coordinator,
processor, Apple capture, runtime, model, and UI files.

**Consumes:** `DictationTextUpdate` and full provisional strings from
`StreamingSpeechSource`.

**Produces:** `StreamingTranscriptStateError` and
`StreamingTranscriptState.accept(generation:fullText:)`.

### TDD red

- [ ] **Step 1: Write boundary tests.**

~~~swift
@Test func stablePrefixOnlyGrows() throws {
  var state = StreamingTranscriptState()
  _ = try state.accept(generation: 1, fullText: "First. Second")
  let update = try state.accept(
    generation: 2,
    fullText: "First. Second. Third"
  )
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second. Third")
}

@Test func staleGenerationAndStableRegressionAreRejected() throws {
  var state = StreamingTranscriptState()
  _ = try state.accept(generation: 2, fullText: "Alpha. Beta")
  #expect(throws: StreamingTranscriptStateError.staleGeneration) {
    try state.accept(generation: 2, fullText: "Alpha. Gamma")
  }
  #expect(throws: StreamingTranscriptStateError.stablePrefixChanged) {
    try state.accept(generation: 3, fullText: "Changed. Beta")
  }
}

@Test func mutableTailNeverExceedsEightyWords() throws {
  var state = StreamingTranscriptState()
  let words = (0..<90).map { "word\($0)" }.joined(separator: " ")
  let update = try state.accept(generation: 1, fullText: words)
  #expect(update.provisionalTail.split(whereSeparator: \.isWhitespace).count <= 80)
}
~~~

- [ ] **Step 2: Run the red command.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter StreamingTranscriptStateTests
~~~

Expected failure: the state/error types and `accept` method do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Implement the state machine.**

~~~swift
enum StreamingTranscriptStateError: Error, Equatable {
  case staleGeneration
  case stablePrefixChanged
  case mutableTailTooLarge
}

struct StreamingTranscriptState {
  private(set) var update = DictationTextUpdate(
    generation: 0, stableText: "", provisionalTail: ""
  )
  let maximumMutableWords = 80
  let maximumMutableClauses = 2

  mutating func accept(
    generation: UInt64,
    fullText: String
  ) throws -> DictationTextUpdate {
    guard generation > update.generation else {
      throw StreamingTranscriptStateError.staleGeneration
    }
    let split = Self.splitStablePrefix(
      fullText,
      maximumMutableWords: maximumMutableWords,
      maximumMutableClauses: maximumMutableClauses
    )
    guard split.stable.hasPrefix(update.stableText) else {
      throw StreamingTranscriptStateError.stablePrefixChanged
    }
    guard split.tail.split(whereSeparator: \.isWhitespace).count
      <= maximumMutableWords else {
      throw StreamingTranscriptStateError.mutableTailTooLarge
    }
    update = DictationTextUpdate(
      generation: generation,
      stableText: split.stable,
      provisionalTail: split.tail
    )
    return update
  }
}
~~~

Implement `splitStablePrefix` using sentence terminators `.?!。？！` followed
by whitespace: retain only the newest two clauses as mutable, then move older
words into the stable prefix until the tail is at most 80 words. Never mutate
the previously accepted stable prefix. Test English and mixed punctuation.

- [ ] **Step 4: Run green, inspect, and commit.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter StreamingTranscriptStateTests
git diff --check
git add Sources/FleckApp/StreamingTranscriptState.swift Tests/FleckAppTests/StreamingTranscriptStateTests.swift
git commit -m "feat: bound streaming transcript mutability"
~~~

The parent reruns Workstream B Tasks 1 and 2 checks and obtains a fresh Sol ship
verdict before Workstream B Task 3.

## Task 3: Reconcile the fake-backed runtime foundation

**Separate user-visible task title:** `Agent - runtime foundation`

**Dependency:** Begin only after Workstream B Task 2's parent rerun and fresh
Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/DictationRuntimePolicy.swift`,
`Sources/FleckApp/DictationInferenceScheduler.swift`,
`Sources/FleckApp/LocalDictationRuntime.swift`, and their three matching test
files.

**Excluded files:** Every other Workstream B path, especially all audio, processor,
coordinator, app, Settings, model-manager, and resource files.

**Consumes:** `DictationPreparationIntent` and `DictationRuntimeSignal`.

**Produces:** `DictationRuntimePolicy`, `DictationInferenceScheduler`,
`LocalDictationRuntimeAdapter`, `LocalDictationRuntime`,
`LocalDictationRuntimeSnapshot`, and `LocalDictationRuntimeError`.

### TDD red

- [ ] **Step 1: Write policy, priority, and lease tests.**

~~~swift
@Test func policyReachesColdAfterCriticalMemory() {
  let policy = DictationRuntimePolicy.policy(
    memoryBytes: 16 * 1_024 * 1_024 * 1_024
  )
  #expect(policy.targetState(
    after: .memoryCritical,
    activeLease: false
  ) == .cold)
}

@Test func liveASRPreemptsCleanupButCleanupCannotPreemptLiveASR() {
  let scheduler = DictationInferenceScheduler()
  #expect(scheduler.canStart(.liveASR, while: .cleanup))
  #expect(!scheduler.canStart(.cleanup, while: .liveASR))
}

@Test func cancellationReleasesOneCaptureLease() async throws {
  let runtime = LocalDictationRuntime(
    asrAdapter: RuntimeAdapterProbe(role: .asr),
    cleanupAdapter: RuntimeAdapterProbe(role: .cleanup),
    policy: .policy(memoryBytes: 16 * 1_024 * 1_024 * 1_024),
    sleeper: { _ in }
  )
  let lease = try await runtime.acquireCaptureLease()
  await runtime.cancelCaptureLease(lease)
  #expect((await runtime.snapshot()).hasActiveLease == false)
}
~~~

- [ ] **Step 2: Run the three red commands.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter DictationRuntimePolicyTests
swift test --disable-automatic-resolution --no-parallel --filter DictationInferenceSchedulerTests
swift test --disable-automatic-resolution --no-parallel --filter LocalDictationRuntimeTests
~~~

Expected failure: the policy, scheduler, adapter, runtime, snapshot, and error
symbols do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Port the deterministic lifecycle names and signatures.**

~~~swift
enum DictationRuntimeResidency: Equatable, Sendable {
  case active, warm, standby, cold
}

struct DictationRuntimePolicy: Equatable, Sendable {
  let warmDuration: Duration
  let standbyDuration: Duration
  static func policy(memoryBytes: UInt64) -> Self
  func targetState(
    after signal: DictationRuntimeSignal,
    activeLease: Bool
  ) -> DictationRuntimeResidency
}

enum DictationInferencePriority: Int, Comparable, Sendable {
  case optionalPolish = 0, cleanup = 1, finalASR = 2, liveASR = 3
}

struct DictationInferenceScheduler: Sendable {
  func canStart(
    _ requested: DictationInferencePriority,
    while running: DictationInferencePriority?
  ) -> Bool
}

protocol LocalDictationRuntimeAdapter: AnyObject, Sendable {
  var role: LocalDictationRuntimeRole { get }
  func load() async throws
  func cancel() async
  func unload() async
}

actor LocalDictationRuntime {
  init(
    asrAdapter: any LocalDictationRuntimeAdapter,
    cleanupAdapter: any LocalDictationRuntimeAdapter,
    policy: DictationRuntimePolicy,
    scheduler: DictationInferenceScheduler = .init(),
    sleeper: @escaping @Sendable (Duration) async -> Void
  )
  func prepare(for intent: DictationPreparationIntent) async
  func acquireCaptureLease() async throws -> UUID
  func releaseCaptureLease(_ id: UUID) async
  func cancelCaptureLease(_ id: UUID) async
  func handle(_ signal: DictationRuntimeSignal) async
  func waitUntilColdForModelMutation() async
  func snapshot() async -> LocalDictationRuntimeSnapshot
}
~~~

Port the restored lifecycle ordering: preparation is advisory; acquisition is
authoritative; only one lease is active; cancellation calls ASR then cleanup
once; active capture defers memory/thermal/sleep transitions; mutation waits
for cold; transition tasks use a generation check; and repeated adapter load
failure marks that role unavailable for the app session. Use injected sleepers,
not wall-clock waits. No runtime type touches audio or files.

- [ ] **Step 4: Run green and broader checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter DictationRuntimePolicyTests
swift test --disable-automatic-resolution --no-parallel --filter DictationInferenceSchedulerTests
swift test --disable-automatic-resolution --no-parallel --filter LocalDictationRuntimeTests
swift test --disable-automatic-resolution --no-parallel --filter DictationProcessingModelsTests
~~~

Expected: all pass without loading a model or creating audio.

- [ ] **Step 5: Inspect and commit.**

~~~bash
git diff --check
rg -n 'URLSession|AVAudioEngine|SFSpeech|SpeechAnalyzer|FileHandle|Data\.write' Sources/FleckApp/DictationRuntimePolicy.swift Sources/FleckApp/DictationInferenceScheduler.swift Sources/FleckApp/LocalDictationRuntime.swift
git add Sources/FleckApp/DictationRuntimePolicy.swift Sources/FleckApp/DictationInferenceScheduler.swift Sources/FleckApp/LocalDictationRuntime.swift Tests/FleckAppTests/DictationRuntimePolicyTests.swift Tests/FleckAppTests/DictationInferenceSchedulerTests.swift Tests/FleckAppTests/LocalDictationRuntimeTests.swift
git commit -m "feat: restore local dictation runtime policy"
~~~

Expected scan: no capture, download, or file-write match. Parent rerun and
fresh Sol ship are required before Workstream B Task 4.

## Task 4: Adapt Apple Speech and compose the processor

**Separate user-visible task title:** `Agent - Apple Speech processor`

**Dependency:** Begin only after Workstream B Task 3's parent rerun and fresh
Sol `ship` gate. This remains a separate task from the runtime foundation.

**Owned files:** Create
`Sources/FleckApp/AppleSpeechStreamingAdapter.swift`,
`Sources/FleckApp/FoundationModelCleanupGenerator.swift`,
`Sources/FleckApp/StreamingDictationProcessor.swift`, and the three matching
test files.

**Excluded files:** Every other Workstream B path, especially
`AppleSpeechCapture.swift`, `DictationCoordinator.swift`, `FleckApp.swift`,
`EnhancedModelManager.swift`, Settings, manifests, and all model files.

**Consumes:** `SpeechEngine`, Workstream B Tasks 1–3, and Workstream A Task 2's
`IncrementalTranscriptCleaner`.

**Produces:** `AppleSpeechStreamingAdapter`,
`FoundationModelCleanupGenerator`, `StreamingDictationProcessor`,
`StreamingDictationSession`, and `StreamingDictationProcessorError`.

### TDD red

- [ ] **Step 1: Write forwarding and safety tests.**

~~~swift
@Test @MainActor
func adapterForwardsSpeechCallbacksWithoutCreatingAudio() async throws {
  let engine = SpeechEngineProbe()
  let adapter = AppleSpeechStreamingAdapter(engine: engine)
  var provisional = [String]()
  try await adapter.start(
    provisional: { provisional.append($0) },
    level: { _ in }
  )
  engine.emitProvisional("First")
  engine.finalText = "First."
  #expect(try await adapter.finish() == "First.")
  #expect(provisional == ["First"])
  #expect(engine.createdAudioSources == 0)
}

@Test @MainActor
func processorUsesExactBaselineWhenCleanupIsRejected() async throws {
  let engine = SpeechEngineProbe(finalText: "Do not cancel 2 meetings")
  let cleaner = IncrementalTranscriptCleaner(
    generator: CleanupGeneratorProbe(result: "Cancel the meetings"),
    clock: .immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { AppleSpeechStreamingAdapter(engine: engine) },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "Do not cancel 2 meetings",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))
  let result = try await session.finish()
  #expect(result.insertedText == "Do not cancel 2 meetings")
  #expect(result.cleanedTranscript == nil)
}
~~~

- [ ] **Step 2: Run the three red commands.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AppleSpeechStreamingAdapterTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelCleanupGeneratorTests
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
~~~

Expected failure: adapter, generator, processor, session, and processor error
symbols do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Add the sole source adapter.**

~~~swift
@MainActor
final class AppleSpeechStreamingAdapter: StreamingSpeechSource {
  private let engine: any SpeechEngine

  init(engine: any SpeechEngine) {
    self.engine = engine
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    try await engine.start(provisional: provisional, level: level)
  }

  func finish() async throws -> String? { try await engine.finish() }
  func cancel() async { await engine.cancel() }
  func releaseResources() async { await engine.releaseResources() }
}
~~~

The factory receives the existing engine from
`DictationSpeechEngineProvider.engineForCapture(preferred:)`. It does not
construct `AppleSpeechCapture` and does not expose audio chunks.

- [ ] **Step 4: Add the bounded cleanup generator.**

~~~swift
struct FoundationModelCleanupGenerator: BoundedCleanupGenerating {
  private let generate: @Sendable (String) async throws -> String

  init(dictation: FoundationModelDictation) {
    generate = { raw in await dictation.cleanupResult(raw).text }
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    FoundationModelCleanupSession(
      task: Task { try await generate(request.baseline) }
    )
  }
}
~~~

The injected production closure calls existing Apple Foundation Models where
supported and deterministic local cleanup otherwise. The Workstream A Task 1
validator remains final authority. Test closures are fake and local.

- [ ] **Step 5: Add the processor/session.**

~~~swift
@MainActor
final class StreamingDictationProcessor: DictationProcessing {
  typealias SourceFactory =
    @MainActor () async throws -> any StreamingSpeechSource

  init(
    makeSource: @escaping SourceFactory,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?
  )

  func prepare(for intent: DictationPreparationIntent) async
  func handle(_ signal: DictationRuntimeSignal) async
  func begin(
    configuration: DictationProcessingConfiguration
  ) async throws -> any DictationProcessingSession
}
~~~

`StreamingDictationSession` owns one source, state, generation counter, stream,
and finalization flag. Each provisional callback increments generation and
publishes only an accepted `StreamingTranscriptState` update. Its `finish`
calls source `finish` exactly once, rejects empty final text, resolves the
dictionary, and sends only the baseline to
`IncrementalTranscriptCleaner`. A cleaned candidate publishes
`cleanedTranscript`; every unsafe/unavailable cleanup publishes
`insertedText` equal to the exact baseline. A resolver failure publishes raw
ASR recovery with no cleaner call. `cancel` invalidates first, closes the
stream, cancels the source, and releases resources once. A state or source
error closes without a late result.

- [ ] **Step 6: Run green and broader checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AppleSpeechStreamingAdapterTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelCleanupGeneratorTests
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
~~~

Expected: all pass; existing availability tests still prove on-device
rejection, and adapter tests prove no second audio source.

- [ ] **Step 7: Inspect and commit.**

~~~bash
git diff --check
rg -n 'AVAudioEngine|installTap|SFSpeechRecognizer|SpeechAnalyzer|URLSession|FileHandle|Data\.write' Sources/FleckApp/AppleSpeechStreamingAdapter.swift Sources/FleckApp/FoundationModelCleanupGenerator.swift Sources/FleckApp/StreamingDictationProcessor.swift
git add Sources/FleckApp/AppleSpeechStreamingAdapter.swift Sources/FleckApp/FoundationModelCleanupGenerator.swift Sources/FleckApp/StreamingDictationProcessor.swift Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift Tests/FleckAppTests/FoundationModelCleanupGeneratorTests.swift Tests/FleckAppTests/StreamingDictationProcessorTests.swift
git commit -m "feat: compose Apple streaming dictation"
~~~

Expected scan: no capture, network, file-write, or model implementation
match. Parent rerun and fresh Sol ship are required before Workstream B Task 5.

## Task 5: Integrate one processing path with coordinator and app runtime

**Separate user-visible task title:** `Agent - coordinator app integration`

**Dependency:** Begin only after Workstream B Task 4's parent rerun and fresh
Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift` and its test;
modify `Sources/FleckApp/DictationCoordinator.swift`,
`Sources/FleckApp/FleckApp.swift`, and
`Tests/FleckAppTests/DictationCoordinatorTests.swift`.

**Excluded files:** Every other Workstream B path, especially
`AppleSpeechCapture.swift`, Settings, EnhancedModelManager, manifests,
resources, scripts, and all candidate/model files.

**Consumes:** `DictationProcessing`,
`DictationProcessingSession`, `DictationProcessingResult`,
`AppleSpeechStreamingAdapter`, `FoundationModelCleanupGenerator`,
`PersonalDictionaryTranscriptResolver` with its explicitly empty entry
provider, and current editor/saver/history protocols.

**Produces:** an optional coordinator `processing` dependency and real-app
construction through the existing engine provider.

### TDD red

- [ ] **Step 1: Add processor-path and legacy-path tests.**

~~~swift
@Test @MainActor
func processingPathPublishesProvisionalAndCommitsFinalResult() async throws {
  let processing = ProcessingProbe(
    updates: [
      .init(generation: 1, stableText: "", provisionalTail: "send the report"),
      .init(
        generation: 2,
        stableText: "Send the report. ",
        provisionalTail: "today"
      )
    ],
    result: .init(
      rawTranscript: "send the report today",
      dictionaryBaseline: "Send the report today",
      cleanedTranscript: "Send the report today.",
      insertedText: "Send the report today.",
      cleanupOutcome: .cleaned,
      measurements: .empty
    )
  )
  let fixture = try Fixture(processing: processing)
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await processing.emitAll()
  await fixture.coordinator.finish()
  #expect(fixture.editor.provisionalTexts == [
    "send the report", "Send the report. today"
  ])
  #expect(fixture.editor.committedTexts == ["Send the report today."])
}

@Test @MainActor
func cancellationRejectsLateProcessingUpdateAndResult() async throws {
  let processing = ProcessingProbe()
  let fixture = try Fixture(processing: processing)
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)
  await fixture.coordinator.cancel()
  await processing.emit(.init(
    generation: 99, stableText: "", provisionalTail: "late"
  ))
  processing.complete(with: .init(
    rawTranscript: "late",
    dictionaryBaseline: "late",
    cleanedTranscript: "late.",
    insertedText: "late.",
    cleanupOutcome: .cleaned,
    measurements: .empty
  ))
  #expect(fixture.editor.committedTexts.isEmpty)
  #expect(fixture.saver.savedTexts.isEmpty)
}

@Test @MainActor
func absentProcessorPreservesLegacyCleanerPath() async throws {
  let fixture = try Fixture(processing: nil)
  fixture.standard.finalText = "Buy tea"
  fixture.cleaner.result = "Buy tea."
  await fixture.coordinator.start(mode: .smartCapture)
  await fixture.coordinator.finish()
  #expect(fixture.cleaner.calls == 1)
  #expect(fixture.saver.savedTexts == ["Buy tea."])
}
~~~

- [ ] **Step 2: Run the red command.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
~~~

Expected failure: the fixture cannot supply a processing session because the
coordinator has no processing dependency or processing branch.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Add the dictionary adapter.**

~~~swift
struct PersonalDictionaryTranscriptResolver: TranscriptDictionaryResolving {
  private let entries: @Sendable () async -> [PersonalDictionaryEntry]
  private let resolveEntries:
    @Sendable (String, [PersonalDictionaryEntry]) throws
      -> PersonalDictionaryResolution

  init(
    entries: @escaping @Sendable () async -> [PersonalDictionaryEntry],
    resolveEntries: @escaping @Sendable (String, [PersonalDictionaryEntry])
      throws -> PersonalDictionaryResolution =
      { raw, entries in try PersonalDictionaryResolver.resolve(
        raw, entries: entries
      ) }
  ) {
    self.entries = entries
    self.resolveEntries = resolveEntries
  }

  func resolve(_ rawTranscript: String) async throws
    -> PersonalDictionaryResolution {
    try resolveEntries(rawTranscript, await entries())
  }
}
~~~

It owns no dictionary entries and adds no resolution policy. Its tests cover
unchanged baseline, exact preferred form, and resolver failure.

- [ ] **Step 4: Add one coordinator capture branch.**

~~~swift
init(
  engineProvider: any SpeechEngineProviding,
  preferredEngine: @escaping @MainActor () -> DictationSpeechEngine,
  cleaner: any TranscriptCleaning,
  router: any DestinationRouting,
  saver: any DictationSaving,
  historyController: DictationHistoryController,
  historyEnabled: @escaping @MainActor () -> Bool,
  processing: (any DictationProcessing)? = nil
)
~~~

At capture start, choose the processor only when the injected processor is
available and the selected standard mode requests the incremental path;
otherwise use the existing engine branch. Store the selected session before
publishing listening. The processor update task checks capture UUID,
cancel-requested state, termination state, strictly increasing generation, and
stable-prefix continuity before each editor update. It updates only focused
provisional text.

On finish, cancel and await the update task, await one processor result, repeat
all guards, create/update the existing history record, and pass only
`result.insertedText` to focused commit or existing Smart Capture routing. Do
not call legacy `cleaner.clean` on this branch. At cancellation start, mark
the capture cancelled and invalidate its generation before calling session
`cancel`; then await cancellation, release existing editor state, and publish
nothing from a late task.

- [ ] **Step 5: Wire the real app without a second capture.** In
`FleckApp.swift`, construct the existing Foundation/deterministic cleanup
object, Workstream A Task 2's `IncrementalTranscriptCleaner`, and
`StreamingDictationProcessor`. Its source factory awaits
`DictationSpeechEngineProvider.engineForCapture(preferred: .standard)` and
wraps that returned engine in `AppleSpeechStreamingAdapter`. Pass Task 0's
resolution core through
`PersonalDictionaryTranscriptResolver(entries: { [] })` and pass that resolver
and processor into the coordinator. This is an explicit empty provider for the
milestone; it does not claim a dictionary store or persistence.

Reuse the provider's existing permission, locale, and microphone-selection
closures. Do not instantiate `AppleSpeechCapture` anywhere new.

This milestone deliberately adds no `PersonalDictionaryStore`, dictionary
codec, or persistent dictionary UI. A later bounded task may add persistence
and its presentation without changing this resolver/order seam.

- [ ] **Step 6: Run green and broader integration checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter PersonalDictionaryTranscriptResolverTests
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAccessibilityTests
~~~

Expected: all pass; coordinator tests prove both paths, late-event rejection,
exact baseline/raw recovery, provisional display, and legacy cleaner isolation.

- [ ] **Step 7: Inspect and commit.**

~~~bash
git diff --check
rg -n 'processingSession|processingUpdatesTask|cancelRequested|isTerminating' Sources/FleckApp/DictationCoordinator.swift
test "$(rg -n 'AppleSpeechCapture\(' Sources/FleckApp/FleckApp.swift | wc -l | tr -d ' ')" -eq 1
git add Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift Sources/FleckApp/DictationCoordinator.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/DictationCoordinatorTests.swift Tests/FleckAppTests/PersonalDictionaryTranscriptResolverTests.swift
git commit -m "feat: integrate streaming dictation with coordinator"
~~~

The parent inspects the complete Workstream B diff, verifies
`AppleSpeechCapture.swift` is unchanged, and obtains a fresh Sol ship verdict
before Workstream C Task 1 starts.

## Parent verification and review handoff

Run, serialized, on the actual dependent worktree:

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter DictationProcessingModelsTests
swift test --disable-automatic-resolution --no-parallel --filter StreamingTranscriptStateTests
swift test --disable-automatic-resolution --no-parallel --filter DictationRuntimePolicyTests
swift test --disable-automatic-resolution --no-parallel --filter DictationInferenceSchedulerTests
swift test --disable-automatic-resolution --no-parallel --filter LocalDictationRuntimeTests
swift test --disable-automatic-resolution --no-parallel --filter AppleSpeechStreamingAdapterTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelCleanupGeneratorTests
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
swift test --disable-automatic-resolution --no-parallel --filter PersonalDictionaryTranscriptResolverTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
swift test --disable-automatic-resolution --no-parallel
git diff --check
~~~

Inspect exact ownership, unchanged Apple capture implementation, one source
release per capture, one legacy/incremental path per capture, dictionary-before-
cleanup ordering, no post-cancel publication, and the absence of network,
logging, persistence, and weights. Classify any inherited viewport failure with
its exact assertion.

## Final real-app verification checklist

After Workstream C completes its numbered tasks, the primary runs from the real checkout:

~~~bash
cd /Users/harryjin/Fleck
swift test --disable-automatic-resolution --no-parallel
./Scripts/build-fleck-app.sh
test -d /Users/harryjin/Fleck/.build/Fleck.app
open /Users/harryjin/Fleck/.build/Fleck.app
~~~

The operator grants Microphone and Speech Recognition permissions, focuses a
Fleck note, holds the existing dictation shortcut, and speaks a known sentence
containing a filler, immediate repetition, a name/number/path, and punctuation.
Record the observed provisional display, stable prefix, final insertion, and
protected-content result. Cancel a second capture and record that no text or
history entry appeared. Automated tests and a launched process do not constitute
speech output evidence; the primary may launch the app but must not fabricate
microphone words or cleanup results.

## Authority boundary

This workstream authorizes only its file map. Each numbered task has separate
ownership and a separate ship gate. It does not authorize Settings or
installer work, model downloads, candidate enablement, package changes, a
second Apple audio path, push, PR, merge, or release admission.
