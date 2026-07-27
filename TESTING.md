# Testing Motes on macOS

> **Release approval is blocked.** Automated checks can validate code and a
> SwiftPM executable, but they cannot approve a release. Enhanced Local is a
> non-shippable candidate until the pinned model materially beats Standard on
> the real-device corpus and every manual gate below has recorded evidence.

## Requirements

- A Mac running macOS 14 Sonoma or later.
- Xcode 16 or later, installed from Apple.
- The Xcode command-line tools selected with `xcode-select`.
- A local checkout of this repository on the branch or pull request being tested.

The package uses Swift tools version 6.0 and native AppKit/SwiftUI APIs. Clean
Dictation adds the checksum-pinned FluidAudio Swift package; the optional model
is downloaded separately and must never be bundled in a release artifact.

## Quick start from Terminal

From the repository root:

```sh
xcode-select -p
swift --version
Scripts/validate-macos.sh
swift run Motes
```

The final command stays attached to Terminal. Look for the note icon in the macOS menu bar, click it to open the notes panel, and press `Control-C` in Terminal when you want to stop the app.

`Scripts/validate-macos.sh` verifies the host OS, runs the complete test suite, creates a release build, checks the release executable against the 15 MB budget, and prints the exact executable path. It does not launch or terminate the app because visual testing should remain under the tester's control.

## Run from Xcode

1. Open the package:

   ```sh
   open Package.swift
   ```

2. Wait for Xcode to finish resolving the package.
3. Select the **Motes** scheme and **My Mac** destination.
4. Choose **Product → Test** (`Command-U`).
5. Choose **Product → Run** (`Command-R`).
6. Click the note icon in the macOS menu bar.
7. Use Xcode's Stop button when testing is finished.

The project is currently a Swift Package executable, not a signed distributable `.app`. Launch-at-login must be validated later from the packaged and signed application; it may report an error when launched directly through SwiftPM or Xcode's package runner.

## Clean Dictation release gates

### Automated gate

Run from the repository root:

```sh
swift package resolve
swift test
swift build -c release
Scripts/check-release-size.sh
Scripts/validate-macos.sh
rg -n 'NSEvent\.addGlobalMonitorForEvents|offlineMode = false|AsrModels\.downloadAndLoad' \
  Sources
git diff --check
git status --short
```

`Scripts/check-release-size.sh` accepts the current executable, a directory
containing `Motes`, or a future `.app` containing `Contents/MacOS/Motes`. It
keeps the 15 MiB executable budget and scans the corresponding artifact root
for `.mlmodel`, `.mlpackage`, `.mlmodelc`, exact `coremldata.bin`/`weight.bin`
names, and `.bin` files under model bundle or model directory paths. An
unrelated `.bin` outside a model path is allowed. The same gate asserts:

- `ModelHub.offlineMode = true` is present.
- `ModelHub.offlineMode = false` is absent.
- production sources do not call `AsrModels.downloadAndLoad`.
- `EnhancedSpeechCapture` does not call `ModelHub.download` or
  `ModelHub.fetchFile`.
- production sources do not call `NSEvent.addGlobalMonitorForEvents`.

#### Recorded size evidence — 2026-07-28

The Swift production/package base was
`a30ce8b5b801bccb429fd236f3b8632ff146f473`; Task 12 changes only the release
script and documentation.

- Host used for the measurement: Apple M1, arm64, macOS 26.2 (25C56).
- Current release executable: **11,068,888 bytes (10.6 MiB)**.
- Budget: **15,728,640 bytes (15 MiB)**; it was not raised.
- Pre-FluidAudio baseline:
  `d9e5c658586446e638a85833042af59087a42498`, the parent of the dependency
  introduction commit `c892872`.
- Baseline release executable: **1,815,544 bytes (1.7 MiB)**.
- FluidAudio code/dependency delta: **+9,253,344 bytes (+8.8 MiB)**.
- Optional pinned model, measured separately from the executable:
  **464,413,247 bytes (442.9 MiB)**.
- This is executable evidence only. No signed/exported `.app` exists, so app
  bundle size, signing, and notarization remain pending.
- The release build emits a dependency warning that FluidAudio's
  `Sources/FluidAudio/ASR/Parakeet/Unified/benchmark.md` is unhandled. It is not
  bundled model evidence and does not waive any release gate.

The baseline was reproduced without switching or modifying the candidate
branch:

```sh
baseline_root="$(mktemp -d)"
git archive d9e5c658586446e638a85833042af59087a42498 |
  tar -x -C "$baseline_root"
(
  cd "$baseline_root"
  swift package resolve
  swift build -c release
  wc -c .build/release/Motes
)
```

#### Test-first artifact evidence

