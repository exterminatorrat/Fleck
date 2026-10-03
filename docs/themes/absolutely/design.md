# Absolutely

**Status: user-approved design; not implemented or visually verified.** A warm coral-red accent adds a little momentum to the native Fleck workspace while graphite and white keep writing calm. Color marks actions and active state, not a stack of decorative panels.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#1B1513` |
| `sidebar` | `#F2F4F6` | `#261D1A` |
| `editorOpaque` | `#FFFFFF` | `#1C1614` |
| `card` | `#FFFFFF` | `#261E1A` |
| `raised` | `#FFFFFF` | `#342923` |
| `border` | `#767C82` | `#8F807A` |
| `textPrimary` | `#17191C` | `#FFF4EF` |
| `textSecondary` | `#515960` | `#D0BEB5` |
| `selectionFill` | `#FFD7C8` | `#77382B` |
| `selectionText` | `#3B170E` | `#FFF3ED` |
| `accent` | `#A33C2D` | `#FF9B7A` |
| `accentText` | `#FFFFFF` | `#33150E` |
| `hoverFill` | `#E7EAED` | `#30241F` |
| `focusRing` | `#A33C2D` | `#FF9B7A` |
| `link` | `#A33C2D` | `#FF9B7A` |
| `caption` | `#535B62` | `#C1AEA5` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#291F1B` |
| `capsuleText` | `#17191C` | `#FFF4EF` |
| `capsuleBorder` | `#767C82` | `#8F807A` |

## Native application treatment

Use coral for a selected note, link, focus ring, and the single prominent action; keep menu notes, editor chrome, Settings, and Dictionary on their neutral role surfaces. Pinned notes use the same selection pairing as the menu. The capsule can use a restrained coral indicator for a meaningful active state, while agent/MCP status remains green/amber/red semantic feedback rather than an all-coral treatment.

Light, Dark, and System are global modes, not variants of the palette; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The screenshot shows only a small coral Absolutely swatch; the warm red direction is inferred from that chip, not an official Absolutely token set. Let native Liquid Glass remain functional chrome and keep the editor opaque. On white or black wallpaper, all text stays on token surfaces; Reduce Transparency swaps to the defined opaque surface, and Increase Contrast strengthens borders and focus outlines while retaining text/icons alongside color.

**Evidence limit:** the provided menu crop does not show notes, settings, the capsule, or colors in context. No logo or website asset is changed, and the approved values have not been visually verified in native UI.
