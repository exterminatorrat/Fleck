# Packaged Local Writing Admission Design

**Status:** Proposed
**Purpose:** Define what “ready to test,” “qualified,” and “release-ready” actually mean for Fleck dictation, cleanup, sorting, dictionary, models, and packaging

## 1. Admission ladder

Every claim is recorded at one exact level:

| Tier | Required evidence | Prohibited claim |
|---|---|---|
| D0 Documented | plan/spec/research exists | implemented |
| D1 Implemented | reviewed source and tests exist | real model works |
| D2 Integrated | production composition reaches the code under declared build flags | packaged app works |
| D3 Real-model replay | exact artifact runs private/public human audio | real microphone works |
| D4 Live packaged | exact ad-hoc/test app runs live microphone on one Mac | two-device/release ready |
| D5 Two-device accepted | identical package passes Mac mini and M1 8 GB MacBook | distribution ready |
| D6 Signed distribution accepted | intended signing/notarization/channel checks pass | release admitted |
| D7 Release admitted | explicit owner decision binds app/catalog/evidence | broader unsupported claims |

The UI and status docs must not compress these into “installed” or “tested.”

## 2. Artifact identity

Before hands-on testing, record:

- Git commit/branch and clean/dirty state;
- build command and environment flags;
- `Package.resolved` hash;
- app archive/ZIP SHA-256;
- bundle executable SHA-256;
- code-sign identity, entitlements, and designated requirement;
- running executable path and SHA-256;
- embedded catalog/manifest/notices hashes;
- catalog revision, configuration key/digest, and exact dictation/vocabulary/cleanup/routing profile digests;
- installed model profile and receipt hashes;
- dictionary snapshot digest;
- corpus/controlled-workspace revision.

Authoritative D4-and-later packaging requires a clean isolated source worktree at the recorded commit, with no staged, tracked, untracked, merge/rebase/cherry-pick, or submodule change. Generated build/evidence outputs must live outside source or under an exact ignored output root and never participate in source identity. A dirty build may be used only for a nonauthoritative developer smoke and must say so; it cannot be promoted. D6 additionally rechecks the clean commit, lockfiles, toolchain, and complete accepted-diff ancestry before signing.

The running process hash is captured immediately before QA. Launching an older `/Applications/Fleck.app` or stale derived build invalidates the run even if the UI looks similar.

### 2.1 Deterministic test ZIP contract

The enhanced test app is built once. A separate packager operates on a staging copy, removes extended attributes, rejects path/symlink escape, normalizes timestamps, walks canonical relative paths in bytewise order, preserves declared file type/mode/symlink target, and uses one recorded compression tool/version with stable options. Packaging the same unchanged `.app` twice must yield the same ZIP SHA-256.

The sidecar canonical receipt records ZIP SHA-256/bytes; canonical app-tree hash; bundle-executable SHA-256; source commit/dirty state; root and enhanced lockfile hashes; catalog revision; configuration key/digest; every role-profile digest; manifest/notices hashes; signing identity; compression tool/version; and packaging-policy revision. The receipt contains no private transcript, corpus path, dictionary content, credential, or model weight.

The app-tree SHA-256 input begins with ASCII `FLECK-APP-TREE`, one NUL byte, and UInt16 big-endian schema version `1`. Each entry then uses exactly: UInt32-BE path-byte count; NFC UTF-8 relative-path bytes; UInt8 type (`1` directory, `2` regular file, `3` symlink); UInt32-BE POSIX permission bits masked to `0o777`; UInt64-BE logical byte count; UInt32-BE payload byte count; payload. Directory payload/counts are empty/zero. Regular-file logical count is the file byte count and payload is exactly the 32 raw SHA-256 bytes of its content. Symlink logical/payload count is the byte count of its exact UTF-8 target and payload is those target bytes. Entries are sorted lexicographically by canonical path bytes. The packager rejects duplicate, Unicode-normalization-colliding, case-fold-colliding, separator-variant, absolute, traversal, device, socket, and escaping-symlink entries before hashing.

