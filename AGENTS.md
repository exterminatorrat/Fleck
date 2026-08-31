# Engineering and GitHub workflow

## Implementation lane selection for change-producing work

The default implementation lane is `$sol-advisor:orchestration` with a
user-visible GPT-5.6 Luna task at Max reasoning. This default applies to every
task that can modify product behavior, source or native code, configuration,
tests, build systems, operational behavior, or reliability. Read-only
orientation and explanation may remain in the primary Sol session.

The current user can explicitly select Codex-native subagents for a task. An
instruction such as "use Codex-native subagents" activates the native-subagent
lane for the entire task: do not create or use a Sol Advisor Luna-Max
implementation task, and route all implementation and correction work through
Codex-native worker subagents instead. This selection is sticky across every
later turn, packet, and fix loop in that task until the current user explicitly
says to revert to the Sol Advisor Luna-Max task lane. Do not silently switch
lanes. If a later instruction makes the active lane ambiguous, surface the
conflict before delegation.

For the default Sol Advisor lane, the primary session must be GPT-5.6 Sol at
High reasoning and must first run the Sol Advisor Luna task-lane capability
gate. For the native-subagent lane, the primary session remains the
orchestrator and writes the same bounded five-part specification before
delegation:

1. Objective and success criteria.
2. Owned files, interfaces, and constraints.
3. Required implementation and explicit non-goals.
4. Verification commands and expected evidence.
5. Authority boundaries and the required handoff.

The primary Sol session remains the orchestrator and integrator. In the default
lane, implementation is only through user-visible Codex tasks running GPT-5.6
Luna at Max reasoning, created and supervised through
`$sol-advisor:orchestration`; do not silently fall back when that lane is
unavailable. In the native-subagent lane, implementation is only through
Codex-native worker subagents created and supervised by the primary session;
do not create a user-visible Luna implementation task. Multiple implementation
workers may run in parallel only when their bounded packets are independent,
use isolated worktrees, and have exact, disjoint file ownership. Work that
shares interfaces, depends on another unaccepted diff, or can touch the same
files remains sequential.
This `AGENTS.md` routing policy supersedes any conflicting worker-model or
routing text in historical plans or specifications.
Each implementation packet must identify ownership, preserve unrelated work,
require adaptation to concurrent edits, and forbid edits outside its owned
paths. The primary Sol inspects each parent diff and reruns the required
verification. A fresh
`sol_advisor_sol_reviewer` (Sol, High) then reviews the actual diff and
evidence. Do not call the work complete unless its verdict is `ship`.

For `fix-first` or `rethink`, return a corrected bounded specification through
the active implementation lane: the same Luna implementation task in the
default lane, or the same Codex-native worker in the native-subagent lane.
Repeat parent verification and obtain a new fresh Sol review. Do not silently
repair a child patch, substitute another agent, model, reasoning level, or
implementation lane, or treat a worker report as verification. A `rethink`
verdict returns architecture to the primary Sol session before the corrected
packet is sent through the active lane.
Do not start a dependent packet until every prerequisite diff has the required
fresh `ship` verdict.

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
