const links = [
  { label: "Features", href: "#features" },
  { label: "How it works", href: "#how-it-works" },
  { label: "FAQ", href: "#faq" },
];

export default function Navigation() {
  return (
    <header className="site-header">
      <nav className="navigation" aria-label="Primary navigation">
        <a className="brand" href="/" aria-label="Fleck home">
          <img className="brand-mark" src="/fleck-mark.png" alt="" />
          <span className="brand-name">Fleck</span>
        </a>

        <a className="waitlist-link waitlist-link-mobile" href="#waitlist">
          Join waitlist
        </a>

        <div className="navigation-links">
          {links.map(({ label, href }) => (
            <a className="navigation-link" href={href} key={href}>
              {label}
            </a>
          ))}
        </div>

        <a className="waitlist-link waitlist-link-desktop" href="#waitlist">
          Join waitlist
        </a>
      </nav>
    </header>
  );
}
