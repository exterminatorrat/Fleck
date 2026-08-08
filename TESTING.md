# Testing Fleck on macOS

> **Release approval is blocked.** Automated checks can validate code and a
> SwiftPM executable, but they cannot approve a release. Enhanced Local is a
> non-shippable candidate until the pinned model materially beats Standard on
> the real-device corpus and every manual gate below has recorded evidence.

## Requirements

- A Mac running macOS 14 Sonoma or later.
- Xcode 26 or later with the macOS 26 SDK or later, installed from Apple. The
  current source references macOS 26 Speech APIs behind runtime-availability checks,
  so it requires this compile toolchain even though macOS 14 remains the
  deployment and runtime minimum.
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
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

Look for the note icon in the macOS menu bar, then click it to open the notes
panel. Quit Fleck from the menu-bar icon's context menu when testing is done.
The packaged app is required for the embedded Agent Connector and for stable
macOS privacy permissions.

`Scripts/validate-macos.sh` verifies the host OS, runs the complete test suite, creates a release build, checks the release executable against the 15 MB budget, and prints the exact executable path. It does not launch or terminate the app because visual testing should remain under the tester's control.

## Packaged editor and branding checklist

Build and launch only the packaged app with `Scripts/build-fleck-app.sh` and
`/usr/bin/open -n .build/Fleck.app`. Use disposable tabs to the right of the
leftmost personal tab. Record pass/fail without note text, screenshots of
private notes, credentials, selection contents, or agent information.

1. Drag a selected disposable tab over its immediate left neighbor and immediate right neighbor; neighboring tabs move live before release, the selected highlight follows, and final order persists after relaunch.
2. Create enough disposable tabs to hide trailing tabs; the right fade and `Reveal hidden tabs` chevron appear only then, the chevron reveals the trailing tab without obscuring the visible final tab, and neither control remains once the trailing edge is visible.
3. At a caret and a uniform selection, confirm the font menu checks the actual family; across a mixed-family selection it checks none. Enter a valid numeric size with Return and with focus loss; verify 1 and 512 apply. Enter 0, 513, empty input, and non-numeric input; verify the displayed current size restores and document content does not change.
4. Apply Font Color, `Automatic`, Highlight, and `No Highlight` to a selection and a caret; type new text after caret commands; relaunch and verify rich text retains the intended attributes while Markdown/plain export remains text-only.
5. Confirm the menu bar and `NotesPanel` header use the same monochrome template mark next to `Fleck`.
6. Confirm Fleck is absent from Dock and Command-Tab while the menu bar, pinned notes window, Settings, onboarding entry, launch-at-login setting, dictation capsule, and Agent Connector remain reachable through their existing paths.
7. With VoiceOver and Full Keyboard Access, confirm names, values, mixed-state announcements, and field focus for the chevron and formatting controls. With Reduce Motion enabled, confirm reordering remains immediate.

## Test from Xcode

1. Open the package:

   ```sh
   open Package.swift
   ```

2. Wait for Xcode to finish resolving the package.
3. Select the **Fleck** scheme and **My Mac** destination.
4. Choose **Product → Test** (`Command-U`).

For interactive UI and Agent Connector testing, use the packaged Terminal flow
above. Xcode's Swift package runner is not a supported interactive launch. The
source project is a Swift Package. `Scripts/build-fleck-app.sh` assembles an
ad-hoc development-signed native `.app`, but no distribution-signed artifact
exists. Launch-at-login must be validated later from the packaged and signed
application.

## Agent workspace release gates

### Automated gate

Run from the repository root with `FLECK_ENHANCED_CANDIDATE` unset:

```sh
swift test --disable-automatic-resolution --no-parallel
swift build
swift build -c release
Scripts/audit-agent-boundary.sh
Scripts/validate-macos.sh
git diff --check
```

CI runs the same locked ordinary graph and the complete product, audit, and
candidate gates:

```sh
swift test --disable-automatic-resolution --no-parallel
swift build -c release --product Fleck
swift build -c release --product fleck-agent
Scripts/audit-agent-boundary.sh
Scripts/check-release-size.sh .build/release/Fleck
Scripts/validate-macos.sh
Scripts/test-enhanced-candidate-pin.sh
Scripts/resolve-enhanced-candidate.sh .build-candidate \
  swift test --disable-automatic-resolution --no-parallel \
    --scratch-path .build-candidate
git diff --exit-code -- Package.resolved
Scripts/test-enhanced-candidate-lock-preservation.sh
git diff --exit-code -- Package.resolved
Scripts/check-candidate-release-rejected.sh
git diff --exit-code -- Package.resolved
```

The test suite probes private, unknown, Trash, and Dictation History UUIDs;
unshared activity; the closed command model; secret-free profile persistence
and setup output; same-user IPC; revisions, retries, transaction recovery, and
Undo; the exact thirteen MCP tools; and tools-only MCP capabilities.
`Scripts/audit-agent-boundary.sh` separately rejects helper AppKit outside the
non-activating launch adapter, HTTP/TCP/listener APIs, direct Fleck storage
paths, an altered MCP tool/handler surface, MCP-mode stdout prose, and
credential-bearing snippets.

`Scripts/validate-macos.sh` builds the native ad-hoc development-signed
`Fleck.app`, verifies its stable code identity and separately packaged helper,
runs a bounded native launch smoke test, and runs the complete macOS test suite,
including Keychain API contract tests. It does not prove a live Keychain round
trip, third-party client compatibility, physical-device accessibility,
distribution signing, notarization, or distribution.

### Manual client, lifecycle, and accessibility gate

- **Status:** PENDING — no Codex, Claude Code, Kimi, generic CLI, live Keychain,
  physical-device accessibility, or distribution result is claimed by the
  automated run.
- **Required setup:** Build with `Scripts/build-fleck-app.sh`; launch with
  `/usr/bin/open -n .build/Fleck.app`; install the **Agent Connector**; create
  one temporary shared note and four separate temporary profiles in
  **Settings → Agents**. Record the commit, macOS/Xcode/Swift versions, client
  versions, profile names, and timestamps.
- **Codex:** Connect the Codex profile with:

  ```sh
  codex mcp add fleck -- "/absolute/path/to/fleck" mcp --profile PROFILE_UUID
  ```

- **Claude Code:** Connect its separate profile with:

  ```sh
  claude mcp add --scope user fleck -- "/absolute/path/to/fleck" mcp \
    --profile PROFILE_UUID
  ```

- **Kimi:** Add the `command` and `["mcp", "--profile", "PROFILE_UUID"]`
  arguments shown in `README.md` to a temporary Kimi MCP configuration.
- **Generic CLI:** Use the installed helper directly with `--json`, beginning
  with:

  ```sh
  fleck notes list --profile PROFILE_UUID --json
  fleck note read NOTE_UUID --profile PROFILE_UUID --json
  ```

For each client, record evidence for list, read, append, add task, complete
task, a stale-revision conflict, retrying an uncertain write with the unchanged
operation UUID, Agent Activity, and safe Undo. Then:

1. Revoke the profile while idle, then repeat during a request; both must deny
   subsequent work without exposing credential material.
2. Turn off **Allow Agent Access** while connected; list, read, activity, and
   mutation probes must immediately return the same safe absence as an unknown
   UUID.
3. Quit Fleck and call the helper; Fleck must launch without activation and the
   bounded request must complete or return a safe timeout.
4. Edit the note locally while a client holds a stale revision; the client
   write must be rejected without overwriting the local edit.
5. Relaunch a prepared-transaction fixture after interruption; reconciliation
   must produce one mutation and one receipt, not a duplicate.
6. Confirm the temporary credential is created and removed in Keychain through
   the UI workflow; never copy the credential into the report.
7. With VoiceOver and Full Keyboard Access, verify the Agent Access toggle and
   confirmation, shared badge, profile buttons, activity rows, banner, and Undo
   names/order. Repeat with Reduce Motion.
