# Engineering and GitHub workflow

## Sol orchestration is mandatory for change-producing work

Use `$sol-advisor:orchestration` for every task that can modify product
behavior, source or native code, configuration, tests, build systems,
operational behavior, or reliability, but only to the extent the installed
skill is compatible with the routing policy below. Read-only orientation and
explanation may remain in the primary Sol session. If an installed Sol Advisor
skill requires Luna/Max, user-visible implementation tasks, or another
conflicting implementation lane, do not run that incompatible workflow; this
tracked `AGENTS.md` policy controls, and the primary Sol must apply the bounded
specification, verification, and review requirements directly.

For covered work, the primary session must be GPT-5.6 Sol at High reasoning and
remains the orchestrator and integrator. Before implementation it writes a
bounded five-part specification:

1. Objective and success criteria.
2. Owned files, interfaces, and constraints.
3. Required implementation and explicit non-goals.
4. Verification commands and expected evidence.
5. Authority boundaries and the required handoff.

Implementation is only through Codex-native subagents running GPT-5.6 Sol at
High reasoning, spawned and supervised by the primary Sol session. Do not use
GPT-5.6 Luna, Terra, user-visible Codex implementation tasks, or any other
model, effort, agent, or lane unless the user explicitly changes this routing
in a later request. The primary chooses the smallest useful independent
partition. Multiple implementation subagents may run in parallel only when
their bounded packets have exact, disjoint file ownership, use isolated
worktrees, and have no sequential dependency. Work that shares interfaces,
depends on an unaccepted diff, or can touch the same files remains sequential.

Each implementation packet must identify ownership, preserve unrelated work,
require adaptation to concurrent edits, and forbid edits outside its owned
paths. After each packet, the primary Sol inspects the actual diff and
independently reruns the required verification. A fresh
`sol_advisor_sol_reviewer` (Sol, High) then reviews that packet's actual diff
and evidence. Do not accept the packet or call its work complete unless the
fresh reviewer verdict is exactly `ship`.

For `fix-first`, return a corrected bounded specification to the same
responsible Sol/High implementation subagent, repeat independent primary
verification, and obtain a new fresh Sol/High review. For `rethink`, return
architecture and scope to the primary Sol session before sending a corrected
packet to that same subagent. Do not silently repair a child patch, substitute
another agent, model, reasoning level, or implementation lane, or treat a
worker report as verification. Do not start a dependent packet until every
prerequisite packet has the required fresh verdict of exactly `ship`.

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
