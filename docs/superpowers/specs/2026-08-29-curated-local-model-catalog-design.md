# Curated Local Model Catalog Design

**Status:** Proposed; no catalog entry below is release-admitted
**Research basis:** `docs/research/2026-08-29-local-writing-model-catalog-primary-sources.md`

## 1. Objective

Give Fleck a small, trustworthy set of exact local configurations without turning Settings into a model marketplace. The catalog must answer four different questions separately:

1. What exact artifacts and runtimes does Fleck know how to verify?
2. Which exact profiles have passed Fleck's quality and hardware gates?
3. Which compatible admitted profile should this Mac use automatically?
4. Which files are actually installed, verified, selected, warm, or active right now?

A family name such as “Parakeet” or “Gemma” is never enough to answer any of them.

## 2. Design decision

Implement a conservative immutable profile catalog on top of the existing `AdmittedModelDescriptor`, `AdmittedModelCatalog`, `EnhancedModelManager`, installation presentation, and runtime policy.

The product can describe its Quality, Lightweight, Live, Built-in Safe, and Evaluation Archive **curated collections** as different catalogs. Internally they are collections inside one immutable catalog snapshot and one identity/admission system. Multiple independent trust roots would let the same artifact be “admitted” in one place and “experimental” in another.

Do not implement a general provider registry or capability-graph platform yet. Choose IDs and events that can later sit behind a deeper `ModelCatalogModule`, but add abstraction only when a second admitted runtime or compound profile makes it necessary.

## 3. Terminology

- **Family** — human grouping, such as Parakeet Unified or Gemma 3; not installable.
- **Artifact manifest** — exact source repository, revision, selected files, byte counts, SHA-256 values, notices, and closed file set.
- **Runtime profile** — one role, manifest/system capability, runtime ABI, inference contract, precision/tier, support envelope, resource envelope, license record, and evidence reference.
- **Curated configuration** — one exact compatible dictation, cleanup, and routing profile tuple, their fallback chains, and joint residency policy.
- **Catalog snapshot** — immutable profiles, configurations, and deterministic recommendation policy embedded with one Fleck build.
- **Installation receipt** — device-local record proving which immutable artifact Fleck actually staged and verified.
- **Admission** — reviewed evidence that allows a profile/configuration in a named hardware/OS/release, claim-scope, and speaker/acoustic cohort.

## 4. Catalog layers

