# Ideas Arrive Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved four-stage “Ideas arrive before your tools are ready” narrative below the hero, ending with a sanitized capture from the real Fleck macOS app.

**Architecture:** A static content module defines the ordered story, `IdeasSection.jsx` renders an accessible timeline and owns a one-shot Intersection Observer reveal, and existing CSS supplies the responsive editorial diagram. The only Fleck product visual is a runtime screenshot captured from a dedicated testing tab; the website does not recreate Fleck UI.

**Tech Stack:** React 19, Canvas-free HTML/CSS editorial graphics, Intersection Observer, Node test runner, Vite, the native Fleck macOS application.

## Global Constraints

- Build only the first section below the hero; do not build the later product-demo sections.
- Use the approved heading and body copy verbatim.
- End with a compact Fleck reveal after three editorial problem rows.
- Any visible Fleck interface must come from the real app runtime in a testing tab to the right of the protected personal tab.
- Never substitute generated, traced, or HTML-recreated Fleck UI.
- Preserve the existing hero and navigation.
- Use no new dependency.
- Motion plays once, never scrubs or traps scrolling, and becomes fully static under reduced motion.
- Desktop content is at most 1180 px wide; the 760 px breakpoint becomes single-column with no horizontal overflow.

---

### Task 1: Capture the genuine Fleck resolution state

**Files:**
- Create: `website/public/assets/fleck-ideas-capture.png`

**Interfaces:**
- Consumes: the current locally built Fleck macOS app and a dedicated non-leftmost testing tab.
- Produces: a sanitized PNG crop showing the real Fleck state for the final timeline row.

- [ ] **Step 1: Build and open the real app**

Run from the repository root:

```bash
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

Expected: the build succeeds and the Fleck menu-bar app can be opened. A build
alone is not acceptance evidence; the live interface must be visible.

- [ ] **Step 2: Prepare safe demo content**

Open a dedicated testing tab to the right of the protected leftmost personal
tab. Do not open, edit, or expose the leftmost tab. In the testing tab, capture
this deliberate demo thought through Fleck's actual dictation/editor surface:

```text
Maybe update onboarding so it explains agent access, then ask Codex to finish the checklist.
```

Expected: the real app displays the captured thought without personal notes,
credentials, or unrelated tabs in view.

- [ ] **Step 3: Save a sanitized product crop**

Capture only the relevant Fleck surface and save the crop as:

```text
website/public/assets/fleck-ideas-capture.png
```

The asset must retain enough real window chrome and typography to be visibly
authentic, while excluding the menu bar, personal content, and unrelated tabs.
If live capture is blocked, stop and report the blocker instead of creating a
replacement image.

- [ ] **Step 4: Verify the asset**

Inspect the PNG at original resolution. Confirm it contains the exact demo
thought, contains no private content, and is a crop from the live app rather
than a mockup.

---

### Task 2: Add the tested story model and section component

**Files:**
- Create: `website/src/ideasContent.js`
- Create: `website/src/ideasContent.test.js`
- Create: `website/src/IdeasSection.jsx`
- Modify: `website/package.json`
- Modify: `website/src/App.jsx`
- Modify: `website/src/styles.css`

**Interfaces:**
- Consumes: `/assets/fleck-ideas-capture.png` from Task 1.
- Produces: `IDEA_STAGES`, `FLECK_CAPTURE_ASSET`, and a default `IdeasSection` React component rendered immediately after the hero.

- [ ] **Step 1: Write the failing story-contract test**

Create `website/src/ideasContent.test.js`:

```js
import assert from "node:assert/strict";
import test from "node:test";
import { FLECK_CAPTURE_ASSET, IDEA_STAGES } from "./ideasContent.js";

test("defines the approved idea-loss story in order", () => {
  assert.deepEqual(
    IDEA_STAGES.map(({ id, label }) => [id, label]),
    [
      ["spark", "A spark of an idea"],
      ["capture", "You try to capture it"],
      ["handoff", "Copy, paste, repeat"],
      ["fleck", "Fleck catches it and keeps it whole"],
    ],
  );
  assert.equal(FLECK_CAPTURE_ASSET, "/assets/fleck-ideas-capture.png");
});
```

Add `src/ideasContent.test.js` to the existing `test` script in
`website/package.json`:

```json
"test": "node --test src/ideasContent.test.js worker/index.test.js"
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run from `website/`:

```bash
node --test src/ideasContent.test.js
```

Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `ideasContent.js`.

