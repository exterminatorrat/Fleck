# Fleck Local Enhanced Dictation Model Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce admissible, reproducible evidence that selects Fleck's local ASR and optional cleanup model/runtime pair before any production runtime, package, onboarding, or Settings integration.

**Architecture:** Keep candidate dependencies outside Fleck's root Swift package. Harden the existing evaluation CLI, add a versioned JSON-lines adapter contract in a standalone tool package, run each candidate through isolated helper processes, and emit the existing `CandidateRun` format for the locked report gate. The plan stops at an evidence-backed selection; the selected runtime receives a new implementation plan with exact pinned revisions and product files.

**Tech Stack:** Swift 6, Swift Testing, Foundation, JSON Schema fixtures, subprocess JSON-lines adapters, whisper.cpp, NeMo-Speech.cpp, admitted Qwen3-ASR Apple runtime, llama.cpp, shell verification scripts.

## Global Constraints

- Base Fleck and Apple Standard retain macOS 14 support.
- Enhanced Dictation may require Apple silicon and macOS 15+.
- The release target is a base M1 Mac with 8 GB unified memory.
- English, Mandarin, and mixed English-Mandarin results remain separate.
- The first cleanup matrix is Off, Qwen3-0.6B Q8, and Qwen3.5-0.8B Q4_0.
- The first ASR matrix is whisper.cpp `small`, whisper.cpp `large-v3-turbo-q5_0`, Nemotron 3.5 ASR 0.6B Q8 through NeMo-Speech.cpp, and one admitted Qwen3-ASR-0.6B Apple route.
- No inference request may access the network or auto-download a model, tokenizer, or runtime.
- Selected runtime libraries and executable code ship inside the signed Fleck
  app. The one-click downloadable pack contains data-only weights,
  tokenizer/configuration, manifests, and license notices.
- The combined installed pack target is at most 2.0 GB and the hard stop is 3.0 GB without a new product decision.
- Protected terms, numbers, units, paths, identifiers, and negations must pass their locked semantic gates.
- Candidate dependencies must not be added to root `Package.swift` or `Package.resolved` during selection.
- Do not edit `AppState.swift`, `FleckApp.swift`, `NotesPanel.swift`, `SettingsView.swift`, `AppPreferences.swift`, onboarding source, folder-agent paths, or persistence-owned files in this plan.
- Preserve unrelated work and adapt to concurrent edits. Stop and coordinate before expanding the file allowlist.

---

## Why this plan ends at model selection

The production adapter, bundle manifest, installed size, native library layout,
deployment floor, license notices, and download origins depend on the measured
winner. Writing those tasks against an unselected runtime would either hide a
material branch or lock Fleck to a model before evidence exists.

Completion of this plan produces one signed-off selection record containing:

- exact model and runtime revisions;
- exact artifact hashes, sizes, provenance, and redistribution review;
- the winning ASR and cleanup configuration, including cleanup Off when it wins;
- the rejected candidates and gate failures;
- the concrete product-runtime dependency and file boundary needed for the
  next implementation plan.

No task in this plan enables Enhanced Dictation in a release build.

## File map

### Files created by this plan

- `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/StrictJSONSchema.swift` — validates unknown JSON object keys against the checked-in schema before Codable decoding.
- `Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/StrictJSONSchemaTests.swift` — recursive unknown-key and schema-reference regression coverage.
- `Tools/LocalDictationCandidateAdapters/Package.swift` — isolated Swift package with no Fleck production dependency.
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/CandidateAdapterModels.swift` — versioned request/event/result contract.
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/JSONLinesCodec.swift` — strict line-oriented encoding and decoding.
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateRunner/AdapterProcess.swift` — bounded subprocess lifecycle, cancellation, stderr capture, and timeout.
- `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateCLI/main.swift` — deterministic CLI used by scripts and candidate helpers.
- `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/CandidateAdapterProtocolTests.swift` — wire contract tests.
- `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/AdapterProcessTests.swift` — cancellation, timeout, malformed output, and teardown tests.
- `Tests/Fixtures/local-dictation-adapter-request-v1.json` — checked-in request example.
- `Tests/Fixtures/local-dictation-adapter-event-v1.jsonl` — checked-in event stream example.
- `Tests/Fixtures/local-dictation-admission-v1.json` — ten-case admission manifest with exact expected categories.
- `Tests/Fixtures/local-dictation-admission-v1.schema.json` — fail-closed schema for admission metadata.
- `Tests/Fixtures/local-dictation-run-sample-v2.json` — complete synthetic example for every release-evidence field.
- `Tests/Fixtures/local-dictation-run-v2.schema.json` — strict combined-component and lifecycle evidence schema.
- `Scripts/test-local-dictation-candidate-adapters.sh` — deterministic package and fixture gate.
- `Scripts/run-local-dictation-candidate.sh` — one candidate invocation that records commands and hashes without downloading at inference time.
- `docs/dictation/local-runtime-admission.md` — reproducible operator runbook.
- `docs/dictation/local-runtime-selection.md` — final measured selection record created only after all admitted runs exist.

### Existing files modified by this plan

- `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift` — adds schema-v2 component, streaming, latency, memory, cancellation, unload, and capability evidence.
- `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationValidation.swift` — makes schema v2 mandatory for release evidence and validates complete lifecycle measurements.
- `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationReport.swift` — adds fail-closed lifecycle and per-slice release gates.
- `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift` — requires a schema path and performs strict schema-key validation before decoding corpus and run JSON; `EvaluationGate` keeps its existing strict custom decoder.
- `Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationReportTests.swift` — covers all new hard gates and slice regressions.
- `Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationValidationTests.swift` — CLI-facing regression cases for unknown keys.
- `Tests/Fixtures/local-dictation-run-v1.schema.json` — remains a diagnostic compatibility schema and is explicitly ineligible for release evidence.
- `Scripts/test-local-dictation-evaluation.sh` — exercises strict decoding through the public command.
- `docs/dictation/local-model-evaluation.md` — records strict-decoding prerequisite and adapter evidence provenance.
- `TESTING.md` — adds the isolated candidate-adapter verification command if the file is free; otherwise stop and coordinate before editing it.

## Task 1: Reject unknown evaluation keys before Codable decoding

**Files:**

- Create: `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/StrictJSONSchema.swift`
- Create: `Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/StrictJSONSchemaTests.swift`
- Test fixtures: `Tests/Fixtures/local-dictation-evaluation-v1.schema.json`
- Test fixtures: `Tests/Fixtures/local-dictation-run-v1.schema.json`

**Interfaces:**

- Produces: `public enum StrictJSONSchema`.
- Produces: `public static func unknownKeyIssues(instanceData:schemaData:) throws -> [StrictJSONIssue]`.
- Produces: `public struct StrictJSONIssue: Equatable, Sendable { let path: String; let key: String }`.
- The validator implements only the checked-in schema subset: object
  `properties`, `additionalProperties: false`, array `items`, local
  references whose strings start with `#/$defs/`, and `anyOf` selection
  for object versus null.
