# Fleck Local Dictation Real-App Vertical Slice Design

**Date:** 2026-08-16

**Status:** Settled architecture for a bounded implementation stack; no custom
model is selected or release-admitted.

**Starting base:** `4212314398853091fa85e7aec18318b9650e8604` with accepted
cleanup commits `7ca58fd8dfdf9ed1d0332c093ef7f9eb36e274b5` and
`4212314398853091fa85e7aec18318b9650e8604`.

**Purpose:** Take the accepted faithful-cleanup base to a development
`Fleck.app` that can be launched and exercised with a real microphone through
Apple on-device Speech, while keeping custom model installation production-shaped,
empty by default, and verified only with fakes and fixtures.

## Scope and truth boundary

The product truth for this milestone is Apple Speech for recognition and Apple
Foundation Models cleanup where supported, with deterministic cleanup as the
existing safe fallback. No Qwen, Whisper, Nemotron/Parakeet, or Qwen cleanup
candidate is a production winner. The existing FluidInference Parakeet v2 Core
ML manifest is experimental English-only evidence, not a selected model and not
release evidence.

| Boundary | What is true | What the implementation may claim |
| --- | --- | --- |
| Implemented at the starting base | `CleanupLexeme`, `CleanupProtectedSpan`, `AppleSpeechCapture`, existing coordinator transaction behavior, existing Foundation Model/deterministic cleanup controls, and compile-gated model-manager plumbing exist. | These are existing seams and evidence inputs. |
| Integrated by Task 0 and the three dependency-ordered workstreams | Personal-dictionary resolution core; faithful validation and bounded cleanup; one coordinator-owned streaming path around the existing `SpeechEngine`; dictionary-before-cleanup finalization; live stable-prefix/mutable-tail display; fail-closed insertion; catalog-driven installer presentation. | The development app can exercise the local Apple path. |
| Packaged-tested | Serialized offline-safe SwiftPM tests, the existing `Scripts/build-fleck-app.sh` path, and a launched development bundle from the real checkout. | Build and launch are directly evidenced; tests use no model weights. |
| Release-admitted | Nothing custom. A signed configuration, exact identity, local calibration, signed-app checks, and a fresh Sol `ship` review are still required for any custom candidate. | The ordinary release remains Apple Speech plus deterministic/Apple cleanup. |

The starting base does not contain `PersonalDictionaryResolution` or
`PersonalDictionaryResolver`. Dependency-first Task 0 ports exactly
`Sources/FleckCore/PersonalDictionary.swift`,
`Sources/FleckCore/PersonalDictionaryResolver.swift`,
`Tests/FleckCoreTests/PersonalDictionaryTests.swift`, and
`Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift` from final
published `898ceae`, including the `6bd6df8`, `5148ef1`, and `27f7a44`
evolution. It contains the exact `baseline`, `protectedForms`, and
`replacements` consumed by cleanup. Codec, store, UI, evaluation, and
candidate-adapter files are not part of Task 0.

## Approaches considered

### Recommended: evidence-gated vertical slice

Task 0 first restores the accepted personal-dictionary resolution core.
Workstream A then adds only `FaithfulCleanupValidator` and
`IncrementalTranscriptCleaner` as two separately reviewed tasks on top of the
accepted lexeme/span and Task 0 base. Workstream B restores the small
`DictationProcessing` seam, stable transcript state, runtime policy, and
processor, then wraps the existing `AppleSpeechCapture` as the sole live speech
source. Workstream C presents an empty-by-default admitted-model catalog,
reuses the existing manager/downloader behind injected fakes, packages the app,
and separates automated evidence from the operator's microphone observation.

This order proves safety before integration, proves the real app before any
candidate enablement, keeps failures attributable, and requires no model-weight
download. It also preserves a later benchmark/admission lane without allowing
benchmark names to become routing authority.

### Rejected: installer-first

Starting with download, Settings, or model lifecycle would make a polished
installer appear complete while Apple Speech capture, cancellation, dictionary
ordering, and insertion remained unproven. It would also encourage wiring the
experimental Parakeet manifest into normal behavior and make a successful fake
download look like recognition evidence. Installer presentation follows the live
safe path so its fallback and error states are grounded in a usable application.

### Rejected: direct candidate enablement

Selecting Qwen, Whisper, Nemotron/Parakeet, or a Qwen cleanup model before the
candidate evidence and signed-app gate would turn an evaluation shortlist into a
release decision. It would broaden runtime, package, licensing, memory, and
network risk, and could regress the Apple fallback that is the current production
truth. Candidate adapters remain a later admission workstream with exact identity,
benchmark evidence, calibration, and signed-app verification.

## Architecture

```text
GlobalHoldShortcut
        |
        v
DictationCoordinator  (capture transaction, generation, history, routing, insertion)
   |                         |
   | legacy capture          | incremental capture, never both in one capture
   v                         v
SpeechEngine             DictationProcessing
   |                         |
   |                         v
AppleSpeechCapture     StreamingDictationProcessor
   |                         |                 |
   | on-device only         |                 +--> StreamingTranscriptState
   |                         |                 +--> PersonalDictionaryResolution
   |                         |                 +--> IncrementalTranscriptCleaner
   |                         |                 +--> LocalDictationRuntime signals
   |                         v
   +------------------ AppleSpeechStreamingAdapter

FoundationModelDictation --> FoundationModelCleanupGenerator --> validator seam
EnhancedModelManager -----> admitted installer adapter only; no ordinary-release route
SettingsView -------------> admitted recommendation presentation, not model selection
```

### Ownership by module

