# Whisper small control corpus benchmark

This is a developer-only control benchmark. It does not participate in Fleck
admission, app wiring, packaging, or release decisions.

The runner uses the already-present, pinned artifacts only:

- `ggml-small.bin`, ggml ftype `1`, mostly-F16/float16; it is not Q8/int8.
- `whisper-cli` from whisper.cpp `v1.9.2`, the clean source commit pinned in
  `whisper-small-control.json`, arm64 static Metal build.
- The checked-in FLEURS manifest plus the two already-prepared, external audio
  roots. No download, model copy, source checkout, or rebuild is performed.

## Run

Run from the Fleck checkout with an absolute, empty evidence directory outside
the repository and outside build/package/app outputs:

```sh
repo_root="$(pwd -P)"
evidence_root="/Users/harryjin/Library/Application Support/Fleck/ModelEvaluation/Evidence/whisper-small-control-$(date +%Y%m%d-%H%M%S)"

Tools/LocalDictationCandidateAdapters/Benchmarks/Candidates/run-whisper-small-corpus-benchmark.sh \
  --control Tools/LocalDictationCandidateAdapters/Benchmarks/Candidates/whisper-small-control.json \
  --repo-root "$repo_root" \
  --output-root "$evidence_root"
```

The runner refuses non-canonical or symlinked inputs, mismatched hashes or
bytes, a dirty/mismatched whisper.cpp source checkout, unsafe CMake flags, an
existing output target, and an unavailable network sandbox. It launches the
CLI through `/usr/bin/sandbox-exec` with `(deny network*)`, `PATH=/usr/bin:/bin`,
`LC_ALL=C`, and proxy variables stripped.

The warm measurement is one CLI process with all 36 audio files and distinct
JSON output bases. The model therefore loads once. Each recorded warm interval
is the interval between observed valid JSON file completions in input order;
the first interval is also recorded from process start. This is not native
decode time, first-partial time, or stop-to-final time. Whisper CLI output is
batch-final only, and the benchmark makes no streaming or partial-result
claim.

Five additional fresh one-file processes measure cold end-to-end time from
process start through observed valid JSON completion: `en_us-01`, `en_us-02`,
`cmn_hans_cn-01`, `cmn_hans_cn-02`, and `mixed-01`. Upstream
`whisper_print_timings` load/total diagnostics are retained separately when
present; they do not replace the observed end-to-end labels.

Resident size and physical footprint are sampled from each exact child PID.
Stdout, stderr, and JSON parsing are bounded. A separate fresh `mixed-01`
process is force-cancelled only after the exact `main: processing '<path>'`
diagnostic is observed. The result is `forced` only when SIGKILL, signal exit,
and no late output are all proven. A marker race is recorded as `inconclusive`.
Cancellation is never labeled cooperative.

## Published files

The external output root receives exactly these four files, each published by
no-overwrite atomic hard-linking from a temporary file; publication never
retries or replaces an existing target:

- `candidate-benchmark-evidence-v2.json`: 36 warm transcript cases, accuracy
  (WER/CER/MER), warm/cold timing labels, memory, lifecycle, privacy, and all
  admission/integration/package/release flags false.
- `model-evaluation-run-input-v1.json`: the 36 warm transcript inputs for the
  existing `fleck-model-eval` scorer.
- `transcripts.jsonl`: bounded per-case raw/final CLI JSON-derived transcript
  records and cold comparisons for the five selected cases.
- `diagnostics.json`: bounded process diagnostics, identity receipts, offline
  enforcement, output order, lifecycle, and cancellation truth.

Run the existing evaluator against the published input without changing the
benchmark output root:

```sh
swift run --package-path "$repo_root" --disable-automatic-resolution fleck-model-eval \
  "$evidence_root/model-evaluation-run-input-v1.json" \
  "/private/tmp/whisper-small-control-model-evaluation-report-v1.json"
```

The evaluator report is a separate diagnostic and is not admission evidence.

## Contract checks

The contract script compiles the runner and runs `--self-test`. Its fake-only
checks cover identity gates, ggml ftype/quantization truth, 36-case one-process
warm semantics, five cold shape, timing labels, strict output parsing and
ordering, bounded flood/duplicate-key rejection, forced-cancellation truth,
offline enforcement, and publication race/no-retry behavior. It never launches
the external model.
