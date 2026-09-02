import Navigation from "./Navigation";
import HeroStory from "./HeroStory";

const APP_STORE_URL = import.meta.env.VITE_APP_STORE_URL?.trim();

function preventUnavailableDownload(event) {
  if (!APP_STORE_URL) event.preventDefault();
}

export default function App() {
  const downloadProps = {
    href: APP_STORE_URL || "#download",
    onClick: preventUnavailableDownload,
    ...(APP_STORE_URL
      ? { target: "_blank", rel: "noreferrer" }
      : {
          "aria-disabled": "true",
          title: "Fleck is not yet available in the Mac App Store",
        }),
  };

  return (
    <div className="page">
      <Navigation downloadProps={downloadProps} />
      <main>
        <HeroStory downloadProps={downloadProps} />
      </main>
    </div>
  );
}