Before the release script change, temporary artifacts containing each of
`.mlmodel`, `.mlpackage`, `.mlmodelc`, `weight.bin`, and `coremldata.bin` all
incorrectly exited 0. After the change, every forbidden case exits 1 and
prints its exact path. A clean artifact and an unrelated
`Resources/Cache/payload.bin` both exit 0. Executable-path, generic-directory,
and `.app`-directory inputs also exit 0 when clean. All fixtures were created
under the system temporary directory; none are committed.

### Manual release blockers

Every item below is open even when the automated gate is green. Replace
`unassigned` with a named accountable owner and attach the required evidence;
do not change the status from pending based on CI alone.

#### Privacy-safe real-device quality corpus

- **Status:** PENDING — manual release blocker
- **Owner:** Product/release owner (unassigned)
- **Required evidence:** Corpus version and consent/provenance record; per-engine
  WER; proper-name, number, negation, and task-preservation failure counts;
  cold and warm finalization latency; predeclared material-improvement
  criterion; signed Standard-versus-pinned-model decision.
- **Exact procedure:** On real Apple-silicon hardware, use the same
  privacy-safe utterances and reference transcripts for Standard and manifest
  revision `ee09c569f73759e6d44c9bd16766f477b2b36d39`. Run cold and warm captures,
  retain raw outputs and timestamps, calculate WER, manually classify every
  required preservation failure, and compare latency. Record the decision
  against the criterion defined before reviewing results.
- **Release rule:** If Enhanced does not materially beat Standard without
  unacceptable latency or resource cost, keep Tasks 0–2 infrastructure out of
  release UI and do not claim Enhanced Local ships.

#### Apple-silicon macOS matrix

- **Status:** PENDING — manual release blocker
- **Owner:** QA owner (unassigned)
- **Required evidence:** Dated results, hardware identifiers, OS/build numbers,
  logs, and failures for macOS 26 plus macOS 14 or 15 on Apple silicon.
- **Exact procedure:** Install the same candidate artifact on clean accounts on
  each OS target; run permission, Standard, cleanup availability, model
  lifecycle, focused capture, Smart Capture, history, sleep/wake, and ordinary
  notes checks; attach the completed matrix. The macOS 26.2 build result above
  does not satisfy this functional matrix.

#### Intel compatibility

- **Status:** PENDING — manual release blocker
- **Owner:** QA owner (unassigned)
- **Required evidence:** Intel Mac model, macOS 14+ build number, launch and
  ordinary-note results, Standard availability behavior, and proof that
  Enhanced remains unavailable.
- **Exact procedure:** Build or install the same candidate on an Intel Mac
  running macOS 14 or later; exercise launch, note editing/persistence,
  Standard capture where supported, Settings, and Enhanced capability
  messaging; attach logs and screenshots.

#### Microphones, permission, and device transitions

- **Status:** PENDING — manual release blocker
- **Owner:** QA owner (unassigned)
- **Required evidence:** Results for built-in, wired, and delayed-wake wireless
  microphones; first-run grant and denial; sleep/wake; active-capture device
  disconnect; selected-device fallback; audio-free persistence inspection.
- **Exact procedure:** On a clean account reset microphone and speech
  permissions, test grant and denial separately, then repeat capture with each
  microphone class. For wireless, begin from a sleeping device and record wake
  delay. Disconnect during capture and sleep/wake between captures. Inspect
  Application Support afterward and confirm it contains no captured audio.

#### Capability and Enhanced model lifecycle

- **Status:** PENDING — manual release blocker
- **Owner:** QA/product owner (unassigned)
- **Required evidence:** Results for Apple Intelligence disabled/not ready,
  Standard on-device recognition unavailable, consent, download, cancel,
  resume, low disk, checksum failure, repair, update, delete, cold load, warm
  use, idle unload, memory pressure, corruption, and backup exclusion.
- **Exact procedure:** Exercise each state independently on real hardware using
  the pinned manifest. Capture the visible state, filesystem state, network
  request URL, byte/checksum result, fallback behavior, and post-relaunch
  result. Inspect model resource values to verify backup exclusion and confirm
  ordinary notes work before install, during failure, and after delete.

#### Interaction, lifecycle, routing, and history

- **Status:** PENDING — manual release blocker
- **Owner:** QA owner (unassigned)
- **Required evidence:** Results for shortcut conflicts, rapid tap, Escape,
  active/hidden/pinned/behind-another-app windows, sleep/wake, device
  disconnect, focused rollback/Undo, title-only routing/Inbox, history
  copy/open/delete/purge/clear, and ordinary notes with no model installed.
- **Exact procedure:** Run every interaction from both idle and active capture
  states. Use uniquely identifiable note-body secrets to confirm routing sees
  titles only. Force failed cleanup and low-confidence routing, verify raw/Inbox
  fallback, advance a test clock or use dated fixtures for 30-day purge, and
  inspect the saved note/history after each terminal path.

