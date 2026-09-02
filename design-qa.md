# Fleck Settings visual QA

## Scope and result

This is the final source-vs-implementation comparison for the native macOS Settings window at clean local head `d1e067003afbe4ffb74640662d14f1c340f8dffd`. The exact rebuilt bundle was inspected with Computer Use across all six destinations, the Vocabulary empty/search/Add New states, the scrolled Agents guidance, and a cross-destination scroll reset. The final pass has no actionable P0, P1, or P2 findings.

## Source visual truth

- [User-provided Stats ideal](/Users/harryjin/.codex/attachments/9aacd791-e89e-43f7-9ca2-c89bc5a872a7/Screenshot%202026-09-01%20at%2013.43.18.png) — rounded inset sidebar, traffic lights contained inside the sidebar, and page title aligned in the compact top band.
- [Installed Stats settings dashboard](/Users/harryjin/.codex/visualizations/2026/09/01/fleck-settings-reference-audit/01-stats-settings-dashboard.png) — 728 x 480 px.
- [Installed Wispr Flow dictionary](/Users/harryjin/.codex/visualizations/2026/09/01/fleck-settings-reference-audit/03-wispr-dictionary.png) — 1220 x 768 px.
- [Fleck menu-bar glass reference](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/reference-fleck-menubar-glass.png) — the existing neutral black-tinted material language reused by Settings.

## Final implementation evidence

The final implementation was inspected from `/Users/harryjin/Fleck/.worktrees/settings-sidebar-redesign/.build/Fleck.app` in Dark appearance at the default 840 x 600 Settings size. The executable SHA-256 was `6906ba9210e03771ebdd5df609879bf2866d7a60458d10d5f331efe4ead7874f`; PID `57182` was running that exact bundle during the final capture pass.

- [Appearance](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-02-appearance-transparent.png) — final transparent-titlebar and glass-chrome state.
- [General](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-03-general.png).
- [Shortcuts](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-04-shortcuts.png).
- [Dictation](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-05-dictation.png).
- [Vocabulary](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-06-vocabulary.png).
- [Vocabulary search](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-07-vocabulary-search.png).
- [Vocabulary Add New sheet](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-08-vocabulary-add.png).
- [Agents](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-09-agents.png).
- [Agents setup guidance](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-10-agents-scrolled.png).
- [General after leaving scrolled Agents](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-11-general-reset.png).

## Comparison method and normalization

The reference and implementation were placed in the same comparison images and inspected together:

- [User ideal / Appearance](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-compare-user-ideal-appearance.png) — both normalized to 600 px high.
- [Installed Stats / Appearance](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-compare-stats-appearance.png) — both normalized to 600 px high.
- [Wispr Flow / Vocabulary](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/accepted-compare-wispr-vocabulary.png) — both normalized to 600 px high.

These are native AppKit/SwiftUI screenshots, so browser viewport and `deviceScaleFactor` values do not apply. No device frame or CSS-density conversion was used.

## Full-view comparison evidence

The final shell reproduces the reference relationship: an 8-point inset, 22-point continuous-radius glass sidebar; traffic lights approximately 14 points inside its top-left corner; no collapse control; no redundant native window title; and no titlebar separator or material seam across the detail. The detail header remains compact and stable across all destinations. The root, sidebar, cards, and dictionary panel use Fleck's neutral black-tinted glass/material contract instead of solid purple surfaces.

The Vocabulary destination follows the Wispr Flow task structure without implying unsupported team/cloud behavior: teaching headline and Add New action first, filter/search/sort/reload controls next, one large dictionary surface, a clear empty state when the local dictionary is empty, and a compact editor sheet for words or corrections.

## Fidelity review

| Surface | Assessment |
| --- | --- |
| Typography | Native system typography provides a clear page-title, section-label, row-label, and supporting-copy hierarchy. No clipped or competing title remains. |
| Spacing and layout rhythm | Sidebar and content start in the same compact top band as the supplied Stats ideal. The sidebar is visibly inset on all four edges; all default-size destinations are unclipped or intentionally scrollable. |
| Colors and tokens | Neutral adaptive glass/material surfaces reuse Fleck's menu-bar treatment. Accent is reserved for selection, primary action, and semantic controls rather than painted across backgrounds. |
| Copy and content | Vocabulary retains `Teach Fleck the words and phrases that matter to you`, concise destination copy, clear empty-state guidance, and no unsupported sharing claim. Agent setup is presented as three short local steps. |
| Icons | Native SF Symbols and standard macOS controls remain consistent. No emoji, custom SVG approximation, or fake asset is used. |
| States and interactions | Selected navigation, Vocabulary empty/search/Add New, installed connector, connected profile, lower Agent instructions, and scroll reset were all inspected in the exact bundle. |
| Accessibility | Computer Use exposed labels, hints, values, and semantic roles for destinations and the visible controls. Native controls remain the interaction basis. |
| Viewport resilience | Default 840 x 600 visual states are stable. Hosted AppKit coverage verifies 840 x 600 and 760 x 520 geometry, all six destinations, sidebar/traffic-light containment, hidden/transparent titlebar, absent separator, and scroll reset. |
| AI-shortcut artifacts | The final composition avoids generic card soup, decorative blobs, faux gradients, oversized hero copy, emoji, and inconsistent one-off controls. |

## Findings and comparison history

No actionable P0, P1, or P2 findings remain.

1. Resolved P2 — the sidebar's opaque List layer flattened its rounded material. The List background is now transparent inside one continuous rounded surface.
2. Resolved P2 — Vocabulary repeated two near-identical teaching sentences. The destination description is now concise while the teaching headline remains the task entry point.
3. Resolved P2 — shared detail scrolling could retain a previous destination's offset. Destination identity now recreates only the detail scroll subtree; hosted and live transition evidence confirm reset.
4. Resolved P2 — cards and the dictionary surface read as solid purple slabs. They now reuse Fleck's neutral black-tinted regular-glass contract with adaptive fallback.
5. Rejected checkpoint — `74764b2` contained the traffic lights but pushed the sidebar 41 px below the window top. The final capsule begins 8 px from the real window edge and the redundant native title is hidden.
6. Rejected checkpoint — `8202bf2` left a horizontal titlebar seam across the detail. The final window uses a hidden, separator-free, transparent titlebar, and the exact recapture shows no stray line.

## Verification

- Hosted chrome test: 1/1 passed after red-first coverage for inset, traffic-light containment, title visibility, separator, and transparency.
- `DictationSettings`: 87/87 passed.
- `PersonalDictionarySettings`: 25/25 passed.
- Earlier unchanged focused suites at this visual lineage: Shortcut Recorder 18/18, Fleck Color Picker 12/12, Note Deletion Confirmation 5/5, Agent Presentation 19/19.
- `./Scripts/build-fleck-app.sh`: passed.
- Deep/strict codesign and designated requirement: passed.
- `git diff --check`: passed.

## Open evidence limit

Computer Use corner drag did not produce a reliable live 760 x 520 capture, so minimum-size proof remains hosted AppKit geometry rather than a live screenshot. This is an evidence limit, not a visible defect in the inspected default-size build.

final result: passed
