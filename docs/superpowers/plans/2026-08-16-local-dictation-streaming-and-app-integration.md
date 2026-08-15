# Local Dictation Streaming and App Integration Implementation Plan

> **For agentic workers:** REQUIRED ROUTE: Workstream B is a dependency-ordered phase, not one task. Each numbered task below is its own separate user-visible Codex task running GPT-5.6 Luna/Max with a title of `Agent - <singular task>`. Before each task, the primary Sol session is GPT-5.6 Sol at High reasoning; it first runs the orchestration exactness check and confirms the exact native routing roles are available, then writes a bounded five-part packet: objective/success criteria; owned files, interfaces, and constraints; implementation and explicit non-goals; verification commands and expected evidence; and authority boundaries plus the handoff. The Luna/Max task adapts to concurrent edits and preserves unrelated work. The parent Sol task inspects the actual diff and reruns the required checks; a fresh `sol_advisor_sol_reviewer` must return exactly `ship` before the next dependent numbered task. Both `fix-first` and `rethink` return the corrected bounded packet to the same user-visible Luna/Max task; neither switches tasks or adds an implementation route. Terra/native subagents are forbidden. Steps use checkbox (`- [ ]`) syntax for tracking.

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
- `StreamingDictationSession` owns one finalization task and one shared
  `cancellationTask`. `finish()` installs finalization exactly once. The first
  `cancel()` creates the shared task, invalidates and closes updates, cancels the
  sole speech source early enough to unblock an in-flight `finish()`, cancels
  and awaits finalization, and releases source resources exactly once. Every
  concurrent or reentrant caller awaits that same cancellation task, so no
  caller returns before the cleaner's bounded helper acknowledgement or
  force-termination path and source release have completed.
- Coordinator cancellation marks the capture cancelled and invalidates its
  generation first, restores the focused editor transaction second, and only
  then awaits processing-session cancellation or legacy source cancellation and
  resource release. No late update, result, history mutation, route, or
  insertion may publish.
- Apple Speech requests require on-device recognition and fail when the locale
  or device cannot provide it. There is no network recognition or hidden
  fallback.
- Stable text is append-only. Only the newest two clauses or 80 `CleanupLexeme`
  lexical units
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
  // All callers await one source-unblocking/finalization/cleanup cancellation
  // task before resource release returns.
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
`DictationProcessingResult`, `DictationProcessingBudget`, `DictationClock`,
`DictationDeadline`,
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

struct DictationProcessingBudget: Equatable, Sendable {
  let insertion: Duration
  let cleanup: Duration

  static let production = Self(
    insertion: .seconds(3),
    cleanup: .milliseconds(1500)
  )
}

struct DictationClock: Sendable {
  let now: @Sendable () -> ContinuousClock.Instant

  static let live = Self(now: { ContinuousClock().now })
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
  let cleanupDeadline: ContinuousClock.Instant

  init(
    stopInstant: ContinuousClock.Instant,
    insertionDeadline: ContinuousClock.Instant,
    cleanupBudget: Duration
  ) {
    self.stopInstant = stopInstant
    self.insertionDeadline = insertionDeadline
    cleanupDeadline = min(
      stopInstant.advanced(by: cleanupBudget),
      insertionDeadline
    )
  }
}
~~~

Add the remaining enums/measurement/context values and the three protocols
from the interface section. The processor receives `DictationClock` and
`DictationProcessingBudget`; tests inject fixed instants and never read or
sleep a production wall clock. The session creates `stopInstant` and
`insertionDeadline = stopInstant + budget.insertion` together at finish, so
cleanup is bounded by `min(stopInstant + budget.cleanup, insertionDeadline)`.
Preserve current interfaces; do not add audio chunks or a second source
abstraction.

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
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/DictationProcessingModels.swift \
    Tests/FleckAppTests/DictationProcessingModelsTests.swift \
    Sources/FleckApp/DictationInterfaces.swift \
  | sort -u
)"
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

@Test func zeroTerminatorsKeepTheWholeTranscriptMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(generation: 1, fullText: "No terminator")
  #expect(update.stableText == "")
  #expect(update.provisionalTail == "No terminator")
}

@Test func oneTerminatorStabilizesThatClause() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(generation: 1, fullText: "First. Second")
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second")
}

@Test func twoTerminatorsKeepTheNewestTwoClausesMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "First. Second. Third"
  )
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second. Third")
}

@Test func threeTerminatorsKeepTheNewestTwoClausesMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "First. Second. Third. Fourth"
  )
  #expect(update.stableText == "First. Second. ")
  #expect(update.provisionalTail == "Third. Fourth")
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

