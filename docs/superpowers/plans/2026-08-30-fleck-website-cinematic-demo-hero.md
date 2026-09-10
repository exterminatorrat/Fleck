# Fleck Cinematic Demo Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task by task. Use `superpowers:test-driven-development`, `superpowers:verification-before-completion`, `ponytail`, `emil-design-eng`, and the relevant web or macOS skills for each packet.

**Goal:** Replace the rejected multi-scene hero with one authentic, scroll-scrubbed Fleck-to-Codex-to-Fleck demonstration inside a licensed complete Space Black MacBook asset, while preserving the approved navigation and true-white page.

**Architecture:** Harden the existing synthetic capture lab so it can run from a short canonical user-owned root under the common checkout's ignored `.build`, uses Fleck dark appearance, and provisions a normal Codex profile. Record real Fleck and Codex interactions into one truthful edited master, encode browser-seekable MP4/WebM outputs, then replace the current nine-state `HeroStory` with one video, one hardware frame, one pure playback mapper, and one GSAP ScrollTrigger. Mobile and Reduced Motion use explicit playback instead of scroll scrubbing.

**Tech Stack:** Swift 6, Swift Testing, Bash, FFmpeg AVFoundation screen capture, Codex CLI, ffmpeg/ffprobe, React 19, Vite 8, GSAP 3 ScrollTrigger, native HTML video, plain CSS, Node test runner

**Spec:** `${FLECK_REPO}/.worktrees/fleck-website-demo-capture-lab-current/docs/superpowers/specs/2026-08-30-fleck-website-cinematic-demo-hero-design.md`

## Orchestration Contract

The primary session remains the integrator. Implementation is performed by Codex-native GPT-5.6 Sol workers at max reasoning, per the user's explicit task-wide override. Never use Terra or Luna. The two implementation packets are sequential because the website packet depends on accepted media and device geometry from the capture packet.

For every worker:

- Work only in `${FLECK_REPO}/.worktrees/fleck-website-demo-capture-lab-current`.
- You are not alone in the repository. Preserve unrelated work and adapt to accepted concurrent edits.
- Edit only the paths assigned in the packet.
- Use red-first TDD for source changes and record the observed failing output before implementation.
- Use `apply_patch` for text edits. Media encoding and mechanical asset conversion may use the appropriate command-line tools.
- Make focused local commits. Do not push, open a pull request, merge, deploy, publish, accept a third-party license agreement, or modify the main checkout.

The primary session must inspect each diff, rerun required verification, and then request a fresh `sol_advisor_sol_reviewer` review. A dependent packet cannot start until its prerequisite receives `ship`. `fix-first` goes back to the same worker; `rethink` returns to the primary session for a corrected packet.

---

## Packet 1: Capture-Lab Truthfulness and Short-Path Hardening

### Five-part specification

1. **Objective and success criteria**
   - Make a freshly prepared capture session use Fleck dark appearance.
   - Create sessions as `<common-checkout>/.build/f.XXXXXX`, where `<common-checkout>` resolves from Git's canonical common directory. This keeps the full connector socket path below the 104-byte AF_UNIX limit without symlinks, a globally writable temporary parent, or an unhardened clone.
   - Require the exact active profile name produced by Fleck's current `Add Codex` UI: `Codex`.
   - Add a synthetic `AGENTS.md` that tells the real Codex agent how to retrieve the open Fleck handoff and write the result back after verified work.
   - Keep seed verification strict and add a distinct postflight contract that admits only the expected completed Fleck task, supported-agent proof, bounded synthetic source/test diff, empty remote list, and passing fake-package tests.
   - Preserve all privacy, canonical-path, symlink, no-remote, deterministic-data, and contamination checks.
2. **Owned files, interfaces, and constraints**
   - Modify: `Sources/FleckCaptureLab/FleckCaptureLab.swift`
   - Modify: `Tests/FleckCaptureLabTests/FleckCaptureLabTests.swift`
   - Modify: `Scripts/fleck-capture-lab.sh`
   - Modify: `Tests/Scripts/fleck-capture-lab.test.sh`
   - Do not edit Fleck product behavior, website files, packaging scripts, or unrelated tests.
