# Fleck

Fleck is a native, local-first macOS notes workspace for quick capture, focused
editing, on-device dictation, and explicitly granted local agent access.

> **Developer Preview:** Fleck is under active development. There is no
> supported binary release yet, and storage formats and contributor-facing
> interfaces may change during the 0.x series.

## What is here

The ordinary build contains:

- a menu-bar workspace and independently sized pinned window;
- local notes, tabs, folders, search, backlinks, file references, import/export,
  30-day Trash, and recovery;
- an AppKit `NSTextView` editor with native undo, formatting, lists, and
  checklists;
- Apple on-device speech recognition, optional faithful local cleanup, and
  Inbox-safe Smart Capture routing;
- a separately packaged local Agent Connector with profile-scoped capabilities,
  explicit note or folder grants, visible activity, revision checks, and Undo;
- readable local storage with atomic replacement and a previous-generation
  recovery snapshot.

On macOS 26, Fleck can use Apple's on-device Foundation Models when the system
reports them available. Failure or ambiguity falls back to the original text or
Inbox rather than inventing a destination.

The Enhanced Local dependency graph is different. It is opt-in, debug-only
experimental work behind `FLECK_ENHANCED_CANDIDATE=1`, with candidate Parakeet
speech and Gemma cleanup/routing paths. It is not part of the ordinary release
graph and is not approved for distribution.

See [Implementation status](IMPLEMENTATION_STATUS.md) for the short current
roadmap and [Architecture](ARCHITECTURE.md) for the system boundaries.

## Requirements

- macOS 14 as the declared minimum deployment target
- Xcode 26 or later with the full macOS 26 SDK selected
- Swift 6

The deployment target is not a completed compatibility matrix. Current local
validation is on Apple silicon; native Intel compatibility and a full macOS 14
native pass have not been verified.

The standalone Command Line Tools are not enough for this source tree. Check the
active toolchain without building:

```sh
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift --version
```

## Get the source

Fork the repository on GitHub, then clone your fork:

```sh
git clone https://github.com/YOUR-USER/fleck.git
cd fleck
git remote add upstream https://github.com/exterminatorrat/fleck.git
```

If you only want to inspect or test the canonical source, clone the upstream URL
directly instead.

## Build and test

Run the ordinary Swift package tests from the repository root:

```sh
unset FLECK_ENHANCED_CANDIDATE
swift test --disable-automatic-resolution --no-parallel
```

Build the development-signed app bundle without launching it:

```sh
Scripts/build-fleck-app.sh
```

Interactive native testing is a separate, explicit step:

```sh
/usr/bin/open -n .build/Fleck.app
```

Opening Fleck creates local Application Support data and may request macOS
permissions. Use a disposable macOS test account and synthetic fixtures, never
personal notes or recordings. The full commands and manual checks are in
[Testing](TESTING.md).

### Website

The website requires Node.js 22.12 or later:

```sh
cd website
npm ci
npm test
npm run build
```

## Repository map

```text
Sources/FleckCore/             Local models, mutations, persistence, and recovery
Sources/FleckAgentProtocol/    Typed local IPC protocol and framing
Sources/FleckApp/              Native macOS UI, editor, dictation, and IPC service
Sources/FleckAgentBridge/      MCP/CLI helper and Unix-socket client
Sources/FleckModelEvaluation/  Deterministic local-model evaluation support
Sources/FleckCaptureLab/       Developer capture tooling
Tests/                         Swift tests and privacy-safe fixtures
Scripts/                       Build, validation, audit, and profiling entry points
Packages/                      Enhanced candidate dependency package
website/                       Vite website
```

## Project principles

Fleck keeps the frequent path small and native. Prefer Apple frameworks and the
standard text system over embedded web views or replacement controls; avoid
background services and dependencies without a demonstrated need; keep notes
local by default; and preserve keyboard access, VoiceOver semantics, Reduce
Motion, contrast, and resource efficiency as features evolve.

## Contributing

Focused contributions are welcome. Read [Contributing](CONTRIBUTING.md),
[Testing](TESTING.md), and the [Code of Conduct](CODE_OF_CONDUCT.md) before
opening a pull request. Security-sensitive findings need a private channel; the
current availability and launch gate are documented in [Security](SECURITY.md).

## License and name

Fleck source is licensed under the [Mozilla Public License 2.0](LICENSE). No
contributor license agreement is required. The Fleck name, logo, and other brand
assets are reserved separately; the source license does not grant trademark
rights.

Reviewed ordinary Swift code dependencies use MIT and/or Apache-2.0 terms;
documentation and candidate assets may carry additional terms. Exact pins and
attributions are recorded in the package lockfiles and
[`ThirdPartyNotices.md`](Sources/FleckApp/Resources/ThirdPartyNotices.md).
