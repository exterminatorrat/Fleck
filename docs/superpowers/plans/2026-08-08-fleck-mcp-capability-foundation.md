# Fleck MCP Capability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`
> task-by-task. Implementation runs only in user-visible Codex tasks on GPT-5.6
> Luna/Max under primary Sol/High ownership. Do not use hidden subagents or Terra.

**Goal:** Replace global per-note Agent Access with explicit profile-scoped
capability grants while preserving every existing Agent Connector operation,
privacy rule, revision check, retry receipt, activity record, and safe Undo.

**Architecture:** Add pure grant/policy modules in `FleckCore`, a recoverable
capability store and authority seam in `FleckApp`, and one v2 capability-summary
command in `FleckAgentProtocol`. Existing MCP names remain bridge adapters;
`tools/list` is profile-filtered while every call is reauthorized natively.

**Tech Stack:** Swift 6, macOS 14+, SwiftPM, Swift Testing, SwiftUI/AppKit,
Foundation actors, Keychain profile credentials, AF_UNIX IPC, and the pinned MCP
Swift SDK revision `a0ae212ebf6eab5f754c3129608bc5557637e605`.

## Global Constraints

- Start only after PR #16 is merged to `origin/main` with accepted search,
  folders, stable links, and backlinks.
- Implement Phase A only. Context/organization tools, Change Sets, Work Items,
  community registry, and execution broker require separate approved plans.
- Preserve the existing 13 MCP names and 12 v1 canonical commands. Add only the
  internal v2 `getCapabilities` command.
- Unknown, private, and unauthorized notes remain identical `note_not_found`
  results. Revoked, unknown, and wrongly authenticated profiles remain identical
  `permission_revoked` results.
- New profiles start with no tools and no scopes. Existing profiles receive exact
  direct-note compatibility grants for notes with legacy `agentAccess == true`.
- “Current notes only” materializes direct grants. Dynamic future-note folder
  access is explicit, visible, and off by default.
- Agents cannot create or widen grants.
- No arbitrary paths, shell, network listener, settings/sharing changes,
  credentials, Trash, Dictation History, note deletion, iCloud, onboarding, or
  AI/dictation behavior.
- Keep credentials, verifiers, note bodies, and private IDs out of profile JSON,
  snippets, logs, stdout, and errors.
- Add no dependency, polling loop, web view, background daemon, or ordinary
  network access. Keep `FleckCore` free of AppKit and SwiftUI.
- Preserve the 15 MiB release executable target, 75 MB normal idle memory ceiling,
  and zero-idle-polling rule.
- Coordinate with the AI/dictation task before editing `AppState.swift`,
  `FleckApp.swift`, `NotesPanel.swift`, `Package.swift`, or shared validation docs.
- Preserve unrelated and concurrent work. Stop on overlap instead of resolving it
  implicitly.

## Execution and GitHub Gate

After this plan receives explicit approval, primary Sol/High must:

1. Run Sol Advisor's exactness check and confirm user-visible Luna/Max
   implementation plus fresh Sol/High review are available with no Terra route.
2. Inspect and message the AI/dictation task with this phase's shared-file list.
3. Verify PR #16 is merged and green, then fetch and fast-forward a clean local
   `main` to `origin/main` without touching the dirty shared checkout.
4. Create `codex/fleck-mcp-capability-foundation` in an isolated worktree.
5. Add the approved design and this plan as the first docs-only commit.

Each numbered task is one user-visible task titled `Agent - <title>` on
GPT-5.6 Luna/Max. The packet contains objective/success criteria, owned files and
interfaces, work/non-goals, verification/evidence, and authority/handoff. Primary
Sol inspects every changed line and reruns focused checks. A fresh Sol/High
reviewer must return exactly `ship` before the next task. `fix-first` or `rethink`
returns to the same Luna task; primary Sol does not silently repair code.

## File Map

**Create:**

- `Sources/FleckCore/AgentCapabilityModels.swift`: IDs, authority lattice, grants,
  scopes, summaries, and authorization snapshots.
- `Sources/FleckCore/AgentCapabilityPolicy.swift`: pure scope expansion and
  authority evaluation.
- `Sources/FleckApp/AgentCapabilityStore.swift`: versioned migration, atomic
  current/previous persistence, optimistic grant revisions.
- `Sources/FleckApp/AgentCapabilityAuthority.swift`: native authority seam.
- `Sources/FleckAgentBridge/AgentWorkspaceClient.swift`: shared credential-backed
  IPC client for discovery and calls.
- `Sources/FleckApp/AgentCapabilityEditorView.swift`: profile editor.
- `Sources/FleckApp/AgentNoteAccessEditorView.swift`: note-focused access editor.
- Matching focused tests in the existing four test targets.

**Modify narrowly:**

