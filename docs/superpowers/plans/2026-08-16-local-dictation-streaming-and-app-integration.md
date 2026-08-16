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
final text, finish, cancellation, and resource release; it creates no audio engine,
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
  `cancellationTask`. `finish()` installs finalization exactly once. On every
  `cancel()` call, the session first checks for an existing stored
  `cancellationTask` and awaits that exact task before inspecting terminal
  state; only a caller that finds no stored task may return early for an
  already-terminal session. The first cancellation caller then marks
  `isCancelled`, invalidates the generation, and closes updates synchronously
  before creating or storing the shared cancellation task. A `finish()` that
  entered earlier returns the one existing finalization task; otherwise it
  rejects when that invalidated state or a stored cancellation task is already
  present, so cancellation cannot race in a new finalization task. If source
  `finish()` is still blocked, the
  shared task cancels finalization first so its `Task.isCancelled` check is
  visible, then calls the sole source's `cancel()` early enough to unblock it,
  and awaits finalization and the cleaner's bounded acknowledgement or
  force-termination path. If `finish()` has already
  completed, the source is already logically finished and cancellation makes
  zero second source-terminal calls; it only drains finalization/cleanup. In
  production, `AppleSpeechCapture.finish()` and `cancel()` each terminalize
  and release their underlying `AppleSpeechSession` before returning; the
  streaming adapter forwards those operations and does not add a second
  physical release. The session records one logical source terminalization,
  and every independent concurrent caller awaits that same cancellation task
  before returning.
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
- `FoundationModelDictation.cleanupResult(_:maximumOutputTokens:)` remains the
  Apple Foundation Models/deterministic control. Workstream B threads the
  bounded token count through its existing closure and the real
  `GenerationOptions(maximumResponseTokens:)` request; it adds no retry or
  second request.
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
- `Sources/FleckApp/FoundationModelDictation.swift` — thread the bounded
  cleanup token count into the existing Foundation Models request.
- `Tests/FleckAppTests/DictationCoordinatorTests.swift` — both-path,
  provisional, result, and cancellation integration tests.
- `Tests/FleckAppTests/FoundationModelDictationTests.swift` — update the
  existing cleanup closure fixtures and prove the production cap boundary.

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
  // task before terminal cancellation returns.
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

`finish()` and `cancel()` are source-owned terminal operations. The production
`AppleSpeechStreamingAdapter` forwards them to the already-created
`SpeechEngine`; `AppleSpeechCapture` performs the underlying session release
inside the operation that wins the phase. A completed `finish()` owns the
physical release on success or failure, while cancellation owns it only when
it wins before finish completion; repeated logical terminalization is rejected
by the session and the underlying Apple operation remains idempotent.
`releaseResources()` remains the logical cleanup hook for a source that fails
before start; the streaming session does not require a second physical release
after successful or failed `finish()` or after `cancel()`. Implementations must
not synchronously await the owning `StreamingDictationSession.cancel()` from a
dependency callback; a callback may record state or send an independent
notification, but it cannot await the session's shared cancellation task. The
B4 concurrency evidence therefore covers independent concurrent callers while
source cancellation still occurs early enough to unblock an in-flight `finish()`.

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
import Foundation
import Testing

@testable import FleckApp

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
sleep a production wall clock. The first accepted public `finish()` entry
captures `stopInstant` synchronously before creating or awaiting its
finalization task and before the source's `finish()` is called. It creates
`insertionDeadline = stopInstant + budget.insertion` immediately; cleanup is
bounded by the absolute `min(stopInstant + budget.cleanup, insertionDeadline)`
even when source finalization consumes part of the insertion budget.
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
import Foundation
import Testing

@testable import FleckApp

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
import Foundation
import Testing

@testable import FleckApp

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
`Sources/FleckApp/StreamingDictationProcessor.swift`; modify
`Sources/FleckApp/FoundationModelDictation.swift`; and create or modify the
four matching test files, including
`Tests/FleckAppTests/FoundationModelDictationTests.swift`.

**Excluded files:** Every other Workstream B path, especially
`AppleSpeechCapture.swift`, `DictationCoordinator.swift`, `FleckApp.swift`,
`EnhancedModelManager.swift`, Settings, manifests, and all model files except
the existing `FoundationModelDictation.swift` control explicitly owned here.

**Consumes:** `SpeechEngine`, Workstream B Tasks 1–3, Workstream A Task 2's
`IncrementalTranscriptCleaner`, and the existing
`FoundationModelDictation.cleanupResult` control.

**Produces:** `AppleSpeechStreamingAdapter`,
`FoundationModelCleanupGenerator`, `StreamingDictationProcessor`,
`StreamingDictationSession`, and `StreamingDictationProcessorError`.

### TDD red

- [ ] **Step 1: Write forwarding and safety tests.**

~~~swift
import Foundation
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@testable import FleckApp

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

#if canImport(FoundationModels)
@available(macOS 26, *)
@Test
func foundationModelDictationPassesMaximumOutputTokensToProductionResponderBoundary() async {
  let probe = FoundationModelResponderProbe()
  let responder = FoundationModelCleanupResponder { _, options in
    await probe.record(options)
    return "send the report"
  }
  let dictation = FoundationModelDictation(
    osMajorVersion: { 26 },
    foundationModelResponder: responder,
    routingGenerator: { _, _ in .inbox }
  )

  let result = await dictation.cleanupResult(
    "send the report",
    maximumOutputTokens: 23
  )

  #expect(result.outcome == .cleaned)
  #expect(await probe.calls == 1)
  #expect(await probe.maximumResponseTokens == 23)
}

@available(macOS 26, *)
private actor FoundationModelResponderProbe {
  private(set) var calls = 0
  private(set) var maximumResponseTokens: Int?

  func record(_ options: GenerationOptions) {
    calls += 1
    maximumResponseTokens = options.maximumResponseTokens
  }
}
#endif

private actor FoundationModelOperationProbe {
  private(set) var calls = 0
  private(set) var request: IncrementalCleanupRequest?
  private(set) var maximumOutputTokens: Int?
  private var started = false
  private var released = false

  func record(
    request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) {
    calls += 1
    self.request = request
    self.maximumOutputTokens = maximumOutputTokens
    started = true
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func waitUntilReleased() async {
    while !released { await Task.yield() }
  }

  func release(_ text: String) {
    _ = text
    released = true
  }
}

@MainActor
private func makeProcessor(
  source: any StreamingSpeechSource,
  onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
  onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
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
    budget: .production,
    onCancellationInvalidated: onCancellationInvalidated,
    onCancellationDrained: onCancellationDrained
  )
}

