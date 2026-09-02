import { useEffect, useRef, useState } from "react";

const primaryLinks = [
  { href: "/", label: "Home" },
  { href: "#features", label: "Features", title: "Features will be added next" },
  { href: "#faq", label: "FAQ", title: "FAQ will be added next" },
];

const socialLinks = [
  { href: "#github", label: "GitHub" },
  { href: "#linkedin", label: "LinkedIn" },
  { href: "#x", label: "X" },
  { href: "#contact", label: "Contact" },
];

function preventPlaceholderNavigation(event) {
  event.preventDefault();
}

export default function Navigation({ downloadProps }) {
  const [isOpen, setIsOpen] = useState(false);
  const menuRef = useRef(null);
  const menuButtonRef = useRef(null);
  const menuItemsRef = useRef([]);
  const pendingFocusRef = useRef(null);

  useEffect(() => {
    if (!isOpen) return undefined;

    function handlePointerDown(event) {
      if (!menuRef.current?.contains(event.target)) setIsOpen(false);
    }

    function handleKeyDown(event) {
      if (event.key !== "Escape") return;
      setIsOpen(false);
      menuButtonRef.current?.focus();
    }

    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || pendingFocusRef.current === null) return;
    menuItemsRef.current[pendingFocusRef.current]?.focus();
    pendingFocusRef.current = null;
  }, [isOpen]);

  function openAndFocus(index) {
    if (isOpen) {
      menuItemsRef.current[index]?.focus();
      return;
    }

    pendingFocusRef.current = index;
    setIsOpen(true);
  }

  function handleButtonKeyDown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      openAndFocus(0);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      openAndFocus(primaryLinks.length + socialLinks.length - 1);
    }
  }

  function handleMenuKeyDown(event) {
    const items = menuItemsRef.current.filter(Boolean);
    const currentIndex = items.indexOf(document.activeElement);
    let nextIndex;

    if (event.key === "ArrowDown") nextIndex = (currentIndex + 1) % items.length;
    else if (event.key === "ArrowUp") nextIndex = (currentIndex - 1 + items.length) % items.length;
    else if (event.key === "Home") nextIndex = 0;
    else if (event.key === "End") nextIndex = items.length - 1;
    else if (event.key === "Tab") {
      setIsOpen(false);
      return;
    } else return;

    event.preventDefault();
    items[nextIndex]?.focus();
  }

  return (
    <header className="site-nav">
      <nav className="site-nav-inner" aria-label="Primary navigation">
        <a className="site-brand" href="/" aria-label="Fleck home">
          <img src="/fleck-mark.png" alt="" />
          <span>Fleck</span>
        </a>

        <div className="nav-menu" data-open={isOpen} ref={menuRef}>
          <button
            className="nav-menu-button"
            id="site-menu-trigger"
            type="button"
            aria-haspopup="menu"
            aria-expanded={isOpen}
            aria-controls="site-menu-panel"
            onClick={() => setIsOpen((open) => !open)}
            onKeyDown={handleButtonKeyDown}
            ref={menuButtonRef}
          >
            <span>Menu</span>
            <span className="nav-menu-glyph" aria-hidden="true">
              <i />
              <i />
            </span>
          </button>

          <div
            className="nav-menu-panel"
            id="site-menu-panel"
            role="menu"
            aria-hidden={!isOpen}
            aria-labelledby="site-menu-trigger"
            inert={!isOpen}
            onKeyDown={handleMenuKeyDown}
          >
            <div className="nav-menu-primary">
              {primaryLinks.map((link, index) => {
                const isPlaceholder = Boolean(link.title);

                return (
                  <a
                    className="nav-menu-item"
                    href={link.href}
                    role="menuitem"
                    aria-disabled={isPlaceholder ? "true" : undefined}
                    title={link.title}
                    tabIndex={isOpen && index === 0 ? 0 : -1}
                    style={{ "--menu-index": index }}
                    onClick={isPlaceholder ? preventPlaceholderNavigation : undefined}
                    ref={(node) => { menuItemsRef.current[index] = node; }}
                    key={link.label}
                  >
                    {link.label}
                  </a>
                );
              })}
            </div>

            <div className="nav-menu-divider" role="separator" />

            <div className="nav-menu-social" role="group" aria-label="Social links">
              {socialLinks.map((link, index) => {
                const itemIndex = primaryLinks.length + index;

                return (
                  <a
                    className="nav-menu-social-link"
                    href={link.href}
                    role="menuitem"
                    aria-disabled="true"
                    title={`${link.label} link coming soon`}
                    tabIndex={-1}
                    onClick={preventPlaceholderNavigation}
                    ref={(node) => { menuItemsRef.current[itemIndex] = node; }}
                    key={link.label}
                  >
                    {link.label}
                  </a>
                );
              })}
            </div>
          </div>
        </div>

        <a className="nav-download" {...downloadProps}>
          Download for Mac
        </a>
      </nav>
    </header>
  );
}
