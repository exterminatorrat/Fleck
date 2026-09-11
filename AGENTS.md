# Engineering and GitHub workflow

## Efficient Astra implementation workflow

Use the globally installed `astra-efficient-coding` skill for every nontrivial
coding task. The normal sequence is Astra architecture, a bounded Sol
implementation, parent inspection and verification, then a fresh Astra review
of the actual diff and evidence. Sol Advisor is retired and must not be invoked,
required, or emulated. Never use Terra or silently substitute a model, lane, or
reviewer when an explicit task override is unavailable.

Every implementation packet must define its objective, exact ownership,
requirements and non-goals, verification evidence, and authority boundaries.
Preserve unrelated and concurrent work. Parallel implementation is permitted
only for independent packets in isolated worktrees with disjoint ownership;
dependent or overlapping packets remain sequential. Do not call meaningful
work complete until parent verification passes and the required fresh Astra
review accepts the result.

## GitHub branch, PR, merge, and sync workflow

GitHub is the operational source of truth. For normal product work, begin by
fetching and synchronizing local `main` with `origin/main`, then create a
focused branch from that synchronized base. Never perform normal product work
directly on `main`.

Make intentional, focused commits and push checkpoints. Open or update the
corresponding pull request. Before merge, require relevant local checks, green
GitHub CI, and approval from the required fresh Astra review. Merge through GitHub, then fetch
and fast-forward local `main` to `origin/main`; verify a clean worktree,
ahead/behind state, unmerged entries, and no merge in progress.

Never push, merge, open or close pull requests, or change GitHub/repository
settings unless the current user has authorized those external writes. Preserve
unrelated dirty, staged, untracked, and concurrent work throughout.

## Version, build, and accepted-baseline provenance

`VERSION` is the only product-version authority. Update it and the matching
dated `CHANGELOG.md` heading together for product changes: small fixes and small
features increment PATCH, substantial feature sets increment MINOR, and beta
product changes use that same PATCH/MINOR rule while resetting to `beta.1`.
Prerelease-only iterations increment
`beta.N`. Removing a prerelease suffix requires an explicit decision. A rebuild
of unchanged source keeps the product version but receives a new build identity.

Before baseline, packaging, handoff, acceptance, or "newest accepted" work,
read `/Users/harryjin/Fleck-builds/accepted/manifest.json`, its adjacent
`manifest.sha256`, and `workflow.md`. Use `latestAcceptedRecordID` only while
`registryStatus` is `active`, and verify it with the preserved read-only
validator. `BuildBaseline.json` pins the expected canonical manifest and source;
never update the pin, infer a newer record, relabel an existing artifact, or
promote acceptance as part of ordinary packaging.

Only a clean committed descendant of the pinned accepted source may produce a
local handoff candidate. Build it fresh in its isolated worktree and report the
full source commit/tree, product version, build number, build UUID, bundle
identifier, candidate status, baseline record/hash/status, and executable
SHA-256. Hosted `ci-unverified` bundles are never handoff or acceptance
candidates. A filename, modification time, branch, installed app, or running
process is not provenance. See `docs/build-identity.md` for the complete policy.