Because two independent filesystem paths cannot be published by one POSIX rename, “atomic ZIP and receipt” means a receipt-last commit protocol: stage and fsync both files inside a receipt-owned temporary directory; fail if final names already exist with different identities; rename and fsync the ZIP first; rename the fully validated receipt last as the commit marker; then fsync the parent. Consumers ignore or quarantine a ZIP without its matching final receipt. Relaunch cleanup may remove only transaction directories and orphan ZIPs named by a validated transaction journal. It never overwrites an existing complete pair.

## 3. Build lanes

### 3.1 Ordinary Fleck

- includes Apple Speech/system cleanup/deterministic fallbacks;
- excludes enhanced runtimes, manifests, helpers, and every weight artifact unless/until the ordinary-release architecture is separately approved;
- passes structural and binary scans for candidate symbols and model assets;
- remains functional without external model installation.

### 3.2 Enhanced test app

- arm64 Apple Silicon test artifact;
- packages exact runtime/helper/catalog metadata and notices;
- includes no model weights;
- acquires models only through explicit model management;
- may expose Quality Lab and unadmitted candidates with unmistakable development labeling;
- may never be described as a release package.
- is atomically wrapped as one deterministic AirDrop-ready ZIP with archive and app-executable SHA-256 receipts; the current app-build script alone is not the ZIP step.

### 3.3 Signed distribution candidate and intended distribution app

- initially built only after D5 from one explicit D5-accepted catalog/configuration/package/evidence tuple and a separately authorized promotion capability;
- is a `signedDistributionCandidate`, not a release-admitted app, while D6 signing/channel checks run;
- contains the D5-accepted enhanced runtime/configuration as its only enhanced selectable tuple if product policy permits it, plus at most one separately typed nonselectable update-transition record for a verified previously admitted predecessor;
- signed/notarized for the intended channel;
- includes required notices/terms and no unauthorized weights;
- preserves offline runtime and safe fallback behavior.

The current repository intentionally compiles enhanced behavior only in debug candidate builds and rejects enhanced release compilation. Passing D5 does not silently remove that guard. A separately authorized promotion packet must bind the exact D5 tuple to a distinct signed-distribution-candidate capability, preserve ordinary safe builds, and continue rejecting every research/development/non-D5 profile before D6 can begin. Only after D6 passes and the owner records D7 does the configuration become `releaseAdmitted`.

The intended distribution sequence is fixed: build and sign the D5-bound app; validate its signature; create a temporary notarization submission archive; submit/wait; staple the accepted ticket into the app; validate Gatekeeper and all post-staple bits; freeze that app; then create the deterministic final distribution ZIP and receipt with the same canonical archive engine used for the test ZIP. The submission archive is not an admission artifact. Because this promotion build is not byte-identical to the earlier development test ZIP, the final post-staple ZIP must then pass a fresh exact-artifact two-Mac functional/live equivalence gate. D6 and D7 bind only that final post-staple ZIP, canonical app tree, executable, and fresh final-artifact evidence. Nothing mutates or rebuilds the app after final packaging; any mutation restarts final packaging and the two-Mac gate.

## 4. Test environment matrix

Minimum hardware:

- primary Mac mini with roomier memory;
- M1 MacBook Pro with 8 GB RAM;
- built-in microphone on both;
- at least one Bluetooth/AirPods path;
- optional external/USB microphone for device-transition coverage.

Minimum states:

- online install, then offline runtime/relaunch;
- cold app/cold models;
- warm ASR;
- ASR-to-cleanup lease handoff;
- low reclaimable memory/memory pressure;
- Low Power Mode;
- thermal state simulation/observation where safe;
- sleep/wake;
- microphone disconnect/change;
- model missing/corrupt/repair/update/remove;
- dictionary empty/populated/conflicted/changed during capture;
- short, long, silence, immediate speech, release-edge speech.

## 5. Functional acceptance script

For the exact packaged app:

1. Launch and verify running artifact identity.
2. Confirm network is unavailable after models/assets are installed.
3. Dictate a clean sentence immediately after key-down; verify first/final words.
4. Dictate a disfluent sentence; compare raw ASR, dictionary baseline, validator-accepted faithful baseline, optional generated candidate, cleanup decision, and final insertion privately.
5. Dictate protected names, numbers, date, negation, URL, path, command, and commitment cases; require exact preservation.
6. Dictate a configured alias; require preferred form and cleanup protection.
7. Smart-capture a unique note topic; verify correct durable destination.
8. Smart-capture an ambiguous topic; verify durable Inbox save and bounded chooser.
9. Choose a destination; verify only the capture-owned receipt moves.
10. Keep another capture in Inbox.
11. Cancel at listening, ASR finish, cleanup, routing, and chooser boundaries; verify no late insertion/history/move.
12. Run a 2-minute transcript and repeated capture soak.
13. Trigger pressure/lifecycle transitions and verify fallback/lease release.
14. Quit/relaunch offline; repeat dictation and cleanup.
15. Repair, update (when an exact replacement exists), and remove a model; verify progress and scoped files.

## 6. Automated release gates

### 6.0 Development-only packaged evidence harness

E2 and soak evidence require an implemented harness, not a manual claim:

- a debug/enhanced-only app launch contract injects validated corpus PCM through the production processing pipeline;
- a separate local harness verifies package/model/dictionary/corpus hashes, launches cases, samples the entire Fleck/helper process tree, checks established network connections and declared persistence roots, and records lifecycle/cancellation receipts;
- a seeded 500-capture schedule is reproducible;
- private detailed evidence stays under the explicit corpus/evidence root;
- ordinary/release build scans prove the injected source and launch contract are unavailable;
- this proves package integration, never live microphone behavior.

### 6.1 Source and tests

- strict-concurrency build;
- focused FleckCore/App/Evaluation tests for each packet;
- complete test suite with baseline failures reconciled, no no-match filters;
- sanitizer/thread diagnostics where supported for critical lifecycle code;
- deterministic clocks/fault injection for deadline/cancellation transitions;
- no transcript/audio/note content in logs or failure descriptions.

### 6.2 Package structure

- no `.mlmodel`, `.mlmodelc`, `.safetensors`, `.gguf`, `.onnx`, model archive, or accidental corpus audio in ordinary/test ZIP unless a future explicitly authorized distribution design says otherwise;
- exact expected helper/runtime architectures;
- no duplicate MLX linkage;
- required metallib/runtime resources present exactly once;
- manifests and notices match catalog hashes;
- executable/ZIP size budgets;
- no source, secrets, tokens, cookies, resume data, corpus files, or personal dictionary in bundle.

### 6.3 Network/privacy

- model runtime starts and processes offline;
- unexpected connection count zero during capture, inference, cleanup, routing, and relaunch;
- only explicit install/update operations may use network;
- redirects/hosts are allowlisted and pinned by policy;
- ordinary audio persistence scan zero;
- diagnostic and crash-log transcript-content scan zero.

### 6.4 Installer fault injection

- redirect violation;
- truncated/wrong-length/wrong-hash file;
- missing/unexpected/duplicate/case-colliding path;
- traversal/symlink/device path;
- stale/tampered resume data;
- disk full before and during staging;
- crash/relaunch during each stage;
- concurrent install/repair/remove;
- mutation while runtime active;
- failed smoke/calibration;
- atomic rollback and receipt-scoped removal.

## 7. Performance and soak

Capture p50/p95/max for each stage and configuration, separated into cold/warm and hardware cohorts. The 500-capture soak includes:

- randomized short/medium/long utterances;
- randomized cancel stages;
- repeated model warm/cold transitions;
- periodic pressure and sleep/wake;
- dictionary edits between, never during, captured revisions;
- unique/ambiguous/Inbox routing;
- app relaunch checkpoints;
- RSS/physical footprint, swap, thermal/power observations;
- leaked process/helper/model lease checks;
- insertion/history/receipt reconciliation after every terminal state.

Averages cannot hide tail or integrity failures. One protected violation, wrong auto-route, late insertion, privacy event, or wrong receipt blocks admission.

## 8. Two-device acceptance

The MacBook does not receive a rebuild. It receives the exact archive produced and hashed on the Mac mini.

Acceptance requires:

- archive/bundle/running hashes match;
- catalog/profile receipts match;
- explicit dictionary export/import digest matches;
- replay corpus inputs match;
- both devices pass the focused live microphone subset;
- M1 8 GB passes footprint, pressure, lifecycle, and latency ceilings;
- adaptive policy decisions are recorded and explainable;
- model removal leaves only expected Fleck state;
- no iCloud/Developer Program capability is assumed.