8. Repeat with multiple Fleck windows, sleep/wake, and a five-minute idle
   bridge session; record CPU and unexpected stdout/stderr.

Do not use real private notes for this gate. Revoke all temporary profiles,
unshare/delete the temporary note, remove temporary client configuration, and
retain only sanitized evidence.

## Clean Dictation release gates

### Automated gate

Run from the repository root:

```sh
swift package resolve
swift test --disable-automatic-resolution --no-parallel
swift build -c release
Scripts/check-release-size.sh
Scripts/validate-macos.sh
git diff --check
git status --short
```

`Scripts/check-release-size.sh` accepts the current executable, a directory
containing `Fleck`, or a future `.app` containing `Contents/MacOS/Fleck`. It
profleck an executable path inside `.app` to the enclosing bundle, including
when an executable symlink outside the bundle resolves into it. It resolves
command-line directory symlinks to a physical root, inspects nested symlink
targets without following arbitrary cycles, fails closed on traversal errors,
and scans case-insensitively for `.mlmodel`, `.mlpackage`, `.mlmodelc`, exact
`coremldata.bin`/`weight.bin`/`weights.bin` names, and `.bin` files under model
bundle or model directory paths relative to each artifact or queued scan root.
When a model-named symlink resolves to a neutral external directory, the
logical model context follows that queued physical root.
An unrelated `.bin` outside a model path is allowed even when an absolute
ancestor happens to be named `models`. The same gate restricts searches to
Swift sources accepted through regular files, file symlinks, or directory
symlinks under `Sources`; resolves and deduplicates their physical targets;
and fails closed on broken links, cycles, or traversal errors.

For source assertions, the gate generates and compiles a temporary structural
inspector using the active Xcode toolchain's host `SwiftSyntax`, `SwiftParser`,
and `SwiftIfConfig` modules. It adds no package or network
dependency. `SwiftParser` parses every discovered production file, and
malformed syntax fails closed. `SwiftIfConfig` evaluates required assignments
for the package's macOS 14 release target; compiler-backed `canImport` checks
use release flags, and the app target's SwiftPM-generated `SWIFT_PACKAGE` and
`SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE` conditions are active. `Package.swift`
currently defines no additional app-target release `-D` flags; if that changes,
update this adapter and its positive/negated condition fixtures. Unknown
conditions fail closed. Forbidden findings remain conservative across all
branches. `SwiftSyntax` then reports only the specific member-access and
assignment findings owned by this gate. Transparent
parentheses, single-element tuples, and metatype `.self` wrappers are
normalized recursively without alias analysis. Comments,
ordinary/raw strings, and bare or extended regex literals are inert, while
real ordinary/raw/nested string interpolation remains executable syntax and is
visited. In particular, matching-hash text such as `\#(...)` inside a regex is
regex pattern content under current Swift semantics, not Swift interpolation.
Physical source aliases are inspected once with their logical
`EnhancedSpeechCapture.swift` identity retained for the required assignment.
Missing toolchain modules, inspector compile/run failures, unknown inspector
output, and malformed source all exit 2. The structural gate asserts:

- `ModelHub.offlineMode = true` is present.
- `ModelHub.offlineMode = false` is absent.
- production sources do not access `AsrModels.downloadAndLoad`.
- production sources do not access `ModelHub.download` or
  `ModelHub.fetchFile`.
- production sources do not access `NSEvent.addGlobalMonitorForEvents`.

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
  wc -c .build/release/Fleck
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

Fix Round 1 added regressions for the real SwiftPM
`.build/release -> arm64-apple-macosx/release` symlink layout, symlinked
directory and `.app` inputs, executable paths inside `.app`, nested symlink
targets and cycles, mixed-case model extensions/names/paths, failed `find`,
failed `rg`, Swift-only source scope, multiline forbidden calls, multiline
required offline assignment, and comment/string-only false positives. A fake
`find` exit 2 and a fake `rg` exit 2 both make the gate exit 2; only ripgrep exit
1 counts as an absent forbidden call.