- Codable and `EvaluationValidator` remain responsible for value types,
  required fields, enums, ranges, and semantic validation.

- [ ] **Step 1: Write recursive unknown-key tests**

Add tests that mutate the decoded JSON object rather than adding permanent
invalid fixtures:

```swift
@Test func rejectsUnknownTopLevelCorpusKey() throws {
  let instance = try objectFixture("local-dictation-evaluation-v1.json")
  var changed = instance
  changed["unexpected"] = true
  let issues = try StrictJSONSchema.unknownKeyIssues(
    instanceData: try JSONSerialization.data(withJSONObject: changed),
    schemaData: try fixture("local-dictation-evaluation-v1.schema.json")
  )
  #expect(issues == [StrictJSONIssue(path: "/unexpected", key: "unexpected")])
}

@Test func rejectsUnknownNestedRunKeyThroughRefAndArray() throws {
  var run = try objectFixture("local-dictation-run-sample-v1.json")
  var results = try #require(run["results"] as? [[String: Any]])
  var first = results[0]
  var latency = try #require(first["latency"] as? [String: Any])
  latency["mysteryMilliseconds"] = 1
  first["latency"] = latency
  results[0] = first
  run["results"] = results
  let issues = try StrictJSONSchema.unknownKeyIssues(
    instanceData: try JSONSerialization.data(withJSONObject: run),
    schemaData: try fixture("local-dictation-run-v1.schema.json")
  )
  #expect(issues == [
    StrictJSONIssue(
      path: "/results/0/latency/mysteryMilliseconds",
      key: "mysteryMilliseconds"
    )
  ])
}
```

- [ ] **Step 2: Run the tests and confirm the contract is missing**

Run:

```bash
swift test --package-path Tools/LocalDictationEvaluation \
  --filter StrictJSONSchemaTests
```

Expected: build failure because `StrictJSONSchema` and `StrictJSONIssue` do not
exist.

- [ ] **Step 3: Implement the narrow schema walker**

Use Foundation JSON values and JSON Pointer escaping. The public entry point
must sort issues by path so output is deterministic:

```swift
public struct StrictJSONIssue: Equatable, Sendable {
  public let path: String
  public let key: String

  public init(path: String, key: String) {
    self.path = path
    self.key = key
  }
}

public enum StrictJSONSchema {
  public static func unknownKeyIssues(
    instanceData: Data,
    schemaData: Data
  ) throws -> [StrictJSONIssue] {
    let instance = try JSONSerialization.jsonObject(with: instanceData)
    let schema = try JSONSerialization.jsonObject(with: schemaData)
    guard let root = schema as? [String: Any] else {
      throw StrictJSONSchemaError.invalidSchema
    }
    return try walk(instance: instance, schema: root, root: root, path: "")
      .sorted { ($0.path, $0.key) < ($1.path, $1.key) }
  }
}
```

Resolve only local `$ref` strings with the exact prefix `#/$defs/`. Reject an
unsupported reference or malformed schema with `StrictJSONSchemaError` rather
than accepting the instance. For `anyOf`, select the object branch when the
instance is an object, the array branch for an array, and the `null` branch for
`NSNull`; if no branch matches, leave type rejection to Codable.

- [ ] **Step 4: Run focused and package tests**

Run:

```bash
swift test --package-path Tools/LocalDictationEvaluation \
  --filter StrictJSONSchemaTests
swift test --package-path Tools/LocalDictationEvaluation
```

Expected: all tests pass and the checked-in valid corpus/run remain issue-free.

- [ ] **Step 5: Commit**

```bash
git add \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/StrictJSONSchema.swift \
  Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/StrictJSONSchemaTests.swift
git commit -m "fix: reject unknown local dictation evidence keys"
```

## Task 2: Enforce strict schemas through the public evaluation CLI

**Files:**

- Modify: `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift`
- Modify: `Scripts/test-local-dictation-evaluation.sh`
- Modify: `docs/dictation/local-model-evaluation.md`

**Interfaces:**

- The CLI adds `--corpus-schema` and `--run-schema` only to commands that
  consume the corresponding document. `EvaluationGate` retains its existing
  custom decoder that already rejects unknown keys.
- `read(_:path:schemaPath:)` runs `StrictJSONSchema` before `JSONDecoder`.
- Unknown keys fail with exit code `2` and stable stderr in the form
  `input error: PATH unknown-key:/json/pointer`.
- Shell scripts pass checked-in schema paths explicitly; no current-working-
  directory inference is permitted inside the CLI.

- [ ] **Step 1: Add CLI regression coverage to the public script**

Create a temporary run by copying the sample through `sed` or a fixture helper
already used by the script, inserting one nested unknown key. Invoke
`validate-run` with both schema paths and assert exit code `2` plus the exact
pointer. Keep the temporary file under `mktemp -d` and remove only that exact
directory in the script trap.

- [ ] **Step 2: Confirm the old CLI silently accepts the key**

Run:

```bash
Scripts/test-local-dictation-evaluation.sh
```

Expected: the new assertion fails because the existing CLI reaches ordinary
Codable decoding without reporting the unknown key.

- [ ] **Step 3: Thread explicit schema paths through `Command`**

The resulting command shapes are:

```swift
private enum Command {
  case validateCorpus(corpus: String, corpusSchema: String)
  case validateRun(
    corpus: String,
    corpusSchema: String,
    run: String,
    runSchema: String
  )
  case report(
    corpus: String,
    corpusSchema: String,
    run: String,
    runSchema: String,
    gate: String,
    output: String
  )
}
```

Do not add optional schema behavior. Missing schema flags are argument errors so
release evidence cannot accidentally use permissive decoding.

- [ ] **Step 4: Implement strict read ordering**

