# Implementation status

This document distinguishes implemented behavior from work that still requires native macOS validation or release infrastructure.

## Implemented

- Native `MenuBarExtra` panel plus a separately openable floating notes window.
- Multiple notes with create, close, select, adjacent navigation, drag reordering, context-menu movement, and pinning.
- AppKit `NSTextView` editor with native undo/redo, spelling, selection-aware bold, italic, underline, strikethrough, installed fonts, bullets, numbering, list continuation, list exit, and indentation.
- Readable per-note Markdown bodies and optional RTF sidecars that preserve formatting Markdown cannot represent.
- Debounced atomic saves, format-versioned manifests, a previous-generation recovery snapshot, and recovery from malformed manifests, preferences, and missing note bodies.
- Plain-text and Markdown import plus plain-text, Markdown, and RTF export.
- System/light/dark themes, installed-font selection, font size, accent color, optional editor colors, glass intensity, panel dimensions, formatting-bar visibility, and automatic-list preferences.
- Editable, removable, and restorable shortcuts with normalization and duplicate-conflict warnings. Configured shortcuts are active while the panel is open.
- Launch-at-login integration through `SMAppService` when running as a packaged macOS application.
- Explicit per-note Agent Access with first-share confirmation, shared badges,
  immediate unshare, per-client profiles, revocation, effective-sharing badges,
  profile and note access editing, and visible Activity.
- A separately packaged `fleck-agent` **Agent Connector** with direct JSON CLI
  and the static exact 13 existing MCP registrations for profile-filtered
  shared-note reads, bounded text/task mutations, Activity, and safe Undo.
- Same-user Unix-domain IPC, Keychain-backed credentials, optimistic revisions,
  caller-owned retry IDs, durable transaction reconciliation, and 30-day
  activity/idempotency retention.
- Automated privacy probes and a static boundary audit covering UUID
  indistinguishability, excluded surfaces, helper imports/network/storage paths,
  the exact MCP surface, stdout, and generated setup snippets.
- Tests for workspace behavior, preferences, shortcuts, persistence, recovery,
  sidecars, transfer formats, dictation, agent protocol/service/bridge/UI, and
  packaging.
- Mandatory, resumable first-launch onboarding with the real Fleck note editor
  and dictation runtime, individually optional permission steps, truthful
  compatibility details, and an access-action boundary for trial, purchase,
  and restore.
- macOS GitHub Actions build/test coverage and scripts for native bundle
  assembly, launch smoke testing, release executable size, resident-memory
  budgets, and agent-boundary enforcement.

## Local writing candidate status at `63a0832`

- Standard Apple on-device speech, deterministic dictionary resolution,
  faithful cleanup fallback, focused insertion, Smart Capture persistence, and
  history are present in the ordinary source graph. The coordinator also owns
  the receipt-bound Inbox-first chooser mechanics used by an ambiguous router.
- The enhanced debug graph contains Parakeet TDT 0.6B v2 dictation and Gemma 3
  1B cleanup/local routing as candidate/test integrations. It supplies complete
  local note bodies and revisions to a bounded memory-only routing index;
  deterministic unique evidence may resolve a note, while supported close
  matches are saved to Inbox before a chooser. The available Foundation Models
  route remains title-based at this base.
- The 2026-08-29 baseline at exact commit
  `63a0832728f57d6a18a4fb46d25199d90c154e71` recorded 63 focused routing tests
  passing, 123 focused cleanup tests passing, and 96 focused enhanced-candidate
  integration tests passing. The ordinary 1,674-test suite has two
  reproducible pre-existing failing tests (three recorded issues); the exact
  commands and failures are in `TESTING.md`.
- This is source plus deterministic/synthetic contract evidence only. No
  real-model human-audio replay, packaged injected-audio run, packaged
  live-human microphone run, two-device candidate acceptance, signed
  distribution acceptance, or release admission is recorded.

## MCP Capability Foundation Phase A

