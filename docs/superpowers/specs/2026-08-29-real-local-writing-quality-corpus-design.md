# Real Local Writing Quality Corpus Design

**Status:** Proposed
**Scope:** Private, English, Apple Silicon, operator-controlled quality evidence

## 1. Purpose

Fleck needs a real corpus that can answer product questions the current synthetic fixtures cannot:

- Does the app hear the first and final words from a real microphone?
- Does the dictionary improve the user's actual names and terminology?
- Does cleanup remove speech artifacts without changing meaning?
- Does Smart Capture file the result correctly against a real controlled workspace?
- Does the exact packaged app stay responsive, private, cancellable, and within memory limits?

The corpus is a local product-quality instrument, not a telemetry system and not a dataset bundled with Fleck.

## 2. Storage and consent boundary

Ordinary Fleck dictation continues to discard audio. Corpus retention exists only inside an explicit **Quality Recording Mode** available in development/Advanced builds.

The user chooses a local corpus root. Fleck requires:

- directory permissions `0700` or stricter;
- a path outside the repository and app bundle;
- an explicit consent receipt for retained recordings;
- per-case delete and whole-corpus delete;
- local export of a manifest/evidence packet only on explicit action;
- no background upload, sync, analytics, or cloud fallback;
- no transcript, note body, or audio in ordinary logs.

Per-case deletion of exposed material first appends `materialLineageInvalidated`, advances the checkpoint, then removes private audio/text while retaining the content-free lineage history, so deletion cannot make exposed material appear blind again. Whole-corpus deletion removes the corpus and ledger only as one explicit destructive action, invalidates every dependent run/admission receipt, and requires a new corpus ID plus fresh cases before testing resumes.

The initial design does not use iCloud for corpus data. Two-device testing transfers an explicitly exported, encrypted or locally controlled archive outside Fleck's ordinary runtime.

## 3. Data model

The product and evaluation tool share strict decoders for a versioned manifest. The corpus itself stays outside Git.

```swift
struct LocalWritingCorpusManifestEnvelope: Codable, Sendable {
  let schemaVersion: Int
  let corpusID: String
  let revisionSHA256: String
  let payload: LocalWritingCorpusPayload
}

struct LocalWritingCorpusPayload: Codable, Sendable {
  let language: String                 // exactly en-US in v1
  let claimScope: LocalCorpusClaimScope
  let consentReceiptSHA256: String
  let createdAtUnixMilliseconds: Int64
  let controlledWorkspaces: [LocalWritingControlledWorkspaceManifestEnvelope]
  let cases: [LocalWritingCorpusCase]
}

struct LocalWritingCorpusCase: Codable, Sendable {
  let id: String
  let materialLineageID: String
  let sourceClass: LocalCorpusSourceClass
  let humanSpeechEligible: Bool
  let scoringEligibility: LocalCorpusScoringEligibility
  let audio: LocalAudioReceipt?
  let referenceTranscript: String
  let tags: [LocalCorpusTag]           // canonical sorted unique array
  let protectedExpectations: [LocalWritingProtectedExpectation]
  let cleanupOracle: LocalWritingCleanupOracle
  let routingOracle: LocalWritingRoutingOracle?
  let executionVariants: [LocalWritingExecutionVariant]
}

enum LocalCorpusScoringEligibility: String, Codable, Sendable {
  case admissionEligible
  case diagnosticOnlyPostExposure
}

struct LocalWritingCorpusLedgerEvent: Codable, Sendable {
  let sequence: UInt64
  let previousEventSHA256: String?
  let payload: LocalWritingCorpusLedgerPayload
}

enum LocalWritingCorpusLedgerPayload: Codable, Sendable {
  case candidateExposure(LocalWritingCandidateExposure)
  case materialLineageInvalidated(LocalWritingMaterialLineageInvalidation)
}

struct LocalWritingCandidateExposure: Codable, Sendable {
  let corpusRevisionSHA256: String
  let caseID: String
  let materialLineageID: String
  let audioSHA256: String?
  let configurationIdentitySHA256: String
  let roleProfileIdentitySHA256: String
  let executionVariant: LocalWritingExecutionVariant
  let scheduledAtUnixMilliseconds: Int64
}

struct LocalWritingMaterialLineageInvalidation: Codable, Sendable {
  let invalidatedCorpusRevisionSHA256: String
  let invalidatedCaseID: String
  let materialLineageID: String
  let audioSHA256: String?
  let reasonCode: LocalWritingInvalidationReason
  let invalidatedAtUnixMilliseconds: Int64
}

enum LocalWritingInvalidationReason: String, Codable, Sendable {
  case oracleCorrectedAfterExposure
  case exposedCaseDeleted
  case sourceMaterialIntegrityFailed
}

struct LocalWritingCorpusLedgerCheckpoint: Codable, Sendable {
  let schemaVersion: Int
  let corpusID: String
  let sequence: UInt64
  let headEventSHA256: String
  let ledgerBytesSHA256: String
  let createdAtUnixMilliseconds: Int64
}

struct LocalWritingCorpusAdmissionSeal: Codable, Sendable {
  let schemaVersion: Int
  let corpusID: String
  let baseCheckpointSHA256: String
  let baseHeadEventSHA256: String
  let allowedSuffix: LocalWritingCorpusSealSuffixPolicy // candidateExposureOnly
  let evaluationSignerFingerprintSHA256: String
  let createdAtUnixMilliseconds: Int64
}

enum LocalWritingCorpusSealSuffixPolicy: String, Codable, Sendable {
  case candidateExposureOnly
}
```

