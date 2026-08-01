function seededRandom(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let value = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function addHemisphere(nodes, side, target, width, height, random) {
  const centerX = width * (side === -1 ? 0.35 : 0.65);
  const centerY = height * 0.49;
  const radiusX = width * 0.23;
  const radiusY = height * 0.45;

  for (let attempts = 0; nodes.length < target && attempts < target * 80; attempts += 1) {
    const x = random() * 2 - 1;
    const y = random() * 2 - 1;
    const angle = Math.atan2(y, x);
    const distance = Math.hypot(x, y);
    const lobedEdge =
      0.94 +
      Math.cos(angle * 3 - side * 0.45) * 0.04 +
      Math.cos(angle * 5 + side * 0.3) * 0.025;
    const inward = side === -1 ? x : -x;
    const fissureLimit = 0.47 + Math.min(1, Math.abs(y) / 0.78) * 0.08;

    if (distance > lobedEdge || inward > fissureLimit) continue;

    nodes.push({
      x: centerX + x * radiusX,
      y: centerY + y * radiusY,
      phase: random() * Math.PI * 2,
      size: 0.55 + random() * 1.25,
      violet: random() > 0.9,
      side,
    });
  }
}

export function createBrainModel(width, height, requestedCount) {
  const count = Math.max(40, requestedCount);
  const random = seededRandom(Math.round(width * 13 + height * 17 + count * 19));
  const nodes = [];
  const half = Math.floor(count / 2);

  addHemisphere(nodes, -1, half, width, height, random);
  addHemisphere(nodes, 1, count, width, height, random);

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

    nearest
      .sort((a, b) => a.distance - b.distance)
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