Fix Round 2 added regressions for an executable symlink outside `.app` that
resolves to `Fleck.app/Contents/MacOS/Fleck`, generic `.bin` classification
relative to the artifact boundary, root-level and symlinked `Models`
directories, raw strings using one or multiple `#` delimiters, raw multiline
strings, nested comments, and unterminated raw strings. The valid Swift
fixtures are parsed with `swiftc -frontend -parse`; executable multiline calls
remain forbidden while the same text in any supported string or comment form
is ignored.

Fix Round 3 added typechecked ordinary, raw, and nested string-interpolation
fixtures, including the production `NSEvent` call shape. Executable calls
inside interpolation exit 1; forbidden text inside nested strings or comments
remains inert; malformed ordinary and raw interpolation exits 2. Source file
and directory symlinks are scanned, clean and logical
`EnhancedSpeechCapture.swift` symlinks pass, and broken or cyclic source links
exit 2. A logical `Resources/Models` symlink to a neutral physical directory
retains model context and rejects its generic `.bin`; a neutral cache symlink
and the external-ancestor clean artifact remain allowed.

Fix Round 4 replaced the custom source scrubber with the compiler-backed
structural inspector above. Regression fixtures cover both reviewed regex
failures; ordinary, raw, and nested string interpolation; inert comments,
strings, and regex patterns; extended regex arbitrary hashes and matching-hash
pattern text; bare regex escapes and character classes; executable calls after
regex literals; malformed syntax; inactive `#if` branches; all forbidden
members; required true and forbidden false assignments; deduplicated source
aliases; and toolchain/module/compile/run failures. The retained source-symlink
and artifact/model fixtures remain green.

Fix Round 5 made the required `ModelHub.offlineMode = true` assertion
conditional on the active macOS release region. Regression fixtures cover
Linux-only versus macOS-active branches, `#elseif`/`#else`, nested conditions,
`canImport`, Swift/compiler versions, architecture checks, fail-closed unknown
conditions, and recursive parentheses/metatype `.self` wrappers. Forbidden
false assignments and forbidden member accesses remain all-branch checks.

Fix Round 6 models the two SwiftPM-generated app-target custom conditions and
adds positive and negated fixtures for both. The gate rejects toolchains older
than Swift 6.1 and toolchains missing the host `SwiftSyntax`, `SwiftParser`,
or `SwiftIfConfig` modules. That inspector preflight does not make the full
project buildable on Xcode 16.3: full compilation requires Xcode 26 or later
with the macOS 26 SDK or later, as documented above.

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
- **Required evidence:** Results for every left/right Command, Option, and
  Control key; Fn on built-in and external keyboards; Input Monitoring grant,
  denial, revocation, retry, restart, sleep/wake; ordinary modifier conflicts;
  180 ms hold, short tap, double-tap hands-free, finish, and Escape; active,
  hidden, pinned, and behind-another-app windows; all Spaces, full-screen apps,
  multiple displays, display removal, and docking; focused rollback/Undo;
  title-only routing/Inbox; history copy/open/delete/purge/clear; and ordinary
  notes with no model installed.
- **Exact procedure:** Run every interaction from both idle and active capture
  states. Confirm the persistent bar remains non-activating and shows neither a
  transcript nor a shortcut hint at idle. Use uniquely identifiable note-body
  secrets to confirm routing sees titles only. Force failed cleanup and
  low-confidence routing, verify raw/Inbox fallback, advance a test clock or
  use dated fixtures for 30-day purge, and inspect the saved note/history after
  each terminal path.

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
  `test -f "$artifact_path/Contents/MacOS/Fleck"` fails. Measure it and run
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
~/Library/Application Support/Fleck/
```

The directory contains readable `.md` note bodies, optional `.rtf` formatting sidecars, `workspace.json`, `preferences.json`, and a previous-generation `Recovery` snapshot. To perform a clean-state test, stop the app first, back up the directory, and then move it out of Application Support:

```sh
mv "$HOME/Library/Application Support/Fleck" \
   "$HOME/Desktop/Fleck-test-backup"
