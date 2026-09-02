# Motes Agent Workspace Integration

**Status:** Approved product design
**Date:** 2026-07-27

## Purpose

Motes should become a small, persistent human-agent workspace for software developers and vibe coders. A user can keep project notes and checklists in the menu bar, explicitly share selected tabs with local AI agents, and let those agents read progress, add context, and update tasks without giving them access to unrelated notes.

The first release supports Codex, Claude Code, Kimi, shell scripts, and other local tools through a common MCP and command-line contract. Motes remains local-first, owns every mutation, and provides visible attribution, revision conflicts, and safe Undo.

## Goals

- Let users explicitly share individual Motes notes with authorized local integrations.
- Let agents read shared Markdown and perform safe free-form and checklist operations.
- Reflect agent changes immediately in the open Motes interface.
- Preserve readable note storage, rich-text behavior, autosave, Trash, and existing Undo boundaries.
- Prevent stale agents from silently overwriting newer human or agent edits.
- Attribute each agent mutation and retain a local reversible activity record for 30 days.
- Offer MCP for agent-native integrations and an equivalent CLI for universal fallback.
- Require no Motes cloud service, account, or internet-facing listener.

## Non-goals

The first release does not:

- Expose every note by default.
- Provide per-agent note access-control lists.
- Let agents share or unshare notes.
- Let agents delete entire notes.
- Expose Trash, Dictation History, preferences, private notes, or local files outside shared note content.
- Run shell commands or control other Mac applications.
- Offer a public HTTP API, remote access, collaboration server, or synchronization service.
- Turn Motes into a project-management database or kanban application.
- Permit agents to edit Motes storage files directly.

## Product model

### Explicit note sharing

Every note has an `agentAccess` value that defaults to disabled. The user can enable or disable it from the note context menu or the Options interface.

Only notes with Agent Access enabled appear through MCP or the CLI. Sharing status is visible through a small connection badge on the tab and in the note menu. An agent cannot change this value.

The first release grants every authorized local integration the same read-and-write access to the explicitly shared set. Per-integration note permissions are deferred until real usage proves they are necessary.

### Hybrid notes and tasks

Agents can work with the shared note as readable Markdown and can also use structured checklist commands.

Free-form operations:

- Read the current note.
- Append text.
- Insert text at a defined line boundary.
- Replace a defined line range.

Checklist operations:

- List checklist items.
- Add an item.
- Rename an item.
- Mark an item complete.
- Reopen an item.
- Remove an item.

Motes continues to store checklist content using its existing readable markers. It does not add hidden identifiers to Markdown. When an agent lists tasks, Motes returns opaque task handles bound to the current note revision. Any intervening note edit invalidates those handles and requires the agent to list tasks again.

## Integration architecture

### Single-writer boundary

Motes is the sole writer for its workspace. Agents never modify Markdown, RTF, manifests, or activity files directly.

All external mutations enter the same serialized application boundary used by the Motes interface. Agent commands are queued one at a time, and every persistence continuation revalidates the live workspace generation before it can publish. This preserves:

- Current in-memory state.
- SwiftUI and AppKit editor synchronization.
- Rich-text sidecars.
- Autosave and save feedback.
- Trash behavior.
- Revision increments.
- Agent activity records.

If the user edits while an agent command is awaiting persistence, the application preserves the newer human state and rejects the agent command as stale rather than publishing an old workspace copy. If the workspace save succeeds but activity finalization fails, the saved workspace remains authoritative and is published immediately; the prepared activity transaction is reconciled on retry or launch.

### Local bridge

Motes ships a bundled `motes` bridge with two modes:

- `motes mcp` runs a local stdio MCP server for Codex, Claude Code, and compatible clients.
- Normal `motes` subcommands expose the same contract to Kimi, scripts, terminals, and agents without MCP support.

The bridge communicates with the Motes application through private per-user IPC. It does not open a TCP listener. If Motes is not running, the bridge launches it without foregrounding the notes interface and waits for the command channel to become ready.

The bridge never falls back to editing storage independently when the application is unavailable.

### Connection authorization

Connections are created in **Settings → Agents**. Motes generates revocable credentials for each configured integration profile. The profile supplies the user-facing integration name used for attribution, such as Codex or Claude Code.

Revoking a profile blocks future requests immediately. A request already accepted by Motes completes or is cancelled according to its current transaction boundary; revocation never leaves a half-written note.

The authorization model is a product boundary for cooperative local tools. It is not protection from malicious software already running as the same macOS user, because same-user software may be able to read Application Support directly.

## MCP contract

The initial MCP tool set is intentionally narrow:

- `list_shared_notes`
- `read_note`
- `append_text`
- `insert_text`
- `replace_lines`
- `list_tasks`
- `add_task`
- `rename_task`
- `set_task_state`
- `remove_task`
- `list_agent_activity`
- `undo_agent_change`