enum StreamingSpeechSourceProbeError: Error {
  case failed
}

@MainActor
final class StreamingSpeechSourceProbe: StreamingSpeechSource {
  init(
    startError: StreamingSpeechSourceProbeError? = nil,
    finishError: StreamingSpeechSourceProbeError? = nil,
    finalText: String? = "First",
    finishBlocksUntilCancel: Bool = false,
    finishReturnsNilAfterCancel: Bool = false,
    finishBlocksUntilRelease: Bool = false,
    onCancel: (@MainActor @Sendable () async -> Void)? = nil,
    onPhysicalRelease: (@MainActor @Sendable () async -> Void)? = nil
  )
  private let finalText: String?
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var finishStarted = false
  private(set) var finishCompleted = false
  private(set) var finishUnblockedByCancel = false
  private(set) var cancelCount = 0
  private(set) var releaseHookCount = 0
  private(set) var physicalReleaseCount = 0
  private(set) var sourceTerminalizationCount = 0
  private(set) var callbacksWereInstalled = false
  private(set) var provisionalCallbackCount = 0
  // When true, cancellation unblocks finish() and lets it return nil; the
  // default blocked-finish probe throws CancellationError instead.
  private let finishReturnsNilAfterCancel: Bool
  func emitProvisional(_ text: String)
  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  // Test-only deterministic gate for source finalization latency. The test
  // advances its injected clock, then calls this without sleeping.
  func releaseFinish()
  // This hook is used for pre-start failure cleanup; finish/cancel own the
  // production physical release.
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
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
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
  #expect(source.releaseHookCount == 1)
  #expect(source.physicalReleaseCount == 0)
}

@Test @MainActor
func successfulFinishUsesSourceOwnedTerminalizationWithoutSecondRelease() async throws {
  let source = StreamingSpeechSourceProbe()
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))

  _ = try await session.finish()
  source.emitProvisional("late")

  #expect(source.cancelCount == 0)
  #expect(source.finishCount == 1)
  #expect(source.finishCompleted)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
  await session.cancel()
  #expect(source.cancelCount == 0)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func emptyFinalTextThrowsStreamingProcessorNoSpeech() async throws {
  let source = StreamingSpeechSourceProbe(finalText: nil)
  let processor = makeProcessor(source: source)
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))

  await #expect(throws: StreamingDictationProcessorError.noSpeech) {
    _ = try await session.finish()
  }
  #expect(source.finishCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func failedFinishUsesSourceOwnedTerminalizationAndPublishesNoLateUpdate() async throws {
  let source = StreamingSpeechSourceProbe(finishError: .failed)
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

  await #expect(throws: StreamingSpeechSourceProbeError.failed) {
    _ = try await session.finish()
  }
  source.emitProvisional("late")

  #expect(source.cancelCount == 0)
  #expect(source.finishCount == 1)
  #expect(source.finishCompleted)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
  await session.cancel()
  #expect(source.cancelCount == 0)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
}

@Test @MainActor
func cancellingAfterSourceFinishAwaitsCleanupWithoutSecondSourceTerminalization() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
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

  #expect(source.finishCount == 1)
  #expect(source.finishCompleted)
  #expect(source.cancelCount == 0)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)

  await session.cancel()
  await order.append(.firstCallerReturned)

  #expect(await helper.acknowledgementFinished)
  await #expect(throws: CancellationError.self) { try await finalization.value }
  #expect(source.cancelCount == 0)
  #expect(source.finishCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let physicalReleaseIndex = try #require(
    events.firstIndex(of: .sourcePhysicalRelease)
  )
  let helperIndex = try #require(events.firstIndex(of: .helperAcknowledged))
  let returnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  #expect(physicalReleaseIndex < helperIndex)
  #expect(helperIndex < returnIndex)
  #expect(!events.contains(.sourceCancelStarted))
}

enum CancellationDrainEvent: Equatable {
  case sourceCancelStarted
  case sourcePhysicalRelease
  case helperAcknowledged
  case sharedDrainCompleted
  case secondCallerEntered
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
func concurrentCancelCallersShareOneTaskDuringBlockedFinish() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    finishBlocksUntilCancel: true,
    onCancel: {
      await order.append(.sourceCancelStarted)
      await order.waitUntil(.secondCallerEntered)
    },
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
  )
  let processor = makeProcessor(
    source: source,
    onCancellationDrained: { order.append(.sharedDrainCompleted) }
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
  await source.waitUntilFinishStarted()

  let first = Task {
    await session.cancel()
    await order.append(.firstCallerReturned)
  }
  await order.waitUntil(.sourceCancelStarted)
  let second = Task {
    await order.append(.secondCallerEntered)
    await session.cancel()
    await order.append(.secondCallerReturned)
  }
  await first.value
  await second.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.finishCompleted == false)
  #expect(source.releaseHookCount == 0)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let cancelIndex = try #require(events.firstIndex(of: .sourceCancelStarted))
  let secondEntryIndex = try #require(events.firstIndex(of: .secondCallerEntered))
  let physicalReleaseIndex = try #require(
    events.firstIndex(of: .sourcePhysicalRelease)
  )
  let sharedDrainIndex = try #require(
    events.firstIndex(of: .sharedDrainCompleted)
  )
  let firstReturnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  let secondReturnIndex = try #require(events.firstIndex(of: .secondCallerReturned))
  #expect(cancelIndex < secondEntryIndex)
  #expect(physicalReleaseIndex < firstReturnIndex)
  #expect(physicalReleaseIndex < secondReturnIndex)
  #expect(sharedDrainIndex < firstReturnIndex)
  #expect(sharedDrainIndex < secondReturnIndex)
}