@Test func mutableTailNeverExceedsEightyCleanupLexemes() throws {
  var state = StreamingTranscriptState()
  let lexicalUnits = String(repeating: "字，", count: 81) + "尾"
  let update = try state.accept(generation: 1, fullText: lexicalUnits)
  #expect(CleanupLexeme.tokenCount(update.provisionalTail) <= 80)
}

@Test func noSpaceMandarinKeepsOnlyNewestTwoClausesMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "第一句。第二句！第三句？第四句"
  )
  #expect(update.stableText == "第一句。第二句！")
  #expect(update.provisionalTail == "第三句？第四句")
}

@Test func whitespaceAfterTerminatorBelongsToStablePrefix() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(generation: 1, fullText: "First. Second")
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second")
}

@Test func mixedLanguageTerminatorsDoNotRequireWhitespace() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "你好。send report!下一句"
  )
  #expect(update.stableText == "你好。")
  #expect(update.provisionalTail == "send report!下一句")
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
  let maximumMutableLexicalUnits = 80
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
      maximumMutableLexicalUnits: maximumMutableLexicalUnits,
      maximumMutableClauses: maximumMutableClauses
    )
    guard split.stable.hasPrefix(update.stableText) else {
      throw StreamingTranscriptStateError.stablePrefixChanged
    }
    guard CleanupLexeme.tokenCount(split.tail)
      <= maximumMutableLexicalUnits else {
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

Implement `splitStablePrefix` from `CleanupLexeme.scan(fullText)`. Treat only
single-character punctuation lexemes in `.?!。！？` as clause terminators, so a
terminator is recognized without requiring following whitespace and periods
inside URL/path/code lexemes are not boundaries. Track each lexeme's character
span from `lexeme.original`; `lexeme.isLexical` is the only unit counted for
the 80-unit bound. If there are no terminators, set `clauseStart = 0`. If
there are terminators, select `boundaryIndex = max(0, terminatorEnds.count -
maximumMutableClauses)` and set `clauseStart = terminatorEnds[boundaryIndex]`:
one terminator selects its own end, two select the first end, and three select
the second end, leaving at most the newest two clauses mutable. Then advance
over immediately following whitespace lexemes so that whitespace after a
terminator belongs to stable text. Move the start forward to the first of the
newest 80 lexical spans when necessary. Never mutate the previously accepted
stable prefix.

~~~swift
private static let clauseTerminators: Set<Character> = [
  ".", "?", "!", "。", "！", "？"
]

private static func splitStablePrefix(
  _ fullText: String,
  maximumMutableLexicalUnits: Int,
  maximumMutableClauses: Int
) -> (stable: String, tail: String) {
  let lexemes = CleanupLexeme.scan(fullText)
  var offset = 0
  var terminatorEnds = [Int]()
  var lexicalSpans = [(start: Int, end: Int)]()

  for lexeme in lexemes {
    let start = offset
    offset += Array(lexeme.original).count
    if lexeme.kind == .punctuation,
       lexeme.original.count == 1,
       clauseTerminators.contains(Character(lexeme.original)) {
      terminatorEnds.append(offset)
    }
    if lexeme.isLexical {
      lexicalSpans.append((start: start, end: offset))
    }
  }

  var clauseStart = 0
  if !terminatorEnds.isEmpty {
    let boundaryIndex = max(
      0,
      terminatorEnds.count - maximumMutableClauses
    )
    clauseStart = terminatorEnds[boundaryIndex]
  }

  let characters = Array(fullText)
  let trailingLexemes = CleanupLexeme.scan(String(characters[clauseStart...]))
  for lexeme in trailingLexemes {
    guard lexeme.kind == .whitespace else { break }
    clauseStart += Array(lexeme.original).count
  }

  let mutableSpans = lexicalSpans.filter { $0.start >= clauseStart }
  let boundedStart = mutableSpans.count > maximumMutableLexicalUnits
    ? mutableSpans[mutableSpans.count - maximumMutableLexicalUnits].start
    : clauseStart
  return (
    String(characters[..<boundedStart]),
    String(characters[boundedStart...])
  )
}
~~~

- [ ] **Step 4: Run green, inspect, and commit.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter StreamingTranscriptStateTests
git diff --check
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/StreamingTranscriptState.swift \
    Tests/FleckAppTests/StreamingTranscriptStateTests.swift \
  | sort -u
)"
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
! rg -n 'URLSession|AVAudioEngine|SFSpeech|SpeechAnalyzer|FileHandle|Data\.write' Sources/FleckApp/DictationRuntimePolicy.swift Sources/FleckApp/DictationInferenceScheduler.swift Sources/FleckApp/LocalDictationRuntime.swift
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/DictationRuntimePolicy.swift \
    Sources/FleckApp/DictationInferenceScheduler.swift \
    Sources/FleckApp/LocalDictationRuntime.swift \
    Tests/FleckAppTests/DictationRuntimePolicyTests.swift \
    Tests/FleckAppTests/DictationInferenceSchedulerTests.swift \
    Tests/FleckAppTests/LocalDictationRuntimeTests.swift \
  | sort -u
)"
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

