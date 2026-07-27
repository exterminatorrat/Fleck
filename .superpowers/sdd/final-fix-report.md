# Clean Dictation Final Fix Report

Date: 2026-07-28
Reviewed base: `ccd1a93414b28925c397a40b68d6e4e90ee08d59`
Branch: `codex/clean-dictation`

## Outcome

The final automated fix wave closes the reviewed code-level blockers without
claiming physical-device, legal, signing, notarization, or store approval.

Enhanced Local remains a developer-only candidate. The ordinary package graph
does not link FluidAudio into Motes, does not define
`CLEAN_DICTATION_ENHANCED_CANDIDATE`, normalizes stale Enhanced preferences to
Standard, and omits Enhanced settings and adapter code. Candidate evaluation is
an explicit opt-in:

```sh
MOTES_ENHANCED_CANDIDATE=1 swift test
```

The release validators reject a set `MOTES_ENHANCED_CANDIDATE` variable before
building or inspecting an artifact.

## Findings and fixes

### Critical: candidate SDK present in the ordinary release

- RED: the initially guarded release executable was `10,798,888` bytes.
  `nm -a` found `42,783` matches for candidate terms, and the release
  `Objects.LinkFileList` named every FluidAudio object file.
- The first source-only compile guard reduced the executable only to
  `10,688,968` bytes and still left `42,379` matching symbols. This proved that
  SwiftPM's unconditional product edge linked the SDK regardless of source
  reachability.
- GREEN: `Package.swift` now selects only the app product edge and debug/test
  compile definitions when `MOTES_ENHANCED_CANDIDATE=1`. The top-level package
  dependency and `Package.resolved` pin remain checked in.
- The complete FluidAudio adapter, inference implementation, and Enhanced audio
  implementation are compiled only in the opt-in candidate graph.
- Fresh ordinary release evidence:
  - executable size: `3,585,432` bytes;
  - FluidAudio entries in
    `.build/arm64-apple-macosx/release/Motes.product/Objects.LinkFileList`: `0`;
  - `nm -a` matches for
    `FluidAudio|Parakeet|AsrModels|ModelHub|FluidEnhancedSpeech`: `0`.
- `Scripts/check-release-size.sh` now rejects active release FluidAudio imports,
  Enhanced construction, candidate UI strings, candidate SDK symbols, and
  bundled model assets.

### High: permission and microphone boundary

- RED: focused Enhanced permission/device tests initially failed to compile
  because the adapter had no engine-aware permission or saved-device selection
  boundary.
- GREEN: Enhanced requests microphone access only, while Standard continues to
  require microphone and Speech Recognition access. Both adapters use the
  shared saved microphone UID selection and automatic fallback behavior.

### High: live availability and actionable failure copy

- RED: availability was inferred from recovery-button absence rather than
  current OS, architecture, permissions, recognizer, model, and Foundation
  Model capability.
- GREEN: runtime availability is evaluated from those live inputs and refreshes
  after startup, permission requests, and preference changes. Standard failure
  copy distinguishes microphone, Speech Recognition, and missing on-device
  English recognition.
- Pure capability tests inject the candidate policy. Production defaults to the
  package feature flag.

### Critical: focused cancellation after an editor commit

- RED: the receipt-based cancellation tests failed to compile because editor
  and persistence commit receipts, conditional rollback, and compensating save
  did not exist.
- GREEN: the editor retains exact attributed content, selection, and origin
  through the terminal boundary. Cancellation rolls back only an exact match,
  invalidates stale undo state, and compensates an already-started persistent
  save.
- The real integration test uses `EditorCommands`, `AppState`, and
  `LocalStore`. With the first save suspended it recorded
  `["Before committed", "Before"]`, and the editor, app state, and persisted
  workspace all ended at `"Before"`.
- If exact rollback is unsafe, later user content is preserved and the result
  exposes the destination instead of pretending cancellation succeeded.

### High: terminal recovery actions

- RED: the recovery tests failed to compile before explicit action types and
  runtime dispatch existed.
- GREEN:
  - successful Smart Capture exposes Undo;
  - safe undo persists removal and deletes its history record;
  - unsafe undo selects and opens the exact destination;
  - durable unsaved recovery opens Dictation History;
  - simultaneous history and destination failure preserves an in-memory Copy
    action;
  - failed focused cancellation opens the affected destination.
- The production capsule exposes keyboard/VoiceOver-labelled actions without
  activating the app for passive status publication. Deliberate action can
  activate the relevant window.