| Module | Owns | Does not own |
| --- | --- | --- |
| `AppleSpeechCapture` | The existing `AVAudioEngine`/Speech framework session, permission request, on-device requirement, provisional/final callbacks, interruption, and source-owned terminal release. Its `finish()` and `cancel()` release the underlying `AppleSpeechSession` before returning and are idempotent at the session boundary. | Dictionary resolution, cleanup, routing, history, UI, or model downloads. |
| `AppleSpeechStreamingAdapter` | Adapting the already-created `SpeechEngine` callback/final interface to the processor seam; `finish()` and `cancel()` are direct forwards and do not construct `AppleSpeechCapture` or add a second physical release. | A second audio tap, microphone session, network fallback, or model choice. |
| `DictationProcessing` / `StreamingDictationProcessor` | One incremental capture session's transcript updates, dictionary-before-cleanup final artifacts, and bounded cleanup decision. | Shortcut identity, note persistence, routing policy, or UI ownership. |
| `StreamingTranscriptState` | Generation ordering, append-only stable prefix, and a mutable tail capped by the newest two clauses or 80 `CleanupLexeme` lexical units. | Semantic cleanup or insertion. |
| `FaithfulCleanupValidator` | The deterministic allowlist and protected-meaning decision. | Generating text, choosing a model, or logging transcript data. |
| `IncrementalTranscriptCleaner` | One bounded cleanup request, one generation attempt, deadline/cancellation race, validation, exact baseline fallback, and session-box publication gate. | Dictionary resolution, audio, runtime residency, or UI. |
| `FoundationModelDictation` / `FoundationModelCleanupGenerator` | The existing Apple Foundation Models/deterministic control and its bounded incremental wrapper. An inspectable responder seam carries `GenerationOptions(maximumResponseTokens:)` into the one production `respond` request. | Retries, cloud fallback, or a second generation request. |
| `LocalDictationRuntime` | Restored active/warm/standby/cold policy, one lease, lifecycle signals, scheduler, and future adapter health. | The Apple audio capture path and installer UI. |
| `EnhancedModelManager` | Existing compile-gated manifest, download, checksum, repair, update, and remove transactions when an admitted configuration exists. | Selecting a model, normal-release routing, or a second downloader. |
| `AdmittedModelCatalog` and settings presentation | One signed configuration's exact identity and one automatic recommendation, or the built-in state. | A model picker, Advanced selector, inference, or model weights. |
| `DictationCoordinator` | Capture identity, pipeline choice, cancellation generation, provisional editor transaction, history, routing, insertion, recovery, and user-visible phase. | Recognition internals, cleanup policy, download transport, or transcript diagnostics. |

### Coordinator seam

The external processing seam is deliberately small and compatible with the
restored lineage:

```swift
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

protocol TranscriptDictionaryResolving: Sendable {
  func resolve(_ rawTranscript: String) async throws -> PersonalDictionaryResolution
}

struct DictationTextUpdate: Equatable, Sendable {
  let generation: UInt64
  let stableText: String
  let provisionalTail: String

  var displayText: String { stableText + provisionalTail }
}

struct DictationProcessingResult: Equatable, Sendable {
  let rawTranscript: String
  let dictionaryBaseline: String?
  let cleanedTranscript: String?
  let insertedText: String
  let cleanupOutcome: DictationCleanupOutcome
  let measurements: DictationRuntimeMeasurements
}
```

`StreamingSpeechSource` is an adapter protocol over the existing
`SpeechEngine`. `AppleSpeechStreamingAdapter` receives the already-created
`SpeechEngine` from `DictationSpeechEngineProvider` and forwards its
provisional/final/level/finish/cancel/release interface; it never constructs
`AppleSpeechCapture`, installs another tap, or creates another audio engine.
`finish()` and `cancel()` are source-owned terminal operations: the current
`AppleSpeechCapture` releases its underlying `AppleSpeechSession` before either
returns, and repeated terminal calls are idempotent. `releaseResources()` is
only the pre-start cleanup hook for this streaming session, not a second
physical release after finish/cancel. The processor awaits the source factory,
starts this one source exactly once with both callbacks, and passes the
already-started source to a synchronous session initializer; a start failure
releases the source before rethrowing. The legacy
coordinator path continues to call `SpeechEngine.start` and `finish`
directly when the incremental processor is not selected. A capture is either
that legacy path or a `DictationProcessingSession`, never both.

`DictationProcessingResult.dictionaryBaseline == nil` means dictionary
resolution failed before a trusted baseline existed. In that case
`insertedText == rawTranscript`, the coordinator records the raw-ASR recovery
path, and no cleanup request is made. When a baseline exists, every unsafe,
unavailable, late, malformed, overlong, cancelled-by-helper, or validator-
rejected cleanup attempt selects exactly `PersonalDictionaryResolution.baseline`.

## End-to-end data flow

1. The shortcut reserves a UUID capture generation in `DictationCoordinator`.
   Focused mode begins the editor transaction before speech starts; Smart Capture
   reserves only the final save transaction.
2. The coordinator chooses one pipeline. The incremental path calls
   `DictationProcessing.begin`; its source factory receives the already-created
   `SpeechEngine` from `DictationSpeechEngineProvider` and wraps it in one
   `AppleSpeechStreamingAdapter`. The existing engine owns the one
   `AppleSpeechCapture` path.
3. `AppleSpeechCapture` requests microphone and Speech Recognition access and
   refuses to start unless on-device recognition is supported. Legacy Speech
   requests set `requiresOnDeviceRecognition = true`; the modern Speech path
   must report unavailable when its locale/device cannot provide on-device
   recognition. No network fallback is permitted.