```swift
private static func read<T: Decodable>(
  _ type: T.Type,
  path: String,
  schemaPath: String
) throws -> T {
  let data = try readData(path: path)
  let schema = try readData(path: schemaPath)
  let issues = try StrictJSONSchema.unknownKeyIssues(
    instanceData: data,
    schemaData: schema
  )
  if let issue = issues.first {
    throw InputError(path: path, kind: "unknown-key:\(issue.path)")
  }
  do {
    return try JSONDecoder().decode(T.self, from: data)
  } catch {
    throw InputError(path: path, kind: "invalid-json-or-schema")
  }
}
```

Map a malformed validator schema to a file/input failure; never fall back to
permissive decoding.

- [ ] **Step 5: Update every documented command and run all evaluation tests**

Run:

```bash
Scripts/test-local-dictation-evaluation.sh
swift test --package-path Tools/LocalDictationEvaluation
```

Expected: all commands pass with explicit schemas and the injected unknown key
fails closed.

- [ ] **Step 6: Commit**

```bash
git add \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluationCLI/main.swift \
  Scripts/test-local-dictation-evaluation.sh \
  docs/dictation/local-model-evaluation.md
git commit -m "fix: enforce strict local dictation schemas"
```

## Task 3: Upgrade release evidence to cover every hard gate

**Files:**

- Modify: `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift`
- Modify: `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationValidation.swift`
- Modify: `Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationReport.swift`
- Modify: `Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationValidationTests.swift`
- Modify: `Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationReportTests.swift`
- Create: `Tests/Fixtures/local-dictation-run-sample-v2.json`
- Create: `Tests/Fixtures/local-dictation-run-v2.schema.json`
- Modify: `docs/dictation/local-model-evaluation.md`

**Interfaces:**

- Produces: `CandidateComponentIdentity` with exact ASR or cleanup role,
  model/runtime revisions, quantization, artifact hash, download bytes,
  installed bytes, license review, and required runtime ABI.
- Produces: `CandidateCapability` with `provisionalResults` as the first
  capability. No runtime may claim streaming solely by emitting a final result.
- Produces: `CandidateRunStage` so ASR-only, cleanup-only, and combined evidence
  have truthful component cardinalities and stage-specific applicable gates.
- Produces: `ProvisionalMeasurement`, expanded `LatencyMeasurement`, expanded
  `ResourceMeasurement`, expanded `UnloadEvidence`, and
  `ReliabilityEvidence`, `CancellationResourceEvidence`, and structured
  `SupplyChainEvidence`.
- Produces: schema-v2 `StandardBaselineEvidence.sliceMetrics` so category and
  mixed-direction regressions compare like-for-like rather than against a
  language-wide aggregate.
- Produces: `EvaluationSliceGate` entries for every locked corpus category and
  both required mixed-direction tags `mixed-en-zh` and `mixed-zh-en`.
- Existing schema-v1 runs remain decodable for diagnostics but are never
  eligible when `releaseEvidence == true`.

- [ ] **Step 1: Write schema-v2 validation tests first**

Add a complete v2 fixture and tests that independently remove or invalidate
each required release field. The representative assertions are:

```swift
@Test func releaseEvidenceRequiresSchemaV2AndExactComponents() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.schemaVersion = 1
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "release_schema_version" && $0.path == "/schemaVersion"
  })

  run = try decodeV2Run()
  run.components.append(run.components[0])
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "component_roles" && $0.path == "/components"
  })
}

@Test func claimedStreamingRequiresCompleteProvisionalEvidence() throws {
  let corpus = try decodeCorpus()
  var run = try decodeV2Run()
  run.claimedCapabilities = [.provisionalResults]
  run.results[0].provisional = nil
  #expect(EvaluationValidator.validate(run: run, against: corpus).contains {
    $0.code == "missing_provisional_evidence"
      && $0.path == "/results/0/provisional"
  })
}
```

Also cover duplicate component roles, malformed SHA-256, component byte totals,
negative timing, missing cancellation timing, missing unload duration, post-
unload memory below zero, ready-idle delta inconsistent with absolute memory,
missing baseline slice metrics, missing category gates, missing mixed direction,
run-stage/component-cardinality mismatches, a prompt-leaked or otherwise
non-meaningful first partial, cancellation insertion or post-cancel unload
regressions, too few repeated runs, nonzero crash/hang/OOM/corruption-acceptance
counts, missing or malformed conversion recipe, provenance, runtime-binary,
redistribution, attribution, removal, or rollback evidence, and a schema-v1 run
attempting `releaseEvidence: true`.

- [ ] **Step 2: Run focused tests and verify current contracts cannot compile**

Run:

```bash
swift test --package-path Tools/LocalDictationEvaluation \
  --filter EvaluationValidationTests
```

Expected: build failure because the v2 component and lifecycle evidence types
do not exist.

- [ ] **Step 3: Add exact component and capability types**

Add these public contracts without replacing the existing combined display
identity:

```swift
public enum CandidateComponentRole: String, Codable, Sendable {
  case asr
  case cleanup
}

public enum CandidateRunStage: String, Codable, Sendable {
  case asrOnly
  case cleanupOnly
  case combined
}

public enum CandidateCapability: String, Codable, Sendable {
  case provisionalResults
}

public struct CandidateComponentIdentity: Codable, Equatable, Sendable {
  public var role: CandidateComponentRole
  public var componentID: String
  public var modelID: String
  public var modelRevision: String
  public var runtimeName: String
  public var runtimeRevision: String
  public var runtimeABI: String
  public var quantization: String
  public var artifactSHA256: String
  public var conversionRecipeSHA256: String
  public var provenanceRecordSHA256: String
  public var downloadBytes: Int64
  public var installedBytes: Int64
  public var licenseReview: String
}

public enum RuntimeBinaryDistribution: String, Codable, Sendable {
  case evaluationHelper
  case signedInApp
}

public struct RuntimeBinaryIdentity: Codable, Equatable, Sendable {
  public var binaryID: String
  public var sourceRevision: String
  public var buildRecipeSHA256: String
  public var binarySHA256: String
  public var distribution: RuntimeBinaryDistribution
}

public enum RedistributionDecision: String, Codable, Sendable {
  case approved
  case rejected
  case pending
}

public struct SupplyChainEvidence: Codable, Equatable, Sendable {
  public var runtimeBinaries: [RuntimeBinaryIdentity]
  public var redistributionDecision: RedistributionDecision
  public var attributionNoticeSHA256: String
  public var removalPlanRevision: String
  public var rollbackPlanRevision: String
}

public struct EvaluationSliceMetric: Codable, Equatable, Sendable {
  public var sliceID: String
  public var metric: EvaluationMetricKind
  public var value: Double
}

public struct ReliabilityEvidence: Codable, Equatable, Sendable {
  public var repeatedRunCount: Int
  public var crashCount: Int
  public var hangCount: Int
  public var metalOOMCount: Int
  public var corruptedModelAcceptedCount: Int
}

public struct CancellationResourceEvidence: Codable, Equatable, Sendable {
  public var observationID: String
  public var requestToControlMilliseconds: Double
  public var insertionOccurred: Bool
  public var preCancelMemoryBytes: Int64
  public var memoryAfterCancelUnloadBytes: Int64
  public var postCancelUnloadDeltaBytes: Int64
  public var cancelUnloadMilliseconds: Double
}
```

