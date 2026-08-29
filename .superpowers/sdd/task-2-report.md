# Task 2 Report: Recorded Scroll-Driven Hero

## Status

Implemented and verified from accepted baseline `768655b`. No push, pull request, merge, publication, or deployment was performed.

## RED and GREEN evidence

### Pure state mapper

- RED command: `node --test src/heroStates.test.js`
- RED result: exit 1 with `ERR_MODULE_NOT_FOUND` for `src/heroStates.js`, the expected failure because the production mapper did not exist.
- GREEN command: `node --test src/heroStates.test.js`
- GREEN result: 1 test passed. Literal cases cover values below 0, above 1, and both sides of every intro, shortcut, listening, processing, saved, memory, codex, writeback, and close boundary.

### Semantic hero rendering

- RED command: `node --test src/HeroStory.test.js`
- RED result: exit 1 with Vite `ERR_LOAD_URL` for `src/HeroStory.jsx`, the expected failure because the production component did not exist.
- GREEN command: `node --test src/HeroStory.test.js`
- GREEN result: 1 test passed. The real server-rendered component contains the exact required hero copy, synthetic Northstar Demo transcript, Codex demo label, all accepted media paths, and neither prohibited completion claim.

### Final verification

- Command: `npm test && npm run build`
- Tests: 4 passed, 0 failed.
- Build: Vite 8.2.0 completed both server and client production builds.
- Client output keeps GSAP and ScrollTrigger in separate dynamically loaded chunks.

## Implementation summary

- Added a pure `heroStateForProgress(progress)` mapper with the approved thresholds.
- Added one semantic `HeroStory` component and integrated it below the approved `Navigation` without changing `Navigation.jsx` or its selectors.
- Added a full-width white simulated macOS menu bar directly beneath the website navigation.
- Added one CSS-sticky `420svh` desktop story with a `100svh` stage and one GSAP `ScrollTrigger` controller.
- GSAP 3.15.0 and ScrollTrigger are dynamically imported inside the effect. Server rendering does not evaluate browser-only code.
- Continuous scroll values never enter React state. The root `data-hero-state` changes only when the mapped state crosses a threshold.
- On each state change, only the matching listening, processing, saved, or writeback clip is played; every other clip is paused.
- The effect kills the active ScrollTrigger, pauses media, and removes both media-query listeners during cleanup.
- At 767px and below, and under reduced motion, the same scenes become a normal vertical narrative. No pinned miniature, wheel interception, smooth scrolling, or scroll snapping is used.
- New hero CSS uses a pure white page and desktop, native system typography, visible focus states, opacity and transform motion only, and no generated wallpaper, gradient hero background, laptop shell, scroll cue, metrics, numbered sections, or decorative card grid.

## Asset provenance

All assets were copied mechanically from:

`/Users/harryjin/Fleck/.worktrees/fleck-website-demo-capture-lab-current/.build/fleck-capture-lab/fleck-demo.ylWvga/Captures`

The source masters and derivatives were not altered. Destination hashes match the accepted manifest:

- `fleck-northstar-open.png`: `2d544aff8271e5ab44f20ad60f6337b42d96e7abccf97cad8e1e66bfd4dfbc44`
- `fleck-northstar-saved.png`: `4ab3c68986875ffae2ee80417b97b93689a6aa6bdb13a4d21e91980ae68014aa`
- `fleck-agent-writeback.png`: `5f4af1e9e690ace7938c4686a9aac2185a186dfb397504057d227994553baa1d`
- `capsule-listening.mp4`: `f430af47afed21f7f9a02255a67208ee2424d9ca92f9ed6da14b97301421cc29`
- `capsule-listening.webm`: `53fc84bffaed5069941cd792b607f4b51a648cb653aa43d8a512d87b4efd38dd`
- `capsule-processing.mp4`: `a8030d088c47c9b73820a5835d39561d3b168e9c0f5aa8ae7dc9197115ac550a`
- `capsule-processing.webm`: `f45c536fb242b0218dac5891fc9c862134221b47a4dabb232d722471b0e14c93`
- `capsule-saved.mp4`: `98572d1c2fcdc50d603c3486416966044980705a7815872a0db0a39b59eb3e23`
- `capsule-saved.webm`: `f13614639d34cbd68b6f77f57ed8d59598c3582d53601fa46f17b9886fdd0c1a`
- `agent-writeback.mp4`: `99ba037699efff2c1b3e321cd17e9a835656a5a7610f3ee3eeee87f7db989ae0`
- `agent-writeback.webm`: `a1d35c4ced6f20a30b888da154266075b3f478387c373722bdbb0d6a676a3a5f`

The stills are declared at 894 by 596 and capped at 894 CSS pixels. Capsule clips are declared at 360 by 96 and capped at 360 CSS pixels. Writeback clips are declared at 894 by 596 and capped at 894 CSS pixels.

## Browser evidence

Focused local Chromium checks used the required viewports:

- 1440 by 900: inspected intro, shortcut, listening, memory, Codex, writeback, and close states. The mapped `data-hero-state` changed at scroll thresholds, the active video was the only unpaused video, captures remained at or below native size, and the console had no errors or warnings.
- 390 by 844: confirmed normal document flow with the complete semantic sequence, all videos paused, no pinned `420svh` miniature, no horizontal overflow, and capsule frames rendering as their section entered view.

Temporary Playwright session artifacts were removed before commit.

## Changed files

- `.superpowers/sdd/task-2-report.md`
- `website/src/heroStates.js`
- `website/src/heroStates.test.js`
- `website/src/HeroStory.jsx`
- `website/src/HeroStory.test.js`
- `website/src/App.jsx`
- `website/src/styles.css`
- `website/package.json`
- `website/package-lock.json`
- `website/public/hero/fleck-northstar-open.png`
- `website/public/hero/fleck-northstar-saved.png`
- `website/public/hero/fleck-agent-writeback.png`
- `website/public/hero/capsule-listening.mp4`
- `website/public/hero/capsule-listening.webm`
- `website/public/hero/capsule-processing.mp4`
- `website/public/hero/capsule-processing.webm`
- `website/public/hero/capsule-saved.mp4`
- `website/public/hero/capsule-saved.webm`
- `website/public/hero/agent-writeback.mp4`
- `website/public/hero/agent-writeback.webm`

## Self-review

- `Navigation.jsx` is unchanged, and hero styles were appended after the accepted navigation styles.
- Visible hero copy contains no em dash or en dash characters.
- `Completed by Codex` and `Tests passing` occur only as negative test assertions, never in rendered content.
- All demo content is the approved synthetic Northstar Demo fixture. No real repository, note, credential, token, or user data appears.
- The Codex section is labeled `Codex demo`, uses semantic transcript markup, and has no fake window chrome.
- Exactly one `ScrollTrigger.create` call exists. No scroll event listener, React scroll state, wheel handler, or frame-by-frame scrubbing exists.
- The page remains exactly white. No ImageGen output, wallpaper, mesh, gradient hero background, glow, or decorative status dot was added.
- The full diff contains only Task 2 owned paths.

## Concerns and boundaries

- The authentic writeback capture retains Fleck's current low-contrast completed-task styling. This is the accepted source limitation and was not concealed with invented UI.
- Browser inspection in this task used Chromium. Safari or WebKit review remains a separate final acceptance check.
- `npm install` reported the repository's dependency audit and install-script notices: 1 low and 7 high audit findings across the full dependency tree, plus four install scripts awaiting allow-list review. This task did not run an unrelated dependency repair.
