# Fleck MCP Capability Platform Design

**Status:** Proposed for user review
**Date:** 2026-08-08
**Scope:** MCP capability foundations, durable Swarm-style work handoffs, and
the later community add-on registry and execution model

## Decision Summary

Build Fleck's next differentiator as three ordered layers:

1. A deep MCP Capability Platform that exposes authorized workspace context,
   organization, graph traversal, typed editing, and bounded atomic change sets.
2. Durable Work Items that let external orchestrators coordinate agents through
   Fleck without making Fleck an agent runtime.
3. A community add-on registry and directory, followed only later by executable
   add-ons through a proven sandbox broker.

The capability platform and Work Items form the first product release, but they
must ship as separate, reviewable implementation phases. The community registry
begins only after the capability and protocol contracts are stable. Fleck must
not offer one-click arbitrary native add-on execution under its current
non-sandboxed packaging.

When this design was written on 2026-08-08, Fleck was source-available under
PolyForm Shield 1.0.0 and a license change was outside its scope. Fleck has
since moved to MPL-2.0; `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`
define the current boundary. Add-ons still declare and retain independent
licenses.

## Verified Starting Point

This design is based on the repository and GitHub state observed on 2026-08-08:

- `origin/main` is `cd3efc0`.
- PR #16, `codex/fleck-search-folder-integration`, is open, clean, and green at
  `8d3896f8303ceb66ea1b326bef3fc113720e7ad7`.
- PR #17, `codex/fleck-backlinks`, is merged at its exact reviewed head
  `031cab8e0a2194aa3654dcd1518c61998d22c63d` into the stacked PR base.
- The shared checkout has an unrelated modification in
  `Sources/FleckApp/NotesPanel.swift`; this design does not alter or claim it.
- The current Agent Connector has 13 MCP tool names mapped to 12 canonical
  workspace commands. `delete_lines` is intentionally an MCP adapter over the
  canonical `replaceLines` command.
- The existing authority path already provides per-note opt-in, profile
  credentials, same-user Unix-socket IPC, optimistic revisions, caller-owned
  operation IDs, durable transaction reconciliation, activity, and safe Undo.
- Search, flat folders, stable Fleck Markdown links, outgoing-link parsing, and
  derived backlinks exist in the stacked integration state and are prerequisites
  for the context tools in this design.

Implementation must start from the eventual accepted integration base, not from
this detached planning worktree. If PR #16's final integrated behavior differs
from this snapshot, the implementation plan must reconcile the spec before code.

## Goals

- Make MCP tools Fleck's primary agent capability surface.
- Let an authorized agent discover, search, traverse, organize, and edit the
  exact workspace context the user grants.
- Preserve the current privacy rule: private, unauthorized, and unknown targets
  are indistinguishable.
- Centralize capability checks, revisions, idempotency, persistence, activity,
  and Undo behind one native authority seam.
- Support atomic, bounded multi-note edits with preview and proposal workflows.
- Provide durable coordination records for external agents and orchestrators.
- Make every grant, inherited scope, write, proposal, lease, result, and
  cancellation visible and revocable by the user.
- Establish immutable, source-linked, versioned community add-on metadata before
  any broad executable ecosystem is offered.

## Non-Goals

- Fleck does not spawn, schedule, host, or select AI agents.
- Fleck does not provide prompts, model routing, inference, or billing.
- Context Packs and other convenience abstractions are not part of v1.
- `get_related_notes` is not part of v1. Search and explicit graph traversal are
  the deeper primitives; a derived related-notes tool can be considered after
  real usage demonstrates a stable ranking contract.
- Nested folders, tags, arbitrary paths, shell execution, settings changes,
  sharing changes, credentials, Trash, Dictation History, and note deletion are
  not exposed.
- iCloud sync, onboarding polish, and AI/dictation behavior are excluded.
- Community review is not a malware-proofing claim.
- Fleck does not load third-party native dynamic libraries in-process.

## Alternatives Considered

### Recommended: capability kernel, then Work Items, then ecosystem

Add a small canonical command interface backed by one authorization and
transaction kernel. MCP tools remain adapters. Work Items use the same identity,
grant, activity, idempotency, and error rules. The public registry follows after
the protocol is stable; executable add-ons wait for a proven broker.

This approach has the greatest module depth: callers learn a small set of stable
rules while Fleck hides filtering, revision checks, transaction recovery, grant
revocation, pagination, and audit behavior inside the native authority.

### Rejected: add tools directly to the existing command switch

This is initially faster, but every tool would repeat scope checks, filtering,
error shaping, persistence, and activity logic. The deletion test fails: removing
the command service would spread authorization complexity across search, links,
folders, work items, and the bridge. It also makes future add-ons depend on
Fleck's implementation details rather than a stable capability interface.

### Rejected: build the add-on runtime first

An extension host before the capability model would either grant broad access or
reimplement permissions per add-on. Under the current non-sandboxed package it
would also create an unjustified native-code safety claim. The registry can be
designed now, but execution follows the authority kernel and sandbox evidence.

## Domain Language