@Test @MainActor
func cancellingBlockedFinishReturningNilWinsWithoutNoSpeechResult() async throws {
  let order = CancellationDrainRecorder()
  let source = StreamingSpeechSourceProbe(
    finalText: nil,
    finishBlocksUntilCancel: true,
    finishReturnsNilAfterCancel: true,
    onCancel: {
      await order.append(.sourceCancelStarted)
      await order.waitUntil(.secondCallerEntered)
    },
    onPhysicalRelease: { await order.append(.sourcePhysicalRelease) }
  )
  let processor = makeProcessor(
    source: source,
    onCancellationDrained: { order.append(.sharedDrainCompleted) }
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
  await source.waitUntilFinishStarted()

  let first = Task {
    await session.cancel()
    await order.append(.firstCallerReturned)
  }
  await order.waitUntil(.sourceCancelStarted)
  let second = Task {
    await order.append(.secondCallerEntered)
    await session.cancel()
    await order.append(.secondCallerReturned)
  }
  await first.value
  await second.value
  await #expect(throws: CancellationError.self) { try await finalization.value }

  #expect(source.finishCount == 1)
  #expect(source.finishUnblockedByCancel)
  #expect(source.finishCompleted)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(try await updates.value.isEmpty)
  let events = order.events
  let sharedDrainIndex = try #require(
    events.firstIndex(of: .sharedDrainCompleted)
  )
  let firstReturnIndex = try #require(events.firstIndex(of: .firstCallerReturned))
  let secondReturnIndex = try #require(events.firstIndex(of: .secondCallerReturned))
  #expect(sharedDrainIndex < firstReturnIndex)
  #expect(sharedDrainIndex < secondReturnIndex)
}

@Test @MainActor
func cancellingSessionUnblocksInFlightSourceFinishWithSourceOwnedRelease() async throws {
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
  #expect(source.finishCompleted == false)
  #expect(source.physicalReleaseCount == 0)
  let secondFinish = Task { try await session.finish() }
  await Task.yield()

  await session.cancel()

  await #expect(throws: CancellationError.self) { try await firstFinish.value }
  await #expect(throws: CancellationError.self) { try await secondFinish.value }
  #expect(source.finishCount == 1)
  #expect(source.finishUnblockedByCancel)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.finishCompleted == false)
  #expect(source.releaseHookCount == 0)
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
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
}

@MainActor
final class CancellationRaceRecorder {
  private(set) var invalidated = false
  func recordInvalidation() { invalidated = true }
  func waitUntilInvalidated() async {
    while !invalidated { await Task.yield() }
  }
}

@Test @MainActor
func cancellationWinnerClosesTheFinishRaceBeforeAnyFinalizationOrSourceFinish() async throws {
  let source = StreamingSpeechSourceProbe()
  let recorder = CancellationRaceRecorder()
  let processor = makeProcessor(
    source: source,
    onCancellationInvalidated: { recorder.recordInvalidation() }
  )
  let session = try await processor.begin(configuration: .init(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: .englishDefault
  ))

  let cancellation = Task { await session.cancel() }
  await recorder.waitUntilInvalidated()
  let finish = Task { try await session.finish() }

  await cancellation.value
  await #expect(throws: CancellationError.self) { try await finish.value }
  #expect(source.finishCount == 0)
  #expect(source.cancelCount == 1)
  #expect(source.sourceTerminalizationCount == 1)
  #expect(source.physicalReleaseCount == 1)
  #expect(source.releaseHookCount == 0)
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
func processorCapturesStopBeforeDelayedSourceFinalization() async throws {
  let stop = TestDictationClock.fixedInstant
  let sourceFinishedAt = stop.advanced(by: .seconds(2))
  let clock = TestDictationClock(values: [stop, sourceFinishedAt])
  let source = StreamingSpeechSourceProbe(finishBlocksUntilRelease: true)
  let generator = CleanupGeneratorProbe(result: "send the report")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )
  let processor = StreamingDictationProcessor(
    makeSource: { source },
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
  let finalization = Task { try await session.finish() }
  await source.waitUntilFinishStarted()
  #expect(source.finishCompleted == false)

  // The second deterministic instant represents two seconds spent inside
  // source.finish(). It is observed before releasing the source gate; no
  // production wall clock or sleep is involved.
  #expect(clock.now() == sourceFinishedAt)
  source.releaseFinish()
  _ = try await finalization.value

  #expect(await generator.requests.first?.deadline == stop.advanced(by: .milliseconds(1500)))
  #expect(await generator.requests.first?.deadline != sourceFinishedAt.advanced(by: .milliseconds(1500)))
  #expect(sourceFinishedAt.advanced(by: .seconds(1)) == stop.advanced(by: .seconds(3)))
}

@Test func foundationModelSessionStartsOnlyWhenResultIsRequested() async throws {
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

  #expect(await probe.calls == 0)
  let first = Task { try await session.result() }
  await probe.waitUntilStarted()
  #expect(await probe.calls == 1)
  #expect(await probe.maximumOutputTokens == 20)

  let concurrent = Task { try await session.result() }
  await probe.release("first")
  _ = try await first.value
  _ = try await concurrent.value
  _ = try await session.result()
  #expect(await probe.calls == 1)
}

@Test func foundationModelPreResultCancellationDoesNotStartGeneration() async throws {
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

  #expect(await probe.calls == 0)
  session.requestCancellation()
  await session.acknowledgement()
  #expect(await probe.calls == 0)
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await session.result()
  }
  await probe.release("late")
  #expect(await probe.calls == 0)
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
  #expect(await probe.calls == 0)
  let result = Task { try await session.result() }
  await probe.waitUntilStarted()
  #expect(await probe.request?.deadline == deadline)
  #expect(await probe.maximumOutputTokens == 20)
  session.requestCancellation()
  await session.acknowledgement()
  await #expect(throws: CleanupGenerationError.requestCancelled) {
    try await result.value
  }
  await probe.release("late")
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
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
~~~

Expected failure: adapter, generator, processor, session, processor error,
clock, budget, cleanup-deadline, finalization-task ownership, cancellation
acknowledgement, four-method Foundation Model session, publication-gate
symbols, and the bounded Foundation Models cleanup closure/request do not
exist.

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
  // Used only for start-failure cleanup. AppleSpeechCapture.finish/cancel
  // already release their AppleSpeechSession before returning.
  func releaseResources() async { await engine.releaseResources() }
}
~~~

The factory receives the existing engine from
`DictationSpeechEngineProvider.engineForCapture(preferred:)`. It does not
construct `AppleSpeechCapture` and does not expose audio chunks. Its `finish`
and `cancel` methods therefore inherit the current `SpeechEngine` contract:
the Apple implementation performs physical session release inside the
terminal operation, and the adapter does not add another release call.