The private corpus root also contains one canonical append-only eligibility ledger and atomically advanced latest-head checkpoint. Ledger payloads use an explicit canonical tag and exact-key schema; each event digest covers its payload, sequence, and prior event digest. Before any runner, adapter, packaged injected path, or live Quality session gives case material to a candidate—or reveals any candidate output—it must durably append `candidateExposure` and advance the checkpoint. Failure to append blocks execution. A crash or rejected output still counts as exposure.

If a frozen oracle is corrected after exposure or an exposed case is deleted, the store must append `materialLineageInvalidated` and advance the checkpoint **before** publishing the correction/deletion. The invalidation targets the prior corpus revision, case, lineage, and audio digest; it retroactively makes every run, score, comparison, promotion, or admission consuming that lineage unverifiable against the current checkpoint. A new diagnostic revision does not itself carry the authority to invalidate old evidence—the chained event does.

Verifiers reject truncated, forked, reordered, duplicate, noncanonical, or corpus/configuration/profile-mismatched ledgers and checkpoints. Every score/D5/D6/D7 verification reopens the current authoritative ledger/checkpoint, proves the receipt-bound earlier head is an ancestor, and rejects any intervening invalidation for a consumed lineage. Thus later exposure events may extend the ledger safely, while a correction cannot leave an old self-consistent score promotable.

After the MacBook D5 ledger extension has fast-forwarded the Mac mini's canonical corpus ledger, the evaluator creates a detached CMS-signed `LocalWritingCorpusAdmissionSeal` using an explicitly reviewed local evaluation identity. The seal's suffix policy permits only new `candidateExposure` events needed for the final signed-app run. Any invalidation, oracle/case/material mutation, fork, or whole-corpus deletion breaks the seal before the mutation completes and blocks D5/D6/D7 reuse. Privacy deletion remains available; it simply invalidates the evidence program. Score/promotion/admission tools require the live canonical Mac-mini ledger, latest checkpoint, seal, and externally reviewed signer fingerprint—never only a copied historical receipt.

Cross-device transfer is fast-forward-only. The Mac mini exports a canonical content-free, CMS-signed ledger extension from a named parent checkpoint; the M1 verifies the expected signer and exact parent before import, appends its exposure events, and returns a signed extension. The Mac mini accepts it only when its local head is still the named parent, then becomes the single authoritative ledger again. D5 sealing happens only after that return. The same sequential extension handshake surrounds the final 9D2 MacBook run. A point-in-time remote copy cannot call itself latest or authorize promotion.

### 3.1 Audio receipt

Every human case records:

- path relative to the chosen corpus root;
- SHA-256 and byte count;
- duration, sample rate, channels, sample format, and container;
- pseudonymous speaker ID;
- capture date;
- input-device class and a privacy-preserving device identity hash;
- read/spontaneous classification;
- consent receipt hash.

