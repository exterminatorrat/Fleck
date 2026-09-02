# Fleck Settings visual QA

## Scope and result

This is the final source-vs-implementation comparison for the native macOS Settings window. The review covers all six destinations, the Vocabulary empty state, and the Vocabulary Add New sheet in the exact rebuilt local bundle. The final pass has no actionable P0, P1, or P2 findings.

## Source visual truth

- [Stats settings dashboard](/Users/harryjin/.codex/visualizations/2026/09/01/fleck-settings-reference-audit/01-stats-settings-dashboard.png) — 728 x 480 px.
- [Wispr dictionary](/Users/harryjin/.codex/visualizations/2026/09/01/fleck-settings-reference-audit/03-wispr-dictionary.png) — 1220 x 768 px.

## Final implementation evidence

The final implementation was inspected from the exact rebuilt local bundle in Dark appearance, using the default 840 x 600 Settings window. The captured states were an empty Vocabulary page, the Add New sheet, an installed connector, and one connected Codex profile.

- [Appearance](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-01-appearance.png) — 840 x 600 px.
- [General](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-02-general.png) — 840 x 600 px.
- [Shortcuts](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-03-shortcuts.png) — 840 x 600 px.
- [Dictation](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-04-dictation.png) — 840 x 600 px.
- [Vocabulary](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-05-vocabulary.png) — 840 x 600 px.
- [Vocabulary Add New sheet](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-06-vocabulary-add-new.png) — 420 x 280 px.
- [Agents](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-page-07-agents.png) — 840 x 600 px.

Post-fix transition evidence:

- [Dictation scrolled](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-transition-01-dictation-scrolled.png) — Dictation deliberately scrolled to its bottom, 840 x 600 px.
- [General reset](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-transition-02-general-reset.png) — General immediately after navigation with its header restored to the same compact safe top band, 840 x 600 px.

## Comparison method and normalization

The combined comparison inputs that were opened and inspected were:

- [Stats / Appearance comparison](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-compare-stats-appearance.png) — 1766 x 600 px. The 728 x 480 source was normalized to 600 px high; the 840 x 600 implementation was retained at its capture size.
- [Wispr / Vocabulary comparison](/Users/harryjin/.codex/visualizations/2026/09/02/fleck-settings-final-visual/final-compare-wispr-vocabulary.png) — 2312 x 768 px. The 1220 x 768 source was retained at its capture size; the implementation was normalized to 768 px high.

These are native AppKit/SwiftUI screenshots, so CSS viewport size and browser `deviceScaleFactor` are not applicable. The page capture pixel sizes are 840 x 600, the sheet is 420 x 280, and the only comparison normalization was the explicit height normalization above; no browser-density or device-frame conversion was applied.

## Full-view comparison evidence

The final Settings shell has a fixed rounded inset sidebar with traffic lights comfortably inset in the native chrome, no collapse control, compact page headers, and a coherent adaptive system-material/window background. Appearance, General, Shortcuts, Dictation, Vocabulary, and Agents remain structured and unclipped at the default window size. The visible task controls are legible, and the selected navigation state is clear.

## Focused-region comparison evidence

The combined Stats / Appearance comparison makes the sidebar/chrome relationship and detail-card treatment readable at the same time, so no additional crop was needed. The combined Wispr / Vocabulary comparison makes the teaching title, Add New action, search/sort/reload controls, list surface, and empty state readable at the same time, so no additional crop was needed.

## Fidelity review

