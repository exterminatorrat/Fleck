import assert from "node:assert/strict";
import test from "node:test";
import { createBrainModel } from "./brainModel.js";

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
