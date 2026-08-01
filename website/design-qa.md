# Fleck hero brain design QA

- Source visual truth: `../docs/design/references/fleck-website-approved-direction-2026-08-01.png`
- Implementation screenshot: `design-qa-hero-desktop.png`
- Mobile screenshot: `design-qa-hero-mobile.png`
- Combined comparison: `design-qa-hero-comparison.png`
- Desktop implementation: 1440 × 1000 px at a 1440 × 1000 CSS viewport and 1× capture density.
- Mobile implementation: 390 × 844 px at a 390 × 844 CSS viewport and 1× capture density.
- State: initial hero, light theme, idle and pointer-hover interaction checked.

## Findings

No actionable P0, P1, or P2 differences remain within this iteration's approved
scope: the brain hologram only.

- Network-only silhouette: The hero contains a single canvas and no rendered
  raster image. Its contour-biased nodes form bilateral outer lobes and a clear
  center fissure, while the center copy area remains quiet.
- Copy and layout: Existing hero copy, typography, spacing, and CTA placement
  remain unchanged. The headline stays readable at both tested breakpoints.
- Responsive behavior: Desktop and mobile captures have no horizontal overflow;
  `document.documentElement.scrollWidth` equals 390 at the 390 px viewport.
- Interaction: Pointer movement gently displaces only nearby network geometry
  and its connected edges. No cursor-bound ring, radar arc, or pointer signal is
  rendered. Touch input does not activate pointer displacement.
- Accessibility and motion: The hologram is decorative and hidden from
  assistive technology. Breathing, drift, and pointer displacement are disabled
  by `prefers-reduced-motion`.
- Console: The desktop and mobile checks reported no errors or warnings.

## Evidence

1. `design-qa-hero-desktop.png` shows the 1440 × 1000 network-only hero.
2. `design-qa-hero-mobile.png` shows the 390 × 844 responsive hero.
3. `design-qa-hero-comparison.png` places the verified desktop and mobile
   captures side by side.

## Final result

final result: passed
