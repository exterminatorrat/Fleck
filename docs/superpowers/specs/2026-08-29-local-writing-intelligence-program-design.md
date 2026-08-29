# Fleck Local Writing Intelligence Program Design

**Status:** Proposed for owner approval; planning only
**Date:** 2026-08-29
**Planning base:** `0c63559083a00dfab5b92b4edea01fbdb0fda14e`
**Product scope for this program:** Apple Silicon, English-first, fully local after an explicit model install

## 1. Decision summary

Fleck should treat dictation, personal terminology, faithful cleanup, and semantic filing as one local writing transaction. It should not expose four loosely related AI features.

The program will extend the existing implementation around five durable Modules:

1. **Local Writing Pipeline** — owns a capture from key-down through durable insertion or save.
2. **Personal Dictionary Compiler** — publishes one immutable dictionary revision that every stage uses for that capture.
3. **Local Writing Quality Lab** — records opt-in private corpus cases and produces reproducible evidence without changing ordinary dictation privacy.
4. **Curated Model Catalog** — contains immutable, no-weight metadata and chooses one measured configuration for the current Mac.
5. **Admission Gate** — separates source existence, integration, real-model evidence, packaged-app evidence, and release approval.

The product remains safe when every optional model is absent or fails:

- Apple Speech remains the dictation fallback.
- Deterministic dictionary resolution remains available.
- Apple Foundation Models are used for cleanup only where available and admitted.
- Gemma is the open-weight cleanup candidate for Macs without Apple Intelligence.
- Every generated cleanup passes the faithful validator or is discarded.
- Routing uncertainty saves to Inbox and asks the user only when a bounded choice is useful.
- No model weights are included in an ordinary Fleck bundle.
- No transcription, transcript, note body, or audio is uploaded.

## 2. Current truth and why this is an extension

The current branch already implements the core pieces:

- a streaming coordinator and stable-prefix/mutable-tail transcript processor;
- Apple Speech and a debug-gated Parakeet TDT 0.6B v2 adapter;
- personal dictionary storage, alias resolution, protected preferred forms, and Settings CRUD;
- deterministic cleanup parsing, protected-span extraction, a fail-closed validator, deadlines, and cancellation;
- Apple Foundation Models and debug-gated Gemma 3 1B 4-bit cleanup generation;
- full-note local semantic indexing, deterministic corroboration, Gemma/Foundation route judgment, Inbox fallback, and a receipt-bound ambiguity chooser;
- resumable, checksum-verified, atomic model installation, repair, update, and scoped removal;
- adaptive Parakeet retention and pressure monitoring;
- benchmark evidence types that distinguish synthetic and human sources.

The important gaps are wiring and proof:

- dictionary context is modeled but is not passed into the active ASR adapters;
- a capture does not pin one dictionary revision across ASR, cleanup, and routing;
- Parakeet begins audio capture only after its model is ready, which can lose the first word;
- stage measurements exist but production results return empty measurements;
- the general runtime scheduler is not composed into the live product;
- cleanup and routing feedback are not yet converted into safe, explicit corpus/dictionary improvements;
- the repository corpus does not constitute a private, real-microphone product corpus;
- no candidate has passed a packaged, two-Mac release gate;
- some architecture/status documents still describe title-only routing even though current code uses a bounded full-note local index.

## 3. Product experience

### 3.1 Normal use

The primary experience stays simple:

1. The user holds the Fleck dictation shortcut.
2. Fleck starts capturing immediately and displays listening state.
3. On release, Fleck recognizes locally, applies the user's terminology, removes safe speech disfluencies, validates meaning, and inserts the result.
4. In Smart Capture, Fleck saves to the uniquely supported note; if evidence is close, it saves to Inbox first and offers a small destination chooser.
5. After ASR and dictionary resolution have produced a faithful baseline, a failure in optional cleanup or routing uses that baseline or Inbox rather than failing the whole capture. An enhanced-ASR failure before any baseline exists publishes no text and selects Apple Speech for the next capture.