@MainActor
private func makeProcessor(
  source: any StreamingSpeechSource
) -> StreamingDictationProcessor {
  StreamingDictationProcessor(
    makeSource: { source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "First",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: IncrementalTranscriptCleaner(
      generator: CleanupGeneratorProbe(result: "First"),
      clock: TestCleanupClock.immediate
    ),
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )
}

enum StreamingSpeechSourceProbeError: Error {
  case failed
}

@MainActor
final class StreamingSpeechSourceProbe: StreamingSpeechSource {
  init(
    startError: StreamingSpeechSourceProbeError? = nil,
    finishBlocksUntilCancel: Bool = false,
    onCancel: (@MainActor @Sendable () async -> Void)? = nil,
    onRelease: (@MainActor @Sendable () async -> Void)? = nil
  )
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var finishStarted = false
  private(set) var finishUnblockedByCancel = false
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0
  private(set) var callbacksWereInstalled = false
  private(set) var provisionalCallbackCount = 0
  func emitProvisional(_ text: String)
  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  func releaseResources() async
  func waitUntilFinishStarted() async
}

@Test @MainActor
func beginStartsTheSoleSourceOnceBeforeReturningAndWiresCallbacks() async throws {
  let source = StreamingSpeechSourceProbe()
  let processor = makeProcessor(source: source)

  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))

  #expect(source.startCount == 1)
  #expect(source.callbacksWereInstalled)
  source.emitProvisional("First")
  #expect(source.provisionalCallbackCount == 1)
  await session.cancel()
  #expect(source.releaseCount == 1)
}

@Test @MainActor
func beginReleasesTheSourceWhenStartFails() async {
  let source = StreamingSpeechSourceProbe(startError: .failed)
  let processor = makeProcessor(source: source)

  await #expect(throws: StreamingSpeechSourceProbeError.failed) {
    _ = try await processor.begin(configuration: .init(
      captureID: UUID(),
      mode: .focused,
      recognitionContext: .englishDefault
    ))
  }
  #expect(source.startCount == 1)
  #expect(source.releaseCount == 1)
}

@Test @MainActor
func cancellingSessionAwaitsCleanupAcknowledgementBeforeSourceShutdown() async throws {
  let source = StreamingSpeechSourceProbe()
  let helper = CleanupGeneratorProbe(
    result: "Send the report.",
    waitsForCancellation: true
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: helper,
    clock: .bounded(milliseconds: 1),
    cancellationBudget: .milliseconds(25)
  )
  let processor = StreamingDictationProcessor(
    makeSource: { source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "Send the report",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))
  let updates = Task {
    try await session.updates.reduce(into: [DictationTextUpdate]()) {
      $0.append($1)
    }
  }
  let finalization = Task { try await session.finish() }
  await helper.waitUntilStarted()

  await session.cancel()

  #expect(await helper.acknowledgementFinished)
  await #expect(throws: CancellationError.self) { try await finalization.value }
  #expect(source.cancelCount == 1)
  #expect(source.releaseCount == 1)
  #expect(try await updates.value.isEmpty)
}

enum CancellationDrainEvent: Equatable {
  case sourceCancel
  case helperAcknowledged
  case sourceRelease
  case firstCallerReturned
  case secondCallerReturned
}

@MainActor
final class CancellationDrainRecorder {
  private(set) var events: [CancellationDrainEvent] = []
  func append(_ event: CancellationDrainEvent) { events.append(event) }
  func waitUntil(_ event: CancellationDrainEvent) async {
    while !events.contains(event) { await Task.yield() }
  }
}

