import assert from "node:assert/strict";
import test from "node:test";
import { FLECK_CAPTURE_ASSET, IDEA_STAGES } from "./ideasContent.js";

test("defines the approved idea-loss story in order", () => {
  assert.deepEqual(
    IDEA_STAGES.map(({ id, label }) => [id, label]),
    [
      ["spark", "A spark of an idea"],
      ["capture", "You try to capture it"],
      ["handoff", "Copy, paste, repeat"],
      ["fleck", "Fleck catches it and keeps it whole"],
    ],
  );
  assert.equal(FLECK_CAPTURE_ASSET, "/assets/fleck-ideas-capture.png");
});
