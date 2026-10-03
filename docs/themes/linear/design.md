# Linear

**Status: user-approved design; not implemented or visually verified.** Keep the workspace composed and low-noise: crisp paper-white writing in Light, deep graphite in Dark, and a custom soft indigo accent for focus and selected state. Hierarchy comes from typography and spacing, not more panels.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#161619` |
| `sidebar` | `#F2F4F6` | `#1F1F23` |
| `editorOpaque` | `#FFFFFF` | `#17171A` |
| `card` | `#FFFFFF` | `#202024` |
| `raised` | `#FFFFFF` | `#2D2D33` |
| `border` | `#767C82` | `#8C8C96` |
| `textPrimary` | `#17191C` | `#F2F2F7` |
| `textSecondary` | `#515960` | `#C0BEC9` |
| `selectionFill` | `#E1DCFF` | `#423865` |
| `selectionText` | `#2B2358` | `#F5F2FF` |
| `accent` | `#5547A5` | `#C0B6FF` |
| `accentText` | `#FFFFFF` | `#231A4E` |
| `hoverFill` | `#E7EAED` | `#2A2A30` |
| `focusRing` | `#5547A5` | `#C0B6FF` |
| `link` | `#5547A5` | `#C0B6FF` |
| `caption` | `#535B62` | `#AEACB9` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#202024` |
| `capsuleText` | `#17191C` | `#F2F2F7` |
| `capsuleBorder` | `#767C82` | `#8C8C96` |

## Native application treatment

Use indigo sparingly for links, selection, focus, and one primary action. Keep menu notes, pinned-editor chrome, Settings, and Dictionary clean and stable; avoid turning the page into a tinted card grid. The capsule is functional chrome and may use a subtle indigo active cue. Agent/MCP output remains neutral except for its explicitly labeled semantic states.

Light, Dark, and System are global modes, never separate palette families; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The supplied screenshot shows only a small purple Linear swatch. The accent is an original native Fleck color, informed by restrained color and breathing room rather than a reproduction of Linear UI. Preserve system Liquid Glass for functional chrome, keep editor content opaque, and tint glass only to convey an important state. Pure-black/white wallpaper does not affect text; Reduce Transparency selects the opaque token fallback, and Increase Contrast emphasizes the listed border/focus outline and retains textual or icon cues.

**Evidence and reference:** the screenshot is a menu-only swatch, not a visual test. Linear’s [public brand guidelines](https://linear.app/brand) describe generous space and a subtle desaturated blue; these tokens are independent and no Linear assets or exact colors are used.