The accepted Phase A implementation adds a narrow, profile-scoped capability
authority around the existing note command surface:

- The current capabilities are `notes.list`, `notes.read`, `notes.write`, and
  `changes.undo`. New profiles start with no tools or scopes.
- Grants are explicit per note or explicit `folderIncludingFutureNotes`. The
  latter requires confirmation and is off by default. Current notes are
  materialized as direct grants; future-note inheritance is never implicit.
- Legacy `Note.agentAccess` data is migrated to direct grants for active
  profiles. Legacy shares without an active profile remain unassigned until the
  user explicitly assigns them. New profiles do not receive legacy shares.
- The native authority checks every command and rechecks the workspace revision
  before protected reads return and before writes commit. Unknown, private, and
  unauthorized targets remain indistinguishable.
- Wire v1 remains compatible. Internal v2 `getCapabilities` is typed,
  non-mutating, and not a user-facing CLI command. MCP `tools/list` is recomputed
  on every request, filters the static exact 13 existing registrations, and does
  not advertise `listChanged`.
- Capability storage has recoverable current/previous generations. Malformed
  capability data is isolated from note availability and reports only a bounded,
  content-free agent error.
- Pending restored notes remain excluded from agent authority until durable
  workspace commit. A Trash cleanup failure after that commit keeps the workspace
  result and exposes only a bounded recoverable cleanup error.
- Folder-contained notes are already reachable through the existing note
  operations when the profile's Agent Access grant authorizes them; Phase A does
  not add a separate folder-access mechanism.

### Deferred MCP scope

The following are not implemented: expanded Discovery/context tools
(`list_folders`, search, backlinks, outgoing links, or related-note traversal),
Organization, Change Sets/Proposals, Collaboration/Work Items, per-agent
capability features beyond the Phase A authority, Add-on SDK/registry,
sandboxed execution broker, Context Packs, recipes, schedules, richer
automation, community directory/marketplace, iCloud, onboarding changes, and
AI/dictation changes. The license remains PolyForm Shield/source-available and
was not changed.

### Phase A automated and release evidence

Fresh code review of exact implementation head
`1671792fca311af4b66efff3c96fe0d1a560f22d` returned exactly **ship** before
the documentation task. The parent release verification recorded:

- `swift test --disable-automatic-resolution --no-parallel`: exit 0, 994 tests
  in 14 suites.
- `swift build -c release --product Fleck`: exit 0.
- `swift build -c release --product fleck-agent`: exit 0.
- `Scripts/audit-agent-boundary.sh`: exit 0, including the exact 13-tool
  surface, local IPC boundary, and no storage fallback.
- `Scripts/check-release-size.sh`: exit 0. Latest sizes were Fleck
  10,803,712 bytes and `fleck-agent` 11,171,312 bytes, both below the 15 MiB
  Fleck budget.
- `Scripts/validate-macos.sh`: exit 0 on rerun. The first run encountered one
  existing `WorkspaceSearchHosting` timing flake after a separate full 994/994
  pass; the rerun passed.
- `Scripts/build-fleck-app.sh`: exit 0.
- `codesign --verify --deep --strict .build/Fleck.app`: exit 0.
- `git diff --check`: exit 0.

The environment was arm64 macOS 26.2 build 25C56, Xcode 26.6 build 17F113,
Swift 6.3.3. Development ad-hoc packaging and codesign verification passed;
that is not distribution signing evidence.

GitHub CI remains pending until the branch and pull request are pushed.
Interactive packaged-app/manual workflows, installed Codex/Claude/Kimi/generic
clients, live Keychain, accessibility, Full Keyboard Access, Reduce Motion,
multiple-window, sleep/wake, five-minute idle, distribution signing,
notarization, and App Store gates remain pending or unrecorded.

## Requires macOS validation

Automated builds and tests compile the macOS-only code, but the following
physical-device or interactive behavior still requires recorded manual evidence:

- AppKit and SwiftUI API compatibility with the selected Xcode toolchain.
- Editor focus, selection, undo, formatting, and list behavior.
- Drag-and-drop tab interaction and file importer/exporter presentation.
- Popover and floating-window sizing, materials, color contrast, and Reduce Transparency behavior.
- VoiceOver labels and complete keyboard focus order.
- `SMAppService` behavior in a signed application bundle.
- Signed app bundle size, idle/active resident memory, idle CPU, launch time, and typing latency.
- Codex, Claude Code, Kimi, and generic CLI setup against separate temporary
  profiles, including read/write/conflict/retry/Undo behavior.
- Profile revocation during idle and in-flight requests, immediate unshare,
  non-activating launch, interrupted-transaction recovery, multi-window
  interaction, sleep/wake, and bridge idle CPU.
- Live Keychain credential creation/removal and accessibility review of Agent
  Access, profiles, activity, banners, and Undo.

## Remaining release work

- Replace the panel-local show/hide behavior with a system-wide hot key hosted by an explicit AppKit status-item controller. The current configurable shortcuts intentionally avoid a third-party runtime, but only operate while the panel is active.
- Add cursor, selection, scroll position, and floating-window position restoration.
- Add malformed RTF-sidecar UI reporting and optional recovery-history browsing.
- Add application icon assets, signing configuration, packaging, and release automation.
- Capture native macOS screenshots after visual review.
- Replace `UnavailableFleckAccessActions` with the later StoreKit 2 access
  subsystem, including the localized lifetime price, authoritative trial and
  purchase state, restore, seven-day expiry, and read-only enforcement. Until
  then, Get Fleck intentionally cannot mark onboarding complete.
- Add an in-app Agent Connector removal control; manual removal of the two
  receipt-owned helper files is documented in `README.md`.

These items must remain visible in the pull request and cannot be declared
complete based only on automated builds.

## Agent workspace release evidence

The automated commands and manual checklist are recorded in `TESTING.md`.
Automated evidence proves the typed and static boundaries on the current
checkout; it does not prove compatibility with installed third-party clients,
live Keychain behavior, accessibility, signing, notarization, or distribution.

The historical record below predates the MCP Capability Foundation Phase A and
is retained as release-validation history, not as current Phase A evidence.

Recorded 2026-07-29 from source base
`264f988beee8fbca79415797d1cf0222916ec4b3` on arm64 macOS 26.2 (25C56),
Xcode 26.6 (17F113), and Swift 6.3.3:

- `swift test`: **471 tests in 8 suites passed** on the fresh release-validation
  rerun.
- Unsigned release `Fleck` executable: **5,551,416 bytes** against the unchanged
  15 MiB budget.
- Separately packaged `fleck-agent` helper: **10,458,296 bytes**.
- Official MCP Swift SDK tag/revision: **0.12.1** /
  **`a0ae212ebf6eab5f754c3129608bc5557637e605`**.
- Codex, Claude Code, and Kimi setup syntax was rechecked on 2026-07-29
  against their official
  [Codex](https://developers.openai.com/codex/mcp),
  [Claude Code](https://docs.anthropic.com/en/docs/claude-code/mcp), and
  [Kimi](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/mcp.html)
  MCP documentation.
- `swift build`, `swift build -c release`, `Scripts/audit-agent-boundary.sh`,
  `Scripts/validate-macos.sh`, and the native bundle launch smoke test passed.
- One earlier full-suite attempt hit the pre-existing
  `wrongUnknownAndRevokedProfilesArePermissionRevoked` raw-JSON-key-order
  assertion twice. Its isolated rerun and the subsequent complete 470-test run
  passed; no unrelated source or test was changed.

Manual Codex, Claude Code, Kimi, generic CLI, live Keychain, VoiceOver,
multi-window, sleep/wake, signing, notarization, and distribution validation
remain **PENDING** exactly as listed in `TESTING.md`.