Read responses contain structured fields and readable Markdown:

- Stable note identifier.
- Display title.
- Current revision.
- Body.
- Checklist summaries when requested.
- Last modification time.

`read_note` accepts optional line-window parameters. This lets an agent inspect a large note without requiring one unbounded response. The response identifies the returned line range and total line count.

Every write includes:

- Note identifier.
- Expected note revision.
- Unique operation identifier.
- Operation-specific payload.

Line replacement includes the expected line range and a hash of the text the agent observed. This supplements the note revision and makes an incorrect target fail closed.

Write responses contain:

- Applied or rejected state.
- Previous and resulting revision.
- Activity record identifier.
- Updated task handle where applicable.
- A structured error and recovery hint when rejected.

## CLI contract

The CLI mirrors MCP instead of creating a second behavior model. Representative commands are:

```bash
motes notes list
motes note read <note-id>
motes note append <note-id> --revision <revision> --operation-id <uuid> --stdin
motes note replace-lines <note-id> <start> <end> --revision <revision> --operation-id <uuid> --stdin
motes tasks list <note-id>
motes task add <note-id> "Add onboarding screenshots" --revision <revision> --operation-id <uuid>
motes task complete <note-id> <task-handle> --revision <revision> --operation-id <uuid>
motes task reopen <note-id> <task-handle> --revision <revision> --operation-id <uuid>
motes task rename <note-id> <task-handle> "Capture final screenshots" --revision <revision> --operation-id <uuid>
motes activity list
motes activity undo <change-id> --revision <revision> --operation-id <uuid>
```

Human-readable output is the default. A stable JSON output mode is available for programs and agents.

## Revisions, conflicts, and idempotency

Each note persists a monotonically increasing revision. Human and agent mutations both increment it.

Every external write must provide the revision observed by the agent. If the current revision differs, Motes returns `revision_conflict` with the new revision and instructs the caller to reread. It does not guess, merge, or overwrite.

Each mutation also provides a unique operation identifier. Motes stores the identifier and result with the Agent Activity record. A retry with the same identifier returns the original result without applying the mutation again. This idempotency guarantee lasts for the 30-day activity retention period.

Task handles encode the note identity, note revision, and task location in an opaque signed value. They are useful only for the revision that produced them. A stale handle returns `task_handle_expired`.

## Agent Activity and Undo

Every accepted agent mutation writes an atomic local activity record containing:

- Change identifier.
- Operation identifier.
- Integration profile and display name.
- Note identifier and title at the time of the change.
- Timestamp.
- Operation type.
- Before-and-after patch.
- Previous and resulting revision.
- Undo eligibility.

Records appear under **Options → Agent Activity**, newest first. The user can inspect the patch, open the affected note, copy details, or request Undo.

The presented Agent Activity sheet includes a visible **Done** action in its header. Done and Escape dismiss only the presented sheet from both Options and Settings, leave activity data and the parent UI unchanged, and expose the Done action to assistive technologies as **Close Agent Activity**.

An integration can list and undo only its own activity for notes that are currently shared. Unsharing a note immediately hides its historical patches from every integration. The Motes user can still inspect all local activity in the application and may request a safe local Undo for any active note even after the originating integration is revoked or the note is unshared.

Undo is conditional:

- It succeeds when Motes can prove that reversing the recorded patch will not overwrite later unrelated work.
- It creates a new attributed revision rather than deleting history.
- It refuses with `unsafe_undo` when later edits make the inverse ambiguous.

Activity records are local, automatically expire after 30 days, and can be cleared manually after confirmation. Clearing activity does not modify note content. A clear removes visible patches and transcript-like content but retains a minimal operation-ID tombstone until the original 30-day expiry, preventing a delayed retry from duplicating an already-applied mutation.

## User experience

### Sharing a note

The note context menu and Options interface expose **Allow Agent Access**. The first use briefly explains that authorized local integrations will be able to read and edit that note. Enabling the option adds the connection badge immediately.

Disabling access:

- Removes the note from discovery immediately.
- Rejects subsequent operations for that note.
- Keeps historical activity records until their normal expiry or manual clearing.

### Live agent feedback

Accepted changes appear immediately in every visible Motes scene. A restrained non-blocking banner reports, for example:

> Codex updated Launch Tasks · Undo

The banner identifies the integration and note, never displays private content from another note, and does not steal focus. Reduce Motion uses a crossfade.

When multiple changes arrive close together, Motes coalesces the banner count while preserving individual activity records.

### Integration setup

**Settings → Agents** shows:

