import assert from "node:assert/strict";
import test from "node:test";
import worker from "./index.js";

test("serves the Vite entry document for the site root", async () => {
  let assetRequest;
  const env = {
    ASSETS: {
      fetch(request) {
        assetRequest = request;
        return new Response("ok");
      },
    },
  };

  const response = await worker.fetch(new Request("https://fleck.example/"), env);

  assert.equal(response.status, 200);
  assert.equal(new URL(assetRequest.url).pathname, "/index.html");
});
