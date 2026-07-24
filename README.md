# Menu Bar Notes

Menu Bar Notes is a planned lightweight, native macOS menu-bar app for keeping multiple quick notes in tabs. The goal is a fast, local-first editor with rich-text formatting, bullets, numbered lists, installed-font support, and low idle resource use.

See the [product plan](PRODUCT_PLAN.md) for the complete vision, feature requirements, technical direction, performance goals, and delivery roadmap.

## Project status

Active development now includes the native macOS menu-bar and floating-window shells, multi-note tabs, an AppKit rich-text editor, Markdown plus RTF-sidecar persistence, recovery snapshots, import/export, customization, and editable shortcuts. See the [implementation status](IMPLEMENTATION_STATUS.md) for the exact feature and validation state, and the [application framework](ARCHITECTURE.md) for the main flows and architecture.

## Build and test

The app targets macOS 14 or later and uses only Apple system frameworks. Open `Package.swift` in Xcode to build and run the native menu-bar executable, or use Swift Package Manager:

```sh
swift run MenuBarNotes
swift test
```

On non-macOS systems, the executable only reports its platform requirement, but the portable core and its tests still build and run.

For a complete native walkthrough and manual acceptance checklist, see [TESTING.md](TESTING.md). On a Mac, `Scripts/validate-macos.sh` runs the automated tests, creates a release build, and checks the executable-size budget before you launch it.

## Development workflow

GitHub is the source of truth for this project. Normal work is developed on a dedicated feature branch, committed and pushed in reviewable checkpoints, and merged into `main` through a pull request only after the branch's planned scope is complete. Keep application changes, relevant tests, and documentation together so the repository always reflects the current state of the product. See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete branch and pull-request workflow.

Do not commit credentials, signing keys, provisioning profiles, local configuration containing secrets, or generated build output.