3. **Required implementation and explicit non-goals**
   - Change the fixture preference from `.light` to `.dark`.
   - Add exactly one deterministic repository file, `AGENTS.md`, with instructions limited to the synthetic demo workflow. Do not add secret material, real project names, or forced fake output.
   - Change only the capture session parent to the short common-checkout build root. Require the parent and leaf to be canonical, non-symlink, owned by the current UID, ignored by Git, and mode `700`; retain root, leaf, and nested symlink rejection.
   - Update exact-profile discovery and diagnostics from `Codex Demo` to `Codex`.
   - Make `codex-command` emit an isolated non-interactive invocation using `codex exec --ephemeral --ignore-user-config -C <fake-repository> -s workspace-write -a never` plus the exact Fleck MCP overrides. Authentication may be reused, but user config and task persistence may not.
   - Add `postflight <manifest>` without weakening `verify <manifest>`. It must require the completed Northstar task, one coherent integration proof for that note, only the expected onboarding source/test paths modified, no untracked/ignored files or remote, a clean patch, the expected `.afterWelcome` behavior and regression assertion, and passing Swift package tests in the session scratch root.
   - Do not weaken the app-tree checks, manifest binding, repository integrity, credential boundaries, or profile uniqueness requirement.
4. **Verification commands and expected evidence**
   - `swift test --filter FleckCaptureLabTests`
   - `bash Tests/Scripts/fleck-capture-lab.test.sh`
   - Both focused suites pass after their new assertions first fail on the old implementation.
   - `git diff --check` passes.
5. **Authority boundaries and required handoff**
   - Local code/test edits and a local commit are allowed.
   - Do not launch Fleck, create a live profile, run Codex, capture video, or change system settings in this packet.
   - Commit message: `fix: harden cinematic capture sessions`
   - Return the red and green evidence, full diff summary, commit SHA, and remaining capture risks.

### TDD steps

- [ ] **Step 1: Write the dark-appearance assertion**

  In `preparesOnlySyntheticCaptureData`, assert:

  ```swift
  #expect(snapshot.preferences.theme == .dark)
  ```

- [ ] **Step 2: Write the deterministic agent-instruction assertions**

  Extend the exact repository-file contract to include `AGENTS.md`. Assert its complete contents describe only these real duties:

  ```text
  When asked to pick up where the user left off, inspect the available Fleck tools for the open Northstar Demo handoff. Make the requested change in this synthetic repository, run its tests, and only after they pass update the originating Fleck task to reflect the completed work. Do not use network access or add a git remote.
  ```

- [ ] **Step 3: Write short-root and exact-profile shell assertions**

  Update the shell fixture to expect `<common-checkout>/.build/f.XXXXXX`, permission mode `700`, current-UID ownership, exact canonical containment, a socket path below the platform limit, the isolated `codex exec` flags, and the `Codex` profile. Add negative cases for:

  - a symlinked common build root or session parent,
  - a symlinked session leaf,
  - nested symlinks in Fleck data and the fake repository,
  - no active `Codex` profile,
  - duplicate active `Codex` profiles,
  - an active profile with a different display name.
  - seed `verify` rejecting a mutated repository and supported-agent proof,
  - `postflight` accepting only the exact completed task, coherent proof, bounded source/test diff, empty remote, clean patch, expected behavior/test assertion, and passing package tests,
  - `postflight` rejecting a missing or incoherent proof, extra file/path, malformed patch, remote, wrong behavior, or failing test.

- [ ] **Step 4: Run focused tests and record RED**

  ```sh
  swift test --filter FleckCaptureLabTests
  bash Tests/Scripts/fleck-capture-lab.test.sh
  ```

  Expected: the new dark-theme, repository-file, session-root, and profile-name assertions fail against the old implementation.

- [ ] **Step 5: Implement the minimal hardening**

  Change only the fixture values and path/profile contracts needed by the failing tests. Keep a single session-parent implementation and one exact profile matcher.

- [ ] **Step 6: Run focused tests and record GREEN**

  Re-run both commands from Step 4, then run `git diff --check`.

- [ ] **Step 7: Self-review and commit**

  Scan the diff for weakened path checks, real data, secrets, network access, or edits outside the four owned files. Commit with the required message.

---

## Packet 2: Authentic Capture, Licensed Hardware, and Web Media

### Five-part specification