@Test @MainActor
func concurrentCancelCallersShareOneTaskAndAwaitOrderedCleanupDrain() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    onCancel: { await order.append(.sourceCancel) },
    onRelease: { await order.append(.sourceRelease) }
  )
  let helper = CleanupGeneratorProbe(
    result: "Send the report.",
    waitsForCancellation: true,
    onAcknowledgementFinished: {
      await order.append(.helperAcknowledged)
    }
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: helper,
    clock: .bounded(milliseconds: 1),
    cancellationBudget: .milliseconds(25)
  )
  let processor = StreamingDictationProcessor(
    makeSource: { source },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "Send the report",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))
  let updates = Task {
    try await session.updates.reduce(into: [DictationTextUpdate]()) {
      $0.append($1)
    }
  }
  let finalization = Task { try await session.finish() }
  await helper.waitUntilStarted()

  let first = Task {
    await session.cancel()
    await order.append(.firstCallerReturned)
  }
  await order.waitUntil(.sourceCancel)
  let second = Task {
    await session.cancel()
    await order.append(.secondCallerReturned)
  }
  await first.value
  await second.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(source.cancelCount == 1)
  #expect(source.releaseCount == 1)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let helperIndex = try #require(events.firstIndex(of: .helperAcknowledged))
  let releaseIndex = try #require(events.firstIndex(of: .sourceRelease))
  let firstReturnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  let secondReturnIndex = try #require(events.firstIndex(of: .secondCallerReturned))
  #expect((events.firstIndex(of: .sourceCancel) ?? Int.max) < helperIndex)
  #expect(helperIndex < releaseIndex)
  #expect(releaseIndex < firstReturnIndex)
  #expect(releaseIndex < secondReturnIndex)
}

@Test @MainActor
func cancellingSessionUnblocksInFlightSourceFinishBeforeReleasingResources() async throws {
  let source = StreamingSpeechSourceProbe(finishBlocksUntilCancel: true)
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))
  let updates = Task {
    try await session.updates.reduce(into: [DictationTextUpdate]()) {
      $0.append($1)
    }
  }
  let firstFinish = Task { try await session.finish() }
  await source.waitUntilFinishStarted()
  let secondFinish = Task { try await session.finish() }
  await Task.yield()

  await session.cancel()

  await #expect(throws: CancellationError.self) { try await firstFinish.value }
  await #expect(throws: CancellationError.self) { try await secondFinish.value }
  #expect(source.finishCount == 1)
  #expect(source.finishUnblockedByCancel)
  #expect(source.cancelCount == 1)
  #expect(source.releaseCount == 1)
  #expect(try await updates.value.isEmpty)
}

@Test @MainActor
func cancellingBeforeFinishCannotStartFinalizationWork() async throws {
  let source = StreamingSpeechSourceProbe()
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))

  await session.cancel()

  await #expect(throws: CancellationError.self) { try await session.finish() }
  #expect(source.finishCount == 0)
  #expect(source.cancelCount == 1)
  #expect(source.releaseCount == 1)
}

@Test @MainActor
func processorUsesExactBaselineWhenCleanupIsRejected() async throws {
  let engine = SpeechEngineProbe(finalText: "Do not cancel 2 meetings")
  let cleaner = IncrementalTranscriptCleaner(
    generator: CleanupGeneratorProbe(result: "Cancel the meetings"),
    clock: TestCleanupClock.immediate
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
    runtime: nil,
    clock: TestDictationClock.immediate,
    budget: .production
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

@Test @MainActor
func processorPassesMinCleanupAndInsertionDeadlineWithoutWallClock() async throws {
  let start = TestDictationClock.fixedInstant
  let stop = start.advanced(by: .seconds(2))
  let clock = TestDictationClock(values: [stop])
  let engine = SpeechEngineProbe(finalText: "send the report")
  let generator = CleanupGeneratorProbe(result: "send the report")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { AppleSpeechStreamingAdapter(engine: engine) },
    dictionaryResolver: DictionaryResolverProbe(
      resolution: .init(
        baseline: "send the report",
        protectedForms: [],
        replacements: 0
      )
    ),
    cleaner: cleaner,
    runtime: nil,
    clock: clock,
    budget: .production
  )

  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))
  _ = try await session.finish()

  #expect(await generator.requests.first?.deadline == start.advanced(by: .milliseconds(3500)))
  #expect(await generator.requests.first?.deadline == stop.advanced(by: .milliseconds(1500)))
}

@Test func foundationModelGeneratorReceivesTheCleanupDeadline() async throws {
  let deadline = TestCleanupClock.fixedInstant.advanced(by: .milliseconds(1500))
  let probe = FoundationModelOperationProbe()
  let generator = FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(request: request, maximumOutputTokens: maximumOutputTokens)
    await probe.waitUntilReleased()
    return request.baseline
  }
  let request = IncrementalCleanupRequest(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: deadline
  )
  let session = try generator.start(request, maximumOutputTokens: 20)
  await probe.waitUntilStarted()
  #expect(await probe.request?.deadline == deadline)
  #expect(await probe.maximumOutputTokens == 20)
  session.requestCancellation()
  await session.acknowledgement()
}

