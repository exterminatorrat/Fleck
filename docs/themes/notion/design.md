# Notion

**Status: user-approved design; not implemented or visually verified.** An editorial writing surface: white paper, a calm gray navigation rail, and ink-first text with a muted blue action/link color. Keep native Fleck’s notes, Dictionary, and editor easy to scan without importing a website layout or block styling.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#15191A` |
| `sidebar` | `#F2F4F6` | `#1E2224` |
| `editorOpaque` | `#FFFFFF` | `#161A1B` |
| `card` | `#FFFFFF` | `#1E2224` |
| `raised` | `#FFFFFF` | `#292E30` |
| `border` | `#767C82` | `#899093` |
| `textPrimary` | `#17191C` | `#F3F5F4` |
| `textSecondary` | `#515960` | `#B9C0BE` |
| `selectionFill` | `#D8E6F1` | `#224565` |
| `selectionText` | `#172A3A` | `#F1F8FD` |
| `accent` | `#365978` | `#91C8F2` |
| `accentText` | `#FFFFFF` | `#142536` |
| `hoverFill` | `#E7EAED` | `#282E30` |
| `focusRing` | `#365978` | `#91C8F2` |
| `link` | `#365978` | `#91C8F2` |
| `caption` | `#535B62` | `#A9B1AF` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#1E2224` |
| `capsuleText` | `#17191C` | `#F3F5F4` |
| `capsuleBorder` | `#767C82` | `#899093` |

## Native application treatment

Give menu notes and the pinned editor the same clear ink-on-white or ink-on-dark hierarchy; selection uses its paired fill/text, not a white-on-light title shortcut. Settings and Dictionary use the same editorial surface roles without a copied block grid. Capsule and agent/MCP surfaces stay compact and semantic, with blue reserved for links or primary/focused interaction.

Light, Dark, and System are independent global modes; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The menu screenshot’s small blue Notion swatch is not a specification for these surfaces. The direction draws on Notion’s public description of a quiet place to think, write, and plan with flexible building blocks, not a proprietary token set or website appearance. Retain macOS Liquid Glass only on native functional chrome; the editor remains opaque. Text is always on its explicit token surface over either black or white wallpaper. Reduce Transparency substitutes the matching opaque role token; Increase Contrast strengthens visible borders and focus edges without relying on blue alone.

**Evidence and reference:** no supplied screenshot shows a Notion-themed native Fleck window, so the approved colors still need rendered contrast and visual QA. See Notion’s public [What is Notion? guide](https://www.notion.com/help/guides/what-is-notion); no Notion logo or website assets are changed.
