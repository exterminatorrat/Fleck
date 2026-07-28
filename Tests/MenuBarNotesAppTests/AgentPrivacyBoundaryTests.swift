import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Suite("Agent privacy boundary")
struct AgentPrivacyBoundaryTests {
  @Test @MainActor
  func privateUnknownTrashAndHistoryIDsShareTheSameSafeFailure() async throws {
    let shared = Note(title: "Shared", body: "Visible", agentAccess: true)
    let privateNote = Note(title: "Private", body: "Secret", agentAccess: false)
    let fixture = AgentPrivacyFixture(notes: [shared, privateNote])
    let excludedIDs = [privateNote.id, UUID(), UUID(), UUID()]
    var failures: [Data] = []

    let listed = try await fixture.execute(.listSharedNotes)
    #expect(
      listed
        == .sharedNotes(
          notes: [
            AgentNoteSummary(
              noteID: shared.id,
              title: shared.displayTitle,
              revision: shared.revision,
              modifiedAt: shared.modifiedAt
            )
          ])
    )

    for noteID in excludedIDs {
      do {
        _ = try await fixture.execute(
          .readNote(request: .init(noteID: noteID))
        )
        Issue.record("Expected note_not_found")
      } catch let error as AgentWorkspaceError {
        failures.append(try JSONEncoder().encode(error))
      }
    }

    #expect(failures.count == excludedIDs.count)
    #expect(Set(failures).count == 1)
    #expect(
      try JSONDecoder().decode(
        AgentWorkspaceError.self,
        from: failures[0]
      ).code == .noteNotFound
    )
  }

  @Test @MainActor
  func activityForAnUnsharedNoteIsNotVisibleToTheIntegration() async throws {
    var note = Note(title: "Later private", body: "Before", agentAccess: true)
    let fixture = AgentPrivacyFixture(notes: [note])
    let changeID = UUID()
    fixture.activity.records = [
      AgentActivityRecord(
        transaction: PreparedAgentTransaction(
          changeID: changeID,
          noteID: note.id,
          noteTitle: note.displayTitle,
          actor: .integration(
            profileID: fixture.profile.id,
            displayName: fixture.profile.displayName
          ),
          operationID: UUID(),
          createdAt: Date(),
          operation: .appendText,
          patch: AgentTextPatch(
            beforeText: "",
            afterText: "After",
            range: NSRange(location: 0, length: 0),
            prefixContext: "",
            suffixContext: ""
          ),
          previousRevision: 0,
          resultingRevision: 1,
          resultingBodySHA256: String(repeating: "0", count: 64)
        ),
        receipt: AgentWriteReceipt(
          changeID: changeID,
          noteID: note.id,
          previousRevision: 0,
          resultingRevision: 1
        )
      )
    ]
    note.agentAccess = false
    fixture.state.workspace.notes = [note]

    let response = try await fixture.execute(.listActivity)

    #expect(response == .activity(entries: []))
    #expect(fixture.activity.lastVisibleNoteIDs == [])
  }

  @Test
  func closedWireCommandRejectsSettingsSharingDeletionAndPathPayloads() {
    let forbiddenCommands = [
      "readPath", "deleteNote", "setNoteSharing", "updateSettings",
      "listTrash", "readDictationHistory",
    ]

    for command in forbiddenCommands {
      let payload = Data(#"{"\#(command)":{"request":{"path":"/tmp/private"}}}"#.utf8)
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(AgentWorkspaceCommand.self, from: payload)
      }
    }
  }

  @Test
  func credentialsAreAbsentFromSetupOutputAndPersistedProfileJSON() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AgentPrivacyBoundaryTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let profilesURL = root.appendingPathComponent("profiles.json")
    let credential = Data(repeating: 0xA5, count: 32)
    let store = AgentProfileStore(
      profilesURL: profilesURL,
      secretStore: PrivacySecretStore(),
      randomBytes: PrivacyRandomBytes(value: credential)
    )

    let provisioning = try await store.create(name: "Codex")
    let setup = AgentClientSetup(
      installedHelperURL: URL(fileURLWithPath: "/Applications/Motes Helper/motes"),
      profileID: provisioning.profile.id
    )
    let persisted = String(
      decoding: try Data(contentsOf: profilesURL),
      as: UTF8.self
    )
    let secretForms = [
      credential.base64EncodedString(),
      AgentCredentialSecurity.sha256(credential).base64EncodedString(),
    ]

    for output in [
      setup.codexCommand,
      setup.claudeCodeCommand,
      setup.kimiConfiguration,
      setup.genericConfiguration,
      persisted,
    ] {
      for secret in secretForms {
        #expect(!output.contains(secret))
      }
      #expect(!output.localizedCaseInsensitiveContains("credential"))
      #expect(!output.localizedCaseInsensitiveContains("token"))
    }
  }
}

