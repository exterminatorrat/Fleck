# Motes — Product Plan

## Product vision

Motes is an extremely lightweight, native macOS notes app that stays one click or keyboard shortcut away in the menu bar. It is designed for quickly capturing and organizing short notes without the memory use, interface complexity, or setup required by a full document editor.

The app should feel immediate: open it, type, switch notes, and dismiss it. Notes save automatically and return exactly as the user left them.

## Product principles

1. **Lightweight by default.** Prefer native macOS frameworks and avoid embedded browsers, background servers, accounts, analytics, and unnecessary dependencies.
2. **Fast to access.** Opening the app, creating a tab, and moving between notes should all have convenient keyboard shortcuts.
3. **Simple first, customizable when wanted.** The default interface should remain uncluttered while appearance and editing preferences are easy to change.
4. **Local and dependable.** Notes are stored locally, save automatically, and recover safely after relaunches or crashes.
5. **Native behavior.** Text selection, undo, spelling, accessibility, menus, and keyboard commands should behave like other macOS apps.

## Source control and GitHub workflow

GitHub is the source of truth for the project. Product documentation, application code, tests, assets, build configuration, and other project files should be version controlled there rather than kept only on a developer's computer.

Every project update should follow this workflow:

1. Create or update a focused branch for the work.
2. Commit all intentional project-file changes with a descriptive commit message.
3. Push the branch to the GitHub repository.
4. Open or update a pull request that explains the change and lists the checks performed.
5. Merge through GitHub after review and required checks pass.

Before committing, review `git status` and the diff so generated files, credentials, signing material, local editor settings, build output, and other machine-specific files are not accidentally published. Secrets must never be committed to Git; use documented environment variables or GitHub's encrypted secrets instead.

Commits should be small enough to review and should leave the repository in a usable state whenever practical. Documentation and tests should be updated in the same pull request as the behavior they describe. Release milestones should use Git tags and GitHub Releases so shipped versions can be traced back to their exact source.

## Initial platform and architecture

The initial release targets macOS and should be built with Swift and native Apple frameworks:

- `NSStatusItem` for the menu-bar presence.
- AppKit's text system, centered on `NSTextView`, for editing and rich-text behavior.
- SwiftUI where it reduces interface code without compromising editor behavior or resource use.
- A menu-bar popover that can optionally become a pinned floating panel.
- Lightweight local files for persistence; no account or network connection is required.

The application should aim for approximately **50 MB of memory while idle with ordinary notes**, measured during development and treated as a performance target rather than an absolute guarantee across every macOS version and workload.

## Core experience

### Menu-bar access

- Clicking the menu-bar icon opens the notes interface.
- A configurable global keyboard shortcut shows or hides the interface.
- The interface opens quickly and restores the previously selected note.
- A pin control converts the temporary popover into a floating panel when the user wants to keep it visible.
- The menu-bar icon can use a system-provided symbol and support light and dark menu bars.

### Note tabs

Multiple notes can be open as tabs in the same compact window.

Each tab should support:

- Creating, closing, renaming, and reordering.
- An optional pinned state for important notes.
- A visible unsaved or save-error state when necessary.
- Restoration of its title, content, cursor position, and scroll position after relaunch.
- Keyboard navigation without requiring the pointer.

Suggested shortcuts:

| Action | Shortcut |
| --- | --- |
| New note | `Command-T` |
| Close current note | `Command-W` |
| Select tab 1–9 | `Command-1` through `Command-9` |
| Next tab | `Control-Tab` |
| Previous tab | `Control-Shift-Tab` |
| Rename current note | `Command-Shift-R` |
| Show or hide the app | User-configurable |

Shortcuts should be checked against standard macOS conventions before implementation and made configurable where conflicts are likely.

## Editor and formatting

The editor should support rich text while keeping the controls compact. Formatting can be available through keyboard shortcuts, the standard macOS Format menu, contextual menus, and an optional toolbar.

### Inline formatting

The first release should include:

- Bold (`Command-B`)
- Italic (`Command-I`)
- Underline (`Command-U`)
- Strikethrough
- Text color
- Highlight color
- Clear formatting
- Increase and decrease font size
- Left, center, and right alignment
- Undo and redo through the native macOS undo manager

Possible later additions include links, find and replace, paragraph spacing, line spacing, and reusable text styles.

### Bulleted lists

Bulleted lists should be convenient from both the keyboard and formatting controls.

Expected behavior:

- Typing `- ` or `* ` at the beginning of a line can automatically begin a bulleted list.
- Pressing Return at the end of a list item creates the next bullet.
- Pressing Return on an empty list item exits the list.
- Tab increases the item's indentation level.
- Shift-Tab decreases the item's indentation level.
- A toolbar or menu action toggles bullets for the current paragraph or selection.
- Pasting, undoing, and editing around lists should preserve predictable formatting.

Automatic list creation should be optional so users who want literal Markdown-like text can disable it.

### Numbered lists

Numbered lists should follow the same editing model as bullets.

Expected behavior:

- Typing `1. ` at the beginning of a line can automatically begin a numbered list.
- Subsequent items continue the sequence automatically.
- Inserting, deleting, indenting, or moving items updates numbering appropriately.
- Nested lists can use a suitable numbering style for each level.
- Return on an empty item exits the list.
- A toolbar or menu action toggles numbering for the current paragraph or selection.

### Fonts

Users should be able to use fonts installed on their Mac.

Font customization should include:

- A searchable list of installed font families.
- The standard macOS font panel where appropriate.
- Font family, face, and size controls.
- A global default font for new notes.
- Optional per-note defaults and formatting for selected text.
- A safe fallback to the system font when a previously selected font is unavailable.
- Storage of stable font identifiers without bundling or copying the user's font files.

### Editing preferences

The app should eventually allow users to configure:

- Editor background and text colors.
- Default font and font size.
- Window or popover dimensions.
- Automatic bullet and numbered-list detection.
- Spell checking, smart quotes, smart dashes, and text replacement.
- Tab width, paragraph spacing, and line spacing.
- Whether formatting controls are always visible or hidden until needed.

## Storage and reliability

Saving should be automatic rather than a task the user has to remember.

The persistence design should provide:

- Debounced autosave after edits.
- Atomic writes so an interrupted save cannot leave a partially written note.
- Separate note records or files so damage to one note does not affect every note.
- Stable identifiers independent of note titles.
- Restoration of open tabs, tab order, selected tab, cursor positions, and window state.
- Clear error reporting when a note cannot be saved.
- A small local recovery or revision history as a later enhancement.

Because fonts and other rich formatting cannot be represented faithfully in plain Markdown, the app should store attributed or rich text internally. It can still offer export to:

- Plain text (`.txt`)
- Markdown (`.md`), with unsupported styling simplified
- Rich Text Format (`.rtf`)

Import and export should never silently overwrite the app's working copy of a note.

## Customization without clutter

The default interface should contain only what is needed to write and switch notes. Optional controls may be exposed through:

- A compact formatting toolbar.
- The standard application menus.
- A contextual right-click menu.
- A dedicated Settings window.
- Customizable keyboard shortcuts where practical.

Themes should begin with system, light, and dark options. Custom editor foreground, background, selection, and accent colors can follow without turning the main window into a theme editor.

## Performance goals

Performance is a product feature and should be tested throughout development.

Initial goals:

- Approximately 50 MB idle memory for a normal set of short notes.
- No embedded web view or Electron-style runtime.
- No continuous polling or unnecessary background activity.
- Near-instant display after the application is running.
- Responsive typing and tab switching, including with many ordinary notes.
- Lazy loading for unusually large or numerous notes where it measurably helps.
- Minimal CPU use while the interface is closed and no save is pending.

Memory, launch time, typing responsiveness, and idle CPU use should be measured in release builds rather than inferred from framework choice alone.

## Accessibility and native integration

The app should support:

- VoiceOver labels and logical keyboard focus order.
- Full keyboard operation.
- Sufficient color contrast in built-in themes.
- Dynamic interface sizing where practical.
- Standard macOS spelling, substitutions, services, copy, paste, and selection behavior.
- Reduced-motion and other relevant system accessibility preferences.

## Privacy and security

The base application is local-only:

- No account is required.
- Notes are not transmitted to a server.
- No analytics or advertising SDK is included.
- Network access is unnecessary for core functionality.
- Any future synchronization feature must be optional and document where data is stored.

A future option may encrypt stored notes or use platform-protected storage, but it should be designed carefully rather than marketed as secure before receiving appropriate review.

## Delivery plan

### Phase 1 — Working prototype

- Menu-bar icon and popover.
- Create and switch between note tabs.
- Native rich-text editor.
- Basic local autosave and session restoration.
- Bold, italic, and underline commands.

### Phase 2 — Complete core editor

- Close, rename, pin, and reorder tabs.
- Bulleted and numbered lists, including typing shortcuts.
- Indentation and alignment.
- Installed-font family and size selection.
- Formatting toolbar and menus.
- Pinned floating-panel mode.

### Phase 3 — Reliability and customization

- Atomic persistence and save-error recovery.
- Settings for fonts, colors, list detection, and editor behavior.
- Import and export.
- Configurable global show/hide shortcut.
- Launch-at-login option.
- Accessibility review and keyboard-navigation polish.

### Phase 4 — Performance and release polish

- Release-build memory, CPU, and launch-time profiling.
- Tests for persistence, list editing, tab restoration, and keyboard commands.
- Handling for large notes and large tab collections.
- Crash recovery and optional lightweight revision history.
- App icon, onboarding, packaging, signing, and release documentation.

## Out of scope for the initial release

To protect the app's simplicity and resource goals, the first release should not include:

- User accounts.
- Cloud synchronization.
- Real-time collaboration.
- AI-generated or AI-edited content.
- A plug-in marketplace.
- A full browser or web-based editor.
- Complex page layout or desktop-publishing features.

These ideas can be reconsidered only if there is a clear user need and they can remain optional without degrading the base experience.

## Open product decisions

The following should be resolved through prototypes and testing:

1. Whether the default interface is a transient popover, a floating panel, or a popover with an optional pinned mode.
2. Whether each note has one base font or permits arbitrary mixed-font selections by default.
3. The exact rich-text storage format and how revisions are retained.
4. How tab overflow behaves in a very narrow panel or with many notes.
5. Which global shortcut is safe as the default and how shortcut conflicts are presented.
6. Whether Markdown-like list conversion is enabled by default.
7. Whether notes live in an app-managed container or a user-visible folder.

## Definition of a successful first release

The first release is successful when a user can install the app, open it from the menu bar, maintain several tabbed notes, format text and lists, choose an installed font, and trust that everything will return after relaunch—all while the app remains fast, unobtrusive, accessible, and close to its lightweight resource target.