1. **Objective and success criteria**
   - Produce truthful high-resolution raw captures of the complete Fleck -> Codex -> Fleck workflow from the accepted synthetic session.
   - Produce one continuous 20 to 25 second silent 60fps master using only chronological cuts that remove latency.
   - Export a seekable H.264 MP4, a seekable WebM, a sharp WebP poster, and a complete Space Black MacBook frame suitable for screen compositing.
   - Document build, capture, asset, license, privacy, and media provenance.
2. **Owned files, interfaces, and constraints**
   - Create/replace: `website/public/hero/fleck-story-scroll.mp4`
   - Create/replace: `website/public/hero/fleck-story-scroll.webm`
   - Create/replace: `website/public/hero/fleck-story-poster.webp`
   - Create: `website/public/hero/macbook-pro-space-black.webp`
   - Create: `website/public/hero/provenance.md`
   - Ignored raw work belongs only under the freshly prepared capture session's `Captures/` directory.
   - Do not edit source code or tests in this packet.
3. **Required implementation and explicit non-goals**
   - Rebuild the newest accepted Fleck source at the exact Packet 1 commit and record a reproducible receipt.
   - Use the capture-lab wrapper and actual Fleck UI. Use actual Codex CLI connected through Fleck's real MCP connector in the synthetic `NorthstarDemo` repository.
   - Use Fleck dark appearance, a clean dark Terminal/Codex appearance, a generic non-personal dark landscape desktop, the actual menu bar, Dock, and cursor.
   - Render the complete Space Black MacBook from William Laverty's pinned `rigged-macbook-3d` GLB at commit `74771a18884dade35cdf79c7614628100f0f893a`. Verify the expected source SHA-256 `558e34c8371297dccb75786e77f2246a4604effe5937288ff4f73f97dd81d6a0`; retain jackbaeten and William Laverty attribution, CC BY 4.0 link, derivative notice, source commit, and render changes in provenance. This is a local-development asset subject to the texture-quality and public-release gates in the design brief.
   - Do not fabricate Fleck, Codex, cursor, test, writeback, or completion states.
4. **Verification commands and expected evidence**
   - `Scripts/fleck-capture-lab.sh verify <manifest>` passes before the real workflow.
   - `Scripts/fleck-capture-lab.sh postflight <manifest>` passes after the real workflow; the seed verifier continues to reject the mutated session.
   - `swift test --package-path <fake-repository> --scratch-path <session-root>/SwiftPMBuild/NorthstarDemo` passes after the Codex change.
   - `git -C <fake-repository> diff --check` passes and `git -C <fake-repository> remote` is empty.
   - `ffprobe` confirms matching dimensions/duration, 60fps, no audio, and expected codecs.
   - Keyframe inspection confirms a maximum 0.2 second interval.
   - SHA-256 hashes exist for the rebuilt Fleck executable, raw master, web media, poster, and hardware asset.
5. **Authority boundaries and required handoff**
   - Launching the isolated app, creating an isolated profile, running Codex against the fake project, recording the screen, temporarily staging a generic background, restoring prior visual state, downloading the pinned CC BY model, using disposable local rendering dependencies, and generating local media are in scope.
   - Never expose or transmit personal data, modify a real repository, add a remote, alter the user's normal Fleck workspace, publish media, or agree to new legal terms.
   - Commit message: `feat: add authentic cinematic hero media`
   - Return the manifest path, build receipt, recording steps, media metadata, hashes, privacy checks, asset provenance, commit SHA, and any editorial cuts.

### Production steps

- [ ] **Step 1: Prove and stop only the isolated Fleck process**

  Inspect the running Fleck process path and launch time without printing its environment. Stop it only if its executable resolves to this worktree's `.build/parakeet-test/Fleck.app`. Do not stop an unrelated Fleck process.

- [ ] **Step 2: Rebuild from the accepted source**

  Run:

  ```sh
  Scripts/build-parakeet-test-app.sh
  ```

  Record commit SHA, clean product-source diff, executable SHA-256, bundle identifier, and codesign inspection. A build success is not capture proof.

- [ ] **Step 3: Prepare and verify a fresh session**

  Run:

  ```sh
  Scripts/fleck-capture-lab.sh prepare
  Scripts/fleck-capture-lab.sh verify <manifest>
  ```

  Confirm the canonical short path, mode `700`, dark preference, exact synthetic files, clean fake repository, empty remote list, and open Fleck task. The strict seed verifier must pass here.

