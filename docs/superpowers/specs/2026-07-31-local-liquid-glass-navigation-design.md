# Fleck Local Liquid-Glass Navigation Design

## Status

Approved for implementation on 2026-07-31.

## Goal

Create the first local website surface for Fleck: a compact, rounded,
Craft-inspired liquid-glass navigation bar running on localhost.

This slice establishes the website foundation and navigation styling only. It
does not build the landing-page sections or any waitlist behavior.

## Context

The repository currently contains the native Fleck macOS application and has no
web application scaffold. The website must therefore live in an isolated
`website/` directory so the Swift package and macOS build remain untouched.

The previous Framer prototype is no longer the implementation target. No Framer
project state, component, deployment, or asset URL is part of this local build.

## Scope

### Included

- A new local React and Vite website in `website/`.
- One reusable `Navigation` component.
- A desktop/tablet liquid-glass navigation layout.
- A narrow-screen two-row layout using the same component.
- The approved Fleck mark and a live `Fleck` wordmark in Outfit Medium.
- Navigation labels:
  - Features
  - How it works
  - FAQ
- A right-side `Join waitlist` action.
- Hover, press, keyboard-focus, and reduced-motion states.
- Local desktop and mobile visual verification.

### Excluded

- Hero or landing-page content.
- Features, How it works, FAQ, or Waitlist sections.
- Forms, email capture, APIs, analytics, or persistence.
- Hamburger menus, drawers, dropdowns, or mega-menus.
- Authentication, pricing, download, or login controls.
- Framer changes.
- Publishing or deployment.

## Technical Foundation

Use React with Vite and plain CSS.

This is slightly more structure than a single static HTML file, but it keeps the
navigation reusable when the rest of the Fleck landing page is added. It avoids
framework features and dependencies that this slice does not need.

The only non-framework typography dependency is Outfit:

```text
@fontsource/outfit
```

No component library, CSS framework, animation library, router, or icon package
is required.

## File Ownership

Implementation is confined to:

```text
website/
├── index.html
├── package.json
├── vite.config.js
├── public/
│   └── fleck-mark.png
└── src/
    ├── App.jsx
    ├── Navigation.jsx
    ├── main.jsx
    └── styles.css
```

The approved four-tile symbol will be derived as a transparent PNG from the
existing Fleck logo. It must not be redrawn with CSS, text glyphs, or an
approximate SVG.

The word `Fleck` remains live HTML text rather than baked into the raster asset,
so Outfit Medium renders crisply at every viewport.

## Information Architecture

Desktop content order:

```text
[ Fleck mark + Fleck ]   [ Features  How it works  FAQ ]   [ Join waitlist ]
```

The brand occupies the left zone, the three links form a centered group, and the
waitlist action anchors the right zone.

The component uses semantic elements:

- `<nav aria-label="Primary navigation">`
- A home link for the brand.
- Anchor links for the three navigation destinations.
- An anchor link styled as the primary waitlist action.

The initial reserved hashes are:

```text
#features
#how-it-works
#faq
#waitlist
```

The destination sections are intentionally absent in this slice. The links
establish the final navigation contract without adding placeholder content.

## Layout

### Desktop and Tablet

- Fixed visual height: approximately 62 px.
- Maximum width: 1120 px.
- Width: viewport minus 48 px, with 24 px side margins.
- Top margin: 24 px.
- Horizontal padding: 14 px on the shell.
- Left and right zones use equal minimum widths so the center links remain
  optically centered.
- Link gap: approximately 30 px.
- The bar remains one row at widths of 720 px and above.

### Narrow Screens

Below 720 px, the same navigation component wraps into two rows:

```text
[ Fleck mark + Fleck ]                  [ Join waitlist ]
[        Features   How it works   FAQ                 ]
```

- No hamburger or drawer is introduced.
- The brand and waitlist action remain on the first row.
- The three links occupy a centered second row.
- The capsule grows only enough to contain both rows.
- All controls remain visible and reachable without horizontal scrolling.

## Visual System

### Typography

- Family: Outfit.
- Wordmark: Outfit Medium, 20 px.
- Navigation labels: Outfit Medium, 14 px.
- Waitlist action: Outfit Medium, 14 px.
- Letter spacing remains close to normal; no exaggerated tracking.

### Color

```text
Paper:          #F4F0E7
Graphite:       #202128
Violet:         #7257F5
Muted graphite: rgba(32, 33, 40, 0.68)
Glass edge:     rgba(255, 255, 255, 0.68)
```

The empty localhost page uses a quiet cool-neutral background with a restrained
violet atmospheric wash so the transparent glass surface is visible. It must
not introduce content, cards, or decorative objects.

### Liquid Glass

The shell uses CSS-native glass treatment:

- A translucent Paper/white surface.
- `backdrop-filter: blur(24px) saturate(145%)`.
- A one-pixel bright edge.
- One soft ambient shadow.
- One subtle inset highlight.
- A restrained diagonal refraction sheen through a pseudo-element.
- Approximately 28 px radius.

The sheen is low contrast and remains inside the shell. There is no glow,
animated blob, thick gradient border, or exaggerated reflection.

### Waitlist Action

- Graphite background and Paper text at rest.
- Violet background on hover.
- Small one-pixel downward press response.
- Approximately 38 px high.
- Rounded rectangle, not a full pill.

## Interaction

- Navigation labels move from muted Graphite to full Graphite on hover.
- A short Violet underline appears beneath the hovered link.
- The brand receives a subtle opacity change on hover.
- The waitlist action changes from Graphite to Violet.
- Press feedback is limited to one pixel of vertical movement.
- Keyboard focus uses a two-pixel Violet outline with a Paper offset.
- Motion durations stay between 160 and 220 ms.
- `prefers-reduced-motion: reduce` removes movement while preserving color and
  focus feedback.

No interaction in this slice opens a menu, submits data, or reveals additional
content.

## Accessibility

- All visible text meets WCAG AA contrast against its effective surface.
- Every link is keyboard reachable in visual order.
- Focus styling is visible and not clipped by the rounded shell.
- Touch targets are at least 44 px high on narrow screens.
- The logo image has empty alternative text because the adjacent live `Fleck`
  wordmark supplies the accessible brand name.
- The brand link uses `aria-label="Fleck home"`.

## Verification

Run the website through Vite on localhost and verify:

1. Production build completes without errors.
2. Desktop at 1440 × 900:
   - one-row 62 px bar;
   - optically centered link group;
   - complete Fleck mark and wordmark;
   - restrained glass edge and shadows.
3. Mobile at 390 × 844:
   - two-row capsule;
   - no clipped or overlapping controls;
   - no horizontal scrolling;
   - 44 px minimum touch targets.
4. Hover, press, and keyboard-focus states work.
5. Reduced-motion mode removes movement.
6. The page contains no content beyond the navigation and its neutral
   demonstration background.

## Acceptance Criteria

- `npm run dev` starts the website locally.
- The native macOS application files are unchanged.
- The bar contains only the approved brand, three navigation labels, and
  waitlist action.
- Outfit Medium is used for the live wordmark and navigation typography.
- The design reads as liquid glass without becoming glossy or decorative.
- Desktop and narrow-screen layouts are visually resolved.
- No Framer, landing-page sections, waitlist functionality, or unrelated
  feature is implemented.