4. Provisional strings flow through the adapter into
   `StreamingTranscriptState`. Accepted updates have strictly increasing
   generations. The state publishes `stableText + provisionalTail`; stable text
   only grows, and the mutable tail contains no more than the newest two clauses
   and 80 `CleanupLexeme` lexical units; `.?!。！？` terminators count without
   requiring following whitespace. With no terminator the whole string remains
   mutable; with one terminator the boundary is after that terminator; with two
   it is after the first; and with three it is after the second. Immediately
   following whitespace is consumed into stable text.
5. In focused mode the coordinator accepts only the active capture generation
   and calls `FocusedDictationEditing.updateFocusedDictation(provisionalText:)`.
   Smart Capture may expose levels/status but does not insert provisional text.
6. On stop, the processing session's first accepted public `finish()` entry
   synchronously records `stopInstant` before creating or awaiting
   finalization and before calling `source.finish()`. It creates
   `insertionDeadline = stopInstant + 3,000 ms`; source-finalization latency
   consumes that absolute stop-to-insertion budget. After the source returns,
   it resolves the personal dictionary before constructing
   `IncrementalCleanupRequest` and gives cleanup the absolute
   `min(stopInstant + 1,500 ms, insertionDeadline)` deadline, never a reset
   clock based on source-finalization completion.
7. `IncrementalTranscriptCleaner` performs at most one bounded generation.
   `FaithfulCleanupValidator` compares the candidate with the dictionary
   baseline and protected spans. A valid candidate becomes `cleanedTranscript`;
   every other valid-capture cleanup outcome inserts the exact baseline.
   When the Apple Foundation Models control is available, the caller's
   `maximumOutputTokens` reaches `GenerationOptions(maximumResponseTokens:)`
   in its one `respond` call; otherwise the deterministic fallback remains in
   place.
8. The processor returns one final artifact to the coordinator. The coordinator
   updates history, routes Smart Capture, commits focused insertion, or exposes
   the existing recovery action. It never calls the legacy `TranscriptCleaning`
   path for the same incremental capture.
9. The coordinator publishes terminal UI state only after its generation check.
   Late processing, cleanup, route, save, or installer events cannot mutate the
   editor, history, route, insertion, or terminal dictation state.

### Exact cleanup allowlist

Automatic cleanup may change only punctuation, capitalization, whitespace,
isolated unambiguous fillers, immediate exact repetition, an explicitly spoken
same-tail correction, and short-list formatting without changing list items.
Personal-dictionary replacements are already represented by the baseline and
are not re-invented by cleanup.

The validator rejects any protected-meaning change involving names and
dictionary forms, numbers and number words, dates and times, prices, units and
quantities, recipients and destinations, paths, URLs, email addresses, code,
commands, negation, modality, commitments, quotes, mixed English/Mandarin order,
lexical insertion, lexical substitution, reordering, or an ambiguous correction.
It classifies supported English cardinal/ordinal number words through trillion,
fractions, decimals, percentages, currencies, and unit quantities before
filler, repetition, or correction recognition; the ordered number signature
must remain identical, and ambiguous or unrecognized numeric/quantity-looking
forms fail closed. Short-list formatting may ignore only paired validated
ordinal marker positions; it never bypasses a quantity change inside an item.
Digit ordinals are recognized from raw `CleanupLexeme` sequences: an adjacent
digit lexeme plus suffix word is one full-token `[0-9]+(st|nd|rd|th)` signature
only when the suffix is semantic (`11th`, `12th`, `13th`, and otherwise
`1st`/`2nd`/`3rd`/`4th` endings). Thus `21st` is protected exactly, while
`11st`, `21th`, and malformed `21stx` fail closed; ordinary words ending in
`st`, `nd`, `rd`, or `th` remain ordinary words. Currency, percentage,
fraction, time, signed, parenthesized, decimal, and bounded unit forms use a
parser mirroring `CleanupLexeme.numberEnd`: optional parenthesis, sign, any
Unicode currency symbol, optional second sign after that currency, digits and
separators, one trailing percent/currency character, closing parenthesis, and
`am`/`pm`. The exact canonical form is retained, so `$-20`, `(-$20)`, and
`₹20` cannot lose or change their sign, currency, or parentheses. The complete
raw sign/currency/separator context that `CleanupLexeme` detached is also
retained.
Removing a detached or doubled affix therefore changes the numeric signature; a
trailing detached sign/currency is ambiguous, while a hyphen without a numeric
raw neighbor remains ordinary punctuation. Balanced parentheses and
complete separators/affixes are required, so `pay - 20`, `pay :20`, `pay : 20`,
`pay %20`, and `pay % 20` cannot become `Pay 20.`; `20-` cannot lose its
trailing sign; and split/doubled `$`/`+`/`-` forms cannot lose one affix.
Unsupported digit-bearing sequences are ambiguous. A list exception validates the ordered pairs `first -> 1` through
`fifth -> 5`, removes only the full raw marker ranges for its remainder check,
and passes only the exact candidate number ranges to protected-span comparison.
Inter-marker whitespace/punctuation does not change those raw coordinates;
swapped markers and item quantities remain protected. Only those paired ordinal
markers may be introduced by the short-list formatting rule.
The transcript is quoted data, never instructions.

## Cancellation and generations

`DictationCoordinator` is the transaction owner. It increments an invalidation
generation before editor rollback and before asking the selected pipeline to
cancel. Every callback carries or closes over the capture UUID and is ignored
unless all of these remain true: the UUID is active, the generation is current,
the capture is not cancelling/terminating, and the pipeline is still accepting
updates.