`CandidateRun` gains `stage`, `components`, `claimedCapabilities`,
`cancellationResourceEvidence`, and `supplyChain`. Its custom decoder defaults
new collections only for schema-v1 diagnostic input; schema v2 requires the
stage and all applicable evidence.

Component cardinality is exact:

- `.asrOnly`: exactly one ASR component and no cleanup component;
- `.cleanupOnly`: exactly one cleanup component and no ASR component;
- `.combined`: exactly one ASR and one cleanup component.

Cleanup Off is represented by the corresponding `.asrOnly` run, not by a fake
cleanup component. Combined confirmation reuses that ASR-only result as its Off
comparison. Component byte totals in every observation must match the sum of
the stage's components so one model cannot disappear from size gates.

`StandardBaselineEvidence` gains `sliceMetrics: [EvaluationSliceMetric]`,
defaulted to an empty array only for schema-v1 diagnostics. `CandidateRun`
gains `reliability: ReliabilityEvidence?`; schema v2 and release validation
require it.

- [ ] **Step 4: Add lifecycle measurements**

Retain the existing schema-v1 properties for diagnostic decoding and add the
following schema-v2 fields. New lifecycle fields are optional in the Swift
in-memory type only so old synthetic runs decode; the v2 schema and release
validator require every applicable value.

```swift
public struct ProvisionalMeasurement: Codable, Equatable, Sendable {
  public var firstMeaningfulPartialMilliseconds: Double
  public var updateIntervalP95Milliseconds: Double
  public var emittedPartialCount: Int
  public var revisedPartialCount: Int
  public var instabilityRate: Double
}

public struct LatencyMeasurement: Codable, Equatable, Sendable {
  public var coldLoadMilliseconds: Double?
  public var asrMilliseconds: Double
  public var cleanupMilliseconds: Double
  public var endToEndMilliseconds: Double
  public var finalASRMilliseconds: Double?
  public var stopToInsertionMilliseconds: Double?
  public var cancellationMilliseconds: Double?

  public init(
    coldLoadMilliseconds: Double?,
    asrMilliseconds: Double,
    cleanupMilliseconds: Double,
    endToEndMilliseconds: Double,
    finalASRMilliseconds: Double? = nil,
    stopToInsertionMilliseconds: Double? = nil,
    cancellationMilliseconds: Double? = nil
  ) {
    self.coldLoadMilliseconds = coldLoadMilliseconds
    self.asrMilliseconds = asrMilliseconds
    self.cleanupMilliseconds = cleanupMilliseconds
    self.endToEndMilliseconds = endToEndMilliseconds
    self.finalASRMilliseconds = finalASRMilliseconds
    self.stopToInsertionMilliseconds = stopToInsertionMilliseconds
    self.cancellationMilliseconds = cancellationMilliseconds
  }
}

public struct ResourceMeasurement: Codable, Equatable, Sendable {
  public var peakMemoryBytes: Int64
  public var idleMemoryBytes: Int64
  public var thermalState: ThermalState
  public var energyImpact: Double
  public var modelDownloadBytes: Int64
  public var modelInstalledBytes: Int64
  public var preLoadMemoryBytes: Int64?
  public var readyIdleMemoryBytes: Int64?
  public var readyIdleDeltaBytes: Int64?
}

public struct UnloadEvidence: Codable, Equatable, Sendable {
  public var unloadAttempted: Bool
  public var unloadSucceeded: Bool
  public var memoryAfterUnloadBytes: Int64
  public var observedAt: String
  public var preLoadMemoryBytes: Int64?
  public var postUnloadDeltaBytes: Int64?
  public var unloadMilliseconds: Double?
}
```

The existing `cleanupMilliseconds`, `peakMemoryBytes`, energy, thermal,
download bytes, installed bytes, and absolute post-unload memory fields remain
and gain explicit v2 gates. Custom decoders reject unknown keys for both
versions; they do not invent release measurements from schema-v1 aggregate
values.

Each `UtteranceResult` gains `provisional: ProvisionalMeasurement?`. A run that
claims `.provisionalResults` requires provisional evidence on every ordinary
speech case. A final-only candidate must omit the capability and the field.

The timing origin for `firstMeaningfulPartialMilliseconds` is the monotonic
instant when the first audio sample is accepted by the runtime stream. A
partial is meaningful only when, after NFKC normalization and removal of
whitespace, punctuation-only output, language tags, and runtime control tokens,
it contains at least one English word, number, or Han character also present in
the final transcript. Context-prompt text emitted during the silence/noise case
is never meaningful. Wrong/retracted units contribute to `instabilityRate` and
cannot satisfy the first-meaningful-partial gate.

Cancellation timing begins when the runner sends the cancel request and ends
when control is returned with no active decode. The linked
`CancellationResourceEvidence.observationID` must identify the cancellation
case, `insertionOccurred` must be false, and post-cancel unload duration and
memory delta must pass the same fail-closed resource bounds as normal unload.

- [ ] **Step 5: Define fail-closed slice and lifecycle gates**

Extend the strict `EvaluationGate` decoder with schema version 2 and these
required fields:

```swift
public struct EvaluationSliceGate: Codable, Equatable, Sendable {
  public var sliceID: String
  public var metric: EvaluationMetricKind
  public var maximumCandidateValue: Double
  public var maximumRegressionFromStandard: Double
}

public var sliceGates: [EvaluationSliceGate]
public var maxFirstMeaningfulPartialMilliseconds: Double
public var maxProvisionalUpdateIntervalMilliseconds: Double
public var maxProvisionalInstabilityRate: Double
public var maxFinalASRMilliseconds: Double
public var maxCleanupMilliseconds: Double
public var maxStopToInsertionMilliseconds: Double
public var maxCancellationMilliseconds: Double
public var maxReadyIdleDeltaBytes: Int64
public var maxPostUnloadDeltaBytes: Int64
public var maxUnloadMilliseconds: Double
public var minimumRepeatedRunCount: Int
```

The report derives `category:<category>` slices from the existing corpus
`categories` field. A release corpus with mixed cases must contain and gate
`category:mixed-en-zh` and `category:mixed-zh-en`. Every category present in the
release corpus needs one gate for each applicable metric; `(sliceID, metric)`
pairs must be unique. An absent, duplicate, or uncomputable slice fails closed.

Gate applicability is determined by `CandidateRunStage`:

- `.asrOnly` evaluates ASR quality/latency, streaming when claimed, dictionary,
  semantic, resource, cancellation, offline, reliability, and supply-chain
  identity; cleanup gates are not applicable.
- `.cleanupOnly` evaluates cleanup fidelity/latency, protected content,
  resource, cancellation, offline, reliability, and supply-chain identity; ASR
  and streaming gates are not applicable.
- `.combined` evaluates every ASR and cleanup gate plus handoff and
  stop-to-insertion latency.

Not-applicable outcomes are explicit and are never counted as passes. When
provisional results are claimed, all three provisional limits are hard
gates. When they are not claimed, the report labels those three gates not
applicable and never describes the candidate as streaming. Final ASR, cleanup,
stop-to-insertion, cancellation, ready-idle delta, peak memory, unload duration,
post-unload delta, storage, semantic safety, offline evidence, and category
gates receive explicit applicable or not-applicable outcomes for the stage.

The checked-in gate sets `minimumRepeatedRunCount` to 50. The reliability gate
requires `repeatedRunCount >= minimumRepeatedRunCount` and zero crashes, hangs,
Metal OOMs, or accepted corrupted models. Supply-chain
validation requires at least one uniquely identified runtime binary, valid
artifact/build/recipe/provenance/NOTICE hashes, an approved redistribution
decision, and nonblank versioned removal and rollback plans. A selection-stage
binary may be `.evaluationHelper`; the later packaged release run must replace
that identity with `.signedInApp` before release approval.

- [ ] **Step 6: Add report tests for every design threshold**

Build one passing v2 report, then mutate exactly one measurement per test and
assert the corresponding stable gate ID fails:

```swift
let expectedGateIDs: Set<String> = [
  "english-wer", "mandarin-cer", "mixed-language",
  "protected-terms", "numbers", "negations", "silence-noise",
  "first-meaningful-partial", "partial-interval", "partial-instability",
  "final-asr-latency", "cleanup-latency", "stop-to-insertion",
  "cancellation-latency", "peak-memory", "ready-idle-delta",
  "unload-duration", "post-unload-delta", "energy", "thermal",
  "download-size", "installed-size", "offline", "reliability-repetition",
  "reliability-failures", "cancellation-no-insertion",
  "cancellation-post-unload", "supply-chain-identity",
  "supply-chain-redistribution", "supply-chain-removal-rollback",
  "failure-cancellation"
]
#expect(expectedGateIDs.isSubset(of: Set(report.gateOutcomes.map(\.id))))
```

Assert category gate IDs are deterministically prefixed `slice:` and that one
English technical category regression plus each mixed direction can fail
without being hidden by a good aggregate score.

- [ ] **Step 7: Run the full evaluator gate**

Run:

```bash
Scripts/test-local-dictation-evaluation.sh
swift test --package-path Tools/LocalDictationEvaluation
```

Expected: schema-v1 diagnostic fixtures still validate as non-release evidence,
the complete v2 fixture passes, every missing v2 field fails closed, and every
design threshold has an explicit gate outcome.

- [ ] **Step 8: Commit**

```bash
git add \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationModels.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationValidation.swift \
  Tools/LocalDictationEvaluation/Sources/LocalDictationEvaluation/EvaluationReport.swift \
  Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationValidationTests.swift \
  Tools/LocalDictationEvaluation/Tests/LocalDictationEvaluationTests/EvaluationReportTests.swift \
  Tests/Fixtures/local-dictation-run-sample-v2.json \
  Tests/Fixtures/local-dictation-run-v2.schema.json \
  docs/dictation/local-model-evaluation.md
git commit -m "feat: gate complete local dictation lifecycle evidence"
```

## Task 4: Define the candidate adapter wire protocol

**Files:**

- Create: `Tools/LocalDictationCandidateAdapters/Package.swift`
- Create: `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/CandidateAdapterModels.swift`
- Create: `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateProtocol/JSONLinesCodec.swift`
- Create: `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/CandidateAdapterProtocolTests.swift`
- Create: `Tests/Fixtures/local-dictation-adapter-request-v1.json`
- Create: `Tests/Fixtures/local-dictation-adapter-event-v1.jsonl`

**Interfaces:**

- Produces: `CandidateAdapterRequest` with `schemaVersion == 1`.
- Produces: `CandidateAdapterOperation` cases `load`, `transcribe`, `clean`,
  `cancel`, `unload`, and `shutdown`.
- Produces: `CandidateAdapterEvent` cases `ready`, `partial`, `final`,
  `cancelled`, `unloaded`, `measurement`, and `failure`.
- Every request carries a unique `requestID`; every event echoes it.
- Transcription input is one explicit local WAV/PCM asset path plus locale and
  bounded context phrases. Cleanup input is one dictionary baseline plus
  protected forms and cleanup mode.
- The wire protocol never carries a model download URL or arbitrary shell
  command.

- [ ] **Step 1: Write round-trip and rejection tests**

```swift
@Test func requestRoundTripsWithBoundedContext() throws {
  let request = CandidateAdapterRequest(
    schemaVersion: 1,
    requestID: "request-1",
    operation: .transcribe,
    audioPath: "/fixtures/mixed.wav",
    sampleRate: 16_000,
    localeIdentifier: "auto",
    contextPhrases: ["Fleck", "SwiftUI"],
    transcript: nil,
    protectedForms: [],
    cleanupMode: nil
  )
  #expect(try JSONLinesCodec.decodeRequest(JSONLinesCodec.encode(request)) == request)
}

@Test func requestRejectsUnknownKeyAndMoreThanOneHundredContextPhrases() throws {
  // Assert strict unknown-key failure and protocol validation failure.
}
```

