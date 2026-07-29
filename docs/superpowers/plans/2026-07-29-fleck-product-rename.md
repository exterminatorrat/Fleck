# Fleck Product Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the complete active Motes product to Fleck while preserving all
local data and keeping existing `motes` CLI/MCP configurations working for one
transition release.

**Architecture:** A tested migration coordinator resolves the canonical Fleck
Application Support root before any store starts. Canonical Fleck Keychain,
bridge, package, bundle, and UI identities replace active Motes names; narrowly
allowlisted legacy identifiers remain only for data adoption and the temporary
compatibility launcher.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, Security/Keychain,
SwiftPM, Swift Testing, POSIX shell, GitHub Actions.

## Global Constraints

- Canonical app identity is `Fleck`, `Fleck.app`, and `com.harryjin.fleck`.
- Canonical helper and installed command are `fleck-agent` and `fleck`.
- Canonical MCP server and socket names are `fleck` and `fleck.sock`.
- Canonical Application Support root is `Fleck`.
- Existing notes, RTF, Trash, preferences, dictation history/model state,
  agent profiles/activity, receipts, and credentials must survive migration.
- A `motes` compatibility launcher remains at the prior absolute installed
  path for exactly the first Fleck transition release.
- The legacy workspace and Keychain items are never deleted by this release.
- Both-workspace conflicts fail closed and never merge or select data silently.
- Historical specifications, plans, and Git history remain unchanged.
- Active Motes names are allowed only in migration constants, compatibility
  code/tests, and the historical-document exclusion.
- No new dependency is added.
- Every production change follows RED → GREEN and each task ends in a focused
  commit.

---

### Task 1: Filesystem Migration Coordinator

**Files:**
- Create: `Sources/MenuBarNotesCore/FleckProductMigration.swift`
- Create: `Tests/MenuBarNotesCoreTests/FleckProductMigrationTests.swift`

**Interfaces:**
- Produces:

```swift
public enum FleckProductPaths {
  public static let canonicalDirectoryName = "Fleck"
  public static let legacyDirectoryName = "MenuBarNotes"
  public static let migrationReceiptName = "motes-to-fleck-v1.json"
}

public struct FleckMigrationReceipt: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let migratedAt: Date
  public let legacyPath: String
  public let canonicalPath: String
}

public enum FleckProductMigrationError: Error, Equatable, Sendable {
  case unsafeLegacyRoot
  case conflictingWorkspaces(legacyPath: String, canonicalPath: String)
  case invalidMigratedWorkspace
  case rollbackFailed(legacyPath: String, canonicalPath: String)
  case filesystemFailure
}

public enum FleckProductMigrationOutcome: Equatable, Sendable {
  case freshInstall(URL)
  case migrated(URL)
  case alreadyMigrated(URL)
  case failed(URL, FleckProductMigrationError)
}

public struct FleckProductMigration {
  public init(
    applicationSupportParent: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  )

  public func prepare() -> FleckProductMigrationOutcome
}
```

- Consumes: existing `LocalStoreSnapshotWriter` to validate a migrated
  snapshot without rewriting content.

- [ ] **Step 1: Write the migration RED tests**

Add temporary-directory tests proving:

```swift
@Test func migratesCompleteLegacyWorkspaceAndWritesReceipt() throws
@Test func repeatedMigrationUsesCanonicalRootWithoutRewritingIt() throws
@Test func canonicalOnlyWorkspaceRunsWithoutInventingAMigrationReceipt() throws
@Test func compatibilityOnlyLegacyRootIsNotAWorkspaceConflict() throws
@Test func twoWorkspaceRootsFailClosedAndPreserveBoth() throws
@Test func symlinkedLegacyRootFailsClosed() throws
@Test func invalidMovedWorkspaceRollsBackToLegacyPath() throws
@Test func failedRollbackReportsBothPreservedPaths() throws
```