### High: history durability propagation

- RED:
  `simultaneousHistoryAndDestinationFailurePreservesInMemoryCopy` observed no
  copyable transcript.
- GREEN: history writes report durability to the coordinator. In-memory copy
  remains available when neither history nor destination is durable.

### Medium: shortcut threshold timing

- The fixed-delay test wait was replaced with explicit observation of the
  coordinator phase. Production shortcut timing was not changed.

### Labels and upstream warning

- Candidate debug settings use explicit `Standard — Apple Speech` and
  `Enhanced Local` labels.
- FluidAudio still emits its pre-existing warning for the unhandled
  `Sources/FluidAudio/ASR/Parakeet/Unified/benchmark.md` during opt-in candidate
  builds. No dependency fork or unrelated upstream patch was introduced.

## TDD evidence

Representative RED observations:

1. `debugBuildEnablesEnhancedCandidateEvaluation` failed to compile before
   `CleanDictationFeatures` existed.
2. Enhanced permission and device-selection tests failed to compile on missing
   initializer arguments and adapter APIs.
3. `simultaneousHistoryAndDestinationFailurePreservesInMemoryCopy` failed with
   `nil` instead of the transcript.
4. Focused cancellation tests failed to compile on missing receipt and
   compensation APIs.
5. Recovery action tests failed to compile on missing action and result types.
6. Binary inspection disproved the first source-only release guard:
   `10,688,968` bytes and `42,379` candidate symbol matches.
7. The first default-off test run exposed remaining candidate-only test
   references and global-policy coupling. Minimum test regions were guarded,
   while pure model-manager and capability tests received injected policy.

Representative focused GREEN evidence:

- focused cancellation compensation fake: passed;
- real editor/AppState/LocalStore compensation: passed;
- terminal Undo/open destination/open history/copy paths: passed;
- focused editor group: 10 passed;
- AppState dictation group: 18 passed;
- accessibility group: 6 passed;
- candidate coordinator group, including explicit shortcut phase observation:
  passed.

## Final automated verification

```sh
env -u MOTES_ENHANCED_CANDIDATE swift package resolve
env -u MOTES_ENHANCED_CANDIDATE swift test
MOTES_ENHANCED_CANDIDATE=1 swift test
env -u MOTES_ENHANCED_CANDIDATE swift build -c release
env -u MOTES_ENHANCED_CANDIDATE Scripts/check-release-size.sh .build/release/Motes
env -u MOTES_ENHANCED_CANDIDATE Scripts/validate-macos.sh
git diff --check
```

Observed results:

- ordinary default-off suite: `274` tests passed;
- opt-in candidate suite: `307` tests passed;
- release executable: `3,585,432` bytes;
- release link-list FluidAudio objects: `0`;
- release candidate SDK symbol matches: `0`;
- release model asset, UI, source, and symbol assertions: passed;
- full macOS validation: passed on macOS `26.2`, Xcode `26.6`,
  Apple Swift `6.3.3`;
- opt-in release gate negative test: exit `2` with
  `unset MOTES_ENHANCED_CANDIDATE before validating an ordinary release`;
- whitespace validation: passed.

`Package.resolved` retains FluidAudio `0.15.5` at revision
`19600a485baa4998812e4654b70d2bab8f2c9949`. Its origin hash changed because
the package manifest changed.

## Required manual evidence still outstanding

Automated evidence is not release approval. The following remain required:

- macOS 26 Apple silicon, macOS 14/15 Apple silicon, and Intel macOS 14+
  behavior;
- built-in, wired, and wireless microphones, saved UID fallback, disconnect,
  and reconnect;
- real permission grant/deny prompts and System Settings recovery;
- Standard on-device English asset availability and offline behavior;
- real Enhanced model download, cancellation, resume, low-disk, checksum,
  repair, update, and deletion;
- privacy-safe corpus accuracy for names, numbers, negation, corrections,
  tasks, accents, and noise;
- cold/warm latency, memory, energy, thermal, and battery measurements;
- shortcut, focus, window, capsule, keyboard, VoiceOver, and Reduce Motion
  interaction;
- sleep/wake and audio interruption recovery;
- physical History, pasteboard Copy, Undo, and Open Destination interaction;
- legal, license, attribution, SBOM, model redistribution, and Mac App Store
  review;
- signed, hardened, notarized, packaged, and store-submission artifacts.

Enhanced Local must remain default-off until those gates have recorded evidence
and an explicit release decision.
