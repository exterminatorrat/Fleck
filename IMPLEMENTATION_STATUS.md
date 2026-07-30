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
  immediate unshare, per-client profiles, revocation, and visible activity.
- A separately packaged `fleck-agent` **Agent Connector** with direct JSON CLI
  and twelve-tool MCP interfaces for shared-note reads, bounded text/task
  mutations, activity, and safe Undo.
- Same-user Unix-domain IPC, Keychain-backed credentials, optimistic revisions,
  caller-owned retry IDs, durable transaction reconciliation, and 30-day
  activity/idempotency retention.
- Automated privacy probes and a static boundary audit covering UUID
  indistinguishability, excluded surfaces, helper imports/network/storage paths,
  the exact MCP surface, stdout, and generated setup snippets.
- Tests for workspace behavior, preferences, shortcuts, persistence, recovery,
  sidecars, transfer formats, dictation, agent protocol/service/bridge/UI, and
  packaging.
- macOS GitHub Actions build/test coverage and scripts for native bundle
  assembly, launch smoke testing, release executable size, resident-memory
  budgets, and agent-boundary enforcement.

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
- Add an in-app Agent Connector removal control; manual removal of the two
  receipt-owned helper files is documented in `README.md`.

These items must remain visible in the pull request and cannot be declared
complete based only on automated builds.

## Agent workspace release evidence

The automated commands and manual checklist are recorded in `TESTING.md`.
Automated evidence proves the typed and static boundaries on the current
checkout; it does not prove compatibility with installed third-party clients,
live Keychain behavior, accessibility, signing, notarization, or distribution.

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
