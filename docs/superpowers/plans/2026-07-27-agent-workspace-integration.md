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
git merge-base --is-ancestor 2d20753 HEAD
test -f Sources/MenuBarNotesApp/NoteTextAppender.swift
test -f Sources/MenuBarNotesApp/DictationCoordinator.swift
rg -n "saveSmartCapture|Dictation History|case dictation" Sources/MenuBarNotesApp
swift test
```

Expected:

- The Agent Workspace specification commit is reachable.
- Clean Dictation's editor append, coordinator, AppState saving, settings, and history integration are present.
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
  - `Workspace.updateRichText(id:rtf:now:)`
  - exactly one revision increment for each actual title, body, RTF, or sharing mutation.

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
  workspace.updateNote(id: id, body: "A")
  #expect(workspace.notes[0].revision == 1)
  workspace.updateNote(id: id, body: "A")
  #expect(workspace.notes[0].revision == 1)
  workspace.setAgentAccess(id: id, enabled: true)
  #expect(workspace.notes[0].revision == 2)
}
```

Add store round-trip coverage for `agentAccess` and `revision`, plus an old manifest fixture without either key.

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

In `Workspace`, update title/body only when the supplied value differs and increment once if either changes. Add:

```swift
public mutating func updateRichText(
  id: UUID,
  rtf: Data?,
  now: Date = Date()
)

public mutating func setAgentAccess(
  id: UUID,
  enabled: Bool,
  now: Date = Date()
)
```

Both no-op when the value is unchanged. Both update `modifiedAt` and increment revision exactly once when changed. Replace AppState's direct RTF assignment with `updateRichText`.

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

Use associated-value Codable commands with explicit nested request structs. Define response cases for note summaries, a paged note body, task summaries, a write receipt, activity summaries, and Undo.

Define the error vocabulary exactly:

```swift
public enum AgentWorkspaceErrorCode: String, Codable, Sendable {
  case noteNotFound = "note_not_found"
  case noteNotShared = "note_not_shared"
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
- Consumes: `AgentTextPatch`, operation ID, integration profile ID, note revisions, and note body hashes.
- Produces:

```swift
public actor AgentActivityStore {
  public init(rootURL: URL, now: @escaping @Sendable () -> Date = Date.init)
  public func prepare(_ transaction: PreparedAgentTransaction) throws
  public func commit(changeID: UUID, receipt: AgentWriteReceipt) throws
  public func abort(changeID: UUID) throws
  public func priorReceipt(profileID: UUID, operationID: UUID) -> AgentWriteReceipt?
  public func list(profileID: UUID?, visibleNoteIDs: Set<UUID>) -> [AgentActivityRecord]
  public func record(id: UUID) -> AgentActivityRecord?
  public func clearVisibleActivity() throws
  public func reconcile(workspace: Workspace) throws
}
```

- [ ] **Step 1: Write lifecycle tests**

Cover:

- Atomic prepared record.
- Commit moves the visible record and writes a tombstone.
- Duplicate `(profileID, operationID)` returns the original response.
- A prepared record whose resulting revision/body hash exists is finalized on reconciliation.
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

A prepared transaction includes resulting note revision and SHA-256 body hash. Reconciliation finalizes only when both match the loaded workspace; otherwise it removes the preparation without creating an activity record.

Visible patches expire at `createdAt + 30 days`. Tombstones retain only profile ID, operation ID, the content-free `AgentWriteReceipt` containing change ID and resulting revision, and original expiry. They never retain body text or patches.

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
- Creation returns a 32-byte random credential once and stores only SHA-256.
- Equal credentials authorize with constant-time comparison.
- Wrong, revoked, and unknown profiles fail with scoped errors.
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

Store credential SHA-256, not the credential. Use an injected random-byte generator in tests and `SecRandomCopyBytes` in production.

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

### Task 5: Implement Rich-Text-Safe Mutations and the Single-Writer Gateway

**Files:**
- Create: `Sources/MenuBarNotesApp/AgentRichTextMutator.swift`
- Create: `Sources/MenuBarNotesApp/AgentCommandService.swift`
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
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
    profile: AgentIntegrationProfile,
    command: AgentWorkspaceCommand
  ) async -> AgentWorkspaceResponse
}

@MainActor
protocol AgentWorkspaceStateAccess: AnyObject {
  var workspace: Workspace { get set }
  var preferences: AppPreferences { get }
  func persistAgentWorkspace(_ workspace: Workspace) async throws
}
```

- [ ] **Step 1: Write rich-text preservation tests**

Cover:

- Append reuses `NoteTextAppender` and preserves existing font/underline runs.
- Line insertion preserves all attributed runs outside the insertion.
- Replacement applies current editor defaults only to new text.
- Completing a task strikes through task content but not indentation or marker.
- Reopening removes only the task-content strike.
- Removing one task preserves adjacent rich text.

- [ ] **Step 2: Write service contract tests**

Cover:

- Discovery returns shared notes only.
- Direct probing of an unshared UUID returns `note_not_shared`, not content or metadata.
- Every write rejects a stale revision before mutation.
- A duplicate operation ID returns the stored receipt.
- Successful persistence publishes one new workspace revision and activity record.
- Save failure publishes no in-memory mutation and aborts preparation.
- Crash-style prepared reconciliation finalizes correctly after reload.
- List activity exposes only the caller's records for currently shared notes.
- Agent Undo creates a new attributed activity record.
- Later ambiguous edits return `unsafe_undo`.
- Human pending edits are part of the revision checked by an agent command.

