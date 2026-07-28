# Motes Agent Workspace Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let authorized local AI agents read and safely edit only explicitly shared Motes notes through a bundled CLI and MCP server, with revisions, attribution, 30-day activity, and conservative Undo.

**Architecture:** Motes remains the sole workspace writer. A main-actor `AgentCommandService` applies revision-checked commands to the in-memory workspace, persists the workspace and an activity transaction before acknowledging success, and publishes the resulting state to every Motes scene. A separately built `motes-agent` helper exposes CLI and stdio MCP modes, retrieves its profile credential from Keychain, and sends length-prefixed Codable requests over a same-user Unix-domain socket to the running Motes app.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, Testing, Security/Keychain, CryptoKit, Darwin Unix sockets, JSON/Codable, official MCP Swift SDK `0.12.1`.

## Global Constraints

- Execute this plan only after the reviewed Clean Dictation branch is merged into the implementation base.
- Keep `platforms: [.macOS(.v14)]`.
- Preserve `Application Support/MenuBarNotes`; do not strand existing notes.
- `Note.agentAccess` defaults to `false`; private notes must not be discoverable by identifier probing.
- Unknown and unshared note identifiers both return `note_not_found`; never expose which private UUIDs exist.
- All human and agent content mutations use one persisted note revision.
- Motes is the sole writer. The helper must never edit Markdown, RTF, manifests, activity, or preferences directly.
- Use private same-user Unix-domain IPC. Do not open TCP, HTTP, SSE, or another remotely reachable listener.
- Agents cannot share notes, delete notes, read Trash or Dictation History, change settings, access arbitrary files, or execute shell commands through Motes.
- Every write requires an expected revision and unique operation ID.
- Retain visible Agent Activity for 30 days. Retain minimal idempotency tombstones through the original 30-day expiry even after visible activity is cleared.
- One mutation may add or replace at most 65,536 bytes of UTF-8 text.
- One wire response may contain at most 1,048,576 bytes.
- Use one-based inclusive line numbers in CLI and MCP inputs.
- Preserve readable checklist markers and do not add hidden task IDs to Markdown.
- Task handles are opaque, authenticated, and valid only for the note revision that produced them.
- Credentials and the task-handle signing key live in macOS Keychain, not preferences or command arguments.
- Pin the official MCP Swift SDK exactly to tag `0.12.1`, commit `a0ae212ebf6eab5f754c3129608bc5557637e605`.
- Verify the SDK license file is 12,227 bytes with SHA-256 `0382b0057770ca05e9c350a50aa3b1c1fea84da0bc81d723bf00b9aa841be58a`.
- The helper uses MCP stdio only and writes no logs to stdout.
- Respect VoiceOver and Reduce Motion. Agent status must never be communicated only by color.
- Stage and commit only each task's named files.

## Preflight Gate

Run this gate before Task 0:

```bash
git status --short --branch
git merge-base --is-ancestor 2b90134 HEAD
test -f Sources/MenuBarNotesApp/NoteTextAppender.swift
test -f Sources/MenuBarNotesApp/DictationCoordinator.swift
test -f Sources/MenuBarNotesApp/DictationHistoryView.swift
rg -n "DictationCoordinator\\(" Sources/MenuBarNotesApp/MenuBarNotesApp.swift
rg -n "DictationHistoryView\\(" Sources/MenuBarNotesApp
swift test
```

Expected:

- The Agent Workspace plan commit is reachable.
- Clean Dictation's editor append, coordinator, AppState saving, settings, and history UI are wired into the application runtime, not merely present as isolated types.
- The working tree is clean.
- The complete baseline suite passes.

If any expectation fails, stop. Finish or merge Clean Dictation first. At execution time, use `using-git-worktrees` to create a separate `codex/agent-workspace` worktree from that clean base.

---

### Task 0: Pin the Official MCP Dependency and License Evidence

**Files:**
- Modify: `Package.swift`
- Modify: `Package.resolved`
- Modify: `Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md`
- Create: `Tests/MenuBarNotesAppTests/MCPDependencyPinTests.swift`

**Interfaces:**
- Consumes: the post–Clean Dictation Swift package.
- Produces: an exact `swift-sdk` dependency available to the later helper target as `.product(name: "MCP", package: "swift-sdk")`.

- [ ] **Step 1: Write the dependency evidence test**

Create a test that reads `Package.resolved` and the notices file from the package root:

```swift
import Foundation
import Testing

@Test func mcpDependencyAndNoticeArePinned() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let resolved = try String(
    contentsOf: root.appendingPathComponent("Package.resolved"),
    encoding: .utf8
  )
  #expect(resolved.contains(#""identity" : "swift-sdk""#))
  #expect(resolved.contains(#""version" : "0.12.1""#))
  #expect(resolved.contains(#""revision" : "a0ae212ebf6eab5f754c3129608bc5557637e605""#))

  let notices = try String(
    contentsOf: root.appendingPathComponent(
      "Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md"
    ),
    encoding: .utf8
  )
  #expect(notices.contains("modelcontextprotocol/swift-sdk"))
  #expect(notices.contains("0.12.1"))
}
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
swift test --filter mcpDependencyAndNoticeArePinned
```

Expected: FAIL because `swift-sdk` is not resolved or attributed.

- [ ] **Step 3: Verify the upstream tag and license**

Run:

```bash
git ls-remote https://github.com/modelcontextprotocol/swift-sdk.git refs/tags/0.12.1
curl -fL https://raw.githubusercontent.com/modelcontextprotocol/swift-sdk/0.12.1/LICENSE \
  -o /tmp/motes-mcp-sdk-license
wc -c /tmp/motes-mcp-sdk-license
shasum -a 256 /tmp/motes-mcp-sdk-license
```

Expected tag: `a0ae212ebf6eab5f754c3129608bc5557637e605`.

Expected license evidence:

```text
12227
0382b0057770ca05e9c350a50aa3b1c1fea84da0bc81d723bf00b9aa841be58a
```

- [ ] **Step 4: Pin the package and add attribution**

Add to `Package.swift` dependencies:

```swift
.package(
  url: "https://github.com/modelcontextprotocol/swift-sdk.git",
  exact: "0.12.1"
),
```

Do not link it into the Motes app target. Add its repository, version, license, and copyright notice to `ThirdPartyNotices.md`.

- [ ] **Step 5: Resolve and verify GREEN**

Run:

```bash
swift package resolve
swift test --filter mcpDependencyAndNoticeArePinned
swift test
git diff --check
```

Expected: all tests pass and `Package.resolved` contains the exact tag revision.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved \
  Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md \
  Tests/MenuBarNotesAppTests/MCPDependencyPinTests.swift
git commit -m "build: pin the Motes MCP SDK"
```

---

### Task 1: Persist Explicit Sharing and Note Revisions

**Files:**
- Modify: `Sources/MenuBarNotesCore/Note.swift`
- Modify: `Sources/MenuBarNotesCore/Workspace.swift`
- Modify: `Sources/MenuBarNotesCore/LocalStore.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Modify: `Tests/MenuBarNotesCoreTests/WorkspaceTests.swift`
- Modify: `Tests/MenuBarNotesCoreTests/LocalStoreTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/AppStateTests.swift`

**Interfaces:**
- Consumes: existing `Note`, `Workspace`, `LocalStore`, and post-dictation `AppState`.
- Produces:
  - `Note.agentAccess: Bool`
  - `Note.revision: UInt64`
  - `Workspace.setAgentAccess(id:enabled:now:)`
  - `Workspace.updateContent(id:body:rtf:now:)`
  - exactly one revision increment for each logical title, combined body/RTF, or sharing mutation.
  - `AppState.persistenceGeneration` and `waitUntilInitialLoad()` for later compare-and-swap persistence and bridge startup.

- [ ] **Step 1: Write backward-compatibility and revision tests**

Add tests covering:

```swift
@Test func oldNoteJSONDefaultsAgentFields() throws {
  let data = Data("""
  {
    "id":"00000000-0000-0000-0000-000000000001",
    "title":"Legacy",
    "body":"Body",
    "createdAt":0,
    "modifiedAt":0,
    "isPinned":false
  }
  """.utf8)
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  let note = try decoder.decode(Note.self, from: data)
  #expect(note.agentAccess == false)
  #expect(note.revision == 0)
}

@Test func contentAndSharingChangesIncrementRevisionOnce() {
  let id = UUID()
  var workspace = Workspace(notes: [Note(id: id)], selectedNoteID: id)
  workspace.updateContent(id: id, body: "A", rtf: Data([1]))
  #expect(workspace.notes[0].revision == 1)
  workspace.updateContent(id: id, body: "A", rtf: Data([1]))
  #expect(workspace.notes[0].revision == 1)
  workspace.setAgentAccess(id: id, enabled: true)
  #expect(workspace.notes[0].revision == 2)
}
```