- [ ] **Step 4: Launch Fleck and provision the isolated connector**

  Launch only through:

  ```sh
  Scripts/fleck-capture-lab.sh launch <manifest>
  ```

  Use Computer Use to install the Agent Connector, add the `Codex` profile, and grant that profile only the minimum Northstar Demo read/task-update capabilities. Re-run:

  ```sh
  Scripts/fleck-capture-lab.sh codex-command <manifest>
  ```

  Confirm the emitted command points only at the fake repository, installed isolated helper, exact active profile, and same short `CFFIXED_USER_HOME`.

- [ ] **Step 5: Rehearse the real agent loop before recording**

  In a clean Terminal window, run the emitted ephemeral Codex command with exactly `Pick up where I left off.` as its prompt. If the real interface requires a follow-up approval, use `Do it.` in the same visible workflow. Confirm Codex actually:

  - discovers and reads the Northstar Demo handoff through Fleck,
  - changes the fake onboarding code and regression test,
  - runs the fake package tests,
  - updates the originating Fleck task only after the tests pass.

  Run `Scripts/fleck-capture-lab.sh postflight <manifest>` and confirm it passes while the strict seed verifier rejects the now-mutated session. Reset by creating a brand-new capture session, not by copying a mutated data tree or running destructive Git commands.

- [ ] **Step 6: Stage a private capture desktop**

  Keep the display at its verified native `2560x1440` resolution. After the Mac is unlocked, visually verify or temporarily stage a licensed generic dark landscape, note and temporarily enable an existing Do Not Disturb state, hide unrelated windows, and remove nonessential status utilities from the capture region without disrupting networking. Do not capture account names, notification contents, recent files, personal Dock badges, or unrelated menu-bar utilities. Record every reversible staging action and restore it after capture.

- [ ] **Step 7: Record real source takes**

  Record a native-pixel `2304x1440` 16:10 crop from `Capture screen 0` through FFmpeg AVFoundation at 60fps with `-capture_cursor 1`, `-capture_mouse_clicks 0`, no audio device, `-n`, constant frame rate, and a ProRes intraframe master. Crop the verified `2560x1440` display with `crop=2304:1440:0:0`; do not change display resolution or scaling. Capture the real chronological states listed in the design brief. Source takes may be separate so model/build latency can be removed honestly, but each take must show real UI and real state transitions. Use `/usr/sbin/screencapture -v -C` only as a documented fallback if AVFoundation capture fails, and do not accept a fallback master until its frame timing is conformed and visually verified at 60fps.

- [ ] **Step 8: Edit the truthful continuous master**

  Use ffmpeg to trim only idle time and concatenate the chronological real takes. Target 20 to 25 seconds. Do not add captions, fake cursor motion, interface graphics, status badges, sound, or invented frames. Restore the prior desktop appearance after capture.

- [ ] **Step 9: Acquire and prepare the hardware asset**

  Download `assets/macbook-rigged.glb` directly from pinned commit `74771a18884dade35cdf79c7614628100f0f893a` and reject it unless its SHA-256 is exactly `558e34c8371297dccb75786e77f2246a4604effe5937288ff4f73f97dd81d6a0`. In ignored capture storage, use a reproducible headless Three.js/Chromium renderer with `GLTFLoader` and `MeshoptDecoder` to produce a perfectly straight-on orthographic render at a minimum 3000px width on transparent or true-white output. Keep the complete base, keyboard, trackpad, hinge, and lid visible; derive the exact screen-aperture coordinates from the isolated `Screen` node. Inspect at the final website size and stop if the embedded textures look soft or artificial. Record the pinned source, authors, CC BY 4.0 attribution, derivative notice, download date, source/render hashes, renderer versions, camera, dimensions, and aperture.

- [ ] **Step 10: Encode web outputs**

  Encode:

  - H.264 High/yuv420p/60fps/faststart/no audio with GOP 12 or shorter.
  - WebM VP9/60fps/no audio with matching duration and a 12-frame or shorter keyframe cadence.
  - A sharp WebP poster from the first readable frame.

  Keep the archival master in ignored capture storage and copy only the four approved web assets into `website/public/hero/`.

- [ ] **Step 11: Write provenance and verify**

  Create `provenance.md` with the exact build receipt, synthetic manifest, raw/output hashes, ffprobe summaries, asset source/license, screen aperture, capture/privacy checklist, real agent actions, and complete cut list. Do not include credentials, profile secrets, or absolute personal paths beyond the isolated worktree/session evidence needed for reproducibility.

