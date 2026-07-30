# Fleck Website Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Craft-inspired floating field bar as a reusable, responsive Framer navigation system and apply it to Fleck's blank Home page without publishing the site.

**Architecture:** Create a canvas-native `Fleck Navigation` component with desktop top/scrolled variants and mobile closed/open drawer variants. Distribute the component through one `Fleck Site Layout` layout template, then apply that template to the existing Home page. Keep final section hashes in the links now; the later landing-page sections will supply those scroll targets.

**Tech Stack:** Framer canvas components and variants, Framer Layout Templates, Framer Agent DSL, IBM Plex Sans, Lucide icons, the approved Fleck logo asset, Framer visual screenshots and serialized-node verification.

## Global Constraints

- Framer project ID is `d0qX2IekJlwu8LZD98Js`.
- Home page ID is `augiA20Il`, path `/`, with primary desktop breakpoint `WQLkyLRf1`.
- The Home page is currently blank. Preserve that blank content canvas; this plan adds only shared navigation.
- Use the approved logo asset at `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-logo-approved.png`.
- Use IBM Plex Sans for navigation copy.
- Use `#F4F0E7` Paper, `#202128` Graphite, `#7257F5` Violet, and `#B9C5B4` Sage.
- Desktop content order is Fleck logo, Product, How it works, Agent access, Principles, Join the waitlist.
- Hash destinations are `/#product`, `/#how-it-works`, `/#agent-access`, `/#principles`, and `/#waitlist`.
- Do not add Login, Pricing, Download, a mega-menu, a recorder, or a waveform.
- Use one reusable component and one shared layout template; do not place independent navigation copies directly on page breakpoints.
- The mobile menu must be a closed/open component-variant drawer, not a fixed overlay.
- Use Lucide `Menu` and `X` icons; do not draw menu icons with shapes, text symbols, SVG strings, or emoji.
- Preserve the existing Design Overview page and all of its nodes.
- Do not publish, deploy, or change Framer project access.
- Framer mutations must inspect and resolve every diagnostic before the next unrelated mutation.
- Because the destination sections do not exist yet, verify the exact final hashes now. End-to-end scroll landing and section-aware active tracking are release gates for the later section-build plan, not reasons to add empty placeholder sections here.

## File and Framer Object Map

**Local documentation**

- Read: `docs/superpowers/specs/2026-07-30-fleck-website-navigation-design.md`
- Read: `/Users/harryjin/.agents/skills/framer/projects/d0qX2IekJlwu8LZD98Js/prompt/how-projects-work.md`
- Read: `/Users/harryjin/.agents/skills/framer/projects/d0qX2IekJlwu8LZD98Js/prompt/updating-the-project.md`
- Read: `/Users/harryjin/.agents/skills/framer/projects/d0qX2IekJlwu8LZD98Js/prompt/implementation-strategy.md`
- Evidence input: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-reference-craft.png`
- Evidence output: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-desktop.png`
- Evidence output: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-mobile-closed.png`
- Evidence output: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-mobile-open.png`

**Framer objects**

- Create component: `FleckNavComp` — `Fleck Navigation`
- Create variants:
  - `FleckNavDeskTop` — `Desktop / Top`
  - `FleckNavDeskScr` — `Desktop / Scrolled`
  - `FleckNavMobCls` — `Mobile / Closed`
  - `FleckNavMobOpn` — `Mobile / Open`
- Create layout template: `FleckSiteLay` — `Fleck Site Layout`
- Create layout-template breakpoints:
  - `FleckLayDesk` — `Desktop`
  - `FleckLayMob` — `Mobile`
- Create Home mobile breakpoint: `FleckHomeMob` — `Mobile`
- Create tokens:
  - `FleckPaper`
  - `FleckGraph`
  - `FleckViolet`
  - `FleckSage`
- Create presets:
  - `FleckNavText`
  - `FleckNavLink`

---

### Task 1: Preflight the Live Framer Project and Register the Approved Logo

**Files:**

