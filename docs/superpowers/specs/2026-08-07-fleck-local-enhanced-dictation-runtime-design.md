# Fleck Local Enhanced Dictation Runtime Design

**Date:** 2026-08-07

**Status:** Approved product direction; production model selection remains benchmark-gated

**Scope:** Entirely local Enhanced Dictation, optional local transcript cleanup, personal vocabulary, and one-click model installation

**Accepted foundation:** `27f7a44e93e8395d8d9c3d952064a28c87b1768d`

## Spec sheet

| Decision | Selected direction |
| --- | --- |
| User experience | One **Install Enhanced Dictation** button in onboarding and Settings |
| Privacy | Audio and transcript inference remain on the Mac; network is used only for model installation and updates |
| Compatibility | Fleck and Apple Standard retain macOS 14 support; Enhanced Dictation may require Apple silicon and macOS 15+ |
| ASR preference | Benchmark Nemotron 3.5 ASR 0.6B through NeMo-Speech.cpp first as the streaming challenger |
| ASR control | Benchmark Whisper `small` and `large-v3-turbo-q5_0` through whisper.cpp |
| ASR feature challenger | Admit Qwen3-ASR-0.6B only after a short native-Apple runtime spike passes |
| Cleanup preference | Benchmark Qwen3.5-0.8B Q4_0 through llama.cpp |
| Cleanup control | Benchmark Qwen3-0.6B Q8 through llama.cpp and retain cleanup Off |
| Dictionary | Use ASR context where supported, deterministic post-ASR resolution, protected cleanup spans, and validation fallback |
| Packaging | Ship signed runtime code inside Fleck and present one curated, data-only Enhanced Dictation model bundle |
| Resource policy | ASR and cleanup never require simultaneous large-model residency on the M1/8 GB target |
| Release rule | No model ships unless it beats the locked baseline and passes privacy, semantic, resource, reliability, license, and packaging gates |

## Objective

Build an Enhanced Dictation path that improves Fleck's English, Mandarin, mixed
English-Mandarin, code, technical writing, and personal-vocabulary dictation
without sending audio or transcript content to a server.

The feature must feel like a built-in capability rather than a model-management
tool. A user sees one installation action, one progress state, and one Enhanced
Dictation choice. Runtime names, quantizations, artifact layouts, and separate
ASR and cleanup components stay behind the product boundary.

## Success criteria

1. On a supported Mac, the user can install Enhanced Dictation with one primary
   action from onboarding or Settings.
2. A successful installation automatically selects Enhanced Dictation.
3. An interrupted download resumes; an invalid or partial installation never
   replaces the last verified bundle.
4. Apple Standard remains usable while Enhanced installs, after cancellation,
   and after any Enhanced failure.
5. Audio and transcript inference function with networking disabled after the
   bundle is installed.
6. Enhanced materially improves the locked Fleck corpus over Apple Standard
   without an unacceptable language or category regression.
7. Dictionary terms, code tokens, paths, numbers, units, and negations survive
   cleanup exactly when marked protected.
8. Cancellation inserts nothing and releases capture, ASR, and cleanup work
   within the locked latency and memory bounds.
9. The complete data pack, in-app native libraries, licenses, signing behavior,
   and packaged-app lifecycle pass on the base M1/8 GB release target.

## Non-goals

- Do not promise parity with Wispr Flow from vendor benchmarks or model cards.
- Do not require a cloud inference account, API key, subscription, or ongoing
  inference service.
- Do not expose a model picker, runtime picker, quantization picker, or separate
  ASR and cleanup downloads in the normal interface.
- Do not bundle gigabytes of model weights inside the base Fleck application.
- Do not fine-tune a model before the general candidates establish a measured
  quality and resource baseline.
- Do not raise the base app's macOS 14 deployment floor.
- Do not make the cleanup LLM a release requirement. Cleanup Off is a valid
  selected result.
- Do not let model installation or inference mutate notes, workspaces, folder
  persistence, recovery state, or agent operations.

## User experience

### Onboarding

