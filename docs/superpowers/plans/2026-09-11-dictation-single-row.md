# Single-row dictation capsule implementation plan

> **For the implementation worker:** Continue in the same Capy Sol High task.
> Use the test-first and verification guidance, but the explicit task contract
> overrides generic skill instructions to create a fresh implementer, commit,
> or ask again whether to execute. Harry has approved the single-row design and
> requested implementation. Corrections return to the same worker; the reviewer
> must be a new Astra High task.

**Goal:** Remove active destination/mode headers in both dictation modes while
preserving controls, truthful processing feedback, and centered terminal panels.

**Architecture:** Delete header-specific layout and sizing rather than adding a
visibility option. Reuse the existing compact listening and processing cores;
leave capture context, accessibility copy, and chooser-aware native geometry
unchanged.

**Tech stack:** Native macOS 14+, Swift 6, SwiftUI, AppKit, Swift Testing. No new
dependencies.

## Global constraints

- This is the historical local implementation plan. Subsequent authorization
  permits publishing the candidate and these portable documents, not merging or
  promoting acceptance. Original local receipts remain outside the repository.
- Work only in the isolated `codex/capsule-single-row-flec5` worktree, identified
  by `$FLECK_WORKTREE` in the commands below.
- Preserve accepted dd5c3e2 plus the reviewed running 11-file delta described in
  `../specs/2026-09-11-dictation-single-row-design.md`.
- Only `Sources/FleckApp/DictationCapsule.swift` and
  `Tests/FleckAppTests/DictationCapsuleVisualCaptureTests.swift` may receive new
  product/test edits. Expand ownership explicitly before any other edit.
- During implementation, keep all changes uncommitted with no GitHub writes or
  registry promotion. Publication is a separate authorized phase.
- Use exact anchored discovered identifiers and record actual matched/executed
  counts. A build or test listing is not a test pass.
- Serialize compiler/native-host use. Check ownership and running compilers
  before execution; do not overlap another Fleck build.
- No private notes, microphone, model download, TCC reset, Gatekeeper bypass, or
  forced process termination.

## Packet 1: Assemble, reproduce, and remove the header

**Owned files:** the two source/test paths above. The primary owns this plan and
the design document. Scratch evidence belongs outside the repository, identified
by `$FLECK_LOCAL_EVIDENCE`. The commands below use `$FLECK_NATIVE_TEST_HELPER` for
the reviewed native-host helper and `$FLECK_PRIOR_EVIDENCE` for the prior local
replacement evidence. These are maintainer-supplied paths, not bundled files.

**Interfaces:** retain `size(for: DictationCapsuleStatus, measuredWidth: CGFloat?,
widthCeiling: CGFloat?)`, `listeningCore(at:)`, `processingCore`, all context data,
and the chooser/presentation APIs. Remove only header-specific APIs with no
remaining consumer, updating every caller inside the owned files.

- [x] Verify canonical acceptance, the clean new worktree, and the inherited
  running-source delta. Export `git diff --binary --full-index` from the preserved
  replacement worktree, require SHA-256 `0c14cc7ea69b640c9926f9a7c55ad9dc20b612585722b2501f1c5fb275875943`,
  apply it to the new worktree, and verify all 11 files byte-for-byte. Copy the
  existing verification-only AppKit host at its pinned hash; never overwrite a
  preexisting different file.

- [x] Add this behavioral regression before editing product code. It uses
  existing `visualProbe` and `visualCaptureSessionID` helpers in the owned test
  file. Keep assertions for the centered waveform, fixed controls, actual frame,
  and full VoiceOver destination in the surrounding regression coverage.

