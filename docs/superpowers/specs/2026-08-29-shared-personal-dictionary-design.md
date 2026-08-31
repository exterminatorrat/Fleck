# Shared Personal Dictionary Design

**Status:** Proposed
**Principle:** One user-owned terminology source, compiled once per revision, consumed consistently by dictation, cleanup, and sorting

## 1. Problem

The current dictionary reliably rewrites aliases after ASR and protects preferred forms from cleanup, but it is not yet one end-to-end language contract:

- recognition context exists in models but is not passed to active speech adapters;
- different stages can reload live state at different times;
- the routing index does not include dictionary revision in its identity;
- suggestions and usage signals exist but do not form a complete explicit-learning loop;
- conflicts can affect ASR hints differently from deterministic resolution unless one compiler excludes them everywhere.

Creating separate “dictation,” “cleanup,” and “sorting” dictionaries would multiply those inconsistencies. Fleck instead evolves the existing `PersonalDictionary` Module.

## 2. Schema v2

Keep the current entry fields and add revisioned snapshot semantics. Do not add phoneme editors, model-specific token IDs, or speculative per-engine parameters.

```swift
struct PersonalDictionarySnapshotV2: Codable, Sendable {
  let schemaVersion: Int               // 2
  let revision: UInt64                 // increments on accepted mutation
  let entries: [PersonalDictionaryEntry]
  let suggestions: [PersonalDictionarySuggestion]
}

struct CompiledPersonalDictionary: Sendable {
  let revision: UInt64
  let contentDigest: SHA256Digest       // effective content + compiler policy, not local revision
  let localeIdentifier: String
  let recognitionStrings: [String]
  let resolverIndex: PersonalDictionaryResolverIndex
  let protectedLexicon: PersonalDictionaryProtectedLexicon
  let routingLexicon: PersonalDictionaryRoutingLexicon
  let diagnostics: [PersonalDictionaryDiagnostic]
  let compilerPolicyRevision: String
}
```

Compilation is deterministic: the same effective entries, locale, and compiler policy produce the same `contentDigest` and outputs even when two devices have different local mutation revision numbers. Evidence records both revision and digest.

## 3. Entry model

The existing conceptual entry remains:

- stable UUID;
- preferred display form;
- aliases;
- locale identifier;
- priority;
- enabled state;
- existing origin (`manual` or `suggested`); `suggested` means the user explicitly approved a proposal, never that Fleck activated it automatically;
- bounded usage metadata.

### 3.1 Meaning of priority

Priority affects bounded ordering for ASR context and tie-free ranking. It never overrides conflict safety and never authorizes cleanup or routing changes. A high-priority ambiguous alias remains excluded.

### 3.2 Locale

The v2 compiler publishes only `en-US` outputs for this program. Unsupported-locale entries are preserved in storage and reported by stable diagnostic code, but are omitted from the active compiled snapshot. Future language support introduces a new compiler policy and evidence tier rather than overloading this one.

## 4. Canonicalization and conflict rules

Canonical comparison uses:

- Unicode canonical composition;
- `en_US_POSIX` case folding for claim identity;
- normalized whitespace at entry boundaries;
- original punctuation, underscore, accent, and display spelling preserved;
- no fuzzy normalization that turns unrelated words into the same claim.

Rules:

1. Empty or whitespace-only preferred forms/aliases are rejected.
2. Duplicate aliases within one entry are rejected.
3. One normalized preferred form owned by multiple entry IDs is a conflict.
4. An alias claimed by multiple preferred forms is ambiguous.
5. An alias equal to another entry's preferred form is ambiguous unless both belong to the same entry.
6. Cycles and overlapping claims never rewrite.
7. Longest safe occurrence wins only among conflict-free claims.
8. Historical conflicts compile by excluding only unsafe claims and publishing diagnostics.
9. New edits, imports, and suggestion approvals must preview and reject creation of a conflict.
10. Disabled entries contribute no runtime output.

The compiler must apply the same exclusion set to recognition strings, resolver rules, protected forms, and routing enrichment. This prevents an ambiguous alias from biasing ASR while the resolver later abstains.

## 5. Compiler products

### 5.1 Recognition product

The compiler emits at most 100 short contextual strings for Apple Speech, ordered deterministically by:

1. priority;
2. explicit manual origin;
3. confirmed use count;
4. recency;
5. stable folded spelling and UUID.

