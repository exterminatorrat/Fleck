# Network-only brain hologram

Status: approved direction, awaiting written-spec review.

## Goal

Replace the raster brain image in Fleck's hero with a pure canvas network that
is clearly recognizable as a brain at first glance while remaining airy enough
for the hero copy to stay dominant.

## Selected approach

Use the existing deterministic canvas renderer and reshape its node generation.
Each hemisphere receives three node groups:

- a higher-density lobed outer contour that establishes the silhouette;
- a narrower central-fissure contour that separates the hemispheres;
- a lower-density interior field that gives the form depth without becoming a
  solid mesh.

Connections remain short and stay within their hemisphere. Contour nodes favor
nearby contour neighbors so the outline reads continuously; interior nodes keep
the existing nearest-neighbor behavior. The center behind the hero copy remains
quieter than the outer lobes.

The existing slow breathing, ambient drift, and local pointer displacement stay.
Touch interaction and pointer-bound rings, signals, or radar arcs remain absent.

## Alternatives considered

1. Keep a faint raster beneath the network. This gives the strongest anatomy,
   but conflicts with the request to remove the image hologram.
2. Draw explicit vector brain outlines. This is immediately recognizable, but
   reads as an illustration placed behind the network rather than a hologram
   made from the network itself.
3. Shape the network through contour-biased nodes and edges. This is selected
   because the interactive system itself creates the silhouette.

## Implementation boundaries

- `BrainHologram.jsx` renders only the canvas and keeps the current animation
  and pointer lifecycle.
- `brainModel.js` owns deterministic node placement, contour classification,
  and edge generation.
- CSS keeps one scaled visual layer and removes image-only styling.
- No new dependency, WebGL layer, physics library, or content below the hero is
  introduced.

## Failure handling and accessibility

The canvas stays decorative and hidden from assistive technology. If its size
changes, the existing resize observer regenerates a deterministic model for the
new dimensions. Reduced-motion users receive a static network with no breathing,
drift, or pointer displacement.

## Verification

- Model tests prove deterministic output, balanced hemispheres, a quiet center,
  valid same-side edges, and sufficient contour coverage.
- Desktop and 390 px mobile screenshots confirm the brain reads without the
  raster image, the copy remains legible, and there is no horizontal overflow.
- Pointer-hover inspection confirms nearby nodes and edges move while no
  cursor-following signal appears.
- `npm test`, `npm run build`, and `git diff --check` pass.
