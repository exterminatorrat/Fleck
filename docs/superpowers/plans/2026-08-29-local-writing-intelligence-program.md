# Fleck Local Writing Intelligence Implementation Program

> **Planning-only checkpoint:** Do not execute these packets until the owner approves the program and the implementation-routing conflict in Phase 0 is resolved.

**Planning base:** `0c63559083a00dfab5b92b4edea01fbdb0fda14e`
**Target:** Apple Silicon, English-first, private local runtime, no bundled weights
**Primary model candidates:** Parakeet TDT 0.6B v2 for hold-to-talk dictation; Gemma 3 1B IT QAT 4-bit for cleanup; Apple Speech and deterministic cleanup remain mandatory fallbacks
**Method:** bounded red-first packets, isolated worktrees, exact ownership, parent verification, fresh independent review, then dependency promotion

## Design package

- `docs/superpowers/specs/2026-08-29-local-writing-intelligence-program-design.md` — umbrella architecture, invariants, states, and completion definition.
- `docs/superpowers/specs/2026-08-29-dictation-cleanup-and-sorting-quality-design.md` — capture, ASR, cleanup, routing, correction, latency, and safety behavior.
- `docs/superpowers/specs/2026-08-29-real-local-writing-quality-corpus-design.md` — private corpus schema, taxonomy, oracles, metrics, evidence levels, and two-Mac protocol.
- `docs/superpowers/specs/2026-08-29-shared-personal-dictionary-design.md` — schema v2, compiler products, conflict handling, capture pinning, and explicit learning.
- `docs/superpowers/specs/2026-08-29-curated-local-model-catalog-design.md` — exact model profiles, curated configurations, recommendation, installation, and admission states.
- `docs/superpowers/specs/2026-08-29-packaged-local-writing-admission-design.md` — package identity, live QA, signing, release ladder, rollback, and final admission.
- `docs/research/2026-08-29-local-writing-model-catalog-primary-sources.md` — primary-source model/runtime/license research and observed revisions; research evidence only.

## Program outcome

Deliver one exact Fleck configuration that can be truthfully tested and, only after all gates, admitted:

```text
real microphone
 -> capture-first local ASR
 -> one revision-pinned personal dictionary
 -> bounded faithful cleanup
 -> fail-closed semantic sorting
 -> durable insertion/history/Inbox chooser
 -> adaptive model lifecycle
 -> reproducible local evidence
 -> exact packaged two-Mac acceptance
```

## Phase 0 — Authority, base, and evidence reconciliation

No product packet starts before Phase 0 closes.

### Packet 0A — Resolve implementation routing

**Objective:** Choose one lawful implementation lane for the whole approved program.

**Conflict:**

- current tracked `AGENTS.md` requires Sol Advisor and user-visible GPT-5.6 Luna/Max tasks, and forbids native implementation subagents;
- the user's later stated implementation preference is Codex-native GPT-5.6 Sol/High subagents.

**Decision required:** Either:

1. keep current `AGENTS.md` and use its Luna/Max task workflow; or
2. explicitly authorize a focused `AGENTS.md` policy update to native Sol/High implementers before any product diff.

No agent may infer that plan approval silently resolves this conflict.

**Files:** none unless option 2 is explicitly authorized.
**Verify:** reread the actual tracked and working-tree `AGENTS.md`; record chosen lane in the implementation checkpoint.
**Gate:** one unambiguous active policy.

### Packet 0B — Freeze the integration base

**Objective:** Start from the newest accepted Fleck UI/product base without losing the semantic-routing/Gemma/Parakeet work.

**Read-only steps:**

1. fetch remotes only after owner authorization if network Git state needs refresh;
2. enumerate branches, worktrees, unmerged entries, merge/rebase state, active tasks, and dirty files;
3. compare `0c635590` to current `origin/main` and any user-named “Fleck - Main” checkpoint;
4. classify every overlapping commit by feature and evidence;
5. choose a clean integration commit containing the newest accepted UI plus the local-writing stack;
6. create one program branch/worktree from that exact commit;
7. preserve the existing uncommitted `AGENTS.md` and all unrelated user work.

**Files:** none.
**Verify:** `git status --short --branch`, `git worktree list --porcelain`, an explicit symmetric comparison such as `git log --left-right --cherry-pick 0c635590...origin/main`, `git diff --check`, merge/rebase/cherry-pick state.
**Gate:** clean isolated base, exact commit recorded, no unrelated file moved or modified.

### Packet 0C — Reconcile baseline tests and documentation truth

**Depends on:** 0B
**Objective:** Distinguish pre-existing failures from program regressions and correct stale claims before using them as acceptance evidence.

**Owned documentation only:**

- `ARCHITECTURE.md`
- `README.md`
- `IMPLEMENTATION_STATUS.md`
- `TESTING.md`
- `docs/testing/local-dictation-routing-checklist.md`

**Required changes:**

- update title-only routing claims to the current bounded full-note local semantic index;
- label Parakeet/Gemma as candidate/test integration unless current evidence proves more;
- record current real/synthetic/package evidence separately;
- record exact baseline test failures with command, commit, date, and reproducibility;
- do not repair unrelated baseline failures in this packet.

**Verify:** link/path audit, `git diff --check`, source-to-document claim audit.
**Gate:** no documentation claims production or release evidence that does not exist.

### Packet 0D — Non-empty Swift test runners and enhanced lock isolation

**Depends on:** 0B
**Objective:** Make every later focused verification fail when its filter matches no tests and make enhanced-candidate tests restore the ordinary root lockfile byte-for-byte.

**Owned files:**

- `Scripts/run-nonempty-swift-tests.sh` — new ordinary runner
- `Scripts/run-nonempty-enhanced-tests.sh` — new candidate runner using `resolve-enhanced-candidate.sh`
- `Scripts/test-nonempty-swift-test-runners.sh` — new hermetic shell contract test
- `Scripts/validate-macos.sh`

**Required implementation:** require a non-empty anchored test-identifier regular expression; accept an optional validated `--package-path <repository-relative-package>` for ordinary nested packages; run both ordinary `swift test list` and the matching filtered test with `--disable-automatic-resolution`; count canonical matching identifiers; fail before testing when the count is zero; preserve the command exit code; and prove the relevant package lockfile plus root lockfile canaries are byte-identical after ordinary success, no-match, test failure, and interruption. The enhanced runner creates a task-local temporary parent, passes its absent `build` child through the existing resolving wrapper, uses that same scratch path for list/run, and proves root `Package.resolved` is byte-identical after success, no-match, test failure, interruption, and resolver failure. It never invokes bare `FLECK_ENHANCED_CANDIDATE=1 swift test`.

**Red tests first:** ordinary no-match, nested-package no-match, invalid/escaping package path, nested lock mutation, enhanced no-match, matching list but failing run, signal cleanup, callback exit propagation, caller working directory, existing scratch refusal, and root-lock canary preservation.

**Verify:**

```bash
Scripts/test-nonempty-swift-test-runners.sh
Scripts/test-enhanced-candidate-lock-preservation.sh
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.personalDictionaryValuesRoundTripThroughCodable\(\)$'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.EnhancedSpeechRejectsAnUnverifiedModelWithoutStartingAudio\(\)$'
```

**Gate:** all later packet commands use these runners; a green command always has a recorded positive matched-test count and cannot leave `Package.resolved` changed.

**Canonical identifier contract for every later packet:** a verification regex targets canonical `swift test list` identifiers, never a filename inferred to be a suite. A new named-suite file must define the suite name shown in its regex. A packet adding top-level tests must give its red tests the explicit function prefix shown in its regex. Before delegation, the primary records the positive matched identifier list from the chosen base; if the planned name and emitted identifier differ, the plan command is corrected before implementation—not after a green no-op run.

## Phase 1 — Evidence contracts and stage observability

Phase 1 is behavior-neutral. It makes later work measurable before model tuning begins.

### Packet 1A — Local corpus and evidence schema

**Objective:** Add strict types for private human corpus manifests, controlled routing workspaces, oracles, execution variants, threshold revisions, and evidence levels.

**Owned files:**

- `Package.swift` — add the one-way `FleckModelEvaluation -> FleckCore` target dependency
- `Sources/FleckCore/LocalWritingCorpus.swift` — new shared manifest, receipts, tags, and oracle contracts
- `Sources/FleckCore/LocalWritingExposureLedger.swift` — new canonical append-only pre-execution exposure contract/store
- `Sources/FleckModelEvaluation/LocalWritingEvidence.swift` — new
- `Sources/FleckModelEvaluation/ModelEvaluation.swift` — map shared protected expectations into the existing scorer
- `Sources/FleckModelEvaluation/CandidateBenchmarkEvidence.swift` — compatibility adapter, not a duplicate admission vocabulary
- `Tests/FleckCoreTests/LocalWritingCorpusTests.swift` — new
- `Tests/FleckCoreTests/LocalWritingExposureLedgerTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingCorpusTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingEvidenceTests.swift` — new

**Explicit non-goals:** no UI, audio recording, product logging, model run, repository corpus files, or changes to current candidate evidence.

**Red tests first:**

- absolute/traversal/symlink-escaping paths rejected;
- missing consent or audio hash rejected for human cases;
- synthetic/fault cases cannot be human-eligible or enter human aggregates;
- conflicting/overlapping oracles rejected;
- controlled workspace duplicate/case-colliding keys, missing unique Inbox, unstable note order, oracle keys absent from the manifest, invalid cohort floors, and noncanonical mutation schedules rejected;
- manifest digest excludes its own envelope and canonicalizes every ordered array;
- threshold and run revisions are immutable;
- exposure is atomically recorded before candidate access/output; truncated, forked, reordered, duplicate, or mismatched eligibility chains/checkpoints fail closed;
- a post-exposure oracle correction or exposed-case deletion appends a lineage-invalidation event before mutation; old receipt heads remain ancestors but fail current verification;
- a post-exposure correction on the same material lineage is diagnostic-only, and admission eligibility requires newly recorded blinded material;
- evidence tier cannot be promoted without required receipts;
- content-free public summary excludes private text/audio paths.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.LocalWritingCorpusTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.LocalWritingExposureLedgerTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingCorpusTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingEvidenceTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.'
```

**Gate:** schema round-trip, malformed corpus fail-closed, no product dependency on evaluation storage.

### Packet 1B — Processor stage measurements

**Objective:** Replace `.empty` processor measurements with monotonic stage receipts while preserving text behavior. This packet records orchestration times only; it does not claim physical key-down/key-up evidence.

**Owned files:**

- `Sources/FleckApp/DictationProcessingModels.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`

**Measurements:** processor/source start, first genuine partial, processor stop request, ASR final, dictionary finish, deterministic/model cleanup, validation, cancellation request/drain.

**Constraints:** inject a monotonic clock; do not log transcripts; do not alter deadlines; absent stages remain explicitly absent rather than zero.

**Red tests first:** tests use the `processorMeasurements...` prefix and cover stage ordering, deadline origin at stop, rejected cleanup timing, cancellation timing, source with no partial, and clock rollback impossible by type. Existing `runtimeMeasurements...` compatibility remains covered.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.processorMeasurements'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.runtimeMeasurements'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(updateDisplay|resultKeeps|productionProcessingBudget|deadlineUses|runtimeMeasurements|recognitionContext|processingValues|protocolSeams)'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(beginStarts|beginPasses|beginForwards|beginRetains|beginReleases|successfulFinish|emptyFinalText|failedFinish|cancellingAfterSourceFinish|concurrentCancelCallers|cancellingBeforeFinalizationBodyStarts|cancellingBlockedFinishReturningNil|cancellingSessionUnblocks|cancellingBeforeFinish|cancellationWinner|processorUsesExactBaseline|processorUsesRawRecovery|processorCapturesStop)'
```

**Gate:** exact existing output/cancellation tests plus non-empty truthful timings.

### Packet 1C — Physical gesture, persistence, and routing measurements

**Depends on:** 1B
**Objective:** Preserve exact physical key-down/key-up instants and extend the same receipt through routing, persistence, insertion, chooser, and compensation.

**Owned files:**

- `Sources/FleckApp/GlobalHoldShortcut.swift`
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/DictationProcessingModels.swift`
- `Tests/FleckAppTests/GlobalHoldShortcutTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`

**Red tests first:** tests use the `physicalGestureReceipt...` prefix and prove physical event instant survives asynchronous delivery; release deadline originates at physical key-up; focused insertion; Smart save; ambiguous Inbox durability; exact move; cancelled route; save recovery; and no timestamp after terminal cancel.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.physicalGestureReceipt'
```

**Gate:** one end-to-end measurement object with no transcript content and no lifecycle behavior change.

## Phase 2 — One reliable revision-pinned dictionary

### Packet 2A — Dictionary v2 values and canonical codec

**Can run in parallel with:** Phase 1
**Objective:** Define snapshot revisioning, strict canonical v2 bytes, and v1-to-v2 candidate decoding without publishing a new authoritative store value yet.

**Owned files:**

- `Sources/FleckCore/PersonalDictionary.swift`
- `Sources/FleckCore/PersonalDictionaryCodec.swift`
- `Tests/FleckCoreTests/PersonalDictionaryTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift`

**Required implementation:** schema v2 values, checked revision arithmetic helpers, canonical sorted encoding, strict unknown-field/duplicate rejection, and non-destructive v1 decoding into an uncommitted v2 candidate. Authoritative publication and automatic migration are explicit non-goals until the compiler exists in 2B.

**Red tests first:** v1 candidate parity, stable canonical bytes across entry order, duplicate keys/IDs, future schema, checked overflow, unsupported locale preserved, suggestions retained, strict size bounds.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.personalDictionary(Values|Snapshot|Entry|JSON|CSV)'
```

**Gate:** current v1 fixtures decode into the intended v2 candidate byte-safely; no authoritative file is replaced in this packet.

### Packet 2B — Deterministic dictionary compiler

**Depends on:** 2A
**Objective:** Compile one snapshot into recognition, resolver, cleanup-protection, routing, and diagnostic products.

**Owned files:**

- `Sources/FleckCore/CompiledPersonalDictionary.swift` — new
- `Sources/FleckCore/PersonalDictionaryResolver.swift`
- `Tests/FleckCoreTests/CompiledPersonalDictionaryTests.swift` — new
- `Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift`

**Required implementation:** canonical conflict graph; exact same exclusion set across outputs; at-most-100 recognition strings; revision/digest; longest-first safe resolver; routing identity; stable content-free diagnostics.

**Red tests first:** alias/preferred collision matrix, cycles, Unicode, punctuation/underscore preservation, deterministic truncation, same digest across order, no term in diagnostics, conflict excluded from every output.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.CompiledPersonalDictionaryTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.resolver'
```

**Gate:** one immutable compiler result, no second dictionary type in FleckApp.

### Packet 2B2 — Compile-before-publish store and migration

**Depends on:** 2A, 2B
**Objective:** Make every authoritative dictionary mutation and v1 migration compile the staged v2 snapshot before one atomic publication.

**Owned files:**

- `Sources/FleckCore/PersonalDictionaryStore.swift`
- `Sources/FleckCore/PersonalDictionaryCodec.swift`
- `Tests/FleckCoreTests/PersonalDictionaryStoreTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryPublicationTests.swift` — new

**Required implementation:** optimistic `expectedRevision`; candidate revision increment before encoding; stage canonical bytes; fsync; strict decode; compile staged value; compute content digest; atomically replace once; publish the matching immutable compiled snapshot; retain one bounded non-authoritative recovery copy. Compiler/decoding/conflict/overflow/I/O failure leaves both authoritative bytes and current compiled snapshot unchanged. Automatic v1 migration uses the same transaction.

**Red tests first:** compile failure after staging, crash before replace, corrupt readback, stale expected revision, revision overflow, recovery copy non-authoritative, v1 migration parity, concurrent import/suggestion edit, authoritative bytes and compiled snapshot never diverge.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.personalDictionaryStore'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.PersonalDictionaryPublicationTests/'
```

**Gate:** no public store mutation path can publish bytes that were not decoded and compiled from that exact staged candidate.

### Packet 2B3 — Canonical dictionary transfer

**Depends on:** 2B2
**Objective:** Export and explicitly import one complete v2 dictionary content snapshot for reproducible two-Mac testing.

**Owned files:**

- `Sources/FleckCore/PersonalDictionaryCodec.swift`
- `Sources/FleckCore/PersonalDictionaryStore.swift`
- `Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryStoreTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryTransferTests.swift` — new

**Required implementation:** strict transfer envelope containing effective entries, approved/pending suggestions, schema/compiler-policy identity, canonical content digest, byte count, and export timestamp outside the digest. Import previews the exact delta, rebases to `currentRevision + 1`, and goes through 2B2's compile-before-publish transaction. Two devices with identical effective content must have the same content digest even when their local structural revisions differ. Existing CSV remains an entries-only convenience and is never accepted as the two-device evidence snapshot.

**Red tests first:** complete round trip, suggestions retained, target revision rebased, cross-device digest equality, tampered digest/unknown field/oversize/traversal rejection, conflict preview, cancelled import leaves state unchanged.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.PersonalDictionaryTransferTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.personalDictionary(Store|JSON|CSV)'
```

**Gate:** an explicit export/import produces matching content digests without assuming matching local revision numbers.

### Packet 2C — Capture-pinned dictionary context

**Depends on:** 1C, 2B2
**Objective:** Pin one already compiled dictionary revision before recognition consumes audio and require acknowledgement through every downstream stage. Audio-ingress lifecycle changes belong to Phase 3.

**Owned files:**

- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationProcessingModels.swift`
- `Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/PersonalDictionaryTranscriptResolverTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Required implementation:** a narrow `LocalWritingCaptureContext` containing capture/generation, `String` locale identifier, existing speech-engine identity, compiled dictionary, and policy revision; pin the store's already published compiled snapshot; explicit applied/unsupported/rejected recognition acknowledgement; settings changes affect next capture; same structural revision/content digest in resolver/protection/evidence. Catalog profile identity is added later in Phase 6.

**Red tests first:** mutation during capture, mismatch at each stage, unsupported ASR context truth, missing/corrupt precompiled context fails before recognition consumes audio, cancellation while pinning, exact faithful fallback.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(resolver|processing|processor|coordinator).*Dictionary'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.dictationAvailability'
```

**Gate:** no active path hard-codes `.englishDefault` without the pinned compiled context.

### Packet 2D — Dictionary Settings and explicit suggestions

**Depends on:** 2B3
**Objective:** Complete conflict-safe editing/import/suggestion approval without hidden learning.

**Owned files:**

- `Sources/FleckApp/PersonalDictionarySettingsViewModel.swift`
- `Sources/FleckApp/SettingsView.swift`
- `Tests/FleckAppTests/PersonalDictionarySettingsTests.swift`
- `Tests/FleckAppTests/DictationAccessibilityTests.swift`

**Required implementation:** search/filter, conflict preview, revision-conflict recovery, suggestions approve/edit/dismiss, canonical snapshot export, explicit canonical import preview, CSV entries-only labeling, and explanatory copy.

**UI skills required:** macOS SwiftUI patterns, `emil-design-eng`, relevant accessibility/visual QA; reuse native Form/list patterns and existing section.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.personalDictionary(Settings|Runtime)'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationAccessibility'
```

**Gate:** normal UI stays compact; no compiler/tokenizer/model knobs.

## Phase 3 — Capture-first ASR and terminology context

### Packet 3A — Physical key-down arming capture

**Depends on:** 1C, 2C
**Objective:** Start the selected speech source at physical key-down while preserving the 180 ms short-tap gesture and suppressing publication until the hold is accepted.

**Owned files:**

- `Sources/FleckApp/GlobalHoldShortcut.swift`
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationProcessingModels.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Tests/FleckAppTests/GlobalHoldShortcutTests.swift`
- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Required implementation:** pass physical press/release instants; reserve and start an arming source at key-down; keep UI/provisional publication in `.arming`; accept at threshold; short release cancels/drains/discards with no insertion/history/failure. Replace the timestamp-free processing-session finish seam with one that requires the capture's physical release instant; the processor derives ASR-readiness, release-tail, cleanup, routing, insertion, and cancellation deadlines from that immutable instant rather than from later actor delivery.

**Red tests first:** speech during the first 180 ms is retained after an accepted hold; short tap drains without output; release racing threshold has one outcome; Escape during arming drains; no old generation publishes; exact physical key-up timestamp survives suspension.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.captureFirst'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(coordinator|processing|hold|short|shortcut)'
```

**Gate:** one source start per press and unchanged user-visible short-tap behavior; no claim that a specific adapter captures before its own startup is fixed.

### Packet 3B — Parakeet batch audio-first/model-parallel startup

**Depends on:** 3A
**Objective:** Fix the enhanced batch adapter so audio capture starts before Parakeet model preparation and retains the complete bounded utterance.

**Owned files:**

- `Sources/FleckApp/EnhancedSpeechCapture.swift`
- `Tests/FleckAppTests/EnhancedSpeechCaptureTests.swift` — new
- `Tests/FleckAppTests/DictationCoordinatorTests.swift` — update the existing enhanced fixtures/assertions that currently require load before audio start

**Required implementation:** start `EnhancedAudioCapturing` immediately; load/verify inference concurrently; retain a bounded full-session PCM buffer because `EnhancedSpeechInferring` is batch-only; await readiness within a fixed deadline after physical release; transcribe once; fixed release tail; zero/release on every terminal; device-loss and maximum-duration behavior.

**Explicit non-goal:** no replay/stream consumer or fabricated partials. Same-capture fallback into Apple Speech requires a future shared PCM adapter and is not promised here; a failed enhanced capture truthfully fails and selects Apple for the next capture.

**Red tests first:** first frame retained through cold load; bounded maximum duration; one batch transcription; final frame retained; stop deadline not extended; cancel/load failure zeroes PCM; no disk I/O; model readiness timeout publishes nothing and selects Apple Speech for the next capture without late output.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.EnhancedSpeechCaptureTests/'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.EnhancedSpeech'
```

The runner must report a positive canonical match count and restore ordinary `Package.resolved` byte-for-byte.

### Packet 3C1 — Apple Speech contextual terminology

**Depends on:** 2C
**Can run in parallel with:** 3B because owned files are disjoint
**Objective:** Pass the pinned bounded recognition strings to both Apple on-device speech implementations.

**Owned files:**

- `Sources/FleckApp/AppleSpeechCapture.swift`
- `Sources/FleckApp/AppleSpeechStreamingAdapter.swift`
- `Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift`

**Required implementation:** legacy `contextualStrings`; macOS 26 `AnalysisContext`; explicit applied/unsupported/rejected acknowledgement; preserve on-device-only enforcement.

**Red tests first:** exact bounded strings/revision/digest, unsupported locale, system asset unavailable, context setup failure, cancel before acknowledgement, no cloud fallback.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.adapterForwardsSpeechCallbacksWithoutCreatingAudio'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.dictationAvailability'
```

### Packet 3C2 — Apple Speech fixed release tail

**Depends on:** 3A, 3C1
**Can run in parallel with:** 3B because owned files are disjoint
**Objective:** Retain a short fixed post-key-up audio tail in both Apple implementations without extending the absolute release-to-insertion deadline.

**Owned files:**

- `Sources/FleckApp/AppleSpeechCapture.swift`
- `Sources/FleckApp/AppleSpeechStreamingAdapter.swift`
- `Tests/FleckAppTests/AppleSpeechReleaseTailTests.swift` — new
- `Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift`

**Required implementation:** inject monotonic sleep/clock; record physical key-up from the 3A interface; continue audio ingress only for one frozen short tail; stop and finalize at the earlier of tail expiry or absolute processing deadline; cancellation/device loss stops immediately with no tail; late frames cannot reset either deadline.