These terms are canonical throughout product copy, protocol models, tests, and
future plans.

| Term | Meaning |
| --- | --- |
| **Agent Profile** | A user-created authorization identity with one credential, display name, grant revision, and revocation state. |
| **Execution Identity** | Caller-supplied run metadata used for attribution, never authorization. It contains an opaque instance ID and optional label. |
| **Capability** | A stable domain permission such as reading notes, traversing links, applying changes, or claiming work. It is not an MCP tool name. |
| **Tool** | A model-controlled MCP interface that maps to one canonical command. Aliases may map to the same command. |
| **Grant** | A user-authored binding of capabilities, authority, and resource scope to one Agent Profile. Agents cannot create or widen grants. |
| **Authority** | The cumulative access level `read`, `propose`, or `write`. `write` includes `propose` and `read`; `propose` includes `read`. |
| **Scope** | The notes, folders, organization metadata, or Work Pools to which a grant applies. |
| **Change Set** | An immutable, bounded collection of typed edits evaluated and committed as one atomic transaction. |
| **Proposal** | A durable Change Set submitted by an agent for local user approval. A proposal is not a mutation. |
| **Work Pool** | A user-created coordination scope containing member Agent Profiles. Membership grants work-item visibility only, never note access. |
| **Work Item** | A durable coordination record with dependencies, parentage, state, lease, context references, attempts, and results. |
| **Lease** | A time-bounded exclusive claim on a Work Item, proven by a secret lease token. |
| **Add-on** | A separately versioned package that declares tools, requested capabilities, compatibility, provenance, and license. |
| **Registry Entry** | Immutable metadata for one exact add-on version. Listing does not authorize or execute the add-on. |
| **Execution Broker** | A future OS-enforced, out-of-process runtime that mediates every executable add-on operation through typed capabilities. |

## Architecture

```text
MCP client or CLI
  -> FleckAgentBridge MCP adapter
  -> versioned FleckAgentProtocol command
  -> profile authentication
  -> Capability Authority
  -> Workspace Capability Kernel
       -> query adapters: workspace, search, links
       -> mutation adapters: note, task, organization, change set
       -> coordination adapter: Work Item Store
  -> atomic persistence + activity + idempotency records
  -> filtered typed response
```

### Module and seam design

#### MCP Adapter

`FleckAgentBridge` owns MCP names, descriptions, JSON schemas, pagination
arguments, structured content, and aliases. It does not decide access, read
workspace files, inspect grants, or implement mutations. Its interface is a
profile-filtered tool registry plus canonical command conversion.

Tool discovery is filtered by the authenticated profile's allowed capabilities.
Every invocation is reauthorized natively because clients may cache `tools/list`.
When the SDK supports it reliably, the helper advertises `listChanged` and emits
`notifications/tools/list_changed` after a grant revision changes. MCP explicitly
supports capability negotiation, profile-independent tool schemas, structured
tool errors, and tool-list change notifications.

#### Wire Protocol

`FleckAgentProtocol` owns versioned canonical commands, responses, cursors, and
stable error payloads. MCP aliases do not appear here. The current integer wire
protocol version is distinct from MCP's date-based negotiated protocol version.

Capability Platform commands require internal wire protocol v2. Fleck accepts the
v1 subset during a compatibility window so an installed older helper fails
closed rather than corrupting state. Unsupported commands return a stable
protocol-version error with no workspace content.

#### Capability Authority

The Capability Authority is a deep module with one conceptual interface:

```text
authorize(profile, capability, requiredAuthority, resourceSelector)
  -> AuthorizedScope | safe error
```

Its implementation authenticates the profile, loads the current grant revision,
evaluates tool allowlists, resolves scopes, filters inaccessible resources, and
produces an immutable authorization snapshot. Callers and tests use the same
seam. No query or mutation adapter performs an independent permission decision.

#### Workspace Capability Kernel

The kernel serializes canonical commands and hides the full operation lifecycle:

1. Authenticate and authorize against one grant revision.
2. Reconcile interrupted prior transactions.
3. Return a prior receipt for a repeated operation ID in the same actor scope.
4. Capture workspace and persistence generations.
5. Plan the query or mutation against authorized immutable snapshots.
6. Recheck grant revision, workspace generation, resource membership, and note
   revisions at commit.
7. Commit atomically, then publish activity and receipts.

The kernel extends the existing `AgentCommandService` seam; it does not create a
parallel persistence path.

#### Pure query and mutation modules

`FleckCore` continues to own portable behavior. Existing `WorkspaceSearchEngine`,
`NoteLinkParser`, `BacklinkIndexer`, `Workspace`, `AgentNoteMutationEngine`, and
`AgentUndoEngine` become adapters behind the kernel. New pure modules plan Change
Sets, evaluate Work Item transitions, and validate grants without AppKit or
SwiftUI dependencies.

#### Persistence adapters

- Notes and organization changes continue through `LocalStore`'s atomic
  workspace generation commit.
- `Workspace.organizationRevision` is a new monotonic persisted value. It
  increments once for every committed folder create/rename/reorder/delete,
  note create/move, or pin mutation. It is independent of a note's content
  revision and is exposed in organization reads and receipts.
