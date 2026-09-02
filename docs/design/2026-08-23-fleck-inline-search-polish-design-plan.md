# Fleck Inline Search Polish Design Plan

Date: 2026-08-23

## Intent

Polish the existing Fleck panel without replacing its navigation, editor, formatting toolbar, settings, persistence, Dictation and Cleanup integration, or menu-bar-first identity. The visible change is confined to Workspace Search and the already accepted toolbar-material correction.

Fleck should feel calmer and more native because search stays spatially connected to its top-trailing trigger, the current note remains visible, and the interface stops stacking a large centered card, border, material, and shadow over the editor.

## Current problem

The accepted search implementation is functionally strong but visually oversized. A small top-row search button morphs into a centered card up to 560 points wide, disables and hides the entire panel from interaction and accessibility, and adds a regular material, border, and 18-point shadow over an already translucent window.

The 100 ms timing is not the main problem. The transformation covers too much distance and changes too much geometry for a frequently used utility action.

| Before | After | Why |
| --- | --- | --- |
| Search button travels into a centered 560-point card | Search appears as a top-trailing surface no wider than 360 points | Search remains spatially connected to the control that opened it. |
| Shared-element shell and magnifier morph | Pointer activation uses a subtle top-trailing scale and opacity transition | The transition provides continuity without turning search into a spectacle. |
| `Command-F` participates in presentation infrastructure | `Command-F` presents instantly with focus already in the query field | Keyboard actions should feel immediate. |
| Reduce Motion uses a spatially neutral crossfade | Reduce Motion keeps only the short opacity change | No scaling or travel occurs. |
| A large surface covers most of the editor | The note remains visually present while the compact search surface occupies only the top-trailing region | Search preserves context instead of behaving like a modal editor replacement. |
| 18-point shadow and 12-point card radius | Restrained system material, 10-point radius, quaternary border, and an 8-point shadow | The surface remains legible without looking like a floating dialog. |
| Formatting toolbar uses `thinMaterial` | Formatting toolbar uses semantic `.bar` material | The existing toolbar gains clearer native separation without changing any command or layout. |

## Chosen approach

### Compact anchored overlay

Retain the existing `WorkspaceSearchController`, search engine, result rows, highlighting, keyboard navigation, focus restoration, note activation, and race protection. Reshape only the presentation:

- Align the surface to the panel's top-trailing edge.
- Limit it to 360 points and 10 points of horizontal inset.
- Start it 8 points from the top so it visually replaces the trailing header controls while open.
- Keep the existing native SwiftUI rounded text field, magnifier, and explicit close control.
- Keep results immediately below the field on the same functional material.
- Keep the full-panel transparent dismissal target so clicking outside closes search and preserves the established focus-restoration contract.
- Keep the underlying note visually available. It remains noninteractive for the duration of search so dismissing cannot restore an obsolete caret after edits made behind the search surface.

This is deliberately not a new sidebar, main window, settings redesign, or toolbar consolidation.

## Motion contract

- Pointer, Reduce Motion off: 100 ms `easeOut`, opacity plus `scale(0.98, anchor: .topTrailing)`.
- Pointer, Reduce Motion on: 100 ms opacity only.
- `Command-F`: no animation.
- Dismissal mirrors the selected presentation kind and remains interruptible through SwiftUI transitions.
- No matched geometry, spring, bounce, blur animation, width animation, or travel toward the editor center.

## Layout contract

- Normal panel width, 640 points: search surface is at most 360 points and aligned to the trailing inset.
- Minimum panel width, 380 points: search surface fits within 360 points with 10-point side insets.
- The header, folders, note tabs, formatting toolbar, title, and editor do not reflow when search appears.
- Result rows retain the existing title, excerpt, highlighting, selected state, scrolling, and 50-result limit.
- Empty and no-result messages remain concise.

## Accessibility contract

- Search receives focus immediately.
- Up, Down, Return, and Escape retain their current behavior.
- Result count, selected result, title, excerpt, and update state remain exposed.
- `Command-F` remains instant in both normal and Reduce Motion states.
- The visual transition contains no spatial movement under Reduce Motion.
- Focus and selection restore to the title or editor after dismissal and to the selected result's note after activation.

## Explicit non-goals

- No standard resizable main window.
- No sidebar or folder-navigation redesign.
- No formatting-command consolidation or Format popover.
- No command removal, reordering, shortcut change, or Delete relocation.
- No Settings redesign.
- No Dictation and Cleanup, model, security, persistence, sync, import/export, or onboarding change.
- No new dependency or deployment target change.
- No integration of prototype commits `c262ed7`, `b13ba15`, `d44beb1`, `64332f7`, `f6a2afd`, or `19d1c32`.

## Visual acceptance

Capture and inspect at least:

1. Closed search at 640 by 430 points.
2. Open empty search at 640 by 430 points.
3. Search with results at 640 by 430 points.
4. Open search at the 380-point minimum width.
5. Dark and Light appearances if automated appearance switching is available without leaving system settings changed.

The review should confirm that search reads as part of the header, the current note remains recognizable, no control is clipped, the minimum-width surface fits, and the toolbar remains unchanged except for its clearer material separation.