Add regressions in `AppStateTests` proving one editor callback that supplies both body and RTF increments the revision once, not once per binding; every persisted workspace, preference, and pending-Trash mutation increments `persistenceGeneration`; and `waitUntilInitialLoad()` resumes on both successful and failed initial load. Add store round-trip coverage for `agentAccess` and `revision`, plus an old manifest fixture without either key.

- [ ] **Step 2: Run focused tests to verify RED**

```bash
swift test --filter oldNoteJSONDefaultsAgentFields
swift test --filter contentAndSharingChangesIncrementRevisionOnce
```

Expected: compilation fails because the properties and APIs do not exist.

- [ ] **Step 3: Add backward-compatible note fields**

Add:

```swift
public var agentAccess: Bool
public var revision: UInt64
```

Extend the initializer with defaults:

```swift
agentAccess: Bool = false,
revision: UInt64 = 0
```

Implement explicit `CodingKeys` and `init(from:)` so missing values decode to `false` and `0`. Preserve every existing field.

- [ ] **Step 4: Centralize revision increments**

In `Workspace`, update title only when it differs. Add one combined editor mutation:

```swift
public mutating func updateContent(
  id: UUID,
  body: String,
  rtf: Data?,
  now: Date = Date()
)

public mutating func setAgentAccess(
  id: UUID,
  enabled: Bool,
  now: Date = Date()
)
```

`updateContent` compares body and RTF together, no-ops when both are unchanged, and increments once when either changes. `setAgentAccess` follows the same no-op rule. Route the editor's body/RTF feedback through one `AppState` method so a keystroke cannot call separate revision-incrementing mutations.

Expose a read-only monotonically increasing `persistenceGeneration` from `AppState` and increment it for every actual persisted-state mutation: workspace, preferences, or pending Trash, including initial load replacement. Add `hasFinishedInitialLoad` plus `waitUntilInitialLoad()` backed by continuations; finish it exactly once on either the load success or failure path.

- [ ] **Step 5: Persist metadata compatibly**

Extend active and Trash metadata with optional decoded fields:

```swift
var agentAccess: Bool?
var revision: UInt64?
```

Write concrete values. Read missing values as `false` and `0`. Trash preserves both fields, but trashed notes remain inaccessible to agents.

- [ ] **Step 6: Verify**

```bash
swift test --filter WorkspaceTests
swift test --filter LocalStoreTests
swift test --filter AppStateTests
swift test
git diff --check
```

Expected: all tests pass and old fixtures load unchanged.

- [ ] **Step 7: Commit**

```bash
git add Sources/MenuBarNotesCore/Note.swift \
  Sources/MenuBarNotesCore/Workspace.swift \
  Sources/MenuBarNotesCore/LocalStore.swift \
  Sources/MenuBarNotesApp/AppState.swift \
  Tests/MenuBarNotesCoreTests/WorkspaceTests.swift \
  Tests/MenuBarNotesCoreTests/LocalStoreTests.swift \
  Tests/MenuBarNotesAppTests/AppStateTests.swift
git commit -m "feat: persist agent sharing and revisions"
```

---

### Task 2: Define the Agent Contract and Pure Mutation Engine

**Files:**
- Create: `Sources/MenuBarNotesCore/AgentWorkspaceModels.swift`
- Create: `Sources/MenuBarNotesCore/AgentNoteMutationEngine.swift`
- Create: `Sources/MenuBarNotesCore/AgentUndoEngine.swift`
- Create: `Tests/MenuBarNotesCoreTests/AgentNoteMutationEngineTests.swift`
- Create: `Tests/MenuBarNotesCoreTests/AgentUndoEngineTests.swift`

**Interfaces:**
- Consumes: `Note.body`, `Note.revision`, and readable `○`/`●` checklist markers.
- Produces:

```swift
public struct AgentWriteContext: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let expectedRevision: UInt64
  public let operationID: UUID
}

public enum AgentWorkspaceCommand: Codable, Equatable, Sendable
public enum AgentWorkspaceResponse: Codable, Equatable, Sendable
public enum AgentWorkspaceErrorCode: String, Codable, Sendable
public struct AgentWriteReceipt: Codable, Equatable, Sendable
public enum AgentActivityActor: Codable, Equatable, Sendable
public struct AgentWorkspaceCommitProof: Codable, Equatable, Sendable
public struct AgentMutationDraft: Equatable, Sendable
public struct AgentTextPatch: Codable, Equatable, Sendable
public struct AgentParsedTask: Equatable, Sendable
public enum AgentNoteMutationEngine
public enum AgentUndoEngine
```

- [ ] **Step 1: Write command encoding and mutation tests**

Cover every command:

- `listSharedNotes`
- `readNote(noteID:startLine:maxLines:)`
- `appendText`
- `insertText(beforeLine:)`
- `replaceLines(startLine:endLine:expectedTextSHA256:text:)`
- `listTasks`
- `addTask(afterTaskHandle:text:)`
- `renameTask(taskHandle:text:)`
- `setTaskState(taskHandle:completed:)`
- `removeTask`
- `listActivity`
- `undoChange`

Include these concrete boundaries:

```swift
@Test func appendUsesParagraphBoundaryAndBuildsPatch() throws {
  let draft = try AgentNoteMutationEngine.append(
    text: "Agent update",
    to: "Existing",
    maximumBytes: 65_536
  )
  #expect(draft.body == "Existing\n\nAgent update")
  #expect(draft.patch.beforeText == "")
  #expect(draft.patch.afterText == "\n\nAgent update")
}

@Test func replaceRejectsWrongObservedHash() {
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.replaceLines(
      in: "One\nTwo\nThree",
      startLine: 2,
      endLine: 2,
      expectedTextSHA256: "wrong",
      replacement: "Changed",
      maximumBytes: 65_536
    )
  }
}

@Test func checklistParsingDoesNotAddHiddenIDs() throws {
  let tasks = AgentNoteMutationEngine.tasks(in: "○ First\n● Done")
  #expect(tasks.map(\.text) == ["First", "Done"])
  #expect(tasks.map(\.completed) == [false, true])
}
```

- [ ] **Step 2: Run RED**

```bash
swift test --filter AgentNoteMutationEngine
swift test --filter AgentUndoEngine
```

Expected: compilation fails because the agent contract does not exist.

- [ ] **Step 3: Implement stable models**

Use associated-value Codable commands with explicit nested request structs. Define response cases for note summaries, a paged note body with `nextLine`, task summaries, a write receipt, activity summaries, and Undo.

Define activity identity explicitly:

```swift
public enum AgentActivityActor: Codable, Equatable, Sendable {
  case integration(profileID: UUID, displayName: String)
  case localUser
}
```

Idempotency scopes an operation ID by this actor. A local Motes Undo therefore cannot collide with an integration operation that happens to use the same UUID.

`AgentWorkspaceCommitProof` is content-free and contains change ID, note ID, resulting revision, body SHA-256, actor, operation ID, and expiry. Task 5 persists it inside the same `workspace.json` replacement that commits the note revision, making it durable proof for crash reconciliation without storing note text.

Define the error vocabulary exactly:

```swift
public enum AgentWorkspaceErrorCode: String, Codable, Sendable {
  case noteNotFound = "note_not_found"
  case permissionRevoked = "permission_revoked"
  case revisionConflict = "revision_conflict"
  case taskHandleExpired = "task_handle_expired"
  case unsafeUndo = "unsafe_undo"
  case motesUnavailable = "motes_unavailable"
  case writeTooLarge = "write_too_large"
  case responseTooLarge = "response_too_large"
  case invalidOperation = "invalid_operation"
  case invalidPayload = "invalid_payload"
  case internalSaveFailure = "internal_save_failure"
}
```

- [ ] **Step 4: Implement line and checklist mutations**

Rules:

- Normalize CRLF and CR to LF at the command boundary.
- Use one-based inclusive line numbers.
- Treat an empty body as zero existing lines for insertion and one empty line for replacement validation.
- Append uses `\n\n` when the existing body is nonempty.
- Checklist recognition accepts indentation in multiples of four spaces and markers `○ ` or `● `.
- A completed task's body marker changes to `●`; a reopened task changes to `○`.
- Renaming preserves indentation and completion.
- Reject one write payload above 65,536 UTF-8 bytes.

