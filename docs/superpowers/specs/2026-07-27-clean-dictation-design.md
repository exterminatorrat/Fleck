# Motes Clean Dictation Design

## Summary

Motes will add private, on-device dictation that turns natural speech into faithful, clean notes. The experience takes behavioral inspiration from Wispr Flow—hold a shortcut, speak naturally, and receive polished text—but remains focused on writing into Motes rather than typing into arbitrary applications.

Users choose between two transcription engines:

1. **Standard — Apple Speech** is the zero-download default.
2. **Enhanced Local** is one curated, removable English model that the user downloads explicitly for stronger natural-speech and technical-vocabulary recognition.

Enhanced Local uses a permissively licensed speech SDK and model artifact directly. Motes does not incorporate FluidVoice's GPLv3 application code or its private Fluid Intelligence runtime.

The first release ships two entry points backed by one dictation pipeline:

1. **Focused Dictation** inserts cleaned speech at the current cursor or replaces the current selection inside Motes.
2. **Smart Capture** works while another app is active, then routes the cleaned thought into the best matching Motes tab based on tab titles.

Both entry points must ship together. They may be implemented as separate internal milestones.

## Product Goals

- Make voice capture feel as immediate as typing.
- Remove filler words, repetitions, false starts, and spoken corrections without changing the user’s meaning.
- Keep audio, transcripts, cleanup, and routing on the user’s Mac.
- Give immediate, non-blocking feedback without stealing focus.
- Preserve completed raw transcripts locally for short-term recovery when history is enabled.
- Route only clear matches automatically and use Inbox for uncertainty.
- Keep Motes usable on its existing macOS 14 minimum.
- Let users improve transcription without making the initial Motes download hundreds of megabytes larger.
- Make model download, disk use, engine choice, repair, updates, and removal understandable and reversible.
- Preserve Motes’ lightweight, native, local-first product identity and one-time-purchase economics.

## Non-Goals

The first release will not:

- Dictate into arbitrary third-party applications.
- Use a cloud transcription or cleanup service.
- Bundle the Enhanced Local model inside the Motes application download.
- Offer a catalog of model families, sizes, or technical tuning controls.
- Copy, link, or redistribute FluidVoice GPLv3 application code.
- Use FluidVoice's privately maintained Fluid Intelligence runtime.
- Support languages other than English.
- Route to headings or sections inside a note.
- Read note bodies to make a routing decision.
- Create new topical notes automatically.
- Retain recorded audio.
- Add voice commands, snippets, a learned dictionary, or writing-style profiles.
- Design or implement the final Motes app icon. The approved floating capsule will use that icon when it exists.

System-wide text insertion may be explored as a separate future project after in-note dictation and Smart Capture prove trustworthy.

## Platform and Availability

Motes continues to support macOS 14.

### Standard — Apple Speech

Standard is selected by default and requires no Motes-managed model download.

- On macOS 26 or later, Motes uses Apple's current on-device speech framework.
- On macOS 14 and 15, Motes may use the older Apple speech API only when the recognizer explicitly supports on-device recognition and the request is configured to require it.
- Standard may be available on Apple-silicon and Intel Macs, subject to the installed English recognizer and on-device support.
- Motes never silently falls back to cloud speech recognition.

### Enhanced Local

Enhanced Local requires:

- An Apple-silicon Mac.
- macOS 14 or later.
- A user-initiated download of the one curated English model.
- Sufficient disk space for the model, compiled Core ML artifacts, and download staging.
- Microphone permission.

The initial curated candidate is the English Parakeet TDT v2 Core ML artifact used through the Apache-2.0 FluidAudio Swift SDK. The artifact is approximately 500 MB and reports approximately 800 MB peak memory use. Release is conditional on pinning an exact immutable revision and completing license, attribution, checksum, accuracy, latency, thermal, and memory review.

### Capability Matrix

