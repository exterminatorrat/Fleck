import assert from "node:assert/strict";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { createServer } from "vite";

const vite = await createServer({
  appType: "custom",
  configFile: false,
  root: fileURLToPath(new URL("..", import.meta.url)),
  server: { middlewareMode: true, hmr: false },
});

after(() => vite.close());

test("renders the complete synthetic voice-to-agent hero story", async () => {
  const { default: HeroStory } = await vite.ssrLoadModule("/src/HeroStory.jsx");
  const markup = renderToStaticMarkup(
    createElement(HeroStory, { downloadProps: { href: "/download" } }),
  );

  assert.match(markup, /Capture thoughts\. Let your agents use them\./);
  assert.match(markup, /Fleck is a lightweight shared memory for you and your agents\./);
  assert.match(markup, /One shared memory\. For you and your agents\./);
  assert.match(markup, /Right Option/);
  assert.match(markup, /Northstar Demo: move the location permission request until after onboarding\./);
  assert.match(markup, /Pick up where I left off\./);
  assert.match(markup, /Do it\./);
  assert.match(markup, /Codex demo/);

  for (const path of [
    "/hero/fleck-northstar-open.png",
    "/hero/fleck-northstar-saved.png",
    "/hero/fleck-agent-writeback.png",
    "/hero/capsule-listening.png",
    "/hero/capsule-processing.png",
    "/hero/capsule-saved.png",
    "/hero/capsule-listening.mp4",
    "/hero/capsule-listening.webm",
    "/hero/capsule-processing.mp4",
    "/hero/capsule-processing.webm",
    "/hero/capsule-saved.mp4",
    "/hero/capsule-saved.webm",
    "/hero/agent-writeback.mp4",
    "/hero/agent-writeback.webm",
  ]) {
    assert.match(markup, new RegExp(path.replaceAll("/", "\\/")));
  }

  assert.doesNotMatch(markup, /Completed by Codex/);
  assert.doesNotMatch(markup, /Tests passing/);
  assert.doesNotMatch(markup, /macos-menu-bar/);
});
