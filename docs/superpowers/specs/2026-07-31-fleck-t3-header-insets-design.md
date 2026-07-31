# Fleck T3 Header Insets Design

## Goal

Refine the existing Fleck hero header so its placement follows the compact T3 Code layout while preserving Fleck's logo, typography, light background, and one-page scope.

## Approved Direction

- Use T3 Code's desktop header geometry: a 12px top offset and 52px left/right content inset at a 1280px viewport.
- Express the horizontal placement as a centered header rail so the controls stay intentionally inset on wider displays instead of drifting to the browser edges.
- Keep the header visually invisible: no bar background, divider, blur, shadow, or contrasting container.
- Preserve the current small Fleck logo lockup and compact header button dimensions.
- Use the light-violet accent from the Fleck mark for both “Download for Mac” buttons. The fill should visually match the logo's violet tile, with accessible white text and a slightly darker violet hover state.
- Keep the GitHub action unchanged.

## Responsive Behavior

- Desktop/tablet: 12px top offset with the T3-style centered rail and 52px side inset at 1280px.
- Mobile: retain a safe 20px side inset and compact top spacing so neither control touches the viewport edge.
- The logo and download button remain on one row without adding navigation items.

## Interaction

- Both Mac download buttons retain their current destinations and focus behavior.
- Hover and pressed states change only the violet treatment; no new motion or cursor-following effects are introduced.

## Verification

- Compare the desktop header at 1280px against the measured T3 placement.
- Verify the hero at desktop and 390px mobile widths.
- Confirm both Mac download links remain usable, tests pass, and the production build succeeds.
