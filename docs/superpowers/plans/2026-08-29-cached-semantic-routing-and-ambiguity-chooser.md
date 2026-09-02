# Cached Semantic Routing and Ambiguity Chooser Implementation Plan

> **For agentic workers:** USER-OVERRIDDEN ROUTE: For this implementation, the user's explicit 2026-08-29 instruction replaces the repository's default Luna/Max lane with Codex-native GPT-5.6 Sol implementers at High reasoning. Each numbered task is one dependent implementation packet in the existing isolated worktree. The primary Sol session inspects every diff, reruns verification, and obtains a fresh read-only Sol/High reviewer verdict exactly `ship` before the next task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search the full local note workspace through a revision-aware cache, auto-file only uniquely supported dictation, and let the user move ambiguous captures from durable Inbox storage through the bottom dictation capsule.

**Architecture:** A local actor caches passage-level lexical features for each note revision and returns a bounded shortlist. Gemma judges only that shortlist. Routing later gains structured `resolved`, `ambiguous`, and `inbox` outcomes; ambiguous text is committed to Inbox before the capsule offers a native note-choice menu backed by an exact insertion receipt.

**Tech Stack:** Swift 6, Foundation, Swift Concurrency actors/tasks, SwiftUI/AppKit, Swift Testing, and the existing Fleck persistence and Gemma helper seams. No new package dependency.

**Spec:** `docs/superpowers/specs/2026-08-29-cached-semantic-routing-and-ambiguity-chooser-design.md`

## Global Constraints

- Work from accepted local branch `codex/local-gemma-semantic-routing` at plan checkpoint `1849519`, based on committed UI checkpoint `895e465`.
- Preserve the primary checkout's unrelated uncommitted `AGENTS.md`, `Sources/FleckApp/NotesPanel.swift`, research, output, temporary, and iCloud plan/spec files.
- English-only and Apple-silicon-only remain the current enhanced-model scope.
- Parakeet produces ASR text; it does not route notes or rewrite cleanup output.
- Note content may influence destination routing only. It must never influence transcript cleanup text.
- All audio, transcripts, note text, retrieval features, excerpts, prompts, and model output remain local.
- Exact-title routing remains the first fast path.
- A unique model choice without deterministic retrieval support cannot auto-file.
- An ambiguous result is saved to Inbox before any chooser becomes visible.
- Ignoring or dismissing the chooser leaves Inbox unchanged.
- No hard-coded project title, keyword pair, plural suffix, or user note content is allowed in production routing logic.
- No new model, model download, model weight, persistent retrieval cache, cloud service, hidden network fallback, or ordinary app-bundle model weight is added.
- No push, pull request, merge, rebase, GitHub mutation, or release-readiness claim is authorized.
- Run SwiftPM checks serialized and without automatic dependency resolution: `swift test --disable-automatic-resolution --no-parallel ...`.

---

## Task 1: Revision-aware cached note retrieval

**Native worker task:** `cached_note_routing_index`

**Files:**

- Modify: `Sources/FleckApp/DictationInterfaces.swift`
- Create: `Sources/FleckApp/CachedNoteRoutingIndex.swift`
- Create: `Tests/FleckAppTests/CachedNoteRoutingIndexTests.swift`

**Interfaces:**

Extend `DictationRoutingCandidate` with an explicit initializer and `contentRevision: UInt64`, defaulting to `0` so existing fixtures remain source-compatible.

```swift
struct CachedNoteRoutingMatch: Equatable, Sendable {
  let candidate: DictationRoutingCandidate
  let excerpt: String
  let score: Int
  let exactTermMatches: Int
}

actor CachedNoteRoutingIndex {
  func retrieve(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    limit: Int = 6
  ) -> [CachedNoteRoutingMatch]
}
```

The actor hides synchronization, passage splitting, tokenization, document frequency, inverted postings, scoring, and stale-note removal.

**Required behavior:**