Build the legacy fixture through `LocalStoreSnapshotWriter.save`, then add
representative `Trash`, `DictationHistory`, `Models`, `AgentIntegrations`, and
`AgentActivity` files. Compare every file byte-for-byte after migration.

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter FleckProductMigrationTests
```

Expected: compile failure because `FleckProductMigration` does not exist.

- [ ] **Step 3: Implement the minimum migration**

Implement same-volume staged moves:

```swift
let legacy = applicationSupportParent
  .appendingPathComponent(FleckProductPaths.legacyDirectoryName, isDirectory: true)
let canonical = applicationSupportParent
  .appendingPathComponent(FleckProductPaths.canonicalDirectoryName, isDirectory: true)
let staging = applicationSupportParent
  .appendingPathComponent(".fleck-migration-\(UUID().uuidString)", isDirectory: true)
```

Treat a legacy root containing only
`AgentBridge/fleck-compatibility-v1.json` and its `bin/motes` launcher as a
compatibility container, not workspace data. Recognize workspace data from
the manifest, note, Trash, dictation, model, integration, or activity
artifacts.

Move `legacy → staging → canonical`, validate with
`LocalStoreSnapshotWriter(rootURL: canonical).loadSnapshot()`, reject a
`.fresh` snapshot source as invalid migrated data, and atomically write
`FleckMigrationReceipt`. If validation or receipt writing fails, move
`canonical → legacy`. Never use copy-and-delete or merge directory contents.

- [ ] **Step 4: Verify focused migration behavior**

Run the Task 1 command again. Expected: all migration tests pass.

- [ ] **Step 5: Run core regressions**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter MenuBarNotesCoreTests
git diff --check
```

Expected: existing core tests and whitespace check pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarNotesCore/FleckProductMigration.swift \
  Tests/MenuBarNotesCoreTests/FleckProductMigrationTests.swift
git commit -m "feat: migrate legacy data into Fleck storage"
```

---

### Task 2: Startup and Canonical Storage Integration

**Files:**
- Modify: `Sources/MenuBarNotesAgentProtocol/AgentBridgeEndpoint.swift`
- Modify: `Sources/MenuBarNotesApp/MenuBarNotesApp.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Modify: `Sources/MenuBarNotesApp/AgentProfileStore.swift`
- Modify: `Sources/MenuBarNotesApp/AgentBridgeInstaller.swift`
- Modify: `Sources/MenuBarNotesApp/EnhancedModelManager.swift`
- Modify: `Tests/MenuBarNotesAgentProtocolTests/AgentWireProtocolTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/AppStateTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/AgentIPCServerTests.swift`
- Create: `Tests/MenuBarNotesAppTests/FleckStartupMigrationTests.swift`

**Interfaces:**
- Produces:

```swift
struct FleckStartupContext {
  let applicationSupportURL: URL
  let migrationError: FleckProductMigrationError?

  init(outcome: FleckProductMigrationOutcome)
}

extension AgentBridgeEndpoint {
  public static func applicationSupportURL(
    fileManager: FileManager = .default
  ) -> URL
}
```

- `AppState.init` gains:

```swift
startupMigrationError: FleckProductMigrationError? = nil
```

- `AppState` exposes:

```swift
@Published private(set) var startupMigrationError: FleckProductMigrationError?
var isPersistenceBlocked: Bool { startupMigrationError != nil }
```

- [ ] **Step 1: Write startup RED tests**

Prove:

```swift
@Test func startupMigrationCompletesBeforeAnyStoreOrSocketUsesFleckRoot() async throws
@Test func migrationConflictFinishesInitialLoadButKeepsAgentWorkspaceUnavailable() async
@Test func migrationConflictBlocksEditorPersistenceAndPreservesBothRoots() async throws
@Test func canonicalEndpointsUseFleckAndFleckSocket() throws
```

