# Fleck Native Interface and Motion System Design

## Status

Proposed design specification for review. This document defines the UI and motion direction; it does not authorize product-code implementation, GitHub writes, or changes to the separate Dictation and Cleanup program.

## Executive vision

Fleck should feel like a quiet physical workspace that happens to live in the menu bar. The note is the stable object. Navigation, search, formatting, feedback, and supporting sheets should appear to unfold from the user's action, preserve spatial context, and settle quickly enough that the user notices confidence rather than choreography.

The goal is not to make Fleck “more animated.” The goal is to make every transition answer one of four questions:

1. What changed?
2. Where did it come from?
3. Where did it go?
4. Is the app ready for the next action?

When motion cannot answer one of those questions, Fleck should remain still.

This program polishes the accepted application instead of revamping it. It preserves Fleck's existing panel structure, commands, editor behavior, toolbar order, folders, tabs, search semantics, sheets, shortcuts, and local-first architecture. It introduces a consistent motion and material contract, then applies that contract surface by surface through bounded, independently reviewed tasks.

## Scope

### Included

- A unified native macOS motion policy for SwiftUI and the small AppKit bridge points that need it.
- Purposeful transitions for panel chrome, folders, tabs, search, menus, popovers, backlinks, notices, save feedback, Trash, Settings, Agent Activity, onboarding, and destructive confirmation.
- A restrained material hierarchy, including conditional modern Liquid Glass behavior where the deployment environment supports it and faithful material fallbacks on macOS 14 and later.
- Interaction-source awareness so pointer interactions may preserve spatial continuity while keyboard commands remain immediate.
- Reduce Motion, Reduce Transparency, increased contrast, VoiceOver, keyboard navigation, localization, and scaling behavior.
- Performance budgets, visual capture requirements, durability checks, packaged-app provenance, and a serial integration strategy.
- Explicit translation of the useful ideas from Beautiful UI, beUI, Rare UI, Transitions.dev, and shadcn/ui into native Fleck behavior.

### Explicit non-goals

- No redesign of dictation recognition, cleanup, enhanced models, routing, model installation, waveform behavior, or dictation policy. Those remain owned by the separate Dictation and Cleanup program.
- No removal, reordering, consolidation, or hiding of accepted toolbar commands.
- No Format popover replacing the existing formatting bar.
- No migration from the menu-bar panel to a completely different application shell in this program.
- No web framework, React component, Tailwind class, Framer Motion dependency, WebGL effect, copied source code, or third-party UI runtime inside Fleck.
- No decorative ambient animation, parallax, mouse-following tilt, confetti, shimmer on static content, or animated gradients.
- No custom scrollbars, custom window controls, nonstandard sheets, or recreated system menus.
- No animation of typed text, caret movement, selection, editor layout, Undo/Redo, paste, checklist typing, search keystrokes, or window resizing.
- No StoreKit, licensing, iCloud, cybersecurity, website, or broader roadmap work.

## Confirmed product direction

Fleck's default design register is **product**, with a restrained color strategy and the personality **calm, capable, native**. The physical scene is a Mac user moving between a quick menu-bar capture and a longer focused editing session, often in the same day and sometimes dozens of times. The interface must work in bright daytime light, dim evening environments, and both system appearances without choosing spectacle over legibility.

Three anchors define the intended feel:

- **macOS first-party applications:** structural familiarity, predictable focus, semantic materials, system controls, and restrained feedback.
- **Raycast-like immediacy:** repeated keyboard workflows do not wait for animation.
- **The reviewed reference libraries:** use their best continuity, state, and component ideas as inspiration, but translate them into Fleck's native hierarchy and interaction frequency.

## Target experience walkthrough

This is the intended lived experience after the program is integrated—not a scripted demo and not a requirement that every moment animate.

### Capture in one breath

The user invokes Fleck from the menu bar. The panel is ready immediately, with the last meaningful workspace state intact and the insertion point where the user expects it. There is no opening flourish competing with the thought being captured. A toolbar press gives one quiet physical response; typing, paste, lists, checklists, Undo, and Redo remain instant. Persistence feedback is concise and truthful, never a theatrical loading sequence.

### Turn a thought into working material

The user pins the panel and continues writing. A folder disclosure preserves the row's identity and reveals its contents without shifting the note unpredictably. A newly opened note becomes a stable tab; the selection capsule carries continuity between tabs while the editor focus and scroll position remain correct. Formatting controls retain their exact commands and geometry, but their material separation reads as intentional chrome rather than a washed-out band.

### Retrieve without losing place

With the pointer, Search appears to grow from the search affordance into the accepted Spotlight-like surface. With the keyboard, the same surface is simply ready—no waiting for the morph. Results are dense, calm, and navigable; preview and count changes do not cause layout churn. Closing Search returns focus and context to the same note. Internal links and backlinks follow the same continuity rules without permanently occupying editor space.

### Understand what Fleck did

A recoverable suggestion or error appears beneath the relevant chrome, states one actionable fact, and can be dismissed without stealing focus. Repeated notices coalesce instead of stacking into clutter. Agent changes disclose provenance and recovery actions without turning the note into an activity dashboard. VoiceOver receives the same state change once, at the moment it becomes actionable.

### Recover with confidence

Trash, destructive confirmation, import, export, and recovery behave like native macOS destinations. A deleted note leaves the active workspace cleanly, selection advances deterministically, and the item remains visibly recoverable. Restoration returns the same note object rather than presenting a visually unrelated copy. The system favors clarity and reversibility over dramatic delete effects.