The selected `DictationProcessingSession` owns one finalization task and one
shared `cancellationTask`. `finish()` installs finalization exactly once. The
first actor-isolated `cancel()` turn marks cancellation, invalidates the
generation, and closes updates synchronously before creating and storing the
shared task. `finish()` rejects if that invalidated state or a shared
`cancellationTask` already exists when no finalization task is already shared;
finish callers that entered first await that existing task. If the sole speech
source's `finish()` is still blocked, the shared task calls `cancel()` early
enough to unblock it, then cancels and awaits finalization and the cleaner's
bounded helper acknowledgement or force-termination path. If `finish()` has
already completed, its source-owned physical release and logical `.finished`
state are already recorded; cancellation makes zero second source-terminal
calls and only drains finalization/cleanup. In production,
`AppleSpeechCapture.finish()` and `cancel()` each release the underlying Apple
Speech session before returning, and the adapter forwards those operations
without adding a physical release. Every independent concurrent caller awaits
that same task before returning.
Concurrent finish callers await the same existing task; if cancellation wins
before any finish task exists, the cancellation guard prevents new finalization
work from starting. The processor test records the synchronous invalidation
boundary, schedules `finish()` only after that event, and asserts that neither
finalization nor source `finish()` starts; the separate source-blocking test
proves early source cancellation unblocks an already-running finish.

The cancellation evidence is phase-specific. A blocked-finish test records
source cancellation and physical release: cancellation wins, releases once,
unblocks the source continuation, and returns only after the shared task drains;
there is no completed finish result or update. A cleanup-phase test waits until
`finish()` has completed and recorded physical release, then blocks the helper;
session cancellation makes zero second source-terminal calls, awaits helper
acknowledgement or force termination, and returns only after that acknowledgement.
Its assertions do not require `cancel` to precede physical release. A separate
concurrent blocked-finish test holds the first source-cancel callback until a
second caller enters, proving both callers await one shared cancellation task.
No result or update may publish in either phase.

`StreamingSpeechSource.cancel()` and `releaseResources()` must not synchronously
await the owning session's `cancel()` from a dependency callback. They may
record state or issue an independent notification, but the cancellation tests
cover independent concurrent callers only; source cancellation still occurs
early enough to unblock an in-flight speech `finish()`.

Cancellation must execute in this order:

1. mark the capture cancelled and invalidate its generation;
2. restore the focused editor's exact pre-capture transaction;
3. await processing-session cancellation, which synchronously closes updates;
   if source finish is still in flight, it calls the selected speech source's
   `cancel()` early enough to unblock finish, otherwise it makes no second
   source-terminal call, then cancels/awaits finalization and helper drain;
4. erase provisional transcript and in-memory audio buffers;
5. remove provisional history work and release runtime scratch state;
6. publish only `.cancelled` after the session's bounded helper
   acknowledgement/force-termination path has completed and no active work can
   publish.

`DictationCoordinator` does not use `isFinishing` as a blanket cancellation
guard. An enhanced capture that owns a `processingSession` remains cancellable
while its session is finishing; otherwise a blocked Apple Speech
`source.finish()` could never receive the session cancellation that unblocks
it. The legacy finishing guard remains only when no processing session exists.
The coordinator integration test starts a blocked processing-session finish,
waits for its start signal, cancels, and proves focused-editor rollback precedes
session/source cancellation, the finish unblocks, session drain precedes cancel
return, and no provisional update, insertion, history mutation, save, or late
result occurs.

`StreamingDictationSession` also owns terminal state for non-cancellation paths.
Its one finalization task marks terminal after both successful result and
thrown source, dictionary, or cleanup error. `source.finish()` owns the
physical release on those paths; the session records `.finished` exactly once
and does not call `releaseResources()` afterward. The cancellation task claims
`.cancelled`, calls source `cancel()` early only for an in-flight Apple Speech
finish, then awaits finalization and helper drain. The terminal guard closes
the update stream before any terminal return, so callbacks arriving after
success, failure, or cancellation cannot publish.

After cancellation, no update, final result, history mutation, route, insertion,
or recovery receipt may publish. A caller cancellation of the cleanup task throws
`CancellationError`; a deadline or helper-request cancellation during an otherwise
valid capture returns a baseline decision. These are distinct from a dictionary
failure before a baseline, which remains raw-ASR recovery.

The Apple Foundation Models cleanup adapter implements all four
`CleanupGenerationSession` methods. Because in-process model work cannot promise
true force termination, its detachable underlying operation is behind a locked
publication gate: cancellation or force termination closes the gate and
acknowledges immediately, while any late candidate is rejected and cannot keep
the cleaner's structured children waiting. The architecture claims bounded
publication and drain, not that the underlying model computation was killed.

## Runtime, privacy, and network rules

The restored `LocalDictationRuntime` remains a small lifecycle seam with active,
warm, standby (hibernating), and cold (unloaded) states, one capture lease,
priority for live/final ASR over automatic cleanup, and memory/thermal/sleep/
update signals. The Apple
vertical slice does not load custom weights and does not make runtime residency
evidence for a candidate. Runtime fakes prove lease and cancellation ordering;
later admitted adapters may use the seam only after a signed configuration exists.

The following are hard boundaries:

- Apple Speech and Foundation Models execute on-device only. Recognition must
  fail closed when on-device support is absent for the requested locale/device.
- There is no cloud transcription, transcript upload, hidden network fallback,
  audio persistence, transcript logging, history diagnostics containing text, or
  model-driven routing authority.
