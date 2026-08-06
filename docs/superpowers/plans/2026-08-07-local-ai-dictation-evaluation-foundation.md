# Local AI Dictation Evaluation Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans task-by-task. Change-producing implementation tasks follow the mandatory Sol Advisor workflow: primary Sol/High writes a bounded five-part specification; implementation occurs only through sol_advisor_terra_implementer at Terra/High; the primary verifies the parent diff and evidence; then a fresh sol_advisor_sol_reviewer at Sol/High reviews the actual diff and evidence. Do not dispatch that implementation lane during this plan-only task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a privacy-safe, deterministic, offline evaluation foundation for ASR, dictionary baseline, and cleanup outputs before selecting any model/runtime.

**Architecture:** Add a nested standard-library-only Swift package under Tools so the root Package.swift, root Package.resolved, and shipped Fleck app remain unchanged. A pure library owns Codable contracts, normalization, metrics, validation, and report construction; a thin CLI owns argument parsing and file I/O; checked-in fixtures distinguish text-contract/sample data from release evidence; wrapper scripts provide stable commands.

**Tech Stack:** Swift 6/Foundation, Swift Testing, JSON/JSON Schema, POSIX shell, and Markdown. No third-party dependencies.

## Global Constraints

- The complete system is entirely local/offline: no network inference, cloud service, account, API key, audio telemetry, transcript telemetry, dictionary telemetry, or content telemetry.
- No production ASR model, cleanup model, or runtime is selected or approved by Phase A.
- Phase A records no real or personal audio and commits no real or personal audio.
- Full source-code-by-voice, cursor commands, and indentation are non-goals.
- Sample and synthetic results are visibly watermarked and can never satisfy a release gate.
- Preserve the three transcript artifacts exactly: ASR raw, dictionary baseline, and optional cleaned result.
- Metrics do not prove semantic fidelity; protected-term, number, and negation checks plus manual adjudication remain required.
- Run-level failure/cancellation evidence is versioned and non-content; the fixed release outcome fails closed unless both failure fallback and cancellation behavior are exercised and verified.
- Do not modify product code, root Package.swift, root Package.resolved, shared integration files, existing fixtures, TESTING.md, or any dependency.
- Root Package.resolved must be byte-identical to 72e5ebb3f7095966de7fc962a1aec3a871340099.
- The implementation starts from accepted design commit 72e5ebb3f7095966de7fc962a1aec3a871340099.
- Main has not released product/source/test/fixture writing for this Phase A packet; the current task creates this plan document only.
- Future packaged QA always uses a disposable tab to the right of the protected leftmost personal tab and never edits the protected tab.
- No shared-file edits occur during Phase A design or evaluation.
- Every implementation task is independently reviewable, ends with its own focused commit, and stages only the files named by that task.
- The Phase A package has no network-capable code, no audio capture code, and no model/runtime dependency.

## Phase A scope and stop gate

Phase A creates only a deterministic foundation: versioned text/corpus/run
contracts, JSON Schema mirrors, normalization and edit metrics, fail-closed
validation, sample-data report generation, CLI commands, stable shell wrappers,
and an operator procedure. The checked-in corpus is text-contract-only, and the
checked-in run is synthetic. No step records audio, admits a personal speaker,
invokes an ASR or cleanup model, selects a candidate, adds a package dependency,
or changes Fleck runtime behavior.

The accepted design is intentionally decomposed into later plans:

- Phase B owns the personal dictionary core and Apple Standard contextual
  vocabulary through contextualStrings/custom language model APIs where
  supported.
- Phase C owns privacy-safe audio admission, actual ASR and cleanup candidate adapters, benchmark execution, and signed model/license selection.
- Phase D owns the selected model pack, manager, and AI-owned dictation pipeline.
- Phase E owns coordinated shared-file runtime and UI integration plus packaged QA.

Phase B is intentionally next after this foundation: dictionary entry and alias
contracts must be established early because both future ASR prompting and local
cleanup consume the same protected terms.

Those phases are named here so the Phase A worker stops at the measured-contract
boundary. This plan does not define their model-specific interfaces.

## Execution checklist

- [ ] Complete Task 1 with deterministic metric tests and its focused commit.
- [ ] Complete Task 2 with versioned contracts, schemas, fixtures, and its focused commit.
- [ ] Complete Task 3 with report/CLI tests and its focused commit.
- [ ] Complete Task 4 with the offline operator procedure and its focused commit.
- [ ] Run the whole-foundation verification and confirm that only the listed Phase A files changed.

## Planned implementation file map

The Phase A worker may create only these files:

- Tools/LocalDictationEvaluation/Package.swift — nested Swift 6 package with one library, one CLI, and one test target.
- Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift — public versioned corpus/run models, transcript artifacts, normalization, and metric APIs.
- Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/TranscriptMetrics.swift — deterministic Levenshtein counts and percentile implementation.
- Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationValidation.swift — deterministic issue reporting and fail-closed corpus/run validation.
- Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationReport.swift — gate contract, summaries, report model, and deterministic Markdown rendering.
- Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift — exact CLI grammar, JSON I/O, exit codes, and diagnostic redaction.
- Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/TranscriptMetricsTests.swift — metric red tests and regression coverage.
- Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationValidationTests.swift — contract decoding and exact validation issue tests.
- Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationReportTests.swift — gate/report behavior and Markdown determinism tests.
- Tests/Fixtures/local-dictation-evaluation-v1.schema.json — corpus JSON Schema.
- Tests/Fixtures/local-dictation-run-v1.schema.json — run JSON Schema.
- Tests/Fixtures/local-dictation-evaluation-v1.json — text-contract-only corpus manifest.
- Tests/Fixtures/local-dictation-run-sample-v1.json — complete synthetic sample run.
- Scripts/evaluate-local-dictation.sh — stable CLI wrapper.
- Scripts/test-local-dictation-evaluation.sh — nested-package and sample-report integration test.
- docs/dictation/local-model-evaluation.md — operator procedure and Phase A/real-evidence boundary.

Do not add a nested Package.resolved: the package has no dependencies. Do not
modify the existing Tests/Fixtures/clean-dictation-evaluation.json, any Fleck
dictation source or test, root package files, TESTING.md, or shared integration
file.

---

## Task 1: Nested Swift package and deterministic transcript metrics

**Files:**

- Create: Tools/LocalDictationEvaluation/Package.swift
- Create: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift
- Create: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/TranscriptMetrics.swift
- Create: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift
- Create: Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/TranscriptMetricsTests.swift

**Interfaces:**

- Produces EvaluationLanguageMode with cases english, mandarin, and mixed.
- Produces TranscriptArtifactKind with cases asrRaw, dictionaryBaseline, and cleanedResult.
- Produces EditCounts with substitutions, deletions, insertions, referenceUnits, and computed errorRate.
- Produces TranscriptMetrics.englishWordErrorRate(reference:hypothesis:), TranscriptMetrics.mandarinCharacterErrorRate(reference:hypothesis:), and TranscriptMetrics.percentile(_:values:).
- Produces TranscriptMetrics.englishWords(_:), TranscriptMetrics.mandarinCharacters(_:), and TranscriptMetrics.protectedDeveloperTerms(_:) for the later validator and report builder.

### Step 1: Create the nested package and its failing metric tests

Create the package manifest exactly as follows:

~~~swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "LocalDictationEvaluation",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "LocalDictationEvaluation",
      targets: ["LocalDictationEvaluation"]
    ),
    .executable(
      name: "local-dictation-evaluation",
      targets: ["LocalDictationEvaluationCLI"]
    ),
  ],
  targets: [
    .target(name: "LocalDictationEvaluation"),
    .executableTarget(
      name: "LocalDictationEvaluationCLI",
      dependencies: ["LocalDictationEvaluation"]
    ),
    .testTarget(
      name: "LocalDictationEvaluationTests",
      dependencies: ["LocalDictationEvaluation"]
    ),
  ]
)
~~~

Create the minimal executable entry point and test file before the library
files. The entry point keeps the declared executable target compilable while
the metric tests are red:

~~~swift
import Foundation

@main
struct LocalDictationEvaluationCLI {
  static func main() {}
}
~~~

The test file is the complete red test
surface for normalization, operation counts, mixed-language separation, and
nearest-rank percentiles:

~~~swift
import Testing
@testable import LocalDictationEvaluation

@Suite("TranscriptMetricsTests")
struct TranscriptMetricsTests {

@Test func emptyEnglishInputsHaveZeroErrorRate() {
  let counts = TranscriptMetrics.englishWordErrorRate(
    reference: "",
    hypothesis: ""
  )
  #expect(counts == EditCounts(
    substitutions: 0,
    deletions: 0,
    insertions: 0,
    referenceUnits: 0
  ))
  #expect(counts.errorRate == 0)
}

@Test func nonemptyHypothesisWithEmptyReferenceHasUnitErrorRate() {
  let counts = TranscriptMetrics.englishWordErrorRate(
    reference: "",
    hypothesis: "one two"
  )
  #expect(counts.insertions == 2)
  #expect(counts.referenceUnits == 0)
  #expect(counts.errorRate == 1)
}

@Test func englishCountsSubstitutionDeletionAndInsertionWithStableTieBreaks() {
  let substitution = TranscriptMetrics.englishWordErrorRate(
    reference: "alpha beta",
    hypothesis: "alpha gamma"
  )
  #expect(substitution == EditCounts(
    substitutions: 1,
    deletions: 0,
    insertions: 0,
    referenceUnits: 2
  ))

  let deletion = TranscriptMetrics.englishWordErrorRate(
    reference: "alpha beta",
    hypothesis: "alpha"
  )
  #expect(deletion == EditCounts(
    substitutions: 0,
    deletions: 1,
    insertions: 0,
    referenceUnits: 2
  ))

  let insertion = TranscriptMetrics.englishWordErrorRate(
    reference: "alpha",
    hypothesis: "alpha beta"
  )
  #expect(insertion == EditCounts(
    substitutions: 0,
    deletions: 0,
    insertions: 1,
    referenceUnits: 1
  ))
}

@Test func englishNormalizationIsLocaleStableAndPunctuationInsensitive() {
  let counts = TranscriptMetrics.englishWordErrorRate(
    reference: "Commit camelCase, now!",
    hypothesis: "commit CAMELCASE now"
  )
  #expect(counts.errorRate == 0)
  #expect(TranscriptMetrics.englishWords("Commit camelCase, now!") == [
    "commit", "camelcase", "now"
  ])
  #expect(TranscriptMetrics.protectedDeveloperTerms(
    "Commit camelCase, PascalCase, snake_case, now!"
  ) == ["camelCase", "PascalCase", "snake_case"])
}

@Test func mandarinUsesCharactersAndRemovesWhitespaceAndPunctuation() {
  let counts = TranscriptMetrics.mandarinCharacterErrorRate(
    reference: "你好，世界",
    hypothesis: "你 好 世界。"
  )
  #expect(counts == EditCounts(
    substitutions: 0,
    deletions: 0,
    insertions: 0,
    referenceUnits: 4
  ))
  #expect(TranscriptMetrics.mandarinCharacters("你 好，世界。") == [
    "你", "好", "世", "界"
  ])
}

@Test func mixedLanguageMetricsRemainSeparate() {
  let english = TranscriptMetrics.englishWordErrorRate(
    reference: "deploy Fleck",
    hypothesis: "deploy Fleck"
  )
  let mandarin = TranscriptMetrics.mandarinCharacterErrorRate(
    reference: "到生产",
    hypothesis: "到生产"
  )
  #expect(english.errorRate == 0)
  #expect(mandarin.errorRate == 0)
  #expect(english.referenceUnits == 2)
  #expect(mandarin.referenceUnits == 3)
}

@Test func nearestRankPercentileHasDeterministicEdges() {
  let values = [10.0, 30.0, 20.0, 40.0]
  #expect(TranscriptMetrics.percentile(0, values: values) == 10)
  #expect(TranscriptMetrics.percentile(50, values: values) == 20)
  #expect(TranscriptMetrics.percentile(95, values: values) == 40)
  #expect(TranscriptMetrics.percentile(100, values: values) == 40)
  #expect(TranscriptMetrics.percentile(50, values: []) == nil)
  #expect(TranscriptMetrics.percentile(.nan, values: values) == nil)
}
}
~~~

### Step 2: Run the red test

Run the nested evaluation package to expose the initial red test surface:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --no-parallel
~~~

Expected: FAIL before compilation of the tests because the library target has
no metric declarations yet. SwiftPM may report a missing target source/module
or undefined TranscriptMetrics and EditCounts symbols; the failure must occur
before any metric assertion can pass.

### Step 3: Implement the deterministic metric library

Create EvaluationModels.swift with the public enums and EditCounts from the
first part of the block below. Create TranscriptMetrics.swift with the
TranscriptMetrics declaration and its private helpers from the second part;
do not duplicate the shared declarations between files. The compatibility
normalization decision
is explicit: metrics first apply Unicode compatibility composition
(NFKC-equivalent via Foundation), then use Locale identifier en_US_POSIX for
English lowercasing. English WER treats every non-letter, non-decimal-digit,
non-ASCII-apostrophe scalar as a token separator. It therefore ignores
punctuation for WER while protectedDeveloperTerms preserves case-sensitive
identifier spellings separately. Mandarin CER applies the same compatibility
composition, removes whitespace and CharacterSet.punctuationCharacters, and
compares Swift Characters.

~~~swift
import Foundation

public enum EvaluationLanguageMode: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case english
  case mandarin
  case mixed
}

public enum TranscriptArtifactKind: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case asrRaw
  case dictionaryBaseline
  case cleanedResult
}

public struct EditCounts: Codable, Equatable, Sendable {
  public let substitutions: Int
  public let deletions: Int
  public let insertions: Int
  public let referenceUnits: Int

  public init(
    substitutions: Int,
    deletions: Int,
    insertions: Int,
    referenceUnits: Int
  ) {
    self.substitutions = substitutions
    self.deletions = deletions
    self.insertions = insertions
    self.referenceUnits = referenceUnits
  }

  public var errorRate: Double {
    guard referenceUnits > 0 else {
      return substitutions == 0 && deletions == 0 && insertions == 0 ? 0 : 1
    }
    return Double(substitutions + deletions + insertions)
      / Double(referenceUnits)
  }

  public func adding(_ other: EditCounts) -> EditCounts {
    EditCounts(
      substitutions: substitutions + other.substitutions,
      deletions: deletions + other.deletions,
      insertions: insertions + other.insertions,
      referenceUnits: referenceUnits + other.referenceUnits
    )
  }
}

public enum TranscriptMetrics {
  private static let englishLocale = Locale(identifier: "en_US_POSIX")

  public static func englishWordErrorRate(
    reference: String,
    hypothesis: String
  ) -> EditCounts {
    editCounts(
      reference: englishWords(reference),
      hypothesis: englishWords(hypothesis)
    )
  }

  public static func mandarinCharacterErrorRate(
    reference: String,
    hypothesis: String
  ) -> EditCounts {
    editCounts(
      reference: mandarinCharacters(reference),
      hypothesis: mandarinCharacters(hypothesis)
    )
  }

  public static func percentile(
    _ percentile: Double,
    values: [Double]
  ) -> Double? {
    guard percentile.isFinite, (0...100).contains(percentile), !values.isEmpty,
      values.allSatisfy(\.isFinite)
    else {
      return nil
    }
    let sorted = values.sorted()
    let nearestRank = max(
      1,
      Int(ceil(percentile / 100 * Double(sorted.count)))
    )
    return sorted[nearestRank - 1]
  }

  public static func englishWords(_ text: String) -> [String] {
    let normalized = text.precomposedStringWithCompatibilityMapping
    var separated = ""
    for scalar in normalized.unicodeScalars {
      if CharacterSet.letters.contains(scalar)
        || CharacterSet.decimalDigits.contains(scalar)
        || scalar.value == 0x27
      {
        separated.unicodeScalars.append(scalar)
      } else {
        separated.append(" ")
      }
    }
    return separated.split(whereSeparator: \.isWhitespace).map {
      String($0).lowercased(with: englishLocale)
    }
  }

  public static func mandarinCharacters(_ text: String) -> [Character] {
    let normalized = text.precomposedStringWithCompatibilityMapping
    return normalized.filter { character in
      !character.unicodeScalars.contains { scalar in
        CharacterSet.whitespacesAndNewlines.contains(scalar)
          || CharacterSet.punctuationCharacters.contains(scalar)
      }
    }.map { $0 }
  }

  public static func protectedDeveloperTerms(_ text: String) -> [String] {
    let candidates = text.split { character in
      !character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.letters.contains(scalar)
          || CharacterSet.decimalDigits.contains(scalar)
          || scalar.value == 0x5F
      }
    }.map(String.init)

    return candidates.filter { candidate in
      let characters = Array(candidate)
      guard characters.count > 1 else { return false }
      let letterCount = characters.filter { $0.isLetter }.count
      let allUppercase = letterCount >= 2
        && characters.filter(\.isLetter).allSatisfy(\.isUppercase)
      let hasCaseTransition = zip(
        characters.dropLast(),
        characters.dropFirst()
      ).contains { previous, current in
        previous.isLowercase && current.isUppercase
      }
      return candidate.contains("_") || allUppercase || hasCaseTransition
    }
  }

  private static func editCounts<T: Equatable>(
    reference: [T],
    hypothesis: [T]
  ) -> EditCounts {
    var costs = Array(
      repeating: Array(repeating: 0, count: hypothesis.count + 1),
      count: reference.count + 1
    )
    for row in 0...reference.count { costs[row][0] = row }
    for column in 0...hypothesis.count { costs[0][column] = column }

    if !reference.isEmpty && !hypothesis.isEmpty {
      for row in 1...reference.count {
        for column in 1...hypothesis.count {
          let substitutionCost = reference[row - 1] == hypothesis[column - 1]
            ? 0
            : 1
          costs[row][column] = min(
            costs[row - 1][column - 1] + substitutionCost,
            costs[row - 1][column] + 1,
            costs[row][column - 1] + 1
          )
        }
      }
    }

    var row = reference.count
    var column = hypothesis.count
    var substitutions = 0
    var deletions = 0
    var insertions = 0

    while row > 0 || column > 0 {
      if row > 0, column > 0,
        reference[row - 1] == hypothesis[column - 1],
        costs[row][column] == costs[row - 1][column - 1]
      {
        row -= 1
        column -= 1
      } else if row > 0, column > 0,
        costs[row][column] == costs[row - 1][column - 1] + 1
      {
        substitutions += 1
        row -= 1
        column -= 1
      } else if row > 0,
        costs[row][column] == costs[row - 1][column] + 1
      {
        deletions += 1
        row -= 1
      } else {
        insertions += 1
        column -= 1
      }
    }

    return EditCounts(
      substitutions: substitutions,
      deletions: deletions,
      insertions: insertions,
      referenceUnits: reference.count
    )
  }
}
~~~

Keep the implementation in one public type in TranscriptMetrics.swift to
prevent duplicate normalizers. Add the version marker after that type:

~~~swift
import Foundation

public enum TranscriptMetricsVersion {
  public static let schemaVersion = 1
}
~~~

The version constant is deliberately separate from the JSON contract version
added in Task 2. It is a compile-time library marker, not a model or corpus
revision.

### Step 4: Run the green metric tests

Run the explicit `TranscriptMetricsTests` Swift Testing suite:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --filter TranscriptMetricsTests --no-parallel
~~~

Expected: all metric tests pass, including empty-reference semantics,
substitution/deletion/insertion counts, punctuation/case normalization,
Mandarin Character comparison, mixed-language separate calculations, and
nearest-rank percentile edges. No network access or root package resolution is
involved.

Then run the package-wide focused check:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --no-parallel
~~~

Expected: PASS for the current metric tests.

### Step 5: Scope-check and commit Task 1

Run:

~~~sh
git diff --check
git status --short --branch
git diff --name-only
~~~

Expected: only the five Task 1 paths are changed, and no root Package.resolved
appears. Stage exactly those five paths and commit:

~~~sh
git add \
  Tools/LocalDictationEvaluation/Package.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/TranscriptMetrics.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift \
  Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/TranscriptMetricsTests.swift
git commit -m "feat: add deterministic local dictation metrics"
~~~

Expected: one focused commit with the exact subject above. The worker reports
the commit SHA, parent SHA, focused test result, and scope output.

---

## Task 2: Versioned corpus/run contracts and fail-closed validation

**Files:**

- Modify: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift
- Create: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationValidation.swift
- Create: Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationValidationTests.swift
- Create: Tests/Fixtures/local-dictation-evaluation-v1.schema.json
- Create: Tests/Fixtures/local-dictation-run-v1.schema.json
- Create: Tests/Fixtures/local-dictation-evaluation-v1.json
- Create: Tests/Fixtures/local-dictation-run-sample-v1.json

**Interfaces:**

- Add public Codable, Sendable, and Equatable contracts for
  EvaluationCorpus, EvaluationCase, ProtectedExpectation,
  CorpusProvenance, CandidateRun, CandidateIdentity, RunEnvironment,
  UtteranceResult, ResourceMeasurement, and OfflineEvidence.
- Add the supporting enums and value types used by those contracts:
  EvaluationSeverity, ProtectedMatchMode, AudioConsentStatus,
  CaptureTemperature, ThermalState, ManualAdjudicationStatus,
  EvaluationTextSlice, AudioProvenance, AudioConsent,
  LatencyMeasurement, ManualAdjudication, EvaluationMetricKind,
  StandardBaselineIdentity, StandardBaselineMetric,
  StandardBaselineEvidence, UnloadEvidence, and
  FailureCancellationEvidence.
- Add EvaluationIssue and
  EvaluationValidator.validate(corpus:) plus
  EvaluationValidator.validate(run:against:). Both return issues sorted by
  JSON path and then issue code, and neither includes transcript text in an
  issue message.
- ProtectedExpectation.language is required and must belong to the case's
  language mode; every admitted audio asset requires AudioConsentStatus.approved.
  A non-synthetic CandidateRun is a real benchmark and requires admitted audio
  for every corpus case regardless of releaseEvidence; releaseEvidence gates
  release-only claims separately.
- Every UtteranceResult is the uniquely identified observation/trial record:
  observationID is stable and unique within CandidateRun, caseID may repeat
  for cold/warm and additional trials, and CandidateRun requires at least one
  cold and one warm observation for every corpus case. A result is never
  implicitly one-per-case.
- StandardBaselineIdentity is comparable evidence, not a label: it records
  baseline model revision, corpus ID/revision, OS version, hardware model,
  architecture, app build, and positive cold/warm observation counts.
- FailureCancellationEvidence is a schemaVersion 1, non-content run-level
  record with separate exercised/verified booleans, evidence IDs, timestamps,
  and an operator note for failure fallback and cancellation behavior.

### Step 1: Create the contract tests and fixtures before the implementation

Create EvaluationValidationTests.swift with these exact test cases. The
fixture loader resolves from the repository root by walking upward from
filePath; it must fail the test with a stable file name if the fixture is
missing rather than silently using inline data.

~~~swift
import Foundation
import Testing
@testable import LocalDictationEvaluation

private func fixture(_ name: String) throws -> Data {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<8 {
    let candidate = url
      .deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/\(name)")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return try Data(contentsOf: candidate)
    }
    url.deleteLastPathComponent()
  }
  Issue.record("Missing fixture \(name)")
  return Data()
}

private func decodeCorpus() throws -> EvaluationCorpus {
  try JSONDecoder().decode(
    EvaluationCorpus.self,
    from: fixture("local-dictation-evaluation-v1.json")
  )
}

private func decodeSampleRun() throws -> CandidateRun {
  try JSONDecoder().decode(
    CandidateRun.self,
    from: fixture("local-dictation-run-sample-v1.json")
  )
}

