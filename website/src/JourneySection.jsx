import { useLayoutEffect, useRef, useState } from "react";
import { JOURNEY_CAPTURE_ASSET, JOURNEY_STAGES } from "./journeyContent";

const JOURNEY_FACTS = [
  ["Clean transcript", "The rough thought becomes a note you can use."],
  ["Note-by-note access", "Agents see only the notes you deliberately share."],
  ["Visible activity", "Completed work returns with a clear record."],
];

export default function JourneySection() {
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
      { threshold: 0.18 },
    );
    observer.observe(sectionRef.current);
    return () => observer.disconnect();
  }, []);

  const className = [
    "journey-section",
    animatable && "is-animatable",
    visible && "is-visible",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <section ref={sectionRef} className={className} aria-labelledby="journey-title">
      <div className="journey-shell">
        <div className="journey-copy">
          <h2 id="journey-title">Catch it once. Carry it all the way through.</h2>
          <p className="journey-summary">
            One thought stays intact from the moment it arrives to the moment the work is done.
          </p>

          <ol className="journey-stages">
            {JOURNEY_STAGES.map((stage, index) => (
              <li key={stage.id} style={{ "--step": index }}>
                <span className="journey-stage-node" aria-hidden="true" />
                <span className="journey-stage-number">{String(index + 1).padStart(2, "0")}</span>
                <div>
                  <h3>{stage.label}</h3>
                  <p>{stage.description}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>

        <div className="journey-product">
          <header className="journey-product-heading">
            <span>Real Fleck capture</span>
            <p>One thought. One source of truth.</p>
          </header>

          <figure className="journey-capture">
            <img
              src={JOURNEY_CAPTURE_ASSET}
              alt="The real Fleck editor holding the captured onboarding thought"
              loading="lazy"
            />
            <figcaption>
              Captured in the native macOS app from a dedicated website-demo note.
            </figcaption>
          </figure>

          <div className="journey-facts" role="list" aria-label="What Fleck preserves">
            {JOURNEY_FACTS.map(([title, description], index) => (
              <article key={title} role="listitem">
                <span>{String(index + 1).padStart(2, "0")}</span>
                <h3>{title}</h3>
                <p>{description}</p>
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
