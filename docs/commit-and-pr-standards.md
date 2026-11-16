# Commit and pull request standards

Every change to Fleck is recorded in two places: the commits that make it and
the pull request that reviews it. Both must let someone who was not present
understand what changed, why, how it was checked, and how risky it is. This
page is the standard. The [pull request template](../.github/pull_request_template.md)
and the [commit message template](../.gitmessage) put it into practice.

## Principles

- One pull request delivers one coherent outcome. Commits are checkpoints inside
  it; a commit does not need its own pull request.
- The type of every change is stated, never implied: feature, fix, refactor,
  and so on.
- The description explains why. The diff already shows what.
- Verification is exact. Name the commands and manual checks that ran, and name
  what did not run.
- Risk is stated up front so the reviewer knows where to look.

## Change types

Commits and pull request titles use one of these types.

| Type | Use for | Changelog section | Version effect |
| --- | --- | --- | --- |
| `feat` | New user-visible capability | Added | PATCH for a small feature; MINOR only by human decision |
| `fix` | Corrects incorrect behavior | Fixed | PATCH |
| `perf` | Measurable speed, memory, CPU or energy improvement | Changed | PATCH |
| `refactor` | Internal restructure, no behavior change | none | none |
| `docs` | Documentation only | none | none |
| `test` | Tests only | none | none |
| `build` | Build, packaging, dependencies, signing | none, unless user-visible | none |
| `ci` | Workflows and automation | none | none |
| `chore` | Maintenance that fits nowhere else | none | none |
| `revert` | Reverts an earlier change | follows the reverted change | follows the reverted change |

A change to existing user-visible behavior that is neither a fix nor a new
capability uses `feat` or `fix` as fits best and appears under **Changed** in
the changelog. Security-sensitive fixes use `fix` and appear under **Security**
once disclosure is safe; report vulnerabilities privately first (see
[SECURITY.md](../SECURITY.md)).

A breaking change adds `!` after the type or scope, for example
`feat(storage)!: ...`, and explains the break and migration in the commit body
under a `BREAKING CHANGE:` footer.

## Commit messages

Format:

```text
<type>(<optional scope>): <summary>

<body>

<footers>
```

Subject line:

- Imperative mood: "Keep resize cursor inside the key window", not "kept" or
  "keeps".
- Describe the effect, not the file touched.
- No trailing period. Aim for 72 characters or fewer.
- Scope is an area of the product, such as `editor`, `menu-panel`, `mcp`,
  `autosave`, `accessibility`, `release`, `docs`.

Body (required for every `feat`, `fix`, `perf` and any non-obvious change;
optional for trivial `docs`, `test` and `chore`):

- **Why**: the problem or need, and what was wrong before.
- **What**: the approach, and any alternative you rejected with the reason.
- **Impact**: user-visible behavior, accessibility, privacy, performance or
  data-compatibility consequences.

Wrap at 72 columns. Explain, do not narrate the editing session.

Footers, one per line, when they apply:

```text
Refs: FLEC-200
Fixes: #123
BREAKING CHANGE: <what breaks and how to migrate>
Co-authored-by: Name <email>
```

Example:

```text
fix(menu-panel): keep resize cursor off the note interior

The resize cursor appeared over note text because the cursor region
extended past the border handles into the editor.

Reserve a three-point geometry band and admit the cursor only inside a
seven-point region at the borders. Cursor artwork is unchanged.

Impact: resizing from the border behaves as before; the note interior
keeps the text cursor. No accessibility or persistence change.

Refs: FLEC-199
```

Merge commits that integrate branches keep their default message. Squash merges
use the pull request title as the subject and the pull request summary as the
body, so write both as if they were the final commit.

## Branches

Use `<type>/<short-kebab-description>`, for example
`fix/menu-panel-resize-cursor`. Automation-created branches may keep their
tool prefix and ticket id, such as `capy/flec200-...`. Keep one outcome per
branch.

## Pull requests

### Title

Same format as a commit subject: `<type>(<scope>): <summary>`. The title is the
permanent record of the change in the history and release notes, so it states
the outcome in plain words.

### Description

The [template](../.github/pull_request_template.md) is required. Every section
is filled in or marked "N/A" with a reason.

1. **Type of change**: exactly one primary type from the table above.
2. **Summary**: what changed, in two to four sentences.
3. **Why**: the user-facing problem or need, with a link to the issue.
4. **Approach**: key decisions and rejected alternatives.
5. **User impact**: what a Fleck user will notice, or "None".
6. **Risk and rollback**: what could break, how likely, how to detect it, and
   how to revert. Low, medium or high, with the reason.
7. **Verification**: exact commands, test counts, and manual native checks on
   which macOS version. State anything not tested.
8. **Version and changelog**: whether `VERSION` and `CHANGELOG.md` changed, per
   [build identity](build-identity.md), and why or why not.
9. **Evidence**: screenshots or recordings only for visual changes, from the
   current candidate, with synthetic content and alt text.
10. **Follow-ups**: known limits and deferred work, each as an issue where
    possible.

### Size and scope

Review quality drops as diffs grow. Split a pull request that mixes types, such
as a refactor combined with a feature. A change over roughly 400 changed lines
of product code needs a note explaining why it cannot be split.

### Review and merge

- A pull request is ready for review only when its checks pass locally and the
  description is complete. Use a draft until then.
- The author reviews the full diff before requesting review: no stray files,
  secrets, local paths or unrelated edits.
- Reviewers check the description against the diff. A description that no
  longer matches is a review finding.
- Resolve every review thread, by change or by a stated reason.
- Required checks must be green at the final commit before merge.
- Nothing is merged, tagged or released without explicit maintainer
  authorization. See [releases](RELEASES.md).

## Changelog and version

`VERSION` and `CHANGELOG.md` change together, in the same commit, as described
in [build identity](build-identity.md). Write changelog entries for users:

- Group under **Added**, **Changed**, **Fixed**, **Security** or **Removed**.
- One entry per user-visible change, written from the user's side, not the code's.
- Skip `refactor`, `docs`, `test`, `ci` and `chore` unless users notice them.

## Using AI assistants

AI-assisted changes follow this same standard. The human contributor reviews
every generated line, confirms the description matches the diff, and reports
only checks that actually ran.