The test initializer injects a `FleckProductMigrationOutcome`; no test touches
the user's Application Support directory.

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter FleckStartupMigrationTests
```

Expected: failures for missing startup context and blocking state.

- [ ] **Step 3: Integrate migration before runtime construction**

At the beginning of the app initializer:

```swift
let parent = FileManager.default.urls(
  for: .applicationSupportDirectory,
  in: .userDomainMask
)[0]
let outcome = FleckProductMigration(applicationSupportParent: parent).prepare()
let startup = FleckStartupContext(outcome: outcome)
```

Pass `startup.applicationSupportURL` into `AppState`, `AgentProfileStore`,
`AgentActivityStore`, dictation history/model roots, bridge installer, and IPC
endpoint construction. Remove independent default `MenuBarNotes` path
construction from active stores.

When migration fails, finish initial-load waiters, keep
`isAgentWorkspaceAvailable == false`, cancel saves, and render a
Fleck-branded actionable error in `NotesPanel` instead of an editable empty
workspace. Do not start the IPC server.

- [ ] **Step 4: Switch canonical endpoint constants**

Return `Application Support/Fleck` and `AgentBridge/fleck.sock` from
`AgentBridgeEndpoint`. Legacy values live only in `FleckProductPaths`.

- [ ] **Step 5: Verify startup and existing persistence**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter 'FleckStartupMigrationTests|AppStateTests|AgentIPCServerTests|AgentWireProtocolTests'
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarNotesAgentProtocol/AgentBridgeEndpoint.swift \
  Sources/MenuBarNotesApp/MenuBarNotesApp.swift \
  Sources/MenuBarNotesApp/AppState.swift \
  Sources/MenuBarNotesApp/AgentProfileStore.swift \
  Sources/MenuBarNotesApp/AgentBridgeInstaller.swift \
  Sources/MenuBarNotesApp/EnhancedModelManager.swift \
  Tests/MenuBarNotesAgentProtocolTests/AgentWireProtocolTests.swift \
  Tests/MenuBarNotesAppTests/AppStateTests.swift \
  Tests/MenuBarNotesAppTests/AgentIPCServerTests.swift \
  Tests/MenuBarNotesAppTests/FleckStartupMigrationTests.swift
git commit -m "feat: start Fleck from canonical migrated storage"
```

---

### Task 3: Keychain Compatibility Migration

**Files:**
- Create: `Sources/MenuBarNotesCore/MigratingKeychainDataStore.swift`
- Create: `Tests/MenuBarNotesCoreTests/MigratingKeychainDataStoreTests.swift`
- Modify: `Sources/MenuBarNotesApp/AgentCredentialSecurity.swift`
- Modify: `Sources/MenuBarNotesApp/AgentTaskHandleCodec.swift`
- Modify: `Sources/MenuBarNotesApp/EnhancedModelManager.swift`
- Modify: `Sources/MotesAgentBridge/BridgeCredentialStore.swift`
- Modify: `Tests/MenuBarNotesAppTests/AgentProfileStoreTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/AgentTaskHandleCodecTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift`
- Create: `Tests/MotesAgentBridgeTests/BridgeCredentialStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public protocol KeychainDataStoring: Sendable {
  func read(service: String, account: String) throws -> Data?
  func write(_ data: Data, service: String, account: String) throws
}

public struct MigratingKeychainDataStore: Sendable {
  public init(
    store: any KeychainDataStoring,
    canonicalService: String,
    legacyServices: [String]
  )

  public func readOrMigrate(account: String) throws -> Data?
  public func write(_ data: Data, account: String) throws
}
```

- Canonical services:

```text
com.harryjin.fleck.agent-profile-verifier
com.harryjin.fleck.agent-task-handles
com.harryjin.fleck.agent-profile
com.harryjin.fleck.enhanced-model-resume
```

- Legacy services remain exact read-only fallbacks:

```text
com.harryjin.motes.agent-profile-verifier
com.harryjin.motes.agent-task-handles
com.harryjin.motes.agent-profile
com.motes.enhanced-model-resume
```

- [ ] **Step 1: Write Keychain migration RED tests**

Cover:

```swift
@Test func canonicalSecretWinsWithoutReadingLegacy() throws
@Test func legacySecretCopiesToCanonicalAndVerifiesBeforeReturn() throws
@Test func failedCanonicalWriteLeavesLegacySecretUntouched() throws
@Test func failedReadbackRejectsTheMigratedSecret() throws
@Test func missingCanonicalAndLegacyReturnsNil() throws
@Test func bridgeCredentialLoadsLegacyProfileAndThenUsesFleckService() throws
@Test func enhancedResumeKeyMigratesWithoutChangingItsBytes() throws
```

Use a locked in-memory `KeychainDataStoring` fake. Assert that no test or
production migration invokes a legacy delete.

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter 'MigratingKeychainDataStoreTests|AgentProfileStoreTests|AgentTaskHandleCodecTests|EnhancedModelManagerTests|BridgeCredentialStoreTests'
```

Expected: compile failures for the missing migrating store/canonical services.

- [ ] **Step 3: Implement verified read-through migration**

`readOrMigrate` reads canonical first. For the first non-nil legacy value it:

```swift
try store.write(legacyValue, service: canonicalService, account: account)
guard try store.read(service: canonicalService, account: account) == legacyValue else {
  throw KeychainMigrationError.verificationFailed
}
return legacyValue
```

It never deletes the legacy item. Writes and new profile creation target only
the canonical service.

- [ ] **Step 4: Integrate all four secret families**

Use the shared helper for profile verifiers, task handles, helper credentials,
and Enhanced resume authentication. Keep existing constant-time comparison,
32-byte validation, access-control attributes, and error redaction.

- [ ] **Step 5: Verify focused and full secret tests**

Run the Task 3 filter again, then:

```bash
swift test --disable-automatic-resolution
```

Expected: focused tests and the complete suite pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarNotesCore/MigratingKeychainDataStore.swift \
  Tests/MenuBarNotesCoreTests/MigratingKeychainDataStoreTests.swift \
  Sources/MenuBarNotesApp/AgentCredentialSecurity.swift \
  Sources/MenuBarNotesApp/AgentTaskHandleCodec.swift \
  Sources/MenuBarNotesApp/EnhancedModelManager.swift \
  Sources/MotesAgentBridge/BridgeCredentialStore.swift \
  Tests/MenuBarNotesAppTests/AgentProfileStoreTests.swift \
  Tests/MenuBarNotesAppTests/AgentTaskHandleCodecTests.swift \
  Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift \
  Tests/MotesAgentBridgeTests/BridgeCredentialStoreTests.swift
git commit -m "feat: migrate legacy credentials into Fleck Keychain services"
```

---

### Task 4: Canonical Bridge and One-Release `motes` Launcher

**Files:**
- Modify: `Sources/MenuBarNotesApp/AgentBridgeInstaller.swift`
- Modify: `Sources/MenuBarNotesApp/AgentClientSetup.swift`
- Create: `Sources/MenuBarNotesApp/ShellArgument.swift`
- Modify: `Sources/MotesAgentBridge/AgentIPCClient.swift`
- Modify: `Sources/MotesAgentBridge/BridgeCommand.swift`
- Modify: `Sources/MotesAgentBridge/MotesAgentBridge.swift`
- Modify: `Sources/MotesAgentBridge/MotesMCPServer.swift`
- Modify: `Sources/MotesAgentBridge/MotesMCPToolRegistry.swift`
- Modify: `Tests/MenuBarNotesAppTests/AgentBridgeInstallerTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/AgentClientSetupTests.swift`
- Modify: `Tests/MotesAgentBridgeTests/AgentIPCClientTests.swift`
- Modify: `Tests/MotesAgentBridgeTests/BridgeCommandTests.swift`
- Modify: `Tests/MotesAgentBridgeTests/MotesMCPServerTests.swift`

**Interfaces:**
- `AgentBridgeInstaller` canonical URLs:

```swift
var installedHelperURL: URL // Fleck/AgentBridge/bin/fleck
var legacyLauncherURL: URL  // MenuBarNotes/AgentBridge/bin/motes
var migratedLegacyHelperURL: URL // Fleck/AgentBridge/bin/motes
```