- Normal application use works with no custom model installed and when an
  install, verification, startup, calibration, repair, update, or removal fails.
- Network is used only by an explicit user install/repair/update operation after
  a signed admitted descriptor is available. All workstream tests inject a fake
  downloader and tiny checksum fixtures; these plans do not download model
  weights or bundle them.
- The existing compile-gated `EnhancedModelManager` and its manifest/download/
  verify/repair/update/remove implementation are reused where admitted. No
  second downloader is introduced.
- Model identity, installer phase, progress, and errors are state, not inferred
  from a spinner or from a successful `download()` return.

## Custom-model catalog and settings behavior

An admitted descriptor is the smallest generic identity shared by the ASR and
cleanup roles. It includes:

```swift
enum AdmittedModelRole: Codable, Equatable, Sendable {
  case asr
  case cleanup
}

struct AdmittedModelFile: Codable, Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

struct RawAdmittedModelDescriptor: Codable, Equatable, Sendable {
  let role: AdmittedModelRole
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let license: String
  let notices: String
  let source: URL
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let languages: [String]
  let architectures: [String]
}

struct AdmittedModelDescriptor: Equatable, Sendable {
  let role: AdmittedModelRole
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let license: String
  let notices: String
  let source: URL
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let languages: [String]
  let architectures: [String]
  let requiredCapacityBytes: Int64

  var immutableIdentity: AdmittedModelImmutableIdentity { get }
  private init(
    role: AdmittedModelRole,
    modelID: String,
    revision: String,
    runtimeABI: String,
    conversion: String,
    quantization: String,
    license: String,
    notices: String,
    source: URL,
    files: [AdmittedModelFile],
    downloadBytes: Int64,
    installedBytes: Int64,
    languages: [String],
    architectures: [String],
    requiredCapacityBytes: Int64
  )
  init(validating raw: RawAdmittedModelDescriptor) throws
}

struct AdmittedModelImmutableIdentity: Equatable, Sendable {
  let sourceRepository: URL
  let modelID: String
  let revision: String
  let license: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let requiredCapacityBytes: Int64
}

struct AdmittedModelHardwareProfile: Equatable, Sendable {
  let architecture: String
  let requestedLanguages: Set<String>
  let availableBytes: Int64
}

enum AdmittedModelDescriptorError: Error, Equatable, Sendable {
  case emptyIdentity
  case emptyRevision
  case emptyRuntimeABI
  case emptyConversion
  case emptyQuantization
  case emptyLicense
  case invalidSource
  case unsafePath(String)
  case duplicateFilePath(String)
  case invalidByteCount
  case invalidChecksum(String)
  case aggregateMismatch
  case requiredCapacityOverflow
  case fileAggregateOverflow
  case emptySupport
}

enum AdmittedModelPathError: Error, Equatable, Sendable {
  case unsafePath(String)
  case duplicatePath(String)
}

enum AdmittedModelPathRules {
  static func canonicalize(_ rawPath: String) throws -> String
  static func canonicalizeUnique(_ rawPaths: [String]) throws -> [String]
}
```

The signed boundary decodes into `RawAdmittedModelDescriptor` and constructs the
validated `AdmittedModelDescriptor` through a throwing initializer that stores
canonical trimmed identity/revision/runtime ABI/conversion/quantization/license
values, rejects empty fields, and accepts only an absolute safe HTTPS
source-repository URL with a host and no credentials, fragment, traversal, or
query. It applies bounded repeated percent-decoding to the repository path and
rejects double-encoded traversal before accepting the source. It also rejects
empty/absolute file paths, `.`, `..`, empty path components, dot components,
backslashes, encoded traversal, duplicate normalized paths, invalid sizes or checksums, aggregate
mismatches, `Int64.addingReportingOverflow` when deriving required staging
capacity, and empty support sets. An installed-plus-download overflow rejects
with `AdmittedModelDescriptorError.requiredCapacityOverflow`; a distinct
per-file aggregate checked-add overflow rejects with
`AdmittedModelDescriptorError.fileAggregateOverflow`. The validated descriptor
stores the checked `requiredCapacityBytes` and has no accessible memberwise
initializer; invalid raw input is rejected before the value can be observed.
`AdmittedModelPathRules.canonicalizeUnique` is also called by the manager's
manifest validation and by `remoteURL`; it performs the same bounded repeated
percent-decoding, rejects any path whose decoded canonical value differs from
its raw value or leaves encoding behind, and rejects the same unsafe and
duplicate canonical paths before URL construction or transport.
The existing
compile-gated manager builds or receives one immutable
`EnhancedModelArtifactIdentity` alongside its `EnhancedModelManifest`; its
source repository and revision derive every `remoteURL`. The admitted installer
compares the descriptor's immutable identity with that artifact identity and the
artifact identity with the actual manifest identity before any manager operation;
descriptor/artifact or artifact/manifest mismatch rejects before transport. The
existing manifest path/revision checks and `?download=true` URL query remain
authoritative. This is a small seam, not a generic multi-model registry.
The existing `DictationModelCapability(modelRootURL:)` and
`DictationModelCapability(modelRootURL:candidateEnabled:architectureProvider:)`
calls remain source-compatible through compile-gated manager convenience
overloads. They retain the live available-capacity calculation and arm64
detection defaults, while tests may inject explicit providers. The compatibility
overloads accept no optional custom manifest: they always pair the exact
embedded experimental Parakeet manifest with its matching compatibility identity.
Any custom manifest must use the designated manager initializer with an explicit
artifact identity. That route does not create an admitted descriptor,
recommendation, or installer. An explicit signed configuration must still
provide its own already-created manager and pass binding before any operation. It also carries
one `AdmittedModelHardwareProfile`; the C3 factory constructs
`AdmittedModelCatalog(signedDescriptor:hardware:)` after descriptor validation
and before `EnhancedModelManagerInstaller`. It continues only when the catalog
returns `.recommended(theSameDescriptor)`. Architecture mismatch, language
mismatch, or available capacity below the validated staging requirement returns
a non-operating built-in/failure presentation with zero transport calls.

