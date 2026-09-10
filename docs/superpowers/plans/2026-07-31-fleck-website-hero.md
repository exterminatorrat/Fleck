# Fleck Website Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce the approved Fleck header and interactive brain hero as the website's only viewport, then validate and publish it through Sites.

**Architecture:** Keep the existing React and Vite application. Render the semantic header and hero in `App.jsx`, isolate continuous canvas work in one `BrainHologram.jsx` leaf, and own the full responsive visual system in `styles.css`. Use no new runtime dependency.

**Tech Stack:** React 19, Vite 8, native Canvas 2D, CSS, Sites hosting

## Global Constraints

- Accepted concept: `${PRIVATE_EVIDENCE_ROOT}/generated_images/019fb779-8096-70d1-a4d7-a606fd4b86cd/exec-c9f5646d-84da-48ef-9295-f7cea729de6e.png`.
- Implement only the header and first hero viewport.
- Do not add content below the hero.
- Preserve the exact approved copy and compact T3 Code-like scale.
- Add no runtime dependency.
- Use `VITE_APP_STORE_URL` only when provided; never invent a store URL.
- Use the repository GitHub remote for `View on GitHub`.
- Honor reduced motion and support pointer and touch interaction.

---

### Task 1: Replace the Existing Header and Hero Markup

**Files:**
- Modify: `website/src/App.jsx`
- Modify: `website/src/Navigation.jsx`
- Modify: `website/index.html`

**Interfaces:**
- Consumes: `VITE_APP_STORE_URL` and the existing `/fleck-mark.png` asset.
- Produces: semantic `Navigation` and `Hero` composition with exact approved copy.

- [ ] Replace the old navigation links and waitlist action with the approved brand and download action.
- [ ] Render the approved headline, motto, supporting paragraph, primary download action, and GitHub source action.
- [ ] Use one shared download-link helper state so both download actions behave consistently.
- [ ] Update document metadata and theme color to the approved white hero.
- [ ] Verify the visible copy with `rg` and review the rendered DOM.

### Task 2: Build the Interactive Brain Hologram

**Files:**
- Create: `website/src/BrainHologram.jsx`
- Modify: `website/src/App.jsx`

**Interfaces:**
- Consumes: viewport size, pointer/touch coordinates, and reduced-motion preference.
- Produces: one decorative `<canvas className="brain-hologram" aria-hidden="true" />`.

- [ ] Generate deterministic nodes inside two ellipse-based hemispheres with a protected center opening.
- [ ] Precompute local edges and signal paths after each resize.
- [ ] Render graphite nodes, faint local edges, curved contour paths, and violet signals.
- [ ] Apply local pointer/touch deformation outside React state.
- [ ] Add ambient motion, device-pixel-ratio scaling, resize handling, and strict cleanup.
- [ ] Freeze the animation when reduced motion is active.

### Task 3: Match the Approved Responsive Visual System

**Files:**
- Modify: `website/src/styles.css`
- Modify: `website/src/main.jsx`

**Interfaces:**
- Consumes: the semantic class names from Tasks 1 and 2.
- Produces: the approved 1586 x 992 composition and phone-safe responsive collapse.

- [ ] Replace the old glass navigation styles with the white canvas design tokens.
- [ ] Match the approved header, hero type scale, action sizes, spacing, and z-order.
- [ ] Add visible hover, focus, press, unavailable, and reduced-motion states.
- [ ] Add explicit tablet and mobile rules that keep the first viewport usable without overflow.
- [ ] Remove unused font weights and obsolete navigation selectors.

### Task 4: Validate Fidelity and Publish

**Files:**
- Modify: `website/.openai/hosting.json` only when Sites creates the project.

**Interfaces:**
- Consumes: the completed website build.
- Produces: fresh build evidence, desktop/mobile render evidence, and a private Sites URL.

- [ ] Run `npm run build` in `website` and fix any failure.
- [ ] Start the existing Vite development server and capture a 1586 x 992 screenshot.
- [ ] Capture a phone-sized screenshot and verify no clipping or horizontal overflow.
- [ ] Use `view_image` on the accepted concept and latest desktop screenshot in the same QA pass.
- [ ] Check copy, layout, typography, palette, hologram, actions, responsiveness, and interaction against the spec.
- [ ] Publish the validated build with Sites and wait for deployment success.
- [ ] Open the deployed URL and report it as the primary deliverable.

