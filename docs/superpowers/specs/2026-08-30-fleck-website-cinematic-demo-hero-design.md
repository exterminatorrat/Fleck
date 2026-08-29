# Fleck Cinematic Demo Hero Design Brief

Date: 2026-08-30

Status: Approved direction, ready for implementation

## 1. Objective

Replace the current multi-scene marketing hero with one quiet, high-fidelity product demonstration. The finished first section must let a visitor understand Fleck by watching a real thought move from Fleck to Codex and back into Fleck, without explanatory headline copy, floating labels, or simulated product UI.

The website navigation remains the only conventional website interface in the first section. Everything below it is a true-white canvas holding a complete physical MacBook and an authentic, silent screen recording.

Success means:

- The existing Fleck brand, center menu, and Download for Mac control remain unchanged.
- A complete front-facing MacBook is centered below the navigation, including display, keyboard, trackpad, and base.
- The MacBook is visually prominent but does not fill the viewport edge to edge.
- The screen contains one continuous, real recording of the latest Fleck build and Codex using only synthetic Northstar Demo data.
- Desktop scrolling scrubs the recording forward and backward with a stable, fixed hardware frame.
- No website headline, subtitle, CTA, caption, progress label, feature badge, or fabricated status appears around or over the MacBook.
- Mobile, Reduced Motion, and failed-media states remain understandable and operable.
- The page does not cause sustained pathological CPU or memory use during normal scrolling.

## 2. Design Read

This is a premium macOS utility landing page for developers. It should feel calm, exact, and quietly confident. The product demonstration is the visual signature, so the surrounding design stays deliberately restrained.

Design dials:

- Design variance: 7/10. The concept is distinctive because the hero is almost entirely a real product proof, not because it adds decoration.
- Motion intensity: 8/10. Motion carries the story, but every frame belongs to the real recording.
- Visual density: 2/10. The white canvas, fixed navigation, and one device are the composition.

Typography remains the existing native sans stack. The hero adds no display typography. This keeps Fleck aligned with the direct product language of SpaceFS and T3 Code instead of introducing an editorial voice that competes with the demo.

## 3. Reference Ledger

### SpaceFS

Transfer these principles:

- Give the product proof far more visual weight than marketing copy.
- Use a very wide, quiet white canvas and generous negative space.
- Let scrolling control a continuous demonstration instead of swapping explanatory cards.
- Keep the centered menu compact and independent from the product stage.
- Use real media, real application artifacts, and restrained transitions.

Do not copy SpaceFS assets, wording, typography files, exact spacing, or page structure. Fleck's complete MacBook, dark macOS capture, and voice-to-agent loop must create a distinct composition.

### T3 Code

Transfer these principles:

- Keep the story centered on one understandable workflow.
- Show the actual product rather than an invented dashboard or generic illustration.
- Remove secondary explanations when the interface can prove the point itself.

Do not copy its source positioning, copy, buttons, or visual assets.

### Fleck

Fleck contributes the unique proof:

- A real local-first macOS workspace.
- Right Option voice capture.
- Local cleanup and save.
- A real Codex agent retrieving the synthetic note.
- A real agent change in a fake software project.
- A real writeback to the same Fleck note.

## 4. Page Composition

### Navigation

Preserve the current approved navigation exactly in behavior and visual hierarchy:

- Fleck mark and wordmark at the top left.
- Glass Menu control centered.
- Download for Mac at the top right.
- Existing placeholder link behavior remains honest and disabled.

The navigation stays above the hero and must not be captured inside the video. There is no simulated macOS menu bar beneath the website navigation.

### Desktop stage

- Page background: `#ffffff`.
- Story height: `340svh`.
- Sticky stage: `100svh` with the device optically centered about 55 to 58 percent down the viewport.
- Device width: `clamp(760px, 72vw, 1140px)`.
- Device must remain entirely visible at common 1440 x 900 and 1512 x 982 viewports.
- Preserve at least 32px of white space at the left and right at the smallest desktop breakpoint.
- Preserve visible white space above the lid and below the base.
- The device does not translate, rotate, scale, or parallax while scrolling. Only the content inside its screen changes.

### Tablet stage

- Device width: approximately 90vw.
- Keep the entire base visible when viewport height permits.
- Reduce the story span enough that the scrub does not feel slow, while preserving the complete video range.

### Mobile stage

- Device width: approximately 96vw.
- Do not shrink desktop scroll scrubbing into an illegible pinned interaction.
- Show the high-resolution poster first and expose an explicit play/pause control associated with the demo.
- The control may sit immediately below the device because it is an accessibility and compatibility fallback, not marketing content.
- Maintain a minimum 44px touch target and a visible focus state.

## 5. Physical MacBook Asset