- [ ] **Step 4: Add the bounded cleanup generator.**

~~~swift
struct FoundationModelCleanupGenerator: BoundedCleanupGenerating {
  private let generate:
    @Sendable (IncrementalCleanupRequest, Int) async throws -> String

  init(dictation: FoundationModelDictation) {
    generate = { request, maximumOutputTokens in
      await dictation.cleanupResult(
        request.baseline,
        maximumOutputTokens: maximumOutputTokens
      ).text
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
      responder: generate
    )
  }
}

private final class FoundationModelCleanupSession: CleanupGenerationSession, @unchecked Sendable {
  private let request: IncrementalCleanupRequest
  private let maximumOutputTokens: Int
  private let responder:
    @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  private let gate: FoundationModelPublicationGate
  private let lock = NSLock()
  private var generationTask: Task<Void, Never>?
  private var cancellationRequested = false

  init(
    request: IncrementalCleanupRequest,
    maximumOutputTokens: Int,
    responder: @escaping @Sendable (IncrementalCleanupRequest, Int) async throws -> String
  ) {
    self.request = request
    self.maximumOutputTokens = maximumOutputTokens
    self.responder = responder
    gate = FoundationModelPublicationGate()
  }

  func result() async throws -> GeneratedCleanupCandidate {
    startGenerationIfNeeded()
    return try await gate.result()
  }

  func acknowledgement() async {
    await gate.acknowledgement()
  }

  func requestCancellation() {
    let task: Task<Void, Never>?
    lock.lock()
    cancellationRequested = true
    task = generationTask
    lock.unlock()
    gate.close(.requestCancelled)
    task?.cancel()
  }

  func forceTerminate() {
    let task: Task<Void, Never>?
    lock.lock()
    cancellationRequested = true
    task = generationTask
    lock.unlock()
    gate.close(.terminated)
    task?.cancel()
  }

  private func startGenerationIfNeeded() {
    lock.lock()
    defer { lock.unlock() }
    guard generationTask == nil, !cancellationRequested else { return }
    let request = self.request
    let maximumOutputTokens = self.maximumOutputTokens
    let responder = self.responder
    let gate = self.gate
    generationTask = Task {
      do {
        let text = try await responder(request, maximumOutputTokens)
        gate.publish(.init(cleaned: text))
      } catch is CancellationError {
        gate.close(.requestCancelled)
      } catch {
        gate.close(.generationFailed)
      }
    }
  }
}

private final class FoundationModelPublicationGate: @unchecked Sendable {
  // The lock-protected gate resumes result/acknowledgement continuations once.
  // publish returns false after close, so late generation work is never visible.
  func publish(_ candidate: GeneratedCleanupCandidate) -> Bool
  func close(_ error: CleanupGenerationError)
  func result() async throws -> GeneratedCleanupCandidate
  func acknowledgement() async
}
~~~

Modify the existing `FoundationModelDictation` control in this task rather
than introducing a second Foundation Models session. Its cleanup closure and
entry point carry the cap, and every existing test fixture changes from
`{ prompt in ... }` to `{ prompt, _ in ... }` unless it asserts the cap. Keep
one injected `respond` call and preserve the deterministic local fallback:

~~~swift
struct FoundationModelDictation: TranscriptCleaning, DestinationRouting {
  typealias CleanupGenerator =
    @Sendable (FoundationModelCleanupPrompt, Int) async throws -> String

  init(
    osMajorVersion: @escaping @Sendable () -> Int = {
      ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    },
    cleanupGenerator: @escaping CleanupGenerator = FoundationModelDictation.generateCleanup,
    routingGenerator: @escaping RoutingGenerator = FoundationModelDictation.generateRoute
  ) {
    self.osMajorVersion = osMajorVersion
    self.cleanupGenerator = cleanupGenerator
    self.routingGenerator = routingGenerator
  }

  func cleanupResult(
    _ rawTranscript: String,
    maximumOutputTokens: Int = 128
  ) async -> FoundationModelCleanupResult {
    let localFallback = Self.localCleanup(rawTranscript)
    guard osMajorVersion() >= 26 else {
      return Self.fallbackResult(raw: rawTranscript, cleaned: localFallback)
    }
    do {
      let cleaned = try await cleanupGenerator(
        .init(rawTranscript: rawTranscript),
        maximumOutputTokens
      )
      guard Self.isFaithful(cleaned, to: rawTranscript) else {
        return Self.fallbackResult(raw: rawTranscript, cleaned: localFallback)
      }
      return .init(text: cleaned, outcome: .cleaned)
    } catch {
      return Self.fallbackResult(raw: rawTranscript, cleaned: localFallback)
    }
  }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
struct FoundationModelCleanupResponder: Sendable {
  typealias Respond =
    @Sendable (String, GenerationOptions) async throws -> String

  private let respondClosure: Respond

  init(_ respond: @escaping Respond) {
    respondClosure = respond
  }

  func respond(to prompt: String, options: GenerationOptions) async throws -> String {
    try await respondClosure(prompt, options)
  }

