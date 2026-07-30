# Fleck Agent Setup and Startup Recovery Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Fleck safely ignore only a recreated empty legacy workspace, make the packaged Agent Connector usable in unsigned development builds, and replace opaque setup failures with actionable UI and launch instructions.

**Architecture:** Keep startup classification in `FleckProductMigration`, with a fail-closed receipt check and exact legacy-root allowlist. Keep agent credentials in the ordinary device-local macOS login Keychain by removing the entitlement-only query flag from both app and helper stores. Keep packaging mandatory, expose that requirement through localized errors and Settings gating, and retain the existing verified-helper installation boundary.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, AppKit, Security.framework, SwiftPM, shell packaging scripts.

## Global Constraints

- Ignore a legacy root only when the canonical Fleck workspace exists, a schema-v1 migration receipt matches both exact standardized paths, and the legacy root is a non-symlink default empty workspace.
- The disposable legacy workspace contains exactly one `Untitled` note with empty body, no RTF, no color, no pin, no agent access, and revision zero.
- Only `workspace.json`, `preferences.json`, that note's zero-byte Markdown
  file, and the exact empty generated directories
  `AgentActivity/{Prepared,Records,Tombstones}` and `AgentBridge` are allowed
  in a disposable legacy root. Any file inside those directories, symlink,
  RTF, Trash, history, recovery, model, agent data, or unknown path fails
  closed.
- Never delete or modify the ignored legacy root.
- Install only `Fleck.app/Contents/SharedSupport/fleck-agent`; never search repository build products.
- Store agent credentials only in the standard macOS login Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Do not write credentials to preferences, JSON profiles, setup snippets, logs, notes, or command arguments.
- Call the UI feature **Agent Connector**.
- Supported interactive development launch is `Scripts/build-fleck-app.sh` followed by `/usr/bin/open -n .build/Fleck.app`.

---

### Task 1: Fail-closed recreated legacy workspace classification

**Files:**
- Modify: `Sources/FleckCore/FleckProductMigration.swift`
- Modify: `Tests/FleckCoreTests/FleckProductMigrationTests.swift`
- Modify: `Tests/FleckAppTests/FleckStartupMigrationTests.swift`

**Interfaces:**
- Consumes: `FleckMigrationReceipt`, `LocalStoreSnapshotWriter.loadSnapshot()`, and the canonical/legacy paths already computed by `prepare()`.
- Produces: `FleckProductMigration.prepare()` returning `.alreadyMigrated(canonical)` only for a receipt-backed disposable legacy root.

- [x] **Step 1: Add the failing core regression**

Create a canonical workspace and schema-v1 receipt, then create the legacy snapshot with:

```swift
let empty = Note(
  title: "Untitled",
  body: "",
  richTextRTF: nil,
  tabColorHex: nil,
  isPinned: false,
  agentAccess: false,
  revision: 0
)
_ = try LocalStoreSnapshotWriter(rootURL: legacy).save(
  workspace: Workspace(notes: [empty], selectedNoteID: empty.id),
  preferences: .init(),
  generation: 1
)
```

Assert `.alreadyMigrated(canonical)` and byte-for-byte preservation of both roots.

- [x] **Step 2: Add fail-closed matrix tests**

Starting from the disposable fixture, independently prove conflicts for:

```text
missing receipt
wrong receipt legacy path
wrong receipt canonical path
schema version other than 1
nonempty body
RTF sidecar
renamed note
pinned note
colored note
agent-shared note
nonzero revision
second note
Trash or Recovery directory
unknown file
nested directory
nonempty file under AgentActivity or AgentBridge
symlinked legacy root
```

Each case must preserve both roots and return the existing `.conflictingWorkspaces` or `.unsafeLegacyRoot` error.

- [x] **Step 3: Run the migration tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution --filter FleckProductMigration
```

Expected: the recreated-empty test fails with `.conflictingWorkspaces`.

- [x] **Step 4: Implement exact classification**

In `FleckProductMigration.prepare()`, before returning the two-workspace conflict, call a private predicate equivalent to:

```swift
private func canIgnoreRecreatedLegacyWorkspace(
  legacy: URL,
  canonical: URL
) -> Bool
```

The predicate must:

1. Reject symlinks and unreadable roots.
2. Decode the canonical migration receipt with ISO-8601 dates.
3. Require schema version 1 and exact standardized legacy/canonical paths.
4. Load the legacy root through `LocalStoreSnapshotWriter`.
5. Independently decode the raw manifest and preferences rather than accepting
   fallback defaults from a hashless malformed snapshot.
6. Require `.root`, one exact default empty note, and raw note order and
   selection pointing only to that note.
7. Enumerate the legacy root without following symlinks and allow only the
   manifest, preferences, selected note Markdown filename, and the exact empty
   generated Agent Activity and Agent Connector directories.
8. Require the raw Markdown data to be zero bytes.

Return `.alreadyMigrated(canonical)` without modifying either root when the predicate succeeds.

- [x] **Step 5: Add the startup integration regression**

Use `FleckStartupContext` and `AppState` with the same canonical/receipt/recreated-legacy fixture. Await initial load and assert:

```swift
#expect(startup.migrationError == nil)
#expect(state.isAgentWorkspaceAvailable)
#expect(!state.isPersistenceBlocked)
#expect(state.selectedNote?.id == canonicalNote.id)
```

- [x] **Step 6: Run Task 1 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'FleckProductMigration|FleckStartupMigration'
```