Validation rejects absolute paths, traversal, symlinks outside the corpus root, duplicate IDs, duplicate hashes with conflicting metadata, unsupported formats, and hash/byte mismatches. `revisionSHA256` is computed over RFC 8785 canonical JSON bytes of `payload` only, excluding the envelope digest itself. Strings are NFC; UUIDs are lowercase canonical strings; timestamps are signed 64-bit Unix milliseconds; unknown/duplicate keys, floats, `null` optionals, noncanonical bytes, and out-of-range integers are rejected. Cases, tags, expectations, oracles, and variants have declared stable sort orders; unordered `Set` encoding is never used as evidence identity.

### 3.2 Module boundary and existing evidence compatibility

The shared manifest/oracle contracts live in `FleckCore` so both `FleckApp` and `FleckModelEvaluation` can use them without making the app depend on the evaluation target. `FleckModelEvaluation` gains a one-way dependency on `FleckCore` and extends the existing `ModelEvaluationScorer` and `CandidateBenchmarkEvidence` concepts through explicit adapters. It does not create a competing WER/protected-value scorer or a second candidate-admission vocabulary.

The separate `Tools/LocalDictationCandidateAdapters` package remains an execution adapter. It emits its existing strict JSONL protocol plus versioned raw stage/resource receipts. The root `fleck-model-eval` executable validates and maps those receipts into canonical Fleck evidence. That JSONL boundary is versioned and tested in both packages; the tool package does not copy the canonical evidence implementation.

### 3.3 Human and synthetic separation

Allowed source classes:

- `humanRead`
- `humanSpontaneous`
- `humanSilence`
- `publicHuman`
- `synthetic`
- `faultInjection`

Only the first four can set `humanSpeechEligible`. Synthetic and fault-injection cases cannot enter WER, first-word, microphone, accent, or human-speech aggregates. The evidence generator fails closed if an aggregate mixes them.

### 3.4 Private per-case result

The runner persists the complete text-stage chain in the private evidence root so cleanup safety and fallback behavior remain observable:

```swift
struct LocalWritingCaseResult: Codable, Sendable {
  let caseID: String
  let captureID: UUID
  let rawASR: String
  let dictionaryBaseline: String
  let faithfulBaseline: String
  let generatedCleanupCandidate: String?
  let finalPublishedText: String?
  let cleanupDecision: CleanupDecisionCode
  let cleanupFailure: CleanupFailureCode?
  let routingResult: LocalWritingRoutingResult
  let stageReceipt: LocalWritingStageReceipt
}
```

`faithfulBaseline` is the latest whole transcript accepted by deterministic faithful validation before any optional generated candidate is selected. It may equal the dictionary baseline, but it is never inferred from the final text or collapsed into a generic fallback flag. A rejected, late, malformed, or cancelled generated candidate must leave `finalPublishedText` equal to that whole faithful baseline unless the overall capture is cancelled. Public summaries contain only hashes, aggregate metrics, and stable outcome codes—not these strings.

### 3.5 Controlled routing workspace

Routing evidence never runs against the user's evolving everyday notes. A strict manifest defines one isolated private fixture workspace:

```swift
struct LocalWritingControlledWorkspaceManifestEnvelope: Codable, Sendable {
  let schemaVersion: Int
  let workspaceID: String
  let revisionSHA256: String
  let payload: LocalWritingControlledWorkspacePayload
}

struct LocalWritingControlledWorkspacePayload: Codable, Sendable {
  let cohort: LocalWritingWorkspaceCohort
  let inboxFixtureKey: String
  let notes: [LocalWritingControlledNote] // canonical fixture-key order
  let mutationSchedule: [LocalWritingWorkspaceMutation]
}

struct LocalWritingControlledNote: Codable, Sendable {
  let fixtureKey: String
  let noteID: UUID
  let title: String
  let body: String
}
```

Its digest is computed over the same strict RFC 8785 canonical payload contract as the corpus envelope; it never includes its own digest. Fixture keys are the only oracle-facing identifiers; titles are not identity. The Quality Lab provisions the manifest into a separate `LocalStore` rooted under the selected private corpus directory, verifies the resulting workspace digest, resets it before every routing run, and tears it down only through receipt-scoped deletion. It refuses the live Fleck store, repository, app bundle, symlinks, traversal, unknown notes, duplicate/case-colliding fixture keys, or a missing unique Inbox. A route result is authoritative only when the pre-run and post-run workspace digests and expected receipt mutations reconcile.