| Platform | Standard | Enhanced Local | Cleanup | Smart routing |
| --- | --- | --- | --- | --- |
| macOS 26+, Apple silicon | When Apple on-device speech is available | After explicit download | Foundation Models when available | Title-only Foundation Models router when available |
| macOS 14–15, Apple silicon | Only when Apple guarantees on-device speech | After explicit download | Unavailable; preserve raw transcript | Save conservatively to Inbox |
| macOS 14+, Intel | Only when Apple guarantees on-device speech | Unavailable | Unavailable before macOS 26 support exists | Save conservatively to Inbox |

Motes checks the selected engine, model, permission, language, operating-system, and Apple Intelligence state at runtime. Controls remain visible but explain concrete recovery actions when a capability is unavailable.

## Technical Approach

The selected approach is an engine-neutral split pipeline:

1. The selected on-device speech engine streams provisional English transcription when supported and produces a final raw transcript.
2. On macOS 26 or later, Apple's on-device Foundation Model performs faithful cleanup.
3. On macOS 26 or later, a conservative on-device router chooses an active Motes tab title or Inbox.
4. On older systems, routing always chooses Inbox and cleanup preserves the raw transcript.
5. Motes commits the result through its existing editor and persistence paths.

Standard and Enhanced conform to the same bounded speech interface. Changing the speech engine does not change cleanup, routing, editor insertion, history, or feedback behavior.

No model is shipped inside the application bundle, and no per-use service is required. Enhanced Local adds network traffic only while the user explicitly downloads or updates the model.

## Component Boundaries

### Dictation Coordinator

The coordinator is the single owner of dictation lifecycle state:

`idle → listening → finalizing → cleaning → routing → saved`

It also owns cancellation and failure transitions. Only one capture may run at a time. A second activation while a capture is active is ignored rather than creating an overlapping audio or insertion task.

### Global Shortcut Registration

The global dictation shortcut registers only the user-selected chord and emits its press and release events to the coordinator. It must not install a general-purpose keystroke monitor or inspect unrelated typing.

No global dictation shortcut is enabled until the user assigns one in Dictation settings. The in-app microphone remains available immediately, and Motes explains that assigning a shortcut enables Smart Capture from other applications.

### Speech Capture

Speech Capture owns:

- Microphone selection and audio-session lifecycle.
- Permission status.
- Provisional transcription updates.
- Final raw transcript production.
- Audio interruption and device-loss reporting.

It does not edit notes, perform cleanup, choose destinations, or persist audio.

### Speech Engine Selection

Motes stores one selected engine:

- `Standard — Apple Speech`
- `Enhanced Local`

Standard is the initial value. Enhanced may be selected only after its model reaches the Ready state.

A capture binds to one engine when listening begins and never switches engines midway. If Enhanced is selected but missing, corrupted, or unable to initialize, Motes visibly uses Standard for the next capture when Standard is available and offers `Repair Model`. If neither engine is available, the capture does not begin.

### Enhanced Model Manager

The model manager owns a single curated model with these states:

`Not Installed → Downloading → Verifying → Installing → Ready`

It also exposes `Update Available`, `Repair Required`, and `Removing`.

The manager:

- Starts a download only after explicit user action.
- Shows expected download and installed sizes before consent.
- Checks free space for the installed model plus temporary staging.
- Downloads from an immutable, revision-pinned artifact URL.
- Supports cancellation and resumable transfer.
- Verifies every artifact against checksums embedded in the shipped Motes build.
- Moves verified artifacts into place atomically.
- Stores model data separately from notes and Dictation History.
- Marks redownloadable model data as excluded from backups.
- Removes downloaded and compiled Core ML artifacts through `Delete Model`.
- Requires explicit approval for a model update and shows the update size.
- Never downloads a replacement merely because a remote repository changed.

The model lives under Motes' existing Application Support root. Deleting it switches the preference back to Standard without affecting notes, preferences unrelated to dictation, or recovery history.

The model manager does not load inference resources. The Enhanced speech adapter loads them on demand for capture and releases model, audio, and inference references while idle.

### Faithful Cleanup