The ordinary UI does not ask the user to select engines, quantizations, runtimes, or residency policies. It says which two local capabilities are active—Dictation and Cleanup—and offers one recommendation for the Mac.

### 3.2 Corrections and learning

Fleck learns only from explicit user actions:

- **Correct dictation…** can replace text through the capture's exact insertion receipt while that receipt remains valid.
- A single safe terminology correction can become a proposed dictionary entry, such as “Always write `FleckApp` for ‘fleck app’?”
- The user must approve, edit, or dismiss the proposal.
- A routing correction becomes quality evidence; it does not silently create a permanent routing rule.
- Arbitrary note edits are never mined as implicit supervision.

### 3.3 Advanced model management

Settings shows:

- **Dictation** — active engine, readiness, and one relevant action.
- **Cleanup** — active engine, readiness, and one relevant action.
- **Recommended for this Mac** — one configuration selected from hardware and measured evidence.

A collapsed **Advanced: Curated local models** disclosure may show other configurations only after they meet their stated admission tier. Experimental candidates remain in development/quality builds. License, exact revision, checksum, and storage receipts remain available in details and diagnostics, not as the normal interaction.

## 4. End-to-end architecture

```text
Shortcut / Capsule / Focused Editor
                |
                v
        LocalWriting facade
                |
     +----------+-----------+
     | capture transaction  |
     | generation + receipt |
     +----------+-----------+
                |
        pin CaptureContext
      (dictionary + catalog
       + hardware revisions)
                |
                v
      capture-first audio ingress
                |
                v
  Apple Speech or admitted local ASR
                |
                v
   deterministic dictionary resolver
                |
                v
 deterministic cleanup -> bounded generator
                |               |
                +---- validator-+
                |
      accepted text or faithful baseline
                |
       +--------+---------+
       | focused insertion|
       | semantic routing |
       +--------+---------+
                |
      durable save + history receipt
                |
      optional Inbox-first chooser
```

### 4.1 External Seam

The desired external Interface is intentionally small. It wraps current behavior before any internal replacement:

```swift
@MainActor
protocol LocalWriting {
  func beginHold(_ request: WritingRequest) -> WritingHold?
  func perform(_ action: WritingActionToken) async -> WritingActionResult
}

@MainActor
protocol WritingHold: AnyObject {
  var events: AsyncStream<WritingEvent> { get }
  func release() async -> WritingOutcome
  func cancel() async -> WritingOutcome
}
```

The capsule receives presentation events and opaque action tokens. It does not receive insertion receipts, cache scores, prompts, model objects, dictionary revisions, or history internals.

This facade is an end-state boundary, not permission for an early rewrite. The current `DictationCoordinator` and `StreamingDictationProcessor` remain the hidden implementation until parity, cancellation, and recovery tests prove the facade.

### 4.2 Per-capture context

Every accepted hold pins one immutable context before recognition begins:

```swift
struct LocalWritingCaptureContext: Sendable {
  let captureID: UUID
  let generation: UInt64
  let localeIdentifier: String
  let dictionary: CompiledPersonalDictionary
  let speechEngineIdentity: DictationSpeechEngine
  let modelConfiguration: LocalWritingModelConfigurationIdentity
  let policyRevision: String
}

struct LocalWritingModelConfigurationIdentity: Sendable {
  let catalogRevision: String
  let configurationKey: String
  let configurationIdentityDigest: SHA256Digest
  let dictationProfileIdentityDigest: SHA256Digest
  let vocabularyProfileIdentityDigest: SHA256Digest?
  let cleanupProfileIdentityDigest: SHA256Digest
  let routingProfileIdentityDigest: SHA256Digest
  let resourcePolicyRevision: String
}
```

The first context packet temporarily uses only the fields and types that already exist or are introduced by the dictionary packet. The catalog/runtime composition packet adds the required non-optional `modelConfiguration` identity shown in the final shape above. Built-in Safe receives exact system/deterministic profile identities too; no active capture uses an anonymous configuration.

