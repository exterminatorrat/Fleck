function seededRandom(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let value = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

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

export function createBrainModel(width, height, requestedCount) {
  const count = Math.max(40, requestedCount);
  const random = seededRandom(Math.round(width * 13 + height * 17 + count * 19));
  const nodes = [];
  const half = Math.floor(count / 2);

  addHemisphere(nodes, -1, half, width, height, random);
  addHemisphere(nodes, 1, count - half, width, height, random);

  const edges = [];
  const seenEdges = new Set();
  const threshold = Math.min(width, height) * 0.12;
  const addEdge = (fromIndex, toIndex) => {
    const from = Math.min(fromIndex, toIndex);
    const to = Math.max(fromIndex, toIndex);
    const key = `${from}:${to}`;

    if (!seenEdges.has(key)) {
      seenEdges.add(key);
      edges.push([from, to]);
    }
  };

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
      .forEach(({ index: otherIndex }) => addEdge(index, otherIndex));
  });

  const signals = new Set(
    edges
      .filter(([from, to]) => (from * 7 + to * 11) % 23 === 0)
      .slice(0, 36)
      .map(([from, to]) => `${from}:${to}`),
  );

  return {
    nodes,
    edges,
    signals,
    positions: new Float32Array(nodes.length * 2),
  };
}