## Design values

### The editor is the still point

The note title and body form Fleck's visual anchor. Everything else may react around them, but the writing surface must not drift, bounce, blur, resize unexpectedly, or lose focus. Motion is allowed to clarify chrome state; it is not allowed to compete with the sentence being written.

### Continuity beats entrance effects

Fleck should prefer a persistent object moving or changing shape over an unrelated object fading in elsewhere. A selected tab capsule glides to the next tab. A pointer-opened search surface grows from the search affordance. A popover opens from its trigger. A banner enters from the edge it occupies. This is continuity, not animation for its own sake.

### Frequency determines intensity

| Interaction frequency | Fleck policy | Examples |
| --- | --- | --- |
| Constant or keyboard-repeated | Instant | Typing, Undo/Redo, Command-F presentation, note activation by keyboard, formatting shortcuts |
| Frequent | 80–140 ms, color/opacity or tiny press feedback | Toolbar press, hover, selected formatting state, row highlight |
| Occasional | 140–220 ms, restrained spatial continuity | Pointer-opened search, folder disclosure, formatting-bar reveal, popover, tab insertion |
| Rare and consequential | 180–280 ms, clear state transition | Delete confirmation, onboarding step, recovery surface, completion of a long operation |

### Exit is faster than entrance

Dismissal communicates that Fleck heard the user. Escape, close, cancel, and pointer-away dismissal must complete immediately or faster than the corresponding entrance. No surface should finish an elaborate exit after the user has already returned to writing.

### Stable identity is a correctness requirement

Motion relies on stable note, folder, result, notice, and task identifiers. If an item changes order, selection follows its identity rather than an array index. Animation must never become the owner of state and must never conceal a stale or deleted object.

## Reference integration matrix

The five reference sites are inputs, not templates. Every borrowed idea is either translated, constrained, or rejected according to Fleck's platform and interaction frequency.

