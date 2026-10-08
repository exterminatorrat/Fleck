# OLED

**Status: user-approved design; not implemented or visually verified.** Dark mode is true black at the window and editor canvas to switch off OLED pixels; quiet near-black navigation and a bright blue action remain legible without a charcoal haze. Light is a fully usable white-and-gray inverse, not a hidden alias to Dark.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md). The true-black requirement applies to Dark `window`, `editorOpaque`, and `card`; raised controls may be visibly separated from black.

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#000000` |
| `sidebar` | `#F2F4F6` | `#0B0B0C` |
| `editorOpaque` | `#FFFFFF` | `#000000` |
| `card` | `#FFFFFF` | `#000000` |
| `raised` | `#FFFFFF` | `#151517` |
| `border` | `#767C82` | `#777777` |
| `textPrimary` | `#17191C` | `#F5F5F7` |
| `textSecondary` | `#515960` | `#C3C3C8` |
| `selectionFill` | `#DCE4EF` | `#223957` |
| `selectionText` | `#182432` | `#F4F8FF` |
| `accent` | `#344554` | `#A8C7FA` |
| `accentText` | `#FFFFFF` | `#111A26` |
| `hoverFill` | `#E7EAED` | `#151517` |
| `focusRing` | `#344554` | `#A8C7FA` |
| `link` | `#344554` | `#A8C7FA` |
| `caption` | `#535B62` | `#B1B1B8` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#101012` |
| `capsuleText` | `#17191C` | `#F5F5F7` |
| `capsuleBorder` | `#767C82` | `#777777` |

## Native application treatment

In Dark, menu notes, pinned editor, Settings/Dictionary, and agent/MCP content sit on true-black editor/window surfaces; reserve `raised` for controls and the capsule so hierarchy does not become a ladder of grays. In Light, those same roles resolve to white content and one light-gray sidebar. Use selection, links, and status roles explicitly, not a fixed white title. Capsule glass is a functional exception to black content and must use its opaque `capsuleSurface` fallback when transparency is reduced.

Light, Dark, and System are independent global modes: OLED never coerces the mode. Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. On black or white wallpaper, text and editor content remain on opaque surfaces rather than sampling the desktop. Reduce Transparency replaces material with the exact role token; Increase Contrast uses the listed outline and focus colors, with visible boundaries and labels even against black. Standard Liquid Glass stays limited to native functional chrome, not the note body.

**Evidence limit:** the supplied screenshot shows only a small blue OLED swatch, not OLED pixels or a full-screen palette. The approved Dark black and Light inversion are design requirements, not measured or visually verified behavior.