`AgentTextPatch` stores the replaced text, replacement text, original UTF-16 range, and up to 32 characters of prefix and suffix context.

- [ ] **Step 5: Implement conservative inverse application**

`AgentUndoEngine.inverting(_:in:)`:

1. Applies at the original range when the replacement and contexts still match.
2. Otherwise searches for exactly one replacement occurrence with both stored contexts.
3. Returns `unsafeUndo` for zero or multiple safe candidates.

It never performs fuzzy matching.

- [ ] **Step 6: Verify**

```bash
swift test --filter AgentNoteMutationEngine
swift test --filter AgentUndoEngine
swift test
git diff --check
```

- [ ] **Step 7: Commit**

```bash
git add Sources/MenuBarNotesCore/AgentWorkspaceModels.swift \
  Sources/MenuBarNotesCore/AgentNoteMutationEngine.swift \
  Sources/MenuBarNotesCore/AgentUndoEngine.swift \
  Tests/MenuBarNotesCoreTests/AgentNoteMutationEngineTests.swift \
  Tests/MenuBarNotesCoreTests/AgentUndoEngineTests.swift
git commit -m "feat: define safe agent note mutations"
```

---

### Task 3: Add Durable Activity, Prepared Transactions, and Idempotency

**Files:**
- Create: `Sources/MenuBarNotesCore/AgentActivityStore.swift`
- Create: `Tests/MenuBarNotesCoreTests/AgentActivityStoreTests.swift`

**Interfaces:**
- Consumes: `AgentTextPatch`, operation ID, `AgentActivityActor`, note revisions, and note body hashes.
- Produces:

```swift
public final class AgentActivityStore: @unchecked Sendable {
  public init(rootURL: URL, now: @escaping @Sendable () -> Date = Date.init)
  public func prepare(_ transaction: PreparedAgentTransaction) throws
  public func commit(changeID: UUID, receipt: AgentWriteReceipt) throws
  public func abort(changeID: UUID) throws
  public func priorReceipt(actor: AgentActivityActor, operationID: UUID) -> AgentWriteReceipt?
  public func list(profileID: UUID?, visibleNoteIDs: Set<UUID>) -> [AgentActivityRecord]
  public func record(id: UUID) -> AgentActivityRecord?
  public func clearVisibleActivity() throws
  public func reconcile(
    workspace: Workspace,
    commitProofs: [AgentWorkspaceCommitProof]
  ) throws
}
```

- [ ] **Step 1: Write lifecycle tests**

Cover:

- Atomic prepared record.
- A durable content-free commit proof from the workspace manifest is accepted only when its identifiers and hashes match the preparation.
- Commit moves the visible record and writes a tombstone.
- Duplicate `(actor, operationID)` returns the original response without collisions between local-user and integration operations.
- A prepared record whose resulting revision/body hash exists is finalized on reconciliation.
- A prepared record with a durable committed proof is finalized when the same note has the resulting or a later revision.
- A later note revision without a committed proof does not falsely finalize a transaction that crashed before applying.
- A prepared record not reflected in the workspace is removed.
- Malformed entries do not poison valid activity.
- Visible records expire at exactly 30 days.
- Clear removes patch content but leaves a minimal tombstone until original expiry.
- Integration listing includes only its own activity for currently shared note IDs.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AgentActivityStore
```

Expected: compilation fails because the store and models do not exist.

- [ ] **Step 3: Implement directory layout and atomic writes**

Use:

```text
Application Support/MenuBarNotes/AgentActivity/
├── Prepared/
├── Records/
└── Tombstones/
```

Each entry is one lowercased UUID JSON file. Reject filenames that do not parse as the embedded identifier. Encode ISO-8601 dates with sorted, pretty JSON. Write atomically.

- [ ] **Step 4: Implement reconciliation and purge**

A prepared transaction includes resulting note revision and SHA-256 body hash. Reconciliation validates any manifest proof against the complete prepared identity and finalizes when:

1. The loaded note has exactly the resulting revision and body hash; or
2. A valid committed proof exists and the loaded note has the resulting or a later revision.

It removes the preparation without activity when neither condition holds. A later revision by itself is never proof, because a human edit may have persisted after preparation but before the agent commit.

Visible patches expire at `createdAt + 30 days`. Tombstones retain only the actor identity, operation ID, the content-free `AgentWriteReceipt` containing change ID and resulting revision, and original expiry. They never retain body text or patches.

Use one internal `NSLock` around every index and filesystem mutation. `AgentActivityStore` is synchronous so its final record/tombstone commit can remain in Task 5's non-yielding main-actor critical section.

- [ ] **Step 5: Verify**

```bash
swift test --filter AgentActivityStore
swift test
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarNotesCore/AgentActivityStore.swift \
  Tests/MenuBarNotesCoreTests/AgentActivityStoreTests.swift
git commit -m "feat: store agent activity and retries"
```

---

### Task 4: Add Integration Profiles, Credential Verification, and Task Handles

**Files:**
- Create: `Sources/MenuBarNotesApp/AgentProfileStore.swift`
- Create: `Sources/MenuBarNotesApp/AgentCredentialSecurity.swift`
- Create: `Sources/MenuBarNotesApp/AgentTaskHandleCodec.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentProfileStoreTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentTaskHandleCodecTests.swift`

**Interfaces:**
- Consumes: profile IDs, profile names, note revision, parsed task line, Security, and CryptoKit.
- Produces:

```swift
struct AgentIntegrationProfile: Codable, Identifiable, Equatable, Sendable

actor AgentProfileStore {
  func create(name: String) async throws -> AgentProfileProvisioning
  func authorize(profileID: UUID, credential: Data) async throws -> AgentIntegrationProfile
  func revoke(profileID: UUID) async throws
  func activeProfiles() async throws -> [AgentIntegrationProfile]
}

struct AgentTaskHandleCodec {
  func encode(_ reference: AgentTaskReference) throws -> String
  func decode(_ handle: String, noteID: UUID, revision: UInt64) throws -> AgentTaskReference
}
```

- [ ] **Step 1: Write fake-secret-store tests**

Cover:

- Profile creation trims and validates a 1–80 character display name.
- Creation returns a 32-byte random credential once and stores only its SHA-256 verifier in Keychain.
- Equal credentials authorize with constant-time comparison.
- Wrong, revoked, and unknown profiles fail with scoped errors.
- Wrong credentials, revoked profiles, and unknown profile IDs all throw the same byte-for-byte `AgentWorkspaceError(code: .permissionRevoked)` so callers cannot enumerate profiles.
- Revocation during a test request prevents the next command.
- Handles reject changed bytes, the wrong note, and the wrong revision.
- Handles round-trip Unicode task text hashes.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AgentProfileStore
swift test --filter AgentTaskHandleCodec
```

- [ ] **Step 3: Implement profile persistence**

Persist non-secret metadata below:

```text
Application Support/MenuBarNotes/AgentIntegrations/profiles.json
```

The JSON contains profile ID, display name, creation/connection timestamps, and revocation state only. Store each credential SHA-256 verifier in Keychain with:

```text
service: com.harryjin.motes.agent-profile-verifier
account: <profile UUID>
```

Never store raw credentials or verifiers in JSON. Use an injected random-byte generator and secret store in tests and `SecRandomCopyBytes` plus Security in production.

- [ ] **Step 4: Implement the signing-key provider**

Define an `AgentSigningKeyProviding` protocol. The production implementation loads or creates 32 random bytes in Keychain with:

```text
service: com.harryjin.motes.agent-task-handles
account: default
```

Use `HMAC<SHA256>` over a versioned Codable payload containing note ID, revision, one-based line number, and SHA-256 of the complete checklist line.

- [ ] **Step 5: Verify**

```bash
swift test --filter AgentProfileStore
swift test --filter AgentTaskHandleCodec
swift test
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarNotesApp/AgentProfileStore.swift \
  Sources/MenuBarNotesApp/AgentCredentialSecurity.swift \
  Sources/MenuBarNotesApp/AgentTaskHandleCodec.swift \
  Tests/MenuBarNotesAppTests/AgentProfileStoreTests.swift \
  Tests/MenuBarNotesAppTests/AgentTaskHandleCodecTests.swift
git commit -m "feat: authorize local Motes agents"
```

---