@Test func foundationModelCallerCancellationAcknowledgesAndReturnsNoCandidate() async throws {
  let probe = FoundationModelOperationProbe()
  let generator = FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }
  let session = try generator.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)
  let result = Task { try await session.result() }
  await probe.waitUntilStarted()
  session.requestCancellation()
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await result.value
  }
  await probe.release("late")
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await session.result()
  }
}

@Test func foundationModelAcknowledgementCompletesAfterCancellation() async throws {
  let session = try FoundationModelCleanupGenerator { _, _ in "unused" }
    .start(.init(
      baseline: "send the report",
      protectedForms: [],
      replacements: 0,
      deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
    ), maximumOutputTokens: 20)
  let acknowledgement = Task { await session.acknowledgement() }
  session.requestCancellation()
  _ = await acknowledgement.value
  await session.acknowledgement()
}

@Test func foundationModelForceTerminationUnblocksBothWaiters() async throws {
  let probe = FoundationModelOperationProbe()
  let session = try FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)
  let result = Task { try await session.result() }
  let acknowledgement = Task { await session.acknowledgement() }
  await probe.waitUntilStarted()
  session.forceTerminate()
  await #expect(throws: CleanupGenerationError.terminated) {
    try await result.value
  }
  _ = await acknowledgement.value
}

@Test func foundationModelLateUnderlyingWorkCannotPublish() async throws {
  let probe = FoundationModelOperationProbe()
  let session = try FoundationModelCleanupGenerator { request, maximumOutputTokens in
    await probe.record(
      request: request,
      maximumOutputTokens: maximumOutputTokens
    )
    await probe.waitUntilReleased()
    return request.baseline
  }.start(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: TestCleanupClock.fixedInstant.advanced(by: .seconds(1))
  ), maximumOutputTokens: 20)
  let result = Task { try await session.result() }
  await probe.waitUntilStarted()
  session.forceTerminate()
  await #expect(throws: CleanupGenerationError.terminated) {
    try await result.value
  }
  await probe.release("late")
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.terminated) {
    try await session.result()
  }
}
~~~

- [ ] **Step 2: Run the three red commands.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AppleSpeechStreamingAdapterTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelCleanupGeneratorTests
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
~~~

Expected failure: adapter, generator, processor, session, processor error,
clock, budget, cleanup-deadline, finalization-task ownership, cancellation
acknowledgement, four-method Foundation Model session, and publication-gate
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
  private let generate:
    @Sendable (IncrementalCleanupRequest, Int) async throws -> String

  init(dictation: FoundationModelDictation) {
    generate = { request, _ in
      await dictation.cleanupResult(request.baseline).text
    }
  }

  init(
    generate: @escaping @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  ) {
    self.generate = generate
  }

  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession {
    FoundationModelCleanupSession(
      request: request,
      maximumOutputTokens: maximumOutputTokens,
      generate: generate
    )
  }
}

private final class FoundationModelCleanupSession: CleanupGenerationSession, @unchecked Sendable {
  private let gate: FoundationModelPublicationGate
  private let underlying: Task<Void, Never>

  init(
    request: IncrementalCleanupRequest,
    maximumOutputTokens: Int,
    generate: @escaping @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  ) {
    let publicationGate = FoundationModelPublicationGate()
    gate = publicationGate
    underlying = Task.detached {
      do {
        let text = try await generate(request, maximumOutputTokens)
        publicationGate.publish(.init(cleaned: text))
      } catch is CancellationError {
        publicationGate.close(.requestCancelled)
      } catch {
        publicationGate.close(.generationFailed)
      }
    }
  }

  func result() async throws -> GeneratedCleanupCandidate {
    try await gate.result()
  }

  func acknowledgement() async {
    await gate.acknowledgement()
  }

  func requestCancellation() {
    gate.close(.requestCancelled)
    underlying.cancel()
  }

  func forceTerminate() {
    gate.close(.terminated)
    underlying.cancel()
  }
}

private final class FoundationModelPublicationGate: @unchecked Sendable {
  // The lock-protected gate resumes result/acknowledgement continuations once.
  // publish returns false after close, so detached late work is never visible.
  func publish(_ candidate: GeneratedCleanupCandidate) -> Bool
  func close(_ error: CleanupGenerationError)
  func result() async throws -> GeneratedCleanupCandidate
  func acknowledgement() async
}
~~~