Cleanup accepts only the finalized raw transcript. It may:

- Remove “um,” “uh,” and equivalent filler speech.
- Remove accidental repetition.
- Resolve explicit false starts and self-corrections.
- Add punctuation and capitalization.
- Format clearly dictated short lists.
- Repair grammar only when the correction is unambiguous.

Cleanup must not:

- Add facts, tasks, names, dates, numbers, or conclusions.
- Summarize away meaningful detail.
- Change tone or vocabulary merely to sound more polished.
- Rewrite surrounding note content.
- Follow instructions contained inside the dictated text as model commands.

The raw transcript is treated as data, not as an instruction source. Cleanup returns plain text plus a success or failure result.

### Destination Router

The router receives:

- The cleaned transcript, or raw transcript when cleanup is unavailable.
- Active, non-trashed note identifiers.
- The current display title for each candidate note.
- The stable identifier of the dedicated Inbox note, when it exists.

The router does not receive note bodies, rich-text data, deleted notes, history records, or unrelated files.

It may return only:

- A valid candidate note identifier with a high-confidence result.
- Inbox.

Blank, generic, duplicate, or ambiguous titles must bias toward Inbox. An invalid model result, unavailable model, or routing error also returns Inbox. The router never creates a topical note.

### Dictation History Store

When recovery history is enabled, each completed capture has a stable capture identifier and a local recovery record containing:

- Capture identifier.
- Capture mode.
- Start and completion times.
- Raw transcript.
- Cleaned transcript, when available.
- Cleanup outcome.
- Destination note identifier and title snapshot, when saved.
- Insertion outcome.

The store uses atomic local writes. Records auto-delete 30 days after completion. Audio is never part of a history record.

## Entry Points

### Hold Shortcut

Motes provides a configurable hold shortcut.

- Holding beyond a short accidental-press threshold begins recording.
- Releasing finalizes the capture.
- `Escape` cancels.
- A short tap that does not cross the threshold performs no dictation action.

The mode is chosen when capture begins:

- If a Motes note body is the active text editor, use Focused Dictation.
- Otherwise, use Smart Capture.

The shortcut works while Motes is behind another application. It captures into Motes and does not type into, inspect, or modify the foreground application.

On macOS 14 and 15, a shortcut started outside the Motes editor still uses Smart Capture, but its destination is always Inbox because intelligent routing is unavailable.

### In-App Microphone

A microphone button is the first action in the editor toolbar, separated visually from Undo and formatting controls.

The button provides toggle behavior for accessibility and longer dictations:

- Start listening.
- Finish and clean.
- Cancel.

The existing Motes header remains unchanged.

## Focused Dictation

At capture start, Motes records the current editor selection or insertion point.

While speaking:

- Provisional words appear at that location.
- The provisional range is visually distinguishable from committed note text.
- Provisional updates are not written into normal autosave history.
- User edits outside the provisional range remain unaffected.

On release:

1. Finalize the raw transcript.
2. Persist the recovery record when history is enabled.
3. Run faithful cleanup when available.
4. Replace the provisional range with the cleaned result.
5. If cleanup is unavailable, replace it with the raw result.
6. Commit the final replacement as one editor Undo operation.
7. Update the recovery record with the result when one exists.

If the user began with selected text, the selection is replaced only when a final transcript exists. Cancellation or transcription failure restores the original selection unchanged.

## Smart Capture

Smart Capture never activates Motes or steals focus from the foreground application.

While speaking, the floating capsule shows listening feedback without displaying the transcript.

On release:

1. Finalize the raw transcript.
2. Persist the recovery record when history is enabled.
3. Run faithful cleanup when available.
4. Route against active Motes tab titles when intelligent routing is available; otherwise choose Inbox.
5. Append the result as a new paragraph to a confident match.
6. Otherwise, append it to Inbox.
7. Save through Motes’ existing local persistence path.
8. Update the recovery record with the destination and insertion outcome when one exists.

Motes creates exactly one normal tab titled `Inbox` on demand if no Inbox exists. It does not automatically pin Inbox or create additional Inbox tabs.

