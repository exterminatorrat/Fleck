# Fleck Local Writing Intelligence Parallel Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` with strict red-first TDD. Each packet is implemented by one Codex-native GPT-5.6 Sol/High subagent in its own isolated worktree, then independently verified by the primary and reviewed by a fresh Sol/High reviewer. A packet is accepted only on verdict `ship`.

**Goal:** Finish Fleck's English-first, Apple-Silicon local dictation, faithful cleanup, semantic sorting, personal dictionary, curated model management, adaptive lifecycle, private quality evidence, and packaged two-Mac test path without cloud processing or bundled model weights.

**Architecture:** Keep the existing capture-to-insertion transaction and deepen its seams rather than replace it: one capture-pinned dictionary, one capture-pinned model configuration, one cancellation authority, deterministic fail-closed cleanup and Inbox fallback, and immutable content-free evidence. Execute independent packets in three parallel lanes, integrate accepted commits serially into the program branch, and never allow a dependent packet to consume an unreviewed diff.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing, SwiftUI/AppKit on macOS, Apple Speech, FluidAudio/Core ML candidate adapters, native MLX Swift Gemma helper, POSIX same-filesystem file publication, local JSON/JSONL evidence, shell/Swift packaging tools.

**Spec:** `docs/superpowers/plans/2026-08-29-local-writing-intelligence-program.md` and the six design documents it names are binding. This plan supplies the approved execution order, parallelism, checkpoints, and plan corrections; packet requirements and exact owned paths remain authoritative in the master plan unless this file explicitly narrows or corrects them.

## Global constraints

- Target Apple Silicon and English-only for this iteration.
- Speech, transcripts, note content, dictionaries, prompts, recordings, and model execution remain local.
- No cloud transcription, transcript upload, hidden network fallback, or bundled model weights.
- Apple Speech and deterministic cleanup/routing remain safe fallbacks until an exact enhanced configuration is admitted.
- Parakeet TDT 0.6B v2 and Gemma 3 1B are development candidates, not release-admitted models.
- Candidate code, unit tests, injected audio, and packaged smoke are separate proof levels.
- A cleanup candidate is discarded on one protected-span, number/date, negation/modality, command, URL/path, technical-term, lexical, or meaning violation.
- Uncertain routing persists to Inbox and offers a chooser; cleanup-only evidence can never choose a destination.
- Normal Settings shows exactly one recommendation. Advanced choices are curated and truthfully labeled.
- Model installation is explicit, resumable, checksum/revision verified, atomic, cancellable, repairable, removable, and scoped to the selected artifact tree.
- No push, PR, merge, GitHub mutation, signing, notarization, publication, or new model-weight download without the separate authority those actions require.
- Preserve the dirty root checkout and every unrelated branch/worktree.
- Every test command uses an anchored canonical identifier regex with both `^` and `$`, reports a positive match count, and preserves `Package.resolved` exactly.

## Accepted starting checkpoint

- Program worktree: `${FLECK_REPO}/.worktrees/local-writing-intelligence-program`
- Branch: `codex/local-writing-intelligence-program`
- Accepted HEAD: `3372a096e51fe638693bad93c15405a263729dbe`
- Accepted foundations: authority/base/docs/runners, the 1A1 corpus-manifest core, stage/physical receipts, dictionary-v2 values/codec/compiler, and cleanup validator regressions.
- Reconciliation correction: the accepted tree does **not** contain `LocalWritingExposureLedger.swift`, `LocalWritingEvidence.swift`, or their tests. The master plan's Packet 1A is therefore split into remaining Packets 1A2 and 1A3 below; no later packet may treat all of 1A as complete until both ship.
- Current lockfile SHA-256: `ccf30f62d44719e9859266a373bb0219dbbd1e0f73d17667b50d7d87715a09f7`
- Not yet proven: real microphone, model qualification, packaged-app behavior, two-Mac identity, signing, release readiness, or release admission.

## Orchestration model

At most three implementation agents run simultaneously; the primary is the fourth active lane. Parallel packets must have accepted prerequisites, isolated worktrees, and disjoint ownership. Each packet follows this loop:

1. Freeze a five-part brief: objective, ownership/interfaces, implementation/non-goals, exact verification, and authority/handoff.
2. Create or verify an isolated worktree from the packet's frozen accepted product base. For Wave 1 that base remains `3372a096e51fe638693bad93c15405a263729dbe`; the reviewed plan is committed as a documentation-only checkpoint on the integration branch and does not silently change any Wave 1 product diff base.
3. Record a red test that fails for the missing behavior.
4. Add the minimum implementation that makes the red test green.
5. Run focused compatibility checks, diff checks, scope checks, lock hash, and clean status.
6. Commit locally and return the report; never push or open a PR.
7. Primary reads the entire diff and reruns the exact gates.
8. Fresh Sol/High reviewer returns `ship`, `fix-first`, or `rethink`.
9. `fix-first` returns to the same implementer; `rethink` returns to primary architecture. Only `ship` permits integration.
10. Cherry-pick accepted commits serially, rerun the integrated selectors, update the recovery ledger, and release dependent packets.

## Proof ladder

The program never collapses these states:

1. Documented design.
2. Code exists.
3. Focused tests pass.
4. Fresh review says `ship`.
5. Integrated program branch passes.
6. Exact model executes against frozen local material.
7. Real microphone/human speech passes.
8. Exact packaged app passes.
9. Same packaged artifact passes on both hardware cohorts.
10. Separately signed/notarized candidate passes post-staple validation.
11. Owner explicitly admits an exact configuration for an exact claim scope.

## Parallel wave graph

| Wave | Lane A | Lane B | Lane C | Integration milestone |
| --- | --- | --- | --- | --- |
| 1 | 2B2 dictionary publication | 6A catalog schema | 1A2 exposure ledger | Three missing, disjoint foundations accepted. |
| 2 | 2C capture-pinned dictionary | 6B exact catalog snapshot | 1A3 evaluation evidence contracts | Capture identity, truthful build catalogs, and the complete 1A evidence vocabulary exist. |
| 3 | 2B3 dictionary transfer | 3A capture-first arming | 6B2 historical archive | Transfer, first-word architecture, and evidence history progress independently. |
| 4 | 2D dictionary Settings | 7D1 private corpus workspace | available repair lane | Dictionary UX and the secure empty-corpus authority exist without inventing premature release schemas. |
| 5a | 3C1 Apple terminology | 7D5 private-material lifecycle | 6B4 recommendation-ready snapshot closure | Apple context, secure corpus mutation/export, and truthful configuration-level recommendation authority advance. |
| 5b | available repair lane | available repair lane | 6C hardware recommender | The pure recommender consumes the accepted closed snapshot rather than inventing a shadow catalog. |
| 6 | 3B Parakeet audio-first | 3C2 Apple release tail | 4B1 Gemma cleanup contract | Both ASR paths and faithful local cleanup improve independently. |
| 7 | 4B2 Gemma harness parity | 4C history baselines | 7D4 corpus templates/oracles | Product/helper parity, correction provenance, and corpus preparation advance. |
| 8 | 3D Parakeet context truth | 4D receipt-safe correction | 7D3 controlled routing workspaces | ASR context, safe correction, and routing fixtures progress. |
| 9 | 4E correction UI | 5A dictionary-aware retrieval | 7E quality recorder | User correction, retrieval, and private recording contracts progress. |
| 10 | 5B dual-evidence routing | 3E packaged first-word smoke | available repair lane | Cleanup cannot invent routing evidence; ambiguity goes to Inbox while the physical smoke gate runs. |
| 11 | 5C content-free feedback | 6D1 joint lifecycle policy | available repair lane | Feedback and adaptive residency become possible after their distinct prerequisites. |
| 12 | 6D2 pinned model identity | available repair lane | available repair lane | Every stage and history row carries one exact configuration identity. |
| 13 | 6D3 runtime composition | 7A corpus runner/scorer | 7D2 feedback review bridge | Product runtime and private evidence tooling become connected but remain separate. |
| 14 | 6D4 lifecycle stress | 7B adapter evidence bridge | 7H 110M catalog profile | Stress, adapter protocol, and lightweight metadata are independently verified. |
| 15 | 6E1 installer/update core | 7C injected-audio path | 7G0 package identity engine | Model operations, E2 execution, and canonical packaging progress in parallel. |
| 16 | 6E2 Settings presentation | 7C2 live-microphone session | available repair lane | Compact model UI and the E3 contract are ready. |
| 17 | 7F Quality Mode UI | 7I 110M adapter | 7G packaged harness | User recording UI, challenger adapter, and package runner are complete. |
| 18 | 7I1 Parakeet qualification | 7L1 cleanup/routing qualification | evidence ledger serialization | Exact role evidence is produced sequentially at the authoritative ledger head. |
| 19 | conditional 7I2/7J/7K/7L2 | conditional lane | conditional lane | Only triggered challengers are implemented or evaluated. |
| 20 | 8A LocalWriting facade | — | — | One external writing interface owns begin/release/cancel/actions. |
| 21 | 8B remove legacy orchestration | — | — | One orchestration path remains. |
| 22 | 9A exact candidate package | — | — | One no-weight ZIP is ready for D4 testing. |
| 23 | 9B Mac mini D4 | — | — | Real Mac-mini evidence exists. |
| 24 | 9C M1 8 GB identical artifact | — | — | D5 comparison exists for the same ZIP. |
| 25 | 9D0 production-UI acceptance harness | — | — | Exact UI/install/update/remove acceptance is automated. |
| 26 | separately authorized 9D signing/notarization | — | — | A signed candidate may exist; still not admitted. |
| 27 | 9D2 post-staple two-Mac test | — | — | Final changed bits have two-Mac evidence. |
| 28 | 9E D6 and detached owner D7 | — | — | Release readiness and owner admission remain separate decisions. |