Implement the gate with `NSLock` and one result continuation plus one
acknowledgement continuation: `publish` stores the candidate, marks the gate
closed, resumes both waiters, and returns `true`; `close` marks it closed,
resumes a waiting result with its terminal error and the acknowledgement
waiter, and is a no-op after the first terminal transition. `result` and
`acknowledgement` first read an already-completed state under the lock, so
there is no continuation race. The terminal result/error is replayable and
stable for later `result()` calls; acknowledgement is idempotent. The tests
therefore release the underlying operation only after cancellation or force
termination, then call `result()` again and assert the same terminal error
without observing a second candidate publication.

The injected production closure calls existing Apple Foundation Models where
supported and deterministic local cleanup otherwise. The Workstream A Task 1
validator remains final authority. `FoundationModelCleanupSession` implements
all four `CleanupGenerationSession` methods. Its underlying operation is
detachable because in-process Foundation Models cannot promise true force
termination: cancellation first closes the publication gate and acknowledges
the session, then requests cancellation of the underlying task. A deadline or
caller cancellation therefore lets the bounded cleaner drain its structured
children immediately. If the underlying operation later completes, `publish`
returns false and no result, update, insertion, or acknowledgement is emitted.
The gate is idempotent and the first terminal state wins; no claim is made that
the Foundation Model computation itself was killed.

`FoundationModelOperationProbe` is an actor-owned test fixture with
`record(request:maximumOutputTokens:)`, `waitUntilStarted()`,
`waitUntilReleased()`, and `release(_:)`. It blocks the underlying closure
until each test chooses cancellation or force termination. `record` stores the
request/token values and resumes `waitUntilStarted()` waiters. Every producer
closure calls `record` before waiting for release, and each cancellation or
force-termination test waits for `waitUntilStarted()` before closing the gate.
It does not inspect the private publication gate; the tests use only `result()`
and `acknowledgement()` as the observable session contract.

The Task 4 cleanup probe additionally exposes
`acknowledgementFinished` after the cleaner's helper session has either
acknowledged cancellation or completed its bounded force-termination path.
For the ordered cancellation test, `CleanupGeneratorProbe` accepts the
test-only `onAcknowledgementFinished` callback and invokes it at its single
acknowledgement transition. `StreamingSpeechSourceProbe` accepts `onCancel`
and `onRelease` callbacks and invokes them exactly once from the corresponding
source methods. The test therefore observes source cancellation early, helper
acknowledgement before source release, and both caller-return events after
release rather than inferring order from a post-completion history.

When initialized with `finishBlocksUntilCancel: true`, the same source probe
marks `finishStarted`, waits inside `finish()` for `cancel()`, and then marks
`finishUnblockedByCancel` before throwing `CancellationError`. The blocking
source test waits for `waitUntilFinishStarted()`, starts a second finish waiter,
cancels the session, and asserts one finish call, one source cancellation, one
release, both finish waiters' terminal cancellation, and no published result or
update. This is the Apple Speech continuation case: source cancellation occurs
early enough to unblock finish, while the session still awaits finalization
before releasing resources.

- [ ] **Step 5: Add the processor/session.**

~~~swift
@MainActor
final class StreamingDictationProcessor: DictationProcessing {
  typealias SourceFactory =
    @MainActor () async throws -> any StreamingSpeechSource

  private let clock: DictationClock
  private let budget: DictationProcessingBudget

  init(
    makeSource: @escaping SourceFactory,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?,
    clock: DictationClock = .live,
    budget: DictationProcessingBudget = .production
  )

  func prepare(for intent: DictationPreparationIntent) async
  func handle(_ signal: DictationRuntimeSignal) async
  func begin(
    configuration: DictationProcessingConfiguration
  ) async throws -> any DictationProcessingSession {
    let source = try await makeSource()
    let callbackBuffer = StreamingDictationCallbackBuffer()
    do {
      try await source.start(
        provisional: { callbackBuffer.provisional($0) },
        level: { callbackBuffer.level($0) }
      )
      return StreamingDictationSession(
        configuration: configuration,
        source: source,
        callbackBuffer: callbackBuffer,
        dictionaryResolver: dictionaryResolver,
        cleaner: cleaner,
        runtime: runtime,
        clock: clock,
        budget: budget
      )
    } catch {
      await source.releaseResources()
      throw error
    }
  }
}
~~~

