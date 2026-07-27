# Motes Clean Dictation Design

## Summary

Motes will add private, on-device dictation that turns natural speech into faithful, clean notes. The experience takes behavioral inspiration from Wispr Flow—hold a shortcut, speak naturally, and receive polished text—but remains focused on writing into Motes rather than typing into arbitrary applications.

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
- Preserve Motes’ lightweight, native, local-first product identity and one-time-purchase economics.

## Non-Goals

The first release will not:

- Dictate into arbitrary third-party applications.
- Use a cloud transcription or cleanup service.
- Bundle an independent speech or language model.
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

The complete Clean Dictation experience requires macOS 26 or later and:

- A compatible Apple-silicon Mac.
- A macOS version that exposes Apple’s SpeechAnalyzer and Foundation Models frameworks to third-party applications.
- Apple Intelligence enabled and its on-device model ready.
- A supported English language configuration.
- Microphone and speech-recognition permission.

Motes must check model and recognizer availability at runtime. Clean Dictation controls remain visible but explain why the feature is unavailable when the device, operating system, model, language, or permission does not qualify.

On older supported macOS releases, Motes remains fully usable as a notes app. Basic raw dictation may be offered only when Apple reports that speech recognition is available entirely on device. Motes must not silently fall back to cloud speech recognition.

## Technical Approach

The selected approach is an Apple-native split pipeline:

1. Apple’s on-device speech framework streams provisional English transcription and produces a final raw transcript.
2. Apple’s on-device Foundation Model performs faithful cleanup.
3. A conservative on-device router chooses an active Motes tab title or Inbox.
4. Motes commits the result through its existing editor and persistence paths.

No model is shipped inside the app, and no per-use service is required.

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
3. Run faithful cleanup.
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
3. Run faithful cleanup.
4. Route against active Motes tab titles.
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
- Configurable hold shortcut.
- Microphone selection, including Automatic.
- English language status.
- Floating capsule toggle.
- `Keep recovery history for 30 days`, enabled by default.
- Clear Dictation History action with confirmation.
- Plain privacy language stating that audio is discarded and transcripts never leave the Mac.

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
- No dictation data is sent over the network.
- Routing sees titles only.
- No analytics or usage telemetry is added.
- Recovery history remains in Motes’ local application storage.
- Clear History and expiry remove the corresponding local records.

The UI must not claim that all Apple Intelligence features are available merely because the Mac uses Apple silicon. Runtime availability can also fail because Apple Intelligence is disabled, the model is downloading, the language or region is unsupported, or the OS lacks the required API.

## Failure Handling

### Permission Denied

Explain which permission is missing and provide an action that opens the relevant System Settings pane. Do not repeatedly prompt after denial.

### No Speech or Cancellation

Insert nothing, create no recovery record, and return to idle. Cancellation restores any Focused Dictation selection unchanged.

### Audio or Transcription Failure

Insert nothing. Discard partial audio. If no final raw transcript exists, do not create a misleading recoverable record.

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
- Begin provisional feedback as soon as Apple’s recognizer emits usable text.
- Complete cleanup within two seconds for an ordinary short dictation on a supported Mac.
- Keep the editor responsive while speech, cleanup, routing, or history I/O occurs.
- Leave no microphone session, audio processing, or model generation active while idle.
- Avoid increasing Motes’ release size by bundling model assets.

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
- Cleanup golden cases: fillers, repetition, false starts, spoken correction, negation, names, dates, numbers, punctuation, and short lists.
- Preservation checks that cleaned output does not invent or remove named entities, numbers, explicit negation, or requested tasks.
- Prompt-injection-like dictated text remains note content rather than model instructions.
- Routing cases: strong match, ambiguity, blank title, duplicate title, deleted title, invalid model output, missing Inbox, and model unavailable.
- Focused editor integration: insertion point, selection replacement, provisional rollback, rich-text preservation, and single-step Undo.
- Smart append formatting and conditional capsule Undo.
- Recovery record atomicity, 30-day purge, individual delete, clear-all confirmation, disabled-history behavior, and failed-save recovery.
- Permission and model-availability presentation.
- Reduce Motion and VoiceOver status mappings.

Apple speech and language models are abstracted behind bounded interfaces so deterministic fakes can cover application behavior in continuous integration.

### Evaluation Corpus

Maintain a checked-in, privacy-safe English evaluation corpus written for Motes. It must include natural rambling speech, domain terms, self-corrections, and ambiguous routing examples. No real user dictation belongs in the repository.

Changes to cleanup instructions, routing instructions, or supported OS model versions require rerunning the corpus. Model updates can change output even when Motes code does not, so manual release evaluation remains required.

### Manual Release Gates

Test on supported Apple-silicon hardware with the target macOS release:

- Built-in microphone.
- Wired microphone.
- AirPods or another delayed-wake wireless microphone.
- First-run permission grant and denial.
- Apple Intelligence disabled.
- Model downloading or not ready.
- Global shortcut conflicts and rapid press/release.
- Motes active, hidden, pinned, and behind another app.
- Sleep/wake and microphone disconnection.
- Long and short English dictation.
- VoiceOver and Reduce Motion.
- Cleanup and routing latency.
- Dictation History copy, open, delete, purge, and clear behavior.

Also verify that Motes launches, edits, saves, and restores ordinary notes on macOS 14 and 15 without Clean Dictation.

Automated tests do not substitute for real-device speech, model, permission, or latency validation.

## Delivery Boundaries

Implementation may proceed in internal milestones:

1. Availability, permissions, shared coordinator, speech abstraction, and Focused Dictation.
2. Faithful cleanup, recovery history, and evaluation corpus.
3. Global hold shortcut, floating capsule, title routing, and Inbox.
4. Accessibility, compatibility, performance, and real-device release validation.

The user-facing release includes both Focused Dictation and Smart Capture. A partially completed internal milestone is not presented as the finished Clean Dictation feature.

## References

- [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels)
- [Apple: Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Apple Speech framework](https://developer.apple.com/documentation/speech/)
- [Apple: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple Intelligence device and language requirements](https://support.apple.com/en-asia/121115)
- [Wispr Flow features](https://try.wisprflow.ai/)
- [Wispr Flow data controls](https://wisprflow.ai/data-controls)
