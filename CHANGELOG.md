# Changelog

All notable Fleck development changes are recorded here. This is development history, not a
public release log. Packaging unchanged source does not add a changelog entry.

## [1.7.9-beta.1] - 2026-11-02

### Fixed

- Send Escape from the font-family table directly to its owning picker's cancellation
  callback, matching the existing explicit Return route instead of relying on table key handling.

## [1.7.8-beta.1] - 2026-11-02

### Fixed

- Publish tab-strip content-width changes after AppKit layout instead of mutating SwiftUI
  state from the preference callback during native resize constraints.
- Restore the prior accessibility mode after the tab-strip native fixture closes.

## [1.7.7-beta.1] - 2026-11-02

### Fixed

- Route a pending capsule recovery mouse release through the pressed gesture's generation
  guard, so replacing a recovery action between press and release cannot accept the new action.
- Restore explicit ambiguous-routing inputs and nanosecond-aligned event timestamps in the
  combined recovery fixtures without weakening their ownership or exact-event assertions.

## [1.7.6-beta.1] - 2026-11-02

### Fixed

- Embed and sign the already-linked Sparkle framework in development packages, and bind the
  staged executable to its embedded copy so an extracted app does not depend on build paths.
- Preserve framework-free packages when the executable does not link Sparkle.

Development candidate only; not an accepted or notarized release.

## [1.7.5-beta.1] - 2026-11-01

### Fixed

- Keep keyboard focus in the vocabulary search field when search is reopened; clearing the
  trigger focus in the same update could leave the Settings window itself focused.
- Refuse an event-subscription refresh at the maximum stored revision before staging a new
  signing key, instead of overflowing after the key is written.
- Delete note-tab title fixture storage only after runtime shutdown completes.
- Keep the Namespace macOS runner display awake during AppKit-hosted CI tests.

