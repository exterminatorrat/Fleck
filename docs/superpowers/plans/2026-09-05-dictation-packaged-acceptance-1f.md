# Packet 1F — Packaged dictation acceptance

**Goal:** Prove the accepted capture, cancellation, feedback and resource behavior in an identified packaged app on the 8 GB M1 MacBook and M4 Mac mini.
**Architecture:** Reuse the 1E collector and provenance, run the physical acceptance matrix, and route any discovered defect through a separate sequential fix packet.
**Stack:** Existing macOS package/signature scripts, content-free diagnostics, exact-process resource sampling, supervised real-microphone and shortcut checks.
**Specification:** `2026-09-05-capture-feedback.md`, Packet 1F. Planned alongside 1E; implementation/execution waits for 1E acceptance.

## F1 — Candidate preparation

1. **Objective / success:** A uniquely named candidate tied to the accepted source and correct architecture is ready for review and supervised launch.
2. **Ownership:** Initially documentation/evidence only. Reuse `Scripts/build-pre-astra-corrected-build.sh` and the established enhanced build path; if incompatibility requires code changes, specify exact owned script/tests before a native Sol High worker edits them.
3. **Required / non-goals:** Verify branch, clean tree, accepted commits, dependency lock, source hash and all feature flags. Identify whether the package actually includes Enhanced Parakeet support. Record executable/helper hashes, SDK, architecture, codesign/entitlements and model-weight exclusion. Preserve the canonical installed bundle. Never call this the newest/current main build while the accepted source remains on an unmerged local branch.
4. **Verification:** Existing packaging/provenance checks, archive contents and signatures. Package build is not recipient-install or microphone proof. Parent verifies and fresh Sol `ship` is required for any changed implementation.
5. **Authority / handoff:** No push, PR, merge, signing-account change, distribution, installed-app replacement or launch without applicable user authorization. Present exact source, candidate path and proposed device action when requesting missing authority. Do not create an implementation task in the alternate Sol Advisor lane.

- [ ] Confirm 1E acceptance and freeze its accepted source/evidence.
- [ ] Prepare the exact candidate through authorized existing build steps.
- [ ] Verify package, dependency/model provenance and clean source.

## F2 — Physical acceptance, separately on both Macs

Use identical scenario definitions and record every attempted trial, including failures. Before launch establish the intended bundle, terminate only an authorized conflicting instance, then verify the actual PID and executable path. Record microphone and permission state. Never infer actual running lineage from the app name or timestamp.

| Scenario | Trials per Mac | Required observation |
| --- | ---: | --- |
| Cold / warm / after Gemma | 10 each | First-word preservation; source/model readiness; final output; resource timeline |
| Short tap / hold / double tap / pointer | 5 each | Intended capture mode, truthful Starting/Listening/Processing feedback, one result |
| Escape during loading / capture / finalization | 5 each | Microphone stops, cancellation drains, no late insertion or save |
| Silence | 5 | Correct no-speech behavior, clean resource release |
| Long dictation, 30 seconds / 2 minutes | 3 each | Complete final output, no truncation, bounded capture behavior |
| Sleep/wake / microphone switch | 5 each | Stale capture invalidated, recoverable next capture, correct device |
| Low Power Mode / observed memory pressure | 5 each | Retention invalidation and usable next capture |

Evaluation targets: p95 feedback <=100 ms from event delivery and audio readiness <=200 ms with permission already granted. Report physical key-to-feedback separately using supervised observation/video when available; do not label internal timestamps as physical latency. Report first-word recall per condition and retain all incorrect outputs in user-controlled evidence rather than in the content-free diagnostic stream.

Check that Starting does not promise an open microphone, Listening follows actual readiness, and cancellation feedback does not promise drain before it happens. This is behavioral acceptance of the existing interface, not a redesign. Preserve dictation/cleanup/routing and approved Settings appearance.

- [ ] Complete the matrix on M1 with exact provenance and evidence links.
- [ ] Complete it independently on M4; never substitute its results for M1.
- [ ] Check no microphone activity after cancellation, no late insertion, and no missing first words. Any such failure blocks acceptance.

## F3 — Defect loop and final handoff

For each defect, identify the failed scenario and minimal reproducible boundary before implementation. Write a bounded five-part specification with exact file ownership, red-first verification, explicit non-goals and authority limits. Execute one native Sol High worker at a time; workers are not alone and must preserve concurrent edits. Parent reviews the actual diff and reruns relevant nonempty checks. A fresh `sol_advisor_sol_reviewer` must return `ship`; `fix-first` goes back to the same worker. Only then produce a new identified candidate and repeat the failed scenario plus affected regressions. Do not reuse physical evidence from an older binary for changed behavior.

- [ ] Resolve all blocking defects through sequential reviewed fixes.
- [ ] Provide per-device pass/fail counts, latency distributions, first-word recall, resource results, missing evidence and remaining limitations.
- [ ] Separate source/test, package/signature, physical-device, recipient-install and release proof.
- [ ] Mark 1F accepted only after the physical matrix passes and the exact final candidate is identified. GitHub integration or release remains a separate authorized action.