- Compatibility marker:

```text
MenuBarNotes/AgentBridge/fleck-compatibility-v1.json
```

- The compatibility launcher content is generated from the exact canonical
  path:

```sh
#!/bin/sh
exec '/absolute/canonical/path/to/fleck' "$@"
```

The path uses the existing shell-argument encoder and the marker/receipt stores
SHA-256 for both canonical helper and launcher.

- [ ] **Step 1: Write bridge transition RED tests**

Prove:

```swift
@Test func installWritesVerifiedFleckHelperAndMotesCompatibilityLauncher() throws
@Test func existingMotesReceiptMustVerifyBeforeReplacement() throws
@Test func movedLegacyHelperVerifiesAgainstItsPreMigrationReceipt() throws
@Test func failedCompatibilitySwapRollsBackCanonicalAndLegacyFiles() throws
@Test func repeatedInstallIsIdempotent() throws
@Test func disconnectExecutesOnlyVerifiedCanonicalFleckHelper() throws
@Test func newClientSetupUsesFleckNamesAndPath() throws
@Test func legacyAbsoluteMotesPathRunsFleckMCPWithoutProtocolNoise() async throws
@Test func mcpServerReportsFleckIdentity() async throws
```

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter 'AgentBridgeInstallerTests|AgentClientSetupTests|MotesMCPServerTests'
```

Expected: failures for old paths, identity, and one-file installer receipt.

- [ ] **Step 3: Extend the existing serialized installer transaction**

After Task 1, the moved legacy helper is
`Fleck/AgentBridge/bin/motes` while its receipt still names the former absolute
path. Accept that one mismatch only when the old bundle identifier, helper
hash, old destination, and verified migration receipt all agree.

Snapshot canonical helper/receipt, moved legacy helper, and legacy
launcher/marker before mutation. Install the bundled helper to `fleck`, create
the fixed launcher data, apply both swaps under the existing transaction lock,
verify both hashes, then write receipts. Restore every prior artifact on any
failure.

Never execute an unverified legacy binary. Provision and Disconnect execute
only `verifiedInstalledHelperURL()`.

- [ ] **Step 4: Switch new client/MCP identity**

Generate:

```text
codex mcp add fleck -- /.../fleck mcp --profile <UUID>
claude mcp add --scope user fleck -- /.../fleck mcp --profile <UUID>
```

Kimi uses `"fleck"` as its MCP key. The server reports `name: "fleck"`.
Recovery messages say “Open Fleck” or “Reconnect in Fleck Settings.”

- [ ] **Step 5: Verify old and new paths**

Run the Task 4 filter and a subprocess smoke that invokes both canonical and
legacy command paths with `--help`. Expected: equal exit status and no
compatibility text on stdout.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarNotesApp/AgentBridgeInstaller.swift \
  Sources/MenuBarNotesApp/AgentClientSetup.swift \
  Sources/MenuBarNotesApp/ShellArgument.swift \
  Sources/MotesAgentBridge \
  Tests/MenuBarNotesAppTests/AgentBridgeInstallerTests.swift \
  Tests/MenuBarNotesAppTests/AgentClientSetupTests.swift \
  Tests/MotesAgentBridgeTests
git commit -m "feat: install Fleck bridge with Motes compatibility"
```

---

### Task 5: Rename Swift Package Graph and Active Source

