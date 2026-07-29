# Fleck

Fleck is a lightweight, native macOS menu-bar app for keeping multiple quick notes in tabs. The goal is a fast, local-first editor with rich-text formatting, bullets, numbered lists, installed-font support, and low idle resource use.

See the [product plan](PRODUCT_PLAN.md) for the complete vision, feature requirements, technical direction, performance goals, and delivery roadmap.

## Project status

Fleck is implemented as native SwiftPM executables. `Scripts/build-fleck-app.sh`
creates an unsigned `Fleck.app` with the agent helper packaged separately in
`Contents/SharedSupport`; signing, notarization, and export remain pending.

Clean Dictation is implemented as a release-disabled candidate. **Enhanced
Local is a non-shippable candidate:** it must not be included in a release
until the pinned model materially beats Standard on the privacy-safe
real-device corpus and every device, accessibility, resource, legal,
attribution, SBOM, signing/notarization, and Mac App Store gate in
[TESTING.md](TESTING.md) has recorded evidence. A green build or CI run is not
release approval. Until those gates pass, keep Enhanced Local out of release UI
and do not describe it as shipping.

## Persistent Dictation Bar

When enabled in **Settings → Dictation**, Fleck keeps one small, non-activating
status bar visible across Spaces. Its default trigger is **Right Option**. Hold
the selected physical modifier for 180 ms to dictate until release, or tap it
twice to start hands-free dictation; the next press finishes and Escape
cancels. The bar contains no transcript or shortcut hint while idle.

The trigger subscribes only to modifier `flagsChanged` transitions through macOS
**Input Monitoring** and never observes ordinary keys. During an accepted
capture, Fleck registers only Escape as a capture-scoped cancellation hot key,
then unregisters it at terminal. Choose a different left/right modifier or Fn
in Settings if needed. Fn is best-effort, and Command, Control, and Left Option
can conflict with normal modifier use. If Input Monitoring is unavailable, use
**Enable Input Monitoring** in Settings; after granting access, choose it again
to recheck and activate the selected modifier.

Use **Show status capsule** to hide or restore the persistent bar, then drag it
or use its menu to dock it at the bottom, left, or right edge. Dictation cleanup
remains on-device. Smart Capture routes only against active note IDs and titles;
ambiguous or failed routing saves to Inbox, never by reading note bodies.

## Agent workspace

Fleck can expose selected notes to local Codex, Claude Code, Kimi, or another
MCP client. Access is off by default and granted per note: use **Allow Agent
Access** in the note menu and accept the first-share confirmation. Turning the
toggle off immediately removes that note and its activity from integration
results.

In **Settings → Agents**, choose **Install Command Bridge**, add a separate
profile for each client, and copy its profile UUID. The verified helper is
installed at:

```text
~/Library/Application Support/Fleck/AgentBridge/bin/fleck
```

Use the absolute expanded helper path and profile UUID in one of these setup
forms:

```sh
codex mcp add fleck -- "/absolute/path/to/fleck" mcp --profile PROFILE_UUID
claude mcp add --scope user fleck -- "/absolute/path/to/fleck" mcp --profile PROFILE_UUID
```

Kimi configuration:

```json
{
  "mcpServers": {
    "fleck": {
      "command": "/absolute/path/to/fleck",
      "args": ["mcp", "--profile", "PROFILE_UUID"]
    }
  }
}
```

The generic MCP configuration is the inner `command`/`args` object above. The
helper also has a direct CLI; run `fleck --help`, then add `--profile
PROFILE_UUID` to every command and `--json` when machine-readable output is
needed. For example:

```sh
fleck notes list --profile PROFILE_UUID --json
fleck note read NOTE_UUID --profile PROFILE_UUID --json
printf '%s' 'Follow up' | fleck note append NOTE_UUID --stdin \
  --revision REVISION --operation-id OPERATION_UUID \
  --profile PROFILE_UUID --json
```

The MCP tools are `list_shared_notes`, `read_note`, `append_text`,
`insert_text`, `replace_lines`, `list_tasks`, `add_task`, `rename_task`,
`set_task_state`, `remove_task`, `list_agent_activity`, and
`undo_agent_change`.

Every write requires the revision returned by the last read and a caller-owned
operation UUID. On `revision_conflict`, reread before constructing a new
request. If a response is lost or times out, retry the unchanged request with
the same operation UUID; using a new UUID asks for a new mutation. Retry
tombstones and visible activity expire after 30 days. Undo is offered only
while the integration/profile scope, revision, note visibility, and exact text
patch still make reversal safe.

The bridge uses a private Unix-domain socket and Keychain credentials. It has no
cloud service, HTTP listener, or internet-facing port. This protects private
notes from cooperative integrations, not from malicious software already
running as the same macOS user. Integrations cannot reach unshared notes, Trash,
Dictation History, settings, sharing controls, note deletion, a shell, arbitrary
paths, or direct note files.

Revoke each profile in **Settings → Agents** before removing a client
configuration; revocation takes effect in Fleck even if helper-Keychain cleanup
needs a retry. There is not yet a helper-removal button. After quitting Fleck
and connected clients, the verified install can be removed without touching
notes:

```sh
rm -- "$HOME/Library/Application Support/Fleck/AgentBridge/bin/fleck" \
  "$HOME/Library/Application Support/Fleck/AgentBridge/install-receipt.json"
```

Settings can reinstall those two bridge-owned files. Do not remove the broader
`Fleck` Application Support directory; it contains notes and history.

## Development workflow

GitHub is the source of truth for this project. Changes should be made on a focused branch, committed with a descriptive message, pushed to GitHub, and submitted through a pull request. Keep application changes, relevant tests, and documentation together so the repository always reflects the current state of the product.

Build and launch the packaged development app so macOS associates microphone
and Speech permissions with Fleck:

```sh
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

Do not use `swift run Fleck` for interactive testing. It launches a bare
executable without the app-bundle privacy identity required by dictation.

Ordinary package resolution includes the MCP Swift SDK and its transitive
dependencies, all pinned by the root `Package.resolved`; none are linked into
Fleck. Ordinary builds also exclude the Enhanced Local SDK, implementation,
manifest, and resources. The exact FluidAudio pin lives in the resolver-only
`Packages/FleckEnhancedCandidateDependencies` package. To compile and run the
developer-only Enhanced candidate tests from the repository root, use the
lock-preservation wrapper with a separate scratch directory:

```sh
Scripts/resolve-enhanced-candidate.sh .build-candidate \
  swift test --disable-automatic-resolution \
    --scratch-path .build-candidate
```

Never set that variable for release validation; `Scripts/validate-macos.sh` and
`Scripts/check-release-size.sh` fail closed when it is present. A requested
candidate release is also rejected at compile time before linking.

Do not commit credentials, signing keys, provisioning profiles, local configuration containing secrets, or generated build output.
