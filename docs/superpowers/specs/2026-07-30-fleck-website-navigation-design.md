# Fleck Website Navigation Design

Date: 2026-07-30

Status: Approved direction, pending written-spec review

## Purpose

The Fleck landing page needs a top navigation bar that feels calm, tactile, and
editorial while supporting the more expressive motion planned for the rest of
the page. It should make Fleck's three defining ideas immediately discoverable:
fast note capture, local AI assistance, and explicitly shared access for coding
agents.

The approved direction adapts the compact floating navigation structure in the
referenced Craft website section to Fleck's existing "Field Notes" visual
direction. It does not copy Craft's brand styling, content breadth, or product
menus.

Reference:

- Mobbin section:
  `https://mobbin.com/sites/sections/dc8ed7f5-06ca-44f1-a6ef-387eacd5da09`
- Current Craft header structure: logo on the left, primary navigation in the
  center, and account/conversion actions on the right.

## Goals

- Keep the product identity and primary waitlist action visible at all times.
- Give Agent Access first-class visibility without making Fleck appear to be
  only an agent tool.
- Remain visually quiet while the hero introduces more expressive motion.
- Feel related to a physical field notebook rather than a generic SaaS pill.
- Scale cleanly from desktop to mobile and support keyboard, pointer, touch,
  VoiceOver, and reduced-motion users.

## Non-goals

- No login or account action is included before Fleck has a public account
  experience.
- No multi-level product mega-menu is needed for the initial landing page.
- The navigation does not become an audio recorder or display decorative
  waveforms.
- The first implementation does not create separate destination pages; links
  scroll to sections on the existing landing page.

## Information Architecture

Desktop order:

1. Fleck logo and wordmark
2. Product
3. How it works
4. Agent access
5. Principles
6. Join the waitlist

Section destinations:

- `Product` → the main product demonstration and feature overview.
- `How it works` → the capture, clean, and use transformation sequence.
- `Agent access` → explicit note sharing, local MCP/CLI access, revision-safe
  agent edits, attribution, and Undo.
- `Principles` → local-first behavior, explicit sharing, calm operation, and
  user ownership.
- `Join the waitlist` → the waitlist form near the end of the page. If the hero
  already exposes an email field, the navigation action may focus that field.

The logo returns to the top of the page.

## Desktop Composition

The navigation is a fixed, centered "floating field bar."

- Top offset: 32 px on wide desktop and 24 px on smaller desktop.
- Maximum width: 1184 px.
- Outer width: viewport width minus 48 px, capped by the maximum width.
- Initial height: 56 px.
- Scrolled height: 52 px.
- Horizontal padding: 12 px on the right and 18 px on the left.
- Corner radius: 26 px.
- Layer order: above all landing-page content and product demonstrations.

The internal layout has three stable zones:

- Left: approved Fleck symbol and wordmark, with a minimum protected width so
  center links do not shift.
- Center: the four primary links in a single horizontal group.
- Right: the waitlist action, with a minimum protected width matching the left
  zone closely enough to keep the center visually centered.

The navigation should not span edge-to-edge. Its floating margin is part of the
design and keeps it distinct from the macOS menu-bar demonstrations below.

## Visual Language

The navigation uses the approved Direction A "Field Notes" theme:

- Paper: `#F4F0E7`
- Graphite: `#202128`
- Violet: `#7257F5`
- Sage: `#B9C5B4`
- Navigation typeface: IBM Plex Sans
- Editorial display typeface elsewhere on the page: Newsreader

Surface:

- Paper fill at approximately 88% opacity.
- Backdrop blur around 18–22 px.
- One-pixel graphite border at approximately 9% opacity.
- Soft neutral shadow with a restrained violet ambient component; the shadow
  must remain subtle enough that the bar feels suspended, not glowing.
- No gradient border and no heavy glass reflection.

Typography:

- Links: IBM Plex Sans, 15 px, medium weight.
- CTA: IBM Plex Sans, 14 px, medium weight.
- Wordmark uses the approved Fleck logo asset rather than reconstructed text.
- Labels use sentence case.

Waitlist action:

- Graphite fill with paper-colored text in the resting state.
- Violet fill on hover and keyboard focus.
- Compact rounded rectangle, not a circular or oversized pill.
- Visible focus ring uses violet plus a paper offset.

## Fleck-Specific Active Marker

The distinguishing detail is a small violet "note tab" beneath the active link.