### Task 4.5: Expose the Exact Resolved Undo Mutation

**Files:**
- Modify: `Sources/MenuBarNotesCore/AgentUndoEngine.swift`
- Modify: `Tests/MenuBarNotesCoreTests/AgentUndoEngineTests.swift`

**Interfaces:**

Add:

```swift
public static func draft(
  inverting patch: AgentTextPatch,
  in body: String
) throws -> AgentMutationDraft
```

Keep `inverting(_:in:)` as a compatibility wrapper returning `draft.body`.

- [ ] **Step 1: Write RED tests**

Cover an Undo whose context uniquely relocates the edit after nearby human text was inserted. Require the draft to return:

- The resulting body.
- The actual resolved UTF-16 range, not the stale original range.
- An inverse patch whose `beforeText` is the text being removed and whose `afterText` is the restored text.
- Prefix and suffix context from the current body at the resolved range.

Add an attributed-text-oriented regression fixture with identical nearby text carrying different formatting so Task 5 can prove it mutates the resolved run rather than the original offset.

- [ ] **Step 2: Implement minimally**

Reuse the existing exact/context matcher once, return the resolved range, and build the inverse `AgentMutationDraft`. Do not duplicate the matcher in Task 5 and do not change current conservative ambiguity or whole-body-deletion behavior.

- [ ] **Step 3: Verify and commit**

```bash
swift test --filter AgentUndoEngine
swift test
git diff --check
git add Sources/MenuBarNotesCore/AgentUndoEngine.swift \
  Tests/MenuBarNotesCoreTests/AgentUndoEngineTests.swift
git commit -m "feat: expose resolved agent undo patches"
```

---

### Task 5: Implement Rich-Text-Safe Mutations and the Single-Writer Gateway

**Files:**
- Create: `Sources/MenuBarNotesCore/LocalStoreSnapshotWriter.swift`
- Modify: `Sources/MenuBarNotesCore/LocalStore.swift`
- Create: `Sources/MenuBarNotesApp/AgentRichTextMutator.swift`
- Create: `Sources/MenuBarNotesApp/AgentCommandService.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Modify: `Tests/MenuBarNotesCoreTests/LocalStoreTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentRichTextMutatorTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentCommandServiceTests.swift`

**Interfaces:**
- Consumes:
  - Task 1 note revisions.
  - Task 2 mutations and inverse patches.
  - Task 3 activity transactions.
  - Task 4 profile authorization and task handles.
  - post-dictation `NoteTextAppender`.
- Produces:

```swift
@MainActor
final class AgentCommandService {
  func execute(
    profileID: UUID,
    credential: Data,
    command: AgentWorkspaceCommand
  ) async throws -> AgentWorkspaceResponse

  func executeLocalUndo(
    changeID: UUID,
    expectedRevision: UInt64,
    operationID: UUID
  ) async throws -> AgentWorkspaceResponse
}

struct AgentChangeFeedback: Equatable, Sendable {
  let changeID: UUID
  let noteID: UUID
  let noteTitle: String
  let actor: AgentActivityActor
  let resultingRevision: UInt64
  let createdAt: Date
}

