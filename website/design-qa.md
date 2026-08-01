# Fleck hero brain design QA

- Source visual truth: `../docs/design/references/fleck-website-approved-direction-2026-08-01.png`
- Implementation screenshot: `design-qa-hero-desktop.png`
- Mobile screenshot: `design-qa-hero-mobile.png`
- Combined comparison: `design-qa-hero-comparison.png`
- Source pixels: 724 × 2172; hero comparison crop: 724 × 430, normalized to 1440 × 855.
- Desktop implementation: 1440 × 1000 px at a 1440 × 1000 CSS viewport and 1× capture density.
- Mobile implementation: 390 × 844 px at a 390 × 844 CSS viewport and 1× capture density.
- State: initial hero, light theme, idle and pointer-hover interaction checked.

## Findings

No actionable P0, P1, or P2 differences remain within this iteration's approved
scope: the brain hologram only.

- Fonts and typography: Existing Outfit hierarchy and copy remain unchanged.
  The brain's quiet center preserves headline and body contrast at both tested
  breakpoints.
- Spacing and layout rhythm: The brain fills the desktop hero at approximately
  the same visual scale as the source and remains centered without horizontal
  overflow at 390 px.
- Colors and visual tokens: The hero uses only graphite and pale-violet canvas
  geometry; no generated brain image is rendered behind it.
- Network rendering: A deterministic canvas adds 560 desktop nodes and more
  than two connections per node across two separated hemispheres.
- Copy and content: No hero copy changed in this pass.
- Responsive behavior: Desktop and mobile captures have no horizontal overflow.
- Interaction: Moving the pointer across the brain gently displaces nearby nodes
  and their connected edges. No cursor-bound ring, radar arc, or signal graphic
  is rendered.
- Accessibility and motion: The complete hologram is decorative and hidden from
  assistive technology. Breathing, drift, and pointer displacement are disabled
  by `prefers-reduced-motion`; touch input does not activate pointer displacement.
- Console: No errors or warnings were reported.

## Comparison history

1. Interaction revision: restored the earlier responsive dot-and-line behavior
   as a separate canvas, constrained its nodes to two brain-shaped hemispheres,
   and increased edge density without restoring the cursor signal.
2. The generated anatomical background image was removed at the user's request,
   leaving the original interactive canvas as the complete hero visual.
3. Post-fix evidence: `design-qa-hero-desktop.png`,
   `design-qa-hero-mobile.png`, and `design-qa-hero-comparison.png` show the
   canvas-only treatment and readable copy.

## Focused comparison

The entire current page is the hero, so the viewport capture is also the focused
region. No additional component crop was needed.

## Follow-up polish

- P3: Node and edge opacity can be tuned after live user feedback.

## Final result

final result: passed
