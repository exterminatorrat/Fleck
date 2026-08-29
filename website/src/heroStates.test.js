import assert from "node:assert/strict";
import { test } from "node:test";
import { heroStateForProgress } from "./heroStates.js";

test("maps clamped scroll progress to each hero state at its exact boundaries", () => {
  const cases = [
    [-1, "intro"],
    [0, "intro"],
    [0.139, "intro"],
    [0.14, "shortcut"],
    [0.249, "shortcut"],
    [0.25, "listening"],
    [0.329, "listening"],
    [0.33, "processing"],
    [0.399, "processing"],
    [0.4, "saved"],
    [0.439, "saved"],
    [0.44, "memory"],
    [0.479, "memory"],
    [0.48, "codex"],
    [0.679, "codex"],
    [0.68, "writeback"],
    [0.899, "writeback"],
    [0.9, "close"],
    [1, "close"],
    [2, "close"],
  ];

  for (const [progress, expected] of cases) {
    assert.equal(heroStateForProgress(progress), expected, `progress ${progress}`);
  }
});
