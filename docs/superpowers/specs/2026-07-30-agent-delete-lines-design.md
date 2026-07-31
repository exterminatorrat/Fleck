# Agent Delete Lines Design

## Goal

Let an authorized local AI integration explicitly delete content from a shared
Fleck note without broadening access to unshared notes or note deletion.

## Contract

Add one MCP tool:

```text
delete_lines
```

It accepts:

- `note_id`
- `expected_revision`
- `operation_id`
- `start_line`
- `end_line`
- `expected_text_sha256`

The line range is one-based and inclusive. The hash must match the exact text
the agent observed in that range.

## Implementation

`delete_lines` maps directly to Fleck's existing `replaceLines` workspace
command with an empty replacement string. This reuses the current sharing,
revision, hash, idempotency, persistence, activity, rich-text mutation, and Undo
paths. It does not add a second deletion engine or change the wire protocol.

Checklist deletion remains available through `remove_task`. Agents cannot
delete a note, Trash entry, unshared note, settings data, or arbitrary files.

## Failure Behavior

The operation fails closed when:

- the note is not shared or does not exist;
- the revision is stale;
- the line range is invalid;
- the observed-text hash does not match; or
- the operation payload contains unknown fields.

Retries with the same operation ID return the original result without deleting
content twice.

## Verification

- Registry tests prove the exact schema and command mapping.
- Existing mutation/service tests continue proving revision, sharing, hash,
  idempotency, activity, persistence, and Undo safety.
- A focused MCP test proves `delete_lines` is advertised and callable.
- The full Swift test suite and release build pass.
- Reinstall the helper and start a new Codex task before live testing, because
  MCP tool schemas are captured when the task connects.
