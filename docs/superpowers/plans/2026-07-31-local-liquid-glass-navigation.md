# Fleck Local Liquid-Glass Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a localhost-only Fleck website containing one compact, responsive liquid-glass navigation bar and no other page features.

**Architecture:** Add an isolated React and Vite app under `website/`, leaving the native macOS package untouched. A single semantic `Navigation` component owns the brand, three anchor links, and waitlist action; plain CSS provides the glass treatment, responsive two-row layout, interaction states, and reduced-motion behavior.

**Tech Stack:** React 19.2.8, React DOM 19.2.8, Vite 8.2.0, Outfit 5.3.0 through `@fontsource/outfit`, CSS, npm, browser-based visual verification.

## Global Constraints

- Work only inside `website/`; do not modify native Fleck application files.
- Do not use Framer.
- Do not add landing-page sections, forms, email capture, APIs, analytics, persistence, menus, drawers, dropdowns, authentication, pricing, login, download, publishing, or deployment.
- Visible content is limited to the approved Fleck brand, `Features`, `How it works`, `FAQ`, and `Join waitlist`.
- Use the approved four-tile Fleck mark and render the `Fleck` wordmark as live Outfit Medium text.
- Use `#F4F0E7` Paper, `#202128` Graphite, and `#7257F5` Violet.
- Desktop uses a one-row navigation at widths of 720 px and above.
- Below 720 px, use a two-row capsule with brand and waitlist first, then all three links; do not add a hamburger.
- Keep the shell near 62 px high on desktop, no wider than 1120 px, with approximately 28 px rounding.
- Use CSS-native blur, saturation, edge, shadow, inset highlight, and restrained sheen; do not add glow, animated blobs, thick gradient borders, or decorative objects.
- Keep interaction durations between 160 and 220 ms and remove movement under `prefers-reduced-motion: reduce`.
- Preserve visible keyboard focus and at least 44 px touch targets on narrow screens.
- Reserve `#features`, `#how-it-works`, `#faq`, and `#waitlist` without creating their destination sections.
- Do not introduce a router, UI kit, CSS framework, icon set, animation package, or test framework.

## File Map

- Create: `website/.gitignore` — keeps generated dependencies and builds out of Git.
- Create: `website/index.html` — Vite document shell and page metadata.
- Create: `website/package.json` — exact dependencies and local scripts.
- Create: `website/package-lock.json` — npm-generated reproducible dependency graph.
- Create: `website/vite.config.js` — localhost-only Vite configuration.
- Create: `website/public/fleck-mark.png` — transparent crop of the approved four-tile mark.
- Create: `website/src/main.jsx` — React entry point and Outfit Medium import.
- Create: `website/src/App.jsx` — intentionally empty page surface plus navigation.
- Create: `website/src/Navigation.jsx` — semantic reusable navigation markup.
- Create: `website/src/styles.css` — tokens, glass treatment, states, and responsive layout.

---

### Task 1: Build and verify the local Fleck navigation

**Files:**

- Create: `website/.gitignore`
- Create: `website/index.html`
- Create: `website/package.json`
- Create: `website/package-lock.json`
- Create: `website/vite.config.js`
- Create: `website/public/fleck-mark.png`
- Create: `website/src/main.jsx`
- Create: `website/src/App.jsx`
- Create: `website/src/Navigation.jsx`
- Create: `website/src/styles.css`

**Interfaces:**

- Consumes: approved design specification at `docs/superpowers/specs/2026-07-31-local-liquid-glass-navigation-design.md` and approved logo source at `${PRIVATE_EVIDENCE_ROOT}/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-logo-approved.png`.
- Produces: default React export `Navigation(): JSX.Element`; Vite development URL `http://127.0.0.1:5173/`; production output in ignored `website/dist/`.

- [ ] **Step 1: Confirm the isolated RED baseline**

Run:

```bash
test ! -e website
npm --prefix website run build
```

Expected:

- `test ! -e website` exits `0`.
- The build exits non-zero because `website/package.json` does not exist.
- `git status --short` still shows no native application changes.

- [ ] **Step 2: Derive the transparent approved mark without redrawing it**

Inspect the source with `view_image`, then run:

```bash
mkdir -p website/public /tmp/fleck-nav-asset
sips \
  --cropToHeightWidth 340 340 \
  --cropOffset 472 168 \
  "${PRIVATE_EVIDENCE_ROOT}/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-logo-approved.png" \
  --out /tmp/fleck-nav-asset/fleck-mark-keyed.png
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input /tmp/fleck-nav-asset/fleck-mark-keyed.png \
  --out website/public/fleck-mark.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill
sips -g pixelWidth -g pixelHeight -g hasAlpha website/public/fleck-mark.png
```

Expected:

- `fleck-mark.png` is 340 × 340 with alpha.
- The transparent corners contain no Paper rectangle.
- The four original tiles remain complete, including the Violet lower-left tile.
- No wordmark pixels remain.

Inspect `website/public/fleck-mark.png` with `view_image`. If a visible light fringe remains, regenerate only the alpha matte with:

```bash
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input /tmp/fleck-nav-asset/fleck-mark-keyed.png \
  --out website/public/fleck-mark.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill \
  --edge-contract 1
```

- [ ] **Step 3: Create the minimal Vite foundation**

Create `website/.gitignore`:

```gitignore
node_modules/
dist/
```

Create `website/package.json`:

```json
{
  "name": "fleck-website",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@fontsource/outfit": "5.3.0",
    "react": "19.2.8",
    "react-dom": "19.2.8"
  },
  "devDependencies": {
    "vite": "8.2.0"
  }
}
```

Create `website/vite.config.js`:

```js
import { defineConfig } from "vite";

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
});
```

Create `website/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="theme-color" content="#f4f0e7" />
    <meta
      name="description"
      content="Fleck — local, personal notes with AI agent access."
    />
    <title>Fleck</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

Install the exact dependency graph:

```bash
cd website
npm install
cd ..
```

Expected:

- `website/package-lock.json` is created.
- `website/node_modules/` remains ignored.
- No files outside `website/` change.

- [ ] **Step 4: Create the semantic navigation component**

Create `website/src/Navigation.jsx`:

```jsx
const links = [
  { label: "Features", href: "#features" },
  { label: "How it works", href: "#how-it-works" },
  { label: "FAQ", href: "#faq" },
];

export default function Navigation() {
  return (
    <header className="site-header">
      <nav className="navigation" aria-label="Primary navigation">
        <a className="brand" href="/" aria-label="Fleck home">
          <img className="brand-mark" src="/fleck-mark.png" alt="" />
          <span className="brand-name">Fleck</span>
        </a>

        <div className="navigation-links">
          {links.map(({ label, href }) => (
            <a className="navigation-link" href={href} key={href}>
              {label}
            </a>
          ))}
        </div>

        <a className="waitlist-link" href="#waitlist">
          Join waitlist
        </a>
      </nav>
    </header>
  );
}
```

Create `website/src/App.jsx`:

```jsx
import Navigation from "./Navigation";

export default function App() {
  return (
    <div className="page">
      <Navigation />
    </div>
  );
}
```

Create `website/src/main.jsx`:

```jsx
import React from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/outfit/500.css";
import App from "./App";
import "./styles.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

- [ ] **Step 5: Implement the approved liquid-glass styling**

Create `website/src/styles.css`:

```css
:root {
  color: #202128;
  background: #eef0f5;
  font-family: "Outfit", sans-serif;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  --paper: #f4f0e7;
  --graphite: #202128;
  --violet: #7257f5;
  --muted-graphite: rgba(32, 33, 40, 0.68);
  --glass-edge: rgba(255, 255, 255, 0.68);
  --motion: 190ms cubic-bezier(0.2, 0.7, 0.2, 1);
}

* {
  box-sizing: border-box;
}

html {
  min-width: 320px;
  min-height: 100%;
}

body {
  min-width: 320px;
  min-height: 100vh;
  margin: 0;
  background:
    radial-gradient(circle at 50% -18%, rgba(114, 87, 245, 0.16), transparent 44%),
    linear-gradient(145deg, #f4f0e7 0%, #eef0f5 58%, #e9edf2 100%);
}

a {
  color: inherit;
  text-decoration: none;
}

.page {
  min-height: 100vh;
}

.site-header {
  padding: 24px 24px 0;
}

.navigation {
  position: relative;
  isolation: isolate;
  display: grid;
  grid-template-columns: minmax(180px, 1fr) auto minmax(180px, 1fr);
  align-items: center;
  width: 100%;
  max-width: 1120px;
  height: 62px;
  margin: 0 auto;
  padding: 0 12px 0 16px;
  overflow: hidden;
  border: 1px solid var(--glass-edge);
  border-radius: 28px;
  background: rgba(248, 247, 244, 0.68);
  box-shadow:
    0 14px 42px rgba(32, 33, 40, 0.1),
    inset 0 1px 0 rgba(255, 255, 255, 0.78);
  backdrop-filter: blur(24px) saturate(145%);
  -webkit-backdrop-filter: blur(24px) saturate(145%);
}

.navigation::before {
  position: absolute;
  z-index: 0;
  inset: 0;
  border-radius: inherit;
  background: linear-gradient(
    112deg,
    rgba(255, 255, 255, 0.34) 0%,
    rgba(255, 255, 255, 0.08) 38%,
    rgba(114, 87, 245, 0.07) 70%,
    rgba(255, 255, 255, 0.22) 100%
  );
  content: "";
  pointer-events: none;
}

.brand,
.navigation-links,
.waitlist-link {
  position: relative;
  z-index: 1;
}

.brand {
  display: inline-flex;
  align-items: center;
  justify-self: start;
  min-height: 44px;
  gap: 9px;
  transition: opacity var(--motion);
}

.brand:hover {
  opacity: 0.76;
}

.brand-mark {
  width: 31px;
  height: 31px;
  object-fit: contain;
}

.brand-name {
  font-size: 20px;
  font-weight: 500;
  line-height: 1;
}

.navigation-links {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 30px;
}

.navigation-link {
  position: relative;
  display: inline-flex;
  align-items: center;
  min-height: 44px;
  color: var(--muted-graphite);
  font-size: 14px;
  font-weight: 500;
  line-height: 1;
  white-space: nowrap;
  transition: color var(--motion);
}

.navigation-link::after {
  position: absolute;
  right: 25%;
  bottom: 7px;
  left: 25%;
  height: 2px;
  border-radius: 999px;
  background: var(--violet);
  content: "";
  opacity: 0;
  transform: scaleX(0.45);
  transition:
    opacity var(--motion),
    transform var(--motion);
}

.navigation-link:hover {
  color: var(--graphite);
}

.navigation-link:hover::after {
  opacity: 1;
  transform: scaleX(1);
}

.waitlist-link {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  justify-self: end;
  min-height: 38px;
  padding: 0 18px;
  border-radius: 13px;
  background: var(--graphite);
  color: var(--paper);
  font-size: 14px;
  font-weight: 500;
  line-height: 1;
  white-space: nowrap;
  box-shadow: 0 4px 12px rgba(32, 33, 40, 0.15);
  transition:
    background-color var(--motion),
    transform var(--motion);
}

.waitlist-link:hover {
  background: var(--violet);
}

.waitlist-link:active {
  transform: translateY(1px);
}

.brand:focus-visible,
.navigation-link:focus-visible,
.waitlist-link:focus-visible {
  border-radius: 8px;
  outline: 2px solid var(--violet);
  outline-offset: 3px;
}

.waitlist-link:focus-visible {
  border-radius: 13px;
}

@media (max-width: 719px) {
  .site-header {
    padding: 16px 14px 0;
  }

  .navigation {
    grid-template-areas:
      "brand waitlist"
      "links links";
    grid-template-columns: 1fr auto;
    grid-template-rows: 44px 44px;
    height: auto;
    min-height: 96px;
    padding: 7px 10px 5px 13px;
    border-radius: 24px;
  }

  .brand {
    grid-area: brand;
  }

  .brand-mark {
    width: 29px;
    height: 29px;
  }

  .navigation-links {
    grid-area: links;
    justify-content: space-around;
    width: 100%;
    gap: 0;
  }

  .navigation-link {
    justify-content: center;
    min-width: 72px;
    min-height: 44px;
  }

  .waitlist-link {
    grid-area: waitlist;
    min-height: 44px;
    padding-inline: 16px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .brand,
  .navigation-link,
  .navigation-link::after,
  .waitlist-link {
    transition: none;
  }

  .waitlist-link:active {
    transform: none;
  }
}
```

