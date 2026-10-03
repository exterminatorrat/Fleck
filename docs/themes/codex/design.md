# Codex

**Status: user-approved design; not implemented or visually verified.** A focused azure-cyan action color sits on cool, deep slate; it reads as deliberate tool feedback rather than a promotional brand surface. Light stays white and restrained so the editor remains the working canvas.

## Semantic tokens

Opaque sRGB defaults; appearance and override behavior follow the shared [token contract](../README.md).

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#101922` |
| `sidebar` | `#F2F4F6` | `#18232B` |
| `editorOpaque` | `#FFFFFF` | `#111A22` |
| `card` | `#FFFFFF` | `#1B252D` |
| `raised` | `#FFFFFF` | `#28363F` |
| `border` | `#767C82` | `#84939D` |
| `textPrimary` | `#17191C` | `#F0F7FA` |
| `textSecondary` | `#515960` | `#B8C7CD` |
| `selectionFill` | `#CCEBF6` | `#1B495C` |
| `selectionText` | `#103548` | `#EDF9FF` |
| `accent` | `#0D648B` | `#83D1F1` |
| `accentText` | `#FFFFFF` | `#12303B` |
| `hoverFill` | `#E7EAED` | `#273842` |
| `focusRing` | `#0D648B` | `#83D1F1` |
| `link` | `#0D648B` | `#83D1F1` |
| `caption` | `#535B62` | `#A8BAC1` |
| `success` | `#216E3A` | `#77D99B` |
| `warning` | `#825300` | `#FFD166` |
| `error` | `#B42318` | `#FF8580` |
| `capsuleSurface` | `#FFFFFF` | `#1A252D` |
| `capsuleText` | `#17191C` | `#F0F7FA` |
| `capsuleBorder` | `#767C82` | `#84939D` |

## Native application treatment

Use the azure-cyan accent on a selected item, focus ring, link, or primary action, not as a background for every note. Menu notes and pinned editor use the same token pair; Settings and Dictionary retain the native white-content/gray-sidebar hierarchy. The capsule may show a quiet blue active cue, while agent/MCP success, warning, and error keep their semantic colors.

Light, Dark, and System stay global modes; Appearance offers this palette family and the global mode, but no separate Accent color, Editor text color, or Editor background controls. All native Fleck surfaces use these palette tokens. Previously saved values for those three settings remain intact for lossless compatibility but are dormant and not applied while this named palette is selected. Per-note tab colors remain note-content metadata across palette changes; for a tab using its stored fill, choose selection ink against that actual fill at 4.5:1 or better rather than assuming white or black from the mode. The supplied screenshot contains only a small blue Codex swatch; the cyan-leaning direction and exact tokens are inferred from that UI chip, not official Codex palette values. Keep content opaque and Liquid Glass to functional native chrome; do not imitate a website. Black/white wallpaper never backs text. Reduce Transparency uses role-matched opaque surfaces, and Increase Contrast reinforces borders/focus outlines and keeps state cues readable without color alone.

**Evidence limit:** the screenshot has no expanded note, Settings, editor, capsule, or agent/MCP surface. This user-approved native Fleck design is not a Codex brand reproduction, and no UI was rendered for verification.
