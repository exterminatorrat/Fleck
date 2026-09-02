# Whisper small preflight

This is a no-download preflight packet for the intended Whisper small control.
The checked-in `WhisperASRMetadata.candidate` keeps compiled runtime identity
unadmitted, so native/runtime admission, model-quality admission, and overall
candidate admission are all false.

## Self-test

From the repository root, run the exact local harness self-test:

```sh
Tools/LocalDictationCandidateAdapters/Spikes/WhisperASR/run-preflight.sh --self-test
```

The self-test covers exclusive publication against a regular file, directory,
and symlink-to-directory race; invalid backend rejection; caller preflight
substitution rejection; current compiled-runtime failure with no output; retry
of the same output path; and direct execution of the checked-in preflight
binary.

## Current preflight

From the repository root, this is the exact normal invocation with prospective
absolute local paths:

```sh
Tools/LocalDictationCandidateAdapters/Spikes/WhisperASR/run-preflight.sh \
  --backend metal \
  --runtime-path /tmp/prospective-whisper-runtime \
  --model-path /tmp/prospective-whisper-model \
  --helper-path /tmp/prospective-whisper-helper \
  --output /tmp/prospective-whisper-preflight.json
```

The current expected result is exit `2` with:

```text
preflight-failure:artifact-identity-unadmitted/runtime-identity-unavailable
preflight-exit=2
```

The failure is fail-closed: the output file is not published, its
destination-directory temp is removed, and the same command can be retried
without clearing a stale artifact. The runtime, model, and helper paths are
prospective only; the immutable compiled-runtime identity check occurs before
resolving or opening any of them.

## Harness and evidence boundary

The harness builds only the checked-in Swift `whisper-asr-preflight` product
with SwiftPM dependency resolution disabled. It does not accept a caller
substitution for that executable. It does not download, build, or load
`whisper.cpp` or the model; transcribe audio; benchmark; install; or integrate
Fleck. It performs no native inference.

The output temp is created in the destination directory and is published only
after a future successful, reviewed admission using exact `/bin/link` exclusive
publication. The current failure output is preflight control evidence only,
not model, transcription, benchmark, or readiness evidence. No evidence is
published until that future admission succeeds.

## Capability boundary

The intended future control is `batch-final-only`: it may produce one final
result for a completed batch, but it does not claim true streaming or rolling
window partials. The planned evaluation cases are English (`en`), Chinese
(`zh`), and mixed (`mixed`).

The current preflight emits no ready, partial, or final events and admits no
cancellation, context, or native execution. Runtime identity, native runtime
admission, model quality, and overall Whisper candidate admission remain
unadmitted.
