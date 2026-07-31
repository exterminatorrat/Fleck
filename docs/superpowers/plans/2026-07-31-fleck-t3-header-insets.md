# Fleck T3 Header Insets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match Fleck's header placement to T3 Code's compact inset geometry and recolor both Mac download buttons with Fleck's violet accent.

**Architecture:** Keep the existing React structure unchanged and implement the approved refinement entirely in `website/src/styles.css`. Use one centered CSS rail for header geometry and existing shared button classes for the accent treatment.

**Tech Stack:** React 19, Vite 8, CSS, Node test runner, Browser/IAB visual QA

## Global Constraints

- At a 1280px desktop viewport, place header controls 52px from each side and 12px from the top.
- Center the header rail on wider viewports.
- Keep the header transparent with no bar, divider, blur, or shadow.
- Preserve the current logo, typography, control dimensions, links, copy, GitHub treatment, and brain hologram.
- Use the light-violet Fleck accent with white text for both Mac download buttons.
- At mobile widths, use a 20px side inset and compact top spacing.

---

### Task 1: Refine header rail and download button color

**Files:**
- Modify: `website/src/styles.css`

**Interfaces:**
- Consumes: existing `.site-header`, `.navigation`, `.download-link-header`, and `.download-link-primary` class names.
- Produces: responsive CSS geometry and shared violet button styling; no JavaScript or component API changes.

- [ ] **Step 1: Record the current verification baseline**

Run: `cd website && npm test && npm run build`

Expected: 2 tests pass and Vite exits successfully. In the live/reference CSS at 1280px, `.navigation` begins near x=38/y=38 and both buttons still use their existing white/graphite treatments.

- [ ] **Step 2: Implement the minimal CSS refinement**

Replace the current header padding and full-width navigation rules with:

```css
.site-header {
  position: absolute;
  z-index: 3;
  inset: 0 0 auto;
  padding-top: 12px;
  pointer-events: none;
}

.navigation {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: min(calc(100% - 104px), 1176px);
  margin-inline: auto;
}
```

Set the shared accent token and both button variants to the approved violet treatment:

```css
:root {
  --violet: #7457f6;
}

.download-link-header {
  border-color: var(--violet);
  background: var(--violet);
  color: #ffffff;
}

.download-link-header:hover,
.download-link-primary:hover {
  border-color: #5d43d8;
  background: #5d43d8;
}

.download-link-primary {
  border-color: var(--violet);
  background: var(--violet);
  box-shadow: 0 12px 28px rgba(103, 73, 255, 0.18);
}
```

Update the existing mobile header rules to retain `padding-top: 12px` and set `.navigation` to `width: calc(100% - 40px)`.

- [ ] **Step 3: Run functional verification**

Run: `cd website && npm test && npm run build`

Expected: 2 tests pass and Vite exits successfully with a production bundle.

- [ ] **Step 4: Verify desktop and mobile fidelity**

Run the existing Vite development server and inspect the page in Browser/IAB at 1280px desktop and 390px mobile widths.

Expected desktop geometry: `.navigation` x=52, y=12, width=1176; header button remains 36px high. Expected mobile geometry: `.navigation` x=20 with no overflow. Both Mac download buttons use `rgb(116, 87, 246)` with white text, all approved above-the-fold copy is unchanged, and the GitHub action and hologram remain unchanged.

- [ ] **Step 5: Commit the validated source**

```bash
git add website/src/styles.css
git commit -m "refine Fleck header spacing and CTA color"
```

### Task 2: Publish the existing private site

**Files:**
- No source changes expected after the validated commit.

**Interfaces:**
- Consumes: the successful production build and existing `website/.openai/hosting.json` project binding.
- Produces: a new private Sites deployment at the existing Fleck URL.

- [ ] **Step 1: Package and save the validated site version**

Use the Sites packaging helper against `website/`, save one version using the validated commit SHA, and preserve the existing private project.

- [ ] **Step 2: Deploy and verify**

Deploy the saved version privately, poll until the deployment reports `succeeded`, then open the returned URL in Codex.

Expected: the existing Fleck Sites URL serves the new header rail and violet buttons.
