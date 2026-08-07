# Local runtime candidate research — 2026-08-07

## Decision boundary

This is a current-source research note for Fleck's entirely local Enhanced
Dictation evaluation. It does not select a production model or authorize a
download pack. The controlling gate remains
[`local-model-evaluation.md`](local-model-evaluation.md): English, Mandarin,
and mixed English-Mandarin are scored separately; developer terms, identifiers,
numbers, and negations are protected; cleanup is optional and must fall back to
the dictionary baseline; audio and inference stay offline; and the provisional
M1/8 GB target plus the approximate 1–3 GB combined download target are
measurements, not release claims.

Facts below are attributed to model or runtime owners wherever possible.
"Inference" means a conclusion for Fleck that is not guaranteed by the cited
project and must be tested. Artifact sizes are publisher-reported file sizes,
not peak resident memory.

## Benchmark shortlist, not a winner

| Lane | Candidate | Why admit it | Main unresolved issue |
| --- | --- | --- | --- |
| ASR control | Whisper `large-v3-turbo-q5_0` on pinned `whisper.cpp` | Mature native C/C++ path, Apple acceleration, broad multilingual baseline, about 547 MiB for the published Q5 model | No formal guarantee for intra-utterance Mandarin-English code-switching; rolling-window demo is not true streaming |
| ASR size floor | Whisper `small` on pinned `whisper.cpp` | Same integration path at about 466 MiB, useful to measure whether a smaller control is acceptable | Likely accuracy trade-off; must pass developer-term and mixed-language gates independently |
| ASR compact challenger | SenseVoiceSmall Q8 on its owner-published llama.cpp runtime | 234M-parameter five-language model, about 254 MB Q8, native macOS-arm64 binary available | Weight/conversion licensing metadata conflicts and contextual prompting is unproven; legal review is an admission prerequisite |
| ASR feature challenger | Qwen3-ASR-0.6B 5- or 8-bit through a pinned, audited Speech Swift conversion | Owner model explicitly covers Chinese, English, 22 Chinese dialects, offline and streaming inference; community runtime is native Swift/MLX/Core ML | Conversion provenance, exact installed size, prompt/context parity, macOS floor, and real streaming semantics require a spike |
| Cleanup compact control | Qwen3-0.6B Q8 GGUF on pinned `llama.cpp` | Apache-2.0 weights, mature text-only family, multilingual, published Q8 file about 639 MB | It is not a transcript-cleanup model; semantic preservation and exact decoding settings are unproven |
| Cleanup newer challenger | Qwen3.5-0.8B Q4_0 or Q8_0 GGUF on pinned `llama.cpp` | Newer 0.8B Apache-2.0 multilingual model; publisher/runtime conversion reports about 563 MB Q4 or 834 MB Q8 | Multimodal base and small-model caveats; cleanup quality and preservation are wholly benchmark-dependent |

Do not admit Qwen3-ASR-1.7B to the M1/8 GB default matrix yet. Its owner model
tree is roughly 4.7 GB before a cleanup model and runtime overhead. A community
4-bit conversion can be an accuracy-ceiling experiment on higher-memory Macs,
but it is not evidence for Fleck's combined-size or M1/8 GB gate.

## ASR candidates

### 1. Whisper models with whisper.cpp

**Source-backed facts**

