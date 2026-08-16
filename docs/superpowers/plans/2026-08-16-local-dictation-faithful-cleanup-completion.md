# Local Dictation Faithful Cleanup Completion Implementation Plan

> **For agentic workers:** REQUIRED ROUTE: Workstream A is a dependency-ordered phase, not one task. Each numbered task below is its own separate user-visible Codex task running GPT-5.6 Luna/Max with a title of `Agent - <singular task>`. Before each task, the primary Sol session is GPT-5.6 Sol at High reasoning; it first runs the orchestration exactness check and confirms the exact native routing roles are available, then writes a bounded five-part packet: objective/success criteria; owned files, interfaces, and constraints; implementation and explicit non-goals; verification commands and expected evidence; and authority boundaries plus the handoff. The Luna/Max task adapts to concurrent edits and preserves unrelated work. The parent Sol task inspects the actual diff and reruns the required checks; a fresh `sol_advisor_sol_reviewer` must return exactly `ship` before the next dependent numbered task. Both `fix-first` and `rethink` return the corrected bounded packet to the same user-visible Luna/Max task; neither switches tasks or adds an implementation route. Terra/native subagents are forbidden. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the deterministic faithful-cleanup validator and bounded incremental
cleaner that accept only the allowlist and return the exact dictionary baseline
for every valid-capture cleanup failure.

**Architecture:** `FaithfulCleanupValidator` consumes the existing
`CleanupLexeme` and `CleanupProtectedSpan` plus the Workstream A Task 0
`PersonalDictionaryResolution` structures. `IncrementalTranscriptCleaner` owns
one synchronous generation start, one bounded result race, one validation
decision, and the exact baseline fallback; it does not change the current
`TranscriptCleaning` finalization path.

**Tech Stack:** Swift 6, Foundation, Swift Concurrency, Swift Testing, and the
existing FleckCore dictionary/cleanup structures. No new package dependency.

## Global Constraints

- The accepted source base is `4212314398853091fa85e7aec18318b9650e8604`, including accepted `CleanupLexeme` and `CleanupProtectedSpan` commits. Preserve unrelated edits and do not widen any task's file ownership.
- Workstream A Task 0 must first port exactly the four final published `898ceae` personal-dictionary files listed below, including the `6bd6df8`, `5148ef1`, and `27f7a44` evolution. Tasks 1 and 2 depend on its ship gate.
- Workstream A creates exactly the four Task 0 FleckCore files plus `FaithfulCleanupValidator.swift`, `FaithfulCleanupValidatorTests.swift`, `IncrementalTranscriptCleaner.swift`, and `IncrementalTranscriptCleanerTests.swift`.
- Task 0 produces the public `PersonalDictionaryResolution` value with exact `baseline: String`, `protectedForms: [String]`, and `replacements: Int`; cleanup receives that data and does not reconstruct dictionary resolution.
- The target cleanup input is the exact dictionary baseline. Dictionary resolution failure before a baseline exists belongs to the later coordinator raw-ASR recovery path and is not converted into a cleanup baseline here.
- Automatic cleanup may change only punctuation, capitalization, whitespace, isolated unambiguous fillers, immediate exact repetition, an explicitly spoken same-tail correction, and short-list formatting without changing list items.
- Names and dictionary forms, numbers and number words, dates and times, prices, units and quantities, recipients and destinations, paths, URLs, email addresses, code, commands, negation, modality, commitments, quotes, and mixed English/Mandarin order are protected meaning.
- Number classification runs over raw `CleanupLexeme` sequences before filler, repetition, or correction recognition; supported English cardinal/ordinal words, scales through trillion, semantically valid full-token digit ordinals, fractions, decimals, percentages, currencies, and unit quantities must keep the exact ordered number signature and detached sign/currency context, while ambiguous or unrecognized numeric/quantity-looking forms fail closed. Only paired, validated ordinal list markers are exempt.
- The validator runs protected-span preservation before allowlist classification. Any protected-meaning violation rejects the candidate.
- The automatic target is at most 80 lexical words. The candidate output is at most input token count plus 32; helper-reported metadata is not authoritative.
- There is one request, one generation attempt, zero automatic retries, no network, no transcript logging, no transcript persistence, and no audio persistence.
- `BoundedCleanupGenerating.start(_:maximumOutputTokens:)` is synchronous and nonblocking. It may create a request/session handle and capture cancellation state, but it performs no I/O, model work, IPC wait, or transcript processing.
- `IncrementalCleanupRequest.deadline` is supplied by the caller. The cleaner never creates a fresh unbounded timeout. The intended warm cleanup allocation is 1,500 ms or the remaining stop-to-insertion budget, whichever is shorter.
- A deadline or helper-request cancellation during a valid capture returns `.baseline(reason:)` after bounded acknowledgement or forced termination. Caller cancellation throws `CancellationError` after the same bounded termination path and publishes no decision.
- A baseline decision contains no alternate text. Its caller uses the unchanged request baseline byte-for-byte.
- No current `TranscriptCleaning`, `DictationCoordinator`, `SettingsView`, `AppState`, `Package.swift`, model manager, runtime, audio, installer, or candidate path is modified.
- No push, PR, merge, GitHub mutation, model download, model-weight write, candidate selection, release admission, or signed-app claim is authorized.
- Automated checks are serialized and offline-safe: `swift test --disable-automatic-resolution --no-parallel [--filter ...]`.

## File Map

### Create

- `Sources/FleckCore/PersonalDictionary.swift` — final published dictionary
  entry/validation types consumed by resolution; no codec or store.
- `Sources/FleckCore/PersonalDictionaryResolver.swift` — final published
  alias resolution, protected occurrences, cleanup preservation, and context
  strings.
- `Tests/FleckCoreTests/PersonalDictionaryTests.swift` — exact core model tests.
- `Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift` — exact
  resolution, ambiguity, protected-form, and contextual-string tests.
- `Sources/FleckApp/FaithfulCleanupValidator.swift` — allowlisted edit operations, protected-span comparison, and validation decisions.
- `Tests/FleckAppTests/FaithfulCleanupValidatorTests.swift` — explicit accept/reject and protected-category evidence.
- `Sources/FleckApp/IncrementalTranscriptCleaner.swift` — request bounds, generation/session contracts, deadline race, cancellation, and baseline decision.
- `Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift` — request count, output bounds, fallback, cancellation, late completion, and privacy evidence.

### Explicitly excluded

- `Sources/FleckApp/CleanupLexeme.swift`
- `Sources/FleckApp/CleanupProtectedSpan.swift`
- `Sources/FleckApp/DictationInterfaces.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckCore/PersonalDictionaryCodec.swift`
- `Sources/FleckCore/PersonalDictionaryStore.swift`
- All dictionary UI, persistence, codec, evaluation, candidate, and adapter files.
- All streaming, runtime, Apple Speech, Settings, model-manager, package, resource, script, and app files.

## Task 0: Restore the personal-dictionary resolution core

**Separate user-visible task title:** `Agent - personal dictionary resolution core`

**Owned files:**

- Create exactly: `Sources/FleckCore/PersonalDictionary.swift`
- Create exactly: `Sources/FleckCore/PersonalDictionaryResolver.swift`
- Test exactly: `Tests/FleckCoreTests/PersonalDictionaryTests.swift`
- Test exactly: `Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift`

**Excluded files:** `Sources/FleckCore/PersonalDictionaryCodec.swift`,
`Sources/FleckCore/PersonalDictionaryStore.swift`, all FleckApp files, all
dictionary UI/persistence files, evaluation tools, candidate adapters, and
every file outside these four paths.

**Dependency and source truth:** The base does not contain this core. Port the
final published versions of exactly these four files from `898ceae`, preserving
the historical `6bd6df8` core and the `5148ef1` and `27f7a44` resolver fixes.
Do not copy the unrelated evaluation-tool or candidate-adapter changes from
that lineage.

**Interfaces consumed:** Foundation `String`, `Locale`, `Date`, `UUID`, and the
existing FleckCore target only.

**Interfaces produced:** `PersonalDictionaryEntry`,
`PersonalDictionaryUsage`, validation values, `PersonalDictionarySnapshot`,
`PersonalDictionaryResolution`, `PersonalDictionaryResolver.resolve(_:entries:)`,
`PersonalDictionaryResolver.cleanupPreserves(_:in:)`, and
`PersonalDictionaryResolver.contextualStrings(entries:locale:limit:)`.

### TDD red

- [ ] **Step 1: Write the four core tests before porting production files.** The
  tests must cover a valid entry, invalid blank/duplicate fields, a unique alias
  replacement, an ambiguous alias that remains raw, repeated protected-form
  occurrences, cleanup preservation counts, and deterministic contextual
  strings.

~~~swift
@Test func resolutionReplacesOnlyAnUnambiguousAlias() throws {
  let entry = PersonalDictionaryEntry(
    preferredForm: "FleckApp",
    aliases: ["fleck app"]
  )
  let result = try PersonalDictionaryResolver.resolve(
    "open fleck app",
    entries: [entry]
  )
  #expect(result.baseline == "open FleckApp")
  #expect(result.protectedForms == ["FleckApp"])
  #expect(result.replacements == 1)
}