@Suite("EvaluationValidationTests")
struct EvaluationValidationTests {

@Test func checkedInCorpusAndSampleRunDecodeAndValidate() throws {
  let corpus = try decodeCorpus()
  let run = try decodeSampleRun()
  #expect(corpus.schemaVersion == 1)
  #expect(run.schemaVersion == 1)
  #expect(run.syntheticSample)
  #expect(!run.releaseEvidence)
  #expect(run.results.count == 6)
  #expect(Set(run.results.map(\.observationID)).count == 6)
  #expect(run.results.filter { $0.caseID == "english-developer-command" }
    .map(\.captureTemperature) == [.cold, .warm])
  #expect(run.results.filter { $0.caseID == "mandarin-prose-numbers" }
    .map(\.captureTemperature) == [.cold, .warm])
  #expect(run.results.filter { $0.caseID == "mixed-prompt-and-path" }
    .map(\.captureTemperature) == [.cold, .warm])
  #expect(EvaluationValidator.validate(corpus: corpus).isEmpty)
  #expect(EvaluationValidator.validate(run: run, against: corpus).isEmpty)
}

@Test func corpusValidationReportsStableDuplicateAndBlankPaths() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].id = " "
  corpus.cases[1].id = corpus.cases[2].id
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "blank_id" && $0.path == "/cases/0/id"
  })
  #expect(issues.contains {
    $0.code == "duplicate_case_id" && $0.path == "/cases/2/id"
  })
}

@Test func corpusValidationRejectsMissingCategoryAndBlankReference() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].categories = []
  corpus.cases[0].referenceText = " \n"
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "missing_category" && $0.path == "/cases/0/categories"
  })
  #expect(issues.contains {
    $0.code == "blank_reference" && $0.path == "/cases/0/referenceText"
  })
}

@Test func corpusValidationRejectsMissingMetricLanguageSlice() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].metricReferenceSlices = []
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "missing_language"
      && $0.path == "/cases/0/metricReferenceSlices"
  })
}

@Test func corpusValidationRejectsMalformedSpokenAndProtectedExpectations()
  throws
{
  var corpus = try decodeCorpus()
  corpus.cases[1].spokenText = " "
  corpus.cases[0].protectedExpectations[0].id = " "
  corpus.cases[0].protectedExpectations[1].id = "duplicate"
  corpus.cases[0].protectedExpectations[2].id = "duplicate"
  corpus.cases[0].protectedExpectations[3].term = " "
  corpus.cases[0].protectedExpectations[4].language = .mandarin
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "blank_spoken_text" && $0.path == "/cases/1/spokenText"
  })
  #expect(issues.contains {
    $0.code == "blank_protected_expectation_id"
      && $0.path == "/cases/0/protectedExpectations/0/id"
  })
  #expect(issues.contains {
    $0.code == "duplicate_protected_expectation_id"
      && $0.path == "/cases/0/protectedExpectations/2/id"
  })
  #expect(issues.contains {
    $0.code == "blank_protected_term"
      && $0.path == "/cases/0/protectedExpectations/3/term"
  })
  #expect(issues.contains {
    $0.code == "protected_language_mismatch"
      && $0.path == "/cases/0/protectedExpectations/4/language"
  })
}

@Test func corpusValidationRejectsUnadmittedAudioAndMissingConsent() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].audioAsset = "audio/english.wav"
  corpus.cases[0].audioProvenance = AudioProvenance(
    assetSHA256: "not-a-sha",
    source: "",
    license: "",
    approved: false,
    speakerLanguage: "English",
    speakerAccent: nil,
    privacyReview: "",
    revocationProcess: ""
  )
  corpus.cases[0].audioConsent = AudioConsent(
    status: .pending,
    recordID: "",
    reviewer: nil,
    reviewedAt: nil
  )
  let issues = EvaluationValidator.validate(corpus: corpus)
  #expect(issues.contains {
    $0.code == "audio_provenance" && $0.path == "/cases/0/audioProvenance"
  })
  #expect(issues.contains {
    $0.code == "audio_consent" && $0.path == "/cases/0/audioConsent"
  })
}

@Test func duplicateCorpusIDsCannotTrapRunValidation() throws {
  var corpus = try decodeCorpus()
  corpus.cases[1].id = corpus.cases[2].id
  let issues = EvaluationValidator.validate(
    run: try decodeSampleRun(),
    against: corpus
  )
  #expect(issues.contains {
    $0.code == "duplicate_case_id" && $0.path == "/cases/2/id"
  })
}

@Test func duplicateObservationIDsAndManualStatusAreRejected() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results[1].observationID = run.results[0].observationID
  run.results[0].manualAdjudication = ManualAdjudication(
    status: .notRequired,
    reviewer: nil,
    notes: nil
  )
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "duplicate_observation_id"
      && $0.path == "/results/1/observationID"
  })
  #expect(issues.contains {
    $0.code == "manual_adjudication_not_required_with_cleanup"
      && $0.path == "/results/0/manualAdjudication/status"
  })
}

@Test func whitespaceAudioAssetCannotBeAdmittedForRealBenchmark() throws {
  var corpus = try decodeCorpus()
  corpus.cases[0].audioAsset = "  \n"
  var run = try decodeSampleRun()
  run.syntheticSample = false
  run.releaseEvidence = false
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "real_audio_not_admitted"
      && $0.path == "/cases/0/audioAsset"
  })
}

@Test func nonSyntheticAudioFreeCorpusCannotValidateWithoutReleaseEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.syntheticSample = false
  run.releaseEvidence = false
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.filter { $0.code == "real_audio_not_admitted" }
    .map(\.path) == [
      "/cases/0/audioAsset",
      "/cases/1/audioAsset",
      "/cases/2/audioAsset"
    ])
}

@Test func runValidationReportsMismatchMissingRawAndArtifactOrder() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.corpusRevision = "wrong-revision"
  run.results[0].asrRaw = " "
  run.results[0].artifactOrder = [.asrRaw, .cleanedResult]
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "corpus_run_mismatch" && $0.path == "/corpusRevision"
  })
  #expect(issues.contains {
    $0.code == "missing_asr_raw" && $0.path == "/results/0/asrRaw"
  })
  #expect(issues.contains {
    $0.code == "invalid_artifact_order"
      && $0.path == "/results/0/artifactOrder"
  })
}

@Test func runValidationRejectsMissingBaselineBlankOptionalsAndInvalidOrder()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results[0].dictionaryBaseline = nil
  run.results[0].cleanedResult = "cleaned result"
  run.results[0].artifactOrder = [.asrRaw, .cleanedResult]
  run.results[1].dictionaryBaseline = " "
  run.results[1].cleanedResult = "\n"
  run.results[1].artifactOrder = [.asrRaw, .dictionaryBaseline, .cleanedResult]
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "cleaned_without_baseline"
      && $0.path == "/results/0/cleanedResult"
  })
  #expect(issues.contains {
    $0.code == "invalid_artifact_order"
      && $0.path == "/results/0/artifactOrder"
  })
  #expect(issues.contains {
    $0.code == "blank_dictionary_baseline"
      && $0.path == "/results/1/dictionaryBaseline"
  })
  #expect(issues.contains {
    $0.code == "blank_cleaned_result"
      && $0.path == "/results/1/cleanedResult"
  })
}

@Test func runValidationRequiresCorrectColdAndWarmEvidence() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results[0].latency.coldLoadMilliseconds = nil
  run.results[1].latency.coldLoadMilliseconds = 1
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "missing_cold_load_measurement"
      && $0.path == "/results/0/latency/coldLoadMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "warm_cold_load_present"
      && $0.path == "/results/1/latency/coldLoadMilliseconds"
  })
}

@Test func runValidationRejectsInvalidBaselineUnloadAndOfflineEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.standardBaseline.metrics[0].scope = .mandarin
  run.standardBaseline.metrics[0].value = .nan
  run.unloadEvidence.memoryAfterUnloadBytes = -1
  run.offlineEvidence.evidenceNote = " "
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "invalid_standard_baseline_metric"
      && $0.path == "/standardBaseline/metrics/0/metric"
  })
  #expect(issues.contains {
    $0.code == "non_finite_standard_baseline_metric"
      && $0.path == "/standardBaseline/metrics/0/value"
  })
  #expect(issues.contains {
    $0.code == "negative_unload_memory"
      && $0.path == "/unloadEvidence/memoryAfterUnloadBytes"
  })
  #expect(issues.contains {
    $0.code == "blank_id"
      && $0.path == "/offlineEvidence/evidenceNote"
  })
}

@Test func runValidationRejectsIncomparableStandardBaseline() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.standardBaseline.identity.corpusID = "different-corpus"
  run.standardBaseline.identity.corpusRevision = "different-revision"
  run.standardBaseline.identity.osVersion = "different-os"
  run.standardBaseline.identity.coldObservationCount = 0
  run.standardBaseline.identity.warmObservationCount = 0
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "baseline_corpus_mismatch"
      && $0.path == "/standardBaseline/identity/corpusID"
  })
  #expect(issues.contains {
    $0.code == "baseline_corpus_mismatch"
      && $0.path == "/standardBaseline/identity/corpusRevision"
  })
  #expect(issues.contains {
    $0.code == "baseline_environment_mismatch"
      && $0.path == "/standardBaseline/identity/osVersion"
  })
  #expect(issues.contains {
    $0.code == "invalid_baseline_coverage"
      && $0.path == "/standardBaseline/identity/coldObservationCount"
  })
  #expect(issues.contains {
    $0.code == "invalid_baseline_coverage"
      && $0.path == "/standardBaseline/identity/warmObservationCount"
  })
}

@Test func runValidationRejectsMalformedFailureCancellationEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.failureCancellationEvidence.failureEvidenceID = " "
  run.failureCancellationEvidence.cancellationObservedAt = "not-a-time"
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "blank_id"
      && $0.path == "/failureCancellationEvidence/failureEvidenceID"
  })
  #expect(issues.contains {
    $0.code == "invalid_failure_cancellation_timestamp"
      && $0.path == "/failureCancellationEvidence/cancellationObservedAt"
  })
}

@Test func runValidationRejectsBadMeasurementsAndSyntheticReleaseEvidence()
  throws
{
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.releaseEvidence = true
  run.results[0].latency.asrMilliseconds = -1
  run.results[1].latency.cleanupMilliseconds = .infinity
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "negative_measurement"
      && $0.path == "/results/0/latency/asrMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "non_finite_measurement"
      && $0.path == "/results/1/latency/cleanupMilliseconds"
  })
  #expect(issues.contains {
    $0.code == "synthetic_release_evidence"
      && $0.path == "/releaseEvidence"
  })
}

@Test func runValidationFailsClosedForOfflineAndUnknownResults() throws {
  let corpus = try decodeCorpus()
  var run = try decodeSampleRun()
  run.results.removeLast()
  run.offlineEvidence.networkDisabled = false
  run.offlineEvidence.networkRequestsObserved = 1
  run.offlineEvidence.contentTelemetryObserved = true
  let unknown = UtteranceResult(
    observationID: "unknown-observation",
    caseID: "not-in-corpus",
    language: .english,
    artifactOrder: [.asrRaw],
    asrRaw: "not persisted",
    dictionaryBaseline: nil,
    cleanedResult: nil,
    captureTemperature: .warm,
    latency: run.results[0].latency,
    resources: run.results[0].resources,
    metricHypothesisSlices: [
      EvaluationTextSlice(language: .english, text: "not persisted")
    ],
    manualAdjudication: nil
  )
  run.results.append(unknown)
  let issues = EvaluationValidator.validate(run: run, against: corpus)
  #expect(issues.contains {
    $0.code == "missing_warm_observation"
      && $0.path == "/cases/2/observations"
  })
  #expect(issues.contains {
    $0.code == "unknown_case_id" && $0.path == "/results/5/caseID"
  })
  #expect(issues.contains {
    $0.code == "offline_network_observed"
      && $0.path == "/offlineEvidence/networkRequestsObserved"
  })
  #expect(issues.contains {
    $0.code == "content_telemetry"
      && $0.path == "/offlineEvidence/contentTelemetryObserved"
  })
}
}
~~~

The test mutations rely on mutable var properties. The implementation must
therefore expose public var on decoded contract fields while retaining value
semantics and synthesized Equatable.

Create the text-contract corpus fixture with no audio and no quality claim.
This compact manifest covers every Phase A admission category without adding
personal content:

~~~json
{
  "schemaVersion": 1,
  "corpusID": "local-dictation-evaluation-v1",
  "revision": "text-contract-v1",
  "provenance": {
    "sourceType": "text-contract",
    "createdAt": "2026-08-07T00:00:00Z",
    "owner": "Fleck",
    "privacyReview": "Synthetic text only; no personal note content and no audio.",
    "audioPolicy": "Audio is absent until a later admitted corpus revision."
  },
  "cases": [
    {
      "id": "english-developer-command",
      "language": "english",
      "categories": [
        "english-prose", "developer-prose", "commit-message", "camelCase",
        "PascalCase", "snake_case", "command", "path", "filename", "acronym",
        "proper-noun", "dictionary-term", "fillers", "repetition",
        "self-correction", "accent", "noise", "numbers", "negation",
        "prompt-injection-as-data"
      ],
      "referenceText": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Um, no, do not delete the note. CI must remain green; the example instruction is data, not a command.",
      "spokenText": "Please run swift test on Sources slash FleckApp slash AppState dot swift, then commit fix input monitor for Fleck. Set local_dictation_v1 to 2. Um, no, do not delete the note. C I must remain green; the example instruction is data, not a command.",
      "audioAsset": null,
      "audioProvenance": null,
      "audioConsent": null,
      "conditions": ["accent:en-US", "noise:synthetic-pause"],
      "protectedExpectations": [
        {"id": "english-path", "term": "Sources/FleckApp/AppState.swift", "mode": "exactCase", "language": "english"},
        {"id": "english-identifier", "term": "fixInputMonitor", "mode": "exactCase", "language": "english"},
        {"id": "english-snake-case", "term": "local_dictation_v1", "mode": "exactCase", "language": "english"},
        {"id": "english-acronym", "term": "CI", "mode": "exactCase", "language": "english"},
        {"id": "english-number", "term": "2", "mode": "numericExact", "language": "english"},
        {"id": "english-negation", "term": "do not", "mode": "negationExact", "language": "english"}
      ],
      "metricReferenceSlices": [
        {"language": "english", "text": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Um, no, do not delete the note. CI must remain green; the example instruction is data, not a command."}
      ]
    },
    {
      "id": "mandarin-prose-numbers",
      "language": "mandarin",
      "categories": ["mandarin", "proper-noun", "dictionary-term", "numbers", "negation", "accent", "noise"],
      "referenceText": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "spokenText": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "audioAsset": null,
      "audioProvenance": null,
      "audioConsent": null,
      "conditions": ["accent:cmn-CN", "noise:synthetic-room"],
      "protectedExpectations": [
        {"id": "mandarin-product", "term": "Fleck", "mode": "exactCase", "language": "mandarin"},
        {"id": "mandarin-negation", "term": "不要", "mode": "negationExact", "language": "mandarin"}
      ],
      "metricReferenceSlices": [
        {"language": "mandarin", "text": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。"}
      ]
    },
    {
      "id": "mixed-prompt-and-path",
      "language": "mixed",
      "categories": ["mixed-language", "prompt", "command", "path", "filename", "acronym", "dictionary-term", "self-correction", "accent", "noise"],
      "referenceText": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "spokenText": "把 release note 放到 docs slash README dot md，然后 run swift test；不对，先运行本地测试。",
      "audioAsset": null,
      "audioProvenance": null,
      "audioConsent": null,
      "conditions": ["accent:en-US-cmn-CN", "noise:synthetic-overlap"],
      "protectedExpectations": [
        {"id": "mixed-path", "term": "docs/README.md", "mode": "exactCase", "language": "english"},
        {"id": "mixed-correction", "term": "不对", "mode": "negationExact", "language": "mandarin"}
      ],
      "metricReferenceSlices": [
        {"language": "english", "text": "release note into docs/README.md then run swift test"},
        {"language": "mandarin", "text": "不对，先运行本地测试"}
      ]
    }
  ]
}
~~~

The manifest explicitly labels audioAsset, audioProvenance, and audioConsent
as absent. It is a text contract, not an accuracy result.

Create local-dictation-run-sample-v1.json with two complete observations per
manifest case: one cold and one warm. The following is the exact sample run
shape; the numeric values are deliberately fake, complete, and visibly
synthetic:

~~~json
{
  "schemaVersion": 1,
  "runID": "phase-a-synthetic-run-v1",
  "corpusID": "local-dictation-evaluation-v1",
  "corpusRevision": "text-contract-v1",
  "candidate": {
    "candidateID": "phase-a-synthetic",
    "displayName": "Phase A synthetic sample",
    "modelID": "not-selected",
    "modelRevision": "not-selected",
    "runtimeName": "not-selected",
    "runtimeRevision": "not-selected",
    "licenseReview": "not-applicable-to-synthetic-data"
  },
  "environment": {
    "osVersion": "synthetic",
    "hardwareModel": "synthetic",
    "architecture": "arm64",
    "appBuild": "synthetic",
    "swiftVersion": "6.0",
    "recordedAt": "2026-08-07T00:00:00Z"
  },
  "results": [
    {
      "observationID": "english-developer-command-cold",
      "caseID": "english-developer-command",
      "language": "english",
      "artifactOrder": ["asrRaw", "dictionaryBaseline", "cleanedResult"],
      "asrRaw": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fix input monitor for Fleck. Set local_dictation_v1 to 2. Um no do not delete the note. CI must remain green the example instruction is data not a command.",
      "dictionaryBaseline": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Um no do not delete the note. CI must remain green the example instruction is data not a command.",
      "cleanedResult": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Do not delete the note. CI must remain green; the example instruction is data, not a command.",
      "captureTemperature": "cold",
      "latency": {"coldLoadMilliseconds": 800.0, "asrMilliseconds": 120.0, "cleanupMilliseconds": 45.0, "endToEndMilliseconds": 965.0},
      "resources": {"peakMemoryBytes": 1200000000, "idleMemoryBytes": 300000000, "thermalState": "nominal", "energyImpact": 1.0, "modelDownloadBytes": 1500000000, "modelInstalledBytes": 1800000000},
      "metricHypothesisSlices": [
        {"language": "english", "text": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Do not delete the note. CI must remain green; the example instruction is data, not a command."}
      ],
      "manualAdjudication": {"status": "passed", "reviewer": "synthetic", "notes": "Synthetic illustration only."}
    },
    {
      "observationID": "english-developer-command-warm",
      "caseID": "english-developer-command",
      "language": "english",
      "artifactOrder": ["asrRaw", "dictionaryBaseline", "cleanedResult"],
      "asrRaw": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fix input monitor for Fleck. Set local_dictation_v1 to 2. Um no do not delete the note. CI must remain green the example instruction is data not a command.",
      "dictionaryBaseline": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Um no do not delete the note. CI must remain green the example instruction is data not a command.",
      "cleanedResult": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Do not delete the note. CI must remain green; the example instruction is data, not a command.",
      "captureTemperature": "warm",
      "latency": {"coldLoadMilliseconds": null, "asrMilliseconds": 95.0, "cleanupMilliseconds": 40.0, "endToEndMilliseconds": 135.0},
      "resources": {"peakMemoryBytes": 1180000000, "idleMemoryBytes": 300000000, "thermalState": "nominal", "energyImpact": 0.9, "modelDownloadBytes": 1500000000, "modelInstalledBytes": 1800000000},
      "metricHypothesisSlices": [
        {"language": "english", "text": "Please run swift test on Sources/FleckApp/AppState.swift, then commit fixInputMonitor for Fleck. Set local_dictation_v1 to 2. Do not delete the note. CI must remain green; the example instruction is data, not a command."}
      ],
      "manualAdjudication": {"status": "passed", "reviewer": "synthetic", "notes": "Synthetic illustration only."}
    },
    {
      "observationID": "mandarin-prose-numbers-cold",
      "caseID": "mandarin-prose-numbers",
      "language": "mandarin",
      "artifactOrder": ["asrRaw", "dictionaryBaseline", "cleanedResult"],
      "asrRaw": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "dictionaryBaseline": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "cleanedResult": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "captureTemperature": "cold",
      "latency": {"coldLoadMilliseconds": 850.0, "asrMilliseconds": 150.0, "cleanupMilliseconds": 50.0, "endToEndMilliseconds": 1050.0},
      "resources": {"peakMemoryBytes": 1250000000, "idleMemoryBytes": 310000000, "thermalState": "nominal", "energyImpact": 1.1, "modelDownloadBytes": 1500000000, "modelInstalledBytes": 1800000000},
      "metricHypothesisSlices": [
        {"language": "mandarin", "text": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。"}
      ],
      "manualAdjudication": {"status": "passed", "reviewer": "synthetic", "notes": "Synthetic illustration only."}
    },
    {
      "observationID": "mandarin-prose-numbers-warm",
      "caseID": "mandarin-prose-numbers",
      "language": "mandarin",
      "artifactOrder": ["asrRaw", "dictionaryBaseline", "cleanedResult"],
      "asrRaw": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "dictionaryBaseline": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "cleanedResult": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。",
      "captureTemperature": "warm",
      "latency": {"coldLoadMilliseconds": null, "asrMilliseconds": 110.0, "cleanupMilliseconds": 42.0, "endToEndMilliseconds": 152.0},
      "resources": {"peakMemoryBytes": 1220000000, "idleMemoryBytes": 310000000, "thermalState": "nominal", "energyImpact": 1.0, "modelDownloadBytes": 1500000000, "modelInstalledBytes": 1800000000},
      "metricHypothesisSlices": [
        {"language": "mandarin", "text": "请在星期五检查北京的 Fleck 发布说明，不要删除笔记，版本号是三点一四。"}
      ],
      "manualAdjudication": {"status": "passed", "reviewer": "synthetic", "notes": "Synthetic illustration only."}
    },
    {
      "observationID": "mixed-prompt-and-path-cold",
      "caseID": "mixed-prompt-and-path",
      "language": "mixed",
      "artifactOrder": ["asrRaw", "dictionaryBaseline", "cleanedResult"],
      "asrRaw": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "dictionaryBaseline": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "cleanedResult": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "captureTemperature": "cold",
      "latency": {"coldLoadMilliseconds": 900.0, "asrMilliseconds": 160.0, "cleanupMilliseconds": 48.0, "endToEndMilliseconds": 1108.0},
      "resources": {"peakMemoryBytes": 1230000000, "idleMemoryBytes": 305000000, "thermalState": "nominal", "energyImpact": 1.0, "modelDownloadBytes": 1500000000, "modelInstalledBytes": 1800000000},
      "metricHypothesisSlices": [
        {"language": "english", "text": "release note into docs/README.md then run swift test"},
        {"language": "mandarin", "text": "不对，先运行本地测试"}
      ],
      "manualAdjudication": {"status": "passed", "reviewer": "synthetic", "notes": "Synthetic illustration only."}
    },
    {
      "observationID": "mixed-prompt-and-path-warm",
      "caseID": "mixed-prompt-and-path",
      "language": "mixed",
      "artifactOrder": ["asrRaw", "dictionaryBaseline", "cleanedResult"],
      "asrRaw": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "dictionaryBaseline": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "cleanedResult": "把 release note 放到 docs/README.md，然后 run swift test；不对，先运行本地测试。",
      "captureTemperature": "warm",
      "latency": {"coldLoadMilliseconds": null, "asrMilliseconds": 115.0, "cleanupMilliseconds": 43.0, "endToEndMilliseconds": 158.0},
      "resources": {"peakMemoryBytes": 1210000000, "idleMemoryBytes": 305000000, "thermalState": "nominal", "energyImpact": 0.9, "modelDownloadBytes": 1500000000, "modelInstalledBytes": 1800000000},
      "metricHypothesisSlices": [
        {"language": "english", "text": "release note into docs/README.md then run swift test"},
        {"language": "mandarin", "text": "不对，先运行本地测试"}
      ],
      "manualAdjudication": {"status": "passed", "reviewer": "synthetic", "notes": "Synthetic illustration only."}
    }
  ],
  "standardBaseline": {
    "identity": {
      "baselineID": "apple-standard-baseline",
      "baselineRevision": "standard-v1",
      "engine": "AppleSpeechCapture",
      "modelRevision": "AppleSpeechCapture-standard-v1-synthetic",
      "corpusID": "local-dictation-evaluation-v1",
      "corpusRevision": "text-contract-v1",
      "osVersion": "synthetic",
      "hardwareModel": "synthetic",
      "architecture": "arm64",
      "appBuild": "synthetic",
      "coldObservationCount": 3,
      "warmObservationCount": 3,
      "recordedAt": "2026-08-07T00:00:00Z"
    },
    "metrics": [
      {"scope": "english", "metric": "englishWordErrorRate", "value": 0.30},
      {"scope": "english", "metric": "protectedTermAccuracy", "value": 0.70},
      {"scope": "mandarin", "metric": "mandarinCharacterErrorRate", "value": 0.35},
      {"scope": "mandarin", "metric": "protectedTermAccuracy", "value": 0.65},
      {"scope": "mixed", "metric": "englishWordErrorRate", "value": 0.40},
      {"scope": "mixed", "metric": "mandarinCharacterErrorRate", "value": 0.45},
      {"scope": "mixed", "metric": "protectedTermAccuracy", "value": 0.60}
    ]
  },
  "unloadEvidence": {
    "unloadAttempted": true,
    "unloadSucceeded": true,
    "memoryAfterUnloadBytes": 250000000,
    "observedAt": "2026-08-07T00:10:00Z"
  },
  "offlineEvidence": {
    "networkDisabled": true,
    "networkRequestsObserved": 0,
    "contentTelemetryObserved": false,
    "isolationMethod": "synthetic-offline-test-harness",
    "startedAt": "2026-08-07T00:00:00Z",
    "endedAt": "2026-08-07T00:10:00Z",
    "evidenceNote": "Synthetic offline evidence; not release evidence."
  },
  "failureCancellationEvidence": {
    "schemaVersion": 1,
    "failureExercised": true,
    "failureFallbackVerified": true,
    "failureEvidenceID": "synthetic-failure-fallback-1",
    "failureObservedAt": "2026-08-07T00:11:00Z",
    "cancellationExercised": true,
    "cancellationOutcomeVerified": true,
    "cancellationEvidenceID": "synthetic-cancellation-1",
    "cancellationObservedAt": "2026-08-07T00:12:00Z",
    "evidenceNote": "Synthetic failure fallback and cancellation evidence; not release evidence."
  },
  "syntheticSample": true,
  "releaseEvidence": false
}
~~~

### Step 2: Run the red contract test

Run the explicit `EvaluationValidationTests` Swift Testing suite:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --filter EvaluationValidationTests --no-parallel
~~~

Expected failure class: the test target compiles, then fails with missing
EvaluationCorpus, CandidateRun, EvaluationValidator, and supporting contract
symbols because the new model and validator declarations do not yet exist. If
the test target cannot locate the fixture, that is also a red failure until the
checked-in fixture path is created; no test may substitute inline transcript
data.

### Step 3: Add the public versioned contracts

Append the following declarations to EvaluationModels.swift. Every property is
mutable so decoded test mutations are possible; every type has an explicit
public initializer and the listed conformances. JSON uses the default
lower-camel-case property names and the enum raw values shown below.

~~~swift
public enum EvaluationSeverity: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case error
  case warning
}

public enum ProtectedMatchMode: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case exactCase
  case caseInsensitive
  case numericExact
  case negationExact
}

public enum AudioConsentStatus: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case approved
  case revoked
  case pending
}

public enum CaptureTemperature: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case cold
  case warm
}

