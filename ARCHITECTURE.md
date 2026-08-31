# Fleck — Application Framework

## Constraints that guide the design

Fleck is a native macOS utility, not a miniature web application. The initial engineering budgets are:

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
├── FleckCore/          # Models, mutations, persistence, and activity journal
├── FleckAgentProtocol/ # Versioned typed IPC messages and framing
├── FleckApp/           # macOS scenes, state coordination, IPC service, and views
└── FleckAgentBridge/          # Separate MCP/CLI helper and Unix-socket client
Tests/
├── FleckCoreTests/
├── FleckAgentProtocolTests/
├── FleckAppTests/
└── FleckAgentBridgeTests/
```

`FleckCore` deliberately does not import AppKit or SwiftUI. Keeping storage and state transformations portable makes them inexpensive to test and prevents UI choices from becoming persistence requirements.

`FleckApp` is compiled as the native executable. On macOS it supplies the menu-bar scene and customization UI. The non-macOS entry point only explains the platform requirement, allowing core builds and tests to run in Linux-based continuous integration.

## State and persistence boundaries

- `Note` owns a stable UUID, title, Markdown-compatible body, dates, and pin state.
- `Workspace` owns note order and current selection, and enforces the invariant that an editable note always exists.
- `AppPreferences` owns lightweight user choices, including shortcuts that can be unset.
- `LocalStore` is an actor so reads, saves, and cleanup cannot execute concurrently.
- `AppState` is main-actor isolated, presents state to SwiftUI, and schedules debounced saves.

The initial format favors plain Markdown note bodies because it is small, readable, portable, and resilient. Font family, size, accent, and glass appearance are app preferences rather than markup embedded into every character. If mixed rich-text formatting becomes a hard requirement, it should be added through an explicitly versioned sidecar format while keeping Markdown export available.

## Agent workspace trust and data flow

```text
local MCP client or CLI
  -> fleck helper (stdio or CLI output; credential in Keychain)
  -> private AF_UNIX socket (same-user peer check + profile authorization)
  -> AgentCommandService
  -> explicit-share filter -> typed mutation -> atomic LocalStore commit
  -> 30-day activity record and retry tombstone
```

- A note is private until an authorized profile has an explicit grant. Listing,
  reads, task operations, activity, writes, and Undo all derive visibility from
  the current in-memory workspace and the native capability authority. Unknown,
  private, and unauthorized UUIDs return the same `note_not_found` error.
- The helper never opens note `.md`/`.rtf` files, `workspace.json`, Trash, or
  Dictation History. It cannot receive settings, share, note-delete, path, or
  shell commands because those cases do not exist in the typed protocol.
- `FleckAgentBridge` is a separately packaged executable. Its only AppKit use
  is the non-activating Fleck launch adapter. IPC uses an `AF_UNIX` socket below
  the user's Fleck Application Support directory, with a private parent,
  private socket mode, and a matching peer UID. There is no HTTP/TCP listener,
  cloud bridge, or internet-facing port.
- Each integration profile has an independent random credential. Fleck stores
  only its verifier in the data-protection Keychain; the helper stores the
  credential in its own Keychain item. Profile JSON, setup snippets, command
  arguments, normal errors, and MCP stdout do not contain it.
- Writes use optimistic revisions and caller-supplied operation UUIDs. A
  revision conflict rejects the mutation. A repeated operation UUID in the same
  actor scope returns its prior receipt instead of applying the change twice;
  retry tombstones expire after 30 days.
- The activity journal retains exact before/after patches for 30 days. Undo
  requires the authorized profile (or local user), current note visibility,
  expected revision, and an unambiguous inverse patch. Clearing visible
  activity does not clear retry tombstones.
- This is a cooperative local-client boundary. A malicious process already
  executing as the same macOS user may have equivalent access to local files,
  Keychain prompts, input, or accessibility APIs and is outside this bridge's
  threat model.

### MCP Capability Foundation Phase A

The Phase A capability surface is deliberately a policy boundary around the
existing typed note operations, not a general agent runtime:

- Profiles carry the four current capabilities `notes.list`, `notes.read`,
  `notes.write`, and `changes.undo`. New profiles start with no tools or
  resource scopes.
- Resource grants are explicit. A direct note grant authorizes the current note;
  a `folderIncludingFutureNotes` grant authorizes the current notes in that
  folder and future notes only after explicit confirmation. Future inheritance
  is off by default. Current-folder materialization is represented by direct
  note grants, not an implicit global folder switch.
- Legacy per-note `agentAccess` values are migration input. Active profiles
  receive direct grants; legacy shares without an active profile remain
  unassigned and require explicit assignment. A newly created profile receives
  none of those shares automatically.
- The native authority evaluates every command, rechecks the current workspace
  revision before protected reads return and before writes commit, and fails
  closed on revoked or unknown profiles. Capability changes take effect through
  the shared authority snapshot; they cannot be self-granted by an agent.
- Wire v1 remains compatible with the existing command set. Internal v2
  `getCapabilities` is typed and non-mutating, but is not exposed as a CLI
  command. MCP `tools/list` is recomputed for every request from the profile's
  current authority and returns only authorized entries from the static exact 13
  existing registrations; `listChanged` is not advertised.
- Capability JSON has recoverable current/previous generations. Malformed
  capability data is isolated from note/workspace availability and produces only
  a bounded, content-free agent error. Pending restored notes stay hidden from
  agent authority until durable workspace commit; post-commit Trash cleanup
  failure does not roll back the workspace or leave the exclusion stuck.
- The profile and note access UI exposes effective sharing, Activity, and safe
  local Undo. Folder-contained notes use the same existing note operations as
  unfiled notes when their grants authorize them.

The following are intentionally outside Phase A: expanded Discovery/context
(`list_folders`, search, backlinks, and outgoing links), Organization, Change
Sets/Proposals, Collaboration/Work Items, the Add-on SDK or registry, a
sandboxed execution broker, Context Packs, recipes, schedules, richer
automation, a community directory or marketplace, iCloud, onboarding changes,
and AI/dictation changes. Fleck remains source-available under PolyForm Shield;
this phase does not change the license.

## Clean Dictation data flow and privacy boundary

```text
microphone -> selected local speech engine -> raw transcript
  -> optional local cleanup -> focused editor OR local semantic router -> LocalStore