The same dictionary revision/content digest and model-configuration identity must appear in ASR acknowledgement, resolution, protected cleanup spans, routing-cache identity, and evidence. A Settings mutation applies only to the next capture.

### 4.3 Mandatory stage order

```text
capture
-> on-device ASR
-> dictionary resolution
-> deterministic cleanup
-> optional bounded local generation
-> faithful validation
-> semantic retrieval
-> optional local route judgment
-> deterministic routing gates
-> durable insertion/save/history
-> optional receipt-bound destination move
```

No catalog profile may reorder these safety boundaries.

## 5. Cross-cutting invariants

### 5.1 Privacy

- Runtime inference has no network fallback.
- Ordinary capture audio is memory-only and destroyed after finish/cancel.
- Ordinary transcripts and note content never enter diagnostic logs.
- Explicit model acquisition is the only model-related network operation.
- Private corpus recording is a separate opt-in mode with a user-selected local root and explicit retention controls.
- No model weights appear in ordinary Fleck resources, Git, archives, or release artifacts.

### 5.2 Faithfulness

- Dictionary resolution precedes cleanup.
- Names, preferred forms, numbers, units, amounts, dates, URLs, paths, code, commands, destinations, commitments, modality, and negation are protected.
- A single protected or semantic violation rejects the entire generated candidate.
- Fleck retains three distinct values: raw ASR, dictionary baseline, and the latest validator-accepted faithful baseline. Safe deterministic cleanup may advance the faithful baseline. A rejected or timed-out generated candidate falls back to that whole faithful baseline; it never partially accepts model edits or discards already validated deterministic cleanup.
- Routing may inspect the dictionary baseline and accepted cleaned text, but cleanup can never create the only evidence for a destination.

### 5.3 Cancellation and ownership

- At most one capture transaction owns publication.
- Release records the absolute deadline before suspension.
- Cancel increments generation before suspension, invalidates action tokens, and drains audio, ASR, cleanup, routing, and persistence compensation.
- No late callback may insert text, create history, move a receipt, or publish a chooser.
- Ambiguity is published only after the capture is durably present in Inbox.
- A destination choice may move only the insertion receipt owned by that capture.

### 5.4 Evidence

- A source file is not integration proof.
- Integration tests are not real-model proof.
- File replay is not live-microphone proof.
- A candidate test app is not an ordinary package.
- An ad-hoc package is not a signed release.
- Synthetic evidence never counts as human-speech evidence.
- Release admission is an explicit owner decision over a frozen evidence packet.

## 6. State models

### 6.1 Writing transaction

```text
idle
 -> arming
 -> listening
 -> finalizingASR
 -> applyingDictionary
 -> cleaning
 -> validating
 -> routing (Smart Capture only)
 -> saving
 -> [saved | needsDestination | failed]

any nonterminal state -> cancelling -> cancelled
needsDestination -> moving -> saved
needsDestination -> keptInInbox
```

Each transition is generation-checked and monotonic. UI state may coalesce progress, but it may not fabricate a completed stage.

### 6.2 Model residency

```text
uninstalled -> installed/cold -> loading -> warm -> active
                                         ^        |
                                         |        v
                                      hibernating <- idle
                                         |
                                         v
                                      unloaded/cold
```

Pressure, Low Power Mode, thermal state, sleep, logout, update, removal, or failure may force a colder state. On an 8 GB Mac, Parakeet and Gemma must not remain resident together; the scheduler hands the inference lease from ASR to cleanup.

### 6.3 Model acquisition

```text
notInstalled -> requestingPermission -> downloading(bytes)
 -> verifying -> installing -> starting -> calibrating -> ready

failure -> repairAvailable -> repairing -> ready
ready -> updateAvailable -> downloading -> atomicSwap -> ready
ready -> removing -> notInstalled
```

