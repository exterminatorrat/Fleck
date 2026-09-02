# Fleck Website Hero Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the approved white Fleck navigation and integrate the recorded synthetic Fleck states into one scroll-driven hero that explains the human-to-agent-to-Fleck loop.

**Architecture:** Keep the React 19 and Vite 8 site. A small pure state mapper defines the storyboard thresholds, one `HeroStory` component renders the semantic states and owns a single GSAP ScrollTrigger on desktop, and plain CSS presents the sticky scene plus normal-flow mobile and reduced-motion fallbacks. Authentic Fleck states use the recorded media; the fictional Codex bridge is a plainly labeled DOM transcript rather than a fake screenshot.

**Tech Stack:** React 19, Vite 8, GSAP ScrollTrigger, native HTML media, plain CSS, Node test runner

**Spec:** `/Users/harryjin/Fleck/docs/superpowers/specs/2026-08-29-fleck-website-hero-design.md`

## Global Constraints

- Explicit later user direction supersedes the draft spec's wallpaper clause: the page and desktop background are completely white, with no hero background image and no ImageGen asset.
- Preserve the approved Fleck brand, expanding glass menu, placeholder links, and Download for Mac action from `/Users/harryjin/Fleck/website/` without redesigning them.
- Desktop uses a `420svh` outer story with a sticky `100svh` stage and native page scrolling. Do not smooth, snap, or hijack the wheel.
- Story bands are: intro 0-14%, shortcut 14-25%, capture 25-48%, Codex retrieval 48-68%, agent write-back 68-90%, close 90-100%.
- Use real Fleck recordings and stills for Fleck product states. Do not construct a fake Fleck screenshot with CSS.
- Use the exact copy from the design spec. Do not add badges, section numbers, scroll cues, test-passing claims, completion metadata, or private data.
- The fictional Codex bridge must be clearly labeled `Codex demo` and use only Northstar Demo synthetic content.
- Phone layouts at 767px and below and reduced-motion layouts use normal vertical flow, not a shrunken pinned desktop.
- Keep the disabled download behavior until `VITE_APP_STORE_URL` is supplied.
- Do not change native Fleck source, the capture lab, worker behavior, hosting configuration, or any homepage section after this hero.
- Do not push, open a pull request, merge, publish, or deploy.

---

### Task 1: Establish the Approved Navigation Baseline

**Files:**
- Modify: `website/src/App.jsx`
- Modify: `website/src/Navigation.jsx`
- Create: `website/src/Navigation.test.js`
- Modify: `website/src/styles.css`
- Modify: `website/src/main.jsx`
- Modify: `website/index.html`
- Modify: `website/package.json`
- Modify: `website/package-lock.json`

**Interfaces:**
- Consumes: the user-approved, uncommitted website files under `/Users/harryjin/Fleck/website/`.
- Produces: the same navigation markup, accessibility behavior, styling, metadata, and blank white content baseline in the isolated worktree.

- [ ] **Step 1: Add the approved navigation behavior test first**

  Copy only `/Users/harryjin/Fleck/website/src/Navigation.test.js` into the worktree test path. It asserts the menu disclosure contract, disabled placeholders, Home link, and Download for Mac link.

- [ ] **Step 2: Run the focused test and verify RED**

  Run: `node --test src/Navigation.test.js` from `website/`.

  Expected: FAIL because the old navigation lacks the approved menu disclosure contract.

- [ ] **Step 3: Transplant only the approved navigation baseline**

  Reproduce the current contents of the eight listed files from `/Users/harryjin/Fleck/website/` in the isolated worktree. Use `apply_patch` for text edits. Do not touch the main checkout and do not delete unrelated legacy files in the worktree.

- [ ] **Step 4: Verify GREEN**

  Run: `npm ci && npm test && npm run build` from `website/`.

  Expected: the navigation test and worker test pass, then Vite builds successfully. Existing package-manager audit/install-script notices are environmental evidence, not a reason to mutate dependencies.

- [ ] **Step 5: Commit**

  Commit message: `feat: preserve approved website navigation`

---

### Task 2: Integrate the Recorded Scroll-Driven Hero

