# Implementation status

Fleck is a **Developer Preview**. The repository has substantial native
implementation and automated coverage, but it does not yet publish a supported,
signed release. This file is the current lightweight roadmap; architecture and
test detail live elsewhere.

## Ordinary graph

Implemented in the default Swift package graph:

- native menu-bar and pinned-window note surfaces;
- local notes, tabs, folders, search, backlinks, file references, transfer,
  30-day Trash, and recovery;
- AppKit editing with native undo, formatting, lists, and checklists;
- atomic local persistence with readable bodies and recovery data;
- Apple on-device speech, personal-dictionary handling, faithful cleanup, local
  text history, and Inbox-safe Smart Capture;
- optional system Foundation Models cleanup/routing on supported macOS 26 hosts;
- the local profile-scoped Agent Connector, explicit grants, activity, revision
  checks, idempotent mutations, and Undo;
- Swift tests, packaging scripts, boundary audits, and a Vite website.

The deployment minimum is macOS 14. Building the current source requires Xcode
26 or later with the full macOS 26 SDK and Swift 6.

## Experimental graph

Enhanced Local is an opt-in debug candidate selected with
`FLECK_ENHANCED_CANDIDATE=1`. It contains candidate Parakeet speech and Gemma
cleanup/routing work, model installation and integrity checks, resource-pressure
handling, and separate tests.

It is not enabled in the ordinary graph, not accepted for release builds, and
not approved for distribution. Candidate model quality, license/attribution,
artifact integrity, resource use, and device coverage remain release gates.

## Before a public Developer Preview

- choose and publish verified private reporting routes for vulnerabilities and
  Code of Conduct incidents;
- make the intended repository public only after the reporting and moderation
  paths are ready;
- run the ordinary non-launching macOS validator and obtain clean CI from the
  exact release commit;
- complete disposable-account native, privacy, accessibility, and resource
  checks with synthetic fixtures;
- establish signing identity, hardened runtime/entitlements as needed,
  notarization, and Gatekeeper verification;
- publish current screenshots from the accepted candidate with synthetic
  content and useful alt text;
- tag and describe the first 0.x release without implying production support.

See [Releases](docs/RELEASES.md) for the maintainer checklist.

## Not promised

There is no supported binary, release history, cloud sync, account service,
real-time collaboration, plug-in marketplace, or distribution-ready Enhanced
Local model in this preview. Those are not implied by source experiments or
tests.