#### VoiceOver and Reduce Motion

- **Status:** PENDING — manual release blocker
- **Owner:** Accessibility QA owner (unassigned)
- **Required evidence:** VoiceOver transcript/recording, keyboard-only results,
  focus order and control names, Reduce Motion behavior, and unresolved
  accessibility defects.
- **Exact procedure:** Enable VoiceOver and operate Settings, the microphone
  control, capsule, consent/model states, focused capture, Smart Capture,
  errors, and history without a pointer. Then enable Reduce Motion, repeat
  start/finalize/cancel/error transitions, and record that content and status
  remain understandable without motion.

#### Memory, energy, and thermal behavior

- **Status:** PENDING — manual release blocker
- **Owner:** Performance owner (unassigned)
- **Required evidence:** Instrument trace and tabulated peak/idle memory, cold
  and warm finalization latency, idle CPU, energy impact, thermal state,
  memory-pressure behavior, and verified idle model-resource unload.
- **Exact procedure:** Run the release candidate on representative
  Apple-silicon hardware. Measure ordinary notes with no model, Enhanced cold
  load, repeated warm captures, post-capture idle, and memory pressure using
  Instruments and Activity Monitor. Record timestamps, capture duration,
  process memory, CPU, energy, thermal observations, and time/resources after
  unload; compare against the quality decision.

#### SDK and model legal terms

- **Status:** PENDING — manual release blocker
- **Owner:** Legal/release owner (unassigned)
- **Required evidence:** Dated written approval of the exact FluidAudio SDK
  license/notices, model and base-model terms, commercial distribution rights,
  and downloaded-data distribution design.
- **Exact procedure:** Review the exact dependency revision and
  `ThirdPartyNotices.md`, retrieve and archive the governing terms for the
  manifest model/base model, map every obligation to the binary, downloaded
  data, repository, product UI, and store listing, and obtain written approval.

#### Checksum manifest approval

- **Status:** PENDING — manual release blocker
- **Owner:** Release/security owner (unassigned)
- **Required evidence:** Signed review of model ID, immutable revision, total
  byte count, per-file paths, byte counts, SHA-256 values, allowlisted host, and
  independently reproduced download verification.
- **Exact procedure:** Download the pinned revision outside the app from the
  allowlisted origin, reject redirects outside policy, enumerate files, compute
  every byte count and SHA-256, compare against
  `EnhancedModelManifest.json`, and archive the command output and reviewer
  approval.

#### Attribution placement

- **Status:** PENDING — manual release blocker
- **Owner:** Legal/product owner (unassigned)
- **Required evidence:** Approved attribution copy and screenshots from the
  actual signed app plus final store listing/package locations.
- **Exact procedure:** Resolve every attribution obligation from legal review,
  place the approved notices in the packaged product and required listing,
  install the signed artifact, navigate to each notice, and archive screenshots
  and the packaged notice files.

#### Software bill of materials

- **Status:** PENDING — manual release blocker
- **Owner:** Release/security owner (unassigned)
- **Required evidence:** Reviewed SBOM tied to the final source commit and
  artifact hashes, including FluidAudio and transitive dependencies, licenses,
  model identity/revision, and shipped resources.
- **Exact procedure:** Generate Swift dependency data with
  `swift package show-dependencies --format json`, inventory final artifact
  contents and checksums, add the external model record, reconcile the result
  against `Package.resolved` and legal notices, then sign and archive the SBOM.

#### Signed `.app`, signing, and notarization

- **Status:** PENDING — manual release blocker
- **Owner:** Release owner (unassigned)
- **Required evidence:** Exported `.app` hash and size, signing identity/team,
  entitlements, `codesign` verification, notarization submission/result, staple
  result, and Gatekeeper assessment.
- **Exact procedure:** Produce the actual release `.app`, record its exported
  path as `artifact_path`, and stop if
  `test -f "$artifact_path/Contents/MacOS/Motes"` fails. Measure it and run
  `Scripts/check-release-size.sh "$artifact_path"`; inspect with
  `codesign -d --entitlements :- "$artifact_path"`; run `codesign --verify
  --deep --strict --verbose=2 "$artifact_path"`; submit with `xcrun notarytool`,
  staple the accepted ticket, and verify with `spctl --assess --type execute
  --verbose=4 "$artifact_path"`. SwiftPM executable checks cannot satisfy this
  gate.

#### Mac App Store rules

- **Status:** PENDING — manual release blocker
- **Owner:** Store/legal owner (unassigned)
- **Required evidence:** Written review of current Mac App Store rules for
  downloaded data-only Core ML assets, sandbox/network/file-access behavior,
  privacy disclosures, in-app attribution, and an accepted final submission or
  documented release-channel decision.