Also cover newline rejection in scalar strings, non-local/relative asset paths,
empty identifiers, unsupported schema versions, duplicate context phrases,
more than 100 context phrases, and an operation with fields that do not belong
to it.

- [ ] **Step 2: Run tests and confirm the package is absent**

Run:

```bash
swift test --package-path Tools/LocalDictationCandidateAdapters
```

Expected: failure because the package does not exist.

- [ ] **Step 3: Create the standalone package**

Use macOS 14 as the protocol-tool floor. The package has one library product
`LocalDictationCandidateProtocol` and one executable product
`local-dictation-candidate`. It has no root Fleck dependency and no candidate
runtime dependency.

- [ ] **Step 4: Implement deterministic JSON-lines encoding**

Use sorted keys and exactly one UTF-8 JSON object per line:

```swift
public enum JSONLinesCodec {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    guard !data.contains(0x0A), !data.contains(0x0D) else {
      throw CandidateAdapterProtocolError.embeddedNewline
    }
    data.append(0x0A)
    return data
  }
}
```

Decode through a strict allowed-key contract, not bare Codable. Keep the
allowed-key sets adjacent to the corresponding wire structs so schema changes
must update code and fixtures in one review.

- [ ] **Step 5: Run package tests and fixture round trips**

Run:

```bash
swift test --package-path Tools/LocalDictationCandidateAdapters
```

Expected: all protocol tests pass; checked-in JSON/JSONL fixtures decode and
re-encode byte-for-byte apart from the final newline rule.

- [ ] **Step 6: Commit**

```bash
git add Tools/LocalDictationCandidateAdapters \
  Tests/Fixtures/local-dictation-adapter-request-v1.json \
  Tests/Fixtures/local-dictation-adapter-event-v1.jsonl
git commit -m "feat: define local dictation adapter protocol"
```

## Task 5: Add fail-closed subprocess lifecycle control

**Files:**

- Create: `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateRunner/AdapterProcess.swift`
- Create: `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateRunner/BoundedOutput.swift`
- Create: `Tools/LocalDictationCandidateAdapters/Tests/LocalDictationCandidateAdaptersTests/AdapterProcessTests.swift`
- Modify: `Tools/LocalDictationCandidateAdapters/Package.swift`

**Interfaces:**

- Consumes: `CandidateAdapterRequest` and `CandidateAdapterEvent`.
- Produces: `actor AdapterProcess`.
- Produces: `start(executableURL:arguments:environment:)`,
  `send(_:)`, `events()`, `cancel(requestID:timeout:)`, and `shutdown(timeout:)`.
- Only an explicitly resolved absolute executable path may run.
- Environment starts from an allowlist (`PATH`, `TMPDIR`, locale variables,
  and candidate-specific Metal diagnostic variables), not the entire parent
  environment.
- Stdout is protocol-only. Stderr is retained in a bounded 1 MiB diagnostic
  ring that redacts configured fixture/model roots and never records transcript
  text in the selection report.

- [ ] **Step 1: Write fake-adapter lifecycle tests**

The test target builds one tiny fixture executable that speaks the protocol.
Cover ready, partial/final ordering, unexpected request IDs, malformed JSON,
stdout flood, stderr flood, timeout, cooperative cancellation, forced
termination, and EOF before shutdown acknowledgement.

- [ ] **Step 2: Confirm tests fail without `AdapterProcess`**

Run:

```bash
swift test --package-path Tools/LocalDictationCandidateAdapters \
  --filter AdapterProcessTests
```

Expected: build failure because the runner target is absent.

- [ ] **Step 3: Implement bounded pipes and lifecycle**

Use `Process`, `Pipe`, task groups, and an injected continuous clock. Do not wait
synchronously on the main actor. A timeout first sends `.cancel`, then
`.shutdown`, then terminates the exact child process if it does not exit within
the locked grace interval. Record which path occurred.

- [ ] **Step 4: Run cancellation and leak repetitions**

Run:

```bash
for i in $(seq 1 50); do
  swift test --package-path Tools/LocalDictationCandidateAdapters \
    --filter AdapterProcessTests >/dev/null || exit 1
done
```

Expected: 50 passes, no surviving fixture-adapter processes, and no unbounded
stdout/stderr memory growth.

- [ ] **Step 5: Commit**

```bash
git add Tools/LocalDictationCandidateAdapters
git commit -m "feat: isolate local dictation candidate processes"
```

## Task 6: Add the ten-case admission manifest and runner CLI

**Files:**

- Create: `Tests/Fixtures/local-dictation-admission-v1.json`
- Create: `Tests/Fixtures/local-dictation-admission-v1.schema.json`
- Create: `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateCLI/main.swift`
- Create: `Scripts/test-local-dictation-candidate-adapters.sh`
- Create: `Scripts/run-local-dictation-candidate.sh`
- Create: `docs/dictation/local-runtime-admission.md`

**Interfaces:**

- CLI command `validate-admission --manifest PATH --schema PATH`.
- CLI command `run --manifest PATH --adapter ABSOLUTE_PATH --model-root
  ABSOLUTE_PATH --output PATH`.
- The manifest identifies ten immutable case IDs, expected language/category,
  audio hash, context phrases, cancellation point, capture temperature, and
  whether partials are claimed.
- The script records runtime/model revisions, executable/library hashes,
  command line, OS/hardware identity, network-isolation method, start/end time,
  child exit status, and raw measurement artifacts outside transcript content.

- [ ] **Step 1: Write CLI argument and manifest tests**

Cover missing schema, relative adapter path, model root symlink escape, duplicate
case ID, wrong audio hash, unsupported schema version, output path already
existing, and exactly ten valid cases.

- [ ] **Step 2: Implement the manifest with these case roles**

1. English technical prose.
2. English developer command with identifiers and path.
3. Mandarin prose with numbers and units.
4. Mandarin technical terms.
5. English-to-Mandarin intra-utterance switch.
6. Mandarin-to-English intra-utterance switch.
7. Personal dictionary aliases and canonical forms.
8. Silence/noise hallucination case.
9. Cancellation during active decode.
10. Repeated load, inference, unload, and reload.

Use only admitted audio with exact provenance and consent. If real audio is not
yet admitted, the runner validates but refuses to label output release evidence.

