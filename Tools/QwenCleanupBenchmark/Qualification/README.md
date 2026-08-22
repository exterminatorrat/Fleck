# Qwen cleanup qualification

This is a developer-only qualification of the already-downloaded Qwen3.5-0.8B
cleanup candidate. It is not Fleck integration, model admission, packaging,
signing, release evidence, or microphone validation. Every aggregate report
sets `productionIntegrated=false`, `packagedAppVerified=false`, and
`releaseAdmitted=false`. A failed candidate is a valid result and is never
promoted automatically.

## Frozen corpus

`corpus-v1.json` contains 83 immutable cases:

- 36 Qwen ASR-derived baselines: 12 English, 12 Mandarin, and 12 mixed.
- 36 Whisper ASR-derived baselines with the same language split.
- 11 deterministic protected-content stress cases covering names,
  destinations, number words and digits, prices and units, dates and times,
  URLs and paths, commands, commitments and modality, and negation.

The corpus uses only these accepted final retained transcript sources. The
runner rejects any substituted path, source hash, record identity, or baseline
value before invoking the accepted harness:

```text
Qwen:
/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/RawRuns/qwen3-asr-0.6b-int8-20260821-real-5/transcripts.jsonl
SHA-256: ccfc1fcd88e2fbc5fb8462201ea02849e5ebb5099e89ec19e22fb4b93bc788b1

Whisper:
/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/whisper-small-control.YPRRYs/transcripts.jsonl
SHA-256: 8f6c8602f188b4f045b77bdb5e33e23532da51b247272027f85e81d01d279cdf
```

No microphone audio is copied or tracked. Stress cases pin the checked-in
`FoundationModelDictation.swift` hash. The report also records the exact
corpus, qualification files, deterministic-control sources, accepted-harness
provenance, and external source identities.

## Real qualification

Run the fake-only contract suite first. Then create a new empty external
directory and run the qualification with the exact runtime and model paths:

```sh
bash Tools/QwenCleanupBenchmark/Qualification/Tests/run-contract-tests.sh

mkdir -p "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/QwenCleanupQualification-NEW"
bash Tools/QwenCleanupBenchmark/Qualification/run-qwen-cleanup-qualification.sh \
  --real \
  --corpus "$PWD/Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json" \
  --qwen-source "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/RawRuns/qwen3-asr-0.6b-int8-20260821-real-5/transcripts.jsonl" \
  --whisper-source "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/whisper-small-control.YPRRYs/transcripts.jsonl" \
  --python-executable "/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/bin/python3.14" \
  --runtime-site-packages "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Tools/qwen35-cleanup-mlx-0.31.3/lib/python3.14/site-packages" \
  --model-root "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Quarantine/qwen3.5-0.8b-mlx-4bit" \
  --output-root "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/QwenCleanupQualification-NEW"
```

The qualification invokes only the accepted
`Tools/QwenCleanupBenchmark/run-qwen-cleanup-benchmark.sh`. That harness
proves macOS network denial, verifies the exact model/runtime inventories,
uses its private staging and exclusive publication, and performs the strict
response-envelope plus existing `FaithfulCleanupValidator` checks. The
qualification runs one warm all-case process, six fresh cold cases spanning
English/Mandarin/mixed for both engines, and a forced-termination probe. It
reports faithful acceptance and rejection reasons by language/source,
protected violations, unexpected lexical changes, warm generation p50/p95,
cold process-to-result p50/p95, maximum RSS, one-request/no-retry evidence,
and cancellation/no-late-publication state.

The deterministic control is compiled read-only from the checked-in
`FoundationModelDictation.localCleanup` implementation with the existing
validator. It is a comparison control only; it does not modify production
code or select a model.

## External evidence layout

The output root must be new and empty. Accepted-harness raw JSONL and summary
files remain in that root. The qualification adds these exclusively published
files:

```text
qualification-report.json
qualification-provenance.json
qualification-corpus-v1.json
cold-manifest.json
cancellation.json
accepted-run-manifest.json
```

The aggregate report is the qualification result, not an admission decision.
Automatic candidate pass requires zero protected violations, zero unexpected
lexical changes, every case accepted by the strict validator, and no late
publication after forced termination. There is no retry path and no download
path. Production integration, packaged-app verification, and release
admission remain explicitly false.

## Immutable rescore

After a scorer-only correction, use `--rescore` with the prior external
qualification root. It selects the exact warm JSONL through that root's
`accepted-run-manifest.json`, verifies the cold manifest, cancellation record,
and corpus hashes without modifying them, compiles the scorer read-only, and
builds scoring and report data from private file-descriptor-verified
snapshots. The scorer receives a private cold-manifest view whose evidence and
summary paths resolve only to those verified snapshots; the published report
remaps those paths to the original identities while retaining snapshot-derived
hashes and RSS metrics. The runner rechecks the original selected inputs after final report assembly
and immediately before publication, and atomically publishes only a new
`qualification-report.json` and `qualification-provenance.json`. The output
parent and destination are anchored by device/inode identity before scoring
and checked again at publication. Rescore mode launches neither the accepted
harness nor a model:

```sh
bash Tools/QwenCleanupBenchmark/Qualification/run-qwen-cleanup-qualification.sh \
  --rescore \
  --rescore-input-root "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/QwenCleanupQualification-PRIOR" \
  --output-root "/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/QwenCleanupQualification-RESCORE"
```

The rescore receipt records prior qualification attempts, including deadline
instability and unsupported-shell failures; it remains developer-only and
keeps all production, package, and release flags false.

## Contract coverage

The fake-only suite uses a temporary fake model inventory, fake runtime, and
fake response map. It does not import MLX or launch model weights. It covers
corpus schema and source-hash pinning, substituted/older evidence rejection,
protected violations, deterministic-control comparison, warm/cold aggregation,
over-deadline termination and no-late output, output-root replacement races,
rescore parent/destination and immutable-input replacement races, including
distinct-inode swap/restore snapshot consumption for cold evidence, public
identity binding, snapshot-derived RSS/hashes, one request/no retry, and the
no-model-launch boundary.