- [ ] **Step 12: Self-review and commit**

  Visually inspect the master, poster, and hardware asset. Verify all commands in the five-part specification, scan visible frames for personal material, then make the required local commit.

---

## Packet 3: Single-Video Scroll-Scrub Hero

### Five-part specification

1. **Objective and success criteria**
   - Replace the existing nine-state hero with one paused video precisely composited into the accepted full MacBook asset.
   - Desktop forward and reverse scrolling map smoothly to the full video duration while the device stays fixed.
   - Mobile, coarse-pointer, Reduced Motion, loading, and media-error modes remain operable and truthful.
   - Preserve the approved navigation, download behavior, true-white page, and demo-only visible composition.
2. **Owned files, interfaces, and constraints**
   - Modify: `website/src/HeroStory.jsx`
   - Modify: `website/src/HeroStory.test.js`
   - Create: `website/src/heroPlayback.js`
   - Create: `website/src/heroPlayback.test.js`
   - Delete: `website/src/heroStates.js`
   - Delete: `website/src/heroStates.test.js`
   - Modify only the hero rules after the navigation block in `website/src/styles.css`.
   - Modify only the test-script file list in `website/package.json`.
   - Delete the obsolete fourteen files under `website/public/hero/` only after confirming they are unreferenced and the four Packet 2 assets are present.
   - Do not edit `App.jsx`, `Navigation.jsx`, `Navigation.test.js`, worker/hosting code, native source, capture scripts, or the four new media/provenance files.
3. **Required implementation and explicit non-goals**
   - Use one video element, one GSAP ScrollTrigger, one scheduled animation frame, and no React state on scroll frames.
   - Use the exact screen-aperture coordinates recorded in provenance as CSS custom properties.
   - Keep the complete device at the spec's exact responsive scale and optical position.
   - Render no visible marketing copy, caption, progress meter, scene labels, fake status, or extra CTA.
   - Do not add a dependency, canvas, WebGL, image sequence, autoplay, scroll lock, smoothing, snapping, or hardware animation.
4. **Verification commands and expected evidence**
   - `node --test src/heroPlayback.test.js` passes after first failing because the module is absent.
   - `node --test src/HeroStory.test.js` passes after first failing against the old multi-scene markup.
   - `npm test` passes.
   - `npm run build` passes.
   - `git diff --check` passes.
5. **Authority boundaries and required handoff**
   - Local website code, test, stylesheet, and obsolete-asset changes are allowed.
   - Do not change navigation, capture media, provenance, native app code, or external systems.
   - Commit message: `feat: build cinematic scroll-scrub hero`
   - Return red and green evidence, test/build results, diff summary, commit SHA, and known browser risks.

### TDD steps

- [ ] **Step 1: Write the pure playback tests**

  Create tests for:

  ```js
  mediaTimeForProgress(-1, 24) === 0
  mediaTimeForProgress(0.5, 24) === 12
  mediaTimeForProgress(2, 24) === 24
  mediaTimeForProgress(0.5, 0) === 0
  ```

  Also test that desktop fine-pointer mode allows scrubbing and that mobile, coarse pointer, or Reduced Motion selects explicit playback.

- [ ] **Step 2: Run the focused mapper test and record RED**

  ```sh
  cd website
  node --test src/heroPlayback.test.js
  ```

  Expected: failure because `heroPlayback.js` does not exist.

- [ ] **Step 3: Implement the minimal pure playback module and record GREEN**

  Implement only clamping, progress-to-time mapping, and playback-mode selection. Re-run the focused test.

- [ ] **Step 4: Replace the semantic rendering expectations and record RED**

  Update `HeroStory.test.js` to require:

  - exactly one `<video>`,
  - MP4 and WebM sources,
  - the accepted poster and device asset,
  - `muted`, `playsInline`, and no autoplay,
  - one accessible synopsis and one fallback play/pause control,
  - absence of all old scene copy, Codex DOM transcript, old media paths, fake macOS chrome, headline, CTA, caption, and status strings.

  Run the focused test and observe it fail against the old component.

