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
| `AppleSpeechCapture` | The existing `AVAudioEngine`/Speech framework session, permission request, on-device requirement, provisional/final callbacks, interruption, and resource release. | Dictionary resolution, cleanup, routing, history, UI, or model downloads. |
| `AppleSpeechStreamingAdapter` | Adapting the existing `SpeechEngine` callback/final interface to the processor seam. | A second audio tap, microphone session, network fallback, or model choice. |
| `DictationProcessing` / `StreamingDictationProcessor` | One incremental capture session's transcript updates, dictionary-before-cleanup final artifacts, and bounded cleanup decision. | Shortcut identity, note persistence, routing policy, or UI ownership. |
| `StreamingTranscriptState` | Generation ordering, append-only stable prefix, and a mutable tail capped by the newest two clauses or 80 `CleanupLexeme` lexical units. | Semantic cleanup or insertion. |
| `FaithfulCleanupValidator` | The deterministic allowlist and protected-meaning decision. | Generating text, choosing a model, or logging transcript data. |
| `IncrementalTranscriptCleaner` | One bounded cleanup request, one generation attempt, deadline/cancellation race, validation, exact baseline fallback, and session-box publication gate. | Dictionary resolution, audio, runtime residency, or UI. |
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
provisional/final/level/cancel/release interface; it never constructs
`AppleSpeechCapture`, installs another tap, or creates another audio engine. The
processor awaits the source factory, starts this one source exactly once with
both callbacks, and passes the already-started source to a synchronous session
initializer; a start failure releases the source before rethrowing. The legacy
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
6. On stop, the processing session finishes the existing Speech source exactly
   once and obtains final raw ASR text. It resolves the personal dictionary
   before constructing `IncrementalCleanupRequest`. At that finish boundary it
   records `stopInstant`, creates `insertionDeadline = stopInstant + 3,000 ms`,
   and gives cleanup `min(stopInstant + 1,500 ms, insertionDeadline)`.
7. `IncrementalTranscriptCleaner` performs at most one bounded generation.
   `FaithfulCleanupValidator` compares the candidate with the dictionary
   baseline and protected spans. A valid candidate becomes `cleanedTranscript`;
   every other valid-capture cleanup outcome inserts the exact baseline.
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
The transcript is quoted data, never instructions.

## Cancellation and generations

`DictationCoordinator` is the transaction owner. It increments an invalidation
generation before editor rollback and before asking the selected pipeline to
cancel. Every callback carries or closes over the capture UUID and is ignored
unless all of these remain true: the UUID is active, the generation is current,
the capture is not cancelling/terminating, and the pipeline is still accepting
updates.

Cancellation must execute in this order:

1. mark the capture cancelled and invalidate its generation;
2. restore the focused editor's exact pre-capture transaction;
3. stop the selected speech source and cancel the processing session;
4. erase provisional transcript and in-memory audio buffers;
5. remove provisional history work and release runtime scratch state;
6. await the bounded cleanup/helper acknowledgement, forcing termination when
   its cancellation budget expires; and
7. publish only `.cancelled` after no active work can publish.

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
struct AdmittedModelDescriptor: Equatable, Sendable {
  let role: AdmittedModelRole
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let license: String
  let source: URL
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let languages: [String]
  let architectures: [String]

