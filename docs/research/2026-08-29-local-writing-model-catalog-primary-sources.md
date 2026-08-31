# Local writing model catalog: primary-source research and interface alternatives

**Research date:** 2026-08-29
**Scope:** Apple-silicon Macs, English dictation and faithful cleanup for Fleck
**Status:** planning evidence only; no model or profile in this document is release-admitted

## Executive conclusion

Fleck should catalog **immutable, task-specific profiles**, not mutable model
names. A profile is the exact tuple of role, source repository, source revision,
selected files and SHA-256 hashes, runtime ABI, conversion, precision,
capabilities, hardware envelope, license obligations, and Fleck evidence. The
same upstream checkpoint may have several profiles because offline, streaming,
custom-vocabulary, FP16, INT8, and latency-tier exports have different files,
runtime contracts, storage costs, and hardware evidence.

The primary-source shortlist worth taking into Fleck's own admission program is:

- **ASR controls/candidates:** Apple Speech as the system-managed control;
  FluidAudio/Core ML Parakeet TDT 0.6B v2 as the existing English batch control;
  Parakeet TDT-CTC 110M as a smaller primary-transcription candidate; Parakeet
  Unified English 0.6B as the most interesting combined batch/streaming
  candidate; and Parakeet EOU 120M as a distinct low-latency/utterance-boundary
  candidate.
- **Vocabulary assistance:** FluidAudio's Parakeet CTC 110M encoder/head is an
  auxiliary acoustic-evidence profile. It can run beside TDT v2, or the built-in
  CTC head can be used with the TDT-CTC 110M profile. It is not by itself a
  drop-in replacement for Fleck's primary transcription path.
- **Cleanup controls/candidates:** Fleck's deterministic faithful cleanup as
  the required fallback; Apple Foundation Models as a system-managed,
  availability-gated candidate; Gemma 3 270M IT as an efficiency candidate; and
  Gemma 3 1B IT as a quality candidate. Neither Gemma's general model card nor
  an MLX conversion is evidence that it preserves dictated meaning.

Vendor benchmark numbers below are useful for prioritizing experiments only.
They are not Fleck quality, latency, memory, lifecycle, packaging, legal, or
release evidence. An automatic recommender must consider only profiles that
have passed Fleck's gates on the relevant hardware cohort; otherwise it returns
the built-in safe path.

## Evidence vocabulary

This document uses the following levels so a model card can never silently turn
into a release claim:

| Level | Meaning | May drive a release recommendation? |
| --- | --- | --- |
| `VENDOR_CLAIM` | First-party model card, vendor benchmark, API documentation, or runtime repository statement. | No |
| `IDENTITY_VERIFIED` | Fleck has pinned a source revision, selected-file manifest, hashes, byte counts, runtime ABI, and license/notice material. | No |
| `LAB_COMPATIBLE` | The exact profile loads and completes bounded smoke cases in an isolated development harness. | No |
| `FLECK_QUALIFIED` | The exact profile passes Fleck corpora, faithfulness validators, performance, lifecycle, and fault-injection gates on a named hardware/OS cohort. | Only inside that cohort, after review |
| `SIGNED_APP_ACCEPTED` | The exact signed Fleck artifact passes hands-on behavior and provenance checks on named physical Macs. | Not by itself |
| `RELEASE_ADMITTED` | Legal/distribution review, packaging scan, CI, signed-app acceptance, and explicit release approval all bind to one immutable profile and app release. | Yes |

Every catalog entry proposed here starts with `releaseState: .notAdmitted`.
Existing local manifests or successful local packages are identity/provenance
inputs, not proof of any later level.

## Primary-source findings

### 1. Apple Speech is a system-managed control, not a distributable artifact

Apple's modern `SpeechAnalyzer`/`SpeechTranscriber` path performs transcription
on device, but locale-specific model assets may need to be fetched. Apple's
`AssetInventory` owns those assets: they are downloaded from Apple, retained,
updated, shared between apps, and may later be unsubscribed when unused. An app
reserves locales and can request installation, but it does not receive a stable
file manifest or control the system's update version.

Primary sources:

- [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber)
- [`AssetInventory`](https://developer.apple.com/documentation/speech/assetinventory)
- [WWDC25: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)

Relevant constraints:

- Supported locales and installed locales are separate queries. A locale can be
  supported but require asset installation.
- Locale reservations are limited; `maximumReservedLocales` can vary by device
  storage. `reserve(locale:)` can fail when there is no supporting asset or the
  limit would be exceeded.
- Releasing a reservation permits later system removal; Fleck does not delete
  Apple-owned files directly.
- The older `SFSpeechRecognizer` path is not automatically local. Fleck must
  check `supportsOnDeviceRecognition` before requiring on-device recognition.
  `SFSpeechRecognitionRequest.contextualStrings` accepts at most 100 brief
  custom phrases and is a hint rather than a deterministic dictionary rewrite.

Sources for the older path:

- [`supportsOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [`SFSpeechRecognitionRequest`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest)
- [`contextualStrings`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)

Catalog consequence: represent Apple Speech with a `systemManaged` profile and
an availability adapter. It has no artifact hashes, install size, repair-by-
redownload, or Fleck-owned removal operation. A successful availability probe
is runtime availability, not model-version identity.

### 2. Parakeet TDT 0.6B v2 remains an English batch/sliding-window control

FluidInference describes `parakeet-tdt-0.6b-v2-coreml` as an English, 16 kHz,
0.6B FastConformer-TDT Core ML conversion for Apple silicon and iOS. Its model
card claims about 110x real-time on an M4 Pro, about 800 MB peak memory, and
macOS 14+/iOS 17+ support. FluidAudio's manual-loading guide says the expected
runtime payload is four compiled Core ML bundles plus
`parakeet_vocab.json`.

Primary sources:

- [FluidInference Parakeet TDT 0.6B v2 Core ML model card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
- [FluidAudio manual ASR model loading](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ManualModelLoading.md)
- [FluidAudio model guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)

The repository contains more than one representation of some assets. A Fleck
profile must select only the required compiled runtime files; the size of the
entire repository is not the install size. The live model name or `main` branch
must never be used as identity.

Vendor claims do not answer Fleck's first-word capture, partial stability,
proper-name recall, long-dictation stitching, dictionary preservation, or stop-
to-insert latency questions.

### 3. TDT-CTC 110M is a primary ASR candidate; CTC 110M is also an auxiliary booster

FluidAudio now documents two related but different uses:

1. `parakeet-tdt-ctc-110m-coreml` is a full hybrid TDT/CTC transcription
   pipeline. Its model card describes a fixed 15-second, 16 kHz window and
   claims 3.0% WER on LibriSpeech test-clean, 102x real-time, and 0.3 GB peak
   memory on an Apple M2.
2. `parakeet-ctc-110m-coreml` supplies the CTC acoustic path used by custom
   vocabulary/keyword spotting. Its current repository tree contains an audio
   encoder, CTC head, mel spectrogram, tokenizer, and vocabulary material. This
   is a separately installed auxiliary profile when paired with TDT v2/v3.

Primary sources:

- [Parakeet TDT-CTC 110M Core ML model card](https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml)
- [Parakeet CTC 110M Core ML repository tree](https://huggingface.co/FluidInference/parakeet-ctc-110m-coreml/tree/main)
- [FluidAudio custom-vocabulary design](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md)
- [FluidAudio benchmark guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)

FluidAudio's custom-vocabulary documentation makes the compatibility split
explicit:

- TDT-CTC 110M can reuse its built-in CTC projection. FluidAudio labels this
  path beta and claims about 67 MB peak memory and 70.29x RTFx for its earnings
  benchmark.
- TDT v2/v3 requires a separate CTC encoder pass. FluidAudio labels this path
  stable and claims about 130 MB peak memory and 25.98x RTFx for the same
  benchmark.
- The document claims 99.4% dictionary recall for both paths. It also exposes
  aliases and global score/similarity controls. Those figures come from
  FluidAudio's benchmark and are not Fleck personal-dictionary evidence.

The booster should therefore be modeled as a **capability dependency** of a
transcription profile, not as a free-floating checkbox. A profile must bind the
TDT tokenizer, CTC tokenizer, frame geometry, thresholds, alias policy, and
compatible runtime versions. Mismatched tokenizers or encoder timing must fail
before inference.

There is a licensing inconsistency that blocks distribution admission without
resolution: the Hugging Face repository metadata for
`parakeet-ctc-110m-coreml` says `cc-by-4.0`, while text in the model card says
the conversion is Apache-2.0. Fleck must not choose whichever is more
convenient. The catalog needs a reviewed license record tied to the exact
revision and selected files.

### 4. Parakeet EOU is genuinely streaming but is a separate behavior profile

FluidInference's Parakeet Realtime EOU 120M Core ML conversion is an English
RNNT with cached streaming state and an explicit end-of-utterance token. Its
published table claims, on LibriSpeech test-clean and Apple M2:

| Export | Vendor latency | Vendor WER | Vendor RTFx |
| --- | ---: | ---: | ---: |
| 160 ms | 160 ms | 8.29% | 4.78x |
| 320 ms | 320 ms | 4.87% | 12.48x |

The model card's current text says two export sizes even though FluidAudio's
broader model guide also lists a 1280 ms subdirectory. This is another reason
to pin and inspect an exact revision rather than infer a profile from docs on
`main`.

Primary sources:

- [FluidInference Parakeet Realtime EOU 120M Core ML model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml)
- [NVIDIA upstream Parakeet Realtime EOU 120M model](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1)
- [FluidAudio model guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)

EOU must not be compared to v2 solely on average WER. Fleck must evaluate
partial churn, premature EOU, missed EOU, restart after pause, cancellation,
microphone interruption, and exact final-text convergence. An EOU runtime also
has state-reset invariants absent from a batch profile.

### 5. Parakeet Unified English is the most extensible speech candidate, not an automatic winner

NVIDIA's upstream `parakeet-unified-en-0.6b` combines offline and buffered
streaming inference in one English FastConformer-RNNT checkpoint, with
punctuation and capitalization. NVIDIA says streaming latency is configurable
down to 160 ms, but also states that the current inference path is buffered
streaming that recomputes left context.

FluidInference's Core ML conversion exposes one offline path and several
streaming attention-window exports. Its current model card claims:

| Fluid profile | Vendor aggregate WER | Vendor RTFx |
| --- | ---: | ---: |
| Offline batch, INT8 encoder | 1.68% | 143.6x overall |
| Streaming 2080 ms, INT8 encoder | 1.79% | 65.9x overall |
| Streaming 320 ms | 2.37% on a 150-file sweep | 10x |
| Streaming 640 ms | 2.40% on a 150-file sweep | 27x |
| Streaming 1120 ms | 2.25% on a 150-file sweep | 33x |

Primary sources:

- [NVIDIA Parakeet Unified English 0.6B model card](https://huggingface.co/nvidia/parakeet-unified-en-0.6b)
- [FluidInference Parakeet Unified English Core ML model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml)
- [FluidAudio unified benchmark documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md#parakeet-unified-english-batch--streaming)

The model repository contains offline/streaming and FP16/INT8 alternatives.
Each chosen combination must be a separate profile with exact selected files.
For example, `unified-int8-streaming-320ms` and
`unified-fp16-streaming-1120ms` cannot share installation evidence or hardware
admission merely because their family ID matches.

Unified's vendor benchmark is promising, but it does not establish Fleck's
push-to-talk latency, personal-dictionary behavior, semantic faithfulness, ANE
compatibility across supported Macs, or memory coexistence with cleanup.

### 6. Apple Foundation Models is an OS capability, not a version-pinned local download

Apple's `SystemLanguageModel` is the on-device text model underlying Apple
Intelligence. Availability depends on eligible hardware, region, Apple
Intelligence being enabled, model readiness, and supported locale. Apple
periodically changes the system model in OS updates and explicitly tells
developers to retest prompts for new model versions. The interface exposes
`availability`, `contextSize`, `supportedLanguages`, and `supportsLocale(_:)`;
Fleck should query rather than hard-code them.

Primary sources:

- [`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Supporting languages and locales with Foundation Models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

Catalog consequence: bind Apple Foundation Models to an OS/model-cohort probe,
prompt-template revision, output validator revision, and Fleck evaluation
evidence. There is no app-owned artifact revision to hash and no install,
repair, update, or remove operation. If unavailable, over context, cancelled,
or rejected by Fleck's faithful-cleanup validator, the latest whole
validator-accepted faithful baseline must remain authoritative. If no ASR and
dictionary baseline exists, no text may be published.

Custom Apple adapters are a separate program. Apple says they are tied to a
specific system-model version, require different adapters across OS model
versions, require an entitlement for deployment, and require Apple-silicon
training hardware with at least 32 GB memory (or Linux GPU machines). They
should not be smuggled into the base system profile.

Source: [Foundation Models adapter training](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)

### 7. Gemma 3 1B IT and 270M IT are cleanup candidates only after Fleck qualification

Google's official cards describe both instruction-tuned models as text-in/text-
out, multilingual Gemma 3 variants. The 1B and 270M variants have 32K total
context, not the 128K context of larger Gemma 3 variants. Google's general
benchmarks cover reasoning, instruction following, code, and multilingual
tasks; none is a dictated-text faithfulness benchmark.

Primary sources:

- [Google Gemma 3 1B IT model card](https://huggingface.co/google/gemma-3-1b-it)
- [Google Gemma 3 270M IT model card](https://huggingface.co/google/gemma-3-270m-it)
- [Google Gemma 3 model card](https://ai.google.dev/gemma/docs/core/model_card_3)

MLX Community publishes quantized conversions, including a 1B instruction-
tuned QAT 4-bit repository and a 270M instruction-tuned 4-bit repository. These
are conversion artifacts, not Google-authored runtime promises and not Fleck
quality evidence:

- [MLX Community Gemma 3 1B IT QAT 4-bit](https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit)
- [MLX Community Gemma 3 270M IT 4-bit](https://huggingface.co/mlx-community/gemma-3-270m-it-4bit)

The official `mlx-swift-lm` source currently contains a registry example for
`gemma-3-1b-it-qat-4bit`. The generic model factory may make other Gemma 3
variants loadable, but the absence of a 270M convenience entry means Fleck must
prove the exact 270M architecture/configuration path instead of assuming the
1B integration transfers.

Source: [`LLMModelFactory.swift`](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift)

For cleanup, both variants need the same strict contract: bounded prompt and
deadline, no tools/network, output-only cleaned text, cancellation, and a
deterministic validator that rejects changed facts, numbers, protected forms,
negation, names, list items, or unsupported rewrites. A smaller profile may win
on load and memory and still fail quality; a larger profile may win quality and
still fail stop-to-insert or 8 GB coexistence.

### 8. MLX Swift is a supported Apple-silicon runtime, not a model admission certificate

Apple's `ml-explore/mlx-swift` repository describes MLX Swift as the Swift API
for MLX on Apple silicon. It supports Xcode/SwiftPM integration and provides
iOS/macOS language-model examples. Important integration constraints include:

- command-line SwiftPM cannot build Metal shaders; the final build must use
  Xcode/`xcodebuild`;
- linking MLX into both an app and a framework can create two copies in one
  process and may fail;
- LLM/VLM implementations live in `mlx-swift-lm`, whose current `main` is a
  breaking 3.x line with downloader/tokenizer integrations separated from the
  core package;
- the `MLXFoundationModels` bridge requires the macOS/iOS/visionOS 27 SDK;
- the MLX Swift and MLX Swift LM code is MIT-licensed, but that does not replace
  the model weights' Gemma terms.

Primary sources:

- [MLX Swift](https://github.com/ml-explore/mlx-swift)
- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)
- [MLX Swift license](https://github.com/ml-explore/mlx-swift/blob/main/LICENSE)
- [MLX Swift LM license](https://github.com/ml-explore/mlx-swift-lm/blob/main/LICENSE)

Fleck should pin the exact Swift package revisions and record an explicit
runtime ABI string in every MLX profile. A green Python `mlx-lm` invocation is
not Swift integration evidence.

## Distribution and license constraints

This section is an engineering checklist, not legal advice. Final distribution
still requires review against the exact files and terms in the candidate
revision.

### FluidAudio runtime code

The current FluidAudio repository identifies its SDK as Apache-2.0. Apache 2.0
redistribution requires a copy of the license, prominent notices on modified
files, retention of applicable source notices, and preservation of any
repository `NOTICE` material.

Sources:

- [FluidAudio license](https://github.com/FluidInference/FluidAudio/blob/main/LICENSE)
- [Apache License 2.0, section 4](https://www.apache.org/licenses/LICENSE-2.0)

### CC BY 4.0 Core ML conversions

The current Hugging Face metadata/model cards identify TDT v2, TDT-CTC 110M,
CTC 110M, and Unified English Core ML repositories as CC BY 4.0. When shared,
CC BY 4.0 requires supplied creator/copyright/license/disclaimer information,
a URI to the source where practicable, an indication of modifications, and a
license link/text. It prohibits downstream terms or technical measures that
restrict recipients' exercise of the licensed rights.

Source: [CC BY 4.0 legal code, sections 2(a)(5) and 3(a)](https://creativecommons.org/licenses/by/4.0/legalcode.en)

The CTC 110M metadata/card disagreement described earlier must be resolved per
revision before any distribution. Catalog validation should reject ambiguous
or conflicting license records.

### NVIDIA Open Model License profiles

The EOU model card and NVIDIA's Unified upstream card use the NVIDIA Open Model
License. NVIDIA describes covered models as commercially usable, but the grant
is conditioned on the agreement, Trustworthy AI terms, guardrail conditions,
and trade compliance. Redistribution of the model requires a copy of the
agreement and a `Notice` file containing the specified NVIDIA attribution.
Separately licensed components keep their own notices/terms.

Source: [NVIDIA Open Model License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)

Fleck should store the license version/date and the exact notice payload in the
profile. A shorthand such as `other` or `nvidia-open-model-license` is not a
sufficient distribution record.

### Gemma terms

Google's current Gemma terms apply to Gemma 3 and define distribution broadly,
including hosted functionality. Distribution of Gemma/model derivatives
requires passing through the use restrictions, providing recipients the
agreement, marking modified files, and including the specified `Notice` file.
The prohibited-use policy is incorporated by reference. The terms also require
deletion and cessation of use/distribution after termination.

Source: [Gemma Terms of Use](https://ai.google.dev/gemma/terms)

The Google Hugging Face repositories require a user to accept the Gemma terms
before accessing their files. A public MLX conversion does not remove the Gemma
terms. Fleck must not embed a developer's Hugging Face token, copy an acceptance
receipt across users, or silently accept terms on someone's behalf. If Fleck
distributes weights itself, the release package and customer terms must carry
the required agreement, notice, and restrictions. If Fleck downloads from a
third party, the legal and authentication flow still needs explicit review.

### Runtime license is not model license

Apache-2.0 FluidAudio or MIT MLX code can coexist with model weights under
different terms, but the catalog must preserve all layers:

1. app/runtime source license;
2. converter code and conversion notices;
3. upstream checkpoint terms;
4. converted artifact terms and attribution;
5. tokenizer/data/auxiliary component terms;
6. Fleck modifications and notice statements.

An entry is legally incomplete if any layer is `unknown`, contradictory, or a
moving URL with no captured content hash/version.

## Research snapshot of mutable repositories

The following revisions were observed through the official Hugging Face model
metadata API on 2026-08-29. They are **research anchors only**. They are not
complete Fleck manifests, and recording them does not admit or install a model.

| Repository | Observed revision | Repository-declared license |
| --- | --- | --- |
| `FluidInference/parakeet-tdt-0.6b-v2-coreml` | `ee09c569f73759e6d44c9bd16766f477b2b36d39` | `cc-by-4.0` |
| `FluidInference/parakeet-ctc-110m-coreml` | `accdafd8cf8a2ff1cabe3c11e54416b405d409aa` | `cc-by-4.0` (conflicts with card text) |
| `FluidInference/parakeet-tdt-ctc-110m-coreml` | `9bc92ead6e8f17eca92a869fd578ae76842b82ba` | `cc-by-4.0` |
| `FluidInference/parakeet-realtime-eou-120m-coreml` | `40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355` | repository metadata `other`; card names NVIDIA Open Model License |
| `FluidInference/parakeet-unified-en-0.6b-coreml` | `4252711f6f060f9a2f91e5f081a806d7f45eebd8` | `cc-by-4.0` |
| `mlx-community/gemma-3-1b-it-qat-4bit` | `15fed4eafb456c6fcb2a1165f19ac609670ed14b` | `gemma` |
| `mlx-community/gemma-3-270m-it-4bit` | `ff1143e3a10547c9f2129e94ca37059b096b23f4` | `gemma` |

API sources use the form
`https://huggingface.co/api/models/{owner}/{repo}?blobs=true`, for example:

- [TDT v2 metadata](https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v2-coreml?blobs=true)
- [Unified metadata](https://huggingface.co/api/models/FluidInference/parakeet-unified-en-0.6b-coreml?blobs=true)
- [Gemma 1B MLX metadata](https://huggingface.co/api/models/mlx-community/gemma-3-1b-it-qat-4bit?blobs=true)

Repository totals are deliberately omitted as recommendation inputs: these
repositories contain alternative exports and conversion material. A profile's
download/install size must be the checked sum of its selected files.

## Recommended conservative catalog design

### Catalog layers

Use four immutable layers and one mutable local receipt:

1. **Family record** — human grouping only (`parakeet-unified-en-0.6b`,
   `gemma-3-1b-it`). It cannot be installed or recommended.
2. **Artifact manifest** — exact upstream repository/revision and a canonical,
   sorted selected-file list with byte count and SHA-256 for every file.
3. **Runtime profile** — binds one artifact manifest (or one system capability)
   to a role, runtime ABI, inference mode, precision, tokenizer/prompt contract,
   capabilities, resource envelope, licenses, and evidence bundle.
4. **Catalog snapshot** — immutable set of profiles plus deterministic
   recommendation rules, signed or embedded with a Fleck build.
5. **Installation receipt** — mutable device-local evidence of what Fleck
   actually staged and verified. It references immutable IDs and never edits a
   manifest.

This prevents three common category errors: selecting a family rather than an
export, treating system assets like downloadable files, and treating an
installed artifact as release-admitted.

### Canonical identity

> **Normative-design note:** this section is a research sketch. The complete,
> normative identity contract is the later
> `2026-08-29-curated-local-model-catalog-design.md`; where this sketch is
> narrower, that design supersedes it.

Every downloaded profile ID should be a digest of canonical manifest material:

```text
profileID = sha256(canonical(
  schemaVersion || profileKey || family || role || distribution ||
  artifactManifestOrSystemCapabilityIdentity || sourceURL || sourceRevision ||
  ordered(path, bytes, sha256)* || completeRuntimeContract ||
  orderedCapabilities || supportEnvelope || resourceEnvelope ||
  orderedLicenseRecords || evidenceCompatibilityRevision
))
```

Rules:

- no `latest`, tags, branches, query-bearing URLs, redirects to unapproved
  hosts, or mutable filenames;
- paths are relative, Unicode-normalized, separator-normalized, unique, and
  reject empty/absolute/`..`/symlink traversal;
- byte sums use checked integer arithmetic;
- non-LFS Git blobs need a computed SHA-256 even when the host exposes only a
  Git object ID;
- the selected-file set is closed: missing and unexpected files both fail;
- runtime ABI includes the exact FluidAudio or MLX Swift/LM revision and the
  profile's own adapter ABI;
- license/notice material is content-hashed and participates in identity;
- an artifact manifest cannot contain secrets, user tokens, acceptance cookies,
  or machine-local paths.

### Suggested profile schema

```swift
struct ModelProfile: Codable, Sendable {
  let id: ModelProfileID
  let family: ModelFamilyID
  let role: ModelRole                 // asr, vocabularyBooster, cleanup
  let releaseState: ReleaseState      // always notAdmitted until governance flips it
  let distribution: Distribution
  let runtime: RuntimeContract
  let capabilities: [Capability]       // canonical sorted unique array; never Set-encoded
  let support: SupportEnvelope
  let resources: ResourceEnvelope
  let licenses: [LicenseRecord]
  let evidence: EvidenceBundleID?
}

enum Distribution: Codable, Sendable {
  case fleckManaged(ArtifactManifestID)
  case systemManaged(SystemCapabilityID)
}

struct ArtifactManifest: Codable, Sendable {
  let schemaVersion: Int
  let source: URL
  let revision: String
  let files: [ArtifactFile]           // canonical order, exact closed set
  let downloadBytes: Int64
  let installedBytes: Int64
  let stagingBytes: Int64             // checked peak during side-by-side update
}

struct RuntimeContract: Codable, Sendable {
  let adapterID: RuntimeAdapterID
  let adapterABI: String
  let dependencyRevisions: [SourceRevision]
  let input: InputContract
  let output: OutputContract
  let cancellation: CancellationContract
  let stateReset: StateResetContract?
}
```

`Capability` should describe observable behavior, not marketing labels. Useful
initial values include `offlineFinalTranscript`, `streamingPartials`,
`endOfUtterance`, `wordTimestamps`, `punctuation`, `capitalization`,
`acousticVocabularyBoost`, `guidedCleanup`, and `systemManagedAvailability`.

### Candidate profile records to curate

The first catalog can remain small while preserving extensibility:

| Proposed profile key | Role | Distribution | Important binding |
| --- | --- | --- | --- |
| `apple-speech-en-system` | ASR | system-managed | locale, installed asset, exact analyzer/transcriber path |
| `parakeet-v2-en-coreml-batch` | ASR | Fleck-managed | four compiled bundles + vocabulary, 15 s window/stitching |
| `parakeet-tdt-ctc-110m-en-coreml-batch` | ASR | Fleck-managed | fused/full hybrid file set, TDT final output |
| `parakeet-v2-plus-ctc110m-en` | ASR + booster | compound Fleck-managed | exact v2 profile + exact auxiliary CTC profile + rescorer policy |
| `parakeet-unified-en-coreml-{precision}-{tier}` | ASR | Fleck-managed | offline or one exact streaming tier; never install all exports by default |
| `parakeet-eou-120m-en-coreml-{tier}` | ASR | Fleck-managed | explicit state reset and EOU debounce policy |
| `apple-foundation-cleanup-system-{osCohort}` | cleanup | system-managed | availability, prompt revision, validator revision |
| `gemma3-270m-it-mlx-{precision}` | cleanup | Fleck-managed | exact MLX conversion, tokenizer/chat template, validator |
| `gemma3-1b-it-mlx-{precision}` | cleanup | Fleck-managed | exact MLX conversion, tokenizer/chat template, validator |

All rows remain research candidates until an evidence bundle gains explicit
release admission.

## Automatic hardware recommendation

### Inputs

Recommendation must be a pure, deterministic function of a catalog snapshot,
a requested role/capability set, and a fresh hardware/runtime observation:

- architecture and machine identifier;
- macOS version/build and app/runtime ABI;
- installed physical memory and active processor count;
- fresh reclaimable-memory estimate and memory-pressure state;
- thermal state and Low Power Mode;
- available capacity for important usage and required side-by-side staging;
- locale and audio input contract;
- Apple Speech asset and Apple Foundation Models availability;
- whether ASR and cleanup are permitted to coexist on this hardware cohort;
- the profile's Fleck evidence cohorts and unresolved legal/packaging blockers.

### Hard gates before ranking

A profile is ineligible if any of these is false. This research list is
superseded by the normative build-capability/claim/cohort contract in the
curated-catalog design:

1. the operation is authorized by the active build capability: normal
   `ordinarySafe` use accepts only admitted/system/deterministic profiles;
   explicit Quality Lab acquisition may use only its exact
   identity-verified development profile; and an exact
   `signedDistributionCandidate` may use only its embedded D5 tuple with the
   same claim and operator/speaker cohort—it never broadens that claim;
2. architecture, OS, locale, runtime ABI, and required capabilities match;
3. the exact hardware/OS cohort is covered by accepted Fleck evidence;
4. storage exceeds checked `stagingBytes` plus Fleck's reserve margin;
5. license/notice record is reviewed and complete for the intended
   distribution path;
6. no known profile/runtime incompatibility or revoked evidence applies;
7. phase-aware residency policy can satisfy memory limits without concurrent
   unsafe models.

If no profile passes, return the built-in safe path. Unknown machine IDs,
missing probes, arithmetic overflow, stale evidence, or ambiguous license data
fail closed.

### Ranking eligible profiles

Ranking should use Fleck measurements only, normalized within the supported
hardware cohort. A reasonable priority order for push-to-talk English writing
is:

1. faithful final text and protected-form preservation;
2. stop-to-insert p95 and cold-start success;
3. capture boundary/first-word and finalization reliability;
4. peak resident memory and pressure survival;
5. streaming partial stability, if the UI consumes partials;
6. install/staging size and energy;
7. vendor claims only as displayed provenance, never as score inputs.

Recommendation selects a **profile**, not a family. It returns the reasons and
the evidence bundle used so Settings can explain the decision. A user may choose
another admitted compatible profile; the recommender must not expose
unadmitted profiles outside an explicit developer lab.

For constrained Macs, use a phase-aware policy: ASR active -> ASR cold ->
cleanup load -> cleanup active -> cleanup cold/eligible warm state. Do not infer
that two individually qualified models are jointly safe.

## Local lifecycle: install, verify, repair, update, remove

### Artifact and runtime residency are separate state machines

```swift
enum ArtifactResidency: Sendable {
  case absent
  case staging(OperationID, received: Int64, expected: Int64)
  case quarantined(OperationID)
  case verified(InstallationReceiptID)
  case repairRequired(IntegrityFailure)
  case removing(OperationID)
}

enum RuntimeResidency: Sendable {
  case unavailable
  case cold
  case loading(LeaseID)
  case warm(LeaseID, expiresAt: ContinuousClock.Instant?)
  case active(LeaseID)
  case unloading(LeaseID)
  case failed(RuntimeFailure)
}

enum UpdateStatus: Sendable {
  case unknown
  case current(ModelProfileID)
  case available(current: ModelProfileID, replacement: ModelProfileID)
  case blocked(reason: UpdateBlocker)
}
```

`installed` must never imply `loaded`, and `loaded` must never imply
`releaseAdmitted`. Update availability is orthogonal to residency.

### Install

1. Resolve an exact operation-authorized profile from the immutable catalog.
   Normal Settings requires release admission; an explicit developer-lab
   evaluation may use an identity-verified, legally reviewed candidate that
   remains nonselectable outside that lane.
2. Re-probe architecture, ABI, license/acceptance state, and live staging
   capacity before any network call.
3. Create a random staging directory inside the profile's receipt-owned storage
   namespace. Never stage in the final directory.
4. Fetch only revision-pinned selected files. Allowlist redirect schemes/hosts,
   stream to new files, enforce expected byte ceilings, and compute SHA-256 as
   bytes arrive.
5. Reject missing, duplicate, case-colliding, unsafe, symlink, device, and
   unexpected paths. Never extract an untrusted archive into the final root.
6. Verify the closed manifest, runtime metadata/configuration, license/notice
   material, and checked byte totals while still quarantined.
7. Run a bounded adapter load/smoke with no transcript upload or hidden network
   retry.
8. Atomically rename the verified staged tree into its content-addressed final
   namespace and write a signed/MACed local receipt. Only then publish
   `verified`.

Cancellation removes only the operation's staging root. It cannot modify a
previous verified profile.

### Verify

Verification is explicit and idempotent:

- validate the receipt-to-profile identity;
- re-open files without following symlinks;
- require the exact manifest set and byte counts;
- recompute SHA-256 for every selected file;
- validate runtime metadata, tokenizer/chat template, and Core ML/MLX adapter
  contract;
- report `repairRequired` before inference on any mismatch.

System-managed profiles instead run their availability/locale probe and return
typed reasons such as asset not installed, model not ready, device ineligible,
or user disabled. Fleck must not translate that result into a fake file receipt.

### Repair

Repair is install-to-new-staging followed by atomic replacement. It never
patches a verified tree in place. It must first acquire the model-mutation
barrier and wait for all runtime leases to become cold. If the fresh repair
fails, the corrupt tree remains quarantined/unavailable and the safe fallback
continues.

### Update

An update is a transition between two immutable profile IDs, never mutation of
one profile:

1. a newer signed/embedded catalog declares the replacement and migration
   relationship;
2. Fleck presents exact size, license, capability, and evidence changes;
3. install the replacement side by side;
4. verify and smoke it before selection changes;
5. atomically switch the selected profile;
6. retain the prior verified profile until the new profile survives the
   rollback window, subject to space and user choice;
7. remove the prior profile only through its own receipt.

Moving upstream `main` never triggers an update. A catalog refresh may discover
research candidates, but only a new admitted immutable profile can be offered
as a normal update.

### Remove

Removal requires the mutation barrier, no active/warm/loading lease, and an
exact receipt-owned namespace beneath Fleck's model root. Refuse broad roots,
unresolved symlinks, missing/mismatched receipts, or paths outside the namespace.
Remove the selected profile only after switching to a safe fallback. System-
managed removal means releasing Fleck's locale reservation or disabling use;
the OS decides when Apple-owned assets are deleted.

## Fleck evidence gates

No profile becomes `RELEASE_ADMITTED` until all applicable gates bind to the
same immutable profile and Fleck build.

### Gate 1: source, identity, and legal

- exact source/revision and canonical selected-file manifest;
- independent verification of every byte count and SHA-256;
- runtime/converter/upstream/model/tokenizer license stack;
- reviewed notices and modification markers;
- terms/acceptance flow that does not reuse developer credentials;
- no unresolved metadata/card disagreement.

### Gate 2: runtime integration

- exact Swift package revisions and adapter ABI;
- Xcode/arm64 build, strict concurrency, cancellation, and offline mode;
- no duplicate MLX linkage or hidden downloader;
- load, unload, repeated load, corrupt config, missing file, and wrong-shape
  failures are typed and fail closed;
- EOU/streaming caches reset exactly between captures.

### Gate 3: English writing quality

Use Fleck-owned, versioned corpora and frozen scoring code:

- clean/quiet, far-field, noisy, accented, fast, hesitant, and interrupted
  dictation;
- first/last word, numbers, currency, percentages, dates, punctuation,
  capitalization, proper nouns, code/technical terms, lists, and corrections;
- short, medium, and long captures;
- personal-dictionary canonical forms, aliases, collisions, false boosts, and
  repeated protected occurrences;
- raw ASR, dictionary baseline, cleaned candidate, validator result, and final
  inserted text kept as separate evidence.

Report aggregate WER/CER only with subgroup distributions and error examples.
A lower WER cannot override changed meaning or protected-form loss.

### Gate 4: faithful cleanup

- exact-fact, numeric/sign/currency/unit, negation, entity/name, list-item, and
  ordering preservation;
- only the explicitly allowed punctuation, capitalization, whitespace,
  filler/repetition, spoken-correction, and list-formatting changes;
- adversarial prompt-like transcript content cannot change the cleanup
  instructions;
- malformed, empty, overlong, timed-out, cancelled, or unfaithful output uses
  the latest validator-accepted faithful baseline; raw ASR and dictionary
  baseline remain separate immutable evidence values;
- 270M and 1B are scored separately at the exact quantization and prompt
  revision.

### Gate 5: performance and residency

On every supported hardware/OS cohort:

- cold/warm load p50/p95; first partial; finalization; stop-to-insert p50/p95;
- peak resident bytes, sustained bytes, memory-pressure response, swap impact,
  thermal/power behavior, and energy;
- ASR-only, cleanup-only, and phase-aware handoff measurements;
- no concurrent open-weight ASR/cleanup residency on constrained profiles;
- repeated capture soak, cancellation at each phase, sleep/wake, microphone
  interruption, model mutation, disk-full, and network-loss tests.

### Gate 6: installer and fault injection

- redirect, truncated file, wrong length, wrong hash, duplicate/unexpected path,
  traversal, case collision, symlink, stale receipt, crash during each phase,
  resume-data tampering, insufficient capacity, and concurrent-operation tests;
- repair/update are side-by-side and atomic;
- removal proves it touches only receipt-owned files;
- inference can never load staging or quarantined files.

### Gate 7: packaging and physical acceptance

- full focused and regression suites plus an arm64 release build;
- bundle/ZIP scan proving whether weights and every required notice are or are
  not included as designed;
- signing/notarization checks appropriate to the release lane;
- installed/running executable and model-receipt provenance captured
  immediately before hands-on testing;
- physical 8 GB and roomier Apple-silicon Macs, supported macOS versions,
  offline relaunch, install/repair/update/remove, microphone dictation, and
  fallback behavior;
- final explicit legal and release approval.

Vendor benchmarks, a green unit suite, a successful model download, a compiled
app, ad-hoc codesign, a Simulator run, or a single physical smoke each close
only their own gate.

## Radically extensible alternative: `ModelCatalogModule`

The conservative design above can fit Fleck's current one-recommendation
surface. A more radical alternative makes the catalog a deep module with a
small external interface and a capability graph behind the seam. It supports
new roles, compound profiles, system assets, multiple stores, and new runtimes
without teaching Settings or dictation coordinators about providers.

### External interface

```swift
actor ModelCatalogModule {
  init(
    catalogSource: any CatalogSourceAdapter,
    artifactStore: any ArtifactStoreAdapter,
    systemAssets: any SystemAssetAdapter,
    runtimes: RuntimeAdapterRegistry,
    hardware: any HardwareProbeAdapter,
    evidence: any EvidenceStoreAdapter,
    legalPolicy: any LegalPolicyAdapter,
    clock: any Clock<Duration>
  )

  func resolve(_ request: ModelRequest) async throws -> ModelResolution

  func observe(_ scope: ObservationScope) -> AsyncStream<ModelCatalogEvent>

  func perform(
    _ operation: ModelOperation,
    authorization: ModelOperationAuthorization
  ) -> AsyncThrowingStream<ModelOperationEvent, Error>
}
```

Three entry points cover query, observation, and mutation. Callers never see
downloaders, filesystem paths, Core ML graphs, MLX containers, Apple asset
reservations, hashes, receipts, locks, or benchmark stores.

### Request and resolution types

```swift
struct ModelRequest: Sendable {
  let role: ModelRole
  let locale: Locale.Language
  let required: [ModelCapability] // canonical sorted unique
  let preferred: [ModelCapability] // canonical sorted unique
  let latencyClass: LatencyClass
  let privacy: PrivacyConstraint        // localOnly for this Fleck program
  let residencyBudget: ResidencyBudget
  let selection: SelectionPolicy        // automatic or exact admitted profile
}

enum ModelResolution: Sendable {
  case ready(ModelHandle, rationale: ResolutionRationale)
  case needsOperation(ModelPlan, rationale: ResolutionRationale)
  case fallback(FallbackHandle, reasons: [IneligibilityReason])
}

struct ModelHandle: Sendable {
  let profileID: ModelProfileID
  let catalogRevision: CatalogRevision
  let capabilities: [ModelCapability] // canonical sorted unique
  let lease: RuntimeLease
}
```

`ModelHandle` is opaque. Inference-specific callers pass it to an ASR or cleanup
adapter facade; they cannot turn it into a path or load a different revision.

### Operation types

```swift
enum ModelOperation: Sendable {
  case install(ModelPlan)
  case verify(ModelProfileID)
  case repair(ModelProfileID)
  case update(from: ModelProfileID, to: ModelProfileID)
  case remove(ModelProfileID)
  case releaseSystemReservation(SystemCapabilityID)
}

enum ModelOperationEvent: Sendable {
  case accepted(OperationID)
  case waitingForMutationBarrier
  case progress(stage: OperationStage, completed: Int64, total: Int64?)
  case verified(InstallationReceiptID)
  case selected(ModelProfileID)
  case completed(ModelCatalogSnapshot)
}
```

`ModelOperationAuthorization` is an unforgeable app-layer value issued only
after the user/approved automation authorizes a concrete operation. It contains
the exact operation digest and expiry, not credentials or license acceptance.

### Capability graph

Behind the seam, a profile is a node and requirements/dependencies are edges:

```swift
struct ProfileNode: Sendable {
  let profile: ModelProfile
  let provides: [ModelCapability] // canonical sorted unique
  let requires: [ProfileRequirement]
  let conflicts: [ProfileConflict]
}

enum ProfileRequirement: Sendable {
  case profile(ModelProfileID)
  case capability(ModelCapability, constraint: VersionConstraint)
  case system(SystemCapabilityID)
  case runtime(RuntimeAdapterID, abi: ABIConstraint)
}

enum ProfileConflict: Sendable {
  case concurrentResidency(ModelProfileID, HardwarePredicate)
  case runtime(RuntimeAdapterID, VersionConstraint)
  case os(OSPredicate)
}
```

This makes `TDT v2 + CTC 110M + rescorer policy` a compound plan without
hard-coding Parakeet into the module interface. It also represents Apple Speech
and Apple Foundation Models as system nodes with no artifact store.

### Adapter seams

| Adapter | Responsibility | Explicitly cannot do |
| --- | --- | --- |
| `CatalogSourceAdapter` | Load and authenticate an immutable catalog snapshot. | Admit profiles or mutate installs. |
| `ArtifactStoreAdapter` | Stage, hash, atomically commit, verify, and remove receipt-owned artifacts. | Choose a model or perform inference. |
| `SystemAssetAdapter` | Probe/reserve/install/release Apple-managed capabilities. | Invent hashes or promise stable system versions. |
| `RuntimeAdapter` | Validate runtime contract, load/unload, health-check, and create typed inference sessions. | Download or select a different profile. |
| `HardwareProbeAdapter` | Return fresh, typed environment observations. | Rank profiles. |
| `EvidenceStoreAdapter` | Return signed evidence bound to profile, cohort, scorer, and Fleck release. | Convert vendor claims into Fleck evidence. |
| `LegalPolicyAdapter` | Evaluate exact license/notice/acceptance records for an intended operation. | Silently accept terms or waive ambiguity. |
| `ASRSessionAdapter` | Consume 16 kHz audio and return typed partial/final results. | Cleanup or edit facts. |
| `CleanupSessionAdapter` | Produce one candidate under a bounded prompt/deadline. | Bypass the faithful validator. |

One adapter means a hypothetical seam; do not introduce provider protocols
until there are at least two real implementations or a test double needed at
that seam. The system/Fleck-managed split and Core ML/MLX runtime split already
justify their respective seams.

### Invariants

1. Catalog revisions, profiles, manifests, and evidence bundles are immutable
   and content-addressed.
2. Only an admitted profile may be returned as `ready` in a normal release.
   Developer-lab visibility is a separate build capability, not a flag in a
   production request.
3. Vendor claims are display metadata only and cannot satisfy a recommendation
   predicate.
4. A runtime lease binds one exact profile ID, catalog revision, receipt, and
   hardware observation. The runtime cannot substitute assets.
5. Artifact mutation is serialized per storage namespace and waits for all
   affected runtime leases to become cold.
6. No operation writes outside its random staging root or exact receipt-owned
   final namespace.
7. A verified old profile remains selected until a new profile is completely
   staged, verified, smoke-tested, and atomically selected.
8. System-managed profiles never expose fake file manifests and never use
   Fleck-owned deletion.
9. Recommendation is deterministic for the same catalog, evidence,
   authorization, and hardware observation; rationale lists every exclusion.
10. Missing probes, stale evidence, unknown license terms, identity mismatch,
    overflow, or adapter disagreement fail closed to fallback.
11. ASR output, dictionary baseline, cleanup candidate, validator result, and
    inserted text remain distinct values across the interface.
12. Cancellation is idempotent and eventually returns affected runtimes to a
    known cold or safe warm state before mutation proceeds.

### Error model

```swift
enum ModelCatalogError: Error, Sendable {
  case invalidCatalog(CatalogValidationFailure)
  case staleCatalog(expected: CatalogRevision, actual: CatalogRevision)
  case unknownProfile(ModelProfileID)
  case notAdmitted(ModelProfileID)
  case incompatible(profile: ModelProfileID, reasons: [IneligibilityReason])
  case evidenceMissing(ModelProfileID, HardwareCohort)
  case legalBlocked(ModelProfileID, LegalBlocker)
  case authorizationRequired(OperationDigest)
  case operationConflict(active: OperationID)
  case insufficientCapacity(required: Int64, available: Int64)
  case integrityFailure(ModelProfileID, IntegrityFailure)
  case runtimeABIMismatch(expected: String, actual: String)
  case systemCapabilityUnavailable(SystemCapabilityID, SystemUnavailableReason)
  case modelMutationTimedOut(ModelProfileID)
  case cancelled(OperationID)
  case fallbackRequired([IneligibilityReason])
}
```

Errors carry typed, non-secret details. UI copy is produced outside the module;
raw filesystem paths, tokens, cookies, and transcript content do not appear in
errors or telemetry.

### Usage example

```swift
let request = ModelRequest(
  role: .asr,
  locale: Locale.Language(identifier: "en"),
  required: [.offlineFinalTranscript],
  preferred: [.streamingPartials, .acousticVocabularyBoost],
  latencyClass: .pushToTalk,
  privacy: .localOnly,
  residencyBudget: .adaptive,
  selection: .automatic
)

switch try await catalog.resolve(request) {
case .ready(let handle, let rationale):
  logger.recordProfileDecision(handle.profileID, rationale.evidenceIDs)
  try await dictation.begin(using: handle)

case .needsOperation(let plan, let rationale):
  settings.present(plan, rationale: rationale) // user may authorize install

case .fallback(let fallback, let reasons):
  try await dictation.begin(using: fallback)
  settings.explainFallback(reasons)
}
```

Settings performs an authorized operation without learning implementation
details:

```swift
let events = catalog.perform(.install(plan), authorization: authorization)
for try await event in events {
  modelSettings.consume(event)
}
```

### What the module hides

- catalog signature/schema migration and canonical identity;
- capability-graph planning and deterministic ranking;
- source authentication, redirects, resumption, staging, hashing, receipts,
  atomic selection, rollback, and safe removal;
- Apple asset reservations and Foundation Models availability;
- Core ML and MLX adapter construction, package ABI, warm/cold leases, and
  phase-aware conflict scheduling;
- evidence/legal evaluation and reason generation;
- concurrency, cancellation, crash recovery, and operation observation.

The deletion test is strong: removing the module would spread profile identity,
download safety, system-asset handling, recommendation, legal/evidence checks,
and lease/mutation coordination across Settings, dictation, cleanup, and tests.

### Tradeoffs

Advantages:

- new model families, providers, system capabilities, latency tiers, and
  compound profiles can be data/adapters rather than caller changes;
- one interface gives Settings, dictation, cleanup, tests, and diagnostics the
  same truthful state;
- safety rules and fallback behavior have high locality;
- the interface remains three methods even as implementation capability grows.

Costs/risks:

- the internal implementation is materially more complex than Fleck's current
  one-recommendation path;
- a generic capability graph can become a stringly typed policy language unless
  capability IDs and schemas are curated and versioned;
- catalog/evidence signing and schema migration add operational work;
- adapter registries can hide unsupported combinations unless validation is
  exhaustive;
- a broad interface implementation could become a premature platform before
  Fleck has two admitted profiles.

Recommendation: implement the conservative immutable profile/receipt model
first, but choose IDs, states, and operation events that can later sit behind
this deep module. Do not implement the full capability graph until Fleck has at
least two real runtime adapters or one compound profile whose variation would
otherwise leak into callers.

## Decision-ready next research packets

Before candidate adapter/acquisition work or candidate selection, produce the
applicable bounded evidence packets below. Behavior-neutral corpus,
instrumentation, and dictionary work does not depend on artifact manifests:

1. **Exact artifact manifests:** generate selected-file manifests from pinned
   revisions for TDT-CTC 110M, CTC booster, one Unified tier/precision, one EOU
   tier, Gemma 270M IT, and Gemma 1B IT. Resolve all license conflicts first.
2. **Runtime ABI matrix:** pin FluidAudio and MLX Swift/LM revisions and prove
   which macOS deployment targets and Xcode toolchains build the exact adapters.
3. **Fleck corpus/scorer freeze:** version English ASR, dictionary, cleanup,
   performance, and lifecycle cases before running candidates.
4. **Hardware cohorts:** at minimum an 8 GB Apple-silicon Mac and the roomier
   target Mac, with OS build and power/thermal state captured.
5. **System controls:** run the same corpus through Apple Speech and Apple
   Foundation Models with availability/model-cohort evidence, not static model
   identity claims.
6. **Joint-residency plan:** prove phase-aware ASR-to-cleanup handoff before
   comparing end-to-end stop-to-insert latency.

None of these packets authorizes a download, model-asset write, package change,
candidate selection, public distribution, or release admission.
