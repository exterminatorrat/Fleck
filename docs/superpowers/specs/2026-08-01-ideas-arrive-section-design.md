# Ideas arrive section

Status: approved direction, awaiting written-spec review.

## Goal

Add the first section below Fleck's hero. It explains why fleeting ideas are
hard to turn into useful work, then ends with a compact reveal showing that
Fleck preserves the thought intact.

This section is the problem narrative only. It must not build the larger
capture-to-finish product demonstration or any later homepage section.

## Copy

Heading:

> Ideas arrive before your tools are ready.

Body:

> Ideas flash by quickly. Even when you catch one, turning it into something
> useful usually means describing it again, cleaning it up, copying it somewhere
> else, and re-explaining the context to an AI agent.

## Storyboard

The visual is a four-row editorial timeline connected by a thin violet path.

1. **A spark of an idea.** A violet ignition point introduces a waveform and a
   raw thought. Its far edge becomes faint to show the idea beginning to vanish.
2. **You try to capture it.** The same thought appears as a hurried, incomplete
   transcript with a small elapsed-time marker.
3. **Copy, paste, repeat.** Restrained labels show the manual path through Notes,
   ChatGPT, and Codex. The chain fragments before the caption “context is lost.”
4. **Fleck catches it and keeps it whole.** The thought resolves into a crop from
   the actual Fleck macOS application, sharp and intact.

The first three rows are an editorial diagram, not product UI. They may use text,
waveforms, paths, timestamps, and restrained tool labels, but they must not mimic
an invented Fleck interface.

## Real Fleck requirement

Any visible Fleck interface must be captured from the real application runtime.
Do not recreate, trace, or approximate Fleck with HTML or an image-generation
model.

Use a dedicated testing tab to the right of the protected leftmost personal tab.
The capture may contain only deliberate demo content. Do not expose personal
notes, credentials, or unrelated tabs.

If the real application cannot be opened or captured, stop at that boundary and
report the blocker. Do not substitute fake UI. A successful build or source-code
inspection is not evidence that the product capture is genuine.

## Layout

The section follows the hero on the same warm-white canvas. Its desktop content
uses the hero's compact page insets and a maximum width of 1180 px.

- The heading and body sit in a left editorial column near the top of the
  section.
- The timeline occupies the wider area below and to the right, giving each row
  enough horizontal space for the thought to travel.
- Fine neutral dividers separate rows. Violet marks only the thought path,
  ignition nodes, selected labels, and final resolution.
- The section receives generous vertical space so it feels like a new chapter,
  not another card attached to the hero.

At widths of 760 px and below, the section becomes a single column. Row labels
move above their visuals, the copy/paste chain wraps or becomes vertical, and no
horizontal scrolling is introduced.

## Motion

The section uses one restrained, scroll-triggered sequence:

1. The heading and body fade upward by no more than 18 px.
2. The violet path draws through the rows.
3. Each row resolves in order as the path reaches it.
4. The first waveform fades at its tail, the manual chain fragments, and the
   real Fleck crop finishes at full opacity with one soft node pulse.

The sequence plays once per page view. It does not scrub continuously with the
scroll position and does not trap scrolling. Use the native Intersection
Observer rather than adding an animation dependency.

With `prefers-reduced-motion: reduce`, the complete composition is visible
immediately with no transforms, path drawing, fading thought, or pulse.

## Components and data flow

- `App.jsx` places one `IdeasSection` immediately after the hero.
- `IdeasSection.jsx` owns the semantic heading, body, four-row timeline, and
  visibility state used to start the sequence.
- `styles.css` owns the layout, diagram styling, responsive rules, and motion.
- One asset under `website/public/assets/` contains the sanitized crop captured
  from the real Fleck app.

All narrative content is local and static. The section performs no network
request, analytics call, agent action, or app integration at runtime.

## Accessibility and failure handling

- The section heading participates in the page's normal heading hierarchy.
- The timeline uses an ordered list so its sequence remains understandable
  without the diagram.
- Decorative waveforms, connectors, and nodes are hidden from assistive
  technology.
- The Fleck crop uses concise alternative text describing only the product state
  that is not already conveyed by adjacent text.
- JavaScript-disabled or Intersection-Observer-unavailable rendering shows the
  completed section instead of hiding content.
- The page restores normal vertical scrolling while retaining horizontal
  overflow protection.

## Verification

- Confirm the Fleck crop came from a live application session using the testing
  tab and contains no personal content.
- Capture desktop at 1440 × 1000 and mobile at 390 × 844, including the boundary
  between the hero and the new section.
- Confirm the timeline order, real UI asset, and final Fleck reveal are visible.
- Confirm the page scrolls vertically, has no horizontal overflow, and the
  navigation and hero remain unchanged.
- Confirm the animation plays once, does not trap scrolling, and becomes fully
  static under reduced motion.
- Confirm no console errors or warnings.
- Run the focused tests, `npm test`, `npm run build`, and `git diff --check`.
