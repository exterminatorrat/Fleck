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
            <li
              key={stage.id}
              className={`idea-stage idea-stage-${stage.id}`}
              style={{ "--step": index }}
            >
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
