import assert from "node:assert/strict";
import test from "node:test";
import { createBrainModel } from "./brainModel.js";

test("creates a dense deterministic two-sided brain network", () => {
  const first = createBrainModel(1440, 960, 560);
  const second = createBrainModel(1440, 960, 560);

  assert.deepEqual(first.nodes, second.nodes);
  assert.equal(first.nodes.length, 560);
  assert.ok(first.edges.length > first.nodes.length * 2);

  const left = first.nodes.filter(({ side }) => side === -1);
  const right = first.nodes.filter(({ side }) => side === 1);
  assert.equal(left.length, right.length);
  assert.equal(first.nodes.filter(({ x }) => Math.abs(x - 720) < 24).length, 0);

  first.edges.forEach(([from, to]) => {
    assert.ok(from >= 0 && from < first.nodes.length);
    assert.ok(to > from && to < first.nodes.length);
    assert.equal(first.nodes[from].side, first.nodes[to].side);
  });
});