~~~swift
@MainActor
fileprivate final class StreamingDictationCallbackBuffer {
  func provisional(_ text: String)
  func level(_ value: Float)
  func attach(to session: StreamingDictationSession)
}

@MainActor
final class StreamingDictationSession: DictationProcessingSession {
  private let source: any StreamingSpeechSource
  private let continuation: AsyncThrowingStream<DictationTextUpdate, Error>.Continuation
  private let dictionaryResolver: any TranscriptDictionaryResolving
  private let cleaner: IncrementalTranscriptCleaner
  private let clock: DictationClock
  private let budget: DictationProcessingBudget
  private var finalizationTask: Task<DictationProcessingResult, Error>?
  private var cancellationTask: Task<Void, Never>?
  private var isCancelled = false
  private var sourceCancellationRequested = false
  private var resourcesReleased = false
  private var generation: UInt64 = 0

  fileprivate init(
    configuration: DictationProcessingConfiguration,
    source: any StreamingSpeechSource,
    callbackBuffer: StreamingDictationCallbackBuffer,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?,
    clock: DictationClock,
    budget: DictationProcessingBudget
  )

  var updates: AsyncThrowingStream<DictationTextUpdate, Error> { get }
  func finish() async throws -> DictationProcessingResult {
    if let finalizationTask {
      return try await finalizationTask.value
    }
    guard !isCancelled else { throw CancellationError() }
    let task = Task { try await self.finalize() }
    finalizationTask = task
    return try await task.value
  }

  func cancel() async {
    if let cancellationTask {
      await cancellationTask.value
      return
    }
    let task = Task { @MainActor [weak self] in
      await self?.performCancellation()
    }
    cancellationTask = task
    await task.value
  }

  private func performCancellation() async {
    guard !isCancelled else { return }
    isCancelled = true
    generation &+= 1
    continuation.finish()

    // Apple Speech may suspend finish() on its session continuation. Cancel
    // the sole source before awaiting finalization so that continuation opens.
    if !sourceCancellationRequested {
      sourceCancellationRequested = true
      await source.cancel()
    }
    if let finalizationTask {
      finalizationTask.cancel()
      _ = try? await finalizationTask.value
    }
    if !resourcesReleased {
      resourcesReleased = true
      await source.releaseResources()
    }
  }

  private func finalize() async throws -> DictationProcessingResult
}
~~~

`StreamingDictationProcessor.begin` is the only source starter. It awaits the
`SourceFactory`, creates one callback buffer, installs both callbacks, and
awaits `source.start` exactly once before returning. The synchronous session
initializer receives that already-started source and the buffer; it never
calls `start`. The buffer forwards callbacks after `attach(to:)` and retains
callbacks that arrive synchronously during start until the session takes
ownership. If source start throws, `begin` awaits `releaseResources()` before
rethrowing; a factory failure before a source exists has nothing to release.
`StreamingSpeechSourceProbe` records start count, callback installation,
release count, and emitted callbacks in the two lifecycle tests above.

`StreamingDictationSession` owns one already-started source, state, generation
counter, stream continuation, one `finalizationTask`, one shared
`cancellationTask`, cancellation state, injected `DictationClock`, and
`DictationProcessingBudget`. At `begin`, it records no deadline. At `finish`,
the session installs exactly one finalization task; later callers await that
same task. It first returns the existing task when present, then guards
`isCancelled` before creating a new task, so cancel-before-finish cannot start
new work and simultaneous finish callers share one terminal task. The task
records
`stopInstant = clock.now()` exactly once, constructs
`insertionDeadline = stopInstant.advanced(by: budget.insertion)` immediately,
and passes both values to:

~~~swift
let stopInstant = clock.now()
let insertionDeadline = stopInstant.advanced(by: budget.insertion)
let deadline = DictationDeadline(
  stopInstant: stopInstant,
  insertionDeadline: insertionDeadline,
  cleanupBudget: budget.cleanup
)
let request = IncrementalCleanupRequest(
  baseline: resolution.baseline,
  protectedForms: resolution.protectedForms,
  replacements: resolution.replacements,
  deadline: deadline.cleanupDeadline
)
let decision = try await cleaner.clean(request)
~~~