public enum ThermalState: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical
}

public enum ManualAdjudicationStatus: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case notRequired
  case pending
  case passed
  case failed
}

public enum EvaluationMetricKind: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case englishWordErrorRate
  case mandarinCharacterErrorRate
  case protectedTermAccuracy
}

public struct EvaluationTextSlice: Codable, Equatable, Sendable {
  public var language: EvaluationLanguageMode
  public var text: String

  public init(language: EvaluationLanguageMode, text: String) {
    self.language = language
    self.text = text
  }
}

public struct ProtectedExpectation: Codable, Equatable, Sendable {
  public var id: String
  public var term: String
  public var mode: ProtectedMatchMode
  public var language: EvaluationLanguageMode

  public init(
    id: String,
    term: String,
    mode: ProtectedMatchMode,
    language: EvaluationLanguageMode
  ) {
    self.id = id
    self.term = term
    self.mode = mode
    self.language = language
  }
}

public struct AudioProvenance: Codable, Equatable, Sendable {
  public var assetSHA256: String
  public var source: String
  public var license: String
  public var approved: Bool
  public var speakerLanguage: String
  public var speakerAccent: String?
  public var privacyReview: String
  public var revocationProcess: String

  public init(
    assetSHA256: String,
    source: String,
    license: String,
    approved: Bool,
    speakerLanguage: String,
    speakerAccent: String?,
    privacyReview: String,
    revocationProcess: String
  ) {
    self.assetSHA256 = assetSHA256
    self.source = source
    self.license = license
    self.approved = approved
    self.speakerLanguage = speakerLanguage
    self.speakerAccent = speakerAccent
    self.privacyReview = privacyReview
    self.revocationProcess = revocationProcess
  }
}

public struct AudioConsent: Codable, Equatable, Sendable {
  public var status: AudioConsentStatus
  public var recordID: String
  public var reviewer: String?
  public var reviewedAt: String?

  public init(
    status: AudioConsentStatus,
    recordID: String,
    reviewer: String?,
    reviewedAt: String?
  ) {
    self.status = status
    self.recordID = recordID
    self.reviewer = reviewer
    self.reviewedAt = reviewedAt
  }
}

public struct StandardBaselineIdentity: Codable, Equatable, Sendable {
  public var baselineID: String
  public var baselineRevision: String
  public var engine: String
  public var modelRevision: String
  public var corpusID: String
  public var corpusRevision: String
  public var osVersion: String
  public var hardwareModel: String
  public var architecture: String
  public var appBuild: String
  public var coldObservationCount: Int
  public var warmObservationCount: Int
  public var recordedAt: String

  public init(
    baselineID: String,
    baselineRevision: String,
    engine: String,
    modelRevision: String,
    corpusID: String,
    corpusRevision: String,
    osVersion: String,
    hardwareModel: String,
    architecture: String,
    appBuild: String,
    coldObservationCount: Int,
    warmObservationCount: Int,
    recordedAt: String
  ) {
    self.baselineID = baselineID
    self.baselineRevision = baselineRevision
    self.engine = engine
    self.modelRevision = modelRevision
    self.corpusID = corpusID
    self.corpusRevision = corpusRevision
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.architecture = architecture
    self.appBuild = appBuild
    self.coldObservationCount = coldObservationCount
    self.warmObservationCount = warmObservationCount
    self.recordedAt = recordedAt
  }
}

public struct StandardBaselineMetric: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var metric: EvaluationMetricKind
  public var value: Double

  public init(
    scope: EvaluationLanguageMode,
    metric: EvaluationMetricKind,
    value: Double
  ) {
    self.scope = scope
    self.metric = metric
    self.value = value
  }
}

public struct StandardBaselineEvidence: Codable, Equatable, Sendable {
  public var identity: StandardBaselineIdentity
  public var metrics: [StandardBaselineMetric]

  public init(
    identity: StandardBaselineIdentity,
    metrics: [StandardBaselineMetric]
  ) {
    self.identity = identity
    self.metrics = metrics
  }
}

public struct UnloadEvidence: Codable, Equatable, Sendable {
  public var unloadAttempted: Bool
  public var unloadSucceeded: Bool
  public var memoryAfterUnloadBytes: Int64
  public var observedAt: String

  public init(
    unloadAttempted: Bool,
    unloadSucceeded: Bool,
    memoryAfterUnloadBytes: Int64,
    observedAt: String
  ) {
    self.unloadAttempted = unloadAttempted
    self.unloadSucceeded = unloadSucceeded
    self.memoryAfterUnloadBytes = memoryAfterUnloadBytes
    self.observedAt = observedAt
  }
}

public struct CorpusProvenance: Codable, Equatable, Sendable {
  public var sourceType: String
  public var createdAt: String
  public var owner: String
  public var privacyReview: String
  public var audioPolicy: String

  public init(
    sourceType: String,
    createdAt: String,
    owner: String,
    privacyReview: String,
    audioPolicy: String
  ) {
    self.sourceType = sourceType
    self.createdAt = createdAt
    self.owner = owner
    self.privacyReview = privacyReview
    self.audioPolicy = audioPolicy
  }
}

public struct EvaluationCase: Codable, Equatable, Sendable {
  public var id: String
  public var language: EvaluationLanguageMode
  public var categories: [String]
  public var referenceText: String
  public var spokenText: String
  public var audioAsset: String?
  public var audioProvenance: AudioProvenance?
  public var audioConsent: AudioConsent?
  public var conditions: [String]
  public var protectedExpectations: [ProtectedExpectation]
  public var metricReferenceSlices: [EvaluationTextSlice]

  public init(
    id: String,
    language: EvaluationLanguageMode,
    categories: [String],
    referenceText: String,
    spokenText: String,
    audioAsset: String?,
    audioProvenance: AudioProvenance?,
    audioConsent: AudioConsent?,
    conditions: [String],
    protectedExpectations: [ProtectedExpectation],
    metricReferenceSlices: [EvaluationTextSlice]
  ) {
    self.id = id
    self.language = language
    self.categories = categories
    self.referenceText = referenceText
    self.spokenText = spokenText
    self.audioAsset = audioAsset
    self.audioProvenance = audioProvenance
    self.audioConsent = audioConsent
    self.conditions = conditions
    self.protectedExpectations = protectedExpectations
    self.metricReferenceSlices = metricReferenceSlices
  }
}

public struct EvaluationCorpus: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var corpusID: String
  public var revision: String
  public var provenance: CorpusProvenance
  public var cases: [EvaluationCase]

  public init(
    schemaVersion: Int,
    corpusID: String,
    revision: String,
    provenance: CorpusProvenance,
    cases: [EvaluationCase]
  ) {
    self.schemaVersion = schemaVersion
    self.corpusID = corpusID
    self.revision = revision
    self.provenance = provenance
    self.cases = cases
  }
}

public struct CandidateIdentity: Codable, Equatable, Sendable {
  public var candidateID: String
  public var displayName: String
  public var modelID: String
  public var modelRevision: String
  public var runtimeName: String
  public var runtimeRevision: String
  public var licenseReview: String

  public init(
    candidateID: String,
    displayName: String,
    modelID: String,
    modelRevision: String,
    runtimeName: String,
    runtimeRevision: String,
    licenseReview: String
  ) {
    self.candidateID = candidateID
    self.displayName = displayName
    self.modelID = modelID
    self.modelRevision = modelRevision
    self.runtimeName = runtimeName
    self.runtimeRevision = runtimeRevision
    self.licenseReview = licenseReview
  }
}

public struct RunEnvironment: Codable, Equatable, Sendable {
  public var osVersion: String
  public var hardwareModel: String
  public var architecture: String
  public var appBuild: String
  public var swiftVersion: String
  public var recordedAt: String

  public init(
    osVersion: String,
    hardwareModel: String,
    architecture: String,
    appBuild: String,
    swiftVersion: String,
    recordedAt: String
  ) {
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.architecture = architecture
    self.appBuild = appBuild
    self.swiftVersion = swiftVersion
    self.recordedAt = recordedAt
  }
}

public struct LatencyMeasurement: Codable, Equatable, Sendable {
  public var coldLoadMilliseconds: Double?
  public var asrMilliseconds: Double
  public var cleanupMilliseconds: Double
  public var endToEndMilliseconds: Double

  public init(
    coldLoadMilliseconds: Double?,
    asrMilliseconds: Double,
    cleanupMilliseconds: Double,
    endToEndMilliseconds: Double
  ) {
    self.coldLoadMilliseconds = coldLoadMilliseconds
    self.asrMilliseconds = asrMilliseconds
    self.cleanupMilliseconds = cleanupMilliseconds
    self.endToEndMilliseconds = endToEndMilliseconds
  }
}

public struct ResourceMeasurement: Codable, Equatable, Sendable {
  public var peakMemoryBytes: Int64
  public var idleMemoryBytes: Int64
  public var thermalState: ThermalState
  public var energyImpact: Double
  public var modelDownloadBytes: Int64
  public var modelInstalledBytes: Int64

  public init(
    peakMemoryBytes: Int64,
    idleMemoryBytes: Int64,
    thermalState: ThermalState,
    energyImpact: Double,
    modelDownloadBytes: Int64,
    modelInstalledBytes: Int64
  ) {
    self.peakMemoryBytes = peakMemoryBytes
    self.idleMemoryBytes = idleMemoryBytes
    self.thermalState = thermalState
    self.energyImpact = energyImpact
    self.modelDownloadBytes = modelDownloadBytes
    self.modelInstalledBytes = modelInstalledBytes
  }
}

public struct OfflineEvidence: Codable, Equatable, Sendable {
  public var networkDisabled: Bool
  public var networkRequestsObserved: Int
  public var contentTelemetryObserved: Bool
  public var isolationMethod: String
  public var startedAt: String
  public var endedAt: String
  public var evidenceNote: String

  public init(
    networkDisabled: Bool,
    networkRequestsObserved: Int,
    contentTelemetryObserved: Bool,
    isolationMethod: String,
    startedAt: String,
    endedAt: String,
    evidenceNote: String
  ) {
    self.networkDisabled = networkDisabled
    self.networkRequestsObserved = networkRequestsObserved
    self.contentTelemetryObserved = contentTelemetryObserved
    self.isolationMethod = isolationMethod
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.evidenceNote = evidenceNote
  }
}

public struct FailureCancellationEvidence: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var failureExercised: Bool
  public var failureFallbackVerified: Bool
  public var failureEvidenceID: String
  public var failureObservedAt: String
  public var cancellationExercised: Bool
  public var cancellationOutcomeVerified: Bool
  public var cancellationEvidenceID: String
  public var cancellationObservedAt: String
  public var evidenceNote: String

  public init(
    schemaVersion: Int,
    failureExercised: Bool,
    failureFallbackVerified: Bool,
    failureEvidenceID: String,
    failureObservedAt: String,
    cancellationExercised: Bool,
    cancellationOutcomeVerified: Bool,
    cancellationEvidenceID: String,
    cancellationObservedAt: String,
    evidenceNote: String
  ) {
    self.schemaVersion = schemaVersion
    self.failureExercised = failureExercised
    self.failureFallbackVerified = failureFallbackVerified
    self.failureEvidenceID = failureEvidenceID
    self.failureObservedAt = failureObservedAt
    self.cancellationExercised = cancellationExercised
    self.cancellationOutcomeVerified = cancellationOutcomeVerified
    self.cancellationEvidenceID = cancellationEvidenceID
    self.cancellationObservedAt = cancellationObservedAt
    self.evidenceNote = evidenceNote
  }
}

public struct ManualAdjudication: Codable, Equatable, Sendable {
  public var status: ManualAdjudicationStatus
  public var reviewer: String?
  public var notes: String?

  public init(
    status: ManualAdjudicationStatus,
    reviewer: String?,
    notes: String?
  ) {
    self.status = status
    self.reviewer = reviewer
    self.notes = notes
  }
}

public struct UtteranceResult: Codable, Equatable, Sendable {
  public var observationID: String
  public var caseID: String
  public var language: EvaluationLanguageMode
  public var artifactOrder: [TranscriptArtifactKind]
  public var asrRaw: String
  public var dictionaryBaseline: String?
  public var cleanedResult: String?
  public var captureTemperature: CaptureTemperature
  public var latency: LatencyMeasurement
  public var resources: ResourceMeasurement
  public var metricHypothesisSlices: [EvaluationTextSlice]
  public var manualAdjudication: ManualAdjudication?

  public init(
    observationID: String,
    caseID: String,
    language: EvaluationLanguageMode,
    artifactOrder: [TranscriptArtifactKind],
    asrRaw: String,
    dictionaryBaseline: String?,
    cleanedResult: String?,
    captureTemperature: CaptureTemperature,
    latency: LatencyMeasurement,
    resources: ResourceMeasurement,
    metricHypothesisSlices: [EvaluationTextSlice],
    manualAdjudication: ManualAdjudication?
  ) {
    self.observationID = observationID
    self.caseID = caseID
    self.language = language
    self.artifactOrder = artifactOrder
    self.asrRaw = asrRaw
    self.dictionaryBaseline = dictionaryBaseline
    self.cleanedResult = cleanedResult
    self.captureTemperature = captureTemperature
    self.latency = latency
    self.resources = resources
    self.metricHypothesisSlices = metricHypothesisSlices
    self.manualAdjudication = manualAdjudication
  }
}

public struct CandidateRun: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var runID: String
  public var corpusID: String
  public var corpusRevision: String
  public var candidate: CandidateIdentity
  public var environment: RunEnvironment
  public var standardBaseline: StandardBaselineEvidence
  public var unloadEvidence: UnloadEvidence
  public var results: [UtteranceResult]
  public var offlineEvidence: OfflineEvidence
  public var failureCancellationEvidence: FailureCancellationEvidence
  public var syntheticSample: Bool
  public var releaseEvidence: Bool

  public init(
    schemaVersion: Int,
    runID: String,
    corpusID: String,
    corpusRevision: String,
    candidate: CandidateIdentity,
    environment: RunEnvironment,
    standardBaseline: StandardBaselineEvidence,
    unloadEvidence: UnloadEvidence,
    results: [UtteranceResult],
    offlineEvidence: OfflineEvidence,
    failureCancellationEvidence: FailureCancellationEvidence,
    syntheticSample: Bool,
    releaseEvidence: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.runID = runID
    self.corpusID = corpusID
    self.corpusRevision = corpusRevision
    self.candidate = candidate
    self.environment = environment
    self.standardBaseline = standardBaseline
    self.unloadEvidence = unloadEvidence
    self.results = results
    self.offlineEvidence = offlineEvidence
    self.failureCancellationEvidence = failureCancellationEvidence
    self.syntheticSample = syntheticSample
    self.releaseEvidence = releaseEvidence
  }
}
~~~

### Step 4: Add fail-closed validation

Create EvaluationValidation.swift with the complete issue surface and these
rules. The implementation must use only Foundation and the Task 1 library;
it must not inspect or log transcript values.

~~~swift
import Foundation

public struct EvaluationIssue: Codable, Equatable, Sendable {
  public var code: String
  public var path: String
  public var message: String
  public var severity: EvaluationSeverity

  public init(
    code: String,
    path: String,
    message: String,
    severity: EvaluationSeverity = .error
  ) {
    self.code = code
    self.path = path
    self.message = message
    self.severity = severity
  }
}