**Red tests first:** final plosive retained, exact tail duration, absolute deadline unchanged, cancel during tail, input loss, duplicate finish, no late callback, legacy and macOS 26 paths behave equivalently.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.AppleSpeechReleaseTailTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(adapterForwardsSpeechCallbacksWithoutCreatingAudio|dictationAvailability)'
```

**Gate:** Apple no longer stops its tap synchronously at key-up, yet cancellation and the total stop budget remain bounded.

### Packet 3D — Parakeet context capability seam

**Depends on:** 2C, 3B
**Objective:** Make enhanced ASR state whether it applied acoustic vocabulary assistance; retain deterministic post-ASR resolution regardless.

**Owned files:**

- `Sources/FleckApp/EnhancedSpeechCapture.swift`
- `Sources/FleckApp/ParakeetTDTTestActivation.swift`
- `Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift`
- `Tests/FleckAppTests/EnhancedSpeechCaptureTests.swift`
- `Tests/FleckAppTests/ParakeetTDTTestActivationTests.swift`
- `Tests/FleckAppTests/ParakeetContextCapabilityTests.swift` — new named suite
- `Tests/FleckAppTests/PersonalDictionaryTranscriptResolverTests.swift`

**First implementation:** return `unsupported` for plain TDT v2 if FluidAudio's selected adapter cannot bias decoding. Do not fake a boost.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.ParakeetContextCapabilityTests/'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.resolver'
```

**Gate:** evidence distinguishes post-ASR correction from actual acoustic context.

### Packet 3E — Parakeet packaged smoke and first-word mini-gate

**Depends on:** 3A, 3B, 3C2, 3D
**Objective:** Produce a local enhanced test app and run a small real-microphone gate before broader model/catalog work.

**Owned files:** no source unless a defect is diagnosed into a new bounded repair packet. Content-free diagnostic evidence goes to a private smoke root that is not a corpus root.

**Run:** 20 immediate-start, 10 release-edge, 10 dictionary-term utterances on Mac mini; cold/warm; cancel; offline after install.

**Verify:**

```bash
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
codesign --verify --deep --strict .build/parakeet-test/Fleck.app
shasum -a 256 .build/parakeet-test/Fleck.app/Contents/MacOS/Fleck
```

Record only the 40-case content-free checklist with exact executable/model/dictionary hashes and outcome codes. These prompts, spoken takes, any troubleshooting recordings, and their material lineages are permanently diagnostic-only and cannot be imported, copied, relabeled, or reused in the admission corpus; later 7D4/7E cases require new frozen oracles and fresh audio before first exposure. Ordinary smoke audio remains memory-only unless the user separately opts into a diagnostic recording, which still stays non-ingestible and outside Git. A content-free summary may enter status docs.

**Gate:** first-word target trend, zero late insertions, exact artifact identity. This is diagnostic human-speech evidence, never D4/D5 evidence. Failure returns to the smallest responsible packet.

## Phase 4 — Faithful cleanup quality and correction

### Packet 4A — Cleanup regression corpus and validator hardening

**Can run in parallel with:** Phase 3 before app composition changes
**Objective:** Freeze missing real-product cleanup cases before prompt/model tuning.

**Owned files:**

- `Tests/FleckAppTests/CleanupLexemeTests.swift`
- `Tests/FleckAppTests/CleanupProtectedSpanTests.swift`
- `Tests/FleckAppTests/FaithfulCleanupValidatorTests.swift`
- `Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift`

**Cases:** stray single letters, stutter/filler combinations, false starts, explicit corrections, lists, chemistry/technical terms, names, numbers/dates/URLs/paths/code/commands, negation/modality, prompt-shaped speech, long tails, malformed/late outputs.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(cleanup|cleaner|faithfulValidator|protected|mutableTail|processorUsesExactBaseline)'
```

**Gate:** this packet freezes red evidence only. A proven deterministic defect receives its own smallest source-repair packet; this test packet does not opportunistically edit product code.

### Packet 4B1 — Gemma cleanup product contract

**Depends on:** 1A, 3A, 4A
**Objective:** Make Gemma produce useful candidates more often without weakening the validator.

**Owned files:**

- `Sources/FleckApp/GemmaCleanupGenerator.swift`
- `Sources/FleckApp/LocalCleanupResponseEnvelope.swift`
- `Sources/FleckApp/GemmaCleanupProcessTransport.swift`
- `Sources/FleckApp/IncrementalTranscriptCleaner.swift`
- `Sources/FleckApp/DictationProcessingModels.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Tests/FleckAppTests/GemmaCleanupGeneratorTests.swift`
- `Tests/FleckAppTests/LocalCleanupResponseEnvelopeTests.swift`
- `Tests/FleckAppTests/GemmaCleanupProcessTransportTests.swift`
- `Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift`
- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`

**Required implementation:** versioned prompt, strict unchanged/cleaned envelope, bounded input/output/deadline, prompt-injection resistance, separate deterministic/model timing, and three explicit values in the processing result: raw ASR, immutable dictionary baseline, and latest validator-accepted faithful baseline. Replace the misleading dictionary-failure `.usedRaw` classification with stable, truthful outcome/reason cases. Rejected/late/cancelled generation returns the whole faithful baseline; history/routing still receive dictionary baseline separately.

**Red tests first:** user examples, stray `P`, no-op, list preservation, prompt-shaped transcript, multiple/late/truncated output, helper death/cancel, protected lexicon.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(cleanup|cleaner|faithfulValidator|processor|processing)'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(gemma|envelope)'
```

**Gate:** zero protected violations and target utility on frozen replay; do not claim model admission from unit tests.

### Packet 4B2 — Gemma qualification harness synchronization

**Depends on:** 4B1
**Objective:** Make the standalone native helper/qualification harness exercise the exact same prompt/envelope/deadline contract without changing product behavior.

**Owned files:**

- `Tools/GemmaCleanupBenchmark/NativeRuntime/Sources/GemmaCleanupHelper/GemmaCleanupRuntime.swift`
- `Tools/GemmaCleanupBenchmark/NativeRuntime/Sources/GemmaCleanupHelper/main.swift`
- `Tools/GemmaCleanupBenchmark/NativeRuntime/Tests/GemmaCleanupHelperTests/GemmaCleanupHelperTests.swift`
- `Tools/GemmaCleanupBenchmark/Corpus/english-qualification-v1.json`
- `Tools/GemmaCleanupBenchmark/Qualification/run-gemma-cleanup-qualification.sh`
- `Tools/GemmaCleanupBenchmark/Qualification/score_gemma_cleanup_qualification.swift`
- `Tools/GemmaCleanupBenchmark/Qualification/Tests/run-contract-tests.sh`

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh --package-path Tools/GemmaCleanupBenchmark/NativeRuntime '^GemmaCleanupHelperTests\.'
Tools/GemmaCleanupBenchmark/Qualification/Tests/run-contract-tests.sh
```

**Gate:** strict helper/score contract tests; corpus/prompt revision recorded; no model run or download in this packet.

### Packet 4C — History baseline schema

**Depends on:** 4B1
**Objective:** Persist enough explicit provenance for correction without conflating raw, dictionary, deterministic, and final text.

**Owned files:**

- `Sources/FleckCore/DictationModels.swift`
- `Sources/FleckCore/DictationHistoryStore.swift`
- `Tests/FleckCoreTests/DictationHistoryStoreTests.swift`

**Required implementation:** versioned optional `dictionaryBaseline` and `faithfulBaseline` fields; preserve existing raw/cleaned compatibility; strict size/privacy bounds; migration of existing records; no audio/model prompt/note body.

**Red tests first:** old-record decode, new round-trip, absent optional baselines, bounded lengths, corrupt migration, history-disabled behavior.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.dictationHistoryStore'
```

### Packet 4D — Receipt-safe correction transaction and suggestion classifier

**Depends on:** 3A, 3B, 4B1, 4C
**Objective:** Replace exactly the capture-owned insertion and derive only an explicit safe terminology proposal.

**Owned files:**

- `Sources/FleckCore/PersonalDictionarySuggestionClassifier.swift` — new
- `Tests/FleckCoreTests/PersonalDictionarySuggestionClassifierTests.swift` — new
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/AppState.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/AppStateDictationTests.swift`

**Required implementation:** opaque correction action token; `Use original` with dictionary baseline; explicit corrected text; exact insertion-receipt validation; one-contiguous-lexical-replacement classifier; suggestion handoff to the existing store; no arbitrary edit mining. The coordinator must also write raw ASR, dictionary baseline, faithful baseline, and final published text from the same immutable processing result into the 4C history record; it may not reconstruct or reread any stage value later.

**Red tests first:** stale/wrong/expired receipt, post-cancel correction, moved destination, correction rollback, unsafe multi-span suggestion, store handoff, history disabled, and an end-to-end coordinator record proving all four text stages remain distinct when deterministic and generated cleanup both participate.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.PersonalDictionarySuggestionClassifierTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(dictationCorrection|appStateDictation|correctionReceipt)'
```

**Gate:** stale/invalid receipt never string-replaces content; cancelled/rolled-back/history-off cases keep only bounded transient data and create no suggestion without explicit approval.

### Packet 4E — Correction presentation

**Depends on:** 2D, 4D
**Objective:** Expose correction without making the capsule or history a permanent editor.

**Owned files:**

- `Sources/FleckApp/DictationCapsule.swift`
- `Sources/FleckApp/DictationHistoryView.swift`
- `Tests/FleckAppTests/DictationCorrectionPresentationTests.swift` — new
- `Tests/FleckAppTests/DictationAccessibilityTests.swift`

**Required implementation:** one unobtrusive `Use original` / `Correct dictation…` action; local edit sheet; proposal approve/edit/dismiss handoff; disabled/actionable states for stale receipts; keyboard and VoiceOver behavior.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationCorrectionPresentationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationAccessibility'
```

## Phase 5 — Universal semantic sorting

### Packet 5A — Dictionary-aware cached retrieval

**Depends on:** 2B2, 2C, 4D
**Objective:** Let preferred forms and aliases corroborate the same concept while keeping the existing bounded in-memory index.

**Owned files:**

- `Sources/FleckApp/CachedNoteRoutingIndex.swift`
- `Sources/FleckApp/DynamicDestinationRouter.swift`
- `Sources/FleckApp/GemmaDestinationRouter.swift`
- `Sources/FleckApp/FoundationModelDictation.swift`
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/CachedNoteRoutingIndexTests.swift`
- `Tests/FleckAppTests/DynamicDestinationRouterTests.swift`
- `Tests/FleckAppTests/GemmaDestinationRouterTests.swift`
- `Tests/FleckAppTests/FoundationModelDictationTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/DictationSettingsTests.swift`
- `Tests/FleckAppTests/GemmaCleanupAppCompositionTests.swift`

**Required implementation:** introduce one compile-complete `DestinationRoutingRequest` migration across every production/test conformer and call site. The request carries the dictionary baseline, optional distinct accepted-cleanup text for the dependent 5B policy, candidates/Inbox, capture identity, dictionary revision/content digest, and routing-policy revision. In 5A every router preserves the current single-baseline decision behavior; the second text is carried but not yet allowed to affect a decision. Cache/query identity includes dictionary revision, dictionary content digest, and routing-policy revision; the routing lexicon is conflict-free; changed-note invalidation stays incremental; no note keyword is hard-coded; bounded passages/candidates stay unchanged unless measured.

**Red tests first:** universal unseen terms, aliases in transcript vs preferred form in note and reverse, conflicts, revision/digest invalidation, same revision with mismatched digest, duplicate titles, omitted-content completeness, performance ceiling.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(cachedRouting|dynamicDestination|gemmaDestination|coordinator)'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.GemmaCleanupAppCompositionTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(FoundationModelDictation|DictationRuntime.*Destination)'
```

**Gate:** no persistent vector store/embedding dependency; cached retrieval p95 target on controlled workspace.

### Packet 5B — Dual-evidence routing policy

**Depends on:** 4D, 5A
**Objective:** Route from both dictionary baseline and accepted cleanup without letting cleanup invent destination evidence.

**Owned files:**

- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DynamicDestinationRouter.swift`
- `Sources/FleckApp/GemmaDestinationRouter.swift`
- `Sources/FleckApp/FoundationModelDictation.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/DynamicDestinationRouterTests.swift`
- `Tests/FleckAppTests/GemmaDestinationRouterTests.swift`
- `Tests/FleckAppTests/FoundationModelDictationTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/DictationSettingsTests.swift`
- `Tests/FleckAppTests/GemmaCleanupAppCompositionTests.swift`

**Decision:** unchanged cleanup uses the baseline alone under existing unique corroboration gates; a distinct cleaned form may never provide sole destination evidence; baseline/cleaned agreement + unique margin -> auto-file; disagreement/close -> durable Inbox + chooser; absent/invalid/stale -> Inbox.

**Red tests first:** cleanup-only term, baseline/cleanup disagreement, exact title, unique body evidence, close candidates, malformed/tied judgment, cancellation, deleted note.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(dynamicDestination|dualEvidenceRouting|ambiguousRouting|routingFailure|coordinator)'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.GemmaCleanupAppCompositionTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(FoundationModelDictation|DictationRuntime.*Destination)'
```

**Gate:** zero wrong auto-route in frozen routing corpus; chooser recall 100%.

### Packet 5C — Content-free local-writing feedback journal

**Depends on:** 4E, 5B
**Objective:** Record bounded routing and cleanup outcome/correction alerts for local evidence without hidden learned rules or retained content.

**Owned files:**

- `Sources/FleckCore/LocalWritingFeedback.swift` — new
- `Sources/FleckCore/LocalWritingFeedbackStore.swift` — new
- `Sources/FleckApp/AppState.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Sources/FleckApp/DictationHistoryView.swift`
- `Tests/FleckCoreTests/LocalWritingFeedbackStoreTests.swift` — new
- `Tests/FleckAppTests/AppStateDictationTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/LocalWritingFeedbackPresentationTests.swift` — new

**Stored data:** stable codes, opaque feedback/capture/receipt IDs, model/policy revisions, offered/selected opaque note IDs, cleanup outcome/failure/correction categories, timestamps, review state, and expiration. No audio, transcript, note body, passage, prompt, score text, or content-derived embedding.

**Correlation contract:** a routed insertion stores a content-free feedback correlation containing capture ID, insertion receipt ID, original destination ID, and expiration. A later manual move counts as a wrong-auto-route event only when AppState proves that exact live receipt moved; note-title/text matching is forbidden.

An accepted cleanup may create a correction alert only from an explicit receipt-bound user action such as “use faithful baseline”/“cleanup was wrong”; a validator rejection, timeout, or deterministic fallback may create a stable diagnostic category without text. The Core store freezes `pendingAlerts(now:limit:)`, `dismiss(id:at:)`, `markReviewed(id:caseRevision:at:)`, cap, ordering, expiry, and idempotency semantics. Query returns only nonexpired content-free alerts; dismissal/review cannot alter a dictionary, route rule, cleanup prompt, model state, or ordinary note. 7D2 consumes this API rather than reconstructing outcomes from history text.

**Red tests first:** cleanup correction with wrong receipt, duplicate event, bounded eviction, stable ordering, expiry, idempotent dismiss/review, no-content encoding, route move after expiry, review case mismatch, and relaunch persistence.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.LocalWritingFeedbackStoreTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingFeedbackPresentationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(routingFeedback|cleanupFeedback|appStateDictation|choosingAmbiguous)'
```

**Gate:** an exact correlated manual move or explicit cleanup correction can create only a bounded content-free review alert; no event creates a rule, dictionary destination mapping, corpus case, or model update.

## Phase 6 — Immutable catalog and adaptive model lifecycle

### Packet 6A — Catalog/profile schema and validation

**Can run in parallel with:** Phase 2 core work and Phase 4A
**Objective:** Evolve the current one-descriptor-per-role types into immutable exact profiles/configurations without changing installation behavior.

**Owned files:**

- `Sources/FleckApp/AdmittedModelDescriptor.swift`
- `Sources/FleckApp/LocalModelCatalog.swift` — new
- `Tests/FleckAppTests/AdmittedModelDescriptorTests.swift`
- `Tests/FleckAppTests/LocalModelCatalogTests.swift` — new

**Required implementation:** family vs profile, system/Fleck/deterministic distribution, runtime ABI, support/resource/license/evidence/admission, separate human-readable configuration key and canonical configuration digest, hardware/OS plus claim-scope and speaker/acoustic cohort binding, closed manifest validation.

**Red tests first:** mutable revision/URL, unsafe paths, file set mismatch, arithmetic overflow, unknown license/evidence, system profile with fake artifacts, compound incompatibility, hardware/claim/speaker cohort mismatch, owner-private evidence in an ordinary build.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelCatalogTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(ordinaryConfiguration|admittedConfiguration|descriptorRole|defaultASRCatalog|cleanupCatalog|mixedRequestedLanguages|unsupportedHardware|spaceAboveDownloadBytes|invalidSignedDescriptorInputs)'
```

**Gate:** existing Parakeet/Gemma descriptors decode through compatibility adapters; no download behavior changes.

### Packet 6B — Exact research catalog snapshot

**Depends on:** 6A
**Objective:** Seed build-capability-specific immutable snapshots with already exact profiles only, with all candidate states `.notAdmitted` and safe built-ins represented truthfully.

**Owned files:**

- `Sources/FleckApp/LocalModelCatalogSnapshot.swift` — new compiled metadata so ordinary builds do not depend on the currently excluded Resources directory
- `Sources/FleckApp/LocalModelUpdateTransition.swift` — new nonselectable predecessor/successor verification and rollback metadata
- `Sources/FleckApp/Resources/ThirdPartyNotices.md` — only exact reviewed candidate notices; candidate builds only until promotion
- `Sources/FleckApp/Resources/GemmaCleanupNotice.md` — exact Gemma notice changes only if required by the reviewed profile
- `Tests/FleckAppTests/LocalModelCatalogTests.swift`
- `Tests/FleckAppTests/LocalModelUpdateTransitionTests.swift` — new

**Profiles:** the `ordinarySafe` snapshot contains only Apple Speech, deterministic cleanup/routing, and exact Apple system cleanup/routing cohorts; it contains no candidate names, manifests, notices, enhanced symbols, or update transitions. The compile-gated `developmentQuality` snapshot may additionally contain current exact Parakeet TDT v2 and current exact Gemma 1B cleanup/routing roles if their manifest/runtime/license records validate. TDT-CTC 110M enters only through 7H; auxiliary CTC only through conditional 7J; Gemma 270M through conditional 7L2; Unified/EOU only through an amended conditional 7K. The later signed-distribution snapshot contains only the exact promotion-authorized tuple plus safe fallbacks as selectable profiles/configurations. A successor build may additionally embed exactly one nonselectable `LocalModelUpdateTransition` derived from a verified previously release-admitted package and the current D5 promotion; it contains exact retired predecessor configuration/profile/artifact/receipt verification metadata, the externally pinned trust-policy sequence/checkpoint shared unchanged by predecessor and successor admission, the ordered predecessor corpus checkpoint/head/seal/evaluation-signer dependency chain reopened at build time, and bounded rollback policy but cannot satisfy lookup, recommendation, selection, or admission. A predecessor from an older trust checkpoint or with a later corpus invalidation is ineligible because this version has no historical-signer ledger or stale-corpus exception.

**Transition validation:** the identity digest covers the previous D7/package/configuration/profile/artifact/receipt-schema/runtime-compatibility tuple, current D5/successor tuple, closed predecessor/successor artifact manifests, predecessor-verification trust-policy sequence/checkpoint, the canonical ordered predecessor corpus dependency chain, checked side-by-side/staging/rollback bytes, reference roles, rollback duration, and transition schema. Reject missing/duplicate/reordered/stale corpus dependencies, a consumed-lineage invalidation, missing/duplicate/mutable artifact manifests, predecessor equal to successor, non-D7 predecessor, successor not equal to the promotion tuple, unsupported receipt/runtime compatibility, absent or mismatched trust anchor, predecessor D7 from any noncurrent checkpoint, insufficient rollback reserve, multiple transitions, or any transition in ordinary/development snapshots. No transition means Update is unavailable rather than inferred.

**Initial exact configurations:** Built-in Safe; Apple Speech + Apple Foundation cleanup + deterministic routing; Apple Speech + deterministic cleanup + Apple Foundation routing; Apple Speech + both Apple Foundation roles for each exact supported OS cohort; Parakeet-v2 + deterministic cleanup/routing; Parakeet-v2 + Gemma-1B cleanup + deterministic routing; Parakeet-v2 + deterministic cleanup + Gemma-1B routing; and Parakeet-v2 + both Gemma-1B roles. Each has its own canonical identity and evidence state. This preserves the current Apple Speech/Foundation path where that system capability is actually available. An unavailable/unadmitted optional role cannot execute through a fallback list: recommendation selects the separately admitted deterministic-role tuple. Later Parakeet+Apple and challenger mixtures enter only as exact separately tested rows.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelCatalogTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelUpdateTransitionTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(ordinarySafeCatalogExcludesCandidates|developmentQualityCatalogIncludesExactCandidates|signedSnapshotRejectsUnpromoted)'
```

**Gate:** research entries cannot appear as normal selectable/recommended profiles; transition metadata cannot execute as a profile or broaden the one promoted successor tuple.

### Packet 6B2 — Historical evaluation archive reconciliation

**Depends on:** 1A, 6B
**Objective:** Preserve exact prior Whisper, Nemotron, Qwen, and rejected-cleanup evidence without making any historical candidate installable or selectable.

**Owned files:**

- `Sources/FleckModelEvaluation/LocalModelEvaluationArchive.swift` — new strict content-free archive index
- `Tests/FleckModelEvaluationTests/LocalModelEvaluationArchiveTests.swift` — new
- `docs/evaluation/local-writing-evaluation-archive.md` — new generated/reviewed status index with no private cases

**Required implementation:** reconcile existing branch/commit/revision/profile/evidence identities; import only records whose source, artifact/profile, corpus class, hardware, and result hashes are provable; preserve rejection/supersession reason and evidence tier; mark unverifiable records as `documentedOnly`, never upgrade them. The archive is evaluator/development metadata, excluded from ordinary runtime recommendation and installation. Private detailed evidence stays outside Git; the checked-in index has stable IDs/hashes/outcome codes only.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalModelEvaluationArchiveTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.(archiveContainsWhisper|archiveContainsNemotron|archiveContainsQwen|archivePreservesDocumentedOnly|archivePreservesRejected)'
```

**Gate:** every historical row is traceable or explicitly `documentedOnly`; no archive row can satisfy a catalog install/recommendation/admission gate.

### Packet 6B3 — Canonical release-evidence verification vocabulary

**Depends on:** 1A, 6A, 6B2
**Objective:** Land one strict, read-only public vocabulary for D6, D7, trust-policy checkpoints, and future-update predecessor records before any packet needs to verify a retained predecessor. This packet cannot create, sign, admit, recommend, or distribute anything.

**Owned files:**

- `Sources/FleckModelEvaluation/LocalWritingReleaseAdmission.swift` — new canonical D6/D7 payloads and pure strict verification
- `Sources/FleckModelEvaluation/LocalWritingAdmissionTrustPolicy.swift` — new canonical trust-policy/checkpoint payloads and pure strict verification
- `Sources/FleckModelEvaluation/LocalWritingUpdatePredecessorRecord.swift` — new canonical future-successor record and pure strict verification
- `Sources/FleckModelEvaluator/ReleaseAdmissionCommand.swift` — new verification-only command adapter
- `Sources/FleckModelEvaluator/main.swift` — add verification-only dispatch
- `Tests/FleckModelEvaluationTests/LocalWritingReleaseAdmissionTests.swift` — new strict codec/verifier fixtures
- `Tests/FleckModelEvaluationTests/LocalWritingAdmissionTrustPolicyTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingUpdatePredecessorRecordTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingReleaseAdmissionVerificationCommandTests.swift` — new

