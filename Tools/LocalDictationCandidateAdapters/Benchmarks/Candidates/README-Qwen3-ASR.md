# Qwen3-ASR-0.6B native corpus benchmark

This is a developer-only, evidence-only benchmark runner for the already-prepared
Qwen3-ASR-0.6B int8 artifact and the accepted native Sherpa helper. It does not
admit the model, wire it into Fleck, package weights, download anything, or make a
release claim.

The runner requires explicit absolute, canonical, non-symlink paths for the
prepared artifact root, helper executable, public-human manifest/root,
public-human-composite manifest/root, and a new external output root. The output
root must not be inside the repository, an app bundle, `.build`, or `DerivedData`.
Existing output roots are rejected; publication is staged privately and completed
with an exclusive atomic directory rename.

## Run

Build and execute the standalone candidate runner through the network-denying
wrapper:

```sh
FLECK_REPO="$(git rev-parse --show-toplevel)"
FLECK_MODEL_EVAL_DIR="${FLECK_MODEL_EVAL_DIR:-$HOME/Library/Application Support/Fleck/ModelEvaluation}"

sh "$FLECK_REPO/Tools/LocalDictationCandidateAdapters/Benchmarks/Candidates/run-qwen-native-corpus-benchmark.sh" \
  --prepared-root "/absolute/path/to/prepared/qwen3-asr-0.6b-int8" \
  --helper "/absolute/path/to/qwen-native-evaluation-helper" \
  --public-human-manifest "/absolute/path/to/fleurs-public-human.json" \
  --public-human-root "/absolute/path/to/fleurs-public-human" \
  --composite-manifest "/absolute/path/to/fleurs-public-human-composite.json" \
  --composite-root "/absolute/path/to/fleurs-public-human-composite" \
  --output-root "$FLECK_MODEL_EVAL_DIR/Evidence/RawRuns/qwen3-asr-0.6b-int8-YYYYMMDD-HHMMSS"
```

The example paths are placeholders except for the repository path. Replace every
input with an existing canonical absolute path and choose a new output directory.
The wrapper fails closed when `/usr/bin/sandbox-exec` is unavailable. The Swift
benchmark process itself performs an explicit socket-connect probe under that
profile and sets `privacy.enforced=true` only after observing `EPERM` or `EACCES`.
It runs with `PATH=/usr/bin:/bin`, `LC_ALL=C`, an empty environment, and
`deny network*`; there is no caller-supplied token or boolean. A direct normal
invocation outside the wrapper fails closed before publication. Contract fixtures
are explicitly marked unenforced and cannot publish a verified-offline claim.

Use the normalized immutable manifest at
`Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/manifest-v1.json` for
both manifest arguments when the two external prepared roots are the standard
FLEURS subsets. The roots remain separate so public-human and artificial
composite audio are independently contained and hashed.

The runner verifies the checked-in metadata pins, the prepared
`installed-artifact-inventory.json` SHA/size and archive identities, then walks,
stats, hashes, and reconciles the canonical prepared directory with the pinned
inventory. Undeclared descendants, symlinks with changed/escaping targets,
special files, path escapes, duplicates, and aggregate byte mismatches fail before
helper launch. It also verifies the accepted helper build receipt (executable
name, exact size/SHA-256, model, and runtime identities) immediately before the
verified executable is launched. The supplied manifests must match
the checked-in immutable manifest's exact selected case IDs, references, and audio
SHA-256 values. Then exactly 12 `publicHuman` English, 12 `publicHuman` Mandarin,
and 12 `publicHumanComposite` mixed cases are validated for containment, SHA,
size, duration, mono 16 kHz WAV shape, and ordered source spans. Composite cases
are artificially composed evidence and always record `naturalCodeSwitch=false`.