- Capability profiles and grants use a versioned, atomic profile document; only
  credential verifiers remain in Keychain.
- Proposals and Work Items use dedicated versioned local stores with atomic
  writes and previous-generation recovery. Their failure cannot make notes
  unreadable.
- Activity and idempotency records retain exact actor and operation scope.

## Capability and Grant Semantics

### Capability families

The initial stable capability IDs are:

| Family | Capability IDs |
| --- | --- |
| Context | `notes.list`, `notes.read`, `notes.search`, `links.traverse` |
| Organization | `folders.list`, `folders.manage`, `notes.create`, `notes.organize`, `ui.openNote` |
| Change | `notes.write`, `changes.preview`, `changes.propose`, `changes.apply`, `changes.undo` |
| Coordination | `work.list`, `work.create`, `work.claim`, `work.coordinate`, `work.cancel` |

Capability IDs are append-only within a protocol major version. New tools cannot
silently reuse a broader existing capability.

### Note and folder scopes

Direct Note Grants name exact stable note UUIDs and continue to apply if a note
moves folders.

Folder Grants have one of two explicit modes:

- **Current notes only:** at grant creation, Fleck materializes direct Note
  Grants for the folder's current notes. Later notes receive no access.
- **This folder, including future notes:** access follows current folder
  membership. Moving a note out revokes this grant immediately; moving a note in
  grants the selected authority immediately.

The second mode is never the default. The UI names it exactly, shows its broader
effect, and records the user's confirmation. Folder rename does not affect the
grant because identity is UUID-based. Folder deletion revokes the dynamic folder
grant; it does not convert the grant to all unfiled notes.

Folder metadata and note content are separate scopes. A profile can manage a
folder name without receiving note bodies. A note returned through a direct Note
Grant includes `folder_id` and folder name only when the profile also has metadata
visibility for that folder; otherwise both are absent.

### Creation semantics

Agents cannot self-grant by creating resources.

- `create_note` requires an explicit grant for note creation in one named folder
  or the unfiled root, plus an explicit **created notes inherit this profile's
  access** choice. Without both, the tool is not exposed for that target.
- `create_folder` requires the broad, separately confirmed `folders.manage`
  capability. It grants metadata management, not access to notes placed there.
- New folders do not inherit note-content grants unless the user later adds a
  visible Folder Grant.

### Authority levels

- **Read** exposes only query tools and Work Item reads allowed by the grant.
- **Propose** adds preview and durable proposal creation. An agent with proposal
  authority cannot approve or apply its own proposal.
- **Write** adds direct typed mutations and atomic Change Set application.

Changing a grant increments its `grantRevision`. Existing cursors, preview
tokens, and unapproved proposal approval tokens bind to the prior revision and
become invalid. Removing a profile from a Work Pool cancels its active leases.
Revoking a profile denies every command immediately while preserving audit
history and safe local Undo.

### Privacy rules

- Lists, search, backlinks, outgoing links, activity, and Work Item context are
  computed from authorized snapshots, not filtered after a broad result is built.
- Unknown, private, and unauthorized note IDs return the existing
  `note_not_found` code with identical content and timing classes where practical.
- Unknown, private, and unauthorized folder and Work Item IDs likewise share
  `folder_not_found` and `work_item_not_found` behavior.
- Graph tools never enrich an unauthorized target with its title, folder, dates,
  or existence. If an authorized source body already contains a Fleck UUID link,
  the graph result may report the destination as `unavailable`, identically for a
  malformed, missing, or unauthorized destination.
- Counts and pagination metadata do not include hidden resources.
- Internal save failures remain content-free.

## MCP Tool Contracts

All list tools use opaque cursors bound to profile ID, grant revision, normalized
query, filters, and deterministic sort order. Cursors expire after 15 minutes.
Unknown fields are rejected. Read results use structured content and bounded
human-readable text. Mutations require caller-generated UUID operation IDs.

### Discovery and context

| Tool | Authority and contract |
| --- | --- |
| `list_folders` | `folders.list`; returns authorized folder metadata, grant mode, and bounded note counts that exclude hidden notes. |
| `list_notes` | `notes.list`; paginated summaries of authorized notes with revision and optional authorized folder metadata. Supersedes the name `list_shared_notes`; the old name remains a compatibility alias during v2. |
| `search_notes` | `notes.search`; searches authorized title/body snapshots using deterministic local search. Accepts query, optional authorized folder filter, cursor, and limit. |
| `read_note` | Existing paginated line read, now evaluated through grants. |
| `get_backlinks` | `links.traverse`; returns authorized source summaries and excerpts for an authorized target. |
| `get_outgoing_links` | `links.traverse`; returns parsed links from an authorized source and enriches only authorized targets. |

`get_related_notes` is deliberately deferred. It can later be an adapter over a
documented, deterministic ranking built from these primitives, not an undefined
AI relevance promise.

### Organization