```swift
@Test @MainActor
func DictationCapsuleBothModesOmitActiveHeaders() throws {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  defer { controller.dismiss() }
  let statuses: [DictationCapsuleStatus] = [
    .listening, .finalizing, .cleaning, .routing, .saving
  ]
  for mode in [DictationMode.focused, .smartCapture] {
    for dock in DictationCapsuleDock.allCases {
      for status in statuses {
        panel.orderOut(nil)
        controller.setDock(dock)
        controller.render(DictationCapsuleContext(
          status: status,
          detailText: "Synthetic captured destination",
          compactDetailText: "Synthetic context",
          sessionID: visualCaptureSessionID,
          trigger: .doubleTap,
          mode: mode,
          isHandsFree: true
        ))
        let host = try #require(panel.contentView)
        host.layoutSubtreeIfNeeded()
        #expect(visualProbe("fleck-rail-context", in: host) == nil)
        #expect(panel.frame.size == DictationCapsuleController.size(for: status))
        #expect(panel.frame.height == 36)
      }
    }
  }
}
```

- [x] Run the new regression against the inherited source with the reviewed
  nonempty native host helper. Expected RED: Smart Capture/contextual cases
  still expose the header and a 52-point frame; a compile-only failure does not
  count. Save the exact log and lock comparisons.

```bash
bash "$FLECK_NATIVE_TEST_HELPER" \
  "$FLECK_WORKTREE" '' \
  '^FleckAppTests\.DictationCapsuleBothModesOmitActiveHeaders\(\)$'
```

- [x] Delete `activeHeaderText`, `contextualActiveHeight`,
  `capturedContextText`, and the conditional header wrappers. Route processing
  directly to `processingCore` and the timeline directly to `listeningCore`:

```swift
case .finalizing, .cleaning, .routing, .saving:
  processingCore
```

```swift
TimelineView(
  .periodic(
    from: .now,
    by: DictationWaveformRefreshSchedule.interval(reduceMotion: reduceMotion)
  )
) { context in
  listeningCore(at: context.date)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel("Dictation listening")
}
```

- [x] Remove the forwarding context-size overload and use the status API at
  its owned callers, retaining the actual chooser-aware width inputs:

```swift
size: Self.size(
  for: currentContext.status,
  measuredWidth: presentation.measuredWidth,
  widthCeiling: presentation.widthCeiling
)
```

- [x] Update existing contextual tests to the deliberately changed compact
  behavior. Replace header-presence/52-point expectations with header absence
  and 36-point height; retain bounds, mode coverage, centering, docking,
  quiet/live/reset, hover stability, control-target sizes, VoiceOver, and
  terminal-position assertions. Rename only tests whose names incorrectly
  promise the removed expanded layout, documenting the old/new identifier in
  evidence. Do not remove tests or safety assertions merely to pass.

- [x] Update synthetic fixtures so both focused and Smart Capture use the
  compact size. Keep quiet/live/hover, all docks, light/dark, long-context
  inputs, processing states, and saved/chooser fixtures. Let the native host
  settle after changing hover state before capturing so a timer frame is not
  mislabeled as a Stop/Cancel frame. Capture only synthetic windows.

- [x] Run GREEN for the new test, then the focused regression set. Preserve
  all inherited waveform behavior and editor files byte-for-byte. Run
  `git diff --check` and verify no remaining header-specific symbols or
  52-point layout branches in product code.

## Packet 2: Enhanced verification and replacement artifact

**Ownership:** no new product files. Existing unmodified enhanced resolver and
builder are execution inputs. Scratch orchestration and evidence may be created
under `$FLECK_LOCAL_EVIDENCE`.

- [x] Snapshot root, enhanced-reference, and Gemma lockfiles before every run;
  compare them after success or failure. Use the existing resolver with a new
  scratch path and the reviewed AppKit helper, as in the prior replacement
  evidence at `$FLECK_PRIOR_EVIDENCE/packet-d/TEST-COMMAND.txt`.
  Preserve the generated enhanced lock, not just the restored ordinary lock.