The device must be a high-resolution, front-facing, complete physical MacBook Pro in Space Black. It must include the full keyboard deck, trackpad, hinge, and lower base. A CSS-drawn laptop, browser window, cropped lid, generic rounded rectangle, or AI-generated application screen is not acceptable.

Asset requirements:

- Minimum useful source width: 3000px.
- Transparent background or a true-white background that disappears against the page.
- Straight-on or near-straight-on perspective so the screen aperture can receive a rectangular video without visible distortion.
- Source URL, author, license text, download date, and source hash recorded in `website/public/hero/provenance.md`.
- The source must permit local design use and commercial website presentation.
- Before public launch, revalidate the source license and Apple trademark/marketing requirements. Local implementation does not constitute approval to publish.

Use the hardware art as supplied. Do not add a fake Apple logo, reflections, exaggerated shadows, floating elements, or effects that appear to leave the display.

## 6. Authentic Demo Environment

Use only the isolated Fleck capture lab. Never record the user's normal Fleck workspace, personal Codex tasks, home directory, notifications, real repositories, credentials, account names, or browsing history.

The capture session contains:

- Projects: `Northstar Demo`, `Relay Demo`, and `Canvas Demo`.
- Selected note: `Northstar Demo`.
- Open task: `Update onboarding permission order and add regression coverage.`
- Dictation: `Northstar Demo: move the location permission request until after onboarding.`
- Agent prompt: `Pick up where I left off.`
- Approval: `Do it.`
- Fake repository: the isolated `NorthstarDemo` Swift package with no remote.
- Fleck theme: dark.
- macOS appearance: dark.
- Wallpaper: a generic, non-personal dark landscape supplied by macOS or a locally licensed equivalent.

Before capture:

- Verify the capture manifest and synthetic repository.
- Verify the fake repository has no remote and is clean.
- Verify the packaged app came from the newest accepted Fleck source in this branch, including dictation, cleanup, sorting, and local model UI.
- Verify the normal Fleck process is not running.
- Disable or hide notifications and close unrelated windows without altering the user's personal data.
- Use an isolated Codex demo task or isolated invocation rooted in `NorthstarDemo`; do not reveal the current task or personal sidebar content.

## 7. Recording Storyboard

Produce one continuous silent master lasting 20 to 25 seconds. The cursor is real and baked into the recording. Every visible state must come from actual app behavior.

1. Establish the dark macOS desktop with a correct menu bar and Dock.
2. Move the cursor to Fleck and open the latest Fleck build.
3. Show the Northstar Demo note in Fleck's dark appearance.
4. Hold Right Option and dictate the approved Northstar sentence.
5. Show the real listening, cleanup, and saved states.
6. Show the new thought in the Northstar Demo note.
7. Open Codex in the synthetic Northstar repository.
8. Enter `Pick up where I left off.`
9. Show Codex retrieving the Fleck note through the real connector and identifying the open task.
10. Approve the work with `Do it.` when the interface requires it.
11. Show Codex making the real synthetic code and test change.
12. Return to Fleck and show the actual task completion/writeback state.
13. Hold the final state briefly so the end frame reads cleanly.

Permitted editorial treatment:

- Remove idle waits, build delays, and model latency.
- Use simple cuts or short dissolves that preserve the order and truth of events.
- Add a small `Sequences shortened` disclosure inside the recorded screen only if required by the chosen hardware/marketing asset terms.

Forbidden treatment:

- Reconstructing Fleck or Codex in HTML, CSS, Figma, ImageGen, or video graphics.
- Replacing the real cursor with an animated cursor.
- Adding floating labels, captions, progress bars, completion claims, fake terminal text, or synthetic success banners.
- Inventing a test result, writeback, model response, or app state.
- Showing `Completed by Codex` or `Tests passing` unless those exact states genuinely exist in the current product and are produced during the recording.

## 8. Master and Web Exports

Capture master:

- Native-resolution source at 60fps.
- 16:10 visual composition.
- Cursor included.
- No audio track in final web files.
- Preserve an archival master outside the public website assets.

Web outputs:

- `website/public/hero/fleck-story-scroll.mp4`: H.264 High profile, yuv420p, 60fps, faststart, no audio.
- `website/public/hero/fleck-story-scroll.webm`: VP9 or AV1 fallback when the available toolchain produces browser-stable seeking, no audio.
- `website/public/hero/fleck-story-poster.webp`: high-resolution first readable frame.
- Keyframe interval: no more than 12 frames, targeting 0.2 seconds at 60fps.
- MP4 and WebM duration and dimensions must match.
- The poster must match the video aperture and may not contain website text.

Do not upscale a low-resolution recording. If a capture does not resolve Fleck and Codex text at the rendered device size, record again.

## 9. Scroll Playback Architecture

