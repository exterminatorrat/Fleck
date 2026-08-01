# Capture Through Finish Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved capture-to-finish homepage chapter using Fleck's genuine app capture and no fabricated product UI.

**Architecture:** A static content module defines the four stages, a focused React component renders the ordered story and one-shot reveal, and the existing stylesheet supplies the editorial two-column composition. The current sanitized Fleck capture is reused as the only product UI asset.

**Tech Stack:** React 19, CSS, Intersection Observer, Node test runner, Vite.

## Global Constraints

- Add only the capture-through-finish section.
- Preserve the hero and existing Ideas section.
- Reuse the real Fleck capture at `/assets/fleck-ideas-capture.png`.
- Do not recreate Fleck windows, controls, agent cards, or activity views in HTML.
- Add no dependency.
- Motion plays once and is fully static under reduced motion.
- Mobile has no horizontal overflow.

---

### Task 1: Add the ordered journey contract

**Files:**
- Create: `website/src/journeyContent.js`
- Create: `website/src/journeyContent.test.js`
- Modify: `website/package.json`

**Interfaces:**
- Produces: `JOURNEY_STAGES` and `JOURNEY_CAPTURE_ASSET`.

- [ ] **Step 1: Write the failing contract test**

Assert the four stage IDs, labels, descriptions, and the existing capture path.

- [ ] **Step 2: Run the focused test and confirm RED**

Run `node --test src/journeyContent.test.js`; expect the missing module failure.

- [ ] **Step 3: Add the minimal static content module**

Export the four approved stages and `/assets/fleck-ideas-capture.png`.

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run `node --test src/journeyContent.test.js`; expect one passing test.

### Task 2: Build the semantic section

**Files:**
- Create: `website/src/JourneySection.jsx`
- Modify: `website/src/App.jsx`
- Modify: `website/src/styles.css`

**Interfaces:**
- Consumes: `JOURNEY_STAGES` and `JOURNEY_CAPTURE_ASSET`.
- Produces: the `JourneySection` rendered directly after `IdeasSection`.

- [ ] **Step 1: Render the heading, ordered stage rail, and real capture**

Keep editorial workflow facts visibly outside the product image and avoid any
invented product controls.

- [ ] **Step 2: Add the one-shot reveal**

Reuse the Ideas section's native Intersection Observer pattern without adding
an animation dependency.

- [ ] **Step 3: Add desktop, mobile, and reduced-motion styles**

Use the existing page insets and tokens. Confirm the product image is not
stretched beyond 650 px.

- [ ] **Step 4: Insert the section after the problem narrative**

Import and render `JourneySection` after `IdeasSection` without touching hero
or problem-section markup.

### Task 3: Verify and publish

**Files:**
- Modify: `website/design-qa.md`
- Create: `website/design-qa-journey-desktop.png`
- Create: `website/design-qa-journey-mobile.png`

- [ ] **Step 1: Run browser design QA**

Compare the locked full-page reference with desktop and 390 px captures. Fix
P0-P2 issues and record `final result: passed` only after the comparison passes.

- [ ] **Step 2: Run the full validation set**

Run `npm test`, `npm run build`, and `git diff --check`; require zero failures.

- [ ] **Step 3: Commit and publish the exact revision**

Publish the verified revision to the existing Fleck Sites project and wait for
the production deployment to succeed.