- [ ] **Step 3: Add the minimal story data**

Create `website/src/ideasContent.js`:

```js
export const FLECK_CAPTURE_ASSET = "/assets/fleck-ideas-capture.png";

export const IDEA_STAGES = [
  { id: "spark", label: "A spark of an idea" },
  { id: "capture", label: "You try to capture it" },
  { id: "handoff", label: "Copy, paste, repeat" },
  { id: "fleck", label: "Fleck catches it and keeps it whole" },
];
```

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run from `website/`:

```bash
node --test src/ideasContent.test.js
```

Expected: 1 test passes, 0 fail.

- [ ] **Step 5: Implement the semantic one-shot section**

Create `website/src/IdeasSection.jsx`:

```jsx
import { useLayoutEffect, useRef, useState } from "react";
import { FLECK_CAPTURE_ASSET, IDEA_STAGES } from "./ideasContent";

const THOUGHT =
  "Maybe update onboarding so it explains agent access, then ask Codex to finish the checklist.";
const WAVEFORM = [10, 18, 25, 14, 31, 22, 38, 17, 28, 34, 19, 27, 15, 23, 12, 18];

function Waveform() {
  return (
    <span className="idea-waveform" aria-hidden="true">
      {WAVEFORM.map((height, index) => (
        <i key={`${height}-${index}`} style={{ "--bar-height": `${height}px` }} />
      ))}
    </span>
  );
}

function StageVisual({ id }) {
  if (id === "spark") {
    return (
      <div className="idea-spark-visual">
        <span className="idea-time">00:00</span>
        <Waveform />
        <p>{THOUGHT}</p>
        <span className="idea-loss">fades</span>
      </div>
    );
  }

  if (id === "capture") {
    return (
      <div className="idea-capture-visual">
        <p>{THOUGHT}</p>
        <span className="idea-time">00:07</span>
        <span className="idea-loss">gets cut off</span>
      </div>
    );
  }

  if (id === "handoff") {
    return (
      <div className="idea-handoff-visual" aria-label="Notes, ChatGPT, then Codex">
        {["Notes", "ChatGPT", "Codex"].map((tool, index) => (
          <span className="idea-handoff-step" key={tool}>
            {index > 0 && <i aria-hidden="true">→</i>}
            <b>{tool}</b>
          </span>
        ))}
        <span className="idea-loss">context is lost</span>
      </div>
    );
  }

  return (
    <figure className="idea-fleck-visual">
      <img
        src={FLECK_CAPTURE_ASSET}
        alt="Fleck note containing the captured onboarding thought"
        loading="lazy"
      />
    </figure>
  );
}

export default function IdeasSection() {
  const sectionRef = useRef(null);
  const [animatable, setAnimatable] = useState(false);
  const [visible, setVisible] = useState(false);

  useLayoutEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reducedMotion.matches || !("IntersectionObserver" in window)) {
      setVisible(true);
      return undefined;
    }

    setAnimatable(true);
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        setVisible(true);
        observer.disconnect();
      },
      { threshold: 0.2 },
    );
    observer.observe(sectionRef.current);
    return () => observer.disconnect();
  }, []);

  const className = [
    "ideas-section",
    animatable && "is-animatable",
    visible && "is-visible",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <section ref={sectionRef} className={className} aria-labelledby="ideas-title">
      <div className="ideas-shell">
        <header className="ideas-intro">
          <h2 id="ideas-title">Ideas arrive before your tools are ready.</h2>
          <p>
            Ideas flash by quickly. Even when you catch one, turning it into
            something useful usually means describing it again, cleaning it up,
            copying it somewhere else, and re-explaining the context to an AI agent.
          </p>
        </header>

        <ol className="idea-timeline">
          {IDEA_STAGES.map((stage, index) => (
            <li key={stage.id} className={`idea-stage idea-stage-${stage.id}`} style={{ "--step": index }}>
              <div className="idea-stage-label">
                <span className="idea-node" aria-hidden="true" />
                <p>{stage.label}</p>
              </div>
              <StageVisual id={stage.id} />
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
```

The default markup is fully visible; only `is-animatable` prepares hidden
states, ensuring no-JavaScript and unsupported-browser rendering stays complete.

- [ ] **Step 6: Insert the section after the hero**

In `website/src/App.jsx`, import `IdeasSection` and render it directly after the
closing hero `</section>`:

```jsx
import IdeasSection from "./IdeasSection";

// Inside <main>, directly after the hero section:
<IdeasSection />
```

