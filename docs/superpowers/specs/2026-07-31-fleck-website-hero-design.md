# Fleck Website Hero Design

Date: 2026-07-31

Status: Approved for implementation

## Source of Truth

Accepted concept:

`${PRIVATE_EVIDENCE_ROOT}/generated_images/019fb779-8096-70d1-a4d7-a606fd4b86cd/exec-c9f5646d-84da-48ef-9295-f7cea729de6e.png`

The implementation must reproduce only the first viewport shown in that image.
No content may be added below the hero.

## Page Structure

The page is one full-height white canvas containing:

1. A borderless header placed directly on the canvas.
2. A centered hero content stack.
3. A full-viewport interactive brain hologram behind the content.

The header has no bar, fill, blur, border, shadow, or contrasting region.

## Header

- Top-left identity: the existing Fleck mark plus the word `Fleck`.
- Mark size: approximately 24 px.
- Wordmark size: 16 px, medium weight.
- Top-right action: `Download for Mac`.
- Header action height: approximately 36 px with 13 px text and an 8 px radius.
- Both header groups use the viewport canvas as their background.

The repository contains no confirmed Fleck Mac App Store URL. Download links
must use `VITE_APP_STORE_URL` when supplied and otherwise expose an honest
unavailable state without inventing a destination.

## Hero Copy

Allowed visible copy, in order:

1. `Your panel for managing the noise.`
2. `Notes that think with you. Always close to your thoughts.`
3. `Dictate your thoughts with automatic cleanup, in a workspace where AI agents can collaborate and help finish tasks with you.`
4. `Download for Mac`
5. `View on GitHub`

No eyebrow, badge, proof strip, extra platform copy, or scroll cue is allowed.

## Hero Composition

- The hero content is centered horizontally and vertically in the first
  viewport, with a slight upward optical bias.
- The headline is a compact two-line modern sans-serif display, approximately
  68-72 px on the 1586 x 992 reference viewport.
- The motto is approximately 18 px.
- The supporting paragraph is approximately 16-17 px with a narrow measure.
- The primary action is content-width, about 48 px high, graphite with white
  text, and uses an 8-10 px radius.
- The GitHub action is a quiet 14 px source link directly beneath it.

## Brain Hologram

The hologram is a recognizable two-hemisphere brain built in native canvas.
It includes:

- Several hundred deterministic nodes distributed inside a brain silhouette.
- Fine local connections and longer violet signal paths.
- Layered curved contour paths that imply brain folds and depth.
- Graphite, gray, and restrained violet colors on a white canvas.
- A quiet center opening behind the copy.
- A pointer or touch interaction that pulls nearby nodes outward and bends
  their connections.
- Slow ambient drift that makes the network feel alive.

The animation must avoid React state on continuous frames, clean up its frame
loop and observers, scale for device pixel ratio, and render a static version
when reduced motion is requested.

## Responsive Behavior

- Desktop reproduces the 1586 x 992 concept composition.
- Tablet retains the centered brain and copy with reduced node density.
- Mobile keeps the header on one line, preserves readable actions, scales the
  headline to roughly 40-46 px, and allows the brain to extend beyond the
  viewport edges without horizontal scrolling.
- Touch movement drives the same local hologram response as pointer movement.
- The complete hero remains within `100dvh` at supported phone heights.

## Accessibility

- Header and actions use semantic links and visible focus states.
- The decorative canvas is hidden from assistive technology.
- Text and controls meet WCAG AA contrast.
- Reduced motion disables ambient movement and pointer deformation.
- Unavailable download actions are announced as unavailable.

## Verification

- Build the existing Vite website successfully.
- Compare a 1586 x 992 browser screenshot with the accepted concept using
  `view_image`.
- Verify a phone-sized viewport for clipping, wrapping, and touch-safe layout.
- Verify pointer interaction, reduced motion behavior, download fallback, and
  the GitHub destination.
- Confirm the visible copy exactly matches the allowed copy list.