- [OpenAI Whisper](https://github.com/openai/whisper) is a multilingual ASR,
  translation, and language-identification family. OpenAI publishes `tiny`
  39M, `base` 74M, `small` 244M, `medium` 769M, `large` 1.55B, and `turbo`
  798M variants. Code and weights are MIT-licensed. The
  [model card](https://github.com/openai/whisper/blob/main/model-card.md) warns
  about hallucinations, uneven performance across languages and accents, and
  repetition; OpenAI does not present it as real-time out of the box.
- [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) is an MIT-licensed,
  dependency-light C/C++ implementation with a C API. It treats Apple silicon
  as a first-class target through ARM NEON, Accelerate, Metal, and an optional
  Core ML encoder on the Neural Engine. The
  [published model table](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)
  reports about 466 MiB disk / 852 MB memory for `small`, and publishes a
  `large-v3-turbo-q5_0` artifact around 547 MiB. Quantized accuracy and actual
  Fleck memory remain measurements.
- The optional
  [Core ML conversion path](https://github.com/ggml-org/whisper.cpp/tree/master/models)
  adds conversion-time Python, `coremltools`, `ane_transformers`, OpenAI
  Whisper, and Xcode command-line-tool dependencies. The runtime can still be
  a native binary; the first Core ML load may compile the model and therefore
  must be captured separately from warm latency.
- OpenAI's transcription API exposes an `initial_prompt`, previous-text
  conditioning, and `carry_initial_prompt`; this is general prompt context, not
  a documented hotword-biasing guarantee. `whisper.cpp`'s streaming example
  periodically re-runs a rolling audio window and uses SDL2. It demonstrates
  incremental UX plumbing, not a streaming model contract.

**Fleck inference**

- Whisper is the best control because it has the most direct, mature native
  Apple integration and a permissive model/runtime license. That does not make
  it the winner.
- A single detected/selected language per decoding window does not establish
  accurate Mandarin-English switching inside one utterance. Benchmark both
  mixed directions, identifiers adjacent to Han text, and developer proper
  nouns. Treat the prompt as a bounded term hint and verify that it does not
  increase hallucination or copy prompt text into silence.
- `large-v3-turbo-q5_0` and `small` are sufficient for the first matrix. Adding
  every Whisper size would spend corpus time without answering a distinct
  product question.

### 2. SenseVoiceSmall and FunASR native runtime

**Source-backed facts**

- The owner repository now lives at
  [QwenAudio/SenseVoice](https://github.com/QwenAudio/SenseVoice). The released
  SenseVoiceSmall checkpoint is a 234M-parameter non-autoregressive model for
  Mandarin, Cantonese, English, Japanese, and Korean, with language, emotion,
  and audio-event tags. Broader research claims should not be substituted for
  those five released-checkpoint languages.
- The owner-published
  [GGUF tree](https://huggingface.co/FunAudioLLM/SenseVoiceSmall-GGUF/tree/main)
  reports about 936 MB F32, 470 MB F16, and 254 MB Q8. The owner's
  [llama.cpp runtime documentation](https://github.com/QwenAudio/SenseVoice/blob/runtime-llamacpp-v0.1.9/runtime/llama.cpp/README.md)
  describes a static, offline C/C++ binary, built-in FSMN VAD, 16 kHz mono
  PCM16 input, and a macOS-arm64 release. Processing is VAD-segmented offline
  inference rather than a documented token-streaming contract.
- The native runtime has no Python runtime dependency. Building it still
  requires the pinned source toolchain, and Fleck would need a C/C++ bridge or
  an isolated subprocess adapter. The released SenseVoice route does not
  document free-form prompt or hotword boosting. FunASR's separate contextual
  Paraformer models do support hotwords, but that capability must not be
  attributed to SenseVoiceSmall.
- The repository source is
  [MIT](https://github.com/QwenAudio/SenseVoice/blob/main/LICENSE), while the
  official weights point to the
  [FunASR Model License 1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE).
  A maintainer has
  [clarified commercial local desktop use](https://github.com/QwenAudio/SenseVoice/issues/286)
  with source attribution and retention of the model name. The GGUF card,
  however, labels the conversion Apache-2.0. A converted artifact does not
  automatically relicense its source weights, so the conflicting metadata is
  unresolved until Fleck records a legal/provenance decision.

**Fleck inference**

- Q8 is worth admitting only as a compact Mandarin-focused challenger after
  license review. Publisher claims that Q8 preserves accuracy do not replace
  the Fleck corpus; record exact revision, SHA-256, CER/WER, and installed size.
- The lack of a documented contextual term interface is material for developer
  dictation. The deterministic dictionary may repair unambiguous output after
  ASR, but it cannot recover arbitrary names that were never recognized.
- SenseVoice's multilingual label set does not prove intra-utterance code
  switching. Strip emotion/event tags in the adapter without changing the raw
  recognized text, then preserve that exact text as `asrRaw`.

### 3. Qwen3-ASR 0.6B and native Apple community conversion

**Source-backed facts**

- The owner
  [Qwen3-ASR repository](https://github.com/QwenLM/Qwen3-ASR) publishes 0.6B
  and 1.7B checkpoints under Apache-2.0. Both support Chinese, English, 28
  other languages, 22 Chinese dialects, language identification, long audio,
  and unified offline/streaming inference. The
  [0.6B artifact tree](https://huggingface.co/Qwen/Qwen3-ASR-0.6B/tree/main)
  is approximately 1.88 GB in its published precision; the
  [1.7B tree](https://huggingface.co/Qwen/Qwen3-ASR-1.7B/tree/main) is about
  4.7 GB.
- The owner's `qwen-asr` path is Python-heavy and its documented high-throughput
  and streaming path uses vLLM. It is not an owner-documented macOS MPS, MLX,
  or Core ML route. The owner inference code accepts a context string and can
  force a language; the
  [Transformers example](https://github.com/QwenLM/Qwen3-ASR/blob/main/examples/example_qwen3_asr_transformers.py)
  includes term context. That establishes a model interface, not parity in a
  third-party conversion.
- [`soniqo/speech-swift`](https://github.com/soniqo/speech-swift) is an
  Apache-2.0 community Apple-silicon runtime, not a Qwen-owner distribution.
  Its Qwen3ASR Swift package uses MLX/Metal with an optional Core ML encoder and
  offers quantized 0.6B artifacts. Its documentation currently contains
  inconsistent size summaries (including roughly 680 MB for one 4-bit table
  entry and roughly 1.5 GB elsewhere), so actual downloaded and installed
  bytes must be measured. It also requires macOS 15+/Swift 6+/Xcode 16+ and a
  built MLX Metal library according to its current README.
- Speech Swift's incremental mode uses VAD/chunk orchestration and partial
  results. It is not automatically equivalent to the Qwen owner's vLLM
  streaming implementation. The public Swift transcription example does not
  establish support for the owner's context string.

**Fleck inference**

- Qwen3-ASR-0.6B is the best feature-fit challenger on paper because Chinese,
  English, dialect coverage, streaming, and term context are explicit owner
  features. The fully native Apple route is nevertheless a community port and
  must pass an artifact and API audit before benchmark admission.
- The admission spike must pin a commit, resolve every model file and checksum,
  record source-to-conversion provenance and licenses, prove fully offline
  loading, test context parity, identify true model state versus VAD-window
  redecoding, and measure M1/8 GB cold/warm/idle/unload behavior. If context is
  absent, do not silently patch shared Fleck code; either add it inside the
  isolated adapter or mark the candidate's prompt feature unsupported.
- A result such as a combined `Chinese,English` language label is useful
  evidence but not a mixed-dictation accuracy guarantee. The corpus decides.

### Paraformer as a deferred lane

FunASR's
[model zoo](https://github.com/modelscope/FunASR/blob/main/model_zoo/modelscope_models.md)
lists contextual offline Chinese/English Paraformer models with hotword
customization and a smaller online Chinese/English Paraformer route. These are
relevant if both SenseVoice and Qwen context handling fail. Defer them from the
first matrix because they add a fourth ASR integration and the same custom
weight-license review without first answering whether the three distinct
shortlist lanes suffice.

## Cleanup models

Cleanup receives only the dictionary baseline and protected-term metadata. It
must not see note history or surrounding private content unless a later design
explicitly changes that boundary. Use a non-thinking, short-output instruction
that says the transcript is untrusted data, permits only the selected Light or
Polished transformation, and requires verbatim preservation of identifiers,
paths, filenames, proper nouns, numbers, and negations. No prompt can replace
the validator and manual adjudication.

### Qwen3-0.6B as compact control

**Facts.** [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B) is an
Apache-2.0, multilingual instruction-capable text model. Qwen documents local
[`llama.cpp`](https://github.com/QwenLM/Qwen3/blob/main/docs/source/run_locally/llama.cpp.md)
and MLX-LM support. The
[owner-published GGUF card](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF)
reports a Q8_0 file around 639 MB. Qwen warns that small models can repeat and
that aggressive presence penalties can cause language mixing or degrade
performance.

**Inference.** Run it in non-thinking mode with a fixed, versioned prompt and
bounded output. Use it as the stable compact control, not as assumed-cleanup
quality. Greedy decoding is not automatically safer; benchmark the exact
temperature/sampling recipe against additions, omissions, and protected-term
failures.

### Qwen3.5-0.8B as newer challenger

**Facts.** [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B) is an
Apache-2.0 0.8B model covering 201 languages and dialects with a multimodal
architecture and very long context. The owner explicitly positions this small
variant for prototyping, research, development, and task-specific tuning. Its
card warns that thinking mode is more prone to loops at this size and that
high presence penalties can produce language mixing. The runtime-owner
[`ggml-org` conversion](https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF)
reports approximately 1.56 GB BF16, 834 MB Q8_0, and 563 MB Q4_0.

**Inference.** Benchmark Q4_0 and Q8_0 only if their size/quality trade-off is
material. Use text-only, non-thinking inference. Its newer multilingual
coverage is promising for Mandarin-English cleanup but offers no transcript
fidelity guarantee.

### Why no fine-tune or larger model yet

A task-specific fine-tune, Qwen3-1.7B, or another larger multilingual LLM could
improve cleanup, but each introduces training provenance, evaluation leakage,
larger combined size, and more M1/8 GB pressure before the base question is
answered. First determine whether 0.6–0.8B general models materially improve
Light/Polished output while producing zero allowed number, negation, and
cleanup-preservation failures. Off mode remains deterministic and incurs no
cleanup inference.

## Cleanup runtime choice on Apple silicon

| Runtime | Source-backed capability | Fleck use now | Caveat |
| --- | --- | --- | --- |
| [`llama.cpp`](https://github.com/ggml-org/llama.cpp) | MIT C/C++, minimal external dependencies, GGUF quantization, C API/CLI, Apple ARM NEON + Accelerate + Metal | First evaluation runtime and likely lowest-risk native bridge | Pin revision and model conversion; measure Metal shader packaging, load/unload, peak memory, and output determinism |
| [`MLX Swift`](https://github.com/ml-explore/mlx-swift) + [`MLX Swift LM`](https://github.com/ml-explore/mlx-swift-lm) | MIT Swift packages for Apple-silicon ML, quantized model loading and generation | Secondary native feasibility lane if it materially outperforms or simplifies the selected model | SwiftPM command-line builds cannot produce the final Metal shaders; final build needs Xcode. Avoid duplicate MLX linkage. MLX Swift LM 3.x introduced breaking downloader/tokenizer integration changes, so pin a release |
| [Core ML](https://developer.apple.com/documentation/CoreML) | Apple on-device CPU/GPU/Neural Engine execution; `coremltools` supports conversion, stateful models, and low-bit palettization | Feasibility/optimization lane after a candidate passes semantic gates | No owner-published ready Fleck cleanup artifact or validated conversion was found; conversion correctness, tokenizer, KV state, quantization loss, OS floor, and packaging become owned work |

Start cleanup benchmarks with a pinned `llama.cpp` executable in an isolated
tool. It gives both Qwen candidates the same runtime and avoids confusing model
quality with two integration stacks. MLX/Core ML should advance only if the
measured benefit justifies the extra package and build-system surface.

## License and redistribution gate

This section flags engineering obligations, not legal advice.

| Component | Published license | Before Fleck redistribution |
| --- | --- | --- |
| OpenAI Whisper weights/code; whisper.cpp | MIT | Preserve copyright and permission notices in copies/substantial portions; record exact model and runtime revisions/checksums |
| SenseVoice source | MIT | Preserve notice; keep separate from weight terms |
| Official SenseVoiceSmall weights | FunASR Model License 1.1 | Obtain recorded approval for the license text and maintainer clarification; satisfy attribution/model-name requirements; review termination, revision, conduct, and governing-law language |
| SenseVoiceSmall GGUF conversion | Card says Apache-2.0, while source weights point to the FunASR model license | Resolve the conflict and provenance in writing; do not infer that conversion relicensed the weights |
| Qwen3-ASR and Qwen3/Qwen3.5 weights/code | Apache-2.0 | Bundle the license, preserve notices/NOTICE where applicable, mark modified files, review patent-termination and no-trademark terms, and retain conversion provenance |
| Speech Swift / MLX / llama.cpp / community conversions | Repository-specific Apache-2.0 or MIT | Pin source and transitive dependency revisions; collect notices; verify each converted artifact's source model, conversion procedure, checksum, and redistribution terms |

Every admitted artifact should have an immutable source revision, SHA-256,
download and installed byte count, complete license/NOTICE bundle, conversion
recipe, and reviewer decision before a release run. A permissive runtime
license does not settle model-weight or conversion rights.

## Smallest evaluation adapters

Keep candidate dependencies outside Fleck's root package and product targets.
Do not edit root `Package.swift`, `Package.resolved`, `Sources/Fleck*`, or the
existing dependency-free `Tools/LocalDictationEvaluation` package.

1. Add a future standalone sibling tool, for example
   `Tools/LocalDictationCandidateAdapters/`, with its own package/lockfile and
   pinned revisions. Its only shared contract is JSON and local file paths.
2. Begin with subprocess adapters around pinned `whisper-cli`, the owner
   SenseVoice native binary, and `llama-cli`. This is the smallest way to
   compare models without committing C++ or model packages to Fleck. The
   adapter supplies a 16 kHz mono WAV path, explicit local model path, language,
   and optional bounded context; it captures recognized text and timings. It
   never downloads at inference time.
3. Add one isolated Swift executable target only for the Qwen3-ASR Speech Swift
   spike. Pin a commit rather than `main`; use an explicit offline cache/model
   directory; expose whether context is supported; and build the Metal library
   in the adapter's Xcode path. Do not add Speech Swift or MLX to Fleck's root
   dependency graph during evaluation.
4. Normalize adapter output into the existing `CandidateRun` schema. Preserve
   exact recognizer text as `asrRaw`; apply the deterministic dictionary in the
   evaluation harness to create `dictionaryBaseline`; pass only that baseline
   to cleanup; store cleanup output separately as `cleanedResult`. Remove
   SenseVoice metadata tags structurally while retaining the exact recognized
   text.
5. Record process/model load separately from ASR and cleanup latency, sample
   peak/idle/post-unload memory for the whole adapter process tree, and record
   runtime/model revisions and artifact bytes. Diagnostics may name stable IDs,
   issue codes, and JSON paths, but must not print transcript text.
6. Use pre-provisioned, checksum-verified model directories and run with the
   network disabled. Audio stays in a disposable lab location, never the repo,
   cache, report, or history. Exercise explicit timeout, child-process failure,
   and cancellation so the existing fallback/cancellation gate is real.

The adapter is disposable measurement code. Product integration begins only
after one complete ASR-plus-cleanup combination passes the predeclared corpus,
resource, privacy, semantic, native-feasibility, and license gates.

## Required first benchmark matrix

Run each complete combination cold and warm on the same admitted corpus and
same M1/8 GB machine:

| ASR | Cleanup |
| --- | --- |
| Whisper `large-v3-turbo-q5_0` | Off; Qwen3-0.6B Q8; Qwen3.5-0.8B Q4_0 |
| Whisper `small` | Off only, unless it independently clears ASR gates |
| SenseVoiceSmall Q8 | Off; best cleanup from the Whisper row, only after license admission |
| Qwen3-ASR-0.6B pinned 5/8-bit conversion | Off; best cleanup from the Whisper row, only after native-adapter admission |

Advance Qwen3.5 Q8 only if Q4 fails semantic quality and the extra size still
fits the combined gate. Advance Paraformer only if contextual recognition is
the blocking ASR deficit. Advance a 1.7B model only as a labeled higher-memory
accuracy ceiling.

No candidate has been benchmarked here. Therefore this research makes no claim
about WER, CER, mixed-language accuracy, developer-term accuracy, latency,
memory, energy, cleanup fidelity, or parity with Wispr Flow. Wispr Flow's
private model/runtime architecture is unknown and is not inferred from its
user-visible behavior.
