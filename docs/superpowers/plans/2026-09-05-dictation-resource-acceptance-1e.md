# Packet 1E — Resource measurements and retention decision

**Goal:** Establish whether the accepted audio-first capture and resource-aware Parakeet retention satisfy the 8 GB M1 target, with the M4 host reported separately.
**Architecture:** Export the existing content-free 1D projection through an explicitly enabled diagnostic sink; sample the exact process externally; tune retention only if repeated target-device evidence justifies it.
**Stack:** Swift, Swift Testing, existing enhanced SwiftPM lane, Darwin process sampling, existing package provenance scripts.
**Specification:** `2026-09-05-capture-feedback.md`, Packet 1E. Written together with the separate Packet 1F plan. Execute sections sequentially, with parent verification and a fresh Sol `ship` before dependent implementation.

## Scope and authority

Continue the accepted local `codex/central-orchestrator-validation` lineage at `a8ca7b0` (1D source `2fb3a1a`); preserve the unrelated root checkout. Native Sol High workers are the active implementation lane. No push, PR, merge, installed-app replacement, model download, microphone run, or package launch follows merely from this plan. Prepare a concrete candidate and request any still-missing execution authority at that gate.

The present machine is a 24 GB M4 Mac mini. Access to the 8 GB M1 MacBook is unresolved. Local implementation and fixture checks can proceed; M4 results cannot close the M1 acceptance gate.

## Section E1 — Collect existing runtime measurements

1. **Objective / success:** An opt-in local run produces bounded, content-free per-capture JSON records of existing 1D diagnostics. Disabled mode performs no disk work. Missing stages remain missing.
2. **Ownership / interfaces:** `Sources/FleckApp/DictationCoordinator.swift`, `Sources/FleckApp/FleckApp.swift`, new `Sources/FleckApp/DictationDiagnosticExporter.swift`, `Tests/FleckAppTests/DictationCoordinatorTests.swift`, new `Tests/FleckAppTests/DictationDiagnosticExporterTests.swift`. Add a dedicated diagnostic observer; do not replace the UI event observer or change the public capture lifecycle.
3. **Implementation / non-goals:** Enable only through `FLECK_DICTATION_DIAGNOSTICS_DIR` at composition. Use a newly created private run directory, at most 128 captures, stable run-local ordinal filenames, and serialized asynchronous writes. Explicitly project only numeric timings and existing fixed enums; never encode transcript, audio, note identity/title, terminal error messages, vocabulary, or destination content. Internal capture UUIDs may associate revisions but must not be exported. An updated record replaces its own earlier revision. Emit immutable snapshots when terminal outcome is known and after subsequent measurement changes. Cancellation drain is recorded after the terminal UI event; preserve that later revision without delaying UI feedback. Preserve capture-ID fencing on reentrant new captures and late ambiguity changes. Do not invent drain timing if an existing path has none. Report sink failures through a fixed diagnostic status, never as capture failure. No retention or UI changes.
4. **Verification:** Red-first tests for disabled mode, allowlisted schema/privacy sentinels, bounded records, revision replacement, write failure isolation, success/failure/cancel observations, drain revision, and reentrant/stale capture isolation. Use `bash scripts/run-nonempty-swift-tests.sh` with anchored discovered Swift Testing function names. Then rerun related coordinator/runtime/diagnostics tests and the existing enhanced adapter tests through the enhanced runner. Parent independently checks the exact diff and nonzero test counts; fresh `sol_advisor_sol_reviewer` must return `ship`.
5. **Handoff:** Exact changed paths, commands/counts, red/green evidence, content-free sample from tests, limitations and diff identity. Worker owns only these files, is not alone, must preserve/adapt to others' edits, and makes no commits or external writes. Parent commits only accepted work.

- [x] Write failing tests and implement the minimal observer/exporter.
- [x] Parent verification and fresh review; correct through the same worker if needed.
- [x] Commit accepted E1 locally before E2.

E1 source acceptance: parent final default 22/22 (`/tmp/fleck-e1-parent-final.log`), true Enhanced 63/63 before the unconditional failure-reporter correction (`/tmp/fleck-e1-parent-enhanced.log`), unchanged dependency lock, clean diff. Fresh reviewer `dictation_e1_final_review` returned `ship`. The first review required a production-visible failure signal; the same worker added one-shot fixed stderr reporting and its configured-path test. Abrupt process exit may lose queued writes. No physical measurement or retention acceptance is claimed.

## Section E2 — Exact-process resource sampling

1. **Objective / success:** Produce time-indexed RSS and physical-footprint samples for an explicitly identified Fleck PID; never substitute a similarly named process or count helper RSS as app RSS.
2. **Ownership:** Existing `Tools/LocalDictationCandidateAdapters/Sources/LocalDictationCandidateRunner/ProcessResourceSampler.swift`, `Sources/LocalDictationCandidateCLI/main.swift` under that package, and focused tests under its existing test target. Any script addition requires an exact bounded follow-up specification before delegation.
3. **Implementation:** Reuse the existing process sampler through a thin CLI entry point. Require PID and finite duration; validate inputs; emit machine-readable samples and unavailable/error status. Record PID identity/start information so exit or reuse cannot silently create a new target. Keep app and helper measurements separate. No second sampling implementation and no benchmark framework.
4. **Verification:** Red-first argument/identity/exit/failure tests and existing sampler tests via that package's Swift test command; verify discovered tests actually execute. Run a harmless local process smoke check without launching Fleck or a model. Parent checks plus fresh Sol `ship`.
5. **Authority / handoff:** Same native worker lane, exact ownership, no concurrent E1 changes or builds. Report CLI usage, units, cadence, failure semantics, and test counts; local commit after acceptance.