**Required implementation:** a canonical strict decoder for the unsigned content-addressed D6 evidence receipt, plus canonical RFC 8785/NFC payload and detached CMS envelope decoders for D7 admission, trust policy/checkpoint, and update-predecessor record; strict unknown/duplicate-key, integer, array-order, digest, certificate, policy-sequence, package, transition, current-corpus, and ordered recursive-dependency verification. Freeze read-only `verify-admission-trust-policy`; `verify-admission-trust-checkpoint --policy --checkpoint --expected-policy-sequence --expected-policy-checkpoint-digest --expected-fingerprint`; `verify-d6-evidence`; `verify-release-admission`; and `verify-update-predecessor-record` commands with the complete external public artifact, live corpus dependency, expected trust checkpoint, and reviewed fingerprint inputs used later in 9D/9E. The exact repeatable transitive input syntax for every command in this program is `--predecessor-corpus-dependency <absolute-descriptor-path>`, supplied once per older signed dependency in canonical admission order. Each mode-`0600` descriptor under a selected `0700` root is strict canonical JSON with exactly `predecessorAdmissionSHA256`, `ledgerPath`, `checkpointPath`, `sealPath`, `expectedCurrentHeadSHA256`, and `expectedEvaluationSignerFingerprintSHA256`; all paths are canonical absolute nonsymlink paths. The descriptor is convenience input, never authority: the command opens and verifies every named live artifact, derives the signed tuple, requires exact ordinal/digest equality with the admission/transition dependency array, and rereads each checkpoint immediately before accepting output. Zero options means the signed dependency array must be empty; missing, extra, duplicate, or reordered options fail. The pure APIs accept immutable byte buffers and explicitly supplied paths/expected values; they never discover a “latest” file, write product state, use a network, or consult an app preference. Test fixtures may be locally signed ephemeral envelopes only. Creation/signing/bootstrap/rotation/revocation commands remain absent until 9E and must reuse these exact types and verifiers rather than introduce a second schema.

The D6 schema is deliberately self-contained for immutable release provenance. Creation embeds the unchanged canonical content-free final package receipt and notary receipt bytes as bounded base64 fields, stores their recomputed digests, and binds the ZIP/app/signing/channel identities derived from them. `verify-d6-evidence` therefore does not accept a second mutable package/notary path: it strict-decodes and revalidates those embedded bytes, checks them against the explicitly supplied final ZIP/app plus all D5/final-run source receipts and live corpus inputs, and fails on any noncanonical byte or digest mismatch. D7 and update-predecessor verifiers likewise reopen the embedded D6 package/notary receipts and require any separately supplied package receipt to match byte-for-byte. This is the only exception to “external public artifact” above; no verification trusts a digest-only D6 claim.

**Red tests first:** unknown/duplicate keys; noncanonical JSON; float/overflow; wrong or revoked certificate; stale/forked policy sequence; changed ZIP/app/package/D6/D7/update digest; `none` transition with predecessor inputs; `executedTransition` without the exact current predecessor ledger/checkpoint/seal/head/evaluation signer; missing/reordered transitive dependency; invalidation after the predecessor-bound head; and any attempt to dispatch a create/sign/admit command from this packet.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingReleaseAdmissionTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingAdmissionTrustPolicyTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingUpdatePredecessorRecordTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingReleaseAdmissionVerificationCommandTests/'
```

**Gate:** retained predecessor evidence can be strictly verified through one reusable vocabulary, while every create/sign/admit entry point is provably absent.

### Packet 6C — Deterministic hardware recommender

**Depends on:** 1B, 1C, 6A, 6B
**Objective:** Select exactly one admitted configuration or Built-in Safe.

**Owned files:**

- `Sources/FleckApp/LocalModelRecommendation.swift` — new
- `Sources/FleckApp/DictationResourceProfile.swift`
- `Tests/FleckAppTests/LocalModelRecommendationTests.swift` — new
- `Tests/FleckAppTests/DictationResourceProfileTests.swift`

**Required implementation:** hard eligibility gates, hardware/OS + claim-scope + speaker/acoustic evidence matching, active build-capability matching, storage/staging arithmetic, deterministic rank, reason codes, freshness/cooldown, fail-closed unknown probes. Owner-private evidence is eligible only in an explicit owner-private build capability; it never recommends a model in an ordinary/general-release build.

**Red tests first:** 8 GB vs roomier, pressure/thermal/Low Power, unknown machine, stale/missing evidence, insufficient staging, legal blocker, no installed enhanced profile, owner-private vs ordinary capability, speaker/acoustic mismatch, tie determinism.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelRecommendationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(resourceSampling|resourceProfile|resourceSnapshot|unrecognizedThermal)'
```

**Gate:** vendor benchmarks never enter scoring; same inputs always produce same result.

### Packet 6D1 — Joint lease and lifecycle policy

**Depends on:** 6C, 3E, 4B1, 5B
**Objective:** Consolidate the existing runtime/scheduler policies and enforce ASR-to-cleanup-to-routing lease handoff without composing them into the app yet.

**Owned files:**

- `Sources/FleckApp/LocalDictationRuntime.swift`
- `Sources/FleckApp/DictationRuntimePolicy.swift`
- `Sources/FleckApp/DictationInferenceScheduler.swift`
- `Sources/FleckApp/DictationResourcePressureMonitor.swift`
- `Sources/FleckApp/AdaptiveEnhancedSpeechInference.swift`
- `Sources/FleckApp/GemmaCleanupCandidateComposition.swift`
- `Sources/FleckApp/DynamicCleanupGenerator.swift`
- `Tests/FleckAppTests/LocalDictationRuntimeTests.swift`
- `Tests/FleckAppTests/DictationRuntimePolicyTests.swift`
- `Tests/FleckAppTests/DictationInferenceSchedulerTests.swift`
- `Tests/FleckAppTests/DictationResourcePressureMonitorTests.swift`
- `Tests/FleckAppTests/AdaptiveEnhancedSpeechInferenceTests.swift`
- `Tests/FleckAppTests/GemmaCleanupAppCompositionTests.swift`
- `Tests/FleckAppTests/DynamicCleanupGeneratorTests.swift`

**Required implementation:** one mutation barrier; phase-aware leases; 8 GB no concurrent ASR/cleanup models; cleanup and routing may share one Gemma artifact lease under an exact operation-authorized `developmentCandidate` configuration in Quality builds or an admitted exact configuration in normal product use; warm/idle/hibernating/cold transitions; pressure/thermal/power/sleep/failure release; content-free lifecycle receipts. Candidate and admitted receipts/states may never be interchanged. Dictation fallback resolution is preflight/next-capture only: once enhanced capture starts, failure publishes nothing and cannot replay into Apple Speech. Cleanup/routing may fall back in the same transaction only from the immutable dictionary/faithful baseline and within the same deadline/cancellation authority.

**Additional red tests:** enhanced start then failure does not invoke Apple on the same PCM/capture; next capture may preflight to Apple; cleanup timeout uses faithful baseline; routing failure uses Inbox; cancellation prevents every fallback publication.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(dictationRuntime|scheduler|resourcePressure|dynamicCleanup)'
```

**Gate:** current specialized Parakeet policy is folded into, not duplicated beside, the one scheduler.

### Packet 6D2 — Pinned model identity propagation

**Depends on:** 5C, 6D1
**Objective:** Carry one exact model configuration identity through processing, routing/cache, persistence, and app-stage receipts before composing the runtime.

**Owned files:**

- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationProcessingModels.swift`
- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Sources/FleckApp/CachedNoteRoutingIndex.swift`
- `Sources/FleckApp/DynamicDestinationRouter.swift`
- `Sources/FleckApp/GemmaDestinationRouter.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckCore/DictationModels.swift`
- `Sources/FleckCore/DictationHistoryStore.swift`
- `Tests/FleckAppTests/DictationProcessingModelsTests.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/CachedNoteRoutingIndexTests.swift`
- `Tests/FleckAppTests/DynamicDestinationRouterTests.swift`
- `Tests/FleckAppTests/GemmaDestinationRouterTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckCoreTests/DictationHistoryStoreTests.swift`
- `Tests/FleckAppTests/PinnedModelIdentityPropagationTests.swift` — new cross-stage identity suite
- `Tests/FleckCoreTests/DictationHistoryModelIdentityTests.swift` — new persistence/migration identity suite

**Required implementation:** bind catalog revision, configuration key/digest, exact dictation/vocabulary/cleanup/routing profile digests, and resource-policy revision into the pinned capture context, processor result, routing cache/query key, durable history record, persistence correlation, and app-stage receipt. Extend the 4C history schema with an optional versioned identity envelope and migrate older rows to explicit `legacyUnknown` rather than fabricating an identity. A stage may acknowledge only the role profile named by that context; a candidate result without the full envelope cannot be published as candidate evidence.

**Red tests first:** exact Built-in Safe identity, configuration-digest mismatch, role-profile mismatch, catalog mutation during capture, stage receipt mismatch, Settings change applies to next capture, candidate stage with anonymous identity rejected.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.PinnedModelIdentityPropagationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.DictationHistoryModelIdentityTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(cachedRouting|dynamicDestination|gemmaDestination|processing)'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.dictationHistoryStore'
```

**Gate:** no app stage or routing cache/query can run with anonymous, stale, or mismatched configuration/profile identity.

### Packet 6D3 — Runtime product composition

**Depends on:** 6D2
**Objective:** Pass the real runtime/scheduler and exact identity through candidate composition and populate lease measurements.

**Owned files:**

- `Sources/FleckApp/StreamingDictationProcessor.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/StreamingDictationProcessorTests.swift`
- `Tests/FleckAppTests/GemmaCleanupAppCompositionTests.swift`

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.GemmaCleanupAppCompositionTests/'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.(runtimeComposition|processing)'
```

**Gate:** `StreamingDictationProcessor(runtime:)` is non-nil in enhanced composition; ordinary safe composition is unchanged; no second scheduler; candidate stages require exact identity.

### Packet 6D4 — Lifecycle stress verification

**Depends on:** 6D3
**Objective:** Prove concurrency/lifecycle invariants without broadening implementation ownership.

**Owned files:**

- `Tests/FleckAppTests/LocalWritingRuntimeStressTests.swift` — new

**Cases:** rapid capture/cancel, cleanup-to-routing reuse, model mutation waiting, pressure during every phase, sleep/wake, helper failure, repeated load/unload, concurrent Settings action, no deadlock/no late publication.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.LocalWritingRuntimeStressTests/'
```

**Gate:** feature-flagged nonzero stress run passes. Any defect returns as a new smallest owned repair packet; the stress packet does not opportunistically edit product source.

### Packet 6E — Model Settings and Advanced catalog

**Depends on:** 2D, 4E, 6B, 6B3, 6C, 6D4
**Objective:** Present one recommendation and compact truthful actions while retaining the existing installer.

**Owned files:**

- `Sources/FleckApp/AdmittedModelInstallation.swift`
- `Sources/FleckApp/AdmittedModelSettingsPresentation.swift`
- `Sources/FleckApp/SettingsView.swift`
- `Tests/FleckAppTests/AdmittedModelInstallationTests.swift`
- `Tests/FleckAppTests/AdmittedModelSettingsPresentationTests.swift`
- `Tests/FleckAppTests/DictationSettingsTests.swift`
- `Tests/FleckAppTests/DictationAccessibilityTests.swift`

**Required implementation:** Dictation/Cleanup rows; recommendation rationale; collapsed admitted alternatives; real byte/stage progress; retry/repair/update/remove; no unadmitted normal choices; detail sheet for identity/license/evidence. Installation/readiness/removal is keyed by exact artifact receipt with catalog-derived role references: shared Gemma downloads once, repair gates both cleanup/routing roles, and removal previews/drains both roles and deletes the tree only after no selected/rollback configuration references it. Update appears only for one verified nonselectable 6B transition matching the installed previously admitted configuration and this build's promoted successor. It checks side-by-side staging plus rollback reserve, stages/verifies/smokes all successor roles, atomically switches the whole configuration/reference graph, and keeps the exact predecessor receipts undeletable for the bounded rollback duration. Termination/failure before the switch leaves the predecessor selected; post-switch failure or explicit rollback atomically restores it. No transition, mismatched old receipt, expired/revoked predecessor, insufficient reserve, or unsafe compatibility produces a short unavailable reason and no Update action; Settings never manufactures a transition from model family names.

**Red tests first:** new transition cases use the `signedTransition...` prefix and cover exact signed transition visibility, no-transition absence, wrong predecessor/D7/package/receipt/runtime identity, checked staging+rollback capacity, interruption before switch, post-switch smoke failure, atomic whole-configuration update/rollback, rollback after relaunch, and rollback-window reference retention/expiry. Existing cases cover one Gemma artifact/two role profiles, reference reconstruction after relaunch, one-role admission failure, shared repair failure, remove while either lease is active, remove while rollback still references, scoped delete, and UI showing one storage action rather than duplicate downloads.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(defaultBuild|admittedStorage|existingDictation|fakeInstall|checksumFailure|refresh|liveCapacity|removeDeletes|admittedInstaller|cancellation|descriptor|installer|immutableArtifact|artifact|manager|builtIn|modelLabel|cleanup|ordinaryStates|onlyActionable|recommendation|recommended|noRecommendation|repairRequired|ready|downloading|everySettings|inProgress|failedRecommended|settingsActions|releasing|orderedInstaller|currentApp|nilSigned|architectureMismatch|languageMismatch|mixedRequested|insufficient|supportedHardware|defaultASRFactory|cleanupFactory|invalidSigned|storageNamespace|DictationSettings|DictationAccessibility)'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.signedTransition'
```

**UI gate:** newest accepted Fleck UI preserved; native system colors/spacing; one primary action; accessibility labels; reduced-motion compliance; no generic indefinite Loading.

## Phase 7 — Candidate adapters, corpus runner, and qualification

### Packet 7A — Private corpus runner and scorer

**Depends on:** 1A, 1B, 1C, 6A, 6B3, 6D2
**Objective:** Extend the existing scorer/evidence types to schedule and score local-writing cases; do not own candidate subprocess execution.

**Owned files:**

- `Package.swift` — add the zero-dependency local evidence-contract package and make `FleckModelEvaluation` depend on its product
- `Packages/LocalWritingEvidenceContracts/Package.swift` — new standalone package with no package dependencies
- `Packages/LocalWritingEvidenceContracts/Sources/LocalWritingEvidenceContracts/LocalWritingPredecessorCorpusSnapshot.swift` — new shared strict content-free snapshot/proof envelope vocabulary
- `Packages/LocalWritingEvidenceContracts/Tests/LocalWritingEvidenceContractsTests/LocalWritingPredecessorCorpusSnapshotTests.swift` — new
- `Sources/FleckModelEvaluation/LocalWritingCorpusRunner.swift` — new
- `Sources/FleckModelEvaluation/LocalWritingScoring.swift` — new
- `Sources/FleckModelEvaluation/LocalWritingCorpusAdmissionSeal.swift` — new strict CMS signing/verification and suffix-policy enforcement
- `Sources/FleckModelEvaluation/LocalWritingEvaluationCommand.swift` — new validated evaluator command/IO contract
- `Sources/FleckCore/LocalWritingQualitySummary.swift` — new content-free canonical summary/envelope and strict verifier shared with the app
- `Sources/FleckModelEvaluation/LocalWritingEvidence.swift`
- `Sources/FleckModelEvaluation/ModelEvaluation.swift`
- `Sources/FleckModelEvaluation/CandidateBenchmarkEvidence.swift`
- `Sources/FleckModelEvaluator/main.swift`
- `Tests/FleckModelEvaluationTests/LocalWritingCorpusRunnerTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingScoringTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingCorpusAdmissionSealTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingEvaluationCommandTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingComparisonEvidenceTests.swift` — new cross-device content-free envelope/import suite
- `Tests/FleckModelEvaluationTests/LocalWritingEvidenceTests.swift`
- `Tests/FleckModelEvaluationTests/ModelEvaluationTests.swift`
- `Tests/FleckModelEvaluationTests/CandidateBenchmarkEvidenceTests.swift`
- `Tests/FleckCoreTests/LocalWritingQualitySummaryTests.swift` — new

**Required implementation:** manifest/hash validation, execution-variant schedule, per-stage scoring, source-class-separated aggregates, controlled-workspace routing oracle, resumable run checkpoint without partial authoritative results, exact catalog/configuration/role-profile identity in every authoritative run, claim/speaker cohort binding, and explicit mapping to existing WER/protected/evidence types. Before resolving a candidate-visible audio path or starting candidate execution, atomically append the 1A exposure event and bind its digest into the raw/result receipt; failure blocks execution, and a crash still leaves the exposure durable. Scoring reopens the entire ledger chain and, for each consumed case/profile/material lineage, rejects when that matching exposure event was appended after its own candidate access/output or when a later invalidation targets that lineage; unrelated later-case exposure events remain a valid ordered suffix. It excludes every `diagnosticOnlyPostExposure` case or reused material lineage. Every private per-case result and run receipt preserves the distinct raw ASR, immutable dictionary baseline, latest validator-accepted `faithfulBaseline`, cleanup decision/failure, and final published text so deterministic cleanup is never hidden inside a generic fallback outcome.

The predecessor snapshot and proof-envelope types live in the dedicated `LocalWritingEvidenceContracts` product so the root evaluator and the later standalone acceptance harness share one strict schema without making the harness depend on the root Fleck package. That package has zero package dependencies and may import only the Swift standard library/Foundation facilities available in the declared toolchain. Its own `Package.resolved` must remain absent. Adding the local path dependency must not change the already pinned root `Package.resolved`; Packet 0D's lock canary fails either mutation or creation.

Freeze twenty-one `fleck-model-eval local-writing` CLI contracts: `validate-corpus --manifest`; `verify-corpus-ledger --ledger --checkpoint --output`; `export-corpus-ledger-extension --ledger --after-checkpoint --signing-identity --output`; `import-corpus-ledger-extension --bundle --ledger --checkpoint --expected-fingerprint --output-checkpoint`; `create-corpus-admission-seal --ledger --checkpoint --expected-fingerprint --signing-identity --output`; `verify-corpus-admission-seal --seal --ledger --checkpoint --expected-fingerprint --output`; `score-run --plan --raw-receipts --output`; `verify-score --receipt --summary-output`; `compare-runs --left --right --output`; `compare-role-matrix --matrix --receipts-root --output`; `export-comparison-evidence --receipt ... --ledger-extension --signing-identity --output`; `verify-comparison-evidence --bundle --expected-package-receipt`; `import-comparison-evidence --bundle --expected-package-receipt --output-root`; `create-promotion-record --test-package-receipt --mac-mini-run --mac-mini-score --m1-run --m1-score --comparison --corpus-ledger-verification-receipt --corpus-seal-verification-receipt --signing-identity --output`; `verify-promotion-record --record --test-package-receipt --mac-mini-run --mac-mini-score --m1-run --m1-score --comparison --corpus-ledger-verification-receipt --corpus-seal-verification-receipt`; `export-promotion-evidence --record --test-package-receipt --mac-mini-run --mac-mini-score --m1-run --m1-score --comparison --corpus-ledger-verification-receipt --corpus-seal-verification-receipt --signing-identity --output`; `verify-promotion-evidence --bundle --test-zip`; `import-promotion-evidence --bundle --test-zip --output-root`; `create-predecessor-corpus-snapshot --update-record --admission-record --d6-evidence --notary-evidence --zip --package-receipt --app --successor-package-receipt --d5-promotion-root --d5-test-zip --mac-mini-run --mac-mini-score --mac-mini-update --m1-run --m1-score --m1-update --comparison --corpus-ledger --corpus-ledger-checkpoint --corpus-admission-seal --expected-corpus-head --expected-evaluation-fingerprint --predecessor-corpus-mode [mode-specific immediate predecessor inputs] --trust-policy --trust-policy-checkpoint --expected-policy-sequence --expected-policy-checkpoint-digest --expected-fingerprint [--predecessor-corpus-dependency <absolute-descriptor-path>]... --signing-identity --output`; `verify-predecessor-corpus-snapshot --snapshot --update-record --admission-record --d6-evidence --notary-evidence --zip --package-receipt --successor-package-receipt --expected-corpus-head --expected-evaluation-fingerprint --trust-policy --trust-policy-checkpoint --expected-policy-sequence --expected-policy-checkpoint-digest --output`; and `import-predecessor-corpus-snapshot --snapshot --update-record --admission-record --d6-evidence --notary-evidence --zip --package-receipt --successor-package-receipt --expected-corpus-head --expected-evaluation-fingerprint --trust-policy --trust-policy-checkpoint --expected-policy-sequence --expected-policy-checkpoint-digest --output-root`.

The ledger and seal commands use exactly the short signatures listed above; no blanket hidden arguments are implied. The score/comparison/promotion evidence family—`score-run`, `verify-score`, `compare-runs`, `compare-role-matrix`, all comparison-evidence commands, and all promotion-record/evidence commands—additionally requires the canonical current `--corpus-ledger`, `--corpus-ledger-checkpoint`, expected head/corpus identity, and reviewed evaluation-signer fingerprint shown at its executable call sites; D5-and-later members also require the live `--corpus-admission-seal`. Each proves every receipt-bound earlier head is an ancestor, the seal suffix contains only exposure events, and no later invalidation targets a consumed lineage; supplying an old but internally valid checkpoint fails. They accept canonical absolute private-root paths, write atomically, reject missing/duplicate/partial cases and identity drift, keep E1/E2/E3 separate, and emit one authoritative aggregate receipt only after every required case and zero-event gate reconciles. `verify-score` refuses an existing or inferred sibling summary path and atomically writes the strict content-free FleckCore envelope only to the explicit new `--summary-output`; that exact file is the sole Quality Lab import artifact. `compare-role-matrix` consumes only already verified, one-configuration aggregate receipts and rejects duplicate/missing identities; it never creates a multi-configuration aggregate that could mask one role's failure.

The comparison-evidence export is a strict, canonical, content-free CMS-signed envelope over an allowlisted set of already verified run/score/comparison receipts plus the verified eligibility-ledger extension/checkpoint, and every CMS create/export command requires an explicit approved keychain `--signing-identity`. The standalone `import-corpus-ledger-extension` command is the single mutating ledger import: it requires the reviewed signer and the extension parent to equal the destination's current head, then atomically fast-forwards that ledger and checkpoint exactly once. `verify-comparison-evidence` and `import-comparison-evidence` run only after that fast-forward; both require the bundle's embedded extension child/checkpoint and digest to equal the destination's now-current head and the separately imported extension, and neither mutates or reapplies the ledger. They revalidate every embedded receipt digest against the separately transferred package receipt, reject forks/private transcript/audio fields and unsafe/duplicate names, and the import writes receipts atomically beneath a new `0700` destination. Thus the signed standalone extension is the only cross-device ledger mutation input, while the comparison bundle is the only cross-device comparison-receipt input accepted by 9C and 9D2.

The predecessor-corpus snapshot family is available only for an immutable final package whose signed transition state is `executedTransition`. Creation first invokes Packet 6B3's full strict `verify-update-predecessor-record` path over the predecessor update record, D7 admission, D6 evidence, retained ZIP/package, the complete retained D5/final run-score-update/comparison source group, current externally pinned trust checkpoint, current canonical predecessor ledger/checkpoint/seal, and every older predecessor corpus dependency named by that admission in exact signed order. It uses Packet 6B3's exact repeatable `--predecessor-corpus-dependency <absolute-descriptor-path>` option; no other grouping syntax exists. The creator reopens every latest checkpoint immediately before signing, binds the successor package receipt and embedded transition digest, and emits a canonical content-free CMS envelope under the reviewed evaluation identity. Verify and import do not invoke the source-heavy update-predecessor verifier remotely: they cryptographically verify the already signed content-free snapshot and its bound public update/D7/D6/notary/package chain, require the exact predecessor and successor public receipts, expected current predecessor head/evaluation fingerprint, expected policy sequence/checkpoint, snapshot CMS signer, and an exact ordered match between the snapshot's recursive dependency tuples and the signed successor transition. They derive the expected ordered tuples from that transition and therefore neither accept live dependency descriptors nor invent a second grouping syntax. Neither command accepts raw audio, transcript text, private corpus paths, or an unbound dependency. Import writes exactly `predecessor-corpus-snapshot.json`, `snapshot-verification-receipt.json`, and `snapshot-import-receipt.json` atomically beneath a new `0700` root. The remote snapshot authorizes only the named 9D2 update test; it cannot mutate a ledger, independently re-admit the predecessor, or replace the live Mac-mini reopening required by D6/D7.

The promotion-evidence bundle is a separate strict schema with exactly these collision-safe member names: `d5-promotion-record.json`, `d5-corpus-ledger-checkpoint.json`, `d5-corpus-ledger-verification-receipt.json`, `d5-corpus-admission-seal.json`, `d5-corpus-seal-verification-receipt.json`, `test-package-receipt.json`, `mac-mini-run-receipt.json`, `mac-mini-score-receipt.json`, `m1-run-receipt.json`, `m1-score-receipt.json`, and `two-device-comparison.json`. Export first re-verifies the live canonical authoritative ledger/checkpoint and detached seal under the reviewed evaluation signer, proves the D5 head is an ancestor with an exposure-only suffix and no consumed-lineage invalidation, and recomputes the D5 record from those exact inputs. Verify/import repeat that computation, reject private case/audio/transcript fields and any extra/missing/renamed member, and write atomically under a new empty `0700` root. Import also preserves the exact canonical source envelope as reserved `promotion-evidence-bundle.json` and emits `promotion-import-receipt.json` binding its digest, member digests, test-ZIP digest, source/destination paths, and importer revision; neither is treated as an embedded member during recursion checks. Its manifest binds the separately transferred 9A test-ZIP digest; the ZIP is never embedded in the content-free bundle. D6 must reopen `promotion-evidence-bundle.json`, every fixed member, and the import receipt, verify the exact 9A ZIP against its package receipt, then verify the bundled D5 checkpoint is an ancestor of the live authoritative ledger, the seal remains valid, and no relevant invalidation exists rather than trusting the D5 digest embedded in the final app.

**Additional red tests:** exposure append failure before launch; output preceding exposure; candidate crash after exposure; truncated/forked/reordered ledger; post-exposure oracle revision reusing audio/material; fresh blinded replacement; D5 export with a swapped live/score pair, changed 9A package receipt/ZIP digest, missing E stratum, mismatched corpus/config/profile/cohort, changed comparison, private field, renamed/duplicate member, unsafe import path, nonempty destination, and a promotion record that is internally valid but not recomputable from the supplied source receipts. Snapshot tests reject a stale or advanced predecessor head, invalid seal, wrong evaluation signer, changed policy checkpoint, swapped predecessor or successor package, missing/reordered recursive dependency, private field, unsafe/nonempty import root, and reuse for any transition other than the one bound by its successor receipt.

The verified aggregate summary is a content-free strict FleckCore envelope over the aggregate payload, plan/run/scorer revision, E-level strata, corpus/config/profile digests, result codes, and evaluator verification receipt digest. `verify-score` writes it only after recomputing the authoritative private receipt; FleckApp can independently strict-decode/recompute the canonical summary digest and require an exact selected plan/corpus/config match without depending on the evaluation target. The UI labels it as a local Quality report, never release admission; importing a file cannot alter a recommendation or catalog state.

The D5 promotion record is canonical evaluator output, not a hand-authored flag. It binds the exact 9A test ZIP/app-tree/executable receipt; catalog/configuration/profile/resource-policy identities; corpus, dictionary, controlled-workspace, threshold, hardware, operator/speaker, and claim-scope cohorts; current eligibility-ledger checkpoint/head and verification receipt; detached admission seal and seal-verification receipt; both device live-run and independently verified score receipts; the cross-device comparison; every zero-event gate; and the explicit D5 decision. Its payload digest is content-addressed and its envelope requires the explicitly reviewed local evaluation signer used for the ledger extensions and seal. Verification reopens the live authoritative ledger/seal plus both run/score pairs and fails on any consumed-lineage invalidation, non-exposure seal suffix, stale/forked head, wrong signer, missing E1/E2/E3 stratum, package mismatch, broadened scope, or nonpassing gate. D5 does not itself authorize signing, distribution, or D7 admission.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingCorpusRunnerTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingScoringTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingCorpusAdmissionSealTests/'
Scripts/run-nonempty-swift-tests.sh --package-path Packages/LocalWritingEvidenceContracts '^LocalWritingEvidenceContractsTests\.LocalWritingPredecessorCorpusSnapshotTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingEvidenceTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingEvaluationCommandTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingComparisonEvidenceTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.LocalWritingQualitySummaryTests/'
```

