# Motes — Application Framework

## Constraints that guide the design

Motes is a native macOS utility, not a miniature web application. The initial engineering budgets are:

- **Installed app size target:** at or below 15 MB for a release build where practical.
- **Memory ceiling:** never intentionally ship a normal idle workflow that exceeds 75 MB; profile representative release builds before releases.
- **Idle behavior:** no polling, server process, web view, analytics client, or network requirement.
- **Storage:** local, readable, atomic, and recoverable.

These are release gates to measure, not assumptions guaranteed by choosing a particular framework. Native AppKit and SwiftUI APIs keep the base notes experience small. The Clean Dictation candidate adds a checksum-pinned FluidAudio dependency for Enhanced Local, so its executable, external model, runtime resources, and licenses are measured and approved separately.

## Main user flows

### 1. Capture a thought

1. The user clicks the menu-bar icon or invokes the configurable global shortcut.
2. The last selected note appears with keyboard focus in the editor.
3. The user types; changes are reflected immediately in memory.
4. A short debounce coalesces edits and atomically saves the workspace locally.
5. The panel can be dismissed without an explicit Save command.

### 2. Work with several notes

1. The tab strip shows open notes without opening separate windows.
2. The user creates a note with the plus button or `Command-T`.
3. Selecting a tab restores that note's content.
4. Closing a note selects an adjacent note and always leaves at least one note available.
5. Tab order, selection, titles, pin state, and content survive relaunch.

### 3. Structure text quickly

1. The user writes in a distraction-free editor.
2. Bullets and numbered lists are available from the compact formatting bar.
3. Markdown-style prefixes keep saved note bodies readable outside the app.
4. Automatic conversion after `- ` or `1. ` is a configurable follow-up behavior.
5. Native rich-text commands can be layered onto the editor later without changing note identity or workspace storage.

### 4. Make the app personal

1. The user opens Settings from the slider button.
2. Appearance settings expose every installed macOS font, type size, accent color, and glass intensity.
3. Editing settings control optional UI and automatic behaviors.
4. Shortcut settings let the user remove or restore individual commands; recording arbitrary replacement combinations is the next shortcut milestone.
5. Preferences save alongside the workspace and take effect without relaunching.

### 5. Recover reliably

1. Each note body lives in its own UTF-8 `.md` file.
2. `workspace.json` contains only ordering and lightweight metadata.
3. `preferences.json` contains appearance, editing, and shortcut choices.
4. Writes use atomic replacement, so interruption cannot leave half a JSON document.
5. Missing note files are skipped rather than preventing every other note from loading.

## Source layout

```text
Sources/
├── MenuBarNotesCore/       # Portable models, text transforms, and local persistence
└── MenuBarNotesApp/        # macOS menu-bar scenes, state coordination, and views
Tests/
└── MenuBarNotesCoreTests/  # Fast tests that do not require a macOS UI session
```

`MenuBarNotesCore` deliberately does not import AppKit or SwiftUI. Keeping storage and state transformations portable makes them inexpensive to test and prevents UI choices from becoming persistence requirements.

`MenuBarNotesApp` is compiled as the native executable. On macOS it supplies the menu-bar scene and customization UI. The non-macOS entry point only explains the platform requirement, allowing core builds and tests to run in Linux-based continuous integration.

## State and persistence boundaries

- `Note` owns a stable UUID, title, Markdown-compatible body, dates, and pin state.
- `Workspace` owns note order and current selection, and enforces the invariant that an editable note always exists.
- `AppPreferences` owns lightweight user choices, including shortcuts that can be unset.
- `LocalStore` is an actor so reads, saves, and cleanup cannot execute concurrently.
- `AppState` is main-actor isolated, presents state to SwiftUI, and schedules debounced saves.

The initial format favors plain Markdown note bodies because it is small, readable, portable, and resilient. Font family, size, accent, and glass appearance are app preferences rather than markup embedded into every character. If mixed rich-text formatting becomes a hard requirement, it should be added through an explicitly versioned sidecar format while keeping Markdown export available.

## Clean Dictation data flow and privacy boundary