Three frozen workspace cohorts keep correctness and scaling claims separate:

| Cohort | Frozen minimum | Claim allowed |
|---|---:|---|
| `ownerLiveFixture` | 12 locally authored safe fixture notes, one Inbox, duplicate-title/Untitled/no-match cases | E3 hands-on behavior only; no cache-scale claim |
| `representative60` | 60 notes across at least six topics, at least 10 bodies of 32 KiB or more with decisive evidence in the middle, duplicate/case-close titles, Untitled, stale/deleted/revised fixtures, and a canonical 20-mutation schedule | ordinary local-workspace precision, chooser recall, and cached retrieval p95 <= 100 ms |
| `stress500` | 500 notes across body-size strata, at least 50 bodies of 32 KiB or more, multiple close-topic clusters, and a canonical 50-mutation churn schedule | cache invalidation, bounded scanning, memory, and cached retrieval p95 <= 250 ms; never substitutes for human E3 |

The complete note bodies and manifests remain in the private corpus root. Each evidence receipt binds the cohort key and manifest digest. A general sorting claim requires both `representative60` and `stress500`; a run against the small live fixture cannot inherit those claims. The provisioning tool must make every cohort deterministically reproducible from its already-frozen private manifest—never from a user's live notes.

### 3.6 Immutable case-template and oracle authoring contract

Quality Lab ships a versioned, nonprivate library of at least 120 **case intents**, not recordings. Each template fixes its purpose, required taxonomy tags, allowed execution variants, workspace cohort/key constraints, and the kind of cleanup/routing oracle the operator must confirm. It may provide a read prompt or a spontaneous-speaking intent. It does not predetermine private names, transcript text, or protected values.

Before recording becomes an evaluable case, the operator must:

1. choose a template or explicitly create a draft from a content-free feedback category;
2. record fresh consented audio;
3. confirm the verbatim reference transcript;
4. confirm every exact protected expectation found in that reference;
5. choose only template-permitted cleanup operations and routing fixture keys; and
6. freeze the case/template/oracle revision before any candidate result is visible.

Validation rejects protected values absent from the reference, routing keys absent from the named controlled workspace, contradictory cleanup operations, missing template requirements, in-place post-exposure oracle edits, or a feedback draft that was never explicitly confirmed. Before first exposure, an edit creates a new frozen corpus revision and invalidates prior plans. After any candidate exposure, the old revision remains immutable; if its oracle is found wrong, the store first appends the canonical lineage-invalidation event and advances the latest checkpoint, making every prior score that consumed it fail current verification. A corrected revision reusing that `materialLineageID` or audio is permanently `diagnosticOnlyPostExposure` and cannot enter an admission aggregate for any candidate. Restoring admission eligibility requires a new case ID and material-lineage ID, fresh consented audio, a freshly confirmed reference/protected set/oracle, and a freeze completed while candidate outputs are hidden. This makes the 120-case floor buildable in the app without letting the model grade itself or letting ordinary dictation silently become training data.

## 4. Initial corpus floor

The first admission corpus contains at least 120 distinct `admissionEligible` human utterances from the primary operator. Diagnostic-only post-exposure revisions do not count toward any floor:

| Group | Minimum | Purpose |
|---|---:|---|
| Ordinary hold-to-talk | 40 | short, medium, long; calm and fast speech; immediate and delayed start |
| Disfluency and correction | 20 | fillers, repetitions, false starts, sentence restarts, explicit corrections, lists |
| Protected meaning | 20 | names, numbers, amounts, dates, URLs, paths, commands, negation, modality, commitments, recipients |
| Personal dictionary | 20 | preferred forms, aliases, multiword terms, acronyms, identifiers, conflicts, disabled entries |
| Semantic routing | 20 | unique match, close/ambiguous, no match, duplicate title, deleted/stale note, malformed judgment |

Tags overlap, but the manifest must contain at least 40 read prompts and 40 spontaneous utterances. One operator's corpus supports a personal-quality claim only; it cannot establish general accent or population performance.