Supported Apple-silicon Macs show one card:

> **Enhanced Dictation**
>
> More accurate dictation for technical writing, code, English, and Mandarin.
>
> Runs entirely on your Mac after a one-time download.
>
> **Install Enhanced Dictation**
>
> Download: the exact size from the verified bundle manifest

`Not Now` remains a subordinate action. Skipping installation never blocks the
rest of onboarding and leaves Apple Standard selected.

Selecting **Install Enhanced Dictation** starts the complete curated bundle.
Onboarding may continue while the app remains open. If the app quits, the
authenticated resume record allows the download to continue on the next launch.
When installation completes, Fleck selects Enhanced Dictation automatically and
shows one confirmation. It does not reopen onboarding or interrupt active note
editing.

Unsupported Macs do not show a dead install button. They show Apple Standard
with a concise compatibility explanation only where dictation compatibility is
already presented.

### Settings

Settings reuses the same presentation state and primary action:

| State | Primary presentation | Secondary action |
| --- | --- | --- |
| Not installed | **Install Enhanced Dictation** and exact download size | None |
| Downloading | Native determinate progress and downloaded/total size | Cancel |
| Verifying | **Verifying Enhanced Dictation…** | None |
| Installing | **Installing Enhanced Dictation…** | None |
| Installed | **Enhanced Dictation Installed** | Remove |
| Update available | **Update Enhanced Dictation** and exact download size | Keep current version |
| Repair required | Short failure explanation and **Try Again** | Use Apple Standard |
| Removing | **Removing Enhanced Dictation…** | None |

The normal UI never names Nemotron, Whisper, Qwen, NeMo-Speech.cpp, llama.cpp,
GGUF, MLX, Core ML, bit depth, or internal component packs. A diagnostics or
license surface may disclose exact component identity for support and legal
attribution.

### Interaction quality

- Installation actions use native SwiftUI controls and semantic system styles.
- There is no decorative animation on frequently used dictation controls.
- Progress changes communicate state rather than adding delay.
- VoiceOver receives the state, progress percentage, total size, failure, and
  available action.
- The install action cannot be triggered twice while one bundle operation is
  active.
- Model installation does not take focus from the editor or open a modal after
  the initiating consent sheet.

## Compatibility

| Capability | Minimum environment |
| --- | --- |
| Fleck base application | Existing macOS 14 floor |
| Apple Standard dictation | Existing supported Fleck environment |
| Enhanced Dictation | Apple silicon and macOS 15+ permitted |
| Candidate evaluation | Base M1 with 8 GB unified memory; macOS 14 and 15 results recorded separately where applicable |

Enhanced is a capability check, not a global package-platform change. Code that
requires macOS 15 must remain availability-gated and must not make the base
target unloadable on macOS 14.

## Product architecture

```text
microphone audio
  -> selected SpeechEngine
  -> raw ASR transcript
  -> PersonalDictionaryResolver
  -> deterministic dictionary baseline
  -> selected TranscriptCleaning mode
  -> protected-content validation
  -> baseline fallback on any unsafe cleanup
  -> existing focused/smart-capture insertion
```

The existing semantic interfaces remain the product seam:

- `SpeechEngine` owns capture start, provisional delivery, finish,
  cancellation, and resource release.
- `SpeechEngineProviding` selects Apple Standard or the installed Enhanced
  engine.
- `TranscriptDictionaryResolving` creates the deterministic baseline and
  protected forms.
- `TranscriptCleaning` transforms text without owning audio capture.
- `DictationCoordinator` orders the stages and owns safe fallback and insertion.

Model-specific code stays behind runtime adapters. `DictationCoordinator` must
not import or switch on a model family or inference framework.

## Runtime decomposition

### ASR adapter

The selected ASR runtime implements the existing `SpeechEngine` contract and
reports `.enhancedLocal`. It may emit meaningful provisional text when the
runtime has true or stable incremental state. Final-only candidates remain
eligible if accuracy and stop-to-insertion latency win the locked comparison.

The adapter owns:

- 16 kHz mono Float32 capture input or a measured runtime-specific conversion;
- bounded dictionary context when the runtime supports it;
- runtime creation, model loading, stream state, finalization, cancellation,
  and destruction;
- exact separation of provisional text from the final raw transcript;
- no network access and no runtime-managed model download.

### Cleanup adapter

The cleanup adapter implements `TranscriptCleaning` through a pinned llama.cpp
C ABI and one selected GGUF model. It owns one bounded request at a time and
uses a fixed, versioned, non-thinking prompt.

The prompt treats transcript content as untrusted data. It permits only the
selected cleanup behavior and requires verbatim preservation of protected
forms. The adapter applies deterministic decoding, a strict token ceiling,
abortable generation, and explicit model/context release.

Prompt instructions are defense in depth. The existing structural validator
and dictionary-baseline fallback remain authoritative.

### Shared inference resource coordinator

ASR and cleanup use separate runtimes but share a single resource lease:

1. Capture and ASR own the ASR lease while listening and finalizing.
2. ASR releases or parks accelerator resources after producing final text.
3. Cleanup acquires its lease only after the ASR handoff.
4. The coordinator refuses simultaneous large-model accelerator residency on
   the M1/8 GB target unless a later measured policy explicitly permits it.
5. Cancellation reaches the active stage and prevents the next stage from
   acquiring a lease.

Model residency may use a bounded warm window only after idle memory, energy,
sleep/wake, and memory-pressure measurements establish a safe value.

## Model shortlist and selection rule

The shortlist is an evaluation order, not a marketing promise or preselected
winner.

### ASR

1. **whisper.cpp control:** Whisper `small` and
   `large-v3-turbo-q5_0`. whisper.cpp offers a mature C/C++ path and Apple
   acceleration; the published `small` footprint is about 466 MiB on disk and
   about 852 MB memory before Fleck-specific measurement.
2. **Preferred streaming challenger:** NVIDIA Nemotron 3.5 ASR 0.6B through
   NeMo-Speech.cpp. The model is cache-aware streaming with configurable chunk
   sizes, punctuation, capitalization, and multilingual language conditioning.
   The current NeMo-Speech.cpp C ABI also exposes bounded per-request speech
   contexts. Recall gain, false boosting, model artifact provenance, OpenMDW
   1.1 redistribution, C ABI maturity, Metal behavior, and M1/8 GB cost remain
   admission gates.
3. **Feature challenger:** Qwen3-ASR-0.6B. Run a short admission comparison
   between an audited native Apple path before spending the full corpus. The
   owner model supports Chinese, English, additional languages and dialects,
   context, and offline/streaming inference; the owner does not provide a
   production Swift/macOS runtime.
4. **Conditional compact fallback:** SenseVoiceSmall Q8 only if leading
   candidates fail Mandarin, size, or memory gates and its weight-license
   provenance is resolved.

Do not admit Qwen3-ASR-1.7B to the default M1/8 GB matrix. Do not add every
Whisper size. Paraformer remains a focused follow-up only if otherwise viable
candidates fail personal-vocabulary recall.

### Cleanup

Benchmark the same dictionary-resolved inputs through:

1. cleanup Off;
2. Qwen3-0.6B Q8 through llama.cpp;
3. Qwen3.5-0.8B Q4_0 through llama.cpp;
4. Qwen3.5-0.8B Q8 only if Q4 fails semantic fidelity and Q8 fits the locked
   resource limits.

Qwen3.5-0.8B Q4_0 is the preferred provisional cleanup candidate. It does not
ship unless it materially improves the cleanup corpus with zero protected-term,
number, and negation failures. If neither local LLM clears that rule, Fleck
ships Enhanced ASR plus dictionary resolution with cleanup Off.

### Source snapshot

Candidate facts and current integration claims must be refreshed and pinned at
implementation time using owner sources:

- [NVIDIA Nemotron 3.5 ASR 0.6B model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
- [NVIDIA NeMo-Speech.cpp](https://github.com/NVIDIA/NeMo-Speech.cpp)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B)
- [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B)

## Personal dictionary contract

The accepted dictionary core is the safety layer, not a UI-only word list.

### Before ASR

The engine provider supplies a bounded recognition context generated from the
active personal dictionary. Adapters map it only to documented runtime
context/hotword features. The benchmark scores context enabled and disabled to
detect false substitutions, prompt leakage, and hallucinations.

### After ASR

`PersonalDictionaryResolver` deterministically produces:

- the dictionary baseline;
- protected canonical forms;
- replacement counts and ambiguity behavior.

Ambiguous aliases are not guessed. The raw transcript remains available in
dictation history for diagnosis under existing history preferences.

### Through cleanup

Cleanup receives only the dictionary baseline and the minimum protected metadata
needed for fidelity. It does not receive note history, workspace contents, or
unrelated private context.

If cleanup changes or removes a protected form, number, unit, negation, path,
identifier, or required token occurrence, the coordinator records the failure
and inserts the dictionary baseline.

## Model bundle and installation architecture

### One user-facing bundle, data-only downloadable components

The installed bundle has one product version and contains independently
identified components:

```text
EnhancedDictationBundle
  manifest
  ASR model artifacts
  cleanup model artifact, when selected
  tokenizer/configuration
  LICENSES and NOTICE
```

Selected ASR and cleanup runtime code ships inside the signed Fleck application
and changes only through an app update. The downloaded bundle is data-only: it
must not contain a dynamic library, executable, script, shader compiler, Python
package, plug-in, or other executable code. This keeps model installation on
the safe side of [App Review Guideline 2.5.2](https://developer.apple.com/app-store/review/guidelines/)
and avoids disabling Apple's
[library validation](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation).

The model manifest declares the minimum compatible Fleck runtime ABI. An app
that does not contain that ABI cannot activate the pack and must request an app
update rather than downloading code.

Each component records:

- stable component ID and capability role;
- model revision and required in-app runtime ABI;
- artifact byte count and SHA-256;
- quantization and conversion recipe;
- platform and architecture requirements;
- license identifier and required attribution;
- source and redistribution provenance;
- cleanup prompt/schema version where applicable.

The bundle manifest records the exact total download and installed size. The UI
uses those values rather than a rounded hard-coded promise.

### Installation transaction

```text
install action
  -> compatibility and capacity preflight
  -> authenticated resumable download into staging
  -> byte-count, path, manifest-signature, and SHA-256 verification
  -> data-only content and runtime-ABI compatibility assessment
  -> atomic activation of the complete bundle
  -> retain last verified bundle until activation succeeds
  -> select Enhanced Dictation
```

A bundle with one missing or invalid component is not selectable. Cancellation
removes disposable staging data but preserves authenticated resume material when
safe. Update follows the same transaction and retains the active version until
the replacement passes verification.

Removal first prevents new Enhanced captures, waits for or cancels active
inference, unloads resources, and removes only the verified model-bundle root.
It never recursively targets a broad application-support directory.

### Distribution reality and Mainland China

Local inference removes per-request compute expense. It does not eliminate the
cost and operational responsibility of distributing a large model bundle.

A reliable one-click installation must not depend on a runtime Python downloader
or an inference framework reaching Hugging Face. Fleck owns the manifest and
downloads exact immutable artifacts through a small transport layer. The
release gate must verify at least one practical Mainland China route as well as
the primary route.

The implementation may use an approved regional mirror or multiple signed
artifact origins, but all origins must serve byte-identical files covered by
the same hashes and license review. Automatic origin fallback must not weaken
TLS, redirect, signature, or checksum validation. If zero-cost third-party
hosting cannot meet reliability and regional-access gates, Fleck must budget a
CDN/object-storage path rather than claiming maintenance is free.

## Privacy and security

- Inference loads only explicit local paths from a verified active bundle.
- The runtime must not auto-download weights, tokenizers, adapters, or telemetry.
- Runtime libraries and executable code load only from the signed Fleck app
  bundle; model installation never adds executable code to Application Support.
- Pack download is the only model-related network operation.
- Audio remains memory-only and is released after capture/cancellation under
  the existing dictation contract.
- Transcript content is never sent to the model host, artifact host, analytics,
  crash reports, or licensing service.
- Manifests are trusted by a pinned signing key or exact embedded trust record;
  every artifact is checked by byte count and SHA-256 before activation.
- Archive and manifest paths reject absolute paths, traversal, symlinks,
  unexpected files, and paths outside the model root.
- Resume data remains authenticated and scoped to the expected immutable URL.
- Model/runtime diagnostic logs exclude audio samples and transcript text.
- Cleanup treats the transcript as untrusted input and cannot invoke tools,
  network access, filesystem access, or arbitrary templates.

## Evaluation sequence

### Stage 0: evaluator integrity

Before generating real candidate evidence, the CLI must reject unknown JSON
keys at every schema level. The current `JSONDecoder` accepts unknown keys even
though the checked-in schemas use exact field contracts. Benchmark evidence is
not admissible until CLI behavior matches the schema contract.

The release evidence schema must also be upgraded before benchmarking. It must
record separate ASR and cleanup component identities,
first-meaningful-partial timing,
partial-update interval and instability when streaming is claimed, final ASR
latency, cleanup latency, stop-to-insertion latency, cancellation latency,
pre-load memory, ready-idle delta, peak memory, unload duration, post-unload
delta, and installed/download bytes by component. Reports must compute
fail-closed gates for every table row below and for every locked corpus category
plus both mixed-language directions. Existing schema-v1 runs remain synthetic
or diagnostic only and cannot satisfy a release gate.

### Stage 1: ten-case runtime admission

Exercise each runtime route on English, Mandarin, mixed language, code,
dictionary context, silence/noise, cancellation, load/unload, and offline
operation. Eliminate candidates that fail artifact provenance, licensing,
repeatable lifecycle, or base resource checks.

### Stage 2: ASR-only corpus

Run cleanup Off. Score English WER, Mandarin CER, both mixed-language slices,
protected terms, numbers, negations, silence/noise, provisional stability where
claimed, final latency, memory, energy, thermal state, offline evidence,
cancellation, failure behavior, and unload recovery.

### Stage 3: cleanup-only corpus

Feed identical dictionary-resolved transcripts to cleanup Off and each cleanup
candidate. Score punctuation/capitalization improvement, fillers/repetition,
code preservation, bilingual fidelity, additions/omissions, exact protected
forms, numbers, negations, deterministic repeats, latency, cancellation, and
unload.

### Stage 4: combined confirmation

Reuse the top two admitted ASR-only results as the cleanup-Off baselines, then
run those two ASR candidates with the single best cleanup candidate. This gives
four comparable rows with only two new combined runs and confirms resource
handoff without an uninformative full Cartesian matrix.

## Proposed M1/8 GB release gates

These are Fleck product targets, not vendor claims. Freeze them in the checked-in
gate manifest before running candidates.

| Dimension | Hard gate |
| --- | --- |
| Offline/privacy | Network disabled for load and inference; zero attempted inference-time network requests |
| Semantic safety | 100% protected-term preservation; zero number changes; zero negation changes; zero non-empty silence/noise hallucinations |
| Quality | Material improvement over Apple Standard on the locked primary metric without an out-of-tolerance language/category regression |
| Streaming, when claimed | Meaningful partial by 500 ms p95 and stable updates at least every 500 ms |
| Final ASR | Warm final transcript within 1,000 ms p95 after stop on the representative short-utterance set |
| Cleanup | Within 750 ms p95 |
| Combined UX | Stop-to-insertion within 1,500 ms p95 |
| Peak memory | Whole process tree at or below 4.5 GB |
| Ready idle | Delta at or below 1.5 GB |
| Unload | Return within 256 MB of pre-load baseline within 10 seconds |
| Storage | Target at or below 2.0 GB; hard stop at 3.0 GB without a separate product decision |
| Cancellation | User control within 250 ms p95, no insertion, normal unload bound within 10 seconds |
| Reliability | At least 50 load/infer/unload cycles with no crash, hang, Metal OOM, corrupted-pack acceptance, or serious/critical thermal state |
| Supply chain | Exact model/runtime revisions, artifact/conversion/provenance/build/runtime-binary hashes, redistribution decision, attribution, removal, and rollback recorded |

The streaming clock starts when the runtime accepts the first audio sample. A
partial is meaningful only when normalized content includes an English word,
number, or Han character that survives into the final transcript; prompt text,
punctuation-only output, tags, and control tokens do not qualify. Cancellation
must additionally prove no insertion and the normal post-cancel unload bound.

If no candidate passes, the result is a failed release gate. Do not redefine a
slow or unsafe result as acceptable after observing it.

## Failure and fallback behavior

- Unsupported environment: keep Apple Standard selected and explain Enhanced
  compatibility without presenting an actionable install control.
- Insufficient disk space: do not start; report required and available space.
- Network interruption: preserve authenticated resume state and show Try Again.
- Invalid redirect, manifest, path, signature, byte count, or hash: fail closed,
  discard invalid staging data, and keep the active version.
- Runtime load failure: mark the bundle repair-required, unload it, recommend
  Apple Standard, and never insert partial output.
- ASR failure: record the existing failure surface and insert nothing.
- Cleanup timeout, cancellation, or fidelity failure: use the dictionary
  baseline unless the whole capture was cancelled.
- Memory pressure: cancel or unload Enhanced work, preserve Apple Standard, and
  never permit the system to continue toward an OOM condition.

## Implementation and coordination boundaries

The next implementation is deliberately split into evidence and product phases.

1. **Selection foundation:** strict evaluator decoding, isolated candidate
   adapter protocol, admission fixtures, reproducible benchmark commands, and
   signed selection report. This phase must not change Fleck's root package or
   production runtime.
2. **Selected runtime core:** pin the winning runtime/model pair, package its
   native adapters inside the signed Fleck app, add the data-only model manifest
   and catalog, resource leasing, and focused tests.
3. **Production integration:** inject the dictionary store/resolver, selected
   engine and cleaner, installation service, and history identity through the
   existing coordinator boundaries.
4. **Onboarding and Settings:** add the single-button experience only after the
   shared-file owner releases the integration window.
5. **Packaged validation:** install, update, resume, remove, corrupt, cancel,
   sleep/wake, memory pressure, fully offline inference, and Mainland China
   distribution-route checks.

The accepted Phase B dictionary files remain AI-owned. Before any implementation
touches `AppState.swift`, `FleckApp.swift`, `NotesPanel.swift`, `SettingsView.swift`,
`AppPreferences.swift`, `Package.swift`, `Package.resolved`, onboarding surfaces,
or folder-agent paths, stop and coordinate exact ownership with the active
folder/UI lane. This specification itself authorizes no such shared-file edit.

## Release and rollback

- Enhanced remains opt-in until the verified bundle is ready.
- A selected bundle version is immutable. Updates activate a new version rather
  than mutating the active directory in place.
- Keep the prior verified version through activation; remove it only after the
  new version loads successfully or according to a bounded retention policy.
- A bad runtime/model release is revoked by a newer signed catalog. Fleck falls
  back to the prior verified bundle when compatible, otherwise Apple Standard.
- Removing Enhanced removes only its downloaded model/data-pack artifacts. The
  signed in-app runtime remains part of Fleck, and the user's personal
  dictionary remains unless the user separately deletes it.

## Final decision rule

The provisional preferred pair is Nemotron 3.5 ASR 0.6B through
NeMo-Speech.cpp plus Qwen3.5-0.8B Q4_0 through llama.cpp. That is the first path
to try, not the release selection.

The shipped pair is the smallest admissible configuration that wins the locked
Fleck corpus and clears every privacy, semantic, latency, memory, reliability,
packaging, distribution, and license gate. whisper.cpp remains the mature ASR
fallback. Cleanup Off remains the safe cleanup fallback.