- **Exact procedure:** Review the rules current on submission day against the
  signed app and exact model download flow, complete privacy and content
  declarations, validate in the App Sandbox and an App Store distribution
  build, submit through App Store Connect, and archive review correspondence
  and disposition.

## Functional test checklist

### Menu bar and windows

- [ ] The note icon appears in the menu bar after launch.
- [ ] Clicking the icon opens the panel without a noticeable delay.
- [ ] Clicking the pin button opens the separate floating notes window.
- [ ] Changing panel width, height, glass opacity, and theme takes effect.
- [ ] Light, dark, and system themes remain legible.

### Notes and tabs

- [ ] `Command-T` creates a note.
- [ ] Clicking a tab selects the correct note.
- [ ] Dragging one tab onto another reorders it.
- [ ] The tab context menu can pin, unpin, move, and close a note.
- [ ] Pinned notes remain grouped at the beginning of the tab strip.
- [ ] Closing the final note leaves a new empty note rather than an unusable panel.
- [ ] Configured next/previous-note shortcuts wrap at both ends.

### Native editor

- [ ] Typing, selecting, copying, pasting, undoing, and redoing behave normally.
- [ ] Bold, italic, underline, strikethrough, and an installed font apply only to the selection.
- [ ] A formatting command with no selection changes subsequent typing.
- [ ] `- ` and `1. ` lists continue when Return is pressed.
- [ ] Return on an empty list item exits the list.
- [ ] Tab and Shift-Tab indent and outdent selected list lines.
- [ ] Disabling automatic lists in Settings prevents list continuation.
- [ ] Spelling and automatic correction follow macOS text preferences.

### Appearance and shortcuts

- [ ] Installed font families appear in Settings and in the editor font menu.
- [ ] Font size, accent, editor text color, and editor background update correctly.
- [ ] Empty editor-color fields fall back to the system theme and transparent glass.
- [ ] Shortcut keys and modifiers can be changed, removed, and restored.
- [ ] Duplicate shortcuts show a conflict warning and do not execute.
- [ ] Configured shortcuts work while the notes panel is active.

The configurable show/hide shortcut is currently panel-local. System-wide activation is a tracked release task and should not be reported as working yet.

### Persistence and transfer

1. Create multiple notes containing plain text and rich formatting.
2. Stop the app normally and launch it again.
3. Confirm note titles, bodies, tab order, selection, pin state, settings, and rich formatting return.
4. Import `.txt` and `.md` files.
5. Export a note as plain text, Markdown, and RTF; open each exported file in another app.
6. Confirm exported filenames do not contain characters illegal in macOS filenames.

Working data is stored in:

```text
~/Library/Application Support/MenuBarNotes/
```

The directory contains readable `.md` note bodies, optional `.rtf` formatting sidecars, `workspace.json`, `preferences.json`, and a previous-generation `Recovery` snapshot. To perform a clean-state test, stop the app first, back up the directory, and then move it out of Application Support:

```sh
mv "$HOME/Library/Application Support/MenuBarNotes" \
   "$HOME/Desktop/MenuBarNotes-test-backup"
```

Do not remove that directory while the app is running.

## Resource checks

Build and run the release executable first:

```sh
swift build -c release
.build/release/Motes
```

In a second Terminal window, measure resident memory:

```sh
Scripts/profile-memory.sh Motes
```

Also inspect **Activity Monitor → Memory** and **Activity Monitor → CPU** after leaving the closed panel idle for at least one minute. Record:

- Release executable size.
- Idle resident memory with the panel closed.
- Resident memory with the panel open and ten ordinary notes loaded.
- Idle CPU after pending saves finish.
- Time from clicking the menu-bar icon to seeing the editor.

The current targets are at or below 15 MB for the release executable where practical and below 75 MB resident memory during an ordinary idle workflow. A SwiftPM executable-size result is not a substitute for measuring the eventual signed `.app` bundle.

## Accessibility checks

- [ ] Use only the keyboard to create, select, edit, format, and close notes.
- [ ] Enable VoiceOver (`Command-F5`) and confirm controls have useful names.
- [ ] Confirm the editor is announced as “Note body.”
- [ ] Enable **System Settings → Accessibility → Display → Reduce transparency** and verify the panel remains legible.
- [ ] Increase display contrast and verify selected tabs and warnings remain distinguishable.

## Reporting a problem

Include:

- macOS version and Mac model.
- Xcode and Swift versions (`xcodebuild -version` and `swift --version`).
- The commit hash (`git rev-parse --short HEAD`).
- Exact reproduction steps.
- Expected and actual behavior.
- Relevant Terminal or Xcode output.
- A screenshot or short screen recording for visual problems.
- Whether the issue reproduces after moving the Application Support test data aside.

Never attach private notes, credentials, signing material, or the contents of Application Support without reviewing and sanitizing them first.