Cleanup unavailable but transcription successful:

- Focused Dictation inserts the raw transcript.
- Smart Capture appends the raw transcript to Inbox.
- Feedback says `Saved without cleanup`.

## Floating Capsule

The approved feedback is a compact floating capsule near the lower center of the active display.

It:

- Uses the eventual Motes app icon.
- Never takes keyboard focus.
- Does not activate Motes.
- Avoids showing transcript contents over another app.
- Uses restrained native motion and respects Reduce Motion.

Its normal state sequence is:

1. `Listening…` with a restrained live waveform.
2. `Cleaning…` with quiet progress feedback.
3. `Saved to [tab title] · Undo`.

When routing falls back, the result says `Saved to Inbox · Undo`.

The success state remains briefly, then dismisses automatically. Undo removes only the just-inserted capture when the inserted text still matches. If safe removal is no longer possible, Motes preserves the note and opens the destination rather than deleting uncertain content.

VoiceOver announces listening, cleaning, failure, and the final destination. Under Reduce Motion, spatial transitions become crossfades.

## Settings

Motes adds a dedicated `Dictation` section alongside Appearance, Editing, and Shortcuts.

It contains:

- Clean Dictation availability and reason when unavailable.
- Speech Engine choice:
  - `Standard — Apple Speech`, selected by default.
  - `Enhanced Local`, with model state and management actions.
- Enhanced model download size, installed size, hardware requirement, and attribution.
- Download, Cancel Download, Repair Model, Update Model, and Delete Model actions when applicable.
- Configurable hold shortcut.
- Microphone selection, including Automatic.
- English language status.
- Floating capsule toggle.
- `Keep recovery history for 30 days`, enabled by default.
- Clear Dictation History action with confirmation.
- Plain privacy language stating that audio is discarded and transcripts never leave the Mac.

The engine control does not expose model-family names, parameter counts, decoding settings, or alternate model sizes. Motes owns one curated Enhanced choice and may change that choice only through a reviewed application update and explicit model-update consent.

Disabling recovery history affects future captures. After a final insertion succeeds, Motes discards the raw transcript rather than retaining a record. Existing records remain until the user clears them or their 30-day expiry.

## Dictation History

`Options → Dictation History` opens the local recovery interface.

Each row shows:

- Capture time.
- Destination title or unsaved status.
- Cleaned text when available.
- Raw transcript.
- Copy Clean.
- Copy Raw.
- Open Destination.
- Delete.

The view explains that records automatically delete after 30 days. Clear History requires confirmation and provides immediate visual feedback.

Recovery history is not a second notes system. Records cannot be edited, tagged, synced, or retained indefinitely in the first release.

## Privacy and Data Handling

- Audio remains in memory only while capture or transcription requires it.
- Audio is discarded immediately after transcription finalizes or capture fails.
- No audio, transcript, note, title, history, or routing data is sent over the network.
- The only new network operation is an explicit Enhanced model download or update.
- Model download requests contain ordinary transport metadata such as IP address and HTTP headers but no dictation content.
- Routing sees titles only.
- No analytics or usage telemetry is added.
- Recovery history remains in Motes’ local application storage.
- Enhanced model files remain in Motes' local Application Support storage and are excluded from backups because they are redownloadable.
- Clear History and expiry remove the corresponding local records.

The UI must not claim that all Apple Intelligence features are available merely because the Mac uses Apple silicon. Runtime availability can also fail because Apple Intelligence is disabled, the model is downloading, the language or region is unsupported, or the OS lacks the required API.

## Failure Handling

### Permission Denied

Explain which permission is missing and provide an action that opens the relevant System Settings pane. Do not repeatedly prompt after denial.

### No Speech or Cancellation

Insert nothing, create no recovery record, and return to idle. Cancellation restores any Focused Dictation selection unchanged.

### Audio or Transcription Failure

Insert nothing. Discard partial audio. If no final raw transcript exists, do not create a misleading recoverable record.