```swift
struct LocalModelCatalogSnapshot: Codable, Sendable {
  let schemaVersion: Int
  let revision: String
  let profiles: [LocalModelProfile]
  let configurations: [CuratedLocalModelConfiguration]
  let updateTransitions: [LocalModelUpdateTransition]
  let recommendationPolicyRevision: String
}

struct LocalModelProfile: Codable, Sendable {
  let key: LocalModelProfileKey          // stable human-readable catalog key
  let identityDigest: SHA256Digest       // immutable exact profile identity
  let familyID: String
  let role: LocalModelRole
  let distribution: LocalModelDistribution
  let runtime: LocalModelRuntimeContract
  let capabilities: [LocalModelCapability] // canonical sorted unique array
  let support: LocalModelSupportEnvelope
  let resources: LocalModelResourceEnvelope
  let licenses: [LocalModelLicenseRecord]
  let evidence: LocalModelEvidenceReference?
  let admission: LocalModelAdmissionState
}

enum LocalModelDistribution: Codable, Sendable {
  case fleckManaged(artifact: ArtifactManifestID)
  case systemManaged(capability: SystemCapabilityID)
  case builtInDeterministic
}

struct LocalModelUpdateTransition: Codable, Sendable {
  let schemaVersion: Int
  let key: String
  let identityDigest: SHA256Digest
  let predecessorUpdateRecordDigest: SHA256Digest
  let predecessorReleaseAdmissionDigest: SHA256Digest
  let predecessorPackageReceiptDigest: SHA256Digest
  let predecessorTrustPolicySequence: UInt64
  let predecessorTrustPolicyCheckpointDigest: SHA256Digest
  let predecessorCorpusDependencies: [LocalModelPredecessorCorpusDependency]
  let predecessorConfiguration: RetiredConfigurationVerificationDescriptor
  let successorPromotionRecordDigest: SHA256Digest
  let successorConfiguration: LocalModelConfigurationReference
  let requiredArtifacts: [TransitionArtifactDescriptor]
  let rollbackPolicy: LocalModelRollbackPolicy
}

struct LocalModelConfigurationReference: Codable, Sendable {
  let key: String
  let identityDigest: SHA256Digest
}

struct LocalModelPredecessorCorpusDependency: Codable, Sendable {
  let predecessorAdmissionDigest: SHA256Digest
  let corpusLedgerCheckpointDigest: SHA256Digest
  let corpusLedgerHeadEventDigest: SHA256Digest
  let corpusAdmissionSealDigest: SHA256Digest
  let evaluationSignerFingerprintDigest: SHA256Digest
}

struct RetiredConfigurationVerificationDescriptor: Codable, Sendable {
  let configuration: LocalModelConfigurationReference
  let profileIdentityDigests: [SHA256Digest]
  let artifactManifestDigests: [SHA256Digest]
  let installationReceiptSchemaVersion: Int
  let runtimeCompatibilityRevision: String
}

struct TransitionArtifactDescriptor: Codable, Sendable {
  let manifestDigest: SHA256Digest
  let side: UpdateTransitionSide       // predecessor or successor
  let role: UpdateTransitionRole       // install, retainForRollback, or shared
  let closedFileSetDigest: SHA256Digest
  let installedBytes: Int64
}

struct LocalModelRollbackPolicy: Codable, Sendable {
  let revision: String
  let retentionDurationMilliseconds: Int64
  let requiredFreeBytesBeforeUpdate: Int64
  let rollbackCompatibilityRevision: String
}
```

`RetiredConfigurationVerificationDescriptor` contains only the previously release-admitted configuration/profile identities, closed artifact manifests, runtime/installation-receipt schema, and rollback-compatibility revision needed to verify an already installed predecessor. It is not a `LocalModelProfile`, cannot satisfy recommendation or runtime lookup, and never makes the predecessor selectable. `TransitionArtifactDescriptor` assigns each predecessor/successor manifest its staging, reference, and rollback role without embedding its files.

The ordinary app bundle includes only `ordinarySafe` system/deterministic catalog metadata and no candidate metadata, enhanced notices/symbols, weights, or update transitions. `developmentQuality` builds compile a separate exact candidate snapshot. A later signed-distribution snapshot contains only its exact promotion-authorized tuple plus safe fallbacks **as selectable configurations**. A successor snapshot may additionally contain exactly one nonselectable `LocalModelUpdateTransition` derived from the previous release's verified 9E `update-predecessor-record`, retained final ZIP/package receipt, current externally pinned trust state, current live predecessor corpus dependency chain, and the current D5 promotion record. The transition binds the exact externally pinned policy sequence/checkpoint plus the ordered predecessor corpus checkpoint/head/seal/evaluation-signer tuple under which the predecessor sources were reopened. D6 and D7 accept it only when the trust fields equal their current pinned latest-state inputs, every live predecessor corpus dependency reopens successfully, and the predecessor record/D7 were issued under those exact anchors. This design has no current-anchor-authorized historical-signer ledger: any trust rotation, revocation, other checkpoint advance, or consumed-lineage invalidation after predecessor D7 makes that predecessor ineligible for an automatic transition. The release must use an empty transition/no-update claim and a fresh explicit installation path unless a later separately approved design restores eligibility with a new evidence/admission chain. A release that makes no update claim has an empty transition list; this proves only that no transition is embedded, not that predecessor absence has been established. Each embedded snapshot is authenticated by its signed app bundle; it does not add a second catalog signature mechanism. A remotely updateable catalog would require a later explicit trust/signature design.

## 5. Canonical profile identity

For Fleck-managed artifacts:

```text
profileIdentityDigest = SHA256(
  schemaVersion
  + profile key and family ID
  + role
  + distribution and exact artifact-manifest or system-capability identity
  + sourceURL and sourceRevision for Fleck-managed artifacts
  + ordered(path, bytes, sha256) for selected files
  + complete runtime contract: adapter ID, ABI, conversion, precision, tokenizer/template, and inference-contract digest
  + canonical sorted unique capabilities
  + canonical support envelope: architecture, OS, locale, hardware/cohort, and required system features
  + canonical resource envelope: download, installed/staging, peak/warm/idle memory, load/latency, and storage policy bounds
  + license-record digest
)
```

Validation rules:

- every identity-bearing collection has a declared stable sort order; unordered `Set` encoding is forbidden;
- no branch, tag, `latest`, mutable URL, query-bearing source, or unapproved redirect;
- closed selected-file set: missing and unexpected files both fail;
- canonical relative paths only; reject empty, absolute, `..`, duplicate, case-colliding, symlink, device, and traversal paths;
- checked byte arithmetic for download, installed, and side-by-side staging totals;
- SHA-256 for every selected file, including non-LFS blobs;
- exact FluidAudio or MLX dependency revisions and Fleck adapter ABI;
- tokenizer/chat template/model config included in the contract;
- license and notice contents/version hashes participate in identity;
- no secrets, tokens, cookies, acceptance receipts, or machine-local paths.

System-managed Apple capabilities use a typed availability/cohort identity instead of fake file hashes.

## 6. Initial curated profiles

### 6.1 Dictation

| Profile | Current role | Key qualification question |
|---|---|---|
| `apple-speech-en-system` | Production fallback/control | Is on-device recognition/assets available for this locale and OS? |
| `parakeet-v2-en-coreml-batch` | Current first enhanced candidate | Does capture-first startup fix first-word misses and does it pass operator WER/latency/memory gates? |
| `parakeet-tdt-ctc-110m-en-coreml-batch` | Lightweight challenger | Can it match useful quality on M1 8 GB with lower load/memory, including 15-second stitching? |
| `parakeet-v2-plus-ctc110m-en` | Vocabulary challenger | Does exact dictionary recall improve enough to justify a second acoustic pass and artifact? |
| `parakeet-unified-en-coreml-{precision}-{tier}` | Batch/streaming challenger | Does one exact offline or 320/640 ms export improve real Fleck behavior without excess memory/churn? |
| `parakeet-eou-120m-en-coreml-{tier}` | Low-latency streaming experiment | Are partials, end-of-utterance, pause/restart, and state reset reliable enough for Fleck? |

The first admission sequence stays narrow:

1. fix and qualify current Parakeet TDT v2 capture reliability;
2. qualify TDT-CTC 110M as a lightweight primary candidate;
3. qualify CTC assistance only if dictionary cases still miss;
4. qualify one Unified or EOU profile only if genuine live partials become a product requirement.

Whisper, Nemotron, and Qwen remain historical/evaluation entries, not normal alternatives, until a new evidence packet gives a specific reason to reopen them.

### 6.2 Cleanup

| Profile | Current role | Key qualification question |
|---|---|---|
| `deterministic-faithful-cleanup` | Mandatory built-in fallback | Does every safe deterministic operation preserve exact meaning? |
| `apple-foundation-cleanup-system-{osCohort}` | System-managed candidate | Is Apple Intelligence/model available, and does this prompt/OS cohort pass the same validator corpus? |
| `gemma3-1b-it-mlx-qat4` | Current open-weight quality candidate | Can it produce enough accepted improvements within M1 memory and stop-to-insert budgets? |
| `gemma3-270m-it-mlx-4bit` | Lightweight challenger | Does lower load/memory retain zero-violation utility? |
| `llama3.2-1b-control` | Optional laboratory control | Only if an exact primary-source/license/runtime packet is justified later |

Rejected Qwen cleanup evidence remains visible in the evaluation archive; it is not promoted by adding it to a selector.

### 6.3 Semantic routing

Routing is a distinct quality role even when it shares one installed Gemma artifact with cleanup:

| Profile key | Artifact relationship | Qualification question |
|---|---|---|
| `deterministic-local-routing` | Built in | Do exact-title, cached retrieval, corroboration, and Inbox gates stay precise without model judgment? |
| `apple-foundation-routing-system-{osCohort}` | Same system capability family, separate prompt/adapter ABI | Does this OS cohort choose only corroborated unique destinations? |
| `gemma3-1b-routing-mlx-qat4` | Shares Gemma 1B artifact manifest with cleanup | Does the routing prompt/parser/gate pass precision and chooser recall independently? |
| `gemma3-270m-routing-mlx-4bit` | Shares Gemma 270M artifact if qualified | Can a lightweight judge add safe coverage within resource limits? |

Cleanup and routing profiles may reference the same artifact manifest, so it downloads once. They retain separate profile keys, adapter/prompt ABIs, evidence, and admission. Passing cleanup does not admit routing, or vice versa.

## 7. Curated configurations

A configuration binds profiles and the joint policy they were tested under:

```swift
struct CuratedLocalModelConfiguration: Codable, Sendable {
  let key: CuratedConfigurationKey
  let identityDigest: SHA256Digest
  let displayName: String
  let dictation: LocalModelProfileReference
  let vocabularyAssistance: LocalModelProfileReference?
  let cleanup: LocalModelProfileReference
  let routing: LocalModelProfileReference
  let dictationFallbacks: [LocalModelProfileReference]
  let cleanupFallbacks: [LocalModelProfileReference]
  let routingFallbacks: [LocalModelProfileReference]
  let jointResidencyPolicy: JointResidencyPolicyID
  let requiredEvidence: LocalModelEvidenceReference
  let admission: LocalModelAdmissionState
}

struct LocalModelProfileReference: Codable, Sendable {
  let key: LocalModelProfileKey
  let identityDigest: SHA256Digest
}
```

The configuration key is a stable human-readable catalog key. The identity digest is computed canonically from the configuration-schema version, key, ordered exact profile references and fallback chains, and joint residency-policy revision. The catalog revision is recorded separately. Display text, mutable evidence pointers, installation state, and admission state do not participate. Any profile, fallback order, or residency-policy change creates a new configuration identity.

Fallback timing is role-specific. A dictation fallback is resolved only during preflight or for the **next capture**: after an enhanced source has started, failure/cancellation publishes nothing and may not replay buffered speech into Apple Speech. Cleanup and routing fallbacks may execute within the same transaction only from the immutable dictionary/faithful text baseline and only within their existing deadline/cancellation gates. The configuration schema encodes this timing policy, and composition rejects a generic same-capture ASR fallback chain.

Proposed collections contain exact configurations rather than “A or B” placeholders. Independently admitted roles are never forced to fail as a bundle: the primary Parakeet/Gemma family has four explicit safe tuples, each with its own identity and joint evidence:

1. **English Dictation — Deterministic Writing** — Parakeet TDT v2 + deterministic cleanup + deterministic routing.
2. **English Cleanup — Open Weight** — Parakeet TDT v2 + admitted Gemma 1B cleanup + deterministic routing.
3. **English Sort — Open Weight** — Parakeet TDT v2 + deterministic cleanup + admitted Gemma 1B routing.
4. **English Quality — Open Weight** — Parakeet TDT v2 + independently admitted Gemma 1B cleanup + independently admitted Gemma 1B routing.
5. **English Quality — Open Weight + CTC Assist** — a separate exact configuration containing the admitted auxiliary CTC profile; it exists only if Packet 7J passes.
6. **Apple Local Writing — Cleanup** — Apple Speech + one exact Apple Foundation cleanup OS cohort + deterministic routing.
7. **Apple Local Writing — Sort** — Apple Speech + deterministic cleanup + one exact Apple Foundation routing OS cohort.
8. **Apple Local Writing — Full** — Apple Speech + independently qualified Apple Foundation cleanup and routing profiles for one OS cohort.
9. **English Quality — Apple System** — exact Parakeet plus one exact independently qualified Apple cleanup/routing combination; deterministic occupies any unqualified optional role.
10. **Lightweight English** — exact TDT-CTC 110M if qualified + deterministic cleanup + deterministic local routing; any Gemma 270M mixed tuple is added only through a later amended exact packet for the independently passing role(s).
11. **Live English Experimental** — one exact Unified or EOU tier + one exact qualified cleanup profile + one exact qualified routing profile; development-only until admitted.
12. **Built-in Safe** — Apple Speech + deterministic cleanup + deterministic local routing; no Fleck-managed weights.
13. **Evaluation Archive** — a development/evaluator-only content-free index of nonselectable historical profiles/evidence; it is not embedded as an installable ordinary runtime catalog.

