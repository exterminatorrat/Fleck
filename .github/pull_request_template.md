<!--
Title format: <type>(<scope>): <summary>
Types: feat, fix, perf, refactor, docs, test, build, ci, chore, revert
Standard: docs/commit-and-pr-standards.md
-->

## Type of change

Pick one primary type.

- [ ] `feat`: new user-visible capability
- [ ] `fix`: corrects incorrect behavior
- [ ] `perf`: speed, memory, CPU or energy improvement
- [ ] `refactor`: internal restructure, no behavior change
- [ ] `docs` / `test` / `build` / `ci` / `chore`
- [ ] `revert`
- [ ] Breaking change (explain the migration below)

## Summary

What changed, in two to four sentences.

## Why

The user-facing problem or need. Link the issue: `Refs #` or `Fixes #`.

## Approach

Key decisions and any alternatives rejected.

## User impact

What a Fleck user will notice, or "None".

## Risk and rollback

Risk level (low, medium, high) and why. What could break, how it would show,
and how to revert.

## Verification

List exact automated and manual checks, including macOS version for native
checks. State anything not tested.

## Version and changelog

- [ ] `VERSION` and `CHANGELOG.md` updated together
- [ ] Not needed (reason):

## Evidence

Screenshots or recordings for visual changes only. Write "N/A" otherwise.

## Follow-ups

Known limits and deferred work, each linked to an issue where possible.

## Checklist

- [ ] The title follows the `<type>(<scope>): <summary>` format.
- [ ] The pull request delivers one coherent outcome.
- [ ] The diff contains no unrelated changes, generated output, secrets, local paths, model weights, or private test data.
- [ ] Tests and contributor docs cover changed behavior where needed.
- [ ] Native, privacy, accessibility, resource, and Enhanced-candidate boundaries were considered.
- [ ] Visual evidence, if included, comes from the current candidate, uses synthetic content, and has useful alt text.
- [ ] Third-party and AI-assisted material has been reviewed for correctness, provenance, and compatible licensing.