public enum EvaluationValidator {
  public static func validate(
    corpus: EvaluationCorpus
  ) -> [EvaluationIssue] {
    var issues: [EvaluationIssue] = []
    if corpus.schemaVersion != 1 {
      issue(&issues, "unsupported_schema_version", "/schemaVersion",
        "Corpus schemaVersion must be 1.")
    }
    requireID(corpus.corpusID, "/corpusID", &issues)
    requireID(corpus.revision, "/revision", &issues)
    var seen: Set<String> = []
    for (index, item) in corpus.cases.enumerated() {
      let path = "/cases/\(index)"
      requireID(item.id, "\(path)/id", &issues)
      if !seen.insert(item.id).inserted, !item.id.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty {
        issue(&issues, "duplicate_case_id", "\(path)/id",
          "Case ID is duplicated.")
      }
      if item.categories.isEmpty || item.categories.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        issue(&issues, "missing_category", "\(path)/categories",
          "Each case needs a nonblank category.")
      }
      if item.referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "blank_reference", "\(path)/referenceText",
          "Reference text must be nonblank.")
      }
      if item.spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "blank_spoken_text", "\(path)/spokenText",
          "Spoken text must be nonblank.")
      }
      validateProtectedExpectations(
        item.protectedExpectations,
        caseLanguage: item.language,
        path: "\(path)/protectedExpectations",
        issues: &issues
      )
      validateSlices(
        item.metricReferenceSlices,
        expected: item.language,
        path: "\(path)/metricReferenceSlices",
        issues: &issues
      )
      validateAudio(item, path: path, issues: &issues)
    }
    return sorted(issues)
  }

  public static func validate(
    run: CandidateRun,
    against corpus: EvaluationCorpus
  ) -> [EvaluationIssue] {
    var issues = validate(corpus: corpus)
    requireID(run.runID, "/runID", &issues)
    requireID(run.candidate.candidateID, "/candidate/candidateID", &issues)
    requireID(run.candidate.displayName, "/candidate/displayName", &issues)
    requireID(run.candidate.modelID, "/candidate/modelID", &issues)
    requireID(run.candidate.modelRevision,
      "/candidate/modelRevision", &issues)
    requireID(run.candidate.runtimeName, "/candidate/runtimeName", &issues)
    requireID(run.candidate.runtimeRevision,
      "/candidate/runtimeRevision", &issues)
    requireID(run.candidate.licenseReview, "/candidate/licenseReview", &issues)
    requireID(run.environment.osVersion, "/environment/osVersion", &issues)
    requireID(run.environment.hardwareModel,
      "/environment/hardwareModel", &issues)
    requireID(run.environment.architecture, "/environment/architecture", &issues)
    requireID(run.environment.appBuild, "/environment/appBuild", &issues)
    requireID(run.environment.swiftVersion,
      "/environment/swiftVersion", &issues)
    requireID(run.environment.recordedAt, "/environment/recordedAt", &issues)
    if run.schemaVersion != 1 {
      issue(&issues, "unsupported_schema_version", "/schemaVersion",
        "Run schemaVersion must be 1.")
    }
    if run.corpusID != corpus.corpusID {
      issue(&issues, "corpus_run_mismatch", "/corpusID",
        "Run corpusID does not match the corpus.")
    }
    if run.corpusRevision != corpus.revision {
      issue(&issues, "corpus_run_mismatch", "/corpusRevision",
        "Run corpus revision does not match the corpus.")
    }
    validateStandardBaseline(
      run.standardBaseline,
      run: run,
      corpus: corpus,
      issues: &issues
    )
    validateUnloadEvidence(run.unloadEvidence, issues: &issues)
    validateOfflineEvidence(run.offlineEvidence, issues: &issues)
    validateFailureCancellationEvidence(
      run.failureCancellationEvidence,
      issues: &issues
    )
    if run.offlineEvidence.networkDisabled == false
      || run.offlineEvidence.networkRequestsObserved != 0
    {
      issue(&issues, "offline_network_observed",
        "/offlineEvidence/networkRequestsObserved",
        "Offline evidence does not prove zero network inference.")
    }
    if run.offlineEvidence.contentTelemetryObserved {
      issue(&issues, "content_telemetry",
        "/offlineEvidence/contentTelemetryObserved",
        "Content telemetry was observed.")
    }

    var casesByID: [String: EvaluationCase] = [:]
    for item in corpus.cases where casesByID[item.id] == nil {
      casesByID[item.id] = item
    }
    var seenObservationIDs: Set<String> = []
    var temperaturesByCase: [String: Set<CaptureTemperature>] = [:]
    for (index, result) in run.results.enumerated() {
      let path = "/results/\(index)"
      requireID(result.observationID, "\(path)/observationID", &issues)
      if !seenObservationIDs.insert(result.observationID).inserted {
        issue(&issues, "duplicate_observation_id",
          "\(path)/observationID", "Observation ID is duplicated.")
      }
      guard let item = casesByID[result.caseID] else {
        issue(&issues, "unknown_case_id", "\(path)/caseID",
          "Result case ID is not in the corpus.")
        continue
      }
      if result.language != item.language {
        issue(&issues, "language_mismatch", "\(path)/language",
          "Result language does not match its case.")
      }
      temperaturesByCase[result.caseID, default: []].insert(
        result.captureTemperature
      )
      if result.asrRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "missing_asr_raw", "\(path)/asrRaw",
          "ASR raw must be present.")
      }
      if result.dictionaryBaseline?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty == true {
        issue(&issues, "blank_dictionary_baseline",
          "\(path)/dictionaryBaseline",
          "Dictionary baseline must be nonblank when present.")
      }
      if result.cleanedResult?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty == true {
        issue(&issues, "blank_cleaned_result", "\(path)/cleanedResult",
          "Cleaned result must be nonblank when present.")
      }
      if result.cleanedResult != nil && result.dictionaryBaseline == nil {
        issue(&issues, "cleaned_without_baseline",
          "\(path)/cleanedResult",
          "Cleaned result requires a dictionary baseline.")
      }
      if let adjudication = result.manualAdjudication {
        if result.cleanedResult == nil && adjudication.status == .notRequired {
          // This is the only valid use of notRequired.
        } else if result.cleanedResult != nil
          && adjudication.status == .notRequired
        {
          issue(&issues, "manual_adjudication_not_required_with_cleanup",
            "\(path)/manualAdjudication/status",
            "A cleaned result requires passed, pending, or failed manual adjudication.")
        }
      }
      var expectedOrder: [TranscriptArtifactKind] = [.asrRaw]
      if result.dictionaryBaseline != nil || result.cleanedResult != nil {
        expectedOrder.append(.dictionaryBaseline)
      }
      if result.cleanedResult != nil {
        expectedOrder.append(.cleanedResult)
      }
      if result.artifactOrder != expectedOrder {
        issue(&issues, "invalid_artifact_order", "\(path)/artifactOrder",
          "Artifact order must be ASR raw, dictionary baseline, then cleaned result.")
      }
      validateSlices(
        result.metricHypothesisSlices,
        expected: item.language,
        path: "\(path)/metricHypothesisSlices",
        issues: &issues
      )
      validateMeasurements(result, path: path, issues: &issues)
    }
    for (index, item) in corpus.cases.enumerated() {
      let temperatures = temperaturesByCase[item.id, default: []]
      if !temperatures.contains(.cold) {
        issue(&issues, "missing_cold_observation",
          "/cases/\(index)/observations",
          "Each corpus case requires a cold observation.")
      }
      if !temperatures.contains(.warm) {
        issue(&issues, "missing_warm_observation",
          "/cases/\(index)/observations",
          "Each corpus case requires a warm observation.")
      }
    }
    if run.syntheticSample && run.releaseEvidence {
      issue(&issues, "synthetic_release_evidence", "/releaseEvidence",
        "Synthetic samples cannot claim release evidence.")
    }
    if !run.syntheticSample {
      for (index, item) in corpus.cases.enumerated()
        where !isAdmittedAudio(item)
      {
        issue(&issues, "real_audio_not_admitted",
          "/cases/\(index)/audioAsset",
          "Non-synthetic runs require admitted audio for every corpus case.")
      }
    }
    if run.releaseEvidence {
      if !run.unloadEvidence.unloadAttempted {
        issue(&issues, "unload_not_attempted",
          "/unloadEvidence/unloadAttempted",
          "Release evidence requires an unload attempt.")
      }
      if !run.unloadEvidence.unloadSucceeded {
        issue(&issues, "unload_not_verified",
          "/unloadEvidence/unloadSucceeded",
          "Release evidence requires verified unload behavior.")
      }
    }
    return sorted(issues)
  }

  private static func validateProtectedExpectations(
    _ expectations: [ProtectedExpectation],
    caseLanguage: EvaluationLanguageMode,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let allowedLanguages: Set<EvaluationLanguageMode> =
      caseLanguage == .mixed ? [.english, .mandarin] : [caseLanguage]
    var seenIDs: Set<String> = []
    for (index, expectation) in expectations.enumerated() {
      let itemPath = "\(path)/\(index)"
      let trimmedID = expectation.id.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if trimmedID.isEmpty {
        issue(&issues, "blank_protected_expectation_id",
          "\(itemPath)/id", "Protected expectation ID must be nonblank.")
      } else if !seenIDs.insert(trimmedID).inserted {
        issue(&issues, "duplicate_protected_expectation_id",
          "\(itemPath)/id", "Protected expectation ID is duplicated in its case.")
      }
      if expectation.term.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
      {
        issue(&issues, "blank_protected_term", "\(itemPath)/term",
          "Protected expectation term must be nonblank.")
      }
      if !allowedLanguages.contains(expectation.language) {
        issue(&issues, "protected_language_mismatch",
          "\(itemPath)/language",
          "Protected expectation language is not a member of the case language mode.")
      }
    }
  }

  private static func validateStandardBaseline(
    _ baseline: StandardBaselineEvidence,
    run: CandidateRun,
    corpus: EvaluationCorpus,
    issues: inout [EvaluationIssue]
  ) {
    requireID(baseline.identity.baselineID,
      "/standardBaseline/identity/baselineID", &issues)
    requireID(baseline.identity.baselineRevision,
      "/standardBaseline/identity/baselineRevision", &issues)
    requireID(baseline.identity.engine,
      "/standardBaseline/identity/engine", &issues)
    requireID(baseline.identity.modelRevision,
      "/standardBaseline/identity/modelRevision", &issues)
    requireID(baseline.identity.corpusID,
      "/standardBaseline/identity/corpusID", &issues)
    requireID(baseline.identity.corpusRevision,
      "/standardBaseline/identity/corpusRevision", &issues)
    requireID(baseline.identity.osVersion,
      "/standardBaseline/identity/osVersion", &issues)
    requireID(baseline.identity.hardwareModel,
      "/standardBaseline/identity/hardwareModel", &issues)
    requireID(baseline.identity.architecture,
      "/standardBaseline/identity/architecture", &issues)
    requireID(baseline.identity.appBuild,
      "/standardBaseline/identity/appBuild", &issues)
    requireID(baseline.identity.recordedAt,
      "/standardBaseline/identity/recordedAt", &issues)
    if baseline.identity.corpusID != corpus.corpusID
      || baseline.identity.corpusID != run.corpusID
    {
      issue(&issues, "baseline_corpus_mismatch",
        "/standardBaseline/identity/corpusID",
        "Standard baseline corpusID must match the candidate run and corpus.")
    }
    if baseline.identity.corpusRevision != corpus.revision
      || baseline.identity.corpusRevision != run.corpusRevision
    {
      issue(&issues, "baseline_corpus_mismatch",
        "/standardBaseline/identity/corpusRevision",
        "Standard baseline corpusRevision must match the candidate run and corpus.")
    }
    let environmentFields: [(String, String, String)] = [
      ("osVersion", baseline.identity.osVersion, run.environment.osVersion),
      ("hardwareModel", baseline.identity.hardwareModel, run.environment.hardwareModel),
      ("architecture", baseline.identity.architecture, run.environment.architecture),
      ("appBuild", baseline.identity.appBuild, run.environment.appBuild)
    ]
    for (field, baselineValue, runValue) in environmentFields
      where baselineValue != runValue
    {
      issue(&issues, "baseline_environment_mismatch",
        "/standardBaseline/identity/\(field)",
        "Standard baseline environment must match the candidate run.")
    }
    if baseline.identity.coldObservationCount <= 0 {
      issue(&issues, "invalid_baseline_coverage",
        "/standardBaseline/identity/coldObservationCount",
        "Standard baseline must include positive cold observation coverage.")
    }
    if baseline.identity.warmObservationCount <= 0 {
      issue(&issues, "invalid_baseline_coverage",
        "/standardBaseline/identity/warmObservationCount",
        "Standard baseline must include positive warm observation coverage.")
    }
    let required: Set<String> = [
      "english:englishWordErrorRate",
      "english:protectedTermAccuracy",
      "mandarin:mandarinCharacterErrorRate",
      "mandarin:protectedTermAccuracy",
      "mixed:englishWordErrorRate",
      "mixed:mandarinCharacterErrorRate",
      "mixed:protectedTermAccuracy"
    ]
    var seen: Set<String> = []
    let allowed: Set<String> = [
      "english:englishWordErrorRate",
      "english:protectedTermAccuracy",
      "mandarin:mandarinCharacterErrorRate",
      "mandarin:protectedTermAccuracy",
      "mixed:englishWordErrorRate",
      "mixed:mandarinCharacterErrorRate",
      "mixed:protectedTermAccuracy"
    ]
    for (index, metric) in baseline.metrics.enumerated() {
      let path = "/standardBaseline/metrics/\(index)"
      let key = "\(metric.scope.rawValue):\(metric.metric.rawValue)"
      if !allowed.contains(key) {
        issue(&issues, "invalid_standard_baseline_metric",
          "\(path)/metric",
          "Standard baseline metric is not valid for its scope.")
      }
      if !seen.insert(key).inserted {
        issue(&issues, "duplicate_standard_baseline_metric", path,
          "Standard baseline metric is duplicated.")
      }
      if !metric.value.isFinite {
        issue(&issues, "non_finite_standard_baseline_metric",
          "\(path)/value", "Standard baseline metric must be finite.")
      } else if metric.value < 0
        || (metric.metric == .protectedTermAccuracy && metric.value > 1)
      {
        issue(&issues, "invalid_standard_baseline_metric",
          "\(path)/value", "Standard baseline metric is outside its range.")
      }
    }
    for missing in required.subtracting(seen).sorted() {
      issue(&issues, "missing_standard_baseline_metric",
        "/standardBaseline/metrics",
        "Missing standard baseline metric \(missing).")
    }
  }

  private static func validateUnloadEvidence(
    _ evidence: UnloadEvidence,
    issues: inout [EvaluationIssue]
  ) {
    if evidence.memoryAfterUnloadBytes < 0 {
      issue(&issues, "negative_unload_memory",
        "/unloadEvidence/memoryAfterUnloadBytes",
        "Memory after unload must not be negative.")
    }
    requireID(evidence.observedAt, "/unloadEvidence/observedAt", &issues)
  }

  private static func validateOfflineEvidence(
    _ evidence: OfflineEvidence,
    issues: inout [EvaluationIssue]
  ) {
    requireID(evidence.isolationMethod,
      "/offlineEvidence/isolationMethod", &issues)
    requireID(evidence.startedAt, "/offlineEvidence/startedAt", &issues)
    requireID(evidence.endedAt, "/offlineEvidence/endedAt", &issues)
    requireID(evidence.evidenceNote, "/offlineEvidence/evidenceNote", &issues)
    if evidence.networkRequestsObserved < 0 {
      issue(&issues, "negative_measurement",
        "/offlineEvidence/networkRequestsObserved",
        "Network request count must not be negative.")
    }
    let formatter = ISO8601DateFormatter()
    guard let started = formatter.date(from: evidence.startedAt),
      let ended = formatter.date(from: evidence.endedAt)
    else {
      issue(&issues, "invalid_offline_timestamp",
        "/offlineEvidence",
        "Offline evidence timestamps must be ISO-8601.")
      return
    }
    if ended <= started {
      issue(&issues, "invalid_offline_interval",
        "/offlineEvidence/endedAt",
        "Offline evidence must end after it starts.")
    }
  }

  private static func validateFailureCancellationEvidence(
    _ evidence: FailureCancellationEvidence,
    issues: inout [EvaluationIssue]
  ) {
    if evidence.schemaVersion != 1 {
      issue(&issues, "unsupported_schema_version",
        "/failureCancellationEvidence/schemaVersion",
        "Failure/cancellation evidence schemaVersion must be 1.")
    }
    requireID(evidence.failureEvidenceID,
      "/failureCancellationEvidence/failureEvidenceID", &issues)
    requireID(evidence.failureObservedAt,
      "/failureCancellationEvidence/failureObservedAt", &issues)
    requireID(evidence.cancellationEvidenceID,
      "/failureCancellationEvidence/cancellationEvidenceID", &issues)
    requireID(evidence.cancellationObservedAt,
      "/failureCancellationEvidence/cancellationObservedAt", &issues)
    requireID(evidence.evidenceNote,
      "/failureCancellationEvidence/evidenceNote", &issues)
    let formatter = ISO8601DateFormatter()
    if formatter.date(from: evidence.failureObservedAt) == nil {
      issue(&issues, "invalid_failure_cancellation_timestamp",
        "/failureCancellationEvidence/failureObservedAt",
        "Failure evidence timestamp must be ISO-8601.")
    }
    if formatter.date(from: evidence.cancellationObservedAt) == nil {
      issue(&issues, "invalid_failure_cancellation_timestamp",
        "/failureCancellationEvidence/cancellationObservedAt",
        "Cancellation evidence timestamp must be ISO-8601.")
    }
  }

  private static func validateAudio(
    _ item: EvaluationCase,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let hasAsset = hasNonblankAudioAsset(item)
    if !hasAsset {
      if item.audioProvenance != nil {
        issue(&issues, "audio_provenance", "\(path)/audioProvenance",
          "Audio provenance requires an audio asset.")
      }
      if item.audioConsent != nil {
        issue(&issues, "audio_consent", "\(path)/audioConsent",
          "Audio consent requires an audio asset.")
      }
      return
    }
    let validProvenance: Bool = {
      guard let provenance = item.audioProvenance,
      provenance.approved,
      provenance.assetSHA256.range(
        of: "^[A-Fa-f0-9]{64}$",
        options: .regularExpression
      ) != nil,
      !provenance.source.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !provenance.license.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !provenance.privacyReview.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !provenance.revocationProcess.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      else {
        return false
      }
      return true
    }()
    if !validProvenance {
      issue(&issues, "audio_provenance", "\(path)/audioProvenance",
        "Audio provenance is not approved, hashed, licensed, and privacy-reviewed.")
    }
    let validConsent: Bool = {
      guard let consent = item.audioConsent,
        consent.status == .approved,
        !consent.recordID.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty,
        consent.reviewer?.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty == false,
        consent.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty == false
      else {
        return false
      }
      return true
    }()
    if !validConsent {
      issue(&issues, "audio_consent", "\(path)/audioConsent",
        "Admitted audio requires approved, recorded consent.")
    }
  }

  private static func isAdmittedAudio(_ item: EvaluationCase) -> Bool {
    var copy: [EvaluationIssue] = []
    validateAudio(item, path: "/case", issues: &copy)
    return hasNonblankAudioAsset(item) && copy.isEmpty
  }

  private static func hasNonblankAudioAsset(_ item: EvaluationCase) -> Bool {
    item.audioAsset?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty == false
  }

  private static func validateSlices(
    _ slices: [EvaluationTextSlice],
    expected: EvaluationLanguageMode,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let expectedLanguages: [EvaluationLanguageMode] =
      expected == .mixed ? [.english, .mandarin] : [expected]
    let actualLanguages = slices.map(\.language)
    if slices.isEmpty {
      issue(&issues, "missing_language", path,
        "At least one language-specific metric slice is required.")
      return
    }
    if actualLanguages != expectedLanguages {
      issue(&issues, "missing_language", path,
        "Metric slices must cover the declared language mode.")
    }
    if slices.contains(where: {
      $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issue(&issues, "invalid_metric_slices", path,
        "Metric slices must contain the language-specific nonblank text in order.")
    }
  }

  private static func validateMeasurements(
    _ result: UtteranceResult,
    path: String,
    issues: inout [EvaluationIssue]
  ) {
    let latency: [(String, Double)] = [
      ("asrMilliseconds", result.latency.asrMilliseconds),
      ("cleanupMilliseconds", result.latency.cleanupMilliseconds),
      ("endToEndMilliseconds", result.latency.endToEndMilliseconds)
    ]
    for (name, value) in latency {
      if !value.isFinite {
        issue(&issues, "non_finite_measurement",
          "\(path)/latency/\(name)", "Measurement must be finite.")
      } else if value < 0 {
        issue(&issues, "negative_measurement",
          "\(path)/latency/\(name)", "Measurement must not be negative.")
      }
    }
    if let cold = result.latency.coldLoadMilliseconds {
      if !cold.isFinite {
        issue(&issues, "non_finite_measurement",
          "\(path)/latency/coldLoadMilliseconds",
          "Measurement must be finite.")
      } else if cold < 0 {
        issue(&issues, "negative_measurement",
          "\(path)/latency/coldLoadMilliseconds",
          "Measurement must not be negative.")
      }
    }
    switch result.captureTemperature {
    case .cold:
      if result.latency.coldLoadMilliseconds == nil {
        issue(&issues, "missing_cold_load_measurement",
          "\(path)/latency/coldLoadMilliseconds",
          "Cold captures require a finite cold-load measurement.")
      }
    case .warm:
      if result.latency.coldLoadMilliseconds != nil {
        issue(&issues, "warm_cold_load_present",
          "\(path)/latency/coldLoadMilliseconds",
          "Warm captures must not include a cold-load measurement.")
      }
    }
    if !result.resources.energyImpact.isFinite {
      issue(&issues, "non_finite_measurement",
        "\(path)/resources/energyImpact", "Measurement must be finite.")
    } else if result.resources.energyImpact < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/energyImpact", "Measurement must not be negative.")
    }
    if result.resources.peakMemoryBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/peakMemoryBytes",
        "Measurement must not be negative.")
    }
    if result.resources.idleMemoryBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/idleMemoryBytes",
        "Measurement must not be negative.")
    }
    if result.resources.modelDownloadBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/modelDownloadBytes",
        "Measurement must not be negative.")
    }
    if result.resources.modelInstalledBytes < 0 {
      issue(&issues, "negative_measurement",
        "\(path)/resources/modelInstalledBytes",
        "Measurement must not be negative.")
    }
  }

  private static func requireID(
    _ value: String,
    _ path: String,
    _ issues: inout [EvaluationIssue]
  ) {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issue(&issues, "blank_id", path, "Stable ID must be nonblank.")
    }
  }

  private static func issue(
    _ issues: inout [EvaluationIssue],
    _ code: String,
    _ path: String,
    _ message: String
  ) {
    issues.append(EvaluationIssue(code: code, path: path, message: message))
  }

  private static func sorted(
    _ issues: [EvaluationIssue]
  ) -> [EvaluationIssue] {
    issues.sorted {
      if $0.path == $1.path { return $0.code < $1.code }
      return $0.path < $1.path
    }
  }
}
~~~

The validator must emit exact JSON pointer paths such as
/results/0/latency/asrMilliseconds and /results/0/resources/peakMemoryBytes.
It also emits stable paths for blank spoken text, malformed protected
expectations, blank optional artifacts, cleaned-without-baseline results,
manual-adjudication combinations, and cold/warm evidence mismatches. It
validates corpus issues before run lookup and uses a first-seen
map, so duplicate or otherwise invalid corpus IDs cannot trap run validation.
Observation IDs must be unique, case IDs may repeat, and every corpus case
must have at least one cold and one warm observation. Actual ASR benchmark mode
fails closed without an admitted, consented audio asset.

### Step 5: Add strict JSON Schemas

Create both schema files as draft 2020-12 schemas. Every object in each schema,
including every definition object, has additionalProperties: false. The
following exact schema fragments establish the shared contract; copy the
complete definitions into each named schema, with the corpus schema requiring
EvaluationCorpus and the run schema requiring CandidateRun.

~~~json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://fleck.local/schemas/local-dictation-evaluation-v1.schema.json",
  "title": "Fleck local dictation evaluation corpus v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "corpusID", "revision", "provenance", "cases"],
  "properties": {
    "schemaVersion": {"const": 1},
    "corpusID": {"type": "string", "minLength": 1},
    "revision": {"type": "string", "minLength": 1},
    "provenance": {"$ref": "#/$defs/CorpusProvenance"},
    "cases": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/EvaluationCase"}}
  },
  "$defs": {
    "EvaluationLanguageMode": {"type": "string", "enum": ["english", "mandarin", "mixed"]},
    "ProtectedMatchMode": {"type": "string", "enum": ["exactCase", "caseInsensitive", "numericExact", "negationExact"]},
    "ProtectedExpectation": {
      "type": "object", "additionalProperties": false,
      "required": ["id", "term", "mode", "language"],
      "properties": {
        "id": {"type": "string", "minLength": 1},
        "term": {"type": "string", "minLength": 1},
        "mode": {"$ref": "#/$defs/ProtectedMatchMode"},
        "language": {"$ref": "#/$defs/EvaluationLanguageMode"}
      }
    },
    "AudioProvenance": {
      "type": "object", "additionalProperties": false,
      "required": ["assetSHA256", "source", "license", "approved", "speakerLanguage", "speakerAccent", "privacyReview", "revocationProcess"],
      "properties": {
        "assetSHA256": {"type": "string", "pattern": "^[A-Fa-f0-9]{64}$"},
        "source": {"type": "string", "minLength": 1},
        "license": {"type": "string", "minLength": 1},
        "approved": {"type": "boolean"},
        "speakerLanguage": {"type": "string", "minLength": 1},
        "speakerAccent": {"type": ["string", "null"]},
        "privacyReview": {"type": "string", "minLength": 1},
        "revocationProcess": {"type": "string", "minLength": 1}
      }
    },
    "AudioConsent": {
      "type": "object", "additionalProperties": false,
      "required": ["status", "recordID", "reviewer", "reviewedAt"],
      "properties": {
        "status": {"type": "string", "enum": ["approved", "revoked", "pending"]},
        "recordID": {"type": "string", "minLength": 1},
        "reviewer": {"type": ["string", "null"]},
        "reviewedAt": {"type": ["string", "null"]}
      }
    },
    "CorpusProvenance": {
      "type": "object", "additionalProperties": false,
      "required": ["sourceType", "createdAt", "owner", "privacyReview", "audioPolicy"],
      "properties": {
        "sourceType": {"type": "string", "minLength": 1},
        "createdAt": {"type": "string", "minLength": 1},
        "owner": {"type": "string", "minLength": 1},
        "privacyReview": {"type": "string", "minLength": 1},
        "audioPolicy": {"type": "string", "minLength": 1}
      }
    },
    "EvaluationTextSlice": {
      "type": "object", "additionalProperties": false,
      "required": ["language", "text"],
      "properties": {
        "language": {"$ref": "#/$defs/EvaluationLanguageMode"},
        "text": {"type": "string", "minLength": 1}
      }
    },
    "EvaluationCase": {
      "type": "object", "additionalProperties": false,
      "required": ["id", "language", "categories", "referenceText", "spokenText", "audioAsset", "audioProvenance", "audioConsent", "conditions", "protectedExpectations", "metricReferenceSlices"],
      "properties": {
        "id": {"type": "string", "minLength": 1},
        "language": {"$ref": "#/$defs/EvaluationLanguageMode"},
        "categories": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
        "referenceText": {"type": "string", "minLength": 1},
        "spokenText": {"type": "string", "minLength": 1},
        "audioAsset": {
          "type": ["string", "null"],
          "description": "May be null for synthetic text-contract data; Swift validation requires admitted audio for every non-synthetic run regardless of releaseEvidence."
        },
        "audioProvenance": {"anyOf": [{"$ref": "#/$defs/AudioProvenance"}, {"type": "null"}]},
        "audioConsent": {"anyOf": [{"$ref": "#/$defs/AudioConsent"}, {"type": "null"}]},
        "conditions": {"type": "array", "items": {"type": "string"}},
        "protectedExpectations": {"type": "array", "items": {"$ref": "#/$defs/ProtectedExpectation"}},
        "metricReferenceSlices": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/EvaluationTextSlice"}}
      }
    }
  }
}
~~~

The run schema uses the following exact root, enum, and object definitions.
The two schemas intentionally duplicate their definitions so each file can be
validated independently:

~~~json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://fleck.local/schemas/local-dictation-run-v1.schema.json",
  "title": "Fleck local dictation candidate run v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "runID", "corpusID", "corpusRevision", "candidate", "environment", "standardBaseline", "unloadEvidence", "results", "offlineEvidence", "failureCancellationEvidence", "syntheticSample", "releaseEvidence"],
  "properties": {
    "schemaVersion": {"const": 1},
    "runID": {"type": "string", "minLength": 1},
    "corpusID": {"type": "string", "minLength": 1},
    "corpusRevision": {"type": "string", "minLength": 1},
    "candidate": {"$ref": "#/$defs/CandidateIdentity"},
    "environment": {"$ref": "#/$defs/RunEnvironment"},
    "standardBaseline": {"$ref": "#/$defs/StandardBaselineEvidence"},
    "unloadEvidence": {"$ref": "#/$defs/UnloadEvidence"},
    "results": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/UtteranceResult"}},
    "offlineEvidence": {"$ref": "#/$defs/OfflineEvidence"},
    "failureCancellationEvidence": {"$ref": "#/$defs/FailureCancellationEvidence"},
    "syntheticSample": {"type": "boolean"},
    "releaseEvidence": {"type": "boolean"}
  },
  "$defs": {
    "EvaluationLanguageMode": {"type": "string", "enum": ["english", "mandarin", "mixed"]},
    "TranscriptArtifactKind": {"type": "string", "enum": ["asrRaw", "dictionaryBaseline", "cleanedResult"]},
    "CaptureTemperature": {"type": "string", "enum": ["cold", "warm"]},
    "ThermalState": {"type": "string", "enum": ["nominal", "fair", "serious", "critical"]},
    "ManualAdjudicationStatus": {"type": "string", "enum": ["notRequired", "pending", "passed", "failed"]},
    "EvaluationMetricKind": {"type": "string", "enum": ["englishWordErrorRate", "mandarinCharacterErrorRate", "protectedTermAccuracy"]},
    "EvaluationTextSlice": {
      "type": "object", "additionalProperties": false,
      "required": ["language", "text"],
      "properties": {
        "language": {"$ref": "#/$defs/EvaluationLanguageMode"},
        "text": {"type": "string", "minLength": 1}
      }
    },
    "CandidateIdentity": {
      "type": "object", "additionalProperties": false,
      "required": ["candidateID", "displayName", "modelID", "modelRevision", "runtimeName", "runtimeRevision", "licenseReview"],
      "properties": {
        "candidateID": {"type": "string", "minLength": 1},
        "displayName": {"type": "string", "minLength": 1},
        "modelID": {"type": "string", "minLength": 1},
        "modelRevision": {"type": "string", "minLength": 1},
        "runtimeName": {"type": "string", "minLength": 1},
        "runtimeRevision": {"type": "string", "minLength": 1},
        "licenseReview": {"type": "string", "minLength": 1}
      }
    },
    "RunEnvironment": {
      "type": "object", "additionalProperties": false,
      "required": ["osVersion", "hardwareModel", "architecture", "appBuild", "swiftVersion", "recordedAt"],
      "properties": {
        "osVersion": {"type": "string", "minLength": 1},
        "hardwareModel": {"type": "string", "minLength": 1},
        "architecture": {"type": "string", "minLength": 1},
        "appBuild": {"type": "string", "minLength": 1},
        "swiftVersion": {"type": "string", "minLength": 1},
        "recordedAt": {"type": "string", "minLength": 1}
      }
    },
    "StandardBaselineIdentity": {
      "type": "object", "additionalProperties": false,
      "required": ["baselineID", "baselineRevision", "engine", "modelRevision", "corpusID", "corpusRevision", "osVersion", "hardwareModel", "architecture", "appBuild", "coldObservationCount", "warmObservationCount", "recordedAt"],
      "properties": {
        "baselineID": {"type": "string", "minLength": 1},
        "baselineRevision": {"type": "string", "minLength": 1},
        "engine": {"type": "string", "minLength": 1},
        "modelRevision": {"type": "string", "minLength": 1},
        "corpusID": {"type": "string", "minLength": 1},
        "corpusRevision": {"type": "string", "minLength": 1},
        "osVersion": {"type": "string", "minLength": 1},
        "hardwareModel": {"type": "string", "minLength": 1},
        "architecture": {"type": "string", "minLength": 1},
        "appBuild": {"type": "string", "minLength": 1},
        "coldObservationCount": {"type": "integer", "minimum": 1},
        "warmObservationCount": {"type": "integer", "minimum": 1},
        "recordedAt": {"type": "string", "minLength": 1}
      }
    },
    "StandardBaselineMetric": {
      "type": "object", "additionalProperties": false,
      "required": ["scope", "metric", "value"],
      "properties": {
        "scope": {"$ref": "#/$defs/EvaluationLanguageMode"},
        "metric": {"$ref": "#/$defs/EvaluationMetricKind"},
        "value": {"type": "number", "minimum": 0}
      }
    },
    "StandardBaselineEvidence": {
      "type": "object", "additionalProperties": false,
      "required": ["identity", "metrics"],
      "properties": {
        "identity": {"$ref": "#/$defs/StandardBaselineIdentity"},
        "metrics": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/StandardBaselineMetric"}}
      }
    },
    "UnloadEvidence": {
      "type": "object", "additionalProperties": false,
      "required": ["unloadAttempted", "unloadSucceeded", "memoryAfterUnloadBytes", "observedAt"],
      "properties": {
        "unloadAttempted": {"type": "boolean"},
        "unloadSucceeded": {"type": "boolean"},
        "memoryAfterUnloadBytes": {"type": "integer", "minimum": 0},
        "observedAt": {"type": "string", "minLength": 1}
      }
    },
    "LatencyMeasurement": {
      "type": "object", "additionalProperties": false,
      "required": ["coldLoadMilliseconds", "asrMilliseconds", "cleanupMilliseconds", "endToEndMilliseconds"],
      "properties": {
        "coldLoadMilliseconds": {"type": ["number", "null"], "minimum": 0},
        "asrMilliseconds": {"type": "number", "minimum": 0},
        "cleanupMilliseconds": {"type": "number", "minimum": 0},
        "endToEndMilliseconds": {"type": "number", "minimum": 0}
      }
    },
    "ResourceMeasurement": {
      "type": "object", "additionalProperties": false,
      "required": ["peakMemoryBytes", "idleMemoryBytes", "thermalState", "energyImpact", "modelDownloadBytes", "modelInstalledBytes"],
      "properties": {
        "peakMemoryBytes": {"type": "integer", "minimum": 0},
        "idleMemoryBytes": {"type": "integer", "minimum": 0},
        "thermalState": {"$ref": "#/$defs/ThermalState"},
        "energyImpact": {"type": "number", "minimum": 0},
        "modelDownloadBytes": {"type": "integer", "minimum": 0},
        "modelInstalledBytes": {"type": "integer", "minimum": 0}
      }
    },
    "OfflineEvidence": {
      "type": "object", "additionalProperties": false,
      "required": ["networkDisabled", "networkRequestsObserved", "contentTelemetryObserved", "isolationMethod", "startedAt", "endedAt", "evidenceNote"],
      "properties": {
        "networkDisabled": {"type": "boolean"},
        "networkRequestsObserved": {"type": "integer", "minimum": 0},
        "contentTelemetryObserved": {"type": "boolean"},
        "isolationMethod": {"type": "string", "minLength": 1},
        "startedAt": {"type": "string", "minLength": 1},
        "endedAt": {"type": "string", "minLength": 1},
        "evidenceNote": {"type": "string", "minLength": 1}
      }
    },
    "FailureCancellationEvidence": {
      "type": "object", "additionalProperties": false,
      "required": ["schemaVersion", "failureExercised", "failureFallbackVerified", "failureEvidenceID", "failureObservedAt", "cancellationExercised", "cancellationOutcomeVerified", "cancellationEvidenceID", "cancellationObservedAt", "evidenceNote"],
      "properties": {
        "schemaVersion": {"const": 1},
        "failureExercised": {"type": "boolean"},
        "failureFallbackVerified": {"type": "boolean"},
        "failureEvidenceID": {"type": "string", "minLength": 1},
        "failureObservedAt": {"type": "string", "minLength": 1},
        "cancellationExercised": {"type": "boolean"},
        "cancellationOutcomeVerified": {"type": "boolean"},
        "cancellationEvidenceID": {"type": "string", "minLength": 1},
        "cancellationObservedAt": {"type": "string", "minLength": 1},
        "evidenceNote": {"type": "string", "minLength": 1}
      }
    },
    "ManualAdjudication": {
      "type": "object", "additionalProperties": false,
      "required": ["status", "reviewer", "notes"],
      "properties": {
        "status": {"$ref": "#/$defs/ManualAdjudicationStatus"},
        "reviewer": {"type": ["string", "null"]},
        "notes": {"type": ["string", "null"]}
      }
    },
    "UtteranceResult": {
      "type": "object", "additionalProperties": false,
      "required": ["observationID", "caseID", "language", "artifactOrder", "asrRaw", "dictionaryBaseline", "cleanedResult", "captureTemperature", "latency", "resources", "metricHypothesisSlices", "manualAdjudication"],
      "properties": {
        "observationID": {"type": "string", "minLength": 1},
        "caseID": {"type": "string", "minLength": 1},
        "language": {"$ref": "#/$defs/EvaluationLanguageMode"},
        "artifactOrder": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/TranscriptArtifactKind"}},
        "asrRaw": {"type": "string", "minLength": 1},
        "dictionaryBaseline": {"anyOf": [{"type": "string", "minLength": 1}, {"type": "null"}]},
        "cleanedResult": {"anyOf": [{"type": "string", "minLength": 1}, {"type": "null"}]},
        "captureTemperature": {"$ref": "#/$defs/CaptureTemperature"},
        "latency": {"$ref": "#/$defs/LatencyMeasurement"},
        "resources": {"$ref": "#/$defs/ResourceMeasurement"},
        "metricHypothesisSlices": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/EvaluationTextSlice"}},
        "manualAdjudication": {"anyOf": [{"$ref": "#/$defs/ManualAdjudication"}, {"type": "null"}]}
      }
    }
  }
}
~~~

The Swift validator is authoritative for cross-object relations and finite
floating-point values; JSON Schema remains the structural contract. Schemas
must reject unknown keys, blank required strings, negative numeric values, and
wrong enum values. JSON does not carry NaN or infinity, so the Swift validator
retains the explicit non-finite check for in-memory runs.

The corpus schema intentionally permits a null audioAsset because the checked-in
Phase A text-contract fixture is synthetic and audio-free. Cross-object Swift
validation treats every run with syntheticSample false as a real benchmark,
regardless of releaseEvidence, and requires admitted audio for every corpus
case, reporting real_audio_not_admitted when that prerequisite is missing.
releaseEvidence remains the separate gate for release-only claims such as
unload verification and release eligibility.

FailureCancellationEvidence booleans are valid measurements even when false;
the validator checks their version, non-content identifiers, timestamps, and
note, while Task 3's fixed failure-cancellation-behavior outcome fails when
either behavior is not exercised and verified. A missing run-level evidence
object fails schema decoding. Standard baseline corpus/environment mismatches
and nonpositive cold/warm baseline coverage are validation errors, so material
improvement is never calculated from incomparable evidence. A cleaned result
without a baseline, blank optional artifact strings, or any artifact order
other than raw -> dictionary baseline -> cleaned result is invalid. An absent
or pending manual adjudication remains valid input and produces reviewRequired;
notRequired with cleanup is the only invalid manual-adjudication combination.

### Step 6: Run the green contract checks

Run the explicit `EvaluationValidationTests` Swift Testing suite:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --filter EvaluationValidationTests --no-parallel
~~~

Expected: PASS for fixture decoding, exact issue code/path mutations,
malformed spoken/protected contracts, duplicate-ID and whitespace-audio
fail-closed behavior, non-synthetic audio-free validation even when
releaseEvidence is false, artifact ordering and baseline retention, cold/warm
evidence, duplicate observation detection, manual-adjudication contract,
comparable Standard-baseline identity and coverage, failure/cancellation
evidence, unload/offline evidence validation, result/corpus matching, offline
fail-closed behavior, measurement validation, and synthetic evidence refusal.

Run the package-wide check:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --no-parallel
~~~

Expected: PASS for Task 1 and Task 2 tests without resolving or changing root
dependencies.

### Step 7: Scope-check and commit Task 2

Run:

~~~sh
git diff --check
git status --short --branch
git diff --name-only
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
~~~

Expected: only the seven Task 2 paths plus the five already committed Task 1
paths are present; the root package files have no diff. Stage only the seven
Task 2 paths and commit:

~~~sh
git add \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationValidation.swift \
  Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationValidationTests.swift \
  Tests/Fixtures/local-dictation-evaluation-v1.schema.json \
  Tests/Fixtures/local-dictation-run-v1.schema.json \
  Tests/Fixtures/local-dictation-evaluation-v1.json \
  Tests/Fixtures/local-dictation-run-sample-v1.json
git commit -m "feat: define local dictation evaluation contracts"
~~~

Expected: one focused contract commit with no source, root package, existing
fixture, or shared integration file in its scope.

---

## Task 3: Deterministic report generation and CLI

**Files:**

- Create: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationReport.swift
- Modify: Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift
- Create: Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationReportTests.swift
- Create: Scripts/evaluate-local-dictation.sh

**Interfaces:**

- Add public Codable, Sendable, and Equatable EvaluationGate with caller-supplied
  maxima, minima, and allowed thermal states for English WER, Mandarin CER,
  English and Mandarin components of the mixed scope, protected terms,
  numbers, negations, cleanup preservation, cold/warm latency, peak and idle
  memory, post-unload memory, energy, model download size, model installed
  size, and standard-baseline material improvement. The library supplies no
  product thresholds.
- Add the exact throwing entry point
  EvaluationReportBuilder.build(corpus:run:gate:) throws -> EvaluationReport.
- Add deterministic report value types for language metrics, protected-term
  outcomes, cleanup/manual review, latency, resource and unload evidence,
  versioned Standard Apple baseline comparison, artifact completeness,
  offline evidence, failure/cancellation behavior evidence, gate outcomes,
  and release decision. The report must expose the validated Standard baseline
  model revision, corpus ID/revision, OS, hardware, architecture, app build,
  and positive cold/warm baseline observation counts as non-content audit
  fields.
- Aggregate repeated observations in corpus case order and then stable
  observationID order. Sum EditCounts within each case for its audit counts,
  then calculate each language error rate as the unweighted mean of the
  case-level aggregate error rates so extra trials cannot overweight a case.
  Protected expectations are denominated as expectation occurrences across
  observations, with case order and observation order preserved. Latency
  p50/p95 and resource maxima use every admitted observation.
- Mixed scope reports separate English WER and Mandarin CER. Its gate passes
  only when both component outcomes pass; no blended mixed score is emitted.
- A release decision is eligible only when syntheticSample is false,
  releaseEvidence is true, all required evidence and gates pass, and every
  cleaned observation has explicit ManualAdjudicationStatus.passed. A run
  with releaseEvidence false is notEligible regardless of metrics. This does
  not relax audio admission: every non-synthetic run must use admitted audio
  before report building, so the corresponding regression uses
  admitted(try reportCorpus()).

The gate file is a versioned JSON object with additionalProperties false and
exactly these required fields: schemaVersion,
maxEnglishWordErrorRate, maxMandarinCharacterErrorRate,
maxMixedEnglishWordErrorRate, maxMixedMandarinCharacterErrorRate,
minimumProtectedTermAccuracy, maximumNumberFailures,
maximumNegationFailures, maximumCleanupPreservationFailures,
maxColdLatencyMilliseconds, maxWarmLatencyMilliseconds, maxPeakMemoryBytes,
maxIdleMemoryBytes, maxPostUnloadMemoryBytes, maxEnergyImpact,
maxModelDownloadBytes, maxModelInstalledBytes,
minimumStandardMaterialImprovement, and allowedThermalStates. Its Swift
Codable type must reject unknown or missing fields through a strict
additional-key decoding test, and its validator must reject nonfinite,
negative, empty, or out-of-range values before any transcript is read.
- Add the exact CLI commands and exit codes:

  ~~~text
  validate-corpus --corpus PATH
  validate-run --corpus PATH --run PATH
  report --corpus PATH --run PATH --gate PATH --output PATH
  ~~~

  Exit code 0 means valid input and a written report, including a synthetic
  report that is explicitly not eligible. Exit code 2 means invalid arguments,
  schema, or input. Exit code 3 means a non-synthetic gate failure or required
  manual review. Exit code 4 means I/O or internal failure.

The report always includes the fixed `failure-cancellation-behavior` outcome;
it is not a caller-configurable threshold. A release run is eligible only when
its versioned failure/cancellation evidence proves both failure fallback and
cancellation behavior, in addition to the numeric gates.

### Step 1: Create report tests and the exact gate contract before implementation

Create EvaluationReportTests.swift. It reuses the Task 2 fixture loader
behavior and contains these complete tests. The in-memory admitted corpus
helper changes metadata only; it does not create or read an audio file.

~~~swift
import Foundation
import Testing
@testable import LocalDictationEvaluation

private func reportFixture(_ name: String) throws -> Data {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<8 {
    let candidate = url
      .deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/\(name)")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return try Data(contentsOf: candidate)
    }
    url.deleteLastPathComponent()
  }
  Issue.record("Missing fixture \(name)")
  return Data()
}

private func reportCorpus() throws -> EvaluationCorpus {
  try JSONDecoder().decode(
    EvaluationCorpus.self,
    from: reportFixture("local-dictation-evaluation-v1.json")
  )
}

private func reportRun() throws -> CandidateRun {
  try JSONDecoder().decode(
    CandidateRun.self,
    from: reportFixture("local-dictation-run-sample-v1.json")
  )
}

private func reportGate(
  maxEnglish: Double = 0.25,
  maxMandarin: Double = 0.25,
  maxMixedEnglish: Double = 0.30,
  maxMixedMandarin: Double = 0.30,
  minimumProtected: Double = 0.90,
  maximumNumberFailures: Int = 0,
  maximumNegationFailures: Int = 0,
  maximumCleanupFailures: Int = 0,
  maxCold: Double = 2_000,
  maxWarm: Double = 500,
  maxPeak: Int64 = 2_000_000_000,
  maxIdle: Int64 = 500_000_000,
  maxPostUnload: Int64 = 500_000_000,
  maxEnergy: Double = 2.0,
  maxDownload: Int64 = 2_000_000_000,
  maxInstalled: Int64 = 2_000_000_000,
  minimumStandardImprovement: Double = 0.10,
  thermal: [ThermalState] = [.nominal, .fair]
) -> EvaluationGate {
  EvaluationGate(
    schemaVersion: 1,
    maxEnglishWordErrorRate: maxEnglish,
    maxMandarinCharacterErrorRate: maxMandarin,
    maxMixedEnglishWordErrorRate: maxMixedEnglish,
    maxMixedMandarinCharacterErrorRate: maxMixedMandarin,
    minimumProtectedTermAccuracy: minimumProtected,
    maximumNumberFailures: maximumNumberFailures,
    maximumNegationFailures: maximumNegationFailures,
    maximumCleanupPreservationFailures: maximumCleanupFailures,
    maxColdLatencyMilliseconds: maxCold,
    maxWarmLatencyMilliseconds: maxWarm,
    maxPeakMemoryBytes: maxPeak,
    maxIdleMemoryBytes: maxIdle,
    maxPostUnloadMemoryBytes: maxPostUnload,
    maxEnergyImpact: maxEnergy,
    maxModelDownloadBytes: maxDownload,
    maxModelInstalledBytes: maxInstalled,
    minimumStandardMaterialImprovement: minimumStandardImprovement,
    allowedThermalStates: thermal
  )
}

private func admitted(_ source: EvaluationCorpus) -> EvaluationCorpus {
  var corpus = source
  for index in corpus.cases.indices {
    let id = corpus.cases[index].id
    corpus.cases[index].audioAsset = "admitted-test-\(id).wav"
    corpus.cases[index].audioProvenance = AudioProvenance(
      assetSHA256: String(repeating: "a", count: 64),
      source: "test metadata only",
      license: "test license",
      approved: true,
      speakerLanguage: corpus.cases[index].language.rawValue,
      speakerAccent: nil,
      privacyReview: "test metadata contains no audio",
      revocationProcess: "remove test asset metadata"
    )
    corpus.cases[index].audioConsent = AudioConsent(
      status: .approved,
      recordID: "test-consent-\(id)",
      reviewer: "test",
      reviewedAt: "2026-08-07T00:00:00Z"
    )
  }
  return corpus
}

@Suite("EvaluationReportTests")
struct EvaluationReportTests {

@Test func syntheticReportIsWatermarkedAndNotEligible() throws {
  let report = try EvaluationReportBuilder.build(
    corpus: try reportCorpus(),
    run: try reportRun(),
    gate: reportGate()
  )
  #expect(report.releaseDecision == .notEligible)
  #expect(
    String(
      report.markdown.split(
        separator: "\n",
        omittingEmptySubsequences: false
      ).first ?? ""
    ) == "SAMPLE DATA — NOT MODEL EVIDENCE"
  )
  #expect(report.markdown.contains("Synthetic sample cannot satisfy a release gate."))
  #expect(!report.markdown.contains("fixInputMonitor"))
  #expect(!report.markdown.contains("请在星期五"))
}

@Test func reportMarkdownIsDeterministicAndHasFixedSectionOrder() throws {
  let corpus = try reportCorpus()
  let run = try reportRun()
  let first = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  let second = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  #expect(first == second)
  #expect(first.markdown == second.markdown)
  let headings = [
    "## Candidate",
    "## Language Metrics",
    "## Standard Baseline Comparison",
    "## Protected Expectations",
    "## Cleanup Preservation",
    "## Latency",
    "## Resources",
    "## Artifacts",
    "## Failure and Cancellation",
    "## Offline Evidence",
    "## Gate Outcomes",
    "## Decision"
  ]
  var previous = -1
  for heading in headings {
    let current = first.markdown.range(of: heading)!.lowerBound
    let offset = first.markdown.distance(
      from: first.markdown.startIndex,
      to: current
    )
    #expect(offset > previous)
    previous = offset
  }
}

@Test func reportKeepsEnglishAndMandarinMetricsSeparateForMixedCases() throws {
  let report = try EvaluationReportBuilder.build(
    corpus: try reportCorpus(),
    run: try reportRun(),
    gate: reportGate()
  )
  #expect(report.languageMetrics.contains {
    $0.scope == .mixed
      && $0.language == .english
      && $0.metric == .wordErrorRate
  })
  #expect(report.languageMetrics.contains {
    $0.scope == .mixed
      && $0.language == .mandarin
      && $0.metric == .characterErrorRate
  })
  #expect(!report.languageMetrics.contains {
    $0.scope == .mixed && $0.language == .mixed
  })
}

@Test func repeatedObservationsHaveDeterministicCaseBalancedAggregation() throws {
  var corpus = try reportCorpus()
  var run = try reportRun()
  let extraCase = EvaluationCase(
    id: "english-case-balance-extra",
    language: .english,
    categories: ["english-prose"],
    referenceText: "alpha beta",
    spokenText: "alpha beta",
    audioAsset: nil,
    audioProvenance: nil,
    audioConsent: nil,
    conditions: ["synthetic"],
    protectedExpectations: [],
    metricReferenceSlices: [
      EvaluationTextSlice(language: .english, text: "alpha beta")
    ]
  )
  guard let englishCase = corpus.cases.first(where: {
    $0.id == "english-developer-command"
  }) else {
    Issue.record("Missing English reference case")
    return
  }
  let existingEnglishIndices = run.results.indices.filter {
    run.results[$0].caseID == englishCase.id
  }
  guard existingEnglishIndices.count == 2 else {
    Issue.record("Expected two existing English observations")
    return
  }
  for index in existingEnglishIndices {
    run.results[index].metricHypothesisSlices =
      englishCase.metricReferenceSlices
  }
  corpus.cases.append(extraCase)
  let extraResources = run.results[existingEnglishIndices[0]].resources
  // The two existing English observations are set to the exact reference
  // slice above, so their aggregate WER is 0 and they contribute 2 * 39 = 78
  // reference units. Each extra observation has one deletion over two
  // reference words, so its three-observation aggregate WER is 3 / 6 = 0.5.
  run.results.append(contentsOf: [
    UtteranceResult(
      observationID: "english-case-balance-extra-cold",
      caseID: extraCase.id,
      language: .english,
      artifactOrder: [.asrRaw],
      asrRaw: "alpha",
      dictionaryBaseline: nil,
      cleanedResult: nil,
      captureTemperature: .cold,
      latency: LatencyMeasurement(
        coldLoadMilliseconds: 100,
        asrMilliseconds: 20,
        cleanupMilliseconds: 0,
        endToEndMilliseconds: 120
      ),
      resources: extraResources,
      metricHypothesisSlices: [
        EvaluationTextSlice(language: .english, text: "alpha")
      ],
      manualAdjudication: nil
    ),
    UtteranceResult(
      observationID: "english-case-balance-extra-warm-1",
      caseID: extraCase.id,
      language: .english,
      artifactOrder: [.asrRaw],
      asrRaw: "alpha",
      dictionaryBaseline: nil,
      cleanedResult: nil,
      captureTemperature: .warm,
      latency: LatencyMeasurement(
        coldLoadMilliseconds: nil,
        asrMilliseconds: 20,
        cleanupMilliseconds: 0,
        endToEndMilliseconds: 20
      ),
      resources: extraResources,
      metricHypothesisSlices: [
        EvaluationTextSlice(language: .english, text: "alpha")
      ],
      manualAdjudication: nil
    ),
    UtteranceResult(
      observationID: "english-case-balance-extra-warm-2",
      caseID: extraCase.id,
      language: .english,
      artifactOrder: [.asrRaw],
      asrRaw: "alpha",
      dictionaryBaseline: nil,
      cleanedResult: nil,
      captureTemperature: .warm,
      latency: LatencyMeasurement(
        coldLoadMilliseconds: nil,
        asrMilliseconds: 20,
        cleanupMilliseconds: 0,
        endToEndMilliseconds: 20
      ),
      resources: extraResources,
      metricHypothesisSlices: [
        EvaluationTextSlice(language: .english, text: "alpha")
      ],
      manualAdjudication: nil
    )
  ])
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  guard let english = report.languageMetrics.first(where: {
    $0.scope == .english && $0.language == .english
  }) else {
    Issue.record("Missing English language summary")
    return
  }
  #expect(english.caseCount == 2)
  #expect(english.observationCount == 5)
  #expect(english.counts.deletions == 3)
  #expect(english.counts.referenceUnits == 84)
  let caseBalancedErrorRate = (0.0 + 0.5) / 2.0
  #expect(caseBalancedErrorRate == 0.25)
  #expect(english.errorRate == caseBalancedErrorRate)
  #expect(english.aggregation.contains("unweighted mean"))
  let observationWeightedErrorRate = (0.0 + 0.0 + 0.5 + 0.5 + 0.5) / 5.0
  #expect(observationWeightedErrorRate == 0.3)
  #expect(english.errorRate != observationWeightedErrorRate)
  #expect(report.languageMetrics.filter { $0.scope != .english }.allSatisfy {
    $0.caseCount == 1 && $0.observationCount == 2
      && $0.aggregation.contains("unweighted mean")
  })
  #expect(report.latency.coldCount == 4)
  #expect(report.latency.warmCount == 5)
  #expect(report.resources.observationCount == 9)
  #expect(report.standardComparison.metrics.count == 7)
  #expect(report.standardComparison.baselineModelRevision
    == "AppleSpeechCapture-standard-v1-synthetic")
  #expect(report.standardComparison.corpusID
    == "local-dictation-evaluation-v1")
  #expect(report.standardComparison.corpusRevision == "text-contract-v1")
  #expect(report.standardComparison.osVersion == "synthetic")
  #expect(report.standardComparison.hardwareModel == "synthetic")
  #expect(report.standardComparison.architecture == "arm64")
  #expect(report.standardComparison.appBuild == "synthetic")
  #expect(report.standardComparison.coldObservationCount == 3)
  #expect(report.standardComparison.warmObservationCount == 3)
  #expect(report.failureCancellation.failureExercised)
  #expect(report.failureCancellation.failureFallbackVerified)
  #expect(report.failureCancellation.cancellationExercised)
  #expect(report.failureCancellation.cancellationOutcomeVerified)
}