The first D5 run qualifies the exact development configuration and produces the promotion input. After promotion/signing/notarization changes the app bits, the final post-staple ZIP is transferred unchanged to both Macs and repeats artifact identity, offline install/relaunch, model lifecycle, dictionary, cleanup, sorting, cancellation, resource/pressure, and a frozen real-microphone subset. External replay may support equivalence, but it cannot replace live E3 on either device. Only this second exact-artifact gate may feed D6/D7. The signed candidate intentionally has no injected-audio debug entrypoint; absence of that entrypoint is itself structurally verified rather than mislabeled as final-artifact E2.

Before D6 is created, the release evaluator must reopen the complete D5 source chain rather than trust the promotion digest embedded in the signed app. It verifies the retained 9A test ZIP against its package receipt; recomputes the D5 record from the Mac-mini and M1 live-run/score receipts plus their comparison; verifies the fixed-schema promotion-evidence bundle; and requires the resulting promotion digest to equal the signed-distribution extension. It also reopens the live Mac-mini canonical corpus ledger/latest checkpoint and detached D5 admission seal under the externally reviewed evaluation-signer fingerprint. Every receipt-bound earlier head must be an ancestor, the post-seal suffix may contain only candidate-exposure events, and any invalidation of consumed material fails current verification. D6 then binds the reopened D5 chain, the current ledger checkpoint/head and eligibility-verification receipt, the seal/signer, and the separate fresh final-artifact receipts. Missing 9A bits, source receipts, current ledger state, or seal proof blocks D6 even when the final app contains a self-consistent digest.

The D6 evidence receipt is unsigned, canonical, content-addressed, and self-contained for immutable release provenance. Its creator embeds the unchanged canonical content-free final package receipt and notary receipt bytes as bounded base64 fields and recomputes their digests. Its verifier strict-decodes those embedded bytes, checks the supplied final ZIP/app tree/executable against them, and reopens every D5/final-run/live-corpus source. D7 signs the resulting D6 digest and complete admission payload. Later D7/update-predecessor verification reopens the embedded package/notary bytes and byte-matches any separately supplied package receipt, so no mutable staging path or digest-only D6 assertion becomes authority.

## 9. Signing and distribution

For the intended channel, verify:

- code-sign chain, hardened runtime, entitlements, nested helper signatures;
- notarization and stapling where required;
- Gatekeeper assessment from a transferred/downloaded artifact;
- first-launch permissions and model-install authorization;
- model terms/notices and source attribution path;
- update/rollback behavior under the signed identity when the catalog names an exact transition from a previously release-admitted predecessor to the current D5-promotion-authorized signed successor candidate; otherwise a signed-identity receipt proving that the release embeds no update transition, no Update action is exposed, and the release makes no validated-update claim;
- no debug/development candidate controls in normal release UI;
- privacy policy/product copy matches actual local behavior.

An ad-hoc signature proves bundle integrity only; it is not distribution acceptance.

## 10. Admission record

The final record binds:

```swift
struct LocalWritingReleaseAdmission: Codable {
  let schemaVersion: Int
  let fleckRelease: String
  let sourceCommit: String
  let catalogRevision: String
  let configurationKey: String
  let configurationIdentityDigest: String
  let dictationProfileIdentityDigest: String
  let vocabularyProfileIdentityDigest: String?
  let cleanupProfileIdentityDigest: String
  let routingProfileIdentityDigest: String
  let evidenceBundleIDs: [String]
  let d5PromotionRecordSHA256: String
  let d5PromotionEvidenceBundleSHA256: String
  let d5TestPackageReceiptSHA256: String
  let d5TestZIPSHA256: String
  let d6EvidenceReceiptSHA256: String
  let corpusLedgerCheckpointSHA256: String
  let corpusLedgerHeadEventSHA256: String
  let corpusEligibilityVerificationReceiptSHA256: String
  let corpusAdmissionSealSHA256: String
  let evaluationSignerFingerprintSHA256: String
  let predecessorCorpusDependencies: [LocalWritingPredecessorCorpusDependency]
  let supportedHardwareOS: [HardwareOSCohort]
  let claimScope: LocalWritingClaimScope
  let speakerAcousticCohort: EvidenceCohortID
  let packageZIPSHA256: String
  let canonicalAppTreeSHA256: String
  let bundleExecutableSHA256: String
  let signingIdentityDigest: String
  let updateTransitionIdentityDigest: String?
  let updateValidation: UpdateValidationDecision
  let trustPolicySequence: UInt64
  let trustPolicyCheckpointSHA256: String
  let decision: AdmissionDecision
  let approver: String
  let decidedAtUnixMilliseconds: Int64
}

enum UpdateValidationDecision: Codable {
  case executedTransition(predecessorAdmissionDigest: String, transitionDigest: String)
  case notApplicableNoEmbeddedTransition(reasonCode: String)
}

struct LocalWritingPredecessorCorpusDependency: Codable {
  let predecessorAdmissionSHA256: String
  let corpusLedgerCheckpointSHA256: String
  let corpusLedgerHeadEventSHA256: String
  let corpusAdmissionSealSHA256: String
  let evaluationSignerFingerprintSHA256: String
}
```