**Gate:** no private audio/text copied into Git or public summaries; scorer revision frozen before candidate runs.

### Packet 7B — Candidate adapter JSONL evidence bridge

**Depends on:** 7A
**Objective:** Extend the separate adapter package's strict JSONL protocol with raw stage/resource/lifecycle receipts that the root evaluator can map.

**Owned files:**

- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/CandidateAdapterModels.swift`
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/JSONLinesCodec.swift`
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateCLI/BenchmarkRun.swift`
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateCLI/main.swift`
- `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/CandidateAdapterProtocolTests.swift`
- `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/BenchmarkRunTests.swift`
- `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/AdmissionCLITests.swift`

**Boundary:** the tool emits raw versioned execution events; `fleck-model-eval` owns canonical scoring/admission mapping. Golden fixtures in both packages prove schema compatibility without copying scoring logic.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalDictationCandidateAdapters '^LocalDictationCandidateAdaptersTests\.'
```

### Packet 7C — Packaged injected-audio path

**Depends on:** 6D3, 7A, 7D3
**Objective:** Add a development-only packaged E2 path that drives the production processor with exact corpus PCM and emits private local receipts.

**Owned files:**

- `Sources/FleckApp/LocalWritingQualityRunConfiguration.swift` — new
- `Sources/FleckApp/InjectedLocalWritingSpeechSource.swift` — new
- `Sources/FleckApp/LocalWritingQualityRunController.swift` — new
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/LocalWritingQualityRunControllerTests.swift` — new

**Required implementation:** enhanced/debug compile gate; validated corpus-root-relative inputs; production dictionary/cleanup/routing/persistence path against the exact 7D3 provisioned/reset controlled workspace; a durable 1A exposure event before PCM becomes processor-visible; named output root; atomic per-case and pre/post workspace receipts; cancellation/fault stages; no normal UI or release symbols.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.LocalWritingQualityRunControllerTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.qualityInjectionAbsentFromOrdinaryBuild'
```

**Gate:** ordinary build/source scan proves the launch arguments and injected source are unreachable or absent; E2 remains explicitly not microphone evidence.

### Packet 7D — Corpus storage and consent

**Depends on:** 1A
**Objective:** Securely create/read/delete/export a private corpus root without recording audio yet.

**Owned files:**

- `Sources/FleckApp/LocalWritingCorpusStore.swift` — new
- `Tests/FleckAppTests/LocalWritingCorpusStoreTests.swift` — new

**Required implementation:** user-selected external `0700` root, consent receipt, canonical manifests, hash verification, repository/app-bundle exclusion, atomic case metadata, per-case/all delete, explicit export. The store owns the 1A canonical eligibility ledger/latest checkpoint and refuses rollback or fork. Per-case deletion of exposed material appends and checkpoints a lineage invalidation before erasing private bytes; whole-corpus deletion removes ledger/material together, invalidates dependent evidence, and forces a new corpus ID.

**Red tests first:** correction/deletion cannot publish before invalidation checkpoint; an old score fails after invalidation; per-case deletion cannot erase exposure or reuse the lineage as blind; whole-corpus deletion invalidates retained plans/receipts; export/import preserves the canonical eligibility chain and invalidation events without exposing private text or audio paths.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingCorpusStoreTests/'
```

### Packet 7D4 — Immutable corpus templates and oracle drafts

**Depends on:** 1A, 7D
**Objective:** Make the 120-case private corpus authorable without letting results, models, or ordinary dictation define their own answers.

**Owned files:**

- `Sources/FleckApp/Resources/LocalWritingCorpusTemplates.v1.json` — new, nonprivate case-intent library
- `Sources/FleckApp/LocalWritingCorpusTemplateLibrary.swift` — new
- `Sources/FleckApp/LocalWritingCorpusOracleDraft.swift` — new
- `Tests/FleckAppTests/LocalWritingCorpusTemplateLibraryTests.swift` — new

**Required implementation:** ship at least 120 versioned case intents covering every frozen corpus floor and taxonomy stratum, including at least 30 intended deterministic-cleanup residuals and 30 intended deterministic-routing residuals. A template fixes required tags, allowed variants, cleanup-oracle shape, and routing cohort/key constraints; it may provide a read prompt or a spontaneous intent but contains no user's private recording/reference/protected values. The draft flow validates the confirmed verbatim reference, exact protected expectations, permitted cleanup operations, routing fixture keys, and execution variants, then freezes a case/oracle revision before results are visible. It consults the 1A eligibility ledger before every edit: pre-exposure edits create a new frozen revision, while a post-exposure correction first appends/checkpoints lineage invalidation, then publishes a permanently diagnostic-only same-material revision and offers a fresh-recording flow with a new case/material lineage to regain eligibility. Feedback-created drafts remain unconfirmed and nonscorable until this same flow completes. After the frozen deterministic-control run, admission remains unscoreable until at least 20 observed residual cleanup and 20 observed residual uniquely routable cases exist; additional cases create a new corpus revision before candidate outputs are inspected.

**Red tests first:** missing taxonomy floor, duplicate template ID, private absolute path, protected value absent from reference, unknown workspace/key, contradictory cleanup operation, result-before-freeze, in-place post-exposure mutation, post-exposure same-material revision marked diagnostic-only, prior-score invalidation, fresh blinded replacement eligibility, feedback draft without confirmation, and deterministic canonical template digest.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingCorpusTemplateLibraryTests/'
```

**Gate:** the template library can produce a valid 120-case manifest skeleton, but no template or generated draft is counted as human evidence until fresh consented audio and a frozen operator-confirmed oracle exist.

### Packet 7D2 — Explicit feedback-to-corpus review bridge

**Depends on:** 5C, 7D4
**Objective:** Make content-free correction events useful without silently retaining or learning from ordinary dictation.

**Owned files:**

- `Sources/FleckApp/LocalWritingFeedbackReviewSource.swift` — new
- `Tests/FleckAppTests/LocalWritingFeedbackReviewSourceTests.swift` — new

**Required implementation:** expose bounded unreviewed routing/cleanup outcome alerts by opaque feedback ID and stable category only. On explicit user action, create an **unconfirmed** 7D4 Quality Lab draft that asks the operator to record a fresh consented utterance and confirm its reference/oracle. Never recover the discarded ordinary audio, copy an ordinary transcript/note body into the corpus, auto-freeze a case, or alter a dictionary/routing rule. Dismissal expires only that alert.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingFeedbackReviewSourceTests/'
```

**Gate:** every corpus case created from feedback has a new explicit consent/audio receipt and user-confirmed oracle; the content-free journal alone changes no quality score or recommendation.

### Packet 7D3 — Controlled routing workspace provisioning

**Depends on:** 1A, 7D
**Objective:** Provision and reset a private isolated note workspace whose canonical manifest makes routing evidence reproducible.

**Owned files:**

- `Sources/FleckApp/LocalWritingControlledWorkspaceStore.swift` — new
- `Tests/FleckAppTests/LocalWritingControlledWorkspaceStoreTests.swift` — new

**Required implementation:** validate the FleckCore controlled-workspace manifest; create a separate `LocalStore` only below the selected private corpus root; materialize exact stable note IDs/title/body and one Inbox; emit canonical pre/post digests; reset atomically before each run; reconcile only receipt-owned expected mutations; tear down through a root/receipt-scoped operation. Implement and validate the frozen `ownerLiveFixture`, `representative60`, and `stress500` cohort floors, including long-body middle evidence and canonical mutation schedules. Refuse the live Fleck store, repository, app bundle, broad/symlinked/traversal paths, unknown notes, and manifest drift.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingControlledWorkspaceStoreTests/'
```

**Gate:** repeated provisioning produces the same workspace digest; a run cannot become authoritative against a user's live workspace or an unreset fixture. Scale claims require both `representative60` and `stress500`; the small live fixture cannot inherit them.

### Packet 7E — Quality audio recorder

**Depends on:** 7D
**Objective:** Record only explicit Quality Mode cases while ordinary dictation remains memory-only.

**Owned files:**

- `Sources/FleckApp/LocalWritingQualityRecorder.swift` — new
- `Tests/FleckAppTests/LocalWritingQualityRecorderTests.swift` — new

**Required implementation:** explicit start/stop, bounded supported format, device receipt, replay, accept/retry/delete, interruption/cancel, never background or ordinary capture.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingQualityRecorderTests/'
```

### Packet 7C2 — Packaged live-microphone quality session

**Depends on:** 7C, 7D3, 7D4, 7E
**Objective:** Capture genuine E3 evidence through the production microphone/processor while keeping all routing writes inside the isolated controlled workspace.

**Owned files:**

- `Sources/FleckApp/LocalWritingLiveQualitySession.swift` — new
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/LocalWritingLiveQualitySessionTests.swift` — new

**Required implementation:** enhanced/debug-only guided session that requires an already frozen case/oracle, durably appends its 1A exposure event before arming the candidate configuration, then arms the real physical hold gesture, production audio source, production processor, dictionary, cleanup, routing, persistence, and chooser against a freshly reset `ownerLiveFixture`. It emits physical key/microphone/device plus exposure and pre/post workspace receipts into the private evidence root. It forbids injected audio, synthetic speech, the user's live note store, background recording, automatic transcript retention, and authoritative completion without an operator-confirmed case/oracle. Cancellation, app quit, or workspace drift leaves no authoritative result and no live-note mutation, but never erases the exposure event.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.LocalWritingLiveQualitySessionTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.liveQualitySessionAbsentFromOrdinaryBuild'
```

**Gate:** tests prove isolation and receipt contracts only. E3 exists only after a human actually speaks into the exact packaged app.

### Packet 7F — Quality Recording Mode UI

**Depends on:** 6E, 7C2, 7D2, 7D4
**Objective:** Create/manage the 120-case local corpus without affecting normal dictation or ordinary Settings clarity.

**Owned files:**

- `Sources/FleckApp/LocalWritingQualityViewModel.swift` — new
- `Sources/FleckApp/LocalWritingQualityView.swift` — new
- `Sources/FleckApp/SettingsView.swift`
- `Tests/FleckAppTests/LocalWritingQualityPresentationTests.swift` — new
- `Tests/FleckAppTests/DictationAccessibilityTests.swift`

**Required implementation:** opt-in explanation; root/consent status; versioned template/read-prompt or spontaneous intent; record/replay/accept/retry/delete; verbatim reference plus bounded protected/cleanup/routing/variant confirmation; pre-result oracle freeze; exposure status; a post-exposure correction warning that marks reused material diagnostic-only plus a one-action fresh blinded re-record path; taxonomy progress counting only admission-eligible cases; explicit content-free feedback-alert review; guided E3 live session; export one frozen evaluator run plan; import/display only the 7A FleckCore strict content-free aggregate envelope after canonical digest and exact plan/corpus/config/profile matching; export/delete; development/Advanced visibility only. Running/scoring remains an external developer operation owned by 7A/7G so FleckApp does not gain an evaluation-target dependency or subprocess dashboard. Import never changes catalog admission or recommendation.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingQualityPresentationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationAccessibility'
```

**Gate:** invalid root/consent blocks recording; UI contains no upload action; normal Settings stays compact.

### Packet 7G0 — Generic development package identity engine

**Depends on:** 0D, 6B, 6D4
**Objective:** Produce reproducible development app/ZIP/configuration receipts before candidate qualification, without pretending that the package is the final selected 9A artifact.

**Owned files:**

- `Scripts/package-local-writing-app.swift` — new canonical archive/receipt engine
- `Scripts/package-local-writing-development-zip.sh` — new generic development wrapper
- `Scripts/verify-packaged-local-writing-receipt.swift` — new strict verifier
- `Scripts/check-packaged-local-writing-no-weights.sh` — new enhanced-aware real app/ZIP scanner
- `Scripts/test-local-writing-package-receipt.sh` — new hermetic fault/transaction tests
- `Tests/FleckAppTests/LocalWritingDevelopmentPackagingTests.swift` — new

**Required implementation:** accept one already-built enhanced app plus one canonical run-configuration record whose profile exists in the embedded development catalog. Hash the clean source commit, lockfiles, app tree, executable, catalog, exact intended configuration/profile set, manifests/notices, tool versions, and package policy. Development receipts are marked `developmentQualification` and can support E2/7I2/7L1 only; they cannot satisfy 9A, D4, D5, signing, recommendation, or distribution. The verifier also provides `--extract-to <new-empty-root>`: it validates archive/receipt before and during extraction, uses only receipt-listed canonical entries, refuses preexisting/broad/symlinked roots and zip-slip/type changes, fsyncs a transaction root, atomically exposes the extracted app, then rechecks app-tree/executable identity.

Use the admission spec's collision-safe length-framed app-tree entries and reject normalization/case/path/type collisions. Publish through the receipt-last transaction protocol: stage/fsync both artifacts, collision-check final names, rename+fsync ZIP, rename receipt as commit marker, fsync parent, and quarantine only journal-owned incomplete outputs on relaunch. Freeze a typed optional `signedDistributionExtension` seam in the receipt schema; development/test receipts require it absent, while 9D may populate it only after strict promotion/notary validation. The canonical verifier and the separate enhanced-aware scanner inspect both the actual input app and a fresh ZIP extraction and reject model-weight extensions/directories/content signatures while allowing only expected runtime libraries, manifests, and notices.

**Red tests first:** same app/config deterministic ZIP; changed file/mode/symlink/config changes identity; delimiter/path-prefix collision; NFC/case-fold collision; escaping symlink; socket/device; unexpected entry; planted `.mlmodel`, `.mlmodelc`, `.safetensors`, `.gguf`, `.onnx`, weight-like archive, or renamed weight signature in app and ZIP; zip-slip/extraction type swap/preexisting or broad extraction root; interrupted before ZIP rename; interrupted between ZIP/receipt rename; fsync/rename failure; stale transaction; existing mismatched pair; receipt without ZIP; ZIP without receipt; unknown release extension; dirty source marked nonauthoritative and rejected by authoritative mode.

**Verify:**

```bash
Scripts/test-local-writing-package-receipt.sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingDevelopmentPackagingTests/'
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
Scripts/package-local-writing-development-zip.sh --app .build/parakeet-test/Fleck.app --configuration-record /absolute/private/evidence/development-configuration.json --output-root .build/local-writing-development
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt .build/local-writing-development/Fleck-local-writing-development.receipt.json --app .build/parakeet-test/Fleck.app --zip .build/local-writing-development/Fleck-local-writing-development.zip --require-class developmentQualification
Scripts/check-packaged-local-writing-no-weights.sh --app .build/parakeet-test/Fleck.app --zip .build/local-writing-development/Fleck-local-writing-development.zip
```

Before execution, substitute a canonical private configuration record. **Gate:** later qualification packets have an exact E2 package identity source; this packet selects and admits no model.

### Packet 7G — Packaged soak, resource, and privacy harness

**Depends on:** 7B, 7C2, 7G0
**Objective:** Make E2, E3 receipt ingestion, the 500-capture soak, process-tree resource sampling, and unexpected-network/audio-persistence checks executable rather than manual prose.

**Owned files:**

- `Tools/LocalWritingQualityHarness/Package.swift` — new
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/main.swift` — new
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/PackagedRun.swift` — new
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/ProcessEvidence.swift` — new
- `Tools/LocalWritingQualityHarness/Tests/LocalWritingQualityHarnessTests/PackagedRunTests.swift` — new
- `Tools/LocalWritingQualityHarness/Tests/LocalWritingQualityHarnessTests/ProcessEvidenceTests.swift` — new

**Required implementation:** verify app/executable/catalog/model/corpus/dictionary/workspace hashes; launch the dev-only injected E2 path; ingest and verify separately produced human E3 receipts without synthesizing speech; sample the Fleck/helper process tree; detect unexpected established connections; scan declared persistence roots; random seeded 500-case/cancel/lifecycle schedule; run representative/stress cache cohorts; output raw receipts for 7A scoring. Freeze four CLI contracts used by Phase 9: `verify-package --receipt --zip --app`, `run --plan`, `verify-run --receipt`, and `verify-run --receipt --compare`. Before the first exposure append, `run` verifies the canonical current eligibility checkpoint and atomically preserves its exact bytes as `<output-root>/run-start-ledger-checkpoint.json`; it refuses an existing file, binds that digest into the run receipt, and never rewrites it. This is the authenticated parent consumed by the later ledger-extension export. A canonical run plan contains only absolute prevalidated private-root paths and immutable identities/thresholds; a run receipt is atomic and cannot become authoritative while any scheduled case is missing. The harness package has only standard-library source plus, after Packet 9D0, the zero-dependency root-local `LocalWritingEvidenceContracts` package; it never depends on the root Fleck package/product or any remote package. `Tools/LocalWritingQualityHarness/Package.resolved` and `Packages/LocalWritingEvidenceContracts/Package.resolved` must remain absent. Packet 0D's nested-package canary treats creation of either absent lockfile, or any mutation of the root lockfile, as failure.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalWritingQualityHarness '^LocalWritingQualityHarnessTests\.PackagedRunTests/'
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalWritingQualityHarness '^LocalWritingQualityHarnessTests\.ProcessEvidenceTests/'
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness --self-test
```

**Gate:** harness failures cannot alter the app or admission thresholds; private detailed output stays under the chosen corpus/evidence root.

### Packet 7H — TDT-CTC 110M exact artifact profile

**Depends on:** 6A, 6B, 7A
**Objective:** Add identity/install metadata for one lightweight evaluation candidate, not a normal selection.

**Owned files:**

- `Sources/FleckApp/ParakeetTDTCTC110MTestConfiguration.swift` — new
- `Sources/FleckApp/Resources/ParakeetTDTCTC110MModelManifest.json` — new
- `Sources/FleckApp/LocalModelCatalogSnapshot.swift`
- `Tests/FleckAppTests/ParakeetTDTCTC110MTestConfigurationTests.swift` — new
- `Tests/FleckAppTests/LocalModelCatalogTests.swift`

**Preconditions:** exact selected files/hashes/bytes; exact runtime ABI; reviewed license; explicit model-download authorization only when the evaluation run begins.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.ParakeetTDTCTC110MTestConfigurationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelCatalogTests/'
Scripts/build-fleck-app.sh
Scripts/check-release-size.sh .build/Fleck.app
```