- Read: `docs/superpowers/specs/2026-07-30-fleck-website-navigation-design.md`
- Read: `/Users/harryjin/.agents/skills/framer/projects/d0qX2IekJlwu8LZD98Js/prompt/how-projects-work.md`
- Read: `/Users/harryjin/.agents/skills/framer/projects/d0qX2IekJlwu8LZD98Js/prompt/updating-the-project.md`
- Read: `/Users/harryjin/.agents/skills/framer/projects/d0qX2IekJlwu8LZD98Js/prompt/implementation-strategy.md`
- Read: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-logo-approved.png`

**Interfaces:**

- Consumes: Connected Framer session `2`, Home page `augiA20Il`, desktop breakpoint `WQLkyLRf1`.
- Produces: Persisted Framer plugin-data key `fleck.nav.logoUrl` containing the uploaded approved logo URL, plus a confirmed empty Home tree.

- [ ] **Step 1: Verify the exact live page and confirm no competing navigation or layout template exists**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const pagePath = "/"
const [home, components, templates] = await Promise.all([
  framer.agent.serialize({ id: "augiA20Il", depth: 2 }, { pagePath }),
  framer.agent.getNodesOfTypes({ types: ["ComponentNode"] }),
  framer.agent.getNodesOfTypes({ types: ["LayoutTemplateNode"] }),
])
console.log(JSON.stringify({
  home,
  matchingComponents: components.filter(node => /fleck|nav|header/iu.test(node.name ?? "")),
  templates: templates.map(node => ({ id: node.id, name: node.name })),
}, null, 2))
'
```

Expected:

- Home is path `/`.
- `WQLkyLRf1` remains the primary desktop breakpoint.
- The breakpoint has no content children.
- No `Fleck Navigation` component or `Fleck Site Layout` template already exists.

- [ ] **Step 2: Capture the live Craft reference at a desktop viewport**

Open `https://www.craft.do/` in the Browser plugin, set a 1440 px desktop viewport, and capture the first viewport to:

```text
/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-reference-craft.png
```

Expected: the image visibly includes Craft's floating top navigation with logo left, centered links, and the right-side action. Do not use the Mobbin sign-up screen as the reference.

- [ ] **Step 3: Verify typography and exact icon names**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const [lucideIcons, lucideControls, logoIcons] = await Promise.all([
  framer.agent.readIcons({ iconSetName: "Lucide" }),
  framer.agent.readIconSetControls({ iconSetNames: ["Lucide"] }),
  framer.agent.readIcons({ iconSetName: "Logos" }),
])
console.log(JSON.stringify({
  menuIcons: lucideIcons.filter(name => name === "Menu" || name === "X"),
  lucideControls: lucideControls.Lucide,
  logosAvailable: logoIcons.length > 0,
}, null, 2))
'
```

Expected:

```text
menuIcons: ["Menu", "X"]
logosAvailable: true
```

Use the approved Fleck asset for the brand mark; the Logos catalog is requested only to satisfy Framer's logo-system context requirement.

- [ ] **Step 4: Prepare a transport-sized copy without changing the logo's pixels or proportions**

Run:

```bash
cp "/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-logo-approved.png" /tmp/fleck-nav-logo.png
sips -Z 640 /tmp/fleck-nav-logo.png
sips -g pixelWidth -g pixelHeight /tmp/fleck-nav-logo.png
```

Expected:

- The file remains PNG.
- The longest edge is 640 px.
- The image content, aspect ratio, colors, and composition are unchanged.

- [ ] **Step 5: Upload the approved logo to the connected Framer project**

Run:

```bash
FLECK_NAV_LOGO_DATA="$(base64 < /tmp/fleck-nav-logo.png | tr -d '\n')"
npx @framer/agent@latest exec -s 2 -e "
const uploaded = await framer.uploadImage({
  image: 'data:image/png;base64,${FLECK_NAV_LOGO_DATA}',
  altText: 'Fleck',
})
await framer.setPluginData('fleck.nav.logoUrl', uploaded.url)
console.log(JSON.stringify({ logoUrl: uploaded.url }))
"
```

Expected:

- A `framerusercontent.com` asset URL is returned.
- The URL is stored under `fleck.nav.logoUrl`.
- No canvas node is created yet.

- [ ] **Step 6: Re-read the persisted URL**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
console.log(JSON.stringify({
  logoUrl: await framer.getPluginData("fleck.nav.logoUrl"),
}))
'
```

Expected: the same non-empty Framer asset URL from Step 4.

**Review gate:** Reject the task if the Home page is no longer blank, if an existing navigation system was ignored, or if the uploaded image is not the approved Fleck asset.

---

### Task 2: Create Field Notes Tokens and the Desktop Navigation Component

**Files:**

- Read: `docs/superpowers/specs/2026-07-30-fleck-website-navigation-design.md`