An active capture never changes engines midway. If Enhanced fails after producing a valid final transcript, continue with that transcript. If it fails before finalization, insert nothing, discard audio, and offer Standard for the next capture when available.

### Enhanced Download or Verification Failure

Standard and ordinary note behavior remain available. Preserve resumable download state only when the transfer mechanism reports it as valid. A checksum mismatch, malformed artifact, incompatible model, or failed Core ML preparation removes staging data, marks `Repair Required`, and never loads the artifact.

### Enhanced Model Missing or Corrupted

Do not begin Enhanced capture. Visibly fall back to Standard for the next capture when Standard is available, and offer `Repair Model`. If Standard is also unavailable, explain why dictation cannot start.

### Cleanup Failure

Preserve and insert the raw transcript according to the active mode. Record the cleanup failure when history is enabled and show `Saved without cleanup`.

### Routing Failure

Use Inbox. Routing failure must never discard a completed transcript.

### Note Save Failure

When history is enabled, keep the recovery record with an unsaved insertion outcome and show an action to open Dictation History. When history is disabled, retain the raw transcript only in the current in-memory failure state and offer Copy before dismissal. Do not silently replay the insertion after relaunch because an uncertain retry could duplicate text.

### Interruption

Microphone disconnection, sleep, app termination, or an audio-session interruption ends the current capture. If a final raw transcript can be produced safely, continue normal completion and persist it only when history is enabled. Otherwise, fail without inserting partial text.

## Performance Targets

These are validation targets, not unconditional guarantees across every device:

- Show the listening capsule within 100 milliseconds after shortcut activation is accepted.
- Begin provisional feedback as soon as the selected recognizer emits usable text.
- Complete cleanup within two seconds for an ordinary short dictation on a supported Mac.
- Keep the editor responsive while speech, cleanup, routing, or history I/O occurs.
- Leave no microphone session, audio processing, or model generation active while idle.
- Avoid increasing Motes’ release size by bundling model assets.
- Release Enhanced model and inference references while idle so its approximately 800 MB peak working set does not become permanent idle memory.
- Keep download, checksum verification, Core ML preparation, and deletion off the main actor.

## Accessibility

- The microphone toolbar button has explicit Start Dictation, Finish Dictation, and Cancel Dictation labels by state.
- All controls are keyboard accessible.
- Holding a shortcut is not the only way to dictate.
- The capsule exposes concise VoiceOver status without moving focus.
- Reduce Motion removes spatial transitions.
- Status is never communicated by color alone.
- Permission and availability messages identify a concrete recovery action.

## Validation Strategy

### Automated Tests

- Coordinator state transitions: start, threshold, release, cancel, interruption, overlapping activation, and reset.
- Engine selection: Standard default, Enhanced unavailable before installation, selection after Ready, explicit deletion fallback, and no mid-capture engine switching.
- Model manager: free-space rejection, progress, cancellation, resumable transfer, checksum failure, atomic install, repair, explicit update, backup exclusion, and deletion.
- Availability matrix across macOS 14, macOS 15, macOS 26, Apple silicon, Intel, Apple on-device recognition, and Apple Intelligence states.
- Cleanup golden cases: fillers, repetition, false starts, spoken correction, negation, names, dates, numbers, punctuation, and short lists.
- Preservation checks that cleaned output does not invent or remove named entities, numbers, explicit negation, or requested tasks.
- Prompt-injection-like dictated text remains note content rather than model instructions.
- Routing cases: strong match, ambiguity, blank title, duplicate title, deleted title, invalid model output, missing Inbox, and model unavailable.
- Focused editor integration: insertion point, selection replacement, provisional rollback, rich-text preservation, and single-step Undo.
- Smart append formatting and conditional capsule Undo.
- Recovery record atomicity, 30-day purge, individual delete, clear-all confirmation, disabled-history behavior, and failed-save recovery.
- Permission and model-availability presentation.
- Reduce Motion and VoiceOver status mappings.