The signed app supplies either no descriptor or exactly one hardware-appropriate
recommendation for the curated experience; the factory never silently surfaces
an unsupported descriptor. Ordinary release configuration is empty, so the
normal Dictation settings surface shows the built-in Apple state:
“Apple Speech — Built in”, “On-device recognition”, and “No custom model is
installed.” There is no model picker and no Advanced selector. A recommendation
surface, when an admitted descriptor exists, has one explicit `Install` action
and shows exact identity, revision, license, checksums, download/installed size,
and the descriptor-derived `supportedArchitectures` and `supportedLanguages`
values. Those arrays are also part of the card's VoiceOver label/value or
accessible child text. Built-in and failed states without a validated
recommendation expose empty custom compatibility arrays; a failed phase with a
validated recommendation retains the exact descriptor arrays. The UI never
invents architecture or language claims.

Hardware recommendation uses the checked `requiredCapacityBytes` staging
requirement, not download bytes alone. The validated required capacity is bound
into the manager adapter; immediately before every install, repair, or update
transfer, the adapter re-reads the live capacity provider and fails before
transport when available bytes are below that bound. It never substitutes the
embedded Parakeet capacity for an admitted descriptor. When `requestedLanguages` is nonempty,
the complete requested set must be a subset of the descriptor's supported
`languages`; an English-plus-Mandarin request against an English-only
descriptor is rejected. A case where available space exceeds `downloadBytes`
but remains below the installed-plus-download staging need is also rejected.
Ordinary and compile-gated candidate Settings render the same single
recommendation/built-in card; the candidate gate does not restore a model
picker, Advanced selector, consent view, or download-specific surface.

Installer presentation has explicit states for `notInstalled`, `downloading`
with received/total bytes, `verifying`, `installing`, `ready`, `starting`,
`calibrating`, `installed`, `updateAvailable`, `repairRequired`, `removing`,
`cancelled`, and actionable failure. It never calls an indeterminate operation
“Loading”. Repair, update, and removal require explicit user actions. Startup
and calibration are visible phases; installation does not imply readiness or
release admission. The installer exposes
`updates: AsyncStream<AdmittedModelInstallationSnapshot>`; the manager adapter
owns one cancellable operation task plus synchronous `@MainActor`
subscriptions to manager byte progress and state. It publishes live monotonic
byte snapshots, starting with one explicit zero and ignoring duplicate or
out-of-range manager emissions, and `verifying`/`installing`/`ready`/`repairRequired`/
`removing`/`cancelled`/failure transitions while the operation is active, and
the Settings view model owns the cancellable subscription.
The Settings action view model maps Install, Cancel, Repair, Update, and Remove
to the corresponding installer method exactly once. One action task serializes
operation actions, one cancellation guard permits Cancel to interrupt that
task, duplicate concurrent operation clicks are ignored, and the action probe
asserts every dispatch produces the expected presentation update. The
`AdmittedModelSettingsPresentation` stores `phase = snapshot.phase`, so the
finite installer phase used by the card and VoiceOver is the same phase tested
by the installer adapter.

If raw signed-descriptor construction fails, or if catalog hardware/language/
capacity gating produces no recommendation, the Settings construction boundary
catches the error and exposes a finite failed installer snapshot with
`.builtIn` recommendation and no custom compatibility claims. If descriptor
validation and catalog recommendation have already succeeded but artifact/
manifest identity binding or enhanced-installer construction fails, the boundary
exposes a finite non-operating failed snapshot retaining
`.recommended(theSameDescriptor)` and its exact architecture/language values.
Both paths start no transport. The coordinator continues using the built-in
Apple Speech/deterministic-cleanup path, so a malformed or failed candidate
configuration cannot disable the safe dictation fallback.
The boundary input is `Optional<AdmittedModelSignedConfiguration>` in the
compile-gated path and is `nil` in the current app; nil maps to the built-in
installer in both ordinary and gated builds. A non-nil value carries the raw
descriptor, exact hardware profile, already-created manager, startup closure,
and calibration closure. Gated factory tests cover unsupported architecture,
unsupported requested language, insufficient staging capacity, and one
supported profile that reaches the recommendation, with
`transport.downloadCalls == 0` before any explicit Install action.
Manager tests also lower live capacity after catalog recommendation and prove
install, repair, and update each fail before transport when available bytes are
above download size but below the bound required staging capacity.

The compile-gated configuration shape is:

```swift
struct AdmittedModelSignedConfiguration {
  let rawDescriptor: RawAdmittedModelDescriptor
  let hardware: AdmittedModelHardwareProfile
  let manager: EnhancedModelManager
  let startup: @MainActor () async throws -> Void
  let calibrate: @MainActor () async throws -> Void
}
```

`makeAdmittedModelInstaller` validates `rawDescriptor`, constructs the catalog
with `hardware`, requires `.recommended(theSameValidatedDescriptor)`, and only
then constructs `EnhancedModelManagerInstaller`. Nil configuration maps to the
built-in installer in ordinary and gated builds.