@MainActor
protocol AgentWorkspaceStateAccess: AnyObject {
  var workspace: Workspace { get }
  var persistenceGeneration: UInt64 { get }
  var preferences: AppPreferences { get }
  var isAgentWorkspaceAvailable: Bool { get }
  func flushPendingPersistenceForAgent() async throws
  func commitAgentWorkspace(
    _ workspace: Workspace,
    expectedGeneration: UInt64,
    commitProof: AgentWorkspaceCommitProof
  ) throws
}
```

`AgentCommandService` uses a FIFO task chain so one complete agent command finishes before the next starts; actor reentrancy alone is not sufficient. It owns `AgentProfileStore`, authorizes `profileID` plus `credential` inside that FIFO immediately before each command, and retains the returned profile only for that command. Authorization and preparation may await, but the final workspace save and publish are one synchronous main-actor critical section.

- [ ] **Step 1: Write rich-text preservation tests**

Cover:

- Append reuses `NoteTextAppender` and preserves existing font/underline runs.
- Line insertion preserves all attributed runs outside the insertion.
- Replacement applies current editor defaults only to new text.
- Completing a task strikes through task content but not indentation or marker.
- Reopening removes only the task-content strike.
- Removing one task preserves adjacent rich text.
- Relocated safe Undo mutates the exact attributed range returned by `AgentUndoEngine.draft`, preserving a differently formatted identical nearby run.
- A stale or semantically mismatched RTF sidecar is rejected safely rather than applying body-derived ranges to unrelated attributed text.
- CR/LF/CRLF body and decoded RTF strings must match exactly in UTF-16 before a rich-text mutation; an unrepresentable newline mismatch is rejected without publishing or persisting a change.

- [ ] **Step 2: Write service contract tests**

Cover:

- Discovery returns shared notes only.
- Direct probing of an unknown or unshared UUID returns the same `note_not_found` response.
- Every write rejects a stale revision before mutation.
- A duplicate operation ID returns the stored receipt.
- Successful persistence publishes one new workspace revision and activity record.
- Save failure publishes no in-memory mutation and aborts preparation.
- A human edit while authorization or preparation is suspended changes the persistence generation and rejects the agent write without overwriting the human state.
- Agent execution first drains any existing autosave and pending Trash work; it times out safely instead of entering the critical section while Trash is pending.
- An activity-commit failure after workspace persistence leaves the persisted workspace published; retrying the same operation reconciles the preparation and does not duplicate the mutation.
- Two concurrent agent commands run through the FIFO chain rather than interleaving at awaits.
- Crash-style prepared reconciliation finalizes correctly after reload.
- List activity exposes only the caller's records for currently shared notes.
- Agent Undo creates a new attributed activity record.
- Local user Undo works for an active note after unsharing or revoking the originating profile.
- Later ambiguous edits return `unsafe_undo`.
- Human pending edits are part of the revision checked by an agent command.
- Every rejection throws the existing Codable `AgentWorkspaceError`; successful return values remain `AgentWorkspaceResponse`.
- A failed initial root/Recovery load leaves `isAgentWorkspaceAvailable == false`; every command, including discovery, throws `motes_unavailable` before observing the default in-memory workspace. A fresh no-manifest workspace is a successful validated load.

- [ ] **Step 3: Run RED**

```bash
swift test --filter AgentRichTextMutator
swift test --filter AgentCommandService
```

- [ ] **Step 4: Implement attributed mutations**

Decode existing RTF when valid; otherwise create attributed text from `note.body` and current font preferences. Before applying anything, require the attributed string and `note.body` to be exactly equal in UTF-16. A parseable but stale sidecar, or a CR/LF/CRLF representation that cannot round-trip exactly through RTF, fails safely with `motes_unavailable` and a retry/recovery action; it is never silently normalized, reformatted, or applied at a guessed range. Map body line ranges to `NSRange` using `NSString`. Apply the exact pure-engine replacement (or the exact resolved inverse patch returned by Task 4.5), serialize RTF, decode it again, and require its string to equal the resulting body before returning body plus RTF together.

Construct the resulting `Note` with body and RTF updated together, then increment its revision exactly once. Do not call the separate human body and RTF mutation methods in sequence.

Do not route mutations through the visible `NSTextView`; visible editors update from the published note state after durable commit.

- [ ] **Step 5: Extract synchronous snapshot persistence**

Move the existing file-writing body used by `LocalStore.save` into a synchronous, lock-protected `LocalStoreSnapshotWriter`. The `LocalStore` actor and `AppState` must receive the same writer instance; expose it from `LocalStore` as an immutable `nonisolated` dependency if needed. The writer holds one internal `NSLock` for the complete synchronous save, so no two paths can write concurrently. Do not duplicate manifest, Markdown, RTF, preferences, Trash, recovery, or cleanup logic.

Every AppState save carries the `persistenceGeneration` captured with that snapshot. Under the same lock, the writer tracks the highest committed generation and returns `.superseded` without touching disk when an older queued autosave arrives after a newer agent or human snapshot. Advance the watermark only after the atomic manifest commit; a pre-commit failure must leave that generation retryable. Test both lock acquisition orders and a failed newer save followed by its retry.

Extend the backward-compatible manifest with optional `snapshotIntegrityVersion: 1`, per-note Markdown and RTF SHA-256 values, `preferencesSHA256`, and a bounded list of unexpired `AgentWorkspaceCommitProof` values. A normal save preserves and purges these content-free proofs. An agent save adds its proof to the manifest that records the resulting note revision.

Treat the atomic `workspace.json` replacement as the snapshot commit point:

1. Validate the current root generation. Create a Recovery snapshot only from a valid root; when root validation already fell back to Recovery, preserve that Recovery until a new root manifest commits.
2. Encode preferences once, then perform every fallible preferences, Markdown, and RTF write for the active generation.
3. Compute hashes from the bytes actually written.
4. Atomically replace `workspace.json` last with matching revisions, hashes, and agent proofs.
5. Perform orphan cleanup as best-effort, non-throwing maintenance.

On load, `snapshotIntegrityVersion == 1` is valid only when every referenced Markdown/RTF file and the exact encoded `preferences.json` bytes have the required matching hash. Reject the entire root generation and load workspace plus preferences from Recovery when any hash is missing or wrong. Old manifests with no integrity version remain readable and acquire hashes on their next save. This makes a preferences-only crash before the manifest commit recover the old complete generation, while a committed proof always names the complete new generation.

Add `LocalStore.loadSnapshot()` returning workspace, preferences, commit proofs, and whether root or Recovery was validated. `AppState` must load workspace and preferences from that one source instead of independently accepting root preferences after the root workspace was rejected.

Add regressions using two queues and controllable filesystem hooks for both stale-save orderings, failed-generation retry, crash points before and after the manifest commit, a preferences-only pre-commit crash, missing or corrupt preferences fallback, post-commit cleanup failure, root hash mismatch fallback followed by a save that preserves valid Recovery, and old hashless manifests.

Trash remains on the existing idempotent archive path rather than entering an agent snapshot transaction. `flushPendingPersistenceForAgent()` cancels the debounce, awaits any in-flight save, and repeats until the current `persistenceGeneration` is durable and `pendingTrashNotes` is empty. Bound this drain to two seconds; on continued edits, Trash failure, or timeout, reject the agent command with `motes_unavailable` and a retry action. `commitAgentWorkspace` refuses to run when pending Trash is nonempty and does not archive or restore Trash itself.

`AppState.commitAgentWorkspace` must:

1. Verify `persistenceGeneration == expectedGeneration`.
2. Cancel the pending debounced save.
3. Persist the candidate workspace with `persistenceGeneration + 1` and the new commit proof synchronously through the shared writer.
4. Publish the candidate workspace and advance `persistenceGeneration` to that committed generation.

The method has no `await`. A pre-commit save error leaves published state unchanged; a post-commit cleanup issue is diagnostic only and cannot turn a committed snapshot into a reported failure. This intentionally keeps the ordered disk write, manifest proof, and publication inside one short main-actor critical section so a human binding update cannot interleave. Do not add a second persistence implementation.

- [ ] **Step 6: Implement transaction ordering**

For a write:

1. Enter the FIFO agent-command chain.
2. Authorize the supplied profile ID and credential through `AgentProfileStore`, then discard the credential after this command; reconcile any preparation for the same operation ID.
3. Return a prior idempotent receipt when present.
4. Await `flushPendingPersistenceForAgent()` so no older save or pending Trash operation remains.
5. On the main actor, capture the live workspace and `persistenceGeneration`; scope unknown and unshared notes identically.
6. Validate the expected note revision and build the candidate body, RTF, patch, and resulting revision from that snapshot.
7. Write the prepared activity transaction.
8. Re-enter the main actor and revalidate both the captured generation and expected note revision.
9. Call synchronous `commitAgentWorkspace` with the candidate, captured generation, and prepared commit proof; successful return means the workspace and its manifest proof are durable and the candidate is published.
10. Commit the activity record/tombstone synchronously, publish feedback, and return the receipt.

On failure before step 9, abort preparation when one exists and publish nothing. A workspace-save failure at step 9 also aborts preparation and publishes nothing. A failure after workspace persistence keeps the durable candidate published and the preparation intact, throws `AgentWorkspaceError(code: .internalSaveFailure)`, and reconciles that operation from the manifest proof before any retry can mutate. Never roll back or overwrite newer human state.

`executeLocalUndo` bypasses integration-profile authorization because it represents an explicit Motes user action. It still requires the active note, expected revision, operation ID, safe inverse proof, the same prepared transaction, and the same synchronous durable commit. Attribute the new activity to the local Motes user while retaining the originating integration in the description.

- [ ] **Step 7: Integrate AppState**

Make `AppState` conform to `AgentWorkspaceStateAccess`, use the Task 1 readiness/generation APIs, and inject the shared synchronous snapshot writer used by `commitAgentWorkspace`. Track successful initial snapshot availability separately from `hasFinishedInitialLoad`: no-manifest initialization and a validated root/Recovery load are available; a thrown load remains unavailable for the process lifetime. Every existing debounced, immediate, restore, and Trash-related save must pass the generation captured with its workspace snapshot and treat `.superseded` as a safe no-op rather than an error.

Add:

```swift
@Published private(set) var latestAgentFeedback: AgentChangeFeedback?
@Published private(set) var agentProfiles: [AgentIntegrationProfile] = []
```

Human sharing changes use `setAgentAccess`, save immediately, and do not create Agent Activity.

- [ ] **Step 8: Verify**

```bash
swift test --filter AgentRichTextMutator
swift test --filter AgentCommandService
swift test
git diff --check
```

- [ ] **Step 9: Commit**

```bash
git add Sources/MenuBarNotesCore/LocalStoreSnapshotWriter.swift \
  Sources/MenuBarNotesCore/LocalStore.swift \
  Sources/MenuBarNotesApp/AgentRichTextMutator.swift \
  Sources/MenuBarNotesApp/AgentCommandService.swift \
  Sources/MenuBarNotesApp/AppState.swift \
  Tests/MenuBarNotesCoreTests/LocalStoreTests.swift \
  Tests/MenuBarNotesAppTests/AgentRichTextMutatorTests.swift \
  Tests/MenuBarNotesAppTests/AgentCommandServiceTests.swift
git commit -m "feat: apply agent changes through Motes"
```

---

### Task 6: Add the Versioned Wire Protocol and Same-User Unix IPC

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MenuBarNotesAgentProtocol/AgentWireProtocol.swift`
- Create: `Sources/MenuBarNotesAgentProtocol/AgentWireFraming.swift`
- Create: `Sources/MenuBarNotesAgentProtocol/AgentBridgeEndpoint.swift`
- Create: `Sources/MenuBarNotesApp/AgentIPCServer.swift`
- Modify: `Sources/MenuBarNotesApp/MenuBarNotesApp.swift`
- Create: `Tests/MenuBarNotesAgentProtocolTests/AgentWireProtocolTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentIPCServerTests.swift`

**Interfaces:**
- Consumes: `AgentWorkspaceCommand`, `AgentWorkspaceResponse`, profile authorization, and `AgentCommandService`.
- Produces:

```swift
public struct AgentWireRequest: Codable, Equatable, Sendable {
  public static let currentProtocolVersion = 1
  public let protocolVersion: Int
  public let requestID: UUID
  public let profileID: UUID
  public let credentialBase64: String
  public let command: AgentWorkspaceCommand

  public init(
    protocolVersion: Int = currentProtocolVersion,
    requestID: UUID,
    profileID: UUID,
    credentialBase64: String,
    command: AgentWorkspaceCommand
  )
}

public struct AgentWireResponse: Codable, Equatable, Sendable {
  public let protocolVersion: Int
  public let requestID: UUID
  public let result: AgentWorkspaceResponse?
  public let error: AgentWorkspaceError?

  public static func success(
    requestID: UUID,
    result: AgentWorkspaceResponse
  ) -> AgentWireResponse
  public static func failure(
    requestID: UUID,
    error: AgentWorkspaceError
  ) -> AgentWireResponse
}

public enum AgentBridgeEndpoint {
  public static func applicationSupportURL(
    fileManager: FileManager = .default
  ) -> URL
  public static func socketURL(
    fileManager: FileManager = .default
  ) -> URL
}

public enum AgentWireFraming {
  public static let maximumFrameBytes = 1_048_576
  public static func encode<T: Encodable>(_ value: T) throws -> Data
  public static func decodeFrame<T: Decodable>(_ type: T.Type, from buffer: inout Data) throws -> T?
}
```

- [ ] **Step 1: Add protocol target and tests**

Add:

```swift
.library(name: "MenuBarNotesAgentProtocol", targets: ["MenuBarNotesAgentProtocol"])
```

