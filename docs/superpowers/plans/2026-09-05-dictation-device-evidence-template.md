# Dictation device evidence sheet — 1E / 1F

Status: **not run**. This is a protocol template, not acceptance evidence. Duplicate once per device and candidate. Preserve failed attempts; use `unavailable` with a reason instead of blank or zero metrics.

## Run manifest

| Field | Recorded value |
| --- | --- |
| Run identifier / UTC start / operator | unavailable — run not started |
| Device model / chip / installed RAM / OS build | unavailable — identify target at run time |
| Source commit / tree hash / clean status / branch | unavailable — freeze accepted candidate first |
| Build flags / SDK / architecture / dependency lock hash | unavailable — candidate not built |
| App absolute path / executable hash / codesign identity | unavailable — candidate not built |
| Helper paths / hashes / separate PIDs | unavailable — candidate not launched |
| App PID / process start identity | unavailable — candidate not launched |
| Model repository / immutable receipt / installed assets | unavailable — inspect authorized device |
| Microphone / selected speech engine / permission state | unavailable — inspect authorized device |
| Power mode / thermal / memory pressure / reclaimable bytes | unavailable — capture alongside each trial |
| Policy source revision / computed retention | unavailable — record exact candidate |
| Diagnostic run directory / sampler file / trial sheet | unavailable — collectors not run |
| Comparison baseline / difference being evaluated | unavailable — choose startup or policy comparison |

## Trial row contract

For an authorized candidate launch, explicitly set `FLECK_DICTATION_DIAGNOSTICS_DIR` and capture stderr. The fixed `fleck_dictation_diagnostics=sink_failure` message invalidates the collection run; missing records are not successful trials. Wait for expected files and the final cancellation-drain revision before closing the app. Abrupt exit may lose queued records. Start a fresh diagnostic run before the 128-capture limit; do not assume later captures were recorded.

Run the resource command against the verified app PID: `local-dictation-candidate sample-resources --pid <PID> --duration-seconds <1...600> --output <new JSON path>`. Record the reported start identity and exit status. An `incomplete` report retains valid earlier samples but cannot prove the complete measurement window. Record power/thermal/pressure/reclaimable snapshots separately; process RSS is not system reclaimable memory.

Use one row per attempted trial, including cancellation and failure. Associate the collector's run-local capture ordinal with the scenario externally. Record device/run identity, trial number, scenario, preparation (cold, within retention window, after Gemma), relative trial start/stop, collector ordinal, actual power/thermal/pressure/reclaimable state, requested gesture, observed result and reason for failure or missing evidence.

Timing columns (milliseconds, preserve unavailable): event-to-feedback, event-to-first-input-buffer, event-to-audio-ready, model-load duration, release-to-ASR-final, release-to-final-insertion, persistence completion, cancel-request-to-drained. Label the underlying anchors precisely; do not silently substitute first partial for first input buffer or insertion for persistence. Physical-key latency is a separate column with its observation method.

Quality columns: expected first word, preserved first word yes/no/unavailable, full result correct yes/no, duplicate/late insertion yes/no, microphone stopped after cancel yes/no, truthful feedback yes/no. Keep spoken/output text in user-controlled supervised evidence; the automatic diagnostic stream remains content-free.

Resource columns (bytes): pre-trial RSS/physical footprint, sampled peaks, residual at 0/5/15/30/60 seconds, sampling cadence, process-identity validity, unavailable-sample count, actual idle/model state. A peak is a sampled lower bound, not an assertion of an unsampled instantaneous maximum. Do not sum unrelated helper and app peaks as simultaneous residency.

## Aggregation and decision

For each device, candidate and scenario separately, report attempts/successes/failures/missing values, first-word recall numerator/denominator, p50/p95 with the calculation rule, latency range, sampled peak and residual resource distributions. Use nearest-rank p95 (`ceil(0.95 * n)` in sorted observed samples); disclose small sample counts. Do not exclude slow or failed attempts to improve a distribution: report timing availability and failure counts alongside it.

The feedback and readiness targets are evaluated only on applicable measured trials. Lost first words, late insertion or a microphone continuing after cancellation block 1F. An absent M1 run blocks the 1E target decision. A clean source review, M4 control or package signature cannot remove either block.