The 120-case floor is a starting floor, not permission to score an empty objective. The template library includes at least 30 cleanup intents expected to remain after the deterministic faithful control and at least 30 uniquely routable intents expected to remain after deterministic title/dictionary routing. After the frozen control run, the admission manifest must contain at least 20 **observed** residual cleanup cases and 20 **observed** residual uniquely routable cases. If either denominator is short, the operator records additional predeclared template cases and creates a new corpus revision before any model result is inspected. Cases may overlap groups when their frozen tags/oracles genuinely satisfy both; the scorer never relabels them after output.

## 5. Taxonomy

### 5.1 Capture and acoustic tags

- immediate speech after key-down;
- delayed speech;
- quiet room;
- fan/keyboard/ambient noise;
- low/normal/high input level;
- built-in microphone;
- USB/external microphone;
- Bluetooth/AirPods;
- input device change before capture;
- input device loss during capture;
- very short utterance;
- 30-, 60-, and 120-second utterance;
- silence and non-speech;
- final word immediately before release;
- interruption, sleep/wake, Low Power Mode, thermal/memory pressure.

### 5.2 Language and meaning tags

- proper name;
- technical product name;
- acronym/initialism;
- chemistry/scientific term;
- code identifier;
- file path;
- URL/email;
- command;
- currency/price/amount;
- date/time;
- unit/measurement;
- recipient/destination;
- commitment;
- negation;
- possibility/requirement/modality;
- quoted text;
- list;
- punctuation-sensitive utterance.

### 5.3 Cleanup tags

- isolated filler;
- repeated filler;
- immediate duplicate;
- stutter;
- false start;
- explicit correction;
- conversational scaffolding;
- already clean/no-op;
- ambiguous correction;
- prohibited summary;
- prompt-injection-shaped speech;
- stray-token regression;
- long mutable tail;
- deadline and cancellation boundary.

### 5.4 Routing tags

- exact unique title;
- unique body-context match;
- unique personal-term match;
- ambiguous close candidates;
- no eligible match;
- duplicate titles;
- Untitled note;
- deleted candidate;
- changed note revision;
- incomplete index scan;
- stale dictionary revision;
- model tie/malformed/unknown key;
- chooser destination deleted before selection;
- keep in Inbox;
- receipt-bound move and undo.

## 6. Oracles

### 6.1 Transcript oracle

Each reference transcript is verbatim, including intended lexical content but excluding acoustic non-speech. Alternative acceptable spellings must be explicit and bounded; the scorer cannot choose a convenient reference after seeing a result.

### 6.2 Protected expectations

Every protected case identifies exact expected values and type. Case validation requires every expectation to occur in the reference and forbids overlapping contradictory expectations.

### 6.3 Cleanup oracle

```swift
enum CleanupOracle: Codable {
  case exact(String)
  case allowedOperations([CleanupEditOperation]) // canonical sorted unique array
  case unchangedRequired
  case rejectGeneratedCandidate
}
```

For flexible cases, acceptance is based on allowed operations plus protected and lexical validation—not subjective string similarity.

### 6.4 Routing oracle

```swift
enum RoutingOracle: Codable {
  case unique(noteFixtureKey: String)
  case ambiguous(acceptableKeys: [String]) // canonical sorted unique array
  case inbox
}
```

The custom evidence encoder writes operation and acceptable-key collections as sorted unique arrays and the strict decoder rejects duplicates or noncanonical order. No synthesized `Set` conformance participates in a digest. A cross-process fixture must produce identical canonical bytes and `revisionSHA256` in the app, root evaluator, and adapter bridge.

The corpus references opaque fixture keys, not live user note UUIDs. A controlled workspace manifest maps keys to exact note/title/body/revision hashes for the run.

## 7. Execution variants

Each case declares applicable variants:

- cold app/cold models;
- warm ASR/cold cleanup;
- warm cleanup after ASR lease handoff;
- healthy, constrained, and critical memory profiles;
- Low Power Mode;
- file replay through the engine/evaluator;
- packaged injected-audio path;
- packaged live microphone;
- cancellation at a named stage.