@Test func ambiguousAliasRemainsRawAndDoesNotBecomeProtected() throws {
  let first = PersonalDictionaryEntry(preferredForm: "Fleck", aliases: ["flow"])
  let second = PersonalDictionaryEntry(preferredForm: "Flow", aliases: ["flow"])
  let result = try PersonalDictionaryResolver.resolve(
    "open flow",
    entries: [first, second]
  )
  #expect(result.baseline == "open flow")
  #expect(result.replacements == 0)
  #expect(result.protectedForms.isEmpty)
}

@Test func cleanupPreservesEveryProtectedOccurrence() throws {
  let result = try PersonalDictionaryResolver.resolve(
    "Fleck Fleck",
    entries: [PersonalDictionaryEntry(preferredForm: "Fleck", aliases: ["fleck"])]
  )
  #expect(result.protectedForms == ["Fleck", "Fleck"])
  #expect(PersonalDictionaryResolver.cleanupPreserves(
    result.protectedForms,
    in: "Fleck Fleck."
  ))
  #expect(!PersonalDictionaryResolver.cleanupPreserves(
    result.protectedForms,
    in: "Fleck."
  ))
}
~~~

- [ ] **Step 2: Run the serialized red commands.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter PersonalDictionaryTests
swift test --disable-automatic-resolution --no-parallel --filter PersonalDictionaryResolverTests
~~~

Expected failure: the FleckCore test target cannot compile because the four
personal-dictionary files and their public types do not exist on `4212314`.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Port the exact published core files.** Preserve the final
  `898ceae` behavior, including entry validation, stable normalization and
  ordering, locale-aware context strings, safe word boundaries, protected
  occurrence counts, and ambiguous-alias reservation. The essential public
  resolution shape is:

~~~swift
public struct PersonalDictionaryResolution: Equatable, Sendable {
  public let baseline: String
  public let protectedForms: [String]
  public let replacements: Int

  public init(
    baseline: String,
    protectedForms: [String],
    replacements: Int
  ) {
    self.baseline = baseline
    self.protectedForms = protectedForms
    self.replacements = replacements
  }
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
~~~

Do not add `PersonalDictionaryCodec`, `PersonalDictionaryStore`, AppKit/SwiftUI,
transcript logging, evaluation helpers, network code, or candidate routing.

- [ ] **Step 4: Run green and broader core checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter PersonalDictionaryTests
swift test --disable-automatic-resolution --no-parallel --filter PersonalDictionaryResolverTests
swift test --disable-automatic-resolution --no-parallel --filter CleanupLexemeTests
swift test --disable-automatic-resolution --no-parallel --filter CleanupProtectedSpanTests
~~~

Expected: all four commands exit 0; the new resolver is deterministic and the
accepted cleanup token/span base is unchanged.

- [ ] **Step 5: Inspect exact scope and commit.**

~~~bash
git diff --check
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckCore/PersonalDictionary.swift \
    Sources/FleckCore/PersonalDictionaryResolver.swift \
    Tests/FleckCoreTests/PersonalDictionaryTests.swift \
    Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift \
  | sort -u
)"
for path in Sources/FleckCore/PersonalDictionary.swift Sources/FleckCore/PersonalDictionaryResolver.swift Tests/FleckCoreTests/PersonalDictionaryTests.swift Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift; do test "$(git hash-object "$path")" = "$(git rev-parse "898ceae:$path")"; done
git add Sources/FleckCore/PersonalDictionary.swift Sources/FleckCore/PersonalDictionaryResolver.swift Tests/FleckCoreTests/PersonalDictionaryTests.swift Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift
git commit -m "feat: restore personal dictionary resolution core"
~~~

Expected: the blob loop matches all four files to the final `898ceae` versions;
exactly those four Task 0 paths differ; codec/store/UI/evaluation and candidate
files are absent. The parent Sol task reruns all Task 0 checks. The parent also
obtains a fresh Sol `ship` verdict from
`sol_advisor_sol_reviewer` before Task 1 starts.

## Task 1: Implement the faithful edit validator

**Separate user-visible task title:** `Agent - faithful edit validator`

**Dependency:** Begin only after Task 0's four-file blob comparison, parent
rerun, and fresh Sol `ship` verdict.

**Owned files:**

- Create: `Sources/FleckApp/FaithfulCleanupValidator.swift`
- Test: `Tests/FleckAppTests/FaithfulCleanupValidatorTests.swift`

**Excluded files:** Task 0's four FleckCore files, Task 2's cleaner files, all
coordinator, processor, runtime, Apple Speech, Settings, model, package,
resource, script, and every file outside these two paths.

**Interfaces:**

- Consumes: `CleanupLexeme.scan(_:)`, `CleanupProtectedSpan.extract(from:protectedForms:)`, `PersonalDictionaryResolver.cleanupPreserves(_:in:)`, and `PersonalDictionaryResolution`.
- Produces:
  - `CleanupEditOperation`
  - `CleanupValidationFailure`
  - `CleanupValidationDecision`
  - `FaithfulCleanupValidator.validate(candidate:against:)`

### TDD red

- [ ] **Step 1: Write the failing matrix first.** Create the test file with
  these concrete cases; they establish the allowlist and the rejection reason,
  rather than asserting only that a result is nonempty.