- [x] Reuse the previous 94 actual identifiers from
  `$FLECK_PRIOR_EVIDENCE/packet-d/requested-94-identifiers.txt`,
  adjusting only deliberately renamed tests and adding the new regression.
  Discover the actual canonical identifiers before constructing the anchored
  union. Require every requested identifier to match and execute, with zero
  failures. Preserve all five editor-polish regressions.
- [x] Build with the unchanged native packager:

```bash
cd "$FLECK_WORKTREE" && \
  bash Scripts/build-parakeet-test-app.sh
```

- [x] Retain the initial `.build/parakeet-test/Fleck.app` output and copy it to
  a new `.build/single-row/Fleck Single Row.app` bundle without overwriting
  either earlier running candidate. Verify nested/deep signatures, arm64,
  macOS 14 floor, stable `com.harryjin.fleck`, exact staged bytes, and unchanged
  resources/model manifests/designated requirement.
- [x] Compare effective dependency resolution with the previously reviewed
  replacement build log and generated lock, including Gemma dependencies.
  Do not infer parity from restored source lockfiles. Stop on an unexplained
  dependency change rather than introducing an upgrade.
- [x] Return exact source/diff/bundle hashes, test commands/counts/logs, native
  captures, resource/signature evidence, and a safe resource boundary. Do not
  launch or stop the personal app from the worker.

## Parent verification, review, and switch

- [x] Inspect the actual incremental diff against the preserved 11-file running
  baseline; ensure only the two owned product/test files changed and the two
  requested documents were added.
- [x] Independently rerun the focused enhanced set and inspect actual synthetic
  single-row captures and settled saved/chooser frame measurements.
- [x] Verify the exact candidate binary, resources, dependency evidence, and
  source identity. Obtain a new independent Astra High `ship` verdict; route
  any correction to the same Sol worker and repeat verification/review.
- [x] Recheck the actual running bundle/PID/hash and idle capsule. Continue the
  previously authorized local replacement workflow using normal termination,
  never force-quit. Preserve the current bundle for rollback, launch the exact
  reviewed new bundle, then verify its PID/path/hash and idle capsule. Stop for
  the user if there is an active capture, a shutdown prompt, or a permission gate.
- [x] Report the plan paths, source and rendering result, actual test counts,
  reviewer verdict, running candidate identity, and remaining physical/microphone
  limitations. Do not promote the accepted registry or claim release acceptance.

## Completion evidence

The same Sol High worker implemented the two-file incremental change. The parent
independently executed 95 matched tests: 95 started, 95 passed, zero failures.
All 11 settled native positioning scenarios remained contained and centered
within 0.5 points. All three source lockfiles were restored unchanged, and actual
app and Gemma dependency resolutions matched the prior running build.

Fresh Astra High Task 5 returned `ship` with no findings for the written plans,
source/tests, and exact candidate bundle. The reviewed tracked full-index diff
SHA-256 is `db01ef6c7c0fcdd83f73915d7bc97e7884bf0e558e628d5b16c09ac154230332`.

The parent confirmed the old app was idle and requested normal termination.
It exited before the exact reviewed `.build/single-row/Fleck Single Row.app`
bundle was launched. At local handoff, it was the sole running
`com.harryjin.fleck` app, with executable
SHA-256 `31e8ffec7a35670f57051fd1ab84c01fb5167f0cfd388153bc1096f9b339e1e0`.
Its 46 × 24-point idle capsule was verified through native accessibility and a
capsule-only screenshot. The prior `Fleck Capsule Fix.app` remains intact for
rollback.

Worker evidence is retained under `$FLECK_LOCAL_EVIDENCE/packet-e/`.
Independent execution, artifact checks, native captures, and the personal runtime
receipt are retained under `$FLECK_LOCAL_EVIDENCE/parent-verification/`; none are
Git-tracked publication artifacts.
At local handoff the changes were uncommitted. These remain candidate results: the canonical
accepted registry is unchanged, and no microphone trial, physical MacBook smoke
check, notarization, or release acceptance is claimed.