Available lanes are intentionally left unused when no independent accepted packet exists. Filling them with dependent work would trade correctness for apparent activity.

## Wave 1 implementation briefs

### Task 1 / Packet 2B2: compile-before-publish dictionary store

**Files:**

- Modify `Sources/FleckCore/PersonalDictionaryStore.swift`
- Modify `Sources/FleckCore/PersonalDictionaryCodec.swift`
- Modify `Tests/FleckCoreTests/PersonalDictionaryStoreTests.swift`
- Modify `Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift`
- Create `Tests/FleckCoreTests/PersonalDictionaryPublicationTests.swift`

**Interface decisions:**

- Preserve every existing v1 store initializer, accessor, and mutation signature.
- Add immutable `PersonalDictionaryPublishedSnapshot` containing one `PersonalDictionarySnapshotV2` and its exact `CompiledPersonalDictionary`.
- Add `publishedSnapshot()` as the only 2C pinning seam; callers never recompile live entries.
- Add optimistic expected-revision mutations while legacy wrappers reload and transact through the same compile-before-publish path.
- Keep `fileURL` as the single authoritative path. Its contents migrate from canonical schema 1 to canonical schema 2; do not create competing v1/v2 authorities.

**Transaction:** lock across store instances; bounded fresh read; expected-revision check; checked increment; canonical encode; exclusive same-directory stage; full file sync; bounded readback; strict decode; exact-byte comparison; compile readback; refresh one bounded non-authoritative recovery copy; one same-filesystem rename as commit; assign the exact decoded/compiled pair without a later throwing operation. Recovery is never loaded automatically.

**Red tests:** strengthen the nine existing store tests and add exactly ten named-suite tests covering compiler failure, pre-rename interruption, corrupt staged readback, stale cross-instance revision, revision overflow, non-authoritative bounded recovery, canonical v1 migration at revision one, concurrent edit winner, byte/compiled identity, and every legacy mutation using compilation.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.personalDictionaryStore[A-Za-z0-9_]*\(\)$'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.PersonalDictionaryPublicationTests/[A-Za-z0-9_]+\(\)$'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.personalDictionaryV2Codec[A-Za-z0-9_]*\(\)$'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\..*$'
```

**Non-goals:** transfer envelope, Settings UI, capture pinning, cloud sync, model runtime, app launch, package creation.

### Task 2 / Packet 6A: immutable model catalog schema

**Files:**

- Modify `Sources/FleckApp/AdmittedModelDescriptor.swift`
- Create `Sources/FleckApp/LocalModelCatalog.swift`
- Modify `Tests/FleckAppTests/AdmittedModelDescriptorTests.swift`
- Create `Tests/FleckAppTests/LocalModelCatalogTests.swift`

**Interface decisions:** preserve legacy `AdmittedModelRole.asr/cleanup` for installer compatibility; add a separate broader catalog role vocabulary. Profiles bind family, role, distribution, runtime ABI, exact immutable artifact manifest, support/resource/license/evidence/admission state, build capability, hardware/OS, claim scope, and speaker/acoustic cohort. Configurations have a human key and canonical digest and may reference only compatible closed profiles.

**Red tests:** mutable revision/URL, unsafe path, missing/extra file, byte overflow, unknown license/evidence, fake system artifacts, incompatible compound roles, cohort mismatch, owner-private evidence in ordinary builds, and digest/order determinism.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalModelCatalogTests/[A-Za-z0-9_]+\(\)$'
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(ordinaryConfiguration|admittedConfiguration|descriptorRole|defaultASRCatalog|cleanupCatalog|mixedRequestedLanguages|unsupportedHardware|spaceAboveDownloadBytes|invalidSignedDescriptorInputs)[A-Za-z0-9_]*\(\)$'
```