  func generate(
    prompt: FoundationModelCleanupPrompt,
    maximumOutputTokens: Int
  ) async throws -> String {
    let options = GenerationOptions(maximumResponseTokens: maximumOutputTokens)
    return try await respond(to: prompt.rendered, options: options)
  }
}

@available(macOS 26, *)
extension FoundationModelDictation {
  init(
    osMajorVersion: @escaping @Sendable () -> Int = {
      ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    },
    foundationModelResponder: FoundationModelCleanupResponder,
    routingGenerator: @escaping RoutingGenerator = FoundationModelDictation.generateRoute
  ) {
    self.init(
      osMajorVersion: osMajorVersion,
      cleanupGenerator: { prompt, maximumOutputTokens in
        try await foundationModelResponder.generate(
          prompt: prompt,
          maximumOutputTokens: maximumOutputTokens
        )
      },
      routingGenerator: routingGenerator
    )
  }
}
#endif

private extension FoundationModelDictation {
  static func generateCleanup(
    _ prompt: FoundationModelCleanupPrompt,
    _ maximumOutputTokens: Int
  ) async throws -> String {
    guard #available(macOS 26, *) else {
      throw FoundationModelDictationError.unavailable
    }
    #if canImport(FoundationModels)
    return try await liveCleanupResponder.generate(
      prompt: prompt,
      maximumOutputTokens: maximumOutputTokens
    )
    #else
    throw FoundationModelDictationError.unavailable
    #endif
  }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
private extension FoundationModelDictation {
  static let liveCleanupResponder = FoundationModelCleanupResponder { prompt, options in
    guard SystemLanguageModel.default.isAvailable else {
      throw FoundationModelDictationError.unavailable
    }
    let session = LanguageModelSession(instructions: cleanupInstructions)
    return try await session.respond(
      to: prompt,
      generating: GeneratedCleanup.self,
      options: options
    ).content.text
  }
}
#endif
~~~

The unavailable-platform path throws the same unavailable error. `clean(_:)`
calls `cleanupResult` with the fixed production cap, while the incremental
processor passes its bounded request cap. `FoundationModelCleanupResponder`
is the inspectable seam at the actual single `LanguageModelSession.respond`
boundary: `generate` constructs `GenerationOptions(maximumResponseTokens:)`,
and the live responder performs exactly one `respond` call. The production
boundary test invokes `FoundationModelDictation.cleanupResult` through the
responder initializer, records the options at that seam, and asserts one call
with the exact requested cap; it does not test only an outer integer closure.
There is no retry or second request, and the existing deadline/cancellation
publication gate still owns the bounded session.

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

The production responder path calls existing Apple Foundation Models where
supported and deterministic local cleanup otherwise. The Workstream A Task 1
validator remains final authority. `FoundationModelCleanupSession` implements
all four `CleanupGenerationSession` methods, but its initializer stores only
the request, token cap, responder, publication gate, and cancellation state.
The first `result()` call creates and stores one cancellable generation
`Task` under the lock; concurrent and repeated result callers await that same
task/gate, and initialization performs zero model work. Pre-result cancellation
closes the gate and acknowledges without creating a generation task. Because
in-process Foundation Models cannot promise true force termination, cancellation
or force termination closes the publication gate and requests cancellation of
the one underlying task. A deadline or caller cancellation therefore lets the
bounded cleaner drain its structured children immediately. If late generation
work completes, `publish` returns false and no result, update, insertion, or
second candidate publication is emitted. The gate is idempotent and the first
terminal state wins; no claim is made that the Foundation Model computation
itself was killed.

`FoundationModelOperationProbe` is an actor-owned test fixture with
`calls`, `record(request:maximumOutputTokens:)`, `waitUntilStarted()`,
`waitUntilReleased()`, and `release(_:)`. It blocks the responder closure
until each test chooses cancellation or force termination. The lazy-start test
asserts zero calls after `start`, one call after the first `result()`, one
call after concurrent and repeated result calls, and the exact token cap. The
pre-result cancellation test acknowledges and then proves the call count
remains zero, including after a late release. It does not inspect the private
publication gate; the tests use only `result()` and `acknowledgement()` as the
observable session contract.

The source probe models the production terminal boundary rather than releasing
at method entry. A successful or failed `finish()` invokes
`terminalizeFromFinish()` only when the source operation completes, sets
`finishCompleted`, and invokes `onPhysicalRelease` once. A blocked `finish()`
has not physically released anything while it waits. If cancellation wins
first, `cancel()` claims the one logical terminalization, invokes the physical
release once, and unblocks the in-flight finish; the default probe then exits
with cancellation without claiming a second release or reporting a completed
result. The nil-race probe sets `finishReturnsNilAfterCancel: true`, so the
source really returns nil after cancellation unblocks it and marks
`finishCompleted`; the session's immediate `Task.checkCancellation()` must
still win before nil becomes `StreamingDictationProcessorError.noSpeech`.
The probe exposes `finishCompleted`, `sourceTerminalizationCount`,
`cancelCount`, and `physicalReleaseCount`, so the two phases assert different
terminal callers.
`releaseResources()` increments only `releaseHookCount`; it never increments
the physical counter. This distinguishes pre-start cleanup from the
source-owned finish/cancel terminal operation and preserves production
idempotence.

The Task 4 cleanup probe additionally exposes
`acknowledgementFinished` after the cleaner's helper session has either
acknowledged cancellation or completed its bounded force-termination path.
For the cleanup-phase test, `CleanupGeneratorProbe` accepts the test-only
`onAcknowledgementFinished` callback and invokes it at its single
acknowledgement transition. The probe's normal `finish()` completes before the
helper starts, so the test records physical release before helper
acknowledgement and then asserts `cancelCount == 0` while cleanup is cancelled.
It therefore never requires a second source terminal call or an ordering that
would put cancellation before an already-completed finish release; both the
helper acknowledgement and the sole caller return are still observed after
the source-owned finish release. The concurrent-caller test uses the separate
blocked-finish phase: its first source-cancel callback waits until the second
caller has entered, then the session's `onCancellationDrained` callback records
`sharedDrainCompleted`. Both caller return events must occur after that shared
drain event, proving that terminal state cannot short-circuit the in-flight
cancellation task; the cancellation-owned physical release is also observed.

When initialized with `finishBlocksUntilCancel: true`, the same source probe
marks `finishStarted`, waits inside `finish()` for `cancel()`, and then marks
`finishUnblockedByCancel` before throwing `CancellationError`. The blocking
source test waits for `waitUntilFinishStarted()`, proves
`physicalReleaseCount == 0`, starts a second finish waiter, cancels the
session, and asserts one finish call, one source cancellation, one logical
terminalization, one cancellation-owned physical release, both finish
waiters' terminal cancellation, `finishCompleted == false`, and no published
result or update. This is the Apple Speech continuation case: source
cancellation occurs early enough to unblock finish; the session then awaits
finalization and helper drain before terminal cancellation returns, without a
double physical release.

When initialized with `finishBlocksUntilRelease: true`, the probe marks
`finishStarted` and holds `finish()` at its deterministic release gate without
completing or physically releasing. The deadline test supplies
`TestDictationClock(values: [stopInstant, sourceFinishedAt])`, observes the
second instant after `finishStarted` to model two seconds of source
finalization, then calls `releaseFinish()`. It asserts cleanup still receives
`stopInstant + 1,500 ms`, not `sourceFinishedAt + 1,500 ms`, while the
insertion deadline remains `stopInstant + 3,000 ms`; source finalization cannot
reset either boundary.

- [ ] **Step 5: Add the processor/session.**

~~~swift
enum StreamingDictationProcessorError: Error, Equatable {
  case noSpeech
}

@MainActor
final class StreamingDictationProcessor: DictationProcessing {
  typealias SourceFactory =
    @MainActor () async throws -> any StreamingSpeechSource