The typed payload is encoded as RFC 8785 canonical JSON with NFC strings, integer-only time/size fields, absent rather than `null` optionals, and lexicographically sorted unique evidence/cohort arrays. A strict preflight rejects duplicate or unknown object keys, floats, out-of-range integers, non-NFC strings, unsorted/duplicate arrays, and any input whose decode/re-encode bytes differ. The payload digest covers those exact bytes.

The canonical payload is wrapped in a detached CMS-signed envelope containing the signer fingerprint and signature bytes. The fingerprint inside the envelope is descriptive only—it is never its own trust root. Verification requires an explicit external `release-admission-trust-policy.json`. Every policy has a monotonic sequence and, after bootstrap, the exact previous checkpoint digest. Its canonical checkpoint binds policy bytes/digest, sequence, predecessor checkpoint, certificate fingerprint/digest, validity, and verifier revision.

D6 creation, D6 verification, D7 creation, D7 verification, and predecessor-record creation/verification all require the same live canonical ledger, latest checkpoint, detached D5 seal, expected current corpus head, and externally reviewed evaluation-signer fingerprint. They recompute the eligibility-verification receipt rather than accepting the digests stored in D6/D7 as authority. For `executedTransition`, those same create/verify paths also receive and independently reopen the immediate predecessor's live ledger/checkpoint/seal/head/evaluation-signer tuple plus every older dependency named by the predecessor admission, in canonical signed order. `predecessorCorpusDependencies` is empty for `notApplicableNoEmbeddedTransition`; it is nonempty and exactly matches the supplied live chain for `executedTransition`. The 9D build and final package receipt bind the same dependency tuple, and a verifier rereads every latest checkpoint immediately before accepting output so an invalidation between 9D, D6, D7, or predecessor export is observed. A later lineage invalidation therefore makes current D6/D7/predecessor verification fail and marks release evidence revoked for present use; the historical signed record remains auditable but cannot authorize a new install, recommendation, or update transition. Restoring eligibility requires fresh blinded material and a new D5-through-D7 chain.

For the remote M1 half of the final two-Mac `executedTransition` run, the authoritative Mac mini creates one content-free predecessor-corpus verification snapshot only after reopening that complete live dependency chain. The CMS-signed snapshot binds the predecessor update record/D7/D6/retained package, successor package and transition digest, current predecessor checkpoint/head/seal/evaluation signer, ordered transitive dependency tuples, and current trust-policy sequence/checkpoint. The source verifies it before transfer; the M1 verifies exact bytes and signer, imports it into a new `0700` evidence root, and binds the imported snapshot plus import receipt into its update-run plan and receipt. The snapshot has no raw corpus paths or content, cannot mutate a ledger, cannot be reused for another successor, and cannot substitute for the live Mac-mini reopening repeated by D6 and D7. `notApplicableNoEmbeddedTransition` forbids the snapshot and every related input.