**Files:**
- Move: `Sources/MenuBarNotesCore` → `Sources/FleckCore`
- Move: `Sources/MenuBarNotesAgentProtocol` → `Sources/FleckAgentProtocol`
- Move: `Sources/MenuBarNotesApp` → `Sources/FleckApp`
- Move: `Sources/MotesAgentBridge` → `Sources/FleckAgentBridge`
- Move: `Tests/MenuBarNotesCoreTests` → `Tests/FleckCoreTests`
- Move: `Tests/MenuBarNotesAgentProtocolTests` → `Tests/FleckAgentProtocolTests`
- Move: `Tests/MenuBarNotesAppTests` → `Tests/FleckAppTests`
- Move: `Tests/MotesAgentBridgeTests` → `Tests/FleckAgentBridgeTests`
- Move: `Sources/FleckApp/MenuBarNotesApp.swift` → `Sources/FleckApp/FleckApp.swift`
- Move: `Sources/FleckAgentBridge/MotesAgentBridge.swift` → `Sources/FleckAgentBridge/FleckAgentBridge.swift`
- Move: `Sources/FleckAgentBridge/MotesMCPServer.swift` → `Sources/FleckAgentBridge/FleckMCPServer.swift`
- Move: `Sources/FleckAgentBridge/MotesMCPToolRegistry.swift` → `Sources/FleckAgentBridge/FleckMCPToolRegistry.swift`
- Move: `Tests/FleckAgentBridgeTests/MotesMCPServerTests.swift` → `Tests/FleckAgentBridgeTests/FleckMCPServerTests.swift`
- Move: `Tests/FleckAgentBridgeTests/MotesMCPToolRegistryTests.swift` → `Tests/FleckAgentBridgeTests/FleckMCPToolRegistryTests.swift`
- Modify: `Package.swift`
- Modify: all imports and renamed primary type references under `Sources` and
  `Tests`

**Interfaces:**
- SwiftPM products/targets:

```swift
.library(name: "FleckCore", targets: ["FleckCore"])
.library(name: "FleckAgentProtocol", targets: ["FleckAgentProtocol"])
.executable(name: "Fleck", targets: ["FleckApp"])
.executable(name: "fleck-agent", targets: ["FleckAgentBridge"])
```

- Main types:

```swift
@main struct FleckApp: App
enum FleckAgentBridge
enum FleckMCPServer
enum FleckMCPToolRegistry
```

- Error rename:

```swift
case fleckUnavailable = "fleck_unavailable"
```

- [ ] **Step 1: Add package identity RED assertions**

Update dependency/identity tests to require the four canonical target names,
the two canonical executables, `Fleck` package name, and no active
`MenuBarNotes*` or `Motes*` target.

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --disable-automatic-resolution \
  --filter 'MCPDependencyPinTests|AgentWireProtocolTests'
```

Expected: assertions fail against the legacy package graph.

- [ ] **Step 3: Perform Git-aware moves**

Use exact `git mv` operations from the Files list. Update `Package.swift`,
imports, `@testable import`, type names, logger labels, recovery messages, and
the unavailable error case. Do not rename domain concepts such as
`MenuBarExtra` or the repository directory.

- [ ] **Step 4: Compile target-by-target**

Run:

```bash
swift build --disable-automatic-resolution --product Fleck
swift build --disable-automatic-resolution --product fleck-agent
swift test --disable-automatic-resolution
```

Expected: canonical products build and the complete test suite passes.

- [ ] **Step 5: Confirm no obsolete active target directories**

Run:

```bash
test ! -e Sources/MenuBarNotesCore
test ! -e Sources/MenuBarNotesAgentProtocol
test ! -e Sources/MenuBarNotesApp
test ! -e Sources/MotesAgentBridge
test ! -e Tests/MenuBarNotesCoreTests
test ! -e Tests/MenuBarNotesAgentProtocolTests
test ! -e Tests/MenuBarNotesAppTests
test ! -e Tests/MotesAgentBridgeTests
```

Expected: every assertion passes.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "refactor: rename active Swift modules to Fleck"
```

---

### Task 6: Bundle, Candidate Package, Scripts, CI, and Active Copy

**Files:**
- Move: `Packages/MotesEnhancedCandidateDependencies` →
  `Packages/FleckEnhancedCandidateDependencies`