  private let clock: DictationClock
  private let budget: DictationProcessingBudget
  private let onCancellationInvalidated: (@MainActor @Sendable () -> Void)?
  private let onCancellationDrained: (@MainActor @Sendable () -> Void)?

  init(
    makeSource: @escaping SourceFactory,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?,
    clock: DictationClock = .live,
    budget: DictationProcessingBudget = .production,
    onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
    onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
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
        budget: budget,
        onCancellationInvalidated: onCancellationInvalidated,
        onCancellationDrained: onCancellationDrained
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
  private let onCancellationInvalidated: (@MainActor @Sendable () -> Void)?
  private let onCancellationDrained: (@MainActor @Sendable () -> Void)?
  private var finalizationTask: Task<DictationProcessingResult, Error>?
  private var cancellationTask: Task<Void, Never>?
  private var isCancelled = false
  private var isTerminal = false
  private enum SourceTerminalization: Equatable {
    case open
    case finished
    case cancelled
  }
  private var sourceTerminalization: SourceTerminalization = .open
  private var generation: UInt64 = 0

  fileprivate init(
    configuration: DictationProcessingConfiguration,
    source: any StreamingSpeechSource,
    callbackBuffer: StreamingDictationCallbackBuffer,
    dictionaryResolver: any TranscriptDictionaryResolving,
    cleaner: IncrementalTranscriptCleaner,
    runtime: LocalDictationRuntime?,
    clock: DictationClock,
    budget: DictationProcessingBudget,
    onCancellationInvalidated: (@MainActor @Sendable () -> Void)? = nil,
    onCancellationDrained: (@MainActor @Sendable () -> Void)? = nil
  )

  var updates: AsyncThrowingStream<DictationTextUpdate, Error> { get }
  func finish() async throws -> DictationProcessingResult {
    if let finalizationTask {
      return try await finalizationTask.value
    }
    guard !isCancelled, !isTerminal, cancellationTask == nil else {
      throw CancellationError()
    }
    // Capture the stop boundary on the public finish entry before any task
    // suspension and before source.finish() can consume the budget.
    let stopInstant = clock.now()
    let insertionDeadline = stopInstant.advanced(by: budget.insertion)
    let deadline = DictationDeadline(
      stopInstant: stopInstant,
      insertionDeadline: insertionDeadline,
      cleanupBudget: budget.cleanup
    )
    let task = Task { @MainActor [weak self] in
      guard let self else { throw CancellationError() }
      return try await self.runFinalization(deadline: deadline)
    }
    finalizationTask = task
    return try await task.value
  }

  func cancel() async {
    if let cancellationTask {
      await cancellationTask.value
      return
    }
    guard !isTerminal else { return }
    // This actor turn is the cancellation winner. No suspension occurs between
    // invalidation and storing the shared task.
    isCancelled = true
    generation &+= 1
    continuation.finish()
    onCancellationInvalidated?()

    let task = Task { @MainActor [weak self] in
      await self?.completeCancellation()
    }
    cancellationTask = task
    await task.value
  }

  private func completeCancellation() async {
    // The shared cancellation task is already stored by cancel(). Mark the
    // finalization task cancelled first so Task.isCancelled is visible before
    // the source is unblocked.
    finalizationTask?.cancel()
    if sourceTerminalization == .open {
      sourceTerminalization = .cancelled
      // Apple Speech may suspend finish() on its session continuation.
      // Production AppleSpeechCapture.cancel() releases its AppleSpeechSession
      // and opens that continuation before returning.
      await source.cancel()
    }
    if let finalizationTask {
      _ = try? await finalizationTask.value
    }
    onCancellationDrained?()
    markTerminal()
  }

  private func runFinalization(
    deadline: DictationDeadline
  ) async throws -> DictationProcessingResult {
    do {
      let result = try await finalizeBody(deadline: deadline)
      try Task.checkCancellation()
      guard !isCancelled, !isTerminal else {
        throw CancellationError()
      }
      markTerminal()
      try Task.checkCancellation()
      return result
    } catch {
      markTerminal()
      throw error
    }
  }

  private func markTerminal() {
    guard !isTerminal else { return }
    isTerminal = true
    generation &+= 1
    continuation.finish()
  }

private func finalizeBody(
  deadline: DictationDeadline
  ) async throws -> DictationProcessingResult
}
~~~

The source terminalization portion of `finalizeBody` is explicit and runs
before dictionary resolution or cleanup:

~~~swift
let rawText: String?
do {
  let returnedText = try await source.finish()
  try Task.checkCancellation()
  rawText = returnedText
  if sourceTerminalization == .open {
    sourceTerminalization = .finished
  }
} catch {
  if sourceTerminalization == .open {
    sourceTerminalization = .finished
  }
  throw error
}
try Task.checkCancellation()
guard let rawText, !rawText.isEmpty else {
  throw StreamingDictationProcessorError.noSpeech
}
~~~

If cancellation has already claimed `.cancelled`, this code is only the
already-running finish that cancellation is unblocking; it cannot claim a
second logical terminalization or publish its result because the synchronous
generation/update gate is closed.

`StreamingDictationProcessor.begin` is the only source starter. It awaits the
`SourceFactory`, creates one callback buffer, installs both callbacks, and
awaits `source.start` exactly once before returning. The synchronous session
initializer receives that already-started source and the buffer; it never
calls `start`. The buffer forwards callbacks after `attach(to:)` and retains
callbacks that arrive synchronously during start until the session takes
ownership. If source start throws, `begin` awaits `releaseResources()` before
rethrowing; a factory failure before a source exists has nothing to release.
`StreamingSpeechSourceProbe` records start count, callback installation,
release-hook count, physical-release count, logical terminalization count, and
emitted callbacks in the lifecycle tests above. Its
`finishError` initializer input makes `finish()` throw after recording the
attempt, while `finalText: nil` makes a cancel-unblocked finish return nil.
The successful and failed terminal-path tests therefore assert one
source-owned terminalization and one physical release with no release-hook
call. The blocked nil-finish test must see `CancellationError`, never
`StreamingDictationProcessorError.noSpeech`, after the finalization task was
cancelled before source cancellation. A later `session.cancel()` is a no-op
after the terminal state, so it cannot issue a second source terminal call or
physical release. A source start failure still uses the release hook exactly
once before rethrowing.

`StreamingDictationSession` owns one already-started source, state, generation
counter, stream continuation, one `finalizationTask`, one shared
`cancellationTask`, a `SourceTerminalization` state, cancellation/terminal
state, injected `DictationClock`, and `DictationProcessingBudget`. At `begin`,
it records no deadline. At `finish`, the session installs exactly one
finalization task; later callers await that same task. It first returns the
existing task when present, then guards `isCancelled`, `isTerminal`, and
`cancellationTask == nil` before creating a new task, so a finish that began
before cancellation shares the terminal task while cancel-before-finish cannot
start new work. On the first accepted public `finish()` call, before storing or
awaiting the task and before `source.finish()`, it synchronously records
`stopInstant = clock.now()`, constructs
`insertionDeadline = stopInstant.advanced(by: budget.insertion)`, and passes
the resulting absolute deadline to:

~~~swift
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
`min(stopInstant + budget.cleanup, insertionDeadline)` (1,500 ms and 3,000 ms
from the same stop boundary in production). `finalizeBody(deadline:)` calls
`source.finish()` exactly once and records `.finished` whether that source
operation returns text or throws; source-finalization latency therefore consumes
the remaining insertion budget and cannot reset either deadline. If cancellation
already claimed `.cancelled`, it does not claim a second logical
terminalization. The production source's `finish()` owns its
physical release. Each provisional callback
increments generation and publishes only an accepted `StreamingTranscriptState`
update. `finish` calls source `finish()` exactly once, checks cancellation
immediately after that await and again before interpreting nil or publishing
any terminal result, resolves the dictionary before creating the request, and
never calls the legacy cleaner. A cleaned candidate publishes
`cleanedTranscript`; every unsafe/unavailable cleanup publishes `insertedText`
equal to the exact baseline. A resolver failure publishes raw ASR recovery
with no cleaner call.
On every `cancel()` call, the method first checks for and awaits an existing
`cancellationTask`; it checks `isTerminal` only when no cancellation task is
stored. This prevents a concurrent caller from returning merely because an
unblocked finish marked the session terminal while the first cancellation
caller still drains cleanup. Only the cancellation winner changes
`isCancelled`, the generation, and the update continuation synchronously; the
test-only `onCancellationInvalidated` callback records that boundary. The
method then creates and stores a `Task<Void, Never>` in `cancellationTask`
without an intervening await. That shared task cancels the finalization task
first so `Task.isCancelled` is visible, then claims `.cancelled` and calls the
sole source's `cancel()` early enough to unblock an in-flight source `finish`,
and awaits finalization and cleaner drain. Production `cancel()` owns the
physical release; the session does not call `releaseResources()` again.
Later independent concurrent callers find the stored handle before terminal
state and await its value; they never return early. The test-only
`onCancellationDrained` callback records completion after finalization and the
cleaner's bounded helper acknowledgement/force-termination path, immediately
before terminal marking. The awaited task propagates caller cancellation
into `IncrementalTranscriptCleaner`, so its helper acknowledgement or
force-termination completes before terminal cancellation returns. No final
result, noSpeech error, or update can publish after that boundary.
`runFinalization` checks cancellation before marking and returning a terminal
result; it marks the terminal state on both success and thrown terminal error
and does not call `source.releaseResources()` after `source.finish()`. A source probe models the
Apple contract with idempotent physical terminalization: successful or failed
finish produces one physical release, cancellation produces one physical
release, and an in-flight finish/cancel unblock does not increment it twice.
The successful and failed finish tests emit a late provisional callback and
assert no update appears. The blocked nil-finish test asserts cancellation wins
instead of `StreamingDictationProcessorError.noSpeech`, both shared-task
callers return only after drain, and no update or insertion occurs. A
deterministic race test waits for the invalidation callback before scheduling
`finish()`, then proves source `finish` never starts after cancellation wins.

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
! rg -n 'AVAudioEngine|installTap|SFSpeechRecognizer|SpeechAnalyzer|URLSession|FileHandle|Data\.write' Sources/FleckApp/AppleSpeechStreamingAdapter.swift Sources/FleckApp/FoundationModelCleanupGenerator.swift Sources/FleckApp/StreamingDictationProcessor.swift Sources/FleckApp/FoundationModelDictation.swift
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
    Sources/FleckApp/FoundationModelDictation.swift \
    Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift \
    Tests/FleckAppTests/FoundationModelCleanupGeneratorTests.swift \
    Tests/FleckAppTests/StreamingDictationProcessorTests.swift \
    Tests/FleckAppTests/FoundationModelDictationTests.swift \
  | sort -u
)"
git add Sources/FleckApp/AppleSpeechStreamingAdapter.swift Sources/FleckApp/FoundationModelCleanupGenerator.swift Sources/FleckApp/StreamingDictationProcessor.swift Sources/FleckApp/FoundationModelDictation.swift Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift Tests/FleckAppTests/FoundationModelCleanupGeneratorTests.swift Tests/FleckAppTests/StreamingDictationProcessorTests.swift Tests/FleckAppTests/FoundationModelDictationTests.swift
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
import Foundation
import Testing

@testable import FleckApp

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
  case finishStarted
  case sessionCancel
  case sourceCancel
  case sourcePhysicalRelease
  case finishUnblocked
  case sessionDrain
  case coordinatorCancelReturned
}