```text
microphone -> selected local speech engine -> raw transcript
  -> optional local cleanup -> focused editor OR title-only router -> LocalStore
```

- **Standard** uses Apple's speech APIs only when on-device recognition is
  available and sets `requiresOnDeviceRecognition = true`. Unavailability is an
  error; there is no cloud fallback.
- **Enhanced Local** is a non-shippable candidate backed by external, data-only
  Core ML model content. The exact model revision and every file byte count and
  checksum are embedded in the application manifest. The 464,413,247-byte
  (442.9 MiB) model must not be bundled; the release gate rejects it in the
  current executable root or a future application artifact.
- FluidAudio inference is forced offline before load and inference. Release
  checks require `ModelHub.offlineMode = true` and reject code that disables
  offline mode or invokes FluidAudio model download helpers from production
  capture code.
- Microphone buffers and Enhanced float samples exist in memory only for the
  active capture and are released afterward. No audio is written to notes,
  dictation history, model storage, or logs.
- Cleanup uses the local Foundation Models framework when available. Failure,
  unavailability, or an unfaithful result falls back to the raw transcript
  without blocking persistence.
- Focused capture writes the transcript into the active editor transaction.
  Smart Capture gives routing the transcript plus candidate UUIDs and display
  titles only; note bodies and other note content never enter the routing
  prompt. Low-confidence or unavailable routing falls back to Inbox.
- `LocalStore` persists notes locally. Optional dictation history stores
  transcript text and destination metadata as atomic local JSON, contains no
  audio, and purges records after 30 days.
- The only intended product network operation is an explicit user-approved
  Enhanced model download, repair, or update from the embedded allowlist.
  Standard recognition, Enhanced inference, cleanup, routing, notes, and
  history have no application-controlled network path.

This architecture is not release approval. Enhanced Local remains disabled
from release until the pinned model materially beats Standard and the manual
device, resource, accessibility, legal, attribution, SBOM, signing, and store
gates in `TESTING.md` have recorded evidence.

## UI direction

The visual hierarchy is intentionally restrained:

- A translucent material surface provides subtle glass depth without custom rendering.
- A single header holds the product identity, new-note action, and customization entry.
- A horizontally scrolling capsule tab strip uses the accent color only for selection.
- Formatting controls remain compact and can be hidden.
- The editor receives most of the available space.
- Native controls preserve keyboard behavior, accessibility, and lower implementation cost.

Glass opacity is stored now, but fine-grained material rendering and contrast adaptation should be finalized on macOS hardware. Legibility and Reduce Transparency support take precedence over a visual effect.

## Development sequence

1. **Framework (implemented):** package structure, portable core, local files, menu-bar and floating-window shells, tabs, settings, and tests.
2. **Native editor (implemented, awaiting macOS validation):** `NSTextView` selections, undo, formatting, list continuation, indentation, installed fonts, and RTF sidecars.
3. **Shortcut customization (partially implemented):** arbitrary combinations, removal, restoration, and conflict detection work while the panel is active; system-wide activation remains.
4. **Panel and tabs (partially implemented):** pinning, dimensions, reordering, navigation, and overflow scrolling work; cursor/scroll/window-position restoration remains.
5. **Hardening (partially implemented):** recovery snapshots, format versioning, malformed-file fallback, and import/export are covered by portable tests; native accessibility and integration audits remain.
6. **Release profiling (pending macOS):** measure signed release app size, idle and active memory, idle CPU, launch time, and typing latency against representative workspaces.
7. **Clean Dictation (implemented candidate, not release-approved):** Standard,
   optional local cleanup/routing, history, and Enhanced infrastructure are on
   a release-disabled candidate. Real-device quality, device matrices,
   accessibility, resource, legal, artifact, signing/notarization, and store
   gates remain pending.

## Explicit non-goals for the lightweight base app

- Electron or an embedded browser runtime.
- Accounts, analytics, advertising, or mandatory network access.
- A database server or background synchronization daemon.
- Bundled font collections.
- Bundled speech-model weights, cloud speech fallback, cloud cleanup/routing,
  or a mandatory AI runtime for ordinary notes.

Features that threaten the resource ceiling must be optional, isolated, measured, and justified before inclusion.
