# Fleck MCP logo — short design

Approved batch scope: use Fleck's custom logo as its external MCP integration/tool icon. This does not redesign Fleck's in-app Activity indicator.

Visual: reuse the canonical website/public/fleck-mark.png without inventing a new mark. Preserve aspect ratio, transparent margins and identity. Prepare a compact PNG only as needed for small client rendering, and check both light/dark backgrounds. If the existing mark is illegible on one background, add theme-appropriate variants of the same artwork, not a new design.

Small-size inspection, 8 September: the original mark remains clear on white, but its three dark tiles nearly disappear on a #171717 surface at 16–32 px. An image-editor preview with a light backing altered the artwork and was rejected. The user has been asked whether to authorize deterministic compositing of a light backing; no answer has arrived. Until that choice is supplied, use the original canonical PNG bytes unchanged. Dark-surface contrast remains an explicit visual limitation. The browser comparison is evidence of the source contrast issue, not proof of Codex rendering.

Delivery: attach one shared MCP icons value to every advertised Tool through the common factory. Prefer a compact embedded PNG data URI, with accurate image/png MIME and dimensions, so branding works offline and after relocation. Avoid remote fetching, absolute development paths, tool-output decoration, new credentials or changed tool contracts.

Compatibility: the pinned SDK supports Tool.icons. Server.Info has icons but Server.init does not expose them; do not patch dependency internals or replace initialize handlers. Native icon metadata is the smallest first implementation. Codex's actual tool-call rendering remains a separate visual acceptance gate.

Client inspection limit: Computer Use explicitly denied access to com.openai.codex for safety reasons. Do not bypass that restriction with another capture technique. Protocol tests and a browser preview cannot establish that the actual Codex tool row displays the logo.

Acceptance: decode and validate advertised PNG; confirm all capability-filtered tools preserve their prior schemas/annotations; test a relocated packaged helper; call a read-only Fleck tool and inspect the requested Codex surface in light/dark appearance. If the client ignores icons, record metadata support as implemented and visible branding as blocked by client support. A plugin-wrapper alternative requires a separate scoped decision rather than silently changing installation or creating a duplicate server.

Implementation packet, file ownership and verification: ../plans/2026-09-07-shortcut-destination-mcp-logo.md, Packet3.
