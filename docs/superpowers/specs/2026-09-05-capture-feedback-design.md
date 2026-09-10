# Capture and Feedback Design

**Scope:** Phase 1 of the dictation reliability program. The user authorized planning followed by beginning this phase on 2026-09-05. Start with packet 1A; do not mistake that packet for the complete phase.

## Problem

EnhancedSpeechCapture currently awaits inference load before opening audio. DictationCoordinator publishes arming immediately, but the capsule renders its idle identity mark in arming. On 8 GB machines, short retention and the Gemma handoff can repeatedly expose this cold-start path. These are source findings; the user's exact MacBook delay and missed words still require device evidence.

## Chosen approach and alternatives

Use explicit startup feedback, followed by bounded audio-first startup and a separate recording-ready signal. Reuse the existing audio capture, lifecycle identity, coordinator, and pill.

Extending retention alone cannot protect cold-start speech and can increase memory pressure. Always-on microphone pre-roll exceeds scope and privacy expectations. Replacing the recognizer or relaxing cleanup validation does not repair this capture boundary.

## State contract

| State | Audio meaning | User feedback |
| --- | --- | --- |
| Idle | No active user capture | Existing compact Fleck mark |
| Starting | User request accepted; audio readiness not established | Visible “Starting” and accessible “Starting dictation”; no invented waveform |
| Recording, model loading | Audio buffers are being retained; inference may be unavailable temporarily | Live microphone-driven waveform once a real readiness signal exists |
| Recording, model ready | Audio capture and inference ready | Existing listening presentation |
| Finishing | Audio stopped; captured buffer is being processed | Existing processing feedback |
| Cancelled | No further audio, inference result, or insertion may commit | Existing cancellation return behavior |
| Failed | Capture cannot continue | Existing failure/recovery presentation with honest reason |

Packet 1A changes only Starting presentation. Recording-while-loading requires 1B/1C and must not be simulated by renaming arming to listening.

## Capture ownership

The active capture owns the audio device, buffer, inference loading task, and session generation. Permission and verified model eligibility are checked before microphone activation. Audio begins before an awaited model load. Every cancellation/failure stops audio synchronously before awaiting inference teardown. No stale callback may update a newer capture.

Stop during loading must stop the audio at the user's stop boundary and retain only that finite buffer while awaiting bounded model completion. Short taps retain the existing cancel-without-insertion semantics. No unbounded waiting or buffer growth may be introduced.

Before 1B implementation, resolve whether existing SpeechEngine/StreamingSpeechSource start/finish semantics can express this safely. If not, write an explicit interface amendment and include all affected callers/tests in the same bounded packet. A simple reorder of load and audio.start is insufficient without this analysis.

## Visual contract

Preserve the accepted pill, dock orientation, accent, and listening waveform. Starting must be visually distinguishable from idle with readable text, no ornamental startup delay, no oscillating fake audio, and no new preferences. Repeated keyboard use favors immediate state changes. Reduced Motion and VoiceOver must retain equivalent state information.

## Safety and authority

No cloud, microphone pre-roll before user action, model download, weight bundling, retention-policy changes, cleanup/routing changes, installation, or GitHub writes. The canonical installed app remains untouched. Apply Sol/High worker and fresh Sol/High review requirements from AGENTS.md and the current user override.

## Acceptance

1A: deterministic tests distinguish starting from idle; rendered text fits all supported docks (bottom, left, right); short tap/cancel/listening behavior remains intact. Parent inspects rendered captures and reruns focused checks; fresh reviewer says `ship`.

Full phase: first-buffer ordering is independent of model load; audio stops promptly during loading/cancellation; early samples survive to inference; failures are bounded; actual waveform reflects microphone energy; exact package passes the two-device matrix. Report source, package, and device evidence separately.
