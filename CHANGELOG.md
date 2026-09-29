# Changelog

All notable Fleck development changes are recorded here. This is development history, not a
public release log. Packaging unchanged source does not add a changelog entry.

## [1.4.0-beta.1] - 2026-09-28

Private local QA candidate only; this change is not an accepted build or public release. It makes
no model-release or benchmark claim.

### Added

- Added a dedicated Models window for optional local models admitted to the current build, with
  search, provider and type filters, stable pins, model details, attribution, and lifecycle actions.
- Added truthful local capability and storage details, a source/license/capacity review before each
  install or update, a Gemma terms-acceptance gate, and not-rated benchmark fields until suitable
  evidence is reviewed.

### Changed

- Kept Dictation capture, history, and privacy controls in Settings while moving model management
  to the Models window and retaining compact model-readiness status.

## [1.3.1-beta.1] - 2026-09-27

Private local QA candidate only; this correction is not an accepted build or public release.

### Fixed

- Use each theme's selection fill and text in the active Settings sidebar instead of macOS blue,
  while retaining native keyboard selection and accessibility semantics.

## [1.3.0-beta.1] - 2026-09-26

Private local QA candidate only; this change is not an accepted build or public release.

### Added

- Added eight semantic native palette families with System, Light, and Dark appearance modes across
  notes, the pinned editor, Settings, the dictation capsule, and agent/MCP surfaces.

### Changed

- Made palette snapshots the source of native appearance colors, while retaining legacy global color
  preference values unchanged and dormant and keeping per-note tab colors local to their notes.

## [1.2.6-beta.1] - 2026-09-26

Private local QA candidate only; this change is not an accepted build or public release.

### Changed

- Introduced B2 Fragment monochrome Fleck branding with neutral, solid surfaces by default.
- Added optional glass chrome with accessibility-aware opaque fallbacks.

## [1.2.5-beta.1] - 2026-09-26

Private local QA candidate only; this correction is not an accepted build or public release.

### Fixed

- Close the Dictionary Sort by popover on Escape before handling search dismissal when the sort
  trigger retains keyboard focus.

## [1.2.4-beta.1] - 2026-09-26

Private local QA candidate only; this change is not an accepted build or public release. It adds no
automatic suggestion generation and makes no model or runtime claim.

### Changed

- Removed the permanent All, Enabled, Disabled, and Suggestions tabs. Moved search, sort, and
  reload into the Dictionary header beside Add new. Show Review suggestions (N) only when a
  suggestions queue exists, and Back to words while that queue is active. Retained the real enable
  switch, Disabled label, and imported-suggestions flow.

## [1.2.3-beta.1] - 2026-09-25

Private local QA candidate only; this change is not an accepted build or public release. It makes
no model-readiness claim and adds no runtime usage tracking.

### Changed

- Replaced the rounded-pill Dictionary filter focus treatment with an underline and let row-hover
  backgrounds extend edge-to-edge beneath the card clip.
- Added a compact `SORT BY` popover with `A–Z`, `Z–A`, `Recently used`, and `Most used` options.
  Starred entries stay pinned, and the popover notes that usage-based ordering uses saved usage
  only, not runtime tracking.

## [1.2.2-beta.1] - 2026-09-25

Private local on-device QA only; this correction is not an accepted build or public
release and makes no model-release, model-behavior, or runtime claim.

### Fixed

- Restored global Settings search inside the sidebar, between the native red and
  yellow title-bar traffic lights and the original Fleck section heading above
  General. The search now sits with nearly equal upper and lower gaps (within
  one point in hosted tests), restoring the native Fleck/General grouping while
  leaving detail page content unchanged and preserving search focus and result
  behavior.

## [1.2.1-beta.1] - 2026-09-25

Private local on-device QA candidate only; this is not an accepted build or public release, and no
model release or model behavior is claimed.

### Changed

- Kept dictionary entries in one shared rounded list card with dividers; each full word row remains
  an always-actionable Edit target, while hover or focus reveals the delete and star icons. Starred
  entries stay above unstarred entries in either alphabetical sort order, and deletion requires
  confirmation.
