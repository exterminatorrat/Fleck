# Fleck Settings Sidebar Design

**Status:** Approved for implementation
**Baseline:** `d6facac` (`codex/dictation-vocabulary-runtime-polish`)
**Platform:** macOS 14+, with native Liquid Glass treatment on supported macOS releases

## Objective

Replace Fleck's cramped top settings selector with a spacious, familiar macOS settings window. The result should make all six settings destinations immediately discoverable, keep the current settings behavior intact, and feel at home beside modern menu-bar utilities such as Stats and the Codex desktop app.

Success means:

- navigation is persistent in a left sidebar;
- the selected settings page is readable in a wider right detail pane;
- each page scrolls independently without moving the sidebar;
- macOS supplies the sidebar material and selection treatment;
- every existing preference, runtime binding, pending route, and shortcut-recording behavior still works;
- the layout remains usable at the minimum window size and with accessibility text sizes.

## Information Architecture

Use one `NavigationSplitView` with a selection-backed sidebar `List`.

### Fleck

- General — existing Editing settings
- Appearance
- Shortcuts

### Voice & Writing

- Dictation
- Vocabulary

### Connections

- Agents

Keep the durable enum case `.editing` so pending routes and existing interfaces do not change. Only its user-facing title becomes **General**.

## Layout

- Default window: approximately 840 × 600 points.
- Minimum usable window: 760 × 520 points.
- Sidebar: 180–230 points, approximately 200 points at rest.
- Detail: a fixed page header above an independently scrolling grouped `Form`.
- Page header: destination title plus one short explanatory sentence.
- Sidebar rows: SF Symbol, concise title, native selection highlight.
- Navigation changes are immediate. Do not animate routine sidebar selection or rebuild the detail view with a transition.

## Liquid Glass Treatment

Use the standard macOS `NavigationSplitView`, sidebar `List`, and titlebar. On systems that provide Liquid Glass, those structures receive the platform's current translucent material, vibrancy, edge treatment, and selection appearance automatically. On older supported systems they retain the native sidebar material.

Do not add `.glassEffect`, an opaque sidebar fill, a custom `NSVisualEffectView`, decorative glass cards, custom selection capsules, or blur overlays. Controls and grouped forms stay on the higher-contrast detail surface so labels and values remain legible.

## Page Copy

- General — “Choose how Fleck edits and organizes your notes.”
- Appearance — “Adjust Fleck’s editor theme, type, and accent.”
- Shortcuts — “Set the keyboard shortcuts you use across Fleck.”
- Dictation — “Configure voice capture, models, microphones, and history.”
- Vocabulary — “Teach Fleck the words and spellings that matter to you.”
- Agents — “Control which local agents can work with your Fleck workspace.”

## Behavior and State Invariants

- Preserve the current initial selection unless a pending runtime route overrides it.
- Preserve `DictationRuntime.pendingSettingsSection` consumption exactly once.
- Preserve cancellation of an active shortcut recording when leaving Shortcuts or closing Settings.
- Preserve all existing `AppState`, login-item, dictation, microphone, model, vocabulary, history, and agent bindings.
- Preserve the floating Settings window configuration.
- Do not move individual settings into new destinations during this change.

## Accessibility

- The sidebar must expose a clear “Settings sections” accessibility label.
- Every destination row must expose its visible title and native selected state.
- The minimum-size sidebar must not clip visible descendants at normal or accessibility text sizes.
- Page title and description must remain readable semantic text, not a drawn image.
- Native keyboard navigation and focus behavior must come from `List(selection:)` and `NavigationSplitView`.

## Non-goals

- No new preferences, search field, accounts UI, privacy controls, or onboarding.
- No redesign of the controls inside Appearance, General, Shortcuts, Dictation, Vocabulary, or Agents.
- No persistence or model-layer changes.
- No custom design system or reusable glass abstraction.
- No Figma artifact and no generated mockup; the native SwiftUI window is the design artifact.
- No push, pull request, merge, installation over `/Applications/Fleck.app`, or publication.

## Verification

1. Replace the selector tests with hosted sidebar layout and accessibility contracts; observe the new tests fail before production changes.
2. Run the focused Settings/Dictation, vocabulary, shortcuts, appearance, agents, and window tests.
3. Run `Scripts/validate-macos.sh` and a release build.
4. Inspect the full diff for preserved state bindings and limited scope.
5. Capture the actual redesigned Settings window at default and minimum sizes in Light and Dark appearances when a uniquely identifiable local build can be launched without replacing the installed Fleck app.
6. Require a fresh Sol reviewer verdict of `ship` before completion.