Refreshing the Settings state subscribes only to the manager's published state
for the refresh duration, maps its final `ready`, `updateAvailable`, or
`repairRequired` value, and never starts transport, byte progress, startup,
calibration, or an installer operation. Fake installer evidence uses one exact
8-byte fixture (`Data("fixture!".utf8)`); descriptor download bytes, manifest
file/aggregate bytes and checksum, artifact identity, and emitted `[4, 8, 8]`
manager progress all derive from that same fixture, while the installer
publishes `[0, 4, 8]`.

The UI uses the existing native macOS Settings structure, semantic colors and
styles, keyboard and VoiceOver labels/values, and no frequent decorative
animation. Keyboard-initiated dictation has no animation. Installer phases,
errors, and byte progress are Settings-only; `Sources/FleckApp/DictationCapsule.swift`
remains excluded from this workstream. Task 3's presentation tests assert the
exact architecture/language strings alongside identity, revision, license,
checksum, size, focus, and finite-progress evidence, plus empty compatibility
values for built-in or invalid/no-recommendation failures and retained exact
values for recommended failures.
The Task 3-owned `AdmittedModelSettingsPresentationTests` evidence is the
source/UI proof for this card; unrelated DictationCapsule accessibility is not
used as evidence.

## Candidate evaluation and later admission

The later evidence lane keeps these candidates distinct:

| Role | Shortlist | Boundary |
| --- | --- | --- |
| ASR | Apple control; Qwen3-ASR 0.6B first and 1.7B conditional; Whisper multilingual base/small/turbo; Nemotron 3.5 ASR Streaming 0.6B; Parakeet v2 English-only control. | No winner is selected by this vertical slice. |
| Cleanup | Dictionary baseline; deterministic cleanup; Apple Foundation Models; Qwen3.5 0.8B and 2B; Qwen3.5 4B lab ceiling only. | No custom cleanup is production-integrated or release-admitted. |

Candidate evidence must name exact upstream ID, immutable revision, runtime and
conversion, quantization, per-file checksums/bytes, license/notices, locale and
hardware support, memory/latency measurements, and offline/cancellation results.
Evaluation-helper, candidate-adapter, and signed-in-app evidence remain separate.
Only the exact signed app with the selected descriptor, verified package, local
calibration, and fresh Sol `ship` verdict can admit a candidate. The vertical
slice's development app is successful with all custom components uninstalled.

## Test and evidence layers

1. **Focused unit evidence:** `PersonalDictionaryTests`,
   `PersonalDictionaryResolverTests`, `CleanupLexemeTests`,
   `CleanupProtectedSpanTests`, `FaithfulCleanupValidatorTests`,
   `IncrementalTranscriptCleanerTests`, and `StreamingTranscriptStateTests`
   prove dictionary alias resolution/ambiguity/protected counts, token
   boundaries, protected categories, allowlisted edits, output bounds, one
   request, deadline behavior, caller cancellation, and number/number-word
   preservation before filler, repetition, or correction edits. The
   `AdmittedModelDescriptorTests` and catalog tests prove raw/validated
separation, both checked-add overflow errors, complete requested-language
subset gating, exact staging capacity, shared repeated-decoding path rejection,
duplicate canonical-path rejection, and the built-in fallback. Compile-gated
manager tests repeat the unsafe-path table through `remoteURL` and prove
duplicate manifest paths fail before transport.
2. **Coordinator integration:** fake `SpeechEngine`, fake processing session,
   fake dictionary resolver, fake cleaner, editor, saver, and history store prove
   one pipeline per capture, provisional display, dictionary-before-cleanup,
   exact baseline insertion, raw-ASR recovery, cancellation, no late events, and
   unchanged legacy behavior.
3. **Apple adapter tests:** injected `SpeechEngine` probes prove the adapter
   forwards provisional/final text and levels, preserves source-owned
   finish/cancel terminalization and idempotent physical release on
   success/failure/cancellation, and makes no second capture. The Foundation
   Model production-boundary probe executes `FoundationModelDictation` through
   an injected responder at the single `respond` call, records one call and
   the exact `GenerationOptions.maximumResponseTokens` cap. Existing
   `AppleSpeechCapture` tests remain green and must prove on-device rejection
   and no network path.
   `StreamingDictationProcessorTests` also hold source finalization at a
   deterministic two-second gate and prove the stop-anchored cleanup and
   insertion deadlines are not reset after the source returns.
4. **Runtime tests:** pure policy, scheduler, lease, lifecycle, memory-pressure,
   sleep, and mutation gates use deterministic sleepers and fake adapters. They
   do not claim a custom model is loaded.
5. **Fake installer tests:** tiny data fixtures and an injected `ModelDownloading`
  fake prove byte progress, checksum/size/path validation, verification,
  installation, startup, calibration, repair, update, removal, cancellation,
  actionable errors, live in-progress snapshot delivery, and descriptor/artifact
   mismatch rejection without a real model transfer. Invalid signed descriptors
   and unsupported catalog profiles use a non-operating failed snapshot with
   `.builtIn` and empty compatibility arrays; binding/installer construction
   failures after a successful recommendation use `.recommended(descriptor)` and
   retain exact descriptor architecture/language arrays. Tests also verify the
   existing Apple Speech availability remains active and transport calls remain
   zero. The
   Task 3-owned Settings presentation tests separately prove the recommendation
   card's VoiceOver label/value, keyboard focus, finite phase/progress copy, and
   exactly-once Install/Cancel/Repair/Update/Remove dispatch with serialized
   duplicate-operation handling.
6. **Offline/cancellation checks:** serialized SwiftPM commands run with
   `--disable-automatic-resolution --no-parallel`; tests assert no URLSession,
   transcript file, audio file, or late insertion is introduced by the vertical
   slice.