- [ ] **Step 3: Run RED**

```bash
swift test --filter AgentRichTextMutator
swift test --filter AgentCommandService
```

- [ ] **Step 4: Implement attributed mutations**

Decode existing RTF when valid; otherwise create attributed text from `note.body` and current font preferences. Map body line ranges to `NSRange` using `NSString`. Apply the exact pure-engine replacement, serialize RTF, and return body plus RTF together.

Construct the resulting `Note` with body and RTF updated together, then increment its revision exactly once. Do not call the separate human body and RTF mutation methods in sequence.

Do not route mutations through the visible `NSTextView`; visible editors update from the published note state after durable commit.

- [ ] **Step 5: Implement transaction ordering**

For a write:

1. Authorize profile and scope.
2. Return a prior idempotent result when present.
3. Validate expected revision.
4. Produce body, RTF, patch, and resulting revision on a workspace copy.
5. Write a prepared activity transaction.
6. Persist the workspace copy with current preferences and pending Trash.
7. Commit the activity record/tombstone.
8. Publish the workspace copy and feedback.
9. Return the receipt.

On failure before step 6, abort preparation. On failure after step 6, leave preparation for startup reconciliation and return `internal_save_failure`; retrying the same operation ID must reconcile rather than duplicate.

- [ ] **Step 6: Integrate AppState**

Make `AppState` conform to `AgentWorkspaceStateAccess`. `persistAgentWorkspace` cancels the debounced save, includes current pending Trash, awaits the store, and does not mutate published state itself.

Add:

```swift
@Published private(set) var latestAgentFeedback: AgentChangeFeedback?
@Published private(set) var agentProfiles: [AgentIntegrationProfile] = []
```

Human sharing changes use `setAgentAccess`, save immediately, and do not create Agent Activity.

- [ ] **Step 7: Verify**

```bash
swift test --filter AgentRichTextMutator
swift test --filter AgentCommandService
swift test
git diff --check
```

- [ ] **Step 8: Commit**

```bash
git add Sources/MenuBarNotesApp/AgentRichTextMutator.swift \
  Sources/MenuBarNotesApp/AgentCommandService.swift \
  Sources/MenuBarNotesApp/AppState.swift \
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
- Create: `Sources/MenuBarNotesApp/AgentIPCServer.swift`
- Modify: `Sources/MenuBarNotesApp/MenuBarNotesApp.swift`
- Create: `Tests/MenuBarNotesAgentProtocolTests/AgentWireProtocolTests.swift`
- Create: `Tests/MenuBarNotesAppTests/AgentIPCServerTests.swift`

**Interfaces:**
- Consumes: `AgentWorkspaceCommand`, `AgentWorkspaceResponse`, profile authorization, and `AgentCommandService`.
- Produces:

```swift
public struct AgentWireRequest: Codable, Equatable, Sendable {
  public let requestID: UUID
  public let profileID: UUID
  public let credentialBase64: String
  public let command: AgentWorkspaceCommand
}

public struct AgentWireResponse: Codable, Equatable, Sendable {
  public let requestID: UUID
  public let result: AgentWorkspaceResponse?
  public let error: AgentWorkspaceFailure?
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

Test fragmented frames, coalesced frames, zero length, a frame above 1 MiB, malformed JSON, and request/response correlation.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AgentWireProtocol
swift test --filter AgentIPCServer
```

- [ ] **Step 3: Implement four-byte framing**

Prefix each JSON payload with an unsigned four-byte big-endian length. Reject zero-length and lengths above 1,048,576 before allocating the payload buffer. Encode dates as ISO-8601.

- [ ] **Step 4: Implement the server**

Create the socket at:

```text
Application Support/MenuBarNotes/AgentBridge/motes.sock
```

Requirements:

- Parent directory mode `0700`.
- Remove an existing path only when `lstat` proves it is a socket owned by the current user.
- Socket mode `0600`.
- Use `getpeereid` to reject a peer UID different from `geteuid()`.
- Bound accepted clients and close idle connections.
- Decode one request at a time per connection.
- Authenticate the profile before invoking the main-actor service.
- Never include internal paths or credentials in errors.
- Remove the socket on clean shutdown.

- [ ] **Step 5: Start one server from the app root**

Construct `AgentIPCServer` once beside the final post-dictation runtime. Start it after `AppState` finishes loading; stop it on runtime deinitialization or application termination. Starting a second Motes window must not create another listener.

- [ ] **Step 6: Verify**

```bash
swift test --filter AgentWireProtocol
swift test --filter AgentIPCServer
swift test
git diff --check
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
  Sources/MenuBarNotesAgentProtocol/AgentWireProtocol.swift \
  Sources/MenuBarNotesAgentProtocol/AgentWireFraming.swift \
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
- Partial frames and response request-ID mismatch fail.
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

Use the exact socket and framing rules from Task 6. CLI output defaults to concise human text; `--json` encodes `AgentWorkspaceResponse`.

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

Show a compact banner above the editor without taking keyboard focus. Use the existing 100/160 ms motion policy, a crossfade under Reduce Motion, and a safe Undo action. Do not display note body text.

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