```

Do not remove that directory while the app is running.

### First-launch onboarding

Automated coverage:

```sh
swift test --disable-automatic-resolution --filter Onboarding
swift test --disable-automatic-resolution \
  --filter 'DictationAvailability|DictationSettings|AppStateDictation'
```

Manual validation requires a disposable Application Support directory or a
separate macOS test account. Do not move live Fleck data while the app is
running.

- [ ] A fresh store opens mandatory onboarding at Welcome and cannot skip it.
- [ ] Quit and relaunch at every rail step and permission substep; the exact
  next incomplete screen returns.
- [ ] The First Note and Dictation canvases are the real Fleck tab/editor
  surface, and editing the starter note unlocks Continue.
- [ ] The configured modifier name, floating capsule, cleanup fallback,
  Smart Capture fallback, and focused-editor insertion match normal Fleck.
- [ ] Microphone, Speech Recognition, and Input Monitoring are requested only
  after their individual buttons; denial and Not Now both remain recoverable.
- [ ] Compatibility matches the Mac's Apple Speech and Apple Intelligence
  state. Check VoiceOver, keyboard order, Reduce Motion, and Reduce
  Transparency.
- [ ] Get Fleck states no credit card, no Apple purchase sheet, and no
  automatic charge. Verify the StoreKit-localized price, trial, purchase,
  restore, and completion transition only after the later access subsystem is
  integrated.

This branch deliberately uses an unavailable access adapter. It cannot provide
a real trial, purchase, restore, localized price, seven-day expiry, or
read-only enforcement, and onboarding therefore cannot complete in production
until the StoreKit 2 access phase replaces that adapter.

## Resource checks

Build and open the packaged app first:

```sh
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

In a second Terminal window, measure resident memory:

```sh
Scripts/profile-memory.sh Fleck
```

Also inspect **Activity Monitor → Memory** and **Activity Monitor → CPU** after leaving the closed panel idle for at least one minute. Record:

- Release executable size.
- Idle resident memory with the panel closed.
- Resident memory with the panel open and ten ordinary notes loaded.
- Idle CPU after pending saves finish.
- Time from clicking the menu-bar icon to seeing the editor.

The current targets are at or below 15 MB for the release executable where practical and below 75 MB resident memory during an ordinary idle workflow. A SwiftPM executable-size result is not a substitute for measuring the eventual signed `.app` bundle.

### Performance baseline — Wave 1A

The reproducible baseline harness uses exactly 10-note, 100-note, and
1,000-note synthetic workspaces. The fixture has stable UUIDs and dates and
contains no personal note content. Automated coverage characterizes current
LocalStore load/save behavior, records temporary-directory storage observations,
and uses the `FleckPerformanceSaveLeavesUnchangedNoteBodiesUntouched` regression
to verify the persistence invariant: when the existing root is a valid
integrity-v1 snapshot and its manifest hash matches the newly encoded
preferences, note body, or RTF bytes, unchanged content is reused rather than
atomically rewritten. Invalid, hashless, legacy, or changed content follows the
full write path.

Run the safe automated checks from the repository root:

```sh
swift test --disable-automatic-resolution --no-parallel --filter FleckPerformance
bash -n Scripts/profile-fleck-performance.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck Scripts/profile-fleck-performance.sh
else
  echo 'shellcheck not installed; not run'
fi
```

For a profile artifact, choose an explicit disposable output directory outside
`~/Library/Application Support/Fleck/` and run:

```sh
Scripts/profile-fleck-performance.sh "/absolute/path/to/disposable-output"
```

The script builds the release Fleck executable and records the machine, macOS,
Xcode, Swift, commit, build configuration, executable size, and command
metadata. If a QA Fleck process is already running, collect five idle RSS/CPU
samples without allowing the script to launch or terminate it:

```sh
FLECK_PERFORMANCE_PID=PID Scripts/profile-fleck-performance.sh \
  "/absolute/path/to/disposable-output"
```