- [ ] **Step 3: Implement safe command resolution**

`run-local-dictation-candidate.sh` accepts paths as arguments, validates them as
existing regular files/directories, resolves them before invocation, and never
uses `eval`, a glob, or an unresolved environment variable as an executable or
destructive target.

- [ ] **Step 4: Run the isolated gate**

Run:

```bash
Scripts/test-local-dictation-candidate-adapters.sh
```

Expected: protocol package tests pass, both adapter fixtures validate, invalid
manifests fail closed, and the fake-adapter admission run produces deterministic
metadata.

- [ ] **Step 5: Commit**

```bash
git add \
  Tests/Fixtures/local-dictation-admission-v1.json \
  Tests/Fixtures/local-dictation-admission-v1.schema.json \
  Tools/LocalDictationCandidateAdapters \
  Scripts/test-local-dictation-candidate-adapters.sh \
  Scripts/run-local-dictation-candidate.sh \
  docs/dictation/local-runtime-admission.md
git commit -m "feat: add local dictation runtime admission gate"
```

## Task 7: Implement runtime-specific admission helpers in isolated tasks

**Files:**

- Create: `Tools/LocalDictationCandidateAdapters/Adapters/WhisperAdapter/`
- Create: `Tools/LocalDictationCandidateAdapters/Adapters/NeMoSpeechAdapter/`
- Create only after route admission: `Tools/LocalDictationCandidateAdapters/Adapters/QwenASRAdapter/`
- Create: `Tools/LocalDictationCandidateAdapters/Adapters/LlamaCleanupAdapter/`
- Modify: `docs/dictation/local-runtime-admission.md`

**Interfaces:**

- Each helper reads `CandidateAdapterRequest` JSON lines from stdin and emits
  `CandidateAdapterEvent` JSON lines on stdout.
- Each helper accepts model and runtime paths only at process startup.
- Each helper loads only local files, implements cancel/unload/shutdown, and
  reports runtime version plus measured artifact identity.
- Helpers never write a `CandidateRun` directly; the Swift runner owns evidence
  normalization.

This task is four separately reviewed implementation packets because the
runtime code and failure modes are independent. They may run in parallel only
when each task owns exactly one adapter directory and no shared protocol file.

- [ ] **Step 1: Freeze exact revisions before writing an adapter**

For each candidate, record the immutable runtime commit, model revision, model
SHA-256, license text, conversion command, compiler/CMake flags, and installed
library list in that adapter's `REVISION.md`. Reject a moving branch name or an
unhashed model.

- [ ] **Step 2: Implement whisper.cpp controls**

Use the pinned whisper C API with `small` and `large-v3-turbo-q5_0`. Pass at
most 100 deduplicated context phrases through the documented initial-prompt
surface. Preserve the library transcript exactly as `final`. Rolling-window
partials are measured separately and must not be labeled stateful streaming.

- [ ] **Step 3: Implement NeMo-Speech.cpp streaming admission**

Use only the stable `nemo_speech/asr.h` ABI:

- create with `nemo_speech_asr_create`;
- pass local Q8 GGUF path in `nemo_speech_asr_model_config`;
- pass locale through `language_code`;
- pass bounded vocabulary through `nemo_speech_asr_speech_context`;
- create a stream with `nemo_speech_asr_streaming_recognize`;
- push mono Float32 audio through `nemo_speech_asr_stream_push_f32`;
- drain with `nemo_speech_asr_stream_next`;
- finish, drain finals, destroy every result, close the stream, and destroy the
  recognizer.

Build and test CPU and Metal presets. Treat speech-context boosting as an
experimental value recorded in the run; test prompt leakage and false boosting.

- [ ] **Step 4: Run the two Qwen Apple admission spikes**

Implement the same ten-case protocol against sherpa-onnx and speech-swift in
separate scratch builds. Admit at most one route to the full adapter directory.
The route must prove local-only model paths, repeatable load/unload,
cancellation, context/hotword semantics, English, Mandarin, mixed language,
and M1/8 GB resource viability. Record speech-swift as macOS 15-only.

If neither route passes, create no production Qwen adapter and record both gate
failures in the selection document.

- [ ] **Step 5: Implement both cleanup candidates through one llama.cpp helper**

The helper takes either Qwen3-0.6B Q8 or Qwen3.5-0.8B Q4_0 at startup. Use one
pinned llama.cpp revision, non-thinking mode, fixed prompt version, deterministic
sampler, strict output token ceiling, abort callback, explicit context/model
free, and no server/network mode. Emit the candidate text only; the evaluation
layer owns protected-content scoring.

- [ ] **Step 6: Run each adapter's focused lifecycle suite**

Each adapter must demonstrate:

- 50 create/load/infer/unload cycles;
- cancellation during load and decode;
- malformed/missing model failure;
- no network with the network disabled;
- no child process after shutdown;
- exact runtime and artifact identity;
- release to the process-memory bound after unload.

Do not proceed to the full corpus for an adapter that fails one admission gate.

- [ ] **Step 7: Commit adapters independently**

Use one commit per runtime adapter so a rejected runtime can be dropped without
rewriting shared protocol history:

```bash
git commit -m "test: admit whisper local dictation controls"
git commit -m "test: admit nemotron local dictation candidate"
git commit -m "test: admit qwen local dictation candidate"
git commit -m "test: admit qwen cleanup candidates"
```

## Task 8: Run the locked ASR and cleanup matrices

**Files:**

- Produce outside source control: `Artifacts/LocalDictation/{runID}/...`, where
  `{runID}` is the immutable `CandidateRun.runID`.
- Modify after adjudication: `docs/dictation/local-runtime-selection.md`
- Modify only when thresholds were predeclared: the checked-in evaluation gate fixture named by `docs/dictation/local-model-evaluation.md`

**Interfaces:**

- Consumes the existing `EvaluationCorpus` plus the schema-v2 `CandidateRun`
  and `EvaluationGate` contracts produced by Task 3.
- Produces one immutable run document per ASR-only, cleanup-only, and combined
  candidate.
- Produces one selection record linking run hashes and report results without
  checking private audio or transcript-bearing artifacts into Git.

- [ ] **Step 1: Freeze the corpus, gate, and Apple Standard baseline**

Commit corpus/gate changes before running any candidate. Record their revisions
and hashes. Capture Apple Standard cold and warm results on the same machine,
OS, microphone path, and audio set.