The target depends on `MenuBarNotesCore`; the app target depends on the new protocol target. Add a protocol test target.

Test fragmented frames, coalesced frames, zero length, a frame above 1 MiB, malformed JSON, request/response correlation, old/new/unsupported protocol versions, and the shared exact `Application Support/MenuBarNotes/AgentBridge/motes.sock` endpoint. `AgentWireResponse` decoding must reject envelopes containing both result and error or neither. Add a server regression proving an oversized encoded success becomes a correlated, structured `response_too_large` error frame that itself remains below 1 MiB.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AgentWireProtocol
swift test --filter AgentIPCServer
```

- [ ] **Step 3: Implement four-byte framing**

Prefix each JSON payload with an unsigned four-byte big-endian length. Reject zero-length and lengths above 1,048,576 before allocating the payload buffer. Encode dates as ISO-8601.

Both request and response envelopes carry `protocolVersion == 1`. Expose the public request initializer and response success/failure factories above so the helper target never relies on internal memberwise initializers and cannot construct an invalid response. Reject unsupported request versions with a correlated `invalid_payload` recovery action instructing the user to update Motes and the helper. Use custom response decoding to enforce exactly one of `result` or `error`.

- [ ] **Step 4: Implement the server**

Create the socket at:

```text
Application Support/MenuBarNotes/AgentBridge/motes.sock
```

Requirements:

- Parent directory mode `0700`.
- Before creating or changing the parent, use `lstat` to reject a symlink, non-directory, or directory not owned by the current effective user.
- Remove an existing path only when `lstat` proves it is a socket owned by the current user.
- Reject a socket path whose UTF-8 representation plus NUL exceeds macOS `sockaddr_un.sun_path` (104 bytes).
- Socket mode `0600`.
- Use `getpeereid` to reject a peer UID different from `geteuid()`.
- Use explicit injectable limits: at most 8 accepted clients and a 10-second idle-read timeout. Reject excess clients immediately.
- Decode one request at a time per connection.
- Decode Base64 credentials strictly, then pass the profile ID and credential to `AgentCommandService`, which authenticates inside its FIFO immediately before executing the command. Catch `AgentWorkspaceError` from the service and encode it directly in the correlated error envelope; map malformed Base64 to `invalid_payload` and unexpected errors to a content-free `internal_save_failure`.
- Require the credential string to round-trip through canonical Base64 and decode to exactly 32 bytes before invoking the service.
- Measure the fully encoded response envelope before writing. Replace an oversized success with a minimal correlated `response_too_large` failure; never drop the connection merely because a legitimate result was too large.
- Never include internal paths or credentials in errors.
- Set `SO_NOSIGPIPE` on accepted sockets so a disconnected writer cannot terminate Motes.
- Bound each connection buffer to one framed request and reject an oversized declared length immediately after the fourth byte. Apply the idle timeout only while waiting for request bytes, never while an authorized command is executing.
- Record the bound socket device/inode and remove it on shutdown only when `lstat` still matches. Listener/client descriptor closure and owned-socket unlink are synchronous and thread-safe; `stop()` is safe before start and when repeated.

- [ ] **Step 5: Start one server from the app root**

Construct `AgentIPCServer` once beside the final post-dictation runtime. Await Task 1's `AppState.waitUntilInitialLoad()` before starting it; the Task 5 service availability gate still rejects every command after a failed load. Stop the server synchronously on runtime deinitialization or application termination. Starting a second Motes window must not create another listener.

Inject peer-credential lookup, active-client limit, idle clock/timeout, and low-level descriptor hooks in tests. Cover matching UID, mismatched UID, `getpeereid` failure, saturation, idle eviction, stop-before-start, start-twice, termination-before-readiness, multiple-window construction, raw-buffer overflow, and a disconnected response writer. Rejected peers and malformed/noncanonical/wrong-length credentials must never invoke authorization. Assert credentials, internal paths, and unexpected error text never appear in responses.

- [ ] **Step 6: Verify**

```bash
swift test --filter AgentWireProtocol
swift test --filter AgentIPCServer
swift test
swift test --filter mcpDependencyAndNoticeArePinned
Scripts/test-enhanced-candidate-pin.sh
Scripts/test-enhanced-candidate-lock-preservation.sh
candidate_scratch="$(mktemp -d "${TMPDIR:-/tmp}/motes-task6-candidate.XXXXXX")"
rmdir "$candidate_scratch"
Scripts/resolve-enhanced-candidate.sh "$candidate_scratch" \
  /bin/sh -c 'swift build --scratch-path "$1" --build-tests && swift test --scratch-path "$1"' \
  task6-candidate "$candidate_scratch"
rm -rf "$candidate_scratch"
Scripts/check-candidate-release-rejected.sh
git diff --check
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
  Sources/MenuBarNotesAgentProtocol/AgentWireProtocol.swift \
  Sources/MenuBarNotesAgentProtocol/AgentWireFraming.swift \
  Sources/MenuBarNotesAgentProtocol/AgentBridgeEndpoint.swift \
  Sources/MenuBarNotesApp/AgentIPCServer.swift \
  Sources/MenuBarNotesApp/MenuBarNotesApp.swift \
  Tests/MenuBarNotesAgentProtocolTests/AgentWireProtocolTests.swift \
  Tests/MenuBarNotesAppTests/AgentIPCServerTests.swift
git commit -m "feat: add private Motes agent IPC"
```

---

### Task 7: Build the `motes-agent` CLI Bridge

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MotesAgentBridge/MotesAgentBridge.swift`
- Create: `Sources/MotesAgentBridge/BridgeCommand.swift`
- Create: `Sources/MotesAgentBridge/AgentIPCClient.swift`
- Create: `Sources/MotesAgentBridge/BridgeCredentialStore.swift`
- Create: `Tests/MotesAgentBridgeTests/BridgeCommandTests.swift`
- Create: `Tests/MotesAgentBridgeTests/AgentIPCClientTests.swift`

**Interfaces:**
- Consumes: Task 6 wire protocol and socket path.
- Produces:
  - executable product `motes-agent`
  - CLI commands specified in the design
  - hidden `configure --profile <uuid> --token-stdin`
  - `mcp --profile <uuid>` entry reserved for Task 8.

- [ ] **Step 1: Add executable and test targets**

Add:

```swift
.executable(name: "motes-agent", targets: ["MotesAgentBridge"])
```

The executable depends on `MenuBarNotesCore` and `MenuBarNotesAgentProtocol`. Do not link MCP yet.

- [ ] **Step 2: Write parser and output tests**

Cover:

- Every documented CLI command.
- Required `--profile`.
- Required `--revision` and `--operation-id` for every write and Undo command.
- `--json`.
- Stdin text input.
- One-based line validation.
- Unknown flags returning exit code `64`.
- Workspace errors returning exit code `1` and stable JSON.
- Secrets never appearing in argv, stdout, stderr, or JSON.

- [ ] **Step 3: Write IPC client lifecycle tests**

Use injected launch and socket closures to cover:

- Existing app connects immediately.
- Missing socket launches bundle ID `com.harryjin.motes` without activation.
- Client waits at most 10 seconds for readiness.
- Partial frames, response request-ID mismatch, and response protocol-version mismatch fail without displaying a result.
- A timed-out write prints a retry-safe message retaining the operation ID.

- [ ] **Step 4: Implement credential storage**

The hidden configure command reads exactly 32 raw bytes encoded as Base64 from stdin and stores them in Keychain:

```text
service: com.harryjin.motes.agent-profile
account: <profile UUID>
```

Normal commands load the credential by profile ID. `disconnect --profile` deletes only that profile's helper credential.

- [ ] **Step 5: Implement app launch and IPC**

Use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and `openApplication(at:configuration:)` with `.withoutActivation`. Never invoke `open` through a shell.

Use `AgentBridgeEndpoint` and the exact socket/framing rules from Task 6. Require both the correlated request ID and `AgentWireRequest.currentProtocolVersion` on every response before exposing its result or error. CLI output defaults to concise human text; `--json` encodes `AgentWorkspaceResponse`.

- [ ] **Step 6: Verify**

```bash
swift test --filter MotesAgentBridgeTests
swift run motes-agent --help
swift test
git diff --check
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
  Sources/MotesAgentBridge/MotesAgentBridge.swift \
  Sources/MotesAgentBridge/BridgeCommand.swift \
  Sources/MotesAgentBridge/AgentIPCClient.swift \
  Sources/MotesAgentBridge/BridgeCredentialStore.swift \
  Tests/MotesAgentBridgeTests/BridgeCommandTests.swift \
  Tests/MotesAgentBridgeTests/AgentIPCClientTests.swift
git commit -m "feat: add the Motes agent CLI"
```

