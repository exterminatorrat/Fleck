# Contributing to Fleck

Focused pull requests are welcome. Fleck is a Developer Preview, so the best
contributions make one behavior easier to understand, safer, or more native
without expanding the product surface unnecessarily.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Do not put vulnerabilities or private user content in an issue; read
[Security](SECURITY.md) first.

## Before you start

1. Read the short [implementation status](IMPLEMENTATION_STATUS.md) and the
   relevant section of [architecture](ARCHITECTURE.md).
2. For a contained fix, create a branch and proceed. For a larger feature or an
   architectural change, open a short issue first once public issues are
   available so the direction can be agreed before substantial work.
3. Use a disposable macOS test account and synthetic fixtures for native flows.
   Never develop or report against personal notes, recordings, credentials, or
   permission databases.

## Set up a fork

Fork the repository on GitHub, then:

```sh
git clone https://github.com/YOUR-USER/fleck.git
cd fleck
git remote add upstream https://github.com/exterminatorrat/fleck.git
git fetch upstream
git switch -c your-focused-branch upstream/main
```

You need macOS 14 or later and Xcode 26 or later with the full macOS 26 SDK.
Fleck uses Swift tools version 6.0. The standalone Command Line Tools do not
provide the required SDK surface.

## Make a focused change

- Keep the ordinary build lightweight and local-first. Prefer native AppKit,
  SwiftUI, and Foundation behavior over new dependencies or custom substitutes.
- Keep the editor responsive and preserve standard selection, undo, spelling,
  keyboard, and accessibility behavior.
- Treat VoiceOver, Full Keyboard Access, Reduce Motion, contrast, idle CPU, and
  memory use as product requirements, not post-release cleanup.
- Keep Enhanced Local work in its opt-in candidate graph. Do not make candidate
  models, assets, or dependencies part of the ordinary release by accident.
- Update tests and contributor documentation in the same pull request when a
  public behavior, command, or boundary changes.
- Avoid drive-by formatting and unrelated refactors.

AI-assisted contributions are allowed. The human contributor remains
responsible for understanding the change, reviewing every generated line,
running the relevant checks, disclosing material limitations, and ensuring the
contribution and its inputs can be licensed to the project.

## Verify the change

At minimum, run the ordinary suite:

```sh
unset FLECK_ENHANCED_CANDIDATE
swift test --disable-automatic-resolution --no-parallel
```

Run the focused checks and manual native checks that cover your change. The
authoritative command list and evidence rules are in [Testing](TESTING.md).
Do not run an Enhanced candidate graph for an ordinary-only change.

Before committing, inspect what will be shared:

```sh
git status --short
git diff --check
git diff
```

Do not commit build output, local paths, secrets, signing material, credentials,
model weights, personal fixtures, or unsanitized logs.

## Open a pull request

Keep the pull request small enough to review. Explain:

- the user-facing problem and the chosen scope;
- the important implementation or documentation decisions;
- the exact automated and manual checks run;
- any unverified behavior, platform limitation, privacy consideration, or
  follow-up.

Screenshots are useful only for a visual change and must come from the current
candidate, contain synthetic content, and include useful alt text. Do not reuse
an older screenshot because it looks close enough.

## Licensing

The project is licensed under the [Mozilla Public License 2.0](LICENSE). There
is no contributor license agreement. By submitting a contribution, you confirm
that you have the right to provide it under the project's license. Third-party
code, assets, models, and substantial generated material need clear provenance
and compatible terms; call them out in the pull request.

The Fleck name and brand assets are reserved separately. Please do not imply
that a fork or derivative is an official Fleck release.