7. **App packaging:** after every source task has parent verification and a
   fresh Sol `ship`, the final parent starts the shell checkpoint with
   `set -euo pipefail`, fetches `origin main` read-only, and requires fetched
   `origin/main`, local `main`, the current root HEAD, and pinned starting SHA
   `ab886d9968e6c1ae088d18e085938bec8a80f7c9` to agree. A live `main` may
   track `archive/main`, but `origin/main` is the operational content source.
   It then preflights the real
   `/Users/harryjin/Fleck` checkout at exact root HEAD
   `ab886d9968e6c1ae088d18e085938bec8a80f7c9`, branch `main`, and status
   exactly ` M AGENTS.md`. It verifies the cumulative diff from that starting
   HEAD to the final accepted SHA does not modify `AGENTS.md`, snapshots the
   working-file hash and exact diff, then switches the root checkout to one
   local `codex/...` branch at that exact SHA without merge/rebase/cherry-pick.
   It requires final SHA/branch, hash, diff, ancestry, unmerged-state, and
   ` M AGENTS.md` status to remain identical and aborts before packaging on any
   mismatch. The full-suite command may continue after a nonzero exit only when
   its bounded log contains exactly the known `AppStateTests.swift:916` viewport
   assertion `18.0 >= 48.0`, one Swift Testing per-test record of the form
   `Test ... failed after ... with 1 issue`, and one suite summary beginning
   `Test run with 1 test in 0 suites failed` and containing `with 1 issue`, with
   no other failure, issue, error, crash, or unexpected record. Every other
   failure aborts. Only then run `./Scripts/build-fleck-app.sh` and inspect
   `/Users/harryjin/Fleck/.build/Fleck.app`. A bundle produced in an isolated
   worktree is not evidence for that exact path.
8. **Operator microphone test:** a human launches the development app, grants
   permissions, speaks a known sentence containing punctuation/filler/repetition
   and protected content, observes provisional display and final insertion,
   then cancels a second capture. The primary may launch the app but must not
   invent what the microphone transcribed; the operator records the actual words
   and result.
9. **Later signed-app admission:** only after candidate evidence exists, repeat
   exact-identity, package, offline, memory, cancellation, calibration, and
   signed-app checks for the selected descriptor. This is not part of the
   development milestone.

The known unrelated baseline caveat remains visible: `AppStateTests.swift`
around line 916 may fail the viewport assertion `18.0 >= 48.0` on `main`. The
plans preserve and report that failure; they do not weaken the assertion or
silence the suite.

## Implementation workstream order and dependency graph

```text
Accepted base 4212314
        |
        v
Task 0. personal-dictionary-resolution-core
   four final 898ceae FleckCore files
        |
        v   parent rerun + fresh Sol ship
A. faithful-cleanup-completion workstream
   Task 1 validator -> Task 2 bounded cleaner
        |
        v   parent rerun + fresh Sol ship
B. streaming-and-app-integration workstream
   processing contracts -> transcript state -> runtime foundation
   -> processor + AppleSpeechStreamingAdapter -> coordinator wiring
        |
        v   parent rerun + fresh Sol ship
C. model-installation-and-real-app-verification workstream
   admitted descriptor/catalog -> manager adapter + fake installer
   -> Settings presentation -> package/build -> human microphone checklist
        |
        v
No custom release admission; later candidate evidence gate remains open.
```

Task 0 is the prerequisite separate user-visible task before Workstream A; it
uses the same workflow gate as every later task. The A, B, and C lines are
dependency-ordered workstreams, not individual implementation tasks. Every
numbered task in a workstream is its own separate user-visible Codex task
running GPT-5.6 Luna/Max and titled with the exact `Agent - <singular task>`
prefix. Before each task, the primary Sol session is GPT-5.6 Sol at High
reasoning; it first runs the orchestration exactness check and confirms the
exact native routing roles are available, then writes a bounded five-part
packet: objective/success criteria; owned files, interfaces, and
constraints; implementation and explicit non-goals; verification commands and
expected evidence; and authority boundaries plus the handoff. The Luna/Max task
adapts to concurrent edits and preserves unrelated work. The parent Sol task
inspects the actual diff and reruns the required checks; a fresh
`sol_advisor_sol_reviewer` must return exactly `ship` before the next dependent
numbered task starts. Both `fix-first` and `rethink` return the corrected bounded
packet to the same user-visible Luna/Max task; neither switches tasks or adds an
implementation route.

No workstream or task authorizes a push, PR, merge, GitHub mutation, model-weight download,
candidate selection, or release admission.

## Milestone completion

The milestone is complete only when all of the following are directly evidenced:

- the focused SwiftPM and scope checks pass, with unrelated baseline failures
  classified rather than hidden;
- the real-checkout build script produces `/Users/harryjin/Fleck/.build/Fleck.app`;
- the development app launches from that artifact;
- the app requests and receives the required microphone and Speech Recognition
  permissions, refuses network recognition, and reaches Apple on-device Speech;
- a human observes live provisional text with an append-only stable prefix and a
  bounded mutable tail, then observes dictionary resolution, fail-closed cleanup,
  and insertion of the actual spoken result or exact baseline;
- cancelling a real capture produces no late update, history mutation, route, or
  insertion; and
- Settings shows the built-in state with no custom model installed and no model
  picker. Any future recommendation remains an explicit, catalog-driven action.

Automated checks establish that the app is packaged and the seams are safe. They
cannot establish what a microphone produced. The final speech observation is a
human evidence item and must be reported as observed, not inferred.
