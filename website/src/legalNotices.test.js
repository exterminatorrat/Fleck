import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { build } from "vite";

const websiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("preserves third-party notices in the production build", async () => {
  const outDir = await mkdtemp(join(tmpdir(), "fleck-website-licenses-"));

  try {
    await build({
      root: websiteRoot,
      logLevel: "silent",
      build: { outDir },
    });

    const assets = await readdir(join(outDir, "assets"));
    const checks = [
      ["GSAP", /^gsap-.*\.js$/, "GSAP 3.15.0"],
      ["ScrollTrigger", /^ScrollTrigger-.*\.js$/, "ScrollTrigger 3.15.0"],
    ];

    for (const [name, filePattern, productBanner] of checks) {
      const file = assets.find((candidate) => filePattern.test(candidate));
      assert.ok(file, `${name} production chunk is missing`);

      const contents = await readFile(join(outDir, "assets", file), "utf8");
      for (const notice of [
        productBanner,
        "https://gsap.com",
        "@license Copyright 2008-2026, GreenSock. All rights reserved.",
        "Subject to the terms at https://gsap.com/standard-license",
        "@author: Jack Doyle, jack@greensock.com",
      ]) {
        assert.ok(contents.includes(notice), `${name} notice lost: ${notice}`);
      }
    }

    const sourceNotice = await readFile(
      join(websiteRoot, "public", "THIRD_PARTY_LICENSES.txt"),
    );
    const builtNotice = await readFile(join(outDir, "THIRD_PARTY_LICENSES.txt"));
    assert.deepEqual(builtNotice, sourceNotice);
  } finally {
    await rm(outDir, { recursive: true, force: true });
  }
});
