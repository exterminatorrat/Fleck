# Capy

**Status: user-approved design; not implemented or visually verified.** Use a clear, waterline teal to give Fleck a warm, calm identity without turning notes into colored cards. Light remains paper-white; Dark shifts to deep green-charcoal with a soft sea-glass action color.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#101A19` |
| `sidebar` | `#F2F4F6` | `#182421` |
| `editorOpaque` | `#FFFFFF` | `#111B1A` |
| `card` | `#FFFFFF` | `#1A2725` |
| `raised` | `#FFFFFF` | `#293532` |
| `border` | `#767C82` | `#84928E` |
| `textPrimary` | `#17191C` | `#EFF8F5` |
| `textSecondary` | `#515960` | `#B6C7C2` |
| `selectionFill` | `#BDE9E2` | `#245951` |
| `selectionText` | `#0B3632` | `#F2FFFC` |
| `accent` | `#006B63` | `#74D5C8` |
| `accentText` | `#FFFFFF` | `#10302B` |
| `hoverFill` | `#E7EAED` | `#283431` |
| `focusRing` | `#006B63` | `#74D5C8` |
| `link` | `#006B63` | `#74D5C8` |
| `caption` | `#535B62` | `#A8BBB5` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#1B2926` |
| `capsuleText` | `#17191C` | `#F2FFFC` |
| `capsuleBorder` | `#767C82` | `#84928E` |

## Native application treatment

Let teal identify selection, links, keyboard focus, and genuinely primary actions; keep menu-bar notes and pinned editor chrome neutral so long text remains the focus. Settings and Dictionary use the same semantic roles, while capsule and agent/MCP surfaces use the shared paired accent and explicit status colors instead of teal-everywhere decoration.

Light, Dark, and System remain independent global appearance modes; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The supplied Appearance-menu screenshot shows only a small teal Capy swatch, not an expanded palette; the hue and all tokens here are inferred direction, not official Capy colors. Use system Liquid Glass for native functional chrome and reserve teal tint for an active or primary control. Keep the editor opaque. Pure-black/white wallpaper cannot affect text; Reduce Transparency maps glass to the matching opaque role, and Increase Contrast makes token borders/focus edges explicit with labels or icons supplementing hue.

**Evidence limit:** the screenshot cannot establish full-window color, contrast, or native rendering, and no app UI was visually verified. The approved custom colors still need rendered visual QA; no logo or website asset changes are proposed.