- Aligned the Fleck heading and global Settings search on the title-bar top row beside the traffic
  lights, and made keyboard focus treatment neutral across folder navigation, dictionary controls,
  and Settings search.
- Applied the same title inset to pinned and unpinned notes so note titles align with editor text.

## [1.2.0-beta.1] - 2026-09-25

Local development candidate only. This entry is not an accepted or public
release and makes no model release, model admission, or runtime claim.

### Added

- Added global Settings search across sections and controls, with keyboard navigation and
  in-context targeting for Dictionary, About metadata, and Agent controls.

### Changed

- Refined Settings and Dictionary presentation, grouping Dictionary filters and transfer actions
  under Options while keeping search reveal distinct from performing a control action.
- Retained the native disclosure style and made search targets expand relevant About, Agent, and
  Privacy disclosures.

### Fixed

- Restored window-scoped Dictionary `⌘F` routing while Vocabulary is selected. The shortcut leaves
  global Settings search undisturbed and does not present local search over an active modal sheet.

## [1.1.2-beta.2] - 2026-09-18

First public **Developer Preview** release. This entry is the public preview record for
version `1.1.2-beta.2`; it carries the reviewed editor-toolbar integration, the stabilized
Agent Activity scrollbar, and the CI verification fixes on top of the accumulated 1.x
development history recorded below. The `-beta.2` iteration follows the internal
`1.1.2-beta.1` development identity so the public preview is never mistaken for a stable
release.

For the full technical summary and first-launch onboarding, see
[`docs/release-notes/1.1.2-beta.2.md`](docs/release-notes/1.1.2-beta.2.md).

## [1.1.2-beta.1] - 2026-09-17

### Added

- Expanded the editor toolbar with visual text styles, paragraph alignment and spacing,
  indentation, clear and copied formatting, safe web and note links, in-note find and replace,
  baseline controls, and Unicode-aware case conversion.

### Changed

- Added the reviewed compact Text, Paragraph, and Tools icons while retaining textual overflow
  menus, truthful accessibility state, measured ordered overflow, a leading microphone, and a
  trailing Delete action.

### Fixed

- Preserved current rich-text, list, note-link, inline-image, selection, undo, and canonical-save
  behavior across the expanded commands and their guarded delayed targets.

## [1.0.21-beta.1] - 2026-09-17

### Fixed

- Replaced the Agent Activity scrollbar's adaptive thumb paint with a stable four-point capsule
  that keeps its size while hovered or dragged without changing native scrolling behavior.

## [1.0.20-beta.1] - 2026-09-17

### Changed

- Made the full padded header row activate Dictation Privacy, Agent Activity, Agent Access,
  and Full build metadata disclosures while keeping their content controls independent.

## [1.0.19-beta.1] - 2026-09-17

### Fixed

- Made the Agent Activity scrollbar track transparent while keeping the complete native thumb
  draggable and positioned five points inside the panel edge.

## [1.0.18-beta.1] - 2026-09-16

### Changed

- Polished the font picker with neutral full-row hover and selection feedback, a trackless
  native scrollbar aligned to the popover edge, and a compact layout that remains usable at
  narrow widths.

### Fixed

- Aligned font names and previews to a shared row baseline and reserved a consistent trailing
  preview column in the font picker.

## [1.0.17-beta.1] - 2026-09-16

### Changed

- Folder creation now stays within the folder navigation row, and paired folder navigation
  controls appear only when measured folder content exceeds the available viewport.

## [1.0.16-beta.1] - 2026-09-16

### Fixed

- Kept Delete fixed at the trailing edge of the editor toolbar while earlier formatting
  commands move into measured overflow at narrower widths.
- Allowed menu-panel resizing and saved menu dimensions to use the current screen's usable
  bounds instead of an arbitrary 800-point ceiling.
- Removed forced immediate display and repeated diagonal-cursor creation from live drag updates
  while preserving synchronous frame adoption and release behavior.

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
