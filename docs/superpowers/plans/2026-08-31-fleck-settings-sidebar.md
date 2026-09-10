# Fleck Settings Sidebar Implementation Plan

> Status: Superseded by final accepted implementation
>
> Historical plan (non-normative). The worker instructions and architecture
> below describe the original proposal and must not be executed for new work.
> The accepted implementation is the fixed HStack sidebar with Fleck neutral
> glass surfaces, Settings-specific AppKit chrome, and the final Vocabulary and
> Agents structures. Use the accepted source/tests and `design-qa.md` as the
> current source of truth.

> **Historical process note:** The original worker process below is retained
> for provenance only; it is not an active instruction set.

**Goal:** Replace Fleck's top settings selector with a larger native macOS sidebar settings window whose system material gains Liquid Glass automatically on supported macOS releases.

**Historical architecture (superseded):** Keep `SettingsSection` and every existing settings binding, but present them through a selection-backed `NavigationSplitView`. A native sidebar `List` owns navigation; a fixed header and grouped scrolling `Form` own the detail. The Settings scene supplies minimum and ideal window dimensions.

**Tech Stack:** Swift 6, SwiftUI, AppKit hosting tests, Swift Testing, Swift Package Manager, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-31-fleck-settings-sidebar-design.md`

## Global Constraints

- Work only in `${FLECK_REPO}/.worktrees/settings-sidebar-redesign` on `codex/settings-sidebar-redesign` based at `d6facac`.
- Modify only the three owned files listed below. Preserve concurrent and unrelated changes; do not revert another contributor's work.
- Keep `.editing` as the durable enum case while changing its visible title to “General.”
- Preserve all runtime and preference behavior, pending route consumption, floating-window configuration, and shortcut-recording cancellation.
- Use native `NavigationSplitView` and `.sidebar` list styling. Do not add custom blur, glass effects, cards, selection pills, or availability-specific visual forks.
- Do not refactor the large Settings file or redesign controls inside the destinations.
- Do not push, open a pull request, merge, install, or replace a running Fleck application.

---

### Task 1: Build the native sidebar Settings window

**Owned files:**

- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/DictationSettingsTests.swift`

**Interfaces:**

- `SettingsSection` gains user-facing icon and description metadata plus explicit sidebar group arrays.
- `SettingsSectionSidebar` replaces `SettingsSectionSelector`.
- `SettingsView` becomes a `NavigationSplitView` with the existing selection and lifecycle hooks.
- The Settings scene uses minimum and ideal dimensions instead of a fixed 520 × 440 frame.

- [ ] **Step 1: Replace selector tests with sidebar contracts**

Update the existing selector-focused tests to assert:

```swift
#expect(SettingsSection.fleckCases == [.editing, .appearance, .shortcuts])
#expect(SettingsSection.voiceAndWritingCases == [.dictation, .vocabulary])
#expect(SettingsSection.connectionCases == [.agents])
#expect(SettingsSection.editing.title == "General")
```

Host `SettingsSectionSidebar` at approximately 200 × 520 with `.large` and `.accessibility3` dynamic type sizes. Assert visible descendants remain within the host bounds and that changing the binding updates the selected section. Replace the old matched-geometry and compact-picker source assertions with a narrow contract for the sidebar accessibility label and native selection tags.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
```

Expected: compilation or assertions fail specifically because the new metadata and `SettingsSectionSidebar` do not exist. Record the failing evidence before production edits.

- [ ] **Step 3: Add minimal destination metadata and native sidebar**

In `SettingsView.swift`:

- retain the current enum cases and `Identifiable` conformance;
- make `.editing` display “General” without changing the case name;
- add SF Symbol and one-sentence description metadata;
- add the three explicit group arrays from the design spec;
- replace `SettingsSectionSelector` with a `List(selection:)` sidebar organized into “Fleck,” “Voice & Writing,” and “Connections” sections;
- use `Label(section.title, systemImage: section.systemImage)`, `.tag(section)`, `.listStyle(.sidebar)`, and a 180/200/230 point split-view column width;
- label the list “Settings sections” for accessibility.

- [ ] **Step 4: Convert SettingsView to the split layout**

Make `NavigationSplitView` the root:

```swift
NavigationSplitView {
  SettingsSectionSidebar(selection: $selectedSection)
} detail: {
  VStack(alignment: .leading, spacing: 0) {
    SettingsPageHeader(section: selectedSection)
    Divider()
    Form { /* existing switch and section views */ }
      .formStyle(.grouped)
  }
}
.navigationSplitViewStyle(.balanced)
```

Keep the existing `onChange`, `onAppear`, `task`, confirmation dialog, and alert behavior on the root. Remove the old selector, matched-geometry namespace, Reduce Motion dependency, `.id`, transition, and sidebar-selection animation. Pending routes should directly assign `selectedSection`.

- [ ] **Step 5: Enlarge the Settings scene**

In `FleckApp.swift`, replace only the fixed Settings frame with:

```swift
.frame(
  minWidth: 760,
  idealWidth: 840,
  minHeight: 520,
  idealHeight: 600
)
```

Keep `FloatingWindowConfigurator()` unchanged.

- [ ] **Step 6: Run focused verification and verify GREEN**

Run:

```bash
swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.personalDictionary(Settings|Runtime)'
swift test --disable-automatic-resolution --no-parallel --filter 'ShortcutRecorder|shortcut|Shortcut|Settings'
swift test --disable-automatic-resolution --no-parallel --filter FleckColorPickerTests
swift test --disable-automatic-resolution --no-parallel --filter AgentPresentationTests
```

Expected: every selected command executes nonzero tests where applicable and exits 0.

- [ ] **Step 7: Run broader verification**

Run:

```bash
Scripts/validate-macos.sh
swift build --disable-automatic-resolution -c release --product Fleck
git diff --check
```

Expected: validation and release build exit 0; the diff has no whitespace errors.

- [ ] **Step 8: Inspect scope and commit locally**

Run:

```bash
git status --short --branch
git diff -- Sources/FleckApp/SettingsView.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/DictationSettingsTests.swift
git add Sources/FleckApp/SettingsView.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/DictationSettingsTests.swift
git commit -m "feat: redesign settings with native sidebar"
```

Expected: only the three owned implementation files are included in the worker commit. Report the RED evidence, GREEN evidence, full commit SHA, and any remaining visual-QA limitation. Do not push.

## Parent Acceptance Gate

The primary session must inspect the complete branch diff, rerun the required checks, and capture the real Settings window without replacing the installed app. A fresh `sol_advisor_sol_reviewer` must review the actual diff and evidence and return exactly `ship`. Any `fix-first` result returns to the same worker with a corrected bounded packet, followed by repeated parent verification and a new fresh review.
