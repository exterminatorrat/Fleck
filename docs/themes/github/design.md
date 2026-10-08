# GitHub

**Status: user-approved design; not implemented or visually verified.** A compact, technical palette pairs a restrained collaboration blue with familiar cool neutrals. The palette is designed for Fleck’s native notes and editor, not as a copy of GitHub’s website or interface.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#0D1117` |
| `sidebar` | `#F2F4F6` | `#161B22` |
| `editorOpaque` | `#FFFFFF` | `#0D1117` |
| `card` | `#FFFFFF` | `#161B22` |
| `raised` | `#FFFFFF` | `#21262D` |
| `border` | `#767C82` | `#8B949E` |
| `textPrimary` | `#17191C` | `#F0F6FC` |
| `textSecondary` | `#515960` | `#B1BAC4` |
| `selectionFill` | `#CFE5FF` | `#153D69` |
| `selectionText` | `#112C4A` | `#E9F4FF` |
| `accent` | `#135FA7` | `#79C0FF` |
| `accentText` | `#FFFFFF` | `#10243A` |
| `hoverFill` | `#E7EAED` | `#202732` |
| `focusRing` | `#135FA7` | `#79C0FF` |
| `link` | `#135FA7` | `#79C0FF` |
| `caption` | `#535B62` | `#A6AFB9` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#161B22` |
| `capsuleText` | `#17191C` | `#F0F6FC` |
| `capsuleBorder` | `#767C82` | `#8B949E` |

## Native application treatment

Menu notes and pinned editor use the blue accent for selection, links, and focus; keep persistent note rows and editor surfaces neutral. Settings and Dictionary keep the same semantic hierarchy. The capsule uses its dedicated surface and only a prominent blue cue for an active or primary interaction. Agent/MCP states use explicit success/warning/error roles, never “green means good” without a label or icon.

Light, Dark, and System remain global appearance modes; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The screenshot offers only a tiny blue GitHub swatch, not a full Fleck UI. Draw on the public idea of role-based, mode-aware semantics, not its literal palette or site styling. Keep the editor opaque; standard system Liquid Glass belongs to functional toolbar/sidebar chrome. Black and white wallpaper cannot change the foreground; Reduce Transparency uses opaque role tokens, while Increase Contrast strengthens boundaries and focus without removing non-color cues.

**Evidence and reference:** the menu crop does not show the palette on any Fleck surface and no native UI was visually checked. GitHub’s public [Primer color-usage guide](https://primer.style/product/getting-started/foundations/color-usage/) documents role-based tokens and light/dark semantics; this approved set uses original values, not copied Primer tokens.