- `AgentWorkspaceModels.swift`, `AgentWireProtocol.swift`, `AgentIPCServer.swift`,
  `AgentIPCClient.swift`, `AgentCommandService.swift`, `FleckMCPToolRegistry.swift`,
  `FleckMCPServer.swift`, `AppState.swift`, `FleckApp.swift`,
  `AgentSettingsView.swift`, `AgentActivityView.swift`, `NotesPanel.swift`,
  `Scripts/audit-agent-boundary.sh`, and the four release docs.

## Frozen Phase A Interfaces

```swift
public enum AgentCapability: String, Codable, CaseIterable, Sendable {
  case listNotes = "notes.list"
  case readNotes = "notes.read"
  case writeNotes = "notes.write"
  case undoChanges = "changes.undo"
}

public enum AgentAuthority: String, Codable, CaseIterable, Sendable {
  case read, propose, write
  public func allows(_ required: AgentAuthority) -> Bool
}

public enum AgentGrantScope: Codable, Equatable, Sendable {
  case note(noteID: UUID)
  case folderIncludingFutureNotes(folderID: UUID)
}

public struct AgentResourceGrant: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let scope: AgentGrantScope
  public let authority: AgentAuthority
}

public struct AgentProfileCapabilities: Codable, Equatable, Sendable {
  public let profileID: UUID
  public let grantRevision: UInt64
  public let allowedCapabilities: Set<AgentCapability>
  public let grants: [AgentResourceGrant]
}

public struct AgentCapabilitySummary: Codable, Equatable, Sendable {
  public let grantRevision: UInt64
  public let availableCapabilities: Set<AgentCapability>
}

public struct AgentAuthorizationSnapshot: Equatable, Sendable {
  public let profileID: UUID
  public let grantRevision: UInt64
  public let availableCapabilities: Set<AgentCapability>
  public let readableNoteIDs: Set<UUID>
  public let proposableNoteIDs: Set<UUID>
  public let writableNoteIDs: Set<UUID>
}

public enum AgentCapabilityPolicy {
  public static func authorizationSnapshot(
    for profile: AgentProfileCapabilities,
    workspace: Workspace
  ) -> AgentAuthorizationSnapshot
}
```

Every public value type has an explicit public initializer. Capability sets use
custom Codable implementations that encode capabilities sorted by raw value and
decode them into sets. Persisted grants are normalized by scope kind, target UUID,
authority, and grant UUID before encoding, so equivalent states produce identical
bytes.

---

### Task 1: Capability Domain and Pure Policy

**Title:** `Agent - MCP Capability Domain`

**Files:**

- Create: `Sources/FleckCore/AgentCapabilityModels.swift`
- Create: `Sources/FleckCore/AgentCapabilityPolicy.swift`
- Create: `Tests/FleckCoreTests/AgentCapabilityPolicyTests.swift`

**Produces:** All frozen `FleckCore` interfaces above.

- [ ] Write red tests for the authority lattice, stable raw values, Codable round
  trips, direct-note access across folder moves, dynamic folder membership,
  overlapping-grant union, folder deletion, read/propose/write sets, empty scope,
  and deterministic results.

```swift
@Test func AgentAuthorityIsCumulative() {
  #expect(AgentAuthority.read.allows(.read))
  #expect(!AgentAuthority.read.allows(.propose))
  #expect(AgentAuthority.propose.allows(.read))
  #expect(!AgentAuthority.propose.allows(.write))
  #expect(AgentAuthority.write.allows(.write))
}

@Test func DynamicFolderGrantTracksMembership() throws {
  let folder = try Folder(name: "Projects")
  let inside = Note(folderID: folder.id)
  let outside = Note()
  let profile = AgentProfileCapabilities(
    profileID: UUID(), grantRevision: 1,
    allowedCapabilities: [.listNotes, .readNotes, .writeNotes],
    grants: [.init(
      scope: .folderIncludingFutureNotes(folderID: folder.id),
      authority: .write
    )]
  )
  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace(notes: [inside, outside], folders: [folder])
  )
  #expect(result.readableNoteIDs == [inside.id])
  #expect(result.writableNoteIDs == [inside.id])
}
```

- [ ] Run and record the expected compile failure:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityPolicyTests
```

- [ ] Implement the exact models and one pure policy pass. Union overlapping
  grants; never infer access from `Note.agentAccess`. A capability is available
  only when it is allowed and at least one effective scope has sufficient
  authority. Add deterministic custom Codable tests for capability sets and grant
  normalization. Do not add future phase types.

- [ ] Run focused and core suites:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityPolicyTests
swift test --disable-automatic-resolution --no-parallel \
  --filter FleckCoreTests
```

- [ ] Commit:

```bash
git add Sources/FleckCore/AgentCapabilityModels.swift \
  Sources/FleckCore/AgentCapabilityPolicy.swift \
  Tests/FleckCoreTests/AgentCapabilityPolicyTests.swift
git commit -m "feat: define agent capability policy"
```

- [ ] Primary Sol reruns both commands and inspects all public types. Fresh
  Sol/High verdict must be exactly `ship`.

---

### Task 2: Recoverable Capability Store and Legacy Migration

