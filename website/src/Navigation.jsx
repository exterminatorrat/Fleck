export default function Navigation({ downloadProps }) {
  return (
    <header className="site-header">
      <nav className="navigation" aria-label="Primary navigation">
        <a className="brand" href="/" aria-label="Fleck home">
          <img className="brand-mark" src="/fleck-mark.png" alt="" />
          <span className="brand-name">Fleck</span>
        </a>

        <a className="download-link download-link-header" {...downloadProps}>
          Download for Mac
        </a>
      </nav>
    </header>
  );
}