The output also records an aggregate disk sample. Use Instruments File Activity
or `fs_usage` on the caller-specified QA PID for logical disk writes; do not
report aggregate device activity as Fleck-only writes. Record launch, panel
presentation, note switching, typing, save duration, logical disk writes, idle
CPU, resident memory, executable size, median/p50, p95, and peak results in
`docs/performance/fleck-baseline-template.md`. Leave values as `[not captured]`
when no measurement was taken; tests and a build do not create runtime
evidence.

The packaged-app boundary is manual. Build and launch the exact QA app with
`Scripts/build-fleck-app.sh` and `/usr/bin/open -n .build/Fleck.app` only from
a disposable macOS account or another isolated QA environment. Current
production persistence has no safe test-root override, so the harness never
launches Fleck and never reads, copies, moves, or deletes the user's Fleck
Application Support directory. If an isolated packaged launch is unavailable,
leave launch and UI/runtime measurements unclaimed.

For the panel-presentation timing loop, grant System Events Accessibility to
the calling Terminal or agent in System Settings → Privacy & Security →
Accessibility, launch the exact packaged Fleck app manually, and run:

```sh
bash -n Scripts/measure-fleck-panel-presentation.sh
FLECK_PERFORMANCE_PID=PID Scripts/measure-fleck-panel-presentation.sh \
  "/absolute/path/to/disposable-output"
```

The script measures the bounded `AX-press-to-accessible-window` interval: one
cold and 30 warm samples from the exact Fleck `AXMenuExtra` AXPress invocation
to the first matching sane-size transient `AXWindow` exposed in Fleck's
process window list. Window-list membership is the observed criterion; the
script does not require `AXVisible`. It searches all Fleck menu bars and
requires title/name `Fleck`, role `AXMenuBarItem`, and subrole `AXMenuExtra`;
it normalizes the panel closed before every sample by toggling that exact item
only when a matching window is present, then verifies that it disappears after
each sample. It uses one JXA process and `Date.now`, writes raw TSV plus
p50/p95/min/max and metadata, and fails closed on missing, ambiguous, or
timed-out states. A failed AX transition receives a bounded best-effort close
attempt without masking the original error. This is not pixel-complete or
human click latency. It does not use app activation/log records, launch or
signal Fleck, or read/write Fleck Application Support or editor data. It
intentionally toggles panel presentation state with AXPress; it does not
terminate, rebuild, or otherwise control Fleck's process lifecycle, and does
not mutate note/editor or Application Support data. Each payload is written
through its securely opened same-directory temporary regular-file handle and
atomically committed with an exclusive same-directory `link(2)` followed by
unlink of the source; every existing destination, including a directory
substituted immediately before publication, fails closed. The caller must provide a fresh existing disposable directory with
the three final names absent; the harness canonicalizes and pins that directory
by device/inode, rejects tab, carriage-return, and line-feed characters in its
lexical or resolved path, and rolls back earlier app-owned publications if a
later publication fails while preserving caller-owned substitutions. The live
directory binding remains authoritative if the caller renames or replaces the
approved pathname: operations continue in the original directory, and a
successful transaction's files remain there rather than being redirected.

The PID guard checks only the packaged executable path shape
`Fleck.app/Contents/MacOS/Fleck`; it does not prove the process is the accepted
build. The caller owns the exact artifact identity and the disposable output
directory.

## Accessibility checks

- [ ] Use only the keyboard to create, select, edit, format, and close notes.
- [ ] Enable VoiceOver (`Command-F5`) and confirm controls have useful names.
- [ ] Confirm the editor is announced as “Note body.”
- [ ] Enable **System Settings → Accessibility → Display → Reduce transparency** and verify the panel remains legible.
- [ ] Increase display contrast and verify selected tabs and warnings remain distinguishable.
- [ ] With VoiceOver and Full Keyboard Access, operate the modifier picker and
  Input Monitoring recovery controls without moving focus into the status bar.
- [ ] Enable Reduce Motion and verify the persistent bar uses understandable
  opacity-only state changes while docking remains immediate.

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