**Interfaces:**

- Consumes: `fleck.nav.logoUrl` from Task 1.
- Produces: `FleckNavComp` with primary variant `FleckNavDeskTop`, exact navigation copy, final hash links, hover/focus/tap effects, and the desktop field-bar layout.

- [ ] **Step 1: Record the Framer design plan before the first mutation**

Use this exact plan in the implementation commentary:

```text
Category: Launch / coming-soon product website
Layout: A fixed, centered floating field bar with protected left and right zones and a visually centered link group.
Color: Warm Paper glass surface, Graphite text, Violet active marker and CTA hover, Sage reserved for later page detail.
Density: Brief essential navigation with generous spacing and no secondary utility links.
Typography:
  - IBM Plex Sans Medium at 15 px for links
  - IBM Plex Sans Medium at 14 px for the waitlist action
Sections:
  1. Desktop field bar
  2. Mobile closed header
  3. Mobile attached drawer
Visual detail strategy:
- Use a one-pixel graphite border, restrained shadow, and a short violet note-tab marker.
- Keep every animation compact and functional; avoid glow, bounce, or decorative waveforms.
Reusable systems:
- Components: one reusable Fleck Navigation component with desktop and mobile variants
- Layout Template: one Fleck Site Layout shared template applied to Home
```

- [ ] **Step 2: Create the color and typography presets**

Run one `applyChanges` call containing:

```javascript
const pagePath = "/"
const dsl = String.raw`
+ColorStyleTokenNode FleckPaper name="Fleck/Paper";
SET FleckPaper light="#F4F0E7";
+ColorStyleTokenNode FleckGraph name="Fleck/Graphite";
SET FleckGraph light="#202128";
+ColorStyleTokenNode FleckViolet name="Fleck/Violet";
SET FleckViolet light="#7257F5";
+ColorStyleTokenNode FleckSage name="Fleck/Sage";
SET FleckSage light="#B9C5B4";
+TextStylePresetNode FleckNavText name="Fleck/Nav Text" tag="p";
SET FleckNavText fontName="IBM Plex Sans" fontWeight="500" fontStyle="normal" fontSize="15px" lineHeight="20px" letterSpacing="-0.1px" textColor="var(--token-FleckGraph)";
+LinkStylePresetNode FleckNavLink name="Fleck/Nav Link";
SET FleckNavLink link.textColor="rgba(32,33,40,0.70)" link.hover.textColor="#202128" link.current.textColor="#202128" link.textDecoration="none" link.hover.textDecoration="none" link.current.textDecoration="none" link.transition="tween 0.2s 0s";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected: `Commands applied cleanly.` with no parse, command, or lint errors.

- [ ] **Step 3: Create the desktop component hierarchy**

Read `fleck.nav.logoUrl`, then apply this hierarchy using that exact URL for `FleckNavLogo fill`:

```text
FleckNavComp
└── FleckNavDeskTop (Desktop / Top)
    └── FleckNavShell
        ├── FleckNavHeaderRow
        │   ├── FleckNavBrandZone
        │   │   └── FleckNavLogo
        │   ├── FleckNavCenter
        │   │   ├── FleckNavProduct
        │   │   │   ├── FleckNavProductText
        │   │   │   └── FleckNavProductMark
        │   │   ├── FleckNavHow
        │   │   │   ├── FleckNavHowText
        │   │   │   └── FleckNavHowMark
        │   │   ├── FleckNavAgents
        │   │   │   ├── FleckNavAgentsText
        │   │   │   └── FleckNavAgentsMark
        │   │   └── FleckNavPrinciples
        │   │       ├── FleckNavPrinciplesText
        │   │       └── FleckNavPrinciplesMark
        │   ├── FleckNavActionZone
        │   │   └── FleckNavWaitlist
        │   │       └── FleckNavWaitlistText
        │   └── FleckNavMenuButton
        └── FleckNavDrawer
```

Use these exact shell attributes:

```text
FleckNavDeskTop:
  name="Desktop / Top"
  layout="stack"
  stackDirection="vertical"
  width="1184px"
  height="56px"
  overflow="clip"

FleckNavShell:
  htmlTag="nav"
  ariaLabel="Primary navigation"
  layout="stack"
  stackDirection="vertical"
  stackDistribution="start"
  stackAlignment="center"
  width="1fr"
  height="auto"
  radius="26px"
  overflow="clip"
  fill="rgba(244,240,231,0.88)"
  backgroundBlur="20px"
  border="1px solid rgba(32,33,40,0.09)"
  boxShadows.0="0px 8px 28px 0px rgba(32,33,40,0.10)"
  boxShadows.1="0px 3px 16px 0px rgba(114,87,245,0.06)"

FleckNavHeaderRow:
  layout="stack"
  stackDirection="horizontal"
  stackDistribution="space-between"
  stackAlignment="center"
  width="1fr"
  height="56px"
  padding="0px 12px 0px 18px"

FleckNavBrandZone and FleckNavActionZone:
  width="184px"
  height="44px"
  layout="stack"
  stackDirection="horizontal"
  stackAlignment="center"

FleckNavCenter:
  width="auto"
  height="44px"
  layout="stack"
  stackDirection="horizontal"
  stackAlignment="center"
  gap="28px"

Each desktop link wrapper:
  width="auto"
  height="44px"
  layout="stack"
  stackDirection="vertical"
  stackDistribution="center"
  stackAlignment="center"
  cursor="pointer"
  link.smoothScroll="true"

Each link marker:
  width="18px"
  height="2px"
  radius="1px"
  fill="#7257F5"
  opacity="0"

FleckNavProductMark:
  opacity="1"

FleckNavWaitlist:
  width="auto"
  height="36px"
  padding="0px 16px"
  radius="12px"
  fill="#202128"
  hoverEffect.backgroundColor="#7257F5"
  hoverEffect.transition="tween"
  tapEffect.scale="0.98"
  tapEffect.transition="spring-duration"
  link.href="/#waitlist"
  link.smoothScroll="true"
  link.trackingId="join-waitlist-nav"
```

Set links and labels exactly:

```text
FleckNavLogo:          /                 aria label "Fleck home"
FleckNavProduct:       /#product         "Product"
FleckNavHow:           /#how-it-works    "How it works"
FleckNavAgents:        /#agent-access    "Agent access"
FleckNavPrinciples:    /#principles      "Principles"
FleckNavWaitlist:      /#waitlist        "Join the waitlist"
```

Expected: one editable component definition with one desktop primary variant; no page or layout-template changes yet.

- [ ] **Step 4: Create the scrolled desktop variant**

Run:

```javascript
const pagePath = "/"
const dsl = String.raw`
CREATE_VARIANT FleckNavDeskScr from="FleckNavDeskTop";
SET FleckNavDeskScr name="Desktop / Scrolled" height="52px";
SET FleckNavDeskScrFleckNavShell height="52px" fill="rgba(244,240,231,0.95)" backgroundBlur="22px" boxShadows.0="0px 6px 20px 0px rgba(32,33,40,0.11)" boxShadows.1="0px 2px 12px 0px rgba(114,87,245,0.05)";
SET FleckNavDeskScrFleckNavHeaderRow height="52px";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected:

- `Desktop / Scrolled` is 52 px high.
- No child changes horizontal position.
- Surface opacity and blur increase slightly.

- [ ] **Step 5: Serialize and measure both desktop variants**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const variants = await framer.agent.serializeNodes({
  ids: ["FleckNavDeskTop", "FleckNavDeskScr"],
  depth: 3,
})
const rects = await Promise.all([
  framer.agent.getRect({ id: "FleckNavDeskTop" }),
  framer.agent.getRect({ id: "FleckNavDeskScr" }),
])
console.log(JSON.stringify({ variants, rects }, null, 2))
'
```

Expected:

- Top is `1184 × 56`.
- Scrolled is `1184 × 52`.
- Copy, font, links, protected zones, and center link order are exact.

**Review gate:** Reject the task if the navigation uses reconstructed logo shapes, a generic rounded font, a gradient border, a glow, or a page-local copy.

---

### Task 3: Add the Accessible Mobile Drawer Variants

**Files:**

- Read: `docs/superpowers/specs/2026-07-30-fleck-website-navigation-design.md`

**Interfaces:**

- Consumes: `FleckNavComp` and its primary descendants from Task 2.
- Produces: `FleckNavMobCls` and `FleckNavMobOpn`, with Lucide Menu/X controls and exact variant transitions.

- [ ] **Step 1: Add mobile-only controls and the drawer to the primary hierarchy**

Add these nodes under `FleckNavShell` before creating mobile variants:

```text
FleckNavHeaderRow
└── FleckNavMenuButton
    └── FleckNavMenuIcon (Lucide / Menu)