- Move: `Scripts/build-motes-app.sh` → `Scripts/build-fleck-app.sh`
- Modify: `Sources/FleckApp/Info.plist`
- Modify: `Sources/FleckApp/Resources/ThirdPartyNotices.md`
- Modify: `Sources/FleckApp/NativeRichTextEditor.swift`
- Modify: `Sources/FleckApp/AgentActivityView.swift`
- Modify: `Sources/FleckApp/StatusItemContextMenuController.swift`
- Modify: `Sources/FleckApp/AgentChangeBanner.swift`
- Modify: `Sources/FleckApp/AgentCommandService.swift`
- Modify: `Sources/FleckApp/AgentCredentialSecurity.swift`
- Modify: `Sources/FleckApp/AgentIPCServer.swift`
- Modify: `Sources/FleckApp/AgentRichTextMutator.swift`
- Modify: `Sources/FleckApp/AppState.swift`
- Modify: `Sources/FleckApp/DictationAvailability.swift`
- Modify: `Sources/FleckApp/EnhancedModelManager.swift`
- Modify: `Sources/FleckApp/EnhancedSpeechCapture.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Sources/FleckApp/SettingsView.swift`
- Modify: `Scripts/audit-agent-boundary.sh`
- Modify: `Scripts/check-candidate-release-rejected.sh`
- Modify: `Scripts/check-release-size.sh`
- Modify: `Scripts/profile-memory.sh`
- Modify: `Scripts/resolve-enhanced-candidate.sh`
- Modify: `Scripts/test-enhanced-candidate-lock-preservation.sh`
- Modify: `Scripts/test-enhanced-candidate-pin.sh`
- Modify: `Scripts/validate-macos.sh`
- Modify: `Scripts/verify-enhanced-candidate-pin.swift`
- Modify: `Scripts/verify-enhanced-model-manifest.swift`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `ARCHITECTURE.md`
- Modify: `CONTRIBUTING.md`
- Modify: `IMPLEMENTATION_STATUS.md`
- Modify: `PRODUCT_PLAN.md`
- Modify: `TESTING.md`
- Create: `Scripts/audit-fleck-brand.sh`
- Create: `Tests/FleckAppTests/FleckBrandAuditTests.swift`

**Interfaces:**
- `Info.plist`:

```xml
<key>CFBundleDisplayName</key><string>Fleck</string>
<key>CFBundleExecutable</key><string>Fleck</string>
<key>CFBundleIdentifier</key><string>com.harryjin.fleck</string>
<key>CFBundleName</key><string>Fleck</string>
```

- Artifacts:

```text
.build/Fleck.app/Contents/MacOS/Fleck
.build/Fleck.app/Contents/SharedSupport/fleck-agent
```

- [ ] **Step 1: Write bundle and brand RED tests**

Require canonical plist values, packaged paths, visible “Quit Fleck,” Fleck
privacy descriptions, Fleck local-user activity attribution, and active-brand
audit success.

`Scripts/audit-fleck-brand.sh` scans tracked active files and rejects
case-insensitive `motes`. A matching active-source/test line is allowed only
when that same line contains `legacy`, `compatibility`, or
`motes-to-fleck-v1`, and only in:

```text
Sources/FleckCore/FleckProductMigration.swift
Sources/FleckApp/AgentBridgeInstaller.swift
Sources/FleckApp/AgentCredentialSecurity.swift
Sources/FleckApp/EnhancedModelManager.swift
Sources/FleckAgentBridge/BridgeCredentialStore.swift
Tests/FleckCoreTests/FleckProductMigrationTests.swift
Tests/FleckAppTests/AgentBridgeInstallerTests.swift
Tests/FleckAppTests/AgentProfileStoreTests.swift
Tests/FleckAppTests/AgentTaskHandleCodecTests.swift
Tests/FleckAppTests/EnhancedModelManagerTests.swift
Tests/FleckAgentBridgeTests/BridgeCredentialStoreTests.swift
```

