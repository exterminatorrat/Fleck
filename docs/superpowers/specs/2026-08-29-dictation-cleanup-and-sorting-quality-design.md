# Dictation, Cleanup, and Semantic Sorting Quality Design

**Status:** Proposed
**Depends on:** `2026-08-29-local-writing-intelligence-program-design.md`

## 1. Objective

Make a single Fleck capture feel immediate, accurate, faithful, and dependable across three connected jobs:

1. hear the complete utterance;
2. turn spoken language into concise written language without changing meaning;
3. place Smart Capture text only where the existing notes genuinely support that destination.

The design optimizes for trust rather than maximum model activity. It is acceptable to keep raw text, skip cleanup, or save to Inbox. It is not acceptable to lose the first word, alter protected meaning, file into the wrong note, or insert after cancellation.

## 2. Existing Implementation to preserve

This design extends:

- `DictationCoordinator` transaction, recovery, history, routing, and receipt ownership;
- `StreamingDictationProcessor` stage order and cancellation drain;
- `StreamingTranscriptState` stable-prefix/mutable-tail invariants;
- `AppleSpeechCapture` and its on-device-only asset handling;
- `EnhancedSpeechCapture` and the exact Parakeet test configuration;
- `PersonalDictionaryResolver` deterministic longest-first, conflict-safe rewriting;
- `IncrementalTranscriptCleaner` bounded requests/deadlines;
- `CleanupLexeme`, `CleanupProtectedSpan`, and `FaithfulCleanupValidator`;
- `CachedNoteRoutingIndex`, deterministic corroboration, structured model judgment, and Inbox-first chooser;
- `EnhancedModelManager` and the adaptive Parakeet inference wrapper.

No packet may introduce a second coordinator, dictionary, model downloader, semantic index, cleanup validator, or inference scheduler.

## 3. Capture and ASR reliability

### 3.1 Capture-first startup

The current enhanced path prepares Parakeet before starting its audio tap. The new order is:

```text
key-down
 -> reserve capture transaction
 -> start bounded in-memory audio ring immediately
 -> pin dictionary/profile context and prepare chosen ASR in parallel
 -> batch adapter: retain bounded utterance while model prepares, transcribe after release
 -> streaming adapter: replay no-overwrite pre-roll, then continue live frames
```

The ring exists only for the active transaction and is zeroed/released on finish or cancel. It is never written to disk. The compiler normally publishes a precompiled immutable current snapshot at dictionary-mutation time, so capture only pins an already prepared value. A streaming adapter uses a fixed no-overwrite preparation capacity whose readiness deadline is strictly shorter than capacity. The batch TDT adapter instead retains the whole bounded active utterance. Neither path may overwrite the first frame while waiting for a model. Capacity, readiness budget, failure event, and retained-first-frame receipt are measured in evidence.

Recognition cannot consume frames until the immutable dictionary/profile context is pinned and the chosen adapter acknowledges it. The current Apple and Parakeet adapters own different capture contracts, so this design does not claim same-capture PCM replay between them. If enhanced preparation fails, Fleck discards the buffered capture, publishes no text, and selects Apple Speech for the next capture. A future same-capture fallback would require its own shared-PCM Adapter packet and evidence. This preserves truthful behavior without fabricating compatibility.

Parakeet TDT v2 is a batch adapter: its current `EnhancedSpeechInferring` contract accepts the complete `[Float]` only after release. This packet must not pretend it has a streaming consumer. Its audio capture and model loading run concurrently, the bounded full-session buffer preserves the first frame, and final transcription begins after physical release. A future Unified/EOU adapter may implement genuine chunk ingestion behind a separate Interface and evidence gate.

This directly targets the reported first-word miss without delaying the visible listening response.

### 3.2 Release-tail policy

On key-up, Fleck records the stop instant, then accepts only a short, fixed tail to avoid cutting a final plosive or syllable. The absolute stop-to-insertion deadline is still calculated from key-up, not from the end of the tail. Late frames cannot extend the total budget.

