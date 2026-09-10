# Gemma cleanup benchmark

This is a provisional, English-only, Apple-Silicon-only candidate record for
the first native MLX-Swift cleanup experiment. It is unintegrated, unadmitted,
unbundled, and not a release or distribution approval.

One exploratory HTTP header probe followed a redirect and transiently transferred model response bytes into a closed pipe. No model file/artifact was written, retained, persisted, installed, cached, integrated, or used for inference; no runtime dependency was acquired.

## Candidate identity

The exact model candidate is
`mlx-community/gemma-3-1b-it-qat-4bit` at immutable revision
`15fed4eafb456c6fcb2a1165f19ac609670ed14b`. MLX Swift LM 3.31.4 is pinned to
commit `bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57`; its tag declares MLX Swift
with `.upToNextMinor(from: "0.31.4")`, resolved here as `>=0.31.4,<0.32.0`.
The direct registry path is `LLMRegistry.gemma3_1B_qat_4bit`.

The upstream identity is `google/gemma-3-1b-it`. Gemma is governed by the
[Gemma Terms of Use](https://ai.google.dev/gemma/terms). Local use constitutes
acceptance of those terms. No distribution approval is granted: any later
redistribution requires a copy of the Gemma Terms of Use Agreement, enforceable
use restrictions, and the required Notice file. The metadata file records the
full immutable artifact inventory and the available Git, LFS, and Xet content
identifiers; it does not contain model content.

## Frozen qualification corpus

`Corpus/english-qualification-v1.json` contains exactly 38 English cases:

- 12 Qwen-derived and 12 Whisper-derived public-human ASR baselines copied
  from `Tools/QwenCleanupBenchmark/Qualification/corpus-v1.json`.
- 9 English protected-stress cases covering names/destinations, numbers,
  prices/units, dates/times, URLs/paths, commands/code,
  recipients/destinations, commitment/modality, and negation.
- 5 synthetic utility cases covering accepted filler removal, immediate
  duplicate removal, explicit correction, punctuation/case, and short-list
  formatting.

Every copied source case retains its source evidence, protected expectations,
raw baseline, and canonical source-case SHA-256. The contract rejects changed
source bytes, changed source fields, Mandarin or mixed language labels, Han
text, and substituted or mutable revisions. Synthetic cases are explicitly
labelled and do not replace public-human evidence. The contract recursively scans every string in the corpus JSON, including nested objects, source evidence, unknown fields, and object keys, and rejects CJK unified or
compatibility characters in U+3400-U+4DBF, U+4E00-U+9FFF, U+F900-U+FAFF, or
U+20000-U+2FA1F.

The current Gemma corpus SHA-256 is
`375a00766c439e53c0844164a4b18c5f5d8db1b89efffaae60799bd2a04ccab5`.
Its current sanitized Qwen source corpus SHA-256 is
`fca16ee1c04b77fa7b17489ea3d071eff3c0d049c78ae90e1977ca3421f10120`.
The earlier pre-sanitization identity
`6d8a639d6b67fde23a198398e13176ccc50af03acdfaf504a68dfaa20c9a17fb`
is preserved only as `historicalOriginalSHA256`; it is not the current corpus
hash. Historical source evidence uses `historical-external-evidence:`
locators rather than machine-specific filesystem paths.

## Qualification boundary

Run the offline metadata/corpus contract before any future helper or model
work:

```sh
bash Tools/GemmaCleanupBenchmark/Tests/run-metadata-corpus-contract-tests.sh
jq -e . Tools/GemmaCleanupBenchmark/Metadata/gemma-3-1b-it-qat-4bit.json
jq -e . Tools/GemmaCleanupBenchmark/Corpus/english-qualification-v1.json
```

The next packet may build a helper and a local test app, but this packet does
not add SwiftPM dependencies, retain or install model content, wire Fleck, or
admit a model.
Any future candidate qualification remains behind `FaithfulCleanupValidator`
and must establish zero semantic/protected/lexical violations before a model
can be considered further.