| Tool | Required contract |
| --- | --- |
| `create_folder` | `folders.manage`; creates one flat non-system folder with existing name validation. Requires expected organization revision and operation ID. |
| `rename_folder` | `folders.manage` and target metadata scope; stable folder UUID, expected organization revision, operation ID. |
| `create_note` | `notes.create` in an explicitly granted container; title/body bounds, expected organization revision, operation ID, and inherited-access policy preauthorized by the user. |
| `move_note` | `notes.organize` write authority on the note and metadata visibility for the destination; expected organization revision and operation ID. It does not conflict with unrelated content edits. |
| `link_notes` | `notes.write` on the source and read visibility on the target; inserts a canonical stable Fleck Markdown link through the normal text mutation path using the source's expected content revision and an operation ID. |
| `open_note` | `ui.openNote`; selects an authorized real note in Fleck. It never shares or mutates content. |
| `pin_note` | `notes.organize`; expected organization revision and operation ID. Pinning is an auditable metadata mutation and does not increment content revision. |

Folder deletion, note deletion, sharing changes, and system Inbox/Trash changes
remain unavailable.

### Existing editing and task tools

The existing append, insert, replace, delete-lines alias, task, activity, and Undo
tools remain typed and bounded. They move behind the Capability Authority without
weakening their current revision, exact-text hash, idempotency, rich-text,
activity, or safe-Undo behavior.

### Atomic Change Sets

The initial Change Set operation vocabulary is intentionally narrow:

- append text;
- insert text before a line;
- replace or delete an observed line range;
- add, rename, complete, or remove a task; and
- insert a stable note link.

Folder changes, note creation, pinning, sharing, and deletion are not Change Set
operations in v1.

Hard limits per Change Set are 20 notes, 100 operations, 256 KiB total inserted
or replacement UTF-8 data, and a 1 MiB structured preview response. Each target
note has one expected revision. Multiple operations on one note are applied in
request order against the evolving draft.

| Tool | Contract |
| --- | --- |
| `preview_change_set` | Pure evaluation with `changes.preview`; returns normalized patches, resulting revisions, affected-note summaries, warnings, a request digest, and a short-lived preview token. It persists no proposal and performs no mutation. |
| `propose_change_set` | `changes.propose`; stores the immutable normalized plan, request digest, actor, grant revision, expected revisions, and 24-hour expiry. Returns a proposal ID for user review. |
| `apply_change_set` | `changes.apply`; accepts a valid preview token or a locally approved proposal ID plus operation ID. Reauthorizes every target and commits all notes or none. |
| `undo_change_set` | `changes.undo`; requires the change-set ID, current expected revisions for every affected note, and operation ID. Every inverse must be safe or none are applied. |

The transaction creates one `changeSetID`, one child `changeID` per affected note,
one commit proof covering the complete resulting workspace generation, and one
idempotency receipt. Activity can be expanded from the parent Change Set to exact
per-note patches. A crash before the workspace manifest commit yields no change;
a crash after commit reconciles all child receipts from the commit proof.

## Swarm-Style Work Items

### Product position

Fleck stores coordination state and authorized context; external systems decide
which agents run and when. There is no background scheduler or polling loop.
Lease expiry is evaluated lazily when a Work Item is read or mutated.

### Work Pool

A local user creates a Work Pool and selects member Agent Profiles. Membership
allows those profiles to see Work Items in that pool. It does not grant note,
folder, or Change Set access. Context is resolved against each caller's current
grants every time it is read.

### Work Item record

Each Work Item contains:

- stable UUID, pool UUID, title, bounded instructions, and creation actor;
- optional parent Work Item UUID;
- zero or more dependency Work Item UUIDs in the same pool;
- context references to notes, folders, proposals, and Change Sets, never copied
  private note bodies;
- state: `open`, `claimed`, `completed`, `failed`, or `cancelled`;
- monotonic revision and caller operation receipts;
- attempt count and immutable transition timestamps;
- optional current lease owner, hashed lease token, and expiry;
- optional preferred handoff profile and reservation expiry; and
- immutable Agent Results.

Open and claimed items persist until they reach a terminal state or the local
user cancels them. Terminal items leave default views after 30 days but are not
automatically deleted in v1; only the local user may delete or export them.
Operation-id receipts expire after 30 days, matching existing agent retry
retention. Terminal transitions remove lease verifiers immediately.

Dependencies must form a directed acyclic graph. A Work Item is claimable only
when all dependencies are completed. A failed or cancelled dependency produces a
derived blocked reason; it does not silently cancel dependents. Parentage is for
navigation and reporting, not claim ordering.

### Identity and leases

Authorization identity is always the Agent Profile. `execution_instance_id` and
an optional execution label provide attribution but confer no access.

`claim_work_item` atomically changes an eligible open item to claimed and returns
a cryptographically random lease token once. Fleck stores only its verifier. The
token is required to renew, hand off, complete, fail, or record a claimant-owned
result. Lease duration defaults to five minutes, with a server-enforced range of
30 seconds to 30 minutes. Expiry returns the item to effective open state and
increments neither success nor failure; the next successful claim increments the
attempt count. Repeated expiries remain visible for operator diagnosis.

