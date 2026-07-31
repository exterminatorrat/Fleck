import assert from "node:assert/strict";
import test from "node:test";
import { createBrainModel } from "./brainModel.js";

test("creates a deterministic two-sided brain model with valid edges", () => {
  const first = createBrainModel(1586, 992, 300);
  const second = createBrainModel(1586, 992, 300);

  assert.deepEqual(first.nodes, second.nodes);
  assert.equal(first.nodes.length, 300);
  assert.ok(first.nodes.some(({ side }) => side === -1));
  assert.ok(first.nodes.some(({ side }) => side === 1));
  assert.ok(first.edges.length > first.nodes.length);

  const left = first.nodes.filter(({ side }) => side === -1);
  const right = first.nodes.filter(({ side }) => side === 1);
  const centerX = 1586 / 2;

  assert.equal(left.length, right.length);
  assert.equal(
    first.nodes.filter(({ x }) => Math.abs(x - centerX) < 16).length,
    0,
  );

  first.edges.forEach(([from, to]) => {
    assert.ok(from >= 0 && from < first.nodes.length);
    assert.ok(to > from && to < first.nodes.length);
    assert.equal(first.nodes[from].side, first.nodes[to].side);
  });
});
