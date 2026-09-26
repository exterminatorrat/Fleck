# Fleck Monochrome

**Status: user-approved design; not implemented or visually verified.** This is the quiet house palette: graphite structure, paper-white writing, and no decorative color hierarchy. Dark is charcoal, not pure black; Light uses white content and one gray sidebar. This is a native Fleck treatment, not a claim about a web theme.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#18191A` |
| `sidebar` | `#F2F4F6` | `#222426` |
| `editorOpaque` | `#FFFFFF` | `#191A1B` |
| `card` | `#FFFFFF` | `#212224` |
| `raised` | `#FFFFFF` | `#2B2D30` |
| `border` | `#767C82` | `#888D92` |
| `textPrimary` | `#17191C` | `#F2F2F0` |
| `textSecondary` | `#515960` | `#BCC0C3` |
| `selectionFill` | `#D8DBDE` | `#3B3E42` |
| `selectionText` | `#17191C` | `#F5F5F2` |
| `accent` | `#42474D` | `#D4D7DA` |
| `accentText` | `#FFFFFF` | `#202224` |
| `hoverFill` | `#E7EAED` | `#2A2C2F` |
| `focusRing` | `#42474D` | `#D4D7DA` |
| `link` | `#42474D` | `#D4D7DA` |
| `caption` | `#535B62` | `#AEB3B7` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#242628` |
| `capsuleText` | `#17191C` | `#F2F2F0` |
| `capsuleBorder` | `#767C82` | `#888D92` |

## Native application treatment

Keep menu-bar notes and the pinned editor quiet: use `sidebar` for navigation, `editorOpaque` for writing, and `selectionFill` with its paired text rather than hard-coded white selected titles. Settings and Dictionary use the same white content surface and graphite hierarchy. The capsule gets the matching neutral surface and a restrained accent only for active/focused states. Agent/MCP surfaces keep status semantic; success, warning, and error are labels/icons, not extra colored panels.

Light, Dark, and System are global modes for this family; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The screenshot contains no Monochrome surface sample, so this is a fresh design rather than a reading of its colors. Keep native toolbar/sidebar Liquid Glass in the functional chrome, not the editor; never tint the glass merely to make the palette feel colorful. Against black or white wallpaper, opaque window/editor tokens keep text independent of the desktop. Reduce Transparency replaces material with the matching token surface; Increase Contrast strengthens the existing border/focus outline without adding translucent overlays or relying on color alone.

**Evidence limit:** no supplied image shows a Monochrome window, editor, or capsule, and no native implementation was visually inspected. The approved tokens and surface behavior still need rendered visual QA.