Expected: all migration and startup tests pass.

---

### Task 2: Unsigned-compatible agent Keychain queries

**Files:**
- Modify: `Sources/FleckApp/AgentCredentialSecurity.swift`
- Modify: `Sources/FleckAgentBridge/BridgeCredentialStore.swift`
- Modify: `Tests/FleckAppTests/AgentProfileStoreTests.swift`
- Modify: `Tests/FleckAgentBridgeTests/BridgeCredentialStoreTests.swift`

**Interfaces:**
- Consumes: existing `MigratingKeychainDataStore` services and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Produces: app and helper base queries that target the ordinary login Keychain without `kSecUseDataProtectionKeychain`.

- [x] **Step 1: Write failing query-shape tests**

For `AgentKeychainSecretStore.baseQuery` and a test-visible
`BridgeCredentialStore.keychainQuery(service:account:)`, assert:

```swift
#expect(query[kSecClass] as? CFString == kSecClassGenericPassword)
#expect(query[kSecAttrService] as? String == service)
#expect(query[kSecAttrAccount] as? String == account)
#expect(query[kSecUseDataProtectionKeychain] == nil)
```

- [x] **Step 2: Run focused tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'AgentProfileStoreTests|BridgeCredentialStoreTests'
```

Expected: both query-shape tests fail because the Data Protection flag is present or the bridge query helper is not visible.

- [x] **Step 3: Remove only the entitlement-only flag**

Remove:

```swift
kSecUseDataProtectionKeychain: true
```

from both agent credential base queries. Keep generic-password class, service, account, constant-time verification, device-only accessibility, migration services, and deletion semantics unchanged.

- [x] **Step 4: Run focused tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'AgentProfileStoreTests|AgentTaskHandleCodecTests|BridgeCredentialStoreTests'
```

Expected: all credential, signing-key, migration, and helper tests pass.

---

### Task 3: Agent Connector terminology, setup gating, and actionable errors

**Files:**
- Modify: `Sources/FleckCore/AgentWorkspaceModels.swift`
- Modify: `Sources/FleckApp/AgentBridgeInstaller.swift`
- Modify: `Sources/FleckApp/AgentSettingsView.swift`
- Modify: `Sources/FleckApp/AppState.swift`
- Modify: `Tests/FleckAppTests/AgentPresentationTests.swift`
- Modify: `Tests/FleckAppTests/AgentBridgeInstallerTests.swift`

**Interfaces:**
- Produces: `AgentConnectorPresentation.canAddIntegration(workspaceAvailable:connectorInstalled:) -> Bool`.
- Produces: `LocalizedError` descriptions for `AgentWorkspaceError` and `AgentBridgeInstallerError`.
- Consumes: `AppState.isAgentWorkspaceAvailable` and verified installed-helper state.

- [x] **Step 1: Write failing presentation tests**

Assert the presentation contract:

```swift
#expect(AgentConnectorPresentation.sectionTitle == "Agent Connector")
#expect(AgentConnectorPresentation.installTitle == "Install Agent Connector")
#expect(AgentConnectorPresentation.explanation.contains("local helper"))
#expect(AgentConnectorPresentation.explanation.contains("explicitly shared"))
#expect(AgentConnectorPresentation.explanation.contains("no network listener"))
#expect(!AgentConnectorPresentation.canAddIntegration(
  workspaceAvailable: true,
  connectorInstalled: false
))
#expect(!AgentConnectorPresentation.canAddIntegration(
  workspaceAvailable: false,
  connectorInstalled: true
))
#expect(AgentConnectorPresentation.canAddIntegration(
  workspaceAvailable: true,
  connectorInstalled: true
))
```

- [x] **Step 2: Write failing localized-error tests**

Assert:

```swift
#expect(
  AgentBridgeInstallerError.bundledHelperMissing.localizedDescription
    .contains("packaged Fleck app")
)
#expect(
  AgentBridgeInstallerError.bundledHelperMissing.recoverySuggestion?
    .contains("Scripts/build-fleck-app.sh") == true
)
#expect(
  AgentWorkspaceError(code: .internalSaveFailure).localizedDescription
    == "Fleck could not update its local agent data."
)
```

Also assert descriptions do not contain `FleckApp.`, `FleckCore.`, `MenuBarNotes`, `error 1`, or raw private paths.

- [x] **Step 3: Run focused tests and verify RED**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'AgentPresentationTests|AgentBridgeInstallerTests'
```

Expected: terminology, gating, and localized-error assertions fail.

- [x] **Step 4: Implement the minimal presentation model**

Add `AgentConnectorPresentation` beside `AgentProfilesPresentation`. Use its static copy in `AgentSettingsView`, show the explanation directly under status, and disable every Add Integration button unless both readiness conditions are true.

Use:

```swift
.disabled(
  !AgentConnectorPresentation.canAddIntegration(
    workspaceAvailable: appState.isAgentWorkspaceAvailable,
    connectorInstalled: appState.isAgentConnectorInstalled
  )
)
```

Rename user-facing “Command Bridge” text to “Agent Connector”; do not rename executable paths, protocol types, or storage directories.

- [x] **Step 5: Implement localized descriptions**

Conform `AgentWorkspaceError` and `AgentBridgeInstallerError` to
`LocalizedError`. Give every case short, content-free descriptions. For
`bundledHelperMissing`, return a recovery suggestion with the packaged build
and open commands.

Update `AppState.installAgentBridge()` and profile creation failure copy to say
“Agent Connector” and rely on those localized descriptions.

- [x] **Step 6: Run Task 3 tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'AgentPresentationTests|AgentBridgeInstallerTests|AgentProfileStoreTests'
```

Expected: all presentation, installer, and profile tests pass.

---

### Task 4: Supported packaged-app workflow and release verification

**Files:**
- Modify: `README.md`
- Modify: `TESTING.md`
- Modify: `IMPLEMENTATION_STATUS.md`
- Modify: `Tests/FleckAppTests/FleckBrandAuditTests.swift`

**Interfaces:**
- Consumes: `Scripts/build-fleck-app.sh`.
- Produces: one documented interactive launch flow and repository checks that reject obsolete setup terminology.

- [x] **Step 1: Write failing documentation audit assertions**

Extend `FleckBrandAuditTests` to assert:

```text
README and TESTING use "Agent Connector"
TESTING contains Scripts/build-fleck-app.sh
TESTING contains /usr/bin/open -n .build/Fleck.app
TESTING does not contain swift run Fleck as an interactive launch command
current Sources and current documentation contain no user-facing "Command Bridge"
```

- [x] **Step 2: Run the audit and verify RED**

Run:

```sh
swift test --disable-automatic-resolution --filter FleckBrandAuditTests
```

Expected: the audit fails on current terminology and `TESTING.md`.

- [x] **Step 3: Update documentation**

Replace user-facing “Command Bridge” with “Agent Connector”, explain that the
connector is embedded only in the packaged app, and standardize interactive
testing on:

```sh
Scripts/build-fleck-app.sh
/usr/bin/open -n .build/Fleck.app
```

Keep direct `fleck-agent` CLI and MCP examples unchanged.

- [x] **Step 4: Run all focused tests**

Run:

```sh
swift test --disable-automatic-resolution \
  --filter 'FleckProductMigration|FleckStartupMigration|AgentProfileStoreTests|AgentTaskHandleCodecTests|BridgeCredentialStoreTests|AgentPresentationTests|AgentBridgeInstallerTests|FleckBrandAuditTests'
```

Expected: all focused tests pass.

- [x] **Step 5: Run complete validation**

Run:

```sh
Scripts/validate-macos.sh
```

Expected: full tests, release builds, bundle inspection, helper packaging,
size/privacy audits, lock preservation, and candidate-release rejection pass.

- [x] **Step 6: Verify the final package boundary**

Run:

```sh
test -x .build/Fleck.app/Contents/MacOS/Fleck
test -x .build/Fleck.app/Contents/SharedSupport/fleck-agent
git diff --check
git status --short
```

Then manually launch only the packaged app:

```sh
/usr/bin/open -n .build/Fleck.app
```

Installation, temporary Codex-profile creation, setup-snippet inspection, and
live Keychain behavior remain manual macOS checks and must be reported
separately from automated evidence.