Preferred forms appear before aliases. Truncation is recorded as a content-free diagnostic and evidence count.

For FluidAudio vocabulary assistance, the adapter consumes the same safe preferred/alias set but performs its own tokenizer/compatibility validation. The compiled dictionary contains no model token IDs. The adapter returns an acknowledgement:

```swift
enum RecognitionContextAcknowledgement: Sendable {
  case applied(revision: UInt64, contentDigest: SHA256Digest, acceptedCount: Int)
  case unsupported(revision: UInt64, contentDigest: SHA256Digest)
  case rejected(revision: UInt64, reason: StableCode)
}
```

Post-ASR deterministic resolution remains mandatory even when bias is applied.

### 5.2 Resolver product

The resolver uses boundary-aware longest-first matching over conflict-free aliases. It preserves ambiguous text and returns:

- exact dictionary baseline;
- applied entry IDs and ranges;
- protected preferred-form occurrences;
- stable diagnostics;
- revision/digest acknowledgement.

No downstream stage reruns matching against a newer store snapshot.

### 5.3 Cleanup-protection product

The protected lexicon supplies exact forms and resolved occurrences to `CleanupProtectedSpan`. Preferred forms are protected from lexical change, deletion, splitting, merging, and reordering. The cleanup generator may adjust adjacent punctuation only when the existing validator permits it.

### 5.4 Routing product

The routing lexicon maps all conflict-free aliases and the preferred form to one internal entry identity. It can enrich both transcript and note-index terms so “fleck app” and `FleckApp` corroborate the same concept without making either a destination rule.

Routing cache and query identity include both dictionary revision and content digest. The routing model receives text/evidence, not a table saying a term belongs to a note.

### 5.5 Evidence product

Evidence records structural revision, content digest, counts, truncation, conflict codes, and per-stage acknowledgement. It does not log terms. Private corpus evidence may reference explicit term-case IDs inside the private root.

## 6. Mutation contract

All authoritative mutation goes through `PersonalDictionaryStore`:

```swift
func mutate(
  expectedRevision: UInt64,
  _ mutation: PersonalDictionaryMutation
) async throws -> PersonalDictionarySnapshotV2
```

Optimistic revision checking prevents two Settings/import/suggestion actions from silently overwriting each other. A successful mutation:

1. validates and previews conflicts;
2. computes `newRevision = currentRevision + 1` with checked arithmetic and constructs the complete candidate v2 snapshot;
3. writes those canonical v2 bytes to a new file;
4. fsyncs as appropriate;
5. decodes and compiles the staged candidate bytes, including the already incremented revision;
6. atomically publishes them once;
7. invalidates compiled-cache products for the next capture.

The store retains one non-authoritative recovery copy only for corruption recovery. It is not a second live source. A normal import is a local mutation and therefore rebases to the next local revision. Its compiled `contentDigest` still matches another device when effective entries and compiler policy match. Evidence never assumes local revision numbers match across Macs.

## 7. Migration from v1

Migration is local, deterministic, and non-destructive:

1. decode the current strict v1 snapshot;
2. validate entries using existing rules;
3. assign revision `1` and schema `2`;
4. compile and ensure every current safe resolver result is preserved in compatibility fixtures;
5. write canonical v2 to staging;
6. decode and hash staged bytes;
7. atomically replace the authoritative file;
8. retain the original only as a bounded recovery copy.

Unsupported locales and historical conflicts are preserved but inactive. Migration never invents aliases or deletes entries to achieve a clean compile.

## 8. Capture pinning

The coordinator requests one compiled snapshot while the bounded capture-first ring is already collecting in-memory frames, but before any ASR adapter acknowledges recognition start or consumes those frames. All stage receipts must match:

```text
captureContext.dictionary.revision
 == ASR/resolver/cleanup/routing/evidence revision

captureContext.dictionary.contentDigest
 == ASR acknowledgement contentDigest
 == resolver contentDigest
 == cleanup protection contentDigest
 == routing cache/query contentDigest
 == evidence contentDigest
```

If an adapter cannot apply context, it explicitly reports `unsupported`; evidence must not claim recognition bias. If a stage reports a different revision, processing fails closed before generated text or routing is accepted. With the current Apple and Parakeet capture contracts, a compile/context failure discards the ring, publishes no text, and may select Apple Speech only for the next capture. Reusing the same ring in another adapter is permitted only after a future shared-PCM adapter packet proves that exact capability. No path may create a mixed-revision result.