- [ ] **Step 6: Run the production and scope checks**

Run:

```bash
npm --prefix website run build
git diff --check
git status --short
```

Expected:

- Vite completes a production build with no errors.
- `git diff --check` reports no whitespace errors.
- All new implementation files are under `website/`.
- `node_modules/` and `dist/` do not appear in Git status.
- The pre-existing `.superpowers/brainstorm/` remains untouched and unstaged.

- [ ] **Step 7: Verify the rendered navigation in the browser**

Start the server:

```bash
npm --prefix website run dev -- --host 127.0.0.1
```

Use the Browser plugin first at `http://127.0.0.1:5173/`. Capture:

```text
${FLECK_REPO}/website/qa/fleck-nav-desktop.png
${FLECK_REPO}/website/qa/fleck-nav-mobile.png
```

Verify at 1440 × 900:

- one-row shell approximately 62 px high and no wider than 1120 px;
- brand left, links optically centered, and waitlist right;
- complete transparent mark plus live Outfit Medium wordmark;
- correct labels and no extra visible content;
- restrained blur, edge, shadow, inset highlight, and sheen.

Verify at 390 × 844:

- brand and waitlist occupy the first row;
- all three links occupy the second row;
- no overlap, clipping, drawer, hamburger, or horizontal scroll;
- every control is at least 44 px high.

Verify interaction:

- Tab reaches brand, three links, then waitlist in that order.
- Focus outlines are visible and unclipped.
- Link hover shows Violet underline.
- Waitlist hover changes Graphite to Violet.
- Waitlist press moves at most one pixel.
- Reduced-motion emulation removes movement but retains color and focus feedback.

Inspect the approved Craft reference at `${PRIVATE_EVIDENCE_ROOT}/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-reference-craft.png` and both rendered screenshots with `view_image`. Record a five-point fidelity ledger covering layout, typography, palette/glass, logo treatment, and responsive behavior. Fix any visible mismatch before continuing.

After verification, remove only the temporary QA screenshots and empty QA directory:

```bash
rm website/qa/fleck-nav-desktop.png website/qa/fleck-nav-mobile.png
rmdir website/qa
```

- [ ] **Step 8: Commit only the website**

Run:

```bash
git add website
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: add Fleck liquid-glass navigation"
```

Expected:

- Only `website/` files are staged.
- The commit contains the local Vite foundation, logo asset, navigation, styles, and npm lockfile.
- No macOS application, Framer, brainstorm, or generated dependency/build files are committed.
