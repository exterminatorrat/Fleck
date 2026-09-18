# Implementation status

Fleck is a **Developer Preview**: the first public preview, `1.1.2-beta.2`, is
prepared and published as a preview. The repository has substantial native
implementation and automated coverage, but the preview carries no support
promise and the community-facing gates (signing/notarization where applicable,
release screenshots, announcement) are completed as part of that release. This
file is the current lightweight roadmap; architecture and test detail live
elsewhere.

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
- Swift tests, packaging scripts, and boundary audits.

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

## Release status

- First public Developer Preview: `1.1.2-beta.2`. Release notes and first-launch
  onboarding:
  [`docs/release-notes/1.1.2-beta.2.md`](docs/release-notes/1.1.2-beta.2.md).
- Completed: verified private reporting routes, public repository, clean CI at
  the release source (2,543 ordinary tests in 37 suites plus the 2,754-test
  Enhanced Local graph and the packaging/audit chain).
- Pending as of preparation: signing identity, notarization, and Gatekeeper
  verification where the release asset applies them; release-candidate
  screenshots; the annotated tag and GitHub Release with checksums.
- The release is titled 1.1.2-beta.2 Developer Preview and does not imply
  production support; see the progression ladder in
  [`docs/RELEASES.md`](docs/RELEASES.md) for how versions advance.

See [Releases](docs/RELEASES.md) for the maintainer checklist.

## Not promised

There is no supported (non-preview) binary, cloud sync, account service,
real-time collaboration, plug-in marketplace, or distribution-ready Enhanced
Local model in this preview. Release history begins with the 1.1.2-beta.2
Developer Preview; those other promises are not implied by source experiments
or tests.