Combined development candidate integrating the open pull-request stack (#68–#93) with these
repairs. Not an accepted release.

## [1.7.4-beta.1] - 2026-10-30

### Fixed

- Inherit the reviewed root/folder-row focus-wrapper prerequisite without importing
  unrelated folder-creation or rename-editor changes.
- Inherit the folder-ID School-row fixture correction and strict visual/focus-layer
  association regression coverage instead of selecting a row by a fixed width.

Source-only dependency inheritance, not a new feature or proved runtime recovery.
Compiler checks, test discovery/tests and native/visual/accessibility checks on this
current source remain unrun.

## [1.7.3-beta.1] - 2026-10-30

### Fixed

- Inherit the reviewed menu-panel native-frame adoption repair, including interaction
  ownership/revision fencing, reentrant rollback and unchanged-axis validation.
- Preserve observable size updates and immediate/deferred publication ordering with the
  complete reviewed native-adoption regressions and existing display coverage.

Source-only dependency inheritance. Compiler checks, test discovery/tests and native,
real-event, display and pixel behavior in this source context remain unverified.

## [1.7.2-beta.1] - 2026-10-30

### Fixed

- Project the Activity scrollbar thumb origin into overlapping native-knob and track
  intervals only for finite usable geometry, preserving width and length. Outside that
  domain, geometry remains unchanged and unqualified.
- Retain the corrected held-entry origin and original proportional motion reference,
  with full-rectangle continuity regression coverage and held-state cleanup on release.

Source-only candidate. Compiler checks, tests, native tracking, real-event behavior and
pixel behavior remain unverified.

## [1.7.2-beta.1] - 2026-10-29

### Fixed

- Ignore earlier and later folder overflow actions while a new folder is being composed,
  including actions sent through retained accessibility controls.
- Cover retained overflow actions from both scroll endpoints while preserving existing
  pointer-path geometry and mounted scroll/document identity checks.

Source-only repair checkpoint. Compilation, native behavior and full CI for this combined
candidate remain unverified.

## [1.7.1-beta.1] - 2026-10-29

### Fixed

- Keep the Activity scrollbar thumb proportionally positioned within the native knob by
  preserving fractional vertical coordinates, with quarter-position regression coverage.

Source-only correction. Compilation, tests and native visual behavior remain unverified.
- Add native destination chooser actions to the dictation capsule menu, rejecting
  stale items after a newer presentation, capture replacement, or choice change.
- Align capsule accessibility fixtures with recovery routing, wait for matching live-pill
  render receipts, and register runtime waiters before opening load gates.
- Retain the controller's routing chooser only when its capture and context are
  still displayable.

Source-only validation. Tests, compilation, native/visual/accessibility validation,
hosted CI, and packaging were not run.

## [1.7.0-beta.1] - 2026-10-27

### Fixed

- Align wrapped checklist content without changing paragraph formatting, preserve completion
  formatting while typing and pasting, and restore checklist selection through undo and redo.
- Keep selected bullet glyphs free of selection highlights without replacing configured
  backgrounds, and copy whole list items and managed-image references without changing selections.
- Preserve relative paragraph tail indents through editor loading and saving, dictated
  appends and agent rich-text mutations without changing their existing fallback or error behavior.
- Commit font-size changes only after editing, with a centered field, hover/focus underline
  and a native Mixed placeholder that leaves the numeric edit string empty.
- Retain edited font sizes when the overflow popover closes without committing direct-field
  drafts during toolbar reflow.

This checkpoint is part of the retained-feature 1.7.0-beta.1 development cohort, not a
separate release. Local compilation, tests and native visual/accessibility behavior remain
unrun; hosted verification is pending.

## [1.7.0-beta.1] - 2026-10-27

### Added

- Add native status-menu actions for Notes, Settings and About while preserving Quit,
  secondary-click behavior and an explicitly unavailable update check.
- Add explicit signed update-information checks shared by About and the status menu,
  remaining unavailable without trusted configuration and packaged identity. Checks
  do not download or install updates, and do not verify release artifact bytes.

This focused layer belongs to the retained-feature 1.7.0-beta.1 release cohort.
Local compilation, tests and native visual/accessibility behavior remain unverified.
- Use the native inline folder-name field for renaming, with Return/Escape, validated
  focus-loss commits and deletion-safe editor ownership. Preserve the existing icon-based
  new-folder controls and compact Unfiled layout while keeping keyboard navigation in its
  owning host.
- Show the tab navigation rail only when intrinsic tab content overflows, restore the
  full viewport when it fits and return to the semantic leading edge as overflow ends.

This focused change is part of the shared 1.7.0-beta.1 retained-feature release cohort,
not a separate release. Source-only checkpoint: local compilation, tests and native
keyboard, focus, IME, visual and accessibility behavior remain unverified.
- Keep raw fallback outcomes honest across cleanup service failure, OS/backend
  unavailability, deadlines and cancellation while preserving dictionary-protected forms.
- Carry insertion-versus-persistence failure provenance through dictation contexts
  without changing receipt-backed recovery or successful-save standby.
- Present session-bound dictation error recovery with guarded retry, copy and Settings
  actions, and actual model-repair activity that does not interrupt an active capture.
- Preserve bottom-only live-pill placement, direct saved-result standby, accessibility,
  reduced motion and monotonic waveform behavior with retained synthetic regressions.

Part of the shared retained-feature 1.7.0 cohort, not a separate release.
Source-only preparation. Local compilation, tests, native/visual/accessibility behavior
and packaging remain unverified; hosted verification is pending.
- Add opt-in, bounded Apple Speech lifecycle diagnostics with per-attempt cancellation,
  reservation ownership, first-buffer and conversion receipts, without transcript or device data.
- Retain the first failure, redact unknown error domains, and balance release receipts when
  asynchronous teardown overlaps without changing capture ownership.

Source-only capture/diagnostics constituent of the retained-feature 1.7 release cohort.
Local compilation, tests and native capture behavior remain unrun; hosted verification is pending.

## [1.7.0-beta.1] - 2026-10-27

### Changed

- Preserve pending dictation and cleanup model requests for startup-only application,
  retaining the existing Parakeet v2 and Gemma 4-bit defaults and coupled cleanup/filing.
- Bind the retained Gemma 8-bit specification to exact metadata and fail-closed identity,
  license, cleanup/filing evidence, measured RAM and storage requirements.
- Label model settings from the actual descriptor instead of assigning a known model's
  name to an unknown identity.

This is one constituent of the shared 1.7.0-beta.1 development cohort, not a separate
release or a qualified alternative model. No alternative availability or selection UI is
added. Local compilation, tests and native/model behavior remain unverified.
- Add bounded MCP stdio transport and modern request dispatch while retaining legacy tools,
  request ownership, cancellation, output ordering and EOF settlement.
- Add strict version-2 event contracts and wire compatibility checks. Subscription execution
  and callback delivery remain unavailable in this foundational layer.
- Add the content-free event journal with snapshot integrity/history fencing, default-off
  scoped observation authority, global privacy exclusions and pending subscription/key lifecycle
  persistence. Event commands and callback delivery remain unavailable until the next layer.
- Connect owner-approved event subscriptions, verified HTTPS callbacks, signed delivery,
  bounded outbox/receipt handling and global privacy controls. Observation remains off by
  default and delivery requires current authorization, endpoint verification and owner consent.

### Fixed

- Handle closed output pipes without SIGPIPE termination, forward legacy notification-only
  batches without responses, preserve cancellation ownership and reject unsupported replay age.
- Fail closed on interrupted privacy-policy generations and pending-subscription lookups
  behind the persisted trusted-clock watermark.

### Fixed - 2026-10-28

- Bind renewal choices and owner approvals to the current subscription control generation,
  so an expired or recreated subscription cannot reuse an earlier checked renewal choice.

This is one constituent of the shared 1.7.0-beta.1 retained-feature development cohort, not a
separate release. Local compilation, tests and native behavior remain unrun; hosted checks are
pending. Existing 1.6.x candidates and all earlier development history remain preserved.

## [1.7.0-beta.1] - 2026-10-28

### Fixed

- Keep process-transport completion open until bounded stderr validation and graceful drain
  finish, while streaming request lifecycle events without waiting for process shutdown.

Part of the approved substantial development cohort. Source-only correction; compilation,
process tests and native behavior remain unverified locally.

## [1.5.13-beta.1] - 2026-10-31

### Fixed

- Source readiness Escape-return requests from the trigger's bound native attachment and
  hand them directly to the existing guarded focus consumer before dismissing the popover.
- Add regression coverage for bound-window/current-input publication and clearing stale
  requests when the producer's native attachment is unbound or detached.

Source-only CI repair candidate. Compilation, tests and hosted keyboard/accessibility
behavior remain unrun; prior public CI is red and Dictionary/Appearance failures remain open.
No passing CI, unchanged-head recovery or test-build delivery is claimed.

## [1.5.12-beta.1] - 2026-10-30

### Fixed

- Explicitly dismiss the existing readiness popover on Escape and request return to its
  trigger through the existing public focus state only while its native attachment,
  active key window and original keyboard-input generation remain current.
- Add regression coverage for stale native attachments and intervening pointer/key input,
  and bounded diagnostic observations for existing Dictionary and Appearance CI failures.

Source-only CI repair candidate. Compilation, regression execution, native keyboard and
accessibility restoration remain unverified; no passing CI or test-build delivery is claimed.

## [1.5.10-beta.1] - 2026-10-30

### Fixed

- Correct the readiness-popover fixture's unsupported trigger-focus retention assumption
  with semantic coverage of existing keyboard entry, actions, traversal, dismissal and return.
- Make the existing System Settings actions recordable in that fixture while preserving
  their original default runtime delegation; no actions or production focus policy change.

Source-only CI repair candidate. Compilation, tests, native keyboard/accessibility and
current-context checks remain unrun for this change; no passing behavior, CI or test-build
delivery is claimed.

## [1.5.10-beta.1] - 2026-10-29

### Fixed

- Inherit the explicit interface-font correction while preserving theme/hover surfaces,
  bottom-only live-pill standby and the reviewed dictation regression guards.

Source-only dependency integration. Local compilation, tests, visual/accessibility inspection
and native behavior remain unverified; hosted verification is pending.

## [1.5.9-beta.1] - 2026-10-27

## [1.5.9-beta.1] - 2026-10-29

### Fixed

- Balance native Settings traffic lights against measured sidebar search and header frames,
  retaining calibrated placement while the header is hidden.
- Add geometry/cache regression coverage and encode the Models reverse-Tab fixture with
  AppKit's backtab character.

Source-only repair checkpoint. Compilation, tests and native/visual/accessibility validation
remain unrun for this change; hosted CI has not run for this checkpoint. Readiness focus
ownership remains unresolved.

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
- Use AppKit's supported light/dark appearance assignment so system accessibility contrast
  remains authoritative, and preserve rectangular padded hit targets beneath rounded hover paint.
- Match Models keyboard-focus regression coverage to its dynamically updated native key loop.

Source-only dependency integration. Local compilation, tests, visual/accessibility inspection
and native behavior remain unverified; hosted verification is pending.

## [1.5.7-beta.1] - 2026-10-27

### Fixed

- Inherit the explicit interface-font correction while preserving transactional multi-note
  and semantic-section filing, durable receipts, guarded undo and filing regression coverage.
- Keep mixed-marker fence closers from exposing code-block headings as filing destinations.
- Reject backtick fence openers whose info contains a backtick while preserving valid
  backtick and tilde fences, including indented longer matching closers.
- 2026-10-29: Honor explicit Inbox routing without unrelated destination suggestions while
  preserving ambiguous/invalid-route fallback, durable receipts, history and undo.

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

## [1.4.43-beta.1] - 2026-11-01

### Fixed

- Use the Trash row's accessibility frame to locate the native folder-scroll band
  without depending on the first folder remaining exposed.

Source checkpoint only; CI and native verification remain pending.

## [1.4.42-beta.1] - 2026-11-01

### Fixed

- Integrate the reviewed retained folder-overflow action guards and complete fixture changes
  while preserving the existing editor and native resize checkpoints.

Source prerequisite only; the new combined source is uncompiled and runtime verification is unrun.
Recovery of the composition failure and full native behavior remain unverified.

## [1.4.39-beta.1] - 2026-11-01

### Fixed

- Ignore retained folder-overflow actions while creating a folder.
- Carry the retained-action regression and await once-only folder-fixture teardown after runtime shutdown.

Source prerequisite only; new source is uncompiled and runtime verification is unrun.
No recovery of another source's composition failure is claimed.

## [1.4.38-beta.1] - 2026-11-01

### Fixed

- Integrate the reviewed aligned-geometry resize reentry guard with the existing editor
  and native fractional-resize checkpoints.

Source checkpoint only; compilation and native verification remain pending. Recovery of the
predecessor's failures and direct nil/nonfinite event-adapter injection coverage remain unverified.

## [1.4.35-beta.1] - 2026-11-01

### Fixed

- Allow panel-resize reentry when native geometry is already aligned while deferred reconciliation remains queued.

Source repair candidate only; this guard remains uncompiled and native verification is unrun.
Recovery of the predecessor's rollback/restart failures and direct nil/nonfinite event-adapter
coverage remain unverified.

## [1.4.34-beta.1] - 2026-11-01

### Fixed

- Integrate the reviewed legacy-compatible native fractional-resize correction with the
  existing editor and activity scrollbar checkpoints.

Source checkpoint only; compilation and native verification remain pending. Direct nil/nonfinite
event-adapter injection coverage remains open.

## [1.4.31-beta.1] - 2026-10-31

### Fixed

- Preserve canonical pointer coordinates and native size readback during fractional panel resizing.
- Fence resize publication, rollback and commit against stale interaction revisions and ownership.

Source checkpoint only; compilation and native verification remain pending. Direct nil/nonfinite
event-adapter coverage remains open.

## [1.4.30-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed activity scrollbar geometry and tracking correction while preserving
  the native Tab and bullet-caret editor checkpoint and its prior parent corrections.

Source checkpoint only; combined compilation and native verification remain pending.

## [1.4.27-beta.1] - 2026-10-31

### Fixed

- Keep the activity scrollbar's visual knob within native knob geometry at fractional positions.
- Preserve the initial visual knob rectangle when native tracking begins and retain held-size behavior.

Source checkpoint only; compilation and native verification remain pending.

## [1.4.26-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed Dictionary capture, folder overflow/focus, Settings spacing and Models
  Backtab corrections while preserving capped, fading note-tab titles and full accessible labels.

Source-only dependency integration; this checkpoint's CI and native validation remain pending.

## [1.4.25-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed Dictionary capture, folder overflow/focus, Settings spacing and Models
  Backtab corrections while preserving theme-matched banners, inline opt-out and native resizing.

Source-only dependency integration; this checkpoint's CI and native validation remain pending.

## [1.4.24-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed Settings spacing, Models Backtab and folder-row focus/School fixture
  corrections while preserving native resize, scrollbar tracking and folder-creation guards.

Source checkpoint only; this combined source's CI and native/visual verification remain pending.

## [1.4.23-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed Settings chrome, Models Backtab and folder-row focus/School fixture
  corrections while preserving the native Tab and bullet-caret editor checkpoint.

Source checkpoint only; combined compilation and native verification remain pending.

## [1.4.20-beta.1] - 2026-10-31

### Fixed

- Calibrate Settings traffic-light spacing against measured native sidebar search and header geometry.
- Use the native Backtab character in the existing Models reverse-focus regression test.
- Preserve folder-row focus through the reorder wrapper and associate the School fixture with its
  explicit accessibility owner instead of an assumed row width.

Source checkpoint only; compilation and native verification remain pending.

## [1.4.19-beta.1] - 2026-10-31

### Fixed

- Ignore retained overflow-rail actions during folder creation so the scrolled folder
  geometry stays in place, with both rail directions covered by the existing regression.
- Inherit the Dictionary priority-star capture fixture's explicit logical bitmap size
  without changing production appearance or assertion thresholds.

Source checkpoint only; this combined source's CI, native interaction and visual validation
remain pending.

## [1.4.18-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed activity-scrollbar containment and held-entry correction while
  preserving capped, fading note-tab titles and their full accessible labels.

Source-only dependency integration; this checkpoint's CI and native validation remain pending.

## [1.4.17-beta.1] - 2026-10-31

### Fixed

- Integrate the reviewed activity-scrollbar containment and held-entry correction while
  preserving theme-matched banners and their existing inline opt-out behavior.

Source-only dependency integration; this checkpoint's CI and native validation remain pending.

## [1.4.16-beta.1] - 2026-10-31

### Fixed

- Constrain idle and released activity-scrollbar paint to the usable native knob and track
  interval without changing its dimensions or weakening containment checks.
- Preserve the corrected full knob rectangle when entering native tracking and retain its
  proportional movement while the held length stays frozen.

Source propagation of the reviewed correction; this checkpoint's CI and native validation
remain pending. Supporting paired CI passes on the existing dependency are not a complete-app pass.

## [1.4.15-beta.1] - 2026-10-29

### Fixed

- Cap note-tab title labels with a semantic trailing fade while preserving full accessible titles.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

## [1.4.14-beta.1] - 2026-10-29

### Fixed

- Port theme-matched agent-update and capture-failure banner surfaces, plus an inline opt-out
  wired to the existing agent-banner preference.

Source-only public review checkpoint, not accepted/development-source advancement. Compilation,
tests, visual/accessibility inspection and native behavior remain unverified.

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

## [1.4.11-beta.1] - 2026-10-29

### Fixed

- Adopt bounded actual native resize frames while preserving anchor, top, containment and
  legal-preference checks.
- Protect resize rollback and completion from newer interactions while preserving deferred
  size publication during reentry.
- Reject backing alignment or native adoption that changes an untouched resize axis.

Source-only checkpoint; compilation, tests and native resize validation remain unrun.

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
