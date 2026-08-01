# Capture Through Finish Section

Status: approved through the locked full-page reference.

## Goal

Add the next homepage chapter after the idea-loss narrative. It shows that one
captured thought stays intact through cleanup, deliberate agent access, and
finished work.

Build only this chapter. Do not add the later lightweight-features, dark agent
workspace, or final call-to-action sections.

## Copy

Heading:

> Catch it once. Carry it all the way through.

Ordered stages:

1. **Capture** — Thought enters Fleck from the menu bar.
2. **Clean up** — Fleck turns rough speech into a clean, structured note.
3. **Collaborate** — Invite agents to this note only.
4. **Finish** — Agents complete tasks and leave a clear trail.

## Visual direction

Use the approved full-page reference as the composition guide: a narrow
editorial stage rail on the left and one large Fleck product surface on the
right. Keep the warm-white canvas, graphite type, fine neutral dividers, and
violet as the only accent.

The product surface must use the existing sanitized capture from the real
Fleck macOS app. It may be surrounded by editorial labels that explain the
workflow, but those labels must not imitate app controls, agent cards, windows,
or dashboards. Do not invent Fleck UI to match the generated reference.

The real capture is dark, so present it as the visual anchor inside a restrained
light product plate. A small source label identifies it as a live Fleck capture.
Below it, three plain editorial facts summarize cleanup, note-by-note access,
and visible activity. They remain visibly outside the app image.

## Layout

- Maximum desktop width: 1180 px using the existing 52 px page insets.
- Desktop: 330 px narrative column and a flexible product column.
- The four stages form a genuine ordered sequence with a continuous violet
  rail and numbered labels.
- The product plate is large enough to make the genuine toolbar, title, and
  thought readable without stretching the capture beyond 650 px.
- At 760 px and below, the section becomes one column. The stage rail remains
  vertical and the product plate fills the available width without horizontal
  overflow.

## Motion

Use one Intersection Observer sequence. The heading appears first, stages
resolve in order, then the real product capture settles into place. Motion
plays once, does not scrub or trap scrolling, and uses only opacity and a
maximum 18 px translation. Reduced-motion users see the complete section
immediately.

## Components

- `journeyContent.js` owns the ordered stage contract and real capture path.
- `JourneySection.jsx` owns semantic markup and the one-shot reveal.
- `App.jsx` places the section directly after `IdeasSection`.
- `styles.css` owns layout, responsive behavior, and motion.
- Reuse `public/assets/fleck-ideas-capture.png`; do not create a duplicate.

## Accessibility and verification

- Use an `h2` and an ordered list.
- Decorative rail elements are hidden from assistive technology.
- The product capture has concise alternative text.
- With JavaScript unavailable, content remains visible.
- Verify desktop and 390 px mobile layouts, no horizontal overflow, the real
  image at its natural aspect ratio, one-shot motion, reduced motion, no browser
  console errors, focused tests, production build, and `git diff --check`.