- Normalize whitespace and split complete note bodies into passages of at most 96 words with 24-word overlap.
- Index title terms and passage terms using `CleanupLexeme`; ignore the generic English function words currently ignored by Gemma routing.
- Add lowercase ASCII character trigrams for meaningful words of at least four characters. Trigrams are generic fuzzy evidence, never transcript replacement.
- Keep postings by exact term and trigram so a query visits matching cached passages instead of rescanning all note text.
- Reindex only a candidate whose note ID is new or whose `contentRevision`, destination title, or semantic context changed. Remove entries for note IDs absent from the latest candidate set.
- Score title exact terms above body exact terms; score trigrams below exact terms; down-weight features appearing in many notes.
- Return at most `limit` unique notes in deterministic score, title, then UUID order, with each note's highest-scoring bounded excerpt.
- Return an empty list for blank or generic queries, nonpositive limits, no evidence, cancellation, or duplicate candidate IDs.
- Do not add `NLEmbedding` yet. Deterministic cached retrieval is the smallest measurable foundation; semantic vectors require separate evidence that lexical-plus-Gemma recall is insufficient.

- [ ] **Step 1: Add failing interface and cache tests.** Cover full-body middle retrieval, arbitrary terms, `hologram`/`holograms` trigram evidence without a suffix rule, stable ranking, title boost, duplicate-ID failure, changed-revision reindex, same-revision reuse, deletion, result limit, and cancellation.

```swift
@Test func cachedRoutingFindsEvidenceFromTheMiddleOfALongNote() async {
  let index = CachedNoteRoutingIndex()
  let target = routingCandidate(
    title: "Optics",
    body: String(repeating: "ordinary context ", count: 120)
      + "laser interference holography experiment"
      + String(repeating: " trailing context", count: 120),
    revision: 4
  )
  let matches = await index.retrieve(
    transcript: "Record the laser holography experiment",
    candidates: [target]
  )
  #expect(matches.first?.candidate.destination.noteID == target.destination.noteID)
  #expect(matches.first?.excerpt.contains("laser interference holography") == true)
}
```

- [ ] **Step 2: Run the focused tests red.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter CachedNoteRoutingIndexTests
```

Expected: compilation fails because the new cache types and revision field do not exist.

- [ ] **Step 3: Implement the smallest actor cache.** Use private nested value types in the new file; do not create a protocol, persistent store, configurable scoring UI, background daemon, or embedding abstraction.

```swift
struct DictationRoutingCandidate: Equatable, Sendable {
  let destination: DictationDestination
  let semanticContext: String
  let contentRevision: UInt64

  init(
    destination: DictationDestination,
    semanticContext: String,
    contentRevision: UInt64 = 0
  ) {
    self.destination = destination
    self.semanticContext = semanticContext
    self.contentRevision = contentRevision
  }
}
```

- [ ] **Step 4: Run focused and routing regressions green.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter CachedNoteRoutingIndexTests
swift test --disable-automatic-resolution --no-parallel --filter GemmaDestinationRouterTests
swift test --disable-automatic-resolution --no-parallel --filter AppStateDictationTests
```

Expected: every command exits `0`; existing fixtures compile through the default revision.

- [ ] **Step 5: Inspect exact scope and commit.**

```bash
git diff --check
git status --short
git diff -- Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/CachedNoteRoutingIndex.swift Tests/FleckAppTests/CachedNoteRoutingIndexTests.swift
git add Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/CachedNoteRoutingIndex.swift Tests/FleckAppTests/CachedNoteRoutingIndexTests.swift
git commit -m "feat: add cached note routing index"
```

Expected: exactly the three owned paths differ and the commit SHA is reported.

---

## Task 2: Full-note cached shortlist and bounded Gemma routing

**Native worker task:** `cached_gemma_destination_shortlist`

**Dependency:** Task 1 parent verification and fresh Sol verdict `ship`.

**Files:**

- Modify: `Sources/FleckApp/AppState.swift`
- Modify: `Sources/FleckApp/GemmaDestinationRouter.swift`
- Modify: `Tests/FleckAppTests/AppStateDictationTests.swift`
- Modify: `Tests/FleckAppTests/GemmaDestinationRouterTests.swift`

