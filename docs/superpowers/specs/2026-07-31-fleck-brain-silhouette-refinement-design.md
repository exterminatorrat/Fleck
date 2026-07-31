# Fleck Brain Silhouette Refinement

## Goal

Make the existing hero thought field read slightly more clearly as a top-down brain without making it literal, heavier, or more anatomically detailed.

## Visual change

- Preserve the current white canvas, graphite nodes, fine connective lines, violet accents, density, scale, and central content.
- Reshape the particle envelope into two softly rounded hemispheres.
- Make the central fissure a little clearer, especially through the upper and middle silhouette.
- Add gentle frontal, parietal, and lower temporal fullness through subtle contour variation.
- Keep the silhouette airy and abstract; do not add labeled anatomy, a side profile, a cerebellum, a hard outline, or additional visual weight.

## Interaction change

- Remove the three curved violet rings drawn around the cursor.
- Retain the subtle local displacement of nearby nodes so the thought field still feels responsive.
- Preserve touch behavior and `prefers-reduced-motion` handling.

## Responsive behavior

- Desktop should retain the broad two-hemisphere composition around the hero copy.
- Mobile should preserve a recognizable bilateral silhouette without crowding or obscuring the text and actions.
- No copy, header, CTA, spacing, or color changes are included in this refinement.

## Verification

- Extend the deterministic brain-model test to check balanced hemispheres and a visible center fissure.
- Compare desktop and mobile browser captures against the accepted Fleck concept and current implementation.
- Confirm pointer movement still shifts nearby nodes but produces no cursor rings.
- Re-run tests, the production build, and the deployed Sites smoke check.