- [ ] **Step 5: Implement the single-video component**

  Render the semantic structure from the design brief. Dynamically import GSAP/ScrollTrigger only in scrubbing mode. Wait for metadata, map normalized progress to duration, coalesce seeks with `requestAnimationFrame`, ignore changes below half a frame, pause outside explicit playback, and clean up every listener, frame, and trigger.

  For mobile/coarse-pointer/Reduced Motion, disable pinning and expose the explicit control. If both sources fail, keep the poster and synopsis available.

- [ ] **Step 6: Replace only the hero stylesheet**

  Preserve all navigation CSS. Replace the current hero rules with:

  - `340svh` desktop story,
  - sticky viewport stage,
  - `clamp(760px, 72vw, 1140px)` device sizing,
  - exact aperture coordinates from `provenance.md`,
  - complete-device visibility and white-space constraints,
  - 90vw tablet and 96vw mobile sizing,
  - non-sticky explicit playback on mobile/Reduced Motion,
  - focus-visible and media-error treatment.

  Do not animate or transform the hardware.

- [ ] **Step 7: Remove obsolete state code and media**

  Delete `heroStates.js`, its test, and the old still/clip files only after `rg` confirms no references. Update only the website test script list.

- [ ] **Step 8: Verify and commit**

  Run focused tests, `npm test`, `npm run build`, `git diff --check`, an em-dash scan over rendered strings, and a privacy scan over source/asset names. Review the full diff and make the required commit.

---

## Packet 4: Browser QA, Motion QA, and Final Polish

This is a verification and correction pass on Packet 3, owned by the same implementation worker if fixes are required.

- [ ] **Step 1: Start the local preview**

  ```sh
  cd website
  npm run dev -- --host 127.0.0.1 --port 4174 --strictPort
  ```

  Keep the preview available at `http://127.0.0.1:4174/`.

- [ ] **Step 2: Use the in-app Browser first**

  Inspect 1512 x 982 and 390 x 844 views in the in-app browser. Test the center menu, forward scrub, reverse scrub, initial poster, final hold, and fallback control. Record console errors and overflow. If the Browser runtime is unavailable or times out on the local page, record the exact failure and use the Playwright CLI fallback.

- [ ] **Step 3: Capture deterministic browser evidence**

  With the Playwright CLI, save screenshots under `website/output/playwright/` at the beginning, middle, end, reverse-middle, mobile, and Reduced Motion states. Inspect each image rather than treating capture success as visual proof.

- [ ] **Step 4: Verify responsive and accessible behavior**

  Confirm:

  - navigation remains above the device,
  - complete hardware remains visible at desktop sizes,
  - no horizontal overflow,
  - exact screen fit with no bezel/base overlap,
  - no visible website copy beyond navigation and the fallback control where required,
  - keyboard menu and playback controls,
  - static poster plus explicit playback for Reduced Motion,
  - silent media and accessible synopsis,
  - no console errors.

- [ ] **Step 5: Run performance sanity checks**

  While repeatedly scrubbing the active stage, verify one video element and one active ScrollTrigger, no repeated React commits on scroll, no growing timers/listeners, and no sustained runaway browser CPU or memory. Record measurements. Optimize only evidence-backed pathological behavior.

- [ ] **Step 6: Correct and reverify**

  Route any P0/P1/P2 visual, motion, accessibility, or performance defect to the same Packet 3 worker. Repeat the focused tests, full tests, build, browser captures, and performance check after each correction. Do not churn on subjective P3 polish once the brief is met.

- [ ] **Step 7: Parent integration verification**

  The primary session independently runs:

  ```sh
  swift test --filter FleckCaptureLabTests
  bash Tests/Scripts/fleck-capture-lab.test.sh
  cd website && npm test && npm run build
  git diff --check
  ```

  The primary also checks media metadata/hashes, capture privacy, full branch diff, and worktree status.

- [ ] **Step 8: Fresh independent review**

  A fresh `sol_advisor_sol_reviewer` inspects the actual accepted diff and parent evidence. Do not call the work complete without `VERDICT: ship`.

## Completion Boundary

Completion means the local branch contains the final brief, this implementation plan, hardened synthetic capture lab, authentic and provenance-documented media, the single-video hero, passing tests/build, inspected desktop/mobile/Reduced Motion evidence, sane runtime behavior, and a fresh `ship` verdict. It does not mean pushed, merged, published, deployed, licensed for public release, or physically validated on another Mac.