```swift
import FleckCore
import Testing

@testable import FleckApp

@Test func faithfulValidatorAcceptsOnlyAllowlistedEdits() {
  let validator = FaithfulCleanupValidator()
  let rows = [
    ("send the report", "Send the report."),
    ("um, send the report", "Send the report."),
    ("send send the report", "Send the report."),
    ("first privacy second speed", "1. Privacy\n2. Speed"),
    ("Use FleckApp today", "Use FleckApp today.")
  ]

  for (baseline, candidate) in rows {
    let decision = validator.validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .accepted(let text, _) = decision else {
      Issue.record("Expected an allowlisted candidate for \(baseline)")
      continue
    }
    #expect(text == candidate)
  }
}

@Test func faithfulValidatorAcceptsExplicitCorrectionOnlyWhenTheTailIsSpoken() {
  let actual = FaithfulCleanupValidator().validate(
    candidate: "The color is blue.",
    against: .init(
      baseline: "The color is red, actually, blue.",
      protectedForms: [],
      replacements: 0
    )
  )
  #expect(actual == .accepted(
    text: "The color is blue.",
    operations: [.selectExplicitCorrection(removed: ["red"], kept: ["blue"])]
  ))

  let nearMiss = FaithfulCleanupValidator().validate(
    candidate: "The color is green.",
    against: .init(
      baseline: "The color is red, actually, blue.",
      protectedForms: [],
      replacements: 0
    )
  )
  #expect(nearMiss == .rejected(.ambiguousCorrection))
}

@Test func faithfulValidatorProtectsNumbersAndNumberWordsBeforeCleanupEdits() {
  let numberWords = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
    "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
    "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
    "billion", "trillion", "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
    "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth",
    "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
    "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth",
    "ninetieth", "hundredth", "thousandth", "millionth", "billionth", "trillionth"
  ]
  let quantityWords = [
    "half", "halves", "quarter", "quarters", "thirds", "fourths", "fifths",
    "eighths", "tenths", "fraction", "fractions", "decimal", "decimals",
    "percent", "percentage", "percentages", "currency", "currencies", "cent",
    "cents", "dollar", "dollars", "euro", "euros",
    "yen", "pound", "pounds", "yuan", "dozen", "dozens", "pair", "pairs",
    "gram", "grams", "kilogram", "kilograms", "meter", "meters", "metre",
    "metres", "kilometer", "kilometers", "kilometre", "kilometres", "mile",
    "miles", "inch", "inches", "foot", "feet", "yard", "yards", "liter",
    "liters", "litre", "litres", "hour", "hours", "minute", "minutes",
    "second", "seconds", "day", "days", "week", "weeks", "month", "months",
    "year", "years"
  ]
  for word in numberWords + quantityWords {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: "send \(word) files.",
        against: .init(
          baseline: "send \(word) files",
          protectedForms: [],
          replacements: 0
        )
      ) == .accepted(text: "send \(word) files.", operations: [.punctuation])
    )
  }
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "send 21st files.",
      against: .init(baseline: "send 21st files", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send 21st files.", operations: [.punctuation])
  )
  #expect(CleanupLexeme.scan("21st").map(\.original) == ["21", "st"])
  for ordinal in ["11th", "12th", "13th", "21st", "22nd", "23rd", "24th"] {
    let decision = FaithfulCleanupValidator().validate(
      candidate: "send \(ordinal) files.",
      against: .init(
        baseline: "send \(ordinal) files",
        protectedForms: [],
        replacements: 0
      )
    )
    guard case .accepted = decision else {
      Issue.record("Semantic ordinal \(ordinal) must remain protected but punctuation-cleanable")
      continue
    }
  }

  let unchangedNumericForms = [
    ("pay $20", "Pay $20."),
    ("progress 20%", "Progress 20%."),
    ("ratio 1/2", "Ratio 1/2."),
    ("meet at 10:30 am", "Meet at 10:30 AM."),
    ("score -3.5", "Score -3.5."),
    ("charge ($20)", "Charge ($20)."),
    ("pay - 20", "Pay - 20."),
    ("pay $ 20", "Pay $ 20."),
    ("pay $$20", "Pay $$20."),
    ("pay $ $20", "Pay $ $20."),
    ("pay $ $ $20", "Pay $ $ $20."),
    ("pay + +20", "Pay + +20."),
    ("pay + + +20", "Pay + + +20.")
  ]
  for (baseline, candidate) in unchangedNumericForms {
    let decision = FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .accepted(let text, _) = decision else {
      Issue.record("Unchanged lexer-supported numeric form must permit punctuation-only cleanup")
      continue
    }
    #expect(text == candidate)
  }
  #expect(CleanupLexeme.scan("pay - 20").map(\.original) == [
    "pay", " ", "-", " ", "20"
  ])
  #expect(CleanupLexeme.scan("pay $ 20").map(\.original) == [
    "pay", " ", "$", " ", "20"
  ])
  #expect(CleanupLexeme.scan("pay $$20").map(\.original) == [
    "pay", " ", "$", "$20"
  ])
  #expect(CleanupLexeme.scan("pay $ $20").map(\.original) == [
    "pay", " ", "$", " ", "$20"
  ])
  #expect(CleanupLexeme.scan("pay + +20").map(\.original) == [
    "pay", " ", "+", " ", "+20"
  ])
  #expect(CleanupLexeme.scan("pay + + +20").map(\.original) == [
    "pay", " ", "+", " ", "+", " ", "+20"
  ])

  let validListWithInterMarkerPunctuation = FaithfulCleanupValidator().validate(
    candidate: "1. buy 20 apples;\n2. buy 20 oranges.",
    against: .init(
      baseline: "first buy 20 apples, second buy 20 oranges",
      protectedForms: [],
      replacements: 0
    )
  )
  guard case .accepted(let text, _) = validListWithInterMarkerPunctuation else {
    Issue.record("Validated markers must not exempt unchanged in-item quantities")
    return
  }
  #expect(text == "1. buy 20 apples;\n2. buy 20 oranges.")

  let rejected: [(String, String)] = [
    ("twenty twenty", "twenty"),
    ("twenty actually thirty", "thirty"),
    ("trillion trillion", "trillion"),
    ("hundredth hundredth", "hundredth"),
    ("half half", "half"),
    ("trillionish trillionish", "trillionish"),
    ("send 21stx 21stx", "send 21stx"),
    ("send 1st2 actually 1st2", "send 1st2"),
    ("send 11st files", "Send 11st files."),
    ("send 21th files", "Send 21th files."),
    ("send 21stx files", "Send 21stx files."),
    ("pay - 20", "Pay 20."),
    ("pay 20-", "Pay 20."),
    ("pay $ 20", "Pay 20."),
    ("pay $$20", "Pay $20."),
    ("pay $ $20", "Pay $20."),
    ("pay $ $ $20", "Pay $ $20."),
    ("pay + 20", "Pay 20."),
    ("pay ++20", "Pay +20."),
    ("pay + +20", "Pay +20."),
    ("pay + + +20", "Pay + +20."),
    ("pay - -20", "Pay -20."),
    ("pay 20-", "Pay 20-."),
    ("send ($20", "Send ($20."),
    ("send 20)", "Send 20)."),
    ("send 10:", "Send 10:."),
    ("send 1/", "Send 1/."),
    ("send 20%%", "Send 20%%."),
    ("send 99:99am", "Send 99:99am."),
    ("send 1/0", "Send 1/0."),
    ("send 20 files", "send 10 files"),
    ("send twenty-two files", "send 22 files"),
    ("send 20th files", "send 20 files"),
    ("pay $20", "pay $21"),
    ("progress 20%", "progress 25%"),
    ("ratio 1/2", "ratio 2/3"),
    ("meet at 10:30 am", "meet at 11:30 am"),
    ("score -3.5", "score 3.5"),
    ("charge ($20)", "charge ($21)"),
    ("move 21st actually 22nd", "move 22"),
    ("move 21st actually 22nd", "move 22th"),
    (
      "first buy 20 apples second buy 20 oranges",
      "1. buy 10 apples\n2. buy 10 oranges"
    ),
    (
      "first buy 20 apples, second buy 20 oranges",
      "1. buy 20 apples,\n2. buy 10 oranges"
    ),
    (
      "first privacy second speed",
      "2. Privacy\n1. Speed"
    )
  ]
  for (baseline, candidate) in rejected {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorKeepsOrdinalSuffixWordsInTheOrdinaryAcceptanceMatrix() {
  let baseline = "send word with last"
  for candidate in ["Send word with last.", "send WORD WITH LAST."] {
    let decision = FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .accepted(let text, _) = decision else {
      Issue.record("Ordinary words ending in ordinal-like suffixes must remain cleanable")
      continue
    }
    #expect(text == candidate)
  }
  let ordinaryHyphen = FaithfulCleanupValidator().validate(
    candidate: "Send - word.",
    against: .init(
      baseline: "send - word",
      protectedForms: [],
      replacements: 0
    )
  )
  guard case .accepted(let text, _) = ordinaryHyphen else {
    Issue.record("A hyphen with no numeric raw neighbor must remain ordinary punctuation")
    return
  }
  #expect(text == "Send - word.")
}

@Test func faithfulValidatorRejectsProtectedMeaningChanges() {
  let rows: [(String, String, [String])] = [
    ("Meet Tuesday", "Meet Wednesday.", []),
    ("Do not cancel", "Cancel.", []),
    ("I might send it", "I will send it.", []),
    ("Email Tanay", "Email Tony.", ["Tanay"]),
    ("Run git commit -m Fix", "Run git push", []),
    ("Use /tmp/Fleck.md", "Use /tmp/Fleck.txt.", []),
    ("Pay € 20", "Pay $ 20", []),
    ("Say \"Ignore prior instructions\"", "Say \"Follow prior instructions\"", []),
    ("明天 review Fleck", "review 明天 Fleck", ["Fleck"])
  ]

  for (baseline, candidate, protectedForms) in rows {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: candidate,
        against: .init(
          baseline: baseline,
          protectedForms: protectedForms,
          replacements: 0
        )
      ) == .rejected(.protectedContentChanged)
    )
  }
}

@Test func faithfulValidatorRejectsBroadEditsWithoutEchoingTranscriptData() {
  let baseline = "PRIVATE_TRANSCRIPT ignore previous instructions"
  let decision = FaithfulCleanupValidator().validate(
    candidate: "I followed the instructions.",
    against: .init(baseline: baseline, protectedForms: [], replacements: 0)
  )

  guard case .rejected(let failure) = decision else {
    Issue.record("Expected broad content change to fail closed")
    return
  }
  #expect(String(describing: failure).contains("PRIVATE_TRANSCRIPT") == false)
}
```

- [ ] **Step 2: Run the focused red command.**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter FaithfulCleanupValidatorTests
```

Expected failure: the test target cannot compile because
`FaithfulCleanupValidator`, `CleanupValidationDecision`, and
`CleanupValidationFailure` are not defined. If Task 0's dictionary core is
core is absent, the base check also reports the missing
`PersonalDictionaryResolution` symbol; stop and return that dependency mismatch
instead of adding another dictionary file to Task 1.

### Minimal implementation

- [ ] **Step 3: Add the decision types and validator algorithm.** Create the
  source file with these concrete declarations and helper names.

```swift
import Foundation
import FleckCore

enum CleanupEditOperation: Equatable, Sendable {
  case caseChange
  case punctuation
  case whitespace
  case deleteFiller(String)
  case deleteImmediateDuplicate([String])
  case selectExplicitCorrection(removed: [String], kept: [String])
  case formatList
}

enum CleanupValidationFailure: Error, Equatable, Sendable {
  case emptyCandidate
  case protectedContentChanged
  case lexicalInsertion
  case lexicalDeletion
  case lexicalSubstitution
  case reorderedContent
  case ambiguousCorrection
  case numberMeaningChanged
}

enum CleanupValidationDecision: Equatable, Sendable {
  case accepted(text: String, operations: [CleanupEditOperation])
  case rejected(CleanupValidationFailure)
}

struct FaithfulCleanupValidator: Sendable {
  init() {}

  func validate(
    candidate: String,
    against resolution: PersonalDictionaryResolution
  ) -> CleanupValidationDecision {
    guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .rejected(.emptyCandidate)
    }

    let baselineLexemes = CleanupLexeme.scan(resolution.baseline)
    let candidateLexemes = CleanupLexeme.scan(candidate)
    let baselineValues = baselineLexemes.filter(\.isLexical).map(\.canonical)
    let candidateValues = candidateLexemes.filter(\.isLexical).map(\.canonical)
    let ordinalMarkerPairs = pairedOrdinalMarkersAreOnlyDifference(
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes
    )

    guard numberMeaningIsPreserved(
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes
    )
      || ordinalMarkerPairs != nil else {
      return .rejected(.numberMeaningChanged)
    }

    guard PersonalDictionaryResolver.cleanupPreserves(
      resolution.protectedForms,
      in: candidate
    ) else { return .rejected(.protectedContentChanged) }

    let baselineSpans = CleanupProtectedSpan.extract(
      from: resolution.baseline,
      protectedForms: resolution.protectedForms
    )
    let candidateSpans = CleanupProtectedSpan.extract(
      from: candidate,
      protectedForms: resolution.protectedForms
    )
    guard protectedSpansMatch(
      baselineSpans,
      candidateSpans,
      ordinalMarkerPairs: ordinalMarkerPairs
    ) else { return .rejected(.protectedContentChanged) }

