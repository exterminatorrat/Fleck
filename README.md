<p align="center">
  <img src="website/public/fleck-mark.png" alt="Fleck mark" width="96">
</p>

<h1 align="center">Fleck</h1>

<p align="center">A native, local-first macOS notes workspace for quick capture, focused editing, on-device dictation, and explicitly granted local agent access.</p>

<p align="center">
  <a href="#requirements"><img alt="macOS 14+ deployment target" src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&amp;logoColor=white"></a>
  <a href="Package.swift"><img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white"></a>
  <a href="https://github.com/exterminatorrat/Fleck/actions/workflows/ci.yml?query=branch%3Amain"><img alt="CI status for main" src="https://github.com/exterminatorrat/Fleck/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="License: MPL-2.0" src="https://img.shields.io/badge/license-MPL--2.0-6355a6"></a>
  <a href="docs/RELEASES.md"><img alt="Status: source preview" src="https://img.shields.io/badge/status-source%20preview-4b5563"></a>
</p>

<p align="center">
  <a href="#what-is-here">Features</a> ·
  <a href="#build-and-test">Build &amp; test</a> ·
  <a href="ARCHITECTURE.md">Architecture</a> ·
  <a href="TESTING.md">Testing</a> ·
  <a href="#contributing">Contributing</a> ·
  <a href="SECURITY.md">Security</a>
</p>

> **Source Preview:** This repository publishes Fleck source for inspection and
> local development. It provides no signed or notarized app, GitHub Release,
> supported release, or downloadable binary.

> **Developer Preview:** Fleck is under active development. There is no
> supported binary release yet, and storage formats and contributor-facing
> interfaces may change during the 0.x series.

## What is here

The ordinary build contains:

| Area | Current implementation |
| --- | --- |
| Native workspace | Menu-bar workspace and an independently sized pinned window. |
| Notes and organization | Local notes, tabs, folders, search, backlinks, file references, import/export, 30-day Trash, and recovery. |
| Native editor | An AppKit `NSTextView` editor with native undo, formatting, lists, and checklists. |
| On-device dictation | Apple on-device speech recognition, optional faithful local cleanup, and Inbox-safe Smart Capture routing. |
| Agent Connector | A separately packaged local helper with profile-scoped capabilities, explicit note or folder grants, visible activity, revision checks, and Undo. |
| Local persistence | Readable local storage with atomic replacement and a previous-generation recovery snapshot. |

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

| Requirement | Version or scope |
| --- | --- |
| macOS | 14 as the declared minimum deployment target. |
| Xcode | 26 or later, with the full macOS 26 SDK selected. |
| Swift | 6. |
| Node.js | 22.12 or later, for the website only. |

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
Scripts/run-nonempty-swift-tests.sh '^.+$'
```

The test runner does not launch the product `Fleck.app`, but its synthetic
AppKit host may create fixture windows and change focus. Run native fixtures in
a disposable macOS test account or session with synthetic content.

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

| Path | Responsibility |
| --- | --- |
| `Sources/FleckCore/` | Local models, mutations, persistence, and recovery. |
| `Sources/FleckAgentProtocol/` | Typed local IPC protocol and framing. |
| `Sources/FleckApp/` | Native macOS UI, editor, dictation, and IPC service. |
| `Sources/FleckAgentBridge/` | MCP/CLI helper and Unix-socket client. |
| `Sources/FleckModelEvaluation/` | Deterministic local-model evaluation support. |
| `Sources/FleckCaptureLab/` | Developer capture tooling. |
| `Tests/` | Swift tests and privacy-safe fixtures. |
| `Scripts/` | Build, validation, audit, and profiling entry points. |
| `Packages/` | Enhanced candidate dependency package. |
| `website/` | Vite website. |

## Project principles

Fleck keeps the frequent path small and native. Prefer Apple frameworks and the
standard text system over embedded web views or replacement controls; avoid
background services and dependencies without a demonstrated need; keep notes
local by default; and preserve keyboard access, VoiceOver semantics, Reduce
Motion, contrast, and resource efficiency as features evolve.

## Contributing

Public contribution intake is not open yet. The future workflow is documented
in [Contributing](CONTRIBUTING.md) and [Testing](TESTING.md). The owner-approved
private conduct route is email to [Harry](mailto:harrythemen@outlook.com), but
inbox delivery has not yet been tested. Participation remains closed until that
delivery check, green CI at the final source commit, the reviewed launch changes
are merged, and explicit issue and pull-request intake readiness is verified.
Security-sensitive findings use the separate route documented in
[Security](SECURITY.md), not the conduct address.

## License and name

Fleck-owned source and documentation in the current tree are licensed under the
[Mozilla Public License 2.0](LICENSE), subject to the boundaries in
[NOTICE](NOTICE), [Branding](BRANDING.md), and
[Third-party notices](THIRD_PARTY_NOTICES.md). Earlier revisions remain subject
to the license notices and terms accompanying those revisions. No contributor
license agreement is required. The Fleck name, logo, and other brand assets are
reserved separately; the source license does not grant trademark rights.

Reviewed ordinary Swift code dependencies use MIT and/or Apache-2.0 terms;
documentation and candidate assets may carry additional terms. Exact pins and
attributions are recorded in the package lockfiles and
[`ThirdPartyNotices.md`](Sources/FleckApp/Resources/ThirdPartyNotices.md).