**Non-goals:** snapshot data, recommendation, installation behavior, download, selection UI, model admission.

### Task 3 / Packet 1A2: canonical exposure ledger

**Files:**

- Create `Sources/FleckCore/LocalWritingExposureLedger.swift`
- Create `Tests/FleckCoreTests/LocalWritingExposureLedgerTests.swift`

**Interface decisions:** add one canonical, append-only, content-free eligibility ledger bound to corpus identity. Every event binds sequence, prior-head digest, event type, case identity, material lineage, candidate/configuration identity where relevant, and a canonical event digest. Exposure publication is durable before candidate access or output. Lineage invalidation is durable before any post-exposure correction or deletion. Checkpoints bind the exact corpus identity, event count, and current head. Verification rejects missing, truncated, reordered, duplicate, forked, noncanonical, mismatched-corpus, or stale chains and refuses an expected-head mismatch.

**Red tests:** canonical empty checkpoint; durable append before a simulated candidate-open seam; append failure blocks access; crash after append retains exposure; second-instance stale-head conflict preserves the winner; truncated, reordered, duplicate, forked, corrupt, and wrong-corpus chains fail; invalidation must precede mutation; old receipt heads remain ancestors but are ineligible after matching invalidation; unrelated later exposure remains a valid suffix; same-material post-exposure correction remains diagnostic-only; fresh material lineage can regain eligibility; bounds and mode checks; and no private text, audio path, prompt, or transcript can enter an event.

**Verify:**

```bash
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.LocalWritingExposureLedgerTests/[A-Za-z0-9_]+\(\)$'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\.LocalWritingCorpusTests/[A-Za-z0-9_]+\(\)$'
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\..*$'
```

**Non-goals:** corpus-root UI/storage, model execution, corpus templates, scoring, evaluation summaries, signing, upload, or repository fixtures.

## Later-wave packet rules

The full exact owned paths, implementation requirements, red cases, and gates for Packets 2B3 through 9E remain in the master plan. Before each dispatch, the primary copies that packet into a five-part brief and applies these corrections:

- Split the unfinished remainder of master Packet 1A before later work consumes it:
  - **1A2** is the Wave 1 Core exposure-ledger packet frozen above.
  - **1A3** owns `Package.swift` solely to add the one-way `FleckModelEvaluation -> FleckCore` target dependency; `Sources/FleckModelEvaluation/LocalWritingEvidence.swift`; the minimal compatibility mappings in `ModelEvaluation.swift` and `CandidateBenchmarkEvidence.swift`; plus `Tests/FleckModelEvaluationTests/LocalWritingCorpusTests.swift` and `LocalWritingEvidenceTests.swift`. It depends on accepted 1A2, remains content-free, and completes the evidence-level/public-summary contract without product storage or model execution. Its verification must include the exact root lockfile hash and a dependency-direction/source scan so no `FleckCore -> FleckModelEvaluation` edge or duplicate corpus vocabulary appears.
  - Packet 7D follows 1A3 and owns the two app-module corpus-store paths from the master plan. It is never dispatched directly against the present partial 1A state.
- Anchor every runner regex with `^` and `$` and record the positive canonical match list before implementation.
- Freeze any unnamed interface before delegation; later packets may not invent a second store cache, digest type, scheduler, routing request, evidence vocabulary, or packaging identity.
- Split Packet 6E before execution:
  - **6E1** owns configuration-level installer/reference/update/rollback orchestration, including `EnhancedModelManager.swift`, `AdmittedModelInstallation.swift`, and their focused tests.
  - **6E2** owns `AdmittedModelSettingsPresentation.swift`, `SettingsView.swift`, presentation tests, Settings regressions, and accessibility tests.
  - 6E2 consumes 6E1 and cannot delete or stage artifact files itself.