    if baselineValues == candidateValues {
      return .accepted(
        text: candidate,
        operations: equalLexicalOperations(baselineLexemes, candidateLexemes)
      )
    }
    if let filler = isolatedFillerRemoval(
      baselineLexemes, candidateLexemes, baselineValues, candidateValues, baselineSpans
    ) {
      return .accepted(text: candidate, operations: [.deleteFiller(filler)])
    }
    if let duplicate = immediateDuplicateRemoval(
      baselineLexemes, candidateValues, baselineValues, baselineSpans
    ) {
      return .accepted(text: candidate, operations: [.deleteImmediateDuplicate(duplicate)])
    }
    if let correction = explicitCorrection(
      baselineLexemes, candidateValues, baselineValues
    ) {
      return .accepted(
        text: candidate,
        operations: [.selectExplicitCorrection(
          removed: correction.removed,
          kept: correction.kept
        )]
      )
    }
    if hasCorrectionMarker(baselineValues) {
      return .rejected(.ambiguousCorrection)
    }
    if let ordinalMarkerPairs,
       isShortListFormatting(
         baselineLexemes,
         candidateLexemes,
         ordinalMarkerPairs: ordinalMarkerPairs
       ) {
      return .accepted(text: candidate, operations: [.formatList])
    }
    if candidateValues.count > baselineValues.count {
      return .rejected(.lexicalInsertion)
    }
    if candidateValues.count < baselineValues.count {
      return .rejected(.lexicalDeletion)
    }
    if candidateValues.sorted() == baselineValues.sorted() {
      return .rejected(.reorderedContent)
    }
    return .rejected(.lexicalSubstitution)
  }

  private static let fillerWords: Set<String> = ["um", "uh", "erm", "呃", "嗯"]
  private static let ordinalWords: Set<String> = ["first", "second", "third", "fourth", "fifth"]
  private static let numberWords: Set<String> = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
    "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
    "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion",
    "trillion", "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
    "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth",
    "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
    "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth",
    "ninetieth", "hundredth", "thousandth", "millionth", "billionth", "trillionth"
  ]
  private static let quantityWords: Set<String> = [
    "half", "halves", "quarter", "quarters", "thirds", "fourths", "fifths",
    "eighths", "tenths", "fraction", "fractions", "decimal", "decimals",
    "percent", "percentage", "percentages", "currency", "currencies", "cent",
    "cents", "dollar", "dollars", "euro", "euros",
    "yen", "pound", "pounds", "yuan", "dozen", "dozens", "pair", "pairs",
    "gram", "grams", "kilogram", "kilograms", "meter", "meters", "metre",
    "metres", "kilometer", "kilometers", "kilometre", "kilometres", "mile",
    "miles", "inch", "inches", "foot", "feet", "yard", "yards", "liter",
    "liters", "litre", "litres", "hour", "hours", "minute", "minutes",
    "second", "seconds", "day", "days", "week", "weeks", "month", "months",
    "year", "years"
  ]
  private static let numericLookingRoots: Set<String> = [
    "hundred", "thousand", "million", "billion", "trillion", "percent",
    "fraction", "decimal", "half", "quarter", "cent", "dollar", "euro",
    "currency",
    "yen", "pound", "yuan", "dozen", "gram", "kilo", "meter", "metre",
    "liter", "litre", "mile", "inch", "foot", "yard"
  ]
  private static let numericLookingSuffixes: [String] = ["ish", "like"]
  private static let correctionMarkers: Set<String> = ["actually", "sorry", "no"]

  private enum NumberClassification: Equatable {
    case none
    case digit(String)
    case digitOrdinal(String)
    case word(String)
    case quantity(String)
    case ambiguous
  }

  private struct PairedOrdinalMarkerIndices: Equatable {
    let baselineRawRanges: [Range<Int>]
    let candidateRawRanges: [Range<Int>]
    let candidateNumberRawRanges: [Range<Int>]
  }

  private struct NumericRawContext: Equatable {
    let detachedLeadingAffixes: [String]
    let detachedTrailingAffixes: [String]

    static let none = Self(
      detachedLeadingAffixes: [],
      detachedTrailingAffixes: []
    )
  }

  private struct NumberSemanticSignature: Equatable {
    let classification: NumberClassification
    let rawContext: NumericRawContext
  }

  private struct NumberSignature: Equatable {
    let rawRange: Range<Int>
    let classification: NumberClassification
    let rawContext: NumericRawContext

    init(
      rawRange: Range<Int>,
      classification: NumberClassification,
      rawContext: NumericRawContext = .none
    ) {
      self.rawRange = rawRange
      self.classification = classification
      self.rawContext = rawContext
    }

    var semantic: NumberSemanticSignature {
      .init(classification: classification, rawContext: rawContext)
    }
  }

  private static let ordinalMarkerNumbers: [String: Int] = [
    "first": 1,
    "second": 2,
    "third": 3,
    "fourth": 4,
    "fifth": 5
  ]

  private static func numberMeaningIsPreserved(
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme]
  ) -> Bool {
    let baseline = numberSignatures(from: baselineLexemes)
    let candidate = numberSignatures(from: candidateLexemes)
    guard !baseline.contains(where: { $0.classification == .ambiguous }),
          !candidate.contains(where: { $0.classification == .ambiguous }) else {
      return false
    }
    return baseline
      .filter { $0.classification != .none }
      .map(\.semantic)
      == candidate
      .filter { $0.classification != .none }
      .map(\.semantic)
  }

  private static func numberSignatures(from lexemes: [CleanupLexeme]) -> [NumberSignature] {
    var signatures: [NumberSignature] = []
    var consumedIndices = Set<Int>()
    var index = 0
    while index < lexemes.count {
      guard lexemes[index].kind == .number else {
        index += 1
        continue
      }

      let value = lexemes[index].canonical.lowercased()
      guard let rawContext = numericRawContext(at: index, in: lexemes) else {
        signatures.append(.init(
          rawRange: index..<(index + 1),
          classification: .ambiguous
        ))
        consumedIndices.insert(index)
        index += 1
        continue
      }
      if index + 1 < lexemes.count, lexemes[index + 1].kind == .word {
        let suffix = lexemes[index + 1].canonical.lowercased()
        if ["st", "nd", "rd", "th"].contains(suffix) {
          let range = index..<(index + 2)
          let classification = validOrdinalSuffix(for: value, suffix: suffix)
            ? .digitOrdinal(value + suffix)
            : .ambiguous
          signatures.append(.init(
            rawRange: range,
            classification: classification,
            rawContext: rawContext
          ))
          consumedIndices.formUnion(range)
          index += 2
          continue
        }
        if unitWords.contains(suffix) {
          signatures.append(.init(
            rawRange: index..<(index + 2),
            classification: .quantity(value + suffix),
            rawContext: rawContext
          ))
          consumedIndices.formUnion(index..<(index + 2))
          index += 2
          continue
        }
        if suffix.hasPrefix("st") || suffix.hasPrefix("nd")
            || suffix.hasPrefix("rd") || suffix.hasPrefix("th") {
          signatures.append(.init(
            rawRange: index..<(index + 2),
            classification: .ambiguous,
            rawContext: rawContext
          ))
          consumedIndices.formUnion(index..<(index + 2))
          index += 2
          continue
        }
        // A digit immediately followed by letters is not a safe punctuation-only
        // form unless the bounded unit/ordinal cases above recognized it.
        signatures.append(.init(
          rawRange: index..<(index + 2),
          classification: .ambiguous,
          rawContext: rawContext
        ))
        consumedIndices.formUnion(index..<(index + 2))
        index += 2
        continue
      }

      if index + 2 < lexemes.count,
         lexemes[index + 1].kind == .whitespace,
         lexemes[index + 2].kind == .word,
         ["am", "pm"].contains(lexemes[index + 2].canonical.lowercased()),
         value.contains(":") {
        let time = value + lexemes[index + 2].canonical.lowercased()
        signatures.append(.init(
          rawRange: index..<(index + 3),
          classification: classifyNumber(time),
          rawContext: rawContext
        ))
        consumedIndices.formUnion(index..<(index + 3))
        index += 3
        continue
      }

      signatures.append(.init(
        rawRange: index..<(index + 1),
        classification: classifyNumber(value),
        rawContext: rawContext
      ))
      consumedIndices.insert(index)
      index += 1
    }

    for index in lexemes.indices where lexemes[index].kind == .word && !consumedIndices.contains(index) {
      if classifyNumber(lexemes[index].canonical) != .none {
        signatures.append(.init(
          rawRange: index..<(index + 1),
          classification: classifyNumber(lexemes[index].canonical)
        ))
      }
    }
    return signatures.sorted { $0.rawRange.lowerBound < $1.rawRange.lowerBound }
  }

  private static let unitWords: Set<String> = [
    "ms", "s", "sec", "secs", "min", "mins", "hour", "hours", "mm", "cm",
    "m", "km", "g", "kg", "mg", "oz", "lb", "lbs", "ml", "l", "gb", "mb",
    "tb", "c", "°c"
  ]

  private static func validOrdinalSuffix(for digits: String, suffix: String) -> Bool {
    guard let integer = Int(digits), ["st", "nd", "rd", "th"].contains(suffix) else {
      return false
    }
    let expected: String
    let lastTwo = integer % 100
    if (11...13).contains(lastTwo) {
      expected = "th"
    } else {
      switch integer % 10 {
      case 1: expected = "st"
      case 2: expected = "nd"
      case 3: expected = "rd"
      default: expected = "th"
      }
    }
    return suffix == expected
  }

  private static func numericRawContext(
    at index: Int,
    in lexemes: [CleanupLexeme]
  ) -> NumericRawContext? {
    let original = lexemes[index].original
    let openCount = original.filter { $0 == "(" }.count
    let closeCount = original.filter { $0 == ")" }.count
    guard openCount == closeCount else { return nil }
    if openCount > 0 {
      guard original.first == "(", original.last == ")" else { return nil }
    }

    func adjacentNonWhitespace(_ step: Int) -> CleanupLexeme? {
      var cursor = index + step
      while lexemes.indices.contains(cursor) {
        if lexemes[cursor].kind != .whitespace { return lexemes[cursor] }
        cursor += step
      }
      return nil
    }

    func affixRun(_ step: Int) -> [String] {
      var cursor = index + step
      var affixes: [String] = []
      while lexemes.indices.contains(cursor) {
        if lexemes[cursor].kind == .whitespace {
          cursor += step
          continue
        }
        guard isNumericAffixPunctuation(lexemes[cursor]) else { break }
        affixes.append(lexemes[cursor].original)
        cursor += step
      }
      return step < 0 ? Array(affixes.reversed()) : affixes
    }

    let previous = adjacentNonWhitespace(-1)
    let next = adjacentNonWhitespace(1)
    if let previous,
       previous.original == "(", !original.hasPrefix("(") {
      return nil
    }
    if let next {
      if next.original == ")" && !original.hasSuffix(")") { return nil }
      if ["/", ":", "%"].contains(next.original) { return nil }
      if original.hasSuffix("%") && next.original == "%" { return nil }
    }
    let detachedLeadingAffixes = affixRun(-1)
    let detachedTrailingAffixes = affixRun(1)
    guard detachedTrailingAffixes.isEmpty else {
      return nil
    }
    return .init(
      detachedLeadingAffixes: detachedLeadingAffixes,
      detachedTrailingAffixes: detachedTrailingAffixes
    )
  }

  private static func isNumericAffixPunctuation(_ lexeme: CleanupLexeme) -> Bool {
    guard lexeme.kind == .punctuation,
          lexeme.original.count == 1,
          let character = lexeme.original.first else {
      return false
    }
    return isNumericSign(character) || isCurrencySymbol(character)
  }

  private static func isNumericSign(_ character: Character) -> Bool {
    character == "+" || character == "-" || character == "−"
  }

  private static func isCurrencySymbol(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      $0.properties.generalCategory == .currencySymbol
    }
  }

  private static func isSupportedNumericForm(_ canonical: String) -> Bool {
    if canonical.range(of: #"^[+-]?\d+/\d+$"#, options: .regularExpression) != nil {
      let parts = canonical.split(separator: "/")
      guard parts.count == 2, let denominator = Int(parts[1]), denominator > 0 else {
        return false
      }
    }
    let meridiem = canonical.hasSuffix("am") || canonical.hasSuffix("pm")
    let hasColon = canonical.contains(":")
    guard !hasColon && !meridiem
      || canonical.range(of: #"^\d{1,2}(?::\d{2})(?:am|pm)?$"#, options: .regularExpression) != nil
      || canonical.range(of: #"^\d{1,2}(?:am|pm)$"#, options: .regularExpression) != nil else {
      return false
    }
    guard hasColon || meridiem else { return true }
    let core = meridiem ? String(canonical.dropLast(2)) : canonical
    let parts = core.split(separator: ":")
    if parts.count == 1 {
      guard meridiem, let hour = Int(parts[0]) else { return false }
      return (1...12).contains(hour)
    }
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (meridiem ? (1...12).contains(hour) : (0...23).contains(hour)),
          (0...59).contains(minute) else {
      return false
    }
    return true
  }

  private static func classifyNumber(_ value: String) -> NumberClassification {
    let canonical = value.lowercased()
    if numberWords.contains(canonical) {
      return .word(canonical)
    }
    if quantityWords.contains(canonical) {
      return .quantity(canonical)
    }
    if canonical.contains("-") {
      let parts = canonical.split(separator: "-").map(String.init)
      if parts.allSatisfy({ numberWords.contains($0) || quantityWords.contains($0) }) {
        return .word(canonical)
      }
      if parts.contains(where: { numberWords.contains($0) || quantityWords.contains($0) }) {
        return .ambiguous
      }
    }
    if canonical.range(of: #"^[0-9]+(?:st|nd|rd|th)$"#, options: .regularExpression) != nil {
      let suffix = String(canonical.suffix(2))
      let digits = String(canonical.dropLast(2))
      return validOrdinalSuffix(for: digits, suffix: suffix)
        ? .digitOrdinal(canonical)
        : .ambiguous
    }
    let supportedDigitPatterns = [
      #"^[+-]?\(?[$€£¥]?\d+(?:\.\d+)?[$€£¥]?\)?$"#,
      #"^[+-]?\d+(?:\.\d+)?%$"#,
      #"^[+-]?\d+/\d+$"#,
      #"^\d{1,2}(?::\d{2})?(?:am|pm)$"#,
      #"^\d{1,2}:\d{2}$"#
    ]
    if supportedDigitPatterns.contains(where: {
      canonical.range(of: $0, options: .regularExpression) != nil
    }) {
      return isSupportedNumericForm(canonical) ? .digit(canonical) : .ambiguous
    }
    if canonical.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains) {
      return .ambiguous
    }
    if isBoundedNumericLookingForm(canonical) {
      return .ambiguous
    }
    return .none
  }

  private static func isBoundedNumericLookingForm(_ canonical: String) -> Bool {
    guard canonical.allSatisfy({ $0.isLetter }) else { return false }
    return numericLookingSuffixes.contains { suffix in
      guard canonical.hasSuffix(suffix) else { return false }
      let root = String(canonical.dropLast(suffix.count))
      return numericLookingRoots.contains(root)
    }
  }

  private static func pairedOrdinalMarkersAreOnlyDifference(
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme]
  ) -> PairedOrdinalMarkerIndices? {
    guard let markerRanges = validatedShortListMarkerRanges(
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes
    ) else {
      return nil
    }
    let baselineMarkers = markerRanges.baselineRawRanges
    let candidateMarkers = markerRanges.candidateRawRanges
    guard baselineMarkers.count >= 2,
          baselineMarkers.count == candidateMarkers.count else {
      return nil
    }
    guard zip(baselineMarkers, candidateMarkers).enumerated().allSatisfy({ offset, pair in
      guard let baselineNumber = ordinalMarkerNumbers[
              baselineLexemes[pair.0.lowerBound].canonical
            ],
            let candidateNumber = isNumericListMarker(
              candidateLexemes[pair.1.lowerBound].canonical
            ) else {
        return false
      }
      return baselineNumber == offset + 1 && candidateNumber == offset + 1
    }) else {
      return nil
    }
    let baselineRemainder = removingRawRanges(baselineMarkers, from: baselineLexemes)
    let candidateRemainder = removingRawRanges(candidateMarkers, from: candidateLexemes)
    guard numberMeaningIsPreserved(
      baselineLexemes: baselineRemainder,
      candidateLexemes: candidateRemainder
    ) else {
      return nil
    }
    return .init(
      baselineRawRanges: baselineMarkers,
      candidateRawRanges: candidateMarkers,
      candidateNumberRawRanges: markerRanges.candidateNumberRawRanges
    )
  }

  private static func removingRawRanges(
    _ ranges: [Range<Int>],
    from lexemes: [CleanupLexeme]
  ) -> [CleanupLexeme] {
    lexemes.enumerated()
      .filter { index, _ in !ranges.contains { $0.contains(index) } }
      .map(\.element)
  }

  private static func isNumericListMarker(_ value: String) -> Int? {
    guard let number = Int(value) else { return nil }
    return (1...5).contains(number) ? number : nil
  }

  private static func protectedSpansMatch(
    _ baseline: [CleanupProtectedSpan],
    _ candidate: [CleanupProtectedSpan],
    ordinalMarkerPairs: PairedOrdinalMarkerIndices?
  ) -> Bool {
    let exemptCandidateNumbers = ordinalMarkerPairs?.candidateNumberRawRanges ?? []
    let comparableCandidate = candidate.filter { span in
      guard span.category == .number else { return true }
      return !exemptCandidateNumbers.contains(span.lexemeRange)
    }
    let stableOrder: (CleanupProtectedSpan, CleanupProtectedSpan) -> Bool = { left, right in
      if left.category.rawValue != right.category.rawValue {
        return left.category.rawValue < right.category.rawValue
      }
      if left.lexemeRange.lowerBound != right.lexemeRange.lowerBound {
        return left.lexemeRange.lowerBound < right.lexemeRange.lowerBound
      }
      return left.lexemeRange.upperBound < right.lexemeRange.upperBound
    }
    let orderedBaseline = baseline.sorted(by: stableOrder)
    let orderedCandidate = comparableCandidate.sorted(by: stableOrder)
    guard orderedBaseline.count == orderedCandidate.count else { return false }
    return zip(orderedBaseline, orderedCandidate).allSatisfy { baselineSpan, candidateSpan in
      baselineSpan.category == candidateSpan.category
        && baselineSpan.canonicalLexemes == candidateSpan.canonicalLexemes
    }
  }

  private static func equalLexicalOperations(
    _ baseline: [CleanupLexeme],
    _ candidate: [CleanupLexeme]
  ) -> [CleanupEditOperation]

  private static func isolatedFillerRemoval(
    _ baseline: [CleanupLexeme],
    _ candidate: [CleanupLexeme],
    _ baselineValues: [String],
    _ candidateValues: [String],
    _ spans: [CleanupProtectedSpan]
  ) -> String?

  private static func immediateDuplicateRemoval(
    _ baseline: [CleanupLexeme],
    _ candidateValues: [String],
    _ baselineValues: [String],
    _ spans: [CleanupProtectedSpan]
  ) -> [String]?

  private static func explicitCorrection(
    _ baseline: [CleanupLexeme],
    _ candidateValues: [String],
    _ baselineValues: [String]
  ) -> (removed: [String], kept: [String])?

  private static func hasCorrectionMarker(_ values: [String]) -> Bool

  private static func isShortListFormatting(
    _ baseline: [CleanupLexeme],
    _ candidate: [CleanupLexeme],
    ordinalMarkerPairs: PairedOrdinalMarkerIndices
  ) -> Bool

  private static func validatedShortListMarkerRanges(
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme]
  ) -> (
    baselineRawRanges: [Range<Int>],
    candidateRawRanges: [Range<Int>],
    candidateNumberRawRanges: [Range<Int>]
  )? {
    let baseline = baselineLexemes.indices.compactMap { index -> Range<Int>? in
      guard baselineLexemes[index].kind == .word,
            ordinalMarkerNumbers[baselineLexemes[index].canonical] != nil else {
        return nil
      }
      return index..<(index + 1)
    }
    let candidate = candidateLexemes.indices.compactMap { index -> (Range<Int>, Range<Int>)? in
      guard candidateLexemes[index].kind == .number,
            isNumericListMarker(candidateLexemes[index].canonical) != nil,
            index + 1 < candidateLexemes.count,
            candidateLexemes[index + 1].original == "." else {
        return nil
      }
      return (index..<(index + 2), index..<(index + 1))
    }
    guard baseline.count == candidate.count, baseline.count >= 2 else { return nil }
    return (
      baselineRawRanges: baseline,
      candidateRawRanges: candidate.map(\.0),
      candidateNumberRawRanges: candidate.map(\.1)
    )
  }
}
```

Implement `protectedSpansMatch` by first filtering only candidate `.number`
spans whose exact raw `lexemeRange` is in
`ordinalMarkerPairs.candidateNumberRawRanges`; no price, quantity, or other
number span is exempt. Sort the remaining baseline and candidate spans by
category raw value, then raw lower/upper bounds, and compare every category and
canonical lexeme occurrence with equal counts. This makes the baseline ordinal
words (`first`/`second`) comparable to a candidate after its validated digit
marker spans are removed without zipping incompatible original arrays.
`isShortListFormatting` is only a presentation
predicate; its sole numeric exception is
`pairedOrdinalMarkersAreOnlyDifference`, which first validates the exact ordered
mapping `first -> 1`, `second -> 2`, `third -> 3`, `fourth -> 4`, and
`fifth -> 5` at the corresponding item positions. Its
`validatedShortListMarkerRanges` helper scans the raw `CleanupLexeme` array and
returns full raw ranges for the baseline word and candidate number-plus-period,
plus a separate raw range for each candidate number lexeme. A quantity `1` or
`2` inside an item is not returned because it is not immediately followed by the
marker period. The paired helper validates those raw ranges, removes only the
full marker ranges for its remainder comparison, and passes the exact candidate
number ranges to `protectedSpansMatch`; only those exact candidate ordinal digit
spans are exempt. It must never ignore a quantity inside a list item. Thus a
baseline with ordinal items
and quantity `20` is rejected when a numbered candidate uses quantity `10`, and
swapped markers (`first privacy second speed` to `2. Privacy / 1. Speed`) reject.
Ignore only numeric list markers introduced by a valid ordinal list; never ignore
a number inside a normal sentence. Implement the four edit recognizers with
`CleanupLexeme` indices, not string replacement. A filler is removable only when
it is one of the five listed words, isolated by punctuation/boundaries, and not
inside a protected quote/span. A duplicate is adjacent, exact after canonical
comparison, and not numeric/protected. Before those recognizers run,
`numberMeaningIsPreserved` builds ordered signatures from raw lexeme sequences,
not from a filtered string list. A contiguous `.number` plus `.word` suffix is
one signature only for a semantically valid full-token ordinal; `11th`, `12th`,
`13th`, `21st`, and `22nd` pass, while `11st`, `21th`, and `21stx` become
ambiguous and fail closed. A number followed by an allowlisted unit is likewise
one bounded quantity signature. A number, optional whitespace, and `am`/`pm`
form one time signature. The remaining single `.number` forms use exact
normalized signatures for currency, percentage, fraction, time, signed,
parenthesized, and decimal lexemes (`$20`, `20%`, `1/2`, `10:30`, `10:30am`,
`-3.5`, and `($20)`); unsupported digit-bearing sequences remain ambiguous.
Before classifying any number, `numericRawContext(at:in:)` checks balanced
parentheses, rejects a number adjacent to a dangling `)`, `/`, `:`, `%`, or
trailing sign/currency, and rejects incomplete affixes even when
`CleanupLexeme` split the punctuation into separate raw lexemes. It skips
whitespace only while walking the contiguous raw affix run: every one-character
`+`, `-`, `−`, or currency symbol before a number is recorded in source order
in `NumericRawContext`; any such run after a number is ambiguous. The number's
semantic signature compares both the classified numeric form and the complete
context, so removing a detached sign/currency or one member of a doubled or
split affix cannot compare equal. Hyphen punctuation elsewhere, with no number
as a raw neighbor, is not treated as numeric context. Complete supported forms then
validate fraction denominators and clock ranges, so `99:99am` and `1/0` are
ambiguous. Therefore `($20`, `20)`, `10:`, `1/`, and `20%%` fail closed even
when their numeric fragments individually match a permissive pattern. Exact
unchanged contexts such as `pay - 20`, `pay $ 20`, and `pay $$20` remain
punctuation-cleanable; candidates that remove those contexts reject.
It requires the ordered number signature to remain identical;
ordinary words such as `send`, `word`, `with`, and `last` remain `.none`, while
malformed digit/suffix forms remain ambiguous and reject fail-closed rather than
reaching duplicate or correction deletion. Avoid broad substring hints for
numeric roots; numeric-looking heuristics use exact vocabulary or bounded token
patterns. Thus neither filler removal, immediate repetition, nor
explicit correction can delete or replace a number word; `twenty twenty` to
`twenty`, `trillion trillion` to `trillion`, `hundredth hundredth` to
`hundredth`, and `half half` to `half` all reject. Any other count-preserving
change is substitution or reordering. Do not put candidate text in a failure
value.

- [ ] **Step 4: Run the focused green command.**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter FaithfulCleanupValidatorTests
```