| Surface | Assessment |
| --- | --- |
| Typography | Native San Francisco/system typography provides a clear page-title, section-label, row-label, and supporting-copy hierarchy. Text remains legible and appropriately weighted in the inspected dark states; no P0-P2 typography issue remains. |
| Spacing and layout rhythm | The rounded sidebar, traffic-light inset, compact page-header band, grouped detail surfaces, and destination-specific spacing preserve the intended calm density. All six default-size pages are contained and unclipped. |
| Colors and tokens | Dark appearance uses the system/adaptive palette, selected-row accent, restrained grouped surfaces, and coherent system-material/window background. The result preserves contrast and state distinction without decorative gradients or faux glass. |
| Image and asset fidelity | No decorative or fake image assets are used. The implementation uses native San Francisco/system symbols and materials, with no emoji or custom SVG approximations. |
| Copy and content | The Vocabulary task headline is retained as `Teach Fleck the words and phrases that matter to you`; its destination description is concise and non-duplicative: `Manage personal vocabulary and dictation corrections.` The inspected page copy is coherent and does not imply unsupported team/cloud behavior. |
| Icons | System symbols and standard macOS controls are visually consistent with the native Settings shell. The traffic lights and standard navigation affordances remain visible and comfortably inset. |
| States and interactions | The inspected states include selected navigation, the empty Vocabulary page, Add New sheet, installed connector, and connected Codex profile. Add New, search/sort/reload, connector/profile actions, and recovery/task controls are legible in their intended destinations. |
| Accessibility | Accessibility labels are present in the exact Computer Use tree for the inspected controls and destinations. Native semantic controls and system symbols remain the basis of the interaction surface; this visual pass does not claim a substitute for exhaustive assistive-technology testing. |
| Viewport resilience | The default 840 x 600 window remains stable across all six destinations, including the live scroll-to-navigation reset. The minimum 760 x 520 boundary is covered by the hosted AppKit geometry test; a live resize screenshot was not obtained (see residual evidence limitation). |
| AI-shortcut artifacts | The final composition avoids generic card soup, decorative blobs, fake imagery, emoji, and handcrafted SVG substitutes. Grouped surfaces are restrained and serve information hierarchy rather than acting as decoration. |

## Findings

No actionable P0, P1, or P2 findings remain in the final pass. The remaining viewport evidence limitation is recorded below and is not a visual defect.

## Comparison history

1. Earlier P2 — `compare-stats-appearance.png` showed an opaque rectangular List layer flattening the rounded sidebar material. The fix was `.scrollContentBackground(.hidden)` plus `.background(Color.clear)`. Post-fix evidence in `after-compare-stats-appearance.png` shows one continuous rounded surface.
2. Earlier P2 — `compare-wispr-vocabulary.png` repeated two near-identical teaching sentences. The destination description was changed to `Manage personal vocabulary and dictation corrections.` while retaining `Teach Fleck the words and phrases that matter to you` as the task headline. Post-fix evidence is in `after-compare-wispr-vocabulary.png`.
3. Earlier P2 / fresh-review concern — one shared `HostingScrollView` could retain a tall page’s offset after navigation. The detail `ScrollView` now has destination identity via `.id(selectedSection)`, and a hosted transition test scrolls Dictation before switching through all six destinations, requiring a fresh scroll view and a header within the accepted top band. Post-fix visual evidence is `final-transition-01-dictation-scrolled.png` and `final-transition-02-general-reset.png`; the test passed 1/1.

## Open questions and evidence limits

Computer Use corner drag did not change the Settings window from 840 x 600, so a live 760 x 520 resize screenshot remains unavailable and that minimum boundary is covered by the hosted AppKit geometry test. Live Computer Use does verify the scroll-to-navigation reset at 840 x 600. This is an evidence limitation, not an actionable visual finding.

## Implementation checklist

- [x] Compare the Stats sidebar/chrome treatment with the final Appearance implementation.
- [x] Compare the Wispr dictionary task structure with the final Vocabulary implementation.
- [x] Inspect all six Settings destinations and the Add New sheet in the final bundle.
- [x] Evaluate typography, spacing/layout rhythm, colors/tokens, image/asset fidelity, copy/content, icons, states/interactions, accessibility, viewport resilience, and AI-shortcut artifacts.
- [x] Record earlier P2 findings, the scroll-reset fix, and post-fix evidence.

## Follow-up polish

No P3 follow-up is required for this handoff. The only remaining limitation is the live minimum-size capture noted above.

final result: passed