  var requiredCapacityBytes: Int64 { installedBytes + downloadBytes }
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
}
```

The signed boundary constructs the descriptor through a throwing validation
initializer for empty identity/revision/license, unsafe paths, invalid sizes or
checksums, aggregate mismatches, and empty support sets. The existing
compile-gated manager builds or receives one immutable
`EnhancedModelArtifactIdentity` alongside its `EnhancedModelManifest`; its
source repository and revision derive every `remoteURL`. The admitted installer
compares the descriptor's immutable identity with that artifact identity and the
artifact identity with the actual manifest identity before any manager operation;
descriptor/artifact or artifact/manifest mismatch rejects before transport. The
existing manifest path/revision checks and `?download=true` URL query remain
authoritative. This is a small seam, not a generic multi-model registry.
The existing `DictationModelCapability(modelRootURL:)` call remains source
compatible through a compile-gated manager convenience initializer that uses
the current experimental Parakeet manifest and a compatibility-only embedded
identity. That route does not create an admitted descriptor, recommendation,
or installer; an explicit signed configuration must still provide its own
already-created manager and pass binding before any operation.

The signed app supplies either no descriptor or exactly one hardware-appropriate
recommendation for the curated experience. Ordinary release configuration is
empty, so the normal Dictation settings surface shows the built-in Apple state:
“Apple Speech — Built in”, “On-device recognition”, and “No custom model is
installed.” There is no model picker and no Advanced selector. A recommendation
surface, when an admitted descriptor exists, has one explicit `Install` action
and shows exact identity, revision, license, checksums, download/installed size,
and supported hardware/languages.

Hardware recommendation uses an explicit staging requirement of
`installedBytes + downloadBytes`, not download bytes alone. Ordinary and
compile-gated candidate Settings render the same single recommendation/built-in
card; the candidate gate does not restore a model picker, Advanced selector,
consent view, or download-specific surface.

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

If signed-descriptor construction or either identity comparison fails, the
Settings construction boundary catches the error and exposes a finite failed
installer snapshot without starting transport. The coordinator continues using
the built-in Apple Speech/deterministic-cleanup path, so a malformed candidate
configuration cannot disable the safe dictation fallback.
The boundary input is `Optional<AdmittedModelSignedConfiguration>` in the
compile-gated path and is `nil` in the current app; nil maps to the built-in
installer in both ordinary and gated builds. A non-nil value carries the raw
descriptor, already-created manager, startup closure, and calibration closure.

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
remains excluded from this workstream.

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
   request, deadline behavior, and caller cancellation.
2. **Coordinator integration:** fake `SpeechEngine`, fake processing session,
   fake dictionary resolver, fake cleaner, editor, saver, and history store prove
   one pipeline per capture, provisional display, dictionary-before-cleanup,
   exact baseline insertion, raw-ASR recovery, cancellation, no late events, and
   unchanged legacy behavior.
3. **Apple adapter tests:** injected `SpeechEngine` probes prove the adapter
   forwards provisional/final text and levels, releases exactly once, and makes
   no second capture. Existing `AppleSpeechCapture` tests remain green and must
   prove on-device rejection and no network path.
4. **Runtime tests:** pure policy, scheduler, lease, lifecycle, memory-pressure,
   sleep, and mutation gates use deterministic sleepers and fake adapters. They
   do not claim a custom model is loaded.
5. **Fake installer tests:** tiny data fixtures and an injected `ModelDownloading`
  fake prove byte progress, checksum/size/path validation, verification,
  installation, startup, calibration, repair, update, removal, cancellation,
  actionable errors, live in-progress snapshot delivery, and descriptor/artifact
  mismatch rejection without a real model transfer. Invalid signed descriptors
  and bindings are caught into a non-operating failed Settings snapshot; Apple
  Speech remains the active fallback and transport calls remain zero.
6. **Offline/cancellation checks:** serialized SwiftPM commands run with
   `--disable-automatic-resolution --no-parallel`; tests assert no URLSession,
   transcript file, audio file, or late insertion is introduced by the vertical
   slice.
7. **App packaging:** run `./Scripts/build-fleck-app.sh` from the real
   `/Users/harryjin/Fleck` checkout and inspect `/Users/harryjin/Fleck/.build/Fleck.app`.
   A bundle produced in an isolated worktree is not evidence for that exact path.
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
uses the same parent inspection and fresh-review gate as every later task. The
A, B, and C lines are dependency-ordered workstreams, not individual
implementation tasks. Every numbered task in a workstream is its own separate
user-visible Codex task running GPT-5.6 Luna/Max and titled with the exact
`Agent - <singular task>` prefix. The parent Sol task inspects and reruns that
task's diff and checks; a fresh `sol_advisor_sol_reviewer` must return exactly
`ship` before the next dependent numbered task starts. A `fix-first` result
returns a corrected bounded specification to the same task; a `rethink` result
returns to the parent architecture.

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
