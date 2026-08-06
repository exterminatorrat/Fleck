# Fleck Local AI Dictation and Personal Dictionary Design

**Status:** Approved
**Date:** 2026-08-06

## 1. Objective and supersession

Fleck will provide private, entirely local dictation for English, Mandarin, and
mixed English-Mandarin developer writing. Inference, speech recognition,
cleanup, dictionary resolution, validation, routing, and persistence stay on
the Mac. The product requires no API keys, accounts, per-minute cloud costs,
cloud transcription, or cloud cleanup. A user-initiated model download is a
distribution operation, not an inference service.

This design supersedes only the obsolete speech/model/cleanup/dictionary parts
of the [2026-07-27 Clean Dictation design](2026-07-27-clean-dictation-design.md):

- The English-only Enhanced model is replaced by a benchmark-gated,
  English-Mandarin design with no production model selected yet.
- Cleanup is no longer available only when Apple Foundation Models is
  available. `FoundationModelDictation` remains a bounded local adapter and
  migration reference, but it cannot define the global cleanup baseline.
- A global personal dictionary is now a v1 product requirement.

Focused Dictation, Smart Capture, the existing `SpeechEngine` /
`SpeechEngineProviding` lifecycle, history and recovery behavior, dictionary-
baseline fallback, ASR-raw recovery, editor insertion, title-only routing, and
local persistence remain in force unless this document explicitly changes
their model context or cleanup contract. The real Fleck editor and current
`DictationCoordinator` remain the runtime seams; this document does not invent
replacement signatures.

## 2. Approved product and platform contract

### Platform and quality bar

- Enhanced requires Apple silicon. Apple Standard remains the zero-download
  engine and remains the compatibility path on Intel Macs where Apple's
  on-device recognition is supported.
- The launch quality bar covers English, Mandarin, and mixed English-Mandarin
  speech. It must be measured rather than inferred from a model's language
  list.
- Optimize for technical prose, prompts, commit messages, commands, paths,
  filenames, acronyms, proper nouns, and correctly cased identifiers such as
  `camelCase`, `PascalCase`, and `snake_case`.
- Full source-code-by-voice, cursor commands, editor navigation commands, and
  spoken indentation are outside this design. Ordinary text insertion into
  Fleck remains the product surface.
- M1 with 8 GB of memory is a provisional benchmark target. It is required for
  representative evidence, not a release qualification or performance claim.

### Distribution and resource contract

- Enhanced has one optional combined English-Mandarin download and one
  consent flow. The approximate target envelope is 1–3 GB for the combined
  pack, pending model and runtime benchmarks; it is not a committed size.
  The base Fleck app remains small and does not bundle the pack.
- The pack is removable, versioned, checksum-verified, stored separately from
  notes and history, and unloaded when dictation is idle. A model that is
  installed is not necessarily resident in memory.
- Audio is transient in memory only and is never retained in files, notes,
  history, model storage, analytics, or diagnostic logs.
- Enhanced inference must be explicitly offline. Model-host bandwidth during
  an authorized download is not inference, and no network is permitted as an
  unannounced recovery path.

## 3. Alternatives and decision

| Alternative | Strengths | Risks and tradeoffs | Decision |
| --- | --- | --- | --- |
| Whisper plus deterministic formatting | One well-understood multilingual ASR family with a small, auditable cleanup surface. | Deterministic rules alone may not handle mixed-language recognition, spoken self-corrections, technical casing, and fragmented prose well enough. | Not the complete product architecture; retain as a benchmark arm. |
| Modular ASR plus separate local cleanup | ASR, dictionary/context, cleanup, validation, and fallback can be measured and replaced independently; the same contract can cover all supported languages. | More interfaces, artifacts, cold-load work, and validation than a single model. | **Selected**, gated by representative benchmarks and license review. |
| Language-routed dual ASR | Specialized English and Mandarin recognizers may offer strong single-language quality. | Language detection can fail at boundaries; mixed speech becomes a routing problem; two model families increase download, memory, thermal, and maintenance cost. | Not selected for v1. |

The approved direction is **benchmark-gated modular ASR plus local cleanup,
distributed as one combined English-Mandarin Enhanced pack**. This is an
architecture decision, not a model selection. The production ASR and cleanup
models remain unselected and are not release-ready.

The evaluation shortlist is:

- [Whisper](https://github.com/openai/whisper) and
  [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
- [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) or
  [Paraformer through FunASR](https://github.com/modelscope/FunASR).
- [Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), or a later
  license-compatible candidate that passes the same gate.

The separate local-cleanup shortlist is also intentionally non-selecting:
evaluate a small multilingual instruction-tuned local model/runtime suitable
for native Apple-silicon deployment, with [Qwen3.5](https://github.com/QwenLM/Qwen3.5)
plus [llama.cpp](https://github.com/ggml-org/llama.cpp), or a later
license-compatible equivalent, as benchmark candidates. The same commercial
redistribution, native feasibility, quality, and M1/8 GB gates apply. Neither
Qwen3.5 nor llama.cpp is selected or approved by this design.

These links identify candidates and primary project/model sources; they do not
approve a model, runtime, conversion, quantization, or transitive dependency.
Every candidate requires a commercial redistribution and attribution review,
including model weights, runtime code, tokenizer/data files, and notices, plus
a native Apple-silicon feasibility review. Vendor benchmarks may narrow the
shortlist but never substitute for Fleck's measured corpus and device gate.
No unsupported claims about any third-party dictation product or stack are part
of this design.

## 4. Pipeline and bounded context

The production pipeline is:

```text
transient audio
  -> local ASR
  -> ASR raw
  -> dictionary resolution
  -> dictionary baseline
  -> optional local cleanup
  -> optional cleaned result
  -> validation
  -> insertion/persistence
```

For Smart Capture, the existing title-only destination decision remains part
of insertion/persistence. It receives candidate note IDs and display titles,
not note bodies. Focused Dictation uses the existing editor transaction and
selection behavior.

### Transcript artifact contract

Each final capture has three distinct transcript artifacts:

1. **ASR raw:** the exact final recognizer output before Fleck dictionary
   mutation.
2. **Dictionary baseline:** ASR raw after only explicit, deterministic,
   unambiguous dictionary aliases with safe token boundaries. This is the
   protected baseline.
3. **Cleaned result:** an optional Light or Polished transformation of the
   dictionary baseline.

Off inserts the dictionary baseline. Light or Polished inserts the cleaned
result only after successful validation. Cleanup being unavailable, timing
out, rejecting its input, producing an empty or suspicious result, failing
validation, losing protected terms, or making an unreasonable transformation
inserts the dictionary baseline, not ASR raw. If dictionary resolution fails
before producing a valid baseline, Fleck inserts ASR raw and visibly records
that dictionary resolution was skipped. ASR raw remains the forensic and
recovery source; it is not the ordinary post-dictionary fallback. `Revert
Cleanup` restores the dictionary baseline, preserving approved dictionary
corrections while removing generative cleanup.

The context passed to an ASR or cleanup operation is bounded to:

- preferred language or language mode;
- note title, and for Smart Capture the small set of candidate titles;
- a small cursor-adjacent text window only when Focused Dictation needs it;
- relevant enabled dictionary entries;
- ASR raw, and the dictionary baseline once resolution succeeds; and
- cleanup strength (`Off`, `Light`, or `Polished`).

The pipeline never reads unrelated note bodies, full workspace content,
history unrelated to the active capture, or arbitrary files. Transcript and
context are data, not instructions. Dictated text that contains an instruction
must remain text and must not gain authority over the cleanup or routing
system. Fleck emits no content telemetry. Local operational logs may record
non-content state such as phase, duration, selected engine kind, model state,
and failure category, but not audio, transcript text, note bodies, dictionary
contents, or routing inputs.

### Existing seams to preserve

- `AppleSpeechCapture` remains the zero-download Standard adapter. It must
  continue to require Apple's on-device capability rather than silently using a
  network recognizer. Apple's [on-device recognizer capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
  and [requires-on-device request setting](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
  are the relevant platform checks.
- `SpeechEngine` and `SpeechEngineProviding` continue to own capture binding,
  provisional updates, final text, cancellation, and resource release.
  `DictationCoordinator` continues to own the single-capture lifecycle,
  `Focused Dictation` versus `Smart Capture`, history writes, cleanup and
  routing phases, insertion, compensation, undo, and recovery.
- `EnhancedSpeechCapture` and `EnhancedModelManager` remain the shape of the
  candidate model adapter and lifecycle manager, but their current
  Parakeet/FluidAudio implementation is release-disabled candidate code, not
  the selected production model. The current pinned artifact and its roughly
  443 MiB manifest are plumbing evidence, not the new combined-pack size or a
  release recommendation.
- `FoundationModelDictation` remains useful for its bounded local cleanup and
  title-only routing behavior and its existing tests. It is not the global
  baseline because OS, Apple Intelligence, language, and model readiness can
  make it unavailable.

## 5. Local cleanup contract

Cleanup is a local, bounded transformation after ASR and dictionary
resolution. It operates on the protected dictionary baseline and must be
independently switchable from the ASR engine.

| Strength | Allowed behavior |
| --- | --- |
| **Off** | Insert the dictionary baseline: ASR output plus dictionary-assisted recognition and safe, explicit, unambiguous aliases only. No generative rewrite. |
| **Light** (default) | Add punctuation and capitalization; remove fillers, accidental repetition, and unambiguous self-corrections; preserve technical casing, filenames, acronyms, identifiers, names, numbers, and explicit negation. |
| **Polished** | Improve fragmented structure when the meaning remains unchanged, while retaining all Light protections and never rewriting surrounding note content. |

No strength may add facts, dates, names, numbers, tasks, conclusions, or
unstated intent. Cleanup cannot summarize, obey instructions in the transcript,
or rewrite text already in the note. A successful result must preserve the
protected terms and meaning that validation identifies for that capture.

Light or Polished inserts a cleaned result only after successful validation.
Cleanup being unavailable, timing out, rejecting its input, producing an empty
or suspicious result, failing validation, losing a protected term, or making
an unreasonable transformation inserts the dictionary baseline. It does not
fall back to ASR raw merely because cleanup failed. If dictionary resolution
fails before producing a valid baseline, the sole ordinary insertion exception
is ASR raw with a visible record that dictionary resolution was skipped.
`Revert Cleanup` restores the dictionary baseline, not ASR raw, so approved
dictionary corrections survive removal of generative cleanup.

During an active capture, ASR raw, the dictionary baseline, and an optional
cleaned result may exist transiently in memory; retention and history-disabled
revert limits are defined in Section 9. ASR raw remains the forensic and
recovery source, not the ordinary post-dictionary fallback. Validation may use
token, number, identifier, protected-term, and structural checks, but a
simplistic edit-distance or string-distance threshold must never be presented
as proof of semantic fidelity. The validator must fail closed and preserve the
dictionary baseline for insertion.

## 6. Personal Dictionary v1

The personal dictionary is global to Fleck and device-local. It is not attached
to a note and is not stored in `AppPreferences`.

Each entry has:

- a stable ID;
- preferred spelling and casing;
- optional spoken aliases or known misrecognitions;
- language or locale;
- priority/star state;
- enabled state;
- manual or suggested origin; and
- local usage metadata such as bounded counts and timestamps.

The dedicated local store feeds relevant enabled entries to whichever ASR
adapter supports prompts, hotwords, contextual phrases, or a custom language
API. Apple Standard uses Apple's contextual vocabulary APIs where supported:
[short `contextualStrings`](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)
are available to `DictationTranscriber`, and Apple's older request path exposes
contextual phrases and custom language-model APIs where the installed OS
supports them. The implementation must respect platform limits and must not
pretend every engine accepts arbitrary dictionaries.

Dictionary resolution is conservative:

- Deterministic replacement is allowed only for an explicit, unambiguous
  spoken alias or known misrecognition with safe token boundaries.
- Ambiguous matches remain model-guided, then pass through the same protected
  term and meaning validation as other cleanup.
- Preferred dictionary forms are protected through cleanup so Light or
  Polished output cannot silently change their spelling or casing.
- Fleck observes only edits to tokens recently produced by dictation on this
  device. Repeated corrections may create a pending suggestion, but no
  suggestion becomes an enabled dictionary entry without explicit user
  approval.

Entries support keyboard- and VoiceOver-accessible CRUD, JSON import/export,
CSV import/export, enable/disable, priority/star changes, and approval or
dismissal of suggestions. The store is versioned and atomic. It records no
audio and does not become a transcript archive.

v1 explicitly excludes sync, team dictionaries, per-note dictionaries,
snippets, writing-style profiles, and automatic acceptance of suggestions.

## 7. Model management and failure behavior

Enhanced model management requires explicit consent that states expected
download and installed storage, Apple-silicon requirements, privacy behavior,
and the removable nature of the pack. Artifacts are immutable and versioned.
The manager must:

- check architecture and free disk space before download;
- verify the allowlisted artifact, exact file list, byte counts, and checksums;
- install through a staging directory and an atomic commit;
- cancel and resume where the transport can safely provide resumable state;
- expose repair, update, and removal with visible progress/state;
- keep model files separate from notes, dictionary data, and history; and
- unload inference resources, audio buffers, and model references after capture
  or cancellation and while idle.

Enhanced availability is preflighted before capture. If Enhanced is unavailable
and Standard is available, the visible result says that Standard is being used
and explains why; it does not imply that Enhanced ran. An active capture binds
to one engine and does not switch engines midway. If Standard is unavailable,
Fleck explains the permission, on-device, architecture, or model state that
blocks capture.

If a model load or inference fails after no final transcript exists, Fleck
releases resources, marks repair when appropriate, and offers Standard for the
next capture. If valid ASR raw exists and dictionary resolution succeeds,
cleanup failure returns the successful dictionary baseline for insertion. If
dictionary resolution itself fails before producing a valid baseline, Fleck
inserts ASR raw and visibly records that dictionary resolution was skipped.
Fleck must never claim that already-consumed audio can be retranscribed unless
the implementation explicitly buffers that audio transiently and tells the
user that such buffering is in use. Network inference is never a silent
fallback.

## 8. Evaluation gate

The evaluation corpus is privacy-safe, checked in, and versioned. It includes:

- English prose and Mandarin prose;
- mixed English-Mandarin speech;
- developer prompts and commit messages;
- `camelCase`, `PascalCase`, and `snake_case`;
- commands, paths, and filenames;
- acronyms, proper nouns, and dictionary terms;
- accents, pauses, repetitions, and spoken corrections; and
- representative background noise and microphone conditions.

For every candidate and relevant Standard baseline, record:

- English WER and Mandarin CER;
- mixed-language accuracy and protected-term accuracy;
- cleanup factual and meaning-preservation failures;
- cold-load, warm-capture, and end-to-end latency;
- peak memory, idle memory, and model unload behavior;
- thermal and energy behavior;
- download size and installed size; and
- failure, cancellation, and offline behavior.

The gate requires measured evidence on representative Apple-silicon hardware,
including M1 with 8 GB of memory. The evidence must identify OS, hardware,
build, model revision, corpus version, and cold/warm conditions. Vendor
benchmarks are shortlist evidence only. Before reviewing candidate outputs,
the release owner must predeclare material-improvement, preservation, latency,
memory, thermal, and size criteria. No model becomes selected, release-ready,
commercially cleared, or M1-qualified without passing this gate.

## 9. Persistence, privacy, and compatibility

- Dictionary data uses a dedicated versioned atomic store under Fleck's
  existing Application Support conventions. It is separate from note bodies,
  Markdown/RTF sidecars, Dictation History, and model repositories.
- Redownloadable model artifacts are excluded from backup where appropriate;
  dictionary and note/history backup decisions remain separate and explicit.
- Existing notes, Markdown and RTF behavior, preference decoding and
  compatibility, editor undo, history retention, Focused Dictation,
  Smart Capture, title-only routing, and local-first operation remain intact.

### Transcript artifact retention and revert

During an active capture, ASR raw, the dictionary baseline, and an optional
cleaned result may exist transiently in memory. Audio remains transient and is
never persisted in either history mode.

When Dictation History is enabled, evolve the existing local record
compatibly to persist ASR raw, the dictionary baseline, the cleaned result when
one was produced, the inserted artifact and outcome, and existing metadata
under the existing 30-day retention and purge contract. Decoding must remain
backward-compatible with old history records that lack the dictionary-baseline
field; the exact migration and record signature belong in the later
implementation plan.

When Dictation History is disabled, persist none of these transcript artifacts
to disk or history. History-disabled `Revert Cleanup` is immediate and
in-memory only: retain the dictionary baseline plus the existing safe
insertion/undo identity only while the most recent cleaned insertion remains
safely replaceable. Clear that state on the next successful capture, when the
inserted range or text no longer matches, when the target note is deleted, or
on process exit, whichever occurs first.

With history enabled, later recovery or revert may use the retained record only
while it remains within existing retention and the insertion can still be
changed safely. Otherwise preserve note content and offer copy/open behavior
rather than destructive replacement.

- No per-minute inference cost does not mean zero maintenance cost. Fleck must
  budget for model-host bandwidth, artifact storage, license/compliance work,
  QA, support, conversion and checksum work, and future model/runtime updates.

## 10. Ownership and integration boundary

### AI-owned files and modules

The AI/dictation work owns:

- `AppleSpeechCapture.swift`
- `DictationAvailability.swift`
- `DictationCoordinator.swift`
- `DictationInterfaces.swift`
- `DictationModelCapability.swift`
- `DictationSettingsPresentation.swift`
- `EnhancedModelManager.swift`
- `EnhancedSpeechCapture.swift`
- `FoundationModelDictation.swift`
- corresponding dictation/model tests, evaluation fixtures, and new
  dictionary-core/evaluation files.

### Shared files requiring a separate coordinated task

These files are not edited during design or evaluation:

- `AppState.swift`
- `FleckApp.swift`
- `NotesPanel.swift`
- `SettingsView.swift`
- `AppPreferences.swift`
- `Package.swift`
- `Package.resolved`

Likely future integration needs are deliberately narrow:

- `FleckApp.swift`: inject the selected dictionary store, model pack, and
  cleanup/ASR services through the existing runtime construction.
- `SettingsView.swift`: add download, cleanup-strength, dictionary CRUD,
  import/export, and suggestion approval UI.
- `AppPreferences.swift`: store engine and cleanup-strength preferences only;
  never dictionary entries.
- `NotesPanel.swift`: provide bounded cursor-adjacent context and recent
  correction presentation through the real editor.
- `AppState.swift`: expose presentation or persistence hooks only if the
  accepted integration contract requires them.
- `Package.swift` and `Package.resolved`: change only after a benchmark and
  license-approved runtime/model choice owns the dependency change.

No shared-file edits occur during evaluation. A later shared integration task
must preserve concurrent roadmap work and verify the real Fleck runtime rather
than introducing a duplicate editor or simulated capture surface.

## 11. Accessibility and user-visible states

The UI clearly distinguishes Standard and Enhanced and labels storage,
download, verification, cleanup strength, repair, fallback, model removal,
and privacy. A disabled or unavailable capability is never shown as ready.
Fallback copy names the engine actually used, the inserted artifact, and
whether dictionary resolution was skipped. The dictionary baseline is the
`Revert Cleanup` target. ASR raw remains available only as the forensic or
recovery source permitted by the current retention mode; the UI never implies
that an unavailable artifact exists.

Dictionary CRUD, import/export, entry enablement, priority/star changes,
suggestion approval, and dismissal are fully keyboard accessible and expose
meaningful VoiceOver labels, values, and state. Progress and errors are not
communicated by color alone. Reduce Motion and Full Keyboard Access preserve
the same information and action order. Focused Dictation keeps the existing
provisional-range, cancellation, undo, and selection behavior; Smart Capture
keeps the existing non-stealing-focus status and recovery behavior.

## 12. Phasing

1. **Phase A — Evaluation harness and corpus contracts.** Define corpus format,
   protected-term cases, metric calculations, offline assertions, and the
   benchmark report before selecting a model.
2. **Phase B — Dictionary core and Apple contextual vocabulary.** Define the
   versioned store, deterministic alias rules, protected terms, correction
   suggestion contract, and Apple Standard contextual-vocabulary adapter.
3. **Phase C — ASR and cleanup evaluation.** Benchmark the shortlist against
   Standard and the corpus; select ASR and cleanup only after quality,
   resource, native Apple-silicon, and commercial-license review.
4. **Phase D — Model pack, manager, and AI-owned pipeline.** Implement the
   one-pack consent and lifecycle, selected adapters, validation, cleanup
   strengths, dictionary feeds, dictionary-baseline fallback with the explicit
   ASR-raw dictionary-resolution failure path, and owned tests.
5. **Phase E — Coordinated shared UX/runtime integration and packaged QA.**
   Inject the accepted services, add Settings/NotesPanel/AppState wiring only
   through a separate coordinated task, and validate the packaged app offline.

Dictionary contracts occur in Phase B before model implementation because both
ASR and cleanup consume them. Phases A–D do not edit shared integration files.

## 13. Verification, acceptance, and non-goals

### Future verification

The accepted implementation will require focused dictation, dictionary,
cleanup, artifact-retention/revert, model-manager, persistence,
backward-compatible history decoding, accessibility, and failure tests; the
full Swift suite; `Scripts/validate-macos.sh`; and an integrity check that
`Package.resolved` matches the approved dependency state. Model checksums,
immutable revisions, notices, and commercial license decisions are verified
from the actual artifacts. Packaged QA runs offline on a disposable QA tab to
the right of the protected leftmost personal tab; the leftmost personal tab is
never used for testing.

### Measurable acceptance criteria

- With approved artifacts installed and networking unavailable, Enhanced
  performs English, Mandarin, and mixed-language captures locally without a
  network inference request; Standard never uses a network-only recognizer.
- The benchmark report contains the required WER/CER, mixed-language,
  protected-term, cleanup-preservation, latency, memory, thermal, download,
  installed-size, and M1/8 GB evidence, with the predeclared gate decision.
- Dictionary entries survive relaunch through atomic storage; JSON/CSV
  round-trips preserve fields; explicit aliases replace deterministically;
  ambiguous matches remain reviewable; and repeated local corrections may
  create a pending suggestion, but no suggestion becomes an enabled dictionary
  entry without explicit user approval.
- Focused and Smart Capture tests distinguish ASR raw as the exact final
  recognizer output before dictionary mutation, the dictionary baseline as
  only explicit deterministic unambiguous aliases with safe token boundaries,
  and the optional cleaned result as a Light or Polished transformation of
  that baseline. Off inserts the dictionary baseline; successful Light or
  Polished cleanup inserts the cleaned result; unavailable, timed-out,
  rejected, empty or suspicious, validation-failed, protected-term-losing, or
  unreasonable cleanup inserts the dictionary baseline. A dictionary
  resolution failure before a valid baseline inserts ASR raw and visibly
  records that dictionary resolution was skipped. `Revert Cleanup` restores
  the dictionary baseline, not ASR raw, without losing approved dictionary
  corrections.
- During active capture the three transcript artifacts may exist only
  transiently in memory. With Dictation History enabled, the local record
  persists ASR raw, the dictionary baseline, the cleaned result when produced,
  the inserted artifact/outcome, and existing metadata under the existing
  30-day retention and purge contract. With history disabled, none of these
  artifacts is persisted to disk/history; in-memory Revert Cleanup retains the
  dictionary baseline and existing safe insertion/undo identity only while the
  cleaned insertion is safely replaceable, and clears on the next successful
  capture, inserted range/text mismatch, target-note deletion, or process exit,
  whichever occurs first. History-enabled recovery/revert is allowed only
  within existing retention and when safe; otherwise note content is preserved
  and copy/open behavior is offered. Old history records lacking the
  dictionary-baseline field decode compatibly, and audio is never persisted.
- Model consent, capacity checks, checksum verification, atomic install,
  cancellation/resume where supported, repair/update/removal, preflight
  fallback, and idle unload are visible and testable. No inference path can
  silently use the network.
- Notes, Markdown/RTF, preference compatibility, undo, history retention,
  routing, privacy boundaries, keyboard behavior, VoiceOver, Reduce Motion,
  and local-first operation remain regression-free in the packaged app.

This design does not include:

- cloud inference, cloud transcription, cloud cleanup, accounts, or API keys;
- dictation into third-party applications;
- full voice coding, cursor commands, or spoken indentation;
- unsupported broad language claims beyond the measured English, Mandarin,
  and mixed-language launch bar;
- a model catalog, model-family selector, or tuning UI;
- sync, team dictionaries, per-note dictionaries, snippets, or profiles;
- audio retention;
- analytics or content telemetry; or
- shared-file edits during design and evaluation.

## References

- [Apple Speech framework](https://developer.apple.com/documentation/speech/)
- [Apple `SFSpeechRecognizer` on-device capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [Apple `requiresOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [Apple `DictationTranscriber`](https://developer.apple.com/documentation/speech/dictationtranscriber)
- [Apple Speech `contextualStrings`](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)
- [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Apple `SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [OpenAI Whisper](https://github.com/openai/whisper)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [FunAudioLLM SenseVoice](https://github.com/FunAudioLLM/SenseVoice)
- [FunASR and Paraformer](https://github.com/modelscope/FunASR)
- [Qwen3-ASR model card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B)
- [Qwen3.5](https://github.com/QwenLM/Qwen3.5)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [FluidAudio candidate runtime](https://github.com/FluidInference/FluidAudio)
