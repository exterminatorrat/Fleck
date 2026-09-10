# Testing Fleck

Fleck combines portable Swift logic with macOS-only UI, permission, speech,
Keychain, and process boundaries. Automated tests are necessary, but native
claims require an explicitly launched packaged app in a disposable environment.

## Requirements

- macOS 14 or later
- Xcode 26 or later with the full macOS 26 SDK selected
- Swift 6
- Node.js 22.12 or later for `website/`

Confirm the selected toolchain without building:

```sh
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift --version
node --version
npm --version
```

## Ordinary automated checks

Run from the repository root with the Enhanced candidate unset:

```sh
unset FLECK_ENHANCED_CANDIDATE
swift test --disable-automatic-resolution --no-parallel
```

For a focused Swift test, use the non-empty wrapper with an anchored test
identifier regex. It fails when the expression matches no tests:

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\..+$'
```

The full ordinary macOS gate is:

```sh
Scripts/validate-macos.sh
```

The integrated validator runs tests, creates and inspects the development-signed
bundle, checks release boundaries, and exits **without launching Fleck**. Treat
interactive testing as a separate action; this prevents validation from
modifying Application Support, permission state, windows, or focus implicitly.

Do not enable the Enhanced candidate for an ordinary test run. Automatic package
resolution stays disabled so a check does not rewrite the reviewed lockfile.

## Packaged native app

Build without launching:

```sh
unset FLECK_ENHANCED_CANDIDATE
Scripts/build-fleck-app.sh
```

Only launch when the test plan calls for interactive native evidence:

```sh
/usr/bin/open -n .build/Fleck.app
```

`swift run Fleck` is not a substitute. A bare executable lacks the packaged app's
privacy identity and embedded Agent Connector, so it cannot prove permission,
dictation, signing, launch-at-login, or bundle behavior.

## Safe native test environment

Use a disposable macOS user account. Populate it only with synthetic notes,
synthetic filenames, and fixtures whose content and provenance have been
reviewed for testing. Never use a personal account, real notes, private
recordings, production credentials, or a copy of a personal Application Support
directory.

Before sharing evidence:

- remove names, paths, UUIDs, usernames, credentials, and unrelated window
  content;
- confirm screenshots and logs contain only synthetic fixtures;
- never attach Keychain values, microphone audio, model weights, or a raw
  Application Support archive;
- reset permissions and delete the disposable account when the test is done.

## Manual native checks

Record the source commit, macOS version, hardware architecture, Xcode and Swift
versions, bundle path, and exact actions. Keep failures and unverified steps
visible.

### Notes and editor

- Create, rename, reorder, pin, close, trash, restore, import, and export
  synthetic notes.
- Exercise search, folders, backlinks, file references, tabs, and both menu-bar
  and pinned-window surfaces.
- Check selection, input methods, undo/redo, formatting, lists, checklists,
  spelling, paste, and keyboard shortcuts in the packaged app.
- Relaunch and verify restored content, order, selection, window state, and the
  previous-generation recovery behavior.

### Dictation

- Grant and deny microphone and speech permissions in the disposable account;
  confirm failures keep user control and do not claim a save that did not occur.
- Use an approved synthetic phrase set. Verify focused insertion, Smart Capture,
  ambiguous routing to Inbox, cancellation, history deletion, and relaunch.
- On macOS 26, record whether the system Foundation Models runtime reports
  available. Do not describe it as tested when the system reports unavailable.
- Confirm no audio recording is written and exported diagnostics contain only
  the reviewed fixture content.

### Agent Connector

- Create a temporary profile and synthetic notes. Verify no access before a
  grant, capability filtering, note and folder grants, stale-revision rejection,
  retry with an unchanged operation ID, visible activity, Undo, and revocation.
- Verify quit/relaunch and timeout behavior without exposing the credential.
- Remove the temporary profile, Keychain item, client configuration, and test
  notes when finished.

### Accessibility and resources

- Test both windows with VoiceOver, Full Keyboard Access, keyboard-only use,
  Reduce Motion, Reduce Transparency, increased contrast, long text, and mixed
  scripts. No state may depend on color, hover, or motion alone.
- Measure release-build idle memory, CPU, energy, launch, typing, search, note
  switching, and dictation teardown. Investigate continuous polling, unexpected
  network use, retained model resources, or background work after the UI closes.

## Enhanced Local candidate

Run this graph only for work that explicitly touches it:

```sh
Scripts/resolve-enhanced-candidate.sh .build-candidate \
  swift test --disable-automatic-resolution --no-parallel \
    --scratch-path .build-candidate
git diff --exit-code -- Package.resolved
```

The command proves candidate compilation and deterministic tests, not live model
quality, microphone behavior, redistribution rights, signing, or release
readiness. Model assets require their own reviewed fixtures and receipts; do not
download or run a model merely to validate an ordinary contribution.

## Website

```sh
cd website
npm ci
npm test
npm run build
```

`npm ci` must use the committed lockfile. A visual website change also needs
keyboard, narrow and wide viewport, contrast, and reduced-motion review with
synthetic content.

## Reporting a failure

Include the smallest reproduction, expected and actual behavior, source commit,
environment versions, and the exact checks run. Sanitize logs before attaching
them. For a security-sensitive failure, do not open an issue; follow
[Security](SECURITY.md).