@MainActor
final class CancellationOrderRecorder {
  private(set) var values: [CancellationEvent] = []
  func append(_ event: CancellationEvent) { values.append(event) }
}

// ProcessingProbe's callbacks are test-only hooks from its owned session and
// source probes; Fixture(onFocusedEditorRollback:) records the existing
// FocusedDictationEditing.cancelFocusedDictation() restoration call.
// For the blocked-finish case the same probe exposes
// `finishBlocksUntilCancel`, `waitUntilFinishStarted()`, `onFinishUnblocked`,
// `onSessionDrain`, and `publishedUpdates`. The Fixture exposes the existing
// history probe as `historyStore.records`; these are test-only observations,
// not production coordinator state.

@Test @MainActor
func cancellationRollsBackFocusedEditorBeforeSessionAndSourceCancel() async throws {
  let order = CancellationOrderRecorder()
  let processing = ProcessingProbe(
    onSessionCancel: { order.append(.sessionCancel) },
    onSourceCancel: { order.append(.sourceCancel) },
    onSourcePhysicalRelease: { order.append(.sourcePhysicalRelease) }
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
    .sourcePhysicalRelease
  ])
  #expect(fixture.editor.committedTexts.isEmpty)
  #expect(fixture.saver.savedTexts.isEmpty)
}