Expected: PASS. The matrix proves accepted punctuation/case/whitespace,
isolated filler, immediate duplicate, explicit correction, and list formatting;
it proves rejection of protected categories, broad lexical edits, reordering,
ambiguous corrections, empty output, and transcript-shaped input without content
appearing in failure values.

- [ ] **Step 5: Run the adjacent focused checks.**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter CleanupLexemeTests
swift test --disable-automatic-resolution --no-parallel --filter CleanupProtectedSpanTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
```

Expected: all three commands exit 0. The accepted lexeme/span authority remains
unchanged and existing Foundation Model/deterministic cleanup behavior remains
green; Workstream A does not wire the validator into the legacy finalization path.

- [ ] **Step 6: Inspect scope and commit the independently reviewable outcome.**

Run:

```bash
git diff --check
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/FaithfulCleanupValidator.swift \
    Tests/FleckAppTests/FaithfulCleanupValidatorTests.swift \
  | sort -u
)"
```

Expected: clean whitespace; the diff contains only the two Task 1 files; no
network, file write, audio, model, or coordinator symbol appears in the source.

Commit checkpoint:

```bash
git add Sources/FleckApp/FaithfulCleanupValidator.swift Tests/FleckAppTests/FaithfulCleanupValidatorTests.swift
git commit -m "feat: validate faithful cleanup edits"
```

The parent Sol task inspects the actual commit and reruns the focused checks. A
fresh Sol/High reviewer must return exactly `ship` before Task 2 starts.

## Task 2: Add bounded incremental cleanup and cancellation

**Separate user-visible task title:** `Agent - bounded incremental cleanup`

**Dependency:** Begin only after Task 1's validator diff, parent rerun, and
fresh Sol `ship` verdict.

**Owned files:**

- Create: `Sources/FleckApp/IncrementalTranscriptCleaner.swift`
- Test: `Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift`

**Excluded files:** Task 0's four FleckCore files, Task 1's validator files,
all coordinator, processor, runtime, Apple Speech, Settings, model, package,
resource, script, and every file outside these two paths.

**Interfaces:**

- Consumes: `FaithfulCleanupValidator`, `CleanupLexeme.tokenCount(_:)`, and the exact dictionary fields from Task 0's `PersonalDictionaryResolution`.
- Produces: `IncrementalCleanupRequest`, `IncrementalCleanupDecision`, `IncrementalCleanupFallbackReason`, `GeneratedCleanupCandidate`, `CleanupGenerationError`, `CleanupGenerationSession`, `BoundedCleanupGenerating`, `CleanupClock`, `CleanupTerminationDisposition`, and `IncrementalTranscriptCleaner.clean(_:)`.

### TDD red

- [ ] **Step 1: Write concrete generator/session probes and failure tests.** The
  test file defines all probes locally so production contains no test helper
  type, lock, transcript recorder, fake model, or file writer.

```swift
import Foundation
import Testing

