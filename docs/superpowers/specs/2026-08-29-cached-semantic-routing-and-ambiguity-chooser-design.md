# Cached Semantic Routing and Ambiguity Chooser Design

**Status:** Implemented checkpoint; query-evidence semantics are superseded by `2026-08-29-dictation-cleanup-and-sorting-quality-design.md` where noted below.

## Summary

Fleck will replace narrow keyword exceptions and bounded whole-workspace prompt
scans with a local cached retrieval layer. Smart Capture will search the full
content of every active note, ask the local routing model to judge only a small
shortlist of relevant excerpts, and auto-file only a uniquely strong match.

When two or more notes remain plausible, Fleck will preserve the capture in
Inbox first and present a compact `Choose note` action through the existing
bottom dictation capsule. The user can move that exact capture to one of the
ranked notes or leave it in Inbox. No transcript is kept only in transient UI
state, and routing uncertainty never becomes a silent guess.

This design keeps speech recognition, faithful cleanup, retrieval, model
judgment, and persistence as separate responsibilities:

`Parakeet -> dictionary -> cleanup -> faithful validation -> retrieval -> routing -> save`

Parakeet produces text. Cleanup may improve presentation without changing
meaning. Note content informs only destination routing; it must never be used to
rewrite the dictated transcript.

## Goals

- Route from arbitrary note titles and full note bodies without Fleck-specific
  keyword mappings.
- Keep dictation-time work bounded as the workspace grows.
- Preserve the existing exact-title fast path.
- Automatically save only when one destination is clearly stronger.
- Make close matches recoverable through a small, local, non-blocking chooser.
- Keep all note content, retrieval features, prompts, and model results local.
- Preserve Inbox, Apple Speech, cancellation, and the latest whole
  validator-accepted faithful baseline after dictionary resolution; an ASR
  failure before any text baseline publishes nothing and selects Apple Speech
  for the next capture.
- Make routing decisions testable independently of ASR and cleanup.

## Non-Goals

- Parakeet does not become a note router or cleanup model.
- Cleanup does not use note bodies as writing context.
- Fleck does not create topical notes automatically.
- Fleck does not learn silently from a user's chooser selection in this packet.
- Fleck does not add a general model picker or a new model download.
- Fleck does not upload transcripts, note text, cache entries, or routing
  evidence.
- Fleck does not claim release readiness from local tests.

## Approaches Considered

### Prompt every note on every capture

Sending all notes directly to Gemma is simple at small scale, but prompt size,
latency, and last-option bias grow with the workspace. It also cannot reliably
cover the middle of long notes. This approach is rejected.

### Semantic embeddings alone

A vector index can retrieve conceptual matches quickly, but a single opaque
similarity score is weak evidence for automatic filing. Availability of a local
embedding provider must also remain optional. This approach is not sufficient
by itself.

### Cached hybrid retrieval followed by bounded model judgment

The selected approach combines deterministic lexical and phrase retrieval with
optional locally available semantic similarity, then asks Gemma to judge only
the strongest few notes and excerpts. Deterministic score and margin gates
remain outside the model. This keeps the interface deep, the prompt bounded,
and uncertainty explicit.

## Routing Outcomes

The router returns a structured decision rather than only a nullable note ID:

- `resolved(noteID)` means one valid candidate passed every automatic gate.
- `ambiguous(candidates)` means at least two candidates are plausible but none
  has a safe unique lead.
- `inbox` means no candidate is adequately supported or routing failed.

An ambiguity candidate contains only the note ID, current display title, score
metadata needed for deterministic ordering, and a short local excerpt for user
recognition. The excerpt is presentation data, not text to append.

Duplicate note titles are allowed in ambiguity results. Their context hints
distinguish them. Invalid IDs, duplicate IDs, deleted notes, stale revisions,
malformed model output, timeouts, and cancellation never produce an automatic
destination.

## Cached Note Retrieval

### Cache identity and lifecycle

Each active note is indexed by stable note ID and content revision. The cache
stores derived local retrieval data, not another authoritative copy of the
workspace.