Cold and warm order is randomized within a declared seed. The run receipt records actual lifecycle transitions so a retained model cannot be mislabeled cold.

## 8. Metrics and frozen targets

Targets are versioned and signed into the run configuration before outputs are inspected.

| Metric | Definition | Proposed gate |
|---|---|---:|
| Raw WER | raw ASR vs verbatim reference | <= 15% aggregate |
| Post-dictionary WER | dictionary baseline vs reference | <= 10%; no stratum >2 points worse |
| First-word recall | exact first lexical item on immediate-speech cases | >= 99.5% |
| Final-word recall | exact final lexical item on release-edge cases | 100% |
| Dictionary term accuracy | exact preferred form | >= 98%; priority terms 100% |
| Protected cleanup safety | accepted output changes protected meaning | 0 |
| Ambiguous cleanup safety | ambiguous correction accepted | 0 |
| End-to-end cleanup utility | all cleanup-eligible cases whose final text improves over dictionary baseline within oracle | >= 85% |
| Generated-cleanup attributable utility | residual cases where the deterministic faithful baseline still has an oracle-allowed improvement and the candidate alone supplies an accepted improvement | >= 60% of at least 20 residual cases and >= 10 percentage-point end-to-end gain vs deterministic control |
| Auto-route precision | correct automatic / all automatic | 100% observed |
| Unique-route coverage | correct automatic / uniquely routable | >= 75% |
| Model-routing attributable coverage | deterministic-control abstentions correctly resolved only after the candidate judgment | >= 50% of at least 20 residual uniquely routable cases and >= 10 percentage-point overall gain |
| Ambiguity safety | ambiguous/no-match silently auto-filed | 0 |
| Chooser recall | expected destination offered | 100% |
| Persistence integrity | loss, duplicate, wrong receipt | 0 |
| Cancel integrity | any late text/history/chooser/move | 0 |
| Warm focused latency | release to durable insertion | p95 <= 3 s target; <= 4 s ceiling |
| Smart-save latency | release to durable save/chooser | p95 <= 7 s |
| Cached retrieval | unchanged-cache query | p95 <= 100 ms |
| Stress cached retrieval | unchanged-cache query on `stress500` | p95 <= 250 ms |
| Cancellation drain | request to drained terminal | p95 <= 750 ms |
| M1 resource ceiling | combined peak physical footprint | <= 2 GiB |
| Idle recovery | 60 s post-capture vs baseline | within 200 MiB |
| Privacy | unexpected network/audio persistence/transcript log | all 0 |

Candidate gates are objective-specific and frozen before results:

- a **quality challenger** must improve post-dictionary WER by at least 20% relative without regressing safety, latency, resource, cancellation, or privacy;
- a **lightweight challenger** may qualify with accuracy noninferiority (no more than 1 absolute WER point worse, no protected/priority-term regression) plus at least 30% improvement in its declared peak-memory or cold-load objective;
- a **streaming challenger** must meet its frozen partial/latency objective with accuracy noninferiority and no lifecycle/safety regression;
- a **cleanup challenger** must retain zero semantic violations and meet both its candidate-attributable incremental utility gate and declared latency/resource objective. Rejection, timeout, no-op, and deterministic-only success contribute zero candidate-attributable utility;
- a **routing challenger** must retain 100% observed automatic precision and add candidate-attributable residual coverage. Inbox/chooser fallbacks and deterministic-only successes contribute zero model-attributable coverage.

“Different” is not enough to justify another model, but an efficiency profile is not required to beat a quality profile by 20% WER.

## 9. Evidence levels

| Level | Evidence | Claim allowed |
|---|---|---|
| E0 | deterministic and synthetic tests | contract behavior only |
| E1 | private human-audio replay | model quality on recorded operator corpus |
| E2 | exact packaged app with injected audio | package/integration path, not microphone behavior |
| E3 | packaged live-human real microphone on one Mac | one-device operator behavior |
| E4 | identical artifact on Mac mini and M1 8 GB MacBook | two-device candidate admission evidence |
| E5 | signed/notarized intended distribution artifact | release-admission input |

