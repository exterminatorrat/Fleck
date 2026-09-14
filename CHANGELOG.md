# Changelog

All notable Fleck development changes are recorded here. This is development history, not a
public release log. Packaging unchanged source does not add a changelog entry.

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