@MainActor
private final class AgentPrivacyFixture {
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Privacy test",
    createdAt: Date(),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let state: PrivacyWorkspaceState
  let activity = PrivacyActivityStore()
  let service: AgentCommandService

  init(notes: [Note]) {
    state = PrivacyWorkspaceState(
      workspace: Workspace(notes: notes, selectedNoteID: notes.first?.id)
    )
    service = AgentCommandService(
      state: state,
      profileStore: PrivacyAuthorizer(profile: profile),
      activityStore: activity
    )
  }

  func execute(
    _ command: AgentWorkspaceCommand
  ) async throws -> AgentWorkspaceResponse {
    try await service.execute(
      profileID: profile.id,
      credential: Data(repeating: 7, count: 32),
      command: command
    )
  }
}

@MainActor
private final class PrivacyWorkspaceState: AgentWorkspaceStateAccess {
  var workspace: Workspace
  var persistenceGeneration: UInt64 = 0
  var preferences = AppPreferences()
  var isAgentWorkspaceAvailable = true
  var agentCommitProofs: [AgentWorkspaceCommitProof] = []

  init(workspace: Workspace) {
    self.workspace = workspace
  }

  func flushPendingPersistenceForAgent() async throws {}

  func commitAgentWorkspace(
    _ workspace: Workspace,
    expectedGeneration: UInt64,
    commitProof: AgentWorkspaceCommitProof
  ) throws {
    self.workspace = workspace
    persistenceGeneration += 1
    agentCommitProofs.append(commitProof)
  }

  func publishAgentFeedback(_ feedback: AgentChangeFeedback) {}
}

private actor PrivacyAuthorizer: AgentProfileAuthorizing {
  let profile: AgentIntegrationProfile

  init(profile: AgentIntegrationProfile) {
    self.profile = profile
  }

  func authorize(
    profileID: UUID,
    credential: Data
  ) async throws -> AgentIntegrationProfile {
    profile
  }
}

private final class PrivacyActivityStore:
  AgentActivityPersisting, @unchecked Sendable
{
  var records: [AgentActivityRecord] = []
  private(set) var lastVisibleNoteIDs: Set<UUID> = []

  func prepare(_ transaction: PreparedAgentTransaction) throws {}
  func commit(changeID: UUID, receipt: AgentWriteReceipt) throws {}
  func abort(changeID: UUID) throws {}

  func priorReceipt(
    actor: AgentActivityActor,
    operationID: UUID
  ) -> AgentWriteReceipt? {
    nil
  }

  func list(
    profileID: UUID?,
    visibleNoteIDs: Set<UUID>
  ) -> [AgentActivityRecord] {
    lastVisibleNoteIDs = visibleNoteIDs
    return records.filter {
      visibleNoteIDs.contains($0.noteID)
        && $0.actor == .integration(
          profileID: profileID ?? UUID(),
          displayName: "Privacy test"
        )
    }
  }

  func record(id: UUID) -> AgentActivityRecord? {
    records.first { $0.changeID == id }
  }

  func reconcile(
    workspace: Workspace,
    commitProofs: [AgentWorkspaceCommitProof]
  ) throws {}
}

private final class PrivacySecretStore: AgentSecretStoring, @unchecked Sendable {
  private var values: [String: Data] = [:]

  func read(service: String, account: String) throws -> Data? {
    values["\(service):\(account)"]
  }

  func write(_ data: Data, service: String, account: String) throws {
    values["\(service):\(account)"] = data
  }

  func delete(service: String, account: String) throws {
    values.removeValue(forKey: "\(service):\(account)")
  }
}

private struct PrivacyRandomBytes: AgentRandomBytesProviding {
  let value: Data

  func randomBytes(count: Int) throws -> Data {
    value
  }
}