**Interfaces:** Consume `CachedNoteRoutingIndex.retrieve(transcript:candidates:limit:)`. Keep `DestinationRouting.route(...) async -> UUID?` for this packet so ambiguity still returns Inbox until Task 4.

```swift
init(
  generator: any GemmaRouteGenerating,
  index: CachedNoteRoutingIndex = CachedNoteRoutingIndex(),
  clock: CleanupClock = .live,
  budget: Duration = .seconds(3)
)
```

**Required behavior:**

- `AppState.activeDestinations()` supplies each active note's complete raw body by
  value plus `Note.revision`; Trash remains excluded. It does not normalize or
  truncate bodies, so unchanged notes avoid another full-text scan before the
  cache decides whether reindexing is required. The cache normalizes only changed
  revisions.
- Gemma removes the 24-candidate guard and asks the index for at most six notes. Inbox is excluded from retrieval and prompts.
- The prompt contains shortlisted titles and bounded best excerpts, not all note bodies.
- A single clearly supported match may keep the deterministic fast path. Multiple supported matches require Gemma plus a unique highest retrieval score; ties and lower-scored choices return Inbox.
- Remove `normalizedTerminalGramPlural`; cached generic trigram evidence replaces the exception.
- Preserve opaque candidate keys, JSON encoding, the 32 KiB prompt cap, three-second budget, acknowledgement, and cancellation drain.

- [ ] **Step 1: Write red tests.** Replace the 480-character AppState assertion
  with exact complete raw-body and revision checks. Add 40-note, middle-of-note,
  bounded-shortlist, cache-reuse, and no-hard-coded-`grams` tests.
- [ ] **Step 2: Run red.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppStateDictationTests
swift test --disable-automatic-resolution --no-parallel --filter GemmaDestinationRouterTests
```

Expected: the new full-body, revision, and shortlist assertions fail.

- [ ] **Step 3: Integrate the cache with the existing prompt and candidate-index validation; replace only candidate preparation and corroboration.**
- [ ] **Step 4: Run green and routing regressions.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppStateDictationTests
swift test --disable-automatic-resolution --no-parallel --filter GemmaDestinationRouterTests
swift test --disable-automatic-resolution --no-parallel --filter DynamicDestinationRouterTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
```

- [ ] **Step 5: Inspect and commit the four owned paths.**

```bash
git diff --check
git status --short
git add Sources/FleckApp/AppState.swift Sources/FleckApp/GemmaDestinationRouter.swift Tests/FleckAppTests/AppStateDictationTests.swift Tests/FleckAppTests/GemmaDestinationRouterTests.swift
git commit -m "feat: route from cached full-note context"
```

---

## Task 3: Receipt-bound Inbox transfer

**Native worker task:** `ambiguous_capture_transfer_contract`

**Dependency:** Task 2 parent verification and fresh Sol verdict `ship`.

**Files:**

- Modify: `Sources/FleckApp/DictationInterfaces.swift`
- Modify: `Sources/FleckApp/AppState.swift`
- Modify: `Tests/FleckAppTests/AppStateDictationTests.swift`

**Interfaces:**

```swift
func moveSmartCapture(
  _ receipt: DictationInsertionReceipt,
  to destinationID: UUID
) async -> DictationInsertionReceipt?
```

The returned receipt keeps the capture ID, uses the chosen note ID, and records the exact newly appended suffix. `nil` means Inbox remains authoritative.

Provide a default protocol-extension implementation that returns `nil`, so
existing non-AppState test savers remain source-compatible until Task 4 needs
explicit transfer behavior.

**Required behavior:**

- Verify source and destination exist, differ, and the source still ends with the nonempty receipt suffix.
- Snapshot both notes and prior selection.
- Append through `NoteTextAppender`, remove only the receipt suffix from source, and persist both mutations in one `saveNow(transactionOwned: true)`.
- Restore both notes and selection exactly on failure.
- Never find the insertion by arbitrary string search and never auto-delete an empty Inbox.
- Concurrent source edits, missing targets, same-target selection, duplicate callbacks, and failures change neither note.

