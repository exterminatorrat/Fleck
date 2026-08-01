import assert from "node:assert/strict";
import test from "node:test";
import { JOURNEY_CAPTURE_ASSET, JOURNEY_STAGES } from "./journeyContent.js";

test("defines the approved capture through finish story", () => {
  assert.deepEqual(
    JOURNEY_STAGES.map(({ id, label, description }) => [id, label, description]),
    [
      ["capture", "Capture", "Thought enters Fleck from the menu bar."],
      ["cleanup", "Clean up", "Fleck turns rough speech into a clean, structured note."],
      ["collaborate", "Collaborate", "Invite agents to this note only."],
      ["finish", "Finish", "Agents complete tasks and leave a clear trail."],
    ],
  );
  assert.equal(JOURNEY_CAPTURE_ASSET, "/assets/fleck-ideas-capture.png");
});
