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
- Portable tests for workspace behavior, preferences, shortcut validation, persistence, recovery, sidecars, and transfer formats.
- macOS GitHub Actions build/test coverage and scripts for release executable size and resident-memory budgets.

## Requires macOS validation

The development container is Linux, so code inside `#if os(macOS)` cannot be compiled or exercised here. The macOS CI workflow and a native development run must verify:

- AppKit and SwiftUI API compatibility with the selected Xcode toolchain.
- Editor focus, selection, undo, formatting, and list behavior.
- Drag-and-drop tab interaction and file importer/exporter presentation.
- Popover and floating-window sizing, materials, color contrast, and Reduce Transparency behavior.
- VoiceOver labels and complete keyboard focus order.
- `SMAppService` behavior in a signed application bundle.
- Signed app bundle size, idle/active resident memory, idle CPU, launch time, and typing latency.

## Remaining release work

- Replace the panel-local show/hide behavior with a system-wide hot key hosted by an explicit AppKit status-item controller. The current configurable shortcuts intentionally avoid a third-party runtime, but only operate while the panel is active.
- Add cursor, selection, scroll position, and floating-window position restoration.
- Add malformed RTF-sidecar UI reporting and optional recovery-history browsing.
- Add application icon assets, signing configuration, packaging, and release automation.
- Capture native macOS screenshots after visual review.

These items must remain visible in the pull request and cannot be declared complete based only on Linux builds.