A client may retry any transition with the same operation ID and receive the
original receipt. A stale Work Item revision, invalid lease, or superseded lease
cannot mutate state.

### Handoffs and cancellation

The current claimant may hand off by releasing its lease and optionally naming a
member profile. The preferred profile receives a five-minute exclusive claim
reservation; after that, any authorized pool member may claim. Handoff never
transfers note permissions.

The local user may cancel any nonterminal Work Item. A profile needs the explicit
`work.cancel` capability to cancel. Cancellation invalidates the lease and makes
later heartbeat, result, completion, or failure calls return
`work_item_cancelled`. Cancelling an MCP request does not cancel a durable Work
Item; only `cancel_work_item` or local UI does.

### Work Item tools

| Tool | Contract |
| --- | --- |
| `list_work_pools` | Lists pools in which the profile is a member. |
| `create_work_item` | Creates an item in an authorized pool with validated parent, dependencies, context references, and operation ID. |
| `list_work_items` | Paginated deterministic filtering by pool, state, parent, dependency status, and assignee. |
| `get_work_item_context` | Returns the record plus only context currently authorized to the caller. Hidden references are `unavailable`. |
| `claim_work_item` | Atomically claims an eligible item and returns lease metadata and the one-time token. |
| `renew_work_item_lease` | Extends a valid lease within the server maximum. It cannot revive an expired or cancelled claim. |
| `handoff_work_item` | Releases a valid lease and optionally reserves the next claim for a pool member. |
| `record_agent_result` | Appends a bounded immutable structured result with summary, status, and authorized Fleck references. It cannot attach arbitrary paths or credentials. |
| `complete_work_item` | Atomically records an optional final result and transitions a valid claim to completed. |
| `fail_work_item` | Atomically records a bounded failure result and transitions a valid claim to failed. |
| `cancel_work_item` | Explicit safe cancellation with local-user or `work.cancel` authority. |

Fleck does not implement automatic retry scheduling. Orchestrators use visible
attempt and expiry data to decide whether to claim again, hand off, or create a
replacement Work Item.

## Community Add-on Ecosystem

### Staged model

#### Stage 1: registry and website directory

The first community release is metadata and source discovery, not execution.
Each exact add-on version has a public source repository, immutable registry
entry, compatibility data, declared permissions, checksums, provenance evidence,
and moderation status. The website is generated from reviewed registry data.

#### Stage 2: first-party and explicit Developer Mode

First-party add-ons may use a tightly controlled, separately reviewed execution
path. Community native add-ons remain manual Developer Mode installations with
the exact command and permissions shown before execution. Developer Mode is
visibly unsafe, cannot be enabled silently, and is not presented as reviewed
isolation.

Data-only add-ons may be eligible for one-click installation only if their format
has no executable or interpreted code path.

#### Stage 3: sandbox broker

One-click executable community add-ons require a separate approved broker design
and evidence that each add-on runs out of process with OS-enforced filesystem,
network, credential, IPC, memory, and lifetime limits. Fleck never loads native
add-on libraries into the app or a shared broker process.

The broker must expose only typed capability calls back to Fleck. Direct note
files, profile files, Keychain items, arbitrary sockets, shell commands, and
unscoped network access are unavailable by default. A separately signed and
notarized process, XPC/app-extension arrangement, or portable sandbox runtime may
be evaluated, but no substrate is selected until a prototype proves isolation,
crash containment, cancellation, and distribution viability on supported macOS
versions.

Apple documents App Sandbox as kernel-enforced resource restriction and XPC as a
mechanism for privilege isolation and crash separation. Merely placing arbitrary
code behind IPC is not isolation; the broker proof must demonstrate the actual
sandbox and entitlement behavior.

### Manifest contract

Each versioned manifest contains:

- manifest schema version;
- stable reverse-DNS add-on ID and display name;
- publisher identity and source repository URL;
- semantic version with no mutable replacement of a released version;
- exact source commit and release tag;
- minimum and maximum tested Fleck versions;
- minimum internal protocol version and required protocol features;
- add-on kind: `dataOnly`, `firstPartyExecutable`, or `developerExecutable` until
  a brokered kind is approved;
- declared tools and stable tool IDs;
- requested capabilities, authority levels, scope kinds, and resource limits;
- independent SPDX license identifier and license file;
- supported macOS versions and architectures;
- artifact URLs, byte counts, SHA-256 checksums, and signatures or attestations;
- build instructions, test command, protocol fixture version, and reproducibility
  evidence status; and
- screenshots, privacy statement, support URL, and reporting URL.

Semantic versions describe the add-on's declared public interface: incompatible
changes increment major, backward-compatible features increment minor, and
backward-compatible fixes increment patch. Fleck still evaluates declared
protocol features and compatibility fixtures; SemVer alone is not proof.

### Submission and validation

Submission is a pull request to a public registry repository and references a
public tagged source release. CI must reject:

- mutable or missing tags, ID ownership conflicts, malformed manifests, unknown
  capabilities, undeclared tools, or prohibited capabilities;