**Title:** `Agent - Capability Store Migration`

**Files:**

- Create: `Sources/FleckApp/AgentCapabilityStore.swift`
- Create: `Tests/FleckAppTests/AgentCapabilityStoreTests.swift`

**Produces:**

```swift
struct AgentCapabilityState: Equatable, Sendable {
  var profiles: [UUID: AgentProfileCapabilities]
  var unassignedLegacyNoteIDs: Set<UUID>
}

actor AgentCapabilityStore {
  func loadOrMigrate(
    activeProfileIDs: [UUID], workspace: Workspace
  ) throws -> AgentCapabilityState
  func currentState() throws -> AgentCapabilityState
  func registerEmptyProfile(_ profileID: UUID) throws -> AgentCapabilityState
  func replaceProfile(
    _ profile: AgentProfileCapabilities,
    expectedGrantRevision: UInt64
  ) throws -> AgentCapabilityState
}
```

- [ ] Write red migration tests. Two active profiles each receive a direct write
  grant for every legacy shared note and the four Phase A capabilities. Private
  notes receive no grant. With no active profiles, shared IDs become unassigned;
  registering a future profile leaves them unassigned and creates an empty profile.

```swift
@Test func NoProfileLegacySharesNeverFlowToANewProfile() async throws {
  let fixture = try CapabilityStoreFixture()
  defer { fixture.remove() }
  let shared = Note(agentAccess: true)
  let migrated = try await fixture.store.loadOrMigrate(
    activeProfileIDs: [], workspace: Workspace(notes: [shared])
  )
  #expect(migrated.unassignedLegacyNoteIDs == [shared.id])
  let created = try await fixture.store.registerEmptyProfile(UUID())
  #expect(created.profiles.values.first?.grants == [])
  #expect(created.unassignedLegacyNoteIDs == [shared.id])
}
```

- [ ] Run and record the compile failure:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityStoreTests
```

- [ ] Implement schema version 2 at
  `AgentIntegrations/capabilities.json` with
  `capabilities.previous.json`. Load valid current; recover valid previous and
  rewrite current; create migration only when neither file exists; fail closed
  with content-free `internal_save_failure` when files exist but neither decodes.
  Encode sorted pretty JSON. Never modify `Workspace` or clear legacy flags.

- [ ] Add red tests for stale revision/no write, profile ID mismatch, one-step
  revision increment, duplicate registration, deterministic bytes, current/previous
  recovery, unknown schema, malformed both, and absence of credential/verifier/body
  text. Implement atomic previous-then-current replacement to pass them.

- [ ] Run focused store and existing profile suites:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityStoreTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentProfileStoreTests
```

- [ ] Commit:

```bash
git add Sources/FleckApp/AgentCapabilityStore.swift \
  Tests/FleckAppTests/AgentCapabilityStoreTests.swift
git commit -m "feat: persist agent capability grants"
```

- [ ] Primary Sol inspects migration/recovery and fixture bytes. Fresh Sol/High
  verdict must be exactly `ship`.

---

### Task 3: Internal Agent Wire Protocol v2

**Title:** `Agent - Agent Wire V2`

**Files:**

- Modify: `Sources/FleckCore/AgentWorkspaceModels.swift`
- Modify: `Sources/FleckAgentProtocol/AgentWireProtocol.swift`
- Modify: `Sources/FleckApp/AgentIPCServer.swift`
- Modify: `Sources/FleckAgentBridge/AgentIPCClient.swift`
- Modify: `Tests/FleckAgentProtocolTests/AgentWireProtocolTests.swift`
- Modify: `Tests/FleckAppTests/AgentIPCServerTests.swift`
- Modify: `Tests/FleckAgentBridgeTests/AgentIPCClientTests.swift`

**Produces:** v1/v2 compatibility, `.getCapabilities`,
`.capabilities(summary:)`, and `protocol_version_unsupported`.

- [ ] Write red tests proving versions 1 and 2 round-trip; v1 accepts every
  original command but rejects `getCapabilities`; v2 accepts both; success and
  failure responses echo an accepted request version; unsupported versions and
  v1-with-v2-command never invoke the service.

```swift
@Test(arguments: [1, 2])
func AgentWireRoundTripsSupportedVersions(_ version: Int) throws {
  let request = AgentWireRequest(
    protocolVersion: version,
    requestID: UUID(), profileID: UUID(),
    credentialBase64: Data(repeating: 7, count: 32).base64EncodedString(),
    command: version == 1 ? .listSharedNotes : .getCapabilities
  )
  var frame = try AgentWireFraming.encode(request)
  #expect(
    try AgentWireFraming.decodeFrame(AgentWireRequest.self, from: &frame)
      == request
  )
}
```