FleckNavDrawer
├── FleckDrawerProduct
├── FleckDrawerHow
├── FleckDrawerAgents
├── FleckDrawerPrinciples
└── FleckDrawerWaitlist
```

Desktop primary rules:

```text
FleckNavMenuButton visible="false"
FleckNavDrawer width="1fr" height="auto" visible="true"
FleckNavDeskTop height="56px" overflow="clip"
```

The drawer must remain present in the primary variant so replica variants inherit one identical drawer tree. It is hidden on desktop and mobile-closed only by the fixed root height plus clipping.

- [ ] **Step 2: Create the mobile closed variant from the desktop primary**

Run:

```javascript
const pagePath = "/"
const dsl = String.raw`
CREATE_VARIANT FleckNavMobCls from="FleckNavDeskTop";
SET FleckNavMobCls name="Mobile / Closed" width="366px" height="56px" overflow="clip";
SET FleckNavMobClsFleckNavShell width="1fr" height="auto";
SET FleckNavMobClsFleckNavHeaderRow layout="stack" stackDirection="horizontal" stackDistribution="space-between" stackAlignment="center" width="1fr" height="56px" padding="0px 8px 0px 14px";
SET FleckNavMobClsFleckNavCenter visible="false";
SET FleckNavMobClsFleckNavBrandZone width="1fr";
SET FleckNavMobClsFleckNavActionZone width="auto";
SET FleckNavMobClsFleckNavMenuButton visible="true";
SET FleckNavMobClsFleckNavWaitlistText text="Join waitlist";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected:

- Closed size is `366 × 56`.
- Logo remains left aligned.
- Compact Join waitlist action and Menu button remain right aligned.
- Drawer descendants exist but are clipped.
- Desktop links are not visible.

- [ ] **Step 3: Create the mobile open variant from mobile closed**

Run:

```javascript
const pagePath = "/"
const dsl = String.raw`
CREATE_VARIANT FleckNavMobOpn from="FleckNavMobCls";
SET FleckNavMobOpn name="Mobile / Open" height="auto";
SET FleckNavMobOpnFleckNavMenuIcon $control__icon="X";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected:

- Open inherits the exact header-row position from Closed.
- Open uses Lucide `X`.
- The complete drawer is revealed below the same header row.

- [ ] **Step 4: Wire exact open and close transitions**

Set the Menu control in `Mobile / Closed`:

```text
onTap.0.action="SET_VARIANT"
onTap.0.controls.variant="FleckNavMobOpn"
ariaLabel="Open navigation"
tabIndex="0"
```

Set the X control in `Mobile / Open`:

```text
onTap.0.action="SET_VARIANT"
onTap.0.controls.variant="FleckNavMobCls"
ariaLabel="Close navigation"
tabIndex="0"
```

Each drawer destination uses the final hash, smooth scrolling, a 48 px minimum row height, and a tap action returning the component to `FleckNavMobCls`.

- [ ] **Step 5: Verify both mobile variants**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const variants = await framer.agent.serializeNodes({
  ids: ["FleckNavMobCls", "FleckNavMobOpn"],
  depth: 5,
})
const rects = await Promise.all([
  framer.agent.getRect({ id: "FleckNavMobCls" }),
  framer.agent.getRect({ id: "FleckNavMobOpn" }),
])
console.log(JSON.stringify({ variants, rects }, null, 2))
'
```

Expected:

- Closed drawer content is clipped.
- Open drawer content is visible.
- Header-row child positions are identical in both variants.
- Menu/X controls use exact variant IDs, not cycling.
- Every mobile control is at least 44 px on its shortest interactive axis.

**Review gate:** Reject the task if the open state uses an overlay, if the closed state deletes/hides drawer children instead of clipping them, or if the logo/menu positions shift between variants.

---

### Task 4: Distribute the Navigation Through a Responsive Layout Template

**Files:**

- Modify remotely: Framer Home page `augiA20Il`
- Preserve remotely: Home primary breakpoint `WQLkyLRf1`

**Interfaces:**

- Consumes: `FleckNavComp` variants from Tasks 2–3.
- Produces: `FleckSiteLay` applied to Home, desktop/mobile layout-template breakpoints, and one Home mobile breakpoint.

- [ ] **Step 1: Create the shared layout template and desktop breakpoint**

Run one mutation:

```javascript
const pagePath = "/"
const dsl = String.raw`
+LayoutTemplateNode FleckSiteLay name="Fleck Site Layout";
+FrameNode FleckLayDesk parent="FleckSiteLay";
SET FleckLayDesk name="Desktop" fill="#F4F0E7" layout="stack" stackDirection="vertical" stackDistribution="start" stackAlignment="center" gap="0px" overflow="clip" width="1200px" minHeight="1000px";
+ComponentInstanceNode FleckNavInst component="FleckNavComp" parent="FleckLayDesk" position="0";
SET FleckNavInst name="Fleck Navigation" position="fixed" top="32px" left="24px" right="24px" width="auto" maxWidth="1184px" height="56px" zIndex="10" $control__variant="Desktop / Top";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected:

- Framer automatically creates one Placeholder child in `FleckLayDesk`.
- The nav instance sits before the Placeholder in document order.
- The nav is fixed and inset.
- No page-local navigation node is created.

- [ ] **Step 2: Add the desktop scroll-state transition**

Set the desktop nav instance:

```text
scrollVariantEffect.trigger="onScrollDirection"
scrollVariantEffect.fromVariant="FleckNavDeskTop"
scrollVariantEffect.toVariant="FleckNavDeskScr"
scrollVariantEffect.direction="down"
scrollVariantEffect.replay="true"
transition="spring-duration"
```

Also give the instance a single on-mount appearance:

```text
appearEffect.trigger="onMount"
appearEffect.enter.opacity="0"
appearEffect.enter.y="-8"
appearEffect.enter.transition="spring-duration"
appearEffect.replay="false"
```

Do not use scale or bounce. Framer's reduced-motion runtime must suppress the movement; verify that the navigation remains fully visible without the effect.

- [ ] **Step 3: Create the layout-template mobile breakpoint**

Run:

```javascript
const pagePath = "/"
const dsl = String.raw`
CREATE_VARIANT FleckLayMob from="FleckLayDesk";
SET FleckLayMob name="Mobile" width="390px" minHeight="844px";
SET FleckLayMobFleckNavInst top="12px" left="12px" right="12px" width="auto" maxWidth="366px" height="auto" $control__variant="Mobile / Closed" appearEffect.enter.y="0";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected:

- Mobile layout width is 390 px.
- Nav is inset 12 px on both sides.
- The one inherited instance selects `Mobile / Closed`.
- No second instance is created.

- [ ] **Step 4: Apply the template and add Home's mobile breakpoint**

Run:

```javascript
const pagePath = "/"
const dsl = String.raw`
SET augiA20Il layoutTemplate="FleckSiteLay";
CREATE_VARIANT FleckHomeMob from="WQLkyLRf1";
SET FleckHomeMob name="Mobile" width="390px" minHeight="844px";
`
console.log(await framer.agent.applyChanges(dsl, { pagePath }))
```

Expected:

- Home uses `Fleck Site Layout`.
- The original desktop breakpoint remains primary.
- The new mobile breakpoint is a replica, not an independent page.
- Home content remains blank.