**Gate:** the exact profile is `identityVerified/developmentCandidate` only; this packet does not download it or make it selectable/recommended.

### Packet 7I — TDT-CTC 110M evaluation adapter

**Depends on:** 3D, 7C2, 7H
**Objective:** Load/transcribe/cancel/unload and select the exact candidate through both packaged quality paths behind a development-only profile identity.

**Owned files:**

- `Sources/FleckApp/ParakeetTDTCTC110MTestActivation.swift` — new
- `Sources/FleckApp/EnhancedSpeechCapture.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Sources/FleckApp/LocalWritingQualityRunConfiguration.swift`
- `Sources/FleckApp/LocalWritingQualityRunController.swift`
- `Sources/FleckApp/LocalWritingLiveQualitySession.swift`
- `Tests/FleckAppTests/ParakeetTDTCTC110MTestActivationTests.swift` — new
- `Tests/FleckAppTests/EnhancedSpeechCaptureTests.swift`
- `Tests/FleckAppTests/LocalWritingQualityRunControllerTests.swift`
- `Tests/FleckAppTests/LocalWritingLiveQualitySessionTests.swift`

**Required implementation:** replace the hardcoded Parakeet-v2 candidate construction in development Quality composition with exact profile-digest resolution. E1 adapter runs, packaged injected E2 runs, and live E3 sessions must all acknowledge the same 110M dictation profile or fail closed; a feature flag without the catalog/configuration/profile identity is insufficient. Ordinary safe composition remains unchanged.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.ParakeetTDTCTC110MTestActivationTests/'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.EnhancedSpeech'
```

**Gate:** feature-flagged nonzero identity/load/cancel/offline/15-second-stitching and E2/E3 composition tests. It remains a development candidate until 7I2 and the later exact-package runs pass.

### Packet 7I1 — Parakeet TDT v2 absolute qualification

**Depends on:** 3D, 7G
**Owned files:** no product source; the rebuilt development package and all detailed outputs remain outside source under the private evidence root.

**Run:** after all accepted v2 capture/context/runtime work, rebuild the enhanced development app from the clean current commit, package it through 7G0 with the exact Parakeet-v2 configuration record, and verify that post-build receipt. Run v2 alone through the frozen E1 human replay and packaged E2 plans. It must pass the absolute ASR, first/final-word, priority-dictionary, latency, memory, cancellation, privacy, and offline gates; no challenger result participates in its decision.

**Verify:**

```bash
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
Scripts/package-local-writing-development-zip.sh --app .build/parakeet-test/Fleck.app --configuration-record /absolute/private/evidence/parakeet-v2-configuration.json --output-root /absolute/private/evidence/parakeet-v2-package
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/evidence/parakeet-v2-package/Fleck-local-writing-development.receipt.json --app .build/parakeet-test/Fleck.app --zip /absolute/private/evidence/parakeet-v2-package/Fleck-local-writing-development.zip --require-class developmentQualification
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run --plan /absolute/private/evidence/parakeet-v2-e1-e2-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-run --receipt /absolute/private/evidence/parakeet-v2-e1-e2-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing score-run --plan /absolute/private/evidence/parakeet-v2-e1-e2-plan.json --raw-receipts /absolute/private/evidence/parakeet-v2-raw --corpus-ledger /absolute/private/corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/evidence/parakeet-v2-scored
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-score --receipt /absolute/private/evidence/parakeet-v2-scored/aggregate-receipt.json --corpus-ledger /absolute/private/corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --summary-output /absolute/private/evidence/parakeet-v2-scored/local-writing-quality-summary.json
```

**Gate:** one independent absolute v2 qualification receipt. A failure cannot be hidden by 110M comparison and prevents any 9A configuration containing v2.

### Packet 7I2 — TDT-CTC 110M frozen-corpus qualification

**Depends on:** 7I, 7I1
**Owned files:** no product source; raw and scored outputs remain below the private evidence root.

**Run:** after 7I composition lands, rebuild and repackage the development app so the receipt's executable includes the 110M selection path. Score 110M independently on the same frozen E1/E2 corpus/dictionary plan, verify its own aggregate, then compare it with the already verified 7I1 v2 receipt. Do not place both profile identities into one authoritative run/aggregate. Preserve raw results for a rejected candidate.

**Verify:**

```bash
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
Scripts/package-local-writing-development-zip.sh --app .build/parakeet-test/Fleck.app --configuration-record /absolute/private/evidence/tdt-ctc-110m-configuration.json --output-root /absolute/private/evidence/tdt-ctc-110m-package
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/evidence/tdt-ctc-110m-package/Fleck-local-writing-development.receipt.json --app .build/parakeet-test/Fleck.app --zip /absolute/private/evidence/tdt-ctc-110m-package/Fleck-local-writing-development.zip --require-class developmentQualification
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run --plan /absolute/private/evidence/tdt-ctc-110m-e1-e2-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-run --receipt /absolute/private/evidence/tdt-ctc-110m-e1-e2-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing score-run --plan /absolute/private/evidence/tdt-ctc-110m-e1-e2-plan.json --raw-receipts /absolute/private/evidence/tdt-ctc-110m-raw --corpus-ledger /absolute/private/corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/evidence/tdt-ctc-110m-scored
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-score --receipt /absolute/private/evidence/tdt-ctc-110m-scored/aggregate-receipt.json --corpus-ledger /absolute/private/corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --summary-output /absolute/private/evidence/tdt-ctc-110m-scored/local-writing-quality-summary.json
swift run --disable-automatic-resolution fleck-model-eval local-writing compare-runs --left /absolute/private/evidence/parakeet-v2-scored/aggregate-receipt.json --right /absolute/private/evidence/tdt-ctc-110m-scored/aggregate-receipt.json --corpus-ledger /absolute/private/corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/evidence/v2-vs-110m-comparison.json
```

Before execution, substitute and freeze the canonical private root, new post-7I package receipt, corpus/dictionary/workspace/profile digests, and lightweight thresholds. **Gate:** 110M independently passes absolute safety/quality ceilings, accuracy noninferiority against the separately verified v2 receipt, no protected/priority-term/cancellation/privacy regression, and at least 30% improvement in its declared peak-memory or cold-load objective. A pass makes 110M eligible to be the one 9A package configuration; it does not admit or recommend it. Its failure leaves a passing v2 receipt intact.

### Packet 7J — Auxiliary CTC dictionary assistance

**Depends on:** 3D, 7I, 7I1; execute only if the verified v2 dictionary-accuracy receipt misses the frozen gate. It may run in parallel with 7I2 because it answers a different bounded question.
**Objective:** Evaluate FluidAudio acoustic vocabulary assistance with exact compatible profile and policy.

**Before delegation:** amend this plan with the resolved auxiliary license, exact revision/manifest, and exact owned configuration/adapter/test paths.
**Required tests:** tokenizer/frame compatibility, alias conflicts, false boosts, threshold freeze, resource overhead, cancellation, separate acknowledgement.
**Verify before delegation:** `rg -n 'resolved auxiliary license|exact revision|exact owned' docs/superpowers/plans/2026-08-29-local-writing-intelligence-program.md` must be replaced by concrete values/paths, followed by exact non-empty enhanced test and frozen-corpus commands in this packet.
**Gate:** measurable dictionary-term gain with no WER/protected/latency/resource regression.

### Packet 7K — Streaming challenger

**Conditional:** execute only if genuine live partials become a hard requirement after user testing.
**Choice:** one exact Unified 320/640 ms profile or one EOU tier, not every export.
**Before delegation:** select one exact artifact and amend this plan with its revision, manifest, runtime ABI, and exact configuration/capture/test files.
**Gates:** partial churn, premature/missed EOU, pause/restart, state reset, final convergence, WER, first/final word, memory, cancellation, package.
**Verify before delegation:** the amended packet must contain one immutable profile digest, exact owned paths, `run-nonempty-enhanced-tests.sh` commands, and private corpus/E2/E3 commands; until then 7K is non-executable.
**Non-goal:** model diversity for its own sake.

### Packet 7L1 — Existing cleanup and routing role qualification

**Depends on:** 4B2, 5B, 6B, 6D4, 7A, 7G
**Owned files:**

- `Scripts/run-local-writing-role-qualification.sh` — new one-identity-at-a-time matrix orchestrator
- `Scripts/test-local-writing-role-qualification.sh` — new hermetic orchestration tests

No product source is owned; authoritative outputs go only to the private evidence root.
**Compare:** deterministic; exact Apple Foundation cohorts where available; current exact Gemma 1B cleanup and routing role profiles. Run the same frozen cases through each role independently and then the exact joint tuple. Emit separate Apple-Speech/Apple-Foundation cleanup-only, routing-only, and both-role OS-cohort receipts so existing system behavior remains reachable only where proven.
**Verify:**

```bash
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
Scripts/test-local-writing-role-qualification.sh
Scripts/run-local-writing-role-qualification.sh --app .build/parakeet-test/Fleck.app --matrix /absolute/private/evidence/cleanup-routing-role-matrix.json --output-root /absolute/private/evidence/cleanup-routing-matrix
swift run --disable-automatic-resolution fleck-model-eval local-writing compare-role-matrix --matrix /absolute/private/evidence/cleanup-routing-role-matrix.json --receipts-root /absolute/private/evidence/cleanup-routing-matrix --corpus-ledger /absolute/private/corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/evidence/cleanup-routing-matrix-comparison.json
```

Before execution, substitute the canonical private root and freeze it in the matrix. The strict matrix contains one row/configuration/plan/output namespace for deterministic-only; each exact Apple OS cohort's cleanup-only, routing-only, and both-role tuples; and Gemma cleanup-only, routing-only, and both-role tuples. For every row the script separately packages/verifies the app with that one configuration record, runs/verifies the harness, scores, and invokes `verify-score --summary-output <row-output>/local-writing-quality-summary.json`; it aborts before comparison on any existing summary path or missing/duplicate/mismatched receipt. The scorer validates corpus/config/profile/prompt/validator/router/package hashes, keeps E1/E2 distinct, and reruns zero-event semantic/routing gates from the private manifest. The matrix comparison reports each independent decision and attributable deltas without merging their aggregates.
**Gate:** cleanup and routing are scored/admitted separately; zero semantic violations, zero wrong auto-routes, candidate-attributable incremental utility/coverage over the exact deterministic controls, separate stage latency, and joint M1 memory. Produce separate qualification receipts for the deterministic-only, cleanup-only, routing-only, and both-role exact tuples; a passing role may therefore survive the other role's rejection without ever invoking the rejected role. Rejection/no-op/deterministic-only success cannot admit a model role. No role or tuple may pass without its own verified identity-bound receipt and every frozen role-specific gate.

### Packet 7L2 — Gemma 270M lightweight challenger

**Depends on:** 7L1; execute only if the 1B tuple misses a frozen resource/latency objective that a smaller model could plausibly address.
**Before delegation:** amend this packet with exact artifact revision/files/hashes/bytes, runtime ABI, terms record, catalog/configuration keys/digests, exact configuration/adapter/manifest/test ownership, and exact non-empty test/corpus commands.
**Verify before delegation:** the amended packet must name one immutable artifact/profile digest, exact disjoint owned paths, positive-match ordinary/enhanced test commands, and frozen E1/E2 resource/quality commands. Until those replace this precondition, 7L2 is deliberately non-executable.
**Gate:** zero semantic violations and zero wrong auto-routes, with frozen utility noninferiority and a material measured memory/cold-load improvement. A pass creates separate exact cleanup and routing profiles; it never silently replaces 1B.

## Phase 8 — Deep facade and product integration cleanup

This phase occurs after behavior and evidence stabilize. It is not an early rewrite.

### Packet 8A — `LocalWriting` facade parity

**Depends on:** 3E, 4E, 5C, 6E, 7C2, plus every executed candidate wiring packet (`7I`/`7I2`, `7J`, `7K`, or `7L2`)
**Objective:** Give shortcut/capsule/focused/Smart callers one small transaction Interface while wrapping current coordinator internals.

**Owned files:**

- `Sources/FleckApp/LocalWriting.swift` — new
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Tests/FleckAppTests/LocalWritingTests.swift` — new
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/GemmaCleanupAppCompositionTests.swift`

**Interface:** `beginHold`, `WritingHold.release/cancel/events`, and opaque `perform(actionToken)`.

**Red tests first:** at most one hold, short tap, all terminal states exactly once, invalid/stale action, same recovery/cancel/chooser semantics, no internal receipt/model/cache leakage.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(coordinator|processing|ambiguousRouting|correction)'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.LocalWritingTests/'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.GemmaCleanupAppCompositionTests/'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.LocalWritingRuntimeStressTests/'
```

**Gate:** pure parity; no model/quality/UI redesign in the facade packet.

### Packet 8B — Remove legacy direct orchestration

**Depends on:** accepted 8A diff plus its required post-facade `LocalWritingRuntimeStressTests` rerun
**Objective:** Delete the coordinator's unused direct speech/cleanup route only after every production caller uses the facade/streaming path.

**Owned files:**

- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Scripts/check-local-writing-single-orchestration.sh` — new failing source-structure gate
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/LocalWritingTests.swift`
- `Tests/FleckAppTests/LocalWritingSourceStructureTests.swift` — new

**Required implementation:** delete only the now-unused direct coordinator speech/cleanup route. The source-structure script has an explicit reviewed allowlist of declaration/construction/call sites and fails on direct `DictationCoordinator`, `StreamingDictationProcessor`, cleanup, routing, or cancellation ownership outside `LocalWriting` and its approved composition root. It must distinguish declarations from constructions and calls, reject a missing expected site as well as an extra site, and emit the offending path/line. The test exercises passing and deliberately violating fixtures; a positive `rg` listing is not evidence.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(coordinator|processing)'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingSourceStructureTests/'
Scripts/check-local-writing-single-orchestration.sh
```

**Gate:** source audit finds one processing order and one cancellation authority; full focused regression passes before deletion is accepted.

## Phase 9 — Packaged admission

### Packet 9A — Candidate package reconciliation

**Depends on:** 6E, 7F, 7G, 7L1, 8B and one exact chosen configuration. Every non-built-in profile in that configuration must name an accepted implementation/qualification packet and receipt: Parakeet v2 requires 3B/3D/7I1; TDT-CTC 110M requires 7H/7I/7I2; auxiliary CTC requires 7J; Unified/EOU requires amended 7K; Gemma 1B roles require the matching 7L1 role/tuple receipt; Gemma 270M requires amended 7L2. A missing conditional dependency makes 9A non-executable.
**Objective:** Build one exact enhanced test ZIP with newest accepted UI, runtimes/helpers/notices, and no weights.

**Owned files:**

- `Package.swift`
- `Package.resolved`
- `Packages/FleckEnhancedCandidateDependencies/Package.swift`
- `Packages/FleckEnhancedCandidateDependencies/Package.resolved`
- `Scripts/build-parakeet-test-app.sh`
- `Scripts/package-parakeet-test-zip.sh` — new
- `Sources/FleckApp/Resources/EnhancedModelManifest.json`
- `Sources/FleckApp/Resources/GemmaCleanupModelManifest.json`
- `Sources/FleckApp/Resources/ThirdPartyNotices.md`
- `Sources/FleckApp/Resources/GemmaCleanupNotice.md`
- `Tests/FleckAppTests/ParakeetTestAppPackagingTests.swift`

**Required implementation:** require a clean isolated source worktree at the accepted commit and exact lockfiles; otherwise emit only a visibly nonauthoritative smoke receipt and fail this packet's gate. Reconcile the selected runtimes/helpers/notices, build `.build/parakeet-test/Fleck.app` once, then package a staging copy without mutating that app. The test wrapper calls the 7G0 canonical archive/receipt engine; the later release wrapper must use that same engine rather than reimplement ZIP identity. The engine contract rejects symlink/path/type/normalization/case collisions and encodes each app-tree entry using length-framed canonical path/type/mode/payload fields. It removes extended attributes from staging, normalizes archive timestamps, enumerates canonical relative paths in bytewise order, preserves declared file type/mode and symlink targets, and invokes one recorded compression tool/version with stable options. It transactionally commits exactly:

- `.build/parakeet-test/Fleck-enhanced-test.zip`;
- `.build/parakeet-test/Fleck-enhanced-test.receipt.json`.

The wrapper requires explicit canonical `--configuration-record` and `--qualification-index` inputs and verifies that every selected non-built-in profile maps to the named accepted receipt before packaging. The canonical receipt binds those input digests plus ZIP SHA-256/bytes, canonical app-tree hash, bundle-executable SHA-256, clean source commit, root and enhanced `Package.resolved` hashes, catalog revision, configuration key/digest, every role-profile digest, manifest/notices hashes, signing identity, compression tool/version, and packaging-policy revision. It is classed `enhancedTestSelectedConfiguration` and requires the signed-distribution extension absent. The 7G0 receipt-last protocol stages/fsyncs both files, publishes the ZIP first and the receipt last as commit marker, refuses mismatched existing outputs, and quarantines only journal-owned incomplete transactions. Packaging the same unchanged `.app` twice must produce the same ZIP SHA-256; any changed tree entry must change the app-tree hash. No receipt contains a private corpus path, dictionary content, or credential.

**Red tests first:** every 7G0 transaction/collision case plus selected-profile not in catalog, profile qualification receipt mismatch, dirty source, root/enhanced lock drift, stale notice, wrong artifact class, nonempty signed-distribution extension, and second packaging with a mismatched existing pair.

**Verify:**

```bash
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.(parakeetPackager|parakeetTestApp)'
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
Scripts/package-parakeet-test-zip.sh --app .build/parakeet-test/Fleck.app --configuration-record /absolute/private/evidence/selected-configuration.json --qualification-index /absolute/private/evidence/selected-qualification-receipts.json --output-root .build/parakeet-test
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --app .build/parakeet-test/Fleck.app --zip .build/parakeet-test/Fleck-enhanced-test.zip --require-class enhancedTestSelectedConfiguration
Scripts/check-packaged-local-writing-no-weights.sh --app .build/parakeet-test/Fleck.app --zip .build/parakeet-test/Fleck-enhanced-test.zip
Scripts/test-release-model-asset-exclusion.sh
```

**Gate:** exact packaged candidate is ready to attempt D4 hands-on testing; 9A does not itself pass D4 or prove real-microphone behavior.

### Packet 9B — Mac mini live admission run

**Depends on:** 7F, 7G, 9A and the 120-case corpus
**Owned files:** no product or repository source. The instantiated run plan and all detailed outputs stay under the owner-selected private evidence root.

**Run:** instantiate one canonical `mac-mini-d4-run-plan.json` that binds the 9A receipt, corpus/dictionary/workspace digests, exact thresholds, hardware/input-device cohort, and output root. Run E1 replay, E2 package injection, E3 real microphone, installer lifecycle, offline relaunch, 500-capture soak, pressure/sleep/wake/Bluetooth, and the cancellation matrix. Human E3 cases require the operator to speak; automation may guide and record but may not replace them with synthetic audio.

**Verify:**

```bash
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-package --receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --zip .build/parakeet-test/Fleck-enhanced-test.zip --app .build/parakeet-test/Fleck.app
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run --plan /absolute/private/mac-mini-evidence/mac-mini-d4-run-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-run --receipt /absolute/private/mac-mini-evidence/mac-mini-d4-run-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing score-run --plan /absolute/private/mac-mini-evidence/mac-mini-d4-run-plan.json --raw-receipts /absolute/private/mac-mini-evidence/mac-mini-raw --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/mac-mini-scored
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-score --receipt /absolute/private/mac-mini-evidence/mac-mini-scored/aggregate-receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --summary-output /absolute/private/mac-mini-evidence/mac-mini-scored/local-writing-quality-summary.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-ledger --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --output /absolute/private/mac-mini-evidence/mac-mini-d4-ledger-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-corpus-ledger-extension --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --after-checkpoint /absolute/private/mac-mini-evidence/run-start-ledger-checkpoint.json --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/mac-mini-d4-ledger-extension.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-comparison-evidence --receipt /absolute/private/mac-mini-evidence/mac-mini-d4-run-receipt.json --receipt /absolute/private/mac-mini-evidence/mac-mini-scored/aggregate-receipt.json --ledger-extension /absolute/private/mac-mini-evidence/mac-mini-d4-ledger-extension.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/mac-mini-d4-comparison-evidence.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/mac-mini-evidence/mac-mini-d4-comparison-evidence.json --expected-package-receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
```

Before execution, replace `/absolute/private/mac-mini-evidence` and `/absolute/private/mac-mini-corpus` with the canonical selected `0700` roots and freeze them in the run plan. `verify-run` fails unless E1/E2/E3 remain distinct, every expected case is present, package/catalog/config/profile/corpus/dictionary hashes match, and raw ASR, dictionary baseline, faithful baseline, cleanup/final text, routing, lifecycle, resource, cancellation, privacy, persistence, and exposure receipts reconcile. The only **9B result/evidence outputs** transferred in 9C are the content-free comparison bundle and authenticated eligibility-ledger extension/checkpoint; neither contains case text, audio, or private paths. Separately, the owner-authorized two-Mac evaluation input transfer carries the exact 9A ZIP/package receipt, frozen private corpus manifest/audio archive, and dictionary snapshot required by the corpus protocol. Those private inputs remain under the selected `0700` roots, are digest-verified against the frozen run plan, and never enter either content-free evidence bundle.

**Gate:** D4 on the Mac mini only when frozen metrics pass and every critical zero-event gate remains zero. Failures become diagnosed bounded packets, not threshold changes.

### Packet 9C — M1 8 GB identical-artifact run

**Depends on:** 9B
**Owned files:** no product or repository source. Transfer/run receipts stay under the MacBook's selected private `0700` evidence root.

**Run:** transfer the exact 9A ZIP plus its receipt, verified 9B `mac-mini-d4-comparison-evidence.json`, and authenticated `mac-mini-d4-ledger-extension.json`; do not rebuild or copy private raw receipts. First authenticate and apply the standalone ledger extension exactly once, requiring its parent to equal the transferred corpus checkpoint. Then verify and import the comparison bundle as receipts-only evidence, requiring its embedded extension child/checkpoint and digest to equal that now-current ledger; any mismatch or attempted second application fails before comparison. Verify ZIP, extracted app tree, bundle executable, and running executable identities; import the explicit dictionary/corpus package and verify digests; repeat E1/E2 and the frozen focused E3 subset; then run pressure, joint residency, offline relaunch, repair, and removal checks. Export the M1 result plus its exposure-only ledger extension back to the Mac mini. The Mac mini—not the remote copy—fast-forwards the canonical ledger, creates the D5 seal, recomputes comparison, creates the promotion record, and exports the promotion bundle.

**Verify:**

```bash
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/m1-evidence/Fleck-enhanced-test.receipt.json --zip /absolute/private/m1-evidence/Fleck-enhanced-test.zip --extract-to /absolute/private/m1-evidence/extracted-test-app --require-class enhancedTestSelectedConfiguration
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/m1-evidence/Fleck-enhanced-test.receipt.json --app /absolute/private/m1-evidence/extracted-test-app/Fleck.app --zip /absolute/private/m1-evidence/Fleck-enhanced-test.zip --require-class enhancedTestSelectedConfiguration
swift run --disable-automatic-resolution fleck-model-eval local-writing import-corpus-ledger-extension --bundle /absolute/private/m1-evidence/imports/mac-mini-d4-ledger-extension.json --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/m1-evidence/imports/mac-mini-d4-comparison-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-test.receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_MAC_MINI_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing import-comparison-evidence --bundle /absolute/private/m1-evidence/imports/mac-mini-d4-comparison-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-test.receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_MAC_MINI_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output-root /absolute/private/m1-evidence/imported/mac-mini-d4
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run --plan /absolute/private/m1-evidence/m1-8gb-d5-run-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-run --receipt /absolute/private/m1-evidence/m1-8gb-d5-run-receipt.json --compare /absolute/private/m1-evidence/imported/mac-mini-d4/mac-mini-d4-run-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing score-run --plan /absolute/private/m1-evidence/m1-8gb-d5-run-plan.json --raw-receipts /absolute/private/m1-evidence/m1-8gb-raw --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_M1_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/m1-evidence/m1-8gb-scored
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-score --receipt /absolute/private/m1-evidence/m1-8gb-scored/aggregate-receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_M1_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --summary-output /absolute/private/m1-evidence/m1-8gb-scored/local-writing-quality-summary.json
swift run --disable-automatic-resolution fleck-model-eval local-writing compare-runs --left /absolute/private/m1-evidence/imported/mac-mini-d4/aggregate-receipt.json --right /absolute/private/m1-evidence/m1-8gb-scored/aggregate-receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_M1_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/m1-evidence/two-device-comparison.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-corpus-ledger-extension --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --after-checkpoint /absolute/private/m1-evidence/imported/mac-mini-d4/eligibility-ledger.checkpoint.json --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/m1-evidence/m1-d5-ledger-extension.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-comparison-evidence --receipt /absolute/private/m1-evidence/m1-8gb-d5-run-receipt.json --receipt /absolute/private/m1-evidence/m1-8gb-scored/aggregate-receipt.json --receipt /absolute/private/m1-evidence/two-device-comparison.json --ledger-extension /absolute/private/m1-evidence/m1-d5-ledger-extension.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-corpus-head CURRENT_M1_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/m1-evidence/m1-d5-return-evidence.json

