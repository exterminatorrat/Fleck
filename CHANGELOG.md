# Changelog

All notable Fleck development changes are recorded here. This is development history, not a
public release log. Packaging unchanged source does not add a changelog entry.

## [1.0.15-beta.1] - 2026-09-16

### Changed

- Formatting toolbar buttons now show a clear, theme-adaptive hover background across their
  existing click targets without shifting the layout.

## [1.0.14-beta.1] - 2026-09-16

### Added

- Added a tint-free top-edge blur to the note editor that ramps in while scrolling and honors
  Reduce Transparency.

## [1.0.13-beta.1] - 2026-09-16

### Changed

- Renamed the Options menu's Import action to "Import Text or Markdown…" to clarify the
  supported file formats.

## [1.0.12-beta.1] - 2026-09-15

### Added

- Dropped and pasted image files now render inline at their full display height, while saved notes
  and agent responses retain managed local-file references instead of embedded image data.

## [1.0.11-beta.1] - 2026-09-15

### Changed

- Replaced the attached-file shelf with a compact single-row Add control, filename chips, and
  overflow count while retaining the existing file actions.

### Fixed

- Presented the native file chooser independently of the transient menu host, suppressed
  duplicate chooser requests, and passed shortcuts through while a modal window is active.

## [1.0.10-beta.1] - 2026-09-14

### Fixed

- Kept the pinned editor title opaque with adaptive native text color and aligned its text
  origin with the note body.
- Aligned checklist circles with native body typography across fonts, sizes, completion states,
  and nesting.

## [1.0.9-beta.1] - 2026-09-14

### Fixed

- Selected note tab labels use solid white in both light and dark appearance.

## [1.0.8-beta.1] - 2026-09-14

### Fixed

- Kept the Agent Activity header at the top and its empty state centered across supported sizes.

## [1.0.7-beta.1] - 2026-09-14

### Fixed

- Removed the faint rounded rectangular backing from dragged note tabs while preserving the
  selected capsule, captured tab content, and transparent padding.

## [1.0.6-beta.1] - 2026-09-13

### Changed

- Removed the active-capture destination guidance banner above the editor.

## [1.0.5-beta.1] - 2026-09-13

### Fixed

- Made Escape cancel every active dictation capture, including toolbar, modifier-hold, and
  capsule starts, with plain Escape or the configured Option, Control, or Command modifier.

## [1.0.4-beta.1] - 2026-09-13

### Changed

- The selected note-tab capsule now travels and resizes smoothly between tabs while note
  selection and editor updates remain immediate.

## [1.0.3-beta.1] - 2026-09-13

### Added

- Added a persisted setting to hide routine agent update banners while keeping Agent Activity
  available for review.

### Changed

- Integrated the dictation capsule presentation from source commit
  `72f81e561cc75c5a19fbad69c7546d97686fcda1`: active dictation uses a single 36-point row,
  the 13-bar waveform uses the reviewed spacing, and settled results and choosers retain their
  centered, content-aware placement.

## [1.0.2-beta.1] - 2026-09-12

### Fixed

- Restored the prior Notes editor polish from source commit
  `cc6fcfb6b9955eab9de4d3a902e8be9fe33e0b44`: editor content is clipped to the panel bounds,
  the font-family trigger remains readable at full and compact widths, and compact toolbar
  spacing is tightened.

## [1.0.1-beta.1] - 2026-09-12

### Changed

- New app bundles, handoff folders, launchers, and ZIPs use their captured product version and
  build number in the artifact name.
- Packaging consumers use per-invocation result files instead of fixed or newest-build paths.

## [1.0.0-beta.1] - 2026-09-11

### Added

- Added durable product-version and packaged-build identity metadata.
- Added native build information in Settings → About with a copy action.
- Added canonical accepted-baseline verification to Fleck packaging workflows.