Do not change the hero's text, controls, or brain.

- [ ] **Step 7: Add the approved layout and motion**

In `website/src/styles.css`, change `body` from `overflow: hidden` to
`overflow-x: hidden`, then add the following section styles before the existing
responsive rules:

```css
.ideas-section {
  position: relative;
  overflow: hidden;
  padding: 164px 0 172px;
  background: #ffffff;
}

.ideas-shell {
  width: min(calc(100% - 104px), 1180px);
  margin-inline: auto;
}

.ideas-intro {
  display: grid;
  grid-template-columns: minmax(0, 560px) minmax(280px, 480px);
  justify-content: space-between;
  gap: 72px;
}

.ideas-intro h2 {
  margin: 0;
  color: var(--graphite);
  font-size: clamp(42px, 4vw, 64px);
  font-weight: 600;
  letter-spacing: -0.048em;
  line-height: 1.02;
  text-wrap: balance;
}

.ideas-intro > p {
  align-self: end;
  max-width: 480px;
  margin: 0 0 5px;
  color: var(--muted);
  font-size: 17px;
  line-height: 1.55;
}

.idea-timeline {
  position: relative;
  padding: 0;
  margin: 112px 0 0;
  list-style: none;
}

.idea-timeline::before {
  position: absolute;
  z-index: 1;
  top: 0;
  bottom: 0;
  left: 224px;
  width: 1px;
  background: linear-gradient(180deg, transparent, rgba(116, 87, 246, 0.72) 9%, rgba(116, 87, 246, 0.32) 91%, transparent);
  content: "";
  transform-origin: top;
}

.idea-stage {
  position: relative;
  display: grid;
  align-items: center;
  min-height: 132px;
  grid-template-columns: 190px minmax(0, 1fr);
  gap: 68px;
  border-top: 1px solid #ececf1;
}

.idea-stage:last-child {
  min-height: 188px;
  border-bottom: 1px solid #ececf1;
}

.idea-stage-label {
  position: relative;
  z-index: 2;
  display: flex;
  align-items: center;
  min-height: 100%;
}

.idea-stage-label p {
  max-width: 150px;
  margin: 0;
  color: #464a54;
  font-size: 14px;
  font-weight: 500;
  line-height: 1.3;
}

.idea-node {
  position: absolute;
  top: 50%;
  right: -42px;
  width: 9px;
  height: 9px;
  border: 2px solid #ffffff;
  border-radius: 50%;
  background: var(--violet);
  box-shadow: 0 0 0 5px rgba(116, 87, 246, 0.09), 0 0 22px rgba(116, 87, 246, 0.48);
  transform: translateY(-50%);
}

.idea-spark-visual,
.idea-capture-visual,
.idea-handoff-visual {
  display: flex;
  align-items: center;
  min-width: 0;
  gap: 18px;
}

.idea-spark-visual p,
.idea-capture-visual p {
  max-width: 410px;
  margin: 0;
  color: #3d414b;
  font-size: 14px;
  line-height: 1.45;
}

.idea-time,
.idea-loss {
  flex: none;
  color: #a1a4ad;
  font-size: 11px;
  letter-spacing: 0.01em;
}

.idea-loss {
  margin-left: auto;
}

.idea-waveform {
  display: flex;
  align-items: center;
  height: 42px;
  gap: 2px;
  color: var(--violet);
  mask-image: linear-gradient(90deg, #000 66%, transparent);
}

.idea-waveform i {
  display: block;
  width: 2px;
  height: var(--bar-height);
  border-radius: 999px;
  background: currentColor;
}

.idea-handoff-visual {
  flex-wrap: wrap;
}

.idea-handoff-step {
  display: inline-flex;
  align-items: center;
  gap: 12px;
}

.idea-handoff-step i {
  color: #b7bac2;
  font-style: normal;
}

.idea-handoff-step b {
  display: inline-flex;
  min-height: 34px;
  align-items: center;
  padding: 0 14px;
  border: 1px solid #e5e5eb;
  border-radius: 8px;
  background: #fafafd;
  color: #555963;
  font-size: 12px;
  font-weight: 500;
}

.idea-fleck-visual {
  width: min(100%, 650px);
  margin: 20px 0;
}

.idea-fleck-visual img {
  display: block;
  width: 100%;
  height: auto;
  border: 1px solid rgba(35, 30, 56, 0.09);
  border-radius: 14px;
  box-shadow: 0 22px 60px rgba(40, 32, 77, 0.12);
}

.ideas-section.is-animatable:not(.is-visible) .ideas-intro,
.ideas-section.is-animatable:not(.is-visible) .idea-stage {
  opacity: 0;
  transform: translateY(18px);
}

.ideas-section.is-animatable .ideas-intro,
.ideas-section.is-animatable .idea-stage {
  transition: opacity 620ms var(--motion), transform 620ms var(--motion);
}

.ideas-section.is-animatable .idea-stage {
  transition-delay: calc(150ms + var(--step) * 115ms);
}

.ideas-section.is-animatable:not(.is-visible) .idea-timeline::before {
  transform: scaleY(0);
}

.ideas-section.is-animatable .idea-timeline::before {
  transition: transform 700ms var(--motion) 120ms;
}
```