# Back on the Mac mini: authenticate and fast-forward the only authoritative ledger, then seal and promote.
swift run --disable-automatic-resolution fleck-model-eval local-writing import-corpus-ledger-extension --bundle /absolute/private/mac-mini-evidence/imports/m1-d5-ledger-extension.json --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-ledger --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --output /absolute/private/mac-mini-evidence/d5-corpus-ledger-verification-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing create-corpus-admission-seal --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-admission-seal --seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/d5-corpus-seal-verification-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/mac-mini-evidence/imports/m1-d5-return-evidence.json --expected-package-receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing import-comparison-evidence --bundle /absolute/private/mac-mini-evidence/imports/m1-d5-return-evidence.json --expected-package-receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output-root /absolute/private/mac-mini-evidence/imported/m1-d5
swift run --disable-automatic-resolution fleck-model-eval local-writing compare-runs --left /absolute/private/mac-mini-evidence/mac-mini-scored/aggregate-receipt.json --right /absolute/private/mac-mini-evidence/imported/m1-d5/aggregate-receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/two-device-comparison.json
swift run --disable-automatic-resolution fleck-model-eval local-writing create-promotion-record --test-package-receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --mac-mini-run /absolute/private/mac-mini-evidence/mac-mini-d4-run-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/mac-mini-scored/aggregate-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/m1-d5/m1-8gb-d5-run-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/m1-d5/aggregate-receipt.json --comparison /absolute/private/mac-mini-evidence/two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-ledger-verification-receipt /absolute/private/mac-mini-evidence/d5-corpus-ledger-verification-receipt.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --corpus-seal-verification-receipt /absolute/private/mac-mini-evidence/d5-corpus-seal-verification-receipt.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/d5-promotion-record.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-promotion-record --record /absolute/private/mac-mini-evidence/d5-promotion-record.json --test-package-receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --mac-mini-run /absolute/private/mac-mini-evidence/mac-mini-d4-run-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/mac-mini-scored/aggregate-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/m1-d5/m1-8gb-d5-run-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/m1-d5/aggregate-receipt.json --comparison /absolute/private/mac-mini-evidence/two-device-comparison.json --corpus-ledger-verification-receipt /absolute/private/mac-mini-evidence/d5-corpus-ledger-verification-receipt.json --corpus-seal-verification-receipt /absolute/private/mac-mini-evidence/d5-corpus-seal-verification-receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing export-promotion-evidence --record /absolute/private/mac-mini-evidence/d5-promotion-record.json --test-package-receipt .build/parakeet-test/Fleck-enhanced-test.receipt.json --mac-mini-run /absolute/private/mac-mini-evidence/mac-mini-d4-run-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/mac-mini-scored/aggregate-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/m1-d5/m1-8gb-d5-run-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/m1-d5/aggregate-receipt.json --comparison /absolute/private/mac-mini-evidence/two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-ledger-verification-receipt /absolute/private/mac-mini-evidence/d5-corpus-ledger-verification-receipt.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --corpus-seal-verification-receipt /absolute/private/mac-mini-evidence/d5-corpus-seal-verification-receipt.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/d5-promotion-evidence.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-promotion-evidence --bundle /absolute/private/mac-mini-evidence/d5-promotion-evidence.json --test-zip .build/parakeet-test/Fleck-enhanced-test.zip --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
```

Before execution, replace the placeholder evidence/corpus roots with the canonical device-specific `0700` roots. The transfer protocol records each source bundle digest independently of its destination path; receipt import refuses an existing/nonempty destination or any embedded private field, while ledger import requires an authenticated exact-parent fast-forward. Only `candidateExposure` events may extend the chain after sealing. The comparison command rejects any archive/app/config/profile/corpus/dictionary/policy/ledger/seal mismatch and reports hardware cohorts separately.

**Gate:** D5 accepted configuration on both named cohorts only after the M1 ledger/result extension fast-forwards the canonical Mac-mini root, that head is sealed under the reviewed evaluator identity, and one verified canonical `d5-promotion-record.json` plus `d5-promotion-evidence.json` binds the exact 9A package/configuration/evidence/checkpoint/seal tuple. The exact 9A ZIP, package receipt, promotion bundle, canonical live ledger/checkpoint, and seal are retained. The bundle moves to the authorized 9D build host under an out-of-band digest manifest, but D6/D7 still reopen the live canonical root; a copied bundle cannot assert latest state. Rebuilding on the MacBook invalidates comparability. The record qualifies promotion input only; it is not final-artifact D6 evidence or release authorization.

### Packet 9D0 — External production-UI acceptance harness

**Depends on:** 7G, 9C
**Objective:** Add a release-safe external QA driver before the final app build; it observes only normal Fleck UI/storage and adds no debug seam to Fleck.app.

**Owned files:**

- `Tools/LocalWritingQualityHarness/Package.swift`
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/main.swift`
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/ReleaseUIRun.swift` — new
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/ReleaseUIAutomation.swift` — new
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/ReleaseQAWorkspace.swift` — new
- `Tools/LocalWritingQualityHarness/Sources/LocalWritingQualityHarness/ReleaseModelUpdateLifecycle.swift` — new signed-identity update/absence driver
- `Tools/LocalWritingQualityHarness/Tests/LocalWritingQualityHarnessTests/ReleaseUIRunTests.swift` — new
- `Tools/LocalWritingQualityHarness/Tests/LocalWritingQualityHarnessTests/ReleaseUIAutomationTests.swift` — new
- `Tools/LocalWritingQualityHarness/Tests/LocalWritingQualityHarnessTests/ReleaseQAWorkspaceTests.swift` — new
- `Tools/LocalWritingQualityHarness/Tests/LocalWritingQualityHarnessTests/ReleaseModelUpdateLifecycleTests.swift` — new

**Required implementation:** freeze `run-live-ui --plan`, `verify-live-ui --receipt`, `verify-live-ui --receipt --compare`, `run-model-update-lifecycle --plan`, `verify-model-update-lifecycle --receipt`, and strict `export-model-update-evidence` / `verify-model-update-evidence` / `import-model-update-evidence` commands. The harness package adds one direct local path dependency on `../../Packages/LocalWritingEvidenceContracts` and imports that product for Packet 7A's single strict content-free predecessor-snapshot/proof envelope vocabulary; it does not duplicate a schema or depend on the root Fleck package/product. The contracts package and harness package have no remote dependencies, both are always invoked with automatic resolution disabled, and neither may create a `Package.resolved`. The `notApplicableNoEmbeddedTransition` form of `run-model-update-lifecycle` uses only `--plan` and forbids predecessor inputs. Its `executedTransition` form additionally requires `--predecessor-corpus-snapshot` plus either the local `--predecessor-corpus-snapshot-verification-receipt` on the Mac mini or the remote `--predecessor-corpus-snapshot-import-receipt` on the M1; the plan freezes the expected snapshot digest, transition digest, recursive dependency tuple, reviewed evaluation signer, policy sequence/checkpoint, and machine role.

The canonical update receipt has a strict enum. `notApplicableNoEmbeddedTransition` contains a reason code and no predecessor bytes. `executedTransition` contains the unchanged canonical snapshot envelope bytes and exactly one unchanged proof envelope—`sourceVerification` for the Mac mini or `remoteImport` for the M1—encoded as bounded base64 fields, plus their SHA-256 digests and the machine-role discriminant. Receipt creation strict-decodes and cryptographically verifies both envelopes, recomputes their digests, matches snapshot/transition/package/trust/dependency fields to the frozen plan, and rejects private content or the wrong proof variant before writing. `verify-model-update-lifecycle --receipt` repeats that full embedded verification without trusting claimed digests. Consequently the dedicated update-evidence export can remain a canonical content-free envelope over exactly one already verified, self-contained update receipt; verify/import reopen the embedded snapshot/proof, bind the signed package/catalog/configuration identity, reject private/unknown fields and unsafe names, and atomically import into a new empty `0700` root. D6 reopens those same embedded envelopes from both update receipts and also reopens the authoritative live Mac-mini predecessor corpus chain, so a returned remote receipt cannot replace current-state verification.

The comparison form verifies each receipt independently first, requires the same final package/configuration/corpus/dictionary/workspace/UI-contract/threshold tuple, preserves separate hardware and input-device cohorts, and rejects any missing case or widened claim; it never merges results into one aggregate. A live plan binds the final package receipt placeholder, dedicated QA macOS account UID/home marker, standard Fleck Application Support root, 12-note fixture manifest, UI/accessibility contract revision, prompts/oracles, hardware/input device, thresholds, and private output root. An update plan binds the same signed app/catalog plus either one exact transition from a previously release-admitted predecessor to the current D5-promotion-authorized `signedDistributionCandidate` successor—with both identities, qualifications, and artifact manifests complete—or the signed catalog's empty transition list. The successor is not assumed D7-admitted; this run is part of the evidence that may admit it. For a transition the harness drives normal Settings UI through stage, verify, smoke, atomic switch, externally induced process/download interruption before switch, retained-prior rollback, successful update, and explicit rollback without adding an app debug seam; for an empty list it proves no Update action exists and direct descriptor/catalog substitution is rejected. The receipt is `executedTransition` or `notApplicableNoEmbeddedTransition`; the latter makes no claim about whether a predecessor exists elsewhere, forbids any validated-update claim, and requires any later update-capable release to repeat 9D/9D2 with an executed transition. Update receipts never pass through 7A's run/score comparison bundle. The driver requires ordinary Accessibility/microphone permission and stops with actionable instructions if absent; it never bypasses TCC. It creates fixtures only through normal Fleck UI/import actions, verifies visible/store state externally, guides but never synthesizes live speech, correlates output through capture/history/note receipts available to the user, and emits private per-case plus content-free aggregate receipts. It refuses the owner's ordinary account/root, alternate hidden launch flags, direct store writes, unknown UI, stale fixture, missing human confirmation, or any debug/Quality symbol.

**Exposure boundary:** every live plan binds the frozen case/oracle and current exposure-ledger head. Before launching or revealing candidate behavior, the external driver atomically appends the exact 1A exposure event and binds its digest into the live receipt. Append failure blocks the run; cancellation, crash, or rejection never erases exposure. Verification rejects output that predates its event and any post-exposure same-material oracle revision from authoritative evidence. Red cases cover append failure, candidate launch before append, forged/forked ledger heads, crash-after-exposure retention, and post-exposure same-material oracle substitution.

**Transition input boundary:** 9D is the only packet that invokes Packet 6B3's strict verifier over the previous release's 9E `update-predecessor-record` under the current externally pinned trust state, then derives the signed nonselectable transition. The predecessor record/D7 must name that exact same current policy sequence/checkpoint; any intervening rotation, revocation, or checkpoint advance makes `successor` mode unavailable, because this version has no historical-signer ledger. The release may continue only in explicit `none` mode with no update claim and a fresh-install experience. The already-built 9D0 harness depends only on the 6B transition schema and 7A shared snapshot/proof envelope: at execution it verifies embedded predecessor digests against the exact retained previous ZIP/package, installed predecessor receipt, and supplied signed snapshot proof. It never constructs a D6/D7/update record or imports 9E creation logic. Neither Settings nor the harness may construct or repair missing transition metadata.

**Red tests first:** fake AX tree success; permission denial; wrong UID/home/root; live-owner root; direct-write attempt; stale/duplicate fixture; UI drift; deleted destination; no human confirmation; injected/synthetic audio claim; cancellation; app crash; receipt/app hash mismatch; private text leakage into aggregate; compare with different package/configuration/corpus/dictionary/workspace/UI-contract/threshold identity; compare with missing cases; compare across allowed distinct hardware cohorts; signed successor mismatch; update interruption at every boundary; failed smoke retaining prior selection; rollback digest/reference count; no-embedded-transition UI absence; forged successor action; executed receipt missing embedded snapshot/proof; altered embedded bytes; wrong source/import proof for the machine role; snapshot/transition/dependency/trust mismatch; private field inside an embedded envelope; and a no-transition receipt carrying predecessor bytes. Tests use fake drivers and temporary roots, never launch the user's app.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalWritingQualityHarness '^LocalWritingQualityHarnessTests\.ReleaseUIRunTests/'
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalWritingQualityHarness '^LocalWritingQualityHarnessTests\.ReleaseUIAutomationTests/'
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalWritingQualityHarness '^LocalWritingQualityHarnessTests\.ReleaseQAWorkspaceTests/'
Scripts/run-nonempty-swift-tests.sh --package-path Tools/LocalWritingQualityHarness '^LocalWritingQualityHarnessTests\.ReleaseModelUpdateLifecycleTests/'
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness --self-test-live-ui
```

**Gate:** the external harness is reviewed before 9D freezes the app; it changes no Fleck product target and provides no path for a nonhuman E3 claim.

### Packet 9D — Separately authorized signed candidate build, notarization, and final package

**Depends on:** 0D, 6B3, 9D0, the verified canonical D5 promotion record plus fixed-schema source-evidence bundle and retained 9A ZIP/package receipt, legal review, intended-channel signing/notary authority, and fresh owner authorization. Every optional packet contributing the selected catalog/configuration must already have an accepted diff, qualification receipt, and fresh review.
**Objective:** Replace the deliberate enhanced-release rejection with one exact D5-bound `signedDistributionCandidate`, then sign, notarize, staple, freeze, and package it without claiming that earlier test-ZIP evidence applies to the new bits.

**Owned files:**

- `Package.swift`
- `Sources/FleckCore/DictationModels.swift`
- `Sources/FleckApp/LocalModelCatalog.swift`
- `Sources/FleckApp/LocalModelCatalogSnapshot.swift`
- `Sources/FleckApp/EnhancedReleaseCapability.swift` — new
- `Sources/FleckApp/FleckApp.swift`
- `Scripts/package-local-writing-app.swift`
- `Scripts/verify-packaged-local-writing-receipt.swift`
- `Scripts/package-enhanced-release-zip.sh` — new final post-staple wrapper
- `Scripts/build-enhanced-release-candidate.sh` — new clean build/nested-sign orchestration
- `Scripts/notarize-and-package-enhanced-release.sh` — new submit/wait/staple/freeze/package orchestration
- `Scripts/check-candidate-release-rejected.sh`
- `Scripts/check-release-size.sh`
- `Scripts/test-release-model-asset-exclusion.sh`
- `Scripts/validate-macos.sh`
- `Tests/FleckAppTests/ParakeetTestAppPackagingTests.swift`
- `Tests/FleckAppTests/AdmittedModelDescriptorTests.swift`
- `Tests/FleckAppTests/LocalModelCatalogTests.swift`
- `Tests/FleckAppTests/EnhancedReleaseCapabilityTests.swift` — new

**Required implementation:** require a clean accepted source worktree/commit and reopen the complete 9C D5 evidence before compiling. Transfer the exact verified D5 promotion bundle, 9A ZIP, and 9A package receipt from the authoritative Mac-mini D5 evidence root to the authorized clean build worktree under one digest-checked transfer manifest (even when that build worktree is on the same physical Mac). Verify/import the bundle into the Mac-mini D6 assembly root, reverify the 9A ZIP/app tree/executable against its imported receipt, rerun the no-weight scan, and recompute the D5 record from both run/score pairs and comparison. The build command consumes only that imported immutable record.

**Build-host boundary:** v1 performs 9D only in a clean isolated worktree on the authoritative Mac mini. The source checkout is isolated, but the canonical D5/corpus roots are reopened locally and are never copied into or shared with the worktree. The post-staple app is built in the new `/absolute/private/mac-mini-evidence/d6-assembly/Fleck.app`; the final ZIP and receipt are atomically published directly as `/absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip` and `/absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json`; and the notary receipt is created as `/absolute/private/mac-mini-evidence/d6-build/notary-receipt.json`. These are the exact paths consumed by 9D2/9E—there is no unstated copy or staging step. Before 9D, `d6-assembly`, `d6-build`, and both final package targets must be absent. The wrapper stages within the canonical evidence filesystem, fsyncs, renames the ZIP first and receipt last as the commit marker, and refuses any pre-existing target. A different physical build host is out of scope and stops execution until a separately reviewed return-manifest/import protocol exists.

Promote only the D5 record's exact catalog/configuration/profile/evidence/claim/operator cohort from `.notAdmitted` to embedded `.twoDeviceAccepted`; add a distinct capability binding that tuple and intended channel. Exactly one update-transition mode is required. `none` requires an empty transition list and produces an explicit no-update-claim reason without asserting global predecessor absence. `successor` requires a separately verified previous-release `update-predecessor-record`, previous final ZIP/package receipt, the predecessor's retained live canonical corpus ledger/latest checkpoint/D5 seal plus externally reviewed evaluation-signer fingerprint, and one trust-policy sequence/checkpoint that is both the predecessor D7's original anchor and the current externally pinned latest state; any trust checkpoint change or predecessor corpus invalidation makes `successor` invalid. The build command independently reopens those inputs after the standalone predecessor check, proves the record-bound predecessor corpus head is an ancestor of the supplied current head with an exposure-only seal suffix, and rechecks the checkpoint/head immediately before emitting the app and package receipt. It embeds exactly one 6B nonselectable transition from that release-admitted predecessor to the D5 candidate successor. The transition and final package receipt bind the verified predecessor corpus checkpoint/head/seal/evaluation-signer tuple as well as the trust-policy sequence/checkpoint. The previous configuration is not copied into selectable profiles/configurations, cannot be recommended, and is present only as closed verification/retention metadata. The final package receipt otherwise binds the transition digest or explicit `none` state. No generic candidate flag is accepted; ordinary safe builds remain unchanged; weights remain external; normal UI can expose only the promotion tuple plus safe fallbacks. The signed candidate contains no Quality Lab, controlled-fixture, injected-audio, candidate selector, or development diagnostic entrypoint/symbol. Final E3 uses only normal production hold-to-talk and ordinary note/history behavior observed externally.