- Installed or missing command-line bridge.
- Authorized integration profiles.
- Copyable setup snippets for supported MCP clients.
- Generic MCP and CLI instructions.
- Last connection time.
- Revoke action.
- Link to Agent Activity.
- Clear Activity with confirmation.
- A concise explanation of explicit note sharing and the same-user security boundary.

Motes does not promise automatic configuration for every agent. It provides verified setup for selected clients and a standards-based generic path for others.

## Validation and limits

Motes validates all external payloads before mutation:

- Note and activity identifiers must exist and be in scope.
- Unknown and unshared note identifiers are externally indistinguishable and return `note_not_found`.
- Text must be valid UTF-8.
- Line ranges must be ordered and within the observed revision.
- Task handles must authenticate and match the current revision.
- Unsupported checklist transitions are rejected.
- Text added or replaced by one mutation is limited to 64 KiB of UTF-8 data. Oversized legitimate updates must be split.
- One response is limited to 1 MiB. `read_note` uses line windows when the complete body would exceed that boundary. If an encoded success envelope would still exceed the limit, the bridge returns a small structured `response_too_large` error instead of dropping the connection.
- Local requests have a bounded timeout. A timed-out caller retries with the same operation identifier instead of inventing a new one.

The initial error vocabulary is:

- `note_not_found`
- `permission_revoked`
- `revision_conflict`
- `task_handle_expired`
- `unsafe_undo`
- `motes_unavailable`
- `write_too_large`
- `response_too_large`
- `invalid_operation`
- `invalid_payload`
- `internal_save_failure`

Errors include a safe recovery action where one exists. Internal file paths, credentials, private-note metadata, and unrelated content never appear in responses.

## Storage

The existing readable note and RTF formats remain authoritative.

Workspace metadata adds:

- Agent Access state.
- Note revision.
- Bounded, content-free operation commit proofs retained only for crash recovery and the 30-day retry boundary.

Agent integration state is stored separately from note bodies:

- Authorized connection profiles and revocation state.
- Activity records.
- Minimal idempotency tombstones retained for the full 30-day retry boundary even when visible activity is cleared.

Raw credentials, credential verifiers, and the task-handle signing key use the macOS Keychain rather than readable preferences. Profile metadata contains identifiers, display names, timestamps, and revocation state only. Activity and IPC state remain separate from Trash and Dictation History.

All persistent mutations use atomic replacement or staging-and-move behavior consistent with the current local store. The workspace manifest is the commit point for a hash-validated complete Markdown/RTF generation; an interrupted partial generation falls back to Recovery rather than being mistaken for an accepted agent operation.

## Testing and release gates

### Core contract tests

- Private notes never appear in discovery or direct reads.
- Sharing and unsharing take effect immediately.
- Every text and checklist operation has positive and negative coverage.
- Human edits and agent edits increment the same revision.
- Stale revisions and stale task handles fail without mutation.
- Duplicate operation identifiers return the original result.
- Activity records match the applied patch.
- Safe Undo reverses only the intended operation.
- Unsafe Undo refuses without changing content.
- Thirty-day purge and confirmed clear behavior are deterministic.

### Integration tests

- The UI updates when an agent change is accepted.
- Rich-text runs outside an edited Markdown range survive.
- Autosave and agent mutations cannot overwrite one another.
- Revocation during activity reaches a complete terminal state.
- Application launch through the bridge is bounded and does not activate the notes window.
- IPC accepts only authenticated local profiles.
- CLI JSON and MCP responses represent the same domain result.
- Oversized, malformed, and out-of-scope requests fail closed.

### Privacy tests

Automated negative checks prove that integrations cannot:

- Enumerate or read private notes.
- Read Trash or Dictation History.
- Change settings or sharing state.
- Delete entire notes.
- Access arbitrary filesystem paths.
- Execute shell commands through Motes.

### Manual compatibility checks

Before release, test installation, authorization, read/write operations, revocation, conflicts, and Undo with:

- Codex.
- Claude Code.
- One generic MCP client.
- One CLI-driven agent or script representative of Kimi-style integration.

VoiceOver, Reduce Motion, multiple Motes windows, app relaunch, sleep/wake, and simultaneous editor activity require native macOS validation.

## Implementation sequencing

This feature touches workspace metadata, `LocalStore`, `AppState`, Settings, and the menu-bar interface. Clean Dictation is actively changing several of the same application boundaries. Implementation should begin from the merged and reviewed Clean Dictation baseline, or explicitly rebase after its `AppState` and shared-runtime tasks, rather than developing two conflicting single-writer coordinators in parallel.

A later implementation plan should separate:

1. Core revisions, sharing metadata, activity records, and mutations.
2. Serialized `AppState` agent command gateway.
3. Private IPC and bundled CLI.
4. MCP adapter.
5. Sharing, setup, activity, and live-feedback UI.
6. Cross-client compatibility and release validation.