@Test @MainActor
func cancellingEnhancedCaptureDuringBlockedFinishRollsBackBeforeSessionCancelAndDrains() async throws {
  let order = CancellationOrderRecorder()
  let processing = ProcessingProbe(
    finishBlocksUntilCancel: true,
    onFinishStarted: { order.append(.finishStarted) },
    onSessionCancel: { order.append(.sessionCancel) },
    onSourceCancel: { order.append(.sourceCancel) },
    onSourcePhysicalRelease: { order.append(.sourcePhysicalRelease) },
    onFinishUnblocked: { order.append(.finishUnblocked) },
    onSessionDrain: { order.append(.sessionDrain) }
  )
  let fixture = try Fixture(
    processing: processing,
    onFocusedEditorRollback: { order.append(.focusedEditorRollback) }
  )
  await fixture.coordinator.start(mode: .focused, editor: fixture.editor)

  let finishTask = Task { await fixture.coordinator.finish() }
  await processing.waitUntilFinishStarted()
  let cancelTask = Task {
    await fixture.coordinator.cancel()
    order.append(.coordinatorCancelReturned)
  }
  await cancelTask.value
  await finishTask.value

  #expect(order.values.firstIndex(of: .focusedEditorRollback)!
    < order.values.firstIndex(of: .sessionCancel)!)
  #expect(order.values.firstIndex(of: .sessionCancel)!
    < order.values.firstIndex(of: .sourceCancel)!)
  #expect(order.values.firstIndex(of: .sourceCancel)!
    < order.values.firstIndex(of: .finishUnblocked)!)
  #expect(order.values.firstIndex(of: .sessionDrain)!
    < order.values.firstIndex(of: .coordinatorCancelReturned)!)
  #expect(order.values.filter { $0 == .sourceCancel }.count == 1)
  #expect(order.values.filter { $0 == .sourcePhysicalRelease }.count == 1)
  #expect(fixture.editor.provisionalTexts.isEmpty)
  #expect(fixture.editor.committedTexts.isEmpty)
  #expect(fixture.saver.savedTexts.isEmpty)
  #expect(fixture.historyStore.records.isEmpty)
  #expect(processing.publishedUpdates.isEmpty)
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

The capture record stores its current generation, `isFinishing` state, and, for
the incremental path, the owned `DictationProcessingSession`. The cancellation
path is ordered explicitly. A capture with a processing session remains
cancellable while `isFinishing` is true; returning early in that state would
leave a blocked source `finish()` unable to receive the session's cancellation.
The legacy guard remains only for a finishing capture with no processing session,
because that branch has no cancellable finalization owner:

~~~swift
private func cancelActiveCapture(_ id: UUID) async {
  guard var capture, capture.id == id, !capture.cancelRequested else { return }
  guard !capture.isFinishing || capture.processingSession != nil else {
    return // legacy finalization has no cancellable processing-session owner
  }
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

On finish, set `capture.isFinishing = true` before awaiting the processing
session's result. On the enhanced path, `cancelActiveCapture` still enters
while that flag is set, invalidates the generation and stops updates, rolls
back the focused editor transaction, and awaits the session's cancellation;
the session cancellation unblocks a blocked source `finish()`. On the legacy
path, the existing finishing guard remains in force because the engine branch
does not own the incremental finalization task. On a successful finish, cancel
and await the update task, await one processor result, repeat
all guards, create/update the existing history record, and pass only
`result.insertedText` to focused commit or existing Smart Capture routing. Do
not call legacy `cleaner.clean` on this branch. At cancellation start, mark the
capture cancelled and invalidate its generation first; restore the focused
editor transaction second through `rollbackEditor` (which calls
`cancelFocusedDictation()` when no commit receipt exists); only then await
processing-session `cancel()`. That session owns finalization cancellation and
source terminalization; when finalization is in flight, the session calls its
source `cancel()` before awaiting finalization so Apple Speech cancel releases
the session and unblocks finish. The coordinator publishes `.cancelled` only
after that await and publishes nothing from a late task. The existing order
test covers an idle enhanced capture; the blocked-finish coordinator test uses
`ProcessingProbe(finishBlocksUntilCancel: true)`, waits for the processing
session's finish-start signal, then cancels. It asserts rollback before session
and source cancellation, one source terminal call/release, finish unblocking,
session drain before coordinator cancel returns, and empty provisional,
insertion, history, save, and late-update probes.

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

## Final real-app verification handoff

Workstream B does not build or switch the separate real checkout. After Task 5
parent verification and a fresh Sol `ship`, Workstream C owns the final root
snapshot/branch/ancestry checkpoint, the serialized SwiftPM run,
`./Scripts/build-fleck-app.sh`, and the exact
`/Users/harryjin/Fleck/.build/Fleck.app` launch. The C checkpoint preserves the
sole dirty root `AGENTS.md` byte-for-byte and aborts before packaging on any
branch, accepted-SHA, unmerged-state, or extra-dirty-file mismatch.

The operator then grants Microphone and Speech Recognition permissions, focuses
a Fleck note, holds the existing dictation shortcut, and speaks a known
sentence containing a filler, immediate repetition, a name/number/path, and
punctuation. Record the observed provisional display, stable prefix, final
insertion, and protected-content result. Cancel a second capture and record
that no text or history entry appeared. Automated tests and a launched process
do not constitute speech output evidence; the primary may launch the app but
must not fabricate microphone words or cleanup results.

## Authority boundary

This workstream authorizes only its file map. Each numbered task has separate
ownership and a separate ship gate. It does not authorize Settings or
installer work, model downloads, candidate enablement, package changes, a
second Apple audio path, push, PR, merge, or release admission.
