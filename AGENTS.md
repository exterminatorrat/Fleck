# Engineering and GitHub workflow

## Sol Advisor is mandatory for change-producing work

Use `$sol-advisor:orchestration` for every task that can modify product
behavior, source or native code, configuration, tests, build systems,
operational behavior, or reliability. Read-only orientation and explanation
may remain in the primary Sol session.

For covered work, the primary session must be GPT-5.6 Sol at High reasoning
and must first run the orchestration exactness check and confirm the exact
user-visible Codex task tools and GPT-5.6 Luna/Max route are available; there
is no native implementer preflight. It writes a bounded five-part specification:

1. Objective and success criteria.
2. Owned files, interfaces, and constraints.
3. Required implementation and explicit non-goals.
4. Verification commands and expected evidence.
5. Authority boundaries and the required handoff.

Implementation is only through one or more separate user-visible Codex tasks
running GPT-5.6 Luna at Max reasoning, created and orchestrated by the primary
Sol session; Luna/Max is the only implementation route, never Terra or native
subagents. The primary chooses the smallest useful independent partition;
requested agent count does not override safe decomposition. Parallel independent
tasks may run concurrently only when their file/module ownership sets are
disjoint with no overlap and they have no sequential dependency, with each task
using a separate worktree.
Tasks sharing files/modules or having dependencies integrate serially under the
primary. Every implementation packet must identify ownership, preserve
unrelated work, and require adaptation to concurrent edits. The primary Sol
inspects all parent diffs and reruns the required verification. A fresh
`sol_advisor_sol_reviewer` (Sol, High) then reviews the actual integrated diff
and evidence. Do not call the work complete unless its verdict is `ship`.

For `fix-first`, return corrected bounded findings and specification to the same
responsible user-visible Luna/Max task, then repeat parent verification and
obtain a new fresh Sol review.

For `rethink`, return to the primary Sol session for architecture/scope
reconsideration and a newly settled specification before any further
implementation routing.

Do not silently repair a child patch, substitute another agent, model, or
reasoning level, or treat a worker report as verification.

## GitHub branch, PR, merge, and sync workflow

GitHub is the operational source of truth. For normal product work, begin by
fetching and synchronizing local `main` with `origin/main`, then create a
focused branch from that synchronized base. Never perform normal product work
directly on `main`.

Make intentional, focused commits and push checkpoints. Open or update the
corresponding pull request. Before merge, require relevant local checks, green
GitHub CI, and the final Sol `ship` verdict. Merge through GitHub, then fetch
and fast-forward local `main` to `origin/main`; verify a clean worktree,
ahead/behind state, unmerged entries, and no merge in progress.

Never push, merge, open or close pull requests, or change GitHub/repository
settings unless the current user has authorized those external writes. Preserve
unrelated dirty, staged, untracked, and concurrent work throughout.