```

- **Standard** uses Apple's speech APIs only when on-device recognition is
  available and sets `requiresOnDeviceRecognition = true`. Unavailability is an
  error; there is no cloud fallback.
- **Enhanced Local** is a non-shippable Parakeet TDT 0.6B v2 candidate/test
  integration backed by external, data-only Core ML model content. The exact
  model revision and every file byte count and checksum are embedded in the
  application manifest. The 464,413,247-byte (442.9 MiB) model must not be
  bundled; the release gate rejects it in the current executable root or a
  future application artifact.
- FluidAudio inference is forced offline before load and inference. Release
  checks require `ModelHub.offlineMode = true` and reject code that disables
  offline mode or invokes FluidAudio model download helpers from production
  capture code.
- Microphone buffers and Enhanced float samples exist in memory only for the
  active capture and are released afterward. No audio is written to notes,
  dictation history, model storage, or logs.
- Cleanup uses the local Foundation Models framework when available. The
  debug-gated enhanced graph also contains a Gemma 3 1B candidate/test
  integration. Failure, unavailability, or an unfaithful result falls back to
  the faithful deterministic baseline without blocking persistence.
- Focused capture writes the transcript into the active editor transaction.
  Smart Capture supplies candidate UUIDs, display titles, complete local note
  bodies, and content revisions to the routing boundary. Exact-title matching
  runs first. In the debug-gated enhanced graph, the local Gemma route uses a
  bounded, memory-only cache of title and body passages, passes at most six
  relevant bounded excerpts under opaque candidate keys, and validates any
  model choice deterministically. The Foundation Models route selected when
  that framework is available remains title-based at this base. Missing,
  incomplete, stale, malformed, cancelled, or low-confidence evidence saves to
  Inbox; supported close matches are saved there before a bounded chooser is
  shown.
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

At base `63a0832728f57d6a18a4fb46d25199d90c154e71`, reviewed source plus
deterministic/synthetic tests establish contract behavior only. They do not
establish real-model human-audio replay, packaged injected-audio behavior,
packaged live-microphone behavior, two-device acceptance, signed-distribution
acceptance, or release admission for Parakeet or Gemma.

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
8. **MCP Capability Foundation Phase A (implemented, manual compatibility and distribution pending):**
   profile-scoped capabilities, explicit note/folder grants, native authority
   enforcement, recoverable capability storage, typed local same-user IPC,
   profile-filtered tools/list, revision/idempotency contracts, 30-day Activity,
   safe Undo, pending-restore privacy, and the profile/note access UI are
   implemented. Manual client compatibility, live Keychain, accessibility,
   lifecycle, packaging, signing, and distribution checks remain pending.

## Explicit non-goals for the lightweight base app

- Electron or an embedded browser runtime.
- Accounts, analytics, advertising, or mandatory network access.
- A database server or background synchronization daemon.
- Agent access to private notes, Trash, Dictation History, settings, sharing,
  note deletion, arbitrary file paths, a shell, or direct storage edits.
- Expanded MCP Discovery/context, Organization, Change Sets/Proposals,
  Collaboration/Work Items, Add-on SDK/registry, and sandboxed execution are
  deferred capabilities rather than implicit permissions.
- Bundled font collections.
- Bundled speech-model weights, cloud speech fallback, cloud cleanup/routing,
  or a mandatory AI runtime for ordinary notes.

Features that threaten the resource ceiling must be optional, isolated, measured, and justified before inclusion.
