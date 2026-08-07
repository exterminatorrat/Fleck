# Fleck Local Dictation Dictionary Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Fleck's real device-local personal-dictionary core, deterministic dictionary baseline, protected-term cleanup fallback, and Apple Standard contextual-vocabulary hooks without selecting or integrating a third-party model.

**Architecture:** A dedicated `FleckCore` actor persists a versioned dictionary snapshot separately from notes, preferences, history, and model files. Pure core helpers validate entries, resolve only explicit unambiguous aliases at safe token boundaries, rank a bounded Apple contextual vocabulary, and verify that cleanup preserves protected preferred forms. `DictationCoordinator` inserts the dictionary baseline whenever cleanup fails or loses a protected form. Apple Speech receives a per-capture locale and contextual strings through its existing engine construction seam; production store injection and CRUD UI remain a later coordinated integration task.

**Tech Stack:** Swift 6, Foundation, Swift Testing, Apple Speech framework, SwiftPM macOS 14+ with macOS 26 API availability guards.

## Global Constraints

- Entirely local: no network calls, cloud APIs, accounts, analytics, audio persistence, or transcript/content logging.
- Dictionary data lives under `Application Support/Fleck/PersonalDictionary/dictionary-v1.json`, separate from `AppPreferences`, notes, history, Trash/recovery, and `DictationModels`.
- Existing note, workspace, `LocalStore`, snapshot-writer, recovery/Trash, Settings, `FleckApp`, `AppState`, `NotesPanel`, `Package.swift`, and `Package.resolved` files are out of scope.
- Do not select, download, bundle, or integrate an ASR or cleanup model in this phase.
- Preserve `SpeechEngine` capture lifecycle and current Focused/Smart insertion transactions.
- Old history records without dictionary fields must continue decoding.
- Explicit ambiguous aliases never mutate text. Matching is deterministic and locale-stable.
- Cleanup failure, empty output, or protected-form loss inserts the dictionary baseline; dictionary-resolution failure inserts ASR raw and records that resolution was skipped.
- Apple legacy contextual strings are deduplicated and capped at 100, matching the installed SDK contract. The same deterministic bounded list is used for modern `AnalysisContext`.
- No shared product integration writer may start until Main acknowledges the exact ownership packet.

---

## 1. Objective and success criteria

The deliverable is successful when:

1. Dictionary entries and pending suggestions round-trip through a versioned atomic local store and survive relaunch.
2. JSON and CSV import/export preserve stable IDs, preferred forms, aliases, locale, priority, enabled/origin state, and bounded usage metadata.
3. Only explicit aliases that map to exactly one enabled preferred form replace text; replacements use safe token boundaries and protect the preferred spelling/casing.
4. `DictationCoordinator` distinguishes ASR raw, dictionary baseline, optional cleaned result, and inserted artifact. It falls back exactly as the approved design requires.
5. Apple legacy requests and macOS 26 analyzers can receive a bounded, locale-filtered contextual vocabulary without changing the default empty-context behavior.
6. Focused tests, the full suite, manifest-integrity checks, and the packaged validation gate pass or expose only a documented external dependency-fetch boundary.

## 2. Owned files, interfaces, and constraints

### Create

- `Sources/FleckCore/PersonalDictionary.swift` — versioned entry, usage, suggestion, snapshot, import-policy, and validation types.
- `Sources/FleckCore/PersonalDictionaryStore.swift` — actor CRUD, suggestion approval/dismissal, atomic persistence, and corrupt-input failure behavior.
- `Sources/FleckCore/PersonalDictionaryResolver.swift` — deterministic alias resolution, protected-form validation, and contextual-string ranking.
- `Sources/FleckCore/PersonalDictionaryCodec.swift` — strict JSON snapshot and RFC 4180-compatible CSV import/export.
- `Tests/FleckCoreTests/PersonalDictionaryTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryStoreTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift`
- `Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift`

### Modify

- `Sources/FleckCore/DictationModels.swift` — backward-compatible optional dictionary-baseline/outcome/inserted-artifact history fields.
- `Sources/FleckApp/DictationInterfaces.swift` — dictionary-resolution protocol and immutable per-capture recognition context.
- `Sources/FleckApp/DictationCoordinator.swift` — raw → dictionary baseline → cleanup → protected validation → insertion flow.
- `Sources/FleckApp/AppleSpeechCapture.swift` — locale/context injection into legacy and modern on-device Apple paths.
- `Tests/FleckCoreTests/DictationHistoryStoreTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/DictationAvailabilityTests.swift`