An `executedTransition` update receipt is self-contained evidence rather than a digest-only claim: it embeds the unchanged canonical snapshot envelope and exactly one unchanged proof envelope, tagged `sourceVerification` on the Mac mini or `remoteImport` on the M1, plus recomputed digests and machine role. Its verifier rechecks both embedded envelopes, CMS signer, predecessor/successor packages, transition, trust checkpoint, and recursive dependency tuple. The content-free update-evidence export therefore transports the whole verified update receipt; D6 reopens those embedded bytes from both machine receipts and separately reopens the authoritative live Mac-mini predecessor chain. The no-transition receipt carries neither envelope.

The owner separately maintains the latest `{ sequence, checkpointSHA256 }` outside the app, repository, release evidence root, and write authority of release commands. D6/D7 creation and verification require those expected values in addition to the reviewed signer fingerprint. Rotation and revocation advance the sequence by exactly one, bind the preceding checkpoint, and remain unusable until the owner reviews the new digest and advances the external latest-state record. A previously valid policy/checkpoint is rejected after that advance even if its certificate and validity window still pass. Rotation is dual-signed by current/incoming keys only to authorize the new policy; this version does not maintain an authorized historical-signer ledger and does not reinterpret old D7/predecessor signatures under the new key. Emergency revocation requires an unrevoked active authority. Revoking/losing the sole root stops new admission and requires explicit out-of-band bootstrap. Private keys remain in the approved local keychain. The owner-private program makes no public-transparency-log claim.

For `executedTransition`, the predecessor D7/update record, embedded transition, final package receipt, both final update runs, D6, and D7 all bind one exact policy sequence/checkpoint. D6 and D7 require that anchor to equal the current externally pinned latest-state inputs. A rotation, revocation, or other latest-state advance after predecessor D7 or after 9D therefore forbids the transition; because this version has no historical-signer chain, the candidate must be rebuilt and retested with `notApplicableNoEmbeddedTransition` rather than re-signing the old predecessor under the new anchor. The `notApplicableNoEmbeddedTransition` path carries no predecessor-derived trust or global predecessor-absence claim.

The record stays in the private release evidence root. It is consumed only by release tooling and status generation; it does not alter the D6 app, embedded catalog, runtime eligibility, or executable hash.

Changing model files, runtime ABI, prompt, validator, dictionary compiler policy, routing policy, package, supported cohort, or release build requires new evidence and a new admission record. It does not inherit automatically.

The initial two-device/one-operator program can admit only `ownerPrivateBeta`. A general-English beta or release requires a separately frozen, consented, representative speaker/accent/acoustic cohort and subgroup evidence; two machines used by one speaker are not a general population cohort.

## 11. Rollback and revocation

- A runtime integrity failure immediately makes that local receipt unusable and selects a safe fallback.
- A catalog can revoke a profile/configuration for future use only through an authenticated app/catalog update; no hidden network kill switch.
- The user can remove Fleck-managed artifacts explicitly.
- A newly selected profile retains the previous verified profile for a bounded local rollback window when storage allows.
- A signed successor may recognize a predecessor only through nonselectable transition metadata derived from the prior release's verified D7/D6/package/catalog export. That metadata cannot recommend or run the predecessor except during exact rollback.
- Automatic update/rollback transitions never cross a trust-policy checkpoint change in this version; the successor uses no embedded transition and the user performs a fresh explicit installation instead.
- An update-capable claim requires an executed predecessor-to-candidate-successor transition on both hardware cohorts; otherwise the signed record says `notApplicableNoEmbeddedTransition` and exposes no Update action.
- Replaying a policy/checkpoint from before rotation or revocation never restores admission authority because every verification requires the externally pinned latest sequence/digest, and any embedded predecessor transition must carry that same sequence/digest.
- Release status docs show revoked/failed evidence without rewriting history.

## 12. Exit criteria

The program may say “ready for your hands-on test” after an exact packaged candidate passes identity, model-install, focused automated, and injected-audio/package smoke checks. That means it is ready to attempt D4; it has not passed D4.

It may record D4 only after the live packaged real-microphone run passes on the named Mac.

It may say “candidate accepted on both Macs” at D5 only after the identical artifact passes the two-device matrix.

It may say “release-ready” only at D6 after the final post-staple bits pass the fresh two-device gate, and “release-admitted” only after a valid detached D7 owner record binds those unchanged D6 bits. None of these terms is inferred from elapsed effort or feature completeness.