- missing README, source, tests, independent license, release notes, checksums,
  source commit, or protocol fixtures;
- artifacts whose bytes do not match the manifest;
- tools that request arbitrary paths, shell, settings, sharing, credentials,
  Trash, Dictation History, silent private-note access, or native in-process
  loading; and
- compatibility claims not exercised by the declared fixture matrix.

CI may build from source, compare artifacts, produce an SBOM, and verify GitHub
artifact attestations. An attestation establishes build provenance, not source
quality or behavioral safety. Reproducibility status is displayed independently.
Third-party workflow dependencies are pinned to full commit SHAs.

### Trust labels

Labels apply to one exact version, not permanently to an add-on ID:

| Label | Meaning |
| --- | --- |
| **First-party** | Published and signed by the Fleck publisher through the first-party release process. |
| **Community Reviewed** | Automated checks and human manifest/source review passed for this exact version. Initially requires an OSI-approved add-on license. |
| **Experimental** | Listed for discovery with automated schema/provenance checks but without complete human review or compatibility evidence. |
| **Developer Mode** | Local or unlisted executable installation chosen explicitly by the user; no community review or isolation claim. |

No label is named “Trusted” or “Safe.” A permission increase, publisher change,
artifact change, major version, or lost reproducibility requires fresh review and
fresh user approval.

### Website directory

Each version page shows source, publisher, license, trust label, supported Fleck
and protocol versions, requested permissions in plain language, release history,
checksums, provenance and reproducibility status, screenshots, known issues, and
a reporting path. Compatibility and trust status are never inferred from GitHub
stars or download counts.

## User Experience

### Capability Profiles

Settings replaces the binary profile view with a Capability Profile summary:

```text
Research Agent
Read + Propose · 8 tools · 2 folders · 3 direct notes
Includes future notes in “Projects”
```

Editing a profile uses three explicit sections: tools, authority, and scope. The
future-note choice is adjacent to each Folder Grant and off by default. Broad
organization management, direct write, created-note inheritance, and Work Item
cancellation each receive a concise confirmation. The user can inspect the exact
effective grant before saving.

Revocation and scope reduction take effect immediately. The UI previews affected
active leases, proposals, and future-note inheritance before confirmation.

### Activity and proposals

Activity groups child note changes under their Change Set while preserving exact
patch inspection and safe Undo. Proposal cards show actor, expiry, affected notes,
expected/current revisions, and normalized diffs. Local approval reauthorizes the
current state; it never blindly applies a stale proposal.

### Work Items

A compact Work view shows pools and state columns with parent/dependency badges,
claimant, lease expiry, attempts, results, and context availability. It is a
coordination ledger, not a live agent console. The UI offers local cancel, reopen
as a new item, inspect result, and open authorized context.

### Add-ons

Before the broker exists, the in-app Add-ons surface links to the directory and
explains the available installation mode. It must not display an enabled
one-click install control for executable community code. Developer Mode shows the
exact executable command, source, checksum, permissions, and same-user risk.

## Error Model

Errors remain stable structured results with `code`, optional content-free
`recoveryAction`, and `retryable`. Tool/domain failures use MCP tool results with
`isError: true`; malformed or unknown MCP tool calls remain protocol errors.

New codes include:

| Code | Meaning |
| --- | --- |
| `capability_denied` | The authenticated profile lacks the requested tool or authority. |
| `folder_not_found` | Folder is unknown or unauthorized. |
| `organization_conflict` | Folder or ordering revision changed. |
| `change_set_conflict` | At least one authorized expected revision no longer matches; nothing applied. |
| `preview_expired` | Preview token expired or its grant revision changed. |
| `proposal_expired` | Proposal expired before approval or application. |
| `proposal_not_approved` | A propose-only actor attempted application without local approval. |
| `work_item_not_found` | Work Item is unknown or unauthorized. |
| `dependency_incomplete` | A dependency is not completed. |
| `lease_conflict` | Another valid claimant owns the item. |
| `lease_expired` | The supplied lease can no longer mutate the item. |
| `work_item_terminal` | Requested transition is invalid for a completed or failed item. |
| `work_item_cancelled` | The item was cancelled and the lease invalidated. |
| `protocol_version_unsupported` | Helper/app wire feature negotiation failed. |

Existing `permission_revoked`, `note_not_found`, `revision_conflict`,
`unsafe_undo`, size, payload, unavailable, and internal-save codes remain.

## Migrations and Compatibility

### Profile and per-note access migration

The current `Note.agentAccess` flag grants every active profile the same note
access. Migration preserves that behavior without granting future profiles:

1. Create a v2 profile/grant document atomically.
2. For every active profile, materialize a direct Note Grant with write authority
   for every currently shared note and the existing 13-tool compatibility set.
3. If shared notes exist but there are no active profiles, record them as visible
   **Unassigned legacy shares**. They are inaccessible until the user assigns a
   profile; a later profile never receives them silently.
4. Keep the legacy flag readable for rollback during the compatibility window,
   but derive new UI badges and command access from grants.
5. Remove legacy write behavior only after migration, rollback, malformed-file,
   and previous-generation recovery fixtures pass.

