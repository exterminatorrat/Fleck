# Changelog

All notable Fleck development changes are recorded here. This is development history, not a
public release log. Packaging unchanged source does not add a changelog entry.

## [1.7.0-beta.1] - 2026-10-27

### Fixed

- Use the native inline folder-name field for renaming, with Return/Escape, validated
  focus-loss commits and deletion-safe editor ownership. Preserve the existing icon-based
  new-folder controls and compact Unfiled layout while keeping keyboard navigation in its
  owning host.
- Show the tab navigation rail only when intrinsic tab content overflows, restore the
  full viewport when it fits and return to the semantic leading edge as overflow ends.

This focused change is part of the shared 1.7.0-beta.1 retained-feature release cohort,
not a separate release. Source-only checkpoint: local compilation, tests and native
keyboard, focus, IME, visual and accessibility behavior remain unverified.

## [1.5.9-beta.1] - 2026-10-27

### Fixed

- Inherit the explicit interface-font correction while preserving theme/hover surfaces,
  bottom-only live-pill standby and the reviewed dictation regression guards.

Source-only dependency integration. Local compilation, tests, visual/accessibility inspection
and native behavior remain unverified; hosted verification is pending.

## [1.5.8-beta.1] - 2026-10-27

### Fixed

- Inherit the explicit interface-font correction while preserving theme propagation,
  Settings/Models appearance, neutral hover and filing regression coverage.

Source-only dependency integration. Local compilation, tests, visual/accessibility inspection
and native behavior remain unverified; hosted verification is pending.

## [1.5.7-beta.1] - 2026-10-27

### Fixed

- Inherit the explicit interface-font correction while preserving transactional multi-note
  and semantic-section filing, durable receipts, guarded undo and filing regression coverage.

Source-only dependency integration. Local compilation, tests, visual/accessibility inspection
and native behavior remain unverified; hosted verification is pending.

## [1.5.6-beta.1] - 2026-10-27

### Fixed

- Keep the selected interface font on explicitly styled Settings and Notes text while
  preserving System defaults, semantic sizes, weights, symbol sizing, monospaced diagnostics
  and editor fonts.

Source-only review correction. Compilation, tests, visual/accessibility inspection and native
behavior remain unverified locally.

## [1.5.5-beta.1] - 2026-10-27

### Fixed

- Propagate the filing codec and formatting-popover compiler repairs through the bottom-only
  dictation pill stack while preserving its reviewed source and regression guards.

Source-only integration checkpoint. Local compilation, tests and native pill behavior remain
unrun; hosted verification is pending.

## [1.5.4-beta.1] - 2026-10-27

### Fixed

- Bind formatting-toolbar popovers to the existing theme snapshot and integrate the filing
  rich-text codec compiler repair.

Source-only compiler repair checkpoint. Local compilation, tests and native appearance remain
unrun; hosted verification is pending.

## [1.5.3-beta.1] - 2026-10-27

### Fixed

- Include the existing bounded rich-text codec required by semantic-section filing without
  replacing ordinary note-appending behavior.
- Add codec round-trip and invalid-metadata regression source.

Source-only compiler repair checkpoint. Local compilation, tests and native behavior remain
unrun; hosted verification is pending.

## [1.5.2-beta.1] - 2026-10-27

### Fixed

- Return confirmed clean and raw dictation saves directly to standby without a success message,
  result actions, chooser or success-return timer.
- Keep the dictation capsule bottom-only and restore the existing live-pill artwork with
  session-bound rendered-frame receipts and control-safe hit testing.
- Reconcile standby, placement and live-artwork test source while retaining recovery and
  ownership guards.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

## [1.5.1-beta.1] - 2026-10-27

### Fixed

- Propagate the selected theme to native window backing and app-owned surfaces while preserving
  transparent material Notes and existing opaque accessibility policies.
- Align Models page/detail headers with Settings and add neutral, disabled-aware button hover.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

## [1.5.0-beta.1] - 2026-10-27

### Added