- [ ] Run and record red evidence:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentWireProtocolTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentIPCServerTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentIPCClientTests
```

- [ ] Add exact model cases without changing any existing case/raw value:

```swift
case getCapabilities // AgentWorkspaceCommand
case capabilities(summary: AgentCapabilitySummary) // response
case capabilityDenied = "capability_denied"
case protocolVersionUnsupported = "protocol_version_unsupported"
```

Add `AgentWorkspaceCommand.isSupported(wireVersion:)`: original 12 commands are
valid on 1 and 2; `getCapabilities` is valid only on 2.

- [ ] Set `currentProtocolVersion = 2` and
  `supportedProtocolVersions = [1, 2]`. Change response factories to require
  `protocolVersion`. The server checks version and command compatibility before
  credential decoding/service execution. Accepted responses echo the request;
  unsupported requests return current version plus content-free upgrade guidance.
  The client compares the response with `request.protocolVersion`.

- [ ] Update every exhaustive switch and response factory call. Preserve v1 JSON
  case names and payloads. Run the three focused suites until all pass.

- [ ] Commit:

```bash
git add Sources/FleckCore/AgentWorkspaceModels.swift \
  Sources/FleckAgentProtocol/AgentWireProtocol.swift \
  Sources/FleckApp/AgentIPCServer.swift \
  Sources/FleckAgentBridge/AgentIPCClient.swift \
  Tests/FleckAgentProtocolTests/AgentWireProtocolTests.swift \
  Tests/FleckAppTests/AgentIPCServerTests.swift \
  Tests/FleckAgentBridgeTests/AgentIPCClientTests.swift
