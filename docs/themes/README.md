# Fleck native palette designs

These nine documents define the approved designs and shared appearance contract for Fleck's eight
native palette families. `Sources/FleckCore/FleckTheme.swift` is the semantic token implementation,
and the native app resolves one palette snapshot for its scenes and capsule. Automated tests check
document/token parity, contrast, persistence, and source-level propagation; they do not replace visual
QA, which is not claimed here.

## Palette families

Appearance mode is global and independent of the selected palette. The eight families are [Fleck Monochrome](monochrome/design.md), [Capy](capy/design.md), [Absolutely](absolutely/design.md), [OLED](oled/design.md), [Codex](codex/design.md), [GitHub](github/design.md), [Linear](linear/design.md), and [Notion](notion/design.md). Light, Dark, and System are modes of each family, not additional families.

## Shared token contract

Each palette supplies the same semantic roles for Light and Dark. Hex values are opaque sRGB `#RRGGBB`; do not store alpha in a surface token or let wallpaper color influence text. Token names are shared across all eight designs:

| Token | Role |
| --- | --- |
| `window` | Opaque base for a native app window or settings page. |
| `sidebar` | Opaque navigation and note-list column; the single light-gray structural surface in Light. |
| `editorOpaque` | Opaque writing canvas, including inverse/editor-specific canvases. |
| `card` | Opaque, quiet container; in Light it stays white rather than introducing another gray tier. |
| `raised` | Opaque transient or elevated surface; in Light it also stays white. |
| `border` | Opaque boundary for controls and grouped content. |
| `textPrimary`, `textSecondary`, `caption` | Text hierarchy; secondary and caption values remain readable on every named opaque surface. |
| `selectionFill`, `selectionText` | A paired, contrast-safe selection treatment. |
| `accent`, `accentText` | Paired action/focus accent and its foreground. |
| `hoverFill` | Transient hover row/control fill, not a persistent card tier. |
| `focusRing` | Keyboard and pointer focus outline; never rely on hue alone. |
| `link` | Link foreground, paired with a non-color cue such as underline. |
| `success`, `warning`, `error` | Semantic foreground colors for status labels and icons, not background fills. |
| `capsuleSurface`, `capsuleText`, `capsuleBorder` | Matched foreground and opaque fallback for Fleck’s native capsule. |

Palette tokens own appearance colors across every native Fleck surface. Appearance exposes the selected palette family and the global Light, Dark, or System mode; it does not expose separate Accent color, Editor text color, or Editor background controls. Existing saved values for those three settings must remain byte-for-byte intact for lossless compatibility, but stay dormant and must not be applied while a named palette is selected. Do not delete, rewrite, migrate, or show those dormant values as controls.

Per-note tab colors are note-content metadata, not global appearance preferences. Preserve them with their notes across palette and appearance changes; they may tint only their own tab, never the app-wide token snapshot. Choose selected-tab ink against the actual tab fill to maintain at least 4.5:1 contrast instead of assuming white or black from the appearance mode. Palette-colored selections use the paired `selectionFill` and `selectionText` tokens.

## Appearance and whole-window propagation

Resolve one immutable semantic theme snapshot from the selected palette, global appearance mode, active system appearance, and accessibility settings. Do not layer dormant custom accent/editor values into it. Inject the snapshot once at each native scene root and use it for menu-bar notes, the pinned editor and chrome, Settings including Dictionary, the capsule, and agent/MCP surfaces. SwiftUI and AppKit-backed editor/capsule surfaces must receive the same resolved values; individual controls must not fetch or asynchronously repaint colors on their own.

For a palette or appearance change, compute the replacement snapshot synchronously on the main actor, publish it as one scene-level value, and disable implicit/per-card animations for that swap. A window must not show a staggered mixture of old and new tokens. All open windows should be sent the same snapshot revision, but separate native OS windows have independent scene/render lifecycles: the design promises consistency within each window and shared logical state, not frame-perfect, cross-window atomic presentation.

System follows the current macOS appearance; explicit Light and Dark stay fixed when the system changes. OLED Dark uses true black for its window and editor canvas, while OLED Light uses the same valid white/gray inverse as any other palette. Selecting OLED never forces Dark or changes the global appearance mode.

## Native material and accessibility rules

Keep editor and document content opaque. Use standard macOS toolbar, sidebar, menu, and sheet materials for their functional chrome rather than painting a theme-colored slab over Liquid Glass; use custom glass sparingly for functional floating controls such as the capsule, with accent tint only when it communicates an active or primary state. Do not put glass over the editor body or use wallpaper as a text backdrop. With Reduce Transparency, replace each material with its matching opaque token surface. With Increase Contrast, retain opaque tokens, make boundaries and focus indicators more explicit, and preserve semantic cues beyond color. These rules keep text and controls stable over both black and white wallpaper.

Apple’s public guidance treats Liquid Glass as a functional layer for navigation and controls, not the content layer: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

## Verification checklist

- Require at least 4.5:1 for body/small text and semantic text tokens on every opaque surface, plus at least 3:1 for non-text UI graphics, borders, focus rings, and state boundaries. Check both foreground/background pairs, including `selectionText`/`selectionFill`, `accentText`/`accent`, capsule pairs, links, captions, and status colors; do not test only against the window background.
- Regress the selected-note title’s white-on-light failure in `NotesPanel.swift:1572–1574` for selected and unselected note tabs in every palette. Retain per-note tab-color metadata and verify selection ink has at least 4.5:1 contrast on each actual tab fill. Verify Settings receives the same appearance and palette as Notes, including its Dictionary section; specifically cover the Settings-scene `preferredColorScheme` propagation gap in `FleckApp.swift` and confirm the three color controls are absent.
- Verify theme and appearance preference round-trip plus migration from existing saved preferences. Assert legacy Accent color, Editor text color, and Editor background values remain unchanged but dormant while a named palette is active; assert a palette switch never applies, erases, or exposes them.
- Check note links, caret, selection, and checklist mark on inverse editor canvases; System-mode appearance changes; Light/Dark stability; and multiple open windows. Assert one coherent snapshot per window and do not claim cross-window pixel atomicity.
- Exercise pure-black and pure-white wallpaper, Reduce Transparency, and Increase Contrast. Confirm opaque fallbacks and visible labels/focus outlines in menu notes, pinned editor/chrome, Settings/Dictionary, capsule, and agent/MCP surfaces.

Automated tests currently verify the documented tokens for all eight families in Light and Dark,
text and interface contrast, the shared snapshot's native propagation, legacy preference retention,
and removal of duplicate global color controls. The remaining checklist covers behavior and rendered
appearance that source assertions cannot prove. No visual QA or local handoff is claimed here.