One warm helper loads once and transcribes all 36 cases exactly once in stable
English, Mandarin, mixed order. Five fresh cold helpers run two English, two
Mandarin, and one mixed case. Canonical v2 cases and aggregate latency contain
only the 36 warm cases; `fileDecodeMilliseconds` and `stopToFinalMilliseconds`
are wall request-to-final measurements. Helper-native decoder measurements are
kept separately in `nonCanonicalDiagnostics`. The same extension records each
cold helper's true fresh-process `launchToFinalMilliseconds`, wall
`requestToFinalMilliseconds`, and native decode time; it never derives cold
latency from load plus native decode. After shutdown acknowledgement, cooperative
finish waits only under a fixed deadline, force-terminates an exact hung child,
proves exit, and fails the run. A separate fresh `--probe-blocked-decode`
helper observes the positive blocked-decode marker, sends no `cancel` request
because cancellation is advertised as unsupported, then terminates the exact
process within the fixed deadline and proves there is no late final output. This
is classified as `process-level-forced-termination-not-cooperative`. Reload is
recorded as `notMeasured` only in the noncanonical diagnostics extension, because
this packet does not attempt reload. The shared canonical contract retains only
supported lifecycle outcomes and reports `reloadSucceeded=false` and
`allSucceeded=false`; it never claims a reload succeeded.

Every evidence run keeps these truth flags false:

```text
automatedCandidatePass=false
productionIntegrated=false
packagedAppVerified=false
releaseAdmitted=false
```

## Output

The published directory contains:

- `candidate-benchmark-evidence-v2.json`: canonical v2 candidate evidence with
  model, runtime, artifact/helper receipts, hardware, exact corpus bindings, all
  hypotheses/references/audio hashes, the 36 warm cases, memory, privacy,
  lifecycle, cancellation, and failure reasons. Its `nonCanonicalDiagnostics`
  extension carries the five cold runs and native timing without affecting the
  canonical aggregate. The file is decoded and validated by
  `CandidateBenchmarkEvidence` before publication.
- `model-evaluation-run-input-v1.json`: the evaluator input mapping English,
  Mandarin, and mixed cases for WER/CER/MER scoring.
- `transcripts.jsonl`: one bounded, final-only transcript record per warm case.
- `helper-diagnostics.json`: bounded warm/cold/cancellation process diagnostics.

Score the generated v1 input separately, writing the report into the same already
published run directory:

```sh
swift run --package-path "$FLECK_REPO" fleck-model-eval \
  "/absolute/path/to/run/model-evaluation-run-input-v1.json" \
  "/absolute/path/to/run/model-evaluation-score.json"
```

The score is evaluator evidence, not model admission or app/release verification.

## Contract tests

The contract suite compiles the Swift file standalone and uses only generated fake
WAVs, manifests, metadata, and a fake JSONL helper. It covers parser strictness,
output flooding, request ordering, identity-before-helper-launch, helper build
receipt rejection, manifest/audio hash and count/language/composite validation,
36-case ordering, five cold launches, forced cancellation/no late output,
canonical repository `CandidateBenchmarkEvidence` decoding, prepared-tree
tamper/undeclared/symlink/aggregate checks, bounded shutdown after a fake helper
hang, output file/directory/symlink races, exclusive publication, in-process
denied-network attestation and unattested/caller-token rejection, and no retry
path:

```sh
contract_tmp="$(mktemp -d "$HOME/.fleck-qwen-native-contract.XXXXXX")"
contract_tmp="$(cd "$contract_tmp" && pwd -P)"
chmod 700 "$contract_tmp"
trap 'rm -rf -- "$contract_tmp"' EXIT

TMPDIR="$contract_tmp" \
  sh "$FLECK_REPO/Tools/LocalDictationCandidateAdapters/Benchmarks/Tests/run-qwen-native-corpus-benchmark-contract-tests.sh" \
    --preflight-only
TMPDIR="$contract_tmp" \
  sh "$FLECK_REPO/Tools/LocalDictationCandidateAdapters/Benchmarks/Tests/run-qwen-native-corpus-benchmark-contract-tests.sh"
```

The contract suite requires `TMPDIR` to be an existing canonical external
directory with no symlinked ancestor. Its `--preflight-only` mode validates that
root and exits before compiling Swift. The common `/tmp` alias is therefore
rejected before compilation; use a canonical per-run root such as the mode-700
directory above instead.

No real model is used by the contract suite. No app integration, installer,
packaging, streaming/partial claim, cleanup, download, or GitHub operation is part
of this candidate.