- [ ] **Step 5: Verify the final Framer tree and exact hashes**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const pagePath = "/"
const [home, template, component, links] = await Promise.all([
  framer.agent.serialize({ id: "augiA20Il", depth: 2 }, { pagePath }),
  framer.agent.serialize({ id: "FleckSiteLay", depth: 4 }, { pagePath }),
  framer.agent.serialize({ id: "FleckNavComp", depth: 5 }),
  framer.agent.getDescendantsOfTypes({
    id: "FleckNavComp",
    types: ["FrameNode", "RichTextNode"],
  }),
])
console.log(JSON.stringify({
  home,
  template,
  component,
  hrefs: links
    .map(node => node.attributes?.link?.href)
    .filter(Boolean),
}, null, 2))
'
```

Expected hash set:

```json
[
  "/",
  "/#product",
  "/#how-it-works",
  "/#agent-access",
  "/#principles",
  "/#waitlist"
]
```

Duplicates are allowed because desktop and drawer controls share destinations; unexpected destinations are not.

**Review gate:** Reject the task if the navigation is page-local, if a second mobile instance exists, if Home content was added, or if the Design Overview changed.

---

### Task 5: Visual, Responsive, Interaction, and Accessibility QA

**Files:**

- Create: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-desktop.png`
- Create: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-mobile-closed.png`
- Create: `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-mobile-open.png`

**Interfaces:**

- Consumes: Final Framer component, template, and Home breakpoints.
- Produces: Three visual evidence images and a clean diagnostic/readback report.

- [ ] **Step 1: Capture desktop, mobile closed, and mobile open screenshots**

Use Framer's screenshot read on:

```text
WQLkyLRf1      → fleck-nav-desktop.png
FleckHomeMob   → fleck-nav-mobile-closed.png
FleckNavMobOpn → fleck-nav-mobile-open.png
```

Save each returned image to its exact evidence path.

Expected:

- Desktop field bar is centered, inset, and visually calm.
- Mobile closed shows logo, Join waitlist, and Menu with no drawer leakage.
- Mobile open keeps the same header row and reveals the attached drawer.

- [ ] **Step 2: Compare the reference and Fleck result side by side**

Create one comparison image containing:

1. `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-nav-reference-craft.png`.
2. `fleck-nav-desktop.png`.
3. The Fleck Design Overview screenshot at `/Users/harryjin/.codex/visualizations/2026/07/27/019fa2df-415f-7021-b22c-6d17a88ca9b9/fleck-framer-design-overview.jpg`.

Review:

- Structural relationship matches Craft: brand left, links centered, action right.
- Fleck styling matches Field Notes: Paper, Graphite, Violet, IBM Plex Sans.
- The center group is visually centered, not merely mathematically centered inside leftover space.
- Logo crop shows the complete approved symbol and wordmark.
- No border, shadow, radius, or blur feels heavier than the reference.

If a mismatch is visible, adjust only the affected Framer attributes and recapture all impacted screenshots.

- [ ] **Step 3: Verify interaction and accessibility properties by serialization**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const ids = [
  "FleckNavShell",
  "FleckNavLogo",
  "FleckNavProduct",
  "FleckNavHow",
  "FleckNavAgents",
  "FleckNavPrinciples",
  "FleckNavWaitlist",
  "FleckNavMenuButton",
  "FleckNavDrawer",
]
const nodes = await framer.agent.serializeNodes({
  ids,
  depth: 2,
  attributeFilter: [
    "ariaLabel",
    "htmlTag",
    "tabIndex",
    "link",
    "hoverEffect",
    "tapEffect",
    "visible",
    "$rect",
  ],
})
console.log(JSON.stringify(nodes, null, 2))
'
```

Expected:

- Navigation has `htmlTag="nav"` and `ariaLabel="Primary navigation"`.
- Logo has accessible name `Fleck home`.
- Menu and close controls have distinct accessible names.
- All links use final hashes and smooth scrolling.
- Mobile interactive targets meet the 44 px minimum.
- CTA hover and focus remain legible.
- No state depends only on color; the active note tab supplements text contrast.

- [ ] **Step 4: Run final scope and diagnostic checks**

Run:

```bash
npx @framer/agent@latest exec -s 2 -e '
const pagePath = "/"
const [home, overview, templates, components] = await Promise.all([
  framer.agent.serialize({ id: "augiA20Il", depth: 2 }, { pagePath }),
  framer.agent.serialize({ id: "Ec7XexWow", depth: 1 }),
  framer.agent.getNodesOfTypes({ types: ["LayoutTemplateNode"] }),
  framer.agent.getNodesOfTypes({ types: ["ComponentNode"] }),
])
console.log(JSON.stringify({
  home,
  overviewId: overview.id,
  fleckTemplates: templates.filter(node => node.name === "Fleck Site Layout"),
  fleckComponents: components.filter(node => node.name === "Fleck Navigation"),
}, null, 2))
'
```

Expected:

- Exactly one `Fleck Site Layout`.
- Exactly one `Fleck Navigation`.
- Home remains otherwise blank.
- Design Overview ID remains `Ec7XexWow`.
- Latest mutation result contains no meaningful diagnostics.
- The project remains unpublished.

- [ ] **Step 5: Record the known section-integration boundary**

The handoff must state:

```text
The navigation uses the final Product, How it works, Agent access, Principles, and Waitlist hashes. The Home page is intentionally still blank, so end-to-end scroll landing and section-aware active-marker movement will be verified when those sections are built. No empty placeholder sections were added.
```

**Final review gate:** Do not claim full landing-page navigation completion until the later section-build plan supplies and verifies the five target IDs. It is accurate to claim the responsive navigation component and layout-template integration are complete.