Keep React 19, Vite 8, GSAP 3, and plain CSS. No new animation dependency is required.

`HeroStory` renders:

- One semantic hero section.
- One sticky stage.
- One device figure.
- One paused `<video>` aligned to the physical screen aperture.
- One hardware image above the video when the frame requires it.
- One screen-safe poster/loading state.
- One visually hidden synopsis for assistive technology.
- One mobile/Reduced Motion playback control.

Desktop behavior:

- Dynamically load GSAP and ScrollTrigger after mount.
- Wait for video metadata before mapping progress to duration.
- Map normalized story progress linearly to `video.currentTime`.
- Schedule seeks through one `requestAnimationFrame` and ignore insignificant sub-frame changes.
- Scrolling backward must seek backward naturally.
- Never call `video.play()` during desktop scrubbing.
- Kill ScrollTrigger, cancel animation frames, remove listeners, and pause media on cleanup.
- Do not place per-frame values in React state.

Fallback behavior:

- Before metadata loads, show the poster and keep the device stable.
- If the preferred source fails, allow the browser to try the alternate source.
- If all video sources fail, keep the poster visible and expose the accessible synopsis.
- At 767px and below, on coarse pointers where seeking is unreliable, or under `prefers-reduced-motion: reduce`, disable pinning and scroll scrubbing. Use explicit play/pause behavior instead.
- Under `prefers-reduced-transparency: reduce`, preserve the existing navigation fallback and do not change the hero.

## 10. Accessibility

- The hero uses a descriptive `aria-label` such as `Fleck voice-to-agent demo`.
- Decorative hardware imagery has empty alternative text.
- The video has an accessible name and a visually hidden synopsis describing the sequence.
- The synopsis is not duplicated as visible marketing copy.
- The mobile/Reduced Motion control communicates play and pause state, works from the keyboard, and retains a 44px target.
- Focus indicators meet WCAG AA contrast against white.
- Scroll remains native. Do not smooth, snap, lock, or hijack the page.
- Reduced Motion users are never forced through scroll-controlled video.

## 11. Performance Guardrails

Visual quality takes priority, but the hero must not throttle the machine unnecessarily.

- One video element only.
- No canvas, WebGL, 3D runtime, image sequence, or parallel hidden videos.
- One ScrollTrigger and one scheduled animation frame at most.
- No React render on scroll frames.
- Stop seeking when the hero is outside its active scroll range.
- Poster remains visible until the first decoded frame is ready.
- Record output file sizes, duration, dimensions, frame rate, codec, pixel format, keyframe cadence, and SHA-256 hashes.
- During local QA, inspect browser CPU and memory for sustained runaway behavior. Optimize only if the hero produces clear sustained load, dropped interaction, or memory growth.

## 12. Responsive and Visual Acceptance

Verify at minimum:

- 1512 x 982 desktop.
- 1440 x 900 desktop.
- 1024 x 768 tablet.
- 390 x 844 mobile.
- Reduced Motion at desktop and mobile widths.

At every size:

- No horizontal overflow.
- Navigation remains legible and above the device.
- The full MacBook is visible where specified.
- The video fits the exact screen aperture without covering bezel, notch, keyboard, or base.
- Website white and asset white are visually continuous.
- No invented copy or overlay is present.
- The dark app capture remains readable.

## 13. Verification

Implementation is accepted only with all of the following evidence:

- Capture-lab tests and verification pass.
- Synthetic repository tests pass before and after the demo action.
- Website tests pass.
- Vite production build passes.
- `git diff --check` passes.
- Media metadata and keyframe cadence meet this brief.
- Media and device provenance are documented and hashed.
- Browser inspection confirms forward and reverse scrubbing, menu interaction, mobile playback fallback, Reduced Motion behavior, no overflow, and no console errors.
- Desktop and mobile screenshots are inspected visually against this brief and the transferable SpaceFS/T3 principles.
- A fresh independent Sol review returns `ship` on the actual diff and evidence.

## 14. Explicit Non-Goals

- No headline, subtitle, CTA, pricing, comparison, FAQ, feature cards, or later homepage sections.
- No redesign of the approved navigation.
- No background image, gradient field, hologram, ASCII art, or generated illustration.
- No fake Mac frame or simulated macOS chrome.
- No public deployment, branch push, pull request, merge, App Store submission, or asset-license acceptance on the user's behalf.
- No performance micro-optimization unless local evidence shows material sustained CPU, memory, or interaction problems.

## 15. Authority Boundaries

The authorized outcome is a complete local implementation and preview in the isolated website worktree. Local commits are allowed. External publication and repository writes are not allowed. Any asset whose public-use rights depend on an account agreement remains gated for public launch even when it is acceptable for the local design checkpoint.