- File smart captures into validated note and semantic-section destinations with bounded,
  lossless chunks while preserving focused-caret insertion.
- Persist atomic filing receipts for retry/restart recovery and guarded whole-capture undo.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests and native behavior remain unverified.

## [1.4.13-beta.1] - 2026-10-26

### Added

- Add an optional installed-font preference for Fleck's interface while preserving the System
  default and note-text formatting.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

## [1.4.12-beta.1] - 2026-10-26

### Fixed

- Cap note-tab title labels with a semantic trailing fade while preserving full accessible titles.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

## [1.4.11-beta.1] - 2026-10-26

### Fixed

- Port theme-matched agent-update and capture-failure banner surfaces, plus an inline opt-out
  wired to the existing agent-banner preference.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

## [1.4.10-beta.1] - 2026-10-26

### Fixed

- Avoid redundant native text-view frame updates during editor layout and use stable flexible
  sizing for the notes panel root.

Source-only port; CPU behavior, native resize/rendering, compilation and tests remain unverified.

## [1.4.9-beta.1] - 2026-10-26

### Fixed

- Insert native tabs in empty plain paragraphs and populated bullet content while preserving
  list nesting, paragraph tab policies, selection undo and prefix-safe caret movement.

Source checkpoint only; Swift tests, builds, native rendering and AppKit caret blinking remain
unverified.

## [1.4.8-beta.1] - 2026-10-26

### Changed

- Adds an explicit Cursor MCP setup flow with a documented local install prompt,
  scope-preserving profile selection, cancellation and manual JSON fallback.
- Keeps prepared profiles distinct from client acceptance and verified connection.

Source checkpoint only; compilation, native UI and live client verification remain pending.

## [1.4.7-beta.1] - 2026-10-08

Private development candidate only; this correction is not an accepted build or public release.

### Fixed

- Preserve caret placement after empty list markers when indenting or outdenting, including
  numbered-list renumbering that changes marker widths.

## [1.4.6-beta.1] - 2026-10-06

Private development candidate only; the original post-sign executable reuse comparison remains
unverified. This is not an accepted build or public release.

### Changed

- Pass the selected macOS SDK version and compiler deployment target to the AppKit test-host linker.

## [1.4.5-beta.1] - 2026-10-05

Private development candidate only; this fix is not an accepted build or public release.

### Fixed

- Retire the folder name field’s hit target when its representable is dismantled, so a closed
  composer no longer consumes pointer input.

## [1.4.4-beta.1] - 2026-10-04

Private development candidate only; this correction is not an accepted build or public release.

### Fixed

- Claim the displayed Dictionary deletion request before confirmation dismissal, preserving its
  expected-revision check and single-flight protection.
- Route Settings searches for the visible Dictionary page name to the Dictionary section while
  retaining Vocabulary and Suggestions searches.

## [1.4.3-beta.1] - 2026-10-02

Private development candidate only; this correction is not an accepted build or public release.

### Fixed

- Keep dictation shortcut-help text within the Notes panel at narrow widths, allowing status and
  destination guidance to wrap without shifting its controls.

## [1.4.2-beta.1] - 2026-09-30

Private development candidate only; this change is not an accepted build or public release.

### Changed

- Added a themed custom Models search field and made outside-click focus resignation preserve the
  initiating interaction. Escape only dismisses search when its native field editor owns focus and
  passes through when another text field is active.
- Added hosted interaction coverage across themes and sizes for search focus, type filtering,
  empty-result recovery, Details/Escape behavior, and unrelated Settings-search focus.

## [1.4.1-beta.1] - 2026-09-29

Private local QA candidate only; this change is not an accepted build or public release. External
benchmark references are third-party citations, not measurements by Fleck.

### Changed

- Moved optional local model management into a Models pane in Settings, retaining search, filters,
  pins, model details, attribution, and lifecycle actions.
- Cited external Parakeet transcription and Gemma throughput results with their test conditions;
  neither verifies the exact pinned conversion, and Gemma cleanup accuracy remains unmeasured.

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
