# Local dictation runtime admission

This document describes the checked-in admission foundation for local
dictation candidates. It does not select a model, approve a model, or add a
product local-AI runtime. Runtime-specific ASR and cleanup adapters remain
unimplemented.

## Validate the immutable manifest

The manifest is the versioned, strict ten-case contract at
`Tests/Fixtures/local-dictation-admission-v1.json`. Its schema is checked in
beside it. Validation rejects unknown fields, unsupported versions, duplicate
case IDs, non-local audio paths, duplicate context phrases, invalid hashes,
and any case list other than the exact immutable role order.

```bash
swift run --package-path Tools/LocalDictationCandidateAdapters \
  local-dictation-candidate validate-admission \
  --manifest "$PWD/Tests/Fixtures/local-dictation-admission-v1.json" \
  --schema "$PWD/Tests/Fixtures/local-dictation-admission-v1.schema.json"
```

The checked-in manifest is intentionally `synthetic-only`: its audio paths are
placeholders and no real audio is admitted. It therefore prints and records
`refused-no-admitted-real-audio`; validation is not release evidence.

The ten immutable roles are:

1. English technical prose.
2. English developer command with identifiers and a path.
3. Mandarin prose with numbers and units.
4. Mandarin technical terms.
5. English-to-Mandarin intra-utterance switch.
6. Mandarin-to-English intra-utterance switch.
7. Personal dictionary aliases and canonical forms.
8. Silence/noise hallucination.
9. Cancellation during active decode.
10. Repeated load, inference, unload, and reload.

Real audio can only change the manifest through a reviewed revision that
records exact provenance and a consent record, supplies an exact SHA-256 for
each admitted asset, and changes the admission status to `admitted`. Until
then, the runner must continue to refuse release-evidence status.

## Run a candidate

The wrapper accepts paths as arguments and resolves them before invoking the
standalone CLI. The adapter must be an absolute, regular executable after
resolution. The model root must be an absolute directory with no symlink
escaping that root. The report path must not already exist.

```bash
Scripts/run-local-dictation-candidate.sh \
  --manifest "$PWD/Tests/Fixtures/local-dictation-admission-v1.json" \
  --adapter "/absolute/path/to/candidate-adapter" \
  --model-root "/absolute/path/to/model-root" \
  --output "/absolute/path/to/new-admission-report.json"
```

The process boundary is offline and fail-closed:

- adapter requests and events are deterministic JSON-lines, one object per
  line, with strict version, key, request-ID, and event-order checks;
- only an explicit executable path runs, with an environment allowlist and no
  inherited secret-bearing environment;
- stdout is protocol-only and bounded; stderr is retained in a bounded 1 MiB
  ring with fixture/model paths redacted;
- cancellation and shutdown use bounded cooperative timeouts followed by
  exact-child forced termination when required;
- model-root symlink escapes, download URLs, arbitrary shell commands,
  auto-downloads, and pre-existing output paths are rejected;
- reports contain case status and raw measurement artifacts, but never
  transcript content.

The report records runtime/model revisions, executable and model-library
hashes, command line, operating-system and hardware identity, network
isolation method, start/end timestamps, child exit status, and the ten case
results. A synthetic fixture run is lifecycle evidence only; it cannot claim
ASR quality, model selection, or product readiness.

## Run the isolated gate

```bash
Scripts/test-local-dictation-candidate-adapters.sh
```

This runs the standalone package tests, validates the checked-in manifest,
checks an invalid duplicate-case manifest fails closed, executes the fixture
adapter through the full ten-case lifecycle, checks deterministic report
metadata and synthetic-only release refusal, rejects a pre-existing output,
and checks that the fixture adapter is not left running.