- [ ] **Step 2: Run ASR with cleanup Off**

Run whisper `small`, whisper turbo Q5, Nemotron Q8, and the admitted Qwen route.
Add SenseVoice Q8 only if a leading candidate fails Mandarin, installed-size,
or memory gates and the license/provenance gate has been resolved.

- [ ] **Step 3: Run cleanup on identical dictionary baselines**

Run cleanup Off, Qwen3-0.6B Q8, and Qwen3.5-0.8B Q4_0. Add Qwen3.5 Q8 only if
Q4 fails fidelity and Q8 remains within resource limits.

- [ ] **Step 4: Compare four final configurations with two new combined runs**

Reuse the two winning `.asrOnly` cleanup-Off results as the Off baselines. Run
only two new `.combined` rows by crossing those ASR candidates with the single
best cleanup candidate. The final comparison therefore contains four rows but
does not fabricate combined evidence for cleanup Off. The two actual combined
runs confirm sequential resource handoff and stop-to-insertion latency.

- [ ] **Step 5: Generate and verify reports**

For every run:

```bash
corpus_path=Artifacts/LocalDictation/locked/corpus.json
run_path=Artifacts/LocalDictation/nemotron-3-5-q8-cleanup-off/candidate-run.json
gate_path=Artifacts/LocalDictation/locked/gate.json
report_path=Artifacts/LocalDictation/nemotron-3-5-q8-cleanup-off/report.md
Scripts/evaluate-local-dictation.sh \
  report \
  --corpus "$corpus_path" \
  --corpus-schema Tests/Fixtures/local-dictation-evaluation-v1.schema.json \
  --run "$run_path" \
  --run-schema Tests/Fixtures/local-dictation-run-v2.schema.json \
  --gate "$gate_path" \
  --output "$report_path"
```

Expected: each selected run passes every hard gate applicable to its declared
run stage. A `reviewRequired` or failed result is not a selection. Passing this
candidate-selection matrix does not approve the packaged Fleck release; that
requires later `.signedInApp` runtime evidence.

- [ ] **Step 6: Write the selection record**

`docs/dictation/local-runtime-selection.md` must name:

- selected ASR model/runtime/revision/quantization;
- selected cleanup model/runtime or cleanup Off;
- exact artifact, conversion recipe, provenance record, runtime source/build,
  and evaluation-helper binary hashes plus download and installed sizes;
- measured metrics and gate decisions by language/category;
- stage-specific applicable, not-applicable, and failed gate outcomes;
- license, attribution, and structured redistribution disposition;
- rejected candidates and reasons;
- macOS floor;
- signed in-app runtime library/package strategy and runtime ABI;
- one-click bundle composition and download-origin requirement;
- versioned removal and rollback procedures;
- the exact next production file allowlist.

- [ ] **Step 7: Commit only non-private evidence**

```bash
git add docs/dictation/local-runtime-selection.md
git commit -m "docs: select Fleck local dictation runtime"
```

Do not add private audio, transcript-bearing raw runs, unsigned binaries,
downloaded weights, or local measurement directories.

## Task 9: Final verification and production-plan handoff

**Files:**

- Modify: `TESTING.md` only if ownership is clear.
- No production runtime or UI file.

- [ ] **Step 1: Run focused gates**

```bash
Scripts/test-local-dictation-evaluation.sh
Scripts/test-local-dictation-candidate-adapters.sh
swift test --package-path Tools/LocalDictationEvaluation
swift test --package-path Tools/LocalDictationCandidateAdapters
```

Expected: all pass.

- [ ] **Step 2: Run the repository gate**

```bash
Scripts/validate-macos.sh
```

Expected: complete validation succeeds with the release candidate flag disabled
and no root-package candidate dependency.

- [ ] **Step 3: Confirm the diff and supply-chain boundary**

```bash
git status --short
git diff --check
git diff --name-only 27f7a44e93e8395d8d9c3d952064a28c87b1768d...HEAD
git ls-files | rg '(^|/)(models?|Artifacts)/' && exit 1 || true
```

Expected: only the documented tool, fixture, script, testing-doc, research, and
selection files changed; no weights, private audio, generated runs, root package
files, product runtime, or shared UI files are present.

- [ ] **Step 4: Obtain fresh review**

Provide the exact worktree, accepted base, head, complete diff, focused outputs,
full validation output, selected run hashes, and license/provenance evidence to
a fresh Sol/High reviewer. Accept only `ship`. Route `fix-first` corrections to
the same implementation lane and repeat verification/review.

- [ ] **Step 5: Write the next plan from measured selection**

Create a separate production implementation plan whose exact files and native
dependency are derived from `docs/dictation/local-runtime-selection.md`. It must
cover, in this order:

1. selected in-process ASR and cleanup adapters;
2. shared inference resource lease;
3. signed data-only bundle catalog and atomic ASR/cleanup model installation;
4. production dictionary-store/resolver injection;
5. coordinated onboarding and Settings one-click UI;
6. packaged offline, signing, update, rollback, removal, and regional-download
   validation.

The packaged validation must replace every selection-stage
`.evaluationHelper` identity with the exact `.signedInApp` runtime binary
identity. It must prove that bundle removal deletes only model/data artifacts,
that no insertion occurs after cancellation, that post-cancel unload satisfies
the declared bounds, and that rollback reactivates only a previously verified
data pack. Candidate-selection reports alone cannot satisfy this release gate.

Do not begin that plan until the shared-file owner explicitly releases every
integration file it names.

## Post-selection PR sequence

This is the expected review topology after Task 9, not permission to skip the
selection gate:

1. **Runtime Core PR:** selected native adapter(s) packaged and signed inside
   Fleck, generic cleanup safety, resource lease, no shared UI.
2. **Bundle Manager PR:** signed data-only catalog, transactional
   install/update/resume, component manifests, runtime-ABI compatibility,
   rollback/removal, distribution-origin abstraction.
3. **Runtime Integration PR:** coordinator/provider/dictionary injection and
   history identity, coordinated against current shared-file ownership.
4. **Onboarding and Settings PR:** one user-facing Install action, native
   progress/retry/update/remove states, automatic selection, accessibility.
5. **Release Validation PR:** packaged harnesses, M1/8 GB evidence, offline
   evidence, Mainland China download-route evidence, license/NOTICE packaging.

Each PR must be independently testable, receive fresh final review, and retain
Apple Standard as a working fallback.