Settings mutations during capture are allowed but affect the next capture only.

## 9. Explicit learning workflow

### 9.1 Dictionary suggestion

After a receipt-safe correction, Fleck may propose a dictionary suggestion only when the diff is:

- one contiguous lexical replacement;
- non-empty on both sides;
- not only punctuation/case/whitespace;
- not a deletion or reordering;
- free of conflicting protected meaning;
- not already covered by an entry;
- bounded in length.

Example:

> Always write “FleckApp” for “fleck app”?

The user can edit, approve, or dismiss. Approval creates or updates an entry through the normal mutation contract with existing origin `.suggested`. Dismissal removes the pending suggestion; v2 adds no persistent tombstone or hidden suppression database. The current session may avoid immediately re-presenting the same action token in memory.

### 9.2 Excluded implicit signals

Never infer dictionary behavior from:

- arbitrary note edits;
- deleted notes;
- destination choices;
- model-generated cleanup;
- clipboard contents;
- full transcript history;
- audio without an explicit Quality Lab action.

### 9.3 Usage metadata

V2 preserves the existing bounded usage fields but does not add automatic per-capture writes. That avoids turning every dictation into a store mutation, routing-cache invalidation, or optimistic-edit conflict. Initial recognition ranking uses explicit priority, enabled state, origin, existing imported usage values, and stable lexical order. Any future automatic usage policy requires its own evidence-backed packet and a usage revision separate from the structural lexicon revision.

## 10. Settings and correction UI

### 10.1 Personal Dictionary

Keep the existing native Settings section and add only the missing behaviors:

- search enabled/preferred/alias text;
- enabled/all/conflict filter;
- edit preferred form, aliases, priority, locale scope;
- clear conflict preview before Save;
- Suggestions subsection with approve/edit/dismiss;
- import preview showing additions, updates, omissions, and conflicts;
- export current canonical snapshot;
- explanatory copy: “Fleck uses these terms to hear, clean up, and sort your dictation consistently.”

The UI does not expose compiler digests, tokenizers, or ASR boost weights in normal use.

### 10.2 Capture correction

The result capsule/history can offer `Correct dictation…` while the exact insertion receipt is valid. Replacement is receipt-based, never broad string matching. If the note changed and the receipt no longer matches, Fleck records feedback but does not mutate content.

## 11. Privacy and sync boundary

- The dictionary is local app data.
- Terms are never uploaded to a model provider.
- Recognition context is passed only to local/system on-device APIs.
- Errors and diagnostics contain stable codes and counts, not terms.
- Export is explicit.
- Automatic cross-Mac sync is outside this program until the CloudKit entitlement/distribution path is separately admitted.
- Two-Mac quality testing imports the same explicit export and verifies its digest.

## 12. Tests and gates

### 12.1 Unit/property tests

- canonicalization and Unicode boundaries;
- conflict matrix and cycles;
- deterministic ordering/truncation;
- v1-to-v2 migration and rollback;
- canonical bytes and digest stability;
- optimistic revision collision;
- resolver longest-first and ambiguity abstention;
- protected occurrence ranges;
- routing identity enrichment;
- context acknowledgement mismatch;
- safe suggestion diff classifier;
- no term content in diagnostics.

### 12.2 Integration tests

- Apple legacy and macOS 26 adapters receive the same revision;
- unsupported Parakeet bias reports truthfully while post-ASR resolution works;
- cleanup protects every resolved preferred form;
- routing cache invalidates after dictionary mutation;
- Settings mutation during capture affects only the next capture;
- cancel/rollback does not create suggestions or mutate dictionary state;
- receipt-invalid correction does not modify a note.

### 12.3 Human corpus gates

- at least 98% preferred-form accuracy; priority cases 100%;
- no conflict case is rewritten or used for a silent route;
- no dictionary term is changed by accepted cleanup;
- aliases improve or preserve post-dictionary WER in every declared stratum;
- exact digest equality across both Macs in the two-device gate.

## 13. Non-goals

- Model-specific token storage in user data.
- Silent phonetic inference or pronunciation recording.
- Separate routing rules inside dictionary entries.
- Destination note IDs in dictionary entries.
- Cloud dictionary lookup or shared training.
- Automatic acceptance of suggestions.
- Fuzzy alias matching that can change ordinary words.
- Cross-device sync in this program.