---

### Task 8: Expose the Same Contract Through MCP Stdio

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MotesAgentBridge/MotesMCPToolRegistry.swift`
- Create: `Sources/MotesAgentBridge/MotesMCPServer.swift`
- Modify: `Sources/MotesAgentBridge/MotesAgentBridge.swift`
- Create: `Tests/MotesAgentBridgeTests/MotesMCPToolRegistryTests.swift`
- Create: `Tests/MotesAgentBridgeTests/MotesMCPServerTests.swift`

**Interfaces:**
- Consumes: official MCP `Server`, `StdioTransport`, `ListTools`, `CallTool`, and Task 7 IPC client.
- Produces: `motes-agent mcp --profile <uuid>` with the twelve approved tools.

- [ ] **Step 1: Link the official SDK only to the helper**

Add:

```swift
.product(name: "MCP", package: "swift-sdk")
```

to `MotesAgentBridge` dependencies. Confirm `otool -L .build/release/Motes` does not contain the MCP helper module.

- [ ] **Step 2: Write schema and mapping tests**

Assert exact tool names:

```swift
[
  "list_shared_notes",
  "read_note",
  "append_text",
  "insert_text",
  "replace_lines",
  "list_tasks",
  "add_task",
  "rename_task",
  "set_task_state",
  "remove_task",
  "list_agent_activity",
  "undo_agent_change",
]
```

For each tool, validate required JSON Schema fields, 64 KiB descriptions, one-based lines, revision, and operation ID. Unknown fields are rejected.

- [ ] **Step 3: Run RED**

```bash
swift test --filter MotesMCP
```

- [ ] **Step 4: Implement the registry**

`MotesMCPToolRegistry` owns tool definitions and converts `CallTool.Parameters` to one `AgentWorkspaceCommand`. It returns both:

- concise text for model readability;
- a JSON text block containing the structured response.

Workspace failures set `isError: true` and retain the stable error code.

- [ ] **Step 5: Implement stdio server lifecycle**

Use the official SDK:

```swift
let server = Server(
  name: "motes",
  version: "1.0.0",
  capabilities: .init(tools: .init(listChanged: false))
)
let transport = StdioTransport()
```

Register `ListTools` and `CallTool` handlers before `server.start`. Keep the process alive until stdin closes or it receives SIGINT/SIGTERM, then call `server.stop()`.

Write diagnostics only to stderr. Do not enable sampling, prompts, resources, roots, elicitation, HTTP, or server-initiated model calls.

- [ ] **Step 6: Verify with in-memory and stdio smoke tests**

```bash
swift test --filter MotesMCP
swift build -c release --product motes-agent
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' \
  | .build/release/motes-agent mcp --profile 00000000-0000-0000-0000-000000000001
swift test
git diff --check
```

Expected smoke result: a valid MCP error or initialization response on stdout, with no log contamination.

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
  Sources/MotesAgentBridge/MotesMCPToolRegistry.swift \
  Sources/MotesAgentBridge/MotesMCPServer.swift \
  Sources/MotesAgentBridge/MotesAgentBridge.swift \
  Tests/MotesAgentBridgeTests/MotesMCPToolRegistryTests.swift \
  Tests/MotesAgentBridgeTests/MotesMCPServerTests.swift
git commit -m "feat: expose Motes through MCP"
```

---

### Task 9: Add Sharing, Agent Activity, Setup, and Live Feedback UI

**Files:**
- Create: `Sources/MenuBarNotesApp/AgentActivityView.swift`
- Create: `Sources/MenuBarNotesApp/AgentSettingsView.swift`
- Create: `Sources/MenuBarNotesApp/AgentChangeBanner.swift`
- Create: `Sources/MenuBarNotesApp/AgentBridgeInstaller.swift`
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Modify: `Sources/MenuBarNotesApp/SettingsView.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentPresentationTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentBridgeInstallerTests.swift`

**Interfaces:**
- Consumes: sharing state, profiles, activity, feedback, helper configure command, and existing crisp motion.
- Produces:
  - **Allow Agent Access** note action.
  - visible shared-tab badge.
  - **Options → Agent Activity**.
  - **Settings → Agents**.
  - non-focusing `Integration updated Note · Undo` banner.

- [ ] **Step 1: Write presentation-model tests**

Cover:

- Sharing disabled by default.
- Shared badge label is `Shared with agents`.
- First share explains read/write access.
- Unsharing hides a note from service reads immediately.
- Activity rows expose integration, note, operation, time, patch, and Undo eligibility.
- A local Undo remains available for an active note after it is unshared or the originating profile is revoked.
- Integration activity never shows an unshared note through the bridge.
- Multiple feedback events coalesce the banner count without coalescing records.
- Reduce Motion removes spatial transition.
- Revoked profile cannot appear active.
- Clear Activity requires confirmation.

- [ ] **Step 2: Write installer tests**

Use a fake file system and process runner:

- Copy only a verified bundled `motes-agent`.
- Install stable helper at `Application Support/MenuBarNotes/AgentBridge/bin/motes`.
- Refuse to overwrite a non-Motes file.
- Verify the destination SHA-256 matches the bundled helper and record it in a Motes-owned installation receipt.
- Provision the profile token through helper stdin, never argv.
- Remove only Motes-owned helper paths.
- Produce an absolute helper path for MCP snippets.

- [ ] **Step 3: Run RED**

```bash
swift test --filter AgentPresentation
swift test --filter AgentBridgeInstaller
```

- [ ] **Step 4: Implement helper installation and profile provisioning**

Copy from `Bundle.main.sharedSupportURL/motes-agent` into the stable Application Support path through a staging file and atomic rename. After copying, compare SHA-256 hashes and write an installation receipt containing the destination, hash, installed version, and Motes bundle identifier.

Refuse replacement unless the existing destination matches a prior Motes receipt. To provision a profile, invoke the installed helper directly with `Process`, pass `configure --profile <uuid> --token-stdin`, and send the one-time Base64 token only through stdin. Treat a nonzero exit as failed provisioning and remove the unactivated profile.

- [ ] **Step 5: Implement note sharing UI**

Add **Allow Agent Access** to each note context menu and Options for the selected note. The first enable shows explanatory confirmation; later enables are immediate. Add a small `point.3.connected.trianglepath.dotted`-style badge with an accessibility label.

Agents cannot invoke this action through the command service.

- [ ] **Step 6: Implement Agent Activity**

Show local activity newest first with:

- integration name;
- note title;
- operation description;
- timestamp;
- before/after patch;
- Open Note;
- Copy Details;
- Undo when safe.

Clearing requires destructive confirmation and refreshes visible records while preserving tombstones.

- [ ] **Step 7: Implement Settings → Agents**

Add `.agents = "Agents"` to the existing animated section selector. The content includes:

- command bridge installed state;
- Add Codex, Add Claude Code, Add Kimi, and Generic CLI profile actions;
- active profiles with last connection and Revoke;
- copyable setup snippet;
- link to Agent Activity;
- confirmed Clear Activity;
- explicit-sharing explanation;
- same-user security boundary.

Revoke in the app store first so access stops immediately, then invoke `motes disconnect --profile <uuid>` directly to remove the helper's Keychain credential. If credential cleanup fails, keep the profile revoked and show a non-blocking cleanup error.

- [ ] **Step 8: Implement feedback**

Show a compact banner above the editor without taking keyboard focus. Use the existing 100/160 ms motion policy, a crossfade under Reduce Motion, and call `executeLocalUndo` for the safe Undo action. Do not display note body text.

- [ ] **Step 9: Verify**

```bash
swift test --filter AgentPresentation
swift test --filter AgentBridgeInstaller
swift test
swift build -c release
git diff --check
```

- [ ] **Step 10: Commit**

```bash
git add Sources/MenuBarNotesApp/AgentActivityView.swift \
  Sources/MenuBarNotesApp/AgentSettingsView.swift \
  Sources/MenuBarNotesApp/AgentChangeBanner.swift \
  Sources/MenuBarNotesApp/AgentBridgeInstaller.swift \
  Sources/MenuBarNotesApp/NotesPanel.swift \
  Sources/MenuBarNotesApp/SettingsView.swift \
  Sources/MenuBarNotesApp/AppState.swift \
  Tests/MenuBarNotesAppTests/AgentPresentationTests.swift \
  Tests/MenuBarNotesAppTests/AgentBridgeInstallerTests.swift
git commit -m "feat: add Motes agent controls"
```