New profiles start with no tools and no scopes.

### Protocol compatibility

- Internal wire v1 remains accepted for its exact existing command subset.
- Internal wire v2 introduces capability-aware commands, cursors, Change Sets,
  Work Items, and new structured errors.
- A v1 helper never receives or approximates a v2 command.
- Tool aliases preserve existing client configurations during one documented
  deprecation window.
- Add-on protocol compatibility is feature-based in addition to integer version.

### Data recovery

Profile grants, proposals, and Work Items each have explicit schema versions,
atomic replacement, malformed-record quarantine, and previous-generation
recovery. A corrupt coordination store cannot block note launch. Unknown future
fields are rejected by mutation interfaces and preserved only where the storage
migration contract explicitly supports forward compatibility.

## Performance and Resource Budgets

- No capability, Work Item, or add-on feature introduces an idle polling loop,
  always-running server, web view, or network requirement.
- Authorization is evaluated from an immutable in-memory grant snapshot and is
  linear in the small number of grants for one profile, not all profiles.
- Search receives only authorized note snapshots and keeps the existing
  cancellation and deterministic ranking behavior.
- Backlink/outgoing-link traversal reuses the incremental parser/index cache and
  filters before response construction.
- Default/max page sizes are 50/100 for notes, links, and Work Items.
- Work Item state transitions and grant changes are actor-serialized and atomic.
- Provisional automated gates use 1,000-note fixtures, 10,000 Work Items across
  20 pools, and 100 concurrent lease attempts. Numeric latency thresholds are set
  only after baseline measurement on the verification machine.
- The existing 15 MiB release executable target, 75 MB normal idle memory ceiling,
  zero-idle-polling rule, and no ordinary network dependency remain release gates.

## Security and Trust Boundaries

- The helper remains a local stdio MCP server plus same-user Unix-socket client.
  MCP's HTTP OAuth flow is not adopted for this local transport.
- Profile credentials remain outside command arguments, setup snippets, logs,
  stdout, profile JSON, activity, Work Items, and Agent Results.
- Execution identity labels are untrusted display metadata and are escaped and
  bounded.
- Capability evaluation occurs in Fleck, never in the helper or add-on.
- Preview tokens and lease tokens are random bearer proofs, scoped, short-lived,
  and excluded from activity and diagnostics. Preview tokens are either signed
  stateless envelopes or verifier-backed records; lease tokens are stored only
  as verifiers.
- MCP request timeouts and cancellation stop bounded request work. They do not
  imply durable Work Item cancellation.
- Add-on registry metadata is untrusted input even after review.
- Native community execution remains disabled until the broker has adversarial
  evidence for filesystem, network, IPC, credential, crash, timeout, and process
  cleanup isolation.

The cooperative same-user threat-model limitation remains visible: current Fleck
does not claim protection from arbitrary malicious software already running as
the same macOS user. The future broker must improve isolation for add-on code
rather than inheriting that limitation silently.

## Test Strategy

### Pure-core contracts

- Grant normalization, authority lattice, note/folder scope resolution, folder
  membership changes, future-note inheritance, and grant-revision invalidation.
- Deterministic authorized search, list, backlinks, outgoing links, hidden target
  handling, Unicode, cancellation, cursor binding, and pagination.
- Every Change Set operation, ordered same-note operations, all size/count limits,
  cross-note revision conflicts, exact atomicity, and safe all-or-nothing Undo.
- Work Item state-machine transition table, dependency DAG/cycle rejection,
  parent rules, lease expiry with a fake clock, claim races, handoff reservation,
  retries, cancellation, and hidden context.
- Versioned migration fixtures for legacy shared notes, no-profile shares,
  malformed grants, interrupted writes, and previous-generation recovery.

### Protocol and adapter contracts

- Exact profile-filtered MCP tool lists, ordering, descriptions, schemas,
  aliases, unknown-field rejection, bounded values, and canonical command mapping.
- Wire v1/v2 round trips, feature negotiation, unsupported versions, cursor and
  token opacity, and content-free errors.
- Every mutating tool proves caller operation ID idempotency.
- Static audits reject direct storage, network listeners, arbitrary paths, shell,
  settings, sharing, credentials, Trash, Dictation History, and undeclared tools.

### Privacy matrix

For every target-bearing tool, run the same request against authorized, private,
unknown, trashed, revoked, and concurrently unshared targets. Assert identical
safe absence for unauthorized/private/unknown cases and assert that list counts,
cursors, snippets, links, activity, proposals, and Work Item context leak no
hidden metadata.

### Persistence and crash recovery

- Failure injection before and after workspace manifest commit for single writes
  and multi-note Change Sets.
- Reconciliation produces exactly one parent receipt and child activity set.
- Capability, proposal, and Work Item store corruption does not damage notes.
- Revocation during query, preview, commit, lease renewal, and completion fails
  closed at the final authority check.

### Community registry

- Manifest schema and semantic-version fixtures.
- ID ownership, immutable version, permission delta, prohibited capability,
  compatibility, checksum, signature/attestation, source tag, and license checks.