- It is a short rounded bar, approximately 16–20 px wide and 2 px tall.
- It moves between navigation items as the active page section changes.
- Hover may preview the marker beneath a different item without changing the
  selected section.
- It must not be the only active-state signal; active text also uses graphite at
  full opacity while inactive links use a slightly softened graphite.

This marker refers to a physical tab protruding from a notebook and connects the
navigation to Fleck's note organization without adding an illustrative icon.

## Motion and Scroll Behavior

At the top of the page:

- The bar is 56 px tall and uses the lighter paper-glass surface.
- It appears with a short downward settling motion after the first hero frame
  begins.

After approximately 24 px of scrolling:

- Height compresses to 52 px.
- The surface becomes slightly more opaque.
- Shadow tightens and backdrop blur increases slightly.
- The content does not reflow or change horizontal position.

Section tracking:

- The active marker moves with a restrained spring as section ownership changes.
- Link color changes and marker movement complete in roughly 180–240 ms.
- Clicking a link scrolls to the section with enough top offset that its heading
  is not hidden by the fixed bar.

Reduced motion:

- No entrance translation.
- Height and surface state change without spring motion.
- Active marker changes position immediately or with a short opacity crossfade.
- Smooth scrolling follows the user's platform preference.

## Hover, Focus, and Press States

Primary links:

- Rest: softened graphite.
- Hover: full graphite plus a preview of the violet marker.
- Keyboard focus: visible two-pixel violet outline with a paper offset.
- Press: one-pixel visual compression or a small opacity change; no large scale
  bounce.
- Active: full graphite plus persistent marker.

Logo:

- Uses a subtle opacity change on hover.
- Has a visible keyboard focus treatment.

Waitlist action:

- Rest: graphite surface.
- Hover/focus: violet surface.
- Press: restrained one-pixel compression.

## Mobile Navigation

At mobile breakpoints, the bar keeps the same floating paper-glass surface but
contains:

- Fleck symbol and wordmark on the left.
- Compact `Join waitlist` action.
- Menu button on the right.

The menu opens a paper-colored panel attached below the bar. It lists the four
primary destinations at comfortable touch sizes and keeps the waitlist action
visible. The menu:

- Uses a real menu icon from the chosen interface icon library.
- Traps focus while open.
- Closes on Escape, outside press, destination selection, or route change.
- Returns focus to the menu button after dismissal.
- Avoids full-screen takeover unless the smallest tested viewport cannot
  preserve readable spacing.

The mobile bar remains inset from the viewport by 12 px and respects safe-area
insets.

## Accessibility

- Navigation is exposed as a landmark with an explicit accessible label.
- Logo link has an accessible name such as `Fleck home`.
- Current section uses `aria-current` where appropriate.
- All interactive targets meet a minimum 44 × 44 px touch target on mobile.
- Text and focus states meet WCAG AA contrast against both navigation surface
  states.
- Surface opacity must remain high enough for text contrast over every hero
  frame.
- The navigation remains usable at 200% browser zoom.
- No state is communicated by violet color alone.

## Framer Component Structure

The implementation should create one reusable navigation component with:

- Desktop and mobile variants.
- Top and scrolled surface states.
- Open and closed mobile-menu states.
- Active-section property for the four primary links.
- Reusable link item and waitlist-button styles.

The component is placed on the Home page's existing desktop breakpoint. New
tablet and mobile breakpoints should be added only as required to verify the
responsive navigation behavior.

The approved logo asset is used directly:

`/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-logo-approved.png`

If the full logo image contains excess whitespace that prevents correct
navigation sizing, a production-ready transparent crop may be derived from the
approved asset without redrawing or changing the mark.

## Acceptance Criteria

- Desktop displays the approved logo, four links, and waitlist action in the
  correct order.
- The bar remains visually centered and fixed at all supported desktop widths.
- Center links do not visibly jump when scroll state or active section changes.
- Every link reaches its intended landing-page section.
- The waitlist action reaches or focuses the waitlist conversion surface.
- Top and scrolled states match the specified sizing and remain readable over
  the hero.
- Hover, focus, active, and pressed states are visibly distinct.
- Reduced-motion behavior removes spring and entrance movement.
- Mobile provides the logo, waitlist action, and an accessible working menu.
- The result is visually compared with the Craft reference for structure and
  with the Fleck Design Overview for typography, color, and brand consistency.
- The Framer Home page remains unpublished until the user explicitly asks to
  publish it.