| Reference | Useful idea | Native Fleck translation | Where it belongs | What Fleck will not copy |
| --- | --- | --- | --- | --- |
| [Beautiful UI](https://www.beautifului.dev/) | Compact task rows, progressive state disclosure, quiet search results, selection actions, truthful loading status | Dense native rows with one strong state, concise secondary metadata, accessible result counts, and truthful persistence/agent feedback | Workspace Search, Agent Activity, save feedback, recovery notices | AI-dashboard framing, constantly streaming decoration, card-heavy layouts, fake elapsed-time theater |
| [beUI](https://beui.dev/) | Morphing Search, origin-aware surfaces, layout-continuous tabs, state swaps, toast stacking | Pointer-opened search continuity, trigger-origin popovers, stable selected-tab capsule, icon/text crossfades, coalesced notices | Search, Options and color popovers, tabs, save state, notices | Framer Motion, goo filters, bouncy Dynamic Island behavior, expanding toolbar controls that change accepted command geometry |
| [Rare UI](https://www.rareui.com/) | Strong object identity and playful spatial metaphors | Use only the idea that folders and objects retain identity while opening, moving, and receiving drops | Folder drag/drop and rare empty-state illustration studies | WebGL fluid orb in general Fleck, ambient motion, 3D folder theatrics, proximity sidebars, decorative scroll progress |
| [Transitions.dev](https://transitions.dev/) | Origin-aware menus, panel reveal, card resize, text state swap, tabs sliding, toast entry, spinner-to-check completion | A named transition vocabulary and consistent timing for native surfaces | Shared motion policy and every bounded implementation packet | Confetti, smoky delete, 3D tilt, per-word dissolve, animation on frequent actions |
| [shadcn/ui](https://ui.shadcn.com/) | Consistent primitives, disciplined states, composable ownership, restrained defaults | A Fleck-native component contract covering hover, focus, active, disabled, loading, error, selected, and accessibility states | Buttons, rows, fields, notices, popovers, sheets, empty states | React components, visual sameness with shadcn, dashboard card grids, web-specific affordances |

### The Rare UI boundary

Rare UI is deliberately the least literal source. Its Fluid Orb naturally suggests voice activity, but dictation is outside this program. Its folder component establishes a useful principle—an object should feel like the same object before, during, and after interaction—but Fleck's folder rows should express that through selection continuity, drag lift, and drop targeting rather than a fan of 3D cards.

### The Liquid Glass boundary

Liquid Glass is a hierarchy tool, not a theme. Fleck may use native glass for transient or floating controls when that material explains elevation and origin. It must not wrap every row, card, or section in a translucent container. On older supported macOS versions, semantic SwiftUI materials and `NSVisualEffectView` remain the fallback. Under Reduce Transparency, glass becomes an opaque adaptive surface with a clear boundary.

## Experience architecture

Fleck has four experience layers. Each layer has a different motion and material responsibility.

| Layer | Contents | Visual behavior | Motion behavior |
| --- | --- | --- | --- |
| Workspace base | Note title, body, caret, selection, scrolling | Stable, readable, lowest visual noise | No decorative or layout motion |
| Persistent chrome | Header, folder navigator, tabs, formatting bar | Quiet grouping, consistent density, semantic separation | Tiny state feedback and continuity only |
| Transient workspace surfaces | Search, link picker, color picker, menus, notices, confirmations | Clear elevation and origin; stronger contrast than underlying chrome | Short, interruptible enter/exit or morph |
| System destinations | Trash, Agent Activity, Settings, onboarding, import/export | Native sheet/window hierarchy with self-contained navigation | System presentation plus restrained internal state transitions |

The user should always know which layer is active. Only one blocking transient surface may own interaction at a time. Underlying content remains visually legible but inaccessible to hit testing and VoiceOver while blocked, matching the accepted search and link-picker behavior.

## Motion architecture

### Shared policy

The existing `Sources/FleckApp/AppMotion.swift` remains the single policy entry point. It should evolve from two raw durations into named semantic roles without becoming a generic animation framework.

The design contract is:

| Semantic role | Normal-motion intent | Target perceptual duration | Reduce Motion |
| --- | --- | --- | --- |
| `press` | Physical pointer acknowledgement | 80–110 ms | No scale; retain color/opacity |
| `state` | On/off, selected, saved, icon swap | 100–140 ms | Brief crossfade or color change |
| `selection` | Stable highlight moves between peers | 120–170 ms | Instant highlight change |
| `reveal` | Small disclosure or anchored popover | 150–200 ms | Crossfade |
| `surface` | Search, confirmation, compact panel | 180–240 ms | Crossfade or instant for keyboard |
| `rare` | Onboarding/recovery transition | 220–280 ms | Crossfade |

The exact public API belongs in the implementation plan after this design is approved. It must remain small, testable, and value-based. It must not introduce a dependency or allow arbitrary per-view timing.

### Interaction source

Motion decisions require the source of presentation:

```text
pointer or direct manipulation -> spatial continuity allowed
keyboard shortcut             -> instant presentation and dismissal
programmatic/system event      -> state transition only; no theatrical movement
Reduce Motion enabled          -> crossfade or instant, regardless of source
```

Workspace Search already distinguishes pointer morph, Reduce Motion crossfade, and Command-F instant presentation. That behavior becomes the reference implementation for other transient surfaces; it is preserved, not rewritten.

### Easing and springs

- Use ease-out for appearance, dismissal, and direct feedback.
- Use ease-in-out only when an already-visible object moves between two visible positions.
- Avoid ease-in for user-interface response.
- Springs are reserved for interruptible spatial continuity such as a dragged row returning to rest or a selected indicator changing target mid-flight.
- Normal UI springs use negligible bounce. Fleck must never oscillate after the user is ready to act.
- No animation waits before enabling input. The end state is interactive from presentation start unless a native modal contract prevents it.

### Allowed properties

Prefer opacity, transform, stable-identity layout continuity, and semantic color. Avoid continuously animating blur, shadow radius, material intensity, height, width, or other properties that repeatedly trigger layout and painting. A one-time small surface resize may be accepted when it communicates content continuity and passes performance evidence.

### Cancellation and interruption

Every transient animation must tolerate:

- Escape before entrance completes.
- A second pointer action while the first transition is running.
- A note or folder being deleted during asynchronous refresh.
- Rapid tab selection changes.
- Search results arriving out of order.
- The panel closing mid-transition.

The final state is derived from product state, not from animation completion callbacks. Cancellation must not strand focus, hit testing, accessibility visibility, save generation, or a stale overlay.

## Material and contrast system

### Material hierarchy

1. **Workspace base:** the note remains visually dominant. It receives no decorative glass card.
2. **Persistent chrome:** header, folder navigator, tab strip, and formatting bar should read as one coherent chrome family. Separation comes first from spacing and a restrained divider; not every region receives its own material band.
3. **Transient surface:** search, link picker, color picker, and confirmation may use a stronger material/opaque fallback because they must separate from the workspace.
4. **System sheet or window:** use native presentation and let the system provide elevation.

### Appearance rules

- Light and Dark Mode are equally primary. Neither is a secondary inversion pass.
- Persistent chrome must not look like stacked translucent gray bars.
- Text and symbols use semantic foreground styles and preserve at least WCAG AA contrast against the effective composited surface.
- Accent color marks selection, primary action, focus, or meaning. It does not tint inactive chrome for decoration.
- Thin separators may define a boundary; large dark or washed-out background bands may not.
- Shadow belongs only to genuinely elevated transient surfaces. Persistent chrome should not float above the note.
- Corners follow system containers. Avoid oversized radii that make dense Mac controls feel like mobile pills.

### Modern Liquid Glass adoption

Because Fleck deploys to macOS 14 while building with a newer SDK, modern glass APIs require availability-gated enhancement:

- Use standard native structure and materials on every supported OS.
- On a supported modern runtime, custom nearby glass controls may share a `GlassEffectContainer` and stable `glassEffectID` only when a real collapsed/expanded identity exists.
- Do not create a parallel visual hierarchy that appears only on the newest OS.
- Do not let modern glass change command order, hit targets, menu behavior, focus order, or accessibility naming.
- Reduced Transparency replaces glass sampling with an opaque adaptive surface and an explicit low-contrast boundary.

## Surface-by-surface design

### 1. Menu-bar panel and pinned window

**Keep:** current menu-bar entry, independently sized pinned window, stored sizing, one-process behavior, and accepted panel structure.

**Polish:**

- Treat panel appearance as immediate; the OS owns the menu-bar panel's lifecycle.
- Do not add a custom whole-panel zoom or bounce.
- Preserve the note's scroll position and editor focus across panel hide/show.
- The pinned window uses the same internal components and motion rules; no “second design system.”
- Resizing is direct. Content reflows without animated width or height.
- Cold and warm open must present complete chrome without delayed staged entrances.

### 2. Header

The header remains a compact command surface with the accepted Fleck mark, save feedback, Search, New Note, Pin, toolbar disclosure, Options, and Customize controls in their accepted order.

- Pointer press feedback is subtle and local to the pressed control.
- Hover changes foreground or quiet background only; no icon lift, glow, or expanding labels.
- The save indicator uses a small state swap: idle → Saving → saved confirmation. It must reflect real persistence and must never claim completion early.
- Options and Customize preserve native menu/window behavior. If a custom anchored transient surface is ever justified, it opens from the trigger; otherwise the system transition wins.
- The header and folder/tab chrome should feel related through spacing and material, not through one enclosing floating capsule.

### 3. Dismissible notices and suggestions

Fleck currently presents dictation availability/recovery rows and agent-change feedback beneath the tabs. General Fleck owns the presentation contract, while Dictation and Cleanup retains the underlying dictation behavior and copy.

The presentation contract is:

- Every nonblocking notice has a visible dismiss action when dismissal is safe.
- Persistent failures remain recoverable from an appropriate menu or Settings destination after dismissal.
- Notices share one row geometry, icon position, copy hierarchy, action placement, and close affordance.
- Repeated compatible notices coalesce rather than forming a tall stack.
- A new notice enters from the top edge by at most four points plus opacity; dismissal is faster.
- Reduce Motion uses opacity only.
- Errors do not auto-dismiss. Success confirmations may time out only when no action is required.
- VoiceOver announces new critical errors once, without re-announcing on every view update.
- A dismissed suggestion does not reappear in the same session unless its underlying state materially changes.

### 4. Folder navigator

The navigator remains horizontally compact and includes Unfiled, user folders, New Folder, and Trash with existing keyboard and drag/drop behavior.

- The selected background is a stable object that moves between rows where feasible; it does not fade every row independently.
- Unfiled disclosure uses a native chevron rotation and a short content reveal. The row itself does not change its hit target.
- Folder creation replaces the intended row with the editor without shifting unrelated commands more than necessary.
- Rename transition prioritizes focus: the text field appears focused immediately, without waiting for a morph.
- Drag begins with a small lift/opacity cue; drop targets use a clear semantic highlight. No 3D tilt or fanning cards.
- Reordering animates neighboring rows into their new positions only during pointer drag, never for storage refresh.
- Empty folders remain structurally present and announce “Empty”; no looping empty-state motion.
- Counts use monospaced digits to avoid horizontal jitter.

### 5. Tab strip

The accepted selected-tab capsule and live drag reordering remain the foundation.

- Pointer selection may move the selected capsule with a short, interruptible continuity transition.
- Keyboard-driven note selection changes instantly.
- Newly created tabs may enter with opacity and a four-point directional reveal; the note editor is already available and does not wait.
- Closing a tab removes it with a faster opacity/size transition only if neighboring tab positions remain stable and focus moves correctly.
- Overflow reveal remains a stable trailing control. It does not pulse to attract attention.
- Tab colors remain secondary identity cues. Selected state must be understandable without color.
- Agent-access and pin symbols do not animate continuously.
- Drag reordering uses real tab identity and must remain correct through rapid crossing, scroll, hidden trailing tabs, and cancellation.

### 6. Note title and editor

The title and native `NSTextView` body remain deliberately still.

- Font changes apply to the current note title according to the accepted title-font behavior, with no crossfade that could make text look blurry.
- Typing, paste, selection, caret motion, Markdown/list transformations, internal links, and Undo/Redo are instant.
- Checklist completion may retain its accepted brief completion overlay, suppressed by Reduce Motion.
- List and checklist marker alignment is a geometry rule, not an animation opportunity.
- Scrolling uses native physics and the accepted slim indicator behavior. No custom progress decoration.
- Long notes must never trigger frame-by-frame material, blur, shadow, or layout animation.
- Switching notes restores the correct title/body, selection, scroll position, undo manager, and focus before any optional chrome continuity completes.

### 7. Formatting bar

The existing full formatting bar is preserved exactly in command set, order, grouping, spacing, horizontal behavior, shortcuts, menus, and Delete placement.

- Show/hide uses a short opacity and four-point reveal for pointer interaction; the keyboard path is instant.
- Active Bold, Italic, Underline, Strikethrough, list, and checklist states use semantic selected styling with a brief color/background transition.
- Pointer press may scale to approximately 0.97; keyboard shortcuts do not simulate a press animation.
- Font, size, color, and highlight menus remain native and origin-aware where the system provides it.
- The highlighter icon and selected swatch remain truthful to the chosen color.
- Mixed-selection states are visually and accessibly distinct from simple Off.
- The toolbar's material is quieter than transient surfaces and clearly separated from note content without a washed-out band.
- Horizontal overflow, focus traversal, tooltips, and minimum hit targets remain usable at the smallest supported panel width.

### 8. Workspace Search

Search is Fleck's showcase continuity interaction, but speed remains dominant.

- Clicking Search may morph the compact affordance into the existing results surface using stable identity and native material.
- Command-F is instant and focuses the field immediately.
- Reduce Motion uses a crossfade.
- Escape, clear, result activation, and outside-click dismissal return focus to the exact title/editor origin using the accepted focus-generation fencing.
- Results update without animating every row on every keystroke.
- The highlighted result may use a short selection-continuity transition for pointer or arrow navigation only if it stays responsive with 1,000-note fixtures.
- Result count changes without a number ticker; accessibility receives an appropriate value without excessive announcements.
- Empty, searching, stale-refresh, and no-result states occupy stable geometry so the surface does not jump.
- The material surface has enough contrast in both appearances and under user-controlled panel opacity.

### 9. Internal links and backlinks

- The note-link picker shares search's focus, keyboard, result, and dismissal principles without sharing mutable presentation state.
- Link insertion remains instant and returns focus to the correct selection.
- Backlinks remain outside the permanent bottom editor footprint, consistent with the accepted relocation.
- A backlinks popover opens from its trigger and closes with Escape, outside click, selection, or the close control.
- The trigger may acknowledge a new backlink count with a one-time state change, not a persistent pulse.
- Result activation preserves note identity and folder scope.

### 10. Destructive confirmation

The delete confirmation remains a focused transient surface rather than a general modal redesign.

- It appears over a stable, noninteractive underlay.
- Pointer presentation may combine opacity with a subtle scale from approximately 0.985; keyboard or Reduce Motion uses opacity only.
- Cancel and Escape are immediate.
- Confirm transitions directly into the next selected note without an empty flash.
- Destructive color is semantic and limited to the destructive action.
- Focus begins on the safe action unless native macOS convention and keyboard behavior require otherwise.

### 11. Trash

- Keep the system sheet, native list, clear 30-day retention message, Restore actions, and empty state.
- Restore removes the row optimistically only when the existing recovery logic can restore truthfully on failure.
- Row removal uses a short opacity/position transition; Reduce Motion uses no movement.
- Multiple restores remain interruptible and preserve list focus.
- Expiry copy uses stable monospaced numbers where changing digits would otherwise shift layout.
- Errors appear in a dismissible/recoverable notice contract rather than expanding the sheet unpredictably.

### 12. Agent Activity and agent-change feedback

- Keep Agent Activity as a system sheet and preserve Done/Escape closure.
- Activity rows follow Beautiful UI's compact status hierarchy: primary action/outcome, concise actor/time metadata, and one semantic status symbol.
- No fake reasoning stream, animated “thinking,” or decorative progress for completed local events.
- Running operations may use native indeterminate progress only when the app truly lacks measurable progress.
- Selecting an activity activates the target note and dismisses the sheet with correct focus restoration.
- Agent change notices coalesce and keep Undo available without occupying excessive editor height.

### 13. Settings

- Keep the compact segmented section model and current truthful controls.
- The selected segment indicator may use stable-identity continuity for pointer selection; keyboard section changes are instant.
- Section content uses a restrained crossfade without animating window size.
- Installation or long-running states show real progress, cancellation, and error recovery; no decorative progress animation.
- Standard controls remain standard. Do not replace toggles, pickers, text fields, or shortcut recorders with web-inspired custom components.
- Changes take effect without a success animation that interrupts the next setting.

### 14. Onboarding

Onboarding is the one Fleck surface where slightly richer motion is appropriate because it is rare and explanatory.

- Preserve the existing rail, step structure, trial placeholder behavior, permission truthfulness, and completion path.
- Forward/back movement may be direction-aware with a restrained 180–240 ms transition.
- The rail's current-step state updates through color, symbol, and accessibility value; no bouncing progress dots.
- Permission outcomes use clear icon/text state swaps.
- Start/continue actions remain immediately responsive.
- Reduce Motion uses crossfades; Reduce Transparency replaces decorative material.
- The experience must fit smaller windows and larger accessibility text without clipping or requiring animation to reveal essential actions.

### 15. Import, export, and recovery

- Keep system file importer/exporter surfaces.
- Starting the operation is immediate; do not add a custom fake progress overlay when the system dialog is authoritative.
- Completion may appear as a compact, truthful state notice.
- Errors remain dismissible and recoverable, with copy that names the failed operation.
- Migration conflict remains a stable high-priority recovery view with no distracting entrance motion.

## Component-state contract

Every Fleck control or row introduced or touched by this program must define the following where applicable:

| State | Required signal |
| --- | --- |
| Default | Legible label/symbol and stable hit target |
| Hover | Quiet foreground or background response; no layout change |
| Focus | Visible native focus indication, unclipped |
| Active/pressed | Immediate local response; no delayed command |
| Selected | Shape/symbol plus color, never color alone |
| Disabled | Reduced emphasis while retaining readable purpose |
| Loading | Truthful progress or status; interaction policy is explicit |
| Error | Semantic icon/color, concise copy, recovery action, dismissal policy |
| Empty | Explains what belongs here and how it becomes populated |
| Reduced Motion | Crossfade or instant equivalent |
| Reduced Transparency | Opaque semantic surface and preserved boundary |

## Accessibility design

### Reduce Motion matrix

| Normal behavior | Reduce Motion equivalent |
| --- | --- |
| Press scale | Color/opacity only |
| Selected capsule moves | Selection changes instantly |
| Surface translates/scales | Crossfade |
| Folder/tab reorder layout motion | Direct reordering with drop highlight |
| Onboarding directional step | Crossfade |
| Checklist completion overlay | Suppressed, state remains visible |
| Pointer search morph | Crossfade |
| Keyboard search | Instant in both modes |

### VoiceOver

- Presentation changes move VoiceOver focus only when a new modal/transient scope truly owns interaction.
- Dismissal restores focus to the invoking control or exact editor origin.
- New critical errors announce once. Routine save completion does not repeatedly interrupt speech.
- Selection, mixed formatting, empty folders, counts, progress, and disabled reasons expose values in addition to visual styling.
- Decorative Fleck marks and transition-only symbols remain hidden.

### Keyboard and Full Keyboard Access

- Every action remains reachable in logical visual order.
- Escape closes the topmost dismissible surface exactly once.
- Command-F, Command-T, formatting shortcuts, Undo/Redo, list commands, folder navigation, tab navigation, and search result navigation remain immediate.
- Animation never steals focus and never creates an intermediate focusable duplicate.
- Focus rings are never clipped by glass shapes, overlays, or scroll containers.

### Contrast and perception

- Body and control text meet at least 4.5:1 against the effective composited background; large text and nontext controls meet at least 3:1.
- Placeholder and secondary text remain readable rather than using “elegant” low contrast.
- Increased Contrast strengthens boundaries and selection without changing layout.
- Color-blind users can identify selection, errors, success, shared notes, and destructive actions through symbol/shape/copy.

### Text and localization

- Verify English, Chinese, mixed Unicode, emoji, composed characters, and long note titles.
- UI labels tolerate localization expansion without truncating the only explanation of an action.
- Note content never changes font or alignment as a side effect of interface motion.
- Larger text may increase row height; the app must prefer scrolling over clipping.

## Performance design

### Budgets

- Keyboard-initiated UI response should present within the next display frame whenever product state is locally available.
- Pointer feedback begins within one frame.
- Standard transitions settle perceptually within 240 ms.
- No persistent animation runs while Fleck is idle, except separately owned real-time dictation activity.
- UI polish must not create sustained idle CPU use or a monotonic memory trend.
- Search filtering and selection remain responsive with 10, 100, and 1,000-note fixtures.
- A long note and rapid editing must not cause material or motion layers to repaint continuously.

### Measurement scenarios

1. Cold panel open and first interaction.
2. Warm panel open/close repeated 50 times.
3. Rapid pointer switching across 20 tabs.
4. Keyboard note switching and Command-F repeated 50 times.
5. Folder collapse/reorder with 0, 10, and 100 folders where fixtures permit.
6. Search with 10, 100, and 1,000 notes while typing rapidly.
7. Backlinks and internal-link result lists at empty, typical, and large counts.
8. A very long rich-text note during scrolling, formatting, and checklist completion.
9. Light/Dark appearance switching with transient surfaces open.
10. Reduce Motion and Reduce Transparency changes while the app remains running.

Use signposts and Instruments where useful. A visually attractive transition that regresses interaction latency, editor scrolling, or memory durability does not ship.

## Visual quality protocol

Every implementation packet that changes visible behavior must include comparable evidence from the packaged app, not only previews or a raw SwiftPM executable.

### Required capture set

- Before and after at the same panel size, note fixture, accent, opacity, and appearance.
- Light and Dark Mode.
- Normal motion and Reduce Motion end states.
- Minimum supported panel width and a comfortable pinned-window size.
- Empty, typical, and stress-content states for the affected surface.
- A short 60 fps recording or a start/mid/end frame sequence for actual motion timing.
- A screenshot with Increased Contrast or Reduce Transparency when material is affected.

### Visual analysis questions

1. Does the eye stay anchored on the note?
2. Does the moving object preserve identity and origin?
3. Does any text blur, jump, or reflow unnecessarily?
4. Does the surface look native in both appearances?
5. Is the transient surface clearly separated without a heavy band or excessive shadow?
6. Is the action available before the animation finishes?
7. Does dismissal feel faster than entrance?
8. Does the result remain understandable in a still screenshot and under Reduce Motion?

## Implementation architecture and ownership

This design must be implemented through the repository's mandatory Sol/Luna workflow. The primary GPT-5.6 Sol/High session owns architecture, packet boundaries, integration, verification, packaged-build provenance, and a fresh `sol_advisor_sol_reviewer` verdict of exactly `ship`. Implementation occurs only in user-visible GPT-5.6 Luna/Max tasks created through Sol Advisor orchestration.

New implementation tasks use the `Agent - ` prefix. Each packet owns exact files, preserves unrelated changes, works in an isolated worktree, starts with a red regression when behavior is testable, and forbids GitHub writes unless separately authorized.

### Relationship to existing plans

- This specification supersedes the visual direction in the narrower July 25 “crisp native motion” plan wherever the two conflict, while retaining already accepted `AppMotion` behavior until a bounded replacement is tested and reviewed.
- It does not supersede accepted functional specifications for Search, tabs, notices, checklists, editing, packaging, or accessibility. Those remain behavioral contracts and become inputs to each implementation packet.
- It does not absorb the Dictation and Cleanup roadmap. Any shared presentation boundary must be agreed as an interface; recognition, cleanup, model policy, and dictation-specific visuals stay in that program.
- A file-by-file implementation plan is intentionally separate from this design specification. It should be written only after the user accepts this direction, so engineering tasks do not prematurely freeze an unapproved interaction choice.

### Dependency sequence

```text
Motion and material contract
  -> transient notice contract
  -> NotesPanel navigation continuity (folders and tabs)
  -> NotesPanel editor chrome (header and formatting bar)
  -> search and link surfaces
  -> independent destination surfaces (Trash, Agent Activity, Settings, onboarding)
  -> accessibility and performance closure
  -> package and live-build acceptance
```

### Parallelism rules

- The shared motion contract is first and serial.
- Any packet touching `NotesPanel.swift` is serial with every other `NotesPanel.swift` packet.
- Search and link-picker work may proceed in parallel only with exact disjoint file ownership and after the motion contract is accepted.
- Trash, Agent Activity, Settings, and onboarding may proceed in parallel after shared contracts are accepted because their primary files are disjoint.
- No packet depends on an unreviewed diff.
- No worker may “helpfully” refactor adjacent code, especially the large `NotesPanel.swift` or `NativeRichTextEditor.swift` files.
- Dictation-owned files and behavior are excluded even when a general notice displays dictation state. General Fleck may own only the generic notice presentation interface agreed with that program.

## Phased delivery plan

### Phase 0: Baseline and inventory

**Purpose:** freeze the accepted behavior and create comparable evidence before changing appearance.

Deliverables:

- Exact source commit, branch, worktree, package graph, installed bundle, and running executable provenance.
- Current screenshots/recordings for header, folders, tabs, editor, toolbar, search, backlinks, notices, Trash, Agent Activity, Settings, and onboarding.
- Interaction-frequency inventory marking each action instant, frequent, occasional, or rare.
- Accessibility baseline for VoiceOver, Reduce Motion, Reduce Transparency, Increased Contrast, Full Keyboard Access, and larger text.
- Performance baseline for cold/warm open, repeated open/close, search fixtures, long notes, CPU, and memory.

Exit gate: baseline evidence is reproducible and all unrelated dirty work is protected.

### Phase 1: Motion and material foundation

**Purpose:** establish semantic roles and accessibility overrides before any surface invents its own timing.

Likely ownership:

- `Sources/FleckApp/AppMotion.swift`
- new narrowly scoped presentation-policy types only if tests prove a need
- `Tests/FleckAppTests/AppMotionTests.swift`

Requirements:

- Red tests for semantic timing, keyboard immediacy, Reduce Motion, and press behavior.
- No UI changes beyond what is required to exercise the contract.
- No dependency and no global animation modifier on workspace state.

Exit gate: focused tests, full relevant suite, build, parent diff inspection, and fresh Sol `ship`.

### Phase 2: Notice and feedback contract

**Purpose:** unify dismissible errors, suggestions, save feedback, and agent-change presentation without owning dictation logic.

Likely ownership:

- `Sources/FleckApp/AgentChangeBanner.swift`
- a new generic notice presentation file if the design cannot remain local
- targeted `NotesPanel.swift` integration, handled serially
- focused presentation and lifecycle tests

Requirements:

- Safe dismissal, coalescing, persistence rules, recovery routing, VoiceOver announcement policy, and Reduce Motion.
- No notice stack that consumes large editor height.
- No false save completion.

Exit gate: functional notice matrix, visual evidence, lifecycle tests, build/package check, and fresh Sol `ship`.

### Phase 3: Navigation continuity

**Purpose:** polish folders and tabs while preserving every command and routing rule.

This is split into two serial `NotesPanel.swift` packets:

1. `Agent - Folder navigator continuity`
2. `Agent - Tab identity and interaction polish`

Requirements:

- Interaction-source-aware motion.
- Drag/drop, rename, collapse, counts, overflow, focus, and VoiceOver regressions covered.
- 10/100/1,000-note behavior where navigation is affected.

Exit gate per packet: red regression, focused/full/package verification, visual recording, live packaged repro, and fresh Sol `ship` before the next packet begins.

### Phase 4: Header and formatting chrome

**Purpose:** make persistent controls feel coherent and native without consolidation.

Serial packets:

1. `Agent - Header state and material polish`
2. `Agent - Formatting bar interaction and contrast polish`

Requirements:

- Exact command/order/spacing/horizontal behavior preservation.
- No Format popover and no Delete relocation.
- Focus, hover, pressed, active, mixed, disabled, and narrow-width states.
- Light/Dark, accent, panel opacity, Increase Contrast, and Reduce Transparency evidence.

Exit gate: screenshot comparison proves improved hierarchy without lost controls, plus fresh Sol `ship` for each packet.

### Phase 5: Search, links, and transient continuity

Potentially parallel, disjoint packets after the shared contract:

1. `Agent - Workspace Search continuity and stable states`
2. `Agent - Internal link and backlinks popover continuity`

Requirements:

- Preserve accepted pointer morph / keyboard instant / Reduce Motion crossfade behavior.
- Preserve exact focus restoration and asynchronous generation fencing.
- Do not animate each result on every query.
- Pass 1,000-note search performance fixtures.

Exit gate: focused search/link suites, performance evidence, packaged recording, and fresh Sol `ship` per packet.

### Phase 6: Destination surfaces

Disjoint packets may run in parallel after shared contracts:

- `Agent - Trash continuity and recovery polish`
- `Agent - Agent Activity hierarchy and closure polish`
- `Agent - Settings section continuity and state polish`
- `Agent - Onboarding explanatory motion polish`

Each packet preserves native sheet/window behavior and owns no unrelated feature logic.

Exit gate: surface-specific functional/accessibility matrix, screenshots, tests/build/package evidence, and fresh Sol `ship`.

### Phase 7: Cross-surface accessibility and performance closure

**Purpose:** find inconsistencies that isolated packets cannot see.

Deliverables:

- Complete Reduce Motion/Transparency/Contrast matrix.
- Keyboard and VoiceOver traversal across every modified surface.
- Light/Dark, font scaling, Unicode/Chinese, localization-length, caret, and selection review.
- Cold/warm panel, 50 open/close cycles, rapid tab/edit/search, long note, and 10/100/1,000-note measurements.
- Removal or simplification of any transition that cannot meet the budget.

Exit gate: no unresolved high-severity accessibility or performance defect and a fresh holistic Sol `ship` review.

### Phase 8: Durability, package, and live acceptance

**Purpose:** prove the user is running the design that was reviewed.

Deliverables:

- Relaunch, sleep/wake, one-process enforcement, migration/recovery fixtures, and persistence checks.
- Resource packaging and signing checks appropriate to the development build.
- A freshly built `.app`, replacement of the authorized install target, and verification of exact executable path, source commit, bundle identity, and visible feature set.
- A live manual walkthrough of every modified interaction in the installed build.
- Final before/after capture set and fresh Sol `ship` verdict on the integrated diff and evidence.

No push, PR, merge, branch deletion, worktree pruning, or GitHub mutation occurs without current explicit authorization.

## Functional regression matrix

UI polish is not accepted until these behaviors remain correct:

- Panel and pinned-window lifecycle, focus, stored size, and one-process behavior.
- Create, select, edit, move, pin, reorder, rename, delete, restore, import, export, and persist notes/folders.
- Typing, Unicode, Chinese, selection, paste options, Undo/Redo, fonts, sizes, colors, highlights, lists, and checklists.
- Search empty/results/stale/activation/dismissal/focus behavior.
- Backlinks and internal-link insertion/activation.
- Trash retention and recovery.
- Agent Activity presentation, activation, Done, Escape, feedback, and Undo.
- Onboarding progress, placeholder trial path, permission outcomes, relaunch, and completion.
- Every existing shortcut, menu item, toolbar control, accessibility label, and accepted visual behavior.

## Risks and mitigations

### Risk: `NotesPanel.swift` becomes a merge-conflict and regression hotspot

Mitigation: serial packets, exact line/feature ownership, no adjacent refactor, parent diff inspection, and a fresh reviewer after each accepted packet. A future view extraction requires its own architecture design and is not smuggled into visual polish.

### Risk: web inspiration makes Fleck feel like a website

Mitigation: standard macOS controls first, no copied code/dependencies, native menu/sheet/focus semantics, and reference ideas translated only at the level of continuity and state.

### Risk: Liquid Glass reduces legibility or creates washed-out bands

Mitigation: one material hierarchy, conditional enhancement, Reduce Transparency fallback, appearance/opacity matrix, and contrast measurement on the effective composited result.

### Risk: motion makes frequent work feel slow

Mitigation: interaction-frequency classification, instant keyboard paths, sub-240 ms budgets, exit faster than entrance, and removal of any transition that fails repeated-use testing.

### Risk: animation destabilizes focus and state

Mitigation: product state owns the final view, stable identifiers, no completion-callback state machines, generation fencing for asynchronous results, and explicit focus restoration tests.

### Risk: visual QA passes while the installed app is stale

Mitigation: record source commit, staged bundle, installed bundle, executable path, process identity, and visible feature markers for every final acceptance run.

## Acceptance criteria

This design program is complete only when all of the following are true:

1. Fleck retains every accepted function, command, shortcut, and layout contract.
2. Motion is consistent across surfaces and can be described using the shared semantic roles.
3. Keyboard workflows are immediate and never simulate pointer animation.
4. The note title/body, caret, selection, scrolling, typing, and Undo/Redo remain visually stable.
5. Pointer-opened transient surfaces preserve origin and dismiss faster than they enter.
6. Notices are coherent, safely dismissible, recoverable, and do not consume excessive note space.
7. The formatting bar remains complete and gains clearer, calmer separation from note content.
8. Search preserves the accepted pointer, keyboard, Reduce Motion, focus, and performance behavior.
9. Liquid Glass/material is functional, restrained, readable, and replaceable under Reduce Transparency.
10. Light Mode, Dark Mode, Reduce Motion, Reduce Transparency, Increased Contrast, keyboard-only use, VoiceOver, larger text, Unicode, and Chinese all have explicit passing evidence.
11. Cold/warm use, repeated interaction, long notes, and 10/100/1,000-note fixtures stay within the defined responsiveness and resource budgets.
12. Every bounded diff receives parent verification and a fresh Sol reviewer verdict of exactly `ship`.
13. The final packaged build is proven to come from the accepted integrated source and is the exact instance the user runs.
14. GitHub remains unchanged until the user explicitly authorizes publication or integration actions.

## Decision summary

Fleck will not integrate the five reference libraries as code or as a blended visual collage. It will integrate their strongest ideas through a native design system:

- Beautiful UI contributes compact, truthful state hierarchy.
- beUI contributes continuity, origin, and state morphing.
- Rare UI contributes object identity, with its decorative effects intentionally constrained.
- Transitions.dev contributes a precise motion vocabulary and transition patterns.
- shadcn/ui contributes component-state discipline and composable consistency.

The result should feel recognizably Fleck and recognizably macOS: still while writing, immediate under the keyboard, gently physical under the pointer, and trustworthy whenever the system changes state.