@testable import FleckApp

@Test func cleanerUsesOneRequestAndReturnsTheExactBaselineWhenValidationRejects() async throws {
  let generator = CleanupGeneratorProbe(result: "Send 10 files.")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )
  let request = IncrementalCleanupRequest(
    baseline: "Send 20 files.",
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now.advanced(by: .seconds(1))
  )

  let decision = try await cleaner.clean(request)

  #expect(decision == .baseline(reason: .validationRejected))
  #expect(await generator.startCount == 1)
  #expect(await generator.resultCount == 1)
}

@Test func cleanerReturnsBaselineForBoundsMalformedOutputAndDeadline() async throws {
  let large = String(repeating: "word ", count: 81)
  let generator = CleanupGeneratorProbe(result: "unused")
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: TestCleanupClock.immediate
  )

  let largeDecision = try await cleaner.clean(.init(
    baseline: large,
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now.advanced(by: .seconds(1))
  ))
  #expect(largeDecision == .baseline(reason: .targetTooLarge))
  #expect(await generator.startCount == 0)

  let expired = try await cleaner.clean(.init(
    baseline: "Send the report",
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock().now
  ))
  #expect(expired == .baseline(reason: .deadlineExpired))
}

@Test func callerCancellationThrowsAndMakesLateCandidateUnusable() async {
  let generator = CleanupGeneratorProbe(result: "Send the report.", waitsForCancellation: true)
  let cleaner = IncrementalTranscriptCleaner(
    generator: generator,
    clock: .bounded(milliseconds: 1)
  )
  let task = Task {
    try await cleaner.clean(.init(
      baseline: "send the report",
      protectedForms: [],
      replacements: 0,
      deadline: ContinuousClock().now.advanced(by: .seconds(1))
    ))
  }
  await generator.waitUntilStarted()
  task.cancel()

  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(await generator.forceTerminateCount == 1)
  #expect(await generator.lateCandidateWasIgnored)
}
```

The committed file also includes explicit tests for helper-request cancellation,
generation failure, empty output, output greater than input plus 32 tokens,
synchronous `start` returning without I/O, a deadline tie recheck, and a
non-cooperative session whose `forceTerminate()` unblocks both `result()` and
`acknowledgement()`. The non-cooperative case uses a fixed injected clock and a
25 ms cancellation budget; it does not sleep on a wall clock or rely on a
post-completion `phaseHistory`-style assertion.

~~~swift
@Test func nonCooperativeSessionIsForcedWithinTheInjectedBudget() async throws {
  let now = TestCleanupClock.fixedInstant
  let session = CleanupGenerationSessionProbe(
    result: .success(.init(cleaned: "late")),
    ignoresCancellation: true
  )
  let clock = TestCleanupClock(
    now: now,
    recordedSleeps: { TestCleanupClock.recordedSleeps.append($0) }
  )
  let cleaner = IncrementalTranscriptCleaner(
    generator: CleanupGeneratorProbe(session: session),
    clock: clock,
    cancellationBudget: .milliseconds(25)
  )

  let decision = try await cleaner.clean(.init(
    baseline: "send the report",
    protectedForms: [],
    replacements: 0,
    deadline: now.advanced(by: .seconds(1))
  ))

  #expect(decision == .baseline(reason: .deadlineExpired))
  #expect(session.forceTerminateCalled)
  #expect(session.resultFinished)
  #expect(session.acknowledgementFinished)
  #expect(TestCleanupClock.recordedSleeps == [.milliseconds(25)])
}
~~~

- [ ] **Step 2: Run the focused red command.**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter IncrementalTranscriptCleanerTests
```

