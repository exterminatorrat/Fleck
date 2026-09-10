# Fleck Settings visual QA

> Historical QA record from 2026-09-02. It is preserved for rationale and
> point-in-time evidence only; it is not a current product or release claim.
> See [`docs/archive/README.md`](docs/archive/README.md).

## Scope and result

This is the final source-vs-implementation comparison for the native macOS Settings window at clean local product head `98242c5b698eb3a13fa726aa4348c69a32bec0f3`. The exact rebuilt bundle was inspected with Computer Use across all six destinations, the Vocabulary empty/search/Add New states, the scrolled Agents guidance, and a cross-destination scroll reset. Forced hosted Light and Dark renders also cover Reduce Transparency. The final pass has no actionable P0, P1, or P2 findings.

## Source visual truth

- **User-provided Stats ideal** (historical external artifact, not included) —
  rounded inset sidebar, traffic lights contained inside the sidebar, and page
  title aligned in the compact top band.
- **Installed Stats settings dashboard** (historical external artifact, not
  included) — 728 x 480 px.
- **Installed Wispr Flow dictionary** (historical external artifact, not
  included) — 1220 x 768 px.
- **Fleck menu-bar glass reference** (historical external artifact, not
  included) — the existing neutral black-tinted material language reused by
  Settings.

## Final implementation evidence

The final implementation was inspected from the isolated Settings redesign
worktree build in Dark appearance at the default 840 x 600 Settings size. The
final executable SHA-256 was
`86f3df2a0f64e0b5c91515037157fcfb17c458230a938a78ab8ae1785dae6fc8`;
PID `63139` ran that exact bundle for the final normal-appearance smoke. The
full destination capture set immediately precedes the accessibility-only
product change, whose normal-appearance branches are unchanged.

- **Final exact-bundle Appearance smoke** — post-accessibility-fix normal
  appearance from PID `63139`.
- **Appearance** — final transparent-titlebar and glass-chrome state.
- **General**, **Shortcuts**, **Dictation**, **Vocabulary**, **Vocabulary
  search**, **Vocabulary Add New sheet**, **Agents**, **Agents setup
  guidance**, and **General after leaving scrolled Agents** — historical
  destination captures, not included in the repository.
- **Reduce Transparency — Dark** and **Reduce Transparency — Light** —
  historical forced hosted opaque-hierarchy captures, not included.

## Comparison method and normalization

The reference and implementation were placed in the same comparison images and inspected together:

- **User ideal / Appearance**, **Installed Stats / Appearance**, and **Wispr
  Flow / Vocabulary** — historical external comparison images, not included;
  each pair was normalized to 600 px high.

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
| Reduce Transparency | Forced hosted Light and Dark renders verify opaque root, sidebar, card, and dictionary hierarchy. A rendered-pixel test requires non-flat adaptive color distance, and the rounded surfaces retain subtle boundaries without blur. |
| AI-shortcut artifacts | The final composition avoids generic card soup, decorative blobs, faux gradients, oversized hero copy, emoji, and inconsistent one-off controls. |

## Findings and comparison history

No actionable P0, P1, or P2 findings remain.

1. Resolved P2 — the sidebar's opaque List layer flattened its rounded material. The List background is now transparent inside one continuous rounded surface.
2. Resolved P2 — Vocabulary repeated two near-identical teaching sentences. The destination description is now concise while the teaching headline remains the task entry point.
3. Resolved P2 — shared detail scrolling could retain a previous destination's offset. Destination identity now recreates only the detail scroll subtree; hosted and live transition evidence confirm reset.
4. Resolved P2 — cards and the dictionary surface read as solid purple slabs. They now reuse Fleck's neutral black-tinted regular-glass contract with adaptive fallback.
5. Rejected checkpoint — `74764b2` contained the traffic lights but pushed the sidebar 41 px below the window top. The final capsule begins 8 px from the real window edge and the redundant native title is hidden.
6. Rejected checkpoint — `8202bf2` left a horizontal titlebar seam across the detail. The final window uses a hidden, separator-free, transparent titlebar, and the exact recapture shows no stray line.
7. Fresh-review P2 — Reduce Transparency initially resolved root, sidebar, and cards to the same rendered RGB value. The final adaptive opaque overlays and strokes produce distinct hierarchy in both Light and Dark hosted renders.
8. Fresh-review evidence limit — traffic-light frames were previously reused across destination checks. A same-window 840 x 600 → 760 x 520 → 840 x 600 test now re-queries every traffic light and layout surface after each relayout.

## Verification

- Hosted Reduce Transparency render: 1/1 passed in Light and Dark after red showed four flattened comparisons at color distance `0.0`.
- Hosted same-window resize: 1/1 passed with fresh frames at 840 x 600, 760 x 520, and 840 x 600.
- `DictationSettings`: 89/89 passed.
- `PersonalDictionarySettings`: 25/25 passed.
- Earlier unchanged focused suites at this visual lineage: Shortcut Recorder 18/18, Fleck Color Picker 12/12, Note Deletion Confirmation 5/5, Agent Presentation 19/19.
- `./Scripts/build-fleck-app.sh`: passed.
- Deep/strict codesign and designated requirement: passed.
- `git diff --check`: passed.

## Open evidence limit

Computer Use corner drag did not produce a reliable live 760 x 520 capture, so minimum-size proof remains hosted AppKit geometry rather than a live screenshot. This is an evidence limit, not a visible defect in the inspected default-size build.

final result: passed
