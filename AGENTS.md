# Contributor guidance

These instructions apply to work in this repository. A direct task or
maintainer instruction may narrow the scope further.

## Work from an explicit base

Before changing files, read the request, inspect `git status`, and identify the
commit or branch the work is based on. Preserve unrelated staged, unstaged, and
untracked work. Use a focused branch or isolated worktree for product changes;
do not rewrite history or alter another worktree.

Maintainers may have a project-scoped accepted-build registry configured
outside the repository. When that optional baseline is available and the task
requires it, follow the maintainer-provided project instruction and validate
the selected record before starting. Contributors without that private
registry should use the base named in the issue or pull request. Never infer
“accepted” or “newest” from a filename, modification time, running process, or
branch name.

## Keep changes bounded

- Edit only the files needed for the requested outcome.
- Do not discard, reformat, or clean up unrelated work.
- Prefer a root-cause fix over duplicated special cases.
- Do not add dependencies, model downloads, telemetry, network services, or
  release behavior unless the request explicitly requires them.
- Never commit credentials, private user content, signing material, local
  machine paths, build output, or personal evidence artifacts.
- Treat dated plans, specifications, and reports as historical context, not
  current requirements. See [the documentation archive
  index](docs/archive/README.md).

## Verify proportionally

Run the narrowest existing checks that cover the files or behavior changed,
then expand only when the change warrants it. Review the complete diff and run
`git diff --check` before handoff. Do not claim a build, test, device run,
signature, model, or release result that was not actually verified from the
reported source and artifact.

Frontend and native-interface changes require visual inspection at the
relevant sizes and accessibility settings. Source-only documentation changes
do not require building or launching the application.

## Respect external-write boundaries

Do not push, open or close a pull request, merge, publish a release, change
repository visibility, or modify repository settings without explicit
authorization. When external writes are authorized, use a focused pull request
and report the checks performed and any remaining gates.

## Licensing and public artifacts

First-party source and documentation are licensed under MPL-2.0 except for the
boundaries identified in `NOTICE`, `BRANDING.md`, and
`THIRD_PARTY_NOTICES.md`. Preserve third-party notices and do not describe
custom-licensed models, data, or dependencies as MPL-covered. Public examples
must use repository-relative paths, environment variables, or obvious
placeholders rather than a contributor's home directory.