The immutable external sequence is: clean release build; sign every nested component and outer app with the intended identity; validate entitlements/designated requirement; create a temporary non-admission notary archive; `notarytool submit --wait` through an approved keychain profile; require accepted result; atomically write and verify the canonical content-free `${evidenceRoot}/notary-receipt.json`; staple; run Gatekeeper and complete post-staple validation; freeze the app; invoke the 7G0 canonical packager; verify by fresh extraction. The notarization wrapper refuses an existing evidence root or a receipt whose request/result/ticket/app/signature digests do not reconcile, so 9E consumes the exact `/absolute/private/mac-mini-evidence/d6-build/notary-receipt.json` produced here rather than an assumed or copied file. No validator silently signs or mutates. The final release receipt's typed `signedDistributionExtension` binds the full imported-promotion-bundle digest and D5 record digest, optional update-transition digest/previous-admission digest plus predecessor-verification trust-policy sequence/checkpoint or explicit no-transition state, intended channel, signing identity/designated requirement, notarization request/result/ticket, final post-staple app tree/executable, and release packaging revision. It cannot bind future D6 evidence; the later D6 receipt binds this final package one-way.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.EnhancedReleaseCapabilityTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelCatalogTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelUpdateTransitionTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(ordinaryConfiguration|admittedConfiguration|descriptorRole|defaultASRCatalog|cleanupCatalog|mixedRequestedLanguages|unsupportedHardware|spaceAboveDownloadBytes|invalidSignedDescriptorInputs)'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.signedReleaseTransition'
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.(parakeetPackager|parakeetTestApp)'
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-promotion-evidence --bundle /absolute/private/mac-mini-evidence/imports/d5-promotion-evidence.json --test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing import-promotion-evidence --bundle /absolute/private/mac-mini-evidence/imports/d5-promotion-evidence.json --test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output-root /absolute/private/mac-mini-evidence/imported/d5-promotion
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/mac-mini-evidence/imported/d5-promotion/test-package-receipt.json --zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --extract-to /absolute/private/mac-mini-evidence/imported/d5-promotion/extracted-test-app --require-class enhancedTestSelectedConfiguration
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/mac-mini-evidence/imported/d5-promotion/test-package-receipt.json --app /absolute/private/mac-mini-evidence/imported/d5-promotion/extracted-test-app/Fleck.app --zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --require-class enhancedTestSelectedConfiguration
Scripts/check-packaged-local-writing-no-weights.sh --app /absolute/private/mac-mini-evidence/imported/d5-promotion/extracted-test-app/Fleck.app --zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-promotion-record --record /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-promotion-record.json --test-package-receipt /absolute/private/mac-mini-evidence/imported/d5-promotion/test-package-receipt.json --mac-mini-run /absolute/private/mac-mini-evidence/imported/d5-promotion/mac-mini-run-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/imported/d5-promotion/mac-mini-score-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/d5-promotion/m1-run-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/d5-promotion/m1-score-receipt.json --comparison /absolute/private/mac-mini-evidence/imported/d5-promotion/two-device-comparison.json --corpus-ledger-verification-receipt /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-corpus-ledger-verification-receipt.json --corpus-seal-verification-receipt /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-corpus-seal-verification-receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_D5_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
Scripts/check-candidate-release-rejected.sh
Scripts/build-enhanced-release-candidate.sh --promotion-record /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-promotion-record.json --promotion-evidence-bundle /absolute/private/mac-mini-evidence/imported/d5-promotion/promotion-evidence-bundle.json --update-transition-mode none --no-transition-reason no-update-claim-for-this-release --signing-identity /absolute/private/mac-mini-evidence/signing-identity-reference.json --channel owner-private-beta --output /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app
Scripts/validate-macos.sh --app /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app --phase pre-notary --evidence-root /absolute/private/mac-mini-evidence/d6-build
Scripts/notarize-and-package-enhanced-release.sh --app /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app --notary-keychain-profile FLECK_APPROVED_PROFILE --output-root /absolute/private/mac-mini-evidence --promotion-record /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-promotion-record.json --promotion-evidence-bundle /absolute/private/mac-mini-evidence/imported/d5-promotion/promotion-evidence-bundle.json --evidence-root /absolute/private/mac-mini-evidence/d6-build
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --app /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --require-class signedDistributionCandidate
Scripts/check-packaged-local-writing-no-weights.sh --app /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip
Scripts/check-release-size.sh /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app
Scripts/test-release-model-asset-exclusion.sh
```

The command above is the explicit no-update-policy form and makes no claim about predecessor existence. A release that elects to embed and validate an update transition instead uses this alternate build command after verifying the previous 9E export and current pinned trust state:

```bash
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.receipt.json --zip /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.zip --extract-to /absolute/private/mac-mini-evidence/previous-release/extracted-release-app --require-class signedDistributionCandidate
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-update-predecessor-record --record /absolute/private/mac-mini-evidence/previous-release/update-predecessor-record.json --admission-record /absolute/private/mac-mini-evidence/previous-release/local-writing-release-admission.json --d6-evidence /absolute/private/mac-mini-evidence/previous-release/d6-evidence-receipt.json --zip /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.receipt.json --app /absolute/private/mac-mini-evidence/previous-release/extracted-release-app/Fleck.app --d5-promotion-root /absolute/private/mac-mini-evidence/previous-release/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/previous-release/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/previous-release/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/previous-release/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/previous-release/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/previous-release/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/previous-release/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/previous-release/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/previous-release/final-two-device-comparison.json --corpus-ledger /absolute/private/previous-release-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/previous-release-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/previous-release-corpus/d5-corpus-admission-seal.json --expected-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256
Scripts/build-enhanced-release-candidate.sh --promotion-record /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-promotion-record.json --promotion-evidence-bundle /absolute/private/mac-mini-evidence/imported/d5-promotion/promotion-evidence-bundle.json --update-transition-mode successor --predecessor-update-record /absolute/private/mac-mini-evidence/previous-release/update-predecessor-record.json --predecessor-admission-record /absolute/private/mac-mini-evidence/previous-release/local-writing-release-admission.json --predecessor-d6-evidence /absolute/private/mac-mini-evidence/previous-release/d6-evidence-receipt.json --predecessor-release-zip /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.zip --predecessor-package-receipt /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.receipt.json --predecessor-corpus-ledger /absolute/private/previous-release-corpus/eligibility-ledger.jsonl --predecessor-corpus-ledger-checkpoint /absolute/private/previous-release-corpus/eligibility-ledger.checkpoint.json --predecessor-corpus-admission-seal /absolute/private/previous-release-corpus/d5-corpus-admission-seal.json --expected-predecessor-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-predecessor-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256 --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256 --signing-identity /absolute/private/mac-mini-evidence/signing-identity-reference.json --channel owner-private-beta --output /absolute/private/mac-mini-evidence/d6-assembly/Fleck.app
```

The verification command shown is the previous release's own no-transition form. If that previous release's admission says `executedTransition`, replace its `--predecessor-corpus-mode none` with the exact 9E live-reopen group for that release's immediate predecessor, then append Packet 6B3's repeatable `--predecessor-corpus-dependency /absolute/private/.../dependency-reopen.json` option for each still-older dependency in signed order. Independently, `build-enhanced-release-candidate.sh` already receives the previous release's current corpus as its immediate successor-transition predecessor; append the same repeatable option once for **every older dependency named by the previous admission**, in signed order. Supply zero options only when the corresponding signed dependency array is empty. Either command rejects a missing, extra, duplicate, reordered, stale, or invalidated descriptor/tuple.

The keychain-profile label above is a placeholder selected at authorized execution; no secret enters the command, repository, receipt, or log. New signed-release transition tests use the `signedReleaseTransition...` prefix. Negative fixtures prove dirty source, changed D5 bundle/package/config/profile/evidence/cohort/channel/signature/notary digest, injected E2 symbol, non-D5 candidate, transition in `none` mode, missing/invalid/revoked predecessor D7/package/catalog, predecessor trust checkpoint older than current, attempted cross-rotation transition, predecessor corpus invalidated after standalone verification but before build, predecessor checkpoint advanced during the build, predecessor exposed as selectable, successor mismatch, multiple transitions, or rollback metadata outside the signed receipt cannot produce the final receipt.

**Gate:** one immutable post-staple ZIP/receipt exists as `signedDistributionCandidate`. It is not yet D6 because it has different bits from 9A and has not passed the fresh final-artifact two-device gate. If promotion/signing is not authorized, stop at private D5 candidate acceptance.

### Packet 9D2 — Final post-staple exact-artifact two-Mac gate

**Depends on:** 9D
**Owned files:** no product or repository source. Run plans, recordings, and receipts remain under each machine's selected private `0700` evidence root.

**Run:** transfer the exact final post-staple ZIP and receipt—never rebuild—to the Mac mini and M1 8 GB MacBook. Also transfer the exact content-free detached `d5-corpus-admission-seal.json` from the already verified D5 promotion bundle to the new, previously absent `/absolute/private/m1-corpus/d5-corpus-admission-seal.json` under the out-of-band transfer manifest; refuse overwrite, require mode `0600` under the selected `0700` root, and verify source/destination bytes and CMS signer before use. Start from the D5-sealed canonical Mac-mini eligibility ledger. The Mac mini appends its final-run exposure events before candidate access, verifies the resulting exposure-only suffix against the D5 seal, then exports one signed ledger extension from the D5 checkpoint together with its content-free run/score envelope and its separately typed update envelope. The M1 verifies that exact parent, imports the ledger extension before its run, appends its own exposure events, verifies the still exposure-only suffix against the transferred seal, and returns a signed extension plus its run/score/comparison and update envelopes. The Mac mini accepts the returned ledger only as an exact-parent fast-forward, becomes the sole authoritative ledger again, reopens the D5 seal against the new current head, and deterministically recomputes the comparison. Private raw receipts, transcripts, and audio never cross machines. On each Mac verify archive/app-tree/executable/signature/staple/Gatekeeper/catalog/config/profile/notices identities and the running executable. Use a dedicated temporary local macOS QA account with the app's ordinary production data location; create the frozen 12-note fixture through normal Fleck UI/import actions and hash/verify it externally, never by a hidden app store override. Install/repair/remove the exact external model artifacts, then run offline relaunch, dictionary, cleanup, sorting/chooser, cancellation, pressure, lifecycle, and persistence checks through production paths. Any invalidation, oracle correction, material mutation, fork, or non-exposure ledger suffix breaks the seal and restarts D5 corpus evidence before packaging; it cannot be repaired by rerunning only 9D2.

If the signed catalog names an exact transition from a previously release-admitted predecessor to this D5-promotion-authorized `signedDistributionCandidate` successor, transfer and verify the previous release's update-predecessor record, D7 admission, D6 evidence, retained final ZIP/package receipt, and public trust-policy checkpoint on both Macs. The Mac mini first reopens the predecessor's current canonical corpus ledger/checkpoint/seal and every signed older dependency, then creates and verifies a content-free CMS-signed predecessor-corpus snapshot bound to the successor package/transition. Only after that producer succeeds may the out-of-band transfer manifest name the snapshot. The M1 verifies the transferred bytes and signer, imports them into a new private root, and supplies the exact imported snapshot plus import receipt to its update run. The Mac mini supplies the locally verified snapshot plus verification receipt to its own update run. Each update plan and receipt binds the snapshot digest, current predecessor tuple, ordered recursive dependency tuple, reviewed evaluation signer, trust checkpoint, and machine role. The snapshot supports the remote update run but never replaces the live Mac-mini reopening required again by D6/D7. In each fresh QA account, install the predecessor app and predecessor model artifacts through its normal signed Settings UI, verify its durable receipt, quit it, install/launch the successor app, and only then exercise Update. Both Macs must stage, verify, smoke, atomically switch, externally interrupt-and-retain-prior, update, and roll back through normal Settings; no direct receipt/store seeding is allowed. 9D2 supplies evidence for the successor's later D6/D7 rather than presuming it admitted. If the current catalog embeds no transition, no snapshot is created, accepted, or supplied; both emit `notApplicableNoEmbeddedTransition`, expose no Update action, reject forged substitution, and D6/D7 make no validated-update claim. This does not assert that no predecessor exists elsewhere, and any later update-capable release must repeat 9D/9D2 with an executed transition. The external harness guides the frozen final E3 real-microphone subset via Accessibility/UI observation of normal hold-to-talk and inspects the QA account's resulting notes/history after each receipt; it cannot inject audio, call internal APIs, synthesize speech, or touch the owner's live account. The signed candidate has no Quality Lab or injected E2 path, so no result may relabel external replay as final-artifact E2.

**Verify:**

For `executedTransition`, the retained previous-release notary receipt is an explicit source/transfer-manifest member on both Macs and must match the notary digest bound by that release's package and D6 evidence; the snapshot commands below refuse a missing or substituted receipt.

The block below is the complete `executedTransition` path. If the immutable package says `notApplicableNoEmbeddedTransition`, omit the four predecessor-snapshot create/verify/import commands and use the two plan-only update-run replacements shown after the block; supplying any snapshot input in that mode is an error.

```bash
# Mac mini: verify and run the exact final artifact.
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --extract-to /absolute/private/mac-mini-evidence/extracted-release-app --require-class signedDistributionCandidate
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --app /absolute/private/mac-mini-evidence/extracted-release-app/Fleck.app --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --require-class signedDistributionCandidate
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run-live-ui --plan /absolute/private/mac-mini-evidence/final-mac-mini-live-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-live-ui --receipt /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-ledger --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --output /absolute/private/mac-mini-evidence/final-mac-mini-ledger-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-admission-seal --seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/final-mac-mini-corpus-seal-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing score-run --plan /absolute/private/mac-mini-evidence/final-mac-mini-live-plan.json --raw-receipts /absolute/private/mac-mini-evidence/final-mac-mini-raw --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_MAC_MINI_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/final-mac-mini-scored
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-score --receipt /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_MAC_MINI_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --summary-output /absolute/private/mac-mini-evidence/final-mac-mini-scored/local-writing-quality-summary.json
# Create and verify before the Mac-mini update run. The command shown is the previous release's own no-transition form. If that release says `executedTransition`, replace `--predecessor-corpus-mode none` with the exact 9E immediate live-reopen group for its predecessor, then append Packet 6B3's exact repeatable --predecessor-corpus-dependency /absolute/private/.../dependency-reopen.json option once per still-older dependency in signed order.
swift run --disable-automatic-resolution fleck-model-eval local-writing create-predecessor-corpus-snapshot --update-record /absolute/private/mac-mini-evidence/previous-release/update-predecessor-record.json --admission-record /absolute/private/mac-mini-evidence/previous-release/local-writing-release-admission.json --d6-evidence /absolute/private/mac-mini-evidence/previous-release/d6-evidence-receipt.json --notary-evidence /absolute/private/mac-mini-evidence/previous-release/notary-receipt.json --zip /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.receipt.json --app /absolute/private/mac-mini-evidence/previous-release/extracted-release-app/Fleck.app --successor-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --d5-promotion-root /absolute/private/mac-mini-evidence/previous-release/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/previous-release/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/previous-release/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/previous-release/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/previous-release/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/previous-release/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/previous-release/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/previous-release/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/previous-release/final-two-device-comparison.json --corpus-ledger /absolute/private/previous-release-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/previous-release-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/previous-release-corpus/d5-corpus-admission-seal.json --expected-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/predecessor-corpus-snapshot.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-predecessor-corpus-snapshot --snapshot /absolute/private/mac-mini-evidence/predecessor-corpus-snapshot.json --update-record /absolute/private/mac-mini-evidence/previous-release/update-predecessor-record.json --admission-record /absolute/private/mac-mini-evidence/previous-release/local-writing-release-admission.json --d6-evidence /absolute/private/mac-mini-evidence/previous-release/d6-evidence-receipt.json --notary-evidence /absolute/private/mac-mini-evidence/previous-release/notary-receipt.json --zip /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/previous-release/Fleck-enhanced-release.receipt.json --successor-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --expected-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256 --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --output /absolute/private/mac-mini-evidence/predecessor-corpus-snapshot-verification.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run-model-update-lifecycle --plan /absolute/private/mac-mini-evidence/final-mac-mini-update-plan.json --predecessor-corpus-snapshot /absolute/private/mac-mini-evidence/predecessor-corpus-snapshot.json --predecessor-corpus-snapshot-verification-receipt /absolute/private/mac-mini-evidence/predecessor-corpus-snapshot-verification.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-model-update-lifecycle --receipt /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness export-model-update-evidence --receipt /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --output /absolute/private/mac-mini-evidence/final-mac-mini-update-evidence.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-model-update-evidence --bundle /absolute/private/mac-mini-evidence/final-mac-mini-update-evidence.json --expected-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-corpus-ledger-extension --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --after-checkpoint /absolute/private/mac-mini-evidence/imported/d5-promotion/d5-corpus-ledger-checkpoint.json --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/final-mac-mini-ledger-extension.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-comparison-evidence --receipt /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --receipt /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --ledger-extension /absolute/private/mac-mini-evidence/final-mac-mini-ledger-extension.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_MAC_MINI_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/final-mac-mini-comparison-evidence.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/mac-mini-evidence/final-mac-mini-comparison-evidence.json --expected-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_MAC_MINI_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256

# M1: verify the same ZIP/receipt, import the verified Mac-mini bundle, and run.
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --zip /absolute/private/m1-evidence/Fleck-enhanced-release.zip --extract-to /absolute/private/m1-evidence/extracted-release-app --require-class signedDistributionCandidate
xcrun swift Scripts/verify-packaged-local-writing-receipt.swift --receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --app /absolute/private/m1-evidence/extracted-release-app/Fleck.app --zip /absolute/private/m1-evidence/Fleck-enhanced-release.zip --require-class signedDistributionCandidate
# After the source verifier succeeds, transfer the exact snapshot under the out-of-band manifest, then verify before importing and consuming it.
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-predecessor-corpus-snapshot --snapshot /absolute/private/m1-evidence/imports/predecessor-corpus-snapshot.json --update-record /absolute/private/m1-evidence/previous-release/update-predecessor-record.json --admission-record /absolute/private/m1-evidence/previous-release/local-writing-release-admission.json --d6-evidence /absolute/private/m1-evidence/previous-release/d6-evidence-receipt.json --notary-evidence /absolute/private/m1-evidence/previous-release/notary-receipt.json --zip /absolute/private/m1-evidence/previous-release/Fleck-enhanced-release.zip --package-receipt /absolute/private/m1-evidence/previous-release/Fleck-enhanced-release.receipt.json --successor-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --expected-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256 --trust-policy /absolute/private/m1-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/m1-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --output /absolute/private/m1-evidence/predecessor-corpus-snapshot-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing import-predecessor-corpus-snapshot --snapshot /absolute/private/m1-evidence/imports/predecessor-corpus-snapshot.json --update-record /absolute/private/m1-evidence/previous-release/update-predecessor-record.json --admission-record /absolute/private/m1-evidence/previous-release/local-writing-release-admission.json --d6-evidence /absolute/private/m1-evidence/previous-release/d6-evidence-receipt.json --notary-evidence /absolute/private/m1-evidence/previous-release/notary-receipt.json --zip /absolute/private/m1-evidence/previous-release/Fleck-enhanced-release.zip --package-receipt /absolute/private/m1-evidence/previous-release/Fleck-enhanced-release.receipt.json --successor-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --expected-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256 --trust-policy /absolute/private/m1-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/m1-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --output-root /absolute/private/m1-evidence/imported/predecessor-corpus
swift run --disable-automatic-resolution fleck-model-eval local-writing import-corpus-ledger-extension --bundle /absolute/private/m1-evidence/imports/final-mac-mini-ledger-extension.json --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-admission-seal --seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/m1-evidence/imported-final-mac-mini-corpus-seal-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/m1-evidence/imports/final-mac-mini-comparison-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_MAC_MINI_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing import-comparison-evidence --bundle /absolute/private/m1-evidence/imports/final-mac-mini-comparison-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_MAC_MINI_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output-root /absolute/private/m1-evidence/imported/final-mac-mini
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-model-update-evidence --bundle /absolute/private/m1-evidence/imports/final-mac-mini-update-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness import-model-update-evidence --bundle /absolute/private/m1-evidence/imports/final-mac-mini-update-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --output-root /absolute/private/m1-evidence/imported/final-mac-mini-update
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run-live-ui --plan /absolute/private/m1-evidence/final-m1-8gb-live-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-live-ui --receipt /absolute/private/m1-evidence/final-m1-8gb-live-receipt.json --compare /absolute/private/m1-evidence/imported/final-mac-mini/final-mac-mini-live-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-ledger --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --output /absolute/private/m1-evidence/final-m1-ledger-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-admission-seal --seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/m1-evidence/final-m1-corpus-seal-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing score-run --plan /absolute/private/m1-evidence/final-m1-8gb-live-plan.json --raw-receipts /absolute/private/m1-evidence/final-m1-8gb-raw --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/m1-evidence/final-m1-8gb-scored
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-score --receipt /absolute/private/m1-evidence/final-m1-8gb-scored/aggregate-receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --summary-output /absolute/private/m1-evidence/final-m1-8gb-scored/local-writing-quality-summary.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run-model-update-lifecycle --plan /absolute/private/m1-evidence/final-m1-8gb-update-plan.json --predecessor-corpus-snapshot /absolute/private/m1-evidence/imported/predecessor-corpus/predecessor-corpus-snapshot.json --predecessor-corpus-snapshot-import-receipt /absolute/private/m1-evidence/imported/predecessor-corpus/snapshot-import-receipt.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-model-update-lifecycle --receipt /absolute/private/m1-evidence/final-m1-8gb-update-receipt.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness export-model-update-evidence --receipt /absolute/private/m1-evidence/final-m1-8gb-update-receipt.json --output /absolute/private/m1-evidence/final-m1-update-evidence.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-model-update-evidence --bundle /absolute/private/m1-evidence/final-m1-update-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing compare-runs --left /absolute/private/m1-evidence/imported/final-mac-mini/aggregate-receipt.json --right /absolute/private/m1-evidence/final-m1-8gb-scored/aggregate-receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/m1-evidence/final-two-device-comparison.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-corpus-ledger-extension --ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --after-checkpoint /absolute/private/m1-evidence/imported/final-mac-mini/eligibility-ledger.checkpoint.json --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/m1-evidence/final-m1-ledger-extension.json
swift run --disable-automatic-resolution fleck-model-eval local-writing export-comparison-evidence --receipt /absolute/private/m1-evidence/final-m1-8gb-live-receipt.json --receipt /absolute/private/m1-evidence/final-m1-8gb-scored/aggregate-receipt.json --receipt /absolute/private/m1-evidence/final-two-device-comparison.json --ledger-extension /absolute/private/m1-evidence/final-m1-ledger-extension.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --signing-identity EVALUATION_KEYCHAIN_IDENTITY --output /absolute/private/m1-evidence/final-m1-return-evidence.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/m1-evidence/final-m1-return-evidence.json --expected-package-receipt /absolute/private/m1-evidence/Fleck-enhanced-release.receipt.json --corpus-ledger /absolute/private/m1-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/m1-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/m1-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256

