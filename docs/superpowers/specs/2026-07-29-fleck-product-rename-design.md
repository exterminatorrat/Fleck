# Fleck Product Rename

**Status:** Approved product design
**Date:** 2026-07-29

## Purpose

Rename the active Motes product to Fleck across the macOS application, local
agent bridge, source tree, build tooling, tests, and current documentation.
Existing users must keep their notes, settings, recovery data, and authorized
agent integrations.

Fleck is the sole canonical name after this change. Motes remains only where
the transition release must recognize or serve an existing installation and
inside immutable historical documents and Git history.

## Canonical identity

The completed rename uses:

| Surface | Canonical value |
| --- | --- |
| Product and package | `Fleck` |
| Application bundle | `Fleck.app` |
| Main executable | `Fleck` |
| Bundle identifier | `com.harryjin.fleck` |
| Bundled helper | `fleck-agent` |
| Installed command | `fleck` |
| MCP server name | `fleck` |
| Agent socket | `fleck.sock` |
| Application Support root | `Fleck` |
| Keychain service prefix | `com.harryjin.fleck` |

Active Swift targets, source directories, primary types, test targets, scripts,
CI labels, package names, current documentation, privacy copy, accessibility
copy, log labels, error names, and temporary-file prefixes follow the Fleck
identity.

The repository directory and GitHub repository are already named
`menubar-notes`; they are not Motes product identifiers and are outside this
rename.

## Compatibility boundary

The first Fleck release is a transition release. It keeps existing agent
configurations working through a compatibility command at:

```text
~/Library/Application Support/MenuBarNotes/AgentBridge/bin/motes
```

That command is a small receipt-authenticated launcher for the canonical
`fleck` command. It forwards arguments and standard streams without modifying
the MCP protocol. It does not contain a second bridge implementation.

New integrations, setup snippets, help output, and documentation use only
`fleck`. The compatibility launcher is retained for one Fleck release and is
explicitly isolated so a later release can remove it without changing the
canonical bridge.

Historical specifications, implementation plans, and Git history remain
unchanged. Tests and audits maintain a narrow allowlist for:

- Legacy storage, socket, receipt, and Keychain identifiers read during
  migration.
- The temporary `motes` compatibility launcher and its tests.
- Historical documents.

No other active product surface may contain the Motes brand.

## Local-data migration

Migration runs before `AppState`, dictation stores, agent stores, or the IPC
server are constructed.

The migration coordinator recognizes the legacy root:

```text
~/Library/Application Support/MenuBarNotes
```

and the canonical root:

```text
~/Library/Application Support/Fleck
```

### Normal migration

When a legacy workspace exists and the Fleck root does not:

1. Validate that the source is a real directory owned by the current user and
   is not a symbolic link.
2. Move the complete directory to a temporary sibling in Application Support.
3. Rename the temporary sibling to `Fleck` on the same volume.
4. Verify the resulting workspace through the existing snapshot readers.
5. Install the canonical bridge and legacy compatibility launcher atomically.
6. Write a migration receipt containing only versions, paths, hashes, and
   timestamps.

The move preserves notes, RTF sidecars, workspace/preferences manifests,
Trash, dictation history, model state, agent profiles, activity, and receipts.
No content is rewritten merely to rename the product.

If a step after the first move but before canonical verification fails, the
coordinator moves the staged directory back to the legacy path before
returning the error. If rollback itself fails, it reports both existing paths,
leaves them untouched, and blocks writes. Fleck never publishes an empty
replacement workspace.

### Repeat launches and conflicts

Migration is idempotent. A verified migration receipt makes later launches use
the Fleck root directly.

The legacy root may be recreated only as a marked compatibility container for
the `motes` launcher. It is not considered a second workspace.

If both roots contain workspace data and there is no verified migration
receipt, Fleck does not merge, delete, or choose one silently. It blocks
workspace writes and presents an actionable migration-conflict error while
leaving both directories untouched.

## Keychain migration

Fleck uses canonical Keychain services for:

- Integration credential verifiers.
- Task-handle signing keys.
- Bridge profile credentials.
- Dictation download/resume authentication where applicable.

For the transition release, each reader:

1. Queries the Fleck service.
2. Falls back to the corresponding legacy Motes service when the canonical item
   is absent.
3. Copies the legacy value into the canonical service.
4. Reads back and compares the canonical value before using it.

Legacy Keychain items are not deleted in the transition release. Failed copies
leave the source untouched and return a recoverable error rather than creating
a new identity or silently revoking an integration.

## Agent bridge migration

The packaged app contains only `fleck-agent`. On a verified legacy
installation, the existing bridge receipt is validated before any legacy
executable runs or is replaced.

The installer transaction:

1. Installs the verified bundled helper as the canonical `fleck` command.
2. Installs the receipt-authenticated `motes` compatibility launcher at the
   prior absolute path.
3. Updates the canonical receipt only after both filesystem operations succeed.
4. Rolls both operations back together on failure.

Existing Codex, Claude Code, Kimi, and generic MCP configurations continue to
invoke their old absolute `motes` path, which forwards to Fleck. New
configuration snippets register the name `fleck` and canonical command path.

The app and helper communicate only through `fleck.sock`. The legacy launcher
does not require a second socket or listener.

## Application identity and permissions

The project is pre-release, so Fleck adopts `com.harryjin.fleck` rather than
retaining the old development bundle identifier.

macOS treats this as a new application identity. Existing note data and local
integration credentials migrate, but microphone and Speech Recognition grants
cannot. Fleck requests those permissions again on first dictation use with
Fleck-branded privacy descriptions.

## Source and documentation rename

The implementation renames active package products, target directories,
primary types, test directories, scripts, generated artifact names, CI steps,
and current documentation. Imports and dependency edges are updated together
so the package graph has no alias layer for old target names.

Portable storage formats do not gain brand-dependent fields. Existing JSON,
Markdown, and RTF formats remain backward compatible.

Historical documents under `docs/superpowers/specs` and
`docs/superpowers/plans` retain their original wording as immutable records.
The new rename specification and plan are the canonical explanation of the
transition.

## Failure behavior

- Migration never deletes or overwrites an unverified legacy workspace.
- A conflicting pair of workspace roots blocks writes instead of merging.
- A failed Keychain copy keeps and continues to protect the legacy secret.
- A failed bridge transaction restores the prior verified installation.
- Unknown or malformed migration receipts fail closed and expose no note or
  credential content.
- Existing agent authorization, revision, idempotency, and private-note
  boundaries remain unchanged.

## Validation

The rename is complete only when:

- Fixtures prove a full legacy workspace migrates without changing note,
  rich-text, Trash, dictation, preference, model, profile, or activity data.
- Repeated migration is a no-op.
- Legacy and canonical workspace conflicts preserve both roots and block
  writes.
- Keychain fallback copies and verifies each supported secret without deleting
  the legacy item.
- Existing `motes` CLI/MCP configurations work through the compatibility
  launcher.
- New setup commands and MCP identity use `fleck`.
- A repository audit rejects active Motes branding outside the explicit
  compatibility and historical allowlist.
- All Swift tests pass in ordinary and Enhanced-candidate graphs.
- Release packaging produces `Fleck.app`, `Fleck`, and `fleck-agent`.
- Release artifact, size, privacy, boundary, candidate-lock, and candidate
  rejection checks pass.
- The packaged Fleck application launches and left/right menu-bar behavior,
  dictation permissions, notes, Trash, customization, and agent setup receive
  a manual smoke test.

Signing, notarization, App Store registration, and distribution remain separate
release activities.