- [ ] Inspect the existing CLI and pin the exact command/interface before delegation.
- [ ] Implement, verify, review, and commit E2 sequentially.

### E2 execution specification (pinned after CLI inspection)

Expose `local-dictation-candidate sample-resources --pid <positive Int32> --duration-seconds <1...600> --output <new JSON path>` with fixed 100 ms cadence. Reject duplicate/unknown/missing flags, invalid PID/duration and occupied output before sampling. Reuse the Darwin provider in `ProcessResourceSampler.swift`; do not repeat its system call elsewhere. Extend its sample with optional process-start identity (default nil for existing injected providers); production obtains it from the same rusage sample. The new command requires identity and rejects a changed identity before including that sample, while existing peak-sampler consumers keep their behavior.

Own exactly the existing `ProcessResourceSampler.swift`, CLI `main.swift`, new runner `ProcessResourceTimeline.swift`, existing `ProcessResourceSamplerTests.swift`, and new `ProcessResourceTimelineTests.swift`, all under `Tools/LocalDictationCandidateAdapters`. Keep parsing tests in the new test file, using the existing CLI's testable target. Reuse its exclusive output publication (a narrow Encodable generalization is allowed). The timeline records requested PID, observed start identity, cadence, elapsed milliseconds, RSS and physical footprint in bytes, sample count, sampled peaks, completion and a fixed failure category. Retain valid samples and mark incomplete/nonzero exit on process exit, identity change or provider failure; no zero-filling, process-name search, app launch or helper aggregation. Stop at the finite deadline, propagate cancellation, and do not introduce a second benchmark framework. Inject only provider/clock seams necessary for deterministic checks.

Red-first tests cover strict parsing, exact PID, ordered samples/peaks, deadline, missing/changed identity, exit/unavailability, invalid samples and preserved incomplete evidence. Run the nonempty runner with `--package-path Tools/LocalDictationCandidateAdapters` and discovered anchored function identifiers, including existing sampler and CLI regression tests. A harmless short-lived local process may be sampled for smoke evidence. Report exact command, count and output schema. No source edits before E1's fresh `ship`; parent reruns checks and obtains a new fresh Sol review before committing E2.

## Section E3 — Reproducible measurement protocol

Prepare a content-free run manifest with commit/tree cleanliness, flags, executable and helper hashes, model receipts, OS, hardware/RAM, microphone, selected engine, power mode, thermal state and memory pressure. Include policy revision and app PID identity. Preserve every failed or cancelled trial. Associate ordinal diagnostics with trial scenario and externally sampled resource timeline; do not treat absent metrics as zero.

On **each** machine run cold, warm (within retention window), and after-Gemma captures: ten trials per state, using the same short utterance and microphone placement. Separately test normal memory, observed low reclaimable memory, Low Power Mode, idle expiry, and sleep/wake. Record actual snapshots rather than manufacturing system pressure or inferring it from allocated bytes. Do not force unsafe load on the user's machine. Record first audio buffer, first-word recall, model-ready, final output, peak RSS and residual RSS at fixed 0/5/15/30/60-second offsets after completion. Report distributions, sample counts, missingness and failures, not only averages.

Compare pre-1B/1C baseline with the accepted capture lineage for startup effects. Compare retention candidates against the **same** accepted capture code for policy effects. Do not attribute the combined startup changes to retention. Use matched utterance/scenario ordering, record cold preparation and cache state, and distinguish event-delivery timing from physical key latency. First-word recall needs supervised utterance/output comparison; diagnostics alone cannot establish it.

- [ ] Prepare manifest and trial sheet with explicit unavailable fields.
- [ ] Resolve M1 access and exact package/run authority before physical runs.
- [ ] Collect target M1 and separate M4 control evidence with provenance.

## Section E4 — Evidence-led policy decision

Current maximums are 5 seconds at <=4 active cores, otherwise 15 seconds at <=8 GiB, 30 seconds below 24 GiB, 120 seconds below 32 GiB, and 300 seconds above. Pressure warning/critical, serious/critical thermal state, Low Power Mode, missing reclaimable memory, reclaimable below 3 GiB or below 25% force zero; below 5 GiB or below 40% caps retention at 5 seconds. These are observations of the existing policy, not new tuning targets.

Keep the policy if repeated M1 evidence supports it. If evidence shows a repeatable tradeoff worth changing, write one bounded candidate specification owning only `DictationRuntimePolicy.swift` and its tests; change one variable, retain all invalidation rules, then rerun the matched measurements. Preserve Parakeet release before Gemma and no default co-residency. Fresh parent checks and Sol `ship` remain required for a policy diff. Do not tune merely because fixture tests pass.

- [ ] Record a measured keep/change decision, raw evidence links, distributions and limitations.
- [ ] If needed, implement and review one evidence-backed candidate, sequentially.
- [ ] Accept 1E only when target evidence and the policy decision are complete. Instrumentation completion is not 1E acceptance.