No report may collapse these levels into a single “tested” boolean. The initial one-operator E4 result supports an `ownerPrivateBeta` claim only. A general-English release claim requires a separately consented multi-speaker/accent/acoustic cohort—provisionally at least 12 speakers and 600 human utterances with subgroup reporting—plus the same zero-event safety gates. Those thresholds must be frozen before that cohort is run.

## 10. Run provenance

Every run envelope contains:

- source commit, branch, clean/dirty status;
- `Package.resolved` hash;
- archive, bundle executable, and running executable SHA-256;
- build command and feature flags;
- Xcode, Swift, macOS versions;
- hardware model, chip, RAM, power/thermal state, available storage;
- input-device class/hash;
- corpus ID/revision and every consumed audio hash;
- candidate-exposure ledger head plus the exact pre-execution event digest for every consumed case/configuration/profile;
- controlled-workspace fixture digest;
- dictionary schema/revision/digest and compiler policy revision;
- catalog/profile and exact ASR/cleanup/runtime/manifest identity;
- prompt, parser, validator, routing-index, and routing-policy revisions;
- per-stage timing, lifecycle, resource, cancellation, privacy, and persistence receipts;
- per-case raw ASR, dictionary baseline, validator-accepted faithful baseline, optional generated candidate, final published text, cleanup decision/failure code, route result, and oracle result;
- operator/date and threshold-revision decision.

Private text may exist inside the private per-case evidence file. Public/checked-in summaries contain aggregate metrics, case IDs, hashes, and stable failure codes only.

## 11. Quality Lab UI

The UI is intentionally separated from normal Settings:

- a clear “Quality Recording Mode” privacy explanation;
- corpus root selection and permission status;
- versioned template/case ID, read prompt or spontaneous intent, and required tags;
- record, stop, replay locally, accept, retry, delete;
- edit/verbatim-reference confirmation followed by a bounded protected-value, cleanup-oracle, routing-fixture, and execution-variant confirmation step;
- an explicit pre-run freeze state; before exposure, editing creates a new frozen revision, while any post-exposure correction is visibly diagnostic-only until the user records and freezes fresh blinded material;
- local corpus progress by taxonomy, not a vanity score;
- export one frozen evaluator run plan and import/display its separately verified aggregate receipt; model execution/scoring remains an explicit external developer operation;
- review a content-free routing/cleanup correction alert and, only on explicit action, create an unconfirmed template draft and record a fresh consented controlled case for it;
- export evidence or delete corpus;
- no automatic upload or model admission button.

The normal user never sees this surface unless they enable the development/Advanced quality mode.

## 12. Two-Mac protocol

1. Build and package once on the Mac mini.
2. Record archive, bundle, and executable hashes.
3. Export the exact corpus manifest/audio archive and dictionary snapshot explicitly.
4. Export the Mac mini's authenticated eligibility-ledger extension/checkpoint from the exact parent head, then transfer it with the app and evidence inputs to the M1 8 GB MacBook.
5. Verify archive, bundle, running executable, corpus, dictionary, ledger parent/head, and evaluation signer before testing; import only as an exact fast-forward.
6. Replay the same corpus for comparable E1/E2 evidence and record a smaller fresh live-microphone E3 subset.
7. Export the M1's signed exposure-only ledger extension and content-free results; on the Mac mini, require its local head still equals the extension parent and fast-forward atomically.
8. Run pressure, cold/warm, sleep/wake, cancellation, offline, and removal checks, then create the D5 admission seal on the canonical Mac-mini head.
9. Combine results only when artifact/policy identities match and the current canonical ledger/seal contains no relevant invalidation. The final signed-app two-Mac run repeats the same sequential extension handshake.

This protocol proves neither automatic sync nor broad population quality.

## 13. Failure handling

- Hash mismatch invalidates the case/run; it is never auto-repaired silently.
- Missing consent invalidates retained human audio.
- Mixed synthetic/human aggregation fails report generation.
- A private root inside Git or the app bundle blocks recording.
- A run interrupted mid-case writes no authoritative case result.
- A missing/forked exposure event blocks execution or scoring; a post-exposure oracle correction on reused material is diagnostic-only and never restores an admission score.
- Threshold changes create a new threshold revision; old results are not rewritten.
- Any protected violation, wrong auto-route, late insertion, privacy violation, or wrong artifact blocks admission regardless of averages.
