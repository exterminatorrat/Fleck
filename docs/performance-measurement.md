# Performance measurement harness

Status: **tooling only.** No benchmark has been run against the source in this
repository's public branches, and this document records no measurements,
budgets, or results. It describes the opt-in harness, the artifacts it emits,
and the operator-provided receipts it consumes.

This layer supplies benchmark collection and prebuilt-bundle validation. It does
not include a public paired-acceptance evaluator, and it ships no measured
budgets.

## Warning: public heads are unmeasured

The harness exists so a future release or candidate source can be measured on
one machine under one configuration. Nothing here establishes current
performance, and no number in a pull request description should be read as a
public measurement. Record the baseline source, configuration, build system,
Swift version and machine with any measured budget. To evaluate a candidate,
keep the baseline frozen and collect comparable candidate observations; do not
regenerate its budget from the candidate to make a failure pass. A receipt's
source label alone does not establish that two runs are comparable.

## What runs

`Tests/FleckPerformanceTests` is a dedicated test target that hosts real AppKit
work. Its benchmark cases are inert unless explicitly opted in; the eight
contract tests in `ForegroundPerformanceHarnessContractTests.swift` always run
and exercise the comparator and save-gate logic with synthetic values.

| Case family | Prefix | Work performed |
| --- | --- | --- |
| Hosted editor typing and selection | `editor.` | Real `NSTextView` typing, selection and caret formatting |
| Selected-content mutations | `state.` | Workspace mutation semantics at 10/100/1,000 notes |
| Note switching | `switch.identity.` | First mount and warm alternation between notes |
| Local store saves | `store.` | Save and full durable reload, including unchanged-file identity |
| App state commits | `commit.` | `AppState` durable commit only, not an end-to-end MCP request |

Each opt-in case runs one warmup and nine measured operations and emits one
`FLECK_PERF_RESULT <json>` line. The record contains the case ID, situation,
configuration, build system, Swift/macOS version, architecture, repetition and
warmup counts, error and correctness fields, median and p95 wall latency,
observed range, process CPU seconds and per-operation CPU, signpost counters,
and a baseline status of `not_configured`, `pass`, `fail` or `invalid`.

`Tests/FleckPerformanceTests/AgentCommandServiceDiagnosticTests.swift` is a
diagnostic that prints `FLECK_PERF_DIAGNOSTIC <json>` lines. It shares the
`FLECK_PERF_RUN` opt-in but produces no baseline decisions. The selector below
limits collection to the benchmark suite rather than also running diagnostics.

## Opt-in environment

All values are read from the test process environment, so the runner has to
forward them. `Scripts/run-swift-tests-with-appkit-host.sh` does this when
`FLECK_PERF_RUN` is set and derives the configuration and build-system fields
from its own arguments.

| Variable | Required | Meaning |
| --- | --- | --- |
| `FLECK_PERF_RUN` | yes | `1` enables the benchmark cases. Any other value leaves every case inert. |
| `FLECK_PERF_CONFIGURATION` | derived | Must equal the compiled configuration. The runner sets it from `FLECK_TEST_SWIFT_CONFIGURATION`. |
| `FLECK_PERF_BUILD_SYSTEM` | derived | `default`, `native`, `swiftbuild` or `xcode`. The runner sets it from `FLECK_TEST_SWIFT_BUILD_SYSTEM`. |
| `FLECK_PERF_SWIFT_VERSION` | yes | First line of `swift --version`; letters, digits, spaces and `.()+_-` only. |
| `FLECK_PERF_BASELINE_RECEIPT` | optional | Absolute path to a baseline receipt JSON. Unset means no baseline decision is made; the case's correctness checks still apply. |

A run that cannot satisfy the guard throws instead of silently measuring the
wrong configuration, so a mismatch is a visible failure, not a skipped case.

## Running the harness

The AppKit host runner takes `<package-root> <scratch-path-or-empty>
<anchored-test-identifier-regex>` and needs a selected target for a
configuration-labelled run:

