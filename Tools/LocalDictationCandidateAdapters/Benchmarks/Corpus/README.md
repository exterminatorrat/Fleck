# Local dictation corpus contract v1

This directory contains metadata and tooling only. Audio is acquired into an
explicit external destination and is never checked into Git. The immutable
manifest carries the exact per-case audio SHA-256, duration, byte count,
reference, evidence class, and `naturalCodeSwitch` value from the accepted
prepared corpus evidence.

Each `publicHumanComposite` case also carries its two ordered `codeSwitchSpans`
with the exact source language, source case ID, sample boundaries, and
reference. These spans document the artificial construction; non-composite
cases omit the field and no span is natural code-switch evidence.

The public source is `google/fleurs` at revision
`a3c817cbf7c08863e0c472861c7c39e27ce7f38e`, licensed as CC-BY-4.0. The
English validation parquet is pinned to 236549523 bytes and SHA-256
`7c3eebdff31e1c510b78e51319e5b9779429b87c9895f2e5f3005bfe68854c65`; the
Mandarin validation parquet is pinned to 287985961 bytes and SHA-256
`18698f80879a221f68318a4ccb8752b74c2f5bf521af0e0011b07e4670ea62ad`.

## Licensing and attribution

FLEURS-derived material is not covered by Fleck's MPL-2.0 license. The pinned
[dataset card](https://huggingface.co/datasets/google/fleurs/blob/a3c817cbf7c08863e0c472861c7c39e27ce7f38e/README.md)
declares [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Fleck-authored schemas, metadata fields, synthetic cases, and tooling remain
MPL-covered when they share a file with FLEURS-derived portions.

Fleck selected 12 English and 12 Mandarin validation records, retained their
reference text and metadata, and created 12 artificial bilingual composites by
concatenating selected recordings with fixed silence gaps. It also generated
ASR and cleanup outputs for evaluation. The composites are explicitly not
natural code-switch evidence. Source audio is acquired separately and is not
tracked in this repository.

Please cite the source dataset as supplied by the pinned dataset card:

> Alexis Conneau, Min Ma, Simran Khanuja, Yu Zhang, Vera Axelrod, Siddharth
> Dalmia, Jason Riesa, Clara Rivera, and Ankur Bapna. “FLEURS: Few-shot
> Learning Evaluation of Universal Representations of Speech.” arXiv preprint
> arXiv:2205.12446 (2022). <https://arxiv.org/abs/2205.12446>

The manifest contains 12 English and 12 Mandarin `publicHuman` cases, 12
artificial `publicHumanComposite` mixed cases, and five deterministic
`synthetic` nonspeech cases. `publicHumanComposite` is concatenated public
speech with a fixed silence gap; it is not evidence of natural code-switching.
All current cases set `naturalCodeSwitch` to `false`. Operator live speech is
not automated corpus evidence and remains a later, separately captured manual
evidence class.

## Acquire the pinned source

The acquisition script is never invoked automatically and refuses repository
destinations, symlinks, unexpected files, and unverified output overwrites. It
reverifies an existing exact final by byte count and SHA-256 before reusing it,
so a retry can keep a verified first final while resuming the other `.partial`.
Use an empty absolute directory outside the repository:

```sh
mkdir /absolute/path/to/corpus
Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/acquire-corpus.sh \
  /absolute/path/to/corpus
```

`--dry-run` validates the destination and prints the exact-revision HTTPS
plans without contacting the network. Downloads use `.partial` files, verify
the pinned byte count and SHA-256, and publish each completed file
exclusively with the macOS `link(2)` wrapper, so a target that appears during
publication is preserved and causes failure rather than becoming a directory
link.

## Generate deterministic nonspeech

The generator requires an existing empty absolute directory and emits exactly
five 16 kHz mono IEEE Float32 WAV files:

| File | Construction | Duration |
| --- | --- | --- |
| `silence-5s.wav` | exact digital silence | 5 s |
| `white-noise-low-5s.wav` | seeded white noise, amplitude 0.01 | 5 s |
| `white-noise-medium-5s.wav` | seeded white noise, amplitude 0.05 | 5 s |
| `impulse-train-5s.wav` | amplitude 0.25 impulse every 500 ms | 5 s |
| `alternating-silence-noise-10s.wav` | repeated 2 s silence, 3 s seeded noise at amplitude 0.02 | 10 s |

The stream uses Python-compatible `random.Random` semantics with fixed seed
`0xF1EC2026`. Compile and run it manually; the module-cache path is writable
so the command also works on a managed developer machine:

```sh
mkdir /absolute/path/to/nonspeech
mkdir -p /private/tmp/fleck-corpus-module-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/fleck-corpus-module-cache \
  swiftc -O -parse-as-library \
  Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/generate-nonspeech.swift \
  -o /private/tmp/generate-nonspeech
/private/tmp/generate-nonspeech /absolute/path/to/nonspeech
```

## Offline contract checks

The contract test does not download audio or models. It validates the closed
JSON Schema, exact source pins, evidence counts/classes, exact synthetic
hashes, WAV shape, repeated-generation determinism, tracked-artifact absence,
and acquisition syntax/dry-run safety:

```sh
bash Tools/LocalDictationCandidateAdapters/Benchmarks/Tests/run-corpus-contract-tests.sh
```