@Test func nonSyntheticWithoutReleaseEvidenceIsNotEligible() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = false
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  #expect(report.releaseDecision == .notEligible)
  #expect(report.markdown.contains(
    "Release evidence was not asserted; metrics cannot make this run eligible."
  ))
}

@Test func incomparableBaselineCannotProduceMaterialImprovement() throws {
  var run = try reportRun()
  run.standardBaseline.identity.appBuild = "different-build"
  #expect(throws: EvaluationReportError.self) {
    _ = try EvaluationReportBuilder.build(
      corpus: try reportCorpus(),
      run: run,
      gate: reportGate()
    )
  }
}

@Test func gatePassAndFailAreExplicitAndHaveNoThresholdDefaults() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = true
  let passing = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  #expect(passing.gateOutcomes.contains { $0.id == "english-wer" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "mixed-language" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "peak-memory" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "idle-memory" && $0.passed })
  #expect(passing.gateOutcomes.contains { $0.id == "energy" && $0.passed })
  #expect(passing.gateOutcomes.contains {
    $0.id == "model-download-size" && $0.passed
  })
  #expect(passing.gateOutcomes.contains {
    $0.id == "standard-improvement-mixed" && $0.passed
  })
  #expect(passing.gateOutcomes.contains { $0.id == "unload-behavior" && $0.passed })
  #expect(passing.gateOutcomes.contains {
    $0.id == "failure-cancellation-behavior" && $0.passed
  })

  let failing = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate(maxEnglish: 0, maxPeak: 1, maxIdle: 1, maxEnergy: 0)
  )
  #expect(failing.releaseDecision == .failed)
  #expect(failing.gateOutcomes.contains { $0.id == "english-wer" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "peak-memory" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "idle-memory" && !$0.passed })
  #expect(failing.gateOutcomes.contains { $0.id == "energy" && !$0.passed })
}

@Test func unverifiedFailureOrCancellationFailsReleaseGate() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = true
  run.failureCancellationEvidence.failureExercised = false
  run.failureCancellationEvidence.failureFallbackVerified = false
  let failure = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  #expect(failure.releaseDecision == .failed)
  #expect(failure.gateOutcomes.contains {
    $0.id == "failure-cancellation-behavior" && !$0.passed
  })

  run.failureCancellationEvidence.failureFallbackVerified = true
  run.failureCancellationEvidence.cancellationExercised = false
  run.failureCancellationEvidence.cancellationOutcomeVerified = false
  let cancellation = try EvaluationReportBuilder.build(
    corpus: corpus, run: run, gate: reportGate()
  )
  #expect(cancellation.releaseDecision == .failed)
  #expect(cancellation.gateOutcomes.contains {
    $0.id == "failure-cancellation-behavior" && !$0.passed
  })
}

@Test func absentManualAdjudicationRequiresReviewAndNeverProvesMeaning() throws {
  let corpus = admitted(try reportCorpus())
  var run = try reportRun()
  run.syntheticSample = false
  run.releaseEvidence = true
  run.results[0].manualAdjudication = nil
  let report = try EvaluationReportBuilder.build(
    corpus: corpus,
    run: run,
    gate: reportGate()
  )
  #expect(report.cleanupPreservation.manualReviewRequired > 0)
  #expect(report.releaseDecision == .reviewRequired)
  #expect(report.markdown.contains("Manual adjudication is required"))
  #expect(report.markdown.contains("Metrics do not prove semantic fidelity."))
}

@Test func pendingAndFailedCleanupAdjudicationHaveDistinctPrecedence() throws {
  let corpus = admitted(try reportCorpus())
  var pendingRun = try reportRun()
  pendingRun.syntheticSample = false
  pendingRun.releaseEvidence = true
  pendingRun.results[0].manualAdjudication = ManualAdjudication(
    status: .pending,
    reviewer: nil,
    notes: nil
  )
  let pending = try EvaluationReportBuilder.build(
    corpus: corpus, run: pendingRun, gate: reportGate()
  )
  #expect(pending.releaseDecision == .reviewRequired)

  var failedRun = pendingRun
  failedRun.results[0].manualAdjudication = ManualAdjudication(
    status: .failed,
    reviewer: "reviewer",
    notes: "meaning changed"
  )
  let failed = try EvaluationReportBuilder.build(
    corpus: corpus, run: failedRun, gate: reportGate()
  )
  #expect(failed.releaseDecision == .failed)
}

@Test func invalidDiagnosticsNeverContainTranscriptContent() throws {
  let corpus = try reportCorpus()
  var run = try reportRun()
  let secret = "PRIVATE_TRANSCRIPT_SHOULD_NOT_BE_LOGGED"
  run.results[0].asrRaw = secret
  run.results[0].dictionaryBaseline = nil
  run.results[0].cleanedResult = " "
  run.results[0].artifactOrder = [.asrRaw, .cleanedResult]
  do {
    _ = try EvaluationReportBuilder.build(
      corpus: corpus,
      run: run,
      gate: reportGate()
    )
    Issue.record("Expected invalid artifact ordering")
  } catch let error as EvaluationReportError {
    #expect(!String(describing: error).contains(secret))
    #expect(!String(describing: error).contains("PRIVATE_TRANSCRIPT"))
    if case .invalid(let issues) = error {
      #expect(issues.contains {
        $0.code == "cleaned_without_baseline"
          && $0.path == "/results/0/cleanedResult"
      })
      #expect(issues.contains {
        $0.code == "blank_cleaned_result"
          && $0.path == "/results/0/cleanedResult"
      })
    } else {
      Issue.record("Expected validation issues")
    }
  }
}

@Test func gateJSONUsesOnlyThePredeclaredCallerSuppliedFields() throws {
  let data = Data(
    """
    {
      "schemaVersion": 1,
      "maxEnglishWordErrorRate": 0.2,
      "maxMandarinCharacterErrorRate": 0.2,
      "maxMixedEnglishWordErrorRate": 0.3,
      "maxMixedMandarinCharacterErrorRate": 0.3,
      "minimumProtectedTermAccuracy": 0.9,
      "maximumNumberFailures": 0,
      "maximumNegationFailures": 0,
      "maximumCleanupPreservationFailures": 0,
      "maxColdLatencyMilliseconds": 2000,
      "maxWarmLatencyMilliseconds": 500,
      "maxPeakMemoryBytes": 2000000000,
      "maxIdleMemoryBytes": 500000000,
      "maxPostUnloadMemoryBytes": 500000000,
      "maxEnergyImpact": 2.0,
      "maxModelDownloadBytes": 2000000000,
      "maxModelInstalledBytes": 2000000000,
      "minimumStandardMaterialImprovement": 0.1,
      "allowedThermalStates": ["nominal", "fair"]
    }
    """.utf8
  )
  let decoded = try JSONDecoder().decode(EvaluationGate.self, from: data)
  #expect(decoded == reportGate(
    maxEnglish: 0.2,
    maxMandarin: 0.2,
    maxMixedEnglish: 0.3,
    maxMixedMandarin: 0.3,
    minimumProtected: 0.9,
    maximumNumberFailures: 0,
    maximumNegationFailures: 0,
    maximumCleanupFailures: 0,
    maxCold: 2000,
    maxWarm: 500,
    maxPeak: 2_000_000_000,
    maxIdle: 500_000_000,
    maxPostUnload: 500_000_000,
    maxEnergy: 2.0,
    maxDownload: 2_000_000_000,
    maxInstalled: 2_000_000_000,
    minimumStandardImprovement: 0.1,
    thermal: [.nominal, .fair]
  ))
}

@Test func gateJSONRejectsUnknownFieldsAndInvalidValues() throws {
  var object: [String: Any] = [
    "schemaVersion": 1,
    "maxEnglishWordErrorRate": 0.2,
    "maxMandarinCharacterErrorRate": 0.2,
    "maxMixedEnglishWordErrorRate": 0.3,
    "maxMixedMandarinCharacterErrorRate": 0.3,
    "minimumProtectedTermAccuracy": 0.9,
    "maximumNumberFailures": 0,
    "maximumNegationFailures": 0,
    "maximumCleanupPreservationFailures": 0,
    "maxColdLatencyMilliseconds": 2000,
    "maxWarmLatencyMilliseconds": 500,
    "maxPeakMemoryBytes": 2000000000,
    "maxIdleMemoryBytes": 500000000,
    "maxPostUnloadMemoryBytes": 500000000,
    "maxEnergyImpact": 2.0,
    "maxModelDownloadBytes": 2000000000,
    "maxModelInstalledBytes": 2000000000,
    "minimumStandardMaterialImprovement": 0.1,
    "allowedThermalStates": ["nominal", "fair"]
  ]
  object["unexpected"] = true
  let data = try JSONSerialization.data(withJSONObject: object)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(EvaluationGate.self, from: data)
  }
  var invalid = reportGate()
  invalid.maxIdleMemoryBytes = -1
  #expect(throws: EvaluationReportError.self) {
    _ = try EvaluationReportBuilder.build(
      corpus: try reportCorpus(), run: try reportRun(), gate: invalid
    )
  }
}

@Test func atomicReportWriteReplacesExistingTarget() throws {
  let target = FileManager.default.temporaryDirectory
    .appendingPathComponent("local-dictation-report-\(UUID().uuidString).md")
  defer { try? FileManager.default.removeItem(at: target) }
  try Data("old report".utf8).write(to: target)
  try EvaluationReportWriter.atomicWrite("new report", to: target)
  #expect(
    String(data: try Data(contentsOf: target), encoding: .utf8) == "new report"
  )
}
}
~~~

### Step 2: Run the red report test

Run the explicit `EvaluationReportTests` Swift Testing suite:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --filter EvaluationReportTests --no-parallel
~~~

Expected failure class: the test target reports missing EvaluationGate,
EvaluationReportBuilder, EvaluationReport, and report summary symbols. No
report is generated and no transcript content is printed.

### Step 3: Implement the report value types and gate

Create EvaluationReport.swift with these exact public types and fields. All
types are Codable, Equatable, and Sendable; all fields are public var with
explicit public initializers. The enum raw values are part of the report
contract.

~~~swift
import Foundation

public struct EvaluationGate: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var maxEnglishWordErrorRate: Double
  public var maxMandarinCharacterErrorRate: Double
  public var maxMixedEnglishWordErrorRate: Double
  public var maxMixedMandarinCharacterErrorRate: Double
  public var minimumProtectedTermAccuracy: Double
  public var maximumNumberFailures: Int
  public var maximumNegationFailures: Int
  public var maximumCleanupPreservationFailures: Int
  public var maxColdLatencyMilliseconds: Double
  public var maxWarmLatencyMilliseconds: Double
  public var maxPeakMemoryBytes: Int64
  public var maxIdleMemoryBytes: Int64
  public var maxPostUnloadMemoryBytes: Int64
  public var maxEnergyImpact: Double
  public var maxModelDownloadBytes: Int64
  public var maxModelInstalledBytes: Int64
  public var minimumStandardMaterialImprovement: Double
  public var allowedThermalStates: [ThermalState]

  public init(
    schemaVersion: Int,
    maxEnglishWordErrorRate: Double,
    maxMandarinCharacterErrorRate: Double,
    maxMixedEnglishWordErrorRate: Double,
    maxMixedMandarinCharacterErrorRate: Double,
    minimumProtectedTermAccuracy: Double,
    maximumNumberFailures: Int,
    maximumNegationFailures: Int,
    maximumCleanupPreservationFailures: Int,
    maxColdLatencyMilliseconds: Double,
    maxWarmLatencyMilliseconds: Double,
    maxPeakMemoryBytes: Int64,
    maxIdleMemoryBytes: Int64,
    maxPostUnloadMemoryBytes: Int64,
    maxEnergyImpact: Double,
    maxModelDownloadBytes: Int64,
    maxModelInstalledBytes: Int64,
    minimumStandardMaterialImprovement: Double,
    allowedThermalStates: [ThermalState]
  ) {
    self.schemaVersion = schemaVersion
    self.maxEnglishWordErrorRate = maxEnglishWordErrorRate
    self.maxMandarinCharacterErrorRate = maxMandarinCharacterErrorRate
    self.maxMixedEnglishWordErrorRate = maxMixedEnglishWordErrorRate
    self.maxMixedMandarinCharacterErrorRate = maxMixedMandarinCharacterErrorRate
    self.minimumProtectedTermAccuracy = minimumProtectedTermAccuracy
    self.maximumNumberFailures = maximumNumberFailures
    self.maximumNegationFailures = maximumNegationFailures
    self.maximumCleanupPreservationFailures = maximumCleanupPreservationFailures
    self.maxColdLatencyMilliseconds = maxColdLatencyMilliseconds
    self.maxWarmLatencyMilliseconds = maxWarmLatencyMilliseconds
    self.maxPeakMemoryBytes = maxPeakMemoryBytes
    self.maxIdleMemoryBytes = maxIdleMemoryBytes
    self.maxPostUnloadMemoryBytes = maxPostUnloadMemoryBytes
    self.maxEnergyImpact = maxEnergyImpact
    self.maxModelDownloadBytes = maxModelDownloadBytes
    self.maxModelInstalledBytes = maxModelInstalledBytes
    self.minimumStandardMaterialImprovement = minimumStandardMaterialImprovement
    self.allowedThermalStates = allowedThermalStates
  }
}

~~~

EvaluationGate must use the following explicit Decodable implementation rather
than synthesized decoding so the gate file is fail-closed. It defines all
nineteen root fields, rejects the first unknown key in decoder order, and
decodes every known field from the typed container. The gate tests must
exercise both an unknown key and an in-memory negative limit.

~~~swift
private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

extension EvaluationGate {
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case maxEnglishWordErrorRate
    case maxMandarinCharacterErrorRate
    case maxMixedEnglishWordErrorRate
    case maxMixedMandarinCharacterErrorRate
    case minimumProtectedTermAccuracy
    case maximumNumberFailures
    case maximumNegationFailures
    case maximumCleanupPreservationFailures
    case maxColdLatencyMilliseconds
    case maxWarmLatencyMilliseconds
    case maxPeakMemoryBytes
    case maxIdleMemoryBytes
    case maxPostUnloadMemoryBytes
    case maxEnergyImpact
    case maxModelDownloadBytes
    case maxModelInstalledBytes
    case minimumStandardMaterialImprovement
    case allowedThermalStates
  }

  public init(from decoder: Decoder) throws {
    let all = try decoder.container(keyedBy: AnyCodingKey.self)
    let allowed = Set(CodingKeys.allCases.map(\.stringValue))
    if let unknown = all.allKeys.first(where: {
      !allowed.contains($0.stringValue)
    }) {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath + [unknown],
          debugDescription: "Unknown EvaluationGate key \(unknown.stringValue)."
        )
      )
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
      maxEnglishWordErrorRate: try container.decode(
        Double.self, forKey: .maxEnglishWordErrorRate
      ),
      maxMandarinCharacterErrorRate: try container.decode(
        Double.self, forKey: .maxMandarinCharacterErrorRate
      ),
      maxMixedEnglishWordErrorRate: try container.decode(
        Double.self, forKey: .maxMixedEnglishWordErrorRate
      ),
      maxMixedMandarinCharacterErrorRate: try container.decode(
        Double.self, forKey: .maxMixedMandarinCharacterErrorRate
      ),
      minimumProtectedTermAccuracy: try container.decode(
        Double.self, forKey: .minimumProtectedTermAccuracy
      ),
      maximumNumberFailures: try container.decode(
        Int.self, forKey: .maximumNumberFailures
      ),
      maximumNegationFailures: try container.decode(
        Int.self, forKey: .maximumNegationFailures
      ),
      maximumCleanupPreservationFailures: try container.decode(
        Int.self, forKey: .maximumCleanupPreservationFailures
      ),
      maxColdLatencyMilliseconds: try container.decode(
        Double.self, forKey: .maxColdLatencyMilliseconds
      ),
      maxWarmLatencyMilliseconds: try container.decode(
        Double.self, forKey: .maxWarmLatencyMilliseconds
      ),
      maxPeakMemoryBytes: try container.decode(
        Int64.self, forKey: .maxPeakMemoryBytes
      ),
      maxIdleMemoryBytes: try container.decode(
        Int64.self, forKey: .maxIdleMemoryBytes
      ),
      maxPostUnloadMemoryBytes: try container.decode(
        Int64.self, forKey: .maxPostUnloadMemoryBytes
      ),
      maxEnergyImpact: try container.decode(
        Double.self, forKey: .maxEnergyImpact
      ),
      maxModelDownloadBytes: try container.decode(
        Int64.self, forKey: .maxModelDownloadBytes
      ),
      maxModelInstalledBytes: try container.decode(
        Int64.self, forKey: .maxModelInstalledBytes
      ),
      minimumStandardMaterialImprovement: try container.decode(
        Double.self, forKey: .minimumStandardMaterialImprovement
      ),
      allowedThermalStates: try container.decode(
        [ThermalState].self, forKey: .allowedThermalStates
      )
    )
  }
}
~~~

~~~swift
public enum ReportMetric: String, Codable, Equatable, Sendable {
  case wordErrorRate
  case characterErrorRate
}

public enum ReleaseDecision: String, Codable, Equatable, Sendable {
  case passed
  case failed
  case reviewRequired
  case notEligible
}

public struct LanguageMetricSummary: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var language: EvaluationLanguageMode
  public var metric: ReportMetric
  public var caseCount: Int
  public var observationCount: Int
  public var counts: EditCounts
  public var errorRate: Double
  public var aggregation: String

  public init(
    scope: EvaluationLanguageMode,
    language: EvaluationLanguageMode,
    metric: ReportMetric,
    caseCount: Int,
    observationCount: Int,
    counts: EditCounts,
    errorRate: Double,
    aggregation: String
  ) {
    self.scope = scope
    self.language = language
    self.metric = metric
    self.caseCount = caseCount
    self.observationCount = observationCount
    self.counts = counts
    self.errorRate = errorRate
    self.aggregation = aggregation
  }
}

public struct ProtectedExpectationSummary: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var caseCount: Int
  public var observationCount: Int
  public var total: Int
  public var passed: Int
  public var failed: Int
  public var accuracy: Double
  public var numberFailures: Int
  public var negationFailures: Int

  public init(
    scope: EvaluationLanguageMode,
    caseCount: Int,
    observationCount: Int,
    total: Int,
    passed: Int,
    failed: Int,
    accuracy: Double,
    numberFailures: Int,
    negationFailures: Int
  ) {
    self.scope = scope
    self.caseCount = caseCount
    self.observationCount = observationCount
    self.total = total
    self.passed = passed
    self.failed = failed
    self.accuracy = accuracy
    self.numberFailures = numberFailures
    self.negationFailures = negationFailures
  }
}

public struct CleanupPreservationSummary: Codable, Equatable, Sendable {
  public var resultsWithCleanup: Int
  public var preservationFailures: Int
  public var manualReviewRequired: Int
  public var meaningProvenAutomatically: Bool

  public init(
    resultsWithCleanup: Int,
    preservationFailures: Int,
    manualReviewRequired: Int,
    meaningProvenAutomatically: Bool
  ) {
    self.resultsWithCleanup = resultsWithCleanup
    self.preservationFailures = preservationFailures
    self.manualReviewRequired = manualReviewRequired
    self.meaningProvenAutomatically = meaningProvenAutomatically
  }
}

public struct LatencySummary: Codable, Equatable, Sendable {
  public var coldCount: Int
  public var warmCount: Int
  public var coldP50Milliseconds: Double?
  public var coldP95Milliseconds: Double?
  public var warmP50Milliseconds: Double?
  public var warmP95Milliseconds: Double?

  public init(
    coldCount: Int,
    warmCount: Int,
    coldP50Milliseconds: Double?,
    coldP95Milliseconds: Double?,
    warmP50Milliseconds: Double?,
    warmP95Milliseconds: Double?
  ) {
    self.coldCount = coldCount
    self.warmCount = warmCount
    self.coldP50Milliseconds = coldP50Milliseconds
    self.coldP95Milliseconds = coldP95Milliseconds
    self.warmP50Milliseconds = warmP50Milliseconds
    self.warmP95Milliseconds = warmP95Milliseconds
  }
}

public struct ResourceSummary: Codable, Equatable, Sendable {
  public var maximumPeakMemoryBytes: Int64
  public var maximumIdleMemoryBytes: Int64
  public var maximumPostUnloadMemoryBytes: Int64
  public var maximumEnergyImpact: Double
  public var maximumModelDownloadBytes: Int64
  public var maximumModelInstalledBytes: Int64
  public var unloadAttempted: Bool
  public var unloadSucceeded: Bool
  public var thermalStates: [ThermalState]
  public var observationCount: Int

  public init(
    maximumPeakMemoryBytes: Int64,
    maximumIdleMemoryBytes: Int64,
    maximumPostUnloadMemoryBytes: Int64,
    maximumEnergyImpact: Double,
    maximumModelDownloadBytes: Int64,
    maximumModelInstalledBytes: Int64,
    unloadAttempted: Bool,
    unloadSucceeded: Bool,
    thermalStates: [ThermalState],
    observationCount: Int
  ) {
    self.maximumPeakMemoryBytes = maximumPeakMemoryBytes
    self.maximumIdleMemoryBytes = maximumIdleMemoryBytes
    self.maximumPostUnloadMemoryBytes = maximumPostUnloadMemoryBytes
    self.maximumEnergyImpact = maximumEnergyImpact
    self.maximumModelDownloadBytes = maximumModelDownloadBytes
    self.maximumModelInstalledBytes = maximumModelInstalledBytes
    self.unloadAttempted = unloadAttempted
    self.unloadSucceeded = unloadSucceeded
    self.thermalStates = thermalStates
    self.observationCount = observationCount
  }
}

