import { useEffect, useRef } from "react";
import { heroStateForProgress } from "./heroStates.js";

function CapsuleVideo({ state, label }) {
  return (
    <div className="hero-capsule-take" data-capsule-state={state}>
      <video
        width="360"
        height="96"
        muted
        playsInline
        preload="metadata"
        aria-label={label}
        data-hero-video={state}
      >
        <source src={`/hero/capsule-${state}.webm`} type="video/webm" />
        <source src={`/hero/capsule-${state}.mp4`} type="video/mp4" />
      </video>
      <span className="hero-capsule-label">{label}</span>
    </div>
  );
}

export default function HeroStory({ downloadProps }) {
  const storyRef = useRef(null);

  useEffect(() => {
    const story = storyRef.current;
    if (!story) return undefined;

    const desktopQuery = window.matchMedia("(min-width: 768px)");
    const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const scenes = [...story.querySelectorAll("[data-hero-scene]")];
    const videos = [...story.querySelectorAll("video[data-hero-video]")];
    let activeState;
    let activeTrigger;
    let setupVersion = 0;
    let disposed = false;

    function pauseVideos() {
      for (const video of videos) video.pause();
    }

    function showAllScenes() {
      for (const scene of scenes) {
        scene.removeAttribute("aria-hidden");
        scene.removeAttribute("inert");
      }
    }

    function setHeroState(nextState) {
      if (activeState === nextState) return;
      activeState = nextState;
      story.dataset.heroState = nextState;

      for (const scene of scenes) {
        const isActive = scene.dataset.heroScene.split(" ").includes(nextState);
        scene.setAttribute("aria-hidden", String(!isActive));
        if (isActive) scene.removeAttribute("inert");
        else scene.setAttribute("inert", "");
      }

      for (const video of videos) {
        if (video.dataset.heroVideo !== nextState) {
          video.pause();
          continue;
        }

        try {
          video.currentTime = 0;
          const playPromise = video.play();
          if (playPromise) playPromise.catch(() => {});
        } catch {
          video.pause();
        }
      }
    }

    async function configureStory() {
      const version = ++setupVersion;
      activeTrigger?.kill();
      activeTrigger = undefined;
      activeState = undefined;
      pauseVideos();

      if (!desktopQuery.matches || reducedMotionQuery.matches) {
        story.dataset.heroState = "intro";
        showAllScenes();
        return;
      }

      setHeroState("intro");
      const [{ gsap }, { ScrollTrigger }] = await Promise.all([
        import("gsap"),
        import("gsap/ScrollTrigger"),
      ]);

      if (
        disposed
        || version !== setupVersion
        || !desktopQuery.matches
        || reducedMotionQuery.matches
      ) return;

      gsap.registerPlugin(ScrollTrigger);
      activeTrigger = ScrollTrigger.create({
        trigger: story,
        start: "top top",
        end: "bottom bottom",
        invalidateOnRefresh: true,
        onUpdate: ({ progress }) => setHeroState(heroStateForProgress(progress)),
      });
      setHeroState(heroStateForProgress(activeTrigger.progress));
    }

    function handleModeChange() {
      void configureStory();
    }

    desktopQuery.addEventListener("change", handleModeChange);
    reducedMotionQuery.addEventListener("change", handleModeChange);
    void configureStory();

    return () => {
      disposed = true;
      setupVersion += 1;
      activeTrigger?.kill();
      pauseVideos();
      desktopQuery.removeEventListener("change", handleModeChange);
      reducedMotionQuery.removeEventListener("change", handleModeChange);
    };
  }, []);

  return (
    <section
      className="hero-story"
      data-hero-state="intro"
      aria-label="Fleck shared memory story"
      ref={storyRef}
    >
      <div className="hero-stage">
        <div className="macos-menu-bar" aria-hidden="true">
          <div className="macos-menu-left">
            <span className="macos-apple"></span>
            <strong>Fleck</strong>
            <span>File</span>
            <span>Edit</span>
            <span>Format</span>
            <span>View</span>
            <span>Window</span>
            <span>Help</span>
          </div>
          <div className="macos-menu-right">
            <strong>Fleck</strong>
            <span className="macos-status-wide">Wi-Fi</span>
            <span className="macos-status-wide">100%</span>
            <time dateTime="09:41">9:41</time>
          </div>
        </div>

        <div className="hero-desktop">
          <section className="hero-scene hero-intro" data-hero-scene="intro">
            <div className="hero-copy">
              <h1 aria-label="Capture thoughts. Let your agents use them.">
                <span aria-hidden="true">Capture thoughts.</span>
                <span aria-hidden="true">Let your agents use them.</span>
              </h1>
              <p>Fleck is a lightweight shared memory for you and your agents.</p>
              <a className="hero-download" {...downloadProps}>
                Download for Mac
              </a>
            </div>
          </section>

          <section className="hero-scene hero-shortcut" data-hero-scene="shortcut">
            <h2 className="visually-hidden">Capture with a shortcut</h2>
            <img
              className="hero-product-capture hero-product-open"
              src="/hero/fleck-northstar-open.png"
              width="894"
              height="596"
              alt="Fleck open to the synthetic Northstar Demo note"
            />
            <div className="hero-shortcut-indicator">
              <kbd>Right Option</kbd>
              <span>Hold to capture</span>
            </div>
          </section>

          <section
            className="hero-scene hero-capture"
            data-hero-scene="listening processing saved"
          >
            <h2 className="visually-hidden">Fleck captures the thought</h2>
            <img
              className="hero-product-capture hero-product-open"
              src="/hero/fleck-northstar-open.png"
              width="894"
              height="596"
              alt=""
            />
            <figure className="hero-capture-sequence">
              <div className="hero-capsule-media">
                <CapsuleVideo state="listening" label="Listening" />
                <CapsuleVideo state="processing" label="Cleaning up" />
                <CapsuleVideo state="saved" label="Saved to Northstar Demo" />
              </div>
              <figcaption>
                Northstar Demo: Move the location permission request until after onboarding.
              </figcaption>
            </figure>
          </section>

          <section className="hero-scene hero-memory" data-hero-scene="memory">
            <div className="hero-step-heading">
              <h2>Fleck remembers</h2>
            </div>
            <figure>
              <img
                className="hero-product-capture"
                src="/hero/fleck-northstar-saved.png"
                width="894"
                height="596"
                alt="Northstar Demo in Fleck with the captured location permission thought saved"
              />
              <figcaption>The thought stays with the Northstar Demo note.</figcaption>
            </figure>
          </section>

          <section className="hero-scene hero-codex" data-hero-scene="codex">
            <div className="codex-demo" aria-labelledby="codex-demo-title">
              <h2 id="codex-demo-title">Codex demo</h2>

              <div className="codex-turn codex-turn-user">
                <p className="codex-speaker">You</p>
                <p>Pick up where I left off.</p>
              </div>

              <div className="codex-tool-event" aria-label="Fleck MCP read note event">
                <div className="codex-tool-name">
                  <span>Fleck MCP</span>
                  <code>read_note</code>
                </div>
                <strong>Northstar Demo</strong>
                <p>Open task: Update onboarding permission order and add regression coverage.</p>
                <p>
                  Decision: Ask for location only after the welcome walkthrough, when the user
                  understands why it is needed.
                </p>
              </div>

              <div className="codex-turn">
                <p className="codex-speaker">Codex</p>
                <p>
                  I found one open task in Northstar Demo. I can move the location permission
                  request until after onboarding.
                </p>
              </div>

              <div className="codex-turn codex-turn-user codex-turn-final">
                <p className="codex-speaker">You</p>
                <p>Do it.</p>
              </div>
            </div>
          </section>

          <section className="hero-scene hero-writeback" data-hero-scene="writeback">
            <div className="hero-step-heading">
              <h2>Agent writes back</h2>
            </div>
            <figure>
              <div className="hero-writeback-media">
                <img
                  className="hero-product-capture"
                  src="/hero/fleck-agent-writeback.png"
                  width="894"
                  height="596"
                  alt="Fleck showing the checked Northstar Demo task and Codex update banner"
                />
                <video
                  className="hero-writeback-video"
                  width="894"
                  height="596"
                  muted
                  playsInline
                  preload="metadata"
                  aria-label="Fleck showing Codex write the completed task back to Northstar Demo"
                  data-hero-video="writeback"
                >
                  <source src="/hero/agent-writeback.webm" type="video/webm" />
                  <source src="/hero/agent-writeback.mp4" type="video/mp4" />
                </video>
              </div>
              <figcaption>Codex updates the supported task, and Fleck records the change.</figcaption>
            </figure>
          </section>

          <section className="hero-scene hero-close" data-hero-scene="close">
            <h2>One shared memory. For you and your agents.</h2>
          </section>
        </div>
      </div>
    </section>
  );
}
