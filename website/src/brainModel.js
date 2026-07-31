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
  const mobile = width < 600;
  const centerX = width * (side === -1 ? (mobile ? 0.19 : 0.34) : mobile ? 0.81 : 0.66);
  const centerY = height * 0.52;
  const radiusX = mobile
    ? width * 0.48
    : Math.min(width * 0.275, height * 0.43);
  const radiusY = height * (mobile ? 0.39 : 0.43);

  for (let attempts = 0; nodes.length < target && attempts < target * 80; attempts += 1) {
    const x = random() * 2 - 1;
    const y = random() * 2 - 1;
    const edgeNoise = 0.92 + Math.sin(y * 9 + side) * 0.05;

    if (x * x + y * y > edgeNoise) continue;
    if (side === -1 && x > 0.02 && Math.abs(y) < 0.57) continue;
    if (side === 1 && x < -0.02 && Math.abs(y) < 0.57) continue;

    nodes.push({
      x: centerX + x * radiusX,
      y: centerY + y * radiusY,
      phase: random() * Math.PI * 2,
      size: 0.7 + random() * 1.65,
      violet: random() > 0.91,
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
  const threshold = Math.min(width, height) * (width < 600 ? 0.15 : 0.135);
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
      if (candidate === index) continue;
      if (node.side !== other.side) continue;
      const distance = Math.hypot(node.x - other.x, node.y - other.y);
      if (distance < threshold) nearest.push({ index: candidate, distance });
    }

    nearest
      .sort((a, b) => a.distance - b.distance)
      .slice(0, 4)
      .forEach(({ index: otherIndex }) => {
        addEdge(index, otherIndex);
      });

    const hemisphereStart = node.side === -1 ? 0 : half;
    const hemisphereSize = node.side === -1 ? half : nodes.length - half;
    const localIndex = index - hemisphereStart;
    const chordIndex = hemisphereStart + ((localIndex + 17) % hemisphereSize);
    const chord = nodes[chordIndex];

    if (
      index % 2 === 0 &&
      Math.hypot(node.x - chord.x, node.y - chord.y) < threshold * 2.35
    ) {
      addEdge(index, chordIndex);
    }
  });

  const signals = new Set(
    edges
      .filter(([from, to]) => (from * 7 + to * 11) % 23 === 0)
      .slice(0, 28)
      .map(([from, to]) => `${from}:${to}`),
  );

  return {
    nodes,
    edges,
    signals,
    positions: new Float32Array(nodes.length * 2),
  };
}
