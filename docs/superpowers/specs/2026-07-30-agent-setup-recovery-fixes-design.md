# Fleck Agent Setup and Startup Recovery Fixes

## Goal

Make the packaged Fleck development app start safely after an obsolete Motes
process recreates an empty legacy store, and make local agent setup understandable
and functional without weakening Fleck's helper-verification boundary.

## Confirmed root causes

- The current legacy `MenuBarNotes` store contains one default `Untitled` note
  with an empty Markdown body. Fleck already has a valid migrated workspace and
  migration receipt, but startup treats every legacy manifest as user data and
  blocks on a false conflict.
- `swift run Fleck` is a bare executable. It does not contain the separately
  built `fleck-agent` helper in `Contents/SharedSupport`, so there is no verified
  helper for the installer to copy.
- The unsigned development app receives `errSecMissingEntitlement` when the
  Keychain query forces the Data Protection Keychain. The ordinary macOS login
  Keychain accepts the same device-only accessibility policy and works for the
  unsigned development bundle.
- Agent profile buttons remain enabled before the helper is installed, and
  internal errors fall back to opaque Swift error-domain descriptions.
- The old “Motes Settings” screenshot and `MenuBarNotesApp` error domains came
  from an obsolete Motes process, not the current Fleck executable.

## Behavior

### Startup migration

Fleck may ignore a recreated legacy workspace only when all of these are true:

- The canonical Fleck workspace is present.
- Fleck has a valid migration receipt matching the canonical and legacy paths.
- The legacy snapshot contains exactly one unpinned, uncolored `Untitled` note
  with an empty body and no rich text. Agent-access and revision bookkeeping
  may differ because the obsolete app can update them after migration; they
  carry no note content and Fleck remains authoritative.
- The note's Markdown file is zero bytes, and the manifest selection and note
  order point only to that note.
- The legacy root contains no Trash, history, recovery, model, agent data, or
  unknown data. Fleck may tolerate only the exact empty generated directories
  `AgentActivity/{Prepared,Records,Tombstones}` and `AgentBridge`; any file
  inside them fails closed.

Fleck leaves that legacy folder untouched. Any meaningful legacy content,
unknown file, missing receipt, malformed manifest or preferences, or symlink
continues to fail closed and preserve both roots.

### Agent Connector

The UI calls the feature **Agent Connector** and explains that it is a local
helper allowing authorized tools such as Codex to communicate with only the
notes explicitly shared with agents. It opens no network listener.

Installation remains packaged-app-only. Fleck installs only the verified
`fleck-agent` executable bundled inside `Fleck.app/Contents/SharedSupport`.
There is no search for or installation of arbitrary debug/release helpers from
the repository.

Integration buttons stay disabled until:

- The workspace loaded successfully.
- The packaged Agent Connector is installed and verified.

The unsigned development bundle stores agent secrets in the standard macOS
login Keychain instead of requiring the entitlement-only Data Protection
Keychain. Credentials remain device-local and are never written to preferences,
profiles JSON, setup commands, logs, or note storage.

### Errors and instructions

Installer and workspace failures receive short actionable descriptions. A bare
SwiftPM launch explains that agent setup requires the packaged app instead of
showing a module-qualified internal error.

Development documentation uses one supported interactive launch flow:

```sh
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

`swift run Fleck` is removed from interactive testing instructions.

## Validation

- A migration regression reproduces a valid Fleck workspace plus a receipt and
  a recreated empty Motes workspace, then proves startup uses Fleck without
  deleting either root.
- Existing conflict tests continue proving that meaningful data preserves both
  roots and blocks editing.
- A Keychain-query regression proves the unsigned-compatible query does not
  require the Data Protection entitlement.
- Agent presentation tests cover terminology, explanation, setup gating, and
  actionable packaged-app errors.
- Focused tests run first, followed by the complete macOS validation script.
- Manual verification launches the packaged app, installs the connector,
  creates a temporary Codex profile, and confirms the generated setup command
  contains no credential.