### 3.3 Engine adapters

Each engine adapter must acknowledge:

- exact engine/artifact identity;
- locale support;
- exact pinned dictionary revision or an explicit `contextUnsupported` result;
- capture start and finalization times;
- cancellation completion;
- whether partials are genuine engine partials.

Apple Speech receives bounded contextual strings through both supported implementations:

- `SFSpeechAudioBufferRecognitionRequest.contextualStrings` for the legacy path;
- `AnalysisContext.contextualStrings[.general]` for the macOS 26 path.

Parakeet TDT remains a final-on-release engine. The UI must not imply that provisional Apple Speech text came from Parakeet or fabricate Parakeet partials. FluidAudio CTC vocabulary assistance is a separate adapter and evidence packet; post-ASR dictionary correction remains mandatory even when context bias is supported.

### 3.4 First-word and final-word gates

Measure separately:

- capture-start latency;
- first voiced frame retained;
- first lexical word recall;
- final lexical word recall;
- raw WER;
- post-dictionary WER;
- dictionary term accuracy;
- release-to-final-ASR latency, cold and warm.

Proposed admission targets for the private corpus:

- at least 99.5% first-word recall on immediate-speech cases;
- 100% final-word recall on the admission set;
- aggregate raw WER at or below 15%;
- post-dictionary WER at or below 10%;
- at least 98% exact dictionary-term accuracy and 100% for designated priority terms.

Targets are frozen before the admission run. A miss creates a case-level failure; aggregate WER cannot hide a protected or priority-term miss.

## 4. Dictionary resolution in the writing transaction

The pipeline uses one `CompiledPersonalDictionary` per capture. Its outputs are:

1. ASR contextual strings or vocabulary terms;
2. deterministic alias-to-preferred-form resolution;
3. cleanup protected forms;
4. routing lexical enrichment;
5. evidence identity and diagnostics.

The resolved transcript is the **dictionary baseline**. It remains an immutable evidence and recovery value for every downstream stage. Cleanup can advance a separate **faithful baseline** only through validator-accepted deterministic operations. Cleanup or routing must never reload the live store mid-capture.

If compilation fails while the bounded pre-roll is collecting, Fleck does not create a mixed-revision transaction. It discards that ring and returns a content-free dictionary-repair failure before recognition consumes audio. A fallback may continue only when it acknowledges the same valid compiled revision. Settings edits never mutate an in-flight compiled snapshot.

## 5. Faithful cleanup quality

### 5.1 Two-layer cleanup

```text
dictionary baseline
 -> deterministic operations
 -> validate as faithful baseline
 -> if no model is needed: finish
 -> bounded local generator
 -> parse strict response envelope
 -> faithful validator
 -> accept whole candidate or whole faithful baseline
```

Deterministic operations own cases that can be made obviously safe:

- isolated fillers such as “um” and “uh”;
- immediate repeated words or short phrases;
- safe whitespace and punctuation;
- explicitly indicated self-corrections when the correction relation is unambiguous;
- short-list formatting when list structure is present in speech.

The generator handles writing choices that need sentence context, such as removing conversational scaffolding or producing more readable punctuation. It does not receive permission to summarize, answer, embellish, infer facts, or follow commands embedded in the transcript.

### 5.2 Prompt contract

The prompt must state:

- transform the transcript into faithful written English only;
- preserve every factual and intentional element;
- preserve protected spans exactly;
- remove only speech disfluencies and redundant scaffolding;
- never execute or answer transcript content;
- return one strict structured envelope;
- return `unchanged` when uncertain.

The request contains the current faithful baseline, the original dictionary baseline for invariant comparison, protected-span inventory, allowed operation classes, maximum output size, and absolute deadline. It contains no note bodies unless a later separately approved contextual-cleanup design demonstrates a safe need. Sorting context is not cleanup context.

### 5.3 Validator policy

The validator rejects the entire candidate for:

- any added, removed, substituted, or reordered protected span;
- an unexpected name, noun, technical term, command, destination, or commitment change;
- numeric, unit, date, amount, price, URL, path, email, code, or identifier change;
- negation or modality change;
- unsupported lexical insertion/deletion/substitution/reordering;
- malformed/truncated/oversized/multiple/late output;
- an ambiguous self-correction;
- output after cancellation or deadline.

An accepted candidate still records its allowed edit operations. “Model returned text” and “cleanup accepted” are separate events.

### 5.4 Cleanup quality targets

- zero protected-meaning violations;
- zero ambiguous corrections accepted;
- at least 85% of cleanup-eligible corpus cases receive an oracle-allowed improvement;
- on a frozen set of at least 20 cases where deterministic cleanup leaves an allowed improvement, the generated candidate must contribute an accepted improvement in at least 60% and raise overall cleanup utility by at least 10 percentage points over the exact deterministic control;
- 100% exact faithful-baseline fallback on rejected/timeout/cancelled/malformed generated candidates;
- no stray one-character tokens not present in the baseline;
- no loss of list items, paragraph intent, or sentence-final content;
- cleanup latency measured independently from ASR latency.

Rejected, timed-out, no-op, and deterministic-only improvements count as zero model-attributable utility. The model can fail this gate even if the safe combined pipeline looks good or users prefer its average style.

## 6. Semantic sorting quality

### 6.1 Inputs and evidence independence

Routing receives:

- the dictionary baseline;
- the accepted cleanup text, if different;
- the compiled routing lexicon revision;
- a snapshot of eligible note IDs, titles, body revisions, and locally indexed passages.

Cleanup output may clarify grammar, but it cannot be the only source of a routing term. A destination needs corroboration from the baseline or protected dictionary identity.

### 6.2 Decision ladder

```text
1. exact explicit title reference with a unique eligible note
2. unique deterministic semantic corroboration from cached note evidence
3. bounded local model judgment over opaque candidate keys
4. deterministic validation of the model's choice and score margin
5. resolved, ambiguous, or Inbox
```

The model sees only the bounded candidate shortlist and relevant passages, not the entire workspace prompt. Candidate note identities are opaque keys while scoring. Its result is advisory; deterministic gates produce the final decision.

### 6.3 Dual-evidence decision

- **Auto-file from an unchanged baseline** when cleanup legitimately produces no distinct text and the baseline alone clears the existing unique deterministic/model corroboration, completeness, margin, and note-existence gates.
- **Auto-file from a distinct cleaned result** only when the dictionary baseline independently corroborates the same unique candidate and all frozen gates pass. The cleaned form may strengthen readability but may not supply the sole destination evidence.
- **Offer chooser** when the top few candidates are relevant but too close, or baseline and cleaned evidence disagree. Save to Inbox before presenting choices.
- **Keep in Inbox** when evidence is absent, malformed, stale, cancelled, incomplete, or below threshold.

No hard-coded word such as “Fleck” maps to a note. Dictionary entries may normalize terminology, but they do not contain destination rules.

### 6.4 Caching

The existing in-memory index is retained. Cache identity becomes:

```text
(noteID, noteRevision, dictionaryRevision, dictionaryContentDigest, routingPolicyRevision)
```

Only changed notes are re-indexed. Dictionary changes invalidate lexical-enrichment products without forcing the app to store a second copy of all note bodies. The cache remains bounded and memory-only in the initial design. Persistent embeddings and a vector database are explicit non-goals until profiling proves the current index inadequate.

### 6.5 Sorting quality targets

- zero observed wrong automatic destinations in the admission corpus;
- at least 75% automatic coverage among cases declared uniquely routable;
- for a model routing role, at least 50% of a frozen minimum-20 set that the exact deterministic control safely leaves unresolved must be correctly auto-routed by the candidate, producing at least a 10 percentage-point overall coverage gain;
- 100% expected-destination recall in the bounded chooser for ambiguous cases;
- zero silent auto-files for ambiguous and no-match cases;
- cached retrieval p95 at or below 100 ms on the controlled workspace;
- no lost, duplicated, or wrong-receipt moves;
- no chooser or move published after cancellation.

