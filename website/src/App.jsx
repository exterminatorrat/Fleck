import BrainHologram from "./BrainHologram";
import IdeasSection from "./IdeasSection";
import JourneySection from "./JourneySection";
import Navigation from "./Navigation";

const APP_STORE_URL = import.meta.env.VITE_APP_STORE_URL?.trim();
const GITHUB_URL = "https://github.com/exterminatorrat/menubar-notes";

function preventUnavailableDownload(event) {
  if (!APP_STORE_URL) event.preventDefault();
}

export default function App() {
  const downloadProps = {
    href: APP_STORE_URL || "#app-store",
    onClick: preventUnavailableDownload,
    ...(APP_STORE_URL
      ? { target: "_blank", rel: "noreferrer" }
      : {
          "aria-disabled": "true",
          title: "Fleck is not yet available in the Mac App Store",
        }),
  };

  return (
    <main className="page">
      <Navigation downloadProps={downloadProps} />
      <section className="hero" aria-labelledby="hero-title">
        <BrainHologram />

        <div className="hero-content">
          <h1 id="hero-title">Your panel for managing the noise.</h1>
          <p className="hero-motto">
            Notes that think with you. Always close to your thoughts.
          </p>
          <p className="hero-description">
            Dictate your thoughts with automatic cleanup, in a workspace where
            AI agents can collaborate and help finish tasks with you.
          </p>

          <div className="hero-actions">
            <a className="download-link download-link-primary" {...downloadProps}>
              Download for Mac
            </a>
            <a
              className="github-link"
              href={GITHUB_URL}
              target="_blank"
              rel="noreferrer"
            >
              <img
                src="https://cdn.simpleicons.org/github/17191f"
                alt=""
                width="16"
                height="16"
              />
              View on GitHub
            </a>
          </div>
        </div>
      </section>
      <IdeasSection />
      <JourneySection />
    </main>
  );
}