- Reproducible and intentionally non-reproducible fixture releases.
- Website generation from sanitized registry data and reporting links.
- Malicious manifest strings, oversized assets, path traversal, symlink, archive
  bomb, and artifact substitution fixtures before any installation path exists.

### Packaged and manual evidence

- Codex, Claude Code, Kimi, and generic CLI against distinct least-privilege
  profiles.
- Grant reduction/revocation while connected, client tool-cache behavior, and
  helper v1/v2 mismatch.
- Search, graph traversal, organization, Change Set preview/propose/apply/Undo,
  lease handoff, expiry, cancellation, and multi-agent claim races.
- VoiceOver, Full Keyboard Access, Reduce Motion, multi-window behavior,
  sleep/wake, five-minute idle CPU, Keychain lifecycle, signed helper packaging,
  and sanitized evidence capture.

Automated success does not substitute for packaged-app, live Keychain,
third-party client, accessibility, signing, notarization, or broker-isolation
evidence.

## Separately Reviewable Delivery Phases

No phase uses one giant implementation branch.

### Phase A: capability foundation and migration

- Pure capability/grant model and policy tests.
- Versioned profile persistence and legacy access migration.
- Internal wire v2 negotiation and profile-filtered MCP discovery.
- Existing 13 tools moved behind the authority with behavior preserved.
- Capability Profile settings and activity visibility.

Stop before new context tools until privacy, migration, and v1 compatibility are
accepted.

### Phase B: context and organization tools

- `list_folders`, `list_notes`, `search_notes`, backlinks, and outgoing links.
- `create_folder`, `rename_folder`, `create_note`, `move_note`, `link_notes`,
  `open_note`, and `pin_note` in bounded sub-phases.
- Search/folder/backlink integration must be present in the accepted base.

Discovery/context and organization may be separate PRs if shared-file ownership
or review size warrants it.

### Phase C: Change Sets and proposals

- Pure planner and limits first.
- Preview and proposal persistence.
- Atomic application, crash reconciliation, grouped activity, and Change Set
  Undo.
- Proposal review UI.

### Phase D: Work Pools and Work Items

- Work Item domain state machine and persistence.
- Read/create/claim/renew/handoff/result/complete/fail/cancel tools.
- Work UI and packaged multi-client evidence.

Completion of Phase D is the MCP Capability Platform v1 milestone.

### Phase E: community registry and directory

- Manifest schema and fixtures.
- Public registry submission/review workflow.
- CI validation, provenance, compatibility, license, and reproducibility fields.
- Website directory and reporting. No community executable install path.

### Phase F: execution isolation research and broker proof

- Separate threat model and substrate comparison.
- Adversarial prototype with no production add-on enablement.
- Explicit user approval of the broker design and release evidence.
- Only then plan one-click brokered executable add-ons.

Every phase requires its own bounded implementation packet, red production-path
tests, local verification, packaged evidence where applicable, focused PR, and
fresh Sol/High `ship` verdict. Later implementation uses the user-visible
Luna/Max lane and must coordinate ownership with the separate AI/dictation task
before touching shared files.

## Stop Conditions

Return to design if:

- authorization logic must be duplicated outside the Capability Authority;
- a query must inspect private notes before scope filtering;
- a tool requires arbitrary paths, shell, settings, sharing, credentials, Trash,
  Dictation History, or note deletion;
- a created resource widens access without a prior explicit user grant;
- a Change Set can partially commit or partially undo;
- interrupted persistence cannot reconcile to exactly one receipt;
- a Work Item lease can be completed by a stale or different claimant;
- cancellation is inferred from transport disconnect rather than a durable state
  transition;
- Work Pool membership grants note access;
- a community trust label is presented as a safety guarantee;
- native add-on code can run in Fleck, a shared process, or an unproven sandbox;
- implementation overlaps uncoordinated AI/dictation ownership; or
- the accepted search/folder/backlink base differs materially from the contracts
  assumed here.

## Primary Sources

- [MCP tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools): tool discovery, structured schemas, calls, human visibility, and list-change notifications.
- [MCP lifecycle specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle): version/capability negotiation, timeouts, cancellation, and shutdown.
- [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization): transport-specific authorization requirements; stdio does not use the HTTP OAuth flow.
- [MCP security best practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices): local-server consent, stdio/IPC preference, scope minimization, and sandbox guidance.
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox): kernel-enforced restriction of resource access.
- [Apple XPC](https://developer.apple.com/documentation/XPC): process lifecycle, mediation, and privilege isolation.
- [GitHub artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations): build provenance generation and verification.
- [GitHub reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows): full commit SHA pinning as the safest workflow reference.
- [Semantic Versioning 2.0.0](https://semver.org/): immutable releases and major/minor/patch compatibility meaning.

## Approval Gate

This document authorizes no implementation, branch, commit, push, PR, merge,
registry creation, website publication, or GitHub change. After user approval of
this written spec, the next artifact is a granular implementation plan under
`docs/superpowers/plans/`. Implementation begins only after a second explicit user
approval of that plan.