```sh
FLECK_TEST_SWIFT_TARGET=FleckPerformanceTests \
FLECK_TEST_SWIFT_CONFIGURATION=release \
FLECK_TEST_SWIFT_BUILD_SYSTEM=swiftbuild \
FLECK_PERF_RUN=1 \
FLECK_PERF_SWIFT_VERSION="$(swift --version | head -n 1)" \
FLECK_PERF_BASELINE_RECEIPT=/absolute/path/to/receipt.json \
Scripts/run-nonempty-swift-tests.sh '^FleckPerformanceTests[./]ForegroundPerformanceTests[./].*$'
```

Omit `FLECK_PERF_*` entirely for an ordinary run: the harness target then only
executes its contract tests. Use `debug` and `release` builds separately; never
compare across configurations.

## Baseline receipt

A baseline receipt is the frozen budget a run is compared against. It must
describe one configuration and carry exactly one entry per benchmark case:

| Field | Value |
| --- | --- |
| `schemaVersion` | `1` |
| `baselineSourceCommit` | 40-character hexadecimal baseline commit |
| `configuration` | `debug` or `release`, matching the run |
| `buildSystem` | `default`, `native`, `swiftbuild` or `xcode`, matching the run |
| `testabilityEnabled` | `true` for testable product builds |
| `cases` | One object per benchmark case ID; the set of `caseID` values must equal the harness's benchmark case set exactly |

Each `cases` entry carries the frozen limit for that case:

| Case field | Value |
| --- | --- |
| `caseID` | Benchmark case identifier, for example `store.one_note_save.notes.1000` |
| `baselineMedianMilliseconds` | Frozen median wall latency |
| `medianNoiseMarginMilliseconds` | Allowed margin above that median |
| `baselineP95Milliseconds` | Frozen p95 wall latency |
| `p95NoiseMarginMilliseconds` | Allowed margin above that p95 |
| `baselineProcessCPUSeconds` | Frozen process CPU for the measured operations |
| `cpuNoiseMarginSeconds` | Allowed margin above that CPU total |

Every numeric value must be non-negative. A receipt that is malformed,
mismatched by configuration or build system, missing a case, carrying an
unknown case ID, or using a negative or unrepresentable value reports `invalid`
rather than comparing partial data. Identify the measured baseline source in
the receipt; this repository does not ship a pre-measured budget.

## Prebuilt bundle validation

Rebuilding between comparable runs can change the compiled product even when
source is unchanged. To measure an already-built bundle instead of rebuilding,
set:

```sh
FLECK_PERF_PREBUILT_RECEIPT=/absolute/path/to/prebuilt-receipt.json
```

In that mode the runner does not invoke `swift build`. It calls
`Scripts/validate-perf-prebuilt.py --receipt … --package-root … --configuration
… --swift-version … --sdk-version … --scratch-path …`, which re-checks the
receipt's `packageRoot`, `sourceCommit`, `sourceTree`, `configuration`,
`buildSystem`, `testabilityEnabled`, `swiftVersion` and `sdkVersion`, then
verifies the product and test bundle layout under
`.build/out/Products/<Configuration>` and the recorded `harnessSHA256`,
`bootstrapWrapperSHA256` and `testBundleExecutableSHA256` digests.

Prebuilt mode is deliberately strict: it requires an explicit configuration, a
`FleckPerformanceTests` target, `swiftbuild`, an empty scratch path, and no
enhanced-candidate or Sparkle-free build selection. Any other combination is
rejected instead of falling back to a rebuild.

## CI coverage

`macos-build` runs the tooling's mocked contract tests:

- `python3 -B -m unittest discover -s Tests/Scripts -p test_validate_perf_prebuilt.py`
- `Tests/Scripts/prebuilt-perf-wrapper.test.sh`
- `Scripts/test-nonempty-swift-test-runners.sh`

These use isolated fixtures and, for the runner tests, `swift`, `swiftc` and
`xcrun` shims prepended to `PATH`. They check the runner and validator contracts
without invoking a real compiler, test host, sampler or network resource. They
prove the tooling's behaviour, not any performance result.