public struct ArtifactCompletenessSummary: Codable, Equatable, Sendable {
  public var totalObservations: Int
  public var asrRawObservationCount: Int
  public var dictionaryBaselineObservationCount: Int
  public var cleanedResultObservationCount: Int

  public init(
    totalObservations: Int,
    asrRawObservationCount: Int,
    dictionaryBaselineObservationCount: Int,
    cleanedResultObservationCount: Int
  ) {
    self.totalObservations = totalObservations
    self.asrRawObservationCount = asrRawObservationCount
    self.dictionaryBaselineObservationCount =
      dictionaryBaselineObservationCount
    self.cleanedResultObservationCount = cleanedResultObservationCount
  }
}

public struct OfflineSummary: Codable, Equatable, Sendable {
  public var networkDisabled: Bool
  public var networkRequestsObserved: Int
  public var contentTelemetryObserved: Bool
  public var isolationMethod: String
  public var startedAt: String
  public var endedAt: String
  public var evidenceNote: String

  public init(
    networkDisabled: Bool,
    networkRequestsObserved: Int,
    contentTelemetryObserved: Bool,
    isolationMethod: String,
    startedAt: String,
    endedAt: String,
    evidenceNote: String
  ) {
    self.networkDisabled = networkDisabled
    self.networkRequestsObserved = networkRequestsObserved
    self.contentTelemetryObserved = contentTelemetryObserved
    self.isolationMethod = isolationMethod
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.evidenceNote = evidenceNote
  }
}

public struct GateOutcome: Codable, Equatable, Sendable {
  public var id: String
  public var passed: Bool
  public var reviewRequired: Bool
  public var observed: String
  public var limit: String
  public var detail: String

  public init(
    id: String,
    passed: Bool,
    reviewRequired: Bool,
    observed: String,
    limit: String,
    detail: String
  ) {
    self.id = id
    self.passed = passed
    self.reviewRequired = reviewRequired
    self.observed = observed
    self.limit = limit
    self.detail = detail
  }
}

public struct StandardImprovementMetric: Codable, Equatable, Sendable {
  public var scope: EvaluationLanguageMode
  public var metric: EvaluationMetricKind
  public var baselineValue: Double
  public var candidateValue: Double
  public var improvement: Double

  public init(
    scope: EvaluationLanguageMode,
    metric: EvaluationMetricKind,
    baselineValue: Double,
    candidateValue: Double,
    improvement: Double
  ) {
    self.scope = scope
    self.metric = metric
    self.baselineValue = baselineValue
    self.candidateValue = candidateValue
    self.improvement = improvement
  }
}

public struct StandardComparisonSummary: Codable, Equatable, Sendable {
  public var baselineID: String
  public var baselineRevision: String
  public var baselineModelRevision: String
  public var corpusID: String
  public var corpusRevision: String
  public var osVersion: String
  public var hardwareModel: String
  public var architecture: String
  public var appBuild: String
  public var coldObservationCount: Int
  public var warmObservationCount: Int
  public var minimumRequiredImprovement: Double
  public var metrics: [StandardImprovementMetric]

  public init(
    baselineID: String,
    baselineRevision: String,
    baselineModelRevision: String,
    corpusID: String,
    corpusRevision: String,
    osVersion: String,
    hardwareModel: String,
    architecture: String,
    appBuild: String,
    coldObservationCount: Int,
    warmObservationCount: Int,
    minimumRequiredImprovement: Double,
    metrics: [StandardImprovementMetric]
  ) {
    self.baselineID = baselineID
    self.baselineRevision = baselineRevision
    self.baselineModelRevision = baselineModelRevision
    self.corpusID = corpusID
    self.corpusRevision = corpusRevision
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.architecture = architecture
    self.appBuild = appBuild
    self.coldObservationCount = coldObservationCount
    self.warmObservationCount = warmObservationCount
    self.minimumRequiredImprovement = minimumRequiredImprovement
    self.metrics = metrics
  }
}

public struct FailureCancellationSummary: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var failureExercised: Bool
  public var failureFallbackVerified: Bool
  public var failureEvidenceID: String
  public var failureObservedAt: String
  public var cancellationExercised: Bool
  public var cancellationOutcomeVerified: Bool
  public var cancellationEvidenceID: String
  public var cancellationObservedAt: String
  public var evidenceNote: String

  public init(
    schemaVersion: Int,
    failureExercised: Bool,
    failureFallbackVerified: Bool,
    failureEvidenceID: String,
    failureObservedAt: String,
    cancellationExercised: Bool,
    cancellationOutcomeVerified: Bool,
    cancellationEvidenceID: String,
    cancellationObservedAt: String,
    evidenceNote: String
  ) {
    self.schemaVersion = schemaVersion
    self.failureExercised = failureExercised
    self.failureFallbackVerified = failureFallbackVerified
    self.failureEvidenceID = failureEvidenceID
    self.failureObservedAt = failureObservedAt
    self.cancellationExercised = cancellationExercised
    self.cancellationOutcomeVerified = cancellationOutcomeVerified
    self.cancellationEvidenceID = cancellationEvidenceID
    self.cancellationObservedAt = cancellationObservedAt
    self.evidenceNote = evidenceNote
  }
}

public struct EvaluationReport: Codable, Equatable, Sendable {
  public var candidateID: String
  public var runID: String
  public var syntheticSample: Bool
  public var languageMetrics: [LanguageMetricSummary]
  public var protectedExpectations: [ProtectedExpectationSummary]
  public var standardComparison: StandardComparisonSummary
  public var cleanupPreservation: CleanupPreservationSummary
  public var latency: LatencySummary
  public var resources: ResourceSummary
  public var artifacts: ArtifactCompletenessSummary
  public var offline: OfflineSummary
  public var failureCancellation: FailureCancellationSummary
  public var gateOutcomes: [GateOutcome]
  public var releaseDecision: ReleaseDecision
  public var markdown: String

  public init(
    candidateID: String,
    runID: String,
    syntheticSample: Bool,
    languageMetrics: [LanguageMetricSummary],
    protectedExpectations: [ProtectedExpectationSummary],
    standardComparison: StandardComparisonSummary,
    cleanupPreservation: CleanupPreservationSummary,
    latency: LatencySummary,
    resources: ResourceSummary,
    artifacts: ArtifactCompletenessSummary,
    offline: OfflineSummary,
    failureCancellation: FailureCancellationSummary,
    gateOutcomes: [GateOutcome],
    releaseDecision: ReleaseDecision,
    markdown: String
  ) {
    self.candidateID = candidateID
    self.runID = runID
    self.syntheticSample = syntheticSample
    self.languageMetrics = languageMetrics
    self.protectedExpectations = protectedExpectations
    self.standardComparison = standardComparison
    self.cleanupPreservation = cleanupPreservation
    self.latency = latency
    self.resources = resources
    self.artifacts = artifacts
    self.offline = offline
    self.failureCancellation = failureCancellation
    self.gateOutcomes = gateOutcomes
    self.releaseDecision = releaseDecision
    self.markdown = markdown
  }
}

public enum EvaluationReportError: Error, Equatable, Sendable {
  case invalid([EvaluationIssue])
  case invalidGate(String)
}

public enum EvaluationReportWriter {
  public static func atomicWrite(_ text: String, to target: URL) throws {
    try Data(text.utf8).write(to: target, options: .atomic)
  }
}
~~~

EvaluationReportWriter must write directly to the final same-filesystem target
with Foundation's atomic option. It must not remove the existing target or
move a separately named temporary file. The report test pre-populates an
output path and verifies replacement, while the absence of pre-removal
preserves the previous report if the atomic write fails.

### Step 4: Implement deterministic report construction

Add EvaluationReportBuilder.build(corpus:run:gate:) with this exact algorithm
and no model or runtime call:

1. Validate the corpus and run with EvaluationValidator. The run validator
   includes corpus issues before building its safe first-seen case map. Throw
   EvaluationReportError.invalid with those stable issues and never include
   transcript values in the error. Validate the gate before reading any
   transcript: schemaVersion is 1; every Double is finite; all maxima and
   integer limits are nonnegative; every latency limit is positive;
   minimumProtectedTermAccuracy and minimumStandardMaterialImprovement are in
   0...1; and allowedThermalStates is nonempty. Throw invalidGate with the
   first field in the fixed gate-field order.
2. Sort observations by corpus case order, then observationID using ordinal
   String comparison. Build per-case accumulators. For each case, sum
   EditCounts across that case's observations for the audit counts; calculate
   the reported error rate as the unweighted mean of each case's aggregate
   error rate, so additional trials do not overweight a case. Preserve
   caseCount, observationCount, and the literal aggregation description in
   LanguageMetricSummary. Pair each reference slice with the hypothesis slice
   of the same language. English uses
   TranscriptMetrics.englishWordErrorRate and Mandarin uses
   TranscriptMetrics.mandarinCharacterErrorRate. Mixed cases emit separate
   English WER and Mandarin CER summaries and never emit a blended metric.
   Do not average individual observation error rates; that observation-weighted
   result is only a contrasting value in the discriminating report test.
3. Inspect cleanedResult ?? dictionaryBaseline ?? asrRaw for each observation's
   protected expectations. exactCase uses a safe token-boundary search,
   caseInsensitive uses Task 1's locale-stable normalization, numericExact
   compares ordered decimal digit runs, and negationExact requires the exact
   negating term in the matching language slice. Count each expectation once
   per observation, with denominators equal to the number of expectation
   occurrences across observations. Keep separate scope summaries and
   separate number/negation failure counts.
4. For each cleaned observation, compare protected expectations in cleanedResult
   against dictionaryBaseline. A lost protected term is a cleanup
   preservation failure. A failed manual adjudication is also a failure;
   pending or absent adjudication is reviewRequired; a cleaned observation
   with notRequired is invalid and cannot reach reporting. No generative
   meaning claim is automatic: set meaningProvenAutomatically to false and
   require ManualAdjudicationStatus.passed for release eligibility. Do not use
   edit distance or a threshold as a semantic-fidelity proof.
5. Group endToEndMilliseconds by captureTemperature across all observations and
   calculate p50 and p95 with Task 1's nearest-rank percentile. Report peak
   memory, idle memory, energy, model download size, and installed size as
   maxima across all observations. Preserve thermal states in first-seen
   order, include cold/warm counts, and copy unloadAttempted,
   unloadSucceeded, and memoryAfterUnloadBytes from the run-level evidence.
6. Count ASR raw, dictionary baseline, and cleaned artifacts independently and
   retain the validated artifact order. Copy every non-content offline field,
   including isolation method and start/end timestamps. Copy the validated
   failure/cancellation evidence into FailureCancellationSummary, including
   booleans, evidence IDs, timestamps, and the non-content note; never copy
   transcript or protected-term text into the report.
7. Compare the candidate with the versioned Standard Apple baseline. For WER
   and CER, calculate improvement as `(baseline - candidate) / baseline`;
   for protected accuracy, calculate `(candidate - baseline) / baseline`.
   When baseline is zero, return 0 when candidate is also zero and otherwise
   return `-candidate` for error metrics or `candidate` for
   accuracy. Positive is better. Require all seven baseline scope/metric pairs
   and report each improvement without blending mixed English WER and Mandarin
   CER. Copy the baseline model revision, corpus ID/revision, OS, hardware,
   architecture, app build, and cold/warm coverage into
   StandardComparisonSummary only after validator-confirmed equality with the
   CandidateRun and corpus and positive baseline coverage. If those identity or
   coverage checks fail, throw invalid and do not calculate material
   improvement. The mixed-language outcome passes only when both mixed
   components meet their caller-supplied maxima and the mixed standard
   comparison meets its material-improvement threshold.
8. Emit outcomes in this fixed order:
   english-wer, mandarin-cer, mixed-language, protected-terms, numbers,
   negations, standard-improvement-english, standard-improvement-mandarin,
   standard-improvement-mixed, cleanup-preservation, cold-latency,
   warm-latency, peak-memory, idle-memory, unload-behavior,
   post-unload-memory, thermal-state, energy, model-download-size,
   model-installed-size, failure-cancellation-behavior, offline-evidence.
   `failure-cancellation-behavior` passes only when
   failureExercised && failureFallbackVerified && cancellationExercised &&
   cancellationOutcomeVerified. Missing metric/resource evidence is
   reviewRequired for a synthetic sample but invalid for a release run. A
   failed outcome takes precedence over reviewRequired; a reviewRequired
   outcome cannot be reported as passed.
9. Set releaseDecision to notEligible first when syntheticSample is true or
   releaseEvidence is false, regardless of metrics or gate outcomes. Otherwise
   set failed when any outcome or required manual adjudication fails; set
   reviewRequired when no outcome fails but any evidence or manual review is
   pending; and set passed only when every required outcome, standard
   comparison, offline record, unload record, and explicit cleaned-result
   adjudication passes. The report never selects or approves a model.
10. Render Markdown in this fixed order: optional first-line sample watermark,
    title, candidate/run IDs, language metrics, Standard Baseline Comparison,
    protected expectations, cleanup preservation, latency, resources and
    unload, artifacts, failure and cancellation evidence, offline evidence,
    gate outcomes, decision. The sample first line must be exactly SAMPLE DATA
    — NOT MODEL EVIDENCE. Include
    Metrics do not prove semantic fidelity. and, for samples, Synthetic sample
    cannot satisfy a release gate. For a non-synthetic run with
    releaseEvidence false, include Release evidence was not asserted; metrics
    cannot make this run eligible. Render only IDs, counts, units, booleans,
    gate details, and the Standard baseline model revision, corpus ID/revision,
    OS, hardware, architecture, app build, and cold/warm coverage in the
    Standard Baseline Comparison section. The Failure and Cancellation section
    contains only the
    schema version, exercised/verified booleans, evidence IDs, timestamps, and
    non-content note. Never render reference, spoken, ASR raw, dictionary
    baseline, cleaned, or protected term text.

Implement the outcome table as data in the listed order, never by iterating a
dictionary. The outcome predicate is lower-is-better for WER, CER, failure
counts, latency, memory, energy, and sizes; higher-is-better for protected
accuracy and each Standard improvement; membership is required for thermal
states; unload requires both unloadAttempted and unloadSucceeded; and offline
requires networkDisabled, zero networkRequestsObserved, and false
contentTelemetryObserved. `mixed-language` is the conjunction of the
English-WER and Mandarin-CER predicates for the mixed scope. The three
standard-improvement outcomes are the conjunction of all required baseline
metrics in their scope, with the mixed outcome requiring both mixed error
metrics plus mixed protected accuracy. `failure-cancellation-behavior` has no
numeric threshold and is true only when both recorded behaviors were exercised
and verified. The builder stores each candidate value, limit, and predicate
result in GateOutcome so Markdown and Codable output remain deterministic.

When a release run has cleaned output, status `.passed` is the only passing
manual status; `.pending` or absent produces reviewRequired and `.failed`
produces a failed outcome. The validator rejects `.notRequired` alongside
cleaned output before the builder runs. Failure precedence is implemented as
`if syntheticSample || !releaseEvidence { .notEligible } else if hasFailure {
.failed } else if hasReview { .reviewRequired } else { .passed }`, with
eligibility evaluated first and failure evaluated before review. Thus a
non-synthetic run with releaseEvidence false cannot become eligible because
its metrics happen to pass.

The implementation may use private deterministic helpers, but their behavior
must be covered by the tests above and the fixed algorithm. The report is an
evaluation artifact, not a claim of semantic correctness.

### Step 5: Implement the exact CLI and wrapper invocation contract

Create main.swift with this complete command shape. The parser must reject
missing flags, duplicate flags, unknown flags, extra positionals, and unknown
commands with exit code 2. Before storing a flag value, reject any value that
starts with `--` with CommandError("missing value for <flag>"); this makes
`validate-corpus --corpus --run` an argument error rather than a file read.
File decoding errors print only a file path and stable error class. Validation
errors print only issue code and JSON path.

~~~swift
import Darwin
import Foundation
import LocalDictationEvaluation

@main
struct LocalDictationEvaluationCLI {
  static func main() {
    exit(run(Array(CommandLine.arguments.dropFirst())))
  }

  static func run(_ arguments: [String]) -> Int32 {
    do {
      let command = try Command.parse(arguments)
      switch command {
      case .validateCorpus(let path):
        let corpus = try read(EvaluationCorpus.self, path: path)
        let issues = EvaluationValidator.validate(corpus: corpus)
        printIssues(issues)
        return issues.isEmpty ? 0 : 2
      case .validateRun(let corpusPath, let runPath):
        let corpus = try read(EvaluationCorpus.self, path: corpusPath)
        let run = try read(CandidateRun.self, path: runPath)
        let issues = EvaluationValidator.validate(run: run, against: corpus)
        printIssues(issues)
        return issues.isEmpty ? 0 : 2
      case .report(let corpusPath, let runPath, let gatePath, let outputPath):
        let corpus = try read(EvaluationCorpus.self, path: corpusPath)
        let run = try read(CandidateRun.self, path: runPath)
        let gate = try read(EvaluationGate.self, path: gatePath)
        let report = try EvaluationReportBuilder.build(
          corpus: corpus,
          run: run,
          gate: gate
        )
        do {
          try EvaluationReportWriter.atomicWrite(
            report.markdown,
            to: URL(fileURLWithPath: outputPath)
          )
        } catch {
          throw FileError(path: outputPath, kind: "write-failed")
        }
        switch report.releaseDecision {
        case .failed, .reviewRequired:
          return 3
        case .passed, .notEligible:
          return 0
        }
      }
    } catch let error as CommandError {
      fputs("argument error: \(error.message)\n", stderr)
      return 2
    } catch let error as FileError {
      fputs("file error: \(error.path) \(error.kind)\n", stderr)
      return 4
    } catch let error as InputError {
      fputs("input error: \(error.path) \(error.kind)\n", stderr)
      return 2
    } catch let error as EvaluationReportError {
      switch error {
      case .invalid(let issues):
        printIssues(issues)
      case .invalidGate(let field):
        fputs("invalid gate field: \(field)\n", stderr)
      }
      return 2
    } catch {
      fputs("internal error\n", stderr)
      return 4
    }
  }

  private static func read<T: Decodable>(
    _ type: T.Type,
    path: String
  ) throws -> T {
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw FileError(path: path, kind: "read-failed")
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw InputError(path: path, kind: "invalid-json-or-schema")
    }
  }

  private static func printIssues(_ issues: [EvaluationIssue]) {
    for issue in issues {
      fputs("\(issue.code) \(issue.path)\n", stderr)
    }
  }

}

private enum Command {
  case validateCorpus(String)
  case validateRun(String, String)
  case report(String, String, String, String)

  static func parse(_ arguments: [String]) throws -> Command {
    guard let name = arguments.first else {
      throw CommandError("one command is required")
    }
    var values: [String: String] = [:]
    var index = 1
    while index < arguments.count {
      let flag = arguments[index]
      guard flag.hasPrefix("--"), index + 1 < arguments.count else {
        throw CommandError("expected a flag and value")
      }
      guard values[flag] == nil else {
        throw CommandError("duplicate flag \(flag)")
      }
      let value = arguments[index + 1]
      guard !value.hasPrefix("--") else {
        throw CommandError("missing value for \(flag)")
      }
      values[flag] = value
      index += 2
    }
    func require(_ flags: [String]) throws -> [String] {
      guard Set(values.keys) == Set(flags),
        flags.allSatisfy({ values[$0]?.isEmpty == false })
      else {
        throw CommandError("invalid flags for \(name)")
      }
      return flags.compactMap { values[$0] }
    }
    switch name {
    case "validate-corpus":
      return .validateCorpus(try require(["--corpus"])[0])
    case "validate-run":
      let values = try require(["--corpus", "--run"])
      return .validateRun(values[0], values[1])
    case "report":
      let values = try require(["--corpus", "--run", "--gate", "--output"])
      return .report(values[0], values[1], values[2], values[3])
    default:
      throw CommandError("unknown command")
    }
  }
}

private struct CommandError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

private struct FileError: Error {
  let path: String
  let kind: String
}

private struct InputError: Error {
  let path: String
  let kind: String
}
~~~

Create Scripts/evaluate-local-dictation.sh only after the CLI tests compile.
It is the stable wrapper and must contain exactly this behavior:

~~~sh
#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  printf '%s\n' 'usage: Scripts/evaluate-local-dictation.sh COMMAND OPTIONS' >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"
exec swift run --package-path Tools/LocalDictationEvaluation local-dictation-evaluation "$@"
~~~

The worker makes the wrapper executable and does not add it to root Package
targets. The shell command must pass all CLI arguments unchanged.

### Step 6: Run the green report and CLI checks

Run the explicit `EvaluationReportTests` Swift Testing suite:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --filter EvaluationReportTests --no-parallel
~~~

Expected: PASS for deterministic Markdown order, sample watermark and
non-eligibility, separate mixed metrics, gate pass/fail, manual-review
refusal, gate decoding, atomic same-target replacement, and transcript-free
diagnostics.

Run the package-wide tests:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --no-parallel
~~~

Expected: PASS for all three task test groups.

Exercise all three CLI commands through the wrapper using the checked-in
corpus/run and a temporary gate JSON with exactly the EvaluationGate fields
shown in the gate decoding test:

~~~sh
Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json
Scripts/evaluate-local-dictation.sh validate-run \
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json \
  --run Tests/Fixtures/local-dictation-run-sample-v1.json
Scripts/evaluate-local-dictation.sh report \
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json \
  --run Tests/Fixtures/local-dictation-run-sample-v1.json \
  --gate "$gate_path" \
  --output "$report_path"
test "$(sed -n '1p' "$report_path")" = "SAMPLE DATA — NOT MODEL EVIDENCE"
~~~

Expected: the first two commands return 0, the sample report command returns
0 while marking the report not eligible, and the output contains no transcript
text. The integration test must also invoke
`validate-corpus --corpus --run`, assert exit 2 with exactly
`argument error: missing value for --corpus`, and prove that no file-error exit
4 is returned. It must then pass an invalid corpus and assert exit 2 with only
a stable code/path diagnostic.

### Step 7: Scope-check and commit Task 3

Run:

~~~sh
git diff --check
git status --short --branch
git diff --name-only
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
~~~

Expected: only the four Task 3 paths plus already committed Task 1 and Task 2
paths are changed. Stage only these Task 3 paths and commit:

~~~sh
git add \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationReport.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift \
  Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationReportTests.swift \
  Scripts/evaluate-local-dictation.sh
git commit -m "feat: generate local dictation evaluation reports"
~~~

Expected: one focused report/CLI commit. No model adapter, audio capture,
dictionary store, product source, shared UI, root package file, or existing
fixture is included.

---

## Task 4: Operator procedure, corpus admission gate, and whole-foundation verification

**Files:**

- Create: Scripts/test-local-dictation-evaluation.sh
- Create: docs/dictation/local-model-evaluation.md

**Interfaces:**

- The test wrapper runs the nested Swift tests, validates the checked-in
  text-contract corpus and synthetic run, invokes the report command with a
  temporary gate file, checks the sample watermark, and checks an invalid-input
  exit without exposing transcript content.
- The operator document is the exact offline procedure for a future admitted
  model run. It records the Phase A stop gate, the audio admission contract,
  gate predeclaration, evidence fields, manual adjudication, release decision,
  and full repository verification commands.

### Step 1: Create the integration wrapper with stable commands

Create Scripts/test-local-dictation-evaluation.sh exactly as follows. It must
run from any current directory, clean its temporary files on every exit, and
not modify a checked-in fixture:

~~~sh
#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

swift test --package-path Tools/LocalDictationEvaluation --no-parallel

corpus_path="Tests/Fixtures/local-dictation-evaluation-v1.json"
run_path="Tests/Fixtures/local-dictation-run-sample-v1.json"
gate_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-gate.XXXXXX")
report_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-report.XXXXXX")
invalid_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-invalid.XXXXXX")
stderr_path=$(mktemp "${TMPDIR:-/tmp}/fleck-local-dictation-stderr.XXXXXX")
cleanup() {
  rm -f "$gate_path" "$report_path" "$invalid_path" "$stderr_path"
}
trap cleanup EXIT HUP INT TERM

