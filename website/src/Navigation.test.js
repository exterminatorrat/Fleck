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
  server: { middlewareMode: true },
});

after(() => vite.close());

test("renders the navigation menu disclosure contract", async () => {
  const { default: Navigation } = await vite.ssrLoadModule("/src/Navigation.jsx");
  const markup = renderToStaticMarkup(
    createElement(Navigation, { downloadProps: { href: "/download" } }),
  );

  assert.match(markup, /<button[^>]*aria-haspopup="menu"[^>]*aria-expanded="false"/);
  assert.match(markup, /aria-controls="site-menu-panel"/);
  assert.match(markup, /id="site-menu-panel"[^>]*role="menu"[^>]*aria-hidden="true"/);
  assert.match(markup, /href="\/"[^>]*role="menuitem"[^>]*>Home<\/a>/);
  assert.equal((markup.match(/aria-disabled="true"/g) ?? []).length, 6);
  assert.match(markup, /href="\/download"[^>]*>Download for Mac<\/a>/);
});