On synchronization, the index compares note IDs and revisions:

- New and restored notes are indexed.
- Notes whose title or body revision changed are reindexed.
- Deleted or trashed notes are removed.
- Unchanged notes reuse their cached features.

The initial implementation uses an in-memory cache and rebuilds it from the
local workspace after launch. A persistent cache is deliberately deferred until
measurements demonstrate that rebuild time is material. This avoids stale disk
indexes, migrations, and another sensitive-data lifecycle.

### Full-note coverage

Each title and complete normalized note body is divided into bounded,
overlapping passages. Retrieval retains the best passages per note rather than
only the beginning and end of the document.

The deterministic index includes:

- normalized words and phrases;
- document-frequency weighting so rare terms matter more than generic prose;
- character fragments for ordinary inflection and small ASR spelling
  differences;
- a title boost without making titles mandatory;
- optional local semantic vectors when the operating system provides an
  admitted on-device embedding facility.

No product-specific word pair, plural suffix, note title, or project name is
embedded in the retrieval rules. The existing terminal `grams` exception stays
only until the general retriever is proven by replacement tests, then is
removed in the same accepted implementation sequence.

### Query behavior

At Smart Capture completion, the index builds separate query evidence from the
immutable dictionary baseline and the accepted cleanup result. If cleanup is
unchanged, the baseline alone may pass the existing unique corroboration gates.
If cleanup is distinct, the dictionary baseline must independently corroborate
the same destination; cleanup may not invent the only routing term. Disagreement
or close evidence yields the durable Inbox chooser. The index searches cached
passages and returns a small ordered union of the best notes. The implementation
will benchmark and fix the shortlist size; it will not expose it as a user
setting.

Gemma receives only those candidate IDs, titles, and best excerpts. Its result
must select an opaque candidate key already present in the request. The final
automatic gate requires both deterministic retrieval support and a unique
model-supported leader. A close score, conflicting evidence, or unsupported
model choice yields `ambiguous`, not a guessed note.

## Durable-First Ambiguity Flow

### Persistence boundary

For an ambiguous result, Fleck first appends the cleaned or safe fallback text
to Inbox through the existing receipt-based Smart Capture save path. Only after
that write is durable does the UI offer destination choices.

The ambiguity record binds to the capture ID and insertion receipt. It never
locates text later by string matching. This prevents moving the wrong paragraph
when identical dictation already exists in Inbox.

### Capsule presentation

The bottom capsule changes from `Finding note` to a durable result state:

`Saved to Inbox` + `Choose note`

Choosing the action opens a compact native macOS menu anchored to the capsule.
It contains only the strongest plausible destinations plus `Keep in Inbox`.
Each destination uses its current display title and, when needed, a short
matching-context hint. The normal capsule remains nonactivating so Smart
Capture does not unexpectedly foreground Fleck or disturb the user's current
application.

There is no countdown and no silent default to the top candidate. Ignoring or
dismissing the menu leaves the text safely in Inbox. Starting another dictation
does not block on an unresolved choice.

### Moving the capture

Selecting a note performs one bounded local transfer:

1. Verify that the Inbox insertion receipt still identifies the exact capture.
2. Verify that the chosen note still exists and is active.
3. Append the captured text to the chosen note.
4. Remove only the receipt-owned Inbox insertion.
5. Update Dictation History with the final destination.

If any verification or persistence step fails, Fleck leaves the Inbox content
unchanged and presents an actionable failure. Cancellation or a late selection
cannot produce a second insertion.

## State and Interface Boundaries

The retrieval index is an actor-like service with a narrow interface: synchronize
workspace documents and retrieve a bounded shortlist for one query. Its
internals hide tokenization, passage splitting, document frequencies, optional
semantic vectors, and invalidation.

Destination routing consumes the shortlist and produces a structured routing
decision. It does not persist notes or present UI.

The coordinator owns the capture lifecycle and converts a routing decision into
one save. It exposes a durable ambiguity presentation only after Inbox
persistence succeeds.