An optional profile that is unadmitted, unavailable, unhealthy, or removed is never invoked through a fallback reference. The recommender selects a separately admitted exact mixed configuration containing the deterministic profile in that role. It does not rewrite a configuration at runtime or let a passing ASR inherit an unadmitted cleanup/router. When the shared Gemma artifact is installed for only one admitted role, installation/storage remains artifact-shared but execution acknowledges only that admitted role profile.

A profile passing alone does not prove the configuration. Configuration evidence must include ASR-to-cleanup-to-routing lease handoff, joint peak memory, end-to-end latency, and routing safety. If cleanup and routing share one artifact/runtime, an exact operation-authorized development configuration may retain one lease during Quality Lab evidence runs; an admitted exact configuration may do so in normal product use. The two states and receipts remain distinct.

## 8. Deterministic recommendation

The recommender takes:

- one immutable catalog snapshot;
- current architecture, machine ID, macOS/build, physical RAM, active processors;
- fresh reclaimable memory, pressure, thermal, Low Power Mode;
- available storage including side-by-side staging margin;
- locale and input contract;
- Apple system-capability availability;
- installed/verified receipts;
- active build capability (`ordinarySafe`, `developmentQuality`, or an exact `signedDistributionCandidate` that embeds the configuration/evidence/signing tuple plus its allowed claim scope and operator/speaker cohort);
- configuration admission by matching hardware/OS, claim-scope, and speaker/acoustic cohort.

### 8.1 Hard gates

A normal configuration is ineligible unless:

1. it is authorized for the active build capability and exact Fleck release, hardware/OS, claim-scope, and speaker/acoustic cohort;
2. architecture, OS, locale, ABI, and capabilities match;
3. identity and license/notice records are complete and reviewed;
4. storage can safely stage/install/update it;
5. joint residency can stay within admitted limits;
6. no revoked evidence, runtime incompatibility, or failed health state applies.

An `ownerPrivateBeta` configuration is ineligible under `ordinarySafe` or a general-population capability even on the same hardware. It may run in Quality Lab or in an exact signed-distribution-candidate capability only when that capability itself nests `claimScope: ownerPrivateBeta` and binds the same evidence/operator/speaker cohort. A signed candidate never broadens the underlying claim. Unknown probe, stale evidence, arithmetic overflow, ambiguous license, or any cohort mismatch fails closed to Built-in Safe.

### 8.2 Ranking

Only Fleck measurements influence rank:

1. zero protected/meaning violations and final-text accuracy;
2. first/final-word and priority-dictionary accuracy;
3. release-to-insertion p95 and cold-start reliability;
4. memory-pressure survival and peak footprint;
5. partial stability if the UI actually consumes partials;
6. install/staging size and energy.

Vendor benchmarks are provenance/prioritization only.

### 8.3 Adaptation during use

The selected configuration remains stable during one capture. Runtime pressure adaptation changes residency, not model identity mid-utterance:

- roomier/healthy Mac: keep the recently used model warm for the admitted window;
- constrained/pressure Mac: unload ASR immediately after finalization before cleanup loads;
- critical pressure/thermal/Low Power Mode: use a colder/deterministic safe path where the policy allows;
- model failure: mark health, release lease, use fallback for the next eligible stage.

Automatic profile switching between captures requires a stable reason and cooldown to avoid flapping. It is recorded in content-free diagnostics.

## 9. Artifact and runtime states

Artifact state:

```text
absent
 -> staging(real bytes)
 -> quarantined/verify
 -> verified(receipt)
 -> repairRequired
 -> removing
```

Runtime state:

```text
unavailable -> cold -> loading -> warm -> active -> idle
                              ^                  |
                              +-- hibernating <--+
                                      |
                                      v
                                     cold
```

`installed`, `verified`, `selected`, `warm`, `active`, `qualified`, and `releaseAdmitted` remain independent values.

Installation ownership is artifact-based, not role-label-based. A device-local ledger is keyed by exact artifact-manifest/receipt digest and records the cleanup/routing/profile/configuration references that currently depend on it. Gemma cleanup and Gemma Smart Sort may therefore expose two independently admitted role profiles while sharing one installed tree, one integrity state, and one runtime artifact lease. Reference counts are derived from the active verified catalog/configuration graph, never from mutable UI counters.

## 10. Installation, repair, update, removal

Reuse `EnhancedModelManager` and its current safety boundaries.

### 10.1 Install

1. Resolve one exact operation-authorized profile. `ordinarySafe` Settings accepts only system/deterministic profiles. An exact signed-distribution-candidate build may install/show only the embedded D5/D6 promotion-authorized tuple whose claim scope and cohort match the build capability. An explicit development/Quality Lab acquisition may accept an identity-verified, legally reviewed candidate, but it remains in a separate candidate state and cannot be automatically selected, recommended, or shown in normal Settings.
2. Present model name, role, download/installed size, and relevant terms acceptance.
3. Obtain explicit user authorization for that exact operation.
4. Recheck capacity, ABI, architecture, and authorization before network use.
5. Download selected revision-pinned files to a random staging root with real byte progress and authenticated resume data.
6. Verify the closed manifest, hashes, bytes, configs, notices, and path safety in quarantine.
7. Run bounded offline load/smoke/calibration.
8. Atomically commit to the content-addressed receipt-owned namespace.
9. Publish readiness only after the installation receipt is durable.

### 10.2 Repair

Repair downloads/verifies into new staging and atomically replaces the bad artifact tree only after every role lease is cold. It never edits verified files in place. All profiles referencing that artifact remain unavailable until the one replacement receipt verifies.

### 10.3 Update

Settings exposes Update only when the signed snapshot contains one transition whose predecessor configuration, previous 9E predecessor-record/D7 digest, previous package receipt digest, installed receipt schema, closed artifact manifests, runtime-compatibility revision, and predecessor-verification trust sequence/checkpoint all match the release-verified transition exactly. That trust sequence/checkpoint must also be the current externally pinned latest state used for the successor admission; a predecessor from any earlier trust checkpoint is ineligible. The successor must be the snapshot's one D5-promotion-authorized signed candidate configuration. The transition record is verification metadata, not a second selectable catalog entry.

An update requires enough checked free space for successor staging, both installed configurations, and the declared rollback reserve. It installs the new immutable artifact/profile set side-by-side, verifies and smokes every referenced role, then atomically switches one whole curated configuration and its artifact reference graph. Cleanup and routing may not split across old/new copies of what either configuration declares as one shared artifact. Failure or termination before the switch leaves the predecessor selected byte-for-byte; failure after the switch atomically restores the predecessor pointer before publishing readiness.

The exact predecessor artifact receipts remain referenced and undeletable for the transition's bounded rollback duration. Rollback is local, verifies those receipts again, drains successor leases, atomically restores the predecessor configuration, and retains/removes successor files only through their own receipt-scoped policy. When the window expires, bounded-storage cleanup may remove only unselected, lease-free, zero-reference predecessor trees whose exact receipt paths still match; otherwise it stops and reports the blocker. No valid transition means no Update action and no validated-update claim. Upstream `main` movement is never an automatic update.

### 10.4 Remove

Removal is requested for an installed artifact/configuration, not an individual role label. It previews every dependent role, switches all of them to safe fallbacks, drains all leases, revalidates the exact receipt-owned namespace, and removes the shared tree only when no retained selected/rollback configuration references it. Removing shared Gemma therefore makes both cleanup and Smart Sort local-model roles unavailable together; it never deletes one role's imaginary duplicate. The operation refuses broad, unresolved, symlinked, mismatched, or still-referenced paths. Apple-owned assets are released through the system API; Fleck never deletes them directly.

