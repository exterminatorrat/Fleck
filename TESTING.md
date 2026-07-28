# Testing Motes on macOS

## Requirements

- A Mac running macOS 14 Sonoma or later.
- Xcode 16 or later, installed from Apple.
- The Xcode command-line tools selected with `xcode-select`.
- A local checkout of this repository on the branch or pull request being tested.

The package uses Swift tools version 6.0 and native AppKit/SwiftUI APIs. It does not require Homebrew or third-party dependencies.

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