`cleanupDeadline` is exactly
`min(stopInstant + budget.cleanup, stopInstant + budget.insertion)` (1,500 ms
and 3,000 ms in production). Each provisional callback
increments generation and publishes only an accepted `StreamingTranscriptState`
update. `finish` calls source `finish` exactly once, rejects empty final text,
resolves the dictionary before creating the request, and never calls the legacy
cleaner. A cleaned candidate publishes `cleanedTranscript`; every
unsafe/unavailable cleanup publishes `insertedText` equal to the exact
baseline. A resolver failure publishes raw ASR recovery with no cleaner call.
The first `cancel` stores a `Task<Void, Never>` in `cancellationTask` before
awaiting it. That task invalidates the generation and closes updates, cancels
the sole source early enough to unblock an in-flight source `finish`, cancels
the one finalization task, awaits it, and releases resources exactly once.
Later concurrent or reentrant callers find the stored handle and await its
value; they never return early. The awaited task propagates caller cancellation
into `IncrementalTranscriptCleaner`, so its helper acknowledgement or
force-termination completes before release returns. No final result or update
can publish after that boundary. A state or source error closes without a late
result.

`TestDictationClock` supplies a fixed sequence of instants to the processor;
`CleanupGeneratorProbe.requests` records the request. These tests never call
`Date()`, sleep a real clock, or infer the deadline from elapsed wall time.

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
! rg -n 'AVAudioEngine|installTap|SFSpeechRecognizer|SpeechAnalyzer|URLSession|FileHandle|Data\.write' Sources/FleckApp/AppleSpeechStreamingAdapter.swift Sources/FleckApp/FoundationModelCleanupGenerator.swift Sources/FleckApp/StreamingDictationProcessor.swift
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/AppleSpeechStreamingAdapter.swift \
    Sources/FleckApp/FoundationModelCleanupGenerator.swift \
    Sources/FleckApp/StreamingDictationProcessor.swift \
    Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift \
    Tests/FleckAppTests/FoundationModelCleanupGeneratorTests.swift \
    Tests/FleckAppTests/StreamingDictationProcessorTests.swift \
  | sort -u
)"
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

enum CancellationEvent: Equatable {
  case focusedEditorRollback
  case sessionCancel
  case sourceCancel
  case sourceRelease
}

@MainActor
final class CancellationOrderRecorder {
  private(set) var values: [CancellationEvent] = []
  func append(_ event: CancellationEvent) { values.append(event) }
}

// ProcessingProbe's callbacks are test-only hooks from its owned session and
// source probes; Fixture(onFocusedEditorRollback:) records the existing
// FocusedDictationEditing.cancelFocusedDictation() restoration call.

@Test @MainActor
func cancellationRollsBackFocusedEditorBeforeSessionAndSourceCancel() async throws {
  let order = CancellationOrderRecorder()
  let processing = ProcessingProbe(
    onSessionCancel: { order.append(.sessionCancel) },
    onSourceCancel: { order.append(.sourceCancel) },
    onSourceRelease: { order.append(.sourceRelease) }
  )
  let fixture = try Fixture(
    processing: processing,
    onFocusedEditorRollback: { order.append(.focusedEditorRollback) }
  )
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)

  await fixture.coordinator.cancel()

  #expect(order.values == [
    .focusedEditorRollback,
    .sessionCancel,
    .sourceCancel,
    .sourceRelease
  ])
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

The capture record stores its current generation and, for the incremental path,
the owned `DictationProcessingSession`. The cancellation path is ordered
explicitly:

~~~swift
private func cancelActiveCapture(_ id: UUID) async {
  guard var capture, capture.id == id, !capture.cancelRequested else { return }
  capture.cancelRequested = true
  capture.generation &+= 1
  self.capture = capture

  rollbackEditor(id)

  guard let current = self.capture, current.id == id else { return }
  if let session = current.processingSession {
    await session.cancel()
  } else if let engine = current.engine {
    await engine.cancel()
    await engine.releaseResources()
  }
  await completeCancellation(id)
}
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
not call legacy `cleaner.clean` on this branch. At cancellation start, mark the
capture cancelled and invalidate its generation first; restore the focused
editor transaction second through `rollbackEditor` (which calls
`cancelFocusedDictation()` when no commit receipt exists); only then await
processing-session `cancel()`. That session owns finalization cancellation and
source cancellation/release; when finalization is in flight, the session
cancels its source before awaiting finalization so Apple Speech finish can
unblock. The coordinator publishes `.cancelled` only after that await and
publishes nothing from a late task. The ordered coordinator test records
focused-editor rollback, session cancel, source cancel, and source release and
asserts this exact sequence.

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
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift \
    Tests/FleckAppTests/PersonalDictionaryTranscriptResolverTests.swift \
    Sources/FleckApp/DictationCoordinator.swift \
    Sources/FleckApp/FleckApp.swift \
    Tests/FleckAppTests/DictationCoordinatorTests.swift \
  | sort -u
)"
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
