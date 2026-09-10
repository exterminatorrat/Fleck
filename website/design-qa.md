# Fleck hero design QA

> Historical website QA record. Its pass/block labels apply only to the dated
> implementation state described here, not the current site or a release. See
> [`docs/archive/README.md`](../docs/archive/README.md).

- Desktop screenshot: `design-qa-hero-desktop.png`
- Mobile screenshot: `design-qa-hero-mobile.png`
- Desktop viewport: 1440 × 1000 px.
- Mobile viewport: 390 × 844 px.

## Findings

- The hero contains the interactive dots-and-connections canvas used by the
  Sites version, with no generated brain image behind it.
- Pointer movement gently displaces nearby nodes and edges; touch interaction
  stays disabled and reduced motion renders a static network.
- Existing navigation, hero copy, and download/GitHub actions are unchanged.
- The centered content remains readable at desktop and mobile breakpoints.
- Mobile has no horizontal overflow.
- The browser console reports no warnings or errors.

## Final result

final result: passed

---

# Fleck Ideas section design QA

- Desktop section capture: `design-qa-ideas-desktop.png`
- Mobile focused capture: `design-qa-ideas-mobile.png`
- Desktop/mobile comparison: `design-qa-ideas-comparison.png`
- Desktop viewport: 1440 × 1000 px; section crop: 1440 × 1242 px.
- Mobile viewport: 390 × 844 px.
- Real product asset: `public/assets/fleck-ideas-capture.png`, 520 × 190 px.

## Product capture provenance

- Built Fleck with `Scripts/build-fleck-app.sh` and opened the resulting
  `.build/Fleck.app`.
- Created a dedicated `Website Demo` testing tab to the right of the protected
  personal tab and entered only the approved onboarding demo thought.
- Captured the live Fleck editor and cropped out every unrelated tab name. The
  final PNG preserves the real toolbar, title, editor typography, and text; it
  contains no generated or HTML-recreated product UI.

## Findings

- The approved heading and body introduce a four-stage semantic ordered list.
- Desktop uses an 1180 px editorial grid with a continuous violet path, quiet
  dividers, compact tool labels, and the genuine Fleck capture as the resolution.
- The one-shot observer changed the section from `is-animatable` to
  `is-animatable is-visible` after entry and did not trap page scrolling.
- At 390 px, all four rows stack in order, the product crop renders at 322 px,
  and `document.documentElement.scrollWidth` remains exactly 390 px.
- The Fleck asset loaded at its native 520 × 190 px dimensions in both tested
  layouts.
- The reduced-motion media block was inspected at runtime and sets Ideas content
  to full opacity with no animation, transform, or transition; the test machine's
  operating-system preference remained off during the capture.
- Browser console warnings and errors: none.
- The current hero and navigation were not edited as part of this section.

## Final result

final result: passed

---

# Fleck capture-through-finish section design QA

- Reference: `docs/design/references/fleck-website-approved-direction-2026-08-01.png`.
- Product image: the existing sanitized capture from the live Fleck macOS app.
- Production deployment completed successfully with the new section.
- The section contract, full website tests, production build, and diff check pass.
- Automated visual comparison is blocked: the in-app browser rejected the local
  preview URL and timed out while refreshing and capturing the authenticated
  Sites page. No alternate browser surface was used.
- Desktop and mobile screenshots were therefore not captured in this pass.

## Final result

final result: blocked