Progress is derived from real bytes and named stages. A generic indefinite “Loading” state is forbidden.

## 7. Exact curated configuration templates

These are planned exact tuples, not current release claims. A conditional row does not exist in the catalog until every named profile is exact and qualified; it never means “A or B” at runtime.

| Configuration template | Dictation | Cleanup | Sorting | Intended use |
|---|---|---|---|---|
| English Dictation — Deterministic Writing | Parakeet TDT 0.6B v2 | Deterministic faithful cleanup | Deterministic routing and Inbox fallback | Preserves an independently passing enhanced ASR even if both optional writing models fail |
| English Cleanup — Open Weight | Parakeet TDT 0.6B v2 | Gemma 3 1B 4-bit cleanup profile | Deterministic routing and Inbox fallback | Uses independently admitted cleanup without requiring model routing |
| English Sort — Open Weight | Parakeet TDT 0.6B v2 | Deterministic faithful cleanup | Separate Gemma 3 1B routing profile | Uses independently admitted routing without requiring generated cleanup |
| English Quality — Open Weight | Parakeet TDT 0.6B v2; no vocabulary-assistance profile | Gemma 3 1B 4-bit cleanup profile | Separate Gemma 3 1B routing profile sharing the same artifact | Hold-to-talk, best measured local writing quality |
| English Quality — Open Weight + CTC Assist | Parakeet TDT 0.6B v2 plus one exact auxiliary CTC profile | Gemma 3 1B 4-bit cleanup profile | Separate Gemma 3 1B routing profile sharing the same artifact | Exists only if the auxiliary profile independently passes |
| Apple Local Writing — Cleanup | Apple Speech | Exact Apple Foundation cleanup OS cohort | Deterministic routing and Inbox fallback | Preserves the existing on-device Apple cleanup path when available |
| Apple Local Writing — Sort | Apple Speech | Deterministic faithful cleanup | Exact Apple Foundation routing OS cohort | Uses independently qualified Apple routing without requiring Apple cleanup |
| Apple Local Writing — Full | Apple Speech | Exact Apple Foundation cleanup OS cohort | Exact Apple Foundation routing OS cohort | Existing all-system local path for one proven OS/model cohort |
| English Quality — Apple System | Parakeet TDT 0.6B v2 | Exact Apple Foundation cleanup OS cohort | Exact Apple Foundation routing OS cohort | Eligible Apple Intelligence Macs only |
| Lightweight English — Deterministic | Exact Parakeet TDT-CTC 110M full ASR profile | Deterministic faithful cleanup | Deterministic routing and Inbox fallback | Exists only if TDT-CTC passes lightweight gates |
| Lightweight English — Gemma 270M | Exact Parakeet TDT-CTC 110M full ASR profile | Exact Gemma 270M cleanup profile | Separate exact Gemma 270M routing profile | Exists only if all three role profiles and the joint tuple pass |
| Live English Experimental | One selected exact Parakeet EOU or Unified streaming profile | One exact qualified faithful-cleanup profile | One exact qualified routing profile | Exists only if live partials become a hard requirement and the whole tuple passes |
| Built-in Safe | Apple Speech | Deterministic faithful cleanup | Deterministic corroboration and Inbox fallback | No downloaded weights and universal fallback |

Apple Foundation cleanup/routing belongs only to exact OS-cohort configurations, not Built-in Safe. Historical Whisper, Nemotron, Qwen, rejected cleanup, and future research profiles live in the nonselectable Evaluation Archive collection rather than pretending to be configurations.

Each row is independently identified and admitted. A missing, rejected, removed, or unhealthy optional role selects an already admitted mixed tuple with the deterministic role; Fleck never edits a tuple at runtime or executes an unadmitted role through a fallback chain.

The catalog contains exact revisions, file inventories, checksums, notices, compatibility, and evidence references—but no weights. Only one dictation and one cleanup engine can be active. Alternatives on disk remain cold.

## 8. Quality program

The quality program has four distinct data classes:

1. **Deterministic/synthetic contracts** — edge cases and fault injection; never speech-quality evidence.
2. **Public human replay** — reproducible baseline comparisons; not the user's microphone/accent.
3. **Private local corpus replay** — opt-in real recordings with hashes and operator consent; supports personal-quality claims.
4. **Packaged live-human runs** — exact app artifact, real microphone, real device lifecycle; required for admission.

The initial private corpus floor is 120 human utterances spanning ordinary speech, disfluencies, protected meaning, dictionary terminology, and routing. Admission targets and provenance are specified separately in the corpus design.

## 9. Error and fallback policy

Only failures requiring user action cross the external boundary:

- microphone/speech permission denied;
- no supported speech engine;
- no speech detected;
- persistence failed with a bounded recovery action;
- invalid or busy session;
- explicit model install/repair/update/remove failure in Settings.

Internal quality failures become safe outcomes:

- dictionary unavailable/corrupt before recognition acknowledgement -> discard that buffered capture, publish no text, and show a content-free repair diagnostic; never continue with a mixed or missing dictionary identity;
- cleanup generator unavailable/timeout/rejection -> latest validator-accepted faithful baseline;
- route retrieval/judgment failure -> Inbox;
- enhanced ASR unavailable before capture selection -> Apple Speech; failure after an enhanced capture starts discards that capture and selects Apple Speech for the next capture because the current adapters cannot replay the same PCM;
- model pressure/failure after a faithful text baseline exists -> release lease, downgrade the next eligible profile, and preserve that baseline; an ASR failure before any baseline follows the discard/next-capture rule above;
- invalid choice or changed note -> keep in Inbox and refresh choices if safe.

## 10. Non-goals

- Cloud transcription or cleanup.
- Hidden network fallback.
- Bundling model weights in ordinary Fleck.
- A normal-purpose model marketplace or arbitrary Hugging Face URL installer.
- Multiple simultaneous ASR or cleanup models.
- An always-visible model picker.
- Silent dictionary learning from note edits.
- Learned automatic routing before a separately admitted feedback policy.
- Multilingual admission in this English-first program.
- Intel optimization for enhanced paths.
- Replacing the existing installer, validator, semantic index, or coordinator wholesale.
- Claiming release readiness from unit tests, synthetic cases, or a Mac mini-only run.

## 11. Program completion definition

The program is complete only when all of the following are true for at least one exact configuration:

- all bounded implementation packets have accepted diffs and fresh review verdicts;
- the same dictionary revision is proven across recognition, resolution, cleanup, and routing;
- real stage timings and resource measurements are populated;
- private corpus thresholds pass with zero protected-meaning violations and zero observed wrong automatic routes;
- cancellation and no-late-insertion gates pass at every stage;
- the exact packaged app passes offline, real-microphone, long-transcript, pressure, sleep/wake, repair/removal, and no-weight checks, and either executes a catalog-authorized signed predecessor-to-successor update/rollback or proves that the release embeds no update transition, exposes no Update action, and makes no validated-update claim;
- Mac mini and M1 8 GB MacBook runs use the identical archive and verified executable hashes;
- signing/notarization and distribution checks pass for the intended channel;
- the owner explicitly records release admission.

Anything less must be labeled by its actual evidence tier.

## 12. Implementation workflow gate

Before product implementation begins, the implementation lane must be reconciled explicitly:

- the current tracked `AGENTS.md` mandates Sol Advisor plus user-visible GPT-5.6 Luna/Max implementation tasks and forbids native implementation subagents;
- the user's later stated preference for this program is Codex-native GPT-5.6 Sol/High implementation subagents.

Planning may proceed read-only, but implementation must not silently choose between those contradictory rules. The owner must approve one routing policy or authorize the corresponding `AGENTS.md` update. After that decision, every packet uses one isolated worktree, exact file ownership, red-first tests, parent verification, and a fresh independent reviewer verdict before dependent work begins.
