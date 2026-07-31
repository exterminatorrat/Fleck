# Fleck Brain Silhouette Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing thought field read slightly more clearly as a top-down bilateral brain and remove the visible cursor rings.

**Architecture:** Keep the current deterministic canvas graph and change only its node acceptance envelope. Replace the high-frequency circular edge noise and broad middle cutout with a gently lobed radius plus a narrow, continuous center fissure; keep pointer displacement but delete the cursor-ring drawing block.

**Tech Stack:** React 19, Canvas 2D, Vite 8, Node test runner, Sites/Cloudflare Workers.

## Global Constraints

- Preserve the approved hero copy, typography, spacing, buttons, palette, graph density, and responsive layout.
- Keep the silhouette airy and abstract rather than anatomically literal.
- Retain subtle node displacement for pointer and touch input.
- Preserve `prefers-reduced-motion` behavior.
- Do not touch the user-owned `.superpowers/brainstorm/` directory.

---

### Task 1: Refine the deterministic brain envelope

**Files:**
- Modify: `website/src/brainModel.test.js`
- Modify: `website/src/brainModel.js`

**Interfaces:**
- Consumes: `createBrainModel(width, height, requestedCount)`.
- Produces: the same `{ nodes, edges, signals, positions }` shape with balanced hemispheres, a visible center fissure, and subtly lobed outer contours.

- [ ] **Step 1: Extend the model test with silhouette assertions**

Add assertions that each hemisphere has the same node count and no node enters a narrow center band:

```js
const left = first.nodes.filter(({ side }) => side === -1);
const right = first.nodes.filter(({ side }) => side === 1);
const centerX = 1586 / 2;

assert.equal(left.length, right.length);
assert.equal(
  first.nodes.filter(({ x }) => Math.abs(x - centerX) < 16).length,
  0,
);
```

- [ ] **Step 2: Run the test and verify the current model fails the stricter silhouette contract**

Run: `npm test`

Expected: FAIL on the new center-fissure or balance assertion.

- [ ] **Step 3: Replace the circular acceptance rule with a subtly lobed envelope**

Inside `addHemisphere`, derive polar values and an inward-facing coordinate:

```js
const angle = Math.atan2(y, x);
const distance = Math.hypot(x, y);
const lobedEdge =
  0.94 +
  Math.cos(angle * 3 - side * 0.45) * 0.035 +
  Math.cos(angle * 5 + side * 0.3) * 0.02;
const inward = side === -1 ? x : -x;
const fissureLimit = 0.47 + Math.min(1, Math.abs(y) / 0.78) * 0.08;

if (distance > lobedEdge) continue;
if (inward > fissureLimit) continue;
```

Delete the old `edgeNoise` and broad `Math.abs(y) < 0.57` cutout checks. Do not change node counts, radii, colors, edge construction, or animation data.

- [ ] **Step 4: Run the focused tests**

Run: `npm test`

Expected: 2 tests pass, 0 fail.

### Task 2: Remove cursor rings and verify the production surface

**Files:**
- Modify: `website/src/BrainHologram.jsx`

**Interfaces:**
- Consumes: the existing pointer state and model positions.
- Produces: the same responsive canvas animation without visible rings around the cursor.

- [ ] **Step 1: Delete only the cursor-ring drawing block**

Remove the block beginning with:

```js
if (pointer.active && !reducedMotion.matches) {
```

and ending after the three-ring loop. Keep the pointer state, `updatePointer`, and node displacement code intact.

- [ ] **Step 2: Run tests and build**

Run: `npm test && npm run build && git diff --check`

Expected: 2 tests pass, Vite emits `dist/client` and `dist/server`, and the command exits 0.

- [ ] **Step 3: Verify desktop and mobile in Browser/IAB**

Capture the hero at `1586x992` and `390x844`. Compare both with the accepted concept and confirm: clearer bilateral outline, narrow center fissure, unchanged copy/layout, no cursor rings, responsive node displacement, and no overflow or console errors.

- [ ] **Step 4: Commit and publish the verified source**

Commit only the model, test, canvas, and plan changes. Push the exact commit to the existing Sites source, save a new version, deploy privately, and verify the authenticated production root plus its main JavaScript asset both return HTTP 200.