Expected failure: the test target cannot compile because the request, decision,
generator, session, clock, and cleaner symbols do not exist.

### Minimal implementation

- [ ] **Step 3: Add the bounded contracts and actor.** Use these exact value and
  protocol shapes; the test file may provide actors that conform to them.

```swift
import Foundation
import FleckCore

struct IncrementalCleanupRequest: Equatable, Sendable {
  let baseline: String
  let protectedForms: [String]
  let replacements: Int
  let deadline: ContinuousClock.Instant
}

enum IncrementalCleanupFallbackReason: Equatable, Sendable {
  case targetTooLarge
  case deadlineExpired
  case requestCancelled
  case generationFailed
  case malformedOutput
  case outputTooLarge
  case validationRejected
}

enum IncrementalCleanupDecision: Equatable, Sendable {
  case accepted(String)
  case baseline(reason: IncrementalCleanupFallbackReason)
}

struct GeneratedCleanupCandidate: Equatable, Sendable {
  let cleaned: String
}

enum CleanupGenerationError: Error, Equatable, Sendable {
  case requestCancelled
  case terminated
  case generationFailed
}

struct CleanupClock: Sendable {
  let now: @Sendable () -> ContinuousClock.Instant
  let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
  let sleepFor: @Sendable (Duration) async throws -> Void

  static let live = Self(
    now: { ContinuousClock().now },
    sleepUntil: { try await ContinuousClock().sleep(until: $0) },
    sleepFor: { try await ContinuousClock().sleep(for: $0) }
  )
}

protocol CleanupGenerationSession: Sendable {
  func result() async throws -> GeneratedCleanupCandidate
  func acknowledgement() async
  func requestCancellation()
  func forceTerminate()
}

protocol BoundedCleanupGenerating: Sendable {
  // This synchronous call only constructs a request-specific session.
  func start(
    _ request: IncrementalCleanupRequest,
    maximumOutputTokens: Int
  ) throws -> any CleanupGenerationSession
}

enum CleanupTerminationDisposition: Equatable, Sendable {
  case acknowledged
  case forcedTermination
}

actor IncrementalTranscriptCleaner {
  private let generator: any BoundedCleanupGenerating
  private let validator: FaithfulCleanupValidator
  private let clock: CleanupClock
  private let cancellationBudget: Duration

  init(
    generator: any BoundedCleanupGenerating,
    validator: FaithfulCleanupValidator = .init(),
    clock: CleanupClock,
    cancellationBudget: Duration = .milliseconds(250)
  ) {
    self.generator = generator
    self.validator = validator
    self.clock = clock
    self.cancellationBudget = cancellationBudget
  }

  func clean(_ request: IncrementalCleanupRequest) async throws -> IncrementalCleanupDecision {
    try Task.checkCancellation()
    let inputCount = CleanupLexeme.tokenCount(request.baseline)
    guard inputCount <= 80 else { return .baseline(reason: .targetTooLarge) }
    guard request.deadline > clock.now() else {
      return .baseline(reason: .deadlineExpired)
    }

    let box = CleanupSessionBox()
    do {
      let session = try generator.start(
        request,
        maximumOutputTokens: inputCount + 32
      )
      box.install(session)
      try Task.checkCancellation()
      guard request.deadline > clock.now() else {
        box.requestCancellation()
        _ = await awaitTermination(
          session: session,
          box: box,
          clock: clock,
          cancellationBudget: cancellationBudget
        )
        try Task.checkCancellation()
        return .baseline(reason: .deadlineExpired)
      }

      let event = await withTaskCancellationHandler(operation: {
        await race(
          session: session,
          deadline: request.deadline,
          box: box,
          clock: clock,
          cancellationBudget: cancellationBudget
        )
      }, onCancel: {
        box.requestCancellation()
      })
      try Task.checkCancellation()

      switch event {
      case .deadline:
        return .baseline(reason: .deadlineExpired)
      case .requestCancelled, .terminated:
        return .baseline(reason: .requestCancelled)
      case .callerCancelled:
        throw CancellationError()
      case .generationFailed:
        return .baseline(reason: .generationFailed)
      case .candidate(let candidate):
        guard request.deadline > clock.now() else {
          box.requestCancellation()
          _ = await awaitTermination(
            session: session,
            box: box,
            clock: clock,
            cancellationBudget: cancellationBudget
          )
          try Task.checkCancellation()
          return .baseline(reason: .deadlineExpired)
        }
        guard !candidate.cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return .baseline(reason: .malformedOutput)
        }
        guard CleanupLexeme.tokenCount(candidate.cleaned) <= inputCount + 32 else {
          return .baseline(reason: .outputTooLarge)
        }
        let resolution = PersonalDictionaryResolution(
          baseline: request.baseline,
          protectedForms: request.protectedForms,
          replacements: request.replacements
        )
        switch validator.validate(candidate: candidate.cleaned, against: resolution) {
        case .accepted(let text, _): return .accepted(text)
        case .rejected: return .baseline(reason: .validationRejected)
        }
      }
    } catch is CancellationError {
      box.requestCancellation()
      if let session = box.currentSession() {
        _ = await awaitTermination(
          session: session,
          box: box,
          clock: clock,
          cancellationBudget: cancellationBudget
        )
      }
      throw CancellationError()
    } catch {
      do {
        try Task.checkCancellation()
      } catch is CancellationError {
        box.requestCancellation()
        if let session = box.currentSession() {
          _ = await awaitTermination(
            session: session,
            box: box,
            clock: clock,
            cancellationBudget: cancellationBudget
          )
        }
        throw CancellationError()
      }
      return .baseline(reason: .generationFailed)
    }
  }
}

private final class CleanupSessionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var session: (any CleanupGenerationSession)?
  private var cancellationRequested = false
  private var forceRequested = false

  func install(_ session: any CleanupGenerationSession) {
    let actions = lock.withLock {
      self.session = session
      return (cancellationRequested, forceRequested)
    }
    if actions.0 { session.requestCancellation() }
    if actions.1 { session.forceTerminate() }
  }

  func currentSession() -> (any CleanupGenerationSession)? {
    lock.withLock { session }
  }

  func requestCancellation() {
    let session = lock.withLock {
      cancellationRequested = true
      return self.session
    }
    session?.requestCancellation()
  }

  func forceTerminate() {
    let session = lock.withLock { () -> (any CleanupGenerationSession)? in
      guard !forceRequested else { return nil }
      forceRequested = true
      return self.session
    }
    session?.forceTerminate()
  }

  func forceTerminationRequested() -> Bool {
    lock.withLock { forceRequested }
  }
}

private enum CleanupRaceEvent: Sendable {
  case candidate(GeneratedCleanupCandidate)
  case deadline
  case requestCancelled
  case terminated
  case generationFailed
  case callerCancelled
}

private enum CleanupTerminationEvent: Sendable {
  case acknowledged
  case budgetExpired
}

private func race(
  session: any CleanupGenerationSession,
  deadline: ContinuousClock.Instant,
  box: CleanupSessionBox,
  clock: CleanupClock,
  cancellationBudget: Duration
) async -> CleanupRaceEvent {
  return await withTaskGroup(of: CleanupRaceEvent.self) { group in
    group.addTask {
      do { return .candidate(try await session.result()) }
      catch let error as CleanupGenerationError {
        switch error {
        case .requestCancelled: return .requestCancelled
        case .terminated: return .terminated
        case .generationFailed: return .generationFailed
        }
      } catch is CancellationError {
        return Task.isCancelled ? .callerCancelled : .generationFailed
      } catch {
        return .generationFailed
      }
    }
    group.addTask {
      do {
        try await clock.sleepUntil(deadline)
        return .deadline
      } catch is CancellationError {
        return Task.isCancelled ? .callerCancelled : .deadline
      } catch {
        return .deadline
      }
    }

    guard let first = await group.next() else { return .generationFailed }
    switch first {
    case .deadline, .callerCancelled, .requestCancelled, .terminated:
      box.requestCancellation()
      _ = await awaitTermination(
        session: session,
        box: box,
        clock: clock,
        cancellationBudget: cancellationBudget
      )
      group.cancelAll()
      while await group.next() != nil { }
      return first
    case .candidate, .generationFailed:
      group.cancelAll()
      while await group.next() != nil { }
      return first
    }
  }
}

private func awaitTermination(
  session: any CleanupGenerationSession,
  box: CleanupSessionBox,
  clock: CleanupClock,
  cancellationBudget: Duration
) async -> CleanupTerminationDisposition {
  return await withTaskGroup(of: CleanupTerminationEvent.self) { group in
    group.addTask {
      await session.acknowledgement()
      return .acknowledged
    }
    group.addTask {
      do {
        try await clock.sleepFor(cancellationBudget)
        return .budgetExpired
      } catch {
        return .budgetExpired
      }
    }

    guard let first = await group.next() else {
      box.forceTerminate()
      group.cancelAll()
      while await group.next() != nil { }
      return .forcedTermination
    }
    switch first {
    case .acknowledged:
      group.cancelAll()
      while await group.next() != nil { }
      return box.forceTerminationRequested() ? .forcedTermination : .acknowledged
    case .budgetExpired:
      box.forceTerminate()
      group.cancelAll()
      while await group.next() != nil { }
      return .forcedTermination
    }
  }
}
```