Apple speech, Enhanced speech, download transport, and language models are abstracted behind bounded interfaces so deterministic fakes can cover application behavior in continuous integration.

### Evaluation Corpus

Maintain a checked-in, privacy-safe English evaluation corpus written for Motes. It must include natural rambling speech, accents, domain terms, technical vocabulary, proper names, numbers, self-corrections, background noise, and ambiguous routing examples. No real user dictation belongs in the repository.

Changes to cleanup instructions, routing instructions, or supported OS model versions require rerunning the corpus. Model updates can change output even when Motes code does not, so manual release evaluation remains required.

Motes may label the optional engine `Enhanced Local` only if the pinned artifact materially improves the corpus result over Standard on representative supported Apple-silicon hardware without unacceptable finalization latency, memory, energy, or thermal behavior. Record word error rate plus preservation failures for names, numbers, negation, and requested tasks. If the candidate does not pass, Enhanced Local does not ship.

### Manual Release Gates

Test on supported Apple-silicon hardware with the target macOS release:

- Built-in microphone.
- Wired microphone.
- AirPods or another delayed-wake wireless microphone.
- First-run permission grant and denial.
- Apple Intelligence disabled.
- Standard recognition unavailable or not guaranteed on-device.
- Enhanced download consent, progress, cancellation, resume, insufficient disk, checksum failure, repair, update, and deletion.
- Enhanced model cold load, warm capture, unload, memory pressure, and corrupted local artifacts.
- Global shortcut conflicts and rapid press/release.
- Motes active, hidden, pinned, and behind another app.
- Sleep/wake and microphone disconnection.
- Long and short English dictation.
- VoiceOver and Reduce Motion.
- Cleanup and routing latency.
- Standard-versus-Enhanced evaluation corpus results.
- Dictation History copy, open, delete, purge, and clear behavior.

Also verify that Motes launches, edits, saves, and restores ordinary notes on macOS 14 and 15 with no Enhanced model installed. Verify reduced Enhanced behavior on Apple-silicon macOS 14 and 15 and Standard-only behavior on Intel where Apple provides on-device recognition.

Before release, audit and record:

- Exact FluidAudio SDK revision and Apache-2.0 notices.
- Exact model repository, immutable revision, file list, sizes, and checksums.
- Model and upstream-base license terms, attribution, commercial-distribution permission, and required notices.
- The license of every new transitive code dependency and downloaded artifact.
- Mac App Store policy compliance for downloading data-only Core ML model artifacts.

Automated tests do not substitute for real-device speech, model, permission, or latency validation.

## Delivery Boundaries

Implementation may proceed in internal milestones:

1. Engine-neutral speech boundary, Standard Apple adapter, availability, permissions, shared coordinator, and Focused Dictation.
2. Enhanced model legal/artifact audit, model manager, FluidAudio adapter, and Standard-versus-Enhanced evaluation.
3. Faithful cleanup, recovery history, and preservation corpus.
4. Global hold shortcut, floating capsule, title routing, reduced-platform Inbox behavior, and conditional Undo.
5. Accessibility, compatibility, model lifecycle, performance, memory, and real-device release validation.

The user-facing release includes both Focused Dictation and Smart Capture. A partially completed internal milestone is not presented as the finished Clean Dictation feature.

The earlier Apple-only implementation plan at `docs/superpowers/plans/2026-07-27-clean-dictation.md` is superseded by this revision and must not be executed until a replacement plan is approved.

## References

- [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels)
- [Apple: Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Apple Speech framework](https://developer.apple.com/documentation/speech/)
- [Apple: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple Intelligence device and language requirements](https://support.apple.com/en-asia/121115)
- [FluidVoice](https://github.com/altic-dev/FluidVoice)
- [FluidAudio](https://github.com/FluidInference/FluidAudio)
- [Parakeet TDT v2 Core ML candidate](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
- [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Wispr Flow features](https://try.wisprflow.ai/)
- [Wispr Flow data controls](https://wisprflow.ai/data-controls)