cat > "$gate_path" <<'JSON'
{
  "schemaVersion": 1,
  "maxEnglishWordErrorRate": 0.25,
  "maxMandarinCharacterErrorRate": 0.25,
  "maxMixedEnglishWordErrorRate": 0.30,
  "maxMixedMandarinCharacterErrorRate": 0.30,
  "minimumProtectedTermAccuracy": 0.90,
  "maximumNumberFailures": 0,
  "maximumNegationFailures": 0,
  "maximumCleanupPreservationFailures": 0,
  "maxColdLatencyMilliseconds": 2000,
  "maxWarmLatencyMilliseconds": 500,
  "maxPeakMemoryBytes": 2000000000,
  "maxIdleMemoryBytes": 500000000,
  "maxPostUnloadMemoryBytes": 500000000,
  "maxEnergyImpact": 2.0,
  "maxModelDownloadBytes": 2000000000,
  "maxModelInstalledBytes": 2000000000,
  "minimumStandardMaterialImprovement": 0.10,
  "allowedThermalStates": ["nominal", "fair"]
}
JSON

Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus "$corpus_path"
Scripts/evaluate-local-dictation.sh validate-run \
  --corpus "$corpus_path" \
  --run "$run_path"
Scripts/evaluate-local-dictation.sh report \
  --corpus "$corpus_path" \
  --run "$run_path" \
  --gate "$gate_path" \
  --output "$report_path"
grep -F -x 'SAMPLE DATA — NOT MODEL EVIDENCE' "$report_path" >/dev/null
grep -F 'failure-cancellation-behavior' "$report_path" >/dev/null
if grep -F 'fixInputMonitor' "$report_path" >/dev/null; then
  printf '%s\n' 'sample report leaked transcript content' >&2
  exit 1
fi

if Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus --run > /dev/null 2> "$stderr_path"
then
  printf '%s\n' 'flag-looking value unexpectedly passed' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 2 ]; then
    printf 'flag-looking value returned %s\n' "$status" >&2
    exit 1
  fi
fi
grep -F -x 'argument error: missing value for --corpus' "$stderr_path" >/dev/null
if grep -F 'file error' "$stderr_path" >/dev/null; then
  printf '%s\n' 'flag-looking value was treated as a file path' >&2
  exit 1
fi

printf '%s\n' '{"schemaVersion":0}' > "$invalid_path"
if Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus "$invalid_path" > /dev/null 2> "$stderr_path"
then
  printf '%s\n' 'invalid corpus unexpectedly passed' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 2 ]; then
    printf 'invalid corpus returned %s\n' "$status" >&2
    exit 1
  fi
fi
if grep -E 'fixInputMonitor|请在星期五|PRIVATE_TRANSCRIPT' "$stderr_path" >/dev/null; then
  printf '%s\n' 'invalid diagnostics leaked transcript content' >&2
  exit 1
fi

printf '%s\n' 'local dictation evaluation integration checks passed'
~~~

Make this wrapper executable. Its expected outcome is one nested test pass,
two validation exit codes of 0, one sample report exit code of 0 with an
ineligible decision, one flag-looking-value argument exit code of 2 with an
argument error, and one invalid-input exit code of 2.

### Step 2: Document the offline operator procedure

Create docs/dictation/local-model-evaluation.md with this complete content:

~~~~markdown
# Fleck Local Dictation Evaluation

## Purpose and Phase A boundary

This procedure evaluates a candidate for Fleck's entirely local English,
Mandarin, and mixed English-Mandarin Enhanced Dictation path. It is a
measurement gate, not a model selector. Phase A contains only the
dependency-free text contracts, deterministic metrics, strict validation,
synthetic sample report, and operator procedure. The checked-in corpus has no
audio, the checked-in run is synthetic, and neither is release evidence.

Phase A does not run ASR or cleanup inference, record real or personal audio,
choose Whisper/whisper.cpp, SenseVoice/Paraformer, Qwen3-ASR, Qwen3.5,
llama.cpp, or any other model/runtime, build the combined download pack, or
edit Fleck product/shared integration files. Phase B covers the global
device-local dictionary and Apple contextual vocabulary. Phase C covers
privacy-safe audio admission, ASR and cleanup candidate benchmarks, native
Apple-silicon feasibility, commercial redistribution/license review, and the
selection gate. Phase D covers the selected model pack/manager and AI-owned
pipeline. Phase E covers coordinated shared runtime and UI integration. These
phases remain separate because exact model/runtime interfaces are intentionally
unselected.

The ordinary pipeline contract remains:

transient audio -> local ASR -> ASR raw -> dictionary baseline -> optional local
cleanup -> validation -> insertion/persistence

The three transcript artifacts are distinct:

1. ASR raw is the exact final recognizer output before Fleck dictionary
   mutation.
2. Dictionary baseline is ASR raw after only explicit deterministic,
   unambiguous dictionary aliases with safe token boundaries. It is the
   protected baseline.
3. Cleaned result is an optional Light or Polished transformation of the
   dictionary baseline.

Off inserts the dictionary baseline. Successful Light or Polished cleanup
inserts the cleaned result. Cleanup unavailable, timeout, rejection, empty or
suspicious output, validation failure, lost protected terms, or unreasonable
transformation inserts the dictionary baseline. If dictionary resolution
fails before a valid baseline exists, insert ASR raw and record visibly that
dictionary resolution was skipped. ASR raw is the forensic and recovery source,
not the ordinary post-dictionary fallback. Revert Cleanup restores the
dictionary baseline.

Audio is transient and never enters disk or history. During capture the three
text artifacts may exist in memory. When Dictation History is enabled, a local
record may persist ASR raw, dictionary baseline, cleaned result when produced,
inserted artifact/outcome, and existing metadata under the existing 30-day
retention and purge contract. When history is disabled, none of those
transcript artifacts are persisted to disk or history. History-disabled Revert
Cleanup is in-memory only and remains replaceable only while the most recent
cleaned insertion still matches its safe insertion identity; clear it on the
next successful capture, range/text mismatch, target-note deletion, or process
exit. With history enabled, recover or revert only while retained and safe;
otherwise preserve note content and offer copy/open behavior. Old history
records without dictionary baseline must continue to decode, with exact
migration details reserved for the implementation task.

## Preflight and gate record

1. Start from the accepted design commit
   72e5ebb3f7095966de7fc962a1aec3a871340099 or a descendant whose parent
   verification is recorded. Confirm a clean worktree with
   git status --short --branch. Do not alter root Package.swift or
   Package.resolved.
2. Declare the gate JSON before any candidate capture. It must contain exactly
   schemaVersion, maxEnglishWordErrorRate, maxMandarinCharacterErrorRate,
   maxMixedEnglishWordErrorRate, maxMixedMandarinCharacterErrorRate,
   minimumProtectedTermAccuracy, maximumNumberFailures,
   maximumNegationFailures, maximumCleanupPreservationFailures,
   maxColdLatencyMilliseconds, maxWarmLatencyMilliseconds, maxPeakMemoryBytes,
   maxIdleMemoryBytes, maxPostUnloadMemoryBytes, maxEnergyImpact,
   maxModelDownloadBytes, maxModelInstalledBytes,
   minimumStandardMaterialImprovement, and allowedThermalStates. Every value
   must be finite, nonnegative where applicable, and explicitly chosen for
   the experiment; the library has no product defaults. The mixed gate is a
   conjunction of its English WER and Mandarin CER limits, not a blended
   score. `failure-cancellation-behavior` is a fixed boolean outcome, not a
   gate-file field, and it must pass for release evidence.
3. Verify the candidate identity and revisions: candidate ID, display name,
   model ID and immutable model revision, runtime name and revision, license
   review record, Fleck/app build, Swift version, macOS version, hardware
   model, architecture, and capture timestamp. Record model download size and
   installed size in resource evidence when a model is admitted. The versioned
   Standard Apple baseline identity must also record baseline ID/revision,
   baseline model revision, corpus ID/revision, OS version, hardware model,
   architecture, app build, recordedAt, and positive cold and warm observation
   counts, together with the seven per-scope baseline metrics used for
   material-improvement comparison. Capture that baseline with the same
   corpus ID/revision and candidate environment; validator-confirmed identity
   or coverage mismatch is not comparable and cannot pass release evidence.
4. Enhanced requires Apple silicon. Include representative Apple-silicon
   evidence, including the provisional M1/8 GB benchmark target. M1/8 GB is
   not a release claim. Standard remains the zero-download Apple on-device
   path and remains available on Intel. Do not claim either model tier is
   available when its preflight is unavailable.
5. Run the candidate with networking disabled at the environment boundary:
   turn off Wi-Fi, disconnect Ethernet and other network interfaces in the
   disposable lab environment, and apply the lab's outbound-deny control.
   Record the isolation method, start/end timestamps, network request count,
   and content-telemetry observation. A run with any network request or content
   telemetry is invalid; never silently use network inference.

## Later audio admission gate

Phase A commits no real or personal audio. Before a future ASR benchmark,
admit each asset only when all of these fields are recorded in the corpus
revision:

- stable asset path or identifier and SHA-256 hash;
- source, redistribution license, and owner;
- explicit consent record, approval status, reviewer, and review timestamp;
- speaker language, accent, and privacy review;
- confirmation that no personal note content, secrets, credentials, or
  unrelated private material is present;
- a revocation/removal process that can remove the asset and invalidate the
  corpus revision.

The validator must fail closed for a missing hash, source/license, privacy
review, approved consent, or revocation process. Only AudioConsentStatus.approved
admits an audio asset; pending and revoked consent are rejected. A corpus revision changes
when audio is admitted or removed. Audio remains transient during a capture
and is never committed to the repository, disk history, analytics, or content
telemetry.

This audio prerequisite is keyed to the run's syntheticSample value, not its
releaseEvidence claim: every non-synthetic run is a real ASR benchmark and
must use admitted audio for every corpus case, even when releaseEvidence is
false. releaseEvidence separately controls release-only evidence and
eligibility.

The initial text-contract cases cover English prose, Mandarin, mixed speech,
developer prompts and commit messages, camelCase/PascalCase/snake_case,
commands, paths, filenames, acronyms, proper nouns, dictionary terms,
fillers, repetition, self-correction, accents, noise, numbers, negation, and
prompt-injection-as-data. Prompt-injection text is data in the corpus; it is
never an instruction to the evaluator or cleanup model.

## Capture and result procedure

After audio admission and offline preflight, capture at least two uniquely
identified observations for every corpus case: one cold observation after
unloading the candidate and an idle interval, and one warm observation without
reloading. Additional trials are allowed. Stable observationID values must be
unique across the run; caseID repeats are expected. Record observations in
corpus case order and use observationID as the deterministic tie-breaker.

1. For each cold observation, record finite nonnegative model-load, ASR,
   cleanup, and end-to-end latency, peak and idle memory, thermal state,
   energy, and model download/installed size. Cold observations require
   coldLoadMilliseconds; warm observations must set that field to null.
2. Capture the warm observation and record the same resource fields. At the
   end of the run record unloadAttempted, unloadSucceeded,
   memoryAfterUnloadBytes, and observedAt. Release evidence is invalid unless
   unload was attempted and succeeded.
3. Preserve ASR raw exactly. Apply only explicit safe dictionary aliases to
   form dictionary baseline. If dictionary resolution fails, preserve ASR raw
   and record the skipped-resolution outcome.
4. If cleanup is enabled, retain the dictionary baseline and optional cleaned
   result. Validate protected terms, numbers, negations, empty/suspicious
   output, and unreasonable transformation. On any cleanup failure, insert
   the dictionary baseline.
5. Write a CandidateRun JSON with both cold and warm observations for every
   case, unique observation IDs, the exact artifact order, corpus ID/revision,
   environment, candidate revisions, versioned comparable Standard baseline
   identity and seven per-scope baseline metrics, unload evidence, offline
   evidence, and schemaVersion 1 failureCancellationEvidence. That evidence
   records separate failureExercised/failureFallbackVerified and
   cancellationExercised/cancellationOutcomeVerified booleans, non-content
   evidence IDs, timestamps, and a note. A real ASR benchmark fails validation
   unless every case has admitted audio and provenance, independently of
   releaseEvidence.
6. Run validate-corpus and validate-run. Fix the data or stop; do not bypass a
   validation error and do not print transcript text in diagnostics.
7. Run the report command with the predeclared gate. Treat the report's
   English WER, Mandarin CER, separate mixed-language English WER and Mandarin
   CER, protected-term counts, number/negation failures, cleanup preservation
   failures, p50/p95 cold/warm latency, peak and idle memory, unload and
   post-unload memory, energy, model download and installed sizes, thermal
   states, Standard-baseline material improvement, artifact completeness,
   offline evidence, and gate outcomes as measurements. Metrics do not prove
   semantic fidelity. A release decision is not eligible unless
   syntheticSample is false and releaseEvidence is true.
   For WER/CER, material improvement is `(standard - candidate) / standard`;
   for protected accuracy it is `(candidate - standard) / standard`. With a
   zero standard baseline, exact zero candidate yields 0 and otherwise the
   error metric yields `-candidate` while accuracy yields `candidate`.
   English and Mandarin components of the mixed scope must each pass, and
   the mixed comparison is never blended. The fixed
   failure-cancellation-behavior outcome must also pass; release evidence
   fails closed when either behavior is absent, unexercised, or unverified.
8. Exercise one controlled failure and verify the documented dictionary or
   cleanup fallback outcome, then exercise one controlled cancellation and
   verify its documented non-destructive outcome. Record only the
   failure/cancellation evidence IDs, booleans, timestamps, and non-content
   note in FailureCancellationEvidence; do not put transcript or audio data
   in this record. Both behavior pairs must be true for the fixed outcome to
   pass.
9. Manually adjudicate meaning preservation, factual additions/omissions,
   names, dates, numbers, negations, tasks, conclusions, dictionary forms,
   filenames, acronyms, identifiers, and surrounding-note preservation.
   A cleaned observation passes this gate only with
   ManualAdjudicationStatus.passed. Pending or absent status is valid input but
   requires review;
   failed status fails; notRequired is valid only when no cleaned result
   exists. A simplistic distance threshold is not semantic proof.
10. Sign the selection decision only after the measured gate, manual
   adjudication, license review, native Apple-silicon feasibility, and
   representative M1/8 GB evidence pass. Phase A itself never signs or
   selects a model/runtime.

## Stable commands and expected outcomes

From the repository root:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --no-parallel
Scripts/test-local-dictation-evaluation.sh
Scripts/evaluate-local-dictation.sh validate-corpus \
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json
Scripts/evaluate-local-dictation.sh validate-run \
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json \
  --run Tests/Fixtures/local-dictation-run-sample-v1.json
~~~

The nested tests and wrapper return 0 for valid text-contract/sample data. The
sample report starts with SAMPLE DATA — NOT MODEL EVIDENCE, is visibly
watermarked, includes the fixed failure-cancellation-behavior outcome, and
never satisfies a release gate. A non-synthetic gate failure returns 3. Invalid
arguments, schema, or input return 2. I/O/internal errors return 4. Error
output names only stable IDs, issue codes, and JSON paths.

For the future admitted run, use:

~~~sh
Scripts/evaluate-local-dictation.sh report \
  --corpus PATH \
  --run PATH \
  --gate PATH \
  --output PATH
~~~

The output is written atomically. Keep ASR raw, dictionary baseline, and
cleaned result according to Dictation History state; do not silently expand
retention. No audio is persisted in either mode.

## Full repository verification after Phase A implementation

Run the following after the nested package and wrappers are stable:

~~~sh
swift test --package-path Tools/LocalDictationEvaluation --no-parallel
Scripts/test-local-dictation-evaluation.sh
swift test --disable-automatic-resolution --no-parallel --quiet
Scripts/validate-macos.sh
git diff --check
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
~~~

On a non-macOS host, record the platform limitation for
Scripts/validate-macos.sh rather than claiming a pass. Verify the nested
package has no third-party dependency, the root Package.resolved is
byte-identical to the accepted design base, checksums and license records are
present for any future model artifacts, and the complete report is generated
offline. Packaged QA, when a later product phase reaches it, uses a disposable
testing tab to the right of the protected leftmost personal tab.

## Privacy and cost boundary

No network inference, account, API key, cloud transcription, cloud cleanup,
content telemetry, or audio retention is permitted. Local inference has no
per-minute inference charge, but model hosting bandwidth, QA, support, license
review, artifact updates, and maintenance still have costs. Models are
separate, checksum-verified, removable, and unloaded while idle. The optional
combined Enhanced download remains an approximate 1–3 GB target pending
benchmarks; the base app remains small. No release size or M1 qualification is
claimed by this Phase A procedure.
~~~~

### Step 3: Run the whole-foundation verification

Run the integration wrapper:

~~~sh
Scripts/test-local-dictation-evaluation.sh
~~~

Expected: nested Swift Testing passes; corpus and sample run validate; sample
report returns 0 with the exact watermark and no transcript leakage; invalid
input returns 2; and no checked-in fixture changes.

Then run the repository checks exactly as documented:

~~~sh
swift test --disable-automatic-resolution --no-parallel --quiet
Scripts/validate-macos.sh
git diff --check
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
~~~

Expected: root checks pass on a supported macOS host, validation script
completes its existing gates, the diff has no whitespace errors, and root
package files remain byte-identical. No model inference, real audio capture,
personal dictionary production work, dependency resolution, or shared-file
integration occurs in Phase A.

### Step 4: Scope-check and commit Task 4

Run:

~~~sh
git diff --check
git status --short --branch
git diff --name-only
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
~~~

Expected: only the two Task 4 paths plus prior Phase A paths are changed.
Stage only the two Task 4 paths and commit:

~~~sh
git add \
  Scripts/test-local-dictation-evaluation.sh \
  docs/dictation/local-model-evaluation.md
git commit -m "docs: document local dictation evaluation gate"
~~~

Expected: one focused operator-procedure commit and no edits to existing
product source, tests, fixtures, root package files, or shared integration
files.

---

## Plan self-review and stop gate

The plan has been checked against the accepted design with this coverage map:

| Accepted-design area | Phase A coverage | Explicit boundary |
| --- | --- | --- |
| Entirely local operation, Standard/Enhanced platform split, transient audio, model storage/checksums/removal, and no content telemetry | Global Constraints; Task 2 OfflineEvidence; Task 4 operator preflight and privacy boundary | No runtime integration or packaged model manager; those belong to Phases D and E. |
| English, Mandarin, mixed-language launch corpus and developer-writing quality bar | Task 2 corpus categories and language slices; Task 1 WER/CER; Task 4 device and thermal evidence | No broad-language claim, full voice coding, cursor command, or indentation feature is admitted. |
| Modular ASR plus local cleanup decision and candidate/license/native feasibility gate | Task 2 candidate identity and Task 4 selection procedure | Phase A selects no ASR or cleanup model/runtime; Phase C performs benchmark, license, and native feasibility review. |
| Three artifacts, dictionary-baseline fallback, raw forensic source, cleanup modes, validation, and Revert Cleanup | Task 2 artifact contracts/validation; Task 3 artifact reporting; Task 4 pipeline and retention procedure | Production SpeechEngine/DictationCoordinator lifecycle remains untouched; Phases D/E integrate later. |
| Personal dictionary global/device-local fields, aliases, protected forms, suggestions, import/export, and Apple contextual vocabulary | Task 2 protected expectations establish evaluation vocabulary only; the Phase B boundary is recorded in scope | No personal dictionary store, automatic acceptance or addition, sync, teams, snippets, profiles, or production Apple API work occurs in Phase A. |
| Consent, expected storage, atomic installation, cancel/repair/removal, preflight fallback, and no silent network inference | Task 2 audio/offline validation; Task 4 audio admission and offline procedure | Model manager behavior is Phase D; this plan only records the evidence contract. |
| Corpus, WER/CER, distinct mixed-language components, protected terms, numbers/negations, cleanup adjudication, cold/warm load, peak/idle/post-unload memory, unload behavior, thermal/energy state, model download/installed size, predeclared size and material-improvement thresholds, comparable Standard Apple baseline identity/coverage, failure/cancellation behavior, offline timestamps/isolation, and M1/8 GB evidence | Tasks 1–3 metrics/contracts/report; Task 4 operator gate | Vendor measurements are shortlist input only; synthetic values never qualify release, and no release qualification is claimed by sample data. |
| History, raw/baseline/cleaned retention, disabled-history in-memory revert, 30-day purge, and backward-compatible old records | Task 2 artifact ordering; Task 4 exact retention procedure | Exact migration and insertion APIs are later implementation work; no history or note code changes are allowed here. |
| AI-owned versus shared ownership and accessibility/state labels | Global file map and Task 4 stop boundary | No shared Fleck file, Settings/Notes UI, AppState presentation, or VoiceOver CRUD surface is changed in Phase A; Phase E coordinates those requirements. |
| Phases A–E, offline QA, disposable testing tab, and non-goals | Scope, execution checklist, Task 4 procedure, and full verification | This document stops after Phase A and does not define model-specific future interfaces. |

The type-consistency review follows one data path: Task 1 defines
EvaluationLanguageMode, TranscriptArtifactKind, EditCounts, and
TranscriptMetrics; Task 2 uses those enums in EvaluationTextSlice,
EvaluationCase, and uniquely identified UtteranceResult observations and
validates the exact artifact order plus cold/warm coverage; Task 3 consumes
those contracts through EvaluationReportBuilder.build(corpus:run:gate:) and
emits case-balanced separate English and Mandarin summaries, distinct mixed
components, protected denominators, comparable Standard-baseline improvements,
failure/cancellation evidence, and fixed resource/outcome order; Task 4
invokes the same JSON contracts through the CLI. ResourceMeasurement carries
peak/idle memory, thermal state, energy, and required model download/installed
sizes; UnloadEvidence carries unload and post-unload evidence;
EvaluationReport carries their maxima plus the validated Standard baseline
identity/coverage and failure/cancellation summary without inventing a product
threshold. The gate JSON fields match EvaluationGate and the wrapper's
temporary file exactly, including the mixed and Standard-baseline criteria;
failure-cancellation-behavior remains a fixed non-configurable outcome.

The ownership review permits only the file map at the start of this document.
No instruction edits root Package.swift, root Package.resolved, TESTING.md,
existing clean-dictation fixtures, Fleck dictation source/tests, model scripts,
AppState, FleckApp, NotesPanel, SettingsView, AppPreferences, or any other
shared integration file.

The language/ownership review scans the complete document for forbidden
placeholder planning language and stale pre-Fleck product naming; zero matches
are required. The complete document must be read after that scan, and the
worker must stop before ASR/cleanup inference, real audio admission, personal
dictionary production work, dependency selection, or shared-file integration.

## Plan-only verification and final handoff

Before the plan commit, run:

~~~sh
git status --short --branch
git diff --check
git diff --name-only 72e5ebb3f7095966de7fc962a1aec3a871340099
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
test -z "$(git ls-files -u)"
test ! -e "$(git rev-parse --git-path MERGE_HEAD)"
~~~

Expected: the worktree has only the owned plan as an untracked/changed file,
the diff has no whitespace errors, the base comparison names exactly
docs/superpowers/plans/2026-08-07-local-ai-dictation-evaluation-foundation.md,
and root package files are byte-identical. No Swift build or test is run for
this plan-only change.

Read the complete plan once more, then stage only the owned plan and create
exactly one new commit on top of 72e5ebb3f7095966de7fc962a1aec3a871340099:

~~~sh
git add docs/superpowers/plans/2026-08-07-local-ai-dictation-evaluation-foundation.md
git commit -m "docs: plan local dictation evaluation foundation"
~~~

After committing, run:

~~~sh
git status --short --branch
git show --stat --oneline --decorate --no-renames HEAD
git diff --name-only 72e5ebb3f7095966de7fc962a1aec3a871340099...HEAD
git diff --exit-code 72e5ebb3f7095966de7fc962a1aec3a871340099 -- Package.swift Package.resolved
~~~

Expected: one clean documentation commit with exactly the owned plan path,
parent 72e5ebb3f7095966de7fc962a1aec3a871340099, no root package diff, and no
push, pull request, merge, rebase, or other worktree mutation.