### Required interfaces

```swift
public struct PersonalDictionaryEntry: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var preferredForm: String
  public var aliases: [String]
  public var localeIdentifier: String
  public var isPriority: Bool
  public var isEnabled: Bool
  public var origin: PersonalDictionaryOrigin
  public var usage: PersonalDictionaryUsage
}

public enum PersonalDictionaryOrigin: String, Codable, Sendable {
  case manual, suggested
}

public struct PersonalDictionaryUsage: Codable, Equatable, Sendable {
  public var useCount: Int
  public var lastUsedAt: Date?
}

public struct PersonalDictionarySuggestion: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var preferredForm: String
  public var observedForms: [String]
  public var localeIdentifier: String
  public var observationCount: Int
  public var lastObservedAt: Date
}

public struct PersonalDictionarySnapshot: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public var schemaVersion: Int
  public var entries: [PersonalDictionaryEntry]
  public var suggestions: [PersonalDictionarySuggestion]
}

public actor PersonalDictionaryStore {
  public func snapshot() throws -> PersonalDictionarySnapshot
  public func upsert(_ entry: PersonalDictionaryEntry) throws
  public func delete(id: UUID) throws
  public func setEnabled(_ enabled: Bool, id: UUID) throws
  public func setPriority(_ priority: Bool, id: UUID) throws
  public func recordSuggestion(_ suggestion: PersonalDictionarySuggestion) throws
  public func approveSuggestion(id: UUID) throws -> PersonalDictionaryEntry
  public func dismissSuggestion(id: UUID) throws
  public func replace(with snapshot: PersonalDictionarySnapshot) throws
}

public struct PersonalDictionaryResolution: Equatable, Sendable {
  public let baseline: String
  public let protectedForms: [String]
  public let replacements: Int
}

public enum PersonalDictionaryResolver {
  public static func resolve(
    _ rawTranscript: String,
    entries: [PersonalDictionaryEntry]
  ) throws -> PersonalDictionaryResolution

  public static func cleanupPreserves(
    _ protectedForms: [String],
    in candidate: String
  ) -> Bool

  public static func contextualStrings(
    entries: [PersonalDictionaryEntry],
    locale: Locale,
    limit: Int = 100
  ) -> [String]
}
```

```swift
struct DictationRecognitionContext: Equatable, Sendable {
  let locale: Locale
  let contextualStrings: [String]
}

protocol TranscriptDictionaryResolving: Sendable {
  func resolve(_ rawTranscript: String) async throws
    -> PersonalDictionaryResolution
}

struct PassthroughTranscriptDictionaryResolver: TranscriptDictionaryResolving {
  func resolve(_ rawTranscript: String) async throws
    -> PersonalDictionaryResolution
}
```

The passthrough implementation returns `baseline == rawTranscript`, no protected forms, and zero replacements. It is the default initializer dependency so existing runtime construction remains source-compatible until the coordinated injection task.

## 3. Required implementation and explicit non-goals

### Task 1: Dictionary domain, validation, and deterministic resolver

**Files:** Create `PersonalDictionary.swift`, `PersonalDictionaryResolver.swift`, `PersonalDictionaryTests.swift`, and `PersonalDictionaryResolverTests.swift`.

- [ ] Write failing tests for blank preferred forms, duplicate/blank aliases, unsupported schema versions, bounded nonnegative usage counts, ambiguous aliases, longest-alias-first replacement, punctuation boundaries, identifier casing, Mandarin aliases, disabled entries, protected-form validation, and deterministic context ranking.
- [ ] Run:

```bash
swift test --disable-automatic-resolution --filter 'PersonalDictionaryTests|PersonalDictionaryResolverTests' --no-parallel
```

Expected: fail because the types do not exist.

- [ ] Implement the minimum pure types and algorithms. Validation returns stable field codes and never includes entry text in error descriptions. Alias normalization uses a fixed POSIX locale for Latin case folding; replacement scans the original string and requires non-word boundaries where “word” includes Unicode letters, numbers, and `_`. If two enabled entries claim the same normalized alias, leave every occurrence unchanged. Sort candidate aliases by descending Unicode-scalar count and then stable normalized alias.
- [ ] Context ranking includes enabled entries compatible with the exact locale language code, then orders priority first, use count descending, last-used descending with `nil` last, preferred form in stable scalar order, and ID as final tie-break. Emit each preferred form and explicit alias at most once, stop at `limit`, and return empty for nonpositive limits.
- [ ] Rerun the focused tests and commit:

```bash
git add Sources/FleckCore/PersonalDictionary.swift Sources/FleckCore/PersonalDictionaryResolver.swift Tests/FleckCoreTests/PersonalDictionaryTests.swift Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift
git commit -m 'feat: add personal dictionary resolution core'
```

### Task 2: Versioned atomic store and import/export

**Files:** Create `PersonalDictionaryStore.swift`, `PersonalDictionaryCodec.swift`, `PersonalDictionaryStoreTests.swift`, and `PersonalDictionaryCodecTests.swift`.

- [ ] Write failing tests for missing-store empty load, atomic relaunch round-trip, CRUD, priority/enable changes, suggestion approval/dismissal, corrupt JSON fail-closed behavior, wrong schema rejection, stable sorted output, JSON round-trip, quoted/multiline CSV fields, malformed CSV rejection, duplicate-ID rejection, and replace-with-valid-snapshot.
- [ ] Run:

```bash
swift test --disable-automatic-resolution --filter 'PersonalDictionaryStoreTests|PersonalDictionaryCodecTests' --no-parallel
```

Expected: fail because the store and codec do not exist.

- [ ] Implement one snapshot file at `PersonalDictionary/dictionary-v1.json`. Create the directory only on first mutation. Encode sorted keys, ISO-8601 dates, and stable entry/suggestion ordering. Write with `Data.write(options: .atomic)`. Missing file means an empty current-version snapshot; unreadable, undecodable, invalid, or future-version data throws and is never replaced silently.
- [ ] Implement JSON as the same strict snapshot envelope. Implement CSV with the exact header `id,preferredForm,aliases,localeIdentifier,isPriority,isEnabled,origin,useCount,lastUsedAt`; encode aliases as a JSON array inside the CSV field so commas and multilingual aliases round-trip. CSV import creates no suggestions and rejects missing/extra headers.
- [ ] Rerun the focused tests and commit:

```bash
git add Sources/FleckCore/PersonalDictionaryStore.swift Sources/FleckCore/PersonalDictionaryCodec.swift Tests/FleckCoreTests/PersonalDictionaryStoreTests.swift Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift
git commit -m 'feat: persist and exchange personal dictionary entries'
```

### Task 3: Dictionary baseline and protected cleanup fallback

**Files:** Modify `DictationModels.swift`, `DictationInterfaces.swift`, `DictationCoordinator.swift`, `DictationHistoryStoreTests.swift`, and `DictationCoordinatorTests.swift`.

- [ ] Add failing tests proving:
  - raw transcript remains exact before dictionary mutation;
  - explicit alias replacement becomes the dictionary baseline;
  - cleanup receives the dictionary baseline;
  - successful protected cleanup inserts the cleaned result;
  - cleanup error, empty cleanup, or protected-form loss inserts the baseline;
  - resolver failure inserts raw and records `dictionaryResolutionSkipped`;
  - old history JSON without new optional fields still decodes;
  - history-disabled captures persist no transcript artifact.
- [ ] Run:

```bash
swift test --disable-automatic-resolution --filter 'DictationCoordinatorTests|DictationHistoryStoreTests' --no-parallel
```

Expected: the new tests fail against the raw → cleanup flow.

- [ ] Add optional, backward-compatible history fields:

```swift
public enum DictationTranscriptArtifact: String, Codable, Sendable {
  case asrRaw, dictionaryBaseline, cleanedResult
}

public enum DictationDictionaryOutcome: String, Codable, Sendable {
  case resolved, unchanged, skipped
}

public var dictionaryBaseline: String?
public var dictionaryOutcome: DictationDictionaryOutcome?
public var insertedArtifact: DictationTranscriptArtifact?
```

- [ ] Add a resolver dependency to both coordinator initializers with `PassthroughTranscriptDictionaryResolver()` as the default. After final ASR, persist raw under the existing history contract, resolve the baseline, then clean the baseline. Trim and reject empty cleanup. Accept cleaned output only when every protected form survives; otherwise use the baseline. Resolver failure is the sole ordinary path that uses raw as the insertion fallback. Never include transcript or dictionary content in failure messages.
- [ ] Rerun focused tests and commit:

```bash
git add Sources/FleckCore/DictationModels.swift Sources/FleckApp/DictationInterfaces.swift Sources/FleckApp/DictationCoordinator.swift Tests/FleckCoreTests/DictationHistoryStoreTests.swift Tests/FleckAppTests/DictationCoordinatorTests.swift
git commit -m 'feat: protect dictionary terms through dictation cleanup'
```

### Task 4: Apple Standard contextual vocabulary

**Files:** Modify `AppleSpeechCapture.swift` and `DictationAvailabilityTests.swift`.

- [ ] Add failing tests for stable deduplication/capping, locale propagation, default empty context, legacy request configuration, and modern context construction. Keep framework construction off the main actor.
- [ ] Run:

```bash
swift test --disable-automatic-resolution --filter 'DictationAvailabilityTests' --no-parallel
```

Expected: the new configuration tests fail.

- [ ] Extend only construction-time APIs:

```swift
convenience init(
  recognitionContext: DictationRecognitionContext = .englishDefault,
  microphoneUID: String? = nil,
  permissions: DictationPermissionController = .init(),
  microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void = { _ in }
)
```

Legacy creates `SFSpeechRecognizer(locale: context.locale)`, sets `request.contextualStrings` to the bounded list, keeps `requiresOnDeviceRecognition = true`, and never configures a network fallback. Modern uses the same locale and calls `SpeechAnalyzer.setContext` with `AnalysisContext.contextualStrings[.general]` before analysis. Empty context preserves current behavior. Do not prepare or persist a custom language-model artifact in this phase.
- [ ] Rerun focused tests and commit:

```bash
git add Sources/FleckApp/AppleSpeechCapture.swift Tests/FleckAppTests/DictationAvailabilityTests.swift
git commit -m 'feat: feed personal vocabulary to Apple dictation'
```

### Task 5: Verification and operator contract

**Files:** Modify this plan only if an exact verified command or boundary is wrong; do not add speculative product documentation.

- [ ] Run all focused suites:

```bash
swift test --disable-automatic-resolution --filter 'PersonalDictionary|DictationCoordinatorTests|DictationHistoryStoreTests|DictationAvailabilityTests' --no-parallel
```

- [ ] Run the complete suite:

```bash
swift test --disable-automatic-resolution --no-parallel --quiet
```

- [ ] Run package and repository integrity checks:

```bash
git diff --check
test ! -f Tools/LocalDictationEvaluation/Package.resolved
git diff --exit-code d5e4783cf89277105382b9fa77df21c62126bf62 -- Package.swift Package.resolved
git ls-files -u
test -z "$(git rev-parse --verify -q MERGE_HEAD)"
```

- [ ] Run the packaged macOS gate:

```bash
Scripts/validate-macos.sh
```

Expected: pass. If the isolated candidate-rejection helper cannot fetch the unchanged Swift MCP dependency, capture the exact external error and do not weaken the check.

- [ ] Confirm the diff contains only the owned files, the worktree is clean, and no shared/folder-core file changed.

## 4. Verification commands and expected evidence

Required handoff evidence is:

- red-first output for each task's focused suite;
- final focused suite counts;
- complete root test count;
- packaged validation result and exact external-fetch caveat if any;
- exact base, head, branch, worktree, commit list, and changed-file list;
- root manifest byte-identity and absence of nested resolution files;
- explicit confirmation that no note/workspace/persistence/settings/runtime-construction file changed;
- content-privacy search showing no transcript, dictionary entry, or alias is logged.

## 5. Authority boundaries and required handoff

- Luna/Max owns implementation only after the user approves this plan and Main acknowledges the exact file packet.
- Luna must not edit outside the listed files, push, open a PR, merge, rebase published stacks, or repair unrelated failures.
- The primary Sol/High task inspects the complete diff and reruns verification.
- A fresh Sol/High reviewer must return `ship`. `fix-first` corrections return to the same Luna task and require new primary verification and a new fresh reviewer.
- This plan does not authorize Settings CRUD UI, `FleckApp` store injection, `AppPreferences` language/cleanup settings, `AppState` hooks, `NotesPanel` correction observation, model dependencies, model downloads, ASR selection, cleanup-model selection, or production Enhanced enablement.
- After Phase B core ships, the next independent gates are: Phase C candidate adapters/benchmarks, then Phase D selected runtime/model pack, then a separately coordinated shared integration/UI task.