Inside the existing `@media (max-width: 760px)` block, add:

```css
.ideas-section {
  padding: 112px 0 120px;
}

.ideas-shell {
  width: calc(100% - 40px);
}

.ideas-intro {
  grid-template-columns: 1fr;
  gap: 28px;
}

.ideas-intro h2 {
  font-size: clamp(40px, 11vw, 52px);
}

.ideas-intro > p {
  font-size: 16px;
}

.idea-timeline {
  margin-top: 72px;
}

.idea-timeline::before {
  left: 5px;
}

.idea-stage {
  display: block;
  min-height: 0;
  padding: 30px 0 34px 28px;
}

.idea-stage:last-child {
  min-height: 0;
}

.idea-stage-label {
  min-height: 0;
  margin-bottom: 24px;
}

.idea-stage-label p {
  max-width: none;
}

.idea-node {
  right: auto;
  left: -27px;
}

.idea-spark-visual,
.idea-capture-visual,
.idea-handoff-visual {
  align-items: flex-start;
  flex-wrap: wrap;
  gap: 12px;
}

.idea-spark-visual p,
.idea-capture-visual p {
  flex-basis: 100%;
  order: 3;
}

.idea-loss {
  margin-left: 0;
}

.idea-fleck-visual {
  margin: 0;
}
```

Inside `@media (prefers-reduced-motion: reduce)`, add:

```css
.ideas-section .ideas-intro,
.ideas-section .idea-stage,
.ideas-section .idea-timeline::before,
.ideas-section .idea-node {
  opacity: 1;
  animation: none;
  transform: none;
  transition: none;
}
```

- [ ] **Step 8: Run focused and full automated checks**

Run from `website/`:

```bash
npm test
npm run build
```

Expected: 2 tests pass, 0 fail; Vite server and client builds succeed.

---

### Task 3: Verify and document the finished section

**Files:**
- Create: `website/design-qa-ideas-desktop.png`
- Create: `website/design-qa-ideas-mobile.png`
- Create: `website/design-qa-ideas-comparison.png`
- Modify: `website/design-qa.md`

**Interfaces:**
- Consumes: the completed local website at `http://127.0.0.1:4173/`.
- Produces: visual evidence and a QA record for the hero-to-Ideas flow.

- [ ] **Step 1: Verify desktop runtime**

At a 1440 × 1000 viewport, scroll from the hero into the Ideas section and
confirm the heading, four rows, path sequence, genuine Fleck crop, and full
vertical scrolling. Confirm the sequence plays once and the console has no
errors or warnings.

- [ ] **Step 2: Verify mobile and reduced motion**

At 390 × 844, confirm `document.documentElement.scrollWidth === 390`, the rows
stack in order, labels wrap, and the Fleck crop remains legible. With reduced
motion emulated, confirm the completed composition appears without transforms,
path drawing, fading, or pulsing.

- [ ] **Step 3: Save visual evidence and update QA**

Capture the desktop and mobile section states, then create a side-by-side
comparison. Update `website/design-qa.md` with the runtime sizes, genuine-Fleck
asset provenance, motion checks, console result, and `final result: passed` only
after all checks succeed.

- [ ] **Step 4: Run final repository checks**

Run:

```bash
cd website && npm test
cd website && npm run build
git diff --check
```

Expected: 2 tests pass, both Vite builds succeed, and `git diff --check` has no
output.

- [ ] **Step 5: Commit only the section implementation**

Before staging, run `git diff --cached --name-only` and require no output. Stage
only the files listed in Tasks 1–3 and verify `git diff --cached --name-status`
before committing:

```bash
git commit -m "feat: add ideas arrival story"
```