- [ ] **Step 1: Write red tests** for success, rich text, stale source, missing target, same target, duplicate callback, and save rollback.
- [ ] **Step 2: Run red.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppStateDictationTests
```

- [ ] **Step 3: Implement by reusing current append, suffix removal, awaited-save, and rollback patterns. Do not add a transfer-service abstraction.**
- [ ] **Step 4: Run green.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppStateDictationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
```

- [ ] **Step 5: Inspect and commit.**

```bash
git diff --check
git status --short
git add Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/AppState.swift Tests/FleckAppTests/AppStateDictationTests.swift
git commit -m "feat: move receipt-bound Inbox captures"
```

---

## Task 4: Structured ambiguity and coordinator lifecycle

**Native worker task:** `durable_ambiguous_routing_lifecycle`

**Dependency:** Task 3 parent verification and fresh Sol verdict `ship`.

**Files:**

- Modify: `Sources/FleckApp/DictationInterfaces.swift`
- Modify: `Sources/FleckApp/GemmaDestinationRouter.swift`
- Modify: `Sources/FleckApp/DynamicDestinationRouter.swift`
- Modify: `Sources/FleckApp/FoundationModelDictation.swift`
- Modify: `Sources/FleckApp/DictationCoordinator.swift`
- Modify: `Tests/FleckAppTests/GemmaDestinationRouterTests.swift`
- Modify: `Tests/FleckAppTests/DynamicDestinationRouterTests.swift`
- Modify: `Tests/FleckAppTests/FoundationModelDictationTests.swift`
- Modify: `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Interfaces:**

```swift
struct DictationRoutingChoice: Equatable, Sendable {
  let destination: DictationDestination
  let contextHint: String
}

enum DictationRoutingDecision: Equatable, Sendable {
  case resolved(UUID)
  case ambiguous([DictationRoutingChoice])
  case inbox
}
```

`DestinationRouting.route` returns `DictationRoutingDecision`. Coordinator adds:

```swift
private(set) var routingChoices: [DictationRoutingChoice] = []
func chooseDestination(_ noteID: UUID?) async -> DictationRecoveryResult?
```

`nil` means keep the durable Inbox copy.

**Required behavior:**

- Exact-title and uniquely supported routes return `.resolved`; close supported results return at most four stable `.ambiguous` choices; failures return `.inbox`.
- Dynamic routing validates returned IDs. Foundation maps only its existing high-confidence choice to `.resolved`; it does not invent ambiguity.
- Coordinator saves ambiguous text once to Inbox, records Inbox in History, retains its receipt and choices, then publishes the normal durable saved outcome.
- A valid choice calls `moveSmartCapture`, updates the same History record, replaces the recovery receipt, and exposes Undo.
- Keeping Inbox clears choices without changing note text or History.
- A new capture clears stale choices but preserves the prior Inbox capture.
- Failed, duplicate, deleted-note, cancelled, or late choices cannot duplicate or lose text.

- [ ] **Step 1: Convert routing fixtures and add red lifecycle tests** proving one Inbox insertion, visible choices, exact-receipt move, one final copy, and updated History.
- [ ] **Step 2: Run red suites.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter GemmaDestinationRouterTests
swift test --disable-automatic-resolution --no-parallel --filter DynamicDestinationRouterTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
```

- [ ] **Step 3: Implement inside the existing routing and Smart Capture lifecycle. Do not add another coordinator, queue, notification channel, or chooser database.**
- [ ] **Step 4: Rerun the four suites green.**
- [ ] **Step 5: Inspect and commit the exact nine-file scope.**

