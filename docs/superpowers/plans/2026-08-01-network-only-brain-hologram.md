# Network-only Brain Hologram Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the raster-backed hero brain with an airy, interactive canvas network whose own nodes and edges form a recognizable bilateral brain silhouette.

**Architecture:** Keep `BrainHologram.jsx` as the canvas animation owner and move all silhouette decisions into the deterministic `createBrainModel` generator. Generate separate outer-contour, fissure-contour, and interior node populations, then favor contour-to-contour edges while preserving the existing same-hemisphere constraint and cursor displacement.

**Tech Stack:** React 19, Canvas 2D, deterministic JavaScript model generation, Node test runner, CSS.

## Global Constraints

- Remove the raster brain from the rendered hero.
- Keep the result clearly recognizable as a brain at first glance but visually airy.
- Preserve slow breathing, ambient drift, and local pointer displacement.
- Do not render pointer-bound rings, signals, or radar arcs.
- Touch interaction stays disabled and reduced motion produces a static network.
- Add no dependency, WebGL layer, physics library, or below-hero content.

---

### Task 1: Make the network itself describe the brain

**Files:**
- Modify: `website/src/brainModel.test.js`
- Modify: `website/src/brainModel.js`
- Modify: `website/src/BrainHologram.jsx`
- Modify: `website/src/styles.css`
- Modify: `website/design-qa.md`

**Interfaces:**
- Consumes: `createBrainModel(width, height, requestedCount)` and its existing `{ nodes, edges, signals, positions }` return object.
- Produces: the same public return shape; each internal node also carries `region: "outer" | "fissure" | "interior"` for edge selection and tests.

- [ ] **Step 1: Write the failing silhouette test**

Replace the current test body with assertions that preserve determinism and edge validity while proving that the generated model contains substantial contour coverage and a quiet copy area:

```js
test("creates a deterministic brain-shaped network", () => {
  const first = createBrainModel(1440, 960, 560);
  const second = createBrainModel(1440, 960, 560);

  assert.deepEqual(first.nodes, second.nodes);
  assert.equal(first.nodes.length, 560);
  assert.ok(first.edges.length > first.nodes.length * 2);

  const left = first.nodes.filter(({ side }) => side === -1);
  const right = first.nodes.filter(({ side }) => side === 1);
  const contours = first.nodes.filter(({ region }) => region !== "interior");
  const copyArea = first.nodes.filter(
    ({ x, y }) => Math.abs(x - 720) < 250 && Math.abs(y - 480) < 170,
  );

  assert.equal(left.length, right.length);
  assert.ok(contours.length >= first.nodes.length * 0.5);
  assert.ok(copyArea.length < first.nodes.length * 0.08);

  first.edges.forEach(([from, to]) => {
    assert.ok(from >= 0 && from < first.nodes.length);
    assert.ok(to > from && to < first.nodes.length);
    assert.equal(first.nodes[from].side, first.nodes[to].side);
  });
});
```

- [ ] **Step 2: Run the model test and confirm it fails**

Run: `node --test website/src/brainModel.test.js`

Expected: FAIL because existing nodes do not expose `region` and the current uniform interior distribution does not satisfy the contour requirement.

- [ ] **Step 3: Generate contour-biased nodes**

In `website/src/brainModel.js`, keep `seededRandom` and replace `addHemisphere` with three focused generators. Use the current hemisphere geometry (`centerX`, `centerY`, `radiusX`, and `radiusY`) and the same lobed radius function:

```js
function geometry(side, width, height) {
  return {
    centerX: width * (side === -1 ? 0.35 : 0.65),
    centerY: height * 0.49,
    radiusX: width * 0.23,
    radiusY: height * 0.45,
  };
}

function edgeRadius(angle, side) {
  return (
    0.94 +
    Math.cos(angle * 3 - side * 0.45) * 0.04 +
    Math.cos(angle * 5 + side * 0.3) * 0.025
  );
}

function pushNode(nodes, side, region, x, y, random, shape) {
  nodes.push({
    x: shape.centerX + x * shape.radiusX,
    y: shape.centerY + y * shape.radiusY,
    phase: random() * Math.PI * 2,
    size: 0.55 + random() * 1.25,
    violet: random() > 0.9,
    side,
    region,
  });
}

function addHemisphere(nodes, side, target, width, height, random) {
  const shape = geometry(side, width, height);
  const start = nodes.length;
  const outerTarget = Math.round(target * 0.38);
  const fissureTarget = Math.round(target * 0.14);

  let outerAdded = 0;
  for (let attempts = 0; outerAdded < outerTarget && attempts < outerTarget * 20; attempts += 1) {
    const angle = random() * Math.PI * 2;
    const radius = edgeRadius(angle, side) * (0.94 + random() * 0.055);
    const x = Math.cos(angle) * radius;
    const y = Math.sin(angle) * radius;
    const inward = side === -1 ? x : -x;
    if (inward < 0.48 + Math.min(1, Math.abs(y) / 0.78) * 0.08) {
      pushNode(nodes, side, "outer", x, y, random, shape);
      outerAdded += 1;
    }
  }

  for (let index = 0; index < fissureTarget; index += 1) {
    const y = -0.76 + (index / Math.max(1, fissureTarget - 1)) * 1.52;
    const inward = 0.46 + Math.abs(y) * 0.08 + (random() - 0.5) * 0.035;
    pushNode(nodes, side, "fissure", -side * inward, y, random, shape);
  }

  for (let attempts = 0; nodes.length - start < target && attempts < target * 100; attempts += 1) {
    const x = random() * 2 - 1;
    const y = random() * 2 - 1;
    const angle = Math.atan2(y, x);
    const distance = Math.hypot(x, y);
    const inward = side === -1 ? x : -x;
    const fissureLimit = 0.47 + Math.min(1, Math.abs(y) / 0.78) * 0.08;
    const worldX = shape.centerX + x * shape.radiusX;
    const worldY = shape.centerY + y * shape.radiusY;
    const inCopyArea =
      Math.abs(worldX - width / 2) < width * 0.175 &&
      Math.abs(worldY - height * 0.5) < height * 0.18;

    if (distance > edgeRadius(angle, side) * 0.9 || inward > fissureLimit || inCopyArea) continue;
    pushNode(nodes, side, "interior", x, y, random, shape);
  }
}
```

Generate a balanced count per hemisphere:

```js
const half = Math.floor(count / 2);
addHemisphere(nodes, -1, half, width, height, random);
addHemisphere(nodes, 1, count - half, width, height, random);
```

During edge generation, favor same-region neighbors before adding the general
local mesh, reusing `addEdge` so duplicates are discarded:

```js
nodes.forEach((node, index) => {
  const nearest = [];

  for (let candidate = 0; candidate < nodes.length; candidate += 1) {
    const other = nodes[candidate];
    if (candidate === index || node.side !== other.side) continue;
    const distance = Math.hypot(node.x - other.x, node.y - other.y);
    if (distance < threshold) nearest.push({ index: candidate, distance });
  }

  nearest.sort((a, b) => a.distance - b.distance);
  nearest
    .filter(({ index: candidate }) => nodes[candidate].region === node.region)
    .slice(0, 2)
    .forEach(({ index: candidate }) => addEdge(index, candidate));
  nearest
    .slice(0, 5)
    .forEach(({ index: candidate }) => addEdge(index, candidate));
});
```

Keep the existing edge threshold, signal selection, and return shape.

- [ ] **Step 4: Run the model test and tune only constants if needed**

Run: `node --test website/src/brainModel.test.js`

Expected: PASS with exactly 560 balanced nodes, at least 280 contour nodes, fewer than 45 nodes in the copy area, more than 1,120 edges, and only same-side edges.

- [ ] **Step 5: Remove the raster layer from the component and CSS**

In `website/src/BrainHologram.jsx`, render only the canvas:

```jsx
return (
  <div className="brain-hologram" aria-hidden="true">
    <div className="brain-hologram-visual">
      <canvas ref={canvasRef} className="brain-network" />
    </div>
  </div>
);
```

In `website/src/styles.css`, remove `.brain-hologram img` and its image-only declaration. Keep `.brain-network` absolutely inset at `0`, full-sized, and at the current opacity. Preserve the shared breathing animation and reduced-motion rule.

- [ ] **Step 6: Verify behavior in the browser**

At `http://127.0.0.1:4173/`, inspect a 1440 × 1000 desktop viewport and a 390 × 844 mobile viewport. Confirm:

- the image asset is not rendered;
- the outer lobes and center fissure make the network read as a brain;
- the headline remains readable through the quiet center;
- pointer movement displaces only nearby network geometry and renders no pointer signal;
- mobile `document.documentElement.scrollWidth === 390`;
- the console contains no errors or warnings.

Replace `website/design-qa-hero-desktop.png`, `website/design-qa-hero-mobile.png`, and `website/design-qa-hero-comparison.png` with the verified captures. Update `website/design-qa.md` to describe the network-only implementation and record `final result: passed` only after the checks pass.

- [ ] **Step 7: Run the complete focused verification**

Run: `npm test` from `website/`.

Expected: 2 tests pass, 0 fail.

Run: `npm run build` from `website/`.

Expected: Vite server and client builds complete successfully.

Run: `git diff --check` from the repository root.

Expected: no output.

- [ ] **Step 8: Commit the implementation**

```bash
git add website/src/brainModel.test.js website/src/brainModel.js website/src/BrainHologram.jsx website/src/styles.css website/design-qa.md website/design-qa-hero-desktop.png website/design-qa-hero-mobile.png website/design-qa-hero-comparison.png
git commit -m "feat: shape hero network into a brain"
```