`race` has exactly two structured children: the session `result()` waiter and
the injected `CleanupClock.sleepUntil` deadline waiter. It receives the
`CleanupSessionBox` so cancellation cannot race session installation. Every
deadline/helper/caller-cancellation branch calls `awaitTermination` with the
session, box, injected clock, and cancellation budget while the result child is
still in the task group, then cancels and drains all children. `awaitTermination`
races the acknowledgement waiter against the injected `cancellationBudget`; a
budget win calls synchronous `box.forceTerminate()`.
The session contract requires that synchronous force to unblock both result and
acknowledgement waiters before the cleaner returns, making the deliberately
non-cooperative test bounded. Caller cancellation is rechecked after every
start, race, termination, and validation boundary and is never converted into a
baseline decision. The bounded cleaner itself owns no detached task, retry,
network, file write, transcript diagnostic, or runtime/model ownership. An
adapter that cannot guarantee true underlying force termination must instead
use the four-method session contract with a detachable publication gate, as
specified for `FoundationModelCleanupSession` in Workstream B; closing that
gate immediately acknowledges cancellation and makes every later candidate
unpublishable.

- [ ] **Step 4: Run the focused green command.**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter IncrementalTranscriptCleanerTests
```

Expected: PASS. The suite proves one request/one attempt, exact baseline fallback
for every valid-capture failure, output and target bounds, deadline tie handling,
bounded helper termination, and caller cancellation with no usable late candidate.

- [ ] **Step 5: Run the Stage 1 broader checks.**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter FaithfulCleanupValidatorTests
swift test --disable-automatic-resolution --no-parallel --filter IncrementalTranscriptCleanerTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
```

Expected: all four commands exit 0. Existing Foundation Model and coordinator
behavior remains unchanged because Stage 1 creates a future structured seam and
does not wire it into legacy finalization.

- [ ] **Step 6: Inspect privacy/scope and commit.**

Run:

```bash
git diff --check
! rg -n "URLSession|FileHandle|Data\.write|NSXPC|LanguageModelSession|transcript|audio" Sources/FleckApp/IncrementalTranscriptCleaner.swift
! rg -n "func start\([^)]*\) async|await .*\.start\(" Sources/FleckApp/IncrementalTranscriptCleaner.swift
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/IncrementalTranscriptCleaner.swift \
    Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift \
  | sort -u
)"
```

Expected: the first scan finds no network, file, IPC, or transcript/audio
storage implementation; the second scan finds no asynchronous `start`; the path
assertion contains only Task 2's two files. The parent inspects the full diff and
confirms no production test probe leaked into the source.

Commit checkpoint:

```bash
git add Sources/FleckApp/IncrementalTranscriptCleaner.swift Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift
git commit -m "feat: bound faithful incremental cleanup"
```

The parent Sol task reruns both focused validator/cleaner suites, checks the
complete Stage 1 diff, and obtains a fresh Sol/High `ship` verdict. Only then
may Workstream B Task 1 consume these interfaces.

## Parent verification and handoff

After both task commits, the parent runs the complete serialized Stage 1 set:

```bash
swift test --disable-automatic-resolution --no-parallel --filter CleanupLexemeTests
swift test --disable-automatic-resolution --no-parallel --filter CleanupProtectedSpanTests
swift test --disable-automatic-resolution --no-parallel --filter FaithfulCleanupValidatorTests
swift test --disable-automatic-resolution --no-parallel --filter IncrementalTranscriptCleanerTests
swift test --disable-automatic-resolution --no-parallel --filter FoundationModelDictationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationCoordinatorTests
swift test --disable-automatic-resolution --no-parallel
git diff --check
```

The full command must be reported honestly. If the known unrelated
`AppStateTests.swift` viewport assertion around line 916 reports `18.0 >= 48.0`,
the parent records it as an inherited baseline failure and does not alter this
workstream to hide it. The parent also confirms that the only source/test paths
in the Workstream A diff are the eight listed files plus the accepted cleanup
base.

## Final real-app verification checklist

Workstream A alone cannot claim a launched app or a microphone transcription; it
does not modify app wiring. After Workstreams B and C complete their numbered
tasks, the parent runs the following milestone checklist without changing
Workstream A's scope:

```bash
cd /Users/harryjin/Fleck
swift test --disable-automatic-resolution --no-parallel
./Scripts/build-fleck-app.sh
test -d /Users/harryjin/Fleck/.build/Fleck.app
open /Users/harryjin/Fleck/.build/Fleck.app
```

The operator records the actual microphone words, provisional display, final
inserted text, and cancellation result. The primary may launch the artifact but
must not state a speech result that was not observed. The app must show the
built-in state with no custom model installed; no model-weight download is part
of this checklist.

## Authority boundary

This workstream authorizes only the eight source/test files listed above. Each
numbered task is independently owned and gated. It does not authorize a push,
PR, merge, GitHub write, runtime/model integration, Apple Speech change,
Settings change, model transfer, candidate routing, or release claim.