The runtime maps that presentation to the existing capsule controller. The
capsule owns only presentation and choice callbacks; it does not move note
content directly.

AppState performs the receipt-validated Inbox-to-note transfer and history
update through the existing workspace persistence boundary.

## Performance and Resource Policy

- Full note tokenization occurs only for a new or changed revision.
- A capture queries cached posting lists and a bounded candidate union instead
  of rescanning every note body.
- Optional semantic vectors are computed locally per changed passage and are
  never required for safe operation.
- Gemma sees a bounded prompt and no longer has a workspace-count ceiling.
- Cache memory and passage limits are fixed internally and covered by stress
  tests; no advanced tuning UI is added.
- Cache rebuild, query, Gemma routing, and cleanup latency are measured
  separately.

## Failure and Cancellation Rules

- Cache unavailability or rebuild failure routes to Inbox.
- Optional embedding failure falls back to deterministic retrieval.
- Gemma failure, malformed output, deadline, or cancellation cannot auto-file.
- A cancellation before the Smart Capture commit writes nothing.
- A cancellation after the Inbox commit uses the existing receipt compensation
  rules and cannot leave a late chooser that can mutate notes.
- Deleted or changed ambiguity destinations are revalidated at selection time.
- Transfer failure preserves the authoritative Inbox copy.

## Accessibility and Interaction

- `Choose note` has an explicit accessibility label and action.
- Candidate menu items expose the complete note title; visual truncation does
  not truncate accessibility text.
- `Keep in Inbox` is a first-class menu item, not an unlabeled dismissal.
- Reduced Motion uses the capsule's existing opacity-only behavior.
- The chooser uses native pointer and keyboard menu behavior without adding a
  permanently key-capable floating window.
- Frequent keyboard-started dictation receives no decorative chooser animation.

## Verification

Focused tests must prove:

- A relevant phrase in the middle of a long note is retrievable.
- Arbitrary vocabulary, ordinary plurals, and small ASR spelling differences do
  not require hard-coded mappings.
- New, edited, renamed, restored, trashed, and deleted notes invalidate only
  their own cache entries.
- Large workspaces no longer fall back solely because they exceed 24 notes.
- A clear unique result saves directly to its note.
- A close pair saves once to Inbox and exposes both choices in stable order.
- Ignoring or dismissing the chooser leaves the Inbox copy unchanged.
- Selecting a candidate transfers exactly the receipt-owned insertion and
  updates history.
- Duplicate titles remain distinguishable by candidate identity and context.
- Deleted destinations, transfer failures, cancellation, and late callbacks
  cannot duplicate or lose text.
- Routing prompts remain bounded and contain only shortlisted excerpts.
- Cleanup output is identical regardless of note content.
- Existing focused dictation, exact-title routing, Inbox fallback, undo,
  recovery, accessibility, and capsule docking tests remain green.

Performance evidence must separately report cold cache rebuild, unchanged-cache
query, one-note reindex, routing-model latency, and end-to-end stop-to-save
latency for representative small and large local workspaces.

## Implementation Sequence

The design will be implemented in dependency order as separate bounded packets:

1. Pure cached retrieval index and tests.
2. Structured routing outcomes and bounded Gemma shortlist/rerank behavior.
3. Receipt-bound ambiguous Inbox transfer contract and coordinator tests.
4. Capsule `Choose note` presentation and accessibility tests.
5. App composition, focused regression verification, local package, and
   hands-on Smart Capture script.

Every packet must preserve unrelated work, use the repository-mandated
implementation lane, receive parent verification and a fresh `ship` review,
and avoid push, pull request, merge, GitHub changes, or model downloads unless
the user separately authorizes them.

## Source Checkpoint

The design was written on `codex/local-gemma-semantic-routing` at accepted local
checkpoint `71294ed`, whose committed base is the current UI checkpoint
`895e465`. Uncommitted files in the primary checkout are unrelated user work
and are not part of this design or its implementation ownership.