---

### Task 10: Package the Helper and Generate Verified Client Setup

**Files:**
- Create: `Scripts/build-motes-app.sh`
- Create: `Sources/MenuBarNotesApp/AgentClientSetup.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentClientSetupTests.swift`
- Modify: `Scripts/validate-macos.sh`
- Modify: `Scripts/check-release-size.sh`

**Interfaces:**
- Consumes: release `Motes`, release `motes-agent`, bundle ID `com.harryjin.motes`, installed helper path, and profile ID.
- Produces:
  - `.build/Motes.app`
  - `Contents/SharedSupport/motes-agent`
  - exact Codex, Claude Code, Kimi, and generic MCP snippets.

- [ ] **Step 1: Write setup generation tests**

Assert exact current formats:

Codex:

```bash
codex mcp add motes -- /absolute/path/to/motes mcp --profile <uuid>
```

Claude Code:

```bash
claude mcp add --scope user motes -- /absolute/path/to/motes mcp --profile <uuid>
```

Kimi `~/.kimi-code/mcp.json` entry:

```json
{
  "mcpServers": {
    "motes": {
      "command": "/absolute/path/to/motes",
      "args": ["mcp", "--profile", "<uuid>"]
    }
  }
}
```

Generic JSON uses the same `command` and `args`. Escape spaces and JSON correctly. Do not include credentials.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AgentClientSetup
```

- [ ] **Step 3: Implement the app-bundle script**

The script:

1. Requires macOS and Xcode.
2. Builds `Motes` and `motes-agent` in release mode.
3. Creates a fresh staging directory with `mktemp -d`.
4. Copies Motes to `Contents/MacOS/Motes`.
5. Copies helper to `Contents/SharedSupport/motes-agent`.
6. Copies the final Info.plist.
7. Sets executable permissions.
8. Moves the staged bundle atomically to `.build/Motes.app`.
9. Performs no signing or notarization.

- [ ] **Step 4: Extend validation**

`validate-macos.sh` runs all tests, builds both products, builds the app bundle, verifies bundle identifiers and helper presence, and launches only the app binary for a bounded smoke test.

The release-size script reports app executable and helper sizes separately. The existing 15 MB Motes executable budget remains; do not silently include the optional dictation model.

- [ ] **Step 5: Verify current external client commands**

Before committing, recheck the official Codex, Claude Code, and Kimi MCP documentation because client syntax can drift. Update only setup generation and its tests if an official current command changed; do not change Motes' MCP contract.

- [ ] **Step 6: Verify**

```bash
swift test --filter AgentClientSetup
Scripts/build-motes-app.sh
Scripts/validate-macos.sh
git diff --check
```

- [ ] **Step 7: Commit**

```bash
git add Scripts/build-motes-app.sh \
  Sources/MenuBarNotesApp/AgentClientSetup.swift \
  Tests/MenuBarNotesAppTests/AgentClientSetupTests.swift \
  Scripts/validate-macos.sh \
  Scripts/check-release-size.sh
git commit -m "build: package the Motes agent bridge"
```

---

### Task 11: Complete Security, Compatibility, Documentation, and Release Gates

**Files:**
- Modify: `README.md`
- Modify: `ARCHITECTURE.md`
- Modify: `IMPLEMENTATION_STATUS.md`
- Modify: `TESTING.md`
- Modify: `.github/workflows/ci.yml`
- Create: `Scripts/audit-agent-boundary.sh`
- Create: `Tests/MenuBarNotesAppTests/AgentPrivacyBoundaryTests.swift`

**Interfaces:**
- Consumes: all Tasks 0–10.
- Produces: release evidence and accurate user/developer documentation.

- [ ] **Step 1: Add privacy boundary tests**

Use UUID probing and malformed requests to prove:

- private notes cannot be listed or read;
- unknown and private note UUID probes return byte-for-byte equivalent safe failures;
- unshared prior activity cannot be read through an integration;
- Trash and Dictation History identifiers are rejected;
- settings and sharing commands do not exist;
- note deletion does not exist;
- arbitrary paths cannot enter a command;
- helper credentials are absent from output and persisted JSON;
- MCP has tools only, with no resources, roots, prompts, sampling, or elicitation.

- [ ] **Step 2: Add the static boundary audit**

The script fails if:

- `MotesAgentBridge` imports `AppKit` except in the launch adapter;
- the helper opens an HTTP/TCP listener;
- helper code references note `.md`, `.rtf`, `workspace.json`, Trash, or Dictation History paths;
- MCP handlers expose a tool outside the approved twelve;
- production logs write to stdout in MCP mode;
- credentials appear in generated snippets.

Use targeted `rg` patterns with comments documenting each forbidden boundary.

- [ ] **Step 3: Update documentation**

Document:

- explicit per-note sharing;
- MCP and CLI setup;
- tool list and examples;
- revision conflicts and retry IDs;
- 30-day activity and safe Undo;
- local IPC and same-user threat boundary;
- private-note, Trash, settings, and shell exclusions;
- helper installation/removal;
- no cloud service or internet-facing port.

Correct the stale README planning-stage claim while preserving unrelated roadmap truth.

- [ ] **Step 4: Extend CI**

CI runs:

```bash
swift test
swift build -c release --product Motes
swift build -c release --product motes-agent
Scripts/audit-agent-boundary.sh
Scripts/check-release-size.sh .build/release/Motes
```

Keep native bundle launch and Keychain validation in the macOS job.

- [ ] **Step 5: Run automated release evidence**

```bash
swift test
swift build
swift build -c release
Scripts/audit-agent-boundary.sh
Scripts/validate-macos.sh
git diff --check
```

Record exact test count, Motes executable size, helper size, and SDK revision in the implementation report.

- [ ] **Step 6: Run manual client validation**

With a temporary shared test note and separate profiles:

1. Connect Codex and verify list/read/add/complete/conflict/Undo.
2. Connect Claude Code and repeat.
3. Connect Kimi and repeat.
4. Use generic CLI JSON mode and repeat.
5. Revoke each profile during an idle session and during a request.
6. Unshare the note and verify immediate denial.
7. Quit Motes, call the helper, and verify non-activating launch.
8. Type in the note while an agent holds a stale revision and verify rejection.
9. Relaunch after a prepared-transaction interruption and verify reconciliation without duplication.
10. Verify VoiceOver labels, keyboard order, Reduce Motion, multiple Motes windows, sleep/wake, and no idle CPU activity from the bridge.

- [ ] **Step 7: Final review**

Request focused reviews for:

- authorization and same-user IPC;
- transaction durability and idempotency;
- rich-text preservation and Undo;
- MCP schema and privacy surface;
- packaging and removal safety;
- UI accessibility.

Resolve every Critical or Important finding and rerun Step 5.

- [ ] **Step 8: Commit**

```bash
git add README.md ARCHITECTURE.md IMPLEMENTATION_STATUS.md TESTING.md \
  .github/workflows/ci.yml \
  Scripts/audit-agent-boundary.sh \
  Tests/MenuBarNotesAppTests/AgentPrivacyBoundaryTests.swift
git commit -m "docs: validate Motes agent integration"
```

## Final Integration Gate

Before merging:

```bash
git status --short
git log --oneline --decorate --max-count=20
swift test
Scripts/validate-macos.sh
Scripts/audit-agent-boundary.sh
git diff --check
```

Confirm:

- Clean Dictation and Agent Workspace tests pass together.
- The working tree is clean.
- Motes remains below its existing executable-size budget.
- The helper is packaged separately.
- No private note or excluded surface is reachable through UUID probing.
- No direct file-edit fallback exists.
- Retry behavior is idempotent for the 30-day tombstone boundary.
- Manual Codex, Claude Code, Kimi, and generic CLI checks are recorded.
- Physical release signing, notarization, and distribution validation remain explicitly separate if not performed.

## Reference Sources to Reverify at Execution

- Official MCP Swift SDK: `https://github.com/modelcontextprotocol/swift-sdk`
- MCP SDK tag: `https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1`
- Codex MCP setup: `https://developers.openai.com/codex/mcp`
- Claude Code MCP setup: `https://docs.anthropic.com/en/docs/claude-code/mcp`
- Kimi Code MCP setup: `https://www.kimi.com/code/docs/en/kimi-code-cli/customization/mcp.html`