## 11. Settings interaction

Normal view:

```text
Enhanced local models

Dictation       Parakeet TDT 0.6B v2       Ready
Cleanup         Gemma 3 1B                 Ready
                Also powers Smart Sort
Recommended for this Mac                   Balanced quality

[Install / Repair / Update / Remove as applicable]
Advanced: Curated local models              >
```

Rules:

- one automatic recommendation;
- no normal primary model picker;
- when cleanup and routing share one artifact, Smart Sort explains that reuse instead of presenting a third install or duplicate storage row;
- one relevant action per row;
- genuine stage/byte progress;
- actionable, short failure copy with Retry/Repair;
- no indefinite “Loading”;
- detailed revision/license/checksum/evidence is available in a secondary detail sheet, not the main list;
- unadmitted candidates appear only in explicit Quality Lab/development builds.

Advanced admitted alternatives may show their tradeoff in one sentence, for example “Lower memory; slower/less accurate on your corpus.” The user can select one only after compatibility and admission checks.

## 12. Evidence and admission

Each profile progresses independently:

```text
documented
 -> identityVerified
 -> labCompatible
 -> FleckQualified(hardware cohort)
 -> twoDeviceAccepted(package + hardware cohorts)
 -> signedDistributionAccepted(channel + signing identity)
 -> releaseAdmitted(release + cohort)
```

Each configuration additionally requires joint-residency and end-to-end evidence. Hardware/OS, claim scope, and speaker/acoustic cohort remain part of every qualification and recommendation decision. A catalog update cannot promote state merely by editing metadata; it references an immutable reviewed evidence bundle and release decision.

The embedded catalog records the highest evidence state available when the exact app is built (for example `twoDeviceAccepted`) and the signed-distribution capability is the sole runtime authorization for its exact tuple/scope/cohort. After D6, D7 is a canonical detached governance record signed by the approved owner release-admission identity. It binds the already signed ZIP, canonical app tree, executable, D6 evidence receipt, catalog/configuration/profile identities, signing identity, hardware/claim/speaker cohorts, and decision. Release tooling verifies the trusted key fingerprint and joins that record with the embedded snapshot to report `releaseAdmitted`; D7 controls distribution and claims, not runtime unlocking. The app bundle is not rebuilt or mutated after D6, and the same binary already fails closed to the exact embedded capability.

## 13. License/distribution gate

Engineering must preserve all layers:

- runtime source license;
- conversion code/notices;
- upstream checkpoint terms;
- converted artifact terms/attribution;
- tokenizer/auxiliary component terms;
- Fleck modifications and required notices.

Known blockers from primary-source research include a license inconsistency in the auxiliary `parakeet-ctc-110m-coreml` repository metadata/card and Gemma terms/acceptance requirements. Unknown or contradictory records block candidate acquisition where the applicable terms cannot be established and always block distribution admission. Fleck never embeds developer credentials or accepts model terms on a user's behalf.

### 13.1 Development candidate acquisition

Qualification cannot require prior release admission. Development/Quality Lab builds therefore have a separate exact operation:

- profile state must be at least `identityVerified` and have a complete selected-file manifest;
- applicable terms/license ambiguity must be resolved for the intended local evaluation operation;
- the user explicitly authorizes that exact profile and byte total;
- the existing staging, hash, path, receipt, cancellation, repair, and removal protections remain mandatory;
- the receipt is marked `developmentCandidate` and stored/selected only in the candidate lane;
- automatic recommendation, normal Settings visibility, ordinary-release composition, and release claims remain forbidden until later admission.

## 14. Non-goals

- Arbitrary repository/URL installation.
- Downloading every export in a family.
- Showing unqualified candidates as choices.
- Choosing from vendor WER alone.
- Keeping ASR and cleanup simultaneously resident on constrained hardware.
- Adding a new downloader or filesystem namespace.
- Generic capability graphs before real variation justifies them.
- Treating Apple system assets as Fleck-owned artifacts.
- Bundling weights in ordinary Fleck.