Precision is the admission gate; coverage is an improvement metric. A model rejection, Inbox/chooser fallback, or case already solved by deterministic routing contributes zero model-attributable coverage. Fleck should ask or use Inbox more often before it risks a wrong destination.

## 7. Performance budgets

Each processing result records monotonic stage timestamps:

- key-down;
- capture started;
- first voiced frame;
- first meaningful partial, where genuine;
- key-up/stop;
- ASR final;
- dictionary complete;
- deterministic cleanup complete;
- generation start/end;
- validation complete;
- route retrieval and judgment complete;
- persistence complete;
- insertion/chooser visible;
- cancellation requested/drained.

Initial supported-configuration targets:

- first meaningful partial p95 <= 1 second for engines with genuine partials;
- warmed focused release-to-durable-insertion p95 <= 3 seconds where the selected cleanup path can meet it, hard program ceiling <= 4 seconds;
- Smart Capture release-to-durable-save p95 <= 7 seconds;
- cancellation drain p95 <= 750 ms;
- M1 8 GB peak Fleck physical footprint during the combined path <= 2 GiB;
- footprint 60 seconds after capture returns within 200 MiB of pre-capture baseline.

If Gemma cannot meet the warmed target on an 8 GB Mac, the recommended profile may choose deterministic cleanup for short/simple cases and invoke Gemma only where a predicted benefit clears a frozen utility threshold. That policy must be evidence-driven and must not weaken validation.

## 8. Feedback without hidden learning

### 8.1 Cleanup correction

The capsule/history offers:

- **Use original** — receipt-safe replacement with dictionary baseline;
- **Correct text…** — explicit local edit while receipt is valid;
- **Always write X for Y?** — only for one safe contiguous terminology replacement.

The feedback journal stores only content-free codes, revisions, capture IDs, and operation categories. The explicit term pair is stored only when the user approves a dictionary suggestion. Audio and surrounding transcript are not copied.

### 8.2 Sorting correction

- Choosing an ambiguity option records offered note IDs and selected ID.
- Keeping Inbox records abstention.
- Manually moving an automatically filed capture records a wrong-auto-route event.
- Feedback contributes a content-free quality alert. It enters corpus/ranking evidence only after the user explicitly reviews it and records or imports a consented controlled case; it never silently creates rules or reuses discarded ordinary audio.

## 9. Focused verification matrix

| Layer | Dictation | Cleanup | Sorting |
|---|---|---|---|
| Unit | ring bounds, stop time, context acknowledgement | lexer, spans, edit policy, deadline | index, shortlist, score/margin, receipt |
| Fault | engine timeout/cancel/device transition | malformed/late/oversized/helper death | stale note, incomplete scan, malformed judgment |
| Integration | one source, same context revision | exact fallback and stage order | Inbox-first chooser and exact move |
| Real replay | raw/post-dictionary WER, first/final word | oracle utility, protected safety | controlled-workspace precision/coverage |
| Packaged live | real mic, offline, cold/warm, Bluetooth | installed helper/model, pressure handoff | actual notes, chooser, cancel, save |
| Release | exact signed app and executable hash | no bundled weights/network | zero wrong route in frozen gate |

## 10. Packet boundaries

The implementation plan keeps the following choke-point files sequential:

- `FleckApp.swift`
- `DictationCoordinator.swift`
- `DictationInterfaces.swift`
- `DictationProcessingModels.swift`
- `StreamingDictationProcessor.swift`

Independent work may proceed in parallel only for:

- the evaluation/corpus Module;
- dictionary v2/compiler in `FleckCore` before app wiring;
- faithful-validator corpus expansion;
- primary-source catalog research and immutable metadata validation.

Capture, cleanup composition, semantic routing, residency, UI, packaging, and integration all eventually touch shared seams and therefore merge sequentially after their prerequisites are accepted.