# Mac mini: import the returned content-free M1 evidence and recompute the comparison.
swift run --disable-automatic-resolution fleck-model-eval local-writing import-corpus-ledger-extension --bundle /absolute/private/mac-mini-evidence/imports/final-m1-ledger-extension.json --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-ledger --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --output /absolute/private/mac-mini-evidence/final-authoritative-corpus-ledger-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-corpus-admission-seal --seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --expected-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/final-authoritative-corpus-seal-verification.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-comparison-evidence --bundle /absolute/private/mac-mini-evidence/imports/final-m1-return-evidence.json --expected-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing import-comparison-evidence --bundle /absolute/private/mac-mini-evidence/imports/final-m1-return-evidence.json --expected-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output-root /absolute/private/mac-mini-evidence/imported/final-m1
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness verify-model-update-evidence --bundle /absolute/private/mac-mini-evidence/imports/final-m1-update-evidence.json --expected-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness import-model-update-evidence --bundle /absolute/private/mac-mini-evidence/imports/final-m1-update-evidence.json --expected-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --output-root /absolute/private/mac-mini-evidence/imported/final-m1-update
swift run --disable-automatic-resolution fleck-model-eval local-writing compare-runs --left /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --right /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --output /absolute/private/mac-mini-evidence/final-two-device-comparison.json
```

For `notApplicableNoEmbeddedTransition`, the common run uses these two replacements and none of the snapshot commands or files above:

```bash
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run-model-update-lifecycle --plan /absolute/private/mac-mini-evidence/final-mac-mini-update-plan.json
swift run --disable-automatic-resolution --package-path Tools/LocalWritingQualityHarness LocalWritingQualityHarness run-model-update-lifecycle --plan /absolute/private/m1-evidence/final-m1-8gb-update-plan.json
```

Each placeholder is replaced by that machine's canonical private root; both plans bind the same final package receipt, frozen subset/threshold revision, D5 seal, reviewed evaluation-signer fingerprint, and exact current ledger checkpoint. Each transfer is performed only after the source bundle and signed ledger extension verify and before destination import; source and destination digests must match an out-of-band transfer manifest. The Mac mini root containing its fast-forwarded canonical ledger, current checkpoint, verified D5 seal, local receipts, imported M1 receipts, and recomputed comparison becomes the sole 9E D6 assembly root. **Gate:** zero critical events and frozen noninferiority/latency/resource ceilings on both Macs, with an exposure-only suffix from the D5 seal checkpoint. A product/evidence failure returns to a bounded repair and then restarts 9D packaging and all of 9D2; a ledger invalidation or seal failure restarts D5 corpus evidence as well. No earlier test-ZIP result is carried across changed bits.

### Packet 9E — D6 evidence and detached D7 owner admission

**Depends on:** 0C, 6B3, 9D2, the final channel receipts, and separately reviewed bootstrap inputs: exact public certificate bytes, their out-of-band SHA-256 fingerprint, validity interval, an owner-controlled latest-state location outside tool/app/evidence-root write authority, and authorization to create then externally pin the initial trust-policy checkpoint. Creating D7 additionally requires a fresh explicit owner decision after that checkpoint is pinned; approval of this program is not D7 authorization.
**Owned files:**

- `Sources/FleckModelEvaluation/LocalWritingReleaseAdmissionCreation.swift` — new D6/D7 canonical creation using the 6B3 vocabulary
- `Sources/FleckModelEvaluation/LocalWritingAdmissionTrustPolicyMutation.swift` — new bootstrap/rotation/revocation creation using the 6B3 vocabulary
- `Sources/FleckModelEvaluation/LocalWritingUpdatePredecessorRecordCreation.swift` — new signed future-successor export using the 6B3 vocabulary
- `Sources/FleckModelEvaluator/ReleaseAdmissionCommand.swift` — extend the 6B3 verification adapter with authorized creation commands
- `Sources/FleckModelEvaluator/main.swift` — add exact creation-command dispatch
- `Tests/FleckModelEvaluationTests/LocalWritingReleaseAdmissionCreationTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingAdmissionTrustPolicyMutationTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingUpdatePredecessorRecordCreationTests.swift` — new
- `Tests/FleckModelEvaluationTests/LocalWritingReleaseAdmissionCreationCommandTests.swift` — new
- `Scripts/verify-local-writing-release-admission.sh` — new
- `docs/release/local-writing-admission-trust-policy.md` — new bootstrap/rotation/revocation procedure; no private key
- `ARCHITECTURE.md`
- `IMPLEMENTATION_STATUS.md`
- `TESTING.md`

**Required implementation:** reuse Packet 6B3's single canonical payloads and strict verifiers; do not redefine or fork their schemas. Add authorized creation of the unsigned content-addressed D6 evidence receipt and authorized detached-CMS signing workflows for D7, trust-policy changes, and the future-update predecessor record. Every canonical payload uses NFC strings, integer Unix milliseconds, sorted unique arrays, absent optionals, and duplicate/unknown-key and noncanonical-byte rejection. D6 gains integrity from full source recomputation and is then bound by signed D7; it is never described as independently signed. A detached CMS envelope's self-described fingerprint is never trusted. Every trust policy has a checked unsigned 64-bit monotonic `policySequence` and, except bootstrap sequence 1, the exact previous checkpoint digest. `verify-admission-trust-policy` emits a canonical checkpoint receipt binding policy bytes/digest, sequence, previous checkpoint digest, reviewed fingerprint, certificate digest, validity interval, and verifier revision.

The owner maintains the current `{ policySequence, checkpointSHA256 }` in an out-of-band latest-state record outside the repository, app bundle, private evidence root, and write authority of these commands. After bootstrap/rotation/revocation creates a checkpoint, execution pauses until its digest is reviewed and that external record is explicitly advanced. Every D6/D7 create/verify, predecessor-export, rotate, and revoke path requires `--expected-policy-sequence` plus `--expected-policy-checkpoint-digest`, recomputes both, and rejects an older or forked checkpoint even when its certificate and validity remain otherwise acceptable. Every D6/D7 and update-predecessor create/verify command also requires exactly one `--predecessor-corpus-mode`. `none` is valid only when the signed package has `notApplicableNoEmbeddedTransition` and rejects every predecessor input. `reopen` is valid only for `executedTransition` and requires the predecessor's retained live canonical ledger, latest checkpoint, D5 seal, expected current head, and reviewed evaluation-signer fingerprint. Each command independently opens and verifies those paths, proves the predecessor record/package-bound head is an ancestor with an exposure-only suffix, then reopens the checkpoint immediately before writing or accepting output; a mid-command advance or invalidation fails closed. For a predecessor whose own admission record names older executed-transition corpus dependencies, each command additionally receives Packet 6B3's exact repeatable `--predecessor-corpus-dependency <absolute-descriptor-path>` option once per dependency in signed order and reopens every descriptor's live artifacts; zero is legal only for an empty signed array, and omission, duplication, or reordering fails. For `executedTransition`, D6/D7 additionally require the current expected trust values to equal the original trust anchor in the predecessor D7/update record and the predecessor-verification anchor embedded by 9D in both the transition and final package receipt. This version has no current-anchor-authorized historical-signer ledger: any latest-state advance after predecessor D7 rejects successor mode. If the advance happens after 9D, the package and 9D2 evidence are discarded and repeated in explicit `none` mode; D6 cannot bless or re-sign stale transition metadata. Initial bootstrap requires exact public certificate bytes plus an out-of-band reviewed fingerprint. Rotation requires current policy/checkpoint/latest-state inputs, `nextSequence == currentSequence + 1`, exact incoming certificate bytes plus their separately reviewed fingerprint, and dual current/incoming CMS signatures. The dual signature authorizes only the new policy, not historical predecessor releases. Revocation requires the current latest-state anchor, an unrevoked active authority, reason/time, and the same exact +1 sequence rule. Compromise/revocation of the sole active root stops D7 and requires a new explicit out-of-band bootstrap; it cannot self-authorize replacement. Private keys stay in the approved local keychain. The one-owner program does not claim a public transparency log; general release requires a separate multi-party/latest-state design.

First create a canonical D6 evidence receipt that binds and **reopens** the unchanged 9D ZIP/app tree/executable; imported D5 promotion bundle; exact 9A test ZIP/package receipt; both D5 run/score pairs and D5 comparison; promotion/notary/signing/channel receipts; both 9D2 live-run receipts; both independently verified final score aggregates; both signed-identity model-update lifecycle/absence receipts; the recomputed final comparison; complete cohorts/thresholds/zero-event gates; the live Mac-mini canonical eligibility ledger/latest checkpoint; the still-valid D5 corpus seal and reviewed evaluation-signer fingerprint; and the latest trust-policy sequence/checkpoint digest. D6 creation and every later verification reopen the full current ledger, prove the D5 and receipt-bound heads are ancestors, require the seal suffix to contain exposure events only, reject any consumed-lineage invalidation, and bind the current checkpoint/head, eligibility-verification receipt, seal, and evaluation signer into D6. They also reverify the 9A ZIP against its receipt, recompute D5 from every imported source receipt, require that D5 digest equals the signed-distribution extension, then reconcile the final run/score/update receipts against the final package/configuration/profile identities and comparison. For an executed transition, they require exact equality among the current externally pinned trust anchor, transition fields, final package receipt, both update receipts, and the predecessor's independently reopened current corpus ledger/seal. A mismatch stops admission and restarts 9D/9D2; a corpus invalidation or seal failure returns to D5 with fresh blinded material. A signed extension, old checkpoint, or comparison that merely names unknown digests is insufficient.

An `executedTransition` update claim requires the same previously release-admitted predecessor and D5-promotion-authorized candidate-successor tuple on both Macs; the successor becomes admitted only through the resulting D6/D7 decision. `notApplicableNoEmbeddedTransition` permits only an explicit no-update claim, makes no global predecessor-absence claim, and prevents D7 from claiming validated update behavior. Then verify pre-D7 state still reports only `signedDistributionCandidate`. Only after a new owner authorization may the tool create/sign `ownerPrivateBeta` D7; `create-release-admission` invokes the same full D6/D5/final-artifact plus live-ledger/seal verifier from the supplied source inputs before signing and cannot accept a standalone self-consistent D6 receipt. It binds the current corpus checkpoint/head, eligibility-verification receipt, D5 seal, and reviewed evaluation-signer fingerprint into D7. It cannot unlock runtime behavior, mutate catalog/app, rebuild, or broaden to general English. After D7 verifies, create and verify a separately CMS-signed `update-predecessor-record` for a future successor. It binds this D7/D6, final ZIP/package/app-tree/executable, embedded catalog/config/profile and closed artifact manifests, installation-receipt/runtime-compatibility revisions, transition schema, current corpus checkpoint/head/seal/evaluation signer, and latest trust anchor. Every future predecessor verification reopens that release's retained current canonical ledger/checkpoint and seal; a later relevant invalidation makes the transition unverifiable and revokes its current release-evidence status even though the historical signed admission record remains auditable. The predecessor record is nonselectable metadata and grants no current runtime permission; a future 9D must still verify it against the retained exact previous ZIP/package, current corpus state, and current trust latest-state record.

The D6 creator's explicit `--release-package-receipt` and `--notary-evidence` inputs are copied unchanged into the bounded content-free D6 receipt and then recomputed, not merely represented by hashes. `verify-d6-evidence` reopens those embedded canonical bytes and checks them against its explicit `--zip`/`--app` plus the supplied source chain; it intentionally has no second package/notary path that could diverge. Every pre-D7, D7, and update-predecessor verifier reuses that same strict D6 verifier, reopens the embedded package/notary bytes, and requires its separately supplied package receipt to be byte-identical. Signing identity and channel are rederived from that receipt and the code-sign/notary evidence rather than accepted as free flags.

**Additional red tests:** D6 creation with a missing/swapped final ZIP or extracted app; missing, noncanonical, altered, or mismatched embedded package/notary bytes; a predecessor lineage invalidated after 9D's standalone verification but before build; after build but before D6; between D6 creation and verification; between D6 and D7; after D7 but before update-predecessor export; and during any verifier invocation. Also reject a stale predecessor head, an otherwise valid old seal/checkpoint, missing/reordered transitive predecessor corpus context, `none` mode with predecessor inputs, `reopen` mode without every required input, and a mode that disagrees with the immutable final package receipt.

**Verify:**

The policy-creation, initial verification, and first `shasum` lines below are bootstrap-only. A later release must not recreate sequence 1; it starts with `verify-admission-trust-checkpoint` against the current externally pinned sequence/digest and the retained policy/checkpoint bytes.

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingReleaseAdmissionCreationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingAdmissionTrustPolicyMutationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingUpdatePredecessorRecordCreationTests/'
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\.LocalWritingReleaseAdmissionCreationCommandTests/'
swift run --disable-automatic-resolution fleck-model-eval local-writing create-admission-trust-policy --certificate /absolute/private/mac-mini-evidence/admission-public.cer --expected-fingerprint REVIEWED_SHA256 --policy-sequence 1 --valid-from-unix-ms VALID_FROM --valid-until-unix-ms VALID_UNTIL --output /absolute/private/mac-mini-evidence/release-admission-trust-policy.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-admission-trust-policy --policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --expected-fingerprint REVIEWED_SHA256 --expected-policy-sequence 1 --checkpoint-output /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json
shasum -a 256 /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-admission-trust-checkpoint --policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing create-d6-evidence --release-package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --app /absolute/private/mac-mini-evidence/extracted-release-app/Fleck.app --notary-evidence /absolute/private/mac-mini-evidence/d6-build/notary-receipt.json --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256 --output /absolute/private/mac-mini-evidence/d6/evidence-receipt.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-d6-evidence --receipt /absolute/private/mac-mini-evidence/d6/evidence-receipt.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --app /absolute/private/mac-mini-evidence/extracted-release-app/Fleck.app --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256
Scripts/verify-local-writing-release-admission.sh --require-absent --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --d6-evidence /absolute/private/mac-mini-evidence/d6/evidence-receipt.json --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing create-release-admission --d6-evidence /absolute/private/mac-mini-evidence/d6/evidence-receipt.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --app /absolute/private/mac-mini-evidence/extracted-release-app/Fleck.app --package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --decision ownerPrivateBeta --approver APPROVER_ID --decided-at-unix-ms DECISION_TIME --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256 --signing-identity OWNER_ADMISSION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/d7/local-writing-release-admission.json
Scripts/verify-local-writing-release-admission.sh --record /absolute/private/mac-mini-evidence/d7/local-writing-release-admission.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --d6-evidence /absolute/private/mac-mini-evidence/d6/evidence-receipt.json --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing create-update-predecessor-record --admission-record /absolute/private/mac-mini-evidence/d7/local-writing-release-admission.json --d6-evidence /absolute/private/mac-mini-evidence/d6/evidence-receipt.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --app /absolute/private/mac-mini-evidence/extracted-release-app/Fleck.app --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256 --signing-identity OWNER_ADMISSION_KEYCHAIN_IDENTITY --output /absolute/private/mac-mini-evidence/d7/update-predecessor-record.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-update-predecessor-record --record /absolute/private/mac-mini-evidence/d7/update-predecessor-record.json --admission-record /absolute/private/mac-mini-evidence/d7/local-writing-release-admission.json --d6-evidence /absolute/private/mac-mini-evidence/d6/evidence-receipt.json --zip /absolute/private/mac-mini-evidence/Fleck-enhanced-release.zip --package-receipt /absolute/private/mac-mini-evidence/Fleck-enhanced-release.receipt.json --app /absolute/private/mac-mini-evidence/extracted-release-app/Fleck.app --d5-promotion-root /absolute/private/mac-mini-evidence/imported/d5-promotion --d5-test-zip /absolute/private/mac-mini-evidence/imports/Fleck-enhanced-test.zip --mac-mini-run /absolute/private/mac-mini-evidence/final-mac-mini-live-receipt.json --mac-mini-score /absolute/private/mac-mini-evidence/final-mac-mini-scored/aggregate-receipt.json --mac-mini-update /absolute/private/mac-mini-evidence/final-mac-mini-update-receipt.json --m1-run /absolute/private/mac-mini-evidence/imported/final-m1/final-m1-8gb-live-receipt.json --m1-score /absolute/private/mac-mini-evidence/imported/final-m1/aggregate-receipt.json --m1-update /absolute/private/mac-mini-evidence/imported/final-m1-update/final-m1-8gb-update-receipt.json --comparison /absolute/private/mac-mini-evidence/final-two-device-comparison.json --corpus-ledger /absolute/private/mac-mini-corpus/eligibility-ledger.jsonl --corpus-ledger-checkpoint /absolute/private/mac-mini-corpus/eligibility-ledger.checkpoint.json --corpus-admission-seal /absolute/private/mac-mini-corpus/d5-corpus-admission-seal.json --expected-corpus-head CURRENT_M1_FINAL_CORPUS_HEAD_SHA256 --expected-evaluation-fingerprint REVIEWED_EVALUATION_SHA256 --predecessor-corpus-mode none --trust-policy /absolute/private/mac-mini-evidence/release-admission-trust-policy.json --trust-policy-checkpoint /absolute/private/mac-mini-evidence/release-admission-trust-policy.checkpoint.json --expected-policy-sequence POLICY_SEQUENCE --expected-policy-checkpoint-digest REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint REVIEWED_SHA256
```

The seven commands from `create-d6-evidence` through `verify-update-predecessor-record` above are the executable no-transition form. When and only when the immutable final package receipt says `executedTransition`, **each of those seven commands** must replace its single `--predecessor-corpus-mode none` token with this complete live-reopen argument group; omission on even one create or verify path is a hard error:

```bash
--predecessor-corpus-mode reopen --predecessor-corpus-ledger /absolute/private/previous-release-corpus/eligibility-ledger.jsonl --predecessor-corpus-ledger-checkpoint /absolute/private/previous-release-corpus/eligibility-ledger.checkpoint.json --predecessor-corpus-admission-seal /absolute/private/previous-release-corpus/d5-corpus-admission-seal.json --expected-predecessor-corpus-head PREVIOUS_RELEASE_CURRENT_CORPUS_HEAD_SHA256 --expected-predecessor-evaluation-fingerprint PREVIOUS_RELEASE_REVIEWED_EVALUATION_SHA256
```

If the predecessor admission itself names older executed-transition corpus dependencies, append Packet 6B3's exact `--predecessor-corpus-dependency /absolute/private/.../dependency-reopen.json` option once per signed dependency in canonical order to **each** of the seven commands. Every invocation reopens every descriptor; no prior command's success receipt substitutes for the live inputs.

Operational rotation/revocation commands are implemented and tested but are never run as part of ordinary admission:

```bash
swift run --disable-automatic-resolution fleck-model-eval local-writing rotate-admission-trust-policy --current-policy /absolute/private/trust/current-policy.json --current-checkpoint /absolute/private/trust/current-policy.checkpoint.json --expected-policy-sequence CURRENT_POLICY_SEQUENCE --expected-policy-checkpoint-digest CURRENT_REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-current-fingerprint CURRENT_REVIEWED_SHA256 --next-policy-sequence NEXT_POLICY_SEQUENCE --incoming-certificate /absolute/private/trust/incoming-public.cer --expected-incoming-fingerprint INCOMING_REVIEWED_SHA256 --current-signing-identity CURRENT_KEYCHAIN_IDENTITY --incoming-signing-identity INCOMING_KEYCHAIN_IDENTITY --valid-from-unix-ms VALID_FROM --valid-until-unix-ms VALID_UNTIL --output /absolute/private/trust/rotated-policy.json --checkpoint-output /absolute/private/trust/rotated-policy.checkpoint.json
shasum -a 256 /absolute/private/trust/rotated-policy.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-admission-trust-checkpoint --policy /absolute/private/trust/rotated-policy.json --checkpoint /absolute/private/trust/rotated-policy.checkpoint.json --expected-policy-sequence NEXT_POLICY_SEQUENCE --expected-policy-checkpoint-digest NEXT_REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint INCOMING_REVIEWED_SHA256
swift run --disable-automatic-resolution fleck-model-eval local-writing revoke-admission-trust-anchor --policy /absolute/private/trust/current-policy.json --policy-checkpoint /absolute/private/trust/current-policy.checkpoint.json --expected-policy-sequence CURRENT_POLICY_SEQUENCE --expected-policy-checkpoint-digest CURRENT_REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-authority-fingerprint CURRENT_REVIEWED_SHA256 --next-policy-sequence NEXT_POLICY_SEQUENCE --revoked-fingerprint REVOKED_SHA256 --reason-code REASON_CODE --authorized-at-unix-ms REVOCATION_TIME --signing-identity CURRENT_KEYCHAIN_IDENTITY --output /absolute/private/trust/revoked-policy.json --checkpoint-output /absolute/private/trust/revoked-policy.checkpoint.json
shasum -a 256 /absolute/private/trust/revoked-policy.checkpoint.json
swift run --disable-automatic-resolution fleck-model-eval local-writing verify-admission-trust-checkpoint --policy /absolute/private/trust/revoked-policy.json --checkpoint /absolute/private/trust/revoked-policy.checkpoint.json --expected-policy-sequence NEXT_POLICY_SEQUENCE --expected-policy-checkpoint-digest NEXT_REVIEWED_POLICY_CHECKPOINT_SHA256 --expected-fingerprint CURRENT_REVIEWED_SHA256
```

Uppercase values are explicit execution-time authority inputs, never inferred defaults. A `shasum` line is an authority pause: the following checkpoint verification and every admission command remain blocked until that digest and sequence are reviewed and written to the independent latest-state record. Tests cover duplicate/unknown keys, non-NFC, float/date ambiguity, unsorted arrays, wrong/stale/revoked/self-described signer, invalid/non-`+1` rotation/revocation, replay of pre-rotation and pre-revocation policies/checkpoints, forked same-sequence policy, changed externally pinned digest, attempted historical-signer/cross-rotation predecessor transition, forced fallback to no embedded transition, changed D5 source/ZIP, changed final ZIP/tree/executable/catalog/profile/evidence/cohort, predecessor-record forgery, and pre/post-D7 app hash equality.

**Gate:** D6 exists only after the complete D5 source chain and fresh final-bit two-device evidence verify under the externally pinned latest trust state. D7 exists only after the separately authorized owner signature binds those unchanged bits, and the future-successor predecessor record must verify before the release evidence is archived. The one-operator program supports only `ownerPrivateBeta`; general English requires the separate multi-speaker cohort. No push, PR, merge, GitHub change, publication, or release without fresh authorization.

## Dependency graph

This is a navigation summary. Each packet's explicit `Depends on` field is authoritative.

```text
Phase 0: 0A + 0B; 0B -> 0C + 0D

Evidence: 1B -> 1C; 1A + 1B + 1C + 6A + 6B3 + 6D2 -> 7A -> 7B
Dictionary: 2A -> 2B -> 2B2 -> 2B3 -> 2D; 1C + 2B2 -> 2C
Dictation: 1C + 2C -> 3A -> 3B -> 3D; 2C -> 3C1; 3A + 3C1 -> 3C2;
           3A + 3B + 3C2 + 3D -> 3E
Cleanup: 1A + 3A + 4A -> 4B1 -> 4B2; 4B1 -> 4C;
         3A + 3B + 4B1 + 4C -> 4D; 2D + 4D -> 4E
Sorting: 2B2 + 2C + 4D -> 5A; 4D + 5A -> 5B; 4E + 5B -> 5C
Catalog: 6A -> 6B; 1A + 6B -> 6B2; 1A + 6A + 6B2 -> 6B3;
         1B + 1C + 6A + 6B -> 6C;
         3E + 4B1 + 5B + 6C -> 6D1; 5C + 6D1 -> 6D2 -> 6D3 -> 6D4;
         2D + 4E + 6B + 6B3 + 6C + 6D4 -> 6E
Quality storage: 1A -> 7D; 1A + 7D -> 7D4; 5C + 7D4 -> 7D2;
                 1A + 7D -> 7D3; 7D -> 7E
Quality paths: 6D3 + 7A + 7D3 -> 7C; 7C + 7D3 + 7E -> 7C2;
               6E + 7C2 + 7D2 + 7D4 -> 7F
Quality tools: 0D + 6B + 6D4 -> 7G0; 7B + 7C2 + 7G0 -> 7G
ASR candidates: 6A + 6B + 7A -> 7H; 3D + 7C2 + 7H -> 7I;
                3D + 7G -> 7I1; 7I + 7I1 -> 7I2 + [7J conditional];
                [7K conditional is amended before execution]
Writing candidates: 4B2 + 5B + 6B + 6D4 + 7A + 7G -> 7L1 -> [7L2 conditional]
Facade: 3E + 4E + 5C + 6E + 7C2 + every executed candidate-wiring packet -> 8A -> 8B
Package/admission: 6E + 7F + 7G + 7L1 + 8B + chosen-profile qualification -> 9A;
                   9A -> 9B -> 9C; 7G + 9C -> 9D0;
                   0D + 6B3 + 9D0 + verified D5 promotion/authority -> 9D -> 9D2;
                   6B3 + 9D2 -> 9E
```

## Parallel execution map

After Phase 0 and routing approval, the maximum useful first wave is:

- **Agent A:** Packet 1A, evaluation schema only.
- **Agent B:** Packet 2A, FleckCore dictionary migration only.
- **Agent C:** Packet 4A, cleanup regression tests/kernel only.

These own disjoint files. Packet 6A can replace one lane after its predecessor completes. App integration packets touching `FleckApp.swift`, `DictationCoordinator.swift`, `DictationInterfaces.swift`, `DictationProcessingModels.swift`, or `StreamingDictationProcessor.swift` remain sequential.

Every implementer receives:

1. objective and success criteria;
2. exact owned files/interfaces/constraints;
3. required implementation and non-goals;
4. red-first and verification commands;
5. authority boundary and handoff format.

Every implementer is told that concurrent work exists, must not revert it, and must modify no path outside ownership. The primary owner independently inspects the diff and reruns verification. A fresh reviewer inspects the actual diff/evidence; dependent work waits for the required verdict.

## Program-level verification

Focused commands vary by packet. Before packaged admission:

```bash
Scripts/run-nonempty-swift-tests.sh '^.+$'
Scripts/build-fleck-app.sh
FLECK_ENHANCED_CANDIDATE=1 Scripts/build-parakeet-test-app.sh
Scripts/run-nonempty-enhanced-tests.sh '^FleckAppTests\.'
Scripts/check-release-size.sh .build/Fleck.app
Scripts/check-candidate-release-rejected.sh
Scripts/validate-macos.sh
```

Commands are examples from the current tree and must be revalidated against the chosen base. A no-match test filter is a failure of verification, not a pass. Existing unrelated/flaky failures must be reconciled by exact test and rerun evidence; they cannot be hidden by broad retries.

## Stop and escalation rules

Stop the affected packet—not the whole safe program—when:

- exact artifact/license/terms are contradictory;
- a model download or external write lacks authorization;
- an owned file overlaps unaccepted concurrent work;
- a required runtime/profile is unavailable;
- a critical zero-event gate fails;
- a protected violation occurs;
- an automatic route is wrong;
- a cancellation publishes late output;
- artifact identity differs between build and test;
- the routing policy remains contradictory.

Diagnose the smallest responsible boundary, add a red case, and issue a corrected packet. Do not loosen admission thresholds after seeing results.

## User-visible checkpoints

1. **Architecture approved** — documentation only.
2. **Instrumented baseline** — same behavior, measurable stages/corpus contracts.
3. **Reliable terminology and first-word capture** — ready for a focused live dictation test.
4. **Cleanup and correction accepted** — ready for real cleanup cases.
5. **Universal sorting accepted** — ready for controlled workspace routing.
6. **One recommended model configuration** — ready for model install/repair/lifecycle test.
7. **Mac mini candidate accepted** — exact local package and evidence.
8. **M1 8 GB candidate accepted** — identical transferred package.
9. **Distribution gate complete** — ready for explicit release decision.