**Files:**
- Create: `website/src/heroStates.js`
- Create: `website/src/heroStates.test.js`
- Create: `website/src/HeroStory.jsx`
- Create: `website/src/HeroStory.test.js`
- Modify: `website/src/App.jsx`
- Modify: `website/src/styles.css`
- Modify: `website/package.json`
- Modify: `website/package-lock.json`
- Create: `website/public/hero/fleck-northstar-open.png`
- Create: `website/public/hero/fleck-northstar-saved.png`
- Create: `website/public/hero/fleck-agent-writeback.png`
- Create: `website/public/hero/capsule-listening.mp4`
- Create: `website/public/hero/capsule-listening.webm`
- Create: `website/public/hero/capsule-processing.mp4`
- Create: `website/public/hero/capsule-processing.webm`
- Create: `website/public/hero/capsule-saved.mp4`
- Create: `website/public/hero/capsule-saved.webm`
- Create: `website/public/hero/agent-writeback.mp4`
- Create: `website/public/hero/agent-writeback.webm`

**Interfaces:**
- Consumes: `downloadProps` from `App`, the approved `Navigation`, and the accepted media under `.build/fleck-capture-lab/fleck-demo.ylWvga/Captures/`.
- Produces: `heroStateForProgress(progress)` and one accessible `HeroStory({ downloadProps })` component whose root exposes `data-hero-state` during desktop scroll.

- [ ] **Step 1: Write the failing state-mapping test**

  Add literal assertions proving boundary behavior for `intro`, `shortcut`, `listening`, `processing`, `saved`, `memory`, `codex`, `writeback`, and `close`, including clamping values below 0 and above 1.

- [ ] **Step 2: Run the mapper test and verify RED**

  Run: `node --test src/heroStates.test.js` from `website/`.

  Expected: FAIL because `heroStates.js` does not exist.

- [ ] **Step 3: Implement the minimal pure mapper and verify GREEN**

  Use these boundaries: `<0.14 intro`, `<0.25 shortcut`, `<0.33 listening`, `<0.40 processing`, `<0.44 saved`, `<0.48 memory`, `<0.68 codex`, `<0.90 writeback`, otherwise `close`.

  Re-run: `node --test src/heroStates.test.js`.

- [ ] **Step 4: Write the failing semantic hero rendering test**

  Server-render `HeroStory` and assert the exact headline, support line, closing line, Right Option label, Northstar dictation, `Pick up where I left off.`, `Do it.`, `Codex demo`, actual media paths, and absence of `Completed by Codex` and `Tests passing`.

- [ ] **Step 5: Run the rendering test and verify RED**

  Run: `node --test src/HeroStory.test.js` from `website/`.

  Expected: FAIL because `HeroStory.jsx` does not exist.

- [ ] **Step 6: Copy only accepted media and implement the hero**

  Copy the three accepted stills and eight optimized video files named in `Files` from the capture directory. Implement one GSAP ScrollTrigger that maps desktop progress to the root `data-hero-state` without React state on scroll frames. On state changes, play only the active short video and pause the rest. Clean up ScrollTrigger, media listeners, and media-query listeners. Keep mobile and reduced-motion content in document flow.

- [ ] **Step 7: Add the responsive visual system**

  Retain the approved navigation styles, add the full-width macOS mini bar immediately below it, keep the backdrop exactly white, use real Fleck captures at a non-upscaled size, render the fictional Codex transcript without fake browser chrome, and provide explicit 1440x900 and 390x844 layouts. Animate only opacity and transform. Keep visible focus states and contrast.

  Later user-approved correction: the simulated macOS mini bar requirement above is superseded. Remove it entirely so the hero begins directly below the fixed website navigation, with no fake OS chrome or blank band.

- [ ] **Step 8: Verify GREEN and build**

  Update the test script, install a pinned GSAP version through npm, then run `npm test && npm run build` from `website/`.

  Expected: all website tests pass and Vite builds successfully.

- [ ] **Step 9: Self-review and commit**

  Re-read every visible string, scan for em-dash characters, confirm no unapproved claim or real user data, review the full diff, then commit with message: `feat: integrate Fleck hero product story`