Historical files below `docs/superpowers/specs` and
`docs/superpowers/plans` are excluded before scanning. The audit also rejects
active `MenuBarNotes` target/module names while allowing the exact
`FleckProductPaths.legacyDirectoryName = "MenuBarNotes"` migration declaration
and repository name. Build the forbidden word inside the audit from two shell
fragments (`legacy_brand='mo''tes'`) so the audit does not exempt or report
itself.

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --disable-automatic-resolution --filter FleckBrandAuditTests
Scripts/audit-fleck-brand.sh
```

Expected: failures enumerate each unallowlisted active legacy name.

- [ ] **Step 3: Rename artifacts and copy**

Use `git mv` for the candidate package and build script. Update candidate
package name/product/import, resolver paths, release-size logic, temporary
prefixes, CI products/labels, bundle assembly, launch instructions, memory
profiling default, and validation output.

Replace current customer/developer copy with Fleck. Preserve legacy strings
only where the audit allowlist documents their compatibility purpose.

- [ ] **Step 4: Update packaging**

`Scripts/build-fleck-app.sh` builds `Fleck` and `fleck-agent`, stages
`Fleck.app`, copies the exact canonical executables, and preserves the existing
atomic replacement and permissions behavior.

- [ ] **Step 5: Verify audit and package tests**

Run:

```bash
swift test --disable-automatic-resolution --filter FleckBrandAuditTests
Scripts/audit-fleck-brand.sh
bash -n Scripts/*.sh
git diff --check
```

Expected: all checks pass with no unallowlisted Motes identity.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Packages Scripts Sources Tests .github README.md \
  IMPLEMENTATION_STATUS.md docs
git commit -m "feat: ship Fleck product identity"
```

---

### Task 7: Full Migration and Release Validation

**Files:**
- Verify only: no planned source changes.
- If a gate fails, return to and amend the task that owns that behavior before
  repeating Task 7.

**Interfaces:**
- Consumes every prior task.
- Produces a clean, packaged, launchable `.build/Fleck.app`.

- [ ] **Step 1: Run the ordinary graph**

```bash
swift test --disable-automatic-resolution
swift build -c release --disable-automatic-resolution --product Fleck
swift build -c release --disable-automatic-resolution --product fleck-agent
```

Expected: all tests and both release products pass.

- [ ] **Step 2: Run the repository release gate**

```bash
Scripts/validate-macos.sh
```

Expected: Fleck package/build, bundle ID/executable/privacy, helper, size,
artifact, agent-boundary, candidate-lock, and candidate-rejection checks pass.

- [ ] **Step 3: Run Enhanced-candidate validation**

```bash
Scripts/resolve-enhanced-candidate.sh swift test
Scripts/check-candidate-release-rejected.sh
```

Expected: candidate debug tests pass and candidate release is rejected before
linking.

- [ ] **Step 4: Test a legacy fixture end-to-end**

With an isolated temporary home/Application Support parent:

1. Create a complete legacy Motes workspace and legacy Keychain fakes.
2. Start Fleck migration.
3. Assert canonical Fleck storage and credentials are byte-equivalent.
4. Invoke canonical `fleck --help`.
5. Invoke the legacy absolute `motes --help`.
6. Assert both helpers connect to only `fleck.sock`.
7. Repeat startup and assert no file changed.

Expected: all assertions pass and no legacy data is deleted.

- [ ] **Step 5: Launch the packaged app**

```bash
/usr/bin/open -n .build/Fleck.app
```

Manually verify:

- Fleck appears in the menu bar and app surfaces.
- Left-click opens the notes panel.
- Right-click shows `Quit Fleck`.
- Existing notes, formatting, Trash, settings, dictation history, and agent
  profiles are present.
- First dictation use requests Fleck microphone/Speech permission.
- Settings generates Fleck Codex/Claude/Kimi setup.

- [ ] **Step 6: Final cleanliness and ancestry checks**

```bash
Scripts/audit-fleck-brand.sh
git diff --check
git status --short --branch
```

Expected: no tracked changes remain after the final commit; unrelated
`.superpowers/brainstorm/` stays untracked and untouched.

- [ ] **Step 7: Record the verified final commit**

Run:

```bash
git log -1 --format='%H %s'
```

Record that existing commit in the implementation handoff. Do not create an
empty validation-only commit.