git commit -m "feat: negotiate agent wire protocol v2"
```

- [ ] Primary Sol compares v1 fixtures before/after and reruns all three suites.
  Fresh Sol/High verdict must be exactly `ship`.

---

### Task 4: Native Capability Authority and Existing Commands

**Title:** `Agent - Capability Authority Integration`

**Files:**

- Create: `Sources/FleckApp/AgentCapabilityAuthority.swift`
- Create: `Tests/FleckAppTests/AgentCapabilityAuthorityTests.swift`
- Modify: `Sources/FleckApp/AgentCommandService.swift`
- Modify: `Tests/FleckAppTests/AgentCommandServiceTests.swift`
- Modify: `Tests/FleckAppTests/AgentPrivacyBoundaryTests.swift`

**Produces:**

```swift
protocol AgentCapabilityAuthorizing: Sendable {
  func snapshot(
    profileID: UUID, workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot
  func assertCurrent(
    profileID: UUID, grantRevision: UInt64
  ) async throws
}
```

- [ ] Write authority tests for policy delegation, unknown profile, current
  revision, and revision replacement. A stale grant revision returns content-free
  `capability_denied`.

- [ ] Write red production-path tests:

```swift
@Test @MainActor func ReadOnlyProfileCannotInvokeCachedWriteTool() async throws
@Test @MainActor func UnauthorizedAndUnknownReadsRemainIdentical() async throws
@Test @MainActor func ListAndActivityContainOnlyAuthorizedNotes() async throws
@Test @MainActor func GrantChangeBeforeCommitRejectsWithoutMutation() async throws
@Test @MainActor func MigratedWriteProfilePreservesRetryAndUndo() async throws
@Test @MainActor func CapabilitySummaryContainsNoResourceIdentifiers() async throws
```

The race test pauses after draft creation, replaces the grant, resumes, and
asserts zero commits, activity records, and feedback.

- [ ] Run and record red evidence:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityAuthorityTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCommandServiceTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentPrivacyBoundaryTests
```

- [ ] Implement one closed canonical requirement mapping:

| Commands | Capability | Authority |
| --- | --- | --- |
| `listSharedNotes` | `listNotes` | read |
| `readNote`, `listTasks`, `listActivity` | `readNotes` | read |
| append/insert/replace and all task mutations | `writeNotes` | write |
| `undoChange` | `undoChanges` | write |
| `getCapabilities` | authenticated profile only | none |

For target commands, absent capability yields `capability_denied`; capability
allowed elsewhere but target outside scope yields `note_not_found`. Undo resolves
only caller-owned activity, then checks write scope without exposing other actors.

- [ ] Inject the authority into `AgentCommandService`. After credential auth and
  reconciliation, obtain one immutable snapshot. Replace every `.agentAccess`
  authorization/list filter with snapshot sets. Return only grant revision and
  available capability IDs for `getCapabilities`. Recheck grant revision before
  returning reads and immediately before commit; make the commit helper async.
  Check current authorization before returning an idempotent prior receipt.

- [ ] Run the three focused suites until all pass. Search the production command
  path for remaining legacy authorization checks:

```bash
rg -n 'agentAccess' Sources/FleckApp/AgentCommandService.swift
```

Expected: no matches.

- [ ] Commit:

```bash
git add Sources/FleckApp/AgentCapabilityAuthority.swift \
  Sources/FleckApp/AgentCommandService.swift \
  Tests/FleckAppTests/AgentCapabilityAuthorityTests.swift \
  Tests/FleckAppTests/AgentCommandServiceTests.swift \
  Tests/FleckAppTests/AgentPrivacyBoundaryTests.swift
git commit -m "feat: enforce profile capability grants"
```

- [ ] Primary Sol inspects every requirement and final revision check, then reruns
  all focused suites. Fresh Sol/High verdict must be exactly `ship`.

---

### Task 5: Profile-Filtered MCP Tool Discovery

**Title:** `Agent - Profile-Filtered MCP Tools`

**Files:**

- Create: `Sources/FleckAgentBridge/AgentWorkspaceClient.swift`
- Create: `Tests/FleckAgentBridgeTests/AgentWorkspaceClientTests.swift`
- Modify: `Sources/FleckAgentBridge/FleckMCPToolRegistry.swift`
- Modify: `Sources/FleckAgentBridge/FleckMCPServer.swift`
- Modify: `Tests/FleckAgentBridgeTests/FleckMCPToolRegistryTests.swift`
- Modify: `Tests/FleckAgentBridgeTests/FleckMCPServerTests.swift`
- Modify: `Scripts/audit-agent-boundary.sh`

**Produces:** dynamic profile-filtered `tools/list` and a shared typed bridge client.

- [ ] Write exact filtering tests:

```swift
@Test func FullCapabilitiesExposeExactReviewedOrder() {
  #expect(FleckMCPToolRegistry.tools(allowedCapabilities: [
    .listNotes, .readNotes, .writeNotes, .undoChanges,
  ]).map(\.name) == [
    "list_shared_notes", "read_note", "append_text", "insert_text",
    "replace_lines", "delete_lines", "list_tasks", "add_task",
    "rename_task", "set_task_state", "remove_task",
    "list_agent_activity", "undo_agent_change",
  ])
}

@Test func ReadOnlyCapabilitiesExposeNoMutationTools() {
  #expect(FleckMCPToolRegistry.tools(allowedCapabilities: [
    .listNotes, .readNotes,
  ]).map(\.name) == [
    "list_shared_notes", "read_note", "list_tasks", "list_agent_activity",
  ])
}
```

Also assert empty capabilities produce no tools and preserve all full-set schemas
and canonical mappings.

- [ ] Write bridge-client tests proving `capabilities()` loads the profile
  credential, sends v2 `.getCapabilities`, validates the response case, and
  returns the summary. Test two `tools/list` calls against a changing injected
  summary. Keep MCP capabilities tools-only with `listChanged: false`.

- [ ] Run red evidence:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter FleckAgentBridgeTests
Scripts/audit-agent-boundary.sh
```

- [ ] Create:

```swift
struct AgentWorkspaceClient {
  typealias CredentialLoader = @Sendable (UUID) throws -> String
  typealias Sender = @Sendable (AgentWireRequest) throws -> AgentWorkspaceResponse
  let profileID: UUID
  let loadCredential: CredentialLoader
  let send: Sender
  func capabilities() throws -> AgentCapabilitySummary
  func execute(_ command: AgentWorkspaceCommand) throws -> AgentWorkspaceResponse
}
```

Production defaults use `BridgeCredentialStore` and `AgentIPCClient`. Both methods
send v2 requests. Do not cache authorization in the helper.

- [ ] Replace the bare tool array with ordered registrations containing exactly
  one `AgentCapability` and the unchanged `Tool`. Map list to `listNotes`,
  read/tasks/activity to `readNotes`, all text/task mutations and delete alias to
  `writeNotes`, and Undo to `undoChanges`. Filter registrations by the summary.

- [ ] Change `FleckMCPServer.makeServer` to accept an async `listTools` closure
  plus `callTool`. Invoke `listTools` on every request. `run(profileID:)` creates
  one `AgentWorkspaceClient` used by both closures. Native authorization remains
  final for cached calls. Do not claim list-change notifications.

- [ ] Update the audit to retain exact 13-name parsing and prove every registration
  has a capability, `ListTools` is dynamic, only `ListTools`/`CallTool` handlers
  exist, and no storage/network/stdout/credential boundary broadened.

- [ ] Run the bridge suite and audit until both pass. Commit:

```bash
git add Sources/FleckAgentBridge/AgentWorkspaceClient.swift \
  Sources/FleckAgentBridge/FleckMCPToolRegistry.swift \
  Sources/FleckAgentBridge/FleckMCPServer.swift \
  Tests/FleckAgentBridgeTests/AgentWorkspaceClientTests.swift \
  Tests/FleckAgentBridgeTests/FleckMCPToolRegistryTests.swift \
  Tests/FleckAgentBridgeTests/FleckMCPServerTests.swift \
  Scripts/audit-agent-boundary.sh
git commit -m "feat: filter MCP tools by profile capability"
```

- [ ] Primary Sol compares every full-set schema/mapping and tests a stale cached
  write denial. Fresh Sol/High verdict must be exactly `ship`.

---

### Task 6: App-State Lifecycle and Production Wiring

**Title:** `Agent - Capability App State`

**Files:**

- Modify: `Sources/FleckApp/AppState.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Modify: `Tests/FleckAppTests/AppStateTests.swift`
- Modify: `Tests/FleckAppTests/AgentProfileStoreTests.swift`
- Modify: `Tests/FleckAppTests/AgentCommandServiceTests.swift`

**Produces:** one shared production capability store/authority, published
capability state, empty new-profile registration, optimistic profile updates, and
derived note-sharing helpers.

- [ ] Write red production wiring tests asserting `FleckApp.swift` constructs one
  `AgentCapabilityStore` and one `AgentCapabilityAuthority` and passes the same
  instances to AppState and the command service.

- [ ] Write startup tests: migration occurs after workspace and active profiles
  load; malformed current+previous capability files leave notes usable and initial
  load complete but set agent workspace unavailable with content-free recovery
  copy.

- [ ] Write profile lifecycle tests: successful profile creation registers empty
  capabilities; helper provisioning/capability registration failure revokes and
  cleans up; unassigned shares remain unassigned; optimistic replacement publishes
  the new revision; revocation removes effective access immediately; local user
  Undo still works without a profile grant.

- [ ] Run red evidence:

```bash
swift test --disable-automatic-resolution --no-parallel --filter AppStateTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentProfileStoreTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCommandServiceTests
```

- [ ] Inject and retain exact state:

```swift
let agentCapabilityStore: AgentCapabilityStore
let agentCapabilityAuthority: any AgentCapabilityAuthorizing
@Published private(set) var agentCapabilityState = AgentCapabilityState(
  profiles: [:], unassignedLegacyNoteIDs: []
)
```

After `load()` and `refreshAgentProfiles()`, call `loadOrMigrate` and only then
enable the agent workspace. Capability failure never replaces/blocks notes.

- [ ] Add:

```swift
func updateAgentCapabilities(
  _ replacement: AgentProfileCapabilities,
  expectedGrantRevision: UInt64
) async
func capabilityProfile(_ profileID: UUID) -> AgentProfileCapabilities?
func profilesWithReadAccess(to noteID: UUID) -> [AgentIntegrationProfile]
func isSharedWithAnyActiveProfile(_ noteID: UUID) -> Bool
```

All helpers evaluate pure policy against current workspace and active profiles;
none reads legacy `agentAccess` as effective authorization.

- [ ] After helper provisioning, register an empty profile. On capability-store
  failure, revoke profile and remove helper credential. Revocation filters inactive
  profiles immediately. Retained grants cannot authorize without profile auth.
  Local Undo uses the same authority instance but remains local-user authorized.

- [ ] In `FleckApp.swift`, construct one store at
  `AgentIntegrations/capabilities.json` plus
  `capabilities.previous.json`, construct one authority, and share them. Do not
  construct either in views, callbacks, or local Undo.

- [ ] Run all three suites until green. Commit:

```bash
git add Sources/FleckApp/AppState.swift Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/AppStateTests.swift \
  Tests/FleckAppTests/AgentProfileStoreTests.swift \
  Tests/FleckAppTests/AgentCommandServiceTests.swift
git commit -m "feat: wire capability profiles into app state"
```

- [ ] Primary Sol rechecks AI/dictation coordination, startup ordering, and
  failure isolation. Fresh Sol/High verdict must be exactly `ship`.

---

### Task 7: Capability Profile and Note Access UX

**Title:** `Agent - Capability Profile UX`

**Files:**

- Create: `Sources/FleckApp/AgentCapabilityEditorView.swift`
- Create: `Sources/FleckApp/AgentNoteAccessEditorView.swift`
- Create: `Tests/FleckAppTests/AgentCapabilityPresentationTests.swift`
- Modify: `Sources/FleckApp/AgentCapabilityStore.swift`
- Modify: `Sources/FleckApp/AppState.swift`
- Modify: `Sources/FleckApp/AgentSettingsView.swift`
- Modify: `Sources/FleckApp/AgentActivityView.swift`
- Modify: `Sources/FleckApp/NotesPanel.swift`
- Modify: `Tests/FleckAppTests/AgentCapabilityStoreTests.swift`
- Modify: `Tests/FleckAppTests/AgentPresentationTests.swift`

**Produces:** explicit Capability Profiles, note-focused access management,
derived sharing badges, future-note confirmation, and unassigned-share recovery.

- [ ] Recheck shared-file ownership before editing. If AI/dictation or another
  active task owns any listed UI file, stop and schedule a separate integration
  packet after that owner lands.

- [ ] Write pure presentation tests for exact labels and decisions:

```swift
@Test func FutureFolderAccessRequiresExplicitConfirmation() {
  #expect(AgentCapabilityPresentation.requiresBroadGrantConfirmation(
    scope: .folderIncludingFutureNotes(folderID: UUID())
  ))
}

@Test func LegacyFlagAloneDoesNotProduceASharedBadge() {
  let note = Note(agentAccess: true)
  #expect(!AgentCapabilityPresentation.isShared(
    noteID: note.id, activeProfiles: [], workspace: Workspace(notes: [note])
  ))
}
```

Cover read/write summaries, zero scope, revoked profiles, folder deletion,
unassigned legacy shares, VoiceOver labels, and exact wording:

```text
No tools or notes granted
Read
Read + Write
Includes future notes in “<folder name>”
This profile will automatically gain access to notes moved into this folder.
Unassigned legacy shares
Manage Agent Access…
```

- [ ] Run red evidence:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityPresentationTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentPresentationTests
```

- [ ] Put formatting/decisions in a pure `AgentCapabilityPresentation` model.
  Do not offer Propose in Phase A because proposal tools do not exist.

- [ ] Build `AgentCapabilityEditorView` with three sections:

1. Tools: list/read, edit/tasks, and Undo mapped to the four Phase A IDs.
2. Direct notes: Off, Read, or Write.
3. Folders: Off, Current notes only, or Including future notes. Current-only
   materializes direct grants in the draft. Future mode creates one dynamic grant
   and requires confirmation.

Save uses the displayed expected revision. Conflict retains the draft and shows:
“This capability profile changed. Reload it before saving.” Unassigned legacy
shares are assigned only by explicit user action and removed atomically from the
unassigned set.

- [ ] Build `AgentNoteAccessEditorView` listing active profiles with Off, Read, or
  Write for one note. Saving multiple profile changes is all-or-nothing: add a
  batch store replacement that validates every revision before one atomic write,
  with red atomicity tests in `AgentCapabilityStoreTests.swift`. Add a separate
  atomic store operation for assigning selected unassigned legacy note IDs to one
  profile; it validates the profile revision, writes direct grants, and removes
  only the selected IDs in the same document replacement.

- [ ] In `NotesPanel.swift`, replace both “Allow Agent Access” toggles with
  “Manage Agent Access…” buttons, present the note editor, derive badges from
  `isSharedWithAnyActiveProfile`, and remove the global first-share confirmation.
  Leave editor/search/folder/backlink/dictation/tab behavior untouched.

- [ ] In `AppState.swift`, remove the now-unreferenced global
  `setSelectedAgentAccess`, `setAgentAccess`, and `confirmFirstAgentShare` actions
  plus their first-share `UserDefaults` presentation state. Keep
  `Note.agentAccess` decoding and legacy migration input intact for the documented
  compatibility window.

- [ ] In `AgentSettingsView`, show profile summaries and open the profile editor;
  retain setup snippets, Copy, Revoke, install, activity, and same-user warning.
  In `AgentActivityView`, sharing presentation uses effective active-profile
  grants instead of legacy flags. The local activity view continues to show local
  workspace history and local safe Undo after unsharing; bridge activity filtering
  remains solely in `AgentCommandService`.

- [ ] Run presentation and privacy suites:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityPresentationTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentPresentationTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentPrivacyBoundaryTests
```

- [ ] Commit:

```bash
git add Sources/FleckApp/AgentCapabilityEditorView.swift \
  Sources/FleckApp/AgentNoteAccessEditorView.swift \
  Sources/FleckApp/AgentCapabilityStore.swift Sources/FleckApp/AppState.swift \
  Sources/FleckApp/AgentSettingsView.swift \
  Sources/FleckApp/AgentActivityView.swift Sources/FleckApp/NotesPanel.swift \
  Tests/FleckAppTests/AgentCapabilityStoreTests.swift \
  Tests/FleckAppTests/AgentCapabilityPresentationTests.swift \
  Tests/FleckAppTests/AgentPresentationTests.swift
git commit -m "feat: add capability profile controls"
```

- [ ] Primary Sol inspects every shared-file line and verifies no actionable
  global toggle remains. Fresh Sol/High verdict must be exactly `ship`.

---

### Task 8: Documentation, Full Validation, Packaging, and PR

**Title:** `Agent - Capability Foundation Release Gate`

**Files:**

- Modify: `README.md`
- Modify: `ARCHITECTURE.md`
- Modify: `IMPLEMENTATION_STATUS.md`
- Modify: `TESTING.md`
- Modify: `Scripts/audit-agent-boundary.sh` only for a narrow correction to the
  accepted Task 5 production path
- Test: all existing and new targets

- [ ] Add final static privacy assertions before docs:

- command service has no `agentAccess` authorization;
- helper has no direct storage/network/stdout/credential broadening;
- exactly 13 tools remain and every registration declares one capability;
- capability JSON has no credential/verifier/token/body/RTF bytes;
- `NotesPanel` has no “Allow Agent Access” toggle.

- [ ] Run privacy tests and audit. Correct the owning production task instead of
  weakening an assertion:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentPrivacyBoundaryTests
Scripts/audit-agent-boundary.sh
```

- [ ] Update docs with profile-scoped tools/authority/scopes, exact migration,
  unassigned shares, wire v1 compatibility, v2 discovery, static 13-tool Phase A
  surface, and native enforcement. Explicitly state that context tools, Change
  Sets, Work Items, add-ons, broker, iCloud, onboarding, and AI/dictation changes
  are not implemented. Do not claim `tools/list_changed` or sandboxed add-ons.

- [ ] Run all focused new suites:

```bash
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityPolicyTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityStoreTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityAuthorityTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentCapabilityPresentationTests
swift test --disable-automatic-resolution --no-parallel \
  --filter AgentWireProtocolTests
swift test --disable-automatic-resolution --no-parallel \
  --filter FleckAgentBridgeTests
```

- [ ] Run the full locked automated gate once and preserve terminal output:

```bash
swift test --disable-automatic-resolution --no-parallel
swift build -c release --product Fleck
swift build -c release --product fleck-agent
Scripts/audit-agent-boundary.sh
Scripts/check-release-size.sh .build/release/Fleck
Scripts/validate-macos.sh
git diff --check
```

Every command must exit 0. Record exact test counts, executable sizes, commit,
macOS, Xcode, and Swift versions.

- [ ] Build and inspect the packaged app:

```bash
Scripts/build-fleck-app.sh
codesign --verify --deep --strict .build/Fleck.app
/usr/bin/open -n .build/Fleck.app
```

Using temporary notes/profiles, record migrated 13-tool access, empty new profile,
four-tool read-only discovery, cached write denial after reduction, direct-note
folder move, dynamic folder gain/loss, inheritance confirmation, unassigned share
assignment, revision conflict, idempotent retry, activity/Undo, idle/in-flight
revocation, VoiceOver, Full Keyboard Access, Reduce Motion, multiple windows,
sleep/wake, and five-minute idle CPU/stdout. Sanitize evidence and remove temporary
profiles/configuration. Unrecorded live Keychain, client, accessibility, signing,
notarization, and distribution gates remain pending.

- [ ] Commit docs:

```bash
git add README.md ARCHITECTURE.md IMPLEMENTATION_STATUS.md TESTING.md
git commit -m "docs: document MCP capability foundation"
```

- [ ] Primary Sol reviews the whole branch from synchronized `origin/main`, every
  persisted field/error/string, and all evidence. Defects return to the owning
  Luna task. A fresh final Sol/High reviewer receives spec, plan, base/head, diff,
  command outputs, packaged evidence, pending gates, and coordination notes. The
  verdict must be exactly `ship`.

- [ ] Only after user-approved GitHub-write authority, primary verification, and
  `ship`, push and open a focused PR:

```bash
git push -u origin codex/fleck-mcp-capability-foundation
gh pr create \
  --base main \
  --head codex/fleck-mcp-capability-foundation \
  --title "Add MCP capability profiles and authorization" \
  --body-file /absolute/path/to/sanitized-pr-body.md
```

The PR body states exact Phase A behavior, migration, compatibility, evidence,
pending gates, exclusions, and final verdict. Require green CI. Do not merge,
retarget, close, or modify settings without separate explicit user authorization.

## Commit Sequence

1. Approved design and plan docs.
2. `feat: define agent capability policy`
3. `feat: persist agent capability grants`
4. `feat: negotiate agent wire protocol v2`
5. `feat: enforce profile capability grants`
6. `feat: filter MCP tools by profile capability`
7. `feat: wire capability profiles into app state`
8. `feat: add capability profile controls`
9. `docs: document MCP capability foundation`

Do not squash during implementation. Merge strategy is a separate user decision.

## Stop Conditions

Stop and return to primary design/coordination if:

- PR #16 is not merged or materially differs from the approved contract.
- Sol Advisor cannot confirm Luna/Max implementation plus fresh Sol/High review
  without Terra fallback.
- an active task owns a shared file or an unexpected concurrent edit appears;
- `FleckCore` needs AppKit, SwiftUI, Keychain, MCP, or filesystem behavior;
- a query/mutation inspects a note outside the authorization snapshot;
- authorization is duplicated outside the authority and canonical mapping;
- a new profile receives a legacy note without explicit assignment;
- dynamic folder inheritance becomes default or survives folder deletion as root
  access;
- grant reduction can return a stale receipt/body or commit a mutation;
- v1 helpers lose their original safe command subset;
- full capability discovery changes an existing schema/mapping;
- capability corruption blocks notes or falls back broad;
- sensitive bytes enter persistence, output, errors, or logs;
- implementation needs excluded product scope or a new dependency/runtime;
- a test is green only by weakening privacy, revision, idempotency, persistence,
  activity, or Undo assertions;
- packaged evidence is missing for a completeness claim; or
- a fresh reviewer returns `rethink`.

## Completion Criteria

Phase A completes only when migration is exact, new profiles are empty, grants are
explicit/editable, every existing command crosses one native authority seam, v1
and v2 pass, full-set schemas remain exact, grant changes fail closed before read
return/write commit, all automated/package evidence is recorded, primary Sol has
inspected every line, fresh Sol/High returns exactly `ship`, the focused PR is
green and truthful, and no merge occurs without separate authorization.

After Phase A is accepted, write and obtain approval for the Phase B context and
organization plan against Phase A's actual merged interfaces.