```bash
git diff --check
git status --short
git add Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/GemmaDestinationRouter.swift Sources/FleckApp/DynamicDestinationRouter.swift Sources/FleckApp/FoundationModelDictation.swift Sources/FleckApp/DictationCoordinator.swift Tests/FleckAppTests/GemmaDestinationRouterTests.swift Tests/FleckAppTests/DynamicDestinationRouterTests.swift Tests/FleckAppTests/FoundationModelDictationTests.swift Tests/FleckAppTests/DictationCoordinatorTests.swift
git commit -m "feat: preserve ambiguous captures for user routing"
```

---

## Task 5: Bottom-capsule chooser and integrated verification

**Native worker task:** `dictation_capsule_note_chooser`

**Dependency:** Task 4 parent verification and fresh Sol verdict `ship`.

**Files:**

- Modify: `Sources/FleckApp/DictationCapsule.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/DictationAccessibilityTests.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`
- Create: `Tests/FleckAppTests/DictationAmbiguityPresentationTests.swift`
- Modify existing `docs/testing/local-dictation-real-app-checklist.md` if present at execution; otherwise create `docs/testing/local-dictation-routing-checklist.md`.

**Interfaces:**

```swift
struct DictationCapsuleChoice: Equatable, Identifiable {
  let id: UUID?
  let title: String
  let contextHint: String?
}
```

Extend `DictationCapsuleController.render` with defaulted `choices` and `onChoice` parameters, preserving existing callers.

**Required behavior:**

- Show `Saved to Inbox` plus a `Choose note` SwiftUI `Menu` in the existing capsule.
- List at most four destinations followed by `Keep in Inbox`; use bounded hints to distinguish duplicate titles and full accessibility text.
- Keep the capsule panel nonactivating and `canBecomeKey == false`.
- Do not schedule the 1.6-second idle timer while choices remain. Selecting a note or Inbox resumes the normal success timer.
- Starting another capture removes the chooser UI without changing the prior Inbox capture.
- Preserve Reduce Motion, Reduce Transparency, docking, VoiceOver, Undo, Copy, Open History, and Open Destination behavior.
- Do not create another window, activate Fleck, add decorative chooser animation, or add a settings preference.

- [ ] **Step 1: Write red UI/runtime tests** for labels, order, duplicate hints, non-key behavior, timer retention, Inbox choice, note choice, and new-capture dismissal.
- [ ] **Step 2: Run red.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter DictationAmbiguityPresentationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAccessibilityTests
swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
```

- [ ] **Step 3: Implement with the existing capsule and native SwiftUI `Menu`.**
- [ ] **Step 4: Run focused, aggregate, and build verification.**

```bash
swift test --disable-automatic-resolution --no-parallel --filter CachedNoteRoutingIndexTests
swift test --disable-automatic-resolution --no-parallel --filter GemmaDestinationRouterTests
swift test --disable-automatic-resolution --no-parallel --filter AppStateDictationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAmbiguityPresentationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAccessibilityTests
swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
swift test --disable-automatic-resolution --no-parallel
swift build --disable-automatic-resolution
```

Expected: all commands exit `0`; aggregate output contains nonzero executed tests.

- [ ] **Step 5: Add a hands-on checklist** for a clear match, two-note ambiguity and transfer, Keep in Inbox, and deleting a candidate before choice. State that source/build/tests are not packaged-app or real-microphone evidence.
- [ ] **Step 6: Inspect and commit.**

```bash
git diff --check
git status --short
git diff --stat
git add Sources/FleckApp/DictationCapsule.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/DictationAccessibilityTests.swift Tests/FleckAppTests/DictationSettingsTests.swift Tests/FleckAppTests/DictationAmbiguityPresentationTests.swift docs/testing
git commit -m "feat: choose ambiguous dictation destinations"
```

## Final Acceptance Evidence

After all five task-level `ship` verdicts, the primary Sol session reruns the aggregate suite and build from the accumulated branch, inspects every commit and the full `1849519..HEAD` diff, and obtains one final fresh Sol review of the entire stack. Only then may it create a local test package. Push, PR, merge, GitHub mutation, model download, signed-app, two-Mac, or release-admission claims remain outside this plan unless separately authorized and directly observed.
