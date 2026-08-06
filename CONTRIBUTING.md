# Contributing to Fleck

> [!IMPORTANT]
> External code contributions and pull requests are not currently accepted.
> Reproducible bug reports and product feedback are welcome. This document records
> the maintainer workflow used to develop and release Fleck.

## Repository workflow

GitHub is the source of truth for Fleck. Intentional changes to application code, tests, documentation, assets, configuration, and release metadata must be committed and pushed; project work should not exist only on a local machine.

The preferred workflow is a dedicated feature branch:

1. Start from an up-to-date `main` branch.
2. Create a descriptive branch such as `feature/native-editor` or `fix/note-recovery`.
3. Commit cohesive, reviewable checkpoints while developing. Do not wait until the entire feature is complete to create the first commit.
4. Push the branch to GitHub regularly so work is backed up and visible.
5. Keep the branch current with `main`, resolving integration issues before final review.
6. Open a pull request early as a draft when useful, and update its description and checks as the work evolves.
7. Mark the pull request ready only when its planned scope is complete, relevant tests and documentation are updated, and required checks pass.
8. Merge the completed pull request into `main` through GitHub.
9. Delete the merged feature branch unless it is intentionally retained for a documented reason.

Direct work on `main` is reserved for exceptional, low-risk repository administration. Product features, fixes, and normal documentation changes should use a separate branch. `main` should remain buildable and represent the latest integrated state of the project.

## Branch scope

A branch should have one clear outcome. A broad milestone branch may contain several related features from the product plan, but unrelated fixes should use separate branches and pull requests. If a branch becomes difficult to review or keep current, split the remaining work into smaller branches rather than delaying all integration indefinitely.

For the initial application milestone, the branch is complete when the selected product-plan scope is implemented, tested, documented, and profiled on macOS. Partial progress should still be committed and pushed regularly; completion controls when the branch is merged, not when it is version controlled.

## Commit expectations

- Review `git status` and the complete diff before each commit.
- Use a descriptive imperative subject, such as `feat: add note tab reordering`.
- Keep generated build output, user-specific IDE state, credentials, signing keys, provisioning profiles, and secrets out of Git.
- Include tests and documentation with the behavior they cover.
- Never rewrite shared branch history without coordinating with other contributors.

## Pull request checklist

Before merging, confirm that:

- [ ] The planned branch scope is complete.
- [ ] The pull request explains the user-facing and technical changes.
- [ ] Automated tests and programmatic checks pass.
- [ ] Native UI changes were exercised on a supported macOS version.
- [ ] Perceptible UI changes include an updated screenshot when practical.
- [ ] Accessibility and keyboard behavior were considered.
- [ ] App size, idle memory, and idle CPU were profiled when the change could affect them.
- [ ] Documentation reflects the implemented behavior.
- [ ] No credentials, local-only files, or generated artifacts are included.

## Recommended commands

```sh
git switch main
git pull --ff-only
git switch -c feature/<short-description>

# Make and verify changes.
swift test
git status --short
git diff --check

git add <intentional-files>
git commit -m "type: concise description"
git push -u origin feature/<short-description>
```

Continue committing and pushing useful checkpoints to the same branch. When its planned work is complete, update the pull request, run final checks, and merge it into `main` through GitHub.
