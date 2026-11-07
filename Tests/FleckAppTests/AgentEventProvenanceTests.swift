import FleckCore
import Foundation
import Testing

@testable import FleckApp

private enum AgentEventProvenanceTestFailure: Error {
  case invalidJSON
}

private struct ProvenanceProfileAuthorizer: AgentProfileAuthorizing {
  let profile: AgentIntegrationProfile

  func authorize(
    profileID: UUID,
    credential: Data
  ) async throws -> AgentIntegrationProfile {
    profile
  }
}

private struct ProvenanceCapabilityAuthorizer: AgentCapabilityAuthorizing {
  let value: AgentAuthorizationSnapshot

  func snapshot(
    profileID: UUID,
    workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot {
    value
  }

  func assertCurrent(profileID: UUID, grantRevision: UInt64) async throws {}
}

@MainActor
private final class ProvenanceWorkspaceState: AgentWorkspaceStateAccess {
  var workspace: Workspace
  var persistenceGeneration: UInt64 = 1
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
    guard persistenceGeneration == expectedGeneration else {
      throw AgentWorkspaceError(code: .revisionConflict)
    }
    self.workspace = workspace
    persistenceGeneration += 1
    agentCommitProofs.append(commitProof)
  }

  func publishAgentFeedback(_ feedback: AgentChangeFeedback) {}

  func publishAgentRequestEvent(_ event: AgentRequestEvent) {}
}

private struct SyntheticAgentSigningKeyProvider: AgentSigningKeyProviding {
  func signingKey() throws -> Data {
    Data(repeating: 7, count: 32)
  }
}

private func object(from data: Data) throws -> [String: Any] {
  guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw AgentEventProvenanceTestFailure.invalidJSON
  }
  return value
}

@Test @MainActor func localUndoCommitProofRetainsItsIntegrationOrigin() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentEventProvenanceTests-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let profile = AgentIntegrationProfile(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
    displayName: "Synthetic profile",
    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let note = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
    title: "Work",
    body: "Original",
    agentAccess: true,
    revision: 3
  )
  let state = ProvenanceWorkspaceState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id)
  )
  let activityStore = AgentActivityStore(
    rootURL: root,
    now: { Date(timeIntervalSince1970: 1_800_000_000) }
  )
  let authorization = AgentAuthorizationSnapshot(
    profileID: profile.id,
    grantRevision: 1,
    availableCapabilities: [.writeNotes, .undoChanges],
    readableNoteIDs: [note.id],
    proposableNoteIDs: [],
    writableNoteIDs: [note.id]
  )
  let service = AgentCommandService(
    state: state,
    profileStore: ProvenanceProfileAuthorizer(profile: profile),
    activityStore: activityStore,
    capabilityAuthority: ProvenanceCapabilityAuthorizer(value: authorization),
    taskHandleCodec: AgentTaskHandleCodec(
      signingKeyProvider: SyntheticAgentSigningKeyProvider()
    ),
    now: { Date(timeIntervalSince1970: 1_800_000_000) }
  )
  let write = try await service.execute(
    profileID: profile.id,
    credential: Data("synthetic-only".utf8),
    command: .appendText(
      request: .init(
        context: .init(
          noteID: note.id,
          expectedRevision: note.revision,
          operationID: UUID()
        ),
        text: " agent change"
      )
    )
  )
  guard case .write(let receipt) = write else {
    Issue.record("Expected an integration write receipt")
    return
  }
  #expect(state.agentCommitProofs.count == 1)

  _ = try await service.executeLocalUndo(
    changeID: receipt.changeID,
    expectedRevision: receipt.resultingRevision,
    operationID: UUID()
  )
  #expect(state.agentCommitProofs.count == 2)

  let encoded = try JSONEncoder().encode(state.agentCommitProofs[1])
  let proof = try object(from: encoded)
  let originatingActor = try #require(proof["originatingActor"] as? [String: Any])
  let integration = try #require(originatingActor["integration"] as? [String: Any])
  #expect(
    (integration["profileID"] as? String).flatMap(UUID.init(uuidString:)) == profile.id
  )
  #expect(integration["displayName"] as? String == profile.displayName)
}

@Test func legacyCommitProofWithoutOriginatingActorStillDecodes() throws {
  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
    noteID: UUID(uuidString: "00000000-0000-0000-0000-000000000052")!,
    resultingRevision: 4,
    bodySHA256: String(repeating: "a", count: 64),
    actor: .localUser,
    operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000053")!,
    expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
  )
  var legacyObject = try object(from: JSONEncoder().encode(proof))
  legacyObject.removeValue(forKey: "originatingActor")
  let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])

  let decoded = try JSONDecoder().decode(AgentWorkspaceCommitProof.self, from: legacyData)
  let reencoded = try object(from: JSONEncoder().encode(decoded))
  #expect(reencoded["originatingActor"] == nil)
}