- Correct the premature Packet 6B3 schedule. Full D6/D7, trust-policy, CMS, notary,
  package, transition, and update-predecessor verification is postponed until the
  canonical package/notary/transition receipt schemas it verifies exist. Wave 4
  must not create placeholder schemas, duplicate Core's private strict JSON parser,
  or make the executable target import inaccessible test-only vocabulary. Before
  its later dispatch, the primary must re-freeze its exact public receipt inputs,
  command grammar, byte/NFC bounds, package target dependency, and CMS policy from
  accepted 7G/9A-era authorities. Downstream dependencies on 6B3 are therefore
  provisional and must be re-sequenced before dispatch rather than satisfied by a
  speculative verifier.
- Split Packet 7D before execution:
  - **7D1** owns the same two 7D paths but implements only the actor-backed secure
    workspace authority: a user-selected external container, one exact managed
    corpus child, canonical content-free consent receipt, an empty canonical Core
    manifest, the Core exposure ledger, and a derived checkpoint cache repaired
    from the ledger on open. It enforces exact modes, no-follow/identity-pinned
    bounded I/O, broad/repository/app-bundle root rejection, canonical readback,
    rollback/fork rejection, and caller-owned security-scoped access. Empty Core
    manifests are valid. It records no audio or human case, offers no importer,
    and performs no per-case or whole-corpus deletion.
  - **7D5** follows accepted 7D1 and adds private case/audio mutation, exact export
    and import, invalidation-before-erasure, and a durable whole-corpus retirement
    authority whose old exports and dependent receipts cannot regain eligibility.
    Its retirement/tombstone schema and crash boundaries must be frozen before
    delegation. Packet 7D4 follows accepted 7D5, not merely 7D1.
- Expand Packet 3C1 after accepted Packet 3A. Its truthful production seam needs
  `AppleSpeechCapture.swift`, `AppleSpeechStreamingAdapter.swift`,
  `DictationInterfaces.swift`, `StreamingDictationProcessor.swift`, and the two
  matching adapter/processor tests. The source applies the exact capture-pinned
  recognition strings before audio start and returns `.applied` only after the
  Apple framework accepts them; unsupported capability retains deterministic
  dictionary resolution, while a claimed-capability setup failure rejects before
  audio. Legacy Speech sets exact contextual strings and on-device-only mode;
  macOS 26 Speech uses exact `.general` `AnalysisContext`. No re-sorting,
  re-normalization, truncation, userData copy, or cloud fallback is permitted.
- Insert **6B4 recommendation-ready snapshot closure** before 6C, owning only
  `LocalModelCatalog.swift`, `LocalModelCatalogSnapshot.swift`, and their existing
  catalog tests. The accepted snapshot presently lacks configuration-level joint
  admission/evidence, deterministic Fleck rank, joint peak/sequential/co-residency
  resources, legal/release authorization, staging requirement, exact hardware and
  OS-build cohorts, evidence validity, and a revisioned recommendation/cooldown
  policy. 6B4 adds one immutable snapshot-bound record for those values and
  requires exact Built-in Safe presence in every signed snapshot while keeping
  development candidates nonrecommendable. Until 6B4 ships, 6C may recommend only
  Built-in Safe; it must never infer safety from per-profile resource sums, vendor
  benchmarks, historical archives, family names, or sentinel values.
- Packet 7J remains absent unless qualified Parakeet v2 fails the frozen dictionary-accuracy gate and an exact auxiliary artifact/license/runtime/files/tests amendment is accepted.
- Packet 7K remains absent unless live partials become a measured hard requirement and an exact Unified/EOU profile amendment is accepted.
- Packet 7L2 remains absent unless Gemma 1B misses a frozen resource or latency objective and an exact 270M artifact/runtime/files/tests amendment is accepted.
- Evidence packets that append to the same private exposure ledger run serially even when source ownership is disjoint.
- Packets 8A through 9E are identity-linked and serial.

## Curated model policy

The initial catalog contains only truthful profiles:

1. **Built-in Safe:** Apple Speech plus deterministic cleanup and deterministic routing/Inbox.
2. **Enhanced English candidate:** exact Parakeet TDT 0.6B v2 plus deterministic cleanup/routing.
3. **Enhanced writing candidate:** the same Parakeet profile with separately qualified Gemma 3 1B cleanup and/or routing roles. One artifact may back two role profiles, but evidence and admission remain separate.
4. **Lightweight candidate:** Parakeet TDT-CTC 110M enters only through 7H/7I/7I2.
5. **System cohorts:** Apple Foundation cleanup/routing appear only when the exact OS/hardware capability exists and that tuple is separately represented.
6. **Historical archive only:** Whisper, Nemotron, Qwen, and any unverifiable historical result never become installable through the archive.

The catalog supports a future high-memory tier, but no larger model is added merely to fill it. Better hardware first receives longer warm retention. A larger model is proposed only after the admitted default fails a frozen accuracy gate and the larger candidate demonstrates enough improvement to justify latency, RAM, storage, license, and packaging cost.

## Installation, repair, update, and removal contract

The normal UI exposes one action and simple stages: Downloading, Verifying, Installing, Starting, Calibrating, Ready. Details disclose exact identity/license/evidence without crowding the normal surface.

- Download uses real byte counts and resumable partials.
- Verification binds revision, artifact manifest, checksums, runtime ABI, and license record.
- Installation stages beside the final tree and switches atomically.
- Repair reuses verified files and reacquires only missing/corrupt bytes.
- Update exists only for one exact verified predecessor-to-successor transition, stages side by side, preserves rollback capacity, and switches the complete configuration/reference graph atomically.
- Removal previews every role/reference, drains active leases, and deletes only the selected artifact tree after no active, selected, or rollback configuration references it.
- Interrupted stages are bounded and recoverable; indefinite generic Loading is forbidden.
- Ordinary Fleck and every ZIP contain no model weights.

## Adaptive RAM and CPU lifecycle contract

One scheduler owns the state machine:

```text
unloaded -> loading -> warm -> idle -> hibernating -> unloaded
```

Inputs are physical RAM, current reclaimable memory, memory pressure, active processor count, thermal state, Low Power Mode, sleep/logout, recent capture frequency, exact startup cost, and active leases. Identity never changes mid-capture.

- On 8 GB, ASR and Gemma do not coexist; ASR releases before cleanup/routing.
- Under pressure, thermal escalation, Low Power Mode, sleep, removal, or failure, leases drain and residency shortens or unloads immediately.
- On roomier Macs with low pressure, the exact same admitted configuration may stay warm longer to lower repeat latency.
- Cleanup and routing may share one exact Gemma artifact lease only when both roles are authorized by the selected configuration.
- Once enhanced audio capture starts, enhanced failure publishes nothing and may choose Apple only for the next capture. Cleanup/routing can still fail to faithful baseline/Inbox inside the same immutable transaction.

## User-visible milestones

1. **Reliable dictionary:** edits, conflicts, transfer, and suggestions are safe; every dictation uses one pinned version.
2. **Better capture:** speech from physical key-down is retained, short taps remain silent, first and final words improve, and cancellation cannot insert late text.
3. **Useful faithful cleanup:** Gemma more often removes fillers/stutters while the validator retains the entire faithful baseline on one unsafe change.
4. **Universal sorting:** aliases and full-note context corroborate concepts; only a unique strong result auto-files; ambiguity uses durable Inbox plus chooser.
5. **Clean model management:** one recommendation, optional curated Advanced choices, real progress, repair/update/removal, and no model-file clutter.
6. **Adaptive performance:** 8 GB Macs unload aggressively; roomier Macs retain the same qualified models longer when safe.
7. **Quality tooling:** explicit private recording/replay/oracle workflows create evidence without upload or hidden collection.
8. **Testable artifact:** one exact no-weight ZIP runs the complete transaction on the Mac mini and M1 MacBook before any release claim.

## Completion and stop conditions

Automated work continues through source, tests, local commits, reviews, integration, unsigned development packaging, and evidence tooling. It stops only for destructive/security-sensitive actions, unavailable authority, a genuinely broken spec, or these explicit external gates:

- new model-weight acquisition or license acceptance;
- live microphone speech that requires the owner to speak;
- AirDrop/physical second-Mac interaction;
- Apple Developer signing/notarization credentials and legal review;
- push/PR/merge/GitHub changes;
- final detached owner admission.

At those points the program reports the exact artifact, command, test script, required manual action, and evidence still missing. It never substitutes synthetic proof for the external gate.
