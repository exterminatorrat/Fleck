# Fleck Local Dictation Evaluation

## Purpose and Phase A boundary

This procedure evaluates a candidate for Fleck's entirely local English,
Mandarin, and mixed English-Mandarin Enhanced Dictation path. It is a
measurement gate, not a model selector. Phase A contains only the
dependency-free text contracts, deterministic metrics, strict validation,
synthetic sample report, and operator procedure. The checked-in corpus has no
audio, the checked-in run is synthetic, and neither is release evidence.
Every corpus/run validation or report command requires an explicit checked-in
JSON schema path; the CLI never infers a schema from the current directory.

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
   and content-telemetry observation. A run with any network request or
   content telemetry is invalid; never silently use network inference.

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
6. Run validate-corpus and validate-run with the checked-in corpus and run
   schemas. Fix the data or stop; do not bypass a validation error and do not
   print transcript text in diagnostics. Unknown JSON keys are rejected before
   Codable decoding.
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
   requires review; failed status fails; notRequired is valid only when no
   cleaned result exists. A simplistic distance threshold is not semantic
   proof.
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
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json \
  --corpus-schema Tests/Fixtures/local-dictation-evaluation-v1.schema.json
Scripts/evaluate-local-dictation.sh validate-run \
  --corpus Tests/Fixtures/local-dictation-evaluation-v1.json \
  --corpus-schema Tests/Fixtures/local-dictation-evaluation-v1.schema.json \
  --run Tests/Fixtures/local-dictation-run-sample-v1.json \
  --run-schema Tests/Fixtures/local-dictation-run-v1.schema.json
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
  --corpus-schema Tests/Fixtures/local-dictation-evaluation-v1.schema.json \
  --run PATH \
  --run-schema Tests/Fixtures/local-dictation-run-v1.schema.json \
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
